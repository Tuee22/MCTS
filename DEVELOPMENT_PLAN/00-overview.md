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
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md),
[../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md),
[../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md)
**Generated sections**: none

> **Purpose**: Capture the target architecture, current baseline, doctrine scope,
> hard constraints, and dependency chain that every MCTS phase depends on.

## Vision

The MCTS runtime is the successor to `MCTS_legacy` and must satisfy three properties
simultaneously:

- **As fast as maximally-optimised imperative C++** on the refactored POC metric
  suite: terminal playout throughput, search-iteration throughput, and played-game
  self-play throughput per
  [../documents/engineering/benchmark_metrics.md](../documents/engineering/benchmark_metrics.md).
  The bar is not the legacy as it exists today — it is the
  strongest imperative-C++ implementation the project can build using every reasonable
  modern technique (LTO, two-stage PGO, BOLT post-link, `mimalloc`, arena-allocated tree
  nodes, scratch-board rollouts, branch hints). Backend (ii) is that ceiling; backend (v)
  Haskell must match it.
- **Purely functional at the API surface** in its final form, so algorithmic changes
  (search policies, evaluators, prior shaping) are local edits rather than rewrites.
  Internally the Haskell engine is free to use `ST`-monad mutable unboxed arrays as the
  only realistic way to match optimised imperative C++; the local-reasoning property is
  preserved by keeping public types and operations pure. The functional comparison
  cohort `(iii)`, `(iv)`, and `(v)` uses the shared functional-core value-state style in
  [../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md);
  local mutation, compact bitfields, and arenas are allowed, while legacy board graphs
  and text action decoding are not treated as functional-core costs.
- **Deterministic inside the documented envelope.** Same-backend runs are reproducible for
  the same seed, RNG source, and logical inputs; cross-backend bit equality is asserted for
  backends `(ii)..(v)` under `--rng cpp`; backend `(i)` is covered by the legacy-parity
  envelope rather than the Q3 equality cohort (see Hard Constraint 36 below and the
  **Engine Envelope** section in
  [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md)).
  Reproducibility is a first-class invariant, not a debugging aid; the engine envelope
  captured in every transcript lets `inspect replay` and `mcts verify` detect substrate
  drift rather than silently displaying ULP-shifted floats as if they were the
  originator's.

**Long-term horizon (out of scope for this plan).** The project
[../README.md](../README.md) declares an eventual AlphaZero-style ANN evaluation goal.
Phases `0`–`8` own the rollout-based MCTS hypothesis only; no ANN, no learned
evaluator, and no Python ML stack appears on the supported path. The intended
final handoff is a parity-proven five-backend CLI that a successor effort can
inherit without reconstructing C++ or Rust comparison evidence; the current
optimized-C++ parity evidence is refreshed against the Dockerfile build that
fails closed on mandatory PGO+BOLT profile data instead of accepting fallback
artifacts. The historical Sprint `8.10` closure used profile data from the bounded
played-game profile suite in `MCTS.CLI.Build`; Sprint `8.11` extends that suite
with primitive terminal-playout and search-iteration profile runs. Sprint `5.6`
later reopened parity evidence against the corrected backend (ii), making Sprint
`8.11` historical metric-suite evidence; Sprint `8.12` supplies the final
corrected-target parity closure.

## Current Handoff Status

The 2026-05-19 report card remains useful smoke-baseline audit evidence, and the
2026-05-21 optimized-C++ report-card refresh remains historical evidence against
the then-canonical backend (ii) artefact. Under the 2026-05-22 fail-closed
PGO+BOLT doctrine, that evidence cannot close parity because C++ BOLT produced no
`.fdata` and the build installed a fallback artifact. The 2026-05-23 Dockerfile
build and aggregate report-card run reclosed that gap: C++ and Rust BOLT profiles,
bolted canonical libraries, LLVM objcopy envelope patching, final installed-library
smokes, and Q1/Q2/Q5/Q6 parity evidence are validated against mandatory PGO+BOLT
artefacts.
The five-backend surface is restored: `cpp-legacy`, `cpp-imperative`,
`cpp-functional`, `rust`, and `haskell` are first-class parser/build/verify/FFI
participants.

The 2026-05-21 evidence-surface audit reopened Phases `1`, `2`, `5`, `6`, `7`,
and `8` for focused reclosure. Sprint `1.10` has reclosed generated-doc metadata
and style-policy alignment. Sprint `2.8` has reclosed transcript version
handling, action-domain wording, and sidecar identity. Sprint `5.5` has reclosed
the compact backend (ii) C ABI contract, and Sprint `5.3` has reclosed C++
PGO/BOLT fail-closed behavior. Sprint `6.6` has reclosed backend (iii)/(iv)
ABI and Rust instrumentation wording, and Sprint `6.4` has reclosed the Rust
PGO/BOLT fail-closed build. Sprint `7.6` has reclosed replay/divergence evidence
labels. Sprint `8.9` has reclosed compiler-tuning wording, Sprint `8.3` has
reclosed the report-card refresh against the reclosed build artefacts, Sprint
`8.10` has reclosed the played-game profile-representativeness gate, and Sprint
`8.11` has reclosed the refactored metric-suite rerun. The build harness now
trains Dockerfile-time PGO/BOLT with terminal playout, search-iteration, legacy
played-game rollout, and self-play runs, both single-threaded and MT8, under
native RNG with seeds `42` and `424242`; `MCTS.CLI.Build` pins the exact primitive
counts, played-game counts, ply caps, and self-play simulation budgets.
Phases `3` and `4` remain `Done` on their owned surfaces; Phase `3` Sprint `3.8`
closed the primitive `playouts/s` and `search-iters/s` benchmark leaves on
2026-05-24. Later phases remain valid on historical implementation work within
their scoped surfaces.

The 2026-05-24 benchmark-metric audit reopened the metric suite because the
then-current Q1/Q2/Q5 report-card rows were played-game measurements under legacy
`rollouts`/`selfplay` labels, not terminal playout or search-iteration
measurements. Phase `3` has closed the missing benchmark primitives, Phase `7`
has closed the report-card row split, and Phase `8` Sprint `8.11` closed the
refactored parity rerun against the then-current backend (ii). Sprint `8.12`
has refreshed that evidence against the corrected backend (ii), and the accepted
report-card verdict is `Within tolerance`.
Phase `7` Sprint `7.9` revalidated the headline report-card mapping on
2026-05-25: there are six questions, Q6 is the all-five legacy-envelope gate,
and external `MCTS_legacy` reproduction fixtures are optional audit data rather
than a numbered report-card row.
Historical played-game numbers remain audit evidence, not final answers to the
refactored Q1a/Q1b/Q2/Q5 suite.

Sprint `5.6` reclosed Phase `5` on 2026-05-25 after backend (ii) moved from the
legacy board hot path to a compact bitfield board with direct capped move
generation and wavefront escapability checks. Focused rebuilt-image benchmarks
now show backend (ii) outperforming backend (i), as the steelman design requires.
That same correction reopened Phase `8` on the Haskell parity surface: the earlier
`Within tolerance` report-card verdict is historical evidence against the slower
backend (ii), not closure against the corrected C++ ceiling. Sprint `8.12`
reclosed that parity surface on 2026-05-26.

Phase `6` Sprint `6.7` reclosed on 2026-05-26: backend (iii)'s former
legacy-board/text-action path is gone from the hot path and no longer explains
the `(ii)` vs `(iii)` performance gap. Backend (iii) now uses compact
functional-core C++ value state, direct capped numeric legal generation, and the
same style backend (iv) Rust already followed. Phase `8` Sprint `8.13` is
closed after Sprint `8.12`; backend (v) Haskell now keeps its pure API boundary
while its hot search path follows the same compact numeric action-set transition
style as `(iii)` and `(iv)`.

## Target Outcome

One `mcts` Haskell CLI binary, built by Cabal under GHC `9.14.1` and Cabal
`3.16.1.0`, drives all five backend slots behind a uniform command surface.
Backend (i) `cpp-legacy/` is a strictly verbatim re-port of `MCTS_legacy` used
for legacy compatibility and Q6 legacy-envelope evidence. Backend (ii)
`cpp-imperative/` is the maximally-tuned imperative C++23 performance ceiling.
Backend (iii) `cpp-functional/` uses the same PGO+BOLT+`mimalloc` optimisation
stack while adopting the functional-core value-state style shared with backend
(iv) `rust/` and backend (v) `haskell`. Backends (ii), (iii), and (iv) publish one
canonical bolted shared library each; the Dockerfile currently trains PGO/BOLT once
on the bounded metric-suite profile suite implemented in `MCTS.CLI.Build`, and
runtime commands do not retrain or switch between workload-specific libraries.
Backend (v) is the pure Haskell engine running natively in the same process, with
`ST`-monad mutable arena internally and pure search API externally.

Three POC metric units exercise the cohort: terminal playout throughput
(`playouts/s`), search-iteration throughput (`search-iters/s`), and played-game
self-play throughput (`games/s`). Performance benchmarks run single-threaded and on
8 workers where batching applies under `--rng native`, where each backend uses its
own fast/native deterministic RNG contract and no cross-backend transcript identity
is expected.
Logical-equivalence verification uses the same workloads under `--rng cpp`, where
equivalence tests consume C++-generated verification seeds through the shared C++ RNG
bridge so MCTS transcripts can be compared exactly. `mcts verify` round-robin-compares
visit counts under `--rng cpp` across `(ii)..(v)`. `mcts verify legacy-parity` supplies
the Q6 legacy-envelope liveness/overflow check across all five backend slots.
`mcts test all` emits the tidy POC report-card summary block answering Q1-Q6 in one
screenful. The current implementation emits unit-aware Q1a terminal playout, Q1b
search-iteration, Q2 played-game, and split Q5 scaling rows; Sprint `8.11`
provided historical closure evidence for those rows, and Sprint `8.12` refreshed
the verdict against the corrected backend (ii). Live
workload constants are implemented in `MCTS.CLI.Test` and mirrored in
`cabal.project` comments. Legacy-envelope knobs remain live report-card metadata.
Normal validation never depends on checked-in generated transcripts, throughput
JSON, or snapshot files; tests synthesize or explicitly generate evidence in
temporary or operator-provided roots.

## Architecture Overview

- **Haskell CLI surface.** One binary `mcts`. `CommandSpec` owns the command tree,
  examples, generated command reference, manpage command list, JSON/tree/list
  introspection, and tracked shell-completion artefacts. `MCTS.CLI.Parser` renders the
  topology from that registry, while the leaf option parsers remain explicit semantic
  parsers in `Parser.hs`; the parser is therefore not a competing CLI source of truth.
  The library-first layout puts `app/Main.hs` thin and logic in `src/MCTS/`.
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
  search and random-rollout leaf evaluation in the `ST s` monad, and a pure API at
  the boundary. The current game loop allocates a fresh arena for each per-move
  search; `treeReroot` is a tested arena primitive, not an across-move persistence
  path. Per-CPU LLVM
  `-mcpu=native` flags are intentionally excluded on the current aarch64 container and
  documented as deferred tuning rather than pending cleanup. Owned by
  [phase-3-haskell-engine.md](phase-3-haskell-engine.md).
- **Backend (i) C++ legacy port and FFI bridge.** Verbatim re-port from `~/MCTS_legacy`
  with only the FFI shims required to expose a C ABI; inherits the legacy's
  `std::shared_ptr<uct_node>` trees, `std::mt19937_64` RNG, single-threaded design, and
  no draw rule (`is_terminal()` ↔ `hero_wins() || villain_wins()`). It remains live for
  Q6 legacy-envelope liveness/overflow evidence;
  it is not part of the default Q3 `(ii)..(v)` visit-vector identity cohort because its
  legacy tree semantics intentionally differ from the steelman cohort. Owned by
  [phase-4-cpp-legacy-port-and-ffi-bridge.md](phase-4-cpp-legacy-port-and-ffi-bridge.md)
  and Phase `8` restoration.
- **Backend (ii) C++ imperative steelman.** The performance ceiling. C++23 with `-O3
  -march=native -mtune=native -flto -fno-plt -fno-semantic-interposition
  -fvisibility=hidden -fvisibility-inlines-hidden -fno-exceptions`, no `-ffast-math`;
  Makefile-level two-stage PGO via `-fprofile-generate` / `-fprofile-use`, BOLT
  post-link targets, `mimalloc` link; arena tree, compact bitfield board,
  direct capped legal-move generation, wavefront bitset escapability, flat children
  layout, move-list buffer reuse, branch hints, `__builtin_prefetch`,
  `__builtin_popcountll` / `__builtin_ctzll`, `alignas(64)`, `thread_local` scratch.
  The Dockerfile routes the PGO/BOLT sequence through the
  `mcts build cpp-imperative` build recipe. PGO profile data and BOLT `.fdata`
  are mandatory image-build outputs; installing a PGO-only or unoptimized fallback
  under the canonical load name is forbidden and must fail the Dockerfile build.
  Sprint `8.10` replaced the earlier narrow self-play training runner with a
  bounded profile suite, and Sprint `8.11` extends that suite with primitive
  terminal-playout and search-iteration profile runs after the metric refactor.
  Owned by
  [phase-5-cpp-imperative-steelman.md](phase-5-cpp-imperative-steelman.md) and Phase
  `8` parity closure.
- **Backends (iii) C++ functional-core and (iv) Rust.** Backend (iii) mirrors
  backend (ii)'s Makefile-level optimisation target surface so the `(ii)` vs
  `(iii)` comparison can isolate style under the shared C++ PGO/BOLT CLI path, and
  Sprint `6.7` closed its compact value-state C++ hot path without legacy
  `corridors::board` or action-text parsing. Backend (iv) Rust follows the
  same functional-core style with Rust ownership idioms and runs on the latest
  stable compiler with the
  pinned `[profile.release]` (`opt-level = 3`, `lto = "fat"`, `codegen-units = 1`,
  `panic = "abort"`, `strip = "debuginfo"`), `RUSTFLAGS=-C target-cpu=native -C
  link-arg=-fuse-ld=lld -C link-arg=-Wl,--emit-relocs`, `mimalloc` through the
  container system library as `#[global_allocator]`, two-stage rustc PGO, and BOLT
  post-link. Their current accepted profiles use the same Dockerfile-time bounded
  metric-suite profile suite as backend (ii): terminal playout, search-iteration,
  legacy played-game rollout, and self-play workloads. Owned by
  [phase-6-cpp-functional-and-rust.md](phase-6-cpp-functional-and-rust.md) and
  [../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md).
- **Cross-backend verify, test stanzas, POC report card.** Five live Cabal test-suite
  stanzas (`mcts-unit`, `mcts-integration`, `mcts-cross-backend`,
  `mcts-legacy-parity`, `mcts-haskell-style`), each `type: exitcode-stdio-1.0` with
  `tasty` as the in-stanza runner; `mcts test all` is a Plan/Apply command whose
  exact sequence is owned by
  [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md)
  and whose high-level surface covers lint/docs prerequisites, warning-clean build,
  Dockerfile-built canonical foreign backend artefacts, Cabal stanzas, verify
  cohorts, the pinned no-write report-card workload, and the tidy summary block.
  Owned by
  [phase-7-cross-backend-verify-and-report-card.md](phase-7-cross-backend-verify-and-report-card.md).
- **Haskell performance parity closure.** GHC `-O2 -fllvm`,
  `-funbox-strict-fields`, `-fspecialise-aggressively`,
  `-fexpose-all-unfoldings`, `-flate-dmd-anal`, `-fmax-simplifier-iterations=20`,
  `-fworker-wrapper`, `-fstatic-argument-transformation`, RTS `-A64m -n4m -qg1 -qb -T`,
  `INLINABLE` on the search hot path, unboxed strict fields everywhere, no
  `Maybe`/`Either` in the rollout inner loop, until backend (v) matches backend (ii) on
  Q1 and Q2 within the parity tolerance per
  [../documents/engineering/compiler_runtime_tuning.md → Parity Tolerance](../documents/engineering/compiler_runtime_tuning.md)
  (`HASKELL_PARITY_TOLERANCE = 0.05`). Phase `8` also keeps all five backends live while
  removing stale two-backend drift and preserving the rule that generated validation data
  is not checked into git. Owned by
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
  `--plan-file <path>` on every Plan/Apply command. Current consumers are
  `mcts test all`, `mcts test parity-anchor`, `mcts docs generate`,
  `mcts inspect cache prune`, `mcts build <backend>`, and
  `mcts build legacy-fixtures`.
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
- Testing Doctrine and Test Organization — five live Cabal stanzas, each
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
  [../HASKELL_CLI_TOOL.md → Error Handling](../HASKELL_CLI_TOOL.md) exactly;
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
- GADT-indexed state machines where naturally indicated (`VerifyBackend`; Q6
  legacy-parity validates the complete backend list under the legacy envelope);
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
5. Two RNG sources are supported and intentionally serve different goals:
   `--rng native` is for performance benchmarks and operator play, where each backend
   uses its own fastest deterministic RNG contract and benchmark streams are not
   expected to be cross-backend bit-equal. `--rng cpp` is for logical-equivalence
   verification, where every participating backend consumes C++-generated
   verification seeds from the shared RNG bridge so game transcripts, visit tables,
   and chosen moves can be compared exactly.
6. `--rng cpp` is the implicit default for `verify` and is not user-overridable on the
   `mcts verify` subtree. The native RNG cannot validate cross-backend bit equality.
7. `VerifyBackend` covers the Q3 logical-equivalence cohort `(ii)..(v)`:
   `cpp-imperative`, `cpp-functional`, `rust`, and `haskell`. Backend (i) is excluded
   from Q3 because its terminal-state and tree semantics are deliberately verbatim legacy
   behavior, not because it is unsupported.
8. The legacy-parity parser surface covers Q6 across all five backend slots under the
   legacy envelope. Q6 is a liveness/overflow and chosen-envelope check; Q3 remains the
   visit-vector identity proof for the steelman cohort `(ii)..(v)`.
9. Backends (ii)–(v) carry a `Word16` ply counter in board state and add the ply-cap
   draw rule: `is_terminal` ↔ `hero_wins || villain_wins || ply_count >= max_plies`;
   `get_terminal_eval` returns `0.0` on ply-cap termination. Default `max_plies = 200`,
   pinned in the transcript header. Backend (i) lacks the ply cap and is verbatim from
   `MCTS_legacy`.
10. The legacy parity envelope pins `max_plies = 10000` (= `MAX_ROLLOUT_ITERS` in the
    legacy). Q6 uses that envelope as a five-backend liveness/overflow gate, while Q3
    owns visit-vector equality across `(ii)..(v)`.
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
14. Search trees are memory-resident only — nothing is serialised between runs. The
    current Haskell driver allocates a fresh `STUArray` arena for each per-move
    search; across-move tree persistence is not implemented in the closed baseline.
    `MCTS.Search.Arena.treeReroot` exists as a tested primitive for future
    profile-driven work, but the game loop does not keep inherited visits warm.
15. Originator equity is recomputed only by the same backend/build slot that produced the
    transcript, or by a live binary whose envelope matches the transcript's recorded
    originator envelope. Cross-backend and logical-fallback recomputes are foreign-view
    evidence and must not be written or displayed as originator evidence. Cross-backend
    equity bit-equality is not asserted; the Q3 determinism contract is on visit counts
    (integer, order-independent) only. Float drift across the Q3 verification cohort
    `(ii)..(v)` that changes UCT child selection or the final highest-visit root action
    surfaces as a visit-count mismatch on the next move and is caught by `mcts verify`.
16. The toolchain is pinned at GHC `9.14.1` and Cabal `3.16.1.0`. `mcts.cabal` declares
    `tested-with: ghc ==9.14.1`; `cabal.project` declares `with-compiler: ghc-9.14.1`.
17. Backend (i) `cpp-legacy/` is strictly verbatim from `~/MCTS_legacy/backend/`. Only
    FFI shims are permitted around the imported legacy source. The build flags are
    `-std=c++17 -O3 -fPIC -Wall`.
    It uses `std::shared_ptr<uct_node>` trees and `std::mt19937_64` unchanged.
18. Backends (ii) and (iii) compile with `-std=c++23 -O3 -march=native -mtune=native
    -flto -fno-plt -fno-semantic-interposition -fvisibility=hidden
    -fvisibility-inlines-hidden -fno-exceptions`. `-fno-exceptions` is mandatory
    (the engine core does not throw, so landing-pad cost is unconditional dead
    weight). No `-ffast-math` and no `-Ofast`. The PGO+BOLT pipeline plus
    container-provided `mimalloc` link is required and must complete inside the
    Dockerfile build. Missing PGO profile data, missing BOLT `.fdata`, or copying a
    lesser artefact into the bolted/canonical load path is a build failure, not an
    accepted fallback. The installed bolted libraries are smoke-tested before the
    image is published. `g++` only — Clang is not supported on the C++ side. Sprint
    `5.3` owns the fail-closed C++ PGO/BOLT CLI wiring; Sprint `8.10` replaced
    the earlier narrow training run with a bounded profile suite and Sprint
    `8.11` adds and validates the primitive benchmark workloads.
19. Backend (iv) Rust uses `[profile.release]` with `opt-level = 3`, `lto = "fat"`,
    `codegen-units = 1`, `panic = "abort"`, `strip = "debuginfo"`. `RUSTFLAGS=-C
    target-cpu=native -C link-arg=-fuse-ld=lld -C link-arg=-Wl,--emit-relocs`.
    `mimalloc` as `#[global_allocator]` through the container system library.
    Two-stage `rustc -Cprofile-generate` / `-Cprofile-use` PGO. BOLT post-link.
    The Dockerfile build must fail if profile merge, BOLT instrumentation, BOLT
    training, BOLT optimization, or the final installed-library smoke cannot produce
    the required optimized cdylib. Sprint `8.10` aligned that PGO/BOLT path with
    the same bounded profile suite as the C++ steelman backends, and Sprint `8.11`
    adds and validates the primitive benchmark workloads.
20. Backend (v) Haskell uses `-O2 -fllvm`, `-funbox-strict-fields`, `-fspecialise-aggressively`,
    `-fexpose-all-unfoldings`, `-flate-dmd-anal`, `-fmax-simplifier-iterations=20`,
    `-fworker-wrapper`, `-fstatic-argument-transformation`. RTS `-A64m -n4m -qg1 -qb
    -T` is baked into the executable. Engine hot path lives in `ST s`; tree is a
    structure-of-arrays `STUArray` arena of unboxed `Int32` / `Float` fields; board
    state is `Word64` bitboards manipulated with `Data.Bits`. Pure API at the
    boundary; no `Maybe` / `Either` in the rollout inner loop. LLVM
    `-optlo-mcpu=native` / `-optlc-mcpu=native` is deferred on aarch64 until
    the assembler target accepts the emitted LSE instructions.
21. Library-first layout: `app/Main.hs` is thin; logic lives under `src/MCTS/`.
22. `CommandSpec` is the source of truth for the command topology, examples, generated
    command reference, manpage command list, command-tree rendering, JSON
    introspection, and tracked shell-completion artefacts. `MCTS.CLI.Parser` renders
    subcommand topology from the registry and keeps leaf option parsing as explicit
    typed semantic parsers.
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
    `mcts-legacy-parity`, and `mcts-haskell-style`. A single `tasty` tree spanning all
    tiers is forbidden.
28. `fourmolu.yaml` at repo root pins the twelve doctrine-mandated settings; the
    `mcts-haskell-style` stanza enforces them plus `cabal format` temp-file round-trip
    byte-equality through the separate formatter-tools install (`ghc-9.12.4`,
    `fourmolu-0.19.0.1`, `hlint-3.10`) under `/opt/mcts-style-tools/bin/` inside the
    container. Host `PATH` fallback is never allowed.
29. Report-card live workload constants are implemented in `MCTS.CLI.Test` and
    mirrored in `cabal.project` comments: `G_R = 1_000`, `G_S = 4`,
    `G_V = 4`, `G_LP = 2`, `S_BENCH = 500`, `S_VERIFY = 500`,
    `S_LP_SIMS = 4`, and `S_LP = 42`.
30. All five backend identifiers, build leaves, transcript wire tags, and verification
    roles remain first-class. Checked-in generated transcripts, throughput JSON,
    report-card schemas, and renderer snapshots are not part of the normal validation
    surface; evidence is generated in memory, in temporary roots, or through explicit
    operator-provided artifact directories.
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
    `compiler_id` + `compiler_version`, `fp_flags`, `libm_id`,
    `cpu_features`, `fp_env`). `mcts verify` hard-fails with
    `AppError EngineEnvelopeMismatch` when cohort-invariant fields disagree across the
    cohort. `checkTranscriptEnvelopesLive`, exercised by integration and Q3/Q6 verify,
    also checks per-backend-slot fields between a cached transcript and the live binary
    for the same backend slot (downgradeable to a warning via the `--allow-stale` flag
    for forensic comparisons). FFI-produced transcripts carry the live
    `mcts_<backend>_get_envelope()` payload when the matching cdylib is present;
    `engine_git_commit` and the display/cache `build_id` accessor remain provenance
    only and do not gate stale-envelope verification.
    absent cdylibs use the in-process fallback envelope. Cross-backend differences in
    per-backend-slot fields are expected and silent — the `verify` contract
    is "different backend slots, identical visits." See
    [../documents/engineering/determinism_contract.md → Engine Envelope](../documents/engineering/determinism_contract.md).
38. Equity sidecar cache layout under the existing transcript cache root:
    `<cache-root>/transcripts/<arch>/<sha>/<backend>-<build_label>.eq`
    plus a `.envelope` neighbour file holding the envelope of the build that wrote
    the `.eq`. Live build labels use the first 16 hex characters of
    `engine_build_id`; logical all-zero GHC envelopes use the `logical` build
    label, yielding full sidecar names such as `<backend>-logical.eq`.
    Multi-build cohabitation is automatic — a rebuild lands in a fresh
    cache slot keyed by the new build label; old slots remain for
    forensic comparison until explicitly pruned (`mcts inspect cache prune`). The
    sidecar is read on `inspect replay` and `inspect show --with-equity` for instant
    cache hits; originator cache misses are filled only by the matching backend/build,
    and foreign-view recomputes are labelled as foreign evidence. See
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
    files live under ignored roots such as `.mcts-cache/`; optional audit artifacts live
    in explicit external or ignored local roots.

## Dependency Chain

| Phase | Depends On | Why |
|-------|------------|-----|
| 0 | — | Bootstrap |
| 1 | Phase 0 | The CLI surface and lint stack consume the doctrine in-scope/out-of-scope split and the standards rule L doctrine-citation contract |
| 2 | Phase 1 | The transcript codec, hash-prefix lookup, and RNG plumbing register their CLI surface (`inspect list`, `inspect show`, `--cache-dir`, `--rng`) and their Plan/Apply discipline through the registry built in Phase 1 |
| 3 | Phase 2 | The Haskell engine writes transcripts in the wire format pinned by Phase 2 and consumes the `splitmix64(master_seed, game_index)` seed derivation |
| 4 | Phase 3 | The C ABI FFI bridge from Haskell to backend (i) reuses the `Subprocess` boundary and `Env` record established by Phases 1 and 3, and validates against the same transcript codec |
| 5 | Phase 3 | Backend (ii) likewise builds on the FFI bridge pattern; it is independent of (i) once the pattern is established, so Phases 4 and 5 may proceed in parallel after Phase 3 closes |
| 6 | Phase 5 | Backend (iii) shares (ii)'s optimisation stack and must be developed against the validated steelman; Sprint `6.7` removed legacy representation costs so `(iii)`, `(iv)`, and `(v)` can share the functional-core style contract |
| 7 | Phases 4, 5, 6 | Cross-backend `verify`, legacy parity, and the POC report card require all five backend slots to produce evidence |
| 8 | Phase 7 plus fail-closed Sprints `5.3`, `6.4`, and `6.7` | Performance parity closure requires report-card numbers against optimized backend (ii) after Dockerfile-time PGO/BOLT succeeds and the report card separates terminal playout, search-iteration, and played-game metrics; Phase `8` owns the restored five-backend live surface, Sprint `8.3` refreshed the report card against reclosed fail-closed build artefacts, Sprint `8.10` closed the historical played-game profile-representativeness gap, Sprint `8.11` closed the refactored metric rerun, Sprint `8.12` refreshed against the corrected backend (ii), and Sprint `8.13` kept backend (v) aligned with the functional-core style after Sprint `6.7` |

## Current Baseline

The repository has a restored five-backend implementation baseline, and the
2026-05-21 evidence-surface audit reopened focused alignment work. Phase `1`
has reclosed generated-doc metadata enforcement and style-policy wording. Phase
`2` has reclosed strict v1 transcript/envelope wording, action-domain docs, and
sidecar identity. Phase `5` has reclosed backend (ii)'s compact C ABI contract
and C++ PGO/BOLT fail-closed behavior. Phase `6` has reclosed backend
(iii)/(iv) ABI wording, Rust build-artifact/instrumentation language, and Rust
PGO/BOLT fail-closed behavior. Phase `7` has reclosed replay and divergence labels.
Phase `8` has reclosed tuning-doc wording, the Sprint `8.3` report-card refresh
against mandatory Dockerfile-time PGO/BOLT artefacts, and the Sprint `8.10`
bounded played-game profile-training gate. The 2026-05-24 metric audit reopened
Sprint `3.8`, Sprint `7.8`, and Sprint `8.11`; all three have reclosed. Sprint
`5.6` then reopened Sprint `8.12` for parity against the corrected backend (ii).
Sprint `6.7` has reclosed the `(iii)/(iv)` compact functional-core style
alignment, and Sprints `8.12` and `8.13` have reclosed Haskell parity and style
follow-up. Phase `4`
remains closed on its owned surface.

| Surface | Current Repo State | Intended End State |
|---------|--------------------|--------------------|
| Repository layout | `app/`, `src/MCTS/`, `src/MCTS/Generated/`, `cpp-legacy/`, `cpp-imperative/`, `cpp-functional/`, `rust/`, `bench/`, `test/`, `docker/`, root `compose.yaml`, `cabal.project`, `fourmolu.yaml`, `.hlint.yaml`, `.gitignore`, `.dockerignore`, `mcts.cabal`, generated-artefact targets `documents/cli/commands.md`, `share/man/man1/mcts.1`, and `share/completion/{bash,zsh,fish}/` | Same layout, with no generated validation data required under `test/` and no checked-in PGO/BOLT profile snapshots |
| Build artefacts | `mcts.cabal` declares the `mcts` binary, live Haskell test stanzas, and the doctrine-standard dependency envelope; host validation enters through `docker compose run --rm mcts mcts check-code` under the pinned toolchain. The foreign backend tree is live for `cpp-legacy/`, `cpp-imperative`, `cpp-functional`, and `rust`; Dockerfile invokes the C++ and Rust PGO/BOLT Plan/Apply build recipes during image construction, and those recipes fail closed on missing profile data, missing `.fdata`, failed BOLT output, or a crashing installed bolted library. PGO/BOLT training uses the bounded metric-suite profile suite owned by Sprints `8.10` and `8.11`, including terminal playout, search-iteration, legacy played-game rollout, and self-play workloads. | Container-image `mcts` binary produced by `docker/Dockerfile`, plus image-local shared libraries for `cpp-legacy`, optimized `cpp-imperative`, optimized `cpp-functional`, and `rust`; runtime validation consumes those artefacts without rebuilding them, and steelman shared libraries exist only after successful Dockerfile-time PGO/BOLT trained on an accepted profile suite |
| CLI surface | The complete command family is wired: `bench`, `verify`, `verify legacy-parity`, `inspect`, `test`, `lint`, `docs`, `commands`, `help`, `check-code`, `build`, and `play`. Generated command docs are checked against the renderer, tracked generated-file drift fails `mcts lint files`, generated path/section registries live under `src/MCTS/Generated/`, parser topology is rendered from `CommandSpec` with explicit leaf option parsers, and `mcts test all` routes recursive CLI calls through `cabal exec mcts -- ...`. | Same surface backed by real C++/Rust/Haskell engines: bench/play/inspect dispatch through selected foreign backends when their shared libraries are present and the relevant ABI path can represent the run, Q3 covers `(ii)..(v)`, Q6 covers all five, Dockerfile-invoked build recipes exist for `cpp-legacy`, `cpp-imperative`, `cpp-functional`, and `rust`, and `legacy-fixtures` remains explicit external audit-fixture generation |
| Test stanzas | Five live Cabal stanzas currently exist: `mcts-unit`, `mcts-integration`, `mcts-cross-backend`, `mcts-legacy-parity`, `mcts-haskell-style`; each stanza has its own `tasty` runner, `mcts-cross-backend` invokes real `mcts verify` subprocesses serially around the process-pinned dynamic-library and shared C++ RNG bridge path, and `docker compose run --rm mcts mcts test all` is the host validation gate under the pinned container toolchain. `mcts-unit` uses semantic/property/temp-dir checks instead of `tasty-golden`. | Keep all validation data generated in memory or temporary directories during the run, so clean-clone validation has no `test/golden/` prerequisite |
| Toolchain | `mcts.cabal` pins `tested-with: ghc ==9.14.1`; `cabal.project` pins `with-compiler: ghc-9.14.1` and mirrors the report-card constants as comments. The style-tool policy pins GHC `9.12.4` only for Fourmolu/HLint installation inside the container. | GHC `9.14.1`, Cabal `3.16.1.0`, style GHC `9.12.4` for `fourmolu-0.19.0.1` / `hlint-3.10`, GCC latest stable on `ubuntu:24.04`, Rust latest stable with pinned minor, LLVM pinned in the Dockerfile |
| Determinism contract | Live C++ and Rust foreign backends dispatch through real FFI engines under `bench`, `play`, `inspect divergence`, Q3 `verify` when shared libraries are present and the fixed search-horizon ABI can represent the run, and Q6 `verify legacy-parity`; the integration stanza's direct live-FFI smoke cases are Rust-specific, with C++ live coverage carried by Q3/Q6/report-card surfaces. Transcript codec, full v1 envelope, process-pinned envelope and C++ RNG dynamic handles, SHA-256 content addressing, cache root resolution, prefix lookup, binary `MEQ1` equity sidecars, layered envelope checks, `divergenceVsEqStream`, compact foreign recompute/read-visits evidence surfaces, canonical search-side 12-wall child caps across the current live cohort, decoded real-binary transcript determinism, and hard-fail `VerifyMismatch` rollout/self-play cohorts in `mcts-cross-backend` are implemented. Sprints `2.8` and `7.6` tighten version handling and sidecar/recompute labeling. | Enforced by live-FFI-capable cross-backend `mcts verify {rollouts,selfplay}` over `(ii)..(v)`, decoded same-backend transcript checks, Rust live FFI-envelope cases under `mcts-integration`, and Q6 legacy-envelope checks across all five |
| Performance parity | The 2026-05-26 Sprint `8.12` `docker compose run --rm mcts mcts test all` run recorded corrected-backend rows: Q1a ST 0.99×, Q1a MT8 0.91×, Q1b ST 1.02×, Q1b MT8 0.99×, Q2 ST 0.63×, Q2 MT8 0.68×, Q5 Haskell search-iteration scaling 6.91×, Q5 C++ (ii) search-iteration scaling 6.72×, Q5 Haskell self-play scaling 3.65×, Q5 C++ (ii) self-play scaling 3.90×, Q6 liveness PASS, zero live-cohort divergence, and `Verdict: Within tolerance`. The 2026-05-24 Sprint `8.11`, 2026-05-21 fallback-backed optimized-C++ run, and 2026-05-23 Sprint `8.10` played-game rows remain historical audit evidence against older artefact or metric shapes. | Haskell (v) within tolerance of optimized live C++ (ii) on Q1a terminal playout throughput, Q1b search-iteration throughput, and Q2 played-game self-play throughput, single-threaded and on 8 workers where applicable, without checked-in generated throughput anchors |

## Related Documents

- [README.md](README.md)
- [development_plan_standards.md](development_plan_standards.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
- [../documents/engineering/backend_style_contract.md](../documents/engineering/backend_style_contract.md)
- [../README.md](../README.md)
