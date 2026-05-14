# Phase 8: Haskell Performance Parity Closure

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

> **Purpose**: Close the project hypothesis. Tune the Haskell engine until backend
> (v) matches backend (ii) on Q1 and Q2 within the parity tolerance defined in
> [../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md)
> (`HASKELL_PARITY_TOLERANCE = 0.05`), record the
> one-known-asymmetry PGO note, and execute the retirement protocol
> (i)→(ii)→(iii)→(v) with frozen golden anchors.

## Phase Status

📋 Planned. Blocked by Phase `7` closure (the report card from Phase 7 provides the
Q1/Q2 numbers that Phase 8 has to push Haskell to match).

## Phase Summary

Phase `8` is the project's exit condition. Phases `3` and `7` establish the
correctness baseline; this phase tunes for speed until pure Haskell (v) matches
maximally-optimised C++ (ii) on both POC workloads. The tuning levers are the
doctrine-named GHC flags, the LLVM `-mcpu=native` lowering, RTS `-A64m -n4m -qg1 -qb
-T`, `INLINABLE` and `SPECIALIZE` on the search loop, unboxed strict fields
everywhere, no `Maybe` / `Either` in the rollout inner loop, the per-rollout scratch
arena, and the `MutableByteArray#` migration if `MutablePrimArray` profiles cold.
The one-known-asymmetry PGO note is recorded honestly: GHC 9.14 has no production-
grade PGO comparable to GCC/Clang `-fprofile-use` or `rustc -Cprofile-use`, so a
5–15% Haskell-shortfall is *attributable* to that asymmetry rather than papered over
— but per
[../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md)
the pass/fail threshold is `HASKELL_PARITY_TOLERANCE = 0.05`, so any shortfall in
the 5–15% band still renders `Shortfall <ratio>` (with the PGO note attached as
attribution, not as exemption).
Once parity holds, the retirement protocol runs: backend (i) retires after Q6
closure, backend (ii) retires after backend (iii) reaches parity, backend (iii)
retires after backend (v) reaches parity. Backend (iv) Rust stays live as the
cross-language second opinion.

## Sprint 8.1: Haskell Compiler and RTS Tuning 📋

**Status**: Planned
**Implementation**: `mcts.cabal` (ghc-options),
`src/MCTS/Engine/Board.hs`, `src/MCTS/Search/Arena.hs`,
`src/MCTS/Search/Search.hs`, `src/MCTS/Search/Rollout.hs`
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

  plus `-optlo-mcpu=native` (through to LLVM `opt`) and `-optlc-mcpu=native`
  (through to `llc`). The pinned LLVM version is the same one BOLT uses, so the
  Dockerfile carries one LLVM only.
- The executable `mcts.cabal` stanza declares
  `ghc-options: -with-rtsopts=-A64m -n4m -qg1 -qb -T` baked into the binary per
  [00-overview.md → Hard Constraints item 20](00-overview.md).
- `INLINABLE` pragmas on every exported engine primitive in `src/MCTS/Engine/`
  and `src/MCTS/Search/`.
- `SPECIALIZE` pragmas on the search loop for the concrete game type so the
  inner loop sees no class dictionaries.
- Strict fields everywhere (`{-# UNPACK #-} !Int` etc.) — Sprint 3.1 set this up
  for `Board`; Sprint 8.1 audits the search-loop locals (`!let` bindings inside
  `ST` blocks).
- No `Maybe` or `Either` in the rollout inner loop — replace with sentinel
  values or unboxed sum representations per
  [00-overview.md → Hard Constraints item 20](00-overview.md).
- If profiling shows `MutablePrimArray` indexing is suboptimal, migrate to a
  hand-rolled `MutableByteArray#` arena. This is profiling-driven; the sprint
  closure does not require the migration if profiling does not justify it, but
  it does require that the profiling pass has been run and the decision is
  recorded in `documents/engineering/compiler_runtime_tuning.md`.

### Validation

1. `cabal build all` succeeds with the new flag set; no warnings.
2. `cabal test mcts-haskell-style` passes (the tuning flags do not break the
   lint stack).
3. `mcts bench rollouts --backend haskell --threading single --rng native
   --games 100000 --seed 42` shows a measurable improvement over the Phase 3
   baseline (the exact ratio is recorded in
   `documents/engineering/compiler_runtime_tuning.md`).
4. Same-backend determinism still holds: the tuning is correctness-preserving.

### Remaining Work

Not started.

## Sprint 8.2: Profile-Driven Hot-Path Tuning 📋

**Status**: Planned
**Implementation**: `src/MCTS/Engine/`, `src/MCTS/Search/`,
`bench/criterion-suites.hs`
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

### Remaining Work

Not started.

## Sprint 8.3: Parity Verdict and One-Known-Asymmetry Note 📋

**Status**: Planned
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

Not started.

## Sprint 8.4: Backend (i) Retirement 📋

**Status**: Planned
**Implementation**: `legacy-tracking-for-deletion.md`,
`test/golden/cpp-legacy/transcripts/<arch>/*.tr`,
`test/golden/cpp-legacy/throughput.json`,
`mcts.cabal` (remove `cpp-legacy` extra-libs declaration),
`cpp-legacy/RETIRED.md`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/determinism_contract.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

After Q6 closure (backend (i) reproducing `MCTS_legacy` byte-for-byte on benchmark
(b) under the legacy parity envelope), retire backend (i): freeze its transcripts
and throughput numbers in `test/golden/cpp-legacy/`, remove its CLI flag value, and
record the retirement in the cleanup ledger.

### Deliverables

- `test/golden/cpp-legacy/<arch>/transcripts/` captures the canonical transcript
  set for backend (i) at the report-card knob seeds, partitioned by host arch
  (`<arch>` ∈ `{amd64, arm64}`) per [../README.md → Architecture
  envelope](../README.md). Each transcript ships alongside its per-`(backend,
  build)` equity sidecar — the originator `.eq` file produced by the
  retiring backend at retirement time — so post-retirement REPL viewing of
  the originator column survives without backend (i)'s binary being
  available locally: `test/golden/cpp-legacy/<arch>/transcripts/<sha>/cpp-legacy-<engine_build_id_prefix16>.eq`
  with its `.envelope` neighbour holds the bit-equal originator equities
  frozen at retirement, and `inspect replay` reads them as cached
  originator values with a special `archived` envelope status (not
  envelope-mismatched against the missing live binary, but flagged so the
  user knows the originator binary no longer exists in the repo). See
  [../documents/engineering/transcript_format.md → Equity Sidecar
  Cache](../documents/engineering/transcript_format.md).
  `test/golden/cpp-legacy/throughput.json` captures the canonical games/sec
  / sims/sec numbers in a schema-checked JSON format rendered by the same
  `ReportCard` JSON encoder; arch-specific throughput rows are tagged
  under the `host_arch` field.
- `legacy-tracking-for-deletion.md` `Pending Removal` enqueues the row for the
  `cpp-legacy` CLI flag value, the FFI bindings module
  `src/MCTS/FFI/CppLegacy.hs`, the driver module `src/MCTS/Driver/CppLegacy.hs`,
  the `cpp-legacy` extra-libs declaration in `mcts.cabal`, and the
  `mcts-legacy-parity` test stanza. The row moves to `Completed` once the
  surviving cohort's `mcts-cross-backend` stanza runs cleanly without backend
  (i).
- The `VerifyBackend` GADT and the `LegacyParityBackend` GADT update: the
  `mcts verify legacy-parity` subcommand is removed from the `CommandSpec`
  registry; the Q7 question is now answered by the frozen golden record.
- `cpp-legacy/RETIRED.md` documents the retirement: when, why, the canonical
  golden anchor location, and the parity chain `MCTS_legacy ≡ (i) ≡ (ii)..(v)`
  it preserves as a frozen historical fact per
  [legacy-tracking-for-deletion.md → Retirement Protocol
  Reference](legacy-tracking-for-deletion.md). The `cpp-legacy/src/` and
  `cpp-legacy/include/` directories remain in the repository for
  reference value but are no longer built.
- `mcts.cabal` removes the `cpp-legacy` extra-libs declaration so `cabal build
  all` no longer requires the `.so` to be present.

### Validation

1. `mcts test all` runs without backend (i) and emits a report card with the
   four-backend `(ii)..(v)` cohort.
2. `cabal test mcts-cross-backend` passes (Q3 still holds).
3. The Q6 question now reads from `test/golden/cpp-legacy/throughput.json`
   rather than from a live backend (i) binary.
4. `mcts verify legacy-parity` no longer appears in `mcts commands --tree`
   output.

### Remaining Work

Not started.

## Sprint 8.5: Backend (ii) Retirement 📋

**Status**: Planned
**Implementation**: `legacy-tracking-for-deletion.md`,
`test/golden/cpp-imperative/transcripts/<arch>/*.tr`,
`test/golden/cpp-imperative/throughput.json`,
`mcts.cabal` (remove `cpp-imperative` extra-libs declaration),
`cpp-imperative/RETIRED.md`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/compiler_runtime_tuning.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Once backend (iii) C++ functional-style reaches parity with backend (ii) C++
imperative on Q1 and Q2 within the parity tolerance defined in
[../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md),
retire backend (ii): freeze its golden anchor, remove its CLI flag value, record
the retirement.

### Deliverables

- `test/golden/cpp-imperative/transcripts/` and
  `test/golden/cpp-imperative/throughput.json` capture the canonical golden
  anchor.
- `legacy-tracking-for-deletion.md` `Pending Removal` enqueues the row for the
  `cpp-imperative` CLI flag value, the FFI bindings, the driver module, and
  the build harness entry. Moves to `Completed` when the surviving cohort's
  `mcts-cross-backend` stanza runs cleanly.
- `cpp-imperative/RETIRED.md` documents the retirement.
- `mcts.cabal` removes the `cpp-imperative` extra-libs declaration.
- The Q1 and Q2 questions are now answered against `test/golden/cpp-imperative/
  throughput.json` rather than against a live (ii) binary, preserving the
  Haskell-vs-(ii) performance target as a fixed number per the project
  [README → First milestone](../README.md).

### Validation

1. `mcts test all` runs with the surviving cohort `(iii), (iv), (v)` plus the
   frozen (ii) anchor and emits a report card.
2. `cabal test mcts-cross-backend` passes.
3. The (ii) anchor in `test/golden/cpp-imperative/throughput.json` is
   schema-checked by `mcts-unit`.

### Remaining Work

Not started.

## Sprint 8.6: Backend (iii) Retirement 📋

**Status**: Planned
**Implementation**: `legacy-tracking-for-deletion.md`,
`test/golden/cpp-functional/transcripts/<arch>/*.tr`,
`test/golden/cpp-functional/throughput.json`,
`mcts.cabal` (remove `cpp-functional` extra-libs declaration),
`cpp-functional/RETIRED.md`
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

- `test/golden/cpp-functional/transcripts/` and
  `test/golden/cpp-functional/throughput.json` capture the canonical golden
  anchor.
- `legacy-tracking-for-deletion.md` `Pending Removal` row for the
  `cpp-functional` flag value, FFI bindings, driver, and build harness entry,
  moving to `Completed` when the surviving cohort runs cleanly.
- `cpp-functional/RETIRED.md` documents the retirement.
- `mcts.cabal` removes the `cpp-functional` extra-libs declaration.

### Validation

1. `mcts test all` runs with the surviving cohort `(rust, haskell)` and emits
   a report card.
2. `cabal test mcts-cross-backend` passes (Q3 holds on the two-backend cohort).

### Remaining Work

Not started.

## Sprint 8.7: Plan Closure 📋

**Status**: Planned
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
  worktree: backend (iv) Rust and backend (v) Haskell live, three golden
  anchors frozen in `test/golden/`, the Haskell-vs-(ii) parity verdict
  recorded, the one-known-asymmetry PGO note finalised.
- `legacy-tracking-for-deletion.md` `Pending Removal` is empty; `Completed`
  carries the (i), (ii), (iii) retirement rows with their `Removed In` dates.
- The doctrine-driven scheduling audit from Sprint `0.2` has zero unowned
  in-scope identifiers; this is rechecked once at plan closure.

### Validation

1. Grep audit: every Exit Definition item from `README.md` has a
   corresponding evidence row (golden anchor, completed sprint, recorded
   verdict).
2. `legacy-tracking-for-deletion.md` `Pending Removal` table has only a
   placeholder row (or is empty).
3. `mcts test all` passes on the surviving cohort `(rust, haskell)` with
   frozen golden anchors for (i), (ii), (iii) honoured.
4. `mcts check-code` passes.

### Remaining Work

Not started.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/compiler_runtime_tuning.md` — finalise the Haskell
  tuning subsection, the round-by-round profile log, the parity verdict, and
  the one-known-asymmetry PGO note.
- `documents/engineering/backend_ffi_contract.md` — record the retirement of
  three FFI surfaces.
- `documents/engineering/determinism_contract.md` — finalise: the four-backend
  cohort reduces to `(rust, haskell)` after Sprint 8.6, with frozen anchors for
  the retired backends.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md` Backends section finalises with `✅ Done` on the
  surviving cohort and `✅ Retired` (frozen anchor) on the retired backends.
- `legacy-tracking-for-deletion.md` `Completed` table holds the three retirement
  rows.

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
