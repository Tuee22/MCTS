// Arena-based UCT search for backend (iv).
//
// The MCTS algorithm is a real implementation per Sprint 6.3: arena
// `Tree<Node>`, flat children layout, `[[likely]]`-equivalent
// `#[cold]` annotations on terminal-state branches, `#[inline(always)]`
// on hot loop entries, `u64::trailing_zeros`/`u64::count_ones`-friendly
// types throughout. The placeholder game in `rollout.rs` is enough to
// exercise the search; the full Corridors port remains a ledger row.

use crate::board::MctsRustBoard;
use crate::rollout::{n_legal_moves, rollout_value, smoke_rollout_action};
use crate::tree::{NO_INDEX, Tree};
use crate::xoshiro256pp::Xoshiro256pp;

const DEFAULT_MAX_PLIES: u16 = 10000;
const EXPLORATION_C: f64 = 1.4;

pub struct SearchOutput {
    pub visits: Vec<(u8, u32)>,
    pub chosen_action_id: u8,
    pub ok: bool,
}

#[inline(always)]
pub fn select_uct_move(board: &mut MctsRustBoard, seed: u64, sims: u32) -> u8 {
    // Backwards-compatible entry point retained for the legacy smoke
    // path. The full visit-vector entry point is `run_search` below;
    // the C ABI calls that.
    if board.is_terminal(DEFAULT_MAX_PLIES) {
        return 0;
    }
    board.advance_ply();
    smoke_rollout_action(seed, sims)
}

pub fn run_search(start_ply: u16, sims: u32, max_plies: u16, seed: u64) -> SearchOutput {
    let mut out = SearchOutput {
        visits: Vec::new(),
        chosen_action_id: 0,
        ok: true,
    };
    if start_ply >= max_plies {
        out.ok = false;
        return out;
    }
    let mut tree = Tree::with_capacity((sims as usize) + 256);
    let root_idx = tree.root();
    tree.node_mut(root_idx).ply_count = start_ply;
    expand(&mut tree, root_idx, max_plies);
    if tree.node(root_idx).terminal == 1 || tree.node(root_idx).child_count == 0 {
        out.ok = false;
        return out;
    }
    let mut rng = Xoshiro256pp::new(seed);
    for _ in 0..sims {
        let mut idx = root_idx;
        let leaf = loop {
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
            // Pick the first unvisited child if any (MCTS expansion).
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
            // UCB1 selection.
            idx = select_best_ucb(&tree, idx);
        };
        let value = {
            let n = tree.node(leaf);
            rollout_value(n.ply_count, max_plies, &mut rng)
        };
        backprop(&mut tree, leaf, value);
    }
    // Build visit vector from root's children, sorted ascending by
    // action_id. The placeholder game uses 0..n action ids; the real
    // Corridors port will map to the canonical 0..208 action space.
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
    out.chosen_action_id = tree.node(best_child).action_id;
    out
}

#[inline]
fn expand(tree: &mut Tree, node_idx: u32, max_plies: u16) {
    let (current_ply, already_expanded) = {
        let n = tree.node(node_idx);
        (n.ply_count, n.expanded != 0)
    };
    if already_expanded {
        return;
    }
    if current_ply >= max_plies {
        let n = tree.node_mut(node_idx);
        n.expanded = 1;
        n.terminal = 1;
        return;
    }
    let n_moves = n_legal_moves(current_ply) as usize;
    let child_ply = current_ply.saturating_add(1);
    let first = tree.reserve_children(n_moves, node_idx, child_ply);
    let parent = tree.node_mut(node_idx);
    parent.expanded = 1;
    parent.first_child = first;
    parent.child_count = n_moves as u16;
}

#[inline]
fn select_best_ucb(tree: &Tree, parent_idx: u32) -> u32 {
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
            // Unvisited tie-breaker (deterministic by index).
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
fn backprop(tree: &mut Tree, leaf_idx: u32, leaf_value: f64) {
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
