//! Bosses (rules section 8): a boss is a monster slot flagged `BOSS` plus a `Boss` record, and its attacks are
//! rows over eight shapes the core implements once. Each shape is drawn on the ground (`Cast`, public so the
//! client can draw it) for `warn` ticks before it lands.

use crate::events::Event;
use crate::hero::push_hero;
use crate::monster::{BOSS, level_scale};
use crate::tables::*;
use crate::tide::IDX_NONE;
use crate::util::{Q14, at_angle, d2, grid_box, isqrt, mix, rng_next};
use crate::geo::{atan_deg, deg, in_beam, near_segment};
use crate::{Field, PCELL_SHIFT, PCELLS_W, SUB};

/// Turn of a sweeping beam: 30 degrees a second, in sixteenths of a degree a tick.
pub const SWEEP_TURN16: i32 = 24;
/// A beam is this wide on each side of its line (px) and hurts each hero this often (ticks).
pub const SWEEP_HALF_W_PX: i32 = 20;
pub const SWEEP_EVERY: u32 = 5;
/// A lane ride: 420 px a second.
pub const LANE_SPEED_PX_S: i32 = 420;
/// A pull drags each hero this far inward at most (px).
pub const PULL_PX: i32 = 140;
/// The ring of fire closes to this radius (px), leaves a gap this wide on each side of its door (degrees),
/// and hurts each hero within it this often (ticks).
pub const WALL_END_PX: i32 = 60;
pub const WALL_GAP_DEG: i32 = 35;
pub const WALL_EVERY: u32 = 10;
/// Boss mire slows heroes this much (percent).
pub const MIRE_SLOW_PCT: i32 = -40;
/// A boss is called this far apart: called monsters stand 50 to 170 px from it.
pub const CALL_NEAR_PX: i32 = 50;
pub const CALL_SPAN_PX: u64 = 120;
/// A boss waits this long after rising before its first cast.
pub const BOSS_FIRST_CAST: u32 = secs(3);

/// A shape on the ground: drawn for `warn` ticks, then it lands (or acts for `dur` ticks).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Cast {
    /// Index into the boss row's attacks.
    pub atk: u8,
    pub age: u16,
    /// Where it is centred (the boss's own place for a slam, pull, call and sweep, which follow it).
    pub x: i32,
    pub y: i32,
    /// A sweep's first beam, a wall's door: sixteenths of a degree from east, clockwise.
    pub angle: i32,
    /// Candle and mire circles; a lane's end.
    pub pts: Vec<(i32, i32)>,
    /// Heroes a lane has already struck.
    pub hit: Vec<u16>,
    /// Lane rides left.
    pub rides: u16,
}

/// A patch of mire a boss left: slows heroes in it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Mire {
    pub x: i32,
    pub y: i32,
    pub px: i32,
    pub left: u16,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Boss {
    /// Row in `BOSSES`.
    pub which: u8,
    /// Its monster slot (its position and health are the monster's).
    pub slot: u32,
    pub max_hp: u32,
    pub phase: u8,
    /// The clock tick it leaves (a vault's boss never does).
    pub leaves: u64,
    /// Percent of its attack damage (a lost tide, seals).
    pub dmg_pct: u32,
    /// The clock tick of its next cast.
    pub next_at: u64,
    pub cycle: u32,
    pub casts: Vec<Cast>,
    pub mires: Vec<Mire>,
    pub world: bool,
    /// The tide index (field boss) or ride (world boss) it came for.
    pub window: u32,
}

impl Field {
    /// A free monster slot; when the pool is full, the first living non-boss monster after a random start gives
    /// its slot up.
    fn take_slot(&mut self) -> usize {
        if let Some(s) = self.free.pop() {
            return s as usize;
        }
        let n = self.m.hp.len();
        let start = (rng_next(&mut self.rng) % n as u64) as usize;
        for k in 0..n {
            let i = (start + k) % n;
            if self.m.hp[i] > 0 && self.m.flags[i] & BOSS == 0 {
                self.m.hp[i] = 0;
                self.alive -= 1;
                return i;
            }
        }
        0
    }

    /// Tools and tests: a boss of row `which` at a point with `hp` health, at the field's top level, resting
    /// until the clock says its first cast (set `hold_boss` to stop it casting by itself).
    pub fn summon_boss(&mut self, which: u8, hp: u32, x: i32, y: i32) {
        let level = self.top_level();
        let leaves = self.realm.clock + BOSS_STAY as u64;
        self.spawn_boss(which, hp, level, x, y, 100, leaves, false, IDX_NONE);
    }

    /// Tools and tests: the boss casts nothing by itself from now on.
    pub fn hold_boss(&mut self) {
        if let Some(b) = self.realm.boss.as_mut() {
            b.next_at = u64::MAX;
        }
    }

    /// Tools and tests: the boss starts attack `idx` of its row now (centred where it stands).
    pub fn cast_boss(&mut self, idx: u8) {
        let Some(slot) = self.realm.boss.as_ref().map(|b| b.slot as usize) else {
            return;
        };
        let (x, y) = (self.m.x[slot], self.m.y[slot]);
        if let Some(b) = self.realm.boss.as_mut() {
            let a = &BOSSES[b.which as usize].attacks[idx as usize];
            b.casts.push(new_cast(idx, a, x, y));
        }
    }

    /// A boss of row `which` rises at a point with `hp` health.
    pub(crate) fn spawn_boss(&mut self, which: u8, hp: u32, level: u8, x: i32, y: i32, dmg_pct: u32, leaves: u64, world: bool, window: u32) {
        let slot = self.take_slot();
        self.m.boss_max = hp;
        self.birth(slot, BOSSES[which as usize].carrier, level, BOSS, x, y);
        self.spawned.push(slot as u32);
        for h in self.heroes.iter_mut() {
            h.boss_contrib = 0;
        }
        self.realm.boss = Some(Boss {
            which,
            slot: slot as u32,
            max_hp: hp,
            phase: 0,
            leaves,
            dmg_pct,
            next_at: self.realm.clock + BOSS_FIRST_CAST as u64,
            cycle: 0,
            casts: Vec::new(),
            mires: Vec::new(),
            world,
            window,
        });
        self.events.push(Event::Boss { which, state: BOSS_RISES, health: hp });
    }

    /// A field boss or the world boss rises at the heart (rules 8): health from the heroes in the heart.
    pub(crate) fn rise_boss(&mut self, which: u8, leaves: u64, world: bool, window: u32) {
        let level = self.top_level();
        let heroes = self.heart_heroes();
        let base = BOSS_HEALTH_BASE as u64 + BOSS_HEALTH_PER_HERO as u64 * heroes as u64;
        let mut hp = level_scale(base.min(u32::MAX as u64 / 20) as u32, level, HEALTH_PCT_PER_LEVEL) as u64;
        hp = hp * BOSSES[which as usize].health_pct as u64 / 100;
        let mut dmg = 100;
        if world {
            hp *= WORLD_HEALTH_MUL as u64;
        } else if self.realm.result_index == window {
            if self.realm.result == TIDE_WON {
                hp = hp * BOSS_WON_HEALTH_PCT as u64 / 100;
            } else if self.realm.result == TIDE_LOST {
                dmg = BOSS_LOST_DAMAGE_PCT;
            }
        }
        let (x, y) = self.terrain.nearest_open(self.terrain.heart.0, self.terrain.heart.1);
        self.spawn_boss(which, hp.clamp(1, u32::MAX as u64) as u32, level, x, y, dmg, leaves, world, window);
    }

    /// The boss's time is up: it goes (no chest).
    pub(crate) fn boss_leaves(&mut self) {
        let Some(b) = self.realm.boss.take() else {
            return;
        };
        let i = b.slot as usize;
        if self.m.hp[i] > 0 {
            self.m.hp[i] = 0;
            self.free.push(i as u32);
            self.alive -= 1;
        }
        self.events.push(Event::Boss { which: b.which, state: BOSS_LEFT, health: 0 });
        for h in self.heroes.iter_mut() {
            h.boss_contrib = 0;
        }
    }

    /// The boss's monster died (called from the kill settlement, which frees its slot).
    pub(crate) fn boss_dead(&mut self) {
        let Some(b) = self.realm.boss.take() else {
            return;
        };
        let row = &BOSSES[b.which as usize];
        self.events.push(Event::Boss { which: b.which, state: BOSS_KILLED, health: 0 });
        let floor = (b.max_hp as u64 * BOSS_FLOOR_MILLE as u64 / 1000) as u32;
        let list: Vec<(u16, u32)> =
            self.heroes.iter().enumerate().filter(|(_, h)| h.present && h.boss_contrib >= floor).map(|(i, h)| (i as u16, h.boss_contrib)).collect();
        let level = self.top_level();
        match row.tier {
            TIER_WORLD => {
                self.pay(R_WORLD_RELIC, self.field, level, 0, list.clone(), coin_for(COIN_WORLD_RELIC, level), WORLD_RELIC_HEROES);
                self.pay(R_WORLD_EPIC, self.field, level, 0, list, coin_for(COIN_WORLD_EPIC, level), usize::MAX);
            }
            TIER_ACT => {}
            TIER_ARCHLICH | TIER_TRIAL => self.vault_won(list),
            _ => self.pay(R_BOSS_CHEST, self.field, level, 0, list, coin_for(COIN_BOSS_CHEST, level), usize::MAX),
        }
        if row.tier != TIER_ACT && row.tier != TIER_ARCHLICH && row.tier != TIER_TRIAL {
            for h in self.heroes.iter_mut() {
                h.boss_contrib = 0;
            }
        }
    }

    /// Up heroes within `px` of a point, by id.
    fn heroes_near(&self, x: i32, y: i32, px: i32) -> Vec<u16> {
        let r = px * SUB;
        let mut v = Vec::new();
        grid_box(&self.hgrid, PCELLS_W, PCELL_SHIFT, x - r, y - r, x + r, y + r, |q| {
            let h = &self.heroes[q as usize];
            if h.alive() && d2(h.x, h.y, x, y) <= r as i64 * r as i64 {
                v.push(q as u16);
            }
        });
        v.sort_unstable();
        v
    }

    /// One hit of a boss on a hero: a share of her health, then her own reductions; a drainer heals.
    fn boss_hit(&mut self, b: &Boss, q: usize, mille: u16, killed: &mut Vec<(u32, u16)>) {
        let raw = (self.heroes[q].max_health as u64 * mille as u64 / 1000 * b.dmg_pct as u64 / 100).min(u32::MAX as u64) as u32;
        let taken = self.hurt_hero(q, raw.max(1), killed);
        let drain = BOSSES[b.which as usize].drain_pct;
        if drain > 0 && taken > 0 && self.m.hp[b.slot as usize] > 0 {
            let i = b.slot as usize;
            self.m.hp[i] = (self.m.hp[i] + (taken as u64 * drain as u64 / 100) as u32).min(b.max_hp);
        }
    }

    fn pick_heroes(&mut self, from: Vec<u16>, n: usize) -> Vec<u16> {
        let mut v = from;
        let take = n.min(v.len());
        for k in 0..take {
            let j = k + (rng_next(&mut self.rng) % (v.len() - k) as u64) as usize;
            v.swap(k, j);
        }
        v.truncate(take);
        v
    }

    /// The boss's tick: phase, mire, walking, the casts it has out, and a new one when it is rested.
    pub(crate) fn boss_act(&mut self, killed: &mut Vec<(u32, u16)>) {
        let Some(mut b) = self.realm.boss.take() else {
            return;
        };
        let slot = b.slot as usize;
        if self.m.hp[slot] == 0 {
            self.realm.boss = Some(b);
            return;
        }
        let row = &BOSSES[b.which as usize];
        let clock = self.realm.clock;
        // Phases by health.
        let pct = (self.m.hp[slot] as u64 * 100 / b.max_hp.max(1) as u64) as u32;
        let phase = BOSS_PHASES.iter().filter(|&&t| pct <= t).count() as u8;
        if phase > b.phase {
            b.phase = phase;
            self.events.push(Event::Boss { which: b.which, state: BOSS_PHASE, health: self.m.hp[slot] });
        }
        for m in b.mires.iter_mut() {
            m.left = m.left.saturating_sub(1);
        }
        b.mires.retain(|m| m.left > 0);
        // Walking toward the nearest hero, but not while riding a lane.
        let riding = b.casts.iter().any(|c| row.attacks[c.atk as usize].shape == A_LANES && c.age >= row.attacks[c.atk as usize].warn);
        if row.speed > 0 && !riding {
            let (x, y) = (self.m.x[slot], self.m.y[slot]);
            let mut best: Option<(i64, u16)> = None;
            for &q in &self.live {
                let h = &self.heroes[q as usize];
                let dd = d2(h.x, h.y, x, y);
                if best.is_none_or(|(bd, _)| dd < bd) {
                    best = Some((dd, q));
                }
            }
            if let Some((dd, q)) = best {
                let len = isqrt(dd);
                let stop = BOSS_STOP_PX as i64 * SUB as i64;
                if len > stop {
                    let h = &self.heroes[q as usize];
                    let step = (row.speed as i64 * SUB as i64 / TICK_HZ as i64).min(len - stop);
                    let (nx, ny) = (x + ((h.x - x) as i64 * step / len) as i32, y + ((h.y - y) as i64 * step / len) as i32);
                    let (nx, ny) = self.terrain.slide(x, y, nx, ny);
                    self.m.x[slot] = nx;
                    self.m.y[slot] = ny;
                }
            }
        }
        // The casts it has out.
        let mut casts = std::mem::take(&mut b.casts);
        let had = !casts.is_empty();
        let mut chained = Vec::new();
        let mut k = 0;
        while k < casts.len() {
            let mut c = std::mem::replace(&mut casts[k], Cast { atk: 0, age: 0, x: 0, y: 0, angle: 0, pts: Vec::new(), hit: Vec::new(), rides: 0 });
            let done = self.cast_step(&mut b, &mut c, killed);
            if done {
                let next = row.attacks[c.atk as usize].then;
                if next != NO_NEXT {
                    chained.push(new_cast(next, &row.attacks[next as usize], self.m.x[slot], self.m.y[slot]));
                }
                casts.remove(k);
            } else {
                c.age = c.age.wrapping_add(1);
                casts[k] = c;
                k += 1;
            }
        }
        casts.extend(chained);
        if had && casts.is_empty() && b.next_at != u64::MAX {
            // The rest starts when the last cast is over; each phase shortens it.
            let haste = 100u64.saturating_sub(PHASE_HASTE_PCT as u64 * b.phase as u64).max(20);
            b.next_at = clock + row.rest as u64 * haste / 100;
        }
        // A new cast (or two) when the last is done and the boss has rested.
        if casts.is_empty() && clock >= b.next_at {
            let elig: Vec<u8> = (0..row.attacks.len() as u8).filter(|&i| row.attacks[i as usize].phase <= b.phase).collect();
            let want = if b.phase >= row.twice_from { 2 } else { 1 };
            let (bx, by) = (self.m.x[slot], self.m.y[slot]);
            for _ in 0..want {
                if elig.is_empty() {
                    break;
                }
                let mut idx = elig[(b.cycle as usize) % elig.len()];
                b.cycle = b.cycle.wrapping_add(1);
                // Two lane rides at once would pull the boss two ways: the second casts the next in turn.
                if row.attacks[idx as usize].shape == A_LANES && casts.iter().any(|c| row.attacks[c.atk as usize].shape == A_LANES) {
                    idx = elig[(b.cycle as usize) % elig.len()];
                    b.cycle = b.cycle.wrapping_add(1);
                }
                casts.push(new_cast(idx, &row.attacks[idx as usize], bx, by));
            }
        }
        b.casts = casts;
        self.realm.boss = Some(b);
    }

    /// Advances one cast by a tick; true when it is over.
    fn cast_step(&mut self, b: &mut Boss, c: &mut Cast, killed: &mut Vec<(u32, u16)>) -> bool {
        let row = &BOSSES[b.which as usize];
        let a = row.attacks[c.atk as usize];
        let slot = b.slot as usize;
        let (bx, by) = (self.m.x[slot], self.m.y[slot]);
        let tick = self.tick;
        match a.shape {
            A_SLAM => {
                c.x = bx;
                c.y = by;
                if c.age >= a.warn {
                    for q in self.heroes_near(bx, by, a.px) {
                        self.boss_hit(b, q as usize, a.dmg, killed);
                    }
                    return true;
                }
            }
            A_PULL => {
                c.x = bx;
                c.y = by;
                if c.age >= a.warn {
                    for q in self.heroes_near(bx, by, a.px) {
                        let h = &self.heroes[q as usize];
                        let len = isqrt(d2(h.x, h.y, bx, by));
                        let stop = BOSS_STOP_PX as i64 * SUB as i64;
                        if len > stop {
                            let step = (PULL_PX as i64 * SUB as i64).min(len - stop);
                            let (dx, dy) = (((bx - h.x) as i64 * step / len) as i32, ((by - h.y) as i64 * step / len) as i32);
                            push_hero(self, q as usize, dx, dy);
                        }
                    }
                    return true;
                }
            }
            A_CANDLES | A_MIRE => {
                if c.age == 0 {
                    let near = self.heroes_near(bx, by, a.reach);
                    let picked = self.pick_heroes(near, a.count as usize);
                    c.pts = picked.iter().map(|&q| (self.heroes[q as usize].x, self.heroes[q as usize].y)).collect();
                }
                if c.age >= a.warn {
                    if a.shape == A_CANDLES {
                        let mut hit: Vec<u16> = Vec::new();
                        for &(x, y) in &c.pts {
                            hit.extend(self.heroes_near(x, y, a.px));
                        }
                        hit.sort_unstable();
                        hit.dedup();
                        for q in hit {
                            self.boss_hit(b, q as usize, a.dmg, killed);
                        }
                    } else {
                        for &(x, y) in &c.pts {
                            b.mires.push(Mire { x, y, px: a.px, left: a.dur });
                        }
                    }
                    return true;
                }
            }
            A_SWEEP => {
                c.x = bx;
                c.y = by;
                if c.age == 0 {
                    let near = self.heroes_near(bx, by, 400);
                    let pick = self.pick_heroes(near, 1);
                    c.angle = match pick.first() {
                        Some(&q) => {
                            let h = &self.heroes[q as usize];
                            let (dx, dy) = ((h.x - bx) as i64, (h.y - by) as i64);
                            atan_deg(dx, dy) * 16
                        }
                        None => (rng_next(&mut self.rng) % 360) as i32 * 16,
                    };
                }
                if c.age >= a.warn {
                    let t = (c.age - a.warn) as i32;
                    if t < a.dur as i32 {
                        let beams = a.count.max(1) as i32;
                        let near = self.heroes_near(bx, by, a.px);
                        for q in near {
                            if (tick + q as u32) % SWEEP_EVERY != 0 {
                                continue;
                            }
                            let h = &self.heroes[q as usize];
                            let (hx, hy) = (h.x, h.y);
                            let struck = (0..beams).any(|k| {
                                let dir = if k % 2 == 0 { 1 } else { -1 };
                                let ang = c.angle + k * 360 * 16 / beams + dir * SWEEP_TURN16 * t;
                                in_beam(bx, by, ang, a.px, SWEEP_HALF_W_PX, hx, hy)
                            });
                            if struck {
                                self.boss_hit(b, q as usize, a.dmg, killed);
                            }
                        }
                    }
                    if t + 1 >= a.dur as i32 {
                        return true;
                    }
                }
            }
            A_LANES => {
                if c.age == 0 {
                    if c.rides == 0 {
                        c.rides = a.count.max(1);
                    }
                    let near = self.heroes_near(bx, by, a.reach);
                    let pick = self.pick_heroes(near, 1);
                    let (tx, ty) = match pick.first() {
                        Some(&q) => (self.heroes[q as usize].x, self.heroes[q as usize].y),
                        None => (bx + SUB, by),
                    };
                    let (dx, dy) = ((tx - bx) as i64, (ty - by) as i64);
                    let len = isqrt(dx * dx + dy * dy).max(1);
                    let reach = a.reach as i64 * SUB as i64;
                    let (ex, ey) = (bx + (dx * reach / len) as i32, by + (dy * reach / len) as i32);
                    let (ex, ey, _) = self.terrain.line_end(bx, by, ex, ey);
                    c.x = bx;
                    c.y = by;
                    c.pts = vec![(ex, ey)];
                    c.hit.clear();
                }
                if c.age >= a.warn {
                    let (ex, ey) = c.pts[0];
                    let (len, step) = (isqrt(d2(bx, by, ex, ey)), LANE_SPEED_PX_S as i64 * SUB as i64 / TICK_HZ as i64);
                    let go = step.min(len);
                    let (nx, ny) = if len == 0 { (bx, by) } else { (bx + ((ex - bx) as i64 * go / len) as i32, by + ((ey - by) as i64 * go / len) as i32) };
                    self.m.x[slot] = nx;
                    self.m.y[slot] = ny;
                    let r = a.px * SUB;
                    let reach = (a.px + 40) * SUB;
                    let mut v = Vec::new();
                    grid_box(&self.hgrid, PCELLS_W, PCELL_SHIFT, nx.min(bx) - reach, ny.min(by) - reach, nx.max(bx) + reach, ny.max(by) + reach, |q| {
                        let h = &self.heroes[q as usize];
                        if h.alive() && near_segment(bx, by, nx, ny, h.x, h.y, r) {
                            v.push(q as u16);
                        }
                    });
                    v.sort_unstable();
                    for q in v {
                        if !c.hit.contains(&q) {
                            c.hit.push(q);
                            self.boss_hit(b, q as usize, a.dmg, killed);
                        }
                    }
                    if go >= len {
                        c.rides -= 1;
                        if c.rides == 0 {
                            return true;
                        }
                        c.age = u16::MAX; // wraps to 0: the next ride is drawn afresh
                    }
                }
            }
            A_CALL => {
                c.x = bx;
                c.y = by;
                if c.age >= a.warn {
                    let level = self.m.level[slot];
                    self.call_monsters(bx, by, level, a.kind, a.count);
                    if a.kind2 != NO_NEXT {
                        self.call_monsters(bx, by, level, a.kind2, a.count2);
                    }
                    return true;
                }
            }
            A_WALL => {
                if c.age == 0 {
                    c.x = bx;
                    c.y = by;
                    c.angle = (rng_next(&mut self.rng) % 360) as i32 * 16;
                }
                if c.age >= a.warn {
                    let t = (c.age - a.warn) as i32;
                    if t < a.dur as i32 {
                        let r = a.px - (a.px - WALL_END_PX) * t / a.dur as i32;
                        let band = a.reach;
                        let (gx, gy) = at_angle(deg(c.angle), 1024);
                        let cos_gap = crate::util::cos_q14(WALL_GAP_DEG);
                        let near = self.heroes_near(c.x, c.y, r + band);
                        for q in near {
                            if (tick + q as u32) % WALL_EVERY != 0 {
                                continue;
                            }
                            let h = &self.heroes[q as usize];
                            let d = isqrt(d2(h.x, h.y, c.x, c.y)) / SUB as i64;
                            if (d - r as i64).abs() > band as i64 / 2 {
                                continue;
                            }
                            // In the door when within `WALL_GAP_DEG` of its direction.
                            let (vx, vy) = ((h.x - c.x) as i64, (h.y - c.y) as i64);
                            let dot = vx * gx as i64 + vy * gy as i64;
                            let vl = isqrt(vx * vx + vy * vy).max(1);
                            if dot * Q14 >= cos_gap * vl * 1024 {
                                continue;
                            }
                            self.boss_hit(b, q as usize, a.dmg, killed);
                        }
                    }
                    if t + 1 >= a.dur as i32 {
                        return true;
                    }
                }
            }
            _ => return true,
        }
        false
    }

    /// Calls `n` monsters of `kind` (or the field's kinds by weight) around a point.
    fn call_monsters(&mut self, x: i32, y: i32, level: u8, kind: u8, n: u16) {
        let row = &FIELDS[self.field as usize];
        let (first, count) = match &self.realm.vault {
            Some(v) => (VAULTS[v.vault as usize].first_kind as usize, VAULTS[v.vault as usize].kind_count as usize),
            None => (row.first_kind as usize, row.kind_count as usize),
        };
        let total: u32 = KINDS[first..first + count].iter().map(|k| k.weight).sum();
        for _ in 0..n {
            let Some(&slot) = self.free.last() else { break };
            let mut at = None;
            for _ in 0..6 {
                let r = rng_next(&mut self.rng);
                let d = CALL_NEAR_PX as i64 + (r >> 20) as i64 % CALL_SPAN_PX as i64;
                let (ox, oy) = at_angle((r % 360) as i32, d as i32 * SUB);
                let (px, py) = (x + ox, y + oy);
                if !self.terrain.wall(px, py) && px > 0 && py > 0 && px < crate::FIELD && py < crate::FIELD {
                    at = Some((px, py));
                    break;
                }
            }
            let Some((px, py)) = at else { continue };
            let k = if kind == CALL_FIELD_KINDS {
                let mut pick = (mix(self.seed, self.tick as u64, slot as u64, 0xCA11) % total as u64) as u32;
                let mut k = first;
                for j in first..first + count {
                    if pick < KINDS[j].weight {
                        k = j;
                        break;
                    }
                    pick -= KINDS[j].weight;
                }
                k as u8
            } else {
                kind
            };
            self.free.pop();
            self.birth(slot as usize, k, level, 0, px, py);
            self.spawned.push(slot);
        }
    }
}

fn new_cast(idx: u8, a: &Atk, x: i32, y: i32) -> Cast {
    Cast { atk: idx, age: 0, x, y, angle: 0, pts: Vec::new(), hit: Vec::new(), rides: a.count }
}

fn coin_for(base: u32, level: u8) -> u32 {
    crate::tide::coin_at(base, level)
}
