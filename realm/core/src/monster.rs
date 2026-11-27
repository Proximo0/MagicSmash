//! Monsters (rules section 4): flat arrays, levels and ranks, the 14 behaviours in movement, contact,
//! the bolt and lob pool, births outside every hero's screen, recycling.

use crate::flow::{NEIGHBOURS, STEP, UNREACHED};
use crate::tables::*;
use crate::util::{d2, grid_box, isqrt, par_ranges, pct};
use crate::{CELL_SHIFT, CELLS_W, FIELD, Field, GRID_MARGIN, PCELL_SHIFT, PCELLS_W, SUB, Shot, cell_of};

pub const ELITE: u8 = 1;
pub const CHAMPION: u8 = 2;
/// A boss's monster slot (rules 8): its health is `Monsters::boss_max`, it takes no stun, slow, push or pull, and
/// it neither walks by the flow nor strikes by contact (its attacks are `boss.rs`).
pub const BOSS: u8 = 4;
/// Aura map bits (cells near a howler, wailer, or a mender on a mend tick).
pub const AURA_HOWL: u8 = 1;
pub const AURA_WAIL: u8 = 2;
pub const AURA_MEND: u8 = 4;
/// Monsters at most this many to a 32 px cell before they are pushed to a less crowded neighbour.
pub const CROWD_CAP: u32 = 6;
/// Births: tries per monster and failures before giving up for the tick.
pub const SPAWN_TRIES: u32 = 16;
pub const SPAWN_FAILS_PER_TICK: u32 = 1_024;
/// A monster this many cells (beyond its hero's head start) from the nearest hero is recycled.
pub const RECYCLE_CELLS: u16 = 64;
/// The straight-line check behind it works on blocks of 8 cells (a hero within about 64 cells keeps it).
pub const RECYCLE_BLOCK_SHIFT: u32 = CELL_SHIFT + 3;
const RECYCLE_BLOCKS_W: i32 = (FIELD >> RECYCLE_BLOCK_SHIFT) as i32;
const RECYCLE_REACH_BLOCKS: i32 = RECYCLE_CELLS as i32 / 8;
/// A monster's body: its centre keeps this far (px) from walls and quiet zones (`off_walls`).
pub const BODY_PX: i32 = 8;
/// Clutch members stand this far apart (px).
pub const CLUTCH_PX: i32 = 18;
/// Splitter children land this far from their parent (px).
pub const SPLIT_PX: i32 = 10;
/// Monster threads take at least this many monsters each.
pub const MOVE_MIN_PER_THREAD: usize = 2_048;

/// Monsters as flat arrays indexed by id (slot). A slot with `hp == 0` is empty.
#[derive(Clone, Debug, Default)]
pub struct Monsters {
    pub x: Vec<i32>,
    pub y: Vec<i32>,
    pub hp: Vec<u32>,
    /// Kind id 0..41.
    pub kind: Vec<u8>,
    pub level: Vec<u8>,
    /// `ELITE`, `CHAMPION`.
    pub flags: Vec<u8>,
    /// Monster effects: three small timers.
    pub stun: Vec<u8>,
    pub slow: Vec<u8>,
    pub curse: Vec<u8>,
    /// A behaviour's timer (runner sprint and rest, spitter and lobber reload, leaper wait).
    pub timer: Vec<u8>,
    /// Hurt this tick: output only.
    pub hurt: Vec<u8>,
    /// The health of the boss, when one runs (one at a time).
    pub boss_max: u32,
    /// Monster health and damage percent (a vault's seals): 100 in a field.
    pub scale_pct: u32,
}

impl Monsters {
    pub fn new(cap: usize) -> Monsters {
        Monsters {
            x: vec![0; cap],
            y: vec![0; cap],
            hp: vec![0; cap],
            kind: vec![0; cap],
            level: vec![1; cap],
            flags: vec![0; cap],
            stun: vec![0; cap],
            slow: vec![0; cap],
            curse: vec![0; cap],
            timer: vec![0; cap],
            hurt: vec![0; cap],
            boss_max: 0,
            scale_pct: 100,
        }
    }
    pub fn len(&self) -> usize {
        self.hp.len()
    }
    pub fn is_empty(&self) -> bool {
        self.hp.is_empty()
    }
    pub fn row(&self, i: usize) -> &'static Kind {
        &KINDS[self.kind[i] as usize]
    }
    pub fn is_elite(&self, i: usize) -> bool {
        self.flags[i] & ELITE != 0
    }
    pub fn is_champion(&self, i: usize) -> bool {
        self.flags[i] & CHAMPION != 0
    }
    pub fn max_hp(&self, i: usize) -> u32 {
        if self.flags[i] & BOSS != 0 {
            return self.boss_max;
        }
        pct(max_hp(self.kind[i], self.level[i], self.flags[i]), self.scale_pct as i64).max(1)
    }
    pub fn is_boss(&self, i: usize) -> bool {
        self.flags[i] & BOSS != 0
    }
    /// Stun, slow, push and pull find no purchase: brutes and bosses.
    pub fn immovable(&self, i: usize) -> bool {
        self.flags[i] & BOSS != 0 || self.row(i).beh & BRUTE != 0
    }
    /// Contact damage per hit at its level.
    pub fn damage(&self, i: usize) -> u32 {
        let d = level_scale(self.row(i).damage, self.level[i], POWER_PCT_PER_LEVEL);
        let d = if self.is_champion(i) { d * CHAMPION_DAMAGE_MUL } else { d };
        pct(d, self.scale_pct as i64).max(1)
    }
    /// XP (and coin) a kill pays.
    pub fn xp(&self, i: usize) -> u32 {
        let row = self.row(i);
        let x = level_scale(row.xp, self.level[i], POWER_PCT_PER_LEVEL) * FIELD_XP_PCT[row.field as usize % FIELD_XP_PCT.len()] / 100;
        if self.is_boss(i) {
            x * BOSS_XP_MUL
        } else if self.is_champion(i) {
            x * CHAMPION_XP_MUL
        } else if self.is_elite(i) {
            x * ELITE_XP_MUL
        } else {
            x
        }
    }
}

/// `v x (100 + per x (level - 1))%`.
pub fn level_scale(v: u32, level: u8, per: u32) -> u32 {
    pct(v, (100 + per * (level.max(1) as u32 - 1)) as i64).max(1)
}

pub fn max_hp(kind: u8, level: u8, flags: u8) -> u32 {
    let h = level_scale(KINDS[kind as usize].health, level, HEALTH_PCT_PER_LEVEL);
    if flags & CHAMPION != 0 {
        h * CHAMPION_HEALTH_MUL
    } else if flags & ELITE != 0 {
        h * ELITE_HEALTH_MUL
    } else {
        h
    }
}

/// A monster's wish to throw: a bolt toward a point or a lob landing on it.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Throw {
    x: i32,
    y: i32,
    tx: i32,
    ty: i32,
    dmg: u32,
    lob: bool,
    /// The monster that threw it, so a throw the pool has no room for lets it throw again next tick.
    who: u32,
}

#[inline]
fn within(ax: i32, ay: i32, bx: i32, by: i32, px: i32) -> bool {
    let r = (px * SUB) as i64;
    d2(ax, ay, bx, by) <= r * r
}

impl Field {
    /// Grid phase, monster part: recycle the left-behind, build the grid and the aura map.
    pub(crate) fn build_monster_grid(&mut self) {
        self.mcells.clear();
        self.aura_list.clear();
        let mend_tick = self.tick % MEND_EVERY == 0;
        // Blocks with a hero in them: a monster far behind on the flow is still kept when a hero is near in
        // a straight line (across a wall).
        let bw = RECYCLE_BLOCKS_W;
        let mut near = vec![false; (bw * bw) as usize];
        let mut anyone = false;
        for h in self.heroes.iter().filter(|h| h.present) {
            near[((h.y >> RECYCLE_BLOCK_SHIFT) * bw + (h.x >> RECYCLE_BLOCK_SHIFT)) as usize] = true;
            anyone = true;
        }
        let hero_near = |x: i32, y: i32| {
            let (bx, by) = (x >> RECYCLE_BLOCK_SHIFT, y >> RECYCLE_BLOCK_SHIFT);
            let r = RECYCLE_REACH_BLOCKS;
            ((by - r).max(0)..=(by + r).min(bw - 1)).any(|yy| ((bx - r).max(0)..=(bx + r).min(bw - 1)).any(|xx| near[(yy * bw + xx) as usize]))
        };
        let m = &mut self.m;
        for i in 0..m.hp.len() {
            if m.hp[i] == 0 {
                continue;
            }
            let c = cell_of(m.x[i], m.y[i]);
            let d = self.flow.dist[c];
            if m.flags[i] & BOSS == 0 && (d != UNREACHED || anyone) {
                // Unreached by the flow (every hero sheltered in a quiet zone, or none chased) counts as far.
                let base = self.src_d0.get(self.flow.src[c] as usize).copied().unwrap_or(0);
                if (d == UNREACHED || d.saturating_sub(base) > RECYCLE_CELLS * STEP) && !hero_near(m.x[i], m.y[i]) {
                    // Left far behind by every hero: free the slot so births put it back in play.
                    m.hp[i] = 0;
                    self.free.push(i as u32);
                    self.alive -= 1;
                    self.recycled_total += 1;
                    continue;
                }
            }
            let beh = KINDS[m.kind[i] as usize].beh;
            if m.flags[i] & BOSS == 0 && (beh & (HOWLER | WAILER) != 0 || (mend_tick && beh & MENDER != 0)) {
                self.aura_list.push(i as u32);
            }
            self.mcells.push((i as u32, c as u32));
        }
        self.grid.build(&self.mcells);
        // The aura map: cells whose centre is within reach of a howler, wailer or mender.
        for &c in &self.aura_cells {
            self.aura[c as usize] = 0;
        }
        self.aura_cells.clear();
        for k in 0..self.aura_list.len() {
            let i = self.aura_list[k] as usize;
            let beh = KINDS[self.m.kind[i] as usize].beh;
            for (bit, b, px) in [(AURA_HOWL, HOWLER, HOWL_PX), (AURA_WAIL, WAILER, WAIL_PX), (AURA_MEND, MENDER, MEND_PX)] {
                if beh & b == 0 || (bit == AURA_MEND && !mend_tick) {
                    continue;
                }
                mark_cells(&mut self.aura, &mut self.aura_cells, self.m.x[i], self.m.y[i], px, bit);
            }
        }
    }

    /// The move phase: monsters in parallel (each reads the others' last positions through the grid),
    /// then their throws join the pool in id order.
    pub(crate) fn phase_move(&mut self) {
        let m = &mut self.m;
        for i in 0..m.hp.len() {
            if m.hp[i] > 0 {
                m.stun[i] = m.stun[i].saturating_sub(1);
                m.slow[i] = m.slow[i].saturating_sub(1);
                m.curse[i] = m.curse[i].saturating_sub(1);
            }
        }
        let n = self.m.hp.len();
        let room = self.shots.len() < SHOT_POOL;
        let this = &*self;
        let outs = par_ranges(n, this.cfg.threads, MOVE_MIN_PER_THREAD, |a, b| this.move_range(a, b, room));
        let mut at = 0;
        let mut throws = Vec::new();
        // Ranges come back in order, so the k-th result of a range is monster `at + k`.
        for (moves, th) in outs {
            let len = moves.len();
            for (k, (x, y, t)) in moves.into_iter().enumerate() {
                let i = at + k;
                self.m.x[i] = x;
                self.m.y[i] = y;
                self.m.timer[i] = t;
            }
            at += len;
            throws.extend(th);
        }
        for t in throws {
            if self.shots.len() >= SHOT_POOL {
                self.m.timer[t.who as usize] = 0;
                continue;
            }
            self.shots.push(make_shot(&t));
        }
    }

    fn move_range(&self, a: usize, b: usize, room: bool) -> (Vec<(i32, i32, u8)>, Vec<Throw>) {
        let mut out = Vec::with_capacity(b - a);
        let mut throws = Vec::new();
        for i in a..b {
            out.push(self.move_one(i, room, &mut throws));
        }
        (out, throws)
    }

    fn move_one(&self, i: usize, room: bool, throws: &mut Vec<Throw>) -> (i32, i32, u8) {
        let m = &self.m;
        let (x, y, mut t) = (m.x[i], m.y[i], m.timer[i]);
        if m.hp[i] == 0 || m.stun[i] > 0 || m.flags[i] & BOSS != 0 {
            return (x, y, t);
        }
        let c = cell_of(x, y);
        if self.terrain.at_cell(c) & QUIET != 0 {
            // Inside a quiet zone (placed there, or born before it formed): straight out from its centre.
            let (nx, ny) = self.quiet_push(x, y, m.row(i).speed as i32);
            return (nx, ny, t);
        }
        let d = self.flow.dist[c];
        if d == UNREACHED {
            return (x, y, t);
        }
        let row = m.row(i);
        let beh = row.beh;
        let hero = &self.heroes[self.flow.src[c] as usize];
        let hd = if hero.alive() { isqrt(d2(hero.x, hero.y, x, y)) / SUB as i64 } else { i64::MAX } as i64;
        let mut speed = row.speed as i64 * SUB as i64 / TICK_HZ as i64;
        if self.quick() {
            speed = speed * TIDE_SPEED_PCT as i64 / 100;
        }
        if m.slow[i] > 0 && beh & BRUTE == 0 {
            speed = speed * SLOW_SPEED_PCT as i64 / 100;
        }
        if self.aura[c] & AURA_HOWL != 0 {
            speed = speed * HOWL_SPEED_PCT as i64 / 100;
        }
        let mut stop = false;
        if beh & RUNNER != 0 {
            if t > RUNNER_REST_TICKS {
                t -= 1;
                speed = speed * RUNNER_SPEED_PCT as i64 / 100;
            } else if t > 0 {
                t -= 1;
            } else if hd <= RUNNER_NEAR_PX as i64 {
                // This tick is the first of the sprint.
                t = RUNNER_SPRINT_TICKS + RUNNER_REST_TICKS - 1;
                speed = speed * RUNNER_SPEED_PCT as i64 / 100;
            }
        }
        if beh & (SPITTER | LOBBER) != 0 && room {
            let (near, every, lob) = if beh & SPITTER != 0 { (SPITTER_STOP_PX, SPIT_EVERY, false) } else { (LOBBER_STOP_PX, LOB_EVERY, true) };
            if hd <= near as i64 {
                stop = true;
                if t == 0 {
                    throws.push(Throw { x, y, tx: hero.x, ty: hero.y, dmg: m.damage(i), lob, who: i as u32 });
                    t = every - 1;
                } else {
                    t -= 1;
                }
            } else {
                t = t.saturating_sub(1);
            }
        }
        if beh & LEAPER != 0 {
            if t > 0 {
                t -= 1;
            } else if hd <= LEAP_NEAR_PX as i64 {
                // Over the front rank onto the hero with the lowest threat near it.
                let r = LEAP_NEAR_PX * SUB;
                let mut best: Option<(i32, u32)> = None;
                grid_box(&self.hgrid, PCELLS_W, PCELL_SHIFT, x - r, y - r, x + r, y + r, |q| {
                    let qh = &self.heroes[q as usize];
                    if qh.alive() && within(qh.x, qh.y, x, y, LEAP_NEAR_PX) && !self.terrain.quiet(qh.x, qh.y) {
                        let th = self.threat[q as usize];
                        if best.is_none_or(|(bt, bq)| th < bt || (th == bt && q < bq)) {
                            best = Some((th, q));
                        }
                    }
                });
                if let Some((_, q)) = best {
                    let qh = &self.heroes[q as usize];
                    let (lx, ly) = self.terrain.mslide(qh.x, qh.y, qh.x + (x - qh.x).signum() * STOP_PX * SUB, qh.y);
                    return (lx, ly, LEAP_EVERY - 1);
                }
            }
        }
        if stop {
            return (x, y, t);
        }
        // Inside two cells: straight at the hero with the highest threat / distance.
        let base = self.src_d0.get(self.flow.src[c] as usize).copied().unwrap_or(0);
        let mut target = None;
        if d.saturating_sub(base) <= CLOSE_CELLS as u16 * STEP + STEP && self.grid.count(c) <= CROWD_CAP {
            let r = CLOSE_CELLS as i32 * (1 << CELL_SHIFT);
            let mut best: Option<(i64, i64, u32)> = None;
            grid_box(&self.hgrid, PCELLS_W, PCELL_SHIFT, x - r, y - r, x + r, y + r, |q| {
                let qh = &self.heroes[q as usize];
                let dd = d2(qh.x, qh.y, x, y).max(1);
                if qh.alive() && dd <= r as i64 * r as i64 && !self.terrain.quiet(qh.x, qh.y) {
                    let th = self.threat[q as usize] as i64;
                    let t2 = th * th;
                    // threat / distance highest: t2 / dd highest.
                    if best.is_none_or(|(bt2, bdd, bq)| t2 * bdd > bt2 * dd || (t2 * bdd == bt2 * dd && q < bq)) {
                        best = Some((t2, dd, q));
                    }
                }
            });
            if let Some((_, _, q)) = best {
                let qh = &self.heroes[q as usize];
                // Straight at her only when no wall corner stands between (else the flow goes round it).
                let open = (1..4).all(|k| !self.terrain.blocked(x + (qh.x - x) * k / 4, y + (qh.y - y) * k / 4));
                if open {
                    target = Some((qh.x, qh.y, STOP_PX * SUB));
                }
            }
        }
        let (tx, ty, stop_at) = match target {
            Some(t) => t,
            None => {
                let cx = (c % CELLS_W) as i32;
                let cy = (c / CELLS_W) as i32;
                let mut best = (i64::MAX, i64::MAX, cx, cy);
                // Ties in the flow (every step costs the same) go to the cell nearest the hero it leads to,
                // so a monster bends smoothly instead of favouring the first neighbour listed.
                let (hx, hy) = self.heroes.get(self.flow.src[c] as usize).filter(|h| h.alive()).map_or((x, y), |h| (h.x, h.y));
                let half = 1 << (CELL_SHIFT - 1);
                for (ox, oy) in NEIGHBOURS {
                    let nx = cx + ox;
                    let ny = cy + oy;
                    if nx < 0 || ny < 0 || nx >= CELLS_W as i32 || ny >= CELLS_W as i32 {
                        continue;
                    }
                    let nc = ny as usize * CELLS_W + nx as usize;
                    let nd = self.flow.dist[nc];
                    // Never a step back down the flow: in a corridor a crowd waits its turn instead of
                    // swaying back and forth at the mouth.
                    if nd == UNREACHED || nd > d {
                        continue;
                    }
                    if ox != 0 && oy != 0 {
                        let a = cy as usize * CELLS_W + nx as usize;
                        let b = ny as usize * CELLS_W + cx as usize;
                        if self.terrain.at_cell(a) & MONSTER_BLOCK != 0 || self.terrain.at_cell(b) & MONSTER_BLOCK != 0 {
                            continue;
                        }
                    }
                    let over = self.grid.count(nc).saturating_sub(CROWD_CAP) as i64;
                    let score = nd as i64 * 2 + over * STEP as i64;
                    if score > best.0 {
                        continue;
                    }
                    let near = d2((nx << CELL_SHIFT) + half, (ny << CELL_SHIFT) + half, hx, hy);
                    if score < best.0 || near < best.1 {
                        best = (score, near, nx, ny);
                    }
                }
                // The cell centre plus a per-monster offset so a crowd does not form a line.
                let h = (i as u32).wrapping_mul(2_654_435_761);
                let jx = ((h >> 8) % 17) as i32 - 8;
                let jy = ((h >> 20) % 17) as i32 - 8;
                ((best.2 << CELL_SHIFT) + half + jx * SUB, (best.3 << CELL_SHIFT) + half + jy * SUB, 0)
            }
        };
        let dx = (tx - x) as i64;
        let dy = (ty - y) as i64;
        let len = isqrt(dx * dx + dy * dy);
        if len <= stop_at as i64 {
            return (x, y, t);
        }
        let go = (len - stop_at as i64).min(speed);
        let (nx, ny) = self.terrain.mslide(x, y, x + (dx * go / len) as i32, y + (dy * go / len) as i32);
        let (nx, ny) = self.off_walls(nx, ny);
        (nx, ny, t)
    }

    /// Keeps a monster's body (`BODY_PX`) off the closed cells beside its own: its centre is held that far in from
    /// any side of its cell that faces a wall or a quiet zone, and from a closed diagonal corner. Four or five cell
    /// reads; it never leaves the cell it is in.
    #[inline]
    pub(crate) fn off_walls(&self, x: i32, y: i32) -> (i32, i32) {
        use crate::terrain::*;
        let e = self.terrain.edges[cell_of(x, y)];
        if e == 0 {
            return (x, y);
        }
        let cell = 1 << CELL_SHIFT;
        let b = BODY_PX * SUB;
        let (cx, cy) = (x & !(cell - 1), y & !(cell - 1));
        let (ox, oy) = (x - cx, y - cy);
        let (lo_x, hi_x, lo_y, hi_y) = (ox < b, ox >= cell - b, oy < b, oy >= cell - b);
        let (west, east, north, south) = (lo_x && e & EDGE_W != 0, hi_x && e & EDGE_E != 0, lo_y && e & EDGE_N != 0, hi_y && e & EDGE_S != 0);
        let (mut nx, mut ny) = (x, y);
        if west {
            nx = cx + b;
        } else if east {
            nx = cx + cell - b - 1;
        }
        if north {
            ny = cy + b;
        } else if south {
            ny = cy + cell - b - 1;
        }
        // A closed diagonal corner: out along the smaller way.
        if !(west || east || north || south) && (lo_x || hi_x) && (lo_y || hi_y) {
            let bit = match (lo_x, lo_y) {
                (true, true) => EDGE_NW,
                (false, true) => EDGE_NE,
                (true, false) => EDGE_SW,
                (false, false) => EDGE_SE,
            };
            if e & bit != 0 {
                let (dx, dy) = (if lo_x { b - ox } else { ox - (cell - b - 1) }, if lo_y { b - oy } else { oy - (cell - b - 1) });
                if dx <= dy {
                    nx = if lo_x { cx + b } else { cx + cell - b - 1 };
                } else {
                    ny = if lo_y { cy + b } else { cy + cell - b - 1 };
                }
            }
        }
        (nx, ny)
    }

    /// One tick of a monster leaving a quiet zone: away from the zone's centre at its speed (at least
    /// `QUIET_PUSH_PX`), sliding along walls; when walls hold it, to the nearest open ground outside.
    pub(crate) fn quiet_push(&self, x: i32, y: i32, speed_px_s: i32) -> (i32, i32) {
        let Some(z) = self.terrain.zone_at(x, y) else { return (x, y) };
        let (mut dx, mut dy) = ((x - z.x) as i64, (y - z.y) as i64);
        if dx == 0 && dy == 0 {
            dy = 1;
        }
        let len = isqrt(dx * dx + dy * dy).max(1);
        let go = ((speed_px_s * SUB / TICK_HZ as i32).max(QUIET_PUSH_PX * SUB)) as i64;
        dx = dx * go / len;
        dy = dy * go / len;
        let (nx, ny) = self.terrain.slide(x, y, x + dx as i32, y + dy as i32);
        if (nx, ny) != (x, y) {
            return (nx, ny);
        }
        // Held by walls: the nearest open cell beyond the zone's edge along the way out, else stay.
        let r = ((z.r + 1) << CELL_SHIFT) as i64;
        let (ox, oy) = ((z.x as i64 + (x - z.x) as i64 * r / len.max(1)) as i32, (z.y as i64 + (y - z.y) as i64 * r / len.max(1)) as i32);
        let (px, py) = self.terrain.nearest_open(ox, oy);
        if self.terrain.blocked(px, py) { (x, y) } else { (px, py) }
    }

    /// Contact damage gathered per hero (on her cadence): raw damage and who dealt it.
    pub(crate) fn gather_contact(&self, a: usize, b: usize) -> Vec<(u16, u32, u32)> {
        let m = &self.m;
        let mut out = Vec::new();
        for id in a..b {
            let p = &self.heroes[id];
            // A hero in a quiet zone is out of reach.
            if !p.alive() || (self.tick + id as u32) % CONTACT_EVERY != 0 || self.terrain.quiet(p.x, p.y) {
                continue;
            }
            let r = CONTACT_PX * SUB + GRID_MARGIN;
            let r2 = (CONTACT_PX * SUB) as i64 * (CONTACT_PX * SUB) as i64;
            grid_box(&self.grid, CELLS_W, CELL_SHIFT, p.x - r, p.y - r, p.x + r, p.y + r, |i| {
                let i = i as usize;
                if m.hp[i] > 0 && m.stun[i] == 0 && m.flags[i] & BOSS == 0 && d2(m.x[i], m.y[i], p.x, p.y) <= r2 {
                    out.push((id as u16, i as u32, m.damage(i) * m.row(i).hits as u32));
                }
            });
        }
        out
    }

    /// Moves the monster bolts and counts down the lobbed circles; returns hero damage (hero, raw).
    pub(crate) fn update_shots(&mut self) -> Vec<(u16, u32)> {
        let mut out = Vec::new();
        let high = FIELDS[self.field as usize].high_ground;
        let mut k = 0;
        while k < self.shots.len() {
            let s = &mut self.shots[k];
            let mut done = false;
            if s.px == 0 {
                let (nx, ny) = (s.x + s.vx, s.y + s.vy);
                s.left = s.left.saturating_sub(1);
                if nx < 0 || ny < 0 || nx >= FIELD || ny >= FIELD || (!high && self.terrain.wall(nx, ny)) || self.terrain.quiet(nx, ny) {
                    done = true;
                } else {
                    s.x = nx;
                    s.y = ny;
                    let r = SPIT_HIT_PX * SUB;
                    let mut hit: Option<u32> = None;
                    grid_box(&self.hgrid, PCELLS_W, PCELL_SHIFT, nx - r, ny - r, nx + r, ny + r, |q| {
                        let qh = &self.heroes[q as usize];
                        if qh.alive() && d2(qh.x, qh.y, nx, ny) <= r as i64 * r as i64 && !self.terrain.quiet(qh.x, qh.y) && hit.is_none_or(|b| q < b) {
                            hit = Some(q);
                        }
                    });
                    if let Some(q) = hit {
                        out.push((q as u16, s.dmg));
                        done = true;
                    }
                }
                done |= s.left == 0;
            } else {
                s.left = s.left.saturating_sub(1);
                if s.left == 0 {
                    let (x, y, px, dmg) = (s.x, s.y, s.px, s.dmg);
                    self.circle_on_heroes(x, y, px, dmg, &mut out);
                    done = true;
                }
            }
            if done {
                self.shots[k].left = 0;
                self.shots[k].px = -1;
            }
            k += 1;
        }
        self.shots.retain(|s| s.px >= 0);
        out
    }

    /// Damage to every up hero within px of a point.
    pub(crate) fn circle_on_heroes(&self, x: i32, y: i32, px: i32, dmg: u32, out: &mut Vec<(u16, u32)>) {
        let r = px * SUB;
        let mut v = Vec::new();
        grid_box(&self.hgrid, PCELLS_W, PCELL_SHIFT, x - r, y - r, x + r, y + r, |q| {
            let qh = &self.heroes[q as usize];
            if qh.alive() && d2(qh.x, qh.y, x, y) <= r as i64 * r as i64 && !self.terrain.quiet(qh.x, qh.y) {
                v.push(q as u16);
            }
        });
        v.sort_unstable();
        out.extend(v.into_iter().map(|q| (q, dmg)));
    }
}

/// Where the k-th member of a clutch stands, in clutch spacings: the centre, then around it.
pub fn clutch_offset(k: i32) -> (i32, i32) {
    const RING: [(i32, i32); 8] = [(0, 0), (1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (-1, -1), (1, -1)];
    RING[(k as usize) % RING.len()]
}

fn make_shot(t: &Throw) -> Shot {
    if t.lob {
        // Thrown in the move phase, counted down in the same tick's fight phase.
        return Shot { x: t.tx, y: t.ty, vx: 0, vy: 0, left: LOB_DELAY + 1, dmg: t.dmg, px: LOB_PX };
    }
    let (dx, dy) = ((t.tx - t.x) as i64, (t.ty - t.y) as i64);
    let len = isqrt(dx * dx + dy * dy).max(1);
    let v = (SPIT_SPEED_PX_S * SUB / TICK_HZ as i32) as i64;
    Shot { x: t.x, y: t.y, vx: (dx * v / len) as i32, vy: (dy * v / len) as i32, left: SPIT_LIFE + 1, dmg: t.dmg, px: 0 }
}

/// Marks the cells whose centre is within `px` of a point.
fn mark_cells(map: &mut [u8], marked: &mut Vec<u32>, x: i32, y: i32, px: i32, bit: u8) {
    let r = px * SUB;
    let lim = CELLS_W as i32 - 1;
    let half = 1 << (CELL_SHIFT - 1);
    let (cx0, cy0) = (((x - r) >> CELL_SHIFT).clamp(0, lim), ((y - r) >> CELL_SHIFT).clamp(0, lim));
    let (cx1, cy1) = (((x + r) >> CELL_SHIFT).clamp(0, lim), ((y + r) >> CELL_SHIFT).clamp(0, lim));
    for cy in cy0..=cy1 {
        for cx in cx0..=cx1 {
            let (mx, my) = ((cx << CELL_SHIFT) + half, (cy << CELL_SHIFT) + half);
            if d2(mx, my, x, y) <= r as i64 * r as i64 {
                let c = cy as usize * CELLS_W + cx as usize;
                if map[c] == 0 {
                    marked.push(c as u32);
                }
                map[c] |= bit;
            }
        }
    }
}
