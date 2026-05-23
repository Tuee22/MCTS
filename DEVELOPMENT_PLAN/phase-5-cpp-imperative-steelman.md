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
Dockerfile-invoked `mcts build cpp-imperative` / `mcts build cpp-functional`
Plan/Apply recipes through the shared C++ PGO/BOLT target sequence. Sprint `5.3`
reclosed on 2026-05-23: C++ BOLT `.fdata` production is mandatory, PGO-only or
unoptimized fallback installs are removed, LLVM objcopy patches BOLT-produced
shared objects without corrupting them, and the Dockerfile build smokes the
installed bolted libraries before publishing the image. Sprint `5.5` reclosed
Phase `5` on 2026-05-21 by aligning the backend (ii) C ABI contract with the
compact live evidence ABI that exists, not speculative tree/rng lifecycle handles.

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

Phase `5` remains closed for the backend (ii) source, ABI, fail-closed PGO/BOLT
mechanics, and canonical artefact installation surfaces. Phase `8` Sprint `8.10`
owns the later requirement that the Dockerfile-time PGO/BOLT training workload be
broadened from the current narrow self-play smoke into the blended Q1/Q2 report-card
profile suite before final parity evidence is accepted.

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

- None.

### Closure Notes

- Closed on 2026-05-21 after the backend (ii) build-recipe dry-run,
  Dockerfile-owned build validation through `docker compose run --rm --build mcts mcts test mcts-unit`,
  `docker compose run --rm mcts mcts docs check`, and `git diff --check` passed.
- Sprint `6.6` retains the shared compact-ABI wording validation for backend (iii)
  and backend (iv).

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

**Product docs to create/update:**

- `README.md`

**Cross-references to add:**

- Keep [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
  aligned with live backend (ii) measurement.
- `legacy-tracking-for-deletion.md` carries Sprint `5.3` fail-open C++ PGO/BOLT
  residue until the Makefile/CLI path fails the Dockerfile build on missing `.fdata`;
  it carries Sprint `5.5` ABI overclaim residue until backend (ii)'s governed ABI
  and headers agree.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
