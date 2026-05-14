#[repr(C)]
pub struct MctsRustBoard {
    ply: u16,
}

#[unsafe(no_mangle)]
pub extern "C" fn mcts_rust_new_board() -> *mut MctsRustBoard {
    Box::into_raw(Box::new(MctsRustBoard { ply: 0 }))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_free_board(board: *mut MctsRustBoard) {
    if !board.is_null() {
        drop(unsafe { Box::from_raw(board) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_is_terminal(board: *const MctsRustBoard) -> i32 {
    if board.is_null() {
        return 1;
    }
    (unsafe { (*board).ply } >= 200) as i32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_select_uct_move(
    board: *mut MctsRustBoard,
    seed: u64,
    sims: u32,
) -> u8 {
    if !board.is_null() {
        unsafe {
            (*board).ply = (*board).ply.saturating_add(1);
        }
    }
    ((seed + sims as u64) % 81) as u8
}
