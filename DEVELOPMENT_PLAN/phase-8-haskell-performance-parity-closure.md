# Phase 8: Haskell Performance Parity Closure

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Close the project hypothesis. Tune the Haskell engine until backend
> (v) matches backend (ii) on Q1 and Q2 within the parity tolerance defined in
> [../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md)
> (`HASKELL_PARITY_TOLERANCE = 0.05`), record the
> one-known-asymmetry PGO note, and execute the retirement protocol
> (i)→(ii)→(iii)→(v) with historical retirement evidence and no generated
> validation data required in git.

## Phase Status

✅ **Done**. The performance-parity proof, backend retirement protocol, and
no-generated-validation-data cleanup are closed for the 2026-05-19 alignment
work. Sprint `8.6`
recorded the backend (v)-vs-backend (iii) parity anchor and retired backend
(iii); Sprint `8.7` closes the plan suite and cleanup ledger after the
alignment pass. Sprint `8.8` closes the no-generated-validation-data doctrine
cleanup. The LLVM-driven GHC
tuning flag set, RTS pin, and hot-path `INLINABLE` pragmas ship under GHC
`9.14.1` with LLVM `19`; Sprint `8.2` ran the three profile-driven tuning
rounds recorded below. The canonical 2026-05-19
`docker compose run --rm mcts mcts test all` gate records Q1 ST **0.05×**,
Q1 MT8 **0.41×**, Q2 ST **0.05×**, Q2 MT8 **0.20×**, Q5 Haskell **0.99×**,
Q5 cpp-imperative **3.64×**, Q7 historical backend (i) evidence **PASS**, and
`Verdict: Within tolerance`. Normal validation no longer depends on checked-in
generated validation data.

## Remaining Work

- None.

## Phase Summary

Phase `8` is the project's exit condition. Phases `3` and `7` establish the
correctness baseline; this phase tunes for speed until pure Haskell (v) matches
maximally-optimised C++ (ii) on both POC workloads. The tuning levers are the
doctrine-named GHC flags, RTS `-A64m -n4m -qg1 -qb -T`, `INLINABLE` and
`SPECIALIZE` where polymorphism exists, unboxed strict fields everywhere, no
`Maybe` / `Either` in the rollout inner loop, the per-rollout scratch arena, and the
hand-rolled `MutableByteArray#` migration if the current `STUArray` indexing layer
profiles hot. The LLVM `-mcpu=native` flags remain ledger-deferred on aarch64 because
the pinned assembler rejects the emitted LSE instructions.
The one-known-asymmetry PGO note is recorded honestly: GHC 9.14 has no production-
grade PGO comparable to GCC/Clang `-fprofile-use` or `rustc -Cprofile-use`, so a
5–15% Haskell-shortfall is *attributable* to that asymmetry rather than papered over
— but per
[../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md)
the pass/fail threshold is `HASKELL_PARITY_TOLERANCE = 0.05`, so any shortfall in
the 5–15% band still renders `Shortfall <ratio>` (with the PGO note attached as
attribution, not as exemption).
The 2026-05-19 canonical report card reaches parity: the verdict is
`Within tolerance`. Backend (i) is retired from live CLI/build/verify/FFI
dispatch and preserved by historical retirement evidence plus optional external
artifacts that are not normal clean-clone test inputs. The Sprint `8.5`
backend (iii)-vs-backend (ii) anchor passed on 2026-05-19, so backend (ii)'s
live CLI/build/verify/FFI surface has been removed and its historical evidence is
recorded in the plan/docs. The Sprint `8.6`
backend (v)-vs-backend (iii) anchor passed on 2026-05-19, so backend (iii)'s
live CLI/build/verify/FFI surface has been removed and its historical evidence is
recorded in the plan/docs. Backend (iv) Rust stays live as the cross-language
second opinion. The surviving live cohort is `(rust, haskell)`. Sprint `8.8`
removed the remaining generated-data residue from tests and generated-path
tracking so a clean clone can validate without checked-in transcripts, schemas,
snapshots, or throughput anchors.

## Sprint 8.1: Haskell Compiler and RTS Tuning ✅

**Status**: Done (the LLVM-driven GHC flag set + RTS pin + INLINABLE
baseline ship under the pinned GHC 9.14.1; `SPECIALIZE` and the
`MutableByteArray#` migration are profile-driven decisions deferred
to Sprint 8.2 with the rationale recorded inline)
**Implementation**: `mcts.cabal` (ghc-options), `src/MCTS/Engine.hs`,
`src/MCTS/Search/Arena.hs`, `src/MCTS/Search/UCT.hs`, `src/MCTS/Rng/Mix.hs`
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Apply the doctrine-named GHC, LLVM, and RTS tuning to the Haskell engine until the
report-card numbers move toward parity with backend (ii).

### Deliverables

- `mcts.cabal` declares per-library `ghc-options` per
  [00-overview.md → Hard Constraints item 20](00-overview.md):

  ```
  -O2 -fllvm
  -funbox-strict-fields
  -fspecialise-aggressively
  -fexpose-all-unfoldings
  -flate-dmd-anal
  -fmax-simplifier-iterations=20
  -fworker-wrapper
  -fstatic-argument-transformation
  ```

  The pinned LLVM version is the same one BOLT uses, so the Dockerfile carries
  one LLVM only. `-optlo-mcpu=native` / `-optlc-mcpu=native` remain excluded on
  the current aarch64 container and tracked through the Sprint 8.2 ledger item.
- The executable `mcts.cabal` stanza declares
  `ghc-options: -with-rtsopts=-A64m -n4m -qg1 -qb -T` baked into the binary per
  [00-overview.md → Hard Constraints item 20](00-overview.md).
- `INLINABLE` pragmas on the current hot exported primitives in
  `src/MCTS/Engine.hs`, `src/MCTS/Rng/Mix.hs`, and `src/MCTS/Search/`.
- `SPECIALIZE` pragmas on the search loop for the concrete game type so the
  inner loop sees no class dictionaries.
- Strict fields everywhere (`{-# UNPACK #-} !Int` etc.) — Sprint 3.1 set this up
  for `Board`; Sprint 8.1 audits the search-loop locals (`!let` bindings inside
  `ST` blocks).
- No `Maybe` or `Either` in the rollout inner loop — replace with sentinel
  values or unboxed sum representations per
  [00-overview.md → Hard Constraints item 20](00-overview.md).
- If profiling shows `STUArray` indexing is suboptimal, migrate to a
  hand-rolled `MutableByteArray#` arena. This is profiling-driven; the sprint
  closure does not require the migration if profiling does not justify it, but
  it does require that the profiling pass has been run and the decision is
  recorded in `documents/engineering/compiler_runtime_tuning.md`.

### Validation

1. `docker compose run --rm mcts mcts check-code` succeeds with the new flag set; no
   warnings.
2. `docker compose run --rm mcts mcts lint haskell` passes (the tuning flags do not
   break the lint stack).
3. `docker compose run --rm mcts mcts bench rollouts --backend haskell --threading
   single --rng native --games 100000 --seed 42` shows a measurable improvement over the Phase 3
   baseline (the exact ratio is recorded in
   `documents/engineering/compiler_runtime_tuning.md`).
4. Same-backend determinism still holds: the tuning is correctness-preserving.

### Closure Notes

- `mcts.cabal` library and executable stanzas now ship the full
  LLVM-driven doctrine flag set: `-O2 -funbox-strict-fields
  -fspecialise-aggressively -fexpose-all-unfoldings -flate-dmd-anal
  -fmax-simplifier-iterations=20 -fworker-wrapper
  -fstatic-argument-transformation -fllvm`. The executable adds
  `-threaded "-with-rtsopts=-A64m -n4m -qg1 -qb -T"` per
  [00-overview.md → Hard Constraints item 20](00-overview.md). GHC's
  LLVM backend is wired to the container's `llc-19` / `opt-19` (the
  same LLVM 19 BOLT uses), so the Dockerfile carries one LLVM only.
- `-optlo-mcpu=native` / `-optlc-mcpu=native` are intentionally
  *not* in the flag set: enabling them on aarch64 inside the
  container emits LSE (Large System Extensions) instructions that
  the assembler refuses (`instruction requires: lse`). The default
  `-fllvm` codegen already targets the project's pinned CPU profile
  through the GHC native code generator path; if a future profiling
  pass justifies the per-CPU flag, the assembler invocation needs a
  matching `-mcpu` extension. Tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
  as a deferred Sprint 8.2 item.
- `SPECIALIZE` pragmas on the search loop are not needed for the
  current implementation: the search kernel (`uctSearch`,
  `uctSearchWithEquity`, `descend`, `rollout`, `pickByUctIndex`) is
  already monomorphic over the concrete `Board` and `Word64` types,
  so there are no type-class dictionaries to specialise away. The
  `INLINABLE` baseline already exposes the unfoldings across module
  boundaries. If a future refactor introduces a polymorphic game
  type, the `SPECIALIZE` pragmas land alongside that change.
- `MutableByteArray#` migration is profile-driven. The current arena
  uses `STUArray` (which is itself backed by `MutableByteArray#`
  under the hood). A direct hand-rolled `MutableByteArray#` arena
  would skip the `STUArray` indexing layer but requires actual
  bench-driven evidence that the indexing layer is the bottleneck.
  Sprint 8.2's `criterion` micro-benchmarks are the right surface
  for that measurement; the decision is enqueued there rather than
  forced through here.
- The rollout inner loop uses the strict `MCTS.Engine.terminalOutcome`
  sentinel primitive (`1.0` hero win, `-1.0` villain win, `0.0` draw,
  `nonTerminalOutcome = 2.0`) instead of `Maybe Winner` per the
  doctrine's "no `Maybe`/`Either` in the rollout inner loop" rule.
  `docker compose run --rm mcts mcts test mcts-unit` validates the sentinel path.

### Validation State

`docker compose run --rm mcts mcts check-code` and
`docker compose run --rm mcts mcts test all` are green under the pinned
toolchain with the LLVM flag set active. The Haskell-style stanza
(pinned Fourmolu / HLint binaries) passes after the flag change.

## Sprint 8.2: Profile-Driven Hot-Path Tuning ✅

**Status**: Done
**Implementation**: `src/MCTS/Engine/`, `src/MCTS/Search/`,
`bench/criterion-suites.hs`, `mcts.cabal` (`mcts-criterion` benchmark stanza)
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`

### Objective

Iterate on the Haskell hot-path profile until the bottleneck moves out of the search
loop or `mcts bench` numbers reach backend (ii) parity within the parity tolerance
defined in
[../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md).

### Deliverables

- `bench/criterion-suites.hs` declares `criterion` micro-benchmarks targeting
  the search loop, the rollout loop, the legal-move generator, and the UCT
  child-selection routine. The benchmarks measure per-call cost in nanoseconds.
- Profile-driven changes: each iteration applies one targeted change (e.g.
  inline a non-strict argument, hoist a constant, unbox a sum, switch a
  `Vector` to `PrimArray`), runs `mcts bench` plus the criterion suite, and
  records the result.
- Each round records its observation in
  `documents/engineering/compiler_runtime_tuning.md` under a Haskell
  hot-path-tuning subsection, with the before / after numbers, the change made,
  and the GHC Core change observed.
- The sprint closes when the profile no longer surfaces a Haskell-specific
  hotspot that the tuning levers can reach, or when `mcts bench` reports
  Haskell within the parity tolerance of backend (ii) on Q1 and Q2 per
  [../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md),
  whichever comes first.

### Validation

1. `mcts test all` emits a report card showing the Haskell parity ratio per
   Q1 and Q2.
2. The criterion suite emits a per-call cost table for the four targeted
   primitives.
3. `documents/engineering/compiler_runtime_tuning.md` records the round-by-round
   observation log.

### Closure Notes (criterion suite landing + round 1)

- `mcts.cabal` declares a `benchmark mcts-criterion` stanza
  (`type: exitcode-stdio-1.0`) wired to `bench/criterion-suites.hs`
  with the same `-fllvm` flag set as the library.
- `bench/criterion-suites.hs` declares four benchmark groups via
  `Criterion.Main.defaultMain`:
  - `legal-moves` — `MCTS.Engine.legalMoves` on the initial board and
    on a deterministically-advanced mid-game board.
  - `apply-move` — `MCTS.Engine.applyMove` on the first legal move
    from each starting point.
  - `uct-search` — `MCTS.Search.UCT.uctSearch` at `sims ∈ {8, 64}`,
    `maxPlies = 60`.
  - `splitmix-mix` — `MCTS.Rng.Mix.mix` at pinned `(seed, n)` tuples,
    measuring per-call cost in nanoseconds.
- `cabal bench mcts-criterion --benchmark-options='--time-limit 2'`
  runs the suite inside the container and emits a regression-stable
  per-call cost table that profile-driven tuning iterations can
  diff against.
- **Round 1 (2026-05-16, `src/MCTS/Engine.hs`)**: migrated
  `pathExists` / `shortestDistance` from list-based `seen` (O(n²)
  `elem` / `notElem`) to `Data.IntSet` (O(n log n)) plus
  `INLINABLE` pragmas. Measured per-call cost change:
  legal-moves 991→160 μs, apply-move 990→158 μs,
  uct-search sims=64 1817→292 ms (**~6.2× speedup** across the
  rollout-dominated hot path). `docker compose run --rm mcts mcts test all` remains
  green.
  Recorded in
  [../../documents/engineering/compiler_runtime_tuning.md →
   Sprint 8.2 — Profile-Driven Hot-Path Tuning
   Rounds](../../documents/engineering/compiler_runtime_tuning.md).
- **Round 2 (2026-05-16, reverted)**: tried a strict-pair `Word64`
  visited bitmap (low Word64 for cells 0..63, high for 64..80). The
  constructor reconstruction at each recursive `go` step matched
  the `IntSet` tree-insert path on legal-moves and *regressed* on
  uct-search (sims=64 292→411 ms). Reverted; the real win on this
  surface needs a wavefront-bitmap BFS rewrite or an `ST`-based
  mutable queue, both bigger changes enqueued for a later round.
  Recorded in the same table.
- **Round 3 (2026-05-16, `src/MCTS/Engine.hs`)**: wavefront-bitmap
  BFS over a strict-pair `Word64` (`Bits128`) frontier with
  precomputed direction-block masks; replaces the list-based
  recursive descent with bitwise shift+and+or expansion per BFS
  wave. Per-call cost change: legal-moves 160→3.1 μs,
  uct-search sims=64 292→8.9 ms (**~52× speedup on legal-moves,
  ~33× on uct-search vs round 1**; combined with round 1, total
  speedup vs the original list-based baseline is **~320× on
  legal-moves** and **~200× on uct-search**).
  `docker compose run --rm mcts mcts test all` remains green. The Q1 ST snapshot collapses from `Shortfall 9.76`
  to **0.89×** (Haskell faster than the non-PGO cpp-imperative
  smoke library). The later 2026-05-19 canonical report card against
  container-built artefacts records `Verdict: Within tolerance`.

### Remaining Work

- None. Round 3 landed the Word128-backed wavefront-bitmap BFS and collapsed
  the known legal-move hotspot. The 2026-05-19 canonical report card against
  container-built artefacts records Q1 ST **0.05×**, Q1 MT8 **0.41×**,
  Q2 ST **0.05×**, Q2 MT8 **0.20×**, and `Verdict: Within tolerance`.

## Sprint 8.3: Parity Verdict and One-Known-Asymmetry Note ✅

**Status**: Done
**Implementation**: `src/MCTS/ReportCard.hs`,
`src/MCTS/ReportCard/Render.hs`,
`documents/engineering/compiler_runtime_tuning.md`
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`,
`DEVELOPMENT_PLAN/README.md` (Closure Status),
`DEVELOPMENT_PLAN/00-overview.md` (Current Baseline)

### Objective

Record the final parity verdict on the project hypothesis. If Haskell matches (ii)
within the parity tolerance per
[../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md)
(`HASKELL_PARITY_TOLERANCE = 0.05`), the project hypothesis is proved. If Haskell
falls short — including shortfalls in the 5–15% PGO-attributable band — the verdict
is `Shortfall <ratio>`, with the one-known-asymmetry PGO note attached as
attribution rather than as exemption.

### Deliverables

- The report-card `Verdict` field carries one of, per
  [../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md):
  - `Within tolerance` (Haskell (v) within `HASKELL_PARITY_TOLERANCE = 0.05` of
    (ii) on both Q1 and Q2 in both threading modes).
  - `Shortfall <ratio>` where `ratio = max(Q1_ratio, Q2_ratio) - 1` (Haskell
    short by `ratio` on the slower of the two benchmarks).
- The summary block's `Verdict:` line per the project [README → Tidy
  summary block](../README.md) is rendered from this field.
- `documents/engineering/compiler_runtime_tuning.md` finalises the
  one-known-asymmetry PGO note per
  [the README's "One known asymmetry" subsection](../README.md):
  GHC 9.14 has no production-grade PGO comparable to GCC/Clang `-fprofile-use`
  or `rustc -Cprofile-use`. The Haskell backend competes against PGO+BOLT-
  optimised C++ and Rust without an equivalent feedback loop. A 5–15%
  Haskell-shortfall is plausibly attributable to the missing PGO loop rather
  than to any property of pure functional code per se.
- `DEVELOPMENT_PLAN/README.md` `Closure Status` and
  `DEVELOPMENT_PLAN/00-overview.md` `Current Baseline` update to reflect the
  verdict.

### Validation

1. `mcts test all` emits the final summary block with the verdict.
2. Plan-level docs reflect the verdict.
3. `documents/engineering/compiler_runtime_tuning.md` finalises the PGO note.

### Remaining Work

- None. The verdict surface remains closed: `docker compose run --rm mcts mcts
  test all` passed on 2026-05-19 and emitted `Verdict: Within tolerance`.
  `documents/engineering/compiler_runtime_tuning.md` now records that `-fllvm`
  is active in `mcts.cabal`; only `-optlo-mcpu=native` /
  `-optlc-mcpu=native` remain deferred on the documented aarch64 assembler
  limitation.

## Sprint 8.4: Backend (i) Retirement ✅

**Status**: Done
**Implementation**: `legacy-tracking-for-deletion.md`,
`src/MCTS/CLI/Build.hs` (remove `cpp-legacy` build entry),
`cpp-legacy/RETIRED.md`, optional external/ignored retirement evidence artifacts
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/determinism_contract.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

After Q6 closure (backend (i) reproducing `MCTS_legacy` byte-for-byte on benchmark
(b) under the legacy parity envelope), retire backend (i): record its final
transcript and throughput evidence outside normal clean-clone validation, remove
its live CLI/build/verify surface, and record the retirement in the cleanup
ledger.

### Deliverables

- The backend (i) final transcript and throughput evidence is recorded as a
  historical retirement fact in this plan and may be regenerated into an
  explicit external/ignored artifact root for audit. It is not a checked-in
  validation input.
- `legacy-tracking-for-deletion.md` records the completed retirement row for the
  `cpp-legacy` CLI flag value, the FFI bindings module
  `src/MCTS/FFI/CppLegacy.hs`, the driver module `src/MCTS/Driver/CppLegacy.hs`,
  the live `cpp-legacy` build/load path, and the `mcts-legacy-parity` test
  stanza.
- The `VerifyBackend` surface remains the live `(ii)..(v)` cohort. The retired
  `LegacyParityBackend` parser surface and `mcts verify legacy-parity`
  subcommand are removed from the `CommandSpec` registry; Q7 is now answered by
  recorded historical evidence.
- `cpp-legacy/RETIRED.md` documents the retirement: when, why, the optional
  external evidence location, and the parity chain `MCTS_legacy ≡ (i) ≡ (ii)..(v)`
  it preserves as a historical fact per
  [legacy-tracking-for-deletion.md → Retirement Protocol
  Reference](legacy-tracking-for-deletion.md). The `cpp-legacy/legacy-core/`
  directory remains in the repository for reference value and optional external
  evidence regeneration, but the backend is no longer a live
  operator-selectable engine.
- The CLI build harness, prerequisite registry, and FFI load surface remove the
  `cpp-legacy` live-backend path so normal validation no longer expects the `.so`
  to be present.

### Validation

1. `docker compose run --rm mcts mcts test all` runs without backend (i) and emits a report card with the
   four-backend `(ii)..(v)` cohort.
2. `docker compose run --rm mcts mcts test mcts-cross-backend` passes (Q3 still holds).
3. The Q7 question now reads recorded historical backend (i) evidence rather
   than a live backend (i) binary or checked-in generated data.
4. `mcts verify legacy-parity` no longer appears in `mcts commands --tree`
   output.

### Closure Notes

- Final pre-retirement live measurement:
  `docker compose run --rm mcts mcts bench selfplay --backend cpp-legacy
  --threading single --rng cpp --games 2 --seed 42 --sims 10000
  --max-plies 10000 --cache-dir <external-or-ignored-root>/cpp-legacy --format json`
  recorded hash
  `a2abdbed9fa0d3528a36864d754ccef80b379f3c8a972f73dc23d6d92dcdee2d`,
  `games_per_second = 0.07518589680938131`, and
  `sims_per_second = 751.8589680938131`; the evidence is recorded as historical
  plan data or in an optional external artifact, not required for normal tests.
- Live `cpp-legacy` command selection is removed from `bench`, `verify`,
  `play`, `inspect` recompute, the build harness, the prerequisite registry, the
  `mcts-legacy-parity` Cabal stanza, and the Haskell FFI/driver modules. The
  wire-format constructor remains so archived transcripts decode.
- `mcts commands --tree` no longer includes `verify legacy-parity` or
  `build cpp-legacy`.

### Remaining Work

None for the retirement. Sprint `8.4` validation passed before Sprint `8.5`
evaluation; Sprint `8.8` has removed the remaining normal-test dependency on
retired backend artifacts.

## Sprint 8.5: Backend (ii) Retirement ✅

**Status**: Done
**Implementation**: `legacy-tracking-for-deletion.md`,
`src/MCTS/CLI/Build.hs` (remove `cpp-imperative` build entry),
`cpp-imperative/RETIRED.md`, optional external/ignored retirement evidence artifacts
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/compiler_runtime_tuning.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Backend (iii) C++ functional-style has reached parity with backend (ii) C++
imperative on Q1 and Q2 within the parity tolerance defined in
[../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md),
so Sprint `8.5` retires backend (ii): record its historical evidence outside
normal validation, remove its live CLI/build/verify/FFI surface, and record the
retirement.

### Deliverables

- Backend (ii) final transcript/throughput evidence is recorded as historical
  plan data and may be regenerated into an explicit external/ignored artifact
  root; it is not required by `mcts test all`.
- `legacy-tracking-for-deletion.md` `Pending Removal` enqueues the row for the
  `cpp-imperative` CLI flag value, the FFI bindings, the driver module, and
  the build harness entry. Moves to `Completed` when the surviving cohort's
  `mcts-cross-backend` stanza runs cleanly.
- `cpp-imperative/RETIRED.md` documents the retirement.
- The CLI build harness, prerequisite registry, and FFI load surface remove the
  `cpp-imperative` live-backend path.
- The Q1 and Q2 questions are now answered against recorded historical backend
  (ii) performance evidence rather than against a live (ii) binary, preserving the
  Haskell-vs-(ii) performance target as a fixed number per the project
  [README → First milestone](../README.md).

### Validation

1. `docker compose run --rm mcts mcts test all` runs with the surviving cohort
   `(iii), (iv), (v)` plus recorded historical (ii) evidence and emits a report card.
2. `docker compose run --rm mcts mcts test mcts-cross-backend` passes.
3. The (ii) evidence shape is checked by semantic unit assertions, not a
   checked-in schema file.

### Current Validation State

- Backend (iii)-vs-backend (ii) parity anchor recorded on 2026-05-19 with
  `docker compose run --rm mcts mcts --format json test retirement-anchor
  cpp-imperative cpp-functional`: Q1 rollouts ST ratio **0.9798**, Q1 rollouts
  MT8 ratio **0.9296**, Q2 self-play ST ratio **0.8944**, Q2 self-play MT8
  ratio **0.9945**, all within `HASKELL_PARITY_TOLERANCE = 0.05`.
- The throughput evidence (`schema: mcts-retirement-anchor-v1`, `retired_in:
  Sprint 8.5`) and final transcript evidence are historical retirement data, not
  normal clean-clone test inputs.
- The live `cpp-imperative` parser/build/dispatch/FFI/verify surface has been
  removed while the `Backend` wire tag remains decodeable for archived
  transcripts.

### Remaining Work

None for the retirement. Sprint `8.5` validation passed before Sprint `8.6`
evaluation; Sprint `8.8` has removed the remaining normal-test dependency on
retired backend artifacts.

## Sprint 8.6: Backend (iii) Retirement ✅

**Status**: Done
**Implementation**: `legacy-tracking-for-deletion.md`,
`src/MCTS/CLI/Build.hs` (remove `cpp-functional` build entry),
`cpp-functional/RETIRED.md`, optional external/ignored retirement evidence artifacts
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/compiler_runtime_tuning.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Once backend (v) Haskell reaches parity with backend (iii) C++ functional-style on
Q1 and Q2 within the parity tolerance defined in
[../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md),
retire backend (iii). The surviving cohort is now
`(rust, haskell)` — Rust as the long-running cross-language second opinion and
Haskell as the target.

### Deliverables

- Backend (iii) final transcript/throughput evidence is recorded as historical
  plan data and may be regenerated into an explicit external/ignored artifact
  root; it is not required by `mcts test all`.
- `legacy-tracking-for-deletion.md` `Pending Removal` row for the
  `cpp-functional` flag value, FFI bindings, driver, and build harness entry,
  moving to `Completed` when the surviving cohort runs cleanly.
- `cpp-functional/RETIRED.md` documents the retirement.
- The CLI build harness, prerequisite registry, and FFI load surface remove the
  `cpp-functional` live-backend path.

### Validation

1. `docker compose run --rm mcts mcts test all` runs with the surviving cohort
   `(rust, haskell)` and emits a report card.
2. `docker compose run --rm mcts mcts test mcts-cross-backend` passes (Q3 holds on the two-backend cohort).

### Current Validation State

- Backend (v)-vs-backend (iii) parity anchor recorded on 2026-05-19 with
  `docker compose run --rm mcts mcts --format json test retirement-anchor
  cpp-functional haskell`: Q1 rollouts ST ratio **0.0491**, Q1 rollouts
  MT8 ratio **0.4115**, Q2 self-play ST ratio **0.0574**, Q2 self-play MT8
  ratio **0.2031**, with the retirement-anchor verdict `within_tolerance: true`.
- The throughput evidence (`schema: mcts-retirement-anchor-v1`, `retired_in:
  Sprint 8.6`) and final transcript evidence are historical retirement data, not
  normal clean-clone test inputs.
- The former live `cpp-functional` parser/build/dispatch/FFI/verify surface has been
  removed while the `Backend` wire tag remains decodeable for archived
  transcripts.

### Remaining Work

None for the retirement. Sprint `8.6` validation passed before Sprint `8.7` plan
closure; Sprint `8.8` has removed the remaining normal-test dependency on
retired backend artifacts.

## Sprint 8.7: Plan Closure ✅

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/README.md`,
`DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: every plan file.

### Objective

Mark the plan complete. Every Exit Definition item in
[README.md](README.md) is satisfied; the `Pending Removal` table in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) is empty (all
retirement rows have moved to `Completed`).

### Deliverables

- `DEVELOPMENT_PLAN/README.md` `Closure Status` reflects every phase as `Done`
  on the relevant scope and the Exit Definition as satisfied.
- `DEVELOPMENT_PLAN/00-overview.md` `Current Baseline` reflects the end-state
  worktree: backend (iv) Rust and backend (v) Haskell live, retired backend
  evidence recorded without checked-in generated validation data, the
  Haskell-vs-(ii) parity verdict recorded, and the one-known-asymmetry PGO note
  finalised.
- `legacy-tracking-for-deletion.md` `Pending Removal` is empty; `Completed`
  carries the (i), (ii), (iii) retirement rows with their `Removed In` dates.
- The doctrine-driven scheduling audit from Sprint `0.2` has zero unowned
  in-scope identifiers; this is rechecked once at plan closure.

### Validation

1. Grep audit: every Exit Definition item from `README.md` has a
   corresponding evidence row (historical evidence, completed sprint, recorded
   verdict).
2. `legacy-tracking-for-deletion.md` `Pending Removal` table has only a
   placeholder row (or is empty).
3. `docker compose run --rm mcts mcts test all` passes on the surviving cohort
   `(rust, haskell)` without requiring checked-in generated validation data.
4. `docker compose run --rm mcts mcts check-code` passes.

### Remaining Work

- None. Reopened Phases `1`, `2`, `6`, `7`, and `8` report `Done` on their
  alignment surfaces; the surviving live cohort remains `(rust, haskell)`, and
  retired-backend evidence remains historical/external rather than generated
  validation data in git.

## Sprint 8.8: No Generated Validation Data Doctrine ✅

**Status**: Done
**Implementation**: `test/unit/Main.hs`, `test/integration/Main.hs`,
`src/MCTS/Generated/Paths.hs`, `src/MCTS/CLI/Parser.hs`,
`src/MCTS/CLI/Spec.hs`, `mcts.cabal`, `.gitignore`, `.dockerignore`
**Docs to update**: `README.md`,
`documents/engineering/unit_testing_policy.md`,
`documents/engineering/determinism_contract.md`,
`documents/engineering/transcript_format.md`,
`documents/engineering/cli_command_surface.md`,
`documents/engineering/backend_ffi_contract.md`,
`documents/engineering/compiler_runtime_tuning.md`,
`documents/engineering/haskell_code_guide.md`,
`documents/engineering/code_quality.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the repository clean-clone validation surface independent of generated
data. Normal `mcts test all`, focused Cabal stanzas, docs checks, and lint checks
must pass without pre-existing transcript directories, byte snapshots, generated
JSON schemas, retired-backend throughput anchors, or other generated validation
files in git.

### Deliverables

- `test/unit/Main.hs` renderer/codec coverage uses semantic assertions,
  property tests, parser checks, and in-memory transcript bytes created inside
  the test process.
- `test/integration/Main.hs` replaces `legacyGoldenCheck` and retired-anchor
  path lookup with synthetic legacy-envelope transcripts generated in temporary
  roots, plus an optional explicit external-artifact suite that is not part of
  `mcts test all`.
- Remove transcript directories and retired-backend evidence roots from
  `trackingGeneratedPaths` / `externallyTrackedPaths`; those registries may track
  generated docs and ignored runtime caches, not repository validation fixtures.
- Keep `mcts build legacy-fixtures` as an explicit Plan/Apply evidence generator,
  but require an output directory in an ignored/external root and document that
  its output is audit evidence, not test input.
- Keep `.gitignore` and `.dockerignore` covering transcript/cache/artifact roots
  so accidental generated-data commits are blocked at the repository boundary.

### Validation

2026-05-19 validation evidence:

- `docker compose run --rm mcts mcts test all` passes on the freshly rebuilt image,
  including `mcts-haskell-style`, `mcts-unit` (26 cases), `mcts-integration`
  (16 cases), `mcts-cross-backend` (7 cases), cross-backend verify, and report-card
  `Verdict: Within tolerance`.
- `docker compose run --rm --build mcts mcts check-code` passes on the current
  source image: file lint, docs check, Haskell style/lint, docs check, and build all.
- Focused local Cabal validation with `/tmp/mcts-cabal-build` also passes for
  `mcts-unit`, `mcts-integration`, `mcts-cross-backend`, `mcts -- docs check`,
  and `git diff --check`.

1. With `test/golden/`, transcript fixture directories, retired throughput
   anchors, and generated schema/snapshot files absent from the worktree,
   `docker compose run --rm mcts mcts test mcts-unit` passes.
2. Under the same absent-data condition,
   `docker compose run --rm mcts mcts test mcts-integration` passes.
3. `docker compose run --rm mcts mcts test mcts-cross-backend` remains the live
   `(rust, haskell)` round-robin comparison and passes without generated repo
   inputs.
4. `docker compose run --rm mcts mcts test all` and
   `docker compose run --rm mcts mcts check-code` pass after the cleanup.
5. `git ls-files` shows no checked-in transcripts, generated schemas, byte
   snapshots, retired throughput anchors, or other generated validation data.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/compiler_runtime_tuning.md` — finalise the Haskell
  tuning subsection, the round-by-round profile log, the parity verdict, and
  the one-known-asymmetry PGO note.
- `documents/engineering/backend_ffi_contract.md` — record the retirement of
  three FFI surfaces.
- `documents/engineering/determinism_contract.md` — finalise: the live
  `(iv)..(v)` cohort reduces to `(rust, haskell)` after Sprint 8.6, with
  historical evidence for retired backends and no checked-in generated
  validation data.
- `documents/engineering/unit_testing_policy.md` — finalise the no-generated
  validation data doctrine and the semantic/property/temp-dir replacement for
  golden-data tests.
- `documents/engineering/transcript_format.md` — clarify that transcripts are
  runtime/cache/audit artifacts, not repository validation fixtures.
- `documents/engineering/code_quality.md` — record that generated-path tracking
  covers generated docs and ignored local artifacts, not generated test inputs.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md` Backends section finalises with `✅ Done` on the
  surviving cohort and `✅ Retired` (historical evidence) on the retired
  backends.
- `legacy-tracking-for-deletion.md` `Completed` table holds the three retirement
  rows and the completed generated-validation-data cleanup rows; `Pending
  Removal` is empty.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [phase-3-haskell-engine.md](phase-3-haskell-engine.md)
- [phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md)
- [phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md)
- [phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md)
- [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
