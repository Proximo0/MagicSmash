//! Terrain (rules section 6): one byte a cell (WALL, MIRE, ROAD, DARK), made from the field's seed by the
//! generator of its terrain rule, then checked: every site reachable from the gate and no passage under
//! `MIN_PASSAGE` cells. Rebuilt from field id and seed on load; only its hash is state.

use crate::tables::*;
use crate::util::{at_angle, rng_next};
use crate::{CELL_SHIFT, CELLS, CELLS_W, FIELD, SUB, terrain_gen};
pub use crate::quiet::*;

pub(crate) const W: i32 = CELLS_W as i32;
/// Diagonal scans flag gaps under this many cells (about `MIN_PASSAGE` across).
const MIN_DIAG: i32 = 4;
/// Repair rounds before giving up (each carves corridors to cut-off sites).
const REPAIR_ROUNDS: u32 = 6;
const GAP_PASSES: u32 = 32;
/// A corridor carved to a cut-off site: brush radius in cells.
const REPAIR_R: i32 = 4;

#[derive(Clone, Debug)]
pub struct Terrain {
    pub field: u8,
    pub map: Vec<u8>,
    /// Sites in sub units: the gate, seven waystones, six altar sites, the heart.
    pub gate: (i32, i32),
    pub waystones: [(i32, i32); 7],
    pub altars: [(i32, i32); 6],
    pub heart: (i32, i32),
    /// QUIET zones (rules 6, quiet zones): the entrance's first, then the intermissions, then the waystones' wards.
    pub quiet: Vec<QuietZone>,
    pub hash: u64,
    /// Per cell, which of its eight neighbours are closed to monsters (`EDGE_*` bits): one read keeps a monster's
    /// body off the walls. Derived from the map (not state).
    pub edges: Vec<u8>,
}



#[inline]
pub(crate) fn idx(x: i32, y: i32) -> usize {
    (y * W + x) as usize
}

#[inline]
pub(crate) fn inside(x: i32, y: i32) -> bool {
    x >= 0 && y >= 0 && x < W && y < W
}

pub(crate) fn cell_xy(p: (i32, i32)) -> (i32, i32) {
    (p.0 >> CELL_SHIFT, p.1 >> CELL_SHIFT)
}

impl Terrain {
    #[inline]
    pub fn at_cell(&self, c: usize) -> u8 {
        self.map[c]
    }
    #[inline]
    pub fn at(&self, x: i32, y: i32) -> u8 {
        if x < 0 || y < 0 || x >= FIELD || y >= FIELD {
            return WALL;
        }
        self.map[crate::cell_of(x, y)]
    }
    #[inline]
    pub fn wall(&self, x: i32, y: i32) -> bool {
        self.at(x, y) & WALL != 0
    }
    /// Closed to monsters: a wall or a quiet zone.
    #[inline]
    pub fn blocked(&self, x: i32, y: i32) -> bool {
        self.at(x, y) & MONSTER_BLOCK != 0
    }
    #[inline]
    pub fn quiet(&self, x: i32, y: i32) -> bool {
        self.at(x, y) & QUIET != 0
    }
    /// The quiet zone a point is in (the nearest centre when zones touch).
    pub fn zone_at(&self, x: i32, y: i32) -> Option<&QuietZone> {
        if !self.quiet(x, y) {
            return None;
        }
        self.quiet.iter().min_by_key(|z| crate::util::d2(x, y, z.x, z.y))
    }
    /// The shrines: (index, centre) of every zone that has one.
    pub fn shrines(&self) -> impl Iterator<Item = (u8, (i32, i32))> + '_ {
        self.quiet.iter().filter(|z| z.shrine != NO_SHRINE).map(|z| (z.shrine, (z.x, z.y)))
    }

    /// A monster's move: as `slide`, with quiet zones closed too.
    pub fn mslide(&self, x: i32, y: i32, nx: i32, ny: i32) -> (i32, i32) {
        let nx = nx.clamp(0, FIELD - 1);
        let ny = ny.clamp(0, FIELD - 1);
        if !self.blocked(nx, ny) {
            (nx, ny)
        } else if !self.blocked(nx, y) {
            (nx, y)
        } else if !self.blocked(x, ny) {
            (x, ny)
        } else {
            (x, y)
        }
    }

    /// Moves from (x, y) toward (nx, ny), sliding along walls; returns where it ends.
    pub fn slide(&self, x: i32, y: i32, nx: i32, ny: i32) -> (i32, i32) {
        let nx = nx.clamp(0, FIELD - 1);
        let ny = ny.clamp(0, FIELD - 1);
        if !self.wall(nx, ny) {
            (nx, ny)
        } else if !self.wall(nx, y) {
            (nx, y)
        } else if !self.wall(x, ny) {
            (x, ny)
        } else {
            (x, y)
        }
    }

    /// The first point where a line from a to b meets a wall (sampled every half cell), or b.
    pub fn line_end(&self, ax: i32, ay: i32, bx: i32, by: i32) -> (i32, i32, bool) {
        let half = 1 << (CELL_SHIFT - 1);
        let len = crate::util::isqrt(crate::util::d2(ax, ay, bx, by));
        let n = (len / half as i64).max(1);
        for s in 1..=n {
            let x = ax + ((bx - ax) as i64 * s / n) as i32;
            let y = ay + ((by - ay) as i64 * s / n) as i32;
            if self.wall(x, y) {
                let pb = s - 1;
                return (ax + ((bx - ax) as i64 * pb / n) as i32, ay + ((by - ay) as i64 * pb / n) as i32, true);
            }
        }
        (bx, by, false)
    }

    /// The nearest open cell centre to a point (sub units), searching rings outward.
    pub fn nearest_open(&self, x: i32, y: i32) -> (i32, i32) {
        let x = x.clamp(0, FIELD - 1);
        let y = y.clamp(0, FIELD - 1);
        if !self.wall(x, y) {
            return (x, y);
        }
        let (cx, cy) = (x >> CELL_SHIFT, y >> CELL_SHIFT);
        let half = 1 << (CELL_SHIFT - 1);
        for r in 1..W {
            for oy in -r..=r {
                for ox in -r..=r {
                    if ox.abs() != r && oy.abs() != r {
                        continue;
                    }
                    let (nx, ny) = (cx + ox, cy + oy);
                    if inside(nx, ny) && self.map[idx(nx, ny)] & WALL == 0 {
                        return ((nx << CELL_SHIFT) + half, (ny << CELL_SHIFT) + half);
                    }
                }
            }
        }
        (x, y)
    }

    pub fn sites(&self) -> Vec<(i32, i32)> {
        let mut v = vec![self.gate];
        v.extend_from_slice(&self.waystones);
        v.extend_from_slice(&self.altars);
        v.push(self.heart);
        v
    }
}

/// The ring of a point: 0 edge, 1 middle, 2 heart.
pub fn ring_of(x: i32, y: i32) -> u8 {
    let d = crate::util::isqrt(crate::util::d2(x, y, FIELD / 2, FIELD / 2)) / SUB as i64;
    if d < HEART_PX as i64 {
        RING_HEART
    } else if d < MIDDLE_PX as i64 {
        RING_MIDDLE
    } else {
        RING_EDGE
    }
}

/// A monster's level where it is born: the field's range spread from the rim (bottom) to the centre (top).
pub fn level_at(field: u8, x: i32, y: i32) -> u8 {
    let f = &FIELDS[field as usize];
    let d = (crate::util::isqrt(crate::util::d2(x, y, FIELD / 2, FIELD / 2)) / SUB as i64).min(LEVEL_RIM_PX as i64) as i32;
    let span = (f.top - f.bottom) as i32;
    (f.top as i32 - (span * d + LEVEL_RIM_PX / 2) / LEVEL_RIM_PX) as u8
}

fn site_pos(s: Site) -> (i32, i32) {
    let (dx, dy) = at_angle(s.0, s.1 * SUB);
    (FIELD / 2 + dx, FIELD / 2 + dy)
}

/// Water cleared of its wall is dry ground: the mire bit goes with it.
#[inline]
fn drained(c: u8, clear: u8) -> u8 {
    if clear & WALL != 0 && c & WATER == WATER { MIRE } else { 0 }
}

pub(crate) struct Gen {
    pub(crate) map: Vec<u8>,
    pub(crate) rng: u64,
}

impl Gen {
    pub(crate) fn r(&mut self, n: i32) -> i32 {
        (rng_next(&mut self.rng) % n.max(1) as u64) as i32
    }
    pub(crate) fn range(&mut self, a: i32, b: i32) -> i32 {
        a + self.r(b - a + 1)
    }
    pub(crate) fn disc(&mut self, cx: i32, cy: i32, r: i32, set: u8, clear: u8) {
        for y in (cy - r).max(0)..=(cy + r).min(W - 1) {
            for x in (cx - r).max(0)..=(cx + r).min(W - 1) {
                let (dx, dy) = (x - cx, y - cy);
                if dx * dx + dy * dy <= r * r + r {
                    let c = &mut self.map[idx(x, y)];
                    *c = (*c & !clear & !drained(*c, clear)) | set;
                }
            }
        }
    }
    pub(crate) fn rect(&mut self, x0: i32, y0: i32, x1: i32, y1: i32, set: u8, clear: u8) {
        for y in y0.max(0)..=y1.min(W - 1) {
            for x in x0.max(0)..=x1.min(W - 1) {
                let c = &mut self.map[idx(x, y)];
                *c = (*c & !clear & !drained(*c, clear)) | set;
            }
        }
    }
    /// A brush of radius r stamped along a straight line.
    pub(crate) fn line(&mut self, a: (i32, i32), b: (i32, i32), r: i32, set: u8, clear: u8) {
        let n = (a.0 - b.0).abs().max((a.1 - b.1).abs()).max(1);
        for s in 0..=n {
            let x = a.0 + (b.0 - a.0) * s / n;
            let y = a.1 + (b.1 - a.1) * s / n;
            self.disc(x, y, r, set, clear);
        }
    }
    /// A wandering path through `bends` random midpoints.
    pub(crate) fn path(&mut self, a: (i32, i32), b: (i32, i32), r: i32, wobble: i32, bends: i32, set: u8, clear: u8) {
        let mut prev = a;
        for k in 1..=bends {
            let p = if k == bends {
                b
            } else {
                let x = a.0 + (b.0 - a.0) * k / bends + self.range(-wobble, wobble);
                let y = a.1 + (b.1 - a.1) * k / bends + self.range(-wobble, wobble);
                (x.clamp(r + 1, W - r - 2), y.clamp(r + 1, W - r - 2))
            };
            self.line(prev, p, r, set, clear);
            prev = p;
        }
    }
    /// A ruin: a rectangle's outline with a door at least `MIN_PASSAGE` wide.
    pub(crate) fn ruin(&mut self, x: i32, y: i32, w: i32, h: i32) {
        self.rect(x, y, x + w, y, WALL, 0);
        self.rect(x, y + h, x + w, y + h, WALL, 0);
        self.rect(x, y, x, y + h, WALL, 0);
        self.rect(x + w, y, x + w, y + h, WALL, 0);
        let door = MIN_PASSAGE + self.r(3);
        match self.r(4) {
            0 => self.rect(x + 1, y, x + door, y, 0, WALL),
            1 => self.rect(x + 1, y + h, x + door, y + h, 0, WALL),
            2 => self.rect(x, y + 1, x, y + door, 0, WALL),
            _ => self.rect(x + w, y + 1, x + w, y + door, 0, WALL),
        }
    }
    pub(crate) fn hedges(&mut self, n: i32, x0: i32, y0: i32, x1: i32, y1: i32) {
        for _ in 0..n {
            let (x, y) = (self.range(x0, x1), self.range(y0, y1));
            let len = self.range(4, 14);
            if self.r(2) == 0 {
                self.rect(x, y, x + len, y, WALL, 0);
            } else {
                self.rect(x, y, x, y + len, WALL, 0);
            }
        }
    }
    pub(crate) fn blobs(&mut self, n: i32, rmin: i32, rmax: i32, set: u8) {
        for _ in 0..n {
            let (x, y, r) = (self.r(W), self.r(W), self.range(rmin, rmax));
            self.disc(x, y, r, set, 0);
        }
    }
}

/// Builds and repairs the map of `field` from `seed`.
pub fn build(field: u8, seed: u64) -> Terrain {
    let row = &FIELDS[field as usize];
    let gate = (FIELD / 2, FIELD - GATE_INSET_PX * SUB);
    let heart = (FIELD / 2, FIELD / 2);
    let waystones = row.waystones.map(site_pos);
    let altars = row.altars.map(site_pos);
    let mut sites = vec![gate];
    sites.extend_from_slice(&waystones);
    sites.extend_from_slice(&altars);
    sites.push(heart);
    let cells: Vec<(i32, i32)> = sites.iter().map(|&p| cell_xy(p)).collect();
    let mut g = Gen { map: vec![0; CELLS], rng: seed ^ 0x7E44_A1C0_0000_0000 ^ ((field as u64) << 40) };
    match row.rule {
        Rule::Road => terrain_gen::gen_road(&mut g, &cells),
        Rule::Wood => terrain_gen::gen_wood(&mut g, &cells),
        Rule::Marsh => terrain_gen::gen_marsh(&mut g, &cells),
        Rule::Peaks => terrain_gen::gen_peaks(&mut g, &cells),
        Rule::Tower => terrain_gen::gen_tower(&mut g, &cells),
        Rule::Edge => terrain_gen::gen_edge(&mut g, &cells),
    }
    // The quiet zones (rules 6, quiet zones), from the field's own stream after its generator: placed, then cleared with a ring
    // round each so monsters walk round them, and joined to the gate like the sites.
    let quiet = place_quiet(&mut g, gate, &waystones, &cells);
    for z in &quiet {
        let (x, y) = cell_xy((z.x, z.y));
        g.disc(x, y, z.r + QUIET_RING, 0, WALL);
    }
    clear_sites(&mut g, &cells);
    let mut must: Vec<(i32, i32)> = cells.clone();
    must.extend(quiet.iter().map(|z| cell_xy((z.x, z.y))));
    let gate_c = must[0];
    for round in 0..REPAIR_ROUNDS {
        fill_narrow(&mut g.map);
        let reach = flood(&g.map, gate_c);
        let cut: Vec<(i32, i32)> = must.iter().copied().filter(|&(x, y)| !reach[idx(x, y)]).collect();
        if cut.is_empty() && narrow_count(&g.map) == 0 {
            break;
        }
        // Carve each cut-off site a straight corridor to the nearest reached site.
        for &c in &cut {
            let to =
                must.iter().copied().filter(|&(x, y)| reach[idx(x, y)]).min_by_key(|&(x, y)| ((x - c.0).pow(2) + (y - c.1).pow(2), x, y)).unwrap_or(gate_c);
            g.disc(c.0, c.1, SITE_CLEAR, 0, WALL);
            g.line(c, to, REPAIR_R + round as i32 / 2, 0, WALL);
        }
    }
    fill_narrow(&mut g.map);
    // Ground nobody can reach from the gate becomes wall, so nothing is born or stranded there.
    let reach = flood(&g.map, gate_c);
    for c in 0..CELLS {
        if !reach[c] {
            g.map[c] = WALL;
        }
    }
    // The quiet bit on the open cells of each zone's disc.
    for z in &quiet {
        let (cx, cy) = cell_xy((z.x, z.y));
        for y in (cy - z.r).max(0)..=(cy + z.r).min(W - 1) {
            for x in (cx - z.r).max(0)..=(cx + z.r).min(W - 1) {
                let (dx, dy) = (x - cx, y - cy);
                if dx * dx + dy * dy <= z.r * z.r + z.r && g.map[idx(x, y)] & WALL == 0 {
                    g.map[idx(x, y)] |= QUIET;
                }
            }
        }
    }
    let hash = map_hash(&g.map);
    let edges = edges_of(&g.map);
    Terrain { field, map: g.map, gate, waystones, altars, heart, quiet, hash, edges }
}


/// A vault's arena (rules 10): a square of `VAULT_ARENA_PX` at the heart, walled all round, with a few pillars
/// from the seed. No gate and no waystones (they sit in the walls, where nobody stands).
pub fn build_vault(field: u8, seed: u64) -> Terrain {
    let mut map = vec![WALL; CELLS];
    let half = VAULT_ARENA_PX / 64;
    let c = W / 2;
    for y in c - half..c + half {
        for x in c - half..c + half {
            map[idx(x, y)] = 0;
        }
    }
    let mut g = Gen { map, rng: seed ^ 0x5A17_0000_0000_0000 ^ ((field as u64) << 40) };
    for _ in 0..PILLARS {
        let span = (half - 2 * PILLAR_EDGE) as i32;
        let (cx, cy) = (c - half + PILLAR_EDGE + g.r(span), c - half + PILLAR_EDGE + g.r(span));
        if (cx - c).abs() < PILLAR_CLEAR && (cy - c).abs() < PILLAR_CLEAR {
            continue;
        }
        g.disc(cx, cy, PILLAR_R, WALL, 0);
    }
    let hash = map_hash(&g.map);
    let heart = (FIELD / 2, FIELD / 2);
    let edges = edges_of(&g.map);
    Terrain { field, map: g.map, gate: (0, 0), waystones: [(0, 0); 7], altars: [(0, 0); 6], heart, quiet: Vec::new(), hash, edges }
}

/// The town's training yard (job R3): an open square of `YARD_PX` walled round, no sites (no gate, no waystones,
/// so no safe ground), the same for every seed.
pub fn build_yard(seed: u64) -> Terrain {
    let _ = seed;
    let mut map = vec![WALL; CELLS];
    let half = crate::pvp::YARD_PX / 64;
    let c = W / 2;
    for y in c - half..c + half {
        for x in c - half..c + half {
            map[idx(x, y)] = 0;
        }
    }
    let hash = map_hash(&map);
    let heart = (FIELD / 2, FIELD / 2);
    let edges = edges_of(&map);
    Terrain { field: 0, map, gate: (0, 0), waystones: [(0, 0); 7], altars: [(0, 0); 6], heart, quiet: Vec::new(), hash, edges }
}

/// Pillars in a vault, their radius, the cells they keep from the walls and from the centre.
const PILLARS: u32 = 8;
const PILLAR_R: i32 = 2;
const PILLAR_EDGE: i32 = 6;
const PILLAR_CLEAR: i32 = 8;

fn map_hash(map: &[u8]) -> u64 {
    let mut h = 0xCBF2_9CE4_8422_2325u64;
    for ch in map.chunks(8) {
        let mut w = [0u8; 8];
        w[..ch.len()].copy_from_slice(ch);
        h = (h.rotate_left(5) ^ u64::from_le_bytes(w)).wrapping_mul(0x9E37_79B9_7F4A_7C15);
    }
    h
}

fn clear_sites(g: &mut Gen, cells: &[(i32, i32)]) {
    for &(x, y) in cells {
        g.disc(x, y, SITE_CLEAR, 0, WALL);
    }
}

/// 4-neighbour reach from a cell over open ground.
pub fn flood(map: &[u8], from: (i32, i32)) -> Vec<bool> {
    let mut seen = vec![false; CELLS];
    let mut q = vec![idx(from.0, from.1)];
    if map[q[0]] & WALL != 0 {
        return seen;
    }
    seen[q[0]] = true;
    let mut h = 0;
    while h < q.len() {
        let c = q[h];
        h += 1;
        let (x, y) = ((c % CELLS_W) as i32, (c / CELLS_W) as i32);
        for (ox, oy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let (nx, ny) = (x + ox, y + oy);
            if inside(nx, ny) {
                let n = idx(nx, ny);
                if !seen[n] && map[n] & WALL == 0 {
                    seen[n] = true;
                    q.push(n);
                }
            }
        }
    }
    seen
}

/// The scan lines: rows, columns and both diagonals, as (start, step, length, minimum gap).
fn scan_lines() -> Vec<((i32, i32), (i32, i32), i32)> {
    let mut v = Vec::new();
    for k in 0..W {
        v.push(((0, k), (1, 0), MIN_PASSAGE));
        v.push(((k, 0), (0, 1), MIN_PASSAGE));
    }
    for k in -(W - 1)..W {
        // x - y = k going down-right; x + y = k + W - 1 going down-left.
        let s1 = if k >= 0 { (k, 0) } else { (0, -k) };
        v.push((s1, (1, 1), MIN_DIAG));
        let s = k + W - 1;
        let s2 = if s < W { (s, 0) } else { (W - 1, s - W + 1) };
        v.push((s2, (-1, 1), MIN_DIAG));
    }
    v
}

/// Gaps of open ground narrower than the minimum between two walls (the field's border counts as wall
/// on rows and columns) along every scan line: calls `f` with each gap's cells.
fn narrow_gaps(map: &[u8], mut f: impl FnMut(&[usize])) {
    let mut run: Vec<usize> = Vec::new();
    for ((sx, sy), (dx, dy), min) in scan_lines() {
        let border_wall = dx == 0 || dy == 0;
        let (mut x, mut y) = (sx, sy);
        let mut walled = border_wall;
        run.clear();
        while inside(x, y) {
            let c = idx(x, y);
            if map[c] & WALL != 0 {
                if walled && !run.is_empty() && (run.len() as i32) < min {
                    f(&run);
                }
                walled = true;
                run.clear();
            } else {
                run.push(c);
            }
            x += dx;
            y += dy;
        }
        if border_wall && walled && !run.is_empty() && (run.len() as i32) < min {
            f(&run);
        }
    }
}

/// How many narrow gaps the map has (the check).
pub fn narrow_count(map: &[u8]) -> usize {
    let mut n = 0;
    narrow_gaps(map, |_| n += 1);
    n
}

/// Fills every narrow gap with wall until none is left.
fn fill_narrow(map: &mut [u8]) {
    for _ in 0..GAP_PASSES {
        let mut fill = Vec::new();
        narrow_gaps(map, |g| fill.extend_from_slice(g));
        if fill.is_empty() {
            return;
        }
        for c in fill {
            map[c] = WALL;
        }
    }
}

/// The checks of section 6: every site reachable from the gate, no passage under `MIN_PASSAGE` cells.
pub fn check(t: &Terrain) -> Result<(), String> {
    let gate = cell_xy(t.gate);
    let reach = flood(&t.map, gate);
    for (k, s) in t.sites().iter().enumerate() {
        let (x, y) = cell_xy(*s);
        if !reach[idx(x, y)] {
            return Err(format!("site {k} at cell ({x}, {y}) unreachable"));
        }
    }
    for (k, z) in t.quiet.iter().enumerate() {
        let (x, y) = cell_xy((z.x, z.y));
        if !reach[idx(x, y)] || t.map[idx(x, y)] & QUIET == 0 {
            return Err(format!("quiet zone {k} at cell ({x}, {y}) unreachable or not quiet"));
        }
    }
    let n = narrow_count(&t.map);
    if n > 0 {
        return Err(format!("{n} passages under {MIN_PASSAGE} cells"));
    }
    Ok(())
}

pub(crate) fn near_site(cells: &[(i32, i32)], x: i32, y: i32, r: i32) -> bool {
    cells.iter().any(|&(sx, sy)| (sx - x).pow(2) + (sy - y).pow(2) <= r * r)
}
