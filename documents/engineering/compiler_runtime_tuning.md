# Compiler and Runtime Tuning

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md, ../../DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md, ../../DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md, ../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md, ../documentation_standards.md, ./README.md, ./backend_ffi_contract.md
**Generated sections**: none

> **Purpose**: Authoritative spec of the per-backend compiler, RTS, and code-level
> tuning stacks: the backend (i) verbatim exemption, the backend (ii)/(iii)
> doctrine-flag set with PGO+BOLT+`mimalloc`, the backend (iv) Rust
> `[profile.release]`, the backend (v) Haskell GHC/LLVM/RTS stack, and the
> one-known-asymmetry PGO note.

This document owns its content. The toolchain pin (GHC `9.14.1`, Cabal `3.16.1.0`)
is doctrine-owned; the per-backend tuning stacks are project-specific.

## Doctrine Pointers

- [../../HASKELL_CLI_TOOL.md → Toolchain pinning](../../HASKELL_CLI_TOOL.md) — GHC
  `9.14.1` and Cabal `3.16.1.0` are the pinned versions for the Haskell binary.
- [../../HASKELL_CLI_TOOL.md → Architecture → Subprocesses as Typed
  Values](../../HASKELL_CLI_TOOL.md) — the PGO+BOLT build harness invokes `g++`,
  `rustc`, `llvm-bolt`, and `cabal` through the typed `Subprocess` boundary.
- [../../HASKELL_CLI_TOOL.md → Plan / Apply](../../HASKELL_CLI_TOOL.md) — the
  `mcts build <backend>` commands are Plan/Apply with `--dry-run` and
  `--plan-file <path>`.

## Backend (i) — `cpp-legacy` (Exempt)

Backend (i) is **exempt** from the optimisation stack. (i) is strictly verbatim
from `MCTS_legacy`; only FFI shims are permitted per
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item 17](../../DEVELOPMENT_PLAN/00-overview.md).

Build flags from the legacy: `-std=c++17 -O3 -fPIC -Wall`. It uses
`std::shared_ptr<uct_node>` trees and `std::mt19937_64` unchanged. No
`-march=native`, no `-flto`, no `mimalloc`, no BOLT, no PGO.

Backend (i) is the regression-sanity port, **not** the performance ceiling. The
project hypothesis is proven when backend (v) Haskell matches backend (ii) — not
(i) — on Q1 and Q2.

## Backend (ii) and (iii) — C++ Imperative and Functional-Style

Compiler flags per
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item 18](../../DEVELOPMENT_PLAN/00-overview.md):

```text
# Example: mandatory C++ compile flags for backends (ii) and (iii)
-std=c++23 -O3 -march=native -mtune=native -flto -fno-plt
-fno-semantic-interposition -fvisibility=hidden -fvisibility-inlines-hidden
-fno-exceptions
```

`-fno-exceptions` is mandatory (promoted from Tier 3 conditional per
[../../README.md → Compiler and runtime tuning](../../README.md)): the engine
core does not throw, so landing-pad cost is unconditional dead weight.

**Excluded deliberately:** `-ffast-math`, `-Ofast`. Equity backprop is
summation-order-sensitive and we want backend-internal determinism even though
equity is excluded from the cross-backend wire format.

GCC only — Clang is not supported on the C++ side.

### Build Workflow

The `mcts build cpp-imperative` (and `mcts build cpp-functional`) Plan/Apply
commands run:

1. **Two-stage PGO.** Instrumented build via
   `-fprofile-generate=cpp-imperative/pgo-profile/`; training run on benchmark
   (b) at a representative game count (100 games × 10_000 sims is the pinned
   training workload); optimised build with
   `-fprofile-use=cpp-imperative/pgo-profile/ -fprofile-correction`.
2. **BOLT post-link.** `llvm-bolt cpp-imperative/build/libmcts_cpp_imperative_bench.so
   -o cpp-imperative/build/libmcts_cpp_imperative_bench.bolted.so -data
   cpp-imperative/bolt-profile/perf.fdata` (and the same for the
   `_instrumented` artefact).
3. **`mimalloc` link.** Static-linked (preferred for FFI determinism;
   `LD_PRELOAD` is acceptable for ad-hoc benchmark runs).
4. **Install.** Rename or symlink `cpp-imperative/build/libmcts_cpp_imperative_bench.bolted.so`
   to `cpp-imperative/libmcts_cpp_imperative.so` — the canonical FFI load name
   pinned by the project [../../README.md → Repository layout
   (target)](../../README.md). The `_instrumented.bolted.so` artefact is
   symlinked to `cpp-imperative/libmcts_cpp_imperative_instrumented.so` for
   the verify/play/replay path. See
   [./backend_ffi_contract.md → Backends and Linkage](./backend_ffi_contract.md)
   for the full install-name vs build-intermediate table.

### Code-Level Requirements

Grouped by priority per the project [../../README.md → Compiler and runtime
tuning](../../README.md). Top-tier items are non-negotiable; the rest are
required unless profiling shows the change is neutral or harmful.

**Top tier** (each expected 1.5–3× over the legacy baseline):

1. **Arena-allocated tree** with `u32` child indices. One contiguous
   `std::vector<uct_node>` per game, expanded in place, freed in bulk at game
   end. Eliminates refcount traffic, double indirection, per-node destruction,
   and most cache misses during tree descent.
2. **Per-rollout scratch board with undo or one snapshot per game.** Eliminates
   the per-rollout `board_copy` allocation.
3. **PGO + BOLT pipeline** as named above.

**Correctness requirement** (also top tier):

- **`Word16` ply counter in board state.** `is_terminal` ↔
  `hero_wins || villain_wins || ply_count >= max_plies`; `terminal_eval` returns
  `0.0` on ply-cap termination. Part of the per-rollout snapshot/undo path. See
  [determinism_contract.md → Ply-Cap Draw Rule](./determinism_contract.md#ply-cap-draw-rule).

**Second tier** (each 10–30%, cumulative):

4. **Flat children layout** — children stored contiguously in the arena; each
   parent records `first_child_idx: u32` and `n_children: u16`. No
   `std::vector<u32>` per node.
5. **Move-list buffer reuse.** Move generators write into a `thread_local` or
   stack-SBO buffer; no per-call `std::vector`. Inline buffer sized for typical
   Corridors move counts (~40); heap spill allowed but rare.
6. **`u32` parent index** rather than `shared_ptr<uct_node>`.
7. **Visit-count compression to `u16`** when `per_move_sims < 65536`. Shrinks
   node footprint, more nodes per cache line. The header's `per_move_sims`
   field gates the choice; the wire format already records visits as `u32`, so
   the in-memory choice is transparent to the determinism contract.

**Third tier** (sub-10% each, cumulative):

8. `[[likely]]` / `[[unlikely]]` on UCT child-selection and terminal-state
   branches.
9. `__attribute__((hot))` / `__attribute__((always_inline))` on
   `select_best_child`, `apply_move`, `is_terminal`, `rollout_step`.
10. `__attribute__((const))` / `((pure))` on referentially-transparent helpers
    — lets GCC hoist and CSE.
11. `__builtin_prefetch` on the child array during UCT descent.
12. `__builtin_popcountll` / `__builtin_ctzll` on raw `u64` bitboards rather
    than `std::bitset<64>::_Find_first()` (not reliably lowered to `tzcnt`).
13. `alignas(64)` on the tree-node arena base; struct-of-arrays where
    measurement supports it.
14. `thread_local` scratch buffers for the multi-threaded driver (per-worker,
    not per-game).

`-fno-exceptions` is promoted to the mandatory flag block at the top of this
section: the engine core does not throw, so landing-pad cost is unconditional
dead weight.

**Native-RNG benchmark only** (not under `--rng cpp`, which is pinned to
`std::mt19937_64` by the determinism contract):

15. Replace `std::mt19937_64` with `xoshiro256++` or `wyrand` — smaller state,
    faster `next_u64`, equivalent statistical quality for rollouts.

### Backend (iii) Functional-Style Discipline

Observes **all** of the above. The "functional style" of (iii) is at the API
and data-flow level, *not* the memory-representation level — arena allocation
and mutable scratch state are still required. Both backends run under the same
optimisation regime so (iii)-vs-(ii) isolates *style* as the variable.

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
strip = "symbols"
```

`RUSTFLAGS`: `-C target-cpu=native -C link-arg=-fuse-ld=lld`.

### Build Workflow

The `mcts build rust` Plan/Apply command runs:

- **Two-stage PGO** via `rustc -Cprofile-generate=rust/pgo-profile/` → train on
  benchmark (b) → `-Cprofile-use=rust/pgo-profile/`.
- **BOLT** post-link, same shape as the C++ backends.
- **`mimalloc`** as `#[global_allocator]` (via the `mimalloc` crate).

### Code-Level Requirements

- **`u16` ply counter in board state** (correctness — see
  [determinism_contract.md → Ply-Cap Draw Rule](./determinism_contract.md#ply-cap-draw-rule)).
  Board carries a `u16` ply counter; `is_terminal` returns `true` on
  `ply >= max_plies` with eval `0.0`. Part of the per-rollout snapshot/undo
  path.
- Tree as `Vec<Node>` with `u32` child indices, mirroring the C++ arena.
- `#[inline(always)]` on hot leaf operations, `#[cold]` on error and terminal
  paths.
- `core::hint::unreachable_unchecked` where a precondition genuinely guarantees
  it; each use documented.
- Bit ops via `u64::count_ones` / `u64::trailing_zeros` (lower to the same
  `popcnt` / `tzcnt` as the C++ builtins).
- No `Rc` / `Arc` in the hot path. No `Box<dyn Trait>` in the search.

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

LLVM codegen tuned via `-optlo-mcpu=native` (through to LLVM `opt`) and
`-optlc-mcpu=native` (through to `llc`). LLVM version pinned in the
`docker/Dockerfile` so codegen is reproducible.

### RTS Tuning

Baked into the executable's `ghc-options`:

```cabal
-- Example: cabal ghc-options RTS-tuning stanza
-with-rtsopts=-A64m -n4m -qg1 -qb -T
```

Large nursery to push major GC out, `-qg1` so major GC is parallel from
generation 1, `-qb` for load balancing across capabilities, `-T` to expose GC
stats for `+RTS -s` profiling.

Backend (v) uses **GHC's built-in RTS allocator**. Alternate allocators
(e.g., `mimalloc` via `LD_PRELOAD`, `jemalloc`, etc.) are **out of scope**
for backend (v): it is the pure-Haskell baseline and replacing the allocator
would muddy the GHC-as-shipped parity claim. `mimalloc` static-linking
applies to backends (ii), (iii), (iv) only — see
[../../DEVELOPMENT_PLAN/system-components.md](../../DEVELOPMENT_PLAN/system-components.md).

### Code-Level Requirements

- **`Word16` ply counter in board state** (correctness). Board carries a
  `Word16` ply counter; `isTerminal` returns true on `ply >= maxPlies` with
  eval `0.0`. Lives in the same unboxed board record as the bitboards;
  restored as part of the per-rollout `ST`-arena snapshot path.
- Engine hot path lives in `ST s`. Tree is a `MutablePrimArray s` arena of
  unboxed `Int32` / `Float` fields (SoA), or a hand-rolled `MutableByteArray#`
  if profiling shows `PrimArray` indexing isn't optimal.
- Board state is `Word64` bitboards, manipulated with `Data.Bits` (compiles to
  `popcnt` / `tzcnt` under `-fllvm` with `-optlo-mcpu=native`).
- Strict fields everywhere (`{-# UNPACK #-} !Int`), bang patterns on `let`
  bindings inside `ST` blocks.
- `INLINABLE` on every exported engine primitive; `SPECIALIZE` on the search
  loop for the concrete game type.
- Pure API at the boundary: `search :: GameState -> Seed -> SearchBudget ->
  Tree -> (Move, Tree)`. `Tree` is opaque; internally backed by the `ST` arena
  and frozen at the API boundary if tree-persistence semantics need it.
- No `Maybe` or `Either` in the rollout inner loop; sentinel values or unboxed
  sum representations instead.

## PGO Asymmetry

GHC `9.14` has no production-grade profile-guided optimisation comparable to
GCC/Clang `-fprofile-use` or `rustc -Cprofile-use`. The Haskell backend
therefore competes against PGO+BOLT-optimised C++ and Rust without an equivalent
feedback loop.

This is the asymmetry that most concretely tests the project hypothesis: if
Haskell matches under these conditions, the result is meaningful; if it falls
short by 5–15%, that gap is plausibly attributable to the missing PGO loop
rather than to any property of pure functional code per se. We document this
rather than paper over it.

The Phase 8 Sprint 8.3 parity verdict records the result honestly: either
`Within tolerance` or `Shortfall <ratio>` per the [Parity Tolerance](#parity-tolerance)
section below, with the gap attributed to this asymmetry where appropriate.

## Parity Tolerance

The Phase 8 Sprint 8.3 verdict pins on a single constant:

**`HASKELL_PARITY_TOLERANCE = 0.05`** (5% shortfall ceiling).

Sprint 8.3 renders `Within tolerance` iff

    haskell_time / cpp_imperative_time <= 1 + HASKELL_PARITY_TOLERANCE

holds on **both** Q1 and Q2, in both threading modes the report card runs.
Otherwise the verdict is `Shortfall <ratio>`, where
`ratio = max(Q1_ratio, Q2_ratio) - 1` (the worst-case shortfall over the
two workloads, expressed as a fraction).

The 5% ceiling is independent of, and stricter than, the 5–15% PGO-attributable
shortfall band described in [PGO Asymmetry](#pgo-asymmetry). A shortfall that
lands inside the 5–15% band still renders `Shortfall <ratio>` — the PGO note
is attached as the attribution, not as an exemption. Only a shortfall of
`<= 5%` clears the bar.

The constant is mirrored in `cabal.project` as
`HASKELL_PARITY_TOLERANCE = 0.05` so `src/MCTS/ReportCard.hs` can reference
it symbolically. Any change to the threshold must update both this section
and `cabal.project` in lock-step.

## Toolchain Pin

Pinned per [../../HASKELL_CLI_TOOL.md → Toolchain
pinning](../../HASKELL_CLI_TOOL.md) and
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item 16](../../DEVELOPMENT_PLAN/00-overview.md):

- **GHC `9.14.1`** — pinned in `mcts.cabal` (`tested-with: ghc ==9.14.1`) and
  `cabal.project` (`with-compiler: ghc-9.14.1`).
- **Cabal `3.16.1.0`** — pinned in `cabal.project`; not a floor.
- **GCC** — latest stable on `ubuntu:24.04` (the container base).
- **LLVM** — pinned version shared by GHC's `-fllvm` backend and BOLT
  post-link. The Dockerfile carries one LLVM version regardless of which
  language is being compiled.
- **Rust** — latest stable, installed via `rustup` with the minor version
  pinned in `docker/Dockerfile`.
- **`mimalloc`** — pinned version, static-linked.

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
