//! Bots through the whole stack: a bot's life is a cycle of login, hero, town, field, bank, spend and logout, and
//! the soak runs many of them against a gateway and its field hosts, then checks the store.

use crate::bot::{play_field, Outcome, PlayOpts};
use crate::client::GatewayClient;
use crate::gateway::{Config, Gateway};
use crate::proto::*;
use realm_core::tables::{FIELDS, STAT_NAMES};
use realm_server::host::HostOpts;
use realm_server::sim::SimOpts;
use realm_store::{SqliteStore, Store};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// What a bot's cycles added up to.
#[derive(Clone, Debug, Default)]
pub struct BotStats {
    pub cycles: u64,
    pub heroes_made: u64,
    pub outings: u64,
    pub banked_outings: u64,
    pub coin: u64,
    pub xp: u64,
    pub levels: u64,
    pub potions: u64,
    pub deposits: u64,
    pub points_spent: u64,
    pub town_snapshots: u64,
    pub chats_heard: u64,
    pub left_by_gate: u64,
    pub left_by_waystone: u64,
    pub timeouts: u64,
    /// After an outing the store did not hold exactly what the gateway reported (coin, xp, level).
    pub mismatches: u64,
    pub errors: Vec<String>,
}

impl BotStats {
    pub fn add(&mut self, o: &BotStats) {
        self.cycles += o.cycles;
        self.heroes_made += o.heroes_made;
        self.outings += o.outings;
        self.banked_outings += o.banked_outings;
        self.coin += o.coin;
        self.xp += o.xp;
        self.levels += o.levels;
        self.potions += o.potions;
        self.deposits += o.deposits;
        self.points_spent += o.points_spent;
        self.town_snapshots += o.town_snapshots;
        self.chats_heard += o.chats_heard;
        self.left_by_gate += o.left_by_gate;
        self.left_by_waystone += o.left_by_waystone;
        self.timeouts += o.timeouts;
        self.mismatches += o.mismatches;
        self.errors.extend(o.errors.iter().cloned());
    }
}

fn io(e: std::io::Error) -> String {
    e.to_string()
}

fn expect_ok(r: Resp, what: &str) -> Result<(), String> {
    match r {
        Resp::Ok => Ok(()),
        r => Err(format!("{what}: {r:?}")),
    }
}

/// One bot's hero name: letters and digits, starting with a letter, at most 16.
pub fn bot_hero_name(bot: u64) -> String {
    format!("Soak{}", bot)
}

/// What runs on a hero before she first goes out (the fast soak and the tests use it to start heroes at a
/// waystone and at a level).
pub type Prep = dyn Fn(&HeroInfo) + Send + Sync;

/// One cycle of a bot's life against a gateway. The hero persists between cycles (the bot logs out and back in).
pub fn cycle(addr: &str, bot: u64, field: u8, play: &PlayOpts, prep: &Prep, stats: &mut BotStats) -> Result<(), String> {
    let mut gw = GatewayClient::connect(addr).map_err(io)?;
    match gw.login(&format!("soak-bot-{bot}")).map_err(io)? {
        Resp::Login { .. } => {}
        r => return Err(format!("login: {r:?}")),
    }
    let mut heroes = gw.heroes().map_err(io)?;
    if heroes.is_empty() {
        let class = 1 + (bot % 5) as u8;
        match gw.call(Req::CreateHero { name: bot_hero_name(bot), race: (bot % 4) as u8, class, look: bot as u32, self_found: false }).map_err(io)? {
            Resp::HeroCreated(_) => stats.heroes_made += 1,
            r => return Err(format!("create hero: {r:?}")),
        }
        heroes = gw.heroes().map_err(io)?;
    }
    let hero = heroes.iter().find(|h| !h.deleted).ok_or("no hero")?.clone();
    prep(&hero);
    // The town: walk a little, say something, hear the room.
    match gw.call(Req::EnterTown { hero: hero.id }).map_err(io)? {
        Resp::Town { .. } => {}
        r => return Err(format!("enter town: {r:?}")),
    }
    expect_ok(gw.call(Req::TownInput { dir: 3 }).map_err(io)?, "town input")?;
    expect_ok(gw.call(Req::Chat { text: format!("{} is here", hero.name) }).map_err(io)?, "chat")?;
    let end = Instant::now() + Duration::from_millis(700);
    while Instant::now() < end {
        gw.poll(Duration::from_millis(100)).map_err(io)?;
    }
    for r in gw.pushes.drain(..) {
        match r {
            Resp::Snapshot(_) => stats.town_snapshots += 1,
            Resp::Chat { .. } => stats.chats_heard += 1,
            _ => {}
        }
    }
    expect_ok(gw.call(Req::LeaveTown).map_err(io)?, "leave town")?;
    // What the store holds before she goes out.
    let before = gw.inventory(hero.id).map_err(io)?;
    let info_before = gw.heroes().map_err(io)?.into_iter().find(|h| h.id == hero.id).ok_or("hero vanished")?;
    // A ticket (the previous outing's result may still be being applied: wait for the hero to be free).
    let mut ticket = None;
    for _ in 0..100 {
        match gw.call(Req::FieldTicket { hero: hero.id, field }).map_err(io)? {
            Resp::Ticket { host, port, ticket: t, .. } => {
                ticket = Some((host, port, t));
                break;
            }
            Resp::Err { code: code::BUSY, .. } => std::thread::sleep(Duration::from_millis(200)),
            r => return Err(format!("field ticket: {r:?}")),
        }
    }
    let (host, port, t) = ticket.ok_or("the hero stayed busy")?;
    let out: Outcome = play_field(&mut gw, &host, port, t, play)?;
    stats.outings += 1;
    stats.coin += out.coin;
    stats.xp += out.xp;
    stats.levels += out.levels as u64;
    stats.potions += out.potions as u64;
    if out.banked {
        stats.banked_outings += 1;
    }
    match out.left {
        0 => stats.left_by_gate += 1,
        1 => stats.left_by_waystone += 1,
        255 => stats.timeouts += 1,
        _ => {}
    }
    // Home again: the store holds exactly what was reported.
    let after = gw.inventory(hero.id).map_err(io)?;
    let info_after = gw.heroes().map_err(io)?.into_iter().find(|h| h.id == hero.id).ok_or("hero vanished")?;
    let coin = |i: &Inventory| i.stack(1, 1);
    if out.left != 255 {
        let drank: u64 = out.potions as u64;
        let potions_before: u64 = before.stacks.iter().filter(|s| s.0 == 1 && (100..106).contains(&s.1)).map(|s| s.2).sum();
        let potions_after: u64 = after.stacks.iter().filter(|s| s.0 == 1 && (100..106).contains(&s.1)).map(|s| s.2).sum();
        let ok = coin(&after) == coin(&before) + out.coin
            && info_after.class_xp == info_before.class_xp + out.xp
            && info_after.class_level == info_before.class_level + out.levels
            && potions_after + drank == potions_before;
        if !ok {
            stats.mismatches += 1;
            stats.errors.push(format!(
                "hero {} coin {}+{} -> {}, xp {}+{} -> {}, level {}+{} -> {}, potions {}-{} -> {}",
                hero.id,
                coin(&before),
                out.coin,
                coin(&after),
                info_before.class_xp,
                out.xp,
                info_after.class_xp,
                info_before.class_level,
                out.levels,
                info_after.class_level,
                potions_before,
                drank,
                potions_after
            ));
        }
    }
    // Bank the coin she carries in her bag, and spend what she earned.
    let bag_coin = coin(&after);
    if bag_coin > 0 {
        expect_ok(gw.call(Req::BankDeposit { hero: hero.id, what: Thing::Stack(1, bag_coin), tab: 0 }).map_err(io)?, "bank deposit")?;
        stats.deposits += 1;
        let inv = gw.inventory(hero.id).map_err(io)?;
        if inv.stack(1, 1) != 0 || inv.stack(3, 1) < bag_coin {
            stats.mismatches += 1;
            stats.errors.push(format!("hero {}: deposit of {bag_coin} left bag {} bank {}", hero.id, inv.stack(1, 1), inv.stack(3, 1)));
        }
    }
    if info_after.unspent > 0 {
        let stat = (bot % 6) as u8;
        expect_ok(gw.call(Req::SpendPoint { hero: hero.id, stat, n: info_after.unspent }).map_err(io)?, &format!("spend on {}", STAT_NAMES[stat as usize]))?;
        stats.points_spent += info_after.unspent as u64;
    }
    stats.cycles += 1;
    Ok(())
}

/// What a soak runs on.
#[derive(Clone, Debug)]
pub struct SoakOpts {
    pub bots: u32,
    pub secs: u64,
    pub fields: Vec<u8>,
    pub monsters: u32,
    pub threads: usize,
    pub db: Option<PathBuf>,
    pub seed: u64,
    pub play: PlayOpts,
    /// Report to stderr every this many seconds (0: never).
    pub progress_secs: u64,
    /// Start every new hero at class level 12 and at waystone 0 of every field, so a short run sees fights and banks.
    pub fast: bool,
}

impl Default for SoakOpts {
    fn default() -> Self {
        SoakOpts { bots: 8, secs: 60, fields: vec![0], monsters: 1500, threads: 1, db: None, seed: 1, play: PlayOpts::default(), progress_secs: 0, fast: false }
    }
}

pub struct SoakReport {
    pub stats: BotStats,
    pub verify: Result<(i64, i64, i64), String>,
    pub secs: f64,
    pub peak_in_fields: u32,
    pub db: PathBuf,
}

impl SoakReport {
    pub fn ok(&self) -> bool {
        self.stats.mismatches == 0 && self.stats.errors.is_empty() && self.verify.is_ok() && self.stats.outings > 0
    }

    /// The one summary line.
    pub fn line(&self) -> String {
        let s = &self.stats;
        let (items, stacks, ledger) = self.verify.as_ref().map_or((0, 0, 0), |v| *v);
        format!(
            "SOAK {} secs={:.0} cycles={} heroes={} outings={} banked={} left_gate={} left_waystone={} timeouts={} coin={} xp={} levels={} potions={} deposits={} points={} snapshots={} chats={} mismatches={} errors={} peak_in_fields={} verify={} items={items} stacks={stacks} ledger_rows={ledger}",
            if self.ok() { "ok" } else { "FAILED" },
            self.secs,
            s.cycles,
            s.heroes_made,
            s.outings,
            s.banked_outings,
            s.left_by_gate,
            s.left_by_waystone,
            s.timeouts,
            s.coin,
            s.xp,
            s.levels,
            s.potions,
            s.deposits,
            s.points_spent,
            s.town_snapshots,
            s.chats_heard,
            s.mismatches,
            s.errors.len(),
            self.peak_in_fields,
            if self.verify.is_ok() { "ok".to_string() } else { format!("{:?}", self.verify) },
        )
    }
}

/// Runs a gateway and a field host for each of `fields` on a store, lets `bots` bots live there for `secs`, shuts
/// everything down in order (every hero banked) and verifies the store.
pub fn run_soak(o: &SoakOpts) -> Result<SoakReport, String> {
    let db = o.db.clone().unwrap_or_else(|| std::env::temp_dir().join(format!("realm-soak-{}-{}.db", std::process::id(), o.seed)));
    let _ = std::fs::remove_file(&db);
    let store = Arc::new(SqliteStore::open(&db).map_err(|e| e.to_string())?);
    let gw = Gateway::start(store.clone(), Config { dev_login: true, secret: o.seed ^ 0x5EC2_E7C0_FFEE, ..Config::default() });
    for (i, &f) in o.fields.iter().enumerate() {
        let sim = SimOpts { field: f.min(FIELDS.len() as u8 - 1), seed: o.seed + i as u64, monsters: o.monsters, threads: o.threads, bots: 0, rally_permille: 0, level: 0 };
        gw.add_host(HostOpts { sim, port: 0, ..HostOpts::default() }).map_err(|e| e.to_string())?;
    }
    let listener = crate::conn::listen(gw.clone(), "127.0.0.1:0").map_err(|e| e.to_string())?;
    let addr = listener.addr.to_string();
    let stop = Arc::new(AtomicBool::new(false));
    let prep: Arc<Box<Prep>> = Arc::new(if o.fast { Box::new(fast_prep(store.clone())) } else { Box::new(|_: &HeroInfo| {}) });
    let total = Arc::new(Mutex::new(BotStats::default()));
    let cycles = Arc::new(AtomicU64::new(0));
    let start = Instant::now();
    let mut threads = Vec::new();
    for b in 0..o.bots as u64 {
        let (addr, stop, total, cycles, fields, play, prep) = (addr.clone(), stop.clone(), total.clone(), cycles.clone(), o.fields.clone(), o.play.clone(), prep.clone());
        let seed = o.seed;
        threads.push(std::thread::spawn(move || {
            let mut n = 0u64;
            while !stop.load(Ordering::Relaxed) {
                let field = fields[((b + n) as usize) % fields.len()];
                let mut st = BotStats::default();
                let mut p = play.clone();
                p.seed = seed ^ (b << 20) ^ n;
                p.stop = Some(stop.clone());
                if let Err(e) = cycle(&addr, b, field, &p, &**prep, &mut st) {
                    st.errors.push(format!("bot {b}: {e}"));
                    if !stop.load(Ordering::Relaxed) {
                        std::thread::sleep(Duration::from_millis(500));
                    }
                }
                n += 1;
                cycles.fetch_add(1, Ordering::Relaxed);
                total.lock().unwrap().add(&st);
            }
        }));
    }
    let mut peak = 0;
    let mut next_report = start + Duration::from_secs(o.progress_secs.max(1));
    while start.elapsed() < Duration::from_secs(o.secs) {
        std::thread::sleep(Duration::from_millis(250));
        peak = peak.max(gw.host_loads().iter().map(|l| l.2).sum());
        if o.progress_secs > 0 && Instant::now() >= next_report {
            next_report += Duration::from_secs(o.progress_secs);
            let t = total.lock().unwrap();
            eprintln!(
                "soak {:>6.0}s cycles={} outings={} coin={} xp={} in_fields={} town={} mismatches={} errors={}",
                start.elapsed().as_secs_f64(),
                t.cycles,
                t.outings,
                t.coin,
                t.xp,
                gw.host_loads().iter().map(|l| l.2).sum::<u32>(),
                gw.towns.population(),
                t.mismatches,
                t.errors.len()
            );
        }
    }
    stop.store(true, Ordering::Relaxed);
    // Bots in a field finish their outing (they leave by waystone, or time out), then the world stops.
    for t in threads {
        let _ = t.join();
    }
    drop(listener);
    gw.shutdown();
    let stats = total.lock().unwrap().clone();
    let verify = store.verify().map_err(|e| e.to_string()).and_then(|r| {
        if r.problems.is_empty() { Ok((r.items, r.stacks, r.ledger_rows)) } else { Err(r.problems.join("; ")) }
    });
    Ok(SoakReport { stats, verify, secs: start.elapsed().as_secs_f64(), peak_in_fields: peak, db })
}

/// `Prep` for a fast run: a hero with no class XP yet is given the XP of class level 12 (a KNIGHT-like fighter
/// kills a scarecrow in a second) and her waystone 0 in every field, so she appears at a waystone and banks
/// there. This is the server acting on the store, as an operator's grant would.
pub fn fast_prep(store: Arc<SqliteStore>) -> impl Fn(&HeroInfo) + Send + Sync {
    use realm_store::{Meta, OutingDelta};
    move |h: &HeroInfo| {
        if h.class_xp > 0 || h.class_level > 1 {
            return;
        }
        let xp = crate::sheet::xp_to_reach(12);
        for f in 0..FIELDS.len() as u8 {
            let d = OutingDelta { xp: if f == 0 { xp } else { 0 }, levels: if f == 0 { 11 } else { 0 }, waystone: Some((f, 0)), ..OutingDelta::default() };
            let id = (0xFA57u128 << 96) | ((h.id as u128) << 8) | f as u128;
            let _ = store.apply_outing(Meta::system(id, crate::gateway::now_ms()), h.id, d);
        }
    }
}
