# mcts command reference

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: ../engineering/cli_command_surface.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md
**Generated sections**: none

> **Purpose**: Generated reference list for the current `mcts` command registry.

- `mcts bench rollouts` - Random-rollout benchmark
- `mcts bench selfplay` - Self-play benchmark
- `mcts bench terminal-playouts` - Terminal playout throughput
- `mcts bench search-iters` - Search-iteration throughput
- `mcts verify rollouts` - Verify rollout visit counts
- `mcts verify selfplay` - Verify self-play visit counts
- `mcts verify legacy-parity rollouts` - Verify legacy-envelope rollout liveness
- `mcts verify legacy-parity selfplay` - Verify legacy-envelope self-play liveness
- `mcts play` - Play or spectate a game
- `mcts inspect list` - List cached transcripts
- `mcts inspect show` - Show one transcript
- `mcts inspect show --envelope` - Show one transcript envelope
- `mcts inspect replay` - Replay one transcript
- `mcts inspect cache list` - List sidecars
- `mcts inspect cache prune` - Prune stale sidecars
- `mcts inspect divergence` - Show divergence matrix
- `mcts test all` - Run full suite and report card
- `mcts test parity-anchor` - Measure backend parity anchor
- `mcts test <stanza>` - Run one cabal stanza
- `mcts lint files` - Lint files
- `mcts lint docs` - Lint docs
- `mcts lint haskell` - Lint Haskell
- `mcts lint all` - Run all linters
- `mcts docs check` - Check generated docs
- `mcts docs generate` - Generate docs
- `mcts commands` - Show command registry
- `mcts help <subcommand>` - Focused help
- `mcts check-code` - Run code-quality gate
- `mcts build cpp-legacy` - C++ legacy backend build recipe
- `mcts build cpp-imperative` - C++ imperative backend build recipe
- `mcts build cpp-functional` - C++ functional backend build recipe
- `mcts build rust` - Rust backend build recipe
- `mcts build legacy-fixtures` - Generate external legacy Q6 evidence
