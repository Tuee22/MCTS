// Arena MCTS tree with flat children per Sprint 6.3.
// Layout matches the C++ steelman:
//   * `Vec<Node>` arena indexed by `u32`.
//   * `Vec<S>` parallel array carrying per-node board state.
//   * Each parent records `first_child : u32` and `child_count : u16`.
//   * No per-node `Vec`; children live in a contiguous arena range.

pub const NO_INDEX: u32 = u32::MAX;

#[repr(C, align(64))]
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
    pub ply_count: u16,
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
            ply_count: 0,
        }
    }
}

pub struct Tree<S: Clone> {
    nodes: Vec<Node>,
    states: Vec<S>,
}

impl<S: Clone> Tree<S> {
    #[inline(always)]
    pub fn with_capacity_state(capacity: usize, root_state: S) -> Self {
        let mut nodes = Vec::with_capacity(capacity);
        let mut states = Vec::with_capacity(capacity);
        nodes.push(Node::root());
        states.push(root_state);
        Self { nodes, states }
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

    #[inline(always)]
    pub fn state(&self, idx: u32) -> &S {
        &self.states[idx as usize]
    }

    /// Reserve `count` consecutive child slots for `parent`. The
    /// builder closure produces `(action_id, state)` for each child
    /// index in [0, count). Returns the arena index of the first
    /// child.
    pub fn reserve_children_with<F>(&mut self, count: usize, parent: u32, mut build: F) -> u32
    where
        F: FnMut(usize) -> (u8, S),
    {
        let start = self.nodes.len() as u32;
        let parent_ply = self.nodes[parent as usize].ply_count;
        for i in 0..count {
            let (action_id, state) = build(i);
            self.nodes.push(Node {
                parent,
                first_child: NO_INDEX,
                child_count: 0,
                action_id,
                expanded: 0,
                terminal: 0,
                visits: 0,
                q_sum: 0.0,
                ply_count: parent_ply.saturating_add(1),
            });
            self.states.push(state);
        }
        start
    }
}
