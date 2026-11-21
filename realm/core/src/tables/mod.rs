//! Every number of the rules, as table rows and named constants. Content is data: a field, kind, class,
//! skill, job, card or potion is a row over the shapes and behaviours the core implements once.

pub mod cards;
pub mod classes;
pub mod fields;
pub mod kinds;

pub use cards::*;
pub use classes::*;
pub use fields::*;
pub use kinds::*;

pub const TICK_HZ: u32 = 20;

/// Seconds to ticks.
pub const fn secs(s: u32) -> u32 {
    s * TICK_HZ
}

// ---- the six stats
pub const MIGHT: usize = 0;
pub const FOCUS: usize = 1;
pub const SWIFT: usize = 2;
pub const VIGOR: usize = 3;
pub const WARD: usize = 4;
pub const FORTUNE: usize = 5;
pub const STAT_NAMES: [&str; 6] = ["MIGHT", "FOCUS", "SWIFT", "VIGOR", "WARD", "FORTUNE"];
/// Per point: MIGHT +2% damage, FOCUS +1% attack speed, SWIFT +1% move, VIGOR +2% health, WARD 1% less
/// damage taken, FORTUNE +3% coin and +1 luck.
pub const MIGHT_PCT: i32 = 2;
pub const FOCUS_PCT: i32 = 1;
pub const SWIFT_PCT: i32 = 1;
pub const VIGOR_PCT: u32 = 2;
pub const WARD_PCT: i32 = 1;
pub const FORTUNE_COIN_PCT: u32 = 3;
pub const FORTUNE_LUCK: i32 = 1;

#[derive(Clone, Copy, Debug)]
pub struct Race {
    pub name: &'static str,
    pub stats: [u16; 6],
    pub class_xp_pct: u32,
    pub pushed_pct: u32,
    /// +`low_dmg_pct` damage under `low_under`% health.
    pub low_dmg_pct: i32,
    pub low_under: u32,
}

pub const HUMAN: u8 = 0;
pub const ELF: u8 = 1;
pub const DWARF: u8 = 2;
pub const ORC: u8 = 3;
pub const RACES: [Race; 4] = [
    Race { name: "HUMAN", stats: [1, 1, 1, 1, 1, 1], class_xp_pct: 105, pushed_pct: 100, low_dmg_pct: 0, low_under: 0 },
    Race { name: "ELF", stats: [0, 3, 4, 0, 0, 0], class_xp_pct: 100, pushed_pct: 100, low_dmg_pct: 0, low_under: 0 },
    Race { name: "DWARF", stats: [0, 0, 0, 4, 3, 0], class_xp_pct: 100, pushed_pct: 50, low_dmg_pct: 0, low_under: 0 },
    Race { name: "ORC", stats: [5, 0, 0, 2, 0, 0], class_xp_pct: 100, pushed_pct: 100, low_dmg_pct: 10, low_under: 30 },
];

// ---- class levels
pub const CLASS_LEVEL_MAX: u8 = 60;
/// A field counts a hero at most its top level + 2.
pub const CEILING_ABOVE_TOP: u8 = 2;
/// A monster more than 10 levels below a hero's class level pays her no class XP.
pub const CLASS_XP_LEVELS_BELOW: u8 = 10;
/// Class XP from level L to L + 1 (index L - 1). Targets to tune with bots: level 10 after about 25
/// minutes of field play, 20 after 4 hours, 40 after 25 hours, 60 after 80 hours (see rules_built.md).
pub const CLASS_XP: [u32; 59] = [
    450, 640, 850, 1_080, 1_330, 1_600, 1_890, 2_200, 2_530, // 1..9
    5_570, 6_440, 7_360, 8_330, 9_350, 10_420, 11_540, 12_710, 13_930, 15_200, // 10..19
    10_280, 10_830, 11_390, 11_960, 12_540, 13_130, 13_730, 14_340, 14_960, 15_590, // 20..29
    16_230, 16_880, 17_540, 18_210, 18_890, 19_580, 20_280, 20_990, 21_710, 22_440, // 30..39
    23_400, 23_950, 24_510, 25_080, 25_660, 26_250, 26_850, 27_460, 28_080, 28_710, // 40..49
    29_350, 30_000, 30_660, 31_330, 32_010, 32_700, 33_400, 34_110, 34_830, 35_560, // 50..59
];

// ---- the haul, falling, rising
pub const WAYSTONE_PX: i32 = 48;
pub const BANK_HOLD: u16 = secs(3) as u16;
/// The gate banks and leaves when she walks into it.
pub const GATE_PX: i32 = 48;
pub const DOWNED_TICKS: u16 = secs(15) as u16;
pub const RAISE_PX: i32 = 40;
/// Raise progress needed: 2 s at 100% speed.
pub const RAISE_NEED: u32 = secs(2) * 100;
pub const RISE_HEALTH_PCT: u32 = 30;
/// Active: dealt damage, healed or was hit in the last 10 seconds.
pub const ACTIVE_TICKS: u32 = secs(10);
pub const XP_SHARE_PX: i32 = 200;
/// No waystone yet.
pub const NO_WAYSTONE: u8 = u8::MAX;
/// The last-struck tick when she never struck a hero (section 14).
pub const NEVER: u32 = u32::MAX;
