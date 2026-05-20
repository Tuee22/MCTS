# Determinism Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/00-overview.md, ../../DEVELOPMENT_PLAN/phase-2-transcript-codec-and-determinism.md, ../../DEVELOPMENT_PLAN/phase-3-haskell-engine.md, ../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md, ../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md, ../documentation_standards.md, ./README.md, ./transcript_format.md, ./backend_ffi_contract.md, ./unit_testing_policy.md
**Generated sections**: none

> **Purpose**: Authoritative spec of the MCTS determinism contract — the RNG source
> split, the per-game seed derivation, the ply-cap draw rule, the visit-count vs
> equity asymmetry, the cross-backend verification cohort, and the retired legacy
> parity envelope.

This document owns its content. There is no doctrine overlap; the determinism
contract is project-specific.

## Validation Data Policy

Determinism validation must not require generated data checked into git. Normal
`mcts test all` and focused stanzas generate transcripts, report-card payloads,
schemas, and legacy-envelope samples in memory or under temporary roots during
the test run. Runtime transcript caches remain ignored local state, and optional
retired-backend audit artifacts live in explicit external/ignored roots.

Historical Q6/Q7 evidence remains documented here and in the development plan,
but it is not a clean-clone test input. The live round-robin comparison is
`mcts-cross-backend` over the surviving `(rust, haskell)` cohort under
`--rng cpp`.

## RNG Source Split

Two RNG sources are supported, exposed on the CLI as `--rng native|cpp`:

### `--rng native`

The current live search path uses the splitmix-compatible seed schedule everywhere
and distinguishes benchmark streams with `MCTS.Rng.Mix.backendNativeSalt`.

- Backend (i) `cpp-legacy` always used `std::mt19937_64` (verbatim from the
  legacy); it has no separate native/cpp axis and is now retired from live CLI
  selection.
- Backend (ii) carried xoshiro256++ helper code in the engine tree before
  retirement; its final native schedule is recorded as Sprint 8.5 historical
  evidence.
- Backend (iii) carried xoshiro256++ helper code in the engine tree before
  retirement; its final native schedule is recorded as Sprint 8.6 historical
  evidence.
- Backend (iv) Rust carries an `Xoshiro256PlusPlus` helper module, but the live
  search kernel also consumes the splitmix-compatible schedule.
- Backend (v) Haskell consumes the same splitmix-compatible schedule.

Used for benchmarks and any workload where backend-distinct streams are useful.
Cross-backend bit equality is **not** asserted under `--rng native`.

#### Per-Backend Native RNG Table

Current live choices. Profiling-driven swaps are allowed; the swap commit must
update this table in the same change.

| Backend | Native RNG (pinned) | Library / source | Owning Sprint |
|---------|---------------------|------------------|---------------|
| (i) `cpp-legacy` | `std::mt19937_64` (immutable — verbatim legacy) | `<random>` | Phase 4 Sprint 4.1 |
| (ii) `cpp-imperative` | splitmix-compatible schedule with backend salt (retired) | `cpp-imperative/engine/search.cpp`, historical Sprint 8.5 evidence | Phase 5 Sprint 5.1, Phase 7 Sprint 7.2, Phase 8 Sprint 8.5 |
| (iii) `cpp-functional` | splitmix-compatible schedule with backend salt (retired) | `cpp-functional/engine/search.cpp`, historical Sprint 8.6 evidence | Phase 6 Sprint 6.1, Phase 7 Sprint 7.2, Phase 8 Sprint 8.6 |
| (iv) `rust` | splitmix-compatible schedule with backend salt | `rust/src/search.rs`, `MCTS.Rng.Mix.backendNativeSalt` | Phase 6 Sprint 6.3, Phase 7 Sprint 7.2 |
| (v) `haskell` | splitmix-compatible schedule with backend salt | `MCTS.Search.UCT`, `MCTS.Rng.Mix.backendNativeSalt` | Phase 2 Sprint 2.5, Phase 7 Sprint 7.2 |

`xoshiro256++`, `wyrand`, and `SmallRng` remain valid future profiling
alternatives for the non-legacy live backends. Retired C++ schedules are frozen
as historical evidence.

### `--rng cpp`

Every participating backend uses the canonical no-backend-salt seed schedule.
The Phase 4 C ABI exposes `cpp_rng_split_seed(master_seed, game_index)`, and the
unit fixture checks that it agrees with `MCTS.Rng.Mix.mix`; the live verify
cohort relies on that shared seed schedule rather than a per-backend native salt.

Used for correctness validation. Under `--rng cpp`, the current live cohort
(iv), (v) must produce identical visit counts, identical action orderings,
and identical rollout sequences for the same seed and move history. Backend (i)
is excluded from the default `verify` cohort because its terminal-state semantics
differ from the steelman cohort (see [Ply-Cap Draw Rule](#ply-cap-draw-rule)
below). Backend (ii) is excluded because it retired in Sprint 8.5 and is now
represented by recorded historical evidence. Backend (iii) is excluded because
it retired in Sprint 8.6 and is now represented by recorded historical evidence.
The former live `mcts verify legacy-parity` gate retired with backend (i) in
Sprint 8.4; Q7 now reads historical backend (i) liveness evidence.

### Flag Default on `verify`

The `mcts verify` subtree pins `RngSource = CppRng` at parse time. The
`VerifyOptions` record has no `verifyRng` field. The native RNG cannot validate
cross-backend bit equality, so attempting `--rng native` on `verify` is rejected
at parse time.

## Per-Game Seed Derivation

Per-game RNG streams derive from:

```haskell
-- Example: per-game seed mix
mix :: Word64 -> Word64 -> Word64
mix masterSeed gameIndex = splitmix64 masterSeed gameIndex
```

`splitmix64` is the canonical mixer from the Java SplittableRandom paper. The mix
is bijective in `gameIndex` for any fixed `masterSeed`, so distinct
`(masterSeed, gameIndex)` pairs always produce distinct per-game seeds.

The `gameIndex` argument is `Word64` to match the C ABI `cpp_rng_split(uint64_t
master_seed, uint64_t game_index)` exposed by Phase 4 Sprint 4.3 (see
[backend_ffi_contract.md → `--rng cpp` Plumbing](./backend_ffi_contract.md)); the
wire-format game discriminator `runConfigGameIndex :: Word32` (see
[transcript_format.md → Content Addressing](./transcript_format.md)) is widened
to `Word64` with `fromIntegral` at the splitmix and FFI call sites. The widening
is zero-extension — `fromIntegral :: Word32 -> Word64` in GHC zeroes the high
32 bits — so the C-side `splitmix64(master_seed, game_index)` receives a
`uint64_t` whose upper half is always zero, and the byte-for-byte agreement
between the Haskell `mix :: Word64 -> Word64 -> Word64` and `cpp_rng_split`
holds trivially for every wire-format-representable `game_index`. The wire
width is fixed by the README's `game_id u32` (see
[../../README.md → Cross-backend verification](../../README.md)); no benchmark
or verify cohort exceeds 2^32 games, so the truncation never matters in
practice.

The retired legacy C++ RNG ABI also exposes
`cpp_rng_split_seed(master_seed, game_index)` so the seed derivation can be
tested directly without consuming a `std::mt19937_64` stream. The Haskell live
fixture loader retired with backend (i); the no-salt live verification schedule
now relies on `MCTS.Rng.Mix.mix`.

This makes per-game output independent of:

- The number of workers.
- The order in which games are scheduled.
- The worker-to-game assignment.

Concretely, running `mcts bench selfplay --games 32 --threading single --seed 42`
and `mcts bench selfplay --games 32 --threading multi --workers 8 --seed 42`
produces **identical** 32-transcript sets; only the wall-clock differs.

Per
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item 4](../../DEVELOPMENT_PLAN/00-overview.md).

## Same-Backend Determinism (Q4)

Required unconditionally for every backend. Same backend, same master seed, same
RNG source, same logical game inputs → same set of game determinism payloads. The
`mcts-integration` Cabal stanza asserts this at three pinned seeds per backend per
[unit_testing_policy.md → Test Stanzas](./unit_testing_policy.md#test-stanzas).

## Cross-Backend Determinism (Q3)

Under `--rng cpp`, the verification cohort for backend slots (iv),
(v) must produce identical visit counts and chosen moves for the same
seed and move history. The `mcts-cross-backend` stanza asserts this via the
`mcts verify rollouts` and `mcts verify selfplay` round-robin commands at the
report-card knob `G_V = 4` games and `S_VERIFY = 500` sims per move. Those
commands dispatch through `runBatchDispatch`, so they use live foreign shared
libraries when present and the in-process fallback only when the cdylib is
absent. Foreign batch search currently has a fixed 60-ply search horizon;
`runBatchDispatch` therefore uses live foreign search only when the requested
`max_plies >= 60`, and uses the in-process fallback for lower caps until the
C/Rust ABI grows an explicit per-run search-cap argument.

The `VerifyBackend` GADT excludes retired backends at the type level:

```haskell
-- Example: VerifyBackend GADT (excludes cpp-legacy and cpp-imperative)
data VerifyBackend
  = VRust
  | VHaskell
  deriving stock (Show, Eq)
```

A cohort of one fails parse-time with `AppError VerifyCohortTooSmall`. Any pair
mismatch fails with `AppError VerifyMismatch` carrying
`(left_backend, right_backend, game_id, move_index, left_record, right_record)`
per [Verify Mismatch Output](#verify-mismatch-output) below.
The `mcts-cross-backend` Cabal stanza asserts successful focused rollout and
self-play cohorts; a `VerifyMismatch` is a failing outcome for Q3. The retired
`mcts-legacy-parity` stanza used the same dispatch and envelope-checking path
as a Q7 liveness/overflow gate rather than comparing backend (i)'s visit vectors
or chosen moves against the steelman engines.

## Ply-Cap Draw Rule

The game's terminal-state semantics differ between backend (i) and backends
(ii)–(v). This is the only intentional behavioural divergence in the project.

### Backend (i)

`is_terminal()` ↔ `hero_wins() || villain_wins()` (verbatim from
`MCTS_legacy/backend/core/board.cpp:247`). A game has no draw outcome; rollouts
that exceed `MAX_ROLLOUT_ITERS = 10000` plies abort the search via an exception
(the legacy's behaviour). Backend (i) is excluded from cross-backend `verify`
cohorts.

### Backends (ii)–(v)

`is_terminal()` ↔ `hero_wins() || villain_wins() || ply_count >= max_plies`. The
board state carries a `Word16` ply counter. When termination is by ply cap,
`get_terminal_eval()` returns `0.0` (draw); rollouts back this value up like any
other terminal.

### `max_plies`

Run-configuration parameter, default `200`, exposed on the CLI as
`--max-plies N`. Pinned in the transcript header (`max_plies u16`). Part of the
determinism contract: two live verifier backends with the same `max_plies`, same seed,
and same chosen sequence must produce identical determinism payloads.

UCT search uses a deterministic search horizon of `min 60 max_plies` for leaf
rollouts and tree terminal checks. The game transcript still records and obeys
the run-level `max_plies`; the 60-ply limit is a search-budget horizon, not a
replacement for the game draw rule. The current foreign C ABI bakes that search
horizon into the compiled engine, which is why sub-60 batch runs fall back to the
in-process path as described in [Cross-Backend Determinism](#cross-backend-determinism-q3).

### `winner` Enum

The transcript wire format's `winner u8` field is a 3-value enum:
`0 = hero`, `1 = villain`, `2 = draw`. The decoder reports draws in
`mcts inspect show` and `mcts inspect replay` as `<draw>` in the same position
move notation otherwise occupies.

## Legacy Parity Envelope

Setting `max_plies = MAX_ROLLOUT_ITERS = 10000` creates the legacy parity
envelope: backend (i) can be driven at its native no-draw horizon while
backends (ii)–(v) retain a transcript-visible cap. The envelope is required for
Q6 legacy compatibility evidence and, historically, for Q7's five-backend
liveness/overflow gate. It is not a claim that backend (i)'s legacy tree search chooses the same
root action or produces the same visit distribution as the steelman engines.

Before Sprint 8.4, `mcts verify legacy-parity` drove this cohort with
`max_plies` and `--rng cpp` pinned. The fixture seed `S_LP = 42` was chosen so
that (i) never tripped `MAX_ROLLOUT_ITERS`. Sprint 8.4 retired the live
subcommand and the `LegacyParityBackend` parser surface. The frozen evidence now
lives as documented historical evidence or optional external/ignored audit
artifacts.

This complements Q6 (does (i) reproduce `MCTS_legacy`?): Q7 asks whether the
retired backend (i) evidence preserves the final no-overflow legacy-envelope
measurement. Q3 supplies the live-cohort visit-vector equality proof, and Q6
supplies historical byte-for-byte legacy evidence for backend (i) plus
temp-generated envelope assertions in normal tests.

## Visit-Count vs Equity Asymmetry

Cross-backend determinism is enforced on visit counts only, not on equity.

### Visit Counts

Integer, order-independent under summation. The live verify cohort under `--rng cpp`
produce identical visit counts byte-for-byte. Visit counts are what `mcts verify`
compares.

### Equity

Derived float. Float accumulation order can differ subtly between GCC, `rustc`,
and GHC-via-LLVM even under `-fno-fast-math`; x87 80-bit intermediates can leak
through libm calls; SIMD reductions can reassociate. Equity values produced by
different backends typically agree to many digits but can differ at the last few
ULPs.

The wire format **excludes** equity. Visit counts (integer) form the Q3
determinism contract for the live verify cohort; equities (float) are not, and requiring
float bit-equality would force every backend to fix a canonical summation order
and a canonical libm — a much bigger contract.

### Cross-Backend Equity Tolerance

Implicit for Q3. The `verify rollouts` and `verify selfplay` subcommands do not
compare equities directly. The contract is that float differences across
the live verify cohort must never be large enough to change the UCT child selected
during search or the final highest-visit root action. This is enforced
transitively: any equity drift that changes a chosen action surfaces as a
visit-count mismatch on the next move, and visit counts are what Q3 `verify`
compares. Backends that drift further than this implicit tolerance fail verify
on visits, not on equities. Q7 legacy parity is outside this equity-tolerance
contract because it is a liveness/overflow gate for backend (i)'s legacy
envelope.

### Equity Recomputation on Replay

`mcts inspect replay` loads cached `.eq` overlays and, when the originator overlay
is missing, recomputes the originator `EqStream` before the TUI starts. The visit
counts and chosen actions produced must equal the transcript records byte-for-byte
under `--rng cpp` before the sidecar is written. Equity is read from the recompute
result, not from the transcript wire format. The stored visits serve as a per-move
determinism check that the re-run stayed on the deterministic path — not as input to
the equity calculation.

### Replay Equity Guarantees

The replay equity guarantee is asymmetric between same-backend and cross-backend.
The contract below is lifted verbatim from
[../../README.md → Cross-backend verification → Replay equity guarantees](../../README.md).

**Same backend that wrote the transcript (same compiled binary, same hardware).**
Equities are **bit-identical** to those the original search computed. The chain
of guarantees is:

1. The seed fixes the RNG state.
2. The deterministic engine plus the byte-consumption contract fixes the
   simulation order.
3. Identical simulation order produces identical value backups in identical
   float-accumulation order.
4. Identical float arithmetic on identical hardware produces identical bits.

Tree persistence carries this property across moves because the inherited tree
at move M is itself a deterministic function of moves 0..M-1.

**Different backend.** Equities are **not** bit-equal. Float accumulation order
can differ subtly between GCC, `rustc`, and GHC-via-LLVM even under
`-fno-fast-math`; x87 80-bit intermediates can leak through libm calls; SIMD
reductions can reassociate. Equity values typically agree to many digits but can
differ at the last few ULPs. This asymmetry is why the wire format excludes
equity: requiring float bit-equality would force every backend to fix a
canonical summation order and a canonical libm — a much bigger contract.

The cross-backend tolerance for equity drift is itself implicit for Q3: any
drift large enough to change UCT child selection or the final root action
surfaces as a visit-count mismatch on the next move, and visit counts are what
Q3 `verify` compares (see
[Cross-Backend Equity Tolerance](#cross-backend-equity-tolerance) above).

## Byte-Consumption Contract

Byte-consumption order is itself part of the determinism contract per
[../../README.md → Cross-backend verification → Byte-consumption order as
contract](../../README.md). Every backend must:

- Draw the **same number** of `u64` values from its RNG per rollout.
- Use Haskell's signed-machine-`Int` modulo semantics for legal-move selection:
  reinterpret the consumed `u64` as a signed 64-bit value, compute `draw % n`,
  and add `n` when the remainder is negative. No rejection sampling, unless
  every backend rejects identically (i.e., rejection is part of the contract).
- Consume RNG bits at the **same logical points** in the search: child
  expansion, rollout move selection, tie-break tiebreakers if any.

The `verify` test enforces this contract implicitly: a backend that drifts off
the byte-consumption contract fails on the first divergent rollout — its
visit-count stream diverges from the reference cohort and the pairwise
comparator surfaces the mismatch.

## Backprop Traversal Contract

Backprop traversal order is also part of the determinism contract per
[../../README.md → Cross-backend verification → Backprop traversal order as
contract](../../README.md). All backends must:

- Walk the path from the selected leaf to the root in the **same order**.
- Apply visit-count increments at the **same logical step**.
- Update value sums (the float that becomes equity) at the same logical step,
  in the same accumulation order within a single backend.

Equity is excluded from the wire format, but transient intermediate visit counts
at non-leaf nodes are observed by the comparator: they must agree.

## Move-Shape and Tie-Breaking Contract

The live verifier cohort uses a simplified Corridors move set:

- Pawn moves are one-square orthogonal moves to an adjacent unoccupied square.
  Quoridor-style jumps and diagonal jump fallbacks are not part of the search
  contract.
- Wall placements cannot overlap an existing same-orientation segment, extend
  a same-orientation wall into the same two-edge slot, cross the opposite
  orientation at the same midpoint, or block all paths for either player.
- Legal moves are sorted by canonical action ID. Search expands all legal pawn
  moves plus the first 12 legal wall moves after canonicalization.

UCT child selection uses the highest UCB score, treating unvisited children as
the largest score and breaking equal scores by canonical action ID. Final root
move selection uses highest visit count, with action ID as the stable tie-break.
There is no separate multi-threaded tie-breaker: within a single game (always
single-threaded internally) nothing has to be aggregated across threads, and
across games each game's RNG stream is its own independent universe.

### `non_terminal_rank` Operational Definition

`non_terminal_rank` is the legacy engine's per-child secondary sort key. The
imported source pins the definition in
`cpp-legacy/legacy-core/board.cpp:395`: `board::get_non_terminal_rank()` returns
`villains_shortest_distance - heros_shortest_distance`. The legacy callers use
that value in `cpp-legacy/legacy-core/mcts.hpp:258`-`266` for the domain-specific
non-terminal shortcut, and in `cpp-legacy/legacy-core/mcts.hpp:400`-`421` as the
secondary display/order key after equity.

Operationally, the legacy reference computes the shortest path length from each
pawn to its goal row under the current wall set, then ranks the child by:

```text
non_terminal_rank = villain_shortest_distance - hero_shortest_distance
```

The value remains exposed for legacy fixture inspection and standalone engine
coverage, but it is not a verifier-cohort tie-break in the current live
UCT search path.

## Verify Mismatch Output

When `mcts verify rollouts` or `mcts verify selfplay` finds a disagreement
between two backends in the Q3 cohort, the output protocol is two-phase per
[../../README.md → Cross-backend verification → Typical transcript sizes](../../README.md):

1. **Determinism-payload digest first.** Decode each backend-specific
   transcript file and compute the SHA-256 of a canonical byte projection over
   the common run inputs plus the decoded game payload described in
   [transcript_format.md → Content Addressing](./transcript_format.md). If two
   payload digests agree, the pair passes without a record scan.
2. **Length-aware scan on mismatch.** The decoder scans both transcripts
   move-by-move only for pairs whose payload digests differ. It stops at the
   first divergent surface:
   `AppError VerifyLengthMismatch` for extra or missing games/moves,
   `AppError VerifyTerminatorMismatch` for winner or total-move terminator
   disagreement, or `AppError VerifyMismatch` for the first divergent move
   record carrying `(left_backend, right_backend, game_id, move_index,
   left_record, right_record)`.

This is the contract the implementer in
[../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md → Sprint
7.2](../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md)
honours.

## Recompute Mismatch Output

`mcts inspect show` and `mcts inspect replay` populate other-backend columns
by asking the live binary to recompute visits from a recorded transcript
(see [cli_command_surface.md → Lazy Compute Trigger](./cli_command_surface.md)
and `src/MCTS/Engine/Recompute.hs`). Under `--rng cpp` the recompute hard-
asserts visit-agreement with the transcript's recorded visits at every
move. A mismatch indicates the live backend has become non-deterministic
against its own prior recording — a bug bell, not a routine outcome.

The renderer emits

    AppError RecomputeMismatch (backend, game_id, move_index,
                                recomputed_record, recorded_record)

where `backend` is the live backend doing the recompute, `recomputed_record`
is what the live binary produced at the first divergent move, and
`recorded_record` is what the on-disk transcript carries at the same move.
Both `Record` fields have the same shape as
`VerifyMismatch`'s `left_record` / `right_record`.

This error is distinct from `VerifyMismatch` (which is the *expected*
outcome cross-backend `mcts verify` exists to surface) because it indicates
a backend's own determinism has broken — different operational meaning,
different downstream handling, different telemetry. Phase 3 Sprint 3.3
(`src/MCTS/Engine/Recompute.hs`) owns the emission path.

## Tree Persistence

Visits persist across moves within a single game. When a move is played, the
chosen child becomes the new root and its accumulated visits are kept; the rest
of the tree is discarded incrementally. The next search starts warm. Tree
persistence is per-game; in multi-threaded batches multiple per-game trees live
concurrently in memory, each independent — there is never more than one thread
touching a given tree.

Trees are memory-resident only — nothing is serialised between runs. Tree state
is losslessly recoverable: Monte Carlo draws are seeded deterministically, so
any tree state is reproducible by replaying the seed and move sequence. This is
what justifies keeping the tree in memory only.

Incremental truncation of the discarded subtree is a memory-management lever,
not a correctness concern per
[../../README.md → Tree persistence and determinism](../../README.md): the shape
of the tree at any given moment is an optimisation; the visit counts it
represents are reproducible from the seed and move sequence regardless of when
or how aggressively the discarded subtree is freed.

## Monotonic Clock Contract

All cross-backend wall-clock comparisons in `mcts bench` and the report-card
workload share a single monotonic clock: `GHC.Clock.getMonotonicTimeNSec`
(nanosecond resolution). Per
[../../README.md → Benchmarks](../../README.md):

- The clock starts inside the Haskell driver **just before** the first game is
  dispatched into the worker pool.
- The clock stops **just after** the last game's transcript returns through
  the FFI (for the native Haskell backend, "returns from the in-process
  `runGame`" is equivalent).

This bracket excludes prerequisite checks, worker-pool setup, and the final
result-rendering pass. All five backends are timed by the same clock so
cross-backend numbers are directly comparable. The Phase 3 Sprint 3.5
integration test intercepts both bracket endpoints via a test-hook field on
`Env` and asserts the bracket wraps exactly the dispatch loop; subsequent
backends (Phases 4–6) inherit this discipline rather than introducing their
own clock.

## Threading

Each individual game is single-threaded internally — one tree, one search, one
rollout stream per game. The project never parallelises the search within a
single game per [../../README.md → Threading](../../README.md): this is a
non-negotiable architectural axis, not an implementation default. Multi-threading
is only ever about running independent games concurrently. The default
`MultiThreaded { workers = 8 }` dispatches a batch of games across 8 workers;
each worker plays one game at a time, single-threaded internally.

Per the per-game seed derivation, running 32 games on 1 worker and 32 games on 8
workers produces identical determinism payloads; only wall-clock and
provenance-bearing dispatcher metadata differ.

## Architecture Envelope

The project supports two host architectures: **amd64 Linux** and **arm64 Linux**
per [../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item
36](../../DEVELOPMENT_PLAN/00-overview.md). Reproducibility envelopes are
per-architecture, not cross-architecture:

- **Within a single architecture** (amd64-vs-amd64 or arm64-vs-arm64), every
  determinism guarantee in this document holds bit-for-bit: same-backend
  determinism, cross-backend visit equality, replay equity bit-equality, and the
  byte-consumption / backprop / tie-breaking contracts.
- **Across architectures** (amd64-vs-arm64), bit-equality is **not** part of the
  contract. The `c_param u64` IEEE-754 bit-cast is portable in shape (both arches
  are IEEE-754) but backend-internal floating-point arithmetic may differ at the
  ULP level due to FMA contraction differences, denormal handling, and library
  implementations (`libm`, `std::log`, `std::sqrt`). Cross-arch cohorts are
  rejected before comparison rather than treated as determinism evidence.

To make this safe, transcript headers and report-card metadata carry a
`host_arch` tag with allowed values `"amd64"` and `"arm64"` per
[transcript_format.md](./transcript_format.md). Cross-backend `verify` and
same-backend `verify` checks compare records only when the comparison set shares
a `host_arch`; mixed-arch comparisons fail with a typed `AppError
ArchEnvelopeMismatch` rather than spuriously reporting determinism drift.

The transcript cache root may be partitioned by `host_arch` (e.g.,
`./.mcts-cache/transcripts/amd64/<sha>.tr`) so that arm64 and amd64 caches do
not collide on shared filesystems; the precise layout is owned by Phase 2.

## Engine Envelope

The Architecture Envelope above pins reproducibility per-arch; the Engine
Envelope pins it per-*build*. Two `rust` or archived `cpp-functional` binaries
on the same amd64 host — one built before a substrate change, the other rebuilt
after a glibc or toolchain point upgrade — are not the same substrate even though they
share `backend`, `host_arch`, and `RunConfig`. The equity floats they
produce can disagree at the ULP level (different libm, different FMA
contraction decisions); their visit counts remain bit-equal. To detect
that condition reliably, every transcript carries an **engine envelope**
block immediately after the fixed header, recording every
substrate-affecting field at the time the engine ran. The envelope is
part of the transcript file but excluded from the cross-backend
determinism payload, so backend-specific cache filenames can preserve
provenance while `mcts verify` still compares the common visit-count
contract.

The envelope decomposes into two layers with very different invariance
semantics under `mcts verify`.

### Cohort-Invariant Fields

Must be identical across every transcript participating in a single
`mcts verify` cohort. A disagreement on any of these fields invalidates
the determinism contract for the cohort and `verify` hard-fails with
`AppError EngineEnvelopeMismatch CohortLevel field expected got`.

| Field | Width | Notes |
|-------|-------|-------|
| `host_arch` | u8 | Matches the existing header field. Cross-arch cohorts are already rejected by [Architecture Envelope](#architecture-envelope) above; recording it inside the envelope makes the cohort-uniformity check uniform. |
| `rng_source` | u8 | Matches the existing header field. `verify` pins this to `cpp` at parse time per [Flag Default on `verify`](#flag-default-on-verify); cohort-uniformity is therefore trivially satisfied unless a transcript was crafted out-of-band. |
| `shared_rng_build_id` | 32 bytes | Provenance for a physically shared RNG stream when one is used. The current no-shared-byte-stream baseline records all-zero for normal `--rng cpp` and `--rng native` transcripts; `--rng cpp` equality comes from the no-backend-salt splitmix-compatible schedule. Optional legacy-parity audit artifacts may pin this field to backend (i)'s engine build identity so stale provenance can still be detected. |
| `cohort_config_hash` | 32 bytes | SHA-256 of the backend-independent cohort config: common verify inputs excluding `backend`, the engine envelope, path, and cache metadata. Distinct from the backend-specific `sha256(RunConfig)` cache filename hash. |

### Per-Backend-Slot Fields

Differ across backends in a cohort *by design* — the whole point of
cross-backend `verify` is to compare bit-equality between different
binaries. These fields must match between a cached transcript and the
*live* binary for the same backend slot. Mismatch on that axis (the
stale-cache case) hard-fails with `AppError EngineEnvelopeMismatch
(BackendSlot b) field expected got`.

| Field | Width | Notes |
|-------|-------|-------|
| `engine_build_id` | 32 bytes | SHA-256 of the loaded backend shared library / executable. The identity of "this binary." |
| `engine_git_commit` | 40 ASCII bytes | Project repo commit SHA at build time. Informational; does **not** gate `verify`. |
| `compiler_id` | u8 | `0 = gcc`, `1 = clang`, `2 = rustc`, `3 = ghc`. |
| `compiler_version` | `u8` `compiler_version_len` (≤63) + ASCII bytes (no NUL terminator) | E.g., `"13.2.0"`. Wire layout: see [transcript_format.md → Envelope Block](./transcript_format.md). |
| `fp_flags` | u32 bitfield | One bit per FP-relevant compiler flag actually active at build time: `FP_FAST_MATH` (bit 0), `FP_FMA_ALLOWED` (bit 1), `FP_CONTRACT_ON` (bit 2), `FP_DENORMALS_ON` (bit 3), `FP_X87_USED` (bit 4). Remaining bits reserved, must be zero. The build harness derives these from the actual compiler invocation. |
| `libm_id` | `u8` `libm_id_len` (≤63) + ASCII bytes (no NUL terminator) | `"glibc-2.39"`, `"musl-1.2.5"`, `"rust-libm-0.2.7"`, or empty (length 0) for a backend whose engine hot path makes no libm transcendental calls. Wire layout: see [transcript_format.md → Envelope Block](./transcript_format.md). |
| `cpu_features` | u32 bitfield | CPU features the binary's runtime dispatch actually selected: `AVX2` (bit 0), `AVX512F` (bit 1), `BMI2` (bit 2), `FMA3` (bit 3), `NEON` (bit 4), `SVE` (bit 5). Remaining bits reserved. Captured at `new_engine` time via `__builtin_cpu_supports` (C++), `is_x86_feature_detected!` (Rust), or build-flag inspection (Haskell). |
| `fp_env` | u8 | FP environment at engine-run time: rounding mode (bits 0-1: `0=RNE`, `1=RZ`, `2=RD`, `3=RU`), FTZ (bit 2), DAZ (bit 3). `0` = IEEE defaults. |

### Wire Format

The envelope block lives immediately after the fixed header in the
transcript file, addressed by the new `envelope_offset u32` header
field. The block is versioned (`u16 envelope_version`) and length-
prefixed (`u32 envelope_byte_length`) so future versions add fields
additively and older readers tolerate trailing bytes they do not
recognise. See
[transcript_format.md → Envelope Block](./transcript_format.md) for the
authoritative byte layout.

### Hash Exclusion

`sha256(RunConfig)` is computed from the backend-specific `RunConfig` record
exclusively (see [transcript_format.md → Content
Addressing](./transcript_format.md)); the envelope's existence does not perturb
cache addressing. Because `RunConfig` includes the backend, workload, threading,
RNG source, master seed, sim budget, `max_plies`, `game_index`, and `c_param`
bits, different backend/game runs produce different provenance-bearing
`<sha>.tr` files while `runGames` stays outside the one-game cache key. `mcts
verify` compares a separate determinism-payload digest decoded from those files;
that payload excludes the backend and envelope so cross-backend visit-equality
remains the contract.

### Layered Verify Rule

`mcts verify` enforces both layers:

1. **Cohort-level**: every transcript in the cohort must agree on
   `host_arch`, `rng_source`, `cohort_config_hash`, and `shared_rng_build_id`.
2. **Per backend slot**: verify compares each transcript against the live
   envelope for that backend slot when the matching cdylib is present, and
   against the in-process fallback envelope when it is absent. FFI-produced
   transcripts are stamped with `mcts_<backend>_get_envelope()` when possible,
   and `checkTranscriptEnvelopesLive` exercises the stale-cache hard-fail /
   `--allow-stale` warning behavior.
3. **Cross-backend differences** in per-backend-slot fields are silent
   by design.

The new `--allow-stale` flag on `verify` downgrades per-backend-slot
mismatches to a warning (the user knows their build drifted and wants
to see whether visits survived anyway). Cohort-level mismatches remain
hard fails even under `--allow-stale` because they invalidate the cohort
seed/provenance contract. In `--format json`, downgraded backend-slot
`EngineEnvelopeMismatch` values are emitted under `warning_details` with the
scope, backend, field, expected value, actual value, and rendered message.

### Retired Legacy-Parity Special Case

Archived backend (i) transcripts may pin `shared_rng_build_id` to backend (i)'s
historical `engine_build_id` so the legacy audit provenance remains tied to
the retired `cpp-legacy` binary. Live verify no longer loads a `cpp-legacy`
binary for this comparison; archived envelopes are treated as self-contained
records.

### Multi-Backend Replay and the Equity Sidecar

The REPL's multi-backend overlay (`mcts inspect replay`) reads cached per-move
equity series and now fills a missing originator series before TUI startup. Each
series is cached in a sidecar `.eq` file keyed by
`(backend, build_label)`. Live envelopes use the first 16 hex characters of
`engine_build_id` for the build label; logical in-process envelopes with an
all-zero engine id use `<backend>-logical`. Multi-build cohabitation is
automatic — a rebuild lands in a fresh cache slot; the old slot remains for
forensic reference until pruned. The originator (the transcript's `backend`
field) is marked with a ★ in the REPL; its `.eq`, when keyed to the transcript's
originator build, carries the bit-equal originator equities. See
[transcript_format.md → Equity Sidecar Cache](./transcript_format.md)
for the on-disk layout and the `.eq` wire format, and
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item
38](../../DEVELOPMENT_PLAN/00-overview.md) for the constraint pin.

Current implementation baseline: `inspect show --with-equity` reads an
envelope-matched originator sidecar before recomputing and writing a replacement,
`inspect replay` fills a missing originator column
before TUI startup and uses `r` to recompute/write the next missing backend
column on demand, `inspect cache list` enumerates sidecar slots with originator /
foreign / unknown markers, and `inspect cache prune --keep-current` retains
`<backend>-logical` build ids through a Plan/Apply deletion plan. Live-envelope
stamping and verify-time comparison are implemented for present cdylibs.
`mcts-integration` also writes a recomputed `.eq` sidecar and consumes it through
the real `mcts inspect divergence` subprocess. Sprint `7.5` also publishes the
bounded report-card divergence matrix through `mcts test all`.

Baseline layered envelope verification exists in `MCTS.Verify.Envelope`: verify
cohorts check `host_arch`, envelope version, `rng_source`,
`shared_rng_build_id`, and `cohort_config_hash` at cohort level, compare each
transcript's backend-slot fields against either the live
`mcts_<backend>_get_envelope()` payload or the in-process fallback, and honor
`--allow-stale` only for backend-slot mismatches. The CLI parser stores default
verify cohorts as `[VerifyBackend]`, so retired backend exclusion is enforced
before dispatch. The retired legacy-parity parser surface is gone. The CLI JSON success renderer includes structured
`warning_details` for downgraded stale backend slots. The `mcts-integration`
stanza conditionally exercises real live-envelope stamping and backend-slot
stale hard-fail/`--allow-stale` warning behavior against each present foreign
cdylib.

## Divergence Smell

The determinism contract above is binary on the cohorts it governs
(same-backend same-envelope -> bit-equal; cross-backend `--rng cpp`
within the live cohort -> visit-equal). Outside those cohorts, two backends or
two builds may produce different visit counts and even occasionally
pick different moves. Some drift is expected from compiler / libm / FMA
differences; *high* drift is a smell — it suggests one of the
implementations is wrong, or that the byte-consumption contract is
being violated in a way verify's cohort failed to catch.

The Divergence Smell metric quantifies "how much" so the REPL and the
report card can surface it.

The retired legacy-parity Q7 command was an allowed liveness/overflow surface,
not a backend (i)-vs-steelman transcript comparison surface. On 2026-05-19 the
live investigation showed backend (i)'s legacy tree search can diverge from the
steelman engines at the report-card budget: visit-count comparison failed at
game 0, move 10 even when `cpp-legacy` and `cpp-imperative` chose the same move,
and chosen-move comparison failed at game 0, move 0. That divergence is expected
under the Q7 contract and is now preserved as retired-backend context rather
than an active Phase 7 blocker.

Current implementation baseline: `MCTS.Verify.Divergence.divergenceRate`
computes visit and chosen-move disagreement rates for two decoded transcripts,
and `MCTS.Verify.Divergence.divergenceVsEqStream` scores a transcript against a
cached or recomputed `EqStream`, including `equity_l2_drift`. `MCTS.ReportCard`
renders the two-backend report-card divergence matrix in both table and JSON
form from typed rows; `mcts test all` populates those rows from the measured
`G_V = 4` self-play verify cohort after the Plan/Apply subprocess sequence
succeeds. `mcts-integration` exercises the same measured builder at smoke scale
and validates cached recompute-sidecar consumption through `mcts inspect
divergence`. The 2026-05-19 canonical report-card run recorded a zero
`visit/move` divergence matrix across the then-live `(ii)..(v)` cohort under
`--rng cpp`; after Sprints 8.5 and 8.6 the same Q3 thresholds apply to the
surviving `(iv)..(v)` cohort.

### Metrics

For a pair `(backend_A, backend_B)` against the same transcript
(`backend_A` is the originator; `backend_B` is the recomputer):

- **`visit_disagreement_rate(A, B)`** = `count(visits_A[m,a] ≠
  visits_B[m,a])` / `count(all (m, a) pairs)`. Zero under `--rng cpp`
  within the live cohort by contract.
- **`move_disagreement_rate(A, B)`** = `count(argmax_action(visits_A[m,
  ·]) ≠ argmax_action(visits_B[m, ·]))` / `count(moves)`. Zero under
  `--rng cpp` within the live cohort by contract; small (<0.1%) expected under
  `--rng native` or cross-build comparisons.
- **`equity_l2_drift(A, B)`** = `‖equity_A − equity_B‖₂` over the
  per-move-per-action equity vectors, normalised by vector length.
  Always nonzero across backends (libm differences); meaningful when
  bounded against the threshold table below.

### Thresholds

| Comparison context | `visit_disagreement_rate` | `move_disagreement_rate` | Action on breach |
|--------------------|---------------------------|--------------------------|-----------------|
| Same backend, same envelope | 0 (contract) | 0 (contract) | Hard fail in `mcts-integration` Q4 |
| Cross-backend live cohort, `--rng cpp`, envelope-uniform cohort | 0 (contract) | 0 (contract) | Hard fail in `mcts-cross-backend` Q3 |
| Cross-backend live cohort, `--rng native` | ≤ 5% | ≤ 0.5% | Warn in report card if exceeded; not a test failure |
| Cross-build same backend | ≤ 1% | ≤ 0.1% | Warn in REPL; not a test failure |

The non-contract thresholds (the bottom two rows) are *empirically
pinnable* — they're placeholders for the numbers we expect to see;
the Phase 7 report-card workload pins them in `cabal.project`
(`MOVE_DELTA_NATIVE_MAX`, `VISIT_DELTA_NATIVE_MAX`, etc.) once we have
measurement runs to calibrate them.

### Surface

- **REPL** (`mcts inspect replay`): cached non-originator columns load at startup,
  and the `r` key recomputes/writes the next missing backend column on demand.
  The final divergence annotation (`move-Δ: x.x%  visit-Δ: y.y%` against the
  originator, colour-coded against thresholds) remains part of the Sprint 7.5
  divergence-matrix surface.
- **Report card** (`mcts test all`): the headline output includes a
  per-backend-pair divergence matrix. Under `--rng cpp` every
  off-diagonal element reads `0.0% / 0.0%`; anything else is a smell
  to investigate. The default renderer and JSON payload are checked by semantic
  unit assertions with a constructed zero matrix, while the live `mcts test all`
  report-card path derives its matrix from the measured `G_V` workload.
- **`mcts inspect divergence <hash>`**: emits the divergence matrix for
  a single transcript across all available cached backend columns.
  Forensic use only. Owned by
  [../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md
  → Sprint 7.5](../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md).

## Known Divergences

The project ships with a closed set of intentional divergences from
bit-for-bit determinism. The set is the authoritative reference: any new
divergence must land an entry here with its gating envelope, or the
divergence fails review. The Phase 7 cross-backend `verify` cohort and the
`mcts-cross-backend` Cabal stanza assume exactly the divergences listed
below.

| # | Backend(s) | Divergence | Reason | Gating envelope / scope |
|---|------------|------------|--------|--------------------------|
| 1 | (i) `cpp-legacy` vs steelman cohort | Terminal-state and search-kernel semantics: (i) has no game-level ply cap and retains the legacy search tree; steelman backends treat `ply_count >= max_plies` as a draw with eval `0.0` and use the steelman search contract | (i) is a verbatim port and inherits the legacy's behaviour; the ply-cap draw rule and steelman search shape are behavioural improvements adopted only by the steelman cohort | (i) is excluded from the default `verify` cohort by the `VerifyBackend` GADT and retired from live CLI selection. Historical Q7 evidence preserves the former `max_plies = MAX_ROLLOUT_ITERS = 10000` liveness/overflow result; backend (i) visit-count and chosen-move equality with the steelman cohort is not contractual. |
| 2 | (i) | RNG: always `std::mt19937_64`; no `--rng native` axis | Verbatim port of the legacy's RNG choice; the legacy ships only `std::mt19937_64` | Retired backend evidence and Q6 temp-generated envelope assertions only; live `mcts verify` cohorts under `--rng cpp` are unaffected |
| 3 | Live FFI engines under `--rng native` | RNG: backend-salted splitmix-compatible schedule rather than the no-salt verification schedule | Benchmark streams stay backend-distinct while preserving the current cross-language search-shape implementation. Faster per-language RNGs remain future profiling work. | Bench-only divergence: visit-count bit-equality is not asserted under `--rng native`; Q3 uses `--rng cpp` verification transcripts and Q7 uses historical backend (i) evidence |
| 4 | (i) under any `max_plies != MAX_ROLLOUT_ITERS` | Q1 / Q2 / Q5 throughput basis: (i)'s games run to a positional win and are on average longer than the ply-capped games of (ii)–(v) | (i) has no ply cap (#1), so games/sec for (i) is not on the same engine-budget basis as (ii)–(v) | Throughput **is published** with a `backendBasisFootnotes` warning per [unit_testing_policy.md → Backend (i) basis caveat](./unit_testing_policy.md) and [../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md → Sprint 7.3](../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md); the load-bearing Q1 / Q2 comparison is Haskell (v) vs C++ (ii). |
| 5 | All backends, amd64 ↔ arm64 | Full determinism evidence, especially equity float bits | `libm`, FMA, denormal handling, SIMD reduction, and runtime dispatch can differ across arches | Cross-arch cohorts are rejected by layered envelope verification with `AppError ArchEnvelopeMismatch`; per-arch cache partitioning makes accidental cross-arch comparison unlikely. No cross-arch bit-equality result is treated as contractual evidence. |
| 6 | Same backend across different build envelopes | Equity float bits and (under `--rng native`) potentially visit counts | A rebuild changes `engine_build_id`, often `libm_id`/`compiler_version`, and may change `fp_flags`/`cpu_features`. Equity drift is unavoidable; visit drift can occur if FP differences swap a tie-break upstream of a subsequent rollout under `--rng native` | `checkTranscriptEnvelopesLive` hard-fails with `AppError EngineEnvelopeMismatch (BackendSlot b)` unless `--allow-stale` is passed. `mcts inspect replay` shows a persistent yellow banner `envelope: BUILD MISMATCH - recomputed locally; equities may drift at ULP from origin`; multi-build sidecar cache (one `.eq` per `(backend, build_prefix16)`) lets the user compare across builds. Visit drift under cross-build `--rng cpp` is expected to be zero; stale backend-slot envelopes must be explicitly acknowledged with `--allow-stale` before visits are compared |

The set is closed in the literal sense: review rejects any PR that
introduces behaviour incompatible with the cohort assertions above unless
this table grows a new entry that names the new divergence, its reason,
and its gating envelope. The `mcts-cross-backend` stanza is the empirical check
for Q3 visit-vector equality, and documented historical evidence preserves Q7
legacy-envelope liveness/overflow results. Live FFI engines are used when
their cdylibs are present and the in-process fallback is used only when needed
for self-contained local validation.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [transcript_format.md](./transcript_format.md) — wire format and content
  addressing
- [backend_ffi_contract.md](./backend_ffi_contract.md) — `--rng cpp` plumbing
  across the FFI
- [compiler_runtime_tuning.md](./compiler_runtime_tuning.md) — RNG-choice
  asymmetry under `--rng native` for backend (ii)/(iii)
- [unit_testing_policy.md](./unit_testing_policy.md) — `mcts-cross-backend` and
  temp-generated legacy-envelope checks
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
