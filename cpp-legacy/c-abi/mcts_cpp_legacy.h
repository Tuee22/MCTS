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
int mcts_legacy_apply_action(mcts_legacy_board*, uint8_t action_id);
uint8_t mcts_legacy_select_uct_move(mcts_legacy_board*, uint64_t seed, uint32_t sims);

// Run `sims` simulations from the current root, then commit the chosen
// (max-visits, ties broken by RNG) move. On success returns the number
// of (action_id, visits) records emitted (one per legal child of the
// pre-search root) and writes them to out_action_ids/out_visits sorted
// ascending by action_id. *out_chosen receives the action_id of the
// move that was committed. out_action_ids and out_visits must have
// capacity for at least 209 entries (the canonical action enumeration
// size, see system-components.md). Returns -1 on any failure
// (terminal state, simulate threw, action parse failure). The board
// pointer must remain owned by the caller.
int32_t mcts_legacy_search_move(
    mcts_legacy_board *board,
    uint64_t seed,
    uint32_t sims,
    uint8_t *out_action_ids,
    uint32_t *out_visits,
    uint8_t *out_chosen);

// Foreign-engine recompute entry point per
// documents/engineering/backend_ffi_contract.md → Engine Recompute.
// Runs `mcts_legacy_search_move` and additionally reports the
// post-move equity (parent-perspective, NaN if unavailable). Callers
// use it to populate `MEQ1` sidecar streams for backend (i)
// transcripts when the originating game ran with `--rng cpp`.
int32_t mcts_legacy_recompute_move(
    mcts_legacy_board *board,
    uint64_t seed,
    uint32_t sims,
    uint8_t *out_action_ids,
    uint32_t *out_visits,
    uint8_t *out_chosen,
    double *out_equity);

// Engine envelope per documents/engineering/backend_ffi_contract.md → Engine
// Envelope. Memory layout mirrors the on-wire envelope block in
// documents/engineering/transcript_format.md → Envelope Block. The pointer
// returned by mcts_legacy_get_envelope() references process-static memory
// and must not be freed by the caller.
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
} mcts_legacy_envelope;

const mcts_legacy_envelope *mcts_legacy_get_envelope(void);

#ifdef __cplusplus
}
#endif

#endif
