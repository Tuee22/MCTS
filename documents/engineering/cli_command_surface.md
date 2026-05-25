# CLI Command Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-2-transcript-codec-and-determinism.md, ../../DEVELOPMENT_PLAN/phase-3-haskell-engine.md, ../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md, ../../DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md, ../../DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md, ../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md, ../documentation_standards.md, ./README.md, ./benchmark_metrics.md
**Generated sections**: command-matrix

> **Purpose**: Operator-facing `mcts` command matrix. Defers to
> [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) for Command Topology,
> `CommandSpec`, and Progressive Introspection.

## Doctrine Pointers

This document covers project-specific elaborations only. For the patterns themselves,
see:

- [../../HASKELL_CLI_TOOL.md → Command Topology](../../HASKELL_CLI_TOOL.md) — commands
  as ordinary Haskell ADTs.
- [../../HASKELL_CLI_TOOL.md → Automatically Generated
  Documentation](../../HASKELL_CLI_TOOL.md) — `CommandSpec` + `OptionSpec` record
  shape, per-leaf `Example` entries, command topology rendered from the spec with
  explicit semantic leaf option parsers.
- [../../HASKELL_CLI_TOOL.md → Progressive Introspection](../../HASKELL_CLI_TOOL.md)
  — `commands [--tree|--json]`, focused `help <subcommand>`.
- [../../HASKELL_CLI_TOOL.md → Generated Artifacts](../../HASKELL_CLI_TOOL.md) —
  marker discipline, paired check/write, `forbiddenPathRegistry`,
  `GeneratedSectionRule`, `trackingGeneratedPaths`.
- [../../HASKELL_CLI_TOOL.md → Output Rules](../../HASKELL_CLI_TOOL.md) —
  `--format json|table|plain`, `--color auto|always|never`, `--no-color`,
  stdout-vs-stderr split.
- [../../HASKELL_CLI_TOOL.md → Error Handling](../../HASKELL_CLI_TOOL.md) — single
  `AppError` ADT, canonical `renderError :: AppError -> Text` boundary
  (`MCTS.CLI.Output` currently exposes a String adapter for command runners).

## Command Matrix

The full operator-facing surface. Generated artefacts under
`documents/cli/commands.md`, the manpages under `share/man/man1/`, and the shell
completion scripts under `share/completion/` all derive from the same `CommandSpec`
registry that drives this table. Phase-owned per
[../../DEVELOPMENT_PLAN/system-components.md](../../DEVELOPMENT_PLAN/system-components.md).
From the host, run any listed logical command as
`docker compose run --rm mcts mcts <command>`.

<!-- mcts:command-matrix:start -->
| Command | Purpose |
|---------|---------|
| `mcts bench rollouts [opts]` | Random-rollouts benchmark across the requested backend cohort |
| `mcts bench selfplay [opts]` | Self-play benchmark across the requested backend cohort |
| `mcts bench terminal-playouts [opts]` | Direct terminal playout throughput in `playouts/s` |
| `mcts bench search-iters [opts]` | Direct UCT search-iteration throughput in `search-iters/s` |
| `mcts verify rollouts [opts]` | Round-robin visit-count equality across `(ii)..(v)` under `--rng cpp` |
| `mcts verify selfplay [opts]` | Round-robin self-play visit-count equality across `(ii)..(v)` |
| `mcts verify legacy-parity rollouts [opts]` | Legacy-envelope rollout liveness across all five backend slots |
| `mcts verify legacy-parity selfplay [opts]` | Legacy-envelope self-play liveness across all five backend slots |
| `mcts play [opts]` | Interactive `brick` TUI; human vs AI or AI vs AI spectate |
| `mcts inspect list` | Non-interactive enumeration of the local transcript cache |
| `mcts inspect show <hash-prefix> [opts]` | Non-interactive transcript dump in legacy notation |
| `mcts inspect replay <hash-prefix> [opts]` | Interactive `brick` TUI for forward/back navigation with multi-backend equity overlay |
| `mcts inspect cache list` | Enumerate equity-sidecar entries per transcript |
| `mcts inspect cache prune [--keep-current] [--dry-run] [--plan-file <path>]` | Delete stale equity-sidecar entries |
| `mcts inspect divergence <hash-prefix>` | Emit the cross-backend divergence-rate matrix for a single transcript |
| `mcts test all [--dry-run] [--plan-file <path>]` | Plan/Apply: Dockerfile-built backends, every Cabal stanza, and pinned report card |
| `mcts test parity-anchor <baseline> <candidate> [--dry-run] [--plan-file <path>]` | Plan/Apply: measure a Q1/Q2 parity anchor for explicit backend pairs |
| `mcts test <stanza>` | Run a named Cabal test-suite stanza |
| `mcts lint files [--write]` | Check whitespace, final newlines, forbidden paths, and tracked generated-file drift |
| `mcts lint docs [--write]` | Run the generated-docs drift gate |
| `mcts lint haskell [--write]` | Run Fourmolu, HLint, and the Cabal-format round trip |
| `mcts lint all` | Run every lint gate |
| `mcts docs check` | Compare rendered output against on-disk markers and tracked paths |
| `mcts docs generate [--dry-run] [--plan-file <path>]` | Splice rendered output into markers and write tracked generated paths |
| `mcts commands [--tree\|--json]` | Flat, tree, or JSON rendering of the command registry |
| `mcts help <subcommand>` | Focused help pointer for a target command |
| `mcts check-code` | Doctrine alignment, formatter, HLint, warning-clean build, docs check |
| `mcts build cpp-legacy [--dry-run] [--plan-file <path>]` | Plan/Apply: Dockerfile C++ legacy backend build recipe |
| `mcts build cpp-imperative [--dry-run] [--plan-file <path>]` | Plan/Apply: Dockerfile C++ imperative backend mandatory PGO/BOLT build recipe |
| `mcts build cpp-functional [--dry-run] [--plan-file <path>]` | Plan/Apply: Dockerfile C++ functional-style backend mandatory PGO/BOLT build recipe |
| `mcts build rust [--dry-run] [--plan-file <path>]` | Plan/Apply: Dockerfile Rust backend mandatory PGO/BOLT build recipe |
| `mcts build legacy-fixtures --output-dir <dir> [--seed <u64>] [--games <n>] [--sims <n>] [--dry-run] [--plan-file <path>]` | Plan/Apply: generate external legacy audit fixtures |
<!-- mcts:command-matrix:end -->

### Benchmark Naming Caveat

Metric semantics are governed by
[benchmark_metrics.md](./benchmark_metrics.md). `mcts bench terminal-playouts`
reports direct terminal playout throughput in `playouts/s`, and `mcts bench
search-iters` reports direct UCT/MCTS iteration throughput in `search-iters/s`.
`mcts bench rollouts` remains a legacy command name and measures played-game
throughput with one search iteration per real move. It does not measure terminal
`playouts/s`. The played-game benchmark leaves report only `games/s`
(`games_per_second` in JSON).

Current implementation baseline: `src/MCTS/CLI/Parser.hs` exposes
`commandParserInfo`, an `optparse-applicative` parser whose command topology is
rendered from the `CommandSpec` tree while leaf option parsers remain explicit;
verify parsers reject `--rng native` at the option-reader boundary. `inspect list`
renders backend, seed, games, threading, sims,
total moves, mtime, and path; `inspect show --with-equity` first reads an
envelope-matched cached originator sidecar, then writes an originator replacement
only through the transcript's same backend/build recompute path and otherwise
reports unavailable evidence;
`inspect cache list` enumerates `.eq` / `.envelope` slots; `inspect cache prune
--keep-current` retains the logical `<backend>-logical` sidecar slot; `inspect show
--envelope` renders every logical v1 envelope field; and `inspect divergence` renders
cached sidecar metrics plus live recompute rows for every available foreign cdylib
from `MCTS.Verify.Divergence`. `mcts verify ...
--allow-stale` is routed through the layered live-envelope verifier; when a
foreign cdylib is present, FFI-produced transcripts are stamped with
`mcts_<backend>_get_envelope()` and compared through
`checkTranscriptEnvelopesLive`. JSON verify output includes
`warning_details` for downgraded `--allow-stale` backend-slot warnings. `mcts verify
legacy-parity {rollouts,selfplay}` pins `--rng cpp`, single-threading, and
`max_plies = 10000`, then checks all five backend slots for legacy-envelope
liveness/overflow without requiring backend (i)'s historical search tree to match
the steelman visit vectors. The report-card renderer emits explicit Q1a terminal
`playouts/s`, Q1b search-iteration `search-iters/s`, Q2 played-game `games/s`, and
separate Q5 scaling fields in table and JSON form. The live `mcts test all` path
requires the live C++ and Rust artefacts and populates divergence rows from the
measured live `G_V` verify cohort over backends (ii)..(v).
`mcts build legacy-fixtures` remains an explicit external audit-fixture path; it
builds `cpp-legacy/build/legacy-to-wire` and passes
output root, seed, game count, and simulation count as explicit flags. Its output
must be directed to an external or ignored artifact root and is not a normal
`mcts test all` input. All five backend identifiers remain first-class CLI values.

## Typed Source of Truth

The command registry in `src/MCTS/CLI/Spec.hs` is the source of truth for the
operator command tree and generated command artefacts. Concrete command, option,
backend ADTs, and verify-cohort GADTs — `Command`, `BenchCommand`,
`VerifyCommand`, `BuildCommand`, `InspectCommand`, `TestCommand`, `LintCommand`,
`DocsCommand`, `CommandsOptions`, `HelpOptions`, `PlayOptions`, `ShowOptions`,
`ReplayOptions`, `CacheCommand`, `DivergenceOptions`, `ParityAnchorOptions`,
`LegacyFixtureOptions`, `BenchPrimitive`, `BenchPrimitiveOptions`, `RunInputs`,
`PlanOptions`, `Backend`, `VerifyBackend`, `SimBudget`, `Threading`, `RngSource`,
`Side`, `TranscriptRef` — live in
`src/MCTS/CLI/Command.hs` and related type modules.
This document does not duplicate their full Haskell declarations; it elaborates
the generated operator-facing matrix and the per-command flag semantics in the
Flag Reference below. The generated command list lives in
[../cli/commands.md](../cli/commands.md), and the operator README carries a short
set of common invocations.

## Flag Reference

| Flag | Commands | Default | Notes |
|------|----------|---------|-------|
| `--backend <list>` | `bench`, `verify`, `play` | required | Comma-separated `NonEmpty Backend` for bench/verify; single `Backend` for play. |
| `--vs <backend>` | `play` | `Nothing` (human plays) | When set, AI-vs-AI spectator mode. |
| `--side hero\|villain` | `play` | required | Side controlled by `--backend`; with `--vs`, the `--vs` backend controls the opposite side and the human spectates. |
| `--threading single\|multi` | `bench`, `verify` | `multi` for `bench`, `single` for `verify` | Threading mode for the batch dispatcher. Primitive benchmark leaves use the same threading flags and default to 8 workers when multi-threaded. |
| `--workers N` | `bench` (when `--threading multi`) | `8` | Worker count for the batch pool. |
| `--rng native\|cpp` | `bench`, `play` | `native` | Pinned to `cpp` on the `verify` subtree at parse time. |
| `--count N` | `bench terminal-playouts`, `bench search-iters` | `1000` | Number of primitive units to measure. This is not a game count and is reported with `playouts/s` or `search-iters/s`. |
| `--games N` | played-game `bench` leaves, `verify`, `build legacy-fixtures` | required for played-game bench/verify; `10` for legacy fixtures | Game count for played-game workloads. Primitive benchmark leaves use `--count` instead. |
| `--seed N` | `bench`, `verify`, `play`, `build legacy-fixtures` | required for `bench`/`verify`; `Nothing` ⇒ fresh random (play); `42` for legacy fixtures | Master seed; played-game per-game seeds derive via `splitmix64(master_seed, game_index)`, while primitive benchmark workers derive deterministic per-unit/chunk seeds from the same master seed and backend RNG salt. |
| `--max-plies N` | `bench`, `verify`, `play` | `200` for played-game bench/verify/play; `60` for primitive benchmark leaves | Part of the determinism contract for the live verifier cohort; on primitive leaves it caps playout/search depth. |
| `--sims N` or `--sims N0:N1` | played-game `bench`, `verify`, `play`, `build legacy-fixtures` | `10_000` for played-game `bench`/`verify`; `1_000` for `play`; `10_000` for legacy fixtures | `N` parses as `FixedSims N`; `N0:N1` parses as `RampedSims N0 N1` for run commands. `build legacy-fixtures` accepts fixed `N` only. Ignored by the current legacy-named `bench rollouts` / `verify rollouts` workload, which forces one search iteration per real move. Primitive benchmark leaves use `--count` and do not accept `--sims`. |
| `--output-dir <path>` | `build legacy-fixtures` | required explicit path | Legacy audit output root; choose an external or ignored artifact directory. Files land below the host-architecture subdirectory and are not repository validation inputs. |
| `--top N` | `inspect show`, `inspect replay` | `10`; `0` ⇒ all legal moves | Live-adjustable via `+`/`-` in `inspect replay`. |
| `--with-equity` | `inspect show` | `False` | Reads the originator's cached `.eq` if envelope-matched (instant); on originator cache miss, writes a replacement only through the same backend/build recompute path. Stale, unavailable, fallback, or foreign recompute evidence is labelled and is not written as originator evidence. |
| `--envelope` | `inspect show` | `False` | Dump the transcript's engine-envelope block as plain text (one field per line) before the per-move output. Useful for scripting (`diff`-friendly) and forensics. |
| `--cache-states N` | `inspect replay` | `20` | In-memory MCTS-state LRU cache for back-navigation. |
| `--allow-stale` | `verify rollouts`, `verify selfplay` | off | Downgrade per-backend-slot `EngineEnvelopeMismatch` from hard fail to a warning; Q3 verify proceeds on visit counts. `--format json` includes the downgraded warnings under `warning_details`. Cohort-level mismatches (`host_arch`, `shared_rng_build_id`, `cohort_config_hash`) remain hard fails. Forensic use only. |
| `--keep-current` | `inspect cache prune` | off | In the Phase 2 baseline, only deletes sidecar slots whose build label does not match the logical `logical` label, yielding the current `<backend>-logical` slot. Live-envelope stale detection is enforced by `verify` for transcript cohorts; report-card/recompute sidecar coverage lives under `inspect divergence` and the Phase 7 integration stanza. |
| `--cache-dir <path>` | every cache-touching command | `./.mcts-cache/` when omitted | The `mcts` binary does not read cache-root environment variables. |
| `--format json\|table\|plain` | every non-TUI command | `table` on TTY, `plain` otherwise | Per [HASKELL_CLI_TOOL.md → Output Rules](../../HASKELL_CLI_TOOL.md). TUI commands (`play`, `inspect replay`) ignore the flag. |
| `--color auto\|always\|never`, `--no-color` | every non-TUI command | `auto` | TUI commands ignore the flag. |
| `--dry-run` | every Plan/Apply command (`test all`, `test parity-anchor`, `docs generate`, `inspect cache prune`, `build <backend>`, `build legacy-fixtures`) | off | Renders the typed `Plan` and exits 0. |
| `--plan-file <path>` | every Plan/Apply command | unset | Writes the rendered plan to disk for out-of-band review. |

## Backend Identifiers

CLI flag values and the human-readable Roman numerals used in prose:

| Identifier (CLI flag) | Roman | Path | Role |
|------------------------|-------|------|------|
| `cpp-legacy` | (i) | `cpp-legacy/` | Verbatim `MCTS_legacy` compatibility and Q6 legacy-envelope evidence |
| `cpp-imperative` | (ii) | `cpp-imperative/` | Imperative C++23 performance ceiling target; supported PGO/BOLT CLI build path |
| `cpp-functional` | (iii) | `cpp-functional/` | Functional-style C++23 steelman target; supported shared C++ PGO/BOLT CLI build path |
| `rust` | (iv) | `rust/` | Rust `cdylib`; cross-language second opinion |
| `haskell` | (v) | `src/MCTS/Engine/`, `src/MCTS/Search/` | Native Haskell engine; the target |

## RNG Source Flag

`--rng native|cpp` is part of the determinism contract. See
[determinism_contract.md](./determinism_contract.md). Pinned to `--rng cpp` at parse
time on the `mcts verify` subtree.

## Output and Color Flags

Doctrine defaults per
[../../HASKELL_CLI_TOOL.md → Output Rules](../../HASKELL_CLI_TOOL.md). `--format
json|table|plain` (default `table` on TTY, `plain` otherwise) and `--color
auto|always|never` / `--no-color` apply to every non-TUI command. The TUI commands
(`mcts play`, `mcts inspect replay`) own their own rendering and ignore both flag
families; the `CommandSpec` declares this asymmetry.

## `mcts play` Transcript Saves

`mcts play` accepts `--cache-dir <path>` for transcript writes and `:save`
inside the `brick` prompt. The TUI keeps a
chronological `MoveRecord` list for the current game; human-entered moves carry
an empty visit vector, and AI moves carry the visit vector returned by the search
that selected the action. The side named by `--side` is controlled by
`--backend`; without `--vs`, the human controls the opposite side, and with
`--vs` the second backend controls the opposite side in spectator mode. AI turns
use the selected backend's dynamic FFI `search_move` path when the matching
foreign shared library is present; if the library is absent, the TUI falls back
to the logical Haskell search path with the selected backend's native RNG salt
and reports the fallback in the status line. When `--seed` is omitted, the runner
draws a fresh `Word64` from `/dev/urandom` and records that actual seed in the
transcript header.
`:save` writes a one-game transcript through
`MCTS.Transcript.writePlayTranscript` into the normal transcript cache and
addresses it by `sha256(run_config || move_history)`, matching
[transcript_format.md → `mcts play`-Recorded
Transcripts](./transcript_format.md). The status line reports the short hash and
path after a successful write.

## `mcts inspect replay` Multi-Backend Overlay

`inspect replay` is a `brick` TUI for forward/back navigation of a stored
transcript. Beyond move-by-move navigation, it surfaces a per-move
**equity overlay** that shows each backend's view of the position the
cursor is on, with the originator marked.

### Status Line

The replay status line follows the literal layout asserted by the unit suite:

```text
<hash> | move M / total | press ? for help
```

The message row below the overlay table carries navigation hints and
cache/recompute outcomes such as originator sidecar recomputation, loaded
on-demand backend columns, missing backend libraries, absent shared libraries, and
recompute failures. The current TUI is synchronous: while a backend column is
being recomputed the event loop waits for the result and then renders either the
loaded column or an unavailable/error status.

### Per-Move Panel

For the move at the cursor, replay renders the board, the recorded move, and one
row per loaded or unavailable backend overlay:

```text
# Example: TUI per-move panel
7a2f9c11 | move 17 / 42 | press ? for help
move played: H(3,5)
backend          build      status                    chosen     equity   divergence
rust             a1b2c3d4   originator verified       H(3,5)     +0.6422  -
haskell          logical    foreign-view verified     H(3,5)     +0.6421  -
cpp-functional   unavailable unavailable              -          -        -
```

Conventions:

- `originator` marks the backend/build slot that wrote the transcript.
- `originator build-mismatch` marks a cached sidecar for the originator backend
  whose build label differs from the transcript envelope.
- `foreign-view` marks another backend's recomputed view of the same recorded
  move sequence.
- `verified` means the overlay's chosen action matches the transcript record at
  the cursor. `diverged` means it does not; the `divergence` cell names the
  recorded and overlay actions. Replay sidecars do not carry visit tables, so
  visit-rate percentages remain an `inspect divergence` / report-card surface
  rather than a replay-row cell.
- `unavailable` rows record missing shared libraries, stale backend bindings, or
  recompute failures encountered after pressing `r`.

### Lazy Compute Trigger

- **On transcript open** the originator's `.eq` is read if it exists and matches
  the transcript's `(backend, engine_build_id)` slot. Match → originator column
  populates instantly. Absent → `MCTS.CLI.Inspect.prepareReplayOverlays` attempts
  the full originator `EqStream` only through the same backend/build slot. It
  validates chosen actions and visits under `--rng cpp` before writing the sidecar.
  If the matching backend/build is unavailable, the TUI opens without an originator
  sidecar and reports unavailable evidence rather than writing a fallback stream
  under the originator label. Recompute failure becomes a status-line message; the
  stored transcript still opens for navigation.
- **Other backends** populate from cached `.eq` sidecars when present. Pressing
  `r` recomputes the next missing backend column through the Haskell recompute path
  or the matching foreign recompute FFI opener, writes
  `<cache-root>/transcripts/<arch>/<sha>/<backend>-<build_label>.eq`, appends the
  overlay, and makes subsequent navigation instant. If a requested foreign shared
  library is absent or recompute fails, the backend is marked unavailable for that
  TUI session and the status line explains why.
- **Under `--rng cpp`** same-backend originator recompute hard-asserts
  chosen-action and visit agreement with the transcript at every move; a mismatch
  surfaces as `AppError RecomputeMismatch (backend, game_id, move_index,
  recomputed_record, recorded_record)` per
  [determinism_contract.md → Recompute Mismatch Output](./determinism_contract.md).
  Foreign-view recompute does not claim originator identity: chosen-action or
  visit disagreement is rendered as `diverged` / divergence-smell comparison
  evidence instead of corrupting the originator column.

### Foreign-Backend View

If the live binary is a different `backend` than the originator (e.g.,
the user is running `inspect replay` on a `rust` transcript
from a `haskell`-only build), the originator column shows the cached
`.eq` if one exists. If the matching originator shared library is present,
`prepareReplayOverlays` can also recompute that originator column through
`MCTS.Engine.ForeignRecompute.foreignRecomputeEqStream`; if the library is absent,
the TUI opens with a status-line note that the originator sidecar is missing and
the library is not built. The persistent orange FOREIGN VIEW banner is the contract
that the user is not looking at originator numbers from the current live backend.

## `mcts verify` Envelope Errors

`mcts verify` enforces the layered envelope rule from
[determinism_contract.md → Engine Envelope](./determinism_contract.md):

- **Cohort-level**: every transcript in the cohort must agree on
  `host_arch`, `rng_source`, `cohort_config_hash`, and `shared_rng_build_id`.
  Mismatch → exit non-zero with `AppError EngineEnvelopeMismatch
  CohortLevel field expected got`. Not overridable by `--allow-stale`.
- **Per backend slot**: verify compares each transcript's substrate-affecting
  envelope fields against the live envelope for that backend slot when the
  cdylib is present, and against the in-process fallback envelope when it is
  not. `engine_git_commit` and the display/cache `build_id` accessor are
  provenance only. This path uses `checkTranscriptEnvelopesLive` and supports
  the same `--allow-stale` downgrade semantics for stale cached transcripts. In JSON
  output, downgraded envelope warnings are structured as `warning_details`
  objects with `scope`, `backend`, `field`, `expected`, `got`, and `message`
  fields.

Cross-backend differences in per-backend-slot fields are expected and
silent — the whole point of `verify` is to compare different backend slots under
one deterministic input schedule.

## Cross-References

- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [code_quality.md](./code_quality.md) — `mcts check-code` and the lint stack
- [haskell_code_guide.md](./haskell_code_guide.md) — `Plan / Apply`, `Subprocess`,
  `Env`, `AppError`
- [determinism_contract.md](./determinism_contract.md) — RNG source flag semantics
