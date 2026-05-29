// Backend (iii) C ABI: shim over the functional-core engine under
// `cpp-functional/engine/`. The engine keeps value-state transitions at
// the API boundary while using compact bitfield state, direct numeric
// action IDs, and the same arena/search memory discipline as the other
// optimized backends.

#include "mcts_cpp_functional.h"

#include "../engine/search.hpp"
#include "../engine/state.hpp"

#include <algorithm>
#include <cfenv>
#if defined(__x86_64__) || defined(__i386__)
#include <cpuid.h>
#endif
#include <cstring>
#include <limits>
#include <optional>
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

constexpr uint16_t kGameMaxPlies = 10000;
constexpr uint16_t kSearchMaxPlies = 60;

[[gnu::hot]] static int apply_action_id(mcts_functional::State &state, uint8_t action_id) {
    std::optional<mcts_functional::State> next = mcts_functional::try_advance(state, action_id);
    if (next.has_value()) {
        state = *next;
        return 0;
    }
    return -1;
}

// Sprint 6.9: trusted internal apply path used after `run_search` already
// validated the absolute action through `legal_actions`. Skips the
// redundant ABI→absolute translation and legality probe that
// `apply_action_id` performs at the C ABI boundary.
[[gnu::hot]] static void apply_trusted_action_id(
    mcts_functional::State &state,
    uint8_t absolute_action_id) noexcept {
    state.apply_action_unchecked(absolute_action_id);
}

[[gnu::hot]] static void store_search_visits(
    mcts_functional_board *board,
    const mcts_functional::SearchOutput &result,
    uint8_t *out_action_ids,
    uint32_t *out_visits) noexcept {
    board->last_visits.clear();
    board->last_visits.reserve(result.visit_count);
    for (size_t i = 0; i < result.visit_count; ++i) {
        const auto &row = result.visits[i];
        board->last_visits.emplace_back(row.first, row.second);
        out_action_ids[i] = row.first;
        out_visits[i] = row.second;
    }
    board->last_chosen = result.chosen_action_id;
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
    return board->state.is_terminal(kGameMaxPlies) ? 1 : 0;
}

extern "C" int mcts_functional_apply_action(mcts_functional_board *board, uint8_t action_id) {
    if (!board) return -1;
    const int applied = apply_action_id(board->state, action_id);
    if (applied == 0) {
        board->last_visits.clear();
        board->last_chosen = 0;
    }
    return applied;
}

// Engine + shim compile under `-fno-exceptions`; invalid C ABI calls
// return error sentinels instead of crossing the C boundary.

extern "C" uint8_t mcts_functional_select_uct_move(mcts_functional_board *board,
                                                   uint64_t seed, uint32_t sims) {
    if (!board || board->state.is_terminal(kGameMaxPlies)) return 0;
    auto result = mcts_functional::run_search(
        board->state,
        sims,
        kSearchMaxPlies,
        mcts_functional::RngBackend::Mt19937,
        seed);
    if (!result.ok) return 0;
    apply_trusted_action_id(board->state, result.chosen_absolute_action_id);
    board->last_visits.clear();
    board->last_chosen = result.chosen_action_id;
    return result.chosen_action_id;
}

extern "C" int32_t mcts_functional_search_move(
    mcts_functional_board *board, uint64_t seed, uint32_t sims,
    uint8_t *out_action_ids, uint32_t *out_visits, uint8_t *out_chosen) {
    if (!board || !out_action_ids || !out_visits || !out_chosen) return -1;
    if (board->state.is_terminal(kGameMaxPlies)) return -1;
    auto result = mcts_functional::run_search(
        board->state,
        sims,
        kSearchMaxPlies,
        mcts_functional::RngBackend::Mt19937,
        seed);
    if (!result.ok) return -1;
    apply_trusted_action_id(board->state, result.chosen_absolute_action_id);
    const int32_t count = static_cast<int32_t>(result.visit_count);
    store_search_visits(board, result, out_action_ids, out_visits);
    *out_chosen = result.chosen_action_id;
    return count;
}

extern "C" int32_t mcts_functional_recompute_move(
    mcts_functional_board *board, uint64_t seed, uint32_t sims,
    uint8_t *out_action_ids, uint32_t *out_visits, uint8_t *out_chosen,
    double *out_equity) {
    if (!board || !out_action_ids || !out_visits || !out_chosen || !out_equity) {
        return -1;
    }
    if (board->state.is_terminal(kGameMaxPlies)) return -1;
    auto result = mcts_functional::run_search(
        board->state,
        sims,
        kSearchMaxPlies,
        mcts_functional::RngBackend::Mt19937,
        seed);
    if (!result.ok) return -1;
    apply_trusted_action_id(board->state, result.chosen_absolute_action_id);
    const int32_t count = static_cast<int32_t>(result.visit_count);
    store_search_visits(board, result, out_action_ids, out_visits);
    *out_chosen = result.chosen_action_id;
    *out_equity = result.chosen_equity;
    return count;
}

extern "C" uint64_t mcts_functional_benchmark_terminal_playouts(
    const mcts_functional_board *board,
    uint64_t seed,
    uint32_t count,
    uint16_t max_plies) {
    if (!board) return 0;
    return mcts_functional::benchmark_terminal_playouts(
        board->state,
        count,
        max_plies,
        seed);
}

extern "C" uint64_t mcts_functional_benchmark_search_iters(
    const mcts_functional_board *board,
    uint64_t seed,
    uint32_t count,
    uint16_t max_plies) {
    if (!board) return 0;
    return mcts_functional::benchmark_search_iters(
        board->state,
        count,
        max_plies,
        mcts_functional::RngBackend::Mt19937,
        seed);
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

// Sprint 6.5: detect the runtime libm at compile time. The pinned
// container ships glibc; the macro check covers the supported set.
static void fill_libm_id(mcts_functional_envelope *env) {
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

extern "C" const mcts_functional_envelope *mcts_functional_get_envelope(void) {
    fill_envelope_once();
    return &g_envelope;
}

#if defined(__GNUC__)
extern "C" void __gcov_dump(void) __attribute__((weak));
extern "C" void __gcov_reset(void) __attribute__((weak));
#endif

extern "C" void mcts_functional_dump_profile(void) {
#if defined(__GNUC__)
    if (__gcov_dump) __gcov_dump();
    if (__gcov_reset) __gcov_reset();
#endif
}
