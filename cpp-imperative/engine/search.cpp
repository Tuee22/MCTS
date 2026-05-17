#include "search.hpp"

#include "arena.hpp"
#include "board.h"
#include "state.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

namespace mcts_imperative {
namespace {

// Hot-path thread-local move-list buffer per Sprint 5.1: move
// generators write into this reusable buffer so the inner loop avoids
// allocating a fresh `std::vector<corridors::board>` per node
// expansion. ~40 moves is the typical Corridors legal-move count;
// heap spill is allowed but rare.
thread_local std::vector<corridors::board> tls_move_buffer;

// Hot-path action-id decoder: matches the layout used by the
// `parse_action_id` helper in the C ABI shim
// (`cpp-imperative/c-abi/mcts_cpp_imperative.cc`). Pawn: y*9+x.
// Horizontal wall: 81 + y*8 + x. Vertical wall: 145 + y*8 + x.
[[gnu::hot]] static uint8_t decode_action_id(const corridors::board &b) noexcept {
    // The legacy `board::action` sub-struct holds the chosen action.
    // We re-derive the canonical action id from `get_action_text`
    // rather than reaching into protected state.
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

// Expand `node`'s children in-arena. After expansion `n_children` is
// non-zero (unless the node is terminal, in which case it stays 0 and
// `terminal` is set).
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
    // Re-fetch parent reference because resize may have invalidated it.
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

// UCB1 child selection. The hero-perspective Q is in node.q_sum /
// node.visit_count; we negate from the parent's perspective because
// `get_legal_moves` emits children from the moving side's perspective
// flipped to the next-to-move (legacy semantic).
[[gnu::hot]] static uint32_t select_best_ucb(const Arena &arena, uint32_t parent_idx, double c) noexcept {
    const UctNode &parent = arena[parent_idx];
    const uint32_t first = parent.first_child_idx;
    const uint16_t n = parent.n_children;
    const double parent_visits = static_cast<double>(parent.visit_count);
    const double log_parent = std::log(parent_visits > 0.0 ? parent_visits : 1.0);
    double best_score = -1.0e300;
    uint32_t best_idx = first;
    // Prefetch the child range so the UCB loop hits warm cache.
    for (uint16_t i = 0; i < n; ++i) {
        __builtin_prefetch(&arena[first + i], 0, 1);
    }
    for (uint16_t i = 0; i < n; ++i) {
        const UctNode &child = arena[first + i];
        double score;
        if (child.visit_count == 0) [[unlikely]] {
            score = 1.0e100 - static_cast<double>(i);  // FPU-stable index tie-break
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
    return best_idx;
}

// Random rollout: from `node_idx`, walk to a terminal state taking
// random legal moves.
//
// Sprint 5.3 scratch-board character: the rollout holds a single
// `State current` snapshot (initial copy from `node.state`) and
// mutates it forward through per-ply move-assigns from
// `tls_move_buffer` (a `thread_local std::vector<corridors::board>`
// declared at the top of this TU). Across the whole rollout this is
// O(1) heap allocations (the buffer reuses capacity via `.clear()`)
// and zero descents-needing-undo (the loop walks forward only,
// terminating on `is_terminal`). The "undo" formulation in the
// doctrine bullet for "scratch-board undo" is the descent-and-
// backtrack pattern for search trees; rollouts have no backtrack, so
// the scratch-board character degenerates to "single mutable
// snapshot + move-assign per ply" — which is what this code does.
//
// The per-ply `move-assign` of `corridors::board` is ~120 bytes (3
// `flags::flags<>` bitsets whose `flip()` is a lazy toggle, plus a
// handful of `unsigned short` fields and the `_action` record). BFS
// inside `get_legal_moves` dominates the per-ply cost; further
// improvement on this surface depends on bitboard wavefront BFS in
// `board.cpp::check_local_escapable`, which is tracked separately
// from this row.
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
        // Flip perspective at each parent step (alternating sides).
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
    // Worst-case node budget: each simulation can add up to one new
    // node (the leaf). Plus the root and its children. A generous cap
    // avoids vector realloc invalidating `first_child_idx` mid-search.
    Arena arena(static_cast<uint32_t>(sims) + 256);
    const uint32_t root_idx = arena.emplace(State{root_state}, kNoIndex);
    RngBackend rng(rng_kind, seed);
    expand(arena, root_idx, max_plies);
    if (arena[root_idx].terminal || arena[root_idx].n_children == 0) [[unlikely]] {
        out.ok = false;
        return out;
    }
    for (uint32_t s = 0; s < sims; ++s) {
        uint32_t idx = root_idx;
        // Descend until we hit an unexpanded node.
        while (true) {
            UctNode &node = arena[idx];
            if (node.terminal) [[unlikely]] {
                break;
            }
            if (!node.expanded) {
                expand(arena, idx, max_plies);
                // After expansion, terminal or empty stops descent.
                if (arena[idx].terminal || arena[idx].n_children == 0) break;
            }
            // If a freshly expanded node, pick the first unvisited
            // child to mirror MCTS's "expand one node per sim"
            // convention; otherwise UCB-select.
            uint32_t chosen;
            const UctNode &n_ref = arena[idx];
            // Look for an unvisited child first.
            chosen = n_ref.first_child_idx;
            bool found_unvisited = false;
            for (uint16_t i = 0; i < n_ref.n_children; ++i) {
                if (arena[n_ref.first_child_idx + i].visit_count == 0) {
                    chosen = n_ref.first_child_idx + i;
                    found_unvisited = true;
                    break;
                }
            }
            if (!found_unvisited) {
                chosen = select_best_ucb(arena, idx, exploration_c);
            } else {
                // Standard MCTS expansion: stop descent at this leaf.
                idx = chosen;
                break;
            }
            idx = chosen;
        }
        // Evaluate (rollout) and backprop.
        const double value = rollout(arena, idx, max_plies, rng);
        backprop(arena, idx, value);
    }
    // Emit the sorted (action_id, visits) vector for the root's
    // children and identify the chosen action.
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

}  // namespace mcts_imperative
