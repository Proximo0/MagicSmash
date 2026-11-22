//! The economy simulation (job E1's proof): thousands of bots play game days against the real store and the real
//! economy door. Each day a bot plays (an outing: coin, items, embers, materials, levels), and on town visits
//! sells to the merchant, lists on the market, buys upgrades, equips, mails and trades, and spends at the smith.
//! The faucets are the loot module's own (`realm_loot::gear` for items) and the core's coin per kill; every
//! change goes through `Economy` or the store, so the store's `verify` (a replay of the whole ledger) is the proof
//! that nothing was copied. Prices, coin supply and the guards (self-found and trade-locked bots that try to
//! trade and must be refused) are measured and printed. Run it with `realm-economy`; `tests/economy_sim.rs` is the
//! 2,000-bot, 90-day run.
//!
//! Determinism: with `threads == 1` a run is a function of the seed. With more threads bots interleave their
//! market actions, so the numbers vary a little between runs; the bands below leave room for that.

use super::market::class_of;
use super::prices::*;
use super::wire::*;
use super::{Economy, Sale};
use crate::proto::{code, Resp, Thing};
use realm_core::tables::FIELDS;
use realm_loot::gear::{item_hundredths, make_item, roll_rarity};
use realm_loot::rng::{mix, Rng};
use realm_loot::smith::upgrade_cost;
use realm_loot::Smith;
use realm_store::*;
use std::collections::{BTreeMap, HashMap, VecDeque};
use std::path::PathBuf;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Instant;

// ---- the bands the run is judged against (docs/realm/economy.md part 2 says why)
/// A class's median sale price, as a percent of the item's value, must stay between these over every 30-day window
/// with at least `MIN_SALES` sales in the class.
pub const BAND_LO_PCT: u64 = 30;
pub const BAND_HI_PCT: u64 = 400;
/// The median of one window against the window before: at most this many times up, or down (percent: 200 = double).
pub const DRIFT_MAX_PCT: u64 = 200;
pub const WINDOW_DAYS: u32 = 30;
/// A median of fewer sales than this is noise (a class of ten sales swings on one rich buyer).
pub const MIN_SALES: usize = 30;

// ---- how a bot lives
pub const KILLS_PER_HOUR: u64 = 300;
pub const ACTIVE_PCT: u64 = 70;
pub const VISIT_PCT_PER_ROUND: u64 = 12;
/// Item rolls per ten thousand kills (the contract's 1 in 400 for monsters plus the elites' share).
pub const ITEM_PER_10K_KILLS: u64 = 35;
pub const LIST_MIN_VALUE: u64 = 60;
/// Items worth less than this are left in the bag (not worth a bot's visit).
pub const JUNK_VALUE: u64 = 25;
pub const SELF_FOUND_PCT: u64 = 5;
pub const FLIPPER_PCT: u64 = 10;
const EPOCH: Millis = 1_800_000_000_000;

#[derive(Clone, Debug)]
pub struct Config {
    pub bots: usize,
    pub days: u32,
    pub seed: u64,
    pub threads: usize,
    pub db: PathBuf,
    /// Bots whose accounts are TRADE_LOCKED from the start (farms that keep trying).
    pub farms: usize,
    pub quiet: bool,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Kind {
    Normal,
    SelfFound,
    Farm,
}

struct Bot {
    idx: usize,
    account: i64,
    hero: i64,
    kind: Kind,
    level: u16,
    prog: u32,
    rng: Rng,
    potions: u64,
    /// How dear she prices next to the market, percent.
    greed: u64,
    listed: Vec<(i64, i64)>,
    /// Items she has listed before: the last price and how many times.
    asks: HashMap<i64, (u64, u8)>,
    flipper: bool,
}

fn name_of(idx: usize) -> String {
    format!("Bot{idx}")
}

fn power(it: &Item) -> u64 {
    item_hundredths(&it.spec, &it.socketed).iter().map(|v| *v as u64).sum()
}

fn kill_coin(level: u16) -> u64 {
    3 * (100 + 12 * (level as u64 - 1)) / 100
}

struct Counters(Mutex<BTreeMap<String, u64>>);

impl Counters {
    fn add(&self, k: &str, n: u64) {
        *self.0.lock().unwrap().entry(k.to_string()).or_insert(0) += n;
    }
}

struct Sim {
    cfg: Config,
    store: Arc<SqliteStore>,
    eco: Arc<Economy>,
    bots: Vec<Mutex<Bot>>,
    normal: Vec<usize>,
    ids: Vec<(i64, i64)>,
    /// Last sale prices as a percent of value, by class (the bots' idea of a fair price).
    ratios: Mutex<HashMap<(u8, u8), VecDeque<u64>>>,
    now: AtomicI64,
    count: Counters,
    secret: u64,
}

#[derive(Clone, Debug, Default)]
pub struct SupplyRow {
    pub day: u32,
    pub supply: u64,
    pub per_bot: u64,
    pub minted: u64,
    pub sunk: u64,
}

#[derive(Clone, Debug)]
pub struct ClassRow {
    pub rarity: u8,
    pub band: u8,
    /// Median percent of value in each 30-day window (None when the window had too few sales) and the sales.
    pub windows: Vec<(Option<u64>, usize)>,
}

#[derive(Clone, Debug, Default)]
pub struct Report {
    pub bots: usize,
    pub days: u32,
    pub secs: f64,
    pub supply: Vec<SupplyRow>,
    pub classes: Vec<ClassRow>,
    pub totals: super::Totals,
    pub counters: BTreeMap<String, u64>,
    pub flows: Vec<(String, String, bool, i64, i64)>,
    pub items_live: i64,
    pub ledger_rows: i64,
    pub problems: Vec<String>,
    pub ember_unit: Option<(u64, u64)>,
    pub repeat_pairs: usize,
    pub farm_hops: usize,
}

impl Report {
    pub fn print(&self) {
        println!("ECONOMY {} bots, {} days, {:.1} s, {} items live, {} ledger rows", self.bots, self.days, self.secs, self.items_live, self.ledger_rows);
        println!("coin supply (all bags, banks, mail), every 5 days:");
        println!("  day |     supply | per bot |   minted (cum) |    sunk (cum)");
        for r in &self.supply {
            println!("  {:>3} | {:>10} | {:>7} | {:>14} | {:>13}", r.day, r.supply, r.per_bot, r.minted, r.sunk);
        }
        println!("coin flows by ledger row (op, reason, minted?, rows, coin):");
        for (op, reason, minted, rows, n) in &self.flows {
            if op == "TRANSFER" {
                continue;
            }
            println!("  {op:<9} {reason:<14} {:<6} {rows:>9} {n:>14}", if *minted { "minted" } else { "" });
        }
        let t = &self.totals;
        println!(
            "market: {} listed, {} sold for {} coin, {} cancelled, {} expired; tax {} fees {} postage {}; npc paid {} took {}; trades {}, letters {} (cod {}), buybacks {}",
            t.listed, t.sales, t.volume, t.cancelled, t.expired, t.tax, t.fees, t.postage, t.npc_paid, t.npc_took, t.trades, t.letters, t.cod_volume, t.buybacks
        );
        println!("median sale price, percent of item value, per class (rarity, level band) per 30-day window (sales):");
        for c in &self.classes {
            let w: Vec<String> = c.windows.iter().map(|(m, n)| format!("{}% ({n})", m.map_or("-".to_string(), |v| v.to_string()))).collect();
            println!("  {} L{:>2}-{:>2}: {}", realm_loot::tables::RARITY_NAMES[c.rarity as usize], c.band as u32 * 10 + 1, c.band as u32 * 10 + 10, w.join("  "));
        }
        if let Some((n, m)) = self.ember_unit {
            println!("embers on the market: {n} sales, median {m} coin each (merchant buys at {EMBER_SELL})");
        }
        println!("guards: {} account pairs traded 5+ times, {} onward hops from the trade-locked farms", self.repeat_pairs, self.farm_hops);
        let c: Vec<String> = self.counters.iter().map(|(k, v)| format!("{k}={v}")).collect();
        println!("actions: {}", c.join(" "));
    }
}

fn median(v: &mut Vec<u64>) -> u64 {
    v.sort_unstable();
    v[v.len() / 2]
}

impl Sim {
    fn me(&self, b: &Bot, now: Millis) -> Meta {
        let mut m = self.eco.meta(now);
        m.actor = b.account;
        m
    }

    fn call(&self, account: i64, now: Millis, r: EReq) -> std::result::Result<EResp, u16> {
        let name = format!("{r:?}");
        let name = name.split(|c: char| !c.is_alphanumeric()).next().unwrap_or("").to_string();
        let t0 = Instant::now();
        let resp = self.eco.handle(account, r, now);
        self.count.add(&format!("us_{name}"), t0.elapsed().as_micros() as u64);
        self.count.add(&format!("n_{name}"), 1);
        match resp {
            Resp::Econ(e) => Ok(e),
            Resp::Err { code, .. } => {
                self.count.add(&format!("err{code}"), 1);
                Err(code)
            }
            _ => Err(0),
        }
    }

    fn fair_pct(&self, it: &Item) -> u64 {
        let c = class_of(it.spec.rarity, it.spec.item_level);
        let r = self.ratios.lock().unwrap();
        match r.get(&c) {
            Some(d) if d.len() >= 4 => {
                let mut v: Vec<u64> = d.iter().copied().collect();
                median(&mut v)
            }
            _ => 200,
        }
    }

    // ---- the day

    /// Every active bot plays: one outing each, all in one store transaction per 500.
    fn play_stage(&self, now: Millis, day: u32) {
        let mut reqs = Vec::new();
        let mut who = Vec::new();
        for (i, b) in self.bots.iter().enumerate() {
            let mut b = b.lock().unwrap();
            if b.rng.below(100) >= ACTIVE_PCT {
                continue;
            }
            let hours = 1 + b.rng.below(2);
            let kills = KILLS_PER_HOUR * hours;
            let level = b.level;
            let field = field_of(level) as u8;
            let n = (kills * ITEM_PER_10K_KILLS + b.rng.below(10_000)) / 10_000;
            let mut items = Vec::new();
            for _ in 0..n {
                let lvl = (level as u64 - b.rng.below(3).min(level as u64 - 1)).max(1) as u8;
                let r = roll_rarity(&mut b.rng, 0);
                items.push(make_item(&mut b.rng, field, lvl, r));
            }
            let scale = 100 + 6 * (level as u64 - 1);
            let embers = kills * 185 / 1000 * scale / 100;
            let mats = kills / 100;
            let mut stacks = vec![(StackKind::material(0), embers)];
            if mats > 0 {
                stacks.push((StackKind::material(1 + field as u32), mats));
            }
            let used = b.potions.min(2 * hours);
            b.potions -= used;
            let per_hour = (30u64).saturating_sub(level as u64 / 3).max(5);
            b.prog += (hours * per_hour) as u32;
            let mut levels = (b.prog / 100) as u16;
            b.prog %= 100;
            if b.level + levels > 60 {
                levels = 60 - b.level;
            }
            b.level += levels;
            let delta = OutingDelta {
                coin: kills * kill_coin(level),
                xp: 0,
                levels,
                items,
                stacks,
                potions_used: if used > 0 { vec![(StackKind::potion(0), used)] } else { vec![] },
                waystone: None,
            };
            let m = self.eco.meta(now);
            reqs.push(Request { id: m.id, actor: 0, now, cmd: Cmd::Outing { hero: b.hero, delta } });
            who.push(i);
        }
        let _ = day;
        for chunk in reqs.chunks(500) {
            let res = self.store.submit_batch(chunk.to_vec());
            for r in res {
                if let Err(e) = r {
                    self.count.add("outing_failed", 1);
                    if self.count.0.lock().unwrap().get("outing_failed").copied().unwrap_or(0) < 5 {
                        eprintln!("outing failed: {e:?}");
                    }
                }
            }
        }
        self.count.add("outings", reqs.len() as u64);
    }

    fn town_stage(&self, now: Millis) {
        let n = self.bots.len();
        let threads = self.cfg.threads.max(1);
        std::thread::scope(|s| {
            for t in 0..threads {
                s.spawn(move || {
                    let mut i = t;
                    while i < n {
                        let mut b = self.bots[i].lock().unwrap();
                        if b.rng.below(100) < VISIT_PCT_PER_ROUND {
                            self.visit(&mut b, now);
                        }
                        drop(b);
                        i += threads;
                    }
                });
            }
        });
    }

    fn drain_sales(&self, day: u32, all: &mut Vec<(u32, Sale)>) {
        let sales = self.eco.take_sales();
        let mut r = self.ratios.lock().unwrap();
        for s in sales {
            if s.value > 0 {
                let d = r.entry(class_of(s.rarity, s.level)).or_default();
                d.push_back(s.price * 100 / s.value);
                while d.len() > 40 {
                    d.pop_front();
                }
            }
            all.push((day, s));
        }
    }

    // ---- one visit to town

    fn visit(&self, b: &mut Bot, now: Millis) {
        self.count.add("visits", 1);
        let hero = b.hero;
        let mut budget = 22i32;
        // what came back in the mail (expired listings, refused letters) goes into the bag
        if let Ok(mail) = self.store.items_at(PlaceKind::Mail, hero) {
            for it in mail.iter().take(6) {
                let m = self.me(b, now);
                let _ = self.store.move_item(m, it.id, Dest::bag(hero));
            }
        }
        // what happened to the listings
        if b.kind == Kind::Normal && !b.listed.is_empty() {
            if let Ok(EResp::Listings(mine)) = self.call(b.account, now, EReq::MarketMine { hero }) {
                let open: Vec<i64> = mine.iter().map(|l| l.id).collect();
                let listed = std::mem::take(&mut b.listed);
                for (id, item) in listed {
                    if open.contains(&id) {
                        b.listed.push((id, item));
                    } else {
                        match self.store.item(item) {
                            Ok(Some(it)) if it.place.kind == PlaceKind::Mail => b.greed = (b.greed * 92 / 100).max(40),
                            Ok(Some(_)) => b.greed = (b.greed * 108 / 100).min(300),
                            _ => b.greed = (b.greed * 108 / 100).min(300),
                        }
                    }
                }
            }
        }
        let level = b.level;
        let mut bag = self.store.items_at(PlaceKind::Bag, hero).unwrap_or_default();
        let mut worn: Vec<Option<Item>> = vec![None; 6];
        for it in self.store.items_at(PlaceKind::Worn, hero).unwrap_or_default() {
            let s = it.spec.gear_slot as usize;
            worn[s] = Some(it);
        }
        // equip what is better
        bag.sort_by_key(|i| i.id);
        let mut i = 0;
        while i < bag.len() && budget > 0 {
            let it = bag[i].clone();
            let s = it.spec.gear_slot as usize;
            let better = it.spec.item_level <= level && worn[s].as_ref().is_none_or(|w| power(&it) * 100 > power(w) * 105);
            if better {
                budget -= 2;
                if let Some(old) = worn[s].clone() {
                    let m = self.me(b, now);
                    if let Ok(p) = self.store.move_item(m, old.id, Dest::bag(hero)) {
                        let mut o = old.clone();
                        o.place = p;
                        worn[s] = None;
                        bag.push(o);
                    } else {
                        i += 1;
                        continue;
                    }
                }
                let m = self.me(b, now);
                if self.store.move_item(m, it.id, Dest::any(PlaceKind::Worn, hero)).is_ok() {
                    worn[s] = Some(it);
                    bag.remove(i);
                    self.count.add("equips", 1);
                    continue;
                }
            }
            i += 1;
        }
        // sell, list or keep each of the rest
        let mut open = b.listed.len();
        let mut new_listings = 0;
        let mut sold_junk = 0;
        for it in bag.iter().take(14) {
            if budget <= 0 {
                break;
            }
            let value = item_value(&it.spec);
            if b.kind == Kind::Normal && value >= LIST_MIN_VALUE && open < 15 && new_listings < 3 {
                let tried = b.asks.get(&it.id).copied();
                // an item that did not sell is tried again at 88% of the last price, now and then, and after
                // three tries goes to the merchant
                let skip = tried.is_some_and(|(_, n)| n >= 3) || (tried.is_some() && b.rng.below(100) < 60);
                if !skip {
                    let fair = value * self.fair_pct(it) / 100;
                    let jitter = 90 + b.rng.below(26);
                    let mut price = fair * b.greed / 100 * jitter / 100;
                    if let Some((a, _)) = tried {
                        price = a * 88 / 100;
                    }
                    price = price.min(item_price_cap(&it.spec));
                    let floor = npc_pays(&it.spec) * 130 / 100;
                    if price > floor {
                        budget -= 1;
                        new_listings += 1;
                        if let Ok(EResp::Listed { id, .. }) = self.call(b.account, now, EReq::MarketList { hero, what: Thing::Item(it.id), price, hours: HOURS[b.rng.below(3) as usize] }) {
                            b.listed.push((id, it.id));
                            b.asks.insert(it.id, (price, tried.map_or(1, |(_, n)| n + 1)));
                            open += 1;
                            self.count.add("listings", 1);
                        }
                        continue;
                    }
                } else if tried.is_some_and(|(_, n)| n < 3) {
                    continue;
                }
            }
            if sold_junk < 3 && value >= JUNK_VALUE {
                sold_junk += 1;
                budget -= 1;
                if self.call(b.account, now, EReq::MerchantSell { hero, what: Thing::Item(it.id) }).is_ok() {
                    self.count.add("npc_sells", 1);
                }
            }
        }
        // potions for the next outings
        if b.potions < 4 && budget > 0 {
            budget -= 1;
            if self.call(b.account, now, EReq::MerchantBuy { hero, offer: 0, count: 8 }).is_ok() {
                b.potions += 8;
            }
        }
        match b.kind {
            Kind::Normal => self.buy_side(b, now, &mut budget, &worn),
            Kind::SelfFound => self.forbidden(b, now, &bag),
            Kind::Farm => self.forbidden(b, now, &bag),
        }
        // embers: the surplus is sold to the merchant by the piece
        let embers = self.store.stack(Owner::bag(hero), StackKind::material(0)).unwrap_or(0);
        let keep = 60 + 4 * level as u64;
        if embers > keep + 40 && budget > 0 {
            if b.kind == Kind::Normal && b.rng.below(100) < 50 && open < 15 {
                let n = embers - keep;
                let price = (n * ember_price(level) * (50 + b.rng.below(30)) / 100).max(1);
                if self.call(b.account, now, EReq::MarketList { hero, what: Thing::Stack(1000, n), price, hours: 24 }).is_ok() {
                    self.count.add("ember_listings", 1);
                }
            } else {
                let _ = self.call(b.account, now, EReq::MerchantSell { hero, what: Thing::Stack(1000, embers - keep) });
            }
        }
        if b.kind != Kind::SelfFound || true {
            self.smith_step(b, now, &worn);
        }
    }

    /// A bot that cannot trade tries, now and then, and must be refused every time.
    fn forbidden(&self, b: &mut Bot, now: Millis, bag: &[Item]) {
        if b.rng.below(100) >= 30 || self.normal.is_empty() {
            return;
        }
        let Some(it) = bag.first() else { return };
        let (pa, ph) = {
            let p = self.normal[b.rng.below(self.normal.len() as u64) as usize];
            self.ids[p]
        };
        let _ = pa;
        let _ = ph;
        let mut tried = 0;
        let mut check = |what: &str, r: std::result::Result<EResp, u16>| {
            tried += 1;
            match r {
                Err(c) if c == code::REFUSED => self.count.add("refused_ok", 1),
                Err(_) => self.count.add(&format!("blocked_{what}"), 1),
                Ok(_) => self.count.add("GUARD_BROKEN", 1),
            }
        };
        check("list", self.call(b.account, now, EReq::MarketList { hero: b.hero, what: Thing::Item(it.id), price: 100, hours: 12 }));
        let target = name_of(self.normal[b.rng.below(self.normal.len() as u64) as usize]);
        check("letter", self.call(b.account, now, EReq::LetterSend { hero: b.hero, to_name: target, text: "gift".into(), things: vec![Thing::Item(it.id)], cod: 0 }));
        let _ = tried;
    }

    // ---- buying

    fn buy_side(&self, b: &mut Bot, now: Millis, budget: &mut i32, worn: &[Option<Item>]) {
        let hero = b.hero;
        let level = b.level;
        let coin = self.eco.coin(hero);
        if *budget <= 2 || coin < 50 {
            return;
        }
        // the weakest slot, or any
        let pw = |s: usize| worn[s].as_ref().map_or(0, power);
        let slot = if b.rng.below(100) < 70 { (0..6).min_by_key(|s| pw(*s)).unwrap() } else { b.rng.below(6) as usize };
        let q = Search { gear_slot: slot as u8, rarity_min: 1, level_min: level.saturating_sub(6).max(1), level_max: level, stack: 0, price_max: coin * 40 / 100, offset: 0 };
        *budget -= 1;
        let Ok(EResp::Listings(found)) = self.call(b.account, now, EReq::MarketSearch { hero, q }) else { return };
        let old = pw(slot);
        let mut best: Option<(i64, i64, i64)> = None;
        for l in &found {
            let (Some(e), false) = (&l.item, l.mine) else { continue };
            let new = e.info.lines.iter().map(|(_, p)| *p as u64 * (100 + 3 * e.plus as u64)).sum::<u64>();
            let spec = ItemSpec { base: e.info.base, gear_slot: e.info.gear_slot, item_level: e.info.level, rarity: e.info.rarity, lines: e.info.lines.clone(), sockets: e.info.sockets, plus: e.plus, bound: e.bound };
            let value = item_value(&spec);
            let gain = if new > old { (new - old) * 100 / old.max(1) } else { 0 };
            let flip = b.flipper && l.price * 100 < value * self.fair_pct_of(&spec) / 100 * 60 / 100 && self.has_board(&spec);
            if gain <= 3 && !flip {
                continue;
            }
            // she pays more for a better item, and more when she has coin to burn (up to double)
            let rich = 100 + (coin / (20 * value.max(1))).min(100);
            let wtp = if gain > 3 { value * (100 + 2 * gain.min(150)) / 100 * rich / 100 } else { value * self.fair_pct_of(&spec) / 100 * 90 / 100 };
            if l.price > wtp || l.price > coin * 40 / 100 {
                continue;
            }
            let surplus = (wtp - l.price) as i64 * 1000 / wtp.max(1) as i64;
            if best.is_none_or(|(_, _, s)| surplus > s) {
                best = Some((l.id, l.item.as_ref().unwrap().info.id, surplus));
            }
        }
        if let Some((listing, item, _)) = best {
            *budget -= 3;
            if self.call(b.account, now, EReq::MarketBuy { hero, listing }).is_ok() {
                self.count.add("buys", 1);
                let m = self.me(b, now);
                if self.store.move_item(m, item, Dest::any(PlaceKind::Worn, hero)).is_ok() {
                    self.count.add("equips", 1);
                } else if let Ok(Some(it)) = self.store.item(item) {
                    // a flip: put it up again, a little under the fair price
                    let value = item_value(&it.spec);
                    let price = value * self.fair_pct(&it) / 100 * 95 / 100;
                    if price > npc_pays(&it.spec) * 130 / 100 && b.listed.len() < 15 {
                        if let Ok(EResp::Listed { id, .. }) = self.call(b.account, now, EReq::MarketList { hero, what: Thing::Item(item), price, hours: 24 }) {
                            b.listed.push((id, item));
                            b.asks.insert(item, (price, 1));
                            self.count.add("flips", 1);
                        }
                    }
                }
            }
        }
        // letters waiting: free gifts are taken; cash on delivery only when worth it
        if *budget > 4 && b.rng.below(100) < 50 {
            *budget -= 1;
            if let Ok(EResp::Letters(inbox)) = self.call(b.account, now, EReq::Inbox { hero }) {
                for l in inbox.iter().take(3) {
                    let ok = if l.cod == 0 {
                        true
                    } else {
                        let value: u64 = l.items.iter().map(|e| item_value(&ItemSpec { base: e.info.base, gear_slot: e.info.gear_slot, item_level: e.info.level, rarity: e.info.rarity, lines: e.info.lines.clone(), sockets: e.info.sockets, plus: e.plus, bound: e.bound })).sum();
                        l.cod * 100 <= value * 150 && l.cod <= self.eco.coin(hero)
                    };
                    *budget -= 1;
                    if ok {
                        if self.call(b.account, now, EReq::LetterTake { hero, letter: l.id }).is_ok() {
                            self.count.add("letters_taken", 1);
                        }
                    } else if self.call(b.account, now, EReq::LetterRefuse { hero, letter: l.id }).is_ok() {
                        self.count.add("letters_refused", 1);
                    }
                }
            }
        }
        // now and then: a letter to a friend, or a trade at hand
        if *budget > 6 && self.normal.len() > 2 {
            let roll = b.rng.below(100);
            if roll < 4 {
                self.send_letter(b, now, budget);
            } else if roll < 7 {
                self.trade(b, now, budget);
            }
        }
    }

    fn fair_pct_of(&self, spec: &ItemSpec) -> u64 {
        let c = class_of(spec.rarity, spec.item_level);
        let r = self.ratios.lock().unwrap();
        match r.get(&c) {
            Some(d) if d.len() >= 4 => {
                let mut v: Vec<u64> = d.iter().copied().collect();
                median(&mut v)
            }
            _ => 200,
        }
    }

    fn has_board(&self, spec: &ItemSpec) -> bool {
        let c = class_of(spec.rarity, spec.item_level);
        self.ratios.lock().unwrap().get(&c).is_some_and(|d| d.len() >= 8)
    }

    fn pick_partner(&self, b: &mut Bot) -> Option<usize> {
        for _ in 0..4 {
            let p = self.normal[b.rng.below(self.normal.len() as u64) as usize];
            if p != b.idx {
                return Some(p);
            }
        }
        None
    }

    fn sale_worthy(&self, b: &Bot) -> Option<Item> {
        let bag = self.store.items_at(PlaceKind::Bag, b.hero).ok()?;
        bag.into_iter().filter(|i| item_value(&i.spec) >= LIST_MIN_VALUE).max_by_key(|i| item_value(&i.spec))
    }

    fn send_letter(&self, b: &mut Bot, now: Millis, budget: &mut i32) {
        let Some(p) = self.pick_partner(b) else { return };
        *budget -= 2;
        if b.rng.below(100) < 50 {
            // a gift of embers
            let n = self.store.stack(Owner::bag(b.hero), StackKind::material(0)).unwrap_or(0);
            if n > 120 {
                let _ = self.call(b.account, now, EReq::LetterSend { hero: b.hero, to_name: name_of(p), text: "for the smith".into(), things: vec![Thing::Stack(1000, 20)], cod: 0 });
                self.count.add("gift_letters", 1);
            }
        } else if let Some(it) = self.sale_worthy(b) {
            let cod = (item_value(&it.spec) * self.fair_pct(&it) / 100 * 90 / 100).max(2);
            if self.call(b.account, now, EReq::LetterSend { hero: b.hero, to_name: name_of(p), text: "cash on delivery".into(), things: vec![Thing::Item(it.id)], cod }).is_ok() {
                self.count.add("cod_letters", 1);
            }
        }
    }

    /// An item for coin, hand to hand: invite, accept, both offer, both confirm the same version.
    fn trade(&self, b: &mut Bot, now: Millis, budget: &mut i32) {
        let Some(p) = self.pick_partner(b) else { return };
        let Some(it) = self.sale_worthy(b) else { return };
        let (pacc, phero) = self.ids[p];
        let price = (item_value(&it.spec) * self.fair_pct(&it) / 100 * 95 / 100).max(2);
        if self.eco.coin(phero) < price {
            return;
        }
        *budget -= 5;
        let me = (b.account, b.hero);
        let Ok(EResp::Trade(v)) = self.call(me.0, now, EReq::TradeInvite { hero: me.1, with_name: name_of(p) }) else { return };
        let s = v.session;
        let t2 = now + CONFIRM_DELAY_MS + 500;
        let run = || -> std::result::Result<(), u16> {
            self.call(pacc, now, EReq::TradeAccept { hero: phero, session: s })?;
            self.call(me.0, now, EReq::TradeOffer { hero: me.1, session: s, items: vec![it.id], stacks: vec![] })?;
            let EResp::Trade(v) = self.call(pacc, now, EReq::TradeOffer { hero: phero, session: s, items: vec![], stacks: vec![(1, price)] })? else { return Err(0) };
            self.call(me.0, t2, EReq::TradeConfirm { hero: me.1, session: s, version: v.version })?;
            self.call(pacc, t2, EReq::TradeConfirm { hero: phero, session: s, version: v.version })?;
            Ok(())
        };
        match run() {
            Ok(()) => self.count.add("trades", 1),
            Err(_) => {
                let _ = self.call(me.0, t2, EReq::TradeCancel { hero: me.1, session: s });
            }
        }
    }

    // ---- the smith

    /// A rich bot raises her weakest worn piece a step: take it off, the smith, put it on. Short of embers, a
    /// very rich one buys them from the merchant (a coin sink).
    fn smith_step(&self, b: &mut Bot, now: Millis, worn: &[Option<Item>]) {
        let hero = b.hero;
        let coin = self.eco.coin(hero);
        let embers = self.store.stack(Owner::bag(hero), StackKind::material(0)).unwrap_or(0);
        let mut pick: Option<(&Item, realm_loot::Cost)> = None;
        for w in worn.iter().flatten() {
            if w.origin_account != b.account {
                continue;
            }
            if let Some(c) = upgrade_cost(&w.spec) {
                if c.coin * 3 <= coin && pick.as_ref().is_none_or(|(p, _)| w.spec.plus < p.spec.plus) {
                    pick = Some((w, c));
                }
            }
        }
        let Some((w, c)) = pick else { return };
        if c.embers > embers {
            let need = (c.embers - embers).min(DAILY_EMBERS as u64);
            if coin < c.coin * 12 + need * ember_price(b.level) || self.call(b.account, now, EReq::MerchantBuy { hero, offer: super::merchant::OFFER_EMBERS, count: need as u32 }).is_err() {
                return;
            }
        }
        let m = self.me(b, now);
        let Ok(_) = self.store.move_item(m, w.id, Dest::bag(hero)) else { return };
        let smith = Smith::new(&*self.store, self.secret);
        let mut item = w.id;
        let mut spec = w.spec.clone();
        for _ in 0..4 {
            let Some(c) = upgrade_cost(&spec) else { break };
            let have = self.eco.coin(hero);
            let e = self.store.stack(Owner::bag(hero), StackKind::material(0)).unwrap_or(0);
            if c.coin * 3 > have || c.embers > e {
                break;
            }
            match smith.upgrade(self.eco.meta(now), hero, item) {
                Ok(u) => {
                    self.count.add(if u.success { "upgrades" } else { "upgrade_fails" }, 1);
                    item = u.item;
                    spec.plus = u.plus;
                }
                Err(_) => break,
            }
        }
        let m = self.me(b, now);
        let _ = self.store.move_item(m, item, Dest::any(PlaceKind::Worn, hero));
    }
}

/// Runs the simulation and judges it. `Report::failures` lists what broke the bands or the guards.
pub fn run(cfg: &Config) -> Report {
    let started = Instant::now();
    for s in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{s}", cfg.db.display()));
    }
    let store = Arc::new(SqliteStore::open_with(&cfg.db, Options { durable: false, ..Default::default() }).expect("store"));
    let eco = Economy::new(store.clone());
    let n = cfg.bots;
    // accounts and heroes, in batches
    let meta0 = eco.meta(EPOCH);
    let mut accounts = Vec::with_capacity(n);
    for chunk in (0..n).collect::<Vec<_>>().chunks(500) {
        let reqs: Vec<Request> = chunk.iter().map(|i| Request { id: eco.meta(EPOCH).id, actor: 0, now: EPOCH, cmd: Cmd::AccountByDevName { name: format!("acct{i}") } }).collect();
        for r in store.submit_batch(reqs) {
            let Ok(Reply::Account(a)) = r else { panic!("account: {r:?}") };
            accounts.push(a);
        }
    }
    let _ = meta0;
    let mut kinds = Vec::with_capacity(n);
    let mut rng = Rng::new(mix(cfg.seed, 0xEC0));
    for i in 0..n {
        kinds.push(if i < cfg.farms { Kind::Farm } else if rng.below(100) < SELF_FOUND_PCT { Kind::SelfFound } else { Kind::Normal });
    }
    let mut heroes = Vec::with_capacity(n);
    for chunk in (0..n).collect::<Vec<_>>().chunks(500) {
        let reqs: Vec<Request> = chunk
            .iter()
            .map(|&i| Request {
                id: eco.meta(EPOCH).id,
                actor: 0,
                now: EPOCH,
                cmd: Cmd::HeroCreate { account: accounts[i], name: name_of(i), race: (i % 4) as u8, class: 1 + (i % 5) as u8, look: 0, self_found: kinds[i] == Kind::SelfFound },
            })
            .collect();
        for r in store.submit_batch(reqs) {
            let Ok(Reply::Hero(h)) = r else { panic!("hero: {r:?}") };
            heroes.push(h);
        }
    }
    let mut levels = Vec::with_capacity(n);
    for chunk in (0..n).collect::<Vec<_>>().chunks(500) {
        let reqs: Vec<Request> = chunk
            .iter()
            .map(|&i| {
                let lv = 1 + (mix(cfg.seed, i as u64) % 40) as u16;
                levels.push(lv);
                Request { id: eco.meta(EPOCH).id, actor: 0, now: EPOCH, cmd: Cmd::Outing { hero: heroes[i], delta: OutingDelta { coin: 300, levels: lv - 1, ..Default::default() } } }
            })
            .collect();
        for r in store.submit_batch(reqs) {
            r.expect("start");
        }
    }
    let farm_accounts: Vec<i64> = accounts.iter().take(cfg.farms).copied().collect();
    if !farm_accounts.is_empty() {
        let ch = farm_accounts.iter().map(|a| FlagChange { account: *a, flags: flags::TRADE_LOCKED, drops_percent: 100, banned_until: None }).collect();
        store.apply_flags(eco.meta(EPOCH), ch, "farm").expect("flags");
    }
    let (tx, _rx) = std::sync::mpsc::channel();
    let mut bots = Vec::with_capacity(n);
    let mut normal = Vec::new();
    for i in 0..n {
        if kinds[i] == Kind::Normal {
            normal.push(i);
        }
        eco.attach(heroes[i], 1, tx.clone());
        bots.push(Mutex::new(Bot {
            idx: i,
            account: accounts[i],
            hero: heroes[i],
            kind: kinds[i],
            level: levels[i],
            prog: 0,
            rng: Rng::new(mix(cfg.seed, 1000 + i as u64)),
            potions: 0,
            greed: 100,
            listed: Vec::new(),
            asks: HashMap::new(),
            flipper: mix(cfg.seed, 77 + i as u64) % 100 < FLIPPER_PCT,
        }));
    }
    let sim = Sim {
        cfg: cfg.clone(),
        store: store.clone(),
        eco: eco.clone(),
        bots,
        normal,
        ids: accounts.iter().zip(&heroes).map(|(a, h)| (*a, *h)).collect(),
        ratios: Mutex::new(HashMap::new()),
        now: AtomicI64::new(EPOCH),
        count: Counters(Mutex::new(BTreeMap::new())),
        secret: cfg.seed ^ 0x5EC,
    };
    let _ = FIELDS.len();

    let mut phase_secs = [0f64; 4];
    let mut all: Vec<(u32, Sale)> = Vec::new();
    let mut report = Report { bots: n, days: cfg.days, ..Default::default() };
    for day in 0..cfg.days {
        let t0 = EPOCH + day as i64 * MS_DAY;
        for (round, off) in [(0, 0i64), (1, 6 * MS_HOUR), (2, 14 * MS_HOUR)] {
            let now = t0 + off;
            sim.now.store(now, Ordering::Relaxed);
            let a = Instant::now();
            sim.eco.sweep(now);
            let b = Instant::now();
            if round == 0 {
                sim.play_stage(now, day);
            } else {
                sim.town_stage(now);
            }
            let c = Instant::now();
            sim.drain_sales(day, &mut all);
            let spent = &mut phase_secs[round];
            *spent += (c - b).as_secs_f64();
            phase_secs[3] += (b - a).as_secs_f64();
        }
        if day % 5 == 4 || day + 1 == cfg.days {
            let flows = store.coin_flows().unwrap_or_default();
            let minted: i64 = flows.iter().filter(|f| f.2).map(|f| f.4).sum();
            let sunk: i64 = flows.iter().filter(|f| f.0 == "DEBIT" || f.0 == "CLAWBACK").map(|f| f.4).sum::<i64>() - flows.iter().filter(|f| f.0 == "CREDIT" && !f.2).map(|f| f.4).sum::<i64>();
            let row = SupplyRow { day: day + 1, supply: (minted - sunk).max(0) as u64, per_bot: ((minted - sunk).max(0) as u64) / n.max(1) as u64, minted: minted as u64, sunk: sunk as u64 };
            if !cfg.quiet {
                println!("  day {:>3}: supply {:>11} coin ({:>6} a bot), sales so far {}, {:.0} s", row.day, row.supply, row.per_bot, sim.eco.totals().sales, started.elapsed().as_secs_f64());
            }
            report.supply.push(row);
        }
    }
    sim.eco.sweep(EPOCH + cfg.days as i64 * MS_DAY + 100 * MS_DAY);
    sim.drain_sales(cfg.days, &mut all);

    // ---- the judgement
    if !cfg.quiet {
        println!("  seconds: play {:.1}, town {:.1}, sweeps {:.1}", phase_secs[0], phase_secs[1] + phase_secs[2], phase_secs[3]);
    }
    report.secs = started.elapsed().as_secs_f64();
    report.totals = eco.totals();
    report.counters = sim.count.0.lock().unwrap().clone();
    report.flows = store.coin_flows().unwrap_or_default();
    let windows = cfg.days.div_ceil(WINDOW_DAYS).max(1);
    for rarity in 0..5u8 {
        for band in 0..6u8 {
            let mut ws = Vec::new();
            let mut any = false;
            for w in 0..windows {
                let mut v: Vec<u64> = all
                    .iter()
                    .filter(|(d, s)| s.stack.is_none() && s.value > 0 && d / WINDOW_DAYS == w && class_of(s.rarity, s.level) == (rarity, band))
                    .map(|(_, s)| s.price * 100 / s.value)
                    .collect();
                let n = v.len();
                any |= n > 0;
                ws.push((if n >= MIN_SALES { Some(median(&mut v)) } else { None }, n));
            }
            if any {
                report.classes.push(ClassRow { rarity, band, windows: ws });
            }
        }
    }
    let mut em: Vec<u64> = all.iter().filter_map(|(_, s)| s.stack.filter(|(k, _)| *k == 1000).map(|(_, n)| s.price / n.max(1))).collect();
    if !em.is_empty() {
        report.ember_unit = Some((em.len() as u64, median(&mut em)));
    }
    report.repeat_pairs = eco.repeat_pairs(5).len();
    for a in &farm_accounts {
        report.farm_hops += store.trace_forward(*a, 1).map(|h| h.len()).unwrap_or(0);
    }
    let v = store.verify().expect("verify");
    report.items_live = v.items;
    report.ledger_rows = v.ledger_rows;
    report.problems = v.problems.clone();
    // coin by the ledger equals coin held, independently of verify's replay
    let flows = &report.flows;
    let minted: i64 = flows.iter().filter(|f| f.2).map(|f| f.4).sum();
    let sunk: i64 = flows.iter().filter(|f| f.0 == "DEBIT" || f.0 == "CLAWBACK").map(|f| f.4).sum::<i64>() - flows.iter().filter(|f| f.0 == "CREDIT" && !f.2).map(|f| f.4).sum::<i64>();
    let held = store.stats().map(|s| s.coin).unwrap_or(-1);
    if minted - sunk != held {
        report.problems.push(format!("coin: ledger says {} held, the stacks hold {held}", minted - sunk));
    }
    eco.stop();
    report
}

impl Report {
    /// What broke the bands or the guards (empty when the run is good).
    pub fn failures(&self) -> Vec<String> {
        let mut f = self.problems.clone();
        for c in &self.classes {
            let name = format!("{} band {}", realm_loot::tables::RARITY_NAMES[c.rarity as usize], c.band);
            let mut prev: Option<u64> = None;
            for (w, (m, n)) in c.windows.iter().enumerate() {
                let Some(m) = m else { continue };
                if *m < BAND_LO_PCT || *m > BAND_HI_PCT {
                    f.push(format!("{name}: window {w} median {m}% of value is outside {BAND_LO_PCT}..{BAND_HI_PCT} ({n} sales)"));
                }
                if let Some(p) = prev {
                    if *m * 100 > p * DRIFT_MAX_PCT {
                        f.push(format!("{name}: window {w} median {m}% against {p}% before is more than x{} up", DRIFT_MAX_PCT / 100));
                    }
                }
                prev = Some(*m);
            }
        }
        if let Some(n) = self.counters.get("GUARD_BROKEN") {
            f.push(format!("{n} trades by locked or self-found bots were NOT refused"));
        }
        if self.farm_hops > 0 {
            f.push(format!("{} onward hops from trade-locked accounts", self.farm_hops));
        }
        for k in ["outing_failed"] {
            if let Some(n) = self.counters.get(k) {
                f.push(format!("{k}: {n}"));
            }
        }
        f
    }
}
