//! The saved hero as the field sees her (`Sheet`, rules section 2) and what lasts one outing (`Outing`).

use crate::tables::*;

/// What the server hands `Field::join`: everything kept for good, already turned into numbers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Sheet {
    /// Class 0..5 (NOVICE below class level 10, whatever this says).
    pub class: u8,
    /// Job id 0..9, or `NONE` (only from class level 40, and only one of the class's two).
    pub job: u8,
    pub race: u8,
    /// 1..60.
    pub class_level: u8,
    /// Stat points spent: one per class level after the first.
    pub points: [u16; 6],
    /// Stat points from gear, runes and cards in sockets.
    pub gear: [u16; 6],
    /// The item level of the gear worn: scales the weapon's damage, and gear above the field's ceiling
    /// scales down.
    pub gear_level: u8,
    /// Card ids 1..30, at most `DECK_SIZE`.
    pub deck: Vec<u8>,
    /// Three slots: (potion id or `P_NONE`, charges).
    pub belt: [(u8, u8); BELT],
    pub look: u32,
}

/// Line points of an item of a level: `1 + level / 4`.
pub fn line_points(item_level: u8) -> u32 {
    1 + item_level as u32 / 4
}

/// Bench gear: six UNCOMMON items of the hero's level, two lines each (UNCOMMON's step is 120%).
pub const BENCH_LINES: [u16; 6] = [4, 2, 1, 3, 2, 0];
pub const BENCH_RARITY_PCT: u32 = 120;
/// Bench points: share of the spent points per stat, in twelfths.
pub const BENCH_POINT_TWELFTHS: [u16; 6] = [6, 2, 1, 2, 1, 0];
/// Bench class byte: bits 0..2 the class, bit 3 the second of its two jobs.
pub const BENCH_SECOND_JOB: u8 = 8;

impl Sheet {
    /// A bench hero of a class level in gear of that level. `class` bits 0..2 are the class, bit 3 picks
    /// the class's second job (from level 40).
    pub fn bench(class: u8, race: u8, class_level: u8) -> Sheet {
        let level = class_level.clamp(1, CLASS_LEVEL_MAX);
        let mut c = (class & 7) % CLASSES.len() as u8;
        if level < SKILL1_LEVEL {
            c = NOVICE;
        }
        let job = if c != NOVICE && level >= JOB_LEVEL { CLASSES[c as usize].jobs[(class & BENCH_SECOND_JOB != 0) as usize] } else { NONE };
        let spent = level as u16 - 1;
        let mut points = [0u16; 6];
        let mut given = 0;
        for s in 0..6 {
            points[s] = spent * BENCH_POINT_TWELFTHS[s] / 12;
            given += points[s];
        }
        points[MIGHT] += spent - given;
        let per_line = (line_points(level) * BENCH_RARITY_PCT / 100) as u16;
        let gear = BENCH_LINES.map(|n| n * per_line);
        let owned = owned_cards(level);
        let deck: Vec<u8> = (1..=owned.min(DECK_SIZE as u8)).collect();
        Sheet {
            class: c,
            job,
            race: race % RACES.len() as u8,
            class_level: level,
            points,
            gear,
            gear_level: level,
            deck,
            belt: [(P_HEALING, 3), (P_WHETSTONE, 2), (P_PHOENIX, 1)],
            look: 0,
        }
    }

    /// The class level the field counts (the ceiling: its top level + 2).
    pub fn counted_level(&self, field: u8) -> u8 {
        self.counted_level_top(FIELDS[field as usize].top)
    }

    /// The same for a place whose top level is `top` (a vault's level).
    pub fn counted_level_top(&self, top: u8) -> u8 {
        self.class_level.min(top + CEILING_ABOVE_TOP).max(1)
    }

    /// The six stats after race, points and gear, under the field's ceiling: points scale with the
    /// counted level, gear above the ceiling scales down by line points.
    pub fn stats(&self, field: u8) -> [u16; 6] {
        self.stats_top(FIELDS[field as usize].top)
    }

    pub fn stats_top(&self, top: u8) -> [u16; 6] {
        let lvl = self.counted_level_top(top);
        let race = &RACES[self.race as usize % RACES.len()];
        let spent = (self.class_level as u32).saturating_sub(1).max(1);
        let counted = (lvl as u32).saturating_sub(1);
        let gl = self.gear_level.min(lvl);
        let (gnum, gden) = (line_points(gl), line_points(self.gear_level.max(1)));
        let mut out = [0u16; 6];
        for s in 0..6 {
            let p = self.points[s] as u32 * counted / spent;
            let g = self.gear[s] as u32 * gnum / gden;
            out[s] = (race.stats[s] as u32 + p + g).min(u16::MAX as u32) as u16;
        }
        out
    }

    /// The weapon's item level the field counts.
    pub fn weapon_level(&self, field: u8) -> u8 {
        self.weapon_level_top(FIELDS[field as usize].top)
    }

    pub fn weapon_level_top(&self, top: u8) -> u8 {
        self.gear_level.min(self.counted_level_top(top)).max(1)
    }
}

/// Cards a hero owns at a class level without pages: the first 12, and one more per even level to 24.
pub fn owned_cards(class_level: u8) -> u8 {
    NOVICE_CARDS + class_level.min(CARD_LEVEL_TOP) / CARD_LEVEL_STEP
}

/// What lasts one outing. `Outing::new()` is a fresh entry; `Field::outing` takes one out so a hero
/// moved to another copy of the field arrives as she left.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Outing {
    /// None: full health.
    pub health: Option<u32>,
    pub level: u16,
    pub xp: u32,
    /// Copies picked of each card (index = card id).
    pub copies: [u8; NCARDS + 1],
    /// Offers waiting for a pick, oldest first.
    pub offers: Vec<[u8; DRAW_MAX as usize]>,
    /// Draws earned but not yet rolled (the queue was full).
    pub owed: u16,
    /// Draws rolled so far (the stream position).
    pub draws: u32,
    pub coin: u32,
    /// Ticks left on skill 1, skill 2, the ultimate.
    pub cooldowns: [u32; 3],
    /// None: filled from the sheet.
    pub belt: Option<[(u8, u8); BELT]>,
    pub belt_rest: [u16; BELT],
    pub phoenix_used: bool,
    pub fx: [u16; NFX],
    pub waystone: u8,
    pub marked: bool,
    /// Ticks since she last struck a hero (`NEVER`).
    pub struck_ago: u32,
    /// Contribution so far to the running tide and to the running boss (rules 8), carried between copies.
    pub tide_contrib: u32,
    pub boss_contrib: u32,
    /// Shrines touched this outing (rules 6, quiet zones), one bit each: each gives its draw once.
    pub shrines: u8,
}

impl Outing {
    pub fn new() -> Outing {
        Outing {
            health: None,
            level: 1,
            xp: 0,
            copies: [0; NCARDS + 1],
            offers: Vec::new(),
            owed: 0,
            draws: 0,
            coin: 0,
            cooldowns: [0; 3],
            belt: None,
            belt_rest: [0; BELT],
            phoenix_used: false,
            fx: [0; NFX],
            waystone: NO_WAYSTONE,
            marked: false,
            struck_ago: NEVER,
            tide_contrib: 0,
            boss_contrib: 0,
            shrines: 0,
        }
    }
}

impl Default for Outing {
    fn default() -> Self {
        Outing::new()
    }
}
