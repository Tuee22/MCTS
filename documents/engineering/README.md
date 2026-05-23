# Engineering Documentation

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/00-overview.md, ../documentation_standards.md
**Generated sections**: none

> **Purpose**: Index of engineering and architecture documentation for the MCTS
> Haskell CLI and its five backends.

SSoT ownership, bidirectional links, and non-duplication rules are mandatory for all
new doctrinal content. See [../documentation_standards.md](../documentation_standards.md).

## Roadmap

Clean-room build order, sprint status, blockers, validation closure, and cleanup
ownership are tracked only in
[../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md).

The documents in this directory are stable doctrine and architecture references. When
the development plan changes the supported architecture, the affected doctrine docs
must be updated in the same change so they continue to describe the implemented
repository state.

The canonical CLI doctrine for this project lives at
[../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md). The four overlap docs below
(`cli_command_surface.md`, `code_quality.md`, `unit_testing_policy.md`,
`haskell_code_guide.md`) defer to the doctrine for the patterns it owns and retain
only project-specific elaborations. The four project-specific docs
(`determinism_contract.md`, `transcript_format.md`, `backend_ffi_contract.md`,
`compiler_runtime_tuning.md`) own their content outright.

## Documents

| Document | Purpose |
|----------|---------|
| [cli_command_surface.md](./cli_command_surface.md) | Canonical `mcts` operator command matrix; defers to the doctrine on Command Topology, `CommandSpec`, and Progressive Introspection |
| [code_quality.md](./code_quality.md) | The `mcts check-code` gate and the lint stack; defers to the doctrine on Lint, Format, Code-Quality Stack, Generated Artifacts, and Forbidden Surfaces |
| [unit_testing_policy.md](./unit_testing_policy.md) | The five live Cabal test stanzas (`mcts-unit`, `mcts-integration`, `mcts-cross-backend`, `mcts-legacy-parity`, `mcts-haskell-style`), the `mcts test all` Plan/Apply command, the report-card workload, and the no-generated-validation-data rule; defers to the doctrine on Test Organization |
| [haskell_code_guide.md](./haskell_code_guide.md) | How the project uses `Subprocess`, `Plan / Apply`, `prerequisiteRegistry`, `Env`, `AppError`, and GADT state machines; defers to the doctrine on each pattern |
| [determinism_contract.md](./determinism_contract.md) | RNG split, per-game `splitmix64(master_seed, game_index)` seed derivation, ply-cap draw rule, visit-count vs equity asymmetry, legacy parity envelope |
| [transcript_format.md](./transcript_format.md) | Little-endian binary wire format, single-byte action enumeration, content addressing, git-style hash-prefix lookup |
| [backend_ffi_contract.md](./backend_ffi_contract.md) | C ABI shape across the live C-ABI backends, `unsafe`/`safe` import policy, `--rng cpp` plumbing, and the foreign steelman `*-bench` vs `*-instrumented` build targets |
| [compiler_runtime_tuning.md](./compiler_runtime_tuning.md) | Per-backend tuning stack: legacy (i) exemption, (ii)/(iii) doctrine flag set, mandatory Dockerfile-time PGO+BOLT success for steelman foreign backends, (iv) Rust `[profile.release]`, (v) Haskell GHC/LLVM/RTS tuning, Haskell PGO asymmetry note |

## Quick Navigation

### CLI Surface

- [`mcts` Command Matrix](./cli_command_surface.md#command-matrix)
- [Command Topology](../../HASKELL_CLI_TOOL.md) — doctrine
- [Progressive Introspection](../../HASKELL_CLI_TOOL.md) — doctrine
- [`CommandSpec` Source of Truth](../../HASKELL_CLI_TOOL.md) — doctrine

### Determinism

- [Per-Game RNG Seed Derivation](./determinism_contract.md#per-game-seed-derivation)
- [`--rng native` vs `--rng cpp`](./determinism_contract.md#rng-source-split)
- [Ply-Cap Draw Rule](./determinism_contract.md#ply-cap-draw-rule)
- [Visit-Count vs Equity Asymmetry](./determinism_contract.md#visit-count-vs-equity)
- [Legacy Parity Envelope](./determinism_contract.md#legacy-parity-envelope)

### Transcript Format

- [Wire Format](./transcript_format.md#wire-format)
- [Single-Byte Action Enumeration](./transcript_format.md#action-enumeration)
- [Content Addressing](./transcript_format.md#content-addressing)
- [Hash-Prefix Lookup](./transcript_format.md#hash-prefix-lookup)

### FFI

- [C ABI Shape](./backend_ffi_contract.md#c-abi-shape)
- [`unsafe`/`safe` Import Policy](./backend_ffi_contract.md#unsafe-safe-policy)
- [`--rng cpp` Plumbing](./backend_ffi_contract.md#rng-cpp-plumbing)

### Tuning

- [Backend (ii)/(iii) Flag Set](./compiler_runtime_tuning.md#cpp-imperative-functional-flags)
- [Backend (iv) Rust `[profile.release]`](./compiler_runtime_tuning.md#rust-profile)
- [Backend (v) Haskell GHC/RTS](./compiler_runtime_tuning.md#haskell-tuning)
- [One-Known-Asymmetry PGO Note](./compiler_runtime_tuning.md#pgo-asymmetry)

### Testing

- [Five Live Cabal Stanzas](./unit_testing_policy.md#test-stanzas)
- [Test Organization](../../HASKELL_CLI_TOOL.md) — doctrine
- [Repository Data Doctrine](./unit_testing_policy.md#repository-data-doctrine)
- [Property Invariants](./unit_testing_policy.md#property-invariants)
- [Generated Validation Data](./unit_testing_policy.md#generated-validation-data)
- [POC Report Card](./unit_testing_policy.md#report-card)

### Code Quality

- [`mcts check-code`](./code_quality.md#check-code)
- [`mcts lint *`](./code_quality.md#lint-stack)
- [`mcts docs check / generate`](./code_quality.md#docs)
- [`forbiddenPathRegistry`](./code_quality.md#forbidden-paths)

### Haskell Patterns

- [`Subprocess` ADT](./haskell_code_guide.md#subprocess)
- [`Plan / Apply`](./haskell_code_guide.md#plan-apply)
- [`prerequisiteRegistry`](./haskell_code_guide.md#prerequisites)
- [`ReaderT Env IO`](./haskell_code_guide.md#env)
- [`AppError` and `renderError`](./haskell_code_guide.md#errors)
- [GADT-Indexed State Machines](./haskell_code_guide.md#gadt-state-machines)

## Cross-References

- [Development Plan](../../DEVELOPMENT_PLAN/README.md)
- [Documentation Standards](../documentation_standards.md)
- [HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) — canonical CLI doctrine
- [CLAUDE.md](../../CLAUDE.md) — agent guardrails
- [AGENTS.md](../../AGENTS.md) — agent guardrails
- [README.md](../../README.md) — project intent and command surface
