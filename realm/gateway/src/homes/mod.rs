//! Homes and the shared places (job H1). `docs/realm/homes.md` has every number and why.
//!
//! A hero walks between places: the plaza (where she arrives), the tavern, the market square, her guild's hall, the
//! training yard, the streets and the houses on them. Each place is a town room tagged with the place
//! (`Towns::enter_at`); a house or a guild hall is one room, a public square opens another when full. A street holds
//! 24 plots; an account buys or rents one with coin (debited from the hero's bag through the store, so it is a ledger
//! row and the coin is destroyed), and may place furniture and trophies on its grid. Furniture is an item of the
//! store: placing moves it from the bag to the house place of the account, picking up moves it back, nothing is
//! copied. Who may visit is the owner's rule (open, friends, guild, locked); visitors may sign the guestbook.
//!
//! The registry of plots (`plots.rs`) is the gateway's own small file; every item and every coin is the store's.

pub mod catalogue;
pub mod place;
pub mod plots;
mod rest;
pub mod wire;
/// Its messages on the gateway wire and its dispatch (`proto::WireModule`).
pub mod gate;
mod yard;

use crate::gateway::{err as store_err, now_ms, Gateway, Session};
use crate::proto::{code, resp_frame, Member, Resp};
use plots::{Refuse, Status};
use place::*;
use realm_store::*;
use std::collections::{BTreeMap, HashMap};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
pub use wire::{HReq, HResp, T_HOME, P_HOME, R_HOME};

type R<T = Resp> = std::result::Result<T, Resp>;

fn fail(c: u16, msg: &str) -> Resp {
    Resp::Err { code: c, msg: msg.into() }
}
fn bad(msg: &str) -> Resp {
    fail(code::BAD_REQUEST, msg)
}
fn ok(h: HResp) -> R {
    Ok(Resp::Home(h))
}
fn serr(e: Error) -> Resp {
    store_err(e)
}

/// What a dev-grant hero also gets (job H1): 3,000 coin (a week of rent, a chair and the smith are then all affordable) and 8 PLAGUE LINEN
/// (a chair), so the house screen can be tried on day one.
pub const DEV_KIT: [(u32, u64); 2] = [(1, 3000), (1001, 8)];

/// A hero may make this many home requests in a burst and earns `LIMIT_REFILL_PER_S` back each second.
pub const LIMIT_BURST: u32 = 40;
pub const LIMIT_REFILL_PER_S: u32 = 8;
/// Listings read for the market square's stalls.
pub const STALL_SCAN: u32 = 400;
pub const STALLS_SHOWN: usize = 40;

#[derive(Default)]
struct State {
    reg: plots::Registry,
    at: HashMap<i64, (u8, u32)>,
    rest: HashMap<i64, rest::Rest>,
    dummies: HashMap<i64, yard::Dummy>,
    board: yard::Board,
    limiter: HashMap<i64, (u32, i64)>,
}

pub struct Homes {
    st: Mutex<State>,
    boot: u64,
    n: AtomicU64,
}

impl Default for Homes {
    fn default() -> Homes {
        use std::hash::{BuildHasher, Hasher};
        let boot = std::collections::hash_map::RandomState::new().build_hasher().finish();
        Homes { st: Mutex::new(State { reg: plots::Registry::new(), ..State::default() }), boot, n: AtomicU64::new(1) }
    }
}

fn refuse(r: Refuse) -> Resp {
    match r {
        Refuse::Taken => fail(code::BUSY, "that plot is taken"),
        Refuse::NotOpen => fail(code::INVALID, "that street is not open, or that is not allowed"),
        Refuse::HaveOne => fail(code::BUSY, "your account already has a house: give it up first"),
        Refuse::NoPlot => fail(code::MISSING, "you have no house"),
        Refuse::Lapsed => fail(code::REFUSED, "the rent has run out: renew it first"),
        Refuse::BadWeeks => fail(code::INVALID, "rent is one to four weeks ahead, and a bought house is not rented"),
        Refuse::Gap => fail(code::SLOW_DOWN, "you signed a book a moment ago"),
        Refuse::Empty => bad("write something"),
    }
}

fn status_code(s: Status) -> u8 {
    match s {
        Status::Free => 0,
        Status::Owned(_) => 1,
        Status::Rented(_) => 2,
        Status::Lapsed(_) => 3,
    }
}

impl Homes {
    /// Keeps the plots (and guestbooks) in `path` and reads what is there.
    pub fn persist(&self, path: &std::path::Path) -> std::io::Result<()> {
        let reg = plots::Registry::open(path)?;
        self.st.lock().unwrap().reg = reg;
        Ok(())
    }

    fn meta(&self, actor: i64, now: i64) -> Meta {
        Meta::new(((self.boot as u128) << 64) | self.n.fetch_add(1, Ordering::Relaxed) as u128, actor, now)
    }

    /// Where a hero is.
    pub fn place_of(&self, hero: i64) -> (u8, u32) {
        self.st.lock().unwrap().at.get(&hero).copied().unwrap_or((PLAZA, 0))
    }

    /// Percent more class XP a hero's flush banks right now (campfire rest).
    pub fn rested_pct(&self, hero: i64, now: i64) -> u64 {
        self.st.lock().unwrap().rest.get(&hero).map_or(0, |r| r.pct(now))
    }

    /// The hero leaves the town (a field ticket, a closed connection): her sit is settled and her place forgotten.
    pub fn depart(&self, towns: &crate::town::Towns, room: u32, me: u16, hero: i64, now: i64) {
        let at = towns.position(room, me).map(|p| (p.0, p.1));
        let mut st = self.st.lock().unwrap();
        if let Some(r) = st.rest.get_mut(&hero) {
            r.stand(now, at);
        }
        st.at.remove(&hero);
        st.dummies.remove(&hero);
    }

    fn limit(&self, hero: i64, now: i64) -> R<()> {
        let mut st = self.st.lock().unwrap();
        let e = st.limiter.entry(hero).or_insert((LIMIT_BURST, now));
        let earned = ((now - e.1).max(0) as u64 * LIMIT_REFILL_PER_S as u64 / 1000) as u32;
        if earned > 0 {
            e.0 = (e.0 + earned).min(LIMIT_BURST);
            e.1 = now;
        }
        if e.0 == 0 {
            return Err(fail(code::SLOW_DOWN, "slow down"));
        }
        e.0 -= 1;
        Ok(())
    }

    fn me(&self, gw: &Gateway, s: &Session, account: i64, hero: i64, now: i64) -> R<Hero> {
        let h = gw.store.hero(hero).map_err(serr)?.ok_or_else(|| fail(code::MISSING, "no such hero"))?;
        if h.account != account {
            return Err(fail(code::NOT_YOURS, "that hero is not yours"));
        }
        if h.deleted_at.is_some() {
            return Err(serr(Error::Deleted));
        }
        if s.town.map(|t| t.2) != Some(hero) {
            return Err(bad("enter the town first"));
        }
        self.limit(hero, now)?;
        Ok(h)
    }

    fn pay(&self, gw: &Gateway, hero: i64, coin: u64, reason: &str, now: i64) -> R<()> {
        gw.store.stack_debit(self.meta(0, now), Owner::bag(hero), StackKind::COIN, coin, reason).map(|_| ()).map_err(serr)
    }

    fn refund(&self, gw: &Gateway, hero: i64, kind: StackKind, n: u64, now: i64) {
        let _ = gw.store.stack_credit(self.meta(0, now), Owner::bag(hero), kind, n, false, "refund");
    }

    /// Answers one request of the session's account.
    pub fn handle(&self, gw: &Gateway, s: &mut Session, account: i64, req: HReq) -> Resp {
        match self.run(gw, s, account, req, now_ms()) {
            Ok(r) | Err(r) => r,
        }
    }

    fn run(&self, gw: &Gateway, s: &mut Session, account: i64, req: HReq, now: i64) -> R {
        let hero_id = match &req {
            HReq::Streets { hero } | HReq::Street { hero, .. } | HReq::Buy { hero, .. } | HReq::Rent { hero, .. } | HReq::Renew { hero, .. } | HReq::Release { hero } | HReq::Rule { hero, .. } | HReq::Name { hero, .. } | HReq::Go { hero, .. } | HReq::House { hero } | HReq::Place { hero, .. } | HReq::Move { hero, .. } | HReq::Pickup { hero, .. } | HReq::Sign { hero, .. } | HReq::Wipe { hero, .. } | HReq::Craft { hero, .. } | HReq::Catalogue { hero } | HReq::Strike { hero } | HReq::YardBoard { hero } | HReq::Sit { hero } | HReq::Stand { hero } | HReq::Status { hero } | HReq::Stalls { hero, .. } | HReq::Where { hero } => *hero,
        };
        let h = self.me(gw, s, account, hero_id, now)?;
        let here = self.place_of(hero_id);
        match req {
            HReq::Where { .. } => ok(HResp::Where { kind: here.0, arg: here.1 }),
            HReq::Streets { .. } => {
                let st = self.st.lock().unwrap();
                let open = st.reg.streets_open(now);
                let taken = (1..=open).map(|n| st.reg.taken_on(n, now) as u8).collect();
                ok(HResp::Streets { open, taken, mine: st.reg.plot_of(account, now) })
            }
            HReq::Street { street, .. } => self.street(street, now),
            HReq::Buy { street, plot, .. } => {
                self.at_street(here, street, plot)?;
                let id = plot_id(street, plot as u32);
                let price = plots::buy_price(plot as u32);
                let mut st = self.st.lock().unwrap();
                st.reg.can_take(id, account, now).map_err(refuse)?;
                self.pay(gw, hero_id, price, "house plot", now)?;
                if let Err(r) = st.reg.buy(id, account, &h.name, now) {
                    self.refund(gw, hero_id, StackKind::COIN, price, now);
                    return Err(refuse(r));
                }
                ok(HResp::Paid { plot: id, until: 0, coin: price })
            }
            HReq::Rent { street, plot, weeks, .. } => {
                self.at_street(here, street, plot)?;
                self.rent(gw, account, &h, plot_id(street, plot as u32), weeks, now)
            }
            HReq::Renew { weeks, .. } => {
                let id = self.st.lock().unwrap().reg.plot_of(account, now).ok_or_else(|| refuse(Refuse::NoPlot))?;
                self.rent(gw, account, &h, id, weeks, now)
            }
            HReq::Release { .. } => {
                self.st.lock().unwrap().reg.release(account, now).map_err(refuse)?;
                ok(HResp::Ok)
            }
            HReq::Rule { rule, .. } => {
                self.st.lock().unwrap().reg.set_rule(account, rule, now).map_err(refuse)?;
                ok(HResp::Ok)
            }
            HReq::Name { name, .. } => {
                // The word filter of the chat: a house name is read by everyone on the street.
                let name = plots::clean(&name, plots::NAME_MAX);
                let name = if name.is_empty() { name } else { gw.social.gate(account, crate::social::chan::SAY, &name, now).map_err(|r| r.resp())? };
                self.st.lock().unwrap().reg.set_name(account, &name, now).map_err(refuse)?;
                ok(HResp::Ok)
            }
            HReq::Go { kind, arg, .. } => self.go(gw, s, account, &h, kind, arg, now),
            HReq::House { .. } => {
                let plot = self.in_house(here)?;
                self.house_view(gw, account, plot, now)
            }
            HReq::Place { item, cell, .. } => self.place(gw, account, &h, here, item, cell, now),
            HReq::Move { item, cell, .. } => {
                let plot = self.my_house(account, here, now)?;
                self.check_cell(plot, account, cell, now)?;
                self.house_item(gw, account, item)?;
                let to = Dest::at(PlaceKind::House, account, 0, cell as u32);
                let p = gw.store.move_item(self.meta(account, now), item, to).map_err(serr)?;
                ok(HResp::Moved { item, house: true, cell: p.slot as u16 })
            }
            HReq::Pickup { item, .. } => {
                self.house_item(gw, account, item)?;
                gw.store.move_item(self.meta(account, now), item, Dest::bag(hero_id)).map_err(serr)?;
                ok(HResp::Moved { item, house: false, cell: 0 })
            }
            HReq::Sign { text, .. } => {
                let plot = self.in_house(here)?;
                let owner = self.st.lock().unwrap().reg.plot(plot).map(|p| p.owner).ok_or_else(|| fail(code::MISSING, "no such house"))?;
                if owner == account {
                    return Err(bad("the owner does not sign her own book"));
                }
                let text = gw.social.gate(account, crate::social::chan::SAY, &text, now).map_err(|r| r.resp())?;
                self.st.lock().unwrap().reg.sign(plot, account, &h.name, &text, now).map_err(refuse)?;
                self.push_account(gw, owner, HResp::Notice { kind: 1, a: plot as i64, text: h.name.clone() });
                ok(HResp::Ok)
            }
            HReq::Wipe { entry, .. } => {
                let mut st = self.st.lock().unwrap();
                let plot = st.reg.plot_of(account, now).ok_or_else(|| refuse(Refuse::NoPlot))?;
                if !st.reg.wipe(plot, entry) {
                    return Err(fail(code::MISSING, "no such entry"));
                }
                ok(HResp::Ok)
            }
            HReq::Craft { kind, .. } => self.craft(gw, &h, kind, now),
            HReq::Catalogue { .. } => ok(HResp::Catalogue(catalogue::all().iter().map(|r| (r.kind, r.material, r.count, r.coin)).collect())),
            HReq::Strike { .. } => self.strike(gw, &h, here, now),
            HReq::YardBoard { .. } => ok(HResp::Board(self.st.lock().unwrap().board.top())),
            HReq::Sit { .. } => self.sit(gw, s, &h, here, now),
            HReq::Stand { .. } => {
                let at = self.position(gw, s);
                let mut st = self.st.lock().unwrap();
                let r = st.rest.entry(hero_id).or_default();
                r.stand(now, at);
                let v = r.view(now);
                ok(HResp::Rest { sitting: v.sitting, secs: v.secs, rested_ms: v.rested_ms, pct: v.pct })
            }
            HReq::Status { .. } => {
                let at = self.position(gw, s);
                let mut st = self.st.lock().unwrap();
                let r = st.rest.entry(hero_id).or_default();
                r.settle(now, at);
                let v = r.view(now);
                ok(HResp::Rest { sitting: v.sitting, secs: v.secs, rested_ms: v.rested_ms, pct: v.pct })
            }
            HReq::Stalls { offset, .. } => self.stalls(gw, here, offset, now),
        }
    }

    fn position(&self, gw: &Gateway, s: &Session) -> Option<(u16, u16)> {
        let (room, me, _) = s.town?;
        gw.towns.position(room, me).map(|p| (p.0, p.1))
    }

    fn at_street(&self, here: (u8, u32), street: u32, plot: u8) -> R<()> {
        if plot as u32 >= PLOTS_PER_STREET || street == 0 || street > STREETS_MAX {
            return Err(bad("no such plot"));
        }
        if here != (STREET, street) {
            return Err(bad("walk to that street first"));
        }
        Ok(())
    }

    fn rent(&self, gw: &Gateway, account: i64, h: &Hero, id: u32, weeks: u8, now: i64) -> R {
        let price = plots::rent_price(index_of(id), weeks);
        let mut st = self.st.lock().unwrap();
        // Check before the coin moves (the registry refuses the same way after it).
        st.reg.can_take(id, account, now).map_err(refuse)?;
        if weeks == 0 || weeks > plots::RENT_WEEKS_MAX {
            return Err(refuse(Refuse::BadWeeks));
        }
        self.pay(gw, h.id, price, "house rent", now)?;
        match st.reg.rent(id, account, &h.name, weeks, now) {
            Ok(until) => ok(HResp::Paid { plot: id, until, coin: price }),
            Err(r) => {
                self.refund(gw, h.id, StackKind::COIN, price, now);
                Err(refuse(r))
            }
        }
    }

    fn street(&self, street: u32, now: i64) -> R {
        let st = self.st.lock().unwrap();
        if street == 0 || street > st.reg.streets_open(now) {
            return Err(refuse(Refuse::NotOpen));
        }
        let plots = (0..PLOTS_PER_STREET)
            .map(|i| {
                let id = plot_id(street, i);
                let status = st.reg.status(id, now);
                let p = st.reg.plot(id).filter(|_| status != Status::Free);
                wire::PlotInfo {
                    index: i as u8,
                    owner: p.map_or(String::new(), |p| p.owner_name.clone()),
                    status: status_code(status),
                    rule: p.map_or(0, |p| p.rule),
                    name: p.map_or(String::new(), |p| p.name.clone()),
                    buy: plots::buy_price(i),
                    rent: plots::rent_price(i, 1),
                    until: match p.map(|p| p.tenure) {
                        Some(plots::Tenure::Rented { until }) => until,
                        _ => 0,
                    },
                }
            })
            .collect();
        ok(HResp::Street { street, plots })
    }

    // ---- going places

    /// May `account` come into house `plot`?
    fn may_enter(&self, gw: &Gateway, account: i64, plot: u32, now: i64) -> R<i64> {
        let (status, rule) = {
            let st = self.st.lock().unwrap();
            (st.reg.status(plot, now), st.reg.plot(plot).map_or(OPEN_RULE, |p| p.rule))
        };
        let owner = match status {
            Status::Free => return Err(fail(code::MISSING, "no one lives there")),
            Status::Owned(o) | Status::Rented(o) | Status::Lapsed(o) => o,
        };
        if owner == account {
            return Ok(owner);
        }
        if matches!(status, Status::Lapsed(_)) {
            return Err(fail(code::REFUSED, "the door is shut"));
        }
        let g = gw.social.inner.lock().unwrap();
        let closed = || fail(code::REFUSED, "the door is shut");
        if g.ignores(owner, account) {
            return Err(closed());
        }
        match rule {
            plots::OPEN => Ok(owner),
            plots::FRIENDS if g.friends.get(&owner).is_some_and(|f| f.contains(&account)) => Ok(owner),
            plots::GUILD if g.guild_of.get(&account).is_some_and(|gid| g.guild_of.get(&owner) == Some(gid)) => Ok(owner),
            _ => Err(closed()),
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn go(&self, gw: &Gateway, s: &mut Session, account: i64, h: &Hero, kind: u8, arg: u32, now: i64) -> R {
        let (kind, arg) = match kind {
            PLAZA | TAVERN | MARKET | YARD => (kind, 0),
            GUILD_HALL => {
                let g = gw.social.inner.lock().unwrap();
                let gid = *g.guild_of.get(&account).ok_or_else(|| fail(code::REFUSED, "you are in no guild"))?;
                (kind, gid as u32)
            }
            STREET => {
                if arg == 0 || arg > self.st.lock().unwrap().reg.streets_open(now) {
                    return Err(refuse(Refuse::NotOpen));
                }
                (kind, arg)
            }
            HOUSE => {
                self.may_enter(gw, account, arg, now)?;
                (kind, arg)
            }
            _ => return Err(bad("no such place")),
        };
        let hero = h.id;
        if self.place_of(hero) == (kind, arg) {
            return Err(bad("you are already there"));
        }
        let (cap, overflow) = rules(kind).ok_or_else(|| bad("no such place"))?;
        let (old_room, old_me, _) = s.town.ok_or_else(|| bad("not in a town"))?;
        let info = Member { id: 0, name: h.name.clone(), class: h.class, race: h.race, level: h.progress.class_level, look: h.look };
        let Some((room, me, members)) = gw.towns.enter_at(key(kind, arg), cap, overflow, info, s.out.clone()) else {
            return Err(fail(code::FULL, "that place is full"));
        };
        let at = gw.towns.position(old_room, old_me).map(|p| (p.0, p.1));
        gw.towns.leave(old_room, old_me);
        s.town = Some((room, me, hero));
        gw.economy.attach(hero, room, s.out.clone());
        {
            let mut st = self.st.lock().unwrap();
            if let Some(r) = st.rest.get_mut(&hero) {
                r.stand(now, at);
            }
            st.dummies.remove(&hero);
            if (kind, arg) == (PLAZA, 0) {
                st.at.remove(&hero);
            } else {
                st.at.insert(hero, (kind, arg));
            }
        }
        if kind == HOUSE {
            if let Some(owner) = self.st.lock().unwrap().reg.plot(arg).map(|p| p.owner).filter(|o| *o != account) {
                self.push_account(gw, owner, HResp::Notice { kind: 0, a: arg as i64, text: h.name.clone() });
            }
        }
        Ok(Resp::Town { room, me, size: crate::town::TOWN_PX, members })
    }

    /// Pushes to every connection of an account (once each).
    fn push_account(&self, gw: &Gateway, account: i64, p: HResp) {
        let g = gw.social.inner.lock().unwrap();
        let f = resp_frame(0, &Resp::HomePush(p));
        let mut seen = Vec::new();
        for hero in g.by_account.get(&account).into_iter().flatten() {
            if let Some(pr) = g.online.get(hero) {
                if !seen.contains(&pr.conn) {
                    seen.push(pr.conn);
                    let _ = pr.out.send(f.clone());
                }
            }
        }
    }

    // ---- the house

    fn in_house(&self, here: (u8, u32)) -> R<u32> {
        (here.0 == HOUSE).then_some(here.1).ok_or_else(|| bad("you are not in a house"))
    }

    /// The plot of the house she stands in, if it is hers and its rent is paid.
    fn my_house(&self, account: i64, here: (u8, u32), now: i64) -> R<u32> {
        let plot = self.in_house(here)?;
        match self.st.lock().unwrap().reg.status(plot, now) {
            Status::Owned(o) | Status::Rented(o) if o == account => Ok(plot),
            _ => Err(fail(code::NOT_YOURS, "this is not your house, or its rent has run out")),
        }
    }

    /// Room 1 (cells 100..200) is for bought houses only.
    fn check_cell(&self, plot: u32, account: i64, cell: u16, now: i64) -> R<()> {
        if cell as u32 >= CELLS {
            return Err(bad("no such cell"));
        }
        let _ = (plot, account, now);
        let st = self.st.lock().unwrap();
        let owned = matches!(st.reg.plot(plot).map(|p| p.tenure), Some(plots::Tenure::Owned));
        if cell as u32 >= GRID_W * GRID_H && !owned {
            return Err(fail(code::REFUSED, "the second room belongs to a house you own, not one you rent"));
        }
        Ok(())
    }

    fn house_item(&self, gw: &Gateway, account: i64, item: i64) -> R<Item> {
        let it = gw.store.item(item).map_err(serr)?.ok_or_else(|| fail(code::MISSING, "no such item"))?;
        if it.place.kind != PlaceKind::House || it.place.owner != account {
            return Err(fail(code::NOT_YOURS, "that is not in your house"));
        }
        Ok(it)
    }

    #[allow(clippy::too_many_arguments)]
    fn place(&self, gw: &Gateway, account: i64, h: &Hero, here: (u8, u32), item: i64, cell: u16, now: i64) -> R {
        let plot = self.my_house(account, here, now)?;
        self.check_cell(plot, account, cell, now)?;
        let it = gw.store.item(item).map_err(serr)?.ok_or_else(|| fail(code::MISSING, "no such item"))?;
        if it.place.kind != PlaceKind::Bag || it.place.owner != h.id {
            return Err(fail(code::NOT_YOURS, "that is not in her bag"));
        }
        if !catalogue::is_house_thing(it.spec.base) {
            return Err(bad("a house holds furniture and trophies"));
        }
        let to = Dest::at(PlaceKind::House, account, 0, cell as u32);
        let p = gw.store.move_item(self.meta(account, now), item, to).map_err(serr)?;
        ok(HResp::Moved { item, house: true, cell: p.slot as u16 })
    }

    fn house_view(&self, gw: &Gateway, account: i64, plot: u32, now: i64) -> R {
        let (p, status, book) = {
            let st = self.st.lock().unwrap();
            (st.reg.plot(plot).cloned().ok_or_else(|| fail(code::MISSING, "no one lives there"))?, st.reg.status(plot, now), st.reg.book(plot))
        };
        let items = gw.store.items_at(PlaceKind::House, p.owner).map_err(serr)?;
        let until = match p.tenure {
            plots::Tenure::Rented { until } => until,
            plots::Tenure::Owned => 0,
        };
        ok(HResp::House(wire::HouseView {
            plot,
            owner: p.owner_name,
            name: p.name,
            rule: p.rule,
            status: status_code(status),
            until,
            mine: p.owner == account,
            items: items.iter().map(|i| crate::economy::wire::EItem::of(i).info).collect(),
            book: book.into_iter().map(|e| wire::EntryInfo { id: e.id, at: e.at, name: e.name, text: e.text }).collect(),
        }))
    }

    // ---- the carpenter

    fn craft(&self, gw: &Gateway, h: &Hero, kind: u16, now: i64) -> R {
        let r = catalogue::recipe(kind).ok_or_else(|| bad("no such piece"))?;
        let bag = gw.store.items_at(PlaceKind::Bag, h.id).map_err(serr)?;
        if bag.len() as u32 >= limits::BAG_SLOTS {
            return Err(serr(Error::Full("her bag is full".into())));
        }
        let mat = StackKind(r.material);
        self.pay_stack(gw, h.id, mat, r.count, now)?;
        if let Err(e) = self.pay(gw, h.id, r.coin, "furniture", now) {
            self.refund(gw, h.id, mat, r.count, now);
            return Err(e);
        }
        match gw.store.mint(self.meta(0, now), Dest::bag(h.id), catalogue::spec(&r), "merchant") {
            Ok((id, _)) => {
                let it = gw.store.item(id).map_err(serr)?.ok_or_else(|| fail(code::INTERNAL, "lost"))?;
                ok(HResp::Crafted(crate::economy::wire::EItem::of(&it).info))
            }
            Err(e) => {
                self.refund(gw, h.id, mat, r.count, now);
                self.refund(gw, h.id, StackKind::COIN, r.coin, now);
                Err(serr(e))
            }
        }
    }

    fn pay_stack(&self, gw: &Gateway, hero: i64, kind: StackKind, n: u64, now: i64) -> R<()> {
        gw.store.stack_debit(self.meta(0, now), Owner::bag(hero), kind, n, "furniture").map(|_| ()).map_err(serr)
    }

    // ---- the yard

    fn strike(&self, gw: &Gateway, h: &Hero, here: (u8, u32), now: i64) -> R {
        if here.0 != YARD {
            return Err(bad("the dummy stands in the training yard"));
        }
        let sheet = crate::sheet::sheet_of(&*gw.store, h).map_err(serr)?;
        let row = &realm_core::CLASSES[sheet.class as usize];
        let w = row.weapon;
        let might = sheet.points[realm_core::tables::MIGHT] as u64 + sheet.gear[realm_core::tables::MIGHT] as u64;
        let damage = yard::strike_damage(w.damage, realm_core::tables::weapon_pct(sheet.gear_level), realm_core::tables::MIGHT_PCT as u64, might);
        let every_ms = w.every as i64 * 1000 / realm_core::TICK_HZ as i64;
        let mut st = self.st.lock().unwrap();
        let d = st.dummies.entry(h.id).or_default();
        let before = d.best;
        let hit = d.strike(now, damage, every_ms).ok_or_else(|| fail(code::SLOW_DOWN, "the dummy is struck as fast as the weapon swings"))?;
        let improved = hit.best > before;
        if improved {
            st.board.note(h.id, &h.name, h.class, hit.best);
        }
        drop(st);
        ok(HResp::Strike { damage: hit.damage, total: hit.total, dps: hit.dps, count: hit.count, best: hit.best })
    }

    // ---- campfires

    fn fires(&self, gw: &Gateway, here: (u8, u32)) -> Vec<(u16, u16)> {
        let mut v = fires(here.0).to_vec();
        if here.0 == HOUSE {
            let owner = self.st.lock().unwrap().reg.plot(here.1).map(|p| p.owner);
            if let Some(items) = owner.and_then(|o| gw.store.items_at(PlaceKind::House, o).ok()) {
                v.extend(items.iter().filter(|i| catalogue::is_hearth(i.spec.base)).map(|i| cell_px(i.place.slot)));
            }
        }
        v
    }

    fn sit(&self, gw: &Gateway, s: &Session, h: &Hero, here: (u8, u32), now: i64) -> R {
        let at = self.position(gw, s).ok_or_else(|| bad("not in a town"))?;
        let fires = self.fires(gw, here);
        if !fires.iter().any(|f| near(at, *f, FIRE_REACH_PX)) {
            return Err(bad("there is no fire near you"));
        }
        let mut st = self.st.lock().unwrap();
        let r = st.rest.entry(h.id).or_default();
        r.settle(now, Some(at));
        r.sit(now, at);
        let v = r.view(now);
        ok(HResp::Rest { sitting: v.sitting, secs: v.secs, rested_ms: v.rested_ms, pct: v.pct })
    }

    // ---- the market square

    fn stalls(&self, gw: &Gateway, here: (u8, u32), offset: u32, now: i64) -> R {
        if here.0 != MARKET {
            return Err(bad("the stalls stand in the market square"));
        }
        let q = ListingQuery { now, limit: STALL_SCAN, offset, ..ListingQuery::default() };
        let v = gw.store.listings(&q).map_err(serr)?;
        let mut by: BTreeMap<String, (u32, u64)> = BTreeMap::new();
        for p in v.iter().filter(|p| p.kind == ParcelKind::Listing) {
            let e = by.entry(p.from_name.clone()).or_insert((0, u64::MAX));
            e.0 += 1;
            e.1 = e.1.min(p.price);
        }
        let mut stalls: Vec<wire::Stall> = by.into_iter().map(|(seller, (listings, cheapest))| wire::Stall { seller, listings, cheapest }).collect();
        stalls.sort_by(|a, b| b.listings.cmp(&a.listings).then(a.seller.cmp(&b.seller)));
        stalls.truncate(STALLS_SHOWN);
        ok(HResp::Stalls(stalls))
    }
}

/// The rule a house has when the registry has no record (never used: a plot with an owner has one).
const OPEN_RULE: u8 = plots::LOCKED;
