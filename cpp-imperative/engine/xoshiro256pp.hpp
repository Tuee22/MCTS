// xoshiro256++ — backend (ii) native RNG per
// DEVELOPMENT_PLAN/phase-5-cpp-imperative-steelman.md → Sprint 5.1 and
// project README → Compiler and runtime tuning item 15.
//
// Under `--rng cpp` the FFI surface accepts a `std::mt19937_64` seed
// stream (see `cpp-legacy/c-abi/rng.{h,cc}`) and this generator is
// unused. Under `--rng native` the imperative engine draws from this
// xoshiro256++ instance seeded via `seed_from_u64`.

#pragma once

#include <cstdint>

namespace mcts_imperative {

class Xoshiro256pp {
public:
    explicit Xoshiro256pp(uint64_t seed) noexcept { seed_from_u64(seed); }

    // SplitMix64 seeding so a single u64 fans out across the 256-bit state.
    void seed_from_u64(uint64_t seed) noexcept {
        uint64_t z = seed;
        for (int i = 0; i < 4; ++i) {
            z += 0x9E3779B97F4A7C15ULL;
            uint64_t t = z;
            t = (t ^ (t >> 30)) * 0xBF58476D1CE4E5B9ULL;
            t = (t ^ (t >> 27)) * 0x94D049BB133111EBULL;
            t = t ^ (t >> 31);
            s_[i] = t;
        }
    }

    [[gnu::hot, gnu::always_inline]] inline uint64_t next() noexcept {
        const uint64_t result = rotl(s_[0] + s_[3], 23) + s_[0];
        const uint64_t t = s_[1] << 17;
        s_[2] ^= s_[0];
        s_[3] ^= s_[1];
        s_[1] ^= s_[2];
        s_[0] ^= s_[3];
        s_[2] ^= t;
        s_[3] = rotl(s_[3], 45);
        return result;
    }

    [[gnu::hot, gnu::always_inline]] inline uint64_t bounded(uint64_t bound) noexcept {
        // Lemire's nearly-divisionless bounded uniform.
        __uint128_t m = (__uint128_t) next() * (__uint128_t) bound;
        uint64_t l = (uint64_t) m;
        if (l < bound) {
            uint64_t t = (uint64_t)(-bound) % bound;
            while (l < t) {
                m = (__uint128_t) next() * (__uint128_t) bound;
                l = (uint64_t) m;
            }
        }
        return (uint64_t)(m >> 64);
    }

    [[gnu::hot, gnu::always_inline]] inline double next_unit_double() noexcept {
        // 53-bit mantissa in [0, 1).
        return (double)(next() >> 11) * (1.0 / 9007199254740992.0);
    }

private:
    [[gnu::always_inline]] static inline uint64_t rotl(uint64_t x, int k) noexcept {
        return (x << k) | (x >> (64 - k));
    }

    uint64_t s_[4]{};
};

}  // namespace mcts_imperative
