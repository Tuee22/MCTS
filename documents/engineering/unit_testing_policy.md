# Unit Testing Policy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md, ../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md, ../documentation_standards.md, ./README.md, ./code_quality.md
**Generated sections**: none

> **Purpose**: Describe the five live Cabal test stanzas (`mcts-unit`,
> `mcts-integration`, `mcts-cross-backend`, `mcts-legacy-parity`,
> `mcts-haskell-style`), the
> `mcts test all` Plan/Apply command, and the pinned POC report-card workload.
> Defers to [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) for Testing
> Doctrine, Test Categories, and Test Organization.

## Doctrine Pointers

- [../../HASKELL_CLI_TOOL.md → Testing Doctrine](../../HASKELL_CLI_TOOL.md) — typed
  data over IO, pure tests preferred, interpreter-only mocking.
- [../../HASKELL_CLI_TOOL.md → Standard Testing Stack](../../HASKELL_CLI_TOOL.md) —
  `tasty`, `tasty-hunit`, `tasty-quickcheck`, and `temporary` in this repository;
  checked-in golden files are intentionally excluded by the project-specific data
  doctrine below.
- [../../HASKELL_CLI_TOOL.md → Test Categories](../../HASKELL_CLI_TOOL.md) —
  pure-logic, parser, property, golden, integration. Parser tests via
  `execParserPure`. Property invariants `decode . encode == id`, `render is
  deterministic`, `parser roundtrips`.
- [../../HASKELL_CLI_TOOL.md → Test Organization](../../HASKELL_CLI_TOOL.md) — one
  Cabal `test-suite` per tier with `type: exitcode-stdio-1.0` and `tasty` as the
  in-stanza runner. A single `tasty` tree spanning multiple stanzas is forbidden.

## Repository Data Doctrine

This project applies a stricter rule than the generic CLI testing doctrine:
normal validation must not require generated data checked into git. A clean clone
must be able to run `mcts-unit`, `mcts-integration`, `mcts-cross-backend`,
`mcts-legacy-parity`, and `mcts test all` without pre-existing transcripts, byte
snapshots, generated JSON schemas, throughput anchors, or other generated validation
files.

Tests may generate data during the test run, but only in memory or under
temporary directories owned by the test. Runtime/operator caches such as
`.mcts-cache/` remain ignored local state. Optional audit evidence may be recorded in
docs or stored in explicit external/ignored artifact roots, but it is not a normal
`mcts test all` input.

The repository does not depend on `tasty-golden` or checked-in generated golden
files. Renderer, codec, schema, and backend-equivalence evidence checks use semantic
assertions, property tests, in-memory values, or temporary directories owned by
the test process.

## Test Stanzas

Per [../../DEVELOPMENT_PLAN/system-components.md → Test
Stanzas](../../DEVELOPMENT_PLAN/system-components.md):

| Stanza | Tier | Scope |
|--------|------|-------|
| `mcts-unit` | Pure logic | Engine invariants, parser tests via `execParserPure`, property invariants (`decode . encode == id`, `render is deterministic`, `parser roundtrips`), semantic renderer tests for `CommandSpec`, report-card, TUI, and `inspect show` output, transcript codec roundtrips, RNG mixer properties, per-leaf `Example` presence |
| `mcts-integration` | Subprocess | Real `mcts` binary across the FFI to every live backend; same-backend determinism (Q4) at 3 seeds per backend; bounded report-card divergence plus cached recompute-sidecar `inspect divergence` coverage; foreign-backend FFI smoke-driver, live-envelope stamping, and backend-slot stale hard-fail/`--allow-stale` warning coverage when shared libraries are present; synthetic legacy-envelope coverage generated in temporary roots |
| `mcts-cross-backend` | Round-robin verify | real `mcts verify` subprocess coverage for the live FFI-capable Q3 `--rng cpp` cohort covering `(ii)..(v)`; runs serially around the process-pinned dynamic-library and C++ RNG bridge path |
| `mcts-legacy-parity` | Legacy-envelope verify | Q7 liveness/overflow coverage across all five backend slots under the legacy envelope |
| `mcts-haskell-style` | Lint | `cabal format` temp-file round-trip byte-equality, pinned style-tool `fourmolu --mode check` and `hlint`, plus the source-walker guard for tabs and the conservative forbidden-symbol subset |

Each stanza declares `type: exitcode-stdio-1.0`, the `tasty` dependencies, and a
dedicated `test/<stanza>/Main.hs` with its own `tasty` tree. The `mcts-unit`
runner is split into named `tasty-hunit` cases by CLI/parser, transcripts/cache,
engine/RNG, envelopes/sidecars, plans/subprocesses, and renderers/TUI dispatch;
the renderers/TUI group asserts the shared board/status layout semantically and
asserts the `mcts play :save` path by writing and decoding a hand-play
transcript in a temporary cache. It also advances an AI turn with a selected
foreign backend, exercising the live FFI path when the matching cdylib exists
and the in-process fallback otherwise, and asserts that the transcript record
keeps the returned visit vector. The replay overlay case also covers originator
cache-miss preparation:
`prepareReplayOverlays` recomputes a missing `.eq`, writes one sidecar, and then
loads the same overlay on a cache hit without recomputing. The envelope case also
covers live C ABI envelope conversion plus hard-fail vs `--allow-stale` behavior
for `compiler_version` and `shared_rng_build_id` mismatches, plus structured JSON
`warning_details` for downgraded stale warnings. `tasty-quickcheck` now covers
transcript roundtrips. The current Phase 7 verification baseline uses
real `mcts verify` subprocesses for Q3, so live foreign shared libraries are exercised
when present by the same operator surface used outside the test runner, while the
in-process fallback keeps the stanza self-contained when they are absent. The integration tier also runs real `mcts` binary same-backend determinism checks through
`MCTS.Subprocess.capture` for Haskell and every built live foreign backend, a bounded
measured report-card builder check, a cached recompute-sidecar
`mcts inspect divergence` subprocess check, plus bounded foreign-backend smoke games through
foreign backend drivers when the container-built shared libraries are present. The cross-backend stanza asserts
successful `verify rollouts` and `verify selfplay` subprocess output for its
focused Q3 smoke cohorts. Its `tasty` tree uses `NumThreads 1` so the Q3
subprocess cases do not concurrently exercise the same process-pinned shared
libraries or C++ RNG bridge.
Q7 runs through `mcts-legacy-parity` and remains independent of
checked-in generated-data dependencies. The single-tree-across-stanzas
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

## Generated Validation Data

No generated validation data lives under `test/golden/` as a normal repository
input. Renderer output is tested by constructing typed values with sentinel
wall-clock fields and asserting row labels, field order, placeholder placement,
JSON keys, and parseable structure directly. Codec coverage uses property tests,
roundtrip checks, and small hand-authored literals where needed; generated
transcript bytes are created in temporary directories during the test run.

Legacy Q6/Q7 coverage asserts the envelope semantics that matter for compatibility
from temporary generated data: backend id, self-play workload, single-threaded
cpp RNG source, seed `S_LP = 42`, `S_LP_SIMS = 10000`, `max_plies = 10000`,
one game per generated transcript, hash-addressing, and no-draw legacy semantics.
Optional external legacy evidence may be regenerated through
`mcts build legacy-fixtures`, but that artifact suite is explicit and excluded
from normal `mcts test all`.

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
3. Inside the container, `cabal build all` warning-clean under the pinned
   toolchain.
4. Build the live foreign backend artefacts through the supported build harness:
   `mcts build cpp-legacy`, `mcts build cpp-imperative`,
   `mcts build cpp-functional`, and `mcts build rust`.
5. Inside the container, `cabal test mcts-haskell-style` (`cabal format`
   temp-file round-trip,
   `/opt/mcts-style-tools/bin/fourmolu --mode check`,
   `/opt/mcts-style-tools/bin/hlint --with-group=default --with-group=extra`
   with only `Error:` findings blocking, and the source-walker guard). The
   style tools are installed inside the container with the separate pinned
   formatter-tools GHC `9.12.4`; ambient host tools are never used as a fallback.
6. Inside the container, `cabal test mcts-unit`.
7. Inside the container, `cabal test mcts-integration`.
8. Inside the container, `cabal test mcts-cross-backend`.
9. Inside the container, `cabal test mcts-legacy-parity`.
10. Pinned report-card workload — Q1/Q2/Q5 are measured inside the report-card
   builder through the no-write batch runner, while Q3/Q7 are rendered as
   explicit checks through `cabal exec mcts -- ...` so the
   command does not depend on a separate `mcts` executable on `PATH`. Q3 is the
   live visit-vector equality gate for `(ii)..(v)`; Q7 is the all-five
   legacy-envelope liveness/overflow gate. Q1/Q2 measure Haskell against backend (ii)
   without relying on a checked-in throughput file.
11. Render the tidy summary block from the collected `ReportCard` value,
    including the `visit/move` divergence matrix populated from the measured
    `G_V` verify transcripts on the live `mcts test all` path.

`--dry-run` renders the typed plan and exits 0. `--plan-file <path>` writes the
rendered plan for out-of-band review. `--format json` emits the JSON form of the
`ReportCard` value for CI consumption, including the Q1/Q2/Q5 evidence fields
and `divergence_matrix` rows.

## POC Headline Questions

The report card answers seven questions, verbatim from
[../../README.md → POC headline questions](../../README.md):

1. **Q1.** Does pure Haskell match maximally-optimised C++ (backend (ii)) on
   benchmark (a) random rollouts, single-threaded and on 8 workers?
2. **Q2.** Does pure Haskell match backend (ii) on benchmark (b) self-play,
   single-threaded and on 8 workers?
3. **Q3.** Do live backends (ii)..(v) produce bit-for-bit identical
   determinism payloads under `--rng cpp` (round-robin verify on both rollouts and
   self-play)?
4. **Q4.** Does same-backend determinism hold across runs (same backend, same
   seed, same logical game inputs ⇒ identical determinism payloads) for every
   backend?
5. **Q5.** How do the Haskell and live C++ (ii) anchors scale from
   `--threading single` to `--threading multi --workers 8`? The text and JSON
   summaries expose those two anchor rows.
6. **Q6.** Does the verbatim port (i) faithfully reproduce `MCTS_legacy` on
   benchmark (b)?
7. **Q7.** Do all five backend slots pass the legacy-envelope liveness/overflow gate?

**Backend (i) basis caveat.** Backend (i) `cpp-legacy` is a verbatim port and
inherits the legacy's lack of a game-level ply cap (see
[../../README.md → Draw rule](../../README.md) and
[determinism_contract.md](./determinism_contract.md)). Its Q1 / Q2 / Q5
throughput numbers are therefore **not on the same basis** as backends
(ii)–(v) under any `max_plies` other than `MAX_ROLLOUT_ITERS = 10000`: (i)'s
games run to a positional win and are on average longer than the ply-capped
games of (ii)–(v), so directly comparing games/sec misreads the engine
budget. `mcts test all` does not use backend (i) for Q1/Q2 throughput rows; Q6/Q7 are
legacy-compatibility evidence and the load-bearing Q1 / Q2 comparison is Haskell (v)
versus C++ (ii), where both backends terminate identically; backend (i) is
otherwise exercised through legacy-parity envelope evidence (Q7), where
the ply cap is pinned to `10000` and the gate checks
liveness/overflow rather than throughput or visit-count equality. See
[compiler_runtime_tuning.md](./compiler_runtime_tuning.md) for the
backend (i) build flags that make the verbatim port non-comparable on raw
throughput.

## Report Card

The Q1–Q7 results from the pinned report-card workload. Live executable
constants are implemented in `MCTS.CLI.Test` and mirrored in `cabal.project`
comments per
[../../DEVELOPMENT_PLAN/system-components.md → POC Report-Card
Knobs](../../DEVELOPMENT_PLAN/system-components.md): `G_R = 1_000`, `G_S =
4`, `G_V = 4`, `G_LP = 2`, `S_BENCH = 500`, `S_VERIFY = 500`,
`S_LP_SIMS = 10_000`, `S_LP = 42`.

`mcts test all` builds the live foreign artefacts before running the Cabal stanzas and
final report card. The measured report-card builder uses the production monotonic clock
for live Haskell Q1/Q2/Q5 throughput through `runBatchNoWriteDispatch`, compares those
rates against live backend (ii) where available, and renders `Evidence pending` only in
deterministic semantic unit values, not in a live full run. Q7 is the all-five
legacy-envelope gate, while Q3 carries the visit-count equality assertion for `(ii)..(v)`.

Summary block format pinned in the project [../../README.md → Tidy summary
block](../../README.md). Renderer is pure; wall-clock numbers render to fixed
precision (two decimals for text ratios, one decimal for text throughputs);
no timestamps, no locale-dependent ordering, no terminal-width-
dependent wrapping.

`mcts-unit` asserts the rendered tidy summary block semantically with sentinel
placeholders substituted for live wall-clock numbers and host arch. The tests
cover row order, labels, ratio fields, Q1–Q7 presence, and the
`visit/move` divergence matrix without reading a snapshot. Paired JSON tests
assert the evidence-pending Q1/Q2/Q5 fields, `divergence_matrix`, and required
keys directly so schema drift fails in `mcts-unit`. The README's tidy summary
remains the user-facing rendering reference, but it is not copied into a
checked-in generated fixture.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [code_quality.md](./code_quality.md) — `mcts-haskell-style` and lint discipline
- [determinism_contract.md](./determinism_contract.md) — Q1–Q7 framing,
  same-backend and cross-backend determinism contracts
- [cli_command_surface.md](./cli_command_surface.md) — `mcts test` subcommand
  surface
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
