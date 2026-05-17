use crate::board::{MctsRustBoard, flip_action_id};
use crate::envelope::{MctsRustEnvelope, envelope_ptr};
use crate::search::{run_search, select_uct_move};

const DEFAULT_MAX_PLIES: u16 = 10000;

#[unsafe(no_mangle)]
pub extern "C" fn mcts_rust_new_board() -> *mut MctsRustBoard {
    Box::into_raw(Box::new(MctsRustBoard::new()))
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
    unsafe { (*board).is_terminal(DEFAULT_MAX_PLIES) as i32 }
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
/// search is driven by the arena MCTS in `search.rs` over the
/// placeholder game from `rollout.rs`; the real Corridors port is a
/// ledger row (Sprint 6.3 remaining work).
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
    // post-move flipped (next-player) perspective so the Haskell
    // driver's symmetric flip recovers absolute coordinates. The
    // Rust search emits ids in current-hero perspective, so we flip
    // each id at the FFI boundary. The chosen-action flip then
    // round-trips correctly through `applyFlip` in
    // `MCTS.Driver.ForeignSearch`.
    let flipped: Vec<(u8, u32)> = result
        .visits
        .iter()
        .map(|(aid, n)| (flip_action_id(*aid), *n))
        .collect();
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
    let flipped: Vec<(u8, u32)> = result
        .visits
        .iter()
        .map(|(aid, n)| (flip_action_id(*aid), *n))
        .collect();
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

/// Instrumentation hook for the paired bench/instrumented split per
/// the Cargo feature `instrumentation`. The bench artefact returns 0;
/// the instrumented artefact would look up the visit count for
/// `action_id` from the last search. The current implementation
/// always returns 0 because the search output is not retained across
/// the C ABI boundary; storing it requires a per-board last-search
/// cache (parallel to the C++ shims).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_read_visits(
    _board: *const MctsRustBoard,
    _action_id: u8,
) -> u32 {
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn mcts_rust_get_envelope() -> *const MctsRustEnvelope {
    envelope_ptr()
}
