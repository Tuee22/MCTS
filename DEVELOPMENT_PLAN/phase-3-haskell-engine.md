# Phase 3: Backend (v) Haskell Engine

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md),
[../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md)
**Generated sections**: none

> **Purpose**: Land the native Haskell Corridors engine — bitboard game state, MCTS
> search and rollout core in `ST s`, tree-arena primitives, the pure search API, and the
> per-game splitmix RNG — so backend (v) is reachable from `mcts bench` and writes
> transcripts in the Phase 2 wire format.

## Phase Status

✅ **Done**. The Haskell backend correctness surface remains closed: it has a
deterministic logical Corridors driver,
strict `Word64` board slots/bitsets with path-preserving wall checks, recursive UCT
search in `ST s` over a structure-of-arrays `STUArray` arena, transcript writing,
monotonic bench timing, logical envelope stamping through `MCTS.Engine.Envelope`,
`non_terminal_rank` implemented and pinned to the imported legacy source for
inspection/tests, current verifier-cohort UCT tie-breaking by action ID/highest
visit count per Sprint `7.2`, in-process equity recompute, and explicit
terminal-playout/search-iteration benchmark primitives. Across-move tree persistence
and per-rollout scratch boards remain profile-driven future work outside the current
closed baseline; post-link build-id stamping and performance parity are closed in
Phase `8`; foreign backend dispatch and foreign recompute coverage remain owned by
Phases `4` through `7`. Sprint `3.8` supplies the primitive benchmark leaves that
Phase `7` uses to refactor Q1/Q5 without overloading the legacy `bench rollouts`
played-game workload.

## Phase Summary

Phase `3` writes the native Haskell engine correctness baseline: Corridors game state
as strict `Word64` pawn slots and wall bitsets manipulated with `Data.Bits`, a
`Word16` ply counter living in the same board record, MCTS tree state as a
structure-of-arrays `STUArray` arena of unboxed fields, UCT child selection and
random-rollout leaf evaluation in the `ST s` monad, and a pure search API at the
boundary. The current driver allocates a fresh arena for each per-move search; the
`treeReroot` arena primitive is tested but is not an across-move persistence path in the
closed baseline. The optimization stack and performance proof land in Phase `8` once
the cross-backend `verify`
baseline pins what `correct` means. `mcts bench rollouts --backend haskell`,
`mcts bench selfplay --backend haskell`, `mcts bench terminal-playouts --backend
haskell`, and `mcts bench search-iters --backend haskell` run end-to-end; the
primitive metric leaves follow
[../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md).

## Sprint 3.1: Corridors Game Engine and Board Representation ✅

**Status**: Done
**Implementation**: `src/MCTS/Engine.hs`, `src/MCTS/Types.hs`,
`src/MCTS/Notation.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Land the Corridors game state, move application, terminal-state detection (including
the ply-cap draw rule for backends (ii)–(v)), and legal-move enumeration.

### Deliverables

- `src/MCTS/Engine.hs` declares the strict board representation per
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

- `boardPly` initialises to `0` and is incremented by `applyMove` **after** the
  move is applied. `plyCount == max_plies` therefore corresponds to a draw if no
  positional win has been recorded; `isTerminal` is checked next, before the next
  move is selected. The counter is restored to its start-of-rollout value as part of
  the per-rollout scratch snapshot/undo path (wired in Phase 8).
- `src/MCTS/Engine.hs` exposes `applyMove :: Action -> Board -> Board` plus the
  unapply path for the per-rollout scratch board reuse (the scratch path is wired
  in Phase 8; this sprint provides the pure version).
- `src/MCTS/Engine.hs` exposes
  `isTerminal :: Word16 -> Board -> Bool` honouring the ply cap:
  `hero_wins || villain_wins || ply_count >= max_plies` per
  [00-overview.md → Hard Constraints item 9](00-overview.md). On ply-cap
  termination, `terminalEval` returns `0.0`. `isTerminal` is called after each
  `applyMove` inside the rollout loop and immediately before each selection step
  inside the UCT descent; a terminal node is never expanded.
- `src/MCTS/Engine.hs` exposes `legalMoves :: Board -> [Action]`; a
  caller-provided-buffer variant is deferred to Phase `8` profiling work if the
  current list boundary remains hot.
- The legal-move generator must enforce the Corridors path-existence invariant:
  walls cannot fully enclose either player. A wall placement is legal only if
  both pawns retain at least one
  path to their respective goal rows after the placement. The invariant is
  checked by a flood-fill (BFS) on the wall-bitboard-derived graph against each
  candidate wall placement; pawn moves do not need this check. The brute-force
  property test in Validation step 1 below covers this rule on the random sample.
- Bitboard primitives go through `Data.Bits` under the active `-fllvm` backend;
  the extra native LLVM CPU flags remain deferred by Phase `8` on the current
  aarch64 container.

### Validation

1. Property tests: legal-move enumeration matches a brute-force reference
   implementation on 10k random board states.
2. Property tests: `applyMove` then `legalMoves` produces only legal successor
   states.
3. Property test: terminal-state detection agrees with the brute-force reference on
   10k random states.
4. Golden test: a known starting position plus a pinned move sequence produces a
   pinned terminal state.

### Closure Notes

- Baseline landed: `src/MCTS/Engine.hs` has a deterministic Corridors board,
  legal-move generation, path-preserving wall checks, move application, side toggling,
  ply counting, terminal detection, and draw rendering through the transcript path.
  The `mcts-unit` stanza now asserts that every chosen move from a recorded game
  was actually legal on the matching reconstructed board (successor-state legality),
  that chosen moves are always represented in their visit list, and that `runGame`
  is reproducible for fixed inputs (Q4 same-backend determinism on a small fixture).
- Tuple/list board storage has been replaced with strict `Word64` pawn slots and
  horizontal/vertical wall bitsets in `MCTS.Engine`. The single-module engine baseline
  remains the Phase `3` ownership boundary; Phase `8` owns further representation changes
  driven by profiling.
- Baseline landed: the `mcts-unit` stanza now walks 10 splitmix-derived
  random pawn-walk seeds × 30 steps each (capped at 200 reachable boards)
  and asserts three invariants across the resulting random sample: (a)
  every legal move applied to a board produces a successor that is either
  legal or terminal; (b) `legalMoves` returns no action-id duplicates;
  (c) every terminal board has an empty legal-move set. The full 10k
  brute-force reference comparison lands with Sprint 7.1 property-based
  coverage.
- The known-position coverage over a pinned legal move sequence is a semantic
  unit assertion; Sprint `8.8` removes any remaining checked-in generated
  baseline dependency.

### Remaining Work

None.

## Sprint 3.2: MCTS Tree Arena in `ST s` ✅

**Status**: Done
**Implementation**: `src/MCTS/Search/Arena.hs`
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Land the mutable tree arena: one structure-of-arrays `STUArray` arena per game,
freed in bulk at game end, with `Int32` child indices and unboxed `Float`
value-backup fields.

### Deliverables

- `src/MCTS/Search/Arena.hs` declares the arena layout per
  [00-overview.md → Hard Constraints item 20](00-overview.md): structure-of-arrays
  with parallel arrays for `parentIdx :: Int32`, `firstChildIdx :: Int32`,
  `nChildren :: Word16`, `actionId :: Word8`, `visits :: Int32`,
  `valueSum :: Float`.
- `src/MCTS/Search/Arena.hs` exposes the strict per-node accessors and mutators in
  `ST s`, plus `newArena`, `freeArena`, `treeRoot`, and `treeReroot`. Full tree
  persistence across played moves is deferred to Phase `8`; the current correctness
  baseline allocates a fresh arena per per-move search.
- Trees are memory-resident only — nothing is serialised between runs.

### Validation

1. Property test: `treeReroot` returns the selected node and preserves that node's
   visit count and value sum inside the arena.
2. Property test: arena bounds checks are correct on 10k random
   expand/select/backup sequences.
3. Unit test: tree memory is released on `freeTree`.

### Closure Notes

- Baseline landed: `src/MCTS/Search/Arena.hs` provides the SoA arena
  (`parentIdx`, `firstChildIdx`, `nChildren`, `actionId`, `visits`,
  `valueSum`) as parallel `STUArray` arrays with a `STRef` cursor.
  Operations exposed: `newArena`, `freeArena`, `allocNode`, `readVisits`,
  `addVisits`, `readValueSum`, `addValueSum`, `readActionId`,
  `readParent`, `readFirstChild`, `readNumChildren`, `setChildren`,
  `treeRoot`, `treeReroot`, `bulkVisits`. The `array` package is now a
  declared dependency. The `mcts-unit` stanza covers (a) `treeReroot`
  round-trips inherited visits and value-sums for the new root, (b) the
  arena cursor tracks allocation count, (c) `bulkVisits` matches
  per-slot reads, (d) `freeArena` resets the cursor and the next
  `allocNode` starts at slot 0.
- The `MutableByteArray#` migration path (a hand-rolled arena with per-rollout
  scratch) remains profile-driven and is not required by the current measured
  baseline. The API exported by `MCTS.Search.Arena` remains the boundary; the
  underlying representation can change behind it.

### Remaining Work

None.

## Sprint 3.3: UCT Search and Random-Rollout Leaf Evaluation ✅

**Status**: Done
**Implementation**: `src/MCTS/Search/UCT.hs`, `src/MCTS/Search/Arena.hs`,
`src/MCTS/Engine.hs`, `src/MCTS/Driver.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`

### Objective

Land the MCTS search loop: selection (UCT), expansion (legal-move generation),
simulation (random rollout to terminal), backpropagation (value update along the
ancestor path).

### Deliverables

- `src/MCTS/Search/UCT.hs` implements UCT in the selection phase. The current
  verifier-cohort contract breaks equal UCT scores by action ID and chooses the
  final root action by highest visit count, then action ID, per the project
  [README → Cross-backend verification](../README.md). `non_terminal_rank`
  remains implemented and cited for legacy inspection coverage; it is no longer
  part of the `(ii)..(v)` verifier-cohort tie-break after Sprint `7.2`.
- `src/MCTS/Search/UCT.hs` owns the random-rollout leaf evaluator: from the
  expanded leaf, play random legal moves until terminal (positional win or ply cap),
  return the terminal evaluation (`-1.0`, `0.0`, `+1.0` from hero's perspective).
- The current pure boundary is
  `uctSearch :: Board -> Word64 -> Int -> Int -> (Action, [(Action, Word32)])`;
  internally it uses `runST` with the mutable arena.
- The search runs in `ST s` internally with `runST` at the boundary; no `IORef`,
  no `MVar`, no `forkIO` inside the search.

### Validation

1. Property test: same-seed same-state same-budget produces identical `(Move,
   Tree)` (same-backend determinism, Q4).
2. Property test: total visits at the root equals the sim budget.
3. Smoke test: a fixed starting position plus a small sim budget produces a
   pinned move choice asserted semantically by the unit suite.

### Closure Notes

- Baseline landed: `src/MCTS/Search/UCT.hs` exposes
  `uctSearch :: Board -> Word64 -> Int -> Int -> (Action, [(Action, Word32)])`
  that allocates a tree in `MCTS.Search.Arena`, pre-expands every legal root
  child, runs `nSims` random rollouts seeded by `splitmix`, backpropagates the
  rollout outcome up the chosen-child path, and returns the highest-visit
  action plus the action-id-sorted visit table. The driver
  (`MCTS.Driver.uctChooseMove`) now dispatches every per-move search through
  this entrypoint with a backend-derived seed salt under `--rng native`
  (zero salt under `--rng cpp` so cross-backend visits are bit-equal).
  The `mcts-unit` stanza asserts: (a) determinism for fixed inputs,
  (b) chosen action is legal, (c) visit list covers every legal move,
  (d) visits sorted ascending by action_id, (e) total root-child visits
  equals the sim budget.
- The current UCT recursively descends through lazily expanded children in the
  `ST` arena and backpropagates along the descent path. Across-move tree persistence
  and a per-rollout scratch board remain future profile-driven work, not part of the
  current measured baseline; representation changes stay behind the exported API.
- `non_terminal_rank` is now implemented in `MCTS.Engine` and cited in
  `documents/engineering/determinism_contract.md` against
  `cpp-legacy/legacy-core/board.cpp:395` and
  `cpp-legacy/legacy-core/mcts.hpp:258`-`266`, `400`-`421`; Sprint `7.2`
  keeps that value as a tested legacy reference while removing it from the
  verifier-cohort UCT tie-break.
- `mcts-unit` covers same-seed determinism, legal chosen moves, legal visit-list actions,
  sorted visit rows, root-child visit totals, the balanced initial `nonTerminalRank`, and
  the known-position engine semantic fixture.

### Remaining Work

None.

## Sprint 3.4: Per-Game Driver and Transcript Writer ✅

**Status**: Done
**Implementation**: `src/MCTS/Driver.hs`, `src/MCTS/Transcript.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/transcript_format.md`

### Objective

Land the per-game driver: from a `(master_seed, game_index)` pair, run an adversarial
self-play game using the Sprint 3.3 search loop, writing the transcript to the cache
in the Phase 2 wire format.

### Deliverables

- `src/MCTS/Driver.hs` exposes `runGame :: RunInputs -> Word32 -> GameTranscript`
  and `runBatch :: RunInputs -> IO (Either String BatchResult)`,
  where `RunInputs` carries `inputSeed`, `inputMaxPlies`, `inputSims`,
  the backend selector, cache override, and the threading mode; the `Word32`
  argument is the game index. The per-game driver is single-threaded internally per
  [00-overview.md → Hard Constraints item 2](00-overview.md)).
- Per-game seed comes from `MCTS.Rng.Mix.mix master_seed game_index` (Phase 2
  Sprint 2.5).
- `src/MCTS/Transcript.hs` exposes `writeTranscript`, computing the hash, resolving
  the cache root, and writing
  `<sha>.tr` atomically (write to temp, fsync, rename).
- For the legacy `mcts bench rollouts` command, the current logical baseline reuses
  the UCT dispatch with a one-simulation budget so the transcript and visit-table
  path stays identical to self-play. This is a played-game workload, not terminal
  playout throughput. Sprint `3.8` adds the explicit lower-level benchmark
  primitives required by the metric taxonomy.
- The native Haskell backend (v) uses the single container-built `mcts` binary in
  the current correctness baseline. Visit tables are available directly from
  `MCTS.Search.UCT.uctSearch`, so the paired bench/instrumented split is not part
  of the Phase `3` closure; any future Haskell split is profiling-driven Phase `8`
  work.

### Validation

1. Same-backend determinism (Q4): `runGame` with the same `(master_seed,
   game_index)` produces an identical determinism payload across runs.
2. The transcript round-trips through `encode . decode` per Phase 2 Sprint 2.1.
3. The transcript filename is `sha256(run_config).tr` with the canonical
   `run_config` byte encoding.

### Closure Notes

- Baseline landed: `MCTS.Driver.runGame`, `runBatch`, `makeRunConfig`, per-game
  splitmix seeding, transcript writing, and logical envelope stamping exist.
- The game loop dispatches each per-move choice through `MCTS.Search.UCT.uctSearch`.
  The closed baseline allocates a fresh arena per move; across-move tree persistence is
  not implemented.
- Atomic transcript writes landed in Sprint 2.2; keep the driver covered by the
  transcript write/read tests as the backend dispatch changes.
- The paired bench/instrumented build-target split is not retained for the logical
  correctness baseline; instrumentation surfaces are available through the single
  container-built `mcts` binary until profiling requires a split.
- Same-backend determinism, transcript roundtrip, and filename/hash behavior are covered
  by `mcts-unit`, `mcts-integration`, and the Phase `2` transcript cache tests.

### Remaining Work

None.

## Sprint 3.5: `mcts bench rollouts` and `mcts bench selfplay` for `--backend haskell` ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Bench.hs`, `src/MCTS/CLI/Spec.hs` (Bench subtree)
**Docs to update**: `documents/engineering/cli_command_surface.md`

### Objective

Wire the original game-level bench command into the CLI for `--backend haskell`
end-to-end: parse, plan,
prerequisite-check, dispatch through a worker pool (single or multi), measure
wall-clock time from a single `GHC.Clock.getMonotonicTimeNSec`, emit
`games/s` as the only played-game throughput unit.

### Deliverables

- `src/MCTS/CLI/Bench.hs` owns `mcts bench rollouts` and `mcts bench selfplay`
  over the current `BenchCommand` plus shared `RunInputs` surface:
  - parsed backend cohort `[Backend]` — Phase 3 lands the `Haskell` baseline;
    later backend phases extend the same surface to the foreign backends.
  - `inputRng :: RngSource` — `NativeRng` or `CppRng`.
  - `inputThreading :: Threading` — `SingleThreaded` or `MultiThreaded N`;
    default `MultiThreaded 8`.
  - `inputGames`, `inputSeed`, `inputMaxPlies` (default 200 and recorded in the
    transcript header), `inputSims` (default `FixedSims 10_000` on the CLI).
  - The `--sims` flag parses two forms per
    [../documents/engineering/cli_command_surface.md → Global Option Defaults](../documents/engineering/cli_command_surface.md):
    `--sims N` ⇒
    `FixedSims N`; `--sims N0:N1` ⇒ `RampedSims N0 N1` (initial-move budget `N0`,
    per-move budget `N1` thereafter). The colon-separated form is the on-wire
    `RampedSims` discriminator that the Phase 2 header layout encodes as
    `initial_sims != per_move_sims`.
- The worker pool is a `concurrently` over the games; each worker calls `runGame`
  for one `(master_seed, game_index)` at a time. Per
  [00-overview.md → Hard Constraints items 2–4](00-overview.md), per-game RNG
  streams are independent of worker scheduling.
- **Monotonic clock contract** per
  [../documents/engineering/determinism_contract.md → Monotonic Clock Contract](../documents/engineering/determinism_contract.md).
  The clock is
  `GHC.Clock.getMonotonicTimeNSec` (monotonic, nanosecond resolution).
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

1. `docker compose run --rm mcts mcts bench rollouts --backend haskell --threading
   single --rng native --games 100 --seed 42` runs to completion and emits a
   `games/s` number.
2. `docker compose run --rm mcts mcts bench selfplay --backend haskell --threading
   multi --workers 8 --rng native --games 32 --seed 42 --sims 1000` runs to
   completion.
3. Same-backend determinism (Q4): the transcripts in `.mcts-cache/transcripts/`
   for `--games 32 --threading single` and `--games 32 --threading multi
   --workers 8` decode to identical determinism payload sets; only wall-clock and
   dispatcher provenance metadata differ.

### Closure Notes

- Baseline landed: `mcts bench rollouts` and `mcts bench selfplay` run through the
  logical Haskell backend, write transcripts, and render table/JSON game-level
  throughput output using `games/s` only. The `bench rollouts` name is legacy and
  does not mean terminal
  `playouts/s`.
  The bench runner now reads the pinned monotonic clock
  (`GHC.Clock.getMonotonicTimeNSec`) via the `monotonicNanos` helper. The
  test-injectable variant `runBenchWithClock` accepts any `IO Word64`
  clock, and the `mcts-unit` stanza asserts the bracket calls the clock
  exactly twice per backend (start + stop) under the test hook.
- `MultiThreaded N` dispatch now runs game generation through a
  deterministic worker pool in `MCTS.Driver`, restores game order before
  transcript hashing/writing, and preserves the single monotonic-clock bracket
  around each backend batch.
- The comma-separated multi-backend bench path remains covered; the parser returns the
  requested backend list and the runner iterates it internally.
- Final report-card budgets are owned by Phase `7` and the Haskell parity proof by
  Phase `8`.

### Remaining Work

None.

## Sprint 3.6: Backend (v) Engine Envelope and Foreign-Engine Recompute ✅

**Status**: Done
**Implementation**: `src/MCTS/Engine/Envelope.hs`, `src/MCTS/Driver.hs`,
`src/MCTS/Transcript.hs`,
`src/MCTS/Verify/Envelope.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/backend_ffi_contract.md`,
`documents/engineering/transcript_format.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Backend (v) Haskell populates its engine envelope from build-time
constants and exposes a foreign-engine recompute entry point so the
REPL's multi-backend overlay can recompute equity series for any
transcript using the in-process Haskell engine. See
[../documents/engineering/determinism_contract.md → Engine Envelope](../documents/engineering/determinism_contract.md)
and
[../documents/engineering/backend_ffi_contract.md → Foreign-Engine
Recompute](../documents/engineering/backend_ffi_contract.md).

### Deliverables

- `src/MCTS/Engine/Envelope.hs` constructs the current logical `Envelope` for the
  in-process Haskell backend. The Phase `3` baseline stamps deterministic
  cohort-invariant fields and logical per-backend-slot stand-ins; post-link
  `engine_build_id`, CPU-feature, FP-environment, and richer compiler metadata
  capture remain Phase `8` performance/build-harness work.
- `src/MCTS/Engine/Recompute.hs` — the in-process foreign-engine
  recompute path: given a transcript's bytes, parse the `RunConfig`,
  replay the search from move 0, emit `(move_index, n_alternatives,
  action_id[], visits[], equity[])` records that the REPL writes into
  an `.eq` sidecar (Sprint 2.7). Under `--rng cpp`, same-backend
  originator recompute hard-asserts chosen-action and visit agreement
  with the transcript at every move; mismatch aborts with
  `AppError RecomputeMismatch (backend, game_id, move_index,
  recomputed_record, recorded_record)`. Foreign-view recompute emits an
  `EqStream` for divergence scoring instead of claiming originator identity,
  per
  [../documents/engineering/determinism_contract.md → Recompute Mismatch Output](../documents/engineering/determinism_contract.md).
- The Haskell driver's existing search loop is invoked from this
  recompute path with an instrumentation hook to record per-move
  equity values into a streaming buffer.

### Validation

- `mcts-integration`: invoke `inspect replay <hash>` on a transcript
  produced by a different backend (e.g., a `cpp-imperative`
  transcript), trigger the haskell column with `r`, assert the
  sidecar `.eq` writes successfully, and assert disagreement is surfaced
  as foreign-view divergence evidence rather than `RecomputeMismatch`.
- `mcts-integration`: produce a transcript with backend (v); on
  subsequent `inspect replay` open, the originator `.eq` is read if
  the live binary's envelope matches.

### Closure Notes

- Baseline landed: the in-process backend stamps the full v1 envelope
  via `MCTS.Driver.makeLogicalEnvelope` (cohort-invariant + per-backend
  slot fields). `src/MCTS/Engine/Recompute.hs` exposes
  `recomputeEquities :: Transcript -> Either AppError [EqRecord]` and
  `recomputeEqStream :: String -> String -> Transcript -> Either
  AppError EqStream`. Under `--rng cpp`, same-backend originator recompute
  hard-asserts chosen-action and visit equality with the transcript at every
  move and short-circuits with `AppError RecomputeMismatch` on the first
  disagreement, while foreign-view recompute emits an `EqStream` for divergence
  scoring, exactly per
  [../documents/engineering/determinism_contract.md → Recompute Mismatch Output](../documents/engineering/determinism_contract.md).
  The `mcts-unit` stanza covers (a) the recompute produces one
  `EqRecord` per recorded move, (b) chosen-move sequence preserved,
  (c) transcript hash and build id are stamped on the stream, and
  (d) intentionally corrupting the visit counts triggers
  `RecomputeMismatch`.
- `src/MCTS/Engine/Envelope.hs` now owns construction of the Haskell logical engine
  envelope used by the driver. Post-link `engine_build_id` patching and richer build
  metadata capture are owned by Phase `8`'s performance/build harness.
- Originator cache hits are covered by the Phase `2` sidecar integration baseline.
  Foreign-view recompute coverage waits for real foreign backend dispatch in Phases `4`
  through `7`.

### Remaining Work

None.

## Sprint 3.7: Rollout Byte-Consumption Realignment ✅

**Status**: Done
**Implementation**: `src/MCTS/Search/UCT.hs`, `test/unit/Main.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/haskell_code_guide.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the Haskell rollout move picker implement the documented signed-`Int`
modulo byte-consumption rule used by the cross-backend determinism contract.

### Deliverables

- `MCTS.Search.UCT.rollout` chooses the rollout action with signed `Int64`
  remainder semantics over the consumed `Word64` draw before mapping into the legal
  move list.
- The implementation keeps the existing deterministic seed schedule and legal-move
  order while removing the unsigned modulo contradiction.
- The determinism contract remains explicit that byte consumption, not rejection
  sampling, is the verification surface.

### Validation

- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

Closed on 2026-05-24 after the rollout move picker and determinism docs matched the
documented signed-modulo rule.

## Sprint 3.8: Terminal Playout and Search-Iteration Benchmarks ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Bench.hs`, `src/MCTS/Search/UCT.hs`,
`src/MCTS/FFI/Common.hs`, `src/MCTS/App.hs`, `src/MCTS/CLI/Command.hs`,
`src/MCTS/CLI/Parser.hs`, `src/MCTS/CLI/Spec.hs`,
`cpp-legacy/c-abi/mcts_cpp_legacy.{h,cc}`,
`cpp-imperative/engine/search.{hpp,cpp}`,
`cpp-imperative/c-abi/mcts_cpp_imperative.{h,cc}`,
`cpp-functional/engine/search.{hpp,cpp}`,
`cpp-functional/c-abi/mcts_cpp_functional.{h,cc}`, `rust/src/search.rs`,
`rust/src/c_abi.rs`
**Docs to update**: `../documents/engineering/benchmark_metrics.md`,
`../documents/engineering/cli_command_surface.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Provide benchmark primitives whose counted units match the metric taxonomy:
terminal playout throughput (`playouts/s`) and search-iteration throughput
(`search-iters/s`).

### Deliverables

- `mcts bench terminal-playouts` runs direct random playouts from explicit board
  positions without allocating or updating an MCTS tree.
- `mcts bench search-iters` times UCT iterations directly at fixed board
  positions and reports observed `search-iters/s`.
- Renderer output that avoids derived or ambiguous simulation-rate values.
- Foreign-backend dynamic ABI entry points measure the same units as the Haskell
  path, including backend (i) where the legacy-envelope gate exercises all five slots.

### Validation

- `docker compose run --rm --build mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts bench terminal-playouts --backend haskell --rng native --seed 42`
- `docker compose run --rm mcts mcts bench search-iters --backend haskell --rng native --seed 42`
- `docker compose run --rm mcts mcts bench terminal-playouts --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --rng native --count 16 --seed 42`
- `docker compose run --rm mcts mcts bench search-iters --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --rng native --count 16 --seed 42`

### Remaining Work

None.

### Closure Notes

Closed on 2026-05-24 after the primitive CLI leaves, Haskell runner, dynamic
foreign benchmark ABI, C++ and Rust backend hooks, parser/registry entries, and
unit coverage landed. Sprint `7.8` later wired these primitive rows into the
report card.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/determinism_contract.md` — extend with the engine-side
  story: same-backend determinism (Q4), the per-game splitmix derivation, the
  fresh per-move arena scope, and deterministic replay property.
- `documents/engineering/transcript_format.md` — confirm that the Haskell engine
  writes the format Phase 2 specified.
- `documents/engineering/cli_command_surface.md` — fill in the `mcts bench` matrix
  for `--backend haskell`.
- `documents/engineering/benchmark_metrics.md` — define the terminal-playout and
  search-iteration primitives Sprint `3.8` adds.
- `documents/engineering/compiler_runtime_tuning.md` — Phase 3 establishes the
  correctness baseline; Phase 8 adds the optimisation stack. This doc gains a
  Haskell-engine subsection noting the in-scope Phase 8 deliverables.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md` Backend (v) row reflects the Phase `3` correctness baseline
  closure while keeping Phase `8` performance-parity work visible.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [phase-2-transcript-codec-and-determinism.md](phase-2-transcript-codec-and-determinism.md)
- [phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
