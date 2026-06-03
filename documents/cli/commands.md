# mcts command reference

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: ../engineering/cli_command_surface.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md
**Generated sections**: none

> **Purpose**: Generated reference list for the current `mcts` command registry.

## `mcts bench rollouts`

Legacy played-game benchmark

**Usage**: `mcts bench rollouts [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--backend BACKENDS` | yes | - | `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | Comma-separated backend list Syntax: comma-separated non-empty list. |
| `--rng native|cpp` | no | native | `native`, `cpp` | RNG source |
| `--threading single|multi` | no | multi | `single`, `multi` | Threading mode |
| `--workers N` | no | 8 | - | Worker count for --threading multi |
| `--games N` | yes | - | - | Number of games |
| `--seed U64` | yes | - | - | Master seed |
| `--max-plies N` | no | 200 | - | Maximum plies per game |
| `--sims N|A:B` | no | 10000 | - | Simulation budget Syntax: N for fixed sims, A:B for ramped sims. |
| `--cache-dir DIR` | no | .mcts-cache | - | Transcript cache root |

**Notes**

- The legacy-named rollouts benchmark measures played games with one search iteration per real move.

**Examples**

- Legacy played-game benchmark

  ```bash
  mcts bench rollouts --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --threading single --rng native --games 100000 --seed 42
  ```

## `mcts bench selfplay`

Self-play benchmark

**Usage**: `mcts bench selfplay [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--backend BACKENDS` | yes | - | `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | Comma-separated backend list Syntax: comma-separated non-empty list. |
| `--rng native|cpp` | no | native | `native`, `cpp` | RNG source |
| `--threading single|multi` | no | multi | `single`, `multi` | Threading mode |
| `--workers N` | no | 8 | - | Worker count for --threading multi |
| `--games N` | yes | - | - | Number of games |
| `--seed U64` | yes | - | - | Master seed |
| `--max-plies N` | no | 200 | - | Maximum plies per game |
| `--sims N|A:B` | no | 10000 | - | Simulation budget Syntax: N for fixed sims, A:B for ramped sims. |
| `--cache-dir DIR` | no | .mcts-cache | - | Transcript cache root |

**Examples**

- Self-play benchmark

  ```bash
  mcts bench selfplay --backend haskell --rng native --games 1000 --seed 42 --sims 10000
  ```

- Self-play benchmark

  ```bash
  mcts bench selfplay --backend haskell --rng native --workers 32 --games 1000 --seed 42 --sims 10000
  ```

## `mcts bench terminal-playouts`

Terminal playout throughput

**Usage**: `mcts bench terminal-playouts [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--backend BACKENDS` | yes | - | `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | Comma-separated backend list Syntax: comma-separated non-empty list. |
| `--rng native|cpp` | no | native | `native`, `cpp` | RNG source |
| `--threading single|multi` | no | multi | `single`, `multi` | Threading mode |
| `--workers N` | no | 8 | - | Worker count for --threading multi |
| `--count N` | no | 1000 | - | Number of primitive benchmark units |
| `--seed U64` | yes | - | - | Master seed |
| `--max-plies N` | no | 60 | - | Maximum plies for each primitive unit |

**Examples**

- Terminal playout throughput

  ```bash
  mcts bench terminal-playouts --backend haskell --rng native --count 1000 --seed 42
  ```

## `mcts bench search-iters`

Search-iteration throughput

**Usage**: `mcts bench search-iters [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--backend BACKENDS` | yes | - | `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | Comma-separated backend list Syntax: comma-separated non-empty list. |
| `--rng native|cpp` | no | native | `native`, `cpp` | RNG source |
| `--threading single|multi` | no | multi | `single`, `multi` | Threading mode |
| `--workers N` | no | 8 | - | Worker count for --threading multi |
| `--count N` | no | 1000 | - | Number of primitive benchmark units |
| `--seed U64` | yes | - | - | Master seed |
| `--max-plies N` | no | 60 | - | Maximum plies for each primitive unit |

**Examples**

- Search-iteration throughput

  ```bash
  mcts bench search-iters --backend haskell --rng native --count 1000 --seed 42
  ```

## `mcts verify rollouts`

Verify rollout visit counts

**Usage**: `mcts verify rollouts [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--allow-stale` | no | - | - | Downgrade backend-slot envelope mismatches to warnings |
| `--backend BACKENDS` | yes | - | `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | Comma-separated backend list Syntax: comma-separated non-empty list. Q3 excludes cpp-legacy; use mcts verify legacy-parity for all five backend slots. |
| `--rng native|cpp` | no | cpp | `native`, `cpp` | RNG source |
| `--threading single|multi` | no | single | `single`, `multi` | Threading mode |
| `--workers N` | no | 8 | - | Worker count for --threading multi |
| `--games N` | yes | - | - | Number of games |
| `--seed U64` | yes | - | - | Master seed |
| `--max-plies N` | no | 200 | - | Maximum plies per game |
| `--sims N|A:B` | no | 10000 | - | Simulation budget Syntax: N for fixed sims, A:B for ramped sims. |
| `--cache-dir DIR` | no | .mcts-cache | - | Transcript cache root |

**Examples**

- Verify rollout visit counts

  ```bash
  mcts verify rollouts --backend cpp-imperative,cpp-functional,rust,haskell --games 2 --seed 42
  ```

## `mcts verify selfplay`

Verify self-play visit counts

**Usage**: `mcts verify selfplay [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--allow-stale` | no | - | - | Downgrade backend-slot envelope mismatches to warnings |
| `--backend BACKENDS` | yes | - | `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | Comma-separated backend list Syntax: comma-separated non-empty list. Q3 excludes cpp-legacy; use mcts verify legacy-parity for all five backend slots. |
| `--rng native|cpp` | no | cpp | `native`, `cpp` | RNG source |
| `--threading single|multi` | no | single | `single`, `multi` | Threading mode |
| `--workers N` | no | 8 | - | Worker count for --threading multi |
| `--games N` | yes | - | - | Number of games |
| `--seed U64` | yes | - | - | Master seed |
| `--max-plies N` | no | 200 | - | Maximum plies per game |
| `--sims N|A:B` | no | 10000 | - | Simulation budget Syntax: N for fixed sims, A:B for ramped sims. |
| `--cache-dir DIR` | no | .mcts-cache | - | Transcript cache root |

**Examples**

- Verify self-play visit counts

  ```bash
  mcts verify selfplay --backend cpp-imperative,cpp-functional,rust,haskell --threading single --games 50 --seed 42 --max-plies 200 --sims 10000
  ```

## `mcts verify legacy-parity rollouts`

Verify legacy-envelope rollout liveness

**Usage**: `mcts verify legacy-parity rollouts [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--allow-stale` | no | - | - | Downgrade backend-slot envelope mismatches to warnings |
| `--backend BACKENDS` | yes | - | `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | Comma-separated backend list Syntax: comma-separated non-empty list. Legacy parity requires each of the five backend identifiers exactly once. |
| `--rng native|cpp` | no | cpp | `native`, `cpp` | RNG source |
| `--threading single|multi` | no | single | `single`, `multi` | Threading mode |
| `--workers N` | no | 8 | - | Worker count for --threading multi |
| `--games N` | yes | - | - | Number of games |
| `--seed U64` | yes | - | - | Master seed |
| `--max-plies N` | no | 200 | - | Maximum plies per game |
| `--sims N|A:B` | no | 10000 | - | Simulation budget Syntax: N for fixed sims, A:B for ramped sims. |
| `--cache-dir DIR` | no | .mcts-cache | - | Transcript cache root |

**Examples**

- Verify legacy-envelope rollout liveness

  ```bash
  mcts verify legacy-parity rollouts --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --games 2 --seed 42
  ```

## `mcts verify legacy-parity selfplay`

Verify legacy-envelope self-play liveness

**Usage**: `mcts verify legacy-parity selfplay [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--allow-stale` | no | - | - | Downgrade backend-slot envelope mismatches to warnings |
| `--backend BACKENDS` | yes | - | `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | Comma-separated backend list Syntax: comma-separated non-empty list. Legacy parity requires each of the five backend identifiers exactly once. |
| `--rng native|cpp` | no | cpp | `native`, `cpp` | RNG source |
| `--threading single|multi` | no | single | `single`, `multi` | Threading mode |
| `--workers N` | no | 8 | - | Worker count for --threading multi |
| `--games N` | yes | - | - | Number of games |
| `--seed U64` | yes | - | - | Master seed |
| `--max-plies N` | no | 200 | - | Maximum plies per game |
| `--sims N|A:B` | no | 10000 | - | Simulation budget Syntax: N for fixed sims, A:B for ramped sims. |
| `--cache-dir DIR` | no | .mcts-cache | - | Transcript cache root |

**Examples**

- Verify legacy-envelope self-play liveness

  ```bash
  mcts verify legacy-parity selfplay --backend cpp-legacy,cpp-imperative,cpp-functional,rust,haskell --games 2 --seed 42 --sims 4
  ```

## `mcts play`

Play or spectate a game

**Usage**: `mcts play [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--backend BACKEND` | yes | - | `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | Backend controlled by --side |
| `--side hero|villain` | yes | - | `hero`, `villain` | Side controlled by --backend |
| `--vs BACKEND` | no | - | `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | Opponent backend for AI-vs-AI spectator mode |
| `--rng native|cpp` | no | native | `native`, `cpp` | RNG source |
| `--sims N|A:B` | no | 1000 | - | Simulation budget Syntax: N for fixed sims, A:B for ramped sims. |
| `--seed U64` | no | - | - | Master seed; omitted means fresh random |
| `--max-plies N` | no | 200 | - | Maximum plies per game |
| `--cache-dir DIR` | no | .mcts-cache | - | Transcript cache root |

**Examples**

- Play or spectate a game

  ```bash
  mcts play --backend haskell --side hero --rng native --max-plies 200 --sims 10000
  ```

- Play or spectate a game

  ```bash
  mcts play --backend haskell --side villain --vs rust --rng native --max-plies 200 --sims 10000
  ```

## `mcts inspect list`

List cached transcripts

**Usage**: `mcts inspect list [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--cache-dir DIR` | no | .mcts-cache | - | Transcript cache root |

**Examples**

- List cached transcripts

  ```bash
  mcts inspect list
  ```

## `mcts inspect show`

Show one transcript

**Usage**: `mcts inspect show <HASH-PREFIX> [options]`

**Arguments**

| Name | Required | Values | Description |
|------|----------|--------|-------------|
| `HASH-PREFIX` | yes | - | Transcript hash prefix |

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--top N` | no | 10 | - | Rows per move to show |
| `--with-equity` | no | - | - | Recompute and render equity sidecar values |
| `--envelope` | no | - | - | Render transcript envelope |
| `--cache-dir DIR` | no | .mcts-cache | - | Transcript cache root |

**Examples**

- Show one transcript

  ```bash
  mcts inspect show 7a2f --top 10 --with-equity
  ```

## `mcts inspect replay`

Replay one transcript

**Usage**: `mcts inspect replay <HASH-PREFIX> [options]`

**Arguments**

| Name | Required | Values | Description |
|------|----------|--------|-------------|
| `HASH-PREFIX` | yes | - | Transcript hash prefix |

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--top N` | no | 10 | - | Rows per move to show |
| `--cache-states N` | no | 20 | - | Replay state cache size |
| `--cache-dir DIR` | no | .mcts-cache | - | Transcript cache root |

**Examples**

- Replay one transcript

  ```bash
  mcts inspect replay 7a2f --top 15
  ```

## `mcts inspect cache list`

List sidecars

**Usage**: `mcts inspect cache list [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--cache-dir DIR` | no | .mcts-cache | - | Transcript cache root |

**Examples**

- List sidecars

  ```bash
  mcts inspect cache list
  ```

## `mcts inspect cache prune`

Prune stale sidecars

**Usage**: `mcts inspect cache prune [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--keep-current` | no | - | - | Keep current backend/build sidecars |
| `--cache-dir DIR` | no | .mcts-cache | - | Transcript cache root |
| `--dry-run` | no | - | - | Render the plan without applying it |
| `--plan-file PATH` | no | - | - | Write the rendered plan to a file |

**Examples**

- Prune stale sidecars

  ```bash
  mcts inspect cache prune --keep-current --dry-run
  ```

## `mcts inspect divergence`

Show divergence matrix

**Usage**: `mcts inspect divergence <HASH-PREFIX> [options]`

**Arguments**

| Name | Required | Values | Description |
|------|----------|--------|-------------|
| `HASH-PREFIX` | yes | - | Transcript hash prefix |

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--cache-dir DIR` | no | .mcts-cache | - | Transcript cache root |

**Examples**

- Show divergence matrix

  ```bash
  mcts inspect divergence 7a2f
  ```

## `mcts test all`

Run full suite and report card

**Usage**: `mcts test all [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--dry-run` | no | - | - | Render the plan without applying it |
| `--plan-file PATH` | no | - | - | Write the rendered plan to a file |

**Examples**

- Run full suite and report card

  ```bash
  mcts test all --dry-run
  ```

## `mcts test parity-anchor`

Measure backend parity anchor

**Usage**: `mcts test parity-anchor <BASELINE> <CANDIDATE> [options]`

**Arguments**

| Name | Required | Values | Description |
|------|----------|--------|-------------|
| `BASELINE` | yes | `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | Baseline backend |
| `CANDIDATE` | yes | `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | Candidate backend |

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--dry-run` | no | - | - | Render the plan without applying it |
| `--plan-file PATH` | no | - | - | Write the rendered plan to a file |

**Examples**

- Measure backend parity anchor

  ```bash
  mcts test parity-anchor rust haskell --format json
  ```

## `mcts test <stanza>`

Run one prebuilt test stanza

**Usage**: `mcts test <stanza> <STANZA> [options]`

**Arguments**

| Name | Required | Values | Description |
|------|----------|--------|-------------|
| `STANZA` | yes | `mcts-haskell-style`, `mcts-unit`, `mcts-integration`, `mcts-cross-backend`, `mcts-legacy-parity`, `mcts-semantic-parity` | Prebuilt Cabal test-suite executable |

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |

**Examples**

- Run one prebuilt test stanza

  ```bash
  mcts test mcts-unit
  ```

## `mcts lint files`

Lint files

**Usage**: `mcts lint files [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--write` | no | - | - | Apply fixes where supported |

**Examples**

- Lint files

  ```bash
  mcts lint files
  ```

## `mcts lint docs`

Lint docs

**Usage**: `mcts lint docs [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--write` | no | - | - | Apply fixes where supported |

**Examples**

- Lint docs

  ```bash
  mcts lint docs
  ```

## `mcts lint haskell`

Lint Haskell

**Usage**: `mcts lint haskell [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--write` | no | - | - | Apply fixes where supported |

**Examples**

- Lint Haskell

  ```bash
  mcts lint haskell
  ```

## `mcts lint all`

Run all linters

**Usage**: `mcts lint all [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |

**Examples**

- Run all linters

  ```bash
  mcts lint all
  ```

## `mcts docs check`

Check generated docs

**Usage**: `mcts docs check [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |

**Examples**

- Check generated docs

  ```bash
  mcts docs check
  ```

## `mcts docs generate`

Generate docs

**Usage**: `mcts docs generate [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--dry-run` | no | - | - | Render the generated-docs plan without writing |
| `--plan-file PATH` | no | - | - | Write the generated-docs plan to a file |

**Examples**

- Generate docs

  ```bash
  mcts docs generate
  ```

## `mcts commands`

Show command registry

**Usage**: `mcts commands [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--tree` | no | - | - | Render command tree |
| `--json` | no | - | - | Render enriched command schema as JSON |

**Examples**

- Show command registry

  ```bash
  mcts commands --tree
  ```

## `mcts help`

Focused help

**Usage**: `mcts help [COMMAND...] [options]`

**Arguments**

| Name | Required | Values | Description |
|------|----------|--------|-------------|
| `COMMAND` | no | - | Command path such as play or verify selfplay |

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |

**Examples**

- Focused help

  ```bash
  mcts help bench selfplay
  ```

## `mcts check-code`

Run code-quality gate

**Usage**: `mcts check-code [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |

**Examples**

- Run code-quality gate

  ```bash
  mcts check-code
  ```

## `mcts build cpp-legacy`

C++ legacy backend build recipe

**Usage**: `mcts build cpp-legacy [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--dry-run` | no | - | - | Render the plan without applying it |
| `--plan-file PATH` | no | - | - | Write the rendered plan to a file |

**Examples**

- C++ legacy backend build recipe

  ```bash
  mcts build cpp-legacy --dry-run
  ```

## `mcts build cpp-imperative`

C++ imperative backend build recipe

**Usage**: `mcts build cpp-imperative [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--dry-run` | no | - | - | Render the plan without applying it |
| `--plan-file PATH` | no | - | - | Write the rendered plan to a file |

**Examples**

- C++ imperative backend build recipe

  ```bash
  mcts build cpp-imperative --dry-run
  ```

## `mcts build cpp-functional`

C++ functional backend build recipe

**Usage**: `mcts build cpp-functional [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--dry-run` | no | - | - | Render the plan without applying it |
| `--plan-file PATH` | no | - | - | Write the rendered plan to a file |

**Examples**

- C++ functional backend build recipe

  ```bash
  mcts build cpp-functional --dry-run
  ```

## `mcts build rust`

Rust backend build recipe

**Usage**: `mcts build rust [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--dry-run` | no | - | - | Render the plan without applying it |
| `--plan-file PATH` | no | - | - | Write the rendered plan to a file |

**Examples**

- Rust backend build recipe

  ```bash
  mcts build rust --dry-run
  ```

## `mcts build legacy-fixtures`

Generate external legacy audit fixtures

**Usage**: `mcts build legacy-fixtures [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--output-dir DIR` | yes | - | - | Required legacy audit output root; use an external or ignored artifact directory |
| `--seed U64` | no | 42 | - | Master seed |
| `--games N` | no | 10 | - | Games |
| `--sims N` | no | 10000 | - | Sims per move |
| `--dry-run` | no | - | - | Render the plan without applying it |
| `--plan-file PATH` | no | - | - | Write the rendered plan to a file |

**Examples**

- Generate external legacy audit fixtures

  ```bash
  mcts build legacy-fixtures --output-dir /tmp/mcts-legacy-fixtures --seed 42 --games 10 --sims 10000 --dry-run
  ```
