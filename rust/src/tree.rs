#[derive(Clone, Copy)]
pub struct Node {
    pub parent: u32,
    pub first_child: u32,
    pub child_count: u16,
    pub action_id: u8,
    pub visits: u32,
    pub value_sum: f32,
}

impl Node {
    #[inline(always)]
    pub fn root() -> Self {
        Self {
            parent: u32::MAX,
            first_child: u32::MAX,
            child_count: 0,
            action_id: u8::MAX,
            visits: 0,
            value_sum: 0.0,
        }
    }
}

pub struct Tree {
    nodes: Vec<Node>,
}

impl Tree {
    #[inline(always)]
    pub fn with_root() -> Self {
        Self {
            nodes: vec![Node::root()],
        }
    }

    #[inline(always)]
    pub fn len(&self) -> usize {
        self.nodes.len()
    }

    #[inline(always)]
    pub fn root_checksum(&self) -> u32 {
        let node = self.nodes[0];
        node.parent
            ^ node.first_child
            ^ node.child_count as u32
            ^ node.action_id as u32
            ^ node.visits
            ^ node.value_sum.to_bits()
    }
}
