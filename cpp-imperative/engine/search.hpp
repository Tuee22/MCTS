// Imperative UCT search loop driving the flat arena. Returns the
// sorted `(action_id, visits)` vector for the root after `sims`
// simulations, plus the chosen action (the highest-visit child with
// deterministic index-based tie-break).

#pragma once

#include "arena.hpp"
#include "state.hpp"
#include "xoshiro256pp.hpp"

#include <cstdint>
#include <limits>
#include <random>
#include <utility>
#include <vector>

namespace mcts_imperative {

// 64-bit uniform RNG abstraction so search can run against either the
// shared `std::mt19937_64` (under `--rng cpp`) or the local
// xoshiro256++ (under `--rng native`). The hot draw is `bounded` —
// kept inline so the branch on `which_` is folded away when callers
// monomorphise.
struct RngBackend {
    enum Kind : uint8_t { Mt19937 = 0, Xoshiro = 1 };
    Kind which = Mt19937;
    std::mt19937_64 mt;
    Xoshiro256pp xs{0};

    explicit RngBackend(Kind k, uint64_t seed) noexcept : which(k), mt(seed), xs(seed) {}

    [[gnu::hot, gnu::always_inline]] inline uint64_t next() noexcept {
        if (which == Xoshiro) return xs.next();
        return mt();
    }

    [[gnu::hot, gnu::always_inline]] inline uint64_t bounded(uint64_t bound) noexcept {
        if (which == Xoshiro) return xs.bounded(bound);
        std::uniform_int_distribution<uint64_t> dist(0, bound - 1);
        return dist(mt);
    }
};

struct SearchOutput {
    std::vector<std::pair<uint8_t, uint32_t>> visits;  // sorted ascending by action_id
    uint8_t chosen_action_id = 0;
    // Sprint 5.5 / 6.5: parent-perspective equity of the chosen child
    // computed as `-child.q_sum / child.visit_count`. NaN if the
    // chosen child has zero visits.
    double chosen_equity = std::numeric_limits<double>::quiet_NaN();
    bool ok = true;
};

// Run `sims` UCT simulations from `root_state`. The `max_plies`
// argument enables the ply-cap terminal rule per the doctrine.
SearchOutput run_search(
    const State &root_state,
    uint32_t sims,
    uint16_t max_plies,
    RngBackend::Kind rng_kind,
    uint64_t seed,
    double exploration_c = 1.4);

}  // namespace mcts_imperative
