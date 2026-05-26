# Backend Style Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../../README.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/00-overview.md, ../../DEVELOPMENT_PLAN/system-components.md, ../../DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md, ../../DEVELOPMENT_PLAN/phase-8-haskell-performance-parity-closure.md, ../documentation_standards.md, ./README.md, ./backend_ffi_contract.md, ./compiler_runtime_tuning.md, ./determinism_contract.md
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
  `uint64_t walls_h`, `uint64_t walls_v`, `uint16_t ply`, and `uint8_t last_action`;
- zero-overhead value APIs such as `legal_actions(const State&, MoveBuffer&)`,
  `apply_action(State, uint8_t) -> std::optional<State>`, and
  `terminal_outcome(const State&, uint16_t)`;
- `constexpr` mapping helpers for action IDs, wall bits, orientation flips, and
  canonical ordering;
- `noexcept`, `[[gnu::hot]]`, `[[gnu::always_inline]]`, stack/SBO move buffers,
  and contiguous arena storage where they improve the measured hot path;
- no exceptions from the engine core, matching the shared C++ steelman flag set.

Backend (iii) must not keep any of these in the hot path:

- `corridors::board` as the search board representation;
- `get_action_text`, `std::stoi`, or text parsing to identify actions;
- generation of the full legacy legal wall set followed by sort/filter to apply
  the 12-wall cap;
- recursive legacy escapability over contact flags when a bitfield path check can
  answer the same rule directly.

Sprint `6.7` removed that migration residue from backend (iii)'s hot path and
deleted the backend-local legacy `board.*` / `mcts.hpp` copies. The completed
cleanup is recorded in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).

## Backend (iv) Rust Target

Rust should stay close to the same functional-core model:

- `#[derive(Clone)]` compact board values with scalar pawn/wall fields and bitfield
  wall maps;
- methods that make transition intent explicit, such as `legal_actions`,
  `apply_action_flip`, and path-check helpers;
- `Vec<Node>` / `Vec<State>` or equivalent contiguous arenas for search internals;
- local mutation of trial states and move buffers only inside the implementation
  of value-style operations;
- no `Rc`, `Arc`, trait objects, heap-owned board graph, or text action codec in
  the search hot path.

Rust may use Rust-specific idioms for ownership and borrowing, but naming,
action-order semantics, ply-cap handling, and boundary shape should remain close
enough that `(iii)` and `(v)` can be reviewed against the same state-transition
story.

## Backend (v) Haskell Target

Haskell remains the native target and keeps its pure API surface:

- strict compact `Board` fields for pawns, wall bitfields, wall counts, side to
  move, and ply;
- `legalMoves :: Board -> [Action]` and `applyMove :: Action -> Board -> Board`
  as pure transitions;
- a packed numeric hot-path boundary (`legalActionSet`, `ActionIds`, and
  `applyActionId`) used by rollout and UCT descent so the pure public API does not
  force list/action allocation inside the search loop;
- `ST`-local arena and mutable scratch internals for UCT search;
- no FFI-shaped pointers or C ABI data in domain types;
- no `Maybe`/`Either` allocation in rollout inner loops when sentinel or unboxed
  representations preserve the public pure boundary.

Haskell does not need to adopt C++ or Rust's exact orientation-normalization
fields. It must preserve the same canonical action ID contract and equivalent
legal-move ordering.

## Acceptance

Backend (iii) is style-aligned when its remaining gap to backend (ii) is
explainable by C++ functional-core API/data-flow choices, not by a different board
representation, string decoding, full-wall generation, or legacy escapability
algorithm. Sprint `6.7` closed that backend (iii) cleanup, and Sprint `8.13`
closed the backend (v) Haskell alignment by keeping Haskell's pure boundary while
using the compact numeric action-set transition shape in the hot path.

Validation for style-alignment work must include:

- Q3 `verify` across `(ii)..(v)` under `--rng cpp`;
- Q6 legacy-envelope liveness across `(i)..(v)`;
- focused native-RNG benchmarks comparing `(ii)` and `(iii)` on terminal playout,
  search-iteration, and played-game throughput;
- the aggregate documentation and code-quality gates required by the owning sprint.
