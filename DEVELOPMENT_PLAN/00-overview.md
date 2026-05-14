# MCTS Development Plan — Overview

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md),
[phase-2-transcript-codec-and-determinism.md](phase-2-transcript-codec-and-determinism.md),
[phase-3-haskell-engine.md](phase-3-haskell-engine.md),
[phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md),
[phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md),
[phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md),
[phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md),
[phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Capture the target architecture, current baseline, doctrine scope,
> hard constraints, and dependency chain that every MCTS phase depends on.

## Vision

The MCTS runtime is the successor to `MCTS_legacy` and must satisfy three properties
simultaneously:

- **As fast as maximally-optimised imperative C++** on the two POC workloads (random
  rollouts and self-play). The bar is not the legacy as it exists today — it is the
  strongest imperative-C++ implementation the project can build using every reasonable
  modern technique (LTO, two-stage PGO, BOLT post-link, `mimalloc`, arena-allocated tree
  nodes, scratch-board rollouts, branch hints). Backend (ii) is that ceiling; backend (v)
  Haskell must match it.
- **Purely functional at the API surface** in its final form, so algorithmic changes
  (search policies, evaluators, prior shaping) are local edits rather than rewrites.
  Internally the Haskell engine is free to use `ST`-monad mutable unboxed arrays as the
  only realistic way to match optimised imperative C++; the local-reasoning property is
  preserved by keeping public types and operations pure.
- **Bit-for-bit deterministic.** Given a seed, an RNG source, and a sequence of moves,
  every implementation produces identical visit counts, identical action orderings, and
  identical rollouts — within an architecture envelope and an engine-build envelope (see
  Hard Constraint 36 below and the **Engine Envelope** section in
  [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md)).
  Reproducibility is a first-class invariant, not a debugging aid; the engine envelope
  captured in every transcript lets `inspect replay` and `mcts verify` detect substrate
  drift rather than silently displaying ULP-shifted floats as if they were the
  originator's.

**Long-term horizon (out of scope for this plan).** The project
[../README.md](../README.md) declares an eventual AlphaZero-style ANN evaluation goal.
Phases `0`–`8` own the rollout-based MCTS hypothesis only; no ANN, no learned
evaluator, and no Python ML stack appears on the supported path. The retirement
protocol's frozen golden anchors (Phase `8`) leave the door open for a successor
effort to inherit a parity-proven Haskell engine; that work is a future plan, not a
deliverable here.

## Target Outcome

One `mcts` Haskell CLI binary, built by Cabal under GHC `9.14.1` and Cabal `3.16.1.0`,
drives five backends behind a uniform command surface: backend (i) `cpp-legacy/` is a
strictly verbatim re-port of `MCTS_legacy` exposed via a C ABI through the Haskell FFI;
backends (ii) `cpp-imperative/` and (iii) `cpp-functional/` are maximally-tuned modern
C++23 implementations under the same PGO+BOLT+`mimalloc` optimisation stack; backend (iv)
`rust/` is an independent cross-language baseline; backend (v) is the pure Haskell engine
running natively in the same process, with `ST`-monad mutable arena internally and pure
search API externally.

Two POC benchmark workloads exercise the cohort: (a) random rollouts and (b) adversarial
MCTS self-play with rollout evaluations. Each runs single-threaded and on 8 workers under
both `--rng native` (each backend's fastest defensible RNG) and `--rng cpp` (all backends
draw from a shared `std::mt19937_64` through the FFI). `mcts verify` round-robin-compares
visit counts under `--rng cpp` across the four-backend cohort `(ii)..(v)`, with backend
(i) excluded by the `VerifyBackend` type because its terminal-state semantics differ;
`mcts verify legacy-parity` pins `max_plies = 10000` and a fixture seed so all five
backends agree under the envelope where the legacy port does not throw. `mcts test all`
emits the tidy POC report-card summary block answering Q1–Q7 in one screenful, with all
report-card knobs pinned in `cabal.project`.

Following the retirement protocol, backend (i) retires once it has demonstrated faithful
reproduction of `MCTS_legacy` (Q6 closure), backend (ii) retires once functional-style
C++ (iii) demonstrates parity with imperative C++, and backend (iii) retires once pure
Haskell (v) demonstrates parity with functional C++. Each retiring backend's transcripts
and throughput numbers freeze in `test/golden/` as the regression anchor for the
surviving cohort. Backend (iv) Rust remains live throughout as a long-running
cross-language second opinion.

## Architecture Overview

- **Haskell CLI surface.** One binary `mcts`. The parser is generated from a separate
  `CommandSpec` registry — never the source of truth. The same registry feeds the parser,
  the command tree (`mcts commands --tree`), the JSON command schema (`mcts commands
  --json`), the markdown command reference, the manpages, and the shell completion
  scripts. The library-first layout puts `app/Main.hs` thin and logic in `src/MCTS/`.
  Owned by [phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md).
- **Transcript codec, RNG, determinism contract.** The transcript wire format is
  little-endian binary with no schema-library dependency: header carrying the run config,
  per-move records of `(action_id, visits)` sorted ascending by action ID, and no stored
  equity floats. An engine-envelope block follows the fixed header (excluded from the
  backend-specific `sha256(RunConfig)` cache key) so substrate drift is detectable on
  replay; equity is cached lazily per `(backend, build)` in a sidecar `.eq` directory
  next to the `.tr`. The canonical single-byte action enumeration covers all legal
  Corridors actions (pawn moves at `y*9 + x` for x,y ∈ [0,8], horizontal walls at
  `81 + y*8 + x`, vertical walls at `145 + y*8 + x`, with 209..254 reserved and
  255 as sentinel). Per-game RNG
  seeds derive from `splitmix64(master_seed, game_index)` so per-game output is
  independent of worker count and scheduling order. Owned by
  [phase-2-transcript-codec-and-determinism.md](phase-2-transcript-codec-and-determinism.md).
- **Backend (v) Haskell engine.** Corridors game state as `Word64` bitboards
  manipulated with `Data.Bits` (lowering to `popcnt`/`tzcnt` under `-fllvm` with
  `-optlo-mcpu=native`), `Word16` ply counter, MCTS tree as a `MutablePrimArray s`
  arena of unboxed `Int32` / `Float` fields, UCT search and random-rollout leaf
  evaluation in the `ST s` monad, tree persistence carrying inherited visits across
  moves, pure API at the boundary. Owned by
  [phase-3-haskell-engine.md](phase-3-haskell-engine.md).
- **Backend (i) C++ legacy port and FFI bridge.** Verbatim re-port from `~/MCTS_legacy`
  with only the FFI shims required to expose a C ABI; inherits the legacy's
  `std::shared_ptr<uct_node>` trees, `std::mt19937_64` RNG, single-threaded design, and
  no draw rule (`is_terminal()` ↔ `hero_wins() || villain_wins()`). Excluded from the
  default `verify` cohort by the `VerifyBackend` type. Owned by
  [phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md).
- **Backend (ii) C++ imperative steelman.** The performance ceiling. C++23 with `-O3
  -march=native -mtune=native -flto -fno-plt -fno-semantic-interposition
  -fvisibility=hidden -fvisibility-inlines-hidden -fno-exceptions`, no `-ffast-math`;
  two-stage PGO via `-fprofile-generate` / `-fprofile-use`, BOLT post-link, `mimalloc`
  static link; arena tree, per-rollout scratch board with undo, flat children layout,
  move-list buffer reuse, branch hints, `__builtin_prefetch`, `__builtin_popcountll` /
  `__builtin_ctzll`, `alignas(64)`, `thread_local` scratch. Owned by
  [phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md).
- **Backends (iii) C++ functional-style and (iv) Rust.** Backend (iii) runs the same
  optimisation stack as (ii) so the (ii)-vs-(iii) comparison isolates *style* as the
  variable; functional style is at the API and data-flow level only, memory remains
  arena-allocated and mutable. Backend (iv) Rust on the latest stable compiler with the
  pinned `[profile.release]` (`opt-level = 3`, `lto = "fat"`, `codegen-units = 1`,
  `panic = "abort"`, `strip = "symbols"`), `RUSTFLAGS=-C target-cpu=native -C
  link-arg=-fuse-ld=lld`, `mimalloc` as `#[global_allocator]`, two-stage rustc PGO, BOLT
  post-link. Owned by
  [phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md).
- **Cross-backend verify, test stanzas, POC report card.** Five Cabal test-suite stanzas
  (`mcts-unit`, `mcts-integration`, `mcts-cross-backend`, `mcts-legacy-parity`,
  `mcts-haskell-style`), each `type: exitcode-stdio-1.0` with `tasty` as the in-stanza
  runner; `mcts test all` is a Plan/Apply command that delegates to `cabal test`, runs
  the pinned report-card workload, and emits the tidy summary block. Owned by
  [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md).
- **Haskell performance parity closure and retirement protocol.** GHC `-O2 -fllvm`,
  LLVM `-mcpu=native`, `-funbox-strict-fields`, `-fspecialise-aggressively`,
  `-fexpose-all-unfoldings`, `-flate-dmd-anal`, `-fmax-simplifier-iterations=20`,
  `-fworker-wrapper`, `-fstatic-argument-transformation`, RTS `-A64m -n4m -qg1 -qb -T`,
  `INLINABLE` + `SPECIALIZE` on the search loop, unboxed strict fields everywhere, no
  `Maybe`/`Either` in the rollout inner loop, until backend (v) matches backend (ii) on
  Q1 and Q2 within the parity tolerance per
  [../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md)
  (`HASKELL_PARITY_TOLERANCE = 0.05`). The retirement protocol then closes
  (i)→(ii)→(iii)→(v) with frozen golden anchors. Owned by
  [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md).

## Doctrine Scope

[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) is the authoritative CLI doctrine. The
project README declares which sections are binding and which are informational; this plan
inherits that split verbatim. No sprint may schedule adoption of an out-of-scope section.

**In scope (binding, every phase that touches the named surface):**

- Command Topology — commands as ordinary Haskell ADTs.
- `CommandSpec` + Generated Artifacts — marker discipline, paired `mcts docs check` /
  `mcts docs generate`, `forbiddenPathRegistry`, generated-section registry,
  `trackingGeneratedPaths` for fully-generated files (manpages, shell completions).
- Progressive Introspection — `mcts commands [--tree|--json]`, `mcts help <subcommand>`.
- Subprocesses as Typed Values — `Subprocess` ADT with `subprocessPath`,
  `subprocessArguments`, `subprocessEnvironment`, `subprocessWorkingDirectory`;
  `renderSubprocess` pure for logs and `--dry-run`; `runStreaming` and `capture` as the
  only IO boundary. `callProcess`, `readCreateProcess`, `System.Process`, and
  `typed-process` smart constructors are forbidden from command runners.
- `Plan / Apply` — `build :: TestInputs -> Either AppError TestPlan` /
  `apply :: Env -> TestPlan -> IO ExitCode` shape, with `--dry-run` and
  `--plan-file <path>` on every Plan/Apply command. `mcts test all` and the PGO+BOLT
  build harness are the principal consumers.
- Prerequisites as Typed Effects — one `prerequisiteRegistry` spanning every backend's
  toolchain (GCC, LLVM/BOLT, `rustc`, `mimalloc`, `ghcup`, the PGO profile dirs); each
  node carries `nodeId`, `nodeDescription`, and a remedy hint; transitive closure runs
  before `apply`; failure emits `AppError PrerequisiteUnmet`.
- Application Environment — `ReaderT Env IO` with a single `Env` record threaded through
  command runners.
- Lint, Format, and Code-Quality Stack — `fourmolu` + `hlint` + `cabal format`; pinned
  `fourmolu.yaml` at repo root with the twelve doctrine-mandated settings
  (`indentation`, `column-limit`, `function-arrows`, `comma-style`,
  `import-export-style`, `indent-wheres`, `record-brace-space`,
  `newlines-between-decls`, `haddock-style`, `let-style`, `in-style`, `unicode`); the
  `mcts-haskell-style` test-suite enforces all three plus the `cabal format` temp-file
  round-trip byte-equality compare.
- Testing Doctrine and Test Organization — five Cabal stanzas, each
  `type: exitcode-stdio-1.0`, each with its own `tasty` tree; a single `tasty` tree
  spanning all tiers is forbidden. Parser tests use `execParserPure`. Canonical property
  invariants `decode . encode == id`, `render is deterministic`, `parser roundtrips` are
  enumerated in the `mcts-unit` stanza. Golden tests replace non-deterministic content
  (wall-clock throughput) with sentinel placeholders.
- Output Rules — stdout primary, stderr diagnostics; `--format json|table|plain` default
  `table` on TTY else `plain`; `--color auto|always|never` / `--no-color`. The TUI
  commands (`play`, `inspect replay`) own their own rendering and ignore both flag
  families.
- Error Handling — single `AppError` ADT covering the canonical 15-variant set:
  `TranscriptNotFound`, `TranscriptAmbiguous`, `TranscriptFormatUnsupported`,
  `VerifyMismatch`, `VerifyCohortTooSmall`, `RecomputeMismatch`,
  `LegacyParityRolloutOverflow`,
  `ArchEnvelopeMismatch`, `EngineEnvelopeMismatch`, `PrerequisiteUnmet`,
  `SubprocessFailed`, `FFIFailure`, `DocsCheckDrift`, `UnknownCommand`,
  `InvalidMove`. The set matches
  [../README.md → Output and error discipline](../README.md) exactly;
  `SubprocessFailed`, `FFIFailure`, and `DocsCheckDrift` cover the typed
  `Subprocess` boundary, the C ABI bridge, and `mcts docs check` marker
  drift respectively. `renderError :: AppError -> Text` is the boundary in
  `src/MCTS/CLI/Output.hs`; hlint rules forbid `print`, `exitFailure`, and
  direct terminal formatting outside that boundary.
  `SubprocessFailed` is reserved for the typed `Subprocess` boundary
  (`runStreaming` / `capture` non-zero exit); `FFIFailure` is reserved for C ABI
  exceptions surfaced through the FFI bridge; `TranscriptFormatUnsupported`
  fires on non-zero `flags u32` in a transcript header;
  `ArchEnvelopeMismatch` fires when a transcript or verify cohort spans more
  than one `host_arch`; `EngineEnvelopeMismatch` fires when the layered
  engine-envelope check (cohort-invariant fields across the cohort,
  per-backend-slot fields against the live binary) finds a disagreement —
  the variants are kept semantically distinct.
- GADT-indexed state machines where naturally indicated (`VerifyBackend`,
  `LegacyParityBackend`); the `RngSource` axis encoded so that `--rng cpp` is the
  parse-time default for `verify`. `SimBudget`, `Threading`, and `Side` remain plain
  ADTs — the doctrine's GADT mandate applies only to state machines with more than
  two conceptual states per
  [../HASKELL_CLI_TOOL.md → GADT-Indexed State Machines](../HASKELL_CLI_TOOL.md).
- Project-level documentation standards — the six elements live in
  [../documents/documentation_standards.md](../documents/documentation_standards.md):
  marker convention with literal `<!-- mcts:<key>:start -->` etc. examples, authoritative
  pointer to the `GeneratedSectionRule` registry, "How to regenerate" naming
  `mcts docs generate`, per-file `**Generated sections**:` metadata field with lint
  contract, five-step extension protocol, fully-generated do-not-hand-edit rule.
- Toolchain pinning — GHC `9.14.1`, Cabal `3.16.1.0`; `mcts.cabal` declares
  `tested-with: ghc ==9.14.1`; `cabal.project` declares `with-compiler: ghc-9.14.1`.
- Project Structure (library-first layout) — `app/Main.hs` thin, logic under
  `src/MCTS/`.

**Out of scope (informational only — no sprint may schedule adoption):**

- Long-Running Daemons in the Same Binary — the CLI is short-running only. Covers the
  daemon `Lifecycle: load → prereq → acquire → ready → serve → drain → exit`,
  `BootConfig` / `LiveConfig` split, `SIGHUP` hot reload, `/healthz` / `/readyz` /
  `/metrics` endpoints, structured `co-log` logging, and the daemon-internal
  "Configuration: Dhall file with mandatory hot reload" subsection.
  - **Exception: `Test hooks in Env`.** Though the doctrine places this subsection
    inside the daemon section, the test-hook pattern (`Env` fields with no-op
    production defaults that tests override to observe or control async behavior)
    is admitted as in-scope. It is required for the
    [phase-1-haskell-cli-surface.md → Sprint 1.8](phase-1-haskell-cli-surface.md)
    `Env` record and the
    [phase-3-haskell-engine.md → Sprint 3.5](phase-3-haskell-engine.md)
    monotonic-clock bracket assertion. No other daemon discipline (lifecycle,
    hot reload, signal handling, `/healthz` endpoints, `co-log`) is admitted.
- Capability Classes and Service Errors — no external subsystems (no MinIO, Redis,
  PostgreSQL on the supported path).
- Retry Policy as First-Class Values — no external subsystems with retryable errors.
- At-Least-Once Event Processing — no event stream.
- Reconcilers: Idempotent Mutation as a Single Command — no managed state in the world
  outside the local transcript cache.
- Smart Constructors for Paired Resources — no paired resources (no DNS/cert pairs, no
  PV/PVC pairs).
- Pulumi-Orchestrated Infrastructure Tests — no cloud surface.

**Stack deviations from doctrine (recorded once, here):**

- `brick` + `vty` are added for the `play` and `inspect replay` TUIs only. No other
  command may import either.
- `dhall` is unused. The doctrine prescribes `dhall` for daemon configuration; daemon
  configuration is itself out of scope for this CLI, so the dependency does not enter
  the stack.

## Hard Constraints

The supported architecture closes on the following non-negotiable rules. Numbered for
referenceability.

1. One Haskell CLI binary named `mcts`. No separate Python entry point, no separate
   Rust entry point, no separate C++ entry point. Every measurement, determinism check,
   and game runs out of one Haskell process driven by one binary.
2. Every individual game is single-threaded internally. One tree, one search, one
   rollout stream per game. Multi-threading is only ever about running independent games
   concurrently.
3. Multi-threaded benchmark mode defaults to 8 workers (`--workers N` to override).
   Each worker plays one game at a time, single-threaded internally.
4. Per-game RNG streams are seeded by `splitmix64(master_seed, game_index)` so per-game
   output is independent of worker count, scheduling order, and worker-to-game
   assignment.
5. Two RNG sources are supported: `--rng native` (each backend's fastest defensible RNG;
   not cross-backend bit-equal) and `--rng cpp` (every participating backend draws from
   the same C++ `std::mt19937_64` generator through the FFI; backend (i) always uses
   `std::mt19937_64` and silently ignores `--rng native`).
6. `--rng cpp` is the implicit default for `verify` and is not user-overridable on the
   `mcts verify` subtree. The native RNG cannot validate cross-backend bit equality.
7. `VerifyBackend` excludes backend (i) at the type level from the default `verify`
   cohort because (i)'s terminal-state semantics lack the ply-cap draw rule (see
   constraint 9).
8. `LegacyParityBackend` requires backend (i) at parse time. Cohorts without
   `cpp-legacy` fail with `AppError VerifyCohortTooSmall`.
9. Backends (ii)–(v) carry a `Word16` ply counter in board state and add the ply-cap
   draw rule: `is_terminal` ↔ `hero_wins || villain_wins || ply_count >= max_plies`;
   `get_terminal_eval` returns `0.0` on ply-cap termination. Default `max_plies = 200`,
   pinned in the transcript header. Backend (i) lacks the ply cap and is verbatim from
   `MCTS_legacy`.
10. The legacy parity envelope pins `max_plies = 10000` (= `MAX_ROLLOUT_ITERS` in the
    legacy). Under that envelope all five backends terminate every rollout on a
    positional win, so decoded determinism payloads must be bit-equal. The
    `mcts verify legacy-parity` subcommand pins this; a fixture seed is chosen so (i) never trips
    `MAX_ROLLOUT_ITERS`. If (i) throws, the cohort fails with
    `AppError LegacyParityRolloutOverflow` carrying `(seed, game_index, move_index)`.
11. The transcript wire format is little-endian binary with no schema-library
    dependency. No protobuf, no flatbuffers, no Cap'n Proto, no CBOR. The header carries
    the run config; per-move records are sparse `(action_id, visits)` pairs sorted
    ascending by action ID. Equity is excluded from the wire format.
12. Transcripts are one-game files content-addressed by `sha256(run_config)`, where
    `run_config` includes the backend and `game_index` so provenance-bearing cache files
    never collide across backends or games. `mcts play`-recorded transcripts use
    `sha256(run_config || move_history)` because the human's move choices make the
    post-config bytes non-deterministic. The cache root resolves
    `--cache-dir <path>` → `$MCTS_CACHE_DIR` → `./.mcts-cache/` and is `.gitignore`'d
    when inside the project tree.
13. Hash-prefix lookup is git-style: shortest unique prefix accepted, minimum 4 hex
    chars. `AppError TranscriptNotFound` on no match; `AppError TranscriptAmbiguous`
    carrying the candidate list on multi-match.
14. Visits persist across moves within a single game (tree persistence); the rest of
    the tree is discarded incrementally as moves are played. Trees are memory-resident
    only — nothing is serialised between runs.
15. Equity is recomputed by the same backend on `inspect replay` and
    `inspect show --with-equity`. Cross-backend equity bit-equality is not asserted; the
    determinism contract is on visit counts (integer, order-independent) only. Equity
    drift across backends that swaps a tie-break surfaces as a visit-count mismatch on
    the next move and is caught by `mcts verify`.
16. The toolchain is pinned at GHC `9.14.1` and Cabal `3.16.1.0`. `mcts.cabal` declares
    `tested-with: ghc ==9.14.1`; `cabal.project` declares `with-compiler: ghc-9.14.1`.
17. Backend (i) `cpp-legacy/` is strictly verbatim from `~/MCTS_legacy/backend/`. Only
    FFI shims are permitted. Build flags are `-std=c++17 -O3 -fPIC -Wall`. It uses
    `std::shared_ptr<uct_node>` trees and `std::mt19937_64` unchanged.
18. Backends (ii) and (iii) compile with `-std=c++23 -O3 -march=native -mtune=native
    -flto -fno-plt -fno-semantic-interposition -fvisibility=hidden
    -fvisibility-inlines-hidden -fno-exceptions`. `-fno-exceptions` is mandatory
    (the engine core does not throw, so landing-pad cost is unconditional dead
    weight). No `-ffast-math` and no `-Ofast`. PGO+BOLT pipeline plus `mimalloc`
    static link required. `g++` only — Clang is not supported on the C++ side.
19. Backend (iv) Rust uses `[profile.release]` with `opt-level = 3`, `lto = "fat"`,
    `codegen-units = 1`, `panic = "abort"`, `strip = "symbols"`. `RUSTFLAGS=-C
    target-cpu=native -C link-arg=-fuse-ld=lld`. `mimalloc` as `#[global_allocator]`.
    Two-stage `rustc -Cprofile-generate` / `-Cprofile-use` PGO. BOLT post-link.
20. Backend (v) Haskell uses `-O2 -fllvm` with LLVM `-optlo-mcpu=native` /
    `-optlc-mcpu=native`, `-funbox-strict-fields`, `-fspecialise-aggressively`,
    `-fexpose-all-unfoldings`, `-flate-dmd-anal`, `-fmax-simplifier-iterations=20`,
    `-fworker-wrapper`, `-fstatic-argument-transformation`. RTS `-A64m -n4m -qg1 -qb
    -T` is baked into the executable. Engine hot path lives in `ST s`; tree is a
    `MutablePrimArray s` arena of unboxed `Int32` / `Float` fields; board state is
    `Word64` bitboards manipulated with `Data.Bits`. Pure API at the boundary; no
    `Maybe` / `Either` in the rollout inner loop.
21. Library-first layout: `app/Main.hs` is thin; logic lives under `src/MCTS/`.
22. `CommandSpec` is the source of truth for the parser, the command tree, the JSON
    schema, the markdown command reference, the manpages, and the shell completion
    scripts. The parser is a renderer of the spec.
23. `Subprocess` is the only IO boundary for subprocess execution. `callProcess`,
    `readCreateProcess`, `System.Process` constructors, and `typed-process` smart
    constructors are hlint-forbidden outside the `runStreaming` / `capture`
    interpreter. The PGO+BOLT build harness invokes `g++`, `rustc`, `llvm-bolt`, and
    `cabal` through the typed `Subprocess` boundary.
24. Every Plan/Apply command supports `--dry-run` (renders the plan and exits 0) and
    `--plan-file <path>` (writes the rendered plan for out-of-band review).
25. One `prerequisiteRegistry` spans every backend's toolchain. Failure emits
    `AppError PrerequisiteUnmet` carrying the failing `nodeId`, description, and remedy
    hint.
26. Single `AppError` ADT; `renderError :: AppError -> Text` is the only Text rendering
    at the CLI boundary; `print`, `exitFailure`, and direct terminal formatting are
    hlint-forbidden outside `src/MCTS/CLI/Output.hs`.
27. `mcts test all` is the doctrine-mandatory canonical test command. The Cabal stanzas
    are `mcts-unit`, `mcts-integration`, `mcts-cross-backend`, `mcts-legacy-parity`,
    `mcts-haskell-style`. A single `tasty` tree spanning all tiers is forbidden.
28. `fourmolu.yaml` at repo root pins the twelve doctrine-mandated settings; the
    `mcts-haskell-style` stanza enforces them plus `cabal format` temp-file round-trip
    byte-equality.
29. Report-card knobs are pinned in `cabal.project`: `G_R = 100_000`, `G_S = 1_000`,
    `G_V = 50`, `G_LP = 10`, `S_BENCH = 10_000`, `S_VERIFY = 10_000`,
    `S_LP_SIMS = 10_000`, `S_LP = 42`.
30. The retirement protocol is (i)→(ii)→(iii)→(v). Each retiring backend's transcripts
    and throughputs freeze in `test/golden/` as the regression anchor for the surviving
    cohort. Backend (iv) Rust remains live as the cross-language second opinion.
31. The Docker development environment provides a single LLVM pinned in
    `docker/Dockerfile` shared by GHC's `-fllvm` backend and BOLT post-link. The base
    is `ubuntu:24.04`; the C++ toolchain is GCC (latest stable on 24.04); Rust is
    `rustup`-installed with a pinned minor version; Haskell is `ghcup`-managed and
    pinned to GHC `9.14.1` and Cabal `3.16.1.0`.
32. Move notation matches the legacy engine: `*(x,y)` for pawn moves, `H(x,y)` for
    horizontal walls, `V(x,y)` for vertical walls, x,y ∈ [0,8] for pawns and ∈ [0,7]
    for walls. `inspect show` / `inspect replay` and the `play` TUI render in this
    notation.
33. The transcript decoder's `winner u8` field is a 3-value enum: `0 = hero`,
    `1 = villain`, `2 = draw`. Draws render as `<draw>` in `inspect show` /
    `inspect replay`.
34. `mcts play` accepts `:hint`, `:undo`, `:save`, and `:quit` in-app commands.
    Hand-played transcripts are addressed by `sha256(run_config || move_history)`
    because the human's choices make the post-config bytes non-deterministic.
35. `inspect replay` recomputes equity on the fly by replaying the search; the visit
    counts produced must equal the transcript record byte-for-byte as a built-in
    determinism check that fires on every navigation. The last `replayCacheStates` MCTS
    states (default 20, `--cache-states N`) are kept in memory for back-navigation.
36. Supported target platforms are **amd64 Linux** and **arm64 Linux**. Reproducibility
    envelopes are per-architecture: a transcript written on amd64 is bit-identical on
    replay against the same backend on amd64, and a transcript written on arm64 is
    bit-identical on replay against the same backend on arm64, but cross-architecture
    bit-equality is **not** guaranteed (the `c_param u64` IEEE-754 bit-cast and the
    backend-internal floating-point arithmetic differ at the ULP level across arches).
    Transcript headers and report-card metadata carry a `host_arch` tag (`"amd64"` |
    `"arm64"`); cross-backend `verify` and same-backend `verify` checks are only valid
    when the comparison set shares a `host_arch`. See
    [../documents/engineering/determinism_contract.md → Architecture
    Envelope](../documents/engineering/determinism_contract.md).
37. Every transcript carries a versioned **engine envelope** block immediately after
    the fixed header, excluded from the backend-specific `sha256(RunConfig)` cache key.
    The envelope decomposes into
    cohort-invariant fields (`host_arch`, `rng_source`, `shared_rng_build_id`,
    `cohort_config_hash`) and per-backend-slot fields (`engine_build_id`,
    `engine_git_commit`, `compiler_id` + `compiler_version`, `fp_flags`, `libm_id`,
    `cpu_features`, `fp_env`). `mcts verify` hard-fails with
    `AppError EngineEnvelopeMismatch` when cohort-invariant fields disagree across the
    cohort, or when per-backend-slot fields disagree between a cached transcript and
    the live binary for the same backend slot (downgradeable to a warning via the
    `--allow-stale` flag for forensic comparisons). Cross-backend differences in
    per-backend-slot fields are expected and silent — `verify`'s contract is "different
    binaries, identical visits." See
    [../documents/engineering/determinism_contract.md → Engine Envelope](../documents/engineering/determinism_contract.md).
38. Equity sidecar cache layout under the existing transcript cache root:
    `<cache-root>/transcripts/<arch>/<sha>/<backend>-<engine_build_id_prefix16>.eq`
    plus a `.envelope` neighbour file holding the envelope of the build that wrote
    the `.eq`. Multi-build cohabitation is automatic — a rebuild lands in a fresh
    cache slot keyed by the new `engine_build_id` prefix; old slots remain for
    forensic comparison until explicitly pruned (`mcts inspect cache prune`). The
    sidecar is read on `inspect replay` and `inspect show --with-equity` for instant
    cache hits; misses trigger lazy on-demand recompute via the per-backend FFI
    `mcts_<backend>_recompute_equities`. See
    [../documents/engineering/transcript_format.md → Equity Sidecar Cache](../documents/engineering/transcript_format.md).
39. Divergence-smell thresholds per
    [../documents/engineering/determinism_contract.md → Divergence Smell](../documents/engineering/determinism_contract.md):
    same-substrate and `--rng cpp` cross-backend cohorts (ii)–(v) hard-fail on any
    visit-count or move disagreement (the existing contract); `--rng native`
    cross-backend and cross-build same-backend comparisons surface
    `move_disagreement_rate` and `visit_disagreement_rate` annotations in the REPL
    column headers and in the `mcts test all` report-card matrix, warning when the
    measured rate exceeds the thresholds (pinned in `cabal.project` once empirically
    calibrated in Phase 7).

## Dependency Chain

| Phase | Depends On | Why |
|-------|------------|-----|
| 0 | — | Bootstrap |
| 1 | Phase 0 | The CLI surface and lint stack consume the doctrine in-scope/out-of-scope split and the standards rule L doctrine-citation contract |
| 2 | Phase 1 | The transcript codec, hash-prefix lookup, and RNG plumbing register their CLI surface (`inspect list`, `inspect show`, `--cache-dir`, `--rng`) and their Plan/Apply discipline through the registry built in Phase 1 |
| 3 | Phase 2 | The Haskell engine writes transcripts in the wire format pinned by Phase 2 and consumes the `splitmix64(master_seed, game_index)` seed derivation |
| 4 | Phase 3 | The C ABI FFI bridge from Haskell to backend (i) reuses the `Subprocess` boundary and `Env` record established by Phases 1 and 3, and validates against the same transcript codec |
| 5 | Phase 3 | Backend (ii) likewise builds on the FFI bridge pattern; it is independent of (i) once the pattern is established, so Phases 4 and 5 may proceed in parallel after Phase 3 closes |
| 6 | Phase 5 | Backend (iii) shares (ii)'s optimisation stack and must be developed against the validated steelman; backend (iv) Rust is independent of (iii) but conventionally bundled in the same phase for scheduling |
| 7 | Phases 4, 5, 6 | The cross-backend `verify` cohort and the POC report card require all five backends live and producing transcripts |
| 8 | Phase 7 | Performance parity closure requires the report-card numbers from Phase 7 to measure Haskell against backend (ii); the retirement protocol then runs the (i)→(ii)→(iii)→(v) chain |

## Current Baseline

| Surface | Current Repo State | Intended End State |
|---------|--------------------|--------------------|
| Repository layout | `app/`, `src/MCTS/`, `cpp-legacy/`, `cpp-imperative/`, `cpp-functional/`, `rust/`, `bench/`, `test/`, `docker/`, `cabal.project`, `fourmolu.yaml`, `.hlint.yaml`, `.gitignore`, `mcts.cabal`, generated-artefact targets `documents/cli/commands.md`, `share/man/man1/mcts.1`, and `share/completion/{bash,zsh,fish}/` | Same layout, with the placeholder backend trees replaced by the real optimized implementations and retained golden anchors |
| Build artefacts | `mcts.cabal` declares the `mcts` binary and all Haskell test stanzas; `cabal build all` is the validation gate under the pinned toolchain. Foreign backend directories contain smoke-buildable C ABI / `cdylib` skeletons but are not linked into the Haskell binary. | `cabal build all`-produced `mcts` binary, plus per-backend shared libraries (`cpp-legacy/libmcts_cpp_legacy.so`, `cpp-imperative/libmcts_cpp_imperative.so`, `cpp-functional/libmcts_cpp_functional.so`, `rust/target/release/libmcts_rust.so`) |
| CLI surface | The complete command family is wired for the logical baseline: `bench`, `verify`, `inspect`, `test`, `lint`, `docs`, `commands`, `help`, `check-code`, `build`, and smoke `play`. Generated command docs are in sync with the renderer, tracked generated-file drift fails `mcts lint files`, and `mcts test all` routes recursive CLI calls through `cabal exec mcts -- ...`. | Same surface backed by real Haskell, C++, and Rust engines plus interactive TUIs |
| Test stanzas | Five Cabal stanzas exist: `mcts-unit`, `mcts-integration`, `mcts-cross-backend`, `mcts-legacy-parity`, `mcts-haskell-style`; the current tests are simple executable `Main.hs` smoke/property checks, and `cabal test all` is the validation gate under the pinned toolchain. | Same stanzas, strengthened to use the doctrine-required `tasty` runners, real FFI-backed cohort, and external golden fixtures |
| Toolchain | `mcts.cabal` pins `tested-with: ghc ==9.14.1`; `cabal.project` pins `with-compiler: ghc-9.14.1` and report-card knobs. | GHC `9.14.1`, Cabal `3.16.1.0`, GCC latest stable on `ubuntu:24.04`, Rust latest stable with pinned minor, LLVM pinned in the Dockerfile |
| Determinism contract | Implemented for the logical in-process five-backend baseline under `mcts verify` and the Cabal tests. Transcript codec, SHA-256 content addressing, cache root resolution, prefix lookup, baseline equity sidecars, and transcript-pair divergence metrics are implemented. | Enforced by real cross-backend `mcts verify {rollouts,selfplay,legacy-parity}` plus same-backend determinism cases under `mcts-integration` |
| Performance parity | Not proven. Report-card rendering exists as a logical baseline and explicitly marks external fixture parity pending. | Haskell (v) within tolerance of C++ (ii) on Q1 and Q2, single-threaded and on 8 workers, recorded in the `mcts test all` report card |

## Related Documents

- [README.md](README.md)
- [development_plan_standards.md](development_plan_standards.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
- [../README.md](../README.md)
