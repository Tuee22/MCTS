#[repr(C)]
pub struct MctsRustBoard {
    ply: u16,
}

impl MctsRustBoard {
    #[inline(always)]
    pub fn new() -> Self {
        Self { ply: 0 }
    }

    #[inline(always)]
    pub fn is_terminal(&self) -> bool {
        self.ply >= 200
    }

    #[inline(always)]
    pub fn advance_ply(&mut self) {
        self.ply = self.ply.saturating_add(1);
    }
}
