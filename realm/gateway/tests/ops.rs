//! Running it (job O1) through real sockets: the kill switches thrown from the admin console and felt by the
//! gateway (login, trade, market, a field kind), the flood limits at the socket, and the numbers the metrics
//! endpoint reports. The switches and limits are process-wide, so the tests take turns.

use realm_gateway::client::GatewayClient;
use realm_gateway::economy::wire::EReq;
use realm_gateway::gateway::{Config, Gateway};
use realm_gateway::proto::*;
use realm_gateway::social::admin::Console;
use realm_ops::{flood, metrics, runtime, switches};
use realm_server::host::HostOpts;
use realm_server::sim::SimOpts;
use realm_store::*;
use std::sync::{Arc, Mutex};
use std::time::Duration;

static TURN: Mutex<()> = Mutex::new(());

struct World {
    gw: Arc<Gateway>,
    store: Arc<SqliteStore>,
    addr: String,
    _l: realm_gateway::conn::Listener,
    db: std::path::PathBuf,
}

impl Drop for World {
    fn drop(&mut self) {
        switches::reset();
        flood::configure(flood::Limits::default());
        self.gw.shutdown();
        for s in ["", ".social", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{}{s}", self.db.display()));
        }
    }
}

fn world(name: &str) -> World {
    let db = std::env::temp_dir().join(format!("realm-ops-gw-{}-{name}.db", std::process::id()));
    for s in ["", ".social", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{s}", db.display()));
    }
    let store = Arc::new(SqliteStore::open(&db).unwrap());
    let gw = Gateway::start(store.clone(), Config { dev_login: true, secret: 5, ..Config::default() });
    gw.add_host(HostOpts { sim: SimOpts { field: 0, seed: 3, monsters: 50, threads: 1, bots: 0, rally_permille: 0, level: 0, vault: None }, port: 0, ..HostOpts::default() }).unwrap();
    let l = realm_gateway::conn::listen(gw.clone(), "127.0.0.1:0").unwrap();
    World { gw, store, addr: l.addr.to_string(), _l: l, db }
}

fn console(w: &World, line: &str) -> String {
    let social = realm_gateway::social::Social::default();
    Console { store: &w.store, social: &social, live: None, op: "test".into() }.run(line)
}

fn err_code(r: &Resp) -> Option<u16> {
    if let Resp::Err { code, .. } = r { Some(*code) } else { None }
}

#[test]
fn kill_switches_close_login_freeze_trade_and_market_and_stop_a_field() {
    let _t = TURN.lock().unwrap_or_else(|e| e.into_inner());
    let w = world("kill");
    let mut ann = GatewayClient::connect_plain(&w.addr).unwrap();
    assert!(matches!(ann.login("ann").unwrap(), Resp::Login { .. }));
    let Resp::HeroCreated(hero) = ann.call(Req::CreateHero { name: "Annie".into(), race: 1, class: 1, look: 0, self_found: false }).unwrap() else { panic!() };

    // Login: closed for new logins, not for the one already in; reopened by revive.
    assert!(console(&w, "kill login").contains("login killed"));
    let mut bob = GatewayClient::connect_plain(&w.addr).unwrap();
    assert_eq!(err_code(&bob.login("bob").unwrap()), Some(code::DISABLED));
    assert!(matches!(ann.call(Req::ListHeroes).unwrap(), Resp::Heroes(_)), "a logged-in player is not thrown out");
    assert!(console(&w, "switches").contains("login closed"));
    assert!(console(&w, "revive login").contains("login revived"));
    assert!(matches!(bob.login("bob").unwrap(), Resp::Login { .. }));

    // Trade and market: frozen separately.
    let trade = |c: &mut GatewayClient| c.call(Req::Econ(EReq::TradeInvite { hero, with_name: "Nobody".into() })).unwrap();
    let market = |c: &mut GatewayClient| c.call(Req::Econ(EReq::MarketBuy { hero, listing: 1 })).unwrap();
    console(&w, "kill trade");
    assert_eq!(err_code(&trade(&mut ann)), Some(code::DISABLED));
    assert_ne!(err_code(&market(&mut ann)), Some(code::DISABLED), "market still open");
    console(&w, "revive trade");
    console(&w, "kill market");
    assert_eq!(err_code(&market(&mut ann)), Some(code::DISABLED));
    assert_ne!(err_code(&trade(&mut ann)), Some(code::DISABLED), "trade still open");
    console(&w, "revive market");

    // A field kind: no new tickets; the other kinds and a revive are untouched.
    console(&w, "kill field 0");
    assert_eq!(err_code(&ann.call(Req::FieldTicket { hero, field: 0 }).unwrap()), Some(code::NO_FIELD));
    console(&w, "revive field 0");
    assert!(matches!(ann.call(Req::FieldTicket { hero, field: 0 }).unwrap(), Resp::Ticket { .. }));
    assert!(console(&w, "kill nonsense").starts_with("error:"));
    assert!(console(&w, "help").contains("kill WHAT"));
}

#[test]
fn flood_limits_close_the_socket_on_too_many_connections_and_too_many_requests() {
    let _t = TURN.lock().unwrap_or_else(|e| e.into_inner());
    let w = world("flood");
    flood::configure(flood::Limits { conn_per_ip: 3, conn_rate: 100, pkt_rate: 20, udp_rate: 0, window_ms: 1000, ban_ms: 600, exempt: vec![] });
    let refused0 = metrics::REG.conn_refused.load(std::sync::atomic::Ordering::Relaxed);
    let mut held: Vec<GatewayClient> = (0..3).map(|_| GatewayClient::connect_plain(&w.addr).unwrap()).collect();
    for c in &mut held {
        assert!(matches!(c.call(Req::Ping).unwrap(), Resp::Pong));
    }
    // The fourth is accepted by the OS and closed at once: its first call fails.
    let mut fourth = GatewayClient::connect_plain(&w.addr).unwrap();
    assert!(fourth.call(Req::Ping).is_err(), "a fourth connection from one address is closed");
    assert!(metrics::REG.conn_refused.load(std::sync::atomic::Ordering::Relaxed) > refused0);
    // The address is now banned for 600 ms: even after the others leave, it is refused...
    drop(held);
    let mut again = GatewayClient::connect_plain(&w.addr).unwrap();
    assert!(again.call(Req::Ping).is_err(), "inside the ban");
    // ...and then admitted again; a request flood closes the connection and bans again.
    std::thread::sleep(Duration::from_millis(900));
    let mut c = GatewayClient::connect_plain(&w.addr).unwrap();
    assert!(matches!(c.call(Req::Ping).unwrap(), Resp::Pong));
    let dropped0 = metrics::REG.frames_dropped.load(std::sync::atomic::Ordering::Relaxed);
    let mut closed = false;
    for _ in 0..200 {
        if c.call(Req::Ping).is_err() {
            closed = true;
            break;
        }
    }
    assert!(closed, "200 requests in a window of 20 end the connection");
    assert!(metrics::REG.frames_dropped.load(std::sync::atomic::Ordering::Relaxed) > dropped0);
    // Limits off again: the realm is open as before.
    flood::configure(flood::Limits::default());
    std::thread::sleep(Duration::from_millis(50));
    let mut d = GatewayClient::connect_plain(&w.addr).unwrap();
    assert!(matches!(d.call(Req::Ping).unwrap(), Resp::Pong));
}

#[test]
fn the_metrics_endpoint_reports_players_fields_ticks_and_store_writes() {
    let _t = TURN.lock().unwrap_or_else(|e| e.into_inner());
    let w = world("metrics");
    let mut ann = GatewayClient::connect_plain(&w.addr).unwrap();
    assert!(matches!(ann.login("ann").unwrap(), Resp::Login { .. }));
    let Resp::HeroCreated(_) = ann.call(Req::CreateHero { name: "Annie".into(), race: 1, class: 1, look: 0, self_found: false }).unwrap() else { panic!() };
    std::thread::sleep(Duration::from_millis(600));
    let g = w.gw.clone();
    let addr = runtime::serve_on(0, Arc::new(move || {
        let fields = g.host_loads();
        metrics::Probe { players: fields.iter().map(|f| f.2 as u64).sum(), fields }
    }))
    .unwrap();
    let m = runtime::fetch(addr, "/metrics").unwrap();
    for want in ["realm_players ", "realm_tick_ms{field=\"0\",q=\"p50\"}", "realm_tick_ms{field=\"0\",q=\"p99\"}", "realm_store_write_ms{q=\"p99\"}", "realm_queue ", "realm_store_errors_total ", "realm_field_heroes{field=\"0\",copy=\"0\"}"] {
        assert!(m.contains(want), "{want} in\n{m}");
    }
    let writes: u64 = m.lines().find_map(|l| l.strip_prefix("realm_store_writes_total ")).unwrap().parse().unwrap();
    assert!(writes >= 1, "the hero's creation went through the timed store path");
    let p99: f64 = m.lines().find_map(|l| l.strip_prefix("realm_tick_ms{field=\"0\",q=\"p99\"} ")).unwrap().parse().unwrap();
    assert!(p99 > 0.0 && p99 < 50.0, "a 50 monster field ticks well inside its budget: {p99}");
    let page = runtime::fetch(addr, "/status").unwrap();
    assert!(page.contains("HORDE & HEARTH realm status") && page.contains("field 0 copy 0"), "{page}");
    assert_eq!(runtime::fetch(addr, "/health").unwrap().trim(), "ok");
}

#[test]
fn a_gateway_started_with_an_ops_conf_logs_serves_metrics_and_keeps_switches_across_a_restart() {
    use std::io::{BufRead, BufReader};
    let _t = TURN.lock().unwrap_or_else(|e| e.into_inner());
    let dir = std::env::temp_dir().join(format!("realm-ops-conf-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
    let mut conf = realm_ops::config::template();
    conf.push_str(&format!("\nmetrics_port = {port}\nlog_dir = {0}/logs\ndb = {0}/realm.db\nbackup_dir = {0}/backups\nadmin_port = 0\n", dir.display()));
    std::fs::write(dir.join("ops.conf"), conf).unwrap();
    // A switch thrown while the realm was down (the offline console writes the file the realm reads at start).
    std::fs::write(dir.join("realm.db.switches"), "trade\n").unwrap();
    let spawn = || {
        let mut child = std::process::Command::new(env!("CARGO_BIN_EXE_realm-gateway"))
            .args([&format!("--db={}/realm.db", dir.display()), "--dev-login", "--bind=127.0.0.1", "--port=0", "--field-port=0", "--fields=0", "--monsters=200", &format!("--ops-conf={}/ops.conf", dir.display())])
            .stdout(std::process::Stdio::piped())
            .spawn()
            .unwrap();
        let mut out = BufReader::new(child.stdout.take().unwrap());
        let mut line = String::new();
        let mut ops_line = String::new();
        while !line.starts_with("LISTEN") {
            line.clear();
            out.read_line(&mut line).unwrap();
            if line.starts_with("OPS ") {
                ops_line = line.clone();
            }
        }
        (child, ops_line)
    };
    let (mut child, ops_line) = spawn();
    assert!(ops_line.contains(&format!("127.0.0.1:{port}")), "{ops_line}");
    std::thread::sleep(Duration::from_millis(500));
    let addr: std::net::SocketAddr = format!("127.0.0.1:{port}").parse().unwrap();
    let status = runtime::fetch(addr, "/status").unwrap();
    assert!(status.contains("trade frozen"), "the switch came back with the process: {status}");
    // The first tick time shows once field 0 has ticked; on a station whose cores are shared that can take seconds.
    let until = std::time::Instant::now() + Duration::from_secs(20);
    let mut metrics = runtime::fetch(addr, "/metrics").unwrap();
    while !metrics.contains("realm_tick_ms{field=\"0\"") && std::time::Instant::now() < until {
        std::thread::sleep(Duration::from_millis(100));
        metrics = runtime::fetch(addr, "/metrics").unwrap();
    }
    assert!(metrics.contains("realm_tick_ms{field=\"0\""), "no field 0 tick time after 20 s: {metrics}");
    let _ = child.kill();
    let _ = child.wait();
    let log = std::fs::read_to_string(dir.join("logs/realm.log")).unwrap();
    assert!(log.contains("INFO realm_start") && log.contains("WARN switches_restored"), "{log}");
    let _ = std::fs::remove_dir_all(&dir);
}

/// A disaster restore brings back the houses and the realm clock: a plot bought in the gateway's own registry and the
/// epoch the clock wrote are copied with the backup, and after the disk is lost the restore puts both back, so
/// the owner still owns her house and the tides have not moved.
#[test]
fn a_backup_and_restore_keep_the_plot_registry_and_the_clock_epoch() {
    use realm_gateway::homes::plots::Registry;
    use realm_ops::sides::{side, EPOCH, HOMES};
    let dir = std::env::temp_dir().join(format!("realm-ops-gw-sides-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.join("data")).unwrap();
    let db = dir.join("data/realm.db");
    SqliteStore::open(&db).unwrap().close();
    let now = 1_700_000_000_000i64;
    {
        let mut reg = Registry::open(&side(&db, HOMES)).unwrap();
        reg.buy(0, 42, "Annie", now).unwrap();
    }
    // An epoch a day old, as the realm wrote it on its first start; the clock reads it.
    let day_ago = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as u64 - 86_400_000;
    std::fs::write(side(&db, EPOCH), format!("{day_ago}\n")).unwrap();
    let before = realm_server::realm_clock::clock_from_epoch(&side(&db, EPOCH), 1).now();
    let made = realm_ops::backup::backup_now(&db, &dir.join("backups"), 3, 0, now).unwrap();
    // The disk is lost.
    for s in ["", "-wal", "-shm", ".homes", ".epoch"] {
        let _ = std::fs::remove_file(format!("{}{s}", db.display()));
    }
    assert!(realm_ops::backup::restore(&made.file, &db, now + 1000).unwrap().notes.is_empty());
    assert_eq!(Registry::open(&side(&db, HOMES)).unwrap().plot_of(42, now), Some(0), "she still owns her house");
    let after = realm_server::realm_clock::clock_from_epoch(&side(&db, EPOCH), 1).now();
    assert!(after >= before && after - before < 20 * 60, "the realm clock runs on from the same epoch ({before} then {after})");
    let _ = std::fs::remove_dir_all(&dir);
}
