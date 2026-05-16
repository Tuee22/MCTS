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
`<sha>.tr` file per game.

```
docker compose up -d
docker compose exec mcts make -C cpp-legacy legacy-to-wire
docker compose exec mcts ./cpp-legacy/build/legacy-to-wire \
    test/golden/legacy/transcripts
```

The tool reads three optional environment variables:

| Variable | Default | Spec value |
|----------|---------|------------|
| `LEGACY_FIXTURE_SEED` | `42` | `S_LP = 42` |
| `LEGACY_FIXTURE_GAMES` | `10` | `G_LP = 10` |
| `LEGACY_FIXTURE_SIMS` | `10000` | `S_LP_SIMS = 10_000` |

The committed fixtures use `LEGACY_FIXTURE_SIMS=1000` so the regenerate
step fits in routine CI budgets; the full report-card snapshot at
`S_LP_SIMS=10000` is reserved for the doctrine's actual report-card
publication and remains a manual run gated by the surrounding cohort
preparation. The chosen sim count is the same for every fixture in a
single regenerate, so internal byte-equality holds across runs.

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
