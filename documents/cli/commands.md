# mcts command reference

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: ../engineering/cli_command_surface.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md
**Generated sections**: none

> **Purpose**: Generated reference list for the current `mcts` command registry.

## `mcts bench rollouts`

Run the legacy-named played-game benchmark across an explicit backend cohort. Provide a comma-separated --backend list plus --games and --seed; use bench terminal-playouts for raw terminal playout throughput.

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

Run full UCT self-play games for one or more backends. Provide --backend, --games, and --seed; --sims controls the per-move search budget and --workers controls multi-threaded dispatch.

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

Measure direct random playout throughput without building a search tree. Provide --backend, --count, and --seed; output reports playouts/s rather than games/s.

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

Measure direct UCT search-iteration throughput for the selected backend cohort. Provide --backend, --count, and --seed; output reports search-iters/s.

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

Run the Q3 rollout verifier over at least two non-legacy backends. Provide a comma-separated --backend list, --games, and --seed; verification uses the cpp RNG path and rejects cpp-legacy.

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

Run the Q3 self-play verifier over at least two non-legacy backends. Provide --backend, --games, and --seed; --sims controls per-move search and verification uses the cpp RNG path.

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

Check Q6 legacy-envelope rollout liveness across all five backend slots. Provide each backend identifier exactly once in --backend plus --games and --seed.

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

Check Q6 legacy-envelope self-play liveness across all five backend slots. Provide each backend identifier exactly once in --backend; --sims sets the small per-move search budget.

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

Open the interactive Brick TUI. Without --vs, --backend controls the side named by --side and the human plays the opposite side. With --vs, --backend controls --side, --vs controls the other side, and the operator spectates AI-vs-AI play from the terminal.

**Usage**: `mcts play [options]`

**Options**

| Option | Required | Default | Values | Description |
|--------|----------|---------|--------|-------------|
| `--format json|table|plain` | no | plain when stdout is not a TTY; table when stdout is a TTY | `json`, `table`, `plain` | Output format Global option parsed before command dispatch. |
| `--color auto|always|never` | no | auto | `auto`, `always`, `never` | Color mode Global option parsed before command dispatch. |
| `--no-color` | no | - | - | Alias for --color never |
| `--backend BACKEND` | yes | - | `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | AI backend that controls the side named by --side Omit --vs for human play; the human controls the opposite side. |
| `--side hero|villain` | yes | - | `hero`, `villain` | Side controlled by --backend; the human plays the opposite side unless --vs is set |
| `--vs BACKEND` | no | - | `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`, `haskell` | Second AI backend for spectator mode; controls the side opposite --side When --vs is set, the operator watches instead of entering human moves. |
| `--rng native|cpp` | no | native | `native`, `cpp` | RNG source |
| `--sims N|A:B` | no | 1000 | - | Simulation budget Syntax: N for fixed sims, A:B for ramped sims. |
| `--seed U64` | no | - | - | Master seed; omitted means fresh random |
| `--max-plies N` | no | 200 | - | Maximum plies per game |
| `--cache-dir DIR` | no | .mcts-cache | - | Transcript cache root |

**Notes**

- Accepted backend values are cpp-legacy, cpp-imperative, cpp-functional, rust, and haskell.
- For human-vs-AI play, omit --vs; the selected backend controls --side and the human controls the other side.
- For AI-vs-AI spectating, pass --vs BACKEND; press Space in the TUI to advance AI turns when prompted.
- Move notation: *(x,y) moves your pawn to a board cell with coordinates 0..8; H(x,y) places a horizontal wall with coordinates 0..7; V(x,y) places a vertical wall with coordinates 0..7.
- In-game commands: :hint asks the selected backend for a move; :undo rewinds one ply; :save writes a transcript under .mcts-cache; :quit or :q exits the TUI; Esc exits immediately.

**Examples**

- Human plays Hero; haskell controls Villain.

  ```bash
  mcts play --backend haskell --side villain --rng native --max-plies 200 --sims 1000
  ```

- Watch Haskell Hero vs Rust Villain in spectator mode.

  ```bash
  mcts play --backend haskell --side hero --vs rust --rng native --max-plies 200 --sims 1000
  ```

## `mcts inspect list`

List transcripts in the selected cache root with backend, seed, games, threading, sims, move count, mtime, and path metadata.

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

Resolve a transcript hash prefix and print its move history. Use --top to limit displayed candidate moves, --with-equity for originator equity evidence, and --envelope for v1 envelope fields.

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

Open the interactive replay TUI for a transcript hash prefix. Navigate forward and backward through recorded moves while viewing multi-backend equity overlays when sidecars or live recompute paths are available.

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

List transcript equity sidecar entries under the cache root, including backend/build slots and envelope neighbours.

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

Plan or delete stale equity sidecars. Use --dry-run to review the deletion plan first; --keep-current keeps the logical current backend/build slot.

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

Resolve one transcript and render a divergence matrix from cached sidecars plus any live foreign recompute rows available in the image.

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

Run the aggregate Plan/Apply validation gate over generated-doc checks, prebuilt Cabal test stanzas, live verification cohorts, and the report-card workload. Use --dry-run or --plan-file to inspect the plan.

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

Measure a focused Q1/Q2 parity anchor between two explicit backend identifiers. Use --dry-run or --plan-file to inspect the planned benchmark and verification steps.

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

Run one Dockerfile-prebuilt Cabal test-suite executable by stanza name. Accepted stanza values are listed in help and command JSON.

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

Check file hygiene, forbidden workflow paths, and tracked generated-file drift. Pass --write to apply supported rewrites for this lint surface.

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

Check generated documentation sections and tracked generated command artefacts for drift. Pass --write to regenerate before rechecking.

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

Run the Haskell style gate through the pinned container toolchain: Fourmolu, HLint, and the Cabal-format round trip. Pass --write for formatter-supported rewrites.

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

Run every lint gate in the supported order: file hygiene, generated docs, and Haskell style.

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

Compare every registered generated section and tracked generated path with the current renderer output. Fails with the drifted path, marker key, and regenerate remedy.

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

Regenerate marker-delimited docs and fully generated command artefacts from the typed registries. Use --dry-run or --plan-file to inspect the generation plan.

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

Print the command registry. Use --tree for a compact topology view or --json for the stable schema consumed by tools and generated docs.

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

Render focused parser help for a command path such as play or verify selfplay. Unknown targets report the nearest valid command-tree context.

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

Run the project code-quality gate that combines doctrine alignment, generated-doc checks, Haskell style, and forbidden-surface linting.

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

Plan or run the C++ legacy backend build recipe used by the Dockerfile. Use --dry-run or --plan-file to inspect subprocesses before execution.

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

Plan or run the C++ imperative steelman backend recipe, including the mandatory PGO/BOLT path. Use --dry-run or --plan-file to inspect subprocesses.

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

Plan or run the C++ functional-core backend recipe, including the shared C++ PGO/BOLT flow. Use --dry-run or --plan-file to inspect subprocesses.

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

Plan or run the Rust cdylib backend recipe, including the mandatory PGO/BOLT path. Use --dry-run or --plan-file to inspect subprocesses.

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

Generate optional external legacy audit fixtures under an explicit output directory. The output is not a normal validation input; use --dry-run or --plan-file to inspect the recipe.

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
