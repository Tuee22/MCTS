use crate::board::{MctsRustBoard, flip_action_id};
use crate::envelope::{MctsRustEnvelope, envelope_ptr};
use crate::search::{
    benchmark_search_iters, benchmark_terminal_playouts, run_search, select_uct_move,
};
use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

const DEFAULT_MAX_PLIES: u16 = 200;

type VisitVector = Vec<(u8, u32)>;

static LAST_VISITS: OnceLock<Mutex<HashMap<usize, VisitVector>>> = OnceLock::new();

fn last_visits_cache() -> &'static Mutex<HashMap<usize, VisitVector>> {
    LAST_VISITS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn board_key(board: *const MctsRustBoard) -> usize {
    board as usize
}

fn store_last_visits(board: *const MctsRustBoard, visits: VisitVector) {
    if let Ok(mut cache) = last_visits_cache().lock() {
        cache.insert(board_key(board), visits);
    }
}

fn clear_last_visits(board: *const MctsRustBoard) {
    if let Ok(mut cache) = last_visits_cache().lock() {
        cache.remove(&board_key(board));
    }
}

fn encode_search_visits(visits: &[(u8, u32)]) -> VisitVector {
    let mut encoded: VisitVector = visits
        .iter()
        .map(|(aid, n)| (flip_action_id(*aid), *n))
        .collect();
    encoded.sort_by_key(|(aid, _)| *aid);
    encoded
}

#[unsafe(no_mangle)]
pub extern "C" fn mcts_rust_new_board() -> *mut MctsRustBoard {
    Box::into_raw(Box::new(MctsRustBoard::new()))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_free_board(board: *mut MctsRustBoard) {
    if !board.is_null() {
        clear_last_visits(board as *const MctsRustBoard);
        drop(unsafe { Box::from_raw(board) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_is_terminal(board: *const MctsRustBoard) -> i32 {
    if board.is_null() {
        return 1;
    }
    unsafe { (*board).is_terminal(DEFAULT_MAX_PLIES) as i32 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_apply_action(
    board: *mut MctsRustBoard,
    action_id: u8,
) -> i32 {
    if board.is_null() {
        return -1;
    }
    let board_ref = unsafe { &mut *board };
    if board_ref.apply_action_flip(flip_action_id(action_id)) {
        clear_last_visits(board);
        0
    } else {
        -1
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_select_uct_move(
    board: *mut MctsRustBoard,
    seed: u64,
    sims: u32,
) -> u8 {
    if board.is_null() {
        return 0;
    }
    select_uct_move(unsafe { &mut *board }, seed, sims)
}

/// Full visit-vector search ABI per
/// `documents/engineering/backend_ffi_contract.md → C ABI Shape`. The
/// search is driven by the arena MCTS in `search.rs` over the real
/// Corridors board and rollout implementation.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_search_move(
    board: *mut MctsRustBoard,
    seed: u64,
    sims: u32,
    out_action_ids: *mut u8,
    out_visits: *mut u32,
    out_chosen: *mut u8,
) -> i32 {
    if board.is_null() || out_action_ids.is_null() || out_visits.is_null() || out_chosen.is_null() {
        return -1;
    }
    let board_ref = unsafe { &mut *board };
    if board_ref.is_terminal(DEFAULT_MAX_PLIES) {
        return -1;
    }
    let result = run_search(board_ref, sims, DEFAULT_MAX_PLIES, seed);
    if !result.ok {
        return -1;
    }
    let _ = board_ref.apply_action_flip(result.chosen_action_id);
    // The legacy C ABI convention is to return action ids in the
    // post-move flipped perspective. The Rust search stores root
    // child ids in current-hero perspective, so the FFI boundary
    // performs the same flip as the C++ board child constructor.
    let flipped = encode_search_visits(&result.visits);
    store_last_visits(board_ref as *const MctsRustBoard, flipped.clone());
    let count = flipped.len();
    for (i, (aid, visits)) in flipped.iter().enumerate() {
        unsafe {
            *out_action_ids.add(i) = *aid;
            *out_visits.add(i) = *visits;
        }
    }
    unsafe {
        *out_chosen = flip_action_id(result.chosen_action_id);
    }
    count as i32
}

/// Foreign-engine recompute: returns the search output plus the
/// post-move parent-perspective equity of the chosen action. Sprint
/// 6.5: the equity is `-child.q_sum / child.visits` from the chosen
/// child captured during `run_search`. NaN if the chosen child was
/// never visited (impossible for sims >= 1).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_recompute_move(
    board: *mut MctsRustBoard,
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
    let board_ref = unsafe { &mut *board };
    if board_ref.is_terminal(DEFAULT_MAX_PLIES) {
        return -1;
    }
    let result = run_search(board_ref, sims, DEFAULT_MAX_PLIES, seed);
    if !result.ok {
        return -1;
    }
    let _ = board_ref.apply_action_flip(result.chosen_action_id);
    let flipped = encode_search_visits(&result.visits);
    store_last_visits(board_ref as *const MctsRustBoard, flipped.clone());
    let count = flipped.len();
    for (i, (aid, visits)) in flipped.iter().enumerate() {
        unsafe {
            *out_action_ids.add(i) = *aid;
            *out_visits.add(i) = *visits;
        }
    }
    unsafe {
        *out_chosen = flip_action_id(result.chosen_action_id);
        *out_equity = result.chosen_equity;
    }
    count as i32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_benchmark_terminal_playouts(
    board: *const MctsRustBoard,
    seed: u64,
    count: u32,
    max_plies: u16,
) -> u64 {
    if board.is_null() {
        return 0;
    }
    benchmark_terminal_playouts(unsafe { &*board }, count, max_plies, seed)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_benchmark_search_iters(
    board: *const MctsRustBoard,
    seed: u64,
    count: u32,
    max_plies: u16,
) -> u64 {
    if board.is_null() {
        return 0;
    }
    benchmark_search_iters(unsafe { &*board }, count, max_plies, seed)
}

/// Optional visit cache accessor on the single optimized Rust FFI
/// artefact. The load-bearing search and recompute ABI returns visit
/// vectors directly; this helper looks up `action_id` in the last
/// exposed visit vector for this board handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_read_visits(
    board: *const MctsRustBoard,
    action_id: u8,
) -> u32 {
    if board.is_null() {
        return 0;
    }
    if let Ok(cache) = last_visits_cache().lock() {
        if let Some(visits) = cache.get(&board_key(board)) {
            for (aid, n) in visits {
                if *aid == action_id {
                    return *n;
                }
            }
        }
    }
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn mcts_rust_get_envelope() -> *const MctsRustEnvelope {
    envelope_ptr()
}
