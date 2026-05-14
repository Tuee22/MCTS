#include "mcts_cpp_legacy.h"

#include <string.h>

#ifndef MCTS_GIT_COMMIT
#define MCTS_GIT_COMMIT "0000000000000000000000000000000000000000"
#endif

struct mcts_legacy_board {
    uint16_t ply;
};

extern "C" mcts_legacy_board* mcts_legacy_new_board(void) {
    return new mcts_legacy_board{0};
}

extern "C" void mcts_legacy_free_board(mcts_legacy_board* board) {
    delete board;
}

extern "C" int mcts_legacy_is_terminal(const mcts_legacy_board* board) {
    return board && board->ply >= 200;
}

extern "C" uint8_t mcts_legacy_select_uct_move(mcts_legacy_board* board, uint64_t seed, uint32_t sims) {
    if (board) {
        board->ply += 1;
    }
    return static_cast<uint8_t>((seed + sims) % 81);
}

// Process-static envelope storage. Fields capture build-time identity per
// documents/engineering/backend_ffi_contract.md → Engine Envelope. The
// engine_build_id and cohort_config_hash slots are zero-initialized until the
// build harness lands the post-link patch step that fills them.
static mcts_legacy_envelope g_envelope;
static int g_envelope_ready = 0;

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
    g_envelope_ready = 1;
}

extern "C" const mcts_legacy_envelope *mcts_legacy_get_envelope(void) {
    fill_envelope_once();
    return &g_envelope;
}
