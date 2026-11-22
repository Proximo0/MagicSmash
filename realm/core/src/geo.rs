//! Boss geometry in whole numbers: beams, segments and angles (sixteenths of a degree).

use crate::util::{Q14, at_angle, isqrt};
use crate::SUB;

/// Sixteenths of a degree to whole degrees.
pub(crate) fn deg(a16: i32) -> i32 {
    (a16 >> 4).rem_euclid(360)
}

/// Whether a point is within `hw` px of the beam from (bx, by) at `angle16` and `len` px long.
pub fn in_beam(bx: i32, by: i32, angle16: i32, len: i32, hw: i32, px: i32, py: i32) -> bool {
    let (ux, uy) = at_angle(deg(angle16), 1024);
    let (dx, dy) = ((px - bx) as i64, (py - by) as i64);
    let along = (dx * ux as i64 + dy * uy as i64) / 1024;
    let side = (dx * uy as i64 - dy * ux as i64) / 1024;
    along >= 0 && along <= len as i64 * SUB as i64 && side.abs() <= hw as i64 * SUB as i64
}

/// Whether a point is within `r` (sub units) of the segment a to b.
pub fn near_segment(ax: i32, ay: i32, bx: i32, by: i32, px: i32, py: i32, r: i32) -> bool {
    let (vx, vy) = ((bx - ax) as i64, (by - ay) as i64);
    let (wx, wy) = ((px - ax) as i64, (py - ay) as i64);
    let l2 = vx * vx + vy * vy;
    let t = if l2 == 0 { 0 } else { (wx * vx + wy * vy).clamp(0, l2) };
    let (cx, cy) = if l2 == 0 { (0, 0) } else { (vx * t / l2, vy * t / l2) };
    let (ex, ey) = (wx - cx, wy - cy);
    ex * ex + ey * ey <= r as i64 * r as i64
}

/// Degrees clockwise from east (y down) of a vector, whole numbers: octant search on the integer cosine.
pub(crate) fn atan_deg(dx: i64, dy: i64) -> i32 {
    if dx == 0 && dy == 0 {
        return 0;
    }
    let len = isqrt(dx * dx + dy * dy).max(1);
    let mut best = (i64::MAX, 0);
    for d in 0..360 {
        let (c, s) = (crate::util::cos_q14(d), crate::util::sin_q14(d));
        let e = (dx * Q14 / len - c).abs() + (dy * Q14 / len - s).abs();
        if e < best.0 {
            best = (e, d);
        }
    }
    best.1
}
