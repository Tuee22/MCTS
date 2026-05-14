#include "mcts_cpp_legacy.h"

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
