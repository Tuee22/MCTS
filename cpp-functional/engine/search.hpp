// Functional-style imperative-search interface for backend (iii).
//
// Sprint 6.1 preserved the functional-style API surface: `std::variant`
// for select outcomes, `std::optional` for terminal evaluations, and a
// `DescentStep` value-type to express the descent loop as a sequence of
// state-transition variants. Sprint 6.9 keeps the same surface while
// lowering the implementation to the action-only flat arena and
// iterative descent shape used by backend (ii), so `(iii)` vs `(ii)`
// isolates style at the API/data-flow level rather than memory layout.

#pragma once

#include "arena.hpp"
#include "state.hpp"
#include "xoshiro256pp.hpp"

#include <array>
#include <cstdint>
#include <limits>
#include <random>
#include <utility>
#include <variant>
#include <vector>

namespace mcts_functional {

// `SelectOutcome` is the functional-style return type for child
// selection: either an index into the arena, or an explicit
// "no child" marker, per Sprint 6.1.
struct ChildIdx { uint32_t value; };
struct NoChild {};
using SelectOutcome = std::variant<ChildIdx, NoChild>;

// Sprint 6.1 (data-flow style): the descent loop is expressed as a
// state-transition function returning one of three step variants. The
// Sprint 6.9 lowering iterates the same variant sequence into the
// action-only flat arena.
struct StepDescend { uint32_t to_idx; };
struct StepExpand { uint32_t at_idx; };
struct StepLeaf { uint32_t idx; };
using DescentStep = std::variant<StepDescend, StepExpand, StepLeaf>;

struct RngBackend {
    enum Kind : uint8_t { Mt19937 = 0, Xoshiro = 1 };
    Kind which = Mt19937;
    std::mt19937_64 mt;
    Xoshiro256pp xs{0};

    explicit RngBackend(Kind k, uint64_t seed) noexcept : which(k), mt(seed), xs(seed) {}

    [[gnu::hot, gnu::always_inline]] inline uint64_t bounded(uint64_t bound) noexcept {
        if (which == Xoshiro) return xs.bounded(bound);
        std::uniform_int_distribution<uint64_t> dist(0, bound - 1);
        return dist(mt);
    }
};

struct SearchOutput {
    std::array<std::pair<uint8_t, uint32_t>, kMaxLegalActions> visits{};
    size_t visit_count = 0;
    // Legacy ABI hero-perspective action ID returned through the C ABI.
    uint8_t chosen_action_id = 0;
    // Absolute internal action ID applied through the trusted path.
    uint8_t chosen_absolute_action_id = 0;
    // Hero-perspective equity of the chosen child (`q_sum / visits`),
    // matching `MCTS.Search.UCT.uctSearchWithEquity`.
    double chosen_equity = std::numeric_limits<double>::quiet_NaN();
    bool ok = true;
};

SearchOutput run_search(
    const State &root_state,
    uint32_t sims,
    uint16_t max_plies,
    RngBackend::Kind rng_kind,
    uint64_t seed,
    double exploration_c = 1.41421356);

uint64_t benchmark_terminal_playouts(
    const State &root_state,
    uint32_t count,
    uint16_t max_plies,
    uint64_t seed);

uint64_t benchmark_search_iters(
    const State &root_state,
    uint32_t count,
    uint16_t max_plies,
    RngBackend::Kind rng_kind,
    uint64_t seed);

}  // namespace mcts_functional
