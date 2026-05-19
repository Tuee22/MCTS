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
`<sha>.tr` file per game. Fixture regeneration uses the supported Plan/Apply
entrypoint:

```bash
docker compose run --rm mcts mcts build legacy-fixtures \
  --output-dir test/golden/legacy/transcripts \
  --seed 42 \
  --games 10 \
  --sims 10000
```

The command builds `cpp-legacy/build/legacy-to-wire` inside the plan and then
invokes it with explicit flags. Direct `make`, direct tool execution, and
environment-variable-driven fixture regeneration are not supported operator
workflows.

The historical fixture constants are seed `42`, `10` games, and the spec
value `S_LP_SIMS = 10000`. The committed `amd64` fixtures were regenerated
through the command above after confirming the imported core matches
`/home/matt/MCTS_legacy/backend/core/` modulo whitespace.

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

1. Lists every `.tr` file under every committed `transcripts/<arch>/`
   directory, regardless of the current host architecture.
2. Decodes each via `MCTS.Transcript.decodeTranscript`.
3. Asserts each filename equals `sha256(file_bytes)`.
4. Asserts the decoded transcript's backend slot equals `cpp-legacy`,
   the workload is self-play, threading is single, RNG source is `cpp`,
   seed is `42`, sims and `max_plies` are `10000`, each file contains one
   game, and no game records a `Draw` winner (the legacy has no draw rule).
