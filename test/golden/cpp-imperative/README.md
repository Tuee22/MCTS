# Backend (ii) Retirement Anchor

**Status**: Frozen backend-retirement anchor.
**Owned by**: [Phase 8 Sprint 8.5](../../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md).

This directory preserves backend (ii) `cpp-imperative` after its live CLI,
build, verify, and FFI surfaces retire. The transcript files are the final
live C++ imperative self-play anchor captured immediately before retirement.
The throughput file records the measured Q1/Q2 parity anchor that allowed
backend (iii) `cpp-functional` to succeed backend (ii).

## Layout

```
test/golden/cpp-imperative/
├── README.md
├── throughput.json
└── transcripts/
    └── <arch>/
        └── <sha256-of-file-bytes>.tr
```

The live `cpp-imperative` backend is no longer selectable from the CLI. Use
these files as the historical anchor for backend (ii).
