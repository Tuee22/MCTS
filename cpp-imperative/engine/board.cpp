#include "board.h"

#include <functional>
#include <string>
#include <algorithm>
#include <limits>

using namespace corridors;

// Hash combine function to replace hash_combine
template <typename T>
inline void hash_combine(std::size_t& seed, const T& v) {
    std::hash<T> hasher;
    seed ^= hasher(v) + 0x9e3779b9 + (seed << 6) + (seed >> 2);
}

// don't use this approach-- it's super slow!!
/*template<std::size_t N>
void reverse_bitset(const std::bitset<N> & input, std::bitset<N> & output)
{
    for (size_t i=0;i<N;++i)
        output[N-1-i] = input[i];
}*/

board::action::action() noexcept
{
    is_positional = false;
    token_position = 0;
    wall_is_vertical = false;
    wall_middle = 0;
}

void board::action::flip()
{
    token_position = BOARD_SIZE*BOARD_SIZE-1-token_position;
    wall_middle = (BOARD_SIZE-1)*(BOARD_SIZE-1)-1-wall_middle;
}

board::board() noexcept
{
    // set game to starting position
    hero_x = BOARD_SIZE / 2;
    hero_y = 0;
    villain_x = BOARD_SIZE / 2;
    villain_y = BOARD_SIZE - 1;
    hero_walls_remaining = STARTING_WALLS;
    villain_walls_remaining = STARTING_WALLS;
    // to ensure the hash gets calculated when called
    _stored_hash = 0;
}

board::board(
    const unsigned short _hero_x,
    const unsigned short _hero_y,
    const unsigned short _villain_x,
    const unsigned short _villain_y,
    const unsigned short _hero_walls_remaining,
    const unsigned short _villain_walls_remaining,
    const flags::flags<(BOARD_SIZE-1)*(BOARD_SIZE-1)> & _wall_middles,
    const flags::flags<(BOARD_SIZE-1)*BOARD_SIZE> & _horizontal_walls,
    const flags::flags<(BOARD_SIZE-1)*BOARD_SIZE> & _vertical_walls
) noexcept
{
    hero_x=_hero_x;
    hero_y=_hero_y;
    villain_x=_villain_x;
    villain_y=_villain_y;
    hero_walls_remaining=_hero_walls_remaining;
    villain_walls_remaining=_villain_walls_remaining;
    wall_middles=_wall_middles;
    horizontal_walls=_horizontal_walls;
    vertical_walls=_vertical_walls;
    // to ensure the hash gets calculated when called
}

board& board::operator=(const board & source) noexcept
{
    if (&source==this)
        return *this;
    Deep_Copy(source, false);
    return *this;
}

bool board::operator==(const board & source) const noexcept
{
    return get_hash() == source.get_hash();
}

board::~board() noexcept
{}

board::board(const board & source) noexcept
{
    if (&source==this)
        return;
    Deep_Copy(source, false);
}

board::board(const board & source, bool flip) noexcept
{
    if (&source==this)
        return;
    Deep_Copy(source, flip);
}

// check that there exists an unobstructed path between
// villain's marker and their destination
bool board::villain_is_escapable() const
{
    flags::flags<BOARD_SIZE*BOARD_SIZE> contact_flags;
    // set villain's present location to true
    contact_flags.set(size_t(villain_y*BOARD_SIZE + villain_x));
    // search outwards recursively, starting from villain's current location
    return check_local_escapable(villain_x, villain_y, contact_flags);
}

bool board::check_local_escapable (
    const unsigned short x,
    const unsigned short y,
    flags::flags<BOARD_SIZE*BOARD_SIZE> & contact_flags) const
{
    // if the first row is reachable, villain is escapable and we're done
    if (y==0) return true;

    // Try down first and up last, as villain will generally be escaping downwards, so we're more likely to find
    // a faster route this way.
    // First term verifies that 1) we can move in that direction legally, and 2) we haven't already marked that square as
    // reachable by villain.
    // Second term then calls this function recursively so we can continue the expansion.
    if (try_positional_move(x, y, 0, -1, &contact_flags) && check_local_escapable(x, y-1, contact_flags)) return true;
    if (try_positional_move(x, y, 1, 0, &contact_flags) && check_local_escapable(x+1, y, contact_flags)) return true;
    if (try_positional_move(x, y, -1, 0, &contact_flags) && check_local_escapable(x-1, y, contact_flags)) return true;
    if (try_positional_move(x, y, 0, 1, &contact_flags) && check_local_escapable(x, y+1, contact_flags)) return true;
    return false;
}

unsigned short board::get_villains_shortest_distance() const
{
    // get a BOARD_SIZE x BOARD_SIZE array where, for each square,
    // we will populate the minimum possible number of moves required
    // to get from villain to the given square.
    // The algorithm starts at villains current square (which we will give a value of zero)
    // and iterates outwards.
    // Values are all initialized to the maximum unsigned short value, which represents infinity.
    // (This ensures that the check shortest_distance[sd_index]>curr_num_moves
    // below is always true so that unexplored squares are always set)
    unsigned short shortest_distance[BOARD_SIZE*BOARD_SIZE];
    for (size_t i=0;i<BOARD_SIZE*BOARD_SIZE;++i)
        shortest_distance[i] = std::numeric_limits<unsigned short>::max();

    // set villain's location to 0
    // (if only finding yourself was that easy in real life)
    shortest_distance[villain_y * BOARD_SIZE + villain_x] = 0;

    // filled_points stores coordinates of squares filled on the last loop
    // iteration. We initialize this to villain's current location
    std::vector<std::pair<unsigned short, unsigned short>> filled_points;
    filled_points.emplace_back(std::make_pair(villain_x, villain_y));

    // pairs of directional movement (down, left, right, up respectively)
    // for looping convenience
    const static short directions[8]={0,-1,-1,0,1,0,0,1};

    // main while-like loop that keeps going until there are no remaining squares to visit
    // (occurs when filled_points is empty). We put it in a for loop
    // for convenience just to get the counter for the cumulative number
    // of moves villain has made
    for (unsigned short cumulative_moves=1;filled_points.size()>0;++cumulative_moves)
    {
        std::vector<std::pair<unsigned short, unsigned short>> next_filled_points;
        std::for_each(
            filled_points.cbegin(),
            filled_points.cend(),
            [&](const std::pair<unsigned short, unsigned short> & pr)
        {
            // iterate once for each direction (down, left, right, up)
            for (size_t i=0;i<4;++i)
            {
                short x_diff = directions[2*i];
                short y_diff = directions[2*i+1];
                // check if a given directional move would be legal (i.e. no walls)
                if (try_positional_move(pr.first, pr.second, x_diff, y_diff))
                {
                    // get the position, and compute its index in the array
                    unsigned short x = (unsigned short)((short)pr.first + x_diff);
                    unsigned short y = (unsigned short)((short)pr.second + y_diff);
                    unsigned short sd_index = y * BOARD_SIZE + x;

                    // check if there's a shorter route than what's currently stored
                    // (always true for a yet-unvisited square)
                    if (shortest_distance[sd_index]>cumulative_moves)
                    {
                        // store the move count in this square, and
                        // add put it in the vector of squares to be
                        // expanded next iteration. We keep doing this till
                        // there are no new squares!
                        shortest_distance[sd_index] = cumulative_moves;
                        next_filled_points.emplace_back(std::make_pair(x,y));
                    }
                }
            }
        });
        filled_points = std::move(next_filled_points);
    }

    // find minimum value on first row (i.e. villain's terminal row)
    // to get villains shortest overall distance
    unsigned short villains_shortest_distance = std::numeric_limits<unsigned short>::max();
    for (size_t i=0;i<BOARD_SIZE;++i)
        if (shortest_distance[i]<villains_shortest_distance)
            villains_shortest_distance = shortest_distance[i];

    return villains_shortest_distance;
}

unsigned short board::get_heros_shortest_distance() const
{
    return board(*this,true).get_villains_shortest_distance();
}

// function signature for eval includes the most general case where we have an eval function that returns
// both a Q value and a policy consisting of a vector of probs corresponding with probs of children
// Sprint 5.3: replaced `throw std::string(...)` with `__builtin_trap()` so the
// translation unit compiles under `-fno-exceptions`. The imperative
// engine never invokes this entry — it routes through
// `mcts_imperative::run_search`'s arena search, not the legacy
// `uct_node::eval` ANN-prior path — so the trap is dead code on the
// supported path.
void board::eval(const std::vector<board_node_ptr> & children, double & eval_Q, std::vector<double> & eval_probs) const
{
    (void)children; (void)eval_Q; (void)eval_probs;
    __builtin_trap();
}

// hash caching with lazy evaluation
size_t board::get_hash() const
{
    if(!_stored_hash)
    {
        hash_combine(_stored_hash,hero_x);
        hash_combine(_stored_hash,hero_y);
        hash_combine(_stored_hash,villain_x);
        hash_combine(_stored_hash,villain_y);
        hash_combine(_stored_hash,hero_walls_remaining);
        hash_combine(_stored_hash,villain_walls_remaining);
        hash_combine(_stored_hash,wall_middles.get_hash());
        hash_combine(_stored_hash,horizontal_walls.get_hash());
        hash_combine(_stored_hash,vertical_walls.get_hash());
    }
    return _stored_hash;
    // NB: we intentionally leave _action out of the hash as the hash is only for the position
}

bool board::is_terminal() const
{
    return hero_wins() || villain_wins();
}

// Sprint 5.3: replaced the non-terminal-state `throw std::string(...)`
// with `__builtin_trap()` so this TU compiles under `-fno-exceptions`.
// The imperative engine never calls this entry — it uses
// `mcts_imperative::State::terminal_eval` (which is `noexcept` and
// returns `0.0` on the ply-cap branch) for every rollout — so the
// trap path is dead code on the supported path.
double board::get_terminal_eval() const
{
    if (hero_wins())
        return 1.0;
    if (villain_wins())
        return -1.0;
    __builtin_trap();
}

std::string board::get_action_text(const bool flip) const
{
    action use_action(_action);
    if (flip) use_action.flip();
    // we flip because we're usually interested in seeing this from the previous hero's perspective
    // (e.g. when we're evaluating hero's move)
    if(use_action.is_positional)
    {
        unsigned short _hero_x = use_action.token_position % BOARD_SIZE;
        unsigned short _hero_y = use_action.token_position / BOARD_SIZE;
        return std::string("*(")
            + lexical_cast<std::string>(_hero_x)
            + std::string(",")
            + lexical_cast<std::string>(_hero_y)
            + std::string(")");
    }
    else
    {
        unsigned short _wall_x = use_action.wall_middle % (BOARD_SIZE-1);
        unsigned short _wall_y = use_action.wall_middle / (BOARD_SIZE-1);
        std::string orientation((use_action.wall_is_vertical?"V":"H"));
        return orientation + std::string("(")
            + lexical_cast<std::string>(_wall_x)
            + std::string(",")
            + lexical_cast<std::string>(_wall_y)
            + std::string(")");
    }
}

std::string board::display() const
{
    std::vector<std::string> rows;

    std::string dots(".");
    std::string bars("|");
    std::string blanks(" ");
    for(size_t i=0;i<BOARD_SIZE;++i)
    {
        dots += "   .";
        bars += "   |";
        blanks += "    ";
    }

    rows.push_back(dots);
    for (size_t i=0;i<BOARD_SIZE;++i)
    {
        rows.push_back(blanks);
        rows.push_back(dots);
    }

    std::string em("—");

    // compute locations of hero markers
    unsigned short output_hero_x = 2 + hero_x * 4;
    unsigned short output_hero_y = 1 + (BOARD_SIZE - 1 - hero_y) * 2;
    unsigned short output_villain_x = 2 + villain_x * 4;
    unsigned short output_villain_y = 1 + (BOARD_SIZE - 1 - villain_y) * 2;
    rows[output_hero_y].replace(output_hero_x,1,"h");
    rows[output_villain_y].replace(output_villain_x,1,"v");

    // add wall intersections
    for (size_t i=0;i<(BOARD_SIZE-1)*(BOARD_SIZE-1);++i)
    {
        if(wall_middles.test(i))
        {
            size_t wall_x = 4 + (i % (BOARD_SIZE-1)) * 4;
            size_t wall_y = 2 + (BOARD_SIZE - 2 - i / (BOARD_SIZE-1)) * 2;
            rows[wall_y].replace(wall_x,1,"+");
        }
    }

    // add horizontal and vertical walls
    for (size_t i=0;i<(BOARD_SIZE-1)*BOARD_SIZE;++i)
    {
        if(horizontal_walls.test(i))
        {
            size_t wall_x = 1 + (i % BOARD_SIZE) * 4;
            size_t wall_y = 2 + (BOARD_SIZE - 2 - i / BOARD_SIZE) * 2;
            rows[wall_y].replace(wall_x,1,"-");
            rows[wall_y].replace(wall_x+1,1,"-");
            rows[wall_y].replace(wall_x+2,1,"-");
        }
        if(vertical_walls.test(i))
        {

            size_t wall_x = 4 + (i / BOARD_SIZE) * 4;
            size_t wall_y = 1 + (BOARD_SIZE - 1 - i % BOARD_SIZE) * 2;
            rows[wall_y].replace(wall_x,1,"|");
        }
    }

    unsigned short _villains_shortest_distance = get_villains_shortest_distance();
    unsigned short _heros_shortest_distance = get_heros_shortest_distance();

    std::string output;
    output += std::string("Hero distance from end: ") + lexical_cast<std::string>(_heros_shortest_distance) + std::string("\n");
    output += std::string("Villain distance from end: ") + lexical_cast<std::string>(_villains_shortest_distance) + std::string("\n");
    output += std::string("Hero walls remaining: ") + lexical_cast<std::string>(hero_walls_remaining) + std::string("\n");
    output += std::string("Villain walls remaining: ") + lexical_cast<std::string>(villain_walls_remaining) + std::string("\n");

    std::for_each(rows.cbegin(), rows.cend(),[&](const std::string & str){
        output += str;
        output += "\n";
    });

    return std::move(output);
}

// if no walls are left, we can easily determine who will win
// as it's just a straight race. We conservatively require a margin
// of 2 moves to declare a victor just to be sure piece hopping,
// who's first to act, etc won't change the outcome of the race.
bool board::check_non_terminal_eval(double & eval) const
{
    if (is_terminal()) return false;
    if (hero_walls_remaining>0 || villain_walls_remaining>0) return false;

    int _non_terminal_rank = get_non_terminal_rank();
    if (_non_terminal_rank<=-2)
    {
        // villain guaranteed to win as they're 2 moves ahead in a straight race
        eval = -1.0;
        return true;
    }
    if (_non_terminal_rank>=2)
    {
        // hero guaranteed to win as they're 2 moves ahead in a straight race
        eval = 1.0;
        return true;
    }
    return false;
}

int board::get_non_terminal_rank() const
{
    // high rank is better for hero
    unsigned short villains_shortest_distance = get_villains_shortest_distance();
    unsigned short heros_shortest_distance = get_heros_shortest_distance();
    return (int)villains_shortest_distance - (int)heros_shortest_distance;
}

void board::Deep_Copy(const board & source, bool flip)
{
    // flip-copying represents the same board position from villain's perspective
    if (flip)
    {
        hero_x=BOARD_SIZE-1-source.villain_x;
        hero_y=BOARD_SIZE-1-source.villain_y;
        villain_x=BOARD_SIZE-1-source.hero_x;
        villain_y=BOARD_SIZE-1-source.hero_y;
        hero_walls_remaining=source.villain_walls_remaining;
        villain_walls_remaining=source.hero_walls_remaining;
        wall_middles=source.wall_middles; wall_middles.flip();
        horizontal_walls=source.horizontal_walls; horizontal_walls.flip();
        vertical_walls=source.vertical_walls; vertical_walls.flip();
        _action = source._action; _action.flip();
    }
    else
    {
        hero_x=source.hero_x;
        hero_y=source.hero_y;
        villain_x=source.villain_x;
        villain_y=source.villain_y;
        hero_walls_remaining=source.hero_walls_remaining;
        villain_walls_remaining=source.villain_walls_remaining;
        wall_middles=source.wall_middles;
        horizontal_walls=source.horizontal_walls;
        vertical_walls=source.vertical_walls;
        _action = source._action;
    }
    _stored_hash = 0; // to ensure we recompute the hash
}

bool board::hero_wins() const
{
    return hero_y == BOARD_SIZE-1;
}

bool board::villain_wins() const
{
    return villain_y == 0;
}

// last argument is optional, for case where we're using contact flags
bool board::try_positional_move(const unsigned short x, const unsigned short y, const short x_diff, const short y_diff, flags::flags<BOARD_SIZE*BOARD_SIZE> * const contact_flags) const
{
    // check that the proposed move is only a single step in a single direction
    // (don't really need to incur the cost of this check anymore since this exception was never getting thrown)
    // if (abs((int)x_diff) + abs((int)y_diff) != 1) throw std::string("Error: board::try_positional_move dimensions must agree.");

    // keep these signed to ensure we catch negative values
    short proposed_hero_x = (short)x + x_diff;
    short proposed_hero_y = (short)y + y_diff;

    // check that we're remaining within game boundaries
    if (proposed_hero_x<0 ||
        proposed_hero_y<0 ||
        proposed_hero_x>=BOARD_SIZE ||
        proposed_hero_y>=BOARD_SIZE)
        return false;

    // check that we don't already have a contact flag set to true.
    // (only checked when the pointer is not null)
    size_t contact_flag_index = (size_t)(proposed_hero_y*BOARD_SIZE + proposed_hero_x);
    if (contact_flags && contact_flags->test(contact_flag_index))
            return false;

    // check that we didn't cross any walls
    if (x_diff!=0)
    {
        // horizontal move -- check for vertical walls

        // compute index of horizontal wall that was immediately to hero's right
        // before they made thier (proposed) move. This is the right wall to
        // check if the proposed move is rightward.
        unsigned short wall_index = BOARD_SIZE*x + y;

        // If the proposed move is leftward, we need to reduce this index by 1 row.
        if (x_diff<0) wall_index -=BOARD_SIZE;

        if (vertical_walls.test((size_t)wall_index)) return false;
    }
    else
    {
        // vertical move -- check for horizontal walls.
        // use similar logic as in horizontal case.
        unsigned short wall_index = BOARD_SIZE*y + x;
        if (y_diff<0) wall_index-=BOARD_SIZE;
        if (horizontal_walls.test((size_t)wall_index)) return false;
    }

    // set contact flag to true (if applicible)
    if (contact_flags) contact_flags->set(contact_flag_index);

    return true;
}
