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

Sprint `5.8` (2026-05-29) closed the residual hot-path squeeze identified in
the post-`5.7` review. The deliverables are visit-preserving and ABI-stable
(the post-`5.8` `mcts test all` recorded `normalized_divergence_score=0.0000`
and Q3/Q4/Q6/Q7 PASS):

- **D1.** `engine/fast_board.hpp::path_exists_with_masks` now uses a
  bidirectional bit-parallel BFS — expanding outward from the pawn cell and
  inward from the goal row simultaneously, returning true on intersection.
  The `bool` contract is unchanged, so `wall_action_legal` continues to call
  the function twice (once per player) without further refactor. The
  combined two-player bitsliced wavefront and the `unsigned __int128` codegen
  audit are deferred follow-ons pending the bidirectional benchmark.
- **D2.** `engine/arena.hpp::UctNode` no longer carries `alignas(kCacheLine)`
  because the (ii) hot path is single-threaded; the constant remains
  documented for any future multi-thread introduction. The arena
  `reserve_nodes` formula in `engine/search.cpp` is the correct upper bound
  (each `expand` adds up to `kMaxLegalActions = 16` children in one shot)
  and was kept; the `arena.hpp` docblock now describes the bound honestly.
- **D3.** `Makefile` appends `-fno-stack-protector -fno-rtti -fipa-pta` to
  the C++ steelman flag set and extends the BOLT invocations with
  `-split-functions -split-strategy=cdsplit -reorder-functions=cdsort
  -icf=1`. Each addition is gated by its own focused (ii) benchmark and
  reverted on focused-row regression.

Phase `8` Sprint `8.16` closed on 2026-05-29 with the downstream
Haskell-vs-`(ii)` rebaseline against the post-`5.8` `(ii)` artefact: Q1a
`1.51x` ST / `1.50x` MT8, Q1b `1.53x` ST / `1.56x` MT8, Q2 `1.41x` ST /
`1.57x` MT8; `Verdict: Trails parity band by 57.1%`. Backend `(ii)`
delivered ~2–6% improvement on the focused ST rows vs the Sprint `8.15`
post-`5.7` measurement.
