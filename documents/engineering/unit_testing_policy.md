# Unit Testing Policy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md, ../documentation_standards.md, ./README.md, ./code_quality.md
**Generated sections**: none

> **Purpose**: Describe the five Cabal test stanzas (`mcts-unit`, `mcts-integration`,
> `mcts-cross-backend`, `mcts-legacy-parity`, `mcts-haskell-style`), the
> `mcts test all` Plan/Apply command, and the pinned POC report-card workload.
> Defers to [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) for Testing
> Doctrine, Test Categories, and Test Organization.

## Doctrine Pointers

- [../../HASKELL_CLI_TOOL.md → Testing Doctrine](../../HASKELL_CLI_TOOL.md) — typed
  data over IO, pure tests preferred, interpreter-only mocking.
- [../../HASKELL_CLI_TOOL.md → Standard Testing Stack](../../HASKELL_CLI_TOOL.md) —
  `tasty`, `tasty-hunit`, `tasty-quickcheck`, `tasty-golden`, `temporary`.
- [../../HASKELL_CLI_TOOL.md → Test Categories](../../HASKELL_CLI_TOOL.md) —
  pure-logic, parser, property, golden, integration. Parser tests via
  `execParserPure`. Property invariants `decode . encode == id`, `render is
  deterministic`, `parser roundtrips`. Golden tests with sentinel placeholders for
  non-deterministic content.
- [../../HASKELL_CLI_TOOL.md → Test Organization](../../HASKELL_CLI_TOOL.md) — one
  Cabal `test-suite` per tier with `type: exitcode-stdio-1.0` and `tasty` as the
  in-stanza runner. A single `tasty` tree spanning multiple stanzas is forbidden.

## Test Stanzas

Per [../../DEVELOPMENT_PLAN/system-components.md → Test
Stanzas](../../DEVELOPMENT_PLAN/system-components.md):

| Stanza | Tier | Scope |
|--------|------|-------|
| `mcts-unit` | Pure logic | Engine invariants, parser tests via `execParserPure`, property invariants (`decode . encode == id`, `render is deterministic`, `parser roundtrips`), golden tests for `CommandSpec` output and `inspect show` rendering, transcript codec roundtrips, RNG mixer properties, per-leaf `Example` presence |
| `mcts-integration` | Subprocess | Real `mcts` binary across the FFI to every backend; same-backend determinism (Q4) at 3 seeds per backend; Q6 golden comparison for backend (i) against `test/golden/legacy/` |
| `mcts-cross-backend` | Round-robin verify | `verify` cohort under `--rng cpp` covering `(ii)..(v)`; backend (i) excluded by the `VerifyBackend` GADT |
| `mcts-legacy-parity` | Round-robin verify, legacy envelope | `verify legacy-parity` across all five backends with `max_plies = 10000` pinned and fixture seed `S_LP = 42`; pre-flight guard asserts (i) does not throw or reach `MAX_ROLLOUT_ITERS` |
| `mcts-haskell-style` | Lint | `fourmolu --mode check`, `hlint`, `cabal format` temp-file round-trip byte-equality |

Each stanza declares `type: exitcode-stdio-1.0`, `tasty` as the runner, and a
dedicated `test/<stanza>/Main.hs`. The single-tree-across-stanzas pattern is
forbidden.

## Property Invariants

Three canonical invariants per
[../../HASKELL_CLI_TOOL.md → Test Categories → Property Tests](../../HASKELL_CLI_TOOL.md),
applied across the project surface:

- `decode . encode == id` on transcript header, transcript record, full transcript
  files, `Subprocess` rendering, `CommandSpec` JSON encoding.
- `render is deterministic` on every renderer: the POC report-card summary block,
  the `inspect show` output, `commands --tree`, `commands --json`,
  `renderSubprocess`, `renderError`, `mcts lint files` output.
- `parser roundtrips` on every leaf `CommandSpec`: `render (parse argv) == argv`
  for canonical-form `argv` sequences.

## Golden Tests

Live under `test/golden/`. Non-deterministic content (wall-clock throughputs, host
identifiers, GHC build IDs) renders as sentinel placeholders in the golden file. The
`mcts-legacy-parity` and `mcts-integration` stanzas additionally consume
`test/golden/legacy/transcripts/` as the Q6 anchor produced out-of-band from
`~/MCTS_legacy/` per
[../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md → Sprint
4.5](../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md).

## `mcts test all`

The doctrine-mandatory canonical test command. Phase 7 Sprint 7.3 owns the
implementation. The plan is a typed `[Subprocess]` sequence run via `Plan / Apply`:

1. `cabal test mcts-haskell-style` (lint-first per the doctrine's `prodbox test
   lint`-style lint-first ordering)
2. `cabal test mcts-unit`
3. `cabal test mcts-integration`
4. `cabal test mcts-cross-backend`
5. `cabal test mcts-legacy-parity`
6. Pinned report-card workload (the eight `mcts bench` / `mcts verify` invocations
   from the project [../../README.md → Report-card workload](../../README.md))
7. Render the tidy summary block from the collected `ReportCard` value

`--dry-run` renders the typed plan and exits 0. `--plan-file <path>` writes the
rendered plan for out-of-band review. `--format json` emits the JSON form of the
`ReportCard` value for CI consumption.

## Report Card

The Q1–Q7 results from the pinned report-card workload. Knobs are pinned in
`cabal.project` per
[../../DEVELOPMENT_PLAN/system-components.md → POC Report-Card
Knobs](../../DEVELOPMENT_PLAN/system-components.md): `G_R = 100_000`, `G_S =
1_000`, `G_V = 50`, `G_LP = 10`, `S_BENCH = 10_000`, `S_VERIFY = 10_000`,
`S_LP_SIMS = 10_000`, `S_LP = 42`.

Summary block format pinned in the project [../../README.md → Tidy summary
block](../../README.md). Renderer is pure; wall-clock numbers render to fixed
precision (three significant figures for ratios, one decimal for throughputs in
kilogames/s); no timestamps, no locale-dependent ordering, no terminal-width-
dependent wrapping.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [code_quality.md](./code_quality.md) — `mcts-haskell-style` and lint discipline
- [determinism_contract.md](./determinism_contract.md) — Q1–Q7 framing,
  same-backend and cross-backend determinism contracts
- [cli_command_surface.md](./cli_command_surface.md) — `mcts test` subcommand
  surface
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
