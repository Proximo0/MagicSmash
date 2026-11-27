//! A hero in the field: her state, the numbers derived from it each tick (`Mods`), and what happens in
//! the input phase (timers, potions, picks, skills that need no monster, movement, banking, falling).

use crate::deck;
use crate::sheet::{Outing, Sheet};
use crate::tables::*;
use crate::util::{d2, isqrt, pct};
use crate::{Field, SUB};

/// Input byte 0: direction 0..8 in bits 0..3, skill 1, skill 2, the ultimate, interact (hold).
pub const IN_DIR: u16 = 0x0F;
pub const IN_SKILL1: u16 = 0x10;
pub const IN_SKILL2: u16 = 0x20;
pub const IN_ULT: u16 = 0x40;
pub const IN_INTERACT: u16 = 0x80;
/// Input byte 1 (bits 8..15): card pick 0 or 1..4, potion slots 1, 2, 3.
pub const IN_PICK_SHIFT: u32 = 8;
pub const IN_PICK: u16 = 0x0700;
pub const IN_POTION1: u16 = 0x0800;
pub const IN_POTION_SHIFT: u32 = 11;

/// Two input bytes as one word: byte 0 low, byte 1 high.
pub const fn input(byte0: u8, byte1: u8) -> u16 {
    byte0 as u16 | (byte1 as u16) << 8
}

/// Hero step 60 px/s is 3 px a tick; the diagonal is the step times 181/256.
pub const HERO_STEP: i32 = HERO_SPEED_PX_S * SUB / TICK_HZ as i32;
pub const DIAG_NUM: i32 = 181;
pub const DIAG_DEN: i32 = 256;
/// Input directions 1..8 as unit steps (E, then clockwise; y down).
pub const DIRS: [(i32, i32); 9] = [(0, 0), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)];
/// Cast bits (which of skill 1, skill 2, ultimate fired this tick).
pub const CAST1: u8 = 1;
pub const CAST2: u8 = 2;
pub const CAST_ULT: u8 = 4;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Hero {
    pub present: bool,
    pub x: i32,
    pub y: i32,
    pub sheet: Sheet,
    pub class: u8,
    pub job: u8,
    pub race: u8,
    /// The class level the field counts (ceiling), and the six stats under it.
    pub class_level: u8,
    pub stats: [u16; 6],
    pub health: u32,
    pub max_health: u32,
    /// Field level and XP (one outing).
    pub level: u16,
    pub xp: u32,
    pub copies: [u8; NCARDS + 1],
    pub offers: Vec<[u8; DRAW_MAX as usize]>,
    pub owed: u16,
    pub draws: u32,
    pub coin: u32,
    /// Weapon charge: + (100 + attack speed %) a tick; she attacks at `every x 100`.
    pub charge: u32,
    pub attacks: u32,
    pub cooldowns: [u32; 3],
    pub belt: [(u8, u8); BELT],
    pub belt_rest: [u16; BELT],
    pub phoenix_used: bool,
    pub fx: [u16; NFX],
    /// Ticks left DOWNED (0: up).
    pub downed: u16,
    pub raise: u32,
    /// Interact held near a waystone.
    pub hold: u16,
    pub waystone: u8,
    /// Banked at the waystone she stands at: the next hold leaves.
    pub banked: bool,
    /// Tick she last dealt damage, healed or was hit.
    pub active: u32,
    /// TEMPERANCE's fraction carried between ticks; THE LOVERS' healing this second.
    pub regen: u32,
    pub lovers: u32,
    /// THE LOVERS: hundredths of a health point carried to the next tick.
    pub lovers_carry: u32,
    /// Section 14, reserved: the BLOOD MARK and the tick she last struck a hero.
    pub marked: bool,
    pub last_struck: u32,
    pub input: u16,
    pub facing_left: bool,
    pub moving: bool,
    /// The last direction she moved (1..8).
    pub dir: u8,
    /// Ticks since she last moved (contribution counts only while this is short).
    pub idle: u16,
    /// Contribution to the running tide and to the running boss or vault (rules 8): damage dealt, healing done and
    /// half the damage taken, never while she stands still.
    pub tide_contrib: u32,
    pub boss_contrib: u32,
    /// Shrines touched this outing (rules 6, quiet zones): bit k is the shrine of index k.
    pub shrines: u8,
    /// A wailer was near at the end of the last tick.
    pub wailed: bool,
    // ---- this tick only (output; not saved)
    pub hurt: bool,
    pub fired: bool,
    pub cast: u8,
    /// Where a dash started this tick.
    pub dash_from: Option<(i32, i32)>,
}

impl Default for Hero {
    fn default() -> Self {
        Hero {
            present: false,
            x: 0,
            y: 0,
            sheet: Sheet::bench(0, 0, 1),
            class: 0,
            job: NONE,
            race: 0,
            class_level: 1,
            stats: [0; 6],
            health: 0,
            max_health: 0,
            level: 1,
            xp: 0,
            copies: [0; NCARDS + 1],
            offers: Vec::new(),
            owed: 0,
            draws: 0,
            coin: 0,
            charge: 0,
            attacks: 0,
            cooldowns: [0; 3],
            belt: [(P_NONE, 0); BELT],
            belt_rest: [0; BELT],
            phoenix_used: false,
            fx: [0; NFX],
            downed: 0,
            raise: 0,
            hold: 0,
            waystone: NO_WAYSTONE,
            banked: false,
            active: 0,
            regen: 0,
            lovers: 0,
            lovers_carry: 0,
            marked: false,
            last_struck: NEVER,
            input: 0,
            facing_left: false,
            moving: false,
            dir: 3,
            idle: 0,
            tide_contrib: 0,
            boss_contrib: 0,
            shrines: 0,
            wailed: false,
            hurt: false,
            fired: false,
            cast: 0,
            dash_from: None,
        }
    }
}

impl Hero {
    /// Present, up and not at 0 health.
    pub fn alive(&self) -> bool {
        self.present && self.downed == 0 && self.health > 0
    }
    pub fn class_row(&self) -> &'static ClassRow {
        &CLASSES[self.class as usize]
    }
    pub fn job_row(&self) -> Option<&'static Job> {
        JOBS.get(self.job as usize)
    }
    /// The class's passive and the job's, summed where both give a number.
    /// Threat in tenths: the job's when it sets one, else the class's.
    pub fn threat(&self) -> i32 {
        let t = self.job_row().map_or(0, |j| j.passive.threat);
        if t > 0 { t } else { self.class_row().threat }
    }
    pub fn has_fx(&self, fx: u8) -> bool {
        self.fx[fx as usize] > 0
    }
    pub fn active_at(&self, tick: u32) -> bool {
        self.active > 0 && tick.saturating_sub(self.active) <= ACTIVE_TICKS
    }
    /// The skill in a slot (0 skill 1, 1 skill 2, 2 the ultimate) if she has it at her counted level.
    pub fn skill(&self, slot: usize) -> Option<u8> {
        let c = self.class_row();
        let id = match slot {
            0 => c.skill1,
            1 => c.skill2,
            _ => self.job_row().map_or(NONE, |j| j.ultimate),
        };
        let s = SKILLS.get(id as usize)?;
        (self.class_level >= s.level).then_some(id)
    }
    /// A skill's rank factor in percent: `1 + (level - skill level) / 10` ranks, 15% each.
    pub fn rank_pct(&self, skill: u8) -> u32 {
        let s = &SKILLS[skill as usize];
        let rank = (1 + self.class_level.saturating_sub(s.level) / RANK_LEVELS).min(RANK_MAX);
        100 + RANK_PCT * (rank as u32 - 1)
    }
    /// Max health from class, counted level, VIGOR and THE EMPRESS.
    pub fn compute_max_health(&self) -> u32 {
        let c = self.class_row();
        let base = c.health + c.health_per_level * (self.class_level as u32 - 1);
        let empress = deck::card_sum(&self.copies, |fx| if let CardFx::Health(p) = fx { p as i64 } else { 0 });
        let v = pct(base, 100 + VIGOR_PCT as i64 * self.stats[VIGOR] as i64);
        pct(v, 100 + empress).max(1)
    }
    pub fn pushed_pct(&self) -> u32 {
        let r = RACES[self.race as usize].pushed_pct;
        let c = self.class_row().passive.pushed_pct;
        let c = if c == 0 { 100 } else { c };
        r.min(c)
    }

    /// Fills a fresh hero from a sheet and an outing.
    pub fn enter(sheet: &Sheet, outing: &Outing, field: u8, x: i32, y: i32) -> Hero {
        Hero::enter_top(sheet, outing, FIELDS[field as usize].top, x, y)
    }

    /// The same for a place whose top level is `top` (a field's, or a vault's level).
    pub fn enter_top(sheet: &Sheet, outing: &Outing, top: u8, x: i32, y: i32) -> Hero {
        let mut h = Hero {
            present: true,
            x,
            y,
            sheet: sheet.clone(),
            class: sheet.class.min(CLASSES.len() as u8 - 1),
            job: sheet.job,
            race: sheet.race % RACES.len() as u8,
            class_level: sheet.counted_level_top(top),
            stats: sheet.stats_top(top),
            level: outing.level.max(1),
            xp: outing.xp,
            copies: outing.copies,
            offers: outing.offers.clone(),
            owed: outing.owed,
            draws: outing.draws,
            coin: outing.coin,
            cooldowns: outing.cooldowns,
            belt_rest: outing.belt_rest,
            phoenix_used: outing.phoenix_used,
            fx: outing.fx,
            waystone: outing.waystone,
            marked: outing.marked,
            tide_contrib: outing.tide_contrib,
            boss_contrib: outing.boss_contrib,
            shrines: outing.shrines,
            ..Hero::default()
        };
        if h.class_level < SKILL1_LEVEL {
            h.class = NOVICE;
        }
        if h.job_row().is_none_or(|j| j.class != h.class || h.class_level < JOB_LEVEL) {
            h.job = NONE;
        }
        h.belt = outing.belt.unwrap_or_else(|| {
            sheet.belt.map(|(p, n)| match POTIONS.get(p as usize) {
                Some(row) if n > 0 => (p, n.min(row.carried)),
                _ => (P_NONE, 0),
            })
        });
        h.max_health = h.compute_max_health();
        h.health = outing.health.unwrap_or(h.max_health).clamp(1, h.max_health);
        h
    }

    /// The outing state to carry to another copy of the field.
    pub fn outing(&self, tick: u32) -> Outing {
        Outing {
            health: Some(self.health.max(1)),
            level: self.level,
            xp: self.xp,
            copies: self.copies,
            offers: self.offers.clone(),
            owed: self.owed,
            draws: self.draws,
            coin: self.coin,
            cooldowns: self.cooldowns,
            belt: Some(self.belt),
            belt_rest: self.belt_rest,
            phoenix_used: self.phoenix_used,
            fx: self.fx,
            waystone: self.waystone,
            marked: self.marked,
            struck_ago: if self.last_struck == NEVER { NEVER } else { tick.saturating_sub(self.last_struck) },
            tide_contrib: self.tide_contrib,
            boss_contrib: self.boss_contrib,
            shrines: self.shrines,
        }
    }

    /// Heals and marks her active; returns what was healed.
    pub fn heal(&mut self, amount: u32, tick: u32) -> u32 {
        if !self.alive() {
            return 0;
        }
        let before = self.health;
        self.health = self.health.saturating_add(amount).min(self.max_health);
        let healed = self.health - before;
        if healed > 0 {
            self.active = tick;
        }
        healed
    }
}

/// Up again with this % of her health and 2 s unhurt.
pub fn rise_up(h: &mut Hero, health_pct: u32) {
    h.downed = 0;
    h.raise = 0;
    h.health = pct(h.max_health, health_pct as i64).clamp(1, h.max_health);
    h.fx[FX_RAISED as usize] = EFFECTS[FX_RAISED as usize].ticks;
}

/// Moves a hero by a push, scaled by how far she is pushed (KNIGHT, DWARF: half). For pulls and
/// knock-backs that strike heroes (bosses, section 8).
pub fn push_hero(f: &mut Field, id: usize, dx: i32, dy: i32) {
    let h = &f.heroes[id];
    let p = h.pushed_pct() as i64;
    let (nx, ny) = (h.x + (dx as i64 * p / 100) as i32, h.y + (dy as i64 * p / 100) as i32);
    let (x, y) = f.terrain.slide(h.x, h.y, nx, ny);
    let h = &mut f.heroes[id];
    h.x = x;
    h.y = y;
}

/// Integer distance in px between two points in sub units.
pub fn dist_px(ax: i32, ay: i32, bx: i32, by: i32) -> i32 {
    (isqrt(d2(ax, ay, bx, by)) / SUB as i64) as i32
}
