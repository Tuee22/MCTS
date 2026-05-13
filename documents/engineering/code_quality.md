# Code Quality

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../documentation_standards.md, ./README.md, ./unit_testing_policy.md
**Generated sections**: none

> **Purpose**: Describe `mcts check-code`, the `mcts lint *` family, the `mcts docs
> check / generate` pair, and the `forbiddenPathRegistry`. Defers to
> [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) for Lint, Format,
> Code-Quality Stack, Generated Artifacts, and Forbidden Surfaces doctrine.

## Doctrine Pointers

- [../../HASKELL_CLI_TOOL.md → Lint, Format, and Code-Quality
  Stack](../../HASKELL_CLI_TOOL.md) — the `fourmolu` + `hlint` + `cabal format`
  stack, the twelve `fourmolu.yaml` settings, the `cabal format` temp-file
  round-trip byte-equality, and the dedicated `mcts-haskell-style` Cabal stanza.
- [../../HASKELL_CLI_TOOL.md → Forbidden Surfaces (Negative-Space
  Lint)](../../HASKELL_CLI_TOOL.md) — the `forbiddenPathRegistry` refusing parallel
  workflow surfaces (`.github/workflows/`, `.husky/`, `.githooks/`, root `Makefile`
  / `justfile` / `Taskfile.yml`).
- [../../HASKELL_CLI_TOOL.md → Generated Artifacts](../../HASKELL_CLI_TOOL.md) — the
  `GeneratedSectionRule` registry, the `trackingGeneratedPaths` registry, the
  paired `mcts docs check` / `mcts docs generate` commands, the determinism
  requirements on renderers, and the three-element error message on drift.
- [../../HASKELL_CLI_TOOL.md → Error Handling](../../HASKELL_CLI_TOOL.md) — the
  HLint rules refusing `print`, `exitFailure`, and direct terminal formatting
  outside `src/MCTS/CLI/Output.hs`.

## `mcts check-code`

The doctrine-alignment gate. Phase 1 Sprint 1.4 owns the implementation.

Running `mcts check-code` dispatches, in order:

1. `mcts lint files` — `forbiddenPathRegistry` + `trackingGeneratedPaths`
   no-hand-edit check.
2. `mcts lint docs` — `mcts docs check` (marker drift detection).
3. `mcts lint haskell` — `fourmolu --mode check` + `hlint` + `cabal format`
   temp-file round-trip byte-equality.
4. `cabal build all` warning-clean under the pinned toolchain.

Failure of any step exits non-zero with the failing stage's `AppError` rendered
through the single `renderError :: AppError -> Text` boundary.

## Lint Stack

`mcts lint files`, `mcts lint docs`, `mcts lint haskell`, and the aggregate
`mcts lint all` are implemented under `src/MCTS/Lint.hs`. Each subcommand accepts
`--write` to apply auto-fixes where applicable per the doctrine's paired check/write
discipline.

### Forbidden Paths

The `forbiddenPathRegistry` refuses the following paths to keep the repository on the
one canonical `mcts` operator surface:

- `.github/workflows/` — CI workflows are out of scope for this project's supported
  path.
- `.husky/`, `.githooks/` — git hooks are out of scope; `mcts check-code` is the
  only doctrine-alignment gate.
- Root `Makefile`, `justfile`, `Taskfile.yml` — competing build orchestrators are
  refused. Per-backend Makefiles under `cpp-legacy/`, `cpp-imperative/`,
  `cpp-functional/`, and per-backend `Cargo.toml` under `rust/` are allowed and
  expected.

### Generated Sections

`mcts docs check` and `mcts docs generate` are paired commands per
[../../HASKELL_CLI_TOOL.md → Generated Artifacts](../../HASKELL_CLI_TOOL.md). The
`GeneratedSectionRule` registry lives in `src/MCTS/Generated/Sections.hs`; the
`trackingGeneratedPaths` registry lives in `src/MCTS/Generated/Paths.hs`. Markers
follow the conventions in
[../documentation_standards.md → Generated Sections](../documentation_standards.md#11-generated-sections).

### HLint Rules

`.hlint.yaml` at the repository root carries the doctrine's nested-case warnings
plus negative-space rules:

- `print`, `exitFailure`, `Text.IO.putStrLn`, `Text.IO.hPutStrLn` (other than to
  `stderr` inside `src/MCTS/CLI/Output.hs`) are forbidden.
- `callProcess`, `readCreateProcess`, `System.Process.createProcess`,
  `System.Process.proc`, `System.Process.shell`, and `typed-process` smart
  constructors are forbidden outside `src/MCTS/Subprocess.hs`.
- Direct terminal-formatting calls (escape-sequence emission, raw ANSI codes)
  are forbidden outside `src/MCTS/CLI/Output.hs`.

### HLint Invocation

The `mcts-haskell-style` Cabal stanza invokes `hlint` with the exact flag pair
pinned by [../../README.md → `mcts test all` → Test-suite
stanzas](../../README.md):

```
hlint --with-group=default --with-group=extra
```

`.hlint.yaml` is picked up automatically from the repo root. The `default` and
`extra` group pair enables both the canonical lint rule set and the additional
"extra" rules; the doctrine's negative-space rules and project-specific bans
above ride alongside.

### `fourmolu.yaml`

At repository root. Pins the twelve doctrine-mandated settings per
[../../HASKELL_CLI_TOOL.md → Pinned fourmolu.yaml](../../HASKELL_CLI_TOOL.md):
`indentation`, `column-limit`, `function-arrows`, `comma-style`,
`import-export-style`, `indent-wheres`, `record-brace-space`,
`newlines-between-decls`, `haddock-style`, `let-style`, `in-style`, `unicode`. Plus
`respectful: true`.

The `mcts-haskell-style` Cabal stanza in `test/haskell-style/Main.hs` enforces the
formatter, the linter, and the `cabal format` round-trip in one suite.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [unit_testing_policy.md](./unit_testing_policy.md) — the `mcts-haskell-style`
  stanza and the lint-first ordering of `mcts test all`
- [cli_command_surface.md](./cli_command_surface.md) — the `mcts lint`, `mcts
  docs`, and `mcts check-code` subcommand surface
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
