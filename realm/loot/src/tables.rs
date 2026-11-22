//! Every number of the loot rules (rules section 9) and of the smith. Nothing here is a literal in logic.
//! `docs/realm/economy.md` part 1 says why each number was chosen.

// ---- rarity (tier 1 to 5 = rarity 0 to 4)
pub const COMMON: u8 = 0;
pub const UNCOMMON: u8 = 1;
pub const RARE: u8 = 2;
pub const EPIC: u8 = 3;
pub const RELIC: u8 = 4;
pub const RARITY_NAMES: [&str; 5] = ["COMMON", "UNCOMMON", "RARE", "EPIC", "RELIC"];
/// Chance of each rarity of one roll, in thousandths (60%, 30%, 8.5%, 1.4%, 0.1%).
pub const RARITY_PER_MILLE: [u32; 5] = [600, 300, 85, 14, 1];
/// A line's points are `1 + item level / 4` times this percent.
pub const RARITY_STEP_PCT: [u32; 5] = [100, 120, 150, 190, 240];
/// Lines drawn (COMMON 1 ... EPIC and RELIC 4).
pub const RARITY_LINES: [usize; 5] = [1, 2, 3, 4, 4];
/// RARE and better have one socket, RELIC two.
pub const RARITY_SOCKETS: [u8; 5] = [0, 0, 1, 1, 2];
/// RARE and better are kept the moment they drop; COMMON and UNCOMMON ride in the haul.
pub const FIRST_KEPT_RARITY: u8 = RARE;
pub const MAX_ITEM_LEVEL: u8 = 60;

// ---- gear
pub const WEAPON: u8 = 0;
pub const HEAD: u8 = 1;
pub const BODY: u8 = 2;
pub const HANDS: u8 = 3;
pub const FEET: u8 = 4;
pub const CHARM: u8 = 5;
pub const SLOT_NAMES: [&str; 6] = ["WEAPON", "HEAD", "BODY", "HANDS", "FEET", "CHARM"];
/// Weight of each slot in a roll.
pub const SLOT_WEIGHT: [u32; 6] = [1, 1, 1, 1, 1, 1];
/// The kinds of base of each slot. The six weapons are the classes' own (dirk, cleaver, staff, longbow, censer, mace).
pub const BASE_VARIANTS: [&[&str]; 6] = [
	&["DIRK", "CLEAVER", "STAFF", "LONGBOW", "CENSER", "MACE"],
	&["COWL", "HELM", "CROWN"],
	&["ROBE", "MAIL", "COAT"],
	&["GLOVES", "GAUNTLETS", "WRAPS"],
	&["BOOTS", "GREAVES", "SANDALS"],
	&["TALISMAN", "RING", "AMULET"],
];
/// The base's name prefix by the field it drops in (its tier of base).
pub const BASE_TIER_NAMES: [&str; 6] = ["PILGRIM'S", "HANGED", "BOG", "HERMIT'S", "GILDED", "ASHEN"];
pub const STAT_NAMES: [&str; 6] = ["MIGHT", "FOCUS", "SWIFT", "VIGOR", "WARD", "FORTUNE"];

/// An item's `plus` adds this percent to each line a step.
pub const PLUS_PCT: u32 = 3;
pub const PLUS_MAX: u8 = 10;

// ---- chances of the rolls of a kill (one in N, N x 100 with luck)
pub const MONSTER_ITEM_ONE_IN: u32 = 400;
pub const ELITE_ITEM_ONE_IN: u32 = 20;
/// Each point of luck adds this percent, relative, to the chance of an item roll.
pub const LUCK_PCT_PER_POINT: u32 = 1;
/// At most this many non-boss item rolls a minute (1,200 ticks) a hero.
pub const ITEM_ROLLS_PER_MINUTE: usize = 12;
pub const ITEM_ROLL_WINDOW_TICKS: u32 = 60 * realm_core::TICK_HZ;
/// A CHAMPION's item roll starts here.
pub const CHAMPION_MIN_RARITY: u8 = UNCOMMON;

pub const CARD_KIND_ONE_IN: u32 = 20_000;
pub const CARD_CHAMPION_ONE_IN: u32 = 200;
pub const CARD_BOSS_ONE_IN: u32 = 100;
pub const RUNE_ELITE_ONE_IN: u32 = 30;
pub const PAGE_ELITE_ONE_IN: u32 = 300;
pub const KEY_ELITE_ONE_IN: u32 = 150;
/// Vault keys drop in fields whose top level is at least this.
pub const KEY_MIN_FIELD_TOP: u8 = 20;
/// An ELITE leaves its field's own material this often (one in N), one piece.
pub const FIELD_MATERIAL_ELITE_ONE_IN: u32 = 2;
pub const FIELD_MATERIAL_CHAMPION: u64 = 3;

// ---- runes
pub const RUNE_POINTS: [u16; 3] = [2, 4, 7];
pub const RUNE_ELITE_GRADE: u32 = 1;
pub const RUNE_BOSS_GRADE: u32 = 2;
/// Three runes of a grade fuse into one of the next.
pub const FUSE_COUNT: u64 = 3;
/// Coin to fuse into grade II and III.
pub const FUSE_COIN: [u64; 2] = [100, 400];

// ---- materials (stack kind `material(n)`)
pub const EMBERS: u32 = 0;
/// A field's own material is `FIELD_MATERIAL_BASE + field`.
pub const FIELD_MATERIAL_BASE: u32 = 1;
pub const FIELD_MATERIAL_NAMES: [&str; 6] = ["PLAGUE LINEN", "GALLOWS OAK", "BOG IRON", "RUNE SLATE", "STAINED GLASS", "ASH GLASS"];
/// A boss's trophy is `TROPHY_BASE + boss`.
pub const TROPHY_BASE: u32 = 10;
pub const TROPHY_ONE_IN: u32 = 4;
/// Embers from a monster: one in N, one piece, scaled by level.
pub const EMBER_MONSTER_ONE_IN: u32 = 8;
pub const EMBER_ELITE: (u64, u64) = (2, 4);
pub const EMBER_CHAMPION: (u64, u64) = (8, 12);
pub const EMBER_TIDE: (u64, u64) = (10, 20);
pub const EMBER_BOSS: (u64, u64) = (30, 50);
pub const EMBER_WORLD: (u64, u64) = (100, 150);
/// Embers and field materials grow with the monster's level by this percent a level.
pub const EMBER_PCT_PER_LEVEL: u32 = 6;

// ---- chests
pub const TIDE_ITEM_ROLLS: usize = 3;
pub const TIDE_MIN_RARITY: u8 = UNCOMMON;
pub const TIDE_FIELD_MATERIAL: u64 = 3;
pub const BOSS_ITEM_ROLLS: usize = 2;
pub const BOSS_MIN_RARITY: u8 = RARE;
pub const BOSS_FIELD_MATERIAL: u64 = 10;
pub const WORLD_TOP_COUNT: usize = 100;
pub const WORLD_TOP_MIN_RARITY: u8 = RELIC;
pub const WORLD_MIN_RARITY: u8 = EPIC;
/// Coin of a cache or chest at level 1, times the monster power percent (`100 + 12 x (level - 1)`).
pub const TIDE_COIN: u64 = 60;
pub const BOSS_COIN: u64 = 400;
pub const WORLD_COIN: u64 = 4_000;
pub const POWER_PCT_PER_LEVEL: u32 = 12;

// ---- the smith
/// Salvage: embers = (1 + item level / 10) x this by rarity, x (100 + 10 x plus)%.
pub const SALVAGE_RARITY_MUL: [u64; 5] = [1, 2, 4, 8, 16];
pub const SALVAGE_LEVEL_DIV: u64 = 10;
pub const SALVAGE_PLUS_PCT: u64 = 10;
/// Upgrade to +s: embers `(2 + item level / 3) x s`, coin `4 x item level x s x s`.
pub const UPGRADE_EMBER_BASE: u64 = 2;
pub const UPGRADE_EMBER_LEVEL_DIV: u64 = 3;
pub const UPGRADE_COIN_PER_LEVEL: u64 = 4;
/// Chance in percent of reaching +s (index s - 1). Steps 1 to 5 never fail; a failed step above +5 costs
/// the embers (not the coin) and never the item.
pub const UPGRADE_SUCCESS_PCT: [u32; 10] = [100, 100, 100, 100, 100, 80, 65, 50, 40, 30];
pub const UPGRADE_SAFE_STEPS: u8 = 5;
/// Reroll lines: embers `(6 + item level / 2) x (rarity + 1) x (10 + plus) / 10`, coin `30 x item level x (rarity + 1)`.
pub const REROLL_EMBER_BASE: u64 = 6;
pub const REROLL_EMBER_LEVEL_DIV: u64 = 2;
pub const REROLL_COIN_PER_LEVEL: u64 = 30;
/// Coin per item level to put a card or rune into a socket, and to take it out.
pub const SOCKET_COIN_PER_LEVEL: u64 = 10;
pub const UNSOCKET_COIN_PER_LEVEL: u64 = 25;
