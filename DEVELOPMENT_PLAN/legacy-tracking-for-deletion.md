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

The repository now contains a two-live-backend implementation baseline plus
retired backend (i), backend (ii), and backend (iii) archives. The
validation-data doctrine sweep is closed: normal tests do not require checked-in
transcripts, throughput anchors, renderer snapshots, schema fixtures, or other
generated validation data. Completed rows below preserve the cleanup and
retirement history that led to this state.

Two classes of entries populate this ledger over time:

1. **Doctrine-deviation residue.** Any worktree behavior that the implemented code
   does not yet honour against an in-scope doctrine section, scheduled through the
   owning sprint per standards rule L.
2. **Retirement protocol entries.** Each retiring backend's CLI flag value, build
   artefact, and shared library is moved to `Pending Removal` at the start of its
   retirement (Phase `8`) and to `Completed` when the surviving cohort's evidence is
   recorded without requiring generated validation data in git and the validation gate
   passes. The
   retirement order is `cpp-legacy` (after Q6 closure), then `cpp-imperative`
   (closed Sprint `8.5` after `cpp-functional` reached parity), then
   `cpp-functional` (Sprint `8.6` implementation after `haskell` reached
   parity). Backend (iv) Rust remains live throughout.

`MCTS_legacy` itself lives at `~/MCTS_legacy/` and is not in this repository; legacy
entries here track only shims and compatibility helpers introduced *inside* this
repository that are slated for removal. The `cpp-legacy/` sources are now a retired
reference and optional local evidence-generation home: Sprint `8.4` recorded their
historical evidence and removed the live backend path.
The `cpp-imperative/` sources are now a retired reference: Sprint `8.5` froze
their historical evidence and removed the live backend
path while preserving the transcript wire tag for archived files.
The `cpp-functional/` sources are now a retired reference: Sprint `8.6` froze
their historical evidence, removed the live
CLI/build/verify/FFI path, and preserved the transcript wire tag for archived
files.

## Pending Removal

| Item | Location | Reason | Owning Sprint |
|------|----------|--------|---------------|
| _None_ | _N/A_ | _All known generated-validation-data residue is closed._ | _N/A_ |

## Pending Removal Notes

Each pending-removal row resolves on the closure of the owning sprint listed in the
relevant phase document. Each row will move to `Completed` when the owning sprint closes
and the doctrine-required replacement is verified (or, for retirement entries, when the
surviving cohort's evidence is recorded without generated repository validation data).

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
  surviving cohort's evidence is recorded without generated repository validation data.

## Completed

| Item | Removed In | Notes |
|------|------------|-------|
| Multi-game transcript file layout | Sprint 7.5, 2026-05-16 | `writeTranscriptPerGame` in `src/MCTS/Transcript.hs` splits batches into one-game-per-file transcripts with per-game splitmix seeds; `MCTS.Driver.runBatchWithGame` reports the resulting hash/path pairs, and `mcts-unit::exercisePerGameTranscriptWriter` covers the behavior. |
| PGO+BOLT pipeline | Sprint 5.3, updated Sprint 6.4, 2026-05-18 | The shared C++ `pgoBoltPlan` in `src/MCTS/CLI/Build.hs` shipped the typed 19-step PGO+BOLT pipeline for the C++ backends before their retirements, including canonical FFI training installs and explicit PGO fallback when BOLT data is unavailable. |
| Backend (iv) Rust Corridors gameplay port | Sprint 6.3, 2026-05-16; updated Sprint 7.2, 2026-05-18 | `rust/src/board.rs`, `rust/src/rollout.rs`, and `rust/src/search.rs` now carry the real Corridors game state, rollout loop, and arena MCTS, and `MCTS.Driver.Dispatch.runBatchDispatch` routes `--backend rust` through the real FFI engine when the cdylib is present. |
| Foreign-engine recompute streaming to `.eq` sidecars | Sprint 7.5, 2026-05-16 | `MCTS.Engine.ForeignRecompute.foreignRecomputeEqStream` drives backend recompute ABIs through transcripts, `MCTS.Verify.Divergence.divergenceVsEqStream` scores the resulting `EqStream`, and `mcts inspect divergence` renders cached and available foreign recompute rows. |
| Logical report-card placeholders | Sprint 7.3 / Sprint 8.3 evidence closure, 2026-05-18 | The static report-card renderer originally used intentional `Evidence pending` sentinels for renderer determinism; Sprint 8.8 removes checked-in renderer baselines. The live `mcts test all` path requires the live Rust artefact, measures Haskell Q1/Q2/Q5 with the production monotonic clock through `runBatchNoWriteDispatch`, compares those rates against the frozen backend (ii) throughput anchor, derives the verdict, and populates divergence rows from the measured `G_V = 4` verify cohort. |
| Measured Q1-Q7 report-card evidence | Sprint 7.3 / Sprint 8.3 evidence closure, updated 2026-05-19 | `docker compose run --rm mcts mcts test all` passed against the canonical workload and recorded Q1 ST 0.05x, Q1 MT8 0.41x, Q2 ST 0.05x, Q2 MT8 0.20x, Q5 Haskell 0.99x, Q5 cpp-imperative 3.64x, zero live-cohort divergence, Q7 historical backend (i) liveness evidence PASS, and verdict `Within tolerance`. |
| Pure Haskell parity proof vs backend (ii) | Sprint 8.2 / Sprint 8.3 closure, 2026-05-19 | Sprint 8.1 closed the LLVM/RTS tuning baseline. Sprint 8.2 ran three profile-driven rounds on 2026-05-16: round 1 IntSet (~6.2× speedup), round 2 strict-pair Word64 (regression, reverted), round 3 wavefront-bitmap BFS over `Bits128` (~52× legal-moves / ~33× uct-search vs round 1; **combined ~320× / ~200× vs original baseline**). The 2026-05-19 canonical report card records Q1/Q2 within `HASKELL_PARITY_TOLERANCE = 0.05` in both threading modes and verdict `Within tolerance`, so backend-retirement work is no longer blocked on Haskell tuning. |
| Backend (i) `cpp-legacy` live backend surface | Sprint 8.4 retirement, 2026-05-19 | Removed live `cpp-legacy` operator selection from the CLI backend parser, `mcts verify legacy-parity`, `mcts build cpp-legacy`, the `mcts-legacy-parity` Cabal stanza, live dispatch/recompute/play paths, the prerequisite node, and the Haskell FFI/driver modules (`src/MCTS/FFI/CppLegacy.hs`, `src/MCTS/Driver/CppLegacy.hs`, `src/MCTS/Rng/Cpp.hs`). The wire-format `CppLegacy` tag remains so archived transcripts decode. Historical Q6/Q7 evidence is no longer a repository validation-data input. |
| Backend (ii) `cpp-imperative` live backend surface | Sprint 8.5 retirement, 2026-05-19 | Removed live `cpp-imperative` operator selection from the CLI backend parser, `mcts build cpp-imperative`, live dispatch/recompute/play paths, verify cohort membership, the prerequisite node, and the Haskell FFI/driver modules (`src/MCTS/FFI/CppImperative.hs`, `src/MCTS/Driver/CppImperative.hs`). The wire-format `CppImperative` tag remains so archived transcripts decode. The retirement evidence recorded backend (iii) parity with backend (ii) on Q1 and Q2. |
| Backend (iii) `cpp-functional` live backend surface | Sprint 8.6 retirement, 2026-05-19 | Removed live `cpp-functional` operator selection from the CLI backend parser, `mcts build cpp-functional`, live dispatch/recompute/play paths, verify cohort membership, the prerequisite nodes, and the Haskell FFI/driver modules (`src/MCTS/FFI/CppFunctional.hs`, `src/MCTS/Driver/CppFunctional.hs`). The wire-format `CppFunctional` tag remains so archived transcripts decode. The retirement evidence recorded backend (v) parity with backend (iii) on Q1 and Q2. |
| Dynamic Rust FFI load policy | Sprint 8.7 plan closure, 2026-05-19 | Closed as supported architecture rather than removal residue: `src/MCTS/FFI/Common.hs`, `src/MCTS/FFI/Rust.hs`, `src/MCTS/Driver/ForeignSmoke.hs`, and `src/MCTS/Driver/Rust.hs` keep dynamic loading so Cabal builds/tests remain independent of local shared-library paths while operator-facing bench/play/verify/inspect-divergence use the real Rust visit-vector and recompute ABIs when the cdylib is present. |
| Rust non-PGO development artefact policy | Sprint 8.7 plan closure, 2026-05-19 | Closed as supported build-intermediate policy rather than deletion residue: `rust/` keeps non-PGO/smoke outputs as local development artefacts alongside the canonical PGO-or-BOLT install path produced by `mcts build rust`. Retired C++ source homes are reference archives, not live non-PGO artefact surfaces. |
| Legacy warning suppression | Sprint 8.4 retirement, 2026-05-19 | The `cpp-legacy/Makefile` warning suppression no longer belongs to a live backend build path. `cpp-legacy/legacy-core/` remains for reference and optional local `legacy-to-wire` evidence generation only. |
| Backend (ii) `-optlo-mcpu=native` / `-optlc-mcpu=native` on aarch64 | Sprint 8.2 closure, 2026-05-19 | Closed as a documented non-adoption: enabling per-CPU LLVM flags through `-fllvm` on aarch64 emits LSE instructions the container's assembler refuses (`instruction requires: lse`). The flags are not in the current flag set, and the parity gate passed without them. |
| LLVM-BOLT shared-library limitations | Sprint 6.4 / Sprint 8.3 closure, updated 2026-05-19 | The build harness explicitly installs the PGO artefact as the canonical fallback when C++ shared-library BOLT instrumentation yields no `.fdata` in the pinned container. The 2026-05-19 parity report card measured the canonical installed artefacts exactly as built by the container, including that documented fallback. Reopen only if the project later requires a true C++ shared-library BOLT comparison for a new target. |
| Q7 legacy-envelope liveness respec | Sprint 7.2 closure, 2026-05-19 | Closed by deliberately respecifying Q7 as a five-backend legacy-envelope liveness/overflow gate. The live investigation found backend (i)'s legacy tree search can diverge from the steelman engines at the report-card budget: the visit-count comparison failed at `game=0`, `move=10` with the same chosen move (`Pawn 4 6`), and a chosen-move comparison failed at `game=0`, `move=0` (`cpp-legacy` chose `WallV 2 1`, `cpp-imperative` chose `Pawn 4 1`). Q3 remains the visit-vector equality gate for the surviving live cohort, and Q6 remains historical byte-for-byte backend (i) legacy evidence. |
| Live FFI Q3 cohort determinism gap | Sprint 7.2 live promotion, 2026-05-18 | Resolved for Q3: `MCTS.Verify.runAndCompare` now dispatches through `MCTS.Driver.Dispatch.runBatchDispatch`, and envelope verification uses `checkTranscriptEnvelopesLive`, so the then-live `(ii)..(v)` verify cohort used live foreign cdylibs when present and the in-process runner only as the no-cdylib fallback. Validation after promotion: `docker compose run --rm mcts mcts test mcts-cross-backend`, `docker compose run --rm mcts mcts test mcts-legacy-parity`, `docker compose run --rm mcts mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200`, and `docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500` pass. Later retirement sprints reduced the live Q3 cohort to `(rust, haskell)`. Q7 now uses historical backend (i) liveness evidence rather than a backend (i) visit-vector comparison. |
| Deterministic placeholder transcript hash | Sprint 2.2 baseline closure | Replaced `pseudoSha256Hex` in `src/MCTS/Transcript.hs` with the pure SHA-256 implementation in `src/MCTS/Crypto/SHA256.hs`; `runConfigHash` and `playTranscriptHash` now emit SHA-256 hex digests. |
| No-op sidecar cache and divergence inspect placeholders | Sprint 2.7 / Sprint 7.5 baseline closure | Replaced fixed `inspect cache list`, `inspect cache prune`, and `inspect divergence` output with `MCTS.Transcript.EquitySidecar` cache discovery/pruning and `MCTS.Verify.Divergence` metric rendering. |
| Missing baseline/live envelope verification and legacy-parity workload dispatch | Sprint 7.5 baseline closure, updated 2026-05-18 | Added `MCTS.Verify.Envelope`, `--allow-stale` parser/execution plumbing, `inspect show --envelope`, and fixed `verify legacy-parity rollouts` so the parsed workload reaches execution. Later Sprint 7.5 work added `MCTS.FFI.Common.engineEnvelopeToEnvelope`, FFI-produced transcript stamping from `mcts_<backend>_get_envelope()` in `MCTS.Driver.Dispatch`, `checkTranscriptEnvelopesLive` comparison against live cdylib envelopes with in-process fallback when the cdylib is absent, structured JSON `warning_details` for downgraded backend-slot stale warnings, and `mcts-integration` coverage for real live-envelope stamping plus stale compiler-version hard-fail/`--allow-stale` warning behavior. |
| Minimal four-field engine envelope | Sprint 2.6 closure | Replaced the `{version, backend, host_arch, build_id}` placeholder with the full v1 doctrine envelope: `rng_source`, `shared_rng_build_id`, `cohort_config_hash`, `engine_build_id`, `engine_git_commit`, `compiler_id`, `compiler_version`, `fp_flags`, `libm_id`, `cpu_features`, `fp_env`, plus the project-local `build_id` accessor field. Wire format matches the C ABI `mcts_<backend>_envelope` struct byte-for-byte. |
| `Show`/`Read` equity sidecar codec | Sprint 2.7 closure | Replaced the `Show`/`Read` round-trip with the fixed-width binary `MEQ1` codec (4-byte magic + u16 version + length-prefixed strings + 15-byte fixed records + `0xFFFFFFFF` terminator), atomic temp-file + rename writes, and `castWord64ToDouble` for IEEE-754 round-trips. |
| Synthetic `chooseMove` weight generator | Sprint 3.3 closure | Removed `MCTS.Engine.chooseMove` and `rawWeight`. The driver now dispatches every per-move search through `MCTS.Search.UCT.uctSearch` running over `MCTS.Search.Arena`. Cross-backend visit-count equality holds under `--rng cpp`; per-backend salt under `--rng native` preserves bench distinguishability. |
| `getSystemTime`-based bench timing | Sprint 3.5 closure | Replaced with the pinned monotonic clock `GHC.Clock.getMonotonicTimeNSec` exposed via `MCTS.CLI.Bench.monotonicNanos`. The test-injectable variant `runBenchWithClock` allows the `mcts-unit` stanza to assert the bench bracket reads the clock exactly twice per backend. |
| Generated command-doc drift | Sprint 1.3 baseline closure | `renderCommandMarkdown` now emits the governed-doc metadata and the documented `inspect show --envelope` row; `MCTS.CLI.Docs` compares tracked generated files and marker-delimited regions through `mcts docs check`. |
| Comma-list report-card benchmark placeholder | Sprint 7.3 baseline closure | `parseBench` now parses comma-separated `--backend` lists and `runBench` iterates every requested backend, so the report-card workload no longer collapses to the first backend. |
| `S_LP_SIMS = 10000` legacy evidence sim count | Sprint 7.1 / Sprint 7.5 Q6 evidence refresh, 2026-05-18 | Historical record: the Q6 evidence was regenerated at `S_LP = 42`, `G_LP = 10`, `S_LP_SIMS = 10000`, `max_plies = 10000` through `docker compose run --rm mcts mcts build legacy-fixtures`. The external checkout at `/home/matt/MCTS_legacy` was clean at `97dd6ed7908a20234e3857c1bb4f8af46b507e0a`; `diff -qr -w` showed only external build/binding/test helper files outside the imported `backend/core` logic. Sprint 8.8 removes the committed-fixture test dependency while preserving this historical evidence. |
| `brick`/`vty` interactive TUI event loops | Sprint 7.4 closure, 2026-05-16; updated 2026-05-18 | `cabal.project` `allow-newer: config-ini:containers, config-ini:base` unblocked `brick-2.12` + `vty-6.5`. `MCTS.CLI.Tui.{Board,Play,Replay}` render the 9×9 board with pawn cells plus horizontal/vertical wall segments, the interactive `mcts play` event loop (legacy notation + `:hint`/`:undo`/`:quit`/`:q`; `:save` writes a hand-play transcript through `MCTS.Transcript.writePlayTranscript` addressed by `sha256(run_config || move_history)`; AI turns use `MCTS.Driver.ForeignSearch.foreignSearchMove` for selected foreign backends when cdylibs are present and in-process fallback when absent), and the replay navigator (forward/back/home/end + multi-backend equity overlay column populated from cached `.eq` sidecars + originator cache-miss recompute/visit-checking before TUI start + `r`-key on-demand backend column recompute/write + a bounded board-snapshot cache driven by the `--cache-states N` flag). `MCTS.App.runPlay` and `MCTS.CLI.Inspect.inspectReplay` dispatch to the brick TUIs on TTY; pure dispatchers plus replay cache-miss/cache-hit and on-demand-column preparation are covered by `mcts-unit::exerciseTuiPlayInput`, `mcts-unit::exerciseTuiReplayNav`, `mcts-unit::exerciseTuiReplayOverlay`. |
| Zero-initialized foreign envelope slots | Sprint 6.5 closure, 2026-05-17 | All four foreign backends populate the full envelope: cpp-legacy/cpp-imperative/cpp-functional run `probe_cpu_features` + `probe_fp_env` + `fill_libm_id` (glibc/musl/libsystem from `__GLIBC__`/`__MUSL__`/`__APPLE__`) + objcopy `.envelope_build_id` post-link patch via the `envelope-build-id` Makefile target. Rust's `OnceLock`-backed `build_envelope` runs `is_aarch64_feature_detected!` / `is_x86_feature_detected!`, derives `libm_id` from `target_env`, and ships a `#[link_section = ".envelope_build_id"]` 32-byte slot that `rustPgoBoltPlan` step 9 patches via `sha256sum` + `python3 -c binascii.unhexlify` + `objcopy --update-section`. `mcts-integration::foreign ffi live envelopes` asserts each backend's `libm_id` is in the known string set. |
| In-process backend dispatch stand-in | Sprint 7.2 closure, 2026-05-17; updated 2026-05-18 | `MCTS.Driver.Dispatch.runBatchDispatch` routes bench/play/verify/integration foreign backend calls (i)/(ii)/(iii)/(iv) through `runForeignSearchGame` over the real FFI engines when the matching cdylib is present; the Haskell-side `Driver.runBatch` remains as the (v) baseline and the no-cdylib fallback. The shared `MCTS.Rng.Mix.backendNativeSalt` helper derives the per-backend `--rng native` salt from `backendId`, applied uniformly in `Driver.uctChooseMove`, `Engine.Recompute.recomputeGame`, and `Engine.ForeignRecompute.recomputeGameMoves`; covered by `mcts-unit::exerciseBackendNativeSalt`. |
| Backend (ii)/(iii) per-rollout scratch-board undo residue | Sprint 5.3 closure, 2026-05-17 | The existing rollout in `cpp-imperative/engine/search.cpp` and `cpp-functional/engine/search.cpp` already implements the scratch-board character for forward-only walks: a single `State current = node.state` snapshot mutated forward via per-ply move-assigns from a `thread_local std::vector<corridors::board> tls_move_buffer`. Across the rollout this is O(1) heap allocations and zero descents-needing-undo (the loop walks forward only). The "undo" formulation in the original doctrine bullet applies to descent-and-backtrack search-tree code, not to forward-only rollouts — for rollouts the scratch-board character degenerates to "single mutable snapshot + move-assign per ply", which is what the implementation does. Code comments in both `search.cpp` files document the rationale; the per-ply ~120-byte move-assign of `corridors::board` is dominated by the BFS cost in `check_local_escapable`, which is a separate (and not-yet-scheduled) wavefront-bitmap port. |
| Backend (iii) functional-style engine internals | Sprint 6.1 closure, 2026-05-17 | `cpp-functional/engine/search.cpp::run_search` descent loop now uses a `DescentStep` state-machine pattern: a `descent_step` lambda computes `std::variant<StepDescend, StepExpand, StepLeaf>` from the current node, and the outer loop dispatches via `std::visit`. Combined with the previously-shipped `SelectOutcome` variant + `try_advance` `std::optional<State>`, the data-flow style now differs from backend (ii)'s fall-through `while (true)` at both the API and the descent levels. Arena memory layout stays byte-comparable so the (ii)-vs-(iii) comparison isolates style as the variable. Per-move output is byte-identical to (ii) under `--rng cpp` (verified via `mcts bench rollouts`). |
| Haskell `nonTerminalRank` heuristic tiebreak in `pickByUctIndex` / `finalChoiceKey` | Sprint 7.2 cohort-agreement closure, 2026-05-17; updated 2026-05-18 | `src/MCTS/Search/UCT.hs::pickByUctIndex` no longer tiebreaks unvisited children by `nonTerminalRank (applyMove action board)`; the tiebreaker is now `(negate score, actionByte)`. `finalChoiceKey` similarly drops the heuristic + equity components, leaving `(negate visits, actionId)`. `MCTS.Verify.comparable` sorts the visit list by `action_id` and filters zero-visit entries so per-backend child-enumeration shape is no longer in the comparison surface. The `nonTerminalRank` function stays exported for standalone test coverage at `test/unit/Main.hs`. The then-live four-backend `(ii)..(v)` `verify rollouts` cohort no longer disagreed on the heuristic axis, and later retirement sprints preserved that evidence historically. |
| Rust paired-target `read_visits` placeholder | Sprint 6.4 closure, 2026-05-18 | `rust/src/c_abi.rs::mcts_rust_read_visits` now reads from a `OnceLock<Mutex<HashMap<board_ptr, Vec<(action_id, visits)>>>>` last-search cache populated by both `mcts_rust_search_move` and `mcts_rust_recompute_move`; `mcts_rust_free_board` clears the cache entry. The cached vector uses the same flipped action IDs exposed through the C ABI output buffers, so the hook now matches the C++ shims' observable contract. Focused validation: `docker compose run --rm mcts mcts test mcts-unit` passed after rebuilding the Compose image. |
| C++ canonical move/search-shape mismatch | Sprint 7.2 cohort-agreement closure, 2026-05-18 | `cpp-imperative/engine/board.h::get_legal_moves` and `cpp-functional/engine/board.h::get_legal_moves` now emit the complete legal wall set, reject pawn moves onto the opponent instead of using Quoridor jump moves, and leave the Haskell-compatible 12-wall cap to `engine/search.cpp` after canonical action ordering. The C++ search loop now follows the Haskell splitmix seed schedule, signed `Int` modulo rollout selection, root visit initialization, highest-visit final choice, and fixed 60-ply search horizon used by the foreign ABI. Focused validation: `docker compose run --rm mcts mcts test mcts-unit` passed after rebuilding the Compose image; subsequent Sprint 7.2 validation tightened `mcts-cross-backend` to fail on Q3 `VerifyMismatch`, while `mcts-legacy-parity` covers Q7 legacy-envelope liveness/overflow. |
| Cohort post-move orientation gap across `(ii)..(v)` | Sprint 7.2 live-cohort closure, 2026-05-18; updated 2026-05-19 | Closed for the then-live `(ii)..(v)` cohort by assertion tightening after the heuristic, 12-wall child-cap, and verify-dispatch promotion fixes: `mcts-cross-backend` asserted equality for rollout and self-play smoke cohorts across `(ii)..(v)`, and `mcts-legacy-parity` exercised liveness/overflow coverage across all five backend slots. Focused validation: `docker compose run --rm mcts mcts test mcts-cross-backend` passed 6 tests, `docker compose run --rm mcts mcts test mcts-legacy-parity` passed 3 tests, and the report-card-sized live Q3 verify commands passed. Later retirement sprints reduced the live cohort while freezing the retired evidence. Q7's backend (i) divergence from the steelman engines is recorded in the Q7 respec row above rather than tracked as active work. |
| Checked-in/generated validation data assumptions | Sprint 8.8 closure, 2026-05-19 | `test/golden/**` generated transcripts, renderer snapshots, report-card schema files, and retired throughput anchors are deleted. `test/unit/Main.hs` now uses semantic renderer assertions, property tests, in-memory transcript bytes, and temporary cache roots; `test/integration/Main.hs` uses synthetic retired-backend transcripts in temporary roots. `src/MCTS/Generated/Paths.hs` no longer tracks validation fixture directories. Validation passed with `test/golden/` absent: `mcts-unit`, `mcts-integration`, `mcts-cross-backend`, `docs check`, `mcts test all`, `mcts check-code`, and `git diff --check`. |
| Legacy fixture output default | Sprint 8.8 closure, 2026-05-19 | `mcts build legacy-fixtures` requires `--output-dir`; `src/MCTS/CLI/Spec.hs` and governed CLI docs point examples at `/tmp/mcts-legacy-fixtures`; the standalone C++ helper defaults only to `.build/legacy-fixtures/transcripts` for direct local use. Generated evidence remains optional external/ignored audit data, not normal test input. |
| `tasty-golden` renderer/codec providers | Sprint 8.8 closure, 2026-05-19 | The `mcts-unit` stanza no longer depends on `tasty-golden`, and `mcts.cabal` removed the dependency. Command, report-card, inspect, error, subprocess, transcript, known-position, and TUI coverage now asserts typed/semantic contracts without checked-in snapshot files. |

## Retirement Protocol Reference

The retirement chain documented in [00-overview.md](00-overview.md) and owned by
[phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md):

| Order | Retiring Backend | Trigger | Surviving Cohort | Evidence |
|-------|------------------|---------|------------------|----------|
| 1 | `cpp-legacy` (i) | Q6 closure: `cpp-legacy` reproduces `MCTS_legacy` byte-for-byte on benchmark (b) under the legacy parity envelope | `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | Historical/external evidence (closed Sprint 8.4) |
| 2 | `cpp-imperative` (ii) | `cpp-functional` reaches parity with `cpp-imperative` on Q1 and Q2 | `cpp-functional`, `rust`, `haskell` | Historical/external evidence (closed Sprint 8.5) |
| 3 | `cpp-functional` (iii) | `haskell` reaches parity with `cpp-functional` on Q1 and Q2 | `rust`, `haskell` | Historical/external evidence (closed Sprint 8.6) |
| — | `rust` (iv) | _(does not retire; kept as the long-running cross-language second opinion throughout)_ | — | — |
| — | `haskell` (v) | _(target; does not retire)_ | — | — |

Q7 and the `mcts-legacy-parity` test stanza retired alongside backend (i), since both
required a live (i) binary to participate in the 5-way liveness gate. The transitive
parity chain `MCTS_legacy ≡ (i) ≡ (ii)..(v)` is now a historical fact recorded in
the plan/docs or optional external artifacts rather than a continuously re-run
clean-clone check. Q3 and the `mcts-cross-backend` stanza continue with the
surviving live subset `(rust, haskell)`.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
