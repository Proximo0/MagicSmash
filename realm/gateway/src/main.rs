//! realm-gateway: the realm's one program: the gateway (accounts, heroes, towns, tickets, the store) and a field
//! host for each field copy, in one process, on one store file.
//!
//! `realm-gateway --db=realm.db --dev-login --port=7700 --fields=0,1,2,3,4,5 --field-port=7800`
//! `realm-gateway --db=realm.db --tls-cert=fullchain.pem --tls-key=privkey.pem` (launch) or `--dev-cert` (a
//! self-signed pair beside the store, for local play): the TCP side speaks TLS only. With neither, the gateway
//! starts only with `--dev-login` or `--plain`, and says loudly that it is unencrypted (`docs/realm/wire.md`).
//! prints `LISTEN tcp=ADDR udp=PORT,PORT,...` when it is ready (with `--port=0` and `--field-port=0` the system
//! picks free ports). It runs until it is stopped; stopping it with SIGINT or SIGTERM is not graceful (the
//! standard library has no signal handling), which is the point of the kill test: everything banked is already
//! in the store, and `--secs=N` ends it gracefully after N seconds (heroes still in a field are banked first).

use realm_gateway::conn::listen_tls;
use realm_gateway::gateway::{load_secret, Config, Gateway};
use realm_gateway::world::WorldConfig;
use realm_server::host::HostOpts;
use realm_server::sim::SimOpts;
use realm_store::SqliteStore;
use std::sync::Arc;
use std::time::Duration;

fn die(msg: &str) -> ! {
    eprintln!("realm-gateway: {msg}");
    std::process::exit(2);
}

fn main() {
    if std::env::args().nth(1).as_deref() == Some("admin") {
        let args: Vec<String> = std::env::args().skip(2).collect();
        std::process::exit(realm_gateway::social::admin::cli(&args));
    }
    let (mut db, mut port, mut fields, mut field_port) = ("realm.db".to_string(), 7700u16, vec![0u8, 1, 2, 3, 4, 5], 7800u16);
    let (mut monsters, mut threads, mut seed, mut dev, mut public_host, mut bind, mut secs) = (20_000u32, 1usize, 1u64, false, String::new(), "0.0.0.0".to_string(), 0u64);
    let mut copies = 1u32;
    let mut dev_grant = false;
    let mut admin_port: Option<u16> = None;
    let mut secret: Option<u64> = None;
    let mut world = WorldConfig::default();
    let mut speed = 1u32;
    let mut ops_conf: Option<String> = None;
    let (mut tls_cert, mut tls_key, mut dev_cert, mut plain) = (None::<String>, None::<String>, false, false);
    for arg in std::env::args().skip(1) {
        let (k, v) = arg.split_once('=').unwrap_or((arg.as_str(), ""));
        let num = |v: &str| v.parse::<u64>().unwrap_or_else(|_| die(&format!("bad value in {arg}")));
        match k {
            "--db" => db = v.to_string(),
            "--port" => port = num(v) as u16,
            "--fields" => fields = v.split(',').filter(|f| !f.is_empty()).map(|f| num(f) as u8).collect(),
            "--field-port" => field_port = num(v) as u16,
            "--copies" => copies = num(v).max(1) as u32,
            "--monsters" => monsters = num(v) as u32,
            "--threads" => threads = num(v).max(1) as usize,
            "--seed" => seed = num(v),
            "--dev-login" => dev = true,
            "--dev-grant" => dev_grant = true,
            "--public-host" => public_host = v.to_string(),
            "--bind" => bind = v.to_string(),
            "--secs" => secs = num(v),
            "--secret" => secret = Some(num(v)),
            "--admin-port" => admin_port = Some(num(v) as u16),
            "--realm-cap" => world.realm_cap = num(v) as u32,
            "--copy-cap" => world.copies.cap = num(v) as u32,
            "--open-at" => world.copies.open_at = num(v) as u32,
            "--merge-under" => world.copies.merge_under = num(v) as u32,
            "--max-copies" => world.copies.max_copies = num(v).max(1) as u32,
            "--vault-max" => world.vault_max = num(v) as u32,
            "--vault-monsters" => world.vault_monsters = num(v) as u32,
            "--dev-bots" => world.dev_bots = true,
            "--clock-speed" => speed = num(v).max(1) as u32,
            "--ops-conf" => ops_conf = Some(v.to_string()),
            "--tls-cert" => tls_cert = Some(v.to_string()),
            "--tls-key" => tls_key = Some(v.to_string()),
            "--dev-cert" => dev_cert = true,
            "--plain" => plain = true,
            "--help" | "-h" => {
                println!("realm-gateway [--db=realm.db] [--dev-login] [--dev-grant] [--bind=0.0.0.0] [--port=7700] [--fields=0,1,2,3,4,5] [--copies=1] [--field-port=7800] [--monsters=20000] [--threads=1] [--seed=1] [--public-host=ADDR] [--secret=N (default: kept in DB.secret)] [--admin-port=N (loopback console, token in DB.admin)] [--ops-conf=FILE (logs, metrics, alarms, backup clock, flood limits: docs/realm/ops.md)] [--secs=N] [--realm-cap=4000] [--copy-cap=1000] [--open-at=800] [--merge-under=500] [--max-copies=4] [--vault-max=64] [--vault-monsters=4000] [--dev-bots] [--clock-speed=1] [--tls-cert=PEM --tls-key=PEM | --dev-cert | --plain]\n       realm-gateway admin (--db=FILE | --connect=ADDR --token-file=FILE) [--op=NAME] COMMAND... (try: help)");
                return;
            }
            _ => die(&format!("unknown flag {arg}")),
        }
    }
    if fields.iter().any(|&f| f > 5) {
        die("--fields are 0..5");
    }
    // The TCP side: TLS from a real pair, or a dev pair made beside the store; plain text only when asked.
    let tls = match (&tls_cert, &tls_key, dev_cert) {
        (Some(c), Some(k), false) => Some(realm_gateway::tls::server_config(std::path::Path::new(c), std::path::Path::new(k)).unwrap_or_else(|e| die(&format!("TLS: {e}")))),
        (None, None, true) => {
            let (c, k) = realm_gateway::tls::dev_cert_files(&db, &public_host).unwrap_or_else(|e| die(&format!("--dev-cert: {e}")));
            eprintln!("realm-gateway: TLS with the dev certificate {} (clients trust it with --ca={})", c.display(), c.display());
            Some(realm_gateway::tls::server_config(&c, &k).unwrap_or_else(|e| die(&format!("TLS: {e}"))))
        }
        (None, None, false) if dev || plain => {
            eprintln!("realm-gateway: WARNING: UNENCRYPTED: the gateway speaks plain TCP; logins, chat and field tickets cross the network in clear text (dev only; use --tls-cert/--tls-key or --dev-cert)");
            None
        }
        (None, None, false) => die("no TLS certificate: give --tls-cert=PEM --tls-key=PEM, or --dev-cert for local play, or --plain (or --dev-login) to run unencrypted"),
        _ => die("give --tls-cert and --tls-key together, or --dev-cert alone"),
    };
    let store = Arc::new(SqliteStore::open(&db).unwrap_or_else(|e| die(&format!("open {db}: {e}"))));
    let secret = secret.unwrap_or_else(|| load_secret(std::path::Path::new(&format!("{db}.secret"))));
    let first_kills = Some(std::path::PathBuf::from(format!("{db}.bosskills")));
    world.monsters = monsters;
    world.threads = threads;
    world.seed = seed;
    // The realm's clock runs from an epoch kept beside the store, so a restart does not move a tide.
    world.clock = Some(realm_server::realm_clock::clock_from_epoch(std::path::Path::new(&format!("{db}.epoch")), speed));
    let gw = Gateway::start(store, Config { dev_login: dev, public_host, secret, first_kills, dev_grant, world });
    if let Err(e) = gw.social.persist(std::path::Path::new(&format!("{db}.social"))) {
        die(&format!("social log {db}.social: {e}"));
    }
    if let Err(e) = gw.homes.persist(std::path::Path::new(&format!("{db}.homes"))) {
        die(&format!("homes file {db}.homes: {e}"));
    }
    if let Some(p) = admin_port {
        let token = realm_gateway::social::admin::load_token(std::path::Path::new(&format!("{db}.admin")));
        let a = realm_gateway::social::admin::serve(gw.clone(), p, token).unwrap_or_else(|e| die(&format!("admin port {p}: {e}")));
        println!("ADMIN {a}");
    }
    if let Some(p) = ops_conf {
        let p = std::path::PathBuf::from(p);
        let conf = realm_ops::config::Conf::load(&p).unwrap_or_else(|e| die(&e));
        let root = p.parent().filter(|d| !d.as_os_str().is_empty()).map_or_else(|| std::path::PathBuf::from("."), |d| d.to_path_buf());
        let g = gw.clone();
        let probe: realm_ops::runtime::ProbeFn = Arc::new(move || {
            let fields = g.host_loads();
            realm_ops::metrics::Probe { players: fields.iter().map(|f| f.2 as u64).sum(), fields }
        });
        match realm_ops::runtime::start(&conf, &root, probe) {
            Ok(r) => println!("OPS metrics={}", r.metrics.map_or("off".to_string(), |a| a.to_string())),
            Err(e) => die(&format!("ops: {e}")),
        }
    }
    let mut udp = Vec::new();
    let mut n = 0u16;
    for _ in 0..copies {
        for &f in &fields {
            let p = if field_port == 0 { 0 } else { field_port + n };
            n += 1;
            // Every copy of a field shares its seed (the same map); new copies the world opens pick free ports.
            let sim = SimOpts { field: f, seed: seed + f as u64, monsters, threads, bots: 0, rally_permille: 0, level: 0, vault: None };
            let addr = gw.add_host(HostOpts { sim, port: p, ..HostOpts::default() }).unwrap_or_else(|e| die(&format!("field {f} on {p}: {e}")));
            udp.push(addr.port().to_string());
        }
    }
    let listener = listen_tls(gw.clone(), &format!("{bind}:{port}"), tls.clone()).unwrap_or_else(|e| die(&format!("listen {bind}:{port}: {e}")));
    println!("LISTEN tcp={} udp={} tls={}", listener.addr, udp.join(","), if tls.is_some() { "on" } else { "off" });
    use std::io::Write;
    let _ = std::io::stdout().flush();
    if secs > 0 {
        std::thread::sleep(Duration::from_secs(secs));
        drop(listener);
        gw.shutdown();
    } else {
        loop {
            std::thread::sleep(Duration::from_secs(3600));
        }
    }
}
