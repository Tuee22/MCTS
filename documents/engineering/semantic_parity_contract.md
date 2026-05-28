# Semantic Parity Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/00-overview.md, ../../DEVELOPMENT_PLAN/system-components.md, ../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md, ../documentation_standards.md, ./README.md, ./backend_ffi_contract.md, ./benchmark_metrics.md, ./cli_command_surface.md, ./compiler_runtime_tuning.md, ./determinism_contract.md, ./unit_testing_policy.md
**Generated sections**: none

> **Purpose**: Define Q7 semantic MCTS parity for steelman backends `(ii)..(v)`
> as a weaker-than-bit-equality correctness gate. Q7 is one of the
> apples-to-apples invariants that gate `mcts test all` closure per
> [compiler_runtime_tuning.md → Performance Measurement Doctrine](./compiler_runtime_tuning.md#performance-measurement-doctrine);
> a Q7 failure means the comparison itself is broken, which is distinct from
> a Q1/Q2 measurement saying Haskell trails C++ on throughput.

## Scope

Q7 answers this report-card question:

> **Q7.** Do steelman backends `(ii)..(v)` implement the same game-rule and MCTS
> semantics under checks that are weaker than bit-for-bit transcript identity?

Q7 is separate from Q3. Q3 remains the strict `--rng cpp` visit-vector and
chosen-move identity gate for `(ii)..(v)`; any Q3 `VerifyMismatch` is still a
hard failure. Q7 exists for the cases where exact play is not the right claim:
native RNG, substrate differences, or future implementation changes that preserve
the game and search contract without producing byte-identical traces.

Backend `(i)` is outside Q7. It stays covered by Q6 because it is a verbatim legacy
port with intentionally different terminal-state and search-tree semantics.

## Evidence Families

Q7 is implemented as the `mcts-semantic-parity` Cabal stanza owned by Phase 7
Sprint `7.11`. The stanza uses generated in-memory or temporary data only; no
checked-in transcript corpus or golden file is allowed.

The hard-gated Q7 evidence families are:

| Family | Assertion |
|--------|-----------|
| Rule-state parity | For a bounded corpus of reachable histories, `(ii)..(v)` agree on terminal state, legal action acceptance, and canonical action IDs. |
| Replay compatibility | A legal move history produced by any steelman backend remains legal when replayed through every other steelman backend and reaches the same deterministic outcome. |
| Search invariants | For every searched position, the chosen move is legal, visit actions are legal and unique, positive visit counts are bounded by the simulation budget, and the chosen action is one of the max-visit candidates. |
| Terminal rejection | Terminal boards reject search rather than emitting a new move. |

The implementation uses the existing C ABI surface:
`new_board`, `free_board`, `is_terminal`, `apply_action`, and `search_move`.
No new FFI symbol is required for Sprint `7.11`; if later work adds a direct
`legal_actions` ABI, this contract should be updated in the same change.

## Divergence Score

The report card does not render empirical divergence thresholds. The
normalized divergence statistic is:

```text
normalized_divergence_score =
  max(all visit_disagreement_rate cells,
      all move_disagreement_rate cells)
```

The score is a unitless value in `[0, 1]`. `0.0000` means no observed visit-table
or chosen-move disagreement anywhere in the measured matrix. The existing
per-backend-pair matrix remains useful explanatory evidence, but the headline
answer reports the single normalized score rather than threshold pairs.

Q3 still hard-fails on any non-zero `--rng cpp` disagreement before the report-card
answer is accepted. The normalized score is not a tolerance; it is a compact
summary of the observed divergence surface.

## Renderer Coverage

Sprint `7.11` adds a semantic renderer test that constructs a small non-zero
divergence matrix and asserts:

- the table labels make clear that each cell is `visit/move`;
- the normalized score is the maximum of every visit and move disagreement rate in
  the matrix;
- a zero matrix renders `normalized_divergence_score = 0.0000`;
- old native/cross-build threshold text is absent from the report-card output.

This test lives in `mcts-unit`; the live Q7 semantic-parity checks belong in
the `mcts-semantic-parity` stanza.

## Cross-References

- [determinism_contract.md](./determinism_contract.md) — Q3/Q4/Q6 exactness and
  divergence metric definitions.
- [unit_testing_policy.md](./unit_testing_policy.md) — test-stanza and report-card
  ownership.
- [backend_ffi_contract.md](./backend_ffi_contract.md) — C ABI consumed by the Q7
  semantic checks.
- [benchmark_metrics.md](./benchmark_metrics.md) — Q1-Q7 report-card mapping.
- [compiler_runtime_tuning.md](./compiler_runtime_tuning.md) — Performance
  Measurement Doctrine (Q-classification, closure gate, verdict-line labelling
  threshold).
- [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md) — sprint
  status and closure ownership.
