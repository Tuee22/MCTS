# MCTS Development Plan

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md), [../AGENTS.md](../AGENTS.md),
[../CLAUDE.md](../CLAUDE.md), [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md),
[development_plan_standards.md](development_plan_standards.md),
[00-overview.md](00-overview.md), [system-components.md](system-components.md),
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
[../documents/documentation_standards.md](../documents/documentation_standards.md)
**Generated sections**: none

> **Purpose**: Provide the single execution-ordered development plan for the MCTS
> Haskell CLI and its five backends, including phase status, validation gates, and cleanup
> ownership across the bootstrap, engine buildout, FFI integration, cross-backend
> verification, and Haskell performance parity proof.

## Standards

See [development_plan_standards.md](development_plan_standards.md) for the maintenance
rules that govern this plan suite.

## Closure Status

Phase `0` is `Done`: Sprint `0.1` (plan-suite bootstrap) closed on initial
commit and Sprint `0.2` (doctrine-driven scheduling audit) closed on
2026-05-14 with the audit replay recorded in
[phase-0-planning-documentation.md](phase-0-planning-documentation.md).
Phase `1` Sprint `1.4` is closed again after the Compose-only
operator-surface doctrine change: `bootstrap/` and repository `.sh` workflow
wrappers are forbidden by `forbiddenPathRegistry`, and the updated registry passed
`docker compose run --rm --build mcts mcts test mcts-unit`,
`docker compose run --rm mcts mcts lint files`,
`docker compose run --rm mcts mcts lint all`, and
`docker compose run --rm mcts mcts check-code` on 2026-05-18. Phases `2`
through `6` remain `Done` on their owned surfaces. Phases `7` and `8` are
`Active` on an implementation baseline that includes: a Cabal package with the
pinned GHC 9.14.1 / Cabal 3.16.1.0
toolchain plus the doctrine-standard dependency envelope in `mcts.cabal`;
Sprint `6.3` closed on 2026-05-16 with the Rust Corridors gameplay port
(8x8 bitfield walls, iterative BFS escapability, post-move 180-degree flip
via `u64::reverse_bits`, uniform-random rollout over real legal moves)
landing in `rust/src/board.rs`, `rust/src/rollout.rs`, and `rust/src/search.rs`,
plus `MCTS.Driver.Dispatch.runBatchDispatch` routing `--backend rust` through
`runForeignSearchGame withRustSearchGame` whenever the cdylib is present;
the cpp-imperative, cpp-functional, and Rust `mcts_*_recompute_move` C ABIs
now stream real parent-perspective `chosen_equity` from the search tree
(Sprint `6.5` partial closure); `MCTS.Verify.Divergence.divergenceVsEqStream`
scores transcripts against sidecar `EqStream`s and `mcts inspect divergence`
emits per-sidecar metrics (Sprint `7.5` partial closure); `cabal.project`
relaxes `config-ini`'s `containers`/`base` upper bounds so `brick-2.12` +
`vty-6.5` resolve under GHC `9.14.1` (Sprint `7.4` unblock) with
`src/MCTS/CLI/Tui/Board.hs` rendering the 9×9 board widget through
`brick`; Sprint `8.2` has run three profile-driven rounds. Round 1 (`IntSet`-backed
BFS) shipped ~6.2× speedup; round 2 (strict-pair `Word64` visited bitmap)
regressed and was reverted; round 3 (wavefront-bitmap BFS over a strict
`Bits128` pair with precomputed direction-block masks) shipped a further
**~52× on legal-moves and ~33× on uct-search** (combined with round 1
that's **~320× / ~200×** vs the original list-based baseline). The
updated Q1 ST snapshot collapses Haskell-vs-cpp-imperative from 10.76×
(`Shortfall 9.76`) to **0.89×** (Haskell *faster* than the non-PGO
smoke library). The bounded canonical 2026-05-18 report card against
canonical container-built artefacts records Q1 ST 2.88×, Q1 MT8 18.93×,
Q2 ST 3.65×, Q2 MT8 10.18×, and verdict
`Shortfall 17.925246987694774`; Sprints `8.4`-`8.7` are therefore blocked
until new profile-directed tuning closes the parity gap. The
`MCTS.Engine.ForeignRecompute` driver feeds
`MCTS.Verify.Divergence.divergenceVsEqStream` end-to-end through
`mcts inspect divergence`. `MCTS.CLI.Tui.Play` ships a brick `App`
event loop for `mcts play` with legacy-notation move input, real
`:hint`/`:undo`/`:quit` handling, and `:save` hand-play transcript writes
addressed by `sha256(run_config || move_history)` (pure dispatcher plus
write/decode path unit-tested); the shared TUI board
widget renders pawn cells plus horizontal and vertical wall segments;
the thin `app/Main.hs`;
the `CommandSpec` registry; the `optparse-applicative` parser rendered from
that registry via `commandParserInfo`; the full v1 transcript codec with the
14-field engine envelope; the `MEQ1` binary equity sidecar with same-directory
temp-file + rename writes plus fsync parity with the transcript writer;
the `Env` record and `ReaderT App` monad;
`MCTS.Plan` doctrine-shaped `buildPlan`, `applyPlan`,
`applySubprocessPlan`, `applyWithEnv`, `applySubprocessWithEnv` helpers;
the dependency-edge-aware `prerequisiteRegistry` with `transitiveClosure`,
`registryHasCycle`, exact GHC/Cabal probes, LLVM/BOLT 19 probes, Rust 1.95.0
probes, `ld.lld-19`, foreign shared-library artefact nodes, profile-directory
nodes, and `mimalloc` probing; a real ST-arena MCTS engine
(`MCTS.Search.Arena` + `MCTS.Search.UCT`) wired through every backend's
driver; deterministic multi-worker game dispatch; the pinned monotonic clock
(`getMonotonicTimeNSec`) for bench timing with an injectable test hook;
baseline equity-sidecar cache inspection/pruning with originator markers and Plan/Apply
pruning; layered envelope verify (cohort-invariant +
per-backend-slot fields); real arena-MCTS foreign-backend engines under
`cpp-legacy/legacy-core/`, `cpp-imperative/engine/`, `cpp-functional/engine/`,
and `rust/src/` exposing the doctrine-shaped envelope C ABI accessors
(`mcts_legacy_get_envelope`, `mcts_imperative_get_envelope`,
`mcts_functional_get_envelope`, `mcts_rust_get_envelope`); full
visit-vector Haskell FFI drivers that drive backends (i), (ii), and (iii)
through `withDynamicSearchGame` plus dynamic envelope loaders for all four
foreign backends; C++ backends (ii) and (iii) compile under the doctrine C++23
flag set with hidden visibility, default-visible C ABI exports, and `mimalloc`,
with the shared C++ 19-step PGO+BOLT pipeline closed across
`cpp-imperative`/`cpp-functional` through Sprints `5.3` and `6.4`;
backend (iv) Rust split into the planned module topology with `mimalloc::MiMalloc`
as the global allocator, a real Corridors gameplay port, the full
visit-vector/recompute C ABI, real `--backend rust` dispatch through
`runForeignSearchGame withRustSearchGame` whenever the cdylib is present, and
the `rustPgoBoltPlan` Plan/Apply harness validated through PGO train/merge/use
plus BOLT training/install on amd64; split generated-artifact registries in
`MCTS.Generated.Paths` and `MCTS.Generated.Sections` with marker-delimited
`GeneratedSectionRule` support and the governed CLI command matrix generated
inside `documents/engineering/cli_command_surface.md`; the full
forbidden-symbol set in `.hlint.yaml` plus the conservative
`mcts-haskell-style` source-walker guard, an unconditional `cabal format`
temp-file round-trip, and mandatory container-owned `fourmolu`/`hlint`
execution. Phase `1` now adopts the separate formatter-tools compiler policy by
building `fourmolu-0.19.0.1` and `hlint-3.10` into
`/opt/mcts-style-tools/bin/` with pinned style GHC `9.12.4`, while the project
compiler remains GHC `9.14.1`. Host-level fallback to ambient toolchains or
style binaries is never allowed. The baseline also includes byte-level goldens for the
transcript wire format and the CLI surfaces, and all five Cabal test-suite
stanzas. The validation gate for this baseline
is `docker compose run --rm mcts mcts test all` under the pinned GHC `9.14.1`
toolchain.

## Current Validation Boundary

After the 2026-05-18 Compose-only operator-surface doctrine edit, the
selected-backend `mcts play` AI dispatch, and the replay cache-miss originator
recompute path, focused validation passed through the canonical Compose
entrypoint:
`docker compose run --rm --build mcts mcts test mcts-unit`,
`docker compose run --rm mcts mcts lint files`,
`docker compose run --rm --build mcts mcts lint all`,
`docker compose run --rm mcts mcts check-code`, and `git diff --check`.
The selected-backend ABI changes also pass
`docker compose run --rm mcts mcts build cpp-legacy`,
`docker compose run --rm mcts mcts build cpp-imperative`,
`docker compose run --rm mcts mcts build cpp-functional`, and
`docker compose run --rm mcts mcts build rust`. The unit pass includes the updated
`forbiddenPathRegistry` expectation, the architecture-normalized transcript
byte-golden assertion for codec fixtures, the refreshed Q6 `10000`-simulation
legacy fixture guard, and the TUI dispatcher assertion that a foreign-selected play
backend advances an AI turn and records the resulting visit vector. It also covers
`mcts inspect replay` cache-miss preparation: a missing originator `.eq` sidecar is
recomputed, visit-checked under the transcript RNG contract before writing, and then
reused on the next open without recomputing. The 2026-05-18 full lifecycle gate
`docker compose run --rm --build mcts mcts test all` passed and recorded the
bounded canonical report-card verdict.

This is **not** the final parity-proven architecture. All four foreign
backends — (i) cpp-legacy, (ii) cpp-imperative, (iii) cpp-functional, and
(iv) rust — now dispatch through real arena-MCTS engines behind the
visit-vector C ABI when their shared libraries are present, and `mcts play`
uses the selected backend's dynamic FFI search path for AI turns when the
matching shared library exists (falling back to the logical Haskell path only
when the library is absent). The Rust
backend, in particular, drives a real Corridors gameplay loop (pawn moves
+ wall placement + BFS escapability) emitting canonical action IDs. The
real sprint-owned remaining work stays explicit: the live FFI cohort determinism
gap tracked in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
and the Phase `8` performance-parity proof after the canonical report card
recorded `Shortfall 17.925246987694774`. Sprints `8.4`-`8.7` stay `Blocked`
rather than being marked `Done` until a future parity gate passes against the
real artefacts.

## Document Index

| Document | Purpose |
|----------|---------|
| [development_plan_standards.md](development_plan_standards.md) | Conventions for maintaining the development plan |
| [00-overview.md](00-overview.md) | Vision, target outcome, doctrine scope, and hard constraints |
| [system-components.md](system-components.md) | Authoritative target component inventory for the MCTS Haskell CLI and its five backends |
| [phase-0-planning-documentation.md](phase-0-planning-documentation.md) | Phase 0: Planning and documentation topology |
| [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md) | Phase 1: Haskell CLI surface, `CommandSpec`, lint stack |
| [phase-2-transcript-codec-and-determinism.md](phase-2-transcript-codec-and-determinism.md) | Phase 2: Transcript codec, RNG, and determinism contract |
| [phase-3-haskell-engine.md](phase-3-haskell-engine.md) | Phase 3: Backend (v) Haskell engine |
| [phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md) | Phase 4: Backend (i) C++ legacy port and FFI bridge |
| [phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md) | Phase 5: Backend (ii) C++ imperative steelman with PGO+BOLT |
| [phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md) | Phase 6: Backends (iii) C++ functional-style and (iv) Rust |
| [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md) | Phase 7: Cross-backend verify, test stanzas, POC report card |
| [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md) | Phase 8: Haskell performance parity closure and retirement protocol |
| [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) | Cleanup and retirement ledger |

## Status Vocabulary

| Status | Meaning | Emoji |
|--------|---------|-------|
| **Done** | Deliverables implemented for the sprint-owned surface, validated, and aligned in docs | ✅ |
| **Active** | Work has started and remaining implementation or documentation work is explicitly listed | 🔄 |
| **Planned** | Ready to start once execution reaches the sprint in sequence | 📋 |
| **Blocked** | Closure depends on an unmet prerequisite outside ordinary sprint order, or on a prior sprint that has not closed when this work is reached | ⏸️ |

## Definition of Done

A sprint can move to `Done` only when all of the following are true:

1. Its deliverables are implemented in the worktree.
2. Its validation commands pass through the canonical `mcts` surface (or, for Phase `0`,
   through the manual lint and grep audits named in this plan until Phase `1` lands the
   `mcts check-code` command).
3. The docs listed in `Docs to update` are aligned with the implemented behavior.
4. Sprint-owned cleanup or retirement entries are reflected in
   [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
5. No sprint-owned blocker or remaining work survives.
6. The doctrine sections the sprint adopts (when any) are cited by name in the
   `Deliverables` block per standards rule L.

## Phase Overview

| Phase | Name | Status | Document |
|-------|------|--------|----------|
| 0 | Planning and Documentation Topology | ✅ Done | [phase-0-planning-documentation.md](phase-0-planning-documentation.md) |
| 1 | Haskell CLI Surface, `CommandSpec`, Lint Stack | ✅ Done | [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md) |
| 2 | Transcript Codec, RNG, and Determinism Contract | ✅ Done (full v1 transcript/envelope codec, cache lookup, splitmix, MEQ1 sidecars, originator markers) | [phase-2-transcript-codec-and-determinism.md](phase-2-transcript-codec-and-determinism.md) |
| 3 | Backend (v) Haskell Engine | ✅ Done (strict Word64 board baseline, recursive ST-arena UCT, deterministic tie-break, bench wiring, recompute) | [phase-3-haskell-engine.md](phase-3-haskell-engine.md) |
| 4 | Backend (i) C++ Legacy Port and FFI Bridge | ✅ Done (legacy core, FFI bindings, shared C++ RNG, full transcript driver via `mcts_legacy_search_move`, external Q6 fixtures via `legacy-to-wire`, verify legacy-parity routed through real backend (i), envelope post-link patch + runtime CPU/FP probes + foreign-engine recompute landed) | [phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md) |
| 5 | Backend (ii) C++ Imperative Steelman with PGO+BOLT | ✅ Done (Sprints 5.1/5.2/5.3/5.4/5.5 closed: arena-MCTS steelman engine — flat children, Word16 ply counter, thread_local move buffer, __builtin_prefetch, alignas(64); shared 19-step typed Subprocess PGO+BOLT pipeline with BOLT `-instrument` self-recording, canonical FFI training installs, idempotence/failure-mode/backend-rewrite tests, and explicit PGO fallback when BOLT data is absent; cpp-imperative + cpp-functional engine TUs and C ABI shims compile under `-fno-exceptions`; the per-rollout scratch-board item is closed as "single mutable snapshot + move-assign per ply") | [phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md) |
| 6 | Backends (iii) C++ Functional-Style and (iv) Rust | ✅ Done (Sprints 6.1/6.2/6.3/6.4/6.5 closed: backend (iii) has functional-style descent/data-flow internals, visit-vector/recompute dispatch, and the shared C++ canonical training/install pipeline; backend (iv) has real arena-MCTS + Corridors gameplay dispatch through FFI, cached Rust `read_visits`, full PGO train/merge/use and BOLT training/install on amd64; all foreign backends expose live envelope probes including `libm_id` + post-link `engine_build_id`. C++ shared-library BOLT still falls back to PGO in the pinned container and is tracked for Phase 8 reporting, not Phase 6 closure.) | [phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md) |
| 7 | Cross-Backend Verify, Test Stanzas, POC Report Card | 🔄 Active (Sprint 7.5 closure: `divergenceVsEqStream` + `mcts inspect divergence` per-sidecar + foreign-FFI live-driven divergence rows + live-envelope stamping/verification via `mcts_<backend>_get_envelope()` in integration + real `mcts-integration` stale-cache hard-fail/`--allow-stale` warning coverage + envelope-mismatch tests + report-card Q1/Q2/Q5 typed fields plus divergence table/JSON rendering + bounded `mcts-integration` report-card/sidecar coverage + measured logical `G_V` report-card row population; Q6 fixture closure: `test/golden/legacy/transcripts/amd64/` was regenerated at `S_LP_SIMS = 10000` from the `/home/matt/MCTS_legacy` core-equivalent port and `mcts-integration` now asserts hash names plus the full legacy parity envelope; Sprint 7.4 substantial closure: `brick`/`vty` unblock, interactive `MCTS.CLI.Tui.Play` with move parser + `:hint`/`:undo`/`:quit`, `:save` hand-play transcript writes, selected-backend AI dispatch through dynamic FFI when a foreign shared library is present, TTY-aware `MCTS.App.runPlay` and `MCTS.CLI.Inspect.inspectReplay` dispatch, `MCTS.CLI.Tui.Replay` forward/back navigator with cached sidecar overlays plus originator cache-miss recompute/visit-checking before TUI start and `r`-key on-demand backend columns, shared wall-aware board rendering, and a stable board/status layout golden; Sprint 7.2 typed cohort closure adds GADT-shaped `VerifyBackend` / `LegacyParityBackend` parser surfaces and hard-fail `VerifyMismatch` logical rollout/self-play cohorts validated by unit, cross-backend, legacy-parity, and the full `mcts test all` gate. Remaining: live FFI cohort promotion tracked in the deletion ledger.) | [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md) |
| 8 | Haskell Performance Parity Closure | 🔄 Active (Sprint 8.1 closed; Sprint 8.2 three profile-driven rounds — round 1 `IntSet`, round 2 reverted, round 3 wavefront-bitmap BFS (**~320× combined speedup on legal-moves, ~200× on uct-search**); Sprint 8.3 is closed with the bounded canonical report card: Q1 ST 2.88×, Q1 MT8 18.93×, Q2 ST 3.65×, Q2 MT8 10.18×, and verdict `Shortfall 17.925246987694774`. The canonical C++ build path installed PGO-only fallback artefacts where BOLT data was unavailable. Sprints 8.4-8.7 are blocked until new profile-directed Haskell tuning reaches parity.) | [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md) |

## Current Plan Status

The repository has moved past bootstrap into an active implementation baseline.
Implemented in the worktree:

- `mcts.cabal`, `cabal.project`, `app/Main.hs`, `src/MCTS/**`, `test/**`,
  `documents/cli/commands.md`, `share/man/man1/mcts.1`,
  `share/completion/{bash,zsh,fish}/`, `fourmolu.yaml`, `.hlint.yaml`, `.gitignore`.
- CLI command families: `bench`, `verify`, `inspect`, `test`, `lint`, `docs`,
  `commands`, `help`, `check-code`, `build`, and a non-interactive `play` smoke.
- Deterministic transcript encode/decode with the full v1 wire format
  including the 14-field engine envelope (cohort-invariant + per-backend
  slot fields); cache root resolution; git-style prefix lookup with the
  unique-prefix property exercised in `mcts-unit`; action enumeration;
  move notation; `splitmix64` seed mixing; the binary `MEQ1` equity
  sidecar codec with same-directory temp-file + rename writes and
  `castWord64ToDouble` round-trips. Byte-level transcript and CLI goldens live under
  `test/golden/`.
- A real ST-arena MCTS engine: `MCTS.Search.Arena` (SoA `STUArray` arena
  with `parentIdx`, `firstChildIdx`, `nChildren`, `actionId`, `visits`,
  `valueSum`) and `MCTS.Search.UCT.uctSearch` (UCT selection +
  random-rollout + backpropagation). The driver dispatches every per-move
  search through it. Cross-backend visit-count equality holds under
  `--rng cpp`; per-backend salt under `--rng native` keeps bench
  transcripts distinct.
- `inspect show --with-equity` writes a recompute-backed logical equity sidecar
  and renders the stream-backed per-move equity column. `inspect divergence`
  now resolves the target transcript and renders metrics from
  `MCTS.Verify.Divergence` rather than a fixed placeholder.
- `inspect show --envelope` renders the current transcript envelope, and
  `mcts verify ... --allow-stale` is parsed and routed through the layered
  envelope verifier covering `rng_source`, `shared_rng_build_id`,
  `cohort_config_hash`, `engine_build_id`, `compiler_id`, `fp_flags`,
  `cpu_features`, `fp_env`; JSON verify output includes structured
  `warning_details` for downgraded backend-slot warnings.
- The `Env` record and `App` monad (`ReaderT Env IO`) scaffold with the
  monotonic-clock test hook. `MCTS.Plan` exposes the doctrine-shaped
  `buildPlan` / `applyPlan` / `applySubprocessPlan` / `applyWithEnv` /
  `applySubprocessWithEnv` helpers; `MCTS.CLI.Bench` uses `monotonicNanos`
  (`getMonotonicTimeNSec`).
- The prerequisite registry carries dependency edges and resolves transitively;
  the GHC/Cabal nodes check exact pinned versions via the typed `Subprocess`
  capture boundary, the legacy shared-library node checks
  `cpp-legacy/build/libmcts_cpp_legacy.so`, and the unit suite asserts the
  registry is acyclic.
- Phase 8 GHC tuning flags landed in `mcts.cabal`: `-O2 -fllvm
  -funbox-strict-fields -fspecialise-aggressively
  -fexpose-all-unfoldings -flate-dmd-anal
  -fmax-simplifier-iterations=20 -fworker-wrapper
  -fstatic-argument-transformation`. The executable adds `-threaded`
  and the doctrine RTS pin `-A64m -n4m -qg1 -qb -T`. `INLINEABLE`
  pragmas mark selected hot-path entries in `MCTS.Rng.Mix`,
  `MCTS.Engine`, `MCTS.Search.Arena`, and `MCTS.Search.UCT`.
  `-optlo-mcpu=native` and `-optlc-mcpu=native` are intentionally
  excluded per Sprint `8.1`'s closure note (LSE-instruction assembler
  refusal on aarch64); the deferred re-introduction is tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).
  `SPECIALIZE` is a no-op for the current monomorphic kernel and the
  `MutableByteArray#` migration is a profile-driven Sprint `8.2` decision.
- Transcript writes are durable: `MCTS.Transcript.writeFileAtomically`
  uses `openBinaryTempFile`, `hFlush`, `System.Posix.Unistd.fileSynchronise`
  on the temp file's Fd, atomic rename, and best-effort fsync of the
  parent directory.
- The recompute path lives in `MCTS.Engine.Recompute`:
  `recomputeEquities` / `recomputeEqStream` replay a transcript through
  the in-process UCT and emit per-move equity records; under `--rng cpp`
  it hard-asserts visit equality and short-circuits with `AppError
  RecomputeMismatch` on the first disagreement.
  `mcts inspect show --with-equity` writes the recomputed sidecar and renders the
  stream-backed per-move equity column.
- Haskell-side FFI scaffolding lives under `src/MCTS/FFI/`:
  `MCTS.FFI.Common` (bracket helpers, `EngineEnvelope` record,
  `liftFFI` that converts foreign exceptions to `AppError FFIFailure`,
  and `withDynamicBoard` using `dlopen` / `dlsym` plus
  `foreign import ccall "dynamic"`),
  plus per-backend `with<Backend>Board` wrappers in `MCTS.FFI.CppLegacy`,
  `CppImperative`, `CppFunctional`, `Rust`.
- The forbidden-path set is a typed `forbiddenPathRegistry :: [ForbiddenPath]`
  value carrying a rationale per entry; `mcts lint files` consumes it.
- The canonical `MCTS.Error.renderError` boundary has the doctrine-pinned
  `AppError -> Text` shape; `MCTS.CLI.Output.renderError` is the current
  `String` adapter for command runners. Global output parsing now defaults to
  `table` on a TTY and `plain` otherwise.
- Five Cabal test stanzas: `mcts-unit`, `mcts-integration`,
  `mcts-cross-backend`, `mcts-legacy-parity`, `mcts-haskell-style`. The
  style stanza walks every `.hs` file and rejects tab characters plus the
  conservative forbidden-symbol subset it can check textually; it also runs
  `cabal format` through a temp-file round-trip and invokes the mandatory
  container-installed `fourmolu` / `hlint` binaries from
  `/opt/mcts-style-tools/bin/`. The mandatory external formatter path is closed by
  pinning a separate formatter-tools GHC `9.12.4` and installing
  `fourmolu-0.19.0.1` plus `hlint-3.10` into the container; the fuller hard-error
  rule set lives in `.hlint.yaml` for that external `hlint` path.
- `mcts lint files` fails on tracked generated-file drift, `mcts lint haskell`
  delegates to `cabal test mcts-haskell-style`, and `mcts check-code` runs lint/docs
  plus `cabal build all` through the dedicated `MCTS.CheckCode` module.
- `mcts test all` routes recursive CLI invocations through `cabal exec mcts -- ...`,
  and `mcts bench rollouts|selfplay` accepts backend cohorts in the report-card
  command form.
- Smoke backend source homes under `cpp-legacy/`, `cpp-imperative/`,
  `cpp-functional/`, and `rust/` each declare the doctrine-shaped
  envelope struct and the current accessor symbol
  (`mcts_legacy_get_envelope`, `mcts_imperative_get_envelope`,
  `mcts_functional_get_envelope`, `mcts_rust_get_envelope`) returning
  process-static memory. `cpp-legacy/legacy-core/` now mechanically imports the legacy
  `backend/core` board and MCTS sources, and the legacy C ABI delegates board
  allocation / UCT selection to those types. Backends (ii) and (iii) smoke-build
  with the target C++23 flag baseline, hidden visibility, default-visible C ABI
  exports, and `mimalloc`; backend (iv) Rust is split into the planned module
  topology and uses `mimalloc::MiMalloc` as its global allocator. The Haskell
  FFI layer has bounded smoke drivers, live envelope loaders for all four
  foreign shared libraries, and verify-time conversion of those envelopes into
  transcript headers when a cdylib is present.
  The shared C++ RNG also exposes `cpp_rng_split_seed`, with `MCTS.Rng.Cpp`
  checking it against the Haskell splitmix mixer when the library is built.
- `MCTS.CLI.Docs` exposes `GeneratedSectionRule`,
  `applyGeneratedSection`, and `checkGeneratedSection` for
  marker-delimited generated regions (`<!-- mcts:<key>:start --> ...
  <!-- mcts:<key>:end -->`); the current registry includes the
  `command-matrix` section in
  `documents/engineering/cli_command_surface.md`.

Remaining work is the difference between this baseline and the target end state:
promoting the live FFI cohort once the compiled engines are deliberately aligned,
running a new profile-directed Haskell tuning round after the recorded
`Shortfall 17.925246987694774`, and then executing the retirement protocol's
frozen golden anchors under `test/golden/<backend>/` once parity holds.

The retirement protocol (i)→(ii)→(iii)→(v) named in [00-overview.md](00-overview.md) and
owned by Phase `8` is the long-running closure mechanism: each retiring backend's
recorded transcripts and throughput numbers freeze in `test/golden/` as the regression
anchor for the surviving cohort. Backend (iv) Rust stays as a long-running second opinion
throughout. Until Phase `8` closure, no backend retires and all five remain live.

## Sprint Dependencies

```mermaid
flowchart TB
    P0[Phase 0: Planning & Docs]
    P1[Phase 1: CLI Surface & Lint]
    P2[Phase 2: Transcript & RNG]
    P3[Phase 3: Haskell Engine v]
    P4[Phase 4: C++ Legacy i + FFI]
    P5[Phase 5: C++ Steelman ii]
    P6[Phase 6: C++ Functional iii + Rust iv]
    P7[Phase 7: Verify & Report Card]
    P8[Phase 8: Haskell Parity Closure]
    P0 --> P1
    P1 --> P2
    P2 --> P3
    P3 --> P4
    P3 --> P5
    P5 --> P6
    P4 --> P7
    P6 --> P7
    P7 --> P8
```

Phase `2` (transcript codec, RNG, determinism contract) gates every backend because the
wire format and the `splitmix64(master_seed, game_index)` per-game seed derivation are the
determinism contract every backend must honour. Phase `3` (Haskell engine) gates Phases
`4`–`6` because the FFI bridge from Haskell into the C ABI backends builds on the same
typed `Env` and `Subprocess` discipline established in Phase `1` and exercised by the
Haskell backend first. Phases `4`, `5`, and `6` then proceed in parallel after Phase `3`
closes — backend (i) is the regression-anchor port, backends (ii) and (iii) are the
performance ceiling and its functional sibling, and backend (iv) Rust is the
cross-language second opinion. Phase `7` joins the five backends in one round-robin
`mcts verify` cohort and emits the POC report card. Phase `8` closes the Haskell tuning
loop until backend (v) matches backend (ii) within tolerance on Q1 and Q2.

## Exit Definition

This plan is complete only when all of the following are true:

1. The repository holds five backends behind one `mcts` binary built by Cabal: backend
   (i) `cpp-legacy/`, (ii) `cpp-imperative/`, (iii) `cpp-functional/`, (iv) `rust/`, and
   (v) the native Haskell engine under `src/MCTS/`.
2. `mcts bench rollouts` and `mcts bench selfplay` produce comparable wall-clock numbers
   across all live backends from a single Cabal-driven monotonic clock
   (`GHC.Clock.getMonotonicTimeNSec` in the current Haskell baseline).
3. `mcts verify rollouts` and `mcts verify selfplay` agree bit-for-bit on visit counts
   across the live `(ii)..(v)` cohort under `--rng cpp`, with the `VerifyBackend` type
   excluding backend (i) at the type level.
4. `mcts verify legacy-parity` agrees on visit counts across all five backends under
   `max_plies = 10000` and the pinned fixture seed, with `LegacyParityBackend` requiring
   backend (i) at parse time.
5. `mcts test all` runs every Cabal test-suite stanza (`mcts-unit`, `mcts-integration`,
   `mcts-cross-backend`, `mcts-legacy-parity`, `mcts-haskell-style`) and emits the tidy
   report-card summary block answering Q1–Q7, with the report-card knobs `G_R=1_000`,
   `G_S=4`, `G_V=4`, `G_LP=2`, `S_BENCH=500`, `S_VERIFY=500`,
   `S_LP_SIMS=10_000`, `S_LP=42` pinned in `cabal.project`.
6. Pure Haskell backend (v) matches backend (ii) C++ steelman on Q1 (random rollouts) and
   Q2 (self-play) within the parity tolerance per
   [../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md)
   (`HASKELL_PARITY_TOLERANCE = 0.05`), both single-threaded and on 8 workers.
   If Haskell falls short — including shortfalls in the 5–15% PGO-attributable band — the
   gap is recorded against the one-known-asymmetry PGO note in
   `documents/engineering/compiler_runtime_tuning.md` rather than papered over.
7. Same-backend determinism (Q4) holds for every backend across 3 seeds: same backend,
   same master seed, same RNG source, and same logical game inputs produce identical
   determinism payloads under the `mcts-integration` stanza.
8. Backend (i) reproduces `MCTS_legacy` byte-for-byte on benchmark (b) (Q6), validated by
   the `test/golden/legacy/` fixture set regenerated through `mcts build
   legacy-fixtures` from the legacy implementation under `~/MCTS_legacy`.
9. The retirement chain (i)→(ii)→(iii)→(v) closes, with frozen golden transcripts and
   throughputs in `test/golden/` as the surviving regression anchor for each retired
   backend; backend (iv) Rust remains live as the cross-language second opinion.
10. The toolchain is pinned at GHC `9.14.1` and Cabal `3.16.1.0`. `mcts.cabal` declares
    `tested-with: ghc ==9.14.1` and `cabal.project` declares `with-compiler: ghc-9.14.1`.
11. The Haskell stack uses `optparse-applicative`, `text`, `bytestring`, `aeson`,
    `prettyprinter`, `prettyprinter-ansi-terminal`, `ansi-terminal`, `path`, `path-io`,
    `typed-process`, `safe-exceptions`, `tasty`, `tasty-hunit`, `tasty-quickcheck`,
    `tasty-golden`, and `temporary` per the doctrine's standardized stack. The two
    deviations are `brick` + `vty` for the `play` and `inspect replay` TUIs only, and
    `dhall` is unused because daemon configuration is out of scope.
12. Library-first layout: `app/Main.hs` is thin and logic lives under `src/MCTS/`.
13. `mcts.cabal` declares the five test-suite stanzas with `type: exitcode-stdio-1.0` and
    `tasty` as the in-stanza runner.
14. `CommandSpec` is the source of truth for the parser, command tree
    (`mcts commands --tree`), JSON schema (`mcts commands --json`), markdown command
    reference, manpages, and shell completion scripts. The parser is a renderer of the
    spec, not the source of truth.
15. `Subprocess` is the only IO boundary for subprocess execution. `callProcess`,
    `readCreateProcess`, `System.Process` constructors, and `typed-process` smart
    constructors are hlint-forbidden outside the `runStreaming` / `capture` interpreter.
16. Every Plan/Apply command supports `--dry-run` and `--plan-file <path>` (`mcts test
    all`, the build harness, anything that mutates external state).
17. One `prerequisiteRegistry` spans every backend's toolchain (GCC, LLVM/BOLT, `rustc`,
    `mimalloc`, `ghcup`, the PGO/BOLT profile directories) and emits
    `AppError PrerequisiteUnmet` carrying the failing `nodeId`, description, and remedy
    hint.
18. Single `AppError` ADT with `renderError :: AppError -> Text` as the only Text
    rendering at the CLI boundary; `print`, `exitFailure`, and direct terminal formatting
    are hlint-forbidden outside `src/MCTS/CLI/Output.hs`.
19. `fourmolu.yaml` at repo root pins the twelve doctrine-mandated settings
    (`indentation`, `column-limit`, `function-arrows`, `comma-style`,
    `import-export-style`, `indent-wheres`, `record-brace-space`,
    `newlines-between-decls`, `haddock-style`, `let-style`, `in-style`, `unicode`); the
    `mcts-haskell-style` stanza enforces them plus the `cabal format` temp-file
    round-trip byte-equality check through a separate pinned formatter-tools GHC
    install (`ghc-9.12.4`, `fourmolu-0.19.0.1`, `hlint-3.10`) under
    `/opt/mcts-style-tools/bin/` inside the container. Host-level fallback is
    not allowed.
20. The transcript wire format is little-endian binary with no schema-library
    dependency: one-game files, header carrying the backend-specific run config,
    per-move records of `(action_id, visits)` sorted ascending by action ID, equity
    excluded. The canonical single-byte action enumeration in
    [system-components.md](system-components.md) is authoritative.
21. The transcript cache root resolves `--cache-dir <path>` → `./.mcts-cache/`
    inside the container. The `mcts` binary does not read cache-root environment
    variables. Hash-prefix lookup is git-style: shortest unique prefix ≥ 4 hex chars; `AppError
    TranscriptNotFound` and `AppError TranscriptAmbiguous` cover the miss and ambiguous
    cases.
22. Equity is recomputed deterministically by the same backend during `inspect show
    --with-equity` and, for `inspect replay`, when the originator `.eq` overlay is
    missing before the TUI starts. The replay recompute checks the transcript's visit
    table under `--rng cpp` before writing a sidecar; cross-backend equity equality is
    not asserted, only cross-backend visit-count equality.
23. The Docker development environment provides a single LLVM pinned in
    `docker/Dockerfile` shared by GHC `-fllvm` and BOLT; the canonical host
    entrypoint is `docker compose run --rm mcts mcts <command>`. There is no
    long-running daemon container, no bind-mounted workspace, no Compose-level
    environment-variable block, and no `sleep infinity` placeholder. The first
    `docker compose run --rm` call builds the image when it is absent. All supported
    project work happens through this short-lived container entrypoint. Host-level
    `.build/` artefacts, repository `.sh` scripts, and `bootstrap/` helpers are
    unsupported.
24. [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) contains no
    unresolved cleanup once Phase `8` closes and the retirement protocol completes; the
    `Completed` table preserves the retirement history.

## Related Documents

- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
- [../documents/documentation_standards.md](../documents/documentation_standards.md)
