// Arena MCTS tree with flat children per Sprint 6.3.
// Layout matches the C++ steelman (Sprint 5.1):
//   * `Vec<Node>` arena indexed by `u32`.
//   * Each parent records `first_child : u32` and `child_count : u16`.
//   * No per-node `Vec`; children live in a contiguous arena range.
//   * `#[repr(C)]` + `#[repr(align(64))]` to align with C++'s
//     `alignas(64)` arena base when sharing layout assumptions across
//     the FFI is meaningful (the Haskell side never inspects this).

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

    #[inline]
    pub fn reserve_children(&mut self, count: usize, parent: u32, child_ply: u16) -> u32 {
        let start = self.nodes.len() as u32;
        for i in 0..count {
            self.nodes.push(Node {
                parent,
                first_child: NO_INDEX,
                child_count: 0,
                action_id: i as u8,
                expanded: 0,
                terminal: 0,
                visits: 0,
                q_sum: 0.0,
                ply_count: child_ply,
            });
        }
        start
    }
}
