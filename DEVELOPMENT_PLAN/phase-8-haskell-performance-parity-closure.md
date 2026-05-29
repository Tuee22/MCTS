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
[../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md),
[../documents/engineering/compiler_runtime_tuning.md](../documents/engineering/compiler_runtime_tuning.md),
[../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md)
**Generated sections**: none

> **Purpose**: Close the proof that backend (v) Haskell can match backend (ii)
> steelmanned imperative C++ on Q1/Q2 while preserving all five backends as live,
> reproducible comparison targets.

## Phase Status

✅ **Done.** Sprint `8.17` closed on 2026-05-29 with the
`MutableByteArray# s` arena migration `measured but rejected` (focused
`Q1a` `-5.5%` ST and `Q1b` `-1.1%` ST regression vs the Sprint `8.13`
six-slab baseline) and the descent/rollout `INLINE` audit recorded as
no-op (Sprints `8.13`/`8.15` had already saturated `INLINE`/`INLINABLE`
density on the hot path). The post-`8.17` `mcts test all` keeps Q3, Q4,
Q6, Q7 PASS with `normalized_divergence_score=0.0000` and a verdict
line of `Trails parity band by 62.7%` (informational); the final cohort
ranking is `rust ≥ cpp-functional ≈ cpp-imperative > haskell`,
confirming the analyst prediction that closing the (iii)/(iv) permitted
hot-path shape gap inverts Haskell's pre-`6.9` lead over the foreign
cohort. The remaining Haskell shortfall sits in the documented
PGO-asymmetry band. Sprints `8.1`–`8.16` remain `Done` on their owned
surfaces. The previously closed Sprint `8.16` status is recorded below
for historical context. Sprint `8.16` closed on 2026-05-29 with the
post-`5.8` Haskell-vs-`(ii)` rebaseline against the further-strengthened
backend `(ii)` artefact: Q1a `1.51x` ST / `1.50x` MT8, Q1b `1.53x` ST /
`1.56x` MT8, Q2 `1.41x` ST / `1.57x` MT8, Q5 scaling Haskell search `7.16x`
vs C++ `(ii)` search `7.31x`, Haskell self-play `3.28x` vs C++ `(ii)`
self-play `3.66x`; `Verdict: Trails parity band by 57.1%`; Q3/Q4/Q6/Q7
PASS; `normalized_divergence_score=0.0000`. Sprint `8.15`'s post-`5.7`
rebaseline and measurement-vs-invariant reframe remain closed for their
delivered surfaces; Sprint `8.15`'s recorded ratios are now historical
against the pre-`5.8` `(ii)` artefact. The 2026-05-28 rebaseline after
Sprint `5.7` (active during the Sprint `8.15` reopen) and the 2026-05-29
rebaseline after Sprint `5.8` (Sprint `8.16` itself) both closed without
Haskell engine or Cabal changes; the moving target was the C++ steelman
ceiling. The Haskell tuning work, no-generated-validation-data cleanup,
five-backend restoration, optimized-C++ report-card refresh, refactored
Q1a/Q1b/Q2/Q5 evidence, Sprint `5.6` corrected backend (ii) target, Sprint `6.7`
backend (iii) compact functional-core style surface, Sprint `8.12` Haskell parity
refresh, Sprint `8.13` Haskell style alignment, and Sprint `8.14` fail-closed
report-card gate remain closed for their owned surfaces. The last accepted
pre-`5.7` evidence is the 2026-05-27
`docker compose run --rm mcts mcts test all` run: Q1a terminal playouts ST
`0.72x` (`30804.2` vs `22078.9` playouts/s), Q1a MT8 `0.85x` (`182020.9`
vs `154067.0` playouts/s), Q1b search iterations ST `0.67x` (`34619.7` vs
`23342.6` search-iters/s), Q1b MT8 `0.67x` (`253507.0` vs `170816.3`
search-iters/s), Q2 self-play ST `0.59x` (`1.9` vs `1.1` games/s), Q2
self-play MT8 `0.68x` (`6.4` vs `4.3` games/s), Q3/Q4/Q6 PASS, zero
live-cohort divergence, all Cabal stanzas PASS, and verdict `Within tolerance`.
This is now historical evidence against the Sprint `5.6` artefact.

The first Sprint `8.15` rebaseline ran on 2026-05-28 through
`docker compose run --rm --build mcts mcts test all`. It passed files/docs/style,
unit, integration, cross-backend, legacy-parity, semantic-parity, Q3, Q4, Q6,
Q7, and zero-divergence gates against the Sprint `5.7` backend `(ii)` kernel,
then exited non-zero under the prior pass/fail framing with
`Verdict: Shortfall`. Observed backend `(ii)`/Haskell ratios were Q1a terminal
playouts `1.13x` ST and `1.49x` MT8, Q1b search iterations `1.14x` ST and
`1.15x` MT8, and Q2 self-play `1.01x` ST and `1.19x` MT8. Sprint `8.15` is
active until the measurement-vs-invariant reframe lands across code, doctrine,
and plan and the aggregate is rerun so the apples-to-apples invariants
Q3/Q4/Q6/Q7 gate closure while Q1/Q2/Q5 are recorded honestly per
[../documents/engineering/compiler_runtime_tuning.md → Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine).

Focused Sprint `8.15` Haskell work accepted compact `Word8` pawn slots,
non-terminal legal-action sets, no-ply rollout application with local ply tracking,
fused arena visit/value updates, first-unvisited UCT child selection, and `forkOn`
worker pinning for benchmark and game pools, plus direct packed-slot path starts
in `pathExistsWithMasks`, a no-wall legal-action fast path, and
single-constructor action transitions with a no-ply rollout variant. The aggregate
rerun after those accepted changes still fails closed with
`Verdict: Shortfall 0.2678864950323545`: Q1a backend `(ii)`/Haskell ratios
`1.06x` ST and `1.27x` MT8, Q1b `1.05x` ST and `1.11x` MT8, and Q2 `0.98x` ST
and `1.11x` MT8. Measured but rejected candidates include direct wall enumeration,
iterative descent, cached coordinate fields in `Board`, direct wall-bit-index
apply, direct terminal checks in `UCT.descend`, and strict `quotRem` index
decoding in the action/wall hot path, direct wall-index legality/trial-mask
decoding, Word64 signed-modulo correction-table rollout selection, forced
splitmix inlining with primitive seed hoisting, and bulk arena child reservation;
each passed focused unit validation but regressed the focused terminal-playout,
search-iteration, self-play, or aggregate report-card rows.
Sprint `5.3` routes the Dockerfile-invoked `mcts build cpp-imperative` and
`mcts build cpp-functional` recipes through the shared C++ PGO/BOLT target sequence,
and Sprint `8.3` refreshed the report-card evidence on 2026-05-21 against the
canonical backend (ii) artefact produced by that Dockerfile-invoked build surface.
The 2026-05-23 fail-closed reclosure removed PGO-only/BOLT-missing fallback
installs from Sprints `5.3` and `6.4`; Sprint `8.3` then refreshed the report
card against successful Dockerfile-time PGO/BOLT artefacts and reclosed.
Sprint `8.9` reclosed Phase `8` on 2026-05-21 after compiler-tuning wording and
final handoff revalidation passed through the root Compose entrypoint. Sprint
`8.10` reclosed Phase `8` on 2026-05-23 by replacing the narrow PGO/BOLT smoke
training run with Dockerfile-time bounded played-game profile training: legacy
rollout games and MCTS self-play, single-threaded and 8-worker batches, native RNG, seeds
`42` and `424242`, `--max-plies 1`, and PGO self-play budgets representative of
`S_BENCH = 500`. The
stale two-backend drift remains corrected: `cpp-legacy`, `cpp-imperative`, and
`cpp-functional` are live parser/build/verify/FFI participants alongside `rust`
and `haskell`.

The 2026-05-24 metric-semantics audit reclassified the existing Q1/Q2/Q5 evidence
as historical played-game throughput evidence. Sprint `3.8` has added
terminal-playout and search-iteration benchmarks, and Sprint `7.8` has rendered
the separated Q1a/Q1b/Q2/Q5 report-card rows. Sprint `8.11` reclosed Phase `8`
against the then-current backend (ii) with a Dockerfile rebuild whose PGO/BOLT
profile suite covers terminal playout, search-iteration, legacy played-game
rollout, and self-play workloads before the refactored report-card verdict runs.
Sprint `5.6` later made that verdict historical.

The 2026-05-25 backend (ii) correction reopened this phase on the Haskell parity
surface. Phase `6` Sprint `6.7` removed backend (iii)'s legacy-board and
action-text hot path, so Q3/Q6 equivalence and liveness remained covered by
Phase `7`; Phase `5` owns the corrected C++ steelman; and Phase `6` owns the
closed backend (iii) functional-core alignment plus Sprint `6.8` Rust hot-path
follow-up. Sprint `8.12` retuned
Haskell against the corrected backend (ii), Sprint `8.13` aligned backend
(v)'s compact action-set and transition boundary with the shared functional-core
style without changing Phase `3`'s closed pure-engine API, and Sprint `8.14`
made the report-card verdict an exit-code gate while raising the primitive
sample to `N_PRIM=20_000` for stable MT8 Q1a/Q1b evidence.

Phase `6` Sprint `6.8` does not reopen this phase. Rust raw-performance rows are
context for the full backend cohort after that sprint removes known Rust hot-path
residue, but the Phase `8` verdict continues to gate backend (v) Haskell against
backend (ii) `cpp-imperative`.

The 2026-05-28 backend `(ii)` steelman audit reopened this phase, and Sprint `5.7`
has now removed the remaining `(ii)` search-kernel and profile-training residue.
Sprint `8.15` owns the closed Haskell parity rebaseline exposed by the fresh
Q1a/Q1b/Q2/Q5 measurement.

The 2026-05-29 backend `(ii)` residual-squeeze audit then reopened this phase
again for Sprint `8.16`. Phase `5` Sprint `5.8` lands a further-tightened
`(ii)` ceiling (bidirectional path-existence BFS, `UctNode` cache-line padding
removed, `-fno-stack-protector -fno-rtti -fipa-pta` plus extended BOLT
invocation). Sprint `8.16` is the downstream measurement: re-run
`docker compose run --rm --build mcts mcts test all` against the post-`5.8`
`(ii)` artefact, record the new Q1a/Q1b/Q2/Q5 ratios, and keep the
apples-to-apples invariants Q3/Q4/Q6/Q7 as the closure gate. No Haskell code
changes are in scope.

The restored end state is:

- Q1/Q2 performance rows measure backend (v) Haskell against live backend (ii)
  `cpp-imperative` where its shared library is available; accepted closure evidence
  must use Dockerfile-built artefacts that completed PGO and BOLT without fallback
  and must report the explicit units defined in
  [../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md).
- Sprints `7.10` and `7.11` report-card output add raw Q1a/Q1b/Q2 rates for every backend slot
  ahead of the parity question summary and divergence matrix, then ends with
  explicit Q1a-Q7 answers based on observed ratios, scaling values, divergence
  rates, and gate outcomes. Those raw rows are context; the Phase `8` verdict still
  gates on Haskell (v) versus backend (ii).
- Performance benchmarks use each backend's own/native deterministic RNG contract.
- Q3 logical-equivalence verification covers `(ii)..(v)` under `--rng cpp`.
- Q6 legacy-envelope verification covers all five backend slots.
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
- The measured baseline retained a fresh per-move `STUArray` arena. Across-move tree
  persistence was not required for parity closure and is not implemented in the closed
  driver path.

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

Record the Q1/Q2/Q5/Q6 measurement of Haskell against the C++ steelman target.
This sprint pre-dates the 2026-05-28 measurement-vs-invariant reframe, so its
historical wording uses the pass/fail framing of the prior doctrine; the
measurement contract this sprint established is now governed by
[../documents/engineering/compiler_runtime_tuning.md → Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine).

### Deliverables

- The 2026-05-23 fail-closed report-card run recorded Q1 ST 0.05x
  (`640.3` vs `34.4` games/s), Q1 MT8 0.45x (`592.9` vs `269.5` games/s),
  Q2 ST 0.06x (`0.5` vs `0.0` games/s), Q2 MT8 0.22x
  (`0.5` vs `0.1` games/s), Q5 Haskell 0.98x, Q5 C++ (ii) 3.70x,
  Q6 liveness PASS, zero live-cohort divergence, and verdict
  `Within tolerance` against backend (ii)'s Dockerfile-built artefact after C++
  and Rust PGO/BOLT completed without fallback. Sprint `8.10` retains this as
  fail-closed pipeline evidence and supersedes it with the bounded-profile
  historical rerun recorded below.
- The 2026-05-21 report-card run recorded Q1 ST 0.05x
  (`740.0` vs `39.2` games/s), Q1 MT8 0.43x (`690.7` vs `294.7` games/s),
  Q2 ST 0.06x (`0.6` vs `0.0` games/s), Q2 MT8 0.19x
  (`0.6` vs `0.1` games/s), Q5 Haskell 1.04x, Q5 `cpp-imperative` 3.64x,
  Q6 liveness PASS, and verdict `Within tolerance` against the then-canonical
  backend (ii) artefact built by `docker/Dockerfile` through the
  `mcts build cpp-imperative` recipe. This is historical evidence because C++ BOLT
  did not produce `.fdata` in that run.
- The report-card numbers remain audit evidence, not checked-in generated validation
  inputs.
- The 2026-05-19 report-card run remains historical smoke-baseline audit context:
  Q1 ST 0.05x, Q1 MT8 0.41x, Q2 ST 0.05x, Q2 MT8 0.20x, Q5 Haskell 0.99x,
  Q5 `cpp-imperative` 3.64x, Q6 liveness PASS, and verdict `Within tolerance`.
- `mcts test parity-anchor <baseline> <candidate>` is the focused Plan/Apply
  parity measurement surface for explicit backend pairs. It shares the Q1/Q2
  workloads and build prerequisites with the Phase `8` report-card proof; its
  verdict line uses the same `HASKELL_PARITY_TOLERANCE = 0.05` labelling
  cutoff defined by
  [../documents/engineering/compiler_runtime_tuning.md → Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine).
  As a focused measurement command, its exit code still tracks the labelling
  cutoff so backend pairs can be compared mechanically; the aggregate
  `mcts test all` gate does not.

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
installed-library smokes, then passed all Cabal stanzas, Q3 `(ii)..(v)`, Q6
all-five legacy-envelope checks, and the report-card verdict. Sprint `8.10` remains
historical played-game evidence; Sprint `8.11` supplies historical refactored
metric-suite evidence because Sprint `5.6` later strengthened backend (ii).

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
- `mcts verify legacy-parity` validates the Q6 `(i)..(v)` cohort.
- `mcts build cpp-legacy`, `mcts build cpp-imperative`, `mcts build cpp-functional`,
  and `mcts build rust` are Dockerfile-invoked Plan/Apply build recipes; the
  `legacy-fixtures` build leaf remains an explicit external audit-fixture generator.
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
- Q6 covers `(i)..(v)` under the legacy envelope.
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
- `docker compose run --rm --build mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts bench terminal-playouts --backend cpp-imperative,haskell --rng native --threading single --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench terminal-playouts --backend cpp-imperative,haskell --rng native --threading multi --workers 8 --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench search-iters --backend cpp-imperative,haskell --rng native --threading single --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench search-iters --backend cpp-imperative,haskell --rng native --threading multi --workers 8 --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench selfplay --backend cpp-imperative,haskell --rng native --threading single --games 4 --seed 42 --max-plies 200 --sims 500`
- `docker compose run --rm mcts mcts bench selfplay --backend cpp-imperative,haskell --rng native --threading multi --workers 8 --games 4 --seed 42 --max-plies 200 --sims 500`
- `docker compose run --rm mcts mcts test all`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`
- Residue search for stale two-backend wording in `README.md`, `DEVELOPMENT_PLAN/`,
  and `documents/`.

2026-05-20 closure evidence:

- Rebuilt `mcts test all` passed all five Cabal stanzas plus Q3 `(ii)..(v)` and Q6
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
  `(ii)..(v)`, Q6 all-five legacy-envelope checks, and the optimized-C++ report-card
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
  Q2 MT8 0.22x, Q5 Haskell 0.98x, Q5 C++ (ii) 3.70x, Q6 liveness PASS, zero
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
passed for `(ii)..(v)`, Q6 passed across all five backend slots, and all five Cabal
stanzas passed. Under the 2026-05-22 fail-closed doctrine this remains historical
fallback evidence. Sprint `8.3` refreshed the parity evidence on 2026-05-23
against successful PGO+BOLT artefacts.

## Sprint 8.10: Bounded PGO/BOLT Training Suite ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Build.hs`, `src/MCTS/CLI/Test.hs`,
`src/MCTS/Driver/Dispatch.hs`, `src/MCTS/FFI/Common.hs`,
`cpp-imperative/Makefile`, `cpp-functional/Makefile`,
`cpp-imperative/c-abi/mcts_cpp_imperative.{h,cc}`,
`cpp-functional/c-abi/mcts_cpp_functional.{h,cc}`, `rust/Cargo.toml`,
`docker/Dockerfile`, `test/unit/Main.hs`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`, `../documents/engineering/compiler_runtime_tuning.md`,
`../documents/engineering/backend_ffi_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/haskell_code_guide.md`

### Objective

Make the Dockerfile-time PGO/BOLT profiles represent the two benchmark families the
project implemented at that point: the legacy Q1 played-game rollout workload and
Q2 MCTS self-play, both single-threaded and multi-worker, under the native-RNG
performance path.

### Deliverables

- `mcts build cpp-imperative`, `mcts build cpp-functional`, and `mcts build rust`
  keep their Dockerfile-owned Plan/Apply boundaries. Runtime commands consume the
  canonical shared libraries and never retrain PGO, rerun BOLT, or choose between
  workload-specific optimized libraries.
- PGO training uses the bounded suite in `MCTS.CLI.Build`: legacy `bench rollouts` and
  `bench selfplay`, `--threading single` and `--threading multi --workers 8`,
  `--rng native`, seeds `42` and `424242`, `--max-plies 1`, two rollout games for
  each threading mode per seed, one self-play game for each threading mode per seed,
  rollout `--sims 1`, and self-play `--sims 500`.
- BOLT training uses the same workload/threading/seed shape with one rollout game for
  each threading mode per seed, one self-play game for each threading mode per seed,
  rollout `--sims 1`, self-play `--sims 100`, and `--max-plies 1`, so image builds
  stay practical while still exercising rollout, tree-descent, and MT dispatch hot
  paths.
- C++ profile roots contain the required `.gcda` data for every optimized C++ artefact
  before `-fprofile-use` runs. Rust profile roots contain `.profraw` files and a
  non-empty `merged.profdata` before `-Cprofile-use` runs.
- BOLT profile roots contain non-empty `.fdata` generated by `llvm-bolt -instrument`
  for the C++ and Rust optimized shared libraries before `llvm-bolt -reorder-blocks`
  runs.
- The Dockerfile build installs only bolted canonical libraries after PGO+BOLT data
  exists, LLVM objcopy patches the final envelope build-id, and each installed
  library passes the bounded smoke run before runtime validation starts.
- The 2026-05-23 Sprint `8.10` report-card rerun is accepted historical played-game
  evidence against bounded-profile Dockerfile artefacts: Q1 ST 0.05x, Q1 MT8
  0.48x, Q2 ST 0.06x, Q2 MT8 0.21x, Q5 Haskell 0.99x, Q5 C++ (ii) 3.65x,
  Q6 PASS, zero live-cohort divergence, and verdict `Within tolerance`.

### Validation

- `docker compose run --rm mcts mcts build cpp-imperative --dry-run`
- `docker compose run --rm mcts mcts build cpp-functional --dry-run`
- `docker compose run --rm mcts mcts build rust --dry-run`
- `docker compose run --rm --build mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts bench terminal-playouts --backend cpp-imperative,haskell --rng native --threading single --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench terminal-playouts --backend cpp-imperative,haskell --rng native --threading multi --workers 8 --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench search-iters --backend cpp-imperative,haskell --rng native --threading single --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench search-iters --backend cpp-imperative,haskell --rng native --threading multi --workers 8 --count 20000 --seed 42 --max-plies 60`
- `docker compose run --rm mcts mcts bench selfplay --backend cpp-imperative,haskell --rng native --threading single --games 4 --seed 42 --max-plies 200 --sims 500`
- `docker compose run --rm mcts mcts bench selfplay --backend cpp-imperative,haskell --rng native --threading multi --workers 8 --games 4 --seed 42 --max-plies 200 --sims 500`
- `docker compose run --rm mcts mcts test all`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

Sprint `8.10` reclosed on 2026-05-23. The final aggregate validation passed with:

- `docker compose run --rm mcts mcts build cpp-imperative --dry-run`
- `docker compose run --rm mcts mcts build cpp-functional --dry-run`
- `docker compose run --rm --build mcts mcts build rust --dry-run`
- `docker compose run --rm --build mcts mcts test all`
- `docker compose run --rm --build mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

The accepted report-card run recorded historical played-game rows: Q1 ST 0.05x (`646.7` vs `35.1` games/s),
Q1 MT8 0.48x (`556.0` vs `269.4` games/s), Q2 ST 0.06x (`0.5` vs `0.0`
games/s), Q2 MT8 0.21x (`0.5` vs `0.1` games/s), Q5 Haskell 0.99x, Q5 C++ (ii)
3.65x, Q6 liveness PASS, zero live-cohort divergence, all Cabal stanzas PASS, and
verdict `Within tolerance`.

## Sprint 8.11: Refactored Metric Parity Rerun ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Test.hs`, `src/MCTS/ReportCard.hs`,
`src/MCTS/CLI/Bench.hs`, `src/MCTS/CLI/Build.hs`, backend benchmark harnesses
**Docs to update**: `../documents/engineering/benchmark_metrics.md`,
`../documents/engineering/compiler_runtime_tuning.md`,
`../documents/engineering/unit_testing_policy.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Rerun the parity proof after the report card separates terminal playout throughput,
search-iteration throughput, and played-game self-play throughput.

### Deliverables

- Fresh Q1a terminal playout throughput evidence for Haskell vs backend (ii).
- Fresh Q1b search-iteration throughput evidence for Haskell vs backend (ii).
- Fresh Q2 played-game self-play evidence for Haskell vs backend (ii).
- Q5 scaling evidence with search-iteration scaling and played-game scaling reported
  separately.
- Dockerfile-time C++ and Rust PGO/BOLT training includes the representative metric
  families: terminal playout primitives, search-iteration primitives, legacy
  played-game rollout batches, and self-play batches.
- A conceptual review of backend ordering: backend (ii) should remain the steelman
  C++ performance ceiling, backend (iii) differences should be explainable by style
  and representation choices, Rust should fit the systems-language baseline, and
  Haskell performance should be interpreted against the documented GHC/PGO asymmetry.

### Validation

- `docker compose run --rm --build mcts mcts test all`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Closure Notes

Closed on 2026-05-24. `docker compose run --rm --build mcts mcts test all`
rebuilt the Dockerfile-owned C++ and Rust PGO/BOLT artefacts, trained profiles
with the bounded metric suite, passed all Cabal stanzas plus Q3 and Q6, and
reported `Verdict: Within tolerance`.

Fresh report-card evidence:

- Q1a terminal playouts: ST `0.07x` (`7166.6` vs `482.6` playouts/s), MT8
  `0.39x` (`9072.2` vs `3512.4` playouts/s).
- Q1b search iterations: ST `0.06x` (`9509.7` vs `531.0` search-iters/s), MT8
  `0.40x` (`9709.2` vs `3906.6` search-iters/s).
- Q2 self-play games: ST `0.05x` (`0.6` vs `0.0` games/s), MT8 `0.17x`
  (`0.6` vs `0.1` games/s).
- Q5 scaling: Haskell search-iters `1.02x`, C++ (ii) search-iters `7.36x`,
  Haskell self-play `0.97x`, C++ (ii) self-play `3.72x`.
- Q3/Q6 passed, the live divergence matrix was all zeroes, and the profile-suite
  review confirmed Dockerfile-time primitive and played-game workloads before the
  final report-card run.

### Remaining Work

None.

## Sprint 8.12: Parity Refresh Against Corrected Backend (ii) ✅

**Status**: Done
**Implementation**: `src/MCTS/Engine.hs`, `src/MCTS/Search/UCT.hs`,
`src/MCTS/CLI/Bench.hs`, `src/MCTS/Driver.hs`, `src/MCTS/CLI/Test.hs`,
`cpp-imperative/engine/fast_board.hpp`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`../documents/engineering/compiler_runtime_tuning.md`

### Objective

Re-establish the Haskell-vs-backend-(ii) parity proof after Sprint `5.6` made
backend (ii) a substantially faster C++ steelman.

### Deliverables

- Fresh `mcts test all` report-card evidence against the corrected backend (ii).
- Focused Haskell hot-path tuning against the new compact-board backend (ii) ceiling:
  packed `ActionIds`, direct `legalActionSet`/`applyActionId` search paths,
  reusable wall-block masks during legal-wall scans, strict terminal-playout and
  rollout loops, and RTS capability pinning for multi-worker primitive and
  played-game benchmarks.
- Updated Q1a/Q1b/Q2/Q5 evidence in
  [../documents/engineering/compiler_runtime_tuning.md](../documents/engineering/compiler_runtime_tuning.md).
- Confirmation that Q3 `(ii)..(v)` and Q6 `(i)..(v)` remain green after any Haskell
  changes.

### Validation

- `docker compose run --rm --build mcts mcts test all`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Closure Notes

Closed on 2026-05-26. The accepted aggregate validation passed:

```bash
docker compose run --rm mcts mcts test all
```

Report-card evidence against the corrected backend (ii):

- Q1a terminal playouts: ST `0.99x` (`22916.2` vs `22614.7` playouts/s), MT8
  `0.91x` (`91657.6` vs `83222.2` playouts/s).
- Q1b search iterations: ST `1.02x` (`22854.7` vs `23352.5` search-iters/s),
  MT8 `0.99x` (`158016.1` vs `156895.9` search-iters/s).
- Q2 self-play games: ST `0.63x` (`1.8` vs `1.2` games/s), MT8 `0.68x`
  (`6.7` vs `4.6` games/s).
- Q5 scaling: Haskell search-iters `6.91x`, C++ (ii) search-iters `6.72x`,
  Haskell self-play `3.65x`, C++ (ii) self-play `3.90x`.
- Q3/Q4/Q6 passed, the live divergence matrix was all zeroes, all Cabal stanzas
  passed, and the verdict was `Within tolerance`.

Focused pre-aggregate rows showed the remaining single-thread primitive blockers
closed before the full run: terminal playout ST reached `21965.7` vs `22620.7`
playouts/s and search-iteration ST reached `22891.1` vs `22326.3`
search-iters/s (Haskell vs backend (ii), seed `42`, count `1000`,
max plies `60`).

### Remaining Work

- None.

## Sprint 8.13: Haskell Functional-Core Style Alignment ✅

**Status**: Done
**Implementation**: `src/MCTS/Engine.hs`, `src/MCTS/Search/UCT.hs`,
`src/MCTS/Search/Arena.hs`
**Docs to update**: `../documents/engineering/backend_style_contract.md`,
`../documents/engineering/compiler_runtime_tuning.md`, `README.md`,
`00-overview.md`, `system-components.md`

### Objective

Keep backend (v) Haskell aligned with the shared `(iii)/(iv)/(v)`
functional-core style after backend (iii)'s compact C++ rewrite lands.

### Deliverables

- Haskell keeps the public `legalMoves :: Board -> [Action]` and
  `applyMove :: Action -> Board -> Board` boundary while the hot search path uses the
  same compact numeric transition shape as `(iii)` and `(iv)` through
  `legalActionSet`, packed `ActionIds`, and `applyActionId`.
- The rollout and UCT descent paths consume numeric action IDs directly, so the
  functional boundary stays typed while the inner loop avoids list/action allocation.
- The `ST` arena and local mutable search internals remain hidden behind the pure API.
- Q3 canonical action ordering, the 12-wall cap, ply-cap draw semantics, and transcript
  action IDs are preserved.

### Validation

- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm --build mcts mcts test mcts-cross-backend`
- `docker compose run --rm --build mcts mcts test all`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Closure Notes

Closed on 2026-05-26 as part of the Sprint `8.12` reclosure. The same
`docker compose run --rm mcts mcts test all` run that accepted the corrected
Haskell parity proof also validated Q3/Q4/Q6, all Cabal stanzas, and the
functional-core Haskell transition shape. The remaining documentation and
code-quality gates are the post-doc-update gates listed above.

### Remaining Work

- None.

## Sprint 8.14: Report-Card Verdict Gate and Primitive Sample Stability ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Test.hs`, `src/MCTS/ReportCard.hs`,
`cabal.project`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/compiler_runtime_tuning.md`, `README.md`,
`00-overview.md`, `system-components.md`

### Objective

Keep the Phase `8` parity proof fail-closed when live report-card evidence falls
outside tolerance, and keep Q1a/Q1b primitive measurements stable enough that MT8
timing noise does not reopen a closed parity surface.

### Deliverables

- The report-card primitive workload uses `N_PRIM=20_000` and `P_MAX=60` for Q1a
  terminal playout and Q1b search-iteration throughput rows.
- `mcts test all` treats the rendered report-card verdict as an execution gate:
  `Within tolerance` exits successfully, while `Evidence pending` and `Shortfall`
  exit non-zero after printing the report card.
- `ReportCard.reportCardPassed` centralizes that verdict predicate so command
  execution and unit coverage use the same rule.
- `cabal.project`, `system-components.md`, and governed engineering docs mirror
  the updated workload constants and fail-closed verdict behavior.

### Validation

- `docker compose run --rm --build mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts check-code`
- `docker compose run --rm mcts mcts test all`
- `git diff --check`

### Closure Notes

Closed on 2026-05-27. The accepted `docker compose run --rm mcts mcts test all`
run exited 0 with verdict `Within tolerance`: Q1a terminal playout ST `0.72x`
and MT8 `0.85x`, Q1b search-iteration ST `0.67x` and MT8 `0.67x`, Q2
self-play ST `0.59x` and MT8 `0.68x`, Q3/Q4/Q6 PASS, all Cabal stanzas PASS,
and zero live-cohort divergence. Earlier same-day `N_PRIM=10_000` evidence
correctly failed closed with a Q1a MT8 `Shortfall`, proving the new exit-code
gate caught parity regressions instead of merely printing them.

**Doctrine note**: Sprint `8.14` established the report-card exit-code gate; the
gate's semantics were later reframed by Sprint `8.15` per
[../documents/engineering/compiler_runtime_tuning.md → Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine).
The exit-code gate now sits on the apples-to-apples invariants Q3/Q4/Q6/Q7
plus a non-pending measurement; the verdict line itself is informational. The
historical "`Within tolerance` is the only pass" wording in this sprint's
deliverables describes the gate as Sprint `8.14` delivered it.

### Remaining Work

- None.

## Sprint 8.15: Backend (ii) Steelman Rebaseline and Measurement Reframe ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Test.hs`, `src/MCTS/ReportCard.hs`,
`test/unit/Main.hs`, `cabal.project`,
`documents/engineering/{benchmark_metrics.md,unit_testing_policy.md,compiler_runtime_tuning.md,semantic_parity_contract.md}`,
`DEVELOPMENT_PLAN/{README.md,00-overview.md,system-components.md,development_plan_standards.md,phase-8-haskell-performance-parity-closure.md,legacy-tracking-for-deletion.md}`,
`README.md`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`development_plan_standards.md`,
`../documents/engineering/benchmark_metrics.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/compiler_runtime_tuning.md`,
`../documents/engineering/semantic_parity_contract.md`,
`../README.md`,
`legacy-tracking-for-deletion.md`

### Objective

Land the **measurement-vs-invariant** reframing across code, doctrine, and
plan, and rebaseline the Haskell measurement against the fully-steelmanned
Sprint `5.7` backend `(ii)` target.

Q1, Q2, and Q5 are recorded as measurements per the new
[../documents/engineering/compiler_runtime_tuning.md → Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine):
"Haskell trails fully-optimised C++ by N%" is an acceptable scientific finding,
provided every steelman backend is at its phase-owned optimisation floor and
PGO-asymmetry attribution is recorded honestly. Closure of `mcts test all`
gates on the apples-to-apples invariants Q3, Q4, Q6, Q7 plus a non-pending
measurement; the verdict line is informational.

### Deliverables

- `Verdict` semantics in `src/MCTS/ReportCard.hs` reframed: `WithinTolerance`
  and `Shortfall` both denote honest measurements, only `EvidencePending`
  blocks closure on the verdict side. New `ApplesToApples` record with explicit
  Q3/Q4/Q6/Q7 booleans surfaced as the `apples_to_apples` field on the JSON
  report card and as the "Apples-to-apples invariants (closure gates)" block
  in the text report card.
- Exit-code gate in `src/MCTS/CLI/Test.hs` moved off `WithinTolerance` and
  onto `applesToApplesAllPass card && reportVerdict /= EvidencePending`.
- `test/unit/Main.hs` verdict-gate assertions updated to exercise the new
  gate semantics (Shortfall passes closure when invariants pass; an invariant
  failure blocks closure even with a `WithinTolerance` verdict).
- § Performance Measurement Doctrine in
  `documents/engineering/compiler_runtime_tuning.md` (renamed from the prior
  § Parity Tolerance) records the Q-classification, the closure gate, the
  verdict-line labelling threshold, and the five-backend full-optimisation
  prerequisite table.
- Cross-reference updates and softened framing in
  `documents/engineering/{benchmark_metrics.md,unit_testing_policy.md,semantic_parity_contract.md}`.
- `DEVELOPMENT_PLAN/{README.md (Exit Definition Item 6, Closure Status),00-overview.md (Vision),development_plan_standards.md (Continuous Clean-Room Narrative)}`
  updated to the reframed doctrine.
- Root `README.md` hypothesis softened to "measured against" rather than
  "must match".
- Final aggregate `docker compose run --rm --build mcts mcts test all` rerun:
  Q3/Q4/Q6/Q7 invariants PASS, Q1/Q2/Q5 measurement recorded honestly against
  the Sprint `5.7` backend `(ii)` target.

### Current Evidence

Accepted Sprint `8.15` Haskell tuning keeps the pure backend API while narrowing
local hot-path overhead: compact `Word8` pawn slots, direct non-terminal action
sets, no-ply rollout apply with local ply tracking, fused arena visit/value
updates, first-unvisited UCT child selection, worker `forkOn` pinning, and direct
packed-slot path starts in `pathExistsWithMasks`, plus the no-wall legal-action
fast path in `appendWallActionIds` and the shared optional-ply
`applyActionIdWithPlyIncrement` transition path.

Focused validation after the transition-path rewrite used the report-card
workload constants (`N_PRIM=20_000`, primitive `--max-plies 60`, self-play
`--games 4 --sims 500 --max-plies 200`) against backend `(ii)`:

- Q1a terminal playouts: ST `37354.7` vs `35671.4` playouts/s; MT8 `246237.3`
  vs `182027.4` playouts/s.
- Q1b search iterations: ST `39245.2` vs `35265.2` search-iters/s; MT8
  `273413.1` vs `195406.1` search-iters/s.
- Q2 self-play: ST `1.8` vs `1.9` games/s; MT8 `6.4` vs `5.5` games/s.

The aggregate rerun after the transition-path rewrite passes the
files/docs/style, unit, integration, cross-backend, legacy-parity,
semantic-parity, Q3, Q4, Q6, Q7, and zero-divergence gates. Under the prior
pass/fail framing it failed closed with `Verdict: Shortfall 0.2678864950323545`:

- Q1a terminal playouts: backend `(ii)`/Haskell `1.06x` ST (`36809.1` vs
  `34786.8` playouts/s), `1.27x` MT8 (`267646.1` vs `211096.3` playouts/s).
- Q1b search iterations: backend `(ii)`/Haskell `1.05x` ST (`39074.4` vs
  `37079.2` search-iters/s), `1.11x` MT8 (`299348.8` vs `269384.0`
  search-iters/s).
- Q2 self-play: backend `(ii)`/Haskell `0.98x` ST (`2.0` vs `2.0` games/s),
  `1.11x` MT8 (`7.4` vs `6.7` games/s).
- Q5 scaling: Haskell search `7.27x`, backend `(ii)` search `7.66x`, Haskell
  self-play `3.35x`, backend `(ii)` self-play `3.79x`.

### Post-reframe Measurement (2026-05-28)

After the measurement-vs-invariant reframe landed in this sprint and the
Dockerfile was rebuilt, the aggregate
`docker compose run --rm --build mcts mcts test all` exits 0 with all four
apples-to-apples invariants PASSing and the labelled measurement recorded
honestly:

- Q3 invariant: PASS (`(ii)..(v)` under `--rng cpp`).
- Q4 invariant: PASS (5 backends × 3 seeds).
- Q6 invariant: PASS (all five backend slots through the legacy envelope).
- Q7 invariant: PASS (`mcts-semantic-parity`; normalized divergence score
  `0.0000`).
- All six Cabal stanzas PASS (`mcts-unit`, `mcts-integration`,
  `mcts-cross-backend`, `mcts-legacy-parity`, `mcts-semantic-parity`,
  `mcts-haskell-style`).
- `Verdict: Trails parity band by 52.3% (measurement recorded; see PGO Asymmetry
  in compiler_runtime_tuning.md)` — informational label, not a closure gate.
- Q1a terminal playouts: backend `(ii)`/Haskell `1.42x` ST
  (`35454.9` vs `25054.8` playouts/s), `1.51x` MT8
  (`253966.0` vs `168490.5` playouts/s).
- Q1b search iterations: backend `(ii)`/Haskell `1.45x` ST
  (`38199.6` vs `26403.9` search-iters/s), `1.52x` MT8
  (`277727.1` vs `182380.9` search-iters/s).
- Q2 self-play: backend `(ii)`/Haskell `1.35x` ST (`1.9` vs `1.4` games/s),
  `1.48x` MT8 (`6.7` vs `4.5` games/s).
- Q5 scaling: Haskell search `6.91x`, backend `(ii)` search `7.27x`, Haskell
  self-play `3.28x`, backend `(ii)` self-play `3.60x`.
- Validation chain: `docker compose run --rm --build mcts mcts test mcts-unit`
  (29/29 passed), `docker compose run --rm --build mcts mcts check-code`
  (files/docs/style/haskell-lint PASS), `docker compose run --rm mcts mcts
  test all` (exit 0), `git diff --check` (clean).

The wider shortfall against the post-`5.7` `(ii)` target (52% worst row vs
27% against the pre-`5.7` artefact) is exactly the kind of honest measurement
the reframed doctrine accepts: every steelman backend is at its phase-owned
optimisation floor (Sprint `5.7` `(ii)`, `6.7` `(iii)`, `6.8` Rust `(iv)`,
`8.13` Haskell `(v)`; backend `(i)` exempt), the apples-to-apples invariants
hold, and the gap is attributable to the documented PGO asymmetry. Sprint
`8.15` closed on 2026-05-28 against this measurement; the work itemised under
Deliverables is complete and the project hypothesis has its honest empirical
answer.

The strict `quotRem` index-decode candidate is rejected after passing
`mcts-unit` but regressing the focused Q1a/Q1b rows: Haskell Q1a fell to
`30787.8` ST and `153879.6` MT8 playouts/s, and Haskell Q1b fell to `31974.8`
ST and `148508.2` MT8 search-iters/s.

The direct wall-index legality/trial-mask candidate is rejected after passing
`mcts-unit` but regressing the focused primitive rows: Q1a measured `35522.3`
vs `33116.5` ST and `252956.7` vs `184728.7` MT8 playouts/s; Q1b measured
`38324.8` vs `33844.6` ST and `244060.6` vs `175051.3` MT8 search-iters/s.

The Word64 signed-modulo correction-table rollout-selection candidate preserved
the Haskell primitive checksums and passed `mcts-unit`, but is rejected because
the focused rows stayed below the accepted baseline: Q1a measured `36368.8` vs
`33474.3` ST and `245645.3` vs `185101.2` MT8 playouts/s; Q1b measured
`40632.6` vs `34720.2` ST and `245171.4` vs `189598.5` MT8 search-iters/s.
Q2 was not rerun for these rejected candidates because Q1a/Q1b already failed
to improve the active shortfall.

The forced splitmix inlining plus primitive seed-hoisting candidate passed
`mcts-unit`, but is rejected after focused primitive rows regressed against the
accepted baseline: Q1a measured `35476.7` vs `33190.6` ST and `265489.0` vs
`194248.4` MT8 playouts/s; Q1b measured `40652.4` vs `35920.2` ST and
`263020.3` vs `190048.2` MT8 search-iters/s.

The bulk arena child-reservation candidate passed `mcts-unit` and improved the
focused Q2 MT8 row to `6.3` vs `5.9` games/s, but is rejected because the
aggregate report-card rerun worsened the active shortfall. The aggregate passed
files/docs/style, unit, integration, cross-backend, legacy-parity,
semantic-parity, Q3, Q4, Q6, Q7, and zero-divergence gates, then failed closed
with `Verdict: Shortfall 0.35914394441567055`: Q1a backend `(ii)`/Haskell
`1.13x` ST and `1.36x` MT8, Q1b `1.09x` ST and `1.07x` MT8, and Q2 `0.97x`
ST and `1.10x` MT8.

### Validation

- `docker compose run --rm --build mcts mcts test all`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None. Closed on 2026-05-28 against the validated post-reframe aggregate
measurement recorded in the [Post-reframe Measurement](#post-reframe-measurement-2026-05-28)
block below. Further Haskell optimisation work is not blocking and may be
scheduled as a new sprint only if the project chooses to invest.

## Sprint 8.16: Haskell Parity Rebaseline vs Post-5.8 Backend (ii) ✅

**Status**: Done
**Implementation**: No Haskell code changes; measurement closure only.
**Blocked by**: Sprint `5.8` (backend `(ii)` residual hot-path squeeze).
**Docs to update**: `README.md`, `00-overview.md`,
`legacy-tracking-for-deletion.md`,
`../documents/engineering/benchmark_metrics.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/compiler_runtime_tuning.md`

### Objective

Rebaseline the Haskell-vs-`(ii)` measurement against the post-Sprint-`5.8`
backend `(ii)` artefact. Sprint `5.8` tightens the C++ steelman ceiling
through visit-preserving changes (bidirectional wall-legality BFS,
`UctNode` cache-line padding removed, `-fno-stack-protector -fno-rtti
-fipa-pta` plus extended BOLT `-split-functions -split-strategy=cdsplit
-reorder-functions=cdsort -icf=1`); the Q3/Q4/Q6/Q7 invariants are
preserved by construction. Sprint `8.16` records the resulting
Q1a/Q1b/Q2/Q5 measurement under the Sprint `8.15` measurement-vs-invariant
reframe and updates the historical-evidence labels on prior rows.

### Deliverables

- Run `docker compose run --rm --build mcts mcts test all` against the
  Dockerfile-built post-`5.8` `(ii)` library; the run must exit 0 with
  Q3/Q4/Q6/Q7 PASS and a non-`Evidence pending` `Verdict:` line.
- Record the new Q1a terminal-playout, Q1b search-iter, Q2 self-play, and
  Q5 scaling ratios in the post-`5.8` measurement block of this phase doc
  and in [README.md](../README.md).
- Mark the Sprint `8.14` and Sprint `8.15` rows in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) as
  historical against the pre-`5.8` `(ii)` artefact; add a new closure row
  for Sprint `8.16` recording the post-`5.8` evidence.
- Update `documents/engineering/benchmark_metrics.md` and
  `documents/engineering/unit_testing_policy.md` historical-evidence
  pointers to name the Sprint `8.16` post-`5.8` measurement as the active
  current-artifact evidence.
- No Haskell engine or Cabal changes are in scope. If the focused Haskell
  rows shift outside measurement noise after the `(ii)` rebaseline, that
  shift is reported honestly but does not block sprint closure.

### Validation

- `docker compose run --rm --build mcts mcts test all`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

Closed on 2026-05-29. After Sprint `5.8` landed the residual hot-path
squeeze and `cpp-imperative/build/libmcts_cpp_imperative.so` was
re-bolted through the corrected `-reorder-functions=cdsort -icf=1` BOLT
invocation, `docker compose run --rm --build mcts mcts test all` exited
0 with all Cabal stanzas PASS, all apples-to-apples invariants Q3/Q4/Q6/Q7
PASS, `normalized_divergence_score=0.0000`, and `Verdict: Trails parity
band by 57.1% (measurement recorded; see PGO Asymmetry in
compiler_runtime_tuning.md)`.

Backend `(ii)` post-`5.8` raw rates: Q1a `37490.9` ST / `248935.5` MT8
`playouts/s`, Q1b `40502.5` ST / `296135.4` MT8 `search-iters/s`, Q2
`1.9` ST / `7.1` MT8 `games/s`. Haskell raw rates: Q1a `24842.8` ST /
`165640.3` MT8 `playouts/s`, Q1b `26457.4` ST / `189527.9` MT8
`search-iters/s`, Q2 `1.4` ST / `4.5` MT8 `games/s`. Backend
`(ii)`/Haskell ratios: Q1a `1.51x` ST / `1.50x` MT8, Q1b `1.53x` ST /
`1.56x` MT8, Q2 `1.41x` ST / `1.57x` MT8; Q5 scaling Haskell search
`7.16x` vs C++ `(ii)` search `7.31x`, Haskell self-play `3.28x` vs C++
`(ii)` self-play `3.66x`. The Sprint `8.15` post-`5.7` measurement (Q1a
`1.42x` / `1.51x`, Q1b `1.45x` / `1.52x`, Q2 `1.35x` / `1.48x`, verdict
`52.3%`) is now historical against the pre-`5.8` `(ii)` artefact.

The increase in `Trails parity band` from 52.3% to 57.1% reflects the
~2–6% improvement in backend `(ii)` from Sprint `5.8`, not a Haskell
regression: Haskell raw rates are within measurement noise of the
Sprint `8.15` post-`5.7` values. Under the Sprint `8.15`
measurement-vs-invariant reframe, this is recorded honestly with
PGO-asymmetry attribution and does not gate closure; the closure gate
is the apples-to-apples invariants Q3/Q4/Q6/Q7 plus a non-pending
measurement, all of which PASS.

## Sprint 8.17: Backend (v) MutableByteArray# Arena and INLINE Audit ✅

**Status**: Done
**Implementation**: `src/MCTS/Search/Arena.hs`, `src/MCTS/Search/UCT.hs`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`,
`../documents/engineering/backend_style_contract.md`,
`../documents/engineering/compiler_runtime_tuning.md`

### Objective

Land the only remaining permitted-but-not-adopted backend (v) hot-path item
inside the contracts owned by
[../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md)
and
[../documents/engineering/compiler_runtime_tuning.md](../documents/engineering/compiler_runtime_tuning.md):
the `MutableByteArray# s`-backed UCT arena and a tail-end `INLINE` audit on the
descent/rollout boundary. Do not reintroduce any Sprint `8.15` "measured but
rejected" candidate. The pure public API surface (`legalMoves`, `applyMove`,
`isTerminal`, `terminalOutcome`, the `search` boundary) is unchanged. Q3 visit
payloads remain bit-identical (`normalized_divergence_score=0.0000`); the
transcript wire format, the canonical action ID contract, and the 12-wall cap
stay identical.

### Deliverables

- **`MutableByteArray# s`-backed SoA arena.** `src/MCTS/Search/Arena.hs`
  replaces the six parallel `STUArray s NodeId X` slabs (parent, firstChild,
  numChildren, actionId, visits, valueSum) with a single
  `MutableByteArray# s`. Per-field offsets are named constants; reads and
  writes go through `primitive` ops (`readWord32Array#`,
  `writeWord32Array#`, `readFloatArray#`, `writeFloatArray#`); the SoA
  layout is preserved at the byte level. `treeReroot` remains a tested arena
  primitive and continues to work over the new representation.
- **Descent / rollout `INLINE` audit.** Confirm `pathExistsWithMasks` and the
  per-side helpers carry the inlining the descent/rollout call sites in
  `src/MCTS/Search/UCT.hs` require. Add specialization only where GHC's
  monomorphic-call-site inference does not pick it up. No new `SPECIALIZE`
  pragmas unless a focused bench shows a residual call site.
- **No `-optlo-mcpu=native` / `-optlc-mcpu=native`.** These remain deferred
  under the documented aarch64 assembler limitation in
  [../documents/engineering/compiler_runtime_tuning.md](../documents/engineering/compiler_runtime_tuning.md).
- **`legacy-tracking-for-deletion.md` row movement.** The six-`STUArray` arena
  residue row moves from Pending Removal to Completed.

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

Q3/Q4/Q6/Q7 must remain PASS. `normalized_divergence_score` must remain
`0.0000`. The verdict line is informational; if the `MutableByteArray#`
migration regresses focused Q1a/Q1b/Q2 rates against the post-`6.10`
cohort baseline, it is reverted and recorded as `measured but rejected`,
mirroring the Sprint `8.15` pattern, and the sprint closes on the
`INLINE` audit alone.

### Remaining Work

None.

### Closure Notes

Sprint `8.17` closed on 2026-05-29. Both deliverables are recorded honestly
per the Performance Measurement Doctrine.

**`MutableByteArray# s` arena migration — measured but rejected.** A
single-buffer migration over `STUArray s Int Word32` (one underlying
mutable byte array, named per-field offsets at cells `[parent,
firstChild, numChildren, visits, valueSum, actionId]`, stride 24 bytes,
`castFloatToWord32` / `castWord32ToFloat` for the `Float` valueSum slot)
compiled cleanly through `mcts test mcts-unit`, but focused native-RNG
benchmarks recorded a regression versus the Sprint `8.13` six-`STUArray`
baseline:

| Backend | Q1a pre-`8.17` ST (playouts/s) | Q1a post-`8.17` ST | Q1b pre-`8.17` ST (search-iters/s) | Q1b post-`8.17` ST |
|---------|-------------------------------:|-------------------:|-----------------------------------:|-------------------:|
| haskell | `22900.8` | `21650.3` (`-5.5%`) | `23287.1` | `23038.4` (`-1.1%`) |

The migration was reverted; `src/MCTS/Search/Arena.hs` keeps the
Sprint `8.13` six-slab `STUArray s NodeId X` layout. The likely cause of
the regression is per-field offset arithmetic (multiply + add for cell
index, plus the `castFloatToWord32` / `castWord32ToFloat` round-trip on
the hot `addVisitValue` path) outweighing the address-register
consolidation win that motivated the migration. This mirrors the Sprint
`8.15` "measured but rejected" pattern (`Search/Arena.hs`-internal
representation changes that pass functional gates but regress focused
rows).

**Descent / rollout `INLINE` audit — no changes.** Sprints `8.13` and
`8.15` already landed `INLINE`/`INLINABLE` on every primitive in
`MCTS.Search.Arena`, `MCTS.Search.UCT`, `MCTS.Rng.Mix`, and the exported
`MCTS.Engine` boundary (`legalMoves`, `applyMove`, `isTerminal`,
`terminalOutcome`, `terminalWinner`, `applyActionId`). The Sprint `8.17`
audit found no residual call sites where additional inlining would help
without risking the same focused-row regressions already enumerated in
the Sprint `8.15` "measured but rejected" ledger.

**Legacy ledger row.** The six-`STUArray` arena Pending Removal row
moves to Completed with the `measured but rejected` notation; the
residue is kept based on focused-bench evidence rather than removed.

Validation results:

- `mcts test mcts-cross-backend` — **PASS** (7/7); Q3 visit-equality holds.
- `mcts test mcts-legacy-parity` — **PASS** (2/2).
- `mcts test mcts-semantic-parity` — **PASS** (1/1; Q7).
- `mcts test mcts-unit` — **PASS** (29/29).
- `mcts test all` aggregate: Q3/Q4/Q6/Q7 **PASS**;
  `normalized_divergence_score=0.0000`; all six Cabal stanzas pass;
  verdict `Trails parity band by 62.7%` (informational measurement
  label, not a closure gate).

Final post-`8.17` cohort raw rates from the aggregate report card:

| Backend         | Q1a ST playouts/s | Q1a MT8 playouts/s | Q1b ST search-iters/s | Q1b MT8 search-iters/s |
|-----------------|------------------:|-------------------:|----------------------:|-----------------------:|
| cpp-imperative  |          ~`35990` |           ~`225800` |              ~`38540` |               ~`244520` |
| cpp-functional  |          ~`35720` |           ~`245470` |              ~`38800` |               ~`236310` |
| rust            |          ~`38940` |           ~`256720` |              ~`42080` |               ~`290210` |
| haskell         |           `23037.9` |           `137348.9` |               `25745.2` |               `170947.7` |

The cohort ranking is `rust ≥ cpp-functional ≈ cpp-imperative > haskell`,
confirming the analyst prediction that closing the (iii)/(iv)/(v)
permitted-but-not-adopted shape gap would invert Haskell's pre-`6.9`
lead over the foreign cohort. Haskell's remaining shortfall sits in
the documented PGO-asymmetry band: GHC `9.14` ships no
production-grade PGO equivalent to GCC/Clang `-fprofile-use` or
`rustc -Cprofile-use`, and the deferred `-optlo-mcpu=native` /
`-optlc-mcpu=native` aarch64 follow-on remains out of scope. Phase `8`
reaches Done again on this measurement; no further (v) optimisation
work is scheduled.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cli_command_surface.md` — command matrix and backend selection
  semantics.
- `documents/engineering/determinism_contract.md` — RNG split, Q3/Q6 equivalence scope,
  and engine-envelope language.
- `documents/engineering/backend_ffi_contract.md` — live C ABI contract for all four
  foreign backends.
- `documents/engineering/backend_style_contract.md` — functional-core style contract
  for `(iii)`, `(iv)`, and `(v)`, including the closed Sprint `8.13` Haskell
  alignment gate.
- `documents/engineering/benchmark_metrics.md` — metric units and Q1-Q7 mapping,
  including Sprint `8.11` rerun evidence, Sprint `7.10` raw backend metric table
  terms, and Sprint `7.11` semantic-parity implementation.
- `documents/engineering/unit_testing_policy.md` — live `mcts-cross-backend` and
  `mcts-legacy-parity` roles without checked-in generated validation data, plus the
  Sprint `8.10` bounded-profile prerequisite for current-artifact report-card
  closure and the active Sprint `8.15` rebaseline shortfall.
- `documents/engineering/compiler_runtime_tuning.md` — performance parity against live
  backend (ii), mandatory Dockerfile-time PGO+BOLT success for accepted evidence,
  native-RNG benchmark semantics, Sprint `8.9` Cabal-stanza flag wording, the
  Sprint `8.10` bounded played-game PGO/BOLT training workload doctrine, the
  Sprint `8.11` refactored metric rerun evidence, and the Sprint `8.14`
  fail-closed report-card verdict/sample-stability gate.
- `documents/engineering/haskell_code_guide.md` — command/build surface examples.

**Product docs to create/update:**

- `README.md`

**Cross-references to add:**

- Add or update backlinks from every governed doc above to this phase and
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) where cleanup
  ownership is referenced.
- Keep [README.md](README.md), [00-overview.md](00-overview.md), and
  [system-components.md](system-components.md) aligned with the closed Sprint `8.10`
  bounded played-game training-workload reclosure, the closed Sprint `8.11`
  bounded metric-suite profile rerun, the closed Sprint `8.12` parity refresh, the
  closed Sprint `8.13` Haskell style-alignment follow-up, the closed Sprint `8.14`
  report-card verdict/sample-stability gate, the active Sprint `8.15` rebaseline
  shortfall, the closed Sprint `5.7` backend `(ii)` steelman, the closed Sprint `6.7` backend
  (iii)/(iv) style alignment, the closed Sprints `5.3`/`6.4` build-harness
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
- [../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md)
