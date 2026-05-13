# Phase 3: Backend (v) Haskell Engine

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

> **Purpose**: Land the native Haskell Corridors engine — bitboard game state, MCTS
> search and rollout core in `ST s`, tree persistence, the pure search API, and the
> per-game splitmix RNG — so backend (v) is reachable from `mcts bench` and writes
> transcripts in the Phase 2 wire format.

## Phase Status

📋 Planned. Blocked by Phase `2` closure (engine output is in the Phase 2 wire format
and consumes the Phase 2 RNG mixer).

## Phase Summary

Phase `3` writes the native Haskell engine: Corridors game state as `Word64` bitboards
manipulated with `Data.Bits`, a `Word16` ply counter living in the same unboxed board
record, MCTS tree as a `MutablePrimArray s` arena of unboxed `Int32` / `Float` fields
(SoA), UCT child selection and random-rollout leaf evaluation in the `ST s` monad,
per-game tree persistence carrying inherited visit counts across moves, and a pure
search API at the boundary. The engine is correctness-first in this phase; the
optimisation stack (LLVM `-mcpu=native`, RTS tuning, `INLINABLE`+`SPECIALIZE`,
unboxed-sum representations) lands in Phase `8` once the cross-backend `verify`
baseline pins what `correct` means. `mcts bench rollouts --backend haskell` and
`mcts bench selfplay --backend haskell` run end-to-end after this phase closes.

## Sprint 3.1: Corridors Game Engine and Board Representation 📋

**Status**: Planned
**Implementation**: `src/MCTS/Engine/Board.hs`, `src/MCTS/Engine/Move.hs`,
`src/MCTS/Engine/Terminal.hs`, `src/MCTS/Engine/Legal.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Land the Corridors game state, move application, terminal-state detection (including
the ply-cap draw rule for backends (ii)–(v)), and legal-move enumeration.

### Deliverables

- `src/MCTS/Engine/Board.hs` declares an unboxed strict record per
  [00-overview.md → Hard Constraints item 20](00-overview.md):

  ```haskell
  data Board = Board
    { boardHero       :: {-# UNPACK #-} !Word64  -- hero pawn position
    , boardVillain    :: {-# UNPACK #-} !Word64  -- villain pawn position
    , boardWallsH     :: {-# UNPACK #-} !Word64  -- horizontal-wall bitboard
    , boardWallsV     :: {-# UNPACK #-} !Word64  -- vertical-wall bitboard
    , boardHeroWalls  :: {-# UNPACK #-} !Word8   -- remaining hero wall count
    , boardVillWalls  :: {-# UNPACK #-} !Word8
    , boardSideToMove :: {-# UNPACK #-} !Side
    , boardPly        :: {-# UNPACK #-} !Word16  -- ply counter
    }
  ```

- `src/MCTS/Engine/Move.hs` exposes `applyMove :: Move -> Board -> Board` plus the
  unapply path for the per-rollout scratch board reuse (the scratch path is wired
  in Phase 8; this sprint provides the pure version).
- `src/MCTS/Engine/Terminal.hs` exposes
  `isTerminal :: Word16 -> Board -> Bool` honouring the ply cap:
  `hero_wins || villain_wins || ply_count >= max_plies` per
  [00-overview.md → Hard Constraints item 9](00-overview.md). On ply-cap
  termination, `terminalEval` returns `0.0`.
- `src/MCTS/Engine/Legal.hs` exposes `legalMoves :: Board -> Vector Move` plus the
  variant that writes into a caller-provided buffer (`legalMovesInto`); the
  buffer-reuse path matters in Phase 8.
- Bitboard primitives go through `Data.Bits` (lowering to `popcnt`/`tzcnt` under
  `-fllvm` with `-optlo-mcpu=native`).

### Validation

1. Property tests: legal-move enumeration matches a brute-force reference
   implementation on 10k random board states.
2. Property tests: `applyMove` then `legalMoves` produces only legal successor
   states.
3. Property test: terminal-state detection agrees with the brute-force reference on
   10k random states.
4. Golden test: a known starting position plus a pinned move sequence produces a
   pinned terminal state.

### Remaining Work

Not started.

## Sprint 3.2: MCTS Tree Arena in `ST s` 📋

**Status**: Planned
**Implementation**: `src/MCTS/Search/Arena.hs`, `src/MCTS/Search/Node.hs`,
`src/MCTS/Search/Tree.hs`
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Land the mutable tree arena: one contiguous `MutablePrimArray s` per game, freed in
bulk at game end, with `Int32` child indices and unboxed `Float` value-backup fields.

### Deliverables

- `src/MCTS/Search/Arena.hs` declares the arena layout per
  [00-overview.md → Hard Constraints item 20](00-overview.md): structure-of-arrays
  with parallel arrays for `parentIdx :: Int32`, `firstChildIdx :: Int32`,
  `nChildren :: Word16`, `actionId :: Word8`, `visits :: Int32`,
  `valueSum :: Float`.
- `src/MCTS/Search/Node.hs` exposes the strict per-node accessors and mutators in
  `ST s`.
- `src/MCTS/Search/Tree.hs` exposes `newTree`, `freeTree`, `treeRoot`,
  `treeReroot`. Tree persistence carries inherited visit counts across moves: when
  a move is played, the chosen child becomes the new root and its accumulated
  visits are kept; the rest of the tree is discarded incrementally per
  [00-overview.md → Hard Constraints item 14](00-overview.md).
- Trees are memory-resident only — nothing is serialised between runs.

### Validation

1. Property test: round-trip via `treeReroot` then `treeRoot` preserves visit
   counts on the new root subtree.
2. Property test: arena bounds checks are correct on 10k random
   expand/select/backup sequences.
3. Unit test: tree memory is released on `freeTree`.

### Remaining Work

Not started.

## Sprint 3.3: UCT Search and Random-Rollout Leaf Evaluation 📋

**Status**: Planned
**Implementation**: `src/MCTS/Search/Uct.hs`, `src/MCTS/Search/Rollout.hs`,
`src/MCTS/Search/Search.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`

### Objective

Land the MCTS search loop: selection (UCT), expansion (legal-move generation),
simulation (random rollout to terminal), backpropagation (value update along the
ancestor path).

### Deliverables

- `src/MCTS/Search/Uct.hs` exposes `selectBestChild` implementing UCT in the
  selection phase, with deterministic tie-break on `(equity desc, non_terminal_rank
  asc)` per the project [README → Cross-backend
  verification](../README.md). The operational definition of `non_terminal_rank`
  lives in
  [../documents/engineering/determinism_contract.md → `non_terminal_rank` Operational Definition](../documents/engineering/determinism_contract.md);
  closing this sprint requires reading
  `~/MCTS_legacy/backend/core/mcts.cpp` to replace the provisional citation in
  that subsection with the precise function and line range, and confirming every
  other backend's tie-break implementation (Phases 4–6) will cite the same
  definition.
- `src/MCTS/Search/Rollout.hs` exposes the random-rollout leaf evaluator: from the
  expanded leaf, play random legal moves until terminal (positional win or ply cap),
  return the terminal evaluation (`-1.0`, `0.0`, `+1.0` from hero's perspective).
- `src/MCTS/Search/Search.hs` exposes the pure API at the boundary per
  [00-overview.md → Hard Constraints item 20](00-overview.md):

  ```haskell
  search :: GameState -> Seed -> SearchBudget -> Tree -> (Move, Tree)
  ```

  `Tree` is opaque; internally backed by the `ST` arena and frozen at the API
  boundary if tree-persistence semantics need it.
- The search runs in `ST s` internally with `runST` at the boundary; no `IORef`,
  no `MVar`, no `forkIO` inside the search.

### Validation

1. Property test: same-seed same-state same-budget produces identical `(Move,
   Tree)` (same-backend determinism, Q4).
2. Property test: total visits at the root equals the sim budget.
3. Smoke test: a fixed starting position plus a small sim budget produces a
   pinned move choice (golden, in `test/golden/haskell-search/`).

### Remaining Work

Not started.

## Sprint 3.4: Per-Game Driver and Transcript Writer 📋

**Status**: Planned
**Implementation**: `src/MCTS/Driver/Game.hs`, `src/MCTS/Driver/Transcript.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/transcript_format.md`

### Objective

Land the per-game driver: from a `(master_seed, game_index)` pair, run an adversarial
self-play game using the Sprint 3.3 search loop, writing the transcript to the cache
in the Phase 2 wire format.

### Deliverables

- `src/MCTS/Driver/Game.hs` exposes `runGame :: GameInputs -> App Transcript`,
  where `GameInputs` carries `master_seed`, `game_index`, `max_plies`,
  `sim_budget`, the backend selector, and the threading mode (the per-game
  driver is single-threaded internally per
  [00-overview.md → Hard Constraints item 2](00-overview.md)).
- Per-game seed comes from `MCTS.Rng.Mix.mix master_seed game_index` (Phase 2
  Sprint 2.5).
- `src/MCTS/Driver/Transcript.hs` exposes `writeTranscript :: Transcript -> App
  TranscriptRef`, computing the hash, resolving the cache root, and writing
  `<sha>.tr` atomically (write to temp, fsync, rename).
- For random-rollout-only benchmark (`mcts bench rollouts`), the driver runs a
  pure-engine loop with no tree at all: play random games end-to-end as fast as
  the engine allows.
- The native Haskell backend (v) honours the paired build-target scheme per
  [../README.md → Cross-backend verification → Compile-time toggle for
  instrumentation](../README.md). The toggle is a Cabal flag
  `instrumentation: True|False` declared in `mcts.cabal`; the driver module
  `src/MCTS/Driver/Game.hs` uses CPP `#ifdef MCTS_INSTRUMENTED` to splice in the
  transcript writer and the `readVisits` instrumentation hook. Two library
  targets are produced — `mcts-bench` (Cabal flag off) and `mcts-instrumented`
  (Cabal flag on). The engine library (search, rollout, board, RNG) is one
  shared artefact between them; only the driver compiles twice. `mcts bench`
  links against `mcts-bench`; `mcts verify`, `mcts play`, `mcts inspect replay`
  link against `mcts-instrumented`. The bench library has nothing to disable,
  so the instrumentation code literally does not exist in it.

### Validation

1. Same-backend determinism (Q4): `runGame` with the same `(master_seed,
   game_index)` produces an identical transcript across runs.
2. The transcript round-trips through `encode . decode` per Phase 2 Sprint 2.1.
3. The transcript filename is `sha256(run_config).tr` with the canonical
   `run_config` byte encoding.

### Remaining Work

Not started.

## Sprint 3.5: `mcts bench rollouts` and `mcts bench selfplay` for `--backend haskell` 📋

**Status**: Planned
**Implementation**: `src/MCTS/CLI/Bench.hs`, `src/MCTS/CLI/Spec.hs` (Bench subtree)
**Docs to update**: `documents/engineering/cli_command_surface.md`

### Objective

Wire the bench command into the CLI for `--backend haskell` end-to-end: parse, plan,
prerequisite-check, dispatch through a worker pool (single or multi), measure
wall-clock time from a single `Data.Time.Clock.getMonotonicTimeNSec`, emit
`games/sec` and `sims/sec`.

### Deliverables

- `src/MCTS/CLI/Bench.hs` owns `mcts bench rollouts` and `mcts bench selfplay` for
  the `BenchOptions` schema in the project [README → CLI command
  topology](../README.md):
  - `benchBackends :: NonEmpty Backend` — Phase 3 supports `Haskell` only;
    Phases 4–6 add the four FFI backends.
  - `benchRng :: RngSource` — `NativeRng` or `CppRng` (Phase 3 supports
    `NativeRng` only on the Haskell side; `CppRng` lands in Phase 4 after the
    FFI bridge exposes `std::mt19937_64`).
  - `benchThreading :: Threading` — `SingleThreaded` or `MultiThreaded { workers
    = N }`; default `MultiThreaded { workers = 8 }`.
  - `benchGames`, `benchSeed`, `benchMaxPlies` (default 200; ignored for backend
    (i)), `benchSims` (default `FixedSims 10_000`).
  - The `--sims` flag parses two forms per
    [../README.md → CLI command topology](../README.md): `--sims N` ⇒
    `FixedSims N`; `--sims N0:N1` ⇒ `RampedSims N0 N1` (initial-move budget `N0`,
    per-move budget `N1` thereafter). The colon-separated form is the on-wire
    `RampedSims` discriminator that the Phase 2 header layout encodes as
    `initial_sims != per_move_sims`.
- The worker pool is a `concurrently` over the games; each worker calls `runGame`
  for one `(master_seed, game_index)` at a time. Per
  [00-overview.md → Hard Constraints items 2–4](00-overview.md), per-game RNG
  streams are independent of worker scheduling.
- **Monotonic clock contract** per
  [../README.md → Benchmarks](../README.md) (line 177). The clock is
  `Data.Time.Clock.getMonotonicTimeNSec` (monotonic, nanosecond resolution).
  It is started inside the Haskell driver **just before the first game is
  dispatched** into the worker pool and stopped **just after the last game's
  transcript returns through the FFI** (for native Haskell, "returns from the
  in-process `runGame`"). All five backends are timed by this single clock so
  cross-backend numbers are directly comparable. An integration test under
  the `mcts-integration` stanza intercepts both call sites with a test-hook
  field on `Env` and asserts the start/stop bracket wraps exactly the
  dispatch loop — not the prerequisite-check phase, not the worker-pool
  setup, not the final JSON/table rendering. Deliverable closes only when
  this assertion is wired.
- The bench result renders through `--format json|table|plain` (Phase 1 Sprint 1.9
  established the renderers).
- The bench command is **not** a Plan/Apply command (no external state
  mutation); but it does consume the `prerequisiteRegistry` to check toolchain
  prereqs (GHC 9.14.1 available, RTS opts honoured).

### Validation

1. `mcts bench rollouts --backend haskell --threading single --rng native --games
   100 --seed 42` runs to completion and emits a games/sec number.
2. `mcts bench selfplay --backend haskell --threading multi --workers 8 --rng
   native --games 32 --seed 42 --sims 1000` runs to completion.
3. Same-backend determinism (Q4): the transcripts in `.mcts-cache/transcripts/`
   for `--games 32 --threading single` and `--games 32 --threading multi
   --workers 8` are identical sets (same 32 sha-addressed files); only wall-clock
   differs.

### Remaining Work

Not started.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/determinism_contract.md` — extend with the engine-side
  story: same-backend determinism (Q4), the per-game splitmix derivation, the
  tree-persistence-is-deterministic property.
- `documents/engineering/transcript_format.md` — confirm that the Haskell engine
  writes the format Phase 2 specified.
- `documents/engineering/cli_command_surface.md` — fill in the `mcts bench` matrix
  for `--backend haskell`.
- `documents/engineering/compiler_runtime_tuning.md` — Phase 3 establishes the
  correctness baseline; Phase 8 adds the optimisation stack. This doc gains a
  Haskell-engine subsection noting the in-scope Phase 8 deliverables.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md` Backend (v) row updates from `📋 Planned` to `🔄 Active`
  on Sprint 3.1 start and `✅ Done` on Sprint 3.5 closure.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [phase-2-transcript-codec-and-determinism.md](phase-2-transcript-codec-and-determinism.md)
- [phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
