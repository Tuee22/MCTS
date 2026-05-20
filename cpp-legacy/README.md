# cpp-legacy

Backend (i), the verbatim `~/MCTS_legacy/backend/core` re-port.

This tree retains the imported legacy core, C ABI wrapper source, RNG shim, and
`legacy-to-wire` evidence generator. `cpp-legacy` remains a first-class backend
slot for build, FFI envelope/recompute surfaces, Q6 legacy reproduction evidence,
and Q7 legacy-envelope liveness/overflow checks across all five backends.

It is intentionally excluded from the default Q3 `mcts verify rollouts` /
`mcts verify selfplay` cohort because its terminal-state and search-kernel
semantics are line-faithful legacy behavior. Q3 compares the steelman cohort
`(ii)..(v)`; Q7 covers `(i)..(v)` under the legacy envelope.

The optional external evidence generator is:

```bash
docker compose run --rm mcts mcts build legacy-fixtures --output-dir /tmp/mcts-legacy-fixtures
```

Generated legacy evidence belongs in an explicit external or ignored artifact
root, not in repository validation fixtures. See
`DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md` and
`DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md` for the current
backend role.
