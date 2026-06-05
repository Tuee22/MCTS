# MCTS

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: AGENTS.md, CLAUDE.md, HASKELL_CLI_TOOL.md, DEVELOPMENT_PLAN/README.md, documents/documentation_standards.md, documents/engineering/README.md
**Generated sections**: none

> **Purpose**: High-level project introduction, supported workflow, and getting-started guide.

MCTS is a Monte Carlo Tree Search runtime for Corridors, a Quoridor-style board
game. One Haskell CLI coordinates several engine backends so the project can
measure search performance, verify rule/search compatibility, inspect recorded
games, and play interactively from the terminal.

The current research question is practical and measurable: how does the native
Haskell backend compare with a fully optimized C++ MCTS implementation when the
backends are kept inside the same documented correctness envelope? The live
answer belongs in the report card printed by `mcts test all` and in the
[development plan](DEVELOPMENT_PLAN/README.md), not in this README.

## What Is Here

- A Haskell `mcts` CLI for play, benchmarks, verification, transcript inspection,
  generated docs, linting, and tests.
- Five backend slots:

  | Backend | Identifier | Role |
  |---------|------------|------|
  | C++ legacy port | `cpp-legacy` | Compatibility baseline for the original legacy behavior. |
  | C++ imperative steelman | `cpp-imperative` | Optimized C++ performance target. |
  | C++ functional-core | `cpp-functional` | C++ value-state implementation shaped like the functional backends. |
  | Rust | `rust` | Cross-language systems baseline. |
  | Haskell | `haskell` | Native in-process target backend. |

- A transcript/cache layer under `.mcts-cache/` for replay, inspection, and
  saved interactive games.
- A documentation suite under [documents/](documents/) and an execution-ordered
  plan under [DEVELOPMENT_PLAN/](DEVELOPMENT_PLAN/).

## Getting Started

All project build, run, test, lint, documentation, benchmark, and backend work
goes through the host-installed `hostbootstrap` CLI:

```bash
hostbootstrap run <mcts-args>
```

Install `hostbootstrap` once on the host:

```bash
# macOS / Apple Silicon
brew install pipx
pipx ensurepath

# Ubuntu 24.04
sudo apt update
sudo apt install -y pipx
pipx ensurepath

pipx install "git+https://github.com/tuee22/hostbootstrap.git#egg=hostbootstrap"
hostbootstrap doctor
```

Then try the CLI:

```bash
hostbootstrap run commands --tree
hostbootstrap run help play
hostbootstrap run inspect --help
```

`hostbootstrap run` builds or refreshes the pinned container image as needed and
passes arguments to the image's tini-wrapped `mcts` ENTRYPOINT. Do not repeat
`mcts` after `hostbootstrap run`. Do not run project workflows directly with
host `cabal`, `cargo`, `cmake`, `make`, formatter binaries, repository shell
wrappers, or direct project `docker build` / `docker run` commands.

## Play, Spectate, And Inspect

The supported host command shape is `hostbootstrap run <mcts-args>`. Run
interactive commands from a real terminal so hostbootstrap can attach stdin and a
TTY:

```bash
hostbootstrap run play
hostbootstrap run inspect
```

`hostbootstrap run play` opens the Brick game UI. With no flags, Haskell controls
Villain and the human controls Hero; flags still accept explicit backend, side,
opponent backend, RNG, seed, ply cap, simulation budget, and cache root choices.
From a non-interactive invocation, `play` exits with an explicit guardrail instead
of silently generating a batch game.

`hostbootstrap run inspect` opens a selectable browser of cached games from a TTY.
Rows show descriptive names derived from game parameters and keep hash prefixes for
exact references. In non-TTY or JSON mode, no-argument `inspect` falls back to the
script-friendly cache list renderer. Opening a game uses the replay surface with
move-by-move navigation and backend equity overlays.

Valid backend identifiers remain `cpp-legacy`, `cpp-imperative`,
`cpp-functional`, `rust`, and `haskell`. Move notation remains:

| Input | Meaning | Coordinate range |
|-------|---------|------------------|
| `*(x,y)` | Move your pawn to a board cell | `0..8` for both coordinates |
| `H(x,y)` | Place a horizontal wall | `0..7` for both coordinates |
| `V(x,y)` | Place a vertical wall | `0..7` for both coordinates |

Every command surface is meant to be self-describing. Use
`hostbootstrap run help <command-path>` for focused usage text and
`hostbootstrap run commands --json` for machine-readable command paths,
options, defaults, accepted values, examples, and notes.

## Common Commands

```bash
# List the command tree
hostbootstrap run commands --tree

# Open focused help
hostbootstrap run help play

# Compare two backends on search-iteration throughput
hostbootstrap run bench search-iters --backend cpp-imperative,haskell --rng native --threading single --count 20000 --seed 42

# Run a small cross-backend self-play verification
hostbootstrap run verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 4 --seed 42 --max-plies 200 --sims 500

# Inspect saved transcripts
hostbootstrap run inspect list

# Run the aggregate validation/report-card gate
hostbootstrap run test all
```

The complete generated command reference is
[documents/cli/commands.md](documents/cli/commands.md). The command-surface
contract is [documents/engineering/cli_command_surface.md](documents/engineering/cli_command_surface.md).

## Benchmarks And Verification

Benchmark commands use `--rng native`; each backend follows its own deterministic
native RNG path. Verification commands use the documented verification envelope
and compare the fields appropriate to that gate.

The project distinguishes three performance units:

| Metric | Unit | Meaning |
|--------|------|---------|
| Terminal playout throughput | `playouts/s` | Random trajectory from a board to terminal or cap; no MCTS tree. |
| Search-iteration throughput | `search-iters/s` | One UCT select/expand/evaluate/rollout/backprop iteration. |
| Played-game throughput | `games/s` | Complete self-played games with a configured search budget per real move. |

For exact benchmark semantics, see
[benchmark_metrics.md](documents/engineering/benchmark_metrics.md). For
determinism, replay, and semantic parity details, see
[determinism_contract.md](documents/engineering/determinism_contract.md),
[transcript_format.md](documents/engineering/transcript_format.md), and
[semantic_parity_contract.md](documents/engineering/semantic_parity_contract.md).

## Validation

Use the smallest hostbootstrap gate that covers the change:

```bash
hostbootstrap run docs check
hostbootstrap run lint files
hostbootstrap run lint docs
hostbootstrap run test mcts-unit
hostbootstrap run check-code
```

When touching shared behavior, backend contracts, generated docs, or report-card
surfaces, close with:

```bash
hostbootstrap run test all
```

## Where To Go Next

- [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md) - phase order,
  sprint status, validation closure, and current evidence.
- [documents/engineering/README.md](documents/engineering/README.md) -
  engineering-document index.
- [documents/engineering/backend_ffi_contract.md](documents/engineering/backend_ffi_contract.md) -
  C ABI and backend loading contract.
- [documents/engineering/backend_style_contract.md](documents/engineering/backend_style_contract.md) -
  shared backend implementation style.
- [documents/engineering/compiler_runtime_tuning.md](documents/engineering/compiler_runtime_tuning.md) -
  compiler, runtime, and performance-measurement doctrine.
- [HASKELL_CLI_TOOL.md](HASKELL_CLI_TOOL.md) - general Haskell CLI doctrine
  adopted by this project.
- [documents/documentation_standards.md](documents/documentation_standards.md) -
  documentation topology and generated-section rules.
