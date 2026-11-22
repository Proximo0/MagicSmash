//! What a carpenter makes. Furniture is an item of the store (a CHARM with one line of zero points, so wearing
//! it changes nothing) whose `base` is `FURNITURE_BASE + kind`; a trophy plaque is `TROPHY_BASE_ITEM + boss`.
//! Each field's own material makes four pieces; a boss trophy (material 10 + boss) makes a plaque.

use realm_store::{ItemSpec, StackKind};

pub const FURNITURE_BASE: u32 = 9000;
pub const TROPHY_ITEM_BASE: u32 = 9100;
pub const FURNITURE_KINDS: usize = 24;
pub const TROPHIES: usize = 8;
/// A craft request names furniture 0..24, or a trophy as `TROPHY_CRAFT + boss`.
pub const TROPHY_CRAFT: u16 = 100;
/// The material of a boss trophy is `material(TROPHY_MATERIAL + boss)` (the loot job's `TROPHY_BASE`).
pub const TROPHY_MATERIAL: u32 = 10;

/// Coin for the first piece of a field's own material set; the next pieces cost this times 2, 3, 4, and the field
/// multiplies by its number (1 to 6).
pub const FURNITURE_COIN: u64 = 60;
/// Pieces of the field's material: 4, 6, 8, 10 for the field's four pieces.
pub const FURNITURE_MAT_BASE: u64 = 4;
pub const FURNITURE_MAT_STEP: u64 = 2;
/// Coin for a trophy plaque (and one trophy).
pub const TROPHY_COIN: u64 = 500;

/// The hearth: a house with one placed has a campfire in that cell.
pub const HEARTH: u16 = 8;

pub const NAMES: [&str; FURNITURE_KINDS] = [
    "CHAIR", "STRAW BED", "LINEN RUG", "PLAGUE CURTAIN",
    "TABLE", "BOOKSHELF", "CHEST", "GALLOWS CLOCK",
    "HEARTH", "CANDELABRA", "BRAZIER", "IRON BED",
    "SIGIL RUG", "ALTAR", "SCRYING BOWL", "RUNE LAMP",
    "WINDOW", "MIRROR", "LANTERN", "SAINT'S SCREEN",
    "URN", "SKULL SHELF", "BLACK MIRROR", "ASH THRONE",
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Recipe {
    pub kind: u16,
    /// The stack kind that is spent, how many, and the coin.
    pub material: u32,
    pub count: u64,
    pub coin: u64,
    pub base: u32,
    pub rarity: u8,
}

/// The recipe a craft request names, or None.
pub fn recipe(kind: u16) -> Option<Recipe> {
    if (kind as usize) < FURNITURE_KINDS {
        let (field, piece) = (kind as u64 / 4, kind as u64 % 4);
        return Some(Recipe {
            kind,
            material: StackKind::material(1 + field as u32).0,
            count: FURNITURE_MAT_BASE + FURNITURE_MAT_STEP * piece,
            coin: FURNITURE_COIN * (field + 1) * (piece + 1),
            base: FURNITURE_BASE + kind as u32,
            rarity: (field / 2) as u8,
        });
    }
    let boss = kind.checked_sub(TROPHY_CRAFT)? as usize;
    (boss < TROPHIES).then(|| Recipe { kind, material: StackKind::material(TROPHY_MATERIAL + boss as u32).0, count: 1, coin: TROPHY_COIN, base: TROPHY_ITEM_BASE + boss as u32, rarity: 3 })
}

pub fn all() -> Vec<Recipe> {
    (0..FURNITURE_KINDS as u16).chain((0..TROPHIES as u16).map(|b| TROPHY_CRAFT + b)).filter_map(recipe).collect()
}

pub fn spec(r: &Recipe) -> ItemSpec {
    ItemSpec { base: r.base, gear_slot: 5, item_level: 1, rarity: r.rarity, lines: vec![(0, 0)], sockets: 0, plus: 0, bound: false }
}

/// Is this item base a piece of furniture or a trophy plaque (something a house holds)?
pub fn is_house_thing(base: u32) -> bool {
    (FURNITURE_BASE..FURNITURE_BASE + FURNITURE_KINDS as u32).contains(&base) || (TROPHY_ITEM_BASE..TROPHY_ITEM_BASE + TROPHIES as u32).contains(&base)
}

pub fn is_hearth(base: u32) -> bool {
    base == FURNITURE_BASE + HEARTH as u32
}

/// A plaque is made from a boss trophy and kept: it is not sold to a merchant or listed on the market.
pub fn is_plaque(base: u32) -> bool {
    (TROPHY_ITEM_BASE..TROPHY_ITEM_BASE + TROPHIES as u32).contains(&base)
}
