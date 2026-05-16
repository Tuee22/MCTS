#ifndef MCTS_CPP_IMPERATIVE_H
#define MCTS_CPP_IMPERATIVE_H

#include <stdint.h>

#if defined(__GNUC__) || defined(__clang__)
#define MCTS_IMPERATIVE_API __attribute__((visibility("default")))
#else
#define MCTS_IMPERATIVE_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mcts_imperative_board mcts_imperative_board;

MCTS_IMPERATIVE_API mcts_imperative_board* mcts_imperative_new_board(void);
MCTS_IMPERATIVE_API void mcts_imperative_free_board(mcts_imperative_board*);
MCTS_IMPERATIVE_API int mcts_imperative_is_terminal(const mcts_imperative_board*);
MCTS_IMPERATIVE_API uint8_t mcts_imperative_select_uct_move(mcts_imperative_board*, uint64_t seed, uint32_t sims);

// Full search-with-visit-vector ABI per
// documents/engineering/backend_ffi_contract.md → C ABI Shape. Mirrors
// backend (i)'s `mcts_legacy_search_move`.
MCTS_IMPERATIVE_API int32_t mcts_imperative_search_move(
    mcts_imperative_board *board,
    uint64_t seed,
    uint32_t sims,
    uint8_t *out_action_ids,
    uint32_t *out_visits,
    uint8_t *out_chosen);

// Foreign-engine recompute entry point. Returns the search result
// plus the post-move parent-perspective equity (NaN when unavailable).
MCTS_IMPERATIVE_API int32_t mcts_imperative_recompute_move(
    mcts_imperative_board *board,
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
} mcts_imperative_envelope;

MCTS_IMPERATIVE_API const mcts_imperative_envelope *mcts_imperative_get_envelope(void);

// Bench / instrumented split: the bench artefact returns 0 from
// `mcts_imperative_read_visits` (the symbol is exported but inert);
// the instrumented artefact returns the actual visit count for the
// requested move. Operator-facing tools (verify, play, inspect
// replay) load the instrumented variant; `mcts bench` loads the bench
// variant.
MCTS_IMPERATIVE_API uint32_t mcts_imperative_read_visits(
    const mcts_imperative_board *board,
    uint8_t action_id);

#ifdef __cplusplus
}
#endif

#endif
