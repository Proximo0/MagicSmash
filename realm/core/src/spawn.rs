//! Births (rules section 4): toward the density target, out of every hero's screen, never on walls, in
//! clutches, with ELITES and CHAMPIONS; and a monster's birth into a slot.

use crate::monster::*;
use crate::tables::*;
use crate::terrain::{level_at, ring_of};
use crate::util::{grid_box, rng_next};
use crate::{FIELD, Field, PCELL_SHIFT, PCELLS_W, SUB, VIEW_H, VIEW_W};

impl Field {
    /// The spawn phase: births toward the density target, out of every hero's screen and off walls. In a tide the
    /// target doubles; in a vault it follows the timeline and the vault's own kinds and level.
    pub(crate) fn phase_spawn(&mut self) {
        if self.live.is_empty() || !self.vault_births_on() {
            return;
        }
        let (target, kinds, fixed_level) = match self.realm.vault {
            Some(v) => {
                let row = &VAULTS[v.vault as usize];
                (self.vault_target(), row.first_kind as usize..(row.first_kind + row.kind_count) as usize, Some(row.level))
            }
            None => {
                let mut target = DENSITY_BASE.min(DENSITY_BASE_PER_HERO * self.live.len() as u32);
                for &q in &self.live {
                    let h = &self.heroes[q as usize];
                    target += RING_WEIGHT[ring_of(h.x, h.y) as usize];
                }
                let row = &FIELDS[self.field as usize];
                (target, row.first_kind as usize..(row.first_kind + row.kind_count) as usize, None)
            }
        };
        let target = self.tide_target(target).min(self.cfg.monsters);
        let total: u32 = KINDS[kinds.clone()].iter().map(|k| k.weight).sum();
        let mut fails = 0;
        while self.alive < target && !self.free.is_empty() {
            let Some((x, y)) = self.find_birth() else {
                fails += 1;
                if fails >= SPAWN_FAILS_PER_TICK {
                    break;
                }
                continue;
            };
            let r = rng_next(&mut self.rng);
            let mut pick = (r % total as u64) as u32;
            let mut kind = kinds.start;
            for k in kinds.clone() {
                if pick < KINDS[k].weight {
                    kind = k;
                    break;
                }
                pick -= KINDS[k].weight;
            }
            let level = fixed_level.unwrap_or_else(|| level_at(self.field, x, y));
            let champ_one_in = if ring_of(x, y) == RING_HEART { CHAMPION_HEART_ONE_IN } else { CHAMPION_ONE_IN };
            for member in 0..KINDS[kind].clutch as i32 {
                let (ox, oy) = clutch_offset(member);
                let (mx, my) = (x + ox * CLUTCH_PX * SUB, y + oy * CLUTCH_PX * SUB);
                if member > 0 && !self.birth_ok(mx, my) {
                    continue;
                }
                let Some(slot) = self.free.pop() else { break };
                let rr = rng_next(&mut self.rng);
                let flags = if (rr >> 8) % champ_one_in == 0 {
                    CHAMPION
                } else if (rr >> 32) % ELITE_ONE_IN == 0 {
                    ELITE
                } else {
                    0
                };
                self.birth(slot as usize, kind as u8, level, flags, mx, my);
                self.spawned.push(slot);
            }
        }
    }

    /// A place to be born: out of every hero's screen, off walls, 400 to 700 px from a random hero (250 to 450 in
    /// the dark), in at most `SPAWN_TRIES` tries.
    pub(crate) fn find_birth(&mut self) -> Option<(i32, i32)> {
        if self.live.is_empty() {
            return None;
        }
        for _ in 0..SPAWN_TRIES {
            let r = rng_next(&mut self.rng);
            let p = &self.heroes[self.live[(r % self.live.len() as u64) as usize] as usize];
            let (lo, hi) = if self.terrain.at(p.x, p.y) & DARK != 0 { (DARK_BIRTH_MIN_PX, DARK_BIRTH_MAX_PX) } else { (BIRTH_MIN_PX, BIRTH_MAX_PX) };
            let span = (hi * 2 + 1) as u64;
            let dx = ((r >> 16) % span) as i32 - hi;
            let dy = ((r >> 32) % span) as i32 - hi;
            let dd = (dx * dx + dy * dy) as i64;
            if dd < (lo * lo) as i64 || dd > (hi * hi) as i64 {
                continue;
            }
            let (x, y) = (p.x + dx * SUB, p.y + dy * SUB);
            if self.birth_ok(x, y) {
                return Some((x, y));
            }
        }
        None
    }

    fn birth_ok(&self, x: i32, y: i32) -> bool {
        if x < 0 || y < 0 || x >= FIELD || y >= FIELD || self.terrain.blocked(x, y) {
            return false;
        }
        let (hw, hh) = (VIEW_W / 2 * SUB, VIEW_H / 2 * SUB);
        let mut seen = false;
        grid_box(&self.hgrid, PCELLS_W, PCELL_SHIFT, x - hw, y - hh, x + hw, y + hh, |q| {
            let h = &self.heroes[q as usize];
            if (h.x - x).abs() < hw && (h.y - y).abs() < hh {
                seen = true;
            }
        });
        !seen
    }

    pub(crate) fn birth(&mut self, i: usize, kind: u8, level: u8, flags: u8, x: i32, y: i32) {
        let m = &mut self.m;
        m.x[i] = x;
        m.y[i] = y;
        m.kind[i] = kind;
        m.level[i] = level;
        m.flags[i] = flags;
        m.stun[i] = 0;
        m.slow[i] = 0;
        m.curse[i] = 0;
        m.timer[i] = 0;
        m.hurt[i] = 0;
        m.hp[i] = m.max_hp(i);
        self.alive += 1;
        self.spawns_total += 1;
    }
}
