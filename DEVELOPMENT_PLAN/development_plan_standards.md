# Development Plan Standards

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md),
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
[../documents/documentation_standards.md](../documents/documentation_standards.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Define the maintenance rules for the MCTS development plan so the repository
> keeps one coherent, execution-ordered plan and one explicit ledger of cleanup work
> across the bootstrap, five-backend buildout, and Haskell performance parity proof.

## Core Principles

### A. Continuous Clean-Room Narrative

The plan must read as one sequential buildout from an empty checkout to the intended
repository end state — one Haskell CLI driving five backends, bit-for-bit cross-backend
verification, and pure Haskell matching maximally-optimised C++ on both POC workloads.

- Every phase assumes the previous phase has already closed.
- The plan flows from documentation topology to CLI scaffolding to engine to FFI backends
  in retirement order, then cross-backend verification, then Haskell performance parity.
- A reader unfamiliar with the repository must be able to follow the plan top to bottom
  without reconstructing hidden dependencies from multiple documents.
- If a previously closed phase reopens because the repository end state expands later, the
  top-level docs must say exactly which earlier phase reopened, which later phases remain
  closed on their owned surfaces, and why the overall handoff is still incomplete.

### B. Detailed, Implementation-Oriented Content

The plan is intentionally specific. It should not collapse into vague milestones or project
management summaries.

- Include concrete deliverables, canonical commands, validation gates, and exact blocked
  prerequisites when they materially clarify closure.
- Examples do not need to be verbatim copies of implementation files, but they must not
  contradict the supported architecture or command surface.
- Host-runnable command examples must use the root Compose entrypoint
  `docker compose run --rm mcts mcts <command>`. Bare `mcts <command>` may be used only
  when naming the CLI surface rather than giving a host command to run. Do not
  document `.sh` scripts, `bootstrap/` helpers, or other host-side wrappers as
  supported project workflows.
- Backend identifiers are `cpp-legacy`, `cpp-imperative`, `cpp-functional`, `rust`,
  `haskell` on the CLI and the Roman numerals `(i)`, `(ii)`, `(iii)`, `(iv)`, `(v)` in
  prose.
- Deprecated aliases or legacy operator paths belong only in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### C. Honest Completion Tracking

Status must describe reality, not intent.

| Indicator | Meaning |
|-----------|---------|
| ✅ | Completed and validated |
| 🔄 | Active and partially complete |
| 📋 | Planned and waiting for execution to reach it |
| ⏸️ | Blocked by an unmet prerequisite |

- `Done` requires passing validation, aligned docs, and no remaining sprint-owned work.
- `Active` requires a `Remaining Work` section.
- `Blocked` requires a `Blocked by` line.
- `Planned` means the work is scheduled but not started; ordinary phase/sprint sequencing
  may still be ahead of it. Use `Blocked` only for an unmet prerequisite outside normal
  execution order or for a prior sprint that has failed to close when this one is reached.
- Status is always scoped to the sprint or phase-owned surface. A later phase may remain
  `Done` when an earlier phase reopens, but the reopened dependency must be called out
  explicitly in `README.md` and `00-overview.md`.

### D. Declarative Plan Language

Phase documents describe the intended architecture in present-tense declarative language.

- Say what the repository uses, owns, validates, and removes.
- Do not turn phase docs into migration diaries.
- Cleanup history and compatibility residue belong in the explicit legacy-removal ledger,
  not as the main narrative of a phase.
- Active sprint bodies describe the end state in present tense; only the
  `### Remaining Work` subsection uses future/incomplete language.

### E. One Canonical Phase Model

The development plan uses exactly this document structure:

```text
DEVELOPMENT_PLAN/
├── development_plan_standards.md
├── README.md
├── 00-overview.md
├── phase-0-planning-documentation.md
├── phase-1-haskell-cli-surface.md
├── phase-2-transcript-codec-and-determinism.md
├── phase-3-haskell-engine.md
├── phase-4-cpp-legacy-port-and-ffi-bridge.md
├── phase-5-cpp-imperative-steelman.md
├── phase-6-cpp-functional-and-rust.md
├── phase-7-cross-backend-verify-and-report-card.md
├── phase-8-haskell-performance-parity-closure.md
├── legacy-tracking-for-deletion.md
└── system-components.md
```

No phase may be skipped. No sprint may exist in two phases. CLI-surface ownership,
transcript-codec ownership, Haskell engine ownership, FFI-bridge ownership, per-backend
optimisation ownership, cross-backend verification ownership, and Haskell parity ownership
each live in one place only.

### F. System Component Inventory

[system-components.md](system-components.md) is the authoritative component inventory for:

- backends and their build artefacts
- CLI surfaces and runtime controls (subcommand families)
- transcript codec and cache locations
- verification surfaces and test stanzas
- toolchain prerequisites and pinned versions
- state locations (cache root, ignored/local artifact roots, generated documentation roots)

When a phase changes the supported architecture, update the inventory in the same change.

### F.1 No Generated Validation Data in Git

The repository must not require pre-existing transcripts, throughput anchors,
snapshot files, report-card schemas, renderer baselines, or other generated
validation data to run its normal test suite.

- Test stanzas synthesize transcripts, sidecars, report cards, and renderer examples in
  memory or under temporary directories during the test run.
- Runtime/operator caches live under ignored cache roots such as `.mcts-cache/`.
- Historical retired-backend evidence may be described in docs or stored as optional
  external/ignored artifacts, but it is not a clean-clone test prerequisite.
- Generated documentation artefacts are the exception owned by the generated-section and
  tracked-generated-path registries; they are deterministic source documentation, not
  validation fixtures.

### G. Phase Documentation Requirements

Every phase document must contain a `Documentation Requirements` section that lists which
governed documents need creation or update under
[../documents/documentation_standards.md](../documents/documentation_standards.md).

Use this format:

```markdown
## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/X.md` — [description]

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Add backlink from Z.md
```

Rules:

- Architecture, command-surface, determinism-contract, FFI-contract, and tuning-stack
  changes require engineering-document updates.
- The plan must not claim a sprint is done if the listed docs are stale.
- If the repository has no product-doc ownership for a phase, say `None.` explicitly.

### H. Sprint Status Format

Every sprint uses the same basic structure:

```markdown
## Sprint X.Y: Name [STATUS]

**Status**: Done | Active | Planned | Blocked
**Implementation**: `path/to/file` (required for Done, recommended otherwise)
**Blocked by**: sprint id(s) or external prerequisite (required for Blocked)
**Docs to update**: `file.md`, `other.md`

### Objective

### Deliverables

### Validation

### Remaining Work
```

Additional sections such as `Current Validation State`, `Current Blockers`, or
`Architecture` are encouraged when they clarify design or closure.

### I. Explicit Cleanup and Removal Ledger

[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) is mandatory and
comprehensive. It is the authoritative list of all known compatibility helpers, deprecated
paths, duplicate surfaces, and stale tooling residue that still need removal.

- If a deprecated or compatibility feature exists anywhere in the repository, it must
  appear in the ledger.
- Each ledger item must name its location, why it is slated for removal, and the sprint
  that owns the cleanup.
- The retirement protocol (i)→(ii)→(iii)→(v) named in
  [00-overview.md](00-overview.md) is itself a cleanup ledger: each retiring backend's
  build artefacts and CLI flag values move from `Pending Removal` to `Completed` when the
  surviving cohort's evidence is recorded without requiring generated validation data in
  the repository.
- When the cleanup lands, move the item from `Pending Removal` to `Completed`.
- Phase docs reference the owning sprint, not duplicate the full cleanup ledger.

### J. Documentation Harmony

The plan and governed documents must agree.

- [README.md](README.md), [00-overview.md](00-overview.md), every phase file, and
  [system-components.md](system-components.md) must use the same phase names, sprint
  statuses, and dependency model.
- Governed docs under `documents/engineering/` must match the current architecture
  described by the plan.
- Root guidance docs `README.md`, `AGENTS.md`, and `CLAUDE.md` must point to both
  [README.md](README.md) and [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md).

### K. Mermaid Rendering Contract

Mermaid diagrams in `DEVELOPMENT_PLAN/` must follow the repository-safe subset and
authoring rules defined in
[../documents/documentation_standards.md](../documents/documentation_standards.md).

If a change adds or edits a Mermaid block in this directory, closure requires:

1. Rendering every Mermaid block in `DEVELOPMENT_PLAN/` through a standalone renderer.
2. Failing the change on any render error.
3. Verifying the edited diagram in the repository's target Markdown viewer.
4. Running `docker compose run --rm mcts mcts check-code` after the documentation
   change. The lint stack must run inside the short-lived Compose container through the
   pinned Fourmolu / HLint binaries and `cabal format`.

This standards document describes Mermaid rules with prose, inline code, or `markdown`
examples only. Do not add live Mermaid blocks here.

### L. CLI Doctrine Alignment

[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md) is the authoritative CLI doctrine. Phase
documents and sprint blocks that schedule adoption work must cite the doctrine sections
they implement by name (for example, `CommandSpec`, `Plan / Apply`, `Subprocesses as Typed
Values`, `Prerequisites as Typed Effects`, `Application Environment`,
`Lint, Format, and Code-Quality Stack`, `Generated Artifacts → The generated-section
registry`, `Test Organization`, `Output Rules`, `Error Handling`, `Toolchain pinning`,
`Project Structure`).

- Governed engineering docs under `documents/engineering/` referenced from the doctrine's
  `Referenced by` line must defer to the doctrine for the patterns it owns and retain only
  project-specific elaborations such as backend identifiers, transcript wire-format
  details, the per-game RNG-seed derivation, retained-state roots, or named validation
  flows.
- The MCTS adoption envelope of the doctrine is bounded: the in-scope and out-of-scope
  splits live in [00-overview.md](00-overview.md) `Doctrine Scope`. No sprint may schedule
  adoption of an out-of-scope doctrine section. The two stack deviations — `brick` + `vty`
  for the `play` and `inspect replay` TUIs only, and `dhall` is unused because daemon
  configuration is itself out of scope — are recorded in the same place.
- When the doctrine prescribes a behavior that the implemented worktree does not yet
  honor and the section is in scope, the gap is scheduled through a sprint deliverable in
  the appropriate phase. Closing the gap silently without a sprint binding is forbidden.
- Doctrine-driven removals — superseded helpers, deprecated CLI flags, parallel workflow
  surfaces — flow through [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
  like any other cleanup.
- If a doctrine section changes, the same change updates every governed doc that
  references it.

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
- [../documents/documentation_standards.md](../documents/documentation_standards.md)

## Cross-Reference Conventions

- Links inside `DEVELOPMENT_PLAN/` use relative paths.
- Links to governed docs under `documents/` use repository-relative paths (`../documents/...`).
- Links to the doctrine use `../HASKELL_CLI_TOOL.md`.
- File renames require same-change link updates everywhere the file is referenced.

## Maintenance Guidelines

1. Update the global control documents first: `README.md`, `00-overview.md`, and
   `system-components.md`.
2. Update the affected phase document next.
3. Update the governed engineering docs listed in `Docs to update`.
4. Update [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) whenever
   cleanup scope changes.
5. Run `docker compose run --rm mcts mcts check-code` before closing the work. The
   pinned Fourmolu / HLint binaries and `cabal format` must run inside the short-lived
   Compose container. Host-level validation fallback is never a closure gate.
6. If the change touched Mermaid, render every Mermaid block in `DEVELOPMENT_PLAN/` and
   verify the edited diagram in the target viewer before closing the work.
