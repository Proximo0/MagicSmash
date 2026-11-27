//! Quiet zones and shrines (rules 6, quiet zones): where they stand, placed by the map generator from the field's seed, and the
//! closed-neighbour bits that keep a monster's body off walls and quiet ground (rules 4, routing).

use crate::tables::*;
use crate::terrain::{Gen, W, cell_xy, idx, inside};
use crate::util::at_angle;
use crate::{CELL_SHIFT, CELLS, FIELD, SUB};

/// A quiet zone: its centre (sub units), radius in cells, and its shrine's index (bit in `Hero::shrines`), or
/// `NO_SHRINE` for a waystone's ward.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct QuietZone {
    pub x: i32,
    pub y: i32,
    pub r: i32,
    pub shrine: u8,
}

pub const NO_SHRINE: u8 = u8::MAX;

pub const EDGE_W: u8 = 1;
pub const EDGE_E: u8 = 2;
pub const EDGE_N: u8 = 4;
pub const EDGE_S: u8 = 8;
pub const EDGE_NW: u8 = 16;
pub const EDGE_NE: u8 = 32;
pub const EDGE_SW: u8 = 64;
pub const EDGE_SE: u8 = 128;

/// The closed-neighbour bits of every cell (the field's rim counts as closed).
pub fn edges_of(map: &[u8]) -> Vec<u8> {
    let mut e = vec![0u8; CELLS];
    let closed = |x: i32, y: i32| !inside(x, y) || map[idx(x, y)] & MONSTER_BLOCK != 0;
    for y in 0..W {
        for x in 0..W {
            let mut b = 0;
            for (bit, ox, oy) in [(EDGE_W, -1, 0), (EDGE_E, 1, 0), (EDGE_N, 0, -1), (EDGE_S, 0, 1), (EDGE_NW, -1, -1), (EDGE_NE, 1, -1), (EDGE_SW, -1, 1), (EDGE_SE, 1, 1)] {
                if closed(x + ox, y + oy) {
                    b |= bit;
                }
            }
            e[idx(x, y)] = b;
        }
    }
    e
}

/// Where the quiet zones stand: the entrance a little north of the gate (so a hero walks over its shrine on her way
/// in), 3 to 5 intermissions spread evenly in depth from the edge ring to the heart's rim, each within
/// `QUIET_SPREAD_DEG` of the line from the gate to the heart and `QUIET_APART` cells from the sites and each other, and
/// a ward round every waystone (no shrine).
pub(crate) fn place_quiet(g: &mut Gen, gate: (i32, i32), waystones: &[(i32, i32); 7], sites: &[(i32, i32)]) -> Vec<QuietZone> {
    let cell = 1 << CELL_SHIFT;
    let half = cell / 2;
    let mut v = vec![QuietZone { x: gate.0, y: gate.1 - (QUIET_GATE_R - 4) * cell, r: QUIET_GATE_R, shrine: 0 }];
    let n = g.range(QUIET_MID_MIN, QUIET_MID_MAX);
    let mut taken: Vec<(i32, i32)> = sites.to_vec();
    // The route winds: each intermission's angle within `QUIET_STEP_DEG` of the last one's.
    let mut prev = 90 + g.range(-QUIET_STEP_DEG, QUIET_STEP_DEG);
    for k in 0..n {
        let depth = QUIET_DEPTH_OUT_PX - (QUIET_DEPTH_OUT_PX - QUIET_DEPTH_IN_PX) * k / (n - 1).max(1);
        let mut pick = (0, 0, prev);
        let mut best = -1i64;
        for _ in 0..16 {
            let ang = (prev + g.range(-QUIET_STEP_DEG, QUIET_STEP_DEG)).clamp(90 - QUIET_SPREAD_DEG, 90 + QUIET_SPREAD_DEG);
            let (dx, dy) = at_angle(ang, depth * SUB);
            let p = ((FIELD / 2 + dx).clamp(cell * 20, FIELD - cell * 20), (FIELD / 2 + dy).clamp(cell * 20, FIELD - cell * 20));
            let c = cell_xy(p);
            let apart = taken.iter().map(|&(x, y)| ((x - c.0).pow(2) + (y - c.1).pow(2)) as i64).min().unwrap_or(i64::MAX);
            if apart > best {
                best = apart;
                pick = (p.0, p.1, ang);
            }
            if apart >= (QUIET_APART * QUIET_APART) as i64 {
                break;
            }
        }
        prev = pick.2;
        let c = cell_xy((pick.0, pick.1));
        taken.push(c);
        v.push(QuietZone { x: (c.0 << CELL_SHIFT) + half, y: (c.1 << CELL_SHIFT) + half, r: QUIET_MID_R, shrine: (k + 1) as u8 });
    }
    for &(x, y) in waystones {
        v.push(QuietZone { x, y, r: QUIET_WARD_R, shrine: NO_SHRINE });
    }
    v
}
