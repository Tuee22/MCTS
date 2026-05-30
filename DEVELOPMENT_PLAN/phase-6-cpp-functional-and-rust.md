# Phase 6: Backends (iii) C++ Functional-Core and (iv) Rust

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Land backend (iii), a functional-core C++ steelman under the same
> optimization stack as backend (ii), and backend (iv) Rust as an independent
> cross-language systems baseline.

## Phase Status

✅ **Done.** Sprints `6.9` and `6.10` closed on 2026-05-29 for the
functional-cohort hot-path shape alignment; Sprint `6.11` closed on
2026-05-30 by pivoting backend `(iii)` cpp-functional from `g++` to
`clang++-19` and migrating its PGO half to the LLVM `.profraw` → merged
`.profdata` flow, mirroring backend `(ii)`'s Sprint `5.9` pivot. The
C ABI symbol set, canonical action ID encoding, 12-wall cap, transcript
wire format, and Q3/Q4/Q6/Q7 invariants are unchanged
(`normalized_divergence_score=0.0000`). Backends (iii) and (iv) match
or exceed backend (ii) on every primitive metric; the cohort ranking is
`rust ≥ cpp-functional ≈ cpp-imperative > haskell`. The fail-closed
Rust PGO/BOLT, backend (iii)/(iv) ABI wording, Sprint `6.7` compact
functional-core source-style surface, and Sprint `6.8` Rust hot-path
structural alignment remain closed on their owned surfaces.

## Phase Summary

Backend (iii) must keep backend (ii)'s performance budget, compact C ABI roles,
and Makefile-level optimization target surface while using a functional-core C++
style: compact value-state board, typed numeric action IDs, direct capped legal
action generation, bitfield path checks, and local scratch/arena mutation hidden
behind value-style transitions. Backend (iv) Rust provides the same functional-core
systems-language shape with Rust ownership idioms, its own release profile,
supported PGO/BOLT Plan/Apply recipe invoked by the Dockerfile, `mimalloc`
allocator, Corridors gameplay port, and C ABI. Its Dockerfile build must fail if
PGO profile merge, BOLT instrumentation, BOLT training, or BOLT optimization cannot
produce the required optimized cdylib. The final installed Rust cdylib is
smoke-tested before the image is published.

Phase `6` is closed for the validated ABI, fail-closed PGO/BOLT mechanics, Rust
allocator/toolchain integration, canonical artefact installation, backend
(iii)'s compact functional-core source/style alignment, and backend (iv)'s Rust
implementation shape. Rust now uses the same bit-parallel path checks,
fixed-capacity action buffers, arena sizing, and board-local visit cache
discipline as the aligned functional-core cohort.
Phase `8` Sprint `8.10` has since broadened the Dockerfile-time PGO/BOLT training
workload from the earlier narrow self-play smoke into a bounded profile suite.
Phase `8` Sprint `8.11` extended and validated that suite with primitive
terminal-playout and search-iteration profile runs after the metric refactor.

## Sprint 6.1: C++ Functional-Core Engine Baseline ✅

**Status**: Done
**Implementation**: `cpp-functional/engine/{state.hpp,arena.hpp,xoshiro256pp.hpp,search.hpp,search.cpp}`,
`cpp-functional/c-abi/`, `cpp-functional/Makefile`
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`,
`documents/engineering/backend_ffi_contract.md`, `system-components.md`

### Objective

Build backend (iii) so the (ii)-vs-(iii) comparison can isolate style, not
optimization effort.

### Deliverables

- Same flat-arena search class and optimization stack as backend (ii), with the
  source-style caveats closed by Sprint `6.7`.
- Functional-style move application, selection outcomes, and descent state transitions.
- C ABI with the same search/recompute/visit/envelope roles as backend (ii).
- The C++ functional PGO/BOLT Makefile targets mirror backend (ii); the
  Dockerfile-invoked recipe for the shared C++ PGO/BOLT sequence closed in
  Sprint `5.3`.

### Validation

`docker compose run --rm --build mcts mcts test mcts-cross-backend`

### Remaining Work

None.

## Sprint 6.2: C++ Functional Dispatch and Verify ✅

**Status**: Done
**Implementation**: `src/MCTS/FFI/CppFunctional.hs`,
`src/MCTS/Driver/Dispatch.hs`, `src/MCTS/Driver/ForeignSearch.hs`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/determinism_contract.md`

### Objective

Make backend (iii) participate in bench, play, inspect, recompute, and Q3 verify.

### Deliverables

- Dynamic loader for `libmcts_cpp_functional`.
- Live search and recompute dispatch.
- Q3 visit-vector equality participation under `--rng cpp`.
- Native-RNG benchmark participation under `--rng native`.

### Validation

- `docker compose run --rm --build mcts mcts test mcts-cross-backend`
- `docker compose run --rm mcts mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200`

### Remaining Work

None.

## Sprint 6.3: Rust Corridors Gameplay Port ✅

**Status**: Done
**Implementation**: `rust/src/board.rs`, `rust/src/rollout.rs`, `rust/src/search.rs`,
`rust/src/c_abi.rs`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/determinism_contract.md`

### Objective

Port the Corridors game rules and arena MCTS search into Rust behind the same C ABI
style used by the C++ backends.

### Deliverables

- 8x8 bitfield wall maps.
- Iterative BFS escapability checks.
- Post-move orientation flip using `u64::reverse_bits`.
- Uniform-random rollout over real legal moves.
- Search/recompute/read-visits/envelope C ABI.

### Validation

- `docker compose run --rm --build mcts mcts test mcts-cross-backend`
- `docker compose run --rm mcts mcts bench rollouts --backend rust --threading single --rng native --games 8 --seed 42 --cache-dir /tmp/mcts-rust-smoke`

### Remaining Work

None.

## Sprint 6.4: Rust PGO/BOLT Build Harness ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Build.hs`, `rust/Cargo.toml`, `rust/build.rs`,
`rust/src/allocator.rs`, `docker/Dockerfile`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`, `documents/engineering/compiler_runtime_tuning.md`,
`documents/engineering/backend_ffi_contract.md`,
`documents/engineering/haskell_code_guide.md`

### Objective

Build Rust under a serious systems-language optimization envelope.

### Deliverables

- `[profile.release]` with `opt-level = 3`, fat LTO, one codegen unit,
  `panic = "abort"`, and `strip = "debuginfo"` so BOLT can read symbols.
- `RUSTFLAGS=-C target-cpu=native -C link-arg=-B/usr/lib/llvm-19/bin
  -C link-arg=-fuse-ld=lld -C link-arg=-Wl,--emit-relocs`.
- `mimalloc` as the global allocator through the container system library and the
  local `SystemMiMalloc` `GlobalAlloc` wrapper; no crates.io allocator dependency is
  required for the Dockerfile build.
- Two-stage rustc PGO and BOLT post-link training/install path.
- Dockerfile build failure when `llvm-profdata`, BOLT `.fdata`, or the final
  optimized cdylib cannot be produced; PGO-only and unoptimized fallback installs
  are forbidden.
- LLVM objcopy patches the installed bolted cdylib's `engine_build_id`, and the
  build smokes the canonical `rust/target/release/libmcts_rust.so` before the
  image is published.
- The final Phase `8` parity gate broadens the training workload through Sprint
  `8.10`; this sprint owns fail-closed mechanics rather than the later workload mix.

### Validation

- `docker compose run --rm --build mcts mcts test mcts-unit`

The 2026-05-23 validation rebuilt the Docker image, ran Rust PGO
generate/train/merge/use, BOLT instrument/train/optimize, patched the installed
bolted cdylib with LLVM objcopy, smoked the canonical Rust library with
`bench selfplay --games 1 --sims 4`, and passed `mcts-unit` including the 14-step
Rust PGO/BOLT plan assertions.

### Remaining Work

None.

### Closure Notes

Sprint `6.4` reclosed on 2026-05-23. The Rust build now links the container
`libmimalloc` directly, keeps release symbols available to BOLT with
`strip = "debuginfo"`, emits relocations for BOLT, fails on missing `.fdata`, and
does not publish a PGO-only fallback cdylib.

## Sprint 6.5: Shared Foreign Envelope and Recompute ✅

**Status**: Done
**Implementation**: `src/MCTS/FFI/Common.hs`, `src/MCTS/Engine/ForeignRecompute.hs`,
`cpp-functional/c-abi/mcts_cpp_functional.{h,cc}`, `rust/src/envelope.rs`,
`rust/src/c_abi.rs`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/determinism_contract.md`

### Objective

Keep every foreign backend observable through the same envelope and recompute contract.

### Deliverables

- Runtime compiler/CPU/FP/libm envelope fields for C++ and Rust.
- Recompute ABI feeding `.eq` sidecars for inspect/replay/divergence.
- Dynamic stale/live envelope checks.
- Process-pinned dynamic envelope handles for process-static foreign envelope storage.
- Process-pinned C++ RNG bridge loading for equivalence seed generation.

### Validation

- `docker compose run --rm mcts mcts test mcts-integration`
- `docker compose run --rm mcts mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 2 --seed 42 --sims 16 --max-plies 60`
- `docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 1 --seed 42 --sims 16 --max-plies 60`
- `docker compose run --rm mcts mcts inspect divergence <hash-prefix>` where a suitable
  transcript and backend library are available.

### Remaining Work

None.

## Sprint 6.6: Functional/Rust ABI and Instrumentation Realignment ✅

**Status**: Done
**Implementation**: `cpp-functional/c-abi/`, `rust/Cargo.toml`, `rust/src/c_abi.rs`,
`src/MCTS/CLI/Build.hs`, `src/MCTS/FFI/CppFunctional.hs`, `src/MCTS/FFI/Rust.hs`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/compiler_runtime_tuning.md`,
`documents/engineering/determinism_contract.md`, `DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Keep backend (iii) and backend (iv) first-class without claiming build or
instrumentation shapes that are not present in the supported code path.

### Deliverables

- Backend (iii)'s governed ABI wording mirrors backend (ii)'s compact live ABI and
  does not claim tree/rng lifecycle symbols or visit-vector accessors that its header
  does not export.
- Rust's build and instrumentation contract is concrete. The current plan records Rust
  as a single optimized FFI artefact with search, recompute, read-visits, and envelope
  symbols. No separate Rust `_instrumented` artefact is part of the current contract.
- `documents/engineering/backend_ffi_contract.md` distinguishes load-bearing backend
  (ii) benchmark evidence from Rust's cross-language verification role, so the absence
  of a Rust paired instrumentation artefact is not confused with the C++ performance
  ceiling.
- Rust and C++ functional header comments, Haskell FFI bindings, and compiler-tuning
  docs agree on the actual artefact names produced by the Dockerfile-invoked build
  recipes.

### Validation

- C++ functional and Rust backend build-recipe dry-runs
- `docker compose run --rm --build mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts docs check`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

Sprint `6.6` reclosed on 2026-05-21. Validation passed with:

- C++ functional and Rust backend build-recipe dry-runs
- `docker compose run --rm --build mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts docs check`
- `git diff --check`

## Sprint 6.7: Functional-Core Compact State Alignment ✅

**Status**: Done
**Implementation**: `cpp-functional/engine/`, `cpp-functional/c-abi/`,
`rust/src/board.rs`, `rust/src/search.rs`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`,
`../documents/engineering/backend_style_contract.md`,
`../documents/engineering/compiler_runtime_tuning.md`,
`../documents/engineering/backend_ffi_contract.md`,
`../documents/engineering/determinism_contract.md`

### Objective

Make backend (iii) a high-performance functional-core C++ implementation that can
serve as the close stylistic template for backend (iv) Rust and backend (v)
Haskell, without copying backend (ii)'s imperative API shape.

### Deliverables

- Replace backend (iii)'s `corridors::board` search representation with a compact
  value-state board: pawn coordinates, remaining-wall counts, horizontal/vertical
  wall bitfields, `uint16_t` ply, and numeric `last_action`.
- Keep backend (iii) idiomatic C++23: value semantics at the boundary, `noexcept`
  helpers, `constexpr` action/wall mapping, stack/SBO move buffers, contiguous arena
  storage, and PGO/BOLT/`mimalloc` under the existing C++ build leaf.
- Remove `get_action_text`, `std::stoi`, full legacy wall-set generation, sort/filter
  canonicalization, and recursive legacy escapability from backend (iii)'s search and
  C ABI hot paths.
- Generate pawn actions plus the first 12 canonical legal walls directly by numeric
  action ID, preserving Q3 visit-vector order and transcript semantics.
- Keep Rust's compact value-state implementation aligned with the same names,
  transition boundaries, legal-action ordering, and local-mutation discipline where
  doing so improves reviewability without regressing performance.
- Leave backend (v) Haskell refactoring to Phase `8`, where Haskell parity work can
  align names or transition boundaries against the same style contract while keeping
  Phase `3`'s pure-engine baseline intact.

### Validation

- `docker compose run --rm --build mcts mcts test mcts-cross-backend`
- `docker compose run --rm mcts mcts test mcts-legacy-parity`
- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts bench terminal-playouts --backend cpp-imperative,cpp-functional --rng native --threading single --count 1000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench search-iters --backend cpp-imperative,cpp-functional --rng native --threading single --count 1000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Current Validation State

Sprint `6.7` closed on 2026-05-26. Backend (iii) now stores compact value-state
fields directly in `cpp-functional/engine/state.hpp`, generates capped numeric
legal successors without `corridors::board`, and applies C ABI actions through
`try_advance`. The old backend-local legacy `board.*` and `mcts.hpp` copies were
removed from `cpp-functional/engine/`, and `cpp-functional/Makefile` builds only
the compact search/ABI translation units.

The focused rebuilt-image performance checks show backend (iii) broadly matching
backend (ii): terminal playout ST is `19416.9` vs `21508.3` playouts/s, and
search-iteration ST is `20694.1` vs `20051.8` search-iters/s
(`cpp-functional` vs `cpp-imperative`, seed `42`, count `1000`, max plies `60`).
Rust already had the compact value-state boundary, so no Rust source changes
were needed for Sprint `6.7`'s backend (iii) closure. Later raw-performance review
showed that this was not enough for Rust: Sprint `6.8` later replaced the remaining Rust
hot-path residue without changing the Sprint `6.7` C++ functional closure claim.

### Remaining Work

None.

## Sprint 6.8: Rust Hot-Path Structural Alignment ✅

**Status**: Done
**Implementation**: `rust/src/board.rs`, `rust/src/search.rs`, `rust/src/tree.rs`,
`rust/src/c_abi.rs`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`,
`../documents/engineering/backend_style_contract.md`,
`../documents/engineering/compiler_runtime_tuning.md`,
`../documents/engineering/backend_ffi_contract.md`

### Objective

Make backend (iv) Rust use the same structural hot path as backend (iii)
`cpp-functional` and backend (v) Haskell while preserving the existing C ABI,
Q3/Q6 semantics, Rust ownership boundaries, and Dockerfile-owned PGO/BOLT build
contract.

### Deliverables

- Replace Rust's queue-based escapability check with bit-parallel `u128`
  wavefront masks derived from the 8x8 horizontal and vertical wall bitfields.
- Replace per-rollout and per-expansion heap `Vec<u8>` legal-action buffers with a
  fixed-capacity action buffer for pawn moves plus the first 12 legal walls.
- Reserve the Rust search arena to the same child-bound shape used by C++ and
  Haskell, avoiding node/state vector reallocation during ordinary search budgets.
- Reduce avoidable board cloning in expansion and descent while keeping value-state
  transitions at the API boundary.
- Move optional `read_visits` state into the opaque Rust board handle instead of the
  global synchronized board-address map.
- Keep `mcts_rust_*` C ABI symbols and transcript action IDs unchanged.

### Validation

- `docker compose run --rm --build mcts mcts bench terminal-playouts --backend cpp-functional,rust,haskell --rng native --threading single --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench search-iters --backend cpp-functional,rust,haskell --rng native --threading single --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200`
- `docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500`
- `docker compose run --rm mcts mcts test mcts-cross-backend`
- `docker compose run --rm mcts mcts test mcts-legacy-parity`
- `docker compose run --rm mcts mcts test all`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Current Validation State

Sprint `6.8` closed on 2026-05-28. The focused native-RNG single-threaded
benchmarks over `cpp-functional`, `rust`, and `haskell` passed with Rust in the
functional-core cohort range:

- `terminal-playouts`, count `20000`, seed `42`, max plies `60`: Rust
  `22213.0` playouts/s, `cpp-functional` `20927.8`, Haskell `31008.9`.
- `search-iters`, count `20000`, seed `42`, max plies `60`: Rust `23164.4`
  search-iters/s, `cpp-functional` `22436.5`, Haskell `33278.1`.

The focused correctness gates also passed:

- `verify rollouts` for `(ii)..(v)`, 4 games, seed `42`, max plies `200`;
- `verify selfplay` for `(ii)..(v)`, 4 games, seed `42`, max plies `200`,
  `--sims 500`;
- `mcts-cross-backend`;
- `mcts-legacy-parity`.

The aggregate docs/code/final-test gates are shared with Sprint `7.11` closure
because both reopened surfaces landed in the same worktree update.

### Remaining Work

None.

## Sprint 6.9: Backend (iii) Hot-Path Shape Alignment ✅

**Status**: Done
**Implementation**: `cpp-functional/engine/state.hpp`, `cpp-functional/engine/arena.hpp`,
`cpp-functional/engine/search.hpp`, `cpp-functional/engine/search.cpp`,
`cpp-functional/c-abi/mcts_cpp_functional.cc`, `cpp-functional/Makefile`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`,
`../documents/engineering/backend_style_contract.md`,
`../documents/engineering/compiler_runtime_tuning.md`,
`../documents/engineering/backend_ffi_contract.md`

### Objective

Adopt every backend-(ii) hot-path technique the functional-core style contract
permits for backend (iii), so any remaining Q1a/Q1b/Q2 gap to backend (ii) is
attributable to C++ functional-core API/data-flow shape rather than to
unadopted permitted optimisations. The C ABI symbol set, the canonical action
ID encoding, the 12-wall cap, the transcript wire format, and the Q3/Q4/Q6/Q7
invariants must remain unchanged. Sprint `6.9` must not reopen any of Sprints
`6.1`–`6.8`.

### Deliverables

- **Absolute `SideToMove` field on `State`.** Drop `flipped_after_move()` from
  every transition; toggle the new field instead. `child_after_action` keeps
  value-state semantics. Canonical action ID semantics and Q3 visit payload
  bit-equality are preserved. Mirrors
  `cpp-imperative/engine/fast_board.hpp:19,56,112–134` Sprint `5.7`.
- **Reusable `BlockMasks` precomputed once per `legal_actions` call.** Wall
  candidates run against `add_wall_to_masks(trial_masks, candidate)` plus two
  `path_exists_with_masks(side)` calls. No per-candidate 56-byte `State` copy
  and no inline mask recomputation. Mirrors
  `cpp-imperative/engine/fast_board.hpp:40–45,249–273`.
- **Bidirectional bit-parallel BFS in `path_exists_with_masks`.** Two
  simultaneous `unsigned __int128` frontiers (from start cell and from goal
  row) with intersect-or-extinct termination. Mirrors
  `cpp-imperative/engine/fast_board.hpp:296–345` Sprint `5.8`.
- **Action-only `UctNode`; `State` materialized on the descent stack.** The
  node footprint drops to `parent_idx`, `first_child_idx`, `n_children`,
  `action_id`, `visit_count`, `q_sum`, `expanded`, `terminal`. Search keeps a
  `State current` and a fixed-capacity `path` buffer through descent. Backprop
  walks the recorded path. Mirrors `cpp-imperative/engine/arena.hpp:34–43` and
  `cpp-imperative/engine/search.cpp:132–178`.
- **`cpp-functional/Makefile` flag/BOLT scrub parity with Sprint `5.8`.** Add
  `-fno-stack-protector -fno-rtti -fipa-pta` to the C++ functional flag block.
  Extend BOLT invocation with `-split-functions -split-strategy=cdsplit
  -reorder-functions=cdsort -icf=1` on top of the existing
  `-reorder-blocks=ext-tsp`. No harness change in `src/MCTS/CLI/Build.hs`.
- **`legacy-tracking-for-deletion.md` row movement.** The five Sprint `6.9`
  Pending Removal rows move to Completed with the same date-and-file-path
  format the existing rows use.

### Validation

```bash
docker compose run --rm --build mcts mcts test mcts-cross-backend
docker compose run --rm mcts mcts test mcts-legacy-parity
docker compose run --rm mcts mcts test mcts-unit
docker compose run --rm mcts mcts test mcts-semantic-parity
docker compose run --rm mcts mcts bench terminal-playouts --backend cpp-imperative,cpp-functional,rust,haskell --rng native --threading single --count 20000 --seed 42 --max-plies 60
docker compose run --rm mcts mcts bench search-iters       --backend cpp-imperative,cpp-functional,rust,haskell --rng native --threading single --count 20000 --seed 42 --max-plies 60
docker compose run --rm mcts mcts bench selfplay           --backend cpp-imperative,cpp-functional,rust,haskell --rng native --threading single --games 4 --seed 42 --sims 500
docker compose run --rm mcts mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200
docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500
docker compose run --rm mcts mcts docs check
docker compose run --rm mcts mcts check-code
docker compose run --rm --build mcts mcts test all
git diff --check
```

`normalized_divergence_score` must remain `0.0000`. Q3/Q4/Q6/Q7 must remain
PASS. The verdict line is informational per
[../documents/engineering/compiler_runtime_tuning.md → Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine);
focused per-backend rates are recorded in `Closure Notes` when the sprint
flips to Done.

### Remaining Work

None.

### Closure Notes

Sprint `6.9` closed on 2026-05-29. All five deliverables landed without any
`measured but rejected` rows. The five Pending Removal rows owned by Sprint
`6.9` moved to Completed in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

Validation results:

- `mcts test mcts-cross-backend` — **PASS** (7/7); Q3 visit-equality holds
  across `(ii)..(v)` under `--rng cpp` after the backend (iii) rewrite.
- `mcts test mcts-legacy-parity` — **PASS** (2/2).
- `mcts test mcts-semantic-parity` — **PASS** (1/1; Q7).
- `mcts test mcts-unit` — **PASS** (29/29).
- `mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell
  --threading single --games 4 --seed 42 --max-plies 200 --sims 500` —
  **PASS** (4 backends agree on visit counts).
- `mcts test all` aggregate: Q3/Q4/Q6/Q7 **PASS**;
  `normalized_divergence_score=0.0000`; all six Cabal stanzas pass; verdict
  `Trails parity band by 65.1%` (informational measurement label, not a
  closure gate).

Focused native-RNG single-threaded benchmark deltas
(`bench terminal-playouts` and `bench search-iters`, `--count 5000 --seed 42
--max-plies 60`):

| Backend         | Q1a pre (playouts/s) | Q1a post (playouts/s) | Q1b pre (search-iters/s) | Q1b post (search-iters/s) |
|-----------------|---------------------:|----------------------:|-------------------------:|--------------------------:|
| cpp-imperative  |             `32634.1` |             `35082.9` |                `37688.7` |                 `36788.6` |
| **cpp-functional** |          `18705.0` |             **`35583.3`** |            `19075.9` |              **`37702.6`** |
| rust            |             `20186.3` |             `19767.0` |                `20732.6` |                 `20319.6` |
| haskell         |             `23337.1` |             `22943.4` |                `23707.8` |                 `23554.9` |

Backend (iii) `cpp-functional` Q1a ST gains `+90.2%` (`18705 → 35583`); Q1b
ST gains `+97.6%` (`19076 → 37703`). The implementation-shape gap to backend
(ii) is closed: cpp-functional now matches (and marginally exceeds)
cpp-imperative on both primitive metrics, confirming the analyst hypothesis
that the prior shortfall was the four shape deliverables above and the
Sprint `5.8` flag/BOLT scrub.

The aggregate `mcts test all` report-card raw rows show backend (iii)
running at `Q1a` `36303.9` ST / `220045.9` MT8 playouts/s, `Q1b`
`39180.3` ST / `296574.6` MT8 search-iters/s, `Q2` `2.2` ST / `7.3`
MT8 games/s — all in the cohort lead alongside backend (ii). Backend (v)
Haskell is now slower than backends (ii) and (iii) on every measured row,
matching the analyst prediction that "if (iii) and (iv) close their
headroom, Haskell's current lead over them inverts." Sprint `6.10` is now
unblocked.

## Sprint 6.10: Backend (iv) Hot-Path Shape Alignment ✅

**Status**: Done
**Implementation**: `rust/src/board.rs`, `rust/src/tree.rs`, `rust/src/search.rs`,
`rust/src/c_abi.rs`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`,
`../documents/engineering/backend_style_contract.md`,
`../documents/engineering/compiler_runtime_tuning.md`,
`../documents/engineering/backend_ffi_contract.md`

### Objective

Adopt the remaining permitted backend-(ii)/(v) hot-path techniques inside
backend (iv) Rust, and close the style-contract violation noted in
[../documents/engineering/backend_style_contract.md → Backend (iv) Rust Target](../documents/engineering/backend_style_contract.md)
where the optional visit cache lives on the search-board struct instead of on
the opaque handle. Preserve the C ABI symbol set, canonical action ID
encoding, 12-wall cap, transcript wire format, and Q3/Q4/Q6/Q7 invariants.

### Deliverables

- **Visit-cache relocation onto the opaque handle.** Remove `last_visit_len:
  u8`, `last_visit_actions: [u8; 16]`, and `last_visit_counts: [u32; 16]` (169
  bytes) from `MctsRustBoard` in `rust/src/board.rs`. Add the same triple to
  the opaque handle struct in `rust/src/c_abi.rs`. `apply_action_flip` no
  longer calls `clear_last_visits()`. The `mcts_rust_read_visits` C ABI
  symbol, its signature, and its observable behavior are unchanged. **Largest
  single yield in the sprint and a no-regret style-contract closure.**
- **Absolute `SideToMove` enum on `MctsRustBoard`.** Drop `flipped()` and
  `*self = self.flipped()` from `apply_action_flip`; toggle the new field.
  Mirrors Sprint `6.9` backend (iii) and Sprint `5.7` backend (ii).
- **Reusable `BlockMasks` in `legal_actions`.** Wall-candidate legality runs
  against an additively-extended `BlockMasks` value (~48 bytes of trial-mask
  copy) instead of a 196-byte `MctsRustBoard` clone. Mirrors backend (v)
  Haskell `src/MCTS/Engine.hs::blockMasks` / `addWallIdToMasks` and Sprint
  `6.9` backend (iii).
- **Bidirectional bit-parallel BFS in `path_exists_with_masks`.** Mirrors
  Sprint `6.9` backend (iii) and Sprint `5.8` backend (ii).
- **Action-only secondary `Vec` in `tree.rs`.** With `last_visit_*` removed
  and the `SideToMove` toggle in place, the parallel `Vec<MctsRustBoard>`
  element shrinks. Reserve to the existing child-bound formula.
- **Inlining and unreachable hints audit.** `#[inline(always)]` on
  `apply_action_flip`, `legal_actions`, `path_exists_with_masks`, the rollout
  body in `rust/src/search.rs`, and the descent body. `#[cold]` on terminal
  and early-exit paths. `core::hint::unreachable_unchecked` after the
  precondition-checked action-id decoding sites, each with a single-line
  `// safety:` comment.
- **`legacy-tracking-for-deletion.md` row movement.** The four Sprint `6.10`
  Pending Removal rows move to Completed.

The visit-cache relocation deliverable should land first inside the sprint as
the no-regret prerequisite; the others may land in any order.

### Validation

```bash
docker compose run --rm --build mcts mcts test mcts-cross-backend
docker compose run --rm mcts mcts test mcts-legacy-parity
docker compose run --rm mcts mcts test mcts-unit
docker compose run --rm mcts mcts test mcts-semantic-parity
docker compose run --rm mcts mcts bench terminal-playouts --backend cpp-imperative,cpp-functional,rust,haskell --rng native --threading single --count 20000 --seed 42 --max-plies 60
docker compose run --rm mcts mcts bench search-iters       --backend cpp-imperative,cpp-functional,rust,haskell --rng native --threading single --count 20000 --seed 42 --max-plies 60
docker compose run --rm mcts mcts bench selfplay           --backend cpp-imperative,cpp-functional,rust,haskell --rng native --threading single --games 4 --seed 42 --sims 500
docker compose run --rm mcts mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200
docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500
docker compose run --rm mcts mcts docs check
docker compose run --rm mcts mcts check-code
docker compose run --rm --build mcts mcts test all
git diff --check
```

Q3/Q4/Q6/Q7 must remain PASS; `normalized_divergence_score` must remain
`0.0000`.

### Remaining Work

None.

### Closure Notes

Sprint `6.10` closed on 2026-05-29. All six deliverables landed without any
`measured but rejected` rows. The four Pending Removal rows owned by Sprint
`6.10` moved to Completed in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

Implementation highlights:

- `rust/src/board.rs` rewrites `MctsRustBoard` as a compact value-state
  struct with an absolute `SideToMove` enum, replaces the per-transition
  `flipped()` reassignment with a side toggle in `apply_action_unchecked`,
  removes the 169-byte `last_visit_*` fields, adds a `BlockMasks` value
  precomputed once per `legal_actions` call, ports backend (ii)'s
  bidirectional bit-parallel BFS in `path_exists_with_masks`, and drops the
  per-wall-candidate `MctsRustBoard` clone in `wall_action_legal`.
- `rust/src/c_abi.rs` introduces `RustBoardHandle`, the opaque handle the C
  ABI hands out. `RustBoardHandle` owns the search-state plus the optional
  `last_visit_*` cache; the search machinery operates on the inner
  `MctsRustBoard`. `mcts_rust_read_visits` and every other C ABI symbol
  keep their existing signatures.
- `rust/src/tree.rs` replaces the parallel `Vec<MctsRustBoard>` + `Vec<Node>`
  with a single `Vec<Node>` action-only arena. `search.rs` materializes
  `MctsRustBoard` on the descent stack via `apply_action_unchecked` and
  walks a fixed-capacity `path: [u32; 256]` for backprop.
- `rust/src/search.rs` `terminal_outcome` is hero-perspective in the absolute
  frame; the rollout reuses a single `ActionBuffer` and applies absolute
  action IDs through `apply_action_unchecked`.

Validation results:

- `mcts test mcts-cross-backend` — **PASS** (7/7); Q3 visit-equality holds
  across `(ii)..(v)` under `--rng cpp` after the backend (iv) rewrite.
- `mcts test mcts-legacy-parity` — **PASS** (2/2).
- `mcts test mcts-semantic-parity` — **PASS** (1/1; Q7).
- `mcts test mcts-unit` — **PASS** (29/29).
- `mcts test all` aggregate: Q3/Q4/Q6/Q7 **PASS**;
  `normalized_divergence_score=0.0000`; all six Cabal stanzas pass; verdict
  `Trails parity band by 60.7%` (informational measurement label, not a
  closure gate).

Focused native-RNG single-threaded benchmark deltas
(`bench terminal-playouts` and `bench search-iters`, `--count 5000 --seed 42
--max-plies 60`):

| Backend         | Q1a pre (playouts/s) | Q1a post (playouts/s) | Q1b pre (search-iters/s) | Q1b post (search-iters/s) |
|-----------------|---------------------:|----------------------:|-------------------------:|--------------------------:|
| cpp-imperative  |             `35082.9` |             `35027.8` |                `36788.6` |                 `36897.2` |
| cpp-functional  |             `35583.3` |             `35315.3` |                `37702.6` |                 `37744.0` |
| **rust**        |             `19767.0` |             **`38864.2`** |            `20319.6` |              **`41515.0`** |
| haskell         |             `22943.4` |             `22900.8` |                `23554.9` |                 `23287.1` |

Backend (iv) `rust` Q1a ST gains `+96.6%` (`19767 → 38864`); Q1b ST gains
`+104.3%` (`20320 → 41515`). After Sprint `6.10`, rust leads the cohort on
every primitive metric.

The aggregate `mcts test all` report-card raw rows show backend (iv) at
`Q1a` `38941.1` ST / `256715.7` MT8 playouts/s, `Q1b` `42078.7` ST /
`290209.4` MT8 search-iters/s, `Q2` `2.2` ST / `7.8` MT8 games/s — the
cohort lead on every metric. The cohort ranking is now `rust ≥
cpp-functional ≈ cpp-imperative > haskell`, confirming the analyst
prediction that Haskell's pre-`6.9` lead over `(iii)`/`(iv)` would invert
once the functional cohort closed its permitted-but-not-adopted shape gap.
Sprint `8.17` is now unblocked.

## Sprint 6.11: Backend (iii) Compiler Pivot to clang++-19 ✅

**Status**: Done
**Implementation**: `cpp-functional/Makefile`,
`cpp-functional/c-abi/mcts_cpp_functional.cc`, `src/MCTS/CLI/Build.hs`,
`src/MCTS/Prerequisite.hs`, `test/integration/Main.hs`, `test/unit/Main.hs`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`,
`../documents/engineering/compiler_runtime_tuning.md`,
`../documents/engineering/backend_style_contract.md`

### Objective

Pivot backend `(iii)` cpp-functional from `g++` to `clang++-19` and
migrate its PGO half from GCC `.gcda` (`-fprofile-correction` etc.) to
LLVM `.profraw` → merged `.profdata` consumed via
`-fprofile-use=<file>`, mirroring backend `(ii)`'s Sprint `5.9` pivot.
Closes the last first-class backend on the compiler-stack alignment
needed before the Sprint `4.7` Dockerfile `gcc`/`g++` scrub.

### Deliverables

- `cpp-functional/Makefile` pins `CXX := clang++-19`, drops `-fipa-pta`
  (clang rejects; GCC-only) and `-fprofile-correction` (GCC-only), adds
  `-fuse-ld=lld`, and introduces a `pgo-merge` target that runs
  `llvm-profdata-19 merge -o $(PGO_DIR)/default.profdata <*.profraw>`.
  `pgo-{bench,instr}-use` consume `$(PGO_DIR)/default.profdata` via
  `-fprofile-use=…/default.profdata`.
- `src/MCTS/CLI/Build.hs::cppProfileStyleFor` maps both
  `cpp-imperative → CppLlvmProfile` and `cpp-functional → CppLlvmProfile`
  so `cppPgoBoltPlan` drives the LLVM `.profraw` flow for both live
  PGO+BOLT C++ backends. The GCC `.gcda` branch is retained in the
  source but is unreachable from the current mapping.
- `cpp-functional/c-abi/mcts_cpp_functional.cc` adds
  `__llvm_profile_write_file` / `__llvm_profile_reset_counters` weak
  symbols alongside the `__gcov_dump` / `__gcov_reset` fallback, gated
  on `__clang__`. The existing `g_envelope.compiler_id = 1` clang
  branch fires under the new build.
- `cpp-functional/c-abi/mcts_cpp_functional.cc::g_engine_build_id` picks
  up `__attribute__((used, retain, section(".envelope_build_id")))` so
  clang+LLD+LTO does not GC the `.envelope_build_id` section. Mirrors the
  Sprint `5.9` cpp-imperative fix.
- `src/MCTS/Prerequisite.hs::prerequisitesForBuild "cpp-functional"`
  swaps `cxx-gpp` for `cxx-clang19` and adds `llvm-profdata-19`; the
  `libmcts-cpp-functional-built` shared-lib node mirrors that change.
- `test/integration/Main.hs::expectedCompilerId` returns `1` (clang) for
  `CppFunctional`.
- `test/unit/Main.hs::exerciseCppBuildPlan` asserts the cpp-functional
  plan drives the `make pgo-merge` step (the legacy `.gcda` bash check
  is no longer reachable).

### Validation

- `docker compose run --rm --build mcts mcts test all` rebuilds the
  Docker image with the new Makefile and runs the orchestrated PGO+BOLT
  pipeline for all four foreign backends through the updated
  `cppPgoBoltPlan`.
- Closure gates: Q3, Q4, Q6, Q7 all PASS with
  `normalized_divergence_score = 0.0000`.
- Per-cell backend (iii) numbers should land near backend (iv) Rust
  given the same compiler-choice mechanism Sprint `5.9` measured on
  (ii).

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/backend_ffi_contract.md` — C++ functional and Rust ABI roles,
  including Sprint `6.6` compact-ABI and Rust artefact wording.
- `documents/engineering/backend_style_contract.md` — functional-core value-state
  contract for `(iii)`, `(iv)`, and `(v)`, Sprint `6.7` closure criteria, and
  Sprint `6.8` Rust hot-path alignment.
- `documents/engineering/compiler_runtime_tuning.md` — C++ functional/Rust tuning flags,
  mandatory Dockerfile-time PGO+BOLT success, the concrete Rust build-artifact
  contract, and the requirement that `(iii)` remove legacy representation costs before
  style is treated as the measured variable, plus the Rust wavefront/action
  buffer/arena/cache refactor.
- `documents/engineering/haskell_code_guide.md` — Plan/Apply examples for the
  Dockerfile-invoked fail-closed Rust build leaf.
- `documents/engineering/backend_ffi_contract.md` — Rust board-handle-local visit
  cache while preserving the existing C ABI.
- `documents/engineering/determinism_contract.md` — Q3 participation and envelope fields.

**Product docs to create/update:**

- `README.md`

**Cross-references to add:**

- Keep [system-components.md](system-components.md) and
  [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
  aligned with backend (iii), backend (iv), and the Phase `8` backend (v)
  style-alignment dependency.
- `legacy-tracking-for-deletion.md` records Sprint `6.4` Rust BOLT fallback residue
  until the Dockerfile build fails on missing `.fdata`, and records Sprint `6.6`
  Rust/instrumentation residue as completed after governed docs and build comments
  agreed. Sprint `6.7` records the backend (iii) legacy-board/text-action hot-path
  cleanup as completed after the compact functional-core rewrite landed. Sprint
  `6.8` records Rust's queue-BFS/action-buffer/arena/clone/cache residue as
  completed after the Rust hot-path structural refactor landed and validated.
  Sprint `6.9` records backend (iii)'s per-transition flip residue, per-candidate
  `State` copy and inline mask recompute residue, full-state embedded `UctNode`
  residue, unidirectional path-existence BFS residue, and C++ steelman flag/BOLT
  scrub parity gap as Pending Removal until the shape-alignment refactor lands.
  Sprint `6.10` records backend (iv)'s `last_visit_*`-on-search-board residue,
  per-transition flip residue, per-wall-candidate `MctsRustBoard` clone residue,
  and unidirectional path-existence BFS residue as Pending Removal until the
  shape-alignment refactor lands.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
- [../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md)
