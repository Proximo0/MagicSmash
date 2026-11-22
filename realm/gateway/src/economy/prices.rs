//! Every number of the economy between players. Nothing in the logic is a literal; `docs/realm/economy.md` part 2
//! says why each was chosen. Coin is whole numbers; a kill at level L pays about `3 x (100 + 12 (L - 1))%` coin.

use realm_core::tables::FIELDS;
use realm_store::ItemSpec;

pub const MS_HOUR: i64 = 3_600_000;
pub const MS_DAY: i64 = 24 * MS_HOUR;

// ---- what an item is worth (the reference every other price hangs on)
/// Value of a COMMON item at level L is `VALUE_BASE + VALUE_PER_LEVEL x L` coin: about 9 kills' coin at any level
/// (a kill pays about `3 + L / 3`), so the lowest rung is always "a few minutes of play".
pub const VALUE_BASE: u64 = 5;
pub const VALUE_PER_LEVEL: u64 = 3;
/// Times the COMMON value by rarity, COMMON to RELIC. The drop odds are 60 / 30 / 8.5 / 1.4 / 0.1 percent, so
/// the multiples are shorter than the odds (a RELIC is 600 times rarer than a COMMON and worth 50 times more): the
/// market, not the table, makes the very rare ones dear.
pub const RARITY_VALUE_MUL: [u64; 5] = [1, 2, 5, 14, 50];
/// Each `+` of the smith adds this percent of the value (the smith charges far more; a used item is cheaper
/// than its making, which is what keeps upgrades a thing done for oneself).
pub const PLUS_VALUE_PCT: u64 = 25;
/// Each filled socket adds this many times the level-1 value of a rune (kept small: the smith's `unsocket` gets
/// it back, so a socketed rune must not be sold for nothing, but it is not priced by the market either).
pub const SOCKET_VALUE_PER_LEVEL: u64 = 2;

pub fn item_value(spec: &ItemSpec) -> u64 {
    let base = VALUE_BASE + VALUE_PER_LEVEL * spec.item_level as u64;
    let v = base * RARITY_VALUE_MUL[spec.rarity.min(4) as usize] * (100 + PLUS_VALUE_PCT * spec.plus as u64) / 100;
    v.max(1)
}

// ---- NPC merchants
/// A merchant pays this percent of an item's value (the floor of every price: nobody sells below it).
pub const NPC_BUY_PCT: u64 = 25;
/// A merchant sells COMMON gear at this many times its value: dear, so the market beats it for anyone who can wait.
pub const NPC_GEAR_MUL: u64 = 12;
/// Potions: `(POTION_BASE + top level of her field) x POTION_MUL[kind]` coin, kinds in the core's order.
pub const POTION_BASE: u64 = 8;
pub const POTION_MUL: [u64; 6] = [1, 3, 3, 5, 8, 20];
/// Embers: `EMBER_BASE + top level / EMBER_LEVEL_DIV` coin each (the smith's other price).
pub const EMBER_BASE: u64 = 4;
pub const EMBER_LEVEL_DIV: u64 = 2;
/// What the merchant pays for embers and for a field's own material, per piece; for a boss trophy.
pub const EMBER_SELL: u64 = 2;
pub const FIELD_MATERIAL_SELL: u64 = 3;
pub const TROPHY_SELL: u64 = 150;
/// What one hero may buy of each line in a day (the merchant restocks at dawn): potions, embers, gear pieces.
pub const DAILY_POTIONS: u32 = 20;
pub const DAILY_EMBERS: u32 = 100;
pub const DAILY_GEAR: u32 = 2;
/// A sold item can be bought back for this percent of what the merchant paid, for this long, from the last 12.
pub const BUYBACK_PCT: u64 = 110;
pub const BUYBACK_MS: i64 = 30 * 60 * 1000;
pub const BUYBACK_KEEP: usize = 12;

/// The field a level belongs to (0 to 5), and the top level of that field.
pub fn field_of(level: u16) -> usize {
    FIELDS.iter().position(|f| level <= f.top as u16).unwrap_or(FIELDS.len() - 1)
}
pub fn field_top(level: u16) -> u64 {
    FIELDS[field_of(level)].top as u64
}

pub fn potion_price(kind: usize, level: u16) -> u64 {
    (POTION_BASE + field_top(level)) * POTION_MUL[kind.min(5)]
}
pub fn ember_price(level: u16) -> u64 {
    EMBER_BASE + field_top(level) / EMBER_LEVEL_DIV
}
pub fn gear_price(spec: &ItemSpec) -> u64 {
    item_value(spec) * NPC_GEAR_MUL
}
pub fn npc_pays(spec: &ItemSpec) -> u64 {
    (item_value(spec) * NPC_BUY_PCT / 100).max(1)
}

// ---- the market
/// Sale tax: this percent of the price (rounded up), destroyed with the sale. The main coin sink of the market.
pub const TAX_PCT: u64 = 6;
/// Listing fee: this percent of the price for each 12 hours listed (rounded up, at least 1), destroyed at once and
/// never refunded: churn (list, cancel, list) costs, and a listing nobody wants for 48 hours costs 4%.
pub const FEE_PCT_PER_12H: u64 = 1;
/// A listing lasts one of these many hours.
pub const HOURS: [u16; 3] = [12, 24, 48];
/// One hero's open listings, and the longest a price may be (the store's own cap is a trillion).
pub const PRICE_MAX: u64 = 100_000_000_000;
/// A listing may ask at most this many times the item's value (stacks: the reference value of the pieces). The
/// ceiling is the market's own guard: the market cannot run away upward, and an account cannot move a large sum
/// to another by listing a cheap thing at a huge price for an accomplice to buy (the cap is a few hundred coin at
/// most for gear a player will meet in the first fields, and the tax and fee come out of it).
pub const PRICE_CAP_MUL: u64 = 10;
/// Search pages of this many listings.
pub const PAGE: u32 = 40;

pub fn tax_of(price: u64) -> u64 {
    (price * TAX_PCT).div_ceil(100)
}
pub fn fee_of(price: u64, hours: u16) -> u64 {
    (price * FEE_PCT_PER_12H * (hours as u64 / 12)).div_ceil(100).max(1)
}

// ---- letters
/// A letter waits this long; then it goes back to the sender's mail.
pub const LETTER_DAYS: i64 = 30;
/// Postage: coin for the letter and for each attachment (destroyed). Keeps a spammer's cost per letter above nothing.
pub const POSTAGE: u64 = 2;
pub const POSTAGE_PER_THING: u64 = 1;
pub const LETTER_THINGS: usize = 8;

// ---- trade
/// A trade invitation lives this long unanswered; an open trade this long without a change.
pub const INVITE_MS: i64 = 60_000;
pub const TRADE_IDLE_MS: i64 = 10 * 60_000;
/// A confirm is accepted only this long after the last change of either offer (no swap at the last click).
pub const CONFIRM_DELAY_MS: i64 = 1_500;

// ---- limits on a hero's actions
/// A hero may make this many economy requests in a burst and earns `LIMIT_REFILL_PER_S` back each second.
pub const LIMIT_BURST: u32 = 30;
pub const LIMIT_REFILL_PER_S: u32 = 3;

/// The most a listing of this item may ask.
pub fn item_price_cap(spec: &ItemSpec) -> u64 {
    item_value(spec) * PRICE_CAP_MUL
}

/// A reference coin value of one piece of a stack kind (what the cap multiplies), or None for a kind that is
/// not for sale (coin). The numbers are the merchant's own where it has them and guesses elsewhere (see the
/// open questions in economy.md): potions at the top field's price, embers at the dearest merchant price,
/// field material and trophies at the merchant's price x10, runes by grade, keys, pages and cards by rarity.
pub fn stack_ref(kind: u32) -> Option<u64> {
    Some(match kind {
        1 => return None,
        100..=105 => potion_price(kind as usize - 100, 60),
        1000 => ember_price(60),
        1001..=1006 => FIELD_MATERIAL_SELL * 10,
        1010..=1017 => TROPHY_SELL * 3,
        2000..=2999 => match (kind - 2000) % 10 {
            1 => 150,
            2 => 600,
            _ => 2_400,
        },
        3000..=3099 => 2_000,
        4000..=4099 => 3_000,
        5000..=9999 => 5_000,
        _ => return None,
    })
}
