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

typedef struct {
    uint16_t envelope_version;
    uint8_t  rng_source_envelope;
    uint8_t  host_arch_envelope;
    uint8_t  shared_rng_build_id[32];
    uint8_t  cohort_config_hash[32];
    uint8_t  engine_build_id[32];
    char     engine_git_commit[40];
    uint8_t  compiler_id;
    uint8_t  compiler_version_len;
    char     compiler_version[63];
    uint32_t fp_flags;
    uint8_t  libm_id_len;
    char     libm_id[63];
    uint32_t cpu_features;
    uint8_t  fp_env;
} mcts_functional_envelope;

const mcts_functional_envelope *mcts_functional_get_envelope(void);

#ifdef __cplusplus
}
#endif

#endif
