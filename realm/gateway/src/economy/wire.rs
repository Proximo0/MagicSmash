//! The economy's part of the gateway wire. One request type (`T_ECON`, a sub-byte after it) and one reply type
//! (`R_ECON`); what the server pushes by itself (a trade update, a sale, a letter) is the same body under
//! `P_ECON` with tag 0. Layouts are in `docs/realm/economy.md` part 2. Strings are `u16 len, bytes`; a `Thing`
//! is the gateway's (`u8 0, u64 item` or `u8 1, u32 kind, u64 count`).

use crate::proto::{put_str, read_str, ItemInfo, Thing};
use realm_server::{put_u16, put_u32, put_u64, Rd};
use realm_store::Item;

/// An item as the economy screens show it: the gateway's `ItemInfo` plus what a price depends on.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EItem {
    pub info: ItemInfo,
    pub plus: u8,
    pub bound: bool,
    /// Stack kind in each socket, 0 for empty.
    pub socketed: [u32; 2],
}

impl EItem {
    pub fn of(i: &Item) -> EItem {
        let s = |k: usize| i.socketed.get(k).copied().flatten().map_or(0, |x| x.0);
        EItem {
            info: ItemInfo {
                id: i.id,
                base: i.spec.base,
                gear_slot: i.spec.gear_slot,
                level: i.spec.item_level,
                rarity: i.spec.rarity,
                lines: i.spec.lines.clone(),
                sockets: i.spec.sockets,
                kind: i.place.kind as u8,
                tab: i.place.tab,
                slot: i.place.slot,
                plus: i.spec.plus,
                socketed: i.socketed.iter().map(|x| x.map_or(0, |k| k.0)).collect(),
            },
            plus: i.spec.plus,
            bound: i.spec.bound,
            socketed: [s(0), s(1)],
        }
    }
    fn put(&self, w: &mut Vec<u8>) {
        self.info.put(w);
        w.extend_from_slice(&[self.plus, self.bound as u8]);
        put_u32(w, self.socketed[0]);
        put_u32(w, self.socketed[1]);
    }
    fn read(r: &mut Rd) -> Option<EItem> {
        Some(EItem { info: ItemInfo::read(r)?, plus: r.u8()?, bound: r.u8()? != 0, socketed: [r.u32()?, r.u32()?] })
    }
}

fn put_items(w: &mut Vec<u8>, v: &[EItem]) {
    put_u16(w, v.len() as u16);
    for i in v {
        i.put(w);
    }
}
fn read_items(r: &mut Rd) -> Option<Vec<EItem>> {
    let n = r.u16()? as usize;
    (0..n).map(|_| EItem::read(r)).collect()
}
fn put_stacks(w: &mut Vec<u8>, v: &[(u32, u64)]) {
    put_u16(w, v.len() as u16);
    for (k, n) in v {
        put_u32(w, *k);
        put_u64(w, *n);
    }
}
fn read_stacks(r: &mut Rd) -> Option<Vec<(u32, u64)>> {
    let n = r.u16()? as usize;
    (0..n).map(|_| Some((r.u32()?, r.u64()?))).collect()
}

/// One line of a merchant's list. `kind`: 0 potion, 1 embers, 2 gear. `left` is what she may still buy today.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Offer {
    pub id: u16,
    pub kind: u8,
    pub stack: u32,
    pub item: Option<EItem>,
    pub price: u64,
    pub left: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BuybackInfo {
    pub id: u64,
    pub item: EItem,
    pub price: u64,
    pub secs_left: u32,
}

/// A market search. `gear_slot` 255, `level_max` 0, `stack` 0 and `price_max` 0 mean "any".
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct Search {
    pub gear_slot: u8,
    pub rarity_min: u8,
    pub level_min: u16,
    pub level_max: u16,
    pub stack: u32,
    pub price_max: u64,
    pub offset: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ListingInfo {
    pub id: i64,
    pub seller: String,
    pub price: u64,
    pub expires: i64,
    pub item: Option<EItem>,
    pub stack: Option<(u32, u64)>,
    pub mine: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LetterInfo {
    pub id: i64,
    pub from: String,
    pub to: String,
    pub text: String,
    pub cod: u64,
    pub expires: i64,
    pub items: Vec<EItem>,
    pub stacks: Vec<(u32, u64)>,
}

/// A trade as one side sees it. `state`: 0 invited, 1 open, 2 done, 3 cancelled. `version` counts offer changes;
/// a confirm names the version it saw. `lock_ms`: how long until a confirm is accepted (0 now).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TradeView {
    pub session: u64,
    pub state: u8,
    pub me: i64,
    pub other: i64,
    pub other_name: String,
    pub version: u32,
    pub lock_ms: u32,
    pub my_items: Vec<EItem>,
    pub my_stacks: Vec<(u32, u64)>,
    pub their_items: Vec<EItem>,
    pub their_stacks: Vec<(u32, u64)>,
    pub my_ok: bool,
    pub their_ok: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ClassPrice {
    pub rarity: u8,
    pub band: u8,
    pub median: u64,
    pub n: u32,
}

pub mod notice {
    pub const SOLD: u8 = 1;
    pub const EXPIRED: u8 = 2;
    pub const LETTER: u8 = 3;
    pub const INVITED: u8 = 4;
    pub const LETTER_RETURNED: u8 = 5;
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum EResp {
    Ok,
    Offers(Vec<Offer>),
    /// Coin in her bag after a purchase or a sale.
    Coin(u64),
    Buybacks(Vec<BuybackInfo>),
    Trade(TradeView),
    Listed { id: i64, fee: u64 },
    Listings(Vec<ListingInfo>),
    Letters(Vec<LetterInfo>),
    Prices(Vec<ClassPrice>),
    /// A push: `kind` (see `notice`), a number (listing, letter or session), an amount of coin, a name or text.
    Notice { kind: u8, a: i64, b: u64, text: String },
}

impl EResp {
    pub fn put(&self, w: &mut Vec<u8>) {
        match self {
            EResp::Ok => w.push(0),
            EResp::Offers(v) => {
                w.push(1);
                put_u16(w, v.len() as u16);
                for o in v {
                    put_u16(w, o.id);
                    w.push(o.kind);
                    put_u32(w, o.stack);
                    match &o.item {
                        Some(i) => {
                            w.push(1);
                            i.put(w);
                        }
                        None => w.push(0),
                    }
                    put_u64(w, o.price);
                    put_u32(w, o.left);
                }
            }
            EResp::Coin(c) => {
                w.push(2);
                put_u64(w, *c);
            }
            EResp::Buybacks(v) => {
                w.push(3);
                put_u16(w, v.len() as u16);
                for b in v {
                    put_u64(w, b.id);
                    b.item.put(w);
                    put_u64(w, b.price);
                    put_u32(w, b.secs_left);
                }
            }
            EResp::Trade(t) => {
                w.push(4);
                put_u64(w, t.session);
                w.push(t.state);
                put_u64(w, t.me as u64);
                put_u64(w, t.other as u64);
                put_str(w, &t.other_name);
                put_u32(w, t.version);
                put_u32(w, t.lock_ms);
                put_items(w, &t.my_items);
                put_stacks(w, &t.my_stacks);
                put_items(w, &t.their_items);
                put_stacks(w, &t.their_stacks);
                w.extend_from_slice(&[t.my_ok as u8, t.their_ok as u8]);
            }
            EResp::Listed { id, fee } => {
                w.push(5);
                put_u64(w, *id as u64);
                put_u64(w, *fee);
            }
            EResp::Listings(v) => {
                w.push(6);
                put_u16(w, v.len() as u16);
                for l in v {
                    put_u64(w, l.id as u64);
                    put_str(w, &l.seller);
                    put_u64(w, l.price);
                    put_u64(w, l.expires as u64);
                    w.push(l.mine as u8);
                    match (&l.item, &l.stack) {
                        (Some(i), _) => {
                            w.push(1);
                            i.put(w);
                        }
                        (None, Some((k, n))) => {
                            w.push(2);
                            put_u32(w, *k);
                            put_u64(w, *n);
                        }
                        _ => w.push(0),
                    }
                }
            }
            EResp::Letters(v) => {
                w.push(7);
                put_u16(w, v.len() as u16);
                for l in v {
                    put_u64(w, l.id as u64);
                    put_str(w, &l.from);
                    put_str(w, &l.to);
                    put_str(w, &l.text);
                    put_u64(w, l.cod);
                    put_u64(w, l.expires as u64);
                    put_items(w, &l.items);
                    put_stacks(w, &l.stacks);
                }
            }
            EResp::Prices(v) => {
                w.push(8);
                put_u16(w, v.len() as u16);
                for p in v {
                    w.extend_from_slice(&[p.rarity, p.band]);
                    put_u64(w, p.median);
                    put_u32(w, p.n);
                }
            }
            EResp::Notice { kind, a, b, text } => {
                w.push(9);
                w.push(*kind);
                put_u64(w, *a as u64);
                put_u64(w, *b);
                put_str(w, text);
            }
        }
    }

    pub fn read(r: &mut Rd) -> Option<EResp> {
        Some(match r.u8()? {
            0 => EResp::Ok,
            1 => {
                let n = r.u16()? as usize;
                let mut v = Vec::with_capacity(n);
                for _ in 0..n {
                    let (id, kind, stack) = (r.u16()?, r.u8()?, r.u32()?);
                    let item = if r.u8()? == 1 { Some(EItem::read(r)?) } else { None };
                    v.push(Offer { id, kind, stack, item, price: r.u64()?, left: r.u32()? });
                }
                EResp::Offers(v)
            }
            2 => EResp::Coin(r.u64()?),
            3 => {
                let n = r.u16()? as usize;
                EResp::Buybacks((0..n).map(|_| Some(BuybackInfo { id: r.u64()?, item: EItem::read(r)?, price: r.u64()?, secs_left: r.u32()? })).collect::<Option<_>>()?)
            }
            4 => {
                let (session, state, me, other) = (r.u64()?, r.u8()?, r.u64()? as i64, r.u64()? as i64);
                let other_name = read_str(r)?;
                let (version, lock_ms) = (r.u32()?, r.u32()?);
                let my_items = read_items(r)?;
                let my_stacks = read_stacks(r)?;
                let their_items = read_items(r)?;
                let their_stacks = read_stacks(r)?;
                EResp::Trade(TradeView { session, state, me, other, other_name, version, lock_ms, my_items, my_stacks, their_items, their_stacks, my_ok: r.u8()? != 0, their_ok: r.u8()? != 0 })
            }
            5 => EResp::Listed { id: r.u64()? as i64, fee: r.u64()? },
            6 => {
                let n = r.u16()? as usize;
                let mut v = Vec::with_capacity(n);
                for _ in 0..n {
                    let (id, seller, price, expires, mine) = (r.u64()? as i64, read_str(r)?, r.u64()?, r.u64()? as i64, r.u8()? != 0);
                    let (mut item, mut stack) = (None, None);
                    match r.u8()? {
                        1 => item = Some(EItem::read(r)?),
                        2 => stack = Some((r.u32()?, r.u64()?)),
                        _ => {}
                    }
                    v.push(ListingInfo { id, seller, price, expires, item, stack, mine });
                }
                EResp::Listings(v)
            }
            7 => {
                let n = r.u16()? as usize;
                let mut v = Vec::with_capacity(n);
                for _ in 0..n {
                    v.push(LetterInfo {
                        id: r.u64()? as i64,
                        from: read_str(r)?,
                        to: read_str(r)?,
                        text: read_str(r)?,
                        cod: r.u64()?,
                        expires: r.u64()? as i64,
                        items: read_items(r)?,
                        stacks: read_stacks(r)?,
                    });
                }
                EResp::Letters(v)
            }
            8 => {
                let n = r.u16()? as usize;
                EResp::Prices((0..n).map(|_| Some(ClassPrice { rarity: r.u8()?, band: r.u8()?, median: r.u64()?, n: r.u32()? })).collect::<Option<_>>()?)
            }
            9 => EResp::Notice { kind: r.u8()?, a: r.u64()? as i64, b: r.u64()?, text: read_str(r)? },
            _ => return None,
        })
    }
}

/// What a client asks of the economy. `hero` is always one of her own.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum EReq {
    /// The merchant of her field: what he sells her today.
    MerchantList { hero: i64 },
    MerchantBuy { hero: i64, offer: u16, count: u32 },
    /// Sell a bag item, or a count of embers or a field material, to the merchant.
    MerchantSell { hero: i64, what: Thing },
    Buyback { hero: i64 },
    BuybackTake { hero: i64, entry: u64 },
    TradeInvite { hero: i64, with_name: String },
    TradeAccept { hero: i64, session: u64 },
    TradeOffer { hero: i64, session: u64, items: Vec<i64>, stacks: Vec<(u32, u64)> },
    TradeConfirm { hero: i64, session: u64, version: u32 },
    TradeCancel { hero: i64, session: u64 },
    TradeView { hero: i64, session: u64 },
    MarketList { hero: i64, what: Thing, price: u64, hours: u16 },
    MarketSearch { hero: i64, q: Search },
    MarketBuy { hero: i64, listing: i64 },
    MarketCancel { hero: i64, listing: i64 },
    MarketMine { hero: i64 },
    MarketPrices,
    LetterSend { hero: i64, to_name: String, text: String, things: Vec<Thing>, cod: u64 },
    Inbox { hero: i64 },
    Outbox { hero: i64 },
    LetterTake { hero: i64, letter: i64 },
    /// The addressee sends it back (to the sender's mail).
    LetterRefuse { hero: i64, letter: i64 },
    /// The sender takes back a letter nobody has opened.
    LetterRecall { hero: i64, letter: i64 },
}

impl EReq {
    pub fn put(&self, w: &mut Vec<u8>) {
        let h = |w: &mut Vec<u8>, hero: &i64| put_u64(w, *hero as u64);
        match self {
            EReq::MerchantList { hero } => {
                w.push(0x01);
                h(w, hero);
            }
            EReq::MerchantBuy { hero, offer, count } => {
                w.push(0x02);
                h(w, hero);
                put_u16(w, *offer);
                put_u32(w, *count);
            }
            EReq::MerchantSell { hero, what } => {
                w.push(0x03);
                h(w, hero);
                what.put(w);
            }
            EReq::Buyback { hero } => {
                w.push(0x04);
                h(w, hero);
            }
            EReq::BuybackTake { hero, entry } => {
                w.push(0x05);
                h(w, hero);
                put_u64(w, *entry);
            }
            EReq::TradeInvite { hero, with_name } => {
                w.push(0x10);
                h(w, hero);
                put_str(w, with_name);
            }
            EReq::TradeAccept { hero, session } => {
                w.push(0x11);
                h(w, hero);
                put_u64(w, *session);
            }
            EReq::TradeOffer { hero, session, items, stacks } => {
                w.push(0x12);
                h(w, hero);
                put_u64(w, *session);
                put_u16(w, items.len() as u16);
                for i in items {
                    put_u64(w, *i as u64);
                }
                put_stacks(w, stacks);
            }
            EReq::TradeConfirm { hero, session, version } => {
                w.push(0x13);
                h(w, hero);
                put_u64(w, *session);
                put_u32(w, *version);
            }
            EReq::TradeCancel { hero, session } => {
                w.push(0x14);
                h(w, hero);
                put_u64(w, *session);
            }
            EReq::TradeView { hero, session } => {
                w.push(0x15);
                h(w, hero);
                put_u64(w, *session);
            }
            EReq::MarketList { hero, what, price, hours } => {
                w.push(0x20);
                h(w, hero);
                what.put(w);
                put_u64(w, *price);
                put_u16(w, *hours);
            }
            EReq::MarketSearch { hero, q } => {
                w.push(0x21);
                h(w, hero);
                w.extend_from_slice(&[q.gear_slot, q.rarity_min]);
                put_u16(w, q.level_min);
                put_u16(w, q.level_max);
                put_u32(w, q.stack);
                put_u64(w, q.price_max);
                put_u32(w, q.offset);
            }
            EReq::MarketBuy { hero, listing } => {
                w.push(0x22);
                h(w, hero);
                put_u64(w, *listing as u64);
            }
            EReq::MarketCancel { hero, listing } => {
                w.push(0x23);
                h(w, hero);
                put_u64(w, *listing as u64);
            }
            EReq::MarketMine { hero } => {
                w.push(0x24);
                h(w, hero);
            }
            EReq::MarketPrices => w.push(0x25),
            EReq::LetterSend { hero, to_name, text, things, cod } => {
                w.push(0x30);
                h(w, hero);
                put_str(w, to_name);
                put_str(w, text);
                w.push(things.len() as u8);
                for t in things {
                    t.put(w);
                }
                put_u64(w, *cod);
            }
            EReq::Inbox { hero } => {
                w.push(0x31);
                h(w, hero);
            }
            EReq::Outbox { hero } => {
                w.push(0x32);
                h(w, hero);
            }
            EReq::LetterTake { hero, letter } => {
                w.push(0x33);
                h(w, hero);
                put_u64(w, *letter as u64);
            }
            EReq::LetterRefuse { hero, letter } => {
                w.push(0x34);
                h(w, hero);
                put_u64(w, *letter as u64);
            }
            EReq::LetterRecall { hero, letter } => {
                w.push(0x35);
                h(w, hero);
                put_u64(w, *letter as u64);
            }
        }
    }

    pub fn read(r: &mut Rd) -> Option<EReq> {
        let t = r.u8()?;
        if t == 0x25 {
            return Some(EReq::MarketPrices);
        }
        let hero = r.u64()? as i64;
        Some(match t {
            0x01 => EReq::MerchantList { hero },
            0x02 => EReq::MerchantBuy { hero, offer: r.u16()?, count: r.u32()? },
            0x03 => EReq::MerchantSell { hero, what: Thing::read(r)? },
            0x04 => EReq::Buyback { hero },
            0x05 => EReq::BuybackTake { hero, entry: r.u64()? },
            0x10 => EReq::TradeInvite { hero, with_name: read_str(r)? },
            0x11 => EReq::TradeAccept { hero, session: r.u64()? },
            0x12 => {
                let session = r.u64()?;
                let n = r.u16()? as usize;
                let items = (0..n).map(|_| r.u64().map(|v| v as i64)).collect::<Option<Vec<_>>>()?;
                EReq::TradeOffer { hero, session, items, stacks: read_stacks(r)? }
            }
            0x13 => EReq::TradeConfirm { hero, session: r.u64()?, version: r.u32()? },
            0x14 => EReq::TradeCancel { hero, session: r.u64()? },
            0x15 => EReq::TradeView { hero, session: r.u64()? },
            0x20 => EReq::MarketList { hero, what: Thing::read(r)?, price: r.u64()?, hours: r.u16()? },
            0x21 => EReq::MarketSearch {
                hero,
                q: Search { gear_slot: r.u8()?, rarity_min: r.u8()?, level_min: r.u16()?, level_max: r.u16()?, stack: r.u32()?, price_max: r.u64()?, offset: r.u32()? },
            },
            0x22 => EReq::MarketBuy { hero, listing: r.u64()? as i64 },
            0x23 => EReq::MarketCancel { hero, listing: r.u64()? as i64 },
            0x24 => EReq::MarketMine { hero },
            0x30 => {
                let (to_name, text) = (read_str(r)?, read_str(r)?);
                let n = r.u8()? as usize;
                let things = (0..n).map(|_| Thing::read(r)).collect::<Option<Vec<_>>>()?;
                EReq::LetterSend { hero, to_name, text, things, cod: r.u64()? }
            }
            0x31 => EReq::Inbox { hero },
            0x32 => EReq::Outbox { hero },
            0x33 => EReq::LetterTake { hero, letter: r.u64()? as i64 },
            0x34 => EReq::LetterRefuse { hero, letter: r.u64()? as i64 },
            0x35 => EReq::LetterRecall { hero, letter: r.u64()? as i64 },
            _ => return None,
        })
    }
}
