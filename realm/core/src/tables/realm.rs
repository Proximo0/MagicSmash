//! Tides, altars, bosses, the world boss and vaults (rules sections 8, 10, 11): the schedule, the numbers and
//! one row per boss and per vault. Content is data: a boss is a row over eight attack shapes.

use super::secs;

// ---- the clock (rules 8): ticks of the realm's clock, which every copy of a field shares
pub const TIDE_EVERY: u32 = secs(30 * 60);
pub const TIDE_LEN: u32 = secs(5 * 60);
/// The first tide of THE FOOL'S ROAD is this far into the clock, and each field's tide `TIDE_STAGGER` later,
/// so the six countdowns differ and a new realm is quiet for its first ten minutes.
pub const TIDE_FIRST: u32 = secs(10 * 60);
pub const TIDE_STAGGER: u32 = secs(3 * 60);
/// A tide makes monsters this much faster (percent), and the target count double.
pub const TIDE_SPEED_PCT: u32 = 120;
pub const TIDE_TARGET_MUL: u32 = 2;
/// The doubling grows with the heroes up in the field (job B1, from the party gate): x1 (percent 100) at
/// `TIDE_FULL_FROM` heroes or fewer, x`TIDE_TARGET_MUL` at `TIDE_FULL_AT` or more, linear between. A small
/// party is not met by twice the horde its own density brings; a field with a crowd meets the contract's double.
pub const TIDE_FULL_FROM: u32 = 4;
pub const TIDE_FULL_AT: u32 = 40;

/// The tide's target in percent of the field's for `heroes` up.
pub const fn tide_target_pct(heroes: u32) -> u32 {
    let full = (TIDE_TARGET_MUL - 1) * 100;
    if heroes <= TIDE_FULL_FROM {
        100
    } else if heroes >= TIDE_FULL_AT {
        100 + full
    } else {
        100 + full * (heroes - TIDE_FULL_FROM) / (TIDE_FULL_AT - TIDE_FULL_FROM)
    }
}
/// After a LOST tide the horde stays quick this long.
pub const TIDE_LOST_QUICK: u32 = secs(120);
/// Three altars of the six light, chosen by the field's seed.
pub const ALTARS_LIT: usize = 3;
pub const ALTARS_TO_WIN: u8 = 2;
/// Hero-seconds to hold an altar are `60 x factor`; the factor is `max(1, heroes / 20)`.
pub const ALTAR_HOLD_SECS: u32 = 60;
pub const ALTAR_HOLD_PX: i32 = 150;
pub const ALTAR_HEALTH: u32 = 8_000;
pub const ALTAR_STRIKE_PX: i32 = 60;
pub const ALTAR_FACTOR_HEROES: u32 = 20;
/// Contribution counts this percent of each hit that came at a hero, before her own reductions (rules 8 say half of
/// damage taken; job B1 counts the hit drawn, so a tank's mitigation does not cut her share).
pub const CONTRIB_DRAWN_PCT: u32 = 50;
/// The contribution floor of a tide is `40 x factor`.
pub const TIDE_FLOOR: u32 = 40;
/// A hero who has not moved for this long earns no contribution ("standing still earns nothing").
pub const STILL_TICKS: u16 = secs(10) as u16;
/// Altar state in the ALTAR event.
pub const ALTAR_LIT: u8 = 0;
pub const ALTAR_HELD: u8 = 1;
pub const ALTAR_RUINED: u8 = 2;
pub const ALTAR_OUT: u8 = 3;
/// Tide state in the TIDE event.
pub const TIDE_BEGIN: u8 = 0;
pub const TIDE_WON: u8 = 1;
pub const TIDE_LOST: u8 = 2;

// ---- field bosses (rules 8)
/// A boss rises `BOSS_RISE_AFTER` after the end of every fourth tide, and leaves `BOSS_STAY` later.
pub const BOSS_EVERY_TIDES: u32 = 4;
pub const BOSS_RISE_AFTER: u32 = secs(30);
pub const BOSS_STAY: u32 = secs(8 * 60);
/// Announced in town this long before it rises.
pub const BOSS_ANNOUNCE: u32 = secs(10 * 60);
pub const BOSS_HEALTH_BASE: u32 = 40_000;
pub const BOSS_HEALTH_PER_HERO: u32 = 6_000;
pub const BOSS_HEART_COUNTED: u32 = 600;
pub const BOSS_WON_HEALTH_PCT: u32 = 80;
pub const BOSS_LOST_DAMAGE_PCT: u32 = 120;
/// The floor of a boss is a fifth of a percent (2 per mille) of its health.
pub const BOSS_FLOOR_MILLE: u32 = 2;
/// A boss kill pays its carrier kind's XP this many times.
pub const BOSS_XP_MUL: u32 = 400;
/// Boss state in the BOSS event.
pub const BOSS_RISES: u8 = 0;
pub const BOSS_PHASE: u8 = 1;
pub const BOSS_KILLED: u8 = 2;
pub const BOSS_LEFT: u8 = 3;
/// Health percent at which a boss enters phase 1 and 2.
pub const BOSS_PHASES: [u32; 2] = [66, 33];
/// Each phase shortens the rest between casts by this much (percent of the row's rest).
pub const PHASE_HASTE_PCT: u32 = 20;
/// Boss damage is a share of the target's health, in per mille, so a slam is a threat at every level.
pub const BOSS_STOP_PX: i32 = 40;

// ---- the world boss
pub const WORLD_EVERY: u32 = secs(6 * 3600);
pub const WORLD_STAY: u32 = secs(15 * 60);
pub const WORLD_ANNOUNCE: u32 = secs(30 * 60);
/// It arrives this long after the start of the field's tide of that half hour, which puts it between the
/// field's boss (gone thirteen and a half minutes after the tide began) and its next tide.
pub const WORLD_AFTER_TIDE: u32 = secs(14 * 60);
pub const WORLD_HEALTH_MUL: u32 = 10;
pub const WORLD_RELIC_HEROES: usize = 100;

// ---- rewards: the REWARD event's kinds
pub const R_TIDE_CACHE: u8 = 0;
pub const R_BOSS_CHEST: u8 = 1;
pub const R_WORLD_RELIC: u8 = 2;
pub const R_WORLD_EPIC: u8 = 3;
pub const R_VAULT_CHEST: u8 = 4;
/// A lost vault: coin for the minutes survived (the "contribution" of each hero is her coin).
pub const R_VAULT_LOSS: u8 = 5;
/// Coin at power level 1 (it grows `POWER_PCT_PER_LEVEL` a level of the field's top level).
pub const COIN_TIDE_CACHE: u32 = 150;
pub const COIN_BOSS_CHEST: u32 = 800;
pub const COIN_WORLD_RELIC: u32 = 4_000;
pub const COIN_WORLD_EPIC: u32 = 1_500;
pub const COIN_VAULT_CHEST: u32 = 1_200;
pub const COIN_VAULT_PER_MINUTE: u32 = 60;
/// Item rolls and the class of the roll, for the server (the contract's chests).
pub const ROLLS_TIDE_CACHE: u8 = 3;
pub const ROLLS_BOSS_CHEST: u8 = 2;
pub const ROLLS_VAULT_CHEST: u8 = 2;

// ---- the eight attack shapes
pub const A_SLAM: u8 = 0;
pub const A_CANDLES: u8 = 1;
pub const A_SWEEP: u8 = 2;
pub const A_LANES: u8 = 3;
pub const A_CALL: u8 = 4;
pub const A_MIRE: u8 = 5;
pub const A_PULL: u8 = 6;
pub const A_WALL: u8 = 7;
pub const ATTACK_SHAPES: usize = 8;
pub const ATTACK_NAMES: [&str; ATTACK_SHAPES] = ["slam", "candles", "sweep", "lanes", "call", "mire", "pull", "wall"];

/// No chained attack.
pub const NO_NEXT: u8 = u8::MAX;
/// A call of the field's own kinds, by weight (the world boss).
pub const CALL_FIELD_KINDS: u8 = u8::MAX;

/// One attack of a boss. Which fields mean what depends on the shape:
/// - `px`: slam radius; candle radius; sweep length; lane half-width; mire radius; pull reach; wall start radius.
/// - `count`: candles (circles); sweeps (beams, turning opposite ways in turn); lane rides; mire zones;
///   monsters called; (the others ignore it).
/// - `reach`: how far from the boss a hero may be to be picked by candles and mire; lane length; wall band.
/// - `dmg`: per mille of the target's health, per hit.
/// - `warn`: ticks the shape is drawn before it lands; for a sweep, lane or wall also its `dur`.
#[derive(Clone, Copy, Debug)]
pub struct Atk {
    pub shape: u8,
    pub warn: u16,
    pub dur: u16,
    pub dmg: u16,
    pub px: i32,
    pub reach: i32,
    pub count: u16,
    /// A call: the kind, and a second kind with `count2`.
    pub kind: u8,
    pub kind2: u8,
    pub count2: u16,
    /// The attack is used from this phase on (0, 1 or 2).
    pub phase: u8,
    /// Another attack of the same boss that starts the moment this one lands.
    pub then: u8,
}

const fn atk(shape: u8, warn: u16, dmg: u16, px: i32) -> Atk {
    Atk { shape, warn, dur: 0, dmg, px, reach: 0, count: 1, kind: NO_NEXT, kind2: NO_NEXT, count2: 0, phase: 0, then: NO_NEXT }
}
const fn dur(mut a: Atk, d: u16) -> Atk {
    a.dur = d;
    a
}
const fn reach(mut a: Atk, r: i32) -> Atk {
    a.reach = r;
    a
}
const fn count(mut a: Atk, n: u16) -> Atk {
    a.count = n;
    a
}
const fn from_phase(mut a: Atk, p: u8) -> Atk {
    a.phase = p;
    a
}
const fn then(mut a: Atk, next: u8) -> Atk {
    a.then = next;
    a
}
const fn call(mut a: Atk, kind: u8, n: u16) -> Atk {
    a.kind = kind;
    a.count = n;
    a
}
const fn call2(mut a: Atk, kind: u8, n: u16) -> Atk {
    a.kind2 = kind;
    a.count2 = n;
    a
}

/// Boss tiers (the server's loot rolls read these).
pub const TIER_FIELD: u8 = 0;
pub const TIER_FINAL: u8 = 1;
pub const TIER_WORLD: u8 = 2;
pub const TIER_ACT: u8 = 3;
pub const TIER_ARCHLICH: u8 = 4;
pub const TIER_TRIAL: u8 = 5;
/// The world boss rides in any field.
pub const ANY_FIELD: u8 = u8::MAX;
/// A vault row's boss slot with no boss.
pub const NO_MINUTE: u8 = u8::MAX;

#[derive(Clone, Copy, Debug)]
pub struct BossRow {
    pub name: &'static str,
    /// The field it rises in (`ANY_FIELD` for the world boss and the vault bosses).
    pub field: u8,
    pub tier: u8,
    /// The monster kind it is drawn as and born from (a table row it borrows its look and name slot from).
    pub carrier: u8,
    /// Walking speed px/s (0: rooted).
    pub speed: u32,
    /// Ticks of rest between casts at phase 0.
    pub rest: u16,
    /// Phase from which it casts two attacks at once.
    pub twice_from: u8,
    /// Percent of the damage it deals that it heals itself (MOTHER OF LEECHES is a drainer).
    pub drain_pct: u32,
    /// Health that this row multiplies the formula by, percent.
    pub health_pct: u32,
    pub attacks: &'static [Atk],
}

pub const B_HARVESTER: u8 = 0;
pub const B_HANGING_TREE: u8 = 1;
pub const B_MOTHER: u8 = 2;
pub const B_GOAT_PROPHET: u8 = 3;
pub const B_CHANDELIER: u8 = 4;
pub const B_GHOSTWRITER: u8 = 5;
pub const B_UNMADE_KING: u8 = 6;
pub const B_DEATH: u8 = 7;
pub const B_WARDEN: u8 = 8;
pub const B_REGENT: u8 = 9;
pub const B_ARCHLICH: u8 = 10;
pub const B_TRIAL: u8 = 11;

// Carrier kinds (ids in `KINDS`).
const K_CROW: u8 = 1;
const K_GRAVEDIGGER: u8 = 5;
const K_HANGED_MAN: u8 = 6;
const K_LUMBERER: u8 = 12;
const K_LEECH: u8 = 14;
const K_CORPSE_BARGE: u8 = 19;
const K_GOAT_CULTIST: u8 = 20;
const K_BONE_PIPER: u8 = 24;
const K_ANCHORITE: u8 = 26;
const K_CENSOR: u8 = 31;
const K_GUARD: u8 = 32;
const K_CINDERLING: u8 = 28;
const K_THE_UNMADE: u8 = 41;
const K_SWORDS: u8 = 33;
const K_COFFIN: u8 = 34;

/// Attacks of each boss. The first attack in the list that is allowed in the phase goes first and they
/// are cast in turn.
const HARVESTER: [Atk; 3] = [dur(count(atk(A_SWEEP, 40, 160, 220), 1), 120), call(atk(A_CALL, 30, 0, 0), K_CROW, 30), from_phase(atk(A_SLAM, 30, 450, 160), 1)];
const HANGING_TREE: [Atk; 3] = [then(atk(A_PULL, 30, 0, 300), 1), atk(A_SLAM, 20, 500, 200), call(atk(A_CALL, 30, 0, 0), K_HANGED_MAN, 20)];
const HANGING_TREE_CANDLES: Atk = reach(count(atk(A_CANDLES, 40, 300, 50), 8), 600);
const MOTHER: [Atk; 3] = [reach(count(dur(atk(A_MIRE, 30, 0, 90), 200), 6), 500), call(atk(A_CALL, 30, 0, 0), K_LEECH, 60), atk(A_SLAM, 30, 400, 150)];
const GOAT_PROPHET: [Atk; 3] = [
    dur(count(atk(A_SWEEP, 40, 150, 260), 2), 140),
    reach(count(atk(A_CANDLES, 40, 350, 60), 8), 700),
    call2(call(atk(A_CALL, 30, 0, 0), K_GOAT_CULTIST, 12), K_BONE_PIPER, 1),
];
const CHANDELIER: [Atk; 3] = [atk(A_SLAM, 30, 450, 180), reach(count(atk(A_CANDLES, 40, 300, 60), 12), 700), call(atk(A_CALL, 30, 0, 0), K_CINDERLING, 40)];
const GHOSTWRITER: [Atk; 3] = [
    reach(count(dur(atk(A_LANES, 40, 450, 40), 0), 2), 1100),
    reach(count(atk(A_CANDLES, 40, 300, 60), 10), 700),
    reach(dur(atk(A_WALL, 40, 350, 420), 160), 28),
];
const UNMADE_KING: [Atk; 8] = [
    dur(count(atk(A_SWEEP, 40, 160, 240), 2), 140),
    call(atk(A_CALL, 30, 0, 0), K_THE_UNMADE, 8),
    atk(A_SLAM, 30, 500, 200),
    then(atk(A_PULL, 30, 0, 320), 2),
    reach(count(atk(A_CANDLES, 40, 320, 60), 10), 700),
    reach(count(dur(atk(A_MIRE, 30, 0, 90), 200), 6), 500),
    from_phase(reach(dur(count(atk(A_LANES, 40, 500, 44), 2), 0), 1400), 1),
    reach(dur(atk(A_WALL, 40, 400, 460), 160), 28),
];
const DEATH: [Atk; 3] =
    [reach(count(atk(A_LANES, 50, 550, 60), 3), 5000), call(atk(A_CALL, 40, 0, 0), CALL_FIELD_KINDS, 300), reach(dur(atk(A_WALL, 50, 450, 700), 200), 40)];
const WARDEN: [Atk; 3] = [atk(A_SLAM, 30, 400, 170), call(atk(A_CALL, 30, 0, 0), K_GOAT_CULTIST, 14), reach(count(atk(A_CANDLES, 40, 280, 60), 6), 600)];
const REGENT: [Atk; 4] = [
    dur(count(atk(A_SWEEP, 40, 150, 240), 2), 140),
    atk(A_SLAM, 30, 450, 190),
    then(atk(A_PULL, 30, 0, 300), 1),
    reach(dur(atk(A_WALL, 40, 350, 420), 160), 28),
];
const ARCHLICH: [Atk; 8] = [
    dur(count(atk(A_SWEEP, 40, 150, 240), 2), 140),
    call(atk(A_CALL, 30, 0, 0), K_GOAT_CULTIST, 20),
    atk(A_SLAM, 30, 500, 190),
    then(atk(A_PULL, 30, 0, 300), 2),
    reach(count(atk(A_CANDLES, 40, 320, 60), 8), 700),
    reach(count(dur(atk(A_MIRE, 30, 0, 90), 200), 5), 500),
    from_phase(reach(dur(count(atk(A_LANES, 40, 500, 44), 2), 0), 1200), 1),
    reach(dur(atk(A_WALL, 40, 400, 420), 160), 28),
];
const TRIAL: [Atk; 2] = [atk(A_SLAM, 40, 300, 150), call(atk(A_CALL, 40, 0, 0), K_SWORDS, 6)];

const fn boss(name: &'static str, field: u8, tier: u8, carrier: u8, speed: u32, rest: u16, attacks: &'static [Atk]) -> BossRow {
    BossRow { name, field, tier, carrier, speed, rest, twice_from: 9, drain_pct: 0, health_pct: 100, attacks }
}
const fn twice(mut b: BossRow, from: u8) -> BossRow {
    b.twice_from = from;
    b
}
const fn drain(mut b: BossRow, pct: u32) -> BossRow {
    b.drain_pct = pct;
    b
}

pub const BOSSES: [BossRow; 12] = [
    boss("THE HARVESTER", 0, TIER_FIELD, K_GRAVEDIGGER, 20, secs(4) as u16, &HARVESTER),
    boss("THE HANGING TREE", 1, TIER_FIELD, K_LUMBERER, 0, secs(4) as u16, &HANGING_TREE_ALL),
    drain(boss("MOTHER OF LEECHES", 2, TIER_FIELD, K_CORPSE_BARGE, 18, secs(4) as u16, &MOTHER), 50),
    boss("THE GOAT PROPHET", 3, TIER_FIELD, K_ANCHORITE, 0, secs(4) as u16, &GOAT_PROPHET),
    boss("THE CHANDELIER", 4, TIER_FIELD, K_GUARD, 0, secs(4) as u16, &CHANDELIER),
    boss("THE GHOSTWRITER", 4, TIER_FIELD, K_CENSOR, 0, secs(3) as u16, &GHOSTWRITER),
    twice(boss("THE UNMADE KING", 5, TIER_FINAL, K_THE_UNMADE, 24, secs(4) as u16, &UNMADE_KING), 1),
    boss("DEATH, THE PALE RIDER", ANY_FIELD, TIER_WORLD, K_THE_UNMADE, 0, secs(4) as u16, &DEATH),
    boss("THE GRAVE WARDEN", ANY_FIELD, TIER_ACT, K_ANCHORITE, 16, secs(4) as u16, &WARDEN),
    boss("THE BONE REGENT", ANY_FIELD, TIER_ACT, K_COFFIN, 16, secs(4) as u16, &REGENT),
    twice(boss("THE ARCHLICH", ANY_FIELD, TIER_ARCHLICH, K_BONE_PIPER, 20, secs(3) as u16, &ARCHLICH), 2),
    boss("THE TRIAL WARDEN", ANY_FIELD, TIER_TRIAL, K_HANGED_MAN, 0, secs(4) as u16, &TRIAL),
];

/// The Hanging Tree casts the pull and the slam in chain (`then`), then candles and its call.
const HANGING_TREE_ALL: [Atk; 4] = [HANGING_TREE[0], HANGING_TREE[1], HANGING_TREE_CANDLES, HANGING_TREE[2]];

/// The boss a field's tide rises: THE TOWER alternates its two bosses; the others have one.
pub fn field_boss_of(field: u8, rise_count: u32) -> u8 {
    match field {
        0 => B_HARVESTER,
        1 => B_HANGING_TREE,
        2 => B_MOTHER,
        3 => B_GOAT_PROPHET,
        4 => {
            if rise_count % 2 == 0 {
                B_CHANDELIER
            } else {
                B_GHOSTWRITER
            }
        }
        _ => B_UNMADE_KING,
    }
}

// ---- vaults (rules 10)
pub const VAULT_ARENA_PX: i32 = 2_048;
pub const VAULT_MINUTES: usize = 15;
pub const VAULT_PARTY_MAX: u8 = 8;
pub const SEALS_MAX: u8 = 8;
/// Every seal: monsters have this much more health and damage (percent), and the chest one more roll.
pub const SEAL_PCT: u32 = 25;
/// Vault state in the VAULT event.
pub const VAULT_START: u8 = 0;
pub const VAULT_ACT: u8 = 1;
pub const VAULT_WON: u8 = 2;
pub const VAULT_LOST: u8 = 3;
/// The ARCHLICH rises at minute 15; the party has this long more to kill her.
pub const VAULT_OVERTIME: u32 = secs(3 * 60);

/// What a minute of a vault's timeline holds: the monsters the field keeps (for a party of eight; fewer
/// heroes, fewer monsters) and a clutch born at the start of the minute (`burst` of the kind at `burst_kind`
/// in the vault's kinds).
#[derive(Clone, Copy, Debug)]
pub struct Minute {
    pub target: u16,
    pub burst: u8,
    pub burst_kind: u8,
}

#[derive(Clone, Copy, Debug)]
pub struct VaultRow {
    pub name: &'static str,
    /// Monster level, and the top level of a hero's ceiling (+2).
    pub level: u8,
    /// Its monsters are `KINDS[first_kind..first_kind + kind_count]`; the field row they come from.
    pub field: u8,
    pub first_kind: u8,
    pub kind_count: u8,
    pub party_max: u8,
    pub minutes: u8,
    pub seals_max: u8,
    /// Bosses: (minute they rise, boss row).
    pub bosses: [(u8, u8); 3],
    /// A vault boss's health: `(base + per_hero x party) x level scale` percent of the field boss formula.
    pub hp_base: u32,
    pub hp_per_hero: u32,
    pub timeline: [Minute; VAULT_MINUTES],
}

/// A timeline that starts at `from` and gains `step` a minute, with a clutch of `burst` every minute.
const fn ramp(from: u16, step: u16, burst: u8) -> [Minute; VAULT_MINUTES] {
    let mut out = [Minute { target: 0, burst: 0, burst_kind: 0 }; VAULT_MINUTES];
    let mut i = 0;
    while i < VAULT_MINUTES {
        out[i] = Minute { target: from + step * i as u16, burst, burst_kind: (i % 3) as u8 };
        i += 1;
    }
    out
}

pub const VAULT_CLASS_TRIAL: u8 = 5;
pub const VAULTS: [VaultRow; 6] = [
    VaultRow {
        name: "THE MIRE CRYPT",
        level: 20,
        field: 2,
        first_kind: 13,
        kind_count: 7,
        party_max: 8,
        minutes: 15,
        seals_max: 8,
        bosses: [(5, B_WARDEN), (10, B_REGENT), (15, B_ARCHLICH)],
        hp_base: 9_000,
        hp_per_hero: 3_000,
        timeline: ramp(160, 16, 12),
    },
    VaultRow {
        name: "THE FROZEN SCRIPTORIUM",
        level: 30,
        field: 3,
        first_kind: 20,
        kind_count: 7,
        party_max: 8,
        minutes: 15,
        seals_max: 8,
        bosses: [(5, B_WARDEN), (10, B_REGENT), (15, B_ARCHLICH)],
        hp_base: 9_000,
        hp_per_hero: 3_000,
        timeline: ramp(170, 17, 12),
    },
    VaultRow {
        name: "THE CINDER LIBRARY",
        level: 40,
        field: 4,
        first_kind: 27,
        kind_count: 8,
        party_max: 8,
        minutes: 15,
        seals_max: 8,
        bosses: [(5, B_WARDEN), (10, B_REGENT), (15, B_ARCHLICH)],
        hp_base: 9_000,
        hp_per_hero: 3_000,
        timeline: ramp(180, 18, 12),
    },
    VaultRow {
        name: "THE ASHEN BASILICA",
        level: 50,
        field: 5,
        first_kind: 35,
        kind_count: 7,
        party_max: 8,
        minutes: 15,
        seals_max: 8,
        bosses: [(5, B_WARDEN), (10, B_REGENT), (15, B_ARCHLICH)],
        hp_base: 9_000,
        hp_per_hero: 3_000,
        timeline: ramp(190, 19, 12),
    },
    VaultRow {
        name: "THE UNMADE VAULT",
        level: 60,
        field: 5,
        first_kind: 27,
        kind_count: 15,
        party_max: 8,
        minutes: 15,
        seals_max: 8,
        bosses: [(5, B_WARDEN), (10, B_REGENT), (15, B_ARCHLICH)],
        hp_base: 9_000,
        hp_per_hero: 3_000,
        timeline: ramp(200, 20, 12),
    },
    VaultRow {
        name: "THE CLASS TRIAL",
        level: 10,
        field: 0,
        first_kind: 0,
        kind_count: 6,
        party_max: 1,
        minutes: 5,
        seals_max: 0,
        bosses: [(3, B_TRIAL), (NO_MINUTE, B_TRIAL), (NO_MINUTE, B_TRIAL)],
        hp_base: 6_000,
        hp_per_hero: 0,
        timeline: ramp(60, 10, 8),
    },
];

/// Seconds before the first act boss etc. are derived from `VaultRow::bosses`; coin for a lost vault is
/// `COIN_VAULT_PER_MINUTE` a minute survived (x the vault level's power).
pub const VAULT_FLOOR_MILLE: u32 = 2;
