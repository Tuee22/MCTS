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
hostbootstrap run <mcts-args>   # canonical shape; Dockerfile ENTRYPOINT supplies mcts
```

`hostbootstrap run` is the canonical host-side entrypoint. It reads `hostbootstrap.dhall` at the repo root, selects the substrate-keyed `NoCluster` container model, idempotently builds the project image against the hostbootstrap base for that substrate, and passes `<mcts-args>` to the image's tini-wrapped `mcts` ENTRYPOINT inside a one-shot `docker run --rm` container. The base image owns GHC `9.12.4` (Phase 1 reopen Sprint `1.14`), Cabal `3.16.1.0`, LLVM `19` + BOLT, clang-19, Rust `1.95.0`, fourmolu `0.19.0.1`, hlint `3.10`, and the warm Cabal store; the project Dockerfile owns the MCTS source build, the `ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/mcts"]`, and the four foreign backend `.so` artifacts. MCTS has no project cluster lifecycle; `hostbootstrap cluster up/down/delete` is intentionally unsupported here.

Install `hostbootstrap` once per host:

```bash
# Apple Silicon / macOS
brew install pipx
pipx ensurepath

# Ubuntu 24.04
sudo apt update
sudo apt install -y pipx
pipx ensurepath

pipx install "git+https://github.com/tuee22/hostbootstrap.git#egg=hostbootstrap"
hostbootstrap doctor
```

Use `pipx` for `hostbootstrap`; do not install it with direct `pip`, and do not install it inside any project virtualenv. For local development changes on this machine, reinstall the checkout with `pipx install --force /Users/matthewnowak/hostbootstrap`.

Do not run project commands directly on the host with ambient toolchains or host-installed binaries. In particular, do not use host `cabal run`, `cabal exec`, `cargo`, `cmake`, `make`, `fourmolu`, `hlint`, or similar commands as a fallback for project work. The `hostbootstrap` Python CLI itself is the one allowed host-installed orchestrator.

Repository shell-script wrappers are not supported. Do not add or run `.sh` scripts, `bootstrap/` helpers, or other host-side orchestration for project build, run, validation, formatting, linting, documentation-generation, test, benchmark, or backend-build work. If a workflow is needed, expose it as an `mcts` command and run it through `hostbootstrap run <mcts-args>`.

Host-side file inspection and bookkeeping commands such as `rg`, `sed`, `git diff --check`, and `git status --short` are acceptable when they do not build, run, format, lint, generate, or validate the project. Direct `docker build` / `docker run` invocations against the project image are not supported; use `hostbootstrap run <mcts-args>` or `hostbootstrap build` instead. Do not use `docker compose up` or `docker compose exec` for this repository's normal workflow.

## Plan and Doctrine

- [`README.md`](README.md) — authoritative project intent, backend roles, and operator-facing command overview.
- [`DEVELOPMENT_PLAN/README.md`](DEVELOPMENT_PLAN/README.md) — authoritative execution-ordered development plan.
- [`DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md`](DEVELOPMENT_PLAN/phase-9-hostbootstrap-adoption.md) — hostbootstrap orchestrator doctrine, `hostbootstrap.dhall` schema, `FROM ${BASE_IMAGE}` inheritance pattern.
- [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md) — authoritative CLI doctrine.
- [`documents/documentation_standards.md`](documents/documentation_standards.md) — authoritative documentation-topology rules (SSoT, bidirectional links, generated sections).
- `~/hostbootstrap/documents/engineering/derived_project_standards.md` — the five rules every derived project follows (Dockerfile constraints, warm-store cache-hit contract, build-time `mcts check-code`, static-link/`-O2` policy, no redundant rebuilds). MCTS is the reference compliant project.
