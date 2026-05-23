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

🔄 **Active.** The Haskell tuning work, no-generated-validation-data cleanup,
five-backend restoration, and optimized-C++ report-card refresh previously closed.
Sprint `5.3` routes the Dockerfile-invoked `mcts build cpp-imperative` and
`mcts build cpp-functional` recipes through the shared C++ PGO/BOLT target sequence,
and Sprint `8.3` refreshed the report-card evidence on 2026-05-21 against the
canonical backend (ii) artefact produced by that Dockerfile-invoked build surface.
The 2026-05-23 fail-closed reclosure removed PGO-only/BOLT-missing fallback
installs from Sprints `5.3` and `6.4`; Sprint `8.3` then refreshed the report
card against successful Dockerfile-time PGO/BOLT artefacts and reclosed.
Sprint `8.9` reclosed Phase `8` on 2026-05-21 after compiler-tuning wording and
final handoff revalidation passed through the root Compose entrypoint.

Phase `8` is reopened for Sprint `8.10` because the implemented PGO/BOLT training
runner in `src/MCTS/CLI/Build.hs` still uses a narrow one-game, single-threaded,
native-RNG self-play smoke workload with seed `42`, `--sims 100` for PGO, and
`--sims 50` for BOLT. That proves the profile pipeline is fail-closed, but it does
not fully leverage PGO/BOLT for the two optimized benchmark families. Final parity
closure now requires Dockerfile-time training over a blended Q1/Q2 report-card suite:
random rollouts and MCTS self-play, single-threaded and 8-worker batches, native
RNG, multiple fixed seeds, and self-play budgets representative of
`S_BENCH = 500`. The stale two-backend drift remains corrected: `cpp-legacy`,
`cpp-imperative`, and `cpp-functional` are live parser/build/verify/FFI
participants alongside `rust` and `haskell`.

The restored end state is:

- Q1/Q2 performance rows measure backend (v) Haskell against live backend (ii)
  `cpp-imperative` where its shared library is available; accepted closure evidence
  must use Dockerfile-built artefacts that completed PGO and BOLT without fallback
  and trained on the blended Q1/Q2 report-card workload suite.
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
0.89x of the historical non-PGO smoke library. That made the full report-card
comparison plausible, but smoke-library evidence is not a current closure gate.

### Remaining Work

None.

## Sprint 8.3: Performance Report Card ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Test.hs`,
`../documents/engineering/compiler_runtime_tuning.md`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`, `../documents/engineering/compiler_runtime_tuning.md`,
`../documents/engineering/unit_testing_policy.md`

### Objective

Record the Q1/Q2/Q5/Q7 evidence that demonstrates Haskell can meet the C++ steelman
target within `HASKELL_PARITY_TOLERANCE = 0.05`.

### Deliverables

- The 2026-05-23 fail-closed report-card run recorded Q1 ST 0.05x
  (`640.3` vs `34.4` games/s), Q1 MT8 0.45x (`592.9` vs `269.5` games/s),
  Q2 ST 0.06x (`0.5` vs `0.0` games/s), Q2 MT8 0.22x
  (`0.5` vs `0.1` games/s), Q5 Haskell 0.98x, Q5 C++ (ii) 3.70x,
  Q7 liveness PASS, zero live-cohort divergence, and verdict
  `Within tolerance` against backend (ii)'s Dockerfile-built artefact after C++
  and Rust PGO/BOLT completed without fallback. Sprint `8.10` now treats this as
  fail-closed pipeline evidence until blended-profile training lands.
- The 2026-05-21 report-card run recorded Q1 ST 0.05x
  (`740.0` vs `39.2` games/s), Q1 MT8 0.43x (`690.7` vs `294.7` games/s),
  Q2 ST 0.06x (`0.6` vs `0.0` games/s), Q2 MT8 0.19x
  (`0.6` vs `0.1` games/s), Q5 Haskell 1.04x, Q5 `cpp-imperative` 3.64x,
  Q7 liveness PASS, and verdict `Within tolerance` against the then-canonical
  backend (ii) artefact built by `docker/Dockerfile` through the
  `mcts build cpp-imperative` recipe. This is historical evidence because C++ BOLT
  did not produce `.fdata` in that run.
- The report-card numbers remain audit evidence, not checked-in generated validation
  inputs.
- The 2026-05-19 report-card run remains historical smoke-baseline audit context:
  Q1 ST 0.05x, Q1 MT8 0.41x, Q2 ST 0.05x, Q2 MT8 0.20x, Q5 Haskell 0.99x,
  Q5 `cpp-imperative` 3.64x, Q7 liveness PASS, and verdict `Within tolerance`.
- `mcts test parity-anchor <baseline> <candidate>` is the focused Plan/Apply
  parity measurement surface for explicit backend pairs. It shares the Q1/Q2
  workloads, build prerequisites, and `HASKELL_PARITY_TOLERANCE = 0.05`
  verdict logic with the Phase `8` report-card proof.

### Validation

The report-card evidence was produced through:

```bash
docker compose run --rm --build mcts mcts test all
```

The focused parity-anchor surface is validated by:

```bash
docker compose run --rm mcts mcts test parity-anchor cpp-imperative haskell --dry-run
```

### Current Validation State

The report-card path measures live backend (ii) where the C++ shared library is
present. The 2026-05-23 aggregate run rebuilt the Dockerfile-owned C++ and Rust
PGO/BOLT artefacts first, required non-empty BOLT profiles and passing
installed-library smokes, then passed all Cabal stanzas, Q3 `(ii)..(v)`, Q7
all-five legacy-envelope checks, and the report-card verdict. Sprint `8.10` keeps
the final parity gate active until the same path runs against artefacts trained on
the blended Q1/Q2 profile suite.

### Remaining Work

None.

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
  and `mcts build rust` are Dockerfile-invoked Plan/Apply build recipes; the
  `legacy-fixtures` build leaf remains an explicit external evidence generator.
- The generated command docs describe parity/equivalence surfaces without two-backend
  language.

### Validation

- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts test mcts-unit`
- Backend build-recipe dry-runs for `cpp-legacy`, `cpp-imperative`, and
  `cpp-functional`

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

- `docker compose run --rm --build mcts mcts test mcts-cross-backend`
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
Haskell is measured against the live C++ comparison backend, all five backends stay
first-class, performance RNG is backend-native, and equivalence RNG is
C++-stream-compatible.

### Deliverables

- Root README states the five-backend architecture and RNG split clearly.
- Development plan standards forbid stale two-backend drift.
- `system-components.md` and this phase identify the restored five-backend surface,
  the historical smoke-baseline performance evidence, and the optimized-C++ evidence
  refresh.
- Governed engineering docs under `documents/engineering/` match the five-backend target.
- Backend FFI and determinism docs identify the process-pinned envelope loader and C++
  RNG bridge used by equivalence verification.
- README, the development plan, and governed engineering docs keep the SSoT boundaries
  explicit: `unit_testing_policy.md` owns the exact `mcts test all` sequence,
  `transcript_format.md` owns sidecar labels, `determinism_contract.md` owns
  replay/recompute mismatch semantics, and README remains operator-facing.

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
  all-five legacy-envelope gates; smoke-baseline report-card verdict:
  `Within tolerance`.
- `docker compose run --rm mcts mcts docs check`,
  `docker compose run --rm mcts mcts check-code`, and `git diff --check` passed
  after the temporary trace hooks were removed.

2026-05-21 closure evidence:

- The `cpp-imperative` and `cpp-functional` build-recipe dry-runs passed, and the
  Dockerfile-owned C++ build path passed through the supported C++ PGO/BOLT
  Plan/Apply sequence.
- `docker compose run --rm mcts mcts test all` passed all five Cabal stanzas, Q3
  `(ii)..(v)`, Q7 all-five legacy-envelope checks, and the optimized-C++ report-card
  refresh with verdict `Within tolerance`.
- Documentation SSoT alignment updated README, `DEVELOPMENT_PLAN/`, and `documents/`
  to defer exact test sequencing, replay overlay behavior, sidecar labels, and
  recompute mismatch semantics to their owning documents.

2026-05-23 fail-closed closure evidence:

- `docker compose run --rm --build mcts mcts test all` rebuilt C++ and Rust
  Dockerfile-owned PGO+BOLT artefacts, required non-empty BOLT profile data,
  patched BOLT-produced shared libraries with LLVM objcopy, smoked the installed
  canonical C++/Rust libraries, and passed docs, file, style, unit, integration,
  cross-backend, legacy-parity, and report-card validation.
- The report-card refresh recorded Q1 ST 0.05x, Q1 MT8 0.45x, Q2 ST 0.06x,
  Q2 MT8 0.22x, Q5 Haskell 0.98x, Q5 C++ (ii) 3.70x, Q7 liveness PASS, zero
  live-cohort divergence, and verdict `Within tolerance`.

### Remaining Work

None.

## Sprint 8.9: Tuning Documentation and Handoff Reclosure ✅

**Status**: Done
**Implementation**: `mcts.cabal`, `src/MCTS/CLI/Test.hs`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`,
`documents/engineering/unit_testing_policy.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Reclose the parity handoff after the evidence-surface corrections land, without
changing the high-level proof or treating stale documentation as proof.

### Deliverables

- `documents/engineering/compiler_runtime_tuning.md` accurately states where GHC
  `-fllvm` is load-bearing. The performance-relevant library, executable, and benchmark
  stanzas carry the optimization flags; test stanzas either carry the same flags or the
  docs explain why they compile/test library code without duplicating `-fllvm`.
- The report-card and parity-anchor docs continue to identify backend (ii)
  `cpp-imperative` as the performance ceiling and backend (v) Haskell as the candidate.
- `README.md`, `00-overview.md`, and `system-components.md` describe the final state
  after Sprints `1.10`, `2.8`, `5.5`, `6.6`, and `7.6` close.
- The aggregate validation gate passes through the root Compose entrypoint with no
  checked-in generated validation data.

### Validation

- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `docker compose run --rm --build mcts mcts test mcts-cross-backend`
- `docker compose run --rm --build mcts mcts test all`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

Sprint `8.9` reclosed on 2026-05-21. Validation passed with:

- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `docker compose run --rm --build mcts mcts test mcts-cross-backend`
- `docker compose run --rm --build mcts mcts test all`
- `git diff --check`

The 2026-05-21 `mcts test all` report-card verdict was `Within tolerance`; Q3
passed for `(ii)..(v)`, Q7 passed across all five backend slots, and all five Cabal
stanzas passed. Under the 2026-05-22 fail-closed doctrine this remains historical
fallback evidence. Sprint `8.3` refreshed the parity evidence on 2026-05-23
against successful PGO+BOLT artefacts.

## Sprint 8.10: Blended PGO/BOLT Training Suite 🔄

**Status**: Active
**Implementation**: `src/MCTS/CLI/Build.hs`, `src/MCTS/CLI/Test.hs`,
`cpp-imperative/Makefile`, `cpp-functional/Makefile`, `rust/Cargo.toml`,
`docker/Dockerfile`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`, `../documents/engineering/compiler_runtime_tuning.md`,
`../documents/engineering/backend_ffi_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/haskell_code_guide.md`

### Objective

Make the Dockerfile-time PGO/BOLT profiles represent the two benchmark families the
project optimizes: Q1 random rollouts and Q2 MCTS self-play, both single-threaded
and multi-worker, under the native-RNG performance path.

### Deliverables

- `mcts build cpp-imperative`, `mcts build cpp-functional`, and `mcts build rust`
  keep their Dockerfile-owned Plan/Apply boundaries. Runtime commands consume the
  canonical shared libraries and never retrain PGO, rerun BOLT, or choose between
  workload-specific optimized libraries.
- PGO training uses a blended suite for each steelman backend:
  `bench rollouts` plus `bench selfplay`, `--threading single` plus
  `--threading multi --workers 8`, `--rng native`, multiple fixed seeds, and
  self-play sim budgets representative of `S_BENCH = 500`.
- BOLT training uses a shorter version of the same blended shape so image builds stay
  practical while still exercising rollout, tree-descent, and MT dispatch hot paths.
- C++ profile roots contain the required `.gcda` data for every optimized C++ artefact
  before `-fprofile-use` runs. Rust profile roots contain `.profraw` files and a
  non-empty `merged.profdata` before `-Cprofile-use` runs.
- BOLT profile roots contain non-empty `.fdata` generated by `llvm-bolt -instrument`
  for the C++ and Rust optimized shared libraries before `llvm-bolt -reorder-blocks`
  runs.
- The Dockerfile build installs only bolted canonical libraries after PGO+BOLT data
  exists, LLVM objcopy patches the final envelope build-id, and each installed
  library passes the bounded smoke run before runtime validation starts.
- The 2026-05-23 report-card numbers remain audit evidence for fail-closed mechanics;
  Sprint `8.10` owns the final parity rerun against blended-profile artefacts.

### Validation

- `docker compose run --rm mcts mcts build cpp-imperative --dry-run`
- `docker compose run --rm mcts mcts build cpp-functional --dry-run`
- `docker compose run --rm mcts mcts build rust --dry-run`
- `docker compose run --rm --build mcts mcts test all`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

- Replace the single `trainingRunFor` smoke command in `src/MCTS/CLI/Build.hs` with a
  typed training-plan builder that emits the blended PGO and shorter blended BOLT
  command sequences.
- Ensure C++ Makefile targets and Rust profile merge checks consume every generated
  profile file needed by the expanded training suite and still fail closed on empty
  outputs.
- Add focused unit coverage for the expanded C++ and Rust build plans without checking
  generated profile files into git.
- Rebuild the Docker image, run the aggregate validation gates, and record the
  post-Sprint `8.10` Q1/Q2/Q5/Q7 report-card evidence in this phase and the compiler
  tuning doc.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cli_command_surface.md` — command matrix and backend selection
  semantics.
- `documents/engineering/determinism_contract.md` — RNG split, Q3/Q7 equivalence scope,
  and engine-envelope language.
- `documents/engineering/backend_ffi_contract.md` — live C ABI contract for all four
  foreign backends.
- `documents/engineering/unit_testing_policy.md` — live `mcts-cross-backend` and
  `mcts-legacy-parity` roles without checked-in generated validation data, plus the
  Sprint `8.10` blended-profile prerequisite for final report-card closure.
- `documents/engineering/compiler_runtime_tuning.md` — performance parity against live
  backend (ii), mandatory Dockerfile-time PGO+BOLT success for accepted evidence,
  native-RNG benchmark semantics, Sprint `8.9` Cabal-stanza flag wording, and the
  Sprint `8.10` blended Q1/Q2 PGO/BOLT training workload doctrine.
- `documents/engineering/haskell_code_guide.md` — command/build surface examples.

**Product docs to create/update:**

- `README.md`

**Cross-references to add:**

- Add or update backlinks from every governed doc above to this phase and
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) where cleanup
  ownership is referenced.
- Keep [README.md](README.md), [00-overview.md](00-overview.md), and
  [system-components.md](system-components.md) aligned with the active Sprint `8.10`
  training-workload follow-up, the closed Sprints `5.3`/`6.4` build-harness
  reclosures, and the cleanup residue recorded in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md)
- [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md)
- [../documents/engineering/backend_ffi_contract.md](../documents/engineering/backend_ffi_contract.md)
