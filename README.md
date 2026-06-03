# MCTS

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: AGENTS.md, CLAUDE.md, HASKELL_CLI_TOOL.md, DEVELOPMENT_PLAN/README.md, DEVELOPMENT_PLAN/00-overview.md, DEVELOPMENT_PLAN/system-components.md, DEVELOPMENT_PLAN/phase-0-planning-documentation.md, DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, DEVELOPMENT_PLAN/phase-2-transcript-codec-and-determinism.md, DEVELOPMENT_PLAN/phase-3-haskell-engine.md, DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md, DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md, DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md, DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md, DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md, documents/documentation_standards.md, documents/engineering/README.md, documents/engineering/backend_ffi_contract.md, documents/engineering/backend_style_contract.md, documents/engineering/benchmark_metrics.md, documents/engineering/cli_command_surface.md, documents/engineering/code_quality.md, documents/engineering/compiler_runtime_tuning.md, documents/engineering/determinism_contract.md, documents/engineering/haskell_code_guide.md, documents/engineering/transcript_format.md, documents/engineering/unit_testing_policy.md
**Generated sections**: none

> **Purpose**: Operator-facing project intent, supported entrypoint, backend cohort summary, and links to the authoritative plan and engineering contracts.

MCTS is a high-performance Monte Carlo Tree Search runtime for the Corridors board game. The current proof of concept is rollout-evaluated MCTS: one Haskell CLI drives five backend implementations so the native Haskell engine can be measured against a maximally optimised C++ baseline while the cohort stays deterministic inside a documented envelope. The hypothesis the cohort tests is whether pure Haskell — with no production GHC equivalent to GCC/Clang `-fprofile-use` — can match maximally-optimised C++ on Quoridor MCTS; the honest answer (whether yes or no) is the project deliverable, provided every steelman backend is fully optimised and the apples-to-apples invariants Q3/Q4/Q6/Q7 in [Performance Measurement Doctrine](documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine) hold.

The long-term research direction is AlphaZero-style ANN evaluation, but this repository's current plan ends at a recorded rollout-MCTS measurement under those conditions. The execution-ordered plan is [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md).

## Supported Workflow

All build, run, validation, formatting, linting, documentation-generation, test, benchmark, and backend-build work enters through the root Compose service:

```bash
docker compose run --rm mcts mcts <command>
```

Do not use host `cabal`, `cargo`, `cmake`, `make`, `fourmolu`, `hlint`, repository shell wrappers, `docker compose up`, or `docker compose exec` as project workflows. The pinned container owns GHC, Cabal, LLVM/BOLT, Rust, style tools, the prebuilt Cabal component cache, and the foreign backend shared libraries.

The Docker image build compiles the `mcts` executable with tests and benchmarks enabled, installs all Cabal test-suite executables, installs the `mcts-criterion` benchmark executable, and produces the four foreign backend shared libraries before the image is published. After the image is built, ordinary `mcts` runtime, lint, docs, test, verify, inspect, play, and benchmark commands should execute from image-local artefacts without compiling or linking on the fly. If a non-build command prints Cabal `Building...`, `Configuring...`, or `Linking...` output, treat the image as stale or incorrectly prewarmed and rebuild it with `--build`.

## Backend Cohort

| # | Backend | Identifier | Role |
|---|---------|------------|------|
| (i) | C++ legacy port | `cpp-legacy` | Verbatim compatibility port of `MCTS_legacy`; Q6 legacy-envelope evidence only, not the performance ceiling. |
| (ii) | C++ imperative steelman | `cpp-imperative` | Maximally optimised C++ performance ceiling. Sprint `5.7` closed the remaining hot-path steelman work: action-id successor generation, absolute side-to-move board state, action-only/SoA tree storage, reusable wall-block masks, internal trusted apply/cache paths, and representative PGO+BOLT training. Sprint `5.8` closed the residual squeeze: bidirectional wall-legality BFS, `UctNode` cache-line-padding removed, additive `-fno-stack-protector -fno-rtti -fipa-pta`, and extended BOLT `-split-functions -split-strategy=cdsplit -reorder-functions=cdsort -icf=1`. Visit-payload contract and C ABI unchanged (`normalized_divergence_score=0.0000` in the Sprint `8.16` rebaseline). |
| (iii) | C++ functional-core | `cpp-functional` | Functional-core C++23 steelman under the same optimisation stack as (ii), using compact value-state search, numeric actions, direct capped legal generation, and the shared style followed by (iv) and (v). Sprint `6.9` closed the remaining backend-(ii) hot-path shape gap inside the functional-core boundary: absolute `SideToMove`, reusable `BlockMasks` precomputed once per `legal_actions`, bidirectional bit-parallel BFS in `path_exists_with_masks`, action-only `UctNode` with `State` materialized on the descent stack, and the Sprint `5.8` C++ flag/BOLT scrub on `cpp-functional/Makefile`. Backend (iii) now matches (and marginally exceeds) backend (ii) on Q1a/Q1b primitive throughput while Q3/Q4/Q6/Q7 remain bit-identical (`normalized_divergence_score=0.0000`). |
| (iv) | Rust | `rust` | Cross-language systems baseline using a compatible functional-core value-state and FFI/search/recompute contract; Sprint `6.8` aligned its hot path with `(iii)`/`(v)` using bit-parallel path checks, stack action buffers, child-bound arena sizing, and board-local visit caching. Sprint `6.10` closed the remaining backend-(ii) hot-path shape gap by relocating the `last_visit_*` cache off `MctsRustBoard` onto the opaque `RustBoardHandle` declared in `rust/src/c_abi.rs` (per the style contract), adopting absolute `SideToMove`, the reusable `BlockMasks` additive pattern, bidirectional `u128` BFS in `path_exists_with_masks`, the action-only `Vec<Node>` arena in `tree.rs`, and an inlining/cold-path audit. Backend (iv) now leads the cohort on every primitive metric while Q3/Q4/Q6/Q7 remain bit-identical (`normalized_divergence_score=0.0000`). |
| (v) | Haskell | `haskell` | Native in-process target backend; pure API surface, compact value board, direct slot-based path checks, and `ST`-arena internals. Sprint `8.17` closed with the `MutableByteArray# s` arena migration **measured but rejected** (single-buffer `STUArray s Int Word32` with named per-field offsets regressed focused Haskell rates by `Q1a -5.5%` / `Q1b -1.1%` ST against the Sprint `8.13` six-slab baseline, reverted under the Performance Measurement Doctrine) and the descent/rollout `INLINE` audit recorded as no-op. Sprint `8.18` closed the cabal-only arm64 recovery ceiling at `+4-8%` Q1a ST on arm64 with `Data.Array.Base.unsafeRead`/`unsafeWrite` for the eight Arena read/write helpers (amd64 flat; Q3/Q4/Q6/Q7 bit-identical); four other Stage-2..5 candidates ledgered. Sprint `8.19` closed 2026-05-30 with the Dockerfile-level aarch64 mcpu unblock **measured but rejected**: the wrapper-routed `-mcpu=apple-m1` worked at the code-generation level (Q3/Q4/Q6/Q7 PASS, `normalized_divergence_score=0.0000`) but regressed Haskell Q1b ST by `-51%` on Docker-on-Apple-Silicon because LSE / `rcpc-immo` atomics execute slower than baseline ARMv8 LL/SC atomics GHC's RTS was tuned against; cohort C++/Rust unaffected (rules out side-effects). Reverted to byte-identical pre-`8.19` toolchain. The aarch64 mcpu deferral now stands on two load-bearing grounds (assembler limitation + Haskell-runtime regression). See [DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md](DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md) Sprint `8.19` and [compiler_runtime_tuning.md → Sprint 8.19 aarch64 mcpu resolution](documents/engineering/compiler_runtime_tuning.md#sprint-819-aarch64-mcpu-resolution). |

Backends (i)..(iv) are loaded through stable C ABIs from canonical shared libraries produced during the Dockerfile build. Backend (v) runs in-process. Rust now uses the same functional-core hot-path shape as `(iii)` and `(v)` while remaining a raw-performance context row rather than the Q1/Q2 verdict target. The authoritative backend, style, and FFI details live in [backend_style_contract.md](documents/engineering/backend_style_contract.md), [backend_ffi_contract.md](documents/engineering/backend_ffi_contract.md), and [compiler_runtime_tuning.md](documents/engineering/compiler_runtime_tuning.md). Sprint `5.7` kept the `(ii)` public ABI stable while replacing internal search-kernel and profile-training paths.

## Benchmark Metrics

The project uses three distinct performance units:

| Metric | Unit | Meaning |
|--------|------|---------|
| Terminal playout throughput | `playouts/s` | Random trajectory from a board to terminal/cap; no MCTS tree. |
| Search-iteration throughput | `search-iters/s` | One UCT iteration: select, expand/evaluate, rollout if needed, backprop. |
| Played-game throughput | `games/s` | Complete self-played game with a configured search budget at each real move. |

Current `mcts bench rollouts` is a legacy command name: it measures played-game
throughput with one search iteration per move, not terminal `playouts/s`.
Played-game benchmark output uses `games/s` only. The metric taxonomy and Q1-Q7 mapping live in
[benchmark_metrics.md](documents/engineering/benchmark_metrics.md).

The post-Sprint-`5.8` `docker compose run --rm --build mcts mcts test all`
under the [Performance Measurement Doctrine](documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine)
exits 0 with all four apples-to-apples invariants Q3/Q4/Q6/Q7 PASS, all six
Cabal stanzas PASS, zero live-cohort divergence
(`normalized_divergence_score=0.0000`), and the labelled measurement
`Verdict: Trails parity band by 57.1% (measurement recorded; see PGO
Asymmetry in compiler_runtime_tuning.md)`. Backend `(ii)`/Haskell ratios
against the fully steelmanned-and-residual-squeezed Sprint `5.8` `(ii)`
target: Q1a `1.51x` ST / `1.50x` MT8, Q1b `1.53x` ST / `1.56x` MT8, Q2
`1.41x` ST / `1.57x` MT8; Q5 scaling Haskell search `7.16x` vs backend
`(ii)` search `7.31x`, Haskell self-play `3.28x` vs backend `(ii)`
self-play `3.66x`. The earlier Sprint `8.15` post-`5.7` measurement
(Q1a `1.42x`/`1.51x`, Q1b `1.45x`/`1.52x`, Q2 `1.35x`/`1.48x`, verdict
`52.3%`) is historical against the pre-`5.8` `(ii)` artefact; the
~5-percentage-point widening reflects the ~2–6% Sprint `5.8`
improvement on backend `(ii)`, not a Haskell regression.

The Sprint `8.16` numbers above are the pre-cohort-shape-audit
measurement. On 2026-05-29 the functional-cohort shape audit reopened
Phase `6` for Sprints `6.9` (backend (iii)) and `6.10` (backend (iv))
and Phase `8` for Sprint `8.17` (backend (v)); see
[DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md) → Closure Status
and the matching phase docs. After all three sprints closed the same
date, the aggregate `mcts test all` recorded the post-`8.17` cohort
raw rates `cpp-imperative ~35990` ST / `~225800` MT8 playouts/s,
`cpp-functional ~35720` ST / `~245470` MT8, `rust ~38940` ST /
`~256720` MT8, `haskell 23037.9` ST / `137348.9` MT8 — cohort ranking
`rust ≥ cpp-functional ≈ cpp-imperative > haskell`, Q3/Q4/Q6/Q7 PASS,
`normalized_divergence_score=0.0000`, verdict `Trails parity band by
62.7%` (informational). Closing the (iii)/(iv) permitted hot-path
shape gap inverted Haskell's pre-`6.9` lead over the foreign cohort,
and Sprint `8.17`'s `MutableByteArray#` arena migration was reverted
as `measured but rejected` (focused Haskell rates regressed against
the Sprint `8.13` six-slab baseline). The remaining Haskell shortfall
sits in the documented PGO-asymmetry band.

Sprint `8.18` (2026-05-30) closes the cross-platform recovery
investigation. The cross-host A/B measurement (Apple Silicon Mac
Docker arm64 vs caledon x86_64 amd64, same `docker/Dockerfile`, same
GHC 9.14.1, same LLVM 19) shows the cohort-vs-Haskell gap is
**dramatically wider on arm64 than on amd64**: post-Sprint-`8.18`
`mcts test all` records `Trails parity band by 85.6%` on arm64
(Q1a `1.60x` ST / `1.86x` MT8, Q1b `1.63x` / `1.69x`, Q2 `1.49x` /
`1.68x`) but only `29.5%` on amd64 (Q1a `1.25x` ST / `1.28x` MT8,
Q1b `1.25x` / `1.06x`, Q2 `1.14x` / `1.29x`; **Q5 MT8 search
scaling Haskell `6.36x` beats backend `(ii)` `5.38x`**). Both
exit 0 with Q3/Q4/Q6/Q7 PASS and
`normalized_divergence_score=0.0000`. One Haskell-source change
accepted (`src/MCTS/Search/Arena.hs` →
`Data.Array.Base.unsafeRead`/`unsafeWrite` for all eight read/write
helpers, eliminating per-access bounds-check insns; +4-8% Q1a ST
arm64 focused-bench gain, amd64 flat). Four other recovery attempts
ledgered as measured-but-rejected or asm-skipped: `-mcpu=apple-m1`
toolchain unblock (binutils-2.42 rejects LSE atomics; out of cabal
scope, needs Dockerfile work), `Float`→`Word32` bitcast in arena
(LLVM register-class promotion eliminates the hypothesised GPR↔NEON
crossings), hand-written rollout worker-wrapper (asm shows GHC's
auto-wrapper already produces the optimal calling convention), and
GHC NCG `-fasm` on aarch64 (-3.45% vs `-fllvm`). See
[`bench-profiles/diagnosis-final.md`](bench-profiles/diagnosis-final.md)
for the cross-platform investigation and
[`bench-profiles/stage{1..5}-result.md`](bench-profiles/)
for per-stage accept/reject records. **The 65-percentage-point
arm64-specific portion of the gap identified in the investigation is
characterised as ~5pp recovered by Stage 1 + ~60pp blocked on the
binutils/assembler issue (Dockerfile-level work).**

Sprint `8.19` closed 2026-05-30 with the Dockerfile-level aarch64
mcpu unblock **measured but rejected**. The wrapper-routed
Approach A (`docker/Dockerfile` installs
`/usr/local/bin/clang-19-aarch64-apple-m1` wrapping `clang-19
-mcpu=apple-m1`; GHC settings patched so both `pgm_c` and `LLVM
llvm-as command` route through the wrapper — the second sed
load-bearing for the `-fllvm` LLVM-assembler stage; cabal
`if arch(aarch64) ghc-options: -optlo-mcpu=apple-m1
-optlc-mcpu=apple-m1`) built cleanly with all closure gates PASS
(Q3/Q4/Q6/Q7, `normalized_divergence_score=0.0000`). **Measurement
rejected:** arm64 `mcts test all` verdict regressed from Sprint
`8.18`'s `85.6%` to `268.7%`; Haskell Q1b ST `~24779 → 12195.2`
search-iters/s (`-51%`); Q1a/Q1b/Q2 ratios all roughly doubled.
Cohort C++/Rust rates within ±3% (rules out broader side-effects);
the regression is **Haskell-only**. Root cause: LSE / `rcpc-immo`
atomics emitted by `llc-19 -mcpu=apple-m1` execute slower than
baseline ARMv8 LL/SC atomics GHC's RTS was tuned against on
Docker-on-Apple-Silicon. `docker/Dockerfile` and `mcts.cabal`
reverted to byte-identical pre-`8.19` state; the Sprint `8.18`
Stage 1 accepted change in `src/MCTS/Search/Arena.hs` remains in
effect. The aarch64 mcpu deferral now stands on two load-bearing
grounds: binutils-2.42 assembler rejection (toolchain-fixable) plus
the Haskell-specific runtime regression (not toolchain-fixable from
this project's side). Further arm64 recovery requires upstream
GHC/LLVM/RTS work outside this project's control. See
[DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md → Sprint 8.19](DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md#sprint-819-dockerfile-level-aarch64-toolchain-unblock-)
and
[compiler_runtime_tuning.md → Sprint 8.19 aarch64 mcpu resolution](documents/engineering/compiler_runtime_tuning.md#sprint-819-aarch64-mcpu-resolution).

Under the reframed doctrine, Q1, Q2, and Q5 are measurement questions and a
Haskell shortfall is recorded honestly with PGO-asymmetry attribution; closure
of `mcts test all` gates on the apples-to-apples invariants Q3, Q4, Q6, Q7
plus a non-pending measurement, not on the `HASKELL_PARITY_TOLERANCE = 0.05`
labelling cutoff. The canonical primitive sample is `N_PRIM=20_000`. The
earlier Sprint `8.14` `Within tolerance` reading against the Sprint `5.6`
`(ii)` artefact, the pre-reframe `Shortfall 0.2678` reading against the
post-`5.7` `(ii)` target, and the Sprint `8.15` `52.3%` reading against the
post-`5.7` `(ii)` target are historical evidence against the pre-`5.8`
artefacts.

Phase 7 Sprint `7.11` adds Q7 semantic parity for `(ii)..(v)`: a
weaker-than-bit-equality gate for game-rule replay compatibility, search
invariants, terminal-board rejection, and a single normalized divergence score.
Q7 does not relax Q3, and it does not include backend `(i)`.

The text report card defines its terms before the evidence block, then renders
three aligned evidence tables in this order: raw backend performance metrics for
every backend slot, the question summary, and the `visit/move` divergence matrix.
The divergence headline reports a single normalized divergence score instead of
empirical threshold pairs. The report ends with an explicit question-answer
summary derived from the observed ratios, scaling values, divergence score, and
gate outcomes. JSON output includes the same raw metric fields under
`raw_performance_metrics` and the score under `normalized_divergence_score`.

## Command Surface

The full generated command reference is [documents/cli/commands.md](documents/cli/commands.md); the command contract is [cli_command_surface.md](documents/engineering/cli_command_surface.md).

The CLI is self-describing through normal introspection. `--help`, `mcts help
<subcommand>`, `mcts commands --json`, generated docs, manpages, completions, and
parse errors expose accepted enum values such as the valid `--backend` identifiers
from the command registry. The owning contract is
[cli_command_surface.md](documents/engineering/cli_command_surface.md#self-describing-cli-contract);
the backend identifiers are listed in the [Backend Cohort](#backend-cohort).

Common operator commands:

```bash
docker compose run --rm mcts mcts commands --tree
docker compose run --rm mcts mcts bench rollouts --backend cpp-imperative,haskell --threading single --rng native --games 1000 --seed 42
docker compose run --rm mcts mcts bench selfplay --backend haskell --rng native --games 100 --seed 42 --sims 10000
docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500
docker compose run --rm mcts mcts verify legacy-parity selfplay --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --games 2 --seed 42 --sims 4
docker compose run --rm mcts mcts play --backend haskell --side hero --rng native --max-plies 200
docker compose run --rm mcts mcts inspect list
docker compose run --rm mcts mcts check-code
```

`mcts build cpp-legacy`, `mcts build cpp-imperative`, `mcts build cpp-functional`, and `mcts build rust` are Dockerfile-owned build leaves. The Dockerfile also prebuilds and installs the Cabal test and benchmark executables so later validation runs consume image-local artefacts instead of compiling test stanzas on demand. Refreshing any build artefact normally means rebuilding the Compose image:

```bash
docker compose run --rm --build mcts mcts test all
```

## Determinism

The project separates performance runs from logical-equivalence verification:

- `--rng native` is for benchmarks and play. Each backend uses its own deterministic native RNG path; cross-backend bit equality is not asserted.
- `--rng cpp` is for verification. The Q3 cohort `(ii)..(v)` consumes the shared C++ verification seed contract and compares canonical visit payloads.
- Backend `(i)` keeps legacy terminal/search semantics and is covered by the dedicated `verify legacy-parity` envelope instead of the Q3 equality cohort.
- Q7 semantic parity is a separate `(ii)..(v)` gate for rule-state replay
  compatibility, search invariants, and terminal-board rejection when
  bit-for-bit play is not the right claim.

Transcripts are local operator cache files under `.mcts-cache/` by default. They are content-addressed per backend/game and carry an engine envelope so verify/replay can detect stale binary, compiler, FP, libm, CPU, and architecture drift. The authoritative contracts are:

- [determinism_contract.md](documents/engineering/determinism_contract.md)
- [semantic_parity_contract.md](documents/engineering/semantic_parity_contract.md)
- [transcript_format.md](documents/engineering/transcript_format.md)
- [unit_testing_policy.md](documents/engineering/unit_testing_policy.md)

## Validation

Use the smallest Compose gate that covers the change, then close with the aggregate gate when touching cross-cutting code or docs:

```bash
docker compose run --rm mcts mcts docs check
docker compose run --rm mcts mcts lint files
docker compose run --rm mcts mcts lint docs
docker compose run --rm mcts mcts test mcts-unit
docker compose run --rm mcts mcts check-code
docker compose run --rm --build mcts mcts test all
```

Normal tests do not depend on checked-in generated transcripts, throughput anchors, renderer snapshots, or report-card fixtures. Generated documentation files are the tracked exception and are governed by [documentation_standards.md](documents/documentation_standards.md).

## Authoritative Documents

This README is intentionally reference-only. Exact rules, ownership boundaries, and
evidence snapshots live in the authoritative documents below.

- [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md) — phase order, sprint status, blockers, validation closure, and cleanup ownership.
- [DEVELOPMENT_PLAN/system-components.md](DEVELOPMENT_PLAN/system-components.md) — component inventory.
- [DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md) — compatibility and stale-surface cleanup ledger.
- [HASKELL_CLI_TOOL.md](HASKELL_CLI_TOOL.md) — CLI doctrine.
- [documents/documentation_standards.md](documents/documentation_standards.md) — documentation topology rules.
- [documents/engineering/backend_style_contract.md](documents/engineering/backend_style_contract.md) — functional-core style contract for backends (iii), (iv), and (v).
- [documents/engineering/benchmark_metrics.md](documents/engineering/benchmark_metrics.md) — terminal playout, search-iteration, and played-game metric semantics.
- [documents/engineering/semantic_parity_contract.md](documents/engineering/semantic_parity_contract.md) — Q7 semantic parity and normalized divergence-score contract.
- [documents/engineering/README.md](documents/engineering/README.md) — engineering-document index.
