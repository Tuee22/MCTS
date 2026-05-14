#ifndef MCTS_CPP_RNG_H
#define MCTS_CPP_RNG_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cpp_rng cpp_rng;

cpp_rng* cpp_rng_new(uint64_t seed);
uint64_t cpp_rng_next_u64(cpp_rng*);
cpp_rng* cpp_rng_split(uint64_t master_seed, uint64_t game_index);
void cpp_rng_free(cpp_rng*);

#ifdef __cplusplus
}
#endif

#endif
