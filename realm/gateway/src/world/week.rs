//! The world's proof (job W2): a realm of six fields and vaults lives a compressed week of bot play. Bots log in
//! through the gateway's TCP wire, make heroes, queue when the realm is full, fight (the host plays them, a core
//! class bot each), open and join vaults with keys, bank at waystones and in the town's bank, log out and come
//! back. The realm's clock runs fast enough that a week of tides, field bosses and world boss rides passes in
//! the run. A rush to one field opens copies; the rush ending merges them, moving heroes with their outing state.
//! Halfway, one field copy's host is killed as a crash would.
//!
//! Checked all along: no hero is ever in two hosts at once. Checked at the end: every hero is somewhere real or
//! nowhere (none lost in the world), no ticket is left, the coin each hero holds in the store (bag and bank) is
//! exactly the coin the gateway reported banked for her outings (nothing lost, nothing doubled, the killed host
//! included), nobody's banked coin went down when the host was killed, and the store verifies.
//!
//! `cargo test --release --test world` runs the short form; `realm-world` the long one (the station word
//! `world`).

use super::copies::CopyRules;
use super::wire::{WReq, WResp};
use super::WorldConfig;
use crate::client::GatewayClient;
use crate::gateway::{now_ms, Config, Gateway, LEFT_LOST};
use crate::proto::*;
use realm_core::tables::{FIELDS, VAULTS};
use realm_server::host::HostOpts;
use realm_server::realm_clock::RealmClock;
use realm_server::sim::SimOpts;
use realm_store::{Cmd, Meta, Owner, SqliteStore, StackKind, Store};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// Ticks in a week of the realm's clock.
pub const WEEK_TICKS: u64 = 7 * 24 * 3600 * realm_core::TICK_HZ as u64;
/// The vault the bots' keys open (THE MIRE CRYPT, keys of THE MOON MARSH).
const BOT_VAULT: u8 = 0;

#[derive(Clone, Debug)]
pub struct WeekOpts {
    pub bots: u32,
    /// Realm days to live (7: a week).
    pub days: f64,
    /// Real seconds the run should take (sets the clock's speed).
    pub secs: f64,
    pub monsters: u32,
    pub vault_monsters: u32,
    pub tick_us: u32,
    pub vault_tick_us: u32,
    pub copies: CopyRules,
    pub realm_cap: u32,
    pub vault_max: u32,
    /// Ticks a bot's outing lasts before she heads home.
    pub outing_ticks: u32,
    /// A leader (every fourth bot) opens a vault every this many sessions (the second first); a follower joins one
    /// when it can.
    pub vault_every: u64,
    /// Kill a field copy's host halfway.
    pub kill: bool,
    pub seed: u64,
    pub db: Option<PathBuf>,
    pub progress_secs: u64,
    /// The gateway and its bots speak TLS (an in-memory dev certificate the bots trust).
    pub tls: bool,
}

impl Default for WeekOpts {
    fn default() -> Self {
        WeekOpts {
            bots: 40,
            days: 7.0,
            secs: 40.0,
            monsters: 300,
            vault_monsters: 600,
            tick_us: 2_000,
            vault_tick_us: 250,
            copies: CopyRules { cap: 8, open_at: 6, merge_under: 4, max_copies: 3, merge_grace_ms: 500 },
            realm_cap: 30,
            vault_max: 3,
            outing_ticks: 400,
            vault_every: 3,
            kill: true,
            seed: 7,
            db: None,
            progress_secs: 0,
            tls: false,
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct WeekReport {
    pub secs: f64,
    pub days: f64,
    /// The days asked for.
    pub target_days: f64,
    pub cycles: u64,
    pub outings: u64,
    pub vault_runs: u64,
    pub vault_joins: u64,
    pub queued: u64,
    pub moved_bots: u64,
    pub lost_outings: u64,
    pub stats: super::WorldStats,
    pub counts: realm_server::host::HostCounts,
    pub peak_heroes: u32,
    pub peak_copies: u32,
    /// A hero seen in two hosts at once (samples).
    pub doubled: u64,
    pub samples: u64,
    /// Heroes whose store coin is not what was reported banked.
    pub coin_mismatches: Vec<String>,
    /// Heroes whose banked coin went down across the kill.
    pub kill_losses: u64,
    pub killed: bool,
    /// Heroes still placed or tickets left after the end.
    pub left_placed: u64,
    pub heroes: u64,
    pub errors: Vec<String>,
    /// The store's `verify`: None when clean.
    pub verify_error: Option<String>,
    /// Items, stacks and ledger rows.
    pub store_rows: (i64, i64, i64),
}

impl WeekReport {
    pub fn ok(&self) -> bool {
        let s = &self.stats;
        self.doubled == 0
            && self.coin_mismatches.is_empty()
            && self.kill_losses == 0
            && self.left_placed == 0
            && self.errors.is_empty()
            && self.verify_error.is_none()
            && self.days >= self.target_days * 0.999
            && s.copies_opened > 0
            && s.merges_done > 0
            && s.queue_max > 0
            && s.admitted_from_queue > 0
            && s.vaults_closed > 0
            && (!self.killed || s.hosts_lost == 1)
            // An outing is lost (its haul since the last bank; banked coin is checked above) only with the killed
            // host: every one the bots saw end that way is a ticket that host held.
            && self.lost_outings <= s.tickets_lost
            && (self.killed || s.tickets_lost == 0)
            && self.counts.world_bosses as f64 >= self.days / 7.0 * 27.0
    }

    pub fn line(&self) -> String {
        let s = &self.stats;
        let c = &self.counts;
        let (items, stacks, ledger) = self.store_rows;
        format!(
            "WORLD {} days={:.2} secs={:.0} heroes={} cycles={} outings={} vault_runs={} vault_joins={} queued={} queue_max={} admitted={} copies_opened={} merges={} moved={} moved_bots={} peak_copies={} peak_heroes={} tides={} won={} bosses={} killed={} world_bosses={} chests={} news={} keys={} refunds={} vaults_closed={} host_killed={} tickets_lost={} lost_outings={} doubled={}/{} coin_mismatch={} kill_losses={} left_placed={} errors={} verify={} items={items} stacks={stacks} ledger_rows={ledger}",
            if self.ok() { "ok" } else { "FAILED" },
            self.days,
            self.secs,
            self.heroes,
            self.cycles,
            self.outings,
            self.vault_runs,
            self.vault_joins,
            s.queued,
            s.queue_max,
            s.admitted_from_queue,
            s.copies_opened,
            s.merges_done,
            s.moved,
            self.moved_bots,
            self.peak_copies,
            self.peak_heroes,
            c.tides,
            c.tides_won,
            c.bosses,
            c.bosses_killed,
            c.world_bosses,
            s.chests,
            s.news,
            s.keys_spent,
            s.keys_refunded,
            s.vaults_closed,
            s.hosts_lost,
            s.tickets_lost,
            self.lost_outings,
            self.doubled,
            self.samples,
            self.coin_mismatches.len(),
            self.kill_losses,
            self.left_placed,
            self.errors.len(),
            self.verify_error.as_deref().unwrap_or("ok"),
        )
    }
}

/// What all bots share: the coin each hero was reported banked, open vault codes, tallies.
#[derive(Default)]
struct Shared {
    reported: HashMap<i64, u64>,
    heroes: HashMap<i64, i64>,
    codes: Vec<u64>,
    cycles: u64,
    outings: u64,
    vault_runs: u64,
    vault_joins: u64,
    queued: u64,
    moved_bots: u64,
    lost_outings: u64,
    errors: Vec<String>,
}

fn io(e: std::io::Error) -> String {
    e.to_string()
}

/// Waits for a ticket after a queue place (the ticket comes as a push).
fn await_ticket(gw: &mut GatewayClient, stop: &AtomicBool) -> Result<Option<u64>, String> {
    loop {
        let t = gw
            .wait_push(Duration::from_millis(200), |r| match r {
                Resp::Ticket { ticket, .. } => Some(*ticket),
                _ => None,
            })
            .map_err(io)?;
        if t.is_some() {
            return Ok(t);
        }
        if stop.load(Ordering::Relaxed) {
            return Ok(None);
        }
    }
}

/// Follows one outing to its end: the last Outing push (cumulative coin of the ticket) and why she left. On stop,
/// a hero the host plays is recalled.
fn await_outing(gw: &mut GatewayClient, hero: i64, stop: &AtomicBool, sh: &Mutex<Shared>) -> Result<(u64, u8), String> {
    let mut recalled = false;
    let start = Instant::now();
    loop {
        if stop.load(Ordering::Relaxed) && !recalled {
            let _ = gw.call(Req::World(WReq::Recall { hero })).map_err(io)?;
            recalled = true;
        }
        let got = gw
            .wait_push(Duration::from_millis(200), |r| match r {
                Resp::Outing { hero: h, coin, left, .. } if *h == hero => Some((*coin, *left)),
                Resp::WorldPush(WResp::Moved { hero: h, .. }) if *h == hero => Some((u64::MAX, 254)),
                _ => None,
            })
            .map_err(io)?;
        match got {
            Some((_, 254)) => sh.lock().unwrap().moved_bots += 1,
            Some((c, left)) => {
                if left != 255 {
                    return Ok((c, left));
                }
            }
            None => {}
        }
        if start.elapsed() > Duration::from_secs(240) {
            return Err(format!("hero {hero}: her outing never ended"));
        }
    }
}

fn prep(store: &SqliteStore, hero: &HeroInfo, keys: bool, n: u64) {
    if hero.class_xp == 0 && hero.class_level <= 1 {
        crate::harness::fast_prep_one(store, hero);
    }
    if keys {
        let kind = StackKind::key(VAULTS[BOT_VAULT as usize].field as u32);
        let have = store.stacks(Owner::bag(hero.id)).ok().and_then(|v| v.iter().find(|s| s.0 == kind).map(|s| s.1)).unwrap_or(0);
        if have == 0 {
            let id = (0x4B45_5953u128 << 96) | ((hero.id as u128) << 32) | n as u128;
            let _ = store.run(Meta::system(id, now_ms()), Cmd::StackCredit { to: Owner::bag(hero.id), kind, count: 2, minted: true, reason: "grant: bot keys".into() });
        }
    }
}

/// One bot's session: login, hero, town, then an outing (a field, or a vault) to its end, the coin to the bank.
#[allow(clippy::too_many_arguments)]
fn session(addr: &str, tls: Option<&std::sync::Arc<crate::tls::rustls::ClientConfig>>, b: u64, n: u64, o: &WeekOpts, clock: &RealmClock, store: &SqliteStore, stop: &AtomicBool, sh: &Mutex<Shared>) -> Result<(), String> {
    let mut gw = GatewayClient::connect_with(addr, tls).map_err(io)?;
    match gw.login(&format!("world-bot-{b}")).map_err(io)? {
        Resp::Login { .. } => {}
        r => return Err(format!("login: {r:?}")),
    }
    let mut heroes = gw.heroes().map_err(io)?;
    if heroes.is_empty() {
        let class = 1 + (b % 5) as u8;
        match gw.call(Req::CreateHero { name: format!("Week{b}"), race: (b % 4) as u8, class, look: b as u32, self_found: false }).map_err(io)? {
            Resp::HeroCreated(_) => {}
            r => return Err(format!("create hero: {r:?}")),
        }
        heroes = gw.heroes().map_err(io)?;
    }
    let hero = heroes.iter().find(|h| !h.deleted).ok_or("no hero")?.clone();
    let account = match store.hero(hero.id) {
        Ok(Some(h)) => h.account,
        _ => return Err("hero not in the store".into()),
    };
    sh.lock().unwrap().heroes.insert(hero.id, account);
    let leader = b % 4 == 0;
    prep(store, &hero, leader, n);
    match gw.call(Req::EnterTown { hero: hero.id }).map_err(io)? {
        Resp::Town { .. } => {}
        r => return Err(format!("enter town: {r:?}")),
    }
    let _ = gw.call(Req::World(WReq::Board)).map_err(io)?;
    // What to do: a leader opens a vault every third session; a follower joins an open one when there is one.
    let day_hour = clock.now() / (3600 * realm_core::TICK_HZ as u64) % 24;
    let code = if b % 4 == 1 { sh.lock().unwrap().codes.pop() } else { None };
    let mut started = false;
    // A leader's second session is a vault, then every `vault_every`th.
    if leader && n % o.vault_every.max(1) == 1 % o.vault_every.max(1) {
        let seals = (n % 4) as u8;
        match gw.call(Req::World(WReq::VaultOpen { hero: hero.id, vault: BOT_VAULT, seals, drive_ticks: 1 })).map_err(io)? {
            Resp::World(WResp::Vault { code, .. }) => {
                sh.lock().unwrap().codes.push(code);
                sh.lock().unwrap().vault_runs += 1;
                started = true;
            }
            Resp::Err { code: code::FULL, .. } | Resp::Err { code: code::INSUFFICIENT, .. } => {}
            r => return Err(format!("vault open: {r:?}")),
        }
    } else if let Some(c) = code {
        match gw.call(Req::World(WReq::VaultJoin { hero: hero.id, code: c, drive_ticks: 1 })).map_err(io)? {
            Resp::World(WResp::Vault { .. }) => {
                sh.lock().unwrap().vault_joins += 1;
                started = true;
            }
            Resp::Err { .. } => {}
            r => return Err(format!("vault join: {r:?}")),
        }
    }
    if !started {
        // A rush: for four realm hours out of every eight, half the bots want THE FOOL'S ROAD.
        let rush = (day_hour / 4) % 2 == 0 && b % 2 == 0;
        let field = if rush { 0 } else { ((b + n) % FIELDS.len() as u64) as u8 };
        let ticks = o.outing_ticks / 2 + (realm_core::rng_next(&mut (o.seed ^ b << 20 ^ n)) % o.outing_ticks as u64) as u32;
        match gw.call(Req::World(WReq::BotTicket { hero: hero.id, field, ticks })).map_err(io)? {
            Resp::Ticket { .. } => {}
            Resp::World(WResp::Queued { .. }) => {
                sh.lock().unwrap().queued += 1;
                if await_ticket(&mut gw, stop)?.is_none() {
                    let _ = gw.call(Req::World(WReq::LeaveQueue { hero: hero.id }));
                    // Let in just as she gave up: she is in the field, and her outing is followed (and recalled) like
                    // any other, or the coin it banks would be coin nobody was told of.
                    let late = gw
                        .wait_push(Duration::from_millis(1_000), |r| matches!(r, Resp::Ticket { .. }).then_some(()))
                        .map_err(io)?;
                    if late.is_none() {
                        return Ok(());
                    }
                }
            }
            Resp::Err { code: code::BUSY, .. } => return Ok(()),
            r => return Err(format!("bot ticket: {r:?}")),
        }
    }
    let (coin, left) = await_outing(&mut gw, hero.id, stop, sh)?;
    {
        let mut s = sh.lock().unwrap();
        *s.reported.entry(hero.id).or_insert(0) += coin;
        s.outings += 1;
        s.lost_outings += (left == LEFT_LOST) as u64;
    }
    // Home: the coin goes to the bank.
    let inv = gw.inventory(hero.id).map_err(io)?;
    let bag = inv.stack(1, 1);
    if bag > 0 {
        match gw.call(Req::BankDeposit { hero: hero.id, what: Thing::Stack(1, bag), tab: 0 }).map_err(io)? {
            Resp::Ok => {}
            r => return Err(format!("deposit: {r:?}")),
        }
    }
    sh.lock().unwrap().cycles += 1;
    Ok(())
}

/// Coin in a hero's bag and her account's bank.
fn coin_of(store: &SqliteStore, hero: i64, account: i64) -> u64 {
    let c = |o: Owner| store.stacks(o).ok().and_then(|v| v.iter().find(|s| s.0 == StackKind(1)).map(|s| s.1)).unwrap_or(0);
    c(Owner::bag(hero)) + c(Owner::bank(account))
}

/// The most the realm clock runs ahead of the slowest field copy (4 min 30 s of the realm, half a minute short of
/// a tide). Each host step sets its field to the realm's clock, so no step jumps farther than this: shorter than a
/// tide (5 min), a field boss's stay (8 min) and a world boss ride (15 min), every copy steps inside each of their
/// windows and counts each one, however slowly a loaded box runs it. Unbounded, a host the box starves for a
/// moment jumps a whole window at this speed (a ride is 45 ms of the wall) and the run counts fewer than the week
/// held.
pub const CLOCK_LEAD: u64 = (realm_core::tables::TIDE_LEN - realm_core::tables::secs(30)) as u64;
/// The clock has not moved this long (a field copy stopped stepping and never ended): an error, and the wall's
/// pace from then on so the run still ends.
const PACE_STALL: Duration = Duration::from_secs(30);

/// Moves the week's clock: `speed` ticks every 50 ms of the wall, held to `CLOCK_LEAD` past the slowest field copy
/// (each copy steps to the realm's clock on its next tick), until `ticks` or `stop`.
fn pace(gw: &Gateway, clock: &RealmClock, speed: u64, ticks: u64, stop: &AtomicBool, sh: &Mutex<Shared>) {
    let start = Instant::now();
    let (mut moved_at, mut free) = (Instant::now(), false);
    while !stop.load(Ordering::Relaxed) && clock.now() < ticks {
        let wall = start.elapsed().as_millis() as u64 * realm_core::TICK_HZ as u64 / 1000 * speed;
        let floor = gw.field_clocks().into_iter().min().unwrap_or(0);
        let to = if free { wall } else { wall.min(floor + CLOCK_LEAD) }.min(ticks);
        if to > clock.now() {
            clock.set(to);
            moved_at = Instant::now();
        } else if !free && moved_at.elapsed() > PACE_STALL {
            sh.lock().unwrap().errors.push(format!("the realm clock stalled at {}: a field copy stopped stepping ({:?})", clock.now(), gw.field_clocks()));
            free = true;
        }
        std::thread::sleep(Duration::from_millis(1));
    }
}

pub fn run_week(o: &WeekOpts) -> Result<WeekReport, String> {
    let db = o.db.clone().unwrap_or_else(|| std::env::temp_dir().join(format!("realm-week-{}-{}.db", std::process::id(), o.seed)));
    for ext in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{ext}", db.display()));
    }
    let store = Arc::new(SqliteStore::open(&db).map_err(|e| e.to_string())?);
    let ticks = (o.days * 24.0 * 3600.0 * realm_core::TICK_HZ as f64) as u64;
    let speed = ((ticks as f64 / (o.secs * realm_core::TICK_HZ as f64)).ceil() as u32).max(1);
    // The clock runs at `speed` but never more than `CLOCK_LEAD` ahead of the slowest field copy (`pace`).
    let clock = RealmClock::manual(0);
    let world = WorldConfig {
        copies: o.copies,
        realm_cap: o.realm_cap,
        vault_max: o.vault_max,
        clock: Some(clock.clone()),
        epoch_file: None,
        monsters: o.monsters,
        threads: 1,
        seed: o.seed,
        vault_monsters: o.vault_monsters,
        tick_us: o.tick_us,
        vault_tick_us: o.vault_tick_us,
        ticket_ttl: realm_server::host::TICKET_TTL,
        dev_bots: true,
    };
    let gw = Gateway::start(store.clone(), Config { dev_login: true, secret: o.seed ^ 0x3EE7, world, ..Config::default() });
    for f in 0..FIELDS.len() as u8 {
        let sim = SimOpts { field: f, seed: o.seed + f as u64, monsters: o.monsters, threads: 1, bots: 0, rally_permille: 0, level: 0, vault: None };
        gw.add_host(HostOpts { sim, port: 0, ..HostOpts::default() }).map_err(|e| e.to_string())?;
    }
    let (server_tls, client_tls) = if o.tls { crate::tls::loopback_pair().map(|(s, c)| (Some(s), Some(c)))? } else { (None, None) };
    let listener = crate::conn::listen_tls(gw.clone(), "127.0.0.1:0", server_tls).map_err(|e| e.to_string())?;
    let addr = listener.addr.to_string();
    let stop = Arc::new(AtomicBool::new(false));
    let sh = Arc::new(Mutex::new(Shared::default()));
    let start = Instant::now();
    let pacer = {
        let (gw, clock, stop, sh) = (gw.clone(), clock.clone(), stop.clone(), sh.clone());
        std::thread::spawn(move || pace(&gw, &clock, speed as u64, ticks, &stop, &sh))
    };
    let mut threads = Vec::new();
    for b in 0..o.bots as u64 {
        let (addr, stop, sh, o2, clock, store) = (addr.clone(), stop.clone(), sh.clone(), o.clone(), clock.clone(), store.clone());
        let client_tls = client_tls.clone();
        threads.push(std::thread::spawn(move || {
            let mut n = 0u64;
            let mut rng = o2.seed ^ (b << 32) ^ 0xB07;
            while !stop.load(Ordering::Relaxed) {
                if let Err(e) = session(&addr, client_tls.as_ref(), b, n, &o2, &clock, &store, &stop, &sh) {
                    if !stop.load(Ordering::Relaxed) {
                        sh.lock().unwrap().errors.push(format!("bot {b}: {e}"));
                    }
                }
                n += 1;
                // Logged out: a pause, longer in the realm's night (realm hours 0 to 6), before logging in again.
                let night = clock.now() / (3600 * realm_core::TICK_HZ as u64) % 24 < 6;
                let ms = 20 + realm_core::rng_next(&mut rng) % if night { 1_500 } else { 300 };
                let end = Instant::now() + Duration::from_millis(ms);
                while Instant::now() < end && !stop.load(Ordering::Relaxed) {
                    std::thread::sleep(Duration::from_millis(10));
                }
            }
        }));
    }
    // The watcher: no hero in two hosts at once; peaks; the kill halfway.
    let mut rep = WeekReport { target_days: o.days, ..WeekReport::default() };
    let mut killed_at: Option<HashMap<i64, u64>> = None;
    let samples = AtomicU64::new(0);
    let mut next_report = Instant::now() + Duration::from_secs(o.progress_secs.max(1));
    while clock.now() < ticks {
        std::thread::sleep(Duration::from_millis(20));
        let members = gw.world_members();
        let mut seen = HashSet::new();
        for (_, _, _, _, m) in &members {
            for h in m {
                if !seen.insert(*h) {
                    rep.doubled += 1;
                }
            }
        }
        samples.fetch_add(1, Ordering::Relaxed);
        rep.peak_heroes = rep.peak_heroes.max(seen.len() as u32);
        rep.peak_copies = rep.peak_copies.max(members.iter().filter(|m| !m.3).count() as u32);
        if o.kill && killed_at.is_none() && clock.now() >= ticks / 2 {
            // The busiest field copy dies as a crash would; first, what everyone has banked.
            let snapshot: HashMap<i64, u64> = sh.lock().unwrap().heroes.iter().map(|(&h, &a)| (h, coin_of(&store, h, a))).collect();
            let target = members.iter().filter(|m| !m.3).max_by_key(|m| (m.4.len(), m.0)).map(|m| (m.1, m.2));
            if let Some((f, c)) = target {
                rep.killed = gw.abort_copy(f, c);
            }
            killed_at = Some(snapshot);
        }
        if o.progress_secs > 0 && Instant::now() >= next_report {
            next_report += Duration::from_secs(o.progress_secs);
            let s = sh.lock().unwrap();
            let w = gw.world.stats();
            eprintln!(
                "world day {:.2} outings={} vaults={} queue={} copies={} in_world={} opened={} merges={} moved={} errors={}",
                clock.now() as f64 / (ticks as f64 / o.days),
                s.outings,
                s.vault_runs,
                gw.world.queue_len(),
                members.iter().filter(|m| !m.3).count(),
                gw.ticket_count(),
                w.copies_opened,
                w.merges_done,
                w.moved,
                s.errors.len()
            );
        }
    }
    rep.days = clock.now() as f64 / (24.0 * 3600.0 * realm_core::TICK_HZ as f64);
    stop.store(true, Ordering::Relaxed);
    let _ = pacer.join();
    for t in threads {
        let _ = t.join();
    }
    // Every outing has ended; nobody is left in the world.
    let end = Instant::now() + Duration::from_secs(10);
    while gw.ticket_count() > 0 && Instant::now() < end {
        std::thread::sleep(Duration::from_millis(50));
    }
    rep.stats = gw.world.stats();
    rep.counts = gw.world_counts();
    drop(listener);
    gw.shutdown();
    rep.secs = start.elapsed().as_secs_f64();
    rep.samples = samples.load(Ordering::Relaxed);
    let s = sh.lock().unwrap();
    rep.cycles = s.cycles;
    rep.outings = s.outings;
    rep.vault_runs = s.vault_runs;
    rep.vault_joins = s.vault_joins;
    rep.queued = s.queued;
    rep.moved_bots = s.moved_bots;
    rep.lost_outings = s.lost_outings;
    rep.errors = s.errors.clone();
    rep.heroes = s.heroes.len() as u64;
    for (&h, &a) in &s.heroes {
        let have = coin_of(&store, h, a);
        let said = s.reported.get(&h).copied().unwrap_or(0);
        if have != said {
            rep.coin_mismatches.push(format!("hero {h}: store {have}, reported {said}"));
        }
        if let Some(before) = killed_at.as_ref().and_then(|k| k.get(&h)) {
            if have < *before {
                rep.kill_losses += 1;
            }
        }
        rep.left_placed += (gw.where_is(h) != 0) as u64;
    }
    rep.left_placed += gw.ticket_count() as u64;
    match store.verify() {
        Ok(r) => {
            rep.store_rows = (r.items, r.stacks, r.ledger_rows);
            if !r.problems.is_empty() {
                rep.verify_error = Some(r.problems.join("; "));
            }
        }
        Err(e) => rep.verify_error = Some(e.to_string()),
    }
    drop(s);
    if o.db.is_none() {
        for ext in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{}{ext}", db.display()));
        }
    }
    Ok(rep)
}
