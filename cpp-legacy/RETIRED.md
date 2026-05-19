# Backend (i) `cpp-legacy` Retired

**Status**: Retired in Phase 8 Sprint 8.4.
**Frozen anchor**: `test/golden/cpp-legacy/`

Backend (i) was the verbatim C++ port used to prove the repository could
reproduce `MCTS_legacy`. That proof is now preserved by the Q6 fixtures under
`test/golden/legacy/` and the backend-retirement anchor under
`test/golden/cpp-legacy/`.

The source remains in `cpp-legacy/` for historical reference and for the
fixture generator used by `mcts build legacy-fixtures`, but it is no longer a
live selectable backend. Normal validation does not build or load
`cpp-legacy/build/libmcts_cpp_legacy.so`, and `mcts verify legacy-parity` has
retired with the live backend.

The preserved parity chain is:

`MCTS_legacy == backend (i) == historical Q6 anchor`

The surviving live cohort after this retirement is backend (ii)
`cpp-imperative`, backend (iii) `cpp-functional`, backend (iv) `rust`, and
backend (v) `haskell`.
