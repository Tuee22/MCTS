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
- Backend (iv) Rust uses the `rand` crate's default stream.
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
| (v) `haskell` | `splitmix` | `splitmix` Hackage library | Phase 2 Sprint 2.5 |

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
to `Word64` with `fromIntegral` at the splitmix and FFI call sites. The wire
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
data VerifyBackend
  = VCppImperative
  | VCppFunctional
  | VRust
  | VHaskell
  deriving stock (Show, Eq)
```

A cohort of one fails parse-time with `AppError VerifyCohortTooSmall`. Any pair
mismatch fails with `AppError VerifyMismatch` carrying `(backend_a, backend_b,
seed, game_index, move_index)`.

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
   feeds the 255-action wire format in
   [transcript_format.md → 255-Action Canonical Enumeration](./transcript_format.md)).

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

Each individual game is single-threaded internally. Multi-threading is only
ever about running independent games concurrently. The default `MultiThreaded
{ workers = 8 }` dispatches a batch of games across 8 workers; each worker plays
one game at a time, single-threaded internally.

Per the per-game seed derivation, running 32 games on 1 worker and 32 games on 8
workers produces identical transcript sets; only wall-clock differs.

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
