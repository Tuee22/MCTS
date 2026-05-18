#pragma once
#include <vector>
#include <string>
#include "flags.hpp"
#include "mcts.hpp"

#define BOARD_SIZE 9
#define STARTING_WALLS 10

namespace corridors {
    class board
    {
        typedef std::shared_ptr<mcts::uct_node<board>> board_node_ptr;

        public:
            struct action
            {
                action() noexcept;
                void flip();
                bool is_positional; // false means it was a wall placement
                unsigned short token_position;
                bool wall_is_vertical;
                unsigned short wall_middle;
            };

            board() noexcept;
            board(
                const unsigned short _hero_x,
                const unsigned short _hero_y,
                const unsigned short _villain_x,
                const unsigned short _villain_y,
                const unsigned short _hero_walls_remaining,
                const unsigned short _villain_walls_remaining,
                const flags::flags<(BOARD_SIZE-1)*(BOARD_SIZE-1)> & _wall_middles,
                const flags::flags<(BOARD_SIZE-1)*BOARD_SIZE> & _horizontal_walls,
                const flags::flags<(BOARD_SIZE-1)*BOARD_SIZE> & _vertical_walls
            ) noexcept;
            board(const board & source) noexcept;
            board(const board & source, bool flip) noexcept;
            virtual ~board() noexcept;
            board& operator=(const board & source) noexcept;
            bool operator==(const board & source) const noexcept;

            // moving enabled (must use noexcept to get stl:: containers to use them!)
            board(board&& source) noexcept = default;
            board& operator=(board&& source) noexcept = default;

            template <typename SOMETHING_EMPLACABLE>
            void get_legal_moves(SOMETHING_EMPLACABLE & output) const;
            void eval(const std::vector<board_node_ptr> & children, double & eval_Q, std::vector<double> & eval_probs) const;
            size_t get_hash() const;
            bool is_terminal() const;
            double get_terminal_eval() const; // eval from hero's perspective
            std::string display() const;
            std::string get_action_text(const bool flip) const;
            bool check_non_terminal_eval(double & eval) const;
            int get_non_terminal_rank() const; // net racing difference (positive means villain's advantage)
            bool hero_wins() const;
            bool villain_wins() const;
            bool villain_is_escapable() const;
            unsigned short get_villains_shortest_distance() const;
            unsigned short get_heros_shortest_distance() const;

        protected:
            unsigned short hero_x, hero_y, villain_x, villain_y, hero_walls_remaining, villain_walls_remaining;

            // memoized values
            mutable size_t _stored_hash;

            // For all wall positions, indices start in the lower-left corner (from hero's perspective)
            // and move right, then up one row then right again, etc, ending in the upper right corner.
            // Therefore in order to flip these indices from
            flags::flags<(BOARD_SIZE-1)*(BOARD_SIZE-1)> wall_middles;
            flags::flags<(BOARD_SIZE-1)*BOARD_SIZE> horizontal_walls;
            flags::flags<(BOARD_SIZE-1)*BOARD_SIZE> vertical_walls;
            action _action;

            void Deep_Copy(const board & source, bool flip);
            bool try_positional_move(const unsigned short x, const unsigned short y, const short x_diff, const short y_diff, flags::flags<BOARD_SIZE*BOARD_SIZE> * const contact_flags = NULL) const;
            template <typename SOMETHING_EMPLACABLE>
            bool get_positional_move(const short x_diff, const short y_diff, SOMETHING_EMPLACABLE & output) const;
            bool check_local_escapable(const unsigned short x, const unsigned short y, flags::flags<BOARD_SIZE*BOARD_SIZE> & contact_flags) const;

            // pairs of direction movement (down, left, right, up) for looping
            //constexpr const static short directions[8]={0,-1,-1,0,1,0,0,1};
            // not sure why the compiler hates this as a const member -- look this up later
    };
}

// make custom hash function for board available to std::hash (so we don't have to pass
// anything extra into std::unordered_map)
namespace std {
    template <>
    struct hash<corridors::board>
    {
        size_t operator()(const corridors::board& input) const
        {
            return input.get_hash();
        }
    };
}

template <typename SOMETHING_EMPLACABLE>
void corridors::board::get_legal_moves(SOMETHING_EMPLACABLE & output) const
{
    if (is_terminal()) return;

    // get legal positional moves
    get_positional_move(0, 1, output);
    get_positional_move(1, 0, output);
    get_positional_move(-1, 0, output);
    get_positional_move(0, -1, output);

    if (hero_walls_remaining==0) return;

    // get legal wall placement moves. The cross-backend verification
    // cohort caps wall children at 12 so the C++ engines match the
    // Haskell/Rust tree shape under the first-unvisited-child policy.
    size_t emitted_wall_moves = 0;
    for (size_t i=0;i<(BOARD_SIZE-1)*(BOARD_SIZE-1);++i)
    {
        if (emitted_wall_moves >= 12) break;
        // check each intersection that doesn't already have a wall
        if (!wall_middles.test(i))
        {
            size_t y = i / (BOARD_SIZE-1);
            size_t x = i % (BOARD_SIZE-1);

            // check for a legal horizontal wall placement
            size_t horizontal_wall_index = y * BOARD_SIZE + x;
            if (!horizontal_walls.test(horizontal_wall_index) && !horizontal_walls.test(horizontal_wall_index+1))
            {
                board proposed_position(*this);
                proposed_position.wall_middles.set(i);
                proposed_position.horizontal_walls.set(horizontal_wall_index);
                proposed_position.horizontal_walls.set(horizontal_wall_index+1);
                --proposed_position.hero_walls_remaining;
                proposed_position._action=action();
                proposed_position._action.wall_is_vertical=false;
                proposed_position._action.wall_middle=i;

                // ensure both players are escapable
                if (proposed_position.villain_is_escapable())
                {
                    board proposed_position_flipped(proposed_position,true);
                    if(proposed_position_flipped.villain_is_escapable())
                    {
                        output.emplace_back(std::move(proposed_position_flipped));
                        ++emitted_wall_moves;
                        if (emitted_wall_moves >= 12) break;
                    }
                }
            }

            // check for a legal vertical wall placement
            size_t vertical_wall_index = x * BOARD_SIZE + y;
            if (!vertical_walls.test(vertical_wall_index) && !vertical_walls.test(vertical_wall_index+1))
            {
                board proposed_position(*this);
                proposed_position.wall_middles.set(i);
                proposed_position.vertical_walls.set(vertical_wall_index);
                proposed_position.vertical_walls.set(vertical_wall_index+1);
                --proposed_position.hero_walls_remaining;
                proposed_position._action=action();
                proposed_position._action.wall_is_vertical=true;
                proposed_position._action.wall_middle=i;

                // ensure both players are escapable
                if (proposed_position.villain_is_escapable())
                {
                    board proposed_position_flipped(proposed_position,true);
                    if(proposed_position_flipped.villain_is_escapable())
                    {
                        output.emplace_back(std::move(proposed_position_flipped));
                        ++emitted_wall_moves;
                    }
                }
            }
        }
    }
}

// exactly one of x_diff or y_diff must equal -1 or 1; the other should remain zero
template <typename SOMETHING_EMPLACABLE>
bool corridors::board::get_positional_move(const short x_diff, const short y_diff, SOMETHING_EMPLACABLE & output) const
{
    if (!try_positional_move(hero_x, hero_y, x_diff, y_diff))
        return false;

    // construct the proposed position
    board proposed_position(*this);
    proposed_position.hero_x = (unsigned short)((short)hero_x + x_diff);
    proposed_position.hero_y = (unsigned short)((short)hero_y + y_diff);
    proposed_position._action=action();
    proposed_position._action.is_positional=true;
    proposed_position._action.token_position=proposed_position.hero_y*BOARD_SIZE + proposed_position.hero_x;

    // check whether villain is in this square
    if (proposed_position.hero_x==proposed_position.villain_x
        && proposed_position.hero_y==proposed_position.villain_y)
    {
        // see if it's a legal move to keep going in the same direction
        if (proposed_position.get_positional_move(x_diff, y_diff, output))
            return true;

        // if we reached this point, continuing in the same direction wasn't
        // legal-- so we check orthogonal moves. Note: what we return in this
        // case doesn't really matter, as we'll never handle it-- but we
        // still compute it for consistentcy (return true as long as at least
        // one legal move was found).
        bool move1, move2;
        if (x_diff!=0)
        {
            // horizontal move-- check vertical moves
            move1 = proposed_position.get_positional_move(0, 1, output);
            move2 = proposed_position.get_positional_move(0, -1, output);
        }
        else
        {
            // vertical move-- check horizontal moves
            move1 = proposed_position.get_positional_move(1, 0, output);
            move2 = proposed_position.get_positional_move(-1, 0, output);
        }
        return move1 || move2;
    }
    else
    {
        // it's a legal move!!
        // flip-construct in-place
        output.emplace_back(std::move(board(proposed_position, true)));
        return true;
    }
}




// uncomment to test that hashing is working correctly for containers
//#include <unordered_map>
//std::unordered_map<corridors::board, int> test_hash;
