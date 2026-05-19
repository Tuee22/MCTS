#include "search.hpp"

#include "arena.hpp"
#include "board.h"
#include "state.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace mcts_functional {
namespace {

thread_local std::vector<corridors::board> tls_move_buffer;

[[gnu::hot]] static bool parse_u8(const std::string &text, size_t first, size_t last, int &out) noexcept {
    if (first >= last) return false;
    int value = 0;
    for (size_t i = first; i < last; ++i) {
        const char c = text[i];
        if (c < '0' || c > '9') return false;
        value = value * 10 + (c - '0');
    }
    out = value;
    return true;
}

[[gnu::hot]] static uint8_t decode_action_id(const corridors::board &b) noexcept {
    const std::string action = b.get_action_text(false);
    if (action.size() < 5) return 0;
    const char kind = action[0];
    const size_t open = action.find('(');
    const size_t comma = action.find(',');
    const size_t close = action.find(')');
    if (open == std::string::npos || comma == std::string::npos || close == std::string::npos) {
        return 0;
    }
    int x = 0;
    int y = 0;
    if (!parse_u8(action, open + 1, comma, x) || !parse_u8(action, comma + 1, close, y)) {
        return 0;
    }
    if (kind == '*') return static_cast<uint8_t>(y * 9 + x);
    if (kind == 'H') return static_cast<uint8_t>(81 + y * 8 + x);
    if (kind == 'V') return static_cast<uint8_t>(145 + y * 8 + x);
    return 0;
}

[[gnu::hot, gnu::always_inline]] static inline uint8_t flip_action_id(uint8_t aid) noexcept {
    if (aid <= 80) return static_cast<uint8_t>(80 - aid);
    if (aid <= 144) return static_cast<uint8_t>(225 - aid);
    if (aid <= 208) return static_cast<uint8_t>(353 - static_cast<int>(aid));
    return aid;
}

[[gnu::hot, gnu::always_inline]] static inline uint8_t canonical_action_id(
    const State &parent,
    const corridors::board &child) noexcept
{
    const uint8_t raw = decode_action_id(child);
    return (parent.ply_count % 2 == 0) ? flip_action_id(raw) : raw;
}

[[gnu::hot, gnu::always_inline]] static inline uint64_t splitmix64(uint64_t input) noexcept {
    const uint64_t z1 = input + 0x9e3779b97f4a7c15ULL;
    const uint64_t z2 = (z1 ^ (z1 >> 30)) * 0xbf58476d1ce4e5b9ULL;
    const uint64_t z3 = (z2 ^ (z2 >> 27)) * 0x94d049bb133111ebULL;
    return z3 ^ (z3 >> 31);
}

[[gnu::hot, gnu::always_inline]] static inline uint64_t mix(uint64_t seed, uint64_t index) noexcept {
    return splitmix64(seed + 0x9e3779b97f4a7c15ULL * (index + 1));
}

[[gnu::hot]] static void canonicalize_moves(const State &state, std::vector<corridors::board> &moves) {
    std::sort(
        moves.begin(),
        moves.end(),
        [&state](const corridors::board &a, const corridors::board &b) {
            return canonical_action_id(state, a) < canonical_action_id(state, b);
        });

    size_t wall_count = 0;
    std::vector<corridors::board> filtered;
    filtered.reserve(moves.size());
    for (auto &move : moves) {
        const uint8_t aid = canonical_action_id(state, move);
        if (aid <= 80) {
            filtered.emplace_back(std::move(move));
        } else if (wall_count < 12) {
            filtered.emplace_back(std::move(move));
            ++wall_count;
        }
    }
    moves = std::move(filtered);
}

[[gnu::hot]] static void legal_moves_for_state(const State &state, std::vector<corridors::board> &moves) {
    moves.clear();
    state.b.get_legal_moves(moves);
    canonicalize_moves(state, moves);
}

[[gnu::hot]] static bool terminal_outcome(const State &state, uint16_t max_plies, double &outcome) noexcept {
    const bool even_ply = (state.ply_count % 2) == 0;
    if (state.b.hero_wins()) {
        outcome = even_ply ? 1.0 : -1.0;
        return true;
    }
    if (state.b.villain_wins()) {
        outcome = even_ply ? -1.0 : 1.0;
        return true;
    }
    if (state.ply_count >= max_plies) {
        outcome = 0.0;
        return true;
    }
    return false;
}

[[gnu::hot]] static void expand(Arena &arena, uint32_t node_idx, uint16_t max_plies) {
    UctNode &node = arena[node_idx];
    if (node.expanded) return;
    node.expanded = 1;
    double outcome = 0.0;
    if (terminal_outcome(node.state, max_plies, outcome)) {
        node.terminal = 1;
        return;
    }

    legal_moves_for_state(node.state, tls_move_buffer);
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
        child.terminal = terminal_outcome(child.state, max_plies, outcome) ? 1 : 0;
        child.visit_count = 0;
        child.q_sum = 0.0;
    }
}

[[gnu::hot]] static uint32_t select_best_ucb(const Arena &arena, uint32_t parent_idx, double c) noexcept {
    const UctNode &parent = arena[parent_idx];
    const uint32_t first = parent.first_child_idx;
    const uint16_t n = parent.n_children;
    if (n == 0) return parent_idx;
    const double parent_visits = static_cast<double>(parent.visit_count + 1);
    const double log_parent = std::log(parent_visits > 0.0 ? parent_visits : 1.0);
    double best_score = -std::numeric_limits<double>::infinity();
    uint32_t best_idx = first;
    for (uint16_t i = 0; i < n; ++i) {
        __builtin_prefetch(&arena[first + i], 0, 1);
    }
    for (uint16_t i = 0; i < n; ++i) {
        const UctNode &child = arena[first + i];
        const double score =
            child.visit_count == 0
                ? 1.0e30
                : (child.q_sum / static_cast<double>(child.visit_count))
                    + c * std::sqrt(log_parent / static_cast<double>(child.visit_count));
        if (score > best_score) {
            best_score = score;
            best_idx = first + i;
        }
    }
    return best_idx;
}

[[gnu::hot]] static double rollout(const State &start, uint64_t seed, uint16_t max_plies) {
    State current = start;
    uint64_t current_seed = seed;
    for (uint16_t step = 0; step < max_plies; ++step) {
        double outcome = 0.0;
        if (terminal_outcome(current, max_plies, outcome)) return outcome;
        legal_moves_for_state(current, tls_move_buffer);
        const size_t n = tls_move_buffer.size();
        if (n == 0) return 0.0;
        const int64_t signed_draw = static_cast<int64_t>(current_seed ^ static_cast<uint64_t>(step));
        int64_t pick_signed = signed_draw % static_cast<int64_t>(n);
        if (pick_signed < 0) pick_signed += static_cast<int64_t>(n);
        const size_t pick = static_cast<size_t>(pick_signed);
        current.b = std::move(tls_move_buffer[pick]);
        current.ply_count = static_cast<uint16_t>(current.ply_count + 1);
        current_seed = mix(current_seed, step);
    }
    return 0.0;
}

[[gnu::hot, gnu::always_inline]] static inline void add_value(Arena &arena, uint32_t node_idx, double value) noexcept {
    UctNode &node = arena[node_idx];
    ++node.visit_count;
    node.q_sum += value;
}

[[gnu::hot]] static double descend(Arena &arena, uint32_t node_idx, uint64_t seed, uint16_t max_plies, double c) {
    double outcome = 0.0;
    if (terminal_outcome(arena[node_idx].state, max_plies, outcome)) {
        add_value(arena, node_idx, outcome);
        return outcome;
    }

    const uint32_t visits = arena[node_idx].visit_count;
    if (visits == 0) {
        outcome = rollout(arena[node_idx].state, seed, max_plies);
        add_value(arena, node_idx, outcome);
        return outcome;
    }

    if (!arena[node_idx].expanded) {
        expand(arena, node_idx, max_plies);
    }
    const UctNode &node = arena[node_idx];
    if (node.terminal || node.n_children == 0) {
        ++arena[node_idx].visit_count;
        return 0.0;
    }

    const uint32_t chosen = select_best_ucb(arena, node_idx, c);
    const uint32_t child_offset = chosen - arena[node_idx].first_child_idx;
    const uint64_t child_seed = mix(seed, static_cast<uint64_t>(child_offset) + 1);
    outcome = descend(arena, chosen, child_seed, max_plies, c);
    add_value(arena, node_idx, outcome);
    return outcome;
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
    double outcome = 0.0;
    if (root_state.b.hero_wins() || root_state.b.villain_wins()) {
        out.ok = false;
        return out;
    }
    if (root_state.ply_count >= max_plies) {
        legal_moves_for_state(root_state, tls_move_buffer);
        if (tls_move_buffer.empty()) {
            out.ok = false;
            return out;
        }
        out.visits.reserve(tls_move_buffer.size());
        for (const auto &move : tls_move_buffer) {
            out.visits.emplace_back(decode_action_id(move), 0);
        }
        out.chosen_action_id = decode_action_id(tls_move_buffer.front());
        out.chosen_equity = 0.0;
        std::sort(out.visits.begin(), out.visits.end(),
                  [](const auto &a, const auto &b) { return a.first < b.first; });
        out.ok = true;
        return out;
    }

    const uint32_t reserve_nodes = std::max<uint32_t>(32, 1 + 16 + sims * 16);
    Arena arena(reserve_nodes);
    const uint32_t root_idx = arena.emplace(State{root_state}, kNoIndex);
    expand(arena, root_idx, max_plies);
    if (arena[root_idx].terminal || arena[root_idx].n_children == 0) {
        out.ok = false;
        return out;
    }
    arena[root_idx].visit_count = 1;

    uint64_t sim_seed = seed;
    for (uint32_t i = 0; i < sims; ++i) {
        sim_seed = mix(sim_seed, static_cast<uint64_t>(i));
        (void)descend(arena, root_idx, sim_seed, max_plies, exploration_c);
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

    const UctNode &chosen = arena[best_child];
    out.chosen_action_id = decode_action_id(chosen.state.b);
    out.chosen_equity =
        chosen.visit_count == 0
            ? std::numeric_limits<double>::quiet_NaN()
            : chosen.q_sum / static_cast<double>(chosen.visit_count);
    out.ok = true;
    return out;
}

}  // namespace mcts_functional
