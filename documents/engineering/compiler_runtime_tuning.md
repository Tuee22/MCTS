# Compiler and Runtime Tuning

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md, ../../DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md, ../../DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md, ../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md, ../../DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md, ../documentation_standards.md, ./README.md, ./backend_ffi_contract.md, ./backend_style_contract.md, ./benchmark_metrics.md, ./semantic_parity_contract.md, ./unit_testing_policy.md
**Generated sections**: none

> **Purpose**: Authoritative spec of the per-backend compiler, RTS, and code-level
> tuning stacks: the backend (i) verbatim exemption, the backend (ii)/(iii)
> doctrine-flag set with PGO+BOLT+`mimalloc`, the functional-core style boundary
> owned by `backend_style_contract.md`, the backend (iv) Rust `[profile.release]`,
> the backend (v) Haskell GHC/LLVM/RTS stack, and the
> mandatory Dockerfile-time bounded PGO/BOLT training contract plus Haskell PGO
> asymmetry note.

This document owns its content. The toolchain pin (GHC `9.12.4`, Cabal `3.16.1.0`
per Phase 1 reopen Sprint `1.14`; see
[../../DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md](../../DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md)
for the hostbootstrap base image whose warm Cabal store this pin matches) is
doctrine-owned; the per-backend tuning stacks are project-specific.

## Doctrine Pointers

- [../../HASKELL_CLI_TOOL.md → Toolchain pinning](../../HASKELL_CLI_TOOL.md) — GHC
  `9.12.4` and Cabal `3.16.1.0` are the pinned versions for the Haskell binary.
- [../../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed
  Values](../../HASKELL_CLI_TOOL.md) — supported build harnesses invoke toolchains
  through typed `Subprocess` values. The Dockerfile invokes the Rust and steelman
  C++ PGO/BOLT `mcts build <backend>` leaves during image construction; see
  [../../DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md](../../DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md).
- [../../HASKELL_CLI_TOOL.md → Plan / Apply](../../HASKELL_CLI_TOOL.md) — the
  `mcts build <backend>` leaves remain Plan/Apply recipes with `--dry-run` and
  `--plan-file <path>` for Dockerfile use and focused diagnostics.

Normal host validation enters through
`docker compose run --rm mcts mcts <command>` and consumes Dockerfile-built Cabal
components plus backend artefacts. Rebuild the image with the same one-shot Compose
shape, for example
`docker compose run --rm --build mcts mcts test all --dry-run`. Direct host
toolchain use is unsupported.

## PGO/BOLT Training Workload Doctrine

The accepted Cabal components and steelman C++ and Rust artefacts are built once
during `docker/Dockerfile` image construction. Runtime commands do not compile Cabal
test executables, retrain PGO, rerun BOLT, switch between per-workload optimized
shared libraries, or install fallback artefacts. The supported runtime contract is
one prebuilt Cabal component cache plus one canonical bolted shared library per
foreign steelman backend, generated from the Dockerfile-owned profile pipeline.

The profile workload is not fully automatic. The build harness must run the binary
through workload examples that resemble the project questions being optimized. Per
[benchmark_metrics.md](./benchmark_metrics.md), the final suite must distinguish
terminal playout throughput, search-iteration throughput, and played-game
throughput. The Dockerfile training suite therefore includes all three metric
families:

- direct `bench terminal-playouts` batches and direct `bench search-iters` batches;
- the legacy-named `bench rollouts` workload, which remains a played-game batch with
  one search iteration per real move, plus MCTS self-play;
- single-threaded and `--threading multi --workers 8` batches;
- `--rng native`, because Q1/Q2 headline throughput uses backend-native RNG;
- fixed deterministic seeds rather than only seed `42`;
- report-card primitive playout caps (`--max-plies 60`) for primitive training;
- a bounded played-game ply cap during profile generation (`--max-plies 1`), with
  self-play simulation budgets representative of `S_BENCH = 500` for PGO.

BOLT may use a shorter version of the same workload shape to keep image builds
practical, but its `.fdata` must still come from the Dockerfile build. Missing PGO
profile data, failed profile merge, missing BOLT `.fdata`, failed BOLT optimization,
or a crashing installed library is an image-build failure.

Current implementation baseline: `src/MCTS/CLI/Build.hs` trains PGO/BOLT with the
bounded suite above. PGO uses terminal playout and search-iteration primitive runs
with `--count 64` and `--max-plies 60`; BOLT uses the same primitive shape with
`--count 16`. Both PGO and BOLT also train the legacy played-game rollout workload
and self-play, ST plus MT8, native RNG, seeds `42` and `424242`, and
`--max-plies 1`. PGO uses two rollout games for each threading mode per seed with
rollout `--sims 1` and one self-play game for each threading mode per seed with
self-play `--sims 500`; BOLT uses one rollout game and one self-play game for each
threading mode per seed, rollout `--sims 1`, and self-play `--sims 100`. C++
training uses scoped dynamic-library loading plus exported profile-dump hooks so
the profile data is flushed before `-fprofile-use`: backends (ii) cpp-imperative
(Sprint 5.9) and (iii) cpp-functional (Sprint 6.11) both build with `clang++-19`
and call `__llvm_profile_write_file`/`__llvm_profile_reset_counters` to flush
`.profraw` files that are then merged via `llvm-profdata-19 merge` into a single
`default.profdata`. Rust training keeps the cdylib pinned and relies on
process-exit `.profraw` emission before `llvm-profdata merge`.

Sprint `5.7` closed backend `(ii)` profile representativeness for the rewritten
kernel. The earlier suite remains accepted for the Sprint `5.6` `FastBoard` and
full-node arena artefact, while the post-`5.7` action-id generation, absolute
side-to-move state, action-only or split hot/cold tree storage, and trusted
internal buffers define the current `(ii)` training target. Runtime commands still
consume one canonical bolted shared library and never select workload-specific
optimized libraries.

## Backend (i) — `cpp-legacy` (Exempt)

Backend (i) is **exempt** from the optimisation stack. (i) is strictly verbatim
from `MCTS_legacy`; only FFI shims are permitted per
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item 17](../../DEVELOPMENT_PLAN/00-overview.md).

Build flags from the legacy: `-std=c++17 -O3 -fPIC -Wall`. It uses
`std::shared_ptr<uct_node>` trees and `std::mt19937_64` unchanged. No
`-march=native`, no `-flto`, no `mimalloc`, no BOLT, no PGO.

Backend (i) is the regression-sanity port, **not** the performance ceiling. The
project hypothesis is proven when backend (v) Haskell matches backend (ii) — not
(i) — on the refactored Q1/Q2 metrics defined in
[benchmark_metrics.md](./benchmark_metrics.md).

## Backend (ii) and (iii) — C++ Imperative and Functional-Core

Sprint `5.9` (2026-05-29 compiler audit) pivoted backend `(ii)`
cpp-imperative from `g++` to `clang++-19` after the audit showed
`clang++-19 -O3 -flto` matched or exceeded `g++` with the full PGO+BOLT
pipeline on cpp-imperative (+8.9% Q1a ST, +10.2% Q1b ST, +22.5% Q1b
MT8). Sprint `6.11` (2026-05-30) then pivoted backend `(iii)`
cpp-functional onto the same `clang++-19` stack and migrated its PGO
half from GCC `.gcda` (`-fprofile-correction` etc.) to LLVM
`.profraw` → merged `.profdata`, mirroring the cpp-imperative
mechanics. `src/MCTS/CLI/Build.hs::cppProfileStyleFor` now maps both
`cpp-imperative` and `cpp-functional` through `CppLlvmProfile` so a
single LLVM `pgo-merge` flow drives the two PGO+BOLT backends.
Sprint `4.6` (same date) flipped backend `(i)` cpp-legacy onto
`clang++-19` for harness alignment; cpp-legacy has no PGO+BOLT path
(it is the verbatim regression-sanity backend).

### Backend (ii) — clang++-19 stack (Sprint 5.9)

```text
# Example: mandatory C++ compile flags for backend (ii)
-std=c++23 -O3 -march=native -mtune=native -flto -fno-plt
-fno-semantic-interposition -fvisibility=hidden -fvisibility-inlines-hidden
-fno-exceptions -fno-stack-protector -fno-rtti
```

The GCC-only `-fipa-pta` flag is dropped; clang rejects it and the audit
measurement did not show it carrying the (ii) baseline either way. The linker
adds `-fuse-ld=lld` so BOLT consumes the same `--emit-relocs` shape used by
backend (iv) Rust. The 2026-05-29 audit also collapsed the prior
`State { FastBoard b; uint16_t ply_count; }` wrapper into a flat
`FastBoard { ...; uint16_t ply_count; }` (matching backend (iii) and (iv)'s
32 B descent state) so the per-simulation copy in `descend_iterative` is no
longer paying a 25% padding tax versus the other steelman backends.

PGO file format changes from GCC's `.gcda` to clang's `.profraw`; the
`cpp-imperative/Makefile` adds a `pgo-merge` target that runs
`llvm-profdata-19 merge -o $(PGO_DIR)/default.profdata <profraw files>` and
the subsequent `pgo-{bench,instr}-use` stages consume the merged
`.profdata` file via `-fprofile-use=…/default.profdata`. The
`-fprofile-correction` flag is dropped (GCC-only). BOLT stages are unchanged:
LLVM BOLT operates on the linked artefact independent of which front-end
produced it.

Sprint `5.10` (2026-05-29) re-ran the PGO+BOLT-vs-no-PGO+BOLT A/B against
the clang-built (ii) artefact and decided to **keep** the pipeline. The
per-cell lift was mixed but concentrated on the parallel hot path where
throughput matters most:

| Cell | clang+PGO+BOLT | clang -O3 -flto | Lift |
|------|---------------:|----------------:|-----:|
| Q1a ST (playouts/s) | 38,349 | 39,589 | −3.1% |
| Q1b ST (search-iters/s) | 41,745 | 42,262 | −1.2% |
| Q1a MT8 (playouts/s) | 262,339 | 230,570 | **+13.8%** |
| Q1b MT8 (search-iters/s) | 281,209 | 261,632 | **+7.5%** |
| Q2 ST (games/s) | 2.0 | 2.1 | −5.0% (at 0.1 games/s measurement floor) |
| Q2 MT8 (games/s) | 7.5 | 7.6 | −1.3% (at 0.1 games/s measurement floor) |

The arithmetic mean of +1.8% is below the Sprint `5.10` plan threshold of
+3% for "keep", but the per-cell picture justifies an override: the MT8
primitive cells lift +13.8% and +7.5% (well above noise), while the ST
cells fall within ±3% (typical run-to-run noise on these primitives) and
the Q2 cells differ by 0.1 games/s (measurement-resolution floor). Sprint
`5.10` closes with PGO+BOLT retained; the ~5 min Dockerfile build cost is
paid by the MT8 wins on the workloads the cohort actually optimizes for.
The decision is recorded against the Sprint `5.9` clang baseline; if the
front-end pivots again or BOLT's layout passes drift, the A/B should be
re-run.

### Backend (iii) — clang++-19 stack (Sprint 6.11)

```text
# Example: mandatory C++ compile flags for backend (iii)
-std=c++23 -O3 -march=native -mtune=native -flto -fno-plt
-fno-semantic-interposition -fvisibility=hidden -fvisibility-inlines-hidden
-fno-exceptions -fno-stack-protector -fno-rtti
```

`-fno-exceptions` is mandatory for the C++ steelman backends: the engine core
does not throw, so landing-pad cost is unconditional dead weight. Sprint `5.8`
added two additional scrub flags under per-flag focused-benchmark gating that
backend (iii) adopted in Sprint `6.9`: `-fno-stack-protector` removes the SSP
cookie write because no untrusted input crosses the hot path, and `-fno-rtti`
removes unreachable RTTI metadata because `dynamic_cast` and `typeid` are not
used on the search hot path. Sprint `6.11` dropped the GCC-only `-fipa-pta`
flag from the (iii) flag set because clang rejects it and the Sprint `5.9`
audit measurement showed it was not load-bearing on the (ii) baseline either
way. The linker adds `-fuse-ld=lld` so BOLT consumes the same `--emit-relocs`
shape used by backend (ii) cpp-imperative and backend (iv) Rust.

PGO file format (Sprint `6.11`): backend (iii) now emits clang `.profraw`
files alongside backend (ii), and `cpp-functional/Makefile`'s `pgo-merge`
target runs `llvm-profdata-19 merge -o $(PGO_DIR)/default.profdata <profraw
files>` so the subsequent `pgo-{bench,instr}-use` stages consume the merged
`.profdata` file via `-fprofile-use=…/default.profdata`. The
`-fprofile-correction` flag is dropped (GCC-only). The
`cpp-functional/c-abi/mcts_cpp_functional.cc` C ABI shim calls
`__llvm_profile_write_file`/`__llvm_profile_reset_counters` to flush
`.profraw` files for the training step (the `__gcov_dump`/`__gcov_reset`
fallback is retained under `#if !defined(__clang__)` for any future
host-diagnostics build).

### Shared constraints

**Excluded deliberately for both (ii) and (iii):** `-ffast-math`, `-Ofast`.
Equity backprop is summation-order-sensitive and we want backend-internal
determinism even though equity is excluded from the cross-backend wire format.

The style boundary for `(iii)` is owned by
[backend_style_contract.md](./backend_style_contract.md). In this document,
"functional-core" never permits a slower legacy representation as the measured
variable. Backend (iii) must keep the C++ steelman optimization stack while using
compact value-state operations, typed action IDs, local scratch mutation, and a
functional-core API/data-flow shape.

### Build Workflow

The C++ Plan/Apply command surface is first-class, but Dockerfile-owned in normal
operation. During image construction, `docker/Dockerfile` invokes
`mcts build cpp-imperative` and `mcts build cpp-functional` to drive the steelman
PGO/BOLT targets below through typed `Subprocess` plans and install the canonical
shared libraries. Manual use of those leaves is diagnostic; normal validation and
benchmarking consume the image-built artefacts and do not rebuild them at runtime.
Optional audit artifacts may be regenerated, but normal validation does not require
checked-in generated data.

1. **Two-stage PGO.** Instrumented build via
   `-fprofile-generate=$(abspath $(PGO_DIR))`; the generated `_bench` and
   `_instrumented` artefacts are build/training intermediates for the bounded
   played-game training suite so profile data exists before the optimized
   build runs with `-fprofile-use=…`. Backends (ii) and (iii) both build with
   `clang++-19` (Sprints `5.9` and `6.11`) and emit `.profraw` files; each
   Makefile's `pgo-merge` target runs `llvm-profdata-19 merge` to produce
   `$(PGO_DIR)/default.profdata` and the optimized build consumes that file
   path via `-fprofile-use=…/default.profdata`. The `-fprofile-correction`
   flag is dropped (GCC-only). Neither set of intermediates is a supported
   runtime FFI load name.
2. **BOLT post-link.** `llvm-bolt -instrument` produces `_bench.inst.so` /
   `_instrumented.inst.so` build intermediates for a shorter bounded
   played-game training suite. `llvm-bolt -reorder-blocks=ext-tsp` consumes
   the resulting `.fdata`. Sprint `5.8` extends backend `(ii)`'s BOLT optimize
   step with `-split-functions -split-strategy=cdsplit` (cache-driven hot/cold
   split), `-reorder-functions=cdsort` (cache-directed function ordering;
   the modern replacement for the deprecated `hfsort+`), and `-icf=1`
   (identical-code folding; LLVM 19's BOLT takes a boolean here, not the
   legacy `safe` value) on top of the existing `-reorder-blocks=ext-tsp`.
   The flag-name correction from `hfsort+`/`safe` to `cdsort`/`1` was made
   on the first Sprint `5.8` validation rebuild when the image build failed
   on `'safe' is invalid value for boolean argument! Try 0 or 1`. The
   extended set is gated by focused (ii) benchmarks and reverted on
   focused-row regression. The `.fdata` files are
   mandatory Dockerfile build outputs; a missing file, failed BOLT invocation,
   or attempt to copy a PGO-only/unoptimized artefact to a `.bolted.so` or
   canonical load name must fail the image build. LLVM objcopy patches the
   `engine_build_id` section on BOLT-produced shared objects, and the installed
   bolted libraries must pass a smoke run before the image is published.
3. **`mimalloc` link.** The current C++ Makefiles link the system `libmimalloc`
   library supplied by the container. Static linking is not required by the current
   build surface.
4. **Install.** The backend (iii) pipeline installs the final bolted
   `cpp-functional/build/libmcts_cpp_functional.so` at the canonical FFI load
   name. The C++ Makefiles may retain `_bench` / `_instrumented` outputs for
   training and investigation, but verify/play/replay load the canonical shared
   library named in
   [./backend_ffi_contract.md → Backends and Linkage](./backend_ffi_contract.md)
   rather than a parallel `_instrumented` runtime artefact.

Current implementation baseline: the Dockerfile uses the C++ Plan/Apply surface
backed by the shared `cppPgoBoltPlan` in `src/MCTS/CLI/Build.hs`. The plan resets
profile directories, builds and trains `_bench` and `_instrumented` PGO artefacts,
runs BOLT instrument/training/optimize steps, and installs the canonical shared
library. The 2026-05-23 reclosure makes that sequence fail closed when
`llvm-bolt` cannot produce usable `.fdata`, uses LLVM objcopy for post-BOLT
envelope patching, and smokes the installed bolted libraries. Sprint `8.10`
added the bounded profile suite described in
[PGO/BOLT Training Workload Doctrine](#pgobolt-training-workload-doctrine) to that
mandatory sequence. Sprint `5.6` replaces backend (ii)'s legacy-board hot path
with `FastBoard`, a compact scalar/bitfield board that emits capped legal moves
directly and checks wall escapability with bitset wavefront expansion.

Sprint `5.7` closed backend `(ii)`'s full hot-path steelman. The compiler flag,
allocator, and fail-closed PGO/BOLT requirements above remain necessary but are not
by themselves the steelman proof; the closed target is fixed-capacity action-id
legal generation, absolute side-to-move board state instead of per-child full-board
flips, action-only or split hot/cold MCTS tree layout, precomputed/reused wall
conflict and block masks, trusted internal apply/visit buffers that avoid replay
allocation, and a post-rewrite PGO/BOLT profile suite. The public compact C ABI
remains the governed runtime boundary.

### Code-Level Requirements

Grouped by priority for the C++ steelman backends. Top-tier items are
non-negotiable; the rest are required unless profiling shows the change is
neutral or harmful.

**Top tier** (each expected 1.5–3× over the legacy baseline):

1. **Arena-allocated tree** with `u32` child indices. One contiguous
   `std::vector<uct_node>` per game, expanded in place, freed in bulk at game
   end. Eliminates refcount traffic, double indirection, per-node destruction,
   and most cache misses during tree descent.
2. **Compact board state and direct capped move generation.** The C++ steelman hot
   path must not generate the full legacy wall set and parse action strings before
   applying the report-card wall cap. It stores the hot state in scalar pawn/wall
   fields plus 8x8 wall bitfields, emits numeric action IDs directly, and checks
   wall escapability with bitset wavefront expansion. Backend (ii) implements this
   through `FastBoard`; backend (iii) implements the same representation class as
   compact functional-core value state without copying (ii)'s imperative API
   shape.
3. **Per-rollout scratch board with undo or one snapshot per game.** Eliminates
   the per-rollout `board_copy` allocation.
4. **PGO + BOLT pipeline** as named above.

**Correctness requirement** (also top tier):

- **`Word16` ply counter in board state.** `is_terminal` ↔
  `hero_wins || villain_wins || ply_count >= max_plies`; `terminal_eval` returns
  `0.0` on ply-cap termination. Part of the compact snapshot/undo path. See
  [determinism_contract.md → Ply-Cap Draw Rule](./determinism_contract.md#ply-cap-draw-rule).

**Second tier** (each 10–30%, cumulative):

5. **Flat children layout** — children stored contiguously in the arena; each
   parent records `first_child_idx: u32` and `n_children: u16`. No
   `std::vector<u32>` per node.
6. **Move-list buffer reuse.** Move generators write into a `thread_local` or
   stack-SBO buffer; no per-call `std::vector`. Inline buffer sized for typical
   Corridors move counts (~40); heap spill allowed but rare.
7. **`u32` parent index** rather than `shared_ptr<uct_node>`.
8. **Visit-count compression to `u16`** when `per_move_sims < 65536`. Shrinks
   node footprint, more nodes per cache line. The header's `per_move_sims`
   field gates the choice; the wire format already records visits as `u32`, so
   the in-memory choice is transparent to the determinism contract.

**Third tier** (sub-10% each, cumulative):

9. `[[likely]]` / `[[unlikely]]` on UCT child-selection and terminal-state
   branches.
10. `__attribute__((hot))` / `__attribute__((always_inline))` on
   `select_best_child`, `apply_move`, `is_terminal`, `rollout_step`.
11. `__attribute__((const))` / `((pure))` on referentially-transparent helpers
    — lets GCC hoist and CSE.
12. `__builtin_prefetch` on the child array during UCT descent.
13. `__builtin_popcountll` / `__builtin_ctzll` on raw `u64` bitboards rather
    than `std::bitset<64>::_Find_first()` (not reliably lowered to `tzcnt`).
14. `alignas(64)` on the tree-node arena base; struct-of-arrays where
    measurement supports it.
15. `thread_local` scratch buffers for the multi-threaded driver (per-worker,
    not per-game).

`-fno-exceptions` is promoted to the mandatory flag block at the top of this
section: the engine core does not throw, so landing-pad cost is unconditional
dead weight.

**Native-RNG benchmark only** (not under `--rng cpp`, which is pinned to the
C++-generated verification-seed contract by the determinism contract):

16. Future profiling candidate: replace the current splitmix-compatible live
    schedule with `xoshiro256++` or `wyrand` where it measurably helps — smaller
    state, faster `next_u64`, equivalent statistical quality for rollouts.

### Backend (iii) Functional-Core Discipline

Observes **all** of the above. The "functional-core style" of (iii) is at the API
and data-flow level, *not* the memory-representation level: arena allocation,
compact bitfields, and mutable scratch state are still required. Both C++
steelman backends run under the same optimisation regime so `(iii)` vs `(ii)`
isolates style: Sprint `6.7` removed backend (iii)'s legacy-board and
action-text hot-path residue and moved the cleanup ledger entry to completed in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

#### Sprint 6.9 Backend (iii) Hot-Path Shape Alignment

Sprint `6.9` adopts the remaining permitted backend (ii) techniques inside the
backend (iii) functional-core boundary:

- **Absolute `SideToMove` field on `State`.** The per-transition full-state
  flip in `flipped_after_move()` is dropped; transitions toggle `SideToMove`
  and leave coordinates / wall bitfields untouched. Canonical action ID
  semantics, Q3 visit payload bit-equality, and transcript wire format are
  preserved. Mirrors `cpp-imperative/engine/fast_board.hpp` Sprint `5.7`.
- **Reusable `BlockMasks` precomputed once per `legal_actions`.** Wall
  candidates run against `add_wall_to_masks(trial_masks, candidate)` plus two
  `path_exists_with_masks(side)` calls. No per-candidate 56-byte `State` copy
  and no inline mask recomputation. Mirrors
  `cpp-imperative/engine/fast_board.hpp::block_masks` /
  `add_wall_to_masks` Sprint `5.7`.
- **Bidirectional bit-parallel BFS in `path_exists_with_masks`.** Two
  simultaneous `unsigned __int128` frontiers (from start cell and from goal
  row) with intersect-or-extinct termination. Mirrors Sprint `5.8`. The
  bidirectional improvement is small on 9x9 Quoridor (≤9 BFS steps) but keeps
  the three steelman backends symmetric so cohort comparisons stay clean.
- **Action-only `UctNode`; `State` materialized on the descent stack.** The
  node footprint drops to `parent_idx`, `first_child_idx`, `n_children`,
  `action_id`, `visit_count`, `q_sum`, `expanded`, `terminal`. Search keeps a
  `State current` and a fixed-capacity `path` buffer through descent. Backprop
  walks the recorded path. Mirrors backend (ii) `arena.hpp` Sprint `5.7`.
- **`cpp-functional/Makefile` flag and BOLT scrub parity with Sprint `5.8`.**
  Add `-fno-stack-protector -fno-rtti -fipa-pta` to the C++ functional flag
  block. Extend BOLT invocation with `-split-functions -split-strategy=cdsplit
  -reorder-functions=cdsort -icf=1` on top of the existing
  `-reorder-blocks=ext-tsp`. The shared `cppPgoBoltPlan` in
  `src/MCTS/CLI/Build.hs` already drives both C++ backends with the same flag
  set, so no harness change is required.

The expected evidence is not a new parity question. Q3/Q4/Q6/Q7 continue to own
correctness. The new evidence is focused native-RNG Q1a/Q1b/Q2 raw performance
for `cpp-functional` against `cpp-imperative`, `rust`, and `haskell`, plus the
aggregate gates required by Phase `6`. Sprint `6.9` does not change the
visit-payload contract, the C ABI, or the functional-core boundary.

## Backend (iv) — Rust

`Cargo.toml` `[profile.release]` per
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item 19](../../DEVELOPMENT_PLAN/00-overview.md):

```toml
# Example: rust/Cargo.toml release profile stanza
[profile.release]
opt-level = 3
lto = "fat"
codegen-units = 1
panic = "abort"
strip = "debuginfo"
```

`RUSTFLAGS`:

```text
-C target-cpu=native -C link-arg=-B/usr/lib/llvm-19/bin -C link-arg=-fuse-ld=lld -C link-arg=-Wl,--emit-relocs
```

### Build Workflow

During image construction, `docker/Dockerfile` invokes the `mcts build rust`
Plan/Apply leaf:

- **Two-stage PGO** via
  `RUSTFLAGS="-C target-cpu=native -C link-arg=-B/usr/lib/llvm-19/bin
  -C link-arg=-fuse-ld=lld -C link-arg=-Wl,--emit-relocs -C
  profile-generate=/workspace/MCTS/rust/pgo-profile"` → bounded metric-suite training
  suite → hard-failing `llvm-profdata merge` into
  `rust/pgo-profile/merged.profdata` → `RUSTFLAGS="-C target-cpu=native -C
  link-arg=-B/usr/lib/llvm-19/bin -C link-arg=-fuse-ld=lld -C
  link-arg=-Wl,--emit-relocs -C
  profile-use=/workspace/MCTS/rust/pgo-profile/merged.profdata"`.
- **BOLT** post-link: temporarily install the BOLT-instrumented copy of the PGO
  cdylib at the canonical FFI load name for a shorter bounded metric-suite training run,
  restore the PGO cdylib, then optimize with `-reorder-blocks=ext-tsp` when
  `.fdata` exists. Missing `.fdata` or a failed BOLT invocation must fail the
  Dockerfile build; copying the PGO cdylib as a fallback is forbidden. This is
  training instrumentation only; the supported Rust contract publishes one
  optimized `libmcts_rust.so`, not a separate `_instrumented` artefact. The
  installed bolted cdylib is patched with LLVM objcopy and smoked before the image
  is published.
- **`mimalloc`** as `#[global_allocator]` through the container system library and
  the local `SystemMiMalloc` wrapper.

Current implementation baseline: the Dockerfile-owned Rust build validates the
pinned Rust toolchain, inherited subprocess environment, absolute profile paths,
the `lld` linker flag in both PGO Cargo builds, profile merge guard, canonical
install path `rust/target/release/libmcts_rust.so`, local `SystemMiMalloc` global
allocator, LLVM objcopy post-link `engine_build_id` patching, and final installed
cdylib smoke inside the pinned amd64 container. Like C++, Rust trains on the
bounded metric-suite profile suite. Sprint `6.8` closes Rust's implementation
shape gap against `(iii)` and `(v)` without changing the build envelope.

### Code-Level Requirements

- **`u16` ply counter in board state** (correctness — see
  [determinism_contract.md → Ply-Cap Draw Rule](./determinism_contract.md#ply-cap-draw-rule)).
  Board carries a `u16` ply counter; `is_terminal` returns `true` on
  `ply >= max_plies` with eval `0.0`. Part of the per-rollout snapshot/undo
  path.
- Tree as `Vec<Node>` with `u32` child indices, mirroring the C++ arena.
- Search arena capacity reserves the full child-bound shape, equivalent to
  `1 + root_children + sims * 16`, so ordinary searches do not reallocate and copy
  node/state vectors.
- Path-existence checks use `u128` wavefront masks over the 9x9 grid. The old
  queue-based iterative BFS shape remains only historical Sprint `6.3` closure
  context.
- Legal-action generation uses stack or packed fixed-capacity action buffers for the
  pawn-plus-12-wall action set. Per-rollout `Vec` allocation is not part of the
  target Rust hot path.
- The optional `read_visits` cache belongs inside the Rust board handle, mirroring
  the C++ handle-local cache shape; the old global synchronized map is historical
  Sprint `6.8` cleanup residue, and **Sprint `6.10` finishes the relocation** by
  removing the `last_visit_len`, `last_visit_actions`, and `last_visit_counts`
  fields from `MctsRustBoard` and moving them onto the opaque handle declared in
  `rust/src/c_abi.rs`.
- `#[inline(always)]` on hot leaf operations, `#[cold]` on error and terminal
  paths.
- `core::hint::unreachable_unchecked` where a precondition genuinely guarantees
  it; each use documented.
- Bit ops via `u64::count_ones` / `u64::trailing_zeros` (lower to the same
  `popcnt` / `tzcnt` as the C++ builtins).
- No `Rc` / `Arc` in the hot path. No `Box<dyn Trait>` in the search.
- **Absolute `SideToMove` field on `MctsRustBoard`.** The per-transition
  `*self = self.flipped()` reassignment is dropped; transitions toggle
  `SideToMove`. Mirrors Sprint `6.9` backend (iii) and Sprint `5.7` backend (ii).
- **Reusable `BlockMasks` precomputed once per `legal_actions`.** Wall-candidate
  legality runs against an additively-extended `BlockMasks` value, eliminating
  the 196-byte `MctsRustBoard` clone in `wall_placement_legal`. Mirrors Haskell
  `src/MCTS/Engine.hs::blockMasks` / `addWallIdToMasks`.
- **Bidirectional bit-parallel BFS in `path_exists_with_masks`.** Mirrors
  Sprint `6.9` backend (iii) and Sprint `5.8` backend (ii).

### Sprint 6.8 Rust Hot-Path Refactor

Sprint `6.8` makes backend (iv) use the same structural hot path as the
already-aligned `(iii)` and `(v)` implementations:

- `rust/src/board.rs` replaces queue BFS path checks with the bit-parallel wavefront
  masks used by `(iii)` and `(v)`;
- `rust/src/search.rs` replaces per-rollout and per-expansion heap `Vec<u8>` action
  buffers with a fixed-capacity action buffer;
- Rust search arenas reserve to the same child-bound formula used by C++ and Haskell;
- expansion/descent avoids unnecessary board clones while preserving value-state
  semantics;
- optional visit-vector cache state moves from the global synchronized map into the
  opaque Rust board handle in `rust/src/c_abi.rs`.

The expected evidence is not a new parity question: Q3/Q6 continue to own correctness.
The new evidence is focused native-RNG Q1a/Q1b/Q2 raw performance for `rust` against
`cpp-functional` and `haskell`, plus the aggregate gates required by Phase `6`.

### Sprint 6.10 Rust Hot-Path Shape Alignment

Sprint `6.10` extends the Sprint `6.8` cleanup with the remaining permitted
backend (ii)/(iii) shape items that still apply to backend (iv):

- **Visit-cache relocation onto the opaque handle.** Remove `last_visit_len`,
  `last_visit_actions: [u8; 16]`, and `last_visit_counts: [u32; 16]` (169 bytes)
  from `MctsRustBoard` in `rust/src/board.rs`. Add the same triple to the opaque
  handle struct in `rust/src/c_abi.rs`. `apply_action` no longer clears a
  search-board cache; the per-rollout and per-wall-candidate copy paths shed the
  169-byte tail. This closes the style-contract violation noted in
  [./backend_style_contract.md → Backend (iv) Rust Target](./backend_style_contract.md).
  The C ABI symbol set, including `mcts_rust_read_visits`, is unchanged.
- **Absolute `SideToMove` enum on `MctsRustBoard`.** Drop `flipped()` and
  `*self = self.flipped()` from `apply_action_flip`; toggle the new field. Pawn
  coordinates and wall bitfields stay in absolute hero-frame storage; canonical
  action ID semantics are preserved by the same `flip_action_id` helper.
- **Reusable `BlockMasks` in `legal_actions`.** Port the additive mask pattern
  used by backend (v) Haskell and the Sprint `6.9` backend (iii) target.
  `wall_placement_legal` no longer clones `MctsRustBoard`.
- **Bidirectional bit-parallel BFS over `u128`.** Mirrors Sprint `5.8` backend
  (ii) and Sprint `6.9` backend (iii).
- **Action-only secondary `Vec` in `tree.rs`.** With the `last_visit_*` fields
  removed and the `SideToMove` toggle replacing the per-transition flip, the
  parallel `Vec<MctsRustBoard>` shrinks per element. Reserve to the existing
  child-bound formula.
- **Inlining and unreachable hints audit.** `#[inline(always)]` on
  `apply_action_flip`, `legal_actions`, `path_exists_with_masks`, the rollout
  body, and the descent body. `#[cold]` on terminal and early-exit paths.
  `core::hint::unreachable_unchecked` after the precondition-checked action-id
  decoding sites, each with a single-line `// safety:` comment.

The expected evidence is not a new parity question. Q3/Q4/Q6/Q7 continue to own
correctness. The new evidence is focused native-RNG Q1a/Q1b/Q2 raw performance
for `rust` against `cpp-functional` and `haskell`, plus the aggregate gates
required by Phase `6`. Sprint `6.10` does not change the visit-payload contract
or the C ABI symbol set.

## Backend (v) — Haskell

GHC flags (in `cabal.project` or per-library stanza) per
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item 20](../../DEVELOPMENT_PLAN/00-overview.md):

```cabal
-- Example: cabal ghc-options stanza for backend (v)
ghc-options:
  -O2 -fllvm
  -funbox-strict-fields
  -fspecialise-aggressively
  -fexpose-all-unfoldings
  -flate-dmd-anal
  -fmax-simplifier-iterations=20
  -fworker-wrapper
  -fstatic-argument-transformation
```

The doctrine target allows native CPU tuning through `-optlo-mcpu=native`
(LLVM `opt`) and `-optlc-mcpu=native` (`llc`). The current implementation does
not enable those two flags: they remain deferred on the documented aarch64
assembler limitation below. LLVM itself is still active through `-fllvm`, and
the LLVM version is pinned in `docker/Dockerfile` so codegen is reproducible.

#### Currently landed (Phase 8 Sprint 8.9 baseline)

The performance-relevant `mcts.cabal` library, executable, and benchmark stanzas
carry the full doctrine flag list including `-fllvm`:

```
-O2
-fllvm
-funbox-strict-fields
-fspecialise-aggressively
-fexpose-all-unfoldings
-flate-dmd-anal
-fmax-simplifier-iterations=20
-fworker-wrapper
-fstatic-argument-transformation
```

The Cabal test-suite stanzas carry the same warning and optimization envelope but
do not duplicate `-fllvm` in their own `ghc-options`. They compile small test
runners that link against the already optimized library code; duplicating `-fllvm`
there would slow validation without changing the backend (v) hot path being tested.
The `mcts-haskell-style` stanza is likewise a validation runner, not performance
evidence.
`docker/Dockerfile` explicitly builds those test runners before the image is
published so `mcts test all` executes prebuilt stanzas rather than compiling them
on first use.

`-optlo-mcpu=native` and `-optlc-mcpu=native` remain deferred on aarch64 on
two load-bearing grounds. **First**, the documented assembler limitation:
enabling them inside the pinned container emits LSE / `rcpc-immo` instructions
that binutils-2.42 rejects (Sprint `8.18` Stage 2 confirmed with four
cabal-only attempts; see
[../../bench-profiles/stage2-result.md](../../bench-profiles/stage2-result.md)).
**Second**, a Haskell-runtime regression: Sprint `8.19`
[§ Sprint 8.19 aarch64 mcpu resolution](#sprint-819-aarch64-mcpu-resolution)
worked around the assembler limitation with a wrapper-routed Approach A and
measured a **-51% Haskell-only regression** on Q1b ST (arm64 verdict
`85.6% → 268.7%`) because LSE / `rcpc-immo` atomics emitted by
`llc-19 -mcpu=apple-m1` execute slower than the baseline ARMv8 LL/SC atomics
GHC's RTS was tuned against under Docker-on-Apple-Silicon — the cohort
C++/Rust backends are unaffected (rules out broader side-effects). The
deferral therefore stands not only on toolchain compatibility but on
Haskell-specific runtime behaviour that is not fixable from this project's
toolchain side. See
[../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md → Sprint 8.19](../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md#sprint-819-dockerfile-level-aarch64-toolchain-unblock-)
Closure Notes for the full measurement table. GHC's LLVM backend uses the pinned
LLVM toolchain carried by `docker/Dockerfile`. `INLINABLE` pragmas
are landed on the hot path: every primitive in `MCTS.Search.Arena`,
`MCTS.Search.UCT`, `MCTS.Rng.Mix`, and the exported engine functions
in `MCTS.Engine` (`legalMoves`, `applyMove`, `isTerminal`,
`terminalOutcome`, `terminalWinner`). The rollout inner loop calls
`terminalOutcome`, which returns a strict `Float` sentinel (`1.0` hero
win, `-1.0` villain win, `0.0` draw, `nonTerminalOutcome = 2.0`) and
therefore avoids allocating through the public `Maybe Winner`
`terminalWinner` API on each rollout step.

### RTS Tuning

Baked into the executable's `ghc-options`:

```cabal
-- Example: cabal ghc-options RTS-tuning stanza
-with-rtsopts=-A64m -n4m -qg1 -qb -T
```

This is landed in `mcts.cabal`'s `executable mcts` stanza as
`-threaded "-with-rtsopts=-A64m -n4m -qg1 -qb -T"` so users do not need
`+RTS … -RTS` on the command line.

Large nursery to push major GC out, `-qg1` so major GC is parallel from
generation 1, `-qb` for load balancing across capabilities, `-T` to expose GC
stats for `+RTS -s` profiling.

Backend (v) uses **GHC's built-in RTS allocator**. Alternate allocators
(e.g., `mimalloc` via `LD_PRELOAD`, `jemalloc`, etc.) are **out of scope**
for backend (v): it is the pure-Haskell baseline and replacing the allocator
would muddy the GHC-as-shipped parity claim. `mimalloc` static-linking
applies to backends (ii), (iii), (iv) only — see
[../../DEVELOPMENT_PLAN/system-components.md](../../DEVELOPMENT_PLAN/system-components.md).

### Sprint 8.17 Backend (v) MutableByteArray# Arena and INLINE Audit

Sprint `8.17` lands the only headroom item left on backend (v) inside the
contracts owned by this document and
[./backend_style_contract.md](./backend_style_contract.md):

- **`MutableByteArray# s`-backed SoA arena.** `src/MCTS/Search/Arena.hs`
  replaces the six parallel `STUArray` slabs with a single
  `MutableByteArray# s`. Per-field offsets are named constants; reads and writes
  go through `primitive` ops; the SoA layout itself (parent, firstChild,
  numChildren, actionId, visits, valueSum) is preserved at the byte level.
  Eliminates five extra header words per logical row and consolidates the six
  array address registers into one.
- **Descent / rollout `INLINE` audit.** Confirm `pathExistsWithMasks` and the
  per-side helpers carry the inlining the descent/rollout call sites in
  `src/MCTS/Search/UCT.hs` require. Add specialization only where GHC's
  monomorphic-call-site inference does not pick it up.
- **`-optlo-mcpu=native` / `-optlc-mcpu=native` remain deferred** under the
  aarch64 assembler limitation already documented above; Sprint `8.17` does not
  enable them.

The Sprint `8.15` ledger of rejected candidates in
[../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md](../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md)
is read-only; no rejected candidate is reintroduced. If focused benches show
the `MutableByteArray#` migration regresses Q1a/Q1b on the post-`6.10` cohort,
the sprint records that result in the same "measured but rejected" pattern
and reverts the migration. Q3/Q4/Q6/Q7 continue to gate closure; the verdict
line remains informational per
[Performance Measurement Doctrine](#performance-measurement-doctrine).

### Sprint 8.18 Backend (v) Arena unsafeRead/unsafeWrite

Sprint `8.18` Stage 1 swapped the eight `MCTS.Search.Arena` read/write
helpers from `Data.Array.ST.{readArray,writeArray}` to
`Data.Array.Base.{unsafeRead,unsafeWrite}` indexed by
`fromIntegral nid :: Int`. The arena's callers in `MCTS.Search.UCT`
produce indices via `firstChild + i` arithmetic where `0 <= i <
numChildren` and the cursor monotonically grows to a pre-computed
capacity; indices are provably in-range, so the bounds checks that
`Data.Array.ST` emits are pure overhead. Post-change the eight Arena
helpers fully inline into the UCT descent path; `UCT.descend$w` shrinks
from 456 B to 92 B on arm64 (no standalone `Arena.addVisitValue` /
`readVisits` / etc. symbols remain in the binary). Focused 3-rep
arm64 Q1a ST: `+7.97%` (22881.9 → 24705.1 playouts/s); amd64 within
±2-4% noise. Validation: `mcts test all` PASS on both hosts;
Q3/Q4/Q6/Q7 PASS; `normalized_divergence_score=0.0000`. See
[../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md → Sprint 8.18](../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md#sprint-818-profile-driven-arm64-recovery-)
for the full investigation (cross-platform A/B with caledon amd64
host, four ledgered recovery attempts beyond Stage 1, asm-level
verification).

### Sprint 8.19 aarch64 mcpu resolution

Sprint `8.19` closed 2026-05-30 with the Dockerfile-level aarch64
mcpu unblock **measured but rejected**. The wrapper-routed
Approach A (`docker/Dockerfile` installs a 7-line
`/usr/local/bin/clang-19-aarch64-apple-m1` wrapper exec'ing
`clang-19 -mcpu=apple-m1`; GHC's `$GHC_LIB/settings` patched so
both `("C compiler command", ...)` and **`("LLVM llvm-as command",
...)`** route through the wrapper; `mcts.cabal` re-adds
`if arch(aarch64) ghc-options: -optlo-mcpu=apple-m1
-optlc-mcpu=apple-m1`) successfully unblocks the build:
binutils-2.42 no longer rejects the LSE / `rcpc-immo` atoms because
they are now assembled by clang's integrated assembler under
`-mcpu=apple-m1`. The build passes `mcts test all` with Q3/Q4/Q6/Q7
PASS and `normalized_divergence_score=0.0000` preserved.

**Empirical lesson on GHC -fllvm assembly stage routing.** Patching
only `("C compiler command", ...)` (pgm_c) is **not sufficient** —
GHC's `-fllvm` LLVM-assembler stage invokes the `LLVM llvm-as
command`, not pgm_c, for `.s → .o`. `-opta-*` flags also do not
propagate to that stage. Both settings entries must be patched to
route through the wrapper.

**Performance verdict: rejected.** Even with the unblock working
correctly at the code-generation level, the measurement on
Docker-on-Apple-Silicon recorded a **-51% Haskell-only** regression:

| Metric             | Sprint `8.18` arm64 | Sprint `8.19` arm64 | Δ          |
|--------------------|--------------------:|--------------------:|-----------:|
| Q1a ST ratio       | `1.60x`             | `3.46x`             | +116%      |
| Q1b ST ratio       | `1.63x`             | `3.53x`             | +117%      |
| Q2 ST ratio        | `1.49x`             | `3.19x`             | +114%      |
| Haskell Q1b ST     | `~24779`            | `12195.2`           | **-51%**   |
| Verdict            | `85.6%`             | `268.7%`            | worse      |

Cohort C++/Rust rates were within ±3% of Sprint `8.18` (rules out
broader toolchain side-effects); the regression is **Haskell-only**.
The cause: LSE / `rcpc-immo` atomics emitted by `llc-19
-mcpu=apple-m1` execute slower than the baseline ARMv8 LL/SC atomics
GHC's RTS was tuned against under Docker-on-Apple-Silicon. GHC's
RTS atomic-heavy code (capability scheduling, MVar wakeups,
thread-local storage, allocator-block locking) is the load-bearing
path; cohort C++/Rust backends, which were already compiled with
clang `-march=native -mtune=native` and thus already use LSE/rcpc,
are unaffected.

**Result.** `docker/Dockerfile` and `mcts.cabal` reverted to
byte-identical pre-`8.19` state. The Sprint `8.18` Stage 1 accepted
change in `src/MCTS/Search/Arena.hs`
(`Data.Array.Base.unsafeRead`/`unsafeWrite`) remains in effect.
The aarch64 mcpu deferral above now has two load-bearing reasons
(assembler limitation + Haskell-runtime regression); arm64 recovery
beyond Sprint `8.18` Stage 1 requires upstream GHC/LLVM/RTS work
outside this project's control. See
[../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md → Sprint 8.19](../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md#sprint-819-dockerfile-level-aarch64-toolchain-unblock-)
Closure Notes for the full validation/measurement record.

### Sprint 8.2 — Profile-Driven Hot-Path Tuning Rounds

The historical `mcts-criterion` benchmark stanza in `mcts.cabal` records per-call
cost for the four hot primitives. Normal supported benchmarking enters through the
Compose-wrapped `mcts bench` command surface.

| Round | Date | Change | Module | Before (μs/op) | After (μs/op) | Outcome |
|-------|------|--------|--------|---------------:|--------------:|---------|
| 1 | 2026-05-16 | `pathExists` / `shortestDistance` migrated from list-based `seen` (O(n²) `elem` / `notElem`) to `Data.IntSet` (O(n log n)); added `INLINABLE` pragmas on both | `src/MCTS/Engine.hs` | 991.5 (legal-moves initial), 1817 (uct-search sims=64) | 160.1 (legal-moves initial), 291.7 (uct-search sims=64) | ~6.2× speedup |
| 2 | 2026-05-16 | Tried strict-pair `Word64` (one for cells 0..63, one for 64..80) backing `pathExists`'s visited set | `src/MCTS/Engine.hs` | 160.1 (legal-moves initial), 291.7 (uct-search sims=64) | 164.1 (legal-moves initial), 410.9 (uct-search sims=64) | Regression — reverted. Constructor reconstruction at each recursive `go` step matched or exceeded the `IntSet` tree-insert path. |
| 3 | 2026-05-16 | Wavefront-bitmap BFS over a strict-pair `Word64` (`Bits128`) frontier with precomputed direction-block masks. Replaces the list-based recursive descent entirely with bitwise shift+and+or expansion per BFS wave | `src/MCTS/Engine.hs` | 160.1 (legal-moves initial), 291.7 (uct-search sims=64) | 3.099 (legal-moves initial), 8.932 (uct-search sims=64) | **~52× speedup** on legal-moves, **~33× speedup** on uct-search vs round 1. Combined with round 1, total speedup vs original list-based baseline is **~320× on legal-moves** and **~200× on uct-search**. |

The legal-moves cost falls because `legalMoves` invokes `pathExists` once per
candidate wall placement (up to 12 per move) — the per-call BFS dominates the
search inner loop. Round 1 takes the rollout's per-step cost from ~1 ms to
~160 μs without changing API or correctness; `mcts test all` stays green.

### Code-Level Requirements

- **`Word16` ply counter in board state** (correctness). Board carries a
  `Word16` ply counter; `isTerminal` returns true on `ply >= maxPlies` with
  eval `0.0`. Lives in the same unboxed board record as the bitboards;
  restored as part of the per-rollout `ST`-arena snapshot path.
- Engine hot path lives in `ST s`. The Sprint `8.13` baseline used six parallel
  structure-of-arrays `STUArray` slabs of unboxed fields. Sprint `8.17` lands
  the hand-rolled `MutableByteArray# s` arena migration: one mutable byte array
  holds the SoA layout (parent, firstChild, numChildren, actionId, visits,
  valueSum) at named per-field offsets, with `primitive` read/write
  primitives. The pure boundary, `INLINABLE` density, and rollout sentinel
  contract are unchanged.
- Board state is `Word64` bitboards, manipulated with `Data.Bits` (compiles to
  efficient bit operations under the active `-fllvm` backend; the extra native
  LLVM CPU flags remain deferred as described above).
- Strict fields everywhere (`{-# UNPACK #-} !Int`), bang patterns on `let`
  bindings inside `ST` blocks.
- `INLINE`/`INLINABLE` on exported hot-path primitives according to call-site
  size: small cross-module operations such as `terminalOutcome`, `applyActionId`,
  and `terminalPlayout` are force-inlined, while larger engine/search entries keep
  exposed unfoldings for specialization. `SPECIALIZE` pragmas are not needed in
  the current search loop because it is already monomorphic over the concrete
  `Board` and `Word64` types; if a future refactor introduces a polymorphic game
  type, the specialisations land with that change.
- Pure API at the boundary: `search :: GameState -> Seed -> SearchBudget ->
  Tree -> (Move, Tree)`. `Tree` is opaque; internally backed by the `ST` arena
  and frozen at the API boundary if tree-persistence semantics need it.
- No `Maybe` or `Either` in the rollout inner loop; sentinel values or unboxed
  sum representations instead.

## arm64 Performance Gap Anatomy

The Sprint `8.18` cross-platform investigation
(`bench-profiles/diagnosis-final.md`) established that the
backend-(v)-Haskell-vs-cohort gap on Q1a/Q1b primitive throughput
is **dramatically wider on arm64 than on amd64**, and Sprint `8.19`
proved the residual is not recoverable from this project's
toolchain or Haskell-source side. This section is the SSoT
explanation of that gap. The Sprint `8.17` / `8.18` / `8.19`
sub-sections above are the per-sprint implementation records; this
section is the cause-and-effect synthesis.

### Quantified gap

Same `docker/Dockerfile`, same GHC `9.14.1`, same LLVM `19`, same
`clang-19`, measured on the post-Sprint-`8.18` baseline image:

| Cohort vs Haskell, Q1a ST | arm64 ratio | amd64 ratio | gap_arm64_specific |
|---------------------------|------------:|------------:|-------------------:|
| cpp-imperative            | `1.63x`     | `1.27x`     | `0.36` (44% of gap) |
| cpp-functional            | `1.72x`     | `1.22x`     | `0.50` (69% of gap) |
| **rust**                  | **`1.77x`** | **`1.12x`** | **`0.65` (84% of gap)** |

Post-Sprint-`8.18` `mcts test all` verdicts: arm64
`Trails parity band by 85.6%`, amd64
`Trails parity band by 29.5%` (Q1b MT8 `1.06x` — essentially
parity; **Q5 MT8 Haskell search scaling `6.36x` outperforms
backend (ii)'s `5.38x`**). On amd64 Haskell is within `12%` of
Rust on Q1a ST; on arm64 the same source is `77%` slower than
Rust. The recoverable surface targeted by Sprints `8.18` and
`8.19` was the 65-percentage-point arm64-specific delta on the
headline Q1a ST / Rust ratio.

### Five contributing factors

The arm64-specific gap has **five distinct mechanisms**, each
load-bearing. Removing any one would shrink the gap measurably;
removing all five would close it. Sprint `8.18` source-level work
addressed factor (1); Sprint `8.19` proved factor (2) is not
recoverable from this project's side; factors (3), (4), (5) require
upstream GHC / LLVM / RTS work.

#### Factor 1 — Per-Arena-access bounds-check overhead (RECOVERED, +5pp arm64)

`Data.Array.ST`'s `readArray`/`writeArray` emit array-bounds checks
on every read and write. Visible in the captured arm64 asm of
`MCTS.Search.Arena.addVisitValue` as 5-6 `cmp/setg/setl/test/b.gt`
instructions out of ~16 total in the hot-path body; identical
pattern with x86 mnemonics on amd64. The MCTS descent's
`firstChild + i` arithmetic produces indices that are provably
in-range (`0 ≤ i < numChildren`; cursor monotonically grows to a
pre-computed capacity), so the bounds checks are pure overhead.

**Sprint `8.18` Stage 1** swapped the eight Arena helpers to
`Data.Array.Base.unsafeRead` / `unsafeWrite` indexed by
`fromIntegral nid :: Int` (see
[Sprint 8.18 sub-section above](#sprint-818-backend-v-arena-unsafereadunsafewrite)).
Post-change, GHC fully inlines the Arena helpers into the UCT
descent path; `UCT.descend$w` shrinks from 456 B to 92 B on arm64;
no standalone `Arena.addVisitValue` / `readVisits` / etc. symbols
remain in the binary. Focused 3-rep arm64 Q1a ST: `+7.97%`
(22881.9 → 24705.1 playouts/s); amd64 within ±2-4% noise (already
absorbed by amd64's wider OoO and CISC density). Within-Mac
cohort/Haskell ratio: cpp-imperative/haskell `1.570x → 1.542x`
(~5 percentage points of the 65pp recovered).

#### Factor 2 — Deferred aarch64 `-mcpu=apple-m1` for GHC's LLVM pipeline (NOT RECOVERABLE)

GHC's LLVM pipeline on aarch64 defaults to baseline ARMv8 codegen
because pinning `-optlc-mcpu=apple-m1` causes `llc-19` to emit LSE
(`ldadd`, `swpl`, `cas`) and `rcpc-immo` (`ldapur`) atomics that
binutils-2.42's `as` rejects. Sprint `8.18` Stage 2 confirmed the
mechanism with four cabal-only sub-variants
(`-mcpu=apple-m1` with `-opta-mcpu`, `-opta-march=armv8.5-a`,
`-mattr=-lse,-rcpc,-rcpc-immo`, and `-mtune=` in opt and llc
forms); see `bench-profiles/stage2-result.md` for the per-variant
ledger. Meanwhile, clang and rustc inside the same image *do*
take `-march=native -mtune=native` and emit ARMv8.5+ (M-series)
instructions freely — the cohort backends collect the M-series
codegen win; backend (v) does not.

**Sprint `8.19` Approach A** worked around the assembler limitation
with a Dockerfile-installed 7-line
`/usr/local/bin/clang-19-aarch64-apple-m1` shell wrapper exec'ing
`/usr/bin/clang-19 -mcpu=apple-m1 "$@"`, plus a GHC `settings`
patch routing both `("C compiler command", ...)` (pgm_c) **and**
`("LLVM llvm-as command", ...)` through the wrapper. The second
patch was load-bearing — GHC's `-fllvm` LLVM-assembler stage uses
`LLVM llvm-as command`, not `pgm_c`, for `.s → .o`, and silently
drops any `-opta-*` flags. With both patched, the build completed
with `mcts test all` Q3/Q4/Q6/Q7 PASS and
`normalized_divergence_score=0.0000` preserved. **The measurement
rejected the change** — see
[Sprint 8.19 sub-section above](#sprint-819-aarch64-mcpu-resolution).
Net effect: arm64 verdict regressed `85.6% → 268.7%`; Haskell Q1b
ST `~24779 → 12195.2` search-iters/s (**-51%**); cohort C++/Rust
rates within ±3% (rules out broader side-effects). The deferral
therefore stands on **two** load-bearing grounds:

1. The original binutils-2.42 assembler rejection
   (toolchain-fixable in principle by a newer binutils or the
   wrapper, but only after factor 3 is addressed).
2. The Haskell-runtime regression from factor 3 below
   (**not** toolchain-fixable from this project's side).

#### Factor 3 — GHC RTS atomics tuned to LL/SC, not LSE (NOT RECOVERABLE from project side)

GHC's runtime system (capability scheduling, MVar wakeups,
thread-local storage barriers, allocator-block locking, garbage
collector stop-the-world coordination) is implemented with atomic
operations whose performance characteristics are tuned to the
baseline ARMv8 load-linked / store-conditional (LL/SC) primitives.
When `llc -mcpu=apple-m1` lowers those atomic operations to LSE
(`ldadd`, `swpl`, `cas`) or `rcpc-immo` (`ldapur`) instructions
instead — instructions which are architecturally *supposed* to be
faster — the resulting Haskell binary runs **measurably slower**
under Docker-on-Apple-Silicon. Sprint `8.19` quantified this as a
`-51%` Q1b ST regression with no change to the user-facing hot
loop (cohort backends already use LSE/rcpc via clang/rustc
`-march=native` and are unaffected; the regression is Haskell-only
and isolated to the RTS atomic path).

The probable cause is the Docker-on-macOS host-OS layer's
emulation or trap behaviour for these instruction encodings; bare
ARMv8.5 silicon (e.g., a native macOS process or a non-Docker
Linux on the same chip) would likely show the expected LSE
speedup. This project does not optimise for bare-metal arm64; the
supported workflow runs in Docker per `CLAUDE.md`, and that's
where the measurement lives. Recovering this requires either a
patched GHC RTS that uses LL/SC even under `-mcpu=apple-m1`, an
LLVM build with different atomic lowering heuristics, or a base
image whose virtualisation layer doesn't penalise these
instructions — all upstream work.

#### Factor 4 — GHC LLVM aarch64 codegen maturity (NOT RECOVERABLE from project side)

GHC's primary x86_64 test surface has been tuned for decades.
aarch64 LLVM output has historically had rougher edges in register
allocation (around `Float` ops crossing GPR↔NEON banks), NEON
instruction selection, and code-density-driven scheduling.
Sprint `8.18` Stage 3 (`STUArray s NodeId Float` → `STUArray s
NodeId Word32` + bitcast) tested the GPR↔NEON-bank hypothesis
directly; the change is bit-identical at the LLVM-IR level
(register-class promotion eliminates the hypothesised crossings)
and measured `+0.04%` arm64 / `-0.4%` amd64 — within noise.
That rules out the specific bank-crossing mechanism but leaves
broader codegen-maturity factors (less aggressive instruction
selection, larger emitted code per Haskell function, weaker
branch-prediction-friendly scheduling) that show up as ~10-18%
larger Haskell hot-loop bodies on arm64 vs amd64 in absolute byte
size (per the asm symbol-size inventory in
`bench-profiles/{arm64-local,amd64-caledon}/uct-arena-hotloop.asm`).
Recovery requires upstream GHC work on the LLVM aarch64 backend.

#### Factor 5 — Apple Silicon microarchitecture amplification (NOT RECOVERABLE)

M-series chips have wide (8-wide) decode and large reorder
buffers. This amplifies codegen-quality differences: already-good
clang/rustc output benefits more than middling GHC-LLVM output.
The same codegen-quality delta shows up smaller on amd64's
narrower-pipeline server-class chip. This is also why x86 CISC
density (memory-operand instructions like
`incl 0x10(%r8,%rax,4)` — single insn — vs arm64 `ldr/add/str` —
three insns — on every visit-count increment) closes some of the
gap on amd64 that opens it on arm64. Not actionable; constraint
on what is theoretically recoverable rather than something
fixable.

### What's NOT a contributor (ruled out empirically)

- **GC/allocator overhead.** `+RTS -s` recorded **99.3% productivity
  on arm64** and **99.7% on amd64**; GC time 0.0-0.3% of total. The
  `-A64m -n4m -qg1 -qb -T` RTS tuning has absorbed the 558 MB heap
  traffic (Board + ActionIds per rollout step) on both platforms.
- **LLVM version asymmetry.** GHC 9.12.4 uses `llc-19` / `opt-19`
  (LLVM 19.1.1), same major version as `clang-19`. Confirmed via
  `ghc --info | grep -i llvm`. (Historical Sprint `8.18` measurement
  was recorded under GHC `9.14.1`; the LLVM major-version invariant is
  preserved by Phase 1 reopen Sprint `1.14`'s pin to `9.12.4`.)
- **Rejected-ledger candidates from Sprints `8.15` / `8.17` /
  `8.18`.** Iterative descent, single-buffer `MutableByteArray#`
  arena, strict `quotRem` index decode, direct wall-bit-index
  apply, forced splitmix inlining, bulk arena child reservation,
  GHC NCG (`-fasm`), rollout worker-wrapper (asm-justified skip),
  `Float`→`Word32` arena bitcast — all measured-but-rejected or
  asm-skipped. None of these would close the arm64-specific delta
  because their mechanisms are platform-agnostic.

### Honest residual

After Sprint `8.18` Stage 1, the arm64 verdict is `~83-86%`
(Trails parity band; verdict-line variance within doctrine noise).
The 65-percentage-point arm64-specific surface decomposes as:

| Component                                  | Status                              | Recovery |
|--------------------------------------------|-------------------------------------|---------:|
| Factor 1 (bounds-check overhead)           | Recovered by Sprint `8.18` Stage 1  | ~5pp     |
| Factor 2 (mcpu unblock, code-gen side)     | Recoverable but **counter-productive** under Factor 3 | 0pp |
| Factor 3 (RTS atomic / LSE mismatch)       | Upstream GHC RTS work               | n/a      |
| Factor 4 (aarch64 LLVM codegen maturity)   | Upstream GHC work                   | n/a      |
| Factor 5 (microarch amplification)         | Architectural constraint            | n/a      |

The post-`8.18` measurement is the **honest current state**: arm64
`Trails parity band by ~85%`, amd64 `Trails parity band by ~30%`,
both with Q3/Q4/Q6/Q7 PASS and
`normalized_divergence_score=0.0000`. Further arm64 recovery
beyond Sprint `8.18` Stage 1 requires either (a) upstream GHC
work on aarch64 LLVM codegen + RTS atomic tuning, or (b) a
different runtime substrate (bare-metal Linux instead of
Docker-on-macOS) that does not penalise LSE/`rcpc-immo` atomics.
Neither is in scope for this project. The Performance Measurement
Doctrine (below) preserves Q3/Q4/Q6/Q7 as the closure gates so
this honest measurement does not block closure of `mcts test
all`; the verdict line records it honestly.

## PGO Asymmetry

GHC `9.14` has no production-grade profile-guided optimisation comparable to
GCC/Clang `-fprofile-use` or `rustc -Cprofile-use`. The Haskell backend
therefore competes against container-built C++ and Rust artefacts that completed
their mandatory PGO+BOLT workflows without an equivalent Haskell feedback loop.
This asymmetry does not permit PGO-only, non-BOLT, or unoptimized foreign
artefacts. Missing BOLT data is always a build failure; Sprint `8.11` produced
historical metric-suite evidence after the Dockerfile build trained primitive
terminal-playout, primitive search-iteration, legacy played-game rollout, and
self-play workloads. Sprint `8.12` then refreshed the verdict against the
corrected Sprint `5.6` backend (ii) target.

This is the asymmetry that most concretely tests the project hypothesis. The
hypothesis the report card answers is: *does pure Haskell, with no production
PGO loop, match maximally-optimised C++ on Quoridor MCTS?* Either answer is an
acceptable scientific outcome. Shortfalls in the 5–15% band are plausibly
attributable to the missing PGO loop rather than to any property of pure
functional code per se; larger shortfalls remain honestly recorded with the
same attribution where appropriate and surface focused tuning work in the next
steelman sprint when the project chooses to invest further. GHC's lack of
production PGO is the dominant remaining explanatory variable when Haskell
trails fully-optimized C++.

The Phase `8` report card records the result honestly for the then-current
fail-closed artefacts: the verdict line summarises whether the worst Q1a/Q1b/Q2
ratio sits inside or outside the labelling threshold below. The verdict line
does **not** gate closure — see [Performance Measurement Doctrine](#performance-measurement-doctrine)
for the closure contract. Sprint `8.10` closed the stricter fail-closed played-game
gate: the same labelled measurement after the C++ and Rust PGO/BOLT profiles are
trained on the bounded profile suite. Sprint `8.11` extends that suite with
direct primitive training and records refactored metric evidence; Sprint
`8.12` refreshed that measurement against the corrected backend (ii).

### Sprint 8.3 — Historical Played-Game Q1 Snapshot

After Sprint 8.2 round 3 (wavefront-bitmap BFS, 2026-05-16):
`mcts bench rollouts --threading single --rng native --games 100 --seed 42`
inside the pinned container, wall-clock median of three runs. The command name is
legacy: this measured complete games with one search iteration per move, not
terminal `playouts/s`.

| Backend | Q1 ST wall (s) — round-1 baseline | Q1 ST wall (s) — round-3 wavefront | Q1 ratio vs cpp-imperative (round-3) |
|---------|----------------------------------:|-----------------------------------:|-------------------------------------:|
| cpp-legacy      | 6.555 | 0.674 | 0.75 |
| cpp-imperative  | 0.625 | 0.904 | 1.00 |
| cpp-functional  | 0.626 | 0.704 | 0.78 |
| rust            | 1.236 | 1.266 | 1.40 |
| **haskell**     | 6.724 | **0.804** | **0.89** |

The Haskell-vs-cpp-imperative Q1 ST ratio collapses from **10.76×**
(`Shortfall 9.76`) at the round-1 baseline to **0.89×** after the
wavefront BFS lands. At this single Q1 ST datapoint Haskell is *faster*
than the historical non-PGO cpp-imperative smoke library. That smoke evidence made
the full report-card measurement plausible, but it is not current parity closure.

### Sprint 8.3 — Measured Q2 Selfplay Snapshot

`mcts bench selfplay --threading single --rng native --games 4 --seed 42 --sims N`
inside the pinned container, wall-clock single-run:

| Sims  | cpp-imperative (s) | haskell (s) | Ratio (haskell / cpp-imperative) |
|------:|------------------:|------------:|-------------------------------:|
| 100   | 1.535 | 1.794 | 1.17× |
| 500   | 5.674 | 5.839 | 1.03× |
| 1000  | 10.672 | 12.090 | 1.13× |

At `sims = 500` Haskell sits within 3% of cpp-imperative — inside the
`HASKELL_PARITY_TOLERANCE = 0.05` parity-band label per
[Performance Measurement Doctrine](#performance-measurement-doctrine). At
`sims = 1000` the gap widens to 13%, in the 5–15% PGO-attributable band per
[PGO Asymmetry](#pgo-asymmetry); the report card records the measurement
honestly with the PGO attribution either way.

### Sprint 8.3 — Historical Played-Game Q1 MT8 Snapshot

`mcts bench rollouts --threading multi --workers 8 --rng native --games N --seed 42`
inside the pinned container, wall-clock median. This is the same legacy played-game
workload, not terminal playout throughput:

| Games | cpp-imperative (s) | haskell (s) | Ratio (haskell / cpp-imperative) |
|------:|------------------:|------------:|-------------------------------:|
| 200   | 1.84 | 1.21 | **0.66×** (Haskell faster) |
| 1000  | 6.58 | 5.74 | **0.87×** (Haskell faster) |

The Q1 MT8 snapshot also shows Haskell at parity-or-better with the
historical non-PGO cpp-imperative smoke library after Sprint 8.2 round 3. GHC's
multi-core RTS pin (`-A64m -n4m -qg1 -qb -T`) helps the Haskell
backend scale across 8 workers without lock contention; the
cpp-imperative smoke library is single-process with no thread-local
optimization beyond the `thread_local` move buffer.

### Sprint 5.3 / 6.4 / 8.3 PGO+BOLT Status

The live Rust and C++ backend install surfaces are fail-closed. On linux/amd64
and linux/arm64, the
Dockerfile-invoked `rustPgoBoltPlan` in `src/MCTS/CLI/Build.hs` completes cargo
`-Cprofile-generate` with `-C target-cpu=native -C
link-arg=-B/usr/lib/llvm-19/bin -C link-arg=-fuse-ld=lld -C
link-arg=-Wl,--emit-relocs`, the bounded PGO training run,
`llvm-profdata merge`, `-Cprofile-use` with the same target CPU/linker/relocation
flags, BOLT instrumentation/training, canonical install, LLVM objcopy
`engine_build_id` patching, and a final installed-library smoke. The C++ Makefiles
contain the corresponding PGO/BOLT target surface for `cpp-imperative` and
`cpp-functional`; `cppPgoBoltPlan` drives that sequence through the
Dockerfile-invoked `mcts build cpp-imperative` and `mcts build cpp-functional`
leaves, and the installed bolted C++ libraries are smoked before the image is
published. Sprints `5.3` and `6.4` removed branches that published PGO-only or
unoptimized fallback artefacts when BOLT data was missing.

On architectures where BOLT cannot instrument the shared libraries or cannot produce
usable `.fdata`, the Dockerfile build fails. That is a supported fail-closed result,
not a reason to publish a PGO-only cdylib or C++ shared library at the canonical
location.

That status proves the PGO/BOLT pipeline is mandatory, fail-closed, and trained on
the bounded profile suite.

The optimized-C++ Sprint 8.10 verdict was refreshed on 2026-05-23 by
`docker compose run --rm --build mcts mcts test all` against the canonical workload
(`N_PRIM=20_000`, `P_MAX=60`, `G_R=1_000`, `G_S=4`, `S_BENCH=500`, MT8 variants)
and bounded-profile Dockerfile-built canonical artefacts. The Dockerfile build
produced C++ and Rust BOLT profiles, bolted canonical shared libraries, LLVM
objcopy-patched envelopes, and passing final installed-library smokes before the
report card ran. The earlier 2026-05-21 run where C++ BOLT yielded no `.fdata`
remains historical fallback evidence only, and the Sprint `8.3` fail-closed run
is historical pipeline evidence superseded by Sprint `8.10`.
Q1/Q2/Q5 use the production monotonic clock through the primitive benchmark
runners and the no-write played-game batch runner rather than the former
zero-valued test stub or transcript-retaining benchmark subprocesses. The rows
below are historical played-game evidence from Sprint `8.10`; they remain useful
integration data. Sprint `8.11` supersedes them with the fresh refactored rerun
with terminal `playouts/s`, `search-iters/s`, and played-game `games/s` rows.

| Row | Ratio | Evidence |
|-----|------:|----------|
| Q1 legacy played-game ST | 0.05x | Haskell 646.7 games/s vs cpp-imperative 35.1 games/s |
| Q1 legacy played-game MT8 | 0.48x | Haskell 556.0 games/s vs cpp-imperative 269.4 games/s |
| Q2 self-play ST | 0.06x | Haskell 0.5 games/s vs cpp-imperative 0.0 games/s |
| Q2 self-play MT8 | 0.21x | Haskell 0.5 games/s vs cpp-imperative 0.1 games/s |
| Q5 Haskell MT scaling | 0.99x | 0.5 -> 0.5 games/s |
| Q5 cpp-imperative MT scaling | 3.65x | 0.0 -> 0.1 games/s |

The optimized-C++ Sprint 8.11 verdict was refreshed on 2026-05-24 by
`docker compose run --rm --build mcts mcts test all` against the refactored metric
surface and the bounded metric-suite Dockerfile-built canonical artefacts. The
Dockerfile build trained terminal-playout primitives, search-iteration primitives,
legacy played-game rollout batches, and self-play batches before publishing the
bolted shared libraries.

| Row | Ratio | Evidence |
|-----|------:|----------|
| Q1a terminal playout ST | 0.07x | Haskell 7166.6 playouts/s vs cpp-imperative 482.6 playouts/s |
| Q1a terminal playout MT8 | 0.39x | Haskell 9072.2 playouts/s vs cpp-imperative 3512.4 playouts/s |
| Q1b search-iteration ST | 0.06x | Haskell 9509.7 search-iters/s vs cpp-imperative 531.0 search-iters/s |
| Q1b search-iteration MT8 | 0.40x | Haskell 9709.2 search-iters/s vs cpp-imperative 3906.6 search-iters/s |
| Q2 self-play ST | 0.05x | Haskell 0.6 games/s vs cpp-imperative 0.0 games/s |
| Q2 self-play MT8 | 0.17x | Haskell 0.6 games/s vs cpp-imperative 0.1 games/s |
| Q5 Haskell search-iteration scaling | 1.02x | 9509.7 -> 9709.2 search-iters/s |
| Q5 cpp-imperative search-iteration scaling | 7.36x | 531.0 -> 3906.6 search-iters/s |
| Q5 Haskell self-play scaling | 0.97x | 0.6 -> 0.6 games/s |
| Q5 cpp-imperative self-play scaling | 3.72x | 0.0 -> 0.1 games/s |

The refreshed Sprint 8.11 verdict was **`Within tolerance`** for the bounded
metric-suite fail-closed pipeline before backend (ii)'s compact-board correction.
Q3 and Q6 passed, and the live divergence matrix was all zeroes.

Sprint `5.6` corrected backend (ii) on 2026-05-25. Focused rebuilt-image
benchmarks now show the intended steelman ordering against backend (i), but they
also reopened Phase `8` parity against backend (v):

| Row | Evidence |
|-----|----------|
| Backend (ii) vs (i), self-play ST | `1.1` vs `0.5` games/s |
| Backend (ii) vs (i), terminal playout ST | `20951.5` vs `3125.2` playouts/s |
| Backend (ii) vs (i), search-iteration ST | `23113.2` vs `3341.0` search-iters/s |
| Haskell vs backend (ii), terminal playout ST | `8558.8` vs `20951.5` playouts/s |
| Haskell vs backend (ii), search-iteration ST | `9256.2` vs `23113.2` search-iters/s |
| Haskell vs backend (ii), self-play ST | `0.6` vs `1.1` games/s |

The focused Sprint `5.6` gates passed `mcts-cross-backend`, `mcts-legacy-parity`,
and `mcts-unit`. Sprint `8.12` then retuned Haskell against this corrected backend
(ii) ceiling.

Sprint `6.7` then removed the backend (iii) representation confounder on
2026-05-26. Focused rebuilt-image checks now show `(iii)` broadly matching `(ii)`:
terminal playout ST is `19416.9` vs `21508.3` playouts/s, and search-iteration ST
is `20694.1` vs `20051.8` search-iters/s (`cpp-functional` vs
`cpp-imperative`, seed `42`, count `1000`, max plies `60`). This confirms the
earlier `(ii)`/`(iii)` shortfall was an implementation-shape gap, not an inherent
cost of functional-core style.

Sprint `8.14` closed on 2026-05-27 with the corrected backend (ii) target, a
fail-closed report-card verdict gate, and `N_PRIM=20_000`. The accepted
`docker compose run --rm mcts mcts test all` report card recorded the current
Sprint `5.6` artefact evidence:

| Row | Ratio | Evidence |
|-----|------:|----------|
| Q1a terminal playout ST | 0.72x | Haskell 30804.2 playouts/s vs cpp-imperative 22078.9 playouts/s |
| Q1a terminal playout MT8 | 0.85x | Haskell 182020.9 playouts/s vs cpp-imperative 154067.0 playouts/s |
| Q1b search-iteration ST | 0.67x | Haskell 34619.7 search-iters/s vs cpp-imperative 23342.6 search-iters/s |
| Q1b search-iteration MT8 | 0.67x | Haskell 253507.0 search-iters/s vs cpp-imperative 170816.3 search-iters/s |
| Q2 self-play ST | 0.59x | Haskell 1.9 games/s vs cpp-imperative 1.1 games/s |
| Q2 self-play MT8 | 0.68x | Haskell 6.4 games/s vs cpp-imperative 4.3 games/s |
| Q5 Haskell search-iteration scaling | 7.32x | 34619.7 -> 253507.0 search-iters/s |
| Q5 cpp-imperative search-iteration scaling | 7.32x | 23342.6 -> 170816.3 search-iters/s |
| Q5 Haskell self-play scaling | 3.42x | 1.9 -> 6.4 games/s |
| Q5 cpp-imperative self-play scaling | 3.92x | 1.1 -> 4.3 games/s |

Q3/Q4/Q6 passed, the divergence matrix was all zeroes, all Cabal stanzas
passed, and the verdict line read **`Within parity band`** (this snapshot
pre-dates Sprint `5.7`; under the reframed doctrine the verdict line is
informational, not a closure gate — see [Performance Measurement
Doctrine](#performance-measurement-doctrine)). Phase `5` Sprint `5.7` has
since closed lower-level backend `(ii)` hot-path steelman work, so this
measurement is not the final Phase `8` handoff. Sprint `8.15` rebaselines
the measurement against the new `(ii)` kernel and retuned PGO/BOLT profile
suite while the apples-to-apples invariants Q3/Q4/Q6/Q7 continue to gate
closure.

Focused Sprint `8.15` Haskell tuning has accepted compact `Word8` pawn slots,
non-terminal action-set paths, no-ply rollout apply, fused arena visit/value
updates, first-unvisited UCT child selection, worker `forkOn` pinning, and direct
packed-slot path starts in `pathExistsWithMasks`, plus a no-wall legal-action fast
path in `appendWallActionIds` and single-constructor action transitions with a
no-ply rollout variant. The aggregate rerun after those accepted changes remains
short of the post-`5.7` target with `Verdict: Shortfall 0.2678864950323545`:
Q1a backend `(ii)`/Haskell ratios `1.06x` ST and `1.27x` MT8, Q1b `1.05x` ST
and `1.11x` MT8, and Q2 `0.98x` ST and `1.11x` MT8. Rejected measured
candidates include direct wall enumeration, iterative descent, cached board
coordinates, direct wall-bit-index apply, direct terminal checks in
`UCT.descend`, strict `quotRem` index decoding in the action/wall hot path,
direct wall-index legality/trial-mask decoding, and Word64 signed-modulo
correction-table rollout selection because they regressed the focused rows. Later
forced splitmix inlining with primitive seed hoisting also regressed focused
Q1a/Q1b primitive rows, and bulk arena child reservation is rejected because the
aggregate report-card rerun worsened the shortfall to
`Shortfall 0.35914394441567055` despite passing functional gates.

The current text report card also prints raw Q1a/Q1b/Q2 rates for every backend
slot before the question-summary table and ends with explicit Q1a-Q7 answers based
on the observed ratios, scaling values, divergence rates, and gate outcomes. Those
raw rows are diagnostic context for the full cohort; the labelled measurement
above remains Haskell (v) versus backend (ii) under the
[Performance Measurement Doctrine](#performance-measurement-doctrine).

## Performance Measurement Doctrine

The report card distinguishes **measurement questions** (Q1, Q2, Q5) from
**apples-to-apples invariants** (Q3, Q4, Q6, Q7). Only the invariants gate
`mcts test all` closure. The performance numbers are reported honestly and
attributed where appropriate; "Haskell trails fully-optimised C++ by N%" is an
acceptable scientific finding under the documented PGO asymmetry.

### Q-classification

| Question | Class | What it answers |
|----------|-------|-----------------|
| Q1a terminal playout throughput   | Measurement | Observed `playouts/s` rate for each backend, and the backend (ii)/Haskell time ratio. |
| Q1b search-iteration throughput   | Measurement | Observed `search-iters/s` rate for each backend, and the backend (ii)/Haskell time ratio. |
| Q2 played-game self-play throughput | Measurement | Observed `games/s` rate for each backend, and the backend (ii)/Haskell time ratio. |
| Q3 cross-backend visit-count equality | Invariant   | Visit and chosen-move equality for `(ii)..(v)` under `--rng cpp`. |
| Q4 same-backend determinism       | Invariant   | Identical determinism payloads for each backend across three seeds. |
| Q5 ST→MT8 scaling per backend     | Measurement | Observed scaling ratio for backend (v) Haskell and backend (ii) C++. |
| Q6 legacy-envelope liveness       | Invariant   | All five backend slots complete the legacy envelope. |
| Q7 semantic parity                | Invariant   | `mcts-semantic-parity` agrees for `(ii)..(v)`. |

### Closure gate

`mcts test all` exits zero iff every apples-to-apples invariant holds and the
verdict line records a non-pending measurement:

    closure_pass  ==  apples_to_apples.q3
                  &&  apples_to_apples.q4
                  &&  apples_to_apples.q6
                  &&  apples_to_apples.q7
                  &&  verdict /= EvidencePending

This is implemented in `src/MCTS/ReportCard.hs` as `reportCardPassed` and
exercised by the `mcts test all` driver in `src/MCTS/CLI/Test.hs`. The JSON
report card surfaces the four invariant booleans (plus the derived
`all_pass`) in the `apples_to_apples` field; the text renderer prints the
same booleans in the "Apples-to-apples invariants (closure gates)" block.

### Verdict-line labelling threshold

The verdict line is **informational**, not a closure gate. The labelling
threshold:

**`HASKELL_PARITY_TOLERANCE = 0.05`** (5% labelling cutoff).

When the worst Q1a/Q1b/Q2 backend (ii)/Haskell time ratio satisfies

    haskell_time / cpp_imperative_time <= 1 + HASKELL_PARITY_TOLERANCE

across both threading modes, the verdict line reads `Within parity band
(Haskell <= 5% of cpp-imperative on Q1a/Q1b/Q2)`. Otherwise it reads
`Trails parity band by N%`, where
`N = max(Q1a_ratio, Q1b_ratio, Q2_ratio) - 1` expressed as a percentage —
honestly recorded with the PGO-asymmetry attribution from
[PGO Asymmetry](#pgo-asymmetry). Both labels are acceptable closure outcomes;
neither passes nor fails the experiment on its own. Only `EvidencePending`
(no measurement recorded) blocks closure on the verdict side.

The implemented threshold lives in `src/MCTS/ReportCard.hs` as
`reportCardParityTolerance = 0.05`; `cabal.project` mirrors the report-card
workload knobs, not this labelling threshold. Any threshold change must update
that source constant and this section in lock-step.

### Five-backend full-optimisation prerequisite

For the measurement to be meaningful, every steelman backend in the cohort
must be at the optimisation floor established by its phase-owned closure:

| Backend | Steelman sprint | Optimisation floor |
|---------|-----------------|---------------------|
| (i) `cpp-legacy`        | exempt by design (see [Backend (i)](#backend-i--cpp-legacy-exempt)) | unoptimised baseline; preserved for legacy comparison only |
| (ii) `cpp-imperative`   | Sprint `5.7` ([phase 5](../../DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md)) | action-id generation without child-board materialization; PGO+BOLT |
| (iii) `cpp-functional`  | Sprint `6.7` ([phase 6](../../DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md)) | compact value-state functional core; PGO+BOLT |
| (iv) `rust`             | Sprint `6.8` ([phase 6](../../DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md)) | bit-parallel path checks, fixed-capacity buffers; PGO+BOLT |
| (v) `haskell`           | Sprint `8.13` ([phase 8](../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md)) | packed numeric `ActionIds`, hot-path INLINE pragmas, RTS pin |

If a future sprint identifies measurable headroom on a steelman backend, the
new floor must close in its phase-owned sprint before the measurement is
considered final. Backend (i) is the only exempt member of the cohort and
remains exempt for the project lifetime.

## Toolchain Pin

Pinned per [../../HASKELL_CLI_TOOL.md → Toolchain
pinning](../../HASKELL_CLI_TOOL.md) and
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item 16](../../DEVELOPMENT_PLAN/00-overview.md):

- **GHC `9.12.4`** (Phase 1 reopen Sprint `1.14`) — pinned in `mcts.cabal`
  (`tested-with: ghc ==9.12.4`) and `cabal.project`
  (`with-compiler: ghc-9.12.4`). Matches the warm Cabal store baked into the
  hostbootstrap base image per
  [../../DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md](../../DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md).
- **Cabal `3.16.1.0`** — pinned in `cabal.project`; not a floor.
- **GCC** — latest stable on `ubuntu:24.04` (the container base).
- **LLVM** — pinned version shared by GHC's `-fllvm` backend and BOLT
  post-link. The Dockerfile carries one LLVM version regardless of which
  language is being compiled.
- **Rust** — latest stable, installed via `rustup` with the minor version
  pinned in `docker/Dockerfile`.
- **`mimalloc`** — Ubuntu `libmimalloc-dev` in the pinned container; C++ links the
  system library and Rust uses a local `GlobalAlloc` wrapper over the same system
  library.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [backend_ffi_contract.md](./backend_ffi_contract.md) — how the build harness
  produces the FFI shared libraries through the `Subprocess` boundary
- [determinism_contract.md](./determinism_contract.md) — why
  `-ffast-math`/`-Ofast` is excluded and why equity is not part of the
  determinism contract
- [unit_testing_policy.md](./unit_testing_policy.md) — the report-card workload
  that measures the parity outcome
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
