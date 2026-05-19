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
> five backends, the transcript codec, the verification cohort, the Cabal test stanzas,
> and the retained state locations.

The inventory documents the authoritative end state and the current implementation
baseline. The repository now has an implemented five-backend verification baseline:
operator-facing verify dispatches through live FFI engines when their shared
libraries are present and the requested batch run is compatible with the current
fixed 60-ply foreign search horizon; it falls back to the in-process runner only
when a library is absent or a lower search cap is requested. Q3 is the
visit-vector equality gate for `(ii)..(v)`, Q6 is the byte-for-byte legacy
fixture anchor, and Q7 is the five-backend legacy-envelope liveness/overflow
gate. The 2026-05-19 canonical report card records `Verdict: Within tolerance`,
so Phase `8`'s remaining work is the ordered retirement protocol, not additional
Haskell parity tuning. Rows marked `🔄 Active` below have concrete code in the
worktree but still retain sprint-owned remaining work before they can move to
`✅ Done`.
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) preserves cleanup
and retirement history separately.

## Current Implementation Baseline

| Component | Current Worktree Evidence | Closure Gap |
|-----------|---------------------------|-------------|
| Cabal package and CLI | `mcts.cabal`, `cabal.project`, `app/Main.hs`, `src/MCTS/App.hs`; doctrine-standard library/test dependency set is declared; host validation enters through `docker compose run --rm mcts mcts check-code`; Docker installs the isolated style-tool GHC and formatter/hlint binaries plus the `mcts` executable | No Phase 1 closure gap |
| Command registry | `src/MCTS/CLI/Spec.hs`, `src/MCTS/CLI/Parser.hs`; `mcts commands --tree` and `mcts commands --json` work; `commandParserInfo` renders an optparse-applicative parser from the registry tree; README concrete invocations use the Compose entrypoint around the same logical leaf commands | No Sprint 1.2 closure gap |
| Transcript/cache baseline | `src/MCTS/Transcript.hs`, `src/MCTS/Crypto/SHA256.hs`, `src/MCTS/Transcript/EquitySidecar.hs`, plus wrapper modules; `.mcts-cache/` ignored; `inspect list` / `inspect show --envelope` / `inspect show --with-equity` / `inspect replay` originator cache-miss sidecar preparation plus `r`-key on-demand backend columns / `inspect cache list` / `inspect cache prune` work; transcript and sidecar writes use same-directory temp files, fsync, rename, and parent-directory fsync; `MCTS.Engine.ForeignRecompute.foreignRecomputeEqStream` can score foreign recompute streams through `mcts inspect divergence` and can fill replay overlays when cdylibs are present; FFI-produced transcripts carry live envelopes when cdylibs are present; `mcts-integration` checks live transcript stamping and backend-slot stale hard-fail/`--allow-stale` warning behavior when cdylibs are present; `mcts-integration` also covers bounded report-card divergence building and cached recompute-sidecar coverage; `mcts test all` derives report-card Q1/Q2/Q5 rows from no-write monotonic-clock measurements and divergence rows from the measured live `G_V` verify transcripts | Phase 8 owns retirement-protocol archived sidecar/anchor handling |
| In-process MCTS engine | `src/MCTS/Engine.hs`, `src/MCTS/Engine/Envelope.hs`, `src/MCTS/Driver.hs`, `src/MCTS/Search/Arena.hs`, `src/MCTS/Search/UCT.hs`, `src/MCTS/Verify.hs`; the Haskell engine uses strict `Word64` board slots/bitsets, real recursive UCT in the `ST` monad over a structure-of-arrays `STUArray` arena, a sentinel `terminalOutcome` path for the rollout inner loop, and per-move search dispatch from the driver. `MCTS.Verify` now dispatches through `MCTS.Driver.Dispatch.runBatchDispatch`, so Q3 uses live foreign cdylibs when present and the in-process runner only as the no-cdylib fallback; Q7 uses the same path as a five-backend legacy-envelope liveness/overflow gate. | No performance-parity closure gap; Phase 8 owns backend-retirement cleanup |
| Foreign backend homes | `cpp-legacy/` contains the mechanically imported legacy core plus C ABI wrappers and the `legacy-to-wire` fixture generator reached through `mcts build legacy-fixtures`; `cpp-imperative/engine/` hosts the arena-MCTS imperative-steelman engine with complete wall generation, canonical search-side 12-wall child cap, adjacent-unoccupied pawn moves only, Haskell-compatible splitmix/signed-modulo rollout selection, and the fixed 60-ply foreign search horizon; `cpp-functional/engine/` ships the functional-style API and `DescentStep`/`std::visit` descent data-flow over the same arena layout and search-shape contract; `rust/src/` ships a real arena MCTS plus xoshiro256++ plus the full Corridors gameplay port (8x8 bitfield walls, iterative BFS escapability, post-move 180-degree flip via `u64::reverse_bits`) and the visit-vector/recompute/read-visits C ABI; `src/MCTS/Driver/{CppLegacy,CppImperative,CppFunctional,Rust}.hs` dispatch through the real shared libraries via `MCTS.FFI.Common.withDynamicSearchGame` / `withDynamicRecomputeGame` | Phase 8 owns retirement of backends (i), (ii), and (iii) after frozen anchors are generated |
| Test stanzas | `test/unit`, `test/integration`, `test/cross-backend`, `test/legacy-parity`, `test/haskell-style`; each stanza has its own `tasty` runner; host validation gate is `docker compose run --rm mcts mcts test all`; report-card text/JSON goldens include explicit evidence-pending Q1/Q2/Q5 fields plus the divergence matrix and schema fixture; `mcts test all` builds canonical backend artefacts before the Cabal stanzas, requires those artefacts for the final measured report card, populates live Q1/Q2/Q5 rows with the production monotonic clock through `runBatchNoWriteDispatch`, and populates divergence rows from the measured live `G_V` verify cohort; `mcts-unit` now includes a `tasty-quickcheck` transcript round-trip property plus `tasty-golden` providers for command/report-card fixtures; `mcts-integration` includes full decoded real-binary transcript determinism, bounded report-card divergence, and cached recompute-sidecar coverage; the Q6 legacy fixture set is committed under `test/golden/legacy/transcripts/amd64/` at `S_LP_SIMS = 10000`, and `mcts-integration` decodes every committed fixture directory on every host, verifies each filename equals `sha256(file_bytes)`, and asserts the full legacy parity envelope; `docker compose run --rm mcts mcts build legacy-fixtures` is the supported regeneration path; the Sprint 8.2 criterion micro-benchmark suite ships under `bench/criterion-suites.hs` + the `mcts-criterion` benchmark stanza in `mcts.cabal`; the 2026-05-19 canonical run records `Verdict: Within tolerance` while Phase 7's Q3/Q6/Q7 gates are closed | Phase 8 owns retirement-driven stanza reductions and frozen throughput anchors |
| Generated docs gate | `src/MCTS/CLI/Docs.hs`, `src/MCTS/Generated/Paths.hs`, `src/MCTS/Generated/Sections.hs`, `documents/engineering/cli_command_surface.md`, `documents/cli/commands.md`, `share/man/man1/mcts.1`, `share/completion/{bash,zsh,fish}/`; `mcts docs check` and `mcts lint files` check tracked generated-file drift; `command-matrix` is a marker-delimited governed-doc section rendered from `CommandSpec` | No Sprint 1.3 closure gap |

## Backends

| Backend | Identifier | Implementation Path | Linkage | Status | Owning Phase |
|---------|------------|---------------------|---------|--------|--------------|
| (i) C++ legacy port | `cpp-legacy` | `cpp-legacy/`, `src/MCTS/Driver/CppLegacy.hs` | C ABI via Haskell FFI | ✅ Done for the Phase 4 closed surfaces (legacy core imported; full visit-vector FFI driver via `mcts_legacy_search_move`; Q6 fixtures committed under `test/golden/legacy/transcripts/` at `S_LP_SIMS = 10000`; supported `mcts build legacy-fixtures` regeneration path; envelope post-link patch + runtime CPU/FP probes + foreign-engine recompute landed) | [Phase 4](phase-4-cpp-legacy-port-and-ffi-bridge.md) |
| (ii) C++ imperative steelman | `cpp-imperative` | `cpp-imperative/`, `src/MCTS/Driver/CppImperative.hs` | C ABI via Haskell FFI | ✅ Done for the Phase 5 closed surfaces (arena-MCTS engine with `Word16` ply counter, `thread_local` move buffer, `__builtin_prefetch`, `alignas(64)`; full visit-vector/recompute FFI driver; shared 19-step typed `Subprocess` PGO+BOLT pipeline with `llvm-bolt -instrument` self-recording, canonical FFI training installs, and explicit PGO fallback when BOLT data is absent; `-fno-exceptions` and the scratch-board residue are closed) | [Phase 5](phase-5-cpp-imperative-steelman.md) |
| (iii) C++ functional-style | `cpp-functional` | `cpp-functional/`, `src/MCTS/Driver/CppFunctional.hs` | C ABI via Haskell FFI | ✅ Done (arena-MCTS engine with `std::optional`/`std::variant` API, `DescentStep`/`std::visit` descent data-flow, visit-vector/recompute dispatch, live envelope probes, and the shared 19-step canonical PGO/BOLT training/install pipeline; C++ BOLT falls back to the PGO artefact when no `.fdata` exists in the pinned container) | [Phase 6](phase-6-cpp-functional-and-rust.md) |
| (iv) Rust | `rust` | `rust/`, `src/MCTS/Driver/Rust.hs` | C ABI via Haskell FFI, `cdylib` | ✅ Done (real arena MCTS with UCT-1, xoshiro256++ native RNG, full `mcts_rust_search_move` / `mcts_rust_recompute_move` C ABI, cached `mcts_rust_read_visits`, real Corridors gameplay in `rust/src/board.rs`, `mimalloc::MiMalloc` global allocator, and `rustPgoBoltPlan` through PGO train/merge/use plus BOLT training/install on amd64. `MCTS.Driver.Dispatch.runBatchDispatch` routes `--backend rust` through the real FFI engine.) | [Phase 6](phase-6-cpp-functional-and-rust.md) |
| (v) Haskell | `haskell` | `src/MCTS/Engine.hs`, `src/MCTS/Engine/Envelope.hs`, `src/MCTS/Driver.hs`, `src/MCTS/Search/Arena.hs`, `src/MCTS/Search/UCT.hs` | Native (in-process) | ✅ Done for the Phase 3 correctness baseline and the Phase 8 parity proof | [Phase 3](phase-3-haskell-engine.md), [Phase 8](phase-8-haskell-performance-parity-closure.md) |

## Haskell CLI Surface

| Surface | Command | Purpose | Status | Owning Sprint |
|---------|---------|---------|--------|---------------|
| Random-rollouts benchmark | `mcts bench rollouts` | Engine throughput on legal-move generation, move application, terminal detection; no tree, no UCT | ✅ Done (all four foreign backends dispatch through real FFI when their shared libraries are present; Haskell remains native in-process) | Sprint 3.5; foreign dispatch in Sprints 4.4, 5.4, 6.2, 6.4 |
| Self-play benchmark | `mcts bench selfplay` | Full UCT search with random-rollout leaf evaluation, adversarial self-play | ✅ Done (all four foreign backends dispatch through real FFI when their shared libraries are present; Haskell remains native in-process) | Sprint 3.5; foreign dispatch in Sprints 4.4, 5.4, 6.2, 6.4 |
| Rollouts verify | `mcts verify rollouts` | Live FFI-backed round-robin visit-count equality across the `(ii)..(v)` cohort under `--rng cpp`; layered envelope checks with `--allow-stale` | ✅ Done (`MCTS.Verify` dispatches through `runBatchDispatch`, `checkTranscriptEnvelopesLive` compares backend-slot fields against live cdylibs when present, and focused plus report-card rollout cohorts pass with `VerifyMismatch` as a hard failure) | Sprint 7.2, Sprint 7.5 |
| Self-play verify | `mcts verify selfplay` | Live FFI-backed round-robin self-play visit-count equality across the `(ii)..(v)` cohort | ✅ Done (`MCTS.Verify` dispatches through `runBatchDispatch`; the report-card `G_V = 4`, `S_VERIFY = 500` live self-play cohort passes) | Sprint 7.2, Sprint 7.5 |
| Legacy parity verify | `mcts verify legacy-parity {rollouts\|selfplay}` | Live FFI-backed 5-backend legacy-envelope liveness/overflow gate under `max_plies = 10000`, pinned fixture seed, `--rng cpp`; workload dispatched by `LegacyParityWorkload` | ✅ Done (Q6 fixtures are refreshed at `S_LP_SIMS = 10000`, the bounded `mcts-legacy-parity` Cabal stanza passes, and Q7 intentionally does not compare backend (i)'s legacy visit vectors or chosen moves against the steelman engines) | Sprint 7.2 |
| Interactive game | `mcts play` | TUI human-vs-AI or AI-vs-AI spectate with live board rendering | ✅ Done (non-interactive fallback plus interactive `brick` `App` event loop in `MCTS.CLI.Tui.Play` with legacy-notation move input (`MCTS.Notation.parseMove`), `:hint`/`:undo`/`:quit`, `:save` transcript writes through `MCTS.Transcript.writePlayTranscript`, selected-backend AI advance through `MCTS.Driver.ForeignSearch.foreignSearchMove` when a foreign shared library is present, in-process fallback when it is absent, and a pure `applyUserInput` dispatcher plus write/decode and AI-advance assertions covered by `mcts-unit::exerciseTuiPlayInput`; the shared board widget renders pawn cells plus horizontal/vertical wall segments from pure text rows pinned by `test/golden/cli/tui-board.txt`) | Sprint 7.4 |
| Transcript list | `mcts inspect list` | Non-interactive enumeration of the local transcript cache | ✅ Done | Sprint 2.4 |
| Transcript show | `mcts inspect show <hash-prefix>` | Non-interactive dump in legacy move notation, `--envelope` dump, optional `--with-equity` recompute-backed logical sidecar write and stream-backed equity column | ✅ Done on the Phase 2 inspect surface; foreign recompute is owned by later backend FFI sprints | Sprint 2.4, Sprint 2.6 |
| Transcript replay | `mcts inspect replay <hash-prefix>` | Interactive `brick` TUI for forward/back navigation with equity overlays | ✅ Done (`MCTS.CLI.Tui.Replay` brick `App` with forward/back/home/end navigation, a bounded board-snapshot cache driven by `--cache-states`, and a per-move multi-backend equity overlay column populated from cached `.eq` sidecars; `MCTS.CLI.Inspect.prepareReplayOverlays` fills a missing originator sidecar before TUI start and performs the `--rng cpp` chosen-action/visit check before writing; `ReplayState.replayOverlayLoader` plus the `r` key recomputes and writes a requested non-originator backend column on demand; `MCTS.CLI.Inspect.inspectReplay` dispatches to `runReplayTuiFromState` on a TTY and falls back to the non-interactive summary on pipes; pure dispatchers plus cache-miss/cache-hit preparation and shared board/status/replay overlay layout are covered by `mcts-unit` goldens) | Sprint 7.4 |
| Sidecar cache list | `mcts inspect cache list` | Enumerate equity-sidecar `(backend, build)` slots cohabiting each cached transcript and mark each slot as originator, foreign, or unknown | ✅ Done on the Phase 2 sidecar-cache surface | Sprint 2.7 |
| Sidecar cache prune | `mcts inspect cache prune [--keep-current]` | Plan/Apply deletion of equity sidecars; `--keep-current` retains current logical build slots in the Phase 2 baseline | ✅ Done on the Phase 2 sidecar-cache surface; verify-time live-envelope stale detection is owned by Sprint 7.5 | Sprint 2.7 |
| Divergence matrix | `mcts inspect divergence <hash-prefix>` | Emit divergence-rate metrics (`visit-Δ`, `move-Δ`, `equity-L2`) for a single transcript and cached backend columns | ✅ Done (`divergenceVsEqStream` pairs the transcript against each cached sidecar `EqStream`; per-sidecar metrics render with real `equity_l2_drift`; live foreign-recompute rows are added for available cpp-imperative, cpp-functional, and Rust cdylibs; `MCTS.ReportCard.reportDivergenceRows` renders the report-card table/JSON matrix, and `MCTS.ReportCard.divergenceRowsFromTranscripts` populates `mcts test all` rows from the measured live `G_V` verify cohort) | Sprint 7.5 |
| Test runner | `mcts test all` / `mcts test <stanza>` | Plan/Apply over backend builds, Cabal test stanzas, verify cohorts, and the no-write measured report-card workload | ✅ Done (`--dry-run`; recursive CLI steps route through `cabal exec mcts -- ...`; report-card summary plus Q1/Q2/Q5 measured fields, Q3 verify cohorts, Q7 legacy-envelope liveness/overflow, and divergence matrix table/JSON goldens exist) | Sprint 7.2, Sprint 7.3 |
| Lint stack | `mcts lint files\|docs\|haskell\|all` | Whitespace, final newline, forbidden paths, generated sections, mandatory container-owned formatter/hlint path, and `cabal format`; host fallback is unsupported | ✅ Done | Sprint 1.4 |
| Docs generation | `mcts docs check` / `mcts docs generate` | Paired generated-section check and write per the `GeneratedSectionRule` registry | ✅ Done | Sprint 1.3 |
| Command introspection | `mcts commands [--tree\|--json]` | Flat list, tree rendering, or JSON command schema from the `CommandSpec` registry | ✅ Done | Sprint 1.2 |
| Focused help | `mcts help <subcommand>` | Equivalent to `<subcommand> --help`; same renderer as the `--help` path | ✅ Done | Sprint 1.2 |
| Code quality gate | `mcts check-code` | Doctrine-alignment enforcement, formatter, hlint, warning-clean build, forbidden-path scan | ✅ Done | Sprint 1.4 |
| Per-backend build harness | `mcts build {cpp-legacy\|cpp-imperative\|cpp-functional\|rust}` | Plan/Apply per-backend PGO+BOLT+`mimalloc` pipeline (legacy-flags subset for `cpp-legacy`) | ✅ Done for the backend build/install surface (`cpp-imperative` and `cpp-functional` share the 19-step PGO/BOLT plan with canonical FFI training installs and PGO fallback when BOLT data is absent; `rustPgoBoltPlan` validates PGO train/merge/use plus BOLT training/install; report-card measurement of the installed artefacts remains Phase 7/8 work) | Sprint 4.1, Sprint 5.3, Sprint 6.2, Sprint 6.4 |

## Transcript Codec and Determinism

| Component | Implementation | Status | Owning Sprint |
|-----------|----------------|--------|---------------|
| Wire-format header | `src/MCTS/Transcript.hs`, `src/MCTS/Transcript/Codec.hs` | ✅ Done (v1 header plus envelope offset) | Sprint 2.1 |
| Per-move record codec | `src/MCTS/Transcript.hs`, `src/MCTS/Transcript/Codec.hs` | ✅ Done (records canonicalize visit pairs by action ID) | Sprint 2.1 |
| Single-byte action enumeration | `src/MCTS/Transcript/Action.hs`, `src/MCTS/Types.hs` | ✅ Done | Sprint 2.1 |
| Content-addressed hash (`sha256(run_config)`) | `src/MCTS/Transcript/Hash.hs`, `src/MCTS/Crypto/SHA256.hs` | ✅ Done | Sprint 2.2 |
| Cache root resolution (`--cache-dir` → `./.mcts-cache/`) | `src/MCTS/Transcript.hs` | ✅ Done; no runtime environment-variable fallback | Sprint 2.2 |
| Git-style hash-prefix lookup (≥ 4 hex chars; `AppError TranscriptNotFound` / `AppError TranscriptAmbiguous`) | `src/MCTS/Transcript/Lookup.hs` | ✅ Done (`TranscriptRef` carries hash plus path; ambiguous candidates render as hashes) | Sprint 2.3 |
| `splitmix64(master_seed, game_index)` per-game seed derivation | `src/MCTS/Rng/Mix.hs` | ✅ Done | Sprint 2.5 |
| `--rng cpp` shared `std::mt19937_64` FFI bridge | `cpp-legacy/c-abi/rng.h`, `cpp-legacy/c-abi/rng.cc`, `src/MCTS/Rng/Cpp.hs` | ✅ Done for the Phase 4 surface (shared C++ RNG with `cpp_rng_split_seed`; checked against the Haskell splitmix mixer when the library is built); foreign-driver stream routing for backends (ii)/(iii)/(iv) tracks under each backend's driver | Sprint 4.3 |
| `--rng native` per-backend selection (`splitmix` for Haskell, `rand_xoshiro::Xoshiro256PlusPlus` for Rust, `xoshiro256++` by default with `wyrand` as the C++ alternative) | `src/MCTS/Engine.hs` | 🔄 Active (logical selection; real per-backend RNG open) | Sprint 2.5 |
| Engine envelope codec (envelope block in transcript header; cohort-invariant vs per-backend-slot fields; excluded from the backend-specific `sha256(RunConfig)` cache key) | `src/MCTS/Transcript.hs` | ✅ Done (full v1 envelope with all fields; round-trip, trailer tolerance, and cache-key invariance exercised) | Sprint 2.6 |
| Per-backend envelope capture (build-id, compiler ID/version, fp_flags, libm_id, cpu_features, fp_env) | `<backend>/c-abi/envelope.{h,cc}` (Phase 4/5/6 for cpp/rust); `src/MCTS/Engine/Envelope.hs` (Phase 3 for haskell); `src/MCTS/FFI/Common.hs` (`engineEnvelopeToEnvelope`) | ✅ Done (Haskell logical envelope module; C++ runtime CPU/FP/libm probes + post-link build-id patch; Rust runtime feature/libm probes + build-id section patch; Haskell conversion of live C ABI envelopes into transcript envelopes) | Sprint 3.6, 4.7, 5.5, 6.5, 7.5 |
| Equity sidecar codec (`.eq` + `.envelope` neighbour, atomic-write, multi-build cohabitation) | `src/MCTS/Transcript/EquitySidecar.hs` | ✅ Done (binary `MEQ1` codec, temp-file + fsync + rename writes, sidecar origin helpers, and multi-build cache layout) | Sprint 2.7 |
| Foreign-engine recompute (`mcts_<backend>_recompute_move` FFI; in-process `Recompute.hs` for haskell) | per-backend C ABI + `src/MCTS/Engine/Recompute.hs` + `src/MCTS/Engine/ForeignRecompute.hs` | ✅ Done at the Sprint 6.5 surface (in-process `Recompute.hs` covers Haskell; all three C-ABI foreign backends (i)/(ii)/(iii) and Rust (iv) expose `mcts_<backend>_recompute_move` with real parent-perspective `chosen_equity`; `MCTS.Engine.ForeignRecompute.foreignRecomputeEqStream` drives the FFI through a transcript to emit an `EqStream`, exercised by `mcts-integration::foreign recompute EqStream` for cpp-imperative, cpp-functional, and rust) | Sprint 3.6, 4.7, 5.5, 6.5 |
| Layered envelope verify (`CohortLevel` + `BackendSlot` rule with `--allow-stale`) | `src/MCTS/Verify/Envelope.hs`, `src/MCTS/Driver/Dispatch.hs`, `src/MCTS/CLI/Verify.hs` | ✅ Done at the Sprint 7.5 surface (cohort-invariant fields checked; FFI-produced transcripts carry live `mcts_<backend>_get_envelope()` payloads when cdylibs are present; `checkTranscriptEnvelopesLive` compares cached transcripts against those live values and falls back to in-process envelopes when cdylibs are absent; JSON verify output carries structured `warning_details` for downgraded backend-slot mismatches; `mcts-integration` conditionally proves live stamping plus stale backend-slot hard-fail/`--allow-stale` warning behavior against real cdylibs) | Sprint 7.5 |
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
| Single `AppError` ADT (`TranscriptNotFound`, `TranscriptAmbiguous`, `TranscriptFormatUnsupported`, `VerifyMismatch`, `VerifyCohortTooSmall`, `RecomputeMismatch`, `LegacyParityRolloutOverflow`, `ArchEnvelopeMismatch`, `EngineEnvelopeMismatch`, `PrerequisiteUnmet`, `SubprocessFailed`, `FFIFailure`, `DocsCheckDrift`, `UnknownCommand`, `InvalidMove`) | Error Handling | ✅ Done | Sprint 1.9 |
| `renderError :: AppError -> Text` boundary | Error Handling | ✅ Done (`MCTS.Error.renderError` is canonical; `MCTS.CLI.Output` re-exports it and owns final string/color rendering at stdout/stderr boundaries) | Sprint 1.9 |
| HLint rules refusing `print`, `exitFailure`, direct terminal formatting outside the output module | Error Handling | ✅ Done (`.hlint.yaml` rule set present; container-pinned HLint rejects `Error:` findings) | Sprint 1.4 |
| `--format json\|table\|plain` (default `table` on TTY else `plain`) | Output Rules | ✅ Done | Sprint 1.9 |
| `--color auto\|always\|never` plus `--no-color` | Output Rules | ✅ Done (`--color always` colors rendered errors at the output boundary; `--color never` / `--no-color` preserve plain text) | Sprint 1.9 |
| `fourmolu.yaml` 12-setting list at repo root | Lint, Format, and Code-Quality Stack → Pinned fourmolu.yaml | ✅ Done | Sprint 1.4 |
| `cabal format` temp-file round-trip byte-equality check | Lint, Format, and Code-Quality Stack | ✅ Done (`mcts-haskell-style` runs the temp-file round-trip and requires container-installed `fourmolu-0.19.0.1` / `hlint-3.10` built with style GHC `9.12.4`) | Sprint 1.4 |
| `forbiddenPathRegistry` (`.github/workflows/`, `.husky/`, `.githooks/`, `.pre-commit-config.yaml`, `pre-commit-*.yaml`, root `Makefile`/`justfile`/`Taskfile.yml`, host `.build/`, `bootstrap/`, repository `.sh` wrappers) | Lint, Format, and Code-Quality Stack → Forbidden Surfaces | ✅ Done (typed `forbiddenPathRegistry :: [ForbiddenPath]` value in `MCTS.CLI.Lint`; the Compose-only doctrine update added `bootstrap/` and recursive `*.sh` refusal plus a unit expectation, validated on 2026-05-18 by `mcts-unit`, `lint files`, `lint all`, and `check-code` through Compose) | Sprint 1.4 |
| `GeneratedSectionRule` registry for marker-delimited generated regions | Generated Artifacts → The generated-section registry | ✅ Done (`MCTS.Generated.Sections` owns `GeneratedSectionRule`, `generatedSectionRules`, `spliceMarkerRegion`, `applyGeneratedSection`, `checkGeneratedSection`; `runDocs` traverses the non-empty registry and renders `command-matrix`) | Sprint 1.3 |
| `trackingGeneratedPaths` registry for fully-generated files (manpages, shell completions) | Generated Artifacts → Two categories of generation | ✅ Done (`MCTS.Generated.Paths` owns the fully-generated file registry wired through `mcts docs check/generate` and `mcts lint files`) | Sprint 1.3 |
| Canonical property-test invariants (`decode . encode == id`, `render is deterministic`, `parser roundtrips`) | Test Categories → Property Tests | ✅ Done (`mcts-unit` keeps the existing fixture-scale checks and adds a `tasty-quickcheck` transcript `decode . encode == id` property plus `tasty-golden` providers for command/report-card rendering) | Sprint 7.1 |
| GADT-indexed `VerifyBackend` type excluding `cpp-legacy` at the type level | GADT-Indexed State Machines | ✅ Done (`src/MCTS/Types.hs` defines `VCppImperative`, `VCppFunctional`, `VRust`, `VHaskell`; `src/MCTS/CLI/Parser.hs` rejects `cpp-legacy` for default verify, and `VerifyCommand` stores `[VerifyBackend]`) | Sprint 7.2 |
| GADT-indexed `LegacyParityBackend` type requiring `cpp-legacy` at parse time | GADT-Indexed State Machines | ✅ Done (`src/MCTS/Types.hs` defines `LpCppLegacy`, `LpCppImperative`, `LpCppFunctional`, `LpRust`, `LpHaskell`; `src/MCTS/CLI/Parser.hs` requires `LpCppLegacy` membership for legacy parity, and `VerifyCommand` stores `[LegacyParityBackend]`) | Sprint 7.2 |
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
| `mcts-unit` | Pure logic | Current `test/unit/Main.hs` uses a fine-grained `tasty` tree with 30 tests grouped by CLI/parser, transcripts/cache, engine/RNG, envelopes/sidecars, plans/subprocesses, and renderers/TUI dispatch. Coverage includes command registry/parser smoke, `execParserPure` happy/failure paths, SHA-256, all-action notation roundtrips, transcript roundtrip, a `tasty-quickcheck` transcript round-trip property, four backend-tagged transcript byte goldens, `tasty-golden` providers for command/report-card fixtures, known-position engine golden, envelope/cache-key checks, sidecars, `inspect show`, `inspect list --format json`, `renderError`, subprocess/render goldens, TUI board/status/replay layout, divergence metrics, and split engine/RNG/FFI fixture checks | ✅ Done | Sprint 7.1 |
| `mcts-integration` | Live integration baseline plus bounded FFI smoke | Current `test/integration/Main.hs` uses a `tasty` runner and checks same-backend determinism directly through `MCTS.Driver`, full decoded real `mcts` binary transcript determinism through `MCTS.Subprocess.capture` for Haskell and every built foreign backend, sidecar origin markers, bounded measured report-card divergence building, cached recompute-sidecar consumption through the real `mcts inspect divergence` subprocess, bounded dynamic-FFI smoke games, live `mcts_<backend>_get_envelope` loading, live transcript-envelope stamping, backend-slot stale hard-fail/`--allow-stale` warning behavior for `cpp-legacy`, `cpp-imperative`, `cpp-functional`, and `rust` when their shared libraries are present, and Q6 fixture byte guards over every committed `test/golden/legacy/transcripts/<arch>/*.tr` file | ✅ Done | Sprint 7.1 |
| `mcts-cross-backend` | Round-robin verify | Current `test/cross-backend/Main.hs` uses a `tasty` runner for rollout and self-play `verify` cohorts under `--rng cpp` covering backends `(ii)`, `(iii)`, `(iv)`, `(v)` through `runBatchDispatch`; backend `(i)` is rejected by the typed `VerifyBackend` parser/runtime cohort checks, and any `VerifyMismatch` fails the focused cases and the bounded canonical report-card cohort | ✅ Done | Sprint 7.2 |
| `mcts-legacy-parity` | Legacy-envelope verify | Current `test/legacy-parity/Main.hs` uses a `tasty` runner for `verify legacy-parity` across all five backend slots through `runBatchDispatch`; the typed `LegacyParityBackend` parser path rejects cohorts missing `LpCppLegacy`; target pins `max_plies = 10000`, fixture seed `S_LP = 42`, and Q7 liveness/overflow coverage. Q6 external fixture guards and live backend (i) pre-flight live in `mcts-integration` | ✅ Done | Sprint 7.2 |
| `mcts-haskell-style` | Lint | `test/haskell-style/Main.hs` checks tab characters plus a conservative forbidden-symbol subset in Haskell sources, runs `cabal format` through a temp-file round-trip, and requires `/opt/mcts-style-tools/bin/fourmolu --mode check` / `/opt/mcts-style-tools/bin/hlint --with-group=default --with-group=extra` inside the container with only `Error:` findings blocking | ✅ Done | Sprint 1.4 |

## POC Report-Card Knobs

Pinned in `cabal.project` for reproducibility across hosts; see
[phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md).

| Knob | Value | Purpose |
|------|-------|---------|
| `G_R` | `1_000` | Random-rollouts game count (Q1) |
| `G_S` | `4` | Self-play game count (Q2 / Q5) |
| `G_V` | `4` | Cross-backend verify game count (Q3) |
| `G_LP` | `2` | Legacy parity game count (Q7) |
| `S_BENCH` | `500` | Per-move sim budget for bench self-play |
| `S_VERIFY` | `500` | Per-move sim budget for verify self-play |
| `S_LP_SIMS` | `10_000` | Per-move sim budget for legacy-parity self-play |
| `S_LP` | `42` | Legacy-parity fixture seed (chosen so (i) does not throw) |

## Toolchain

| Component | Pinned Version | Purpose | Status | Owning Sprint |
|-----------|----------------|---------|--------|---------------|
| GHC | `9.14.1` | Haskell compiler for backend (v) and the CLI binary | ✅ Done (`mcts.cabal` / `cabal.project` / Docker pins and exact prerequisite probe landed) | Sprint 1.1 |
| Cabal | `3.16.1.0` | Haskell build tool; per-stanza `type: exitcode-stdio-1.0` | ✅ Done (`cabal.project` / Docker pins and exact prerequisite probe landed) | Sprint 1.1 |
| Style-tool GHC | `9.12.4` | Isolated compiler for installing `fourmolu-0.19.0.1` and `hlint-3.10` into `/opt/mcts-style-tools/bin/` inside the container; not used for project builds | ✅ Done (Docker install and style stanza path invocation landed) | Sprint 1.4 |
| GCC | Latest stable on `ubuntu:24.04` | C++23 compiler for backends (i), (ii), (iii). Clang not supported. | 🔄 Active (Docker/build-essential baseline; exact version and C++23 validation open) | Sprint 4.1, Sprint 5.1 |
| LLVM | `19` in `docker/Dockerfile` | Shared by GHC `-fllvm` and BOLT post-link | 🔄 Active (Docker installs LLVM/LLD/BOLT pin; prerequisite probes validate `19.x`) | Sprint 1.1 |
| `rustup` | Latest stable installer with Rust `1.95.0` selected in `docker/Dockerfile` | Rust toolchain manager for backend (iv) | ✅ Done for the Phase 6 build surface (Docker install, prerequisite probes, and `mcts build rust` PGO/BOLT install path validate) | Sprint 6.4 |
| Rust | `1.95.0` in `docker/Dockerfile` | Rust compiler for backend (iv) | ✅ Done for the Phase 6 build surface (Docker pin, prerequisite probes, Rust FFI integration, and canonical `mcts build rust` path validate) | Sprint 6.4 |
| `mimalloc` | Ubuntu `libmimalloc-dev` in `docker/Dockerfile`; Rust crate `mimalloc = "0.1"` locked in `rust/Cargo.lock` | System allocator for backends (ii), (iii), (iv); static link preferred for FFI determinism | 🔄 Active (Docker package pin and library-path probe landed because the Ubuntu package does not ship `mimalloc.pc`; Rust global allocator landed; C++ static-link validation open) | Sprint 5.3, Sprint 6.4 |
| BOLT | LLVM `19` package in `docker/Dockerfile` | Post-link binary reordering after PGO for backends (ii), (iii), (iv) | 🔄 Active (Docker pin and prerequisite probe landed; Rust BOLT training/install validates on amd64, while C++ shared-library BOLT currently falls back to PGO when no `.fdata` exists; Phase 8 owns the reporting/verdict impact) | Sprint 5.3, Sprint 6.4, Sprint 8.3 |
| `ghcup` | Latest stable binary installed in the container | Manages the pinned GHC and Cabal versions inside the container | ✅ Done (Docker installs `ghcup`; `prerequisiteRegistry` carries a `ghcup` node) | Sprint 1.1 |
| Target platforms | `amd64` Linux + `arm64` Linux | Both architectures supported; reproducibility envelope is per-architecture (transcripts and report-card metadata carry a `host_arch` tag); cross-arch bit-equality not guaranteed. See [00-overview.md → Hard Constraints item 36](00-overview.md) and [../documents/engineering/determinism_contract.md → Architecture Envelope](../documents/engineering/determinism_contract.md) | 📋 Pinned | n/a |

## State Locations

| State Class | Authority | Durable Home | Notes |
|-------------|-----------|--------------|-------|
| Transcript cache | `mcts` CLI | `--cache-dir <path>` → `./.mcts-cache/transcripts/<arch>/<sha>.tr` inside the container (arch ∈ `{amd64, arm64}`); per-transcript sidecar directory `./.mcts-cache/transcripts/<arch>/<sha>/<backend>-<engine_build_id_prefix16>.eq` plus `.envelope` neighbour for cached equity series | One-game transcript files are content-addressed by `sha256(run_config)`, where `run_config` includes backend and `game_index` (or `sha256(run_config \|\| move_history)` for `mcts play`-recorded transcripts); arch-partitioned per [../README.md → Architecture envelope](../README.md); sidecar `.eq` files multi-build-cohabitable (one per `(backend, build)` slot), prunable via `mcts inspect cache prune`; cross-backend verify compares decoded determinism payloads rather than cache filenames; no runtime environment-variable fallback |
| Legacy fixture set | `mcts build legacy-fixtures` from the `cpp-legacy/legacy-core/` port of `~/MCTS_legacy/` | `test/golden/legacy/` | Authoritative Q6 reference; checked into the repo |
| Retirement golden anchors | `mcts` CLI on retirement | `test/golden/<backend>/` | Frozen transcripts and throughput numbers for each retired backend; populated by the retirement protocol in Phase 8 |
| Build outputs | `docker compose run --rm mcts mcts <command>` | Container-local `dist-newstyle/` plus per-backend `build/` / `target/` directories | Built artefacts live inside the Compose-built image or short-lived container filesystem; host-level `.build/` is unsupported |
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
