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

✅ **Done.** Sprints `9.1`, `9.2`, and `9.3` are **Done** as of
2026-06-04: the hostbootstrap doctrine has landed,
`hostbootstrap.dhall` exists at repo root, `docker/Dockerfile` inherits
`FROM ${BASE_IMAGE}`, `compose.yaml` is deleted, and the project builds
and runs through `hostbootstrap run <mcts-args>`. Sprint `9.3`
closed by proving the canonical post-migration `hostbootstrap run test all` gate
emits a non-pending report card and passes Q3/Q4/Q6/Q7 under the new image. Sprint
`9.4` reclosed on 2026-06-05 after moving `hostbootstrap.dhall` from host-named
entries to `targets`, using one `H.target H.Accel.Cpu` container target, adding the
scoped `.mcts-cache/` mount supported by container models, and consuming
hostbootstrap TTY/stdin support for interactive `play` and `inspect`. Phase 1
Sprints `1.14`, `1.15`, and `1.16` are reclosed; Phase 0 Sprint `0.5` is
reclosed. Phases `3`, `4`, `5`, `6`, and `8` remain closed on their owned
backend/performance surfaces.

## Doctrine Scope

**In scope (Phase 9):**

- `hostbootstrap` as a host-installed Python CLI providing host capability
  detection, prerequisite validation, base-image pull, project-image build, and
  one-shot `docker run --rm` dispatch. Installed once per
  host with `pipx`; on Apple Silicon this means `brew install pipx`,
  `pipx ensurepath`, and `pipx install
  "git+https://github.com/tuee22/hostbootstrap.git#egg=hostbootstrap"`.
  On Ubuntu 24.04 this means `sudo apt install -y pipx`, `pipx
  ensurepath`, and the same `pipx install …` command. Validated with
  `hostbootstrap doctor`.
- Sprint `9.4` target shape for `hostbootstrap.dhall`: typed project config carrying
  `targets = [ H.target H.Accel.Cpu container ]`, where `container` is
  `H.Model.Container` with `service = False`, `dockerfile =
  "docker/Dockerfile"`, and a scoped `.mcts-cache/` mount. The schema is injected
  by the CLI as `H`; no import line. Hostbootstrap selects this CPU target on
  Apple Silicon, Linux CPU, and Linux GPU hosts because CPU targets run on every
  supported host capability set. MCTS does not name specific host classes in the
  project config.
- `docker/Dockerfile` inherits `FROM ${BASE_IMAGE}` — the CLI passes the
  arch-specific tag
  `docker.io/tuee22/hostbootstrap:basecontainer-cpu-<arch>` — and adds
  only the project-specific layers: source copy, the seven Cabal exe
  builds, and the four `mcts build <backend>` invocations that produce
  the foreign backend `.so` artifacts.
- MCTS uses the same CPU container model on every host. Hostbootstrap derives the
  CPU base-image family from `H.Accel.Cpu`; the project does not request
  GPU-specific runtime behavior.

**Out of scope (owned by Phase 1 reopen sprints, or deferred):**

- The toolchain pin values (GHC `9.12.4` + Cabal `3.16.1.0`) — owned by
  [Sprint 1.14](phase-1-haskell-cli-surface.md#sprint-114-toolchain-pin-update-to-ghc-9124--cabal-3161).
- The canonical invocation shape (`hostbootstrap run <mcts-args>`) —
  owned by [Sprint 1.15](phase-1-haskell-cli-surface.md#sprint-115-canonical-command-shape--hostbootstrap-run-mcts-command).
- The lint stack architecture (formatter-tools GHC unified with project
  GHC) — owned by [Sprint 1.16](phase-1-haskell-cli-surface.md#sprint-116-lint-stack--formatter-tools-ghc-unified-with-project-ghc).
- Apple-silicon host-native execution (MCTS runs in Docker on every host).
- General bind-mounted workspaces and generated profile roots remain out
  of scope. Sprint `9.4` admits only the `hostbootstrap.dhall` container mount for
  the operator `.mcts-cache/` root so one-shot `play` and `inspect` commands share
  cached games.

## Documentation Requirements

| Document | Owned change (Sprint) |
|---|---|
| [`../CLAUDE.md`](../CLAUDE.md), [`../AGENTS.md`](../AGENTS.md) | New paragraph naming `hostbootstrap` as the host-installed orchestrator, the `pipx` install command, and `hostbootstrap doctor` for prerequisite validation (Sprint 9.1). The canonical command shape sentence in those files is owned by Sprint 1.15; the toolchain pin sentence is owned by Sprint 1.14; the lint stack sentence is owned by Sprint 1.16. |
| [`../HASKELL_CLI_TOOL.md`](../HASKELL_CLI_TOOL.md) | New paragraph naming `hostbootstrap` as the orchestrator and the base image as the toolchain source (Sprint 9.1). The pin block sweep is owned by Sprint 1.14. |
| [`../README.md`](../README.md) | New onboarding lines naming `pipx install hostbootstrap` and `hostbootstrap doctor` (Sprint 9.1). Sprint `9.4` updated the operator guidance for the refactored target-schema cache mount and TTY/stdin support. The operator command syntax sweep is owned by Sprint 1.15. |
| [`README.md`](README.md) | Phase 9 row in phase index; Phase 9 paragraph in closure-status block (Sprint 9.1). Sprint `9.4` updates the phase status and closure summary for the `targets` / `H.Accel.Cpu` config and scoped cache mount. |
| [`00-overview.md`](00-overview.md) | Phase 9 paragraph in Current Handoff Status section; Phase 9 bullet in Doctrine Scope; line 960 layout row update to name `hostbootstrap.dhall` (Sprint 9.1). Sprint `9.4` updates those surfaces for the refactored target schema and cache mount. The entrypoint-doctrine sweep is owned by Sprint 1.15; the pin sweep is owned by Sprint 1.14; the lint stack annotation is owned by Sprint 1.16. |
| [`system-components.md`](system-components.md) | Docker development environment row at line 301 fully rewritten to name `hostbootstrap.dhall`, the slim `docker/Dockerfile`, and the inherited base image (Sprint 9.1). Sprint `9.4` updates the row to name `targets`, `H.Accel.Cpu`, and the scoped `.mcts-cache/` mount. The toolchain-version sweep is owned by Sprint 1.14; the Rust pin annotation is owned by Sprint 9.1. |
| [`legacy-tracking-for-deletion.md`](legacy-tracking-for-deletion.md) | Completed rows for the heavy multi-language toolchain layers, deleted `compose.yaml`, source pin update, retired formatter-tools GHC install layer (Sprint 9.2 closure), and the operator host-entry config/cache gap (Sprint 9.4 closure). |
| [`../documents/engineering/cli_command_surface.md`](../documents/engineering/cli_command_surface.md), [`../documents/engineering/README.md`](../documents/engineering/README.md) | Sprint `9.4` records hostbootstrap TTY support and the refactored `hostbootstrap.dhall` target/mount adoption without duplicating Phase 9's config doctrine. |

## Sprint 9.1: hostbootstrap as host-side orchestrator ✅

**Status**: Done
**Implementation**: doctrine paragraphs added to `CLAUDE.md`, `AGENTS.md`, `HASKELL_CLI_TOOL.md`, `README.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`; new `phase-9-hostbootstrap-adoption.md` (this file); `hostbootstrap` installed on this host with `pipx`; root `hostbootstrap.dhall` landed with the then-current hostbootstrap container config, with the refactored `targets` schema tracked by Sprint `9.4`.
**Blocked by**: N/A
**Docs to update**: [../CLAUDE.md](../CLAUDE.md), [../AGENTS.md](../AGENTS.md), [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md), [../README.md](../README.md), [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Objective

Establish `hostbootstrap` as the host-installed orchestrator that
detects host capabilities, validates prerequisites, builds the project image
against the pinned base, and passes `<mcts-args>` to the image's
tini-wrapped `mcts` ENTRYPOINT inside a one-shot container. Declare the
typed `hostbootstrap.dhall` project config, the `FROM ${BASE_IMAGE}`
Dockerfile inheritance pattern, and the runtime ENTRYPOINT as the new
project architecture.

### Deliverables

- Doctrine paragraphs added to the named docs naming `hostbootstrap`,
  the install command, the `doctor` validation step, the
  `hostbootstrap.dhall` file location and shape, and the
  `FROM ${BASE_IMAGE}` Dockerfile pattern. The paragraphs name
  Phase 9 explicitly and cross-link to this file.
- This phase doc itself, declaring the doctrine scope, the sprint
  roster, and the documentation requirements.
- Completed ledger row in
  [`legacy-tracking-for-deletion.md`](legacy-tracking-for-deletion.md)
  for the heavy multi-language toolchain layers removed from the project
  `docker/Dockerfile` by the inheritance pattern.

### Validation

`hostbootstrap --help` exits 0. `hostbootstrap doctor` was attempted on
this Apple Silicon host; the updated local hostbootstrap correctly
reports FileVault as enabled, which is a host setup issue outside this
repository. Docker itself is reachable, and the canonical project
build/run gates below validated the repository work. The project
closure gate is `hostbootstrap run <mcts-args>`.

Bidirectional `Referenced by` audit passes: every governed doc this
sprint updates lists `phase-9-hostbootstrap-adoption.md` in its own
`Referenced by` metadata.

### Remaining Work

None.

## Sprint 9.2: Implementation — code-side migration ✅

**Status**: Done
**Implementation**: new `hostbootstrap.dhall` at repo root; rewritten `docker/Dockerfile` per the inheritance pattern; deletion of `compose.yaml`; removal of the `STYLE_GHC_VERSION` install layer; source pins updated to GHC `9.12.4`; Rust build recipe pins `CARGO_TARGET_DIR=target` so Dockerfile-time Rust artefacts land at the canonical `rust/target/release/libmcts_rust.so`.
**Blocked by**: N/A
**Docs to update**: closure note in this phase doc only; the operator-facing doctrine sweeps are owned by Sprints 9.1, 1.14, 1.15, 1.16 and ship before this sprint opens.

### Objective

Land the code-side migration consolidating all four former
Pending-Removal rows into a single coherent worktree shape:
`hostbootstrap.dhall` exists at repo root, `docker/Dockerfile`
inherits the hostbootstrap base image, `compose.yaml` is deleted, the
project Haskell pin tracks GHC `9.12.4`, and the separate
formatter-tools GHC install is collapsed into the project GHC.

### Deliverables

- `hostbootstrap.dhall` at repo root with the project container model; Sprint `9.4`
  owns adapting that file to the refactored hostbootstrap `targets` schema and
  adding the scoped `.mcts-cache/` mount.
- `docker/Dockerfile` rewritten per the Sprint 9.1 inheritance pattern:
  `FROM ${BASE_IMAGE}`; copies source; builds the seven Cabal exes
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

`hostbootstrap build` exits 0 and exports `mcts:apple-silicon-arm64`.
`hostbootstrap run test all` exits 0 with Q3/Q4/Q6/Q7 PASS,
`normalized_divergence_score = 0.0000`, all six Cabal test stanzas
pass, and the four foreign backend smokes succeed.

### Remaining Work

None.

## Sprint 9.3: Post-migration report-card closure ✅

**Status**: Done
**Implementation**: `hostbootstrap run test all` runs under the new pin and image, passes the apples-to-apples invariants, and renders the live report-card measurement without requiring checked-in arm64/amd64 throughput anchors.
**Blocked by**: N/A
**Docs to update**: this phase doc, [`README.md`](README.md), [`00-overview.md`](00-overview.md), [`legacy-tracking-for-deletion.md`](legacy-tracking-for-deletion.md), and [`development_plan_standards.md`](development_plan_standards.md). Sprint `8.18` and `8.19` historical measurement narratives remain verbatim because they are historical performance investigations, not Phase 9 closure prerequisites.

### Objective

Prove that the post-migration hostbootstrap workflow produces the same
closure signal as the former container workflow: the full lifecycle gate
builds against the new image, runs all live test stanzas, emits a
non-pending report card, and passes the Q3/Q4/Q6/Q7 invariants.

### Deliverables

- The phase plan records invariant/report-card closure, not hardcoded
  per-architecture throughput rates.
- `hostbootstrap run test all` remains the source of truth for
  live post-migration report-card numbers on whichever host runs the gate.
- Cross-architecture report-card reruns remain permitted performance
  analysis, but they are not a Phase 9 closure prerequisite.

### Validation

`hostbootstrap run test all` exits 0; all six Cabal test stanzas
pass; Q3/Q4/Q6/Q7 PASS; `normalized_divergence_score=0.0000`; and the
report-card verdict is a non-pending measurement label per the
[Performance Measurement Doctrine](../documents/engineering/compiler_runtime_tuning.md#performance-measurement-doctrine).

### Remaining Work

None.

## Sprint 9.4: Target Schema, TTY, and Persistent Operator Cache ✅

**Status**: Done
**Implementation**: `hostbootstrap.dhall` now uses `targets = [ H.target H.Accel.Cpu container ]`
with a scoped `.mcts-cache/` mount; `docker/Dockerfile` labels interactive command
paths; local `hostbootstrap` run behavior forwards stdin and allocates a TTY only
for labelled interactive command paths when the host invocation itself has a TTY.
No repository shell wrappers were added.
**Blocked by**: N/A
**Docs to update**: [../README.md](../README.md), [README.md](README.md),
[00-overview.md](00-overview.md), [system-components.md](system-components.md),
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md),
[../documents/engineering/cli_command_surface.md](../documents/engineering/cli_command_surface.md),
[../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md).

### Objective

Make `hostbootstrap.dhall` compatible with the refactored hostbootstrap schema and
make `hostbootstrap run play` and `hostbootstrap run inspect` usable as the
canonical host-side interactive operator commands while preserving the one-shot
container model and the `hostbootstrap run <mcts-args>` command shape.

### Deliverables

- `hostbootstrap.dhall` declares `targets`, not host-named entries: one
  `H.target H.Accel.Cpu` container target covers Apple Silicon, Linux CPU, and
  Linux GPU hosts because CPU capability is available on each supported host.
- The container target keeps `dockerfile = "docker/Dockerfile"` and
  `service = False`.
- The default `.mcts-cache/` root is persisted across one-shot hostbootstrap runs
  through the target's `mounts` list. The mount is limited to operator cache state;
  it is not a bind-mounted workspace or a profile/build artifact escape hatch.
- `hostbootstrap run` forwards interactive stdin and allocates a TTY when the
  selected `mcts` command is interactive, so Brick/Vty can open normally.
- Non-interactive commands keep their existing stdout/stderr behavior and do not
  receive unnecessary TTY allocation.
- `hostbootstrap run play` no longer reaches the accidental batch fallback when
  the operator requested the interactive game UI.
- `hostbootstrap run inspect` can see games saved by earlier `play` runs without
  requiring an explicit host path on every invocation.

### Validation

- `hostbootstrap run --no-pull commands --tree` exits 0 under the refactored
  `hostbootstrap.dhall` target schema and renders `inspect - Browse transcript
  cache`.
- `hostbootstrap run --no-pull play` from a non-TTY exits 1 with the explicit
  interactive-terminal guard instead of reaching the historical batch fallback.
- `hostbootstrap run --no-pull play --max-plies 2 --sims 1` from a real PTY opens
  the Brick game UI, renders the shared session status line, and exits cleanly on
  Esc.
- `hostbootstrap run --no-pull inspect` exits 0 without `--cache-dir` and reads the
  default mounted `.mcts-cache/` root.
- The Dockerfile-time `mcts check-code` gate exits 0 during the hostbootstrap image
  build, including `docs check PASS`, generated-file drift checks, Fourmolu, HLint,
  and file lint.

### Remaining Work

None.

## Closure status

| Sprint | Status | As of |
|---|---|---|
| `9.1` hostbootstrap as host-side orchestrator | ✅ Done | 2026-06-04 |
| `9.2` Implementation — code-side migration | ✅ Done | 2026-06-04 |
| `9.3` Post-migration report-card closure | ✅ Done | 2026-06-04 |
| `9.4` Target schema, TTY, and persistent operator cache | ✅ Done | 2026-06-05 |

Phase 9 is closed again through Sprint `9.4`. Phase 1 is closed through Sprint
`1.18`, Phase 2 is closed through Sprint `2.10`, Phase 7 is closed through Sprint
`7.12`, and Phase 0 is closed through Sprint `0.5`; Phases `3`, `4`, `5`, `6`,
and `8` remain closed on their owned backend/performance surfaces. See
[`README.md`](README.md) closure-status block for the canonical
cross-phase summary.
