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

> **Purpose**: Record every surviving compatibility helper, deprecated path, doctrine
> deviation, and tooling residue still slated for deletion, plus the completed
> retirement history under the (i)→(ii)→(iii)→(v) protocol.

> **Authoritative Reference**:
> [development_plan_standards.md → I. Explicit Cleanup and Removal Ledger](development_plan_standards.md#i-explicit-cleanup-and-removal-ledger)

## Ledger Status

The repository now contains an active logical baseline. The rows below track
intentional stand-ins that keep the CLI, transcript, cache, and test surfaces runnable
while the real backend and parity work lands. These rows must move to `Completed` only
when the owning sprint replaces the stand-in with the target implementation and the
validation gate passes.

Two classes of entries populate this ledger over time:

1. **Doctrine-deviation residue.** Any worktree behavior that the implemented code
   does not yet honour against an in-scope doctrine section, scheduled through the
   owning sprint per standards rule L.
2. **Retirement protocol entries.** Each retiring backend's CLI flag value, build
   artefact, and shared library is moved to `Pending Removal` at the start of its
   retirement (Phase `8`) and to `Completed` when the surviving cohort's golden
   transcripts and throughput numbers freeze in `test/golden/<backend>/`. The
   retirement order is `cpp-legacy` (after Q6 closure), then `cpp-imperative` (after
   `cpp-functional` reaches parity), then `cpp-functional` (after `haskell` reaches
   parity). Backend (iv) Rust remains live throughout.

`MCTS_legacy` itself lives at `~/MCTS_legacy/` and is not in this repository; legacy
entries here track only shims and compatibility helpers introduced *inside* this
repository that are slated for removal. The `cpp-legacy/` sources are themselves a
verbatim re-port plus FFI shims, not a legacy artefact — they are a current supported
backend until Phase `8` retirement closes Q6.

## Pending Removal

| Item | Location | Reason | Owning Sprint |
|------|----------|--------|---------------|
| In-process backend dispatch stand-in | `src/MCTS/Driver.hs`, `src/MCTS/Verify.hs` | The CLI, transcript, cache, and verify surfaces dispatch every backend through the in-process Haskell engine (`MCTS.Search.UCT.uctSearch`) plus a per-backend RNG salt. Must be replaced by real foreign-backend FFI dispatch so each backend actually runs the C++ / Rust / verbatim-legacy code its identifier names | Sprint 4.4, Sprint 5.4, Sprint 6.2, Sprint 6.4 |
| Dynamic FFI smoke loader and chosen-move-only smoke drivers | `src/MCTS/FFI/Common.hs`, `src/MCTS/FFI/{CppLegacy,CppImperative,CppFunctional,Rust}.hs`, `src/MCTS/Driver/{CppLegacy,CppImperative,CppFunctional,Rust}.hs` | Keeps Cabal builds independent of local shared-library paths while bounded smoke games exercise real C ABI symbols. The final backend drivers need the full visit-vector/recompute ABI and the final linkage/load policy, not the chosen-action-only smoke path | Sprint 4.4, Sprint 5.4, Sprint 6.2, Sprint 6.4 |
| Foreign backend smoke skeletons | `cpp-imperative/`, `cpp-functional/`, `rust/` | Provides concrete source homes and smoke build targets; final contract requires optimized C++ engines, Rust engine, and Haskell FFI-backed game drivers | Sprint 5.1, Sprint 6.1, Sprint 6.3 |
| Zero-initialized foreign envelope slots | `cpp-legacy/c-abi/mcts_cpp_legacy.*`, `cpp-imperative/c-abi/mcts_cpp_imperative.*`, `cpp-functional/c-abi/mcts_cpp_functional.*`, `rust/src/envelope.rs` | Smoke accessors expose the final envelope struct shape but leave build-id, cohort hash, CPU-feature, FP-environment, and some compiler/libm fields unset until post-link patching and runtime probes exist | Sprint 4.7, Sprint 5.5, Sprint 6.5, Sprint 7.5 |
| Legacy warning suppression | `cpp-legacy/Makefile` | The verbatim imported legacy `board.cpp` triggers the container compiler's `-Wpessimizing-move` warning on a return statement. The Makefile carries `-Wno-pessimizing-move` so the port can stay line-level faithful and still build warning-clean. Remove only if the retirement protocol deletes backend (i) or an upstream-verbatim source change makes the suppression unnecessary | Sprint 8.4 |
| Logical report-card placeholders | `src/MCTS/ReportCard.hs` | Allows `mcts test all --dry-run` and renderer smoke tests; final report card must use measured Q1-Q7 evidence | Sprint 7.3, Sprint 8.3 |
| ~~Multi-game transcript file layout~~ | *(closed Sprint 7.5, 2026-05-16)* | Resolved: `writeTranscriptPerGame` in `src/MCTS/Transcript.hs` splits the batch into N one-game-per-file transcripts; each per-game file is written with `runGames = 1` and the splitmix-derived per-game seed so the per-game hashes differ from the batch hash. `MCTS.Driver.runBatchWithGame` populates the new `batchGameWrites :: [(String, FilePath)]` field; the bench renderer prints "wrote N per-game transcripts under …" when N > 1. `mcts-unit::exercisePerGameTranscriptWriter` covers the entry shape (one entry per game, distinct hashes, each file decodes as a single-game transcript) | — |
| `S_LP_SIMS = 1000` fixture sim count | `test/golden/legacy/transcripts/arm64/*.tr` | The committed Q6 fixtures were produced with `LEGACY_FIXTURE_SIMS=1000` so the regenerate step fits routine CI budgets. The spec value is `S_LP_SIMS = 10000`. The `legacy-to-wire` tool honours either via the `LEGACY_FIXTURE_SIMS` env var; the 10000-sim refresh is owed once the report-card cohort actually publishes | Sprint 7.3 |
| Backend (iii) engine re-uses the verbatim legacy core | `cpp-functional/engine/` | Phase 6 closed backend (iii)'s C ABI, recompute, envelope probes, and Haskell dispatcher on a real-engine basis, but the engine source is the byte-identical legacy core. The doctrine's "functional-style" character (immutable boards, value semantics, lazy seqs) is NOT yet realised. (Backend (ii)'s imperative-steelman character — arena allocator, flat children, `Word16` ply counter, `thread_local` move buffer, `__builtin_prefetch` — landed under Sprint 5.1 on 2026-05-16; only the `-fno-exceptions` engine TU and per-rollout scratch-board undo remain as backend-(ii) residue, captured in the new row below.) | Sprint 6.1 |
| Backend (ii) `-fno-exceptions` engine TU + per-rollout scratch-board undo | `cpp-imperative/engine/{board.cpp,search.cpp}` | Sprint 5.1 landed the arena-MCTS steelman character but the engine TU still compiles with exceptions enabled because `corridors::board::eval` / `get_terminal_eval` throw `std::string`; the rollout also copies the `corridors::board` each step (legacy default) rather than using per-rollout scratch-board undo. Either remove the throws under an `-fno-exceptions`-safe board variant or guard the offending paths; add a true scratch-board undo for the rollout's hottest copy. | Sprint 5.1 (residue), Sprint 5.3 |
| ~~PGO+BOLT pipeline~~ | *(closed Sprint 5.3, 2026-05-16)* | Resolved: `cppImperativePgoBoltPlan` in `src/MCTS/CLI/Build.hs` ships the 11-step PGO + BOLT-instrument + BOLT-optimize + install pipeline through the typed `Subprocess` boundary; `cpp-imperative/Makefile` carries the per-stage targets; BOLT runs without `perf` via `llvm-bolt -instrument`; `mcts-unit::exerciseCppImperativeBuildPlan` covers idempotence + failure-mode | — |
| Backend (iv) Rust Corridors gameplay port | `rust/src/board.rs`, `rust/src/rollout.rs` | Sprint 6.3 landed a real arena MCTS with UCT-1 in Rust (`rust/src/{tree.rs,search.rs,xoshiro256pp.rs}`) and the full `mcts_rust_search_move` / `mcts_rust_recompute_move` / `mcts_rust_read_visits` C ABI surface. What remains is the Corridors gameplay port from `cpp-legacy/legacy-core/board.cpp` — pawn movement + jump-over-opponent + wall placement + BFS escapability check — so the Rust engine emits Corridors-legal action IDs. Until that lands, the Haskell dispatcher keeps `--backend rust` on the in-process logical UCT for the operator-facing bench/verify path | Sprint 6.3, Sprint 6.4 |
| `brick`/`vty` interactive TUIs (compiler-pin blocker) | `src/MCTS/App.hs::runPlay` (non-interactive smoke), `src/MCTS/CLI/Inspect.hs::inspectReplay` (non-interactive summary), absent `src/MCTS/CLI/Tui/` | Sprint 7.4 specifies a full `brick`/`vty` TUI. Attempted to add `brick` and `vty` as `build-depends` of `mcts.cabal` under the pinned GHC 9.14.1: the cabal solver fails because every `brick`-eligible `config-ini` version conflicts with the installed `text 2.1.3` / `containers 0.8` / `base 4.22.0.0` triple that ships with GHC 9.14.1. Closure requires either a newer `brick` release with updated `config-ini` bounds or pinning a compatible `config-ini` flag set; both are upstream-dependent | Sprint 7.4 |
| Measured Q1–Q7 report-card evidence | `src/MCTS/ReportCard.hs`, `src/MCTS/CLI/Test.hs` | The renderer + Plan/Apply scaffolding are in place but the numbers shipped are logical placeholders rather than wall-clock measurements through the PGO+BOLT C++ steelman and the live Haskell tuning baseline. Closing this row depends on Sprints 5.3 (PGO+BOLT), 6.3/6.4 (Rust engine), and 8.1–8.3 (Haskell tuning) | Sprint 7.3, Sprint 8.3 |
| Foreign-engine recompute streaming to `.eq` sidecars | `src/MCTS/CLI/Inspect.hs::inspectDivergence`, `src/MCTS/Verify/Divergence.hs` | Sprint 4.7 / 5.5 expose `mcts_<backend>_recompute_move` from backends (i)–(iii); `mcts inspect divergence` and the divergence stanza still read sidecars from the in-process Haskell engine only. Wiring the foreign recompute streams into `MEQ1` sidecars closes the cross-backend equity comparison contract | Sprint 7.5 |
| Pure Haskell parity proof vs backend (ii) | `src/MCTS/Engine.hs`, `src/MCTS/Search/{Arena,UCT}.hs` | Sprint 8.1 closed: `-fllvm` lands under GHC 9.14.1's LLVM 19 backend; `SPECIALIZE` is a no-op for the current monomorphic kernel; the `MutableByteArray#` migration is profile-driven and enqueued under Sprint 8.2. Still remaining: the criterion micro-benchmark suite (`bench/criterion-suites.hs`), the profile-driven hot-path tuning iterations, the tree-persistent / bitboard board (only if profiling justifies), and the measured Q1+Q2 throughput ratio vs the C++ steelman within `HASKELL_PARITY_TOLERANCE = 0.05` | Sprint 8.2, Sprint 8.3 |
| Backend (ii) `-optlo-mcpu=native` / `-optlc-mcpu=native` on aarch64 | `mcts.cabal` (Haskell library + executable `ghc-options`) | Sprint 8.1 closure note: enabling per-CPU LLVM flags through `-fllvm` on aarch64 emits LSE (Large System Extensions) instructions the container's assembler refuses (`instruction requires: lse`). The flags are NOT in the current flag set; if a future profiling pass shows headroom, the assembler invocation needs a matching `-mcpu=…+lse` extension or a different LLVM target tuning configuration | Sprint 8.2 |

## Pending Removal Notes

Each pending-removal row resolves on the closure of the owning sprint listed in the
relevant phase document. Each row will move to `Completed` when the owning sprint closes
and the doctrine-required replacement is verified (or, for retirement entries, when the
surviving cohort's golden anchor freezes).

The expected populating events are:

- **Phase 1.** Any doctrine-adoption gap surfaced by Sprint `0.2`'s grep audit enqueues
  here under its owning Phase `1`–`8` sprint. The audit's job is to ensure no gap is
  silently adopted; the ledger is where unowned gaps would become visible.
- **Phase 4.** If backend (i)'s verbatim re-port introduces any code-level adjustment
  beyond FFI shims (an adjustment that goes beyond what the legacy itself contained), the
  adjustment enqueues here under Sprint `4.N` as residue to revert before retirement.
- **Phase 5/6.** If backend (ii)'s or (iii)'s tuning stack departs from the doctrine's
  named flags in either direction — extra flags or missing flags — the deviation
  enqueues here. The 16-item tuning checklist in
  [../documents/engineering/compiler_runtime_tuning.md](../documents/engineering/compiler_runtime_tuning.md)
  is the reference list against which the deviation is judged.
- **Phase 8.** The retirement protocol populates this section with one row per retiring
  backend at the start of its retirement, then moves the row to `Completed` once the
  surviving cohort's golden anchor freezes.

## Completed

| Item | Removed In | Notes |
|------|------------|-------|
| Deterministic placeholder transcript hash | Sprint 2.2 baseline closure | Replaced `pseudoSha256Hex` in `src/MCTS/Transcript.hs` with the pure SHA-256 implementation in `src/MCTS/Crypto/SHA256.hs`; `runConfigHash` and `playTranscriptHash` now emit SHA-256 hex digests. |
| No-op sidecar cache and divergence inspect placeholders | Sprint 2.7 / Sprint 7.5 baseline closure | Replaced fixed `inspect cache list`, `inspect cache prune`, and `inspect divergence` output with `MCTS.Transcript.EquitySidecar` cache discovery/pruning and `MCTS.Verify.Divergence` metric rendering. |
| Missing baseline envelope verification and legacy-parity workload dispatch | Sprint 7.5 baseline closure | Added `MCTS.Verify.Envelope`, `--allow-stale` parser/execution plumbing, `inspect show --envelope`, and fixed `verify legacy-parity rollouts` so the parsed workload reaches execution. |
| Minimal four-field engine envelope | Sprint 2.6 closure | Replaced the `{version, backend, host_arch, build_id}` placeholder with the full v1 doctrine envelope: `rng_source`, `shared_rng_build_id`, `cohort_config_hash`, `engine_build_id`, `engine_git_commit`, `compiler_id`, `compiler_version`, `fp_flags`, `libm_id`, `cpu_features`, `fp_env`, plus the project-local `build_id` accessor field. Wire format matches the C ABI `mcts_<backend>_envelope` struct byte-for-byte. |
| `Show`/`Read` equity sidecar codec | Sprint 2.7 closure | Replaced the `Show`/`Read` round-trip with the fixed-width binary `MEQ1` codec (4-byte magic + u16 version + length-prefixed strings + 15-byte fixed records + `0xFFFFFFFF` terminator), atomic temp-file + rename writes, and `castWord64ToDouble` for IEEE-754 round-trips. |
| Synthetic `chooseMove` weight generator | Sprint 3.3 closure | Removed `MCTS.Engine.chooseMove` and `rawWeight`. The driver now dispatches every per-move search through `MCTS.Search.UCT.uctSearch` running over `MCTS.Search.Arena`. Cross-backend visit-count equality holds under `--rng cpp`; per-backend salt under `--rng native` preserves bench distinguishability. |
| `getSystemTime`-based bench timing | Sprint 3.5 closure | Replaced with the pinned monotonic clock `GHC.Clock.getMonotonicTimeNSec` exposed via `MCTS.CLI.Bench.monotonicNanos`. The test-injectable variant `runBenchWithClock` allows the `mcts-unit` stanza to assert the bench bracket reads the clock exactly twice per backend. |
| Generated command-doc drift | Sprint 1.3 baseline closure | `renderCommandMarkdown` now emits the governed-doc metadata and the documented `inspect show --envelope` row; `MCTS.CLI.Docs` compares tracked generated files and marker-delimited regions through `mcts docs check`. |
| Comma-list report-card benchmark placeholder | Sprint 7.3 baseline closure | `parseBench` now parses comma-separated `--backend` lists and `runBench` iterates every requested backend, so the report-card workload no longer collapses to the first backend. |

## Retirement Protocol Reference

The retirement chain documented in [00-overview.md](00-overview.md) and owned by
[phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md):

| Order | Retiring Backend | Trigger | Surviving Cohort | Frozen Anchor |
|-------|------------------|---------|------------------|---------------|
| 1 | `cpp-legacy` (i) | Q6 closure: `cpp-legacy` reproduces `MCTS_legacy` byte-for-byte on benchmark (b) under the golden fixture set | `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | `test/golden/cpp-legacy/` |
| 2 | `cpp-imperative` (ii) | `cpp-functional` reaches parity with `cpp-imperative` on Q1 and Q2 | `cpp-functional`, `rust`, `haskell` | `test/golden/cpp-imperative/` |
| 3 | `cpp-functional` (iii) | `haskell` reaches parity with `cpp-functional` on Q1 and Q2 | `rust`, `haskell` | `test/golden/cpp-functional/` |
| — | `rust` (iv) | _(does not retire; kept as the long-running cross-language second opinion throughout)_ | — | — |
| — | `haskell` (v) | _(target; does not retire)_ | — | — |

Q7 and the `mcts-legacy-parity` test stanza retire alongside backend (i), since both
require a live (i) binary to participate in the 5-way round-robin. The transitive parity
chain `MCTS_legacy ≡ (i) ≡ (ii)..(v)` becomes a frozen historical fact recorded in
`test/golden/legacy/` rather than a continuously re-run check. Q3 and the
`mcts-cross-backend` stanza continue with whatever subset of (ii)–(v) is still live.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
