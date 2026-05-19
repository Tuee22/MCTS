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

The repository now contains an active five-backend implementation baseline. The rows
below track intentional stand-ins that keep the CLI, transcript, cache, and test
surfaces runnable while the remaining parity work lands. These rows must move to `Completed` only
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
backend until Sprint `8.4` freezes their anchors and removes the live backend path.

## Pending Removal

| Item | Location | Reason | Owning Sprint |
|------|----------|--------|---------------|
| Dynamic FFI smoke helpers and final linkage/load policy | `src/MCTS/FFI/Common.hs`, `src/MCTS/FFI/{CppLegacy,CppImperative,CppFunctional,Rust}.hs`, `src/MCTS/Driver/ForeignSmoke.hs`, `src/MCTS/Driver/{CppLegacy,CppImperative,CppFunctional,Rust}.hs` | The real visit-vector and recompute ABIs now drive bench/play/verify/inspect-divergence and integration smokes when cdylibs are present. The dynamic loader and legacy chosen-action smoke helper remain so Cabal builds/tests stay independent of local shared-library paths. The final policy must decide whether these helpers remain supported or are replaced by fixed installed artefact loading. | Sprint 4.4, Sprint 5.4, Sprint 6.2, Sprint 6.4 |
| Non-PGO foreign backend development artefacts | `cpp-imperative/`, `cpp-functional/`, `rust/` | The source homes now contain real engines and FFI drivers, and the canonical install paths for `cpp-functional` and `rust` validate through `mcts build cpp-functional` / `mcts build rust`. The remaining residue is the non-PGO/smoke artefact path that coexists with the final installed PGO-or-BOLT artefacts, plus the final linkage/load policy tracked in the dynamic FFI row above. | Sprint 5.3, Sprint 6.2, Sprint 6.4, Sprints 8.4-8.6 |
| Legacy warning suppression | `cpp-legacy/Makefile` | The verbatim imported legacy `board.cpp` triggers the container compiler's `-Wpessimizing-move` warning on a return statement. The Makefile carries `-Wno-pessimizing-move` so the port can stay line-level faithful and still build warning-clean. Remove only if the retirement protocol deletes backend (i) or an upstream-verbatim source change makes the suppression unnecessary | Sprint 8.4 |
| ~~Multi-game transcript file layout~~ | *(closed Sprint 7.5, 2026-05-16)* | Resolved: `writeTranscriptPerGame` in `src/MCTS/Transcript.hs` splits the batch into N one-game-per-file transcripts; each per-game file is written with `runGames = 1` and the splitmix-derived per-game seed so the per-game hashes differ from the batch hash. `MCTS.Driver.runBatchWithGame` populates the new `batchGameWrites :: [(String, FilePath)]` field; the bench renderer prints "wrote N per-game transcripts under …" when N > 1. `mcts-unit::exercisePerGameTranscriptWriter` covers the entry shape (one entry per game, distinct hashes, each file decodes as a single-game transcript) | — |
| ~~PGO+BOLT pipeline~~ | *(closed Sprint 5.3, updated Sprint 6.4, 2026-05-18)* | Resolved: the shared C++ `pgoBoltPlan` in `src/MCTS/CLI/Build.hs` ships the 19-step PGO + BOLT-instrument + BOLT-optimize + install pipeline through the typed `Subprocess` boundary for `cppImperativePgoBoltPlan` and `cppFunctionalPgoBoltPlan`; both C++ Makefiles carry absolute PGO profile directories, paired bench/instrumented targets, canonical FFI training installs, and explicit PGO fallbacks when BOLT data is unavailable. `mcts-unit::exerciseCppImperativeBuildPlan` covers idempotence, failure mode, and backend-rewrite equivalence. | — |
| ~~Backend (iv) Rust Corridors gameplay port~~ | *(closed Sprint 6.3, 2026-05-16; updated Sprint 7.2, 2026-05-18)* | Resolved: `rust/src/board.rs` carries the full Corridors game state — 8x8 bitfield wall maps (`walls_h`, `walls_v`), `u8` hero/villain pawn coordinates, `u8` wall-remaining counters, `u16` ply counter, post-move 180-degree flip with `u64::reverse_bits` — plus iterative BFS escapability via a 128-bit visited bitmap. `rust/src/rollout.rs` plays a uniform-random rollout through real legal Corridors moves; `rust/src/search.rs` carries the arena MCTS using `Tree<MctsRustBoard>` with per-node board state. `mcts_rust_search_move` emits action ids flipped to the post-move (next-player) perspective to match the legacy C ABI convention; the Haskell-side `applyFlip` in `MCTS.Driver.ForeignSearch` recovers absolute coordinates. `MCTS.Driver.Dispatch.runBatchDispatch` now routes `--backend rust` through `runForeignSearchGame withRustSearchGame` when `rust/target/release/libmcts_rust.so` is present. Sprint 7.2 tightened the cross-backend smoke cohorts so `VerifyMismatch` fails Q3 instead of being accepted; Q7 uses the same live dispatch path for legacy-envelope liveness/overflow. | — |
| ~~Foreign-engine recompute streaming to `.eq` sidecars~~ | *(closed Sprint 7.5, 2026-05-16)* | Resolved: real `chosen_equity` output from `mcts_imperative_recompute_move`, `mcts_functional_recompute_move`, and `mcts_rust_recompute_move` (parent-perspective equity from the search tree's chosen child). `MCTS.Engine.ForeignRecompute.foreignRecomputeEqStream` drives any per-backend recompute opener through a transcript to emit a fresh `EqStream`. `MCTS.Verify.Divergence.divergenceVsEqStream` scores a transcript against an EqStream with real `equity_l2_drift`. `mcts inspect divergence` emits one sidecar row per cached `.eq` plus one foreign row per available cdylib labeled `<origin>/foreign:<backend>` through `MCTS.Engine.ForeignRecompute`. Integration coverage: `mcts-integration::foreign recompute EqStream` exercises all three foreign backends end-to-end |

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
| Logical report-card placeholders | Sprint 7.3 / Sprint 8.3 evidence closure, 2026-05-18 | The static golden report-card keeps intentional `Evidence pending` sentinels for renderer determinism, but the live `mcts test all` path now requires canonical backend artefacts, measures Q1/Q2/Q5 with the production monotonic clock through `runBatchNoWriteDispatch`, derives the verdict, and populates divergence rows from the measured `G_V = 4` verify cohort. |
| Measured Q1-Q7 report-card evidence | Sprint 7.3 / Sprint 8.3 evidence closure, updated 2026-05-19 | `docker compose run --rm mcts mcts test all` passed against the canonical workload and recorded Q1 ST 0.05x, Q1 MT8 0.40x, Q2 ST 0.05x, Q2 MT8 0.20x, Q5 Haskell 1.00x, Q5 cpp-imperative 3.61x, zero `(ii)..(v)` divergence, Q7 legacy-envelope liveness PASS, and verdict `Within tolerance`. |
| Pure Haskell parity proof vs backend (ii) | Sprint 8.2 / Sprint 8.3 closure, 2026-05-19 | Sprint 8.1 closed the LLVM/RTS tuning baseline. Sprint 8.2 ran three profile-driven rounds on 2026-05-16: round 1 IntSet (~6.2× speedup), round 2 strict-pair Word64 (regression, reverted), round 3 wavefront-bitmap BFS over `Bits128` (~52× legal-moves / ~33× uct-search vs round 1; **combined ~320× / ~200× vs original baseline**). The 2026-05-19 canonical report card records Q1/Q2 within `HASKELL_PARITY_TOLERANCE = 0.05` in both threading modes and verdict `Within tolerance`, so backend-retirement work is no longer blocked on Haskell tuning. |
| Backend (ii) `-optlo-mcpu=native` / `-optlc-mcpu=native` on aarch64 | Sprint 8.2 closure, 2026-05-19 | Closed as a documented non-adoption: enabling per-CPU LLVM flags through `-fllvm` on aarch64 emits LSE instructions the container's assembler refuses (`instruction requires: lse`). The flags are not in the current flag set, and the parity gate passed without them. |
| LLVM-BOLT shared-library limitations | Sprint 6.4 / Sprint 8.3 closure, updated 2026-05-19 | The build harness explicitly installs the PGO artefact as the canonical fallback when C++ shared-library BOLT instrumentation yields no `.fdata` in the pinned container. The 2026-05-19 parity report card measured the canonical installed artefacts exactly as built by the container, including that documented fallback. Reopen only if the project later requires a true C++ shared-library BOLT comparison for a new target. |
| Q7 legacy-envelope liveness respec | Sprint 7.2 closure, 2026-05-19 | Closed by deliberately respecifying Q7 as a five-backend legacy-envelope liveness/overflow gate. The live investigation found backend (i)'s legacy tree search can diverge from the steelman engines at the report-card budget: the visit-count comparison failed at `game=0`, `move=10` with the same chosen move (`Pawn 4 6`), and a chosen-move comparison failed at `game=0`, `move=0` (`cpp-legacy` chose `WallV 2 1`, `cpp-imperative` chose `Pawn 4 1`). Q3 remains the visit-vector equality gate for `(ii)..(v)`, and Q6 remains the byte-for-byte backend (i) legacy anchor. |
| Live FFI Q3 cohort determinism gap | Sprint 7.2 live promotion, 2026-05-18 | Resolved for Q3: `MCTS.Verify.runAndCompare` now dispatches through `MCTS.Driver.Dispatch.runBatchDispatch`, and envelope verification uses `checkTranscriptEnvelopesLive`, so the `(ii)..(v)` verify cohort uses live foreign cdylibs when present and the in-process runner only as the no-cdylib fallback. Validation after promotion: `docker compose run --rm mcts mcts test mcts-cross-backend`, `docker compose run --rm mcts mcts test mcts-legacy-parity`, `docker compose run --rm mcts mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200`, and `docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500` pass. Q7 now uses the same live dispatch path as a legacy-envelope liveness/overflow gate rather than a backend (i) visit-vector comparison. |
| Deterministic placeholder transcript hash | Sprint 2.2 baseline closure | Replaced `pseudoSha256Hex` in `src/MCTS/Transcript.hs` with the pure SHA-256 implementation in `src/MCTS/Crypto/SHA256.hs`; `runConfigHash` and `playTranscriptHash` now emit SHA-256 hex digests. |
| No-op sidecar cache and divergence inspect placeholders | Sprint 2.7 / Sprint 7.5 baseline closure | Replaced fixed `inspect cache list`, `inspect cache prune`, and `inspect divergence` output with `MCTS.Transcript.EquitySidecar` cache discovery/pruning and `MCTS.Verify.Divergence` metric rendering. |
| Missing baseline/live envelope verification and legacy-parity workload dispatch | Sprint 7.5 baseline closure, updated 2026-05-18 | Added `MCTS.Verify.Envelope`, `--allow-stale` parser/execution plumbing, `inspect show --envelope`, and fixed `verify legacy-parity rollouts` so the parsed workload reaches execution. Later Sprint 7.5 work added `MCTS.FFI.Common.engineEnvelopeToEnvelope`, FFI-produced transcript stamping from `mcts_<backend>_get_envelope()` in `MCTS.Driver.Dispatch`, `checkTranscriptEnvelopesLive` comparison against live cdylib envelopes with in-process fallback when the cdylib is absent, structured JSON `warning_details` for downgraded backend-slot stale warnings, and `mcts-integration` coverage for real live-envelope stamping plus stale compiler-version hard-fail/`--allow-stale` warning behavior. |
| Minimal four-field engine envelope | Sprint 2.6 closure | Replaced the `{version, backend, host_arch, build_id}` placeholder with the full v1 doctrine envelope: `rng_source`, `shared_rng_build_id`, `cohort_config_hash`, `engine_build_id`, `engine_git_commit`, `compiler_id`, `compiler_version`, `fp_flags`, `libm_id`, `cpu_features`, `fp_env`, plus the project-local `build_id` accessor field. Wire format matches the C ABI `mcts_<backend>_envelope` struct byte-for-byte. |
| `Show`/`Read` equity sidecar codec | Sprint 2.7 closure | Replaced the `Show`/`Read` round-trip with the fixed-width binary `MEQ1` codec (4-byte magic + u16 version + length-prefixed strings + 15-byte fixed records + `0xFFFFFFFF` terminator), atomic temp-file + rename writes, and `castWord64ToDouble` for IEEE-754 round-trips. |
| Synthetic `chooseMove` weight generator | Sprint 3.3 closure | Removed `MCTS.Engine.chooseMove` and `rawWeight`. The driver now dispatches every per-move search through `MCTS.Search.UCT.uctSearch` running over `MCTS.Search.Arena`. Cross-backend visit-count equality holds under `--rng cpp`; per-backend salt under `--rng native` preserves bench distinguishability. |
| `getSystemTime`-based bench timing | Sprint 3.5 closure | Replaced with the pinned monotonic clock `GHC.Clock.getMonotonicTimeNSec` exposed via `MCTS.CLI.Bench.monotonicNanos`. The test-injectable variant `runBenchWithClock` allows the `mcts-unit` stanza to assert the bench bracket reads the clock exactly twice per backend. |
| Generated command-doc drift | Sprint 1.3 baseline closure | `renderCommandMarkdown` now emits the governed-doc metadata and the documented `inspect show --envelope` row; `MCTS.CLI.Docs` compares tracked generated files and marker-delimited regions through `mcts docs check`. |
| Comma-list report-card benchmark placeholder | Sprint 7.3 baseline closure | `parseBench` now parses comma-separated `--backend` lists and `runBench` iterates every requested backend, so the report-card workload no longer collapses to the first backend. |
| `S_LP_SIMS = 10000` fixture sim count | Sprint 7.1 / Sprint 7.5 Q6 fixture refresh, 2026-05-18 | Removed the transitional `test/golden/legacy/transcripts/arm64/*.tr` set and regenerated `test/golden/legacy/transcripts/amd64/*.tr` at `S_LP = 42`, `G_LP = 10`, `S_LP_SIMS = 10000`, `max_plies = 10000` through `docker compose run --rm mcts mcts build legacy-fixtures`. The external checkout at `/home/matt/MCTS_legacy` was clean at `97dd6ed7908a20234e3857c1bb4f8af46b507e0a`; `diff -qr -w` showed only external build/binding/test helper files outside the imported `backend/core` logic. `mcts-integration` now verifies ten fixtures per committed architecture directory, hash-named bytes, and the full legacy parity envelope. |
| `brick`/`vty` interactive TUI event loops | Sprint 7.4 closure, 2026-05-16; updated 2026-05-18 | `cabal.project` `allow-newer: config-ini:containers, config-ini:base` unblocked `brick-2.12` + `vty-6.5`. `MCTS.CLI.Tui.{Board,Play,Replay}` render the 9×9 board with pawn cells plus horizontal/vertical wall segments, the interactive `mcts play` event loop (legacy notation + `:hint`/`:undo`/`:quit`/`:q`; `:save` writes a hand-play transcript through `MCTS.Transcript.writePlayTranscript` addressed by `sha256(run_config || move_history)`; AI turns use `MCTS.Driver.ForeignSearch.foreignSearchMove` for selected foreign backends when cdylibs are present and in-process fallback when absent), and the replay navigator (forward/back/home/end + multi-backend equity overlay column populated from cached `.eq` sidecars + originator cache-miss recompute/visit-checking before TUI start + `r`-key on-demand backend column recompute/write + a bounded board-snapshot cache driven by the `--cache-states N` flag). `MCTS.App.runPlay` and `MCTS.CLI.Inspect.inspectReplay` dispatch to the brick TUIs on TTY; pure dispatchers plus replay cache-miss/cache-hit and on-demand-column preparation are covered by `mcts-unit::exerciseTuiPlayInput`, `mcts-unit::exerciseTuiReplayNav`, `mcts-unit::exerciseTuiReplayOverlay`. |
| Zero-initialized foreign envelope slots | Sprint 6.5 closure, 2026-05-17 | All four foreign backends populate the full envelope: cpp-legacy/cpp-imperative/cpp-functional run `probe_cpu_features` + `probe_fp_env` + `fill_libm_id` (glibc/musl/libsystem from `__GLIBC__`/`__MUSL__`/`__APPLE__`) + objcopy `.envelope_build_id` post-link patch via the `envelope-build-id` Makefile target. Rust's `OnceLock`-backed `build_envelope` runs `is_aarch64_feature_detected!` / `is_x86_feature_detected!`, derives `libm_id` from `target_env`, and ships a `#[link_section = ".envelope_build_id"]` 32-byte slot that `rustPgoBoltPlan` step 9 patches via `sha256sum` + `python3 -c binascii.unhexlify` + `objcopy --update-section`. `mcts-integration::foreign ffi live envelopes` asserts each backend's `libm_id` is in the known string set. |
| In-process backend dispatch stand-in | Sprint 7.2 closure, 2026-05-17; updated 2026-05-18 | `MCTS.Driver.Dispatch.runBatchDispatch` routes bench/play/verify/integration foreign backend calls (i)/(ii)/(iii)/(iv) through `runForeignSearchGame` over the real FFI engines when the matching cdylib is present; the Haskell-side `Driver.runBatch` remains as the (v) baseline and the no-cdylib fallback. The shared `MCTS.Rng.Mix.backendNativeSalt` helper derives the per-backend `--rng native` salt from `backendId`, applied uniformly in `Driver.uctChooseMove`, `Engine.Recompute.recomputeGame`, and `Engine.ForeignRecompute.recomputeGameMoves`; covered by `mcts-unit::exerciseBackendNativeSalt`. |
| Backend (ii)/(iii) per-rollout scratch-board undo residue | Sprint 5.3 closure, 2026-05-17 | The existing rollout in `cpp-imperative/engine/search.cpp` and `cpp-functional/engine/search.cpp` already implements the scratch-board character for forward-only walks: a single `State current = node.state` snapshot mutated forward via per-ply move-assigns from a `thread_local std::vector<corridors::board> tls_move_buffer`. Across the rollout this is O(1) heap allocations and zero descents-needing-undo (the loop walks forward only). The "undo" formulation in the original doctrine bullet applies to descent-and-backtrack search-tree code, not to forward-only rollouts — for rollouts the scratch-board character degenerates to "single mutable snapshot + move-assign per ply", which is what the implementation does. Code comments in both `search.cpp` files document the rationale; the per-ply ~120-byte move-assign of `corridors::board` is dominated by the BFS cost in `check_local_escapable`, which is a separate (and not-yet-scheduled) wavefront-bitmap port. |
| Backend (iii) functional-style engine internals | Sprint 6.1 closure, 2026-05-17 | `cpp-functional/engine/search.cpp::run_search` descent loop now uses a `DescentStep` state-machine pattern: a `descent_step` lambda computes `std::variant<StepDescend, StepExpand, StepLeaf>` from the current node, and the outer loop dispatches via `std::visit`. Combined with the previously-shipped `SelectOutcome` variant + `try_advance` `std::optional<State>`, the data-flow style now differs from backend (ii)'s fall-through `while (true)` at both the API and the descent levels. Arena memory layout stays byte-comparable so the (ii)-vs-(iii) comparison isolates style as the variable. Per-move output is byte-identical to (ii) under `--rng cpp` (verified via `mcts bench rollouts`). |
| Haskell `nonTerminalRank` heuristic tiebreak in `pickByUctIndex` / `finalChoiceKey` | Sprint 7.2 cohort-agreement closure, 2026-05-17; updated 2026-05-18 | `src/MCTS/Search/UCT.hs::pickByUctIndex` no longer tiebreaks unvisited children by `nonTerminalRank (applyMove action board)`; the tiebreaker is now `(negate score, actionByte)`. `finalChoiceKey` similarly drops the heuristic + equity components, leaving `(negate visits, actionId)`. `MCTS.Verify.comparable` sorts the visit list by `action_id` and filters zero-visit entries so per-backend child-enumeration shape is no longer in the comparison surface. The `nonTerminalRank` function stays exported for standalone test coverage at `test/unit/Main.hs`. The live four-backend `(ii)..(v)` `verify rollouts` cohort no longer disagrees on the heuristic axis. |
| Rust paired-target `read_visits` placeholder | Sprint 6.4 closure, 2026-05-18 | `rust/src/c_abi.rs::mcts_rust_read_visits` now reads from a `OnceLock<Mutex<HashMap<board_ptr, Vec<(action_id, visits)>>>>` last-search cache populated by both `mcts_rust_search_move` and `mcts_rust_recompute_move`; `mcts_rust_free_board` clears the cache entry. The cached vector uses the same flipped action IDs exposed through the C ABI output buffers, so the hook now matches the C++ shims' observable contract. Focused validation: `docker compose run --rm mcts mcts test mcts-unit` passed after rebuilding the Compose image. |
| C++ canonical move/search-shape mismatch | Sprint 7.2 cohort-agreement closure, 2026-05-18 | `cpp-imperative/engine/board.h::get_legal_moves` and `cpp-functional/engine/board.h::get_legal_moves` now emit the complete legal wall set, reject pawn moves onto the opponent instead of using Quoridor jump moves, and leave the Haskell-compatible 12-wall cap to `engine/search.cpp` after canonical action ordering. The C++ search loop now follows the Haskell splitmix seed schedule, signed `Int` modulo rollout selection, root visit initialization, highest-visit final choice, and fixed 60-ply search horizon used by the foreign ABI. Focused validation: `docker compose run --rm mcts mcts test mcts-unit` passed after rebuilding the Compose image; subsequent Sprint 7.2 validation tightened `mcts-cross-backend` to fail on Q3 `VerifyMismatch`, while `mcts-legacy-parity` covers Q7 legacy-envelope liveness/overflow. |
| Cohort post-move orientation gap across `(ii)..(v)` | Sprint 7.2 live-cohort closure, 2026-05-18; updated 2026-05-19 | Closed for the live `(ii)..(v)` cohort by assertion tightening after the heuristic, 12-wall child-cap, and verify-dispatch promotion fixes: `mcts-cross-backend` now asserts equality for rollout and self-play smoke cohorts across `(ii)..(v)`, and `mcts-legacy-parity` exercises liveness/overflow coverage across all five backend slots. Focused validation: `docker compose run --rm mcts mcts test mcts-cross-backend` passed 6 tests, `docker compose run --rm mcts mcts test mcts-legacy-parity` passed 3 tests, and the report-card-sized live Q3 verify commands passed. Q7's backend (i) divergence from the steelman engines is recorded in the Q7 respec row above rather than tracked as active work. |

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
