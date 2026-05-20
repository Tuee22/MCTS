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
protocol's recorded historical evidence (Phase `8`) leaves the door open for a
successor effort to inherit a parity-proven Haskell engine; that work is a future
plan, not a deliverable here.

## Current Handoff Status

The 2026-05-19 report card proves the performance-parity target for the
surviving `(rust, haskell)` live cohort, backend retirements `(i)` through
`(iii)` remain recorded as historical evidence, and the Phase `8`
compiler-runtime plan alignment plus no-generated-validation-data doctrine
cleanup are closed.

Phase `1` reclosed on its owned CLI-scaffold and lint-stack surfaces during the
2026-05-19 alignment sweep. Phase `2` reclosed on the transcript/cache/envelope
surface after one-game cache keys, the envelope wire payload, and `inspect show`
sidecar/envelope behavior were aligned. Phase `6` reclosed after the Rust PGO
build harness adopted the documented `lld` linker flag. Phase `7` reclosed after
the verifier comparator, `play`, replay overlay, and cross-backend stanza
alignment. Phase `8` reclosed after the tuning-doc and generated-validation-data
cleanup. Phases `3`, `4`, and `5` remain `Done` on their owned engine and
retired-backend surfaces.

## Target Outcome

One `mcts` Haskell CLI binary, built by Cabal under GHC `9.14.1` and Cabal `3.16.1.0`,
drives the live backend cohort behind a uniform command surface. Backend (i)
`cpp-legacy/` is a strictly verbatim re-port of `MCTS_legacy` retained as a retired
reference and optional local evidence-generation home. Backend (ii)
`cpp-imperative/` is the retired maximally-tuned imperative C++23 performance
ceiling, preserved as source plus recorded historical evidence.
Backend (iii) `cpp-functional/` is the retired maximally-tuned modern C++23
functional-style anchor under the same PGO+BOLT+`mimalloc` optimisation stack,
preserved as source plus recorded historical evidence; backend (iv) `rust/` is
the live cross-language baseline; backend (v) is the pure Haskell engine running
natively in the same process, with `ST`-monad mutable arena internally and pure
search API externally.

Two POC benchmark workloads exercise the cohort: (a) random rollouts and (b) adversarial
MCTS self-play with rollout evaluations. Each runs single-threaded and on 8 workers under
both `--rng native` (the current backend-salted deterministic schedule used for
benchmark stream separation) and `--rng cpp` (all backends draw from the canonical
C++-RNG seed schedule with no backend-native salt). `mcts verify` round-robin-compares
visit counts under `--rng cpp` across the current live cohort `(iv)..(v)`, with
retired backends excluded by the `VerifyBackend` type. The former live
`mcts verify legacy-parity` gate retired with backend (i) in Sprint 8.4; Q7 is
now answered by recorded historical backend (i) evidence.
`mcts test all`
emits the tidy POC report-card summary block answering Q1–Q7 in one screenful, with all
live workload constants implemented in `MCTS.CLI.Test` and mirrored in
`cabal.project` comments. Retired legacy-envelope knobs remain historical
evidence metadata rather than current validation inputs.

Following the retirement protocol, backend (i) retired once it demonstrated faithful
reproduction of `MCTS_legacy` (Q6 closure), and backend (ii) retired once
functional-style C++ (iii) demonstrated parity with imperative C++ on Q1/Q2.
Backend (iii) retired after pure Haskell (v) demonstrated parity with
functional C++. Each retiring backend's evidence is recorded in plan/docs or
optional external/ignored artifacts; normal validation never depends on
checked-in generated transcripts, throughput JSON, or snapshot files. Backend
(iv) Rust remains live throughout as a long-running cross-language second opinion.

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
  manipulated with `Data.Bits` under `-fllvm`, `Word16` ply counter, MCTS tree as a
  structure-of-arrays `STUArray` arena of unboxed `Int32` / `Float` fields, UCT
  search and random-rollout leaf evaluation in the `ST s` monad, tree persistence
  carrying inherited visits across moves, pure API at the boundary. Per-CPU LLVM
  `-mcpu=native` flags are intentionally excluded on the current aarch64 container and
  tracked as a Sprint 8.2 ledger item. Owned by
  [phase-3-haskell-engine.md](phase-3-haskell-engine.md).
- **Backend (i) C++ legacy port and FFI bridge.** Verbatim re-port from `~/MCTS_legacy`
  with only the FFI shims required to expose a C ABI; inherits the legacy's
  `std::shared_ptr<uct_node>` trees, `std::mt19937_64` RNG, single-threaded design, and
  no draw rule (`is_terminal()` ↔ `hero_wins() || villain_wins()`). Excluded from the
  default `verify` cohort by the `VerifyBackend` type and retired from live
  CLI/build/verify/FFI dispatch in Sprint 8.4. Owned by
  [phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md)
  and retired by [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md).
- **Backend (ii) C++ imperative steelman.** The retired performance ceiling. C++23 with `-O3
  -march=native -mtune=native -flto -fno-plt -fno-semantic-interposition
  -fvisibility=hidden -fvisibility-inlines-hidden -fno-exceptions`, no `-ffast-math`;
  two-stage PGO via `-fprofile-generate` / `-fprofile-use`, BOLT post-link, `mimalloc`
  static link; arena tree, per-rollout scratch board with undo, flat children layout,
  move-list buffer reuse, branch hints, `__builtin_prefetch`, `__builtin_popcountll` /
  `__builtin_ctzll`, `alignas(64)`, `thread_local` scratch. Owned by
  [phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md) and
  retired by [phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md).
- **Backends (iii) C++ functional-style and (iv) Rust.** Backend (iii) ran the same
  optimisation stack as (ii) so the (ii)-vs-(iii) comparison isolated *style* as the
  variable; it is now a retired Sprint 8.6 source/evidence archive.
  Backend (iv) Rust on the latest stable compiler with the
  pinned `[profile.release]` (`opt-level = 3`, `lto = "fat"`, `codegen-units = 1`,
  `panic = "abort"`, `strip = "symbols"`), `RUSTFLAGS=-C target-cpu=native -C
  link-arg=-fuse-ld=lld`, `mimalloc` as `#[global_allocator]`, two-stage rustc PGO, BOLT
  post-link. Owned by
  [phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md).
- **Cross-backend verify, test stanzas, POC report card.** Four live Cabal test-suite
  stanzas (`mcts-unit`, `mcts-integration`, `mcts-cross-backend`,
  `mcts-haskell-style`), each `type: exitcode-stdio-1.0` with `tasty` as the in-stanza
  runner; `mcts test all` is a Plan/Apply command that builds the canonical foreign
  backend artefacts, delegates to `cabal test`, runs the pinned no-write
  report-card measurements plus verify cohorts, and emits the tidy summary
  block. Owned by
  [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md).
- **Haskell performance parity closure and retirement protocol.** GHC `-O2 -fllvm`,
  `-funbox-strict-fields`, `-fspecialise-aggressively`,
  `-fexpose-all-unfoldings`, `-flate-dmd-anal`, `-fmax-simplifier-iterations=20`,
  `-fworker-wrapper`, `-fstatic-argument-transformation`, RTS `-A64m -n4m -qg1 -qb -T`,
  `INLINABLE` + `SPECIALIZE` on the search loop, unboxed strict fields everywhere, no
  `Maybe`/`Either` in the rollout inner loop, until backend (v) matches backend (ii) on
  Q1 and Q2 within the parity tolerance per
  [../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md)
  (`HASKELL_PARITY_TOLERANCE = 0.05`). The retirement protocol then closes
  (i)→(ii)→(iii)→(v) with recorded historical evidence and no generated validation
  data checked into git. Owned by
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
  round-trip byte-equality compare. Fourmolu and HLint are installed with a separate
  pinned formatter-tools GHC `9.12.4` into `/opt/mcts-style-tools/bin/` inside the
  container; the project compiler remains GHC `9.14.1`. Ambient host fallback is
  not supported.
- Testing Doctrine and Test Organization — four live Cabal stanzas, each
  `type: exitcode-stdio-1.0`, each with its own `tasty` tree; a single `tasty` tree
  spanning all tiers is forbidden. Parser tests use `execParserPure`. Canonical property
  invariants `decode . encode == id`, `render is deterministic`, `parser roundtrips` are
  enumerated in the `mcts-unit` stanza. The project-specific stricter rule is that
  normal tests do not read checked-in generated validation data: renderer examples,
  transcripts, sidecars, and report-card shapes are asserted semantically or generated
  under temporary directories during the test run.
- Output Rules — stdout primary, stderr diagnostics; `--format json|table|plain` default
  `table` on TTY else `plain`; `--color auto|always|never` / `--no-color`. The TUI
  commands (`play`, `inspect replay`) own their own rendering and ignore both flag
  families.
- Error Handling — single `AppError` ADT covering the canonical 19-variant set:
  `TranscriptNotFound`, `TranscriptAmbiguous`, `TranscriptFormatUnsupported`,
  `VerifyMismatch`, `VerifyLengthMismatch`, `VerifyTerminatorMismatch`,
  `VerifyCohortTooSmall`, `RecomputeMismatch`, `LegacyParityRolloutOverflow`,
  `ArchEnvelopeMismatch`, `EngineEnvelopeMismatch`, `PrerequisiteUnmet`,
  `SubprocessFailed`, `FFIFailure`, `DocsCheckDrift`, `UnknownCommand`,
  `InvalidMove`, `ParseError`, `IOErrorText`. The set matches
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
  per-backend-slot fields against the live binary) finds a disagreement;
  `ParseError` and `IOErrorText` carry parser/validation and textual IO failures
  that must still pass through the same render boundary — the variants are kept
  semantically distinct.
- GADT-indexed state machines where naturally indicated (`VerifyBackend`; the
  retired `LegacyParityBackend` parser surface is preserved only in Phase 7 history);
  the `RngSource` axis encoded so that `--rng cpp` is the
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
5. Two RNG sources are supported: `--rng native` (the current backend-salted
   deterministic schedule; benchmark streams are intentionally backend-distinct
   and not cross-backend bit-equal) and `--rng cpp` (the verification cohort uses
   the canonical C++-RNG seed schedule with no backend-native salt; retired
   backend (i) always used `std::mt19937_64` and silently ignored
   `--rng native`).
6. `--rng cpp` is the implicit default for `verify` and is not user-overridable on the
   `mcts verify` subtree. The native RNG cannot validate cross-backend bit equality.
7. `VerifyBackend` excludes retired backends (i) and (ii) at the type level
   from the default `verify` cohort; backend (i)'s terminal-state semantics lack
   the ply-cap draw rule (see constraint 9), and backend (ii) is now preserved by
   its Sprint `8.5` recorded retirement evidence.
8. The legacy-parity parser surface retired with backend (i) in Sprint 8.4. Q7
   is now recorded historical evidence, not a checked-in generated validation input.
9. Backends (ii)–(v) carry a `Word16` ply counter in board state and add the ply-cap
   draw rule: `is_terminal` ↔ `hero_wins || villain_wins || ply_count >= max_plies`;
   `get_terminal_eval` returns `0.0` on ply-cap termination. Default `max_plies = 200`,
   pinned in the transcript header. Backend (i) lacks the ply cap and is verbatim from
   `MCTS_legacy`.
10. The legacy parity envelope pins `max_plies = 10000` (= `MAX_ROLLOUT_ITERS` in the
    legacy). Before Sprint 8.4, Q7 used that envelope as a five-backend
    liveness/overflow gate, while Q3 owned visit-vector equality across the
    then-live `(ii)..(v)` cohort and Q6 owned byte-for-byte legacy evidence.
    After Sprint 8.4, the live subcommand is retired and Q7 reads the frozen
    backend (i) historical evidence.
11. The transcript wire format is little-endian binary with no schema-library
    dependency. No protobuf, no flatbuffers, no Cap'n Proto, no CBOR. The header carries
    the run config; per-move records are sparse `(action_id, visits)` pairs sorted
    ascending by action ID. Equity is excluded from the wire format.
12. Transcripts are one-game files content-addressed by `sha256(run_config)`, where
    `run_config` includes the backend and `game_index` so provenance-bearing cache files
    never collide across backends or games. `mcts play`-recorded transcripts use
    `sha256(run_config || move_history)` because the human's move choices make the
    post-config bytes non-deterministic. The cache root resolves
    `--cache-dir <path>` → `./.mcts-cache/` inside the container; the `mcts` binary
    does not read cache-root environment variables.
13. Hash-prefix lookup is git-style: shortest unique prefix accepted, minimum 4 hex
    chars. `AppError TranscriptNotFound` on no match; `AppError TranscriptAmbiguous`
    carrying the candidate list on multi-match.
14. Visits persist across moves within a single game (tree persistence); the rest of
    the tree is discarded incrementally as moves are played. Trees are memory-resident
    only — nothing is serialised between runs.
15. Equity is recomputed by the same backend on `inspect replay` and
    `inspect show --with-equity`. Cross-backend equity bit-equality is not asserted; the
    Q3 determinism contract is on visit counts (integer, order-independent) only.
    Float drift across the current live verification cohort that changes UCT child selection or the
    final highest-visit root action surfaces as a visit-count mismatch on the next
    move and is caught by `mcts verify`.
16. The toolchain is pinned at GHC `9.14.1` and Cabal `3.16.1.0`. `mcts.cabal` declares
    `tested-with: ghc ==9.14.1`; `cabal.project` declares `with-compiler: ghc-9.14.1`.
17. Backend (i) `cpp-legacy/` is strictly verbatim from `~/MCTS_legacy/backend/` and
    retired from live CLI dispatch. Only FFI shims are permitted in the retained
    reference source. The historical build flags are `-std=c++17 -O3 -fPIC -Wall`.
    It uses `std::shared_ptr<uct_node>` trees and `std::mt19937_64` unchanged.
18. Backends (ii) and (iii) compile with `-std=c++23 -O3 -march=native -mtune=native
    -flto -fno-plt -fno-semantic-interposition -fvisibility=hidden
    -fvisibility-inlines-hidden -fno-exceptions`. `-fno-exceptions` is mandatory
    (the engine core does not throw, so landing-pad cost is unconditional dead
    weight). No `-ffast-math` and no `-Ofast`. Backend (ii) is now retired but
    retains this historical contract in source and recorded evidence. PGO+BOLT pipeline plus `mimalloc`
    static link required. `g++` only — Clang is not supported on the C++ side.
19. Backend (iv) Rust uses `[profile.release]` with `opt-level = 3`, `lto = "fat"`,
    `codegen-units = 1`, `panic = "abort"`, `strip = "symbols"`. `RUSTFLAGS=-C
    target-cpu=native -C link-arg=-fuse-ld=lld`. `mimalloc` as `#[global_allocator]`.
    Two-stage `rustc -Cprofile-generate` / `-Cprofile-use` PGO. BOLT post-link.
20. Backend (v) Haskell uses `-O2 -fllvm`, `-funbox-strict-fields`, `-fspecialise-aggressively`,
    `-fexpose-all-unfoldings`, `-flate-dmd-anal`, `-fmax-simplifier-iterations=20`,
    `-fworker-wrapper`, `-fstatic-argument-transformation`. RTS `-A64m -n4m -qg1 -qb
    -T` is baked into the executable. Engine hot path lives in `ST s`; tree is a
    structure-of-arrays `STUArray` arena of unboxed `Int32` / `Float` fields; board
    state is `Word64` bitboards manipulated with `Data.Bits`. Pure API at the
    boundary; no `Maybe` / `Either` in the rollout inner loop. LLVM
    `-optlo-mcpu=native` / `-optlc-mcpu=native` is ledger-deferred on aarch64 until
    the assembler target accepts the emitted LSE instructions.
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
27. `mcts test all` is the doctrine-mandatory canonical test command. The live Cabal
    stanzas are `mcts-unit`, `mcts-integration`, `mcts-cross-backend`,
    `mcts-haskell-style`. A single `tasty` tree spanning all tiers is forbidden.
28. `fourmolu.yaml` at repo root pins the twelve doctrine-mandated settings; the
    `mcts-haskell-style` stanza enforces them plus `cabal format` temp-file round-trip
    byte-equality through the separate formatter-tools install (`ghc-9.12.4`,
    `fourmolu-0.19.0.1`, `hlint-3.10`) under `/opt/mcts-style-tools/bin/` inside the
    container. Host `PATH` fallback is never allowed.
29. Report-card live workload constants are implemented in `MCTS.CLI.Test` and
    mirrored in `cabal.project` comments: `G_R = 1_000`, `G_S = 4`,
    `G_V = 4`, `S_BENCH = 500`, `S_VERIFY = 500`. Retired legacy-envelope
    knobs (`G_LP`, `S_LP_SIMS`, `S_LP`) are historical evidence metadata.
30. The retirement protocol is (i)→(ii)→(iii)→(v). Each retiring backend's evidence is
    recorded in plan/docs or optional external/ignored artifacts; checked-in generated
    transcripts, throughput JSON, report-card schemas, and renderer snapshots are not
    part of the normal validation surface. Backend (iv) Rust remains live as the
    cross-language second opinion.
31. The Docker development environment provides a single LLVM pinned in
    `docker/Dockerfile` shared by GHC's `-fllvm` backend and BOLT post-link. The base
    is `ubuntu:24.04`; the C++ toolchain is GCC (latest stable on 24.04); Rust is
    `rustup`-installed with a pinned minor version; Haskell is `ghcup`-managed and
    pinned to GHC `9.14.1` and Cabal `3.16.1.0`; Haskell style tools use a separate
    pinned GHC `9.12.4` and do not alter the project compiler. Root-level
    `compose.yaml` supports only `docker compose run --rm mcts mcts <command>` as the
    host entrypoint. There is no long-running daemon container, bind-mounted workspace,
    Compose-level environment-variable block, repository `.sh` workflow wrapper, or
    `bootstrap/` helper; host-level `.build/` artefacts are unsupported.
32. Move notation matches the legacy engine: `*(x,y)` for pawn moves, `H(x,y)` for
    horizontal walls, `V(x,y)` for vertical walls, x,y ∈ [0,8] for pawns and ∈ [0,7]
    for walls. `inspect show` / `inspect replay` and the `play` TUI render in this
    notation.
33. The transcript decoder's `winner u8` field is a 3-value enum: `0 = hero`,
    `1 = villain`, `2 = draw`. Draws render as `<draw>` in `inspect show` /
    `inspect replay`.
34. `mcts play` accepts `:hint`, `:undo`, `:save`, and `:quit` in-app commands.
    Hand-played transcripts are addressed by `sha256(run_config || move_history)`
    because the human's choices make the post-config bytes non-deterministic. The
    current Sprint `7.4` baseline writes `:save` transcripts through
    `MCTS.Transcript.writePlayTranscript`, routes AI turns through the selected
    backend's dynamic FFI search path when a foreign shared library is present,
    and unit-tests the write/decode plus selected-backend AI advance paths.
35. `inspect replay` loads cached equity sidecars before opening the TUI and fills a
    missing originator sidecar by replaying the search through the same backend. The
    replay preparation compares the recomputed chosen action and visit table against
    the transcript under `--rng cpp` before writing the `.eq`; failures surface in the
    TUI status line. The last `replayCacheStates` board states (default 20,
    `--cache-states N`) are kept in memory for back-navigation.
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
    cohort. `checkTranscriptEnvelopesLive`, exercised by integration and Q3/Q7 verify,
    also checks per-backend-slot fields between a cached transcript and the live binary
    for the same backend slot (downgradeable to a warning via the `--allow-stale` flag
    for forensic comparisons). FFI-produced transcripts carry the live
    `mcts_<backend>_get_envelope()` payload when the matching cdylib is present;
    absent cdylibs use the in-process fallback envelope. Cross-backend differences in
    per-backend-slot fields are expected and silent — the `verify` contract
    is "different backend slots, identical visits." See
    [../documents/engineering/determinism_contract.md → Engine Envelope](../documents/engineering/determinism_contract.md).
38. Equity sidecar cache layout under the existing transcript cache root:
    `<cache-root>/transcripts/<arch>/<sha>/<backend>-<build_label>.eq`
    plus a `.envelope` neighbour file holding the envelope of the build that wrote
    the `.eq`. Live envelopes use the first 16 hex characters of
    `engine_build_id`; logical all-zero envelopes use `<backend>-logical`.
    Multi-build cohabitation is automatic — a rebuild lands in a fresh
    cache slot keyed by the new build label; old slots remain for
    forensic comparison until explicitly pruned (`mcts inspect cache prune`). The
    sidecar is read on `inspect replay` and `inspect show --with-equity` for instant
    cache hits; `inspect replay` fills missing originator overlays before TUI start,
    while `inspect show --with-equity` writes the requested logical sidecar. See
    [../documents/engineering/transcript_format.md → Equity Sidecar Cache](../documents/engineering/transcript_format.md).
39. Divergence-smell thresholds per
    [../documents/engineering/determinism_contract.md → Divergence Smell](../documents/engineering/determinism_contract.md):
    same-substrate and `--rng cpp` cross-backend cohorts (ii)–(v) hard-fail on any
    visit-count or move disagreement (the existing contract); `--rng native`
    cross-backend and cross-build same-backend comparisons surface
    `move_disagreement_rate` and `visit_disagreement_rate` annotations in the REPL
    column headers and in the `mcts test all` report-card matrix, warning when the
    measured rate exceeds the thresholds (mirrored in `cabal.project` comments after
    Phase 7 calibration).
40. Normal validation must pass from a clean clone without pre-existing transcripts,
    throughput anchors, report-card schemas, renderer snapshots, or other generated
    validation data. Tests generate transcripts, sidecars, report-card values, and
    renderer examples in memory or under temporary directories. Runtime/operator cache
    files live under ignored roots such as `.mcts-cache/`; retired-backend evidence is
    historical or optional external/local data.

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
| 7 | Phases 4, 5, 6 | The pre-retirement cross-backend `verify` cohort and the POC report card required all five backend slots to produce evidence |
| 8 | Phase 7 | Performance parity closure requires the report-card numbers from Phase 7 to measure Haskell against backend (ii); the retirement protocol then runs the (i)→(ii)→(iii)→(v) chain |

## Current Baseline

Phase `1` is closed again after the Compose-only operator-surface doctrine
update and the 2026-05-19 parser/lint alignment sweep: repository `.sh`
wrappers and `bootstrap/` helpers are forbidden surfaces, the registry/parser
contract matches the governed command surface, and the lint-stack docs now
point at the committed formatter SSoT while the source walker guards
supported-path partial functions. Phase `2` is also closed again after the
transcript/cache/envelope alignment sweep, and Phase `6` is closed again after
the Rust build-harness tuning alignment. Phase `7` is closed again after the
digest-first verifier comparator, length-aware mismatch surfaces, `mcts play`
side/opponent runtime contract, and replay overlay row contract were aligned.
Phase `8` has closed the performance-parity proof and retired backends (i),
(ii), and (iii) from the live surface, but remains active for the final
compiler-runtime plan alignment and no-generated-validation-data sweep.

| Surface | Current Repo State | Intended End State |
|---------|--------------------|--------------------|
| Repository layout | `app/`, `src/MCTS/`, `src/MCTS/Generated/`, `cpp-legacy/`, `cpp-imperative/`, `cpp-functional/`, `rust/`, `bench/`, `test/`, `docker/`, root `compose.yaml`, `cabal.project`, `fourmolu.yaml`, `.hlint.yaml`, `.gitignore`, `mcts.cabal`, generated-artefact targets `documents/cli/commands.md`, `share/man/man1/mcts.1`, and `share/completion/{bash,zsh,fish}/` | Same layout, with no generated validation data required under `test/` |
| Build artefacts | `mcts.cabal` declares the `mcts` binary, live Haskell test stanzas, and the doctrine-standard dependency envelope; host validation enters through `docker compose run --rm mcts mcts check-code` under the pinned toolchain. The live foreign backend tree is `rust/src/`; `cpp-legacy/` is retained for reference and `legacy-to-wire` fixture generation, `cpp-imperative/` is retained as a retired backend (ii) reference, and `cpp-functional/` is retained as a retired backend (iii) reference. The Rust crate carries the full Corridors gameplay port (board.rs + rollout.rs + search.rs); the Rust PGO/BOLT install pipeline ships via the typed `Subprocess` boundary. Haskell loads the live Rust shared library dynamically through `MCTS.FFI.Common`; the link-time-bound `extra-libraries` policy is ledger residue. | Container-image `mcts` binary produced by `docker/Dockerfile`, plus the container-local live backend shared library (`rust/target/release/libmcts_rust.so`) |
| CLI surface | The complete live command family is wired: `bench`, `verify`, `inspect`, `test`, `lint`, `docs`, `commands`, `help`, `check-code`, `build`, and `play`. Generated command docs are checked against the renderer, tracked generated-file drift fails `mcts lint files`, generated path/section registries live under `src/MCTS/Generated/`, and `mcts test all` routes recursive CLI calls through `cabal exec mcts -- ...`. The bench/play/inspect paths dispatch through real FFI for backend (iv) whenever the Rust shared library is present in the build tree; Q3 `verify` uses `runBatchDispatch` and the live FFI engine when the cdylib is present and the run is compatible with the fixed 60-ply foreign search horizon, with an in-process fallback when it is absent or a lower search cap is requested. The `mcts verify legacy-parity` and C++ build leaves retired in Sprints 8.4-8.6. Verify command constructors carry typed `VerifyBackend` backend lists, with parser-boundary guards excluding retired backends from default verify. `mcts play` and `mcts inspect replay` dispatch to `brick` TUIs on TTY and non-interactive fallbacks on pipes; `mcts play :save` writes hand-play transcripts addressed by `sha256(run_config || move_history)`, AI turns use the selected backend's dynamic FFI search path when its shared library is present, and replay fills a missing originator `.eq` overlay before TUI start. Renderer tests assert layout semantically rather than via checked-in goldens. | Same surface backed by real Haskell and Rust engines, with C++ backends retained as retired source/evidence archives |
| Test stanzas | Four live Cabal stanzas exist: `mcts-unit`, `mcts-integration`, `mcts-cross-backend`, `mcts-haskell-style`; each stanza has its own `tasty` runner, and `docker compose run --rm mcts mcts test all` is the host validation gate under the pinned container toolchain. `mcts-unit` uses semantic/property/temp-dir checks instead of `tasty-golden`; `mcts-integration` synthesizes retired-backend evidence in temporary roots. | Same live stanzas and fine-grained `tasty` organization; all validation data is generated in memory or temporary directories during the run, so clean-clone validation has no `test/golden/` prerequisite |
| Toolchain | `mcts.cabal` pins `tested-with: ghc ==9.14.1`; `cabal.project` pins `with-compiler: ghc-9.14.1` and mirrors the report-card constants as comments. The style-tool policy pins GHC `9.12.4` only for Fourmolu/HLint installation inside the container. | GHC `9.14.1`, Cabal `3.16.1.0`, style GHC `9.12.4` for `fourmolu-0.19.0.1` / `hlint-3.10`, GCC latest stable on `ubuntu:24.04`, Rust latest stable with pinned minor, LLVM pinned in the Dockerfile |
| Determinism contract | The live Rust foreign backend (iv) dispatches through the real FFI engine under `bench`, `play`, `inspect divergence`, integration smokes, and Q3 `verify` when its shared library is present and the fixed search-horizon ABI can represent the run. Transcript codec, full v1 envelope, SHA-256 content addressing, cache root resolution, prefix lookup, binary `MEQ1` equity sidecars, layered envelope checks, `divergenceVsEqStream`, live foreign-recompute divergence rows, cached Rust `read_visits`, canonical search-side 12-wall child caps across the live cohort, decoded real-binary transcript determinism, and hard-fail `VerifyMismatch` rollout/self-play cohorts in `mcts-cross-backend` are implemented. Backend (i) legacy visit-count or chosen-move divergence from the steelman cohort is outside the live Q3 comparison contract. | Enforced by live-FFI-capable cross-backend `mcts verify {rollouts,selfplay}`, decoded same-backend transcript checks, live FFI-envelope cases under `mcts-integration`, and synthetic legacy-envelope checks generated during tests |
| Performance parity | Proven against backend (ii)'s recorded steelman evidence. The historical 2026-05-19 `docker compose run --rm mcts mcts test all` run recorded Q1 ST 0.05×, Q1 MT8 0.41×, Q2 ST 0.05×, Q2 MT8 0.20×, Q5 Haskell 0.99×, Q5 cpp-imperative 3.64×, Q7 liveness PASS, and `Verdict: Within tolerance`; the current report-card path compares live Haskell timings to the frozen backend (ii) throughput anchor and reports Q6/Q7 as `HIST`. Sprint `8.4` retired backend (i); Sprint `8.5` recorded backend (iii)-vs-backend (ii) parity; Sprint `8.6` recorded backend (v)-vs-backend (iii) parity. | Haskell (v) within tolerance of C++ (ii) on Q1 and Q2, single-threaded and on 8 workers, recorded as historical report-card evidence rather than a checked-in generated throughput anchor |

## Related Documents

- [README.md](README.md)
- [development_plan_standards.md](development_plan_standards.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
- [../README.md](../README.md)
