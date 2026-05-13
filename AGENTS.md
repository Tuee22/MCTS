# AGENTS.md

## Git Restrictions for LLM Agents

The following git commands are **FORBIDDEN** for LLM agents:

- `git add`
- `git commit`
- `git push`

Only the human user is permitted to run these commands. Agents must never stage, commit, or push changes to the repository under any circumstances, even if explicitly asked. If staging, committing, or pushing appears necessary, stop and inform the human user so they can perform the action themselves.

This restriction applies to all variants and equivalents (e.g., `git commit -a`, `git push --force`, plumbing commands that achieve the same effect, scripts or aliases that wrap these commands, etc.).

## Plan and Doctrine

- [`DEVELOPMENT_PLAN/README.md`](DEVELOPMENT_PLAN/README.md) — authoritative execution-ordered development plan.
- [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md) — authoritative CLI doctrine.
