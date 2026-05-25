// Arena-based UCT search for backend (iv) over the real Corridors
// game per Sprint 6.3. The MCTS algorithm is a flat-children arena
// search with first-unvisited-child expansion and UCB1 selection.

use crate::board::MctsRustBoard;
use crate::board::flip_action_id;
use crate::rollout::smoke_rollout_action;
use crate::tree::Tree;

const DEFAULT_MAX_PLIES: u16 = 200;
const EXPLORATION_C: f64 = 1.41421356;
const ROLLOUT_CAP: u16 = 60;

pub struct SearchOutput {
    pub visits: Vec<(u8, u32)>,
    pub chosen_action_id: u8,
    /// Parent-perspective equity of the chosen child:
    /// `-child.q_sum / child.visits` (the search Q is stored from the
    /// chosen child's perspective; we negate to express the value of
    /// the chosen action from the parent's perspective). NaN if the
    /// chosen child has zero visits.
    pub chosen_equity: f64,
    pub ok: bool,
}

/// Legacy smoke entry point retained for the bench/instrumented split.
#[inline(always)]
pub fn select_uct_move(board: &mut MctsRustBoard, seed: u64, sims: u32) -> u8 {
    if board.is_terminal(DEFAULT_MAX_PLIES) {
        return 0;
    }
    let mut scratch: Vec<u8> = Vec::with_capacity(160);
    board.legal_actions(&mut scratch, DEFAULT_MAX_PLIES);
    if scratch.is_empty() {
        return 0;
    }
    let pick = (smoke_rollout_action(seed, sims) as usize) % scratch.len();
    let action = scratch[pick];
    let _ = board.apply_action_flip(action);
    action
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
        chosen_equity: f64::NAN,
        ok: true,
    };
    if start.is_terminal(max_plies) {
        out.ok = false;
        return out;
    }
    let search_max_plies = max_plies.min(ROLLOUT_CAP);
    if start.ply >= search_max_plies {
        let mut buffer: Vec<u8> = Vec::with_capacity(160);
        start.legal_actions(&mut buffer, max_plies);
        if buffer.is_empty() {
            out.ok = false;
            return out;
        }
        out.visits = buffer.into_iter().map(|aid| (aid, 0)).collect();
        out.chosen_action_id = out.visits[0].0;
        out.chosen_equity = 0.0;
        return out;
    }
    let cap = (sims as usize).saturating_mul(2).max(256);
    let mut tree: Tree<MctsRustBoard> = Tree::with_capacity_state(cap, start.clone());
    let root_idx = tree.root();
    {
        let node = tree.node_mut(root_idx);
        node.ply_count = start.ply;
    }
    expand(&mut tree, root_idx, search_max_plies);
    let root_after = tree.node(root_idx);
    if root_after.terminal == 1 || root_after.child_count == 0 {
        out.ok = false;
        return out;
    }
    {
        let root = tree.node_mut(root_idx);
        root.visits = 1;
    }
    let mut sim_seed = seed;
    for i in 0..sims {
        sim_seed = mix(sim_seed, i as u64);
        let _ = descend(&mut tree, root_idx, sim_seed, search_max_plies);
    }
    let root = tree.node(root_idx).clone();
    let mut best_visits = 0u32;
    let mut best_child = root.first_child;
    out.visits.reserve(root.child_count as usize);
    for i in 0..root.child_count {
        let child_idx = root.first_child + i as u32;
        let child = tree.node(child_idx);
        out.visits.push((child.action_id, child.visits));
        if child.visits > best_visits {
            best_visits = child.visits;
            best_child = child_idx;
        }
    }
    out.visits.sort_by_key(|(aid, _)| *aid);
    let chosen_node = tree.node(best_child);
    out.chosen_action_id = chosen_node.action_id;
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

fn expand(tree: &mut Tree<MctsRustBoard>, node_idx: u32, max_plies: u16) {
    let (current_state, already_expanded) = {
        let n = tree.node(node_idx);
        (tree.state(node_idx).clone(), n.expanded != 0)
    };
    if already_expanded {
        return;
    }
    if current_state.is_terminal(max_plies) {
        let n = tree.node_mut(node_idx);
        n.expanded = 1;
        n.terminal = 1;
        return;
    }
    let mut buffer: Vec<u8> = Vec::with_capacity(160);
    current_state.legal_actions(&mut buffer, max_plies);
    if buffer.is_empty() {
        let n = tree.node_mut(node_idx);
        n.expanded = 1;
        n.terminal = 1;
        return;
    }
    let n_moves = buffer.len();
    let first = tree.reserve_children_with(n_moves, node_idx, |child_index| {
        let action_id = buffer[child_index];
        let mut child_state = current_state.clone();
        let _ = child_state.apply_action_flip(action_id);
        (action_id, child_state)
    });
    let parent = tree.node_mut(node_idx);
    parent.expanded = 1;
    parent.first_child = first;
    parent.child_count = n_moves as u16;
}

fn descend(tree: &mut Tree<MctsRustBoard>, node_idx: u32, seed: u64, max_plies: u16) -> f64 {
    let state = tree.state(node_idx).clone();
    if let Some(outcome) = terminal_outcome(&state, max_plies) {
        add_value(tree, node_idx, outcome);
        return outcome;
    }
    let visits = tree.node(node_idx).visits;
    if visits == 0 {
        let outcome = rollout_haskell(&state, seed, max_plies);
        add_value(tree, node_idx, outcome);
        return outcome;
    }
    if tree.node(node_idx).expanded == 0 {
        expand(tree, node_idx, max_plies);
    }
    let node = tree.node(node_idx);
    if node.terminal == 1 || node.child_count == 0 {
        let outcome = 0.0;
        add_value(tree, node_idx, outcome);
        return outcome;
    }
    let parent_visits_after = visits.saturating_add(1);
    let child_offset = select_best_ucb_offset(tree, node_idx, parent_visits_after);
    let child_idx = tree.node(node_idx).first_child + child_offset;
    let child_seed = mix(seed, child_offset as u64 + 1);
    let outcome = descend(tree, child_idx, child_seed, max_plies);
    add_value(tree, node_idx, outcome);
    outcome
}

#[inline]
fn add_value(tree: &mut Tree<MctsRustBoard>, node_idx: u32, value: f64) {
    let node = tree.node_mut(node_idx);
    node.visits = node.visits.saturating_add(1);
    node.q_sum += value;
}

#[inline]
fn select_best_ucb_offset(
    tree: &Tree<MctsRustBoard>,
    parent_idx: u32,
    parent_visits_after: u32,
) -> u32 {
    let parent_state = tree.state(parent_idx);
    let p = tree.node(parent_idx);
    let first = p.first_child;
    let n = p.child_count;
    let log_parent = (parent_visits_after.max(1) as f64).ln();
    let mut best_score = f64::NEG_INFINITY;
    let mut best_offset = 0u32;
    let mut best_key = u8::MAX;
    for i in 0..n {
        let child_idx = first + i as u32;
        let child = tree.node(child_idx);
        let score = if child.visits == 0 {
            1.0e30
        } else {
            let mean = child.q_sum / child.visits as f64;
            let exploration = EXPLORATION_C * (log_parent / child.visits as f64).sqrt();
            mean + exploration
        };
        let key = canonical_key(parent_state, child.action_id);
        if score > best_score || (score == best_score && key < best_key) {
            best_score = score;
            best_offset = i as u32;
            best_key = key;
        }
    }
    best_offset
}

#[inline]
fn rollout_haskell(start: &MctsRustBoard, seed: u64, max_plies: u16) -> f64 {
    let mut board = start.clone();
    let mut current_seed = seed;
    let mut buffer: Vec<u8> = Vec::with_capacity(160);
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
        let action = buffer[pick as usize];
        let _ = board.apply_action_flip(action);
        current_seed = mix(current_seed, step as u64);
    }
    0.0
}

#[inline]
fn terminal_outcome(board: &MctsRustBoard, max_plies: u16) -> Option<f64> {
    if board.hero_wins() {
        Some(if board.ply % 2 == 0 { 1.0 } else { -1.0 })
    } else if board.villain_wins() {
        Some(if board.ply % 2 == 0 { -1.0 } else { 1.0 })
    } else if board.ply >= max_plies {
        Some(0.0)
    } else {
        None
    }
}

#[inline]
fn canonical_key(board: &MctsRustBoard, action_id: u8) -> u8 {
    if board.ply % 2 == 0 {
        action_id
    } else {
        flip_action_id(action_id)
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
