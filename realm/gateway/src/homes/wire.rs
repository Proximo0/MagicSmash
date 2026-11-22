//! The homes' part of the gateway wire: one request tag `T_HOME` (a sub-byte, then the acting hero, then the
//! arguments), one reply tag `R_HOME`, and pushes under `P_HOME` with the same body. Layouts: `docs/realm/homes.md`.
//! Strings are `u16 len, bytes`; an item is the gateway's `ItemInfo` (its `slot` is the house cell).

use crate::proto::{put_str, read_str, ItemInfo};
use realm_server::{put_u16, put_u32, put_u64, Rd};

pub const T_HOME: u8 = 0x70;
pub const R_HOME: u8 = 0x8C;
pub const P_HOME: u8 = 0xA9;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HReq {
    /// How many streets are open and how full each is.
    Streets { hero: i64 },
    Street { hero: i64, street: u32 },
    Buy { hero: i64, street: u32, plot: u8 },
    Rent { hero: i64, street: u32, plot: u8, weeks: u8 },
    /// Extends her rent (the same as `Rent` on her own plot).
    Renew { hero: i64, weeks: u8 },
    Release { hero: i64 },
    /// 0 open, 1 friends, 2 guild, 3 locked.
    Rule { hero: i64, rule: u8 },
    Name { hero: i64, name: String },
    /// Walk to a place: `kind` and `arg` as in `homes::place` (arg: the street, the plot, 0 for a guild hall).
    Go { hero: i64, kind: u8, arg: u32 },
    /// The house she stands in.
    House { hero: i64 },
    Place { hero: i64, item: i64, cell: u16 },
    Move { hero: i64, item: i64, cell: u16 },
    Pickup { hero: i64, item: i64 },
    Sign { hero: i64, text: String },
    Wipe { hero: i64, entry: u64 },
    Craft { hero: i64, kind: u16 },
    Catalogue { hero: i64 },
    Strike { hero: i64 },
    YardBoard { hero: i64 },
    Sit { hero: i64 },
    Stand { hero: i64 },
    Status { hero: i64 },
    Stalls { hero: i64, offset: u32 },
    Where { hero: i64 },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PlotInfo {
    pub index: u8,
    pub owner: String,
    /// 0 free, 1 owned, 2 rented, 3 lapsed.
    pub status: u8,
    pub rule: u8,
    pub name: String,
    pub buy: u64,
    pub rent: u64,
    pub until: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EntryInfo {
    pub id: u64,
    pub at: i64,
    pub name: String,
    pub text: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HouseView {
    pub plot: u32,
    pub owner: String,
    pub name: String,
    pub rule: u8,
    pub status: u8,
    pub until: i64,
    pub mine: bool,
    /// Furniture and trophies in the house; each `slot` is its cell.
    pub items: Vec<ItemInfo>,
    pub book: Vec<EntryInfo>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Stall {
    pub seller: String,
    pub listings: u32,
    pub cheapest: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HResp {
    Ok,
    Streets { open: u32, taken: Vec<u8>, mine: Option<u32> },
    Street { street: u32, plots: Vec<PlotInfo> },
    House(HouseView),
    /// An item moved: where it is now (0 bag, 1 house) and its cell.
    Moved { item: i64, house: bool, cell: u16 },
    Crafted(ItemInfo),
    /// A paid plot: its number, when the rent ends (0 for owned) and the coin taken.
    Paid { plot: u32, until: i64, coin: u64 },
    Strike { damage: u32, total: u64, dps: u32, count: u32, best: u32 },
    Board(Vec<(String, u8, u32)>),
    Rest { sitting: bool, secs: u32, rested_ms: u32, pct: u8 },
    Stalls(Vec<Stall>),
    Where { kind: u8, arg: u32 },
    Catalogue(Vec<(u16, u32, u64, u64)>),
    Book(Vec<EntryInfo>),
    /// A push: `kind` 0 someone came into your house (text: her name), 1 someone signed your guestbook, 2 your rent
    /// ends soon (a: ms left), 3 a hero in the yard finished a round (text: name, a: dps).
    Notice { kind: u8, a: i64, text: String },
}

fn hero(r: &mut Rd) -> Option<i64> {
    r.u64().map(|v| v as i64)
}

impl HReq {
    pub fn put(&self, w: &mut Vec<u8>) {
        let h = |w: &mut Vec<u8>, sub: u8, hero: i64| {
            w.push(sub);
            put_u64(w, hero as u64);
        };
        match self {
            HReq::Streets { hero } => h(w, 0, *hero),
            HReq::Street { hero, street } => {
                h(w, 1, *hero);
                put_u32(w, *street);
            }
            HReq::Buy { hero, street, plot } => {
                h(w, 2, *hero);
                put_u32(w, *street);
                w.push(*plot);
            }
            HReq::Rent { hero, street, plot, weeks } => {
                h(w, 3, *hero);
                put_u32(w, *street);
                w.extend_from_slice(&[*plot, *weeks]);
            }
            HReq::Renew { hero, weeks } => {
                h(w, 4, *hero);
                w.push(*weeks);
            }
            HReq::Release { hero } => h(w, 5, *hero),
            HReq::Rule { hero, rule } => {
                h(w, 6, *hero);
                w.push(*rule);
            }
            HReq::Name { hero, name } => {
                h(w, 7, *hero);
                put_str(w, name);
            }
            HReq::Go { hero, kind, arg } => {
                h(w, 8, *hero);
                w.push(*kind);
                put_u32(w, *arg);
            }
            HReq::House { hero } => h(w, 9, *hero),
            HReq::Place { hero, item, cell } => {
                h(w, 10, *hero);
                put_u64(w, *item as u64);
                put_u16(w, *cell);
            }
            HReq::Move { hero, item, cell } => {
                h(w, 11, *hero);
                put_u64(w, *item as u64);
                put_u16(w, *cell);
            }
            HReq::Pickup { hero, item } => {
                h(w, 12, *hero);
                put_u64(w, *item as u64);
            }
            HReq::Sign { hero, text } => {
                h(w, 13, *hero);
                put_str(w, text);
            }
            HReq::Wipe { hero, entry } => {
                h(w, 14, *hero);
                put_u64(w, *entry);
            }
            HReq::Craft { hero, kind } => {
                h(w, 15, *hero);
                put_u16(w, *kind);
            }
            HReq::Catalogue { hero } => h(w, 16, *hero),
            HReq::Strike { hero } => h(w, 17, *hero),
            HReq::YardBoard { hero } => h(w, 18, *hero),
            HReq::Sit { hero } => h(w, 19, *hero),
            HReq::Stand { hero } => h(w, 20, *hero),
            HReq::Status { hero } => h(w, 21, *hero),
            HReq::Stalls { hero, offset } => {
                h(w, 22, *hero);
                put_u32(w, *offset);
            }
            HReq::Where { hero } => h(w, 23, *hero),
        }
    }

    pub fn read(r: &mut Rd) -> Option<HReq> {
        let sub = r.u8()?;
        let hero = hero(r)?;
        Some(match sub {
            0 => HReq::Streets { hero },
            1 => HReq::Street { hero, street: r.u32()? },
            2 => HReq::Buy { hero, street: r.u32()?, plot: r.u8()? },
            3 => HReq::Rent { hero, street: r.u32()?, plot: r.u8()?, weeks: r.u8()? },
            4 => HReq::Renew { hero, weeks: r.u8()? },
            5 => HReq::Release { hero },
            6 => HReq::Rule { hero, rule: r.u8()? },
            7 => HReq::Name { hero, name: read_str(r)? },
            8 => HReq::Go { hero, kind: r.u8()?, arg: r.u32()? },
            9 => HReq::House { hero },
            10 => HReq::Place { hero, item: self::hero(r)?, cell: r.u16()? },
            11 => HReq::Move { hero, item: self::hero(r)?, cell: r.u16()? },
            12 => HReq::Pickup { hero, item: self::hero(r)? },
            13 => HReq::Sign { hero, text: read_str(r)? },
            14 => HReq::Wipe { hero, entry: r.u64()? },
            15 => HReq::Craft { hero, kind: r.u16()? },
            16 => HReq::Catalogue { hero },
            17 => HReq::Strike { hero },
            18 => HReq::YardBoard { hero },
            19 => HReq::Sit { hero },
            20 => HReq::Stand { hero },
            21 => HReq::Status { hero },
            22 => HReq::Stalls { hero, offset: r.u32()? },
            23 => HReq::Where { hero },
            _ => return None,
        })
    }
}

fn put_entries(w: &mut Vec<u8>, v: &[EntryInfo]) {
    put_u16(w, v.len() as u16);
    for e in v {
        put_u64(w, e.id);
        put_u64(w, e.at as u64);
        put_str(w, &e.name);
        put_str(w, &e.text);
    }
}
fn read_entries(r: &mut Rd) -> Option<Vec<EntryInfo>> {
    let n = r.u16()? as usize;
    (0..n).map(|_| Some(EntryInfo { id: r.u64()?, at: r.u64()? as i64, name: read_str(r)?, text: read_str(r)? })).collect()
}

impl HResp {
    pub fn put(&self, w: &mut Vec<u8>) {
        match self {
            HResp::Ok => w.push(0),
            HResp::Streets { open, taken, mine } => {
                w.push(1);
                put_u32(w, *open);
                put_u16(w, taken.len() as u16);
                w.extend_from_slice(taken);
                put_u32(w, mine.map_or(u32::MAX, |p| p));
            }
            HResp::Street { street, plots } => {
                w.push(2);
                put_u32(w, *street);
                put_u16(w, plots.len() as u16);
                for p in plots {
                    w.extend_from_slice(&[p.index, p.status, p.rule]);
                    put_str(w, &p.owner);
                    put_str(w, &p.name);
                    put_u64(w, p.buy);
                    put_u64(w, p.rent);
                    put_u64(w, p.until as u64);
                }
            }
            HResp::House(v) => {
                w.push(3);
                put_u32(w, v.plot);
                put_str(w, &v.owner);
                put_str(w, &v.name);
                w.extend_from_slice(&[v.rule, v.status, v.mine as u8]);
                put_u64(w, v.until as u64);
                put_u16(w, v.items.len() as u16);
                for i in &v.items {
                    i.put(w);
                }
                put_entries(w, &v.book);
            }
            HResp::Moved { item, house, cell } => {
                w.push(4);
                put_u64(w, *item as u64);
                w.push(*house as u8);
                put_u16(w, *cell);
            }
            HResp::Crafted(i) => {
                w.push(5);
                i.put(w);
            }
            HResp::Paid { plot, until, coin } => {
                w.push(6);
                put_u32(w, *plot);
                put_u64(w, *until as u64);
                put_u64(w, *coin);
            }
            HResp::Strike { damage, total, dps, count, best } => {
                w.push(7);
                put_u32(w, *damage);
                put_u64(w, *total);
                put_u32(w, *dps);
                put_u32(w, *count);
                put_u32(w, *best);
            }
            HResp::Board(v) => {
                w.push(8);
                put_u16(w, v.len() as u16);
                for (n, c, d) in v {
                    put_str(w, n);
                    w.push(*c);
                    put_u32(w, *d);
                }
            }
            HResp::Rest { sitting, secs, rested_ms, pct } => {
                w.push(9);
                w.push(*sitting as u8);
                put_u32(w, *secs);
                put_u32(w, *rested_ms);
                w.push(*pct);
            }
            HResp::Stalls(v) => {
                w.push(10);
                put_u16(w, v.len() as u16);
                for s in v {
                    put_str(w, &s.seller);
                    put_u32(w, s.listings);
                    put_u64(w, s.cheapest);
                }
            }
            HResp::Where { kind, arg } => {
                w.push(11);
                w.push(*kind);
                put_u32(w, *arg);
            }
            HResp::Catalogue(v) => {
                w.push(12);
                put_u16(w, v.len() as u16);
                for (k, m, n, c) in v {
                    put_u16(w, *k);
                    put_u32(w, *m);
                    put_u64(w, *n);
                    put_u64(w, *c);
                }
            }
            HResp::Book(v) => {
                w.push(13);
                put_entries(w, v);
            }
            HResp::Notice { kind, a, text } => {
                w.push(14);
                w.push(*kind);
                put_u64(w, *a as u64);
                put_str(w, text);
            }
        }
    }

    pub fn read(r: &mut Rd) -> Option<HResp> {
        Some(match r.u8()? {
            0 => HResp::Ok,
            1 => {
                let open = r.u32()?;
                let n = r.u16()? as usize;
                let taken = r.bytes(n)?.to_vec();
                let m = r.u32()?;
                HResp::Streets { open, taken, mine: (m != u32::MAX).then_some(m) }
            }
            2 => {
                let street = r.u32()?;
                let n = r.u16()? as usize;
                let plots = (0..n)
                    .map(|_| {
                        let (index, status, rule) = (r.u8()?, r.u8()?, r.u8()?);
                        Some(PlotInfo { index, status, rule, owner: read_str(r)?, name: read_str(r)?, buy: r.u64()?, rent: r.u64()?, until: r.u64()? as i64 })
                    })
                    .collect::<Option<Vec<_>>>()?;
                HResp::Street { street, plots }
            }
            3 => {
                let (plot, owner, name) = (r.u32()?, read_str(r)?, read_str(r)?);
                let (rule, status, mine, until) = (r.u8()?, r.u8()?, r.u8()? != 0, r.u64()? as i64);
                let n = r.u16()? as usize;
                let items = (0..n).map(|_| ItemInfo::read(r)).collect::<Option<Vec<_>>>()?;
                HResp::House(HouseView { plot, owner, name, rule, status, until, mine, items, book: read_entries(r)? })
            }
            4 => HResp::Moved { item: r.u64()? as i64, house: r.u8()? != 0, cell: r.u16()? },
            5 => HResp::Crafted(ItemInfo::read(r)?),
            6 => HResp::Paid { plot: r.u32()?, until: r.u64()? as i64, coin: r.u64()? },
            7 => HResp::Strike { damage: r.u32()?, total: r.u64()?, dps: r.u32()?, count: r.u32()?, best: r.u32()? },
            8 => {
                let n = r.u16()? as usize;
                HResp::Board((0..n).map(|_| Some((read_str(r)?, r.u8()?, r.u32()?))).collect::<Option<_>>()?)
            }
            9 => HResp::Rest { sitting: r.u8()? != 0, secs: r.u32()?, rested_ms: r.u32()?, pct: r.u8()? },
            10 => {
                let n = r.u16()? as usize;
                HResp::Stalls((0..n).map(|_| Some(Stall { seller: read_str(r)?, listings: r.u32()?, cheapest: r.u64()? })).collect::<Option<_>>()?)
            }
            11 => HResp::Where { kind: r.u8()?, arg: r.u32()? },
            12 => {
                let n = r.u16()? as usize;
                HResp::Catalogue((0..n).map(|_| Some((r.u16()?, r.u32()?, r.u64()?, r.u64()?))).collect::<Option<_>>()?)
            }
            13 => HResp::Book(read_entries(r)?),
            14 => HResp::Notice { kind: r.u8()?, a: r.u64()? as i64, text: read_str(r)? },
            _ => return None,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(slot: u32) -> ItemInfo {
        ItemInfo { id: 5, base: 9000, gear_slot: 5, level: 1, rarity: 0, lines: vec![(0, 0)], sockets: 0, kind: 7, tab: 0, slot, plus: 0, socketed: vec![] }
    }

    #[test]
    fn every_home_request_and_reply_survives_the_wire() {
        let reqs = vec![
            HReq::Streets { hero: 1 },
            HReq::Street { hero: 1, street: 3 },
            HReq::Buy { hero: 1, street: 2, plot: 5 },
            HReq::Rent { hero: 1, street: 2, plot: 5, weeks: 3 },
            HReq::Renew { hero: 1, weeks: 1 },
            HReq::Release { hero: 1 },
            HReq::Rule { hero: 1, rule: 2 },
            HReq::Name { hero: 1, name: "The Lantern".into() },
            HReq::Go { hero: 1, kind: 6, arg: 77 },
            HReq::House { hero: 1 },
            HReq::Place { hero: 1, item: 9, cell: 123 },
            HReq::Move { hero: 1, item: 9, cell: 4 },
            HReq::Pickup { hero: 1, item: 9 },
            HReq::Sign { hero: 1, text: "hi".into() },
            HReq::Wipe { hero: 1, entry: 8 },
            HReq::Craft { hero: 1, kind: 103 },
            HReq::Catalogue { hero: 1 },
            HReq::Strike { hero: 1 },
            HReq::YardBoard { hero: 1 },
            HReq::Sit { hero: 1 },
            HReq::Stand { hero: 1 },
            HReq::Status { hero: 1 },
            HReq::Stalls { hero: 1, offset: 40 },
            HReq::Where { hero: 1 },
        ];
        for q in reqs {
            let mut w = Vec::new();
            q.put(&mut w);
            assert_eq!(HReq::read(&mut Rd::new(&w)), Some(q.clone()), "{q:?}");
            w.push(0);
            let mut r = Rd::new(&w);
            assert!(HReq::read(&mut r).is_some() && r.left() == 1);
        }
        let e = EntryInfo { id: 3, at: 99, name: "Bob".into(), text: "nice".into() };
        let rs = vec![
            HResp::Ok,
            HResp::Streets { open: 2, taken: vec![24, 3], mine: Some(5) },
            HResp::Streets { open: 1, taken: vec![0], mine: None },
            HResp::Street { street: 1, plots: vec![PlotInfo { index: 2, owner: "Ann".into(), status: 2, rule: 1, name: "Home".into(), buy: 5, rent: 6, until: 77 }] },
            HResp::House(HouseView { plot: 4, owner: "Ann".into(), name: "H".into(), rule: 0, status: 1, until: 0, mine: true, items: vec![item(12)], book: vec![e.clone()] }),
            HResp::Moved { item: 5, house: true, cell: 12 },
            HResp::Crafted(item(0)),
            HResp::Paid { plot: 1, until: 5, coin: 6 },
            HResp::Strike { damage: 10, total: 100, dps: 55, count: 10, best: 60 },
            HResp::Board(vec![("Ann".into(), 2, 300)]),
            HResp::Rest { sitting: true, secs: 4, rested_ms: 5, pct: 10 },
            HResp::Stalls(vec![Stall { seller: "Zed".into(), listings: 3, cheapest: 40 }]),
            HResp::Where { kind: 6, arg: 9 },
            HResp::Catalogue(vec![(0, 1001, 4, 60)]),
            HResp::Book(vec![e]),
            HResp::Notice { kind: 0, a: 1, text: "Bob".into() },
        ];
        for p in rs {
            let mut w = Vec::new();
            p.put(&mut w);
            assert_eq!(HResp::read(&mut Rd::new(&w)), Some(p.clone()), "{p:?}");
        }
        assert!(HReq::read(&mut Rd::new(&[99, 0, 0, 0, 0, 0, 0, 0, 0])).is_none());
    }
}
