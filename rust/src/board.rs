// Backend (iv) Corridors board state with bitfield walls and BFS
// escapability per Sprint 6.3.
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
            last_action: 255,
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
            last_action: if self.last_action == 255 {
                255
            } else {
                flip_action_id(self.last_action)
            },
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
    /// edges. BFS over the 81-cell grid using a 128-bit visited
    /// bitmap.
    pub fn path_exists(&self, side: Side) -> bool {
        let (start_x, start_y, goal_y) = match side {
            Side::Hero => (self.hero_x, self.hero_y, BOARD_SIZE - 1),
            Side::Villain => (self.villain_x, self.villain_y, 0u8),
        };
        if start_y == goal_y {
            return true;
        }
        let mut visited: u128 = 0;
        let mut queue: [u8; 81] = [0; 81];
        let mut head: usize = 0;
        let mut tail: usize = 0;
        let start_idx = start_y * BOARD_SIZE + start_x;
        queue[tail] = start_idx;
        tail += 1;
        visited |= 1u128 << start_idx;
        while head < tail {
            let cell = queue[head];
            head += 1;
            let x = cell % BOARD_SIZE;
            let y = cell / BOARD_SIZE;
            for &(dx, dy) in &[(0i8, 1i8), (1, 0), (-1, 0), (0, -1)] {
                let nx_i = x as i8 + dx;
                let ny_i = y as i8 + dy;
                if nx_i < 0
                    || ny_i < 0
                    || nx_i >= BOARD_SIZE as i8
                    || ny_i >= BOARD_SIZE as i8
                {
                    continue;
                }
                let nx = nx_i as u8;
                let ny = ny_i as u8;
                let n_idx = ny * BOARD_SIZE + nx;
                if (visited >> n_idx) & 1 != 0 {
                    continue;
                }
                if self.edge_blocked(x, y, nx, ny) {
                    continue;
                }
                if ny == goal_y {
                    return true;
                }
                visited |= 1u128 << n_idx;
                queue[tail] = n_idx;
                tail += 1;
            }
        }
        false
    }

    /// Append every legal action (canonical action IDs from current
    /// hero's perspective) to `out`. Order matches the legacy
    /// `corridors::board::get_legal_moves` discipline so the
    /// first-unvisited-child policy at sims=1 picks "up" (forward
    /// progress) and game playthroughs terminate: pawn (up, right,
    /// left, down), then walls iterated `i = y*8 + x` with the
    /// horizontal slot tried before the vertical slot at each
    /// intersection. Wall moves are capped at 12 to match
    /// `MCTS.Engine.legalMoves` `take 12 (wallMoves board)`.
    pub fn legal_actions(&self, out: &mut Vec<u8>, max_plies: u16) {
        out.clear();
        if self.is_terminal(max_plies) {
            return;
        }
        self.append_pawn_actions(out);
        if self.hero_walls_remaining == 0 {
            return;
        }
        let mut count = 0usize;
        for i in 0..64u8 {
            if count >= 12 {
                break;
            }
            let y = i / 8;
            let x = i % 8;
            if wall_test(self.walls_h, x, y) || wall_test(self.walls_v, x, y) {
                continue;
            }
            if self.wall_placement_legal(x, y, false) {
                out.push(81 + y * 8 + x);
                count += 1;
                if count >= 12 {
                    break;
                }
            }
            if self.wall_placement_legal(x, y, true) {
                out.push(145 + y * 8 + x);
                count += 1;
            }
        }
    }

    fn append_pawn_actions(&self, out: &mut Vec<u8>) {
        // Match the legacy ordering: up, right, left, down so the
        // first emitted child is forward progress.
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
        true
    }
}
