//! The gateway: accounts, characters, town rooms, field tickets, the store calls players make, and the
//! applier that writes every field host's outing results to the store.
//!
//! Who acts for whom (store.md, "Who may run what"): a player's own things go to the store with the account as
//! the actor, so the store itself refuses what is not hers (`Gateway::player` only runs commands that
//! `who_may` marks Owner). What only the server may do, the gateway does as actor 0, and only after it has
//! checked the player's right itself: mail to another player's hero (`mail_send`), logging in (an account is
//! found or made), and the outing results (`apply`), which come from the field host, never from a client.

use crate::proto::*;
use crate::economy::Economy;
use crate::loot::{delivery_id, fall_rng, FirstKills, RewardKind, TicketLoot};
use crate::sheet::{level_for_xp, sheet_of};
use crate::town::Towns;
use realm_core::tables::{CLASSES, FIELDS, JOBS, JOB_LEVEL, NO_WAYSTONE, P_NONE, RACES};
use realm_core::Outing;
use realm_loot::{deliver, drops_percent_of, roll, Credit, Haul, RollKey, Smith, Source};
use realm_server::host::{Entry, Flush, HostCmd, HostHandle, HostMsg, HostOpts, KillBatch, Leave};
use crate::world::{Placed, World, WorldConfig};
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
    /// Dev only (`--dev-grant`, with dev login): a new hero is given a small kit (coin, embers, a few items, runes,
    /// potions) so the shell's bank, smith and merchants can be tried on day one. Minted as "grant".
    pub dev_grant: bool,
    /// Copies, the queue, the realm clock, vaults (`world`).
    pub world: WorldConfig,
}

/// The loot secret kept in `path`: 32 bytes from the OS's secure random source the first time (64 hex digits,
/// written 0600 with `tls::write_private`); the loot rolls use its first 8 bytes (`Config::secret` is a u64). An
/// older file of 16 hex digits is read as it always was, so a store keeps its secret.
pub fn load_secret(path: &std::path::Path) -> u64 {
    if let Ok(t) = std::fs::read_to_string(path) {
        let t = t.trim();
        if t.len() == 16 {
            if let Ok(v) = u64::from_str_radix(t, 16) {
                return v;
            }
        } else if t.len() == 64 {
            if let Ok(v) = u64::from_str_radix(&t[..16], 16) {
                return v;
            }
        }
    }
    let mut b = [0u8; 32];
    crate::tls::fill_random(&mut b);
    let hex: String = b.iter().map(|x| format!("{x:02x}")).collect();
    if let Err(e) = crate::tls::write_private(path, format!("{hex}\n").as_bytes()) {
        eprintln!("realm-gateway: {}: {e}", path.display());
    }
    u64::from_str_radix(&hex[..16], 16).unwrap_or(0)
}

/// Where a hero is. A hero is in one place: a town room, or a field (from the ticket until her final flush is
/// applied), never both and never two copies.
pub(crate) enum Loc {
    Town { conn: u64 },
    Field { ticket: u64, out: Sender<Vec<u8>> },
    /// Waiting in the realm's queue for a place in a field.
    Queue { conn: u64 },
}

pub(crate) struct Ticket {
    pub(crate) hero: i64,
    pub(crate) account: i64,
    pub(crate) field: u8,
    /// Applied so far, for the result pushed to her client.
    pub(crate) coin: u64,
    pub(crate) xp: u64,
    pub(crate) levels: u16,
    pub(crate) potions: u32,
    /// The host (`HostSlot::id`) she is in or on her way to.
    pub(crate) host: u32,
    /// The session that asked for it (a hero the host plays is recalled when it ends).
    pub(crate) conn: u64,
    pub(crate) driven: bool,
    /// Moved from a closing copy and not yet in the new one: her last flush number and the haul's coin she carries,
    /// banked (as a disconnect) if she never arrives.
    pub(crate) moved: Option<(u32, u64)>,
    /// The ticket's field key (`realm_server::host::Entry`): random, replaced by a fresh one at each move to another
    /// another copy admits her with the same ones.
    pub(crate) key: realm_server::TicketKey,
}

/// A vault's host: its row, seals, the code its party enters with, and who paid its key.
pub(crate) struct VaultSlot {
    pub(crate) vault: u8,
    pub(crate) seals: u8,
    pub(crate) code: u64,
    pub(crate) key: Option<(i64, u32)>,
}

pub(crate) struct HostSlot {
    pub(crate) handle: HostHandle,
    pub(crate) id: u32,
    pub(crate) field: u8,
    pub(crate) copy: u8,
    pub(crate) vault: Option<VaultSlot>,
    /// Being closed into this copy (rules section 11).
    pub(crate) closing: Option<u32>,
    /// A Stop has been sent.
    pub(crate) stopping: bool,
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
    /// Merchants, trade, the market and letters (job E1).
    pub economy: Arc<Economy>,
    pub(crate) locs: Mutex<HashMap<i64, Loc>>,
    pub(crate) tickets: Mutex<HashMap<u64, Ticket>>,
    pub(crate) hosts: Mutex<Vec<HostSlot>>,
    pub(crate) msgs: Sender<HostMsg>,
    /// Copies, the queue, the clock, vaults.
    pub world: World,
    loot: Mutex<HashMap<u64, TicketLoot>>,
    first_kills: Mutex<FirstKills>,
    ids: IdGen,
    pub(crate) stop: AtomicBool,
    threads: Mutex<Vec<JoinHandle<()>>>,
    next_conn: AtomicU64,
    ticket_rng: AtomicU64,
    /// Logins accepted and field tickets issued since start (for the LAN rehearsal's host report; not game state).
    pub logins: AtomicU64,
    pub tickets_issued: AtomicU64,
    /// Parties, guilds, friends, chat channels and the moderators' hooks (job T1).
    pub social: crate::social::Social,
    /// Houses and the shared places (job H1).
    pub homes: crate::homes::Homes,
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

pub(crate) fn bad(msg: &str) -> Resp {
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

pub(crate) fn item_info(i: &Item) -> ItemInfo {
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
        plus: i.spec.plus,
        socketed: i.socketed.iter().map(|s| s.map_or(0, |k| k.0)).collect(),
    }
}

impl Gateway {
    /// Starts the gateway on a store: the town ticker and the outing applier run on their own threads.
    pub fn start(store: Arc<SqliteStore>, cfg: Config) -> Arc<Gateway> {
        let (msgs, rx) = channel();
        let first_kills = Mutex::new(FirstKills::open(cfg.first_kills.as_deref()));
        let store_for_economy = store.clone();
        let world = World::new(cfg.world.clone());
        let gw = Arc::new(Gateway {
            store,
            cfg,
            towns: Towns::default(),
            economy: Economy::new(store_for_economy),
            locs: Mutex::new(HashMap::new()),
            tickets: Mutex::new(HashMap::new()),
            hosts: Mutex::new(Vec::new()),
            msgs,
            world,
            loot: Mutex::new(HashMap::new()),
            first_kills,
            ids: IdGen::new(),
            stop: AtomicBool::new(false),
            threads: Mutex::new(Vec::new()),
            next_conn: AtomicU64::new(1),
            logins: AtomicU64::new(0),
            tickets_issued: AtomicU64::new(0),
            ticket_rng: AtomicU64::new(IdGen::new().boot | 1),
            social: crate::social::Social::default(),
            homes: crate::homes::Homes::default(),
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
                    // Job R3: duels in the training yard step with the town.
                    g.social.run_duels();
                }
            })
            .expect("thread");
        let g = gw.clone();
        let world = std::thread::Builder::new()
            .name("world".into())
            .spawn(move || {
                while !g.stop.load(Ordering::Relaxed) {
                    std::thread::sleep(Duration::from_millis(crate::world::WORLD_STEP_MS));
                    g.world_step();
                }
            })
            .expect("thread");
        gw.threads.lock().unwrap().extend([applier, ticker, world]);
        gw.economy.spawn_sweeper();
        gw
    }

    pub fn conn_id(&self) -> u64 {
        self.next_conn.fetch_add(1, Ordering::Relaxed)
    }

    /// Opens a field copy (or a vault, `opts.sim.vault`) on its own thread group, on the realm's clock; returns the
    /// UDP address it listens on. The world opens and closes copies by itself; this is the first copy of a field.
    pub fn add_host(&self, opts: HostOpts) -> std::io::Result<std::net::SocketAddr> {
        self.spawn_host(opts, None).map(|(addr, _)| addr)
    }

    /// Heroes in each field copy now: (field, copy, heroes). Vaults are not listed.
    pub fn host_loads(&self) -> Vec<(u8, u8, u32)> {
        self.hosts.lock().unwrap().iter().filter(|h| h.vault.is_none()).map(|h| (h.field, h.copy, h.handle.heroes())).collect()
    }

    /// Stops the world, then the field hosts and vaults (every hero in them is banked and her result applied),
    /// then the applier and the town ticker.
    pub fn shutdown(&self) {
        self.world.stopping.store(true, Ordering::Relaxed);
        let slots: Vec<HostSlot> = self.hosts.lock().unwrap().drain(..).collect();
        for s in &slots {
            let _ = s.handle.cmds.send(HostCmd::Stop);
        }
        for mut s in slots {
            s.handle.stop();
        }
        self.stop.store(true, Ordering::Relaxed);
        self.economy.stop();
        let threads: Vec<_> = self.threads.lock().unwrap().drain(..).collect();
        for t in threads {
            let _ = t.join();
        }
    }

    pub(crate) fn random(&self) -> u64 {
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
        realm_ops::metrics::store_call(|| self.store.run(self.meta(account), cmd))
    }

    /// A change the server makes for a player after checking her right to it.
    pub(crate) fn server(&self, cmd: Cmd) -> Result<Reply> {
        realm_ops::metrics::store_call(|| self.store.run(self.meta(0), cmd))
    }

    /// The hero if she is this account's and alive.
    pub(crate) fn own_hero(&self, account: AccountId, hero: HeroId) -> Result<Hero> {
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
            Req::LoginDev { .. } | Req::LoginSteam { .. } if realm_ops::switches::refuse_login() => {
                return Ok(Resp::Err { code: code::DISABLED, msg: "the realm is closed for the moment; try again soon".into() });
            }
            Req::LoginDev { name } => return self.login_dev(s, &name),
            Req::LoginSteam { .. } => return Ok(Resp::Err { code: code::DISABLED, msg: "Steam login comes with the Steam job".into() }),
            _ => {}
        }
        let Some(account) = s.account else {
            return Ok(Resp::Err { code: code::NOT_LOGGED_IN, msg: "log in first".into() });
        };
        // The modules' requests (economy, social, world, homes: `proto::MODULES`), each served by its `gate.rs`.
        let mut req = req;
        for m in MODULES {
            match (m.serve)(self, s, account, req) {
                Ok(r) => return r,
                Err(back) => req = back,
            }
        }
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
                if self.cfg.dev_grant && self.cfg.dev_login {
                    self.dev_kit(id);
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
                if let Some((room, me, hero)) = s.town {
                    self.towns.input(room, me, dir);
                    self.social.duel_input(hero, dir);
                }
                Ok(Resp::Ok)
            }
            Req::Chat { text } => {
                let Some((room, me, _)) = s.town else { return Ok(bad("not in a town")) };
                // Muted, rate and word filter (job T1) before the room hears it.
                let text = match self.social.gate(account, crate::social::chan::SAY, &text, now_ms()) {
                    Ok(t) => t,
                    Err(r) => return Ok(r.resp()),
                };
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
                if crate::homes::catalogue::is_house_thing(it.spec.base) {
                    return Ok(bad("furniture is not worn"));
                }
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
            Req::Cards { hero } => self.cards(account, hero),
            Req::Buy { hero, kind, n } => self.buy(account, hero, kind, n),
            Req::Sell { hero, item } => self.sell(account, hero, item),
            // Ping and the logins were answered above; every module's requests by the module.
            _ => Ok(bad("no one serves that request")),
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
        self.world.sessions.lock().unwrap().insert(s.conn, s.out.clone());
        self.logins.fetch_add(1, Ordering::Relaxed);
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
        self.social.attach(hero, account, &h.name, h.class, h.progress.class_level, s.conn, s.out.clone(), crate::social::PLACE_TOWN);
        let (room, me, members) = self.towns.enter(info, s.out.clone());
        s.town = Some((room, me, hero));
        self.economy.attach(hero, room, s.out.clone());
        Ok(Resp::Town { room, me, size: crate::town::TOWN_PX, members })
    }

    /// Takes the session out of its town (and frees the hero), if it is in one. `only`: just if it is that hero.
    fn leave_town_of(&self, s: &mut Session, only: Option<i64>) {
        if let Some((room, me, hero)) = s.town {
            if only.is_none_or(|h| h == hero) {
                self.homes.depart(&self.towns, room, me, hero, now_ms());
                self.towns.leave(room, me);
                self.economy.detach(hero);
                let mut locs = self.locs.lock().unwrap();
                if matches!(locs.get(&hero), Some(Loc::Town { conn }) if *conn == s.conn) {
                    locs.remove(&hero);
                    self.social.detach_hero(hero, s.conn);
                }
                s.town = None;
            }
        }
    }

    /// A connection has ended.
    pub fn close_session(&self, s: &mut Session) {
        self.leave_town_of(s, None);
        self.social.detach_conn(s.conn);
        self.world_session_closed(s.conn);
    }

    fn field_ticket(&self, s: &mut Session, account: i64, hero: i64, field: u8) -> Result<Resp> {
        self.ask_field(s, account, hero, field, None)
    }

    /// A place in a field for a hero: a ticket to the emptiest copy with room, or a place in the realm's queue when
    /// the realm (or every copy of the field) is full. `drive`: the host plays her (dev bots).
    pub(crate) fn ask_field(&self, s: &mut Session, account: i64, hero: i64, field: u8, drive: Option<realm_server::driver::Drive>) -> Result<Resp> {
        if field as usize >= FIELDS.len() {
            return Ok(bad("no such field"));
        }
        if realm_ops::switches::field_stopped(field) {
            return Ok(Resp::Err { code: code::NO_FIELD, msg: "this field is closed for the moment".into() });
        }
        let h = self.own_hero(account, hero)?;
        // Her sheet is read before anything is reserved, so a failure leaves her where she was.
        let sheet = sheet_of(&*self.store, &h)?;
        if !self.hosts.lock().unwrap().iter().any(|x| x.vault.is_none() && x.field == field) {
            return Ok(Resp::Err { code: code::NO_FIELD, msg: "that field is closed".into() });
        }
        {
            let locs = self.locs.lock().unwrap();
            match locs.get(&hero) {
                Some(Loc::Field { .. }) => return Ok(Resp::Err { code: code::BUSY, msg: "she is in a field".into() }),
                Some(Loc::Queue { .. }) => return Ok(Resp::Err { code: code::BUSY, msg: "she is waiting for a place".into() }),
                Some(Loc::Town { conn }) if *conn != s.conn => return Ok(Resp::Err { code: code::BUSY, msg: "she is in a town".into() }),
                _ => {}
            }
        }
        // Leaving the town room (if she is in one here) must not free the hero: take the room only.
        let take_room = |s: &mut Session| {
            if let Some((room, me, th)) = s.town {
                if th == hero {
                    self.towns.leave(room, me);
                    self.economy.detach(hero);
                    s.town = None;
                }
            }
        };
        match self.place(account, hero, field, s.conn, &s.out, sheet, drive) {
            Placed::Ticket(r) => {
                take_room(s);
                Ok(r)
            }
            Placed::Queued(r) => {
                take_room(s);
                Ok(r)
            }
            Placed::Busy => Ok(Resp::Err { code: code::BUSY, msg: "she is already somewhere".into() }),
        }
    }

    /// Issues a ticket to host `host_id` for a hero who is free (checked by the caller under `locs`): she is
    /// placed in the field, the host is told to admit her. None if the host is gone or she was placed meanwhile.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn issue(&self, account: i64, hero: i64, field: u8, conn: u64, out: &Sender<Vec<u8>>, host_id: u32, sheet: realm_core::Sheet, drive: Option<realm_server::driver::Drive>) -> Option<(u16, u8, u64, realm_server::TicketKey)> {
        let h = self.store.hero(hero).ok().flatten()?;
        let mut outing = Outing::new();
        // Job R3: her BLOOD MARK and its ten-minute wait come with her from the last outing.
        self.social.outing_mark(hero, &mut outing);
        let way = h.progress.waystones.get(field as usize).copied().unwrap_or(-1);
        outing.waystone = if way >= 0 { way as u8 } else { NO_WAYSTONE };
        let ticket = loop {
            let t = self.random();
            if t != 0 && !self.tickets.lock().unwrap().contains_key(&t) {
                break t;
            }
        };
        // The ticket number is an id (the store's request ids); the key is the secret (`docs/realm/wire.md`).
        let key = crate::tls::random_key();
        let hosts = self.hosts.lock().unwrap();
        let slot = hosts.iter().find(|x| x.id == host_id && !x.stopping && x.closing.is_none())?;
        {
            let mut locs = self.locs.lock().unwrap();
            match locs.get(&hero) {
                Some(Loc::Field { .. }) => return None,
                Some(Loc::Town { conn: c }) | Some(Loc::Queue { conn: c }) if *c != conn => return None,
                _ => {}
            }
            locs.insert(hero, Loc::Field { ticket, out: out.clone() });
        }
        // Her party sees her in the field, and its next members go to the same copy (job T1).
        self.social.attach(hero, account, &h.name, h.class, h.progress.class_level, conn, out.clone(), crate::social::PLACE_FIELD);
        self.social.party_set_copy(hero, field, slot.copy, now_ms());
        self.tickets.lock().unwrap().insert(
            ticket,
            Ticket { hero, account, field, coin: 0, xp: 0, levels: 0, potions: 0, host: host_id, conn, driven: drive.is_some(), moved: None, key },
        );
        let mut e = Entry::new(ticket, hero as u64, sheet, outing);
        e.drive = drive;
        e.key = key;
        // Job R3b: the field tags her with her guild as she joins (what an altar war reads).
        e.guild = self.social.guild_of_account(account);
        let _ = slot.handle.cmds.send(HostCmd::Admit(e));
        self.tickets_issued.fetch_add(1, Ordering::Relaxed);
        Some((slot.handle.addr.port(), slot.copy, ticket, key))
    }

    /// The deck cards the hero may use: the novice twelve, one more at each even class level to 24 (the store's
    /// `card_owned`), and the pages the account has learned.
    fn cards(&self, account: i64, hero: i64) -> Result<Resp> {
        let h = self.own_hero(account, hero)?;
        let level = h.progress.class_level;
        let mut v: Vec<u16> = (0..limits::DECK_CARDS).filter(|&c| c < limits::NOVICE_CARDS || (c < limits::NOVICE_CARDS + 12 && level >= 2 * (c - limits::NOVICE_CARDS + 1))).collect();
        for c in self.store.owned_cards(account)? {
            if !v.contains(&c) {
                v.push(c);
            }
        }
        v.sort_unstable();
        Ok(Resp::Cards(v))
    }

    /// A merchant sells potions: coin first, then the potion, the coin given back if the bag cannot take it.
    fn buy(&self, account: i64, hero: i64, kind: u32, n: u32) -> Result<Resp> {
        self.own_hero(account, hero)?;
        let Some(price) = potion_price(kind) else { return Ok(bad("the merchant does not sell that")) };
        if n == 0 || n > 99 {
            return Ok(bad("1 to 99 at a time"));
        }
        let cost = price * n as u64;
        let bag = Owner::bag(hero);
        self.server(Cmd::StackDebit { from: bag, kind: StackKind::COIN, count: cost, reason: "buy".into() })?;
        let credit = Cmd::StackCredit { to: bag, kind: StackKind(kind), count: n as u64, minted: false, reason: "buy".into() };
        if let Err(e) = self.server(credit) {
            let _ = self.server(Cmd::StackCredit { to: bag, kind: StackKind::COIN, count: cost, minted: false, reason: "refund".into() });
            return Err(e);
        }
        Ok(Resp::Smith { item: 0, plus: 0, success: true, amount: cost })
    }

    /// A merchant buys an item from her bag at `sell_price`.
    fn sell(&self, account: i64, hero: i64, item: i64) -> Result<Resp> {
        self.own_hero(account, hero)?;
        let it = self.item_at(item, PlaceKind::Bag, hero)?;
        if crate::homes::catalogue::is_plaque(it.spec.base) {
            return Ok(bad("a plaque is kept, not sold"));
        }
        let price = sell_price(&it.spec);
        self.server(Cmd::SellItem { hero, item, price })?;
        Ok(Resp::Smith { item: 0, plus: 0, success: true, amount: price })
    }

    /// The `--dev-grant` kit: 3,500 coin (500, and 3,000 for the homes), 30 embers, four runes of MIGHT I, two healing draughts, and a rare, an
    /// uncommon and a common item of level 1 from The Fool's Road.
    fn dev_kit(&self, hero: i64) {
        let mut rng = realm_loot::rng::Rng::new(hero as u64 ^ 0xD3F_0001);
        let bag = Owner::bag(hero);
        for (kind, count) in [(StackKind::COIN, 500u64), (StackKind::material(0), 30), (StackKind::rune(0, 1), 4), (StackKind::potion(0), 2)] {
            let _ = self.server(Cmd::StackCredit { to: bag, kind, count, minted: true, reason: "grant".into() });
        }
        for (kind, count) in crate::homes::DEV_KIT {
            let _ = self.server(Cmd::StackCredit { to: bag, kind: StackKind(kind), count, minted: true, reason: "grant".into() });
        }
        for rarity in [2u8, 1, 0] {
            let spec = realm_loot::gear::make_item(&mut rng, 0, 1, rarity);
            let _ = self.server(Cmd::Mint { to: Dest::bag(hero), spec, reason: "grant".into() });
        }
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
                Ok(HostMsg::Unused { hero, ticket }) => self.unused(hero, ticket),
                Ok(HostMsg::Joined { ticket, .. }) => {
                    if let Some(t) = self.tickets.lock().unwrap().get_mut(&ticket) {
                        t.moved = None;
                    }
                }
                Ok(HostMsg::Moved { host, hero, ticket, seq, transfer, driven }) => self.on_moved(host, hero, ticket, seq, transfer, driven),
                Ok(HostMsg::Reward(b)) => self.on_reward(b),
                Ok(HostMsg::Closed { host }) => {
                    self.world.closed(host);
                    self.wars_host_gone(host);
                }
                Ok(HostMsg::Lost { host }) => {
                    self.lose_host(host);
                    self.wars_host_gone(host);
                }
                Ok(HostMsg::War { host, war, held, over }) => self.on_war(host, war, held, over),
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
    pub(crate) fn apply(&self, f: Flush) {
        let hero = f.hero as i64;
        // Job R3: her mark and its wait, for her next outing.
        if let Some((marked, struck_ago)) = f.mark {
            self.social.note_mark(hero, marked, struck_ago);
        }
        let info = self.tickets.lock().unwrap().get(&f.ticket).map(|t| (t.account, t.field));
        let Some((_account, field)) = info else { return };
        let mut done: Option<(u64, u64, u16, u32)> = None;
        // Job R3b: what each plundered fall took from her haul, for the hero who downed her.
        let mut spoils: Vec<(realm_server::host::Plundered, Haul)> = Vec::new();
        // The haul: halved by each fall (and by a disconnect), banked when the flush says it is safe.
        let haul = {
            let mut loot = self.loot.lock().unwrap();
            let tl = loot.entry(f.ticket).or_default();
            let mut rng = fall_rng(self.cfg.secret, f.ticket, f.seq);
            for k in 0..f.fell + (f.left == Some(Leave::Disconnect)) as u32 {
                let mut lost = tl.haul.fall(&mut rng);
                if let Some(p) = f.plunders.iter().find(|p| p.fall == k) {
                    // A bound item is never plundered: it stays in her haul.
                    for sp in lost.items.iter().filter(|sp| sp.bound) {
                        tl.haul.add_item(sp.clone());
                    }
                    lost.items.retain(|sp| !sp.bound);
                    spoils.push((*p, lost));
                }
            }
            let h = if f.banked { std::mem::take(&mut tl.haul) } else { Haul::new() };
            if f.left.is_some() {
                loot.remove(&f.ticket);
            }
            h
        };
        // Job R3b: banked coin she plundered goes in as the victims' coin moved to her.
        let plundered: Vec<(HeroId, u64)> = f.plunder_coin.iter().filter(|p| p.1 > 0).map(|&(v, n)| (v as i64, n)).collect();
        let plundered_sum: u64 = plundered.iter().map(|p| p.1).sum();
        match self.store.hero(hero) {
            Ok(Some(h)) => {
                // A hero rested at a campfire (job H1) banks a few percent more class XP while the rest lasts.
                let rested = f.xp * self.homes.rested_pct(hero, now_ms()) / 100;
                let f_xp = f.xp + rested;
                let total = h.progress.class_xp + f_xp;
                let levels = level_for_xp(total).max(h.progress.class_level).saturating_sub(h.progress.class_level);
                let mut potions: Vec<(StackKind, u64)> =
                    f.potions.iter().enumerate().filter(|(_, n)| **n > 0).map(|(p, n)| (StackKind::potion(p as u32), *n as u64)).collect();
                let waystone = f.waystone.filter(|&w| w != NO_WAYSTONE).map(|w| (field, w as i32));
                for attempt in 0..8u128 {
                    let delta = haul.clone().into_delta(OutingDelta { coin: f.coin, xp: f_xp, levels, items: Vec::new(), stacks: Vec::new(), potions_used: potions.clone(), waystone, plundered: plundered.clone() });
                    let id = ((f.ticket as u128) << 64) | f.seq as u128 | (attempt << 40);
                    let m = Meta::new(id, 0, now_ms());
                    match self.store.apply_outing(m, hero, delta) {
                        Ok(_) => {
                            done = Some((f.coin + plundered_sum, f_xp, levels, potions.iter().map(|p| p.1 as u32).sum()));
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
        for (p, lost) in spoils {
            self.plunder(hero, f.ticket, f.seq, p, lost);
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
            let left = f.left.map_or(255, Leave::code);
            let _ = tx.send(resp_frame(0, &Resp::Outing { hero, coin, xp, levels, potions, left }));
        }
    }

    /// A plundered fall (job R3b): what the fall took from her haul goes to the hero who downed her, in one store
    /// transaction (`Cmd::Plunder`: ledger lines on both sides, she stays each item's origin, his full bag spills to
    /// his mail). The request id is made of her ticket, the flush and the fall, so a flush applied twice moves
    /// nothing twice (the repeat is refused as `RequestMismatch` or answered as before). A fall that took nothing and
    /// paid no coin needs no record. Nothing is lost: if the store refuses the plunder for any other reason, what the
    /// fall took goes back to her, banked as her haul (`give_back`).
    fn plunder(&self, hero: i64, ticket: u64, seq: u32, p: realm_server::host::Plundered, lost: Haul) {
        if lost.is_empty() && p.coin == 0 {
            return;
        }
        let stacks: Vec<(StackKind, u64)> = lost.stacks.iter().map(|(k, v)| (StackKind(*k), *v)).collect();
        for attempt in 0..PLUNDER_TRIES {
            let m = Meta::new(plunder_id(ticket, seq, p.fall, attempt), 0, now_ms());
            match self.store.plunder(m, hero, p.by_hero as i64, lost.items.clone(), stacks.clone(), p.coin) {
                Ok(_) | Err(Error::RequestMismatch) => return,
                Err(Error::Db(_)) => std::thread::sleep(Duration::from_millis(50)),
                Err(e) => {
                    eprintln!("realm-gateway: plunder of hero {hero} by hero {} refused ({e}): it goes back to her", p.by_hero);
                    break;
                }
            }
        }
        self.give_back(hero, ticket, seq, p.fall, lost);
    }

    /// What a plundered fall took, banked back to her as her haul (her bag, her mail when full), with its own request
    /// id (attempt `PLUNDER_TRIES`), so it too is applied once.
    fn give_back(&self, hero: i64, ticket: u64, seq: u32, fall: u32, lost: Haul) {
        if lost.is_empty() {
            return;
        }
        for _ in 0..8 {
            let m = Meta::new(plunder_id(ticket, seq, fall, PLUNDER_TRIES), 0, now_ms());
            match self.store.apply_outing(m, hero, lost.clone().into_delta(OutingDelta::default())) {
                Ok(_) | Err(Error::RequestMismatch) => return,
                Err(Error::Db(_)) => std::thread::sleep(Duration::from_millis(50)),
                Err(e) => {
                    eprintln!("realm-gateway: plunder of hero {hero} could not go back to her: {e}");
                    return;
                }
            }
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
                let key = RollKey { field_seed: crate::world::roll_seed(b.field_seed, b.host), tick: b.tick, index: k.index, slot: c.slot };
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
            // A vault chest is the Archlich's chest (rolls from RARE, its card and trophy rolls), once for every two
            // of the chest's rolls (`chest_rolls`: two and one more per seal).
            RewardKind::Vault { level, .. } => Source::BossChest { boss: realm_core::tables::B_ARCHLICH, level, first_kill: self.first_kills.lock().unwrap().first(hero, realm_core::tables::B_ARCHLICH) },
        };
        let rounds = match kind {
            RewardKind::Vault { seals, .. } => (realm_core::chest_rolls(seals) as u32).div_ceil(2),
            _ => 1,
        };
        let mut loot = self.loot.lock().unwrap();
        let tl = loot.entry(ticket).or_default();
        let pct = *tl.pct.get_or_insert_with(|| drops_percent_of(&*self.store, account).unwrap_or(100));
        let mut found = Vec::new();
        for r in 0..rounds {
            // Each round its own key: the event index moved past any tick's real events.
            let k = RollKey { index: key.index ^ (r << 24), ..key };
            let src = if r == 0 { src } else { match src { Source::BossChest { boss, level, .. } => Source::BossChest { boss, level, first_kill: false }, s => s } };
            found.extend(roll(self.cfg.secret, &k, &Credit { luck: luck.max(0) as u32, drops_percent: pct }, &src, &mut tl.gate));
        }
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

    /// A ticket the host never used: the hero is free again. A hero moved from a closing copy who never arrived
    /// in the other is banked as a disconnect (half the haul's coin).
    fn unused(&self, hero: u64, ticket: u64) {
        let moved = self.tickets.lock().unwrap().get(&ticket).and_then(|t| t.moved);
        if let Some((seq, coin)) = moved {
            let lost = coin / 2;
            self.apply(Flush { hero, ticket, seq: seq + 1, coin: coin - lost, lost_coin: lost, xp: 0, potions: [0; 6], waystone: None, fell: 0, banked: true, left: Some(Leave::Disconnect), mark: None, plunders: Vec::new(), plunder_coin: Vec::new() });
            self.world.count(|s| s.moved_lost += 1);
            return;
        }
        self.loot.lock().unwrap().remove(&ticket);
        self.tickets.lock().unwrap().remove(&ticket);
        let tx = {
            let mut locs = self.locs.lock().unwrap();
            match locs.get(&(hero as i64)) {
                Some(Loc::Field { ticket: t, out }) if *t == ticket => {
                    let o = out.clone();
                    locs.remove(&(hero as i64));
                    Some(o)
                }
                _ => None,
            }
        };
        // Her client learns the ticket went unused (never entered: expired, or the vault was full or closing).
        if let Some(tx) = tx {
            let _ = tx.send(resp_frame(0, &Resp::Outing { hero: hero as i64, coin: 0, xp: 0, levels: 0, potions: 0, left: LEFT_UNUSED }));
        }
    }

    /// A host is gone: its outings are given up on the applier thread, after every message it sent (a flush in
    /// flight still banks what it says; one applied while the outings were dropped would be coin nobody was told of).
    pub(crate) fn host_lost(&self, host_id: u32) {
        let _ = self.msgs.send(HostMsg::Lost { host: host_id });
    }

    /// Forgets the outings of a host that died (a crash, `HostCmd::Abort`): what each hero banked is in the store;
    /// her haul is lost, as when the whole server is killed. She is free again at once.
    pub(crate) fn lose_host(&self, host_id: u32) {
        let lost: Vec<(u64, i64, u64, u64, u16, u32)> = {
            let mut tickets = self.tickets.lock().unwrap();
            let ids: Vec<u64> = tickets.iter().filter(|(_, t)| t.host == host_id).map(|(k, _)| *k).collect();
            ids.into_iter().filter_map(|k| tickets.remove(&k).map(|t| (k, t.hero, t.coin, t.xp, t.levels, t.potions))).collect()
        };
        for (ticket, hero, coin, xp, levels, potions) in lost {
            self.loot.lock().unwrap().remove(&ticket);
            let tx = {
                let mut locs = self.locs.lock().unwrap();
                match locs.get(&hero) {
                    Some(Loc::Field { ticket: t, out }) if *t == ticket => {
                        let o = out.clone();
                        locs.remove(&hero);
                        Some(o)
                    }
                    _ => None,
                }
            };
            if let Some(tx) = tx {
                let _ = tx.send(resp_frame(0, &Resp::Outing { hero, coin, xp, levels, potions, left: LEFT_LOST }));
            }
            self.world.count(|s| s.tickets_lost += 1);
        }
    }
}

/// Tries of a plunder (attempts 0..7 of `plunder_id`); attempt 7 is the give-back.
pub const PLUNDER_TRIES: u8 = 7;

/// The store request id of a plundered fall: the victim's ticket, bit 63 (no flush id, which holds a seq and an attempt
/// in bits 0..43, nor a delivery id, bit 31 and a count, sets it), the attempt in bits 56..59, the flush's number in
/// bits 16..47 and the fall in bits 0..15.
pub fn plunder_id(ticket: u64, seq: u32, fall: u32, attempt: u8) -> u128 {
    ((ticket as u128) << 64) | 1u128 << 63 | ((attempt as u128 & 0x7) << 56) | ((seq as u128) << 16) | (fall as u128 & 0xFFFF)
}

/// The Outing push's code for a hero whose field host died.
pub const LEFT_LOST: u8 = 6;
/// The Outing push's code for a ticket that was never used (she never entered).
pub const LEFT_UNUSED: u8 = 7;

/// The potion id a belt entry holds, for tests.
/// What a merchant asks for a potion of stack kind 100 + p, in coin (None: not a potion he sells).
pub fn potion_price(kind: u32) -> Option<u64> {
    const PRICES: [u64; 6] = [20, 60, 60, 120, 120, 400];
    kind.checked_sub(100).and_then(|p| PRICES.get(p as usize)).copied()
}

/// What a merchant pays for an item: `2 x (1 + level / 4)` coin times 1, 2, 5, 12 or 40 by rarity. Far under what the
/// smith would pay in embers and coin to make it, so selling is a way to be rid of an item, not a faucet.
pub fn sell_price(spec: &ItemSpec) -> u64 {
    const BY_RARITY: [u64; 5] = [1, 2, 5, 12, 40];
    2 * (1 + spec.item_level as u64 / 4) * BY_RARITY[(spec.rarity as usize).min(4)]
}

pub fn belt_potion(kind: u32) -> u8 {
    if kind >= 100 && kind < 106 { (kind - 100) as u8 } else { P_NONE }
}

#[cfg(test)]
mod plunder_tests {
    use super::*;
    use realm_server::host::Plundered;

    fn spec(level: u16) -> ItemSpec {
        ItemSpec { base: 3, gear_slot: 1, item_level: level, rarity: 1, lines: vec![(0, 2)], sockets: 0, plus: 0, bound: false }
    }

    /// Job R3b: a plundered fall's items and materials go to the hero who downed her, through the applier, once;
    /// bound items stay in her haul; the coin moves when he banks it, as hers.
    #[test]
    fn a_plundered_fall_moves_the_lost_haul_to_the_plunderer_once() {
        let db = std::env::temp_dir().join(format!("realm-plunder-{}.db", std::process::id()));
        for s in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{}{s}", db.display()));
        }
        let store = Arc::new(SqliteStore::open(&db).unwrap());
        let gw = Gateway::start(store.clone(), Config { dev_login: true, secret: 5, ..Config::default() });
        let acct = |n: &str| store.account_by_dev_name(Meta::system(gw.ids.next(), 1), n).unwrap();
        let (va, wa) = (acct("prey"), acct("hunter"));
        let victim = store.hero_create(Meta::system(gw.ids.next(), 1), va, "Prey", 0, 1, 0, false).unwrap();
        let winner = store.hero_create(Meta::system(gw.ids.next(), 1), wa, "Hunter", 0, 1, 0, false).unwrap();
        let (vt, wt) = (0x1111u64, 0x2222u64);
        let (tx, _rx) = channel();
        for (t, h, a) in [(vt, victim, va), (wt, winner, wa)] {
            gw.tickets.lock().unwrap().insert(t, Ticket { hero: h, account: a, field: 0, coin: 0, xp: 0, levels: 0, potions: 0, host: 1, conn: 0, driven: false, moved: None, key: Default::default() });
            gw.locs.lock().unwrap().insert(h, Loc::Field { ticket: t, out: tx.clone() });
        }
        {
            let mut loot = gw.loot.lock().unwrap();
            let tl = loot.entry(vt).or_default();
            for l in 1..=6 {
                tl.haul.add_item(spec(l));
            }
            // Bound: never plundered, whatever the fall picks.
            for l in 7..=8 {
                tl.haul.add_item(ItemSpec { bound: true, ..spec(l) });
            }
            tl.haul.add_stack(StackKind::material(1), 10);
        }
        let p = Plundered { fall: 0, by_hero: winner as u64, by_ticket: wt, coin: 40 };
        let f = Flush { hero: victim as u64, ticket: vt, seq: 1, coin: 0, lost_coin: 40, xp: 0, potions: [0; 6], waystone: None, fell: 1, banked: false, left: None, mark: None, plunders: vec![p], plunder_coin: Vec::new() };
        gw.apply(f.clone());
        let got = store.items_at(PlaceKind::Bag, winner).unwrap();
        assert!(!got.is_empty() && got.iter().all(|i| !i.spec.bound), "no bound item: {got:?}");
        assert_eq!(gw.loot.lock().unwrap()[&vt].haul.items.iter().filter(|i| i.bound).count(), 2, "her bound items stay");
        assert_eq!(got.len() + gw.loot.lock().unwrap()[&vt].haul.items.len(), 8, "nothing lost");
        assert!(got.iter().all(|i| i.origin_hero == Some(victim) && i.origin_account == va), "she stays the origin");
        assert_eq!(store.stack(Owner::bag(winner), StackKind::material(1)).unwrap(), 5);
        let n = got.len();
        // The same flush applied again moves nothing more (the plunder's request id is the flush's and the fall's).
        gw.apply(f);
        assert_eq!(store.items_at(PlaceKind::Bag, winner).unwrap().len(), n);
        // He banks 100 coin, 40 of it hers: banked as her coin moved to him, which her clawback plan reaches.
        let wf = Flush { hero: winner as u64, ticket: wt, seq: 1, coin: 60, lost_coin: 0, xp: 0, potions: [0; 6], waystone: None, fell: 0, banked: true, left: None, mark: None, plunders: vec![], plunder_coin: vec![(victim as u64, 40)] };
        gw.apply(wf);
        assert_eq!(store.stack(Owner::bag(winner), StackKind::COIN).unwrap(), 100);
        assert_eq!(gw.tickets.lock().unwrap()[&wt].coin, 100, "she is told all she banked");
        assert_eq!(store.clawback_plan(va, 0).unwrap().stacks.iter().filter(|s| s.1 == StackKind::COIN).map(|s| s.2).sum::<u64>(), 40);
        assert_eq!(store.stack(Owner::bag(winner), StackKind::material(1)).unwrap(), 5);
        assert!(store.verify().unwrap().ok());
        gw.shutdown();
        for s in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{}{s}", db.display()));
        }
    }

    #[test]
    fn plunder_ids_share_no_request_id_with_flushes_or_deliveries() {
        let t = 0xABCD_EF01_2345u64;
        for seq in [0u32, 1, 77, u32::MAX] {
            for fall in [0u32, 3, 65_535] {
                for attempt in 0..8u8 {
                    let p = plunder_id(t, seq, fall, attempt);
                    assert_eq!(p >> 64, t as u128);
                    assert!(p & (1 << 63) != 0);
                    for a in 0..8u128 {
                        assert_ne!(p, ((t as u128) << 64) | seq as u128 | (a << 40));
                    }
                    assert_ne!(p, delivery_id(t, seq));
                }
            }
        }
        assert_ne!(plunder_id(t, 1, 0, 0), plunder_id(t, 1, 1, 0));
        assert_ne!(plunder_id(t, 1, 0, 0), plunder_id(t, 2, 0, 0));
    }
}
