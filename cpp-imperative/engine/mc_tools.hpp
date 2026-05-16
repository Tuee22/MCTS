#pragma once
#include <random>
#include <limits>
#include <vector>

namespace mcts{

typedef uint_fast64_t Seed;

template <typename RAND>
double unif(RAND & rand) noexcept
{
    uint64_t random_integer = rand();

    // Convert and scale it to [0,1) range
    double random_double = static_cast<double>(random_integer) / (static_cast<double>(RAND::max()) + 1.0);
    return random_double;
}

template <typename T, typename RAND>
size_t select_random_index(const std::vector<T> & vec, RAND & rand) noexcept
{
    size_t sze=vec.size();
    return sze==0
        ? std::numeric_limits<size_t>::max()
        : sze==1
            ? 0
            : (size_t)((double)sze * unif(rand));
}

template <typename T, typename RAND>
T select_random_value(const std::vector<T> & vec, RAND & rand )
{
    size_t random_index=select_random_index(vec,rand);
    assert (random_index < vec.size());
    return vec[random_index];
}
} // namespace mcts
