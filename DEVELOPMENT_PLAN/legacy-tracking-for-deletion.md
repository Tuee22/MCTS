# Legacy Tracking

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[00-overview.md](00-overview.md), [system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md),
[phase-2-transcript-codec-and-determinism.md](phase-2-transcript-codec-and-determinism.md),
[phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md),
[phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md),
[phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md),
[phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md),
[phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md),
[phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md),
[../CLAUDE.md](../CLAUDE.md),
[../AGENTS.md](../AGENTS.md),
[../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md),
[../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md),
[../documents/engineering/code_quality.md](../documents/engineering/code_quality.md),
[../documents/engineering/compiler_runtime_tuning.md](../documents/engineering/compiler_runtime_tuning.md),
[../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md),
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

The 2026-05-27 Dockerfile prebuild closure moved normal Cabal compile/link work into
image construction as well: the image now prebuilds the executable with tests and
benchmarks enabled, installs the test-suite and `mcts-criterion` benchmark
executables, and builds foreign backend artefacts before runtime commands consume
them.

The same-day documentation-topology audit found one stale-reference class:
`HASKELL_CLI_TOOL.md` was absent from the current worktree while root guidance docs,
the plan suite, governed engineering docs, and source comments still cited it as the
canonical CLI doctrine. Sprint `0.3` restored that root doctrine file on
2026-05-27, so the existing doctrine citations resolve again.

The 2026-05-24 benchmark-metric audit added stale benchmark labels and report-card
rows to this ledger. Sprint `3.8` added explicit `terminal-playouts` and
`search-iters` benchmark leaves, and Sprint `7.8` split the report card into
unit-aware Q1a/Q1b/Q2/Q5 rows. The 2026-05-25 played-game renderer cleanup
removed the derived simulation-rate output so `games/s` is the only played-game
throughput unit. Sprint `8.11` closed the profile-suite review and fresh parity
rerun, so no metric-suite cleanup row remains pending.

The 2026-05-25 backend-style audit added backend (iii)'s legacy-board/text-action
hot path to Pending Removal. Sprint `6.7` closed that cleanup on 2026-05-26 by
replacing it with compact functional-core value-state C++ while keeping Rust's
already compact value-state boundary in the live cohort. Later raw-performance
review found separate Rust hot-path residue: queue-BFS path checks, heap legal-action
buffers, under-reserved arena growth, avoidable board clones, and a global visit-cache
map. Sprint `6.8` closed that residue without reopening Sprint `6.7`'s backend
(iii) closure. Sprints `8.12`, `8.13`, and `8.14` then closed the Haskell parity,
style follow-up, and report-card verdict gate against the corrected backend (ii)
target, so no Phase `8` style, parity, or verdict-gating cleanup row remains pending.

Sprint `7.10` closed the stale report-card presentation shape: text output now
aligns columns, states the report-card terms and questions, and includes raw
Q1a/Q1b/Q2 metrics for every backend slot before the question summary and
divergence matrix, followed by explicit Q1a-Q6 answers based on observed metrics
and gate outcomes. No pending report-card presentation cleanup remains.

Sprint `0.4` closed the remaining README-as-authority citation drift after README
became reference-only. Sprint `1.12` closed generated command-summary drift where
`mcts bench rollouts` was still described as a random-rollout benchmark even though
the implemented surface is a legacy played-game workload. No pending SSoT or generated
`bench rollouts` cleanup row remains.

Sprint `7.11` closed the narrow report-card presentation cleanup: empirical
divergence-threshold constants and renderer text were replaced by a single
normalized divergence score plus Q7 semantic-parity evidence.

The 2026-05-28 backend `(ii)` steelman audit reopened Phase `5` for Sprint `5.7`
and Phase `8` for Sprint `8.15`. Sprint `5.7` has closed the imperative-kernel
residue in backend `(ii)`. The remaining pending row tracks the active Haskell
parity shortfall exposed by the fail-closed report-card rebaseline against that
stronger `(ii)` target.

The 2026-05-29 backend `(ii)` residual-squeeze audit reopened Phase `5` for
Sprint `5.8` and Phase `8` for Sprint `8.16`. Sprint `5.8` closed three
doctrine-deviation rows on the same date: the wall-legality path-existence
leaf is now a bidirectional bit-parallel BFS; `UctNode`'s `alignas(kCacheLine)`
is removed; and the C++ steelman flag block now carries
`-fno-stack-protector -fno-rtti -fipa-pta` plus extended BOLT
`-split-functions -split-strategy=cdsplit -reorder-functions=cdsort -icf=1`
on top of `-reorder-blocks=ext-tsp`. The flag-name correction from
`hfsort+`/`safe` to `cdsort`/`1` was applied mid-validation after LLVM 19's
BOLT rejected the legacy syntax. Sprint `8.16` recorded the post-`5.8`
Haskell-vs-`(ii)` measurement on the same date: Q1a `1.51x` ST / `1.50x`
MT8, Q1b `1.53x` ST / `1.56x` MT8, Q2 `1.41x` ST / `1.57x` MT8, Q5 scaling
Haskell search `7.16x` vs C++ search `7.31x`, Haskell self-play `3.28x`
vs C++ self-play `3.66x`; `Verdict: Trails parity band by 57.1%`;
Q3/Q4/Q6/Q7 PASS and normalized_divergence_score `0.0000`. The Sprint
`8.15` post-`5.7` measurement is now historical against the pre-`5.8`
`(ii)` artefact.

The 2026-05-29 functional-cohort shape audit then reopened Phase `6` for
Sprints `6.9` (backend (iii)) and `6.10` (backend (iv)), and Phase `8` for
Sprint `8.17` (backend (v)). The audit identified that the three steelman
backends in the functional cohort do not yet adopt every backend-(ii) hot-path
technique that
[../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md)
permits. Sprints `6.9`, `6.10`, and `8.17` closed on the same date; their
rows live in the Completed table below. None of the deliverables touched
the C ABI symbol set, the canonical action ID encoding, the 12-wall cap, the
transcript wire format, or the Q3/Q4/Q6/Q7 invariants; closure followed the
[../documents/engineering/compiler_runtime_tuning.md → Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine)
gate.

The 2026-05-30 compiler-stack closure landed the three remaining
backend-pivot rows from the post-`5.9` audit: Sprint `4.6` flipped
backend (i) cpp-legacy to `clang++-19`, Sprint `6.11` flipped backend
(iii) cpp-functional and migrated its PGO half to LLVM `.profraw` →
merged `.profdata`, and Sprint `4.7` dropped `gcc`/`g++` from the
explicit `docker/Dockerfile` apt-get list and flipped the image's
`ENV CC/CXX` defaults to `clang-19`/`clang++-19`. The Pending Removal
table was empty after that closure; all three rows are in the Completed
table below.

The 2026-06-03 CLI introspection audit reopened Phase `1` for Sprint
`1.13`. The code accepted several closed value sets (`Backend`, Q3
`VerifyBackend`, `RngSource`, `Side`, `Threading`, output/color modes), but
help and command JSON did not expose those value sets consistently, and
`mcts help <path>` was pointer-only. Sprint `1.13` reclosed the same day; the
completed row below records the stale introspection surface cleanup.

The 2026-06-04 command-use audit reopened Phase `1` for Sprint `1.17`.
Generated leaf-command docs still leaned on terse summaries, and the play surface
read like flag inventory: `BACKEND` metavars were not paired with enough operator
text, generated docs did not clearly explain which backend controls which side,
and AI-vs-AI spectator mode was under-described. Sprint `1.17` reclosed the same
day with registry-backed leaf descriptions, focused play parser help, generated
docs, README guidance, and semantic tests; the completed row below records the
stale command-use text cleanup.

The 2026-06-05 operator UI audit reopened Phase `9` Sprint `9.4`, Phase `1`
Sprint `1.18`, Phase `2` Sprint `2.10`, and Phase `7` Sprint `7.12`. The stale
surfaces were operator-facing: hostbootstrap TTY/stdin, the refactored
target/mount shape for persistent cache state, the non-interactive `play`
hash-printing fallback, hash-first `inspect`, split play/replay session status,
recorded-position recompute semantics, and terminal interaction evidence. Those
rows closed the same day and are recorded in the Completed table below.

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

The 2026-05-29 compiler-stack audit reopened Phase `5` and produced four
rows sequenced as "(ii) pilot, then (i) and (iii), then Dockerfile
scrub" so the Sprint `5.9` build-orchestration changes (LLVM PGO
`.profraw` flow, `cppPgoBoltPlan` profile-style split) were validated
before they propagated. All four rows closed on 2026-05-30 through
Sprints `4.6` / `6.11` / `4.7` (see Completed table below).

The 2026-05-30 cross-platform performance investigation (Sprint
`8.18`) added two Pending Removal rows owned by Sprint `8.19`
(Dockerfile-level aarch64 toolchain unblock). Sprint `8.19` closed
the same date 2026-05-30 **measured but rejected** — both rows
have moved to Completed below. The wrapper-routed `-mcpu=apple-m1`
Approach A built cleanly with closure gates PASS, but the arm64
`mcts test all` verdict regressed from `85.6%` to `268.7%` because
LSE/`rcpc-immo` atomics emitted by `llc-19 -mcpu=apple-m1` execute
slower than the baseline ARMv8 LL/SC atomics GHC's RTS was tuned
against under Docker-on-Apple-Silicon. The Sprint `8.18` deferral
and root-cause attribution stand; the deferral now has two
load-bearing reasons instead of one. Sprint `1.13` later closed the
CLI-introspection residue on 2026-06-03.

**2026-06-04 — Phase 9 hostbootstrap implementation closes.** The four
Phase 9 / Phase 1 reopen Pending-Removal rows moved to Completed after
Sprint `9.2` landed `hostbootstrap.dhall`, rewrote `docker/Dockerfile`
to inherit `FROM ${BASE_IMAGE}`, deleted `compose.yaml`, updated source
pins to GHC `9.12.4`, and removed the separate formatter-tools GHC
install layer. `hostbootstrap run test all` exited 0 with
Q3/Q4/Q6/Q7 PASS and `normalized_divergence_score = 0.0000`. Sprint
`9.3` closed without checked-in arm64/amd64 throughput anchors; the
live report card remains the source of truth for current performance
measurements.

**2026-06-05 — Operator play/inspect cleanup closed.** No Pending Removal row
remains for the operator audit. Sprints `9.4`, `1.18`, `2.10`, and `7.12` closed
with aligned generated docs, the refactored `hostbootstrap.dhall` target/mount
config, hostbootstrap PTY smoke evidence, no-argument `play`/`inspect`, descriptive
cache rows, recorded-position recompute, and shared play/replay session status.

## Pending Removal Notes

Pending-removal rows move to `Completed` only after the corrected surface is
implemented, governed docs are aligned, generated docs are regenerated or checked,
and the canonical validation command for that surface passes through
`hostbootstrap run <mcts-args>`. For PGO/BOLT failover rows,
closure also requires a Dockerfile build that exits non-zero on missing profile
data instead of publishing a fallback shared library.

## Completed

| Item | Removed In | Notes |
|------|------------|-------|
| Operator play/inspect stale host path, cache, browser, session, and recompute surfaces | Sprints `9.4`, `1.18`, `2.10`, `7.12`, 2026-06-05 | `hostbootstrap.dhall` now uses the refactored `targets` schema with one `H.Accel.Cpu` target and a scoped `.mcts-cache/` mount; `docker/Dockerfile` labels interactive command paths; hostbootstrap forwards stdin/TTY for labelled `play`, no-argument `inspect`, and `inspect replay` paths; `play` has no-argument defaults and exits with an actionable non-TTY guardrail instead of running the historical batch fallback; no-argument `inspect` opens a descriptive cache browser from a TTY and falls back to list output for non-TTY/JSON use; foreign recompute rebuilds each backend from the recorded cursor history; play/replay share `GameSessionState` and session status rendering. Validation passed `docs generate`, `docs check`, `mcts-unit`, `mcts-integration`, `mcts-cross-backend`, focused help checks, non-TTY `play`, non-TTY `inspect`, and PTY smokes for `play` and `inspect` through `hostbootstrap run`. |
| Heavy multi-language toolchain layers in `docker/Dockerfile` | Sprint `9.2`, 2026-06-04 | The project Dockerfile now inherits `FROM ${BASE_IMAGE}` from the hostbootstrap base image instead of explicitly installing ghcup, GHC, Cabal, the full LLVM/BOLT 19 stack, clang, the clang PGO runtime, Rust, base Rust machinery, formatter tools, and base apt dependencies. The slim overlay adds Cabal executable/test/benchmark installs and the four Dockerfile-time foreign backend builds. `hostbootstrap build` and `hostbootstrap run test all` passed on Apple Silicon / arm64 before the follow-up base-image consolidation. |
| Separate formatter-tools GHC install in `docker/Dockerfile` | Sprint `1.16` + Sprint `9.2`, 2026-06-04 | Removed the `STYLE_GHC_VERSION` ARG, the separate `ghcup install ghc ${STYLE_GHC_VERSION}` step, and the `--with-compiler ghc-${STYLE_GHC_VERSION}` formatter install. Fourmolu `0.19.0.1` and HLint `3.10` now install into `/opt/hostbootstrap/haskell-style/bin/` with the project GHC `9.12.4`. |
| Root `compose.yaml` | Sprint `1.15` + Sprint `9.2`, 2026-06-04 | Deleted the root Compose workflow file. The canonical host-side invocation is `hostbootstrap run <mcts-args>` through root `hostbootstrap.dhall`; direct Compose entrypoints are no longer a supported project workflow. |
| Project Haskell toolchain pinned at GHC `9.14.1` in source surfaces | Sprint `1.14` + Sprint `9.2`, 2026-06-04 | `mcts.cabal`, `cabal.project`, `src/MCTS/Prerequisite.hs`, `src/MCTS/ReportCard.hs`, `src/MCTS/Engine/Envelope.hs`, and `test/unit/Main.hs` now pin or assert GHC `9.12.4`. Historical GHC `9.14.1` references remain only in dated evidence or compatibility notes. |
| Summary-only generated leaf descriptions and thin play command-use text around `BACKEND`, `--side`, and `--vs` | Sprint `1.17`, 2026-06-04 | `src/MCTS/CLI/Spec.hs` now gives every leaf command an action-oriented description and gives `mcts play` examples/notes covering valid backend identifiers, human-vs-AI side ownership, AI-vs-AI spectator mode, and Space-to-advance behavior; `src/MCTS/CLI/Parser.hs` mirrors the play semantics in focused `optparse-applicative` help. `documents/cli/commands.md`, `share/man/man1/mcts.1`, and shell completions regenerate from the same registry, and `test/unit/Main.hs` asserts that every leaf description is action-oriented and that help/generated Markdown keep the play mode text. |
| Pointer-only help and missing enum-value introspection | Sprint `1.13`, 2026-06-03 | `src/MCTS/CLI/Spec.hs` now carries enriched command, option, positional, default, choice, list-syntax, note, example, and completion metadata; `src/MCTS/CLI/Parser.hs` consumes the same value sets for enum readers and renders focused `optparse-applicative` help for `mcts help <path>` and explicit `--help` requests; invalid enum/list parse errors name accepted values and Q3's `cpp-legacy` rejection points to `mcts verify legacy-parity`; `mcts commands --json`, generated Markdown/manpage output, and shell completions expose the enriched registry data. Validation passed `mcts-unit`, `docs check`, `lint haskell`, `lint docs`, `lint files`, `check-code`, `play --help`, `help play`, `commands --json`, the expected exit-2 invalid-backend probe, and `git diff --check` through the Compose workflow. |
| Deferred `-optlo-mcpu=native` / `-optlc-mcpu=native` on aarch64 | Sprint `8.19`, 2026-05-30 (measured but rejected) | Sprint `8.18` Stage 2 root-caused the deferral to binutils-2.42 LSE rejection. Sprint `8.19` Approach A worked around that with a 7-line `/usr/local/bin/clang-19-aarch64-apple-m1` wrapper exec'ing `clang-19 -mcpu=apple-m1`, GHC `settings` patched so both `("C compiler command", ...)` and `("LLVM llvm-as command", ...)` route through the wrapper (the second sed was load-bearing — GHC's `-fllvm` LLVM-assembler stage uses `LLVM llvm-as command`, not `pgm_c`, and ignores `-opta-*` flags). Build completed; Q3/Q4/Q6/Q7 PASS; `normalized_divergence_score=0.0000`. **Measurement rejected:** arm64 `mcts test all` verdict regressed `85.6% → 268.7%`; Haskell Q1b ST `~24779 → 12195.2` search-iters/s (`-51%`); Q1a/Q1b/Q2 ratios all roughly doubled. Cohort C++/Rust rates within ±3% (rules out broader toolchain side-effects); the regression is Haskell-only. Root cause: LSE/`rcpc-immo` atomics emitted by `llc-19 -mcpu=apple-m1` execute slower than baseline ARMv8 LL/SC atomics GHC's RTS was tuned against on Docker-on-Apple-Silicon. The deferral now stands on two load-bearing grounds: (a) the original binutils-2.42 assembler rejection (toolchain-fixable), and (b) the Haskell-specific runtime regression from LSE/`rcpc-immo` (not toolchain-fixable from this project's side). `docker/Dockerfile` and `mcts.cabal` reverted to byte-identical pre-`8.19` state. See `phase-8-haskell-performance-parity-closure.md` Sprint `8.19` Closure Notes for the full measurement table. |
| `docker/Dockerfile` aarch64 build path emits baseline ARMv8 instructions while clang/rustc emit ARMv8.5+ | Sprint `8.19`, 2026-05-30 (measured but rejected) | Same root cause as the row above. Sprint `8.19` proved the toolchain shape gap is not recoverable on this hardware: enabling `-mcpu=apple-m1` for GHC's `-fllvm` pipeline produces correct code (Q3/Q4/Q6/Q7 PASS, bit-identical visit payloads) but slower (-51% Haskell-only). The arm64 baseline ARMv8 codegen, while slower in instruction selection than clang/rustc's ARMv8.5+, runs faster overall because GHC RTS atomics are tuned to LL/SC. |
| Backend (v) `Data.Array.ST.readArray`/`writeArray` bounds-check overhead in the `MCTS.Search.Arena` hot path | Sprint `8.18`, 2026-05-30 | `src/MCTS/Search/Arena.hs` swapped all eight read*/add*/set*/allocNode/bulkVisits helpers from `Data.Array.ST.{readArray,writeArray}` to `Data.Array.Base.{unsafeRead,unsafeWrite}` indexed by `fromIntegral nid :: Int`. The arena's callers in `MCTS.Search.UCT` produce indices via `firstChild + i` arithmetic where `0 <= i < numChildren` and the cursor monotonically grows to capacity; indices are provably in-range. Post-change, GHC fully inlines the Arena helpers into the UCT descent path (e.g. `UCT.descend$w` shrinks 456→92 bytes on arm64; no standalone `Arena.addVisitValue` / `readVisits` symbols remain in the binary). Validation: `mcts test all` PASS on both arm64 (Apple Silicon Docker) and amd64 (caledon Linux) hosts; Q3/Q4/Q6/Q7 PASS; `normalized_divergence_score=0.0000`. Focused 3-rep arm64 Q1a ST: 22881.9 → 24705.1 playouts/s (`+7.97%`); amd64 within ±2-4% noise. |
| Sprint 8.15-pattern measured-but-rejected residue for backend (v) `STUArray Float`→`Word32` arena bitcast | Sprint `8.18`, 2026-05-30 (measured but rejected) | Sprint `8.18` Stage 3 changed `arenaValueSum :: !(STUArray s NodeId Float)` to `STUArray s NodeId Word32` with `GHC.Float.{castFloatToWord32,castWord32ToFloat}` bitcasts at the `addVisitValue`/`readValueSum` boundary. Hypothesis: keep load/store on aarch64 in GPR bank instead of NEON bank, converting to FPR only at the `fadd` site. mcts-cross-backend PASS (Word32↔Float roundtrip is bit-identical). Focused 3-rep arm64 Q1a ST: 24705.1 → 24715.9 playouts/s (`+0.04%`, within noise); amd64 -0.4% (within noise). LLVM register-class promotion eliminates the hypothesised GPR↔NEON crossings in practice. Reverted to Sprint `8.18` Stage 1 state. |
| Sprint 8.15-pattern measured-but-rejected residue for backend (v) GHC NCG (`-fasm`) on aarch64 | Sprint `8.18`, 2026-05-30 (measured but rejected) | Sprint `8.18` Stage 5 added `if arch(aarch64) ghc-options: -fasm` to library/executable/benchmark stanzas, switching the GHC backend on aarch64 only (`-fasm` wins over earlier `-fllvm`). mcts-cross-backend PASS (visit counts bit-identical between LLVM and NCG codegen). Focused 3-rep arm64 Q1a ST: 24705.1 → 23853.5 playouts/s (`-3.45%`). GHC's native code generator on aarch64 is not yet competitive with `-fllvm` for our recursion-heavy hot loops. Reverted; `-fllvm` retained on all platforms. |
| Sprint `4.7` Dockerfile gcc/g++ scrub | Sprint 4.7, 2026-05-30 | `docker/Dockerfile`'s explicit apt-get list no longer names `g++` or `gcc`; `build-essential` is retained for `make`/`libc6-dev`/`libstdc++-dev` (it still pulls g++/gcc transitively, but no first-class backend build path depends on either). `ENV CC=gcc CXX=g++` flipped to `clang-19`/`clang++-19` so any image-default tool falls back to clang. `src/MCTS/Prerequisite.hs` dropped the `cxx-gpp` node entirely; the `cpp-legacy`, `cpp-functional`, and `legacy-fixtures` build paths and the `libmcts-cpp-{legacy,functional}-built` shared-lib nodes now name only `cxx-clang19` (+ `llvm-profdata-19` where the PGO+BOLT path runs). Validation: full image rebuild and `mcts test all` PASS. |
| Sprint `6.11` backend (iii) cpp-functional compiler pivot to `clang++-19` | Sprint 6.11, 2026-05-30 | Mirrors Sprint `5.9` on backend (iii). `cpp-functional/Makefile` flipped `CXX := clang++-19`, dropped `-fipa-pta` (clang rejects) and `-fprofile-correction` (GCC-only), added `-fuse-ld=lld`, and gained a `pgo-merge` target that runs `llvm-profdata-19 merge -o $(PGO_DIR)/default.profdata <*.profraw>` for the `-fprofile-use=…/default.profdata` consumption. `src/MCTS/CLI/Build.hs::cppProfileStyleFor` now maps `cpp-functional → CppLlvmProfile` so `cppPgoBoltPlan` drives the LLVM `.profraw` flow for both live PGO+BOLT C++ backends. `cpp-functional/c-abi/mcts_cpp_functional.cc` adds the `__llvm_profile_write_file`/`__llvm_profile_reset_counters` weak-symbol branch alongside the existing `__gcov_*` fallback, gated on `__clang__`. The `g_engine_build_id` slot picks up `used, retain` so clang+LLD+LTO does not GC the `.envelope_build_id` section. `src/MCTS/Prerequisite.hs::prerequisitesForBuild "cpp-functional"` now lists `cxx-clang19` + `llvm-profdata-19`; the `libmcts-cpp-functional-built` shared-lib dep mirrors that change. `test/unit/Main.hs::exerciseCppBuildPlan` asserts the cpp-functional plan drives the `make pgo-merge` step (the legacy `.gcda` bash check is no longer reachable). `test/integration/Main.hs::expectedCompilerId` returns `1` (clang) for `CppFunctional`. |
| Sprint `4.6` backend (i) cpp-legacy compiler pivot to `clang++-19` | Sprint 4.6, 2026-05-30 | `cpp-legacy/Makefile` pinned `CXX := clang++-19` (`:=`, not `?=`, so the Dockerfile's `ENV CXX=g++` could not override before Sprint 4.7 dropped that var). Engine source under `cpp-legacy/legacy-core/` is preserved verbatim per Phase 4 doctrine; only the build harness flipped. `cpp-legacy/c-abi/mcts_cpp_legacy.cc`'s `g_engine_build_id` slot picked up `used, retain` so clang's -O3 cannot constant-fold the `memcpy(..., g_engine_build_id, 32)` read into a `memset(..., 0, 32)` (same Sprint 5.9 fix as cpp-imperative). The `envelope-build-id` target now discovers `llvm-objcopy-19` before falling back to GNU `objcopy` so the post-link patch keeps working under the Sprint 4.7 scrub. `src/MCTS/Prerequisite.hs::prerequisitesForBuild "cpp-legacy"` and `"legacy-fixtures"` swap `cxx-gpp` for `cxx-clang19`; `libmcts-cpp-legacy-built` mirrors that. `test/integration/Main.hs::expectedCompilerId` returns `1` (clang) for `CppLegacy`. Validation: `mcts test mcts-legacy-parity` PASS, Q6 legacy-envelope liveness PASS. |
| Sprint `5.10` PGO+BOLT efficacy reevaluation on clang-built backend (ii) | Sprint 5.10, 2026-05-29 (measured and kept) | The A/B against the Sprint `5.9` clang+PGO+BOLT baseline vs `clang++-19 -O3 -flto -fuse-ld=lld` produced mixed per-cell results. Average lift +1.8% (below the +3% threshold the plan committed to), but the per-cell picture justified an override: Q1a MT8 `+13.8%` (`262,339` vs `230,570` playouts/s) and Q1b MT8 `+7.5%` (`281,209` vs `261,632` search-iters/s) — comfortably above noise — while the four ST/Q2-MT8 cells fell within ±5% (typical run-to-run noise on these primitives, with Q2 at the `0.1` games/s measurement-resolution floor). The MT8 primitive wins justify the ~5 min Dockerfile build cost; the pipeline is retained. The decision is recorded against the Sprint `5.9` clang baseline; if the front-end pivots again or BOLT's layout passes drift, the A/B should be re-run. Doctrine recorded in `documents/engineering/compiler_runtime_tuning.md` backend (ii) section. |
| Sprint `5.9` backend (ii) compiler pivot from `g++` to `clang++-19` + `State`→`FastBoard` collapse | Sprint 5.9, 2026-05-29 | The 2026-05-29 compiler-stack audit found `clang++-19 -O3 -flto` matched or exceeded `g++` with full PGO+BOLT on cpp-imperative. `cpp-imperative/Makefile` flipped `CXX := clang++-19`, dropped `-fipa-pta` (clang rejects) and `-fprofile-correction` (GCC-only), added `-fuse-ld=lld`, and added a `pgo-merge` target that runs `llvm-profdata-19 merge -o $(PGO_DIR)/default.profdata <*.profraw>` for the `-fprofile-use=…/default.profdata` consumption. `src/MCTS/CLI/Build.hs::cppPgoBoltPlan` split on `CppProfileStyle` so (ii) takes the LLVM-merge branch while (iii) keeps the GCC `.gcda` check. `cpp-imperative/engine/state.hpp` deleted; `uint16_t ply_count` inlined into `cpp-imperative/engine/fast_board.hpp::FastBoard` along with `is_terminal(max_plies)` and `terminal_eval()`; `search.cpp`, `search.hpp`, `arena.hpp`, and `c-abi/mcts_cpp_imperative.cc` retype `State` → `FastBoard` and drop `state.b.` indirection. `__attribute__((used, retain, section(".envelope_build_id")))` on `g_engine_build_id` keeps the envelope section alive through clang+LLD+LTO. `docker/Dockerfile` adds `libclang-rt-19-dev` (needed by `-fprofile-generate` linking). `src/MCTS/Prerequisite.hs` renames `cxx` → `cxx-gpp` and adds `cxx-clang19` + `llvm-profdata-19` nodes. `test/integration/Main.hs::expectedCompilerId` returns `1` (clang) for `CppImperative`. Validation: `mcts test all` PASS, Q3/Q4/Q6/Q7 PASS, `normalized_divergence_score=0.0000`. Backend (ii) post-pivot vs pre-pivot g++ baseline: Q1a ST `35,853 → 38,532` (`+7.5%`), Q1b ST `38,467 → 41,214` (`+7.1%`), Q1a MT8 `264,478 → 262,207` (`−0.9%`), Q1b MT8 `260,887 → 261,003` (`+0.0%`), Q2 ST `1.9 → 2.0` (`+5.3%`), Q2 MT8 `7.1 → 7.7` (`+8.5%`). (ii) is now within `0.88×–1.20×` of (iv) Rust across the six headline cells (was `0.85×–1.10×` pre-pivot); the residual gap is reduced. |
| Backend (v) six-`STUArray` UCT arena residue | Sprint 8.17, 2026-05-29 (measured but rejected) | The proposed `MutableByteArray# s`-backed migration was implemented (single `STUArray s Int Word32` carrying the six SoA fields at named per-field offsets, stride 24 bytes, `castFloatToWord32`/`castWord32ToFloat` for the `valueSum` slot) and compiled cleanly through `mcts test mcts-unit`. Focused native-RNG single-threaded benchmarks recorded a regression vs the Sprint `8.13` six-slab baseline (`Q1a` `22900.8 → 21650.3` playouts/s, `-5.5%`; `Q1b` `23287.1 → 23038.4` search-iters/s, `-1.1%`), so the change was reverted under the Performance Measurement Doctrine and `src/MCTS/Search/Arena.hs` keeps the Sprint `8.13` six-`STUArray` layout. The likely cause is per-field offset arithmetic plus the `Float`/`Word32` cast on `addVisitValue` outweighing the address-register consolidation win. This mirrors the Sprint `8.15` "measured but rejected" pattern; no further (v) optimisation work is scheduled. |
| Backend (iv) `last_visit_*` fields on the search-board struct | Sprint 6.10, 2026-05-29 | `rust/src/c_abi.rs` introduces `RustBoardHandle`, the opaque struct returned by `mcts_rust_new_board`. The handle owns the search-state `MctsRustBoard` plus the `last_visit_*` cache; the search hot path operates on the inner board only. The 169-byte cache no longer propagates through `wall_action_legal` (now mask-additive — no clone), per-rollout copies, or per-expansion child construction. The C ABI symbol set, including `mcts_rust_read_visits`, is unchanged. |
| Backend (iv) per-transition full-state coordinate/wall reversal residue | Sprint 6.10, 2026-05-29 | `rust/src/board.rs::MctsRustBoard` now carries an absolute `SideToMove` enum; `apply_action_unchecked` toggles the field and increments `ply` without reversing wall bitmaps or swapping pawn coordinates. `flipped()`, `apply_action_flip`, and `*self = self.flipped()` are removed from the hot path. Q3 visit-payload bit-equality is preserved (`mcts test mcts-cross-backend` passed; `mcts test all` `normalized_divergence_score=0.0000`). |
| Backend (iv) per-wall-candidate `MctsRustBoard` clone in `wall_placement_legal` | Sprint 6.10, 2026-05-29 | `rust/src/board.rs::legal_actions` precomputes `BlockMasks` via `block_masks()` and the wall-candidate loop calls `wall_action_legal(aid, &base)`, which adds the candidate's bits via `add_wall_to_masks` and runs `path_exists_with_masks` against the trial mask. No per-candidate 196-byte board clone. |
| Backend (iv) unidirectional path-existence BFS | Sprint 6.10, 2026-05-29 | `rust/src/board.rs::path_exists_with_masks` now runs two simultaneous `u128` frontiers (from the start cell and from the goal row) under the shared `BlockMasks`, returning `true` on the first intersection. Mirrors Sprint 6.9 backend (iii) and Sprint 5.8 backend (ii). Q3 visit payloads remain bit-identical. Focused native-RNG benchmarks recorded backend (iv) `Q1a` ST at `38864.2` playouts/s (from a pre-`6.10` baseline of `19767.0`, `+96.6%`) and `Q1b` ST at `41515.0` search-iters/s (from `20319.6`, `+104.3%`); the aggregate report card recorded backend (iv) at the cohort lead on every primitive metric. |
| Backend (iii) per-transition full-state coordinate/wall flip residue | Sprint 6.9, 2026-05-29 | `cpp-functional/engine/state.hpp` now carries an absolute `SideToMove` field; `apply_action_unchecked` toggles the field and increments `ply_count` without bit-reversing `walls_h`/`walls_v` or swapping pawn coordinates. The legacy `flipped_after_move()` helper, `reverse_bits64()`, and `child_after_action()` were removed. Q3 visit-payload bit-equality is preserved (`mcts test mcts-cross-backend` passed; `mcts test all` `normalized_divergence_score=0.0000`). |
| Backend (iii) per-wall-candidate `State` copy and inline mask recomputation in `wall_action_legal` | Sprint 6.9, 2026-05-29 | `cpp-functional/engine/state.hpp::legal_actions` precomputes `BlockMasks` once via `block_masks()` and the wall-candidate loop calls `wall_action_legal(action_id, base_masks)`, which runs `add_wall_to_masks` plus `path_exists_with_masks` against the trial mask. No per-candidate `State` copy and no inline mask reconstruction on the hot path. |
| Backend (iii) full-state embedded `UctNode` | Sprint 6.9, 2026-05-29 | `cpp-functional/engine/arena.hpp::UctNode` now stores only `parent_idx`, `first_child_idx`, `n_children`, `action_id`, `visit_count`, `q_sum`, `expanded`, `terminal`. `cpp-functional/engine/search.cpp::descend_iterative` materializes `State` on the descent stack via `apply_action_unchecked` and a fixed-capacity `std::array<uint32_t, 256> path` for backprop, mirroring the backend (ii) action-only arena. |
| Backend (iii) unidirectional path-existence BFS | Sprint 6.9, 2026-05-29 | `cpp-functional/engine/state.hpp::path_exists_with_masks` now runs two simultaneous `unsigned __int128` frontiers (from the start cell and from the goal row) under the shared `BlockMasks`, returning `true` on the first intersection. Q3 visit payloads remain bit-identical. |
| Backend (iii) C++ steelman flag/BOLT scrub parity gap | Sprint 6.9, 2026-05-29 | `cpp-functional/Makefile` now appends `-fno-stack-protector -fno-rtti -fipa-pta` to `CXXFLAGS` and extends both BOLT optimize invocations (`bolt-bench-optimize`, `bolt-instr-optimize`) with `-split-functions -split-strategy=cdsplit -reorder-functions=cdsort -icf=1` on top of `-reorder-blocks=ext-tsp`. The Dockerfile-owned `cppPgoBoltPlan` rebuilt and trained the canonical `libmcts_cpp_functional.so` without harness changes. Focused native-RNG benchmarks recorded backend (iii) `Q1a` ST at `35583.3` playouts/s (from a pre-`6.9` baseline of `18705.0`) and `Q1b` ST at `37702.6` search-iters/s (from `19075.9`); the aggregate report card recorded backend (iii) at the cohort lead alongside backend (ii). |
| Backend `(ii)` wall-legality path-check residue | Sprint 5.8, 2026-05-29 | `cpp-imperative/engine/fast_board.hpp::path_exists_with_masks` now runs a bidirectional bit-parallel BFS — expanding outward from the pawn cell and inward from the goal row, returning true on intersection — instead of the prior unidirectional 128-bit BFS. The `bool` return contract is preserved (the post-`5.8` `mcts test all` run recorded `normalized_divergence_score=0.0000` and Q3/Q4/Q6/Q7 PASS, confirming bit-identical visit payloads). The two-player bitsliced wavefront and the `unsigned __int128` codegen audit named in the residual-squeeze review remain deferred follow-ons not scheduled into Sprint `5.8`. |
| Backend `(ii)` `UctNode` cache-line padding residue | Sprint 5.8, 2026-05-29 | `cpp-imperative/engine/arena.hpp::UctNode` no longer carries `alignas(kCacheLine)`. The constant remains documented for any future multi-thread introduction. The arena `reserve_nodes` formula at `search.cpp:247` was reviewed under the same deliverable and kept unchanged: `1 + root_actions.size + sims * kMaxLegalActions` is the correct upper bound because each `descend_iterative` triggers at most one `expand` call which adds up to `kMaxLegalActions = 16` children in one shot, and the `vector::reserve` capacity does not fault pages until `reserve_children` actually writes. The `arena.hpp:42` docblock describes the bound honestly. |
| Backend `(ii)` compiler/linker flag scrub residue | Sprint 5.8, 2026-05-29 | `cpp-imperative/Makefile` now appends `-fno-stack-protector -fno-rtti -fipa-pta` to the C++ steelman flag set and extends the BOLT optimize invocations with `-split-functions -split-strategy=cdsplit -reorder-functions=cdsort -icf=1` on top of the existing `-reorder-blocks=ext-tsp`. The flag-name correction from `hfsort+`/`safe` to `cdsort`/`1` was applied during validation when LLVM 19's BOLT rejected the legacy syntax with `'safe' is invalid value for boolean argument! Try 0 or 1`; the doctrine doc and source comments record the reason. `documents/engineering/compiler_runtime_tuning.md` C++ steelman flag block and BOLT subsection are updated to match. |
| Verdict-as-closure-gate doctrine residue | Sprint 8.15, 2026-05-28 | The prior doctrine required Haskell to beat `HASKELL_PARITY_TOLERANCE = 0.05` against backend `(ii)` for `mcts test all` to exit 0, treating a measured `Shortfall` as a project failure even when every backend was fully optimised. Sprint `8.15` landed the measurement-vs-invariant reframe across `src/MCTS/ReportCard.hs`, `src/MCTS/CLI/Test.hs`, `test/unit/Main.hs`, `documents/engineering/compiler_runtime_tuning.md` (renamed § Parity Tolerance → § Performance Measurement Doctrine), `documents/engineering/{benchmark_metrics.md,unit_testing_policy.md,semantic_parity_contract.md}`, `DEVELOPMENT_PLAN/{README.md,00-overview.md,phase-8-haskell-performance-parity-closure.md,development_plan_standards.md,system-components.md}`, `README.md`, and `cabal.project`. Q1/Q2/Q5 are now honest measurements (`Within parity band` / `Trails parity band by N%`); the closure gate is the apples-to-apples invariants Q3/Q4/Q6/Q7 plus a non-`EvidencePending` measurement. Validated 2026-05-28 with `mcts test mcts-unit` (29/29 PASS), `mcts check-code` (PASS), `mcts test all` (exit 0, `Verdict: Trails parity band by 52.3%`, Q3/Q4/Q6/Q7 PASS), `mcts docs check` (PASS), and `git diff --check` (clean). |
| Backend `(ii)` child-board and full-state tree hot-path residue | Sprint 5.7, 2026-05-28 | `cpp-imperative/engine/fast_board.hpp`, `state.hpp`, `arena.hpp`, and `search.cpp` now use fixed-capacity action-id generation, absolute side-to-move board state, action-only tree nodes, and per-generation wall block masks instead of child-board generation, full-board flips, full-state tree snapshots, and repeated wall/path reconstruction. |
| Backend `(ii)` C ABI trusted-search allocation/replay residue | Sprint 5.7, 2026-05-28 | `cpp-imperative/c-abi/mcts_cpp_imperative.cc` keeps external `apply_action` validating while `search_move`, `recompute_move`, and `select_uct_move` apply trusted chosen moves through internal unchecked transitions and fixed visit buffers. |
| Backend `(ii)` profile-training representativeness after kernel rewrite | Sprint 5.7, 2026-05-28 | The Dockerfile-owned `mcts build cpp-imperative` path rebuilt successfully after the kernel rewrite, trained PGO/BOLT on the bounded Q1a/Q1b/Q2 profile suite, installed the canonical bolted shared library, and smoked it before validation consumed it. |
| Rust hot-path structural residue | Sprint 6.8, 2026-05-28 | `rust/src/board.rs` uses bit-parallel `u128` wavefront path checks and fixed-capacity action buffers; `rust/src/search.rs` reserves the child-bound arena shape and reduces expansion clone churn; `rust/src/c_abi.rs` reads visit vectors from board-handle-local cache state instead of a global synchronized map. Focused terminal-playout/search-iteration benchmarks and Q3/Q6 verification gates passed through Compose. |
| Divergence threshold renderer/comment residue | Sprint 7.11, 2026-05-28 | `src/MCTS/ReportCard.hs` renders a normalized divergence score derived from the `visit/move` matrix, JSON exposes `normalized_divergence_score`, `test/unit/Main.hs` constructs a non-zero matrix to prove the score is not hard-coded, and `mcts-semantic-parity` supplies the Q7 semantic-parity gate. |
| Stale README authority citations | Sprint 0.4, 2026-05-27 | README remains operator-facing and reference-only. Doctrine scope now points to `DEVELOPMENT_PLAN/00-overview.md`; transcript wire-format width, report-card rendering, FFI, determinism, and tuning citations point to governed engineering docs or local implementation contracts instead of treating README as the source of truth. |
| Generated `bench rollouts` random-rollout summary | Sprint 1.12, 2026-05-27 | `src/MCTS/CLI/Spec.hs` and `src/MCTS/Generated/Sections.hs` describe `mcts bench rollouts` as a legacy played-game benchmark. Generated command docs and the command matrix are regenerated from those sources, and `mcts-unit` asserts the stale random-rollout wording does not return. |
| Missing root CLI doctrine target | Sprint 0.3, 2026-05-27 | Restored `HASKELL_CLI_TOOL.md` as the root authoritative CLI doctrine, kept root guidance docs, `DEVELOPMENT_PLAN/`, governed docs, and source comments on the existing doctrine topology, and made every `HASKELL_CLI_TOOL.md` markdown link resolve again. |
| Print-only report-card shortfalls | Sprint 8.14, 2026-05-27 | Sprint `8.14` temporarily made `mcts test all` return a non-zero exit code for report-card verdicts `Evidence pending` and `Shortfall`, and only exit 0 for `Within tolerance`. Sprint `8.15` superseded that gate with the current Performance Measurement Doctrine: Q3/Q4/Q6/Q7 plus a non-`EvidencePending` measurement gate closure, while `Within parity band` / `Trails parity band by N%` is an informational label. Unit coverage exercises `ReportCard.reportCardPassed`; the accepted Sprint `8.14` aggregate run used `N_PRIM=20_000`, passed Q3/Q4/Q6 and every Cabal stanza, and recorded `Verdict: Within tolerance`. |
| Report-card unaligned text and missing raw backend metrics | Sprint 7.10 | `src/MCTS/ReportCard.hs` now renders fixed-width raw-performance, question-summary, divergence-matrix, and final question-answer tables; `src/MCTS/CLI/Test.hs` measures raw Q1a/Q1b/Q2 rates for every backend slot while retaining Haskell-vs-backend-(ii) verdict semantics; JSON exposes the rows under `raw_performance_metrics`; docs state every report-card term and question. |
| Corrected-backend Haskell parity shortfall | Sprint 8.12, 2026-05-26 | `src/MCTS/Engine.hs`, `src/MCTS/Search/UCT.hs`, `src/MCTS/CLI/Bench.hs`, and `src/MCTS/Driver.hs` now use packed numeric action IDs, direct `legalActionSet`/`applyActionId` hot paths, reusable wall-block masks, strict rollout/terminal loops, and RTS capability pinning for multi-worker benchmark paths. `docker compose run --rm mcts mcts test all` recorded Q1a/Q1b/Q2 within tolerance against corrected backend (ii), Q3/Q4/Q6 PASS, zero live-cohort divergence, and `Verdict: Within tolerance`. |
| Backend (v) Haskell functional-core style follow-up | Sprint 8.13, 2026-05-26 | Haskell keeps the public `legalMoves`/`applyMove` pure boundary while the search hot path uses packed `ActionIds` and numeric transitions aligned with backend (iii)'s compact style and the Sprint `6.8` Rust target. The `ST` arena remains local to search, and transcript action IDs, canonical action ordering, the 12-wall cap, and ply-cap draw semantics are preserved. |
| Runtime Cabal builds in normal validation | Dockerfile Cabal prebuild, 2026-05-27; Q7 stanza update 2026-05-28 | `docker/Dockerfile` now prebuilds the `mcts` executable with tests and benchmarks enabled, installs all six current Cabal test-suite executables including `mcts-semantic-parity` plus the `mcts-criterion` benchmark executable, and builds foreign backends before image publication. `mcts test all` no longer runs a runtime `cabal build all` gate or routes recursive CLI steps through `cabal exec mcts`; `mcts check-code` runs lint/docs/style only, with warning-clean compilation owned by image construction. |
| Backend (iii) legacy-board/text-action hot path | Sprint 6.7, 2026-05-26 | `cpp-functional/engine/state.hpp` now stores compact value-state fields and generates capped numeric legal successors directly; `cpp-functional/engine/search.cpp` uses `std::vector<State>` successor buffers; `cpp-functional/c-abi/mcts_cpp_functional.cc` applies C ABI actions through `try_advance`; `cpp-functional/Makefile` no longer builds the legacy board translation unit; the backend-local legacy `cpp-functional/engine/board.cpp`, `cpp-functional/engine/board.h`, and `cpp-functional/engine/mcts.hpp` copies were removed. Validation passed `mcts-cross-backend`, `mcts-legacy-parity`, `mcts-unit`, and focused `(ii)`/`(iii)` native-RNG performance checks through Compose. |
| Derived played-game simulation-rate column | Sprint 7.8 follow-up, 2026-05-25 | `src/MCTS/CLI/Bench.hs` now renders played-game benchmarks with only `games/s` in text output and `games_per_second` in JSON. Governed metric docs identify terminal playout, search-iteration, and played-game throughput as the only supported benchmark units. |
| External legacy-reproduction headline question | Sprint 7.9, 2026-05-25 | Removed the old report-card question that compared backend (i) against external `MCTS_legacy`; the legacy-envelope liveness/overflow gate is now Q6 and the report card has six questions. `mcts build legacy-fixtures` remains an optional external audit helper with no numbered report-card role. The Q6 report-card self-play liveness budget is `S_LP_SIMS=4`; the old `10_000` budget belonged to the removed external-reproduction evidence shape. |
| PGO/BOLT profile-suite metric proxy | Sprint 8.11, 2026-05-24 | `src/MCTS/CLI/Build.hs` now trains C++ and Rust PGO/BOLT profiles with terminal playout primitives, search-iteration primitives, legacy played-game rollout batches, and self-play batches. `docker compose run --rm --build mcts mcts test all` validated the aggregate Dockerfile rebuild and refactored report-card rerun end to end, recording Q1a/Q1b/Q2/Q5 unit-aware evidence and `Verdict: Within tolerance` for the then-current backend (ii) artefact. Sprint `5.6` later made that report-card evidence historical. |
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
| Fallback-backed parity report-card evidence | Sprint 8.3, 2026-05-23 | The 2026-05-21 amd64 report card remains historical audit evidence only. `docker compose run --rm --build mcts mcts test all` refreshed the report card against fail-closed Dockerfile PGO/BOLT artefacts and recorded Q1 ST 0.05x, Q1 MT8 0.45x, Q2 ST 0.06x, Q2 MT8 0.22x, Q5 Haskell 0.98x, Q5 C++ (ii) 3.70x, zero live-cohort divergence, Q6 PASS, and verdict `Within tolerance`. Sprint `8.10` later superseded this with bounded-profile historical evidence. |
| C++ PGO/BOLT fail-open artefact copying | Sprint 5.3, 2026-05-23 | `cpp-imperative/Makefile`, `cpp-functional/Makefile`, and `src/MCTS/CLI/Build.hs` now require non-empty BOLT `.fdata`, surface `llvm-bolt` diagnostics, use LLVM objcopy for BOLT-produced shared objects, and smoke the installed bolted C++ canonical libraries during the Dockerfile build. |
| Rust BOLT PGO-only fallback install | Sprint 6.4, 2026-05-23 | `src/MCTS/CLI/Build.hs` now requires Rust profraw/profdata, BOLT `.fdata`, a bolted cdylib, LLVM objcopy envelope patching, and a final canonical Rust smoke; no PGO-only cdylib is copied to the supported load name when BOLT fails. |
| Runtime backend builds in normal validation | Dockerfile backend-build migration, 2026-05-22 | `docker/Dockerfile` now invokes `mcts build cpp-legacy`, `mcts build cpp-imperative`, `mcts build cpp-functional`, and `mcts build rust` during image construction; `mcts test all` and `mcts test parity-anchor` no longer rebuild foreign backend artefacts at runtime. |
| Generated-section metadata overclaim | Sprint 1.10, 2026-05-21 | `mcts docs check` now verifies governed-doc `**Generated sections**:` metadata against physical marker pairs and the `GeneratedSectionRule` registry; fenced Markdown examples are ignored as examples, not real markers. |
| `check-code` stage-order drift | Sprint 1.10, 2026-05-21 | `mcts check-code` now runs the documented lint/docs/style sequence once per stage; validation output contains a single generated-doc check in the lint phase. Dockerfile image construction owns warning-clean compilation. |
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
| Measured Q1-Q6 report-card evidence | Sprint 7.3 / Sprint 8.14 evidence closure, updated 2026-05-27 | `docker compose run --rm mcts mcts test all` passed against the corrected backend (ii) on 2026-05-27, recording Q1a terminal-playout ST 0.72x and MT8 0.85x, Q1b search-iteration ST 0.67x and MT8 0.67x, Q2 played-game ST 0.59x and MT8 0.68x, Q5 Haskell search-iteration scaling 7.32x, Q5 C++ (ii) search-iteration scaling 7.32x, Q5 Haskell self-play scaling 3.42x, Q5 C++ (ii) self-play scaling 3.92x, zero live-cohort divergence, Q3/Q4/Q6 PASS, all Cabal stanzas PASS, and verdict `Within tolerance`. The 2026-05-26 Sprint 8.12, 2026-05-24 Sprint 8.11, and 2026-05-25 Sprint 7.9 rows remain historical against older sample, artefact, or metric shapes. |
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
