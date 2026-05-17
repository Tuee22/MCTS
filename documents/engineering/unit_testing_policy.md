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
| `mcts-integration` | Subprocess | Real `mcts` binary across the FFI to every backend; same-backend determinism (Q4) at 3 seeds per backend; foreign-backend FFI smoke-driver and live-envelope coverage when shared libraries are present; Q6 golden comparison for backend (i) against `test/golden/legacy/` |
| `mcts-cross-backend` | Round-robin verify | `verify` cohort under `--rng cpp` covering `(ii)..(v)`; backend (i) excluded by the `VerifyBackend` GADT |
| `mcts-legacy-parity` | Round-robin verify, legacy envelope | `verify legacy-parity` across all five backends with `max_plies = 10000` pinned and fixture seed `S_LP = 42`; pre-flight guard asserts (i) does not throw or reach `MAX_ROLLOUT_ITERS` |
| `mcts-haskell-style` | Lint | `cabal format` temp-file round-trip byte-equality, pinned style-tool `fourmolu --mode check` and `hlint`, plus the bootstrap source walker for tabs and the conservative forbidden-symbol subset |

Each stanza declares `type: exitcode-stdio-1.0`, the `tasty` dependencies, and a
dedicated `test/<stanza>/Main.hs` with its own `tasty` tree. The current Phase 7
baseline still uses logical backend dispatch for the foreign-named backends in the
integration, cross-backend, and legacy-parity tiers; real FFI-backed Q4/Q6/Q7
coverage remains active plan work. The integration tier additionally runs bounded
foreign-backend smoke games through `src/MCTS/Driver/{CppLegacy,CppImperative,CppFunctional,Rust}.hs`
when the container-built shared libraries are present. The single-tree-across-stanzas
pattern is forbidden.

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
implementation. From the host, run it as
`docker compose run --rm mcts mcts test all`; the first run builds the image when
needed. Internally, the plan is a typed `[Subprocess]` sequence run via
`Plan / Apply`:

1. `mcts lint files` (rendered as `cabal exec mcts -- lint files` in the current
   apply plan; whitespace, final newline, `forbiddenPathRegistry`,
   `trackingGeneratedPaths` no-hand-edit) — first per the doctrine's
   [Aggregate dispatch](../../HASKELL_CLI_TOOL.md) lint-first ordering.
2. `mcts lint docs` (rendered as `cabal exec mcts -- lint docs`; generated-section
   drift on the `GeneratedSectionRule` registry).
3. `cabal build all` warning-clean under the pinned toolchain.
4. `cabal test mcts-haskell-style` (`cabal format` temp-file round-trip,
   `/opt/mcts-style-tools/bin/fourmolu --mode check`,
   `/opt/mcts-style-tools/bin/hlint --with-group=default --with-group=extra`
   with only `Error:` findings blocking, and the bootstrap source walker). The
   style tools are installed inside the container with the separate pinned
   formatter-tools GHC `9.12.4`; ambient host tools are never used as a fallback.
5. `cabal test mcts-unit`.
6. `cabal test mcts-integration`.
7. `cabal test mcts-cross-backend`.
8. `cabal test mcts-legacy-parity`.
9. Pinned report-card workload — the seven `mcts bench` / `mcts verify`
   invocations from the project, rendered through `cabal exec mcts -- ...` in the
   apply plan so the command does not depend on a separate `mcts` executable on `PATH`,
   [../../README.md → Report-card workload](../../README.md) lines 223–246,
   enumerated verbatim by
   [../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md →
   Sprint 7.3](../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md).
10. Render the tidy summary block from the collected `ReportCard` value.

`--dry-run` renders the typed plan and exits 0. `--plan-file <path>` writes the
rendered plan for out-of-band review. `--format json` emits the JSON form of the
`ReportCard` value for CI consumption.

## POC Headline Questions

The report card answers seven questions, verbatim from
[../../README.md → POC headline questions](../../README.md):

1. **Q1.** Does pure Haskell match maximally-optimised C++ (backend (ii)) on
   benchmark (a) random rollouts, single-threaded and on 8 workers?
2. **Q2.** Does pure Haskell match backend (ii) on benchmark (b) self-play,
   single-threaded and on 8 workers?
3. **Q3.** Do backends (ii), (iii), (iv), (v) produce bit-for-bit identical
   determinism payloads under `--rng cpp` (round-robin verify on both rollouts and
   self-play)?
4. **Q4.** Does same-backend determinism hold across runs (same backend, same
   seed, same logical game inputs ⇒ identical determinism payloads) for every
   backend?
5. **Q5.** How does each backend scale from `--threading single` to
   `--threading multi --workers 8`? The text summary highlights Haskell and
   C++ (ii) as the two anchors; the full per-backend scaling table is
   available via `mcts test all --format json`.
6. **Q6.** Does the verbatim port (i) faithfully reproduce `MCTS_legacy` on
   benchmark (b)?
7. **Q7.** Do all five backends agree round-robin under the legacy-parity
   envelope (`max_plies = 10000`, fixture seed where (i) does not throw)?

**Backend (i) basis caveat.** Backend (i) `cpp-legacy` is a verbatim port and
inherits the legacy's lack of a game-level ply cap (see
[../../README.md → Draw rule](../../README.md) and
[determinism_contract.md](./determinism_contract.md)). Its Q1 / Q2 / Q5
throughput numbers are therefore **not on the same basis** as backends
(ii)–(v) under any `max_plies` other than `MAX_ROLLOUT_ITERS = 10000`: (i)'s
games run to a positional win and are on average longer than the ply-capped
games of (ii)–(v), so directly comparing games/sec misreads the engine
budget. The report-card renderer appends the `backendBasisFootnotes`
warning from [../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md
→ Sprint 7.3](../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md)
to any Q1 / Q2 / Q5 row produced for backend (i) under
`max_plies != 10000`. The load-bearing Q1 / Q2 comparison is Haskell (v)
versus C++ (ii), where both backends terminate identically; backend (i) is
otherwise compared on equal footing only under the legacy-parity envelope
(Q7), where the ply cap is pinned to `10000` and all five backends
terminate identically. See
[compiler_runtime_tuning.md](./compiler_runtime_tuning.md) for the
backend (i) build flags that make the verbatim port non-comparable on raw
throughput.

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

A `mcts-unit` golden test asserts byte-equality between the rendered tidy
summary block (with sentinel placeholders substituted for the live wall-clock
numbers and host arch) and the literal layout pinned at
[../../README.md → Tidy summary block](../../README.md) lines 255–273. Drift
from the README layout fails the golden — the README's tidy summary is the
source of truth for the renderer.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [code_quality.md](./code_quality.md) — `mcts-haskell-style` and lint discipline
- [determinism_contract.md](./determinism_contract.md) — Q1–Q7 framing,
  same-backend and cross-backend determinism contracts
- [cli_command_surface.md](./cli_command_surface.md) — `mcts test` subcommand
  surface
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
