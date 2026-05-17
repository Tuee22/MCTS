// Random-rollout leaf evaluator over the real Corridors game per
// Sprint 6.3. The rollout uniformly samples a legal action, applies
// it, and continues until the position is terminal. Returns the
// hero-perspective leaf value as a draw under ply cap, +1 hero win,
// -1 villain win.

use crate::board::MctsRustBoard;
use crate::xoshiro256pp::Xoshiro256pp;

const HERO_WIN_VALUE: f64 = 1.0;
const VILLAIN_WIN_VALUE: f64 = -1.0;
const DRAW_VALUE: f64 = 0.0;

#[allow(dead_code)]
#[inline(always)]
pub fn smoke_rollout_action(seed: u64, sims: u32) -> u8 {
    ((seed.wrapping_add(sims as u64)) % 81) as u8
}

/// Play a random rollout from `start` to a terminal state or the ply
/// cap, returning the value from the perspective of the side that
/// moves at `start`. The board flips after every move so the always-
/// to-move side is "hero"; we map the hero-perspective leaf value
/// back through the parity of flip count.
pub fn rollout_value(start: &MctsRustBoard, max_plies: u16, rng: &mut Xoshiro256pp) -> f64 {
    let mut board = start.clone();
    let mut buffer: Vec<u8> = Vec::with_capacity(160);
    let mut perspective_flips: u32 = 0;
    while !board.is_terminal(max_plies) {
        board.legal_actions(&mut buffer, max_plies);
        if buffer.is_empty() {
            return DRAW_VALUE;
        }
        let pick = rng.bounded(buffer.len() as u64) as usize;
        let action = buffer[pick];
        let _ = board.apply_action_flip(action);
        perspective_flips = perspective_flips.wrapping_add(1);
    }
    let leaf_hero_value = if board.hero_wins() {
        HERO_WIN_VALUE
    } else if board.villain_wins() {
        VILLAIN_WIN_VALUE
    } else {
        DRAW_VALUE
    };
    if perspective_flips & 1 == 0 {
        leaf_hero_value
    } else {
        -leaf_hero_value
    }
}
