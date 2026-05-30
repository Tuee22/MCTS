// Compact Corridors board for backend (ii). The public C ABI keeps the
// legacy raw action-id convention, but the hot search path stores an
// absolute board with an explicit side-to-move bit and emits capped
// legal action IDs without materializing child boards.

#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace mcts_imperative {

inline constexpr uint8_t kBoardSize = 9;
inline constexpr uint8_t kStartingWalls = 10;
inline constexpr uint8_t kMaxLegalActions = 16;
inline constexpr uint8_t kNoAction = 255;

enum class SideToMove : uint8_t { Hero = 0, Villain = 1 };

struct ActionBuffer {
    std::array<uint8_t, kMaxLegalActions> items{};
    size_t size = 0;

    [[gnu::always_inline]] inline void clear() noexcept { size = 0; }

    [[gnu::always_inline]] inline bool empty() const noexcept { return size == 0; }

    [[gnu::always_inline]] inline void push(uint8_t action_id) noexcept {
        if (size < items.size()) {
            items[size++] = action_id;
        }
    }

    [[gnu::always_inline]] inline uint8_t operator[](size_t idx) const noexcept {
        return items[idx];
    }
};

struct BlockMasks {
    unsigned __int128 up = 0;
    unsigned __int128 down = 0;
    unsigned __int128 right = 0;
    unsigned __int128 left = 0;
};

// Sprint 5.9: `ply_count` collapsed into `FastBoard` so the descent state
// the search materializes is a flat 32 B value, matching backend (iii)
// `cpp-functional/engine/state.hpp::State` and backend (iv) Rust
// `rust/src/board.rs::MctsRustBoard`. The prior `State { FastBoard b;
// uint16_t ply_count; }` wrapper in `state.hpp` is removed; the State→
// FastBoard tax (~40 B padded) is gone from `descend_iterative`'s
// per-simulation copy. Validated via the 2026-05-29 (ii) vs (iii)/(iv)
// reportcard rerun: (iii) and (iv) both hit Q2 ST=2.2 with the flat 32 B
// layout vs (ii)'s 1.9 under the wrapper.
struct FastBoard {
    uint8_t hero_x = 4;
    uint8_t hero_y = 0;
    uint8_t villain_x = 4;
    uint8_t villain_y = kBoardSize - 1;
    uint8_t hero_walls_remaining = kStartingWalls;
    uint8_t villain_walls_remaining = kStartingWalls;
    uint64_t walls_h = 0;
    uint64_t walls_v = 0;
    uint16_t ply_count = 0;
    uint8_t last_action = kNoAction;
    SideToMove side_to_move = SideToMove::Hero;

    [[gnu::always_inline]] inline bool hero_wins() const noexcept {
        return hero_y == kBoardSize - 1;
    }

    [[gnu::always_inline]] inline bool villain_wins() const noexcept {
        return villain_y == 0;
    }

    [[gnu::hot, gnu::always_inline]] inline bool is_terminal(uint16_t max_plies) const noexcept {
        return hero_wins() || villain_wins() || ply_count >= max_plies;
    }

    // Hero-perspective terminal evaluation; ply-cap termination is a draw (0).
    [[gnu::hot, gnu::always_inline]] inline double terminal_eval() const noexcept {
        if (hero_wins()) return 1.0;
        if (villain_wins()) return -1.0;
        return 0.0;
    }

    [[gnu::always_inline]] static inline uint8_t flip_action_id(uint8_t action_id) noexcept {
        if (action_id <= 80) return static_cast<uint8_t>(80 - action_id);
        if (action_id <= 144) return static_cast<uint8_t>(225 - action_id);
        if (action_id <= 208) return static_cast<uint8_t>(353 - static_cast<int>(action_id));
        return action_id;
    }

    [[gnu::always_inline]] inline uint8_t get_action_id(bool flip) const noexcept {
        if (last_action == kNoAction) return last_action;
        return flip ? flip_action_id(last_action) : last_action;
    }

    [[gnu::always_inline]] static inline uint8_t abi_action_from_absolute(
        SideToMove side,
        uint8_t action_id) noexcept {
        return side == SideToMove::Hero ? flip_action_id(action_id) : action_id;
    }

    [[gnu::always_inline]] inline uint8_t abi_action_from_absolute(uint8_t action_id) const noexcept {
        return abi_action_from_absolute(side_to_move, action_id);
    }

    [[gnu::always_inline]] inline uint8_t absolute_action_from_abi(uint8_t action_id) const noexcept {
        return side_to_move == SideToMove::Hero ? flip_action_id(action_id) : action_id;
    }

    [[gnu::hot]] void legal_actions(ActionBuffer &output) const noexcept {
        output.clear();
        if (hero_wins() || villain_wins()) return;

        append_pawn_actions(output);
        if (walls_remaining() == 0) return;

        size_t wall_count = 0;
        const BlockMasks base_masks = block_masks();
        for (uint16_t canonical = 81; canonical <= 208 && wall_count < 12; ++canonical) {
            const uint8_t action_id = static_cast<uint8_t>(canonical);
            if (wall_action_exists(action_id) || !wall_action_legal(action_id, base_masks)) {
                continue;
            }
            output.push(action_id);
            ++wall_count;
        }
    }

    [[gnu::always_inline]] inline void apply_action_unchecked(uint8_t action_id) noexcept {
        if (action_id <= 80) {
            const uint8_t x = static_cast<uint8_t>(action_id % 9);
            const uint8_t y = static_cast<uint8_t>(action_id / 9);
            if (side_to_move == SideToMove::Hero) {
                hero_x = x;
                hero_y = y;
            } else {
                villain_x = x;
                villain_y = y;
            }
        } else if (action_id <= 144) {
            const uint8_t n = static_cast<uint8_t>(action_id - 81);
            walls_h |= wall_bit(static_cast<uint8_t>(n % 8), static_cast<uint8_t>(n / 8));
            decrement_current_walls();
        } else if (action_id <= 208) {
            const uint8_t n = static_cast<uint8_t>(action_id - 145);
            walls_v |= wall_bit(static_cast<uint8_t>(n % 8), static_cast<uint8_t>(n / 8));
            decrement_current_walls();
        }
        last_action = action_id;
        side_to_move = side_to_move == SideToMove::Hero ? SideToMove::Villain : SideToMove::Hero;
        ply_count = static_cast<uint16_t>(ply_count + 1);
    }

private:
    [[gnu::always_inline]] static inline uint64_t wall_bit(uint8_t x, uint8_t y) noexcept {
        return 1ULL << static_cast<uint8_t>(y * 8 + x);
    }

    [[gnu::always_inline]] static inline bool wall_test(uint64_t bits, uint8_t x, uint8_t y) noexcept {
        if (x > 7 || y > 7) return false;
        return (bits & wall_bit(x, y)) != 0;
    }

    [[gnu::always_inline]] inline uint8_t walls_remaining() const noexcept {
        return side_to_move == SideToMove::Hero ? hero_walls_remaining : villain_walls_remaining;
    }

    [[gnu::always_inline]] inline void decrement_current_walls() noexcept {
        uint8_t &remaining =
            side_to_move == SideToMove::Hero ? hero_walls_remaining : villain_walls_remaining;
        if (remaining > 0) --remaining;
    }

    [[gnu::hot]] inline void append_pawn_actions(ActionBuffer &out) const noexcept {
        constexpr std::array<int8_t, 8> directions{0, -1, -1, 0, 1, 0, 0, 1};
        const uint8_t actor_x = side_to_move == SideToMove::Hero ? hero_x : villain_x;
        const uint8_t actor_y = side_to_move == SideToMove::Hero ? hero_y : villain_y;
        const uint8_t occupied_x = side_to_move == SideToMove::Hero ? villain_x : hero_x;
        const uint8_t occupied_y = side_to_move == SideToMove::Hero ? villain_y : hero_y;
        for (size_t i = 0; i < 4; ++i) {
            const int8_t nx_i = static_cast<int8_t>(actor_x) + directions[2 * i];
            const int8_t ny_i = static_cast<int8_t>(actor_y) + directions[2 * i + 1];
            if (nx_i < 0 || ny_i < 0 || nx_i >= kBoardSize || ny_i >= kBoardSize) continue;
            const uint8_t nx = static_cast<uint8_t>(nx_i);
            const uint8_t ny = static_cast<uint8_t>(ny_i);
            if (nx == occupied_x && ny == occupied_y) continue;
            if (edge_blocked(actor_x, actor_y, nx, ny)) continue;
            out.push(static_cast<uint8_t>(ny * 9 + nx));
        }
    }

    [[gnu::always_inline]] inline bool edge_blocked(uint8_t x1, uint8_t y1, uint8_t x2, uint8_t y2) const noexcept {
        if (x1 == x2) {
            const uint8_t y = y1 < y2 ? y1 : y2;
            const bool left = x1 == 0 ? false : wall_test(walls_h, static_cast<uint8_t>(x1 - 1), y);
            const bool right = wall_test(walls_h, x1, y);
            return left || right;
        }
        const uint8_t x = x1 < x2 ? x1 : x2;
        const bool down = y1 == 0 ? false : wall_test(walls_v, x, static_cast<uint8_t>(y1 - 1));
        const bool up = wall_test(walls_v, x, y1);
        return down || up;
    }

    [[gnu::always_inline]] inline bool wall_action_exists(uint8_t action_id) const noexcept {
        if (action_id <= 144) {
            const uint8_t n = static_cast<uint8_t>(action_id - 81);
            return horizontal_wall_conflicts(static_cast<uint8_t>(n % 8), static_cast<uint8_t>(n / 8));
        }
        const uint8_t n = static_cast<uint8_t>(action_id - 145);
        return vertical_wall_conflicts(static_cast<uint8_t>(n % 8), static_cast<uint8_t>(n / 8));
    }

    [[gnu::always_inline]] inline bool horizontal_wall_conflicts(uint8_t x, uint8_t y) const noexcept {
        return wall_test(walls_v, x, y)
            || wall_test(walls_h, x, y)
            || (x > 0 && wall_test(walls_h, static_cast<uint8_t>(x - 1), y))
            || (x < 7 && wall_test(walls_h, static_cast<uint8_t>(x + 1), y));
    }

    [[gnu::always_inline]] inline bool vertical_wall_conflicts(uint8_t x, uint8_t y) const noexcept {
        return wall_test(walls_h, x, y)
            || wall_test(walls_v, x, y)
            || (y > 0 && wall_test(walls_v, x, static_cast<uint8_t>(y - 1)))
            || (y < 7 && wall_test(walls_v, x, static_cast<uint8_t>(y + 1)));
    }

    [[gnu::always_inline]] inline bool wall_action_legal(
        uint8_t action_id,
        const BlockMasks &base_masks) const noexcept {
        const BlockMasks trial_masks = add_wall_to_masks(action_id, base_masks);
        return path_exists_with_masks(true, trial_masks) && path_exists_with_masks(false, trial_masks);
    }

    [[gnu::always_inline]] static constexpr inline unsigned __int128 cell_bit(uint8_t x, uint8_t y) noexcept {
        return static_cast<unsigned __int128>(1) << static_cast<uint8_t>(y * kBoardSize + x);
    }

    [[gnu::always_inline]] static constexpr inline unsigned __int128 valid_cells() noexcept {
        return (static_cast<unsigned __int128>(1) << 81) - 1;
    }

    [[gnu::always_inline]] static constexpr inline unsigned __int128 row_mask(uint8_t y) noexcept {
        return ((static_cast<unsigned __int128>(1) << 9) - 1) << static_cast<uint8_t>(y * kBoardSize);
    }

    [[gnu::always_inline]] static constexpr inline unsigned __int128 right_source_mask() noexcept {
        unsigned __int128 mask = 0;
        for (uint8_t y = 0; y < kBoardSize; ++y) {
            for (uint8_t x = 0; x < kBoardSize - 1; ++x) {
                mask |= cell_bit(x, y);
            }
        }
        return mask;
    }

    [[gnu::always_inline]] static constexpr inline unsigned __int128 left_source_mask() noexcept {
        unsigned __int128 mask = 0;
        for (uint8_t y = 0; y < kBoardSize; ++y) {
            for (uint8_t x = 1; x < kBoardSize; ++x) {
                mask |= cell_bit(x, y);
            }
        }
        return mask;
    }

    [[gnu::hot]] inline BlockMasks block_masks() const noexcept {
        BlockMasks masks{};
        uint64_t h = walls_h;
        while (h != 0) {
            const uint8_t idx = static_cast<uint8_t>(__builtin_ctzll(h));
            h &= h - 1;
            const uint8_t x = static_cast<uint8_t>(idx % 8);
            const uint8_t y = static_cast<uint8_t>(idx / 8);
            masks.up |= cell_bit(x, y) | cell_bit(static_cast<uint8_t>(x + 1), y);
            masks.down |= cell_bit(x, static_cast<uint8_t>(y + 1))
                | cell_bit(static_cast<uint8_t>(x + 1), static_cast<uint8_t>(y + 1));
        }

        uint64_t v = walls_v;
        while (v != 0) {
            const uint8_t idx = static_cast<uint8_t>(__builtin_ctzll(v));
            v &= v - 1;
            const uint8_t x = static_cast<uint8_t>(idx % 8);
            const uint8_t y = static_cast<uint8_t>(idx / 8);
            masks.right |= cell_bit(x, y) | cell_bit(x, static_cast<uint8_t>(y + 1));
            masks.left |= cell_bit(static_cast<uint8_t>(x + 1), y)
                | cell_bit(static_cast<uint8_t>(x + 1), static_cast<uint8_t>(y + 1));
        }
        return masks;
    }

    [[gnu::always_inline]] inline BlockMasks add_wall_to_masks(
        uint8_t action_id,
        BlockMasks masks) const noexcept {
        if (action_id <= 144) {
            const uint8_t n = static_cast<uint8_t>(action_id - 81);
            const uint8_t x = static_cast<uint8_t>(n % 8);
            const uint8_t y = static_cast<uint8_t>(n / 8);
            masks.up |= cell_bit(x, y) | cell_bit(static_cast<uint8_t>(x + 1), y);
            masks.down |= cell_bit(x, static_cast<uint8_t>(y + 1))
                | cell_bit(static_cast<uint8_t>(x + 1), static_cast<uint8_t>(y + 1));
        } else {
            const uint8_t n = static_cast<uint8_t>(action_id - 145);
            const uint8_t x = static_cast<uint8_t>(n % 8);
            const uint8_t y = static_cast<uint8_t>(n / 8);
            masks.right |= cell_bit(x, y) | cell_bit(x, static_cast<uint8_t>(y + 1));
            masks.left |= cell_bit(static_cast<uint8_t>(x + 1), y)
                | cell_bit(static_cast<uint8_t>(x + 1), static_cast<uint8_t>(y + 1));
        }
        return masks;
    }

    // Sprint 5.8: bidirectional bit-parallel BFS. Expands one frontier
    // outward from the pawn cell and another inward from the goal row,
    // returning true as soon as the two visited sets intersect. Walls
    // are bidirectional in Corridors (a wall blocks both directions
    // equally), so the start-side and goal-side expansions use the
    // identical four-direction shift+mask kernel against the same
    // `BlockMasks`. The bool return contract is unchanged versus the
    // prior unidirectional implementation.
    [[gnu::hot]] inline bool path_exists_with_masks(
        bool hero_side,
        const BlockMasks &masks) const noexcept {
        const uint8_t start_x = hero_side ? hero_x : villain_x;
        const uint8_t start_y = hero_side ? hero_y : villain_y;
        const uint8_t goal_y = hero_side ? static_cast<uint8_t>(kBoardSize - 1) : 0;
        if (start_y == goal_y) return true;

        const unsigned __int128 valid = valid_cells();
        const unsigned __int128 right_sources = right_source_mask();
        const unsigned __int128 left_sources = left_source_mask();

        unsigned __int128 start_front = cell_bit(start_x, start_y);
        unsigned __int128 start_visit = start_front;
        unsigned __int128 goal_front = row_mask(goal_y);
        unsigned __int128 goal_visit = goal_front;
        if ((start_front & goal_visit) != 0) return true;

        while (start_front != 0 && goal_front != 0) {
            {
                const unsigned __int128 up    = ((start_front & ~masks.up)                       << 9) & valid;
                const unsigned __int128 down  =  (start_front & ~masks.down)                     >> 9;
                const unsigned __int128 right = ((start_front & right_sources & ~masks.right)    << 1) & valid;
                const unsigned __int128 left  =  (start_front & left_sources  & ~masks.left)     >> 1;
                const unsigned __int128 next  = (up | down | right | left) & ~start_visit;
                if ((next & goal_visit) != 0) return true;
                start_visit |= next;
                start_front  = next;
            }
            {
                const unsigned __int128 up    = ((goal_front & ~masks.up)                        << 9) & valid;
                const unsigned __int128 down  =  (goal_front & ~masks.down)                      >> 9;
                const unsigned __int128 right = ((goal_front & right_sources & ~masks.right)     << 1) & valid;
                const unsigned __int128 left  =  (goal_front & left_sources  & ~masks.left)      >> 1;
                const unsigned __int128 next  = (up | down | right | left) & ~goal_visit;
                if ((next & start_visit) != 0) return true;
                goal_visit |= next;
                goal_front  = next;
            }
        }
        return false;
    }
};

}  // namespace mcts_imperative
