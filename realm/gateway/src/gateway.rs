//! The gateway: accounts, characters, town rooms, field tickets, the store calls players make, and the
//! applier that writes every field host's outing results to the store.
//!
//! Who acts for whom (store.md, "Who may run what"): a player's own things go to the store with the account as
//! the actor, so the store itself refuses what is not hers (`Gateway::player` only runs commands that
//! `who_may` marks Owner). What only the server may do, the gateway does as actor 0, and only after it has
//! checked the player's right itself: mail to another player's hero (`mail_send`), logging in (an account is
//! found or made), and the outing results (`apply`), which come from the field host, never from a client.

use crate::proto::*;
use crate::loot::{delivery_id, fall_rng, FirstKills, RewardKind, TicketLoot};
use crate::sheet::{level_for_xp, sheet_of};
use crate::town::Towns;
use realm_core::tables::{CLASSES, FIELDS, JOBS, JOB_LEVEL, NO_WAYSTONE, P_NONE, RACES};
use realm_core::Outing;
use realm_loot::{deliver, drops_percent_of, roll, Credit, Haul, RollKey, Smith, Source};
use realm_server::host::{self, Entry, Flush, HostCmd, HostHandle, HostMsg, HostOpts, KillBatch, Leave};
use realm_store::*;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// The store's "no job": a hero's job column is 0 by default, which is a real job's id.
pub const NO_JOB: u8 = 15;

#[derive(Clone, Debug, Default)]
pub struct Config {
    /// Dev login (a name, no password): only with `--dev-login`.
    pub dev_login: bool,
    /// The address clients are told to send field UDP to; empty means the address they reached the gateway at.
    pub public_host: String,
    /// The server's loot secret (`realm_loot::roll`): no client may know it. `load_secret` keeps one beside the db.
    pub secret: u64,
    /// Where first boss kills are kept (None: in memory).
    pub first_kills: Option<std::path::PathBuf>,
}

/// The loot secret kept in `path` (16 hex digits), made from the clock, the process and the OS's random hasher
/// the first time.
pub fn load_secret(path: &std::path::Path) -> u64 {
    if let Ok(t) = std::fs::read_to_string(path) {
        if let Ok(v) = u64::from_str_radix(t.trim(), 16) {
            return v;
        }
    }
    let v = IdGen::new().boot;
    let _ = std::fs::write(path, format!("{v:016x}\n"));
    v
}

/// Where a hero is. A hero is in one place: a town room, or a field (from the ticket until her final flush is
/// applied), never both and never two copies.
enum Loc {
    Town { conn: u64 },
    Field { ticket: u64, out: Sender<Vec<u8>> },
}

struct Ticket {
    hero: i64,
    account: i64,
    field: u8,
    /// Applied so far, for the result pushed to her client.
    coin: u64,
    xp: u64,
    levels: u16,
    potions: u32,
}

struct HostSlot {
    handle: HostHandle,
    copy: u8,
}

/// One connection's state.
pub struct Session {
    pub conn: u64,
    pub account: Option<i64>,
    pub town: Option<(u32, u16, i64)>,
    pub out: Sender<Vec<u8>>,
}

impl Session {
    pub fn new(conn: u64, out: Sender<Vec<u8>>) -> Session {
        Session { conn, account: None, town: None, out }
    }
}

struct IdGen {
    boot: u64,
    n: AtomicU64,
}

impl IdGen {
    fn new() -> IdGen {
        use std::hash::{BuildHasher, Hasher};
        let mut h = std::collections::hash_map::RandomState::new().build_hasher();
        h.write_u64(SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_nanos() as u64));
        h.write_u32(std::process::id());
        IdGen { boot: h.finish(), n: AtomicU64::new(1) }
    }
    /// A request id no earlier run of the gateway used (the boot number is random).
    fn next(&self) -> RequestId {
        ((self.boot as u128) << 64) | self.n.fetch_add(1, Ordering::Relaxed) as u128
    }
}

pub struct Gateway {
    pub store: Arc<SqliteStore>,
    pub cfg: Config,
    pub towns: Towns,
    locs: Mutex<HashMap<i64, Loc>>,
    tickets: Mutex<HashMap<u64, Ticket>>,
    hosts: Mutex<Vec<HostSlot>>,
    msgs: Sender<HostMsg>,
    loot: Mutex<HashMap<u64, TicketLoot>>,
    first_kills: Mutex<FirstKills>,
    ids: IdGen,
    stop: AtomicBool,
    threads: Mutex<Vec<JoinHandle<()>>>,
    next_conn: AtomicU64,
    ticket_rng: AtomicU64,
}

pub fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as i64)
}

pub fn err(e: Error) -> Resp {
    let (code, msg) = match &e {
        Error::NotYours(m) => (code::NOT_YOURS, m.clone()),
        Error::Full(m) => (code::FULL, m.clone()),
        Error::Missing(m) => (code::MISSING, m.clone()),
        Error::NameTaken => (code::NAME_TAKEN, "name taken".into()),
        Error::BadName => (code::BAD_NAME, "bad name".into()),
        Error::Insufficient { .. } => (code::INSUFFICIENT, format!("{e}")),
        Error::Refused => (code::REFUSED, "refused".into()),
        Error::Banned { .. } => (code::BANNED, "banned".into()),
        Error::Invalid(m) => (code::INVALID, m.clone()),
        Error::Deleted => (code::MISSING, "deleted".into()),
        Error::SlotTaken(_) | Error::Bound(_) | Error::LevelTooLow { .. } | Error::Expired => (code::INVALID, format!("{e}")),
        Error::RequestMismatch | Error::Db(_) | Error::Closed => (code::INTERNAL, "internal error".into()),
    };
    Resp::Err { code, msg }
}

fn bad(msg: &str) -> Resp {
    Resp::Err { code: code::BAD_REQUEST, msg: msg.into() }
}

fn hero_info(h: &Hero) -> HeroInfo {
    let p = &h.progress;
    HeroInfo {
        id: h.id,
        name: h.name.clone(),
        race: h.race,
        class: h.class,
        look: h.look,
        job: if (p.job as usize) < JOBS.len() { p.job } else { realm_core::tables::NONE },
        class_level: p.class_level,
        class_xp: p.class_xp,
        unspent: p.unspent,
        stats: p.stats,
        deck: p.deck.clone(),
        belt: p.belt,
        waystones: p.waystones,
        self_found: h.self_found,
        deleted: h.deleted_at.is_some(),
    }
}

fn item_info(i: &Item) -> ItemInfo {
    ItemInfo {
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
    }
}

impl Gateway {
    /// Starts the gateway on a store: the town ticker and the outing applier run on their own threads.
    pub fn start(store: Arc<SqliteStore>, cfg: Config) -> Arc<Gateway> {
        let (msgs, rx) = channel();
        let first_kills = Mutex::new(FirstKills::open(cfg.first_kills.as_deref()));
        let gw = Arc::new(Gateway {
            store,
            cfg,
            towns: Towns::default(),
            locs: Mutex::new(HashMap::new()),
            tickets: Mutex::new(HashMap::new()),
            hosts: Mutex::new(Vec::new()),
            msgs,
            loot: Mutex::new(HashMap::new()),
            first_kills,
            ids: IdGen::new(),
            stop: AtomicBool::new(false),
            threads: Mutex::new(Vec::new()),
            next_conn: AtomicU64::new(1),
            ticket_rng: AtomicU64::new(IdGen::new().boot | 1),
        });
        let g = gw.clone();
        let applier = std::thread::Builder::new().name("applier".into()).spawn(move || g.applier(rx)).expect("thread");
        let g = gw.clone();
        let ticker = std::thread::Builder::new()
            .name("towns".into())
            .spawn(move || {
                while !g.stop.load(Ordering::Relaxed) {
                    std::thread::sleep(Duration::from_millis(1000 / crate::town::STEP_HZ as u64));
                    g.towns.step();
                }
            })
            .expect("thread");
        gw.threads.lock().unwrap().extend([applier, ticker]);
        gw
    }

    pub fn conn_id(&self) -> u64 {
        self.next_conn.fetch_add(1, Ordering::Relaxed)
    }

    /// Opens a field copy of `opts.sim.field` on its own thread group; returns the UDP address it listens on.
    pub fn add_host(&self, mut opts: HostOpts) -> std::io::Result<std::net::SocketAddr> {
        opts.require_tickets = true;
        let handle = host::spawn(opts, Some(self.msgs.clone()))?;
        let addr = handle.addr;
        let mut hosts = self.hosts.lock().unwrap();
        let copy = hosts.iter().filter(|h| h.handle.field == handle.field).count() as u8;
        hosts.push(HostSlot { handle, copy });
        Ok(addr)
    }

    /// Heroes in each field copy now: (field, copy, heroes).
    pub fn host_loads(&self) -> Vec<(u8, u8, u32)> {
        self.hosts.lock().unwrap().iter().map(|h| (h.handle.field, h.copy, h.handle.heroes.load(Ordering::Relaxed))).collect()
    }

    /// Stops the field hosts (every hero in them is banked and her result applied), then the applier and the
    /// town ticker.
    pub fn shutdown(&self) {
        let slots: Vec<HostSlot> = self.hosts.lock().unwrap().drain(..).collect();
        for mut s in slots {
            s.handle.stop();
        }
        self.stop.store(true, Ordering::Relaxed);
        let threads: Vec<_> = self.threads.lock().unwrap().drain(..).collect();
        for t in threads {
            let _ = t.join();
        }
    }

    fn random(&self) -> u64 {
        // splitmix over an atomic counter seeded from the boot nonce: tickets are not guessable in a run.
        let mut z = self.ticket_rng.fetch_add(0x9E37_79B9_7F4A_7C15, Ordering::Relaxed).wrapping_add(0x9E37_79B9_7F4A_7C15);
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    // ---- store calls

    fn meta(&self, actor: AccountId) -> Meta {
        Meta::new(self.ids.next(), actor, now_ms())
    }

    /// A player's own change: the account is the actor and the store judges. Only commands `who_may` gives to an
    /// owner may go this way.
    fn player(&self, account: AccountId, cmd: Cmd) -> Result<Reply> {
        if who_may(&cmd) != Who::Owner {
            return Err(Error::Invalid(format!("{} is not a player's to run", cmd.name())));
        }
        self.store.run(self.meta(account), cmd)
    }

    /// A change the server makes for a player after checking her right to it.
    fn server(&self, cmd: Cmd) -> Result<Reply> {
        self.store.run(self.meta(0), cmd)
    }

    /// The hero if she is this account's and alive.
    fn own_hero(&self, account: AccountId, hero: HeroId) -> Result<Hero> {
        let h = self.store.hero(hero)?.ok_or_else(|| Error::Missing(format!("hero {hero}")))?;
        if h.account != account {
            return Err(Error::NotYours(format!("hero {hero}")));
        }
        if h.deleted_at.is_some() {
            return Err(Error::Deleted);
        }
        Ok(h)
    }

    fn smith(&self) -> Smith<'_, SqliteStore> {
        Smith::new(&*self.store, self.cfg.secret)
    }

    // ---- requests

    /// Answers one request. A reply of `None` is sent by the caller as `Resp::Ok`.
    pub fn handle(&self, s: &mut Session, req: Req) -> Resp {
        match self.dispatch(s, req) {
            Ok(r) => r,
            Err(e) => err(e),
        }
    }

    fn dispatch(&self, s: &mut Session, req: Req) -> Result<Resp> {
        match req {
            Req::Ping => return Ok(Resp::Pong),
            Req::LoginDev { name } => return self.login_dev(s, &name),
            Req::LoginSteam { .. } => return Ok(Resp::Err { code: code::DISABLED, msg: "Steam login comes with the Steam job".into() }),
            _ => {}
        }
        let Some(account) = s.account else {
            return Ok(Resp::Err { code: code::NOT_LOGGED_IN, msg: "log in first".into() });
        };
        match req {
            Req::ListHeroes => Ok(Resp::Heroes(self.store.heroes(account, true)?.iter().map(hero_info).collect())),
            Req::CreateHero { name, race, class, look, self_found } => {
                if !(1..CLASSES.len() as u8).contains(&class) || race as usize >= RACES.len() {
                    return Ok(bad("class 1..5, race 0..3"));
                }
                let id = match self.player(account, Cmd::HeroCreate { account, name, race, class, look, self_found })? {
                    Reply::Hero(h) => h,
                    r => return Err(Error::Db(format!("unexpected reply {r:?}"))),
                };
                // A new hero has no job: the column starts at 0, which is a job's id.
                if let Some(h) = self.store.hero(id)? {
                    let mut p = h.progress;
                    p.job = NO_JOB;
                    self.player(account, Cmd::HeroSave { hero: id, progress: p })?;
                }
                Ok(Resp::HeroCreated(id))
            }
            Req::DeleteHero { hero } => {
                self.leave_town_of(s, Some(hero));
                self.player(account, Cmd::HeroDelete { hero }).map(|_| Resp::Ok)
            }
            Req::UndeleteHero { hero } => self.player(account, Cmd::HeroUndelete { hero }).map(|_| Resp::Ok),
            Req::RenameHero { hero, name } => self.player(account, Cmd::HeroRename { hero, name }).map(|_| Resp::Ok),
            Req::EnterTown { hero } => self.enter_town(s, account, hero),
            Req::LeaveTown => {
                self.leave_town_of(s, None);
                Ok(Resp::Ok)
            }
            Req::TownInput { dir } => {
                if let Some((room, me, _)) = s.town {
                    self.towns.input(room, me, dir);
                }
                Ok(Resp::Ok)
            }
            Req::Chat { text } => {
                let Some((room, me, _)) = s.town else { return Ok(bad("not in a town")) };
                match self.towns.chat(room, me, &text) {
                    Ok(()) => Ok(Resp::Ok),
                    Err(crate::town::ChatError::SlowDown) => Ok(Resp::Err { code: code::SLOW_DOWN, msg: "slow down".into() }),
                    Err(crate::town::ChatError::Empty) => Ok(bad("empty line")),
                }
            }
            Req::FieldTicket { hero, field } => self.field_ticket(s, account, hero, field),
            Req::Inventory { hero } => self.inventory(account, hero),
            Req::BankDeposit { hero, what, tab } => self.bank(account, hero, what, tab, true),
            Req::BankWithdraw { hero, what, tab } => self.bank(account, hero, what, tab, false),
            Req::MailSend { hero, to_name, what } => self.mail_send(account, hero, &to_name, what),
            Req::MailTake { hero, what } => self.mail_take(account, hero, what),
            Req::SpendPoint { hero, stat, n } => {
                let h = self.own_hero(account, hero)?;
                let mut p = h.progress;
                if stat >= 6 || n == 0 || p.unspent < n {
                    return Ok(bad("no such stat or not enough points"));
                }
                p.stats[stat as usize] += n;
                p.unspent -= n;
                self.player(account, Cmd::HeroSave { hero, progress: p }).map(|_| Resp::Ok)
            }
            Req::SetDeck { hero, cards } => {
                let h = self.own_hero(account, hero)?;
                let mut p = h.progress;
                p.deck = cards;
                self.player(account, Cmd::HeroSave { hero, progress: p }).map(|_| Resp::Ok)
            }
            Req::SetBelt { hero, kinds } => {
                let h = self.own_hero(account, hero)?;
                let mut p = h.progress;
                p.belt = kinds;
                self.player(account, Cmd::HeroSave { hero, progress: p }).map(|_| Resp::Ok)
            }
            Req::ChooseJob { hero, job } => {
                let h = self.own_hero(account, hero)?;
                let ok = JOBS.get(job as usize).is_some_and(|j| j.class == h.class) && h.progress.class_level >= JOB_LEVEL as u16;
                if !ok {
                    return Ok(bad("that job is not hers to choose yet"));
                }
                let mut p = h.progress;
                p.job = job;
                self.player(account, Cmd::HeroSave { hero, progress: p }).map(|_| Resp::Ok)
            }
            Req::LearnPage { hero, card } => {
                self.own_hero(account, hero)?;
                self.player(account, Cmd::LearnPage { hero, card }).map(|_| Resp::Ok)
            }
            Req::Equip { hero, item } => {
                self.own_hero(account, hero)?;
                let it = self.store.item(item)?.ok_or_else(|| Error::Missing(format!("item {item}")))?;
                let to = Dest::at(PlaceKind::Worn, hero, 0, it.spec.gear_slot as u32);
                self.player(account, Cmd::MoveItem { item, to }).map(|_| Resp::Ok)
            }
            Req::Unequip { hero, item } => {
                self.own_hero(account, hero)?;
                self.player(account, Cmd::MoveItem { item, to: Dest::bag(hero) }).map(|_| Resp::Ok)
            }
            // The smith charges coin for sockets, so they go through it (the server acts, for her own hero and item).
            Req::Socket { hero, item, socket, kind } => {
                self.own_hero(account, hero)?;
                let coin = self.smith().socket(self.meta(0), hero, item, socket, StackKind(kind))?;
                Ok(Resp::Smith { item, plus: 0, success: true, amount: coin })
            }
            Req::Unsocket { hero, item, socket } => {
                self.own_hero(account, hero)?;
                let coin = self.smith().unsocket(self.meta(0), hero, item, socket)?;
                Ok(Resp::Smith { item, plus: 0, success: true, amount: coin })
            }
            Req::Salvage { hero, item } => {
                self.own_hero(account, hero)?;
                let r = self.smith().salvage(self.meta(0), hero, item)?;
                Ok(Resp::Smith { item: 0, plus: 0, success: true, amount: r.embers })
            }
            Req::Upgrade { hero, item } => {
                self.own_hero(account, hero)?;
                let r = self.smith().upgrade(self.meta(0), hero, item)?;
                Ok(Resp::Smith { item: r.item, plus: r.plus, success: r.success, amount: r.spent.embers })
            }
            Req::Reroll { hero, item } => {
                self.own_hero(account, hero)?;
                let new = self.smith().reroll(self.meta(0), hero, item)?;
                Ok(Resp::Smith { item: new, plus: 0, success: true, amount: 0 })
            }
            Req::Fuse { hero, stat, grade } => {
                self.own_hero(account, hero)?;
                let k = self.smith().fuse(self.meta(0), hero, stat as u32, grade as u32)?;
                Ok(Resp::Smith { item: 0, plus: 0, success: true, amount: k.0 as u64 })
            }
            Req::Ping | Req::LoginDev { .. } | Req::LoginSteam { .. } => unreachable!(),
        }
    }

    fn login_dev(&self, s: &mut Session, name: &str) -> Result<Resp> {
        if !self.cfg.dev_login {
            return Ok(Resp::Err { code: code::DISABLED, msg: "dev login is off".into() });
        }
        // An account is found or made: only the server may, so this is the gateway's own call.
        let account = self.store.account_by_dev_name(self.meta(0), name)?;
        if let Some(a) = self.store.account(account)? {
            if a.banned_until.is_some_and(|u| u > now_ms()) {
                return Ok(Resp::Err { code: code::BANNED, msg: "banned".into() });
            }
        }
        s.account = Some(account);
        Ok(Resp::Login { account })
    }

    fn enter_town(&self, s: &mut Session, account: i64, hero: i64) -> Result<Resp> {
        let h = self.own_hero(account, hero)?;
        self.leave_town_of(s, None);
        {
            let mut locs = self.locs.lock().unwrap();
            if locs.contains_key(&hero) {
                return Ok(Resp::Err { code: code::BUSY, msg: "she is already somewhere".into() });
            }
            locs.insert(hero, Loc::Town { conn: s.conn });
        }
        let info = Member { id: 0, name: h.name.clone(), class: h.class, race: h.race, level: h.progress.class_level, look: h.look };
        let (room, me, members) = self.towns.enter(info, s.out.clone());
        s.town = Some((room, me, hero));
        Ok(Resp::Town { room, me, size: crate::town::TOWN_PX, members })
    }

    /// Takes the session out of its town (and frees the hero), if it is in one. `only`: just if it is that hero.
    fn leave_town_of(&self, s: &mut Session, only: Option<i64>) {
        if let Some((room, me, hero)) = s.town {
            if only.is_none_or(|h| h == hero) {
                self.towns.leave(room, me);
                let mut locs = self.locs.lock().unwrap();
                if matches!(locs.get(&hero), Some(Loc::Town { conn }) if *conn == s.conn) {
                    locs.remove(&hero);
                }
                s.town = None;
            }
        }
    }

    /// A connection has ended.
    pub fn close_session(&self, s: &mut Session) {
        self.leave_town_of(s, None);
    }

    fn field_ticket(&self, s: &mut Session, account: i64, hero: i64, field: u8) -> Result<Resp> {
        if field as usize >= FIELDS.len() {
            return Ok(bad("no such field"));
        }
        let h = self.own_hero(account, hero)?;
        // Her sheet is read before anything is reserved, so a failure leaves her where she was.
        let sheet = sheet_of(&*self.store, &h)?;
        let mut outing = Outing::new();
        let way = h.progress.waystones[field as usize];
        outing.waystone = if way >= 0 { way as u8 } else { NO_WAYSTONE };
        let ticket = loop {
            let t = self.random();
            if t != 0 && !self.tickets.lock().unwrap().contains_key(&t) {
                break t;
            }
        };
        // The emptier copy of the field.
        let (port, copy) = {
            let hosts = self.hosts.lock().unwrap();
            let Some(slot) = hosts.iter().filter(|h| h.handle.field == field).min_by_key(|h| h.handle.heroes.load(Ordering::Relaxed)) else {
                return Ok(Resp::Err { code: code::NO_FIELD, msg: "that field is closed".into() });
            };
            (slot.handle.addr.port(), slot.copy)
        };
        {
            let mut locs = self.locs.lock().unwrap();
            match locs.get(&hero) {
                Some(Loc::Field { .. }) => return Ok(Resp::Err { code: code::BUSY, msg: "she is in a field".into() }),
                Some(Loc::Town { conn }) if *conn != s.conn => return Ok(Resp::Err { code: code::BUSY, msg: "she is in a town".into() }),
                _ => {}
            }
            locs.insert(hero, Loc::Field { ticket, out: s.out.clone() });
        }
        // Leaving the town room (if she is in one here) must not free the hero: take the room only.
        if let Some((room, me, th)) = s.town {
            if th == hero {
                self.towns.leave(room, me);
                s.town = None;
            }
        }
        self.tickets.lock().unwrap().insert(ticket, Ticket { hero, account, field, coin: 0, xp: 0, levels: 0, potions: 0 });
        let hosts = self.hosts.lock().unwrap();
        if let Some(slot) = hosts.iter().find(|h| h.handle.field == field && h.copy == copy) {
            let _ = slot.handle.cmds.send(HostCmd::Admit(Entry { ticket, hero: hero as u64, sheet, outing }));
        }
        Ok(Resp::Ticket { host: self.cfg.public_host.clone(), port, ticket, field, copy })
    }

    fn inventory(&self, account: i64, hero: i64) -> Result<Resp> {
        self.own_hero(account, hero)?;
        let mut inv = Inventory::default();
        for (kind, owner) in [(PlaceKind::Bag, hero), (PlaceKind::Worn, hero), (PlaceKind::Mail, hero), (PlaceKind::Bank, account)] {
            inv.items.extend(self.store.items_at(kind, owner)?.iter().map(item_info));
        }
        for o in [Owner::bag(hero), Owner { kind: PlaceKind::Mail, id: hero }, Owner::bank(account)] {
            for (k, n) in self.store.stacks(o)? {
                inv.stacks.push((o.kind as u8, k.0, n));
            }
        }
        Ok(Resp::Inventory(inv))
    }

    fn item_at(&self, item: i64, kind: PlaceKind, owner: i64) -> Result<Item> {
        let it = self.store.item(item)?.ok_or_else(|| Error::Missing(format!("item {item}")))?;
        if it.place.kind != kind || it.place.owner != owner {
            return Err(Error::NotYours(format!("item {item} is not there")));
        }
        Ok(it)
    }

    /// Bank deposit (bag to the account's bank) or withdrawal (bank to the hero's bag): her own things, so the
    /// store is the judge. The gateway only checks the thing is where the player says it is.
    fn bank(&self, account: i64, hero: i64, what: Thing, tab: u32, deposit: bool) -> Result<Resp> {
        self.own_hero(account, hero)?;
        let cmd = match what {
            Thing::Item(item) => {
                if deposit {
                    self.item_at(item, PlaceKind::Bag, hero)?;
                    Cmd::MoveItem { item, to: Dest::bank(account, tab) }
                } else {
                    self.item_at(item, PlaceKind::Bank, account)?;
                    Cmd::MoveItem { item, to: Dest::bag(hero) }
                }
            }
            Thing::Stack(kind, count) => {
                let (from, to) = if deposit { (Owner::bag(hero), Owner::bank(account)) } else { (Owner::bank(account), Owner::bag(hero)) };
                Cmd::StackTransfer { from, to, kind: StackKind(kind), count }
            }
        };
        self.player(account, cmd).map(|_| Resp::Ok)
    }

    /// Mail from her bag to a hero by name. To one of her own heroes it is the player's own move; to another
    /// player's hero it moves value between accounts, which only the server may do, so the gateway checks that
    /// the thing is in her bag and then does it as the server (the store still applies TRADE_LOCKED).
    fn mail_send(&self, account: i64, hero: i64, to_name: &str, what: Thing) -> Result<Resp> {
        self.own_hero(account, hero)?;
        let to = self.store.hero_by_name(to_name)?.ok_or_else(|| Error::Missing(format!("no hero named {to_name}")))?;
        if to.id == hero {
            return Ok(bad("that is you"));
        }
        let cmd = match what {
            Thing::Item(item) => {
                self.item_at(item, PlaceKind::Bag, hero)?;
                Cmd::MoveItem { item, to: Dest::any(PlaceKind::Mail, to.id) }
            }
            Thing::Stack(kind, count) => {
                let have = self.store.stack(Owner::bag(hero), StackKind(kind))?;
                if have < count {
                    return Err(Error::Insufficient { kind: StackKind(kind), have, want: count });
                }
                Cmd::StackTransfer { from: Owner::bag(hero), to: Owner { kind: PlaceKind::Mail, id: to.id }, kind: StackKind(kind), count }
            }
        };
        if to.account == account {
            self.player(account, cmd).map(|_| Resp::Ok)
        } else {
            self.server(cmd).map(|_| Resp::Ok)
        }
    }

    fn mail_take(&self, account: i64, hero: i64, what: Thing) -> Result<Resp> {
        self.own_hero(account, hero)?;
        let cmd = match what {
            Thing::Item(item) => {
                self.item_at(item, PlaceKind::Mail, hero)?;
                Cmd::MoveItem { item, to: Dest::bag(hero) }
            }
            Thing::Stack(kind, count) => Cmd::StackTransfer { from: Owner { kind: PlaceKind::Mail, id: hero }, to: Owner::bag(hero), kind: StackKind(kind), count },
        };
        self.player(account, cmd).map(|_| Resp::Ok)
    }

    // ---- the outing applier

    fn applier(&self, rx: Receiver<HostMsg>) {
        loop {
            match rx.recv_timeout(Duration::from_millis(100)) {
                Ok(HostMsg::Flush(f)) => self.apply(f),
                Ok(HostMsg::Kills(b)) => self.roll_kills(b),
                Ok(HostMsg::Unused { hero, ticket }) => {
                    self.loot.lock().unwrap().remove(&ticket);
                    self.tickets.lock().unwrap().remove(&ticket);
                    self.locs.lock().unwrap().remove(&(hero as i64));
                }
                Ok(HostMsg::Joined { .. }) | Ok(HostMsg::Closed) => {}
                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                    if self.stop.load(Ordering::Relaxed) {
                        break;
                    }
                }
                Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => break,
            }
        }
    }

    /// One field host flush into the store, in one `apply_outing`, with a request id made of the ticket and the
    /// flush's number: a flush sent twice (or retried after a database error) is applied once.
    fn apply(&self, f: Flush) {
        let hero = f.hero as i64;
        let info = self.tickets.lock().unwrap().get(&f.ticket).map(|t| (t.account, t.field));
        let Some((_account, field)) = info else { return };
        let mut done: Option<(u64, u64, u16, u32)> = None;
        // The haul: halved by each fall (and by a disconnect), banked when the flush says it is safe.
        let haul = {
            let mut loot = self.loot.lock().unwrap();
            let tl = loot.entry(f.ticket).or_default();
            let mut rng = fall_rng(self.cfg.secret, f.ticket, f.seq);
            for _ in 0..f.fell + (f.left == Some(Leave::Disconnect)) as u32 {
                tl.haul.fall(&mut rng);
            }
            let h = if f.banked { std::mem::take(&mut tl.haul) } else { Haul::new() };
            if f.left.is_some() {
                loot.remove(&f.ticket);
            }
            h
        };
        match self.store.hero(hero) {
            Ok(Some(h)) => {
                let total = h.progress.class_xp + f.xp;
                let levels = level_for_xp(total).max(h.progress.class_level).saturating_sub(h.progress.class_level);
                let mut potions: Vec<(StackKind, u64)> =
                    f.potions.iter().enumerate().filter(|(_, n)| **n > 0).map(|(p, n)| (StackKind::potion(p as u32), *n as u64)).collect();
                let waystone = f.waystone.filter(|&w| w != NO_WAYSTONE).map(|w| (field, w as i32));
                for attempt in 0..8u128 {
                    let delta = haul.clone().into_delta(OutingDelta { coin: f.coin, xp: f.xp, levels, items: Vec::new(), stacks: Vec::new(), potions_used: potions.clone(), waystone });
                    let id = ((f.ticket as u128) << 64) | f.seq as u128 | (attempt << 40);
                    let m = Meta::new(id, 0, now_ms());
                    match self.store.apply_outing(m, hero, delta) {
                        Ok(_) => {
                            done = Some((f.coin, f.xp, levels, potions.iter().map(|p| p.1 as u32).sum()));
                            break;
                        }
                        // She drank what she no longer has (the bag changed during the outing): apply the rest.
                        Err(Error::Insufficient { kind, have, .. }) => {
                            for p in potions.iter_mut().filter(|p| p.0 == kind) {
                                p.1 = have.min(p.1);
                            }
                            potions.retain(|p| p.1 > 0);
                        }
                        Err(Error::Db(_)) => std::thread::sleep(Duration::from_millis(50)),
                        Err(e) => {
                            eprintln!("realm-gateway: outing of hero {hero} not applied: {e}");
                            break;
                        }
                    }
                }
            }
            Ok(None) => eprintln!("realm-gateway: outing of unknown hero {hero}"),
            Err(e) => eprintln!("realm-gateway: outing of hero {hero}: {e}"),
        }
        let mut out = None;
        {
            let mut tickets = self.tickets.lock().unwrap();
            if let Some(t) = tickets.get_mut(&f.ticket) {
                if let Some((coin, xp, levels, potions)) = done {
                    t.coin += coin;
                    t.xp += xp;
                    t.levels += levels;
                    t.potions += potions;
                }
                out = Some((t.coin, t.xp, t.levels, t.potions));
            }
            if f.left.is_some() {
                tickets.remove(&f.ticket);
            }
        }
        let tx = {
            let mut locs = self.locs.lock().unwrap();
            let tx = match locs.get(&hero) {
                Some(Loc::Field { ticket, out }) if *ticket == f.ticket => Some(out.clone()),
                _ => None,
            };
            if f.left.is_some() && tx.is_some() {
                locs.remove(&hero);
            }
            tx
        };
        if let (Some(tx), Some((coin, xp, levels, potions))) = (tx, out) {
            let left = match f.left {
                None => 255,
                Some(Leave::Gate) => 0,
                Some(Leave::Waystone) => 1,
                Some(Leave::Disconnect) => 2,
                Some(Leave::Kicked) => 3,
                Some(Leave::Shutdown) => 4,
            };
            let _ = tx.send(resp_frame(0, &Resp::Outing { hero, coin, xp, levels, potions, left }));
        }
    }

    /// Rolls what a tick's kills drop for the ticketed heroes they credit: kept drops go to the store at once, the
    /// rest into each hero's haul.
    fn roll_kills(&self, b: KillBatch) {
        let accounts: HashMap<u64, (i64, i64)> = {
            let t = self.tickets.lock().unwrap();
            b.kills.iter().flat_map(|k| k.credited.iter()).filter_map(|c| t.get(&c.ticket).map(|t| (c.ticket, (t.account, c.hero as i64)))).collect()
        };
        let mut loot = self.loot.lock().unwrap();
        let mut kept: HashMap<u64, Vec<realm_loot::Found>> = HashMap::new();
        for k in &b.kills {
            let src = Source::Kill { kind: k.kind, level: k.level, flags: k.flags };
            for c in &k.credited {
                let Some(&(account, _)) = accounts.get(&c.ticket) else { continue };
                let tl = loot.entry(c.ticket).or_default();
                let pct = *tl.pct.get_or_insert_with(|| drops_percent_of(&*self.store, account).unwrap_or(100));
                let key = RollKey { field_seed: b.field_seed, tick: b.tick, index: k.index, slot: c.slot };
                let credit = Credit { luck: c.luck.max(0) as u32, drops_percent: pct };
                for found in roll(self.cfg.secret, &key, &credit, &src, &mut tl.gate) {
                    if let Some(now) = tl.haul.take(found) {
                        kept.entry(c.ticket).or_default().push(now);
                    }
                }
            }
        }
        for (ticket, list) in kept {
            let Some(&(_, hero)) = accounts.get(&ticket) else { continue };
            let n = {
                let tl = loot.entry(ticket).or_default();
                tl.n += 1;
                tl.n
            };
            let d = deliver(&*self.store, Meta::new(delivery_id(ticket, n), 0, now_ms()), hero, &list);
            for (i, e) in &d.failed {
                eprintln!("realm-gateway: drop {i} of hero {hero} not kept: {e}");
            }
        }
    }

    /// A tide's cache, a boss's chest or the world's chest for a hero in a field (the host will send these when the
    /// core has the events): rolled, and everything written to the store at once (a chest is not part of the haul).
    /// A boss's first kill by this hero is remembered here.
    pub fn reward(&self, ticket: u64, key: RollKey, luck: i32, kind: RewardKind) -> Option<realm_loot::Delivered> {
        let (account, hero) = {
            let t = self.tickets.lock().unwrap();
            let t = t.get(&ticket)?;
            (t.account, t.hero)
        };
        let src = match kind {
            RewardKind::Tide { field, level } => Source::TideCache { field, level },
            RewardKind::Boss { boss, level } => Source::BossChest { boss, level, first_kill: self.first_kills.lock().unwrap().first(hero, boss) },
            RewardKind::World { level, top } => Source::WorldChest { level, top },
        };
        let mut loot = self.loot.lock().unwrap();
        let tl = loot.entry(ticket).or_default();
        let pct = *tl.pct.get_or_insert_with(|| drops_percent_of(&*self.store, account).unwrap_or(100));
        let found = roll(self.cfg.secret, &key, &Credit { luck: luck.max(0) as u32, drops_percent: pct }, &src, &mut tl.gate);
        tl.n += 1;
        let id = delivery_id(ticket, tl.n);
        // Rewards are kept, never held in the haul: `take` returns every kept drop and holds the rest.
        let mut now = Vec::new();
        for f in found {
            let mut f = f;
            f.kept = true;
            now.push(f);
        }
        Some(deliver(&*self.store, Meta::new(id, 0, now_ms()), hero, &now))
    }

    /// Is this hero in a town or a field right now?
    pub fn is_placed(&self, hero: i64) -> bool {
        self.locs.lock().unwrap().contains_key(&hero)
    }

    /// Sends the hero out of her field (the operator's kick): she is banked and her result applied.
    pub fn kick(&self, hero: i64) {
        for s in self.hosts.lock().unwrap().iter() {
            let _ = s.handle.cmds.send(HostCmd::Kick(hero as u64));
        }
    }
}

/// The potion id a belt entry holds, for tests.
pub fn belt_potion(kind: u32) -> u8 {
    if kind >= 100 && kind < 106 { (kind - 100) as u8 } else { P_NONE }
}
