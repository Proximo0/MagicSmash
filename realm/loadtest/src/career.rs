//! Careers: bot heroes that live a hero's life from class level 1 to 60 the way people do (job B1,
//! `docs/realm/balance.md`). Between outings a hero is in town: she banks, takes her class at 10 and her job at
//! 40, spends her points, wears the better item, sells junk to the merchant, salvages the rest, buys gear on the
//! market when hers falls behind, restocks her belt, repairs, pays the fare to her waystone and visits the smith.
//! In the field she is a core class bot (`realm_core::bots`), alone or in a party of two to eight, at the ring
//! whose monsters are her level; she kills, picks cards, drinks, banks, is downed, raised and sometimes falls.
//!
//! Every number of a career is a whole number and every choice is seeded, so a cohort is a pure function of its
//! seed (instances of one round run on threads and are applied in order). Coin is booked as minted (kills,
//! chests, the merchant) or sunk (potions, repair, fares, the smith, the market's tax, falls).
//!
//! Compression: an outing of `minutes` played ticks is credited as `k` times as long (XP, coin, loot rolls,
//! potions and wear x k) from class level `FAST_FROM` on, so a career of 80 hours can be measured in a few.

use realm_core::bots::{Bot, Plan};
use realm_core::tables::*;
use realm_core::rng_next;
use realm_core::{Config, Event, FIELD, Field, Outing, SUB, Sheet};
use realm_gateway::economy::prices;
use realm_loot::gear::{base_id, gear_stats, line_value, roll_lines};
use realm_loot::rng::{Rng, mix};
use realm_loot::tables::{BASE_VARIANTS, FIRST_KEPT_RARITY, RARITY_LINES, RARITY_SOCKETS, UNCOMMON};
use realm_loot::{Credit, Found, Haul, RollGate, RollKey, Source, What, roll, sinks, smith};
use realm_store::{ItemSpec, StackClass, StackKind};

// ---- the numbers of a person's choices (each is reported in balance.md)

/// Stat points by class, in twelfths of the points spent (NOVICE, KNIGHT, MAGE, ARCHER, PRIEST, PALADIN).
pub const STAT_PLAN: [[u16; 6]; 6] = [
    [6, 2, 2, 2, 0, 0],
    [5, 1, 0, 4, 2, 0],
    [6, 3, 1, 2, 0, 0],
    [6, 3, 2, 1, 0, 0],
    [4, 2, 0, 4, 2, 0],
    [5, 1, 0, 4, 2, 0],
];
/// She fights monsters this many levels below her own (a margin of safety).
pub const RING_LEVEL_BELOW: u8 = 1;
/// The patrol radius is kept between these (px from the heart).
pub const RING_MIN_PX: i32 = 2_000;
pub const RING_MAX_PX: i32 = 7_200;
/// Market: she buys a piece when hers is this many levels behind (or missing), at this percent of its value,
/// choosing the best of this many listings, and keeps this many hours of her income in the bank.
pub const MARKET_LAG: u16 = 6;
pub const MARKET_PRICE_PCT: u64 = 100;
pub const MARKET_CHOICE: usize = 4;
/// Belt: HEALING DRAUGHT, WHETSTONE OIL and PHOENIX ASH, filled to what a slot carries.
pub const BELT_PLAN: [u8; 3] = [P_HEALING, P_WHETSTONE, P_PHOENIX];
/// The phoenix is bought from this class level (before it, two draughts).
pub const PHOENIX_FROM: u8 = 10;
/// Smith: every worn piece to +`SMITH_SAFE`; the weapon on to +`SMITH_WEAPON_MAX` while the bank holds this many
/// times the step's coin.
pub const SMITH_SAFE: u8 = 5;
pub const SMITH_WEAPON_MAX: u8 = 7;
pub const SMITH_RICH_MUL: u64 = 4;
/// A haul is banked at a waystone when it is worth this many kills of her level (`Plan.bank_coin`).
pub const BANK_KILLS: u32 = 150;
/// Heroes in one field copy of a career round: a field this empty gives each the density R1 tuned (60 a hero).
pub const SOLO_PER_FIELD: usize = 5;
/// Party sizes careers prefer, by career index (the first member of a party sets its size).
pub const PARTY_SIZES: [usize; 4] = [4, 3, 6, 8];
/// The share of outings a career plays in a party (percent); the rest alone. People do both.
pub const PARTY_PCT: u64 = 50;
/// Compression starts at this class level (below it every tick is played).
pub const FAST_FROM: u8 = 10;
/// A weapon level is worth this many line points when choosing what to wear.
pub const WEAPON_LEVEL_WORTH: u32 = 6;

/// Class XP an hour at a level, from measured (level, XP an hour) rows, interpolated in logs between rows of the
/// same field (a hero changes field, and with it her rate, at a field's bottom level; and her class at 10).
pub fn rate_at(rows: &[(u8, u64)], level: u8) -> f64 {
    let field = Career::place(level).0;
    let same: Vec<(f64, f64)> = rows.iter().filter(|r| Career::place(r.0).0 == field).map(|r| (r.0 as f64, (r.1.max(1) as f64).ln())).collect();
    let same = if same.is_empty() { rows.iter().map(|r| (r.0 as f64, (r.1.max(1) as f64).ln())).collect() } else { same };
    let l = level as f64;
    if l <= same[0].0 {
        return same[0].1.exp();
    }
    for w in same.windows(2) {
        if l <= w[1].0 {
            let t = (l - w[0].0) / (w[1].0 - w[0].0);
            return (w[0].1 * (1.0 - t) + w[1].1 * t).exp();
        }
    }
    same[same.len() - 1].1.exp()
}

/// What a career makes of the probe's rate in each field, percent: two steps of the curve's hours for the field's
/// band over the median career's (`balance career 1 1 10 16 160`, then `1 2`; balance.md). Falls, travel and town
/// make a career slower than the probe where it dies (THE HANGED WOOD); bigger parties make it faster elsewhere.
pub const CAREER_PCT: [u64; 6] = [89, 56, 150, 74, 143, 155];

/// `MEASURED_XP_HOUR` times `CAREER_PCT` of its field: the rates `CLASS_XP` is fitted to.
pub const CAREER_XP_HOUR: [(u8, u64); 18] = {
    let mut out = MEASURED_XP_HOUR;
    let mut i = 0;
    while i < out.len() {
        let l = out[i].0;
        let f = if l >= 50 { 5 } else if l >= 40 { 4 } else if l >= 30 { 3 } else if l >= 20 { 2 } else if l >= 10 { 1 } else { 0 };
        out[i].1 = out[i].1 * CAREER_PCT[f] / 100;
        i += 1;
    }
    out
};

/// Class XP an hour of the median career (half alone, half in parties: the harmonic mean of the two medians of
/// the five classes) at a class level, measured by `realm-loadtest balance probe 3 8` at the bottom, middle and
/// last level of each field (balance.md). Careers choose where to fight by them; `CLASS_XP` is fitted to `CAREER_XP_HOUR`.
pub const MEASURED_XP_HOUR: [(u8, u64); 18] = [
    (1, 1_135), (5, 1_327), (9, 4_019), (10, 129_918), (15, 90_890), (19, 141_700), (20, 69_794), (25, 92_024), (29, 67_483),
    (30, 330_474), (35, 328_054), (39, 531_502), (40, 58_366), (45, 456_129), (49, 523_657), (50, 801_750), (55, 902_255), (60, 2_507_979),
];
/// A hero keeps to the best place of the last `STAY_LEVELS` levels: (the level of monsters she seeks, its rate).
pub const STAY_LEVELS: u8 = 5;
pub fn best_rate(rows: &[(u8, u64)], level: u8) -> (u8, f64) {
    let mut best = (level, rate_at(rows, level));
    for l in level.saturating_sub(STAY_LEVELS).max(1)..level {
        let r = rate_at(rows, l);
        if r > best.1 * 1.0001 {
            best = (l, r);
        }
    }
    best
}

/// Coin booked over a career or a band.
#[derive(Clone, Copy, Debug, Default)]
pub struct Book {
    /// Minted: kill coin into the haul, chest and cache coin, the merchant's pay for junk.
    pub kills: u64,
    pub chests: u64,
    pub merchant: u64,
    /// Sunk: lost to falls, potions, repair, fares, the smith, the market's tax.
    pub fall: u64,
    pub potions: u64,
    pub repair: u64,
    pub travel: u64,
    pub smith: u64,
    pub tax: u64,
    /// Moved to other players (market purchases after tax).
    pub market: u64,
}

impl Book {
    pub fn minted(&self) -> u64 {
        self.kills + self.chests + self.merchant
    }
    pub fn monsters(&self) -> u64 {
        self.kills + self.chests
    }
    pub fn sunk(&self) -> u64 {
        self.fall + self.potions + self.repair + self.travel + self.smith + self.tax
    }
    pub fn add(&mut self, o: &Book) {
        self.kills += o.kills;
        self.chests += o.chests;
        self.merchant += o.merchant;
        self.fall += o.fall;
        self.potions += o.potions;
        self.repair += o.repair;
        self.travel += o.travel;
        self.smith += o.smith;
        self.tax += o.tax;
        self.market += o.market;
    }
}

/// What a career did inside one level band (1-9, 10-19, ... 50-59, 60).
#[derive(Clone, Copy, Debug, Default)]
pub struct Band {
    /// Credited field ticks.
    pub ticks: u64,
    pub xp: u64,
    pub kills: u64,
    pub downs: u64,
    pub falls: u64,
    pub outings: u64,
    pub partied: u64,
    pub book: Book,
}

pub const BANDS: usize = 7;
pub fn band_of(level: u8) -> usize {
    (level as usize / 10).min(BANDS - 1)
}

#[derive(Clone, Debug)]
pub struct Career {
    pub idx: usize,
    /// The class she takes at 10 and whether she takes its second job at 40.
    pub class: u8,
    pub second_job: bool,
    pub race: u8,
    /// 1 alone, else the party size she looks for.
    pub party: usize,
    pub level: u8,
    pub xp: u64,
    pub worn: [Option<ItemSpec>; 6],
    pub sockets: [Vec<Option<StackKind>>; 6],
    pub runes: Vec<StackKind>,
    pub embers: u64,
    pub coin: u64,
    pub potions: [u64; 6],
    pub ticks: u64,
    /// Credited ticks when she reached each level (index = level).
    pub reached: [u64; 61],
    pub bands: [Band; BANDS],
    pub rng: Rng,
}

/// One hero's result of one outing (played ticks, before compression).
#[derive(Clone, Debug, Default)]
pub struct Played {
    pub xp: u64,
    pub kills: u64,
    pub downs: u64,
    pub falls: u64,
    pub kill_coin: u64,
    pub chest_coin: u64,
    pub fall_coin: u64,
    pub potions: [u64; 6],
    /// Kept drops (RARE and better, runes, chest coin as `What::Stack(COIN)`), and the banked haul.
    pub found: Vec<Found>,
    pub haul: Haul,
}

impl Career {
    pub fn new(idx: usize, class: u8, second_job: bool, race: u8, party: usize, seed: u64) -> Career {
        let mut c = Career {
            idx,
            class,
            second_job,
            race,
            party,
            level: 1,
            xp: 0,
            worn: Default::default(),
            sockets: Default::default(),
            runes: Vec::new(),
            embers: 0,
            coin: 0,
            potions: [0; 6],
            ticks: 0,
            reached: [u64::MAX; 61],
            bands: [Band::default(); BANDS],
            rng: Rng::new(mix(seed, 0xCA_2EE2 + idx as u64)),
        };
        c.reached[1] = 0;
        c
    }

    /// A hero placed at a level as a career of that level would be (the probe): gear `MARKET_LAG / 2` levels
    /// behind, UNCOMMON, at the smith's safe steps, a full belt.
    pub fn at_level(idx: usize, class: u8, second_job: bool, race: u8, level: u8, seed: u64) -> Career {
        let mut c = Career::new(idx, class, second_job, race, 1, seed);
        c.level = level.clamp(1, CLASS_LEVEL_MAX);
        c.xp = realm_gateway::sheet::xp_to_reach(c.level as u16);
        let il = (c.level as u16).saturating_sub(MARKET_LAG / 2).max(1);
        for slot in 0..6u8 {
            let mut spec = c.market_item(slot, il);
            spec.plus = (c.level / 10).min(SMITH_SAFE);
            c.sockets[slot as usize] = vec![None; spec.sockets as usize];
            c.worn[slot as usize] = Some(spec);
        }
        c.potions = [20; 6];
        c
    }

    /// The class the field sees.
    pub fn field_class(&self) -> u8 {
        if self.level < SKILL1_LEVEL { NOVICE } else { self.class }
    }

    pub fn sheet(&self) -> Sheet {
        let class = self.field_class();
        let job = if class != NOVICE && self.level >= JOB_LEVEL { CLASSES[class as usize].jobs[self.second_job as usize] } else { NONE };
        let spent = self.level as u16 - 1;
        let plan = &STAT_PLAN[class as usize];
        let mut points = [0u16; 6];
        let mut given = 0;
        for s in 0..6 {
            points[s] = spent * plan[s] / 12;
            given += points[s];
        }
        points[MIGHT] += spent - given;
        let worn: Vec<(ItemSpec, Vec<Option<StackKind>>)> =
            (0..6).filter_map(|s| self.worn[s].clone().map(|w| (w, self.sockets[s].clone()))).collect();
        let gear = gear_stats(&worn);
        let gear_level = self.worn[0].as_ref().map_or(1, |w| w.item_level).clamp(1, CLASS_LEVEL_MAX as u16) as u8;
        let mut belt = [(P_NONE, 0u8); BELT];
        for (slot, &p) in self.belt_plan().iter().enumerate() {
            let n = self.potions[p as usize].min(POTIONS[p as usize].carried as u64) as u8;
            if n > 0 {
                belt[slot] = (p, n);
            }
        }
        Sheet {
            class,
            job,
            race: self.race,
            class_level: self.level,
            points,
            gear,
            gear_level,
            deck: (1..=realm_core::owned_cards(self.level).min(DECK_SIZE as u8)).collect(),
            belt,
            look: 0,
        }
    }

    fn belt_plan(&self) -> [u8; 3] {
        if self.level < PHOENIX_FROM { [P_HEALING, P_WHETSTONE, P_HEALING] } else { BELT_PLAN }
    }

    /// How much an item is worth to her: its lines by her class's plan (+1 each so no stat is worthless),
    /// the smith's steps, and a weapon's level.
    pub fn worth(&self, spec: &ItemSpec) -> u32 {
        let plan = &STAT_PLAN[self.class as usize];
        let mut w = 0u32;
        for &(s, p) in &spec.lines {
            w += p as u32 * (1 + plan[s as usize] as u32) * (100 + 3 * spec.plus as u32) / 100;
        }
        if spec.gear_slot == 0 {
            w += spec.item_level as u32 * WEAPON_LEVEL_WORTH * 12 / 12;
        }
        w
    }

    /// Where a hero of a level fights: the place of the level of the last `STAY_LEVELS` that pays best.
    pub fn place_for(level: u8) -> (u8, i32) {
        Career::place(best_rate(&MEASURED_XP_HOUR, level).0)
    }

    /// The field of a level and the ring radius (px) whose monsters are that level less the margin.
    pub fn place(level: u8) -> (u8, i32) {
        let field = (0..FIELDS.len()).rev().find(|&f| FIELDS[f].bottom <= level).unwrap_or(0) as u8;
        let row = &FIELDS[field as usize];
        let want = level.saturating_sub(RING_LEVEL_BELOW).clamp(row.bottom, row.top);
        let span = (row.top - row.bottom).max(1) as i32;
        let d = (row.top - want) as i32 * LEVEL_RIM_PX / span;
        (field, d.clamp(RING_MIN_PX, RING_MAX_PX))
    }

    /// An UNCOMMON piece of a slot at an item level, the best for her of `MARKET_CHOICE` listings.
    fn market_item(&mut self, slot: u8, level: u16) -> ItemSpec {
        let field = Career::place(level as u8).0;
        let mut best: Option<ItemSpec> = None;
        for _ in 0..MARKET_CHOICE {
            let variant = self.rng.below(BASE_VARIANTS[slot as usize].len() as u64) as u8;
            let lines = roll_lines(&mut self.rng, RARITY_LINES[UNCOMMON as usize], line_value(level, UNCOMMON));
            let spec = ItemSpec {
                base: base_id(slot, field, variant),
                gear_slot: slot,
                item_level: level,
                rarity: UNCOMMON,
                lines,
                sockets: RARITY_SOCKETS[UNCOMMON as usize],
                plus: 0,
                bound: false,
            };
            if best.as_ref().is_none_or(|b| self.worth(&spec) > self.worth(b)) {
                best = Some(spec);
            }
        }
        best.unwrap()
    }

    /// Compression of an outing at her level.
    pub fn k(&self, fast: u64) -> u64 {
        if self.level < FAST_FROM { 1 } else { fast.max(1) }
    }

    /// Back in town after an outing of `played` ticks credited `k` times.
    pub fn town(&mut self, p: &Played, played: u64, k: u64, partied: bool, travel: u64) {
        let band = band_of(self.level);
        let mut book = Book::default();
        let credited = played * k;
        // XP and the level reached (time within the outing interpolated).
        let gained = p.xp * k;
        let start = self.ticks;
        let before = self.xp;
        self.xp += gained;
        self.ticks += credited;
        let new_level = realm_gateway::sheet::level_for_xp(self.xp).min(CLASS_LEVEL_MAX as u16) as u8;
        for l in self.level + 1..=new_level {
            let need = realm_gateway::sheet::xp_to_reach(l as u16) - before;
            self.reached[l as usize] = start + credited * need / gained.max(1);
        }
        // Coin: the haul's coin was banked (or lost to falls).
        book.kills = p.kill_coin * k;
        book.chests = p.chest_coin * k;
        book.fall = p.fall_coin * k;
        self.coin += (p.kill_coin + p.chest_coin).saturating_sub(p.fall_coin) * k;
        // What she drank, k times over, is bought again at the merchant (below, the belt is filled).
        let mut drunk = [0u64; 6];
        for (i, n) in p.potions.iter().enumerate() {
            drunk[i] = n * k;
            self.potions[i] = self.potions[i].saturating_sub(*n);
        }
        // Wear: repair what she wore for what she played (credited) and her falls.
        let minutes = credited / (60 * TICK_HZ as u64);
        for w in self.worn.iter().flatten() {
            book.repair += sinks::repair_cost(w, minutes, p.falls * k);
        }
        // She pays the fare, then what repair she can (the rest of her gear stays worn: nothing is booked unpaid).
        book.travel = travel.min(self.coin);
        self.coin -= book.travel;
        book.repair = book.repair.min(self.coin);
        self.coin -= book.repair;
        // What she found: chest coin is already booked; runes kept; items worn, sold or salvaged.
        let mut items: Vec<ItemSpec> = p.haul.items.clone();
        for f in &p.found {
            match &f.what {
                What::Item(s) => items.push(s.clone()),
                What::Stack(kind, n) if kind.class() == Some(StackClass::Rune) => {
                    for _ in 0..*n {
                        self.runes.push(*kind);
                    }
                }
                What::Stack(kind, n) if *kind == StackKind::material(realm_loot::tables::EMBERS) => self.embers += n,
                _ => {}
            }
        }
        // (rolls were made k times already, see `run`)
        self.embers += p.haul.stacks.get(&StackKind::material(realm_loot::tables::EMBERS).0).copied().unwrap_or(0);
        self.level = new_level.max(self.level);
        // Compressed outings found k times what was rolled; the rolls were made k times already (see `run`).
        for spec in items {
            self.offer(spec, &mut book);
        }
        // The market, when her gear has fallen behind; the weapon first.
        let income = (book.kills + book.chests) / k.max(1);
        for slot in 0..6u8 {
            let behind = self.worn[slot as usize].as_ref().is_none_or(|w| w.item_level + MARKET_LAG <= self.level as u16);
            if !behind {
                continue;
            }
            let spec = self.market_item(slot, self.level as u16);
            let price = prices::item_value(&spec) * MARKET_PRICE_PCT / 100;
            if self.coin >= price + income {
                self.coin -= price;
                let tax = prices::tax_of(price);
                book.tax += tax;
                book.market += price - tax;
                self.offer(spec, &mut book);
            }
        }
        // Runes into empty sockets.
        while let Some(rune) = self.runes.pop() {
            let Some(slot) = (0..6).find(|&s| self.sockets[s].iter().any(|x| x.is_none())) else {
                break;
            };
            let level = self.worn[slot].as_ref().map_or(1, |w| w.item_level) as u64;
            let cost = realm_loot::tables::SOCKET_COIN_PER_LEVEL * level;
            if self.coin < cost {
                self.runes.push(rune);
                break;
            }
            self.coin -= cost;
            book.smith += cost;
            let free = self.sockets[slot].iter().position(|x| x.is_none()).unwrap();
            self.sockets[slot][free] = Some(rune);
        }
        // The belt: what was drunk beyond one outing's worth is paid for as it was bought.
        for (i, &n) in drunk.iter().enumerate() {
            let extra = n - p.potions[i];
            let price = prices::potion_price(i, self.level as u16) * extra;
            let paid = price.min(self.coin);
            self.coin -= paid;
            book.potions += paid;
        }
        for (slot, &pot) in self.belt_plan().iter().enumerate() {
            let carried = POTIONS[pot as usize].carried as u64;
            let same = self.belt_plan()[..slot].iter().filter(|&&q| q == pot).count() as u64;
            let want = carried * (same + 1);
            while self.potions[pot as usize] < want {
                let price = prices::potion_price(pot as usize, self.level as u16);
                if self.coin < price {
                    break;
                }
                self.coin -= price;
                book.potions += price;
                self.potions[pot as usize] += 1;
            }
        }
        // The smith: every piece to the safe steps, the weapon beyond while rich.
        for pass in 0..2 {
            for slot in 0..6usize {
                loop {
                    let Some(w) = self.worn[slot].as_ref() else { break };
                    let cap = if pass == 1 && slot == 0 { SMITH_WEAPON_MAX } else { SMITH_SAFE };
                    if w.plus >= cap {
                        break;
                    }
                    let Some(cost) = smith::upgrade_cost(w) else { break };
                    let rich = if w.plus >= SMITH_SAFE { SMITH_RICH_MUL } else { 1 };
                    if self.embers < cost.embers || self.coin < cost.coin * rich + income {
                        break;
                    }
                    let chance = smith::upgrade_success_pct(w);
                    self.embers -= cost.embers;
                    if self.rng.below(100) < chance as u64 {
                        self.coin -= cost.coin;
                        book.smith += cost.coin;
                        self.worn[slot].as_mut().unwrap().plus += 1;
                    } else {
                        break;
                    }
                }
            }
        }
        let b = &mut self.bands[band];
        b.ticks += credited;
        b.xp += gained;
        b.kills += p.kills * k;
        b.downs += p.downs * k;
        b.falls += p.falls * k;
        b.outings += 1;
        b.partied += partied as u64;
        b.book.add(&book);
    }

    /// An item she found or bought: worn if better and of her level, else sold (COMMON, UNCOMMON) or salvaged.
    fn offer(&mut self, spec: ItemSpec, book: &mut Book) {
        let slot = spec.gear_slot as usize;
        let wearable = spec.item_level <= self.level as u16;
        let better = wearable && self.worn[slot].as_ref().is_none_or(|w| self.worth(&spec) > self.worth(w));
        let old = if better {
            self.sockets[slot] = vec![None; spec.sockets as usize];
            self.worn[slot].replace(spec)
        } else {
            Some(spec)
        };
        if let Some(o) = old {
            if o.rarity < FIRST_KEPT_RARITY {
                let pay = prices::npc_pays(&o);
                self.coin += pay;
                book.merchant += pay;
            } else {
                self.embers += smith::salvage_embers(&o);
            }
        }
    }
}

/// A group in one field copy: careers (by index) who play together (one alone, or a party).
#[derive(Clone, Debug)]
pub struct Group {
    pub members: Vec<usize>,
    pub ring_px: i32,
}

/// One field copy of a round: its field, seed, clock and groups.
#[derive(Clone, Debug)]
pub struct Instance {
    pub field: u8,
    pub seed: u64,
    pub clock: u64,
    pub groups: Vec<Group>,
}

/// Groups of one field copy are put this far apart (px) when the ring has room, in at most this many tries.
pub const GROUP_SPREAD_PX: i64 = 1_500;
const PLACE_TRIES: u32 = 400;

/// Whole-number square root.
pub fn isqrt(v: i64) -> i64 {
    if v <= 0 {
        return 0;
    }
    let mut x = (v as f64).sqrt() as i64;
    while x * x > v {
        x -= 1;
    }
    while (x + 1) * (x + 1) <= v {
        x += 1;
    }
    x
}

/// A secret for the loot rolls of careers (the server's own is never in a test).
const SECRET: u64 = 0xB1_BA1A_9CE5;

/// Plays one instance for `ticks`; returns each member's `Played` in the order of its groups' members.
/// `k` per member is the number of loot rolls a kill gets (compression).
pub fn run(inst: &Instance, sheets: &[(Sheet, u64, u32)], ticks: u32) -> Vec<Played> {
    let monsters = 4_096;
    let mut f = Field::open(inst.field, inst.seed, Config { monsters, threads: 1 });
    f.set_clock(inst.clock);
    let mut bots = Vec::new();
    let mut ids = Vec::new();
    let mut placed: Vec<(i32, i32)> = Vec::new();
    let mut r = inst.seed;
    let mut m = 0usize;
    for group in inst.groups.iter() {
        // Groups spread around their rings: open ground, `GROUP_SPREAD_PX` from every other group if it can be.
        let (mut x, mut y) = (FIELD / 2, FIELD / 2);
        let mut best = -1i64;
        for _ in 0..PLACE_TRIES {
            let a = rng_next(&mut r);
            let (dx, dy) = ((a % 2001) as i64 - 1000, ((a >> 20) % 2001) as i64 - 1000);
            let len = isqrt(dx * dx + dy * dy);
            if len < 100 {
                continue;
            }
            let (px, py) = (FIELD / 2 + (dx * group.ring_px as i64 * SUB as i64 / len) as i32, FIELD / 2 + (dy * group.ring_px as i64 * SUB as i64 / len) as i32);
            if f.terrain().wall(px, py) {
                continue;
            }
            let near = placed.iter().map(|&(qx, qy): &(i32, i32)| isqrt(((qx - px) as i64 / SUB as i64).pow(2) + ((qy - py) as i64 / SUB as i64).pow(2))).min().unwrap_or(i64::MAX);
            if near > best {
                best = near;
                (x, y) = (px, py);
            }
            if near >= GROUP_SPREAD_PX {
                break;
            }
        }
        placed.push((x, y));
        for (k, _) in group.members.iter().enumerate() {
            let (sheet, _, bank) = &sheets[m];
            let (ox, oy) = ((k as i32 % 3) * 16 * SUB, (k as i32 / 3) * 16 * SUB);
            let mut px = (x + ox, y + oy);
            if f.terrain().wall(px.0, px.1) {
                px = (x, y);
            }
            let id = f.join(sheet, &Outing::new(), px.0, px.1);
            let mut plan = if group.members.len() > 1 { Plan::party(group.ring_px) } else { Plan::alone(group.ring_px) };
            plan.bank_coin = *bank;
            bots.push(Bot::new(id, inst.seed ^ m as u64, plan));
            ids.push(id);
            m += 1;
        }
    }
    let mut out: Vec<Played> = (0..ids.len()).map(|_| Played::default()).collect();
    let slot_of = |id: u16| ids.iter().position(|&q| q == id);
    let mut gates: Vec<Vec<RollGate>> = sheets.iter().map(|s| (0..s.1).map(|_| RollGate::new()).collect()).collect();
    let mut coin: Vec<u32> = vec![0; ids.len()];
    let mut last_boss = 0u8;
    let mut inputs = vec![0u16; f.heroes().len()];
    for _ in 0..ticks {
        for (b, &id) in bots.iter_mut().zip(&ids) {
            inputs[id as usize] = b.act(&f);
        }
        f.step(&inputs);
        let tick = f.tick();
        let mut rewarded: Vec<usize> = Vec::new();
        for (index, e) in f.events().iter().enumerate() {
            match *e {
                Event::Xp { hero, amount } => {
                    if let Some(s) = slot_of(hero) {
                        out[s].xp += amount as u64;
                    }
                }
                Event::Down { hero } => {
                    if let Some(s) = slot_of(hero) {
                        out[s].downs += 1;
                    }
                }
                Event::Fallen { hero, coin: lost } => {
                    if let Some(s) = slot_of(hero) {
                        out[s].falls += 1;
                        out[s].fall_coin += lost as u64;
                        let mut rr = Rng::new(mix(inst.seed, tick as u64 * 64 + s as u64));
                        out[s].haul.fall(&mut rr);
                    }
                }
                Event::Potion { hero, slot, .. } => {
                    if let Some(s) = slot_of(hero) {
                        let p = sheets[s].0.belt[slot as usize].0;
                        if (p as usize) < 6 {
                            out[s].potions[p as usize] += 1;
                        }
                    }
                }
                Event::Boss { which, .. } => last_boss = which,
                Event::Kill { first, count, .. } => {
                    let Some(src) = Source::from_kill(e) else { continue };
                    for &q in f.credited(first, count) {
                        let Some(s) = slot_of(q) else { continue };
                        out[s].kills += 1;
                        let luck = f.luck(q).max(0) as u32;
                        for rep in 0..sheets[s].1 {
                            let key = RollKey { field_seed: inst.seed, tick, index: index as u32 | (rep as u32) << 20, slot: q };
                            for found in roll(SECRET, &key, &Credit { luck, drops_percent: 100 }, &src, &mut gates[s][rep as usize]) {
                                if let Some(kept) = out[s].haul.take(found) {
                                    out[s].found.push(kept);
                                }
                            }
                        }
                    }
                }
                Event::Reward { kind, source, level, first, count, .. } => {
                    let src = match kind {
                        R_TIDE_CACHE => Source::TideCache { field: source, level },
                        R_BOSS_CHEST => Source::BossChest { boss: last_boss.min(6), level, first_kill: false },
                        R_WORLD_RELIC => Source::WorldChest { level, top: true },
                        R_WORLD_EPIC => Source::WorldChest { level, top: false },
                        _ => continue,
                    };
                    for &(q, _) in f.rewarded(first, count) {
                        let Some(s) = slot_of(q) else { continue };
                        rewarded.push(s);
                        let key = RollKey { field_seed: inst.seed, tick, index: index as u32, slot: q };
                        for found in roll(SECRET, &key, &Credit { luck: 0, drops_percent: 100 }, &src, &mut RollGate::new()) {
                            match found.what {
                                What::Stack(k, n) if k == StackKind::COIN => out[s].chest_coin += n,
                                _ => out[s].found.push(found),
                            }
                        }
                    }
                }
                _ => {}
            }
        }
        // Coin into the haul: kills (and the core's own chest coin, booked as a chest).
        for (s, &id) in ids.iter().enumerate() {
            let now = f.heroes()[id as usize].coin;
            if now > coin[s] {
                let d = (now - coin[s]) as u64;
                if rewarded.contains(&s) {
                    out[s].chest_coin += d;
                } else {
                    out[s].kill_coin += d;
                }
            }
            coin[s] = now;
        }
    }
    out
}

/// What a career round needs to know.
#[derive(Clone, Copy, Debug)]
pub struct Pace {
    /// Played ticks of an outing.
    pub ticks: u32,
    /// Compression from `FAST_FROM`.
    pub fast: u64,
    /// Threads for the instances of a round.
    pub threads: usize,
}

/// A cohort: careers of every class and job, alone and in parties, that play rounds of outings.
pub struct Cohort {
    pub careers: Vec<Career>,
    pub seed: u64,
    pub round: u64,
}

/// The coin a kill pays at a level, about (for the banking threshold): two XP at level 1, +12% a level.
fn kill_coin(level: u8) -> u32 {
    2 * (100 + POWER_PCT_PER_LEVEL * (level as u32 - 1)) / 100
}

impl Cohort {
    /// `per` careers of each of the ten jobs; races and preferred party sizes in turn.
    pub fn new(seed: u64, per: usize) -> Cohort {
        let mut careers = Vec::new();
        for class in 1..6u8 {
            for second in [false, true] {
                for j in 0..per {
                    let idx = careers.len();
                    let party = PARTY_SIZES[(idx + j) % PARTY_SIZES.len()];
                    careers.push(Career::new(idx, class, second, (idx % 4) as u8, party, seed));
                }
            }
        }
        Cohort { careers, seed, round: 0 }
    }

    pub fn done(&self) -> bool {
        self.careers.iter().all(|c| c.level >= CLASS_LEVEL_MAX)
    }

    /// Played out: every career is 60, or every career still below 60 has `max_hours` credited. Only those below 60
    /// count: one that reached 60 early stops playing, so her hours stop growing (counting her, a career that never
    /// reaches 60 made the cohort play forever).
    pub fn finished(&self, max_hours: u64) -> bool {
        self.careers.iter().filter(|c| c.level < CLASS_LEVEL_MAX).all(|c| c.ticks >= max_hours * crate::balance::TICKS_HOUR)
    }

    /// One round: every career below 60 plays one outing; instances on threads, applied in order.
    pub fn round(&mut self, pace: Pace) {
        let live: Vec<usize> = (0..self.careers.len()).filter(|&i| self.careers[i].level < CLASS_LEVEL_MAX).collect();
        // Groups by field: parties of those who want one (by level), the rest alone.
        let mut by_field: Vec<Vec<usize>> = vec![Vec::new(); FIELDS.len()];
        for &i in &live {
            by_field[Career::place_for(self.careers[i].level).0 as usize].push(i);
        }
        let mut insts: Vec<(Instance, Vec<usize>)> = Vec::new();
        let mut r = mix(self.seed, 0x40_0000 + self.round);
        for (field, list) in by_field.iter().enumerate() {
            // Each outing a career partys with chance `PARTY_PCT` (seeded by round and career), else she goes alone.
            let parties = |i: usize| mix(self.seed ^ 0x9A27, self.round * 1_000 + i as u64) % 100 < PARTY_PCT;
            let mut solo: Vec<usize> = list.iter().copied().filter(|&i| !parties(i)).collect();
            let mut party: Vec<usize> = list.iter().copied().filter(|&i| parties(i)).collect();
            party.sort_by_key(|&i| (self.careers[i].level, i));
            // A party of one is alone this time.
            while !party.is_empty() {
                let want = self.careers[party[0]].party.min(party.len());
                let members: Vec<usize> = party.drain(..want).collect();
                if members.len() == 1 {
                    solo.push(members[0]);
                    continue;
                }
                let lvl = (members.iter().map(|&i| self.careers[i].level as u32).sum::<u32>() / members.len() as u32) as u8;
                insts.push((self.instance(field as u8, &mut r, vec![Group { members: members.clone(), ring_px: Career::place_for(lvl).1 }]), members));
            }
            solo.sort();
            for chunk in solo.chunks(SOLO_PER_FIELD) {
                let groups = chunk.iter().map(|&i| Group { members: vec![i], ring_px: Career::place_for(self.careers[i].level).1 }).collect();
                insts.push((self.instance(field as u8, &mut r, groups), chunk.to_vec()));
            }
        }
        let jobs: Vec<(Instance, Vec<(Sheet, u64, u32)>)> = insts
            .iter()
            .map(|(inst, members)| {
                let sheets = members
                    .iter()
                    .map(|&i| {
                        let c = &self.careers[i];
                        (c.sheet(), c.k(pace.fast), BANK_KILLS * kill_coin(c.level))
                    })
                    .collect();
                (inst.clone(), sheets)
            })
            .collect();
        let results = par_map(&jobs, pace.threads, |(inst, sheets)| run(inst, sheets, pace.ticks));
        for ((inst, members), played) in insts.iter().zip(results) {
            let partied = members.len() > 1 && inst.groups.len() == 1;
            for (&i, p) in members.iter().zip(played) {
                let c = &mut self.careers[i];
                let k = c.k(pace.fast);
                let ring = realm_core::ring_of(FIELD / 2 + inst.groups[0].ring_px * SUB, FIELD / 2);
                let fare = if ring == RING_EDGE { 0 } else { sinks::travel_cost(inst.field, ring) };
                c.town(&p, pace.ticks as u64, k, partied, fare);
            }
        }
        self.round += 1;
    }

    fn instance(&self, field: u8, r: &mut u64, groups: Vec<Group>) -> Instance {
        let seed = rng_next(r);
        // A random moment of the realm's day: tides, bosses and the world boss come as they come.
        let clock = rng_next(r) % (WORLD_EVERY as u64);
        Instance { field, seed, clock, groups }
    }
}

/// `f` over `items` on `threads` threads, results in order.
pub fn par_map<T: Sync, R: Send>(items: &[T], threads: usize, f: impl Fn(&T) -> R + Sync) -> Vec<R> {
    let n = items.len();
    let mut out: Vec<Option<R>> = (0..n).map(|_| None).collect();
    let next = std::sync::atomic::AtomicUsize::new(0);
    let done = std::sync::Mutex::new(&mut out);
    std::thread::scope(|s| {
        for _ in 0..threads.max(1).min(n.max(1)) {
            s.spawn(|| {
                loop {
                    let k = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    if k >= n {
                        break;
                    }
                    let v = f(&items[k]);
                    done.lock().unwrap()[k] = Some(v);
                }
            });
        }
    });
    out.into_iter().map(|v| v.unwrap()).collect()
}
