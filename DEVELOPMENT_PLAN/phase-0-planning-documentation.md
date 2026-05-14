# Phase 0: Planning and Documentation Topology

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
[development_plan_standards.md](development_plan_standards.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Define the plan-ownership baseline for the MCTS Haskell CLI so phase
> status, sequencing, doctrine-alignment, and documentation-topology work has one
> canonical home.

## Phase Status

🔄 **Active** — Sprint `0.1` (canonical plan suite bootstrap) is `Done`; Sprint `0.2`
(doctrine-driven scheduling audit) is `Planned`. The phase closes when Sprint `0.2`
lands and every in-scope doctrine identifier is bound to an owned deliverable in Phases
`1`–`8`.

## Phase Summary

This phase establishes the development plan as the canonical execution-ordered record for
the MCTS repository, the governed `documents/` doctrine suite, the root-file pointers
that name [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) as the authoritative CLI
doctrine, and the in-scope vs out-of-scope doctrine envelope inherited verbatim from the
project README. It owns the phase model, the top-level control documents, the cleanup
ledger that later phases populate, and the standards-rule-L doctrine-citation contract
that every doctrine-adoption sprint must follow.

The phase does not write Haskell, C++, or Rust source. Every implementation surface —
the CLI, the engine, the FFI bridge, the backends, the test stanzas, the report card —
is scheduled by this phase but executed by Phases `1`–`8`.

## Sprint 0.1: Canonical Plan Suite Bootstrap ✅

**Status**: Done
**Implementation**: `DEVELOPMENT_PLAN/README.md`,
`DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`DEVELOPMENT_PLAN/phase-0-planning-documentation.md`,
`DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md`,
`DEVELOPMENT_PLAN/phase-2-transcript-codec-and-determinism.md`,
`DEVELOPMENT_PLAN/phase-3-haskell-engine.md`,
`DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md`,
`DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md`,
`DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md`,
`DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md`,
`DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md`,
`documents/documentation_standards.md`,
`documents/engineering/README.md`,
`documents/engineering/cli_command_surface.md`,
`documents/engineering/code_quality.md`,
`documents/engineering/unit_testing_policy.md`,
`documents/engineering/haskell_code_guide.md`,
`documents/engineering/determinism_contract.md`,
`documents/engineering/transcript_format.md`,
`documents/engineering/backend_ffi_contract.md`,
`documents/engineering/compiler_runtime_tuning.md`,
`HASKELL_CLI_TOOL.md`, `README.md`, `AGENTS.md`, `CLAUDE.md`
**Docs to update**: every file listed above.

### Objective

Stand up the canonical plan suite, the governed `documents/` doctrine suite, and the
root-file doctrine pointers so every later phase can cite a single execution-ordered
plan, a single doctrine, and a single governed-documents home with no ambiguity about
where the source of truth lives.

### Deliverables

- The `DEVELOPMENT_PLAN/` directory exists with the 14 files named above. Every file
  carries the standard `**Status**` / `**Supersedes**` / `**Referenced by**` /
  `**Generated sections**` metadata block plus a `> **Purpose**:` line per the
  convention shared with
  `~/prodbox/DEVELOPMENT_PLAN/`, `~/mattandjames/DEVELOPMENT_PLAN/`, and
  `~/infernix/DEVELOPMENT_PLAN/`.
- The phase model is the nine-phase surface-oriented decomposition declared in
  [README.md → Phase Overview](README.md): Phase `0` documentation/planning, Phase `1`
  Haskell CLI surface, Phase `2` transcript codec / RNG / determinism contract, Phase
  `3` backend (v) Haskell engine, Phase `4` backend (i) C++ legacy port + FFI bridge,
  Phase `5` backend (ii) C++ imperative steelman, Phase `6` backends (iii) C++
  functional and (iv) Rust, Phase `7` cross-backend verify + report card, Phase `8`
  Haskell performance parity closure plus retirement protocol.
- [development_plan_standards.md](development_plan_standards.md) declares rules A–L,
  including the CLI Doctrine Alignment rule L that requires phase docs to cite
  [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) sections by name on
  doctrine-adoption deliverables.
- [00-overview.md](00-overview.md) inherits the project README's `Doctrine scope`
  in-scope and out-of-scope splits verbatim, plus the two recorded stack deviations
  (`brick` + `vty` for TUIs only; `dhall` unused because daemon configuration is
  out of scope).
- [system-components.md](system-components.md) lists the planned backends, transcript
  codec components, CLI doctrine components, test stanzas, toolchain pins, and state
  locations with owning sprint / status for each row.
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) is empty in both
  sections at write time, with the retirement-protocol reference table populated so
  Phase `8` can enqueue rows without schema churn.
- `documents/documentation_standards.md` carries the six doctrine-mandated Generated
  Sections elements per [../HASKELL_CLI_TOOL.md → Project-level documentation
  standards](../HASKELL_CLI_TOOL.md): marker convention with literal
  `<!-- mcts:<key>:start -->` / `<!-- mcts:<key>:end -->` examples per file type, an
  authoritative pointer to the `GeneratedSectionRule` registry, a "How to regenerate"
  instruction naming `mcts docs generate` literally, a per-file
  `**Generated sections**:` metadata field with lint contract, the five-step extension
  protocol, and the "fully generated, do-not-hand-edit" rule cross-referencing the
  `trackingGeneratedPaths` registry.
- `documents/engineering/` carries the eight scaffolded engineering docs named under
  Implementation above. The four doctrine-overlap docs (`cli_command_surface.md`,
  `code_quality.md`, `unit_testing_policy.md`, `haskell_code_guide.md`) defer to the
  doctrine sections they implement by name and retain only project-specific
  elaborations. The four project-specific docs (`determinism_contract.md`,
  `transcript_format.md`, `backend_ffi_contract.md`,
  `compiler_runtime_tuning.md`) own their content outright with no doctrine overlap.
- `HASKELL_CLI_TOOL.md` carries the standard `**Status**` / `**Supersedes**` /
  `**Referenced by**` metadata block plus a `> **Purpose**:` line. The doctrine body
  is verbatim authoritative; no other edits.
- `README.md` (project root) carries one added pointer line under the existing
  introduction linking to [README.md](README.md) and
  [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) as the authoritative plan and
  doctrine entrypoints. No other content changes.
- `AGENTS.md` and `CLAUDE.md` (project root) carry two appended pointer lines below
  the existing git-restriction block: one to
  [`DEVELOPMENT_PLAN/README.md`](README.md) and one to
  [`HASKELL_CLI_TOOL.md`](../HASKELL_CLI_TOOL.md). Existing content unchanged.

### Validation

1. Every `[..](path)` link inside `DEVELOPMENT_PLAN/`, `documents/`, and the four root
   files resolves to a file that exists on disk.
2. Every file under `DEVELOPMENT_PLAN/` opens with `**Status**:` / `**Supersedes**:` /
   `**Referenced by**:` / `**Generated sections**:` / `> **Purpose**:` lines per the
   convention.
3. The four-row Done/Active/Planned/Blocked status-vocabulary table is identical in
   `README.md`, `development_plan_standards.md`, and `00-overview.md`.
4. The Phase Overview table in `README.md` names exactly nine phases (0–8) with names
   matching the `phase-N-*.md` titles letter-for-letter.
5. The doctrine-scope subsection in `00-overview.md` covers every in-scope and
   out-of-scope item declared by the project README's `Doctrine scope` section, plus
   the two recorded stack deviations.
6. The Sprint Dependencies Mermaid flowchart in `README.md` renders without error in a
   standalone Mermaid renderer (e.g. `npx @mermaid-js/mermaid-cli@latest -i
   DEVELOPMENT_PLAN/README.md -o /tmp/r.svg`) per standards rule K.
7. `documents/documentation_standards.md` covers every one of the six doctrine-mandated
   Generated Sections elements; a diff against the doctrine's
   `Project-level documentation standards` subsection shows no missing item.
8. Each `documents/engineering/*` file that overlaps with the doctrine either cites a
   doctrine section by name or shrinks to a doctrine pointer.
9. Root `README.md`, `AGENTS.md`, and `CLAUDE.md` link to both
   `DEVELOPMENT_PLAN/README.md` and `HASKELL_CLI_TOOL.md`.
10. Mermaid render pass per standards rule K: `README.md`'s Sprint Dependencies
    flowchart is the only Mermaid block in `DEVELOPMENT_PLAN/` at Sprint `0.1`
    closure; it renders successfully.

### Remaining Work

None.

## Sprint 0.2: Doctrine-Driven Scheduling Audit 📋

**Status**: Planned
**Implementation**: `DEVELOPMENT_PLAN/phase-0-planning-documentation.md`,
`DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md`,
`DEVELOPMENT_PLAN/phase-2-transcript-codec-and-determinism.md`,
`DEVELOPMENT_PLAN/phase-3-haskell-engine.md`,
`DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md`,
`DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md`,
`DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md`,
`DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md`,
`DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md`,
`DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`,
`DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`
**Docs to update**: every file listed above.

### Objective

Confirm that every in-scope identifier from
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) is owned by an explicit sprint
deliverable in Phases `1`–`8`. Any unowned identifier is scheduled by extending an
existing sprint's `Deliverables` block (or, if no existing sprint is a natural home,
adding a new sprint). The audit's purpose is to ensure no in-scope doctrine prescription
gets silently adopted at code-write time without a plan-level binding, per standards
rule L.

### Deliverables

- A grep audit of [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) enumerates every
  prescriptive identifier from the in-scope sections. The expected identifier list
  (non-exhaustive) is:
  - **Toolchain pinning**: `GHC 9.14.1`, `Cabal 3.16.1.0`,
    `tested-with: ghc ==9.14.1`, `with-compiler: ghc-9.14.1`.
  - **Project Structure**: `app/Main.hs` thin, `src/MyTool/` (here `src/MCTS/`)
    library-first layout.
  - **Command Topology / CommandSpec**: `Command`, `CommandSpec`, `OptionSpec`,
    `Example`, `name`, `summary`, `description`, `children`, `options`, `examples`,
    `longName`, `shortName`, `metavar`, `required`.
  - **Progressive Introspection**: `mcts commands`, `--tree`, `--json`,
    `mcts help <subcommand>`.
  - **Generated Artifacts**: `GeneratedSectionRule`, `trackingGeneratedPaths`,
    `mcts docs check`, `mcts docs generate`, marker conventions
    `<!-- mcts:<key>:start -->` (Markdown), `// mcts:<key>:start` (Haskell), etc.;
    paired check/write commands; three-element error message contract on drift.
  - **Subprocesses as Typed Values**: `Subprocess`, `subprocessPath`,
    `subprocessArguments`, `subprocessEnvironment`, `subprocessWorkingDirectory`,
    `renderSubprocess`, `runStreaming`, `capture`; forbidden primitives `callProcess`,
    `readCreateProcess`, `System.Process`, `typed-process` smart constructors.
  - **Plan / Apply**: `Plan`, `build`, `apply`, `--dry-run`, `--plan-file <path>`.
  - **Prerequisites as Typed Effects**: `prerequisiteRegistry`, `nodeId`,
    `nodeDescription`, remedy hint, `AppError PrerequisiteUnmet`.
  - **Application Environment**: `ReaderT Env IO`, single `Env` record.
  - **Lint, Format, Code-Quality Stack**: `fourmolu.yaml`, the twelve settings
    (`indentation`, `column-limit`, `function-arrows`, `comma-style`,
    `import-export-style`, `indent-wheres`, `record-brace-space`,
    `newlines-between-decls`, `haddock-style`, `let-style`, `in-style`, `unicode`),
    `hlint`, `cabal format` temp-file round-trip byte-equality, `forbiddenPathRegistry`
    refusing `.github/workflows/`, `.husky/`, `.githooks/`, root `Makefile` /
    `justfile` / `Taskfile.yml`.
  - **Testing Doctrine and Test Organization**: per-tier stanza model,
    `type: exitcode-stdio-1.0`, `tasty`, `execParserPure`, property invariants
    `decode . encode == id`, `render is deterministic`, `parser roundtrips`, golden
    tests with sentinel placeholders for non-deterministic content.
  - **Output Rules**: `--format json|table|plain`, default `table` on TTY else
    `plain`, `--color auto|always|never`, `--no-color`.
  - **Error Handling**: single `AppError` ADT, `renderError :: AppError -> Text`,
    forbidden `print`, `exitFailure`, direct terminal formatting outside the output
    layer. The audit confirms the canonical 15-variant list is named in
    [system-components.md → CLI Doctrine Components](system-components.md),
    [phase-1-haskell-cli-surface.md → Sprint 1.9](phase-1-haskell-cli-surface.md),
    and the doctrine-scope Error Handling bullet in [00-overview.md](00-overview.md):
    `TranscriptNotFound`, `TranscriptAmbiguous`, `TranscriptFormatUnsupported`,
    `VerifyMismatch`, `VerifyCohortTooSmall`, `RecomputeMismatch`,
    `LegacyParityRolloutOverflow`,
    `ArchEnvelopeMismatch`, `EngineEnvelopeMismatch`, `PrerequisiteUnmet`,
    `SubprocessFailed`, `FFIFailure`, `DocsCheckDrift`, `UnknownCommand`,
    `InvalidMove`. `TranscriptFormatUnsupported`, `ArchEnvelopeMismatch`, and
    `EngineEnvelopeMismatch` are doctrine-required because the project README
    pins them; the others mirror the README's enumeration plus the three
    project-added surfaces.
  - **GADT-Indexed State Machines**: phantom-type indices, singleton witnesses, the
    forbidden runtime-status-enum-with-manual-validation pattern.
  - **Project-level documentation standards**: the six elements
    (marker convention; authoritative list/pointer of generated-region files;
    `mcts docs generate`; per-file `**Generated sections**:`; five-step extension
    protocol; fully-generated do-not-hand-edit rule).
- Every identifier above is found at least once across the phase docs as an owned
  deliverable. Identifiers without a current owner enqueue an extension to the closest
  natural sprint.
- A second project-README identifier audit (separate from the doctrine audit above)
  confirms every normative term in the project [../README.md](../README.md) has an
  owning sprint. The classes of identifier and the required hits in
  `DEVELOPMENT_PLAN/*.md` and `documents/engineering/*.md`:
  - **Transcript wire format**: `MCTR`, `c_param`, `flags u32`, `initial_sims`,
    `TranscriptFormatUnsupported`, `0xFF` (terminator), `game_id`, the
    `winner ∈ {0,1,2}` enum. A counter-grep for the prior (incorrect) field set —
    `MCTS magic`, `sim_budget_kind`, `ramped_per_move_sims`, `action_enum_version`
    — must produce **zero** hits.
  - **RNG FFI contract**: `cpp_rng_new`, `cpp_rng_next_u64`, `cpp_rng_split`,
    `cpp_rng_free` (all four functions present per README §6.10).
  - **Paired build targets**: `*-bench`, `*-instrumented` (or the project-specific
    `_bench` / `_instrumented` suffix), with at least one owning sprint per
    non-exempt backend (ii, iii, iv, v).
  - **Verify mismatch protocol**: `digest equality`, `first divergent record`.
  - **Replay equity contract**: `bit-identical`, `ULP`, `same-backend equity`,
    `cross-backend equity tolerance`.
  - **Byte-consumption and backprop traversal contracts**: `byte-consumption order`,
    `backprop traversal order`.
  - **Q1–Q7 mapping**: each of `Q1`, `Q2`, `Q3`, `Q4`, `Q5`, `Q6`, `Q7` appears in
    the `ReportCard` deliverable list (Sprint 7.3).
  - **Report-card pinned values**: each of `G_R`, `G_S`, `G_V`, `G_LP`, `S_BENCH`,
    `S_VERIFY`, `S_LP_SIMS`, `S_LP` appears in `cabal.project` (Sprint 1.1) and in
    `system-components.md`.
- An out-of-scope counter-grep confirms no sprint schedules adoption of any
  out-of-scope doctrine section. The following identifiers must produce **zero** hits
  in `DEVELOPMENT_PLAN/*.md` except inside an explicit "out of scope" or "informational
  only" sentence: `Long-Running Daemons`, `BootConfig`, `LiveConfig`, `Capability
  Class`, `ServiceError`, `RetryPolicy`, `Reconciler`, `Pulumi`, `Smart Constructors
  for Paired Resources`, `dhall`.
- The two recorded stack deviations remain accurate: `brick` + `vty` appear only in
  Sprint 7.4 (`mcts play` and `mcts inspect replay`) and the dependency audit; `dhall`
  appears only as an explicit out-of-scope note.
- `system-components.md` is reviewed against the audit findings; any newly identified
  CLI doctrine component is added as a row with owning sprint and status.
- `legacy-tracking-for-deletion.md` enqueues a `Pending Removal` row for any
  identified doctrine deviation that the current plan text claims to honor in scope
  but does not (this is expected to be empty at first audit because no implementation
  code exists yet — the row appears only if Sprint `0.2` finds a plan-text
  contradiction).
- `00-overview.md` and `README.md` retain the unchanged Phase `0` overview text;
  Sprint `0.2`'s outputs are documentation refinements to phase docs and
  `system-components.md`, not architectural pivots.

### Validation

1. Manual grep-audit replay against `DEVELOPMENT_PLAN/*.md` confirms every doctrine
   identifier named above appears at least once. The audit is recorded inside this
   sprint's body when it lands, including the literal `grep -E` command for each
   class of identifier and the file:line evidence.
2. Counter-grep confirms zero out-of-scope adoption-style hits per the list above.
3. Each new sprint block introduced by Sprint `0.2` (if any) follows the rule H sprint
   format (Status / Implementation / Docs to update / Objective / Deliverables /
   Validation / Remaining Work).
4. Each new deliverable cites the [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
   section it implements by section heading per standards rule L.
5. Mermaid render pass (standards rule K) is a no-op — Sprint `0.2` introduces no
   diagrams.
6. Plan-level lint pass: the manual `fourmolu --mode check` and `hlint` runs are
   no-ops (no Haskell code yet); the plan-level checks reduce to the
   cross-reference resolution, metadata-block consistency, and identifier-audit
   checks named above.

### Remaining Work

Not started. Sprint `0.2` runs once Sprint `0.1` (the plan suite bootstrap, this
document and its siblings) lands and the project moves into normal phase execution.

## Doctrine Sections Cited

Sprint `0.1` is structural rather than doctrine-adopting; it instantiates the plan
suite and the doctrine-citation contract but binds no specific doctrine section to a
code-level deliverable. Sprint `0.2` cites the doctrine globally — its purpose is to
audit every in-scope section. Phases `1`–`8` cite individual doctrine sections at the
deliverable level.

The Phase `0`-owned doctrine sections — the meta-rules under which later phases adopt
doctrine — are:

- [../HASKELL_CLI_TOOL.md → Project-level documentation
  standards](../HASKELL_CLI_TOOL.md) — instantiated by
  `documents/documentation_standards.md` (Sprint `0.1`).
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) header — instantiated by the
  `**Status**` / `**Supersedes**` / `**Referenced by**` block added to
  `HASKELL_CLI_TOOL.md` itself (Sprint `0.1`).
- Standards rule L of [development_plan_standards.md](development_plan_standards.md)
  is the project-internal CLI doctrine alignment contract that every later phase
  follows.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/documentation_standards.md` — add the six Generated Sections elements
  named by the doctrine's `Project-level documentation standards` subsection.
- `documents/engineering/README.md` — index of the eight scaffolded engineering docs
  named in this phase, with one-line purpose each.
- `documents/engineering/cli_command_surface.md` — defer to the doctrine's
  `Command Topology`, `CommandSpec`, and `Progressive Introspection` sections; retain
  only the MCTS-specific command matrix.
- `documents/engineering/code_quality.md` — defer to the doctrine's `Lint, Format, and
  Code-Quality Stack` and `Forbidden Surfaces` plus
  `Generated Artifacts → The generated-section registry` and the paired
  `mcts docs check` / `mcts docs generate` contract.
- `documents/engineering/unit_testing_policy.md` — defer to the doctrine's
  `Testing Doctrine`, `Test Categories`, and `Test Organization` for the tasty stanza
  model.
- `documents/engineering/haskell_code_guide.md` — defer to the doctrine for GADT state
  machines, smart constructors, `Subprocess` values, `Plan / Apply`, prerequisites,
  application environment, and error handling.
- `documents/engineering/determinism_contract.md` — project-specific: the RNG split,
  per-game `splitmix64(master_seed, game_index)` seed derivation, ply-cap draw rule,
  visit-count vs equity asymmetry, legacy parity envelope, the `VerifyBackend` /
  `LegacyParityBackend` GADT split.
- `documents/engineering/transcript_format.md` — project-specific: little-endian
  binary wire format, single-byte action enumeration, content addressing,
  hash-prefix lookup, header layout.
- `documents/engineering/backend_ffi_contract.md` — project-specific: C ABI shape,
  `--rng cpp` plumbing through the FFI, instrumented vs bench build targets, the
  `*-bench` / `*-instrumented` paired-target template-flag scheme.
- `documents/engineering/compiler_runtime_tuning.md` — project-specific: the
  per-backend tuning stacks from the project README, with doctrine pointers for the
  toolchain pin and the `Subprocess` boundary the build harness uses.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- Root guidance docs (`README.md`, `AGENTS.md`, `CLAUDE.md`) link to
  [README.md](README.md) and [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) as the
  authoritative plan and CLI doctrine entrypoints (Sprint `0.1`).
- The doctrine itself lists every governed-doc and plan-file consumer in its
  `**Referenced by**` line (Sprint `0.1`).

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
- [../documents/documentation_standards.md](../documents/documentation_standards.md)
