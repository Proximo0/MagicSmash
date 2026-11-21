//! Bot players, outside the core: their inputs come from their own seeded RNG and travel in protocol B
//! like anyone's.
//!
//! Every 8 ticks (staggered by id) a bot looks at the monsters in a 3 x 3 block of 32 px cells 128 px out
//! in each of the 8 directions, and at the 4 x 4 cells around itself:
//! - crowded (more than 12 within about 64 px): kite toward the emptiest direction, skill one time in 4;
//! - a rally bot (`--rally` share) farther than 300 px from the centre walks back to it, else wanders;
//! - any other bot walks toward the thinnest direction that still has monsters (the nearest thin spot in
//!   the horde), or wanders when none is near; near a wall it turns back in.

use realm_core::{rng_next, Field, CELLS_W, CELL_SHIFT, FIELD, IN_POTION1, IN_SKILL1, IN_SKILL2, IN_ULT, NEIGHBOURS, SUB};

pub const DECIDE_EVERY: u32 = 8;
pub const LOOK_PX: i32 = 128;
pub const CROWDED: u32 = 12;
pub const RALLY_PX: i32 = 300;
pub const WALL_PX: i32 = 300;

#[derive(Clone, Debug)]
pub struct Bot {
    pub id: u16,
    pub rally: bool,
    pub input: u16,
    rng: u64,
}

/// NEIGHBOURS index to input direction (1 E, 2 SE, ... clockwise) is index + 1.
fn dir_of(k: usize) -> u8 {
    k as u8 + 1
}

/// The 8-way input direction nearest a vector (y down).
pub fn dir_toward(dx: i32, dy: i32) -> u8 {
    if dx == 0 && dy == 0 {
        return 0;
    }
    let (ax, ay) = (dx.abs() as i64, dy.abs() as i64);
    let (sx, sy) = (dx.signum(), dy.signum());
    let (ox, oy) = if ax * 5 > ay * 12 {
        (sx, 0)
    } else if ay * 5 > ax * 12 {
        (0, sy)
    } else {
        (sx, sy)
    };
    NEIGHBOURS.iter().position(|&n| n == (ox, oy)).map_or(0, dir_of)
}

/// Where a new bot joins: rally bots within 300 px of the centre, others anywhere 200 px from a wall.
pub fn join_spot(rng: &mut u64, rally: bool) -> (u8, u8, i32, i32) {
    let r = rng_next(rng);
    // KNIGHT to PALADIN, half of them on the class's second job (from class level 40).
    let class = 1 + (r % 5) as u8 | (((r >> 5) & 1) as u8) << 3;
    let race = ((r >> 8) % 4) as u8;
    let (x, y) = if rally {
        let span = (2 * RALLY_PX) as u64;
        (FIELD / 2 + ((r >> 16) % span) as i32 * SUB - RALLY_PX * SUB, FIELD / 2 + ((r >> 40) % span) as i32 * SUB - RALLY_PX * SUB)
    } else {
        let span = (realm_core::FIELD_PX - 400) as u64;
        (((r >> 16) % span) as i32 * SUB + 200 * SUB, ((r >> 40) % span) as i32 * SUB + 200 * SUB)
    };
    (class, race, x, y)
}

fn count_box(f: &Field, x: i32, y: i32, half: i32) -> u32 {
    let g = f.grid();
    let lim = CELLS_W as i32 - 1;
    let (cx, cy) = (x >> CELL_SHIFT, y >> CELL_SHIFT);
    let mut n = 0;
    for yy in (cy - half).max(0)..=(cy + half).min(lim) {
        for xx in (cx - half).max(0)..=(cx + half).min(lim) {
            n += g.count(yy as usize * CELLS_W + xx as usize);
        }
    }
    n
}

impl Bot {
    pub fn new(id: u16, rally: bool, seed: u64) -> Bot {
        Bot { id, rally, input: 0, rng: seed ^ (id as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15) }
    }

    pub fn decide(&mut self, f: &Field) {
        if (f.tick() + self.id as u32) % DECIDE_EVERY != 0 {
            return;
        }
        let p = &f.players()[self.id as usize];
        if !p.alive() {
            self.input = 0;
            return;
        }
        let r = rng_next(&mut self.rng);
        let local = count_box(f, p.x, p.y, 2);
        let mut around = [0u32; 8];
        for (k, (ox, oy)) in NEIGHBOURS.iter().enumerate() {
            around[k] = count_box(f, p.x + ox * LOOK_PX * SUB, p.y + oy * LOOK_PX * SUB, 1);
        }
        let start = (r % 8) as usize;
        let pick = |want: &dyn Fn(u32) -> bool| -> Option<usize> {
            (0..8).map(|k| (start + k) % 8).filter(|&k| want(around[k])).min_by_key(|&k| around[k])
        };
        let wander = |cur: u16| if (r >> 8) % 4 == 0 { ((r >> 12) % 9) as u8 } else { (cur & 0x0F) as u8 };
        let (cx, cy) = (FIELD / 2 - p.x, FIELD / 2 - p.y);
        let near_wall = p.x < WALL_PX * SUB || p.y < WALL_PX * SUB || p.x > FIELD - WALL_PX * SUB || p.y > FIELD - WALL_PX * SUB;
        let mut dir;
        let mut skill = false;
        if local > CROWDED {
            dir = pick(&|_| true).map_or(0, dir_of);
            skill = (r >> 20) % 4 == 0;
        } else if self.rally && (cx.abs() > RALLY_PX * SUB || cy.abs() > RALLY_PX * SUB) {
            dir = dir_toward(cx, cy);
        } else if self.rally {
            dir = wander(self.input);
        } else {
            dir = pick(&|n| n > 0).map_or_else(|| wander(self.input), dir_of);
        }
        if near_wall && local <= CROWDED {
            dir = dir_toward(cx, cy);
        }
        // Byte 1 (a card pick, potion slot 1 when hurt) is pressed for one decision and released the next.
        let mut b1 = 0u16;
        if self.input >> 8 == 0 {
            if !p.offers.is_empty() {
                b1 |= 1 + ((r >> 24) % 3) as u16;
            }
            if p.health * 100 < p.max_health * 40 {
                b1 |= IN_POTION1 >> 8;
            }
        }
        self.input = dir as u16 | if skill { IN_SKILL1 | IN_SKILL2 | IN_ULT } else { 0 } | b1 << 8;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn directions_match_the_contract() {
        assert_eq!(dir_toward(10, 0), 1);
        assert_eq!(dir_toward(10, 10), 2);
        assert_eq!(dir_toward(0, 10), 3);
        assert_eq!(dir_toward(-10, 10), 4);
        assert_eq!(dir_toward(-10, 0), 5);
        assert_eq!(dir_toward(-10, -10), 6);
        assert_eq!(dir_toward(0, -10), 7);
        assert_eq!(dir_toward(10, -10), 8);
    }
}
