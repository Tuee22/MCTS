# Backend FFI Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md, ../../DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md, ../../DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md, ../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md, ../documentation_standards.md, ./README.md, ./determinism_contract.md, ./compiler_runtime_tuning.md
**Generated sections**: none

> **Purpose**: Authoritative spec of the compact C ABI shape exposed by the live
> FFI-linked backends, the Haskell-side import policy, the `--rng cpp`
> shared-generator plumbing, and the concrete foreign build artefact contracts.

This document owns its content. There is no doctrine overlap; the FFI contract is
project-specific.

## Backends and Linkage

Five backend slots exist. Backends (i), (ii), (iii), and (iv) are live foreign
participants behind the Haskell CLI. Backend (v) is the in-process Haskell engine.
The canonical C ABI surface is:

| Backend | Linkage | FFI load name (canonical) | Build-time intermediate | Symbol prefix |
|---------|---------|---------------------------|-------------------------|----------------|
| (i) `cpp-legacy` | C ABI via Haskell FFI | `cpp-legacy/build/libmcts_cpp_legacy.so` | `cpp-legacy/build/libmcts_cpp_legacy_*` | `mcts_legacy_*` |
| (ii) `cpp-imperative` | C ABI via Haskell FFI | `cpp-imperative/build/libmcts_cpp_imperative.so` | `cpp-imperative/build/libmcts_cpp_imperative_*` | `mcts_imperative_*` |
| (iii) `cpp-functional` | C ABI via Haskell FFI | `cpp-functional/build/libmcts_cpp_functional.so` | `cpp-functional/build/libmcts_cpp_functional_*` | `mcts_functional_*` |
| (iv) `rust` | C ABI via Haskell FFI, `cdylib` | `rust/target/release/libmcts_rust.so` | `rust/target/release/libmcts_rust.pgo.so` / `rust/target/release/libmcts_rust.bolted.so` | `mcts_rust_*` |
| (v) `haskell` | Native (in-process) | (compiled into `mcts`) | n/a | (no FFI surface) |

Each foreign backend exposes a shared-library C ABI to Haskell. The FFI baseline
loads board lifecycle symbols with `dlopen` / `dlsym` and converts them to typed
function pointers via `foreign import ccall "dynamic"`; this keeps Cabal builds
independent of platform-specific `extra-libraries` paths while the backend build
harness is active. The C++ and Rust loaders share that dynamic-load policy.

The Haskell driver dynamically loads board lifecycle, visit-vector search,
recompute, read-visits, and envelope symbols through `src/MCTS/FFI/Cpp*.hs`,
`src/MCTS/FFI/Rust.hs`, `src/MCTS/Driver/Dispatch.hs`, and
`src/MCTS/Driver/ForeignSearch.hs` when the matching shared library is present.
The bounded chosen-action smoke helpers are permanent clean-clone test
scaffolding for Cabal builds without local shared libraries, not deprecated
operator surface. The operator-facing bench/play/divergence paths and
Q3/Q7/report-card surfaces use the real visit-vector and recompute ABIs for
available foreign backends. The direct live-FFI integration smoke cases currently
exercise the Rust search/recompute/envelope path; C++ live coverage is carried by
Q3 `verify`, Q7 legacy parity, and report-card measurement against the
Dockerfile-built C++ artefacts. Q3 `verify` uses live visit-vector ABI for visit-count
equality across `(ii)..(v)`, and Q7 uses live backend slots `(i)..(v)` under the
legacy envelope. Q3 uses the live cdylib when the matching
library is present and the requested batch can use the fixed 60-ply foreign
search horizon; otherwise it falls back to the in-process runner so Cabal
stanzas stay self-contained.

The **FFI load name** is the canonical install path named by
[DEVELOPMENT_PLAN/system-components.md → Artefact Locations](../../DEVELOPMENT_PLAN/system-components.md);
the Haskell FFI binds against this name. `docker/Dockerfile` invokes the
supported `mcts build` Plan/Apply leaves for Rust and the steelman C++
backends, then installs the PGO+BOLT-optimized shared library at the canonical
load name before runtime validation starts. Missing PGO profile data, missing
BOLT `.fdata`, or any attempt to install a PGO-only/unoptimized fallback under
that load name is a Dockerfile build failure. The accepted steelman artefact is
one canonical shared library per backend, trained during the Dockerfile build
on the bounded Q1/Q2-shaped profile suite defined in
[compiler_runtime_tuning.md → PGO/BOLT Training Workload Doctrine](./compiler_runtime_tuning.md#pgobolt-training-workload-doctrine);
runtime FFI loading does not switch between workload-specific libraries or trigger
PGO/BOLT retraining. Post-BOLT envelope patching uses LLVM `objcopy`, and the final
installed C++/Rust library must pass a bounded smoke run before the image can be
published. The C++ backends also retain concrete `_instrumented` Makefile outputs
for C++ investigations, but the supported Haskell FFI loader names the canonical
shared libraries above. Rust publishes one optimized `cdylib` contract, not a
parallel `_instrumented` artefact. The earlier narrow self-play training residue is
closed by Phase 8 Sprint `8.10`, and runtime FFI selection remains one canonical
library per backend rather than a profile-workload switch.

## C ABI Shape

The live C-ABI backend exposes the same operation set with its backend-specific
symbol prefix. The header lives in `<backend-dir>/c-abi/mcts_<backend>.h`.

### Opaque Handle Types

```c
// Example: C ABI opaque handle types (per backend)
typedef struct mcts_<backend>_board   mcts_<backend>_board;
```

Handles are opaque pointers; only the named operations may touch the underlying
state.

### Lifecycle

```c
// Example: compact live C ABI lifecycle entry points
mcts_<backend>_board *mcts_<backend>_new_board(void);
void                  mcts_<backend>_free_board(mcts_<backend>_board *b);
```

The live foreign search path owns one opaque board handle per replayed game. It does
not expose C-owned tree or RNG lifecycle objects: the backend search allocates its
own per-call arena internally, and the Haskell driver supplies deterministic
per-move seeds derived from either the backend-native schedule or the shared C++ RNG
bridge.

### Engine Operations

```c
// Example: compact live C ABI engine operations
int                    mcts_<backend>_is_terminal(const mcts_<backend>_board *b);
int                    mcts_<backend>_apply_action(mcts_<backend>_board *b, uint8_t action_id);
uint8_t                mcts_<backend>_select_uct_move(mcts_<backend>_board *b,
                                                      uint64_t seed,
                                                      uint32_t sim_budget);
```

`apply_action` returns `0` on success and a negative value on rejection or backend
failure. `mcts play` uses it to replay operator-entered and previously selected moves
into a fresh foreign board before calling `mcts_<backend>_search_move`, which keeps
`:undo` simple and avoids trusting a stale long-lived foreign board.

### Search Operations

```c
// Example: full search-with-visit-vector C ABI
int32_t                mcts_<backend>_search_move(mcts_<backend>_board *b,
                                                  uint64_t seed,
                                                  uint32_t sim_budget,
                                                  uint8_t *out_action_ids,
                                                  uint32_t *out_visits,
                                                  uint8_t *out_chosen);

// Example: replay/divergence recompute C ABI
int32_t                mcts_<backend>_recompute_move(mcts_<backend>_board *b,
                                                     uint64_t seed,
                                                     uint32_t sim_budget,
                                                     uint8_t *out_action_ids,
                                                     uint32_t *out_visits,
                                                     uint8_t *out_chosen,
                                                     double *out_equity);
```

The current C++ and Rust visit-vector search entry points expose `sim_budget`
but not an explicit search-horizon argument. Their compiled search horizon is
60 plies, matching the Haskell `min 60 max_plies` UCT rollout/tree cap used by
the report-card verify workload. Batch dispatch therefore uses live foreign
search for `max_plies >= 60` and falls back to the in-process runner for lower
caps until a future ABI revision adds an explicit per-run search-cap parameter.

### Optional Visit Read Surface

For `inspect replay`, `inspect divergence`, integration smoke, and optional Q6
audit comparisons, live foreign backends may provide a read-only visit cache
accessor on the board handle:

```c
// Example: optional C ABI read accessor
uint32_t               mcts_<backend>_read_visits(const mcts_<backend>_board *b,
                                                  uint8_t action_id);
```

The load-bearing visit evidence comes from `search_move` and `recompute_move`,
which return the sorted visit vector directly. `read_visits` is an auxiliary
same-board cache accessor where a backend exposes it; it is not a tree-object API.

### Engine Envelope Surface

Each backend exposes a read-only envelope that captures its substrate
metadata (build identity, compiler, libm, CPU features, FP environment)
so the transcript codec can stamp the envelope into every transcript
and the live integration verifier can enforce the layered cohort-invariant vs
per-backend-slot rule from
[determinism_contract.md → Engine Envelope](./determinism_contract.md).

```c
// Example: C ABI engine envelope struct and read accessor
typedef struct {
  uint16_t envelope_version;            // = 1
  uint8_t  rng_source_envelope;         // matches the transcript header's rng_source
  uint8_t  host_arch_envelope;          // matches the transcript header's host_arch
  uint8_t  shared_rng_build_id[32];     // shared-RNG provenance; zero in current no-shared-stream baseline
  uint8_t  cohort_config_hash[32];      // backend-independent cohort hash; filled by the codec
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

The Haskell dynamic envelope loader keeps the `dlopen` handle pinned for the
process lifetime after resolving `mcts_<backend>_get_envelope`. That is
intentional: the returned pointer names process-static storage owned by the
shared object, and verify/recompute flows can immediately reuse the same
backend for search. Closing and reopening C++ DSOs around this static storage is
not part of the contract.

Current baseline: `src/MCTS/FFI/Common.hs` dynamically loads
`mcts_<backend>_get_envelope` via `dlopen` / `dlsym`, marshals the C/Rust
process-static struct into `EngineEnvelope`, and the per-backend modules expose
`loadCppLegacyEnvelope`, `loadCppImperativeEnvelope`, `loadCppFunctionalEnvelope`,
and `loadRustEnvelope`. The integration stanza validates the live Rust envelope
path when the Rust shared artefact is present, including transcript stamping and
backend-slot stale hard-fail/`--allow-stale` warning behavior; C++ live envelope
loading is exercised through the Q3/Q7/report-card operator surfaces. The C++
backends patch
`engine_build_id` after link through their Makefile `envelope-build-id` targets;
Rust stamps `compiler_version` from
`rustc --version` through `rust/build.rs` / `MCTS_RUSTC_VERSION` and patches the
`.envelope_build_id` slot during the Dockerfile-invoked `mcts build rust` leaf.
Runtime CPU/FP/libm probes are
live for the foreign envelope surfaces; `MCTS.Driver.Dispatch` stamps FFI-produced
transcripts with the live payload, and `MCTS.Verify.Envelope.checkTranscriptEnvelopesLive`
compares cached transcript envelopes against `mcts_<backend>_get_envelope()` when
the matching cdylib is present.

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
per move. Under `--rng cpp` the recompute **hard-asserts** chosen-action and
visit agreement only when the transcript is a live same-backend originator
transcript. For in-process fallback transcripts, native-RNG transcripts, or a
foreign backend on another backend's `--rng cpp` transcript, the recompute does
not abort on disagreement; the disagreement contributes to the divergence-smell
metric (see
[determinism_contract.md → Divergence Smell](./determinism_contract.md)).

The implemented Haskell bridge uses the per-move
`mcts_<backend>_recompute_move` dynamic symbol exposed through
`MCTS.FFI.Common.withDynamicRecomputeGame` rather than a C-owned stream object.
`mcts inspect replay` uses that bridge to fill a missing originator overlay
before the TUI starts when the matching shared library is present. The result
caches in `<cache-root>/transcripts/<arch>/<sha>/<backend>-<build_label>.eq`
(see [transcript_format.md → Equity Sidecar Cache](./transcript_format.md))
so subsequent opens are instant.

## Haskell-Side Import Policy

Haskell bindings live under `src/MCTS/FFI/`:

- `src/MCTS/FFI/Common.hs` — shared dynamic board/search/recompute wrappers, the
  `bracket`-based pattern that guarantees handle release on exceptions, and
  `AppError FFIFailure` error rendering for C ABI exceptions surfaced through the
  FFI bridge (see [Error Rendering](#error-rendering) below). Distinct from
  `AppError SubprocessFailed`, which is reserved for the typed `Subprocess`
  boundary.
- `src/MCTS/FFI/CppLegacy.hs` — backend (i) bindings.
- `src/MCTS/FFI/CppImperative.hs` — backend (ii) bindings.
- `src/MCTS/FFI/CppFunctional.hs` — backend (iii) bindings.
- `src/MCTS/FFI/Rust.hs` — backend (iv) bindings.

The live baseline modules (Phase 5 Sprint 5.2 / Phase 6
Sprints 6.2 and 6.4) expose `with<Backend>Board :: (Handle -> IO a) -> IO
(Either AppError a)` routed through `MCTS.FFI.Common.liftFFI`. The handle types
are opaque `Ptr ()` newtypes. `MCTS.FFI.Common.withDynamicBoard` opens the
backend library, resolves `mcts_<backend>_new_board` /
`mcts_<backend>_free_board`, and brackets the resulting handle. Hot-path move
selection, tree, RNG, envelope, and recompute symbols still land with the real
foreign drivers.

The in-process Haskell recompute path lives at `src/MCTS/Engine/Recompute.hs`.
It reuses `MCTS.Search.UCT.uctSearchWithEquity` to replay every move of a
transcript and emits a per-move `(move_index, action, visits, equity)` record
stream. The foreign recompute path lives at `src/MCTS/Engine/ForeignRecompute.hs`
and drives `DynamicRecomputeGame` through the same transcript. Both paths
hard-assert chosen-action and visit equality under `--rng cpp` only for live
same-backend originator transcripts; foreign-view recompute otherwise emits an
`EqStream` for divergence scoring. A strict mismatch aborts with
`AppError RecomputeMismatch (Backend, GameId, MoveIndex,
recomputed_record, recorded_record)`. The sidecar
writer `MCTS.Transcript.EquitySidecar.writeEquitySidecarStream` accepts an
explicit `EqStream` so the recompute-driven stream can be persisted;
`mcts inspect show --with-equity`, `mcts inspect divergence`, and the
`mcts inspect replay` originator-cache-miss path wire this through.

### `unsafe`/`safe` Policy

Per-symbol:

- **Hot-path symbols** (`select_uct_move`, `apply_action`, `is_terminal`,
  `search_move`, and `recompute_move`) use the dynamic-call wrapper in
  `MCTS.FFI.Common`; the wrapper keeps the Haskell-side lifetime boundary explicit
  while preserving the compact board-handle ABI.
- **Lifecycle and metadata symbols** (`new_board`, `free_board`, `read_visits`,
  `get_envelope`) may block on allocator or loader activity; they remain on the
  shared FFI boundary rather than becoming persistent C-owned resource graphs.

## `--rng cpp` Plumbing

For the Q3 verification cohort, the `--rng cpp` flag selects C++-generated
verification seeds and suppresses backend-native benchmark RNGs. The
legacy RNG fixture lives in `cpp-legacy/c-abi/rng.{h,cc}` and
exposes the canonical symbols required by
[determinism_contract.md → `--rng cpp`](./determinism_contract.md#rng-cpp):

```c
// Example: legacy cpp_rng C ABI (unprefixed canonical symbols)
cpp_rng* cpp_rng_new(uint64_t seed);
uint64_t cpp_rng_next_u64(cpp_rng*);
uint64_t cpp_rng_split_seed(uint64_t master_seed, uint64_t game_index);
cpp_rng* cpp_rng_split(uint64_t master_seed, uint64_t game_index);
int      cpp_rng_fill_u64(uint64_t master_seed, uint64_t game_index,
                          uint64_t* out, uint64_t count);
void     cpp_rng_free(cpp_rng*);
```

These are the unprefixed canonical fixture symbols retained in the legacy source tree.
The Haskell `MCTS.Rng.Cpp` bridge loads `cpp_rng_fill_u64` dynamically from the
dedicated `cpp-legacy/build/libmcts_cpp_rng.so` shared object when it is present.

The C++ RNG bridge also keeps the dedicated RNG shared-library handle pinned for
the process lifetime. The bridge is used specifically by equivalence
verification to generate controlled per-move search seeds before live backend
search; it is not part of native-RNG performance measurement. Keeping the handle
open avoids cycling C++ shared-object constructors/destructors around every
verification seed stream.

**Per-game seeding.** Under `--rng cpp`, per-game streams are derived from
the same schedule as `cpp_rng_split(master_seed, game_index)` and consumed by the
Haskell driver as per-move search seeds for equivalence participants. The live path
uses `cpp_rng_fill_u64(master_seed, game_index, out, count)` so Haskell owns the
destination buffer and does not keep a heap-owned C++ RNG object across the FFI
boundary. The C fixture's `cpp_rng_split_seed(master_seed, game_index)` is kept as a
seed-level sanity check for integrations that need it.
Each game's RNG stream is independent and reproducible from
`(master_seed, game_index)` alone; workers do not carry RNG identities, so
worker-to-game assignment never affects a game's output.

**`game_index` width at the FFI boundary.** The C ABI takes `uint64_t
game_index`. The Haskell wire-format discriminator `runConfigGameIndex` is
`Word32` (matching the README's `game_id u32` wire-format pin); the Haskell
caller widens it to `Word64` with `fromIntegral` at the FFI call site. The
Haskell `mix :: Word64 -> Word64 -> Word64` mixer must agree byte-for-byte
with `cpp_rng_split_seed` for any widened pair in the fixture code.

The current per-backend ABI has no `mcts_<backend>_new_rng` /
`mcts_<backend>_free_rng` resource pair. The live search path receives effective
seeds from the Haskell driver rather than persistent RNG handles.

## Paired Build Targets

Backend (i) `cpp-legacy` is the exception: it ships a single shared library because the
verbatim legacy engine has no separate instrumentation build to disable.

Backends (ii) `cpp-imperative` and (iii) `cpp-functional` keep concrete Makefile
targets for a bench-shaped artefact and an instrumented-shaped artefact:

- `*-bench` — no instrumentation. The binary is byte-identical to one where the
  instrumentation feature does not exist. Used for benchmark runs where any
  observable overhead would corrupt the measurement.
- `*-instrumented` — transcript writer plus `read_visits` exported. Used by
  C++ replay/divergence investigations when that concrete artefact is selected.

The toggle is a template / type-level flag on the per-game driver, not a runtime
branch in the hot loop. The MCTS engine itself (search, rollout, board, RNG) is
one shared artefact between the two targets; only the small driver compiles
twice.

Because the bench binary has nothing to disable, no benchmark phase is needed to
demonstrate zero overhead — the instrumentation code literally does not exist in
it. This is the "Compile-time toggle for instrumentation" property in the
foreign-backend contract for evidence-producing artefacts.

Backend (iv) Rust currently publishes one concrete optimized FFI artefact at
`rust/target/release/libmcts_rust.so`. It exports search, recompute, read-visits,
and envelope symbols from that artefact; there is no supported Rust
`_instrumented` companion artefact in the current contract. Rust remains
first-class for Q3 cross-language verification and FFI smoke coverage, while backend
(ii) remains the load-bearing performance ceiling for Q1/Q2.

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

- Haskell owns the FFI board handle; the C++/Rust side allocates and frees the
  underlying memory. Every handle goes through the dynamic-board `bracket` pattern
  in `src/MCTS/FFI/Common.hs`; double-free and leaked handles are prevented at the
  wrapper boundary.
- `search_move` and `recompute_move` write visit vectors into caller-provided
  buffers; those buffers are allocated Haskell-side and the C++/Rust side only
  fills them. No buffer ownership crosses the FFI boundary.

## Domain-to-ABI Conversion Discipline

The Haskell domain types — `Board`, `Action`, `Move`, `Tree`, `RunConfig` —
**never** carry C ABI shape. They never embed `Ptr a`, `CInt`, `CDouble`,
`CSize`, `CUChar`, or any other `Foreign.C.Types` member; they never expose
`Storable` instances; and they never carry pinned `ForeignPtr` fields on
their public surface. The domain is unambiguously Haskell-shaped: an
`Action` is the `Pawn | WallH | WallV` algebraic domain from `MCTS.Types`,
with `actionId` / `actionFromId` as the named byte conversion boundary.

The conversion lives at the FFI boundary modules and only there:

- `src/MCTS/FFI/Common.hs` owns the shared dynamic FFI machinery:
  `dlopen`/`dlsym`, opaque board/game handles, C function-pointer wrappers,
  bracket helpers, and the `EngineEnvelope` record mirrored from the C ABI
  structs. It uses `foreign import ccall "dynamic"` because the supported
  runtime loader names canonical shared libraries produced by the Dockerfile.
- `src/MCTS/FFI/CppLegacy.hs`, `src/MCTS/FFI/CppImperative.hs`,
  `src/MCTS/FFI/CppFunctional.hs`, and `src/MCTS/FFI/Rust.hs` provide the
  typed per-backend openers and envelope loaders. They do not re-export raw
  C function pointers.
- Domain conversion is named at the call sites that cross the boundary:
  `actionId` converts Haskell `Action` values to ABI bytes, and every byte
  returned by a foreign search/recompute surface is revalidated with
  `actionFromId` before it becomes an `Action`.
- Engine modules under `src/MCTS/Engine/` and CLI modules under
  `src/MCTS/CLI/` import the typed Haskell surface only. A `Ptr CChar`
  in `src/MCTS/Engine/Search.hs` would fail review.

The benefit is concentrated, not theoretical: when a Haskell-level refactor
reshuffles `Action` or `Board`, only the four FFI boundary modules and
`MCTS.FFI.Common` need to update their marshalling. When a backend reshapes its
C ABI, the dynamic loader and the corresponding backend wrapper absorb that
change. The engine, the CLI, and the determinism property tests stay put.

This discipline also keeps the `unsafe`/`safe` import policy easy to audit:
the dynamic FFI imports and symbol wrappers are concentrated in
`MCTS.FFI.Common`, so hot-path and lifecycle classification can be reviewed in
one shared boundary instead of being spread through engine or CLI modules.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [haskell_code_guide.md](./haskell_code_guide.md) — `Subprocess` boundary
  through which the build harness invokes the C/Rust compilers
- [determinism_contract.md](./determinism_contract.md) — `--rng cpp` semantics
  and the verification cohort
- [transcript_format.md](./transcript_format.md) — wire format consumed by
  transcript and recompute evidence
- [compiler_runtime_tuning.md](./compiler_runtime_tuning.md) — per-backend flag
  sets and the PGO+BOLT build harness
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
