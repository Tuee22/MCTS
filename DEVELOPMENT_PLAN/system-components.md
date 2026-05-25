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
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md),
[../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md)
**Generated sections**: none

> **Purpose**: Authoritative target component inventory for the MCTS Haskell CLI, the
> backend cohort, the transcript codec, the verification cohort, the Cabal test stanzas,
> and the retained state locations.

The inventory documents the authoritative end state and the current implementation
baseline. The intended architecture is a five-backend CLI: `cpp-legacy`,
`cpp-imperative`, `cpp-functional`, `rust`, and `haskell` remain first-class backend
slots. The stale two-backend drift from the 2026-05-19 cleanup is corrected: C++
parser/build/verify/FFI dispatch is live, Q3 covers `(ii)..(v)`, and Q6 is live
across `(i)..(v)`. The 2026-05-21 evidence-surface audit reopened focused
alignment sprints in Phases `1`, `2`, `5`, `6`, `7`, and `8`; the 2026-05-24
harmony sweep reopened and reclosed focused alignment sprints in Phases `1`,
`2`, `3`, `4`, and `7`. All reopened reclosure sprints have closed without
changing the five-backend hypothesis. The 2026-05-24 metric-semantics audit
reopened the benchmark/report-card metric suite: Sprint `3.8` has added explicit
terminal playout and search-iteration benchmark primitives, while historical
Q1/Q2/Q5 rows remain played-game evidence. Sprint `7.8` has refactored the report
card into unit-aware Q1a/Q1b/Q2/Q5 rows, and Sprint `8.11` has rerun parity.
Sprint `5.6` has corrected backend (ii)'s hot path with a compact bitfield board,
direct capped legal-move generation, and wavefront escapability checks; Phase `8`
Sprint `8.12` is active because the strengthened backend (ii) reopens the Haskell
parity evidence.
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) tracks stale surfaces
and cleanup ownership separately.

## Current Implementation Baseline

| Component | Current Worktree Evidence | Closure Gap |
|-----------|---------------------------|-------------|
| Cabal package and CLI | `mcts.cabal`, `cabal.project`, `app/Main.hs`, `src/MCTS/App.hs`; doctrine-standard library/test dependency set is declared; host validation enters through `docker compose run --rm mcts mcts check-code`; Docker installs the isolated style-tool GHC and formatter/hlint binaries plus the `mcts` executable | ✅ Done |
| Command registry | `src/MCTS/CLI/Spec.hs`, `src/MCTS/CLI/Parser.hs`; `mcts commands --tree` and `mcts commands --json` work; `commandParserInfo` renders the optparse-applicative subcommand topology from the registry tree, while leaf option parsers remain explicit semantic parsers in `Parser.hs`; README concrete invocations use the Compose entrypoint around the same logical leaf commands; `bench` and `verify` require explicit backend/games/seed inputs where governed, `verify` defaults to single-threaded `--rng cpp`, and `play` carries `--backend`, `--side`, `--vs`, `--rng`, `--seed`, `--max-plies`, and `--cache-dir` | ✅ Done |
| Transcript/cache baseline | `src/MCTS/Transcript.hs`, `src/MCTS/Crypto/SHA256.hs`, `src/MCTS/Transcript/EquitySidecar.hs`, plus wrapper modules; `.mcts-cache/` ignored; one-game transcript cache writes use `runGameIndex` without rewriting `master_seed`; `inspect list` / `inspect show --envelope` / `inspect show --with-equity` / `inspect replay` / `inspect cache list` / `inspect cache prune` are implemented; transcript and sidecar writes use same-directory temp files, fsync, rename, and parent-directory fsync; `MCTS.Engine.ForeignRecompute.foreignRecomputeEqStream` can score foreign recompute streams through `mcts inspect divergence` and can fill replay overlays when cdylibs are present; FFI-produced transcripts carry live envelopes when cdylibs are present. Sprint `2.8` closed strict v1 transcript/envelope version wording, action-domain wording, logical sidecar stem normalization, and exact originator sidecar identity; Sprint `2.9` closed envelope wire-slot/gating wording; Sprint `7.6` closed inspect/replay/divergence labeling on top of that corrected cache contract. | ✅ Done |
| In-process MCTS engine | `src/MCTS/Engine.hs`, `src/MCTS/Engine/Envelope.hs`, `src/MCTS/Driver.hs`, `src/MCTS/Search/Arena.hs`, `src/MCTS/Search/UCT.hs`, `src/MCTS/Verify.hs`; the Haskell engine uses strict `Word64` board slots/bitsets, real recursive UCT in the `ST` monad over a structure-of-arrays `STUArray` arena, a sentinel `terminalOutcome` path for the rollout inner loop, signed-modulo rollout move selection per the byte-consumption contract, and per-move search dispatch from the driver. The current driver allocates a fresh arena for each move search; `treeReroot` is a tested primitive, not a game-loop persistence path. `MCTS.Verify` dispatches through `MCTS.Driver.Dispatch.runBatchDispatch`; Q3 reaches `(ii)..(v)`. It compares a canonical byte-projected determinism payload digest first, then runs a length-aware game/move/terminator scan only on digest mismatch. | ✅ Done |
| Foreign backend homes | `cpp-legacy/` contains the mechanically imported legacy core plus C ABI wrappers and the optional local `legacy-to-wire` evidence generator reached through `mcts build legacy-fixtures`; `cpp-imperative/` contains the imperative steelman with `FastBoard` compact bitfield state, direct capped legal-move generation, numeric action IDs, and wavefront escapability checks; `cpp-functional/` contains the functional-style C++ steelman; `rust/src/` ships a real arena MCTS, a dormant xoshiro256++ helper module, the splitmix-compatible live search schedule, the full Corridors gameplay port (8x8 bitfield walls, iterative BFS escapability, post-move 180-degree flip via `u64::reverse_bits`), and the search/recompute/read-visits/envelope C ABI. Haskell dispatch loads all four foreign backend families through `src/MCTS/FFI/Cpp*`, `src/MCTS/FFI/Rust.hs`, and `src/MCTS/Driver/Dispatch.hs` when canonical shared libraries are present. Sprint `5.5` closed backend (ii)'s compact ABI contract; Sprint `5.6` closed backend (ii)'s compact-board hot path; Sprint `6.6` closed backend (iii)/(iv) ABI docs and Rust build-artifact wording. | ✅ Done |
| Test stanzas | `test/unit`, `test/integration`, `test/cross-backend`, `test/legacy-parity`, `test/haskell-style`; each stanza has its own `tasty` runner; host validation gate is `docker compose run --rm mcts mcts test all`. Unit renderer/codec checks use semantic assertions and in-memory bytes; `test/golden/` generated inputs and `tasty-golden` are absent. | ✅ Done |
| Generated docs gate | `src/MCTS/CLI/Docs.hs`, `src/MCTS/Generated/Paths.hs`, `src/MCTS/Generated/Sections.hs`, `documents/engineering/cli_command_surface.md`, `documents/cli/commands.md`, `share/man/man1/mcts.1`, `share/completion/{bash,zsh,fish}/`; `mcts docs check` and `mcts lint files` check tracked generated-file drift; `mcts lint docs --write` regenerates fully generated files and marker-delimited sections before rechecking, while `mcts lint files --write` rewrites fully generated command/man/completion files from the generated-file registry; `command-matrix` is a marker-delimited governed-doc section rendered from `CommandSpec`; governed-doc `**Generated sections**:` metadata must match physical markers and the generated-section registry. | ✅ Done |
| Benchmark metric taxonomy | `documents/engineering/benchmark_metrics.md` defines terminal playout throughput (`playouts/s`), search-iteration throughput (`search-iters/s`), and played-game throughput (`games/s`). `mcts bench terminal-playouts` and `mcts bench search-iters` implement the primitive units across the five backend slots; `bench rollouts` remains a legacy command name for played-game throughput with one search iteration per real move; played-game benchmark renderers expose only `games/s`. The report card emits explicit Q1a/Q1b/Q2/Q5 unit fields. Sprint `8.11` closed the prior parity rerun against those units; Sprint `8.12` is active because backend (ii)'s corrected hot path changes the parity target. | ✅ Done |
| PGO/BOLT training workload | `src/MCTS/CLI/Build.hs` owns the Dockerfile-invoked `cppPgoBoltPlan` and `rustPgoBoltPlan` training runs. PGO uses a bounded metric-suite profile suite: `bench terminal-playouts` and `bench search-iters` with `--count 64` and `--max-plies 60`, plus legacy `bench rollouts` and `bench selfplay`, ST plus MT8, native RNG, seeds `42` and `424242`, and played-game `--max-plies 1`; per seed it runs rollout ST/MT8 with 2 games each and self-play ST/MT8 with 1 game each at `--sims 500`. BOLT uses the same workload/threading/seed shape with primitive `--count 16`, 1 game per played-game workload/threading pair, and shorter self-play `--sims 100`. C++ profile training uses scoped dynamic-library loading plus explicit GCOV dump hooks; Rust keeps the library pinned and relies on process-exit `.profraw` emission. The 2026-05-24 aggregate rebuild validated this suite before report-card measurement. | ✅ Done |

## Backends

| Backend | Identifier | Implementation Path | Linkage | Status | Owning Phase |
|---------|------------|---------------------|---------|--------|--------------|
| (i) C++ legacy port | `cpp-legacy` | `cpp-legacy/` | C ABI via Haskell FFI | ✅ Done (verbatim legacy port, live C ABI, legacy-fixtures generator, dynamic dispatch/envelope/recompute surfaces for Q6 legacy-envelope evidence where applicable) | [Phase 4](phase-4-cpp-legacy-port-and-ffi-bridge.md), [Phase 8](phase-8-haskell-performance-parity-closure.md) |
| (ii) C++ imperative steelman | `cpp-imperative` | `cpp-imperative/` | C ABI via Haskell FFI | ✅ Done for live parser/build/verify/FFI dispatch, Q3 participation, canonical fail-closed C++ PGO/BOLT Plan/Apply wiring, governed compact C ABI contract, Sprint `5.6` compact-board hot path, Sprint `8.10` bounded played-game profile training, and Sprint `8.11` bounded metric-suite profile training. Phase `8` Sprint `8.12` is active for Haskell parity against this corrected target. | [Phase 5](phase-5-cpp-imperative-steelman.md), [Phase 8](phase-8-haskell-performance-parity-closure.md) |
| (iii) C++ functional-style | `cpp-functional` | `cpp-functional/` | C ABI via Haskell FFI | ✅ Done for live parser/build/verify/FFI dispatch, Q3 participation, shared fail-closed C++ PGO/BOLT Plan/Apply wiring, compact ABI wording, Sprint `8.10` bounded played-game profile training, and Sprint `8.11` bounded metric-suite profile training | [Phase 6](phase-6-cpp-functional-and-rust.md), [Phase 8](phase-8-haskell-performance-parity-closure.md) |
| (iv) Rust | `rust` | `rust/`, `src/MCTS/Driver/Rust.hs` | C ABI via Haskell FFI, `cdylib` | ✅ Done for real arena MCTS with UCT-1, splitmix-compatible live search schedule, dormant xoshiro256++ helper module, full search/recompute/read-visits/envelope C ABI, real Corridors gameplay in `rust/src/board.rs`, local `SystemMiMalloc` global allocator over the container `libmimalloc`, single optimized FFI artefact, fail-closed Rust PGO/BOLT plan, Sprint `8.10` bounded played-game profile training, and Sprint `8.11` bounded metric-suite profile training | [Phase 6](phase-6-cpp-functional-and-rust.md), [Phase 8](phase-8-haskell-performance-parity-closure.md) |
| (v) Haskell | `haskell` | `src/MCTS/Engine.hs`, `src/MCTS/Engine/Envelope.hs`, `src/MCTS/Driver.hs`, `src/MCTS/Search/Arena.hs`, `src/MCTS/Search/UCT.hs` | Native (in-process) | ✅ Done for the Phase 3 correctness baseline, historical smoke-baseline evidence, and optimized-C++ Phase 8 evidence | [Phase 3](phase-3-haskell-engine.md), [Phase 8](phase-8-haskell-performance-parity-closure.md) |

## Haskell CLI Surface

| Surface | Command | Purpose | Status | Owning Sprint |
|---------|---------|---------|--------|---------------|
| Terminal playout benchmark | `mcts bench terminal-playouts` | Direct primitive benchmark that runs random playouts from an explicit board position without allocating or updating an MCTS tree and reports `playouts/s`. Dynamic benchmark ABI hooks cover the four foreign backend families when their canonical shared libraries are present. | ✅ Done | Sprint 3.8 |
| Search-iteration benchmark | `mcts bench search-iters` | Direct primitive benchmark that times UCT/MCTS iterations at a fixed board position and reports `search-iters/s`. Dynamic benchmark ABI hooks cover the four foreign backend families when their canonical shared libraries are present. | ✅ Done | Sprint 3.8 |
| Legacy played-game rollout benchmark | `mcts bench rollouts` | Legacy command name. Measures complete played games with one search iteration per real move, exercising legal-move generation, move application, terminal detection, and the shared per-move search path. It does not measure terminal `playouts/s`; use `mcts bench terminal-playouts` for that primitive unit. Performance runs use each backend's native RNG contract. | ✅ Done as legacy played-game surface | Sprint 3.5 baseline; Sprint 3.8 primitive supplement |
| Self-play benchmark | `mcts bench selfplay` | Full UCT search with random-rollout leaf evaluation, adversarial self-play. Performance runs use each backend's native RNG contract. | ✅ Done | Sprint 3.5; foreign dispatch in Sprints 5.4, 6.2, 6.4; Phase 8 restoration |
| Rollouts verify | `mcts verify rollouts` | Live FFI-backed round-robin visit-count equality across `(ii)..(v)` under `--rng cpp`, using C++-generated verification seeds from the shared C++ RNG bridge; layered envelope checks with `--allow-stale`; digest-first canonical payload comparison with length-aware mismatch reporting | ✅ Done | Sprint 7.2, Sprint 7.5, Phase 8 restoration |
| Self-play verify | `mcts verify selfplay` | Live FFI-backed round-robin self-play visit-count equality across `(ii)..(v)` under the same C++-generated verification-seed contract and digest-first verifier comparator | ✅ Done | Sprint 7.2, Sprint 7.5, Phase 8 restoration |
| Legacy parity verify | `mcts verify legacy-parity {rollouts\|selfplay}` | Q6 five-backend legacy-envelope liveness/overflow check; uses the legacy-compatible envelope and does not require checked-in generated transcripts | ✅ Done | Sprint 7.2, Phase 8 restoration |
| Interactive game | `mcts play` | TUI human-vs-AI or AI-vs-AI spectate with live board rendering; parser and execution carry `--backend`, `--side`, `--vs`, `--rng`, `--seed`, `--max-plies`, and `--cache-dir`; the side named by `--side` is AI-controlled by `--backend`, `--vs` controls the opposite side in spectator mode, and omitted seeds come from `/dev/urandom` | ✅ Done | Sprint 7.4 |
| Transcript list | `mcts inspect list` | Non-interactive enumeration of the local transcript cache | ✅ Done | Sprint 2.4 |
| Transcript show | `mcts inspect show <hash-prefix>` | Non-interactive dump in legacy move notation, `--envelope` dump, optional `--with-equity` originator-sidecar read/recompute and stream-backed equity column | ✅ Done (cache misses never write foreign or fallback recompute streams under the originator label) | Sprint 2.4, Sprint 2.6, Sprint 7.6 |
| Transcript replay | `mcts inspect replay <hash-prefix>` | Interactive `brick` TUI for forward/back navigation with equity overlays; rows label originator, originator build-mismatch, foreign-view, unavailable, verified, and diverged states, with chosen-action divergence annotations where sidecars carry mismatched choices | ✅ Done | Sprint 7.4 |
| Sidecar cache list | `mcts inspect cache list` | Enumerate equity-sidecar `(backend, build)` slots cohabiting each cached transcript and mark each slot as originator, foreign, or unknown | ✅ Done on the Phase 2 sidecar-cache surface | Sprint 2.7 |
| Sidecar cache prune | `mcts inspect cache prune [--keep-current]` | Plan/Apply deletion of equity sidecars; `--keep-current` retains current logical build slots in the Phase 2 baseline | ✅ Done on the Phase 2 sidecar-cache surface; verify-time live-envelope stale detection is owned by Sprint 7.5 | Sprint 2.7 |
| Divergence matrix | `mcts inspect divergence <hash-prefix>` | Emit divergence-rate metrics (`visit-Δ`, `move-Δ`, `equity-L2`) for a single transcript and cached backend columns; report-card rows consume decoded verify transcripts consistent with the corrected canonical comparator | ✅ Done (live recompute rows cover every available foreign cdylib and docs match cached-vs-live row scope) | Sprint 7.5, Phase 8 restoration, Sprint 7.6 |
| Test runner | `mcts test all` / `mcts test <stanza>` | Plan/Apply over lint/docs prerequisites, warning-clean build, Cabal test stanzas, verify cohorts, and the measured report-card workload. The report card times primitive Q1a/Q1b rows through direct benchmark runners, played-game Q2 rows through the no-write batch runner, and Q5 search-iteration and played-game scaling separately, with typed prerequisite checks for Dockerfile-built backend artefacts before runtime apply; exact ordering is owned by `unit_testing_policy.md` | ✅ Done | Sprint 7.2, Sprint 7.3, Sprint 7.8, Sprint 8.8, Phase 8 restoration |
| Parity anchor | `mcts test parity-anchor <baseline> <candidate>` | Plan/Apply Q1/Q2 parity-anchor measurement for explicit backend pairs using the same build prerequisites and tolerance as the Phase 8 report-card proof | ✅ Done | Sprint 8.3, Phase 8 restoration |
| Lint stack | `mcts lint files\|docs\|haskell\|all` | Whitespace, final newline, forbidden paths, generated sections, governed-doc generated-section metadata agreement, mandatory container-owned formatter/hlint path, partial-function policy, and `cabal format`; leaf `--write` flags repair fixable drift before rechecking; host fallback is unsupported | ✅ Done | Sprint 1.4, Sprint 1.10, Sprint 1.11 |
| Docs generation | `mcts docs check` / `mcts docs generate` | Paired generated-section check and write per the `GeneratedSectionRule` registry plus governed-doc metadata agreement | ✅ Done | Sprint 1.3, Sprint 1.10 |
| Command introspection | `mcts commands [--tree\|--json]` | Flat list, tree rendering, or JSON command schema from the `CommandSpec` registry | ✅ Done | Sprint 1.2 |
| Focused help | `mcts help <subcommand>` | Focused pointer for a target command; the runner prints the target and directs operators to `docker compose run --rm mcts mcts commands --tree` for the command tree | ✅ Done | Sprint 1.2 |
| Code quality gate | `mcts check-code` | Doctrine-alignment enforcement, formatter, hlint, generated-doc checks, warning-clean build, forbidden-path scan | ✅ Done | Sprint 1.4, Sprint 1.10 |
| Per-backend build harness | `mcts build cpp-legacy`, `mcts build cpp-imperative`, `mcts build cpp-functional`, `mcts build rust`, plus `mcts build legacy-fixtures` | Dockerfile-invoked Plan/Apply build recipes; C++ and Rust steelman leaves run their PGO+BOLT+`mimalloc` paths during image construction, fail closed on missing profile/BOLT data, patch BOLT-produced shared objects with LLVM objcopy, smoke the installed bolted canonical libraries before runtime validation, and train on the bounded metric-suite profile suite. The optional local legacy audit fixture generator remains external/ignored | ✅ Done | Sprint 4.1, Sprint 4.4, Sprint 5.3, Sprint 6.2, Sprint 6.4, Sprint 8.8, Phase 8 restoration, Sprint 8.10, Sprint 8.11 |

## Transcript Codec and Determinism

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Wire-format header | `src/MCTS/Transcript.hs`, `src/MCTS/Transcript/Codec.hs` | ✅ Done (v1 header includes workload; decoded one-game files set `runGameIndex` from the body `game_id`) | Sprint 2.1 |
| Per-move record codec | `src/MCTS/Transcript.hs`, `src/MCTS/Transcript/Codec.hs` | ✅ Done (records canonicalize visit pairs by action ID) | Sprint 2.1 |
| Single-byte action enumeration | `src/MCTS/Transcript/Action.hs`, `src/MCTS/Types.hs` | ✅ Done (governed docs match the implemented `0..208` `Action` domain; `209..254` are reserved bytes and `255` is sentinel-only, not an admitted `Action`) | Sprint 2.1, Sprint 2.8 |
| Content-addressed hash (`sha256(run_config)`) | `src/MCTS/Transcript/Hash.hs`, `src/MCTS/Crypto/SHA256.hs` | ✅ Done (hash input matches the documented backend/workload/threading/RNG/seed/budget/game-index/c-param projection; `runGames` is excluded and normal batch writes retain only one-game transcript files) | Sprint 2.2 |
| Cache root resolution (`--cache-dir` → `./.mcts-cache/`) | `src/MCTS/Transcript.hs` | ✅ Done; no runtime environment-variable fallback | Sprint 2.2 |
| Git-style hash-prefix lookup (≥ 4 hex chars; `AppError TranscriptNotFound` / `AppError TranscriptAmbiguous`) | `src/MCTS/Transcript/Lookup.hs` | ✅ Done (`TranscriptRef` carries hash plus path; ambiguous candidates render as hashes) | Sprint 2.3 |
| `splitmix64(master_seed, game_index)` per-game seed derivation | `src/MCTS/Rng/Mix.hs` | ✅ Done | Sprint 2.5 |
| `--rng cpp` shared C++ verification stream | `src/MCTS/Rng/Cpp.hs`, `src/MCTS/Rng/Mix.hs`; C++ RNG source under `cpp-legacy/c-abi/rng.{h,cc}` builds the dedicated `cpp-legacy/build/libmcts_cpp_rng.so` bridge, and equivalent seed consumers live in the steelman backends | ✅ Done (equivalence tests use C++-generated verification seeds from `cpp_rng_fill_u64` when the dedicated RNG shared library is present; clean stanzas fall back to the deterministic in-process schedule when no shared library exists) | Sprint 4.3, Sprint 7.2, Phase 8 restoration |
| `--rng native` backend-native deterministic RNG | `src/MCTS/Rng/Mix.hs`, `src/MCTS/Driver.hs`, `src/MCTS/Driver/ForeignSearch.hs`, `src/MCTS/Engine/Recompute.hs`, `src/MCTS/Engine/ForeignRecompute.hs`; backend-native RNG code in C++/Rust/Haskell search kernels | ✅ Done (performance benchmarks use each backend's own fast RNG and never assert cross-backend bit-equality under `--rng native`) | Sprint 2.5, Sprint 7.2, Phase 8 restoration |
| Engine envelope codec (envelope block in transcript header; cohort-invariant vs per-backend-slot fields; excluded from the backend-specific `sha256(RunConfig)` cache key) | `src/MCTS/Transcript.hs` | ✅ Done (v1 reader rejects unsupported transcript/envelope versions and requires `envelope_offset == 48`; additive v1 envelope trailing bytes are covered by unit tests) | Sprint 2.6, Sprint 2.8 |
| Per-backend envelope capture (build-id, compiler ID/version, fp_flags, libm_id, cpu_features, fp_env) | `cpp-legacy/c-abi/mcts_cpp_legacy.{h,cc}`, `cpp-imperative/c-abi/mcts_cpp_imperative.{h,cc}`, `cpp-functional/c-abi/mcts_cpp_functional.{h,cc}`, `rust/src/envelope.rs`, `rust/src/c_abi.rs`; `src/MCTS/Engine/Envelope.hs` (Phase 3 for Haskell); `src/MCTS/FFI/Common.hs` (`engineEnvelopeToEnvelope`) | ✅ Done (Haskell logical envelope module; C++ runtime CPU/FP/libm probes + post-link build-id patch; Rust runtime feature/libm probes + build-id section patch; Haskell conversion of live C ABI envelopes into transcript envelopes) | Sprint 3.6, 4.2, 5.5, 6.5, 7.5 |
| Equity sidecar codec (`.eq` + `.envelope` neighbour, atomic-write, multi-build cohabitation) | `src/MCTS/Transcript/EquitySidecar.hs` | ✅ Done (logical sidecar stems normalize to `<backend>-logical`, and originator identity is backend/build/envelope exact) | Sprint 2.7, Sprint 2.8 |
| Foreign-engine recompute (`mcts_<backend>_recompute_move` FFI; in-process `Recompute.hs` for haskell) | per-backend C ABI + `src/MCTS/Engine/Recompute.hs` + `src/MCTS/Engine/ForeignRecompute.hs` | ✅ Done (recompute streams persist and display under the correct originator or foreign-view label) | Sprint 3.6, Sprint 6.5, Sprint 7.6 |
| Layered envelope verify (`CohortLevel` + `BackendSlot` rule with `--allow-stale`) | `src/MCTS/Verify/Envelope.hs`, `src/MCTS/Driver/Dispatch.hs`, `src/MCTS/CLI/Verify.hs` | ✅ Done (cohort-invariant fields hard-fail; backend-slot substrate fields gate stale checks; `engine_git_commit` and display/cache `build_id` are provenance only) | Sprint 7.5, Sprint 7.7 |
| Divergence-rate metric (`visit_disagreement_rate`, `move_disagreement_rate`, `equity_l2_drift`) | `src/MCTS/Verify/Divergence.hs` | ✅ Done (metric math and `mcts inspect divergence` row coverage include every available cached sidecar and live foreign cdylib; `equity_l2_drift` is over the chosen-action equity series carried by `EqStream`) | Sprint 7.5, Sprint 7.6, Sprint 7.7 |

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
| Parser topology rendered from the registry; leaf options parsed by explicit semantic parsers | Command Topology | ✅ Done | Sprint 1.2 |
| Parser-test category via `execParserPure` | Testing Doctrine → Parser Tests | ✅ Done | Sprint 1.2 |
| `mcts commands --tree` and `mcts commands --json` introspection | Progressive Introspection | ✅ Done | Sprint 1.2 |
| `Subprocess` ADT plus `runStreaming` / `capture` interpreter; pure `renderSubprocess` | Architecture → Subprocesses as Typed Values | ✅ Done (`MCTS.Subprocess` interprets the typed value through `typed-process`) | Sprint 1.6 |
| Forbidden subprocess primitives (`callProcess`, `readCreateProcess`, `System.Process` constructors, `typed-process` smart constructors) | Architecture → Subprocesses as Typed Values | ✅ Done (`.hlint.yaml` carries the full direct-primitive rule set and container-pinned HLint enforces `Error:` findings; the source walker provides an additional textual guard) | Sprint 1.6 |
| `Plan` / `apply` boundary with `--dry-run` and `--plan-file <path>` | Plan / Apply | ✅ Done (`MCTS.Plan` owns `buildPlan`, `applyPlan`, `applySubprocessPlan`, `applyWithEnv`, and `applySubprocessWithEnv`; every current Plan/Apply leaf declares `--dry-run` and `--plan-file` in `CommandSpec`) | Sprint 1.5 |
| `prerequisiteRegistry` with `nodeId`, `nodeDescription`, remedy hint, transitive closure | Prerequisites as Typed Effects | ✅ Done (current probes cover exact GHC/Cabal, C++ compiler, LLVM/BOLT 19, Rust 1.95.0, LLD 19, `mimalloc`, Rust and C++ profile directories, and canonical foreign shared-library nodes) | Sprint 1.7, Sprint 5.3 |
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
| GADT-indexed `VerifyBackend` type for Q3 `(ii)..(v)` | GADT-Indexed State Machines | ✅ Done (`src/MCTS/Types.hs` defines `VCppImperative`, `VCppFunctional`, `VRust`, and `VHaskell`) | Sprint 7.2, Phase 8 restoration |
| Q6 legacy-parity parser/runtime surface | GADT-Indexed State Machines | ✅ Done (`mcts verify legacy-parity` validates the complete `(i)..(v)` backend list and pins the legacy envelope) | Sprint 7.2, Phase 8 restoration |
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
| `mcts-unit` | Pure logic | Current `test/unit/Main.hs` uses a fine-grained `tasty` tree with 28 tests grouped by CLI/parser, transcripts/cache, engine/RNG, envelopes/sidecars, plans/subprocesses, and renderers/TUI dispatch. Coverage includes command registry/parser smoke, `execParserPure` happy/failure paths, SHA-256, all-action notation roundtrips, transcript roundtrip, a `tasty-quickcheck` transcript round-trip property, envelope/cache-key checks, sidecars, `inspect show`, `inspect list --format json`, `renderError`, TUI board/status/replay layout, divergence metrics, split engine/RNG/FFI fixture checks, C++ PGO/BOLT plan/prerequisite checks, and semantic renderer assertions without checked-in golden providers. | ✅ Done | Sprint 7.1, Sprint 8.8 |
| `mcts-integration` | Live integration baseline plus bounded FFI smoke | Current `test/integration/Main.hs` uses a `tasty` runner and checks same-backend determinism directly through `MCTS.Driver`, decoded real `mcts` binary transcript determinism through `MCTS.Subprocess.capture` for Haskell and Rust when the Rust cdylib is present, sidecar origin markers, bounded measured report-card divergence building, cached recompute-sidecar consumption through the real `mcts inspect divergence` subprocess, Rust dynamic-FFI smoke games, Rust live `mcts_rust_get_envelope` loading, Rust live transcript-envelope stamping, backend-slot stale hard-fail/`--allow-stale` warning behavior, and synthetic C++-slot evidence in temporary roots. Live C++ visit-vector/envelope coverage is exercised by `mcts-cross-backend`, `mcts-legacy-parity`, and the report-card path against the Dockerfile-built C++ artefacts. | ✅ Done | Sprint 7.1, Sprint 8.8, Phase 8 restoration |
| `mcts-cross-backend` | Round-robin verify | Current `test/cross-backend/Main.hs` uses a serial `tasty` runner whose rollout and self-play Q3 cases invoke real `mcts verify` subprocesses under `--rng cpp` for backends `(ii)..(v)`, with any `VerifyMismatch` failing the subprocess and the bounded canonical report-card cohort. The stanza runs with `NumThreads 1` around the process-pinned dynamic-library handles and shared C++ RNG bridge. Synthetic comparator coverage asserts digest-first equivalence and length-aware extra-game, extra-move, and terminator mismatch surfaces. | ✅ Done | Sprint 7.2, Phase 8 restoration |
| `mcts-legacy-parity` | Legacy-envelope verify | Q6 liveness/overflow across all five backend slots under the legacy envelope. | ✅ Done | Sprint 7.2, Phase 8 restoration |
| `mcts-haskell-style` | Lint | `test/haskell-style/Main.hs` checks tab characters plus a conservative forbidden-symbol subset in Haskell sources, runs `cabal format` through a temp-file round-trip, and requires `/opt/mcts-style-tools/bin/fourmolu --mode check` / `/opt/mcts-style-tools/bin/hlint --with-group=default --with-group=extra` inside the container with only `Error:` findings blocking. The supported-path partial-function wording matches the exact source-walker policy. | ✅ Done | Sprint 1.4, Sprint 1.10 |

## POC Report-Card Knobs

Implemented in `MCTS.CLI.Test` and mirrored in `cabal.project` comments for
operator auditability; see
[phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md).

| Knob | Value | Purpose |
|------|-------|---------|
| `N_PRIM` | `1_000` | Terminal-playout and search-iteration primitive count for Q1a/Q1b |
| `P_MAX` | `60` | Primitive benchmark max-plies cap for Q1a/Q1b |
| `G_R` | `1_000` | Legacy played-game rollout count for parity-anchor and historical Q1 audit rows |
| `G_S` | `4` | Self-play game count (Q2 / Q5) |
| `G_V` | `4` | Cross-backend verify game count (Q3) |
| `G_LP` | `2` | Legacy parity game count (Q6) |
| `S_BENCH` | `500` | Per-move sim budget for bench self-play |
| `S_VERIFY` | `500` | Per-move sim budget for verify self-play |
| `S_LP_SIMS` | `4` | Per-move sim budget for legacy-parity self-play liveness |
| `S_LP` | `42` | Legacy-parity fixture seed (chosen so (i) did not throw) |

These knobs describe the refactored report-card row families and the remaining
legacy played-game rollout anchor used by `mcts test parity-anchor`. Sprint `8.11`
reviewed the Dockerfile-time profile suite against these units per
[benchmark_metrics.md](../documents/engineering/benchmark_metrics.md).

## Toolchain

| Component | Pinned Version | Purpose | Status | Owning Sprint |
|-----------|----------------|---------|--------|---------------|
| GHC | `9.14.1` | Haskell compiler for backend (v) and the CLI binary | ✅ Done (`mcts.cabal` / `cabal.project` / Docker pins and exact prerequisite probe landed) | Sprint 1.1 |
| Cabal | `3.16.1.0` | Haskell build tool; per-stanza `type: exitcode-stdio-1.0` | ✅ Done (`cabal.project` / Docker pins and exact prerequisite probe landed) | Sprint 1.1 |
| Style-tool GHC | `9.12.4` | Isolated compiler for installing `fourmolu-0.19.0.1` and `hlint-3.10` into `/opt/mcts-style-tools/bin/` inside the container; not used for project builds | ✅ Done (Docker install and style stanza path invocation landed) | Sprint 1.4 |
| GCC | Latest stable on `ubuntu:24.04` | C++23 compiler for backends (i), (ii), (iii). Clang not supported. | ✅ Done for the container baseline (Docker installs the distro `build-essential`/`g++` toolchain and the Dockerfile-invoked build recipes compile the C++23 engines; the exact patch version intentionally follows the pinned Ubuntu base image) | Sprint 4.1, Sprint 5.1 |
| LLVM | `19` in `docker/Dockerfile` | Shared by GHC `-fllvm` and BOLT post-link | ✅ Done (Docker installs LLVM/LLD/BOLT 19 and prerequisite probes validate `19.x`) | Sprint 1.1 |
| `rustup` | Latest stable installer with Rust `1.95.0` selected in `docker/Dockerfile` | Rust toolchain manager for backend (iv) | ✅ Done for the Phase 6 build surface (Docker install, prerequisite probes, and Dockerfile-invoked Rust PGO/BOLT install path validate) | Sprint 6.4 |
| Rust | `1.95.0` in `docker/Dockerfile` | Rust compiler for backend (iv) | ✅ Done for the Phase 6 build surface (Docker pin, prerequisite probes, Rust FFI integration, `lld` linker flag in both PGO stages, and canonical Dockerfile-invoked Rust build path validate) | Sprint 6.4 |
| `mimalloc` | Ubuntu `libmimalloc-dev` in `docker/Dockerfile`; Rust links the same system library through `rust/build.rs` and `rust/src/allocator.rs` | System allocator for backends (ii), (iii), (iv) | ✅ Done for the current baseline (Docker package and library-path probe landed because the Ubuntu package does not ship `mimalloc.pc`; Rust uses the local `SystemMiMalloc` wrapper; C++ build plans link the system library rather than requiring a static archive) | Sprint 5.3, Sprint 6.4 |
| BOLT | LLVM `19` package in `docker/Dockerfile` | Mandatory post-link binary reordering after PGO for backends (ii), (iii), (iv) | ✅ Done for fail-closed enforcement. Docker pinning and prerequisite probing exist; Sprints `5.3` and `6.4` remove PGO-only/BOLT-missing fallback installs, require non-empty `.fdata`, use LLVM objcopy for post-BOLT envelope patching, and smoke installed bolted artefacts before the image is published. | Sprint 5.3, Sprint 6.4 |
| `ghcup` | Latest stable binary installed in the container | Manages the pinned GHC and Cabal versions inside the container | ✅ Done (Docker installs `ghcup`; `prerequisiteRegistry` carries a `ghcup` node) | Sprint 1.1 |
| Target platforms | `amd64` Linux + `arm64` Linux | Both architectures supported; reproducibility envelope is per-architecture (transcripts and report-card metadata carry a `host_arch` tag); cross-arch bit-equality not guaranteed. See [00-overview.md → Hard Constraints item 36](00-overview.md) and [../documents/engineering/determinism_contract.md → Architecture Envelope](../documents/engineering/determinism_contract.md) | ✅ Done / pinned envelope | n/a |

## State Locations

| State Class | Authority | Durable Home | Notes |
|-------------|-----------|--------------|-------|
| Transcript cache | `mcts` CLI | `--cache-dir <path>` → `./.mcts-cache/transcripts/<arch>/<sha>.tr` inside the container (arch ∈ `{amd64, arm64}`); per-transcript sidecar directory `./.mcts-cache/transcripts/<arch>/<sha>/<backend>-<build_label>.eq` plus `.envelope` neighbour for cached equity series | One-game transcript files are content-addressed by `sha256(run_config)`, where `run_config` includes backend and `game_index` (or `sha256(run_config \|\| move_history)` for `mcts play`-recorded transcripts); arch-partitioned per [../documents/engineering/determinism_contract.md → Architecture Envelope](../documents/engineering/determinism_contract.md); sidecar `.eq` files multi-build-cohabitable (one per `(backend, build)` slot; live labels use the `engine_build_id` prefix and logical all-zero GHC envelopes use the `logical` build label, yielding `<backend>-logical` slots), prunable via `mcts inspect cache prune`; cross-backend verify compares decoded determinism payloads rather than cache filenames; no runtime environment-variable fallback |
| Optional legacy audit fixtures | `mcts build legacy-fixtures` from the `cpp-legacy/legacy-core/` port of `~/MCTS_legacy/` | Explicit operator-provided output directory, preferably outside the repo or under an ignored local artifact root | Optional external audit evidence; not a report-card question, not required by normal validation, and not checked into the repo |
| Optional audit evidence | `mcts` CLI or explicit operator generation commands | Plan/docs plus optional external/ignored artifact storage | Transcripts and throughput captures may exist for audit, but generated evidence files are not repository validation inputs |
| Build outputs | `docker/Dockerfile`; runtime entry through `docker compose run --rm mcts mcts <command>` | Image-local `dist-newstyle/` plus per-backend `build/` / `target/` directories | Canonical backend artefacts live inside the Compose-built image; runtime commands consume them without rebuilding, and host-level `.build/` is unsupported. Steelman foreign artefacts are valid only after Dockerfile-time PGO+BOLT succeeds and the installed bolted library smoke passes. |
| PGO/BOLT profile directories | Dockerfile-invoked two-stage PGO/BOLT build harness | `cpp-imperative/pgo-profile/`, `cpp-imperative/bolt-profile/`, `cpp-functional/pgo-profile/`, `cpp-functional/bolt-profile/`, `rust/pgo-profile/`, `rust/bolt-profile/` | Rust and C++ profile roots are generated build artefact locations, ignored by git and by the Docker build context. Each Dockerfile-invoked `mcts build <backend>` recipe recreates the needed roots, generates fresh PGO/BOLT profile data from the bounded metric-suite profile suite, and fails the image build when required profile data is missing instead of relying on checked-in snapshots. |
| Profile-training transcript cache | Dockerfile-invoked PGO/BOLT training runs | `/tmp/mcts-profile-training/<backend>/<workload>-<threading>-<seed>-<sims>/` inside the build container | `MCTS.CLI.Build.trainingCacheDir` gives each bounded training run an isolated transcript cache root so profile runs do not write into the operator `.mcts-cache/` tree. These are generated build-time scratch roots, not repository validation inputs. |
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
| Backend (i) sources | `cpp-legacy/` | Verbatim re-port of `MCTS_legacy`, live through C ABI for Q6 legacy-envelope evidence |
| Backend (ii) sources | `cpp-imperative/` | Maximally-tuned imperative C++23 performance ceiling |
| Backend (iii) sources | `cpp-functional/` | Functional-style C++23 steelman under the same optimisation stack as backend (ii) |
| Backend (iv) sources | `rust/` | Rust `cdylib` with the pinned `[profile.release]` |
| Haskell tests | `test/` | Five live Cabal stanza modules. Generated transcripts, sidecars, report-card values, and renderer baselines are produced in memory or temporary directories during tests, not stored under `test/golden/` |
| Bench targets | `bench/` | Cabal benchmark target (`mcts-criterion`) using Criterion for in-process timing |
| Docker development environment | `docker/Dockerfile`, root `compose.yaml`, `.dockerignore` | `ubuntu:24.04` base with pinned GCC, LLVM, GHC, Cabal, Rust, a separate formatter-tools GHC for Fourmolu/HLint, copied project sources, an installed `mcts`, and all four foreign backend shared libraries produced during image construction; all supported runtime host work uses `docker compose run --rm mcts mcts <command>`. The image build owns successful PGO/BOLT for backends (ii), (iii), and (iv), uses LLVM objcopy for post-BOLT envelope patching, smokes installed bolted artefacts, trains on the bounded metric-suite profile suite, and must fail instead of publishing PGO-only or unoptimized fallback artefacts. `.dockerignore` keeps generated profile roots and backend build outputs out of the Docker context so each image build regenerates fresh profile data. Repository `.sh` wrappers and `bootstrap/` helpers are forbidden workflow surfaces. The 2026-05-18 Compose-only doctrine update passed `mcts-unit`, `lint files`, `lint all`, and `check-code` through the root Compose service |
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
