# Backend FFI Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md, ../../DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md, ../../DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md, ../documentation_standards.md, ./README.md, ./determinism_contract.md, ./compiler_runtime_tuning.md
**Generated sections**: none

> **Purpose**: Authoritative spec of the C ABI shape exposed by the four FFI-linked
> backends, the Haskell-side import policy, the `--rng cpp` shared-generator
> plumbing, and the instrumented-vs-bench paired build-target scheme.

This document owns its content. There is no doctrine overlap; the FFI contract is
project-specific.

## Backends and Linkage

Five backends, four of which expose a C ABI to Haskell:

| Backend | Linkage | FFI load name (canonical) | Build-time intermediate | Symbol prefix |
|---------|---------|---------------------------|-------------------------|----------------|
| (i) `cpp-legacy` | C ABI via Haskell FFI | `cpp-legacy/libmcts_cpp_legacy.so` | `cpp-legacy/build/libmcts_cpp_legacy.so` | `mcts_legacy_*` |
| (ii) `cpp-imperative` | C ABI via Haskell FFI | `cpp-imperative/libmcts_cpp_imperative.so` | `cpp-imperative/build/libmcts_cpp_imperative_bench.bolted.so` | `mcts_imperative_*` |
| (iii) `cpp-functional` | C ABI via Haskell FFI | `cpp-functional/libmcts_cpp_functional.so` | `cpp-functional/build/libmcts_cpp_functional_bench.bolted.so` | `mcts_functional_*` |
| (iv) `rust` | C ABI via Haskell FFI, `cdylib` | `rust/target/release/libmcts_rust.so` | `rust/target/release-pgo/libmcts_rust.so` | `mcts_rust_*` |
| (v) `haskell` | Native (in-process) | (compiled into `mcts`) | n/a | (no FFI surface) |

Backends (i)–(iv) are loaded as shared libraries linked into the `mcts` binary at
build time. There is no `dlopen` and no runtime backend discovery; the set of live
backends is fixed at Cabal build time.

The **FFI load name** is the canonical install path matching
[../../README.md → Repository layout (target)](../../README.md); the Haskell FFI
binds against this name. The **build-time intermediate** is the artefact the
PGO+BOLT harness in Phase 5/6 produces under `<backend>/build/`; the install
step (last step of `mcts build <backend>`) renames or symlinks the `_bench`
variant of the bolted intermediate to the canonical FFI load name. The `_bench`
artefact is what the benchmark report card measures; the parallel
`_instrumented` artefact (under
`<backend>/build/libmcts_<backend>_instrumented.bolted.so`) carries the
transcript-writer and `read_visits` symbols and is loaded only by `mcts verify`,
`mcts play`, and `mcts inspect replay` — see
[Paired Build Targets](#paired-build-targets) for the toggle semantics.

## C ABI Shape

Each of the four C-ABI backends exposes the same operation set with its
backend-specific symbol prefix. The header lives in
`<backend-dir>/c-abi/mcts_<backend>.h`.

### Opaque Handle Types

```c
typedef struct mcts_<backend>_board   mcts_<backend>_board;
typedef struct mcts_<backend>_tree    mcts_<backend>_tree;
typedef struct mcts_<backend>_rng     mcts_<backend>_rng;
```

Handles are opaque pointers; only the named operations may touch the underlying
state.

### Lifecycle

```c
mcts_<backend>_board *mcts_<backend>_new_board(uint16_t max_plies);
void                  mcts_<backend>_free_board(mcts_<backend>_board *b);

mcts_<backend>_tree  *mcts_<backend>_new_tree(uint32_t initial_capacity);
void                  mcts_<backend>_free_tree(mcts_<backend>_tree *t);

mcts_<backend>_rng   *mcts_<backend>_new_rng(uint64_t seed, int rng_kind);
void                  mcts_<backend>_free_rng(mcts_<backend>_rng *r);
```

`rng_kind` is `0 = native` or `1 = cpp`. Backend (i) always returns the
`std::mt19937_64` generator regardless of `rng_kind`.

### Engine Operations

```c
int                    mcts_<backend>_is_terminal(const mcts_<backend>_board *b);
float                  mcts_<backend>_terminal_eval(const mcts_<backend>_board *b);
void                   mcts_<backend>_apply_move(mcts_<backend>_board *b, uint8_t action_id);
uint8_t                mcts_<backend>_legal_moves(const mcts_<backend>_board *b,
                                                  uint8_t *out, size_t out_capacity);
```

### Search Operations

```c
uint8_t                mcts_<backend>_select_uct_move(mcts_<backend>_tree *t,
                                                      const mcts_<backend>_board *b,
                                                      mcts_<backend>_rng *r,
                                                      uint32_t sim_budget);
void                   mcts_<backend>_rollout(mcts_<backend>_tree *t,
                                               mcts_<backend>_board *b,
                                               mcts_<backend>_rng *r);
void                   mcts_<backend>_backprop(mcts_<backend>_tree *t,
                                                uint32_t leaf_idx, float value);
void                   mcts_<backend>_reroot(mcts_<backend>_tree *t, uint8_t chosen_action);
```

### Instrumentation Surface (Instrumented Build Only)

For `inspect replay`, `mcts verify`, and the Q6 golden comparison, each backend
provides a read-only instrumentation surface:

```c
uint32_t               mcts_<backend>_read_visits(const mcts_<backend>_tree *t,
                                                   uint32_t node_idx,
                                                   uint8_t *out_action,
                                                   uint32_t *out_visits,
                                                   uint32_t out_capacity);
```

Returns the sorted (action, visits) vector for a given node. Available only when
the backend is built in instrumented mode (see [Paired Build
Targets](#paired-build-targets) below).

## Haskell-Side Import Policy

Haskell bindings live under `src/MCTS/FFI/`:

- `src/MCTS/FFI/Common.hs` — shared RAII wrappers (`withBoard`, `withTree`,
  `withRng`), the `bracket`-based pattern that guarantees handle release on
  exceptions, and `AppError FFIFailure` error rendering for C ABI exceptions
  surfaced through the FFI bridge (see [Error Rendering](#error-rendering)
  below). Distinct from `AppError SubprocessFailed`, which is reserved for the
  typed `Subprocess` boundary.
- `src/MCTS/FFI/CppLegacy.hs` — backend (i) bindings.
- `src/MCTS/FFI/CppImperative.hs` — backend (ii) bindings.
- `src/MCTS/FFI/CppFunctional.hs` — backend (iii) bindings.
- `src/MCTS/FFI/Rust.hs` — backend (iv) bindings.

### `unsafe`/`safe` Policy

Per-symbol:

- **Hot-path symbols** (`select_uct_move`, `rollout`, `backprop`, `apply_move`,
  `is_terminal`, `terminal_eval`, `legal_moves`, the `rng_*` family) use
  `foreign import ccall unsafe`. These calls do not allocate Haskell heap memory
  and do not call back into the Haskell RTS; `unsafe` is correct and avoids the
  safe-call overhead.
- **Lifecycle symbols** (`new_board`, `new_tree`, `new_rng`, `free_*`,
  `read_visits`) use `foreign import ccall safe`. These calls may block on
  allocator activity; `safe` lets the GC run on other capabilities.

## `--rng cpp` Plumbing

The `--rng cpp` flag draws every backend's random bytes from the **same** C++
`std::mt19937_64` generator. The shared generator lives in
`cpp-legacy/c-abi/rng.{h,cc}` (because the legacy itself uses it) and exposes
the four exact symbols required by
[../../README.md → Cross-backend verification → RNG FFI contract](../../README.md):

```c
cpp_rng* cpp_rng_new(uint64_t seed);
uint64_t cpp_rng_next_u64(cpp_rng*);
cpp_rng* cpp_rng_split(uint64_t master_seed, uint64_t game_index);
void     cpp_rng_free(cpp_rng*);
```

These four are the unprefixed canonical symbol set. They are linked into every
participating backend rather than re-implemented:

- Backends (ii) and (iii) link against `libmcts_cpp_legacy.so`'s exported
  `cpp_rng_*` symbols. The two C++ steelmans do not provide their own copy.
- Backend (iv) Rust reaches the generator through its own FFI binding to
  `cpp-legacy`'s shared library, calling the same `cpp_rng_*` symbols.
- Backend (v) Haskell reaches the generator directly through `MCTS.Rng.Cpp` per
  [../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md → Sprint
  4.3](../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md).

**Per-game seeding.** Under `--rng cpp`, per-game sub-seeds are derived by
calling `cpp_rng_split(master_seed, game_index)`, which uses
`splitmix64(master_seed, game_index)` internally and returns a fresh `cpp_rng*`
seeded with that value. Each game's RNG stream is independent and reproducible
from `(master_seed, game_index)` alone; workers do not carry RNG identities, so
worker-to-game assignment never affects a game's output.

**`game_index` width at the FFI boundary.** The C ABI takes `uint64_t
game_index`. The Haskell wire-format discriminator `runConfigGameIndex` is
`Word32` (matching the README's `game_id u32` wire-format pin); the Haskell
caller widens it to `Word64` with `fromIntegral` at the FFI call site. The
Haskell `mix :: Word64 -> Word64 -> Word64` mixer must agree byte-for-byte
with `cpp_rng_split`'s initial state for any widened pair; the Phase 2 Sprint
2.5 fixture asserts this once Phase 4's shim is callable.

The per-backend lifecycle symbols (`mcts_<backend>_new_rng` / `_free_rng`) from
the per-backend ABI are convenience wrappers around the `cpp_rng_*` core when
`rng_kind = 1`; they exist so per-backend driver code does not need to know
about the `cpp-legacy` shared library directly.

## Paired Build Targets

Each backend produces two build targets:

- `*-bench` — no instrumentation. The binary is byte-identical to one where the
  instrumentation feature does not exist. Used for benchmark runs where any
  observable overhead would corrupt the measurement.
- `*-instrumented` — transcript writer plus `read_visits` exported. Used by
  `mcts verify`, `mcts play`, and `mcts inspect replay`.

The toggle is a template / type-level flag on the per-game driver, not a runtime
branch in the hot loop. The MCTS engine itself (search, rollout, board, RNG) is
one shared artefact between the two targets; only the small driver compiles
twice.

Because the bench binary has nothing to disable, no benchmark phase is needed to
demonstrate zero overhead — the instrumentation code literally does not exist in
it. This is the "Compile-time toggle for instrumentation" property in the
project [../../README.md → Cross-backend verification](../../README.md).

## Error Rendering

C ABI calls that raise (e.g., a `cpp_throw` from the legacy backend on
`MAX_ROLLOUT_ITERS`, an arena allocation failure, a corrupted handle) surface
in Haskell as `AppError FFIFailure`, declared in the project's single
`AppError` ADT per
[../../DEVELOPMENT_PLAN/00-overview.md → Error Handling](../../DEVELOPMENT_PLAN/00-overview.md)
and elaborated in
[./haskell_code_guide.md → `AppError` and `renderError`](./haskell_code_guide.md).

The carried payload is:

```haskell
data AppError
  = ...
  | FFIFailure
      { ffiBackend :: Backend  -- which backend's C ABI raised
      , ffiSymbol  :: Text     -- the C ABI symbol that raised (e.g. "mcts_legacy_rollout")
      , ffiMessage :: Text     -- decoded error message from the C ABI side
      }
  | ...
```

`FFIFailure` is **semantically distinct** from `SubprocessFailed`:

- `SubprocessFailed` is raised by the typed `Subprocess` boundary
  (`runStreaming` / `capture` non-zero exit) when an external child process
  fails — the PGO+BOLT build harness, `cabal test`, `llvm-bolt`, etc.
- `FFIFailure` is raised by the in-process FFI bridge when a C ABI symbol
  signals an exceptional condition through the shared-library boundary.

Keeping them distinct lets `renderError` print useful diagnostics
("`mcts_legacy_rollout` raised: rollout exceeded MAX_ROLLOUT_ITERS = 10000")
without conflating subprocess and in-process failure modes. The `Subprocess`
hlint forbiddance from
[./code_quality.md → HLint Rules](./code_quality.md) does **not** apply to
FFI calls — those go through `foreign import ccall` and are governed by the
per-symbol `unsafe`/`safe` policy above, not the `Subprocess` interpreter.

## Memory Ownership

- Haskell owns the FFI handle; the C++/Rust side allocates and frees the
  underlying memory. Every handle goes through the `withBoard` / `withTree` /
  `withRng` `bracket` pattern in `src/MCTS/FFI/Common.hs`; double-free and leaked
  handles are statically prevented.
- `legal_moves` writes into a caller-provided buffer; the buffer is allocated
  Haskell-side and the C++/Rust side only fills it. No buffer ownership crosses
  the FFI boundary.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [haskell_code_guide.md](./haskell_code_guide.md) — `Subprocess` boundary
  through which the build harness invokes the C/Rust compilers
- [determinism_contract.md](./determinism_contract.md) — `--rng cpp` semantics
  and the shared `std::mt19937_64` generator
- [transcript_format.md](./transcript_format.md) — wire format the instrumented
  build emits
- [compiler_runtime_tuning.md](./compiler_runtime_tuning.md) — per-backend flag
  sets and the PGO+BOLT build harness
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
