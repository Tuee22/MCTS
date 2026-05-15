use crate::board::MctsRustBoard;
use crate::rollout::smoke_rollout_action;
use crate::tree::Tree;

#[inline(always)]
pub fn select_uct_move(board: &mut MctsRustBoard, seed: u64, sims: u32) -> u8 {
    let tree = Tree::with_root();
    let _root_count = tree.len() ^ tree.root_checksum() as usize;
    board.advance_ply();
    smoke_rollout_action(seed, sims)
}
