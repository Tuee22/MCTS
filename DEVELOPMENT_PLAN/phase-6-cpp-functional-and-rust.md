# Phase 6: Backends (iii) C++ Functional-Style and (iv) Rust

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Land backend (iii), a functional-style C++ steelman under the same
> optimization stack as backend (ii), and backend (iv) Rust as an independent
> cross-language systems baseline.

## Phase Status

✅ **Done.** Rust and `cpp-functional/` are live backends. Backend (iii)
remains first-class because it isolates C++ style from C++ optimization when
compared with backend (ii). The shared C++ PGO/BOLT Plan/Apply wiring closed in
Sprint `5.3`; Phase `6` does not duplicate that build harness. Sprint `6.4`
reclosed on 2026-05-23: Rust PGO profile data, merged `profdata`, BOLT `.fdata`,
the bolted cdylib, LLVM objcopy envelope patching, and the final installed
canonical Rust smoke run are all mandatory Dockerfile-build steps. Sprint `6.6`
reclosed this phase on 2026-05-21 by aligning backend (iii)'s compact ABI wording
with backend (ii), and by making Rust's instrumentation/build-artifact contract
match the code rather than a speculative paired-target description.

## Phase Summary

Backend (iii) keeps backend (ii)'s data layout, performance budget, compact C ABI
roles, and Makefile-level optimization target surface while expressing search flow
with functional-style C++ APIs and data flow. Backend (iv) Rust provides a second
systems-language implementation with its own release profile, supported PGO/BOLT
Plan/Apply recipe invoked by the Dockerfile, `mimalloc` allocator, Corridors
gameplay port, and C ABI. Its Dockerfile build must fail if PGO profile merge,
BOLT instrumentation, BOLT training, or BOLT optimization cannot produce the
required optimized cdylib. The final installed Rust cdylib is smoke-tested before
the image is published.

Phase `6` remains closed for backend (iii)/(iv) source, ABI, fail-closed PGO/BOLT
mechanics, Rust allocator/toolchain integration, and canonical artefact installation.
Phase `8` Sprint `8.10` owns the later requirement that the Dockerfile-time
PGO/BOLT training workload be broadened from the current narrow self-play smoke into
the blended Q1/Q2 report-card profile suite before final parity evidence is accepted.

## Sprint 6.1: C++ Functional-Style Engine ✅

**Status**: Done
**Implementation**: `cpp-functional/engine/{state.hpp,arena.hpp,xoshiro256pp.hpp,search.hpp,search.cpp}`,
`cpp-functional/c-abi/`, `cpp-functional/Makefile`
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`,
`documents/engineering/backend_ffi_contract.md`, `system-components.md`

### Objective

Build backend (iii) so the (ii)-vs-(iii) comparison isolates style, not optimization
effort.

### Deliverables

- Same arena memory layout and optimization stack as backend (ii).
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

None for the Rust source/ABI baseline.

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
- `RUSTFLAGS=-C target-cpu=native -C link-arg=-fuse-ld=lld
  -C link-arg=-Wl,--emit-relocs`.
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

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/backend_ffi_contract.md` — C++ functional and Rust ABI roles,
  including Sprint `6.6` compact-ABI and Rust artefact wording.
- `documents/engineering/compiler_runtime_tuning.md` — C++ functional/Rust tuning flags,
  mandatory Dockerfile-time PGO+BOLT success, and the concrete Rust build-artifact
  contract.
- `documents/engineering/haskell_code_guide.md` — Plan/Apply examples for the
  Dockerfile-invoked fail-closed Rust build leaf.
- `documents/engineering/determinism_contract.md` — Q3 participation and envelope fields.

**Product docs to create/update:**

- `README.md`

**Cross-references to add:**

- Keep [system-components.md](system-components.md) and
  [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
  aligned with backend (iii) and backend (iv) live status.
- `legacy-tracking-for-deletion.md` records Sprint `6.4` Rust BOLT fallback residue
  until the Dockerfile build fails on missing `.fdata`, and records Sprint `6.6`
  Rust/instrumentation residue as completed after governed docs and build comments
  agreed.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
