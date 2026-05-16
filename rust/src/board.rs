// Backend (iv) game-state stub.
//
// The full Corridors game logic port from `cpp-legacy/legacy-core/`
// (wall placement, jump moves, BFS escapability check) is the largest
// remaining Sprint 6.3 / 6.4 deliverable and lives as a ledger row in
// `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`. Until that port
// lands, this struct carries only the `Word16` ply counter required by
// the doctrine ply-cap terminal semantic and the maximum-action-count
// envelope so the arena MCTS in `search.rs` has the right shape to
// drop a real game in later.

#[repr(C)]
pub struct MctsRustBoard {
    pub ply: u16,
}

impl MctsRustBoard {
    #[inline(always)]
    pub fn new() -> Self {
        Self { ply: 0 }
    }

    #[inline(always)]
    pub fn is_terminal(&self, max_plies: u16) -> bool {
        self.ply >= max_plies
    }

    #[inline(always)]
    pub fn advance_ply(&mut self) {
        self.ply = self.ply.saturating_add(1);
    }
}
