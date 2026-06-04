# Unit Testing Policy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/00-overview.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md, ../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md, ../../DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md, ../documentation_standards.md, ./README.md, ./benchmark_metrics.md, ./code_quality.md, ./semantic_parity_contract.md
**Generated sections**: none

> **Purpose**: Describe the six current live Cabal test stanzas, including
> `mcts-semantic-parity` for Q7, the `mcts test all` Plan/Apply command, and
> the pinned POC report-card workload.
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
`mcts-legacy-parity`, `mcts-semantic-parity`, and `mcts test all` without pre-existing transcripts, byte
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
| `mcts-integration` | Subprocess | Same-backend determinism (Q4) at 3 seeds per backend through `MCTS.Driver`; real `mcts` binary determinism for Haskell and Rust when the Rust cdylib is present; bounded report-card divergence plus cached recompute-sidecar `inspect divergence` coverage; Rust FFI smoke-driver, live-envelope stamping, and backend-slot stale hard-fail/`--allow-stale` warning coverage; synthetic C++ and legacy-envelope coverage generated in temporary roots |
| `mcts-cross-backend` | Round-robin verify | real `mcts verify` subprocess coverage for the live FFI-capable Q3 `--rng cpp` cohort covering `(ii)..(v)`; runs serially around the process-pinned dynamic-library and C++ RNG bridge path |
| `mcts-legacy-parity` | Legacy-envelope verify | Q6 liveness/overflow coverage across all five backend slots under the legacy envelope |
| `mcts-semantic-parity` | Semantic parity | Sprint `7.11` Q7 rule-state parity, replay compatibility, search-invariant, and terminal-rejection checks for `(ii)..(v)` using generated in-memory or temporary histories |
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
in-process fallback keeps the stanza self-contained when they are absent. The
integration tier also runs real `mcts` binary same-backend determinism checks
through `MCTS.Subprocess.capture` for Haskell and Rust when the Rust cdylib is
present, a bounded measured report-card builder check, a cached recompute-sidecar
`mcts inspect divergence` subprocess check, plus bounded Rust foreign-backend
smoke games through foreign backend drivers. Live C++ FFI coverage is carried by
the cross-backend, legacy-parity, and report-card surfaces against the
Dockerfile-built C++ artefacts. The cross-backend stanza asserts
successful `verify rollouts` and `verify selfplay` subprocess output for its
focused Q3 smoke cohorts. Its `tasty` tree uses `NumThreads 1` so the Q3
subprocess cases do not concurrently exercise the same process-pinned shared
libraries or C++ RNG bridge.
Q6 runs through `mcts-legacy-parity` and remains independent of
checked-in generated-data dependencies. Sprint `7.11` adds the
`mcts-semantic-parity` stanza for Q7 without changing Q3/Q6 meanings. The
single-tree-across-stanzas
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

Legacy-envelope coverage asserts the envelope semantics that matter for compatibility
from temporary generated data: backend id, self-play workload, single-threaded
cpp RNG source, seed `S_LP = 42`, `S_LP_SIMS = 4`, `max_plies = 10000`,
one game per generated transcript, hash-addressing, and no-draw legacy semantics.
Optional external legacy audit fixtures may be regenerated through
`mcts build legacy-fixtures`, but that artifact suite is explicit and excluded
from normal `mcts test all`.

## `mcts test all`

The doctrine-mandatory canonical test command. Phase 7 Sprint 7.3 owns the
implementation. From the host, run it as
`hostbootstrap run mcts test all` (Phase 1 reopen Sprint `1.15` canonical
invocation; see
[../../DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md](../../DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md));
the first run builds the image when needed. Image construction compiles the `mcts` executable with tests and benchmarks
enabled, installs the `mcts-criterion` benchmark executable, installs all six Cabal
current test-suite executables, and produces the Dockerfile-owned foreign backend
artefacts before publishing the image. Before applying the plan,
`checkPrerequisites prerequisitesForTest` checks the pinned Haskell toolchain,
the installed image-local `mcts` binary, installed test-suite executables, the
installed `mcts-criterion` benchmark executable, logical backend coverage, and the
Dockerfile-built foreign shared libraries.
Runtime validation then consumes those image-local artefacts. Internally, the plan
is a typed `[Subprocess]` sequence run via `Plan / Apply`:

1. `mcts lint files` (rendered as an image-local `mcts lint files` subprocess;
   whitespace, final newline, `forbiddenPathRegistry`, `trackingGeneratedPaths`
   no-hand-edit) — first per the doctrine's
   [Aggregate dispatch](../../HASKELL_CLI_TOOL.md) lint-first ordering.
2. `mcts lint docs` (rendered as an image-local `mcts lint docs` subprocess;
   generated-section drift on the `GeneratedSectionRule` registry).
3. Inside the container, run the installed `mcts-haskell-style` executable
   (`cabal format` temp-file round-trip,
   `/opt/mcts-style-tools/bin/fourmolu --mode check`,
   `/opt/mcts-style-tools/bin/hlint --with-group=default --with-group=extra`
   with only `Error:` findings blocking, and the source-walker guard). The
   style tools are installed inside the container against the project GHC
   `9.12.4` (Phase 1 reopen Sprints `1.14` + `1.16`);
   ambient host tools are never used as a fallback.
4. Inside the container, run the installed `mcts-unit` executable.
5. Inside the container, run the installed `mcts-integration` executable.
6. Inside the container, run the installed `mcts-cross-backend` executable.
7. Inside the container, run the installed `mcts-legacy-parity` executable.
8. Inside the container, run the installed `mcts-semantic-parity` executable.
9. Pinned Q3/Q6 verify gates and report-card workload — Q1/Q2/Q5 are measured inside the report-card
   builder through the no-write batch runner, while Q3/Q6 are rendered as
   explicit checks through the installed image-local `mcts` binary. Q3 is the live
   visit-vector equality gate for `(ii)..(v)`; Q6 is the all-five legacy-envelope
   liveness/overflow gate. Q1/Q2 measure Haskell against backend (ii) without
   relying on a checked-in throughput file.
10. Render the tidy summary block from the collected `ReportCard` value,
   including the `visit/move` divergence matrix and normalized divergence score
   populated from the measured `G_V` verify transcripts on the live `mcts test all`
   path.

The stanza commands are execution gates over Dockerfile-prebuilt test executables
installed on the image `PATH`. A runtime `mcts test all` run should not invoke Cabal
to configure, compile, or link a test suite. If a non-build command emits Cabal
`Configuring`, `Building`, or `Linking` output after the image is already built, the
image is stale or the Dockerfile prebuild contract has regressed; rebuild the image
with `--build`.

`--dry-run` renders the typed plan and exits 0. `--plan-file <path>` writes the
rendered plan for out-of-band review. `--format json` emits the JSON form of the
`ReportCard` value for CI consumption, including explicit
`q1a_terminal_playouts_*`, `q1b_search_iters_*`, `q2_selfplay_games_*`,
unit-specific Q5 scaling fields, `raw_performance_metrics`,
`divergence_matrix` rows and the normalized divergence score, the
`apples_to_apples` block carrying the Q3/Q4/Q6/Q7 closure booleans plus the
derived `all_pass` value, and the labelled `verdict` line.

## POC Headline Questions

The target report card is required to answer seven headline project questions owned by this
policy, with Q1 rendered as Q1a/Q1b metric subquestions, using the metric units defined in
[benchmark_metrics.md](./benchmark_metrics.md). Q1/Q2 compare against the live backend
(ii) artefact that `mcts test all` consumes from the Dockerfile-built C++ PGO/BOLT
path. That path is mandatory and fail-closed: missing PGO data, missing BOLT
`.fdata`, or PGO-only/unoptimized fallback artefacts cannot satisfy the report-card
gate.

Phase 8 Sprint `8.10` closed the fail-closed profile-training requirement, and
Sprint `7.8` split the report-card rows into terminal playout throughput,
search-iteration throughput, and played-game throughput. Sprint `8.11` closed the
profile-suite review and historical parity rerun against that refactored metric
surface; Sprint `8.12` closed the active parity refresh after backend (ii)'s
compact-board correction. Sprint `8.14` made the apples-to-apples invariants
plus the non-pending measurement an exit-code gate. Phase `5` Sprint `5.7` then
closed backend `(ii)`'s full imperative-kernel steelman, and Phase `8` Sprint
`8.15` recorded the post-`5.7` Haskell-vs-`(ii)` rebaseline. Phase `5` Sprint
`5.8` further extended backend `(ii)` with bidirectional path-existence BFS,
`UctNode` cache-line padding removed, and additive C++/BOLT flag scrub; Phase
`8` Sprint `8.16` closed on 2026-05-29 with the post-`5.8` rebaseline. Sprint
`8.17` measured and rejected the `MutableByteArray#` arena migration, Sprint
`8.18` accepted `unsafeRead`/`unsafeWrite` Arena helpers and recorded arm64/amd64
cross-host evidence, and Sprint `8.19` measured and rejected the Dockerfile-level
aarch64 `-mcpu=apple-m1` unblock. The apples-to-apples invariants Q3/Q4/Q6/Q7
remain the closure gate per
[compiler_runtime_tuning.md → Performance Measurement Doctrine](./compiler_runtime_tuning.md#performance-measurement-doctrine).

1. **Q1a.** Does pure Haskell match backend (ii) on terminal playout throughput
   (`playouts/s`), single-threaded and on 8-worker batches where batching applies?
2. **Q1b.** Does pure Haskell match backend (ii) on search-iteration throughput
   (`search-iters/s`), single-threaded and on 8-worker batches where batching applies?
3. **Q2.** Does pure Haskell match backend (ii) on complete self-play throughput
   (`games/s`) at the report-card search budget, single-threaded and on 8 workers?
4. **Q3.** Do live backends (ii)..(v) produce bit-for-bit identical
   determinism payloads under `--rng cpp` (round-robin verify on both rollouts and
   self-play)?
5. **Q4.** Does same-backend determinism hold across runs (same backend, same
   seed, same logical game inputs ⇒ identical determinism payloads) for every
   backend?
6. **Q5.** How do the Haskell and live C++ (ii) anchors scale from
   `--threading single` to `--threading multi --workers 8`? Search-iteration
   scaling and played-game scaling must be reported separately; terminal playout
   scaling is diagnostic for Q1a.
7. **Q6.** Do all five backend slots pass the legacy-envelope liveness/overflow gate?
8. **Q7.** Do steelman backends `(ii)..(v)` satisfy semantic MCTS parity under
   weaker-than-bit-equality checks? Sprint `7.11` owns this row; Q7
   passes only on rule-state parity, replay compatibility, search invariants, and
   terminal-rejection checks. The normalized divergence score is supporting
   evidence, not a tolerance that can rescue a failed invariant.

**Backend (i) basis caveat.** Backend (i) `cpp-legacy` is a verbatim port and
inherits the legacy's lack of a game-level ply cap (see
[determinism_contract.md → Ply-Cap Draw Rule](./determinism_contract.md#ply-cap-draw-rule)).
Its played-game throughput numbers are therefore **not on the same basis** as backends
(ii)–(v) under any `max_plies` other than `MAX_ROLLOUT_ITERS = 10000`: (i)'s
games run to a positional win and are on average longer than the ply-capped
games of (ii)–(v), so directly comparing `games/s` misreads the engine
budget. `mcts test all` does not use backend (i) for Q1/Q2 throughput rows; Q6 is
legacy-envelope liveness evidence and the load-bearing Q1 / Q2 comparison is Haskell (v)
versus C++ (ii), where both backends terminate identically; backend (i) is
exercised through legacy-parity envelope evidence (Q6), where
the ply cap is pinned to `10000` and the gate checks
liveness/overflow rather than throughput or visit-count equality. See
[compiler_runtime_tuning.md](./compiler_runtime_tuning.md) for the
backend (i) build flags that make the verbatim port non-comparable on raw
throughput.

## Report Card

The current Q1-Q7 results come from the pinned report-card workload and the
`mcts-semantic-parity` stanza. Live executable
constants are implemented in `MCTS.CLI.Test` and mirrored in `cabal.project`
comments per
[../../DEVELOPMENT_PLAN/system-components.md → POC Report-Card
Knobs](../../DEVELOPMENT_PLAN/system-components.md): `N_PRIM = 20_000`,
`P_MAX = 60`, `G_R = 1_000`, `G_S = 4`, `G_V = 4`, `G_LP = 2`,
`S_BENCH = 500`, `S_VERIFY = 500`, `S_LP_SIMS = 4`, `S_LP = 42`.

`mcts test all` requires the Dockerfile-built live foreign artefacts and the
Dockerfile-prebuilt Cabal test executables before executing the test stanzas and final
report card. The current gate proves those artefacts are present, fail-closed, and
produced from the bounded metric-suite Dockerfile-time PGO/BOLT training suite. The
measured report-card builder uses the production
monotonic clock for live Haskell primitive throughput through the direct benchmark
runners and for live played-game throughput through `runBatchNoWriteDispatch`. It
measures raw Q1a/Q1b/Q2 rates for every backend slot, compares the Haskell rows
against live backend (ii) where available, and renders `Evidence pending` only in
deterministic semantic unit values, not in a live full run. Q6 is the all-five
legacy-envelope gate, while Q3 carries the visit-count equality assertion for
`(ii)..(v)`. Rust raw-performance rows are context rather than Q1/Q2 verdict
inputs after Phase `6` Sprint `6.8` aligns its hot path with `(iii)` and `(v)`.
The Q7 row is governed by
[semantic_parity_contract.md](./semantic_parity_contract.md).

The text renderer is an aligned-table contract:

1. Brief term definitions (`ST`, `MT8`, `Q1a`, `Q1b`, `Q2`, `Q5`,
   `visit/move`, and normalized divergence score).
2. Raw performance metrics for each backend slot and metric family.
3. The question summary table, with every Q1a/Q1b/Q2/Q3/Q4/Q5/Q6/Q7 question stated.
4. The divergence matrix table.
5. A final question-answer table that explicitly answers Q1a-Q7 from the observed
   ratios, scaling values, normalized divergence score, and gate outcomes.

The JSON renderer exposes the same observed rates under
`raw_performance_metrics` and keeps the existing unit-specific Q1/Q2/Q5 fields.

The 2026-05-27 Sprint `8.14` aggregate run measured the corrected-backend
parity surface with `Verdict: Within parity band` (legacy label
`Within tolerance`): Q1a terminal playout ST `0.72x`, Q1a MT8 `0.85x`, Q1b
search-iteration ST `0.67x`, Q1b MT8 `0.67x`, Q2 played-game ST `0.59x`, Q2 MT8
`0.68x`, Haskell search-iteration scaling `7.32x`, C++ (ii) search-iteration
scaling `7.32x`, Haskell self-play scaling `3.42x`, C++ (ii) self-play scaling
`3.92x`, Q3/Q4/Q6/Q7 PASS, all Cabal stanzas PASS, and zero live-cohort
divergence. Under the reframed
[compiler_runtime_tuning.md → Performance Measurement Doctrine](./compiler_runtime_tuning.md#performance-measurement-doctrine),
the verdict line is informational and `mcts test all` closure is gated by the
apples-to-apples invariants Q3/Q4/Q6/Q7 plus a non-pending measurement.

This evidence remains valid for the Sprint `5.6` backend `(ii)` artefact. It is
historical after Phase `5` Sprint `5.7` because the backend `(ii)` kernel and
PGO/BOLT profile suite changed; the accepted Sprint `8.15` aggregate rerun
recorded `Verdict: Trails parity band by 26.8%` (legacy label
`Shortfall 0.2678864950323545`): Q1a backend `(ii)`/Haskell ratios `1.06x` ST
and `1.27x` MT8, Q1b `1.05x` ST and `1.11x` MT8, and Q2 `0.98x` ST and
`1.11x` MT8. That measurement is itself historical against the pre-Sprint
`5.8` `(ii)` artefact, because Sprint `5.8` landed the bidirectional
path-existence BFS, the `UctNode` cache-line padding drop, and the additive
C++/BOLT flag scrub. Phase `8` Sprint `8.16` closed on 2026-05-29 with the
post-`5.8` measurement: Q1a backend
`(ii)`/Haskell ratios `1.51x` ST / `1.50x` MT8, Q1b `1.53x` ST / `1.56x`
MT8, Q2 `1.41x` ST / `1.57x` MT8, Q5 scaling Haskell search `7.16x` vs
C++ `(ii)` search `7.31x`, Haskell self-play `3.28x` vs C++ `(ii)`
self-play `3.66x`; `Verdict: Trails parity band by 57.1%`; Q3/Q4/Q6/Q7
PASS and `normalized_divergence_score=0.0000`. Later accepted evidence is the
Sprint `8.18` arm64/amd64 cross-host measurement (`85.6%` / `29.5%`) plus the
post-`4.7` unified-clang aggregate (`69.1%`), with Sprint `8.19` recorded as
measured but rejected and reverted.
The 2026-05-24 Sprint `8.11` aggregate run remains historical refactored-metric
evidence for the older backend (ii) artefact: Q1a terminal playout ST `0.07x`,
Q1a MT8 `0.39x`, Q1b search-iteration ST `0.06x`, Q1b MT8 `0.40x`, Q2
played-game ST `0.05x`, Q2 MT8 `0.17x`, Haskell search-iteration scaling `1.02x`,
C++ (ii) search-iteration scaling `7.36x`, Haskell self-play scaling `0.97x`,
C++ (ii) self-play scaling `3.72x`, Q6 PASS, and zero live-cohort divergence.
The 2026-05-25 Sprint `7.9` aggregate revalidation kept the six-question surface
within tolerance after the external legacy-reproduction headline row was removed:
Q1a ST `0.06x`, Q1a MT8 `0.38x`, Q1b ST `0.05x`, Q1b MT8 `0.36x`,
Q2 ST `0.05x`, Q2 MT8 `0.17x`, Haskell search-iteration scaling `0.97x`,
C++ (ii) search-iteration scaling `7.47x`, Haskell self-play scaling `1.03x`,
C++ (ii) self-play scaling `3.69x`, Q6 PASS, and zero live-cohort divergence.

Summary block format is pinned here. Renderer is pure; wall-clock numbers render to fixed
precision (two decimals for text ratios, one decimal for text throughputs);
no timestamps, no locale-dependent ordering, no terminal-width-
dependent wrapping.

`mcts-unit` asserts the rendered tidy summary block semantically with sentinel
placeholders substituted for live wall-clock numbers and host arch. The tests
cover table order, labels, ratio fields, raw metric fields, Q1–Q7 question
presence, the final observed-metric Q1a-Q7 answer table, and the `visit/move`
divergence matrix without reading a snapshot. Sprint `7.11` adds a constructed
non-zero divergence matrix test proving that the normalized divergence score is
derived from the maximum visit or move disagreement cell and that threshold text is
absent.
Paired JSON tests assert the evidence-pending Q1/Q2/Q5 fields,
`raw_performance_metrics`, `divergence_matrix`, the normalized divergence
score, and required keys directly so
schema drift fails in `mcts-unit`. The report-card text renderer remains the
user-facing rendering reference, but it is not copied into a checked-in generated fixture.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [code_quality.md](./code_quality.md) — `mcts-haskell-style` and lint discipline
- [benchmark_metrics.md](./benchmark_metrics.md) — benchmark unit taxonomy and Q1-Q7
  metric mapping
- [determinism_contract.md](./determinism_contract.md) — same-backend and
  cross-backend determinism contracts
- [semantic_parity_contract.md](./semantic_parity_contract.md) — Q7 semantic-parity contract
- [cli_command_surface.md](./cli_command_surface.md) — `mcts test` subcommand
  surface
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
