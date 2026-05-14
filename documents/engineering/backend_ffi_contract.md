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
// Example: C ABI opaque handle types (per backend)
typedef struct mcts_<backend>_board   mcts_<backend>_board;
typedef struct mcts_<backend>_tree    mcts_<backend>_tree;
typedef struct mcts_<backend>_rng     mcts_<backend>_rng;
```

Handles are opaque pointers; only the named operations may touch the underlying
state.

### Lifecycle

```c
// Example: C ABI lifecycle entry points
mcts_<backend>_board *mcts_<backend>_new_board(uint16_t max_plies);
void                  mcts_<backend>_free_board(mcts_<backend>_board *b);

mcts_<backend>_tree  *mcts_<backend>_new_tree(uint32_t initial_capacity);
void                  mcts_<backend>_free_tree(mcts_<backend>_tree *t);

mcts_<backend>_rng   *mcts_<backend>_new_rng(uint64_t seed, int rng_kind);
void                  mcts_<backend>_free_rng(mcts_<backend>_rng *r);
```

`rng_kind` is `0 = native` or `1 = cpp`. Backend (i) always returns the
`std::mt19937_64` generator regardless of `rng_kind`. The per-backend
native generator that each backend returns for `rng_kind = 0` is pinned
in [determinism_contract.md → Per-Backend Native RNG
Table](./determinism_contract.md); profiling-driven swaps must update
that table in the same change.

### Engine Operations

```c
// Example: C ABI engine operations
int                    mcts_<backend>_is_terminal(const mcts_<backend>_board *b);
float                  mcts_<backend>_terminal_eval(const mcts_<backend>_board *b);
void                   mcts_<backend>_apply_move(mcts_<backend>_board *b, uint8_t action_id);
uint8_t                mcts_<backend>_legal_moves(const mcts_<backend>_board *b,
                                                  uint8_t *out, size_t out_capacity);
```

### Search Operations

```c
// Example: C ABI search operations
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
// Example: C ABI instrumentation read accessor (instrumented build only)
uint32_t               mcts_<backend>_read_visits(const mcts_<backend>_tree *t,
                                                   uint32_t node_idx,
                                                   uint8_t *out_action,
                                                   uint32_t *out_visits,
                                                   uint32_t out_capacity);
```

Returns the sorted (action, visits) vector for a given node. Available only when
the backend is built in instrumented mode (see [Paired Build
Targets](#paired-build-targets) below).

### Engine Envelope Surface

Each backend exposes a read-only envelope that captures its substrate
metadata (build identity, compiler, libm, CPU features, FP environment)
so the transcript codec can stamp the envelope into every transcript
and `mcts verify` can enforce the layered cohort-invariant vs
per-backend-slot rule from
[determinism_contract.md → Engine Envelope](./determinism_contract.md).

```c
// Example: C ABI engine envelope struct and read accessor
typedef struct {
  uint16_t envelope_version;            // = 1
  uint8_t  rng_source_envelope;         // matches the transcript header's rng_source
  uint8_t  host_arch_envelope;          // matches the transcript header's host_arch
  uint8_t  shared_rng_build_id[32];     // SHA-256 of cpp_rng.so; all-zero for --rng native
  uint8_t  run_config_hash[32];         // sha256(RunConfig); filled by the codec, not by the backend
  uint8_t  engine_build_id[32];         // SHA-256 of THIS backend's loaded .so / executable
  char     engine_git_commit[40];       // project repo commit at build time, NUL-padded
  uint8_t  compiler_id;                 // 0=gcc, 1=clang, 2=rustc, 3=ghc
  uint8_t  compiler_version_len;        // ≤63
  char     compiler_version[63];        // length-prefixed ASCII; NOT NUL-terminated
  uint32_t fp_flags;                    // bitfield per envelope spec
  uint8_t  libm_id_len;                 // ≤63
  char     libm_id[63];                 // length-prefixed ASCII
  uint32_t cpu_features;                // bitfield per envelope spec
  uint8_t  fp_env;                      // rounding mode + FTZ + DAZ
} mcts_<backend>_envelope;

const mcts_<backend>_envelope *mcts_<backend>_get_envelope(void);
```

The pointer returned by `mcts_<backend>_get_envelope` references
process-static memory and is valid for the lifetime of the loaded shared
library — no allocation, no ownership transfer, no free. The C struct
layout above mirrors the wire-format envelope in
[transcript_format.md → Envelope Block](./transcript_format.md);
marshalling the struct to the wire format is a memcpy of the
non-length-prefixed fields plus length-prefixed copies of
`compiler_version[0..compiler_version_len)` and
`libm_id[0..libm_id_len)`.

#### Field Capture Protocol

- **`engine_build_id`**: filled by a build step that hashes the linked
  shared library / executable and embeds the digest as a `const char[32]`
  at link time (`objcopy --update-section .build_id=<digest>` or
  equivalent for each toolchain). The `engine_build_id` is therefore
  the SHA-256 of the same binary that exports it; computing it requires
  the build harness to link, hash, then patch the embedded constant.
- **`engine_git_commit`**: the project repo commit SHA, passed at
  compile time via `-DMCTS_GIT_COMMIT="..."` (or Cargo build env).
- **`compiler_id` / `compiler_version`**: derived at compile time from
  toolchain-provided macros (`__GNUC__` / `__GNUC_MINOR__` /
  `__GNUC_PATCHLEVEL__` for GCC; `__clang_major__` etc.; `RUSTC_VERSION`
  for Rust; `__GLASGOW_HASKELL__` for GHC).
- **`fp_flags`**: derived at compile time from explicit
  `-D` markers the build harness emits to mirror its own flag set
  (e.g., `-DMCTS_FP_FAST_MATH=0 -DMCTS_FP_FMA_ALLOWED=1`).
- **`libm_id`**: derived at compile time from a probe (the build
  harness reads `getconf GNU_LIBC_VERSION` on glibc systems, `ldd --version`
  fallback, or "rust-libm-x.y" for Rust which links its own libm).
- **`cpu_features`**: captured at runtime when the static envelope is
  first referenced, via `__builtin_cpu_supports` (GCC/Clang),
  `is_x86_feature_detected!` (Rust), or build-flag inspection (Haskell).
  The first call to `mcts_<backend>_get_envelope` triggers the probe
  and caches the result for the process lifetime.
- **`fp_env`**: captured at runtime at first `get_envelope` call via
  `fegetround` plus a probe of MXCSR / SSE control bits for FTZ/DAZ.

### Foreign-Engine Recompute

The REPL's multi-backend overlay needs to recompute the per-move equity
series for any backend on a transcript that any *other* backend
produced. Each backend exposes:

```c
// Example: foreign-engine equity-recompute stream API
// Streams (move_index, action_id, visits, equity) records for the given transcript bytes.
// Returns NULL on parse failure; on success, the caller must call `mcts_<backend>_free_eq_stream`.
mcts_<backend>_eq_stream *mcts_<backend>_recompute_equities(
    const uint8_t *transcript_bytes, size_t transcript_len);

// Pulls one per-move record. Returns 1 on success, 0 on stream end, -1 on error.
int mcts_<backend>_eq_stream_next(
    mcts_<backend>_eq_stream *s,
    uint16_t *out_move_index,
    uint16_t *out_n_alternatives,
    uint8_t  *out_action_buf,      // capacity ≥ 209
    uint32_t *out_visits_buf,      // capacity ≥ 209
    double   *out_equity_buf);     // capacity ≥ 209

void mcts_<backend>_free_eq_stream(mcts_<backend>_eq_stream *s);
```

The recompute reads the transcript's `RunConfig`, replays the search
from move 0 using the transcript's seed and budget, and emits one record
per move. Under `--rng cpp` the recompute **hard-asserts** visit-
agreement with the transcript's recorded visits at every move and
returns `-1` on disagreement (the determinism contract is binding);
under `--rng native` or for a foreign backend on a `--rng cpp`
transcript, the recompute does not abort on visit disagreement but the
disagreement contributes to the divergence-smell metric (see
[determinism_contract.md → Divergence Smell](./determinism_contract.md)).

This is the FFI the REPL's per-backend column populates from. The result
caches in `<cache-root>/transcripts/<arch>/<sha>/<backend>-<build_prefix16>.eq`
(see [transcript_format.md → Equity Sidecar Cache](./transcript_format.md))
so subsequent column opens are instant.

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
// Example: shared cpp_rng C ABI (unprefixed canonical symbols)
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

Each backend produces two build targets — **except backend (i) `cpp-legacy`,
which is exempt** and ships a single shared library
`cpp-legacy/libmcts_cpp_legacy.so`. The verbatim port has no instrumentation
to disable: the legacy C++ engine has neither a transcript writer nor a
`read_visits` symbol of its own, and the C ABI shim is too thin to host a
template flag. The Haskell-side `src/MCTS/Driver/CppLegacy.hs` carries the
transcript writer and the instrumentation surface on top of the shared library.
The exemption is end-to-end: backend (i) has neither a paired pair of
`.so` artefacts nor a paired pair of Haskell-side Cabal stanzas. The
single `libmcts_cpp_legacy.so` is what every consumer — `mcts bench`,
`mcts verify`, `mcts play`, `mcts inspect replay` — loads, and the
Haskell driver gates instrumentation behaviourally rather than by build
target. See
[../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md → Sprint 4.4](../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md)
for the exemption rationale.

For the four steelman backends — (ii) `cpp-imperative`, (iii) `cpp-functional`,
(iv) `rust`, and (v) `haskell` (the in-process Haskell backend's two stanzas):

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
-- Example: AppError carrying FFIFailure (distinct from SubprocessFailed)
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

## Domain-to-ABI Conversion Discipline

The Haskell domain types — `Board`, `Action`, `Move`, `Tree`, `RunConfig` —
**never** carry C ABI shape. They never embed `Ptr a`, `CInt`, `CDouble`,
`CSize`, `CUChar`, or any other `Foreign.C.Types` member; they never expose
`Storable` instances; and they never carry pinned `ForeignPtr` fields on
their public surface. The domain is unambiguously Haskell-shaped: an
`Action` is an `ActionId` (the bounded `Word8` newtype from
[transcript_format.md → Action Enumeration](./transcript_format.md)), a
`Move` is `(Action, Side)`, and so on.

The conversion lives at the FFI boundary module and only there:

- C struct shapes live in `src/MCTS/FFI/<Backend>.hsc` (or `.chs` if
  `c2hs` is preferred for a given backend). The `.hsc` file `#include`s
  the corresponding `<backend>/c-abi/mcts_<backend>.h` and exposes
  `Storable` instances on FFI-only newtypes (e.g. `FFIBoardPtr`,
  `FFITreeHandle`, `FFIActionByte`). These newtypes are not re-exported
  from `MCTS.FFI.<Backend>` — the module re-exports only typed Haskell
  surface (`SearchHandle`, `BoardHandle`, ...) and the `withBoard` /
  `withTree` / `withRng` bracket helpers.
- Marshalling functions are named `fromDomain` and `toDomain` (one
  matched pair per domain type per backend), live next to the `foreign
  import` declarations, and are the only functions in the module that
  touch both a domain type and an FFI type. They are total when the
  domain type's smart constructor has already enforced the input range
  (`fromDomain (a :: Action) :: FFIActionByte` is total because `Action`
  carries only `0..208 ∪ {255}`); the inverse `toDomain :: FFIActionByte
  -> Either AppError Action` re-validates on decode because the C ABI
  side may return arbitrary bytes.
- Engine modules under `src/MCTS/Engine/` and CLI modules under
  `src/MCTS/CLI/` import the typed Haskell surface only. A `Ptr CChar`
  in `src/MCTS/Engine/Search.hs` would fail review.

The benefit is concentrated, not theoretical: when a Haskell-level
refactor reshuffles `Action` or `Board`, only the four FFI boundary
modules need to update their marshalling. When a backend reshapes its
struct layout (e.g. Phase 6's Rust backend changing `repr(C)`), only
that backend's `.hsc` updates. The engine, the CLI, and the determinism
property tests stay put.

This discipline also keeps the `unsafe`/`safe` import policy easy to
audit: every `foreign import ccall` is co-located with its
`fromDomain` / `toDomain` pair, so the per-symbol classification (hot
path → `unsafe`, lifecycle → `safe`) can be eyeballed by reading one
file per backend rather than chasing call sites.

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
