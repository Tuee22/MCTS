// Functional-style imperative-search interface. The functional API
// surface uses `std::variant` for select outcomes and `std::optional`
// for terminal evaluations (per Sprint 6.1's "functional style at the
// API and data-flow level"); the implementation lowers to the same
// arena-MCTS algorithm as backend (ii), with the same absolute action
// ordering, splitmix seed schedule, and hero-perspective value
// propagation as the Haskell verifier.

#pragma once

#include "arena.hpp"
#include "state.hpp"
#include "xoshiro256pp.hpp"

#include <cstdint>
#include <limits>
#include <random>
#include <utility>
#include <variant>
#include <vector>

namespace mcts_functional {

// `SelectOutcome` is the functional-style return type for child
// selection: either an index into the arena, or an explicit
// "no child" marker, per Sprint 6.1 (`std::variant<ChildIdx, NoChild>`
// rather than a sentinel -1).
struct ChildIdx { uint32_t value; };
struct NoChild {};
using SelectOutcome = std::variant<ChildIdx, NoChild>;

// Sprint 6.1 (data-flow style): the descent loop is expressed as a
// state-transition function returning one of three step variants.
// The lowering still uses the same arena machinery as backend (ii);
// the source-level shape differs — descent is a sequence of
// `DescentStep` transitions rather than a fall-through `while (true)`
// with `break`/`continue` control flow.
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
    std::vector<std::pair<uint8_t, uint32_t>> visits;
    uint8_t chosen_action_id = 0;
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

}  // namespace mcts_functional
