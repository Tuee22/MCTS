# Phase 7: Cross-Backend Verify, Test Stanzas, POC Report Card

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md),
[../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md)
**Generated sections**: none

> **Purpose**: Land the cross-backend verification gates, Cabal test stanzas,
> `mcts test all` report card, and interactive play/replay surfaces that prove the
> five-backend hypothesis end to end.

## Phase Status

✅ **Done** for the metric-suite report-card refactor. The Phase 7 correctness
surface remains live: Q3 verifies `(ii)..(v)`, Q7 verifies the `(i)..(v)` legacy
envelope, the report-card machinery measures Q1a terminal playout throughput,
Q1b search-iteration throughput, Q2 played-game self-play throughput, and split
Q5 scaling rows against live backend (ii), and no checked-in generated validation
data is required. The optimized-C++ parity evidence was refreshed by Sprint `8.3`
after Sprint `5.3` closed. Sprint `7.6` reclosed the inspect/replay/divergence
evidence surface on 2026-05-21 so originator, foreign-view, unavailable, and
live-recompute labels cannot be misread as stronger evidence than the matching
backend/build actually provides.

The 2026-05-19 report-card evidence remains useful smoke-baseline audit context:
Q1 ST 0.05x,
Q1 MT8 0.41x, Q2 ST 0.05x, Q2 MT8 0.20x, Q5 Haskell 0.99x, Q5 `cpp-imperative`
3.64x, Q7 liveness PASS, and verdict `Within tolerance`.

The 2026-05-21 report-card refresh remains historical fallback-backed evidence.
The 2026-05-23 report-card refresh against the fail-closed Dockerfile PGO+BOLT
build path recorded Q1 ST 0.05x, Q1 MT8 0.45x, Q2 ST 0.06x, Q2 MT8 0.22x,
Q5 Haskell 0.98x, Q5 C++ (ii) 3.70x, Q7 liveness PASS, zero live-cohort
divergence, and verdict `Within tolerance`. That evidence remains historical
played-game throughput context under the 2026-05-24 metric taxonomy. Sprint `7.8`
closed the report-card row semantics so Q1/Q5 distinguish terminal playout
throughput, search-iteration throughput, and played-game throughput per
[../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md).

## Sprint 7.1: Cabal Test Organization ✅

**Status**: Done
**Implementation**: `mcts.cabal`, `test/unit`, `test/integration`,
`test/cross-backend`, `test/legacy-parity`, `test/haskell-style`
**Docs to update**: `documents/engineering/unit_testing_policy.md`

### Objective

Keep each validation tier in its own Cabal `exitcode-stdio-1.0` stanza with a local
`tasty` runner.

### Deliverables

- `mcts-unit` for pure logic, parser, codec, renderer, and TUI semantics.
- `mcts-integration` for real binary and dynamic FFI smoke checks.
- `mcts-cross-backend` for Q3 `(ii)..(v)`.
- `mcts-legacy-parity` for Q7 all-five legacy-envelope liveness/overflow.
- `mcts-haskell-style` for formatter, HLint, and source-walker guards.

### Validation

- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts test mcts-integration`
- `docker compose run --rm mcts mcts test mcts-cross-backend`
- `docker compose run --rm mcts mcts test mcts-legacy-parity`
- `docker compose run --rm mcts mcts test mcts-haskell-style`

### Remaining Work

None.

## Sprint 7.2: Q3 and Q7 Verification Gates ✅

**Status**: Done
**Implementation**: `src/MCTS/Verify.hs`, `src/MCTS/Types.hs`,
`src/MCTS/CLI/Parser.hs`, `test/cross-backend`, `test/legacy-parity`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Separate logical equivalence from performance benchmarking.

### Deliverables

- Q3: `mcts verify {rollouts,selfplay}` compares `(ii)..(v)` visit tables under
  `--rng cpp`.
- Q7: `mcts verify legacy-parity {rollouts,selfplay}` checks all five backend slots
  under the legacy envelope.
- `--rng cpp` uses C++-generated verification seeds from the C++ RNG bridge for equivalence.
- `--rng native` is not used to prove cross-backend transcript identity.

### Validation

- `docker compose run --rm mcts mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200`
- `docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500`
- `docker compose run --rm mcts mcts verify legacy-parity selfplay --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --games 2 --seed 42 --sims 10000`

### Remaining Work

None.

## Sprint 7.3: `mcts test all` Report Card ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Test.hs`, `cabal.project`
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/compiler_runtime_tuning.md`

### Objective

Emit one concise report-card block answering Q1-Q7.

### Deliverables

- Q1/Q2: Haskell vs live backend (ii) on the implemented played-game rollout and
  self-play rows, single-threaded and 8-worker.
- Q3: `(ii)..(v)` zero-divergence visit-vector checks.
- Q4: same-backend determinism over multiple seeds.
- Q5: scaling rows for Haskell and backend (ii).
- Q6: explicit legacy reproduction evidence generated outside checked-in fixtures.
- Q7: all-five legacy-envelope liveness/overflow evidence.

### Validation

`docker compose run --rm mcts mcts test all`

### Remaining Work

None.

## Sprint 7.4: Play and Replay TUIs ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Tui/Play.hs`, `src/MCTS/CLI/Tui/Replay.hs`,
`src/MCTS/CLI/Tui/Board.hs`
**Docs to update**: `documents/engineering/cli_command_surface.md`

### Objective

Provide interactive operator surfaces for playing and inspecting games while keeping the
CLI non-interactive fallback usable on pipes.

### Deliverables

- `mcts play` with `--backend`, `--side`, `--vs`, `--rng`, `--seed`, `--max-plies`,
  and `--cache-dir`.
- TUI board rendering through `brick`/`vty`.
- `:hint`, `:undo`, `:save`, and `:quit`.
- `inspect replay` navigation with cached/on-demand backend equity overlays.

### Validation

`docker compose run --rm mcts mcts test mcts-unit`

### Remaining Work

None.

## Sprint 7.5: Envelopes, Divergence, and Generated-Data Cleanup ✅

**Status**: Done
**Implementation**: `src/MCTS/Verify/Divergence.hs`, `src/MCTS/Verify/Envelope.hs`,
`src/MCTS/Generated/Paths.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Make verification evidence reproducible without checked-in generated fixtures.

### Deliverables

- Digest-first comparator with length-aware mismatch reporting.
- Layered engine-envelope checks and `--allow-stale` warnings.
- Divergence rows for cached or available backend `.eq` sidecars.
- Generated validation data excluded from normal test prerequisites.

### Validation

- `docker compose run --rm mcts mcts test mcts-integration`
- `docker compose run --rm mcts mcts docs check`

### Remaining Work

None.

## Sprint 7.6: Replay and Divergence Evidence Labels ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Inspect.hs`, `src/MCTS/CLI/Tui/Replay.hs`,
`src/MCTS/Engine/ForeignRecompute.hs`, `test/unit`, `test/integration`
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`documents/engineering/determinism_contract.md`,
`documents/engineering/transcript_format.md`,
`documents/engineering/unit_testing_policy.md`, `DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make replay and divergence output preserve the distinction between originator
evidence, foreign-view evidence, stale-build evidence, and unavailable evidence.

### Deliverables

- `inspect show --with-equity` reads an envelope-matched originator sidecar first and
  writes an originator replacement only through the same backend/build slot. If the
  matching backend cannot recompute, the command reports unavailable or foreign-view
  evidence instead of writing a Haskell recompute under the originator label.
- `inspect replay` prepares a missing originator column only through the matching
  backend/build and marks foreign or fallback columns explicitly.
- `inspect divergence <hash>` emits rows for every available cached sidecar and every
  available live foreign recompute backend, including C++ backends where their cdylibs
  are present. Rust-only live recompute is no longer described as the all-backend
  surface.
- Unit and integration tests assert the originator/foreign/unavailable labels and prove
  that a foreign recompute cannot be persisted as the originator stream.

### Validation

- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts test mcts-integration`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

Sprint `7.6` reclosed on 2026-05-21. Validation passed with:

- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts test mcts-integration`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

## Sprint 7.7: Verifier Gate and Divergence Metric Realignment ✅

**Status**: Done
**Implementation**: `src/MCTS/Verify/Envelope.hs`,
`src/MCTS/Verify/Divergence.hs`, `test/unit/Main.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/cli_command_surface.md`,
`documents/engineering/transcript_format.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Keep the verifier focused on reproducibility-affecting envelope fields and describe
divergence metrics at the precision actually produced by the current sidecar format.

### Deliverables

- Live and cached envelope checks hard-fail cohort-invariant disagreements, gate
  backend-slot substrate fields, and leave `engine_git_commit` plus display/cache
  `build_id` as provenance.
- `--allow-stale` remains a forensic downgrade only for backend-slot mismatches.
- Divergence documentation states that `EqStream` carries chosen-action equity and
  that `equity_l2_drift` is RMS over the per-move chosen-action series.

### Validation

- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

Closed on 2026-05-24 after verifier behavior, CLI stale-envelope wording, and
divergence metric docs were aligned.

## Sprint 7.8: Report-Card Metric Semantics Refactor ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Test.hs`, `src/MCTS/ReportCard.hs`,
`src/MCTS/CLI/Bench.hs`, `test/unit/Main.hs`, `test/integration/Main.hs`
**Docs to update**: `../documents/engineering/benchmark_metrics.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/cli_command_surface.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the report card answer Q1-Q7 using unambiguous metric units instead of the
legacy overloaded "rollouts" and derived "sims/s" labels.

### Deliverables

- Q1a terminal playout throughput rows (`playouts/s`) for Haskell vs backend (ii).
- Q1b search-iteration throughput rows (`search-iters/s`) for Haskell vs backend (ii).
- Q2 played-game self-play throughput rows (`games/s`) for Haskell vs backend (ii).
- Q5 scaling rows that keep search-iteration scaling and played-game scaling separate.
- Q6 legacy evidence hooks that compare backend (i) with external `MCTS_legacy` on
  terminal playout and legacy `simulate(N)` throughput without making those artifacts
  normal validation inputs.
- Renderer and JSON field names that include the unit, so old `rollouts` and
  ambiguous `sims/s` labels cannot be mistaken for lower-level metrics.

### Validation

- `docker compose run --rm --build mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts test mcts-integration`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

Sprint `7.8` reclosed on 2026-05-24 after the report-card renderer and JSON schema
switched to unit-aware Q1a terminal playout, Q1b search-iteration, Q2 played-game,
and split Q5 scaling rows.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cli_command_surface.md` — verify/test/play command surfaces plus
  Sprint `7.6` replay/divergence evidence labels and Sprint `7.8` report-card
  metric units.
- `documents/engineering/benchmark_metrics.md` — benchmark unit taxonomy and Q1-Q7 metric
  mapping for Sprint `7.8`.
- `documents/engineering/determinism_contract.md` — Q3/Q7 semantics, RNG split, and
  Sprint `7.6` originator/foreign-view replay semantics.
- `documents/engineering/unit_testing_policy.md` — test stanza ownership and no generated
  validation data.

**Product docs to create/update:**

- `README.md`

**Cross-references to add:**

- Keep [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
  aligned with live C++ verification and report-card measurement.
- `legacy-tracking-for-deletion.md` records Sprint `7.6` replay/divergence residue as
  completed after output labels and live recompute row coverage were reclosed.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
