// Arena-allocated MCTS tree per Sprint 5.7's hot-path steelman:
//   * flat `std::vector<UctNode>` instead of `std::shared_ptr<uct_node>`
//   * each parent records `first_child_idx : u32` and `n_children : u16`
//     (no per-node `std::vector`)
//   * nodes store only the action from their parent plus hot visit/value
//     fields. Board state is carried on the descent stack and materialized
//     only for the selected child path.

#pragma once

#include "state.hpp"

#include <cstdint>
#include <limits>
#include <new>
#include <vector>

namespace mcts_imperative {

inline constexpr uint32_t kNoIndex = std::numeric_limits<uint32_t>::max();

// Stable cache-line constant per Sprint 5.1: GCC's
// `-Winterference-size` warns about cross-version drift in
// `std::hardware_destructive_interference_size`, and the steelman
// envelope ships across hosts. 64 bytes matches the dominant
// architecture's L1 cache line.
inline constexpr size_t kCacheLine = 64;

struct alignas(kCacheLine) UctNode {
    uint32_t parent_idx = kNoIndex; // index in arena; kNoIndex for root
    uint32_t first_child_idx = kNoIndex;
    uint32_t visit_count = 0;
    double   q_sum = 0.0;           // sum of backprop'd hero-perspective equities
    uint16_t n_children = 0;
    uint8_t  action_id = kNoAction; // absolute action from parent; sentinel for root
    uint8_t  expanded = 0;          // 0 until select() has expanded children
    uint8_t  terminal = 0;          // 1 when state.is_terminal(max_plies)
};

// Arena owns every UctNode in the current search. The vector is reserved
// up-front to the worst-case node budget (sims + 1) so realloc-during-
// search does not invalidate child indices.
class Arena {
public:
    explicit Arena(uint32_t reserve_nodes) {
        nodes_.reserve(reserve_nodes);
    }

    [[gnu::always_inline]] inline UctNode &operator[](uint32_t idx) noexcept { return nodes_[idx]; }
    [[gnu::always_inline]] inline const UctNode &operator[](uint32_t idx) const noexcept { return nodes_[idx]; }

    [[gnu::always_inline]] inline uint32_t size() const noexcept {
        return static_cast<uint32_t>(nodes_.size());
    }

    // Appends one node and returns its index.
    [[gnu::hot]] uint32_t emplace(uint8_t action_id, uint32_t parent_idx) {
        nodes_.emplace_back();
        UctNode &node = nodes_.back();
        node.action_id = action_id;
        node.parent_idx = parent_idx;
        return static_cast<uint32_t>(nodes_.size() - 1);
    }

    // Reserve a contiguous range of n child nodes and return the start
    // index. Children are default-constructed; the caller fills them.
    [[gnu::hot]] uint32_t reserve_children(uint32_t count) {
        const uint32_t start = static_cast<uint32_t>(nodes_.size());
        nodes_.resize(nodes_.size() + count);
        return start;
    }

    void clear() noexcept { nodes_.clear(); }

private:
    std::vector<UctNode> nodes_;
};

}  // namespace mcts_imperative
