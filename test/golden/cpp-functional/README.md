# Backend (iii) Retirement Anchor

**Status**: Frozen backend-retirement anchor.
**Owned by**: [Phase 8 Sprint 8.6](../../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md).

This directory preserves backend (iii) `cpp-functional` after its live CLI,
build, verify, and FFI surfaces retire. The transcript files are the final
live C++ functional-style self-play anchor captured immediately before
retirement. The throughput file records the measured Q1/Q2 parity anchor that
allowed backend (v) `haskell` to succeed backend (iii).

## Layout

```
test/golden/cpp-functional/
├── README.md
├── throughput.json
└── transcripts/
    └── <arch>/
        └── <sha256-of-file-bytes>.tr
```

The live `cpp-functional` backend is no longer selectable from the CLI. Use
these files as the historical anchor for backend (iii).
