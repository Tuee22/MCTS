# Backend Style Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/00-overview.md, ../../DEVELOPMENT_PLAN/system-components.md, ../../DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md, ../../DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md, ../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md, ../documentation_standards.md, ./README.md, ./backend_ffi_contract.md, ./compiler_runtime_tuning.md, ./determinism_contract.md
**Generated sections**: none

> **Purpose**: Define the functional-core style shared by backends (iii), (iv),
> and (v), and separate that style from accidental legacy representation costs.

This document owns the style contract for the functional cohort. Compiler flags,
PGO/BOLT, allocator policy, and parity tolerance live in
[compiler_runtime_tuning.md](./compiler_runtime_tuning.md). C ABI symbol shapes and
opaque-handle ownership live in
[backend_ffi_contract.md](./backend_ffi_contract.md). RNG and equivalence semantics
live in [determinism_contract.md](./determinism_contract.md).

## Scope

The functional cohort is:

- backend (iii) `cpp-functional`;
- backend (iv) `rust`;
- backend (v) `haskell`.

Backend (ii) `cpp-imperative` remains the imperative performance ceiling. Backend
(i) `cpp-legacy` remains a verbatim compatibility port. This contract does not
require `(iii)` to copy `(ii)`'s imperative API shape, but it does require `(iii)`
to use the same class of compact representation and hot-path work as `(iv)` and
`(v)` so that measured differences are attributable to style rather than legacy
object-model residue.

Phase `5` Sprint `5.7` closed only backend `(ii)`'s imperative-kernel steelman. It
does not reopen the closed functional implementations in `(iii)`, `(iv)`, or
`(v)`. The Sprint `5.7` target is action-id generation, absolute side-to-move
state, action-only or split hot/cold tree storage, reusable wall masks, trusted
internal apply/cache paths, and retuned PGO/BOLT training for `(ii)`.

Phase `5` Sprint `5.8` extends backend `(ii)`'s budget with the residual
hot-path squeeze: bidirectional bit-parallel BFS in `path_exists_with_masks`,
`UctNode` `alignas(64)` removed, additive `-fno-stack-protector -fno-rtti
-fipa-pta` C++ flags, and extended BOLT `-split-functions
-split-strategy=cdsplit -reorder-functions=cdsort -icf=1`. None of these
deliverables change the visit-payload contract, the C ABI, or the
functional-core boundary that `(iii)`, `(iv)`, and `(v)` follow; they only
tighten backend `(ii)`'s imperative kernel and toolchain. Functional-core
backends do not need a matching change.

## Functional-Core Rule

Functional style in this repository means value-state game logic at the boundary:
typed action IDs, deterministic legal-action order, explicit state transitions,
and no observable mutation leaking out of the search call. It does not mean heap
allocated board graphs, text-encoded actions, full legacy wall-set enumeration, or
avoiding local mutation where local mutation is the efficient implementation of a
pure boundary.

Allowed implementation techniques:

- flat MCTS arenas, mutable arrays, and local scratch buffers inside one search call;
- compact scalar board fields and 8x8 wall bitfields;
- local mutation of a copied/trial board for path checks and child construction;
- thread-local scratch buffers that carry no semantic state between games.

Required boundary properties:

- board states are cheap value snapshots, not shared object graphs;
- actions are represented as canonical `uint8_t`/`Word8` action IDs or typed
  algebraic actions with one named conversion boundary;
- `legal_actions` / `legalMoves` emits pawn actions plus the first 12 legal wall
  actions in canonical order;
- `apply_action` / `applyMove` is a typed state transition, not a string parse;
- terminal checks include the `Word16`/`uint16_t` ply-cap draw rule;
- any internal current-player normalization or explicit side-to-move field must
  produce the same canonical action IDs and Q3 visit payloads.

## Backend (iii) C++ Target

Backend (iii) is written as idiomatic C++23 functional-core code:

- a compact `State` / `Board` value with pawn coordinates, remaining-wall counts,
  `uint64_t walls_h`, `uint64_t walls_v`, `uint16_t ply`, `uint8_t last_action`,
  and an explicit absolute `SideToMove` field;
- zero-overhead value APIs such as `legal_actions(const State&, MoveBuffer&)`,
  `apply_action(State, uint8_t) -> std::optional<State>`, and
  `terminal_outcome(const State&, uint16_t)`;
- `constexpr` mapping helpers for action IDs, wall bits, orientation flips, and
  canonical ordering;
- `noexcept`, `[[gnu::hot]]`, `[[gnu::always_inline]]`, stack/SBO move buffers,
  and contiguous arena storage where they improve the measured hot path;
- no exceptions from the engine core, matching the shared C++ steelman flag set;
- a reusable `BlockMasks` value precomputed once per `legal_actions` call and
  reused across all wall candidates by additive mask increments, mirroring the
  backend (ii) `block_masks()` / `add_wall_to_masks()` pattern;
- bidirectional bit-parallel BFS in `path_exists_with_masks`, mirroring backend
  (ii) Sprint `5.8` `fast_board.hpp::path_exists_with_masks`;
- action-only MCTS tree nodes (`parent_idx`, `first_child_idx`, `n_children`,
  `action_id`, `visit_count`, `q_sum`, `expanded`, `terminal`); search materializes
  the `State` on the descent stack and applies trusted `apply_action_unchecked`
  while marching down, matching backend (ii)'s action-only arena;
- the additive C++ flag set `-fno-stack-protector -fno-rtti -fipa-pta` and the
  extended BOLT invocation `-split-functions -split-strategy=cdsplit
  -reorder-functions=cdsort -icf=1` on top of `-reorder-blocks=ext-tsp`, matching
  the Sprint `5.8` backend (ii) Makefile.

Backend (iii) must not keep any of these in the hot path:

- `corridors::board` as the search board representation;
- `get_action_text`, `std::stoi`, or text parsing to identify actions;
- generation of the full legacy legal wall set followed by sort/filter to apply
  the 12-wall cap;
- recursive legacy escapability over contact flags when a bitfield path check can
  answer the same rule directly;
- a `flipped_after_move()` full-state coordinate/wall reversal on every
  transition — orientation is tracked by the absolute `SideToMove` field;
- a per-wall-candidate `State` copy and inline mask recomputation in
  `wall_action_legal` — candidates run against an additively-extended
  `BlockMasks` value;
- a full embedded `State` per `UctNode`.

Sprint `6.7` removed the migration residue from backend (iii)'s hot path and
deleted the backend-local legacy `board.*` / `mcts.hpp` copies. Sprint `6.9`
adopts the additional permitted backend (ii) techniques listed above. The
completed cleanup rows are recorded in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

## Backend (iv) Rust Target

Rust should stay close to the same functional-core model:

- `#[derive(Clone)]` compact board values with scalar pawn/wall fields, bitfield
  wall maps, and an explicit absolute `SideToMove` field;
- methods that make transition intent explicit, such as `legal_actions`,
  `apply_action`, and path-check helpers; the per-transition `flipped()`
  coordinate/wall reversal is replaced by toggling `SideToMove`;
- bit-parallel `u128` bidirectional wavefront path-existence checks over
  precomputed wall-block masks, matching the shape used by `(ii)`, `(iii)`, and
  `(v)`;
- a reusable `BlockMasks` value precomputed once per `legal_actions` call and
  reused across all wall candidates by additive mask increments, replacing the
  prior per-candidate full-board clone in `wall_placement_legal`;
- stack or packed small action buffers for the at-most-16 legal action IDs, rather
  than per-rollout heap allocation;
- `Vec<Node>` / `Vec<State>` or equivalent contiguous arenas for search internals,
  reserved to the same child-bound shape as `(iii)` and `(v)` so search does not
  reallocate during ordinary simulation budgets;
- local mutation of trial states and move buffers only inside the implementation
  of value-style operations;
- **the optional `read_visits` cache must live on the opaque Rust board handle
  declared in `rust/src/c_abi.rs`, never on the search-board struct**; this is the
  load-bearing contract that keeps wall-candidate paths and per-rollout copies
  free of the 169-byte cache footprint, and it is what
  [./backend_ffi_contract.md](./backend_ffi_contract.md) refers to as the
  handle-local read-visits cache;
- `#[inline(always)]` on the hot leaf operations and `#[cold]` on terminal and
  early-exit paths, matching the marking density `(iii)` carries via `[[gnu::hot]]`;
- no `Rc`, `Arc`, trait objects, heap-owned board graph, or text action codec in
  the search hot path.

Rust may use Rust-specific idioms for ownership and borrowing, but naming,
action-order semantics, ply-cap handling, and boundary shape remain close
enough that `(iii)` and `(v)` can be reviewed against the same state-transition
story. Sprint `6.8` closed Rust's compact value-state boundary and the bit-parallel
path check, and Sprint `6.10` closes the remaining shape items above: visit-cache
relocation onto the opaque handle, additive `BlockMasks` reuse in wall legality,
explicit `SideToMove` (no full-board flip on transitions), and bidirectional BFS.

## Backend (v) Haskell Target

Haskell remains the native target and keeps its pure API surface:

- strict compact `Board` fields for pawns, wall bitfields, wall counts, side to
  move, and ply;
- `legalMoves :: Board -> [Action]` and `applyMove :: Action -> Board -> Board`
  as pure transitions;
- a packed numeric hot-path boundary (`legalActionSet`, `ActionIds`, and
  `applyActionId`) used by rollout and UCT descent so the pure public API does not
  force list/action allocation inside the search loop;
- `ST`-local UCT arena backed by a single `MutableByteArray# s` with named per-field
  offsets, replacing the six parallel `STUArray` slabs used by the Sprint `8.13`
  baseline; the SoA layout (parent, firstChild, numChildren, actionId, visits,
  valueSum) is preserved at the field-offset level;
- no FFI-shaped pointers or C ABI data in domain types;
- no `Maybe`/`Either` allocation in rollout inner loops when sentinel or unboxed
  representations preserve the public pure boundary.

Haskell does not need to adopt C++ or Rust's exact orientation-normalization
fields. It must preserve the same canonical action ID contract and equivalent
legal-move ordering. Sprint `8.17` lands the `MutableByteArray#` arena
migration and the tail-end `INLINE` audit on the descent/rollout boundary
described in
[./compiler_runtime_tuning.md](./compiler_runtime_tuning.md) Backend (v)
Code-Level Requirements.

## Acceptance

Backend (iii) is style-aligned when its remaining gap to backend (ii) is
explainable by C++ functional-core API/data-flow choices, not by a different board
representation, string decoding, full-wall generation, legacy escapability
algorithm, per-transition full-state flip, per-candidate `State` copy in wall
legality, or full-state embedded `UctNode`. Sprint `6.7` closed the backend (iii)
legacy-representation cleanup, Sprint `8.13` closed the backend (v) Haskell
alignment by keeping the pure boundary while using compact numeric action-set
transitions in the hot path, and Sprint `6.8` closed backend (iv) Rust by replacing
queue-BFS, heap action-buffer, under-reserved arena, extra clone, and global
visit-cache residue. Sprint `6.9` closes the remaining backend (iii) shape items
(absolute `SideToMove`, additive `BlockMasks` reuse, bidirectional BFS, action-only
`UctNode`, additive `-fno-stack-protector -fno-rtti -fipa-pta` plus extended BOLT
invocation), Sprint `6.10` closes the remaining backend (iv) shape items
(visit-cache relocation onto the opaque handle, additive `BlockMasks` reuse,
absolute `SideToMove`, bidirectional BFS, inlining/cold-path marking), and Sprint
`8.17` lands the backend (v) `MutableByteArray#` arena migration and the
descent/rollout `INLINE` audit.

Validation for style-alignment work must include:

- Q3 `verify` across `(ii)..(v)` under `--rng cpp`;
- Q6 legacy-envelope liveness across `(i)..(v)`;
- focused native-RNG benchmarks comparing `(ii)` and `(iii)` on terminal playout,
  search-iteration, and played-game throughput;
- focused native-RNG benchmarks comparing `(iv)` against `(iii)` and `(v)`, so
  Rust is measured against the functional-core cohort rather than only against the
  imperative ceiling;
- the aggregate documentation and code-quality gates required by the owning sprint.
