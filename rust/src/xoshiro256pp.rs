// xoshiro256++ for backend (iv) under `--rng native`. Matches
// backends (ii) and (iii)'s native RNG choice per
// DEVELOPMENT_PLAN/phase-6-cpp-functional-and-rust.md → Sprint 6.3
// "Native RNG choice".

#[allow(dead_code)]
#[repr(C)]
pub struct Xoshiro256pp {
    s: [u64; 4],
}

#[allow(dead_code)]
impl Xoshiro256pp {
    #[inline(always)]
    pub fn new(seed: u64) -> Self {
        let mut s = [0u64; 4];
        let mut z = seed;
        for slot in s.iter_mut() {
            z = z.wrapping_add(0x9E3779B97F4A7C15);
            let mut t = z;
            t = (t ^ (t >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
            t = (t ^ (t >> 27)).wrapping_mul(0x94D049BB133111EB);
            t ^= t >> 31;
            *slot = t;
        }
        Self { s }
    }

    #[inline(always)]
    pub fn next(&mut self) -> u64 {
        let result = (self.s[0].wrapping_add(self.s[3])).rotate_left(23).wrapping_add(self.s[0]);
        let t = self.s[1] << 17;
        self.s[2] ^= self.s[0];
        self.s[3] ^= self.s[1];
        self.s[1] ^= self.s[2];
        self.s[0] ^= self.s[3];
        self.s[2] ^= t;
        self.s[3] = self.s[3].rotate_left(45);
        result
    }

    #[inline(always)]
    pub fn bounded(&mut self, bound: u64) -> u64 {
        if bound == 0 {
            return 0;
        }
        let mut m: u128 = (self.next() as u128) * (bound as u128);
        let mut l = m as u64;
        if l < bound {
            let t = (0u64.wrapping_sub(bound)) % bound;
            while l < t {
                m = (self.next() as u128) * (bound as u128);
                l = m as u64;
            }
        }
        (m >> 64) as u64
    }
}
