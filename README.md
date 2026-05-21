# MCTS

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: AGENTS.md, CLAUDE.md, HASKELL_CLI_TOOL.md, DEVELOPMENT_PLAN/README.md, DEVELOPMENT_PLAN/00-overview.md, DEVELOPMENT_PLAN/system-components.md, DEVELOPMENT_PLAN/phase-0-planning-documentation.md, DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, DEVELOPMENT_PLAN/phase-2-transcript-codec-and-determinism.md, DEVELOPMENT_PLAN/phase-3-haskell-engine.md, DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md, DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md, DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md, DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md, DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md, documents/documentation_standards.md, documents/engineering/README.md, documents/engineering/backend_ffi_contract.md, documents/engineering/cli_command_surface.md, documents/engineering/code_quality.md, documents/engineering/compiler_runtime_tuning.md, documents/engineering/determinism_contract.md, documents/engineering/haskell_code_guide.md, documents/engineering/transcript_format.md, documents/engineering/unit_testing_policy.md
**Generated sections**: none

> **Purpose**: Operator-facing project intent — what MCTS is, what the backend cohort exists to prove, the threading and RNG strategy, the cross-backend verification surface, and where the authoritative plan and doctrine live.

A high-performance runtime for Monte Carlo Tree Search (MCTS), targeting the Corridors board game. The long-term goal is AlphaZero-style ANN evaluation; the first phase is rollout-based MCTS only.

This repository continues from `MCTS_legacy`, a hand-tuned imperative C++ implementation. The goal here is to keep five parallel implementations alive behind one CLI until a pure Haskell version equals a deliberately steelmanned C++ implementation in throughput. The proof of concept is that purely functional Haskell can rival C++ on a workload this performance-sensitive, using only the game engine and rollout-based MCTS.

> **Current status:** The supported architecture is a five-backend implementation
> baseline behind one Haskell CLI: three C++ backends, Rust, and Haskell all remain
> first-class benchmark and verification participants. The POC is not just a
> throughput race; it must show that pure Haskell matches a deliberately
> steelmanned imperative C++ baseline while the five implementations preserve the
> same MCTS logic under the controlled C++-RNG verification mode. Normal tests pass
> from a clean clone without checked-in transcripts, throughput anchors, snapshots,
> or other generated validation data. The authoritative phase-by-phase status
> remains
> [`DEVELOPMENT_PLAN/README.md`](DEVELOPMENT_PLAN/README.md).

> **Plan and doctrine:** The authoritative execution-ordered plan lives at [`DEVELOPMENT_PLAN/README.md`](DEVELOPMENT_PLAN/README.md); the authoritative CLI doctrine lives at [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md); the documentation-topology rules live at [`documents/documentation_standards.md`](documents/documentation_standards.md).

---

## Why this exists

The legacy implementation lives at `~/MCTS_legacy`: a template-heavy, mutation-heavy C++ MCTS engine glued to Python via pybind11. It is fast, but the code is tightly coupled to its imperative representation, hard to reason about, and hostile to algorithmic experimentation.

We want a runtime that is:

1. **As fast as maximally-optimised imperative C++** on the headline workloads. The bar is not the legacy as it exists today — it is the strongest imperative-C++ implementation we can build using every reasonable modern technique (LTO, PGO, BOLT, arena-allocated tree nodes, scratch-board rollouts, branch hints). See backend (ii) below.
2. **Purely functional at the API surface** in its final form, so that algorithmic changes (search policies, evaluators, prior shaping) are local edits rather than rewrites. Internally, the engine is free to use `ST`-monad mutable unboxed arrays — that is the only realistic way to match optimised imperative C++, and the local-reasoning property is preserved as long as the public types and operations stay pure.
3. **Bit-for-bit deterministic**: given a seed, an RNG source, and a sequence of moves, every implementation produces identical visit counts, identical action orderings, identical rollouts. Reproducibility is a first-class invariant, not a debugging aid.

The contest is rigged in favour of imperative C++ and Rust. Backends (ii), (iii), and (iv) are compiled and linked with every reasonable optimisation — `-O3`, `-march=native`, full LTO, two-stage PGO, BOLT post-link, `mimalloc`, arena-allocated tree nodes, scratch-board rollouts, branch hints. Backend (i) is a strictly verbatim port used to prove faithful reproduction of the legacy engine; backend (ii) is the performance ceiling against which (v) Haskell must compete. The hypothesis is only meaningful when tested against a maximally-tuned imperative baseline rather than a strawman.

To get there without a single big-bang rewrite, we keep multiple implementations alive in the same repo, expose them through a single tool, and benchmark them against each other on every change.

---

## One CLI, Five Backends

There is exactly one user-facing binary: a Haskell CLI built with Cabal, written in accordance with [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md). All five implementations are reachable as first-class backends behind the same command surface.

| # | Backend                           | Linkage                | Purpose                                                                                                                                                                                                                                                                          |
|---|-----------------------------------|------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| i   | **C++ (legacy port)**             | C ABI via Haskell FFI | Strictly verbatim re-port of the original imperative C++. Only FFI shims and the minimum changes needed to expose a C ABI are allowed. Inherits the legacy's tree representation, `std::mt19937_64` RNG, and single-threaded design unchanged. Regression sanity check only; **not** the performance ceiling. |
| ii  | **C++ (imperative, max-optimised)** | C ABI via Haskell FFI | Imperative C++, rewritten with every reasonable modern optimisation (see [Compiler and runtime tuning](#compiler-and-runtime-tuning)): arena-allocated tree nodes, scratch-board rollouts, PGO+BOLT, `mimalloc`, branch hints. **The actual performance ceiling.** If pure Haskell matches this, the hypothesis is proven. |
| iii | **C++ (functional-style)**        | C ABI via Haskell FFI | Same algorithms as (ii), same optimisation stack, rewritten in a more functional style with modern C++ idiom. Tests whether functional-style C++ pays a tax against imperative C++ *in the same language*. Stepping stone to Haskell. |
| iv  | **Rust**                          | C ABI via Haskell FFI  | Modern, functional-leaning Rust on the latest stable compiler, same maximal-optimisation stance as (ii)/(iii). Independent cross-language check on the C++ numbers.                                                                                                            |
| v   | **Haskell**                       | Native (in-process)    | Pure Haskell, the eventual target. **Must match (ii)** — not (i) — on both benchmarks. Pure at the API; `ST` + unboxed mutable arena internally.                                                                                                                              |

Backends (i), (ii), (iii), and (iv) are compiled to shared libraries with stable C ABIs and called from Haskell through the FFI; backend (v) runs in-process. There is no separate Python entry point, no separate Rust entry point — every measurement, every determinism check, every game runs out of one process driven by one binary. This keeps the clock, the threading model, and the input encoding identical across measurements.

---

## Threading

**Each individual game is single-threaded.** One tree, one search, one rollout stream — we never parallelise the search within a single game. Multi-threading in this project is *only ever* about running independent games concurrently.

The two modes:

- **Single-threaded.** Games run sequentially on one worker. The per-game wall-clock from this mode is the basic "how fast is one game" measurement, with no scheduling overhead attached.
- **Multi-threaded.** Default **8 workers** (`--workers N` to override). The batch of games is dispatched into a pool of workers; each worker plays one game at a time, single-threaded internally, and picks up the next when done. The point of this mode is to measure how each implementation's runtime *scales* — how `games/sec` changes as the worker count grows. Different runtimes (GHC's RTS, Tokio, raw pthreads, ...) have very different concurrency overheads, allocator-contention behaviour, and locality characteristics; the MT benchmark is what surfaces them.

Each game's RNG stream is seeded by `splitmix64(master_seed, game_index)` or by the C++-RNG equivalent under the verification mode, so per-game output is independent of worker count, scheduling order, and worker-to-game assignment. Running `--games 32 --threading single` and `--games 32 --threading multi --workers 8` must produce the same 32 determinism payloads for the same backend, seed, RNG source, and logical inputs; only the wall-clock and provenance metadata differ. Every backend is single-threaded internally per game and is dispatched into the same worker pool as the others, so all five backends measure under identical scheduling semantics.

---

## RNG strategy

Different RNG algorithms cannot be expected to produce identical byte streams, so the project deliberately separates performance benchmarking from logical-equivalence verification. Backends (ii), (iii), (iv), and (v) support **two RNG sources**; backend (i) uses the legacy C++ RNG by definition:

- **`--rng native`** — each backend uses the fastest RNG it can defend statistically. Backends (ii)/(iii) may use xoshiro/wyrand-class generators instead of `std::mt19937_64`; Rust uses its native fast RNG; Haskell uses splitmix or its chosen native generator. This mode is for performance benchmarks and operator play. Cross-backend transcript identity is not expected here.
- **`--rng cpp`** — equivalence tests use random numbers generated by the C++ RNG bridge. The bridge splits `(master_seed, game_index)` in the legacy-compatible C++ path and supplies the controlled per-move search seeds used by the participating backends. Backends (ii) and (iii) run their C++ search kernels from that seed contract; Rust and Haskell reach the same controlled stream through the Haskell FFI. This mode is for MCTS logical-equivalence tests, not headline performance.

Backend (i) is verbatim from `MCTS_legacy` and always uses `std::mt19937_64`; it has no separate native/cpp axis. When (i) appears in a mixed benchmark command that passes `--rng native`, the flag is ignored for (i): it draws from the legacy C++ RNG while the other backends draw from their native RNGs.

The dedicated C++ RNG bridge library (`cpp-legacy/build/libmcts_cpp_rng.so` on Linux) is loaded only for equivalence verification and is kept open for the process lifetime once loaded. Native-RNG benchmark paths do not use it.

The split is deliberate:

- **Native RNG** isolates language/runtime overhead from RNG unification overhead and gives each implementation a fair throughput measurement. We do **not** assert cross-backend bit equality here.
- **C++ RNG** factors RNG choice out of the equivalence proof. Under `--rng cpp`, backends (ii), (iii), (iv), and (v) must produce identical visit counts and chosen moves for the same seed and move history. Backend (i) is excluded from the default `verify` cohort because its terminal-state semantics and legacy search kernel differ (see [Draw rule](#draw-rule)); it participates in the dedicated legacy-parity envelope where those differences are intentionally bounded.

Same-language determinism (same backend, same master seed, same RNG source, same logical game inputs ⇒ same set of game determinism payloads) is required unconditionally. Each game's RNG stream is seeded by `splitmix64(master_seed, game_index)` (or the C++-RNG equivalent under `--rng cpp`), so worker count, scheduling order, and worker-to-game assignment never affect any individual game's output — only the total wall-clock and provenance metadata.

---

## Cross-backend verification

The `mcts verify` subcommands run the requested backend slots under `--rng cpp` and check that their determinism payloads agree. Verification uses the live C++/Rust foreign engines when their shared libraries are present and the in-process Haskell backend for (v); any fallback behavior exists only to keep local development stanzas runnable and is not accepted as headline cross-language evidence.

**Round-robin, no oracle.** Every requested backend produces a transcript; decoded determinism payloads are compared pairwise. Any mismatched pair fails the test. No backend is privileged as "truth" — disagreement between any two backends is a bug somewhere.

**Operator cache is local.** Runtime transcripts live in a local `.mcts-cache/transcripts/` directory which is `.gitignore`'d. Files are content-addressed by `sha256(run_config)`, where `run_config` includes the backend, workload, threading/workers, RNG source, master seed, sim params, `max_plies`, per-game index, and `c_param` bits, so the same backend/game run reuses prior output across runs. Cross-backend verification compares a canonical determinism payload decoded from those backend-specific files; it does not require different backends to share a filename. The repository has no checked-in transcript fixture exception: tests synthesize transcripts and sidecars in temporary directories.

**Compile-time toggle for foreign instrumentation.** Steelman foreign backends (ii), (iii), and (iv) keep the paired-target discipline: `*-bench` (no instrumentation — the binary is byte-identical to one where the feature does not exist) and `*-instrumented` (transcript writer plus hooks that expose per-move tree state; used by `play`, `inspect replay`, `inspect divergence`, and integration smokes). Backend (i) is the legacy exemption: it remains line-level faithful to the legacy engine, with transcript writing and instrumentation layered around the C ABI boundary. Backend (v) is native Haskell in-process; it exposes the same logical visit/recompute surfaces directly through Haskell modules rather than through a paired shared-library target. The toggle for foreign steelman backends is a template / type-level flag on the self-play driver, not a runtime branch in the hot loop. The MCTS engine itself (search, rollout, board, RNG) is one shared artefact between paired foreign targets; only the small driver compiles twice. Because the bench binary has nothing to disable, no benchmark phase is needed to demonstrate zero overhead — the instrumentation code literally does not exist in it.

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
             | workers u16 | rng_source u8 | host_arch u8
             | c_param u64 | flags u32 | master_seed u64
             | initial_sims u32 | per_move_sims u32
             | max_plies u16 | workload u16 | envelope_offset u32

envelope   : envelope_version u16 | envelope_byte_length u32
             | cohort-invariant fields (host_arch, rng_source, shared_rng_build_id,
               cohort_config_hash)
             | per-backend-slot fields (engine_build_id, engine_git_commit,
               compiler_id, compiler_version, fp_flags, libm_id, cpu_features, fp_env)
             | -- NOT part of sha256(RunConfig); see Engine envelope below

per game   : game_id u32, then per-move records, then terminator
per move   : move_index u16 | chosen u8 | n_actions u8
             | n_actions × (action u8, visits u32) sorted ascending by action
terminator : 0xFFFF u16 | winner u8 | total_moves u16
             winner ∈ {0 = hero, 1 = villain, 2 = draw}
```

Field semantics:

- **`host_arch u8`** identifies the host CPU architecture the transcript was written on. `0 = amd64` (Linux x86-64), `1 = arm64` (Linux aarch64). Cross-architecture comparison rejects with `AppError ArchEnvelopeMismatch`; see [Architecture envelope](#architecture-envelope) below.
- **`c_param u64`** is the UCT exploration constant stored as an IEEE-754 `double` bit-cast to `u64` (little-endian, matching the rest of the layout). Portability across hosts depends on `double` being IEEE-754; the determinism contract pins amd64 Linux and arm64 Linux as a two-arch envelope (both IEEE-754), so this is satisfied within each arch. Cross-arch comparison is rejected — see [Architecture envelope](#architecture-envelope).
- **`flags u32`** is reserved for future format extensions (e.g., compression, extended action enumerations). All bits **must** be zero in v1; non-zero bits cause the decoder to reject the file with `AppError TranscriptFormatUnsupported`.
- **`initial_sims u32` / `per_move_sims u32`** together encode the `SimBudget`. For `FixedSims N`, both fields are set to N (so `initial_sims == per_move_sims` is the on-wire discriminator for `FixedSims`); for `RampedSims N0 N1`, `initial_sims = N0` and `per_move_sims = N1`.
- **`workload u16`** records the transcript workload: `0 = rollouts`,
  `1 = selfplay`. Other values are rejected by the v1 decoder.

Each game is single-threaded internally regardless of the batch's `--threading` setting, so the per-move record carries exactly one `(action, visits)` list — there are no per-worker blocks. A `--games N` batch writes N backend-specific transcript files, one per `game_id`; the header's `threading` / `workers` fields record the batch dispatcher that produced that game. Typical sizes: ~30 bytes per move, ~2 KB per game; a thousand game transcripts is in the low megabytes. Verification first compares an in-memory SHA-256 over the decoded canonical determinism payload, then runs a length-aware scan to report extra games, extra moves, terminator disagreement, or the first divergent record.

**RNG FFI contract.** The Phase 4 C ABI exposes the legacy C++ seed splitter and
a bulk-fill helper so the Haskell verification path can consume C++-generated
per-move seeds without owning a C++ RNG object across the FFI boundary:

```c
cpp_rng* cpp_rng_new(uint64_t seed);
uint64_t cpp_rng_next_u64(cpp_rng*);
uint64_t cpp_rng_split_seed(uint64_t master_seed, uint64_t game_index);
cpp_rng* cpp_rng_split(uint64_t master_seed, uint64_t game_index);
int      cpp_rng_fill_u64(uint64_t master_seed, uint64_t game_index,
                          uint64_t* out, uint64_t count);
void     cpp_rng_free(cpp_rng*);
```

In `--rng cpp` mode, per-game C++ RNG streams are derived from `(master_seed,
game_index)` rather than mutating any parent generator's state. Each game's RNG
stream is independent and reproducible from the master seed and its index alone.
The live Haskell bridge loads `cpp_rng_fill_u64` from the dedicated RNG shared
object and treats the resulting `u64` values as per-move search seeds.
Workers do not have RNG identities — they execute games, and the seed lives with
the game. Native-RNG benchmark mode may use backend-specific generators, but it
must preserve the same per-game independence property.

**Byte-consumption order is itself the contract.** Every backend draws the same number of `u64`s per rollout, reinterprets the consumed word with Haskell's signed machine-`Int` modulo semantics for legal-move selection, and consumes RNG bits at the same logical points in the search. There is no rejection sampling unless every backend rejects identically. The verify test enforces this implicitly: any backend that drifts off the contract fails on its first divergent rollout.

**Backprop traversal order is part of the contract.** All backends walk the path from the selected leaf to the root in the same order, applying visit-count increments at the same logical step. Equity is excluded from the wire format, but transient intermediate visit counts at non-leaf nodes are observed by the comparator and must agree.

**Move shape and tie-breaking are part of the contract.** The verifier cohort uses the simplified Corridors move set implemented by the Haskell engine: one-square orthogonal pawn moves to adjacent unoccupied cells, no Quoridor-style jumps, no overlapping or crossing walls, and no wall that blocks all paths. Search expands all legal pawn moves plus the first 12 legal wall moves after canonical action-ID ordering. UCT child selection breaks equal scores by action ID; the final root action is the highest-visit child with action ID as the stable tie-break. There is no separate multi-threaded tie-breaker — within a single game there is nothing to aggregate, and across games each game's RNG stream is its own independent universe.

### Replay equity guarantees

Re-running the deterministic search recovers equity values; the bit-exactness of those values depends on whether the *substrate* — backend, arch, and the engine-build envelope — matches what produced the transcript.

- **Same substrate** (same backend, same arch, same engine envelope — i.e., same compiled binary, same hardware, same libm, same compiler flags): equities are bit-identical to those the original search computed. The chain that guarantees this: the seed fixes the RNG state; RNG plus the deterministic engine fixes the simulation order; identical simulation order produces identical value backups in identical float-accumulation order; identical float arithmetic on identical hardware and binaries produces identical bits. Tree persistence carries this property across moves because the inherited tree at move M is itself a deterministic function of moves 0..M-1. Detection of this state is automatic: every transcript carries an [engine envelope](#engine-envelope) and the REPL hard-compares it against the live binary.
- **Same backend, different envelope** (the user has rebuilt — different commit, different optimisation flags, or a libm point upgrade): equities recomputed by the rebuilt binary are *not* bit-equal to the originally-recorded engine's. Visit counts under `--rng cpp` remain bit-equal when the same controlled C++ verification seeds and logical inputs are used; only the floats drift, typically by a few ULPs. `inspect replay` shows a persistent yellow `envelope: BUILD MISMATCH` banner whenever this happens, so the user is never silently shown drifted numbers as if they were the originator's.
- **Different backend** (foreign-engine view): equities are not bit-equal to *any* originator's numbers — they are the foreign backend's own view of the position. This is the multi-backend overlay's intended use: cross-engine comparison. `inspect replay` marks the originator column with ★ and shows a persistent orange `envelope: FOREIGN VIEW` banner whenever the live binary is a different backend than the originator.

This asymmetry is why the wire format and determinism payload exclude equity: visit counts (integer) are bit-equal across the live verification cohort and form the Q3 determinism contract; equities (float) are not, and requiring float bit-equality would force every backend to fix a canonical summation order and a canonical libm — a much bigger contract. The recomputed-per-substrate floats are cached out-of-band in the [equity sidecar cache](#multi-backend-replay) instead.

**Cross-backend equity tolerance is implicit for Q3.** The `verify rollouts` and `verify selfplay` subcommands do not compare equities directly. The contract is that float differences across the live verification cohort must never be large enough to change UCT child selection or the final highest-visit root action. This is enforced transitively: any equity drift that changes a chosen action surfaces as a visit-count mismatch on the next move, and visit counts are what Q3 `verify` compares. Backends that drift further than this implicit tolerance fail verify on visits, not on equities. Q7 legacy parity is a separate liveness/overflow gate for backend (i)'s legacy envelope.

### Engine envelope

Every transcript carries an **engine envelope** block (immediately after the fixed header, excluded from the cross-backend determinism payload) recording every substrate-affecting field at the time the engine ran: the build hash of the loaded shared library, the compiler ID and version, the FP-relevant compiler flags, the libm identity, the CPU features the binary's runtime dispatch actually selected, and the FP environment. Two backends running the same common inputs under `--rng cpp` produce backend-specific `<sha>.tr` files, but the decoded canonical determinism payload must hash identically — exactly the property cross-backend visit-equality requires.

The envelope is layered:

- **Cohort-invariant fields** (`host_arch`, `rng_source`, `shared_rng_build_id`, `cohort_config_hash`) must match across every transcript in a `verify` cohort. `cohort_config_hash` is the SHA-256 of the backend-independent logical inputs, not the backend-specific cache filename hash. `shared_rng_build_id` records the shared verification-RNG provenance when available and is all-zero for deterministic logical fallback transcripts. Cohort-level mismatch is meaningless for bit-equality and `verify` hard-fails with `AppError EngineEnvelopeMismatch CohortLevel ...`. Not overridable.
- **Per-backend-slot fields** (`engine_build_id`, `compiler_id`/`compiler_version`, `fp_flags`, `libm_id`, `cpu_features`, `fp_env`, plus informational `engine_git_commit`) legitimately differ across backends in a cohort — that's the whole point of cross-backend `verify`. They must match between a *cached transcript* and the *current live binary* for the same backend slot; per-backend-slot mismatch is the stale-cache case and `verify` hard-fails with `AppError EngineEnvelopeMismatch (BackendSlot b) ...`. Overridable by `--allow-stale` for forensic comparisons that knowingly accept envelope drift; `--format json` reports downgraded warnings under `warning_details`.

See [`documents/engineering/determinism_contract.md`](documents/engineering/determinism_contract.md) §Engine Envelope for the authoritative contract, [`documents/engineering/transcript_format.md`](documents/engineering/transcript_format.md) §Envelope Block for the wire format, and [`documents/engineering/backend_ffi_contract.md`](documents/engineering/backend_ffi_contract.md) §Engine Envelope Surface for the FFI capture protocol.

### Multi-backend replay

`mcts inspect replay` opens a transcript and renders a per-move equity overlay with one column per backend. The originator (the `backend` field in the transcript header) is marked with ★; other backends are computed lazily on first request and cached.

The cache layout is `<cache-root>/transcripts/<arch>/<sha>/<backend>-<build_label>.eq` — one sidecar `.eq` file per `(backend, build)` slot. Live envelopes use the first 16 hex characters of `engine_build_id` for the build label; logical in-process envelopes with an all-zero engine id use `<backend>-logical`. Multi-build cohabitation is automatic: a rebuild lands in a fresh cache slot, the old slot stays put for forensic reference. Pruning is explicit (`mcts inspect cache prune`).

On transcript open:

- The originator's `.eq` is read if it exists and its embedded envelope matches the live originator binary. Match → originator column populates instantly with the bit-equal originator equities. Mismatch or absent → user explicitly populates it (cursor on the originator column header, press `r`); the recomputed values are labelled with the persistent yellow `BUILD MISMATCH` banner.
- Other backends' columns stay `--` until the user requests them (`r`). Compute runs in the background; the column shows `…computing` until the FFI returns, then writes to `.eq` so subsequent opens are instant.
- Visits are shared across Q3-compatible steelman columns under `--rng cpp` (and any recompute mismatch inside that contract is surfaced loudly).

The full UX is documented in [`documents/engineering/cli_command_surface.md`](documents/engineering/cli_command_surface.md) §`mcts inspect replay` Multi-Backend Overlay.

### Architecture envelope

The project supports two host architectures: **amd64 Linux** and **arm64 Linux**. Bit-equality guarantees are per-architecture, not cross-architecture. Within a single architecture, every backend's determinism guarantees hold as documented above. Across architectures, the `c_param u64` IEEE-754 bit-cast is portable in shape (both arches are IEEE-754) but `libm`, FMA contraction, SIMD lowering, and denormal handling can differ. Cross-arch verify cohorts are therefore rejected instead of being treated as determinism evidence.

Every transcript header carries the `host_arch u8` field (see [transcript wire format](#cross-backend-verification) above). The transcript cache is partitioned by arch — the on-disk layout is `<cache-root>/transcripts/<arch>/<sha>.tr`, where `<arch>` is `amd64` or `arm64`. Verify subcommands reject mixed-arch cohorts at parse time with `AppError ArchEnvelopeMismatch`. See [`documents/engineering/determinism_contract.md`](documents/engineering/determinism_contract.md) §Architecture Envelope for the full contract.

### Draw rule

The game's terminal-state semantics differ between backend (i) and backends (ii)–(v). This is the only intentional behavioural divergence in the project.

- **Backend (i)** — `is_terminal()` ↔ `hero_wins() || villain_wins()` (verbatim from `MCTS_legacy/backend/core/board.cpp:247`). A game has no draw outcome; rollouts that exceed `MAX_ROLLOUT_ITERS = 10000` plies abort the search via an exception (the legacy's behaviour). Because (i) is the strictly verbatim regression-sanity port, it is excluded from cross-backend `verify` cohorts.
- **Backends (ii)–(v)** — `is_terminal()` ↔ `hero_wins() || villain_wins() || ply_count >= max_plies`. The board state carries a `uint16_t` ply counter. When termination is by ply cap, `get_terminal_eval()` returns `0.0` (draw); rollouts back this value up like any other terminal. UCT search uses `min 60 max_plies` as its deterministic leaf-rollout/tree horizon while the game transcript still records and obeys the run-level `max_plies`. The current C/Rust search ABI bakes in that 60-ply search horizon, so batch dispatch falls back to the in-process path for sub-60 `max_plies` runs until the ABI grows an explicit search-cap argument.

`max_plies` is a run-configuration parameter (default **200**), exposed on the CLI as `--max-plies N`, pinned in the transcript header (`max_plies u16`), and part of the determinism contract: two backends (ii)–(v) with the same `max_plies`, same seed, and same chosen sequence must produce identical determinism payloads.

The wire format's `winner u8` field is a 3-value enum: `0 = hero`, `1 = villain`, `2 = draw`. The decoder reports draws in `inspect show` / `inspect replay` as `<draw>` in the same position move notation otherwise occupies.

**Legacy parity envelope.** The new draw rule is the only thing keeping backend (i) out of the default cross-backend `verify` cohort. Setting `max_plies = MAX_ROLLOUT_ITERS = 10000` creates the envelope where backend (i) can be driven at its native no-draw horizon while the steelman engines retain a transcript-visible cap. `mcts verify legacy-parity` drives this cohort with `max_plies` and `--rng cpp` pinned, under a fixture seed chosen so that (i) never trips `MAX_ROLLOUT_ITERS`. This complements Q6: Q6 asks "does (i) reproduce `MCTS_legacy`?", while Q7 asks whether all five backend slots complete the legacy envelope without backend (i) overflow or envelope failure. Q7 intentionally does not require backend (i)'s legacy search tree to match the steelman visit vectors or chosen moves outside that envelope.

---

## Benchmarks

Two workloads define "fast enough":

- **(a) Random rollouts.** Pure stress test of the game engine: legal-move generation, move application, terminal detection. No tree, no UCT — just play random games end-to-end as fast as the engine allows.
- **(b) Adversarial MCTS self-play with rollout evaluations.** Full UCT search with random-rollout leaf evaluation, played as adversarial self-play. Exercises the engine, the tree representation, and the search policy together. Each game is single-threaded internally; in multi-threaded mode the workload is a batch of independent self-play games dispatched across `--workers N` workers, with each worker playing one game at a time.

The load-bearing performance benchmarks run the cross product of `{backend} × {single-threaded, multi-threaded}` under `--rng native`, reporting wall-clock time and throughput (games/sec, simulations/sec) from a single Cabal-driven measurement clock. That means every backend is measured with its own fast RNG. `--rng cpp` may be used for diagnostic overhead experiments, but those rows are not the performance comparison. The clock is `GHC.Clock.getMonotonicTimeNSec` (monotonic, ns-resolution), started inside the Haskell driver just before the first game is dispatched and stopped just after the last game returns through the FFI; all five backends are timed by the same clock so cross-backend numbers are directly comparable.

Backend (i)'s throughput is published for reference only and is **not on the same basis** as (ii)–(v) under any `max_plies` other than `MAX_ROLLOUT_ITERS = 10000`: (i) has no game-level ply cap (see [Draw rule](#draw-rule)), so its games run to a positional win and are on average longer than the ply-capped games of (ii)–(v). The load-bearing comparison in Q1/Q2 is Haskell vs (ii), where both backends terminate identically.

---

## `mcts test all`

The doctrine-mandatory canonical test command. `mcts test all` is the developer-facing entrypoint that proves whether the POC's hypotheses hold. It does four things, in order:

1. **Builds canonical backend artefacts.** The same short-lived container runs
   `mcts build cpp-legacy`, `mcts build cpp-imperative`,
   `mcts build cpp-functional`, and `mcts build rust` before any FFI-sensitive
   tests or report-card measurements.
2. **Delegates to `cabal test`.** Runs every `test-suite` stanza below, each
   `type: exitcode-stdio-1.0`, with `tasty` as the in-stanza runner.
3. **Executes a fixed POC report-card workload.** Q1/Q2/Q5 use bounded
   no-transcript native-RNG timing measurements over the pinned game counts, and
   Q3/Q7 use explicit C++-RNG `verify` cohorts.
4. **Prints a single tidy summary block** on stdout that answers the POC's
   headline questions (Q1–Q7 below) in one screenful.

Failure of any cabal stanza, any verify cohort, or any report-card measurement exits non-zero.

### Test-suite stanzas

Per doctrine §Test Organization, each tier is a separate cabal stanza:

| Stanza | Tier | Scope |
|---|---|---|
| `mcts-unit` | pure logic | engine invariants, parser tests (`execParserPure`), property/semantic tests for `CommandSpec` output and `inspect show` rendering, transcript codec roundtrips using in-memory or temporary data, RNG mixer properties |
| `mcts-integration` | subprocess | exercises the real `mcts` binary across the FFI to every backend; same-backend determinism (same seed and logical game inputs ⇒ same determinism payloads, three seeds per backend); decoded real-binary transcript determinism generated during the test run; bounded report-card divergence and cached recompute-sidecar checks using temporary cache roots; live-envelope stamping/stale-cache coverage when foreign shared libraries are present |
| `mcts-cross-backend` | round-robin verify | real `mcts verify` subprocesses for the live FFI-capable `--rng cpp` cohort covering backends (ii), (iii), (iv), (v); backend (i) excluded by the `VerifyBackend` type; test cases run serially around the process-pinned foreign-library and C++ RNG bridge path |
| `mcts-legacy-parity` | legacy-envelope verify | live FFI-capable `verify legacy-parity` across all five backend slots with `max_plies = 10000` pinned and a fixture seed; Q7 checks liveness/overflow rather than backend (i)-vs-steelman visit-vector equality |
| `mcts-haskell-style` | lint | pinned style-tool `fourmolu --mode check`, `hlint --with-group=default --with-group=extra + .hlint.yaml` with only `Error:` findings blocking, `cabal format` round-trip equality |

A single `tasty` tree spanning all tiers is forbidden by doctrine; the stanza split gives Cabal-native parallelism and lets contributors target one tier (`docker compose run --rm mcts mcts test mcts-unit`).

### POC headline questions

The report-card workload runs *after* `cabal test` succeeds and answers:

1. **Q1.** Does pure Haskell match maximally-optimised C++ (backend ii) on benchmark (a) random rollouts, single-threaded and on 8 workers?
2. **Q2.** Does pure Haskell match backend (ii) on benchmark (b) self-play, single-threaded and on 8 workers?
3. **Q3.** Do backend slots (ii), (iii), (iv), (v) produce bit-for-bit identical determinism payloads under `--rng cpp` (round-robin verify on both rollouts and self-play)?
4. **Q4.** Does same-backend determinism hold across runs (same backend, same seed, same logical game inputs ⇒ identical determinism payloads) for every backend?
5. **Q5.** How does each backend scale from `--threading single` to `--threading multi --workers 8`? The text summary block highlights Haskell and C++ (ii) as the two anchors; JSON exposes the full per-backend scaling table.
6. **Q6.** Does the verbatim port (i) faithfully reproduce `MCTS_legacy` on benchmark (b)?
7. **Q7.** Can all five backend slots complete the legacy-parity envelope (`max_plies = 10000`, fixture seed where live (i) does not throw) without overflow or envelope errors?

### Report-card workload

A fixed, deterministic battery, identical across hosts. `mcts test all` measures
Q1/Q2/Q5 internally with the same inputs as `mcts bench` but deliberately does
not retain or write the 100k-game transcript batches; the standalone `bench`
commands remain the operator-facing way to generate comparable ad hoc wall-clock
numbers and cache transcripts for smaller inspection runs. The explicit
subprocess plan covers the deterministic verification cohorts:

```bash
# Q3 — cross-backend determinism, backend (i) excluded by the VerifyBackend type
docker compose run --rm mcts mcts verify rollouts \
    --backend cpp-imperative,cpp-functional,rust,haskell \
    --threading single --games $G_V --seed 42 --max-plies 200
docker compose run --rm mcts mcts verify selfplay \
    --backend cpp-imperative,cpp-functional,rust,haskell \
    --threading single --games $G_V --seed 42 --max-plies 200 --sims $S_VERIFY

# Q7 — legacy parity, all five backends, max_plies and RNG pinned by the subcommand
docker compose run --rm mcts mcts verify legacy-parity selfplay \
    --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell \
    --games $G_LP --seed $S_LP --sims $S_LP_SIMS
```

Game counts (`$G_R`, `$G_S`, `$G_V`, `$G_LP`), per-move sim budgets (`$S_BENCH`, `$S_VERIFY`, `$S_LP_SIMS`), and the legacy-parity seed (`$S_LP`) are implemented in `MCTS.CLI.Test` and mirrored in `cabal.project` comments. The pinned values are: `G_R = 1_000`, `G_S = 4`, `G_V = 4`, `G_LP = 2`, `S_BENCH = 500`, `S_VERIFY = 500`, `S_LP_SIMS = 10_000`, `S_LP = 42`. `mcts test all` measures Q1/Q2/Q5 with the production monotonic clock through `runBatchNoWriteDispatch`, uses native RNG for headline throughput rows, and requires canonical backend artefacts built earlier in the same container. Q3/Q7 use `runBatchDispatch` under `--rng cpp`, so the headline determinism rows exercise live FFI engines when cdylibs are present and fall back to the in-process runner only when needed for self-contained local stanzas. Q3 compares nonzero visit vectors for backends (ii)..(v). Q7 is a legacy-envelope liveness/overflow gate for all five backend slots; it intentionally does not require the steelman engines to reproduce backend (i)'s tree visit counts or chosen moves outside the envelope. Q4 (same-backend determinism) is covered by the `mcts-integration` stanza, including decoded real-binary transcript determinism generated during the test run. Q6 decodes backend (i) evidence generated during the test run or under an explicit temporary artifact root, not checked-in transcript fixtures.

### Tidy summary block

Rendered to stdout at the end of `mcts test all`. The block below is a
constructed renderer fixture for the semantic renderer assertions; live runs
replace the logical-baseline ratio fields with measured throughput ratios and
render `Verdict: Within tolerance` when the parity gate passes.

```
MCTS POC report card - seed=42, max-plies=200, host=amd64, ghc=9.14.1
------------------------------------------------------------------------
Q1  Haskell vs live C++ (ii) rollouts  ST      1.00x   (logical baseline)
Q1  Haskell vs live C++ (ii) rollouts  MT8     1.00x   (logical baseline)
Q2  Haskell vs live C++ (ii) self-play ST      1.00x   (logical baseline)
Q2  Haskell vs live C++ (ii) self-play MT8     1.00x   (logical baseline)
Q3  Cross-backend determinism  (cpp RNG)       PASS    ((ii)..(v), 4 backends agree)
Q4  Same-backend determinism   (per backend)   PASS    (5/5 backends x 3 seeds)
Q5  MT scaling  Haskell   1->8 workers         1.00x   (logical baseline)
Q5  MT scaling  C++ (ii)  1->8 workers         1.00x   (logical baseline)
Q6  Legacy port (i) vs MCTS_legacy             HIST    (external audit evidence)
Q7  Legacy envelope across all backends         PASS    (all five backend slots live)

Divergence matrix (visit/move, cpp RNG; thresholds native 0.050/0.005, cross-build 0.010/0.001)
cpp-imperative  0.0000/0.0000  0.0000/0.0000  0.0000/0.0000  0.0000/0.0000
cpp-functional  0.0000/0.0000  0.0000/0.0000  0.0000/0.0000  0.0000/0.0000
rust            0.0000/0.0000  0.0000/0.0000  0.0000/0.0000  0.0000/0.0000
haskell         0.0000/0.0000  0.0000/0.0000  0.0000/0.0000  0.0000/0.0000

cabal test                                     PASS    (mcts-unit, mcts-integration,
                                                        mcts-cross-backend, mcts-legacy-parity,
                                                        mcts-haskell-style)

Verdict: Evidence pending (logical baseline; performance parity evidence pending)
```

The same data is available as `mcts test all --format json` for CI consumption; both formats are rendered by the same pure function over a typed `ReportCard` value. Rendering precision is fixed: ratios render to fixed precision (e.g. `2.88x`), throughputs to one decimal place (e.g. `531.4 games/s`). No timestamps, no locale-dependent ordering, no terminal-width-dependent wrapping. Wall-clock numbers are the only non-deterministic content; renderer tests assert structure and field semantics directly rather than reading checked-in snapshot files.

### Doctrine compliance

- **Plan / Apply.** `mcts test all` is a Plan/Apply command. `build :: TestInputs -> Either AppError TestPlan` produces the typed list of canonical backend builds, Cabal stanzas, and verify subprocesses (modelled per doctrine §Subprocesses as Typed Values); `apply :: Env -> TestPlan -> IO ExitCode` runs it before the measured report-card builder renders Q1/Q2/Q5 and the divergence rows. `--dry-run` prints the rendered plan and exits 0; `--plan-file <path>` writes the rendered plan for out-of-band review.
- **Prerequisites.** All five backend artifacts present, PGO+BOLT profiles populated, `mimalloc` linked, GHC/Cabal pinned versions on the container `PATH` — encoded as one `prerequisiteRegistry` per doctrine §Prerequisites as Typed Effects. The transitive closure runs before `apply`; a single unmet node aborts with `AppError PrerequisiteUnmet` carrying the failing `nodeId`, description, and remedy hint.
- **Determinism.** The summary block is rendered by a pure function of a typed `ReportCard` value. No timestamps, no locale-dependent ordering, no terminal-width-dependent wrapping. Wall-clock numbers are the only non-deterministic content and are rendered to fixed precision for ratios and one decimal place for throughputs. Tests assert renderer structure and sentinel substitution in memory; they do not depend on checked-in generated baselines.

---

## Tree persistence and determinism

One non-negotiable feature inherited from the legacy implementation:

- **Visits persist across moves.** When a move is played, the chosen child becomes the new root and its accumulated visits are kept; the rest of the tree is discarded incrementally. The next search starts warm. Tree persistence is per-game; in multi-threaded batches multiple per-game trees live concurrently in memory, each independent — there is never more than one thread touching a given tree.
- **Trees are memory-resident only.** Nothing is serialised; persistence between runs is not a goal.
- **Trees are losslessly recoverable.** Because Monte Carlo draws are seeded deterministically, any tree state is reproducible by replaying the seed and move sequence. This is what justifies keeping the tree in memory only.
- **Incremental truncation is a memory-management lever**, not a correctness concern. The shape of the tree at any given moment is an optimisation; the visits it represents are reproducible from the seed.

---

## CLI command topology

Following [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md), commands are modelled as ordinary Haskell data types and the parser is generated from a separate `CommandSpec`. The live source of truth is `src/MCTS/CLI/Spec.hs`, with concrete command ADTs in `src/MCTS/CLI/Command.hs` and the `optparse-applicative` parser rendered in `src/MCTS/CLI/Parser.hs`. Generated command artefacts under `documents/cli/`, `share/man/man1/`, and `share/completion/` derive from that same registry.

This README is intentionally operator-facing: it names the project intent, verification model, and common invocations, but it does not duplicate the full command ADT cascade. Use `mcts commands --tree` for the current command tree, `mcts commands --json` for the stable machine-readable schema, and [`documents/engineering/cli_command_surface.md`](documents/engineering/cli_command_surface.md) for the generated command matrix and flag reference.

Concrete invocations:

```bash
# (a) Random rollouts, all five backends, single-threaded, native RNG, 100k games
docker compose run --rm mcts mcts bench rollouts \
    --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell \
    --threading single --rng native --games 100000 --seed 42

# (b) Self-play, multi-threaded with 8 workers (default), native RNG
docker compose run --rm mcts mcts bench selfplay \
    --backend haskell --rng native --games 1000 --seed 42 --sims 10000

# Same as above on 32 workers
docker compose run --rm mcts mcts bench selfplay \
    --backend haskell --rng native --workers 32 --games 1000 --seed 42 --sims 10000

# Cross-backend determinism check: C++-RNG cohort
docker compose run --rm mcts mcts verify selfplay \
    --backend cpp-imperative,cpp-functional,rust,haskell \
    --threading single --games 50 --seed 42 --max-plies 200 --sims 10000

# Interactive game: human plays hero against the haskell backend, 10k sims/move
docker compose run --rm mcts mcts play --backend haskell --side hero \
    --rng native --max-plies 200 --sims 10000

# Backend-vs-backend spectate (no human input; watch a self-play game render live)
docker compose run --rm mcts mcts play --backend haskell --side villain --vs cpp-imperative \
    --rng native --max-plies 200 --sims 10000

# What's in my local transcript cache?
docker compose run --rm mcts mcts inspect list

# Dump a stored transcript with equities recomputed (slow; opt-in)
docker compose run --rm mcts mcts inspect show 7a2f --top 10 --with-equity

# Interactive replay: navigate forward/back through a stored game
docker compose run --rm mcts mcts inspect replay 7a2f --top 15

# Doctrine-alignment gate: lint files + docs + haskell, then the container-owned warning-clean build
docker compose run --rm mcts mcts check-code

# Build the live foreign backend's optimised library (Plan/Apply: PGO instrument → train → re-build → BOLT → mimalloc link)
docker compose run --rm mcts mcts build rust --dry-run
docker compose run --rm mcts mcts build rust
```

The `verify` subtree pins `--rng cpp`, drives every requested backend over the same seed and same move sequence, and round-robin-compares their decoded determinism payloads (see [Cross-backend verification](#cross-backend-verification) above). Same-backend determinism tests live alongside as `tasty` cases under the `mcts-integration` stanza (see [`mcts test all`](#mcts-test-all)).

`mcts check-code` is the canonical doctrine-alignment gate: it dispatches `mcts lint files`, `mcts lint docs`, `mcts lint haskell`, then the container-owned warning-clean build step, and fails if any step is non-clean. `mcts build <backend>` is a Plan/Apply harness per doctrine §Subprocesses as Typed Values; `--dry-run` and `--plan-file <path>` apply identically to the way they do on [`mcts test all`](#mcts-test-all).

### Progressive introspection

Per doctrine §Progressive Introspection, the CLI exposes:

```bash
docker compose run --rm mcts mcts commands
docker compose run --rm mcts mcts commands --tree
docker compose run --rm mcts mcts commands --json
docker compose run --rm mcts mcts help <subcommand>
```

`mcts commands --json` is the externally-stable interface; the human-readable forms are derived from the same `CommandSpec` value.

### Output and error discipline

Per doctrine §Output Rules and §Error Handling: stdout carries primary output, stderr carries diagnostics. The non-TUI commands (`bench`, `verify`, `test`, `inspect list`, `inspect show`, `inspect cache list`, `inspect cache prune`, `inspect divergence`, `commands`, `help`, `lint`, `docs`) accept `--format json|table|plain` (default `table` on a TTY, `plain` otherwise) and the standard `--color auto|always|never` / `--no-color` flags. The TUI commands (`play`, `inspect replay`) own their own rendering and ignore both. Errors render through a single `AppError` ADT at the CLI boundary — `AppError TranscriptNotFound`, `AppError TranscriptAmbiguous`, `AppError TranscriptFormatUnsupported`, `AppError VerifyMismatch`, `AppError VerifyLengthMismatch`, `AppError VerifyTerminatorMismatch`, `AppError VerifyCohortTooSmall`, `AppError RecomputeMismatch`, `AppError LegacyParityRolloutOverflow`, `AppError ArchEnvelopeMismatch`, `AppError EngineEnvelopeMismatch`, `AppError PrerequisiteUnmet`, `AppError SubprocessFailed`, `AppError FFIFailure`, `AppError DocsCheckDrift`, `AppError UnknownCommand`, `AppError InvalidMove`, `AppError ParseError`, `AppError IOErrorText` — and never leak onto stdout. `SubprocessFailed` is the typed-`Subprocess` boundary's failure surface (`runStreaming` / `capture` non-zero exit), `FFIFailure` is the C ABI bridge's surface (foreign call raised or returned an error sentinel), `DocsCheckDrift` is what `mcts docs check` raises when a marker region's on-disk content disagrees with the renderer, and `EngineEnvelopeMismatch` is raised by `verify` when the layered envelope check (cohort-invariant fields across the cohort, per-backend-slot fields against the live binary) finds a disagreement — see [Engine envelope](#engine-envelope) above.

### Doctrine scope

This project adopts the following sections of `HASKELL_CLI_TOOL.md` as binding: Command Topology, CommandSpec + Generated Artifacts (marker discipline, paired check/write, `forbiddenPathRegistry`), Progressive Introspection, Subprocesses as Typed Values (the PGO+BOLT build harness invokes `g++`, `rustc`, `llvm-bolt` through the typed `Subprocess` boundary), Plan/Apply (notably for `mcts test all` and the build harness, with `--dry-run` and `--plan-file <path>` on every Plan/Apply command), Prerequisites as Typed Effects (toolchain prereqs across all five backends, encoded as one `prerequisiteRegistry`), Application Environment (`ReaderT Env IO` with a single `Env` record), Lint, Format, and Code-Quality Stack (`fourmolu` + `hlint` + `cabal format`, with `fourmolu.yaml` committed at repo root and the `mcts-haskell-style` test-suite), Testing Doctrine and Test Organization (one `test-suite` stanza per tier), Output Rules, Error Handling, and GADT-indexed state machines where naturally indicated. The project also treats repository `.sh` scripts and `bootstrap/` helpers as forbidden workflow surfaces; supported work enters through `docker compose run --rm mcts mcts <command>`.

Explicitly **out of scope**: Long-Running Daemons in the Same Binary (the CLI is short-running only — this also covers the daemon-internal "Configuration: Dhall file with mandatory hot reload" subsection), Capability Classes and Service Errors (no external subsystems), Retry Policy as First-Class Values (no external subsystems), At-Least-Once Event Processing (no event stream), Reconcilers: Idempotent Mutation as a Single Command (no managed state in the world), Smart Constructors for Paired Resources (no paired resources), and Pulumi-Orchestrated Infrastructure Tests (no cloud surface). These sections of `HASKELL_CLI_TOOL.md` are read as informational context, not as binding constraints on this project.

The `forbiddenPathRegistry` defaults, the per-artifact lint subcommands (`mcts lint files|docs|haskell|all`), and the doctrine-alignment gate `mcts check-code` are elaborated in [`documents/engineering/code_quality.md`](documents/engineering/code_quality.md).

---

## Interactive modes

`play` and `inspect replay` are full-screen TUIs built on `brick` over `vty`. Layouts are declarative; redraws happen on event-loop ticks, not on every keystroke. `inspect show` and `inspect list` are plain non-interactive output. All four modes use the legacy move notation (`*(x,y)`, `H(x,y)`, `V(x,y)`) inherited from `MCTS_legacy`.

**Doctrine alignment.** The interactive surfaces add `brick` and `vty` to the doctrine's standard stack; this is the only deviation from the `HASKELL_CLI_TOOL.md` stack list and applies to no other command. The TUI commands (`play`, `inspect replay`) own their own rendering and do not honour the `--format` / `--color` flags from [Output and error discipline](#output-and-error-discipline) — those apply to the non-interactive `inspect list` and `inspect show` only. Errors in all four modes render through the same `AppError` ADT and `renderError` boundary used by the rest of the CLI, never written to stdout.

**Hash-prefix lookup.** `<hash-prefix>` arguments to `inspect show` and `inspect replay` use git-style resolution: the shortest prefix that uniquely identifies a transcript is accepted, minimum 4 hex chars. On no match: exit non-zero with `AppError TranscriptNotFound`. On multi-match: exit non-zero with `AppError TranscriptAmbiguous` carrying the list of candidate hashes so the operator can re-issue with a longer prefix.

**Cache root.** The transcript cache root resolves to `--cache-dir <path>` if given, else `./.mcts-cache/` resolved against the current working directory inside the container. The `mcts` binary does not read a cache-root environment variable. The on-disk layout under that root is `transcripts/<arch>/<sha>.tr` (where `<arch>` is `amd64` or `arm64` per [Architecture envelope](#architecture-envelope)); this is the `.mcts-cache/transcripts/<arch>/` directory referenced throughout the rest of this document.

**`play`** — interactive game against any backend. Left pane shows the Corridors board; the right pane carries whose turn it is, move count, last move played, and status text. The side named by `--side` runs MCTS through `--backend` under `--sims`, `--rng`, `--seed`, and `--max-plies`; without `--vs`, the human controls the opposite side and manual input is rejected while the AI is to move. With `--vs <backend>`, `--backend` controls the side named by `--side`, the `--vs` backend controls the opposite side, and the human is a spectator who advances AI turns with Space.

In-app prompt grammar. Lines beginning with `:` are commands; everything else is parsed as a move in legacy notation. Recognised commands:

- `:hint` — show the top-N moves the AI would consider for the side currently to play.
- `:undo` — back up one ply; supported by an in-memory stack of MCTS states.
- `:save` — flush the partial game as a transcript to the cache root. Hand-played transcripts are addressed by `sha256(run_config || move_history)` (where `||` denotes byte concatenation) rather than `sha256(run_config)` alone, because the human's move choices make the post-config bytes non-deterministic.
- `:quit` — exit. The final transcript is written automatically when the game ends.

Any other `:`-prefixed input renders an `AppError UnknownCommand` to the status bar and leaves game state untouched. Malformed move notation renders an `AppError InvalidMove` similarly. `Ctrl-C` during the AI's turn cancels the in-progress search and returns control to the prompt; `Ctrl-C` at the prompt is equivalent to `:quit`. All four error renderings go through the same `renderError` boundary the non-interactive commands use.

**`inspect list`** — non-interactive. Scans `<cache-root>/transcripts/<arch>/*.tr` for the current host arch, decodes each header, prints one line per per-game transcript: short hash (first 8 chars), backend, game id, master seed, threading (`ST` or `MT8`), sims, total moves, mtime. Sorted by mtime descending. Honours `--format json|table|plain`.

**`inspect show <hash-prefix>`** — non-interactive dump in legacy notation. Header summary followed by per-move records:

```
Move N (hero|villain): *(4,2)
    *(4,2)  visits=3401
    *(3,2)  visits=2105
    ...
```

Default `--top 10`; `--top 0` shows all legal moves. With `--with-equity`, the command first reads an envelope-matched originator `.eq` sidecar when present; on a miss or stale envelope, it re-runs the deterministic search, writes a fresh sidecar, and emits an `equity=...` column on every line.

**`inspect replay <hash-prefix>`** — interactive brick TUI for navigating a stored game.

- Layout: board on the left; on the right, a context panel with the current move index, the move actually played, and the top-N legal-move list (visits, equity, action). Status line at the bottom: `<hash> | move M / total | press ? for help`.
- Keybinds: `→` / `l` next move, `←` / `h` prev move, `Home` / `End` jump to start / end, `g` opens a "jump to move N" prompt, `+` / `-` adjust the top-N cutoff live, `?` toggles a keybind overlay, `q` quits.
- **Equity is recomputed on the fly.** Equities and alternative moves are not stored in the transcript — that omission is by design (the transcript wire format excludes floats to keep its hash byte-exact). When navigating to move M, the replay engine reconstructs the game state by replaying moves 0..M-1 with the persistent tree carried forward as in the original search, runs move M's search using the seed and budget from the transcript header, then reads sorted actions back from the tree through the instrumentation interface (FFI for backends (i)–(iv), a direct module call for (v)). The visit counts produced must equal the transcript record byte-for-byte; this doubles as a built-in determinism check that fires on every navigation. Equity is derived from the same search's value backups. The cross-language determinism guarantee in [Cross-backend verification](#cross-backend-verification) is what makes this recompute trustworthy.
- **State caching.** The last `replayCacheStates` MCTS states (default 20, `--cache-states N`) are kept in memory so back-navigation past those is incremental. Eviction is LRU on the cached-state map; jumping past the cache window triggers a forward re-replay from the nearest earlier cached state, not always from move 0. For typical game lengths (60 moves × 10k sims) this is seconds, not minutes.

---

## First milestone

The first concrete deliverable is the **Cabal-centric benchmark harness** described by the CLI topology above:

- `mcts bench rollouts` and `mcts bench selfplay` running across all five backends, both threading modes, and both RNG sources where applicable.
- `mcts verify rollouts` and `mcts verify selfplay` enforcing cross-backend determinism under the shared C++ RNG byte contract.
- All measurements taken from a single Cabal-driven clock; backends (i), (ii), (iii), and (iv) reached through the FFI from the same Haskell process, with (v) Haskell running natively in that same process.
- No ANN evaluation. No Python. No web frontend. Just engine, rollouts, MCTS, numbers.

The C++ backends are not stepping stones to delete. Backend (i) proves the
legacy port is faithful, backend (ii) is the maximally optimised performance
target, backend (iii) isolates functional style inside C++, backend (iv) is a
cross-language systems implementation, and backend (v) is the pure Haskell
target. The project succeeds only if these backends remain comparable through the
same CLI, the same measurement clock, and the same C++-RNG equivalence harness.

---

## Build and run

The project ships `docker/Dockerfile` and a root-level `compose.yaml`
(inspired by `MCTS_legacy/docker/`) so the toolchain and installed `mcts`
binary are reproducible. All supported development, validation, formatting,
linting, benchmark, and backend build work enters through this host command
shape:

```bash
docker compose run --rm mcts mcts <command>
```

There is no long-running project daemon. `docker compose up` is not part of the
workflow, and the Compose service intentionally has no bind mount, no
environment-variable block, and no `sleep infinity` placeholder. The first
`docker compose run --rm` invocation builds the image when it is absent; source
and build artefacts then live inside that container image and its short-lived
runtime filesystem. Host-level toolchain fallback is unsupported; in particular,
Fourmolu and HLint must never be taken from the host `PATH`. A host-level
`.build/` directory is unsupported residue under this policy. Runtime project
configuration is expressed with CLI flags, not application-specific environment
variables read by the `mcts` binary. Repository shell-script wrappers are also
unsupported: no `.sh` script or `bootstrap/` helper may substitute for the
Compose entrypoint above.

- **Base:** `ubuntu:24.04`
- **C++:** latest stable GCC shipped with 24.04, C++23 enabled (GCC only — Clang is not supported). LLVM/BOLT pinned in the Dockerfile for the post-link reordering step (see [Compiler and runtime tuning](#compiler-and-runtime-tuning)). GHC's `-fllvm` backend (used for the Haskell engine) shares this same pinned LLVM, so the container carries one LLVM version regardless of which language is being compiled — the C++ toolchain itself remains GCC.
- **Rust:** latest stable, installed via `rustup`; minor version pinned in the Dockerfile.
- **Haskell:** `ghcup`-managed, pinned to **GHC 9.14.1** and **Cabal 3.16.1.0** (per `HASKELL_CLI_TOOL.md`). LLVM toolchain pinned for GHC's `-fllvm` backend — the same LLVM version used by BOLT, so the container only carries one.
- **Haskell style tools:** the container installs Fourmolu and HLint into
  `/opt/mcts-style-tools/bin/` with a separate pinned formatter-tools compiler,
  **GHC 9.12.4**. The main project remains pinned to GHC 9.14.1; the style
  compiler exists only to make `fourmolu-0.19.0.1` and `hlint-3.10`
  reproducible while their parser dependencies track a different GHC API
  window.

```bash
docker compose run --rm mcts mcts check-code
docker compose run --rm mcts mcts test all
docker compose run --rm mcts mcts bench rollouts --backend haskell --threading single --rng native --games 100000 --seed 42
```

The Haskell CLI follows the conventions in [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md) where they apply:

- Library-first layout (`app/Main.hs` is a thin entry point; logic lives in `src/`).
- Commands modelled as Haskell ADTs; `optparse-applicative` parser generated from a separate `CommandSpec`.
- `tasty` (+ `tasty-hunit`, `tasty-quickcheck`, `temporary`) for tests, partitioned into the `test-suite` stanzas listed in [`mcts test all`](#mcts-test-all). Project tests do not require checked-in golden data; any generated transcripts, sidecars, or renderer baselines are created inside temporary directories during the run.
- `brick` + `vty` for the interactive TUI screens (`play`, `inspect replay`); pure terminal, no graphical dependencies. This is the only addition to the doctrine's standard stack.
- `fourmolu` + `hlint` + `cabal format` as the code-quality stack, with
  `fourmolu.yaml` committed at repo root; the policy invocation path for
  Fourmolu/HLint is the container-owned `/opt/mcts-style-tools/bin/`, and the
  gate is exposed both as `mcts lint haskell` and as the
  `mcts-haskell-style` test-suite. Host `PATH` fallback and environment-variable
  overrides are not supported.
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
-fno-exceptions
```

`-fno-exceptions` is mandatory: the engine core does not throw, so landing-pad cost is unconditional dead weight.

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

*Native-RNG benchmark only* (not under `--rng cpp`, which is pinned to the C++-generated verification-seed contract by the determinism contract):

15. Future native-RNG profiling candidate: replace the current splitmix-compatible live schedule with `xoshiro256++` or `wyrand` where it measurably helps — smaller state, faster `next_u64`, equivalent statistical quality for rollouts.

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

LLVM codegen is active through `-fllvm`, with the LLVM version pinned in the
Dockerfile so codegen is reproducible. The doctrine target allows native CPU
tuning through `-optlo-mcpu=native` and `-optlc-mcpu=native`, but the current
implementation intentionally excludes those two flags because the pinned
aarch64 container can emit LSE instructions that the assembler rejects.

RTS tuning, baked into the executable's `ghc-options`:

```
-with-rtsopts=-A64m -n4m -qg1 -qb -T
```

Large nursery to push major GC out, `-qg1` so major GC is parallel from gen 1, `-qb` for load balancing across capabilities, `-T` to expose GC stats for `+RTS -s` profiling.

Code-level requirements:

- **Ply counter in board state** (correctness — see [Draw rule](#draw-rule)). Board carries a `Word16` ply counter; `isTerminal` returns true on `ply >= maxPlies` with eval `0.0`. Lives in the same unboxed board record as the bitboards; restored as part of the per-rollout `ST`-arena snapshot path.
- Engine hot path lives in `ST s`. The current tree is a structure-of-arrays
  `STUArray` arena of unboxed `Int32` / `Float` fields; a hand-rolled
  `MutableByteArray#` migration remains profile-driven and is not required by
  the measured baseline.
- Board state is `Word64` bitboards, manipulated with `Data.Bits` under the
  active `-fllvm` backend. Extra native LLVM CPU flags remain deferred as
  described above.
- Strict fields everywhere (`{-# UNPACK #-} !Int`), bang patterns on `let` bindings inside `ST` blocks.
- `INLINABLE` on the exported engine primitives and search hot path.
  `SPECIALIZE` pragmas are not needed while the search loop is monomorphic over
  the concrete `Board` and `Word64` types.
- Pure API boundary: the driver calls `uctSearch` / `uctSearchWithEquity` with
  a `Board`, seed, search budget, and ply cap, then receives the chosen action
  plus visit/equity streams. Tree persistence remains internal to the arena
  boundary if future profiling requires it.
- No `Maybe` or `Either` in the rollout inner loop; sentinel values or unboxed sum representations instead.

### One known asymmetry: PGO

GHC 9.14 has no production-grade profile-guided optimisation comparable to GCC/Clang `-fprofile-use` or `rustc -Cprofile-use`. The Haskell backend therefore competes against PGO+BOLT-optimised C++ and Rust without an equivalent feedback loop. This is the asymmetry that most concretely tests the hypothesis: if Haskell matches under these conditions, the result is meaningful; if it falls short by 5–15%, that gap is plausibly attributable to the missing PGO loop rather than to any property of pure functional code per se. We document this rather than paper over it.

---

## Game: Corridors

Corridors is a two-player race game on a 9×9 board. Each player tries to reach the opposite edge while spending a finite supply of walls to obstruct the opponent. Walls cannot fully enclose either player. The verifier cohort uses a simplified rules subset: adjacent unoccupied pawn moves only, no jump moves, walls cannot overlap or cross, and each wall placement must leave both players with a path.

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
  bench/               -- Cabal benchmark target (mcts-criterion / Criterion)
  test/                -- deterministic, property, integration, and cross-backend tests
                       --   no checked-in generated transcripts or golden data
  docker/              -- Dockerfile
  compose.yaml         -- root-level Docker Compose entrypoint
  cabal.project        -- toolchain pin, report-card constant comments
  fourmolu.yaml        -- formatter config (per HASKELL_CLI_TOOL.md)
  DEVELOPMENT_PLAN/    -- authoritative execution-ordered development plan
  documents/           -- documentation standards and project-specific engineering elaborations
  README.md            -- this file
  LICENCE              -- project license
  HASKELL_CLI_TOOL.md  -- Haskell project conventions
  AGENTS.md / CLAUDE.md -- agent guardrails
```

This layout is the target; not all directories exist yet.

---

## License

See [`LICENCE`](LICENCE).
