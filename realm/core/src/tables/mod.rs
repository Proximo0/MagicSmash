//! Every number of the rules, as table rows and named constants. Content is data: a field, kind, class,
//! skill, job, card or potion is a row over the shapes and behaviours the core implements once.

pub mod cards;
pub mod classes;
pub mod fields;
pub mod kinds;
pub mod realm;

pub use cards::*;
pub use classes::*;
pub use fields::*;
pub use kinds::*;
pub use realm::*;

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
/// Class XP from level L to L + 1 (index L - 1). Fitted by job B1 (`docs/realm/balance.md`, `realm-loadtest
/// balance fit`) to the class XP an hour bot careers earn at each level, so that the median career reaches level 10
/// after 25 minutes of field play, 20 after 4 hours, 40 after 25 and 60 after 80 (rules 2). The steps follow the
/// fields: a field that pays more an hour (THE HERMIT'S PEAKS, THE WORLD'S EDGE) asks more a level.
pub const CLASS_XP: [u32; 59] = [
    14, 26, 36, 44, 52, 76, 110, 156, 219, // 1..9
    10_300, 12_600, 15_200, 18_100, 21_300, 24_800, 26_600, 28_500, 36_100, 45_400, // 10..19
    69_200, 79_100, 90_100, 102_000, 116_000, 131_000, 139_000, 148_000, 157_000, 166_000, // 20..29
    322_000, 339_000, 357_000, 375_000, 394_000, 413_000, 484_000, 571_000, 673_000, 791_000, // 30..39
    897_000, 939_000, 982_000, 1_030_000, 1_070_000, 1_200_000, 1_290_000, 1_390_000, 1_500_000, 1_610_000, // 40..49
    2_440_000, 2_600_000, 2_760_000, 2_920_000, 3_100_000, 3_280_000, 4_160_000, 5_280_000, 6_690_000, 8_470_000, // 50..59
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
