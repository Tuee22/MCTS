// Backend (iv) Corridors board state with bitfield walls and bit-parallel
// escapability. Sprint 6.10 mirrors the Sprint 6.9 backend (iii) hot-path
// shape inside the Rust ownership idioms:
//   * An absolute `SideToMove` field replaces the per-transition full-state
//     `flipped()` coordinate/wall reversal. `apply_action` toggles the field
//     and increments `ply`.
//   * A reusable `BlockMasks` value is precomputed once per `legal_actions`
//     call and extended additively via `add_wall_to_masks` per candidate.
//     The prior 196-byte clone in `wall_placement_legal` is gone.
//   * `path_exists_with_masks` runs a bidirectional bit-parallel BFS over
//     `u128`, mirroring backend (ii) Sprint `5.8`.
//   * The 169-byte `last_visit_*` cache is relocated off the search-state
//     struct (`MctsRustBoard`) onto the opaque handle (`RustBoardHandle`)
//     in `c_abi.rs`. The search hot path no longer carries the cache through
//     every clone / per-rollout copy.
//
// Action ID encoding (canonical, matches Haskell engine
// `MCTS.Types.actionId` exactly):
//   Pawn(x, y)  -> y * 9 + x          in [0..80]
//   WallH(x, y) -> 81  + y * 8 + x    in [81..144]
//   WallV(x, y) -> 145 + y * 8 + x    in [145..208]
//
// Action IDs at the C ABI boundary use the legacy hero-perspective
// convention. Translation between the absolute internal frame and the ABI
// frame is owned by `abi_action_from_absolute` / `absolute_action_from_abi`
// and applied at the FFI shim.

pub const BOARD_SIZE: u8 = 9;
pub const STARTING_WALLS: u8 = 10;
pub const MAX_LEGAL_ACTIONS: usize = 16;
const NO_ACTION: u8 = 255;
const VALID_CELLS: u128 = (1u128 << 81) - 1;
const RIGHT_SOURCE_MASK: u128 = source_mask_right();
const LEFT_SOURCE_MASK: u128 = source_mask_left();

#[derive(Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum SideToMove {
    Hero = 0,
    Villain = 1,
}

/// Flip a canonical action id (0..208) through the 180-degree
/// rotation. Pawns reflect through 80; H/V walls through 225/353.
#[inline]
pub fn flip_action_id(raw: u8) -> u8 {
    if raw <= 80 {
        80 - raw
    } else if raw <= 144 {
        225 - raw
    } else if raw <= 208 {
        (353u16 - raw as u16) as u8
    } else {
        raw
    }
}

/// Translate an internal absolute action id to the legacy ABI
/// hero-perspective convention used by the C ABI shim.
#[inline]
pub fn abi_action_from_absolute(side: SideToMove, action_id: u8) -> u8 {
    if matches!(side, SideToMove::Hero) {
        flip_action_id(action_id)
    } else {
        action_id
    }
}

/// Inverse of `abi_action_from_absolute`: translate a legacy-ABI action
/// id (hero-perspective) into the absolute internal frame.
#[inline]
pub fn absolute_action_from_abi(side: SideToMove, action_id: u8) -> u8 {
    if matches!(side, SideToMove::Hero) {
        flip_action_id(action_id)
    } else {
        action_id
    }
}

/// Bit at (x, y) for x, y in [0..7] (8x8 wall grid).
#[inline(always)]
fn wall_bit(x: u8, y: u8) -> u64 {
    1u64 << (y * 8 + x)
}

#[inline(always)]
fn wall_test(bits: u64, x: u8, y: u8) -> bool {
    if x > 7 || y > 7 {
        return false;
    }
    (bits & wall_bit(x, y)) != 0
}

#[derive(Clone)]
pub struct ActionBuffer {
    items: [u8; MAX_LEGAL_ACTIONS],
    len: usize,
}

impl ActionBuffer {
    #[inline(always)]
    pub fn new() -> Self {
        Self {
            items: [0; MAX_LEGAL_ACTIONS],
            len: 0,
        }
    }

    #[inline(always)]
    pub fn clear(&mut self) {
        self.len = 0;
    }

    #[inline(always)]
    pub fn push(&mut self, action_id: u8) {
        if self.len < MAX_LEGAL_ACTIONS {
            self.items[self.len] = action_id;
            self.len += 1;
        }
    }

    #[inline(always)]
    pub fn len(&self) -> usize {
        self.len
    }

    #[inline(always)]
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    #[inline(always)]
    pub fn get(&self, idx: usize) -> u8 {
        self.items[idx]
    }

    #[inline(always)]
    pub fn as_slice(&self) -> &[u8] {
        &self.items[..self.len]
    }
}

/// Precomputed wall-block masks. Mirrors backend (iii)
/// `cpp-functional/engine/state.hpp::BlockMasks` Sprint 6.9. Computed
/// once per `legal_actions` call via `block_masks()` and additively
/// extended per wall candidate via `add_wall_to_masks()`.
#[derive(Clone, Copy)]
pub struct BlockMasks {
    pub up: u128,
    pub down: u128,
    pub right: u128,
    pub left: u128,
}

impl BlockMasks {
    #[inline(always)]
    pub fn empty() -> Self {
        Self { up: 0, down: 0, right: 0, left: 0 }
    }
}

/// Compact value-state Corridors board used by the Rust hot path.
/// Sprint 6.10: no `last_visit_*` cache here — it lives on the C ABI
/// handle in `c_abi.rs`.
#[derive(Clone)]
pub struct MctsRustBoard {
    pub hero_x: u8,
    pub hero_y: u8,
    pub villain_x: u8,
    pub villain_y: u8,
    pub hero_walls_remaining: u8,
    pub villain_walls_remaining: u8,
    pub walls_h: u64,
    pub walls_v: u64,
    pub ply: u16,
    pub last_action: u8,
    pub side_to_move: SideToMove,
}

impl MctsRustBoard {
    #[inline(always)]
    pub fn new() -> Self {
        Self {
            hero_x: 4,
            hero_y: 0,
            villain_x: 4,
            villain_y: BOARD_SIZE - 1,
            hero_walls_remaining: STARTING_WALLS,
            villain_walls_remaining: STARTING_WALLS,
            walls_h: 0,
            walls_v: 0,
            ply: 0,
            last_action: NO_ACTION,
            side_to_move: SideToMove::Hero,
        }
    }

    #[inline(always)]
    pub fn hero_wins(&self) -> bool {
        self.hero_y == BOARD_SIZE - 1
    }

    #[inline(always)]
    pub fn villain_wins(&self) -> bool {
        self.villain_y == 0
    }

    #[inline(always)]
    pub fn is_terminal(&self, max_plies: u16) -> bool {
        self.hero_wins() || self.villain_wins() || self.ply >= max_plies
    }

    /// True if the edge between two Manhattan neighbours is blocked
    /// by a wall.
    #[inline]
    fn edge_blocked(&self, x1: u8, y1: u8, x2: u8, y2: u8) -> bool {
        if x1 == x2 && y1.abs_diff(y2) == 1 {
            let y = y1.min(y2);
            let left = if x1 == 0 {
                false
            } else {
                wall_test(self.walls_h, x1 - 1, y)
            };
            let right = wall_test(self.walls_h, x1, y);
            left || right
        } else if y1 == y2 && x1.abs_diff(x2) == 1 {
            let x = x1.min(x2);
            let down = if y1 == 0 {
                false
            } else {
                wall_test(self.walls_v, x, y1 - 1)
            };
            let up = wall_test(self.walls_v, x, y1);
            down || up
        } else {
            false
        }
    }

    #[inline(always)]
    fn walls_remaining_for(&self, side: SideToMove) -> u8 {
        match side {
            SideToMove::Hero => self.hero_walls_remaining,
            SideToMove::Villain => self.villain_walls_remaining,
        }
    }

    #[inline(always)]
    fn decrement_current_walls(&mut self) {
        match self.side_to_move {
            SideToMove::Hero => {
                if self.hero_walls_remaining > 0 {
                    self.hero_walls_remaining -= 1;
                }
            }
            SideToMove::Villain => {
                if self.villain_walls_remaining > 0 {
                    self.villain_walls_remaining -= 1;
                }
            }
        }
    }

    /// Precompute the four-direction wall-block masks for the current
    /// `(walls_h, walls_v)` configuration. The result is reused across
    /// every wall candidate in `legal_actions` (Sprint 6.10), replacing
    /// the prior per-candidate 196-byte board clone in
    /// `wall_placement_legal`.
    #[inline]
    pub fn block_masks(&self) -> BlockMasks {
        let mut masks = BlockMasks::empty();
        let mut h = self.walls_h;
        while h != 0 {
            let idx = h.trailing_zeros() as u8;
            h &= h - 1;
            let x = idx % 8;
            let y = idx / 8;
            masks.up |= cell_bit(x, y) | cell_bit(x + 1, y);
            masks.down |= cell_bit(x, y + 1) | cell_bit(x + 1, y + 1);
        }
        let mut v = self.walls_v;
        while v != 0 {
            let idx = v.trailing_zeros() as u8;
            v &= v - 1;
            let x = idx % 8;
            let y = idx / 8;
            masks.right |= cell_bit(x, y) | cell_bit(x, y + 1);
            masks.left |= cell_bit(x + 1, y) | cell_bit(x + 1, y + 1);
        }
        masks
    }

    #[inline(always)]
    pub fn add_wall_to_masks(action_id: u8, mut masks: BlockMasks) -> BlockMasks {
        if action_id <= 144 {
            let n = action_id - 81;
            let x = n % 8;
            let y = n / 8;
            masks.up |= cell_bit(x, y) | cell_bit(x + 1, y);
            masks.down |= cell_bit(x, y + 1) | cell_bit(x + 1, y + 1);
        } else {
            let n = action_id - 145;
            let x = n % 8;
            let y = n / 8;
            masks.right |= cell_bit(x, y) | cell_bit(x, y + 1);
            masks.left |= cell_bit(x + 1, y) | cell_bit(x + 1, y + 1);
        }
        masks
    }

    /// Sprint 6.10: bidirectional bit-parallel BFS. Two simultaneous
    /// frontiers (start cell and goal row) expand under the same
    /// four-direction shift+mask kernel; the function returns true on
    /// the first intersection. Mirrors backend (iii) Sprint 6.9 and
    /// backend (ii) Sprint 5.8.
    #[inline]
    pub fn path_exists_with_masks(&self, hero_side: bool, masks: &BlockMasks) -> bool {
        let (start_x, start_y, goal_y) = if hero_side {
            (self.hero_x, self.hero_y, BOARD_SIZE - 1)
        } else {
            (self.villain_x, self.villain_y, 0u8)
        };
        if start_y == goal_y {
            return true;
        }
        let mut start_front = cell_bit(start_x, start_y);
        let mut start_visit = start_front;
        let mut goal_front = row_mask(goal_y);
        let mut goal_visit = goal_front;
        if (start_front & goal_visit) != 0 {
            return true;
        }
        while start_front != 0 && goal_front != 0 {
            {
                let up = ((start_front & !masks.up) << 9) & VALID_CELLS;
                let down = (start_front & !masks.down) >> 9;
                let right = ((start_front & RIGHT_SOURCE_MASK & !masks.right) << 1) & VALID_CELLS;
                let left = (start_front & LEFT_SOURCE_MASK & !masks.left) >> 1;
                let next = (up | down | right | left) & !start_visit;
                if (next & goal_visit) != 0 {
                    return true;
                }
                start_visit |= next;
                start_front = next;
            }
            {
                let up = ((goal_front & !masks.up) << 9) & VALID_CELLS;
                let down = (goal_front & !masks.down) >> 9;
                let right = ((goal_front & RIGHT_SOURCE_MASK & !masks.right) << 1) & VALID_CELLS;
                let left = (goal_front & LEFT_SOURCE_MASK & !masks.left) >> 1;
                let next = (up | down | right | left) & !goal_visit;
                if (next & start_visit) != 0 {
                    return true;
                }
                goal_visit |= next;
                goal_front = next;
            }
        }
        false
    }

    /// Sprint 6.10: emit absolute action IDs only; no per-candidate
    /// `MctsRustBoard` clone, no inline mask recomputation. Mirrors
    /// backend (iii) `cpp-functional/engine/state.hpp::legal_actions`.
    pub fn legal_actions(&self, out: &mut ActionBuffer, max_plies: u16) {
        out.clear();
        if self.is_terminal(max_plies) {
            return;
        }
        self.append_pawn_actions(out);
        if self.walls_remaining_for(self.side_to_move) == 0 {
            return;
        }
        let base = self.block_masks();
        let mut count = 0usize;
        let mut canonical = 81u16;
        while canonical <= 208 && count < 12 {
            let aid = canonical as u8;
            if !self.wall_action_exists(aid) && self.wall_action_legal(aid, &base) {
                out.push(aid);
                count += 1;
            }
            canonical += 1;
        }
    }

    fn append_pawn_actions(&self, out: &mut ActionBuffer) {
        // Direction order [up, left, right, down] in absolute frame.
        let directions: [(i8, i8); 4] = [(0, -1), (-1, 0), (1, 0), (0, 1)];
        let (actor_x, actor_y) = match self.side_to_move {
            SideToMove::Hero => (self.hero_x, self.hero_y),
            SideToMove::Villain => (self.villain_x, self.villain_y),
        };
        let (occupied_x, occupied_y) = match self.side_to_move {
            SideToMove::Hero => (self.villain_x, self.villain_y),
            SideToMove::Villain => (self.hero_x, self.hero_y),
        };
        for &(dx, dy) in &directions {
            let nx = actor_x as i8 + dx;
            let ny = actor_y as i8 + dy;
            if nx < 0 || ny < 0 || nx >= BOARD_SIZE as i8 || ny >= BOARD_SIZE as i8 {
                continue;
            }
            let nx_u = nx as u8;
            let ny_u = ny as u8;
            if nx_u == occupied_x && ny_u == occupied_y {
                continue;
            }
            if self.edge_blocked(actor_x, actor_y, nx_u, ny_u) {
                continue;
            }
            out.push(ny_u * 9 + nx_u);
        }
    }

    #[inline(always)]
    fn wall_action_exists(&self, action_id: u8) -> bool {
        if action_id <= 144 {
            let n = action_id - 81;
            self.horizontal_wall_conflicts(n % 8, n / 8)
        } else {
            let n = action_id - 145;
            self.vertical_wall_conflicts(n % 8, n / 8)
        }
    }

    #[inline(always)]
    fn horizontal_wall_conflicts(&self, x: u8, y: u8) -> bool {
        wall_test(self.walls_v, x, y)
            || wall_test(self.walls_h, x, y)
            || (x > 0 && wall_test(self.walls_h, x - 1, y))
            || (x < 7 && wall_test(self.walls_h, x + 1, y))
    }

    #[inline(always)]
    fn vertical_wall_conflicts(&self, x: u8, y: u8) -> bool {
        wall_test(self.walls_h, x, y)
            || wall_test(self.walls_v, x, y)
            || (y > 0 && wall_test(self.walls_v, x, y - 1))
            || (y < 7 && wall_test(self.walls_v, x, y + 1))
    }

    /// Sprint 6.10: legality check against an additively-extended
    /// `BlockMasks`. No `MctsRustBoard` clone.
    #[inline(always)]
    fn wall_action_legal(&self, action_id: u8, base_masks: &BlockMasks) -> bool {
        let trial = Self::add_wall_to_masks(action_id, *base_masks);
        self.path_exists_with_masks(true, &trial) && self.path_exists_with_masks(false, &trial)
    }

    /// Trusted internal transition. Toggles `side_to_move` and
    /// increments `ply`. Caller must already know the action is legal.
    /// Mirrors backend (iii) `apply_action_unchecked`.
    pub fn apply_action_unchecked(&mut self, action_id: u8) {
        if action_id <= 80 {
            let x = action_id % 9;
            let y = action_id / 9;
            match self.side_to_move {
                SideToMove::Hero => {
                    self.hero_x = x;
                    self.hero_y = y;
                }
                SideToMove::Villain => {
                    self.villain_x = x;
                    self.villain_y = y;
                }
            }
        } else if action_id <= 144 {
            let n = action_id - 81;
            self.walls_h |= wall_bit(n % 8, n / 8);
            self.decrement_current_walls();
        } else if action_id <= 208 {
            let n = action_id - 145;
            self.walls_v |= wall_bit(n % 8, n / 8);
            self.decrement_current_walls();
        }
        self.last_action = action_id;
        self.ply = self.ply.saturating_add(1);
        self.side_to_move = match self.side_to_move {
            SideToMove::Hero => SideToMove::Villain,
            SideToMove::Villain => SideToMove::Hero,
        };
    }

    /// Validate an absolute action id against the current legal-action
    /// set and apply it. Returns `false` if illegal.
    pub fn try_apply_absolute(&mut self, absolute_action_id: u8, max_plies: u16) -> bool {
        let mut actions = ActionBuffer::new();
        self.legal_actions(&mut actions, max_plies);
        for i in 0..actions.len() {
            if actions.get(i) == absolute_action_id {
                self.apply_action_unchecked(absolute_action_id);
                return true;
            }
        }
        false
    }
}

#[inline(always)]
fn cell_bit(x: u8, y: u8) -> u128 {
    1u128 << (y * BOARD_SIZE + x)
}

#[inline(always)]
fn row_mask(y: u8) -> u128 {
    ((1u128 << 9) - 1) << (y * BOARD_SIZE)
}

const fn source_mask_right() -> u128 {
    let mut mask = 0u128;
    let mut y = 0u8;
    while y < BOARD_SIZE {
        let mut x = 0u8;
        while x < BOARD_SIZE - 1 {
            mask |= 1u128 << (y * BOARD_SIZE + x);
            x += 1;
        }
        y += 1;
    }
    mask
}

const fn source_mask_left() -> u128 {
    let mut mask = 0u128;
    let mut y = 0u8;
    while y < BOARD_SIZE {
        let mut x = 1u8;
        while x < BOARD_SIZE {
            mask |= 1u128 << (y * BOARD_SIZE + x);
            x += 1;
        }
        y += 1;
    }
    mask
}
