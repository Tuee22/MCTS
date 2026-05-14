# Phase 5: Backend (ii) C++ Imperative Steelman with PGO+BOLT

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Land backend (ii) — the performance ceiling — as a maximally-tuned
> imperative C++23 implementation with arena allocation, per-rollout scratch board,
> PGO+BOLT pipeline, `mimalloc`, and the full tuning stack. Backend (v) Haskell
> must match (ii), not (i), to prove the project hypothesis.

## Phase Status

🔄 **Active**. `cpp-imperative/` now exists with a smoke-buildable C ABI skeleton, and
the Haskell CLI can exercise `cpp-imperative` as a logical backend in benchmark and
verify flows. Remaining Phase `5` closure work is the real C++23 steelman engine,
paired bench/instrumented artefacts, Haskell FFI bindings, PGO+BOLT+`mimalloc` build
harness, envelope capture, and foreign-engine recompute.

## Phase Summary

Phase `5` writes the steelman. C++23 with the doctrine-named flag set, arena-allocated
tree, per-rollout scratch board with undo, flat children layout, move-list buffer
reuse, branch hints, `__builtin_prefetch`, `__builtin_popcountll` /
`__builtin_ctzll`, `alignas(64)`, `thread_local` scratch, `-fno-exceptions`,
`Word16` ply counter; two-stage PGO via `-fprofile-generate` / `-fprofile-use`
training on benchmark (b), BOLT post-link binary reordering, `mimalloc` static-linked
as the system allocator. The build harness is a Plan/Apply command built on the
Phase 1 `Subprocess` boundary. Backend (ii) participates in the four-backend
`(ii)..(v)` cross-backend `verify` cohort (Phase 7) and in the legacy parity envelope
cohort (Phase 4).

## Sprint 5.1: `cpp-imperative/` Source Tree and Build Flags 🔄

**Status**: Active
**Implementation**: `cpp-imperative/c-abi/`, `cpp-imperative/Makefile`
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`,
`documents/engineering/backend_ffi_contract.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Write the imperative-style engine in C++23 with the full doctrine-mandated flag set
(no `-ffast-math`, no `-Ofast`), the arena-allocated tree, the per-rollout scratch
board, and the C ABI shim that matches backend (i)'s shape so the FFI bridge is
backend-agnostic from the Haskell side.

### Deliverables

- `cpp-imperative/src/` contains the imperative engine: `board.hpp/cc`
  (`Word16` ply counter; `is_terminal` ↔ `hero_wins || villain_wins || ply_count
  >= max_plies` per [00-overview.md → Hard Constraints item 9](00-overview.md);
  `terminal_eval` returns `0.0` on ply-cap termination); `tree.hpp/cc` (arena-
  allocated `std::vector<uct_node>` with `u32` child indices, freed in bulk at
  game end per
  [00-overview.md → Hard Constraints item 18](00-overview.md)); `search.hpp/cc`
  (UCT child selection); `rollout.hpp/cc` (random-rollout leaf evaluation with
  per-rollout scratch board reuse via undo or one snapshot per game).
- Flat children layout: each parent records `first_child_idx: u32` and
  `n_children: u16`; no `std::vector<u32>` per node.
- Move-list buffer reuse: move generators write into a `thread_local` or stack-SBO
  buffer sized for typical Corridors move counts (~40); heap spill allowed but
  rare.
- `__attribute__((hot))` / `__attribute__((always_inline))` on
  `select_best_child`, `apply_move`, `is_terminal`, `rollout_step`.
- `__attribute__((const))` / `((pure))` on referentially-transparent helpers.
- `[[likely]]` / `[[unlikely]]` on UCT child-selection and terminal-state
  branches.
- `__builtin_prefetch` on the child array during UCT descent.
- `__builtin_popcountll` / `__builtin_ctzll` on raw `u64` bitboards (not
  `std::bitset<64>::_Find_first()`).
- `alignas(64)` on the tree-node arena base; struct-of-arrays where measurement
  supports it.
- `thread_local` scratch buffers for the multi-threaded driver (per-worker, not
  per-game).
- Visit-count compression to `u16` when `per_move_sims < 65536`.
- **Native RNG choice.** Under `--rng native`, backend (ii) uses
  `xoshiro256++` (the
  [project README → Compiler and runtime tuning item 15](../README.md)
  candidate; `wyrand` is the alternative). The choice is recorded in
  [../documents/engineering/determinism_contract.md → RNG Source Split → Per-Backend Native RNG Table](../documents/engineering/determinism_contract.md);
  swapping to `wyrand` post-Sprint-5.3 profiling is allowed, but the table
  must be updated in the same commit so the documented choice never lags the
  implemented choice. Under `--rng cpp` the RNG is `std::mt19937_64` via the
  shared `cpp_rng_*` C ABI; the native choice is irrelevant.
- `cpp-imperative/c-abi/mcts_cpp_imperative.{h,cc}` declares and implements the
  same C ABI shape as `cpp-legacy/c-abi/mcts_cpp_legacy.h` (Phase 4 Sprint 4.1)
  with the prefix `mcts_imperative_*`. Both backends expose `Board`, `Tree`,
  `Rng` opaque handles and the same operation set.
- `cpp-imperative/Makefile` builds with the doctrine flag set per
  [00-overview.md → Hard Constraints item 18](00-overview.md):
  `-std=c++23 -O3 -march=native -mtune=native -flto -fno-plt
  -fno-semantic-interposition -fvisibility=hidden -fvisibility-inlines-hidden
  -fno-exceptions`. No `-ffast-math`, no `-Ofast`. GCC only (Clang not
  supported).
- **Paired build targets** per
  [../README.md → Cross-backend verification → Compile-time toggle for
  instrumentation](../README.md). The self-play driver in
  `cpp-imperative/src/driver.cc` is a template parameterised by a
  `Instrumentation` template type (`InstrumentedOn` / `InstrumentedOff`).
  `cpp-imperative/Makefile` builds two artefacts in one pipeline:
  `libmcts_cpp_imperative_bench.{so,a}` (instantiates driver with
  `InstrumentedOff`; `read_visits` symbol absent) and
  `libmcts_cpp_imperative_instrumented.{so,a}` (instantiates driver with
  `InstrumentedOn`; `read_visits` exported). The engine TU (search, rollout,
  board, RNG) compiles once and is statically linked into both. The toggle is
  not a runtime branch in the hot loop. `mcts bench` links the `_bench`
  artefact; `mcts verify`, `mcts play`, `mcts inspect replay` link the
  `_instrumented` artefact.
- The build products are `cpp-imperative/build/libmcts_cpp_imperative_bench.{so,a}`
  and `cpp-imperative/build/libmcts_cpp_imperative_instrumented.{so,a}`. The
  PGO+BOLT pipeline in Sprint 5.3 runs **both** artefacts through training and
  reordering; the bench artefact is the canonical one whose throughput appears
  in the report card.
- **Install step.** The `_bench.bolted.so` intermediate is renamed or symlinked
  to the canonical FFI load name `cpp-imperative/libmcts_cpp_imperative.so` per
  [../README.md → Repository layout (target)](../README.md) and
  [../documents/engineering/backend_ffi_contract.md → Backends and Linkage](../documents/engineering/backend_ffi_contract.md).
  The Haskell FFI binds against the canonical name; the suffixed/bolted names
  are private to the build harness. The `_instrumented.bolted.so` intermediate
  retains its full name (loaded only by `mcts verify`, `mcts play`,
  `mcts inspect replay`).

### Validation

1. `make -C cpp-imperative` produces the shared library under the pinned
   toolchain inside the container.
2. The compiled `.so` exports the same symbol set as backend (i), with the
   `mcts_imperative_*` prefix.
3. A unit test (after Sprint 5.2 lands the FFI bindings) creates a board, plays
   a known move sequence to a known terminal state, and asserts the legal-move
   enumeration matches a brute-force Haskell reference (the same reference Phase
   3 used).

### Remaining Work

- Baseline landed: `cpp-imperative/` has a smoke-buildable C ABI skeleton, Makefile,
  README, and `build/libmcts_cpp_imperative.so` output path.
- Replace the smoke implementation with the real C++23 imperative steelman engine.
- Add the final compiler/link flags, allocator link strategy, and source layout
  described by the sprint.
- Validate warning-clean builds and update tuning docs with any final flag decisions.

## Sprint 5.2: FFI Bindings for Backend (ii) 📋

**Status**: Planned
**Implementation**: `src/MCTS/FFI/CppImperative.hs`, `mcts.cabal`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`

### Objective

Bind the `cpp-imperative` C ABI to Haskell with the same `foreign import ccall`
pattern as backend (i), reusing the `MCTS.FFI.Common` RAII wrappers from Phase 4.

### Deliverables

- `src/MCTS/FFI/CppImperative.hs` declares the per-symbol bindings from
  `cpp-imperative/c-abi/mcts_cpp_imperative.h`. Hot-path symbols use `unsafe`;
  lifecycle symbols use `safe`.
- `mcts.cabal` declares the `cpp-imperative` extra-libraries entry plus the
  `extra-lib-dirs: cpp-imperative/build` directive.
- The `prerequisiteRegistry` gains a `libmcts-cpp-imperative-built` node with a
  remedy hint that points at the PGO+BOLT build harness (Sprint 5.3); the
  no-PGO smoke build for development is `make -C cpp-imperative
  smoke`.
- A `cpp-imperative/Makefile` `smoke` target builds without PGO/BOLT for
  development; the canonical build through the build harness runs the full
  PGO+BOLT pipeline.

### Validation

1. `cabal build all` succeeds after `make -C cpp-imperative smoke`.
2. The same handle round-trip test as Phase 4 Sprint 4.2 passes for backend
   (ii).
3. Same-backend determinism: `mcts bench rollouts --backend cpp-imperative
   --threading single --rng cpp --games 4 --seed 42` produces identical
   transcripts across two runs.

### Remaining Work

Not started.

## Sprint 5.3: PGO+BOLT+`mimalloc` Build Harness 🔄

**Status**: Active
**Implementation**: `src/MCTS/CLI/Build.hs`,
`src/MCTS/CLI/Spec.hs` (Build subtree),
`cpp-imperative/Makefile` (smoke target)
**Docs to update**: `documents/engineering/compiler_runtime_tuning.md`,
`documents/engineering/backend_ffi_contract.md`

### Objective

Implement the two-stage PGO + BOLT post-link build harness as a Plan/Apply command
running through the `Subprocess` boundary. The harness is the canonical build path
for backend (ii) (and later (iii), (iv)) and is required to produce the steelman
that backend (v) Haskell must match.

### Deliverables

- `mcts build cpp-imperative [--dry-run] [--plan-file <path>]` is a Plan/Apply
  command per [00-overview.md → Hard Constraints item 24](00-overview.md).
- The plan is a typed `[Subprocess]` sequence; both paired targets ride through
  the same pipeline (the `_bench` and `_instrumented` artefacts each go through
  PGO+BOLT):
  1. **Instrumented PGO build.** `g++ ... -fprofile-generate=cpp-imperative/pgo-profile/ ...`
     for both targets.
  2. **Training run.** Run `mcts bench selfplay --backend cpp-imperative
     --threading multi --workers 8 --rng cpp --games $PGO_TRAINING_GAMES
     --seed 42 --sims $PGO_TRAINING_SIMS` (benchmark (b) at a representative game
     count). The pinned tuple `($PGO_TRAINING_GAMES, $PGO_TRAINING_SIMS) =
     (100, 10_000)` lives in `cabal.project` alongside the report-card knobs so
     the training workload is reproducible across hosts. The PGO-instrumented
     binary writes profile data into the `pgo-profile/` directory. Training
     drives only the `_bench` target (whose throughput is what the report card
     measures).
  3. **Optimised build.** `g++ ... -fprofile-use=cpp-imperative/pgo-profile/
     -fprofile-correction ...` producing the PGO-optimised
     `libmcts_cpp_imperative_bench.so` and `libmcts_cpp_imperative_instrumented.so`.
  4. **BOLT post-link.** `llvm-bolt cpp-imperative/build/libmcts_cpp_imperative_bench.so
     -o cpp-imperative/build/libmcts_cpp_imperative_bench.bolted.so -data
     cpp-imperative/bolt-profile/perf.fdata`, and the same for the
     `_instrumented` artefact. The perf data comes from the BOLT
     instrumentation, which itself runs benchmark (b).
  5. **`mimalloc` link.** Static link `mimalloc` per
     [00-overview.md → Hard Constraints item 18](00-overview.md) for both
     artefacts. Static link is preferred for FFI determinism; `LD_PRELOAD` is
     acceptable for ad-hoc benchmark runs.
  6. **Install.** Rename or symlink the `_bench.bolted.so` intermediate to the
     canonical FFI load name `cpp-imperative/libmcts_cpp_imperative.so` per
     [../README.md → Repository layout (target)](../README.md). The
     `_instrumented.bolted.so` intermediate keeps its full name; it lives at
     `cpp-imperative/libmcts_cpp_imperative_instrumented.so` (symlink) for
     `mcts verify`/`play`/`inspect replay` loads.
- `src/MCTS/CLI/Build.hs` builds and applies the plan, with `--dry-run` rendering
  the typed `Subprocess` sequence and exiting 0.
- `src/MCTS/CLI/Command.hs` gains the `BuildCppImperative` constructor on the
  `BuildCommand` family per
  [phase-1-haskell-cli-surface.md → Sprint 1.2 ownership note](phase-1-haskell-cli-surface.md),
  with a matching `CommandSpec` leaf and at least one `Example`
  (`mcts build cpp-imperative --dry-run`) wired into the registry so the
  `mcts <subcommand> --help`, `documents/cli/commands.md`, and
  `mcts commands --json` outputs all carry the new surface.
- The `prerequisiteRegistry` gains nodes for `llvm-bolt`, `perf` (for BOLT
  profile generation), `mimalloc-static`, and the PGO and BOLT profile
  directories.

### Validation

1. `mcts build cpp-imperative --dry-run` renders the typed `Subprocess`
   sequence and exits 0.
2. `mcts build cpp-imperative` runs the full pipeline and produces both
   `libmcts_cpp_imperative_bench.bolted.so` and
   `libmcts_cpp_imperative_instrumented.bolted.so`; the `_bench` artefact is
   strictly faster than the smoke non-PGO build on `mcts bench selfplay
   --backend cpp-imperative --games 100`
   (the speedup is the proof that PGO+BOLT had a measurable effect; the exact
   ratio is recorded in the engineering doc, not pinned).
3. The build harness goes through the `Subprocess` boundary; an `hlint` check
   confirms no `callProcess` / `readCreateProcess` / `System.Process` call
   sites exist in `src/MCTS/CLI/Build.hs`.

### Remaining Work

- Baseline landed: `mcts build cpp-imperative --dry-run` renders a typed plan and the
  apply path smoke-builds `cpp-imperative/` through `make`.
- Replace the smoke `make` plan with the full two-stage PGO, BOLT, and `mimalloc`
  pipeline.
- Add prerequisite checks for GCC, LLVM/BOLT, allocator availability, and profile
  directories.
- Add idempotence and failure-mode tests for the generated build plan.

## Sprint 5.4: Backend (ii) Game Driver and Transcript Output 🔄

**Status**: Active
**Implementation**: `src/MCTS/Driver.hs`,
`src/MCTS/CLI/Bench.hs`, `src/MCTS/CLI/Verify.hs`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/cli_command_surface.md`

### Objective

Wire backend (ii) into the bench, verify, and play dispatch so `mcts bench
rollouts/selfplay --backend cpp-imperative` and `mcts verify
rollouts/selfplay/legacy-parity` (where cohort includes (ii)) run end-to-end.

### Deliverables

- `src/MCTS/Driver/CppImperative.hs` exposes `runGameCppImperative :: GameInputs
  -> App Transcript`, mirroring the Phase 3 Haskell driver and the Phase 4
  legacy-port driver but driving the FFI-backed backend (ii) tree.
- The driver respects backend (ii)'s ply-cap draw rule (the engine's `Word16`
  ply counter and the `is_terminal` ↔ `... || ply_count >= max_plies` semantic
  from Sprint 5.1).
- `src/MCTS/CLI/Bench.hs` dispatch table adds `--backend cpp-imperative`.
- `src/MCTS/CLI/Verify.hs` `VerifyBackend` GADT (Phase 4 Sprint 4.6 introduced
  this) gains `VCppImperative`. The four-backend `(ii)..(v)` cohort is now
  parseable, though full bit-equality requires Phases 6 + 7 closure to land the
  remaining backends.

### Validation

1. `mcts bench rollouts --backend cpp-imperative --threading single --rng cpp
   --games 8 --seed 42` runs to completion and writes 8 transcripts.
2. Same-backend determinism: two runs produce identical determinism payload sets.
3. `mcts verify rollouts --backend cpp-imperative,haskell --threading single
   --games 1 --seed 42 --max-plies 200 --sims 10` runs to completion (a
   cohort of two is the minimum parseable size). Bit-equality success or
   failure of visit counts at this stage is informational — Phase 7's full
   cohort is where the determinism contract is enforced — but the wiring is
   exercised here.

### Remaining Work

- Baseline landed: the logical in-process driver can run `--backend cpp-imperative`
  through bench, verify, transcript, and report-card smoke surfaces.
- Replace the logical stand-in with `src/MCTS/Driver/CppImperative.hs` and the real
  backend (ii) C ABI.
- Add transcript-output validation for the optimized engine.
- Add two-backend wiring smoke tests against Haskell once both real drivers exist.

## Sprint 5.5: Backend (ii) Engine Envelope and Foreign-Engine Recompute ⏸️

**Status**: Blocked
**Implementation**: `cpp-imperative/c-abi/envelope.{h,cc}`,
`cpp-imperative/c-abi/recompute.{h,cc}`, `src/MCTS/FFI/CppImperative.hs`,
`src/MCTS/Driver/CppImperative.hs`
**Blocked by**: Sprint 5.2, Sprint 5.4, Sprint 2.7
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/backend_ffi_contract.md`,
`documents/engineering/transcript_format.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Backend (ii) implements the same envelope-capture + foreign-engine
recompute pattern as Sprint 4.7, with `compiler_id` = `0` (g++),
`compiler_version` derived from the build-time GCC version, and
`fp_flags` reflecting the (ii) build's `-O3 -march=native -mtune=native
-flto -fno-plt -fno-semantic-interposition -fvisibility=hidden
-fvisibility-inlines-hidden -fno-exceptions` flag set. `engine_build_id`
hashes the bolted `libmcts_cpp_imperative.so` (the `_bench` variant
that ships at the canonical FFI load path).

### Deliverables

- `cpp-imperative/c-abi/envelope.{h,cc}` mirroring Sprint 4.7's pattern.
- `cpp-imperative/c-abi/recompute.{h,cc}` exposing
  `mcts_imperative_recompute_equities` over the foreign-engine FFI
  surface from
  [../documents/engineering/backend_ffi_contract.md → Foreign-Engine
  Recompute](../documents/engineering/backend_ffi_contract.md).
- Build harness extension: the PGO+BOLT pipeline gains a final
  post-link `objcopy --update-section .envelope_build_id`
  step that computes the SHA-256 of the bolted `.so` and embeds it
  as the `engine_build_id` constant. The patch is performed *after*
  BOLT runs, so the embedded digest reflects the final shipping
  binary.

### Validation

- `mcts-integration`: `mcts_imperative_get_envelope()` returns a
  struct whose `engine_build_id` equals
  `sha256(cpp-imperative/libmcts_cpp_imperative.so)` measured
  externally.
- `mcts-cross-backend`: write a (ii) transcript, rebuild (ii) with
  a different `-march=` value, re-run `mcts verify rollouts
  --backend cpp-imperative,cpp-functional` against the cached
  transcript, assert `AppError EngineEnvelopeMismatch (BackendSlot
  CppImperative) CpuFeatures expected got`.
- `mcts-cross-backend`: foreign-engine recompute of a
  `cpp-functional` transcript on (ii) returns visits identical to
  the transcript under `--rng cpp` (the existing determinism
  contract) and acceptable `equity_l2_drift`.

### Remaining Work

- Add backend (ii)'s live envelope capture after the real optimized driver exists.
- Add foreign-engine recompute for backend (ii) equity sidecars.
- Patch the final post-BOLT shared library with the shipping `engine_build_id`.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/compiler_runtime_tuning.md` — fill in the backend (ii)
  flag set, the priority-tier optimisation list, the PGO+BOLT+`mimalloc`
  pipeline, and the exclusion of `-ffast-math` / `-Ofast`.
- `documents/engineering/backend_ffi_contract.md` — extend with the
  `cpp-imperative` C ABI shape, the `unsafe`/`safe` choice per symbol, and the
  build harness contract.
- `documents/engineering/cli_command_surface.md` — extend with `mcts build
  cpp-imperative` and the `--backend cpp-imperative` dispatch.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md` Backend (ii) row updates from `📋 Planned` to `🔄
  Active` on Sprint 5.1 start and `✅ Done` on Sprint 5.4 closure.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [phase-3-haskell-engine.md](phase-3-haskell-engine.md)
- [phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md)
- [phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md)
- [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
