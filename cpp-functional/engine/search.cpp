// Sprint 6.9 implementation: action-only flat arena, iterative descent
// with `State` materialized on the descent stack, hero-perspective
// terminal evaluation, and `BlockMasks`-backed legal action generation.
// The functional-style API surface (`std::variant` outcomes, value-state
// `try_advance` boundary) is preserved via `state.hpp` and `search.hpp`.

#include "search.hpp"

#include "arena.hpp"
#include "state.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>

namespace mcts_functional {
namespace {

[[gnu::hot, gnu::always_inline]] static inline uint64_t splitmix64(uint64_t input) noexcept {
    const uint64_t z1 = input + 0x9e3779b97f4a7c15ULL;
    const uint64_t z2 = (z1 ^ (z1 >> 30)) * 0xbf58476d1ce4e5b9ULL;
    const uint64_t z3 = (z2 ^ (z2 >> 27)) * 0x94d049bb133111ebULL;
    return z3 ^ (z3 >> 31);
}

[[gnu::hot, gnu::always_inline]] static inline uint64_t mix(uint64_t seed, uint64_t index) noexcept {
    return splitmix64(seed + 0x9e3779b97f4a7c15ULL * (index + 1));
}

// Hero-perspective terminal outcome. Mirrors backend (ii) Sprint 5.7.
[[gnu::hot]] static bool terminal_outcome(const State &state, uint16_t max_plies, double &outcome) noexcept {
    if (state.hero_wins()) {
        outcome = 1.0;
        return true;
    }
    if (state.villain_wins()) {
        outcome = -1.0;
        return true;
    }
    if (state.ply_count >= max_plies) {
        outcome = 0.0;
        return true;
    }
    return false;
}

[[gnu::hot, gnu::always_inline]] static inline void add_value(Arena &arena, uint32_t node_idx, double value) noexcept {
    UctNode &node = arena[node_idx];
    ++node.visit_count;
    node.q_sum += value;
}

[[gnu::hot]] static void expand(
    Arena &arena,
    uint32_t node_idx,
    const State &state,
    uint16_t max_plies)
{
    UctNode &node = arena[node_idx];
    if (node.expanded) return;
    node.expanded = 1;
    double outcome = 0.0;
    if (terminal_outcome(state, max_plies, outcome)) {
        node.terminal = 1;
        return;
    }

    ActionBuffer actions;
    state.legal_actions(actions);
    if (actions.empty()) {
        node.terminal = 1;
        return;
    }

    const uint32_t first = arena.reserve_children(static_cast<uint32_t>(actions.size));
    UctNode &parent = arena[node_idx];
    parent.first_child_idx = first;
    parent.n_children = static_cast<uint16_t>(actions.size);
    for (uint32_t i = 0; i < actions.size; ++i) {
        UctNode &child = arena[first + i];
        child.parent_idx = node_idx;
        child.first_child_idx = kNoIndex;
        child.visit_count = 0;
        child.q_sum = 0.0;
        child.n_children = 0;
        child.action_id = actions[i];
        child.expanded = 0;
        child.terminal = 0;
    }
}

[[gnu::hot]] static uint32_t select_best_ucb_offset(
    const Arena &arena,
    uint32_t parent_idx,
    double c) noexcept
{
    const UctNode &parent = arena[parent_idx];
    const uint32_t first = parent.first_child_idx;
    const uint16_t n = parent.n_children;
    const double parent_visits = static_cast<double>(parent.visit_count + 1);
    const double log_parent = std::log(parent_visits > 0.0 ? parent_visits : 1.0);
    double best_score = -std::numeric_limits<double>::infinity();
    uint32_t best_offset = 0;
    for (uint16_t i = 0; i < n; ++i) {
        const UctNode &child = arena[first + i];
        if (child.visit_count == 0) return i;
        const double score =
            (child.q_sum / static_cast<double>(child.visit_count))
                + c * std::sqrt(log_parent / static_cast<double>(child.visit_count));
        if (score > best_score) {
            best_score = score;
            best_offset = i;
        }
    }
    return best_offset;
}

[[gnu::hot]] static double rollout(const State &start, uint64_t seed, uint16_t max_plies) {
    State current = start;
    uint64_t current_seed = seed;
    ActionBuffer actions;
    for (uint16_t step = 0; step < max_plies; ++step) {
        double outcome = 0.0;
        if (terminal_outcome(current, max_plies, outcome)) return outcome;
        current.legal_actions(actions);
        if (actions.empty()) return 0.0;
        const int64_t signed_draw = static_cast<int64_t>(current_seed ^ static_cast<uint64_t>(step));
        int64_t pick_signed = signed_draw % static_cast<int64_t>(actions.size);
        if (pick_signed < 0) pick_signed += static_cast<int64_t>(actions.size);
        current.apply_action_unchecked(actions[static_cast<size_t>(pick_signed)]);
        current_seed = mix(current_seed, step);
    }
    return 0.0;
}

// Sprint 6.9 descent: iterative, materializes `State` on the stack and
// records the visited path so backprop walks it explicitly. Mirrors
// `cpp-imperative/engine/search.cpp::descend_iterative`.
[[gnu::hot]] static double descend_iterative(
    Arena &arena,
    uint32_t root_idx,
    const State &root_state,
    uint64_t seed,
    uint16_t max_plies,
    double c)
{
    State current = root_state;
    uint32_t node_idx = root_idx;
    uint64_t current_seed = seed;
    std::array<uint32_t, 256> path{};
    size_t path_size = 0;
    double outcome = 0.0;

    while (true) {
        path[path_size++] = node_idx;
        if (terminal_outcome(current, max_plies, outcome)) {
            break;
        }

        UctNode &node = arena[node_idx];
        if (node.visit_count == 0) {
            outcome = rollout(current, current_seed, max_plies);
            break;
        }

        if (!node.expanded) {
            expand(arena, node_idx, current, max_plies);
        }
        if (node.terminal || node.n_children == 0) {
            outcome = 0.0;
            break;
        }

        const uint32_t child_offset = select_best_ucb_offset(arena, node_idx, c);
        const uint32_t chosen = node.first_child_idx + child_offset;
        current.apply_action_unchecked(arena[chosen].action_id);
        current_seed = mix(current_seed, static_cast<uint64_t>(child_offset) + 1);
        node_idx = chosen;
    }

    for (size_t i = 0; i < path_size; ++i) {
        add_value(arena, path[i], outcome);
    }
    return outcome;
}

[[gnu::always_inline]] static inline uint8_t raw_action_for_root(
    const State &root_state,
    uint8_t absolute_action_id) noexcept {
    return State::abi_action_from_absolute(root_state.side_to_move, absolute_action_id);
}

[[gnu::hot]] static void push_visit(
    SearchOutput &out,
    const State &root_state,
    uint8_t absolute_action_id,
    uint32_t visits) noexcept {
    if (out.visit_count < out.visits.size()) {
        out.visits[out.visit_count++] =
            std::pair<uint8_t, uint32_t>{raw_action_for_root(root_state, absolute_action_id), visits};
    }
}

[[gnu::hot]] static void sort_visits(SearchOutput &out) noexcept {
    std::sort(
        out.visits.begin(),
        out.visits.begin() + static_cast<std::ptrdiff_t>(out.visit_count),
        [](const auto &a, const auto &b) { return a.first < b.first; });
}

}  // namespace

SearchOutput run_search(
    const State &root_state,
    uint32_t sims,
    uint16_t max_plies,
    RngBackend::Kind rng_kind,
    uint64_t seed,
    double exploration_c)
{
    (void)rng_kind;
    SearchOutput out;
    if (root_state.hero_wins() || root_state.villain_wins()) {
        out.ok = false;
        return out;
    }
    if (root_state.ply_count >= max_plies) {
        ActionBuffer actions;
        root_state.legal_actions(actions);
        if (actions.empty()) {
            out.ok = false;
            return out;
        }
        for (size_t i = 0; i < actions.size; ++i) {
            push_visit(out, root_state, actions[i], 0);
        }
        out.chosen_absolute_action_id = actions[0];
        out.chosen_action_id = raw_action_for_root(root_state, actions[0]);
        out.chosen_equity = 0.0;
        sort_visits(out);
        out.ok = true;
        return out;
    }

    ActionBuffer root_actions;
    root_state.legal_actions(root_actions);
    if (root_actions.empty()) {
        out.ok = false;
        return out;
    }

    const uint32_t reserve_nodes =
        std::max<uint32_t>(32, 1 + static_cast<uint32_t>(root_actions.size) + sims * kMaxLegalActions);
    Arena arena(reserve_nodes);
    const uint32_t root_idx = arena.emplace(kNoAction, kNoIndex);
    const uint32_t first = arena.reserve_children(static_cast<uint32_t>(root_actions.size));
    UctNode &root_node = arena[root_idx];
    root_node.expanded = 1;
    root_node.first_child_idx = first;
    root_node.n_children = static_cast<uint16_t>(root_actions.size);
    root_node.visit_count = 1;
    for (uint32_t i = 0; i < root_actions.size; ++i) {
        UctNode &child = arena[first + i];
        child.parent_idx = root_idx;
        child.first_child_idx = kNoIndex;
        child.visit_count = 0;
        child.q_sum = 0.0;
        child.n_children = 0;
        child.action_id = root_actions[i];
        child.expanded = 0;
        child.terminal = 0;
    }

    uint64_t sim_seed = seed;
    for (uint32_t i = 0; i < sims; ++i) {
        sim_seed = mix(sim_seed, static_cast<uint64_t>(i));
        (void)descend_iterative(arena, root_idx, root_state, sim_seed, max_plies, exploration_c);
    }

    const UctNode &root = arena[root_idx];
    uint32_t best_visits = 0;
    uint32_t best_child = root.first_child_idx;
    for (uint16_t i = 0; i < root.n_children; ++i) {
        const uint32_t child_idx = root.first_child_idx + i;
        const UctNode &child = arena[child_idx];
        push_visit(out, root_state, child.action_id, child.visit_count);
        if (child.visit_count > best_visits) {
            best_visits = child.visit_count;
            best_child = child_idx;
        }
    }
    sort_visits(out);

    const UctNode &chosen = arena[best_child];
    out.chosen_absolute_action_id = chosen.action_id;
    out.chosen_action_id = raw_action_for_root(root_state, chosen.action_id);
    out.chosen_equity =
        chosen.visit_count == 0
            ? std::numeric_limits<double>::quiet_NaN()
            : chosen.q_sum / static_cast<double>(chosen.visit_count);
    out.ok = true;
    return out;
}

uint64_t benchmark_terminal_playouts(
    const State &root_state,
    uint32_t count,
    uint16_t max_plies,
    uint64_t seed)
{
    uint64_t checksum = 0;
    uint64_t current_seed = seed;
    for (uint32_t i = 0; i < count; ++i) {
        current_seed = mix(current_seed, static_cast<uint64_t>(i));
        const double outcome = rollout(root_state, current_seed, max_plies);
        const uint64_t outcome_key =
            outcome > 0.0 ? 0x9e3779b97f4a7c15ULL
            : outcome < 0.0 ? 0xbf58476d1ce4e5b9ULL
                            : 0x94d049bb133111ebULL;
        checksum ^= mix(current_seed, outcome_key ^ static_cast<uint64_t>(i));
    }
    return checksum;
}

uint64_t benchmark_search_iters(
    const State &root_state,
    uint32_t count,
    uint16_t max_plies,
    RngBackend::Kind rng_kind,
    uint64_t seed)
{
    SearchOutput out = run_search(root_state, count, max_plies, rng_kind, seed);
    uint64_t checksum = seed ^ static_cast<uint64_t>(out.chosen_action_id);
    for (size_t i = 0; i < out.visit_count; ++i) {
        const auto &row = out.visits[i];
        checksum ^= (static_cast<uint64_t>(row.first) << 32) ^ static_cast<uint64_t>(row.second);
    }
    return checksum;
}

}  // namespace mcts_functional
