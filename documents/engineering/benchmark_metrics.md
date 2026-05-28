# Benchmark Metrics

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/00-overview.md, ../../DEVELOPMENT_PLAN/system-components.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-3-haskell-engine.md, ../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md, ../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md, ../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md, ../documentation_standards.md, ./README.md, ./cli_command_surface.md, ./compiler_runtime_tuning.md, ./determinism_contract.md, ./semantic_parity_contract.md, ./unit_testing_policy.md
**Generated sections**: none

> **Purpose**: Define the benchmark units used by Q1/Q2/Q5 and the Q1-Q7
> report-card mapping so terminal random playouts, MCTS search iterations,
> complete played games, and semantic-parity evidence are not conflated.

This document is the single source of truth for benchmark metric semantics. It does
not change the determinism contract: correctness verification still lives in
[determinism_contract.md](./determinism_contract.md), and the test/report-card gate
lives in [unit_testing_policy.md](./unit_testing_policy.md).

## Metric Taxonomy

| Metric | Unit | Counted work | What it answers |
|--------|------|--------------|-----------------|
| Terminal playout throughput | `playouts/s` | One random trajectory from an explicit board position until terminal, non-terminal exact evaluation, or rollout cap. No MCTS tree is allocated or updated. | Whether board copying/scratch state, legal moves, terminal checks, and random move selection match the legacy pure-rollout kernel. |
| Search-iteration throughput | `search-iters/s` | One UCT/MCTS iteration: select through the tree, expand or evaluate the leaf, run a terminal playout when the policy calls for rollout evaluation, and backpropagate. | Whether the actual search core is fast, independent of complete-game length and transcript overhead. |
| Played-game throughput | `games/s` | One full game from the starting position to terminal or `max_plies`; each real move runs the configured search budget, chooses an action, applies it, and records transcript visits. | Whether the integrated backend path performs well, including search, move application, FFI dispatch, transcript forcing, and batch/thread scheduling. |

The names are intentionally explicit. Avoid unqualified `rollout` or
`simulation` in new documentation because each has been used for more than one
unit, and do not add derived simulation-rate columns to played-game output.

## Current CLI Surface

The public CLI exposes explicit primitive benchmark leaves and still carries
legacy played-game names:

- `mcts bench terminal-playouts` measures direct terminal playout throughput and
  reports `playouts/s`.
- `mcts bench search-iters` measures direct UCT/MCTS search-iteration throughput
  and reports `search-iters/s`.
- `mcts bench rollouts` remains a legacy command name. It measures
  **played-game throughput** with one
  search iteration per real move and reports `games/s`, not terminal
  `playouts/s`.
- `mcts bench selfplay` also measures **played-game throughput**, but each real
  move uses the configured self-play search budget and reports `games/s`.
- Played-game benchmark renderers expose only `games/s`
  (`games_per_second` in JSON). The removed derived simulation-rate column was
  not an observed count of terminal playouts or search iterations across all
  moves.

Documentation may refer to `bench rollouts` only as a legacy played-game CLI
name. The report card uses the explicit primitive leaves for Q1a/Q1b and keeps
played-game self-play rows under `games/s`.

## Report-Card Terms

The text report card defines these terms before rendering evidence:

| Term | Definition |
|------|------------|
| `ST` | Single-threaded benchmark or verification run. |
| `MT8` | Multi-threaded benchmark run with 8 workers. |
| `Q1a` | Terminal playout throughput question, reported in `playouts/s`. |
| `Q1b` | UCT/MCTS search-iteration throughput question, reported in `search-iters/s`. |
| `Q2` | Complete self-play game throughput question, reported in `games/s`. |
| `Q5` | `MT8 / ST` scaling ratio for the named backend and metric. |
| `visit/move` | Divergence matrix cell containing visit-table and chosen-move disagreement rates. |

Raw backend performance metrics are observed rates, not ratios. The text report
card renders one raw table row per backend and metric family before the question
summary and divergence-matrix tables, then ends with an explicit answer summary
derived from the observed ratios, scaling values, divergence score, and gate
outcomes. Q1/Q2 verdict logic still uses backend (v) Haskell against backend (ii)
`cpp-imperative`; the extra raw rows are context for all five backend slots, not
additional pass/fail gates. Backend (iv) Rust raw rows remain context rather than
Q1/Q2 verdict inputs after Phase `6` Sprint `6.8` aligns its hot path with the
functional-core cohort.

The Sprint `8.14` `Within tolerance` verdict is current-artifact evidence for the
Sprint `5.6` backend `(ii)` implementation. Phase `5` Sprint `5.7` has since
closed the full imperative C++ kernel steelman, so Phase `8` Sprint `8.15` owns
the active Haskell shortfall exposed by rerunning these Q1a, Q1b, Q2, and Q5
metric rows against the fully steelmanned `(ii)` target.
Focused accepted Sprint `8.15` Haskell changes improve the local hot path but
still leave the aggregate handoff open after backend `(ii)`'s Sprint `5.7`
steelman. The latest accepted aggregate rerun still fails closed with `Verdict: Shortfall`:
Q1a backend `(ii)`/Haskell ratios `1.06x` ST and `1.27x` MT8, Q1b
`1.05x` ST and `1.11x` MT8, and Q2 `0.98x` ST and `1.11x` MT8
(`Shortfall 0.2678864950323545`). The accepted Haskell changes now include
single-constructor action transitions with the no-ply rollout variant, in
addition to the earlier compact pawn slots, direct non-terminal action sets,
packed-slot path starts, and no-wall legal-action fast path.

## Benchmark Leaves

The refactored suite provides or retains these operator-facing benchmark
families:

| Target benchmark | Required unit | Legacy/current relationship |
|------------------|---------------|-----------------------------|
| `terminal-playouts` | `playouts/s` | Implemented primitive metric; reproduces the original `MCTS_legacy` "Pure rollouts" measurement. |
| `search-iters` | `search-iters/s` | Implemented primitive metric; reproduces the original legacy `simulate(N)` timing basis and measures the live UCT core directly. |
| `rollouts` / `selfplay` | `games/s` | Existing game-level work under legacy names, including one-iteration-per-move games and configured self-play games. |

The semantic requirement is that report-card rows name the counted unit and never
compare different units as if they were interchangeable.

## Q1-Q7 Mapping

| Question | Stated question | Metric evidence required |
|----------|-----------------|--------------------------|
| Q1a | Does pure Haskell match backend (ii) on terminal playout throughput? | Backend (v) Haskell vs backend (ii) C++ on terminal playout throughput (`playouts/s`), single-threaded and 8-worker where batching applies. |
| Q1b | Does pure Haskell match backend (ii) on search-iteration throughput? | Backend (v) Haskell vs backend (ii) C++ on search-iteration throughput (`search-iters/s`), single-threaded and 8-worker where batching applies. |
| Q2 | Does pure Haskell match backend (ii) on complete self-play throughput? | Backend (v) Haskell vs backend (ii) C++ on played-game self-play throughput (`games/s`) at the report-card search budget, single-threaded and 8-worker. |
| Q3 | Do live backends `(ii)..(v)` produce identical `--rng cpp` determinism payloads? | Cross-backend determinism for `(ii)..(v)` under `--rng cpp`; compares canonical visit payloads and chosen moves, not performance rates. |
| Q4 | Does same-backend determinism hold across repeated runs? | Same-backend determinism for each backend across repeated runs with the same logical inputs. |
| Q5 | How do Haskell and backend (ii) scale from `ST` to `MT8`? | Search-iteration scaling and played-game scaling reported separately; terminal-playout scaling may be included as Q1a diagnostic evidence. Do not infer search-core scaling from `games/s` alone. |
| Q6 | Do all five backend slots pass the legacy-envelope liveness/overflow gate? | Legacy-envelope liveness/overflow across all five backend slots. This is not a throughput claim and not a visit-vector equality claim for backend (i). |
| Q7 | Do steelman backends `(ii)..(v)` satisfy semantic MCTS parity under weaker-than-bit-equality checks? | Q7 semantic-parity gate over rule-state parity, replay compatibility, search invariants, and terminal rejection for `(ii)..(v)`. This is not a benchmark metric and does not relax Q3. |

The historical Q1/Q2/Q5 rows emitted before this taxonomy are legacy
**played-game** evidence. They are useful for audit and integration diagnostics,
but current Q1/Q5 closure uses the explicit `playouts/s`, `search-iters/s`, and
`games/s` report-card rows instead of treating those historical rows as final.
After Sprint `5.7` changed backend `(ii)`, the Sprint `8.14` rows joined the audit
history. Sprint `8.15` remains active until the new-target metric evidence either
closes within tolerance or records an accepted non-parity outcome.

## Legacy C++ Basis

The original C++ harness in `MCTS_legacy/backend/core/test.cpp` timed two lower
level units before any Python/API benchmarks existed:

- "Pure rollouts": direct calls to `mcts::rollout<corridors::board>()` from the
  starting board, reported as seconds per rollout and rollouts per second.
- `simulate(N)`: MCTS iterations at the root and at each self-play move, reported
  as seconds per simulation and simulations per second.

That harness did not report complete games per second for the pure-rollout
measurement. These terms explain why the current benchmark taxonomy preserves
lower-level `playouts/s` and `search-iters/s` units. External `MCTS_legacy`
reproduction is no longer a headline report-card question; the remaining
legacy-envelope question is Q6.

## Cross-References

- [unit_testing_policy.md](./unit_testing_policy.md) — report-card gate and Q1-Q7 ownership.
- [compiler_runtime_tuning.md](./compiler_runtime_tuning.md) — backend tuning and parity tolerance.
- [determinism_contract.md](./determinism_contract.md) — Q3/Q4/Q6 correctness envelopes.
- [semantic_parity_contract.md](./semantic_parity_contract.md) — Q7 semantic-parity evidence and normalized divergence score.
- [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md) — phase status, metric-suite history, and active parity work.
