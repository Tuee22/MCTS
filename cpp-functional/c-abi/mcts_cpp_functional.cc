#include "mcts_cpp_functional.h"

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
