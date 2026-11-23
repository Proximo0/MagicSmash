//! The world (job W2, `docs/realm/world.md`): the realm's one clock, the copies of every field that open when one
//! fills and merge when they empty (rules section 11), the queue when the realm is full, vault instances with
//! keys, a time limit and a clean close (rules section 10), boss news for the whole realm, and the chests the
//! field hosts' REWARD events pay.
//!
//! The world thread steps every `WORLD_STEP_MS`: it reaps hosts that ended (a vault that closed, a copy that was
//! merged away, a host that died), asks the copies planner what each field needs, moves heroes out of a closing
//! copy, admits the head of the queue, tells the waiting their places, and sends boss news. Everything that comes
//! from a host (a moved hero, a reward, a close) arrives on the applier thread, in order with that host's flushes.

pub mod copies;
pub mod wars;
pub mod week;
pub mod wire;
/// Its messages on the gateway wire and its dispatch (`proto::WireModule`).
pub mod gate;

use crate::gateway::{bad, now_ms, Gateway, HostSlot, Loc, Session, VaultSlot};
use crate::loot::RewardKind;
use crate::proto::*;
use crate::sheet::sheet_of;
use copies::{choose, CopyLoad, CopyRules, Plan, Planner};
use realm_core::tables::{BOSS_ANNOUNCE, R_BOSS_CHEST, R_TIDE_CACHE, R_VAULT_CHEST, R_WORLD_EPIC, R_WORLD_RELIC, SKILL1_LEVEL, VAULTS, WORLD_ANNOUNCE};
use realm_core::{Sheet, Transfer};
use realm_loot::RollKey;
use realm_server::driver::Drive;
use realm_server::host::{self, Entry, Flush, HostCmd, HostOpts, Leave, RewardBatch, NOT_A_VAULT};
use realm_server::realm_clock::RealmClock;
use realm_server::sim::SimOpts;
use realm_server::world::realm_board;
use realm_store::{Cmd, Owner, StackKind, Store};
use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc::Sender;
use std::sync::Mutex;
use std::time::{Duration, Instant};
use wire::{BoardField, WReq, WResp, NEWS_FIELD_BOSS, NEWS_WORLD_BOSS};

/// How often the world thread steps (ms): a queue moves and a copy opens within a quarter second.
pub const WORLD_STEP_MS: u64 = 250;
/// A host that ended without saying it closed is taken for dead after this long (its last messages are applied
/// first).
pub const DEAD_GRACE: Duration = Duration::from_secs(1);
/// The class trial (rules section 3 and 10): a vault for one hero, needs no key, from class level 10.
pub const TRIAL_VAULT: u8 = 5;

/// What the realm is made of; the numbers of a live realm are the defaults.
#[derive(Clone, Debug)]
pub struct WorldConfig {
    pub copies: CopyRules,
    /// Heroes in fields and vaults (tickets) the realm holds before it queues (what one box carries).
    pub realm_cap: u32,
    /// Vaults open at once.
    pub vault_max: u32,
    /// The realm clock. None: kept from `epoch_file` (or a fresh one at speed 1 when there is none).
    pub clock: Option<RealmClock>,
    pub epoch_file: Option<std::path::PathBuf>,
    /// A copy's monsters, worker threads and seed base (a new copy of a field shares its first copy's seed: the
    /// same map).
    pub monsters: u32,
    pub threads: usize,
    pub seed: u64,
    pub vault_monsters: u32,
    /// Microseconds a tick for every field host (50,000: 20 Hz).
    pub tick_us: u32,
    /// Microseconds a tick for a vault's host (a test realm runs a vault's fifteen minutes fast; 0: flat out).
    pub vault_tick_us: u32,
    /// An unused ticket is handed back after this long (30 s; a test realm shortens it).
    pub ticket_ttl: Duration,
    /// Dev only: heroes the host plays (`WReq::BotTicket`, a vault's `drive_ticks`).
    pub dev_bots: bool,
}

impl Default for WorldConfig {
    fn default() -> Self {
        WorldConfig {
            copies: CopyRules::default(),
            realm_cap: 4_000,
            vault_max: 64,
            clock: None,
            epoch_file: None,
            monsters: 20_000,
            threads: 1,
            seed: 1,
            vault_monsters: 4_000,
            tick_us: 50_000,
            vault_tick_us: 50_000,
            ticket_ttl: host::TICKET_TTL,
            dev_bots: false,
        }
    }
}

/// What the world has done (the soak's report and the tests).
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct WorldStats {
    pub copies_opened: u64,
    pub merges: u64,
    pub merges_done: u64,
    pub moved: u64,
    pub moved_banked: u64,
    pub moved_lost: u64,
    pub queued: u64,
    pub queue_max: u64,
    pub admitted_from_queue: u64,
    pub vaults_opened: u64,
    pub vaults_closed: u64,
    pub keys_spent: u64,
    pub keys_refunded: u64,
    pub hosts_lost: u64,
    pub tickets_lost: u64,
    pub news: u64,
    pub chests: u64,
    pub trials_passed: u64,
}

/// A hero waiting for a place.
struct Waiter {
    account: i64,
    hero: i64,
    field: u8,
    conn: u64,
    out: Sender<Vec<u8>>,
    drive: Option<Drive>,
    told: u32,
}

#[derive(Default)]
struct State {
    planners: HashMap<u8, Planner>,
    queue: VecDeque<Waiter>,
    /// News already sent: (kind, field, clock tick of the event).
    announced: HashSet<(u8, u8, u64)>,
    /// Hosts that said they closed.
    closed: HashSet<u32>,
    /// Hosts seen ended without a close, and since when.
    ended: HashMap<u32, Instant>,
    /// The fields this realm runs (it keeps a copy of each open), and how each was first opened (a new copy is
    /// made the same way: the same seed, so the same map).
    fields: Vec<u8>,
    templates: HashMap<u8, SimOpts>,
    /// Counts of the hosts that have ended.
    retired: realm_server::host::HostCounts,
}

pub struct World {
    pub cfg: WorldConfig,
    pub clock: RealmClock,
    state: Mutex<State>,
    stats: Mutex<WorldStats>,
    next_host: AtomicU32,
    /// Every logged-in connection, for news.
    pub(crate) sessions: Mutex<HashMap<u64, Sender<Vec<u8>>>>,
    pub(crate) stopping: AtomicBool,
    /// Guild wars armed on the field copies and their summed results (job R3b, `wars.rs`).
    pub(crate) wars: Mutex<wars::Wars>,
}

/// A copy's roll key seed: copies of a field share the field's seed, so the host's id is mixed in.
pub fn roll_seed(field_seed: u64, host: u32) -> u64 {
    field_seed ^ (host as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15)
}

fn add_counts(c: &mut realm_server::host::HostCounts, k: &realm_server::host::HostCounts) {
    c.tides += k.tides;
    c.tides_won += k.tides_won;
    c.tides_lost += k.tides_lost;
    c.bosses += k.bosses;
    c.bosses_killed += k.bosses_killed;
    c.bosses_left += k.bosses_left;
    c.world_bosses += k.world_bosses;
    c.rewards += k.rewards;
    c.joined += k.joined;
    c.moved_in += k.moved_in;
    c.moved_out += k.moved_out;
    c.recalled += k.recalled;
    c.wars_begun += k.wars_begun;
    c.wars_ended += k.wars_ended;
}

impl World {
    pub fn new(cfg: WorldConfig) -> World {
        let clock = cfg.clock.clone().unwrap_or_else(|| match &cfg.epoch_file {
            Some(p) => realm_server::realm_clock::clock_from_epoch(p, 1),
            None => RealmClock::wall(0, 1),
        });
        World {
            cfg,
            clock,
            state: Mutex::new(State::default()),
            stats: Mutex::new(WorldStats::default()),
            next_host: AtomicU32::new(1),
            sessions: Mutex::new(HashMap::new()),
            stopping: AtomicBool::new(false),
            wars: Mutex::new(wars::Wars::default()),
        }
    }

    pub fn stats(&self) -> WorldStats {
        self.stats.lock().unwrap().clone()
    }

    pub(crate) fn count(&self, f: impl FnOnce(&mut WorldStats)) {
        f(&mut self.stats.lock().unwrap());
    }

    pub(crate) fn closed(&self, host: u32) {
        self.state.lock().unwrap().closed.insert(host);
    }

    /// Heroes waiting now.
    pub fn queue_len(&self) -> usize {
        self.state.lock().unwrap().queue.len()
    }
}

/// Where `place` put a hero.
pub(crate) enum Placed {
    Ticket(Resp),
    Queued(Resp),
    Busy,
}

impl Gateway {
    /// Starts a host on the realm's clock and registers it; `vault` makes it a vault's.
    pub(crate) fn spawn_host(&self, mut opts: HostOpts, vault: Option<VaultSlot>) -> std::io::Result<(std::net::SocketAddr, u32)> {
        let id = self.world.next_host.fetch_add(1, Ordering::Relaxed);
        opts.require_tickets = true;
        opts.id = id;
        opts.clock = Some(self.world.clock.clone());
        opts.ticket_ttl = self.world.cfg.ticket_ttl;
        opts.tick_us = if vault.is_some() { self.world.cfg.vault_tick_us } else { self.world.cfg.tick_us };
        let field = opts.sim.field;
        let sim_opts = opts.sim.clone();
        let handle = host::spawn(opts, Some(self.msgs.clone()))?;
        let addr = handle.addr;
        let mut hosts = self.hosts.lock().unwrap();
        let copy = if vault.is_some() {
            0
        } else {
            (0..=u8::MAX).find(|c| !hosts.iter().any(|h| h.vault.is_none() && h.field == field && h.copy == *c)).unwrap_or(u8::MAX)
        };
        if vault.is_none() {
            let mut st = self.world.state.lock().unwrap();
            if !st.fields.contains(&field) {
                st.fields.push(field);
            }
            st.templates.entry(field).or_insert_with(|| sim_opts.clone());
        }
        hosts.push(HostSlot { handle, id, field, copy, vault, closing: None, stopping: false });
        Ok((addr, id))
    }

    /// Opens a field's first copy with the world's numbers (`realm-gateway` does this for each `--fields`).
    pub fn open_field(&self, field: u8) -> std::io::Result<std::net::SocketAddr> {
        self.open_copy(field, 0).map(|(a, _)| a)
    }

    fn open_copy(&self, field: u8, port: u16) -> std::io::Result<(std::net::SocketAddr, u32)> {
        let c = &self.world.cfg;
        let template = self.world.state.lock().unwrap().templates.get(&field).cloned();
        let sim = template.unwrap_or(SimOpts { field, seed: c.seed + field as u64, monsters: c.monsters, threads: c.threads, bots: 0, rally_permille: 0, level: 0, vault: None });
        self.spawn_host(HostOpts { sim, port, tick_us: c.tick_us, ..HostOpts::default() }, None)
    }

    /// Tickets on each host now.
    fn ticket_loads(&self) -> HashMap<u32, u32> {
        let mut m = HashMap::new();
        for t in self.tickets.lock().unwrap().values() {
            *m.entry(t.host).or_insert(0) += 1;
        }
        m
    }

    fn copy_loads(&self, field: u8) -> Vec<CopyLoad> {
        let loads = self.ticket_loads();
        self.hosts
            .lock()
            .unwrap()
            .iter()
            .filter(|h| h.vault.is_none() && h.field == field && !h.stopping)
            .map(|h| CopyLoad { id: h.id, heroes: loads.get(&h.id).copied().unwrap_or(0), tide: h.handle.status.tide.load(Ordering::Relaxed) || h.handle.status.boss.load(Ordering::Relaxed), closing: h.closing.is_some() })
            .collect()
    }

    /// A ticket to the emptiest copy with room, or a place in the queue (the realm is full, or every copy of the
    /// field is). The caller has checked she is free.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn place(&self, account: i64, hero: i64, field: u8, conn: u64, out: &Sender<Vec<u8>>, sheet: Sheet, drive: Option<Drive>) -> Placed {
        let full = self.tickets.lock().unwrap().len() as u32 >= self.world.cfg.realm_cap;
        let queue_before = !self.world.state.lock().unwrap().queue.is_empty();
        // A party's heroes share a copy (job T1): the one a party mate's ticket went to, while it has room.
        let loads = self.copy_loads(field);
        let party = self.social.party_copy(hero, field, now_ms()).and_then(|c| {
            let hosts = self.hosts.lock().unwrap();
            let id = hosts.iter().find(|h| h.vault.is_none() && h.field == field && h.copy == c)?.id;
            loads.iter().find(|l| l.id == id && !l.closing && l.heroes < self.world.cfg.copies.cap).map(|l| l.id)
        });
        let copy = if full || queue_before { None } else { party.or_else(|| choose(&loads, &self.world.cfg.copies, 1)) };
        if let Some(host_id) = copy {
            return match self.issue(account, hero, field, conn, out, host_id, sheet, drive) {
                Some((port, copy, ticket, key)) => Placed::Ticket(Resp::Ticket { host: self.cfg.public_host.clone(), port, ticket, field, copy, key }),
                None => Placed::Busy,
            };
        }
        {
            let mut locs = self.locs.lock().unwrap();
            if matches!(locs.get(&hero), Some(Loc::Field { .. }) | Some(Loc::Queue { .. })) {
                return Placed::Busy;
            }
            locs.insert(hero, Loc::Queue { conn });
        }
        let (place, of) = {
            let mut st = self.world.state.lock().unwrap();
            let place = st.queue.len() as u32 + 1;
            st.queue.push_back(Waiter { account, hero, field, conn, out: out.clone(), drive, told: place });
            (place, st.queue.len() as u32)
        };
        self.world.count(|s| {
            s.queued += 1;
            s.queue_max = s.queue_max.max(of as u64);
        });
        Placed::Queued(Resp::World(WResp::Queued { hero, field, place, of }))
    }

    pub(crate) fn world_request(&self, s: &mut Session, account: i64, q: WReq) -> realm_store::Result<Resp> {
        match q {
            WReq::Board => Ok(Resp::World(self.board())),
            WReq::LeaveQueue { hero } => {
                self.own_hero(account, hero)?;
                self.leave_queue(|w| w.hero == hero);
                Ok(Resp::Ok)
            }
            WReq::BotTicket { hero, field, ticks } => {
                if !(self.cfg.dev_login && self.world.cfg.dev_bots) {
                    return Ok(Resp::Err { code: code::DISABLED, msg: "dev bots are off".into() });
                }
                let seed = self.random();
                self.ask_field(s, account, hero, field, Some(Drive { seed, ticks }))
            }
            WReq::Recall { hero } => {
                self.own_hero(account, hero)?;
                let driven = self.tickets.lock().unwrap().values().any(|t| t.hero == hero && t.driven);
                if !driven {
                    return Ok(bad("only a hero the host plays can be recalled"));
                }
                self.kick(hero);
                Ok(Resp::Ok)
            }
            WReq::VaultOpen { hero, vault, seals, drive_ticks } => self.vault_open(s, account, hero, vault, seals, drive_ticks),
            WReq::VaultJoin { hero, code, drive_ticks } => self.vault_join(s, account, hero, code, drive_ticks),
            WReq::Trial { hero } => {
                let h = self.own_hero(account, hero)?;
                Ok(Resp::World(self.trial_view(&h)?))
            }
        }
    }

    /// THE CLASS TRIAL as the trainer tells it to her.
    fn trial_view(&self, h: &realm_store::Hero) -> realm_store::Result<WResp> {
        Ok(WResp::Trial {
            hero: h.id,
            level: VAULTS[TRIAL_VAULT as usize].level as u16,
            passed: self.store.feats(h.id)?.contains(&realm_store::feats::CLASS_TRIAL),
            job: h.progress.job,
            job_level: realm_core::tables::JOB_LEVEL as u16,
            job_price: realm_loot::sinks::job_change_cost(h.progress.class_level.max(realm_core::tables::JOB_LEVEL as u16)),
        })
    }

    /// She won THE CLASS TRIAL: the feat is kept for good, and her client is told at once.
    fn trial_passed(&self, ticket: u64) {
        let Some(hero) = self.tickets.lock().unwrap().get(&ticket).map(|t| t.hero) else { return };
        if self.server(Cmd::HeroFeat { hero, feat: realm_store::feats::CLASS_TRIAL }).is_err() {
            return;
        }
        self.world.count(|s| s.trials_passed += 1);
        let view = match self.store.hero(hero) {
            Ok(Some(h)) => self.trial_view(&h).ok(),
            _ => None,
        };
        let out = match self.locs.lock().unwrap().get(&hero) {
            Some(Loc::Field { out, .. }) => Some(out.clone()),
            _ => None,
        };
        if let (Some(v), Some(out)) = (view, out) {
            let _ = out.send(resp_frame(0, &Resp::WorldPush(v)));
        }
    }

    fn drive_of(&self, ticks: u32) -> Result<Option<Drive>, Resp> {
        if ticks == 0 {
            return Ok(None);
        }
        if !(self.cfg.dev_login && self.world.cfg.dev_bots) {
            return Err(Resp::Err { code: code::DISABLED, msg: "dev bots are off".into() });
        }
        Ok(Some(Drive { seed: self.random(), ticks }))
    }

    /// The realm board: every field's countdowns, the world boss, the copies and the queue.
    pub fn board(&self) -> WResp {
        let clock = self.world.clock.now();
        let (fields, world_field, world_in) = realm_board(clock);
        let sat = |v: u64| v.min(u32::MAX as u64) as u32;
        let fields = fields.iter().map(|f| BoardField { field: f.field, tide_in: sat(f.tide_in), tide_left: sat(f.tide_left), boss: f.boss, boss_in: sat(f.boss_in) }).collect();
        let hosts = self.hosts.lock().unwrap();
        let copies = hosts.iter().filter(|h| h.vault.is_none()).map(|h| (h.field, h.copy, h.handle.heroes())).collect();
        let vaults = hosts.iter().filter(|h| h.vault.is_some()).count() as u32;
        WResp::Board { clock, fields, world_field, world_in: sat(world_in), queue: self.world.queue_len() as u32, copies, vaults }
    }

    fn leave_queue(&self, pick: impl Fn(&Waiter) -> bool) {
        let gone: Vec<i64> = {
            let mut st = self.world.state.lock().unwrap();
            let gone = st.queue.iter().filter(|w| pick(w)).map(|w| w.hero).collect();
            st.queue.retain(|w| !pick(w));
            gone
        };
        let mut locs = self.locs.lock().unwrap();
        for h in gone {
            if matches!(locs.get(&h), Some(Loc::Queue { .. })) {
                locs.remove(&h);
            }
        }
    }

    /// A connection ended: out of the queue, and the heroes the host plays for it are recalled.
    pub(crate) fn world_session_closed(&self, conn: u64) {
        self.world.sessions.lock().unwrap().remove(&conn);
        self.leave_queue(|w| w.conn == conn);
        let driven: Vec<i64> = self.tickets.lock().unwrap().values().filter(|t| t.conn == conn && t.driven).map(|t| t.hero).collect();
        for h in driven {
            self.kick(h);
        }
    }

    // ---- vaults

    fn vault_open(&self, s: &mut Session, account: i64, hero: i64, vault: u8, seals: u8, drive_ticks: u32) -> realm_store::Result<Resp> {
        let Some(row) = VAULTS.get(vault as usize) else { return Ok(bad("no such vault")) };
        if seals > row.seals_max {
            return Ok(bad("too many seals"));
        }
        let drive = match self.drive_of(drive_ticks) {
            Ok(d) => d,
            Err(r) => return Ok(r),
        };
        let h = self.own_hero(account, hero)?;
        if vault == TRIAL_VAULT && h.progress.class_level < SKILL1_LEVEL as u16 {
            return Ok(bad(&format!("THE CLASS TRIAL is from class level {SKILL1_LEVEL}; she is level {}", h.progress.class_level)));
        }
        if vault == TRIAL_VAULT && self.store.feats(hero)?.contains(&realm_store::feats::CLASS_TRIAL) {
            return Ok(bad("she has passed THE CLASS TRIAL already"));
        }
        let sheet = sheet_of(&*self.store, &h)?;
        if self.locs.lock().unwrap().get(&hero).is_some_and(|l| !matches!(l, Loc::Town { conn } if *conn == s.conn)) {
            return Ok(Resp::Err { code: code::BUSY, msg: "she is already somewhere".into() });
        }
        if self.tickets.lock().unwrap().len() as u32 >= self.world.cfg.realm_cap {
            return Ok(Resp::Err { code: code::FULL, msg: "the realm is full".into() });
        }
        let open = self.hosts.lock().unwrap().iter().filter(|x| x.vault.is_some()).count() as u32;
        if open >= self.world.cfg.vault_max {
            return Ok(Resp::Err { code: code::FULL, msg: "every vault is taken, try again in a minute".into() });
        }
        // The leader's key (the trial needs none): spent by the server, refunded if nobody ever enters.
        let key = if vault == TRIAL_VAULT {
            None
        } else {
            let kind = StackKind::key(row.field as u32);
            self.server(Cmd::StackDebit { from: Owner::bag(hero), kind, count: 1, reason: format!("vault key: {}", row.name) })?;
            self.world.count(|s| s.keys_spent += 1);
            Some((hero, row.field as u32))
        };
        let code = self.random() | 1;
        let c = &self.world.cfg;
        let sim = SimOpts { field: row.field, seed: self.random(), monsters: c.vault_monsters, threads: 1, bots: 0, rally_permille: 0, level: 0, vault: Some((vault, seals)) };
        let opened = self.spawn_host(HostOpts { sim, port: 0, tick_us: c.tick_us, ..HostOpts::default() }, Some(VaultSlot { vault, seals, code, key }));
        let (addr, host_id) = match opened {
            Ok(v) => v,
            Err(e) => {
                if let Some((h, f)) = key {
                    self.refund_key(h, f);
                }
                return Ok(Resp::Err { code: code::INTERNAL, msg: format!("vault: {e}") });
            }
        };
        self.world.count(|s| s.vaults_opened += 1);
        self.enter_vault(s, account, hero, host_id, addr.port(), code, vault, seals, sheet, drive)
    }

    fn vault_join(&self, s: &mut Session, account: i64, hero: i64, code: u64, drive_ticks: u32) -> realm_store::Result<Resp> {
        let drive = match self.drive_of(drive_ticks) {
            Ok(d) => d,
            Err(r) => return Ok(r),
        };
        let h = self.own_hero(account, hero)?;
        let sheet = sheet_of(&*self.store, &h)?;
        let found = self.hosts.lock().unwrap().iter().find(|x| x.vault.as_ref().is_some_and(|v| v.code == code) && !x.stopping).map(|x| {
            let v = x.vault.as_ref().unwrap();
            (x.id, x.handle.addr.port(), v.vault, v.seals, x.handle.status.vault.load(Ordering::Relaxed))
        });
        let Some((host_id, port, vault, seals, run)) = found else { return Ok(Resp::Err { code: code::MISSING, msg: "no such vault".into() }) };
        if run != realm_core::RUN_GOING || run == NOT_A_VAULT {
            return Ok(Resp::Err { code: code::REFUSED, msg: "that vault's run is over".into() });
        }
        let party = self.ticket_loads().get(&host_id).copied().unwrap_or(0);
        if party >= VAULTS[vault as usize].party_max as u32 {
            return Ok(Resp::Err { code: code::FULL, msg: "the party is full".into() });
        }
        if self.locs.lock().unwrap().get(&hero).is_some_and(|l| !matches!(l, Loc::Town { conn } if *conn == s.conn)) {
            return Ok(Resp::Err { code: code::BUSY, msg: "she is already somewhere".into() });
        }
        self.enter_vault(s, account, hero, host_id, port, code, vault, seals, sheet, drive)
    }

    #[allow(clippy::too_many_arguments)]
    fn enter_vault(&self, s: &mut Session, account: i64, hero: i64, host_id: u32, port: u16, code: u64, vault: u8, seals: u8, sheet: Sheet, drive: Option<Drive>) -> realm_store::Result<Resp> {
        let field = VAULTS[vault as usize].field;
        match self.issue_vault(account, hero, field, s.conn, &s.out, host_id, sheet, drive) {
            Some((ticket, key)) => {
                if let Some((room, me, th)) = s.town {
                    if th == hero {
                        self.towns.leave(room, me);
                        self.economy.detach(hero);
                        s.town = None;
                    }
                }
                let _ = port;
                Ok(Resp::World(WResp::Vault { code, vault, seals, host: self.cfg.public_host.clone(), port, ticket, key }))
            }
            None => Ok(Resp::Err { code: code::BUSY, msg: "she is already somewhere".into() }),
        }
    }

    /// `issue` for a vault's host (no copy rules).
    #[allow(clippy::too_many_arguments)]
    fn issue_vault(&self, account: i64, hero: i64, field: u8, conn: u64, out: &Sender<Vec<u8>>, host_id: u32, sheet: Sheet, drive: Option<Drive>) -> Option<(u64, realm_server::TicketKey)> {
        let ticket = loop {
            let t = self.random();
            if t != 0 && !self.tickets.lock().unwrap().contains_key(&t) {
                break t;
            }
        };
        let key = crate::tls::random_key();
        let hosts = self.hosts.lock().unwrap();
        let slot = hosts.iter().find(|x| x.id == host_id && !x.stopping)?;
        {
            let mut locs = self.locs.lock().unwrap();
            match locs.get(&hero) {
                Some(Loc::Field { .. }) | Some(Loc::Queue { .. }) => return None,
                Some(Loc::Town { conn: c }) if *c != conn => return None,
                _ => {}
            }
            locs.insert(hero, Loc::Field { ticket, out: out.clone() });
        }
        self.tickets.lock().unwrap().insert(
            ticket,
            crate::gateway::Ticket { hero, account, field, coin: 0, xp: 0, levels: 0, potions: 0, host: host_id, conn, driven: drive.is_some(), moved: None, key },
        );
        let mut e = Entry::new(ticket, hero as u64, sheet, realm_core::Outing::new());
        e.drive = drive;
        e.key = key;
        let _ = slot.handle.cmds.send(HostCmd::Admit(e));
        Some((ticket, key))
    }

    fn refund_key(&self, hero: i64, field: u32) {
        let r = self.server(Cmd::StackCredit { to: Owner::bag(hero), kind: StackKind::key(field), count: 1, minted: true, reason: "vault key returned: nobody entered".into() });
        if r.is_ok() {
            self.world.count(|s| s.keys_refunded += 1);
        }
    }

    // ---- what the hosts send (applier thread)

    /// A hero taken out of a closing copy: set down in the copy it closes into, in the same ring.
    pub(crate) fn on_moved(&self, from: u32, hero: u64, ticket: u64, seq: u32, transfer: Transfer, driven: Option<Drive>) {
        // A fresh key for the new admission, kept on her ticket and sent to her client over TLS in the Moved push:
        // nothing seen on the old copy's wire is any use on the new one. No ticket: no key, and no HELLO gets in.
        let key = {
            let mut t = self.tickets.lock().unwrap();
            t.get_mut(&ticket).map_or(realm_server::TicketKey::default(), |t| {
                t.key = crate::tls::random_key();
                t.key
            })
        };
        // Job R3b: she keeps her guild tag in the copy she is moved to.
        let account = self.tickets.lock().unwrap().get(&ticket).map(|t| t.account);
        let guild = account.map_or(0, |a| self.social.guild_of_account(a));
        let dest = {
            let hosts = self.hosts.lock().unwrap();
            let into = hosts.iter().find(|h| h.id == from).and_then(|h| h.closing);
            into.and_then(|id| hosts.iter().find(|h| h.id == id && !h.stopping && !h.handle.status.ended.load(Ordering::Relaxed))).map(|h| {
                let mut e = Entry::new(ticket, hero, transfer.sheet.clone(), transfer.outing.clone());
                e.seq = seq;
                e.arrive = Some(transfer.ring);
                e.drive = driven;
                e.key = key;
                e.guild = guild;
                let _ = h.handle.cmds.send(HostCmd::Admit(e));
                (h.id, h.field, h.copy, h.handle.addr.port())
            })
        };
        let Some((id, field, copy, port)) = dest else {
            // Nowhere to go: she is banked as if the host had stopped.
            self.apply(Flush { hero, ticket, seq: seq + 1, coin: transfer.outing.coin as u64, lost_coin: 0, xp: 0, potions: [0; 6], waystone: None, fell: 0, banked: true, left: Some(Leave::Shutdown), mark: None, plunders: Vec::new(), plunder_coin: Vec::new() });
            self.world.count(|s| s.moved_banked += 1);
            return;
        };
        let tx = {
            let mut tickets = self.tickets.lock().unwrap();
            let Some(t) = tickets.get_mut(&ticket) else { return };
            t.host = id;
            t.moved = Some((seq, transfer.outing.coin as u64));
            let driven = t.driven;
            drop(tickets);
            if driven {
                None
            } else {
                match self.locs.lock().unwrap().get(&(hero as i64)) {
                    Some(Loc::Field { ticket: tk, out }) if *tk == ticket => Some(out.clone()),
                    _ => None,
                }
            }
        };
        if let Some(tx) = tx {
            let _ = tx.send(resp_frame(0, &Resp::WorldPush(WResp::Moved { hero: hero as i64, field, copy, host: self.cfg.public_host.clone(), port, ticket, key })));
        }
        self.world.count(|s| s.moved += 1);
    }

    /// A REWARD event: each ticketed hero past the floor gets her chest, rolled and written at once.
    pub fn on_reward(&self, b: RewardBatch) {
        let kind = |top: bool| match b.kind {
            R_TIDE_CACHE => Some(RewardKind::Tide { field: b.source, level: b.level }),
            R_BOSS_CHEST => Some(RewardKind::Boss { boss: if b.boss == u8::MAX { realm_core::tables::field_boss_of(b.source, 0) } else { b.boss }, level: b.level }),
            R_WORLD_RELIC | R_WORLD_EPIC => Some(RewardKind::World { level: b.level, top }),
            R_VAULT_CHEST => Some(RewardKind::Vault { vault: b.vault, level: b.level, seals: b.seals }),
            _ => None,
        };
        let Some(k) = kind(b.kind == R_WORLD_RELIC) else { return };
        // THE CLASS TRIAL needs no key, so its win pays no chest (a free chest every five minutes would be a
        // faucet): the win is the feat that lets the trainer give her a job.
        if b.kind == R_VAULT_CHEST && b.vault == TRIAL_VAULT {
            for (c, _) in &b.heroes {
                self.trial_passed(c.ticket);
            }
            return;
        }
        for (c, _) in &b.heroes {
            let key = RollKey { field_seed: roll_seed(b.field_seed, b.host), tick: b.tick, index: b.index, slot: c.slot };
            if self.reward(c.ticket, key, c.luck, k).is_some() {
                self.world.count(|s| s.chests += 1);
            }
        }
    }

    // ---- the world's step

    pub fn world_step(&self) {
        if self.world.stopping.load(Ordering::Relaxed) {
            return;
        }
        self.reap_hosts();
        let fields = self.world.state.lock().unwrap().fields.clone();
        let now = now_ms().max(0) as u64;
        for &f in &fields {
            self.step_field(f, now);
        }
        // Job R3b: wars armed on every copy before their tide (and on a copy that opens during one).
        self.arm_wars(&fields);
        self.admit_queue();
        self.news();
    }

    /// Hosts that ended: a closed one is removed; one that died without closing loses its outings (after the
    /// applier has had time for its last messages); a vault nobody entered refunds its key.
    fn reap_hosts(&self) {
        let ended: Vec<(u32, bool)> = {
            let hosts = self.hosts.lock().unwrap();
            let st = self.world.state.lock().unwrap();
            hosts.iter().filter(|h| h.handle.status.ended.load(Ordering::Relaxed)).map(|h| (h.id, st.closed.contains(&h.id))).collect()
        };
        for (id, clean) in ended {
            if !clean {
                let first = *self.world.state.lock().unwrap().ended.entry(id).or_insert_with(Instant::now);
                if first.elapsed() < DEAD_GRACE {
                    continue;
                }
                if self.world.state.lock().unwrap().closed.contains(&id) {
                    // It closed after all (its message was late).
                } else {
                    self.host_lost(id);
                    self.world.count(|s| s.hosts_lost += 1);
                }
            }
            let slot = {
                let mut hosts = self.hosts.lock().unwrap();
                hosts.iter().position(|h| h.id == id).map(|i| hosts.remove(i))
            };
            {
                let mut st = self.world.state.lock().unwrap();
                st.closed.remove(&id);
                st.ended.remove(&id);
            }
            if let Some(mut s) = slot {
                s.handle.reap();
                let k = s.handle.status.counts.lock().unwrap().clone();
                add_counts(&mut self.world.state.lock().unwrap().retired, &k);
                // Anyone still holding a ticket to it (a ticket refused as it closed) is freed.
                self.host_lost(id);
                if let Some(v) = &s.vault {
                    self.world.count(|w| w.vaults_closed += 1);
                    if s.handle.status.counts.lock().unwrap().joined == 0 {
                        if let Some((h, f)) = v.key {
                            self.refund_key(h, f);
                        }
                    }
                } else if s.closing.is_some() {
                    self.world.count(|w| w.merges_done += 1);
                }
            }
        }
    }

    fn step_field(&self, field: u8, now_ms: u64) {
        // A closing copy: move out whoever is still in it; stop it once nobody holds a ticket to it.
        let loads = self.ticket_loads();
        let closing: Vec<(u32, Vec<u64>)> = self
            .hosts
            .lock()
            .unwrap()
            .iter()
            .filter(|h| h.vault.is_none() && h.field == field && h.closing.is_some() && !h.stopping)
            .map(|h| (h.id, h.handle.status.members.lock().unwrap().clone()))
            .collect();
        for (id, members) in closing {
            let mut hosts = self.hosts.lock().unwrap();
            let Some(h) = hosts.iter_mut().find(|h| h.id == id) else { continue };
            if loads.get(&id).copied().unwrap_or(0) == 0 {
                let _ = h.handle.cmds.send(HostCmd::Stop);
                h.stopping = true;
            } else {
                for m in members {
                    let _ = h.handle.cmds.send(HostCmd::MoveOut(m));
                }
            }
        }
        let cl = self.copy_loads(field);
        let plan = self.world.state.lock().unwrap().planners.entry(field).or_default().plan(&cl, &self.world.cfg.copies, now_ms);
        match plan {
            Some(Plan::Open) => {
                if self.open_copy(field, 0).is_ok() {
                    self.world.count(|s| s.copies_opened += 1);
                }
            }
            Some(Plan::Merge { from, into }) => {
                let mut hosts = self.hosts.lock().unwrap();
                if let Some(h) = hosts.iter_mut().find(|h| h.id == from) {
                    h.closing = Some(into);
                    self.world.count(|s| s.merges += 1);
                }
            }
            None => {}
        }
    }

    /// The queue's head goes in as soon as there is room (first come, first served; a waiter for a full field
    /// lets the next one by), and the rest are told their places when they change.
    fn admit_queue(&self) {
        loop {
            let cap = self.world.cfg.realm_cap;
            if self.tickets.lock().unwrap().len() as u32 >= cap {
                break;
            }
            let fields = self.world.state.lock().unwrap().fields.clone();
            let room: Vec<u8> = fields.into_iter().filter(|&f| choose(&self.copy_loads(f), &self.world.cfg.copies, 1).is_some()).collect();
            let pick = self.world.state.lock().unwrap().queue.iter().position(|w| room.contains(&w.field));
            let Some(i) = pick else { break };
            let Some(w) = self.world.state.lock().unwrap().queue.remove(i) else { break };
            {
                let mut locs = self.locs.lock().unwrap();
                if !matches!(locs.get(&w.hero), Some(Loc::Queue { conn }) if *conn == w.conn) {
                    continue;
                }
                locs.remove(&w.hero);
            }
            let sheet = match self.store.hero(w.hero).ok().flatten().map(|h| sheet_of(&*self.store, &h)) {
                Some(Ok(s)) => s,
                _ => continue,
            };
            let Some(host_id) = choose(&self.copy_loads(w.field), &self.world.cfg.copies, 1) else { continue };
            if let Some((port, copy, ticket, key)) = self.issue(w.account, w.hero, w.field, w.conn, &w.out, host_id, sheet, w.drive) {
                self.world.count(|s| s.admitted_from_queue += 1);
                let _ = w.out.send(resp_frame(0, &Resp::Ticket { host: self.cfg.public_host.clone(), port, ticket, field: w.field, copy, key }));
            }
        }
        let mut st = self.world.state.lock().unwrap();
        let of = st.queue.len() as u32;
        for (i, w) in st.queue.iter_mut().enumerate() {
            let place = i as u32 + 1;
            if place != w.told {
                w.told = place;
                let _ = w.out.send(resp_frame(0, &Resp::WorldPush(WResp::Queued { hero: w.hero, field: w.field, place, of })));
            }
        }
    }

    /// Boss news for every connection: a field boss ten minutes before it rises, the world boss thirty minutes
    /// before it rides (rules section 8).
    fn news(&self) {
        let clock = self.world.clock.now();
        let (fields, wf, world_in) = realm_board(clock);
        let mut items = Vec::new();
        {
            let mut st = self.world.state.lock().unwrap();
            for f in &fields {
                if f.boss_in > 0 && f.boss_in <= BOSS_ANNOUNCE as u64 && st.announced.insert((NEWS_FIELD_BOSS, f.field, clock + f.boss_in)) {
                    items.push(WResp::News { kind: NEWS_FIELD_BOSS, field: f.field, boss: f.boss, in_ticks: f.boss_in as u32 });
                }
            }
            if world_in > 0 && world_in <= WORLD_ANNOUNCE as u64 && st.announced.insert((NEWS_WORLD_BOSS, wf, clock + world_in)) {
                items.push(WResp::News { kind: NEWS_WORLD_BOSS, field: wf, boss: realm_core::tables::B_DEATH, in_ticks: world_in as u32 });
            }
            st.announced.retain(|k| k.2 + 1 >= clock);
        }
        if items.is_empty() {
            return;
        }
        let sessions: Vec<Sender<Vec<u8>>> = self.world.sessions.lock().unwrap().values().cloned().collect();
        for n in items {
            let frame = resp_frame(0, &Resp::WorldPush(n));
            for s in &sessions {
                let _ = s.send(frame.clone());
            }
            self.world.count(|s| s.news += 1);
        }
    }

    // ---- for tests and the operator

    /// Every host's heroes now: (host id, field, copy, vault?, hero numbers).
    pub fn world_members(&self) -> Vec<(u32, u8, u8, bool, Vec<u64>)> {
        self.hosts.lock().unwrap().iter().map(|h| (h.id, h.field, h.copy, h.vault.is_some(), h.handle.status.members.lock().unwrap().clone())).collect()
    }

    /// The realm clock as each running field copy last stepped it (vaults keep their own clock; a host that has
    /// ended is not listed).
    pub fn field_clocks(&self) -> Vec<u64> {
        self.hosts.lock().unwrap().iter().filter(|h| h.vault.is_none() && !h.handle.status.ended.load(Ordering::Relaxed)).map(|h| h.handle.status.clock.load(Ordering::Relaxed)).collect()
    }

    /// Every host's counts of tides, bosses and rewards, summed (a merged copy's are lost with it).
    pub fn world_counts(&self) -> realm_server::host::HostCounts {
        let mut c = self.world.state.lock().unwrap().retired.clone();
        for h in self.hosts.lock().unwrap().iter() {
            add_counts(&mut c, &h.handle.status.counts.lock().unwrap());
        }
        c
    }

    /// Kills a field copy's host as a crash would (no flush): the kill test of the world.
    pub fn abort_copy(&self, field: u8, copy: u8) -> bool {
        let hosts = self.hosts.lock().unwrap();
        match hosts.iter().find(|h| h.vault.is_none() && h.field == field && h.copy == copy) {
            Some(h) => h.handle.cmds.send(HostCmd::Abort).is_ok(),
            None => false,
        }
    }

    /// Where a hero is: 0 nowhere, 1 town, 2 a field or vault, 3 the queue.
    pub fn where_is(&self, hero: i64) -> u8 {
        match self.locs.lock().unwrap().get(&hero) {
            None => 0,
            Some(Loc::Town { .. }) => 1,
            Some(Loc::Field { .. }) => 2,
            Some(Loc::Queue { .. }) => 3,
        }
    }

    /// Tickets held now.
    pub fn ticket_count(&self) -> usize {
        self.tickets.lock().unwrap().len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::client::GatewayClient;
    use crate::gateway::{Config, LEFT_LOST};
    use realm_server::host::HostMsg;
    use realm_store::{Meta, OutingDelta, SqliteStore};
    use std::sync::Arc;

    /// The week once ended with a hero's coin in the store but not in what she was told: her host died with a
    /// flush on its way, and the host's outings were given up (on another thread) while the applier wrote it. The
    /// loss now queues behind the host's messages, so the flush is banked and counted in the LOST result.
    #[test]
    fn a_flush_sent_before_its_host_was_lost_is_banked_and_told() {
        let db = std::env::temp_dir().join(format!("realm-lost-host-{}.db", std::process::id()));
        let _ = std::fs::remove_file(&db);
        let store = Arc::new(SqliteStore::open(&db).unwrap());
        let gw = Gateway::start(store.clone(), Config { dev_login: true, secret: 5, ..Config::default() });
        let sim = SimOpts { field: 0, seed: 3, monsters: 50, threads: 1, bots: 0, rally_permille: 0, level: 0, vault: None };
        gw.add_host(HostOpts { sim, port: 0, ..HostOpts::default() }).unwrap();
        let l = crate::conn::listen(gw.clone(), "127.0.0.1:0").unwrap();
        let mut c = GatewayClient::connect_plain(&l.addr.to_string()).unwrap();
        assert!(matches!(c.login("lost").unwrap(), Resp::Login { .. }));
        let hero = match c.call(Req::CreateHero { name: "Lost".into(), race: 0, class: 1, look: 1, self_found: false }).unwrap() {
            Resp::HeroCreated(id) => id,
            r => panic!("{r:?}"),
        };
        let d = OutingDelta { xp: crate::sheet::xp_to_reach(12), levels: 11, waystone: Some((0, 0)), ..OutingDelta::default() };
        store.apply_outing(Meta::system(0x1057 << 64 | hero as u128, 1), hero, d).unwrap();
        let ticket = match c.call(Req::FieldTicket { hero, field: 0 }).unwrap() {
            Resp::Ticket { ticket, .. } => ticket,
            r => panic!("{r:?}"),
        };
        let host = gw.tickets.lock().unwrap()[&ticket].host;
        // She banked 120 coin and her host died: the flush is still queued when the gateway gives the host up.
        let f = Flush { hero: hero as u64, ticket, seq: 1, coin: 120, lost_coin: 0, xp: 0, potions: [0; 6], waystone: None, fell: 0, banked: true, left: None, mark: None, plunders: Vec::new(), plunder_coin: Vec::new() };
        gw.msgs.send(HostMsg::Flush(f)).unwrap();
        gw.host_lost(host);
        let told = c.wait_push(Duration::from_secs(10), |r| match r {
            Resp::Outing { coin, left, .. } if *left == LEFT_LOST => Some(*coin),
            _ => None,
        });
        let have = store.stacks(Owner::bag(hero)).unwrap().iter().find(|s| s.0 == StackKind::COIN).map_or(0, |s| s.1);
        assert_eq!((told.unwrap(), have), (Some(120), 120), "what she was told is what the store has");
        assert_eq!(gw.ticket_count(), 0);
        drop(l);
        gw.shutdown();
        let _ = std::fs::remove_file(&db);
    }
}
