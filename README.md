# MCTS

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: AGENTS.md, CLAUDE.md, HASKELL_CLI_TOOL.md, DEVELOPMENT_PLAN/README.md, DEVELOPMENT_PLAN/00-overview.md, DEVELOPMENT_PLAN/system-components.md, DEVELOPMENT_PLAN/phase-0-planning-documentation.md, DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, DEVELOPMENT_PLAN/phase-2-transcript-codec-and-determinism.md, DEVELOPMENT_PLAN/phase-3-haskell-engine.md, DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md, DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md, DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md, DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md, DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md, documents/documentation_standards.md, documents/engineering/README.md, documents/engineering/backend_ffi_contract.md, documents/engineering/benchmark_metrics.md, documents/engineering/cli_command_surface.md, documents/engineering/code_quality.md, documents/engineering/compiler_runtime_tuning.md, documents/engineering/determinism_contract.md, documents/engineering/haskell_code_guide.md, documents/engineering/transcript_format.md, documents/engineering/unit_testing_policy.md
**Generated sections**: none

> **Purpose**: Operator-facing project intent, supported entrypoint, backend cohort summary, and links to the authoritative plan and engineering contracts.

MCTS is a high-performance Monte Carlo Tree Search runtime for the Corridors board game. The current proof of concept is rollout-evaluated MCTS: one Haskell CLI drives five backend implementations so the native Haskell engine can be measured against a maximally optimised C++ baseline while the cohort stays deterministic inside a documented envelope.

The long-term research direction is AlphaZero-style ANN evaluation, but this repository's current plan ends at a parity-proven rollout MCTS runtime. The execution-ordered plan is [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md).

## Supported Workflow

All build, run, validation, formatting, linting, documentation-generation, test, benchmark, and backend-build work enters through the root Compose service:

```bash
docker compose run --rm mcts mcts <command>
```

Do not use host `cabal`, `cargo`, `cmake`, `make`, `fourmolu`, `hlint`, repository shell wrappers, `docker compose up`, or `docker compose exec` as project workflows. The pinned container owns GHC, Cabal, LLVM/BOLT, Rust, style tools, and the foreign backend shared libraries.

## Backend Cohort

| # | Backend | Identifier | Role |
|---|---------|------------|------|
| (i) | C++ legacy port | `cpp-legacy` | Verbatim compatibility port of `MCTS_legacy`; Q6 legacy-envelope evidence only, not the performance ceiling. |
| (ii) | C++ imperative steelman | `cpp-imperative` | Maximally optimised C++ performance ceiling: PGO+BOLT, `mimalloc`, arena search, compact bitfield board, direct capped move generation. |
| (iii) | C++ functional-style | `cpp-functional` | Same algorithm and optimisation stance as (ii), used to isolate C++ style effects. |
| (iv) | Rust | `rust` | Cross-language systems baseline with the same FFI/search/recompute contract. |
| (v) | Haskell | `haskell` | Native in-process target backend; pure API surface with `ST`-arena internals. |

Backends (i)..(iv) are loaded through stable C ABIs from canonical shared libraries produced during the Dockerfile build. Backend (v) runs in-process. The authoritative backend and FFI details live in [backend_ffi_contract.md](documents/engineering/backend_ffi_contract.md) and [compiler_runtime_tuning.md](documents/engineering/compiler_runtime_tuning.md).

## Benchmark Metrics

The project uses three distinct performance units:

| Metric | Unit | Meaning |
|--------|------|---------|
| Terminal playout throughput | `playouts/s` | Random trajectory from a board to terminal/cap; no MCTS tree. |
| Search-iteration throughput | `search-iters/s` | One UCT iteration: select, expand/evaluate, rollout if needed, backprop. |
| Played-game throughput | `games/s` | Complete self-played game with a configured search budget at each real move. |

Current `mcts bench rollouts` is a legacy command name: it measures played-game
throughput with one search iteration per move, not terminal `playouts/s`.
Played-game benchmark output uses `games/s` only. The report-card metric refactor
is tracked in the development plan; the metric taxonomy and Q1-Q6 mapping live in
[benchmark_metrics.md](documents/engineering/benchmark_metrics.md).

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

`mcts build cpp-legacy`, `mcts build cpp-imperative`, `mcts build cpp-functional`, and `mcts build rust` are Dockerfile-owned build leaves. Runtime validation consumes the canonical artefacts already built into the image; refreshing them normally means rebuilding the Compose image:

```bash
docker compose run --rm --build mcts mcts test all
```

## Determinism

The project separates performance runs from logical-equivalence verification:

- `--rng native` is for benchmarks and play. Each backend uses its own deterministic native RNG path; cross-backend bit equality is not asserted.
- `--rng cpp` is for verification. The Q3 cohort `(ii)..(v)` consumes the shared C++ verification seed contract and compares canonical visit payloads.
- Backend `(i)` keeps legacy terminal/search semantics and is covered by the dedicated `verify legacy-parity` envelope instead of the Q3 equality cohort.

Transcripts are local operator cache files under `.mcts-cache/` by default. They are content-addressed per backend/game and carry an engine envelope so verify/replay can detect stale binary, compiler, FP, libm, CPU, and architecture drift. The authoritative contracts are:

- [determinism_contract.md](documents/engineering/determinism_contract.md)
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

- [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md) — phase order, sprint status, blockers, validation closure, and cleanup ownership.
- [DEVELOPMENT_PLAN/system-components.md](DEVELOPMENT_PLAN/system-components.md) — component inventory.
- [DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md) — compatibility and stale-surface cleanup ledger.
- [HASKELL_CLI_TOOL.md](HASKELL_CLI_TOOL.md) — CLI doctrine.
- [documents/documentation_standards.md](documents/documentation_standards.md) — documentation topology rules.
- [documents/engineering/benchmark_metrics.md](documents/engineering/benchmark_metrics.md) — terminal playout, search-iteration, and played-game metric semantics.
- [documents/engineering/README.md](documents/engineering/README.md) — engineering-document index.
