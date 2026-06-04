# Code Quality

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md, ../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md, ../documentation_standards.md, ./README.md, ./unit_testing_policy.md
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
  / `justfile` / `Taskfile.yml`, host `.build/`, `bootstrap/`, and repository
  `.sh` wrappers).
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

`mcts check-code` is a container-only gate. Run it through the host-installed
`hostbootstrap` CLI (Phase 1 reopen Sprint `1.15` canonical invocation), for
example:

```bash
# Example: canonical code-quality gate
hostbootstrap run mcts check-code
```

The host `hostbootstrap` command is installed with `pipx` per the repository
[README](../../README.md#supported-workflow) and
[Phase 9 doctrine](../../DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md).
Direct `pip` installs and project-virtualenv installs are not supported.

Ambient host-level tool fallback is unsupported. Fourmolu and HLint must come from
the short-lived container's pinned style-tool install, not from the host `PATH`.
Repository shell-script wrappers are unsupported for the same reason: project
work must enter through `hostbootstrap run mcts <command>`.

Running `mcts check-code` dispatches, in order:

1. `mcts lint files` — `forbiddenPathRegistry` + `trackingGeneratedPaths`
   no-hand-edit check.
2. `mcts lint docs` — `mcts docs check` (marker drift detection).
3. `mcts lint haskell` — executes the installed `mcts-haskell-style` test
   executable, which runs `fourmolu --mode check`, `hlint`, and the `cabal format`
   temp-file round-trip byte-equality check.

Failure of any step exits non-zero with the failing stage's `AppError` rendered
through the single `renderError :: AppError -> Text` boundary.

Warning-clean compilation is owned by `docker/Dockerfile`, not by runtime
`check-code`. The image build compiles the library and executable with tests and
benchmarks enabled, installs the `mcts-criterion` benchmark executable, and installs
all current Cabal test-suite executables, including `mcts-semantic-parity`, before
publishing the image. `check-code` then runs only lint/docs/style gates against that
image-local toolchain. Runtime `check-code` output should not include Cabal
compile/link work.

## Lint Stack

`mcts lint files`, `mcts lint docs`, `mcts lint haskell`, and the aggregate
`mcts lint all` are implemented under `src/MCTS/CLI/Lint.hs`. The leaf subcommands
accept `--write` for fixable drift: file lint trims trailing whitespace, restores
final newlines, and rewrites fully generated paths; docs lint runs the generated-doc
writer before rechecking; Haskell lint runs the pinned Fourmolu inplace formatter and
`cabal format` before re-running the style stanza. Non-fixable findings such as
forbidden paths and HLint hard errors remain failures.

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
- Host-level `.build/` — canonical foreign backend artefacts belong inside the
  hostbootstrap-built image; runtime caches and temporary outputs belong inside the
  short-lived container filesystem or explicit operator-provided artifact roots.
- `bootstrap/` and repository `.sh` scripts — shell-script wrappers are refused
  because the single supported host entrypoint is
  `hostbootstrap run mcts <command>`.

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

`trackingGeneratedPaths` tracks generated documentation and other explicitly
rendered source-of-truth outputs; it must not make checked-in transcripts,
report-card snapshots, generated JSON schemas, throughput anchors, or
legacy audit directories into normal validation inputs. Those artifacts are
created in temporary roots during tests or in external/ignored roots for
explicit audits per
[unit_testing_policy.md → Repository Data Doctrine](./unit_testing_policy.md#repository-data-doctrine).

### HLint Rules

The hard Haskell style gate combines `.hlint.yaml` with the
`mcts-haskell-style` source walker:

- `print`, `exitFailure`, `Text.IO.putStrLn`, `Text.IO.hPutStrLn` (other than to
  `stderr` inside `src/MCTS/CLI/Output.hs`) are forbidden.
- `callProcess`, `readCreateProcess`, `System.Process.createProcess`,
  `System.Process.proc`, `System.Process.shell`, and `typed-process` smart
  constructors are forbidden outside `src/MCTS/Subprocess.hs`.
- Direct terminal-formatting calls (escape-sequence emission, raw ANSI codes)
  are forbidden outside `src/MCTS/CLI/Output.hs`.
- **Ambient data partials are forbidden on the supported path.**
  `Prelude.head`, `Prelude.tail`, `Prelude.init`, `Prelude.last`,
  `Prelude.read`, `Data.List.(!!)`, `Data.Maybe.fromJust`,
  `Data.Either.fromLeft`, and `Data.Either.fromRight` raise on inputs the type
  system already permits, so a silent bottom in transcript decoding, RNG state
  derivation, or move generation surfaces as a mysterious cross-backend
  `verify` mismatch instead of a typed `AppError`. Remedy hint: use
  `Data.List.NonEmpty.head` / `NonEmpty.tail` on a `NonEmpty`, `readMaybe`
  from `Text.Read`, pattern matching with an explicit `AppError` branch, or a
  local total helper. Narrow `error` calls remain permitted only for impossible
  hot-path invariants where threading `AppError` through the inner loop would
  corrupt the measured surface; ordinary input, parse, IO, FFI, and CLI errors
  still use typed errors. The `mcts-haskell-style` source walker enforces this
  rule under `src/` and `app/`; HLint remains the broader advisory pass for the
  full Haskell tree. See [haskell_code_guide.md → Total functions on the
  supported path](./haskell_code_guide.md) for the same rule expressed in
  code-guide form.

### HLint Invocation

The `mcts-haskell-style` Cabal stanza invokes `hlint` with the exact flag pair
pinned by [unit_testing_policy.md → Test Stanza Layout](./unit_testing_policy.md):

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

The repository-root `fourmolu.yaml` is the formatter SSoT. It pins the
doctrine-mandated setting names plus `respectful: true`; this document links to
that file instead of copying the YAML body, per
[../documentation_standards.md → Duplication Rules](../documentation_standards.md#5-duplication-rules).
`column-limit` is finite per doctrine (an unset or infinite column-limit
defeats the readability proxy), and the committed value is the project's chosen
ceiling.

The `mcts-haskell-style` Cabal stanza in `test/haskell-style/Main.hs` enforces the
`cabal format` round-trip through a system temp file on every run. The project policy is to
install `fourmolu-0.19.0.1` and `hlint-3.10` into `/opt/mcts-style-tools/bin/`
inside the container against the project GHC `9.12.4` (Phase 1 reopen
Sprints `1.14` + `1.16`); the formatter tools share the project GHC.
The style stanza invokes only those pinned container paths and does not honour
environment-variable overrides. If they are absent, the check fails with a remedy
pointing at `hostbootstrap run mcts check-code`; it must not skip the tools
or fall back to host `PATH`. The existing source walker remains an additional guard
for tab characters and the conservative forbidden-symbol subset.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [unit_testing_policy.md](./unit_testing_policy.md) — the `mcts-haskell-style`
  stanza and the lint-first ordering of `mcts test all`
- [cli_command_surface.md](./cli_command_surface.md) — the `mcts lint`, `mcts
  docs`, and `mcts check-code` subcommand surface
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
