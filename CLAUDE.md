# CLAUDE.md

## Git Restrictions for LLM Agents

The following git commands are **FORBIDDEN** for LLM agents:

- `git add`
- `git commit`
- `git push`

Only the human user is permitted to run these commands. Agents must never stage, commit, or push changes to the repository under any circumstances, even if explicitly asked. If staging, committing, or pushing appears necessary, stop and inform the human user so they can perform the action themselves.

This restriction applies to all variants and equivalents (e.g., `git commit -a`, `git push --force`, plumbing commands that achieve the same effect, scripts or aliases that wrap these commands, etc.).

## Build, Run, and Validation Environment

All supported project build, run, validation, formatting, linting, documentation-generation, test, benchmark, and backend-build work must enter through the root Compose service:

```bash
docker compose run --rm mcts mcts <command>
```

Do not run project commands directly on the host with ambient toolchains or host-installed binaries. In particular, do not use host `cabal run`, `cabal exec`, `cargo`, `cmake`, `make`, `fourmolu`, `hlint`, or similar commands as a fallback for project work.

Repository shell-script wrappers are not supported. Do not add or run `.sh` scripts, `bootstrap/` helpers, or other host-side orchestration for project build, run, validation, formatting, linting, documentation-generation, test, benchmark, or backend-build work. If a workflow is needed, expose it as an `mcts` command and run it through the Compose entrypoint above.

Host-side file inspection and bookkeeping commands such as `rg`, `sed`, `git diff --check`, and `git status --short` are acceptable when they do not build, run, format, lint, generate, or validate the project. Do not use `docker compose up` or `docker compose exec` for this repository's normal workflow; use the one-shot `docker compose run --rm mcts mcts <command>` shape instead.

## Plan and Doctrine

- [`DEVELOPMENT_PLAN/README.md`](DEVELOPMENT_PLAN/README.md) — authoritative execution-ordered development plan.
- [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md) — authoritative CLI doctrine.
- [`documents/documentation_standards.md`](documents/documentation_standards.md) — authoritative documentation-topology rules (SSoT, bidirectional links, generated sections).
