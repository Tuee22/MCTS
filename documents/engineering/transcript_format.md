# Transcript Format

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-2-transcript-codec-and-determinism.md, ../../DEVELOPMENT_PLAN/phase-3-haskell-engine.md, ../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md, ../documentation_standards.md, ./README.md, ./determinism_contract.md
**Generated sections**: none

> **Purpose**: Authoritative spec of the MCTS transcript wire format, the single-byte
> action enumeration, the content-addressed cache layout, and the git-style
> hash-prefix lookup.

This document owns its content. There is no doctrine overlap; the wire format is
project-specific.

## Design Principles

- **Little-endian binary everywhere.** No padding. No schema-library dependency:
  protobuf, flatbuffers, Cap'n Proto, and CBOR all have library-version-dependent
  encoding latitude that would have to be imported into the determinism contract.
- **Dense, fully owned.** Per-move records are sparse `(action_id, visits)` pairs
  sorted ascending by action ID; equity is excluded because it is a derived float
  whose accumulation order is summation-order-sensitive across backends.
- **Memory-resident trees only.** Nothing about the in-memory tree is serialised;
  only the per-move action choices and visit-count vectors. Tree state at any
  given moment is reproducible by replaying the seed and move sequence.
- **Content-addressed per backend/game.** Transcripts live in
  `<cache-root>/transcripts/<arch>/<sha>.tr` (arch-partitioned per the
  architecture envelope) where `<sha>` is `sha256(run_config)`. The
  `run_config` includes the backend and `game_index`, so a batch of N games
  writes N per-game transcript files per backend. `mcts play`-recorded
  transcripts use `sha256(run_config || move_history)` because human choices are
  part of the provenance; see [Content Addressing](#content-addressing).
- **Runtime artifact, not repository fixture.** Transcripts are cache or audit
  artifacts. Normal tests generate transcript bytes in memory or temporary
  roots; no pre-existing transcript directory is a clean-clone validation input.

## Wire Format

This section is the authoritative byte-level transcript specification.
Little-endian everywhere, no padding.

### Header

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 4 | magic | `MCTR` ASCII bytes (`0x4D 0x43 0x54 0x52`) |
| 4 | 2 | version | Wire-format version (currently `1`) |
| 6 | 1 | backend | `0 = cpp-legacy`, `1 = cpp-imperative`, `2 = cpp-functional`, `3 = rust`, `4 = haskell` |
| 7 | 1 | threading | `0 = single`, `1 = multi` |
| 8 | 2 | workers | `u16`; meaningful only when `threading = multi` |
| 10 | 1 | rng_source | `0 = native`, `1 = cpp` |
| 11 | 1 | host_arch | `0 = amd64` (Linux x86-64), `1 = arm64` (Linux aarch64). Identifies the architecture the transcript was written on; cross-arch `verify` rejects mismatches with `AppError ArchEnvelopeMismatch`. See [determinism_contract.md → Architecture Envelope](./determinism_contract.md). |
| 12 | 8 | c_param | UCT exploration constant stored as IEEE-754 `double` bit-cast to `u64` little-endian. Both supported arches (amd64, arm64) are IEEE-754 so the bit-cast is portable in shape; same-arch replay is bit-identical, cross-arch replay differs at the ULP level. |
| 20 | 4 | flags | Reserved for future format extensions. **All bits must be zero in v1**; non-zero bits cause `decode` to reject the file with `AppError TranscriptFormatUnsupported`. |
| 24 | 8 | master_seed | `u64` |
| 32 | 4 | initial_sims | `u32`; together with `per_move_sims` encodes `SimBudget` (see below) |
| 36 | 4 | per_move_sims | `u32`; together with `initial_sims` encodes `SimBudget` |
| 40 | 2 | max_plies | `u16`; default `200`, pinned to `10000` under the legacy-parity envelope |
| 42 | 2 | workload | `0 = rollouts`, `1 = selfplay`; other values are rejected in v1 |
| 44 | 4 | envelope_offset | `u32`; byte offset from file start where the [Envelope Block](#envelope-block) begins. Version-1 readers require this to be exactly `48` and reject any other value with `AppError TranscriptFormatUnsupported`. |
| 48 | — | — | Header end; envelope block begins at `envelope_offset`, per-game body begins immediately after the envelope block |

**`SimBudget` encoding.** For `FixedSims N`, both `initial_sims` and
`per_move_sims` are set to `N` (the on-wire discriminator for `FixedSims` is
`initial_sims == per_move_sims`). For `RampedSims N0 N1`, `initial_sims = N0` and
`per_move_sims = N1`.

### Envelope Block

The envelope block records every substrate-affecting field at the time the
transcript was written — the build identity of the backend that wrote the file,
the compiler and libm versions, the FP-relevant compiler flags, the CPU features
the binary actually dispatched, and the FP environment at engine-run time.
It is part of the transcript file but excluded from the cross-backend
determinism payload: backend-specific cache filenames preserve provenance, while
`mcts verify` compares the decoded common payload. See
[determinism_contract.md → Engine Envelope](./determinism_contract.md) for the
layered cohort-invariant vs per-backend-slot rule and how `mcts verify` enforces
it.

The block lives at `envelope_offset` (byte 48 in version-1 transcripts):

| Offset (within block) | Size | Field | Notes |
|-----------------------|------|-------|-------|
| 0 | 2 | envelope_version | `u16`; currently `1`. Version-1 readers reject unsupported envelope versions with `AppError TranscriptFormatUnsupported`. New v1 fields are appended additively; readers tolerate trailing bytes they do not recognise after the known v1 payload. |
| 2 | 4 | envelope_byte_length | `u32`; total length of the envelope block in bytes, counting from `envelope_version` through the last byte of the block. |
| 6 | 1 | rng_source_envelope | `u8`; matches the header's `rng_source`. Recorded inside the envelope so the cohort-uniformity check is uniform across fields. |
| 7 | 1 | host_arch_envelope | `u8`; matches the header's `host_arch`. Same rationale as `rng_source_envelope`. |
| 8 | 32 | shared_rng_build_id | Provenance for a shared verification-RNG source when one is recorded. Deterministic logical fallback transcripts record all-zero; live equivalence evidence may pin this to the RNG provider build identity. |
| 40 | 32 | cohort_config_hash | SHA-256 of the backend-independent cohort config: the common verify inputs excluding `backend`, the engine envelope, path, and cache metadata. Distinct from the backend-specific cache filename hash. |
| 72 | 32 | engine_build_id | SHA-256 of the loaded backend shared library / executable that wrote this transcript. |
| 104 | 40 | engine_git_commit | ASCII; project repo commit SHA at build time. Padded with NULs if shorter than 40 bytes. Informational; does not gate `verify`. |
| 144 | 1 | compiler_id | `u8`; `0 = gcc`, `1 = clang`, `2 = rustc`, `3 = ghc`. |
| 145 | 1 | compiler_version_len | `u8`; number of valid bytes in the following fixed-width field, ≤63. |
| 146 | 63 | compiler_version | ASCII, NUL-padded to 63 bytes; readers consume only `compiler_version_len` bytes. |
| 209 | 4 | fp_flags | `u32` bitfield. Bit 0 = `FP_FAST_MATH`, bit 1 = `FP_FMA_ALLOWED`, bit 2 = `FP_CONTRACT_ON`, bit 3 = `FP_DENORMALS_ON`, bit 4 = `FP_X87_USED`. All other bits reserved (must be zero). |
| 213 | 1 | libm_id_len | `u8`; number of valid bytes in the following fixed-width field, ≤63. |
| 214 | 63 | libm_id | ASCII, NUL-padded to 63 bytes. Empty (length 0) if the backend's engine hot path makes no libm transcendental calls. |
| 277 | 4 | cpu_features | `u32` bitfield. Bit 0 = `AVX2`, bit 1 = `AVX512F`, bit 2 = `BMI2`, bit 3 = `FMA3`, bit 4 = `NEON`, bit 5 = `SVE`. All other bits reserved (must be zero). |
| 281 | 1 | fp_env | `u8`; bits 0-1 = rounding mode (`0=RNE`, `1=RZ`, `2=RD`, `3=RU`), bit 2 = FTZ, bit 3 = DAZ. `0` = IEEE defaults. |

Total block length in version-1 is fixed at 282 bytes. The two string fields are
length-prefixed for decoding, but their storage slots are fixed-width so the
remaining offsets stay stable.

The envelope is excluded from the cross-backend **determinism payload** (see
[Content Addressing](#content-addressing) below). The cached file hash remains
backend-specific because `RunConfig` includes the backend, but `mcts verify`
compares a canonical decoded payload that omits provenance fields such as
`backend` and the envelope. This is the property cross-backend visit-equality
requires.

Version handling: the current reader recognises transcript version `1`,
requires `envelope_offset == 48`, recognises envelope version `1`, and rejects
unsupported transcript or envelope versions with
`AppError TranscriptFormatUnsupported`. If `envelope_byte_length` exceeds the
known v1 payload length, the reader skips those trailing v1 bytes without
interpreting them; unit coverage pins this additive-extension behavior.

### Per-Game Body

After the header and envelope, the body contains exactly one game:

```text
# Example: per-game body schema
game_id u32, then per-move records, then terminator
```

#### Per-Move Record

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 2 | move_index | `u16`; 0-based |
| 2 | 1 | chosen | `u8`; canonical action ID per the single-byte action enumeration |
| 3 | 1 | n_actions | `u8`; the number of `(action, visits)` pairs that follow |
| 4 | n_actions × 5 | pairs | Each pair: `u8 action` then `u32 visits`, sorted ascending by `action` |

Total record size: `4 + n_actions × 5` bytes. Pairs are sorted ascending by
`action` so the byte sequence is canonical: any two backends that produce the
same set of `(action, visits)` data produce identical bytes.

#### Terminator

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 2 | sentinel | `0xFFFF`; impossible for a valid `move_index` because `max_plies` is bounded by `u16` and the supported configurations never allow 65,535 moves |
| 2 | 1 | winner | `0 = hero`, `1 = villain`, `2 = draw` |
| 3 | 2 | total_moves | `u16`; the number of per-move records that preceded the terminator |

### File End

The file ends immediately after the single game's terminator. The
content-addressed cache uses `sha256(RunConfig)` as the filename (see
[Content Addressing](#content-addressing) below) — the hash is computed
over the canonical encoding of the `RunConfig` record alone, *not* over
the whole file. The envelope block and per-game body are part of the
file but excluded from the cache-key hash. Cross-backend equality is
checked with a separate canonical determinism payload decoded from the
file.

## Action Enumeration

Canonical single-byte action enumeration. The byte namespace packs 209 legal
actions, 46 reserved codes, and 1 sentinel into 256 codes total (one byte per
action):

```text
# Example: single-byte canonical action enumeration
  0..80    pawn moves         y*9 + x           (x,y ∈ [0,8])      — 81 actions
 81..144   horizontal walls   81  + y*8 + x     (x,y ∈ [0,7])      — 64 actions
145..208   vertical walls     145 + y*8 + x     (x,y ∈ [0,7])      — 64 actions
209..254   reserved                                                — 46 codes
255        sentinel / invalid                                      — 1 code
```

Total legal actions: 81 + 64 + 64 = 209. Total byte namespace: 256.

The encoding lives in `src/MCTS/Transcript/Action.hs`. The single-byte action
enumeration is pinned by the determinism contract; future enumeration changes
ride the `flags` field, which currently must be zero.

The implemented `Action` domain admits only the valid range `0..208` through
`actionFromId :: Word8 -> Maybe Action`. The reserved range `209..254` and the
sentinel/invalid byte `255` are rejected as actions; `255` is used only by
terminator/sentinel contexts outside the `Action` model. See
[haskell_code_guide.md → Smart Constructors for Bounded Domain
Types](./haskell_code_guide.md) for the project-wide pattern; the
`decode . encode == id` property in
[unit_testing_policy.md → Property Invariants](./unit_testing_policy.md)
holds vacuously over the smart constructor's accepted subset.

## Content Addressing

### Standard Transcripts

Transcripts produced by `mcts bench rollouts/selfplay` and by `mcts verify
rollouts/selfplay` are one-game files addressed by the SHA-256 of
the canonical little-endian encoding of the backend-specific `RunConfig` record:

```haskell
-- Example: RunConfig record hashed for transcript addressing
data RunConfig = RunConfig
  { runConfigBackend      :: Backend
  , runConfigWorkload     :: Workload     -- Rollouts | Selfplay
  , runConfigThreading    :: Threading
  , runConfigRngSource    :: RngSource
  , runConfigMasterSeed   :: Word64
  , runConfigInitialSims  :: Word32      -- SimBudget low half
  , runConfigPerMoveSims  :: Word32      -- SimBudget high half
  , runConfigMaxPlies     :: Word16
  , runConfigGameIndex    :: Word32      -- per-game index; wire width matches
                                          -- the README's `game_id u32`, widened
                                          -- to Word64 with `fromIntegral` at
                                          -- the splitmix and FFI call sites
                                          -- (see determinism_contract.md and
                                          -- backend_ffi_contract.md)
  , runConfigGames        :: Word32      -- batch count; not part of the hash
  , runConfigCParam       :: Double      -- bit-cast to Word64 in the hash
  }
```

The cache-key encoding is a canonical little-endian projection, not the whole
header byte sequence. The hash input order is:

```text
backend u8 | workload u8 | threading u8 | workers u16 | rng_source u8
| master_seed u64 | initial_sims u32 | per_move_sims u32 | max_plies u16
| game_index u32 | c_param_bits u64
```

`runConfigGames` is deliberately excluded: it describes the requested batch, not
the one-game artifact being addressed. `game_index` must equal the `game_id u32`
stored in the body. The hash is the hex-encoded SHA-256 digest of this record.
Because `runConfigBackend` participates in this cache key, different backends
never overwrite each other's provenance-bearing `.tr` files.

For cross-backend `verify`, the comparator decodes each backend-specific file and
computes a **determinism payload digest** over the common inputs and per-move
records: `rng_source`, `c_param`, `master_seed`, `game_index`, `initial_sims`,
`per_move_sims`, `max_plies`, the chosen action sequence, sorted `(action,
visits)` vectors, `winner`, and `total_moves`. The payload excludes
`runConfigBackend`, the engine envelope, the filesystem path, and cache metadata.
Pairs whose payload digests differ are then scanned with explicit length and
terminator checks. The verifier reports extra or missing games/moves as
`VerifyLengthMismatch`, winner or total-move disagreement as
`VerifyTerminatorMismatch`, and otherwise the first divergent record as
`VerifyMismatch`.

### `mcts play`-Recorded Transcripts

Hand-played transcripts produced by `mcts play` are addressed by
`sha256(run_config || move_history)` (where `||` denotes byte concatenation)
rather than `sha256(run_config)` alone, because the human's move choices make the
post-config bytes non-deterministic. The `move_history` is the canonical encoded
per-move record sequence, including the chosen action and any visit-count vector
captured for AI moves. When `mcts play` uses a selected foreign backend and the
matching cdylib is present, that visit vector comes from the backend's
`search_move` ABI after the current history has been replayed through
`apply_action`; otherwise it comes from the in-process fallback. `MCTS.Transcript.writePlayTranscript`
is the writer for this address shape; batch benchmark and verify transcripts continue
to use the per-game `sha256(run_config)` writer.

## Cache Root Resolution

Per
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item 12](../../DEVELOPMENT_PLAN/00-overview.md):

1. `--cache-dir <path>` if provided.
2. `./.mcts-cache/` resolved against the current working directory inside the
   container.

The `mcts` binary does not read a cache-root environment variable.

On-disk layout under the cache root:

```text
# Example: on-disk transcript cache layout under <cache-root>
<cache-root>/transcripts/<arch>/<sha>.tr                                    # one-game backend-specific transcript
<cache-root>/transcripts/<arch>/<sha>/                                      # sidecar directory (one per transcript, lazily created)
  <backend>-<build_label>.eq                                                # per-backend equity series, see Equity Sidecar Cache
  <backend>-<build_label>.envelope                                          # snapshot of the engine envelope that wrote this .eq
```

`<arch>` is `amd64` or `arm64` per the host architecture the transcript was
written on. The `<sha>` is the full 64-character hex-encoded backend-specific
cache-key digest.
Per-arch partitioning ensures that arm64 and amd64 caches do not collide on
shared filesystems (e.g., NFS-mounted home directories or shared CI cache
volumes), and hash-prefix lookup naturally scopes to the current host's arch.
See [determinism_contract.md → Architecture
Envelope](./determinism_contract.md).

The cache root is `.gitignore`'d when it falls inside the project tree. Test
suites that need transcript files create their own temporary cache roots and
delete them with the test process; repository paths such as `test/golden/` are
not transcript cache inputs.

## Equity Sidecar Cache

The wire format excludes equity by design (see [Design
Principles](#design-principles)): floats are summation-order-sensitive and
would import non-determinism into the content hash. But the REPL's
multi-backend overlay (`mcts inspect replay`, see
[cli_command_surface.md → `mcts inspect replay`](./cli_command_surface.md))
needs to display per-backend equity series, including the originator's
equities and the lazily-recomputed equities of *other* backends viewing
the same transcript. To avoid recomputing the same `(transcript, backend,
build)` triple twice, those equity series are cached in a sidecar
directory alongside the transcript.

### Layout

For a transcript at `<cache-root>/transcripts/<arch>/<sha>.tr`, the
sidecar directory is `<cache-root>/transcripts/<arch>/<sha>/`. Inside, one
`(backend, build)` pair gets two files:

- `<backend>-<build_label>.eq` — the per-move equity series,
  binary format below.
- `<backend>-<build_label>.envelope` — exactly the binary engine
  envelope block supplied by the backend that wrote the sidecar, so scripts can
  `cat .envelope` without parsing the `.eq` stream.

`<backend>` is the string identifier (`cpp-legacy`, `cpp-imperative`,
`cpp-functional`, `rust`, `haskell`). `<build_label>` is the first 16 hex
characters of the backend's `engine_build_id` for a live backend envelope (the
SHA-256 of its loaded shared library / executable). Logical in-process GHC envelopes
with an all-zero `engine_build_id` use `logical` as their display/cache build
label, yielding full sidecar names such as `rust-a1b2c3d4e5f60718.eq` and
`haskell-logical.eq`. The 16-char prefix is collision-safe for any realistic
number of cohabiting builds (the birthday bound is 2^32 before a 50/50
collision) and short enough to be human-eyeable.

Multi-build cohabitation is automatic: a rebuild produces a new
`engine_build_id`, lands in a fresh cache slot, and leaves the old slot
intact for forensic comparison. Pruning is explicit
(`mcts inspect cache prune`).

### `.eq` Wire Format

The `.eq` file is little-endian binary, no padding, no schema-library
dependency — same principles as the transcript itself.

Current implementation baseline: `src/MCTS/Transcript/EquitySidecar.hs`
stores `EqStream` in the binary `MEQ1` format below and writes a neighbouring
`.envelope` file containing the same binary envelope block used in the transcript.
`inspect show --with-equity` first loads an envelope-matched originator sidecar
when one exists. On an originator cache miss, it writes a replacement only
through the transcript's same backend/build recompute path; stale, unavailable,
fallback, or foreign recompute evidence is labelled as such and is not written
as originator evidence. `inspect cache list` marks each sidecar as originator,
foreign, or unknown and `inspect cache prune --keep-current` exercises the
documented cache layout through a Plan/Apply deletion plan.

```text
# Example: .eq sidecar wire format
Header:
  u32 magic = MEQ1                   -- "MEQ1" ASCII (0x4D 0x45 0x51 0x31)
  u16 version = 1
  u8  backend
  u8  transcript_hash_len
  64 bytes transcript_hash           -- ASCII, NUL-padded
  u8  build_id_len
  63 bytes build_id                  -- ASCII, NUL-padded
  u32 record_count

Per-move records, one per move in the transcript:
  u32 game_id
  u16 move_index
  u8  chosen_action_id
  f64 equity                         -- IEEE-754 double, bit-cast to u64 little-endian

Terminator:
  u32 sentinel = 0xFFFFFFFF
```

Visits are not duplicated in the `.eq` stream. Same-backend originator recompute
compares recomputed visits and chosen actions against the transcript before
writing the sidecar: under `--rng cpp` they MUST agree. Foreign-view recompute of
another backend's transcript emits that backend's own comparison stream; chosen
or visit disagreement is surfaced as divergence-smell evidence instead of
originator corruption (see
[determinism_contract.md → Divergence Smell](./determinism_contract.md)).
`mcts inspect replay` uses the same writer on originator cache miss before
starting the TUI, so a successful replay-preparation recompute creates the same
sidecar that later opens read instantly.

### Originator vs Foreign Columns

The transcript's `backend` header field identifies the originator. The
originator sidecar carries the original-equity stream for that backend/build
slot when its neighbouring `.envelope` bytes match the transcript's recorded
originator envelope. Under a live backend envelope, those values are bit-equal to
what the search computed on the original run by the chain of guarantees in
[determinism_contract.md → Replay Equity
Guarantees](./determinism_contract.md). Every other `.eq` in the sidecar
directory is a foreign column: a recompute by a different engine, useful for
cross-engine comparison but not "the original numbers."

`mcts inspect cache list` marks every slot as `originator`, `foreign`, or
`unknown` (when the neighbouring transcript is absent or unreadable). The REPL
marks the originator with a ★ and surfaces envelope match status (verified /
build-mismatch / foreign-view) per
[cli_command_surface.md → `mcts inspect replay`](./cli_command_surface.md).

## Hash-Prefix Lookup

Git-style. Per
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item 13](../../DEVELOPMENT_PLAN/00-overview.md):

- Minimum prefix length: 4 hex characters.
- On no match: `AppError TranscriptNotFound`.
- On multi-match: `AppError TranscriptAmbiguous` carrying the candidate hash list.
- On unique match: the resolved `TranscriptRef`.

The lookup is purely lexical over filenames under
`<cache-root>/transcripts/<arch>/*.tr` for the current host arch; no transcript
bytes are read.

## Atomic Writes

The transcript writer and equity-sidecar writer both write to a temp file in the
same directory, flush, fsync the file descriptor, rename to the final path, and
best-effort fsync the parent directory. This guarantees that any file under
`<cache-root>/transcripts/` is either complete and valid or absent — there is no
torn-write window.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [determinism_contract.md](./determinism_contract.md) — visit-count vs equity
  asymmetry that motivates the equity-excluded wire format; engine envelope
  layered rule; divergence-smell metric
- [backend_ffi_contract.md](./backend_ffi_contract.md) — how each backend writes
  the wire format from its FFI driver; `mcts_<backend>_get_envelope` and
  `mcts_<backend>_recompute_equities` FFI surfaces
- [cli_command_surface.md](./cli_command_surface.md) — `mcts inspect list`,
  `mcts inspect show` (including `--envelope`), `mcts inspect replay`
  (multi-backend overlay), `mcts inspect cache`
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
