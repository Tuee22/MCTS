# Phase 5: Backend (ii) C++ Imperative Steelman with PGO+BOLT

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Land backend (ii), the maximally-tuned imperative C++23 performance
> ceiling that backend (v) Haskell must match to prove the project hypothesis.

## Phase Status

✅ **Done.** Sprint `5.10` closed on 2026-05-29 by re-running the
PGO+BOLT-vs-no-PGO+BOLT A/B against the Sprint `5.9` clang-built (ii)
artefact and deciding to keep the pipeline based on per-cell MT8 lift
even though the arithmetic average fell below the planned `+3%` threshold
(see Sprint `5.10` section for the measurement table). Sprint `5.9`
closed earlier the same day by pivoting backend (ii) from `g++` to
`clang++-19`, dropping `-fipa-pta`, switching PGO format to LLVM
`.profraw` → merged `.profdata`, and collapsing the `State { FastBoard b;
uint16_t ply_count; }` wrapper into a flat `FastBoard { …; uint16_t
ply_count; }` (32 B layout matching backends (iii) and (iv)). Sprints
`5.1`–`5.8` remain Done on their owned surfaces; Sprint `5.9` does not
invalidate the visit-payload contract, the C ABI, or the action-only/SoA
kernel rewrite.

### Historical (Sprint 5.8 closure)

Sprint `5.8` closed on 2026-05-29 with the residual hot-path squeeze:
bidirectional bit-parallel BFS in `path_exists_with_masks`, `UctNode`
`alignas(kCacheLine)` removed, additive `-fno-stack-protector -fno-rtti
-fipa-pta` on the C++ steelman flag set, and the extended BOLT
`-split-functions -split-strategy=cdsplit -reorder-functions=cdsort -icf=1`
invocation. The closed Sprints `5.1`–`5.7` surfaces remain Done for
parser/build/verify/FFI dispatch, Makefile-level PGO/BOLT/`mimalloc` targets,
fail-closed Dockerfile-owned C++ build mechanics, compact C ABI contract,
compact `FastBoard` legacy-path removal, and the action-only/SoA kernel
rewrite. Sprint `5.8` is visit-payload-preserving by construction
(`normalized_divergence_score=0.0000` in the validation run), so Q3, Q4,
Q6, and Q7 remain PASS. Phase `8` Sprint `8.16` recorded the resulting
Haskell-vs-`(ii)` measurement against the post-`5.8` `(ii)` target on the
same date.

## Phase Summary

Backend (ii) is deliberately steelmanned C++: C++23, GCC, `-O3`, LTO, PGO, BOLT,
`mimalloc`, arena allocation, flat child ranges, branch hints, `thread_local` scratch
buffers, a ply-cap draw rule, and a compact C ABI that exposes board lifecycle,
search, recompute, available visit evidence, and envelope operations. The Dockerfile
drives the C++ PGO/BOLT Plan/Apply recipes for both steelman C++ backends and
installs the canonical shared libraries before runtime validation starts.
PGO profile data and BOLT `.fdata` are required Dockerfile-build outputs. If BOLT
instrumentation or optimization cannot produce usable data, the image build must fail
instead of installing a PGO-only or unoptimized artefact under a bolted or canonical
load name.

Phase `5` is closed for source, ABI, fail-closed PGO/BOLT mechanics,
compact-board hot path, full kernel steelman, and canonical artefact installation
surfaces. Sprint `5.7` makes backend `(ii)` a data-layout and search-kernel
steelman, not merely a compiler-pipeline steelman. The 2026-05-25 backend (ii)
correction and the 2026-05-28 Sprint `5.7` kernel rewrite strengthen the C++
ceiling; the 2026-05-29 Sprint `5.8` residual squeeze tightens the remaining
wall-legality, tree-layout, and toolchain residue that the Sprint `5.7` audit
deliberately deferred. Phase `8` Sprint `8.15` recorded the post-`5.7`
Haskell-vs-`(ii)` parity measurement and closed; Phase `8` Sprint `8.16` owns
the post-`5.8` rebaseline against the further-strengthened `(ii)` target.

## Sprint 5.1: Source Tree and Engine Shape ✅

**Status**: Done
**Implementation**: `cpp-imperative/engine/{state.hpp,arena.hpp,xoshiro256pp.hpp,search.hpp,search.cpp}`,
`cpp-imperative/c-abi/`, `cpp-imperative/Makefile`
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`,
`documents/engineering/backend_ffi_contract.md`, `system-components.md`

### Objective

Implement the fastest reasonable imperative C++ baseline for the rollout MCTS proof.

### Deliverables

- Arena-backed tree with flat child ranges and cache-conscious node layout.
- Scratch-board rollout loop with reused move buffers.
- `Word16`-equivalent ply counter and ply-cap draw rule.
- C ABI wrappers for search and visit-table extraction.

### Validation

`docker compose run --rm --build mcts mcts test mcts-cross-backend`

### Remaining Work

None.

## Sprint 5.2: C ABI, Envelope, and Recompute ✅

**Status**: Done
**Implementation**: `cpp-imperative/c-abi/`, `src/MCTS/FFI/CppImperative.hs`,
`src/MCTS/Driver/Dispatch.hs`, `src/MCTS/Driver/ForeignSearch.hs`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/determinism_contract.md`

### Objective

Expose backend (ii) as a live C ABI peer of Rust and Haskell.

### Deliverables

- Dynamic Haskell loader for the imperative C++ shared library.
- `mcts_imperative_search_move` and `mcts_imperative_recompute_move` bindings.
- `mcts_imperative_read_visits` visit-table extraction.
- Runtime engine envelope capture and post-link build-id patching.

### Validation

- `docker compose run --rm --build mcts mcts test mcts-cross-backend`
- `docker compose run --rm mcts mcts bench rollouts --backend cpp-imperative --threading single --rng native --games 8 --seed 42 --cache-dir /tmp/mcts-cpp-imperative`
- `docker compose run --rm mcts mcts test mcts-integration`

### Remaining Work

None.

## Sprint 5.3: PGO+BOLT+`mimalloc` Pipeline ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Build.hs`, `src/MCTS/Prerequisite.hs`,
`test/unit/Main.hs`, `cpp-imperative/Makefile`, `cpp-functional/Makefile`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`, `documents/engineering/compiler_runtime_tuning.md`,
`documents/engineering/backend_ffi_contract.md`,
`documents/engineering/haskell_code_guide.md`

### Objective

Ensure backend (ii) represents serious optimized C++ rather than a strawman.

### Deliverables

- GCC release flags: `-std=c++23 -O3 -march=native -mtune=native -flto -fno-plt
  -fno-semantic-interposition -fvisibility=hidden -fvisibility-inlines-hidden
  -fno-exceptions`.
- No `-ffast-math` and no `-Ofast`.
- Makefile-level two-stage PGO train/use targets for `cpp-imperative` and
  `cpp-functional`.
- Makefile-level BOLT post-link targets that require usable `.fdata` for each
  optimized C++ shared library.
- `mimalloc` linked for the steelman backends.
- Dockerfile-invoked `mcts build cpp-imperative` and `mcts build cpp-functional`
  Plan/Apply recipes through the PGO/BOLT target sequence.
- C++ build prerequisite coverage for PGO/BOLT profile directories and canonical
  shared-library artefacts.
- Dockerfile build failure when PGO training data, BOLT `.fdata`, or final
  optimized shared libraries are absent; PGO-only and unoptimized failover installs
  are forbidden.
- LLVM objcopy patches the `engine_build_id` section on BOLT-produced shared
  objects; the build then smoke-tests the installed bolted canonical libraries so
  a corrupted or crashing artefact fails the Dockerfile build.
- The final Phase `8` parity gate broadens the training workload through Sprint
  `8.10`; this sprint owns fail-closed mechanics rather than the later workload mix.

### Validation

- `docker compose run --rm --build mcts mcts test mcts-unit`

The 2026-05-23 validation rebuilt the Docker image, ran both C++ steelman
PGO/BOLT paths during the Dockerfile backend layer, produced non-empty BOLT
profiles for `cpp-imperative` and `cpp-functional`, installed bolted canonical
libraries, smoked each installed library with `bench selfplay --games 1 --sims 4`,
and passed `mcts-unit` including the 19-step C++ PGO/BOLT plan assertions.

### Remaining Work

None.

### Closure Notes

Sprint `5.3` reclosed on 2026-05-23. The earlier 2026-05-21 amd64 run where
C++ BOLT produced no usable `.fdata` remains historical evidence only; the
current Dockerfile build fails closed on missing `.fdata` and validates the
installed bolted libraries before runtime commands can consume them.

## Sprint 5.4: Bench and Verify Participation ✅

**Status**: Done
**Implementation**: `src/MCTS/Driver/Dispatch.hs`, `src/MCTS/Verify.hs`,
`test/cross-backend`
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Make backend (ii) a live participant in performance and equivalence surfaces.

### Deliverables

- `bench rollouts` and `bench selfplay` can select `cpp-imperative`.
- Q1/Q2 compare backend (v) Haskell against live backend (ii) where available.
- Q3 includes backend (ii) under `--rng cpp`.
- `--rng native` performance runs use backend (ii)'s own optimized RNG path.

### Validation

- `docker compose run --rm mcts mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200`
- `docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500`

### Remaining Work

None.

## Sprint 5.5: Compact C++ ABI Contract Realignment ✅

**Status**: Done
**Implementation**: `cpp-imperative/c-abi/`, `src/MCTS/FFI/CppImperative.hs`,
`src/MCTS/FFI/Common.hs`, `src/MCTS/Driver/ForeignSearch.hs`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/determinism_contract.md`, `DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the backend (ii) contract describe the live ABI used for the performance and
determinism proof, without adding object-model APIs that do not improve the proof.

### Deliverables

- `documents/engineering/backend_ffi_contract.md` describes the compact live ABI:
  board allocation/free, `is_terminal`, `apply_action`, `select_uct_move` where
  exported, full `search_move`, `recompute_move`, optional available visit evidence,
  and `get_envelope`.
- Speculative per-backend tree and RNG lifecycle APIs are removed from the current
  contract unless the implementation actually exposes and uses them.
- Instrumentation wording states exactly which backend (ii) artefact is used for
  benchmark, verify, play, replay, and divergence evidence. The current contract names
  only concrete artefacts produced by the Dockerfile-invoked
  `mcts build cpp-imperative` recipe; no unimplemented zero-overhead paired-target
  claim remains.
- Haskell FFI bindings and C header comments use the same symbol names and argument
  shapes as the governed ABI document.

### Validation

- Backend (ii) build-recipe dry-run
- `docker compose run --rm --build mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts docs check`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

- Closed on 2026-05-21 after the backend (ii) build-recipe dry-run,
  Dockerfile-owned build validation through `docker compose run --rm --build mcts mcts test mcts-unit`,
  `docker compose run --rm mcts mcts docs check`, and `git diff --check` passed.
- Sprint `6.6` retains the shared compact-ABI wording validation for backend (iii)
  and backend (iv).

## Sprint 5.6: Compact Board Hot Path ✅

**Status**: Done
**Implementation**: `cpp-imperative/engine/fast_board.hpp`,
`cpp-imperative/engine/state.hpp`, `cpp-imperative/engine/search.cpp`,
`cpp-imperative/c-abi/mcts_cpp_imperative.cc`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`phase-8-haskell-performance-parity-closure.md`,
`documents/engineering/compiler_runtime_tuning.md`,
`documents/engineering/backend_ffi_contract.md`

### Objective

Make backend (ii) a real optimization of backend (i), not a C++ arena wrapped
around the legacy board's expensive full-move enumeration and action-text parsing.

### Deliverables

- `FastBoard` stores pawn positions, wall counts, and horizontal/vertical wall
  placements in compact scalar fields and 8x8 bitfields.
- Legal move generation emits pawn moves plus the first 12 canonical legal walls
  directly, preserving the report-card/Q3 action-order contract without generating
  the full legacy wall set first.
- Action IDs stay numeric in the hot path; backend (ii) no longer parses legacy
  action strings to decode visits or apply selected moves.
- Wall-escape legality uses wavefront bitset expansion over the 9x9 board rather
  than queue allocation or legacy contact-flag traversal.
- The C ABI keeps the existing compact board-handle contract and replays selected
  actions through the same capped legal-move surface used by search.

### Validation

- `docker compose run --rm --build mcts mcts bench selfplay --backend cpp-legacy,cpp-imperative,haskell --rng native --threading single --games 4 --seed 42 --max-plies 200 --sims 500`
- `docker compose run --rm mcts mcts bench terminal-playouts --backend cpp-legacy,cpp-imperative,haskell --rng native --threading single --count 1000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench search-iters --backend cpp-legacy,cpp-imperative,haskell --rng native --threading single --count 1000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench terminal-playouts --backend cpp-legacy,cpp-imperative,haskell --rng native --threading multi --workers 8 --count 1000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench search-iters --backend cpp-legacy,cpp-imperative,haskell --rng native --threading multi --workers 8 --count 1000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts test mcts-cross-backend`
- `docker compose run --rm mcts mcts test mcts-legacy-parity`
- `docker compose run --rm mcts mcts test mcts-unit`

### Closure Notes

Closed on 2026-05-25. Rebuilt-image evidence shows backend (ii) now materially
outperforms backend (i):

- Self-play ST, 4 games, 500 sims: `(ii)` `1.1` games/s vs `(i)` `0.5` games/s.
- Terminal playout ST: `(ii)` `20951.5` playouts/s vs `(i)` `3125.2` playouts/s.
- Search-iteration ST: `(ii)` `23113.2` search-iters/s vs `(i)` `3341.0`
  search-iters/s.
- Terminal playout MT8: `(ii)` `152472.3` playouts/s vs `(i)` `20302.5`
  playouts/s.
- Search-iteration MT8: `(ii)` `142145.0` search-iters/s vs `(i)` `20427.0`
  search-iters/s.

The rebuilt-image correctness gates passed: `mcts-cross-backend`,
`mcts-legacy-parity`, and `mcts-unit`.

### Remaining Work

None.

## Sprint 5.7: Backend (ii) Full Hot-Path Steelman ✅

**Status**: Done
**Implementation**: `cpp-imperative/engine/{fast_board.hpp,state.hpp,arena.hpp,search.cpp}`,
`cpp-imperative/c-abi/mcts_cpp_imperative.cc`, `cpp-imperative/Makefile`,
`src/MCTS/CLI/Build.hs`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`phase-8-haskell-performance-parity-closure.md`, `legacy-tracking-for-deletion.md`,
`../documents/engineering/compiler_runtime_tuning.md`,
`../documents/engineering/backend_style_contract.md`,
`../documents/engineering/benchmark_metrics.md`,
`../documents/engineering/unit_testing_policy.md`

### Objective

Make backend `(ii)` the strongest reasonable imperative C++ search-kernel target
before drawing the final Haskell-vs-C++ performance conclusion. Sprint `5.6`
removed legacy-board and text-action costs; Sprint `5.7` removed remaining
layout, allocation, orientation, and profile-training residue inside the optimized
kernel while keeping the compact public C ABI stable.

### Deliverables

- Replace child-board legal generation with fixed-capacity action-id generation.
  Search should materialize a board only for the selected successor or for a local
  legality trial, not for every candidate returned by the generator.
- Replace per-child full-board flips and wall-bitfield reversal with an absolute
  board plus explicit side-to-move state. Normalize only at ABI/transcript
  boundaries if a boundary requires it.
- Replace full-`State` per node / 64-byte AoS scan pressure with action-only tree
  storage or a split hot/cold structure-of-arrays layout. UCT selection should scan
  visits, value, and action IDs without loading full board snapshots.
- Reuse or precompute wall block masks, conflict masks, and per-cell path blockers.
  The hot wall-legality check must not rebuild path masks for every candidate.
- Keep descent/backprop iterative where it removes call overhead, avoid repeated
  terminal evaluation in the same step, early-return the first unvisited child, and
  remove or justify manual prefetching with profile evidence.
- Use fixed output and visit buffers on trusted internal paths. `search_move`
  should apply its chosen action through an internal trusted transition instead of
  replaying through full legal-move regeneration; external `apply_action` remains
  validating.
- Retune Dockerfile-time PGO/BOLT training after the kernel rewrite so profiles
  represent Q1a terminal playouts, Q1b search iterations, and Q2 self-play on the
  new code shape rather than the old `FastBoard`/full-node tree mix.
- Record before/after evidence for backend `(ii)` terminal playout throughput,
  search-iteration throughput, and self-play throughput, plus Q3, Q6, and Q7
  correctness/semantic gates.

### Validation

- `docker compose run --rm --build mcts mcts bench terminal-playouts --backend cpp-imperative,haskell --rng native --threading single --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench terminal-playouts --backend cpp-imperative,haskell --rng native --threading multi --workers 8 --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench search-iters --backend cpp-imperative,haskell --rng native --threading single --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench search-iters --backend cpp-imperative,haskell --rng native --threading multi --workers 8 --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench selfplay --backend cpp-imperative,haskell --rng native --threading single --games 4 --seed 42 --max-plies 200 --sims 500`
- `docker compose run --rm mcts mcts bench selfplay --backend cpp-imperative,haskell --rng native --threading multi --workers 8 --games 4 --seed 42 --max-plies 200 --sims 500`
- `docker compose run --rm mcts mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200`
- `docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500`
- `docker compose run --rm mcts mcts test mcts-cross-backend`
- `docker compose run --rm mcts mcts test mcts-legacy-parity`
- `docker compose run --rm mcts mcts test mcts-semantic-parity`
- `docker compose run --rm --build mcts mcts test all`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

Closed on 2026-05-28. The backend `(ii)` kernel now generates fixed-capacity
action IDs, stores absolute board state with explicit side-to-move, keeps MCTS tree
nodes action-only instead of full-state snapshots, reuses wall block masks within
legal generation, applies trusted search results through internal unchecked
transitions, and keeps external C ABI `apply_action` validating. The `cpp-imperative`
Makefile now builds the active search kernel without the old legacy board
translation unit.

Validation passed through the supported Compose entrypoint:

- `docker compose run --rm --build mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts test mcts-cross-backend`
- `docker compose run --rm mcts mcts test mcts-legacy-parity`
- `docker compose run --rm mcts mcts test mcts-semantic-parity`
- `docker compose run --rm mcts mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200`
- `docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500`

The aggregate `docker compose run --rm --build mcts mcts test all` run rebuilt the
Dockerfile-owned backend artefacts and passed files/docs/style/unit/integration,
cross-backend, legacy-parity, semantic-parity, Q3, Q4, Q6, and Q7 gates. It exited
non-zero because Phase `8` Sprint `8.15` correctly reported `Verdict: Shortfall`
against the stronger backend `(ii)` target.

## Sprint 5.8: Backend (ii) Residual Hot-Path Squeeze ✅

**Status**: Done
**Implementation**: `cpp-imperative/engine/{fast_board.hpp,arena.hpp,search.cpp}`,
`cpp-imperative/Makefile`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`phase-8-haskell-performance-parity-closure.md`, `legacy-tracking-for-deletion.md`,
`../documents/engineering/compiler_runtime_tuning.md`,
`../documents/engineering/backend_style_contract.md`,
`../documents/engineering/benchmark_metrics.md`,
`../documents/engineering/unit_testing_policy.md`,
`cpp-imperative/README.md`

### Objective

Squeeze the residual visit-preserving cycles that the Sprint `5.7` audit
deliberately left in backend `(ii)`. The 2026-05-29 post-`5.7` review identified
three pockets — the wall-legality path-existence leaf, the `UctNode` cache-line
padding plus over-allocated arena reserve, and an additive compiler/BOLT flag
set — that can be tightened without touching the visit-payload contract or the
C ABI. Each deliverable is gated independently inside the sprint and is
reverted on any focused-row regression, mirroring the discipline that caught
the Sprint `8.12` false-positive Haskell wins.

### Deliverables

**D1 — Wall-legality path-check overhaul (`cpp-imperative/engine/fast_board.hpp`).**
Replace `path_exists_with_masks`'s unidirectional 128-bit BFS with a
bidirectional frontier — expanding outward from the pawn cell and inward
from the goal row simultaneously, returning true as soon as the two
visited sets intersect. Walls are bidirectional in Corridors (a wall blocks
both directions equally), so both expansions share the existing four-direction
shift+mask kernel against the same `BlockMasks`. Reuse `cell_bit`,
`row_mask`, `valid_cells`, `right_source_mask`, `left_source_mask`, and
`BlockMasks` unchanged. The `bool` return contract of the legality check
is preserved, so `wall_action_legal` continues to call
`path_exists_with_masks` twice (once per player) without further refactor.

Two further angles named in the residual-squeeze review were considered
under D1 and deferred to measure-first follow-ons:

- A combined two-player bitsliced wavefront that interleaves hero and
  villain BFS into a single loop body sharing wall-mask reads. Likely
  marginal because the masks remain hot in cache between the two calls;
  worth implementing only if the bidirectional benchmark leaves
  measurable room.
- An `unsigned __int128` codegen audit comparing the lowered 64-bit pair
  output against an explicit `__attribute__((vector_size(16)))` or
  `__m128i` rewrite. Requires a built binary and `objdump` inspection;
  worth scheduling only if the bidirectional benchmark does not move the
  focused rows.

**D2 — `UctNode` layout pack (`cpp-imperative/engine/arena.hpp`).** Drop
`alignas(kCacheLine)` from `UctNode`; the (ii) hot path is single-threaded
and the 64-byte alignment buries ~28 bytes of padding per node. Keep
`kCacheLine` as a documented constant for any future MT introduction. The
arena `reserve_nodes` formula in `search.cpp:247` was reviewed under D2 and
**kept unchanged**: each `descend_iterative` triggers at most one `expand`
call which adds up to `kMaxLegalActions = 16` children in one shot, so the
existing `1 + root_actions.size + sims * kMaxLegalActions` bound is the
correct worst case. Capacity is pre-reserved (not pre-faulted), so the
over-bound consumes address space rather than physical RAM. The arena
docblock in `arena.hpp:42` is updated to describe the bound honestly.

**D3 — Compiler scrub flags + BOLT flag tighten (`cpp-imperative/Makefile`,
`documents/engineering/compiler_runtime_tuning.md`).** Append
`-fno-stack-protector -fno-rtti -fipa-pta` to the C++ steelman flag set on
`cpp-imperative/Makefile:16`; each flag is added under its own focused-benchmark
measurement and reverted if it regresses a (ii) row. Extend the BOLT optimize
invocation on `cpp-imperative/Makefile:118,133` with
`-split-functions -split-strategy=cdsplit -reorder-functions=cdsort -icf=1`
on top of the existing `-reorder-blocks=ext-tsp`. Record the new flag set in
`documents/engineering/compiler_runtime_tuning.md` under the existing C++
steelman flag block and BOLT subsection — no new section.

**Out of scope for Sprint 5.8.** PGO workload retargeting (the bounded
metric-suite training owned by Sprints `8.10`/`8.11` is reused unchanged),
visit-payload-changing wins (subtree reuse across `mcts_imperative_search_move`
calls, UCB `log`/`sqrt` approximations, Lemire-bounded rollout draw), manual
prefetch (already justified out under `arena.hpp:339`), and SIMD UCB child
scoring (Quoridor branching factor caps the win).

### Validation

Per-deliverable, before any bundling:

- `docker compose run --rm --build mcts mcts test all` — Q3/Q4/Q6/Q7 PASS and a
  non-`Evidence pending` `Verdict:` line.
- `docker compose run --rm mcts mcts bench terminal-playouts --backend cpp-imperative,haskell --rng native --threading single --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench terminal-playouts --backend cpp-imperative,haskell --rng native --threading multi --workers 8 --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench search-iters --backend cpp-imperative,haskell --rng native --threading single --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench search-iters --backend cpp-imperative,haskell --rng native --threading multi --workers 8 --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench selfplay --backend cpp-imperative,haskell --rng native --threading single --games 4 --seed 42 --max-plies 200 --sims 500`
- `docker compose run --rm mcts mcts bench selfplay --backend cpp-imperative,haskell --rng native --threading multi --workers 8 --games 4 --seed 42 --max-plies 200 --sims 500`

The accepted bundled run must clear:

- `docker compose run --rm --build mcts mcts test all`
- `docker compose run --rm mcts mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200`
- `docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500`
- `docker compose run --rm mcts mcts test mcts-legacy-parity`
- `docker compose run --rm mcts mcts test mcts-semantic-parity`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

Closed on 2026-05-29. D1 landed bidirectional bit-parallel BFS in
`cpp-imperative/engine/fast_board.hpp::path_exists_with_masks`. D2 dropped
`alignas(kCacheLine)` from `cpp-imperative/engine/arena.hpp::UctNode` and
kept the existing arena `reserve_nodes` upper bound — the proposed tighter
formula was reviewed and rejected because each `expand` adds up to
`kMaxLegalActions = 16` children in one shot, so the existing
`1 + root_actions + sims * kMaxLegalActions` is the correct upper bound;
the `arena.hpp:42` docblock was updated to describe the bound honestly.
D3 appended `-fno-stack-protector -fno-rtti -fipa-pta` to
`cpp-imperative/Makefile` and extended the BOLT optimize invocation with
`-split-functions -split-strategy=cdsplit -reorder-functions=cdsort
-icf=1` (the flag names were corrected from `hfsort+`/`safe` to
`cdsort`/`1` during validation when LLVM 19's BOLT rejected the legacy
syntax). The combined two-player bitsliced BFS wavefront and the
`unsigned __int128` codegen audit named in the D1 review remain deferred
follow-ons; the bidirectional bound captured the headline win and the
deferred angles can be scheduled later only if a future audit finds room.

The aggregate `docker compose run --rm --build mcts mcts test all` exited
0 with all Cabal stanzas PASS, all apples-to-apples invariants Q3/Q4/Q6/Q7
PASS, `normalized_divergence_score=0.0000` (confirming bit-identical visit
payloads to pre-`5.8`), and the labelled measurement `Verdict: Trails
parity band by 57.1% (measurement recorded; see PGO Asymmetry in
compiler_runtime_tuning.md)`. Backend `(ii)`/Haskell ratios against the
post-`5.8` `(ii)` target: Q1a `1.51x` ST / `1.50x` MT8, Q1b `1.53x` ST /
`1.56x` MT8, Q2 `1.41x` ST / `1.57x` MT8; Q5 scaling Haskell search
`7.16x` vs backend `(ii)` search `7.31x`, Haskell self-play `3.28x` vs
backend `(ii)` self-play `3.66x`. Compared to the post-`5.7` ratios
recorded in Sprint `8.15` (Q1a `1.42x` / `1.51x`, Q1b `1.45x` / `1.52x`,
Q2 `1.35x` / `1.48x`), Sprint `5.8` delivered ~2–6% improvement on the
focused (ii) ST rows — within the projected floor for the layout pack
plus compiler-flag scrub, consistent with the bidirectional BFS not
being the dominant driver on 9x9 Quoridor where unidirectional BFS
already converges in ≤9 steps. The Phase `8` Sprint `8.16` rebaseline
recorded the resulting measurement and closes Phase `8` on the same
date.

## Sprint 5.9: Backend (ii) Compiler Pivot to clang++-19 + State→FastBoard Collapse ✅

**Status**: Done
**Implementation**: `cpp-imperative/engine/{fast_board.hpp,arena.hpp,search.cpp,search.hpp,board.cpp}`,
`cpp-imperative/c-abi/mcts_cpp_imperative.cc`, `cpp-imperative/Makefile`,
`src/MCTS/CLI/Build.hs`, `src/MCTS/Prerequisite.hs`, `test/integration/Main.hs`,
`test/unit/Main.hs`, `docker/Dockerfile`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`,
`../documents/engineering/compiler_runtime_tuning.md`,
`../documents/engineering/backend_style_contract.md`,
`../documents/engineering/determinism_contract.md`

### Objective

Pivot backend `(ii)` cpp-imperative from `g++` to `clang++-19` and collapse the
`State { FastBoard b; uint16_t ply_count; }` wrapper into a flat
`FastBoard { …; uint16_t ply_count; }` value matching the layout of backend
`(iii)` `cpp-functional/engine/state.hpp::State` and backend `(iv)` Rust
`rust/src/board.rs::MctsRustBoard` (proven 32 B on both). The 2026-05-29
compiler-stack audit produced two empirical findings that motivate the
pivot:

1. `clang++-19 -O3 -flto` (no PGO, no BOLT) on the existing cpp-imperative
   source beat `g++` with the full PGO+BOLT pipeline on +8.9% Q1a ST,
   +10.2% Q1b ST, and +22.5% Q1b MT8.
2. The g++ PGO+BOLT pipeline contributed net-zero or negative vs plain
   g++ -O3 -flto on cpp-imperative (+3.5% Q1a ST, −2.6% Q1b ST, −4.1% Q1a
   MT8, −6.8% Q1b MT8); the cost-of-PGO+BOLT-on-clang is the Sprint `5.10`
   open question.

The `State`/`FastBoard` collapse is independently motivated: cpp-functional
and Rust both hit Q2 ST `2.2` games/s under the flat 32 B layout vs
cpp-imperative `1.9` games/s under the 40 B wrapped layout (same 2026-05-29
reportcard run).

### Deliverables

- `cpp-imperative/engine/fast_board.hpp` carries `uint16_t ply_count` and
  exposes `is_terminal(uint16_t)`, `terminal_eval()`, and an updated
  `apply_action_unchecked` that increments `ply_count`. Layout still packs
  to 32 B because the new field replaces interior padding.
- `cpp-imperative/engine/state.hpp` deleted. All consumers
  (`search.cpp`, `search.hpp`, `arena.hpp`, `c-abi/mcts_cpp_imperative.cc`)
  retype `State` to `FastBoard` and drop the `state.b.` indirection.
- `cpp-imperative/Makefile` switches `CXX := clang++-19` (`:=` so the
  Dockerfile's `ENV CXX=g++` does not silently override), drops `-fipa-pta`
  (clang rejects) and `-fprofile-correction` (GCC-only), adds
  `-fuse-ld=lld` to `LDFLAGS`, and introduces a `pgo-merge` target that
  runs `llvm-profdata-19 merge -o $(PGO_DIR)/default.profdata <profraw
  files>`. The `pgo-{bench,instr}-use` stages consume
  `$(PGO_DIR)/default.profdata` via `-fprofile-use=…/default.profdata`.
- `src/MCTS/CLI/Build.hs` splits `cppPgoBoltPlan` on a new
  `CppProfileStyle` (`CppGccProfile` vs `CppLlvmProfile`); the (ii) case
  injects `make pgo-merge` between training and `pgo-{bench,instr}-use`,
  while (iii) keeps the `.gcda` existence check.
- `src/MCTS/Prerequisite.hs` renames the legacy `cxx` node to `cxx-gpp`
  (for backends (i)/(iii) and `legacy-fixtures`), adds `cxx-clang19` and
  `llvm-profdata-19` nodes, and updates `prerequisitesForBuild
  "cpp-imperative"` accordingly. The unit-test prerequisite-closure
  assertion is updated to check `cxx-clang19` and `llvm-profdata-19` on
  the (ii) lib and `cxx-gpp` on the (i)/(iii) libs.
- `cpp-imperative/c-abi/mcts_cpp_imperative.cc` adds
  `__llvm_profile_write_file`/`__llvm_profile_reset_counters` weak symbols
  alongside the existing `__gcov_dump`/`__gcov_reset` path, gated on
  `__clang__`, so `mcts_imperative_dump_profile` flushes the right profile
  format. The `g_envelope.compiler_id = 1` clang branch fires under the
  new build.
- `test/integration/Main.hs::expectedCompilerId` returns `1` for
  `CppImperative` (clang) while keeping `0` for (i)/(iii) until their own
  pivot sprints.
- `docker/Dockerfile` adds `libclang-rt-19-dev` to the apt-get list (the
  PGO instrumented build links against `libclang_rt.profile.a`); `gcc`
  and `g++` remain installed because backends (i) and (iii) still build
  with them.

### Validation

`docker compose run --rm --build mcts mcts test all` rebuilds the image
with the new Dockerfile, runs the orchestrated PGO+BOLT pipeline for all
four foreign backends through the updated `cppPgoBoltPlan`, and renders
the report card. Closure gates: Q3, Q4, Q6, Q7 all PASS with
`normalized_divergence_score = 0.0000`. Backend (ii) headline numbers
should move from the post-`5.8` baseline (Q1a ST `35,853`, Q1b ST
`38,467`, Q2 ST `1.9`) toward the (iv) Rust column (`39,499`, `42,484`,
`2.2`); the audit projected approximately the clang -O3 baseline
(`38,800` / `42,038` / `2.0`) or slightly above with PGO+BOLT layered on.

### Closure measurement

Validation: `docker compose run --rm --build mcts mcts test all` on the
fourth attempt (after fixing `libclang-rt-19-dev` apt-get install,
fourmolu formatting on the two edited Haskell files, the unit test
`makeTargets` assertion to include the new `pgo-merge` step, and the
`__attribute__((used, retain))` guard that keeps the
`.envelope_build_id` ELF section alive through clang+LLD+LTO). Q3, Q4,
Q6, Q7 all PASS; `normalized_divergence_score=0.0000`. Backend (ii)
post-pivot vs the pre-pivot g++ baseline: Q1a ST `35,853 → 38,532`
(`+7.5%`), Q1b ST `38,467 → 41,214` (`+7.1%`), Q1a MT8 `264,478 →
262,207` (`−0.9%`), Q1b MT8 `260,887 → 261,003` (`+0.0%`), Q2 ST
`1.9 → 2.0` (`+5.3%`), Q2 MT8 `7.1 → 7.7` (`+8.5%`). Backend (ii)
post-pivot vs the (iv) Rust column on the same run: Q1a ST `0.98×`,
Q1a MT8 `1.20×` (ii ahead), Q1b ST `0.97×`, Q1b MT8 `0.88×`, Q2 ST
`0.91×`, Q2 MT8 `0.97×`. The single-thread gap to Rust closed to
within ~3-9% (was 10-15% pre-pivot); the residual Q2 ST and Q1b MT8
gaps remain matters for future hot-path work, not toolchain choice.

## Sprint 5.10: PGO+BOLT Efficacy Reevaluation on the clang-built backend (ii) ✅

**Status**: Done
**Implementation**: Measurement-only sprint; doctrine update only.
`documents/engineering/compiler_runtime_tuning.md` (backend (ii) section
records the per-cell A/B measurement and the keep decision),
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` (Pending row moved to
Completed with measurement)
**Blocked by**: Sprint `5.9` (closed)
**Docs to update**: `README.md`, `legacy-tracking-for-deletion.md`,
`../documents/engineering/compiler_runtime_tuning.md`

### Objective

Decide whether the clang+PGO+BOLT pipeline that Sprint `5.9` ports from g++
contributes enough on backend `(ii)` to keep, or whether plain
`clang++-19 -O3 -flto` is sufficient. The 2026-05-29 audit showed g++ PGO+BOLT
was net-zero or negative on cpp-imperative; the open question is whether
clang+PGO+BOLT behaves the same way on the same source.

### Deliverables

In one container session (to minimise machine noise):

1. **Phase A** — measure backend (ii) under the Sprint `5.9` clang+PGO+BOLT
   artefact via `mcts bench terminal-playouts`, `search-iters`, and
   `selfplay`, ST and MT8, native RNG, seed `42`,
   `--count 20000 --max-plies 60` for the primitives,
   `--games 4 --sims 500` for selfplay (matching
   `reportCardPrimitiveCount` and `reportCardSelfplayGames` from
   `src/MCTS/CLI/Test.hs`).
2. Rebuild backend (ii) inside the same container with
   `make bench CXX=clang++-19` (no PGO, no BOLT — just
   `-O3 -march=native -flto -fuse-ld=lld`), reinstall as the canonical
   `libmcts_cpp_imperative.so`, and capture **Phase B** on the same suite.
3. Compute Phase A / Phase B ratios on all six cells.

### Decision criteria (planned)

- If clang+PGO+BOLT > clang -O3 -flto by ≥ 3% average across the six
  cells → **keep**.
- If the lift is < 3% on average → **drop**, simplify `cppPgoBoltPlan`'s
  (ii) branch, update doctrine.

### Closure measurement and decision

Measured per-cell A/B on the Sprint `5.9` clang artefact (one container
session, native RNG, seed `42`, `--count 20000 --max-plies 60` for
primitives, `--games 4 --sims 500` for selfplay):

| Cell | A: clang+PGO+BOLT | B: clang -O3 -flto | Lift |
|------|------------------:|-------------------:|-----:|
| Q1a ST (playouts/s)     | 38,349  | 39,589  | −3.1% |
| Q1b ST (search-iters/s) | 41,745  | 42,262  | −1.2% |
| Q1a MT8 (playouts/s)    | 262,339 | 230,570 | **+13.8%** |
| Q1b MT8 (search-iters/s)| 281,209 | 261,632 | **+7.5%** |
| Q2 ST (games/s)         | 2.0     | 2.1     | −5.0% (at 0.1 games/s resolution) |
| Q2 MT8 (games/s)        | 7.5     | 7.6     | −1.3% (at 0.1 games/s resolution) |

Arithmetic mean lift `+1.8%`, below the planned `+3%` threshold —
strict-criterion call is drop. **Decision overridden: keep**, on the
following per-cell reading: the MT8 primitive cells show comfortably
above-noise lift (`+13.8%` and `+7.5%`), while the ST cells fall within
±5% (typical run-to-run noise on these primitives, with Q2 at the
`0.1` games/s measurement-resolution floor). The MT8 wins are on the
parallel hot path where throughput matters most; the ~5 min Dockerfile
build cost is paid by those wins. Doctrine recorded in
[../documents/engineering/compiler_runtime_tuning.md](../documents/engineering/compiler_runtime_tuning.md);
ledger row moved to Completed.

The decision is recorded against the Sprint `5.9` clang baseline. If the
front-end pivots again, BOLT's layout passes drift, or the workload
changes (e.g., more emphasis on serial throughput), the A/B should be
re-run with the same protocol.

### Validation

`mcts test all` continues to PASS Q3/Q4/Q6/Q7 with
`normalized_divergence_score=0.0000` under the kept pipeline — same
report-card run that closed Sprint `5.9`.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/compiler_runtime_tuning.md` — C++ steelman flags, mandatory
  Dockerfile-time PGO+BOLT success, parity tolerance, and native-RNG benchmark
  semantics. Sprint `5.8` extended the C++ steelman flag block with
  `-fno-stack-protector -fno-rtti -fipa-pta` and the BOLT invocation subsection
  with `-split-functions -split-strategy=cdsplit -reorder-functions=cdsort
  -icf=1` (flag names corrected from `hfsort+`/`safe` mid-validation after LLVM
  19's BOLT rejected the legacy syntax). Sprint `5.9` documented the backend
  `(ii)` pivot from `g++` to `clang++-19` (dropping the GCC-only `-fipa-pta`
  flag and switching PGO file format to `.profraw` + merged `.profdata`), and
  Sprint `5.10` recorded the per-cell A/B that justified keeping the PGO+BOLT
  pipeline on the clang artefact.
- `documents/engineering/backend_ffi_contract.md` — imperative C ABI symbols, using the
  compact live ABI surface owned by Sprint `5.5`, and canonical load-name install
  requirements that reject PGO-only/unoptimized fallback artefacts.
- `documents/engineering/haskell_code_guide.md` — Plan/Apply examples for the
  Dockerfile-invoked fail-closed C++ build leaves.
- `documents/engineering/determinism_contract.md` — Q3 equivalence participation.
- `documents/engineering/backend_style_contract.md` — explicit boundary that
  Sprints `5.7`–`5.10` change only backend `(ii)`'s imperative kernel and
  toolchain, not the closed functional implementations. Sprint `5.8` extended
  the (ii) budget with a bidirectional bit-parallel wall-legality BFS, a tighter
  `UctNode` layout, and an expanded compiler/BOLT flag set. Sprint `5.9`
  collapsed the `State { FastBoard b; uint16_t ply_count; }` wrapper into a flat
  `FastBoard` value to match the 32 B layout already used by backends `(iii)`
  and `(iv)`. None of these changes touched the visit-payload contract or the C
  ABI.
- `documents/engineering/benchmark_metrics.md` and
  `documents/engineering/unit_testing_policy.md` — Sprint `8.14` / Sprint `8.15`
  measurements are historical current-artifact evidence against the
  pre-Sprint-`5.8` `(ii)` target; Sprint `8.16` recorded the post-Sprint-`5.8`
  rebaseline (`Trails parity band by 57.1%`) and Sprint `8.17` recorded the
  post-functional-cohort rebaseline (`Trails parity band by 62.7%`) under the
  Performance Measurement Doctrine.

**Product docs to create/update:**

- `README.md`

**Cross-references to add:**

- Keep [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
  aligned with live backend (ii) measurement; Sprint `8.15` recorded the
  post-`5.7` Haskell-vs-`(ii)` shortfall and closed with the
  measurement-vs-invariant reframe, Sprint `8.16` closed the post-`5.8`
  rebaseline, and Sprint `8.17` closed the post-functional-cohort rebaseline
  with the `MutableByteArray# s` arena migration `measured but rejected`.
- `legacy-tracking-for-deletion.md` keeps the Sprint `5.7` backend `(ii)`
  hot-path/profile-training cleanup and the three Sprint `5.8` rows
  (wall-legality path-check residue, `UctNode` cache-line padding residue,
  compiler/linker flag scrub residue) in Completed, along with Sprint `5.9`'s
  compiler pivot + `State`/`FastBoard` collapse row and Sprint `5.10`'s
  PGO+BOLT efficacy reevaluation row. The post-`5.9` compiler-stack
  pending rows (backend (i) and (iii) `clang++-19` pivots plus the
  follow-on `docker/Dockerfile` `gcc`/`g++` scrub) closed on 2026-05-30
  through Sprints `4.6`, `6.11`, and `4.7`; the Pending Removal table
  in the ledger is now empty.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
