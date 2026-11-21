//! Every monster and class number in one place.

#[derive(Clone, Copy, Debug)]
pub struct Kind {
    pub name: &'static str,
    /// px per second.
    pub speed: u16,
    pub health: u16,
    /// Contact damage per hit (every 10 ticks).
    pub damage: u16,
    pub xp: u32,
}

/// 0 bloat, 1 coffin, 2 guard, 3 cinderling, 4 censor, 5 hound, 6 shard, 7 swords.
pub const KINDS: [Kind; 8] = [
    Kind { name: "bloat", speed: 30, health: 60, damage: 6, xp: 3 },
    Kind { name: "coffin", speed: 20, health: 120, damage: 10, xp: 5 },
    Kind { name: "guard", speed: 35, health: 80, damage: 8, xp: 4 },
    Kind { name: "cinderling", speed: 55, health: 20, damage: 4, xp: 1 },
    Kind { name: "censor", speed: 40, health: 40, damage: 5, xp: 2 },
    Kind { name: "hound", speed: 70, health: 30, damage: 6, xp: 2 },
    Kind { name: "shard", speed: 50, health: 25, damage: 4, xp: 1 },
    Kind { name: "swords", speed: 45, health: 50, damage: 7, xp: 3 },
];

#[derive(Clone, Copy, Debug)]
pub struct Class {
    pub name: &'static str,
    /// Auto-attack area radius, px.
    pub area_px: i32,
    pub area_damage: u16,
    /// Ticks between auto-attacks.
    pub cooldown: u8,
    pub bolt_damage: u16,
    /// Bolt reach, px.
    pub bolt_px: i32,
}

/// 0 knight, 1 mage, 2 archer, 3 priest, 4 paladin.
pub const CLASSES: [Class; 5] = [
    Class { name: "knight", area_px: 64, area_damage: 30, cooldown: 10, bolt_damage: 15, bolt_px: 160 },
    Class { name: "mage", area_px: 120, area_damage: 20, cooldown: 16, bolt_damage: 30, bolt_px: 320 },
    Class { name: "archer", area_px: 48, area_damage: 10, cooldown: 10, bolt_damage: 40, bolt_px: 400 },
    Class { name: "priest", area_px: 96, area_damage: 15, cooldown: 12, bolt_damage: 15, bolt_px: 240 },
    Class { name: "paladin", area_px: 80, area_damage: 25, cooldown: 12, bolt_damage: 20, bolt_px: 200 },
];
