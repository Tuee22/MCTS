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
> legacy C++ RNG split-seed fixture for `--rng cpp` validation, and the historical
> Q6 evidence path that Sprint `8.8` supersedes with generated temp-dir coverage.

## Phase Status

✅ **Done (retired source/evidence surface)**. Phase `4` closed the original
backend (i) port, C ABI, legacy RNG fixture, Q6 evidence generator, and
pre-retirement legacy-envelope verification surface. Sprint `8.4` then retired
backend (i) from live CLI/build/verify/FFI dispatch, removed the Haskell
`CppLegacy` FFI/driver modules, and preserved the wire tag for archived
transcripts. The current worktree keeps `cpp-legacy/` as a retired reference plus
the optional `mcts build legacy-fixtures` evidence generator; normal validation
does not require a live `cpp-legacy` shared library or checked-in legacy
transcripts. The retirement history and any surviving cleanup facts live in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Phase Summary

Phase `4` retains the verbatim `~/MCTS_legacy/backend/` port under `cpp-legacy/`
with only the C ABI and optional fixture-generation shim needed for historical
evidence. The legacy keeps its `std::shared_ptr<uct_node>` trees,
`std::mt19937_64` RNG, single-threaded design, and no-draw-rule terminal
semantics (`is_terminal()` ↔ `hero_wins() || villain_wins()`). Backend (i) is a
retired regression-sanity reference, not a performance ceiling and not a live
operator-selectable backend. The current live `verify` cohort excludes it through
the Phase 7 `VerifyBackend` parser surface; Q6 and Q7 are historical or optional
external evidence rather than clean-clone validation inputs.

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
  `Board`, `Tree`, `Rng`; `mcts_legacy_new_board`, `mcts_legacy_apply_action`,
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
- At the pre-retirement closure point, `src/MCTS/CLI/Command.hs` gained the `BuildCppLegacy` constructor on the
  `BuildCommand` family per
  [phase-1-haskell-cli-surface.md → Sprint 1.2 ownership note](phase-1-haskell-cli-surface.md).
  The matching `mcts build cpp-legacy` Plan/Apply ran `make -C cpp-legacy`
  (the legacy-flags subset only — no PGO/BOLT/mimalloc) as a typed
  `[Subprocess]` sequence; Sprint `8.4` later retired that live build leaf and
  left `mcts build legacy-fixtures` as the supported optional evidence path.

### Validation

1. `docker compose run --rm mcts mcts build cpp-legacy` produces
   `cpp-legacy/build/libmcts_cpp_legacy.so` through the internal
   `make -C cpp-legacy` typed subprocess under the pinned toolchain.
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
- The `mcts build cpp-legacy` plan delegates to the backend Makefile to build
  `cpp-legacy/build/libmcts_cpp_legacy.so` with the legacy
  `-std=c++17 -O3 -fPIC -Wall` shape plus a narrow `-Wno-pessimizing-move`
  compatibility suppression for the verbatim legacy return statement; the smoke
  target is warning-clean on the container compiler.
- Keep all future non-FFI changes out of the port and record any unavoidable
  compatibility residue in `legacy-tracking-for-deletion.md`.

## Sprint 4.2: Haskell FFI Bindings ✅

**Status**: Done
**Implementation**: `cpp-legacy/c-abi/mcts_cpp_legacy.{h,cc}`,
`src/MCTS/FFI/Common.hs`, `legacy-tracking-for-deletion.md` (Sprint 8.4
retirement record for the removed `src/MCTS/FFI/CppLegacy.hs` live binding)
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
- At the pre-retirement closure point, `src/MCTS/FFI/CppLegacy.hs` loaded the smoke shared library dynamically from
  `cpp-legacy/build/libmcts_cpp_legacy.so` through `dlopen` / `dlsym` and
  converts the resolved symbols with `foreign import ccall "dynamic"`. The
  final static per-symbol `foreign import ccall` bindings and Cabal
  `extra-libraries` linkage are owned by the real transcript-driver closure.
- `mcts.cabal` remains independent of the foreign smoke shared-library path, so
  the `cabal build all` step inside `docker compose run --rm mcts mcts
  check-code` does not require a prebuilt `libmcts_cpp_legacy.so`.
- The pre-retirement `prerequisiteRegistry` gained a `libmcts-cpp-legacy-built`
  node. Sprint `8.4` removed the live prerequisite when backend (i) retired.

### Validation

1. `docker compose run --rm mcts mcts check-code` reaches its internal
   `cabal build all` step without requiring the foreign smoke library to be
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
  At the pre-retirement closure point, `src/MCTS/FFI/CppLegacy.hs`,
  `src/MCTS/FFI/CppImperative.hs`, `src/MCTS/FFI/CppFunctional.hs`, and
  `src/MCTS/FFI/Rust.hs` declared per-backend board handle wrappers. The live
  worktree now keeps `src/MCTS/FFI/Rust.hs` plus the shared dynamic loader while
  the C++ Haskell bindings are recorded as retired. The stand-in unit handles have been
  replaced by opaque `Ptr ()` newtypes allocated and freed through
  `withDynamicBoard`, which uses `dlopen` / `dlsym` plus
  `foreign import ccall "dynamic"` function pointers for the backend
  `mcts_<backend>_new_board` / `mcts_<backend>_free_board` symbols. This keeps
  Cabal builds independent of platform-specific shared-library paths while still
  exercising the real C ABI. The pre-retirement prerequisite registry included
  `libmcts-cpp-legacy-built` with a `cxx` dependency; Sprint `8.4` removed it
  from live prerequisite closure.
- The container does not currently ship `valgrind`; the high-count leak gate remains
  owned by the real backend-driver validation pass once the image includes that tool.
  The bounded dynamic board acquire/free smoke now runs when
  `cpp-legacy/build/libmcts_cpp_legacy.so` is present.

## Sprint 4.3: `--rng cpp` C++ Split-Seed Fixture ✅

**Status**: Done
**Implementation**: `cpp-legacy/c-abi/rng.h`, `cpp-legacy/c-abi/rng.cc`,
`src/MCTS/Rng/Mix.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/backend_ffi_contract.md`

### Objective

Expose the legacy C++ seed splitter to Haskell over the FFI so the no-backend-salt
`--rng cpp` schedule can be validated against the C++ side. The current live
verify path does not route every backend through a shared `std::mt19937_64` byte
stream.

### Deliverables

- `cpp-legacy/c-abi/rng.h` declares the C ABI for the legacy RNG fixture per
  [../README.md → Cross-backend verification → RNG FFI contract](../README.md).
  The exported symbols are:
  ```c
  cpp_rng* cpp_rng_new(uint64_t seed);
  uint64_t cpp_rng_next_u64(cpp_rng*);
  uint64_t cpp_rng_split_seed(uint64_t master_seed, uint64_t game_index);
  cpp_rng* cpp_rng_split(uint64_t master_seed, uint64_t game_index);
  void     cpp_rng_free(cpp_rng*);
  ```
  `cpp_rng_split` returns a fresh `cpp_rng*` whose internal state is seeded from
  `splitmix64(master_seed, game_index)` — this is how per-game sub-seeds are
  derived without mutating the parent generator state. Workers therefore do not
  carry RNG identities; the seed lives with the game, and worker-to-game
  assignment never changes a game's output.
- `cpp-legacy/c-abi/rng.cc` wraps the standard library generator and exposes
  `cpp_rng_split_seed` for direct cross-language seed checks.
- At the pre-retirement closure point, `src/MCTS/Rng/Cpp.hs` exposed the
  Haskell-side `cppSplitSeed` helper, dynamically loaded
  `cpp_rng_split_seed`, and let `mcts-unit` compare the C++ fixture against
  `MCTS.Rng.Mix.mix`. Sprint `8.4` removed that live Haskell loader with the
  rest of backend (i)'s live FFI surface; the current unit suite pins the
  Haskell splitmix vectors directly.
- The `--rng cpp` flag is plumbed through `BenchOptions` (Phase 3 Sprint 3.5
  reserved the field). The `mcts bench rollouts/selfplay --backend cpp-legacy
  --rng cpp` invocation is end-to-end at Sprint 4.4 closure.

### Validation

1. A unit test pins `cpp_rng_split_seed(master_seed, game_index)` against the
   Haskell `MCTS.Rng.Mix.mix` vectors when the legacy shared library is built.
2. Same-backend determinism: two runs of the Compose invocation
   `docker compose run --rm mcts mcts bench rollouts --backend cpp-legacy --rng cpp --games 4 --seed 42`
   produce identical determinism payloads.
3. At the pre-retirement closure point, the `prerequisiteRegistry`
   `libmcts-cpp-legacy-built` node passed its check.

### Closure Notes

- Baseline landed: `cpp-legacy/c-abi/rng.h` and `rng.cc` provide the legacy C++
  RNG fixture ABI, including `cpp_rng_split_seed(master_seed, game_index)` for direct
  cross-language splitmix fixtures. During backend (i)'s live interval,
  `src/MCTS/Rng/Cpp.hs` dynamically called that symbol through
  `foreign import ccall "dynamic"` and `mcts-unit` checked the C++ split seed
  against the Haskell `MCTS.Rng.Mix.mix` vectors when the legacy shared library
  was built. The current clean-clone suite keeps the Haskell splitmix vector
  checks without requiring the retired legacy shared library.
- The current real foreign backend drivers use the cross-language splitmix
  schedule validated by `cpp_rng_split_seed`; `--rng cpp` keeps
  `MCTS.Rng.Mix.backendNativeSalt` at zero instead of routing a live shared
  `std::mt19937_64` byte stream through every backend.
- Whole-cohort identical visit-count validation is owned by Phase `7`'s
  cross-backend verify closure.

## Sprint 4.4: Backend (i) Game Driver and Transcript Output ✅

**Status**: Done
**Implementation**: `cpp-legacy/c-abi/mcts_cpp_legacy.{h,cc}`,
`cpp-legacy/tools/legacy-to-wire.cc`, `src/MCTS/Driver/Dispatch.hs`,
`legacy-tracking-for-deletion.md` (Sprint 8.4 retirement record for the removed
`src/MCTS/Driver/CppLegacy.hs` live driver)
**Docs to update**: `documents/engineering/backend_ffi_contract.md`

### Objective

Wire backend (i) into the bench / verify driver so `mcts bench rollouts --backend
cpp-legacy` and the eventual `mcts verify legacy-parity --backend cpp-legacy,...`
run end-to-end, write transcripts in the Phase 2 wire format, and respect the
backend (i)'s no-draw-rule terminal semantics.

### Deliverables

- At the pre-retirement closure point, `src/MCTS/Driver/CppLegacy.hs` exposed
  backend (i) through the FFI-backed search driver, mirroring the Phase 3
  Haskell driver but driving the legacy tree. Sprint `8.4` later removed that
  live Haskell driver.
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
- `src/MCTS/CLI/Bench.hs` (Phase 3 Sprint 3.5) gained `--backend cpp-legacy`
  dispatch for the pre-retirement backend (i) surface; Sprint `8.4` removed that
  operator selection.

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
- At the pre-retirement closure point, `src/MCTS/FFI/CppLegacy.hs` added `cppLegacySearchMove` and resolved
  `mcts_legacy_search_move` dynamically alongside the existing symbols.
  `src/MCTS/Driver/CppLegacy.hs` consumes it, flips the legacy's
  current-player-at-y=0 action ids back into Haskell's absolute coordinate
  enumeration (`applyFlip`, gated on `boardSideToMove`), and surfaces
  `AppError LegacyParityRolloutOverflow` when the hard internal cap
  `legacyMaxRolloutIters = 10000` fires.
- `src/MCTS/Driver/Dispatch.hs` routed `--backend cpp-legacy` through
  `runGameCppLegacy` during the live backend (i) interval. It now rejects
  `CppLegacy` in live dispatch and points operators at explicit external
  evidence.
- The `--max-plies` flag is silently ignored for backend (i) per
  [00-overview.md → Hard Constraints item 9](00-overview.md): the driver
  derives the winner from `terminalWinner maxBound` and only the
  `legacyMaxRolloutIters` safety cap surfaces as `LegacyParityRolloutOverflow`.
- Validation gates pass under the pinned toolchain: `mcts bench rollouts
  --backend cpp-legacy --threading single --rng cpp --games 8 --seed 42`
  writes 8 transcripts, two consecutive runs produce identical hashes
  (`f55b9736...`), and `mcts inspect show <prefix>` renders the legacy
  notation correctly.

## Sprint 4.5: Historical Q6 Evidence Generator ✅

**Status**: Done for the historical evidence generator; superseded by Sprint
`8.8` for normal validation because generated transcript data must not be
required in git.
**Implementation**: `cpp-legacy/tools/legacy-to-wire.cc`,
`cpp-legacy/Makefile` (legacy-to-wire target),
`test/integration/Main.hs` (legacy-envelope checks),
`src/MCTS/Generated/Paths.hs` (generated-path cleanup in Sprint `8.8`)
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/unit_testing_policy.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Provide an auditable way to convert `MCTS_legacy`-produced games into the Phase 2
wire format for Q6 investigation. Sprint `8.8` changes the normal
`mcts-integration` path so it generates or synthesizes legacy-envelope data in a
temporary root instead of reading checked-in transcripts.

### Deliverables

- `cpp-legacy/tools/legacy-to-wire.cc` documents and implements the conversion
  path from out-of-band `MCTS_legacy` games to the Phase 2 wire format. The tool
  stamps the canonical `host_arch u8` byte for the host it ran on (see
  [../documents/engineering/transcript_format.md → Header](../documents/engineering/transcript_format.md)).
- The historical evidence envelope covers benchmark (b) self-play at the
  report-card legacy-parity knobs: seed `$S_LP = 42`, `$G_LP = 10` games,
  `$S_LP_SIMS = 10_000` sims/move, `--max-plies 10000`.
- The generated evidence is per-architecture and per game when produced, but it
  belongs in an explicit external or ignored artifact root, not in the repository.
- `test/integration/Main.hs` must assert the legacy-envelope semantics that
  matter for compatibility from temporary generated data: cpp-legacy backend
  slot, self-play workload, single-threaded cpp RNG source, seed `42`, `10000`
  sims, `max_plies = 10000`, one game per file, and no-draw semantics.

### Validation

1. `docker compose run --rm mcts mcts build legacy-fixtures --output-dir
   <external-or-ignored-root>/legacy/transcripts --seed 42 --games 10 --sims
   10000 --dry-run` renders the supported Plan/Apply evidence-generation plan.
2. Normal `mcts-integration` validates the same legacy-envelope semantics from
   temporary generated data and does not require pre-existing transcripts.
3. Generated transcript roots are ignored/local and are not named as repository
   validation inputs in generated-path tracking.

### Closure Notes

- `cpp-legacy/tools/legacy-to-wire.cc` is the conversion script: it links
  directly against `cpp-legacy/legacy-core/` (the byte-identical port of
  `~/MCTS_legacy/backend/core/`) and emits one `<sha>.tr` file per game in
  the Phase 2 wire format. The pinned envelope is single-threaded,
  `--rng cpp`, `max_plies = 10000`, seed `S_LP = 42`, `G_LP = 10`, and
  `S_LP_SIMS = 10000`. Regeneration enters through `docker compose run --rm
  mcts mcts build legacy-fixtures --output-dir
  <external-or-ignored-root>/legacy/transcripts --seed 42 --games 10 --sims
  10000` rather than direct tool execution.
- Historical 2026-05-18 evidence was generated after comparing the imported core
  against `/home/matt/MCTS_legacy/backend/core/` with whitespace ignored. Sprint
  `8.8` removes the old committed-transcript assumption from normal validation.
- `test/integration/Main.hs` keeps the `MCTS.Transcript.decodeTranscript`
  coverage and legacy-envelope assertions, but the inputs are generated inside
  the test process or read only by an explicit optional artifact suite.

## Sprint 4.6: `mcts verify legacy-parity` Cohort Logic ✅

**Status**: Done (cohort runs end-to-end with backend (i) on the real
FFI; Q7 five-backend legacy-envelope liveness/overflow coverage is owned by
[phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md)
and is closed there)
**Implementation**: `src/MCTS/CLI/Verify.hs`, `src/MCTS/Verify.hs`,
`src/MCTS/Driver/Dispatch.hs`, `src/MCTS/CLI/Spec.hs` (Verify subtree),
`test/integration/Main.hs` (legacy-parity preflight)
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/cli_command_surface.md`

### Objective

Land the `mcts verify legacy-parity` subcommand that runs all five backends under
the legacy parity envelope (`max_plies = 10000`, fixture seed pinned, `--rng cpp`,
`--threading single`) and checks backend (i) liveness/overflow inside that envelope.

### Deliverables

- At the pre-retirement closure point, `src/MCTS/CLI/Spec.hs` added the
  `Verify VerifyCommand` subtree carrying
  `VerifyLegacyParity LegacyParityOptions` per the project
  [README → CLI command topology](../README.md). That surface parsed a
  `[LegacyParityBackend]` cohort and rejected cohorts without `LpCppLegacy` at
  the parser boundary with `AppError VerifyCohortTooSmall`. Sprint `8.4`
  removed the live parser surface.
- The historical `LegacyParityOptions` pinned `RngSource = CppRng`,
  `Threading = SingleThreaded`, and `max_plies = MAX_ROLLOUT_ITERS = 10000`
  non-user-overridable. The `lpSeed :: Word64` field defaulted to the
  report-card knob `S_LP = 42`. The workload was one of `LpRollouts` or
  `LpSelfplay`.
- `src/MCTS/CLI/Verify.hs` runs the cohort: for each requested backend, run
  `mcts bench {rollouts,selfplay}`-equivalent with the pinned envelope, collect
  the transcripts, and verify the live envelopes. If backend (i) throws or reaches
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
   --sims 10` runs to completion. Full five-backend Q7 liveness/overflow
   coverage waits until all five backends are live (Phase 7 closure); at Phase 4
   close, the command runs and backend (i)'s overflow guard is wired.
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
  in-process engine so `docker compose run --rm mcts mcts test all`
  stays self-contained.
- `test/integration/Main.hs`'s `legacy parity pre-flight` test runs a
  single backend (i) game at `S_LP = 42`, `max_plies = 10000`, and
  `--rng cpp`, asserting that `MCTS.Driver.CppLegacy.runGameCppLegacy`
  returns `Right` rather than `AppError LegacyParityRolloutOverflow` —
  i.e., the pinned fixture seed completes a full game without
  tripping the legacy's `MAX_ROLLOUT_ITERS = 10000` cap.
- The legacy-parity cohort surfaces `VerifyCohortTooSmall` when
  `cpp-legacy` is missing (covered by
  `test/legacy-parity/Main.hs → cohort constraints`).
- Full five-backend Q7 liveness/overflow coverage is not asserted at Phase 4
  closure because the other backends are not live yet. The full cohort closure
  lives in
  [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md);
  Sprint 7.2 closes it without requiring backend (i)'s legacy search tree to
  match the steelman visit vectors.

## Sprint 4.7: Backend (i) Engine Envelope and Foreign-Engine Recompute ✅

**Status**: Done (post-link envelope patch idempotent within a build;
runtime CPU/FP probes populate `cpu_features` / `fp_env`; recompute
ABI exposed pre-retirement; Sprint 8.4 later removed the live Haskell binding)
**Implementation**: `cpp-legacy/c-abi/mcts_cpp_legacy.{h,cc}` (envelope
runtime probes + `mcts_legacy_recompute_move`), `cpp-legacy/Makefile`
(post-link `envelope-build-id` target), `legacy-tracking-for-deletion.md`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/backend_ffi_contract.md`,
`documents/engineering/transcript_format.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Backend (i) populates its engine envelope from build-time constants
and exposes a foreign-engine recompute entry point. The current envelope
baseline leaves `shared_rng_build_id` zero for normal runs; backend (i)'s
post-link SHA-256 is stamped as `engine_build_id`, and legacy-parity fixture
provenance can compare against that build identity when needed. See
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
  the transcript was written with `rng_source = cpp`, the recompute uses the
  no-backend-salt schedule and hard-asserts visit-agreement.
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
  expects patched, non-zero `engine_build_id` values for
  `cpp-legacy`, `cpp-imperative`, and `cpp-functional`; Rust is accepted
  in either smoke-build zero-digest form or post-`mcts build rust`
  patched form. Phase 7 later extends that group to prove live transcript
  stamping and stale compiler-version hard-fail/`--allow-stale` behavior
  for every present foreign cdylib.
- Phase 7 Sprint 7.5 routes the live envelope into the layered verifier's
  `BackendSlot CppLegacy` slot when the cdylib is present; Sprint 4.7 closes
  the per-backend envelope and recompute surfaces.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/backend_ffi_contract.md` — fill in the C ABI shape, the
  `unsafe`/`safe` choice per symbol, the `bracket`-based RAII pattern, the
  `cpp-legacy/c-abi/` layout, and the `--rng cpp` shared-generator contract.
- `documents/engineering/determinism_contract.md` — extend with the Q6
  legacy-envelope semantics, the legacy parity envelope (`max_plies = 10000`),
  and the
  `LegacyParityRolloutOverflow` failure mode.
- `documents/engineering/compiler_runtime_tuning.md` — extend with the legacy
  exemption: backend (i) builds with `-std=c++17 -O3 -fPIC -Wall` and is exempt
  from the optimisation stack.
- `documents/engineering/cli_command_surface.md` — fill in the `mcts verify
  legacy-parity` matrix and the `--backend cpp-legacy` dispatch.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md` Backend (i) row reflects the current retired reference
  state and points to the Phase 8 retirement record.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [phase-3-haskell-engine.md](phase-3-haskell-engine.md)
- [phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md)
- [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
