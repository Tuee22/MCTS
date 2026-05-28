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

✅ **Done.** Sprint `5.7` closes Phase `5` for the full backend `(ii)` hot-path
steelman. The closed Sprint `5.3`, `5.5`, and `5.6` evidence remains valid for
parser/build/verify/FFI dispatch, Makefile-level PGO/BOLT/`mimalloc` targets,
fail-closed Dockerfile-owned C++ build mechanics, compact C ABI contract, and
compact `FastBoard` legacy-path removal. Sprint `5.7` removes the remaining
lower-level kernel residue: child-board materialization during legal generation,
per-child full-board orientation flips, full-state tree-node storage, repeated
wall/path-mask reconstruction, and trusted-search allocation/replay paths. The
fresh Phase `8` Sprint `8.15` report-card rebaseline now measures Haskell against
this stronger `(ii)` target and records an active Haskell parity shortfall.

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
ceiling; Phase `8` Sprint `8.15` owns the resulting Haskell-vs-`(ii)` parity
shortfall.

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

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/compiler_runtime_tuning.md` — C++ steelman flags, mandatory
  Dockerfile-time PGO+BOLT success, parity tolerance, and native-RNG benchmark
  semantics.
- `documents/engineering/backend_ffi_contract.md` — imperative C ABI symbols, using the
  compact live ABI surface owned by Sprint `5.5`, and canonical load-name install
  requirements that reject PGO-only/unoptimized fallback artefacts.
- `documents/engineering/haskell_code_guide.md` — Plan/Apply examples for the
  Dockerfile-invoked fail-closed C++ build leaves.
- `documents/engineering/determinism_contract.md` — Q3 equivalence participation.
- `documents/engineering/backend_style_contract.md` — explicit boundary that Sprint
  `5.7` changes only backend `(ii)`'s imperative kernel, not the closed functional
  implementations.
- `documents/engineering/benchmark_metrics.md` and
  `documents/engineering/unit_testing_policy.md` — mark the Sprint `8.14`
  report-card evidence as historical current-artifact evidence and Sprint `8.15`
  as active on the post-`5.7` Haskell shortfall.

**Product docs to create/update:**

- `README.md`

**Cross-references to add:**

- Keep [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
  aligned with live backend (ii) measurement; Sprint `8.15` is active on the
  measured Haskell-vs-`(ii)` shortfall.
- `legacy-tracking-for-deletion.md` keeps the Sprint `5.7` backend `(ii)`
  hot-path/profile-training cleanup in Completed and carries only the active
  Sprint `8.15` parity shortfall row for this handoff.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
