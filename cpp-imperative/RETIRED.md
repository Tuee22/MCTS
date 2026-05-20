# Backend (ii) `cpp-imperative` Retired

**Status**: Retired in Phase 8 Sprint 8.5.
**Frozen anchor**: source-owned report-card anchor constants plus historical plan evidence.

Backend (ii) was the maximally tuned imperative C++ steelman used as the
performance target for the pure Haskell backend and as the immediate successor
to backend (i). Its final Q1/Q2 parity anchor shows backend (iii)
`cpp-functional` within tolerance, so backend (ii) is now preserved by
historical plan evidence and source-owned report-card anchor constants rather
than normal validation fixtures.

The source remains in `cpp-imperative/` for historical reference, but it is no
longer a live selectable backend. Normal validation does not build or load
`cpp-imperative/build/libmcts_cpp_imperative.so`, and `mcts build
cpp-imperative` has retired with the live backend.

The preserved parity chain is:

`backend (ii) == backend (iii) historical Q1/Q2 anchor`

The surviving live cohort after this retirement is backend (iii)
`cpp-functional`, backend (iv) `rust`, and backend (v) `haskell`.
