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

The doctrine-alignment gate. Phase 1 Sprint 1.4 owns the implementation in
`src/MCTS/CheckCode.hs`.

`mcts check-code` is a container-only gate. Run it through the root-level
`compose.yaml` environment, for example:

```bash
# Example: canonical code-quality gate
docker compose up -d
docker compose exec mcts cabal run exe:mcts -- check-code
```

Ambient host-level tool fallback is unsupported. Fourmolu and HLint must come from
the container's pinned style-tool install, not from the host `PATH`.

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
`mcts lint all` are implemented under `src/MCTS/CLI/Lint.hs`. Each subcommand accepts
`--write` to apply auto-fixes where applicable per the doctrine's paired check/write
discipline.

### Forbidden Paths

The `forbiddenPathRegistry` refuses the following paths to keep the repository on the
one canonical `mcts` operator surface:

- `.github/workflows/` — CI workflows are out of scope for this project's supported
  path.
- `.husky/`, `.githooks/`, `.pre-commit-config.yaml`, `pre-commit-*.yaml` — git
  hooks and pre-commit shims are out of scope per
  [../../HASKELL_CLI_TOOL.md → Forbidden Surfaces](../../HASKELL_CLI_TOOL.md);
  `mcts check-code` is the only doctrine-alignment gate.
- Root `Makefile`, `justfile`, `Taskfile.yml` — competing build orchestrators are
  refused. Per-backend Makefiles under `cpp-legacy/`, `cpp-imperative/`,
  `cpp-functional/`, and per-backend `Cargo.toml` under `rust/` are allowed and
  expected.

### Generated Sections

`mcts docs check` and `mcts docs generate` are paired commands per
[../../HASKELL_CLI_TOOL.md → Generated Artifacts](../../HASKELL_CLI_TOOL.md). The
current baseline keeps fully-generated path renderers and `trackingGeneratedPaths` in
`src/MCTS/Generated/Paths.hs`; marker-delimited section rules and splice/check helpers
live in `src/MCTS/Generated/Sections.hs`. The current section registry includes
the `command-matrix` region in `documents/engineering/cli_command_surface.md`.
`src/MCTS/CLI/Docs.hs` consumes both registries and re-exports them for tests and
compatibility. Markers follow the
conventions in
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
- **Partial functions are forbidden on the supported path.** `Prelude.head`,
  `Prelude.tail`, `Prelude.init`, `Prelude.last`, `Prelude.read`,
  `Data.List.(!!)`, `Data.Maybe.fromJust`, `Data.Either.fromLeft`, and
  `Data.Either.fromRight` raise on inputs the type system already permits, so
  a silent bottom in transcript decoding, RNG state derivation, or move
  generation surfaces as a mysterious cross-backend `verify` mismatch instead
  of a typed `AppError`. Remedy hint: use `Data.List.NonEmpty.head` /
  `NonEmpty.tail` on a `NonEmpty`, `readMaybe` from `Text.Read`, pattern
  matching with an explicit `AppError` branch, or the `safe` package's
  `headMay` / `lastMay`. The `mcts-haskell-style` stanza picks these up
  through `hlint --with-group=default --with-group=extra`; the bans appear
  explicitly in `.hlint.yaml` so they survive future HLint default-set
  changes. See [haskell_code_guide.md → Total functions on the supported
  path](./haskell_code_guide.md) for the same rule expressed in code-guide
  form.

### HLint Invocation

The `mcts-haskell-style` Cabal stanza invokes `hlint` with the exact flag pair
pinned by [../../README.md → `mcts test all` → Test-suite
stanzas](../../README.md):

```bash
# Example: hlint invocation pinned by mcts-haskell-style
/opt/mcts-style-tools/bin/hlint --with-group=default --with-group=extra
```

`.hlint.yaml` is picked up automatically from the repo root. The `default` and
`extra` group pair enables both the canonical lint rule set and the additional
"extra" rules. Built-in HLint hints remain advisory; the style stanza treats only
emitted `Error:` findings from the doctrine's negative-space rules and project-specific
bans above as the hard gate.

### `fourmolu.yaml`

At repository root. Pins the twelve doctrine-mandated settings (plus
`respectful: true`) verbatim per
[../../HASKELL_CLI_TOOL.md → Pinned fourmolu.yaml](../../HASKELL_CLI_TOOL.md):

```yaml
# Example: fourmolu.yaml at repository root
indentation: 2
column-limit: 100
function-arrows: leading
comma-style: leading
import-export-style: leading
indent-wheres: false
record-brace-space: true
newlines-between-decls: 1
haddock-style: single-line
let-style: auto
in-style: right-align
unicode: never
respectful: true
```

`column-limit` is finite per doctrine (an unset or infinite column-limit
defeats the readability proxy). The value `100` is the project's chosen ceiling
within the doctrine's permitted range.

The `mcts-haskell-style` Cabal stanza in `test/haskell-style/Main.hs` enforces the
`cabal format` round-trip through a temp file on every run. The project policy is to
install `fourmolu-0.19.0.1` and `hlint-3.10` into
`/opt/mcts-style-tools/bin/` inside the container with a separate pinned
formatter-tools GHC `9.12.4`; the main project compiler stays on GHC `9.14.1`.
The style stanza invokes only those pinned container paths. If they are absent,
the check fails with a remedy pointing at the container workflow; it must not
skip the tools or fall back to host `PATH`. The existing source walker remains an
additional guard for tab characters and the conservative forbidden-symbol subset.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [unit_testing_policy.md](./unit_testing_policy.md) — the `mcts-haskell-style`
  stanza and the lint-first ordering of `mcts test all`
- [cli_command_surface.md](./cli_command_surface.md) — the `mcts lint`, `mcts
  docs`, and `mcts check-code` subcommand surface
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
