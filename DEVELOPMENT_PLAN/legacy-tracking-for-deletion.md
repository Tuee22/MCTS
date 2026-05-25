# Legacy Tracking

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[00-overview.md](00-overview.md), [system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md),
[phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md),
[phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md),
[phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md),
[phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md),
[../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md),
[../documents/engineering/compiler_runtime_tuning.md](../documents/engineering/compiler_runtime_tuning.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Record every remaining compatibility helper, deprecated path, doctrine
> deviation, and stale tooling surface still slated for deletion or correction.

> **Authoritative Reference**:
> [development_plan_standards.md → I. Explicit Cleanup and Removal Ledger](development_plan_standards.md#i-explicit-cleanup-and-removal-ledger)

## Ledger Status

The intended repository end state is one Haskell CLI with five first-class backend
slots: `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`, and `haskell`.
The stale two-backend drift from the 2026-05-19 cleanup is corrected. The 2026-05-21
audit closed the remaining build-surface gap: the supported
`mcts build cpp-imperative` and `mcts build cpp-functional` Plan/Apply paths now
drive the C++ PGO/BOLT target sequence. The 2026-05-22 Dockerfile migration moved
normal backend artefact production into image construction, so runtime validation
checks and consumes the resulting shared libraries instead of rebuilding them.
The 2026-05-22 fail-closed doctrine now requires the C++ and Rust steelman
PGO/BOLT workflows to succeed inside the Dockerfile build. The 2026-05-23
reclosure removed the PGO-only, BOLT-missing, and unoptimized fallback install
paths, switched post-BOLT envelope patching to LLVM objcopy, and added final
installed-library smokes so corrupted BOLT outputs fail the image build. Sprint
`8.3` refreshed the report-card evidence against these successful PGO+BOLT
artefacts on 2026-05-23. Sprint `8.10` then replaced the remaining
profile-workload residue with the bounded played-game profile suite. The metric
audit reopened profile representativeness for Sprint `8.11` after terminal-playout,
search-iteration, and played-game report-card rows became explicit; Sprint `8.11`
closed that review with a Dockerfile rebuild that trained terminal-playout,
search-iteration, legacy played-game rollout, and self-play workloads before the
refactored report-card rerun.

The validation-data doctrine sweep remains closed: normal tests do not require
checked-in transcripts, throughput anchors, renderer snapshots, schema fixtures, or
other generated validation data. Evidence needed for audit is generated in memory,
under temporary directories, or under explicit operator-provided artifact roots.

The 2026-05-21 evidence-surface audit reopened doctrine-deviation residue where
governed docs or comments overclaim the current code. Sprints `1.10`, `2.8`,
`5.5`, `6.6`, `7.6`, and `8.9` have closed the Phase `1` generated-doc/style-policy
residue, the Phase `2` transcript/sidecar identity residue, the backend (ii)
compact ABI contract residue, the backend (iii)/(iv) ABI/build-artifact wording
residue, the replay/divergence evidence-label residue, and the compiler-tuning
test-stanza wording residue. The 2026-05-23 fail-closed PGO/BOLT reclosure moved
the build-failover rows to Completed, and Sprint `8.10` moved the profile
representativeness row to Completed. The 2026-05-24 harmony sweep then moved the
README-topology, lint-write, envelope-gating, rollout-byte-consumption,
FFI-domain-conversion, and divergence-metric rows to Completed. All five backend
slots remain first-class.

The 2026-05-24 benchmark-metric audit added stale benchmark labels and report-card
rows to this ledger. Sprint `3.8` added explicit `terminal-playouts` and
`search-iters` benchmark leaves, and Sprint `7.8` split the report card into
unit-aware Q1a/Q1b/Q2/Q5 rows. The 2026-05-25 played-game renderer cleanup
removed the derived simulation-rate output so `games/s` is the only played-game
throughput unit. Sprint `8.11` closed the profile-suite review and fresh parity
rerun, so no metric-suite cleanup row remains pending.

Two classes of entries populate this ledger over time:

1. **Doctrine-deviation residue.** Any worktree behavior that the implemented code
   does not yet honour against an in-scope doctrine section, scheduled through the
   owning sprint per standards rule L.
2. **Stale-surface residue.** Any code, command, document, generated text, or source
   comment that contradicts the five-backend architecture or describes the C++ backends
   as inactive.

`MCTS_legacy` itself lives at `~/MCTS_legacy/` and is not in this repository; legacy
entries here track only shims and compatibility helpers introduced *inside* this
repository.

## Pending Removal

None.

## Pending Removal Notes

Pending-removal rows move to `Completed` only after the corrected surface is
implemented, governed docs are aligned, generated docs are regenerated or checked,
and the canonical validation command for that surface passes through
`docker compose run --rm mcts mcts <command>`. For PGO/BOLT failover rows,
closure also requires a Dockerfile build that exits non-zero on missing profile
data instead of publishing a fallback shared library.

## Completed

| Item | Removed In | Notes |
|------|------------|-------|
| Derived played-game simulation-rate column | Sprint 7.8 follow-up, 2026-05-25 | `src/MCTS/CLI/Bench.hs` now renders played-game benchmarks with only `games/s` in text output and `games_per_second` in JSON. Governed metric docs identify terminal playout, search-iteration, and played-game throughput as the only supported benchmark units. |
| External legacy-reproduction headline question | Sprint 7.9, 2026-05-25 | Removed the old report-card question that compared backend (i) against external `MCTS_legacy`; the legacy-envelope liveness/overflow gate is now Q6 and the report card has six questions. `mcts build legacy-fixtures` remains an optional external audit helper with no numbered report-card role. The Q6 report-card self-play liveness budget is `S_LP_SIMS=4`; the old `10_000` budget belonged to the removed external-reproduction evidence shape. |
| PGO/BOLT profile-suite metric proxy | Sprint 8.11, 2026-05-24 | `src/MCTS/CLI/Build.hs` now trains C++ and Rust PGO/BOLT profiles with terminal playout primitives, search-iteration primitives, legacy played-game rollout batches, and self-play batches. `docker compose run --rm --build mcts mcts test all` validated the aggregate Dockerfile rebuild and refactored report-card rerun end to end, recording final Q1a/Q1b/Q2/Q5 unit-aware evidence and `Verdict: Within tolerance`. |
| Legacy `bench rollouts` metric-name ambiguity | Sprint 7.8, 2026-05-24 | `bench rollouts` remains as a documented legacy played-game workload, while lower-level throughput uses explicit `bench terminal-playouts` and `bench search-iters`. Report-card rows no longer use the legacy `rollouts` label for Q1/Q5 evidence. |
| Report-card Q1/Q5 metric conflation | Sprint 7.8, 2026-05-24 | `src/MCTS/CLI/Test.hs` and `src/MCTS/ReportCard.hs` now render unit-aware Q1a terminal playout (`playouts/s`), Q1b search-iteration (`search-iters/s`), Q2 played-game (`games/s`), and split Q5 scaling rows. Unit tests and integration tests assert the new JSON field names. |
| README-as-contract duplication | Sprint 1.11, 2026-05-24 | `README.md` now stays operator-facing and reference-only: project intent, Compose entrypoint, backend cohort, short command examples, validation gates, and links. Transcript, determinism, FFI, tuning, code-quality, and testing details live in governed docs; stale README section citations were redirected to those owning documents. |
| No-op lint `--write` flags | Sprint 1.11, 2026-05-24 | `mcts lint files --write` trims fixable whitespace/final-newline drift and rewrites fully generated command/man/completion files; `mcts lint docs --write` runs the generated-doc writer before checking; `mcts lint haskell --write` runs pinned Fourmolu and `cabal format` before the style stanza. |
| Envelope provenance fields treated as verifier gates | Sprint 2.9 / Sprint 7.7, 2026-05-24 | `src/MCTS/Verify/Envelope.hs` gates stale backend slots on `backend`, `engine_build_id`, `compiler_id`, `compiler_version`, `fp_flags`, `libm_id`, `cpu_features`, and `fp_env`. `engine_git_commit` and display/cache `build_id` remain provenance-only, with unit coverage proving provenance-only changes do not fail stale checks. |
| Unsigned Haskell rollout modulo | Sprint 3.7, 2026-05-24 | `MCTS.Search.UCT.rollout` now maps consumed `Word64` draws through signed `Int64` remainder semantics before selecting the legal move, matching the determinism contract's signed-`Int` modulo rule. |
| FFI/domain-conversion documentation overclaim | Sprint 4.5, 2026-05-24 | `documents/engineering/backend_ffi_contract.md` now describes the implemented dynamic loader, opaque-handle C ABI, and `Action`/`actionId`/`actionFromId` boundary instead of claiming `.hsc`/`.chs` generation or generic `fromDomain`/`toDomain` wrappers. |
| Per-action divergence metric overclaim | Sprint 7.7, 2026-05-24 | Divergence documentation now states that `EqStream` carries chosen-action equity and `equity_l2_drift` is RMS over the per-move chosen-action series, not a per-action vector comparison. |
| Narrow PGO/BOLT training workload | Sprint 8.10, 2026-05-23 | `src/MCTS/CLI/Build.hs` trains C++ and Rust PGO/BOLT profiles with a bounded played-game suite: legacy `bench rollouts` plus self-play, ST plus MT8, native RNG, seeds `42` and `424242`, `--max-plies 1`, PGO rollout games 2 ST/2 MT8 with `--sims 1`, PGO self-play games 1 ST/1 MT8 with `--sims 500`, and BOLT games 1 ST/1 MT8 for each workload with rollout `--sims 1` and self-play `--sims 100`. C++ training uses scoped dynamic-library loading plus explicit GCOV dump hooks; Rust training keeps the cdylib pinned and relies on process-exit `.profraw` emission. Sprint `8.11` later extended this into the bounded metric-suite profile suite. |
| Tracked PGO/BOLT profile snapshots | Sprint 8.8 follow-up, 2026-05-23 | Removed checked-in `cpp-imperative/pgo-profile/`, `cpp-functional/pgo-profile/`, and `rust/pgo-profile/` generated profile files, and added the C++/Rust PGO+BOLT profile roots to `.gitignore` and `.dockerignore`. The Dockerfile-owned build recipes regenerate fresh profile data and fail closed on missing profile outputs. |
| Fallback-backed parity report-card evidence | Sprint 8.3, 2026-05-23 | The 2026-05-21 amd64 report card remains historical audit evidence only. `docker compose run --rm --build mcts mcts test all` refreshed the report card against fail-closed Dockerfile PGO/BOLT artefacts and recorded Q1 ST 0.05x, Q1 MT8 0.45x, Q2 ST 0.06x, Q2 MT8 0.22x, Q5 Haskell 0.98x, Q5 C++ (ii) 3.70x, zero live-cohort divergence, Q6 PASS, and verdict `Within tolerance`. Sprint `8.10` later superseded this with bounded-profile final evidence. |
| C++ PGO/BOLT fail-open artefact copying | Sprint 5.3, 2026-05-23 | `cpp-imperative/Makefile`, `cpp-functional/Makefile`, and `src/MCTS/CLI/Build.hs` now require non-empty BOLT `.fdata`, surface `llvm-bolt` diagnostics, use LLVM objcopy for BOLT-produced shared objects, and smoke the installed bolted C++ canonical libraries during the Dockerfile build. |
| Rust BOLT PGO-only fallback install | Sprint 6.4, 2026-05-23 | `src/MCTS/CLI/Build.hs` now requires Rust profraw/profdata, BOLT `.fdata`, a bolted cdylib, LLVM objcopy envelope patching, and a final canonical Rust smoke; no PGO-only cdylib is copied to the supported load name when BOLT fails. |
| Runtime backend builds in normal validation | Dockerfile backend-build migration, 2026-05-22 | `docker/Dockerfile` now invokes `mcts build cpp-legacy`, `mcts build cpp-imperative`, `mcts build cpp-functional`, and `mcts build rust` during image construction; `mcts test all` and `mcts test parity-anchor` no longer rebuild foreign backend artefacts at runtime. |
| Generated-section metadata overclaim | Sprint 1.10, 2026-05-21 | `mcts docs check` now verifies governed-doc `**Generated sections**:` metadata against physical marker pairs and the `GeneratedSectionRule` registry; fenced Markdown examples are ignored as examples, not real markers. |
| `check-code` stage-order drift | Sprint 1.10, 2026-05-21 | `mcts check-code` now runs the documented lint/docs/style/build sequence once per stage; validation output contains a single generated-doc check in the lint phase before the warning-clean build. |
| Supported-path partial-function wording drift | Sprint 1.10, 2026-05-21 | `documents/engineering/haskell_code_guide.md` and `documents/engineering/code_quality.md` now describe the narrow hot-path invariant-failure exception instead of claiming an unconditional partial-function ban. |
| Transcript forward-compat overclaim | Sprint 2.8, 2026-05-21 | `src/MCTS/Transcript.hs` now requires `envelope_offset == 48`, rejects unsupported envelope versions, and unit-tests additive v1 envelope trailing bytes. |
| Action smart-constructor overclaim | Sprint 2.8, 2026-05-21 | The governed transcript docs describe the implemented `Action` conversion: legal actions are `0..208`, reserved bytes are not accepted, and `255` remains sentinel-only. |
| Logical sidecar label duplication | Sprint 2.8, 2026-05-21 | Logical build labels normalize to `logical`, sidecar stems render `<backend>-logical`, and current-sidecar pruning follows the same build-label contract. |
| Originator sidecar identity exactness | Sprint 2.8, 2026-05-21 | Phase `2` sidecar identity is backend/build/envelope exact; Sprint `7.6` retains the CLI replay/divergence labeling validation for fallback and foreign recompute streams. |
| Originator-labelled fallback recompute | Sprint 7.6, 2026-05-21 | `inspect show --with-equity` and replay preparation now preserve originator identity: fallback or foreign recompute streams are reported as unavailable/foreign-view evidence and are not written under the transcript originator backend/build slot. |
| Rust-only live divergence recompute wording | Sprint 7.6, 2026-05-21 | `mcts inspect divergence` docs and implementation now cover cached sidecars plus every available live foreign recompute backend, including C++ cdylibs where present, instead of presenting a Rust-only row set as the full live surface. |
| Test-stanza `-fllvm` wording drift | Sprint 8.9, 2026-05-21 | `documents/engineering/compiler_runtime_tuning.md` now states that `-fllvm` is load-bearing on the library, executable, and benchmark stanzas; test stanzas compile small runners and link the optimized library without duplicating `-fllvm`. |
| Backend (ii) compact C ABI contract | Sprint 5.5, 2026-05-21 | `documents/engineering/backend_ffi_contract.md`, `cpp-imperative/c-abi/`, and the Haskell FFI docs now describe the compact live board/search/recompute/read-visits/envelope surface without speculative tree/rng lifecycle handles. |
| Backend (iii)/(iv) compact C ABI contract | Sprint 6.6, 2026-05-21 | `documents/engineering/backend_ffi_contract.md`, `cpp-functional/c-abi/`, `rust/src/c_abi.rs`, and the Haskell FFI docs now describe the compact live ABI with no speculative tree/rng lifecycle handles. |
| Rust instrumented-artefact overclaim | Sprint 6.6, 2026-05-21 | Docs and tooling now describe one optimized Rust FFI artefact; the BOLT-instrumented copy is a temporary build detail, not a supported `_instrumented` artefact. |
| C++ PGO/BOLT Plan/Apply overclaim | Sprint 5.3, 2026-05-21; Dockerfile migration updated 2026-05-22 | `src/MCTS/CLI/Build.hs` now uses `cppPgoBoltPlan` for `mcts build cpp-imperative` and `mcts build cpp-functional`; dry-run and Dockerfile-owned build validation cover both C++ steelman backends, and Sprint 8.3 refreshed the report-card evidence. |
| Unused `perf` prerequisite node | Sprint 5.3, 2026-05-21 | Removed the unused `perf` prerequisite node; the implemented BOLT path uses `llvm-bolt -instrument`, and the build prerequisite closure now covers LLVM/BOLT plus the relevant profile directories and shared-library artefacts. |
| Multi-game transcript file layout | Sprint 7.5, 2026-05-16 | `writeTranscriptPerGame` in `src/MCTS/Transcript.hs` splits batches into one-game-per-file transcripts with per-game splitmix seeds; `MCTS.Driver.runBatchWithGame` reports the resulting hash/path pairs, and `mcts-unit::exercisePerGameTranscriptWriter` covers the behavior. |
| C++ Makefile PGO+BOLT target surface | Sprint 5.3 Makefile baseline, updated Sprint 6.4, 2026-05-18; CLI wiring closed 2026-05-21 | `cpp-imperative/Makefile` and `cpp-functional/Makefile` contain PGO generate/use, BOLT instrument/optimize, and canonical install targets. The supported `mcts build` Plan/Apply wiring for those targets is closed by `cppPgoBoltPlan`. |
| Backend (iv) Rust Corridors gameplay port | Sprint 6.3, 2026-05-16; updated Sprint 7.2, 2026-05-18 | `rust/src/board.rs`, `rust/src/rollout.rs`, and `rust/src/search.rs` carry the real Corridors game state, rollout loop, and arena MCTS, and `MCTS.Driver.Dispatch.runBatchDispatch` routes `--backend rust` through the real FFI engine when the cdylib is present. |
| Foreign-engine recompute streaming to `.eq` sidecars | Sprint 7.5, 2026-05-16 | `MCTS.Engine.ForeignRecompute.foreignRecomputeEqStream` drives backend recompute ABIs through transcripts, `MCTS.Verify.Divergence.divergenceVsEqStream` scores the resulting `EqStream`, and `mcts inspect divergence` renders cached and available foreign recompute rows. |
| Measured Q1-Q6 report-card evidence | Sprint 7.3 / Sprint 8.11 evidence closure, updated by Sprint 7.9 on 2026-05-25 | `docker compose run --rm --build mcts mcts test all` passed against the canonical workload and bounded metric-suite Dockerfile PGO/BOLT artefacts on 2026-05-24. The 2026-05-25 Sprint 7.9 aggregate revalidation passed `docker compose run --rm mcts mcts test all` after removing the external legacy-reproduction headline row, recording Q1a terminal-playout ST 0.06x and MT8 0.38x, Q1b search-iteration ST 0.05x and MT8 0.36x, Q2 played-game ST 0.05x and MT8 0.17x, Q5 Haskell search-iteration scaling 0.97x, Q5 C++ (ii) search-iteration scaling 7.47x, Q5 Haskell self-play scaling 1.03x, Q5 C++ (ii) self-play scaling 3.69x, zero live-cohort divergence, Q6 liveness evidence PASS, and verdict `Within tolerance`. The older 2026-05-23 fail-closed and Sprint 8.10 played-game rows remain historical pipeline evidence. |
| Pure Haskell parity proof vs backend (ii) | Sprint 8.2 / Sprint 8.3 closure, 2026-05-19 | Sprint 8.1 closed the LLVM/RTS tuning baseline. Sprint 8.2 ran three profile-driven rounds on 2026-05-16: round 1 IntSet (~6.2x speedup), round 2 strict-pair Word64 (regression, reverted), round 3 wavefront-bitmap BFS over `Bits128` (~52x legal-moves / ~33x uct-search vs round 1; combined ~320x / ~200x vs original baseline). |
| Deterministic placeholder transcript hash | Sprint 2.2 baseline closure | Replaced `pseudoSha256Hex` in `src/MCTS/Transcript.hs` with the pure SHA-256 implementation in `src/MCTS/Crypto/SHA256.hs`; `runConfigHash` and `playTranscriptHash` now emit SHA-256 hex digests. |
| No-op sidecar cache and divergence inspect placeholders | Sprint 2.7 / Sprint 7.5 baseline closure | Replaced fixed `inspect cache list`, `inspect cache prune`, and `inspect divergence` output with `MCTS.Transcript.EquitySidecar` cache discovery/pruning and `MCTS.Verify.Divergence` metric rendering. |
| Minimal four-field engine envelope | Sprint 2.6 closure | Replaced the `{version, backend, host_arch, build_id}` placeholder with the full v1 doctrine envelope: `rng_source`, `shared_rng_build_id`, `cohort_config_hash`, `engine_build_id`, `engine_git_commit`, `compiler_id`, `compiler_version`, `fp_flags`, `libm_id`, `cpu_features`, `fp_env`, plus the project-local `build_id` accessor field. |
| `Show`/`Read` equity sidecar codec | Sprint 2.7 closure | Replaced the `Show`/`Read` round-trip with the fixed-width binary `MEQ1` codec, atomic temp-file + rename writes, and `castWord64ToDouble` for IEEE-754 round-trips. |
| Synthetic `chooseMove` weight generator | Sprint 3.3 closure | Removed `MCTS.Engine.chooseMove` and `rawWeight`. The driver now dispatches every per-move search through `MCTS.Search.UCT.uctSearch` running over `MCTS.Search.Arena`. |
| `getSystemTime`-based bench timing | Sprint 3.5 closure | Replaced with the pinned monotonic clock `GHC.Clock.getMonotonicTimeNSec` exposed via `MCTS.CLI.Bench.monotonicNanos`. |
| Generated command-doc drift | Sprint 1.3 baseline closure | `renderCommandMarkdown` now emits governed-doc metadata and `MCTS.CLI.Docs` compares tracked generated files and marker-delimited regions through `mcts docs check`. |
| Comma-list report-card benchmark placeholder | Sprint 7.3 baseline closure | `parseBench` parses comma-separated `--backend` lists and `runBench` iterates every requested backend. |
| Legacy fixture output default | Sprint 8.8 closure, 2026-05-19 | `mcts build legacy-fixtures` requires `--output-dir`; generated evidence remains optional external/ignored audit data, not normal test input. |
| `tasty-golden` renderer/codec providers | Sprint 8.8 closure, 2026-05-19 | The `mcts-unit` stanza no longer depends on `tasty-golden`; command, report-card, inspect, error, subprocess, transcript, known-position, and TUI coverage now asserts typed/semantic contracts without checked-in snapshot files. |
| Two-backend backend parser and `VerifyBackend` constructors | Phase 8 restoration | `VerifyBackend` now covers `VCppImperative`, `VCppFunctional`, `VRust`, and `VHaskell`; parser tests validate the Q3 `(ii)..(v)` cohort and reject backend (i) at the default-verify boundary. |
| Missing C++ live dispatch and FFI drivers | Phase 8 restoration | `src/MCTS/FFI/CppLegacy.hs`, `src/MCTS/FFI/CppImperative.hs`, `src/MCTS/FFI/CppFunctional.hs`, and `MCTS.Driver.Dispatch` restore C++ dynamic search/envelope/recompute dispatch following the Rust pattern. |
| C++ backend build leaves not yet in full validation | Phase 8 restoration; Dockerfile migration updated 2026-05-22 | Phase 8 restored the build leaves to the full validation surface; the Dockerfile migration now invokes those leaves during image construction, and `mcts test all` checks the resulting artefacts before FFI-sensitive stanzas, Q3, Q6, and report-card measurement. |
| Missing Q6 live legacy-parity stanza | Phase 8 restoration | `mcts.cabal` declares `mcts-legacy-parity`, `test/legacy-parity` validates all five backend slots and incomplete-cohort rejection, and `mcts verify legacy-parity` pins the legacy envelope. |
| Stale two-backend wording | Phase 8 restoration | `README.md`, `DEVELOPMENT_PLAN/`, governed docs, generated command docs, and source comments now describe the five-backend first-class surface and the native-vs-C++ RNG split. |
| C++ backend retirement marker files | Phase 8 restoration | Deleted `cpp-legacy/RETIRED.md`, `cpp-imperative/RETIRED.md`, and `cpp-functional/RETIRED.md`; the backend-local READMEs now describe the live first-class roles of `(i)`, `(ii)`, and `(iii)`. |
| Static backend (ii) report-card anchor | Phase 8 restoration | Q1/Q2 report-card measurement uses `runBatchNoWriteDispatch` against live backend (ii) where the canonical shared library is present. |
| Internal parity-anchor naming cleanup | Phase 8 restoration | Internal command/test types now use `ParityAnchor*`, `baseline`, and `candidate`; the public `mcts test parity-anchor` command remains unchanged. |

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
