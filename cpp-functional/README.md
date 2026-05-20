# cpp-functional

Backend (iii), the functional-style C++23 steelman backend.

This tree contains the functional-style arena/search implementation, C ABI
source, Makefile, and PGO/BOLT build surface. It remains a first-class backend
slot for `mcts build cpp-functional`, benchmark measurement, live FFI
search/recompute/envelope loading, selected-backend play, and Q3
logical-equivalence verification.

Backend (iii) uses the same optimization stack as backend (ii), so the
comparison isolates C++ programming style rather than compiler/runtime
advantages. See `DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md` and
`DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md` for the current
backend role.
