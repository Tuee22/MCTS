// Arena-based UCT search for backend (iv) over the real Corridors
// game per Sprint 6.3. The MCTS algorithm is a flat-children arena
// search with first-unvisited-child expansion and UCB1 selection.

use crate::board::MctsRustBoard;
use crate::rollout::{rollout_value, smoke_rollout_action};
use crate::tree::{NO_INDEX, Tree};
use crate::xoshiro256pp::Xoshiro256pp;

const DEFAULT_MAX_PLIES: u16 = 200;
const EXPLORATION_C: f64 = 1.4;

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
    let cap = (sims as usize).saturating_mul(2).max(256);
    let mut tree: Tree<MctsRustBoard> = Tree::with_capacity_state(cap, start.clone());
    let root_idx = tree.root();
    {
        let node = tree.node_mut(root_idx);
        node.ply_count = start.ply;
    }
    expand(&mut tree, root_idx, max_plies);
    let root_after = tree.node(root_idx);
    if root_after.terminal == 1 || root_after.child_count == 0 {
        out.ok = false;
        return out;
    }
    let mut rng = Xoshiro256pp::new(seed);
    for _ in 0..sims {
        let mut idx = root_idx;
        let leaf_idx = loop {
            let node = tree.node(idx);
            if node.terminal == 1 {
                break idx;
            }
            if node.expanded == 0 {
                expand(&mut tree, idx, max_plies);
                let n = tree.node(idx);
                if n.terminal == 1 || n.child_count == 0 {
                    break idx;
                }
            }
            let n = tree.node(idx);
            let first = n.first_child;
            let count = n.child_count;
            let mut chosen = NO_INDEX;
            for i in 0..count {
                let child = tree.node(first + i as u32);
                if child.visits == 0 {
                    chosen = first + i as u32;
                    break;
                }
            }
            if chosen != NO_INDEX {
                idx = chosen;
                break idx;
            }
            idx = select_best_ucb(&tree, idx);
        };
        let leaf_state = tree.state(leaf_idx).clone();
        let value = rollout_value(&leaf_state, max_plies, &mut rng);
        backprop(&mut tree, leaf_idx, value);
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
        -(chosen_node.q_sum / chosen_node.visits as f64)
    };
    out
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

#[inline]
fn select_best_ucb(tree: &Tree<MctsRustBoard>, parent_idx: u32) -> u32 {
    let p = tree.node(parent_idx);
    let first = p.first_child;
    let n = p.child_count;
    let parent_visits = (p.visits as f64).max(1.0);
    let log_parent = parent_visits.ln();
    let mut best_score = f64::NEG_INFINITY;
    let mut best = first;
    for i in 0..n {
        let child_idx = first + i as u32;
        let child = tree.node(child_idx);
        let score = if child.visits == 0 {
            1.0e100 - (i as f64)
        } else {
            let mean = -(child.q_sum / child.visits as f64);
            let exploration = EXPLORATION_C * (log_parent / child.visits as f64).sqrt();
            mean + exploration
        };
        if score > best_score {
            best_score = score;
            best = child_idx;
        }
    }
    best
}

#[inline]
fn backprop(tree: &mut Tree<MctsRustBoard>, leaf_idx: u32, leaf_value: f64) {
    let mut idx = leaf_idx;
    let mut value = leaf_value;
    while idx != NO_INDEX {
        let node = tree.node_mut(idx);
        node.visits = node.visits.saturating_add(1);
        node.q_sum += value;
        let parent = node.parent;
        value = -value;
        idx = parent;
    }
}
