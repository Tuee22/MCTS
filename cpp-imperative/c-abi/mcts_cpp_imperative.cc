// Backend (ii) C ABI: thin shim over the imperative-steelman engine
// under `cpp-imperative/engine/`. The engine is the doctrine-character
// arena-allocated MCTS per Sprint 5.1 — flat children, `Word16` ply
// counter + ply-cap terminal, thread_local move-list buffer,
// `__builtin_prefetch` on the UCB descent, xoshiro256++ under
// `--rng native`. Exceptions stay enabled in the shim layer because
// `corridors::board` throws `std::string` from its eval path; the
// `-fno-exceptions` engine build remains a ledger item.

#include "mcts_cpp_imperative.h"

#include "../engine/fast_board.hpp"
#include "../engine/search.hpp"
#include "../engine/state.hpp"

#include <algorithm>
#include <cfenv>
#if defined(__x86_64__) || defined(__i386__)
#include <cpuid.h>
#endif
#include <cstdio>
#include <cstring>
#include <limits>
#include <utility>
#include <vector>

#ifndef MCTS_GIT_COMMIT
#define MCTS_GIT_COMMIT "0000000000000000000000000000000000000000"
#endif

#ifndef MCTS_IMPERATIVE_INSTRUMENTED
#define MCTS_IMPERATIVE_INSTRUMENTED 1
#endif

// The C-ABI board handle is a small wrapper: it owns the current root
// `State` (a compact board + `Word16` ply counter) plus the per-search
// `read_visits` cache so `mcts_imperative_read_visits` remains O(1)
// lookup on the last-search action set.
struct mcts_imperative_board {
    mcts_imperative::State state{};
    std::vector<std::pair<uint8_t, uint32_t>> last_visits{};
    uint8_t last_chosen = 0;
};

namespace {

constexpr uint16_t kGameMaxPlies = 10000;
constexpr uint16_t kSearchMaxPlies = 60;

[[gnu::hot]] static int apply_action_id(mcts_imperative::State &state, uint8_t action_id) {
    std::vector<mcts_imperative::FastBoard> moves;
    state.b.get_capped_legal_moves(moves, state.ply_count);
    for (auto &m : moves) {
        if (m.get_action_id(false) == action_id) {
            state.b = std::move(m);
            state.ply_count = static_cast<uint16_t>(state.ply_count + 1);
            return 0;
        }
    }
    return -1;
}

}  // namespace

extern "C" mcts_imperative_board *mcts_imperative_new_board(void) {
    return new (std::nothrow) mcts_imperative_board{};
}

extern "C" void mcts_imperative_free_board(mcts_imperative_board *board) {
    delete board;
}

extern "C" int mcts_imperative_is_terminal(const mcts_imperative_board *board) {
    if (!board) return 1;
    return board->state.is_terminal(kGameMaxPlies) ? 1 : 0;
}

extern "C" int mcts_imperative_apply_action(mcts_imperative_board *board, uint8_t action_id) {
    if (!board) return -1;
    const int applied = apply_action_id(board->state, action_id);
    if (applied == 0) {
        board->last_visits.clear();
        board->last_chosen = 0;
    }
    return applied;
}

// Sprint 5.3: the engine and C ABI shim both compile under
// `-fno-exceptions` per the doctrine. The legacy `corridors::board`
// throws were replaced with `__builtin_trap()` in `board.cpp` /
// `mcts.hpp`, so no exception can propagate to the C ABI boundary.
// The previous `try`/`catch (...)` defensive wrappers are removed.

extern "C" uint8_t mcts_imperative_select_uct_move(mcts_imperative_board *board,
                                                   uint64_t seed, uint32_t sims) {
    if (!board || board->state.is_terminal(kGameMaxPlies)) return 0;
    auto result = mcts_imperative::run_search(
        board->state,
        sims,
        kSearchMaxPlies,
        mcts_imperative::RngBackend::Mt19937,
        seed);
    if (!result.ok) return 0;
    if (apply_action_id(board->state, result.chosen_action_id) != 0) return 0;
    return result.chosen_action_id;
}

extern "C" int32_t mcts_imperative_search_move(
    mcts_imperative_board *board, uint64_t seed, uint32_t sims,
    uint8_t *out_action_ids, uint32_t *out_visits, uint8_t *out_chosen) {
    if (!board || !out_action_ids || !out_visits || !out_chosen) return -1;
    if (board->state.is_terminal(kGameMaxPlies)) return -1;
    auto result = mcts_imperative::run_search(
        board->state,
        sims,
        kSearchMaxPlies,
        mcts_imperative::RngBackend::Mt19937,
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
}

extern "C" int32_t mcts_imperative_recompute_move(
    mcts_imperative_board *board, uint64_t seed, uint32_t sims,
    uint8_t *out_action_ids, uint32_t *out_visits, uint8_t *out_chosen,
    double *out_equity) {
    if (!board || !out_action_ids || !out_visits || !out_chosen || !out_equity) {
        return -1;
    }
    if (board->state.is_terminal(kGameMaxPlies)) return -1;
    auto result = mcts_imperative::run_search(
        board->state,
        sims,
        kSearchMaxPlies,
        mcts_imperative::RngBackend::Mt19937,
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
    *out_equity = result.chosen_equity;
    return count;
}

extern "C" uint64_t mcts_imperative_benchmark_terminal_playouts(
    const mcts_imperative_board *board,
    uint64_t seed,
    uint32_t count,
    uint16_t max_plies) {
    if (!board) return 0;
    return mcts_imperative::benchmark_terminal_playouts(
        board->state,
        count,
        max_plies,
        seed);
}

extern "C" uint64_t mcts_imperative_benchmark_search_iters(
    const mcts_imperative_board *board,
    uint64_t seed,
    uint32_t count,
    uint16_t max_plies) {
    if (!board) return 0;
    return mcts_imperative::benchmark_search_iters(
        board->state,
        count,
        max_plies,
        mcts_imperative::RngBackend::Mt19937,
        seed);
}

extern "C" uint32_t mcts_imperative_read_visits(
    const mcts_imperative_board *board, uint8_t action_id) {
#if MCTS_IMPERATIVE_INSTRUMENTED
    if (!board) return 0;
    for (const auto &pair : board->last_visits) {
        if (pair.first == action_id) return pair.second;
    }
#else
    (void)board;
    (void)action_id;
#endif
    return 0;
}

static mcts_imperative_envelope g_envelope;
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

// Sprint 6.5: detect the runtime libm at compile time. Same shape as
// cpp-functional's helper; kept inline here so the cpp-imperative
// TU does not need to share a header with cpp-functional.
static void fill_libm_id(mcts_imperative_envelope *env) {
    const char *id =
#if defined(__GLIBC__)
        "glibc"
#elif defined(__MUSL__)
        "musl"
#elif defined(__APPLE__)
        "libsystem"
#else
        "unknown"
#endif
        ;
    size_t len = std::strlen(id);
    if (len > sizeof(env->libm_id)) len = sizeof(env->libm_id);
    std::memcpy(env->libm_id, id, len);
    env->libm_id_len = static_cast<uint8_t>(len);
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
    fill_libm_id(&g_envelope);
    g_envelope_ready = 1;
}

extern "C" const mcts_imperative_envelope *mcts_imperative_get_envelope(void) {
    fill_envelope_once();
    return &g_envelope;
}

#if defined(__GNUC__)
extern "C" void __gcov_dump(void) __attribute__((weak));
extern "C" void __gcov_reset(void) __attribute__((weak));
#endif

extern "C" void mcts_imperative_dump_profile(void) {
#if defined(__GNUC__)
    if (__gcov_dump) __gcov_dump();
    if (__gcov_reset) __gcov_reset();
#endif
}
