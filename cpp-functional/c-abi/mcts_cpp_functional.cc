// Backend (iii) C ABI: shim over the functional-style engine under
// `cpp-functional/engine/`. The engine is the arena-MCTS *with
// functional-style API surface* (per Sprint 6.1):
// `std::optional<State>` move attempts, `std::variant<ChildIdx,
// NoChild>` select outcomes, immutable `State` value semantics at the
// API boundary. The data layout (arena, flat children, thread_local
// move buffer) intentionally matches backend (ii) so the (ii)-vs-(iii)
// comparison isolates style as the variable.

#include "mcts_cpp_functional.h"

#include "../engine/board.h"
#include "../engine/search.hpp"
#include "../engine/state.hpp"

#include <algorithm>
#include <cfenv>
#if defined(__x86_64__) || defined(__i386__)
#include <cpuid.h>
#endif
#include <cstring>
#include <limits>
#include <utility>
#include <vector>

#ifndef MCTS_GIT_COMMIT
#define MCTS_GIT_COMMIT "0000000000000000000000000000000000000000"
#endif

struct mcts_functional_board {
    mcts_functional::State state{};
    std::vector<std::pair<uint8_t, uint32_t>> last_visits{};
    uint8_t last_chosen = 0;
};

namespace {

constexpr uint16_t kDefaultMaxPlies = 10000;

[[gnu::hot]] static int apply_action_id(mcts_functional::State &state, uint8_t action_id) {
    std::vector<corridors::board> moves;
    state.b.get_legal_moves(moves);
    for (auto &m : moves) {
        std::string action = m.get_action_text(false);
        if (action.size() < 5) continue;
        const bool pawn = action[0] == '*';
        const bool horizontal = action[0] == 'H';
        const bool vertical = action[0] == 'V';
        const size_t open = action.find('(');
        const size_t comma = action.find(',');
        const size_t close = action.find(')');
        if (open == std::string::npos || comma == std::string::npos || close == std::string::npos) continue;
        const int x = std::stoi(action.substr(open + 1, comma - open - 1));
        const int y = std::stoi(action.substr(comma + 1, close - comma - 1));
        uint8_t aid = 0;
        if (pawn) aid = static_cast<uint8_t>(y * 9 + x);
        else if (horizontal) aid = static_cast<uint8_t>(81 + y * 8 + x);
        else if (vertical) aid = static_cast<uint8_t>(145 + y * 8 + x);
        if (aid == action_id) {
            state.b = std::move(m);
            state.ply_count = static_cast<uint16_t>(state.ply_count + 1);
            return 0;
        }
    }
    return -1;
}

}  // namespace

extern "C" mcts_functional_board *mcts_functional_new_board(void) {
    return new (std::nothrow) mcts_functional_board{};
}

extern "C" void mcts_functional_free_board(mcts_functional_board *board) {
    delete board;
}

extern "C" int mcts_functional_is_terminal(const mcts_functional_board *board) {
    if (!board) return 1;
    return board->state.is_terminal(kDefaultMaxPlies) ? 1 : 0;
}

extern "C" uint8_t mcts_functional_select_uct_move(mcts_functional_board *board,
                                                   uint64_t seed, uint32_t sims) {
    if (!board || board->state.is_terminal(kDefaultMaxPlies)) return 0;
    try {
        auto result = mcts_functional::run_search(
            board->state,
            sims,
            kDefaultMaxPlies,
            mcts_functional::RngBackend::Mt19937,
            seed);
        if (!result.ok) return 0;
        if (apply_action_id(board->state, result.chosen_action_id) != 0) return 0;
        return result.chosen_action_id;
    } catch (...) {
        return 0;
    }
}

extern "C" int32_t mcts_functional_search_move(
    mcts_functional_board *board, uint64_t seed, uint32_t sims,
    uint8_t *out_action_ids, uint32_t *out_visits, uint8_t *out_chosen) {
    if (!board || !out_action_ids || !out_visits || !out_chosen) return -1;
    if (board->state.is_terminal(kDefaultMaxPlies)) return -1;
    try {
        auto result = mcts_functional::run_search(
            board->state,
            sims,
            kDefaultMaxPlies,
            mcts_functional::RngBackend::Mt19937,
            seed);
        if (!result.ok) return -1;
        if (apply_action_id(board->state, result.chosen_action_id) != 0) return -1;
        const int32_t count = static_cast<int32_t>(result.visits.size());
        board->last_visits = result.visits;
        board->last_chosen = result.chosen_action_id;
        for (int32_t i = 0; i < count; ++i) {
            out_action_ids[i] = result.visits[i].first;
            out_visits[i] = result.visits[i].second;
        }
        *out_chosen = result.chosen_action_id;
        return count;
    } catch (...) {
        return -1;
    }
}

extern "C" int32_t mcts_functional_recompute_move(
    mcts_functional_board *board, uint64_t seed, uint32_t sims,
    uint8_t *out_action_ids, uint32_t *out_visits, uint8_t *out_chosen,
    double *out_equity) {
    if (!out_equity) return -1;
    *out_equity = std::numeric_limits<double>::quiet_NaN();
    return mcts_functional_search_move(board, seed, sims, out_action_ids, out_visits, out_chosen);
}

static mcts_functional_envelope g_envelope;
static int g_envelope_ready = 0;

__attribute__((section(".envelope_build_id")))
static uint8_t g_engine_build_id[32] = {0};

static uint32_t probe_cpu_features(void) {
    uint32_t bits = 0;
#if defined(__x86_64__) || defined(__i386__)
    unsigned int eax = 0, ebx = 0, ecx = 0, edx = 0;
    if (__get_cpuid(1, &eax, &ebx, &ecx, &edx)) {
        if (edx & (1u << 23)) bits |= 0x1u;
        if (edx & (1u << 25)) bits |= 0x2u;
        if (edx & (1u << 26)) bits |= 0x4u;
        if (ecx & (1u << 0)) bits |= 0x8u;
        if (ecx & (1u << 9)) bits |= 0x10u;
        if (ecx & (1u << 19)) bits |= 0x20u;
        if (ecx & (1u << 20)) bits |= 0x40u;
        if (ecx & (1u << 28)) bits |= 0x80u;
        if (ecx & (1u << 12)) bits |= 0x100u;
    }
    if (__get_cpuid_count(7, 0, &eax, &ebx, &ecx, &edx)) {
        if (ebx & (1u << 5)) bits |= 0x200u;
        if (ebx & (1u << 16)) bits |= 0x400u;
        if (ebx & (1u << 29)) bits |= 0x800u;
    }
#elif defined(__aarch64__)
    bits |= 0x10000u;
    bits |= 0x20000u;
#endif
    return bits;
}

static uint8_t probe_fp_env(void) {
    uint8_t value = 0;
    int rounding = std::fegetround();
    switch (rounding) {
        case FE_TONEAREST: value |= 0x0u; break;
        case FE_DOWNWARD: value |= 0x1u; break;
        case FE_UPWARD: value |= 0x2u; break;
        case FE_TOWARDZERO: value |= 0x3u; break;
        default: value |= 0x3u; break;
    }
#if defined(__x86_64__)
    unsigned int mxcsr;
    __asm__ __volatile__("stmxcsr %0" : "=m"(mxcsr));
    if (mxcsr & (1u << 15)) value |= 0x10u;
    if (mxcsr & (1u << 6)) value |= 0x20u;
#endif
    return value;
}

static void fill_envelope_once(void) {
    if (g_envelope_ready) return;
    std::memset(&g_envelope, 0, sizeof(g_envelope));
    g_envelope.envelope_version = 1;
    g_envelope.rng_source_envelope = 1;
#if defined(__aarch64__)
    g_envelope.host_arch_envelope = 1;
#else
    g_envelope.host_arch_envelope = 0;
#endif
#if defined(__clang__)
    g_envelope.compiler_id = 1;
#else
    g_envelope.compiler_id = 0;
#endif
    const char *commit = MCTS_GIT_COMMIT;
    size_t commit_len = std::strlen(commit);
    if (commit_len > sizeof(g_envelope.engine_git_commit))
        commit_len = sizeof(g_envelope.engine_git_commit);
    std::memcpy(g_envelope.engine_git_commit, commit, commit_len);
    std::memcpy(g_envelope.engine_build_id, g_engine_build_id, 32);
    g_envelope.cpu_features = probe_cpu_features();
    g_envelope.fp_env = probe_fp_env();
    g_envelope_ready = 1;
}

extern "C" const mcts_functional_envelope *mcts_functional_get_envelope(void) {
    fill_envelope_once();
    return &g_envelope;
}
