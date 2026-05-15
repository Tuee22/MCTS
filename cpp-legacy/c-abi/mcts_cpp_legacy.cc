#include "mcts_cpp_legacy.h"

#include "../legacy-core/board.h"

#include <memory>
#include <random>
#include <string.h>
#include <string>

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
