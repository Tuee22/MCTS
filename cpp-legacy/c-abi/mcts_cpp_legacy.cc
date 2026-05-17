#include "mcts_cpp_legacy.h"

#include "../legacy-core/board.h"

#include <algorithm>
#if defined(__x86_64__) || defined(__i386__)
#include <cpuid.h>
#endif
#include <cfenv>
#include <limits>
#include <memory>
#include <random>
#include <string.h>
#include <string>
#include <tuple>

#ifndef MCTS_GIT_COMMIT
#define MCTS_GIT_COMMIT "0000000000000000000000000000000000000000"
#endif

struct mcts_legacy_board {
    std::shared_ptr<mcts::uct_node<corridors::board>> root;
    std::mt19937_64 rng;
};

extern "C" mcts_legacy_board* mcts_legacy_new_board(void) {
    corridors::board initial;
    return new mcts_legacy_board{
        std::make_shared<mcts::uct_node<corridors::board>>(std::move(initial)),
        std::mt19937_64(0)
    };
}

extern "C" void mcts_legacy_free_board(mcts_legacy_board* board) {
    delete board;
}

extern "C" int mcts_legacy_is_terminal(const mcts_legacy_board* board) {
    if (!board || !board->root) {
        return 1;
    }
    return board->root->get_state().is_terminal() ? 1 : 0;
}

static uint8_t parse_action_id(const std::string& action) {
    if (action.size() < 5) {
        return 0;
    }
    const bool pawn = action[0] == '*';
    const bool horizontal = action[0] == 'H';
    const bool vertical = action[0] == 'V';
    const size_t open = action.find('(');
    const size_t comma = action.find(',');
    const size_t close = action.find(')');
    if (open == std::string::npos || comma == std::string::npos || close == std::string::npos) {
        return 0;
    }
    const int x = std::stoi(action.substr(open + 1, comma - open - 1));
    const int y = std::stoi(action.substr(comma + 1, close - comma - 1));
    if (pawn) {
        return static_cast<uint8_t>(y * 9 + x);
    }
    if (horizontal) {
        return static_cast<uint8_t>(81 + y * 8 + x);
    }
    if (vertical) {
        return static_cast<uint8_t>(145 + y * 8 + x);
    }
    return 0;
}

extern "C" uint8_t mcts_legacy_select_uct_move(mcts_legacy_board* board, uint64_t seed, uint32_t sims) {
    if (!board || !board->root || board->root->get_state().is_terminal()) {
        return 0;
    }
    try {
        board->rng.seed(seed);
        board->root->simulate(
            static_cast<size_t>(sims),
            board->rng,
            1.4,
            true,
            false,
            false,
            false
        );
        auto next = board->root->choose_best_action(board->rng, 0.0, true);
        std::string action = next->get_state().get_action_text(false);
        board->root = next;
        return parse_action_id(action);
    } catch (...) {
        return 0;
    }
}

extern "C" int32_t mcts_legacy_search_move(
    mcts_legacy_board *board,
    uint64_t seed,
    uint32_t sims,
    uint8_t *out_action_ids,
    uint32_t *out_visits,
    uint8_t *out_chosen) {
    if (!board || !board->root || !out_action_ids || !out_visits || !out_chosen) {
        return -1;
    }
    if (board->root->get_state().is_terminal()) {
        return -1;
    }
    try {
        board->rng.seed(seed);
        // Mirror the upstream legacy's exact `simulate` call signature
        // (eval_children=false). At report-card sim budgets
        // (S_LP_SIMS=10000) every child of the root gets explored via
        // the iteration loop, so `choose_best_action`'s winning-moves
        // `get_equity` check has valid `eval_Q` for every terminal
        // child. At lower sim budgets some terminal children may stay
        // unevaluated; the try/catch below falls back to a
        // deterministic max-visit pick from `get_sorted_actions`.
        board->root->simulate(
            static_cast<size_t>(sims),
            board->rng,
            1.4,
            true,
            false,
            false,
            false
        );
        auto moves = board->root->get_sorted_actions(false);
        std::vector<std::tuple<uint8_t, uint32_t>> records;
        records.reserve(moves.size());
        for (const auto &mv : moves) {
            size_t visits = std::get<0>(mv);
            const std::string &text = std::get<2>(mv);
            uint8_t aid = parse_action_id(text);
            if (visits > std::numeric_limits<uint32_t>::max()) {
                visits = std::numeric_limits<uint32_t>::max();
            }
            records.emplace_back(aid, static_cast<uint32_t>(visits));
        }
        std::sort(records.begin(), records.end(),
                  [](const auto &a, const auto &b) {
                      return std::get<0>(a) < std::get<0>(b);
                  });
        std::shared_ptr<mcts::uct_node<corridors::board>> next;
        std::string action;
        try {
            next = board->root->choose_best_action(board->rng, 0.0, true);
            action = next->get_state().get_action_text(false);
        } catch (const std::string &) {
            // The legacy's `choose_best_action` calls `get_equity()`
            // on every terminal child when scanning for winning moves;
            // when `simulate` ran with a small budget and the root's
            // `check_non_terminal_eval()` is true (race decided, no
            // walls), terminal children stay unevaluated and that
            // call throws. Fall back to picking the highest-visit
            // child by action text — `get_sorted_actions` ordered
            // them by equity desc, so the tied-visit head is the
            // legacy's own preferred move. Tie-break is the action
            // text's lexicographic order, which is deterministic per
            // seed (we don't draw from the RNG here, so subsequent
            // simulate calls see identical RNG state).
            const std::tuple<size_t, double, std::string> *best = nullptr;
            for (const auto &mv : moves) {
                if (!best || std::get<0>(mv) > std::get<0>(*best)) {
                    best = &mv;
                }
            }
            if (!best) {
                throw;
            }
            action = std::get<2>(*best);
            next = board->root->make_move(action, false);
        }
        // Preserve the legacy's tree continuity: the new root keeps
        // its accumulated visit counts and evaluations. This matches
        // the upstream legacy's self-play loop and the
        // `legacy-to-wire` fixture generator.
        board->root = next;
        const int32_t count = static_cast<int32_t>(records.size());
        for (int32_t i = 0; i < count; ++i) {
            out_action_ids[i] = std::get<0>(records[i]);
            out_visits[i] = std::get<1>(records[i]);
        }
        *out_chosen = parse_action_id(action);
        return count;
    } catch (const std::string &) {
        if (out_chosen) *out_chosen = 0;
        return -1;
    } catch (const std::exception &) {
        return -1;
    } catch (...) {
        return -1;
    }
}

// Process-static envelope storage. Fields capture build-time identity
// per documents/engineering/backend_ffi_contract.md → Engine Envelope.
// `engine_build_id` and `cohort_config_hash` are zero-initialized
// until the build harness lands the post-link `objcopy
// --update-section` patch (the `legacy-envelope-id` Make target writes
// it into the `.envelope_build_id` ELF section). `cpu_features` and
// `fp_env` are filled at the first `mcts_legacy_get_envelope` call
// via the runtime probes below.
static mcts_legacy_envelope g_envelope;
static int g_envelope_ready = 0;

// Embedded `engine_build_id` slot. The post-link patch step
// (`make -C cpp-legacy envelope-build-id`) replaces the contents of
// the `.envelope_build_id` ELF section with the SHA-256 of the linked
// `libmcts_cpp_legacy.so` itself. The default contents stay
// zero-initialised so smoke builds without the patch still match the
// envelope's `zeroDigest` sentinel.
__attribute__((section(".envelope_build_id")))
static uint8_t g_engine_build_id[32] = {0};

// Runtime CPU feature bits per
// `documents/engineering/backend_ffi_contract.md → CPU Feature Bits`.
// The doctrine packs bits into the same `u32` layout for every
// backend so verify can compare backends.
static uint32_t probe_cpu_features(void) {
    uint32_t bits = 0;
#if defined(__x86_64__) || defined(__i386__)
    unsigned int eax = 0, ebx = 0, ecx = 0, edx = 0;
    if (__get_cpuid(1, &eax, &ebx, &ecx, &edx)) {
        if (edx & (1u << 23)) bits |= 0x1u; // MMX
        if (edx & (1u << 25)) bits |= 0x2u; // SSE
        if (edx & (1u << 26)) bits |= 0x4u; // SSE2
        if (ecx & (1u << 0))  bits |= 0x8u; // SSE3
        if (ecx & (1u << 9))  bits |= 0x10u; // SSSE3
        if (ecx & (1u << 19)) bits |= 0x20u; // SSE4.1
        if (ecx & (1u << 20)) bits |= 0x40u; // SSE4.2
        if (ecx & (1u << 28)) bits |= 0x80u; // AVX
        if (ecx & (1u << 12)) bits |= 0x100u; // FMA
    }
    if (__get_cpuid_count(7, 0, &eax, &ebx, &ecx, &edx)) {
        if (ebx & (1u << 5))  bits |= 0x200u; // AVX2
        if (ebx & (1u << 16)) bits |= 0x400u; // AVX-512F
        if (ebx & (1u << 29)) bits |= 0x800u; // SHA
    }
#elif defined(__aarch64__)
    // The arm64 ABI guarantees NEON + ASIMD on every AArch64 binary
    // we'd run; ASE / SHA / CRC come from getauxval(AT_HWCAP) which
    // varies by libc and isn't worth conditionally pulling in here.
    bits |= 0x10000u; // NEON (asimd)
    bits |= 0x20000u; // FP
#endif
    return bits;
}

// Pack the rounding mode + denormal flag into the doctrine's u8 fp_env
// payload.
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
    if (mxcsr & (1u << 15)) value |= 0x10u; // FTZ
    if (mxcsr & (1u << 6))  value |= 0x20u; // DAZ
#endif
    return value;
}

// Sprint 6.5: detect the runtime libm at compile time. Same shape
// as the cpp-functional / cpp-imperative shims.
static void fill_libm_id(mcts_legacy_envelope *env) {
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
    size_t len = strlen(id);
    if (len > sizeof(env->libm_id)) len = sizeof(env->libm_id);
    memcpy(env->libm_id, id, len);
    env->libm_id_len = static_cast<uint8_t>(len);
}

static void fill_envelope_once(void) {
    if (g_envelope_ready) return;
    memset(&g_envelope, 0, sizeof(g_envelope));
    g_envelope.envelope_version = 1;
    g_envelope.rng_source_envelope = 1; // cpp
#if defined(__aarch64__)
    g_envelope.host_arch_envelope = 1; // arm64
#else
    g_envelope.host_arch_envelope = 0; // amd64
#endif
#if defined(__clang__)
    g_envelope.compiler_id = 1;
#else
    g_envelope.compiler_id = 0; // gcc
#endif
    const char *commit = MCTS_GIT_COMMIT;
    size_t commit_len = strlen(commit);
    if (commit_len > sizeof(g_envelope.engine_git_commit))
        commit_len = sizeof(g_envelope.engine_git_commit);
    memcpy(g_envelope.engine_git_commit, commit, commit_len);
    memcpy(g_envelope.engine_build_id, g_engine_build_id, 32);
    g_envelope.cpu_features = probe_cpu_features();
    g_envelope.fp_env = probe_fp_env();
    fill_libm_id(&g_envelope);
    g_envelope_ready = 1;
}

extern "C" const mcts_legacy_envelope *mcts_legacy_get_envelope(void) {
    fill_envelope_once();
    return &g_envelope;
}

// Foreign-engine recompute entry point per
// `documents/engineering/backend_ffi_contract.md → Engine Recompute`.
// Replays a single move of a transcript through the legacy and emits
// the resulting visit vector plus a per-move equity record. The
// `equity` slot is the parent-perspective equity reported by the
// legacy's `get_equity()` after the search (a float in [-1, +1]);
// callers should treat `NaN` as "equity not available at this depth".
extern "C" int32_t mcts_legacy_recompute_move(
    mcts_legacy_board *board,
    uint64_t seed,
    uint32_t sims,
    uint8_t *out_action_ids,
    uint32_t *out_visits,
    uint8_t *out_chosen,
    double *out_equity) {
    if (!out_equity) return -1;
    *out_equity = std::numeric_limits<double>::quiet_NaN();
    int32_t count = mcts_legacy_search_move(
        board, seed, sims, out_action_ids, out_visits, out_chosen);
    if (count < 0) return count;
    // The chosen child has just become the new root; its parent (the
    // pre-make_move root) is gone. Equity at the new root mirrors the
    // pre-make_move parent's equity through choose_best_action's sign
    // flip in the legacy: equity from the previous player's POV.
    try {
        if (board && board->root && board->root->is_evaluated()) {
            *out_equity = -board->root->get_equity();
        }
    } catch (...) {
        *out_equity = std::numeric_limits<double>::quiet_NaN();
    }
    return count;
}
