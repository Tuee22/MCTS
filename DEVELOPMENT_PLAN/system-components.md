# System Components

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[00-overview.md](00-overview.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md),
[phase-2-transcript-codec-and-determinism.md](phase-2-transcript-codec-and-determinism.md),
[phase-3-haskell-engine.md](phase-3-haskell-engine.md),
[phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md),
[phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md),
[phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md),
[phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md),
[phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)

> **Purpose**: Authoritative target component inventory for the MCTS Haskell CLI, the
> five backends, the transcript codec, the verification cohort, the Cabal test stanzas,
> and the retained state locations.

The inventory documents the authoritative Haskell-only end state. At Sprint `0.1`
closure the repository is at the bootstrap phase; every row below names its owning phase
and current status. [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
preserves cleanup and retirement history separately.

## Backends

| Backend | Identifier | Implementation Path | Linkage | Status | Owning Phase |
|---------|------------|---------------------|---------|--------|--------------|
| (i) C++ legacy port | `cpp-legacy` | `cpp-legacy/` | C ABI via Haskell FFI | 📋 Planned | [Phase 4](phase-4-cpp-legacy-port-and-ffi-bridge.md) |
| (ii) C++ imperative steelman | `cpp-imperative` | `cpp-imperative/` | C ABI via Haskell FFI | 📋 Planned | [Phase 5](phase-5-cpp-imperative-steelman.md) |
| (iii) C++ functional-style | `cpp-functional` | `cpp-functional/` | C ABI via Haskell FFI | 📋 Planned | [Phase 6](phase-6-cpp-functional-and-rust.md) |
| (iv) Rust | `rust` | `rust/` | C ABI via Haskell FFI, `cdylib` | 📋 Planned | [Phase 6](phase-6-cpp-functional-and-rust.md) |
| (v) Haskell | `haskell` | `src/MCTS/Engine/`, `src/MCTS/Search/` | Native (in-process) | 📋 Planned | [Phase 3](phase-3-haskell-engine.md) |

## Haskell CLI Surface

| Surface | Command | Purpose | Status | Owning Sprint |
|---------|---------|---------|--------|---------------|
| Random-rollouts benchmark | `mcts bench rollouts` | Engine throughput on legal-move generation, move application, terminal detection; no tree, no UCT | 📋 Planned | Sprint 7.1 |
| Self-play benchmark | `mcts bench selfplay` | Full UCT search with random-rollout leaf evaluation, adversarial self-play | 📋 Planned | Sprint 7.1 |
| Rollouts verify | `mcts verify rollouts` | Round-robin visit-count equality across the `(ii)..(v)` cohort under `--rng cpp` | 📋 Planned | Sprint 7.2 |
| Self-play verify | `mcts verify selfplay` | Round-robin self-play visit-count equality across the `(ii)..(v)` cohort | 📋 Planned | Sprint 7.2 |
| Legacy parity verify | `mcts verify legacy-parity` | 5-backend round-robin under `max_plies = 10000`, pinned fixture seed, `--rng cpp` | 📋 Planned | Sprint 7.2 |
| Interactive game | `mcts play` | TUI human-vs-AI or AI-vs-AI spectate with live board rendering | 📋 Planned | Sprint 7.4 |
| Transcript list | `mcts inspect list` | Non-interactive enumeration of the local transcript cache | 📋 Planned | Sprint 2.4 |
| Transcript show | `mcts inspect show <hash-prefix>` | Non-interactive dump in legacy move notation, optional `--with-equity` recompute | 📋 Planned | Sprint 2.4 |
| Transcript replay | `mcts inspect replay <hash-prefix>` | Interactive `brick` TUI for forward/back navigation with equity recompute | 📋 Planned | Sprint 7.4 |
| Test runner | `mcts test all` / `mcts test <stanza>` | Plan/Apply over Cabal test stanzas plus the pinned report-card workload | 📋 Planned | Sprint 7.3 |
| Lint stack | `mcts lint files\|docs\|haskell\|all` | Whitespace, final newline, forbidden paths, generated sections, formatter + hlint + `cabal format` | 📋 Planned | Sprint 1.4 |
| Docs generation | `mcts docs check` / `mcts docs generate` | Paired generated-section check and write per the `GeneratedSectionRule` registry | 📋 Planned | Sprint 1.3 |
| Command introspection | `mcts commands [--tree\|--json]` | Flat list, tree rendering, or JSON command schema from the `CommandSpec` registry | 📋 Planned | Sprint 1.2 |
| Focused help | `mcts help <subcommand>` | Equivalent to `<subcommand> --help`; same renderer as the `--help` path | 📋 Planned | Sprint 1.2 |
| Code quality gate | `mcts check-code` | Doctrine-alignment enforcement, formatter, hlint, warning-clean build, forbidden-path scan | 📋 Planned | Sprint 1.5 |

## Transcript Codec and Determinism

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Wire-format header | `src/MCTS/Transcript/Header.hs` | 📋 Planned | Sprint 2.1 |
| Per-move record codec | `src/MCTS/Transcript/Record.hs` | 📋 Planned | Sprint 2.1 |
| 255-action canonical enumeration | `src/MCTS/Transcript/Action.hs` | 📋 Planned | Sprint 2.1 |
| Content-addressed hash (`sha256(run_config)`) | `src/MCTS/Transcript/Hash.hs` | 📋 Planned | Sprint 2.2 |
| Cache root resolution (`--cache-dir` → `$MCTS_CACHE_DIR` → `./.mcts-cache/`) | `src/MCTS/Transcript/Cache.hs` | 📋 Planned | Sprint 2.2 |
| Git-style hash-prefix lookup (≥ 4 hex chars; `AppError TranscriptNotFound` / `AppError TranscriptAmbiguous`) | `src/MCTS/Transcript/Lookup.hs` | 📋 Planned | Sprint 2.3 |
| `splitmix64(master_seed, game_index)` per-game seed derivation | `src/MCTS/Rng/Mix.hs` | 📋 Planned | Sprint 2.5 |
| `--rng cpp` shared `std::mt19937_64` FFI bridge | `src/MCTS/Rng/Cpp.hs`, `cpp-legacy/c-abi/rng.h` | 📋 Planned | Sprint 4.3 |
| `--rng native` per-backend selection (splitmix for Haskell, `rand` for Rust, `xoshiro256++` / `wyrand` candidate for C++) | `src/MCTS/Rng/Native.hs` | 📋 Planned | Sprint 2.5 |

## CLI Doctrine Components

Components introduced by the doctrine adoption sprints scheduled in
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md) and the surfaces that
consume them. Citations name the doctrine sections they implement per standards rule L.

| Component | Doctrine Section | Status | Owning Sprint |
|-----------|------------------|--------|---------------|
| `CommandSpec` registry as source of truth | Automatically Generated Documentation; Command Topology | 📋 Planned | Sprint 1.2 |
| `OptionSpec` record fields (`longName`, `shortName`, `metavar`, `description`, `required`) | Automatically Generated Documentation | 📋 Planned | Sprint 1.2 |
| Per-leaf `Example` entries on every `CommandSpec` | Automatically Generated Documentation | 📋 Planned | Sprint 1.2 |
| Parser generated from the registry (parser is a renderer, not the source of truth) | Command Topology | 📋 Planned | Sprint 1.2 |
| Parser-test category via `execParserPure` | Testing Doctrine → Parser Tests | 📋 Planned | Sprint 1.2 |
| `mcts commands --tree` and `mcts commands --json` introspection | Progressive Introspection | 📋 Planned | Sprint 1.2 |
| `Subprocess` ADT plus `runStreaming` / `capture` interpreter; pure `renderSubprocess` | Architecture → Subprocesses as Typed Values | 📋 Planned | Sprint 1.6 |
| Forbidden subprocess primitives (`callProcess`, `readCreateProcess`, `System.Process` constructors, `typed-process` smart constructors) | Architecture → Subprocesses as Typed Values | 📋 Planned | Sprint 1.6 |
| `Plan` / `apply` boundary with `--dry-run` and `--plan-file <path>` | Plan / Apply | 📋 Planned | Sprint 1.7 |
| `prerequisiteRegistry` with `nodeId`, `nodeDescription`, remedy hint, transitive closure | Prerequisites as Typed Effects | 📋 Planned | Sprint 1.8 |
| Single `Env` record threaded via `ReaderT Env IO` | Application Environment | 📋 Planned | Sprint 1.9 |
| Single `AppError` ADT (`TranscriptNotFound`, `TranscriptAmbiguous`, `VerifyMismatch`, `VerifyCohortTooSmall`, `LegacyParityRolloutOverflow`, `PrerequisiteUnmet`, `SubprocessFailed`, `FFIFailure`, `UnknownCommand`, `InvalidMove`, …) | Error Handling | 📋 Planned | Sprint 1.9 |
| `renderError :: AppError -> Text` boundary | Error Handling | 📋 Planned | Sprint 1.9 |
| HLint rules refusing `print`, `exitFailure`, direct terminal formatting outside the output module | Error Handling | 📋 Planned | Sprint 1.4 |
| `--format json\|table\|plain` (default `table` on TTY else `plain`) | Output Rules | 📋 Planned | Sprint 1.9 |
| `--color auto\|always\|never` plus `--no-color` | Output Rules | 📋 Planned | Sprint 1.9 |
| `fourmolu.yaml` 12-setting list at repo root | Lint, Format, and Code-Quality Stack → Pinned fourmolu.yaml | 📋 Planned | Sprint 1.4 |
| `cabal format` temp-file round-trip byte-equality check | Lint, Format, and Code-Quality Stack | 📋 Planned | Sprint 1.4 |
| `forbiddenPathRegistry` (`.github/workflows/`, `.husky/`, `.githooks/`, root `Makefile`/`justfile`/`Taskfile.yml`) | Lint, Format, and Code-Quality Stack → Forbidden Surfaces | 📋 Planned | Sprint 1.4 |
| `GeneratedSectionRule` registry for marker-delimited generated regions | Generated Artifacts → The generated-section registry | 📋 Planned | Sprint 1.3 |
| `trackingGeneratedPaths` registry for fully-generated files (manpages, shell completions) | Generated Artifacts → Two categories of generation | 📋 Planned | Sprint 1.3 |
| Canonical property-test invariants (`decode . encode == id`, `render is deterministic`, `parser roundtrips`) | Test Categories → Property Tests | 📋 Planned | Sprint 7.1 |
| GADT-indexed `VerifyBackend` type excluding `cpp-legacy` at the type level | GADT-Indexed State Machines | 📋 Planned | Sprint 7.2 |
| GADT-indexed `LegacyParityBackend` type requiring `cpp-legacy` at parse time | GADT-Indexed State Machines | 📋 Planned | Sprint 7.2 |
| Cabal-manifest toolchain pin (`tested-with: ghc ==9.14.1` in `mcts.cabal`, `with-compiler: ghc-9.14.1` in `cabal.project`) | Toolchain pinning | 📋 Planned | Sprint 1.1 |
| Library-first layout audit (thin `app/Main.hs`, logic in `src/MCTS/`) | Project Structure | 📋 Planned | Sprint 1.1 |
| Durable CLI documentation artefacts (`documents/cli/commands.md`, `share/man/man1/mcts*.1`, `share/completion/{bash,zsh,fish}/`) | Automatically Generated Documentation | 📋 Planned | Sprint 1.3 |
| Standardized library set audit in `mcts.cabal` (`optparse-applicative`, `text`, `bytestring`, `aeson`, `prettyprinter*`, `ansi-terminal`, `path`, `path-io`, `typed-process`, `safe-exceptions`, `tasty*`, `temporary`, plus deviations `brick` + `vty`) | Overview → standardized stack | 📋 Planned | Sprint 1.1 |

## Test Stanzas

Per doctrine `Test Organization`, each tier is a separate Cabal `test-suite` with
`type: exitcode-stdio-1.0` and `tasty` as the in-stanza runner. A single `tasty` tree
spanning all tiers is forbidden.

| Stanza | Tier | Scope | Status | Owning Sprint |
|--------|------|-------|--------|---------------|
| `mcts-unit` | Pure logic | Engine invariants, parser tests via `execParserPure`, property tests (`decode . encode == id`, `render is deterministic`, `parser roundtrips`), golden tests for `CommandSpec` output and `inspect show` rendering, transcript codec roundtrips, RNG mixer properties | 📋 Planned | Sprint 7.1 |
| `mcts-integration` | Subprocess | Exercises the real `mcts` binary across the FFI to every backend; same-backend determinism (same seed ⇒ same transcripts, three seeds per backend) covering Q4 and Q6 | 📋 Planned | Sprint 7.1 |
| `mcts-cross-backend` | Round-robin verify | The `verify` cohort under `--rng cpp` covering backends `(ii)`, `(iii)`, `(iv)`, `(v)`; backend `(i)` excluded by the `VerifyBackend` type | 📋 Planned | Sprint 7.2 |
| `mcts-legacy-parity` | Round-robin verify, legacy envelope | `verify legacy-parity` across all five backends with `max_plies = 10000` pinned and the fixture seed `S_LP = 42`; pre-flight guard asserts (i) neither throws nor reaches the cap | 📋 Planned | Sprint 7.2 |
| `mcts-haskell-style` | Lint | `fourmolu --mode check`, `hlint --with-group=default --with-group=extra` plus `.hlint.yaml`, `cabal format` temp-file round-trip byte equality | 📋 Planned | Sprint 1.4 |

## POC Report-Card Knobs

Pinned in `cabal.project` for reproducibility across hosts; see
[phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md).

| Knob | Value | Purpose |
|------|-------|---------|
| `G_R` | `100_000` | Random-rollouts game count (Q1) |
| `G_S` | `1_000` | Self-play game count (Q2 / Q5) |
| `G_V` | `50` | Cross-backend verify game count (Q3) |
| `G_LP` | `10` | Legacy parity game count (Q7) |
| `S_BENCH` | `10_000` | Per-move sim budget for bench self-play |
| `S_VERIFY` | `10_000` | Per-move sim budget for verify self-play |
| `S_LP_SIMS` | `10_000` | Per-move sim budget for legacy-parity self-play |
| `S_LP` | `42` | Legacy-parity fixture seed (chosen so (i) does not throw) |

## Toolchain

| Component | Pinned Version | Purpose | Status | Owning Sprint |
|-----------|----------------|---------|--------|---------------|
| GHC | `9.14.1` | Haskell compiler for backend (v) and the CLI binary | 📋 Planned | Sprint 1.1 |
| Cabal | `3.16.1.0` | Haskell build tool; per-stanza `type: exitcode-stdio-1.0` | 📋 Planned | Sprint 1.1 |
| GCC | Latest stable on `ubuntu:24.04` | C++23 compiler for backends (i), (ii), (iii). Clang not supported. | 📋 Planned | Sprint 4.1, Sprint 5.1 |
| LLVM | Pinned in `docker/Dockerfile` | Shared by GHC `-fllvm` and BOLT post-link | 📋 Planned | Sprint 1.1 |
| `rustup` | Latest stable | Rust toolchain manager for backend (iv) | 📋 Planned | Sprint 6.4 |
| Rust | Latest stable; minor version pinned in `docker/Dockerfile` | Rust compiler for backend (iv) | 📋 Planned | Sprint 6.4 |
| `mimalloc` | Pinned in `docker/Dockerfile` | System allocator for backends (ii), (iii), (iv); static link preferred for FFI determinism | 📋 Planned | Sprint 5.3, Sprint 6.4 |
| BOLT | Pinned LLVM version | Post-link binary reordering after PGO for backends (ii), (iii), (iv) | 📋 Planned | Sprint 5.3 |
| `ghcup` | Latest stable | Manages the pinned GHC and Cabal versions inside the container | 📋 Planned | Sprint 1.1 |

## State Locations

| State Class | Authority | Durable Home | Notes |
|-------------|-----------|--------------|-------|
| Transcript cache | `mcts` CLI | `--cache-dir <path>` → `$MCTS_CACHE_DIR` → `./.mcts-cache/transcripts/<sha>.tr` | `.gitignore`'d when inside the project tree; per-game files content-addressed by `sha256(run_config)` (or `sha256(run_config \|\| move_history)` for `mcts play`-recorded transcripts) |
| Legacy fixture set | Out-of-band from `~/MCTS_legacy/` | `test/golden/legacy/` | Authoritative Q6 reference; checked into the repo |
| Retirement golden anchors | `mcts` CLI on retirement | `test/golden/<backend>/` | Frozen transcripts and throughput numbers for each retired backend; populated by the retirement protocol in Phase 8 |
| Build outputs | `cabal` plus per-backend `make` / `cargo` | `dist-newstyle/` (Cabal), per-backend `build/` directories | Operator-visible artefacts; rebuilt on demand |
| PGO profile directories | Two-stage PGO build harness | `cpp-imperative/pgo-profile/`, `cpp-functional/pgo-profile/`, `rust/pgo-profile/` | Populated by the instrumented build; consumed by the optimised build |
| CommandSpec-derived artefacts | `mcts docs generate` | `documents/cli/commands.md`, `share/man/man1/mcts*.1`, `share/completion/{bash,zsh,fish}/` | Fully-generated; tracked by `trackingGeneratedPaths`; hand edits fail `mcts lint files` |
| Plan suite | Repository worktree | `DEVELOPMENT_PLAN/` | This document set |
| Doctrine | Repository worktree | `HASKELL_CLI_TOOL.md` (root) | Authoritative CLI doctrine |
| Governed engineering docs | Repository worktree | `documents/engineering/` | Project-specific elaborations of the doctrine and project-owned content (transcript format, FFI contract, determinism contract, compiler tuning) |

## Artefact Locations

| Type | Location | Purpose |
|------|----------|---------|
| Haskell application entrypoint | `app/Main.hs` | Thin entry point per the library-first layout |
| Haskell source modules | `src/MCTS/` | Engine, CLI, transcript codec, FFI bindings, output, lint |
| Cabal package definition | `mcts.cabal` | Build, test, and dependency definition with `tested-with: ghc ==9.14.1` |
| Cabal project definition | `cabal.project` | Repository-wide Cabal package-set definition with `with-compiler: ghc-9.14.1` and the report-card knobs |
| Formatter config | `fourmolu.yaml` | Pinned 12 doctrine-mandated settings at repo root |
| Backend (i) sources | `cpp-legacy/` | Verbatim re-port of `MCTS_legacy` with FFI shims |
| Backend (ii) sources | `cpp-imperative/` | Maximally-tuned imperative C++23 |
| Backend (iii) sources | `cpp-functional/` | Functional-style C++23 under the same optimisation stack as (ii) |
| Backend (iv) sources | `rust/` | Rust `cdylib` with the pinned `[profile.release]` |
| Haskell tests | `test/` | Five Cabal stanza modules; `test/golden/` for golden fixtures including `test/golden/legacy/` |
| Bench targets | `bench/` | Cabal benchmark targets (`criterion` / `tasty-bench`) for in-process timing |
| Docker development environment | `docker/Dockerfile`, `docker/compose.yaml` | `ubuntu:24.04` base with pinned GCC, LLVM, GHC, Cabal, and Rust |
| Development plan | `DEVELOPMENT_PLAN/` | This plan suite |
| Doctrine | `HASKELL_CLI_TOOL.md` | Authoritative CLI doctrine at repo root |
| Project README | `README.md` | Project intent, command surface, doctrine scope, build instructions |
| Agent guardrails | `AGENTS.md`, `CLAUDE.md` | Git-command restrictions and doctrine pointers for LLM agents |

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
