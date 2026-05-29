// Backend (iv) C ABI shim. Sprint 6.10 introduces `RustBoardHandle`,
// the opaque handle the Rust C ABI hands out. It owns the search-board
// state (`MctsRustBoard`, with no `last_visit_*` fields after Sprint
// 6.10) plus the optional read-visits cache. The C ABI symbol set,
// signatures, and behavior are unchanged: `mcts_rust_new_board`,
// `mcts_rust_free_board`, `mcts_rust_is_terminal`, `mcts_rust_apply_action`,
// `mcts_rust_select_uct_move`, `mcts_rust_search_move`,
// `mcts_rust_recompute_move`, `mcts_rust_read_visits`,
// `mcts_rust_benchmark_terminal_playouts`,
// `mcts_rust_benchmark_search_iters`, `mcts_rust_get_envelope`.

use crate::board::{
    absolute_action_from_abi, MctsRustBoard, MAX_LEGAL_ACTIONS,
};
use crate::envelope::{envelope_ptr, MctsRustEnvelope};
use crate::search::{
    benchmark_search_iters, benchmark_terminal_playouts, run_search, select_uct_move,
};

const DEFAULT_MAX_PLIES: u16 = 200;

/// Opaque handle the C ABI hands out. Owns the search-state plus the
/// optional read-visits cache. Sprint 6.10 relocates the 169-byte
/// `last_visit_*` cache off `MctsRustBoard` (search state) onto this
/// handle so every per-rollout clone, per-wall-candidate trial, and
/// per-expansion child shed the cache footprint.
pub struct RustBoardHandle {
    pub state: MctsRustBoard,
    last_visit_len: u8,
    last_visit_actions: [u8; MAX_LEGAL_ACTIONS],
    last_visit_counts: [u32; MAX_LEGAL_ACTIONS],
}

impl RustBoardHandle {
    #[inline(always)]
    fn new() -> Self {
        Self {
            state: MctsRustBoard::new(),
            last_visit_len: 0,
            last_visit_actions: [0; MAX_LEGAL_ACTIONS],
            last_visit_counts: [0; MAX_LEGAL_ACTIONS],
        }
    }

    #[inline(always)]
    fn store_visits(&mut self, visits: &[(u8, u32)]) {
        self.last_visit_len = visits.len().min(MAX_LEGAL_ACTIONS) as u8;
        for (idx, (action, count)) in visits.iter().take(MAX_LEGAL_ACTIONS).enumerate() {
            self.last_visit_actions[idx] = *action;
            self.last_visit_counts[idx] = *count;
        }
    }

    #[inline(always)]
    fn clear_visits(&mut self) {
        self.last_visit_len = 0;
    }

    #[inline(always)]
    fn read_visit(&self, action_id: u8) -> u32 {
        for idx in 0..self.last_visit_len as usize {
            if self.last_visit_actions[idx] == action_id {
                return self.last_visit_counts[idx];
            }
        }
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mcts_rust_new_board() -> *mut RustBoardHandle {
    Box::into_raw(Box::new(RustBoardHandle::new()))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_free_board(board: *mut RustBoardHandle) {
    if !board.is_null() {
        drop(unsafe { Box::from_raw(board) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_is_terminal(board: *const RustBoardHandle) -> i32 {
    if board.is_null() {
        return 1;
    }
    unsafe { (*board).state.is_terminal(DEFAULT_MAX_PLIES) as i32 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_apply_action(
    board: *mut RustBoardHandle,
    action_id: u8,
) -> i32 {
    if board.is_null() {
        return -1;
    }
    let handle = unsafe { &mut *board };
    let absolute = absolute_action_from_abi(handle.state.side_to_move, action_id);
    if handle.state.try_apply_absolute(absolute, DEFAULT_MAX_PLIES) {
        handle.clear_visits();
        0
    } else {
        -1
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_select_uct_move(
    board: *mut RustBoardHandle,
    seed: u64,
    sims: u32,
) -> u8 {
    if board.is_null() {
        return 0;
    }
    let handle = unsafe { &mut *board };
    let chosen = select_uct_move(&mut handle.state, seed, sims);
    handle.clear_visits();
    chosen
}

/// Full visit-vector search ABI. Sprint 6.10: the search returns visit
/// IDs already translated into the legacy ABI hero-perspective via
/// `abi_action_from_absolute(root_side, absolute)`, and the trusted
/// internal apply uses `chosen_absolute_action_id` so the C ABI shim
/// no longer redundantly re-flips through `flip_action_id`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_search_move(
    board: *mut RustBoardHandle,
    seed: u64,
    sims: u32,
    out_action_ids: *mut u8,
    out_visits: *mut u32,
    out_chosen: *mut u8,
) -> i32 {
    if board.is_null() || out_action_ids.is_null() || out_visits.is_null() || out_chosen.is_null() {
        return -1;
    }
    let handle = unsafe { &mut *board };
    if handle.state.is_terminal(DEFAULT_MAX_PLIES) {
        return -1;
    }
    let result = run_search(&handle.state, sims, DEFAULT_MAX_PLIES, seed);
    if !result.ok {
        return -1;
    }
    handle
        .state
        .apply_action_unchecked(result.chosen_absolute_action_id);
    handle.store_visits(&result.visits);
    let count = result.visits.len();
    for (i, (aid, visits)) in result.visits.iter().enumerate() {
        unsafe {
            *out_action_ids.add(i) = *aid;
            *out_visits.add(i) = *visits;
        }
    }
    unsafe {
        *out_chosen = result.chosen_action_id;
    }
    count as i32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_recompute_move(
    board: *mut RustBoardHandle,
    seed: u64,
    sims: u32,
    out_action_ids: *mut u8,
    out_visits: *mut u32,
    out_chosen: *mut u8,
    out_equity: *mut f64,
) -> i32 {
    if board.is_null()
        || out_action_ids.is_null()
        || out_visits.is_null()
        || out_chosen.is_null()
        || out_equity.is_null()
    {
        return -1;
    }
    let handle = unsafe { &mut *board };
    if handle.state.is_terminal(DEFAULT_MAX_PLIES) {
        return -1;
    }
    let result = run_search(&handle.state, sims, DEFAULT_MAX_PLIES, seed);
    if !result.ok {
        return -1;
    }
    handle
        .state
        .apply_action_unchecked(result.chosen_absolute_action_id);
    handle.store_visits(&result.visits);
    let count = result.visits.len();
    for (i, (aid, visits)) in result.visits.iter().enumerate() {
        unsafe {
            *out_action_ids.add(i) = *aid;
            *out_visits.add(i) = *visits;
        }
    }
    unsafe {
        *out_chosen = result.chosen_action_id;
        *out_equity = result.chosen_equity;
    }
    count as i32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_benchmark_terminal_playouts(
    board: *const RustBoardHandle,
    seed: u64,
    count: u32,
    max_plies: u16,
) -> u64 {
    if board.is_null() {
        return 0;
    }
    benchmark_terminal_playouts(unsafe { &(*board).state }, count, max_plies, seed)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_benchmark_search_iters(
    board: *const RustBoardHandle,
    seed: u64,
    count: u32,
    max_plies: u16,
) -> u64 {
    if board.is_null() {
        return 0;
    }
    benchmark_search_iters(unsafe { &(*board).state }, count, max_plies, seed)
}

/// Optional read-visits accessor: looks up `action_id` in the last
/// exposed visit vector cached on the opaque handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_read_visits(
    board: *const RustBoardHandle,
    action_id: u8,
) -> u32 {
    if board.is_null() {
        return 0;
    }
    unsafe { (*board).read_visit(action_id) }
}

#[unsafe(no_mangle)]
pub extern "C" fn mcts_rust_get_envelope() -> *const MctsRustEnvelope {
    envelope_ptr()
}
