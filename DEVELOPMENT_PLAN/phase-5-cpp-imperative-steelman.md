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

✅ **Done.** `cpp-imperative/` contains the arena-MCTS steelman source, live
parser/build/verify/FFI dispatch, Makefile-level PGO/BOLT/`mimalloc` targets, and
supported `mcts build cpp-imperative` / `mcts build cpp-functional` Plan/Apply
wiring through the shared C++ PGO/BOLT target sequence. The 2026-05-21 validation
run closed Sprint `5.3`; Phase `8` then refreshed the report-card evidence against
the canonical backend (ii) artefact produced by that build surface. Sprint `5.5`
reclosed Phase `5` on 2026-05-21 by aligning the backend (ii) C ABI contract with
the compact live evidence ABI that exists, not speculative tree/rng lifecycle
handles.

## Phase Summary

Backend (ii) is deliberately steelmanned C++: C++23, GCC, `-O3`, LTO, PGO, BOLT,
`mimalloc`, arena allocation, flat child ranges, branch hints, `thread_local` scratch
buffers, a ply-cap draw rule, and a compact C ABI that exposes board lifecycle,
search, recompute, available visit evidence, and envelope operations. The supported
CLI build now drives the C++ PGO/BOLT target sequence for both steelman C++ backends
and installs the canonical shared library.
On the 2026-05-21 amd64 validation run, BOLT instrumentation produced no usable
`.fdata`, so the documented Makefile fallback installed the PGO artefact as the
bolted artefact.

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

`docker compose run --rm mcts mcts build cpp-imperative`

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

- `docker compose run --rm mcts mcts build cpp-imperative`
- `docker compose run --rm mcts mcts bench rollouts --backend cpp-imperative --threading single --rng native --games 8 --seed 42 --cache-dir /tmp/mcts-cpp-imperative`
- `docker compose run --rm mcts mcts test mcts-integration`

### Remaining Work

None.

## Sprint 5.3: PGO+BOLT+`mimalloc` Pipeline ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Build.hs`, `src/MCTS/Prerequisite.hs`,
`test/unit/Main.hs`, `cpp-imperative/Makefile`, `cpp-functional/Makefile`
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`

### Objective

Ensure backend (ii) represents serious optimized C++ rather than a strawman.

### Deliverables

- GCC release flags: `-std=c++23 -O3 -march=native -mtune=native -flto -fno-plt
  -fno-semantic-interposition -fvisibility=hidden -fvisibility-inlines-hidden
  -fno-exceptions`.
- No `-ffast-math` and no `-Ofast`.
- Makefile-level two-stage PGO train/use targets for `cpp-imperative` and
  `cpp-functional`.
- Makefile-level BOLT post-link targets with documented fallback when no usable
  `.fdata` is produced.
- `mimalloc` linked for the steelman backends.
- Supported `mcts build cpp-imperative` and `mcts build cpp-functional` Plan/Apply
  wiring through the PGO/BOLT target sequence.
- C++ build prerequisite coverage for PGO/BOLT profile directories and canonical
  shared-library artefacts.

### Validation

- `docker compose run --rm mcts mcts build cpp-imperative --dry-run`
- `docker compose run --rm mcts mcts build cpp-imperative`
- `docker compose run --rm mcts mcts build cpp-functional --dry-run`
- `docker compose run --rm mcts mcts build cpp-functional`
- `docker compose run --rm --build mcts mcts test mcts-unit`

2026-05-21 closure evidence:

- `docker compose run --rm mcts mcts build cpp-imperative --dry-run` and
  `docker compose run --rm mcts mcts build cpp-functional --dry-run` rendered the
  shared 18-step C++ PGO/BOLT Plan/Apply sequence.
- `docker compose run --rm mcts mcts build cpp-imperative` and
  `docker compose run --rm mcts mcts build cpp-functional` both completed through
  PGO generate/use, BOLT instrument/optimize, and canonical install. On amd64,
  `llvm-bolt` emitted no usable `.fdata`; the Makefile fallback copied the PGO
  artefacts as the bolted artefacts.
- `docker compose run --rm --build mcts mcts test mcts-unit` passed 28 cases,
  including the C++ PGO/BOLT plan and prerequisite coverage assertions.

### Remaining Work

None.

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
  only concrete artefacts produced by `mcts build cpp-imperative`; no unimplemented
  zero-overhead paired-target claim remains.
- Haskell FFI bindings and C header comments use the same symbol names and argument
  shapes as the governed ABI document.

### Validation

- `docker compose run --rm mcts mcts build cpp-imperative --dry-run`
- `docker compose run --rm mcts mcts build cpp-imperative`
- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts docs check`
- `git diff --check`

### Remaining Work

- None.

### Closure Notes

- Closed on 2026-05-21 after
  `docker compose run --rm mcts mcts build cpp-imperative --dry-run`,
  `docker compose run --rm mcts mcts build cpp-imperative`,
  `docker compose run --rm mcts mcts test mcts-unit`,
  `docker compose run --rm mcts mcts docs check`, and `git diff --check` passed.
- Sprint `6.6` retains the shared compact-ABI wording validation for backend (iii)
  and backend (iv).

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/compiler_runtime_tuning.md` — C++ steelman flags, PGO/BOLT,
  parity tolerance, and native-RNG benchmark semantics.
- `documents/engineering/backend_ffi_contract.md` — imperative C ABI symbols, using the
  compact live ABI surface owned by Sprint `5.5`.
- `documents/engineering/determinism_contract.md` — Q3 equivalence participation.

**Product docs to create/update:**

- `README.md`

**Cross-references to add:**

- Keep [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
  aligned with live backend (ii) measurement.
- `legacy-tracking-for-deletion.md` carries Sprint `5.5` ABI overclaim residue until
  backend (ii)'s governed ABI and headers agree.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
