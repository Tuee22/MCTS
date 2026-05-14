#ifndef MCTS_CPP_LEGACY_H
#define MCTS_CPP_LEGACY_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mcts_legacy_board mcts_legacy_board;
typedef struct mcts_legacy_tree mcts_legacy_tree;

mcts_legacy_board* mcts_legacy_new_board(void);
void mcts_legacy_free_board(mcts_legacy_board*);
int mcts_legacy_is_terminal(const mcts_legacy_board*);
uint8_t mcts_legacy_select_uct_move(mcts_legacy_board*, uint64_t seed, uint32_t sims);

#ifdef __cplusplus
}
#endif

#endif
