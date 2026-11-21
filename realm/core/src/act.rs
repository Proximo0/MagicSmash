//! The input phase: every present hero in id order: timers, TEMPERANCE, picks, potions, skills that need
//! no monster, movement, the weapon's charge, the gate, banking, and the DOWNED, raised and FALLEN.

use crate::deck;
use crate::events::Event;
use crate::hero::*;
use crate::mods::*;
use crate::tables::*;
use crate::util::{d2, grid_box, pct};
use crate::{Field, Zone, FIELD, PCELLS_W, PCELL_SHIFT, SUB};

impl Field {
    /// The input phase: every present hero in id order.
    pub(crate) fn phase_heroes(&mut self, inputs: &[u16]) {
        let tick = self.tick;
        // Timers run down for everyone first, so an effect cast on a later hero this tick is not cut short.
        for h in self.heroes.iter_mut().filter(|h| h.present) {
            for t in h.fx.iter_mut() {
                *t = t.saturating_sub(1);
            }
            for t in h.cooldowns.iter_mut() {
                *t = t.saturating_sub(1);
            }
            for t in h.belt_rest.iter_mut() {
                *t = t.saturating_sub(1);
            }
        }
        for i in 0..self.heroes.len() {
            if !self.heroes[i].present {
                continue;
            }
            let inp = inputs.get(i).copied().unwrap_or(0);
            let m = self.mods[i];
            let h = &mut self.heroes[i];
            let prev = h.input;
            h.input = inp;
            h.fired = false;
            h.cast = 0;
            h.dash_from = None;
            if tick % LOVERS_EVERY == 0 {
                h.lovers = 0;
            }
            if h.downed > 0 {
                h.moving = false;
                h.hold = 0;
                self.downed_tick(i);
                continue;
            }
            let id = i as u16;
            // TEMPERANCE.
            if m.regen_tenths > 0 && h.health < h.max_health {
                h.regen += h.max_health * m.regen_tenths;
                let add = h.regen / REGEN_DEN;
                h.regen %= REGEN_DEN;
                h.health = (h.health + add).min(h.max_health);
            }
            // A card pick: byte 1 bits 0..2 when they change to 1..4.
            let pick = ((inp & IN_PICK) >> IN_PICK_SHIFT) as u8;
            let prev_pick = ((prev & IN_PICK) >> IN_PICK_SHIFT) as u8;
            if pick != 0 && pick != prev_pick {
                deck::pick(self, i, pick);
            }
            // Potions: a slot bit newly pressed.
            for slot in 0..BELT {
                let bit = IN_POTION1 << slot;
                if inp & bit != 0 && prev & bit == 0 {
                    self.drink(i, slot, &m);
                }
            }
            // Skills: held bits fire when ready.
            for (slot, bit) in [IN_SKILL1, IN_SKILL2, IN_ULT].into_iter().enumerate() {
                if inp & bit != 0 {
                    self.cast(i, slot, &m);
                }
            }
            let h = &mut self.heroes[i];
            // Movement, sliding along walls.
            let dir = (inp & IN_DIR).min(8) as usize;
            let (ux, uy) = DIRS[dir];
            h.moving = dir != 0;
            if dir != 0 {
                h.dir = dir as u8;
                let step = (HERO_STEP as i64 * (100 + m.move_pct).max(MIN_SPEED_PCT) as i64 / 100) as i32;
                let (sx, sy) = if ux != 0 && uy != 0 { (step * DIAG_NUM / DIAG_DEN, step * DIAG_NUM / DIAG_DEN) } else { (step, step) };
                if ux < 0 {
                    h.facing_left = true;
                } else if ux > 0 {
                    h.facing_left = false;
                }
                let (nx, ny) = self.terrain.slide(h.x, h.y, h.x + ux * sx, h.y + uy * sy);
                h.x = nx;
                h.y = ny;
            }
            // The weapon.
            let every = h.class_row().weapon.every * 100;
            h.charge = (h.charge + (100 + m.as_pct).max(MIN_SPEED_PCT) as u32).min(every);
            if h.charge >= every {
                h.charge -= every;
                h.fired = true;
                h.attacks = h.attacks.wrapping_add(1);
            }
            // Walking out of the gate banks and leaves.
            let (gx, gy) = self.terrain.gate;
            if uy > 0 && d2(h.x, h.y, gx, gy) <= (GATE_PX * SUB) as i64 * (GATE_PX * SUB) as i64 {
                let coin = std::mem::take(&mut h.coin);
                h.present = false;
                self.events.push(Event::Bank { hero: id, coin, waystone: NO_WAYSTONE });
                self.events.push(Event::Leave { hero: id });
                continue;
            }
            // Banking: interact held within 48 px of a waystone for 3 s, unhurt.
            let near = self.terrain.waystones.iter().position(|&(wx, wy)| {
                d2(h.x, h.y, wx, wy) <= (WAYSTONE_PX * SUB) as i64 * (WAYSTONE_PX * SUB) as i64
            });
            match near {
                None => {
                    h.hold = 0;
                    h.banked = false;
                }
                Some(w) if inp & IN_INTERACT != 0 => {
                    h.hold += 1;
                    if h.hold >= BANK_HOLD {
                        h.hold = 0;
                        if h.banked && h.waystone == w as u8 {
                            h.present = false;
                            self.events.push(Event::Leave { hero: id });
                        } else {
                            let coin = std::mem::take(&mut h.coin);
                            h.waystone = w as u8;
                            h.banked = true;
                            self.events.push(Event::Bank { hero: id, coin, waystone: w as u8 });
                        }
                    }
                }
                Some(_) => h.hold = 0,
            }
        }
    }

    /// A DOWNED hero's tick: raised by allies standing near, or FALLEN when time runs out.
    fn downed_tick(&mut self, i: usize) {
        let tick = self.tick;
        let (x, y) = (self.heroes[i].x, self.heroes[i].y);
        let r = RAISE_PX * SUB;
        let mut best: Option<(u32, u16)> = None;
        let heroes = &self.heroes;
        let mods = &self.mods;
        grid_box(&self.hgrid, PCELLS_W, PCELL_SHIFT, x - r, y - r, x + r, y + r, |q| {
            let qh = &heroes[q as usize];
            if q as usize != i && qh.alive() && d2(qh.x, qh.y, x, y) <= r as i64 * r as i64 {
                let rate = mods[q as usize].raise_pct;
                if best.is_none_or(|(b, bq)| rate > b || (rate == b && (q as u16) < bq)) {
                    best = Some((rate, q as u16));
                }
            }
        });
        let h = &mut self.heroes[i];
        h.downed -= 1;
        match best {
            Some((rate, by)) => {
                h.raise += rate;
                if h.raise >= RAISE_NEED {
                    let rise = self.mods[i].rise_pct;
                    rise_up(h, pct(RISE_HEALTH_PCT, rise as i64));
                    h.active = tick;
                    self.events.push(Event::Raise { hero: i as u16, by });
                    return;
                }
            }
            None => h.raise = 0,
        }
        if h.downed > 0 {
            return;
        }
        // Not raised in time: PHOENIX ASH, or FALLEN.
        if !h.phoenix_used {
            if let Some(slot) = h.belt.iter().position(|&(p, n)| p == P_PHOENIX && n > 0) {
                h.phoenix_used = true;
                h.belt[slot].1 -= 1;
                let PotionFx::Phoenix(p) = POTIONS[P_PHOENIX as usize].fx else { unreachable!() };
                rise_up(h, p);
                let left = h.belt[slot].1;
                self.events.push(Event::Potion { hero: i as u16, slot: slot as u8, left });
                return;
            }
        }
        let keep = self.mods[i].keep_tenths.min(TENTHS);
        let lost = h.coin / 2 * (TENTHS - keep) / TENTHS;
        h.coin -= lost;
        let (wx, wy) = self.terrain.waystones.get(h.waystone as usize).copied().unwrap_or(self.terrain.gate);
        h.x = wx;
        h.y = wy;
        h.raise = 0;
        h.health = h.max_health;
        self.events.push(Event::Fallen { hero: i as u16, coin: lost });
    }

    fn drink(&mut self, i: usize, slot: usize, m: &Mods) {
        let h = &mut self.heroes[i];
        let (p, n) = h.belt[slot];
        let Some(row) = POTIONS.get(p as usize) else { return };
        if n == 0 || h.belt_rest[slot] > 0 {
            return;
        }
        match row.fx {
            PotionFx::Heal(pc) => {
                let amount = pct(pct(h.max_health, pc as i64), (100 + m.cups_pct) as i64);
                h.heal(amount, self.tick);
            }
            PotionFx::Effect(fx) => h.fx[fx as usize] = EFFECTS[fx as usize].ticks,
            PotionFx::Phoenix(_) => return,
        }
        h.belt[slot].1 -= 1;
        h.belt_rest[slot] = row.rest;
        let left = h.belt[slot].1;
        self.events.push(Event::Potion { hero: i as u16, slot: slot as u8, left });
    }

    /// Casts the skill in a slot if she has it and it is ready. Acts that need no monster happen now;
    /// the rest (rings, drops, dashes' damage, volleys, curses) in the fight phase from `cast`.
    fn cast(&mut self, i: usize, slot: usize, m: &Mods) {
        let tick = self.tick;
        let h = &self.heroes[i];
        let Some(sk) = h.skill(slot) else { return };
        if h.cooldowns[slot] > 0 {
            return;
        }
        let row = &SKILLS[sk as usize];
        let cdr = if slot == 2 { m.ult_cdr_pct } else { m.cdr_pct };
        let rank = h.rank_pct(sk);
        let (hx, hy, dir) = (h.x, h.y, h.dir);
        self.heroes[i].cooldowns[slot] = pct(row.cooldown, (100 - cdr) as i64).max(1);
        self.heroes[i].cast |= 1 << slot;
        self.events.push(Event::Skill { hero: i as u16, which: slot as u8 + 1 });
        match row.act {
            Act::HealSelf { pct: p } => {
                let h = &mut self.heroes[i];
                let amount = pct(pct(h.max_health, p as i64), rank as i64);
                h.heal(amount, tick);
            }
            Act::SelfEffect { fx } => {
                self.heroes[i].fx[fx as usize] = pct(EFFECTS[fx as usize].ticks as u32, rank as i64).min(u16::MAX as u32) as u16;
            }
            Act::GroupEffect { px, fx } => {
                let ticks = pct(EFFECTS[fx as usize].ticks as u32, rank as i64).min(u16::MAX as u32) as u16;
                for q in self.allies_within(hx, hy, px, true) {
                    let qh = &mut self.heroes[q];
                    qh.fx[fx as usize] = qh.fx[fx as usize].max(ticks);
                }
            }
            Act::GroupHeal { px, pct: p } => {
                for q in self.allies_within(hx, hy, px, false) {
                    let qh = &mut self.heroes[q];
                    if qh.downed > 0 {
                        rise_up(qh, RISE_HEALTH_PCT * self.mods[q].rise_pct / 100);
                        self.events.push(Event::Raise { hero: q as u16, by: i as u16 });
                    } else {
                        let amount = pct(pct(qh.max_health, p as i64), rank as i64);
                        qh.heal(amount, tick);
                    }
                }
                self.heroes[i].active = tick;
            }
            Act::Dash { len, zone, along_move, .. } => {
                let _ = along_move;
                let (ux, uy) = DIRS[dir as usize];
                let l = len * SUB;
                let (lx, ly) = if ux != 0 && uy != 0 { (l * DIAG_NUM / DIAG_DEN, l * DIAG_NUM / DIAG_DEN) } else { (l, l) };
                let (ex, ey, _) = self.terrain.line_end(hx, hy, hx + ux * lx, hy + uy * ly);
                let h = &mut self.heroes[i];
                h.dash_from = Some((hx, hy));
                h.x = ex.clamp(0, FIELD - 1);
                h.y = ey.clamp(0, FIELD - 1);
                h.fx[FX_DASH as usize] = EFFECTS[FX_DASH as usize].ticks;
                if zone != NONE {
                    self.add_zone(i, zone, hx, hy, rank, m);
                }
            }
            Act::Zone { zone, reach: 0 } => self.add_zone(i, zone, hx, hy, rank, m),
            _ => {}
        }
    }

    /// Present, up heroes within `px` of a point, by id (the downed too when `with_downed` is false and
    /// they are present: SANCTUARY raises them).
    pub(crate) fn allies_within(&self, x: i32, y: i32, px: i32, only_up: bool) -> Vec<usize> {
        let r = px * SUB;
        let mut v = Vec::new();
        // The hero grid holds only the living; the downed are found by a scan (few).
        grid_box(&self.hgrid, PCELLS_W, PCELL_SHIFT, x - r, y - r, x + r, y + r, |q| {
            let qh = &self.heroes[q as usize];
            if qh.alive() && d2(qh.x, qh.y, x, y) <= r as i64 * r as i64 {
                v.push(q as usize);
            }
        });
        if !only_up {
            for (q, qh) in self.heroes.iter().enumerate() {
                if qh.present && qh.downed > 0 && d2(qh.x, qh.y, x, y) <= r as i64 * r as i64 {
                    v.push(q);
                }
            }
        }
        v.sort_unstable();
        v.dedup();
        v
    }

    pub(crate) fn add_zone(&mut self, owner: usize, zone: u8, x: i32, y: i32, rank: u32, m: &Mods) {
        if self.zones.len() >= ZONE_POOL {
            return;
        }
        let row = &ZONES[zone as usize];
        let per_act = row.dmg_s * ZONE_EVERY / TICK_HZ;
        // Like every hero damage: the weapon's item level, then the power product.
        let lvl = weapon_pct(self.heroes[owner].sheet.weapon_level(self.field));
        let dmg = (per_act as u64 * lvl / 100 * m.power / POWER_ONE * rank as u64 / 100) as u32;
        let heal_tenths = row.heal_s * 10 * ZONE_EVERY / TICK_HZ * rank / 100;
        let px = row.px * m.size_pct as i32 / 100;
        let ticks = pct(row.ticks as u32, rank as i64).min(u16::MAX as u32) as u16;
        self.zones.push(Zone { x, y, px, kind: zone, owner: owner as u16, left: ticks, age: 0, dmg, heal_tenths });
    }
}

