# cpp-legacy

Backend (i), the retired verbatim `~/MCTS_legacy/backend/core` re-port.

This tree retains the imported legacy core, C ABI wrapper source, RNG shim, and
`legacy-to-wire` evidence generator for historical audit work. Live
CLI/build/verify/FFI dispatch for `cpp-legacy` retired in Phase 8 Sprint 8.4, so
normal validation does not build or load `cpp-legacy` as a selectable backend.

The supported command that still touches this tree is the optional external
evidence generator:

```bash
docker compose run --rm mcts mcts build legacy-fixtures --output-dir /tmp/mcts-legacy-fixtures
```

Generated legacy evidence belongs in an explicit external or ignored artifact
root, not in repository validation fixtures. See `RETIRED.md` and
`DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md` for the
retirement record.
