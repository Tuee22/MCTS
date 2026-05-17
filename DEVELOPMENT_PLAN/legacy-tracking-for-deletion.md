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
| Dynamic FFI smoke loader and chosen-move-only smoke drivers | `src/MCTS/FFI/Common.hs`, `src/MCTS/FFI/{CppLegacy,CppImperative,CppFunctional,Rust}.hs`, `src/MCTS/Driver/{CppLegacy,CppImperative,CppFunctional,Rust}.hs` | Keeps Cabal builds independent of local shared-library paths while bounded smoke games exercise real C ABI symbols. The final backend drivers need the full visit-vector/recompute ABI and the final linkage/load policy, not the chosen-action-only smoke path | Sprint 4.4, Sprint 5.4, Sprint 6.2, Sprint 6.4 |
| Foreign backend smoke skeletons | `cpp-imperative/`, `cpp-functional/`, `rust/` | Provides concrete source homes and smoke build targets; final contract requires optimized C++ engines, Rust engine, and Haskell FFI-backed game drivers | Sprint 5.1, Sprint 6.1, Sprint 6.3 |
| Legacy warning suppression | `cpp-legacy/Makefile` | The verbatim imported legacy `board.cpp` triggers the container compiler's `-Wpessimizing-move` warning on a return statement. The Makefile carries `-Wno-pessimizing-move` so the port can stay line-level faithful and still build warning-clean. Remove only if the retirement protocol deletes backend (i) or an upstream-verbatim source change makes the suppression unnecessary | Sprint 8.4 |
| Logical report-card placeholders | `src/MCTS/ReportCard.hs` | Allows `mcts test all --dry-run` and renderer smoke tests; final report card must use measured Q1-Q7 evidence | Sprint 7.3, Sprint 8.3 |
| ~~Multi-game transcript file layout~~ | *(closed Sprint 7.5, 2026-05-16)* | Resolved: `writeTranscriptPerGame` in `src/MCTS/Transcript.hs` splits the batch into N one-game-per-file transcripts; each per-game file is written with `runGames = 1` and the splitmix-derived per-game seed so the per-game hashes differ from the batch hash. `MCTS.Driver.runBatchWithGame` populates the new `batchGameWrites :: [(String, FilePath)]` field; the bench renderer prints "wrote N per-game transcripts under …" when N > 1. `mcts-unit::exercisePerGameTranscriptWriter` covers the entry shape (one entry per game, distinct hashes, each file decodes as a single-game transcript) | — |
| `S_LP_SIMS = 1000` fixture sim count | `test/golden/legacy/transcripts/arm64/*.tr` | The committed Q6 fixtures are a `1000`-simulation transitional snapshot so routine checks stay bounded. The spec value is `S_LP_SIMS = 10000`. The 10000-sim refresh is owed once the report-card cohort actually publishes, and the regeneration path must be exposed through a `mcts` CLI entrypoint with explicit flags rather than environment-variable or direct-tool execution | Sprint 7.3 |
| ~~PGO+BOLT pipeline~~ | *(closed Sprint 5.3, 2026-05-16)* | Resolved: `cppImperativePgoBoltPlan` in `src/MCTS/CLI/Build.hs` ships the 11-step PGO + BOLT-instrument + BOLT-optimize + install pipeline through the typed `Subprocess` boundary; `cpp-imperative/Makefile` carries the per-stage targets; BOLT runs without `perf` via `llvm-bolt -instrument`; `mcts-unit::exerciseCppImperativeBuildPlan` covers idempotence + failure-mode | — |
| ~~Backend (iv) Rust Corridors gameplay port~~ | *(closed Sprint 6.3, 2026-05-16)* | Resolved: `rust/src/board.rs` carries the full Corridors game state — 8x8 bitfield wall maps (`walls_h`, `walls_v`), `u8` hero/villain pawn coordinates, `u8` wall-remaining counters, `u16` ply counter, post-move 180-degree flip with `u64::reverse_bits` — plus iterative BFS escapability via a 128-bit visited bitmap. `rust/src/rollout.rs` plays a uniform-random rollout through real legal Corridors moves; `rust/src/search.rs` carries the arena MCTS using `Tree<MctsRustBoard>` with per-node board state. `mcts_rust_search_move` emits action ids flipped to the post-move (next-player) perspective to match the legacy C ABI convention; the Haskell-side `applyFlip` in `MCTS.Driver.ForeignSearch` recovers absolute coordinates. `MCTS.Driver.Dispatch.runBatchDispatch` now routes `--backend rust` through `runForeignSearchGame withRustSearchGame` when `rust/target/release/libmcts_rust.so` is present. `docker compose run --rm mcts mcts test all` and `docker compose run --rm mcts mcts check-code` stay green; cross-backend smoke continues to accept a well-formed `VerifyMismatch` outcome (the cohort agreement contract is owned by Sprint 7.2's final tightening) | — |
| Measured Q1–Q7 report-card evidence (Q1+Q2 ST snapshots, 2026-05-16) | `src/MCTS/ReportCard.hs`, `src/MCTS/CLI/Test.hs`, `documents/engineering/compiler_runtime_tuning.md` | The renderer + Plan/Apply scaffolding are in place; after Sprint 8.2 round 3, the Q1 ST snapshot (100 games, non-PGO smoke) lands at **0.89×** (Haskell faster than cpp-imperative smoke), and the Q2 ST scaling snapshot (4 games, --rng cpp, varying sims) measures sims=100 1.17×, sims=500 1.03× (within tolerance), sims=1000 1.13× (in PGO band). Closing this row fully requires the multi-minute report-card workload (`G_R=100_000`, `G_S=1_000`, MT8 variants, `S_BENCH=10_000`) populating the report-card renderer with measured numbers and the verdict against the PGO+BOLT-tuned cdylibs | Sprint 7.3, Sprint 8.3 |
| ~~Foreign-engine recompute streaming to `.eq` sidecars~~ | *(closed Sprint 7.5, 2026-05-16)* | Resolved: real `chosen_equity` output from `mcts_imperative_recompute_move`, `mcts_functional_recompute_move`, and `mcts_rust_recompute_move` (parent-perspective equity from the search tree's chosen child). `MCTS.Engine.ForeignRecompute.foreignRecomputeEqStream` drives any per-backend recompute opener through a transcript to emit a fresh `EqStream`. `MCTS.Verify.Divergence.divergenceVsEqStream` scores a transcript against an EqStream with real `equity_l2_drift`. `mcts inspect divergence` emits one sidecar row per cached `.eq` plus one foreign row per available cdylib labeled `<origin>/foreign:<backend>` through `MCTS.Engine.ForeignRecompute`. Integration coverage: `mcts-integration::foreign recompute EqStream` exercises all three foreign backends end-to-end |
| Pure Haskell parity proof vs backend (ii) | `src/MCTS/Engine.hs`, `src/MCTS/Search/{Arena,UCT}.hs` | Sprint 8.1 closed. Sprint 8.2 ran three profile-driven rounds on 2026-05-16: round 1 IntSet (~6.2× speedup), round 2 strict-pair Word64 (regression, reverted), round 3 wavefront-bitmap BFS over `Bits128` (~52× legal-moves / ~33× uct-search vs round 1; **combined ~320× / ~200× vs original baseline**). Updated Q1 ST snapshot (100 games, non-PGO smoke libraries): Haskell-vs-cpp-imperative = **0.89×** (Haskell faster than the non-PGO smoke). Still remaining: the `MutableByteArray#` arena migration if profiling justifies, and the full measured Q1+Q2 matrix vs the PGO+BOLT-tuned C++ steelman within `HASKELL_PARITY_TOLERANCE = 0.05` | Sprint 8.2, Sprint 8.3 |
| Backend (ii) `-optlo-mcpu=native` / `-optlc-mcpu=native` on aarch64 | `mcts.cabal` (Haskell library + executable `ghc-options`) | Sprint 8.1 closure note: enabling per-CPU LLVM flags through `-fllvm` on aarch64 emits LSE (Large System Extensions) instructions the container's assembler refuses (`instruction requires: lse`). The flags are NOT in the current flag set; if a future profiling pass shows headroom, the assembler invocation needs a matching `-mcpu=…+lse` extension or a different LLVM target tuning configuration | Sprint 8.2 |
| LLVM-BOLT post-link on aarch64 (2026-05-16) | `src/MCTS/CLI/Build.hs::rustPgoBoltPlan` (steps 5-7), `cpp-imperative/Makefile`, `cpp-functional/Makefile` (pgoBoltPlan steps) | Sprint 6.4 closure note: `llvm-bolt-19` in the pinned container errors with `BOLT-WARNING: non-relocation mode for AArch64 is not fully supported` followed by `BOLT-ERROR: instrumentation runtime libraries require relocations` on `cargo build --release` cdylibs (even with `--allow-stripped`). The plan's `\|\| cp` fallback degrades the BOLT pass to a no-op so the install path still publishes a PGO-optimized cdylib, but the full PGO+BOLT target is achievable on amd64 only. The Sprint 8.3 parity verdict against the PGO+BOLT cdylib therefore needs an amd64 run, OR the doctrine should record that the aarch64 parity bar is PGO-only | Sprint 6.4, Sprint 8.3 |
| Cohort tree-shape gap across `(ii)..(v)` | `cpp-imperative/engine/board.h::get_legal_moves`, `cpp-functional/engine/board.h::get_legal_moves`, `rust/src/board.rs::legal_actions`, `src/MCTS/Engine.hs::legalMoves` (line 59 `take 12 (wallMoves board)`) | Sprint 7.2 closure note, 2026-05-17: with the Haskell heuristic tiebreak dropped, the selection-policy axis of cohort agreement is uniform across (ii)..(v). The remaining `VerifyMismatch` surface on multi-move `verify rollouts` runs traces to two structural differences: (a) `cpp-imperative` / `cpp-functional` emit a child for every legal wall slot (up to 128) while Rust and Haskell cap walls at 12 via `take 12 (wallMoves board)` / `if count >= 12 { break; }`, and (b) the post-move 180-degree flip orientation conventions are not byte-identical across the four engines — so the side-to-move board state diverges after a few plies even when each engine's selection policy is correct in isolation. Closing this gap requires either (a) unifying the wall enumeration cap across all four engines or (b) making `MCTS.Verify.comparable` quotient by tree shape (already partly done: visit-list sort + zero-visit filter). The `mcts-cross-backend` stanza accepts `VerifyMismatch` today; flipping to assert-equality is gated on this gap | Sprint 7.2 |

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
| `brick`/`vty` interactive TUI event loops | Sprint 7.4 closure, 2026-05-16 | `cabal.project` `allow-newer: config-ini:containers, config-ini:base` unblocked `brick-2.12` + `vty-6.5`. `MCTS.CLI.Tui.{Board,Play,Replay}` render the 9×9 board, the interactive `mcts play` event loop (legacy notation + `:hint`/`:undo`/`:save`/`:quit`/`:q`), and the replay navigator (forward/back/home/end + multi-backend equity overlay column populated from cached `.eq` sidecars + a bounded board-snapshot cache driven by the `--cache-states N` flag). `MCTS.App.runPlay` and `MCTS.CLI.Inspect.inspectReplay` dispatch to the brick TUIs on TTY; pure dispatchers covered by `mcts-unit::exerciseTuiPlayInput`, `mcts-unit::exerciseTuiReplayNav`, `mcts-unit::exerciseTuiReplayOverlay`. |
| Zero-initialized foreign envelope slots | Sprint 6.5 closure, 2026-05-17 | All four foreign backends populate the full envelope: cpp-legacy/cpp-imperative/cpp-functional run `probe_cpu_features` + `probe_fp_env` + `fill_libm_id` (glibc/musl/libsystem from `__GLIBC__`/`__MUSL__`/`__APPLE__`) + objcopy `.envelope_build_id` post-link patch via the `envelope-build-id` Makefile target. Rust's `OnceLock`-backed `build_envelope` runs `is_aarch64_feature_detected!` / `is_x86_feature_detected!`, derives `libm_id` from `target_env`, and ships a `#[link_section = ".envelope_build_id"]` 32-byte slot that `rustPgoBoltPlan` step 9 patches via `sha256sum` + `python3 -c binascii.unhexlify` + `objcopy --update-section`. `mcts-integration::foreign ffi live envelopes` asserts each backend's `libm_id` is in the known string set. |
| In-process backend dispatch stand-in | Sprint 7.2 closure, 2026-05-17 | `MCTS.Driver.Dispatch.runBatchDispatch` routes every foreign backend (i)/(ii)/(iii)/(iv) through `runForeignSearchGame` over the real FFI engines when the matching cdylib is present; the Haskell-side `Driver.runBatch` remains as the (v) baseline and the no-cdylib fallback. The shared `MCTS.Rng.Mix.backendNativeSalt` helper derives the per-backend `--rng native` salt from `backendId`, applied uniformly in `Driver.uctChooseMove`, `Engine.Recompute.recomputeGame`, and `Engine.ForeignRecompute.recomputeGameMoves`; covered by `mcts-unit::exerciseBackendNativeSalt`. |
| Backend (ii)/(iii) per-rollout scratch-board undo residue | Sprint 5.3 closure, 2026-05-17 | The existing rollout in `cpp-imperative/engine/search.cpp` and `cpp-functional/engine/search.cpp` already implements the scratch-board character for forward-only walks: a single `State current = node.state` snapshot mutated forward via per-ply move-assigns from a `thread_local std::vector<corridors::board> tls_move_buffer`. Across the rollout this is O(1) heap allocations and zero descents-needing-undo (the loop walks forward only). The "undo" formulation in the original doctrine bullet applies to descent-and-backtrack search-tree code, not to forward-only rollouts — for rollouts the scratch-board character degenerates to "single mutable snapshot + move-assign per ply", which is what the implementation does. Code comments in both `search.cpp` files document the rationale; the per-ply ~120-byte move-assign of `corridors::board` is dominated by the BFS cost in `check_local_escapable`, which is a separate (and not-yet-scheduled) wavefront-bitmap port. |
| Backend (iii) functional-style engine internals | Sprint 6.1 closure, 2026-05-17 | `cpp-functional/engine/search.cpp::run_search` descent loop now uses a `DescentStep` state-machine pattern: a `descent_step` lambda computes `std::variant<StepDescend, StepExpand, StepLeaf>` from the current node, and the outer loop dispatches via `std::visit`. Combined with the previously-shipped `SelectOutcome` variant + `try_advance` `std::optional<State>`, the data-flow style now differs from backend (ii)'s fall-through `while (true)` at both the API and the descent levels. Arena memory layout stays byte-comparable so the (ii)-vs-(iii) comparison isolates style as the variable. Per-move output is byte-identical to (ii) under `--rng cpp` (verified via `mcts bench rollouts`). |
| Haskell `nonTerminalRank` heuristic tiebreak in `pickByUctIndex` / `finalChoiceKey` | Sprint 7.2 cohort-agreement closure, 2026-05-17 | `src/MCTS/Search/UCT.hs::pickByUctIndex` no longer tiebreaks unvisited children by `nonTerminalRank (applyMove action board)`; the tiebreaker is now `(negate score, actionByte)` matching the C++/Rust first-unvisited-child policy. `finalChoiceKey` similarly drops the heuristic + equity components, leaving `(negate visits, actionId)` — the same surface as `cpp-imperative/engine/search.cpp::run_search`'s `if (child.visit_count > best_visits) { ... }`. `MCTS.Verify.comparable` now sorts the visit list by `action_id` and filters zero-visit entries so per-backend child-enumeration shape (cpp-imperative emitting every legal wall slot vs. Rust / Haskell `take 12`) is no longer in the comparison surface. The `nonTerminalRank` function stays exported for standalone test coverage at `test/unit/Main.hs`. The four-backend `(ii)..(v)` `verify rollouts` cohort no longer disagrees on the heuristic axis; the residual `VerifyMismatch` surface on multi-move runs traces to the cohort tree-shape gap (wall-cap divergence, post-move flip orientation conventions) tracked separately. `docker compose run --rm mcts mcts test all` + `docker compose run --rm mcts mcts check-code` green. |

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
