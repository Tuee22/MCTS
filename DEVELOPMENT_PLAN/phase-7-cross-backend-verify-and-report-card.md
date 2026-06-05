# Phase 7: Cross-Backend Verify, Test Stanzas, POC Report Card

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md),
[../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md),
[../documents/engineering/semantic_parity_contract.md](../documents/engineering/semantic_parity_contract.md)
**Generated sections**: none

> **Purpose**: Land the cross-backend verification gates, Cabal test stanzas,
> `mcts test all` report card, and interactive play/replay surfaces that prove the
> five-backend hypothesis end to end.

## Phase Status

🔄 **Active** for the operator UI/test surface. The current Q1-Q7 metric-suite
report-card refactor remains Done, including Sprint `7.11` Q7 semantic parity.
The Phase 7 correctness
surface remains live: Q3 verifies `(ii)..(v)`, Q6 verifies the `(i)..(v)` legacy
envelope, the report-card machinery measures Q1a terminal playout throughput,
Q1b search-iteration throughput, Q2 played-game self-play throughput, and split
Q5 scaling rows against live backend (ii), and no checked-in generated validation
data is required. The optimized-C++ parity evidence was refreshed by Sprint `8.3`
after Sprint `5.3` closed. Sprint `7.6` reclosed the inspect/replay/divergence
evidence surface on 2026-05-21 so originator, foreign-view, unavailable, and
live-recompute labels cannot be misread as stronger evidence than the matching
backend/build actually provides.

Sprint `7.12` reopened on 2026-06-05 after operator use exposed that the live play
TUI, saved replay TUI, and test coverage are not one end-to-end operator surface:
AI-vs-AI observation advances one ply at a time in the current dispatcher, but the
documented host path cannot open the TUI, live games cannot be replayed with the
same overlay controls as saved games, and `mcts test all` does not exercise real
PTY play/spectate/inspect interactions.

The 2026-05-19 report-card evidence remains useful smoke-baseline audit context:
Q1 ST 0.05x,
Q1 MT8 0.41x, Q2 ST 0.05x, Q2 MT8 0.20x, Q5 Haskell 0.99x, Q5 `cpp-imperative`
3.64x, Q6 liveness PASS, and verdict `Within tolerance`.

The 2026-05-21 report-card refresh remains historical fallback-backed evidence.
The 2026-05-23 report-card refresh against the fail-closed Dockerfile PGO+BOLT
build path recorded Q1 ST 0.05x, Q1 MT8 0.45x, Q2 ST 0.06x, Q2 MT8 0.22x,
Q5 Haskell 0.98x, Q5 C++ (ii) 3.70x, Q6 liveness PASS, zero live-cohort
divergence, and verdict `Within tolerance`. That evidence remains historical
played-game throughput context under the 2026-05-24 metric taxonomy. Sprint `7.8`
closed the report-card row semantics so Q1/Q5 distinguish terminal playout
throughput, search-iteration throughput, and played-game throughput per
[../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md).
Sprint `7.9` closed on 2026-05-25 after the headline report-card mapping was
renumbered to Q1-Q6 and the aggregate report card revalidated with verdict
`Within tolerance` for the then-current backend (ii) artefact. Sprint `5.6` later
strengthened backend (ii), and Phase `8` Sprint `8.12` refreshed the parity
evidence while this phase remains closed for report-card structure. Sprint `7.10`
keeps that structure closed by making the text renderer define its terms, align
columns, render raw performance metrics for every backend ahead of the question
summary and divergence matrix, end with observed-metric answers for Q1a-Q7, and
expose the raw rows in JSON. Sprint `7.11` adds Q7 semantic parity for `(ii)..(v)`,
removes empirical divergence thresholds from report-card wording, and replaces the
divergence headline with a single normalized score derived from the matrix.
Sprint `7.12` owns the shared live/replay game-session model and the interaction
tests needed to prove that operator surface.

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
- `mcts-legacy-parity` for Q6 all-five legacy-envelope liveness/overflow.
- `mcts-haskell-style` for formatter, HLint, and source-walker guards.

### Validation

- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts test mcts-integration`
- `docker compose run --rm mcts mcts test mcts-cross-backend`
- `docker compose run --rm mcts mcts test mcts-legacy-parity`
- `docker compose run --rm mcts mcts test mcts-haskell-style`

### Remaining Work

None.

## Sprint 7.2: Q3 and Q6 Verification Gates ✅

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
- Q6: `mcts verify legacy-parity {rollouts,selfplay}` checks all five backend slots
  under the legacy envelope.
- `--rng cpp` uses C++-generated verification seeds from the C++ RNG bridge for equivalence.
- `--rng native` is not used to prove cross-backend transcript identity.

### Validation

- `docker compose run --rm mcts mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200`
- `docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500`
- `docker compose run --rm mcts mcts verify legacy-parity selfplay --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --games 2 --seed 42 --sims 4`

### Remaining Work

None.

## Sprint 7.3: `mcts test all` Report Card ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Test.hs`, `docker/Dockerfile`, `cabal.project`
**Docs to update**: `documents/engineering/unit_testing_policy.md`,
`documents/engineering/compiler_runtime_tuning.md`

### Objective

Emit one concise report-card block answering Q1-Q6.

### Deliverables

- Q1/Q2: Haskell vs live backend (ii) on the implemented played-game rollout and
  self-play rows, single-threaded and 8-worker.
- Q3: `(ii)..(v)` zero-divergence visit-vector checks.
- Q4: same-backend determinism over multiple seeds.
- Q5: scaling rows for Haskell and backend (ii).
- Q6: all-five legacy-envelope liveness/overflow evidence.
- Runtime validation consumes Dockerfile-prebuilt Cabal test-suite executables and
  the installed image-local `mcts` binary; compile/link work belongs to image
  construction rather than the `mcts test all` apply phase.

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

Make the report card answer Q1-Q6 using unambiguous metric units instead of the
legacy overloaded "rollouts" and derived simulation-rate labels.

### Deliverables

- Q1a terminal playout throughput rows (`playouts/s`) for Haskell vs backend (ii).
- Q1b search-iteration throughput rows (`search-iters/s`) for Haskell vs backend (ii).
- Q2 played-game self-play throughput rows (`games/s`) for Haskell vs backend (ii).
- Q5 scaling rows that keep search-iteration scaling and played-game scaling separate.
- Q6 legacy-envelope liveness/overflow evidence across all five backend slots without
  checked-in generated validation inputs.
- Renderer and JSON field names that include the unit, so old `rollouts` and
  ambiguous simulation-rate labels cannot be mistaken for lower-level metrics.
- Played-game benchmark output exposes only `games/s` in text and
  `games_per_second` in JSON.

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
and split Q5 scaling rows. A 2026-05-25 follow-up removed the derived
simulation-rate column from played-game benchmark output, leaving `games/s` as the
only played-game throughput unit.

## Sprint 7.9: Six-Question Report-Card Renumbering ✅

**Status**: Done
**Implementation**: `src/MCTS/ReportCard.hs`, `src/MCTS/CLI/Spec.hs`,
`src/MCTS/Generated/Sections.hs`
**Docs to update**: `README.md`, `documents/engineering/benchmark_metrics.md`,
`documents/engineering/unit_testing_policy.md`,
`documents/engineering/determinism_contract.md`,
`documents/engineering/cli_command_surface.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Remove the external `MCTS_legacy` reproduction headline question and make the
legacy-envelope liveness/overflow gate the sixth report-card question for Sprint
`7.9` closure.

### Deliverables

- `MCTS.ReportCard.renderReportCard` emits Q1-Q6 only; the old historical
  external-reproduction row is removed.
- `mcts build legacy-fixtures` is described as an optional external audit-fixture
  generator, not as numbered report-card evidence.
- README, governed engineering docs, and the development plan use the Q1-Q6
  mapping consistently for the Sprint `7.9` surface. Sprint `7.11` later adds Q7
  semantic parity without restoring the removed external reproduction row.
- `legacy-tracking-for-deletion.md` records the removed headline question as
  completed cleanup.

### Validation

- `docker compose run --rm mcts mcts docs generate`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts test mcts-legacy-parity`
- `docker compose run --rm mcts mcts check-code`
- `docker compose run --rm mcts mcts test all`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

Closed on 2026-05-25. The focused validation passed, and the aggregate
`docker compose run --rm mcts mcts test all` gate emitted the six-question report
card with Q6 legacy-envelope PASS, zero live-cohort divergence, and verdict
`Within tolerance`.

## Sprint 7.10: Report-Card Tables, Raw Backend Metrics, and Final Answers ✅

**Status**: Done
**Implementation**: `src/MCTS/ReportCard.hs`, `src/MCTS/CLI/Test.hs`,
`test/unit/Main.hs`
**Docs to update**: `README.md`, `documents/engineering/benchmark_metrics.md`,
`documents/engineering/unit_testing_policy.md`,
`documents/engineering/cli_command_surface.md`,
`documents/engineering/determinism_contract.md`, `DEVELOPMENT_PLAN/README.md`,
`DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the human report-card output readable as aligned tables while preserving the
Q1/Q2/Q5 verdict semantics and the no-generated-validation-data doctrine, and end
the report card with explicit Q1a-Q6 answers derived from the observed metrics and
gate outcomes.

### Deliverables

- Text output defines `ST`, `MT8`, Q1a, Q1b, Q2, Q5, and `visit/move` before
  rendering evidence.
- A raw performance table records Q1a/Q1b/Q2 observed rates for every backend slot
  and appears before the question-summary and divergence-matrix tables.
- The question-summary table states every Q1a/Q1b/Q2/Q3/Q4/Q5/Q6 question and keeps
  Haskell-vs-backend-(ii) parity ratios as the load-bearing Q1/Q2 evidence.
- The divergence matrix remains the third table and is rendered with aligned
  backend columns.
- A final question-answer table explicitly answers Q1a-Q6 from the observed
  parity ratios, scaling values, divergence rates, and gate outcomes.
- JSON output includes `raw_performance_metrics` alongside the unit-specific
  Q1/Q2/Q5 fields and `divergence_matrix`.
- `legacy-tracking-for-deletion.md` records the prior unaligned/no-raw-table report
  card shape as completed stale-surface cleanup.

### Validation

- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

## Sprint 7.11: Q7 Semantic Parity and Divergence Score ✅

**Status**: Done
**Implementation**: `src/MCTS/Verify/Semantic.hs`, `test/semantic-parity`,
`mcts.cabal`, `docker/Dockerfile`, `src/MCTS/CLI/Test.hs`,
`src/MCTS/Prerequisite.hs`, `src/MCTS/ReportCard.hs`, `test/unit/Main.hs`
**Docs to update**: `README.md`, `documents/engineering/semantic_parity_contract.md`,
`documents/engineering/unit_testing_policy.md`,
`documents/engineering/determinism_contract.md`,
`documents/engineering/backend_ffi_contract.md`,
`documents/engineering/benchmark_metrics.md`,
`documents/engineering/cli_command_surface.md`, `DEVELOPMENT_PLAN/README.md`,
`DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Promote semantic parity to Q7 without weakening Q3. Q7 proves that steelman
backends `(ii)..(v)` implement the same game-rule and MCTS semantics through
rule-state parity, replay compatibility, search-invariant, and terminal-rejection
checks, even when bit-for-bit play is not the claim.

### Deliverables

- `mcts-semantic-parity` Cabal stanza with its own `tasty` runner.
- `MCTS.Verify.Semantic` helper layer for generated reachable histories, replay
  compatibility checks, search-invariant checks, and terminal-board rejection.
- Reuse of the existing C ABI (`new_board`, `free_board`, `is_terminal`,
  `apply_action`, `search_move`) without adding a direct legal-action ABI in this
  sprint.
- `mcts test all` includes the prebuilt `mcts-semantic-parity` executable after the
  image installs it.
- Report-card question summary and final answers include Q7.
- Report-card divergence output removes empirical threshold text and reports
  `normalized_divergence_score`, defined as the maximum visit or move disagreement
  rate across every matrix cell.
- `mcts-unit` adds an explanatory renderer test with a constructed non-zero
  divergence matrix proving the normalized score is derived from the matrix, not
  from a hard-coded zero path.
- `legacy-tracking-for-deletion.md` records the old threshold constants and renderer
  wording as completed cleanup after the code and generated comments were corrected.

### Validation

- `docker compose run --rm --build mcts mcts test mcts-semantic-parity`
- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts test all`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Current Validation State

Sprint `7.11` closed on 2026-05-28. Focused validation passed:

- `mcts-semantic-parity` with the Q7 steelman semantic-parity case;
- `mcts-unit`, including report-card renderer coverage for Q7 and a constructed
  non-zero normalized divergence score.

The aggregate docs/code/final-test gates are shared with Sprint `6.8` closure
because both reopened surfaces landed in the same worktree update.

### Remaining Work

None.

## Sprint 7.12: Unified Game Session UI and Interaction Coverage 🔄

**Status**: Active
**Implementation**: `src/MCTS/CLI/Tui/Play.hs`,
`src/MCTS/CLI/Tui/Replay.hs`, `src/MCTS/CLI/Tui/Board.hs`,
`src/MCTS/CLI/Inspect.hs`, `src/MCTS/App.hs`, `test/unit`,
`test/integration`, optional new PTY-focused Cabal test stanza if needed.
**Blocked by**: Sprint `9.4` for host-side TTY and refactored
`hostbootstrap.dhall` cache-mount closure; Sprint `1.18`
for no-argument command surfaces; Sprint `2.10` for cache catalog and
recorded-position recompute semantics.
**Docs to update**: `README.md`, `documents/engineering/cli_command_surface.md`,
`documents/engineering/unit_testing_policy.md`,
`documents/engineering/determinism_contract.md`,
`documents/engineering/transcript_format.md`, `DEVELOPMENT_PLAN/README.md`,
`DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Unify live play, AI-vs-AI observation, saved replay, in-progress replay, and
backend equity overlays under one DRY game-session UI and prove the operator
interactions with PTY-backed tests.

### Deliverables

- A shared game-session state model represents both saved transcripts and live games:
  board timeline, current cursor, live cursor, player control map, transcript metadata,
  loaded overlay columns, unavailable backend evidence, and save status.
- Human-vs-AI and AI-vs-AI observed games use the same board/timeline/replay widgets
  as saved `inspect replay`. The operator can rewind through already-played plies,
  step forward, return to the live cursor, save, and continue the live game.
- Spectator mode advances one AI ply per Space by default. It does not fly through the
  entire game unless a future explicit auto-advance control is added.
- On-demand backend equity overlays work from both saved replay and live replay
  cursors, using the recorded-position recompute contract from Sprint `2.10`.
- The implementation removes duplicated play-vs-replay board/status/timeline logic or
  concentrates unavoidable differences at a small adapter boundary.
- Tests cover user interactions rather than checked-in golden histories:
  no-argument `play`, explicit human-vs-AI play, AI-vs-AI spectate, no-argument
  `inspect`, cache-browser selection, saved replay, live replay/scrub, save and
  reopen, on-demand overlay load, missing-backend unavailable labels, invalid input,
  and non-TTY guardrail behavior.
- `mcts test all` includes the new interaction tests or names the prebuilt
  interaction stanza in its Plan/Apply sequence.

### Validation

- `hostbootstrap run test mcts-unit`
- `hostbootstrap run test mcts-integration`
- `hostbootstrap run test all`
- `hostbootstrap run docs check`
- `hostbootstrap run check-code`
- PTY-backed tests synthesize all game histories and cache entries in temporary roots.

### Remaining Work

- Design and implement the shared game-session state model.
- Refactor play/replay TUI modules onto the shared board/timeline/overlay path.
- Add PTY-backed interaction coverage and wire it into `mcts test all`.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/cli_command_surface.md` — verify/test/play command surfaces plus
  Sprint `7.6` replay/divergence evidence labels and Sprint `7.8` report-card
  metric units, Sprint `7.11` Q7 stanza routing and normalized divergence-score
  wording, and Sprint `7.12` unified live/replay game-session behavior.
- `documents/engineering/benchmark_metrics.md` — benchmark unit taxonomy and
  Q1-Q7 evidence mapping, including Sprint `7.8` metric units, Sprint `7.10`
  report-card term definitions and raw backend metric table semantics, and Sprint
  `7.11` semantic-parity implementation.
- `documents/engineering/determinism_contract.md` — Q3/Q6 semantics, RNG split, and
  Sprint `7.6` originator/foreign-view replay semantics, plus Sprint `7.11`
  normalized divergence-score wording.
- `documents/engineering/semantic_parity_contract.md` — Q7 semantic parity SSoT.
- `documents/engineering/unit_testing_policy.md` — test stanza ownership and no generated
  validation data, plus the Sprint `7.10` report-card table layout and Sprint `7.11`
  semantic-parity stanza, plus Sprint `7.12` PTY-backed play/spectate/inspect
  interaction coverage.

**Product docs to create/update:**

- `README.md`

**Cross-references to add:**

- Keep [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
  aligned with live C++ verification and report-card measurement.
- `legacy-tracking-for-deletion.md` records Sprint `7.6` replay/divergence residue as
  completed after output labels and live recompute row coverage were reclosed, and
  records Sprint `7.10` report-card text-layout residue as completed; Sprint `7.11`
  records divergence-threshold renderer/comment residue as completed after the
  normalized-score renderer and Q7 semantic-parity stanza landed. Sprint `7.12`
  records the split live/replay UI and missing PTY interaction coverage as active
  cleanup until the unified session closes.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
