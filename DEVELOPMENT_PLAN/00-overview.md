# MCTS Development Plan — Overview

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
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
[phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md),
[../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md),
[../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md),
[../documents/engineering/semantic_parity_contract.md](../documents/engineering/semantic_parity_contract.md)
**Generated sections**: none

> **Purpose**: Capture the target architecture, current baseline, doctrine scope,
> hard constraints, and dependency chain that every MCTS phase depends on.

## Vision

The MCTS runtime is the successor to `MCTS_legacy` and must satisfy three properties
simultaneously:

- **Measured honestly against maximally-optimised imperative C++** on the
  refactored POC metric suite: terminal playout throughput, search-iteration
  throughput, and played-game self-play throughput per
  [../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md).
  The bar is not the legacy as it exists today — it is the strongest
  imperative-C++ implementation the project can build using every reasonable
  modern technique (LTO, two-stage PGO, BOLT post-link, `mimalloc`,
  arena-allocated tree nodes, scratch-board rollouts, branch hints). Backend
  (ii) is that ceiling; backend (v) Haskell is measured against it. The
  hypothesis the cohort tests is whether pure Haskell can match that ceiling
  given GHC's lack of a production PGO loop; the honest answer (whether yes or
  no) is the project deliverable, provided every steelman backend is fully
  optimised by its phase-owned closure and the apples-to-apples invariants
  Q3/Q4/Q6/Q7 in
  [../documents/engineering/compiler_runtime_tuning.md → Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine)
  hold. Q1, Q2, and Q5 are measurement questions; a Haskell shortfall under
  these conditions is recorded honestly with PGO-asymmetry attribution and
  does not block closure.
- **Purely functional at the API surface** in its final form, so algorithmic changes
  (search policies, evaluators, prior shaping) are local edits rather than rewrites.
  Internally the Haskell engine is free to use `ST`-monad mutable unboxed arrays as the
  only realistic way to match optimised imperative C++; the local-reasoning property is
  preserved by keeping public types and operations pure. The functional comparison
  cohort `(iii)`, `(iv)`, and `(v)` uses the shared functional-core value-state style in
  [../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md);
  local mutation, compact bitfields, and arenas are allowed, while legacy board graphs
  and text action decoding are not treated as functional-core costs.
- **Deterministic inside the documented envelope.** Same-backend runs are reproducible for
  the same seed, RNG source, and logical inputs; cross-backend bit equality is asserted for
  backends `(ii)..(v)` under `--rng cpp`; backend `(i)` is covered by the legacy-parity
  envelope rather than the Q3 equality cohort (see Hard Constraint 36 below and the
  **Engine Envelope** section in
  [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md)).
  Reproducibility is a first-class invariant, not a debugging aid; the engine envelope
  captured in every transcript lets `inspect replay` and `mcts verify` detect substrate
  drift rather than silently displaying ULP-shifted floats as if they were the
  originator's.

**Long-term horizon (out of scope for this plan).** The project
[../README.md](../README.md) declares an eventual AlphaZero-style ANN evaluation goal.
Phases `0`–`8` own the rollout-based MCTS hypothesis only; no ANN, no learned
evaluator, and no Python ML stack appears on the supported path. The intended
final handoff is a parity-proven five-backend CLI that a successor effort can
inherit without reconstructing C++ or Rust comparison evidence; the current
optimized-C++ parity evidence is refreshed against the Dockerfile build that
fails closed on mandatory PGO+BOLT profile data instead of accepting fallback
artifacts. The historical Sprint `8.10` closure used profile data from the bounded
played-game profile suite in `MCTS.CLI.Build`; Sprint `8.11` extended that suite
with primitive terminal-playout and search-iteration profile runs. Sprint `5.6`
later reopened parity evidence against the corrected backend (ii), making Sprint
`8.11` historical metric-suite evidence; Sprint `8.12` supplied the corrected-target
parity measurement and Sprint `8.14` closed the report-card exit-code gate (the gate
semantics it established were later reframed by Sprint `8.15` so the gate now sits on
the apples-to-apples invariants Q3/Q4/Q6/Q7 plus a non-pending measurement). Sprint
`5.7` then strengthened backend `(ii)`, Sprint `8.15` closed on 2026-05-28 with the
measurement-vs-invariant doctrine reframe and the post-`5.7` Haskell rebaseline, and
Sprints `5.8`/`8.16`, `5.9`/`5.10`, and `6.9`/`6.10`/`8.17` closed on 2026-05-29.
Sprints `4.6` (backend (i) cpp-legacy compiler pivot to `clang++-19`),
`6.11` (backend (iii) cpp-functional compiler pivot + LLVM PGO migration),
and `4.7` (Dockerfile `gcc`/`g++` scrub + `ENV CC`/`CXX` flip to clang
defaults) then closed on 2026-05-30, reaching the doctrine end state where
all three C++ backends build with `clang++-19` and the `cxx-gpp`
prerequisite node is gone.

## Current Handoff Status

Documentation topology is closed again: Phase `0` Sprint `0.3` restored
`HASKELL_CLI_TOOL.md` as the root authoritative CLI doctrine on 2026-05-27,
keeping the existing root guidance, plan-suite, governed engineering-doc, and
source-comment citations link-complete. This did not reopen backend
implementation phases on their owned surfaces.
Sprint `0.4` then reclosed the remaining README-authority citation drift: README is
reference-only, this overview owns the doctrine-scope split, and governed engineering docs
own transcript wire-format, report-card rendering, FFI, determinism, and tuning details.
Sprint `1.12` reclosed generated command-summary wording so `mcts bench rollouts` is
described as the legacy played-game benchmark implemented by the code, not as terminal
random-rollout throughput.
Phase `1` reopened on 2026-06-03 for Sprint `1.13` after operator use found that the
CLI was not yet fully self-describing: accepted backend values were absent from
`mcts play --help`, `mcts help <path>` was pointer-only, and invalid enum parse errors
omitted the accepted values. Sprint `1.13` reclosed the same day with choice-aware
metadata, focused help, generated docs, enriched JSON, and completions; it did not
reopen backend, transcript, verification, or performance surfaces. The operator-facing
contract is
defined in
[cli_command_surface.md → Self-Describing CLI Contract](../documents/engineering/cli_command_surface.md#self-describing-cli-contract).
Phase `1` reopened again on 2026-06-04 for Sprint `1.17` after leaf-command
descriptions still leaned on terse summaries, with `mcts play` as the concrete
operator failure: `BACKEND` metavars needed explicit backend identifiers, and
help/generated docs needed to explain human-vs-AI side ownership and AI-vs-AI
spectator mode. Sprint `1.17` reclosed the same day with action-oriented registry
descriptions, parser-help text, generated docs, README guidance, and semantic tests.
Phases `2` through `8` remain closed on their owned surfaces.

The 2026-05-19 report card remains useful smoke-baseline audit evidence, and the
2026-05-21 optimized-C++ report-card refresh remains historical evidence against
the then-canonical backend (ii) artefact. Under the 2026-05-22 fail-closed
PGO+BOLT doctrine, that evidence cannot close parity because C++ BOLT produced no
`.fdata` and the build installed a fallback artifact. The 2026-05-23 Dockerfile
build and aggregate report-card run reclosed that gap: C++ and Rust BOLT profiles,
bolted canonical libraries, LLVM objcopy envelope patching, final installed-library
smokes, and Q1/Q2/Q5/Q6 parity evidence are validated against mandatory PGO+BOLT
artefacts.
The five-backend surface is restored: `cpp-legacy`, `cpp-imperative`,
`cpp-functional`, `rust`, and `haskell` are first-class parser/build/verify/FFI
participants.

The 2026-05-21 evidence-surface audit reopened Phases `1`, `2`, `5`, `6`, `7`,
and `8` for focused reclosure. Sprint `1.10` has reclosed generated-doc metadata
and style-policy alignment. Sprint `2.8` has reclosed transcript version
handling, action-domain wording, and sidecar identity. Sprint `5.5` has reclosed
the compact backend (ii) C ABI contract, and Sprint `5.3` has reclosed C++
PGO/BOLT fail-closed behavior. Sprint `6.6` has reclosed backend (iii)/(iv)
ABI and Rust instrumentation wording, and Sprint `6.4` has reclosed the Rust
PGO/BOLT fail-closed build. Sprint `7.6` has reclosed replay/divergence evidence
labels. Sprint `8.9` has reclosed compiler-tuning wording, Sprint `8.3` has
reclosed the report-card refresh against the reclosed build artefacts, Sprint
`8.10` has reclosed the played-game profile-representativeness gate, and Sprint
`8.11` has reclosed the refactored metric-suite rerun. The build harness now
trains Dockerfile-time PGO/BOLT with terminal playout, search-iteration, legacy
played-game rollout, and self-play runs, both single-threaded and MT8, under
native RNG with seeds `42` and `424242`; `MCTS.CLI.Build` pins the exact primitive
counts, played-game counts, ply caps, and self-play simulation budgets.
Phases `3` and `4` remain `Done` on their owned surfaces; Phase `3` Sprint `3.8`
closed the primitive `playouts/s` and `search-iters/s` benchmark leaves on
2026-05-24. Later phases remain valid on historical implementation work within
their scoped surfaces.

The 2026-05-24 benchmark-metric audit reopened the metric suite because the
then-current Q1/Q2/Q5 report-card rows were played-game measurements under legacy
`rollouts`/`selfplay` labels, not terminal playout or search-iteration
measurements. Phase `3` has closed the missing benchmark primitives, Phase `7`
has closed the report-card row split, and Phase `8` Sprint `8.11` closed the
refactored parity rerun against the then-current backend (ii). Sprint `8.12`
has refreshed that evidence against the corrected backend (ii), and the accepted
report-card verdict is `Within tolerance`. Sprint `8.14` closed on 2026-05-27
by making that verdict an exit-code gate and raising `N_PRIM` to `20_000` for
stable primitive MT8 evidence.
Phase `7` Sprint `7.9` revalidated the headline report-card mapping on
2026-05-25: there are six questions, Q6 is the all-five legacy-envelope gate,
and external `MCTS_legacy` reproduction fixtures are optional audit data rather
than a numbered report-card row.
Historical played-game numbers remain audit evidence, not final answers to the
refactored Q1a/Q1b/Q2/Q5 suite.

Sprint `5.6` reclosed Phase `5` on 2026-05-25 after backend (ii) moved from the
legacy board hot path to a compact bitfield board with direct capped move
generation and wavefront escapability checks. Focused rebuilt-image benchmarks
now show backend (ii) outperforming backend (i), as the steelman design requires.
That same correction reopened Phase `8` on the Haskell parity surface: the earlier
`Within tolerance` report-card verdict is historical evidence against the slower
backend (ii), not closure against the corrected C++ ceiling. Sprint `8.12`
reclosed that parity surface on 2026-05-26.

Phase `6` Sprint `6.7` reclosed on 2026-05-26: backend (iii)'s former
legacy-board/text-action path is gone from the hot path and no longer explains
the `(ii)` vs `(iii)` performance gap. Backend (iii) now uses compact
functional-core C++ value state, direct capped numeric legal generation, and the
compact value-state boundary that backend (iv) Rust already had at the API and
FFI level. Sprint `6.8` closed Rust's hot-path structural alignment by replacing
queue-BFS path checks, heap action buffers, under-reserved arena growth, avoidable
board clones, and global visit-cache state with the same shape used by `(iii)` and
`(v)`. Phase `8` Sprint `8.13` is closed after Sprint
`8.12`; backend (v) Haskell now keeps its pure API boundary while its hot search
path follows the same compact numeric action-set transition style as `(iii)` and
the Sprint `6.8` Rust target.
Phase `8` Sprint `8.14` is also closed: `mcts test all` exits non-zero
when the apples-to-apples invariants Q3/Q4/Q6/Q7 fail or the measurement is
`Evidence pending`, and exits successfully when those invariants pass and a
verdict (either `Within parity band` or `Trails parity band by N%`) has been
recorded per
[../documents/engineering/compiler_runtime_tuning.md → Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine).
The verdict-line label itself is informational.
Phase `0` Sprint `0.4` and Phase `1` Sprint `1.12` closed documentation-topology and
generated-text drift after that verdict-gate work. Phase `6` Sprint `6.8` and
Phase `7` Sprint `7.11` close the remaining reopened behavior surfaces: Rust
hot-path alignment, Q7 semantic parity for `(ii)..(v)`, removal of divergence
threshold report-card wording, and one normalized divergence score derived from the
`visit/move` matrix. Q3/Q4/Q6 and Phase `8` performance-parity evidence remain
valid for their scoped claims.

The 2026-05-28 backend `(ii)` steelman audit reopened Phase `5` for Sprint `5.7`
without reopening the closed functional implementations. Sprint `5.7` has now
closed the remaining imperative-kernel residue: action-id legal generation without
materializing every child board, absolute side-to-move state instead of per-child
board flips, action-only tree storage, reusable wall block masks, trusted internal
apply/visit buffers, and PGO/BOLT training retuned after the kernel rewrite.
Phase `8` closed on 2026-05-28 with Sprint `8.15`: the measurement-vs-invariant
doctrine reframe landed, the apples-to-apples invariants Q3/Q4/Q6/Q7 became the
sole closure gate per
[../documents/engineering/compiler_runtime_tuning.md → Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine),
and the post-`5.7` `(ii)` rebaseline produced the project's honest empirical
answer: `Verdict: Trails parity band by 52.3%`, recorded with PGO-asymmetry
attribution while every apples-to-apples invariant holds across the cohort.
The Sprint `8.14` `Within tolerance` reading against the pre-`5.7` artefact and
the pre-reframe `Shortfall 0.2678` reading against the post-`5.7` target remain
historical evidence under the prior framing.

The 2026-05-29 backend `(ii)` residual-squeeze audit reopened Phase `5` for
Sprint `5.8` and Phase `8` for Sprint `8.16`; both closed on the same date.
Sprint `5.8` landed bidirectional bit-parallel BFS in
`path_exists_with_masks`, `UctNode` `alignas(kCacheLine)` removed, additive
`-fno-stack-protector -fno-rtti -fipa-pta` on the C++ steelman flag set, and
extended BOLT `-split-functions -split-strategy=cdsplit
-reorder-functions=cdsort -icf=1` (flag names corrected from
`hfsort+`/`safe` mid-validation after LLVM 19's BOLT rejected the legacy
syntax). The D2 reserve-formula tighten was reviewed and rejected because
the existing `1 + root + sims * kMaxLegalActions` upper bound is correct;
the D1 two-player bitsliced wavefront and `unsigned __int128` codegen audit
remain deferred follow-ons not scheduled. Sprint `8.16` recorded the
post-`5.8` Haskell-vs-`(ii)` rebaseline: Q1a `1.51x` ST / `1.50x` MT8, Q1b
`1.53x` ST / `1.56x` MT8, Q2 `1.41x` ST / `1.57x` MT8, Q5 scaling Haskell
search `7.16x` vs C++ `(ii)` search `7.31x`, Haskell self-play `3.28x` vs
C++ `(ii)` self-play `3.66x`; `Verdict: Trails parity band by 57.1%`;
Q3/Q4/Q6/Q7 PASS and `normalized_divergence_score=0.0000`. The increase
from 52.3% to 57.1% is the (ii)-ceiling raise from the ~2–6% Sprint `5.8`
improvement, not a Haskell regression. Sprints `5.1`–`5.7` and `8.1`–`8.15`
remain closed for their delivered surfaces. See
[README.md](README.md) → Closure Status for the full closure narrative.

The 2026-05-29 functional-cohort shape audit then reopened Phase `6` for
Sprints `6.9` and `6.10`, and Phase `8` for Sprint `8.17`. The audit
identified that backends (iii), (iv), and (v) do not yet adopt every
backend-(ii) hot-path technique permitted by
[../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md)
inside the functional-core boundary, and that backend (iv) Rust still
carries the `last_visit_*` cache on its search-board struct where the
style contract requires it on the opaque Rust board handle. Sprint
`6.9` closed the same date for backend (iii) by adopting absolute
`SideToMove`, reusable `BlockMasks`, bidirectional path-existence BFS,
action-only `UctNode`, and the Sprint `5.8` C++ flag/BOLT scrub; the
accepted `mcts test all` recorded backend (iii) Q1a/Q1b at the cohort
lead alongside backend (ii) (`+94%` Q1a ST and `+105%` Q1b ST vs the
pre-`6.9` baseline), Q3/Q4/Q6/Q7 PASS, and
`normalized_divergence_score=0.0000`. Sprint `6.10` closed the same date by introducing `RustBoardHandle` as
the opaque C ABI handle (with the relocated `last_visit_*` cache),
adopting absolute `SideToMove`, the `BlockMasks` additive pattern,
bidirectional BFS, an action-only secondary `Vec` (the parallel
`Vec<MctsRustBoard>` was removed from `tree.rs`), and an
inlining/cold-path audit for backend (iv). The accepted `mcts test all`
recorded backend (iv) at the cohort lead on every primitive metric
(`Q1a` `38941.1` ST playouts/s, `Q1b` `42078.7` ST search-iters/s),
Q3/Q4/Q6/Q7 PASS, `normalized_divergence_score=0.0000`. Sprint `8.17`
then closed the same date with the proposed `MutableByteArray# s`
arena migration **measured but rejected** (single-buffer
`STUArray s Int Word32` with named per-field offsets compiled cleanly
but regressed focused Haskell rates by `Q1a` `-5.5%` ST / `Q1b`
`-1.1%` ST against the Sprint `8.13` six-slab baseline; reverted under
the Performance Measurement Doctrine) and the descent/rollout `INLINE`
audit recorded as no-op (Sprints `8.13`/`8.15` had already saturated
`INLINE`/`INLINABLE` density). The post-`8.17` cohort ranking
`rust ≥ cpp-functional ≈ cpp-imperative > haskell` confirms the
analyst prediction that closing the (iii)/(iv) permitted hot-path
shape gap inverts Haskell's pre-`6.9` lead. The remaining Haskell
shortfall sits in the documented PGO-asymmetry band. None of the
deliverables touched the C ABI symbol set, the canonical action ID
encoding, the 12-wall cap, the transcript wire format, or the
Q3/Q4/Q6/Q7 invariants; the verdict line remains informational per
[Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine).
The Sprint `6.9`, `6.10`, and `8.17` rows all moved to Completed in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md);
the `8.17` row carries the `measured but rejected` notation.

Sprint `8.18` closed on 2026-05-30 with the profile-driven arm64
recovery investigation. A cross-platform A/B measurement between an
Apple Silicon arm64 Docker host and an x86_64 amd64 host (caledon),
both running the same `docker/Dockerfile`, GHC `9.14.1`, and LLVM
`19`, confirmed the cohort-vs-Haskell gap is dramatically wider on
arm64 (`mcts test all` verdict `Trails parity band by 85.6%`) than
on amd64 (`29.5%`; Q1b MT8 ratio `1.06x`; Haskell MT8 search scaling
`6.36x` outperforms backend `(ii)`'s `5.38x`). Sprint `8.18` Stage 1
accepted one Haskell-source change (`src/MCTS/Search/Arena.hs` →
`Data.Array.Base.unsafeRead`/`unsafeWrite` for the Arena read/write
helpers; +4-8% Q1a ST arm64 focused-bench, amd64 flat); Stages 2-5
ledgered (toolchain `mcpu` unblock root-caused to binutils-2.42 LSE
rejection, `Float`→`Word32` bitcast neutral, rollout worker-wrapper
asm-skipped, NCG `-fasm` -3.45% vs `-fllvm`). Authoritative
investigation methodology and per-stage records live in
`bench-profiles/diagnosis-final.md` and
`bench-profiles/stage{1..5}-result.md`; see
[phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
Sprint `8.18` section for the closure narrative.

Sprint `8.19` closed 2026-05-30 with the Dockerfile-level aarch64
mcpu unblock **measured but rejected**. The wrapper-routed Approach
A (settings patch on `pgm_c` + `LLVM llvm-as command`, cabal
`if arch(aarch64) ghc-options -optlo-mcpu=apple-m1
-optlc-mcpu=apple-m1`) built cleanly with closure gates PASS, but
the arm64 `mcts test all` verdict regressed from Sprint `8.18`'s
`85.6%` to `268.7%` because LSE / `rcpc-immo` atomics emitted by
`llc-19 -mcpu=apple-m1` execute slower than the baseline ARMv8
LL/SC atomics GHC's RTS was tuned against on Docker-on-Apple-Silicon
(Haskell Q1b ST -51%; cohort C++/Rust within noise — rules out
broader side-effects). Reverted to byte-identical pre-`8.19`
toolchain state. The documented aarch64 mcpu deferral now stands on
two load-bearing grounds: binutils-2.42 assembler rejection
(toolchain-fixable) plus the measured Haskell-runtime regression
from LSE/rcpc-immo atomics (not toolchain-fixable from this
project's side). Phase `8` returns to ✅ Done. See
[phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
Sprint `8.19` Closure Notes for the full measurement table.

**2026-06-04 — Phase 9 hostbootstrap implementation closes.** Phase 9
introduced `hostbootstrap` as the host-installed orchestrator, the typed
`hostbootstrap.dhall` project config, and the `FROM ${BASE_IMAGE}`
Dockerfile inheritance pattern. Sprints `9.1`, `9.2`, and `9.3` are `✅ Done`:
the root config exists, the Dockerfile is a slim base-image overlay,
`compose.yaml` is deleted, and the canonical invocation is
`hostbootstrap run <mcts-args>`. Sprint `9.3` closed the post-migration
report-card surface: `hostbootstrap run test all` emits a non-pending
measurement and passes Q3/Q4/Q6/Q7 without requiring checked-in arm64/amd64
throughput anchors. Phase `1` reclosed Sprints `1.14` (toolchain pin update to
GHC `9.12.4` + Cabal `3.16.1.0`), `1.15` (canonical hostbootstrap invocation),
and `1.16` (formatter-tools GHC unified with project GHC). Phase `0` reclosed
Sprint `0.5`. Phases `2`–`8` remain closed on their owned surfaces. The
implementation handoff is complete.
See [phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md)
Sprints `1.14`–`1.16`, and
[phase-0-planning-documentation.md](phase-0-planning-documentation.md)
Sprint `0.5` for the doctrine.

## Target Outcome

One `mcts` Haskell CLI binary, built by Cabal under GHC `9.12.4` and Cabal
`3.16.1.0` (Phase 1 reopen Sprint `1.14`; see
[phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md) for the
hostbootstrap base image whose warm Cabal store this pin matches), drives all
five backend slots behind a uniform command surface.
Backend (i) `cpp-legacy/` is a strictly verbatim re-port of `MCTS_legacy` used
for legacy compatibility and Q6 legacy-envelope evidence. Backend (ii)
`cpp-imperative/` is the maximally-tuned imperative C++23 performance ceiling;
Sprint `5.7` closed its current kernel as fixed-capacity action-id generation,
absolute side-to-move board state, action-only MCTS tree storage, reusable wall
masks, trusted internal apply/cache paths, and representative Dockerfile-time
PGO/BOLT training.
Backend (iii) `cpp-functional/` uses the same PGO+BOLT+`mimalloc` optimisation
stack while adopting the functional-core value-state style shared with backend
(iv) `rust/` and backend (v) `haskell`; Sprint `6.8` has brought Rust's implementation
hot path up to that same structural target. Backends
(ii), (iii), and (iv) publish one
canonical bolted shared library each; the Dockerfile currently trains PGO/BOLT once
on the bounded metric-suite profile suite implemented in `MCTS.CLI.Build`, and
runtime commands do not retrain or switch between workload-specific libraries.
Backend (v) is the pure Haskell engine running natively in the same process, with
`ST`-monad mutable arena internally and pure search API externally.

Three POC metric units exercise the cohort: terminal playout throughput
(`playouts/s`), search-iteration throughput (`search-iters/s`), and played-game
self-play throughput (`games/s`). Performance benchmarks run single-threaded and on
8 workers where batching applies under `--rng native`, where each backend uses its
own fast/native deterministic RNG contract and no cross-backend transcript identity
is expected.
Logical-equivalence verification uses the same workloads under `--rng cpp`, where
equivalence tests consume C++-generated verification seeds through the shared C++ RNG
bridge so MCTS transcripts can be compared exactly. `mcts verify` round-robin-compares
visit counts under `--rng cpp` across `(ii)..(v)`. `mcts verify legacy-parity` supplies
the Q6 legacy-envelope liveness/overflow check across all five backend slots.
`mcts test all` emits the tidy POC report-card summary block answering Q1-Q7 in one
screenful. The current implementation emits unit-aware Q1a terminal playout, Q1b
search-iteration, Q2 played-game, and split Q5 scaling rows; Sprint `8.11`
provided historical closure evidence for those rows, and Sprint `8.12` refreshed
the verdict against the corrected backend (ii). Live
workload constants are implemented in `MCTS.CLI.Test` and mirrored in
`cabal.project` comments. Legacy-envelope knobs remain live report-card metadata.
Sprint `7.11` extended the report card to Q1-Q7 by adding Q7 semantic parity for
`(ii)..(v)` and a normalized divergence score that summarizes the measured matrix
without empirical threshold text.
Normal validation never depends on checked-in generated transcripts, throughput
JSON, or snapshot files; tests synthesize or explicitly generate evidence in
temporary or operator-provided roots.

## Architecture Overview

- **Haskell CLI surface.** One binary `mcts`. `CommandSpec` owns the command tree,
  action-oriented command descriptions, examples, generated command reference, manpage
  command list, JSON/tree/list introspection, and tracked shell-completion artefacts.
  `MCTS.CLI.Parser` renders the topology from that registry, while the leaf option
  parsers remain explicit semantic parsers in `Parser.hs`; the parser is therefore not
  a competing CLI source of truth.
  The library-first layout puts `app/Main.hs` thin and logic in `src/MCTS/`.
  Owned by [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md).
- **Transcript codec, RNG, determinism contract.** The transcript wire format is
  little-endian binary with no schema-library dependency: header carrying the run config,
  per-move records of `(action_id, visits)` sorted ascending by action ID, and no stored
  equity floats. An engine-envelope block follows the fixed header (excluded from the
  backend-specific `sha256(RunConfig)` cache key) so substrate drift is detectable on
  replay; equity is cached lazily per `(backend, build)` in a sidecar `.eq` directory
  next to the `.tr`. The canonical single-byte action enumeration covers all legal
  Corridors actions (pawn moves at `y*9 + x` for x,y ∈ [0,8], horizontal walls at
  `81 + y*8 + x`, vertical walls at `145 + y*8 + x`, with 209..254 reserved and
  255 as sentinel). Per-game RNG
  seeds derive from `splitmix64(master_seed, game_index)` so per-game output is
  independent of worker count and scheduling order. Owned by
  [phase-2-transcript-codec-and-determinism.md](phase-2-transcript-codec-and-determinism.md).
- **Backend (v) Haskell engine.** Corridors game state as strict `Word64` wall
  bitboards and compact `Word8` pawn slots under `-fllvm`, `Word16` ply counter,
  MCTS tree as a structure-of-arrays `STUArray` arena of unboxed `Int32` / `Float`
  fields, UCT search and random-rollout leaf evaluation in the `ST s` monad,
  direct packed-slot path starts in wall-legality BFS, no-wall legal-action fast
  path, and a pure API at the boundary. The current game loop allocates a fresh
  arena for each per-move search; `treeReroot` is a tested arena primitive, not an across-move persistence
  path. Per-CPU LLVM
  `-mcpu=native` flags are intentionally excluded on the current aarch64 container and
  documented as deferred tuning rather than pending cleanup. Owned by
  [phase-3-haskell-engine.md](phase-3-haskell-engine.md).
- **Backend (i) C++ legacy port and FFI bridge.** Verbatim re-port from `~/MCTS_legacy`
  with only the FFI shims required to expose a C ABI; inherits the legacy's
  `std::shared_ptr<uct_node>` trees, `std::mt19937_64` RNG, single-threaded design, and
  no draw rule (`is_terminal()` ↔ `hero_wins() || villain_wins()`). It remains live for
  Q6 legacy-envelope liveness/overflow evidence;
  it is not part of the default Q3 `(ii)..(v)` visit-vector identity cohort because its
  legacy tree semantics intentionally differ from the steelman cohort. Owned by
  [phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md)
  and Phase `8` restoration.
- **Backend (ii) C++ imperative steelman.** The performance ceiling. C++23 with `-O3
  -march=native -mtune=native -flto -fno-plt -fno-semantic-interposition
  -fvisibility=hidden -fvisibility-inlines-hidden -fno-exceptions`, no `-ffast-math`;
  Makefile-level two-stage PGO via `-fprofile-generate` / `-fprofile-use`, BOLT
  post-link targets, `mimalloc` link; arena tree, compact bitfield board,
  direct capped legal-move generation, wavefront bitset escapability, flat children
  layout, move-list buffer reuse, branch hints, `__builtin_prefetch`,
  `__builtin_popcountll` / `__builtin_ctzll`, `alignas(64)`, `thread_local` scratch.
  Sprint `5.7` closed this component's full hot-path steelman by removing
  remaining full-child-board generation, per-child board flipping, full-state node
  storage, repeated wall/path mask construction, and trusted-search allocation or
  replay residue.
  The Dockerfile routes the PGO/BOLT sequence through the
  `mcts build cpp-imperative` build recipe. PGO profile data and BOLT `.fdata`
  are mandatory image-build outputs; installing a PGO-only or unoptimized fallback
  under the canonical load name is forbidden and must fail the Dockerfile build.
  Sprint `8.10` replaced the earlier narrow self-play training runner with a
  bounded profile suite, Sprint `8.11` extended that suite with primitive
  terminal-playout and search-iteration profile runs after the metric refactor,
  and Sprint `5.7` retuned those profiles for the new kernel.
  Owned by
  [phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md) and Phase
  `8` parity closure.
- **Backends (iii) C++ functional-core and (iv) Rust.** Backend (iii) mirrors
  backend (ii)'s Makefile-level optimisation target surface so the `(ii)` vs
  `(iii)` comparison can isolate style under the shared C++ PGO/BOLT CLI path, and
  Sprint `6.7` closed its compact value-state C++ hot path without legacy
  `corridors::board` or action-text parsing. Backend (iv) Rust follows the
  same compact value-state and C ABI boundary with Rust ownership idioms. Sprint
  `6.8` has replaced its queue-BFS, heap action-buffer, arena-reservation, clone, and
  global visit-cache hot-path residue. Sprint `6.9` (closed 2026-05-29)
  adopted the remaining backend-(ii) hot-path techniques permitted by the
  style contract for backend (iii) — absolute `SideToMove`, reusable
  `BlockMasks`, bidirectional path-existence BFS, action-only `UctNode`,
  and the Sprint `5.8` C++ flag/BOLT scrub on `cpp-functional/Makefile` —
  bringing backend (iii) into the cohort lead alongside backend (ii) on
  Q1a/Q1b. Sprint `6.10`
  (closed 2026-05-29) closed the analogous shape items on backend (iv):
  the `last_visit_*` cache moved from the search-board struct onto the
  opaque `RustBoardHandle` declared in `rust/src/c_abi.rs` (closing the
  style-contract deviation in
  [../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md)),
  the absolute `SideToMove` enum replaced the per-transition `flipped()`
  reassignment, `BlockMasks` are reused additively per wall candidate,
  `path_exists_with_masks` is bidirectional, and the parallel
  `Vec<MctsRustBoard>` was removed from `tree.rs` to keep the arena
  action-only. Backend (iv) now leads the cohort on every primitive
  metric. Rust runs on
  the latest stable compiler with the
  pinned `[profile.release]` (`opt-level = 3`, `lto = "fat"`, `codegen-units = 1`,
  `panic = "abort"`, `strip = "debuginfo"`), `RUSTFLAGS=-C target-cpu=native -C
  link-arg=-B/usr/lib/llvm-19/bin -C link-arg=-fuse-ld=lld -C
  link-arg=-Wl,--emit-relocs`, `mimalloc` through the
  container system library as `#[global_allocator]`, two-stage rustc PGO, and BOLT
  post-link. Their current accepted profiles use the same Dockerfile-time bounded
  metric-suite profile suite as backend (ii): terminal playout, search-iteration,
  legacy played-game rollout, and self-play workloads. Owned by
  [phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md) and
  [../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md).
- **Cross-backend verify, test stanzas, POC report card.** Six live Cabal test-suite
  stanzas (`mcts-unit`, `mcts-integration`, `mcts-cross-backend`,
  `mcts-legacy-parity`, `mcts-semantic-parity`, `mcts-haskell-style`), each
  `type: exitcode-stdio-1.0` with `tasty` as the in-stanza runner; `mcts test all`
  is a Plan/Apply command whose
  exact sequence is owned by
  [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md)
  and whose high-level surface covers lint/docs prerequisites, Dockerfile-prebuilt
  Cabal test executables, Dockerfile-built canonical foreign backend artefacts,
  prebuilt stanza execution, verify cohorts, the pinned no-write report-card
  workload, and the tidy summary block.
  The text report card defines its terms, renders aligned raw-performance,
  question-summary, and divergence-matrix tables in that order, and ends with
  explicit answers based on the observed metrics, normalized divergence score, and
  gate outcomes.
  Owned by
  [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md).
- **Haskell performance parity closure.** GHC `-O2 -fllvm`,
  `-funbox-strict-fields`, `-fspecialise-aggressively`,
  `-fexpose-all-unfoldings`, `-flate-dmd-anal`, `-fmax-simplifier-iterations=20`,
  `-fworker-wrapper`, `-fstatic-argument-transformation`, RTS
  `-A64m -n4m -qg1 -qb -T`, `INLINABLE` on the search hot path, unboxed strict
  fields everywhere, no `Maybe`/`Either` in the rollout inner loop. Phase `8`
  records the honest Q1/Q2/Q5 measurement of backend (v) Haskell against the
  fully-optimised backend (ii) target per
  [../documents/engineering/compiler_runtime_tuning.md → Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine).
  The verdict line uses `HASKELL_PARITY_TOLERANCE = 0.05` as a labelling cutoff
  (`Within parity band` vs `Trails parity band by N%`) and is informational, not
  a closure gate. Closure gates on the apples-to-apples invariants Q3/Q4/Q6/Q7
  plus a non-pending measurement. Phase `8` also keeps all five backends live
  while removing stale two-backend drift and preserving the rule that generated
  validation data is not checked into git. Sprint `8.17` closed on
  2026-05-29 with the `MutableByteArray# s` arena migration **measured but
  rejected** (single-buffer `STUArray s Int Word32` regressed focused
  Haskell rates by `Q1a -5.5%` ST / `Q1b -1.1%` ST against the Sprint
  `8.13` six-slab baseline; reverted under the Performance Measurement
  Doctrine) and the descent/rollout `INLINE` audit recorded as no-op
  (Sprints `8.13`/`8.15` had already saturated `INLINE`/`INLINABLE`
  density). Owned by
  [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md).

## Doctrine Scope

[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) is the authoritative CLI doctrine. This
section declares which doctrine sections are binding and which are informational. No
sprint may schedule adoption of an out-of-scope section.

**In scope (binding, every phase that touches the named surface):**

- Command Topology — commands as ordinary Haskell ADTs.
- `CommandSpec` + Generated Artifacts — marker discipline, paired `mcts docs check` /
  `mcts docs generate`, `forbiddenPathRegistry`, generated-section registry,
  `trackingGeneratedPaths` for fully-generated files (manpages, shell completions),
  and action-oriented command-use text.
- Progressive Introspection — `mcts commands [--tree|--json]`, `mcts help <subcommand>`.
- Subprocesses as Typed Values — `Subprocess` ADT with `subprocessPath`,
  `subprocessArguments`, `subprocessEnvironment`, `subprocessWorkingDirectory`;
  `renderSubprocess` pure for logs and `--dry-run`; `runStreaming` and `capture` as the
  only IO boundary. `callProcess`, `readCreateProcess`, `System.Process`, and
  `typed-process` smart constructors are forbidden from command runners.
- `Plan / Apply` — `build :: TestInputs -> Either AppError TestPlan` /
  `apply :: Env -> TestPlan -> IO ExitCode` shape, with `--dry-run` and
  `--plan-file <path>` on every Plan/Apply command. Current consumers are
  `mcts test all`, `mcts test parity-anchor`, `mcts docs generate`,
  `mcts inspect cache prune`, `mcts build <backend>`, and
  `mcts build legacy-fixtures`.
- Prerequisites as Typed Effects — one `prerequisiteRegistry` spanning every backend's
  toolchain (GCC, LLVM/BOLT, `rustc`, `mimalloc`, `ghcup`, the PGO profile dirs); each
  node carries `nodeId`, `nodeDescription`, and a remedy hint; transitive closure runs
  before `apply`; failure emits `AppError PrerequisiteUnmet`.
- Application Environment — `ReaderT Env IO` with a single `Env` record threaded through
  command runners.
- Lint, Format, and Code-Quality Stack — `fourmolu` + `hlint` + `cabal format`; pinned
  `fourmolu.yaml` at repo root with the twelve doctrine-mandated settings
  (`indentation`, `column-limit`, `function-arrows`, `comma-style`,
  `import-export-style`, `indent-wheres`, `record-brace-space`,
  `newlines-between-decls`, `haddock-style`, `let-style`, `in-style`, `unicode`).
  Under Phase 1 reopen Sprint `1.16` the formatter-tools GHC is the project GHC
  (`9.12.4` per Sprint `1.14`). The
  `mcts-haskell-style` test-suite enforces all three plus the `cabal format` temp-file
  round-trip byte-equality compare. Fourmolu and HLint are installed into
  `/opt/hostbootstrap/haskell-style/bin/` inside the container against the project GHC
  `9.12.4` (Phase 1 reopen Sprints `1.14` + `1.16`); the formatter tools share
  the single project GHC. Ambient host fallback is not supported.
- Testing Doctrine and Test Organization — six live Cabal stanzas, each
  `type: exitcode-stdio-1.0`, each with its own `tasty` tree; a single `tasty` tree
  spanning all tiers is forbidden. Parser tests use `execParserPure`. Canonical property
  invariants `decode . encode == id`, `render is deterministic`, `parser roundtrips` are
  enumerated in the `mcts-unit` stanza. The project-specific stricter rule is that
  normal tests do not read checked-in generated validation data: renderer examples,
  transcripts, sidecars, and report-card shapes are asserted semantically or generated
  under temporary directories during the test run.
- Output Rules — stdout primary, stderr diagnostics; `--format json|table|plain` default
  `table` on TTY else `plain`; `--color auto|always|never` / `--no-color`. The TUI
  commands (`play`, `inspect replay`) own their own rendering and ignore both flag
  families.
- Error Handling — single `AppError` ADT covering the canonical 19-variant set:
  `TranscriptNotFound`, `TranscriptAmbiguous`, `TranscriptFormatUnsupported`,
  `VerifyMismatch`, `VerifyLengthMismatch`, `VerifyTerminatorMismatch`,
  `VerifyCohortTooSmall`, `RecomputeMismatch`, `LegacyParityRolloutOverflow`,
  `ArchEnvelopeMismatch`, `EngineEnvelopeMismatch`, `PrerequisiteUnmet`,
  `SubprocessFailed`, `FFIFailure`, `DocsCheckDrift`, `UnknownCommand`,
  `InvalidMove`, `ParseError`, `IOErrorText`. The set matches
  [../HASKELL_CLI_TOOL.md → Error Handling](../HASKELL_CLI_TOOL.md) exactly;
  `SubprocessFailed`, `FFIFailure`, and `DocsCheckDrift` cover the typed
  `Subprocess` boundary, the C ABI bridge, and `mcts docs check` marker
  drift respectively. `renderError :: AppError -> Text` is the boundary in
  `src/MCTS/CLI/Output.hs`; hlint rules forbid `print`, `exitFailure`, and
  direct terminal formatting outside that boundary.
  `SubprocessFailed` is reserved for the typed `Subprocess` boundary
  (`runStreaming` / `capture` non-zero exit); `FFIFailure` is reserved for C ABI
  exceptions surfaced through the FFI bridge; `TranscriptFormatUnsupported`
  fires on non-zero `flags u32` in a transcript header;
  `ArchEnvelopeMismatch` fires when a transcript or verify cohort spans more
  than one `host_arch`; `EngineEnvelopeMismatch` fires when the layered
  engine-envelope check (cohort-invariant fields across the cohort,
  per-backend-slot fields against the live binary) finds a disagreement;
  `ParseError` and `IOErrorText` carry parser/validation and textual IO failures
  that must still pass through the same render boundary — the variants are kept
  semantically distinct.
- GADT-indexed state machines where naturally indicated (`VerifyBackend`; Q6
  legacy-parity validates the complete backend list under the legacy envelope);
  the `RngSource` axis encoded so that `--rng cpp` is the
  parse-time default for `verify`. `SimBudget`, `Threading`, and `Side` remain plain
  ADTs — the doctrine's GADT mandate applies only to state machines with more than
  two conceptual states per
  [../HASKELL_CLI_TOOL.md → GADT-Indexed State Machines](../HASKELL_CLI_TOOL.md).
- Project-level documentation standards — the six elements live in
  [../documents/documentation_standards.md](../documents/documentation_standards.md):
  marker convention with literal `<!-- mcts:<key>:start -->` etc. examples, authoritative
  pointer to the `GeneratedSectionRule` registry, "How to regenerate" naming
  `mcts docs generate`, per-file `**Generated sections**:` metadata field with lint
  contract, five-step extension protocol, fully-generated do-not-hand-edit rule.
- Toolchain pinning — GHC `9.12.4`, Cabal `3.16.1.0` (Phase 1 reopen Sprint
  `1.14`); `mcts.cabal` declares `tested-with: ghc ==9.12.4`; `cabal.project`
  declares `with-compiler: ghc-9.12.4`. The pin matches the warm Cabal store
  baked into the hostbootstrap base image (see
  [phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md)).
- Project Structure (library-first layout) — `app/Main.hs` thin, logic under
  `src/MCTS/`.
- hostbootstrap adoption (Phase 9) — `hostbootstrap` as the `pipx`-installed
  host Python CLI orchestrating substrate detection, prerequisite validation,
  base-image pull, project-image build, and `<mcts-args>` dispatch to the
  image's tini-wrapped `mcts` ENTRYPOINT in a one-shot `docker run --rm`
  container; typed `hostbootstrap.dhall` at repo
  root declaring `AppleSilicon`, `LinuxCpu`, and `LinuxGpu` substrates
  with the same `Container` model;
  `docker/Dockerfile` inheriting `FROM ${BASE_IMAGE}` from the prebuilt
  base image `docker.io/tuee22/hostbootstrap:basecontainer-cpu-<arch>`,
  adding only what the base does not ship (pinned formatter tools, source
  build, foreign-backend builds). See
  [phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md);
  the canonical invocation shape (`hostbootstrap run <mcts-args>`) is
  Phase 1 reopen Sprint `1.15`'s doctrine.

**Out of scope (informational only — no sprint may schedule adoption):**

- Long-Running Daemons in the Same Binary — the CLI is short-running only. Covers the
  daemon `Lifecycle: load → prereq → acquire → ready → serve → drain → exit`,
  `BootConfig` / `LiveConfig` split, `SIGHUP` hot reload, `/healthz` / `/readyz` /
  `/metrics` endpoints, structured `co-log` logging, and the daemon-internal
  "Configuration: Dhall file with mandatory hot reload" subsection.
  - **Exception: `Test hooks in Env`.** Though the doctrine places this subsection
    inside the daemon section, the test-hook pattern (`Env` fields with no-op
    production defaults that tests override to observe or control async behavior)
    is admitted as in-scope. It is required for the
    [phase-1-haskell-cli-surface.md → Sprint 1.8](phase-1-haskell-cli-surface.md)
    `Env` record and the
    [phase-3-haskell-engine.md → Sprint 3.5](phase-3-haskell-engine.md)
    monotonic-clock bracket assertion. No other daemon discipline (lifecycle,
    hot reload, signal handling, `/healthz` endpoints, `co-log`) is admitted.
- Capability Classes and Service Errors — no external subsystems (no MinIO, Redis,
  PostgreSQL on the supported path).
- Retry Policy as First-Class Values — no external subsystems with retryable errors.
- At-Least-Once Event Processing — no event stream.
- Reconcilers: Idempotent Mutation as a Single Command — no managed state in the world
  outside the local transcript cache.
- Smart Constructors for Paired Resources — no paired resources (no DNS/cert pairs, no
  PV/PVC pairs).
- Pulumi-Orchestrated Infrastructure Tests — no cloud surface.

**Stack deviations from doctrine (recorded once, here):**

- `brick` + `vty` are added for the `play` and `inspect replay` TUIs only. No other
  command may import either.
- `dhall` is unused. The doctrine prescribes `dhall` for daemon configuration; daemon
  configuration is itself out of scope for this CLI, so the dependency does not enter
  the stack.

## Hard Constraints

The supported architecture closes on the following non-negotiable rules. Numbered for
referenceability.

1. One Haskell CLI binary named `mcts`. No separate Python entry point, no separate
   Rust entry point, no separate C++ entry point. Every measurement, determinism check,
   and game runs out of one Haskell process driven by one binary.
2. Every individual game is single-threaded internally. One tree, one search, one
   rollout stream per game. Multi-threading is only ever about running independent games
   concurrently.
3. Multi-threaded benchmark mode defaults to 8 workers (`--workers N` to override).
   Each worker plays one game at a time, single-threaded internally.
4. Per-game RNG streams are seeded by `splitmix64(master_seed, game_index)` so per-game
   output is independent of worker count, scheduling order, and worker-to-game
   assignment.
5. Two RNG sources are supported and intentionally serve different goals:
   `--rng native` is for performance benchmarks and operator play, where each backend
   uses its own fastest deterministic RNG contract and benchmark streams are not
   expected to be cross-backend bit-equal. `--rng cpp` is for logical-equivalence
   verification, where every participating backend consumes C++-generated
   verification seeds from the shared RNG bridge so game transcripts, visit tables,
   and chosen moves can be compared exactly.
6. `--rng cpp` is the implicit default for `verify` and is not user-overridable on the
   `mcts verify` subtree. The native RNG cannot validate cross-backend bit equality.
7. `VerifyBackend` covers the Q3 logical-equivalence cohort `(ii)..(v)`:
   `cpp-imperative`, `cpp-functional`, `rust`, and `haskell`. Backend (i) is excluded
   from Q3 because its terminal-state and tree semantics are deliberately verbatim legacy
   behavior, not because it is unsupported.
8. The legacy-parity parser surface covers Q6 across all five backend slots under the
   legacy envelope. Q6 is a liveness/overflow and chosen-envelope check; Q3 remains the
   visit-vector identity proof for the steelman cohort `(ii)..(v)`.
9. Backends (ii)–(v) carry a `Word16` ply counter in board state and add the ply-cap
   draw rule: `is_terminal` ↔ `hero_wins || villain_wins || ply_count >= max_plies`;
   `get_terminal_eval` returns `0.0` on ply-cap termination. Default `max_plies = 200`,
   pinned in the transcript header. Backend (i) lacks the ply cap and is verbatim from
   `MCTS_legacy`.
10. The legacy parity envelope pins `max_plies = 10000` (= `MAX_ROLLOUT_ITERS` in the
    legacy). Q6 uses that envelope as a five-backend liveness/overflow gate, while Q3
    owns visit-vector equality across `(ii)..(v)`.
11. The transcript wire format is little-endian binary with no schema-library
    dependency. No protobuf, no flatbuffers, no Cap'n Proto, no CBOR. The header carries
    the run config; per-move records are sparse `(action_id, visits)` pairs sorted
    ascending by action ID. Equity is excluded from the wire format.
12. Transcripts are one-game files content-addressed by `sha256(run_config)`, where
    `run_config` includes the backend and `game_index` so provenance-bearing cache files
    never collide across backends or games. `mcts play`-recorded transcripts use
    `sha256(run_config || move_history)` because the human's move choices make the
    post-config bytes non-deterministic. The cache root resolves
    `--cache-dir <path>` → `./.mcts-cache/` inside the container; the `mcts` binary
    does not read cache-root environment variables.
13. Hash-prefix lookup is git-style: shortest unique prefix accepted, minimum 4 hex
    chars. `AppError TranscriptNotFound` on no match; `AppError TranscriptAmbiguous`
    carrying the candidate list on multi-match.
14. Search trees are memory-resident only — nothing is serialised between runs. The
    current Haskell driver allocates a fresh `STUArray` arena for each per-move
    search; across-move tree persistence is not implemented in the closed baseline.
    `MCTS.Search.Arena.treeReroot` exists as a tested primitive for future
    profile-driven work, but the game loop does not keep inherited visits warm.
15. Originator equity is recomputed only by the same backend/build slot that produced the
    transcript, or by a live binary whose envelope matches the transcript's recorded
    originator envelope. Cross-backend and logical-fallback recomputes are foreign-view
    evidence and must not be written or displayed as originator evidence. Cross-backend
    equity bit-equality is not asserted; the Q3 determinism contract is on visit counts
    (integer, order-independent) only. Float drift across the Q3 verification cohort
    `(ii)..(v)` that changes UCT child selection or the final highest-visit root action
    surfaces as a visit-count mismatch on the next move and is caught by `mcts verify`.
16. The toolchain is pinned at GHC `9.12.4` and Cabal `3.16.1.0` (Phase 1 reopen
    Sprint `1.14`). `mcts.cabal` declares `tested-with: ghc ==9.12.4`;
    `cabal.project` declares `with-compiler: ghc-9.12.4`. The pin matches the
    warm Cabal store baked into the hostbootstrap base image (see
    [phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md)).
17. Backend (i) `cpp-legacy/` is strictly verbatim from `~/MCTS_legacy/backend/`. Only
    FFI shims are permitted around the imported legacy source. The build flags are
    `-std=c++17 -O3 -fPIC -Wall`.
    It uses `std::shared_ptr<uct_node>` trees and `std::mt19937_64` unchanged.
18. Backends (ii) and (iii) compile with `-std=c++23 -O3 -march=native -mtune=native
    -flto -fno-plt -fno-semantic-interposition -fvisibility=hidden
    -fvisibility-inlines-hidden -fno-exceptions`. `-fno-exceptions` is mandatory
    (the engine core does not throw, so landing-pad cost is unconditional dead
    weight). No `-ffast-math` and no `-Ofast`. The PGO+BOLT pipeline plus
    container-provided `mimalloc` link is required and must complete inside the
    Dockerfile build. Missing PGO profile data, missing BOLT `.fdata`, or copying a
    lesser artefact into the bolted/canonical load path is a build failure, not an
    accepted fallback. The installed bolted libraries are smoke-tested before the
    image is published. Sprint `5.9` (2026-05-29 compiler audit) pivoted
    backend `(ii)` from `g++` to `clang++-19` (dropping the GCC-only `-fipa-pta`
    flag and switching PGO file format to `.profraw` + merged `.profdata`);
    Sprints `4.6` and `6.11` then pivoted backends `(i)` and `(iii)` to
    `clang++-19`, and Sprint `4.7` removed the `cxx-gpp` prerequisite node plus
    explicit `gcc`/`g++` Dockerfile packages. All three C++ backend Makefiles now
    pin `CXX := clang++-19`; GCC is only a transitive `build-essential`
    dependency, not a first-class backend compiler. Sprint
    `5.3` owns the fail-closed C++ PGO/BOLT CLI wiring; Sprint `8.10` replaced
    the earlier narrow training run with a bounded profile suite and Sprint
    `8.11` added and validated the primitive benchmark workloads. Sprint `5.7`
    closed backend `(ii)`'s lower-level imperative kernel work: action-id legal
    generation, absolute side-to-move state, action-only tree layout, reusable
    wall masks, trusted internal buffers, and profile retuning. Sprint `5.9`
    also collapsed the prior `State { FastBoard b; uint16_t ply_count; }`
    wrapper into a flat `FastBoard` so backend `(ii)`'s descent state matches
    the 32 B layout that backends `(iii)` and `(iv)` already use.
19. Backend (iv) Rust uses `[profile.release]` with `opt-level = 3`, `lto = "fat"`,
    `codegen-units = 1`, `panic = "abort"`, `strip = "debuginfo"`. `RUSTFLAGS=-C
    target-cpu=native -C link-arg=-B/usr/lib/llvm-19/bin -C link-arg=-fuse-ld=lld
    -C link-arg=-Wl,--emit-relocs`.
    `mimalloc` as `#[global_allocator]` through the container system library.
    Two-stage `rustc -Cprofile-generate` / `-Cprofile-use` PGO. BOLT post-link.
    The Dockerfile build must fail if profile merge, BOLT instrumentation, BOLT
    training, BOLT optimization, or the final installed-library smoke cannot produce
    the required optimized cdylib. Sprint `8.10` aligned that PGO/BOLT path with
    the same bounded profile suite as the C++ steelman backends, and Sprint `8.11`
    added and validated the primitive benchmark workloads. Sprint `6.8` closed the
    Rust implementation-shape cleanup: bit-parallel path checks, fixed-capacity
    action buffers, child-bound arena reservation, reduced board cloning, and
    board-handle-local visit caching align Rust with `(iii)` and `(v)`.
20. Backend (v) Haskell uses `-O2 -fllvm`, `-funbox-strict-fields`, `-fspecialise-aggressively`,
    `-fexpose-all-unfoldings`, `-flate-dmd-anal`, `-fmax-simplifier-iterations=20`,
    `-fworker-wrapper`, `-fstatic-argument-transformation`. RTS `-A64m -n4m -qg1 -qb
    -T` is baked into the executable. Engine hot path lives in `ST s`; tree is a
    structure-of-arrays `STUArray` arena of unboxed `Int32` / `Float` fields; board
    state is compact `Word8` pawn slots plus `Word64` wall bitboards manipulated
    with `Data.Bits`. Pure API at the
    boundary; no `Maybe` / `Either` in the rollout inner loop. LLVM
    `-optlo-mcpu=native` / `-optlc-mcpu=native` is deferred on aarch64 until
    the assembler target accepts the emitted LSE instructions.
21. Library-first layout: `app/Main.hs` is thin; logic lives under `src/MCTS/`.
22. `CommandSpec` is the source of truth for the command topology, action-oriented
    command-use descriptions, examples, generated command reference, manpage command
    list, command-tree rendering, JSON introspection, and tracked shell-completion
    artefacts. `MCTS.CLI.Parser` renders subcommand topology from the registry and
    keeps leaf option parsing as explicit typed semantic parsers.
23. `Subprocess` is the only IO boundary for subprocess execution. `callProcess`,
    `readCreateProcess`, `System.Process` constructors, and `typed-process` smart
    constructors are hlint-forbidden outside the `runStreaming` / `capture`
    interpreter. The PGO/BOLT build harness invokes `clang++-19` for all three
    C++ backends (with LLVM `.profraw` PGO on `(ii)` and `(iii)`), plus `rustc`,
    `llvm-bolt`, and `cabal` through the typed `Subprocess` boundary.
24. Every Plan/Apply command supports `--dry-run` (renders the plan and exits 0) and
    `--plan-file <path>` (writes the rendered plan for out-of-band review).
25. One `prerequisiteRegistry` spans every backend's toolchain. Failure emits
    `AppError PrerequisiteUnmet` carrying the failing `nodeId`, description, and remedy
    hint.
26. Single `AppError` ADT; `renderError :: AppError -> Text` is the only Text rendering
    at the CLI boundary; `print`, `exitFailure`, and direct terminal formatting are
    hlint-forbidden outside `src/MCTS/CLI/Output.hs`.
27. `mcts test all` is the doctrine-mandatory canonical test command. The live Cabal
    stanzas are `mcts-unit`, `mcts-integration`, `mcts-cross-backend`,
    `mcts-legacy-parity`, `mcts-semantic-parity`, and `mcts-haskell-style`.
    A single `tasty` tree spanning all tiers is
    forbidden. Dockerfile image construction prebuilds each test-suite executable so
    runtime stanza execution does not compile or link on first use.
28. `fourmolu.yaml` at repo root pins the twelve doctrine-mandated settings; the
    `mcts-haskell-style` stanza enforces them plus `cabal format` temp-file round-trip
    byte-equality through the formatter-tools install (`fourmolu-0.19.0.1`,
    `hlint-3.10`) under `/opt/hostbootstrap/haskell-style/bin/` inside the container. Under
    Phase 1 reopen Sprint `1.16` the formatter tools share the project GHC
    `9.12.4` (Sprint `1.14`). Host
    `PATH` fallback is never allowed.
29. Report-card live workload constants are implemented in `MCTS.CLI.Test` and
    mirrored in `cabal.project` comments: `N_PRIM = 20_000`, `P_MAX = 60`,
    `G_R = 1_000`, `G_S = 4`, `G_V = 4`, `G_LP = 2`, `S_BENCH = 500`,
    `S_VERIFY = 500`, `S_LP_SIMS = 4`, and `S_LP = 42`.
30. All five backend identifiers, build leaves, transcript wire tags, and verification
    roles remain first-class. Checked-in generated transcripts, throughput JSON,
    report-card schemas, and renderer snapshots are not part of the normal validation
    surface; evidence is generated in memory, in temporary roots, or through explicit
    operator-provided artifact directories.
31. The Docker development environment inherits the hostbootstrap base image
    `docker.io/tuee22/hostbootstrap:basecontainer-cpu-<arch>` (see
    [phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md)),
    which provides the single LLVM `19` shared by GHC's `-fllvm` backend and
    BOLT post-link, GHC `9.12.4` and Cabal `3.16.1.0` (Phase 1 reopen Sprint
    `1.14`) with a warm Cabal store, `clang-19`, `libclang-rt-19-dev`,
    fourmolu `0.19.0.1`, hlint `3.10`, and Rust `1.95.0` via `rustup`.
    The slim project `docker/Dockerfile` adds the source copy, the Cabal
    exe installs, and the foreign-backend builds. Root-level
    `hostbootstrap.dhall` is the typed project config (Phase 9 Sprint `9.2`);
    `hostbootstrap run <mcts-args>` is the canonical host-side invocation
    (Phase 1 reopen Sprint `1.15`). There is no long-running daemon
    container, bind-mounted workspace, repository
    `.sh` workflow wrapper, or `bootstrap/` helper; host-level `.build/`
    artefacts are unsupported.
32. Move notation matches the legacy engine: `*(x,y)` for pawn moves, `H(x,y)` for
    horizontal walls, `V(x,y)` for vertical walls, x,y ∈ [0,8] for pawns and ∈ [0,7]
    for walls. `inspect show` / `inspect replay` and the `play` TUI render in this
    notation.
33. The transcript decoder's `winner u8` field is a 3-value enum: `0 = hero`,
    `1 = villain`, `2 = draw`. Draws render as `<draw>` in `inspect show` /
    `inspect replay`.
34. `mcts play` accepts `:hint`, `:undo`, `:save`, and `:quit` in-app commands.
    Hand-played transcripts are addressed by `sha256(run_config || move_history)`
    because the human's choices make the post-config bytes non-deterministic. The
    current Sprint `7.4` baseline writes `:save` transcripts through
    `MCTS.Transcript.writePlayTranscript`, routes AI turns through the selected
    backend's dynamic FFI search path when a foreign shared library is present,
    and unit-tests the write/decode plus selected-backend AI advance paths.
35. `inspect replay` loads cached equity sidecars before opening the TUI and fills a
    missing originator sidecar by replaying the search through the same backend. The
    replay preparation compares the recomputed chosen action and visit table against
    the transcript under `--rng cpp` before writing the `.eq`; failures surface in the
    TUI status line. The last `replayCacheStates` board states (default 20,
    `--cache-states N`) are kept in memory for back-navigation.
36. Supported target platforms are **amd64 Linux** and **arm64 Linux**. Reproducibility
    envelopes are per-architecture: a transcript written on amd64 is bit-identical on
    replay against the same backend on amd64, and a transcript written on arm64 is
    bit-identical on replay against the same backend on arm64, but cross-architecture
    bit-equality is **not** guaranteed (the `c_param u64` IEEE-754 bit-cast and the
    backend-internal floating-point arithmetic differ at the ULP level across arches).
    Transcript headers and report-card metadata carry a `host_arch` tag (`"amd64"` |
    `"arm64"`); cross-backend `verify` and same-backend `verify` checks are only valid
    when the comparison set shares a `host_arch`. See
    [../documents/engineering/determinism_contract.md → Architecture
    Envelope](../documents/engineering/determinism_contract.md).
37. Every transcript carries a versioned **engine envelope** block immediately after
    the fixed header, excluded from the backend-specific `sha256(RunConfig)` cache key.
    The envelope decomposes into
    cohort-invariant fields (`host_arch`, `rng_source`, `shared_rng_build_id`,
    `cohort_config_hash`) and per-backend-slot fields (`engine_build_id`,
    `compiler_id` + `compiler_version`, `fp_flags`, `libm_id`,
    `cpu_features`, `fp_env`). `mcts verify` hard-fails with
    `AppError EngineEnvelopeMismatch` when cohort-invariant fields disagree across the
    cohort. `checkTranscriptEnvelopesLive`, exercised by integration and Q3/Q6 verify,
    also checks per-backend-slot fields between a cached transcript and the live binary
    for the same backend slot (downgradeable to a warning via the `--allow-stale` flag
    for forensic comparisons). FFI-produced transcripts carry the live
    `mcts_<backend>_get_envelope()` payload when the matching cdylib is present;
    `engine_git_commit` and the display/cache `build_id` accessor remain provenance
    only and do not gate stale-envelope verification.
    absent cdylibs use the in-process fallback envelope. Cross-backend differences in
    per-backend-slot fields are expected and silent — the `verify` contract
    is "different backend slots, identical visits." See
    [../documents/engineering/determinism_contract.md → Engine Envelope](../documents/engineering/determinism_contract.md).
38. Equity sidecar cache layout under the existing transcript cache root:
    `<cache-root>/transcripts/<arch>/<sha>/<backend>-<build_label>.eq`
    plus a `.envelope` neighbour file holding the envelope of the build that wrote
    the `.eq`. Live build labels use the first 16 hex characters of
    `engine_build_id`; logical all-zero GHC envelopes use the `logical` build
    label, yielding full sidecar names such as `<backend>-logical.eq`.
    Multi-build cohabitation is automatic — a rebuild lands in a fresh
    cache slot keyed by the new build label; old slots remain for
    forensic comparison until explicitly pruned (`mcts inspect cache prune`). The
    sidecar is read on `inspect replay` and `inspect show --with-equity` for instant
    cache hits; originator cache misses are filled only by the matching backend/build,
    and foreign-view recomputes are labelled as foreign evidence. See
    [../documents/engineering/transcript_format.md → Equity Sidecar Cache](../documents/engineering/transcript_format.md).
39. Divergence-smell reporting per
    [../documents/engineering/determinism_contract.md → Divergence Smell](../documents/engineering/determinism_contract.md):
    same-substrate and `--rng cpp` cross-backend cohorts (ii)–(v) hard-fail on any
    visit-count or move disagreement (the existing contract). Report-card output uses
    the explanatory `visit/move` divergence matrix plus one
    `normalized_divergence_score`, defined as the maximum visit or move disagreement
    rate across every matrix cell. The report card must not render empirical native
    or cross-build threshold pairs.
40. Normal validation must pass from a clean clone without pre-existing transcripts,
    throughput anchors, report-card schemas, renderer snapshots, or other generated
    validation data. Tests generate transcripts, sidecars, report-card values, and
    renderer examples in memory or under temporary directories. Runtime/operator cache
    files live under ignored roots such as `.mcts-cache/`; optional audit artifacts live
    in explicit external or ignored local roots.
41. Q7 semantic parity is scoped to steelman backends `(ii)..(v)`. It checks
    rule-state parity, replay compatibility, search invariants, and terminal-board
    search rejection under generated histories. It does not include backend `(i)`, does
    not weaken Q3, and does not use the normalized divergence score as a tolerance for
    failed semantic invariants.

## Dependency Chain

| Phase | Depends On | Why |
|-------|------------|-----|
| 0 | — | Bootstrap |
| 1 | Phase 0 | The CLI surface and lint stack consume the doctrine in-scope/out-of-scope split and the standards rule L doctrine-citation contract |
| 2 | Phase 1 | The transcript codec, hash-prefix lookup, and RNG plumbing register their CLI surface (`inspect list`, `inspect show`, `--cache-dir`, `--rng`) and their Plan/Apply discipline through the registry built in Phase 1 |
| 3 | Phase 2 | The Haskell engine writes transcripts in the wire format pinned by Phase 2 and consumes the `splitmix64(master_seed, game_index)` seed derivation |
| 4 | Phase 3 | The C ABI FFI bridge from Haskell to backend (i) reuses the `Subprocess` boundary and `Env` record established by Phases 1 and 3, and validates against the same transcript codec |
| 5 | Phase 3 | Backend (ii) likewise builds on the FFI bridge pattern; it is independent of (i) once the pattern is established, so Phases 4 and 5 may proceed in parallel after Phase 3 closes |
| 6 | Phase 5 | Backend (iii) shares (ii)'s optimisation stack and must be developed against the validated steelman; Sprint `6.7` removed backend (iii)'s legacy representation costs, and Sprint `6.8` completes Rust's hot-path structural alignment with the functional-core style contract |
| 7 | Phases 4, 5, 6 | Cross-backend `verify`, legacy parity, and the POC report card require all five backend slots to produce evidence |
| 8 | Phase 7 plus fail-closed Sprints `5.3`, `5.7`, `6.4`, and `6.7` | Performance parity closure requires report-card numbers against optimized backend (ii) after Dockerfile-time PGO/BOLT succeeds and the report card separates terminal playout, search-iteration, and played-game metrics; Phase `8` owns the restored five-backend live surface, Sprint `8.3` refreshed the report card against reclosed fail-closed build artefacts, Sprint `8.10` closed the historical played-game profile-representativeness gap, Sprint `8.11` closed the refactored metric rerun, Sprint `8.12` refreshed against the corrected backend (ii), Sprint `8.13` kept backend (v) aligned with the functional-core style after Sprint `6.7`, Sprint `8.14` made the report-card verdict an exit-code gate with the stable `N_PRIM=20_000` primitive sample, Sprint `6.8` closed Rust raw-performance/style cleanup, Sprint `5.7` closed the backend `(ii)` full hot-path steelman, and Sprint `8.15` closed the measurement-vs-invariant doctrine reframe plus the post-`5.7` `(ii)` rebaseline on 2026-05-28 |

## Current Baseline

The repository has a restored five-backend implementation baseline, and the
2026-05-21 evidence-surface audit reopened focused alignment work. Phase `1`
has reclosed generated-doc metadata enforcement and style-policy wording. Phase
`2` has reclosed strict v1 transcript/envelope wording, action-domain docs, and
sidecar identity. Phase `5` has reclosed backend (ii)'s compact C ABI contract
and C++ PGO/BOLT fail-closed behavior. Phase `6` has reclosed backend
(iii)/(iv) ABI wording, Rust build-artifact/instrumentation language, and Rust
PGO/BOLT fail-closed behavior. Phase `7` has reclosed replay and divergence labels.
Phase `8` has reclosed tuning-doc wording, the Sprint `8.3` report-card refresh
against mandatory Dockerfile-time PGO/BOLT artefacts, and the Sprint `8.10`
bounded played-game profile-training gate. The 2026-05-24 metric audit reopened
Sprint `3.8`, Sprint `7.8`, and Sprint `8.11`; all three have reclosed. Sprint
`5.6` then reopened Sprint `8.12` for parity against the corrected backend (ii).
Sprint `6.7` has reclosed backend (iii)'s compact functional-core style
alignment, and Sprints `8.12`, `8.13`, and `8.14` have reclosed historical Haskell
parity, style follow-up, and report-card verdict gating. Sprint `6.8` has closed Rust
hot-path structural alignment without changing current Q3/Q6/Q7 correctness claims.
Sprint `7.10` has reclosed report-card table layout and raw
backend metric rendering. Sprint `7.11` has closed Q7 semantic parity and
normalized divergence-score reporting. Phase `4`
remains closed on its owned surface. Phase `0` Sprint `0.3` has restored the root
doctrine-link topology without reopening backend implementation phases.
Sprint `5.7` has closed backend `(ii)`'s full imperative hot-path steelman.
Sprint `8.15` closed on 2026-05-28 with the measurement-vs-invariant doctrine
reframe and the post-`5.7` `(ii)` rebaseline: the apples-to-apples invariants
Q3/Q4/Q6/Q7 hold, the labelled measurement is recorded honestly as
`Trails parity band by 52.3%`, and `mcts test all` exits 0. The earlier
pre-reframe rerun under the prior framing returned `Verdict: Shortfall 0.2678864950323545`; the Sprint
`8.14` `Within tolerance` verdict remains historical
evidence against the Sprint `5.6` backend `(ii)` artefact, not final handoff
evidence against the stronger Sprint `5.7` kernel.
Sprints `5.8`/`8.16`, `6.9`/`6.10`/`8.17`, `8.18`, and `8.19` then advanced
the current measurement surface: backend `(ii)` residual squeeze (`57.1%`),
functional-cohort hot-path closure plus measured/rejected Haskell arena migration
(`62.7%` post-`8.17`), accepted Arena `unsafeRead`/`unsafeWrite` recovery with
arm64/amd64 cross-host evidence (`85.6%` / `29.5%`), and a measured/rejected
Dockerfile-level aarch64 `-mcpu=apple-m1` unblock. Sprints `4.6`, `6.11`, and
`4.7` then unified the C++ build surface on `clang++-19`; the post-`4.7`
aggregate recorded `Verdict: Trails parity band by 69.1%` with Q3/Q4/Q6/Q7
PASS and `normalized_divergence_score=0.0000`.
Phase `1` Sprint `1.17` has reclosed self-describing CLI command-use text after
Sprint `1.13` reclosed value introspection.

| Surface | Current Repo State | Intended End State |
|---------|--------------------|--------------------|
| Repository layout | `app/`, `src/MCTS/`, `src/MCTS/Generated/`, `cpp-legacy/`, `cpp-imperative/`, `cpp-functional/`, `rust/`, `bench/`, `test/`, `docker/`, root `hostbootstrap.dhall`, `cabal.project`, `fourmolu.yaml`, `.hlint.yaml`, `.gitignore`, `.dockerignore`, `mcts.cabal`, generated-artefact targets `documents/cli/commands.md`, `share/man/man1/mcts.1`, and `share/completion/{bash,zsh,fish}/` | Same layout; no generated validation data required under `test/` and no checked-in PGO/BOLT profile snapshots |
| Build artefacts | `mcts.cabal` declares the `mcts` binary, live Haskell test stanzas, benchmark stanza, and the doctrine-standard dependency envelope; host validation enters through `hostbootstrap run check-code` under the pinned toolchain. The foreign backend tree is live for `cpp-legacy/`, `cpp-imperative`, `cpp-functional`, and `rust`; Dockerfile invokes the C++ and Rust PGO/BOLT Plan/Apply build recipes during image construction, and those recipes fail closed on missing profile data, missing `.fdata`, failed BOLT output, or a crashing installed bolted library. PGO/BOLT training uses the bounded metric-suite profile suite owned by Sprints `8.10` and `8.11`, including terminal playout, search-iteration, legacy played-game rollout, and self-play workloads; Sprint `5.7` retuned backend `(ii)` training after the action-only/SoA kernel rewrite. | Container-image `mcts` binary, installed Cabal test-suite executables, installed `mcts-criterion` benchmark executable, and image-local shared libraries for `cpp-legacy`, optimized `cpp-imperative`, optimized `cpp-functional`, and `rust` produced by `docker/Dockerfile`; runtime validation consumes those artefacts without rebuilding them, and steelman shared libraries exist only after successful Dockerfile-time PGO+BOLT trained on an accepted profile suite |
| CLI surface | The complete command family is wired: `bench`, `verify`, `verify legacy-parity`, `inspect`, `test`, `lint`, `docs`, `commands`, `help`, `check-code`, `build`, and `play`. Generated command docs are checked against the renderer, tracked generated-file drift fails `mcts lint files`, generated path/section registries live under `src/MCTS/Generated/`, parser topology is rendered from enriched `CommandSpec` metadata with explicit semantic leaf option parsers, and `mcts test all` routes recursive CLI calls through the installed image-local `mcts` binary. Sprint `1.13` closed the self-describing introspection surface: every leaf command exposes required inputs, defaults, accepted values, examples, parse-error remedies, JSON schema data, manpage data, and shell completions from one choice-aware registry. Sprint `1.17` closed the follow-up command-use surface: generated docs and focused help explain how to use `mcts play`, including backend identifiers, side ownership, and spectator mode. | Same surface backed by real C++/Rust/Haskell engines and fully self-describing introspection: bench/play/inspect dispatch through selected foreign backends when their shared libraries are present and the relevant ABI path can represent the run, Q3 covers `(ii)..(v)`, Q6 covers all five, Dockerfile-invoked build recipes exist for `cpp-legacy`, `cpp-imperative`, `cpp-functional`, and `rust`, `legacy-fixtures` remains explicit external audit-fixture generation, and every leaf command exposes required inputs, defaults, accepted values, action-oriented usage descriptions, examples, parse-error remedies, JSON schema data, manpage data, and shell completions from one choice-aware registry |
| Test stanzas | Six live Cabal stanzas currently exist: `mcts-unit`, `mcts-integration`, `mcts-cross-backend`, `mcts-legacy-parity`, `mcts-semantic-parity`, and `mcts-haskell-style`. Each stanza has its own `tasty` runner, Dockerfile prebuilds every test executable, `mcts-cross-backend` invokes real `mcts verify` subprocesses serially around the process-pinned dynamic-library and shared C++ RNG bridge path, and `hostbootstrap run test all` is the host validation gate under the pinned container toolchain. `mcts-unit` uses semantic/property/temp-dir checks instead of `tasty-golden`. | Keep all validation data generated in memory or temporary directories during the run, so clean-clone validation has no `test/golden/` prerequisite and no runtime test-stanza compilation |
| Toolchain | `mcts.cabal` pins `tested-with: ghc ==9.12.4`; `cabal.project` pins `with-compiler: ghc-9.12.4` and mirrors the report-card constants as comments. The formatter tools share the project GHC under Sprint `1.16`. | GHC `9.12.4`, Cabal `3.16.1.0` (Phase 1 reopen Sprint `1.14`), formatter tools (`fourmolu-0.19.0.1`, `hlint-3.10`) sharing the project GHC `9.12.4` at `/opt/hostbootstrap/haskell-style/bin/` (Sprint `1.16`), `clang++-19` for C++ backends `(i)`, `(ii)`, and `(iii)` (Sprints `4.6`, `5.9`, `6.11`), `llvm-profdata-19` for `(ii)`/`(iii)` LLVM PGO, Rust `1.95.0`, LLVM/BOLT `19`, and no first-class GCC backend build path after Sprint `4.7`. The toolchain layers are inherited from the hostbootstrap base image `docker.io/tuee22/hostbootstrap:basecontainer-cpu-<arch>` per [phase-9-hostbootstrap-adoption.md](phase-9-hostbootstrap-adoption.md); the project Dockerfile adds only what the base does not ship. |
| Determinism contract | Live C++ and Rust foreign backends dispatch through real FFI engines under `bench`, `play`, `inspect divergence`, Q3 `verify` when shared libraries are present and the fixed search-horizon ABI can represent the run, and Q6 `verify legacy-parity`; the integration stanza's direct live-FFI smoke cases are Rust-specific, with C++ live coverage carried by Q3/Q6/report-card surfaces. Transcript codec, full v1 envelope, process-pinned envelope and C++ RNG dynamic handles, SHA-256 content addressing, cache root resolution, prefix lookup, binary `MEQ1` equity sidecars, layered envelope checks, `divergenceVsEqStream`, compact foreign recompute/read-visits evidence surfaces, canonical search-side 12-wall child caps across the current live cohort, decoded real-binary transcript determinism, and hard-fail `VerifyMismatch` rollout/self-play cohorts in `mcts-cross-backend` are implemented. Sprints `2.8` and `7.6` tighten version handling and sidecar/recompute labeling. | Enforced by live-FFI-capable cross-backend `mcts verify {rollouts,selfplay}` over `(ii)..(v)`, decoded same-backend transcript checks, Rust live FFI-envelope cases under `mcts-integration`, and Q6 legacy-envelope checks across all five |
| Performance parity | Historical evidence is retained by sprint, but the current implementation has moved beyond the Sprint `8.15` `52.3%` rebaseline: Sprint `8.16` recorded the post-`5.8` backend `(ii)` measurement (`57.1%`), Sprint `8.17` measured and rejected the `MutableByteArray#` arena migration (`62.7%` aggregate after revert), Sprint `8.18` accepted `unsafeRead`/`unsafeWrite` Arena helpers and recorded cross-host evidence (`85.6%` on Apple Silicon Docker arm64, `29.5%` on caledon amd64), Sprint `8.19` measured and rejected the Dockerfile-level `-mcpu=apple-m1` unblock after a `-51%` Haskell Q1b ST regression, and the post-`4.7` unified-clang aggregate recorded `Verdict: Trails parity band by 69.1%`. All accepted aggregate runs keep Q3/Q4/Q6/Q7 PASS with `normalized_divergence_score=0.0000`; the verdict line remains an informational measurement label. | Honest Q1a/Q1b/Q2 measurement of Haskell (v) against fully-optimised live C++ (ii) recorded per [Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine), single-threaded and on 8 workers where applicable, without checked-in generated throughput anchors. The apples-to-apples invariants Q3/Q4/Q6/Q7 plus a non-pending measurement are the sole closure gate; matching the parity band is not required for closure. |

## Related Documents

- [README.md](README.md)
- [development_plan_standards.md](development_plan_standards.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
- [../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md)
- [../README.md](../README.md)
