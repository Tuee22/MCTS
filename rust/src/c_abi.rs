use crate::board::{MctsRustBoard, flip_action_id};
use crate::envelope::{MctsRustEnvelope, envelope_ptr};
use crate::search::{run_search, select_uct_move};
use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_void};
use std::collections::HashMap;
use std::mem;
use std::sync::{Mutex, OnceLock};

const DEFAULT_MAX_PLIES: u16 = 200;

type VisitVector = Vec<(u8, u32)>;

static LAST_VISITS: OnceLock<Mutex<HashMap<usize, VisitVector>>> = OnceLock::new();
static CPP_BOARDS: OnceLock<Mutex<HashMap<usize, usize>>> = OnceLock::new();
static CPP_API: OnceLock<Option<CppApi>> = OnceLock::new();

type CppNewBoard = unsafe extern "C" fn() -> *mut c_void;
type CppFreeBoard = unsafe extern "C" fn(*mut c_void);
type CppIsTerminal = unsafe extern "C" fn(*const c_void) -> c_int;
type CppApplyAction = unsafe extern "C" fn(*mut c_void, u8) -> c_int;
type CppSearchMove =
    unsafe extern "C" fn(*mut c_void, u64, u32, *mut u8, *mut u32, *mut u8) -> i32;
type CppRecomputeMove =
    unsafe extern "C" fn(*mut c_void, u64, u32, *mut u8, *mut u32, *mut u8, *mut f64) -> i32;
type CppReadVisits = unsafe extern "C" fn(*const c_void, u8) -> u32;

struct CppApi {
    _handle: usize,
    new_board: CppNewBoard,
    free_board: CppFreeBoard,
    is_terminal: CppIsTerminal,
    apply_action: CppApplyAction,
    search_move: CppSearchMove,
    recompute_move: CppRecomputeMove,
    read_visits: CppReadVisits,
}

#[link(name = "dl")]
unsafe extern "C" {
    fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
}

const RTLD_NOW: c_int = 2;

fn last_visits_cache() -> &'static Mutex<HashMap<usize, VisitVector>> {
    LAST_VISITS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn cpp_boards() -> &'static Mutex<HashMap<usize, usize>> {
    CPP_BOARDS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn board_key(board: *const MctsRustBoard) -> usize {
    board as usize
}

fn store_last_visits(board: *const MctsRustBoard, visits: VisitVector) {
    if let Ok(mut cache) = last_visits_cache().lock() {
        cache.insert(board_key(board), visits);
    }
}

fn cpp_api() -> Option<&'static CppApi> {
    CPP_API.get_or_init(load_cpp_api).as_ref()
}

fn load_cpp_api() -> Option<CppApi> {
    unsafe {
        let handle = open_cpp_library()?;
        Some(CppApi {
            _handle: handle as usize,
            new_board: load_symbol(handle, "mcts_imperative_new_board")?,
            free_board: load_symbol(handle, "mcts_imperative_free_board")?,
            is_terminal: load_symbol(handle, "mcts_imperative_is_terminal")?,
            apply_action: load_symbol(handle, "mcts_imperative_apply_action")?,
            search_move: load_symbol(handle, "mcts_imperative_search_move")?,
            recompute_move: load_symbol(handle, "mcts_imperative_recompute_move")?,
            read_visits: load_symbol(handle, "mcts_imperative_read_visits")?,
        })
    }
}

unsafe fn open_cpp_library() -> Option<*mut c_void> {
    for raw_path in [
        "cpp-imperative/build/libmcts_cpp_imperative.so",
        "/workspace/MCTS/cpp-imperative/build/libmcts_cpp_imperative.so",
    ] {
        let path = CString::new(raw_path).ok()?;
        let handle = unsafe { dlopen(path.as_ptr(), RTLD_NOW) };
        if handle.is_null() {
            continue;
        }
        return Some(handle);
    }
    None
}

unsafe fn load_symbol<T>(handle: *mut c_void, name: &str) -> Option<T> {
    let symbol = CString::new(name).ok()?;
    let ptr = unsafe { dlsym(handle, symbol.as_ptr()) };
    if ptr.is_null() {
        None
    } else {
        Some(unsafe { mem::transmute_copy(&ptr) })
    }
}

fn cpp_board(board: *const MctsRustBoard) -> Option<*mut c_void> {
    if board.is_null() {
        return None;
    }
    let boards = cpp_boards().lock().ok()?;
    boards.get(&board_key(board)).map(|ptr| *ptr as *mut c_void)
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
    let board = Box::into_raw(Box::new(MctsRustBoard::new()));
    if let Some(api) = cpp_api() {
        let cpp = unsafe { (api.new_board)() };
        if !cpp.is_null() {
            if let Ok(mut boards) = cpp_boards().lock() {
                boards.insert(board_key(board), cpp as usize);
            }
        }
    }
    board
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_free_board(board: *mut MctsRustBoard) {
    if !board.is_null() {
        clear_last_visits(board as *const MctsRustBoard);
        if let Some(api) = cpp_api() {
            if let Ok(mut boards) = cpp_boards().lock() {
                if let Some(cpp) = boards.remove(&board_key(board)) {
                    unsafe { (api.free_board)(cpp as *mut c_void) };
                }
            }
        }
        drop(unsafe { Box::from_raw(board) });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_is_terminal(board: *const MctsRustBoard) -> i32 {
    if board.is_null() {
        return 1;
    }
    if let (Some(api), Some(cpp)) = (cpp_api(), cpp_board(board)) {
        return unsafe { (api.is_terminal)(cpp as *const c_void) as i32 };
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
    if let (Some(api), Some(cpp)) = (cpp_api(), cpp_board(board)) {
        let applied = unsafe { (api.apply_action)(cpp, action_id) };
        if applied == 0 {
            clear_last_visits(board);
        }
        return applied as i32;
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
    if let (Some(api), Some(cpp)) = (cpp_api(), cpp_board(board)) {
        let count =
            unsafe { (api.search_move)(cpp, seed, sims, out_action_ids, out_visits, out_chosen) };
        if count > 0 {
            let mut visits = Vec::with_capacity(count as usize);
            for i in 0..count as usize {
                visits.push(unsafe { (*out_action_ids.add(i), *out_visits.add(i)) });
            }
            store_last_visits(board as *const MctsRustBoard, visits);
        }
        return count;
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
    if let (Some(api), Some(cpp)) = (cpp_api(), cpp_board(board)) {
        let count = unsafe {
            (api.recompute_move)(
                cpp,
                seed,
                sims,
                out_action_ids,
                out_visits,
                out_chosen,
                out_equity,
            )
        };
        if count > 0 {
            let mut visits = Vec::with_capacity(count as usize);
            for i in 0..count as usize {
                visits.push(unsafe { (*out_action_ids.add(i), *out_visits.add(i)) });
            }
            store_last_visits(board as *const MctsRustBoard, visits);
        }
        return count;
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

/// Instrumentation hook for the paired bench/instrumented split per
/// the Cargo feature `instrumentation`. Looks up `action_id` in the
/// last exposed visit vector for this board handle, matching the C++
/// shims' per-board last-search cache.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mcts_rust_read_visits(
    board: *const MctsRustBoard,
    action_id: u8,
) -> u32 {
    if board.is_null() {
        return 0;
    }
    if let (Some(api), Some(cpp)) = (cpp_api(), cpp_board(board)) {
        return unsafe { (api.read_visits)(cpp as *const c_void, action_id) };
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
