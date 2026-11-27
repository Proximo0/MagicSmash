//! How a class bot gets around (job B1): stepping out of monster shots about to land, and walking around walls
//! toward its patrol's target by a search of the cells, as a person would. Whole numbers, from public state.

use super::{Bot, GOAL_W};
use crate::hero::Hero;
use crate::util::isqrt;
use crate::{CELL_SHIFT, Field, SUB};

/// Dodging monster shots: a landing circle is left by its radius and this margin (px) with this strength; a bolt
/// within `DODGE_BOLT_PX` that would pass within `DODGE_BOLT_MISS` px in the next second is sidestepped (0: bolts
/// are not dodged; sidestepping them walked novices into the crowd).
const DODGE_MARGIN: i64 = 16;
const DODGE_W: i64 = GOAL_W;
const DODGE_BOLT_PX: i64 = 0;
const DODGE_BOLT_MISS: i64 = 20;

/// Navigation: the patrol's target lies this far ahead along the ring (percent of the radius), the search looks
/// `NAV_CELLS` cells around the hero, a waypoint lasts `NAV_TICKS`, and it pulls with `NAV_W` (a goal's strength).
pub(super) const NAV_AHEAD_PCT: i64 = 15;
const NAV_CELLS: i32 = 40;
const NAV_TICKS: u32 = 20;
pub(super) const NAV_W: i64 = GOAL_W / 3;
/// The straight way to a target is open when no wall lies on it in steps of this many px, up to `NAV_SIGHT` px.
const NAV_STEP: i32 = 16;
const NAV_SIGHT: i32 = 320;
/// A delving hero this close (px, along x plus y) to her detour's waypoint looks again.
const NAV_REACHED: i32 = 56;

/// The push (in the flee vector's units) out of every lobbed or bursting circle about to land on her (the lobbers of
/// THE HANGED WOOD and THE MOON MARSH downed whole parties that never dodged), and aside from bolts about to hit.
pub(super) fn dodge(f: &Field, h: &Hero) -> (i64, i64) {
    let (mut ax, mut ay) = (0i64, 0i64);
    let tick_hz = crate::tables::TICK_HZ as i64;
    for s in f.shots() {
        let (dx, dy) = (((h.x - s.x) / SUB) as i64, ((h.y - s.y) / SUB) as i64);
        if s.px > 0 {
            let r = s.px as i64 + DODGE_MARGIN;
            let dd = dx * dx + dy * dy;
            if dd < r * r {
                let d = isqrt(dd).max(1);
                let (ux, uy) = if dd == 0 { (1_000, 0) } else { (dx * 1_000 / d, dy * 1_000 / d) };
                ax += ux * DODGE_W / 1_000;
                ay += uy * DODGE_W / 1_000;
            }
        } else if dx.abs() < DODGE_BOLT_PX && dy.abs() < DODGE_BOLT_PX {
            // The bolt's closest approach within its next second; step to the side it misses by.
            let (vx, vy) = (s.vx as i64, s.vy as i64);
            let vv = (vx * vx + vy * vy).max(1);
            let (rx, ry) = ((h.x - s.x) as i64, (h.y - s.y) as i64);
            let t = ((rx * vx + ry * vy) / vv).clamp(0, tick_hz);
            let (cx, cy) = ((rx - vx * t) / SUB as i64, (ry - vy * t) / SUB as i64);
            if t > 0 && cx * cx + cy * cy < DODGE_BOLT_MISS * DODGE_BOLT_MISS {
                let side = if cx * vy - cy * vx >= 0 { 1 } else { -1 };
                let vl = isqrt(vv).max(1);
                ax += -vy * side * DODGE_W / vl / 2;
                ay += vx * side * DODGE_W / vl / 2;
            }
        }
    }
    (ax, ay)
}

impl Bot {
    /// A waypoint (px) on the way to (gx, gy) when walls stand between, or None when the way is open. The search is
    /// a breadth-first walk over the cells within `NAV_CELLS`; the waypoint is the farthest cell along the found way
    /// that she can see straight. It is kept `NAV_TICKS`.
    pub(super) fn waypoint(&mut self, f: &Field, x: i32, y: i32, gx: i32, gy: i32) -> Option<(i32, i32)> {
        let t = f.terrain();
        let clear = |ax: i32, ay: i32, bx: i32, by: i32| -> bool {
            let (dx, dy) = ((bx - ax) as i64, (by - ay) as i64);
            let full = isqrt(dx * dx + dy * dy).max(1);
            let n = (full.min(NAV_SIGHT as i64) / NAV_STEP as i64).max(1);
            (1..=n).all(|k| {
                let s = k * NAV_STEP as i64;
                !t.wall(((ax as i64 + dx * s / full) * SUB as i64) as i32, ((ay as i64 + dy * s / full) * SUB as i64) as i32)
            })
        };
        // A delving hero keeps her detour until she is on it or it runs out: the straight way is only looked at
        // `NAV_SIGHT` px far, so it can seem open a step aside of where it seemed shut, and she would sway between.
        if self.plan.delve {
            if let Some(w) = self.nav.filter(|&(wx, wy)| f.tick() < self.nav_until && (wx - x).abs() + (wy - y).abs() > NAV_REACHED) {
                return Some(w);
            }
        }
        if clear(x, y, gx, gy) {
            self.nav = None;
            return None;
        }
        if let Some(w) = self.nav.filter(|_| f.tick() < self.nav_until) {
            return Some(w);
        }
        let cell = 1i32 << (CELL_SHIFT - 8);
        let (hx, hy) = (x / cell, y / cell);
        let side = 2 * NAV_CELLS + 1;
        let mut parent = vec![u8::MAX; (side * side) as usize];
        let idx = |cx: i32, cy: i32| ((cy - hy + NAV_CELLS) * side + (cx - hx + NAV_CELLS)) as usize;
        const STEPS: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];
        let mut queue = std::collections::VecDeque::new();
        parent[idx(hx, hy)] = 0;
        queue.push_back((hx, hy));
        let (tcx, tcy) = (gx / cell, gy / cell);
        let mut best = (i64::MAX, hx, hy);
        while let Some((cx, cy)) = queue.pop_front() {
            let dd = ((cx - tcx) as i64).pow(2) + ((cy - tcy) as i64).pow(2);
            if dd < best.0 {
                best = (dd, cx, cy);
            }
            for (k, &(ox, oy)) in STEPS.iter().enumerate() {
                let (nx, ny) = (cx + ox, cy + oy);
                if (nx - hx).abs() > NAV_CELLS || (ny - hy).abs() > NAV_CELLS || parent[idx(nx, ny)] != u8::MAX {
                    continue;
                }
                if t.wall((nx * cell + cell / 2) * SUB, (ny * cell + cell / 2) * SUB) {
                    continue;
                }
                parent[idx(nx, ny)] = k as u8 + 1;
                queue.push_back((nx, ny));
            }
        }
        // Back from the best cell to the hero; the waypoint is the farthest cell of the way she sees straight.
        let mut way = vec![(best.1, best.2)];
        let (mut cx, mut cy) = (best.1, best.2);
        while (cx, cy) != (hx, hy) {
            let (ox, oy) = STEPS[parent[idx(cx, cy)] as usize - 1];
            cx -= ox;
            cy -= oy;
            way.push((cx, cy));
        }
        let mut w = None;
        for &(cx, cy) in way.iter().rev().skip(1) {
            let (px, py) = (cx * cell + cell / 2, cy * cell + cell / 2);
            if w.is_some() && !clear(x, y, px, py) {
                break;
            }
            w = Some((px, py));
        }
        let w = w.unwrap_or((gx, gy));
        self.nav = Some(w);
        self.nav_until = f.tick() + NAV_TICKS;
        Some(w)
    }
}
