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

✅ **Done.** Rust and `cpp-functional/` are live backends. Backend (iii) remains
first-class because it isolates C++ style from C++ optimization when compared with
backend (ii).

## Phase Summary

Backend (iii) keeps backend (ii)'s data layout, performance budget, C ABI shape, and
optimization stack while expressing search flow with functional-style C++ APIs and data
flow. Backend (iv) Rust provides a second systems-language implementation with its own
release profile, PGO/BOLT path, `mimalloc` allocator, Corridors gameplay port, and C ABI.

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

### Validation

`docker compose run --rm mcts mcts build cpp-functional`

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

- `docker compose run --rm mcts mcts build cpp-functional`
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

- `docker compose run --rm mcts mcts build rust`
- `docker compose run --rm mcts mcts bench rollouts --backend rust --threading single --rng native --games 8 --seed 42 --cache-dir /tmp/mcts-rust-smoke`

### Remaining Work

None for the Rust source/ABI baseline.

## Sprint 6.4: Rust PGO/BOLT Build Harness ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Build.hs`, `rust/Cargo.toml`, `docker/Dockerfile`
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`

### Objective

Build Rust under a serious systems-language optimization envelope.

### Deliverables

- `[profile.release]` with `opt-level = 3`, fat LTO, one codegen unit,
  `panic = "abort"`, and stripped symbols.
- `RUSTFLAGS=-C target-cpu=native -C link-arg=-fuse-ld=lld`.
- `mimalloc::MiMalloc` as global allocator.
- Two-stage rustc PGO and BOLT post-link training/install path.

### Validation

- `docker compose run --rm mcts mcts build rust --dry-run`
- `docker compose run --rm mcts mcts build rust`
- `docker compose run --rm mcts mcts test mcts-unit`

### Remaining Work

None.

## Sprint 6.5: Shared Foreign Envelope and Recompute ✅

**Status**: Done
**Implementation**: `src/MCTS/FFI/Common.hs`, `src/MCTS/Engine/ForeignRecompute.hs`,
foreign `c-abi/envelope.*`
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

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/backend_ffi_contract.md` — C++ functional and Rust ABI roles.
- `documents/engineering/compiler_runtime_tuning.md` — C++ functional/Rust tuning flags.
- `documents/engineering/determinism_contract.md` — Q3 participation and envelope fields.

**Product docs to create/update:**

- `README.md`

**Cross-references to add:**

- Keep [system-components.md](system-components.md) and
  [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
  aligned with backend (iii) and backend (iv) live status.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
