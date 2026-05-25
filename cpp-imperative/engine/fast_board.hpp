// Compact Corridors board for backend (ii). The public C ABI keeps the
// legacy post-move flipped action-id convention, but the hot search path
// stores walls as 8x8 bitfields and emits capped legal moves directly.

#pragma once

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>

namespace mcts_imperative {

inline constexpr uint8_t kBoardSize = 9;
inline constexpr uint8_t kStartingWalls = 10;

struct FastBoard {
    uint8_t hero_x = 4;
    uint8_t hero_y = 0;
    uint8_t villain_x = 4;
    uint8_t villain_y = kBoardSize - 1;
    uint8_t hero_walls_remaining = kStartingWalls;
    uint8_t villain_walls_remaining = kStartingWalls;
    uint64_t walls_h = 0;
    uint64_t walls_v = 0;
    uint8_t last_action = 255;

    [[gnu::always_inline]] inline bool hero_wins() const noexcept {
        return hero_y == kBoardSize - 1;
    }

    [[gnu::always_inline]] inline bool villain_wins() const noexcept {
        return villain_y == 0;
    }

    [[gnu::always_inline]] static inline uint8_t flip_action_id(uint8_t action_id) noexcept {
        if (action_id <= 80) return static_cast<uint8_t>(80 - action_id);
        if (action_id <= 144) return static_cast<uint8_t>(225 - action_id);
        if (action_id <= 208) return static_cast<uint8_t>(353 - static_cast<int>(action_id));
        return action_id;
    }

    [[gnu::always_inline]] inline uint8_t get_action_id(bool flip) const noexcept {
        if (last_action == 255) return last_action;
        return flip ? flip_action_id(last_action) : last_action;
    }

    template <typename Output>
    [[gnu::hot]] void get_capped_legal_moves(Output &output, uint16_t ply_count) const {
        if (hero_wins() || villain_wins()) return;

        std::array<uint8_t, 4> pawn_actions{};
        size_t pawn_count = 0;
        append_pawn_actions(pawn_actions, pawn_count);
        std::sort(
            pawn_actions.begin(),
            pawn_actions.begin() + static_cast<std::ptrdiff_t>(pawn_count),
            [ply_count](uint8_t a, uint8_t b) {
                const uint8_t key_a = (ply_count % 2 == 0) ? a : flip_action_id(a);
                const uint8_t key_b = (ply_count % 2 == 0) ? b : flip_action_id(b);
                return key_a < key_b;
            });
        for (size_t i = 0; i < pawn_count; ++i) {
            output.emplace_back(child_after_action(pawn_actions[i]));
        }

        if (hero_walls_remaining == 0) return;

        size_t wall_count = 0;
        for (uint16_t canonical = 81; canonical <= 208 && wall_count < 12; ++canonical) {
            const uint8_t action_id =
                (ply_count % 2 == 0)
                    ? static_cast<uint8_t>(canonical)
                    : flip_action_id(static_cast<uint8_t>(canonical));
            if (wall_action_exists(action_id) || !wall_action_legal(action_id)) {
                continue;
            }
            output.emplace_back(child_after_action(action_id));
            ++wall_count;
        }
    }

private:
    [[gnu::always_inline]] static inline uint64_t wall_bit(uint8_t x, uint8_t y) noexcept {
        return 1ULL << static_cast<uint8_t>(y * 8 + x);
    }

    [[gnu::always_inline]] static inline bool wall_test(uint64_t bits, uint8_t x, uint8_t y) noexcept {
        if (x > 7 || y > 7) return false;
        return (bits & wall_bit(x, y)) != 0;
    }

    [[gnu::always_inline]] static inline uint64_t reverse_bits64(uint64_t x) noexcept {
        x = ((x & 0x5555555555555555ULL) << 1) | ((x >> 1) & 0x5555555555555555ULL);
        x = ((x & 0x3333333333333333ULL) << 2) | ((x >> 2) & 0x3333333333333333ULL);
        x = ((x & 0x0f0f0f0f0f0f0f0fULL) << 4) | ((x >> 4) & 0x0f0f0f0f0f0f0f0fULL);
        x = ((x & 0x00ff00ff00ff00ffULL) << 8) | ((x >> 8) & 0x00ff00ff00ff00ffULL);
        x = ((x & 0x0000ffff0000ffffULL) << 16) | ((x >> 16) & 0x0000ffff0000ffffULL);
        return (x << 32) | (x >> 32);
    }

    [[gnu::always_inline]] inline FastBoard flipped() const noexcept {
        FastBoard out;
        out.hero_x = static_cast<uint8_t>(kBoardSize - 1 - villain_x);
        out.hero_y = static_cast<uint8_t>(kBoardSize - 1 - villain_y);
        out.villain_x = static_cast<uint8_t>(kBoardSize - 1 - hero_x);
        out.villain_y = static_cast<uint8_t>(kBoardSize - 1 - hero_y);
        out.hero_walls_remaining = villain_walls_remaining;
        out.villain_walls_remaining = hero_walls_remaining;
        out.walls_h = reverse_bits64(walls_h);
        out.walls_v = reverse_bits64(walls_v);
        out.last_action = last_action == 255 ? 255 : flip_action_id(last_action);
        return out;
    }

    [[gnu::always_inline]] inline FastBoard child_after_action(uint8_t action_id) const noexcept {
        FastBoard child = *this;
        child.apply_action_unchecked(action_id);
        return child.flipped();
    }

    [[gnu::always_inline]] inline void apply_action_unchecked(uint8_t action_id) noexcept {
        if (action_id <= 80) {
            hero_x = static_cast<uint8_t>(action_id % 9);
            hero_y = static_cast<uint8_t>(action_id / 9);
        } else if (action_id <= 144) {
            const uint8_t n = static_cast<uint8_t>(action_id - 81);
            walls_h |= wall_bit(static_cast<uint8_t>(n % 8), static_cast<uint8_t>(n / 8));
            if (hero_walls_remaining > 0) --hero_walls_remaining;
        } else if (action_id <= 208) {
            const uint8_t n = static_cast<uint8_t>(action_id - 145);
            walls_v |= wall_bit(static_cast<uint8_t>(n % 8), static_cast<uint8_t>(n / 8));
            if (hero_walls_remaining > 0) --hero_walls_remaining;
        }
        last_action = action_id;
    }

    [[gnu::hot]] inline void append_pawn_actions(std::array<uint8_t, 4> &out, size_t &count) const noexcept {
        constexpr std::array<int8_t, 8> directions{0, 1, 1, 0, -1, 0, 0, -1};
        for (size_t i = 0; i < 4; ++i) {
            const int8_t nx_i = static_cast<int8_t>(hero_x) + directions[2 * i];
            const int8_t ny_i = static_cast<int8_t>(hero_y) + directions[2 * i + 1];
            if (nx_i < 0 || ny_i < 0 || nx_i >= kBoardSize || ny_i >= kBoardSize) continue;
            const uint8_t nx = static_cast<uint8_t>(nx_i);
            const uint8_t ny = static_cast<uint8_t>(ny_i);
            if (nx == villain_x && ny == villain_y) continue;
            if (edge_blocked(hero_x, hero_y, nx, ny)) continue;
            out[count++] = static_cast<uint8_t>(ny * 9 + nx);
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

    [[gnu::always_inline]] inline bool wall_action_legal(uint8_t action_id) const noexcept {
        FastBoard trial = *this;
        if (action_id <= 144) {
            const uint8_t n = static_cast<uint8_t>(action_id - 81);
            trial.walls_h |= wall_bit(static_cast<uint8_t>(n % 8), static_cast<uint8_t>(n / 8));
        } else {
            const uint8_t n = static_cast<uint8_t>(action_id - 145);
            trial.walls_v |= wall_bit(static_cast<uint8_t>(n % 8), static_cast<uint8_t>(n / 8));
        }
        return trial.path_exists(true) && trial.path_exists(false);
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

    [[gnu::hot]] inline bool path_exists(bool hero_side) const noexcept {
        const uint8_t start_x = hero_side ? hero_x : villain_x;
        const uint8_t start_y = hero_side ? hero_y : villain_y;
        const uint8_t goal_y = hero_side ? static_cast<uint8_t>(kBoardSize - 1) : 0;
        if (start_y == goal_y) return true;

        unsigned __int128 up_blocked = 0;
        unsigned __int128 down_blocked = 0;
        uint64_t h = walls_h;
        while (h != 0) {
            const uint8_t idx = static_cast<uint8_t>(__builtin_ctzll(h));
            h &= h - 1;
            const uint8_t x = static_cast<uint8_t>(idx % 8);
            const uint8_t y = static_cast<uint8_t>(idx / 8);
            up_blocked |= cell_bit(x, y) | cell_bit(static_cast<uint8_t>(x + 1), y);
            down_blocked |= cell_bit(x, static_cast<uint8_t>(y + 1))
                | cell_bit(static_cast<uint8_t>(x + 1), static_cast<uint8_t>(y + 1));
        }

        unsigned __int128 right_blocked = 0;
        unsigned __int128 left_blocked = 0;
        uint64_t v = walls_v;
        while (v != 0) {
            const uint8_t idx = static_cast<uint8_t>(__builtin_ctzll(v));
            v &= v - 1;
            const uint8_t x = static_cast<uint8_t>(idx % 8);
            const uint8_t y = static_cast<uint8_t>(idx / 8);
            right_blocked |= cell_bit(x, y) | cell_bit(x, static_cast<uint8_t>(y + 1));
            left_blocked |= cell_bit(static_cast<uint8_t>(x + 1), y)
                | cell_bit(static_cast<uint8_t>(x + 1), static_cast<uint8_t>(y + 1));
        }

        const unsigned __int128 valid = valid_cells();
        const unsigned __int128 right_sources = right_source_mask();
        const unsigned __int128 left_sources = left_source_mask();
        const unsigned __int128 goal = row_mask(goal_y);

        unsigned __int128 frontier = cell_bit(start_x, start_y);
        unsigned __int128 visited = frontier;
        while (frontier != 0) {
            const unsigned __int128 up = ((frontier & ~up_blocked) << 9) & valid;
            const unsigned __int128 down = (frontier & ~down_blocked) >> 9;
            const unsigned __int128 right = ((frontier & right_sources & ~right_blocked) << 1) & valid;
            const unsigned __int128 left = (frontier & left_sources & ~left_blocked) >> 1;
            const unsigned __int128 next = (up | down | right | left) & ~visited;
            if ((next & goal) != 0) return true;
            visited |= next;
            frontier = next;
        }
        return false;
    }
};

}  // namespace mcts_imperative
