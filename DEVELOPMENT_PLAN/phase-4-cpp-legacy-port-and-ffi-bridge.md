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
> exposed through a stable C ABI so the Haskell CLI can generate Q6/Q7 legacy evidence
> and compare the project against the original engine.

## Phase Status

✅ **Done.** `cpp-legacy/` source, the `legacy-to-wire` evidence generator, and live
Haskell dynamic dispatch/envelope loading are present. Backend (i) remains
first-class:
it is the legacy-compatibility backend for Q6 byte-for-byte evidence and the Q7
legacy-envelope liveness/overflow gate.

## Phase Summary

Backend (i) is not a performance ceiling. It is the faithful bridge to
`MCTS_legacy`: `std::shared_ptr<uct_node>` trees, `std::mt19937_64`, the legacy
single-threaded search shape, and the legacy terminal rule are preserved. Only C ABI
shims and build plumbing are allowed around the imported source.

Q3 visit-vector identity belongs to the steelman cohort `(ii)..(v)`. Q7 is the place
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

`docker compose run --rm mcts mcts build cpp-legacy`

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

- `docker compose run --rm mcts mcts build cpp-legacy`
- `docker compose run --rm mcts mcts test mcts-integration`

### Remaining Work

None.

## Sprint 4.3: C++ RNG Verification Seeds for Equivalence ✅

**Status**: Done
**Implementation**: `cpp-legacy/c-abi/rng.{h,cc}`, `src/MCTS/Rng/Cpp.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`

### Objective

Expose the C++ `std::mt19937_64` bridge used by Q3/Q7 logical-equivalence checks.

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

Generate optional Q6 audit evidence without checking generated transcripts into git.

### Deliverables

- `mcts build legacy-fixtures --output-dir <dir>` builds and runs the legacy evidence
  generator.
- Output paths are explicit operator-provided directories, preferably outside the repo
  or under ignored local artifact roots.
- Normal validation synthesizes fixture shapes in temporary directories.

### Validation

`docker compose run --rm mcts mcts build legacy-fixtures --output-dir /tmp/mcts-legacy-fixtures --dry-run`

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/backend_ffi_contract.md` — legacy C ABI and dynamic loading.
- `documents/engineering/determinism_contract.md` — C++ RNG verification-seed equivalence
  contract.
- `documents/engineering/unit_testing_policy.md` — Q6/Q7 evidence without checked-in
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
