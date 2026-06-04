# CLAUDE.md

## Git Restrictions for LLM Agents

The following git commands are **FORBIDDEN** for LLM agents:

- `git add`
- `git commit`
- `git push`

Only the human user is permitted to run these commands. Agents must never stage, commit, or push changes to the repository under any circumstances, even if explicitly asked. If staging, committing, or pushing appears necessary, stop and inform the human user so they can perform the action themselves.

This restriction applies to all variants and equivalents (e.g., `git commit -a`, `git push --force`, plumbing commands that achieve the same effect, scripts or aliases that wrap these commands, etc.).

## Build, Run, and Validation Environment

All supported project build, run, validation, formatting, linting, documentation-generation, test, benchmark, and backend-build work must enter through the host-installed `hostbootstrap` CLI (Phase 9 doctrine; see [`DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md`](DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md)):

```bash
hostbootstrap run mcts <command>   # Phase 1 reopen Sprint 1.15 canonical shape
```

`hostbootstrap run` is the canonical host-side entrypoint. It reads `hostbootstrap.dhall` at the repo root, idempotently builds the project image against the pinned base (`docker.io/tuee22/hostbootstrap:basecontainer-cpu-<arch>`), and dispatches `mcts <command>` inside a one-shot `docker run --rm` container. The base image owns GHC `9.12.4` (Phase 1 reopen Sprint `1.14`), Cabal `3.16.1.0`, LLVM `19` + BOLT, fourmolu, hlint, and the warm Cabal store; the project Dockerfile owns clang-19, Rust `1.95.0`, the pinned style-tool versions (Phase 1 reopen Sprint `1.16`), the MCTS source build, and the four foreign backend `.so` artifacts.

**Transitional note (Phase 9):** until Phase 9 Sprint `9.2` ships the new `hostbootstrap.dhall` + slim Dockerfile and deletes `compose.yaml`, the worktree still supports the prior entrypoint `docker compose run --rm mcts mcts <command>` for validation. The doctrine above is authoritative; `compose.yaml` is residue tracked in [`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`](DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

Install `hostbootstrap` once per host:

```bash
python -m pip install \
  "git+https://github.com/tuee22/hostbootstrap.git#egg=hostbootstrap"
hostbootstrap doctor
```

Do not run project commands directly on the host with ambient toolchains or host-installed binaries. In particular, do not use host `cabal run`, `cabal exec`, `cargo`, `cmake`, `make`, `fourmolu`, `hlint`, or similar commands as a fallback for project work. The `hostbootstrap` Python CLI itself is the one allowed host-installed orchestrator.

Repository shell-script wrappers are not supported. Do not add or run `.sh` scripts, `bootstrap/` helpers, or other host-side orchestration for project build, run, validation, formatting, linting, documentation-generation, test, benchmark, or backend-build work. If a workflow is needed, expose it as an `mcts` command and run it through `hostbootstrap run mcts <command>`.

Host-side file inspection and bookkeeping commands such as `rg`, `sed`, `git diff --check`, and `git status --short` are acceptable when they do not build, run, format, lint, generate, or validate the project. Direct `docker build` / `docker run` invocations against the project image are not supported; use `hostbootstrap run mcts <command>` or `hostbootstrap build` instead. Do not use `docker compose up` or `docker compose exec` for this repository's normal workflow.

## Plan and Doctrine

- [`README.md`](README.md) — authoritative project intent, backend roles, and operator-facing command overview.
- [`DEVELOPMENT_PLAN/README.md`](DEVELOPMENT_PLAN/README.md) — authoritative execution-ordered development plan.
- [`DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md`](DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md) — hostbootstrap orchestrator doctrine, `hostbootstrap.dhall` schema, `FROM ${BASE_IMAGE}` inheritance pattern.
- [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md) — authoritative CLI doctrine.
- [`documents/documentation_standards.md`](documents/documentation_standards.md) — authoritative documentation-topology rules (SSoT, bidirectional links, generated sections).
