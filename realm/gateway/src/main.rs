//! realm-gateway: the realm's one program: the gateway (accounts, heroes, towns, tickets, the store) and a field
//! host for each field copy, in one process, on one store file.
//!
//! `realm-gateway --db=realm.db --dev-login --port=7700 --fields=0,1,2,3,4,5 --field-port=7800`
//! prints `LISTEN tcp=ADDR udp=PORT,PORT,...` when it is ready (with `--port=0` and `--field-port=0` the system
//! picks free ports). It runs until it is stopped; stopping it with SIGINT or SIGTERM is not graceful (the
//! standard library has no signal handling), which is the point of the kill test: everything banked is already
//! in the store, and `--secs=N` ends it gracefully after N seconds (heroes still in a field are banked first).

use realm_gateway::conn::listen;
use realm_gateway::gateway::{load_secret, Config, Gateway};
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
            "--help" | "-h" => {
                println!("realm-gateway [--db=realm.db] [--dev-login] [--dev-grant] [--bind=0.0.0.0] [--port=7700] [--fields=0,1,2,3,4,5] [--copies=1] [--field-port=7800] [--monsters=20000] [--threads=1] [--seed=1] [--public-host=ADDR] [--secret=N (default: kept in DB.secret)] [--admin-port=N (loopback console, token in DB.admin)] [--secs=N]\n       realm-gateway admin (--db=FILE | --connect=ADDR --token-file=FILE) [--op=NAME] COMMAND... (try: help)");
                return;
            }
            _ => die(&format!("unknown flag {arg}")),
        }
    }
    if fields.iter().any(|&f| f > 5) {
        die("--fields are 0..5");
    }
    let store = Arc::new(SqliteStore::open(&db).unwrap_or_else(|e| die(&format!("open {db}: {e}"))));
    let secret = secret.unwrap_or_else(|| load_secret(std::path::Path::new(&format!("{db}.secret"))));
    let first_kills = Some(std::path::PathBuf::from(format!("{db}.bosskills")));
    let gw = Gateway::start(store, Config { dev_login: dev, public_host, secret, first_kills, dev_grant });
    if let Err(e) = gw.social.persist(std::path::Path::new(&format!("{db}.social"))) {
        die(&format!("social log {db}.social: {e}"));
    }
    if let Some(p) = admin_port {
        let token = realm_gateway::social::admin::load_token(std::path::Path::new(&format!("{db}.admin")));
        let a = realm_gateway::social::admin::serve(gw.clone(), p, token).unwrap_or_else(|e| die(&format!("admin port {p}: {e}")));
        println!("ADMIN {a}");
    }
    let mut udp = Vec::new();
    let mut n = 0u16;
    for c in 0..copies {
        for &f in &fields {
            let p = if field_port == 0 { 0 } else { field_port + n };
            n += 1;
            let sim = SimOpts { field: f, seed: seed + n as u64 + c as u64 * 1000, monsters, threads, bots: 0, rally_permille: 0, level: 0 };
            let addr = gw.add_host(HostOpts { sim, port: p, ..HostOpts::default() }).unwrap_or_else(|e| die(&format!("field {f} on {p}: {e}")));
            udp.push(addr.port().to_string());
        }
    }
    let listener = listen(gw.clone(), &format!("{bind}:{port}")).unwrap_or_else(|e| die(&format!("listen {bind}:{port}: {e}")));
    println!("LISTEN tcp={} udp={}", listener.addr, udp.join(","));
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
