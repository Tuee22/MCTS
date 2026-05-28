// Imperative engine state: wraps the Corridors `board` with a
// `uint16_t` ply counter so the doctrine's
// `is_terminal ↔ ... || ply_count >= max_plies` semantic (per
// DEVELOPMENT_PLAN/00-overview.md → Hard Constraints item 9) holds at
// the engine level without modifying the verbatim legacy board class.

#pragma once

#include "fast_board.hpp"

#include <cstdint>

namespace mcts_imperative {

struct State {
    FastBoard b;
    uint16_t ply_count = 0;

    [[gnu::hot, gnu::always_inline]] inline bool is_terminal(uint16_t max_plies) const noexcept {
        return b.hero_wins() || b.villain_wins() || ply_count >= max_plies;
    }

    // Hero-perspective terminal evaluation; ply-cap termination is a draw (0).
    [[gnu::hot, gnu::always_inline]] inline double terminal_eval() const noexcept {
        if (b.hero_wins()) return 1.0;
        if (b.villain_wins()) return -1.0;
        return 0.0;  // ply-cap draw
    }

    [[gnu::hot, gnu::always_inline]] inline void apply_action_unchecked(uint8_t action_id) noexcept {
        b.apply_action_unchecked(action_id);
        ply_count = static_cast<uint16_t>(ply_count + 1);
    }
};

}  // namespace mcts_imperative
