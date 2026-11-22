//! Tides and altars (rules section 8) on the realm's clock, and the clock's schedule of tides, field bosses and
//! the world boss. The schedule is a set of pure functions of the clock, so the server, the client and the
//! town all read the same countdowns; a field only ever asks "what does the clock say now".

use crate::boss::Boss;
use crate::events::Event;
use crate::monster::{BOSS, level_scale};
use crate::tables::*;
use crate::terrain::ring_of;
use crate::util::{d2, grid_box, mix};
use crate::vault::{RUN_GOING, VaultRun};
use crate::{CELL_SHIFT, CELLS_W, Field, GRID_MARGIN, PCELL_SHIFT, PCELLS_W, SUB};

/// "No tide yet".
pub const IDX_NONE: u32 = u32::MAX;

// ---- the schedule (pure)

/// The clock tick the `n`-th tide of a field begins.
pub fn tide_start(field: u8, n: u32) -> u64 {
    n as u64 * TIDE_EVERY as u64 + TIDE_FIRST as u64 + TIDE_STAGGER as u64 * field as u64
}

/// The tide whose window holds `clock`: its index, or None between tides.
pub fn tide_running(clock: u64, field: u8) -> Option<u32> {
    let n = tide_last(clock, field)?;
    (clock < tide_start(field, n) + TIDE_LEN as u64).then_some(n)
}

/// The latest tide that has begun by `clock` (running or over).
pub fn tide_last(clock: u64, field: u8) -> Option<u32> {
    let first = tide_start(field, 0);
    (clock >= first).then(|| ((clock - first) / TIDE_EVERY as u64) as u32)
}

/// Ticks until a field's next tide begins (0 while one runs) and ticks left of the running one.
pub fn tide_countdown(clock: u64, field: u8) -> (u64, u64) {
    if let Some(n) = tide_running(clock, field) {
        return (0, tide_start(field, n) + TIDE_LEN as u64 - clock);
    }
    let next = tide_last(clock, field).map_or(0, |n| n + 1);
    (tide_start(field, next) - clock, 0)
}

/// Whether the tide of index `n` is followed by a field boss (every fourth).
pub fn boss_due(n: u32) -> bool {
    (n + 1) % BOSS_EVERY_TIDES == 0
}

/// The clock ticks the boss after tide `n` rises and leaves.
pub fn field_boss_window(field: u8, n: u32) -> (u64, u64) {
    let rise = tide_start(field, n) + TIDE_LEN as u64 + BOSS_RISE_AFTER as u64;
    (rise, rise + BOSS_STAY as u64)
}

/// The next (or running) field boss at or after `clock`: tide index, rise tick.
pub fn next_field_boss(clock: u64, field: u8) -> (u32, u64) {
    let mut n = tide_last(clock, field).unwrap_or(0);
    loop {
        if boss_due(n) {
            let (rise, leave) = field_boss_window(field, n);
            if clock < leave {
                return (n, rise);
            }
        }
        n += 1;
    }
}

/// The `k`-th world boss ride: its field (in turn), arrival and departure on the clock.
pub fn world_ride(k: u32) -> (u8, u64, u64) {
    let field = (k % FIELDS.len() as u32) as u8;
    let start = k as u64 * WORLD_EVERY as u64 + TIDE_FIRST as u64 + TIDE_STAGGER as u64 * field as u64 + WORLD_AFTER_TIDE as u64;
    (field, start, start + WORLD_STAY as u64)
}

/// The world boss ride running or next at `clock`: (k, field, arrival). It is announced `WORLD_ANNOUNCE` before.
pub fn next_world_boss(clock: u64) -> (u32, u8, u64) {
    let mut k = (clock / WORLD_EVERY as u64) as u32;
    loop {
        let (field, start, end) = world_ride(k);
        if clock < end {
            return (k, field, start);
        }
        k += 1;
    }
}

// ---- state

/// One of a field's six war altars during a tide.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Altar {
    /// `ALTAR_LIT`, `ALTAR_HELD`, `ALTAR_RUINED`, or `ALTAR_OUT` (dark).
    pub state: u8,
    /// Hero-ticks held so far.
    pub progress: u32,
    pub hp: u32,
}

/// The realm's part of a field's state: the clock, the tide, the boss, the vault run.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Realm {
    pub clock: u64,
    pub tide_index: u32,
    pub tide_seen: u32,
    pub factor: u32,
    pub altars: [Altar; 6],
    pub quick_until: u64,
    /// The last tide's result: 0 none, `TIDE_WON`, `TIDE_LOST`, and its index.
    pub result: u8,
    pub result_index: u32,
    pub boss_seen: u32,
    pub world_seen: u32,
    pub boss: Option<Boss>,
    pub vault: Option<VaultRun>,
}

impl Realm {
    pub fn new() -> Realm {
        Realm {
            clock: 0,
            tide_index: IDX_NONE,
            tide_seen: IDX_NONE,
            factor: 1,
            altars: [Altar { state: ALTAR_OUT, progress: 0, hp: 0 }; 6],
            quick_until: 0,
            result: 0,
            result_index: IDX_NONE,
            boss_seen: IDX_NONE,
            world_seen: IDX_NONE,
            boss: None,
            vault: None,
        }
    }
}

impl Default for Realm {
    fn default() -> Self {
        Realm::new()
    }
}

/// Coin at a level of power: `base x (100 + 12 x (level - 1))%`.
pub fn coin_at(base: u32, level: u8) -> u32 {
    level_scale(base, level, POWER_PCT_PER_LEVEL)
}

impl Field {
    /// The realm's clock in ticks.
    pub fn clock(&self) -> u64 {
        self.realm.clock
    }
    /// Sets the realm's clock (the server does this when it opens a copy, so every copy shares one).
    pub fn set_clock(&mut self, ticks: u64) {
        self.realm.clock = ticks;
    }
    pub fn realm(&self) -> &Realm {
        &self.realm
    }
    /// The running boss, if any.
    pub fn boss(&self) -> Option<&Boss> {
        self.realm.boss.as_ref()
    }
    /// Where the running boss stands (sub units).
    pub fn boss_pos(&self) -> Option<(i32, i32)> {
        self.realm.boss.as_ref().map(|b| (self.m.x[b.slot as usize], self.m.y[b.slot as usize]))
    }
    /// The boss's health now and at most.
    pub fn boss_health(&self) -> Option<(u32, u32)> {
        self.realm.boss.as_ref().map(|b| (self.m.hp[b.slot as usize], b.max_hp))
    }
    pub fn altars(&self) -> &[Altar; 6] {
        &self.realm.altars
    }
    /// The monsters are quick: a tide runs, or a lost one's two minutes have not passed.
    pub fn quick(&self) -> bool {
        self.tide || self.realm.clock < self.realm.quick_until
    }
    /// The level a hero's ceiling and the field's scales count from: the field's top, or a vault's level.
    pub fn top_level(&self) -> u8 {
        match &self.realm.vault {
            Some(v) => VAULTS[v.vault as usize].level,
            None => FIELDS[self.field as usize].top,
        }
    }
    /// Who was paid in the last tick's REWARD events: `rewarded(first, count)` of the event.
    pub fn rewarded(&self, first: u32, count: u16) -> &[(u16, u32)] {
        &self.reward_list[first as usize..first as usize + count as usize]
    }

    /// Start of every tick after the clock moved: tides, field bosses, the world boss, or a vault's timeline.
    pub(crate) fn realm_begin(&mut self) {
        self.realm.clock += 1;
        if self.realm.vault.is_some() {
            self.vault_begin();
            return;
        }
        let (clock, f) = (self.realm.clock, self.field);
        if self.tide && clock >= tide_start(f, self.realm.tide_index) + TIDE_LEN as u64 {
            self.end_tide(false);
        }
        if !self.tide {
            if let Some(n) = tide_running(clock, f) {
                if self.realm.tide_seen != n {
                    self.begin_tide(n);
                }
            }
        }
        if let Some(b) = &self.realm.boss {
            if clock >= b.leaves {
                self.boss_leaves();
            }
        }
        if self.realm.boss.is_none() {
            // The world boss first: it is rarer.
            let k = (clock / WORLD_EVERY as u64) as u32;
            let (wf, start, end) = world_ride(k);
            if wf == f && clock >= start && clock < end && self.realm.world_seen != k {
                self.realm.world_seen = k;
                self.rise_boss(B_DEATH, end, true, k);
            } else if let Some(n) = tide_last(clock, f) {
                if boss_due(n) && self.realm.boss_seen != n {
                    let (rise, leave) = field_boss_window(f, n);
                    if clock >= rise && clock < leave {
                        self.realm.boss_seen = n;
                        self.rise_boss(field_boss_of(f, n / BOSS_EVERY_TIDES), leave, false, n);
                    }
                }
            }
        }
    }

    fn present_count(&self) -> u32 {
        self.heroes.iter().filter(|h| h.present).count() as u32
    }

    /// The heroes factor of the rules: `max(1, heroes in the field / 20)`.
    fn heroes_factor(&self) -> u32 {
        (self.present_count() / ALTAR_FACTOR_HEROES).max(1)
    }

    fn begin_tide(&mut self, n: u32) {
        self.tide = true;
        self.realm.tide_index = n;
        self.realm.tide_seen = n;
        let factor = self.heroes_factor();
        self.realm.factor = factor;
        for h in self.heroes.iter_mut() {
            h.tide_contrib = 0;
        }
        let hp = level_scale(ALTAR_HEALTH.saturating_mul(factor), self.top_level(), HEALTH_PCT_PER_LEVEL);
        let mut order = [0usize, 1, 2, 3, 4, 5];
        for k in 0..ALTARS_LIT {
            let j = k + (mix(self.seed, n as u64, 0xA17A, k as u64) % (6 - k) as u64) as usize;
            order.swap(k, j);
        }
        self.realm.altars = [Altar { state: ALTAR_OUT, progress: 0, hp: 0 }; 6];
        self.events.push(Event::Tide { state: TIDE_BEGIN, index: n });
        let mut lit = order[..ALTARS_LIT].to_vec();
        lit.sort_unstable();
        for a in lit {
            self.realm.altars[a] = Altar { state: ALTAR_LIT, progress: 0, hp };
            self.events.push(Event::Altar { index: a as u8, state: ALTAR_LIT });
        }
    }

    /// The tide is over: WON (two altars held) or LOST (time ran out).
    fn end_tide(&mut self, won: bool) {
        self.tide = false;
        let n = self.realm.tide_index;
        self.realm.result = if won { TIDE_WON } else { TIDE_LOST };
        self.realm.result_index = n;
        self.events.push(Event::Tide { state: if won { TIDE_WON } else { TIDE_LOST }, index: n });
        for a in 0..6 {
            if self.realm.altars[a].state != ALTAR_OUT {
                self.realm.altars[a].state = ALTAR_OUT;
                self.events.push(Event::Altar { index: a as u8, state: ALTAR_OUT });
            }
        }
        if won {
            let floor = TIDE_FLOOR.saturating_mul(self.realm.factor);
            let list: Vec<(u16, u32)> =
                self.heroes.iter().enumerate().filter(|(_, h)| h.present && h.tide_contrib >= floor).map(|(i, h)| (i as u16, h.tide_contrib)).collect();
            let coin = coin_at(COIN_TIDE_CACHE, self.top_level());
            self.pay(R_TIDE_CACHE, self.field, self.top_level(), 0, list, coin, usize::MAX);
        } else {
            self.realm.quick_until = self.realm.clock + TIDE_LOST_QUICK as u64;
        }
        for h in self.heroes.iter_mut() {
            h.tide_contrib = 0;
        }
    }

    /// Pays a chest: the heroes (best contribution first, ties by id; at most `take`), their coin, one REWARD event.
    pub(crate) fn pay(&mut self, kind: u8, source: u8, level: u8, seals: u8, mut list: Vec<(u16, u32)>, coin: u32, take: usize) {
        list.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
        list.truncate(take);
        let first = self.reward_list.len() as u32;
        for &(q, _) in &list {
            let h = &mut self.heroes[q as usize];
            h.coin = h.coin.saturating_add(coin);
        }
        let count = list.len() as u16;
        self.reward_list.extend(list);
        self.events.push(Event::Reward { kind, source, level, seals, first, count });
    }

    /// Adds contribution to the running tide and boss (never while she stands still).
    pub(crate) fn credit(&mut self, i: usize, amount: u32) {
        if amount == 0 {
            return;
        }
        let tide = self.tide;
        let boss = self.realm.boss.is_some() || self.realm.vault.as_ref().is_some_and(|v| v.state == RUN_GOING);
        if !tide && !boss {
            return;
        }
        let Some(h) = self.heroes.get_mut(i) else {
            return;
        };
        if !h.present || h.idle >= STILL_TICKS {
            return;
        }
        if tide {
            h.tide_contrib = h.tide_contrib.saturating_add(amount);
        }
        if boss {
            h.boss_contrib = h.boss_contrib.saturating_add(amount);
        }
    }

    /// The fight phase's realm part, before the kills are settled: contribution from this tick's damage, the
    /// altars, and the boss's attacks.
    pub(crate) fn realm_fight(&mut self, killed: &mut Vec<(u32, u16)>) {
        if self.tide || self.realm.boss.is_some() || self.realm.vault.is_some() {
            for i in 0..self.dealt.len().min(self.heroes.len()) {
                let d = self.dealt[i];
                self.credit(i, d);
            }
        }
        if self.tide {
            self.altars_tick();
        }
        if self.realm.boss.is_some() {
            self.boss_act(killed);
        }
    }

    fn altars_tick(&mut self) {
        let need = ALTAR_HOLD_SECS * TICK_HZ * self.realm.factor;
        let tick = self.tick;
        let r = ALTAR_HOLD_PX * SUB;
        for a in 0..6 {
            if self.realm.altars[a].state != ALTAR_LIT {
                continue;
            }
            let (ax, ay) = self.terrain.altars[a];
            let mut n = 0u32;
            grid_box(&self.hgrid, PCELLS_W, PCELL_SHIFT, ax - r, ay - r, ax + r, ay + r, |q| {
                let h = &self.heroes[q as usize];
                if h.alive() && d2(h.x, h.y, ax, ay) <= r as i64 * r as i64 {
                    n += 1;
                }
            });
            // Monsters within 60 px strike it on the contact cadence.
            let mut dmg = 0u32;
            if (tick + a as u32) % CONTACT_EVERY == 0 {
                let sr = ALTAR_STRIKE_PX * SUB;
                let lim = sr + GRID_MARGIN;
                grid_box(&self.grid, CELLS_W, CELL_SHIFT, ax - lim, ay - lim, ax + lim, ay + lim, |i| {
                    let i = i as usize;
                    let m = &self.m;
                    if m.hp[i] > 0 && m.stun[i] == 0 && m.flags[i] & BOSS == 0 && d2(m.x[i], m.y[i], ax, ay) <= sr as i64 * sr as i64 {
                        dmg = dmg.saturating_add(m.damage(i) * m.row(i).hits as u32);
                    }
                });
            }
            let al = &mut self.realm.altars[a];
            al.progress = al.progress.saturating_add(n);
            al.hp = al.hp.saturating_sub(dmg);
            if al.progress >= need {
                al.state = ALTAR_HELD;
                self.events.push(Event::Altar { index: a as u8, state: ALTAR_HELD });
            } else if al.hp == 0 {
                al.state = ALTAR_RUINED;
                self.events.push(Event::Altar { index: a as u8, state: ALTAR_RUINED });
            }
        }
        let held = self.realm.altars.iter().filter(|a| a.state == ALTAR_HELD).count() as u8;
        if held >= ALTARS_TO_WIN {
            self.end_tide(true);
        }
    }

    /// Heroes in the heart ring, for a boss's health (at most `BOSS_HEART_COUNTED`).
    pub(crate) fn heart_heroes(&self) -> u32 {
        self.heroes.iter().filter(|h| h.alive() && ring_of(h.x, h.y) == RING_HEART).count().min(BOSS_HEART_COUNTED as usize) as u32
    }

    /// The tide target of the spawner: doubled during a tide.
    pub(crate) fn tide_target(&self, target: u32) -> u32 {
        if self.tide { target.saturating_mul(TIDE_TARGET_MUL) } else { target }
    }
}
