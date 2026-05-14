#ifndef MCTS_CPP_FUNCTIONAL_H
#define MCTS_CPP_FUNCTIONAL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mcts_functional_board mcts_functional_board;

mcts_functional_board* mcts_functional_new_board(void);
void mcts_functional_free_board(mcts_functional_board*);
int mcts_functional_is_terminal(const mcts_functional_board*);
uint8_t mcts_functional_select_uct_move(mcts_functional_board*, uint64_t seed, uint32_t sims);

#ifdef __cplusplus
}
#endif

#endif
