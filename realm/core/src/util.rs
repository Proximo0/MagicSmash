//! Small whole-number helpers: the seeded streams, integer trigonometry, the counting-sort grid and the
//! thread splitter every parallel phase uses.

use std::thread;

/// splitmix64: the field's one sequential stream.
pub fn rng_next(s: &mut u64) -> u64 {
    *s = s.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let mut z = *s;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

/// A stateless draw from the field's seed and a few counters (draws, THE MOON): the same on every
/// machine and thread, whatever order heroes are handled in.
pub fn mix(seed: u64, a: u64, b: u64, c: u64) -> u64 {
    let mut s = seed ^ a.wrapping_mul(0xD6E8_FEB8_6659_FD93) ^ b.wrapping_mul(0xA076_1D64_78BD_642F) ^ c.wrapping_mul(0xE703_7ED1_A0B4_28DB);
    rng_next(&mut s)
}

/// Fixed point of the trigonometry: one is 16 384.
pub const Q14: i64 = 16_384;
/// Bhaskara's cosine in degrees: `(32400 - 4 d^2) / (32400 + d^2)` on -90 to 90 degrees, error under 2 in 1 000.
const BHASKARA: i64 = 32_400;
const HALF_TURN: i32 = 180;
const QUARTER_TURN: i32 = 90;
const TURN: i32 = 360;

pub fn cos_q14(deg: i32) -> i64 {
    let d = deg.rem_euclid(TURN);
    let (d, sign) = if d <= QUARTER_TURN {
        (d, 1)
    } else if d < TURN - QUARTER_TURN {
        (HALF_TURN - d, -1)
    } else {
        (d - TURN, 1)
    };
    let d = d as i64;
    sign * Q14 * (BHASKARA - 4 * d * d) / (BHASKARA + d * d)
}

pub fn sin_q14(deg: i32) -> i64 {
    cos_q14(deg - QUARTER_TURN)
}

/// Turns a vector by `deg` (y down, so positive turns clockwise on screen).
pub fn rotate(dx: i32, dy: i32, deg: i32) -> (i32, i32) {
    let (c, s) = (cos_q14(deg), sin_q14(deg));
    let (x, y) = (dx as i64, dy as i64);
    (((x * c - y * s) / Q14) as i32, ((x * s + y * c) / Q14) as i32)
}

/// A unit vector (length `len`) at `deg` from east, clockwise.
pub fn at_angle(deg: i32, len: i32) -> (i32, i32) {
    ((cos_q14(deg) * len as i64 / Q14) as i32, (sin_q14(deg) * len as i64 / Q14) as i32)
}

#[inline]
pub fn isqrt(v: i64) -> i64 {
    (v.max(0) as u64).isqrt() as i64
}

#[inline]
pub fn d2(ax: i32, ay: i32, bx: i32, by: i32) -> i64 {
    let dx = (ax - bx) as i64;
    let dy = (ay - by) as i64;
    dx * dx + dy * dy
}

/// `v * pct / 100` in 64 bits, never below zero.
#[inline]
pub fn pct(v: u32, pct: i64) -> u32 {
    ((v as i64 * pct.max(0)) / 100).clamp(0, u32::MAX as i64) as u32
}

/// A counting-sort grid: `items[start[c]..start[c + 1]]` are the ids in cell `c`, in id order.
#[derive(Clone, Debug, Default)]
pub struct Grid {
    pub start: Vec<u32>,
    pub items: Vec<u32>,
}

impl Grid {
    pub fn new(cells: usize) -> Grid {
        Grid { start: vec![0; cells + 1], items: Vec::new() }
    }

    pub fn cell(&self, c: usize) -> &[u32] {
        &self.items[self.start[c] as usize..self.start[c + 1] as usize]
    }

    pub fn count(&self, c: usize) -> u32 {
        self.start[c + 1] - self.start[c]
    }

    /// Rebuilds from `(id, cell)` pairs given in id order.
    pub fn build(&mut self, cells_of: &[(u32, u32)]) {
        let cells = self.start.len() - 1;
        self.start.fill(0);
        for &(_, c) in cells_of {
            self.start[c as usize] += 1;
        }
        let mut sum = 0u32;
        for c in 0..cells {
            let t = self.start[c];
            self.start[c] = sum;
            sum += t;
        }
        self.start[cells] = sum;
        self.items.resize(sum as usize, 0);
        for &(id, c) in cells_of {
            let s = &mut self.start[c as usize];
            self.items[*s as usize] = id;
            *s += 1;
        }
        for c in (1..=cells).rev() {
            self.start[c] = self.start[c - 1];
        }
        self.start[0] = 0;
    }
}

/// Calls `f` for every id in the cells of `g` (side `w`, cell shift `shift`) overlapping the box.
#[inline]
#[allow(clippy::too_many_arguments)]
pub fn grid_box(g: &Grid, w: usize, shift: u32, x0: i32, y0: i32, x1: i32, y1: i32, mut f: impl FnMut(u32)) {
    let lim = w as i32 - 1;
    let cx0 = (x0 >> shift).clamp(0, lim);
    let cy0 = (y0 >> shift).clamp(0, lim);
    let cx1 = (x1 >> shift).clamp(0, lim);
    let cy1 = (y1 >> shift).clamp(0, lim);
    for cy in cy0..=cy1 {
        let row = cy as usize * w;
        for cx in cx0..=cx1 {
            for &id in g.cell(row + cx as usize) {
                f(id);
            }
        }
    }
}

/// Splits `0..n` into `t` contiguous ranges.
pub fn chunk_len(n: usize, t: usize) -> usize {
    n.div_ceil(t.max(1)).max(1)
}

/// Runs `f(start, end)` over `0..n` split into `threads` ranges and returns the results in range order:
/// the same answer for any thread count as long as `f` only reads shared state.
pub fn par_ranges<T: Send>(n: usize, threads: usize, min_per_thread: usize, f: impl Fn(usize, usize) -> T + Sync) -> Vec<T> {
    let t = threads.max(1).min(n.div_ceil(min_per_thread.max(1)).max(1));
    if t == 1 {
        return vec![f(0, n)];
    }
    let chunk = chunk_len(n, t);
    let f = &f;
    thread::scope(|sc| {
        let hs: Vec<_> = (0..t)
            .map(|k| {
                let (a, b) = ((k * chunk).min(n), ((k + 1) * chunk).min(n));
                sc.spawn(move || f(a, b))
            })
            .collect();
        hs.into_iter().map(|h| h.join().expect("worker")).collect()
    })
}
