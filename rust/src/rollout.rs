#[allow(dead_code)]
#[inline(always)]
pub fn smoke_rollout_action(seed: u64, sims: u32) -> u8 {
    ((seed.wrapping_add(sims as u64)) % 81) as u8
}
