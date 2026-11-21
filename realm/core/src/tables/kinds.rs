//! The 42 monster kinds (rules section 4) and the numbers of the 14 behaviours.

use super::secs;

/// Behaviour bits: a kind may carry several ("brute, splitter").
pub type Beh = u16;
pub const WALKER: Beh = 1 << 0;
pub const SWARM: Beh = 1 << 1;
pub const RUNNER: Beh = 1 << 2;
pub const BRUTE: Beh = 1 << 3;
pub const SHIELDED: Beh = 1 << 4;
pub const BURSTER: Beh = 1 << 5;
pub const SPLITTER: Beh = 1 << 6;
pub const SPITTER: Beh = 1 << 7;
pub const LOBBER: Beh = 1 << 8;
pub const LEAPER: Beh = 1 << 9;
pub const HOWLER: Beh = 1 << 10;
pub const MENDER: Beh = 1 << 11;
pub const WAILER: Beh = 1 << 12;
pub const DRAINER: Beh = 1 << 13;
pub const BEHAVIOURS: usize = 14;

/// No kind (a splitter's child when it is not one).
pub const NO_KIND: u8 = u8::MAX;

#[derive(Clone, Copy, Debug)]
pub struct Kind {
    pub name: &'static str,
    /// Field id 0..5.
    pub field: u8,
    pub beh: Beh,
    /// px per second.
    pub speed: u32,
    pub health: u32,
    /// Contact damage per hit (every `CONTACT_EVERY` ticks).
    pub damage: u32,
    pub xp: u32,
    /// Born in clutches of this many.
    pub clutch: u8,
    /// Contact hits per cadence (2: "hits twice as often").
    pub hits: u8,
    /// A splitter's smaller kind.
    pub split: u8,
    /// Spawn weight within its field.
    pub weight: u32,
}

const fn k(name: &'static str, field: u8, beh: Beh, speed: u32, health: u32, damage: u32, xp: u32) -> Kind {
    let clutch = if beh & SWARM != 0 { SWARM_CLUTCH } else { 1 };
    let weight = if beh & BRUTE != 0 {
        WEIGHT_BRUTE
    } else if beh & SWARM != 0 {
        WEIGHT_SWARM
    } else {
        WEIGHT_BASE
    };
    Kind { name, field, beh, speed, health, damage, xp, clutch, hits: 1, split: NO_KIND, weight }
}
const fn clutch(mut kd: Kind, n: u8) -> Kind {
    kd.clutch = n;
    kd.weight = WEIGHT_CLUTCH;
    kd
}
const fn split(mut kd: Kind, into: u8) -> Kind {
    kd.split = into;
    kd
}
const fn twice(mut kd: Kind) -> Kind {
    kd.hits = 2;
    kd
}

pub const SWARM_CLUTCH: u8 = 8;
pub const WEIGHT_BASE: u32 = 4;
pub const WEIGHT_SWARM: u32 = 1;
pub const WEIGHT_CLUTCH: u32 = 2;
pub const WEIGHT_BRUTE: u32 = 1;

// Kind ids of the splitters' children.
pub const HANGED_MAN: u8 = 6;
pub const DROWNED: u8 = 13;
pub const CINDERLING: u8 = 28;
pub const ASH_LEGIONARY: u8 = 35;

pub const KINDS: [Kind; 42] = [
    // 0 THE FOOL'S ROAD
    k("plague rat", 0, SWARM, 55, 18, 3, 1),
    k("carrion crow", 0, RUNNER, 70, 22, 4, 1),
    k("scarecrow", 0, WALKER, 40, 45, 6, 2),
    k("bloated pilgrim", 0, BURSTER, 30, 60, 6, 3),
    k("penitent", 0, SPITTER, 40, 35, 5, 2),
    k("gravedigger", 0, BRUTE, 25, 140, 10, 5),
    // 6 THE HANGED WOOD
    k("hanged man", 1, WALKER, 40, 50, 7, 2),
    k("noose spider", 1, LEAPER, 60, 30, 6, 2),
    clutch(k("wood wolf", 1, RUNNER, 75, 30, 6, 2), 4),
    k("wisp", 1, BURSTER, 65, 15, 8, 1),
    k("wood witch", 1, LOBBER, 35, 40, 9, 3),
    k("bark wight", 1, SHIELDED, 35, 90, 8, 4),
    split(k("lumberer", 1, BRUTE | SPLITTER, 22, 180, 12, 6), HANGED_MAN),
    // 13 THE MOON MARSH
    k("drowned", 2, WALKER, 45, 55, 7, 2),
    k("leech", 2, SWARM | DRAINER, 60, 16, 3, 1),
    k("eel knight", 2, RUNNER, 80, 45, 8, 3),
    k("marsh light", 2, WAILER, 50, 30, 4, 2),
    k("toadstone", 2, LOBBER, 30, 60, 10, 3),
    k("bog hag", 2, MENDER, 35, 70, 6, 4),
    split(k("corpse barge", 2, BRUTE | SPLITTER, 20, 220, 12, 7), DROWNED),
    // 20 THE HERMIT'S PEAKS
    k("goat cultist", 3, WALKER, 45, 55, 8, 2),
    k("flagellant", 3, RUNNER, 85, 25, 11, 2),
    k("rune carver", 3, SPITTER, 40, 45, 8, 3),
    k("cliff harpy", 3, LEAPER, 70, 35, 8, 3),
    k("bone piper", 3, HOWLER, 40, 60, 5, 4),
    k("frost revenant", 3, WAILER, 40, 80, 8, 4),
    k("stone anchorite", 3, BRUTE | SHIELDED, 20, 240, 13, 7),
    // 27 THE TOWER
    k("shard", 4, WALKER, 50, 25, 4, 1),
    k("cinderling", 4, SWARM, 55, 20, 4, 1),
    k("hound", 4, RUNNER, 70, 30, 6, 2),
    k("bloat", 4, BURSTER, 30, 60, 6, 3),
    k("censor", 4, SPITTER, 40, 40, 5, 2),
    k("guard", 4, SHIELDED, 35, 80, 8, 4),
    twice(k("swords", 4, WALKER, 45, 50, 7, 3)),
    split(k("coffin", 4, BRUTE | SPLITTER, 20, 120, 10, 5), CINDERLING),
    // 35 THE WORLD'S EDGE
    k("ash legionary", 5, SHIELDED, 45, 90, 9, 4),
    clutch(k("pit hound", 5, RUNNER, 90, 35, 8, 2), 4),
    k("hollow angel", 5, LEAPER, 70, 50, 10, 4),
    k("void eye", 5, SPITTER, 40, 45, 10, 3),
    k("blood priest", 5, HOWLER | MENDER, 40, 70, 6, 5),
    k("flesh choir", 5, WAILER | DRAINER, 35, 110, 8, 5),
    split(k("the unmade", 5, BRUTE | SPLITTER, 22, 260, 14, 8), ASH_LEGIONARY),
];

// ---- monster levels, ranks and contact
/// Health x (100 + 18 x (level - 1))%; damage, XP and coin x (100 + 12 x (level - 1))%.
pub const HEALTH_PCT_PER_LEVEL: u32 = 18;
pub const POWER_PCT_PER_LEVEL: u32 = 12;
pub const ELITE_ONE_IN: u64 = 50;
pub const ELITE_HEALTH_MUL: u32 = 4;
pub const ELITE_XP_MUL: u32 = 3;
pub const CHAMPION_ONE_IN: u64 = 2_000;
pub const CHAMPION_HEART_ONE_IN: u64 = 800;
pub const CHAMPION_HEALTH_MUL: u32 = 25;
pub const CHAMPION_DAMAGE_MUL: u32 = 2;
pub const CHAMPION_XP_MUL: u32 = 20;
/// Contact: within 20 px, every 10 ticks.
pub const CONTACT_PX: i32 = 20;
pub const CONTACT_EVERY: u32 = 10;
/// A monster this close to its target stops.
pub const STOP_PX: i32 = 14;
/// Inside two cells a monster walks straight at the hero with the highest threat / distance.
pub const CLOSE_CELLS: u32 = 2;

// ---- behaviours
pub const RUNNER_NEAR_PX: i32 = 160;
pub const RUNNER_SPRINT_TICKS: u8 = secs(1) as u8;
pub const RUNNER_REST_TICKS: u8 = secs(2) as u8;
pub const RUNNER_SPEED_PCT: u32 = 200;
pub const SHIELD_FRONT_TAKEN_PCT: u32 = 70;
pub const BURST_PX: i32 = 40;
pub const BURST_DAMAGE_MUL: u32 = 2;
pub const BURST_DELAY: u16 = 10;
pub const SPLIT_INTO: u32 = 4;
pub const SPITTER_STOP_PX: i32 = 150;
pub const SPIT_SPEED_PX_S: i32 = 90;
pub const SPIT_LIFE: u16 = secs(3) as u16;
pub const SPIT_EVERY: u8 = secs(2) as u8;
/// A monster bolt hits a hero this close to it.
pub const SPIT_HIT_PX: i32 = 12;
pub const LOBBER_STOP_PX: i32 = 250;
pub const LOB_PX: i32 = 50;
pub const LOB_DELAY: u16 = secs(1) as u16;
pub const LOB_EVERY: u8 = secs(3) as u8;
pub const LEAP_NEAR_PX: i32 = 200;
pub const LEAP_EVERY: u8 = secs(5) as u8;
pub const HOWL_PX: i32 = 100;
pub const HOWL_SPEED_PCT: u32 = 120;
pub const MEND_PX: i32 = 100;
pub const MEND_EVERY: u32 = secs(2);
pub const MEND_PCT: u32 = 4;
pub const WAIL_PX: i32 = 80;
pub const WAIL_MOVE_PCT: i32 = -20;
/// Monster bolts and lobbed circles share one pool.
pub const SHOT_POOL: usize = 4_096;

// ---- monster effects (three small timers)
pub const SLOW_SPEED_PCT: u32 = 50;
/// Cursed monsters take 15% more from everyone (the HEXER's passive).
pub const CURSE_TAKEN_PCT: u32 = 115;
pub const CURSE_SPREAD_PX: i32 = 60;
