# Phase 8: Haskell Performance Parity Closure and Five-Backend Restoration

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[00-overview.md](00-overview.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-3-haskell-engine.md](phase-3-haskell-engine.md),
[phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md),
[phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md),
[phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md),
[phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md),
[../documents/engineering/compiler_runtime_tuning.md](../documents/engineering/compiler_runtime_tuning.md)
**Generated sections**: none

> **Purpose**: Close the proof that backend (v) Haskell can match backend (ii)
> steelmanned imperative C++ on Q1/Q2 while preserving all five backends as live,
> reproducible comparison targets.

## Phase Status

The Haskell tuning work, no-generated-validation-data cleanup, and five-backend
restoration are closed. The stale two-backend drift has been corrected:
`cpp-legacy`, `cpp-imperative`, and `cpp-functional` are live
parser/build/verify/FFI participants alongside `rust` and `haskell`.

The restored end state is:

- Q1/Q2 performance rows measure backend (v) Haskell against live backend (ii)
  `cpp-imperative` where its shared library is available.
- Performance benchmarks use each backend's own/native deterministic RNG contract.
- Q3 logical-equivalence verification covers `(ii)..(v)` under `--rng cpp`.
- Q7 legacy-envelope verification covers all five backend slots.
- `--rng cpp` means equivalence tests consume C++-generated verification seeds through
  the shared C++ RNG bridge so game transcripts can be compared exactly.
- Generated validation data remains out of git; tests synthesize or explicitly generate
  evidence in temporary or operator-provided roots.

## Sprint 8.1: Haskell LLVM/RTS Baseline ✅

**Status**: Done
**Implementation**: `mcts.cabal`, `src/MCTS/Search/`, `src/MCTS/CLI/Test.hs`
**Docs to update**: `../documents/engineering/compiler_runtime_tuning.md`

### Objective

Establish the GHC/RTS baseline used for Haskell parity work.

### Deliverables

- GHC `-O2 -fllvm` plus the documented strictness/specialization flags.
- RTS baseline `-A64m -n4m -qg1 -qb -T`.
- Haskell search hot path structured around strict `ST` arena data and unboxed fields.

### Validation

The tuning baseline fed the later Q1/Q2 report-card runs.

### Remaining Work

None.

## Sprint 8.2: Haskell Hot-Path Profiling ✅

**Status**: Done
**Implementation**: `src/MCTS/Search/UCT.hs`, `src/MCTS/Engine.hs`, `src/MCTS/Types.hs`
**Docs to update**: `../documents/engineering/compiler_runtime_tuning.md`

### Objective

Remove Haskell hot-path bottlenecks until backend (v) is a credible performance
comparison against backend (ii).

### Deliverables

- Round 1 replaced list-heavy BFS work with an `IntSet`-backed approach and produced an
  approximate 6.2x speedup.
- Round 2 strict-pair `Word64` visited bitmap regressed and was reverted.
- Round 3 wavefront-bitmap BFS over a strict `Bits128` pair delivered roughly 52x on
  legal-moves and 33x on `uct-search` relative to round 1, roughly 320x / 200x relative
  to the original list-heavy baseline.

### Validation

The updated Q1 ST snapshot moved Haskell-vs-`cpp-imperative` from 10.76x slower to
0.89x of the non-PGO smoke library, making the full report-card comparison plausible.

### Remaining Work

None.

## Sprint 8.3: Performance Report Card ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Test.hs`,
`../documents/engineering/compiler_runtime_tuning.md`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`../documents/engineering/compiler_runtime_tuning.md`

### Objective

Record the Q1/Q2/Q5/Q7 evidence that demonstrates Haskell can meet the C++ steelman
target within `HASKELL_PARITY_TOLERANCE = 0.05`.

### Deliverables

- The 2026-05-19 report-card run recorded Q1 ST 0.05x, Q1 MT8 0.41x, Q2 ST 0.05x,
  Q2 MT8 0.20x, Q5 Haskell 0.99x, Q5 `cpp-imperative` 3.64x, Q7 liveness PASS, and
  verdict `Within tolerance`.
- The report-card numbers remain audit evidence, not checked-in generated validation
  inputs.

### Validation

The report-card evidence was produced through:

```bash
docker compose run --rm mcts mcts test all
```

### Remaining Work

None. The report-card path now measures live backend (ii) where the C++ shared library
is present.

## Sprint 8.4: Keep Generated Validation Data Out of Git ✅

**Status**: Done
**Implementation**: `test/unit`, `test/integration`, `src/MCTS/Generated/Paths.hs`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/code_quality.md`

### Objective

Ensure a clean clone can validate without pre-existing transcripts, report-card JSON,
renderer snapshots, or throughput files.

### Deliverables

- `test/golden/` generated inputs are not a normal validation prerequisite.
- Renderer, codec, transcript, report-card, and schema checks use semantic assertions,
  in-memory bytes, temporary directories, or explicit operator-provided artifact roots.
- `tasty-golden` is not required by the `mcts-unit` stanza.

### Validation

Closed through the Compose validation sequence recorded in
[README.md](README.md#closure-status).

### Remaining Work

None.

## Sprint 8.5: Restore Five-Backend Command and Build Surfaces ✅

**Status**: Done
**Implementation**: `src/MCTS/Types.hs`, `src/MCTS/CLI/Parser.hs`,
`src/MCTS/CLI/Spec.hs`, `src/MCTS/CLI/Build.hs`, `mcts.cabal`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`, `../documents/engineering/cli_command_surface.md`,
`../documents/engineering/haskell_code_guide.md`

### Objective

Restore the first-class backend surface for `cpp-legacy`, `cpp-imperative`,
`cpp-functional`, `rust`, and `haskell`.

### Deliverables

- `allBackends` enumerates all five backends.
- `parseBackend` accepts all five backend identifiers wherever the command surface owns
  a backend selection.
- `VerifyBackend` covers Q3 `(ii)..(v)`.
- `mcts verify legacy-parity` validates the Q7 `(i)..(v)` cohort.
- `mcts build cpp-legacy`, `mcts build cpp-imperative`, `mcts build cpp-functional`,
  `mcts build rust`, and `mcts build legacy-fixtures` are live Plan/Apply leaves.
- The generated command docs describe parity/equivalence surfaces without two-backend
  language.

### Validation

- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts build cpp-legacy --dry-run`
- `docker compose run --rm mcts mcts build cpp-imperative --dry-run`
- `docker compose run --rm mcts mcts build cpp-functional --dry-run`

### Remaining Work

None.

## Sprint 8.6: Restore C++ FFI Dispatch and Recompute ✅

**Status**: Done
**Implementation**: `src/MCTS/Driver/Dispatch.hs`,
`src/MCTS/Driver/ForeignSearch.hs`, `src/MCTS/FFI/Cpp*.hs`,
`src/MCTS/Engine/ForeignRecompute.hs`
**Docs to update**: `../documents/engineering/backend_ffi_contract.md`,
`../documents/engineering/determinism_contract.md`,
`../documents/engineering/compiler_runtime_tuning.md`

### Objective

Make the C++ backends live peers of Rust in bench/play/verify/inspect dispatch.

### Deliverables

- Dynamic C ABI loaders exist for `cpp-legacy`, `cpp-imperative`, and `cpp-functional`.
- Bench and play route selected C++ backends through their shared libraries when present.
- Recompute and divergence paths can fill C++ `.eq` sidecars through live FFI.
- C++ envelope loading participates in the same stale/live checks as Rust.
- Q1/Q2 report-card rows measure Haskell against live backend (ii) where available,
  rather than a static throughput anchor.

### Validation

- `docker compose run --rm mcts mcts build cpp-imperative`
- `docker compose run --rm mcts mcts build cpp-functional`
- `docker compose run --rm mcts mcts bench rollouts --backend cpp-imperative,haskell --threading single --rng native --games 8 --seed 42 --cache-dir /tmp/mcts-cpp-smoke`
- `docker compose run --rm mcts mcts inspect divergence <hash-prefix>` with a C++ sidecar
  candidate when a suitable transcript exists.

### Remaining Work

None.

## Sprint 8.7: Restore Logical Equivalence Gates ✅

**Status**: Done
**Implementation**: `src/MCTS/Verify.hs`, `src/MCTS/Driver/Dispatch.hs`,
`test/cross-backend`, `test/legacy-parity`
**Docs to update**: `../documents/engineering/determinism_contract.md`,
`../documents/engineering/unit_testing_policy.md`

### Objective

Restore the MCTS logical-equivalence proof without conflating it with performance RNG.

### Deliverables

- Q3 covers `(ii)..(v)` under `--rng cpp`.
- Q7 covers `(i)..(v)` under the legacy envelope.
- `--rng cpp` feeds equivalence verification from C++-generated seeds through the C++ RNG
  bridge only.
- `--rng native` remains the performance benchmark path, with backend-native RNGs.
- `mcts-cross-backend` and `mcts-legacy-parity` are live Cabal stanzas.
- `mcts-cross-backend` drives Q3 through real `mcts verify` subprocesses and
  serializes its Tasty tree around the process-pinned dynamic-library and shared
  C++ RNG bridge path.

### Validation

- `docker compose run --rm mcts mcts test mcts-cross-backend`
- `docker compose run --rm mcts mcts test mcts-legacy-parity`
- `docker compose run --rm mcts mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200`
- `docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500`

### Remaining Work

None.

## Sprint 8.8: Documentation and Standards Realignment ✅

**Status**: Done
**Implementation**: `README.md`, `DEVELOPMENT_PLAN/`, `documents/`
**Docs to update**: all governed docs touched by the five-backend restoration

### Objective

Make the project documentation match the original hypothesis with tighter language:
Haskell matches steelmanned C++, all five backends stay first-class, performance RNG is
backend-native, and equivalence RNG is C++-stream-compatible.

### Deliverables

- Root README states the five-backend architecture and RNG split clearly.
- Development plan standards forbid stale two-backend drift.
- `system-components.md` and this phase identify the restored five-backend surface and
  the validation evidence that closed it.
- Governed engineering docs under `documents/engineering/` match the five-backend target.
- Backend FFI and determinism docs identify the process-pinned envelope loader and C++
  RNG bridge used by equivalence verification.

### Validation

- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm --build mcts mcts test mcts-cross-backend`
- `docker compose run --rm --build mcts mcts test all`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`
- Residue search for stale two-backend wording in `README.md`, `DEVELOPMENT_PLAN/`,
  and `documents/`.

2026-05-20 closure evidence:

- Rebuilt `mcts test all` passed all five Cabal stanzas plus Q3 `(ii)..(v)` and Q7
  all-five legacy-envelope gates; report-card verdict: `Within tolerance`.
- `mcts docs check`, `mcts check-code`, and `git diff --check` passed after the
  temporary trace hooks were removed.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cli_command_surface.md` — command matrix and backend selection
  semantics.
- `documents/engineering/determinism_contract.md` — RNG split, Q3/Q7 equivalence scope,
  and engine-envelope language.
- `documents/engineering/backend_ffi_contract.md` — live C ABI contract for all four
  foreign backends.
- `documents/engineering/unit_testing_policy.md` — live `mcts-cross-backend` and
  `mcts-legacy-parity` roles without checked-in generated validation data.
- `documents/engineering/compiler_runtime_tuning.md` — performance parity against live
  backend (ii) and native-RNG benchmark semantics.
- `documents/engineering/haskell_code_guide.md` — command/build surface examples.

**Product docs to create/update:**

- `README.md`

**Cross-references to add:**

- Add or update backlinks from every governed doc above to this phase and
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) where cleanup
  ownership is referenced.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md)
- [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md)
- [../documents/engineering/backend_ffi_contract.md](../documents/engineering/backend_ffi_contract.md)
