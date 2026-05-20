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
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Record every remaining compatibility helper, deprecated path, doctrine
> deviation, and stale tooling surface still slated for deletion or correction.

> **Authoritative Reference**:
> [development_plan_standards.md → I. Explicit Cleanup and Removal Ledger](development_plan_standards.md#i-explicit-cleanup-and-removal-ledger)

## Ledger Status

The intended repository end state is one Haskell CLI with five first-class backend
slots: `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`, and `haskell`.
The stale two-backend drift from the 2026-05-19 cleanup is corrected; remaining
ledger entries track only future compatibility residue discovered after the current
restoration.

The validation-data doctrine sweep remains closed: normal tests do not require
checked-in transcripts, throughput anchors, renderer snapshots, schema fixtures, or
other generated validation data. Evidence needed for audit is generated in memory,
under temporary directories, or under explicit operator-provided artifact roots.

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

| Item | Location | Reason | Owning Sprint |
|------|----------|--------|---------------|
| None. | n/a | No pending stale-surface cleanup remains after the five-backend restoration. | n/a |

## Pending Removal Notes

Each pending-removal row resolves on the closure of the owning sprint listed in the
relevant phase document. Each row moves to `Completed` only after the corrected
surface is implemented, governed docs are aligned, generated docs are regenerated or
checked, and the canonical validation command for that surface passes through
`docker compose run --rm mcts mcts <command>`.

## Completed

| Item | Removed In | Notes |
|------|------------|-------|
| Multi-game transcript file layout | Sprint 7.5, 2026-05-16 | `writeTranscriptPerGame` in `src/MCTS/Transcript.hs` splits batches into one-game-per-file transcripts with per-game splitmix seeds; `MCTS.Driver.runBatchWithGame` reports the resulting hash/path pairs, and `mcts-unit::exercisePerGameTranscriptWriter` covers the behavior. |
| PGO+BOLT pipeline | Sprint 5.3, updated Sprint 6.4, 2026-05-18 | The shared C++ `pgoBoltPlan` in `src/MCTS/CLI/Build.hs` shipped the typed 19-step PGO+BOLT pipeline for the C++ steelman backends, including canonical FFI training installs and explicit PGO fallback when BOLT data is unavailable. |
| Backend (iv) Rust Corridors gameplay port | Sprint 6.3, 2026-05-16; updated Sprint 7.2, 2026-05-18 | `rust/src/board.rs`, `rust/src/rollout.rs`, and `rust/src/search.rs` carry the real Corridors game state, rollout loop, and arena MCTS, and `MCTS.Driver.Dispatch.runBatchDispatch` routes `--backend rust` through the real FFI engine when the cdylib is present. |
| Foreign-engine recompute streaming to `.eq` sidecars | Sprint 7.5, 2026-05-16 | `MCTS.Engine.ForeignRecompute.foreignRecomputeEqStream` drives backend recompute ABIs through transcripts, `MCTS.Verify.Divergence.divergenceVsEqStream` scores the resulting `EqStream`, and `mcts inspect divergence` renders cached and available foreign recompute rows. |
| Measured Q1-Q7 report-card evidence | Sprint 7.3 / Sprint 8.3 evidence closure, updated 2026-05-19 | `docker compose run --rm mcts mcts test all` passed against the canonical workload and recorded Q1 ST 0.05x, Q1 MT8 0.41x, Q2 ST 0.05x, Q2 MT8 0.20x, Q5 Haskell 0.99x, Q5 cpp-imperative 3.64x, zero live-cohort divergence, Q7 liveness evidence PASS, and verdict `Within tolerance`. |
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
| C++ backend build leaves not yet in full validation | Phase 8 restoration | `mcts test all` now builds `cpp-legacy`, `cpp-imperative`, `cpp-functional`, and `rust` before FFI-sensitive stanzas, Q3, Q7, and report-card measurement. |
| Missing Q7 live legacy-parity stanza | Phase 8 restoration | `mcts.cabal` declares `mcts-legacy-parity`, `test/legacy-parity` validates all five backend slots and incomplete-cohort rejection, and `mcts verify legacy-parity` pins the legacy envelope. |
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
