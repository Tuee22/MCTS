# Phase 2: Transcript Codec, RNG, and Determinism Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Land the transcript wire format, the single-byte action enumeration,
> the per-game RNG seed derivation, the cache root resolution and hash-prefix lookup,
> and the non-interactive `mcts inspect list` / `mcts inspect show` surfaces — the
> determinism contract every backend will honour.

## Phase Status

✅ **Done.** The 2026-05-19 alignment sweep reclosed the Phase `2` owned
transcript/cache/envelope surface, and Sprint `2.8` reclosed the 2026-05-21
evidence-surface audit findings for the transcript and sidecar contracts. The
v1 transcript version handling is explicit, the single-byte action-domain docs
match the implemented `Action` conversion, and logical sidecar identities are
unambiguous. `RunConfig` still carries an
explicit `runGameIndex`, `sha256(run_config)` hashes `game_index` instead of
`runGames`, normal batch runs publish only one-game transcript files in the
operator cache, per-game files preserve `master_seed`, and runtime seed
derivation remains `splitmix64(master_seed, game_index)`.

Focused Phase `2` validation passed on 2026-05-21 with
`docker compose run --rm mcts mcts test mcts-unit`,
`docker compose run --rm mcts mcts docs check`,
`docker compose run --rm mcts mcts check-code`, and `git diff --check`.
Sprint `8.8` later removed checked-in transcript, renderer, report-card, and
backend-fixture dependencies from the normal clean-clone suite; Phase `2`
continues to rely on in-memory and temporary-root codec/cache tests.

## Phase Summary

Phase `2` writes the deterministic byte-level layer of the project: the little-endian
binary transcript wire format with no schema-library dependency, the single-byte
action enumeration that gives every legal Corridors action a `u8` ID, the
`splitmix64(master_seed, game_index)` per-game RNG seed derivation that makes per-game
output independent of worker count and scheduling order, the `--rng native` vs
`--rng cpp` split, and the content-addressed transcript cache under
`.mcts-cache/transcripts/`. It also lands the non-interactive `mcts inspect list` and
`mcts inspect show` commands plus the git-style hash-prefix lookup. No engine and no
backend lands yet; this phase is the format spec the engine writes into.

## Sprint 2.1: Wire-Format Header and Per-Move Record Codec ✅

**Status**: Done
**Implementation**: `src/MCTS/Transcript.hs`, `src/MCTS/Transcript/Action.hs`,
`src/MCTS/Transcript/Codec.hs`, `src/MCTS/Types.hs`
**Docs to update**: `documents/engineering/transcript_format.md`,
`documents/engineering/determinism_contract.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Land the deterministic binary wire format: header carrying the run config, per-move
records of `(action_id, visits)` sorted ascending by action ID, equity excluded.

### Deliverables

- `src/MCTS/Transcript/Action.hs` declares the canonical single-byte action enumeration
  as a pure conversion between Corridors action types and `Word8`. The byte namespace
  packs 209 legal actions plus 46 reserved codes plus 1 sentinel into 256 codes:
  - `0..80` pawn moves: `y*9 + x` for `x,y ∈ [0,8]`
  - `81..144` horizontal walls: `81 + y*8 + x` for `x,y ∈ [0,7]`
  - `145..208` vertical walls: `145 + y*8 + x` for `x,y ∈ [0,7]`
  - `209..254` reserved
  - `255` sentinel / invalid
- `src/MCTS/Transcript.hs` carries the header layout per
  [../documents/engineering/transcript_format.md → Header](../documents/engineering/transcript_format.md).
  Little-endian, no padding, fixed-width fields in this exact order:
  - `magic u32 = "MCTR"` — ASCII bytes `0x4D 0x43 0x54 0x52`.
  - `version u16` — wire-format version; v1 in this sprint.
  - `backend u8` — 0=cpp-legacy, 1=cpp-imperative, 2=cpp-functional, 3=rust, 4=haskell.
  - `threading u8` — 0=single, 1=multi.
  - `workers u16` — meaningful only when `threading = multi`.
  - `rng_source u8` — 0=native, 1=cpp.
  - `host_arch u8` — 0=amd64 (Linux x86-64), 1=arm64 (Linux aarch64). Cross-arch
    comparison rejects with `AppError ArchEnvelopeMismatch` per
    [../documents/engineering/determinism_contract.md → Architecture
    Envelope](../documents/engineering/determinism_contract.md).
  - `c_param u64` — UCT exploration constant stored as IEEE-754 `double` bit-cast to
    `u64` little-endian. Portability pins amd64 Linux and arm64 Linux as a two-arch
    envelope (both IEEE-754); bit-equality is per-arch.
  - `flags u32` — reserved for future format extensions. All bits **must** be zero
    in v1; non-zero bits cause `decode` to reject the file with
    `AppError TranscriptFormatUnsupported`.
  - `master_seed u64`.
  - `initial_sims u32` / `per_move_sims u32` — together encode `SimBudget`. For
    `FixedSims N` both fields are N (the on-wire discriminator for `FixedSims` is
    `initial_sims == per_move_sims`). For `RampedSims N0 N1` set
    `initial_sims = N0` and `per_move_sims = N1`.
  - `max_plies u16` — default `200`; pinned to `10000` under the legacy-parity
    envelope.
  - `workload u16` — `0 = rollouts`, `1 = selfplay`; other values are rejected in
    v1.
  - `envelope_offset u32` — byte offset from file start where the Envelope Block
    begins. The fixed header ends at byte 48; the v1 encoder writes the envelope
    block immediately at that offset. The field exists from v1 so future header growth never breaks
    envelope readers, per
    [../documents/engineering/transcript_format.md → Header](../documents/engineering/transcript_format.md).
    Property test `decode . encode == id` covers it.
- `src/MCTS/Transcript.hs` carries the per-game and per-move layout:
  - Per-game body starts with `game_id u32`, then per-move records, then a
    terminator.
  - Per-move record: `move_index u16 | chosen u8 | n_actions u8` followed by
    `n_actions × (action u8, visits u32)` pairs sorted ascending by action.
  - Terminator: `0xFFFF u16 | winner u8 | total_moves u16`, with
    `winner ∈ {0 = hero, 1 = villain, 2 = draw}`. `winner = 2` (draw) is invalid for
    `backend = cpp-legacy` transcripts (backend (i) has no draw rule per
    [../documents/engineering/determinism_contract.md → Backend (i)](../documents/engineering/determinism_contract.md)); the decoder rejects this combination
    with `AppError TranscriptFormatUnsupported`.
- `src/MCTS/Transcript/Codec.hs` exposes pure `encode` and `decode` functions
  satisfying the canonical property invariant `decode . encode == id` per
  [../HASKELL_CLI_TOOL.md → Test Categories → Property Tests](../HASKELL_CLI_TOOL.md);
  Sprint 7.1 owns the property test placement. `decode` rejects non-zero `flags`
  with `AppError TranscriptFormatUnsupported` (the `AppError` constructor is
  declared in
  [phase-1-haskell-cli-surface.md → Sprint 1.9](phase-1-haskell-cli-surface.md)).
- The wire format excludes equity. Cross-backend determinism is enforced on visit
  counts only, per
  [00-overview.md → Hard Constraints item 15](00-overview.md).

### Validation

1. A property test asserts `decode . encode == id` on `Header`, `Record`, and
   `Transcript` (full file).
2. A property test asserts records within a file are sorted ascending by
   `action_id`.
3. Unit coverage asserts representative transcript field offsets, terminator
   shape, cache-key invariants, and envelope round-trips through semantic and
   in-memory byte checks rather than checked-in byte-golden fixtures.

### Closure Notes

- Baseline landed: `MCTS.Transcript` writes and reads the v1 `MCTR` header,
  per-game/per-move records, the documented winner terminator, action IDs, and the
  full v1 envelope block. The decoder preserves workload and sets decoded
  one-game `runGameIndex` from the body `game_id` for `decode . encode`
  roundtrips in the hand-rolled unit suite. `encodeRecord` now
  emits the per-move `(action, visits)` list sorted ascending by `action_id`
  per [../documents/engineering/transcript_format.md → Per-Game Body](../documents/engineering/transcript_format.md),
  and `decodeTranscript` rejects `cpp-legacy` transcripts that carry a `Draw`
  winner (`AppError TranscriptFormatUnsupported`) per
  [../documents/engineering/determinism_contract.md → Backend (i)](../documents/engineering/determinism_contract.md).
  Sprint `8.8` removed the former
  checked-in byte-golden fixtures for representative transcripts and replaced
  them with in-memory byte-layout and determinism-payload assertions so host
  architecture differences cannot make the clean-clone suite flaky.
- The single-module `MCTS.Transcript` implementation is retained as the concrete codec
  owner, with thin `MCTS.Transcript.Codec`, `MCTS.Transcript.Action`,
  `MCTS.Transcript.Cache`, `MCTS.Transcript.Hash`, and `MCTS.Transcript.Lookup`
  wrapper modules preserving the planned public ownership boundaries without duplicating
  parser state.
- Legacy-envelope (`max_plies = 10000`) generated evidence belongs to the backend (i)
  optional evidence path; Phase `2` owns only the codec shape and tests it
  with generated in-memory/temporary transcripts.

### Remaining Work

None.

## Sprint 2.2: Content-Addressed Cache and Cache Root Resolution ✅

**Status**: Done
**Implementation**: `src/MCTS/Transcript/Hash.hs`,
`src/MCTS/Transcript/Cache.hs`, `.gitignore`
**Docs to update**: `documents/engineering/transcript_format.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Land `sha256(run_config)` content addressing, the cache root resolution chain, and
the `.gitignore` entry that keeps the cache out of version control.

### Deliverables

- `src/MCTS/Transcript/Hash.hs` exposes `runConfigHash :: RunConfig -> ByteString`
  computing the backend-specific cache key `sha256(run_config)` over the canonical
  little-endian encoding of the run config; `playTranscriptHash` computes
  `sha256(run_config || move_history)` for `mcts play`-recorded transcripts. The
  `RunConfig` record shape (field list and on-wire byte widths) is owned by
  [../documents/engineering/transcript_format.md → Content
  Addressing](../documents/engineering/transcript_format.md); this sprint imports
  the type from there rather than redefining it.
- `src/MCTS/Transcript.hs` resolves the cache root in this order, per
  [00-overview.md → Hard Constraints item 12](00-overview.md):
  1. `--cache-dir <path>` if provided
  2. `./.mcts-cache/` resolved against the current working directory inside the
     container
  The `mcts` binary does not read a cache-root environment variable.
- On-disk layout under the cache root: `transcripts/<arch>/<sha>.tr`, where
  `<arch>` is `amd64` or `arm64` per
  [../documents/engineering/determinism_contract.md → Architecture Envelope](../documents/engineering/determinism_contract.md).
  The full sha is the hex-encoded `sha256` digest.
- `.gitignore` excludes `.mcts-cache/` when the cache resolves inside the project
  tree.

### Validation

1. A unit test exercises the cache-root resolution chain across all three branches.
2. A round-trip test writes a transcript to a temporary cache root via
   `MCTS.Transcript.Cache.write`, reads it back via `MCTS.Transcript.Cache.read`,
   and asserts byte equality.
3. `git status` in a fresh worktree shows no `.mcts-cache/` entry.

### Closure Notes

- Baseline landed: pure SHA-256 hashing, `runConfigHash`, `playTranscriptHash`,
  cache-root resolution, arch-partitioned transcript paths, transcript writes, and the
  `.mcts-cache/` ignore rule. Transcript writes now use a same-directory temp file
  with explicit fsync coverage: `writeFileAtomically` opens the temp file via
  `openBinaryTempFile`, `BS.hPut`s the bytes, `hFlush`s, calls
  `System.Posix.IO.handleToFd` to obtain the underlying file descriptor
  (which closes the handle but preserves the Fd), invokes
  `System.Posix.Unistd.fileSynchronise` on that Fd, closes it, performs
  the rename, then fsync's the parent directory (best-effort — fsync on
  a directory may be a no-op on some kernels). The `unix` package is now
  a declared dependency.
- Cache-root branch coverage for explicit `--cache-dir` and default project-local
  cache behavior lives in `mcts-unit`.
- `RunConfig` now has a real `runGameIndex` cache-key discriminator. `runGames`
  is excluded from `encodeRunConfig`; normal batch writes publish one `.tr` file
  per game via `writeTranscriptPerGame`, preserve `master_seed`, set
  `runGames = 1`, and set `runGameIndex = game_id`.
- Container validation confirmed generated `.mcts-cache/` contents are ignored by git and
  do not appear in `git status --short --ignored`.

### Remaining Work

None.

## Sprint 2.3: Git-Style Hash-Prefix Lookup ✅

**Status**: Done
**Implementation**: `src/MCTS/Transcript/Lookup.hs`
**Docs to update**: `documents/engineering/transcript_format.md`,
`documents/engineering/cli_command_surface.md`

### Objective

Land `lookupByPrefix :: Text -> App (Either AppError TranscriptRef)` so the
`inspect show` and `inspect replay` `<hash-prefix>` arguments resolve to a unique
transcript with the doctrine-flavoured error rendering.

### Deliverables

- `src/MCTS/Transcript/Lookup.hs` exposes `lookupByPrefix` per
  [00-overview.md → Hard Constraints item 13](00-overview.md):
  - Minimum prefix is 4 hex characters.
  - On no match, return `AppError TranscriptNotFound`.
  - On multi-match, return `AppError TranscriptAmbiguous` carrying the candidate
    list so the operator can re-issue with a longer prefix.
  - On unique match, return the resolved `TranscriptRef`.
- The lookup is purely lexical over filenames under
  `<cache-root>/transcripts/<arch>/*.tr` for the current host arch; no
  transcript bytes are read. The host arch is the one returned by the
  toolchain prereq probe (Sprint 1.7).

### Validation

1. Unit tests cover the no-match, ambiguous-match, exact-match, and
   too-short-prefix branches.
2. Property test: for any populated cache with N transcripts, any prefix `p` of
   `sha(t)` that is unique among the set returns `t` and nothing else.

### Closure Notes

- Baseline landed: `lookupByPrefix` enforces a four-hex-character minimum, scans the
  current-arch transcript cache, and returns `TranscriptNotFound` /
  `TranscriptAmbiguous` / the unique path. Hand-rolled unit coverage exercises the
  too-short, non-hex, no-match, ambiguous, and exact-match branches. The
  `mcts-unit` stanza now also exercises the unique-prefix property over a
  populated synthetic cache of 6 hashes at 7 prefix lengths (28 cases):
  every prefix that's unique among the set returns the single matching
  hash, every prefix that collides returns `TranscriptAmbiguous` with
  exactly the colliding candidates, and a non-matching prefix returns
  `TranscriptNotFound`.
- `lookupByPrefix` now returns a typed `TranscriptRef` carrying the resolved full hash and
  file path. Ambiguous-prefix errors render candidate hashes rather than paths.

### Remaining Work

None.

## Sprint 2.4: `mcts inspect list` and `mcts inspect show` ✅

**Status**: Done
**Implementation**: `src/MCTS/CLI/Inspect.hs`,
`src/MCTS/CLI/Spec.hs` (Inspect subtree),
`src/MCTS/Notation.hs`
**Docs to update**: `documents/engineering/cli_command_surface.md`,
`documents/engineering/transcript_format.md`

### Objective

Land the non-interactive `inspect` commands: `mcts inspect list` for cache
enumeration and `mcts inspect show <hash-prefix>` for transcript dump in the
legacy move notation. `mcts inspect replay` (interactive `brick` TUI) is owned by
Sprint 7.4.

### Deliverables

- `src/MCTS/Notation.hs` exposes `renderMove :: Move -> Text` and the inverse
  parser for the legacy move notation: `*(x,y)` pawn, `H(x,y)` horizontal wall,
  `V(x,y)` vertical wall, with `x,y ∈ [0,8]` for pawns and `∈ [0,7]` for walls.
  Draws render as `<draw>`.
- `src/MCTS/CLI/Inspect.hs` owns the runners:
  - `mcts inspect list` scans `<cache-root>/transcripts/<arch>/*.tr` for the
    current host arch, decodes each header,
    prints one line per transcript: short hash (first 8 chars), backend, master
    seed, threading (`ST` or `MT8`), sims, game id, total moves, mtime. Sorted
    by mtime descending. Honours `--format json|table|plain`.
  - `mcts inspect show <hash-prefix>` resolves the prefix via Sprint 2.3, decodes
    the transcript, prints the header summary followed by per-move records in the
    legacy notation. Default `--top 10`;
    `--top 0` shows all legal moves.
  - **`--with-equity` column.** When `--with-equity` is set, the per-move record
    renderer emits an `equity=<float>` column on every line per
    [../documents/engineering/cli_command_surface.md → Replay and Equity Semantics](../documents/engineering/cli_command_surface.md).
    The equity values are produced by the same pure
    rendering function that the `inspect replay` TUI's context panel uses
    (Sprint 7.4), so the two surfaces stay aligned. The recompute path itself
    (re-running the deterministic search to populate the equity values) lands
    in Sprint 7.4; Sprint 2.4 wires the column slot, the flag, and the shared
    renderer signature so that hooking the recompute path is a one-line wiring
    change in 7.4.
- The `CommandSpec` entries for `inspect list` and `inspect show` carry at least
  one `Example` entry each, per
  [../HASKELL_CLI_TOOL.md → Command Topology](../HASKELL_CLI_TOOL.md) and
  [../HASKELL_CLI_TOOL.md → Automatically Generated Documentation](../HASKELL_CLI_TOOL.md).
  Both commands honour `--format json|table|plain` and the standard color flags
  per [../HASKELL_CLI_TOOL.md → Output Rules](../HASKELL_CLI_TOOL.md).

### Validation

1. A round-trip test writes a known transcript to a temporary cache root, runs
   `mcts inspect show <prefix>`, and asserts the parsed/rendered fields
   semantically.
2. `mcts inspect list --format json` emits valid JSON; the test validates the
   expected keys and field types directly instead of reading a checked-in schema
   fixture.
3. A unit test asserts the move-notation renderer / parser round-trips over every
   action in the single-byte action enumeration.

### Closure Notes

- Baseline landed: `mcts inspect list`, `mcts inspect show <prefix>`,
  `--top`, `--with-equity`, `--envelope`, JSON/plain output branches, and legacy move
  notation round-trips exist. `inspect list` now renders the planned threading,
  sims, total-move, and mtime columns in table/plain output and the equivalent
  fields in JSON.
- The sidecar path is recompute-backed on cache miss, and `inspect show
  --with-equity` first loads an envelope-matched originator sidecar when present.
  The inline text renderer reads the resulting `EqStream` for the per-move
  `equity=<float>` column instead of a fixed placeholder.
- `inspect show --envelope` renders all v1 logical envelope fields in plain text
  and JSON.
- Sprint `8.8` replaced byte-stable `inspect show` text and
  `inspect list --format json` fixture residue with semantic assertions while
  preserving the round-trip coverage over every action in the single-byte action
  enumeration.

### Remaining Work

None.

## Sprint 2.5: `splitmix64` Seed Derivation and `--rng` Plumbing ✅

**Status**: Done
**Implementation**: `src/MCTS/Rng/Mix.hs`, `src/MCTS/Types.hs`,
`src/MCTS/CLI/Parser.hs` (`--rng` option), `src/MCTS/Engine.hs`
**Docs to update**: `documents/engineering/determinism_contract.md`,
`documents/engineering/cli_command_surface.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Land the per-game `splitmix64(master_seed, game_index)` seed mixer, the
`RngSource = NativeRng | CppRng` type, and the `--rng native|cpp` parser surface.
The Haskell-side `NativeRng` consumer is `splitmix`; the C++ FFI-backed `CppRng`
consumer is wired in Phase 4 once the FFI bridge exists.

### Deliverables

- `src/MCTS/Rng/Mix.hs` exposes
  `mix :: Word64 -> Word64 -> Word64` implementing the splitmix64 mixer per
  [00-overview.md → Hard Constraints item 4](00-overview.md). The game-index
  argument is `Word64` to match the C ABI's `cpp_rng_split(uint64_t master_seed,
  uint64_t game_index)` from
  [../documents/engineering/backend_ffi_contract.md → `--rng cpp` Plumbing](../documents/engineering/backend_ffi_contract.md);
  callers that hold a `Word32` wire-format `runConfigGameIndex` widen with
  `fromIntegral` at the call site. Tests pin the mixer output for a known
  `(master_seed, game_index)` pair to a known `Word64`.
- `src/MCTS/Types.hs` declares `data RngSource = NativeRng | CppRng`. Parsing
  of `--rng native` and `--rng cpp` is registered in the `CommandSpec`.
- The current Haskell-native RNG consumer lives in the Phase 3 driver and search
  modules by applying `MCTS.Rng.Mix.mix` to the master seed and game/move index.
  A separate native-RNG module is not present in the baseline; real per-backend
  native RNG streams remain owned by the backend-driver sprints.
- The `verify` subtree defaults to `--rng cpp` and rejects `--rng native` during
  parser validation; the parsed `VerifyCommand` carries `RunInputs` plus the
  live `[VerifyBackend]` cohort and `allow-stale` flag.
- Backend (i)'s native RNG asymmetry is legacy compatibility behavior. The current
  live operator surface accepts `--rng native` for `rust` and `haskell` benchmarks/play,
  and requires `--rng cpp` for `verify`.

### Validation

1. Unit tests pin `mix(42, 0) = <Word64>`, `mix(42, 1) = <Word64>` for a chosen
   seed pair without checked-in generated fixture files; the values come from
   the canonical splitmix64 spec.
2. A bounded property test asserts `mix master_seed n` is bijective in `n` for fixed
   `master_seed` over the implemented smoke range; the current `mcts-unit` coverage
   pins uniqueness for `mix 42 i` where `i ∈ [0, 1023]`.
3. Cross-language agreement is asserted through generated test data and the live
   `(rust, haskell)` verify/recompute schedule. Historical C++ RNG split-seed
   evidence remains recorded with backend (i), but the current clean-clone test suite
   does not require a live `cpp-legacy` shared library or committed fixture table.
4. `docker compose run --rm mcts mcts bench rollouts --rng native --backend haskell --games 8 --seed 42`
   runs to completion through the Phase 3 engine wiring; parser and execution
   coverage assert the flag matrix.

### Closure Notes

- Baseline landed: `splitmix64`, `mix`, `RngSource`, `--rng native|cpp` parsing, and
  verification paths that force the cohort to `CppRng`.
- Baseline unit coverage now pins `mix(42, 0) == 2949826092126892291` and
  `mix(42, 1) == 5139283748462763858`, and the `mcts-unit` stanza adds a
  bounded bijection check (`mix 42 i` is unique for `i ∈ [0, 1023]`). Larger
  statistical or exhaustive RNG evidence can be added in a future validation
  expansion, but it is not part of the current clean-clone gate.
- The C++ `cpp_rng_split_seed` / verification-seed bridge belongs to the live
  equivalence path. Current unit and cross-backend tests pin the Haskell splitmix
  values, assert per-backend native salts in `MCTS.Rng.Mix`, and exercise the live
  `(ii)..(v)` `--rng cpp` schedule without relying on committed fixture data.
- Baseline parser coverage rejects user-supplied `--rng native` on `verify` at parse
  time rather than silently overriding the parsed run inputs.

### Remaining Work

None.

## Sprint 2.6: Engine Envelope Codec ✅

**Status**: Done
**Implementation**: `src/MCTS/Transcript.hs`, `src/MCTS/Verify/Envelope.hs`,
`src/MCTS/CLI/Inspect.hs`, `src/MCTS/CLI/Verify.hs`, `test/unit/Main.hs`
**Docs to update**: `documents/engineering/transcript_format.md`,
`documents/engineering/determinism_contract.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Implement the encoder/decoder for the engine-envelope block that lives
between the fixed header and the per-game body of every transcript.
See [../documents/engineering/transcript_format.md → Envelope
Block](../documents/engineering/transcript_format.md) for the wire
format and [../documents/engineering/determinism_contract.md → Engine
Envelope](../documents/engineering/determinism_contract.md) for the
layered cohort-invariant vs per-backend-slot semantics.

### Deliverables

- `src/MCTS/Transcript.hs` — `Envelope` ADT, `encodeEnvelope ::
  Envelope -> Builder`, `decodeEnvelope :: Get Envelope`, plus the
  field-by-field record matching the wire format.
- `src/MCTS/Transcript/Codec.hs` re-exports the existing transcript encoder, which is
  extended to write the envelope block starting at the offset already
  carried by the header's `envelope_offset` field (`48` in v1); the existing
  decoder parses the v1 envelope immediately after the fixed header and then
  continues to the per-game body.
- The backend-specific `sha256(RunConfig)` cache-key path is verified by a property
  test to be invariant under arbitrary envelope changes: the hash is computed over
  the canonical encoding of the `RunConfig` record alone, and the envelope block does
  not perturb it.
- Version-tolerance coverage: a decoder built against `envelope_version = 1`
  successfully reads an envelope block with extra bytes past the version-1 field
  set, skipping the unrecognised trailing bytes via `envelope_byte_length`.
- Envelope round-trip coverage: the unit suite encodes and decodes representative
  `Envelope` values, including empty `libm_id`, max-length string fields, and
  zero `shared_rng_build_id`.
- Same-backend envelope stamping: the Phase `2` codec accepts and preserves a full
  `Envelope` value in every transcript. The current baseline stamps logical
  envelopes from the Haskell driver; replacing those logical values with live
  backend `get_envelope` FFI structs is owned by Sprints `3.6`, `4.2`, `5.5`,
  and `6.5`.

### Validation

- `mcts-unit`: envelope round-trip, version-tolerance, hash-stability,
  sidecar-cache-hit, and full-envelope rendering coverage.
- `mcts-integration`: live-envelope stamping and stale-cache coverage when the
  Rust shared library is present; backend-equivalence fixture shapes are synthesized in
  temporary roots.

### Closure Notes

- Baseline landed: transcripts carry the full v1 engine envelope per
  [../documents/engineering/backend_ffi_contract.md → Engine Envelope](../documents/engineering/backend_ffi_contract.md).
  The `Envelope` ADT carries `envelopeVersion`, `envelopeBackend`,
  `envelopeRngSource`, `envelopeHostArch`, `envelopeSharedRngBuildId`,
  `envelopeCohortConfigHash`, `envelopeEngineBuildId`,
  `envelopeEngineGitCommit`, `envelopeCompilerId`, `envelopeCompilerVersion`,
  `envelopeFpFlags`, `envelopeLibmId`, `envelopeCpuFeatures`, `envelopeFpEnv`,
  and the project-local display/cache `envelopeBuildId` accessor field. The
  encoded wire payload now matches the C ABI `mcts_<backend>_envelope` layout:
  `rng_source_envelope`, `host_arch_envelope`, three 32-byte digests, 40-byte
  git commit, compiler metadata, length-prefixed `compiler_version`, 32-bit
  `fp_flags`, length-prefixed `libm_id`, 32-bit `cpu_features`, and 8-bit
  `fp_env`. The backend comes from the transcript header, and
  `envelopeBuildId` is derived from `engine_build_id` instead of encoded as a
  trailer. `decodeEnvelope . encodeEnvelope == id` round-trips through
  `mcts-unit`. Sprint `8.8` replaced the byte-level transcript-golden residue for
  this shape with semantic byte-layout assertions so supported host architectures
  cannot make the suite flaky. `MCTS.Verify.Envelope`
  cohort-level checks now compare `rng_source`, `shared_rng_build_id`,
  and `cohort_config_hash` (in addition to `host_arch` and
  `envelope_version`); backend-slot checks now compare `engine_build_id`,
  `compiler_id`, `compiler_version`, `fp_flags`, `libm_id`,
  `cpu_features`, and `fp_env` (in addition to `backend`). The display/cache
  `build_id` accessor and `engine_git_commit` are provenance only and do not
  gate stale-envelope verification.
- The current suite uses generated in-memory layout assertions and property
  coverage for this envelope shape.
- Keep `envelope_byte_length` forward-compatible: the current decoder tolerates
  trailing bytes after the v1 field set, and the unit suite exercises that shape;
  a named v2 trailer property lands once a v2 schema is defined.
- The unit suite now proves backend-specific `sha256(RunConfig)` and
  `playTranscriptHash` invariance under per-backend envelope changes for all five
  backend tags.
- Replacing logical envelope values with live backend envelope capture is explicitly owned
  by Sprints `3.6`, `4.2`, `5.5`, and `6.5`. The Phase `2` codec surface is closed on
  the envelope wire format and reader/writer behavior.

### Remaining Work

None.

## Sprint 2.7: Equity Sidecar Codec ✅

**Status**: Done
**Implementation**: `src/MCTS/Transcript/EquitySidecar.hs`, `src/MCTS/CLI/Inspect.hs`,
`test/unit/Main.hs`
**Docs to update**: `documents/engineering/transcript_format.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Implement the `.eq` / `.envelope` sidecar codec for the multi-backend
overlay (REPL) and the lazy-recompute cache. See
[../documents/engineering/transcript_format.md → Equity Sidecar
Cache](../documents/engineering/transcript_format.md) for the wire
format and the on-disk layout.

### Current Validation State

The closed baseline uses `src/MCTS/Transcript/EquitySidecar.hs` to write the binary
`MEQ1` `EqStream` beside a binary envelope neighbour, stored under
`.mcts-cache/transcripts/<host_arch>/<sha>/<backend>-<build_label>.{eq,envelope}`.
`mcts inspect show --with-equity` reads the matching originator sidecar before
materializing a recompute-backed sidecar on miss; Sprint `2.8` and Sprint `7.6`
correct the miss path so fallback recomputes cannot be labelled as originator
evidence. `mcts inspect cache list`
enumerates cached `(backend, build)` slots, and
`mcts inspect cache prune --keep-current` removes sidecars whose build label does
not match the current logical `logical` baseline. `mcts-unit` covers sidecar
encode/decode, listing, keep-current prune behavior, binary magic/terminator checks,
and `castWord64ToDouble` round-trips.

### Deliverables

- `src/MCTS/Transcript/EquitySidecar.hs` — `EqStream` ADT, encoder /
  decoder for the `.eq` file (header + per-move records + terminator),
  plus the `.envelope` neighbour file (the same envelope bytes
  extracted from the `.eq` header for easy `cat .envelope` access).
- `src/MCTS/Transcript/Cache.hs` extended: given a transcript hash and
  a `(backend, build_label)` pair, resolve the sidecar
  path; create the `<sha>/` directory lazily on first write; list
  cohabiting `(backend, build)` slots for the `mcts inspect cache
  list` subcommand.
- `src/MCTS/CLI/Inspect.hs` — `mcts inspect cache list` and
  `mcts inspect cache prune [--keep-current]`. `cache list` enumerates
  every `(backend, build)` slot per transcript via the helper above.
  `cache prune` walks the cache and deletes sidecars selected by the plan. The
  current Phase `2` baseline treats the `logical` build label as current for
  logical sidecar slots; live-envelope pruning against backend `get_envelope` FFI structs is
  owned by Sprints `3.6`, `4.2`, `5.5`, `6.5`, and `7.5`.
- Originator-vs-foreign discrimination: the codec exposes a helper
  `isOriginator :: TranscriptHeader -> EqSidecar -> Bool` that
  compares the `.eq`'s embedded `backend` against the transcript's
  recorded `backend` field. The REPL uses this to mark the originator
  column with ★.
- Atomic-write target contract: the final `.eq` writer should mirror the
  transcript writer from Sprint 2.1 by publishing from a same-directory temp file
  with file and directory fsync coverage before/around rename.
- `inspect cache list` and `inspect cache prune` `CommandSpec` entries
  carry at least one `Example` each and honour the standard
  `--format json|table|plain` and color flags per
  [../HASKELL_CLI_TOOL.md → Command Topology](../HASKELL_CLI_TOOL.md),
  [../HASKELL_CLI_TOOL.md → Automatically Generated Documentation](../HASKELL_CLI_TOOL.md),
  and [../HASKELL_CLI_TOOL.md → Output Rules](../HASKELL_CLI_TOOL.md).
  The `cache prune` runner is `Plan / Apply`-shaped per
  [../HASKELL_CLI_TOOL.md → Plan / Apply](../HASKELL_CLI_TOOL.md): the
  planner produces the set of sidecars to delete (and the skipped-
  backend warnings), and `apply` performs the deletions.

### Validation

- `mcts-unit`: `.eq` round-trip property (arbitrary `EqStream`
  encodes and decodes to itself); originator-vs-foreign discrimination
  unit test; cache-key prefix derivation collision-tolerance test
  over a 100-build synthetic corpus.
- `mcts-integration`: write a `.tr` with a known originator, write a
  `.eq` for that originator, write a second `.eq` for a foreign
  backend, list the sidecar directory, assert both slots are
  enumerated with correct origin markers.

### Closure Notes

- Baseline landed: `MCTS.Transcript.EquitySidecar` now encodes the `.eq`
  sidecar as a fixed-width little-endian binary stream (`MEQ1` magic + u16
  version + backend u8 + length-prefixed `transcript_hash` and `build_id`
  + u32 record count + 15-byte records of `(game_id u32, move_index u16,
  chosen u8, equity f64)` + `0xFFFFFFFF` terminator). The `.envelope`
  neighbour file is now the same binary blob produced by
  `MCTS.Transcript.encodeEnvelope`, so `cat .envelope` over a sidecar
  matches the originator transcript's envelope block byte-for-byte. The writer
  now uses the same crash-safe publication shape as transcript writes:
  same-directory temp files via `openBinaryTempFile`, `hFlush`, file
  `fileSynchronise`, atomic `renameFile`, and best-effort parent-directory fsync.
  The
  `mcts-unit` stanza now asserts the leading magic is `MEQ1`, the trailing
  terminator is `0xFFFFFFFF`, that round-tripping arbitrary equity values
  preserves them through `castWord64ToDouble`, and that a corrupted magic
  triggers a decode failure.
- `MCTS.Transcript.EquitySidecar` exposes `isOriginator` and
  `sidecarIsOriginator`, and `mcts inspect cache list` renders an originator /
  foreign / unknown marker for each cached sidecar. `mcts-integration` covers one
  transcript with both originator and foreign backend slots cohabiting in the same sidecar
  directory.
- `mcts inspect cache prune` is Plan/Apply-shaped: `--dry-run` renders the deletion plan,
  `--plan-file` writes it, and apply deletes `.eq` plus `.envelope` neighbours.
- Logical `logical` build-label stale detection remains the Phase `2` baseline. Live
  `mcts_<backend>_get_envelope()` matching is owned by Sprints `3.6`, `4.2`, `5.5`,
  `6.5`, and `7.5`.
- `MCTS.Transcript.EquitySidecar.loadMatchingOriginatorSidecar` now filters
  sidecars by transcript hash, origin backend, build label, and exact neighbouring
  `.envelope` bytes before decoding the `.eq` stream. `mcts-unit` covers the
  cache-hit path and the full-envelope `inspect show` rendering branch.

### Remaining Work

None.

## Sprint 2.8: Transcript and Sidecar Evidence Contract Realignment ✅

**Status**: Done
**Implementation**: `src/MCTS/Transcript.hs`, `src/MCTS/Transcript/Action.hs`,
`src/MCTS/Transcript/EquitySidecar.hs`, `src/MCTS/Engine/Envelope.hs`,
`test/unit`
**Docs to update**: `documents/engineering/transcript_format.md`,
`documents/engineering/determinism_contract.md`,
`documents/engineering/cli_command_surface.md`, `DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Protect the evidence surface by making the wire-format and sidecar identity rules
strict, current, and impossible to mislabel.

### Deliverables

- The v1 transcript decoder treats unsupported transcript or envelope versions as
  `AppError TranscriptFormatUnsupported`. The current v1 reader validates
  `envelope_offset == 48` instead of implying support for arbitrary future header
  growth. Additive envelope trailing bytes are tolerated only where unit tests prove the
  reader can skip them without interpreting unknown fields.
- The action-domain docs match the implemented `Action` model: legal actions are
  `0..208`; `209..254` are reserved; `255` is a sentinel/invalid byte in terminator
  contexts and is not admitted as an `Action`.
- Logical sidecar cache names are exactly `<backend>-logical.{eq,envelope}`. Internal
  build labels must not double-prefix the backend, and `isCurrentSidecar` /
  pruning logic must use the same build-label contract as the docs.
- Originator sidecar identity is backend/build/envelope exact. A recompute performed by
  another backend or by a logical fallback must be labelled as a foreign view or
  unavailable, never as the originator stream.
- `documents/engineering/transcript_format.md` owns the final byte layout and cache
  naming language; `documents/engineering/determinism_contract.md` owns the
  same-substrate vs foreign-view replay-equity semantics.

### Validation

- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

- Closed on 2026-05-21 after `docker compose run --rm mcts mcts test mcts-unit`,
  `docker compose run --rm mcts mcts docs check`,
  `docker compose run --rm mcts mcts check-code`, and `git diff --check` passed.
- Sprint `7.6` retains the CLI replay/divergence evidence-label validation on top of
  this corrected transcript/sidecar identity contract.

## Sprint 2.9: Transcript and Envelope Doctrine Realignment ✅

**Status**: Done
**Implementation**: `src/MCTS/Types.hs`, `src/MCTS/Verify/Envelope.hs`,
`test/unit/Main.hs`
**Docs to update**: `documents/engineering/transcript_format.md`,
`documents/engineering/determinism_contract.md`,
`documents/engineering/cli_command_surface.md`,
`documents/engineering/unit_testing_policy.md`, `DEVELOPMENT_PLAN/README.md`,
`DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Objective

Make the transcript envelope documentation, verifier gates, and cache identity
language match the implemented v1 codec and the current verification goal.

### Deliverables

- The v1 envelope wire docs pin the fixed 63-byte `compiler_version` and `libm_id`
  slots, their length bytes, field offsets, and the 282-byte fixed envelope block.
- Backend-slot stale checks compare only fields that can affect substrate behavior:
  `backend`, `engine_build_id`, `compiler_id`, `compiler_version`, `fp_flags`,
  `libm_id`, `cpu_features`, and `fp_env`.
- `engine_git_commit` and the display/cache `build_id` accessor are provenance only;
  unit coverage proves changing only those fields does not fail stale-envelope checks.
- Determinism docs describe canonical visit-payload comparison, chosen-action equity
  streams, and the current `equity_l2_drift` metric without claiming unavailable
  per-action equity-vector proof.

### Validation

- `docker compose run --rm mcts mcts test mcts-unit`
- `docker compose run --rm mcts mcts docs check`
- `docker compose run --rm mcts mcts check-code`
- `git diff --check`

### Remaining Work

None.

### Closure Notes

Closed on 2026-05-24 after the envelope gate, wire-format docs, and unit coverage
were brought back into agreement.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/transcript_format.md` — fill in the wire format (including
  the engine-envelope block placed at `envelope_offset` and excluded from the
  backend-specific `sha256(RunConfig)` cache key), the single-byte action enumeration,
  the content-addressing scheme, the cache root resolution including the per-transcript
  sidecar directory layout, the equity sidecar `.eq` / `.envelope` wire format, and the
  git-style hash-prefix lookup contract.
- `documents/engineering/determinism_contract.md` — fill in the full determinism
  contract per the README. The eleven owned sections are: the `--rng native` vs
  `--rng cpp` split (and the verify-subtree pin); the per-game
  `splitmix64(master_seed, game_index)` derivation; same-backend determinism
  (Q4); cross-backend determinism (Q3) under `--rng cpp` with the `VerifyBackend`
  GADT excluding `cpp-legacy`; the ply-cap draw rule and `max_plies`
  contract; the legacy parity envelope (`max_plies = MAX_ROLLOUT_ITERS = 10000`,
  fixture seed `S_LP = 42`, `AppError LegacyParityRolloutOverflow`); the
  visit-count vs equity asymmetry and the cross-backend equity tolerance
  implicit through search-choice drift; the byte-consumption contract (same
  `u64`s per rollout, Haskell signed-`Int` modulo legal-move selection, no
  rejection sampling unless identical); the backprop traversal contract (same
  path order, same logical step for visit-count and value-sum updates); the
  move-shape and tie-breaking contract (adjacent unoccupied pawn moves only,
  no jump moves, no overlapping/crossing walls, first 12 canonical wall moves,
  UCT score ties by action ID, final root choice by visit count then action
  ID); the verify mismatch output protocol (digest-equality first, then
  move-by-move scan emitting `AppError VerifyMismatch` with `(left_backend,
  right_backend, game_id, move_index, left_record, right_record)`); tree
  persistence and memory-resident-only trees; and the threading model
  (single-threaded per game, MT pool dispatches independent games).
- `documents/engineering/cli_command_surface.md` — extend the command matrix with
  the `mcts inspect list` and `mcts inspect show` surfaces, and document the
  `--rng`, `--cache-dir`, `--top`, `--with-equity`, `--format`, `--color`,
  `--no-color` flags. Sprint `2.8` and Sprint `7.6` keep `inspect show
  --with-equity` originator/foreign-view language synchronized with the corrected
  sidecar identity contract.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- `system-components.md` Transcript Codec rows reflect the current `✅ Done`
  transcript/cache/envelope baseline.
- `legacy-tracking-for-deletion.md` carries Sprint `2.8` transcript/sidecar doctrine
  residue until the strict v1 and sidecar-identity work closes.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md)
- [phase-3-haskell-engine.md](phase-3-haskell-engine.md)
- [phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
