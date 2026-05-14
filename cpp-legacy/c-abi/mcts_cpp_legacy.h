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
