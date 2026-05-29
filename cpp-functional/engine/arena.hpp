// Action-only flat MCTS arena per Sprint 6.9. Mirrors backend (ii)
// `cpp-imperative/engine/arena.hpp`:
//   * flat `std::vector<UctNode>` indexed by `u32`
//   * each parent records `first_child_idx : u32` and `n_children : u16`
//   * nodes store only the parent action and hot visit/value fields;
//     `State` is carried on the descent stack and materialized only
//     for the selected child path
// The functional-core boundary is preserved at the API/data-flow layer
// (`std::optional<State>` returns from `try_advance`, `std::variant`
// descent step modeling in `search.hpp`); the underlying memory layout
// intentionally matches (ii) so `(ii)` vs `(iii)` isolates style as the
// single variable.

#pragma once

#include "state.hpp"

#include <cstdint>
#include <limits>
#include <vector>

namespace mcts_functional {

inline constexpr uint32_t kNoIndex = std::numeric_limits<uint32_t>::max();

// Stable cache-line constant; Sprint 6.9 keeps it documented but the
// (iii) hot path is single-threaded, so no `alignas(kCacheLine)` is
// forced on `UctNode`. Mirrors Sprint 5.8 backend (ii) tightening.
inline constexpr size_t kCacheLine = 64;

struct UctNode {
    uint32_t parent_idx = kNoIndex;
    uint32_t first_child_idx = kNoIndex;
    uint32_t visit_count = 0;
    double   q_sum = 0.0;
    uint16_t n_children = 0;
    uint8_t  action_id = kNoAction;  // absolute action from parent; sentinel for root
    uint8_t  expanded = 0;
    uint8_t  terminal = 0;
};

class Arena {
public:
    explicit Arena(uint32_t reserve_nodes) { nodes_.reserve(reserve_nodes); }

    [[gnu::always_inline]] inline UctNode &operator[](uint32_t idx) noexcept { return nodes_[idx]; }
    [[gnu::always_inline]] inline const UctNode &operator[](uint32_t idx) const noexcept { return nodes_[idx]; }

    [[gnu::always_inline]] inline uint32_t size() const noexcept {
        return static_cast<uint32_t>(nodes_.size());
    }

    [[gnu::hot]] uint32_t emplace(uint8_t action_id, uint32_t parent_idx) {
        nodes_.emplace_back();
        UctNode &node = nodes_.back();
        node.action_id = action_id;
        node.parent_idx = parent_idx;
        return static_cast<uint32_t>(nodes_.size() - 1);
    }

    [[gnu::hot]] uint32_t reserve_children(uint32_t count) {
        const uint32_t start = static_cast<uint32_t>(nodes_.size());
        nodes_.resize(nodes_.size() + count);
        return start;
    }

    void clear() noexcept { nodes_.clear(); }

private:
    std::vector<UctNode> nodes_;
};

}  // namespace mcts_functional
