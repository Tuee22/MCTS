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

✅ **Done** for the currently validated ABI/build surfaces, backend (iii)
compact functional-core alignment, and Sprint `6.8` Rust hot-path structural
alignment. Rust and `cpp-functional/` remain live backends.
The fail-closed Rust PGO/BOLT, backend (iii)/(iv) ABI wording, and Sprint `6.7`
compact functional-core source-style surfaces are closed. Sprint `6.7` removed
backend (iii)'s legacy-board/action-text hot path and aligned the C++ functional
backend with the compact value-state style described in
[backend_style_contract.md](../documents/engineering/backend_style_contract.md).
Sprint `6.8` keeps that history intact: Rust already had the compact value-state
boundary, and now uses the same bit-parallel path checks, stack action buffers,
child-bound arena sizing, reduced clone discipline, and board-handle visit cache
shape that `(iii)` and `(v)` use.

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
Phase `8` Sprint `8.11` extends and validates that suite with primitive
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
showed that this was not enough for Rust: Sprint `6.8` replaces the remaining Rust
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

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
- [../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md)
