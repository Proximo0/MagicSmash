//! The numbers derived from a hero's state at the start of every tick: damage, speed, damage taken and
//! the card and aura numbers (not state: rebuilt every tick from state).

use crate::deck;
use crate::hero::Hero;
use crate::tables::*;
use crate::util::{d2, grid_box};
use crate::{Field, PCELL_SHIFT, PCELLS_W, SUB};

/// Numbers derived from a hero's state at the start of a tick (not state: rebuilt every tick).
#[derive(Clone, Copy, Debug, Default)]
pub struct Mods {
    /// Damage multiplier, parts per `POWER_ONE` (MIGHT x class level x cards x effects).
    pub power: u64,
    pub as_pct: i32,
    pub move_pct: i32,
    /// Damage taken, parts per `POWER_ONE`.
    pub taken: u64,
    pub unhurt: bool,
    pub nofall: bool,
    pub size_pct: u32,
    pub reach_pct: u32,
    pub cdr_pct: u32,
    pub ult_cdr_pct: u32,
    pub coin_pct: u32,
    /// Class XP of a kill, percent (THE HERMIT, SCHOLAR'S INK).
    pub xp_pct: u32,
    pub luck: i32,
    pub pierce_add: u8,
    pub targets_add: u8,
    pub push_add: i32,
    pub elite_pct: u32,
    pub execute_pct: u32,
    pub execute_under: u32,
    pub crit_chance: u32,
    pub reflect_pct: u32,
    pub lifesteal_pct: u32,
    pub lifesteal_cap: u32,
    pub every_nth: u32,
    pub nth_extra: u32,
    pub raise_pct: u32,
    pub rise_pct: u32,
    pub regen_tenths: u32,
    pub cups_pct: u32,
    pub burst_dmg: u32,
    pub burst_px: i32,
    pub keep_tenths: u32,
}

/// Damage and taken multipliers are in parts per this.
pub const POWER_ONE: u64 = 100_000_000;
/// The lowest attack speed a hero can have (percent of base).
pub const MIN_SPEED_PCT: i32 = 10;
pub const MAX_CDR_PCT: u32 = 80;

/// Computes a hero's mods from her own state and the heroes around her (auras, THE SUN, allies).
pub fn mods_of(f: &Field, id: usize) -> Mods {
    let h = &f.heroes[id];
    let mut m = Mods::default();
    if !h.present {
        return m;
    }
    let pc = h.class_row().passive;
    let pj = h.job_row().map(|j| j.passive).unwrap_or_default();
    let cards = deck::card_mods(&h.copies, h.class_row().weapon.shape, h.job != NONE, f.tide);

    // Allies around her: counts, the strongest paladin aura and THE SUN.
    let (mut near100, mut near150, mut aura, mut sun) = (0i32, 0i32, 0u32, 0u32);
    let r = 150 * SUB;
    let heroes = &f.heroes;
    let mut seen = |q: &Hero, me: bool| {
        let dd = d2(q.x, q.y, h.x, h.y);
        if !me {
            if dd <= (100 * SUB) as i64 * (100 * SUB) as i64 {
                near100 += 1;
            }
            if dd <= (150 * SUB) as i64 * (150 * SUB) as i64 {
                near150 += 1;
            }
        }
        let qp = q.job_row().map(|j| j.passive).filter(|p| p.aura_pct > 0).unwrap_or(q.class_row().passive);
        if qp.aura_pct > 0 && dd <= (qp.aura_px * SUB) as i64 * (qp.aura_px * SUB) as i64 {
            aura = aura.max(qp.aura_pct);
        }
        let qs = q.copies[CARD_SUN as usize] as u32;
        if qs > 0 && dd <= (SUN_PX * SUB) as i64 * (SUN_PX * SUB) as i64 {
            sun = sun.max(SUN_PCT * qs);
        }
    };
    grid_box(&f.hgrid, PCELLS_W, PCELL_SHIFT, h.x - r, h.y - r, h.x + r, h.y + r, |q| {
        let qh = &heroes[q as usize];
        if qh.alive() && q as usize != id {
            seen(qh, false);
        }
    });
    seen(h, true);

    let mut fxs = (0i32, 0i32, 0i32, 0i32, 0i32);
    let mut taken_fx: u64 = POWER_ONE;
    for (k, e) in EFFECTS.iter().enumerate() {
        if h.fx[k] == 0 {
            continue;
        }
        let mul = if k == FX_KNIGHT_OF_WANDS as usize { h.copies[CARD_KNIGHT_OF_WANDS as usize].max(1) as i32 } else { 1 };
        fxs.0 += e.dmg_pct * mul;
        fxs.1 += e.as_pct * mul;
        fxs.2 += e.move_pct * mul;
        fxs.3 += e.xp_pct * mul;
        fxs.4 += e.luck * mul;
        if e.taken_pct != 0 {
            taken_fx = taken_fx * (100 + e.taken_pct).max(0) as u64 / 100;
        }
        m.unhurt |= e.unhurt;
        m.nofall |= e.nofall;
    }
    // Effects group: timed effects, THE SUN, the CRUSADER's allies, the BERSERKER's missing health, ORC.
    let mut eff = fxs.0 + sun as i32;
    if pj.ally_dmg_pct > 0 {
        eff += (pj.ally_dmg_pct as i32 * near100).min(pj.ally_dmg_max as i32);
    }
    if pj.dmg_per_missing > 0 && h.max_health > 0 {
        let missing = 100 - (h.health as i64 * 100 / h.max_health as i64) as i32;
        eff += missing / pj.dmg_per_missing as i32;
    }
    let race = &RACES[h.race as usize];
    if race.low_dmg_pct > 0 && (h.health as u64 * 100) < (h.max_health as u64 * race.low_under as u64) {
        eff += race.low_dmg_pct;
    }
    let mut card_dmg = cards.dmg_pct;
    if cards.alone_pct > 0 && near150 == 0 {
        card_dmg += cards.alone_pct;
    }
    if cards.company_pct > 0 {
        card_dmg += (cards.company_pct * near150).min(cards.company_max) * cards.company_copies;
    }
    let might = 100 + MIGHT_PCT as u64 * h.stats[MIGHT] as u64;
    // The class level the field counts (rules 2): 2% a level, in place of the old per-outing field level.
    let cl = 100 + CLASS_LEVEL_DMG_PCT as u64 * (h.class_level.max(1) as u64 - 1);
    m.power = might * cl * (100 + card_dmg.max(-90)) as u64 * (100 + eff.max(-90)) as u64;

    m.as_pct = (FOCUS_PCT * h.stats[FOCUS] as i32 + cards.as_pct + fxs.1).max(MIN_SPEED_PCT - 100);
    let swift = (SWIFT_PCT * h.stats[SWIFT] as i32).min(SWIFT_CAP_PCT);
    let ground = f.terrain.at(h.x, h.y);
    let mut terrain = 0;
    if ground & ROAD != 0 {
        terrain += ROAD_MOVE_PCT;
    }
    if ground & MIRE != 0 {
        terrain += MIRE_MOVE_PCT;
    }
    if h.wailed {
        terrain += WAIL_MOVE_PCT;
    }
    if let Some(b) = &f.realm.boss {
        if b.mires.iter().any(|mi| d2(h.x, h.y, mi.x, mi.y) <= (mi.px * SUB) as i64 * (mi.px * SUB) as i64) {
            terrain += crate::boss::MIRE_SLOW_PCT;
        }
    }
    m.move_pct = swift + cards.move_pct + pc.move_pct + pj.move_pct + fxs.2 + terrain;

    let ward = (WARD_PCT * h.stats[WARD] as i32).min(WARD_CAP_PCT);
    let card_taken = (100 + cards.taken_pct).max(0) as u64;
    m.taken = (100 - ward) as u64 * card_taken * (100 - aura) as u64 * taken_fx / POWER_ONE * 100;
    m.size_pct = 100 + cards.size_pct;
    m.reach_pct = 100 + cards.reach_pct + pj.reach_pct;
    m.cdr_pct = cards.cdr_pct.min(MAX_CDR_PCT);
    m.ult_cdr_pct = (cards.cdr_pct + cards.ult_cdr_pct).min(MAX_CDR_PCT);
    m.coin_pct = 100 + FORTUNE_COIN_PCT * h.stats[FORTUNE] as u32 + cards.coin_pct;
    m.xp_pct = (100 + cards.xp_pct as i32 + fxs.3).max(0) as u32;
    m.luck = FORTUNE_LUCK * h.stats[FORTUNE] as i32 + fxs.4;
    // The BLOOD MARK's reward (section 14): coin from kills and luck while she carries it.
    if h.marked {
        m.coin_pct += crate::pvp::MARK_COIN_PCT;
        m.luck += crate::pvp::MARK_LUCK;
    }
    m.pierce_add = cards.fool;
    m.targets_add = cards.fool;
    m.push_add = cards.push_px;
    m.elite_pct = cards.elite_pct + pj.elite_pct;
    m.execute_pct = cards.execute_pct;
    m.execute_under = cards.execute_under;
    m.crit_chance = cards.crit;
    m.reflect_pct = cards.reflect;
    m.lifesteal_pct = cards.lifesteal;
    m.lifesteal_cap = cards.lifesteal_cap;
    m.every_nth = cards.every_nth;
    m.nth_extra = cards.nth_extra;
    m.raise_pct = if pc.raise_pct > 0 { pc.raise_pct } else { 100 } * (100 + cards.raise_pct) / 100;
    m.rise_pct = 100 + cards.rise_pct;
    m.regen_tenths = cards.regen;
    m.cups_pct = cards.cups;
    m.burst_dmg = cards.burst_dmg;
    m.burst_px = cards.burst_px;
    m.keep_tenths = cards.keep;
    m
}

pub const CARD_SUN: u8 = 17;
pub const CARD_KNIGHT_OF_WANDS: u8 = 30;
pub const CARD_HANGED_MAN: u8 = 20;
pub const CARD_THREE_OF_CUPS: u8 = 24;
pub const SUN_PCT: u32 = 3;
pub const SUN_PX: i32 = 100;
/// TEMPERANCE: tenths of a percent a second, so per tick out of `REGEN_DEN`.
pub const REGEN_DEN: u32 = 1_000 * TICK_HZ;
/// The fraction carried by TEMPERANCE is in parts of this.
pub const LOVERS_EVERY: u32 = TICK_HZ;
