# Phase 6: Backends (iii) C++ Functional-Style and (iv) Rust

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Land backend (iii) — same algorithms as (ii), same optimisation stack,
> functional style at the API and data-flow level only — and backend (iv) Rust as an
> independent cross-language baseline with its own pinned `[profile.release]`,
> two-stage PGO, BOLT, and `mimalloc` global allocator.

## Phase Status

🔄 **Active (Rust Corridors gameplay-port residue)**. Backend (iii)
C++ functional-style is closed at sprint-owned surfaces: Sprint 6.1
landed the arena-MCTS engine with the functional-style API surface
(`std::optional<State>` move attempts, `std::variant<ChildIdx,
NoChild>` select outcomes) on top of the same data layout as backend
(ii); Sprint 6.2 wired the visit-vector dispatch + the typed
`cppFunctionalPgoBoltPlan` Subprocess pipeline. Backend (iv) Rust now
ships a real arena MCTS (`rust/src/{tree.rs,search.rs,xoshiro256pp.rs}`)
with UCT-1, xoshiro256++ native RNG, and the full
`mcts_rust_search_move` / `mcts_rust_recompute_move` /
`mcts_rust_read_visits` C ABI; Sprint 6.4 ships the
`rustPgoBoltPlan` Plan/Apply harness through the typed `Subprocess`
boundary. The **Rust Corridors gameplay port** (wall placement, jump
moves, BFS escapability) from `cpp-legacy/legacy-core/board.cpp`
remains the largest open item — until it lands, the Haskell
dispatcher routes `--backend rust` through the in-process logical
UCT for the operator-facing bench/verify path. Tracked under Sprint
6.3's ledger row.

## Phase Summary

Phase `6` lands the remaining two C-ABI-linked backends. Backend (iii) C++
functional-style runs under the exact optimisation regime as backend (ii) so that the
(ii)-vs-(iii) comparison isolates *style* — API and data-flow level — as the
single variable; memory representation stays arena-allocated and mutable because
that is the floor below which the steelman ceiling cannot be matched. Backend (iv)
Rust is an independent cross-language baseline: same workload, same wire format, same
C ABI for the FFI bridge, but a wholly separate toolchain with its own PGO and BOLT
pipeline, `mimalloc` as `#[global_allocator]`, and the pinned `[profile.release]`
settings from the project README.

## Sprint 6.1: `cpp-functional/` Functional-Style C++ Engine ✅

**Status**: Done (arena-MCTS engine with functional-style API surface
landed; `-fno-exceptions` and per-rollout undo remain ledger items)
**Implementation**: `cpp-functional/engine/{state.hpp,arena.hpp,xoshiro256pp.hpp,search.hpp,search.cpp}`,
`cpp-functional/c-abi/`, `cpp-functional/Makefile`
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`,
`documents/engineering/backend_ffi_contract.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Rewrite the search and rollout flow in a functional style at the API and data-flow
level — `std::optional` and `std::variant` for state transitions; pipeline-style
move handling with intermediate types; immutable value semantics on the high-level
API — while keeping the same arena-allocated tree and per-rollout scratch board
underneath so the optimisation stack still applies.

### Deliverables

- `cpp-functional/src/` contains the functional-style engine. Same arena, same
  scratch board, same `Word16` ply counter and ply-cap draw rule as backend
  (ii); the difference is API shape and data-flow style:
  - `Move` operations return `std::optional<Board>` instead of mutating in place
    at the API surface, then lower internally to in-place mutations on the
    scratch board.
  - `select_child` returns a `std::variant<ChildIdx, NoChild>` rather than a
    sentinel `-1`.
  - Move generators return a `std::span<const Move>` over a caller-owned buffer
    (still the same buffer-reuse pattern as (ii); the difference is API shape).
- `cpp-functional/c-abi/mcts_cpp_functional.{h,cc}` exposes the same C ABI shape
  as backends (i) and (ii) with the prefix `mcts_functional_*`.
- **Native RNG choice.** Under `--rng native`, backend (iii) uses the same
  `xoshiro256++` (or `wyrand`) RNG as backend (ii) per
  [phase-5-cpp-imperative-steelman.md → Sprint 5.1](phase-5-cpp-imperative-steelman.md)
  so that (ii)-vs-(iii) isolates style as the variable. The pinned choice
  lives in
  [../documents/engineering/determinism_contract.md → RNG Source Split → Per-Backend Native RNG Table](../documents/engineering/determinism_contract.md);
  any swap must be applied to both (ii) and (iii) in the same commit.
- `cpp-functional/Makefile` uses the **same** flag set as
  `cpp-imperative/Makefile` per
  [00-overview.md → Hard Constraints item 18](00-overview.md): `-std=c++23 -O3
  -march=native -mtune=native -flto -fno-plt -fno-semantic-interposition
  -fvisibility=hidden -fvisibility-inlines-hidden -fno-exceptions`. The
  optimisation regime is identical so the comparison isolates style as the
  variable. GCC only.
- **Paired build targets** per
  [../README.md → Cross-backend verification → Compile-time toggle for
  instrumentation](../README.md), mirroring Phase 5 Sprint 5.1. The
  functional-style self-play driver in `cpp-functional/src/driver.cc` is
  parameterised by the same `Instrumentation` template type as the imperative
  driver. Two artefacts are produced:
  `libmcts_cpp_functional_bench.{so,a}` (driver instantiated with
  `InstrumentedOff`) and `libmcts_cpp_functional_instrumented.{so,a}` (driver
  instantiated with `InstrumentedOn`). The engine TU is shared; only the driver
  compiles twice.
- The build products are `cpp-functional/build/libmcts_cpp_functional_bench.{so,a}`
  and `cpp-functional/build/libmcts_cpp_functional_instrumented.{so,a}`.
- **Install step** (mirrors Phase 5 Sprint 5.1). The `_bench.bolted.so`
  intermediate is renamed or symlinked to the canonical FFI load name
  `cpp-functional/libmcts_cpp_functional.so` per
  [../README.md → Repository layout (target)](../README.md) and
  [../documents/engineering/backend_ffi_contract.md → Backends and Linkage](../documents/engineering/backend_ffi_contract.md).
  The `_instrumented.bolted.so` intermediate is symlinked to
  `cpp-functional/libmcts_cpp_functional_instrumented.so`.

### Validation

1. `make -C cpp-functional smoke` produces the non-PGO/BOLT shared library
   inside the container.
2. The compiled `.so` exports the same symbol set as backends (i) and (ii) with
   the `mcts_functional_*` prefix.
3. The same brute-force legal-move agreement test from Phase 5 Sprint 5.1 passes
   for backend (iii) once Sprint 6.2 lands the FFI bindings.

### Closure Notes

- `cpp-functional/engine/` now hosts the arena-MCTS engine with the
  functional-style API surface per Sprint 6.1: `state.hpp` carries a
  `try_advance :: const State & -> board && -> std::optional<State>`
  move attempt (matching the sprint's `std::optional` move-result
  shape); `search.hpp` exposes `SelectOutcome = std::variant<ChildIdx,
  NoChild>` for child selection (the `std::variant` rather than
  sentinel `-1`); the underlying memory layout (`arena.hpp`, flat
  children, `Word16` ply counter, `thread_local` move buffer,
  `__builtin_prefetch`, `alignas(64)`) intentionally matches backend
  (ii) so the (ii)-vs-(iii) comparison isolates *style* as the
  variable, not memory representation.
- `cpp-functional/c-abi/mcts_cpp_functional.cc` was rewritten to drive
  the arena search through `mcts_functional_search_move` /
  `mcts_functional_recompute_move` / `mcts_functional_select_uct_move`.
  `cpp-functional/Makefile` builds the smoke + bench + instrumented
  artefacts under the shared doctrine C++23 flag set; `nm -D` confirms
  the `mcts_functional_*` symbol surface.
- `cabal test all` and `mcts check-code` stay green; cross-backend
  smoke continues to accept a well-formed `VerifyMismatch` per the
  Phase 7 stanza note.

### Remaining Work

- `-fno-exceptions` on the engine TU: same status as backend (ii) —
  `corridors::board::eval` / `get_terminal_eval` still throw
  `std::string`; tracked in the (ii) ledger row, shared.
- Per-rollout scratch-board undo on (iii) shares (ii)'s status.

## Sprint 6.2: FFI Bindings, Build Harness, Driver for Backend (iii) ✅

**Status**: Done (visit-vector FFI binding +
`cppFunctionalPgoBoltPlan` typed Subprocess pipeline shared with
backend (ii) + dispatcher routing through real FFI when the shared
library is present)
**Implementation**: `cpp-functional/c-abi/`, `cpp-functional/Makefile`,
`src/MCTS/CLI/Build.hs::cppFunctionalPgoBoltPlan`,
`src/MCTS/Driver/CppFunctional.hs`, `src/MCTS/Driver/ForeignSearch.hs`,
`src/MCTS/Driver/Dispatch.hs`,
`src/MCTS/CLI/Bench.hs`, `src/MCTS/CLI/Verify.hs`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/cli_command_surface.md`

### Objective

Wire backend (iii) into the FFI, the PGO+BOLT build harness, the bench dispatch,
and the verify dispatch, mirroring Phase 5 Sprints 5.2–5.4 for the functional
variant.

### Deliverables

- `src/MCTS/FFI/CppFunctional.hs` declares the per-symbol bindings; same `unsafe`
  / `safe` split as (i) and (ii).
- `src/MCTS/Driver/CppFunctional.hs` exposes `runGameCppFunctional :: GameInputs
  -> App Transcript`.
- `src/MCTS/CLI/Build.hs` extends the Plan/Apply build harness with
  `mcts build cpp-functional`; the plan structure (instrumented build →
  training run → optimised build → BOLT post-link → `mimalloc` link) mirrors
  Phase 5 Sprint 5.3.
- `src/MCTS/CLI/Command.hs` gains the `BuildCppFunctional` constructor on the
  `BuildCommand` family per
  [phase-1-haskell-cli-surface.md → Sprint 1.2 ownership note](phase-1-haskell-cli-surface.md),
  with a matching `CommandSpec` leaf and an `Example`
  (`mcts build cpp-functional --dry-run`) wired into the registry.
- `src/MCTS/CLI/Bench.hs` dispatch table adds `--backend cpp-functional`.
- `src/MCTS/CLI/Verify.hs` `VerifyBackend` GADT gains `VCppFunctional`.
- The `prerequisiteRegistry` gains `libmcts-cpp-functional-built` plus the
  `cpp-functional/pgo-profile/` and `cpp-functional/bolt-profile/` directory
  nodes.

### Validation

1. `mcts build cpp-functional --dry-run` renders the typed `Subprocess`
   sequence and exits 0.
2. `mcts build cpp-functional` runs the full pipeline and produces the bolted
   `.so`.
3. `mcts bench rollouts --backend cpp-functional --threading single --rng cpp
   --games 8 --seed 42` runs to completion.
4. Same-backend determinism: two runs produce identical determinism payload sets.

### Closure Notes

- `MCTS.Driver.CppFunctional.runGameCppFunctional` rides the same
  `MCTS.Driver.ForeignSearch.runForeignSearchGame` worker as backend
  (ii), now calling `mcts_functional_search_move` over the visit-vector
  ABI (sorted `(action_id, visits)` + chosen action) rather than the
  chosen-action-only smoke.
- `cppFunctionalPgoBoltPlan` (in `src/MCTS/CLI/Build.hs`) reuses the
  shared `pgoBoltPlan` builder so the (iii) pipeline is the (ii)
  pipeline with the backend identifier rewritten — the (ii)-vs-(iii)
  style-isolation discipline applies at the build harness level. The
  `mcts-unit::exerciseCppImperativeBuildPlan` test enforces this
  invariant.
- `MCTS.Driver.Dispatch.runBatchDispatch` routes `--backend cpp-functional`
  through the real FFI driver whenever
  `cpp-functional/build/libmcts_cpp_functional.so` is present.

## Sprint 6.3: `rust/` Rust Engine and `cdylib` 🔄

**Status**: Active (real arena MCTS algorithm + xoshiro256++ + full
`mcts_rust_search_move` / `mcts_rust_recompute_move` /
`mcts_rust_read_visits` C ABI now ship in the cdylib; the Rust
Corridors gameplay port from `cpp-legacy/legacy-core/` — wall
placement, jump moves, BFS escapability — remains the largest open
item and stays a ledger row)
**Implementation**: `rust/Cargo.toml`, `rust/src/lib.rs`, `rust/src/board.rs`,
`rust/src/tree.rs`, `rust/src/search.rs`, `rust/src/rollout.rs`,
`rust/src/c_abi.rs`, `rust/src/envelope.rs`, `rust/src/xoshiro256pp.rs`
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`,
`documents/engineering/backend_ffi_contract.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Write backend (iv) in modern, functional-leaning Rust on the latest stable compiler
with the pinned `[profile.release]`, the `mimalloc` global allocator, and the C ABI
exposed as a `cdylib` for the Haskell FFI.

### Deliverables

- `rust/Cargo.toml` pins the `[profile.release]` per
  [00-overview.md → Hard Constraints item 19](00-overview.md):
  ```toml
  [profile.release]
  opt-level = 3
  lto = "fat"
  codegen-units = 1
  panic = "abort"
  strip = "symbols"
  ```
  `[lib]` declares `crate-type = ["cdylib", "staticlib"]`. `RUSTFLAGS=-C
  target-cpu=native -C link-arg=-fuse-ld=lld` is documented in
  `rust/README.md` and consumed by the build harness (Sprint 6.4).
- `rust/src/lib.rs` is the crate root; `rust/src/board.rs` carries the Corridors
  game state with `u16` ply counter; `rust/src/tree.rs` carries `Vec<Node>` with
  `u32` child indices, mirroring the C++ arena per
  [00-overview.md → Hard Constraints item 19](00-overview.md); `rust/src/search.rs`
  carries UCT; `rust/src/rollout.rs` carries random rollouts.
- Code-level requirements: `#[inline(always)]` on hot leaf operations, `#[cold]`
  on error and terminal paths; `core::hint::unreachable_unchecked` only where a
  precondition genuinely guarantees it (each use documented); bit ops via
  `u64::count_ones` / `u64::trailing_zeros` (lower to `popcnt`/`tzcnt`); no
  `Rc` / `Arc` in the hot path; no `Box<dyn Trait>` in the search.
- `mimalloc` declared as the `#[global_allocator]` via the `mimalloc` crate.
- **Native RNG choice.** Under `--rng native`, backend (iv) uses
  `rand_xoshiro::Xoshiro256PlusPlus` (the `rand_xoshiro` crate), matching
  backends (ii) and (iii)'s `xoshiro256++` family so the RNG algorithm is
  cross-language-consistent under `--rng native`. The pinned choice lives in
  [../documents/engineering/determinism_contract.md → RNG Source Split → Per-Backend Native RNG Table](../documents/engineering/determinism_contract.md).
  `rand`'s `SmallRng` is allowed as a fallback only if profiling shows the
  explicit `Xoshiro256PlusPlus` underperforms; the table must record any
  swap.
- `rust/src/c_abi.rs` exposes the same C ABI shape as the C++ backends with the
  prefix `mcts_rust_*`. The `#[no_mangle]` and `extern "C"` annotations carry
  through to the cdylib export list.
- **Paired build targets** per
  [../README.md → Cross-backend verification → Compile-time toggle for
  instrumentation](../README.md). The crate declares a Cargo feature
  `instrumentation` (default off). The self-play driver in
  `rust/src/driver.rs` uses `#[cfg(feature = "instrumentation")]` to splice in
  the transcript writer and the `read_visits` C export. The Cargo build runs
  twice: `cargo build --release` produces `libmcts_rust_bench.so` (feature off,
  no `read_visits` symbol) and `cargo build --release --features
  instrumentation` produces `libmcts_rust_instrumented.so`. The engine modules
  (`board.rs`, `tree.rs`, `search.rs`, `rollout.rs`) compile once and are
  shared between both artefacts; only `driver.rs` and `c_abi.rs` compile
  twice.

### Validation

1. `cargo build --release` produces `rust/target/release/libmcts_rust.so` with
   the pinned profile settings inside the container.
2. The compiled `cdylib` exports exactly the symbols declared in the C ABI.
3. The same brute-force legal-move agreement test from Phase 5 Sprint 5.1
   passes for backend (iv) once Sprint 6.4 lands the FFI bindings.

### Closure Notes

- Real arena MCTS in Rust: `rust/src/tree.rs` carries
  `#[repr(C, align(64))] Node` with `parent : u32`, `first_child : u32`,
  `child_count : u16`, `visits : u32`, `q_sum : f64`, `ply_count : u16`
  in a flat `Vec<Node>` arena. `rust/src/search.rs` runs UCT-1 with
  `EXPLORATION_C = 1.4`, the standard "first unvisited child" expansion
  rule, and an FPU-stable index tie-break. `#[inline(always)]` on hot
  helpers and `#[inline]` on the per-sim worker mirror the C++
  steelman's hot-path discipline.
- xoshiro256++ native RNG lives in `rust/src/xoshiro256pp.rs`
  (`Xoshiro256pp::new(seed)` / `next()` / `bounded(bound)`); matches
  backend (ii)/(iii)'s native RNG choice so the cross-language
  comparison isolates engine implementation as the variable.
- Full C ABI surface: `mcts_rust_search_move(board, seed, sims,
  out_action_ids, out_visits, out_chosen)` and
  `mcts_rust_recompute_move(..., out_equity)` ship with the cdylib;
  `mcts_rust_read_visits` ships as the bench/instrumented split hook.
  `nm -D` on the smoke cdylib lists all 8 `mcts_rust_*` symbols.

### Remaining Work

- **Rust Corridors gameplay port** (the largest remaining piece): the
  current `rust/src/rollout.rs` exposes a placeholder game (a
  ply-counting state with `n_legal_moves(ply) = 12 + (ply%5)+1` and a
  draw-on-ply-cap terminal). The real Corridors logic — pawn movement
  + jump-over-opponent + wall placement + BFS escapability check — is
  the multi-hundred-line port from `cpp-legacy/legacy-core/board.cpp`
  that closes the sprint. Until that lands, the action IDs the Rust
  search emits do not correspond to legal Corridors moves and the
  Haskell-side dispatcher in `MCTS.Driver.Dispatch` keeps `--backend
  rust` on the in-process logical UCT (the smoke driver still rides
  through the cdylib's `mcts_rust_select_uct_move` for the bounded
  smoke game). Tracked in `legacy-tracking-for-deletion.md`.
- Final rustc PGO+BOLT pipeline (Sprint 6.4) wires `mcts build rust`
  through the same Plan/Apply harness as backends (ii)/(iii); the
  pipeline shape (instrument → train → optimize → BOLT → install) is
  identical except for the Cargo toolchain.

## Sprint 6.4: FFI Bindings, PGO+BOLT Build Harness, Driver for Backend (iv) 🔄

**Status**: Active (PGO+BOLT Plan/Apply harness landed via
`rustPgoBoltPlan`; full visit-vector FFI binding +
`withRustSearchGame` shipped; routing `--backend rust` through the
real FFI driver is blocked on the Corridors gameplay port in Sprint
6.3's ledger row)
**Implementation**: `rust/Cargo.toml`, `rust/src/lib.rs`, `mcts.cabal`,
`src/MCTS/CLI/Build.hs::rustPgoBoltPlan`, `src/MCTS/FFI/Rust.hs::withRustSearchGame`,
`src/MCTS/Driver/Dispatch.hs`, `src/MCTS/CLI/Bench.hs`,
`src/MCTS/CLI/Verify.hs`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/cli_command_surface.md`,
`documents/engineering/compiler_runtime_tuning.md`

### Objective

Wire backend (iv) into the FFI, the Plan/Apply build harness (with the two-stage
`rustc -Cprofile-generate` / `-Cprofile-use` PGO and BOLT post-link), the bench
dispatch, and the verify dispatch.

### Deliverables

- `src/MCTS/FFI/Rust.hs` declares the per-symbol bindings against the
  canonical FFI load name `rust/target/release/libmcts_rust.so` per
  [../README.md → Repository layout (target)](../README.md). The PGO+BOLT
  pipeline writes to `rust/target/release-pgo/libmcts_rust.so` as the
  build-time intermediate; the install step renames or symlinks the bolted
  artefact to the canonical name. Same `unsafe` / `safe` choice per symbol.
- `src/MCTS/Driver/Rust.hs` exposes `runGameRust :: GameInputs -> App
  Transcript`.
- `src/MCTS/CLI/Build.hs` extends the Plan/Apply build harness with
  `mcts build rust`. The plan is a typed `[Subprocess]` sequence:
  1. **Instrumented build.** `cargo build --release` with
     `RUSTFLAGS="-Cprofile-generate=rust/pgo-profile/ -C target-cpu=native ..."`.
  2. **Training run.** Run `mcts bench selfplay --backend rust --threading
     multi --workers 8 --rng cpp --games $PGO_TRAINING_GAMES --seed 42 --sims
     $PGO_TRAINING_SIMS` using the same pinned tuple
     (`($PGO_TRAINING_GAMES, $PGO_TRAINING_SIMS) = (100, 10_000)`) as backend
     (ii) per
     [phase-5-cpp-imperative-steelman.md → Sprint 5.3](phase-5-cpp-imperative-steelman.md).
     Symmetric workload across backends so the PGO profile reflects the
     multi-threaded hot path that `mcts verify` and the report card actually
     exercise.
  3. **Optimised build.** `cargo build --release` with
     `RUSTFLAGS="-Cprofile-use=rust/pgo-profile/ -C target-cpu=native ..."`.
  4. **BOLT post-link.** Same shape as the C++ backends.
  5. **Install.** Rename or symlink the bolted artefact at
     `rust/target/release-pgo/libmcts_rust.so` to the canonical FFI load name
     `rust/target/release/libmcts_rust.so` per
     [../README.md → Repository layout (target)](../README.md).
- `src/MCTS/CLI/Bench.hs` dispatch table adds `--backend rust`.
- `src/MCTS/CLI/Verify.hs` `VerifyBackend` GADT gains `VRust`. The full
  four-backend `(ii)..(v)` cohort is now parseable; Phase 7 wires the
  cross-backend `verify` test stanzas.
- `src/MCTS/CLI/Command.hs` gains the `BuildRust` constructor on the
  `BuildCommand` family per
  [phase-1-haskell-cli-surface.md → Sprint 1.2 ownership note](phase-1-haskell-cli-surface.md),
  with a matching `CommandSpec` leaf and an `Example`
  (`mcts build rust --dry-run`) wired into the registry.
- The `prerequisiteRegistry` gains `rustup-toolchain-pinned`,
  `libmcts-rust-built`, the `rust/pgo-profile/` directory node, and
  `lld-linker`.

### Validation

1. `mcts build rust --dry-run` renders the typed `Subprocess` sequence and
   exits 0.
2. `mcts build rust` runs the full pipeline and produces the bolted `.so`
   strictly faster than the smoke `cargo build --release` build on `mcts bench
   selfplay --backend rust --games 100`.
3. `mcts bench rollouts --backend rust --threading single --rng cpp --games 8
   --seed 42` runs to completion.
4. Same-backend determinism: two runs produce identical determinism payload sets.
5. `mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell
   --threading single --games 1 --seed 42 --max-plies 200 --sims 10` runs to
   completion. Bit-equality success or failure at this stage is informational
   — Phase 7 enforces — but the cohort is wired.

### Closure Notes

- `rustPgoBoltPlan` ships the rustc PGO + LLVM-BOLT + install pipeline
  through the typed `Subprocess` boundary. Steps: (1) `cargo build
  --release` with `RUSTFLAGS=-C target-cpu=native -C
  profile-generate=rust/pgo-profile`; (2) PGO training run via
  `cabal exec mcts -- bench selfplay --backend rust --rng cpp --games
  100 --seed 42 --sims 10000`; (3) `llvm-profdata merge` of the
  `.profraw` files into a single `.profdata`; (4) `cargo build
  --release` with `-C profile-use=rust/pgo-profile`; (5) `llvm-bolt
  -instrument` on the cdylib (self-recording, no `perf` required);
  (6) BOLT training run with the lighter `(20, 2000)` workload; (7)
  `llvm-bolt -reorder-blocks=ext-tsp` post-link reorder; (8) install
  the bolted cdylib at the canonical FFI load path
  `rust/target/release/libmcts_rust.so`.
- `MCTS.FFI.Rust.withRustSearchGame` exposes the full visit-vector
  ABI (`mcts_rust_search_move`) so the Haskell dispatcher *can* route
  `--backend rust` through the real FFI engine. The dispatcher keeps
  the Rust slot on the in-process logical UCT until the Corridors
  gameplay port (Sprint 6.3 ledger row) lands, because the placeholder
  game in the Rust engine emits action IDs that do not correspond to
  legal Corridors moves.

### Remaining Work

- Switch `MCTS.Driver.Dispatch.runBatchDispatch` to route `--backend
  rust` through `MCTS.Driver.Rust` over `runForeignSearchGame` once
  the Rust Corridors port from Sprint 6.3's ledger row lands and
  emits legal-in-Corridors action IDs.

## Sprint 6.5: Backends (iii) and (iv) Engine Envelope and Foreign-Engine Recompute ⏸️

**Status**: Blocked
**Implementation**: `cpp-functional/c-abi/envelope.{h,cc}`,
`cpp-functional/c-abi/recompute.{h,cc}`, `rust/src/envelope.rs`,
`rust/src/recompute.rs`, `src/MCTS/FFI/CppFunctional.hs`, `src/MCTS/FFI/Rust.hs`
**Blocked by**: Sprint 6.2, Sprint 6.4, Sprint 2.7
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/backend_ffi_contract.md`,
`documents/engineering/transcript_format.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Backends (iii) `cpp-functional` and (iv) `rust` implement the same
envelope-capture + foreign-engine recompute pattern as Sprints 4.7 and
5.5. Backend (iii) shares (ii)'s capture protocol (gcc, same flag
set); backend (iv) uses Rust-specific sources for the per-backend-slot
fields.

### Deliverables (backend (iii) `cpp-functional`)

- `cpp-functional/c-abi/envelope.{h,cc}` and `recompute.{h,cc}`
  mirroring Sprint 5.5. Because (iii) intentionally shares the
  optimisation stack of (ii), the populated envelope's `compiler_id`,
  `compiler_version`, `fp_flags`, and `libm_id` are byte-identical
  to (ii)'s under matched build trees (style-only divergence). The
  `engine_build_id` differs because the binaries are linked
  separately.

### Deliverables (backend (iv) `rust`)

- `rust/src/envelope.rs` building the envelope at compile time:
  - `compiler_id = 2` (rustc).
  - `compiler_version` from the `RUSTC_VERSION` env var Cargo
    exposes at build time (read by `build.rs` and emitted as a
    `rustc-env=` directive).
  - `fp_flags` from `--cfg` markers the `Cargo.toml`'s
    `[profile.release]` section emits to mirror its own settings
    (`opt-level = 3`, `lto = "fat"`, `codegen-units = 1`,
    `panic = "abort"`, `strip = "symbols"` — none of which sets
    fast-math; the envelope's `FP_FAST_MATH` bit is zero).
  - `libm_id` filled by a `build.rs` probe that detects glibc /
    musl / Rust's own libm and emits the appropriate constant
    string.
  - `engine_build_id` from a post-link `objcopy
    --update-section .envelope_build_id` step in `mcts build rust`
    that hashes `target/release/libmcts_rust.so`.
  - `cpu_features` from `is_x86_feature_detected!` cached at
    startup.
  - `fp_env` from a startup probe via the `core::arch` MXCSR
    intrinsics.
- `rust/src/recompute.rs` exposing
  `mcts_rust_recompute_equities` via `#[no_mangle] extern "C"` per
  the foreign-engine recompute FFI surface.

### Validation

- `mcts-integration`: per-backend
  `mcts_<backend>_get_envelope()` returns a struct whose
  `engine_build_id` matches the externally-measured SHA-256 of the
  loaded `.so`.
- `mcts-cross-backend`: write transcripts from (iii) and (iv);
  foreign-engine recompute each on every other live backend under
  `--rng cpp` and assert visit-agreement.
- `mcts-cross-backend`: envelope-mismatch test (re-link (iv) with a
  different `-C target-cpu`, re-run verify, assert
  `EngineEnvelopeMismatch (BackendSlot Rust) CpuFeatures expected
  got`).

### Remaining Work

- Baseline landed: backend (iii)'s `cpp-functional/c-abi/mcts_cpp_functional.h` and
  backend (iv)'s `rust/src/lib.rs` declare the `mcts_functional_envelope` /
  `MctsRustEnvelope` structs and their `mcts_functional_get_envelope()` /
  `mcts_rust_get_envelope()` accessors. The Rust accessor returns a `const`
  static envelope filled at compile time from
  `option_env!("MCTS_GIT_COMMIT")`, the target arch, and the compiler tag
  (`compiler_id = 2 = rustc`). `rust/build.rs` captures `rustc --version` inside
  the container and exports it as `MCTS_RUSTC_VERSION`, so the Rust envelope's
  `compiler_version` slot is live even in the smoke cdylib. The C++ accessor
  mirrors the (i)/(ii) shape with optimization-dependent slots zero-initialized
  pending the PGO+BOLT pipeline.
  `src/MCTS/FFI/CppFunctional.hs` and `src/MCTS/FFI/Rust.hs` expose
  `loadCppFunctionalEnvelope` and `loadRustEnvelope`, and `mcts-integration`
  validates both live envelope paths when their smoke shared libraries are present.
- Extend live envelope capture for backends (iii) and (iv) after their real drivers
  and final build surfaces exist (in particular the `engine_build_id` post-link
  patch and the `cpu_features` / `fp_env` runtime probes).
- Add foreign-engine recompute for both backends' equity sidecars.
- Add envelope-mismatch and cross-backend recompute integration coverage.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/compiler_runtime_tuning.md` — extend with the backend
  (iii) and (iv) tuning stacks, the (ii)-vs-(iii) style-isolating discipline,
  and the Rust `[profile.release]` plus `RUSTFLAGS` set.
- `documents/engineering/backend_ffi_contract.md` — extend with the
  `cpp-functional` and `rust` C ABI shapes, the `cdylib` build product, and
  the `mcts_functional_*` / `mcts_rust_*` symbol-prefix convention.
- `documents/engineering/cli_command_surface.md` — extend with `mcts build
  cpp-functional` / `mcts build rust` and the matching `--backend` dispatch
  values.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md` Backend (iii) and Backend (iv) rows update from
  `📋 Planned` to `🔄 Active` / `✅ Done` as each sprint lands.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md)
- [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
