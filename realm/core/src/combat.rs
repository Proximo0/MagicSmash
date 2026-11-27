//! The fight phase: hero strikes (gathered in parallel) are applied in hero order, then zones, drops,
//! contact and monster shots against heroes, falls, healing, menders, and last the kills with their
//! credit, XP, coin and death rules (burster, splitter, curse).

use crate::attack::{Hit, Strikes};
use crate::events::Event;
use crate::hero::rise_up;
use crate::mods::{CARD_KNIGHT_OF_WANDS, POWER_ONE};
use crate::monster::{AURA_MEND, AURA_WAIL, BOSS, clutch_offset};
use crate::tables::*;
use crate::util::{d2, grid_box, par_ranges, pct};
use crate::{Drop, Field, PCELL_SHIFT, PCELLS_W, SUB, Shot, cell_of};

/// Heroes per fight thread at least.
pub const FIGHT_MIN_PER_THREAD: usize = 64;

impl Field {
    pub(crate) fn phase_fight(&mut self) {
        self.m.hurt.fill(0);
        for i in 0..self.heroes.len() {
            let h = &mut self.heroes[i];
            h.hurt = false;
            if h.present {
                h.wailed = self.aura[cell_of(h.x, h.y)] & AURA_WAIL != 0;
            }
        }
        let this = &*self;
        let outs = par_ranges(self.heroes.len(), self.cfg.threads, FIGHT_MIN_PER_THREAD, |a, b| (this.gather_strikes(a, b), this.gather_contact(a, b)));
        let mut killed: Vec<(u32, u16)> = Vec::new();
        self.dealt.clear();
        self.dealt.resize(self.heroes.len(), 0);
        let mut contact = Vec::new();
        // Drops thrown earlier land first, so one thrown this tick falls `delay` ticks from now.
        self.land_drops(&mut killed);
        // All the ranges' strikes as one, so the order of hits, heals and pulls never depends on the thread count.
        let mut all = crate::attack::Strikes::default();
        for (s, c) in outs {
            all.hits.extend(s.hits);
            all.heals.extend(s.heals);
            all.drops.extend(s.drops);
            all.zones.extend(s.zones);
            all.curses.extend(s.curses);
            all.pulls.extend(s.pulls);
            all.phits.extend(s.phits);
            contact.extend(c);
        }
        self.apply_strikes(all, &mut killed);
        self.act_zones(&mut killed);
        // Heroes struck: contact (with JUSTICE and drainers) and monster shots.
        let shots = self.update_shots();
        let mut k = 0;
        while k < contact.len() {
            let hero = contact[k].0;
            let mut end = k;
            let mut raw = 0u32;
            while end < contact.len() && contact[end].0 == hero {
                raw = raw.saturating_add(contact[end].2);
                end += 1;
            }
            let taken = self.hurt_hero(hero as usize, raw, &mut killed);
            let reflect = self.mods[hero as usize].reflect_pct;
            for &(_, mi, r) in &contact[k..end] {
                let i = mi as usize;
                if KINDS[self.m.kind[i] as usize].beh & DRAINER != 0 && self.m.hp[i] > 0 && raw > 0 {
                    let share = (taken as u64 * r as u64 / raw as u64) as u32;
                    self.m.hp[i] = (self.m.hp[i] + share).min(self.m.max_hp(i));
                }
                if reflect > 0 && self.heroes[hero as usize].present {
                    let dmg = pct(r, reflect as i64).max(1);
                    let (sx, sy) = (self.heroes[hero as usize].x, self.heroes[hero as usize].y);
                    self.apply_hit(Hit { m: mi, dmg, hero, stun: 0, slow: 0, push: 0, sx, sy }, &mut killed);
                }
            }
            k = end;
        }
        for (hero, raw) in shots {
            self.hurt_hero(hero as usize, raw, &mut killed);
        }
        // THE LOVERS: a share of the damage dealt, at most a share of health a second.
        for i in 0..self.heroes.len() {
            let m = self.mods[i];
            if m.lifesteal_pct == 0 || self.dealt[i] == 0 {
                continue;
            }
            let h = &mut self.heroes[i];
            let budget = pct(h.max_health, m.lifesteal_cap as i64).saturating_sub(h.lovers);
            // A share of every point dealt, with the fraction carried so small blows still count.
            let parts = self.dealt[i] as u64 * m.lifesteal_pct as u64 + h.lovers_carry as u64;
            h.lovers_carry = (parts % 100) as u32;
            let heal = ((parts / 100).min(u32::MAX as u64) as u32).min(budget);
            h.lovers += h.heal(heal, self.tick);
        }
        // Menders: every 2 s, monsters near one heal 4% (once, however many menders).
        if self.tick % MEND_EVERY == 0 {
            for i in 0..self.m.hp.len() {
                if self.m.hp[i] > 0 && self.m.flags[i] & BOSS == 0 && self.aura[cell_of(self.m.x[i], self.m.y[i])] & AURA_MEND != 0 {
                    let mx = self.m.max_hp(i);
                    self.m.hp[i] = (self.m.hp[i] + pct(mx, MEND_PCT as i64)).min(mx);
                }
            }
        }
        self.realm_fight(&mut killed);
        self.process_kills(killed);
    }

    fn apply_strikes(&mut self, s: Strikes, killed: &mut Vec<(u32, u16)>) {
        for hit in s.hits {
            self.apply_hit(hit, killed);
        }
        if !s.phits.is_empty() {
            self.apply_phits(s.phits, killed);
        }
        for (q, amount, by, shield) in s.heals {
            if !self.may_help(by as usize, q as usize) {
                continue;
            }
            let tick = self.tick;
            let qh = &mut self.heroes[q as usize];
            let healed = qh.heal(amount, tick);
            if shield {
                qh.fx[FX_SHIELD as usize] = EFFECTS[FX_SHIELD as usize].ticks;
            }
            self.heroes[by as usize].active = tick;
            if q != by {
                self.credit(by as usize, healed);
            }
        }
        for (i, tx, ty) in s.pulls {
            let i = i as usize;
            if self.m.hp[i] > 0 && !self.m.immovable(i) {
                let (x, y) = self.terrain.mslide(self.m.x[i], self.m.y[i], tx, ty);
                self.m.x[i] = x;
                self.m.y[i] = y;
            }
        }
        for (i, t) in s.curses {
            let c = &mut self.m.curse[i as usize];
            *c = (*c).max(t);
        }
        self.drops.extend(s.drops);
        for (owner, zone, x, y, rank) in s.zones {
            let m = self.mods[owner as usize];
            self.add_zone(owner as usize, zone, x, y, rank, &m);
        }
    }

    /// One hit on a monster: damage, stun, slow and push (none of them on a brute but the damage).
    pub(crate) fn apply_hit(&mut self, hit: Hit, killed: &mut Vec<(u32, u16)>) {
        let i = hit.m as usize;
        let m = &mut self.m;
        if m.hp[i] == 0 {
            return;
        }
        let d = hit.dmg.max(1).min(m.hp[i]);
        m.hp[i] -= d;
        m.hurt[i] = 1;
        if let Some(h) = self.heroes.get_mut(hit.hero as usize) {
            h.active = self.tick;
        }
        if let Some(x) = self.dealt.get_mut(hit.hero as usize) {
            *x = x.saturating_add(d);
        }
        if !m.immovable(i) {
            m.stun[i] = m.stun[i].max(hit.stun);
            m.slow[i] = m.slow[i].max(hit.slow);
            if hit.push > 0 {
                let (x, y) = (m.x[i], m.y[i]);
                let dl = crate::util::isqrt(d2(x, y, hit.sx, hit.sy)).max(1);
                let (nx, ny) = (x + ((x - hit.sx) as i64 * hit.push as i64 / dl) as i32, y + ((y - hit.sy) as i64 * hit.push as i64 / dl) as i32);
                let (nx, ny) = self.terrain.mslide(x, y, nx, ny);
                m.x[i] = nx;
                m.y[i] = ny;
            }
        }
        if m.hp[i] == 0 {
            killed.push((i as u32, hit.hero));
        }
    }

    fn act_zones(&mut self, killed: &mut Vec<(u32, u16)>) {
        let tick = self.tick;
        let mut k = 0;
        while k < self.zones.len() {
            let z = self.zones[k];
            if z.age % ZONE_EVERY as u16 == 0 {
                let row = &ZONES[z.kind as usize];
                let r = z.px * SUB;
                if row.dmg_s > 0 || row.slow {
                    let mut v = Vec::new();
                    self.in_circle(z.x, z.y, r, |i| v.push(i));
                    v.sort_unstable();
                    let mods = self.mods.get(z.owner as usize).copied().unwrap_or_default();
                    for i in v {
                        if row.slow && !self.m.immovable(i) {
                            self.m.slow[i] = self.m.slow[i].max(ZONE_SLOW_TICKS);
                        }
                        if z.dmg > 0 {
                            let d = (z.dmg as u64 * self.target_pct(&mods, i, z.x, z.y) / 100) as u32;
                            self.apply_hit(Hit { m: i as u32, dmg: d, hero: z.owner, stun: 0, slow: 0, push: 0, sx: z.x, sy: z.y }, killed);
                        }
                    }
                }
                // A hero's zone strikes her foes in it too (section 14).
                if z.dmg > 0 && self.flagged(z.owner as usize) {
                    let ph: Vec<crate::pvp::PHit> = self
                        .foes_in_circle(z.owner as usize, z.x, z.y, r)
                        .into_iter()
                        .map(|q| crate::pvp::PHit { to: q, by: z.owner, dmg: pvp_dmg(z.dmg as u64) })
                        .collect();
                    self.apply_phits(ph, killed);
                }
                if row.heal_s > 0 || row.fx != NONE {
                    for q in self.allies_within(z.x, z.y, z.px, true) {
                        if !self.may_help(z.owner as usize, q) {
                            continue;
                        }
                        let qh = &mut self.heroes[q];
                        if row.heal_s > 0 {
                            let amount = (qh.max_health as u64 * z.heal_tenths as u64 / 1_000) as u32;
                            let healed = qh.heal(amount.max(1), tick);
                            if healed > 0 {
                                if let Some(o) = self.heroes.get_mut(z.owner as usize) {
                                    o.active = tick;
                                }
                                if q != z.owner as usize {
                                    self.credit(z.owner as usize, healed);
                                }
                            }
                        }
                        if row.fx != NONE {
                            let qh = &mut self.heroes[q];
                            let t = EFFECTS[row.fx as usize].ticks;
                            qh.fx[row.fx as usize] = qh.fx[row.fx as usize].max(t);
                        }
                    }
                }
            }
            let z = &mut self.zones[k];
            z.age += 1;
            z.left = z.left.saturating_sub(1);
            if z.left == 0 {
                self.zones.remove(k);
            } else {
                k += 1;
            }
        }
    }

    fn land_drops(&mut self, killed: &mut Vec<(u32, u16)>) {
        let mut k = 0;
        while k < self.drops.len() {
            let d = &mut self.drops[k];
            d.left = d.left.saturating_sub(1);
            if d.left > 0 {
                k += 1;
                continue;
            }
            let d: Drop = self.drops.remove(k);
            let mut v = Vec::new();
            self.in_circle(d.x, d.y, d.px * SUB, |i| v.push(i));
            v.sort_unstable();
            let mods = self.mods.get(d.hero as usize).copied().unwrap_or_default();
            for i in v {
                let dmg = (d.dmg as u64 * self.target_pct(&mods, i, d.x, d.y) / 100) as u32;
                self.apply_hit(Hit { m: i as u32, dmg, hero: d.hero, stun: d.stun, slow: 0, push: 0, sx: d.x, sy: d.y }, killed);
            }
            if self.flagged(d.hero as usize) {
                let ph: Vec<crate::pvp::PHit> =
                    self.foes_in_circle(d.hero as usize, d.x, d.y, d.px * SUB).into_iter().map(|q| crate::pvp::PHit { to: q, by: d.hero, dmg: pvp_dmg(d.dmg as u64) }).collect();
                self.apply_phits(ph, killed);
            }
        }
    }

    /// Damage to a hero (contact, shots, bursts; later, marked heroes' blows): reductions, unhurt,
    /// cannot fall, DOWNED and TEN OF SWORDS. Returns the damage taken.
    pub(crate) fn hurt_hero(&mut self, i: usize, raw: u32, killed: &mut Vec<(u32, u16)>) -> u32 {
        let tick = self.tick;
        let m = self.mods[i];
        let h = &mut self.heroes[i];
        if !h.alive() || raw == 0 {
            return 0;
        }
        h.active = tick;
        h.hurt = true;
        if m.unhurt {
            return 0;
        }
        let mut d = (raw as u64 * m.taken / POWER_ONE).min(u32::MAX as u64) as u32;
        if m.nofall || h.has_fx(FX_MARTYR) {
            d = d.min(h.health - 1);
        }
        // Contribution counts half of the hit that came at her, before her own reductions (job B1): a tank who
        // draws the horde and shrugs it off contributes for what she drew, not less for shrugging.
        let drawn = (raw.max(d) as u64 * CONTRIB_DRAWN_PCT as u64 / 100) as u32;
        if d < h.health {
            h.health -= d;
            self.credit(i, drawn);
            return d;
        }
        let taken = h.health;
        self.credit(i, drawn);
        let h = &mut self.heroes[i];
        h.health = 0;
        h.downed = DOWNED_TICKS;
        h.raise = 0;
        h.hold = 0;
        // Downed by this blow: credit only if it was a hero's (`apply_phits` sets it after this).
        self.pvp.set_downer(i, crate::pvp::NOBODY);
        self.deaths_total += 1;
        self.events.push(Event::Down { hero: i as u16 });
        if m.burst_dmg > 0 {
            let (x, y) = (h.x, h.y);
            let mut v = Vec::new();
            self.in_circle(x, y, m.burst_px * SUB, |k| v.push(k));
            v.sort_unstable();
            for k in v {
                let dmg = (m.burst_dmg as u64 * self.target_pct(&m, k, x, y) / 100) as u32;
                self.apply_hit(Hit { m: k as u32, dmg, hero: i as u16, stun: 0, slow: 0, push: 0, sx: x, sy: y }, killed);
            }
        }
        taken
    }

    fn process_kills(&mut self, mut killed: Vec<(u32, u16)>) {
        let tick = self.tick;
        self.cxp.clear();
        self.cxp.resize(self.heroes.len(), 0);
        let r = XP_SHARE_PX * SUB;
        let mut k = 0;
        while k < killed.len() {
            let (id, killer) = killed[k];
            k += 1;
            let i = id as usize;
            let (x, y) = (self.m.x[i], self.m.y[i]);
            let (kind, level, flags) = (self.m.kind[i], self.m.level[i], self.m.flags[i]);
            let xp = self.m.xp(i);
            let curse = self.m.curse[i];
            let dmg = self.m.damage(i);
            // Credit: every living, active hero within 200 px.
            let mut credited = Vec::new();
            grid_box(&self.hgrid, PCELLS_W, PCELL_SHIFT, x - r, y - r, x + r, y + r, |q| {
                let h = &self.heroes[q as usize];
                if h.alive() && h.active_at(tick) && d2(h.x, h.y, x, y) <= r as i64 * r as i64 {
                    credited.push(q as u16);
                }
            });
            credited.sort_unstable();
            let first = self.credits.len() as u32;
            self.credits.extend_from_slice(&credited);
            self.events.push(Event::Kill { kind, level, flags, x, y, first, count: credited.len() as u16 });
            for &q in &credited {
                let q = q as usize;
                let m = self.mods[q];
                let gain = pct(xp, m.xp_pct as i64);
                self.gain_field_xp(q, gain);
                let h = &mut self.heroes[q];
                if level as u32 + CLASS_XP_LEVELS_BELOW as u32 >= h.sheet.class_level as u32 {
                    self.cxp[q] += pct(gain, RACES[h.race as usize].class_xp_pct as i64);
                }
                if flags & BOSS == 0 {
                    h.coin = h.coin.saturating_add(pct(xp, m.coin_pct as i64));
                }
            }
            if let Some(h) = self.heroes.get_mut(killer as usize) {
                if h.alive() {
                    if h.has_fx(FX_BLOOD_RAGE) {
                        let amount = pct(h.max_health, BLOOD_RAGE_HEAL_PCT as i64).max(1);
                        h.heal(amount, tick);
                    }
                    if h.copies[CARD_KNIGHT_OF_WANDS as usize] > 0 {
                        h.fx[FX_KNIGHT_OF_WANDS as usize] = EFFECTS[FX_KNIGHT_OF_WANDS as usize].ticks;
                    }
                }
            }
            // The slot is free before its children take one.
            self.free.push(id);
            self.alive -= 1;
            self.kills_total += 1;
            let beh = KINDS[kind as usize].beh;
            if flags & BOSS != 0 {
                self.boss_dead();
                continue;
            }
            if beh & BURSTER != 0 {
                let shot = Shot { x, y, vx: 0, vy: 0, left: BURST_DELAY, dmg: dmg * BURST_DAMAGE_MUL, px: BURST_PX };
                if self.shots.len() < SHOT_POOL {
                    self.shots.push(shot);
                } else {
                    let mut out = Vec::new();
                    self.circle_on_heroes(x, y, BURST_PX, shot.dmg, &mut out);
                    for (q, raw) in out {
                        self.hurt_hero(q as usize, raw, &mut killed);
                    }
                }
            }
            if beh & SPLITTER != 0 && KINDS[kind as usize].split != NO_KIND {
                for c in 0..SPLIT_INTO as i32 {
                    let Some(slot) = self.free.pop() else { break };
                    let (ox, oy) = clutch_offset(c + 1);
                    let (cx, cy) = self.terrain.mslide(x, y, x + ox * crate::monster::SPLIT_PX * SUB, y + oy * crate::monster::SPLIT_PX * SUB);
                    self.birth(slot as usize, KINDS[kind as usize].split, level, 0, cx, cy);
                    self.spawned.push(slot);
                }
            }
            if curse > 0 {
                let mut v = Vec::new();
                self.in_circle(x, y, CURSE_SPREAD_PX * SUB, |j| v.push(j));
                for j in v {
                    self.m.curse[j] = self.m.curse[j].max(curse);
                }
            }
        }
        for q in 0..self.heroes.len() {
            if self.cxp[q] > 0 {
                self.events.push(Event::Xp { hero: q as u16, amount: self.cxp[q] });
            }
        }
        let _ = rise_up;
    }
}

/// A blow's damage to a hero: `PVP_DAMAGE_PCT` of what it does to a monster.
pub(crate) fn pvp_dmg(d: u64) -> u32 {
    (d * crate::pvp::PVP_DAMAGE_PCT / 100).clamp(1, u32::MAX as u64) as u32
}

/// BLOOD RAGE: each kill heals 1%.
pub const BLOOD_RAGE_HEAL_PCT: u32 = 1;
