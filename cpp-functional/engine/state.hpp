// Functional-style engine state: wraps Corridors `board` with a
// `Word16` ply counter so the doctrine ply-cap terminal semantic
// applies (matches backend (ii)). The data layout is identical to
// (ii); only the API uses functional-style return types like
// `std::optional<State>` for legal-move attempts.

#pragma once

#include "board.h"

#include <cstdint>
#include <optional>

namespace mcts_functional {

struct State {
    corridors::board b;
    uint16_t ply_count = 0;

    [[gnu::hot, gnu::always_inline]] inline bool is_terminal(uint16_t max_plies) const noexcept {
        return b.hero_wins() || b.villain_wins() || ply_count >= max_plies;
    }

    [[gnu::hot, gnu::always_inline]] inline double terminal_eval() const noexcept {
        if (b.hero_wins()) return 1.0;
        if (b.villain_wins()) return -1.0;
        return 0.0;
    }
};

// Functional-style move attempt: returns std::optional<State> rather
// than mutating in place. Internally the search lowers to in-place
// mutation; this is the API-shape difference between (ii) and (iii).
[[gnu::hot]] inline std::optional<State> try_advance(const State &current, corridors::board &&moved) noexcept {
    State next{std::move(moved), static_cast<uint16_t>(current.ply_count + 1)};
    return std::optional<State>{std::move(next)};
}

}  // namespace mcts_functional
