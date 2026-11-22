//! The world (job W2): the compressed week of bot play, and each part of it on its own: a player moved over the
//! wire when her copy closes, the queue, vaults and their keys, chests, the board, and heroes playing their own
//! class, level, job and gear in the field.

use realm_core::tables::{CLASSES, NOVICE, PRIEST, R_BOSS_CHEST, R_VAULT_CHEST, VAULTS};
use realm_gateway::bot::{play_field, PlayOpts};
use realm_gateway::client::GatewayClient;
use realm_gateway::gateway::{Config, Gateway};
use realm_gateway::proto::*;
use realm_gateway::world::copies::CopyRules;
use realm_gateway::world::week::{run_week, WeekOpts};
use realm_gateway::world::wire::{WReq, WResp};
use realm_gateway::world::WorldConfig;
use realm_server::client::LockstepClient;
use realm_server::host::{Credited, HostOpts, RewardBatch};
use realm_server::realm_clock::RealmClock;
use realm_server::sim::SimOpts;
use realm_store::*;
use std::net::UdpSocket;
use std::sync::Arc;
use std::time::{Duration, Instant};

struct Realm {
    gw: Arc<Gateway>,
    store: Arc<SqliteStore>,
    addr: String,
    _l: realm_gateway::conn::Listener,
    db: std::path::PathBuf,
}

impl Drop for Realm {
    fn drop(&mut self) {
        self.gw.shutdown();
        let _ = std::fs::remove_file(&self.db);
    }
}

fn realm(name: &str, world: WorldConfig, copies_of_field0: u32) -> Realm {
    let db = std::env::temp_dir().join(format!("realm-world-{}-{name}.db", std::process::id()));
    let _ = std::fs::remove_file(&db);
    let store = Arc::new(SqliteStore::open(&db).unwrap());
    let gw = Gateway::start(store.clone(), Config { dev_login: true, secret: 91, world, ..Config::default() });
    for _ in 0..copies_of_field0 {
        let sim = SimOpts { field: 0, seed: 3, monsters: 200, threads: 1, bots: 0, rally_permille: 0, level: 0, vault: None };
        gw.add_host(HostOpts { sim, port: 0, ..HostOpts::default() }).unwrap();
    }
    let l = realm_gateway::conn::listen(gw.clone(), "127.0.0.1:0").unwrap();
    Realm { gw, store, addr: l.addr.to_string(), _l: l, db }
}

fn quick(copies: CopyRules) -> WorldConfig {
    WorldConfig { copies, clock: Some(RealmClock::manual(100)), tick_us: 5_000, vault_tick_us: 1_000, dev_bots: true, monsters: 200, vault_monsters: 300, ..WorldConfig::default() }
}

fn login(r: &Realm, name: &str) -> GatewayClient {
    let mut c = GatewayClient::connect(&r.addr).unwrap();
    assert!(matches!(c.login(name).unwrap(), Resp::Login { .. }));
    c
}

fn hero(c: &mut GatewayClient, name: &str, class: u8) -> i64 {
    match c.call(Req::CreateHero { name: name.into(), race: 0, class, look: 1, self_found: false }).unwrap() {
        Resp::HeroCreated(id) => id,
        r => panic!("{r:?}"),
    }
}

fn level_up(r: &Realm, h: i64, level: u16) {
    let d = OutingDelta { xp: realm_gateway::sheet::xp_to_reach(level), levels: level - 1, waystone: Some((0, 0)), ..OutingDelta::default() };
    r.store.apply_outing(Meta::system(0x1E7E1 << 64 | h as u128, 1), h, d).unwrap();
}

/// What the waits below allow before calling it a stall. Each waits on something the hosts do in their own ticks
/// (a vault nobody entered closes after `VAULT_EMPTY_TICKS`, a closed copy's thread ends), which a loaded box runs
/// at a fraction of their pace: the bound is a hang guard, not a pace, and a passing wait returns at once.
const STALL_SECS: u64 = 120;

fn wait_until(secs: u64, mut ok: impl FnMut() -> bool) -> bool {
    let end = Instant::now() + Duration::from_secs(secs);
    while Instant::now() < end {
        if ok() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    ok()
}

fn coin(r: &Realm, h: i64) -> u64 {
    r.store.stacks(Owner::bag(h)).unwrap().iter().find(|s| s.0 == StackKind(1)).map_or(0, |s| s.1)
}

#[test]
fn a_compressed_week_of_bot_play_loses_and_doubles_nothing() {
    // Hosts at 250 Hz and a vault every sixth session of a leader keep the run near a minute and a half of CPU.
    let o = WeekOpts { bots: 32, secs: 30.0, realm_cap: 24, tick_us: 4_000, vault_every: 6, ..WeekOpts::default() };
    let r = run_week(&o).unwrap();
    for e in r.errors.iter().take(5) {
        eprintln!("{e}");
    }
    for m in r.coin_mismatches.iter().take(5) {
        eprintln!("{m}");
    }
    println!("{}", r.line());
    assert!(r.ok(), "{}", r.line());
    // A tide of five minutes passes in a few host ticks at this speed, and a host the box starves misses some.
    assert!(r.counts.tides as f64 >= 7.0 * 48.0 * 6.0 / 4.0, "a week of tides in the fields: {}", r.counts.tides);
    assert!(r.counts.bosses as f64 >= 7.0 * 12.0 * 6.0 / 4.0, "field bosses: {}", r.counts.bosses);
    // About 130 outings on an idle box; a loaded one (other builds on its cores) has done under 90.
    assert!(r.outings >= 60 && r.vault_runs >= 1, "outings {} vault runs {}", r.outings, r.vault_runs);
}

#[test]
fn a_player_in_a_closing_copy_is_moved_over_the_wire_with_her_haul() {
    let rules = CopyRules { cap: 50, open_at: 40, merge_under: 10, max_copies: 2, merge_grace_ms: 3_000 };
    let r = realm("move", quick(rules), 2);
    let mut a = login(&r, "drover");
    let ha = hero(&mut a, "Drover", 1);
    level_up(&r, ha, 12);
    let mut p = login(&r, "player");
    let hp = hero(&mut p, "Player", 1);
    level_up(&r, hp, 12);
    let mut b = login(&r, "drover2");
    let hb = hero(&mut b, "Drovertwo", 1);
    level_up(&r, hb, 12);
    // A host-played hero in copy 0, the player in copy 1 (the emptier), another in copy 0: copy 1 is the emptier
    // and closes into copy 0.
    assert!(matches!(a.call(Req::World(WReq::BotTicket { hero: ha, field: 0, ticks: 1_000_000 })).unwrap(), Resp::Ticket { copy: 0, .. }));
    let (host, port, ticket) = match p.call(Req::FieldTicket { hero: hp, field: 0 }).unwrap() {
        Resp::Ticket { host, port, ticket, copy: 1, .. } => (host, port, ticket),
        r => panic!("{r:?}"),
    };
    assert!(matches!(b.call(Req::World(WReq::BotTicket { hero: hb, field: 0, ticks: 1_000_000 })).unwrap(), Resp::Ticket { copy: 0, .. }));
    // She fights well past the merge (3 s of grace is 600 ticks here), then banks and leaves from the new copy.
    // The walk to a waystone is slow in host ticks when the box starves the bot (its inputs come every 50 ms).
    let play = PlayOpts { fight_ticks: 2_000, max_ticks: 24_000, ..PlayOpts::default() };
    let out = play_field(&mut p, &host, port, ticket, &play).unwrap_or_else(|e| panic!("{e}: {:?} {:?}", r.gw.host_loads(), r.gw.world.stats()));
    assert_eq!(out.moves, 1, "{out:?}");
    assert!(out.left == 0 || out.left == 1, "she left by the gate or a waystone after the move: {out:?}");
    assert_eq!(coin(&r, hp), out.coin, "what was reported banked is in her bag");
    let s = r.gw.world.stats();
    assert!(s.merges >= 1 && s.moved >= 1, "{s:?}");
    assert!(wait_until(STALL_SECS, || r.gw.host_loads().len() == 1), "the closed copy is gone: {:?}", r.gw.host_loads());
    let _ = a.call(Req::World(WReq::Recall { hero: ha }));
    let _ = b.call(Req::World(WReq::Recall { hero: hb }));
    assert!(wait_until(STALL_SECS, || r.gw.ticket_count() == 0));
}

#[test]
fn a_full_realm_queues_tells_places_and_lets_heroes_in_in_order() {
    let mut w = quick(CopyRules::default());
    w.realm_cap = 1;
    let r = realm("queue", w, 1);
    let mut cs: Vec<(GatewayClient, i64)> = (0..4)
        .map(|i| {
            let mut c = login(&r, &format!("q{i}"));
            let h = hero(&mut c, &format!("Queuer{i}"), 1);
            level_up(&r, h, 12);
            (c, h)
        })
        .collect();
    let first = cs[0].1;
    assert!(matches!(cs[0].0.call(Req::World(WReq::BotTicket { hero: first, field: 0, ticks: 1_000_000 })).unwrap(), Resp::Ticket { .. }));
    for (i, (c, h)) in cs.iter_mut().enumerate().skip(1) {
        match c.call(Req::World(WReq::BotTicket { hero: *h, field: 0, ticks: 1_000_000 })).unwrap() {
            Resp::World(WResp::Queued { place, of, .. }) => assert_eq!((place, of), (i as u32, i as u32)),
            r => panic!("{r:?}"),
        }
    }
    // Asking again while waiting is refused; leaving the queue moves the others up.
    let h2 = cs[2].1;
    assert!(matches!(cs[2].0.call(Req::FieldTicket { hero: h2, field: 0 }).unwrap(), Resp::Err { code: code::BUSY, .. }));
    let h1 = cs[1].1;
    assert_eq!(cs[1].0.call(Req::World(WReq::LeaveQueue { hero: h1 })).unwrap(), Resp::Ok);
    let place = cs[3].0.wait_push(Duration::from_secs(STALL_SECS), |r| match r {
        Resp::WorldPush(WResp::Queued { place, .. }) => Some(*place),
        _ => None,
    });
    assert_eq!(place.unwrap(), Some(2), "the last one moves up");
    // The first comes home: the head of the queue goes in with a pushed ticket.
    assert_eq!(cs[0].0.call(Req::World(WReq::Recall { hero: first })).unwrap(), Resp::Ok);
    let t = cs[2].0.wait_push(Duration::from_secs(STALL_SECS), |r| matches!(r, Resp::Ticket { .. }).then_some(()));
    assert_eq!(t.unwrap(), Some(()), "tickets {} first at {} h2 at {} queue {} {:?} {:?}", r.gw.ticket_count(), r.gw.where_is(first), r.gw.where_is(h2), r.gw.world.queue_len(), r.gw.host_loads(), r.gw.world.stats());
    assert_eq!(r.gw.where_is(h2), 2);
    // A waiter who disconnects is out of the queue.
    let h3 = cs[3].1;
    let (c3, _) = cs.pop().unwrap();
    drop(c3);
    assert!(wait_until(STALL_SECS, || r.gw.where_is(h3) == 0));
    assert_eq!(r.gw.world.queue_len(), 0);
    let s = r.gw.world.stats();
    assert_eq!((s.queued, s.admitted_from_queue), (3, 1));
}

#[test]
fn vaults_take_a_key_a_party_by_code_and_close_cleanly() {
    let mut w = quick(CopyRules::default());
    w.ticket_ttl = Duration::from_millis(300);
    let r = realm("vault", w, 1);
    let mut lead = login(&r, "leader");
    let hl = hero(&mut lead, "Leader", 1);
    level_up(&r, hl, 20);
    let key = StackKind::key(VAULTS[0].field as u32);
    // No key: refused, nothing opened.
    assert!(matches!(lead.call(Req::World(WReq::VaultOpen { hero: hl, vault: 0, seals: 2, drive_ticks: 0 })).unwrap(), Resp::Err { code: code::INSUFFICIENT, .. }));
    let grant = |n: u128| r.store.run(Meta::system(0x6E7 << 64 | n, 1), Cmd::StackCredit { to: Owner::bag(hl), kind: key, count: 1, minted: true, reason: "grant".into() }).unwrap();
    grant(1);
    // Opened and nobody comes (the ticket expires): the vault closes and the key comes back.
    match lead.call(Req::World(WReq::VaultOpen { hero: hl, vault: 0, seals: 2, drive_ticks: 0 })).unwrap() {
        Resp::World(WResp::Vault { vault: 0, seals: 2, .. }) => {}
        r => panic!("{r:?}"),
    }
    let keys = |r: &Realm| r.store.stacks(Owner::bag(hl)).unwrap().iter().find(|s| s.0 == key).map_or(0, |s| s.1);
    assert_eq!(keys(&r), 0);
    assert!(wait_until(STALL_SECS, || r.gw.world.stats().keys_refunded == 1), "{:?}", r.gw.world.stats());
    assert_eq!(keys(&r), 1);
    assert_eq!(r.gw.where_is(hl), 0, "she is free again");
    let unused = lead.wait_push(Duration::from_secs(STALL_SECS), |p| match p {
        Resp::Outing { left, .. } => Some(*left),
        _ => None,
    });
    assert_eq!(unused.unwrap(), Some(realm_gateway::gateway::LEFT_UNUSED), "her client is told the ticket went unused");
    // A party: the leader (played by the host) and a friend by the code; a stranger with a wrong code is refused.
    // The friend is made first: the leader's run starts as the vault opens and can end in a few hundred of its
    // ticks (a second at this pace), so nothing slow (a login, the store's writes) stands between the two.
    let mut fr = login(&r, "friend");
    let hf = hero(&mut fr, "Friend", 2);
    level_up(&r, hf, 20);
    let code = match lead.call(Req::World(WReq::VaultOpen { hero: hl, vault: 0, seals: 0, drive_ticks: 1 })).unwrap() {
        Resp::World(WResp::Vault { code, .. }) => code,
        r => panic!("{r:?}"),
    };
    assert!(matches!(fr.call(Req::World(WReq::VaultJoin { hero: hf, code: code ^ 2, drive_ticks: 1 })).unwrap(), Resp::Err { code: code::MISSING, .. }));
    match fr.call(Req::World(WReq::VaultJoin { hero: hf, code, drive_ticks: 1 })).unwrap() {
        Resp::World(WResp::Vault { .. }) => {}
        r => panic!("the friend's join by code: {r:?}"),
    }
    // The run ends (won or lost) and the vault banks them and closes: both pushed `left` 5.
    for (c, h) in [(&mut lead, hl), (&mut fr, hf)] {
        let left = c.wait_push(Duration::from_secs(STALL_SECS), |p| match p {
            Resp::Outing { hero, left, .. } if *hero == h && *left != 255 => Some(*left),
            _ => None,
        });
        assert_eq!(left.unwrap(), Some(5), "hero {h} left when her vault closed");
    }
    assert!(wait_until(STALL_SECS, || r.gw.world.stats().vaults_closed == 2));
    assert_eq!(r.gw.ticket_count(), 0);
    assert_eq!(r.gw.world.stats().keys_spent, 2);
    let v = r.store.verify().unwrap();
    assert!(v.problems.is_empty(), "{:?}", v.problems);
}

#[test]
fn a_reward_rolls_a_chest_for_each_hero_with_a_ticket() {
    let r = realm("chest", quick(CopyRules::default()), 1);
    let mut c = login(&r, "chester");
    let h = hero(&mut c, "Chester", 3);
    level_up(&r, h, 30);
    let ticket = match c.call(Req::World(WReq::BotTicket { hero: h, field: 0, ticks: 1_000_000 })).unwrap() {
        Resp::Ticket { ticket, .. } => ticket,
        r => panic!("{r:?}"),
    };
    let items = |r: &Realm| r.store.items_at(PlaceKind::Bag, h).unwrap().len();
    let before = items(&r);
    let cr = Credited { hero: h as u64, ticket, slot: 0, luck: 0 };
    let batch = |kind: u8, index: u32| RewardBatch { host: 1, field_seed: 5, tick: 900, index, kind, source: 0, level: 10, seals: 3, boss: 0, vault: 0, heroes: vec![(cr, 5_000)] };
    r.gw.on_reward(batch(R_BOSS_CHEST, 1));
    let after_boss = items(&r);
    assert!(after_boss >= before + 2, "a boss chest holds two item rolls from RARE: {before} -> {after_boss}");
    r.gw.on_reward(batch(R_VAULT_CHEST, 2));
    assert!(items(&r) >= after_boss + 2 * 3, "a vault chest of three seals is three rounds: {after_boss} -> {}", items(&r));
    // No ticket, no chest.
    let mut stranger = batch(R_BOSS_CHEST, 3);
    stranger.heroes[0].0.ticket ^= 1;
    let n = items(&r);
    r.gw.on_reward(stranger);
    assert_eq!(items(&r), n);
    assert_eq!(r.gw.world.stats().chests, 2);
    let _ = c.call(Req::World(WReq::Recall { hero: h }));
}

#[test]
fn the_board_counts_down_every_field_and_the_world_boss() {
    let r = realm("board", quick(CopyRules::default()), 1);
    let mut c = login(&r, "reader");
    match c.call(Req::World(WReq::Board)).unwrap() {
        Resp::World(WResp::Board { clock, fields, world_field, world_in, copies, .. }) => {
            assert!((100..200).contains(&clock));
            assert_eq!(fields.len(), 6);
            for f in &fields {
                assert_eq!(f.tide_in as u64, realm_core::tide_start(f.field, 0) - clock);
            }
            assert_eq!(world_field, 0);
            assert_eq!(world_in as u64, realm_core::world_ride(0).1 - clock);
            assert_eq!(copies, vec![(0, 0, 0)]);
        }
        r => panic!("{r:?}"),
    }
}

/// A hero in the field is her saved self: class, class level, job and gear come from her sheet (THE TOWER, top
/// level 50, so her 45 is under the field's ceiling of top + 2). Below class level 10 every class plays as a
/// NOVICE (rules section 3, the core's rule: the class comes with level 10).
#[test]
fn heroes_play_their_own_class_level_job_and_gear() {
    let r = realm("sheet", quick(CopyRules::default()), 0);
    let sim = SimOpts { field: 4, seed: 3, monsters: 200, threads: 1, bots: 0, rally_permille: 0, level: 0, vault: None };
    r.gw.add_host(HostOpts { sim, port: 0, ..HostOpts::default() }).unwrap();
    let mut c = login(&r, "priestess");
    let h = hero(&mut c, "Priestess", PRIEST);
    level_up(&r, h, 45);
    let job = CLASSES[PRIEST as usize].jobs[1];
    assert_eq!(c.call(Req::ChooseJob { hero: h, job }).unwrap(), Resp::Ok);
    let spec = ItemSpec { base: 1, gear_slot: 2, item_level: 40, rarity: 2, lines: vec![(3, 9), (1, 4)], sockets: 0, plus: 0, bound: false };
    let item = match r.store.run(Meta::system(0x17E << 64, 1), Cmd::Mint { to: Dest::bag(h), spec, reason: "grant".into() }).unwrap() {
        Reply::Item(id, _) => id,
        r => panic!("{r:?}"),
    };
    assert_eq!(c.call(Req::Equip { hero: h, item }).unwrap(), Resp::Ok);
    let mut n = login(&r, "newcomer");
    let hn = hero(&mut n, "Newcomer", PRIEST);
    for (cl, id, want_class, want_level) in [(&mut c, h, PRIEST, 45u8), (&mut n, hn, NOVICE, 1u8)] {
        let (port, ticket) = match cl.call(Req::FieldTicket { hero: id, field: 4 }).unwrap() {
            Resp::Ticket { port, ticket, .. } => (port, ticket),
            r => panic!("{r:?}"),
        };
        let sock = UdpSocket::bind("127.0.0.1:0").unwrap();
        sock.connect(("127.0.0.1", port)).unwrap();
        sock.set_nonblocking(true).unwrap();
        let mut lc = LockstepClient::with_ticket(ticket, 1);
        let mut buf = [0u8; 2048];
        let end = Instant::now() + Duration::from_secs(STALL_SECS);
        let mut seen = None;
        while Instant::now() < end && seen.is_none() {
            if !lc.welcomed() {
                let _ = sock.send(&lc.hello());
            }
            while let Ok(k) = sock.recv(&mut buf) {
                lc.receive(&buf[..k]);
            }
            lc.apply();
            if lc.welcomed() {
                let _ = sock.send(&lc.input_word(0));
            }
            if let Some(p) = lc.hero_player() {
                assert_eq!(p.sheet.class_level as u8, want_level.max(1));
                seen = Some((p.class, p.class_level, p.job, p.sheet.gear));
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        let (class, level, j, gear) = seen.expect("she is in the field");
        assert_eq!((class, level), (want_class, want_level), "hero {id}");
        if want_class == PRIEST {
            assert_eq!(j, job, "her job");
            assert_eq!((gear[3], gear[1]), (9, 4), "her gear's lines");
        }
        let _ = sock.send(&[realm_server::MSG_BYE]);
    }
}
