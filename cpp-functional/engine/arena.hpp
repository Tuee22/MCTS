// Arena-allocated MCTS tree shared with backend (ii). Backend (iii)'s
// "functional style" lives at the API + data-flow layer (`std::optional`
// returns, `std::variant` for select outcomes); the underlying memory
// layout intentionally matches (ii) so that the (ii)-vs-(iii)
// comparison isolates style as the single variable.

#pragma once

#include "state.hpp"

#include <cstdint>
#include <limits>
#include <vector>

namespace mcts_functional {

inline constexpr uint32_t kNoIndex = std::numeric_limits<uint32_t>::max();

// Stable cache-line constant; see Sprint 5.1 closure note.
inline constexpr size_t kCacheLine = 64;

struct alignas(kCacheLine) UctNode {
    State state{};
    uint32_t parent_idx = kNoIndex;
    uint32_t first_child_idx = kNoIndex;
    uint16_t n_children = 0;
    uint8_t  expanded = 0;
    uint8_t  terminal = 0;
    uint32_t visit_count = 0;
    double   q_sum = 0.0;
};

class Arena {
public:
    explicit Arena(uint32_t reserve_nodes) { nodes_.reserve(reserve_nodes); }

    [[gnu::always_inline]] inline UctNode &operator[](uint32_t idx) noexcept { return nodes_[idx]; }
    [[gnu::always_inline]] inline const UctNode &operator[](uint32_t idx) const noexcept { return nodes_[idx]; }

    [[gnu::always_inline]] inline uint32_t size() const noexcept {
        return static_cast<uint32_t>(nodes_.size());
    }

    [[gnu::hot]] uint32_t emplace(State &&s, uint32_t parent_idx) {
        nodes_.emplace_back();
        UctNode &node = nodes_.back();
        node.state = std::move(s);
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
