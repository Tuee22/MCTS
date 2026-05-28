// Backend (iv) Corridors board state with bitfield walls and bit-parallel
// escapability per Sprint 6.8.
//
// Action ID encoding (canonical, matches Haskell engine
// `MCTS.Types.actionId` exactly):
//   Pawn(x, y)  -> y * 9 + x          in [0..80]
//   WallH(x, y) -> 81  + y * 8 + x    in [81..144]
//   WallV(x, y) -> 145 + y * 8 + x    in [145..208]
//
// Like the legacy C++ engine, the board flips after every move so the
// always-to-move side is treated as `hero` internally. Walls are
// encoded with one bit per wall keyed by its lower-left intersection
// (x, y) for x, y in [0..7]. The 180-degree flip required after each
// move is a bit-reverse over the 64-bit wall bitmaps.

pub const BOARD_SIZE: u8 = 9;
pub const STARTING_WALLS: u8 = 10;
pub const MAX_LEGAL_ACTIONS: usize = 16;
const NO_ACTION: u8 = 255;
const VALID_CELLS: u128 = (1u128 << 81) - 1;
const RIGHT_SOURCE_MASK: u128 = source_mask_right();
const LEFT_SOURCE_MASK: u128 = source_mask_left();

#[derive(Clone, Copy)]
pub enum Side {
    Hero,
    Villain,
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

    #[inline(always)]
    fn as_mut_slice(&mut self) -> &mut [u8] {
        &mut self.items[..self.len]
    }
}

#[repr(C)]
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
    last_visit_len: u8,
    last_visit_actions: [u8; MAX_LEGAL_ACTIONS],
    last_visit_counts: [u32; MAX_LEGAL_ACTIONS],
}

impl Clone for MctsRustBoard {
    #[inline(always)]
    fn clone(&self) -> Self {
        Self {
            hero_x: self.hero_x,
            hero_y: self.hero_y,
            villain_x: self.villain_x,
            villain_y: self.villain_y,
            hero_walls_remaining: self.hero_walls_remaining,
            villain_walls_remaining: self.villain_walls_remaining,
            walls_h: self.walls_h,
            walls_v: self.walls_v,
            ply: self.ply,
            last_action: self.last_action,
            last_visit_len: 0,
            last_visit_actions: [0; MAX_LEGAL_ACTIONS],
            last_visit_counts: [0; MAX_LEGAL_ACTIONS],
        }
    }
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
            last_visit_len: 0,
            last_visit_actions: [0; MAX_LEGAL_ACTIONS],
            last_visit_counts: [0; MAX_LEGAL_ACTIONS],
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

    #[inline(always)]
    pub fn advance_ply(&mut self) {
        self.ply = self.ply.saturating_add(1);
    }

    /// Return the 180-degree flipped copy of this board. Used after
    /// every move so the next-to-move side is treated as hero by the
    /// engine.
    #[inline]
    pub fn flipped(&self) -> Self {
        Self {
            hero_x: BOARD_SIZE - 1 - self.villain_x,
            hero_y: BOARD_SIZE - 1 - self.villain_y,
            villain_x: BOARD_SIZE - 1 - self.hero_x,
            villain_y: BOARD_SIZE - 1 - self.hero_y,
            hero_walls_remaining: self.villain_walls_remaining,
            villain_walls_remaining: self.hero_walls_remaining,
            walls_h: self.walls_h.reverse_bits(),
            walls_v: self.walls_v.reverse_bits(),
            ply: self.ply,
            last_action: if self.last_action == NO_ACTION {
                NO_ACTION
            } else {
                flip_action_id(self.last_action)
            },
            last_visit_len: 0,
            last_visit_actions: [0; MAX_LEGAL_ACTIONS],
            last_visit_counts: [0; MAX_LEGAL_ACTIONS],
        }
    }

    /// True if the edge between two Manhattan neighbours is blocked
    /// by a wall. Matches `MCTS.Engine.edgeBlocked`.
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

    /// True if `side`'s pawn can reach its goal row through unblocked
    /// edges. Uses the same 81-cell wavefront bitmap shape as the
    /// functional C++ and Haskell engines.
    pub fn path_exists(&self, side: Side) -> bool {
        let (start_x, start_y, goal_y) = match side {
            Side::Hero => (self.hero_x, self.hero_y, BOARD_SIZE - 1),
            Side::Villain => (self.villain_x, self.villain_y, 0u8),
        };
        if start_y == goal_y {
            return true;
        }
        let mut up_blocked = 0u128;
        let mut down_blocked = 0u128;
        let mut walls_h = self.walls_h;
        while walls_h != 0 {
            let idx = walls_h.trailing_zeros() as u8;
            walls_h &= walls_h - 1;
            let x = idx % 8;
            let y = idx / 8;
            up_blocked |= cell_bit(x, y) | cell_bit(x + 1, y);
            down_blocked |= cell_bit(x, y + 1) | cell_bit(x + 1, y + 1);
        }

        let mut right_blocked = 0u128;
        let mut left_blocked = 0u128;
        let mut walls_v = self.walls_v;
        while walls_v != 0 {
            let idx = walls_v.trailing_zeros() as u8;
            walls_v &= walls_v - 1;
            let x = idx % 8;
            let y = idx / 8;
            right_blocked |= cell_bit(x, y) | cell_bit(x, y + 1);
            left_blocked |= cell_bit(x + 1, y) | cell_bit(x + 1, y + 1);
        }

        let goal = row_mask(goal_y);
        let mut frontier = cell_bit(start_x, start_y);
        let mut visited = frontier;
        while frontier != 0 {
            let up = ((frontier & !up_blocked) << 9) & VALID_CELLS;
            let down = (frontier & !down_blocked) >> 9;
            let right = ((frontier & RIGHT_SOURCE_MASK & !right_blocked) << 1) & VALID_CELLS;
            let left = (frontier & LEFT_SOURCE_MASK & !left_blocked) >> 1;
            let next = (up | down | right | left) & !visited;
            if (next & goal) != 0 {
                return true;
            }
            visited |= next;
            frontier = next;
        }
        false
    }

    /// Append every legal action to `out`. Action IDs are always in
    /// the current internal hero perspective, but the order is keyed by
    /// the canonical Haskell/C++ verification perspective for this
    /// absolute ply. This keeps the first-unvisited-child policy stable
    /// even on odd plies, where the internal board has been rotated.
    ///
    /// Wall moves are capped at 12 to match `MCTS.Engine.legalMoves`
    /// `take 12 (wallMoves board)`.
    pub fn legal_actions(&self, out: &mut ActionBuffer, max_plies: u16) {
        out.clear();
        if self.is_terminal(max_plies) {
            return;
        }
        self.append_pawn_actions(out);
        if self.hero_walls_remaining == 0 {
            return;
        }
        let mut count = 0usize;
        for canonical in 81..=208u8 {
            if count >= 12 {
                break;
            }
            let action_id = self.internal_action_for_canonical_order(canonical);
            if self.wall_action_exists(action_id) {
                continue;
            }
            if self.wall_action_legal(action_id) {
                out.push(action_id);
                count += 1;
            }
        }
    }

    fn append_pawn_actions(&self, out: &mut ActionBuffer) {
        let start = out.len();
        let candidates: [(i8, i8); 4] = [(0, 1), (1, 0), (-1, 0), (0, -1)];
        for &(dx, dy) in &candidates {
            let nx = self.hero_x as i8 + dx;
            let ny = self.hero_y as i8 + dy;
            if nx < 0 || ny < 0 || nx >= BOARD_SIZE as i8 || ny >= BOARD_SIZE as i8 {
                continue;
            }
            let nx_u = nx as u8;
            let ny_u = ny as u8;
            if nx_u == self.villain_x && ny_u == self.villain_y {
                continue;
            }
            if self.edge_blocked(self.hero_x, self.hero_y, nx_u, ny_u) {
                continue;
            }
            out.push(ny_u * 9 + nx_u);
        }
        let odd_ply = self.ply % 2 != 0;
        out.as_mut_slice()[start..].sort_by_key(|aid| {
            if odd_ply {
                flip_action_id(*aid)
            } else {
                *aid
            }
        });
    }

    #[inline(always)]
    fn internal_action_for_canonical_order(&self, canonical_action_id: u8) -> u8 {
        if self.ply % 2 == 0 {
            canonical_action_id
        } else {
            flip_action_id(canonical_action_id)
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

    #[inline(always)]
    fn wall_action_legal(&self, action_id: u8) -> bool {
        if action_id <= 144 {
            let n = action_id - 81;
            self.wall_placement_legal(n % 8, n / 8, false)
        } else {
            let n = action_id - 145;
            self.wall_placement_legal(n % 8, n / 8, true)
        }
    }

    fn wall_placement_legal(&self, x: u8, y: u8, vertical: bool) -> bool {
        let mut trial = self.clone();
        if vertical {
            trial.walls_v |= wall_bit(x, y);
        } else {
            trial.walls_h |= wall_bit(x, y);
        }
        trial.path_exists(Side::Hero) && trial.path_exists(Side::Villain)
    }

    #[inline(always)]
    pub fn child_after_action(&self, action_id: u8) -> Self {
        let mut child = self.clone();
        let _ = child.apply_action_flip(action_id);
        child
    }

    #[inline(always)]
    pub fn store_last_visits(&mut self, visits: &[(u8, u32)]) {
        self.last_visit_len = visits.len().min(MAX_LEGAL_ACTIONS) as u8;
        for (idx, (action, count)) in visits.iter().take(MAX_LEGAL_ACTIONS).enumerate() {
            self.last_visit_actions[idx] = *action;
            self.last_visit_counts[idx] = *count;
        }
    }

    #[inline(always)]
    pub fn clear_last_visits(&mut self) {
        self.last_visit_len = 0;
    }

    #[inline(always)]
    pub fn read_last_visits(&self, action_id: u8) -> u32 {
        for idx in 0..self.last_visit_len as usize {
            if self.last_visit_actions[idx] == action_id {
                return self.last_visit_counts[idx];
            }
        }
        0
    }

    /// Apply a canonical action id from current-hero perspective, then
    /// flip the board so the next side to move becomes hero. Caller
    /// must have validated the action against `legal_actions`.
    pub fn apply_action_flip(&mut self, action_id: u8) -> bool {
        if action_id <= 80 {
            let x = action_id % 9;
            let y = action_id / 9;
            self.hero_x = x;
            self.hero_y = y;
        } else if action_id <= 144 {
            let n = action_id - 81;
            let x = n % 8;
            let y = n / 8;
            self.walls_h |= wall_bit(x, y);
            if self.hero_walls_remaining > 0 {
                self.hero_walls_remaining -= 1;
            }
        } else if action_id <= 208 {
            let n = action_id - 145;
            let x = n % 8;
            let y = n / 8;
            self.walls_v |= wall_bit(x, y);
            if self.hero_walls_remaining > 0 {
                self.hero_walls_remaining -= 1;
            }
        } else {
            return false;
        }
        self.last_action = action_id;
        let flipped = self.flipped();
        *self = flipped;
        self.advance_ply();
        self.clear_last_visits();
        true
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
