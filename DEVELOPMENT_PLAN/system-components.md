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
**Generated sections**: none

> **Purpose**: Authoritative target component inventory for the MCTS Haskell CLI, the
> backend cohort, the transcript codec, the verification cohort, the Cabal test stanzas,
> and the retained state locations.

The inventory documents the authoritative end state and the current implementation
baseline. The repository now has an implemented two-live-backend verification baseline:
operator-facing verify dispatches through live FFI engines when their shared
libraries are present and the requested batch run is compatible with the current
fixed 60-ply foreign search horizon; it falls back to the in-process runner only
when a library is absent or a lower search cap is requested. Q3 is the
visit-vector equality gate for the surviving `(iv)..(v)` cohort. Q6 and Q7 are
retired-backend historical evidence surfaces, not clean-clone test inputs. The
2026-05-19 canonical report card records
`Verdict: Within tolerance`. The Phase `8` parity proof, retirement anchors,
compiler-runtime doc alignment, and generated-validation-data cleanup are closed;
the surviving live cohort is `(rust, haskell)`. Rows marked `✅ Done` reflect
implemented and validated surfaces; retired rows preserve source/reference value
and historical evidence without requiring checked-in generated artifacts. There
is no remaining Phase `8` cleanup work.
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) preserves cleanup
and retirement history separately.

## Current Implementation Baseline

| Component | Current Worktree Evidence | Closure Gap |
|-----------|---------------------------|-------------|
| Cabal package and CLI | `mcts.cabal`, `cabal.project`, `app/Main.hs`, `src/MCTS/App.hs`; doctrine-standard library/test dependency set is declared; host validation enters through `docker compose run --rm mcts mcts check-code`; Docker installs the isolated style-tool GHC and formatter/hlint binaries plus the `mcts` executable | ✅ Done |
| Command registry | `src/MCTS/CLI/Spec.hs`, `src/MCTS/CLI/Parser.hs`; `mcts commands --tree` and `mcts commands --json` work; `commandParserInfo` renders an optparse-applicative parser from the registry tree; README concrete invocations use the Compose entrypoint around the same logical leaf commands; `bench` and `verify` require explicit backend/games/seed inputs where governed, `verify` defaults to single-threaded `--rng cpp`, and `play` carries `--backend`, `--side`, `--vs`, `--rng`, `--seed`, `--max-plies`, and `--cache-dir` | ✅ Done |
| Transcript/cache baseline | `src/MCTS/Transcript.hs`, `src/MCTS/Crypto/SHA256.hs`, `src/MCTS/Transcript/EquitySidecar.hs`, plus wrapper modules; `.mcts-cache/` ignored; one-game transcript cache writes use `runGameIndex` without rewriting `master_seed`; `inspect list` / `inspect show --envelope` / `inspect show --with-equity` / `inspect replay` originator cache-miss sidecar preparation plus `r`-key on-demand backend columns / `inspect cache list` / `inspect cache prune` work; transcript and sidecar writes use same-directory temp files, fsync, rename, and parent-directory fsync; the v1 envelope wire payload matches the documented C ABI and display/cache build labels derive from `engine_build_id`; `inspect show --with-equity` reads an envelope-matched originator sidecar before recomputing; `MCTS.Engine.ForeignRecompute.foreignRecomputeEqStream` can score foreign recompute streams through `mcts inspect divergence` and can fill replay overlays when cdylibs are present; FFI-produced transcripts carry live envelopes when cdylibs are present; `mcts-integration` checks live transcript stamping and backend-slot stale hard-fail/`--allow-stale` warning behavior when cdylibs are present; `mcts-integration` also covers bounded report-card divergence building and cached recompute-sidecar coverage; `mcts test all` derives report-card Q1/Q2/Q5 rows from live no-write Haskell measurements against the frozen backend (ii) anchor and divergence rows from the measured live `G_V` verify transcripts | ✅ Done for the Phase 2 transcript/cache/envelope surface, Phase 7 verifier/replay overlay surface, and Sprint 8.8 generated-validation-data cleanup |
| In-process MCTS engine | `src/MCTS/Engine.hs`, `src/MCTS/Engine/Envelope.hs`, `src/MCTS/Driver.hs`, `src/MCTS/Search/Arena.hs`, `src/MCTS/Search/UCT.hs`, `src/MCTS/Verify.hs`; the Haskell engine uses strict `Word64` board slots/bitsets, real recursive UCT in the `ST` monad over a structure-of-arrays `STUArray` arena, a sentinel `terminalOutcome` path for the rollout inner loop, and per-move search dispatch from the driver. `MCTS.Verify` now dispatches through `MCTS.Driver.Dispatch.runBatchDispatch`, so Q3 uses the live Rust cdylib for `(iv)..(v)` when present and the in-process runner only as the no-cdylib fallback. It compares a canonical byte-projected determinism payload digest first, then runs a length-aware game/move/terminator scan only on digest mismatch. Q1/Q2/Q7 retired-backend results are historical evidence, not generated repository inputs. | ✅ Done |
| Foreign backend homes | `cpp-legacy/` contains the retired mechanically imported legacy core plus C ABI wrappers and the optional local `legacy-to-wire` evidence generator reached through `mcts build legacy-fixtures`; `cpp-imperative/` is a retired reference; `cpp-functional/` is a retired functional-style C++ reference; `rust/src/` ships a real arena MCTS, a dormant xoshiro256++ helper module, the splitmix-compatible live search schedule, the full Corridors gameplay port (8x8 bitfield walls, iterative BFS escapability, post-move 180-degree flip via `u64::reverse_bits`), and the visit-vector/recompute/read-visits C ABI; `src/MCTS/Driver/Rust.hs` dispatches through the real shared library via `MCTS.FFI.Common.withDynamicSearchGame` / `withDynamicRecomputeGame`; `mcts build rust` passes the documented `-C link-arg=-fuse-ld=lld` through both PGO stages | ✅ Done for the Phase 6 Rust build-harness surface |
| Test stanzas | `test/unit`, `test/integration`, `test/cross-backend`, `test/haskell-style`; each stanza has its own `tasty` runner; host validation gate is `docker compose run --rm mcts mcts test all`. Unit renderer/codec checks use semantic assertions and in-memory bytes; integration retired-backend coverage synthesizes transcripts in temporary roots; `test/golden/` generated inputs and `tasty-golden` are absent. | ✅ Done for Sprint 8.8 no-generated-validation-data cleanup |
| Generated docs gate | `src/MCTS/CLI/Docs.hs`, `src/MCTS/Generated/Paths.hs`, `src/MCTS/Generated/Sections.hs`, `documents/engineering/cli_command_surface.md`, `documents/cli/commands.md`, `share/man/man1/mcts.1`, `share/completion/{bash,zsh,fish}/`; `mcts docs check` and `mcts lint files` check tracked generated-file drift; `command-matrix` is a marker-delimited governed-doc section rendered from `CommandSpec` | ✅ Done |

## Backends

| Backend | Identifier | Implementation Path | Linkage | Status | Owning Phase |
|---------|------------|---------------------|---------|--------|--------------|
| (i) C++ legacy port | `cpp-legacy` | `cpp-legacy/` | Retired; archived C ABI source retained for reference and optional local evidence generation | ✅ Retired in Sprint 8.4 (Phase 4 surfaces closed; Q6 evidence recorded historically; live CLI/build/verify/FFI dispatch removed; generated transcript/throughput anchors are no longer repository validation inputs) | [Phase 4](phase-4-cpp-legacy-port-and-ffi-bridge.md), [Phase 8](phase-8-haskell-performance-parity-closure.md) |
| (ii) C++ imperative steelman | `cpp-imperative` | `cpp-imperative/` | Retired; archived C ABI source retained for reference | ✅ Retired in Sprint 8.5 (Phase 5 surfaces closed; backend (iii)-vs-(ii) Q1/Q2 evidence recorded within tolerance; live CLI/build/verify/FFI dispatch removed; generated transcript/throughput anchors are no longer repository validation inputs) | [Phase 5](phase-5-cpp-imperative-steelman.md), [Phase 8](phase-8-haskell-performance-parity-closure.md) |
| (iii) C++ functional-style | `cpp-functional` | `cpp-functional/` | Retired; archived C ABI source retained for reference | ✅ Retired in Sprint 8.6 (Phase 6 surfaces closed; backend (v)-vs-(iii) Q1/Q2 evidence recorded within tolerance; live CLI/build/verify/FFI dispatch removed; generated transcript/throughput anchors are no longer repository validation inputs) | [Phase 6](phase-6-cpp-functional-and-rust.md), [Phase 8](phase-8-haskell-performance-parity-closure.md) |
| (iv) Rust | `rust` | `rust/`, `src/MCTS/Driver/Rust.hs` | C ABI via Haskell FFI, `cdylib` | ✅ Done (real arena MCTS with UCT-1, splitmix-compatible live search schedule, dormant xoshiro256++ helper module, full `mcts_rust_search_move` / `mcts_rust_recompute_move` C ABI, cached `mcts_rust_read_visits`, real Corridors gameplay in `rust/src/board.rs`, `mimalloc::MiMalloc` global allocator, and `rustPgoBoltPlan` through PGO train/merge/use plus BOLT training/install on amd64. `MCTS.Driver.Dispatch.runBatchDispatch` routes `--backend rust` through the real FFI engine.) | [Phase 6](phase-6-cpp-functional-and-rust.md) |
| (v) Haskell | `haskell` | `src/MCTS/Engine.hs`, `src/MCTS/Engine/Envelope.hs`, `src/MCTS/Driver.hs`, `src/MCTS/Search/Arena.hs`, `src/MCTS/Search/UCT.hs` | Native (in-process) | ✅ Done for the Phase 3 correctness baseline and the Phase 8 parity proof | [Phase 3](phase-3-haskell-engine.md), [Phase 8](phase-8-haskell-performance-parity-closure.md) |

## Haskell CLI Surface

| Surface | Command | Purpose | Status | Owning Sprint |
|---------|---------|---------|--------|---------------|
| Random-rollouts benchmark | `mcts bench rollouts` | Engine throughput on legal-move generation, move application, terminal detection; no tree, no UCT | ✅ Done (the live Rust foreign backend dispatches through real FFI when its shared library is present; Haskell remains native in-process; backends (i), (ii), and (iii) are archived) | Sprint 3.5; foreign dispatch in Sprints 5.4, 6.2, 6.4; Sprints 8.4-8.6 retirement |
| Self-play benchmark | `mcts bench selfplay` | Full UCT search with random-rollout leaf evaluation, adversarial self-play | ✅ Done (the live Rust foreign backend dispatches through real FFI when its shared library is present; Haskell remains native in-process; backends (i), (ii), and (iii) are archived) | Sprint 3.5; foreign dispatch in Sprints 5.4, 6.2, 6.4; Sprints 8.4-8.6 retirement |
| Rollouts verify | `mcts verify rollouts` | Live FFI-backed round-robin visit-count equality across the `(iv)..(v)` cohort under `--rng cpp`; layered envelope checks with `--allow-stale`; digest-first canonical payload comparison with length-aware mismatch reporting | ✅ Done | Sprint 7.2, Sprint 7.5, Sprints 8.5-8.6 retirement |
| Self-play verify | `mcts verify selfplay` | Live FFI-backed round-robin self-play visit-count equality across the `(iv)..(v)` cohort using the same digest-first, length-aware verifier comparator | ✅ Done | Sprint 7.2, Sprint 7.5, Sprints 8.5-8.6 retirement |
| Legacy parity verify | `mcts verify legacy-parity {rollouts\|selfplay}` | Retired Sprint 8.4; Q7 is preserved as historical retirement evidence, not as a clean-clone generated input | ✅ Retired | Sprint 7.2, Sprint 8.4 |
| Interactive game | `mcts play` | TUI human-vs-AI or AI-vs-AI spectate with live board rendering; parser and execution carry `--backend`, `--side`, `--vs`, `--rng`, `--seed`, `--max-plies`, and `--cache-dir`; the side named by `--side` is AI-controlled by `--backend`, `--vs` controls the opposite side in spectator mode, and omitted seeds come from `/dev/urandom` | ✅ Done | Sprint 7.4 |
| Transcript list | `mcts inspect list` | Non-interactive enumeration of the local transcript cache | ✅ Done | Sprint 2.4 |
| Transcript show | `mcts inspect show <hash-prefix>` | Non-interactive dump in legacy move notation, `--envelope` dump, optional `--with-equity` originator-sidecar read/recompute and stream-backed equity column | ✅ Done (`--with-equity` reads an envelope-matched originator `.eq` before recomputing, and `--envelope` renders the full logical v1 envelope) | Sprint 2.4, Sprint 2.6 |
| Transcript replay | `mcts inspect replay <hash-prefix>` | Interactive `brick` TUI for forward/back navigation with equity overlays; rows label originator, originator build-mismatch, foreign-view, unavailable, verified, and diverged states, with chosen-action divergence annotations where sidecars carry mismatched choices | ✅ Done | Sprint 7.4 |
| Sidecar cache list | `mcts inspect cache list` | Enumerate equity-sidecar `(backend, build)` slots cohabiting each cached transcript and mark each slot as originator, foreign, or unknown | ✅ Done on the Phase 2 sidecar-cache surface | Sprint 2.7 |
| Sidecar cache prune | `mcts inspect cache prune [--keep-current]` | Plan/Apply deletion of equity sidecars; `--keep-current` retains current logical build slots in the Phase 2 baseline | ✅ Done on the Phase 2 sidecar-cache surface; verify-time live-envelope stale detection is owned by Sprint 7.5 | Sprint 2.7 |
| Divergence matrix | `mcts inspect divergence <hash-prefix>` | Emit divergence-rate metrics (`visit-Δ`, `move-Δ`, `equity-L2`) for a single transcript and cached backend columns; report-card rows consume decoded verify transcripts consistent with the corrected canonical comparator | ✅ Done | Sprint 7.5, Sprints 8.5-8.6 retirement |
| Test runner | `mcts test all` / `mcts test <stanza>` | Plan/Apply over backend builds, Cabal test stanzas, verify cohorts, and the no-write measured report-card workload | ✅ Done (`--dry-run`; recursive CLI steps route through `cabal exec mcts -- ...`; report-card summary plus Q1/Q2/Q5 measured fields, Q3 verify cohorts, Q7 historical evidence, and divergence matrix rendering exist without checked-in report-card/schema fixtures) | Sprint 7.2, Sprint 7.3, Sprint 8.8 |
| Lint stack | `mcts lint files\|docs\|haskell\|all` | Whitespace, final newline, forbidden paths, generated sections, mandatory container-owned formatter/hlint path, partial-function enforcement, and `cabal format`; host fallback is unsupported | ✅ Done (formatter docs point at the committed `fourmolu.yaml` SSoT; supported-path partial functions are removed and guarded by the `mcts-haskell-style` source walker) | Sprint 1.4 |
| Docs generation | `mcts docs check` / `mcts docs generate` | Paired generated-section check and write per the `GeneratedSectionRule` registry | ✅ Done | Sprint 1.3 |
| Command introspection | `mcts commands [--tree\|--json]` | Flat list, tree rendering, or JSON command schema from the `CommandSpec` registry | ✅ Done | Sprint 1.2 |
| Focused help | `mcts help <subcommand>` | Focused pointer for a target command; the runner prints the target and directs operators to `docker compose run --rm mcts mcts commands --tree` for the command tree | ✅ Done | Sprint 1.2 |
| Code quality gate | `mcts check-code` | Doctrine-alignment enforcement, formatter, hlint, warning-clean build, forbidden-path scan | ✅ Done | Sprint 1.4 |
| Per-backend build harness | `mcts build rust` plus `mcts build legacy-fixtures` | Plan/Apply per-live-backend PGO+BOLT+`mimalloc` pipeline; optional local legacy evidence generator for Q6 | ✅ Done (`rustPgoBoltPlan` includes the documented `lld` linker flag; `legacy-fixtures` requires an explicit ignored/external output path) | Sprint 4.5, Sprint 5.3, Sprint 6.2, Sprint 6.4, Sprints 8.4-8.6, Sprint 8.8 |

## Transcript Codec and Determinism

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Wire-format header | `src/MCTS/Transcript.hs`, `src/MCTS/Transcript/Codec.hs` | ✅ Done (v1 header includes workload; decoded one-game files set `runGameIndex` from the body `game_id`) | Sprint 2.1 |
| Per-move record codec | `src/MCTS/Transcript.hs`, `src/MCTS/Transcript/Codec.hs` | ✅ Done (records canonicalize visit pairs by action ID) | Sprint 2.1 |
| Single-byte action enumeration | `src/MCTS/Transcript/Action.hs`, `src/MCTS/Types.hs` | ✅ Done | Sprint 2.1 |
| Content-addressed hash (`sha256(run_config)`) | `src/MCTS/Transcript/Hash.hs`, `src/MCTS/Crypto/SHA256.hs` | ✅ Done (hash input matches the documented backend/workload/threading/RNG/seed/budget/game-index/c-param projection; `runGames` is excluded and normal batch writes retain only one-game transcript files) | Sprint 2.2 |
| Cache root resolution (`--cache-dir` → `./.mcts-cache/`) | `src/MCTS/Transcript.hs` | ✅ Done; no runtime environment-variable fallback | Sprint 2.2 |
| Git-style hash-prefix lookup (≥ 4 hex chars; `AppError TranscriptNotFound` / `AppError TranscriptAmbiguous`) | `src/MCTS/Transcript/Lookup.hs` | ✅ Done (`TranscriptRef` carries hash plus path; ambiguous candidates render as hashes) | Sprint 2.3 |
| `splitmix64(master_seed, game_index)` per-game seed derivation | `src/MCTS/Rng/Mix.hs` | ✅ Done | Sprint 2.5 |
| `--rng cpp` no-salt verification schedule | `src/MCTS/Rng/Mix.hs`; retired RNG source under `cpp-legacy/c-abi/rng.{h,cc}` | ✅ Done for the current live surface (verify/recompute paths use the same no-backend-salt schedule rather than a live shared `std::mt19937_64` byte stream; the legacy C++ loader retired with backend (i)) | Sprint 4.3, Sprint 7.2, Sprint 8.4 |
| `--rng native` backend-salted deterministic seed schedule | `src/MCTS/Rng/Mix.hs`, `src/MCTS/Driver.hs`, `src/MCTS/Driver/ForeignSearch.hs`, `src/MCTS/Engine/Recompute.hs`, `src/MCTS/Engine/ForeignRecompute.hs`; C++ and Rust search kernels mirror the splitmix-compatible schedule | ✅ Done for the current contract (`backendNativeSalt` distinguishes benchmark streams under `--rng native`; `--rng cpp` keeps salt zero for bit-equality cohorts. C++/Rust xoshiro helper modules remain present but the live FFI search path currently ignores the RNG-kind selector and consumes the splitmix-compatible schedule; fastest per-language RNG swaps are future profiling work, not an active plan blocker.) | Sprint 2.5, Sprint 7.2 |
| Engine envelope codec (envelope block in transcript header; cohort-invariant vs per-backend-slot fields; excluded from the backend-specific `sha256(RunConfig)` cache key) | `src/MCTS/Transcript.hs` | ✅ Done (the encoded block matches the documented C ABI/wire layout; backend and display/cache `build_id` convenience fields stay out of the wire payload) | Sprint 2.6 |
| Per-backend envelope capture (build-id, compiler ID/version, fp_flags, libm_id, cpu_features, fp_env) | `<backend>/c-abi/envelope.{h,cc}` (Phase 4/5/6 for cpp/rust); `src/MCTS/Engine/Envelope.hs` (Phase 3 for haskell); `src/MCTS/FFI/Common.hs` (`engineEnvelopeToEnvelope`) | ✅ Done (Haskell logical envelope module; C++ runtime CPU/FP/libm probes + post-link build-id patch; Rust runtime feature/libm probes + build-id section patch; Haskell conversion of live C ABI envelopes into transcript envelopes) | Sprint 3.6, 4.7, 5.5, 6.5, 7.5 |
| Equity sidecar codec (`.eq` + `.envelope` neighbour, atomic-write, multi-build cohabitation) | `src/MCTS/Transcript/EquitySidecar.hs` | ✅ Done (binary `MEQ1` codec, temp-file + fsync + rename writes, sidecar origin helpers, and multi-build cache layout) | Sprint 2.7 |
| Foreign-engine recompute (`mcts_<backend>_recompute_move` FFI; in-process `Recompute.hs` for haskell) | per-backend C ABI + `src/MCTS/Engine/Recompute.hs` + `src/MCTS/Engine/ForeignRecompute.hs` | ✅ Done at the Sprint 6.5 surface and reduced by retirement (in-process `Recompute.hs` covers Haskell; Rust (iv) exposes `mcts_rust_recompute_move` with real parent-perspective `chosen_equity`; retired C++ recompute surfaces remain archived in source and frozen sidecars, while live dispatch only loads Rust; `MCTS.Engine.ForeignRecompute.foreignRecomputeEqStream` drives the FFI through a transcript to emit an `EqStream`) | Sprint 3.6, 4.7, 5.5, 6.5, Sprints 8.4-8.6 |
| Layered envelope verify (`CohortLevel` + `BackendSlot` rule with `--allow-stale`) | `src/MCTS/Verify/Envelope.hs`, `src/MCTS/Driver/Dispatch.hs`, `src/MCTS/CLI/Verify.hs` | ✅ Done (validated against the corrected envelope wire payload and corrected canonical determinism digest) | Sprint 7.5 |
| Divergence-rate metric (`visit_disagreement_rate`, `move_disagreement_rate`, `equity_l2_drift`) | `src/MCTS/Verify/Divergence.hs` | ✅ Done at the Sprint 7.5 surface (`divergenceRate` transcript-pair metric, `divergenceVsEqStream` foreign-recompute scoring with real `equity_l2_drift`; `mcts inspect divergence` emits one row per cached sidecar plus one row per available foreign cdylib through `MCTS.Engine.ForeignRecompute`) | Sprint 7.5 |

The engine envelope is a **cross-component invariant**: every transcript
writer (Phases 3, 4, 5, 6 per-backend drivers) stamps it; every transcript
reader (the codec, `mcts verify`, `mcts inspect show --envelope`, `mcts
inspect replay`'s status line) inspects it; the report card surfaces its
match status. Adding a new substrate-affecting build dimension (e.g.,
switching from glibc to musl in the Dockerfile) requires updating the
envelope's `libm_id` capture path, not the determinism contract itself.

## CLI Doctrine Components

Components introduced by the doctrine adoption sprints scheduled in
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md) and the surfaces that
consume them. Citations name the doctrine sections they implement per standards rule L.

| Component | Doctrine Section | Status | Owning Sprint |
|-----------|------------------|--------|---------------|
| `CommandSpec` registry as source of truth | Automatically Generated Documentation; Command Topology | ✅ Done | Sprint 1.2 |
| `OptionSpec` record fields (`longName`, `shortName`, `metavar`, `description`, `required`) | Automatically Generated Documentation | ✅ Done | Sprint 1.2 |
| Per-leaf `Example` entries on every `CommandSpec` | Automatically Generated Documentation | ✅ Done | Sprint 1.2 |
| Parser generated from the registry (parser is a renderer, not the source of truth) | Command Topology | ✅ Done | Sprint 1.2 |
| Parser-test category via `execParserPure` | Testing Doctrine → Parser Tests | ✅ Done | Sprint 1.2 |
| `mcts commands --tree` and `mcts commands --json` introspection | Progressive Introspection | ✅ Done | Sprint 1.2 |
| `Subprocess` ADT plus `runStreaming` / `capture` interpreter; pure `renderSubprocess` | Architecture → Subprocesses as Typed Values | ✅ Done (`MCTS.Subprocess` interprets the typed value through `typed-process`) | Sprint 1.6 |
| Forbidden subprocess primitives (`callProcess`, `readCreateProcess`, `System.Process` constructors, `typed-process` smart constructors) | Architecture → Subprocesses as Typed Values | ✅ Done (`.hlint.yaml` carries the full direct-primitive rule set and container-pinned HLint enforces `Error:` findings; the source walker provides an additional textual guard) | Sprint 1.6 |
| `Plan` / `apply` boundary with `--dry-run` and `--plan-file <path>` | Plan / Apply | ✅ Done (`MCTS.Plan` owns `buildPlan`, `applyPlan`, `applySubprocessPlan`, `applyWithEnv`, and `applySubprocessWithEnv`; every current Plan/Apply leaf declares `--dry-run` and `--plan-file` in `CommandSpec`) | Sprint 1.5 |
| `prerequisiteRegistry` with `nodeId`, `nodeDescription`, remedy hint, transitive closure | Prerequisites as Typed Effects | ✅ Done (real executable/version probes for build/test commands, exact GHC/Cabal, LLVM/BOLT 19, Rust 1.95.0, LLD 19, `mimalloc`, foreign smoke shared libraries, and per-backend profile directories; build and Cabal-backed test plans check closure before apply) | Sprint 1.7 |
| Single `Env` record threaded via `ReaderT Env IO` | Application Environment | ✅ Done (`MCTS.Env` declares `Env`, `App`, `runAppIO`, `askEnv`, `withTestClock`, generated-registry fields, output options, cache override, log handle, raw args, and prerequisite registry; public runners return `Env.App ExitCode`) | Sprint 1.8 |
| Single `AppError` ADT (`TranscriptNotFound`, `TranscriptAmbiguous`, `TranscriptFormatUnsupported`, `VerifyMismatch`, `VerifyLengthMismatch`, `VerifyTerminatorMismatch`, `VerifyCohortTooSmall`, `RecomputeMismatch`, `LegacyParityRolloutOverflow`, `ArchEnvelopeMismatch`, `EngineEnvelopeMismatch`, `PrerequisiteUnmet`, `SubprocessFailed`, `FFIFailure`, `DocsCheckDrift`, `UnknownCommand`, `InvalidMove`, `ParseError`, `IOErrorText`) | Error Handling | ✅ Done | Sprint 1.9 |
| `renderError :: AppError -> Text` boundary | Error Handling | ✅ Done (`MCTS.Error.renderError` is canonical; `MCTS.CLI.Output` re-exports it and owns final string/color rendering at stdout/stderr boundaries) | Sprint 1.9 |
| HLint rules refusing `print`, `exitFailure`, direct terminal formatting outside the output module | Error Handling | ✅ Done (`.hlint.yaml` rule set present; container-pinned HLint rejects `Error:` findings) | Sprint 1.4 |
| `--format json\|table\|plain` (default `table` on TTY else `plain`) | Output Rules | ✅ Done | Sprint 1.9 |
| `--color auto\|always\|never` plus `--no-color` | Output Rules | ✅ Done (`--color always` colors rendered errors at the output boundary; `--color never` / `--no-color` preserve plain text) | Sprint 1.9 |
| `fourmolu.yaml` 12-setting list at repo root | Lint, Format, and Code-Quality Stack → Pinned fourmolu.yaml | ✅ Done (the committed file is the formatter SSoT; governed docs link to it instead of duplicating a conflicting YAML body) | Sprint 1.4 |
| `cabal format` temp-file round-trip byte-equality check | Lint, Format, and Code-Quality Stack | ✅ Done (`mcts-haskell-style` runs the temp-file round-trip and requires container-installed `fourmolu-0.19.0.1` / `hlint-3.10` built with style GHC `9.12.4`) | Sprint 1.4 |
| `forbiddenPathRegistry` (`.github/workflows/`, `.husky/`, `.githooks/`, `.pre-commit-config.yaml`, `pre-commit-*.yaml`, root `Makefile`/`justfile`/`Taskfile.yml`, host `.build/`, `bootstrap/`, repository `.sh` wrappers) | Lint, Format, and Code-Quality Stack → Forbidden Surfaces | ✅ Done (typed `forbiddenPathRegistry :: [ForbiddenPath]` value in `MCTS.CLI.Lint`; the Compose-only doctrine update added `bootstrap/` and recursive `*.sh` refusal plus a unit expectation, validated on 2026-05-18 by `mcts-unit`, `lint files`, `lint all`, and `check-code` through Compose) | Sprint 1.4 |
| `GeneratedSectionRule` registry for marker-delimited generated regions | Generated Artifacts → The generated-section registry | ✅ Done (`MCTS.Generated.Sections` owns `GeneratedSectionRule`, `generatedSectionRules`, `spliceMarkerRegion`, `applyGeneratedSection`, `checkGeneratedSection`; `runDocs` traverses the non-empty registry and renders `command-matrix`) | Sprint 1.3 |
| `trackingGeneratedPaths` registry for fully-generated files (manpages, shell completions) | Generated Artifacts → Two categories of generation | ✅ Done (`MCTS.Generated.Paths` owns the fully-generated file registry wired through `mcts docs check/generate` and `mcts lint files`) | Sprint 1.3 |
| Canonical property-test invariants (`decode . encode == id`, `render is deterministic`, `parser roundtrips`) | Test Categories → Property Tests | ✅ Done (`mcts-unit` combines QuickCheck transcript roundtrips with semantic renderer assertions and parser checks; no checked-in golden providers remain) | Sprint 7.1, Sprint 8.8 |
| GADT-indexed `VerifyBackend` type excluding retired backends at the type level | GADT-Indexed State Machines | ✅ Done (`src/MCTS/Types.hs` defines `VRust` and `VHaskell`; `src/MCTS/CLI/Parser.hs` rejects `cpp-legacy`, `cpp-imperative`, and `cpp-functional` for default verify, and `VerifyCommand` stores `[VerifyBackend]`) | Sprint 7.2, Sprints 8.5-8.6 |
| Retired `LegacyParityBackend` parser surface | GADT-Indexed State Machines | ✅ Retired (Sprint 7.2's pre-retirement `LegacyParityBackend` surface was removed in Sprint 8.4 with `mcts verify legacy-parity`; Q7 is now historical backend (i) liveness evidence) | Sprint 7.2, Sprint 8.4 |
| Cabal-manifest toolchain pin (`tested-with: ghc ==9.14.1` in `mcts.cabal`, `with-compiler: ghc-9.14.1` in `cabal.project`) | Toolchain pinning | ✅ Done | Sprint 1.1 |
| Library-first layout audit (thin `app/Main.hs`, logic in `src/MCTS/`) | Project Structure | ✅ Done | Sprint 1.1 |
| Durable CLI documentation artefacts (`documents/cli/commands.md`, `share/man/man1/mcts*.1`, `share/completion/{bash,zsh,fish}/`) | Automatically Generated Documentation | ✅ Done | Sprint 1.3 |
| Standardized library set audit in `mcts.cabal` (`optparse-applicative`, `text`, `bytestring`, `aeson`, `prettyprinter*`, `ansi-terminal`, `path`, `path-io`, `typed-process`, `safe-exceptions`, `tasty*`, `temporary`, plus deviations `brick` + `vty`) | Overview → standardized stack | ✅ Done (standard library/test dependencies declared; `brick` + `vty` are present for `MCTS.CLI.Tui.{Board,Play,Replay}` only) | Sprint 1.1 |

## Test Stanzas

Per doctrine `Test Organization`, each tier is a separate Cabal `test-suite` with
`type: exitcode-stdio-1.0`; each stanza has its own `tasty` runner, and a single
`tasty` tree spanning all tiers is forbidden. The current baseline uses
`runBatchDispatch` for the operator-facing verify cohort, so foreign backends run
through live FFI when their artefacts are present and fall back to the in-process runner
only when a shared library is absent.

| Stanza | Tier | Scope | Status | Owning Sprint |
|--------|------|-------|--------|---------------|
| `mcts-unit` | Pure logic | Current `test/unit/Main.hs` uses a fine-grained `tasty` tree with 26 tests grouped by CLI/parser, transcripts/cache, engine/RNG, envelopes/sidecars, plans/subprocesses, and renderers/TUI dispatch. Coverage includes command registry/parser smoke, `execParserPure` happy/failure paths, SHA-256, all-action notation roundtrips, transcript roundtrip, a `tasty-quickcheck` transcript round-trip property, envelope/cache-key checks, sidecars, `inspect show`, `inspect list --format json`, `renderError`, TUI board/status/replay layout, divergence metrics, split engine/RNG/FFI fixture checks, and semantic renderer assertions without checked-in golden providers. | ✅ Done | Sprint 7.1, Sprint 8.8 |
| `mcts-integration` | Live integration baseline plus bounded FFI smoke | Current `test/integration/Main.hs` uses a `tasty` runner and checks same-backend determinism directly through `MCTS.Driver`, full decoded real `mcts` binary transcript determinism through `MCTS.Subprocess.capture` for Haskell and every built live foreign backend, sidecar origin markers, bounded measured report-card divergence building, cached recompute-sidecar consumption through the real `mcts inspect divergence` subprocess, bounded dynamic-FFI smoke games, live `mcts_<backend>_get_envelope` loading, live transcript-envelope stamping, backend-slot stale hard-fail/`--allow-stale` warning behavior for Rust when its shared library is present, and synthetic retired-backend evidence in temporary roots. | ✅ Done | Sprint 7.1, Sprints 8.4-8.6, Sprint 8.8 |
| `mcts-cross-backend` | Round-robin verify | Current `test/cross-backend/Main.hs` uses a `tasty` runner for rollout and self-play `verify` cohorts under `--rng cpp` covering backends `(iv)`, `(v)` through `runBatchDispatch`; backends `(i)`, `(ii)`, and `(iii)` are rejected by the typed `VerifyBackend` parser/runtime cohort checks; any `VerifyMismatch` fails the focused cases and the bounded canonical report-card cohort; synthetic comparator coverage asserts digest-first equivalence and length-aware extra-game, extra-move, and terminator mismatch surfaces | ✅ Done | Sprint 7.2, Sprints 8.5-8.6 |
| `mcts-legacy-parity` | Legacy-envelope verify | Retired in Sprint 8.4 with backend (i). Q7 liveness/overflow is now historical evidence and is not a normal test-suite input. | ✅ Retired | Sprint 7.2, Sprint 8.4 |
| `mcts-haskell-style` | Lint | `test/haskell-style/Main.hs` checks tab characters plus a conservative forbidden-symbol subset in Haskell sources, rejects supported-path partial functions under `src/` and `app/`, runs `cabal format` through a temp-file round-trip, and requires `/opt/mcts-style-tools/bin/fourmolu --mode check` / `/opt/mcts-style-tools/bin/hlint --with-group=default --with-group=extra` inside the container with only `Error:` findings blocking | ✅ Done | Sprint 1.4 |

## POC Report-Card Knobs

Implemented in `MCTS.CLI.Test` and mirrored in `cabal.project` comments for
operator auditability; see
[phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md).

| Knob | Value | Purpose |
|------|-------|---------|
| `G_R` | `1_000` | Random-rollouts game count (Q1) |
| `G_S` | `4` | Self-play game count (Q2 / Q5) |
| `G_V` | `4` | Cross-backend verify game count (Q3) |
| `G_LP` | `2` | Historical legacy parity game count (Q7; retired evidence metadata) |
| `S_BENCH` | `500` | Per-move sim budget for bench self-play |
| `S_VERIFY` | `500` | Per-move sim budget for verify self-play |
| `S_LP_SIMS` | `10_000` | Historical per-move sim budget for legacy-parity self-play |
| `S_LP` | `42` | Historical legacy-parity fixture seed (chosen so (i) did not throw) |

## Toolchain

| Component | Pinned Version | Purpose | Status | Owning Sprint |
|-----------|----------------|---------|--------|---------------|
| GHC | `9.14.1` | Haskell compiler for backend (v) and the CLI binary | ✅ Done (`mcts.cabal` / `cabal.project` / Docker pins and exact prerequisite probe landed) | Sprint 1.1 |
| Cabal | `3.16.1.0` | Haskell build tool; per-stanza `type: exitcode-stdio-1.0` | ✅ Done (`cabal.project` / Docker pins and exact prerequisite probe landed) | Sprint 1.1 |
| Style-tool GHC | `9.12.4` | Isolated compiler for installing `fourmolu-0.19.0.1` and `hlint-3.10` into `/opt/mcts-style-tools/bin/` inside the container; not used for project builds | ✅ Done (Docker install and style stanza path invocation landed) | Sprint 1.4 |
| GCC | Latest stable on `ubuntu:24.04` | C++23 compiler for backends (i), (ii), (iii). Clang not supported. | ✅ Done for the container baseline (Docker installs the distro `build-essential`/`g++` toolchain and the backend build plans compile the C++23 engines through `mcts build`; the exact patch version intentionally follows the pinned Ubuntu base image) | Sprint 4.1, Sprint 5.1 |
| LLVM | `19` in `docker/Dockerfile` | Shared by GHC `-fllvm` and BOLT post-link | ✅ Done (Docker installs LLVM/LLD/BOLT 19 and prerequisite probes validate `19.x`) | Sprint 1.1 |
| `rustup` | Latest stable installer with Rust `1.95.0` selected in `docker/Dockerfile` | Rust toolchain manager for backend (iv) | ✅ Done for the Phase 6 build surface (Docker install, prerequisite probes, and `mcts build rust` PGO/BOLT install path validate) | Sprint 6.4 |
| Rust | `1.95.0` in `docker/Dockerfile` | Rust compiler for backend (iv) | ✅ Done for the Phase 6 build surface (Docker pin, prerequisite probes, Rust FFI integration, `lld` linker flag in both PGO stages, and canonical `mcts build rust` path validate) | Sprint 6.4 |
| `mimalloc` | Ubuntu `libmimalloc-dev` in `docker/Dockerfile`; Rust crate `mimalloc = "0.1"` locked in `rust/Cargo.lock` | System allocator for backends (ii), (iii), (iv) | ✅ Done for the current baseline (Docker package and library-path probe landed because the Ubuntu package does not ship `mimalloc.pc`; Rust uses `mimalloc::MiMalloc`; C++ build plans link the system library rather than requiring a static archive) | Sprint 5.3, Sprint 6.4 |
| BOLT | LLVM `19` package in `docker/Dockerfile` | Post-link binary reordering after PGO for backends (ii), (iii), (iv) | ✅ Done for the implemented build surface (Docker pin and prerequisite probe landed; Rust BOLT training/install validates on amd64; C++ shared-library plans fall back to the PGO artefact when no `.fdata` exists, and Sprint 8.3 records that as the measured baseline rather than an open blocker) | Sprint 5.3, Sprint 6.4, Sprint 8.3 |
| `ghcup` | Latest stable binary installed in the container | Manages the pinned GHC and Cabal versions inside the container | ✅ Done (Docker installs `ghcup`; `prerequisiteRegistry` carries a `ghcup` node) | Sprint 1.1 |
| Target platforms | `amd64` Linux + `arm64` Linux | Both architectures supported; reproducibility envelope is per-architecture (transcripts and report-card metadata carry a `host_arch` tag); cross-arch bit-equality not guaranteed. See [00-overview.md → Hard Constraints item 36](00-overview.md) and [../documents/engineering/determinism_contract.md → Architecture Envelope](../documents/engineering/determinism_contract.md) | ✅ Done / pinned envelope | n/a |

## State Locations

| State Class | Authority | Durable Home | Notes |
|-------------|-----------|--------------|-------|
| Transcript cache | `mcts` CLI | `--cache-dir <path>` → `./.mcts-cache/transcripts/<arch>/<sha>.tr` inside the container (arch ∈ `{amd64, arm64}`); per-transcript sidecar directory `./.mcts-cache/transcripts/<arch>/<sha>/<backend>-<build_label>.eq` plus `.envelope` neighbour for cached equity series | One-game transcript files are content-addressed by `sha256(run_config)`, where `run_config` includes backend and `game_index` (or `sha256(run_config \|\| move_history)` for `mcts play`-recorded transcripts); arch-partitioned per [../README.md → Architecture envelope](../README.md); sidecar `.eq` files multi-build-cohabitable (one per `(backend, build)` slot; live labels use the `engine_build_id` prefix and logical all-zero envelopes use `<backend>-logical`), prunable via `mcts inspect cache prune`; cross-backend verify compares decoded determinism payloads rather than cache filenames; no runtime environment-variable fallback |
| Optional legacy evidence | `mcts build legacy-fixtures` from the `cpp-legacy/legacy-core/` port of `~/MCTS_legacy/` | Explicit operator-provided output directory, preferably outside the repo or under an ignored local artifact root | Optional Q6 reproduction evidence; not required by normal validation and not checked into the repo |
| Retired-backend evidence | `mcts` CLI on retirement or external archival process | Plan/docs plus optional external/ignored artifact storage | Historical transcripts and throughput captures may exist for audit, but generated evidence files are not repository validation inputs |
| Build outputs | `docker compose run --rm mcts mcts <command>` | Container-local `dist-newstyle/` plus per-backend `build/` / `target/` directories | Built artefacts live inside the Compose-built image or short-lived container filesystem; host-level `.build/` is unsupported |
| PGO profile directories | Two-stage PGO build harness | `rust/pgo-profile/` | Populated by the instrumented build; consumed by the optimised build; `cpp-imperative/pgo-profile/` and `cpp-functional/pgo-profile/` are retired reference residue |
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
| Cabal project definition | `cabal.project` | Repository-wide Cabal package-set definition with `with-compiler: ghc-9.14.1` and comments mirroring report-card constants |
| Formatter config | `fourmolu.yaml` | Pinned 12 doctrine-mandated settings at repo root |
| Backend (i) sources | `cpp-legacy/` | Retired verbatim re-port of `MCTS_legacy`, retained for reference and optional local Q6 evidence generation |
| Backend (ii) sources | `cpp-imperative/` | Retired maximally-tuned imperative C++23 reference plus documented Sprint 8.5 evidence |
| Backend (iii) sources | `cpp-functional/` | Retired functional-style C++23 reference plus documented Sprint 8.6 evidence |
| Backend (iv) sources | `rust/` | Rust `cdylib` with the pinned `[profile.release]` |
| Haskell tests | `test/` | Four live Cabal stanza modules. Generated transcripts, sidecars, report-card values, and renderer baselines are produced in memory or temporary directories during tests, not stored under `test/golden/` |
| Bench targets | `bench/` | Cabal benchmark targets (`criterion` / `tasty-bench`) for in-process timing |
| Docker development environment | `docker/Dockerfile`, root `compose.yaml` | `ubuntu:24.04` base with pinned GCC, LLVM, GHC, Cabal, Rust, a separate formatter-tools GHC for Fourmolu/HLint, copied project sources, and an installed `mcts`; all supported host work uses `docker compose run --rm mcts mcts <command>`. Repository `.sh` wrappers and `bootstrap/` helpers are forbidden workflow surfaces. The 2026-05-18 Compose-only doctrine update passed `mcts-unit`, `lint files`, `lint all`, and `check-code` through the root Compose service |
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
