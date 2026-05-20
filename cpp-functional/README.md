# cpp-functional

Backend (iii), the retired functional-style C++23 backend.

This tree preserves the functional-style arena/search implementation, C ABI
source, Makefile, and historical PGO profile residue used for the Phase 8 Sprint
8.6 retirement evidence. Live operator selection, `mcts build cpp-functional`,
verify/recompute/play dispatch, and Haskell FFI modules have retired, so normal
validation does not build or load this backend.

The source remains as the historical functional-style anchor that backend (v)
Haskell matched before retirement. See `RETIRED.md` and
`DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md` for the
retirement record.
