# cpp-imperative

Backend (ii), the maximally tuned imperative C++23 steelman.

This tree preserves the arena/search implementation, C ABI source, Makefile, and
PGO/BOLT build surface used as the performance ceiling for the project. It
remains a first-class backend slot for `mcts build cpp-imperative`, benchmark
measurement, live FFI search/recompute/envelope loading, selected-backend play,
and Q3 logical-equivalence verification.

The project uses this backend to steelman C++: Haskell parity is measured
against backend (ii), while backend (iii) isolates C++ style under the same
optimization stack. See
`DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md` and
`DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md` for the current
backend role.
