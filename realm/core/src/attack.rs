//! The attack shapes (arc, ring, bolt, drop; zones and dashes in `hero.rs` and `combat.rs`), gathered per
//! hero in parallel from a read-only field and applied in hero order, so any thread count gives the same
//! result. A hit names a monster; heroes are struck through `combat::damage_hero` (kept apart so a later
//! job can let marked heroes' attacks strike heroes).

use crate::hero::{Hero, CAST1};
use crate::mods::{Mods, POWER_ONE};
use crate::monster::{CHAMPION, ELITE};
use crate::tables::*;
use crate::util::{cos_q14, d2, grid_box, isqrt, mix, pct, rotate, Q14};
use crate::{cell_of, Drop, Field, CELLS_W, CELL_SHIFT, GRID_MARGIN, PCELLS_W, PCELL_SHIFT, SUB};

#[derive(Clone, Copy, Debug)]
pub struct Hit {
    pub m: u32,
    pub dmg: u32,
    pub hero: u16,
    pub stun: u8,
    pub slow: u8,
    /// Push in sub units away from (sx, sy).
    pub push: i32,
    pub sx: i32,
    pub sy: i32,
}

/// What one range of heroes wants done, in hero order.
#[derive(Default)]
pub struct Strikes {
    pub hits: Vec<Hit>,
    /// (ally, amount, healer, shield her).
    pub heals: Vec<(u16, u32, u16, bool)>,
    pub drops: Vec<Drop>,
    /// (owner, zone row, x, y, rank %).
    pub zones: Vec<(u16, u8, i32, i32, u32)>,
    pub curses: Vec<(u32, u8)>,
    /// (monster, to x, to y): PROVOKE's pull.
    pub pulls: Vec<(u32, i32, i32)>,
}

/// THE MOON's draw for a hero's n-th hit this tick.
const STREAM_MOON: u64 = 0x4D00_4E00;
/// A dash hits monsters this close to its line (px).
pub const DASH_HALF_WIDTH_PX: i32 = 24;
pub const WARDEN_PROVOKE_PX: i32 = 200;

struct Ctx<'a> {
    f: &'a Field,
    id: usize,
    h: &'a Hero,
    m: &'a Mods,
    n: u64,
}

impl Field {
    pub(crate) fn gather_strikes(&self, a: usize, b: usize) -> Strikes {
        let mut out = Strikes::default();
        for id in a..b {
            let h = &self.heroes[id];
            if !h.alive() || (!h.fired && h.cast == 0) {
                continue;
            }
            let mut c = Ctx { f: self, id, h, m: &self.mods[id], n: 0 };
            if h.fired {
                c.weapon(&mut out);
            }
            for slot in 0..3 {
                if h.cast & (CAST1 << slot) != 0 {
                    if let Some(sk) = h.skill(slot) {
                        c.skill(sk, &mut out);
                    }
                }
            }
        }
        out
    }

    /// The damage multiplier a monster takes from a hero (percent): ELITES, DEATH, curses, shields.
    pub(crate) fn target_pct(&self, m: &Mods, i: usize, sx: i32, sy: i32) -> u64 {
        let mon = &self.m;
        let mut p: u64 = 100;
        if mon.flags[i] & (ELITE | CHAMPION) != 0 {
            p = p * (100 + m.elite_pct) as u64 / 100;
        }
        if m.execute_pct > 0 && (mon.hp[i] as u64 * 100) < mon.max_hp(i) as u64 * m.execute_under as u64 {
            p = p * (100 + m.execute_pct) as u64 / 100;
        }
        if mon.curse[i] > 0 {
            p = p * CURSE_TAKEN_PCT as u64 / 100;
        }
        if mon.row(i).beh & SHIELDED != 0 {
            let (x, y) = (mon.x[i], mon.y[i]);
            let q = &self.heroes[self.flow.src[cell_of(x, y)] as usize];
            let dot = (sx - x) as i64 * (q.x - x) as i64 + (sy - y) as i64 * (q.y - y) as i64;
            if dot > 0 {
                p = p * SHIELD_FRONT_TAKEN_PCT as u64 / 100;
            }
        }
        p
    }

    /// Live monsters within `r` (sub units) of a point, nearest first (ties to the lower id), at most `k`.
    pub(crate) fn nearest_k(&self, x: i32, y: i32, r: i32, k: usize) -> Vec<u32> {
        let m = &self.m;
        let r2 = r as i64 * r as i64;
        let cx = x >> CELL_SHIFT;
        let cy = y >> CELL_SHIFT;
        let rings = ((r + GRID_MARGIN) >> CELL_SHIFT) + 1;
        let mut best: Vec<(i64, u32)> = Vec::new();
        let lim = CELLS_W as i32 - 1;
        for ring in 0..=rings {
            for oy in -ring..=ring {
                let edge = oy == -ring || oy == ring;
                let mut ox = -ring;
                while ox <= ring {
                    let (nx, ny) = (cx + ox, cy + oy);
                    if nx >= 0 && ny >= 0 && nx <= lim && ny <= lim {
                        for &id in self.grid.cell(ny as usize * CELLS_W + nx as usize) {
                            let i = id as usize;
                            if m.hp[i] == 0 {
                                continue;
                            }
                            let dd = d2(m.x[i], m.y[i], x, y);
                            if dd <= r2 {
                                best.push((dd, id));
                            }
                        }
                    }
                    ox += if edge { 1 } else { 2 * ring.max(1) };
                }
            }
            if best.len() >= k {
                best.sort_unstable();
                best.truncate(k);
                let safe = ((ring << CELL_SHIFT) - GRID_MARGIN).max(0) as i64;
                if best[k - 1].0 <= safe * safe {
                    break;
                }
            }
        }
        best.sort_unstable();
        best.truncate(k);
        best.into_iter().map(|(_, i)| i).collect()
    }

    /// Calls `f` for each live monster within `r` of a point.
    pub(crate) fn in_circle(&self, x: i32, y: i32, r: i32, mut f: impl FnMut(usize)) {
        let m = &self.m;
        let r2 = r as i64 * r as i64;
        let rr = r + GRID_MARGIN;
        grid_box(&self.grid, CELLS_W, CELL_SHIFT, x - rr, y - rr, x + rr, y + rr, |i| {
            let i = i as usize;
            if m.hp[i] > 0 && d2(m.x[i], m.y[i], x, y) <= r2 {
                f(i);
            }
        });
    }

    /// Live monsters within `hw` of the segment a-b, by distance along it.
    pub(crate) fn on_line(&self, ax: i32, ay: i32, bx: i32, by: i32, hw: i32) -> Vec<u32> {
        let m = &self.m;
        let (vx, vy) = ((bx - ax) as i64, (by - ay) as i64);
        let len2 = (vx * vx + vy * vy).max(1);
        let mut out: Vec<(i64, u32)> = Vec::new();
        let pad = hw + GRID_MARGIN;
        grid_box(&self.grid, CELLS_W, CELL_SHIFT, ax.min(bx) - pad, ay.min(by) - pad, ax.max(bx) + pad, ay.max(by) + pad, |i| {
            let k = i as usize;
            if m.hp[k] == 0 {
                return;
            }
            let (px, py) = ((m.x[k] - ax) as i64, (m.y[k] - ay) as i64);
            let t = px * vx + py * vy;
            if t < 0 || t > len2 {
                return;
            }
            let cross = (px * vy - py * vx) as i128;
            if cross * cross <= (hw as i128) * (hw as i128) * len2 as i128 {
                out.push((t, i));
            }
        });
        out.sort_unstable();
        out.into_iter().map(|(_, i)| i).collect()
    }

    /// The densest cells within `r` of a point (most monsters first, then the lower cell), as centres.
    pub(crate) fn thickest(&self, x: i32, y: i32, r: i32, n: usize) -> Vec<(i32, i32)> {
        let lim = CELLS_W as i32 - 1;
        let half = 1 << (CELL_SHIFT - 1);
        let (cx0, cy0) = (((x - r) >> CELL_SHIFT).clamp(0, lim), ((y - r) >> CELL_SHIFT).clamp(0, lim));
        let (cx1, cy1) = (((x + r) >> CELL_SHIFT).clamp(0, lim), ((y + r) >> CELL_SHIFT).clamp(0, lim));
        let mut cells: Vec<(u32, usize)> = Vec::new();
        for cy in cy0..=cy1 {
            for cx in cx0..=cx1 {
                let c = cy as usize * CELLS_W + cx as usize;
                let cnt = self.grid.count(c);
                let (mx, my) = ((cx << CELL_SHIFT) + half, (cy << CELL_SHIFT) + half);
                if cnt > 0 && d2(mx, my, x, y) <= r as i64 * r as i64 {
                    cells.push((u32::MAX - cnt, c));
                }
            }
        }
        cells.sort_unstable();
        cells
            .into_iter()
            .take(n)
            .map(|(_, c)| ((((c % CELLS_W) as i32) << CELL_SHIFT) + half, (((c / CELLS_W) as i32) << CELL_SHIFT) + half))
            .collect()
    }
}

impl Ctx<'_> {
    /// Damage of a base number for this hero: the weapon's item level, then MIGHT, field level, cards, effects.
    fn power(&self, base: u32) -> u64 {
        let lvl = weapon_pct(self.h.sheet.weapon_level(self.f.field));
        base as u64 * lvl / 100 * self.m.power / POWER_ONE
    }

    fn hit(&mut self, out: &mut Strikes, i: usize, dmg: u64, stun: u8, slow: u8, push: i32, sx: i32, sy: i32) {
        let f = self.f;
        let mut d = dmg * f.target_pct(self.m, i, sx, sy) / 100;
        if self.m.crit_chance > 0 {
            let r = mix(f.seed ^ STREAM_MOON, f.tick as u64, self.id as u64, self.n);
            if (r % 100) < self.m.crit_chance as u64 {
                d *= 2;
            }
        }
        self.n += 1;
        out.hits.push(Hit { m: i as u32, dmg: d.min(u32::MAX as u64) as u32, hero: self.id as u16, stun, slow, push, sx, sy });
    }

    fn weapon(&mut self, out: &mut Strikes) {
        let h = self.h;
        let w = h.class_row().weapon;
        let pj = h.job_row().map(|j| j.passive).unwrap_or_default();
        let mut base = self.power(w.damage);
        if pj.weapon_dmg_mul_pct > 0 {
            base = base * pj.weapon_dmg_mul_pct as u64 / 100;
        }
        let push = if w.push_px + self.m.push_add > 0 { (w.push_px + self.m.push_add) * SUB } else { 0 };
        let repeats = if self.m.every_nth > 0 && h.attacks % self.m.every_nth == 0 { 1 + self.m.nth_extra } else { 1 };
        let (x, y) = (h.x, h.y);
        let size = self.m.size_pct as i32;
        let reach = self.m.reach_pct as i32;
        let mut struck = false;
        for _ in 0..repeats {
            match w.shape {
                Shape::Arc { deg, px } => {
                    let r = px * size / 100 * reach / 100 * SUB;
                    let Some(&t) = self.f.nearest_k(x, y, r, 1).first() else { break };
                    let (dx, dy) = (self.f.m.x[t as usize] - x, self.f.m.y[t as usize] - y);
                    self.arc(out, x, y, dx, dy, deg, r, base, push);
                    struck = true;
                }
                Shape::Ring { px } => {
                    let r = px * size / 100 * SUB;
                    let mut v = Vec::new();
                    self.f.in_circle(x, y, r, |i| v.push(i));
                    v.sort_unstable();
                    struck |= !v.is_empty();
                    for i in v {
                        self.hit(out, i, base, 0, 0, push, x, y);
                    }
                }
                Shape::Bolt { reach: rch, pierce, burst } => {
                    let r = rch * reach / 100 * SUB;
                    let deadeye = h.has_fx(FX_DEADEYE);
                    let (targets, pierce) = if burst > 0 {
                        (1 + self.m.targets_add as usize, 0)
                    } else {
                        let p = if pj.pierce > 0 { pj.pierce } else { pierce };
                        (1, if deadeye { u8::MAX } else { p.saturating_add(self.m.pierce_add) })
                    };
                    for t in self.f.nearest_k(x, y, r, targets) {
                        let (dx, dy) = (self.f.m.x[t as usize] - x, self.f.m.y[t as usize] - y);
                        self.bolt(out, x, y, dx, dy, r, pierce, burst * size / 100, pj.second_burst_pct, base, push);
                        struck = true;
                    }
                }
                Shape::Drop { reach: rch, px, delay } => {
                    let r = rch * reach / 100 * SUB;
                    let mut k = 1 + self.m.targets_add as usize;
                    if h.has_fx(FX_CRUSADE) {
                        k += CRUSADE_TARGETS as usize - 1;
                    }
                    for t in self.f.nearest_k(x, y, r, k) {
                        let (tx, ty) = (self.f.m.x[t as usize], self.f.m.y[t as usize]);
                        out.drops.push(Drop { x: tx, y: ty, px: px * size / 100, left: delay, dmg: base as u32, hero: self.id as u16, stun: 0 });
                        struck = true;
                    }
                }
            }
        }
        // HOLY LIGHT also heals the most hurt ally near her.
        let pc = h.class_row().passive;
        if pc.heal_pct > 0 && struck {
            self.heal_most_hurt(out, pc.heal_pct, pc.heal_px, pj);
        }
    }

    fn heal_most_hurt(&mut self, out: &mut Strikes, heal_pct: u32, px: i32, pj: Passive) {
        let (x, y) = (self.h.x, self.h.y);
        let r = px * SUB;
        let mut best: Option<(u64, u32)> = None;
        let heroes = &self.f.heroes;
        let me = self.id as u32;
        grid_box(&self.f.hgrid, PCELLS_W, PCELL_SHIFT, x - r, y - r, x + r, y + r, |q| {
            let qh = &heroes[q as usize];
            if q != me && qh.alive() && qh.health < qh.max_health && d2(qh.x, qh.y, x, y) <= r as i64 * r as i64 {
                let frac = qh.health as u64 * 10_000 / qh.max_health.max(1) as u64;
                if best.is_none_or(|(bf, bq)| frac < bf || (frac == bf && q < bq)) {
                    best = Some((frac, q));
                }
            }
        });
        if let Some((frac, q)) = best {
            let qh = &heroes[q as usize];
            let mul = if pj.heal_mul_pct > 0 { pj.heal_mul_pct } else { 100 };
            let amount = pct(pct(qh.max_health, heal_pct as i64), mul as i64).max(1);
            let shield = pj.shield_under_pct > 0 && frac < pj.shield_under_pct as u64 * 100;
            out.heals.push((q as u16, amount, self.id as u16, shield));
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn arc(&mut self, out: &mut Strikes, x: i32, y: i32, dx: i32, dy: i32, deg: i32, r: i32, dmg: u64, push: i32) {
        let cos_half = cos_q14(deg / 2);
        let dl = isqrt(dx as i64 * dx as i64 + dy as i64 * dy as i64).max(1);
        let mut v = Vec::new();
        let m = &self.f.m;
        self.f.in_circle(x, y, r, |i| {
            let (vx, vy) = ((m.x[i] - x) as i64, (m.y[i] - y) as i64);
            let vl = isqrt(vx * vx + vy * vy);
            if vl == 0 || (vx * dx as i64 + vy * dy as i64) * Q14 >= cos_half * vl * dl {
                v.push(i);
            }
        });
        v.sort_unstable();
        for i in v {
            self.hit(out, i, dmg, 0, 0, push, x, y);
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn bolt(&mut self, out: &mut Strikes, x: i32, y: i32, dx: i32, dy: i32, r: i32, pierce: u8, burst: i32, second: u32, dmg: u64, push: i32) {
        let dl = isqrt(dx as i64 * dx as i64 + dy as i64 * dy as i64).max(1);
        let (ex, ey) = (x + (dx as i64 * r as i64 / dl) as i32, y + (dy as i64 * r as i64 / dl) as i32);
        let (ex, ey, _) = self.f.terrain.line_end(x, y, ex, ey);
        let line = self.f.on_line(x, y, ex, ey, BOLT_HALF_WIDTH_PX * SUB);
        if burst > 0 {
            let (bx, by) = match line.first() {
                Some(&i) => (self.f.m.x[i as usize], self.f.m.y[i as usize]),
                None => (ex, ey),
            };
            let br = burst * SUB;
            let mut v = Vec::new();
            self.f.in_circle(bx, by, br, |i| v.push(i));
            v.sort_unstable();
            for &i in &v {
                self.hit(out, i, dmg, 0, 0, push, bx, by);
            }
            if second > 0 {
                for &i in &v {
                    self.hit(out, i, dmg * second as u64 / 100, 0, 0, 0, bx, by);
                }
            }
            return;
        }
        for &i in line.iter().take(pierce as usize + 1) {
            self.hit(out, i as usize, dmg, 0, 0, push, x, y);
        }
    }

    fn skill(&mut self, sk: u8, out: &mut Strikes) {
        let h = self.h;
        let rank = h.rank_pct(sk) as u64;
        let (x, y) = (h.x, h.y);
        let size = self.m.size_pct as i32;
        match SKILLS[sk as usize].act {
            Act::Ring { px, dmg, stun } => {
                let d = self.power(dmg) * rank / 100;
                let mut v = Vec::new();
                self.f.in_circle(x, y, px * size / 100 * SUB, |i| v.push(i));
                v.sort_unstable();
                for i in v {
                    self.hit(out, i, d, stun, 0, 0, x, y);
                }
            }
            Act::Thick { reach, px, dmg, delay, count, every } => {
                let d = (self.power(dmg) * rank / 100).min(u32::MAX as u64) as u32;
                let spots = self.f.thickest(x, y, reach * SUB, count as usize);
                for (k, (tx, ty)) in spots.into_iter().enumerate() {
                    let left = delay + every * k as u16;
                    out.drops.push(Drop { x: tx, y: ty, px: px * size / 100, left, dmg: d, hero: self.id as u16, stun: 0 });
                }
            }
            Act::Volley { n, deg } => {
                let w = h.class_row().weapon;
                let Shape::Bolt { reach, pierce, .. } = w.shape else { return };
                let pj = h.job_row().map(|j| j.passive).unwrap_or_default();
                let r = reach * self.m.reach_pct as i32 / 100 * SUB;
                let p = if h.has_fx(FX_DEADEYE) { u8::MAX } else { (if pj.pierce > 0 { pj.pierce } else { pierce }).saturating_add(self.m.pierce_add) };
                let (dx, dy) = match self.f.nearest_k(x, y, r, 1).first() {
                    Some(&t) => (self.f.m.x[t as usize] - x, self.f.m.y[t as usize] - y),
                    None => {
                        let (ux, uy) = crate::hero::DIRS[h.dir as usize];
                        (ux * SUB, uy * SUB)
                    }
                };
                let base = self.power(w.damage) * rank / 100;
                let n = n as i32;
                for k in 0..n {
                    let a = -deg / 2 + deg * k / (n - 1).max(1);
                    let (rx, ry) = rotate(dx, dy, a);
                    self.bolt(out, x, y, rx, ry, r, p, 0, 0, base, 0);
                }
            }
            Act::Dash { dmg, stun, .. } if dmg > 0 => {
                let Some((fx, fy)) = h.dash_from else { return };
                let d = self.power(dmg) * rank / 100;
                for i in self.f.on_line(fx, fy, x, y, DASH_HALF_WIDTH_PX * SUB) {
                    self.hit(out, i as usize, d, stun, 0, 0, fx, fy);
                }
            }
            Act::Zone { zone, reach } if reach > 0 => {
                if let Some(&(tx, ty)) = self.f.thickest(x, y, reach * SUB, 1).first() {
                    out.zones.push((self.id as u16, zone, tx, ty, rank as u32));
                }
            }
            Act::Curse { px, ticks } => {
                let t = (ticks as u64 * rank / 100).min(u8::MAX as u64) as u8;
                let mut v = Vec::new();
                self.f.in_circle(x, y, px * SUB, |i| v.push(i));
                v.sort_unstable();
                out.curses.extend(v.into_iter().map(|i| (i as u32, t)));
            }
            Act::SelfEffect { fx: FX_PROVOKE } => {
                let pull = h.job_row().map_or(0, |j| j.passive.provoke_pull_px);
                if pull > 0 {
                    let mut v = Vec::new();
                    self.f.in_circle(x, y, WARDEN_PROVOKE_PX * SUB, |i| v.push(i));
                    v.sort_unstable();
                    let m = &self.f.m;
                    for i in v {
                        let (mx, my) = (m.x[i], m.y[i]);
                        let dl = isqrt(d2(mx, my, x, y)).max(1);
                        let go = (pull * SUB) as i64;
                        let (tx, ty) = if dl <= go { (x, y) } else { (mx + ((x - mx) as i64 * go / dl) as i32, my + ((y - my) as i64 * go / dl) as i32) };
                        out.pulls.push((i as u32, tx, ty));
                    }
                }
            }
            _ => {}
        }
    }
}
