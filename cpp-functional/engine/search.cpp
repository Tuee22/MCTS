#include "search.hpp"

#include "arena.hpp"
#include "board.h"
#include "state.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace mcts_functional {
namespace {

thread_local std::vector<corridors::board> tls_move_buffer;

[[gnu::hot]] static uint8_t decode_action_id(const corridors::board &b) noexcept {
    std::string action = b.get_action_text(false);
    if (action.size() < 5) return 0;
    const bool pawn = action[0] == '*';
    const bool horizontal = action[0] == 'H';
    const bool vertical = action[0] == 'V';
    const size_t open = action.find('(');
    const size_t comma = action.find(',');
    const size_t close = action.find(')');
    if (open == std::string::npos || comma == std::string::npos || close == std::string::npos) {
        return 0;
    }
    const int x = std::stoi(action.substr(open + 1, comma - open - 1));
    const int y = std::stoi(action.substr(comma + 1, close - comma - 1));
    if (pawn) return static_cast<uint8_t>(y * 9 + x);
    if (horizontal) return static_cast<uint8_t>(81 + y * 8 + x);
    if (vertical) return static_cast<uint8_t>(145 + y * 8 + x);
    return 0;
}

[[gnu::hot]] static void expand(Arena &arena, uint32_t node_idx, uint16_t max_plies) {
    UctNode &node = arena[node_idx];
    if (node.expanded) return;
    node.expanded = 1;
    if (node.state.is_terminal(max_plies)) {
        node.terminal = 1;
        return;
    }
    tls_move_buffer.clear();
    node.state.b.get_legal_moves(tls_move_buffer);
    const uint32_t n = static_cast<uint32_t>(tls_move_buffer.size());
    if (n == 0) {
        node.terminal = 1;
        return;
    }
    const uint32_t first = arena.reserve_children(n);
    UctNode &parent = arena[node_idx];
    parent.first_child_idx = first;
    parent.n_children = static_cast<uint16_t>(n);
    const uint16_t child_ply = static_cast<uint16_t>(parent.state.ply_count + 1);
    for (uint32_t i = 0; i < n; ++i) {
        UctNode &child = arena[first + i];
        child.state.b = std::move(tls_move_buffer[i]);
        child.state.ply_count = child_ply;
        child.parent_idx = node_idx;
        child.first_child_idx = kNoIndex;
        child.n_children = 0;
        child.expanded = 0;
        child.terminal = child.state.is_terminal(max_plies) ? 1 : 0;
        child.visit_count = 0;
        child.q_sum = 0.0;
    }
}

// Functional-style UCB select: returns a SelectOutcome variant rather
// than an index sentinel. Empty children produce NoChild.
[[gnu::hot]] static SelectOutcome select_best_ucb(const Arena &arena, uint32_t parent_idx, double c) noexcept {
    const UctNode &parent = arena[parent_idx];
    const uint32_t first = parent.first_child_idx;
    const uint16_t n = parent.n_children;
    if (n == 0) return SelectOutcome{NoChild{}};
    const double parent_visits = static_cast<double>(parent.visit_count);
    const double log_parent = std::log(parent_visits > 0.0 ? parent_visits : 1.0);
    double best_score = -1.0e300;
    uint32_t best_idx = first;
    for (uint16_t i = 0; i < n; ++i) {
        __builtin_prefetch(&arena[first + i], 0, 1);
    }
    for (uint16_t i = 0; i < n; ++i) {
        const UctNode &child = arena[first + i];
        double score;
        if (child.visit_count == 0) [[unlikely]] {
            score = 1.0e100 - static_cast<double>(i);
        } else {
            const double mean = -(child.q_sum / static_cast<double>(child.visit_count));
            const double exploration = c * std::sqrt(log_parent / static_cast<double>(child.visit_count));
            score = mean + exploration;
        }
        if (score > best_score) {
            best_score = score;
            best_idx = first + i;
        }
    }
    return SelectOutcome{ChildIdx{best_idx}};
}

// See cpp-imperative/engine/search.cpp::rollout for the Sprint 5.3
// scratch-board character notes; (iii) shares the same shape because
// (ii)/(iii) memory layout is byte-comparable per Sprint 6.1's
// "style isolation, not memory representation" rule.
[[gnu::hot]] static double rollout(const Arena &arena, uint32_t node_idx, uint16_t max_plies, RngBackend &rng) {
    const UctNode &node = arena[node_idx];
    State current = node.state;
    while (!current.is_terminal(max_plies)) {
        tls_move_buffer.clear();
        current.b.get_legal_moves(tls_move_buffer);
        const size_t n = tls_move_buffer.size();
        if (n == 0) break;
        const uint64_t pick = rng.bounded(static_cast<uint64_t>(n));
        current.b = std::move(tls_move_buffer[pick]);
        ++current.ply_count;
    }
    return current.terminal_eval();
}

[[gnu::hot]] static void backprop(Arena &arena, uint32_t leaf_idx, double leaf_value) noexcept {
    uint32_t idx = leaf_idx;
    double value = leaf_value;
    while (idx != kNoIndex) {
        UctNode &node = arena[idx];
        ++node.visit_count;
        node.q_sum += value;
        value = -value;
        idx = node.parent_idx;
    }
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
    SearchOutput out;
    if (root_state.is_terminal(max_plies)) {
        out.ok = false;
        return out;
    }
    Arena arena(static_cast<uint32_t>(sims) + 256);
    const uint32_t root_idx = arena.emplace(State{root_state}, kNoIndex);
    RngBackend rng(rng_kind, seed);
    expand(arena, root_idx, max_plies);
    if (arena[root_idx].terminal || arena[root_idx].n_children == 0) [[unlikely]] {
        out.ok = false;
        return out;
    }
    // Sprint 6.1 functional-style descent: each iteration computes a
    // `DescentStep` variant (Descend → keep walking; Expand → grow
    // the tree and re-evaluate; Leaf → rollout from `idx`). The
    // imperative cohort's equivalent uses a fall-through `while
    // (true)` with `break`/`continue`; this `std::visit` lowering is
    // the same machine code under -O3 (LLVM/GCC fuses the variant
    // switch into a jump table) but the source expresses descent as
    // a sequence of typed transitions.
    auto descent_step =
        [&arena, max_plies, exploration_c](uint32_t idx) -> DescentStep {
        UctNode &node = arena[idx];
        if (node.terminal) [[unlikely]] return DescentStep{StepLeaf{idx}};
        if (!node.expanded) return DescentStep{StepExpand{idx}};
        const UctNode &n_ref = arena[idx];
        for (uint16_t i = 0; i < n_ref.n_children; ++i) {
            if (arena[n_ref.first_child_idx + i].visit_count == 0) {
                return DescentStep{StepLeaf{n_ref.first_child_idx + i}};
            }
        }
        SelectOutcome outcome = select_best_ucb(arena, idx, exploration_c);
        if (std::holds_alternative<NoChild>(outcome)) {
            return DescentStep{StepLeaf{idx}};
        }
        return DescentStep{StepDescend{std::get<ChildIdx>(outcome).value}};
    };

    for (uint32_t s = 0; s < sims; ++s) {
        uint32_t idx = root_idx;
        uint32_t leaf_idx = idx;
        bool reached_leaf = false;
        while (!reached_leaf) {
            DescentStep step = descent_step(idx);
            std::visit(
                [&](auto &&payload) {
                    using T = std::decay_t<decltype(payload)>;
                    if constexpr (std::is_same_v<T, StepDescend>) {
                        idx = payload.to_idx;
                    } else if constexpr (std::is_same_v<T, StepExpand>) {
                        expand(arena, payload.at_idx, max_plies);
                        if (arena[payload.at_idx].terminal ||
                            arena[payload.at_idx].n_children == 0) {
                            leaf_idx = payload.at_idx;
                            reached_leaf = true;
                        }
                    } else if constexpr (std::is_same_v<T, StepLeaf>) {
                        leaf_idx = payload.idx;
                        reached_leaf = true;
                    }
                },
                step);
        }
        const double value = rollout(arena, leaf_idx, max_plies, rng);
        backprop(arena, leaf_idx, value);
    }
    const UctNode &root = arena[root_idx];
    out.visits.reserve(root.n_children);
    uint32_t best_visits = 0;
    uint32_t best_child = root.first_child_idx;
    for (uint16_t i = 0; i < root.n_children; ++i) {
        const UctNode &child = arena[root.first_child_idx + i];
        out.visits.emplace_back(decode_action_id(child.state.b), child.visit_count);
        if (child.visit_count > best_visits) {
            best_visits = child.visit_count;
            best_child = root.first_child_idx + i;
        }
    }
    std::sort(out.visits.begin(), out.visits.end(),
              [](const auto &a, const auto &b) { return a.first < b.first; });
    {
        const UctNode &chosen = arena[best_child];
        out.chosen_action_id = decode_action_id(chosen.state.b);
        out.chosen_equity = chosen.visit_count == 0
            ? std::numeric_limits<double>::quiet_NaN()
            : -(chosen.q_sum / static_cast<double>(chosen.visit_count));
    }
    out.ok = true;
    return out;
}

}  // namespace mcts_functional
