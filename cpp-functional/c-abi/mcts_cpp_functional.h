#ifndef MCTS_CPP_FUNCTIONAL_H
#define MCTS_CPP_FUNCTIONAL_H

#include <stdint.h>

#if defined(__GNUC__) || defined(__clang__)
#define MCTS_FUNCTIONAL_API __attribute__((visibility("default")))
#else
#define MCTS_FUNCTIONAL_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mcts_functional_board mcts_functional_board;

MCTS_FUNCTIONAL_API mcts_functional_board* mcts_functional_new_board(void);
MCTS_FUNCTIONAL_API void mcts_functional_free_board(mcts_functional_board*);
MCTS_FUNCTIONAL_API int mcts_functional_is_terminal(const mcts_functional_board*);
MCTS_FUNCTIONAL_API int mcts_functional_apply_action(mcts_functional_board*, uint8_t action_id);
MCTS_FUNCTIONAL_API uint8_t mcts_functional_select_uct_move(mcts_functional_board*, uint64_t seed, uint32_t sims);

MCTS_FUNCTIONAL_API int32_t mcts_functional_search_move(
    mcts_functional_board *board,
    uint64_t seed,
    uint32_t sims,
    uint8_t *out_action_ids,
    uint32_t *out_visits,
    uint8_t *out_chosen);

MCTS_FUNCTIONAL_API int32_t mcts_functional_recompute_move(
    mcts_functional_board *board,
    uint64_t seed,
    uint32_t sims,
    uint8_t *out_action_ids,
    uint32_t *out_visits,
    uint8_t *out_chosen,
    double *out_equity);

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

MCTS_FUNCTIONAL_API const mcts_functional_envelope *mcts_functional_get_envelope(void);

// Optional profile flush hook used by Dockerfile-time PGO training.
// Non-PGO builds expose the symbol as a no-op.
MCTS_FUNCTIONAL_API void mcts_functional_dump_profile(void);

#ifdef __cplusplus
}
#endif

#endif
