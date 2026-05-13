# Transcript Format

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-2-transcript-codec-and-determinism.md, ../../DEVELOPMENT_PLAN/phase-3-haskell-engine.md, ../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md, ../documentation_standards.md, ./README.md, ./determinism_contract.md
**Generated sections**: none

> **Purpose**: Authoritative spec of the MCTS transcript wire format, the 255-action
> canonical enumeration, the content-addressed cache layout, and the git-style
> hash-prefix lookup.

This document owns its content. There is no doctrine overlap; the wire format is
project-specific.

## Design Principles

- **Little-endian binary everywhere.** No padding. No schema-library dependency:
  protobuf, flatbuffers, Cap'n Proto, and CBOR all have library-version-dependent
  encoding latitude that would have to be imported into the determinism contract.
- **Dense, fully owned.** Per-move records are sparse `(action_id, visits)` pairs
  sorted ascending by action ID; equity is excluded because it is a derived float
  whose accumulation order is summation-order-sensitive across backends.
- **Memory-resident trees only.** Nothing about the in-memory tree is serialised;
  only the per-move action choices and visit-count vectors. Tree state at any
  given moment is reproducible by replaying the seed and move sequence.
- **Content-addressed.** Transcripts live in
  `<cache-root>/transcripts/<sha>.tr` where `<sha>` is
  `sha256(run_config)` (or `sha256(run_config || move_history)` for `mcts
  play`-recorded transcripts; see [Content Addressing](#content-addressing)).

## Wire Format

The authoritative wire format is specified by the project
[../../README.md → Cross-backend verification → Transcript wire format](../../README.md).
Little-endian everywhere, no padding.

### Header

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 4 | magic | `MCTR` ASCII bytes (`0x4D 0x43 0x54 0x52`) |
| 4 | 2 | version | Wire-format version (currently `1`) |
| 6 | 1 | backend | `0 = cpp-legacy`, `1 = cpp-imperative`, `2 = cpp-functional`, `3 = rust`, `4 = haskell` |
| 7 | 1 | threading | `0 = single`, `1 = multi` |
| 8 | 2 | workers | `u16`; meaningful only when `threading = multi` |
| 10 | 1 | rng_source | `0 = native`, `1 = cpp` |
| 11 | 1 | _reserved | Must be zero on write, ignored on read |
| 12 | 8 | c_param | UCT exploration constant stored as IEEE-754 `double` bit-cast to `u64` little-endian. Portability pins x86-64 Linux (the project's only target). |
| 20 | 4 | flags | Reserved for future format extensions. **All bits must be zero in v1**; non-zero bits cause `decode` to reject the file with `AppError TranscriptFormatUnsupported`. |
| 24 | 8 | master_seed | `u64` |
| 32 | 4 | initial_sims | `u32`; together with `per_move_sims` encodes `SimBudget` (see below) |
| 36 | 4 | per_move_sims | `u32`; together with `initial_sims` encodes `SimBudget` |
| 40 | 2 | max_plies | `u16`; default `200`, pinned to `10000` under the legacy-parity envelope |
| 42 | 2 | _reserved | Must be zero on write, ignored on read |
| 44 | — | — | Header end; per-game body begins at byte 44 |

**`SimBudget` encoding.** For `FixedSims N`, both `initial_sims` and
`per_move_sims` are set to `N` (the on-wire discriminator for `FixedSims` is
`initial_sims == per_move_sims`). For `RampedSims N0 N1`, `initial_sims = N0` and
`per_move_sims = N1`.

### Per-Game Body

After the header, the per-game body is:

```
game_id u32, then per-move records, then terminator
```

#### Per-Move Record

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 2 | move_index | `u16`; 0-based |
| 2 | 1 | chosen | `u8`; canonical action ID per the 255-action enumeration |
| 3 | 1 | n_actions | `u8`; the number of `(action, visits)` pairs that follow |
| 4 | n_actions × 5 | pairs | Each pair: `u8 action` then `u32 visits`, sorted ascending by `action` |

Total record size: `4 + n_actions × 5` bytes. Pairs are sorted ascending by
`action` so the byte sequence is canonical: any two backends that produce the
same set of `(action, visits)` data produce identical bytes.

#### Terminator

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 1 | sentinel | `0xFF`; distinguishes a terminator from a per-move record (whose `move_index` low byte is never `0xFF` because the wire field is `u16`) |
| 1 | 1 | winner | `0 = hero`, `1 = villain`, `2 = draw` |
| 2 | 2 | total_moves | `u16`; the number of per-move records that preceded the terminator |

### File End

The file ends immediately after the terminator of the last game. The
content-addressed cache uses `sha256` of the whole file as the filename, so the
filename itself is the integrity check. SHA-256 is computed on the fly during
write so the encoder need not hold the whole file in memory.

## Action Enumeration

Canonical 255-action enumeration. One byte per action:

```
  0..80    pawn moves         y*9 + x           (x,y ∈ [0,8])
 81..144   horizontal walls   81  + y*8 + x     (x,y ∈ [0,7])
145..208   vertical walls     145 + y*8 + x     (x,y ∈ [0,7])
209..254   reserved
255        sentinel / invalid
```

The encoding lives in `src/MCTS/Transcript/Action.hs`. The 255-action enumeration
is pinned by the determinism contract; future enumeration changes ride the
`flags` field, which currently must be zero.

## Content Addressing

### Standard Transcripts

Transcripts produced by `mcts bench rollouts/selfplay` and by `mcts verify
rollouts/selfplay/legacy-parity` are addressed by the SHA-256 of the canonical
little-endian encoding of the `RunConfig` record:

```haskell
data RunConfig = RunConfig
  { runConfigBackend      :: Backend
  , runConfigThreading    :: Threading
  , runConfigWorkers      :: Word16
  , runConfigRngSource    :: RngSource
  , runConfigCParam       :: Double      -- bit-cast to Word64 on the wire
  , runConfigMasterSeed   :: Word64
  , runConfigInitialSims  :: Word32      -- SimBudget low half
  , runConfigPerMoveSims  :: Word32      -- SimBudget high half
  , runConfigMaxPlies     :: Word16
  , runConfigGameIndex    :: Word32      -- per-game index; wire width matches
                                          -- the README's `game_id u32`, widened
                                          -- to Word64 with `fromIntegral` at
                                          -- the splitmix and FFI call sites
                                          -- (see determinism_contract.md and
                                          -- backend_ffi_contract.md)
  }
```

The field order and on-wire byte width match the header layout above (game_index
is appended after the on-wire header fields for hashing purposes only — it is
the per-game discriminator and lives in the per-game body, not the header). The
hash is the hex-encoded SHA-256 digest of this record.

### `mcts play`-Recorded Transcripts

Hand-played transcripts produced by `mcts play` are addressed by
`sha256(run_config || move_history)` (where `||` denotes byte concatenation)
rather than `sha256(run_config)` alone, because the human's move choices make the
post-config bytes non-deterministic. The `move_history` is the canonical
byte sequence of `chosen_action` values from the per-move records.

## Cache Root Resolution

Per
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item 12](../../DEVELOPMENT_PLAN/00-overview.md):

1. `--cache-dir <path>` if provided.
2. `$MCTS_CACHE_DIR` if set.
3. `./.mcts-cache/` resolved against the current working directory.

On-disk layout under the cache root: `transcripts/<sha>.tr`. The `<sha>` is the
full 64-character hex-encoded SHA-256 digest.

The cache root is `.gitignore`'d when it falls inside the project tree.

## Hash-Prefix Lookup

Git-style. Per
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item 13](../../DEVELOPMENT_PLAN/00-overview.md):

- Minimum prefix length: 4 hex characters.
- On no match: `AppError TranscriptNotFound`.
- On multi-match: `AppError TranscriptAmbiguous` carrying the candidate hash list.
- On unique match: the resolved `TranscriptRef`.

The lookup is purely lexical over filenames under
`<cache-root>/transcripts/*.tr`; no transcript bytes are read.

## Atomic Writes

The transcript writer writes to a temp file in the same directory, fsyncs, then
renames to the final path. This guarantees that any file under
`<cache-root>/transcripts/` is either complete and valid or absent — there is no
torn-write window.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [determinism_contract.md](./determinism_contract.md) — visit-count vs equity
  asymmetry that motivates the equity-excluded wire format
- [backend_ffi_contract.md](./backend_ffi_contract.md) — how each backend writes
  the wire format from its FFI driver
- [cli_command_surface.md](./cli_command_surface.md) — `mcts inspect list`,
  `mcts inspect show`, `mcts inspect replay`
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
