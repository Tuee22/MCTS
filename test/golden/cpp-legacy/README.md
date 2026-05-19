# Backend (i) Retirement Anchor

**Status**: Frozen backend-retirement anchor.
**Owned by**: [Phase 8 Sprint 8.4](../../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md).

This directory preserves backend (i) `cpp-legacy` after its live CLI, build,
verify, and FFI surfaces retire. The transcript files are copied from the Q6
legacy fixture set that pins the repository port to `MCTS_legacy`; the
throughput file records the final live `cpp-legacy` self-play measurement taken
immediately before retirement.

## Layout

```
test/golden/cpp-legacy/
├── README.md
├── throughput.json
└── transcripts/
    └── <arch>/
        └── <sha256-of-file-bytes>.tr
```

The live `cpp-legacy` backend is no longer selectable from the CLI. Use these
files as the historical anchor for Q6 and Q7.
