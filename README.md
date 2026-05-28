# MCTS

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: AGENTS.md, CLAUDE.md, HASKELL_CLI_TOOL.md, DEVELOPMENT_PLAN/README.md, DEVELOPMENT_PLAN/00-overview.md, DEVELOPMENT_PLAN/system-components.md, DEVELOPMENT_PLAN/phase-0-planning-documentation.md, DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, DEVELOPMENT_PLAN/phase-2-transcript-codec-and-determinism.md, DEVELOPMENT_PLAN/phase-3-haskell-engine.md, DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md, DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md, DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md, DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md, DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md, documents/documentation_standards.md, documents/engineering/README.md, documents/engineering/backend_ffi_contract.md, documents/engineering/backend_style_contract.md, documents/engineering/benchmark_metrics.md, documents/engineering/cli_command_surface.md, documents/engineering/code_quality.md, documents/engineering/compiler_runtime_tuning.md, documents/engineering/determinism_contract.md, documents/engineering/haskell_code_guide.md, documents/engineering/transcript_format.md, documents/engineering/unit_testing_policy.md
**Generated sections**: none

> **Purpose**: Operator-facing project intent, supported entrypoint, backend cohort summary, and links to the authoritative plan and engineering contracts.

MCTS is a high-performance Monte Carlo Tree Search runtime for the Corridors board game. The current proof of concept is rollout-evaluated MCTS: one Haskell CLI drives five backend implementations so the native Haskell engine can be measured against a maximally optimised C++ baseline while the cohort stays deterministic inside a documented envelope. The hypothesis the cohort tests is whether pure Haskell — with no production GHC equivalent to GCC/Clang `-fprofile-use` — can match maximally-optimised C++ on Quoridor MCTS; the honest answer (whether yes or no) is the project deliverable, provided every steelman backend is fully optimised and the apples-to-apples invariants Q3/Q4/Q6/Q7 in [Performance Measurement Doctrine](documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine) hold.

The long-term research direction is AlphaZero-style ANN evaluation, but this repository's current plan ends at a recorded rollout-MCTS measurement under those conditions. The execution-ordered plan is [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md).

## Supported Workflow

All build, run, validation, formatting, linting, documentation-generation, test, benchmark, and backend-build work enters through the root Compose service:

```bash
docker compose run --rm mcts mcts <command>
```

Do not use host `cabal`, `cargo`, `cmake`, `make`, `fourmolu`, `hlint`, repository shell wrappers, `docker compose up`, or `docker compose exec` as project workflows. The pinned container owns GHC, Cabal, LLVM/BOLT, Rust, style tools, the prebuilt Cabal component cache, and the foreign backend shared libraries.

The Docker image build compiles the `mcts` executable with tests and benchmarks enabled, installs all Cabal test-suite executables, installs the `mcts-criterion` benchmark executable, and produces the four foreign backend shared libraries before the image is published. After the image is built, ordinary `mcts` runtime, lint, docs, test, verify, inspect, play, and benchmark commands should execute from image-local artefacts without compiling or linking on the fly. If a non-build command prints Cabal `Building...`, `Configuring...`, or `Linking...` output, treat the image as stale or incorrectly prewarmed and rebuild it with `--build`.

## Backend Cohort

| # | Backend | Identifier | Role |
|---|---------|------------|------|
| (i) | C++ legacy port | `cpp-legacy` | Verbatim compatibility port of `MCTS_legacy`; Q6 legacy-envelope evidence only, not the performance ceiling. |
| (ii) | C++ imperative steelman | `cpp-imperative` | Maximally optimised C++ performance ceiling. Sprint `5.7` closed the remaining hot-path steelman work: action-id successor generation, absolute side-to-move board state, action-only/SoA tree storage, reusable wall-block masks, internal trusted apply/cache paths, and representative PGO+BOLT training. |
| (iii) | C++ functional-core | `cpp-functional` | Functional-core C++23 steelman under the same optimisation stack as (ii), using compact value-state search, numeric actions, direct capped legal generation, and the shared style followed by (iv) and (v). |
| (iv) | Rust | `rust` | Cross-language systems baseline using a compatible functional-core value-state and FFI/search/recompute contract; Sprint `6.8` aligns its hot path with `(iii)`/`(v)` using bit-parallel path checks, stack action buffers, child-bound arena sizing, and board-local visit caching. |
| (v) | Haskell | `haskell` | Native in-process target backend; pure API surface, compact value board, direct slot-based path checks, and `ST`-arena internals. |

Backends (i)..(iv) are loaded through stable C ABIs from canonical shared libraries produced during the Dockerfile build. Backend (v) runs in-process. Rust now uses the same functional-core hot-path shape as `(iii)` and `(v)` while remaining a raw-performance context row rather than the Q1/Q2 verdict target. The authoritative backend, style, and FFI details live in [backend_style_contract.md](documents/engineering/backend_style_contract.md), [backend_ffi_contract.md](documents/engineering/backend_ffi_contract.md), and [compiler_runtime_tuning.md](documents/engineering/compiler_runtime_tuning.md). Sprint `5.7` kept the `(ii)` public ABI stable while replacing internal search-kernel and profile-training paths.

## Benchmark Metrics

The project uses three distinct performance units:

| Metric | Unit | Meaning |
|--------|------|---------|
| Terminal playout throughput | `playouts/s` | Random trajectory from a board to terminal/cap; no MCTS tree. |
| Search-iteration throughput | `search-iters/s` | One UCT iteration: select, expand/evaluate, rollout if needed, backprop. |
| Played-game throughput | `games/s` | Complete self-played game with a configured search budget at each real move. |

Current `mcts bench rollouts` is a legacy command name: it measures played-game
throughput with one search iteration per move, not terminal `playouts/s`.
Played-game benchmark output uses `games/s` only. The metric taxonomy and Q1-Q7 mapping live in
[benchmark_metrics.md](documents/engineering/benchmark_metrics.md).

The first post-reframe `docker compose run --rm --build mcts mcts test all`
under the [Performance Measurement Doctrine](documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine)
exits 0 with all four apples-to-apples invariants Q3/Q4/Q6/Q7 PASS, all six
Cabal stanzas PASS, zero live-cohort divergence, and the labelled measurement
`Verdict: Trails parity band by 52.3% (measurement recorded; see PGO
Asymmetry in compiler_runtime_tuning.md)`. Backend `(ii)`/Haskell ratios
against the fully steelmanned Sprint `5.7` `(ii)` target: Q1a `1.42x` ST /
`1.51x` MT8, Q1b `1.45x` ST / `1.52x` MT8, Q2 `1.35x` ST / `1.48x` MT8;
Q5 scaling Haskell search `6.91x` vs backend `(ii)` search `7.27x`, Haskell
self-play `3.28x` vs backend `(ii)` self-play `3.60x`.

Under the reframed doctrine, Q1, Q2, and Q5 are measurement questions and a
Haskell shortfall is recorded honestly with PGO-asymmetry attribution; closure
of `mcts test all` gates on the apples-to-apples invariants Q3, Q4, Q6, Q7
plus a non-pending measurement, not on the `HASKELL_PARITY_TOLERANCE = 0.05`
labelling cutoff. The canonical primitive sample is `N_PRIM=20_000`. The
earlier Sprint `8.14` `Within tolerance` reading against the Sprint `5.6`
`(ii)` artefact and the pre-reframe `Shortfall 0.2678` measurement against the
post-`5.7` `(ii)` target are historical evidence.

Phase 7 Sprint `7.11` adds Q7 semantic parity for `(ii)..(v)`: a
weaker-than-bit-equality gate for game-rule replay compatibility, search
invariants, terminal-board rejection, and a single normalized divergence score.
Q7 does not relax Q3, and it does not include backend `(i)`.

The text report card defines its terms before the evidence block, then renders
three aligned evidence tables in this order: raw backend performance metrics for
every backend slot, the question summary, and the `visit/move` divergence matrix.
The divergence headline reports a single normalized divergence score instead of
empirical threshold pairs. The report ends with an explicit question-answer
summary derived from the observed ratios, scaling values, divergence score, and
gate outcomes. JSON output includes the same raw metric fields under
`raw_performance_metrics` and the score under `normalized_divergence_score`.

## Command Surface

The full generated command reference is [documents/cli/commands.md](documents/cli/commands.md); the command contract is [cli_command_surface.md](documents/engineering/cli_command_surface.md).

Common operator commands:

```bash
docker compose run --rm mcts mcts commands --tree
docker compose run --rm mcts mcts bench rollouts --backend cpp-imperative,haskell --threading single --rng native --games 1000 --seed 42
docker compose run --rm mcts mcts bench selfplay --backend haskell --rng native --games 100 --seed 42 --sims 10000
docker compose run --rm mcts mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500
docker compose run --rm mcts mcts verify legacy-parity selfplay --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --games 2 --seed 42 --sims 4
docker compose run --rm mcts mcts play --backend haskell --side hero --rng native --max-plies 200
docker compose run --rm mcts mcts inspect list
docker compose run --rm mcts mcts check-code
```

`mcts build cpp-legacy`, `mcts build cpp-imperative`, `mcts build cpp-functional`, and `mcts build rust` are Dockerfile-owned build leaves. The Dockerfile also prebuilds and installs the Cabal test and benchmark executables so later validation runs consume image-local artefacts instead of compiling test stanzas on demand. Refreshing any build artefact normally means rebuilding the Compose image:

```bash
docker compose run --rm --build mcts mcts test all
```

## Determinism

The project separates performance runs from logical-equivalence verification:

- `--rng native` is for benchmarks and play. Each backend uses its own deterministic native RNG path; cross-backend bit equality is not asserted.
- `--rng cpp` is for verification. The Q3 cohort `(ii)..(v)` consumes the shared C++ verification seed contract and compares canonical visit payloads.
- Backend `(i)` keeps legacy terminal/search semantics and is covered by the dedicated `verify legacy-parity` envelope instead of the Q3 equality cohort.
- Q7 semantic parity is a separate `(ii)..(v)` gate for rule-state replay
  compatibility, search invariants, and terminal-board rejection when
  bit-for-bit play is not the right claim.

Transcripts are local operator cache files under `.mcts-cache/` by default. They are content-addressed per backend/game and carry an engine envelope so verify/replay can detect stale binary, compiler, FP, libm, CPU, and architecture drift. The authoritative contracts are:

- [determinism_contract.md](documents/engineering/determinism_contract.md)
- [semantic_parity_contract.md](documents/engineering/semantic_parity_contract.md)
- [transcript_format.md](documents/engineering/transcript_format.md)
- [unit_testing_policy.md](documents/engineering/unit_testing_policy.md)

## Validation

Use the smallest Compose gate that covers the change, then close with the aggregate gate when touching cross-cutting code or docs:

```bash
docker compose run --rm mcts mcts docs check
docker compose run --rm mcts mcts lint files
docker compose run --rm mcts mcts lint docs
docker compose run --rm mcts mcts test mcts-unit
docker compose run --rm mcts mcts check-code
docker compose run --rm --build mcts mcts test all
```

Normal tests do not depend on checked-in generated transcripts, throughput anchors, renderer snapshots, or report-card fixtures. Generated documentation files are the tracked exception and are governed by [documentation_standards.md](documents/documentation_standards.md).

## Authoritative Documents

This README is intentionally reference-only. Exact rules, ownership boundaries, and
evidence snapshots live in the authoritative documents below.

- [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md) — phase order, sprint status, blockers, validation closure, and cleanup ownership.
- [DEVELOPMENT_PLAN/system-components.md](DEVELOPMENT_PLAN/system-components.md) — component inventory.
- [DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md) — compatibility and stale-surface cleanup ledger.
- [HASKELL_CLI_TOOL.md](HASKELL_CLI_TOOL.md) — CLI doctrine.
- [documents/documentation_standards.md](documents/documentation_standards.md) — documentation topology rules.
- [documents/engineering/backend_style_contract.md](documents/engineering/backend_style_contract.md) — functional-core style contract for backends (iii), (iv), and (v).
- [documents/engineering/benchmark_metrics.md](documents/engineering/benchmark_metrics.md) — terminal playout, search-iteration, and played-game metric semantics.
- [documents/engineering/semantic_parity_contract.md](documents/engineering/semantic_parity_contract.md) — Q7 semantic parity and normalized divergence-score contract.
- [documents/engineering/README.md](documents/engineering/README.md) — engineering-document index.
