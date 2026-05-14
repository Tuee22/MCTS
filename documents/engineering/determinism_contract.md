# Determinism Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/00-overview.md, ../../DEVELOPMENT_PLAN/phase-2-transcript-codec-and-determinism.md, ../../DEVELOPMENT_PLAN/phase-3-haskell-engine.md, ../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md, ../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md, ../documentation_standards.md, ./README.md, ./transcript_format.md, ./backend_ffi_contract.md, ./unit_testing_policy.md
**Generated sections**: none

> **Purpose**: Authoritative spec of the MCTS determinism contract — the RNG source
> split, the per-game seed derivation, the ply-cap draw rule, the visit-count vs
> equity asymmetry, the cross-backend verification cohort, and the legacy parity
> envelope.

This document owns its content. There is no doctrine overlap; the determinism
contract is project-specific.

## RNG Source Split

Two RNG sources are supported, exposed on the CLI as `--rng native|cpp`:

### `--rng native`

Each backend uses the fastest RNG it can defend statistically.

- Backend (i) `cpp-legacy` always uses `std::mt19937_64` (verbatim from the
  legacy); it has no separate native/cpp axis. When (i) appears in a mixed cohort
  that passes `--rng native`, the flag is silently ignored for (i).
- Backend (ii) / (iii) may use `xoshiro256++` or `wyrand` instead of
  `std::mt19937_64` per
  [../../README.md → Compiler and runtime tuning item 16](../../README.md).
- Backend (iv) Rust uses `Xoshiro256PlusPlus` via the `rand_xoshiro`
  crate (see [Per-Backend Native RNG Table](#per-backend-native-rng-table)
  below for the pinned per-backend choices).
- Backend (v) Haskell uses `splitmix` or equivalent.

Used for benchmarks and any workload where raw throughput matters. Cross-backend
bit equality is **not** asserted under `--rng native`.

#### Per-Backend Native RNG Table

Pinned per-backend choices. Profiling-driven swaps are allowed; the swap commit
must update this table in the same change.

| Backend | Native RNG (pinned) | Library / source | Owning Sprint |
|---------|---------------------|------------------|---------------|
| (i) `cpp-legacy` | `std::mt19937_64` (immutable — verbatim legacy) | `<random>` | Phase 4 Sprint 4.1 |
| (ii) `cpp-imperative` | `xoshiro256++` | `xoshiro-cpp` header-only impl, or hand-rolled | Phase 5 Sprint 5.1 |
| (iii) `cpp-functional` | `xoshiro256++` (matches (ii) so the (ii)-vs-(iii) comparison isolates style) | same as (ii) | Phase 6 Sprint 6.1 |
| (iv) `rust` | `Xoshiro256PlusPlus` | `rand_xoshiro` crate | Phase 6 Sprint 6.3 |
| (v) `haskell` | `splitmix` (or equivalent statistically-defensible Haskell-native RNG) | `splitmix` Hackage library | Phase 2 Sprint 2.5 |

`wyrand` is the documented alternative for backends (ii)/(iii); `SmallRng` is
the documented fallback for backend (iv). Any swap must keep (ii) and (iii)
aligned with each other so the style-isolating discipline survives.

### `--rng cpp`

Every participating backend draws its random bytes from the same C++
`std::mt19937_64` generator (the one the legacy uses). Backends (ii) and (iii)
use it directly; (iv) Rust and (v) Haskell reach it through the FFI shared
generator owned by Phase 4 Sprint 4.3.

Used for correctness validation. Under `--rng cpp`, backends (ii), (iii), (iv),
(v) must produce identical visit counts, identical action orderings, and
identical rollout sequences for the same seed and move history. Backend (i) is
excluded from the default `verify` cohort because its terminal-state semantics
differ from (ii)–(v) (see [Ply-Cap Draw Rule](#ply-cap-draw-rule) below); it
rejoins the cohort under `mcts verify legacy-parity`, which pins
`max_plies = 10000` so the divergence collapses.

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
RNG source → same set of game transcripts. The `mcts-integration` Cabal stanza
asserts this at three pinned seeds per backend per
[unit_testing_policy.md → Test Stanzas](./unit_testing_policy.md#test-stanzas).

## Cross-Backend Determinism (Q3)

Under `--rng cpp`, backends (ii), (iii), (iv), (v) must produce identical visit
counts, identical action orderings, and identical rollout sequences for the same
seed and move history. The `mcts-cross-backend` stanza asserts this via the
`mcts verify rollouts` and `mcts verify selfplay` round-robin commands at the
report-card knob `G_V = 50` games and `S_VERIFY = 10_000` sims per move.

The `VerifyBackend` GADT excludes `cpp-legacy` at the type level:

```haskell
-- Example: VerifyBackend GADT (excludes cpp-legacy)
data VerifyBackend
  = VCppImperative
  | VCppFunctional
  | VRust
  | VHaskell
  deriving stock (Show, Eq)
```

A cohort of one fails parse-time with `AppError VerifyCohortTooSmall`. Any pair
mismatch fails with `AppError VerifyMismatch` carrying
`(left_backend, right_backend, game_id, move_index, left_record, right_record)`
per [Verify Mismatch Output](#verify-mismatch-output) below.

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
determinism contract: two backends (ii)–(v) with the same `max_plies`, same seed,
and same chosen sequence must produce identical transcripts.

### `winner` Enum

The transcript wire format's `winner u8` field is a 3-value enum:
`0 = hero`, `1 = villain`, `2 = draw`. The decoder reports draws in
`mcts inspect show` and `mcts inspect replay` as `<draw>` in the same position
move notation otherwise occupies.

## Legacy Parity Envelope

Setting `max_plies = MAX_ROLLOUT_ITERS = 10000` collapses the (i)-vs-(ii)–(v)
divergence: in this envelope all five backends terminate every rollout the same
way (on a positional win), so transcripts must be bit-equal.

`mcts verify legacy-parity` drives this cohort with `max_plies` and `--rng cpp`
pinned. The fixture seed `S_LP = 42` is chosen so that (i) never trips
`MAX_ROLLOUT_ITERS`. If a future change causes (i) to throw or reach
`MAX_ROLLOUT_ITERS`, the cohort fails with `AppError LegacyParityRolloutOverflow`
carrying `(seed, game_index, move_index)` so the seed can be replaced. The
test also fails if (i) survives but its longest rollout reaches the cap, since
that means the legacy is one change away from the cliff.

The `LegacyParityBackend` GADT requires `LpCppLegacy` at parse time:

```haskell
-- Example: LegacyParityBackend GADT (requires cpp-legacy at parse time)
data LegacyParityBackend
  = LpCppLegacy
  | LpCppImperative
  | LpCppFunctional
  | LpRust
  | LpHaskell
  deriving stock (Show, Eq)
```

Cohorts without `cpp-legacy` fail parse-time with `AppError VerifyCohortTooSmall`.

This complements Q6 (does (i) reproduce `MCTS_legacy`?): Q7 asks whether all five
backends agree within the envelope. Composed with Q6, they give a transitive
parity chain `MCTS_legacy ≡ (i) ≡ (ii)..(v)`.

## Visit-Count vs Equity Asymmetry

Cross-backend determinism is enforced on visit counts only, not on equity.

### Visit Counts

Integer, order-independent under summation. Backends (ii)–(v) under `--rng cpp`
produce identical visit counts byte-for-byte. Visit counts are what `mcts verify`
compares.

### Equity

Derived float. Float accumulation order can differ subtly between GCC, `rustc`,
and GHC-via-LLVM even under `-fno-fast-math`; x87 80-bit intermediates can leak
through libm calls; SIMD reductions can reassociate. Equity values produced by
different backends typically agree to many digits but can differ at the last few
ULPs.

The wire format **excludes** equity. Visit counts (integer) form the determinism
contract; equities (float) are not, and requiring float bit-equality would force
every backend to fix a canonical summation order and a canonical libm — a much
bigger contract.

### Cross-Backend Equity Tolerance

Implicit. The verify subcommands do not compare equities directly. The contract is
that equity differences across backends must never be large enough to swap a
tie-break in `(equity desc, non_terminal_rank asc)`. This is enforced
transitively: any equity drift that swaps a chosen action surfaces as a
visit-count mismatch on the next move (because subsequent searches diverge from
that point onward), and visit counts are what `verify` compares. Backends that
drift further than this implicit tolerance fail verify on visits, not on
equities.

### Equity Recomputation on Replay

`mcts inspect replay` recomputes equity on the fly by replaying the search from
move 0 with the persistent tree carried forward. The visit counts produced must
equal the transcript record byte-for-byte (built-in determinism check that fires
on every navigation). Equity is then read from the resulting in-memory tree's
value backups. The stored visits serve as a per-move determinism check that the
re-run stayed on the deterministic path — not as input to the equity
calculation.

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

The cross-backend tolerance for equity drift is itself implicit: any drift large
enough to swap a tie-break surfaces as a visit-count mismatch on the next move,
and visit counts are what `verify` compares (see
[Cross-Backend Equity Tolerance](#cross-backend-equity-tolerance) above).

## Byte-Consumption Contract

Byte-consumption order is itself part of the determinism contract per
[../../README.md → Cross-backend verification → Byte-consumption order as
contract](../../README.md). Every backend must:

- Draw the **same number** of `u64` values from its RNG per rollout.
- Use `draw % n` for legal-move selection. No rejection sampling, unless every
  backend rejects identically (i.e., rejection is part of the contract).
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

## Tie-Breaking Contract

Move selection follows the legacy's `(equity desc, non_terminal_rank asc)`
ordering, applied uniformly across all five backends per
[../../README.md → Cross-backend verification → Tie-breaking as
contract](../../README.md). There is no separate multi-threaded tie-breaker:
within a single game (always single-threaded internally) nothing has to be
aggregated across threads, and across games each game's RNG stream is an
independent universe.

### `non_terminal_rank` Operational Definition

`non_terminal_rank` is the legacy engine's per-child secondary sort key,
defined by `MCTS_legacy/backend/core/mcts.cpp` (the exact function and line
range are pinned by Phase 3 Sprint 3.3 by reading the legacy source —
provisionally `uct_node::best_move()` and its `non_terminal_rank` helper).
Operationally:

1. Among the legal children of a node, those whose subtree contains at least
   one non-terminal leaf are ranked **before** those whose subtree is fully
   terminal.
2. Within each of those two groups, the rank is the child's position in the
   board's canonical legal-move enumeration order (the same enumeration that
   feeds the single-byte action wire format in
   [transcript_format.md → Action Enumeration](./transcript_format.md#action-enumeration)).

The full sort key is `(equity desc, non_terminal_rank asc)`: equity (a `Float`)
descending as the primary key, `non_terminal_rank` (a `uint16_t`) ascending as
the deterministic tiebreaker. Because both keys are derived from the same
visit-and-value state across all five backends, and because the legal-move
enumeration order is fixed by the wire format, every backend produces the same
ordering for every node — modulo equity drift, which is bounded by the
[Cross-Backend Equity Tolerance](#cross-backend-equity-tolerance) above.

The Phase 3 Sprint 3.3 deliverable closes only when this subsection's legacy
citation is replaced with the precise function and line range from
`MCTS_legacy/backend/core/mcts.cpp`, and all five backends' tie-break
implementations cite the same definition.

## Verify Mismatch Output

When `mcts verify rollouts`, `mcts verify selfplay`, or `mcts verify
legacy-parity` finds a disagreement between two backends in the cohort, the
output protocol is two-phase per
[../../README.md → Cross-backend verification → Typical transcript sizes](../../README.md):

1. **Digest-equality first.** Compare the SHA-256 of the transcript files
   pairwise. If two digests differ, the pair has a mismatch.
2. **Move-by-move scan on mismatch.** The decoder scans both transcripts
   move-by-move and stops at the first divergent record. The renderer emits
   `AppError VerifyMismatch` carrying
   `(left_backend, right_backend, game_id, move_index, left_record,
   right_record)` so the failure points at the precise byte of disagreement.

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
workload share a single monotonic clock: `Data.Time.Clock.getMonotonicTimeNSec`
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
workers produces identical transcript sets; only wall-clock differs.

## Architecture Envelope

The project supports two host architectures: **amd64 Linux** and **arm64 Linux**
per [../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item
36](../../DEVELOPMENT_PLAN/00-overview.md). Reproducibility envelopes are
per-architecture, not cross-architecture:

- **Within a single architecture** (amd64-vs-amd64 or arm64-vs-arm64), every
  determinism guarantee in this document holds bit-for-bit: same-backend
  determinism, cross-backend visit equality, replay equity bit-equality, and the
  byte-consumption / backprop / tie-breaking contracts.
- **Across architectures** (amd64-vs-arm64), bit-equality is **not** guaranteed.
  The `c_param u64` IEEE-754 bit-cast is portable in shape (both arches are
  IEEE-754) but backend-internal floating-point arithmetic may differ at the ULP
  level due to FMA contraction differences, denormal handling, and library
  implementations (`libm`, `std::log`, `std::sqrt`). Visit-count integer paths
  are bit-equal across arches; equity floats are within ULPs but not bit-equal.

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
Envelope pins it per-*build*. Two `cpp-imperative` binaries on the same
amd64 host — one built with GCC 13.2 and glibc 2.39, the other rebuilt
after a glibc point upgrade — are not the same substrate even though they
share `backend`, `host_arch`, and `RunConfig`. The equity floats they
produce can disagree at the ULP level (different libm, different FMA
contraction decisions); their visit counts remain bit-equal. To detect
that condition reliably, every transcript carries an **engine envelope**
block immediately after the fixed header, recording every
substrate-affecting field at the time the engine ran. The envelope is
part of the transcript file but **excluded from the
`sha256(RunConfig)` content hash** so cross-backend visit-equality
continues to work unchanged: two backends running the same `RunConfig`
land at the same `<sha>.tr` filename even though their envelopes are
different.

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
| `shared_rng_build_id` | 32 bytes | SHA-256 of the loaded `cpp_rng.so` (the Phase 4 Sprint 4.3 FFI-exported `std::mt19937_64`). All backends in a `--rng cpp` cohort consume bytes from this same generator; two transcripts that recorded different `shared_rng_build_id` values consumed bytes from *physically different generators* and visit-equality between them is meaningless. Set to all-zero for `--rng native` transcripts. |
| `run_config_hash` | 32 bytes | `sha256(RunConfig)`. Redundant with the filename but recorded inline so `verify` can confirm cohort uniformity without filename gymnastics. |

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

`sha256(RunConfig)` is computed from the `RunConfig` record exclusively
(see [transcript_format.md → Content Addressing](./transcript_format.md));
the envelope's existence does not perturb cache addressing. Two backends
running the same `RunConfig` under `--rng cpp` therefore produce the
same `<sha>.tr` filename even though their envelopes are different —
exactly the property cross-backend visit-equality requires.

### Layered Verify Rule

`mcts verify` enforces both layers:

1. **Cohort-level**: every transcript in the cohort must agree on
   `host_arch`, `rng_source`, `run_config_hash`, and `shared_rng_build_id`.
2. **Per backend slot**: each cached transcript's per-backend-slot
   fields (`engine_build_id`, `compiler_id`, `compiler_version`,
   `fp_flags`, `libm_id`, `cpu_features`, `fp_env`) must match the live
   binary's fields for the same backend.
3. **Cross-backend differences** in per-backend-slot fields are silent
   by design.

The new `--allow-stale` flag on `verify` downgrades per-backend-slot
mismatches to a warning (the user knows their build drifted and wants
to see whether visits survived anyway). Cohort-level mismatches remain
hard fails even under `--allow-stale` because they invalidate the
shared-RNG contract.

### Legacy-Parity Special Case

Under `mcts verify legacy-parity`, `shared_rng_build_id` is pinned to
backend (i)'s `engine_build_id` — backend (i) *is* the canonical
`std::mt19937_64` owner under that envelope, so its build hash is the
shared-RNG identity. The cohort-uniformity check still applies; any
transcript in the cohort whose `shared_rng_build_id` disagrees with
the live `cpp-legacy` binary's `engine_build_id` fails with
`AppError EngineEnvelopeMismatch CohortLevel SharedRngBuildId
expected got`.

### Multi-Backend Replay and the Equity Sidecar

The REPL's multi-backend overlay (`mcts inspect replay`) recomputes the
per-move equity series for any backend on demand and caches the result
in a sidecar `.eq` file keyed by `(backend, engine_build_id_prefix16)`.
Multi-build cohabitation is automatic — a rebuild lands in a fresh
cache slot; the old slot remains for forensic reference until pruned.
The originator (the transcript's `backend` field) is marked with a ★
in the REPL; its `.eq`, when envelope-matched against the live
originator binary, carries the bit-equal originator equities. See
[transcript_format.md → Equity Sidecar Cache](./transcript_format.md)
for the on-disk layout and the `.eq` wire format, and
[../../DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item
38](../../DEVELOPMENT_PLAN/00-overview.md) for the constraint pin.

Current implementation baseline: `inspect show --with-equity` writes the
logical originator sidecar, `inspect cache list` enumerates sidecar slots, and
`inspect cache prune --keep-current` retains `<backend>-logical` build ids until
live backend envelopes are available through FFI. Foreign recompute sidecars and
originator markers remain Sprint `2.7` / `7.5` closure work.

Baseline layered envelope verification exists in `MCTS.Verify.Envelope`: verify cohorts
check `host_arch` and envelope version at cohort level, compare each transcript's
`backend` and logical `build_id` against its requested backend slot, and honor
`--allow-stale` only for backend-slot mismatches. The full per-backend substrate fields
remain tied to the real FFI envelope capture work.

## Divergence Smell

The determinism contract above is binary on the cohorts it governs
(same-backend same-envelope → bit-equal; cross-backend `--rng cpp`
within (ii)–(v) → visit-equal). Outside those cohorts, two backends or
two builds may produce different visit counts and even occasionally
pick different moves. Some drift is expected from compiler / libm / FMA
differences; *high* drift is a smell — it suggests one of the
implementations is wrong, or that the byte-consumption contract is
being violated in a way verify's cohort failed to catch.

The Divergence Smell metric quantifies "how much" so the REPL and the
report card can surface it.

Current implementation baseline: `MCTS.Verify.Divergence.divergenceRate`
computes the visit and chosen-move disagreement rates for two decoded
transcripts and reports `0.0` equity drift because the baseline transcript
format still excludes foreign recompute equity vectors. The final
`Transcript -> EqStream -> DivergenceMetrics` scorer remains Sprint `7.5`
closure work.

### Metrics

For a pair `(backend_A, backend_B)` against the same transcript
(`backend_A` is the originator; `backend_B` is the recomputer):

- **`visit_disagreement_rate(A, B)`** = `count(visits_A[m,a] ≠
  visits_B[m,a])` / `count(all (m, a) pairs)`. Zero under `--rng cpp`
  within the (ii)–(v) cohort by contract.
- **`move_disagreement_rate(A, B)`** = `count(argmax_action(visits_A[m,
  ·]) ≠ argmax_action(visits_B[m, ·]))` / `count(moves)`. Zero under
  `--rng cpp` within (ii)–(v) by contract; small (<0.1%) expected under
  `--rng native` or cross-build comparisons.
- **`equity_l2_drift(A, B)`** = `‖equity_A − equity_B‖₂` over the
  per-move-per-action equity vectors, normalised by vector length.
  Always nonzero across backends (libm differences); meaningful when
  bounded against the threshold table below.

### Thresholds

| Comparison context | `visit_disagreement_rate` | `move_disagreement_rate` | Action on breach |
|--------------------|---------------------------|--------------------------|-----------------|
| Same backend, same envelope | 0 (contract) | 0 (contract) | Hard fail in `mcts-integration` Q4 |
| Cross-backend (ii)–(v), `--rng cpp`, envelope-uniform cohort | 0 (contract) | 0 (contract) | Hard fail in `mcts-cross-backend` Q3 |
| Cross-backend (ii)–(v), `--rng native` | ≤ 5% | ≤ 0.5% | Warn in report card if exceeded; not a test failure |
| Cross-build same backend | ≤ 1% | ≤ 0.1% | Warn in REPL; not a test failure |

The non-contract thresholds (the bottom two rows) are *empirically
pinnable* — they're placeholders for the numbers we expect to see;
the Phase 7 report-card workload pins them in `cabal.project`
(`MOVE_DELTA_NATIVE_MAX`, `VISIT_DELTA_NATIVE_MAX`, etc.) once we have
measurement runs to calibrate them.

### Surface

- **REPL** (`mcts inspect replay`): when the user opens a non-originator
  column for a `(transcript, backend, build)` triple, the column
  header annotates `move-Δ: x.x%  visit-Δ: y.y%` against the
  originator. Colour-coded against the thresholds (green within, yellow
  approaching, red exceeding).
- **Report card** (`mcts test all`): the headline output adds a
  per-backend-pair divergence matrix. Under `--rng cpp` every
  off-diagonal element reads `0.0% / 0.0%`; anything else is a smell
  to investigate.
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
| 1 | (i) `cpp-legacy` vs (ii)–(v) | Terminal-state semantics: (i) has no game-level ply cap; (ii)–(v) treat `ply_count >= max_plies` as a draw with eval `0.0` | (i) is a verbatim port and inherits the legacy's behaviour; the ply-cap draw rule is a behavioural improvement adopted only by the steelman backends | (i) is excluded from the default `verify` cohort by the `VerifyBackend` GADT; rejoins under `mcts verify legacy-parity` with `max_plies = MAX_ROLLOUT_ITERS = 10000` pinned, where the divergence collapses |
| 2 | (i) | RNG: always `std::mt19937_64`; no `--rng native` axis | Verbatim port of the legacy's RNG choice; the legacy ships only `std::mt19937_64` | `--rng native` is silently ignored for (i) when it appears in a mixed cohort; `mcts verify` cohorts under `--rng cpp` are unaffected |
| 3 | (ii) / (iii) under `--rng native` | RNG: `xoshiro256++` or `wyrand`, not `std::mt19937_64` | Smaller state and faster `next_u64` for benchmark throughput; statistical quality adequate for rollout selection. See [compiler_runtime_tuning.md → Native-RNG item](./compiler_runtime_tuning.md) and [../../README.md → Compiler and runtime tuning](../../README.md) item 15 | Bench-only divergence: visit-count bit-equality is not asserted under `--rng native`; under `--rng cpp` all four steelman backends draw from the shared `std::mt19937_64` and remain bit-equal |
| 4 | (iv) Rust / (v) Haskell under `--rng native` | RNG: each backend's idiomatic generator (Rust `rand`, Haskell `splitmix`) | Same rationale as #3; raw-throughput measurement should not be taxed by an artificial RNG choice | Bench-only divergence; visit-count bit-equality is not asserted across `--rng native` cohorts. Same-backend determinism (Q4) still holds under `--rng native` |
| 5 | (i) under any `max_plies != MAX_ROLLOUT_ITERS` | Q1 / Q2 / Q5 throughput basis: (i)'s games run to a positional win and are on average longer than the ply-capped games of (ii)–(v) | (i) has no ply cap (#1), so games/sec for (i) is not on the same engine-budget basis as (ii)–(v) | Throughput **is published** with a `backendBasisFootnotes` warning per [unit_testing_policy.md → Backend (i) basis caveat](./unit_testing_policy.md) and [../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md → Sprint 7.3](../../DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md); the load-bearing Q1 / Q2 comparison is Haskell (v) vs C++ (ii). |
| 6 | All backends, amd64 ↔ arm64 | Equity float bits | `libm`, FMA, denormal handling, SIMD reduction differ across arches | Cross-arch cohorts rejected at parse time with `AppError ArchEnvelopeMismatch`; per-arch cache partitioning makes accidental cross-arch comparison impossible. Visit counts remain bit-equal even across arches. |
| 7 | Same backend across different build envelopes | Equity float bits and (under `--rng native`) potentially visit counts | A rebuild changes `engine_build_id`, often `libm_id`/`compiler_version`, and may change `fp_flags`/`cpu_features`. Equity drift is unavoidable; visit drift can occur if FP differences swap a tie-break upstream of a subsequent rollout under `--rng native` | `mcts verify` hard-fails with `AppError EngineEnvelopeMismatch (BackendSlot b)` unless `--allow-stale` is passed. `mcts inspect replay` shows a persistent yellow banner `envelope: BUILD MISMATCH — recomputed locally; equities may drift at ULP from origin`; multi-build sidecar cache (one `.eq` per `(backend, build_prefix16)`) lets the user compare across builds. Visit drift under cross-build `--rng cpp` is still expected to be zero in practice (the byte-consumption contract pins it) but is not a contract |

The set is closed in the literal sense: review rejects any PR that
introduces behaviour incompatible with the cohort assertions above unless
this table grows a new entry that names the new divergence, its reason,
and its gating envelope. The `mcts-cross-backend` and `mcts-legacy-parity`
stanzas are precisely the empirical check that the listed divergences are
the only divergences; any unlisted drift fails them.

## Cross-References

- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [transcript_format.md](./transcript_format.md) — wire format and content
  addressing
- [backend_ffi_contract.md](./backend_ffi_contract.md) — `--rng cpp` plumbing
  across the FFI
- [compiler_runtime_tuning.md](./compiler_runtime_tuning.md) — RNG-choice
  asymmetry under `--rng native` for backend (ii)/(iii)
- [unit_testing_policy.md](./unit_testing_policy.md) — `mcts-cross-backend` and
  `mcts-legacy-parity` Cabal stanzas
- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
