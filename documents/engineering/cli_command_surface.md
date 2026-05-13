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
| `mcts inspect replay <hash-prefix> [opts]` | Interactive `brick` TUI for forward/back navigation |
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

## Cross-References

- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [code_quality.md](./code_quality.md) — `mcts check-code` and the lint stack
- [haskell_code_guide.md](./haskell_code_guide.md) — `Plan / Apply`, `Subprocess`,
  `Env`, `AppError`
- [determinism_contract.md](./determinism_contract.md) — RNG source flag semantics
