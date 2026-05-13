# Phase 2: Transcript Codec, RNG, and Determinism Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

> **Purpose**: Land the transcript wire format, the 255-action canonical enumeration,
> the per-game RNG seed derivation, the cache root resolution and hash-prefix lookup,
> and the non-interactive `mcts inspect list` / `mcts inspect show` surfaces — the
> determinism contract every backend will honour.

## Phase Status

📋 Planned. Blocked by Phase `1` closure (the codec lives behind the `Subprocess`
boundary, the `Plan` ADT, the `AppError` ADT, and the `Env` record established there).

## Phase Summary

Phase `2` writes the deterministic byte-level layer of the project: the little-endian
binary transcript wire format with no schema-library dependency, the 255-action
canonical enumeration that gives every legal Corridors action a single `u8` ID, the
`splitmix64(master_seed, game_index)` per-game RNG seed derivation that makes per-game
output independent of worker count and scheduling order, the `--rng native` vs
`--rng cpp` split, and the content-addressed transcript cache under
`.mcts-cache/transcripts/`. It also lands the non-interactive `mcts inspect list` and
`mcts inspect show` commands plus the git-style hash-prefix lookup. No engine and no
backend lands yet; this phase is the format spec the engine writes into.

## Sprint 2.1: Wire-Format Header and Per-Move Record Codec 📋

**Status**: Planned
**Implementation**: `src/MCTS/Transcript/Header.hs`,
`src/MCTS/Transcript/Record.hs`, `src/MCTS/Transcript/Action.hs`,
`src/MCTS/Transcript/Codec.hs`
**Docs to update**: `documents/engineering/transcript_format.md`,
`documents/engineering/determinism_contract.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Land the deterministic binary wire format: header carrying the run config, per-move
records of `(action_id, visits)` sorted ascending by action ID, equity excluded.

### Deliverables

- `src/MCTS/Transcript/Action.hs` declares the canonical 255-action enumeration as a
  pure conversion between Corridors action types and `Word8`:
  - `0..80` pawn moves: `y*9 + x` for `x,y ∈ [0,8]`
  - `81..144` horizontal walls: `81 + y*8 + x` for `x,y ∈ [0,7]`
  - `145..208` vertical walls: `145 + y*8 + x` for `x,y ∈ [0,7]`
  - `209..254` reserved
  - `255` sentinel / invalid
- `src/MCTS/Transcript/Header.hs` carries the header layout per
  [../README.md → Cross-backend verification → Transcript wire format](../README.md).
  Little-endian, no padding, fixed-width fields in this exact order:
  - `magic u32 = "MCTR"` — ASCII bytes `0x4D 0x43 0x54 0x52`.
  - `version u16` — wire-format version; v1 in this sprint.
  - `backend u8` — 0=cpp-legacy, 1=cpp-imperative, 2=cpp-functional, 3=rust, 4=haskell.
  - `threading u8` — 0=single, 1=multi.
  - `workers u16` — meaningful only when `threading = multi`.
  - `rng_source u8` — 0=native, 1=cpp.
  - `_reserved u8` — must be zero on write, ignored on read.
  - `c_param u64` — UCT exploration constant stored as IEEE-754 `double` bit-cast to
    `u64` little-endian. Portability pins x86-64 Linux (the project's only target).
  - `flags u32` — reserved for future format extensions. All bits **must** be zero
    in v1; non-zero bits cause `decode` to reject the file with
    `AppError TranscriptFormatUnsupported`.
  - `master_seed u64`.
  - `initial_sims u32` / `per_move_sims u32` — together encode `SimBudget`. For
    `FixedSims N` both fields are N (the on-wire discriminator for `FixedSims` is
    `initial_sims == per_move_sims`). For `RampedSims N0 N1` set
    `initial_sims = N0` and `per_move_sims = N1`.
  - `max_plies u16` — default `200`; pinned to `10000` under the legacy-parity
    envelope.
  - `_reserved u16` — must be zero on write, ignored on read.
- `src/MCTS/Transcript/Record.hs` carries the per-game and per-move layout:
  - Per-game body starts with `game_id u32`, then per-move records, then a
    terminator.
  - Per-move record: `move_index u16 | chosen u8 | n_actions u8` followed by
    `n_actions × (action u8, visits u32)` pairs sorted ascending by action.
  - Terminator: `0xFF u8 | winner u8 | total_moves u16`, with
    `winner ∈ {0 = hero, 1 = villain, 2 = draw}`.
- `src/MCTS/Transcript/Codec.hs` exposes pure `encode` and `decode` functions
  satisfying the canonical property invariant `decode . encode == id` per
  [../HASKELL_CLI_TOOL.md → Test Categories → Property Tests](../HASKELL_CLI_TOOL.md);
  Sprint 7.1 owns the property test placement. `decode` rejects non-zero `flags`
  with `AppError TranscriptFormatUnsupported` (the `AppError` constructor is
  declared in
  [phase-1-haskell-cli-surface.md → Sprint 1.9](phase-1-haskell-cli-surface.md)).
- The wire format excludes equity. Cross-backend determinism is enforced on visit
  counts only, per
  [00-overview.md → Hard Constraints item 15](00-overview.md).

### Validation

1. A property test asserts `decode . encode == id` on `Header`, `Record`, and
   `Transcript` (full file).
2. A property test asserts records within a file are sorted ascending by
   `action_id`.
3. A golden test asserts a specific transcript renders to a specific byte sequence
   (the bytes are pinned in `test/golden/transcript-codec/`).

### Remaining Work

Not started.

## Sprint 2.2: Content-Addressed Cache and Cache Root Resolution 📋

**Status**: Planned
**Implementation**: `src/MCTS/Transcript/Hash.hs`,
`src/MCTS/Transcript/Cache.hs`, `.gitignore`
**Docs to update**: `documents/engineering/transcript_format.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Land `sha256(run_config)` content addressing, the cache root resolution chain, and
the `.gitignore` entry that keeps the cache out of version control.

### Deliverables

- `src/MCTS/Transcript/Hash.hs` exposes `runConfigHash :: RunConfig -> ByteString`
  computing `sha256(run_config)` over the canonical big-endian encoding of the run
  config; `playTranscriptHash :: RunConfig -> [Move] -> ByteString` computes
  `sha256(run_config || move_history)` for `mcts play`-recorded transcripts.
- `src/MCTS/Transcript/Cache.hs` resolves the cache root in this order, per
  [00-overview.md → Hard Constraints item 12](00-overview.md):
  1. `--cache-dir <path>` if provided
  2. `$MCTS_CACHE_DIR` if set
  3. `./.mcts-cache/` resolved against the current working directory
- On-disk layout under the cache root: `transcripts/<sha>.tr`. The full sha is the
  hex-encoded `sha256` digest.
- `.gitignore` excludes `.mcts-cache/` when the cache resolves inside the project
  tree.

### Validation

1. A unit test exercises the cache-root resolution chain across all three branches.
2. A round-trip test writes a transcript to a temporary cache root via
   `MCTS.Transcript.Cache.write`, reads it back via `MCTS.Transcript.Cache.read`,
   and asserts byte equality.
3. `git status` in a fresh worktree shows no `.mcts-cache/` entry.

### Remaining Work

Not started.

## Sprint 2.3: Git-Style Hash-Prefix Lookup 📋

**Status**: Planned
**Implementation**: `src/MCTS/Transcript/Lookup.hs`
**Docs to update**: `documents/engineering/transcript_format.md`,
`documents/engineering/cli_command_surface.md`

### Objective

Land `lookupByPrefix :: Text -> App (Either AppError TranscriptRef)` so the
`inspect show` and `inspect replay` `<hash-prefix>` arguments resolve to a unique
transcript with the doctrine-flavoured error rendering.

### Deliverables

- `src/MCTS/Transcript/Lookup.hs` exposes `lookupByPrefix` per
  [00-overview.md → Hard Constraints item 13](00-overview.md):
  - Minimum prefix is 4 hex characters.
  - On no match, return `AppError TranscriptNotFound`.
  - On multi-match, return `AppError TranscriptAmbiguous` carrying the candidate
    list so the operator can re-issue with a longer prefix.
  - On unique match, return the resolved `TranscriptRef`.
- The lookup is purely lexical over filenames under
  `<cache-root>/transcripts/*.tr`; no transcript bytes are read.

### Validation

1. Unit tests cover the no-match, ambiguous-match, exact-match, and
   too-short-prefix branches.
2. Property test: for any populated cache with N transcripts, any prefix `p` of
   `sha(t)` that is unique among the set returns `t` and nothing else.

### Remaining Work

Not started.

## Sprint 2.4: `mcts inspect list` and `mcts inspect show` 📋

**Status**: Planned
**Implementation**: `src/MCTS/CLI/Inspect.hs`,
`src/MCTS/CLI/Spec.hs` (Inspect subtree),
`src/MCTS/Notation.hs`
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`documents/engineering/transcript_format.md`

### Objective

Land the non-interactive `inspect` commands: `mcts inspect list` for cache
enumeration and `mcts inspect show <hash-prefix>` for transcript dump in the
legacy move notation. `mcts inspect replay` (interactive `brick` TUI) is owned by
Sprint 7.4.

### Deliverables

- `src/MCTS/Notation.hs` exposes `renderMove :: Move -> Text` and the inverse
  parser for the legacy move notation: `*(x,y)` pawn, `H(x,y)` horizontal wall,
  `V(x,y)` vertical wall, with `x,y ∈ [0,8]` for pawns and `∈ [0,7]` for walls.
  Draws render as `<draw>`.
- `src/MCTS/CLI/Inspect.hs` owns the runners:
  - `mcts inspect list` scans `<cache-root>/transcripts/*.tr`, decodes each header,
    prints one line per transcript: short hash (first 8 chars), backend, master
    seed, threading (`ST` or `MT8`), sims, total games, total moves, mtime. Sorted
    by mtime descending. Honours `--format json|table|plain`.
  - `mcts inspect show <hash-prefix>` resolves the prefix via Sprint 2.3, decodes
    the transcript, prints the header summary followed by per-move records in the
    legacy notation per the project [README](../README.md). Default `--top 10`;
    `--top 0` shows all legal moves.
  - **`--with-equity` column.** When `--with-equity` is set, the per-move record
    renderer emits an `equity=<float>` column on every line per
    [../README.md → Interactive modes → `inspect show <hash-prefix>`](../README.md)
    (README lines 538–540). The equity values are produced by the same pure
    rendering function that the `inspect replay` TUI's context panel uses
    (Sprint 7.4), so the two surfaces stay aligned. The recompute path itself
    (re-running the deterministic search to populate the equity values) lands
    in Sprint 7.4; Sprint 2.4 wires the column slot, the flag, and the shared
    renderer signature so that hooking the recompute path is a one-line wiring
    change in 7.4.
- The `CommandSpec` entries for `inspect list` and `inspect show` carry at least
  one `Example` entry each.

### Validation

1. A round-trip test: write a known transcript to the cache, run
   `mcts inspect show <prefix>`, assert the rendered output matches a golden.
2. `mcts inspect list --format json` emits valid JSON; the schema is pinned in
   `test/golden/inspect-list-schema.json`.
3. A unit test asserts the move-notation renderer / parser round-trips over every
   action in the 255-action enumeration.

### Remaining Work

Not started.

## Sprint 2.5: `splitmix64` Seed Derivation and `--rng` Plumbing 📋

**Status**: Planned
**Implementation**: `src/MCTS/Rng/Mix.hs`, `src/MCTS/Rng/Native.hs`,
`src/MCTS/Rng/Source.hs`, `src/MCTS/CLI/Spec.hs` (`--rng` option)
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/cli_command_surface.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Land the per-game `splitmix64(master_seed, game_index)` seed mixer, the
`RngSource = NativeRng | CppRng` type, and the `--rng native|cpp` parser surface.
The Haskell-side `NativeRng` consumer is `splitmix`; the C++ FFI-backed `CppRng`
consumer is wired in Phase 4 once the FFI bridge exists.

### Deliverables

- `src/MCTS/Rng/Mix.hs` exposes
  `mix :: Word64 -> Word64 -> Word64` implementing the splitmix64 mixer per
  [00-overview.md → Hard Constraints item 4](00-overview.md). The game-index
  argument is `Word64` to match the C ABI's `cpp_rng_split(uint64_t master_seed,
  uint64_t game_index)` from
  [../README.md → Cross-backend verification → RNG FFI contract](../README.md);
  callers that hold a `Word32` wire-format `runConfigGameIndex` widen with
  `fromIntegral` at the call site. Tests pin the mixer output for a known
  `(master_seed, game_index)` pair to a known `Word64`.
- `src/MCTS/Rng/Source.hs` declares `data RngSource = NativeRng | CppRng`. Parsing
  of `--rng native` and `--rng cpp` is registered in the `CommandSpec`.
- `src/MCTS/Rng/Native.hs` carries the Haskell-native splitmix RNG consumer
  (the `splitmix` library on Hackage; backend (v)'s pinned `--rng native`
  choice per
  [../documents/engineering/determinism_contract.md → RNG Source Split → Per-Backend Native RNG Table](../documents/engineering/determinism_contract.md));
  the `bench rollouts` / `bench selfplay` paths for `--backend haskell` use it
  once Phase 3 lands the engine.
- The `verify` subtree pins `--rng cpp` at parse time (the `VerifyOptions` record
  has no `verifyRng` field); attempting `--rng native` on `verify` is rejected at
  parse time with `AppError VerifyCohortTooSmall`-style messaging.
- Backend (i) silently ignores `--rng native` and always uses `std::mt19937_64`; the
  `CommandSpec` documentation reflects this asymmetry.

### Validation

1. Golden test pins `mix(42, 0) = <Word64>`, `mix(42, 1) = <Word64>` for a chosen
   seed pair; the values come from the canonical splitmix64 spec.
2. A property test asserts `mix master_seed n` is bijective in `n` for fixed
   `master_seed` over the first 1M values of `Word64`.
3. Cross-language roundtrip: for a small fixture of `(master_seed, game_index)`
   pairs, the Haskell `mix masterSeed gameIndex` must equal the initial-state
   word produced by the C ABI `cpp_rng_split(masterSeed, gameIndex)` from
   [phase-4-cpp-legacy-port-and-ffi-bridge.md → Sprint 4.3](phase-4-cpp-legacy-port-and-ffi-bridge.md).
   The check is deferred to Phase 4 closure (the FFI shim must exist) but the
   fixture is committed in this sprint so the assertion lands the moment the
   shim is callable.
4. `mcts bench rollouts --rng native --backend haskell --games 8 --seed 42` runs
   to completion once Phase 3 closure connects the engine to the CLI surface;
   placeholder smoke test in this sprint asserts the CLI parses the flag matrix.

### Remaining Work

Not started.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/transcript_format.md` — fill in the wire format, the
  255-action enumeration, the content-addressing scheme, the cache root resolution,
  and the git-style hash-prefix lookup contract.
- `documents/engineering/determinism_contract.md` — fill in the full determinism
  contract per the README. The eleven owned sections are: the `--rng native` vs
  `--rng cpp` split (and the verify-subtree pin); the per-game
  `splitmix64(master_seed, game_index)` derivation; same-backend determinism
  (Q4); cross-backend determinism (Q3) under `--rng cpp` with the `VerifyBackend`
  GADT excluding `cpp-legacy`; the ply-cap draw rule and `max_plies`
  contract; the legacy parity envelope (`max_plies = MAX_ROLLOUT_ITERS = 10000`,
  fixture seed `S_LP = 42`, `AppError LegacyParityRolloutOverflow`); the
  visit-count vs equity asymmetry and the cross-backend equity tolerance
  implicit through tie-break swap; the byte-consumption contract (same `u64`s
  per rollout, `draw % n` for legal-move selection, no rejection sampling unless
  identical); the backprop traversal contract (same path order, same logical
  step for visit-count and value-sum updates); the tie-breaking contract
  (`(equity desc, non_terminal_rank asc)` applied uniformly across all five
  backends); the verify mismatch output protocol (digest-equality first, then
  move-by-move scan emitting `AppError VerifyMismatch` with `(left_backend,
  right_backend, game_id, move_index, left_record, right_record)`); tree
  persistence and memory-resident-only trees; and the threading model
  (single-threaded per game, MT pool dispatches independent games).
- `documents/engineering/cli_command_surface.md` — extend the command matrix with
  the `mcts inspect list` and `mcts inspect show` surfaces, and document the
  `--rng`, `--cache-dir`, `--top`, `--with-equity`, `--format`, `--color`,
  `--no-color` flags.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md` Transcript Codec rows update from `📋 Planned` to
  `🔄 Active` / `✅ Done` as each sprint lands.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md)
- [phase-3-haskell-engine.md](phase-3-haskell-engine.md)
- [phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
