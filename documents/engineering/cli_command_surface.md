# CLI Command Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-2-transcript-codec-and-determinism.md, ../../DEVELOPMENT_PLAN/phase-3-haskell-engine.md, ../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md, ../../DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md, ../../DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md, ../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md, ../documentation_standards.md, ./README.md
**Generated sections**: none

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
  shape, per-leaf `Example` entries, parser as a renderer of the spec.
- [../../HASKELL_CLI_TOOL.md → Progressive Introspection](../../HASKELL_CLI_TOOL.md)
  — `commands [--tree|--json]`, focused `help <subcommand>`.
- [../../HASKELL_CLI_TOOL.md → Generated Artifacts](../../HASKELL_CLI_TOOL.md) —
  marker discipline, paired check/write, `forbiddenPathRegistry`,
  `GeneratedSectionRule`, `trackingGeneratedPaths`.
- [../../HASKELL_CLI_TOOL.md → Output Rules](../../HASKELL_CLI_TOOL.md) —
  `--format json|table|plain`, `--color auto|always|never`, `--no-color`,
  stdout-vs-stderr split.
- [../../HASKELL_CLI_TOOL.md → Error Handling](../../HASKELL_CLI_TOOL.md) — single
  `AppError` ADT, `renderError :: AppError -> Text` boundary.

## Command Matrix

The full operator-facing surface. Generated artefacts under
`documents/cli/commands.md`, the manpages under `share/man/man1/`, and the shell
completion scripts under `share/completion/` all derive from the same `CommandSpec`
registry that drives this table. Phase-owned per
[../../DEVELOPMENT_PLAN/system-components.md](../../DEVELOPMENT_PLAN/system-components.md).

| Command | Purpose |
|---------|---------|
| `mcts bench rollouts [opts]` | Random-rollouts benchmark across the requested backend cohort |
| `mcts bench selfplay [opts]` | Self-play benchmark across the requested backend cohort |
| `mcts verify rollouts [opts]` | Round-robin visit-count equality across `(ii)..(v)` under `--rng cpp` |
| `mcts verify selfplay [opts]` | Round-robin self-play visit-count equality across `(ii)..(v)` |
| `mcts verify legacy-parity {rollouts\|selfplay} [opts]` | 5-backend round-robin under the legacy parity envelope |
| `mcts play [opts]` | Interactive `brick` TUI; human vs AI or AI vs AI spectate |
| `mcts inspect list` | Non-interactive enumeration of the local transcript cache |
| `mcts inspect show <hash-prefix> [opts]` | Non-interactive transcript dump in legacy notation |
| `mcts inspect replay <hash-prefix> [opts]` | Interactive `brick` TUI for forward/back navigation with multi-backend equity overlay |
| `mcts inspect cache list` | Enumerate equity-sidecar entries per transcript (one row per cached `(backend, build)` slot) |
| `mcts inspect cache prune [--keep-current]` | Delete stale equity-sidecar entries (envelope-mismatched against the current live binaries); `--keep-current` retains slots matching live binaries |
| `mcts inspect divergence <hash-prefix>` | Emit the cross-backend divergence-rate matrix (visit-Δ, move-Δ, equity-L2) for a single transcript across all cached backend columns |
| `mcts test all [--dry-run] [--plan-file <path>]` | Plan/Apply: every cabal stanza plus pinned report card |
| `mcts test <stanza>` | Run a named Cabal test-suite stanza |
| `mcts lint files\|docs\|haskell\|all` | Lint stack |
| `mcts docs check` | Compare rendered output against on-disk markers and tracked paths |
| `mcts docs generate` | Splice rendered output into markers; idempotent |
| `mcts commands` | Flat list of every subcommand |
| `mcts commands --tree` | Tree rendering |
| `mcts commands --json` | JSON command schema |
| `mcts help <subcommand>` | Focused help; equivalent to `<subcommand> --help` |
| `mcts check-code` | Doctrine alignment, formatter, hlint, warning-clean build, docs check |
| `mcts build {cpp-legacy\|cpp-imperative\|cpp-functional\|rust} [--dry-run] [--plan-file <path>]` | Plan/Apply: per-backend build harness (PGO+BOLT pipeline) |

Current implementation baseline: `inspect show --with-equity` writes a logical
originator sidecar, `inspect cache list` enumerates `.eq` / `.envelope` slots,
`inspect cache prune --keep-current` retains the logical `<backend>-logical`
build id, `inspect show --envelope` renders the current envelope fields, and
`inspect divergence` renders transcript-pair metrics from `MCTS.Verify.Divergence`.
`mcts verify ... --allow-stale` is routed through the baseline envelope verifier.
Live backend-envelope stale detection, foreign recompute, and the full cross-backend
matrix remain active plan work.

## ADT Source of Truth

All command, option, and backend ADTs — `Command`, `BenchCommand`,
`VerifyCommand`, `BuildCommand`, `InspectCommand`, `TestCommand`, `LintCommand`,
`DocsCommand`, `CommandsOptions`, `HelpOptions`, `BenchOptions`,
`VerifyOptions`, `LegacyParityOptions`, `PlayOptions`, `ShowOptions`,
`ReplayOptions`, `Backend`, `VerifyBackend`, `LegacyParityBackend`,
`LegacyParityWorkload`, `SimBudget`, `Threading`, `RngSource`, `Side`,
`TranscriptRef` — are defined in
[../../README.md → CLI command topology](../../README.md). This document does
not duplicate them; it elaborates the operator-facing matrix and the per-command
flag semantics in the Flag Reference below. Worked invocation examples for every
command also live in
[../../README.md → CLI command topology → Concrete invocations](../../README.md).

## Flag Reference

| Flag | Commands | Default | Notes |
|------|----------|---------|-------|
| `--backend <list>` | `bench`, `verify`, `play` | required | Comma-separated `NonEmpty Backend` for bench/verify; single `Backend` for play. |
| `--vs <backend>` | `play` | `Nothing` (human plays) | When set, AI-vs-AI spectator mode. |
| `--side hero\|villain` | `play` | required | Human-controlled side; ignored when `--vs` is set. |
| `--threading single\|multi` | `bench`, `verify` | `multi` for `bench`, `single` for `verify` | Threading mode for the batch dispatcher. |
| `--workers N` | `bench` (when `--threading multi`) | `8` | Worker count for the batch pool. |
| `--rng native\|cpp` | `bench`, `play` | `native` | Pinned to `cpp` on the `verify` subtree at parse time. |
| `--games N` | `bench`, `verify` | required | Game count for the run. |
| `--seed N` | `bench`, `verify`, `play` | required (bench/verify); `Nothing` ⇒ fresh random (play) | Master seed; per-game seeds derive via `splitmix64(master_seed, game_index)`. |
| `--max-plies N` | `bench`, `verify`, `play` | `200`; pinned to `10000` under `verify legacy-parity` | Ignored for backend (i); part of the determinism contract for (ii)–(v). |
| `--sims N` or `--sims N0:N1` | `bench`, `verify`, `play` | `10_000` | `N` parses as `FixedSims N`; `N0:N1` parses as `RampedSims N0 N1`. Ignored by `bench rollouts` / `verify rollouts`. |
| `--top N` | `inspect show`, `inspect replay` | `10`; `0` ⇒ all legal moves | Live-adjustable via `+`/`-` in `inspect replay`. |
| `--with-equity` | `inspect show` | `False` | Re-runs the deterministic search to populate the equity column. Reads the originator's cached `.eq` if envelope-matched (instant); otherwise recomputes locally and writes a fresh sidecar. |
| `--envelope` | `inspect show` | `False` | Dump the transcript's engine-envelope block as plain text (one field per line) before the per-move output. Useful for scripting (`diff`-friendly) and forensics. |
| `--cache-states N` | `inspect replay` | `20` | In-memory MCTS-state LRU cache for back-navigation. |
| `--allow-stale` | `verify rollouts`, `verify selfplay`, `verify legacy-parity` | off | Downgrade per-backend-slot `EngineEnvelopeMismatch` from hard fail to a warning; verify proceeds on visit counts only. Cohort-level mismatches (`host_arch`, `shared_rng_build_id`, `run_config_hash`) remain hard fails. Forensic use only. |
| `--keep-current` | `inspect cache prune` | off | Only delete sidecar slots whose envelope does NOT match a live binary; preserves the current build's cached recomputes. |
| `--cache-dir <path>` | every cache-touching command | `$MCTS_CACHE_DIR` else `./.mcts-cache/` | Resolves before the env-var fallback. |
| `--format json\|table\|plain` | every non-TUI command | `table` on TTY, `plain` otherwise | Per [HASKELL_CLI_TOOL.md → Output Rules](../../HASKELL_CLI_TOOL.md). TUI commands (`play`, `inspect replay`) ignore the flag. |
| `--color auto\|always\|never`, `--no-color` | every non-TUI command | `auto` | TUI commands ignore the flag. |
| `--dry-run` | every Plan/Apply command (`test all`, `build <backend>`) | off | Renders the typed `Plan` and exits 0. |
| `--plan-file <path>` | every Plan/Apply command | unset | Writes the rendered plan to disk for out-of-band review. |

## Backend Identifiers

CLI flag values and the human-readable Roman numerals used in prose:

| Identifier (CLI flag) | Roman | Path | Role |
|------------------------|-------|------|------|
| `cpp-legacy` | (i) | `cpp-legacy/` | Verbatim re-port of `MCTS_legacy`; regression-sanity port; excluded from the default `verify` cohort |
| `cpp-imperative` | (ii) | `cpp-imperative/` | Maximally-tuned imperative C++23; performance ceiling |
| `cpp-functional` | (iii) | `cpp-functional/` | Functional-style C++23 under the same optimisation stack as (ii) |
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

## `mcts inspect replay` Multi-Backend Overlay

`inspect replay` is a `brick` TUI for forward/back navigation of a stored
transcript. Beyond move-by-move navigation, it surfaces a per-move
**equity overlay** that shows each backend's view of the position the
cursor is on, with the originator marked.

### Status Line

Two lines, always visible at the top of the TUI:

```text
# Example: TUI status-line rendering
Transcript: 7a2f…  (cpp-imperative, seed=42, sims=10000, c_param=0.7)
Substrate:  ★ originator [cpp-imperative @ build a1b2c3…]  •  envelope: VERIFIED
```

The `Substrate:` line distinguishes three states, determined by
comparing the live `cpp-imperative` binary's envelope against the
transcript's recorded per-backend-slot envelope:

| State | Trailing text | Banner |
|-------|---------------|--------|
| Live originator binary's envelope matches exactly | `envelope: VERIFIED` (green) | none |
| Live originator binary is the same `backend` but `engine_build_id` (or any other per-backend-slot field) differs | `envelope: BUILD MISMATCH — recomputed locally; equities may drift at ULP from origin` (yellow) | persistent banner; dismiss for the session via `b` |
| Live binary is a different `backend` than the originator (the user is browsing a foreign-engine overlay only) | `envelope: FOREIGN VIEW — these numbers are this engine's, not the originator's` (orange) | persistent banner |

### Per-Move Panel

For the move at the cursor:

```text
# Example: TUI per-move panel
Move 17 — H(3,5)                                                    -- chosen action
─────────────────────────────────────────────────────────────────────
Action     Visits     ★cpp-imperative  cpp-functional  rust    haskell
H(3,5)     4123       0.6421           0.6420          0.6422  0.6421
*(4,2)      812        0.3104           0.3105          --      0.3104
V(2,6)      287       -0.0512          -0.0510         --       --
…
```

Conventions:

- **★** marks the originator (the transcript header's `backend` field).
  The originator column reads from its cached `.eq` sidecar when
  envelope-matched; otherwise the cell shows recomputed-locally values
  with the yellow BUILD MISMATCH banner.
- **`--`** marks a column that has not been computed yet for this
  transcript. The user moves focus to the column header and presses
  `r` to trigger recompute (the column shows `…computing` in the
  background; once the FFI returns, the column back-fills and writes
  to a fresh sidecar so subsequent opens are instant).
- **Column-header icons** indicate envelope status:
  - `✓` — verified (live build matches the build that wrote this `.eq`)
  - `Δ` — build mismatch (`.eq` exists but envelope drifted; cells are
    historical, hover for the recorded envelope)
  - `?` — never computed (no `.eq` for any build of this backend on
    this transcript)
- **Divergence-rate annotations**: when a non-originator column
  populates, the column header gains a small footer
  `move-Δ: 0.3%  visit-Δ: 2.1%` showing this column's
  disagreement against the originator. Colours follow the threshold
  table in [determinism_contract.md → Divergence Smell → Thresholds](./determinism_contract.md).

### Lazy Compute Trigger

- **On transcript open** the originator's `.eq` is read if it exists
  *and* its embedded envelope matches the live originator binary's
  envelope. Match → originator column populates instantly. Absent /
  envelope-stale → originator column is empty; user explicitly
  populates it (cursor on the originator column header, press `r`).
  No background work happens on open.
- **Other backends** stay `--` until requested. Compute runs in the
  background (the FFI call returns from a worker thread the REPL
  spawns); the column shows `…computing` until ready. The result
  writes to `<cache-root>/transcripts/<arch>/<sha>/<backend>-<build_prefix16>.eq`,
  so subsequent navigation away and back to that column reads the
  cache and is instant.
- **Under `--rng cpp`** the recompute hard-asserts visit-agreement
  with the transcript's recorded visits at every move; a mismatch
  surfaces as a red error banner `AppError RecomputeMismatch
  (backend, game_id, move_index, recomputed_record, recorded_record)`
  per [determinism_contract.md → Recompute Mismatch Output](./determinism_contract.md)
  — this is a bug bell, not an expected state.

### Foreign-Backend View

If the live binary is a different `backend` than the originator (e.g.,
the user is running `inspect replay` on a `cpp-imperative` transcript
from a `haskell`-only build), the originator column shows the cached
`.eq` if one exists (read-only — the live binary cannot recompute the
originator's values), and the foreign-backend's own column populates on
`r`. The persistent orange FOREIGN VIEW banner is the contract that
the user is not looking at the originator's numbers in the live
column; if no `.eq` exists for the originator, the originator column
shows `--` and a placeholder `(no cached originator equities; rebuild
cpp-imperative locally to populate)`.

## `mcts verify` Envelope Errors

`mcts verify` enforces the layered envelope rule from
[determinism_contract.md → Engine Envelope](./determinism_contract.md):

- **Cohort-level**: every transcript in the cohort must agree on
  `host_arch`, `rng_source`, `run_config_hash`, and `shared_rng_build_id`.
  Mismatch → exit non-zero with `AppError EngineEnvelopeMismatch
  CohortLevel field expected got`. Not overridable by `--allow-stale`.
- **Per backend slot**: each cached transcript's per-backend-slot
  fields must match the live binary's per-backend-slot fields for the
  same backend. Mismatch → exit non-zero with `AppError
  EngineEnvelopeMismatch (BackendSlot b) field expected got`. The
  user's options are (a) regenerate the cached transcript (`mcts bench`
  with the same `RunConfig` overwrites it) or (b) pass `--allow-stale`
  to downgrade this layer's mismatch to a warning.

Cross-backend differences in per-backend-slot fields are expected and
silent — the whole point of `verify` is to compare different binaries.

## Cross-References

- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [code_quality.md](./code_quality.md) — `mcts check-code` and the lint stack
- [haskell_code_guide.md](./haskell_code_guide.md) — `Plan / Apply`, `Subprocess`,
  `Env`, `AppError`
- [determinism_contract.md](./determinism_contract.md) — RNG source flag semantics
