# MCTS

A high-performance runtime for Monte Carlo Tree Search (MCTS), targeting the Corridors board game. The long-term goal is AlphaZero-style ANN evaluation; the first phase is rollout-based MCTS only.

This repository is the successor to `MCTS_legacy`, a hand-tuned imperative C++ implementation. The goal here is to **progressively refactor that codebase, maintaining multiple parallel implementations side-by-side, until a pure Haskell version equals the original C++ in throughput**. The proof of concept is that purely functional Haskell can rival C++ on a workload this performance-sensitive, using only the game engine and rollout-based MCTS.

> **Status:** This README expresses the project's intent and roadmap. The repository is in its bootstrap phase; the first deliverable is the cross-language benchmark harness described below.

> **Plan and doctrine:** The authoritative execution-ordered plan lives at [`DEVELOPMENT_PLAN/README.md`](DEVELOPMENT_PLAN/README.md); the authoritative CLI doctrine lives at [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md).

---

## Why this exists

The legacy implementation lives at `~/MCTS_legacy`: a template-heavy, mutation-heavy C++ MCTS engine glued to Python via pybind11. It is fast, but the code is tightly coupled to its imperative representation, hard to reason about, and hostile to algorithmic experimentation.

We want a runtime that is:

1. **As fast as maximally-optimised imperative C++** on the headline workloads. The bar is not the legacy as it exists today — it is the strongest imperative-C++ implementation we can build using every reasonable modern technique (LTO, PGO, BOLT, arena-allocated tree nodes, scratch-board rollouts, branch hints). See backend (ii) below.
2. **Purely functional at the API surface** in its final form, so that algorithmic changes (search policies, evaluators, prior shaping) are local edits rather than rewrites. Internally, the engine is free to use `ST`-monad mutable unboxed arrays — that is the only realistic way to match optimised imperative C++, and the local-reasoning property is preserved as long as the public types and operations stay pure.
3. **Bit-for-bit deterministic**: given a seed, an RNG source, and a sequence of moves, every implementation produces identical visit counts, identical action orderings, identical rollouts. Reproducibility is a first-class invariant, not a debugging aid.

The contest is rigged in favour of imperative C++ and Rust. Backends (ii), (iii), and (iv) are compiled and linked with every reasonable optimisation — `-O3`, `-march=native`, full LTO, two-stage PGO, BOLT post-link, `mimalloc`, arena-allocated tree nodes, scratch-board rollouts, branch hints. Backend (i) is preserved as a strictly verbatim port to confirm faithful reproduction of the legacy engine; (ii) is the actual performance ceiling against which (v) Haskell must compete. The hypothesis is only meaningful when tested against a maximally-tuned imperative baseline rather than a strawman.

To get there without a single big-bang rewrite, we keep multiple implementations alive in the same repo, expose them through a single tool, and benchmark them against each other on every change.

---

## One CLI, five backends

There is exactly one user-facing binary: a Haskell CLI built with Cabal, written in accordance with [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md). All five implementations are reachable as backends behind the same command surface.

| # | Backend                           | Linkage                | Purpose                                                                                                                                                                                                                                                                          |
|---|-----------------------------------|------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| i   | **C++ (legacy port)**             | C ABI via Haskell FFI  | Strictly verbatim re-port of the original imperative C++ — only FFI shims and the minimum changes needed to expose a C ABI. Inherits the legacy's `shared_ptr` trees, `std::mt19937_64` RNG, and single-threaded design unchanged. Regression sanity check only; **not** the performance ceiling. |
| ii  | **C++ (imperative, max-optimised)** | C ABI via Haskell FFI | Imperative C++, rewritten with every reasonable modern optimisation (see [Compiler and runtime tuning](#compiler-and-runtime-tuning)): arena-allocated tree nodes, scratch-board rollouts, PGO+BOLT, `mimalloc`, branch hints. **The actual performance ceiling.** If pure Haskell matches this, the hypothesis is proven. |
| iii | **C++ (functional-style)**        | C ABI via Haskell FFI  | Same algorithms as (ii), same optimisation stack, rewritten in a more functional style with modern C++ idiom. Tests whether functional-style C++ pays a tax against imperative C++ *in the same language*. Stepping stone to Haskell.                                          |
| iv  | **Rust**                          | C ABI via Haskell FFI  | Modern, functional-leaning Rust on the latest stable compiler, same maximal-optimisation stance as (ii)/(iii). Independent cross-language check on the C++ numbers.                                                                                                            |
| v   | **Haskell**                       | Native (in-process)    | Pure Haskell, the eventual target. **Must match (ii)** — not (i) — on both benchmarks. Pure at the API; `ST` + unboxed mutable arena internally.                                                                                                                              |

Backends (i), (ii), (iii), and (iv) are compiled to static / shared libraries with a stable C ABI and called from Haskell through the FFI. There is no separate Python entry point, no separate Rust entry point — every measurement, every determinism check, every game runs out of one process driven by one binary. This keeps the clock, the threading model, and the input encoding identical across measurements.

---

## Threading

**Each individual game is single-threaded.** One tree, one search, one rollout stream — we never parallelise the search within a single game. Multi-threading in this project is *only ever* about running independent games concurrently.

The two modes:

- **Single-threaded.** Games run sequentially on one worker. The per-game wall-clock from this mode is the basic "how fast is one game" measurement, with no scheduling overhead attached.
- **Multi-threaded.** Default **8 workers** (`--workers N` to override). The batch of games is dispatched into a pool of workers; each worker plays one game at a time, single-threaded internally, and picks up the next when done. The point of this mode is to measure how each implementation's runtime *scales* — how `games/sec` changes as the worker count grows. Different runtimes (GHC's RTS, Tokio, raw pthreads, ...) have very different concurrency overheads, allocator-contention behaviour, and locality characteristics; the MT benchmark is what surfaces them.

Each game's RNG stream is seeded by `splitmix64(master_seed, game_index)`, so per-game output is independent of worker count, scheduling order, and worker-to-game assignment. Running `--games 32 --threading single` and `--games 32 --threading multi --workers 8` produce the same 32 game transcripts; only the wall-clock differs. Every backend is single-threaded internally per game (matching the legacy implementation) and is dispatched into the same worker pool as the others, so all five backends measure under identical scheduling semantics.

---

## RNG strategy

Different RNG algorithms cannot be expected to produce identical byte streams, so we cannot assert cross-implementation equality under each language's native RNG. Instead, every backend except (i) supports **two RNG sources**:

- **`--rng native`** — each backend uses the fastest RNG it can defend statistically. Backends (ii)/(iii) may use `xoshiro256++` or `wyrand` (see [Compiler and runtime tuning](#compiler-and-runtime-tuning) item 16) instead of `std::mt19937_64`; (iv) Rust uses `rand`; (v) Haskell uses `splitmix` or equivalent. Used for benchmarks and any workload where raw throughput matters.
- **`--rng cpp`** — every participating backend draws its random bytes from **the same C++ `std::mt19937_64` generator** (the one the legacy uses). Backends (ii) and (iii) use it directly; (iv) Rust and (v) Haskell reach it through the FFI. Used for correctness validation.

Backend (i) is verbatim from `MCTS_legacy` and always uses `std::mt19937_64` — it has no separate native/cpp axis. When (i) appears in a mixed cohort that passes `--rng native`, the flag is silently ignored for (i): it draws from `std::mt19937_64` while the other backends draw from their native RNGs.

The split is deliberate:

- **Native RNG** isolates language-level overhead from RNG overhead and gives each implementation a fair throughput measurement. We do **not** assert cross-backend bit equality here.
- **C++ RNG** factors RNG choice out of the equation, leaving only the search algorithm and the game engine. Under `--rng cpp`, backends (ii), (iii), (iv), (v) must produce **identical visit counts, identical action orderings, and identical rollout sequences** for the same seed and move history. Backend (i) is excluded from the default `verify` cohort because its terminal-state semantics differ (see [Draw rule](#draw-rule)); it rejoins the cohort under `mcts verify legacy-parity`, which pins `max_plies = 10000` so the divergence collapses. This is what the `mcts verify` subcommands check; see [Cross-backend verification](#cross-backend-verification) below.

Same-language determinism (same backend, same master seed, same RNG source ⇒ same set of game transcripts) is required unconditionally. Each game's RNG stream is seeded by `splitmix64(master_seed, game_index)` (or the C++-RNG equivalent under `--rng cpp`), so worker count, scheduling order, and worker-to-game assignment never affect any individual game's output — only the total wall-clock.

---

## Cross-backend verification

The `mcts verify` subcommands run the requested backends under `--rng cpp` and check that their game transcripts agree.

**Round-robin, no oracle.** Every requested backend produces a transcript; transcripts are compared pairwise. Any mismatched pair fails the test. No backend is privileged as "truth" — disagreement between any two backends is a bug somewhere.

**Nothing is committed.** Transcripts live in a local `.mcts-cache/transcripts/` directory which is `.gitignore`'d. Files are content-addressed by `sha256(run_config)`, so the same `(backend, master_seed, threading, workers, sim_params)` reuses prior output across runs. The MC seed is the provenance: any transcript can be regenerated from scratch, so persisting them in version control buys nothing.

**Compile-time toggle for instrumentation.** Each backend produces two build targets: `*-bench` (no instrumentation — the binary is byte-identical to one where the feature doesn't exist) and `*-instrumented` (transcript writer plus FFI hooks that expose per-move tree state; used by `verify`, `play`, and `inspect replay`). The toggle is a template / type-level flag on the self-play driver, not a runtime branch in the hot loop. The MCTS engine itself (search, rollout, board, RNG) is one shared artefact between the two targets; only the small driver compiles twice. Because the bench binary has nothing to disable, no benchmark phase is needed to demonstrate zero overhead — the instrumentation code literally does not exist in it.

**Format: dense binary, fully owned.** No schema-library dependency: protobuf, flatbuffers, Cap'n Proto, and CBOR all have library-version-dependent encoding latitude that would have to be imported into the determinism contract. The header carries the run config; per-move records are sparse `(action_id, visits)` pairs sorted ascending by action ID.

Equity is **excluded** from the wire format. Visit counts are integer and order-independent; equity is a derived float and would import summation-order non-determinism into the hash. See [Replay equity guarantees](#replay-equity-guarantees) below for the bit-equality semantics this gives the user.

For human-readable failure diffs, the decoder re-runs the deterministic search from move 0 using the seed and the recorded `chosen` sequence; equity is then read from the resulting in-memory tree's value backups. The stored visits serve as a per-move determinism check that the re-run stayed on the deterministic path — not as input to the equity calculation.

Canonical action enumeration (one byte per action):

```
  0..80    pawn moves         y*9 + x           (x,y ∈ [0,8])
 81..144   horizontal walls   81  + y*8 + x     (x,y ∈ [0,7])
145..208   vertical walls     145 + y*8 + x     (x,y ∈ [0,7])
209..254   reserved
255        sentinel / invalid
```

Sketch of the file layout (little-endian everywhere, no padding):

```
header     : magic u32 = "MCTR" | version u16 | backend u8 | threading u8
             | workers u16 | rng_source u8 | _reserved u8
             | c_param u64 | flags u32 | master_seed u64
             | initial_sims u32 | per_move_sims u32
             | max_plies u16 | _reserved u16

per game   : game_id u32, then per-move records, then terminator
per move   : move_index u16 | chosen u8 | n_actions u8
             | n_actions × (action u8, visits u32) sorted ascending by action
terminator : 0xFF u8 | winner u8 | total_moves u16
             winner ∈ {0 = hero, 1 = villain, 2 = draw}
```

Field semantics:

- **`c_param u64`** is the UCT exploration constant stored as an IEEE-754 `double` bit-cast to `u64` (little-endian, matching the rest of the layout). Portability across hosts depends on `double` being IEEE-754; the determinism contract pins x86-64 Linux, so this is satisfied.
- **`flags u32`** is reserved for future format extensions (e.g., compression, extended action enumerations). All bits **must** be zero in v1; non-zero bits cause the decoder to reject the file with `AppError TranscriptFormatUnsupported`.
- **`initial_sims u32` / `per_move_sims u32`** together encode the `SimBudget`. For `FixedSims N`, both fields are set to N (so `initial_sims == per_move_sims` is the on-wire discriminator for `FixedSims`); for `RampedSims N0 N1`, `initial_sims = N0` and `per_move_sims = N1`.
- **`_reserved u8` / `_reserved u16`** must be zero on write and are ignored on read.

Each game is single-threaded internally regardless of the batch's `--threading` setting, so the per-move record carries exactly one `(action, visits)` list — there are no per-worker blocks. The header's `threading` / `workers` fields are batch-level metadata (useful for `inspect list`), not per-game content. Typical sizes: ~30 bytes per move, ~2 KB per game; a thousand games is in the low megabytes. SHA-256 is computed on the fly during write; comparison is digest-equality first, with the decoder scanning move-by-move to print the first divergent record on failure.

**RNG FFI contract.** Under `--rng cpp`, Rust and Haskell consume `u64` values from a shared C++ `std::mt19937_64` via:

```c
cpp_rng* cpp_rng_new(uint64_t seed);
uint64_t cpp_rng_next_u64(cpp_rng*);
cpp_rng* cpp_rng_split(uint64_t master_seed, uint64_t game_index);
void     cpp_rng_free(cpp_rng*);
```

Per-game sub-seeds are derived via `splitmix64(master_seed, game_index)` rather than mutating any parent generator's state, so each game's RNG stream is independent and reproducible from the master seed and its index alone. Workers don't have RNG identities — they execute games, and the seed lives with the game.

**Byte-consumption order is itself the contract.** Every backend draws the same number of `u64`s per rollout, uses `draw % n` for legal-move selection (no rejection sampling unless every backend rejects identically), and consumes RNG bits at the same logical points in the search. The verify test enforces this implicitly: any backend that drifts off the contract fails on its first divergent rollout.

**Backprop traversal order is part of the contract.** All backends walk the path from the selected leaf to the root in the same order, applying visit-count increments at the same logical step. Equity is excluded from the wire format, but transient intermediate visit counts at non-leaf nodes are observed by the comparator and must agree.

**Tie-breaking is part of the contract.** Move selection follows the legacy's `(equity desc, non_terminal_rank asc)`, applied uniformly across all five backends. There is no separate multi-threaded tie-breaker — within a single game (which is always single-threaded) there is nothing to aggregate, and across games each game's RNG stream is its own independent universe.

### Replay equity guarantees

Re-running the deterministic search recovers equity values; the bit-exactness of those values depends on which backend executes the replay.

- **Same backend that wrote the transcript** (same compiled binary, same hardware): equities are bit-identical to those the original search computed. The chain that guarantees this: the seed fixes the RNG state; RNG plus the deterministic engine fixes the simulation order; identical simulation order produces identical value backups in identical float-accumulation order; identical float arithmetic on identical hardware produces identical bits. Tree persistence carries this property across moves because the inherited tree at move M is itself a deterministic function of moves 0..M-1.
- **Different backend**: equities are not bit-equal. Float accumulation order can differ subtly between GCC, `rustc`, and GHC-via-LLVM even under `-fno-fast-math`; x87 80-bit intermediates can leak through libm calls; SIMD reductions can reassociate. Equity values produced by different backends typically agree to many digits but can differ at the last few ULPs.

This asymmetry is why the wire format excludes equity: visit counts (integer) are bit-equal across backends and form the determinism contract; equities (float) are not, and requiring float bit-equality would force every backend to fix a canonical summation order and a canonical libm — a much bigger contract.

**Cross-backend equity tolerance is implicit.** The verify subcommands do not compare equities directly. The contract is that equity differences across backends must never be large enough to swap a tie-break in `(equity desc, non_terminal_rank asc)`. This is enforced transitively: any equity drift that swaps a chosen action surfaces as a visit-count mismatch on the next move (because subsequent searches diverge from that point onward), and visit counts are what `verify` compares. Backends that drift further than this implicit tolerance fail verify on visits, not on equities.

### Draw rule

The game's terminal-state semantics differ between backend (i) and backends (ii)–(v). This is the only intentional behavioural divergence in the project.

- **Backend (i)** — `is_terminal()` ↔ `hero_wins() || villain_wins()` (verbatim from `MCTS_legacy/backend/core/board.cpp:247`). A game has no draw outcome; rollouts that exceed `MAX_ROLLOUT_ITERS = 10000` plies abort the search via an exception (the legacy's behaviour). Because (i) is the strictly verbatim regression-sanity port, it is excluded from cross-backend `verify` cohorts.
- **Backends (ii)–(v)** — `is_terminal()` ↔ `hero_wins() || villain_wins() || ply_count >= max_plies`. The board state carries a `uint16_t` ply counter. When termination is by ply cap, `get_terminal_eval()` returns `0.0` (draw); rollouts back this value up like any other terminal.

`max_plies` is a run-configuration parameter (default **200**), exposed on the CLI as `--max-plies N`, pinned in the transcript header (`max_plies u16`), and part of the determinism contract: two backends (ii)–(v) with the same `max_plies`, same seed, and same chosen sequence must produce identical transcripts.

The wire format's `winner u8` field is a 3-value enum: `0 = hero`, `1 = villain`, `2 = draw`. The decoder reports draws in `inspect show` / `inspect replay` as `<draw>` in the same position move notation otherwise occupies.

**Legacy parity envelope.** The new draw rule is the only thing keeping backend (i) out of the cross-backend `verify` cohort. Setting `max_plies = MAX_ROLLOUT_ITERS = 10000` collapses that divergence: in this envelope all five backends terminate every rollout the same way (on a positional win), so transcripts must be bit-equal. The `mcts verify legacy-parity` subcommand drives this cohort with `max_plies` and `--rng cpp` pinned, under a fixture seed chosen so that (i) never trips `MAX_ROLLOUT_ITERS`. If a future change causes (i) to throw, the cohort fails with `AppError LegacyParityRolloutOverflow` carrying `(seed, game_index, move_index)` so the seed can be replaced. The test also fails if (i) survives but its longest rollout reaches the cap, since that means the legacy is one change away from the cliff. This complements Q6: Q6 asks "does (i) reproduce `MCTS_legacy`?", legacy-parity asks "do all five backends agree?" within the envelope. Composed with Q6 they give a transitive parity chain `MCTS_legacy ≡ (i) ≡ (ii)..(v)`.

---

## Benchmarks

Two workloads define "fast enough":

- **(a) Random rollouts.** Pure stress test of the game engine: legal-move generation, move application, terminal detection. No tree, no UCT — just play random games end-to-end as fast as the engine allows.
- **(b) Adversarial MCTS self-play with rollout evaluations.** Full UCT search with random-rollout leaf evaluation, played as adversarial self-play. Exercises the engine, the tree representation, and the search policy together. Each game is single-threaded internally; in multi-threaded mode the workload is a batch of independent self-play games dispatched across `--workers N` workers, with each worker playing one game at a time.

Each benchmark runs the full cross product of `{backend} × {single-threaded, multi-threaded} × {native RNG, C++ RNG}` (where applicable — backend (i) has no separate "native vs. C++" axis), reporting wall-clock time and throughput (games/sec, simulations/sec) from a single Cabal-driven measurement clock. The clock is `Data.Time.Clock.getMonotonicTimeNSec` (monotonic, ns-resolution), started inside the Haskell driver just before the first game is dispatched and stopped just after the last game returns through the FFI; all five backends are timed by the same clock so cross-backend numbers are directly comparable.

Backend (i)'s throughput is published for reference only and is **not on the same basis** as (ii)–(v) under any `max_plies` other than `MAX_ROLLOUT_ITERS = 10000`: (i) has no game-level ply cap (see [Draw rule](#draw-rule)), so its games run to a positional win and are on average longer than the ply-capped games of (ii)–(v). The load-bearing comparison in Q1/Q2 is Haskell vs (ii), where both backends terminate identically.

---

## `mcts test all`

The doctrine-mandatory canonical test command. `mcts test all` is the developer-facing entrypoint that proves whether the POC's hypotheses hold. It does three things, in order:

1. **Delegates to `cabal test`.** Runs every `test-suite` stanza below, each `type: exitcode-stdio-1.0`, with `tasty` as the in-stanza runner.
2. **Executes a fixed POC report-card workload.** A deterministic battery of `bench` and `verify` runs, pinned in `cabal.project`, so the headline numbers are reproducible across hosts.
3. **Prints a single tidy summary block** on stdout that answers the POC's headline questions (Q1–Q6 below) in one screenful.

Failure of any cabal stanza, any verify cohort, or any report-card invocation exits non-zero.

### Test-suite stanzas

Per doctrine §Test Organization, each tier is a separate cabal stanza:

| Stanza | Tier | Scope |
|---|---|---|
| `mcts-unit` | pure logic | engine invariants, parser tests (`execParserPure`), property tests, golden tests for `CommandSpec` output and `inspect show` rendering, transcript codec roundtrips, RNG mixer properties |
| `mcts-integration` | subprocess | exercises the real `mcts` binary across the FFI to every backend; same-backend determinism (same seed ⇒ same transcripts, three seeds per backend) |
| `mcts-cross-backend` | round-robin verify | the `verify` cohort under `--rng cpp` covering backends (ii), (iii), (iv), (v); backend (i) excluded by the `VerifyBackend` type |
| `mcts-legacy-parity` | round-robin verify, legacy envelope | `verify legacy-parity` across all five backends with `max_plies = 10000` pinned and a fixture seed; pre-flight guard asserts (i) neither throws nor reaches the cap, see [Draw rule](#draw-rule) |
| `mcts-haskell-style` | lint | `fourmolu --mode check`, `hlint --with-group=default --with-group=extra + .hlint.yaml`, `cabal format` round-trip equality |

A single `tasty` tree spanning all tiers is forbidden by doctrine; the stanza split gives Cabal-native parallelism and lets contributors target one tier (`cabal test mcts-unit`).

### POC headline questions

The report-card workload runs *after* `cabal test` succeeds and answers:

1. **Q1.** Does pure Haskell match maximally-optimised C++ (backend ii) on benchmark (a) random rollouts, single-threaded and on 8 workers?
2. **Q2.** Does pure Haskell match backend (ii) on benchmark (b) self-play, single-threaded and on 8 workers?
3. **Q3.** Do backends (ii), (iii), (iv), (v) agree bit-for-bit under `--rng cpp` (round-robin verify on both rollouts and self-play)?
4. **Q4.** Does same-backend determinism hold across runs (same backend, same seed ⇒ identical transcripts) for every backend?
5. **Q5.** How does each backend scale from `--threading single` to `--threading multi --workers 8`? The text summary block highlights Haskell and C++ (ii) as the two anchors; the full per-backend scaling table is available via `mcts test all --format json`.
6. **Q6.** Does the verbatim port (i) faithfully reproduce `MCTS_legacy` on benchmark (b)?
7. **Q7.** Do all five backends agree round-robin under the legacy-parity envelope (`max_plies = 10000`, fixture seed where (i) does not throw)?

### Report-card workload

A fixed, deterministic battery, identical across hosts:

```bash
# Q1 — random rollouts
mcts bench rollouts --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell \
                    --threading single --rng native --games $G_R --seed 42
mcts bench rollouts --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell \
                    --threading multi --workers 8 --rng native --games $G_R --seed 42

# Q2 / Q5 — self-play, with both threading modes feeding Q5's scaling table
mcts bench selfplay --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell \
                    --threading single --rng native --games $G_S --seed 42 --sims $S_BENCH
mcts bench selfplay --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell \
                    --threading multi --workers 8 --rng native --games $G_S --seed 42 --sims $S_BENCH

# Q3 — cross-backend determinism, backend (i) excluded by the VerifyBackend type
mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell \
                     --threading single --games $G_V --seed 42 --max-plies 200
mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell \
                     --threading single --games $G_V --seed 42 --max-plies 200 --sims $S_VERIFY

# Q7 — legacy parity, all five backends, max_plies and RNG pinned by the subcommand
mcts verify legacy-parity selfplay \
            --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell \
            --games $G_LP --seed $S_LP --sims $S_LP_SIMS
```

Game counts (`$G_R`, `$G_S`, `$G_V`, `$G_LP`), per-move sim budgets (`$S_BENCH`, `$S_VERIFY`, `$S_LP_SIMS`), and the legacy-parity seed (`$S_LP`) are pinned in `cabal.project` so the report card is reproducible across hosts. The pinned values are: `G_R = 100_000`, `G_S = 1_000`, `G_V = 50`, `G_LP = 10`, `S_BENCH = 10_000`, `S_VERIFY = 10_000`, `S_LP_SIMS = 10_000`, `S_LP = 42`. Q4 (same-backend determinism) and Q6 (backend (i) vs `MCTS_legacy` parity) are fully covered by the `mcts-integration` stanza — Q6 specifically as a golden-test cohort comparing `cpp-legacy` transcripts against an out-of-band `MCTS_legacy`-produced fixture set checked into `test/golden/legacy/` — and are re-asserted by the report-card summary rather than re-run. Q7 (5-way legacy-parity round-robin) runs in full both inside the `mcts-legacy-parity` stanza and again here, since its failure modes are configuration-sensitive (fixture seed, sim budget) and worth surfacing in the headline summary.

### Tidy summary block

Rendered to stdout at the end of `mcts test all`. Literal example:

```
MCTS POC report card — seed=42, max-plies=200, host=<uname -m>, ghc=9.14.1
──────────────────────────────────────────────────────────────────────────
Q1  Haskell vs C++ (ii)  rollouts  ST          0.96×   ( 98.1k vs 102.1k games/s)
Q1  Haskell vs C++ (ii)  rollouts  MT8         0.94×   (727k   vs 776k   games/s)
Q2  Haskell vs C++ (ii)  self-play ST          0.91×   (   213 vs    235 games/s)
Q2  Haskell vs C++ (ii)  self-play MT8         0.89×   (  1570 vs   1764 games/s)
Q3  Cross-backend determinism  (cpp RNG)       PASS    (4 backends × 50 games agree)
Q4  Same-backend determinism   (per backend)   PASS    (5/5 backends × 3 seeds)
Q5  MT scaling  Haskell   1→8 workers          7.4×    (linear ideal: 8×)
Q5  MT scaling  C++ (ii)  1→8 workers          7.6×
Q6  Legacy port (i) vs MCTS_legacy             PASS    (golden transcripts match)
Q7  Legacy parity, 5-way round-robin           PASS    (5 backends × 10 games agree,
                                                        max_plies=10000, seed=42)

cabal test                                     PASS    (mcts-unit, mcts-integration,
                                                        mcts-cross-backend, mcts-legacy-parity,
                                                        mcts-haskell-style)

Verdict: Haskell within 11% of max-optimised C++ on the slower of the two benchmarks.
```

The same data is available as `mcts test all --format json` for CI consumption; both formats are rendered by the same pure function over a typed `ReportCard` value.

### Doctrine compliance

- **Plan / Apply.** `mcts test all` is a Plan/Apply command. `build :: TestInputs -> Either AppError TestPlan` produces the typed list of cabal stanzas + report-card subprocesses (modelled per doctrine §Subprocesses as Typed Values); `apply :: Env -> TestPlan -> IO ExitCode` runs it. `--dry-run` prints the rendered plan and exits 0; `--plan-file <path>` writes the rendered plan for out-of-band review.
- **Prerequisites.** All five backend artifacts present, PGO+BOLT profiles populated, `mimalloc` linked, GHC/Cabal pinned versions on `$PATH` — encoded as one `prerequisiteRegistry` per doctrine §Prerequisites as Typed Effects. The transitive closure runs before `apply`; a single unmet node aborts with `AppError PrerequisiteUnmet` carrying the failing `nodeId`, description, and remedy hint.
- **Determinism.** The summary block is rendered by a pure function of a typed `ReportCard` value. No timestamps, no locale-dependent ordering, no terminal-width-dependent wrapping. Wall-clock numbers are the only non-deterministic content and are rendered to fixed precision (three significant figures for ratios, one decimal for throughputs in kilogames/s). The block is golden-testable; the live throughputs are replaced by sentinel placeholders in the golden file.

---

## Tree persistence and determinism

One non-negotiable feature inherited from the legacy implementation:

- **Visits persist across moves.** When a move is played, the chosen child becomes the new root and its accumulated visits are kept; the rest of the tree is discarded incrementally. The next search starts warm. Tree persistence is per-game; in multi-threaded batches multiple per-game trees live concurrently in memory, each independent — there is never more than one thread touching a given tree.
- **Trees are memory-resident only.** Nothing is serialised; persistence between runs is not a goal.
- **Trees are losslessly recoverable.** Because Monte Carlo draws are seeded deterministically, any tree state is reproducible by replaying the seed and move sequence. This is what justifies keeping the tree in memory only.
- **Incremental truncation is a memory-management lever**, not a correctness concern. The shape of the tree at any given moment is an optimisation; the visits it represents are reproducible from the seed.

---

## CLI command topology

Following [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md), commands are modelled as ordinary Haskell data types and the parser is generated from a separate `CommandSpec`:

```haskell
data Command
  = Bench    BenchCommand
  | Verify   VerifyCommand
  | Play     PlayOptions
  | Inspect  InspectCommand
  | Test     TestCommand           -- mcts test all, mcts test <stanza>
  | Lint     LintCommand           -- mcts lint files|docs|haskell|all
  | Docs     DocsCommand           -- mcts docs check|generate
  | Commands CommandsOptions       -- introspection: --tree, --json, default flat list
  | Help     HelpOptions           -- mcts help <subcommand>
  deriving stock (Show, Eq)

data BenchCommand
  = BenchRollouts BenchOptions
  | BenchSelfplay BenchOptions
  deriving stock (Show, Eq)

data VerifyCommand
  = VerifyRollouts     VerifyOptions          -- cross-backend determinism on rollouts
  | VerifySelfplay     VerifyOptions          -- cross-backend determinism on self-play
  | VerifyLegacyParity LegacyParityOptions    -- all five backends under the legacy envelope
  deriving stock (Show, Eq)

data InspectCommand
  = InspectList                    -- enumerate the local transcript cache
  | InspectShow   ShowOptions      -- dump one transcript, legacy notation
  | InspectReplay ReplayOptions    -- interactive TUI replay
  deriving stock (Show, Eq)

data TestCommand
  = TestAll                        -- every cabal stanza + POC report card
  | TestStanza Text                -- e.g. "mcts-unit", "mcts-integration"
  deriving stock (Show, Eq)

data LintCommand
  = LintFiles   { lintWrite :: Bool }  -- whitespace, final newline, forbidden paths
  | LintDocs    { lintWrite :: Bool }  -- governed docs, generated sections
  | LintHaskell { lintWrite :: Bool }  -- fourmolu + hlint + cabal format
  | LintAll                            -- runs every lint above
  deriving stock (Show, Eq)

data DocsCommand
  = DocsCheck                      -- compare rendered output against on-disk markers
  | DocsGenerate                   -- splice rendered output into markers (idempotent)
  deriving stock (Show, Eq)

data CommandsOptions = CommandsOptions
  { commandsTree :: Bool           -- --tree
  , commandsJson :: Bool           -- --json
  } deriving stock (Show, Eq)

newtype HelpOptions = HelpOptions { helpTarget :: [Text] }
                      deriving stock (Show, Eq)

data Backend    = CppLegacy | CppImperative | CppFunctional | Rust | Haskell
                  deriving stock (Show, Eq)

data VerifyBackend = VCppImperative | VCppFunctional | VRust | VHaskell
                     deriving stock (Show, Eq)        -- backend (i) excluded at the type level

data LegacyParityBackend = LpCppLegacy | LpCppImperative | LpCppFunctional | LpRust | LpHaskell
                           deriving stock (Show, Eq)  -- (i) is allowed here, and required in any cohort

data LegacyParityWorkload = LpRollouts | LpSelfplay
                            deriving stock (Show, Eq)

data RngSource  = NativeRng | CppRng
                  deriving stock (Show, Eq)

data Threading  = SingleThreaded | MultiThreaded { workers :: Int }
                  deriving stock (Show, Eq)

data Side       = Hero | Villain
                  deriving stock (Show, Eq)

data SimBudget  = FixedSims Int                    -- same budget every move
                | RampedSims Int Int               -- initial, then per-move
                  deriving stock (Show, Eq)
-- CLI syntax: `--sims N` parses as `FixedSims N`; `--sims N0:N1` parses as
-- `RampedSims N0 N1` (initial-move budget N0, per-move budget N1 thereafter).

newtype TranscriptRef = TranscriptRef Text          -- sha256 prefix, git-style
                        deriving stock (Show, Eq)

data BenchOptions = BenchOptions
  { benchBackends  :: NonEmpty Backend
  , benchRng       :: RngSource
  , benchThreading :: Threading       -- default: MultiThreaded { workers = 8 }
  , benchGames     :: Int
  , benchSeed      :: Word64
  , benchMaxPlies  :: Word16          -- default: 200; ignored for backend (i)
  , benchSims      :: SimBudget       -- default: FixedSims 10_000; ignored by bench rollouts
  } deriving stock (Show, Eq)

data VerifyOptions = VerifyOptions
  { verifyBackends  :: NonEmpty VerifyBackend  -- (i) cannot appear: see VerifyBackend above
  , verifyThreading :: Threading              -- default: SingleThreaded; transcripts are identical either way, ST is the simpler default
  , verifyGames     :: Int
  , verifySeed      :: Word64
  , verifyMaxPlies  :: Word16             -- default: 200; pinned across the cohort
  , verifySims      :: SimBudget          -- default: FixedSims 10_000; ignored by verify rollouts
  -- RngSource is implicitly CppRng; native RNG cannot validate cross-backend
  -- The "must include >= 2 backends" rule is checked at parse time and rendered
  -- as AppError VerifyCohortTooSmall on failure (see Output and error discipline).
  } deriving stock (Show, Eq)

data LegacyParityOptions = LegacyParityOptions
  { lpBackends :: NonEmpty LegacyParityBackend  -- must include LpCppLegacy (parse-time check)
  , lpWorkload :: LegacyParityWorkload          -- rollouts or self-play
  , lpGames    :: Int
  , lpSeed     :: Word64                        -- fixture seed; chosen so (i) does not throw
  , lpSims     :: SimBudget                     -- default: FixedSims 10_000; ignored for LpRollouts
  -- max_plies is pinned to MAX_ROLLOUT_ITERS = 10000, not user-overridable
  -- RngSource is pinned to CppRng
  -- Threading is pinned to SingleThreaded
  -- On (i) throwing or its longest rollout reaching the cap, the cohort fails
  -- with AppError LegacyParityRolloutOverflow (seed, game_index, move_index).
  } deriving stock (Show, Eq)

data PlayOptions = PlayOptions
  { playBackend :: Backend
  , playSide    :: Side
  , playVs      :: Maybe Backend         -- Just b → AI-vs-AI; Nothing → human plays
  , playRng     :: RngSource
  , playSeed    :: Maybe Word64          -- Nothing → fresh random, recorded in transcript
  , playSims    :: SimBudget
  , playMaxPlies :: Word16               -- default: 200; ignored if playBackend is (i)
  -- no threading field: a single game is always single-threaded internally
  } deriving stock (Show, Eq)

data ShowOptions = ShowOptions
  { showRef        :: TranscriptRef
  , showTopN       :: Int                -- default 10; 0 = all
  , showWithEquity :: Bool               -- default False; True re-runs search
  } deriving stock (Show, Eq)

data ReplayOptions = ReplayOptions
  { replayRef         :: TranscriptRef
  , replayTopN        :: Int             -- default 10; 0 = all; live-adjustable in-app
  , replayCacheStates :: Int             -- default 20; in-memory MCTS state cache size
  } deriving stock (Show, Eq)
```

This gives a typed surface that the parser, the help text, and the test suite all derive from.

Concrete invocations:

```bash
# (a) Random rollouts, all five backends, single-threaded, native RNG, 100k games
mcts bench rollouts --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell \
                    --threading single --rng native --games 100000 --seed 42

# (b) Self-play, multi-threaded with 8 workers (default), native RNG
mcts bench selfplay --backend haskell --rng native --games 1000 --seed 42 --sims 10000

# Same as above on 32 workers
mcts bench selfplay --backend haskell --rng native --workers 32 --games 1000 --seed 42 --sims 10000

# Cross-backend determinism check: same C++ RNG bytes, identical trees expected
mcts verify selfplay --backend cpp-imperative,rust,haskell \
                     --threading single --games 50 --seed 42 --max-plies 200 --sims 10000

# Interactive game: human plays hero against the haskell backend, 10k sims/move
mcts play --backend haskell --side hero --sims 10000

# Backend-vs-backend spectate (no human input; watch a self-play game render live) — Haskell vs the steelman ceiling
mcts play --backend haskell --side villain --vs cpp-imperative --sims 10000

# What's in my local transcript cache?
mcts inspect list

# Dump a stored transcript with equities recomputed (slow; opt-in)
mcts inspect show 7a2f --top 10 --with-equity

# Interactive replay: navigate forward/back through a stored game
mcts inspect replay 7a2f --top 15
```

The `verify` subtree pins `--rng cpp`, drives every requested backend over the same seed and same move sequence, and round-robin-compares their transcripts (see [Cross-backend verification](#cross-backend-verification) above). Same-backend determinism tests live alongside as `tasty` cases under the `mcts-integration` stanza (see [`mcts test all`](#mcts-test-all)).

### Progressive introspection

Per doctrine §Progressive Introspection, the CLI exposes:

```bash
mcts commands              # flat list of every subcommand
mcts commands --tree       # tree rendering
mcts commands --json       # JSON command schema (source of truth for external tooling)
mcts help <subcommand>     # focused help, equivalent to `<subcommand> --help`
```

`mcts commands --json` is the externally-stable interface; the human-readable forms are derived from the same `CommandSpec` value.

### Output and error discipline

Per doctrine §Output Rules and §Error Handling: stdout carries primary output, stderr carries diagnostics. The non-TUI commands (`bench`, `verify`, `test`, `inspect list`, `inspect show`, `commands`, `help`, `lint`, `docs`) accept `--format json|table|plain` (default `table` on a TTY, `plain` otherwise) and the standard `--color auto|always|never` / `--no-color` flags. The TUI commands (`play`, `inspect replay`) own their own rendering and ignore both. Errors render through a single `AppError` ADT at the CLI boundary — `AppError TranscriptNotFound`, `AppError VerifyMismatch`, `AppError VerifyCohortTooSmall`, etc. — and never leak onto stdout.

### Doctrine scope

This project adopts the following sections of `HASKELL_CLI_TOOL.md` as binding: Command Topology, CommandSpec + Generated Artifacts (marker discipline, paired check/write, `forbiddenPathRegistry`), Progressive Introspection, Subprocesses as Typed Values (the PGO+BOLT build harness invokes `g++`, `rustc`, `llvm-bolt` through the typed `Subprocess` boundary), Plan/Apply (notably for `mcts test all` and the build harness, with `--dry-run` and `--plan-file <path>` on every Plan/Apply command), Prerequisites as Typed Effects (toolchain prereqs across all five backends, encoded as one `prerequisiteRegistry`), Application Environment (`ReaderT Env IO` with a single `Env` record), Lint, Format, and Code-Quality Stack (`fourmolu` + `hlint` + `cabal format`, with `fourmolu.yaml` committed at repo root and the `mcts-haskell-style` test-suite), Testing Doctrine and Test Organization (one `test-suite` stanza per tier), Output Rules, Error Handling, and GADT-indexed state machines where naturally indicated.

Explicitly **out of scope**: Long-Running Daemons in the Same Binary (the CLI is short-running only — this also covers the daemon-internal "Configuration: Dhall file with mandatory hot reload" subsection), Capability Classes and Service Errors (no external subsystems), Retry Policy as First-Class Values (no external subsystems), At-Least-Once Event Processing (no event stream), Reconcilers: Idempotent Mutation as a Single Command (no managed state in the world), Smart Constructors for Paired Resources (no paired resources), and Pulumi-Orchestrated Infrastructure Tests (no cloud surface). These sections of `HASKELL_CLI_TOOL.md` are read as informational context, not as binding constraints on this project.

---

## Interactive modes

`play` and `inspect replay` are full-screen TUIs built on `brick` over `vty`. Layouts are declarative; redraws happen on event-loop ticks, not on every keystroke. `inspect show` and `inspect list` are plain non-interactive output. All four modes use the legacy move notation (`*(x,y)`, `H(x,y)`, `V(x,y)`) inherited from `MCTS_legacy`.

**Doctrine alignment.** The interactive surfaces add `brick` and `vty` to the doctrine's standard stack; this is the only deviation from the `HASKELL_CLI_TOOL.md` stack list and applies to no other command. The TUI commands (`play`, `inspect replay`) own their own rendering and do not honour the `--format` / `--color` flags from [Output and error discipline](#output-and-error-discipline) — those apply to the non-interactive `inspect list` and `inspect show` only. Errors in all four modes render through the same `AppError` ADT and `renderError` boundary used by the rest of the CLI, never written to stdout.

**Hash-prefix lookup.** `<hash-prefix>` arguments to `inspect show` and `inspect replay` use git-style resolution: the shortest prefix that uniquely identifies a transcript is accepted, minimum 4 hex chars. On no match: exit non-zero with `AppError TranscriptNotFound`. On multi-match: exit non-zero with `AppError TranscriptAmbiguous` carrying the list of candidate hashes so the operator can re-issue with a longer prefix.

**Cache root.** The transcript cache root resolves to `--cache-dir <path>` if given, else `$MCTS_CACHE_DIR` if set, else `./.mcts-cache/` resolved against the current working directory. The on-disk layout under that root is `transcripts/<sha>.tr`; this is the `.mcts-cache/transcripts/` directory referenced throughout the rest of this document. The cache root is `.gitignore`'d when it falls inside the project tree.

**`play`** — interactive game against any backend. Left pane shows the Corridors board; the right pane carries whose turn it is, move count, last move played, and (during the AI's turn) a live counter of simulations completed. The human types moves into a prompt at the bottom. The AI side runs MCTS through `playBackend` under `playSims` and the configured RNG. With `--vs <backend>` the AI plays both sides and the human is a spectator.

In-app prompt grammar. Lines beginning with `:` are commands; everything else is parsed as a move in legacy notation. Recognised commands:

- `:hint` — show the top-N moves the AI would consider for the side currently to play.
- `:undo` — back up one ply; supported by an in-memory stack of MCTS states.
- `:save` — flush the partial game as a transcript to the cache root. Hand-played transcripts are addressed by `sha256(run_config || move_history)` (where `||` denotes byte concatenation) rather than `sha256(run_config)` alone, because the human's move choices make the post-config bytes non-deterministic.
- `:quit` — exit. The final transcript is written automatically when the game ends.

Any other `:`-prefixed input renders an `AppError UnknownCommand` to the status bar and leaves game state untouched. Malformed move notation renders an `AppError InvalidMove` similarly. `Ctrl-C` during the AI's turn cancels the in-progress search and returns control to the prompt; `Ctrl-C` at the prompt is equivalent to `:quit`. All four error renderings go through the same `renderError` boundary the non-interactive commands use.

**`inspect list`** — non-interactive. Scans `<cache-root>/transcripts/*.tr`, decodes each header, prints one line per transcript: short hash (first 8 chars), backend, master seed, threading (`ST` or `MT8`), sims, total games, total moves, mtime. Sorted by mtime descending. Honours `--format json|table|plain`.

**`inspect show <hash-prefix>`** — non-interactive dump in legacy notation. Header summary followed by per-move records:

```
Move N (hero|villain): *(4,2)
    *(4,2)  visits=3401
    *(3,2)  visits=2105
    ...
```

Default `--top 10`; `--top 0` shows all legal moves. With `--with-equity` the engine re-runs the search to populate an `equity=...` column on every line — this is exactly the recompute path that `inspect replay` uses, just emitted as plain output.

**`inspect replay <hash-prefix>`** — interactive brick TUI for navigating a stored game.

- Layout: board on the left; on the right, a context panel with the current move index, the move actually played, and the top-N legal-move list (visits, equity, action). Status line at the bottom: `<hash> | move M / total | press ? for help`.
- Keybinds: `→` / `l` next move, `←` / `h` prev move, `Home` / `End` jump to start / end, `g` opens a "jump to move N" prompt, `+` / `-` adjust the top-N cutoff live, `?` toggles a keybind overlay, `q` quits.
- **Equity is recomputed on the fly.** Equities and alternative moves are not stored in the transcript — that omission is by design (the transcript wire format excludes floats to keep its hash byte-exact). When navigating to move M, the replay engine reconstructs the game state by replaying moves 0..M-1 with the persistent tree carried forward as in the original search, runs move M's search using the seed and budget from the transcript header, then reads sorted actions back from the tree through the instrumentation interface (FFI for backends (i)–(iv), a direct module call for (v)). The visit counts produced must equal the transcript record byte-for-byte; this doubles as a built-in determinism check that fires on every navigation. Equity is derived from the same search's value backups. The cross-language determinism guarantee in [Cross-backend verification](#cross-backend-verification) is what makes this recompute trustworthy.
- **State caching.** The last `replayCacheStates` MCTS states (default 20, `--cache-states N`) are kept in memory so back-navigation past those is incremental. Eviction is LRU on the cached-state map; jumping past the cache window triggers a forward re-replay from the nearest earlier cached state, not always from move 0. For typical game lengths (60 moves × 10k sims) this is seconds, not minutes.

---

## First milestone

The first concrete deliverable is the **Cabal-centric benchmark harness** described by the CLI topology above:

- `mcts bench rollouts` and `mcts bench selfplay` running across all five backends, both threading modes, both RNG sources.
- `mcts verify rollouts` and `mcts verify selfplay` enforcing cross-backend determinism under the shared C++ RNG.
- All measurements taken from a single Cabal-driven clock; backends (i), (ii), (iii), and (iv) reached through the FFI from the same Haskell process, with (v) Haskell running natively in that same process.
- No ANN evaluation. No Python. No web frontend. Just engine, rollouts, MCTS, numbers.

Subsequent milestones progressively retire (i) in favour of (ii) once the verbatim port has demonstrated faithful reproduction of the legacy, then (ii) in favour of (iii) once functional-style C++ has demonstrated parity with imperative C++, then (iii) in favour of (v) once pure Haskell has demonstrated parity with functional C++. Each retiring backend's recorded transcripts and throughput numbers are frozen in `test/golden/` as the regression anchor for the surviving cohort, so the Haskell-vs-(ii) performance target from [Why this exists](#why-this-exists) survives (ii)'s retirement as a fixed number rather than a live binary. Backend (iv) Rust is kept as a long-running second opinion throughout.

Q7 and the `mcts-legacy-parity` test stanza retire alongside (i), since both require a live (i) binary to participate in the 5-way round-robin. The transitive parity chain `MCTS_legacy ≡ (i) ≡ (ii)..(v)` (see [Draw rule](#draw-rule)) becomes a frozen historical fact recorded in `test/golden/legacy/` rather than a continuously re-run check. Q3 and the `mcts-cross-backend` stanza continue with whatever subset of (ii)–(v) is still live.

---

## Build and run

The project ships a Dockerfile and `compose.yaml` (inspired by `MCTS_legacy/docker/`) so the toolchain is reproducible:

- **Base:** `ubuntu:24.04`
- **C++:** latest stable GCC shipped with 24.04, C++23 enabled (GCC only — Clang is not supported). LLVM/BOLT pinned in the Dockerfile for the post-link reordering step (see [Compiler and runtime tuning](#compiler-and-runtime-tuning)). GHC's `-fllvm` backend (used for the Haskell engine) shares this same pinned LLVM, so the container carries one LLVM version regardless of which language is being compiled — the C++ toolchain itself remains GCC.
- **Rust:** latest stable, installed via `rustup`; minor version pinned in the Dockerfile.
- **Haskell:** `ghcup`-managed, pinned to **GHC 9.14.1** and **Cabal 3.16.1.0** (per `HASKELL_CLI_TOOL.md`). LLVM toolchain pinned for GHC's `-fllvm` backend — the same LLVM version used by BOLT, so the container only carries one.

```bash
docker compose up -d
docker compose exec mcts bash
# inside the container:
cabal build all
cabal test
mcts bench rollouts --backend haskell --threading single --rng native --games 100000 --seed 42
```

The Haskell CLI follows the conventions in [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md) where they apply:

- Library-first layout (`app/Main.hs` is a thin entry point; logic lives in `src/`).
- Commands modelled as Haskell ADTs; `optparse-applicative` parser generated from a separate `CommandSpec`.
- `tasty` (+ `tasty-hunit`, `tasty-quickcheck`, `tasty-golden`) for tests, partitioned into the `test-suite` stanzas listed in [`mcts test all`](#mcts-test-all).
- `brick` + `vty` for the interactive TUI screens (`play`, `inspect replay`); pure terminal, no graphical dependencies. This is the only addition to the doctrine's standard stack.
- `fourmolu` + `hlint` + `cabal format` as the code-quality stack, with `fourmolu.yaml` committed at repo root; exposed both as `mcts lint haskell` and as the `mcts-haskell-style` test-suite.
- Strict toolchain pinning via `cabal.project` and `tested-with: ghc ==9.14.1`.

See [Doctrine scope](#doctrine-scope) above for the explicit in-scope / out-of-scope split against `HASKELL_CLI_TOOL.md`.

---

## Compiler and runtime tuning

Each backend has an explicit, copy-pasteable optimisation stack covering compiler flags **and** code-level structural requirements. The contest is rigged in favour of imperative C++ and Rust on purpose — see [Why this exists](#why-this-exists). Backend (v) Haskell competes against (ii), not (i).

### Backend (i) — C++ legacy port

Exempt from this section. (i) is strictly verbatim from `MCTS_legacy`; only FFI shims are permitted. It uses the legacy's flags (`-std=c++17 -O3 -fPIC -Wall`), its `std::shared_ptr<uct_node>` trees, and `std::mt19937_64`. The only adjustments are those required to expose a C ABI to Haskell.

### Backends (ii) and (iii) — C++ imperative and functional-style

**Compiler flags:**

```
-std=c++23 -O3 -march=native -mtune=native -flto -fno-plt
-fno-semantic-interposition -fvisibility=hidden -fvisibility-inlines-hidden
```

**Build workflow:**

- **Two-stage PGO**: instrumented build via `-fprofile-generate=<dir>`, training run on benchmark (b) at a representative game count, optimised build with `-fprofile-use=<dir> -fprofile-correction`.
- **BOLT** post-link binary reordering after PGO — the canonical PGO+BOLT stack used by perf-critical C++ services.
- **`mimalloc`** as the system allocator (static link preferred for FFI determinism; `LD_PRELOAD` acceptable for benchmark runs).

**Code-level requirements**, grouped by priority. Top-tier items are non-negotiable; the rest are required unless profiling shows the change is neutral or harmful.

*Top tier — each individually expected to be a 1.5–3× gain over the legacy baseline:*

1. **Arena-allocated tree, children referenced by `uint32_t` indices.** One contiguous `std::vector<uct_node>` per game, expanded in place, freed in bulk at game end. Replaces the legacy's `std::vector<std::shared_ptr<uct_node>>` + `new uct_node` (`MCTS_legacy/backend/core/mcts.hpp:145`). Eliminates refcount traffic, double indirection, per-node destruction, and most cache misses during tree descent. This is the single largest structural change and the principal reason (i) cannot serve as the steelman.
2. **Per-rollout scratch board with undo, or one snapshot per game.** Reuses one `board` instance per game — rollouts either undo moves at end-of-rollout or restore from a snapshot taken at expansion time. Eliminates the per-rollout `board_copy` allocation that the legacy pays on every simulation.
3. **PGO + BOLT pipeline.** Two-stage feedback-directed optimisation, as in the build workflow above. The branch-heavy UCT descent and the rollout's terminal-check loop are exactly the workloads FDO was designed for.

*Correctness requirement (also top tier):*

- **Ply counter in board state.** Board state carries a `uint16_t` ply counter. `is_terminal()` becomes `hero_wins() || villain_wins() || ply_count >= max_plies`; `get_terminal_eval()` returns `0.0` on ply-cap termination. The ply counter is part of the board snapshot used for per-rollout scratch reuse (item 2 above); restoring it to the start-of-rollout value is part of the undo / snapshot path. See [Draw rule](#draw-rule) for the determinism contract.

*Second tier — each individually 10–30%, cumulative:*

4. **Flat children layout** — children stored contiguously in the arena, each parent recording `first_child_idx: u32` and `n_children: u16`. No `std::vector<u32>` per node. Eliminates one allocation per expansion and one indirection per descent step.
5. **Move-list buffer reuse.** Move generators write into a thread-local or stack-SBO buffer; no per-call `std::vector`. Inline buffer sized for typical Corridors move counts (≈40); heap spill is allowed but should be rare.
6. **`uint32_t` parent index, not `shared_ptr<uct_node>`.** Backprop walks a flat array, not a refcounted pointer chain.
7. **Visit-count compression to `uint16_t`** where the per-move sim budget permits (`per_move_sims < 65536`). Shrinks node footprint, more nodes per cache line. The header's `per_move_sims` field gates the choice; the wire format already records visits as `u32`, so the in-memory choice is transparent to the determinism contract.

*Third tier — sub-10% each but they stack:*

8. `[[likely]]` / `[[unlikely]]` on UCT child-selection and terminal-state branches.
9. `__attribute__((hot))` / `__attribute__((always_inline))` on `select_best_child`, `apply_move`, `is_terminal`, `rollout_step`.
10. `__attribute__((const))` / `((pure))` on referentially-transparent helpers — lets GCC hoist and CSE.
11. `__builtin_prefetch` on the child array during UCT descent.
12. `__builtin_popcountll` / `__builtin_ctzll` on raw `uint64_t` bitboards rather than `std::bitset<64>::_Find_first()` (not reliably lowered to `tzcnt`).
13. `alignas(64)` on the tree-node arena base; struct-of-arrays where measurement supports it.
14. `thread_local` scratch buffers for the MT pool (per-worker, not per-game).
15. `-fno-exceptions` for the engine core if no engine code throws — eliminates landing-pad cost.

*Native-RNG benchmark only* (not under `--rng cpp`, which is pinned to `std::mt19937_64` by the determinism contract):

16. Replace `std::mt19937_64` with `xoshiro256++` or `wyrand` — smaller state, faster `next_u64`, equivalent statistical quality for rollouts.

**Backend (iii) — functional-style C++** observes all of the above. The "functional style" of (iii) is at the API and data-flow level, *not* the memory-representation level — arena allocation and mutable scratch state are still required. Both backends run under the same optimisation regime so that (iii)-vs-(ii) isolates *style* as the variable.

Excluded deliberately from both (ii) and (iii): `-ffast-math` / `-Ofast`. Equity backprop is summation-order-sensitive and we want backend-internal determinism even though equity is excluded from the cross-backend wire format.

### Backend (iv) — Rust

`Cargo.toml`:

```toml
[profile.release]
opt-level = 3
lto = "fat"
codegen-units = 1
panic = "abort"
strip = "symbols"
```

`RUSTFLAGS`: `-C target-cpu=native -C link-arg=-fuse-ld=lld`.

Build workflow:

- **Two-stage PGO** via `rustc -Cprofile-generate=<dir>` → train on benchmark (b) → `-Cprofile-use=<dir>`.
- **BOLT** post-link, same as C++.
- **`mimalloc`** as `#[global_allocator]` (via the `mimalloc` crate).

Code-level requirements:

- **Ply counter in board state** (correctness — see [Draw rule](#draw-rule)). Board carries a `u16` ply counter; `is_terminal` returns true on `ply >= max_plies` with eval `0.0`. Part of the per-rollout snapshot/undo path.
- Tree as `Vec<Node>` with `u32` child indices, mirroring the C++ arena.
- `#[inline(always)]` on hot leaf operations, `#[cold]` on error and terminal paths.
- `core::hint::unreachable_unchecked` where a precondition genuinely guarantees it; each use documented.
- Bit ops via `u64::count_ones` / `u64::trailing_zeros` (lower to the same `popcnt`/`tzcnt` as the C++ builtins).
- No `Rc` / `Arc` in the hot path. No `Box<dyn Trait>` in the search.

### Backend (v) — Haskell

GHC flags (in `cabal.project` or per-library stanza):

```
ghc-options:
  -O2 -fllvm
  -funbox-strict-fields
  -fspecialise-aggressively
  -fexpose-all-unfoldings
  -flate-dmd-anal
  -fmax-simplifier-iterations=20
  -fworker-wrapper
  -fstatic-argument-transformation
```

LLVM codegen tuned via `-optlo-mcpu=native` (through to LLVM `opt`) and `-optlc-mcpu=native` (through to `llc`). LLVM version pinned in the Dockerfile so codegen is reproducible.

RTS tuning, baked into the executable's `ghc-options`:

```
-with-rtsopts=-A64m -n4m -qg1 -qb -T
```

Large nursery to push major GC out, `-qg1` so major GC is parallel from gen 1, `-qb` for load balancing across capabilities, `-T` to expose GC stats for `+RTS -s` profiling.

Code-level requirements:

- **Ply counter in board state** (correctness — see [Draw rule](#draw-rule)). Board carries a `Word16` ply counter; `isTerminal` returns true on `ply >= maxPlies` with eval `0.0`. Lives in the same unboxed board record as the bitboards; restored as part of the per-rollout `ST`-arena snapshot path.
- Engine hot path lives in `ST s`. Tree is a `MutablePrimArray s` arena of unboxed `Int32` / `Float` fields (SoA), or a hand-rolled `MutableByteArray#` if profiling shows `PrimArray` indexing isn't optimal.
- Board state is `Word64` bitboards, manipulated with `Data.Bits` (compiles to `popcnt`/`tzcnt` under `-fllvm` with `-optlo-mcpu=native`).
- Strict fields everywhere (`{-# UNPACK #-} !Int`), bang patterns on `let` bindings inside `ST` blocks.
- `INLINABLE` on every exported engine primitive; `SPECIALIZE` on the search loop for the concrete game type.
- Pure API: `search :: GameState -> Seed -> SearchBudget -> Tree -> (Move, Tree)`. `Tree` is opaque; internally backed by the `ST` arena and frozen at the API boundary if tree-persistence semantics need it.
- No `Maybe` or `Either` in the rollout inner loop; sentinel values or unboxed sum representations instead.

### One known asymmetry: PGO

GHC 9.14 has no production-grade profile-guided optimisation comparable to GCC/Clang `-fprofile-use` or `rustc -Cprofile-use`. The Haskell backend therefore competes against PGO+BOLT-optimised C++ and Rust without an equivalent feedback loop. This is the asymmetry that most concretely tests the hypothesis: if Haskell matches under these conditions, the result is meaningful; if it falls short by 5–15%, that gap is plausibly attributable to the missing PGO loop rather than to any property of pure functional code per se. We document this rather than paper over it.

---

## Game: Corridors

Corridors is a two-player race game on a 9×9 board. Each player tries to reach the opposite edge while spending a finite supply of walls to obstruct the opponent. Walls cannot fully enclose either player. The rules are unchanged from the legacy implementation; only the runtime is being rebuilt.

Strict Corridors has no draw rule — a game can in principle run arbitrarily long if both players waste moves. Backend (i) inherits this property unchanged (it is a verbatim port). Backends (ii)–(v) impose an additional termination rule: if the ply count reaches `max_plies` (default 200) without a positional win, the game is a draw. `max_plies` is part of the run configuration and pinned in the transcript header, so it's part of the determinism contract. See [Draw rule](#draw-rule) for the wire-format and contract details.

Move notation matches the legacy engine: `*(x,y)` for pawn moves, `H(x,y)` / `V(x,y)` for horizontal / vertical wall placements.

---

## Repository layout (target)

```
MCTS/
  app/                 -- Haskell CLI entry point (thin)
  src/                 -- Haskell library: engine, MCTS, CommandSpec, FFI bindings
  cpp-legacy/          -- (i)   verbatim port of the original C++, exposed via C ABI
  cpp-imperative/      -- (ii)  imperative C++, max-optimised, exposed via C ABI
  cpp-functional/      -- (iii) functional-style C++, exposed via C ABI
  rust/                -- (iv)  Rust implementation, exposed via C ABI (cdylib)
  bench/               -- Cabal benchmark targets (criterion / tasty-bench)
  test/                -- determinism and cross-backend verification tests
                       --   test/golden/legacy/ — MCTS_legacy fixtures for Q6
  docker/              -- Dockerfile, compose.yaml
  cabal.project        -- toolchain pin, report-card knobs ($G_*, $S_*, $S_LP)
  fourmolu.yaml        -- formatter config (per HASKELL_CLI_TOOL.md)
  README.md            -- this file
  LICENCE              -- project license
  HASKELL_CLI_TOOL.md  -- Haskell project conventions
  AGENTS.md / CLAUDE.md -- agent guardrails
```

This layout is the target; not all directories exist yet.

---

## License

See [`LICENCE`](LICENCE).
