# Legacy Golden Fixtures (Q6)

**Status**: Authoritative source for backend (i) byte-equality.
**Owned by**: [Phase 4 Sprint 4.5](../../../DEVELOPMENT_PLAN/phase-4-cpp-legacy-port-and-ffi-bridge.md).

Frozen wire-format transcripts produced by the legacy core under
`cpp-legacy/legacy-core/` (a byte-identical port of
`~/MCTS_legacy/backend/core/`). The integration stanza decodes each fixture and
asserts the legacy parity envelope and no-draw-rule semantics; the fixtures
themselves are the regression anchor that pins backend (i)'s output to a
specific point-in-time legacy snapshot per
[Q6](../../../README.md).

## Layout

```
test/golden/legacy/
├── README.md
└── transcripts/
    └── <arch>/
        └── <sha256-of-file-bytes>.tr
```

`<arch>` is one of `arm64` or `amd64`. Each `.tr` file is a single-game
transcript in the Phase 2 wire format (header + envelope + one game block).

## How fixtures are produced

The conversion script lives at
[`cpp-legacy/tools/legacy-to-wire.cc`](../../../cpp-legacy/tools/legacy-to-wire.cc).
It links directly against `cpp-legacy/legacy-core/` and writes one
`<sha>.tr` file per game. Fixture regeneration is not a routine operator
entrypoint under the current container doctrine: supported host work must enter
through `docker compose run --rm mcts mcts <command>`. A future fixture refresh
must add or use a `mcts` subcommand for the regeneration path rather than
documenting direct `make` or direct tool execution from the host.

The historical fixture constants are seed `42`, `10` games, and the spec
value `S_LP_SIMS = 10000`. The committed arm64 fixtures capture a transitional
`1000`-simulation snapshot so routine checks stay bounded; the full
`10000`-simulation refresh is reserved for the doctrine's report-card
publication and must be exposed as CLI flags on the future `mcts` regeneration
subcommand. Environment-variable-driven fixture regeneration is not a supported
operator workflow.

## When fixtures regenerate

Per [development_plan_standards.md §I](../../../DEVELOPMENT_PLAN/development_plan_standards.md):

- The fixture set is a frozen historical record.
- It regenerates only when either:
  1. `~/MCTS_legacy/` is upgraded and `cpp-legacy/legacy-core/` is
     re-imported.
  2. The wire format's `flags u32` bumps.
- Any other refresh is a separate scheduled sprint and is enqueued as
  cleanup in
  [legacy-tracking-for-deletion.md](../../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

## What the integration stanza checks

`test/integration/Main.hs` includes a `legacy goldens` group that:

1. Lists every `.tr` file in `transcripts/<host_arch>/`.
2. Decodes each via `MCTS.Transcript.decodeTranscript`.
3. Asserts the decoded transcript's backend slot equals `cpp-legacy`,
   the envelope's RNG source equals `cpp`, and no game records a
   `Draw` winner (the legacy has no draw rule).

Full byte-exact comparison against a `mcts bench` regeneration is gated on
the Phase 2 single-game-file wire-format alignment — the current Haskell
writer aggregates multiple games into one file, while the fixtures
follow the one-game-per-file rule from
[../../../README.md → Cross-backend verification](../../../README.md);
the gap is tracked in
[../../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).
