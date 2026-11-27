//! Classes, their weapons and skills, the ten jobs, and the hero effects (rules section 3).

use super::secs;

/// The attack shapes the core implements once.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Shape {
    /// A cone toward the nearest monster: width in degrees, radius px.
    Arc { deg: i32, px: i32 },
    /// A circle on the hero.
    Ring { px: i32 },
    /// Flies to the nearest monster in reach; hits `1 + pierce` along its line; may burst; stops at walls.
    Bolt { reach: i32, pierce: u8, burst: i32 },
    /// A circle at the nearest monster in reach, landing after `delay` ticks.
    Drop { reach: i32, px: i32, delay: u16 },
}

#[derive(Clone, Copy, Debug)]
pub struct Weapon {
    pub name: &'static str,
    pub shape: Shape,
    pub damage: u32,
    /// Ticks between attacks.
    pub every: u32,
    pub push_px: i32,
}

#[derive(Clone, Copy, Debug)]
pub struct ClassRow {
    pub name: &'static str,
    pub health: u32,
    pub health_per_level: u32,
    pub weapon: Weapon,
    /// Tenths: 10 is a threat of one.
    pub threat: i32,
    pub skill1: u8,
    pub skill2: u8,
    pub jobs: [u8; 2],
    pub passive: Passive,
}

/// A class's or job's passive as numbers (zero means none). Implemented once in `hero.rs`/`attack.rs`.
#[derive(Clone, Copy, Debug, Default)]
pub struct Passive {
    /// Pushed this percent as far (knight, dwarf: 50).
    pub pushed_pct: u32,
    /// Cards a draw shows (mage: 4).
    pub draw_size: u8,
    pub move_pct: i32,
    /// Raises this percent as fast (priest: 200).
    pub raise_pct: u32,
    /// Allies within `aura_px` take `aura_pct` less (paladin).
    pub aura_pct: u32,
    pub aura_px: i32,
    /// Weapon healing: the most hurt ally within `heal_px` regains `heal_pct` of her health per attack.
    pub heal_pct: u32,
    pub heal_px: i32,
    /// Overrides the class threat (tenths).
    pub threat: i32,
    /// PROVOKE also pulls monsters this far inward.
    pub provoke_pull_px: i32,
    /// +1% damage per this many % health missing (berserker: 2).
    pub dmg_per_missing: u32,
    /// The weapon bolt bursts a second time for this percent.
    pub second_burst_pct: u32,
    /// LONGBOW pierce override.
    pub pierce: u8,
    pub reach_pct: u32,
    /// Extra damage to ELITES, CHAMPIONS and bosses.
    pub elite_pct: u32,
    /// Heals also shield (unhurt) the ally under this % health.
    pub shield_under_pct: u32,
    /// Weapon damage x this percent and its healing x `heal_mul_pct`.
    pub weapon_dmg_mul_pct: u32,
    pub heal_mul_pct: u32,
    /// +`ally_dmg_pct` per ally within `ally_px`, at most `ally_dmg_max`.
    pub ally_dmg_pct: u32,
    pub ally_dmg_max: u32,
    pub ally_px: i32,
}

const NO: Passive = Passive {
    pushed_pct: 0,
    draw_size: 0,
    move_pct: 0,
    raise_pct: 0,
    aura_pct: 0,
    aura_px: 0,
    heal_pct: 0,
    heal_px: 0,
    threat: 0,
    provoke_pull_px: 0,
    dmg_per_missing: 0,
    second_burst_pct: 0,
    pierce: 0,
    reach_pct: 0,
    elite_pct: 0,
    shield_under_pct: 0,
    weapon_dmg_mul_pct: 0,
    heal_mul_pct: 0,
    ally_dmg_pct: 0,
    ally_dmg_max: 0,
    ally_px: 0,
};

pub const NOVICE: u8 = 0;
pub const KNIGHT: u8 = 1;
pub const MAGE: u8 = 2;
pub const ARCHER: u8 = 3;
pub const PRIEST: u8 = 4;
pub const PALADIN: u8 = 5;
/// No skill or job.
pub const NONE: u8 = u8::MAX;

pub const CLASSES: [ClassRow; 6] = [
    ClassRow {
        name: "NOVICE",
        health: 200,
        health_per_level: 20,
        weapon: Weapon { name: "DIRK", shape: Shape::Arc { deg: 90, px: 48 }, damage: 14, every: 12, push_px: 0 },
        threat: 10,
        skill1: S_SECOND_WIND,
        skill2: NONE,
        jobs: [NONE, NONE],
        passive: NO,
    },
    ClassRow {
        name: "KNIGHT",
        health: 360,
        health_per_level: 36,
        weapon: Weapon { name: "CLEAVE", shape: Shape::Arc { deg: 110, px: 72 }, damage: 30, every: 10, push_px: 12 },
        threat: 20,
        skill1: S_PROVOKE,
        skill2: S_CHARGE,
        jobs: [J_WARDEN, J_BERSERKER],
        passive: Passive { pushed_pct: 50, ..NO },
    },
    ClassRow {
        name: "MAGE",
        health: 180,
        health_per_level: 18,
        weapon: Weapon { name: "FIREBALL", shape: Shape::Bolt { reach: 320, pierce: 0, burst: 60 }, damage: 40, every: 16, push_px: 0 },
        threat: 8,
        skill1: S_NOVA,
        skill2: S_METEOR,
        jobs: [J_ARCHMAGE, J_HEXER],
        passive: Passive { draw_size: 4, ..NO },
    },
    ClassRow {
        name: "ARCHER",
        health: 200,
        health_per_level: 20,
        weapon: Weapon { name: "LONGBOW", shape: Shape::Bolt { reach: 400, pierce: 4, burst: 0 }, damage: 40, every: 10, push_px: 0 },
        threat: 8,
        skill1: S_VOLLEY,
        skill2: S_TUMBLE,
        jobs: [J_RANGER, J_SHARPSHOOTER],
        passive: Passive { move_pct: 8, ..NO },
    },
    ClassRow {
        name: "PRIEST",
        health: 220,
        health_per_level: 22,
        weapon: Weapon { name: "HOLY LIGHT", shape: Shape::Ring { px: 96 }, damage: 28, every: 12, push_px: 0 },
        threat: 7,
        skill1: S_SANCTUARY,
        skill2: S_CONSECRATE,
        jobs: [J_ORACLE, J_INQUISITOR],
        passive: Passive { raise_pct: 200, heal_pct: 3, heal_px: 160, ..NO },
    },
    ClassRow {
        name: "PALADIN",
        health: 300,
        health_per_level: 30,
        weapon: Weapon { name: "SMITE", shape: Shape::Drop { reach: 200, px: 60, delay: 6 }, damage: 36, every: 12, push_px: 0 },
        threat: 16,
        skill1: S_AEGIS,
        skill2: S_HAMMERFALL,
        jobs: [J_TEMPLAR, J_CRUSADER],
        passive: Passive { aura_pct: 8, aura_px: 100, ..NO },
    },
];

/// Where a skill or ultimate acts.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Act {
    /// Heals the caster `pct` of her health.
    HealSelf { pct: u32 },
    /// A timed hero effect on the caster.
    SelfEffect { fx: u8 },
    /// A timed hero effect on every ally within `px` (the caster too).
    GroupEffect { px: i32, fx: u8 },
    /// Allies within `px` heal `pct`, and the downed among them rise.
    GroupHeal { px: i32, pct: u32 },
    /// A circle on the hero: damage and stun ticks.
    Ring { px: i32, dmg: u32, stun: u8 },
    /// `count` drops on the thickest cells within `reach`, `every` ticks apart.
    Thick { reach: i32, px: i32, dmg: u32, delay: u16, count: u8, every: u16 },
    /// `n` weapon bolts in a fan of `deg`.
    Volley { n: u8, deg: i32 },
    /// Dash `len` px (toward the nearest monster, or along her movement), damaging and stunning along it,
    /// then leaving a zone row (or `NONE`).
    Dash { len: i32, dmg: u32, stun: u8, along_move: bool, zone: u8 },
    /// A zone row on the hero, or at the thickest cell within `reach` when `reach > 0`.
    Zone { zone: u8, reach: i32 },
    /// Curses monsters within `px` for `ticks`.
    Curse { px: i32, ticks: u8 },
}

#[derive(Clone, Copy, Debug)]
pub struct Skill {
    pub name: &'static str,
    /// Class level it comes at (ranks count from here).
    pub level: u8,
    pub cooldown: u32,
    pub act: Act,
}

pub const S_SECOND_WIND: u8 = 0;
pub const S_PROVOKE: u8 = 1;
pub const S_CHARGE: u8 = 2;
pub const S_NOVA: u8 = 3;
pub const S_METEOR: u8 = 4;
pub const S_VOLLEY: u8 = 5;
pub const S_TUMBLE: u8 = 6;
pub const S_SANCTUARY: u8 = 7;
pub const S_CONSECRATE: u8 = 8;
pub const S_AEGIS: u8 = 9;
pub const S_HAMMERFALL: u8 = 10;
pub const U_RAMPART: u8 = 11;
pub const U_BLOOD_RAGE: u8 = 12;
pub const U_CATACLYSM: u8 = 13;
pub const U_PLAGUE: u8 = 14;
pub const U_HAIL: u8 = 15;
pub const U_DEADEYE: u8 = 16;
pub const U_BENEDICTION: u8 = 17;
pub const U_PYRE: u8 = 18;
pub const U_MARTYR: u8 = 19;
pub const U_CRUSADE: u8 = 20;

pub const SKILL1_LEVEL: u8 = 10;
pub const SKILL2_LEVEL: u8 = 25;
pub const JOB_LEVEL: u8 = 40;
pub const NOVICE_SKILL_LEVEL: u8 = 1;
/// A rank is `1 + (class level - skill level) / 10`, at most 5; each adds 15%.
pub const RANK_LEVELS: u8 = 10;
pub const RANK_MAX: u8 = 5;
pub const RANK_PCT: u32 = 15;

pub const SKILLS: [Skill; 21] = [
    Skill { name: "SECOND WIND", level: NOVICE_SKILL_LEVEL, cooldown: secs(30), act: Act::HealSelf { pct: 30 } },
    Skill { name: "PROVOKE", level: SKILL1_LEVEL, cooldown: secs(20), act: Act::SelfEffect { fx: FX_PROVOKE } },
    Skill { name: "CHARGE", level: SKILL2_LEVEL, cooldown: secs(14), act: Act::Dash { len: 200, dmg: 80, stun: secs(1) as u8, along_move: false, zone: NONE } },
    Skill { name: "NOVA", level: SKILL1_LEVEL, cooldown: secs(25), act: Act::Ring { px: 200, dmg: 160, stun: 0 } },
    Skill { name: "METEOR", level: SKILL2_LEVEL, cooldown: secs(30), act: Act::Thick { reach: 400, px: 140, dmg: 400, delay: 30, count: 1, every: 0 } },
    Skill { name: "VOLLEY", level: SKILL1_LEVEL, cooldown: secs(15), act: Act::Volley { n: 12, deg: 120 } },
    Skill { name: "TUMBLE", level: SKILL2_LEVEL, cooldown: secs(10), act: Act::Dash { len: 120, dmg: 0, stun: 0, along_move: true, zone: Z_TUMBLE } },
    Skill { name: "SANCTUARY", level: SKILL1_LEVEL, cooldown: secs(40), act: Act::GroupHeal { px: 200, pct: 40 } },
    Skill { name: "CONSECRATE", level: SKILL2_LEVEL, cooldown: secs(25), act: Act::Zone { zone: Z_CONSECRATE, reach: 0 } },
    Skill { name: "AEGIS", level: SKILL1_LEVEL, cooldown: secs(45), act: Act::GroupEffect { px: 120, fx: FX_AEGIS } },
    Skill { name: "HAMMERFALL", level: SKILL2_LEVEL, cooldown: secs(18), act: Act::Ring { px: 100, dmg: 120, stun: 30 } },
    Skill { name: "RAMPART", level: JOB_LEVEL, cooldown: secs(90), act: Act::Zone { zone: Z_RAMPART, reach: 0 } },
    Skill { name: "BLOOD RAGE", level: JOB_LEVEL, cooldown: secs(90), act: Act::SelfEffect { fx: FX_BLOOD_RAGE } },
    Skill {
        name: "CATACLYSM",
        level: JOB_LEVEL,
        cooldown: secs(120),
        act: Act::Thick { reach: 500, px: 140, dmg: 400, delay: 30, count: 5, every: secs(1) as u16 },
    },
    Skill { name: "PLAGUE", level: JOB_LEVEL, cooldown: secs(90), act: Act::Curse { px: 300, ticks: secs(10) as u8 } },
    Skill { name: "HAIL", level: JOB_LEVEL, cooldown: secs(100), act: Act::Zone { zone: Z_HAIL, reach: 400 } },
    Skill { name: "DEADEYE", level: JOB_LEVEL, cooldown: secs(90), act: Act::SelfEffect { fx: FX_DEADEYE } },
    Skill { name: "BENEDICTION", level: JOB_LEVEL, cooldown: secs(120), act: Act::GroupEffect { px: 300, fx: FX_BENEDICTION } },
    Skill { name: "PYRE", level: JOB_LEVEL, cooldown: secs(90), act: Act::Zone { zone: Z_PYRE, reach: 0 } },
    Skill { name: "MARTYR", level: JOB_LEVEL, cooldown: secs(120), act: Act::GroupEffect { px: 200, fx: FX_MARTYR } },
    Skill { name: "CRUSADE", level: JOB_LEVEL, cooldown: secs(90), act: Act::SelfEffect { fx: FX_CRUSADE } },
];

#[derive(Clone, Copy, Debug)]
pub struct Job {
    pub name: &'static str,
    pub class: u8,
    pub ultimate: u8,
    pub passive: Passive,
}

pub const J_WARDEN: u8 = 0;
pub const J_BERSERKER: u8 = 1;
pub const J_ARCHMAGE: u8 = 2;
pub const J_HEXER: u8 = 3;
pub const J_RANGER: u8 = 4;
pub const J_SHARPSHOOTER: u8 = 5;
pub const J_ORACLE: u8 = 6;
pub const J_INQUISITOR: u8 = 7;
pub const J_TEMPLAR: u8 = 8;
pub const J_CRUSADER: u8 = 9;

pub const JOBS: [Job; 10] = [
    Job { name: "WARDEN", class: KNIGHT, ultimate: U_RAMPART, passive: Passive { threat: 26, provoke_pull_px: 40, weapon_dmg_mul_pct: 200, ..NO } },
    Job { name: "BERSERKER", class: KNIGHT, ultimate: U_BLOOD_RAGE, passive: Passive { threat: 14, dmg_per_missing: 3, ..NO } },
    Job { name: "ARCHMAGE", class: MAGE, ultimate: U_CATACLYSM, passive: Passive { second_burst_pct: 100, ..NO } },
    // The HEXER's "cursed monsters take 15% more" is `CURSE_TAKEN_PCT`: only PLAGUE curses.
    Job { name: "HEXER", class: MAGE, ultimate: U_PLAGUE, passive: NO },
    Job { name: "RANGER", class: ARCHER, ultimate: U_HAIL, passive: Passive { pierce: 8, move_pct: 10, ..NO } },
    Job { name: "SHARPSHOOTER", class: ARCHER, ultimate: U_DEADEYE, passive: Passive { reach_pct: 25, elite_pct: 30, ..NO } },
    Job { name: "ORACLE", class: PRIEST, ultimate: U_BENEDICTION, passive: Passive { shield_under_pct: 30, ..NO } },
    Job { name: "INQUISITOR", class: PRIEST, ultimate: U_PYRE, passive: Passive { weapon_dmg_mul_pct: 200, heal_mul_pct: 50, ..NO } },
    Job { name: "TEMPLAR", class: PALADIN, ultimate: U_MARTYR, passive: Passive { aura_pct: 14, aura_px: 140, weapon_dmg_mul_pct: 135, ..NO } },
    Job { name: "CRUSADER", class: PALADIN, ultimate: U_CRUSADE, passive: Passive { ally_dmg_pct: 2, ally_dmg_max: 20, ally_px: 100, ..NO } },
];

/// A timed hero effect row. Percents add within the effects group; `unhurt` takes no damage; `nofall`
/// cannot drop below 1 health.
#[derive(Clone, Copy, Debug)]
pub struct Effect {
    pub name: &'static str,
    pub ticks: u16,
    pub dmg_pct: i32,
    pub as_pct: i32,
    pub move_pct: i32,
    pub taken_pct: i32,
    pub unhurt: bool,
    pub nofall: bool,
    pub xp_pct: i32,
    pub luck: i32,
}

const E: Effect = Effect { name: "", ticks: 0, dmg_pct: 0, as_pct: 0, move_pct: 0, taken_pct: 0, unhurt: false, nofall: false, xp_pct: 0, luck: 0 };

pub const FX_PROVOKE: u8 = 0;
pub const FX_AEGIS: u8 = 1;
pub const FX_RAMPART: u8 = 2;
pub const FX_BLOOD_RAGE: u8 = 3;
pub const FX_BENEDICTION: u8 = 4;
pub const FX_MARTYR: u8 = 5;
pub const FX_CRUSADE: u8 = 6;
pub const FX_DEADEYE: u8 = 7;
pub const FX_RAISED: u8 = 8;
pub const FX_VEIL: u8 = 9;
pub const FX_WHETSTONE: u8 = 10;
pub const FX_INK: u8 = 11;
pub const FX_GAMBLER: u8 = 12;
pub const FX_KNIGHT_OF_WANDS: u8 = 13;
pub const FX_SHIELD: u8 = 14;
pub const FX_DASH: u8 = 15;
pub const NFX: usize = 16;

pub const EFFECTS: [Effect; NFX] = [
    Effect { name: "PROVOKE", ticks: secs(5) as u16, taken_pct: -50, ..E },
    Effect { name: "AEGIS", ticks: secs(3) as u16, unhurt: true, ..E },
    // RAMPART is renewed by its zone while she stands in it.
    Effect { name: "RAMPART", ticks: ZONE_EVERY as u16 + 1, taken_pct: -40, ..E },
    Effect { name: "BLOOD RAGE", ticks: secs(10) as u16, as_pct: 60, ..E },
    Effect { name: "BENEDICTION", ticks: secs(10) as u16, dmg_pct: 25, as_pct: 25, ..E },
    Effect { name: "MARTYR", ticks: secs(8) as u16, nofall: true, ..E },
    Effect { name: "CRUSADE", ticks: secs(10) as u16, move_pct: 30, ..E },
    // DEADEYE: arrows pierce everything and deal double (+100% in the effects group).
    Effect { name: "DEADEYE", ticks: secs(8) as u16, dmg_pct: 100, ..E },
    Effect { name: "RAISED", ticks: secs(2) as u16, unhurt: true, ..E },
    Effect { name: "VEIL OF ASH", ticks: secs(3) as u16, unhurt: true, ..E },
    Effect { name: "WHETSTONE OIL", ticks: secs(30) as u16, dmg_pct: 20, ..E },
    Effect { name: "SCHOLAR'S INK", ticks: secs(120) as u16, xp_pct: 50, ..E },
    Effect { name: "GAMBLER'S COIN", ticks: secs(120) as u16, luck: 20, ..E },
    // KNIGHT OF WANDS: +15% move per copy, for 3 s after a kill.
    Effect { name: "KNIGHT OF WANDS", ticks: secs(3) as u16, move_pct: 15, ..E },
    Effect { name: "SHIELD", ticks: secs(2) as u16, unhurt: true, ..E },
    Effect { name: "DASH", ticks: DASH_TICKS, unhurt: true, ..E },
];

/// A dash takes no time; she is unhurt for this many ticks after it.
pub const DASH_TICKS: u16 = 6;
/// CRUSADE: SMITE strikes this many targets.
pub const CRUSADE_TARGETS: u8 = 3;

/// A zone row: a circle on the ground that acts every `ZONE_EVERY` ticks.
#[derive(Clone, Copy, Debug)]
pub struct ZoneRow {
    pub name: &'static str,
    pub px: i32,
    pub ticks: u16,
    /// Monster damage per second (halved per act at two acts a second).
    pub dmg_s: u32,
    /// Ally healing, percent of her health per second.
    pub heal_s: u32,
    /// Slows monsters in it.
    pub slow: bool,
    /// A hero effect renewed on allies in it.
    pub fx: u8,
}

pub const ZONE_EVERY: u32 = 10;
pub const ZONE_POOL: usize = 2_048;
pub const Z_TUMBLE: u8 = 0;
pub const Z_CONSECRATE: u8 = 1;
pub const Z_RAMPART: u8 = 2;
pub const Z_HAIL: u8 = 3;
pub const Z_PYRE: u8 = 4;

pub const ZONES: [ZoneRow; 5] = [
    ZoneRow { name: "TUMBLE", px: 60, ticks: secs(4) as u16, dmg_s: 0, heal_s: 0, slow: true, fx: NONE },
    ZoneRow { name: "CONSECRATE", px: 140, ticks: secs(8) as u16, dmg_s: 20, heal_s: 4, slow: false, fx: NONE },
    ZoneRow { name: "RAMPART", px: 160, ticks: secs(8) as u16, dmg_s: 0, heal_s: 0, slow: false, fx: FX_RAMPART },
    ZoneRow { name: "HAIL", px: 300, ticks: secs(8) as u16, dmg_s: 60, heal_s: 0, slow: false, fx: NONE },
    ZoneRow { name: "PYRE", px: 180, ticks: secs(10) as u16, dmg_s: 90, heal_s: 0, slow: false, fx: NONE },
];
/// A slowing zone keeps monsters in it slowed this long.
pub const ZONE_SLOW_TICKS: u8 = ZONE_EVERY as u8 + 1;

/// Hero base speed 60 px/s.
pub const HERO_SPEED_PX_S: i32 = 60;
/// SWIFT's move bonus caps at +40%.
pub const SWIFT_CAP_PCT: i32 = 40;
/// WARD's damage reduction caps at 60%.
pub const WARD_CAP_PCT: i32 = 60;
/// Each class level the field counts adds 2% damage (+118% at 60). It replaced the per-outing field level (4% a
/// field level, at most +160%) on 27 Nov 2026; 2 matches what that gave a lone hero over a 5-minute outing
/// (rules_built.md, `measure pace`).
pub const CLASS_LEVEL_DMG_PCT: u32 = 2;
/// A bolt hits monsters this close to its line.
pub const BOLT_HALF_WIDTH_PX: i32 = 10;
/// A weapon's damage grows with its item level (the gear the bench sheet wears): `155 + 4 x (level - 1)`
/// percent of the table's number. The level scaling that keeps the walker gate (600 to 1200 ms) at every
/// level; tuned in rules_built.md.
pub const WEAPON_BASE_PCT: u32 = 155;
pub const WEAPON_PCT_PER_LEVEL: u32 = 4;

/// The weapon's percent at an item level.
pub const fn weapon_pct(item_level: u8) -> u64 {
    let l = if item_level == 0 { 1 } else { item_level };
    (WEAPON_BASE_PCT + WEAPON_PCT_PER_LEVEL * (l as u32 - 1)) as u64
}
