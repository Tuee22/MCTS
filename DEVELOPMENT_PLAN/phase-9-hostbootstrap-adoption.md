# Phase 9: hostbootstrap Adoption

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[00-overview.md](00-overview.md),
[system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md),
[phase-8-haskell-performance-parity-closure.md](phase-8-haskell-performance-parity-closure.md),
[../CLAUDE.md](../CLAUDE.md),
[../AGENTS.md](../AGENTS.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md),
[../README.md](../README.md),
[../documents/documentation_standards.md](../documents/documentation_standards.md),
[../documents/engineering/code_quality.md](../documents/engineering/code_quality.md),
[../documents/engineering/compiler_runtime_tuning.md](../documents/engineering/compiler_runtime_tuning.md),
[../documents/engineering/haskell_code_guide.md](../documents/engineering/haskell_code_guide.md),
[../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md)
**Generated sections**: none

> **Purpose**: Introduce `hostbootstrap` as the host-installed orchestrator
> for MCTS, declare the typed `hostbootstrap.dhall` project config, and
> establish the base-image inheritance pattern for `docker/Dockerfile`.
> Toolchain pin doctrine, canonical command shape doctrine, and lint stack
> architecture doctrine remain owned by Phase 1 (Sprints 1.14, 1.15, 1.16);
> Phase 9 introduces only the *new* surfaces that make Phase 1's reopen
> sprints possible.

## Phase Status

🔄 **Open.** Sprint `9.1` (hostbootstrap as host-side orchestrator) is
**Active** as of 2026-06-03 — the doctrine establishing the
host-installed `hostbootstrap` CLI, the `hostbootstrap.dhall` typed
project config, and the `FROM ${BASE_IMAGE}` Dockerfile inheritance
pattern has landed across the governed documentation. The worktree
still ships `compose.yaml`, the thick `docker/Dockerfile`, no
`hostbootstrap.dhall`, and no host install of the CLI. Sprint `9.2`
(implementation — code-side migration) and Sprint `9.3` (post-migration
evidence rebaseline) remain **Planned**. Phase 1 is reopened on three
narrow sub-surfaces via Sprints `1.14`, `1.15`, `1.16`. Phase 0 is
reopened on its planning-baseline sub-surface via Sprint `0.5`. Phases
2–8 remain closed on their owned surfaces. The overall MCTS handoff is
incomplete pending Sprint `9.2` and Sprint `9.3`.

## Doctrine Scope

**In scope (Phase 9):**

- `hostbootstrap` as a host-installed Python CLI providing substrate
  detection, prerequisite validation, base-image pull, project-image
  build, and one-shot `docker run --rm` dispatch. Installed once per
  host with
  `python -m pip install "git+https://github.com/tuee22/hostbootstrap.git#egg=hostbootstrap"`;
  validated with `hostbootstrap doctor`.
- `hostbootstrap.dhall` at repo root: typed project config carrying one
  `H.Substrate.LinuxCpu` substrate entry, `H.Model.Container` model,
  `service = False`, `dockerfile = "docker/Dockerfile"`. The schema is
  injected by the CLI as `H`; no import line.
- `docker/Dockerfile` inherits `FROM ${BASE_IMAGE}` — the CLI passes the
  arch-specific tag
  `docker.io/tuee22/hostbootstrap:basecontainer-cpu-<arch>` — and adds
  only the project-specific layers: `clang-19` and `libclang-rt-19-dev`
  via apt; pinned Rust `1.95.0` via `rustup toolchain install` over the
  base's `stable`; the `${BOLT_RT_INSTR_LIB}` →
  `/usr/local/lib/libbolt_rt_instr.a` symlink; pinned
  `fourmolu-0.19.0.1` and `hlint-3.10` at `/opt/mcts-style-tools/bin/`
  via `cabal install` against the base's GHC; source copy; the seven
  Cabal exe builds; and the four `mcts build <backend>` invocations
  that produce the foreign backend `.so` artifacts.
- Single substrate covers all platforms: MCTS runs under Docker on
  every host (Apple Silicon developers use Docker Desktop's
  `linux/arm64`). No `H.Substrate.AppleSilicon` entry is needed.

**Out of scope (owned by Phase 1 reopen sprints, or deferred):**

- The toolchain pin values (GHC `9.12.4` + Cabal `3.16.1.0`) — owned by
  [Sprint 1.14](phase-1-haskell-cli-surface.md#sprint-114-toolchain-pin-update-to-ghc-9124--cabal-3161).
- The canonical invocation shape (`hostbootstrap run mcts <command>`) —
  owned by [Sprint 1.15](phase-1-haskell-cli-surface.md#sprint-115-canonical-command-shape--hostbootstrap-run-mcts-command).
- The lint stack architecture (formatter-tools GHC unified with project
  GHC) — owned by [Sprint 1.16](phase-1-haskell-cli-surface.md#sprint-116-lint-stack--formatter-tools-ghc-unified-with-project-ghc).
- Apple-silicon host-native execution (MCTS runs in Docker on every
  substrate).
- Bind mounts for `transcripts/`, `.mcts-cache/`, `bench-profiles/` —
  the legacy `compose.yaml` mounted nothing; the v1 `hostbootstrap.dhall`
  preserves that behavior. A future revision may revisit.
- `mcts play` (TUI) under the new entrypoint —
  `hostbootstrap run` does not pass `-t`/`-i`; an upstream `hostbootstrap`
  change is needed before `mcts play` runs that way. Not blocking
  Phase 9 closure; `mcts test all` does not exercise `mcts play`.

## Documentation Requirements

| Document | Owned change (Sprint) |
|---|---|
| [`../CLAUDE.md`](../CLAUDE.md), [`../AGENTS.md`](../AGENTS.md) | New paragraph naming `hostbootstrap` as the host-installed orchestrator, the install command, and `hostbootstrap doctor` for prerequisite validation (Sprint 9.1). The canonical command shape sentence in those files is owned by Sprint 1.15; the toolchain pin sentence is owned by Sprint 1.14; the lint stack sentence is owned by Sprint 1.16. |
| [`../HASKELL_CLI_TOOL.md`](../HASKELL_CLI_TOOL.md) | New paragraph naming `hostbootstrap` as the orchestrator and the base image as the toolchain source (Sprint 9.1). The pin block sweep is owned by Sprint 1.14. |
| [`../README.md`](../README.md) | New onboarding lines naming `pip install hostbootstrap` and `hostbootstrap doctor` (Sprint 9.1). The operator command syntax sweep is owned by Sprint 1.15. |
| [`README.md`](README.md) | Phase 9 row in phase index; Phase 9 paragraph in closure-status block (Sprint 9.1). |
| [`00-overview.md`](00-overview.md) | Phase 9 paragraph in Current Handoff Status section; Phase 9 bullet in Doctrine Scope; line 960 layout row update to name `hostbootstrap.dhall` (Sprint 9.1). The entrypoint-doctrine sweep is owned by Sprint 1.15; the pin sweep is owned by Sprint 1.14; the lint stack annotation is owned by Sprint 1.16. |
| [`system-components.md`](system-components.md) | Docker development environment row at line 301 fully rewritten to name `hostbootstrap.dhall`, the slim `docker/Dockerfile`, and the inherited base image (Sprint 9.1). The toolchain-version sweep is owned by Sprint 1.14; the Rust pin annotation is owned by Sprint 9.1. |
| [`legacy-tracking-for-deletion.md`](legacy-tracking-for-deletion.md) | One Pending-Removal row for the heavy multi-language toolchain layers in the project `docker/Dockerfile` that become redundant under the inheritance pattern (Sprint 9.1). Other Pending-Removal rows are owned by Sprints 1.14, 1.15, 1.16. |

## Sprint 9.1: hostbootstrap as host-side orchestrator [🔄 Active]

**Status**: Active
**Implementation**: doctrine paragraphs added to `CLAUDE.md`, `AGENTS.md`, `HASKELL_CLI_TOOL.md`, `README.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`; new `phase-9-hostbootstrap-adoption.md` (this file). Host install of `hostbootstrap` and the new `hostbootstrap.dhall` + slim `docker/Dockerfile` are deferred to Sprint 9.2.
**Blocked by**: N/A
**Docs to update**: [../CLAUDE.md](../CLAUDE.md), [../AGENTS.md](../AGENTS.md), [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md), [../README.md](../README.md), [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Objective

Establish `hostbootstrap` as the host-installed orchestrator that
substrate-detects, validates prerequisites, builds the project image
against the pinned base, and dispatches `mcts <command>` inside a
one-shot container. Declare the typed `hostbootstrap.dhall` project
config and the `FROM ${BASE_IMAGE}` Dockerfile inheritance pattern as
the new project architecture.

### Deliverables

- Doctrine paragraphs added to the named docs naming `hostbootstrap`,
  the install command, the `doctor` validation step, the
  `hostbootstrap.dhall` file location and shape, and the
  `FROM ${BASE_IMAGE}` Dockerfile pattern. The paragraphs name
  Phase 9 explicitly and cross-link to this file.
- This phase doc itself, declaring the doctrine scope, the sprint
  roster, and the documentation requirements.
- One Pending-Removal row in
  [`legacy-tracking-for-deletion.md`](legacy-tracking-for-deletion.md)
  for the heavy multi-language toolchain layers in the current
  `docker/Dockerfile` (ghcup installer + GHC install, full `rustup`
  install-from-scratch, the LLVM 19 apt block, the LLVM symlink RUN
  block, the LANG/LC_ALL/PATH ENV block, the apt deps that the base
  already provides). These layers become redundant under the
  inheritance pattern.

### Validation

`docker compose run --rm mcts mcts docs check` exits 0;
`docker compose run --rm mcts mcts lint docs` exits 0;
`docker compose run --rm mcts mcts check-code` exits 0. The legacy
Compose entrypoint remains the validation gate during this sprint —
that is intended; during Sprint 9.2 the gate switches to
`hostbootstrap run mcts <command>`.

Bidirectional `Referenced by` audit passes: every governed doc this
sprint updates lists `phase-9-hostbootstrap-adoption.md` in its own
`Referenced by` metadata.

### Remaining Work

- Host install of `hostbootstrap` on developer hosts (not a repo edit;
  the onboarding lines in `README.md` document the install command).
- Creation of `hostbootstrap.dhall` at repo root (Sprint 9.2
  implementation).
- Rewrite of `docker/Dockerfile` to the inheritance pattern (Sprint 9.2
  implementation).

The Sprint 9.1 doctrine portion closes when the named doc edits land
and the validation gates pass. The implementation portion is the
Sprint 9.2 scope; this sprint stays `🔄 Active` until both portions
ship.

## Sprint 9.2: Implementation — code-side migration [📋 Planned]

**Status**: Planned
**Implementation**: new `hostbootstrap.dhall` at repo root; rewritten `docker/Dockerfile` per the inheritance pattern; deletion of `compose.yaml`; removal of `STYLE_GHC_VERSION` install layer; flip of `ARG GHC_VERSION` to `9.12.4`. Coordinated with Sprint 1.14 source edits (cabal manifests + Prerequisite registry + source defaults + unit-test literal).
**Blocked by**: 9.1, 1.14, 1.15, 1.16 — this sprint cannot ship until the doctrine landed by those sprints is stable in governed docs.
**Docs to update**: closure note in this phase doc only; the operator-facing doctrine sweeps are owned by Sprints 9.1, 1.14, 1.15, 1.16 and ship before this sprint opens.

### Objective

Land the code-side migration consolidating all four
Pending-Removal rows into a single coherent worktree shape:
`hostbootstrap.dhall` exists at repo root, `docker/Dockerfile`
inherits the hostbootstrap base image, `compose.yaml` is deleted, the
project Haskell pin tracks GHC `9.12.4`, and the separate
formatter-tools GHC install is collapsed into the project GHC.

### Deliverables

- `hostbootstrap.dhall` at repo root per Sprint 9.1 schema:
  ```dhall
  H.config
    { project = "mcts"
    , substrates =
      [ H.entry H.Substrate.LinuxCpu
          ( H.Model.Container
              H.Container::{
              , dockerfile = "docker/Dockerfile"
              , service = False
              }
          )
      ]
    }
  ```
- `docker/Dockerfile` rewritten per the Sprint 9.1 inheritance pattern:
  `FROM ${BASE_IMAGE}`; apt-installs `clang-19` + `libclang-rt-19-dev`;
  symlinks `${BOLT_RT_INSTR_LIB}` → `/usr/local/lib/libbolt_rt_instr.a`;
  pins Rust `1.95.0` via rustup over the base's `stable`; pins
  `fourmolu-0.19.0.1` + `hlint-3.10` at `/opt/mcts-style-tools/bin/`
  via `cabal install` against the base's GHC `9.12.4` and warm Cabal
  store; copies source; builds the seven Cabal exes
  (`mcts-haskell-style`, `mcts-unit`, `mcts-integration`,
  `mcts-cross-backend`, `mcts-legacy-parity`, `mcts-semantic-parity`,
  `mcts-criterion`, `mcts`) and installs them to `/usr/local/bin`;
  runs `mcts build cpp-legacy && … && mcts build rust` to produce the
  four foreign backend `.so` files.
- Source edits per Sprint 1.14 ship in the same change (`mcts.cabal`
  `tested-with`, `cabal.project` `with-compiler`, `Prerequisite.hs`
  registry id + remedy + seed list, `ReportCard.hs` default,
  `Engine/Envelope.hs` default, `test/unit/Main.hs` closure literal).
- `compose.yaml` deleted (Sprint 1.15 implementation deliverable).
- `STYLE_GHC_VERSION` ARG + the separate
  `ghcup install ghc ${STYLE_GHC_VERSION}` step removed from
  `docker/Dockerfile` (Sprint 1.16 implementation deliverable).

### Validation

`hostbootstrap run mcts test all` exits 0 with Q3/Q4/Q6/Q7 PASS,
`normalized_divergence_score = 0.0000`, all six Cabal test stanzas
pass, and the four foreign backend smokes succeed. Requires the host
to have `hostbootstrap` installed per Sprint 9.1.

### Remaining Work

Files not yet landed. This sprint is `📋 Planned` until the
follow-up implementation plan opens.

## Sprint 9.3: Post-migration evidence rebaseline [📋 Planned]

**Status**: Planned
**Implementation**: evidence block appended to this phase doc with results from `hostbootstrap run mcts test all` on amd64 and arm64 Docker substrates under the new pin and the new image.
**Blocked by**: 9.2.
**Docs to update**: this phase doc only. The Sprint `8.18` historical baseline in [`../README.md`](../README.md) and [`../documents/engineering/compiler_runtime_tuning.md`](../documents/engineering/compiler_runtime_tuning.md) stays verbatim — Sprint 9.3 records a *new* baseline as a sibling, not as a replacement.

### Objective

Record an honest post-migration baseline on both amd64 and arm64
Docker substrates under the new toolchain pin (GHC `9.12.4`) and the
new image (the hostbootstrap base + the slim project overlay), so
future evidence has a stable comparison anchor.

### Deliverables

Two evidence blocks (one per substrate), structured identically to the
Sprint `8.18` README block, tagged `GHC 9.12.4` and the
`docker.io/tuee22/hostbootstrap:basecontainer-cpu-<arch>@sha256:…`
digest. Each block records raw rates, Q1a/Q1b/Q2 ratios, Q5 scaling,
Q3/Q4/Q6/Q7 outcomes, `normalized_divergence_score`, and the verdict
line.

### Validation

`hostbootstrap run mcts test all` exits 0 on both substrates; the
verdict line is non-pending per the
[Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine).

### Remaining Work

Measurement not yet captured. This sprint is `📋 Planned` until
Sprint 9.2 ships.

## Closure status

| Sprint | Status | As of |
|---|---|---|
| `9.1` hostbootstrap as host-side orchestrator | 🔄 Active | 2026-06-03 |
| `9.2` Implementation — code-side migration | 📋 Planned | 2026-06-03 |
| `9.3` Post-migration evidence rebaseline | 📋 Planned | 2026-06-03 |

Phase 9 is **OPEN**. Phase 1 is reopened on three narrow sub-surfaces
via Sprints `1.14`, `1.15`, `1.16` (toolchain pin, canonical command
shape, lint stack architecture). Phase 0 is reopened on its
planning-baseline sub-surface via Sprint `0.5`. Phases 2–8 remain
closed on their owned surfaces. The overall MCTS handoff is incomplete
pending Sprint `9.2` (which consolidates the code-side implementation
of Sprints `1.14`, `1.15`, `1.16`, and `9.1`) and Sprint `9.3` (the
post-migration evidence rebaseline). See
[`README.md`](README.md) closure-status block for the canonical
cross-phase summary.
