#include "mcts_cpp_imperative.h"

struct mcts_imperative_board {
    uint16_t ply;
};

extern "C" mcts_imperative_board* mcts_imperative_new_board(void) {
    return new mcts_imperative_board{0};
}

extern "C" void mcts_imperative_free_board(mcts_imperative_board* board) {
    delete board;
}

extern "C" int mcts_imperative_is_terminal(const mcts_imperative_board* board) {
    return board && board->ply >= 200;
}

extern "C" uint8_t mcts_imperative_select_uct_move(mcts_imperative_board* board, uint64_t seed, uint32_t sims) {
    if (board) {
        board->ply += 1;
    }
    return static_cast<uint8_t>((seed + sims) % 81);
}
