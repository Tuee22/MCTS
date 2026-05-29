// Action-only arena MCTS tree per Sprint 6.10 backend (iv) hot-path
// alignment. Mirrors backend (iii) Sprint 6.9 and backend (ii) Sprint
// 5.7 `arena.hpp`:
//   * `Vec<Node>` arena indexed by `u32`.
//   * Each parent records `first_child : u32` and `child_count : u16`.
//   * Nodes carry only the action from their parent plus hot visit/value
//     fields. Board state is materialized on the descent stack in
//     `search.rs::descend_iterative`.
//   * No parallel `Vec<MctsRustBoard>`; the prior secondary state vector
//     was the dominant per-node footprint while `MctsRustBoard` carried
//     the visit cache (Sprint 6.8 baseline). Sprint 6.10 removed the
//     cache from the search board AND the per-node state copy.

pub const NO_INDEX: u32 = u32::MAX;

#[derive(Clone)]
pub struct Node {
    pub parent: u32,
    pub first_child: u32,
    pub child_count: u16,
    pub action_id: u8,
    pub expanded: u8,
    pub terminal: u8,
    pub visits: u32,
    pub q_sum: f64,
}

impl Node {
    #[inline(always)]
    pub fn root() -> Self {
        Self {
            parent: NO_INDEX,
            first_child: NO_INDEX,
            child_count: 0,
            action_id: u8::MAX,
            expanded: 0,
            terminal: 0,
            visits: 0,
            q_sum: 0.0,
        }
    }

    #[inline(always)]
    fn child_of(parent: u32) -> Self {
        Self {
            parent,
            first_child: NO_INDEX,
            child_count: 0,
            action_id: u8::MAX,
            expanded: 0,
            terminal: 0,
            visits: 0,
            q_sum: 0.0,
        }
    }
}

pub struct Tree {
    nodes: Vec<Node>,
}

impl Tree {
    #[inline(always)]
    pub fn with_capacity(capacity: usize) -> Self {
        let mut nodes = Vec::with_capacity(capacity);
        nodes.push(Node::root());
        Self { nodes }
    }

    #[inline(always)]
    pub fn root(&self) -> u32 {
        0
    }

    #[allow(dead_code)]
    #[inline(always)]
    pub fn len(&self) -> usize {
        self.nodes.len()
    }

    #[inline(always)]
    pub fn node(&self, idx: u32) -> &Node {
        &self.nodes[idx as usize]
    }

    #[inline(always)]
    pub fn node_mut(&mut self, idx: u32) -> &mut Node {
        &mut self.nodes[idx as usize]
    }

    /// Reserve `count` contiguous child slots for `parent` and return
    /// the arena index of the first child. Children are
    /// default-initialized; the caller fills `action_id`.
    pub fn reserve_children(&mut self, count: usize, parent: u32) -> u32 {
        let start = self.nodes.len() as u32;
        for _ in 0..count {
            self.nodes.push(Node::child_of(parent));
        }
        start
    }
}
