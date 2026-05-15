# Phase 3: Backend (v) Haskell Engine

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Land the native Haskell Corridors engine — bitboard game state, MCTS
> search and rollout core in `ST s`, tree persistence, the pure search API, and the
> per-game splitmix RNG — so backend (v) is reachable from `mcts bench` and writes
> transcripts in the Phase 2 wire format.

## Phase Status

✅ **Done**. The Haskell backend has a deterministic logical Corridors driver,
strict `Word64` board slots/bitsets with path-preserving wall checks, recursive UCT
search in `ST s` over a structure-of-arrays `STUArray` arena, transcript writing,
monotonic bench timing, logical envelope stamping through `MCTS.Engine.Envelope`,
deterministic `non_terminal_rank` tie-breaking pinned to the imported legacy source,
and in-process equity recompute. Tree persistence, per-rollout scratch boards,
post-link build-id stamping, and performance parity remain owned by Phase `8`; foreign
backend dispatch and foreign recompute coverage remain owned by Phases `4` through `7`.

## Phase Summary

Phase `3` writes the native Haskell engine correctness baseline: Corridors game state
as strict `Word64` pawn slots and wall bitsets manipulated with `Data.Bits`, a
`Word16` ply counter living in the same board record, MCTS tree state as a
structure-of-arrays `STUArray` arena of unboxed fields, UCT child selection and
random-rollout leaf evaluation in the `ST s` monad, and a pure search API at the
boundary. The optimization stack, tree persistence across played moves, per-rollout
scratch boards, and performance proof land in Phase `8` once the cross-backend `verify`
baseline pins what `correct` means. `mcts bench rollouts --backend haskell` and
`mcts bench selfplay --backend haskell` run end-to-end after this phase closes.

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

- `boardPly` initialises to `0` and is incremented by `applyMove` **after** the
  move is applied. `plyCount == max_plies` therefore corresponds to a draw if no
  positional win has been recorded; `isTerminal` is checked next, before the next
  move is selected. The counter is restored to its start-of-rollout value as part of
  the per-rollout scratch snapshot/undo path (wired in Phase 8).
- `src/MCTS/Engine/Move.hs` exposes `applyMove :: Move -> Board -> Board` plus the
  unapply path for the per-rollout scratch board reuse (the scratch path is wired
  in Phase 8; this sprint provides the pure version).
- `src/MCTS/Engine/Terminal.hs` exposes
  `isTerminal :: Word16 -> Board -> Bool` honouring the ply cap:
  `hero_wins || villain_wins || ply_count >= max_plies` per
  [00-overview.md → Hard Constraints item 9](00-overview.md). On ply-cap
  termination, `terminalEval` returns `0.0`. `isTerminal` is called after each
  `applyMove` inside the rollout loop and immediately before each selection step
  inside the UCT descent; a terminal node is never expanded.
- `src/MCTS/Engine/Legal.hs` exposes `legalMoves :: Board -> Vector Move` plus the
  variant that writes into a caller-provided buffer (`legalMovesInto`); the
  buffer-reuse path matters in Phase 8.
- The legal-move generator must enforce the Corridors path-existence invariant per
  [../README.md → Game: Corridors](../README.md): walls cannot fully enclose
  either player. A wall placement is legal only if both pawns retain at least one
  path to their respective goal rows after the placement. The invariant is
  checked by a flood-fill (BFS) on the wall-bitboard-derived graph against each
  candidate wall placement; pawn moves do not need this check. The brute-force
  property test in Validation step 1 below covers this rule on the random sample.
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
- The known-position golden over a pinned legal move sequence now lives at
  `test/golden/engine/known-position.txt`.

## Sprint 3.2: MCTS Tree Arena in `ST s` ✅

**Status**: Done
**Implementation**: `src/MCTS/Search/Arena.hs`
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
- The Phase 8 `MutableByteArray#` migration path (a hand-rolled arena with
  per-rollout scratch) lands when profiling justifies it. The API exported
  by `MCTS.Search.Arena` remains the boundary; the underlying
  representation flips behind it.

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
  `ST` arena and backpropagates along the descent path. The Phase `8` optimized
  version owns tree persistence across played moves, a per-rollout scratch board to skip
  the per-step `applyMove` copy, and profiling-driven representation changes behind the
  exported API.
- `non_terminal_rank` is now implemented in `MCTS.Engine` and cited in
  `documents/engineering/determinism_contract.md` against
  `cpp-legacy/legacy-core/board.cpp:395` and
  `cpp-legacy/legacy-core/mcts.hpp:258`-`266`, `400`-`421`.
- `mcts-unit` covers same-seed determinism, legal chosen moves, legal visit-list actions,
  sorted visit rows, root-child visit totals, the balanced initial `nonTerminalRank`, and
  the known-position engine golden.

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
   game_index)` produces an identical determinism payload across runs.
2. The transcript round-trips through `encode . decode` per Phase 2 Sprint 2.1.
3. The transcript filename is `sha256(run_config).tr` with the canonical
   `run_config` byte encoding.

### Closure Notes

- Baseline landed: `MCTS.Driver.runGame`, `runBatch`, `makeRunConfig`, per-game
  splitmix seeding, transcript writing, and logical envelope stamping exist.
- The game loop dispatches each per-move choice through `MCTS.Search.UCT.uctSearch`.
  Tree persistence across played moves is owned by Phase `8` as a performance feature.
- Atomic transcript writes landed in Sprint 2.2; keep the driver covered by the
  transcript write/read tests as the backend dispatch changes.
- The paired bench/instrumented build-target split is not retained for the logical
  correctness baseline; instrumentation surfaces are available through the single
  container-built `mcts` binary until profiling requires a split.
- Same-backend determinism, transcript roundtrip, and filename/hash behavior are covered
  by `mcts-unit`, `mcts-integration`, and the Phase `2` transcript cache tests.

## Sprint 3.5: `mcts bench rollouts` and `mcts bench selfplay` for `--backend haskell` ✅

**Status**: Done
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
   --workers 8` decode to identical determinism payload sets; only wall-clock and
   dispatcher provenance metadata differ.

### Closure Notes

- Baseline landed: `mcts bench rollouts` and `mcts bench selfplay` run through the
  logical Haskell backend, write transcripts, and render table/JSON throughput output.
  The bench runner now reads the pinned monotonic clock
  (`GHC.Clock.getMonotonicTimeNSec`) via the `monotonicNanos` helper. The
  test-injectable variant `runBenchWithClock` accepts any `IO Word64`
  clock, and the `mcts-unit` stanza asserts the bracket calls the clock
  exactly twice per backend (start + stop) under the test hook.
- `MultiThreaded { workers = N }` dispatch now runs game generation through a
  deterministic worker pool in `MCTS.Driver`, restores game order before
  transcript hashing/writing, and preserves the single monotonic-clock bracket
  around each backend batch.
- The comma-separated multi-backend bench path remains covered; the parser returns the
  requested backend list and the runner iterates it internally.
- Final report-card budgets are owned by Phase `7` and the Haskell parity proof by
  Phase `8`.

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

- `src/MCTS/Engine/Envelope.hs` — a module that constructs the
  `Envelope` for the in-process Haskell backend from build-time
  values. Compiler ID/version comes from `__GLASGOW_HASKELL__` via
  a CPP-passed `MCTS_GHC_VERSION` macro in `cabal.project`. `fp_flags`
  is filled from `-DMCTS_FP_FAST_MATH=0 -DMCTS_FP_FMA_ALLOWED=...`
  emitted by the Cabal stanza. `libm_id` is empty (the Haskell hot
  path makes no libm transcendental calls — `log` / `sqrt` go through
  GHC primops on `Double#`, which compile to LLVM IR and inline; the
  envelope captures this as `libm_id = ""`). `engine_build_id` is the
  SHA-256 of the linked `mcts` binary (since the Haskell engine is
  in-process), embedded by a post-link patcher invoked from the
  `Subprocess` boundary of the build harness. `cpu_features` is
  captured at startup via `cpuid` via a small C shim or via inspecting
  `getCpuModel`-style introspection; the resulting bitfield is
  cached for the process lifetime.
- `src/MCTS/Engine/Recompute.hs` — the in-process foreign-engine
  recompute path: given a transcript's bytes, parse the `RunConfig`,
  replay the search from move 0, emit `(move_index, n_alternatives,
  action_id[], visits[], equity[])` records that the REPL writes into
  an `.eq` sidecar (Sprint 2.7). Under `--rng cpp` the recompute
  hard-asserts visit-agreement with the transcript's recorded visits
  at every move; mismatch aborts with `AppError RecomputeMismatch
  (backend, game_id, move_index, recomputed_record, recorded_record)`
  per
  [../documents/engineering/determinism_contract.md → Recompute Mismatch Output](../documents/engineering/determinism_contract.md).
- The Haskell driver's existing search loop is invoked from this
  recompute path with an instrumentation hook to record per-move
  equity values into a streaming buffer.

### Validation

- `mcts-integration`: invoke `inspect replay <hash>` on a transcript
  produced by a different backend (e.g., a `cpp-imperative`
  transcript), trigger the haskell column with `r`, assert the
  sidecar `.eq` writes successfully, assert the recompute's visits
  agree byte-for-byte with the transcript's recorded visits under
  `--rng cpp`.
- `mcts-integration`: produce a transcript with backend (v); on
  subsequent `inspect replay` open, the originator `.eq` is read if
  the live binary's envelope matches.

### Closure Notes

- Baseline landed: the in-process backend stamps the full v1 envelope
  via `MCTS.Driver.makeLogicalEnvelope` (cohort-invariant + per-backend
  slot fields). `src/MCTS/Engine/Recompute.hs` exposes
  `recomputeEquities :: Transcript -> Either AppError [EqRecord]` and
  `recomputeEqStream :: String -> String -> Transcript -> Either
  AppError EqStream`. Under `--rng cpp` the recompute hard-asserts
  visit equality with the transcript's recorded visits at every move
  and short-circuits with `AppError RecomputeMismatch` on the first
  disagreement, exactly per
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

- `system-components.md` Backend (v) row reflects the Phase `3` correctness baseline
  closure while keeping Phase `8` performance-parity work visible.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [phase-2-transcript-codec-and-determinism.md](phase-2-transcript-codec-and-determinism.md)
- [phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
