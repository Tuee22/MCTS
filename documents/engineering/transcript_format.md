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
- **Content-addressed.** Transcripts live in
  `<cache-root>/transcripts/<arch>/<sha>.tr` (arch-partitioned per the
  architecture envelope) where `<sha>` is `sha256(run_config)` (or
  `sha256(run_config || move_history)` for `mcts play`-recorded transcripts;
  see [Content Addressing](#content-addressing)).

## Wire Format

The authoritative wire format is specified by the project
[../../README.md → Cross-backend verification → Transcript wire format](../../README.md).
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
| 42 | 2 | _reserved | Must be zero on write, ignored on read |
| 44 | 4 | envelope_offset | `u32`; byte offset from file start where the [Envelope Block](#envelope-block) begins. Always `48` in version-1 transcripts (the envelope immediately follows the fixed header), but explicit so future header changes can grow the fixed header without breaking envelope readers. |
| 48 | — | — | Header end; envelope block begins at `envelope_offset`, per-game body begins immediately after the envelope block |

**`SimBudget` encoding.** For `FixedSims N`, both `initial_sims` and
`per_move_sims` are set to `N` (the on-wire discriminator for `FixedSims` is
`initial_sims == per_move_sims`). For `RampedSims N0 N1`, `initial_sims = N0` and
`per_move_sims = N1`.

### Envelope Block

The envelope block records every substrate-affecting field at the time the
transcript was written — the build identity of every backend involved, the
compiler and libm versions, the FP-relevant compiler flags, the CPU features
the binary actually dispatched, and the FP environment at engine-run time.
It is part of the transcript file but **excluded from `sha256(RunConfig)`**:
cross-backend visit-equality requires that two backends running the same
`RunConfig` produce the same `<sha>.tr` filename even though their envelopes
differ. See [determinism_contract.md → Engine Envelope](./determinism_contract.md)
for the layered cohort-invariant vs per-backend-slot rule and how
`mcts verify` enforces it.

The block lives at `envelope_offset` (byte 48 in version-1 transcripts):

| Offset (within block) | Size | Field | Notes |
|-----------------------|------|-------|-------|
| 0 | 2 | envelope_version | `u16`; currently `1`. New envelope fields are appended additively; older readers tolerate trailing bytes they do not recognise. |
| 2 | 4 | envelope_byte_length | `u32`; total length of the envelope block in bytes, counting from `envelope_version` through the last byte of the block. A decoder that does not recognise an `envelope_version` skips past the block by reading this field. |
| 6 | 1 | rng_source_envelope | `u8`; matches the header's `rng_source`. Recorded inside the envelope so the cohort-uniformity check is uniform across fields. |
| 7 | 1 | host_arch_envelope | `u8`; matches the header's `host_arch`. Same rationale as `rng_source_envelope`. |
| 8 | 32 | shared_rng_build_id | SHA-256 of the loaded `cpp_rng.so`. All-zero for `--rng native` transcripts. Under `mcts verify legacy-parity` pinned to backend (i)'s `engine_build_id`. |
| 40 | 32 | run_config_hash | `sha256(RunConfig)`. Redundant with the filename; recorded inline for cohort-uniformity checks. |
| 72 | 32 | engine_build_id | SHA-256 of the loaded backend shared library / executable that wrote this transcript. |
| 104 | 40 | engine_git_commit | ASCII; project repo commit SHA at build time. Padded with NULs if shorter than 40 bytes. Informational; does not gate `verify`. |
| 144 | 1 | compiler_id | `u8`; `0 = gcc`, `1 = clang`, `2 = rustc`, `3 = ghc`. |
| 145 | 1 | compiler_version_len | `u8`; length of the following ASCII string, ≤63. |
| 146 | `compiler_version_len` | compiler_version | ASCII; e.g., `"13.2.0"`. No NUL terminator (length-prefixed). |
| … | 4 | fp_flags | `u32` bitfield. Bit 0 = `FP_FAST_MATH`, bit 1 = `FP_FMA_ALLOWED`, bit 2 = `FP_CONTRACT_ON`, bit 3 = `FP_DENORMALS_ON`, bit 4 = `FP_X87_USED`. All other bits reserved (must be zero). |
| … | 1 | libm_id_len | `u8`; length of the following ASCII string, ≤63. |
| … | `libm_id_len` | libm_id | ASCII; e.g., `"glibc-2.39"`. Empty (length 0) if the backend's engine hot path makes no libm transcendental calls. |
| … | 4 | cpu_features | `u32` bitfield. Bit 0 = `AVX2`, bit 1 = `AVX512F`, bit 2 = `BMI2`, bit 3 = `FMA3`, bit 4 = `NEON`, bit 5 = `SVE`. All other bits reserved (must be zero). |
| … | 1 | fp_env | `u8`; bits 0-1 = rounding mode (`0=RNE`, `1=RZ`, `2=RD`, `3=RU`), bit 2 = FTZ, bit 3 = DAZ. `0` = IEEE defaults. |

Total block length in version-1 with default-length `compiler_version` and
`libm_id` is bounded by `145 + 1 + 63 + 4 + 1 + 63 + 4 + 1 = 282` bytes;
typical values land around 160-200 bytes.

The envelope is **excluded from `sha256(RunConfig)`** (see [Content
Addressing](#content-addressing) below): the encoder hashes the `RunConfig`
record alone, so two backends producing the same `RunConfig` under
`--rng cpp` write to the same `<sha>.tr` filename even though their
envelopes differ. This is the property cross-backend visit-equality
requires.

Version handling: a reader that recognises `envelope_version` reads
the fields it knows about by their fixed-or-length-prefixed widths; if
`envelope_byte_length` exceeds what the reader expects for that version,
the trailing bytes are skipped silently. A reader that does **not**
recognise the version skips the entire block via `envelope_byte_length`
and decodes the per-game body normally — visit counts remain
machine-readable across envelope-version drift.

### Per-Game Body

After the header, the per-game body is:

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
| 0 | 1 | sentinel | `0xFF`; distinguishes a terminator from a per-move record (whose `move_index` low byte is never `0xFF` because the wire field is `u16`) |
| 1 | 1 | winner | `0 = hero`, `1 = villain`, `2 = draw` |
| 2 | 2 | total_moves | `u16`; the number of per-move records that preceded the terminator |

### File End

The file ends immediately after the terminator of the last game. The
content-addressed cache uses `sha256(RunConfig)` as the filename (see
[Content Addressing](#content-addressing) below) — the hash is computed
over the canonical encoding of the `RunConfig` record alone, *not* over
the whole file. The envelope block and per-game body are part of the
file but excluded from the hash, so two backends running the same
`RunConfig` under `--rng cpp` land at the same filename even though their
envelopes differ — exactly the property cross-backend visit-equality
requires.

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

`ActionId` is a newtype with a smart constructor (`mkActionId :: Word8 ->
Either AppError ActionId`) that rejects the reserved range `209..254`,
admits the sentinel `255`, and admits the valid range `0..208`. The data
constructor is not exported from `MCTS.Transcript.Action`. See
[haskell_code_guide.md → Smart Constructors for Bounded Domain
Types](./haskell_code_guide.md) for the project-wide pattern; the
`decode . encode == id` property in
[unit_testing_policy.md → Property Invariants](./unit_testing_policy.md)
holds vacuously over the smart constructor's accepted subset.

## Content Addressing

### Standard Transcripts

Transcripts produced by `mcts bench rollouts/selfplay` and by `mcts verify
rollouts/selfplay/legacy-parity` are addressed by the SHA-256 of the canonical
little-endian encoding of the `RunConfig` record:

```haskell
-- Example: RunConfig record hashed for transcript addressing
data RunConfig = RunConfig
  { runConfigBackend      :: Backend
  , runConfigThreading    :: Threading
  , runConfigWorkers      :: Word16
  , runConfigRngSource    :: RngSource
  , runConfigCParam       :: Double      -- bit-cast to Word64 on the wire
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
  }
```

The field order and on-wire byte width match the header layout above (game_index
is appended after the on-wire header fields for hashing purposes only — it is
the per-game discriminator and lives in the per-game body, not the header). The
hash is the hex-encoded SHA-256 digest of this record.

### `mcts play`-Recorded Transcripts

Hand-played transcripts produced by `mcts play` are addressed by
`sha256(run_config || move_history)` (where `||` denotes byte concatenation)
rather than `sha256(run_config)` alone, because the human's move choices make the
post-config bytes non-deterministic. The `move_history` is the canonical
byte sequence of `chosen_action` values from the per-move records.

## Cache Root Resolution

Per
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item 12](../../DEVELOPMENT_PLAN/00-overview.md):

1. `--cache-dir <path>` if provided.
2. `$MCTS_CACHE_DIR` if set.
3. `./.mcts-cache/` resolved against the current working directory.

On-disk layout under the cache root:

```text
# Example: on-disk transcript cache layout under <cache-root>
<cache-root>/transcripts/<arch>/<sha>.tr                                    # canonical transcript (hash-stable, visits only)
<cache-root>/transcripts/<arch>/<sha>/                                      # sidecar directory (one per transcript, lazily created)
  <backend>-<engine_build_id_prefix16>.eq                                   # per-backend equity series, see Equity Sidecar Cache
  <backend>-<engine_build_id_prefix16>.envelope                             # snapshot of the engine envelope that wrote this .eq
```

`<arch>` is `amd64` or `arm64` per the host architecture the transcript was
written on. The `<sha>` is the full 64-character hex-encoded SHA-256 digest.
Per-arch partitioning ensures that arm64 and amd64 caches do not collide on
shared filesystems (e.g., NFS-mounted home directories or shared CI cache
volumes), and hash-prefix lookup naturally scopes to the current host's arch.
See [determinism_contract.md → Architecture
Envelope](./determinism_contract.md).

The cache root is `.gitignore`'d when it falls inside the project tree.

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

- `<backend>-<engine_build_id_prefix16>.eq` — the per-move equity series,
  binary format below.
- `<backend>-<engine_build_id_prefix16>.envelope` — exactly the envelope
  block extracted from the `.eq` header (see below), so scripts can
  `cat .envelope` without parsing.

`<backend>` is the string identifier (`cpp-legacy`, `cpp-imperative`,
`cpp-functional`, `rust`, `haskell`). `<engine_build_id_prefix16>` is
the first 16 hex characters of the backend's `engine_build_id` (the
SHA-256 of its loaded shared library / executable). The 16-char prefix
is collision-safe for any realistic number of cohabiting builds (the
birthday bound is 2³² before a 50/50 collision) and short enough to be
human-eyeable.

Multi-build cohabitation is automatic: a rebuild produces a new
`engine_build_id`, lands in a fresh cache slot, and leaves the old slot
intact for forensic comparison. Pruning is explicit
(`mcts inspect cache prune`).

### `.eq` Wire Format

The `.eq` file is little-endian binary, no padding, no schema-library
dependency — same principles as the transcript itself.

```text
# Example: .eq sidecar wire format
Header:
  u32 magic = MCEQ                   -- "MCEQ" ASCII (0x4D 0x43 0x45 0x51)
  u16 version = 1
  envelope_block                     -- exactly the wire-format envelope of the backend+build that wrote this .eq
  32 bytes transcript_hash           -- the sha256 of the corresponding .tr (defensive integrity check)

Per-move records, one per move in the transcript:
  u16 move_index
  u16 n_alternatives                 -- matches the transcript's per-move n_actions exactly
  n_alternatives × {
    u8  action_id                    -- matches the transcript's action_id at this slot
    u32 visits                       -- recomputed by this backend+build
    f64 equity                       -- IEEE-754 double, bit-cast to u64 little-endian
  }

Terminator:
  u8  sentinel = 0xFF
  u16 total_moves
```

Visits are recorded so the REPL can sanity-check this column's recompute
against the transcript's recorded visits: under `--rng cpp` within the
(ii)–(v) cohort they MUST agree (built-in determinism check that fires
on every cache write); under `--rng native` or cross-build they
*usually* agree, and disagreement is surfaced as the divergence-smell
metric (see [determinism_contract.md → Divergence Smell](./determinism_contract.md)).

### Originator vs Foreign Columns

The transcript's `backend` header field identifies the originator. The
sidecar `<originator>-<originator_build_prefix16>.eq` carries the
*actual* original equities when its embedded envelope matches the live
originator binary's envelope — those values are bit-equal to what the
search computed on the original run, by the chain of guarantees in
[determinism_contract.md → Replay Equity
Guarantees](./determinism_contract.md). Every other `.eq` in the
sidecar directory is a foreign column: a recompute by a different
engine, useful for cross-engine comparison but not "the original
numbers."

The REPL marks the originator with a ★ and surfaces envelope match
status (verified / build-mismatch / foreign-view) per
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

The transcript writer writes to a temp file in the same directory, fsyncs, then
renames to the final path. This guarantees that any file under
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
