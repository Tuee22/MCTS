#ifndef MCTS_CPP_IMPERATIVE_H
#define MCTS_CPP_IMPERATIVE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mcts_imperative_board mcts_imperative_board;

mcts_imperative_board* mcts_imperative_new_board(void);
void mcts_imperative_free_board(mcts_imperative_board*);
int mcts_imperative_is_terminal(const mcts_imperative_board*);
uint8_t mcts_imperative_select_uct_move(mcts_imperative_board*, uint64_t seed, uint32_t sims);

#ifdef __cplusplus
}
#endif

#endif
