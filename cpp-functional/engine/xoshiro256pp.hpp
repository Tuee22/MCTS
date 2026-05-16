// xoshiro256++ — backend (iii) native RNG. Shares backend (ii)'s
// algorithm per Sprint 6.1: the (ii)-vs-(iii) comparison isolates
// *style* (API + data-flow), so the RNG must match. See
// DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md → Sprint 6.1
// "Native RNG choice" and
// [../documents/engineering/determinism_contract.md → RNG Source Split].

#pragma once

#include <cstdint>

namespace mcts_functional {

class Xoshiro256pp {
public:
    explicit Xoshiro256pp(uint64_t seed) noexcept { seed_from_u64(seed); }

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

private:
    [[gnu::always_inline]] static inline uint64_t rotl(uint64_t x, int k) noexcept {
        return (x << k) | (x >> (64 - k));
    }

    uint64_t s_[4]{};
};

}  // namespace mcts_functional
