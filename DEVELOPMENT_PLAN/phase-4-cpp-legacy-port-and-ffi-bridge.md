# Phase 4: Backend (i) C++ Legacy Port and FFI Bridge

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Land backend (i) — the strictly verbatim re-port of `MCTS_legacy`
> exposed via a stable C ABI through the Haskell FFI — plus the build harness, the
> `--rng cpp` `std::mt19937_64` plumbing, and the `test/golden/legacy/` Q6 fixture
> set.

## Phase Status

🔄 **Active**. `cpp-legacy/` now exists with smoke-buildable C ABI and RNG skeletons,
and the Haskell CLI can exercise `cpp-legacy` as a logical backend in benchmark and
legacy-parity flows. Remaining Phase `4` closure work is the actual verbatim
`~/MCTS_legacy/backend/core` port, Haskell `foreign import ccall` bindings, shared
`std::mt19937_64` FFI plumbing, external Q6 golden fixtures, envelope capture, and
foreign-engine recompute.

## Phase Summary

Phase `4` ports `~/MCTS_legacy/backend/` verbatim into `cpp-legacy/` with only the
minimum changes required to expose a C ABI. The legacy keeps its
`std::shared_ptr<uct_node>` trees, `std::mt19937_64` RNG, single-threaded design, and
its no-draw-rule terminal semantics (`is_terminal()` ↔ `hero_wins() ||
villain_wins()`); the legacy is a strictly verbatim regression-sanity port, not a
performance ceiling, and the `VerifyBackend` GADT excludes it from the default
cross-backend `verify` cohort. Phase 4 also lands the `--rng cpp` C++ generator the
other backends will draw from in Phase 5+, the Q6 golden fixture set from
out-of-band `MCTS_legacy` runs, and the `mcts verify legacy-parity` cohort logic
that pins `max_plies = 10000` so all five backends agree under the envelope.

## Sprint 4.1: `cpp-legacy/` Verbatim Re-Port 🔄

**Status**: Active
**Implementation**: `cpp-legacy/c-abi/`, `cpp-legacy/Makefile`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/compiler_runtime_tuning.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Copy `~/MCTS_legacy/backend/` into `cpp-legacy/` with the absolute minimum changes:
add a C ABI shim layer (`cpp-legacy/c-abi/`); rename the build product to
`libmcts_cpp_legacy.{so,a,dylib}`; preserve every other line.

### Deliverables

- `cpp-legacy/src/` and `cpp-legacy/include/` mirror `~/MCTS_legacy/backend/core/`
  contents verbatim. No code-level edits. No structural reorganisation.
- `cpp-legacy/c-abi/mcts_cpp_legacy.h` declares the C ABI: opaque handles for
  `Board`, `Tree`, `Rng`; `mcts_legacy_new_board`, `mcts_legacy_apply_move`,
  `mcts_legacy_is_terminal`, `mcts_legacy_select_uct_move`, `mcts_legacy_rollout`,
  `mcts_legacy_backprop`, `mcts_legacy_free_board`, `mcts_legacy_free_tree`, and
  the `mcts_legacy_rng_*` family. The complete C ABI function inventory (every
  backend's symbols, opaque-handle types, lifecycle, ownership) is canonical in
  [../documents/engineering/backend_ffi_contract.md → C ABI
  Shape](../documents/engineering/backend_ffi_contract.md); this sprint conforms
  to that contract rather than redefining it.
- `cpp-legacy/c-abi/mcts_cpp_legacy.cc` implements the shims by delegating to the
  unchanged C++ types from `cpp-legacy/src/`.
- `cpp-legacy/Makefile` builds with the legacy's exact flags per
  [00-overview.md → Hard Constraints item 17](00-overview.md):
  `-std=c++17 -O3 -fPIC -Wall`. The build product is
  `cpp-legacy/build/libmcts_cpp_legacy.{so,a}`.
- No `-march=native`, no `-flto`, no `mimalloc`, no BOLT, no PGO — backend (i) is
  exempt from the optimisation stack per
  [00-overview.md → Hard Constraints item 17](00-overview.md).
- A `cpp-legacy/README.md` notes the verbatim status, points readers at the
  legacy source path, and warns that adjustments beyond FFI shims are forbidden
  (and would enqueue under
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) as residue
  to revert).
- The `prerequisiteRegistry` (Phase 1 Sprint 1.7) gains a `gcc-cpp17` node
  declaring the `g++` minimum version with a remedy hint pointing at the
  `docker compose` entrypoint.
- `src/MCTS/CLI/Command.hs` gains the `BuildCppLegacy` constructor on the
  `BuildCommand` family per
  [phase-1-haskell-cli-surface.md → Sprint 1.2 ownership note](phase-1-haskell-cli-surface.md).
  The matching `mcts build cpp-legacy` Plan/Apply runs `make -C cpp-legacy`
  (the legacy-flags subset only — no PGO/BOLT/mimalloc) as a typed
  `[Subprocess]` sequence; the constructor exists for ADT symmetry rather
  than to apply the steelman optimisation regime.

### Validation

1. `make -C cpp-legacy` produces `cpp-legacy/build/libmcts_cpp_legacy.so` under
   the pinned toolchain.
2. A line-level diff `diff -ruw ~/MCTS_legacy/backend/core/ cpp-legacy/src/`
   produces only documentation, comment, or whitespace differences (every
   structural difference is forbidden and would block the sprint).
3. The compiled `.so` exports exactly the symbols declared in
   `cpp-legacy/c-abi/mcts_cpp_legacy.h`.

### Remaining Work

- Baseline landed: `cpp-legacy/legacy-core/` carries the mechanically imported
  `~/MCTS_legacy/backend/core/{board.cpp,board.h,flags.hpp,mc_tools.hpp,mcts.hpp}`
  sources, and `cpp-legacy/c-abi/mcts_cpp_legacy.cc` delegates board allocation,
  terminal checks, and UCT move selection to the legacy `corridors::board` /
  `mcts::uct_node` types.
- The Makefile builds `cpp-legacy/build/libmcts_cpp_legacy.so` with the legacy
  `-std=c++17 -O3 -fPIC -Wall` shape plus a narrow `-Wno-pessimizing-move`
  compatibility suppression for the verbatim legacy return statement; `make -C
  cpp-legacy clean smoke` is warning-clean on the container compiler.
- Keep all future non-FFI changes out of the port and record any unavoidable
  compatibility residue in `legacy-tracking-for-deletion.md`.

## Sprint 4.2: Haskell FFI Bindings 🔄

**Status**: Active
**Implementation**: `src/MCTS/FFI/CppLegacy.hs`, `src/MCTS/FFI/Common.hs`,
`mcts.cabal`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/haskell_code_guide.md`

### Objective

Bind the C ABI from Haskell with the `foreign import ccall` pattern, plus the typed
wrappers that make every call safe (no leaked handles, no double-free).

### Deliverables

- `src/MCTS/FFI/Common.hs` declares the typed wrappers shared by all four C-ABI
  backends: `withBoard`, `withTree`, `withRng`, the `bracket`-based RAII pattern
  that guarantees handle release even on exceptions, plus `AppError FFIFailure`
  error rendering for C ABI exceptions surfaced through the FFI bridge. The
  `FFIFailure` constructor carries the backend identity (`Backend`), the C ABI
  symbol that raised, and the decoded error message; it is semantically
  distinct from `SubprocessFailed`, which is reserved for the typed
  `Subprocess` boundary (`runStreaming` / `capture` non-zero exits). See
  [00-overview.md → Error Handling](00-overview.md) and
  [../documents/engineering/backend_ffi_contract.md → Error rendering](../documents/engineering/backend_ffi_contract.md).
- `src/MCTS/FFI/CppLegacy.hs` declares the per-symbol bindings from
  `cpp-legacy/c-abi/mcts_cpp_legacy.h` via `foreign import ccall unsafe`. Hot-path
  symbols (`select_uct_move`, `rollout`, `apply_move`) use `unsafe`; lifecycle
  symbols (`new_board`, `free_board`) use `safe`.
- `mcts.cabal` declares the `cpp-legacy` extra-libraries entry plus the
  `extra-lib-dirs: cpp-legacy/build` directive so `cabal build all` links the
  shared library.
- The `prerequisiteRegistry` gains a `libmcts-cpp-legacy-built` node that
  validates `cpp-legacy/build/libmcts_cpp_legacy.so` exists; the remedy hint is
  `make -C cpp-legacy`.

### Validation

1. `cabal build all` links `libmcts_cpp_legacy.so` successfully.
2. A unit test creates and frees `Board`, `Tree`, and `Rng` handles 1M times in a
   loop with no leak (validated under `valgrind --leak-check=full` inside the
   container).
3. A round-trip test: create a `Board` via the FFI, apply a move via the FFI,
   read the resulting state back, compare against a known result.

### Remaining Work

- Baseline landed: `src/MCTS/FFI/Common.hs` declares
  `withBoard` / `withTree` / `withRng` bracket helpers, the
  `EngineEnvelope` record that mirrors the C ABI
  `mcts_<backend>_envelope` struct, and `liftFFI` that lifts every IO
  action into `Either AppError a` (converting any `SomeException` to
  `AppError FFIFailure backend symbol message`).
  `src/MCTS/FFI/CppLegacy.hs`, `src/MCTS/FFI/CppImperative.hs`,
  `src/MCTS/FFI/CppFunctional.hs`, and `src/MCTS/FFI/Rust.hs` declare
  per-backend board handle wrappers. The stand-in unit handles have been
  replaced by opaque `Ptr ()` newtypes allocated and freed through
  `withDynamicBoard`, which uses `dlopen` / `dlsym` plus
  `foreign import ccall "dynamic"` function pointers for the backend
  `mcts_<backend>_new_board` / `mcts_<backend>_free_board` symbols. This keeps
  Cabal builds independent of platform-specific shared-library paths while still
  exercising the real C ABI. The prerequisite registry now includes
  `libmcts-cpp-legacy-built` with a `cxx` dependency, and `mcts-unit` runs a
  bounded dynamic board acquire/free smoke when
  `cpp-legacy/build/libmcts_cpp_legacy.so` is present.
- Add the 1M-handle round-trip leak test under `valgrind --leak-check=full`
  inside the Docker container.

## Sprint 4.3: `--rng cpp` Shared `std::mt19937_64` Plumbing 🔄

**Status**: Active
**Implementation**: `cpp-legacy/c-abi/rng.h`, `cpp-legacy/c-abi/rng.cc`,
`src/MCTS/Rng/Mix.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/backend_ffi_contract.md`

### Objective

Expose the `std::mt19937_64` generator to Haskell over the FFI so that every
participating backend can draw from the same C++ generator under `--rng cpp`. This
is the determinism contract's shared-RNG path.

### Deliverables

- `cpp-legacy/c-abi/rng.h` declares the C ABI for the `std::mt19937_64` generator
  per [../README.md → Cross-backend verification → RNG FFI contract](../README.md).
  The four exported symbols are:
  ```c
  cpp_rng* cpp_rng_new(uint64_t seed);
  uint64_t cpp_rng_next_u64(cpp_rng*);
  cpp_rng* cpp_rng_split(uint64_t master_seed, uint64_t game_index);
  void     cpp_rng_free(cpp_rng*);
  ```
  `cpp_rng_split` returns a fresh `cpp_rng*` whose internal state is seeded from
  `splitmix64(master_seed, game_index)` — this is how per-game sub-seeds are
  derived without mutating the parent generator state. Workers therefore do not
  carry RNG identities; the seed lives with the game, and worker-to-game
  assignment never changes a game's output.
- `cpp-legacy/c-abi/rng.cc` wraps the standard library generator. The
  implementation lives in `cpp-legacy/` (verbatim port territory) because the
  legacy itself uses this generator; later backends (ii)–(iv) will dlopen-or-link
  this same exported symbol set rather than provide their own copies of
  `std::mt19937_64`, so the determinism contract is single-sourced.
- `src/MCTS/Rng/Cpp.hs` exposes the Haskell-side `CppRng` consumer:
  `withCppRngForGame :: Word64 -> Word64 -> (CppRngHandle -> App a) -> App a`
  (master_seed → game_index → action) calls `cpp_rng_split` under the hood to get
  a per-game handle, and `cppRngNextU64 :: CppRngHandle -> App Word64` draws bytes
  from it. `cppRngFree` is paired into the bracket so the handle is always
  released. `cpp_rng_new` is exposed for tests that need a non-split handle.
- The `--rng cpp` flag is plumbed through `BenchOptions` (Phase 3 Sprint 3.5
  reserved the field). The `mcts bench rollouts/selfplay --backend cpp-legacy
  --rng cpp` invocation is end-to-end at Sprint 4.4 closure.

### Validation

1. A unit test pins a specific `(seed, n)` pair to a specific
   `cppRngNextU64`-produced `Word64` sequence (the values come from a verbatim
   `std::mt19937_64` reference).
2. Same-backend determinism: two runs of `mcts bench rollouts --backend
   cpp-legacy --rng cpp --games 4 --seed 42` produce identical determinism payloads.
3. The `prerequisiteRegistry` `libmcts-cpp-legacy-built` node passes its check.

### Remaining Work

- Baseline landed: `cpp-legacy/c-abi/rng.h` and `rng.cc` provide the shared C++
  RNG ABI, including `cpp_rng_split_seed(master_seed, game_index)` for direct
  cross-language splitmix fixtures. `src/MCTS/Rng/Cpp.hs` dynamically calls that
  symbol through `foreign import ccall "dynamic"`, and `mcts-unit` checks the
  C++ split seed against the Haskell `MCTS.Rng.Mix.mix` vectors when the legacy
  shared library is built.
- Route `--rng cpp` through the shared `std::mt19937_64` stream for real foreign
  backends once the real backend drivers replace the logical cohort.
- Verify every backend consumes identical `u64` streams under the byte-consumption
  contract.

## Sprint 4.4: Backend (i) Game Driver and Transcript Output 🔄

**Status**: Active
**Implementation**: `src/MCTS/Driver.hs`, `src/MCTS/CLI/Bench.hs`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`

### Objective

Wire backend (i) into the bench / verify driver so `mcts bench rollouts --backend
cpp-legacy` and the eventual `mcts verify legacy-parity --backend cpp-legacy,...`
run end-to-end, write transcripts in the Phase 2 wire format, and respect the
backend (i)'s no-draw-rule terminal semantics.

### Deliverables

- `src/MCTS/Driver/CppLegacy.hs` exposes `runGameCppLegacy :: GameInputs -> App
  Transcript`, mirroring `MCTS.Driver.Game.runGame` (Phase 3 Sprint 3.4) but
  driving the FFI-backed backend (i) tree.
- **Paired build-target exemption for backend (i).** The verbatim port has no
  instrumentation to disable: the legacy C++ engine has neither a transcript
  writer nor a `read_visits` symbol of its own, and the C ABI shim in
  `cpp-legacy/c-abi/` is too thin to host a template flag. Backend (i) therefore
  ships **one** build product `libmcts_cpp_legacy.so` (not two), and the
  Haskell-side `src/MCTS/Driver/CppLegacy.hs` carries the transcript writer and
  the instrumentation surface on top of the shared library. This is the only
  exemption from the paired-target scheme per
  [../README.md → Cross-backend verification → Compile-time toggle for
  instrumentation](../README.md); it is recorded here so the Sprint 0.2 audit
  does not flag the missing `*-bench` / `*-instrumented` split as an omission.
- The driver respects backend (i)'s legacy semantics: no `max_plies` ply cap (the
  legacy aborts on `MAX_ROLLOUT_ITERS = 10000` via exception); the `--max-plies`
  CLI flag is silently ignored for backend (i) per
  [00-overview.md → Hard Constraints item 9](00-overview.md).
- The transcript writer emits the wire format with `backend_id = cpp-legacy`,
  preserving the same `(action_id, visits)` sparse-record layout.
- `src/MCTS/CLI/Bench.hs` (Phase 3 Sprint 3.5) gains `--backend cpp-legacy`
  dispatch.

### Validation

1. `mcts bench rollouts --backend cpp-legacy --threading single --rng cpp
   --games 8 --seed 42` runs to completion and writes 8 transcripts.
2. Same-backend determinism (Q4): two such runs produce identical determinism
   payload sets.
3. `mcts inspect show <prefix>` on a backend (i) transcript renders correctly in
   the legacy move notation.

### Remaining Work

- Baseline landed: the logical in-process driver can run `--backend cpp-legacy` through
  the shared transcript/cache/verify surfaces.
- Replace the logical stand-in with `src/MCTS/Driver/CppLegacy.hs` and real C ABI calls
  once Sprint 4.2 closes.
- Ensure backend (i)'s no-draw terminal semantics and legacy overflow behavior surface
  through `AppError LegacyParityRolloutOverflow`.
- Add transcript-output validation against the verbatim port.

## Sprint 4.5: `test/golden/legacy/` Q6 Fixture Set 🔄

**Status**: Active
**Implementation**: `test/golden/legacy/README.md`,
`test/golden/legacy/transcripts/<arch>/*.tr`,
`test/integration/CppLegacyParity.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/unit_testing_policy.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Capture a fixed set of `MCTS_legacy`-produced transcripts under `test/golden/legacy/`
so Phase 7's `mcts-integration` stanza can compare backend (i)'s transcripts against
this anchor (Q6).

### Deliverables

- `test/golden/legacy/README.md` documents how the fixtures are produced:
  out-of-band from `~/MCTS_legacy/` using the legacy's own binary on a
  pinned seed set, then byte-converted to the Phase 2 wire format via a one-time
  conversion script that lives under `cpp-legacy/tools/legacy-to-wire.cc` (or
  equivalent). The conversion script stamps the canonical `host_arch u8` byte for
  the host it ran on (see [../documents/engineering/transcript_format.md →
  Header](../documents/engineering/transcript_format.md)).
- The fixture set covers benchmark (b) self-play at the report-card legacy-parity
  knobs: seed `$S_LP = 42`, `$G_LP = 10` games, `$S_LP_SIMS = 10_000` sims/move,
  `--max-plies 10000` (the legacy parity envelope, so terminal semantics agree).
- Fixtures are per-architecture and per game:
  `test/golden/legacy/transcripts/<arch>/<sha>.tr` with `<arch>` ∈ `{amd64,
  arm64}`. Each supported host architecture ships its own fixture set generated on
  that arch (per [../README.md → Architecture envelope](../README.md)).
- `test/integration/CppLegacyParity.hs` declares the Q6 golden cohort: it runs
  `mcts bench selfplay --backend cpp-legacy --rng cpp --max-plies 10000 --seed
  $S_LP --games $G_LP --sims $S_LP_SIMS` and compares the resulting per-game
  transcript set byte-by-byte against `test/golden/legacy/transcripts/<arch>/`
  for the current host arch. Sprint 7.1 wires this test into the `mcts-integration`
  stanza (it does **not** live in the `mcts-legacy-parity` stanza, which
  round-robins live binaries instead).
- The fixture set is a frozen historical record: it regenerates only when
  `MCTS_legacy` is upgraded **or** the wire format's `flags u32` bumps. Otherwise
  it's a checked-in artefact; any other refresh is a separate scheduled sprint
  that touches `~/MCTS_legacy` and is enqueued as cleanup.

### Validation

1. `test/golden/legacy/transcripts/<arch>/` contains the pinned-seed per-game
   `.tr` fixture set for each supported host arch.
2. The conversion script under `cpp-legacy/tools/` is documented but not invoked
   during normal testing — fixtures are checked in.
3. A static check confirms `test/golden/legacy/` is named in the
   `trackingGeneratedPaths` no-hand-edit registry (with the explicit exception
   that the registry's "renderer-source modules" check does not apply, because
   the renderer is an external legacy binary).

### Remaining Work

- Baseline landed: `test/golden/legacy/README.md` exists as the fixture-set home.
- Generate the real out-of-band fixtures from `~/MCTS_legacy`.
- Add fixture metadata and validation commands for Q6.
- Wire the `mcts-legacy-parity` stanza to consume the real fixture set rather than
  only the logical cohort.

## Sprint 4.6: `mcts verify legacy-parity` Cohort Logic 🔄

**Status**: Active
**Implementation**: `src/MCTS/CLI/Verify.hs`,
`src/MCTS/CLI/Spec.hs` (Verify subtree)
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/cli_command_surface.md`

### Objective

Land the `mcts verify legacy-parity` subcommand that runs all five backends under
the legacy parity envelope (`max_plies = 10000`, fixture seed pinned, `--rng cpp`,
`--threading single`) and asserts every pair of transcripts agrees on visit counts.

### Deliverables

- `src/MCTS/CLI/Spec.hs` adds the `Verify VerifyCommand` subtree carrying
  `VerifyLegacyParity LegacyParityOptions` per the project [README → CLI command
  topology](../README.md). `LegacyParityBackend` is a GADT-indexed type that
  requires `LpCppLegacy` at parse time per
  [00-overview.md → Hard Constraints item 8](00-overview.md); cohorts without
  `cpp-legacy` fail with `AppError VerifyCohortTooSmall`.
- `LegacyParityOptions` pins `RngSource = CppRng`, `Threading = SingleThreaded`,
  `max_plies = MAX_ROLLOUT_ITERS = 10000` non-user-overridable. The
  `lpSeed :: Word64` field defaults to the report-card knob `S_LP = 42`. The
  workload is one of `LpRollouts` or `LpSelfplay`.
- `src/MCTS/CLI/Verify.hs` runs the cohort: for each requested backend, run
  `mcts bench {rollouts,selfplay}`-equivalent with the pinned envelope, collect
  the transcripts, round-robin compare on visit counts. Any mismatched pair
  emits `AppError VerifyMismatch` with the canonical payload
  `(left_backend, right_backend, game_id, move_index, left_record, right_record)`
  per
  [../documents/engineering/determinism_contract.md → Verify Mismatch Output](../documents/engineering/determinism_contract.md).
  If backend (i) throws or reaches
  `MAX_ROLLOUT_ITERS`, the cohort emits `AppError LegacyParityRolloutOverflow`
  carrying `(seed, game_index, move_index)`.
- The Q3 cousin (`mcts verify rollouts` / `mcts verify selfplay` for the four-
  backend `(ii)..(v)` cohort) is owned by Phase 7 Sprint 7.2; Sprint 4.6 lands
  the legacy-parity subcommand only.

### Validation

1. With backend (i) live but no other backends, `mcts verify legacy-parity
   selfplay --backend cpp-legacy` fails with `AppError VerifyCohortTooSmall` (a
   cohort of one cannot prove parity).
2. With backends (i) and (v) live (Phase 3 + Phase 4 only), `mcts verify
   legacy-parity selfplay --backend cpp-legacy,haskell --games 1 --seed 42
   --sims 10` runs to completion. Bit-equality of visit counts cannot be
   asserted until all five backends are live (Phase 7 closure); at Phase 4
   close, the command runs and the visit-count comparison is wired but the
   cohort is incomplete.
3. The fixture seed `S_LP = 42` does not trip
   `MAX_ROLLOUT_ITERS` on backend (i) for the pinned game-counts and sim
   budgets; a pre-flight smoke run asserts this.

### Remaining Work

- Baseline landed: `mcts verify legacy-parity {rollouts|selfplay}` parses workload,
  requires `cpp-legacy`, pins `CppRng`, pins single-threaded execution and
  `max_plies = 10000`, and compares the logical five-backend cohort.
- Replace logical backend execution with real backend (i) FFI execution.
- Add longest-rollout/cap-overflow pre-flight checks against the verbatim port.
- Add fixture-seed coverage once `test/golden/legacy/` contains external legacy
  artefacts.

## Sprint 4.7: Backend (i) Engine Envelope and Foreign-Engine Recompute ⏸️

**Status**: Blocked
**Implementation**: `cpp-legacy/c-abi/`, `src/MCTS/FFI/CppLegacy.hs`,
`src/MCTS/Driver/CppLegacy.hs`
**Blocked by**: Sprint 4.2, Sprint 4.4, Sprint 2.7
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/backend_ffi_contract.md`,
`documents/engineering/transcript_format.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Backend (i) populates its engine envelope from build-time constants
and exposes a foreign-engine recompute entry point. The `cpp_rng.so`
that backend (i) ships also stamps the canonical
`shared_rng_build_id` (the SHA-256 of `libmcts_cpp_legacy.so` itself,
since backend (i) IS the canonical `std::mt19937_64` owner under both
`--rng cpp` and `mcts verify legacy-parity` cohorts). See
[../documents/engineering/determinism_contract.md → Engine Envelope](../documents/engineering/determinism_contract.md)
and [../documents/engineering/backend_ffi_contract.md → Engine
Envelope Surface](../documents/engineering/backend_ffi_contract.md).

### Deliverables

- `cpp-legacy/c-abi/envelope.h` / `envelope.cc` — the per-process
  static `mcts_legacy_envelope` struct populated at build time.
  `engine_build_id` is filled by a post-link build step that hashes
  `libmcts_cpp_legacy.so` and writes the digest into a reserved
  `.envelope_build_id` ELF section (`objcopy
  --update-section`). `compiler_id` = `0` (gcc); `compiler_version`
  derived from `__GNUC__` / `__GNUC_MINOR__` /
  `__GNUC_PATCHLEVEL__`. `fp_flags` reflects the legacy's exact
  flag set: `FP_FAST_MATH=0`, `FP_FMA_ALLOWED=1` (default GCC),
  `FP_CONTRACT_ON=1`, `FP_DENORMALS_ON=1`, `FP_X87_USED=0`.
  `libm_id` filled from a probe of `getconf GNU_LIBC_VERSION` at
  build time. `cpu_features` populated at the first
  `mcts_legacy_get_envelope` call via `__builtin_cpu_supports`.
  `fp_env` captured at the same call via `fegetround` + MXCSR
  inspection.
- `cpp-legacy/c-abi/recompute.cc` — `mcts_legacy_recompute_equities`
  re-uses the existing per-game driver from Sprint 4.4 with a
  transcript-replay code path: parse the `RunConfig` from the
  transcript bytes, run the search game-by-game using the
  transcript's seed and budget, and stream `(move_index, action_id[],
  visits[], equity[])` records back to Haskell through the `EqStream`
  FFI. Recompute respects the transcript's `--rng cpp` envelope: if
  the transcript was written with `rng_source = cpp`, the recompute
  draws from the shared `cpp_rng.so` (which backend (i) itself owns)
  and hard-asserts visit-agreement.
- Build harness extension: `mcts build cpp-legacy` Plan/Apply gains
  a post-link "envelope patch" step that computes
  `sha256(libmcts_cpp_legacy.so)` and `objcopy
  --update-section`s the result into `.envelope_build_id`. The patch
  is bytewise idempotent across rebuilds with no content changes;
  reproducible builds remain reproducible.

### Validation

- `mcts-integration`: after `mcts build cpp-legacy`, the loaded
  `mcts_legacy_get_envelope()` returns a struct whose
  `engine_build_id` equals
  `sha256(cpp-legacy/libmcts_cpp_legacy.so)` measured externally
  (`sha256sum` matches the embedded constant).
- `mcts-integration`: write a transcript with backend (i), modify
  `libmcts_cpp_legacy.so` (e.g., re-link with a different commit
  embedded in `engine_git_commit`), re-run `mcts verify
  legacy-parity` against the cached transcript, assert it fails
  with `AppError EngineEnvelopeMismatch (BackendSlot CppLegacy)
  EngineBuildId expected got`.
- `mcts-cross-backend`: re-run the foreign-engine recompute path for
  a `cpp-imperative` transcript on backend (i)'s recompute FFI,
  assert visit-agreement under `--rng cpp` and acceptable
  `equity_l2_drift` under the divergence-smell thresholds.

### Remaining Work

- Baseline landed: `cpp-legacy/c-abi/mcts_cpp_legacy.h` and the matching `.cc`
  now declare the `mcts_legacy_envelope` struct and the
  `mcts_legacy_get_envelope(void)` accessor with the layout specified in
  [../documents/engineering/backend_ffi_contract.md → Engine Envelope](../documents/engineering/backend_ffi_contract.md).
  The accessor returns a process-static envelope value whose `envelope_version`,
  `rng_source_envelope`, `host_arch_envelope`, `engine_git_commit`, and
  `compiler_id` slots are filled at first call; `engine_build_id`,
  `cohort_config_hash`, `shared_rng_build_id`, `compiler_version`, `libm_id`,
  `fp_flags`, `fp_env`, and `cpu_features` are zero-initialized pending the
  post-link patch step and runtime probe work scheduled by Sprint `4.7`.
- Add the post-link `objcopy --update-section` step that fills
  `engine_build_id = sha256(libmcts_cpp_legacy.so)` and the runtime CPU/FP
  probe that fills `cpu_features` / `fp_env` per the doctrine's Field Capture
  Protocol.
- Add backend (i)'s foreign-engine recompute surface for equity sidecars.
- Wire the live envelope into layered verification and stale-sidecar pruning
  via the Haskell-side FFI binding (under `src/MCTS/FFI/CppLegacy.hs`).

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/backend_ffi_contract.md` — fill in the C ABI shape, the
  `unsafe`/`safe` choice per symbol, the `bracket`-based RAII pattern, the
  `cpp-legacy/c-abi/` layout, and the `--rng cpp` shared-generator contract.
- `documents/engineering/determinism_contract.md` — extend with the Q6 golden
  fixture set, the legacy parity envelope (`max_plies = 10000`), and the
  `LegacyParityRolloutOverflow` failure mode.
- `documents/engineering/compiler_runtime_tuning.md` — extend with the legacy
  exemption: backend (i) builds with `-std=c++17 -O3 -fPIC -Wall` and is exempt
  from the optimisation stack.
- `documents/engineering/cli_command_surface.md` — fill in the `mcts verify
  legacy-parity` matrix and the `--backend cpp-legacy` dispatch.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md` Backend (i) row updates from `📋 Planned` to `🔄 Active`
  on Sprint 4.1 start and `✅ Done` on Sprint 4.6 closure.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [phase-3-haskell-engine.md](phase-3-haskell-engine.md)
- [phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md)
- [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
