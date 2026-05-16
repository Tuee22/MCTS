// Random-rollout leaf evaluator for the placeholder game.
//
// The placeholder game has `n_legal_moves(ply)` legal actions at each
// ply, and reaches a terminal at `ply >= max_plies` with a draw
// payoff. This is enough to exercise the arena search; the real
// Corridors port from `cpp-legacy/legacy-core/` (wall + jump + BFS
// escapability) remains a Sprint 6.3/6.4 ledger row.

use crate::xoshiro256pp::Xoshiro256pp;

#[allow(dead_code)]
#[inline(always)]
pub fn smoke_rollout_action(seed: u64, sims: u32) -> u8 {
    ((seed.wrapping_add(sims as u64)) % 81) as u8
}

#[inline(always)]
pub fn n_legal_moves(ply: u16) -> u32 {
    let base = 12u32;
    let cycle = (ply as u32 % 5) + 1;
    base + cycle
}

#[inline(always)]
pub fn rollout_value(start_ply: u16, max_plies: u16, rng: &mut Xoshiro256pp) -> f64 {
    let mut ply = start_ply;
    while ply < max_plies {
        let _ = rng.next();
        ply = ply.saturating_add(1);
    }
    0.0  // draw under ply-cap termination
}
