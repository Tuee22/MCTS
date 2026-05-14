#include "mcts_cpp_functional.h"

#include <string.h>

#ifndef MCTS_GIT_COMMIT
#define MCTS_GIT_COMMIT "0000000000000000000000000000000000000000"
#endif

struct mcts_functional_board {
    uint16_t ply;
};

extern "C" mcts_functional_board* mcts_functional_new_board(void) {
    return new mcts_functional_board{0};
}

extern "C" void mcts_functional_free_board(mcts_functional_board* board) {
    delete board;
}

extern "C" int mcts_functional_is_terminal(const mcts_functional_board* board) {
    return board && board->ply >= 200;
}

extern "C" uint8_t mcts_functional_select_uct_move(mcts_functional_board* board, uint64_t seed, uint32_t sims) {
    if (board) {
        board->ply += 1;
    }
    return static_cast<uint8_t>((seed + sims) % 81);
}

static mcts_functional_envelope g_envelope;
static int g_envelope_ready = 0;

static void fill_envelope_once(void) {
    if (g_envelope_ready) return;
    memset(&g_envelope, 0, sizeof(g_envelope));
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
    size_t commit_len = strlen(commit);
    if (commit_len > sizeof(g_envelope.engine_git_commit))
        commit_len = sizeof(g_envelope.engine_git_commit);
    memcpy(g_envelope.engine_git_commit, commit, commit_len);
    g_envelope_ready = 1;
}

extern "C" const mcts_functional_envelope *mcts_functional_get_envelope(void) {
    fill_envelope_once();
    return &g_envelope;
}
