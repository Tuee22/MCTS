#include "rng.h"

#include <random>

struct cpp_rng {
    std::mt19937_64 gen;
};

static uint64_t splitmix64(uint64_t x) {
    uint64_t z = x + 0x9e3779b97f4a7c15ULL;
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    return z ^ (z >> 31);
}

extern "C" cpp_rng* cpp_rng_new(uint64_t seed) {
    return new cpp_rng{std::mt19937_64(seed)};
}

extern "C" uint64_t cpp_rng_next_u64(cpp_rng* rng) {
    return rng ? rng->gen() : 0;
}

extern "C" cpp_rng* cpp_rng_split(uint64_t master_seed, uint64_t game_index) {
    return cpp_rng_new(splitmix64(master_seed + 0x9e3779b97f4a7c15ULL * (game_index + 1)));
}

extern "C" void cpp_rng_free(cpp_rng* rng) {
    delete rng;
}
