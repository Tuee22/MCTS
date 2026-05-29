// Sprint 6.10 backend (iv) search: arena-based UCT mirroring the
// backend (iii) Sprint 6.9 shape inside Rust ownership idioms.
//
//   * `terminal_outcome` is hero-perspective (the absolute `SideToMove`
//     in `MctsRustBoard` removes the prior per-transition flip, so the
//     outcome lives in the absolute frame).
//   * `descend_iterative` materializes the search `MctsRustBoard` on
//     the stack and walks a fixed-capacity `path` buffer for backprop.
//     The arena node carries only `action_id` plus visit/value fields.
//   * `rollout_haskell` reuses a single `ActionBuffer`; no per-rollout
//     heap allocation.
//   * The Sprint 6.10 `legal_actions` precomputes `BlockMasks` once
//     per call and runs `wall_action_legal` against additive trial
//     masks — no per-candidate board clone.

use crate::board::{
    abi_action_from_absolute, ActionBuffer, MctsRustBoard, SideToMove, MAX_LEGAL_ACTIONS,
};
use crate::rollout::smoke_rollout_action;
use crate::tree::Tree;

const DEFAULT_MAX_PLIES: u16 = 200;
const EXPLORATION_C: f64 = 1.41421356;
const ROLLOUT_CAP: u16 = 60;
const PATH_CAPACITY: usize = 256;

pub struct SearchOutput {
    pub visits: Vec<(u8, u32)>,
    /// Legacy ABI hero-perspective action ID returned through the C ABI.
    pub chosen_action_id: u8,
    /// Absolute internal action ID applied through the trusted path.
    pub chosen_absolute_action_id: u8,
    /// Hero-perspective equity of the chosen child:
    /// `q_sum / visits`. NaN if the chosen child has zero visits.
    pub chosen_equity: f64,
    pub ok: bool,
}

/// Legacy smoke entry point retained for the bench/instrumented split.
#[inline(always)]
pub fn select_uct_move(board: &mut MctsRustBoard, seed: u64, sims: u32) -> u8 {
    if board.is_terminal(DEFAULT_MAX_PLIES) {
        return 0;
    }
    let mut scratch = ActionBuffer::new();
    board.legal_actions(&mut scratch, DEFAULT_MAX_PLIES);
    if scratch.is_empty() {
        return 0;
    }
    let pick = (smoke_rollout_action(seed, sims) as usize) % scratch.len();
    let absolute = scratch.get(pick);
    board.apply_action_unchecked(absolute);
    abi_action_from_absolute(prior_side(board.side_to_move), absolute)
}

#[inline(always)]
fn prior_side(after: SideToMove) -> SideToMove {
    match after {
        SideToMove::Hero => SideToMove::Villain,
        SideToMove::Villain => SideToMove::Hero,
    }
}

pub fn run_search(
    start: &MctsRustBoard,
    sims: u32,
    max_plies: u16,
    seed: u64,
) -> SearchOutput {
    let mut out = SearchOutput {
        visits: Vec::new(),
        chosen_action_id: 0,
        chosen_absolute_action_id: 0,
        chosen_equity: f64::NAN,
        ok: true,
    };
    if start.is_terminal(max_plies) {
        out.ok = false;
        return out;
    }
    let search_max_plies = max_plies.min(ROLLOUT_CAP);
    let root_side = start.side_to_move;

    if start.ply >= search_max_plies {
        let mut buffer = ActionBuffer::new();
        start.legal_actions(&mut buffer, max_plies);
        if buffer.is_empty() {
            out.ok = false;
            return out;
        }
        for i in 0..buffer.len() {
            let abs = buffer.get(i);
            out.visits.push((abi_action_from_absolute(root_side, abs), 0));
        }
        out.visits.sort_by_key(|(aid, _)| *aid);
        let first_abs = buffer.get(0);
        out.chosen_absolute_action_id = first_abs;
        out.chosen_action_id = abi_action_from_absolute(root_side, first_abs);
        out.chosen_equity = 0.0;
        return out;
    }

    let mut root_actions = ActionBuffer::new();
    start.legal_actions(&mut root_actions, search_max_plies);
    if root_actions.is_empty() {
        out.ok = false;
        return out;
    }

    let cap = (1usize)
        .saturating_add(root_actions.len())
        .saturating_add((sims as usize).saturating_mul(MAX_LEGAL_ACTIONS))
        .max(32);

    let mut tree: Tree = Tree::with_capacity(cap);
    let root_idx = tree.root();
    {
        let root = tree.node_mut(root_idx);
        root.expanded = 1;
        root.first_child = 1; // children placed contiguously starting at 1
        root.child_count = root_actions.len() as u16;
        root.visits = 1;
    }
    let first = tree.reserve_children(root_actions.len(), root_idx);
    for i in 0..root_actions.len() {
        let child = tree.node_mut(first + i as u32);
        child.action_id = root_actions.get(i);
    }

    let mut sim_seed = seed;
    for i in 0..sims {
        sim_seed = mix(sim_seed, i as u64);
        let _ = descend_iterative(&mut tree, root_idx, start, sim_seed, search_max_plies);
    }

    let root = tree.node(root_idx).clone();
    let mut best_visits = 0u32;
    let mut best_child = root.first_child;
    out.visits.reserve(root.child_count as usize);
    for i in 0..root.child_count {
        let child_idx = root.first_child + i as u32;
        let child = tree.node(child_idx);
        out.visits
            .push((abi_action_from_absolute(root_side, child.action_id), child.visits));
        if child.visits > best_visits {
            best_visits = child.visits;
            best_child = child_idx;
        }
    }
    out.visits.sort_by_key(|(aid, _)| *aid);

    let chosen_node = tree.node(best_child);
    out.chosen_absolute_action_id = chosen_node.action_id;
    out.chosen_action_id = abi_action_from_absolute(root_side, chosen_node.action_id);
    out.chosen_equity = if chosen_node.visits == 0 {
        f64::NAN
    } else {
        chosen_node.q_sum / chosen_node.visits as f64
    };
    out
}

pub fn benchmark_terminal_playouts(
    start: &MctsRustBoard,
    count: u32,
    max_plies: u16,
    seed: u64,
) -> u64 {
    let mut checksum = 0u64;
    let mut current_seed = seed;
    for i in 0..count {
        current_seed = mix(current_seed, i as u64);
        let outcome = rollout_haskell(start, current_seed, max_plies);
        let outcome_key = if outcome > 0.0 {
            0x9e3779b97f4a7c15u64
        } else if outcome < 0.0 {
            0xbf58476d1ce4e5b9u64
        } else {
            0x94d049bb133111ebu64
        };
        checksum ^= mix(current_seed, outcome_key ^ i as u64);
    }
    checksum
}

pub fn benchmark_search_iters(
    start: &MctsRustBoard,
    count: u32,
    max_plies: u16,
    seed: u64,
) -> u64 {
    let result = run_search(start, count, max_plies, seed);
    let mut checksum = seed ^ result.chosen_action_id as u64;
    for (aid, visits) in result.visits {
        checksum ^= ((aid as u64) << 32) ^ visits as u64;
    }
    checksum
}

fn expand(tree: &mut Tree, node_idx: u32, current_state: &MctsRustBoard, max_plies: u16) {
    {
        let node = tree.node(node_idx);
        if node.expanded != 0 {
            return;
        }
    }
    if current_state.is_terminal(max_plies) {
        let n = tree.node_mut(node_idx);
        n.expanded = 1;
        n.terminal = 1;
        return;
    }
    let mut buffer = ActionBuffer::new();
    current_state.legal_actions(&mut buffer, max_plies);
    if buffer.is_empty() {
        let n = tree.node_mut(node_idx);
        n.expanded = 1;
        n.terminal = 1;
        return;
    }
    let n_moves = buffer.len();
    let first = tree.reserve_children(n_moves, node_idx);
    for i in 0..n_moves {
        let child = tree.node_mut(first + i as u32);
        child.action_id = buffer.get(i);
    }
    let parent = tree.node_mut(node_idx);
    parent.expanded = 1;
    parent.first_child = first;
    parent.child_count = n_moves as u16;
}

/// Sprint 6.10 iterative descent: materialize `MctsRustBoard` on the
/// stack and walk a fixed-capacity `path` buffer. Mirrors backend (iii)
/// `cpp-functional/engine/search.cpp::descend_iterative`.
fn descend_iterative(
    tree: &mut Tree,
    root_idx: u32,
    root_state: &MctsRustBoard,
    seed: u64,
    max_plies: u16,
) -> f64 {
    let mut current = root_state.clone();
    let mut node_idx = root_idx;
    let mut current_seed = seed;
    let mut path = [0u32; PATH_CAPACITY];
    let mut path_size: usize = 0;
    let mut outcome: f64;

    loop {
        if path_size < PATH_CAPACITY {
            path[path_size] = node_idx;
            path_size += 1;
        }
        if let Some(t) = terminal_outcome(&current, max_plies) {
            outcome = t;
            break;
        }
        let visits = tree.node(node_idx).visits;
        if visits == 0 {
            outcome = rollout_haskell(&current, current_seed, max_plies);
            break;
        }
        if tree.node(node_idx).expanded == 0 {
            expand(tree, node_idx, &current, max_plies);
        }
        let n = tree.node(node_idx);
        if n.terminal == 1 || n.child_count == 0 {
            outcome = 0.0;
            break;
        }
        let parent_visits_after = visits.saturating_add(1);
        let child_offset = select_best_ucb_offset(tree, node_idx, parent_visits_after);
        let chosen = tree.node(node_idx).first_child + child_offset;
        let absolute = tree.node(chosen).action_id;
        current.apply_action_unchecked(absolute);
        current_seed = mix(current_seed, child_offset as u64 + 1);
        node_idx = chosen;
    }

    for i in 0..path_size {
        add_value(tree, path[i], outcome);
    }
    outcome
}

#[inline]
fn add_value(tree: &mut Tree, node_idx: u32, value: f64) {
    let node = tree.node_mut(node_idx);
    node.visits = node.visits.saturating_add(1);
    node.q_sum += value;
}

#[inline]
fn select_best_ucb_offset(tree: &Tree, parent_idx: u32, parent_visits_after: u32) -> u32 {
    let p = tree.node(parent_idx);
    let first = p.first_child;
    let n = p.child_count;
    let log_parent = (parent_visits_after.max(1) as f64).ln();
    let mut best_score = f64::NEG_INFINITY;
    let mut best_offset = 0u32;
    for i in 0..n {
        let child_idx = first + i as u32;
        let child = tree.node(child_idx);
        if child.visits == 0 {
            return i as u32;
        }
        let mean = child.q_sum / child.visits as f64;
        let exploration = EXPLORATION_C * (log_parent / child.visits as f64).sqrt();
        let score = mean + exploration;
        if score > best_score {
            best_score = score;
            best_offset = i as u32;
        }
    }
    best_offset
}

#[inline]
fn rollout_haskell(start: &MctsRustBoard, seed: u64, max_plies: u16) -> f64 {
    let mut board = start.clone();
    let mut current_seed = seed;
    let mut buffer = ActionBuffer::new();
    for step in 0..max_plies {
        if let Some(outcome) = terminal_outcome(&board, max_plies) {
            return outcome;
        }
        board.legal_actions(&mut buffer, u16::MAX);
        if buffer.is_empty() {
            return 0.0;
        }
        let signed_draw = (current_seed ^ step as u64) as i64;
        let n = buffer.len() as i64;
        let mut pick = signed_draw % n;
        if pick < 0 {
            pick += n;
        }
        let action = buffer.get(pick as usize);
        board.apply_action_unchecked(action);
        current_seed = mix(current_seed, step as u64);
    }
    0.0
}

#[inline]
fn terminal_outcome(board: &MctsRustBoard, max_plies: u16) -> Option<f64> {
    if board.hero_wins() {
        Some(1.0)
    } else if board.villain_wins() {
        Some(-1.0)
    } else if board.ply >= max_plies {
        Some(0.0)
    } else {
        None
    }
}

#[inline]
fn mix(master_seed: u64, index: u64) -> u64 {
    splitmix64(master_seed.wrapping_add(0x9e3779b97f4a7c15u64.wrapping_mul(index + 1)))
}

#[inline]
fn splitmix64(input: u64) -> u64 {
    let z1 = input.wrapping_add(0x9e3779b97f4a7c15);
    let z2 = (z1 ^ (z1 >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    let z3 = (z2 ^ (z2 >> 27)).wrapping_mul(0x94d049bb133111eb);
    z3 ^ (z3 >> 31)
}
