# Phase 4: Backend (i) C++ Legacy Port and FFI Bridge

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Land backend (i), the strictly verbatim re-port of `MCTS_legacy`,
> exposed through a stable C ABI so the Haskell CLI can generate Q6 legacy-envelope evidence
> and compare the project against the original engine.

## Phase Status

✅ **Done.** `cpp-legacy/` source, the `legacy-to-wire` evidence generator, and live
Haskell dynamic dispatch/envelope loading are present. Backend (i) remains
first-class: it is the legacy-compatibility backend for the Q6 legacy-envelope
liveness/overflow gate. Sprint `4.6` flipped the cpp-legacy build harness
from `g++` to `clang++-19` on 2026-05-30 (verbatim engine source preserved),
and Sprint `4.7` then dropped `gcc`/`g++` from the explicit `docker/Dockerfile`
apt-get list and flipped the image's `ENV CC/CXX` defaults to `clang-19` /
`clang++-19` on the same date.

## Phase Summary

Backend (i) is not a performance ceiling. It is the faithful bridge to
`MCTS_legacy`: `std::shared_ptr<uct_node>` trees, `std::mt19937_64`, the legacy
single-threaded search shape, and the legacy terminal rule are preserved. Only C ABI
shims and build plumbing are allowed around the imported source.

Q3 visit-vector identity belongs to the steelman cohort `(ii)..(v)`. Q6 is the place
where backend (i) participates with all five backend slots under the legacy envelope.

## Sprint 4.1: Verbatim Source Import ✅

**Status**: Done
**Implementation**: `cpp-legacy/legacy-core/`, `cpp-legacy/c-abi/`,
`cpp-legacy/Makefile`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/compiler_runtime_tuning.md`, `system-components.md`

### Objective

Copy `~/MCTS_legacy/backend/` into `cpp-legacy/` with only the changes required to
compile inside this repository and expose a C ABI.

### Deliverables

- `cpp-legacy/legacy-core/` mirrors the legacy backend core.
- `cpp-legacy/c-abi/mcts_cpp_legacy.h` exposes opaque board/search handles and visit
  table accessors.
- The build product is `libmcts_cpp_legacy`.
- The legacy RNG remains `std::mt19937_64`.

### Validation

`docker compose run --rm --build mcts mcts test mcts-legacy-parity`

### Remaining Work

None.

## Sprint 4.2: Haskell FFI Binding ✅

**Status**: Done
**Implementation**: `src/MCTS/FFI/CppLegacy.hs`,
`src/MCTS/Driver/Dispatch.hs`, `src/MCTS/Driver/ForeignSearch.hs`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`

### Objective

Bind the legacy C ABI through the same dynamic-load pattern used by Rust.

### Deliverables

- Dynamic loader for `libmcts_cpp_legacy`.
- Safe bracketed board/search handles.
- Conversion from C ABI visit tables into transcript records.
- Envelope loading through `mcts_legacy_get_envelope`.

### Validation

- `docker compose run --rm --build mcts mcts test mcts-legacy-parity`
- `docker compose run --rm mcts mcts test mcts-integration`

### Remaining Work

None.

## Sprint 4.3: C++ RNG Verification Seeds for Equivalence ✅

**Status**: Done
**Implementation**: `cpp-legacy/c-abi/rng.{h,cc}`, `src/MCTS/Rng/Cpp.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`

### Objective

Expose the C++ `std::mt19937_64` bridge used by Q3/Q6 logical-equivalence checks.

### Deliverables

- Haskell can request C++-generated verification seeds from the dedicated backend (i)
  RNG bridge shared object (`libmcts_cpp_rng.so` on Linux).
- The live Haskell bridge uses `cpp_rng_fill_u64` so the caller owns the destination
  buffer and no heap-owned C++ RNG object crosses the FFI lifetime boundary.
- Backends `(ii)..(v)` can consume that controlled seed stream for `--rng cpp`
  equivalence tests.
- Performance benchmarks remain on `--rng native` and use each backend's own RNG.

### Validation

- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts test mcts-cross-backend`

### Remaining Work

None.

## Sprint 4.4: Legacy Evidence Generator ✅

**Status**: Done
**Implementation**: `cpp-legacy/tools/legacy-to-wire.cc`, `cpp-legacy/Makefile`,
`src/MCTS/CLI/Build.hs`
**Docs to update**: `documents/engineering/transcript_format.md`,
`documents/engineering/unit_testing_policy.md`

### Objective

Generate optional legacy audit fixtures without checking generated transcripts into git.

### Deliverables

- `mcts build legacy-fixtures --output-dir <dir>` builds and runs the legacy audit
  fixture generator.
- Output paths are explicit operator-provided directories, preferably outside the repo
  or under ignored local artifact roots.
- Normal validation synthesizes fixture shapes in temporary directories.

### Validation

`docker compose run --rm mcts mcts build legacy-fixtures --output-dir /tmp/mcts-legacy-fixtures --dry-run`

### Remaining Work

None.

## Sprint 4.5: FFI Domain-Conversion Contract Realignment ✅

**Status**: Done
**Implementation**: `src/MCTS/Types.hs`, `src/MCTS/FFI/Common.hs`,
`src/MCTS/FFI/CppLegacy.hs`, `src/MCTS/FFI/CppImperative.hs`,
`src/MCTS/FFI/CppFunctional.hs`, `src/MCTS/FFI/Rust.hs`
**Docs to update**: `documents/engineering/backend_ffi_contract.md`,
`documents/engineering/haskell_code_guide.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Align the FFI contract with the actual Haskell-side dynamic-loader and action-domain
conversion model.

### Deliverables

- The FFI contract describes dynamic `dlopen`/`dlsym` loaders, opaque handles,
  `foreign import ccall "dynamic"` function pointers, and per-backend typed openers.
- Action-domain conversion is documented through the implemented `Action` ADT plus
  `actionId` / `actionFromId`; foreign-returned action bytes are revalidated at the
  Haskell boundary.
- Obsolete claims about `.hsc` / `.chs` generators and generic `fromDomain` /
  `toDomain` smart-constructor wrappers are removed.

### Validation

- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

Closed on 2026-05-24 after governed FFI docs described the implemented dynamic-load
and action-conversion boundary.

## Sprint 4.6: Backend (i) Compiler Pivot to clang++-19 ✅

**Status**: Done
**Implementation**: `cpp-legacy/Makefile`, `cpp-legacy/c-abi/mcts_cpp_legacy.cc`,
`src/MCTS/Prerequisite.hs`, `test/integration/Main.hs`, `test/unit/Main.hs`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`,
`../documents/engineering/compiler_runtime_tuning.md`,
`../documents/engineering/backend_ffi_contract.md`

### Objective

Pivot backend `(i)` cpp-legacy from `g++` to `clang++-19` so the verbatim
legacy engine source builds with the same front-end as backends `(ii)` and
(post-Sprint `6.11`) `(iii)`. The legacy engine has no PGO+BOLT pipeline —
its role is the Q6 legacy-envelope evidence backend, not a performance
ceiling — so this sprint is a build-harness flip only, not a steelman.

### Deliverables

- `cpp-legacy/Makefile` pins `CXX := clang++-19` (`:=`, not `?=`, so the
  pre-Sprint-`4.7` Dockerfile `ENV CXX=g++` could not silently override; a
  command-line `make CXX=...` still wins per GNU make's variable precedence
  rules).
- `cpp-legacy/c-abi/mcts_cpp_legacy.cc::g_engine_build_id` carries
  `__attribute__((used, retain, section(".envelope_build_id")))` so clang's
  -O3 cannot constant-fold the `memcpy(..., g_engine_build_id, 32)` read
  into a `memset(..., 0, 32)` and `objcopy` can still patch the section.
  Same defensive fix Sprint `5.9` applied to cpp-imperative.
- `cpp-legacy/Makefile::envelope-build-id` now discovers
  `llvm-objcopy-19` before falling back to GNU `objcopy` so the post-link
  patch keeps working under the Sprint `4.7` Dockerfile scrub.
- `src/MCTS/Prerequisite.hs::prerequisitesForBuild "cpp-legacy"` and
  `"legacy-fixtures"` swap `cxx-gpp` for `cxx-clang19`; the
  `libmcts-cpp-legacy-built` shared-lib node mirrors that change. The
  legacy engine source under `legacy-core/` is preserved verbatim per
  Phase 4 doctrine.
- `test/integration/Main.hs::expectedCompilerId` returns `1` (clang) for
  `CppLegacy`.
- `test/unit/Main.hs::exercisePrerequisiteClosure` asserts the cpp-legacy
  shared-lib prerequisite includes `cxx-clang19`.

### Validation

- `docker compose run --rm --build mcts mcts test mcts-legacy-parity`
- `docker compose run --rm mcts mcts test mcts-integration`
- `docker compose run --rm mcts mcts test all`
- Q6 legacy-envelope liveness PASS for the (i) slot; the post-pivot
  `compiler_id` envelope field reads `1` (clang).

### Remaining Work

None.

## Sprint 4.7: Dockerfile gcc/g++ Scrub ✅

**Status**: Done
**Implementation**: `docker/Dockerfile`, `src/MCTS/Prerequisite.hs`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`,
`../documents/engineering/compiler_runtime_tuning.md`

### Objective

Drop `gcc` and `g++` from the explicit `docker/Dockerfile` apt-get list now
that all three first-class C++ backends (`(i)` via Sprint `4.6`, `(ii)` via
Sprint `5.9`, `(iii)` via Sprint `6.11`) build with `clang++-19`. The
backend Makefiles each pin `CXX := clang++-19`, so the image's default
`CC`/`CXX` no longer influences any build path.

### Deliverables

- `docker/Dockerfile` apt-get list no longer names `g++` or `gcc`.
  `build-essential` is retained for `make`, `libc6-dev`, and
  `libstdc++-dev` (it still pulls g++/gcc transitively today; a future
  image revision can unpack the meta-package further if the apt-time
  savings justify it).
- `docker/Dockerfile::ENV CC=clang-19 CXX=clang++-19` so any image-default
  tool falls back to the LLVM toolchain instead of GCC.
- `src/MCTS/Prerequisite.hs` removes the `cxx-gpp` node entirely (no
  first-class build path references it after Sprint `6.11`).
- The `legacy-fixtures` build prerequisite (already swapped in Sprint
  `4.6`) continues to point at `cxx-clang19`.

### Validation

- Full image rebuild: `docker compose run --rm --build mcts mcts test all`
- `mcts test mcts-unit` exercises `exercisePrerequisiteClosure`, which no
  longer references the `cxx-gpp` node.
- Q3, Q4, Q6, Q7 invariants PASS; `normalized_divergence_score = 0.0000`.

### Remaining Work

None. Doctrine end state reached.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/backend_ffi_contract.md` — legacy C ABI and dynamic loading.
- `documents/engineering/determinism_contract.md` — C++ RNG verification-seed equivalence
  contract.
- `documents/engineering/unit_testing_policy.md` — Q6 evidence without checked-in
  generated data.

**Product docs to create/update:**

- `README.md`

**Cross-references to add:**

- Keep [system-components.md](system-components.md) and
  [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
  aligned with the live backend role.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md)
