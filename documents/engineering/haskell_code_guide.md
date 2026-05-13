# Haskell Code Guide

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../documentation_standards.md, ./README.md
**Generated sections**: none

> **Purpose**: Describe how the MCTS project uses the doctrine's Haskell patterns —
> `Subprocess`, `Plan / Apply`, `prerequisiteRegistry`, `ReaderT Env IO`, `AppError`
> with `renderError`, GADT-indexed state machines — and record the project's
> stack deviations. Defers to [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md)
> for each pattern's authoritative definition.

## Doctrine Pointers

- [../../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed
  Values](../../HASKELL_CLI_TOOL.md) — `Subprocess` ADT, pure `renderSubprocess`,
  `runStreaming` / `capture` as the only IO boundary, the forbidden-primitives
  list (`callProcess`, `readCreateProcess`, `System.Process` constructors,
  `typed-process` smart constructors).
- [../../HASKELL_CLI_TOOL.md → Plan / Apply](../../HASKELL_CLI_TOOL.md) — `build` /
  `apply` boundary, `--dry-run` and `--plan-file <path>` on every Plan/Apply
  command.
- [../../HASKELL_CLI_TOOL.md → Prerequisites as Typed
  Effects](../../HASKELL_CLI_TOOL.md) — `prerequisiteRegistry` with `nodeId`,
  `nodeDescription`, remedy hint, transitive closure, `AppError PrerequisiteUnmet`
  on failure.
- [../../HASKELL_CLI_TOOL.md → Application Environment](../../HASKELL_CLI_TOOL.md)
  — `ReaderT Env IO` with a single `Env` record, test-hook fields with no-op
  defaults in production.
- [../../HASKELL_CLI_TOOL.md → Error Handling](../../HASKELL_CLI_TOOL.md) — single
  `AppError` ADT, `renderError :: AppError -> Text` boundary, `print` /
  `exitFailure` / direct terminal formatting forbidden outside the dedicated
  output module.
- [../../HASKELL_CLI_TOOL.md → GADT-Indexed State Machines](../../HASKELL_CLI_TOOL.md)
  — phantom-type indices, singleton witnesses, the existential-wrapping pattern
  for runtime discovery, the forbidden runtime-status-enum-with-manual-validation
  pattern.

## Project-Specific Elaborations

### `Subprocess`

The Phase 5/6 PGO+BOLT build harness and the FFI shared-library link path go
through `runStreaming` / `capture`. There is no other IO surface for subprocess
execution. The `.hlint.yaml` rules from
[code_quality.md → HLint Rules](./code_quality.md#hlint-rules) enforce the
forbidden-primitives list.

### `Plan / Apply`

The MCTS commands that consume the `Plan / Apply` pattern are:

- `mcts test all` — Plan/Apply over the five Cabal stanzas plus the report-card
  workload (Phase 7 Sprint 7.3).
- `mcts build {cpp-legacy|cpp-imperative|cpp-functional|rust}` — Plan/Apply over
  the per-backend two-stage PGO + BOLT post-link + `mimalloc` link pipeline
  (Phase 5 Sprint 5.3, Phase 6 Sprint 6.2, Phase 6 Sprint 6.4).
- `mcts docs generate` — internally Plan/Apply over the rendered marker
  substitutions and the `trackingGeneratedPaths` writes (Phase 1 Sprint 1.3).

`mcts bench` and `mcts verify` are not Plan/Apply commands — they do not mutate
external state (only the transcript cache, which they own), so the
`--dry-run` flag does not apply. They do, however, consume the
`prerequisiteRegistry`.

### `prerequisiteRegistry`

The `prerequisiteRegistry` (Phase 1 Sprint 1.7) covers every toolchain dependency
across the five backends. The remedy hints point at concrete operator actions —
`docker compose up -d` for missing container tooling, `make -C cpp-imperative
smoke` for a missing `libmcts_cpp_imperative.so`, `mcts build rust` for a missing
`libmcts_rust.so`, and so on.

### `Env`

The `Env` record (Phase 1 Sprint 1.8) carries the log handle, the cache root, the
parsed CLI options, the `CommandSpec` registry, the generated-section registries,
the `prerequisiteRegistry`, and test-hook fields. The `newtype App = App
{ runApp :: ReaderT Env IO a }` is the only application monad.

### `AppError` and `renderError`

The single `AppError` ADT (Phase 1 Sprint 1.9) declares constructors for the
project's named error conditions:

- `TranscriptNotFound`, `TranscriptAmbiguous` — hash-prefix lookup failures.
- `VerifyMismatch`, `VerifyCohortTooSmall` — cross-backend verify failures.
- `LegacyParityRolloutOverflow` — backend (i) throws or hits
  `MAX_ROLLOUT_ITERS`.
- `PrerequisiteUnmet` — `prerequisiteRegistry` failure carrying the failing
  `nodeId`, `nodeDescription`, and remedy hint.
- `SubprocessFailed` — `runStreaming` / `capture` returns a non-zero exit code
  through the typed `Subprocess` boundary (the PGO+BOLT build harness, the
  `cabal test` invocation, etc.). Reserved for the subprocess boundary only.
- `FFIFailure` — a C ABI call through the Haskell FFI raised. Carries the
  backend identity (`Backend`), the C ABI symbol that raised, and the decoded
  error message. Reserved for the FFI bridge only; distinct from
  `SubprocessFailed` because the failure surface is in-process rather than a
  spawned child. See
  [backend_ffi_contract.md → Error rendering](./backend_ffi_contract.md).
- `DocsCheckDrift` — `mcts docs check` detects a marker drift.
- `UnknownCommand`, `InvalidMove` — `mcts play` in-app input errors.

`renderError :: AppError -> Text` lives in `src/MCTS/CLI/Output.hs`. It is the
only Text-rendering path at the CLI boundary; the `.hlint.yaml` rules enforce
this.

### GADT-Indexed State Machines

Three project state machines use phantom-type indices:

- `SimBudget = FixedSims Int | RampedSims Int Int` — single-budget and per-move
  ramped variants.
- `Threading = SingleThreaded | MultiThreaded { workers :: Int }` — single and
  multi-worker dispatch.
- `VerifyBackend` and `LegacyParityBackend` — the type-level exclusion of
  backend (i) from the default `verify` cohort and the type-level requirement of
  backend (i) for the legacy-parity cohort. Phase 7 Sprint 7.2 owns the GADT
  shape.

The doctrine's "more than two states ⇒ GADT-indexed" guidance applies; the
two-state ADTs above (`SimBudget` is a sum of two constructors but the state
space is conceptually two; `Threading` similarly) are allowed as plain ADTs.

## Stack Deviations from Doctrine

Two recorded deviations from
[../../HASKELL_CLI_TOOL.md → Overview](../../HASKELL_CLI_TOOL.md):

- **`brick` + `vty` for TUIs only.** Required by the interactive `mcts play` and
  `mcts inspect replay` commands. Gated: `brick` and `vty` are imported only by
  modules under `src/MCTS/CLI/Tui/`, `src/MCTS/CLI/Play.hs`, and
  `src/MCTS/CLI/Replay.hs`. Phase 7 Sprint 7.4 owns the gate. The `mcts lint
  haskell` pass enforces the gate via an `.hlint.yaml` rule.
- **`dhall` unused.** The doctrine prescribes `dhall` for daemon configuration;
  daemon configuration is out of scope for this CLI per
  [../../DEVELOPMENT_PLAN/00-overview.md → Doctrine
  Scope](../../DEVELOPMENT_PLAN/00-overview.md), so the dependency does not
  enter the stack.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [code_quality.md](./code_quality.md) — lint rules that enforce the patterns
- [cli_command_surface.md](./cli_command_surface.md) — the user-facing surface
  these patterns underpin
- [backend_ffi_contract.md](./backend_ffi_contract.md) — how `Subprocess`
  underpins the FFI build harness
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
