# cpp-imperative

Backend (ii), the maximally tuned imperative C++23 steelman.

This tree preserves the arena/search implementation, C ABI source, Makefile, and
Makefile-level PGO/BOLT build targets used for the intended performance ceiling.
It remains a first-class backend slot for `mcts build cpp-imperative`, benchmark
measurement, live FFI search/recompute/envelope loading, selected-backend play,
and Q3 logical-equivalence verification. The supported `mcts build
cpp-imperative` path now drives the PGO/BOLT target sequence through the CLI
Plan/Apply harness and installs the canonical shared library, using the documented
BOLT fallback when no usable `.fdata` is produced.

The project uses this backend to steelman C++: Haskell parity is measured
against backend (ii), while backend (iii) isolates C++ style under the same
optimization stack. See
`DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md` and
`DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md` for the current
backend role.
