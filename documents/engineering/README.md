# Engineering Documentation

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/00-overview.md, ../documentation_standards.md, ./benchmark_metrics.md
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

Current planning note: the 2026-06-05 operator UI audit reopened and reclosed
Phase `9` Sprint `9.4`, Phase `1` Sprint `1.18`, Phase `2` Sprint `2.10`, and
Phase `7` Sprint `7.12`. The closure covers hostbootstrap TTY support,
substrate-keyed `hostbootstrap.dhall` `NoCluster` adoption, no-argument `play` and
`inspect`, descriptive cached-game selection, shared live/replay session status,
recorded-position backend equity recomputation, and PTY smoke evidence. Backend
optimization, report-card, and Q3/Q4/Q6/Q7 parity surfaces remain closed on their
owned implementation claims.

The canonical CLI doctrine for this project lives at
[../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md). The overlap docs below
(`cli_command_surface.md`, `code_quality.md`, `unit_testing_policy.md`,
`haskell_code_guide.md`) defer to the doctrine for the patterns it owns and retain
only project-specific elaborations. The project-specific docs
(`determinism_contract.md`, `semantic_parity_contract.md`,
`transcript_format.md`, `backend_ffi_contract.md`, `backend_style_contract.md`,
`benchmark_metrics.md`, `compiler_runtime_tuning.md`)
own their content outright.

## Documents

| Document | Purpose |
|----------|---------|
| [cli_command_surface.md](./cli_command_surface.md) | Canonical `mcts` operator command matrix, self-describing CLI contract, and implemented play/inspect host workflow; defers to the doctrine on Command Topology, `CommandSpec`, and Progressive Introspection |
| [code_quality.md](./code_quality.md) | The `mcts check-code` gate and the lint stack; build/warning-clean compilation is Dockerfile-owned; defers to the doctrine on Lint, Format, Code-Quality Stack, Generated Artifacts, and Forbidden Surfaces |
| [unit_testing_policy.md](./unit_testing_policy.md) | The six current live Cabal test stanzas, including `mcts-semantic-parity` for Q7, the `mcts test all` Plan/Apply command, the report-card workload/output layout, the Dockerfile-built steelman artefact and prebuilt-test-executable prerequisite, and the no-generated-validation-data rule; defers to the doctrine on Test Organization |
| [haskell_code_guide.md](./haskell_code_guide.md) | How the project uses `Subprocess`, `Plan / Apply`, `prerequisiteRegistry`, `Env`, `AppError`, and GADT state machines; defers to the doctrine on each pattern |
| [benchmark_metrics.md](./benchmark_metrics.md) | Terminal playout, search-iteration, and played-game throughput semantics, including report-card term definitions, Q1-Q7 evidence mapping, raw backend metrics, current-artifact observed answers, the active Sprint `8.15` rebaseline shortfall, and the current `bench rollouts` legacy-name caveat |
| [determinism_contract.md](./determinism_contract.md) | RNG split, per-game `splitmix64(master_seed, game_index)` seed derivation, ply-cap draw rule, visit-count vs equity asymmetry, legacy parity envelope |
| [semantic_parity_contract.md](./semantic_parity_contract.md) | Q7 semantic parity for `(ii)..(v)`, including rule-state/replay/search-invariant checks, terminal rejection, and the normalized divergence-score contract |
| [transcript_format.md](./transcript_format.md) | Little-endian binary wire format, single-byte action enumeration, content addressing, git-style hash-prefix lookup |
| [backend_ffi_contract.md](./backend_ffi_contract.md) | C ABI shape across the live C-ABI backends, `unsafe`/`safe` import policy, `--rng cpp` plumbing, canonical FFI load names, and the one-bolted-library-per-backend runtime contract |
| [backend_style_contract.md](./backend_style_contract.md) | Functional-core style contract for backends (iii), (iv), and (v): compact value state, typed action transitions, deterministic legal-action order, permitted local mutation, and completed Rust hot-path alignment |
| [compiler_runtime_tuning.md](./compiler_runtime_tuning.md) | Per-backend tuning stack: legacy (i) exemption, (ii)/(iii) doctrine flag set, mandatory Dockerfile-time bounded PGO/BOLT success for steelman foreign backends, closed Sprint `5.7` backend `(ii)` kernel/profile target, (iv) Rust `[profile.release]` and hot-path refactor, (v) Haskell GHC/LLVM/RTS tuning (including Sprint `8.18` `unsafeRead`/`unsafeWrite` arena and Sprint `8.19` aarch64 mcpu resolution `measured but rejected`), comprehensive five-factor arm64 Performance Gap Anatomy, Haskell PGO asymmetry note |

## Quick Navigation

### CLI Surface

- [`mcts` Command Matrix](./cli_command_surface.md#command-matrix)
- [Self-Describing CLI Contract](./cli_command_surface.md#self-describing-cli-contract)
- [Command Topology](../../HASKELL_CLI_TOOL.md) — doctrine
- [Progressive Introspection](../../HASKELL_CLI_TOOL.md) — doctrine
- [`CommandSpec` Source of Truth](../../HASKELL_CLI_TOOL.md) — doctrine

### Determinism

- [Per-Game RNG Seed Derivation](./determinism_contract.md#per-game-seed-derivation)
- [`--rng native` vs `--rng cpp`](./determinism_contract.md#rng-source-split)
- [Ply-Cap Draw Rule](./determinism_contract.md#ply-cap-draw-rule)
- [Visit-Count vs Equity Asymmetry](./determinism_contract.md#visit-count-vs-equity)
- [Legacy Parity Envelope](./determinism_contract.md#legacy-parity-envelope)
- [Q7 Semantic Parity](./semantic_parity_contract.md#scope)
- [Normalized Divergence Score](./semantic_parity_contract.md#divergence-score)

### Transcript Format

- [Wire Format](./transcript_format.md#wire-format)
- [Single-Byte Action Enumeration](./transcript_format.md#action-enumeration)
- [Content Addressing](./transcript_format.md#content-addressing)
- [Hash-Prefix Lookup](./transcript_format.md#hash-prefix-lookup)

### FFI

- [C ABI Shape](./backend_ffi_contract.md#c-abi-shape)
- [`unsafe`/`safe` Import Policy](./backend_ffi_contract.md#unsafe-safe-policy)
- [`--rng cpp` Plumbing](./backend_ffi_contract.md#rng-cpp-plumbing)

### Backend Style

- [Functional-Core Rule](./backend_style_contract.md#functional-core-rule)
- [Backend (iii) C++ Target](./backend_style_contract.md#backend-iii-c-target)
- [Backend (iv) Rust Target](./backend_style_contract.md#backend-iv-rust-target)
- [Rust Hot-Path Refactor](./compiler_runtime_tuning.md#sprint-68-rust-hot-path-refactor-target)
- [Backend (v) Haskell Target](./backend_style_contract.md#backend-v-haskell-target)

### Tuning

- [Backend (ii)/(iii) Flag Set](./compiler_runtime_tuning.md#backend-ii-and-iii--c-imperative-and-functional-core)
- [Sprint 5.7 Backend (ii) Hot-Path Target](./compiler_runtime_tuning.md#backend-ii-and-iii--c-imperative-and-functional-core)
- [PGO/BOLT Training Workload Doctrine](./compiler_runtime_tuning.md#pgobolt-training-workload-doctrine)
- [Backend (iv) Rust `[profile.release]`](./compiler_runtime_tuning.md#rust-profile)
- [Backend (v) Haskell GHC/RTS](./compiler_runtime_tuning.md#haskell-tuning)
- [Sprint 8.18 Backend (v) Arena `unsafeRead`/`unsafeWrite`](./compiler_runtime_tuning.md#sprint-818-backend-v-arena-unsafereadunsafewrite)
- [Sprint 8.19 aarch64 mcpu resolution (measured but rejected)](./compiler_runtime_tuning.md#sprint-819-aarch64-mcpu-resolution)
- [arm64 Performance Gap Anatomy](./compiler_runtime_tuning.md#arm64-performance-gap-anatomy) — comprehensive five-factor explanation of the lingering arm64-specific gap and what is/isn't recoverable
- [One-Known-Asymmetry PGO Note](./compiler_runtime_tuning.md#pgo-asymmetry)

### Testing

- [Current Cabal Stanzas](./unit_testing_policy.md#test-stanzas)
- [Benchmark Metric Taxonomy](./benchmark_metrics.md#metric-taxonomy)
- [Q1-Q7 Mapping](./benchmark_metrics.md#q1-q7-mapping)
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
