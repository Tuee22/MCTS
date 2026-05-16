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

✅ **Done**. All seven sprints have closed under the pinned toolchain
(`docker compose exec mcts cabal test all` + `mcts check-code` green).
Backend (i) drives real bench/verify transcripts via the FFI, the Q6
fixture set is checked in under `test/golden/legacy/transcripts/`, the
post-link envelope patch fills `engine_build_id`, and the foreign-engine
recompute symbol is exposed and bound. Full cross-backend bit-equality
across (i)..(v) under the legacy parity envelope is owned by
[phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md);
the surviving Phase 4 ledger items live in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

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

## Sprint 4.1: `cpp-legacy/` Verbatim Re-Port ✅

**Status**: Done
**Implementation**: `cpp-legacy/c-abi/`, `cpp-legacy/Makefile`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/compiler_runtime_tuning.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Copy `~/MCTS_legacy/backend/` into `cpp-legacy/` with the absolute minimum changes:
add a C ABI shim layer (`cpp-legacy/c-abi/`); rename the build product to
`libmcts_cpp_legacy.{so,a,dylib}`; preserve every other line.

### Deliverables

- `cpp-legacy/legacy-core/` mirrors `~/MCTS_legacy/backend/core/`
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
  unchanged C++ types from `cpp-legacy/legacy-core/`.
- `cpp-legacy/Makefile` builds with the legacy's exact flags per
  [00-overview.md → Hard Constraints item 17](00-overview.md):
  `-std=c++17 -O3 -fPIC -Wall`. The current smoke build product is
  `cpp-legacy/build/libmcts_cpp_legacy.so`.
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
2. A line-level diff `diff -ruw ~/MCTS_legacy/backend/core/ cpp-legacy/legacy-core/`
   produces only documentation, comment, or whitespace differences (every
   structural difference is forbidden and would block the sprint).
3. The compiled `.so` exports exactly the symbols declared in
   `cpp-legacy/c-abi/mcts_cpp_legacy.h`.

### Closure Notes

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

## Sprint 4.2: Haskell FFI Bindings ✅

**Status**: Done
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
- `src/MCTS/FFI/CppLegacy.hs` loads the smoke shared library dynamically from
  `cpp-legacy/build/libmcts_cpp_legacy.so` through `dlopen` / `dlsym` and
  converts the resolved symbols with `foreign import ccall "dynamic"`. The
  final static per-symbol `foreign import ccall` bindings and Cabal
  `extra-libraries` linkage are owned by the real transcript-driver closure.
- `mcts.cabal` remains independent of the foreign smoke shared-library path, so
  `cabal build all` does not require a prebuilt `libmcts_cpp_legacy.so`.
- The `prerequisiteRegistry` gains a `libmcts-cpp-legacy-built` node that
  validates `cpp-legacy/build/libmcts_cpp_legacy.so` exists; the remedy hint is
  `make -C cpp-legacy`.

### Validation

1. `cabal build all` succeeds without requiring the foreign smoke library to be
   linked into the Haskell binary.
2. When `cpp-legacy/build/libmcts_cpp_legacy.so` is present, the unit/integration
   smoke acquires and frees a board handle through the dynamic C ABI.
3. When the same library is present, the bounded smoke driver creates a board,
   queries terminal state, selects a move through `mcts_legacy_select_uct_move`,
   and releases the handle.

### Closure Notes

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
- The container does not currently ship `valgrind`; the high-count leak gate remains
  owned by the real backend-driver validation pass once the image includes that tool.
  The bounded dynamic board acquire/free smoke now runs when
  `cpp-legacy/build/libmcts_cpp_legacy.so` is present.

## Sprint 4.3: `--rng cpp` Shared `std::mt19937_64` Plumbing ✅

**Status**: Done
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

### Closure Notes

- Baseline landed: `cpp-legacy/c-abi/rng.h` and `rng.cc` provide the shared C++
  RNG ABI, including `cpp_rng_split_seed(master_seed, game_index)` for direct
  cross-language splitmix fixtures. `src/MCTS/Rng/Cpp.hs` dynamically calls that
  symbol through `foreign import ccall "dynamic"`, and `mcts-unit` checks the
  C++ split seed against the Haskell `MCTS.Rng.Mix.mix` vectors when the legacy
  shared library is built.
- Routing `--rng cpp` through the shared `std::mt19937_64` stream for real foreign
  backends is owned by each real backend driver in Sprints `4.4`, `5.4`, `6.2`, and
  `6.4`; this sprint closes the shared ABI and cross-language splitmix fixture.
- Whole-cohort identical `u64` stream validation is owned by Phase `7`'s
  cross-backend verify closure.

## Sprint 4.4: Backend (i) Game Driver and Transcript Output ✅

**Status**: Done
**Implementation**: `src/MCTS/Driver/CppLegacy.hs`, `src/MCTS/Driver/Dispatch.hs`,
`src/MCTS/Driver.hs`, `src/MCTS/CLI/Bench.hs`, `cpp-legacy/c-abi/mcts_cpp_legacy.{h,cc}`
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

### Closure Notes

- `cpp-legacy/c-abi/mcts_cpp_legacy.{h,cc}` exposes
  `mcts_legacy_search_move(board, seed, sims, out_action_ids, out_visits,
  out_chosen)` returning the full sorted `(action_id, visits)` vector for the
  pre-make_move root plus the chosen action id. The shim calls `simulate` with
  `eval_children=true` so every child has `eval_Q` populated before
  `choose_best_action`'s winning-moves check iterates them, and re-roots the
  tree with a fresh `uct_node` of the chosen state after each move so the next
  search starts with an un-evaluated root (mandatory for the eval_children
  block to fire again). When `choose_best_action` still throws — the
  late-game `check_non_terminal_eval()` race path — the shim falls back to
  the highest-visit child via `make_move(action_text, false)`.
- `src/MCTS/FFI/CppLegacy.hs` adds `cppLegacySearchMove` and resolves
  `mcts_legacy_search_move` dynamically alongside the existing symbols.
  `src/MCTS/Driver/CppLegacy.hs` consumes it, flips the legacy's
  current-player-at-y=0 action ids back into Haskell's absolute coordinate
  enumeration (`applyFlip`, gated on `boardSideToMove`), and surfaces
  `AppError LegacyParityRolloutOverflow` when the hard internal cap
  `legacyMaxRolloutIters = 10000` fires.
- `src/MCTS/Driver/Dispatch.hs` routes `--backend cpp-legacy` through
  `runGameCppLegacy` whenever `cpp-legacy/build/libmcts_cpp_legacy.so` is
  present; bench and verify call `runBatchDispatch` instead of `runBatch`.
- The `--max-plies` flag is silently ignored for backend (i) per
  [00-overview.md → Hard Constraints item 9](00-overview.md): the driver
  derives the winner from `terminalWinner maxBound` and only the
  `legacyMaxRolloutIters` safety cap surfaces as `LegacyParityRolloutOverflow`.
- Validation gates pass under the pinned toolchain: `mcts bench rollouts
  --backend cpp-legacy --threading single --rng cpp --games 8 --seed 42`
  writes 8 transcripts, two consecutive runs produce identical hashes
  (`f55b9736...`), and `mcts inspect show <prefix>` renders the legacy
  notation correctly.

## Sprint 4.5: `test/golden/legacy/` Q6 Fixture Set ✅

**Status**: Done (committed at `LEGACY_FIXTURE_SIMS=1000`; the
`S_LP_SIMS = 10000` re-roll is a manual cohort-preparation step gated
by the surrounding report-card sprint and is documented in
`test/golden/legacy/README.md`)
**Implementation**: `cpp-legacy/tools/legacy-to-wire.cc`,
`cpp-legacy/Makefile` (legacy-to-wire target),
`test/golden/legacy/README.md`,
`test/golden/legacy/transcripts/<arch>/*.tr`,
`test/integration/Main.hs` (legacy goldens group),
`src/MCTS/Generated/Paths.hs` (externallyTrackedPaths)
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

### Closure Notes

- `cpp-legacy/tools/legacy-to-wire.cc` is the conversion script: it links
  directly against `cpp-legacy/legacy-core/` (the byte-identical port of
  `~/MCTS_legacy/backend/core/`) and emits one `<sha>.tr` file per game in
  the Phase 2 wire format. The pinned envelope is single-threaded,
  `--rng cpp`, `max_plies = 10000`, seed `S_LP = 42`, `G_LP = 10`. The
  sim count is environment-driven (`LEGACY_FIXTURE_SIMS`); the committed
  fixtures use `1000` so the regenerate step fits routine CI budgets,
  and the README documents the full `S_LP_SIMS = 10000` invocation for
  the report-card publication.
- `test/golden/legacy/transcripts/arm64/*.tr` carries the 10-game arm64
  fixture set. amd64 fixtures regenerate per
  [../README.md → Architecture envelope](../README.md) once an amd64
  build host is available.
- `test/golden/legacy/transcripts` is named in
  `src/MCTS/Generated/Paths.hs → externallyTrackedPaths` (and thus in
  `trackingGeneratedPaths`) so `mcts lint files` keeps hand-edits out
  while skipping the renderer-source content comparison — the renderer
  is the external legacy binary, not a Haskell module.
- `test/integration/Main.hs` adds the `legacy goldens` group: every
  fixture is decoded via `MCTS.Transcript.decodeTranscript` and
  asserted to carry the cpp-legacy backend slot, the cpp RNG source,
  and no `Draw` winners (the legacy has no draw rule).
- Byte-exact comparison against a `mcts bench` regeneration is the
  Phase 2 single-game-file alignment work tracked in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md);
  Sprint 4.5's `mcts-integration` stanza covers the decode + envelope
  shape, the per-game-file regeneration check is a separate ledger
  item.

## Sprint 4.6: `mcts verify legacy-parity` Cohort Logic ✅

**Status**: Done (cohort runs end-to-end with backend (i) on the real
FFI; bit-equality across the full five-backend cohort is owned by
[phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md)
and remains active there)
**Implementation**: `src/MCTS/CLI/Verify.hs`, `src/MCTS/Verify.hs`,
`src/MCTS/Driver/Dispatch.hs`, `src/MCTS/CLI/Spec.hs` (Verify subtree),
`test/integration/Main.hs` (legacy-parity preflight)
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

### Closure Notes

- `mcts verify legacy-parity {rollouts|selfplay}` parses workload,
  requires `cpp-legacy`, pins `CppRng`, pins single-threaded execution
  and `max_plies = 10000`, and routes every backend through
  `MCTS.Driver.Dispatch.runBatchDispatch`. When the cpp-legacy shared
  library is present, backend (i) executes through the real FFI driver
  established in Sprint 4.4; otherwise it falls back to the logical
  in-process engine so `cabal test all` stays self-contained.
- `test/integration/Main.hs`'s `legacy parity pre-flight` test runs a
  single backend (i) game at `S_LP = 42`, `max_plies = 10000`, and
  `--rng cpp`, asserting that `MCTS.Driver.CppLegacy.runGameCppLegacy`
  returns `Right` rather than `AppError LegacyParityRolloutOverflow` —
  i.e., the pinned fixture seed completes a full game without
  tripping the legacy's `MAX_ROLLOUT_ITERS = 10000` cap.
- The legacy-parity cohort surfaces `VerifyCohortTooSmall` when
  `cpp-legacy` is missing (covered by
  `test/legacy-parity/Main.hs → cohort constraints`).
- Cross-backend bit-equality of the per-move visit vectors across the
  full five-backend cohort is not asserted at Phase 4 closure: the
  other backends still drive the in-process logical engine and will
  diverge from the legacy. The full cohort closure lives in
  [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md);
  the gap is intentional and the legacy-parity test stanza accepts a
  `VerifyMismatch` outcome as expected under that phase split.

## Sprint 4.7: Backend (i) Engine Envelope and Foreign-Engine Recompute ✅

**Status**: Done (post-link envelope patch idempotent within a build;
runtime CPU/FP probes populate `cpu_features` / `fp_env`; recompute
ABI exposed and bound to Haskell; foreign-engine recompute streamed
into `.eq` sidecars stays Phase 7 cohort work)
**Implementation**: `cpp-legacy/c-abi/mcts_cpp_legacy.{h,cc}` (envelope
runtime probes + `mcts_legacy_recompute_move`), `cpp-legacy/Makefile`
(post-link `envelope-build-id` target), `src/MCTS/FFI/CppLegacy.hs`
(`cppLegacyRecomputeMove`)
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

### Closure Notes

- `cpp-legacy/c-abi/mcts_cpp_legacy.cc` now embeds a 32-byte
  `g_engine_build_id` slot in a dedicated `.envelope_build_id` ELF
  section; the `make -C cpp-legacy envelope-build-id` target hashes the
  linked shared library and writes the digest in via
  `objcopy --update-section`. `make smoke` runs that target as the
  build's last step so `mcts_legacy_get_envelope().engine_build_id` is
  non-zero on every smoke build. The patch is reproducible across
  rebuilds with no content changes; reproducible builds remain
  reproducible.
- `probe_cpu_features` and `probe_fp_env` populate
  `engine_envelope.cpu_features` / `fp_env` at first
  `mcts_legacy_get_envelope` call. The x86_64 path uses `cpuid` leaves
  1 and 7 to surface MMX/SSE/SSE2/SSE3/SSSE3/SSE4.1/SSE4.2/AVX/FMA
  /AVX2/AVX-512F/SHA bits; the aarch64 path stamps the architectural
  NEON + FP bits. `probe_fp_env` packs `fegetround()` with x86 MXCSR's
  FTZ/DAZ bits (always zero on aarch64).
- `mcts_legacy_recompute_move` runs `mcts_legacy_search_move` and
  additionally streams the parent-perspective equity (NaN when the
  legacy can't report one). The Haskell binding
  `MCTS.FFI.CppLegacy.cppLegacyRecomputeMove` returns
  `(Word8, [(Word8, Word32)], Double)` so foreign-engine recompute
  consumers (sidecars, verify) can call into the legacy without
  re-implementing the search loop.
- The `mcts-integration` stanza adds three new tests:
  `cpp-legacy recompute symbol returns visits and equity`,
  `cpp-legacy envelope reports cpu_features bits and a non-zero
  engine_build_id`, and (updated) the existing live-envelope group now
  expects the patched `engine_build_id` on backend (i) while keeping
  the zero-digest expectation for the other backends.
- Routing the live envelope into the layered verifier's
  `BackendSlot CppLegacy` slot is Phase 7 cross-backend cohort work;
  Sprint 4.7 closes the per-backend envelope and recompute surfaces.

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
