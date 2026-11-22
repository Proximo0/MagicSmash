//! realm-lanplay: bots that play against a REMOTE gateway the way a player's client does: TLS to the gateway
//! (trusting exactly the PEM given with `--ca`), login, hero, town, field ticket, field play over UDP with the
//! per-admission key, bank. Used by `tools/station/jobs/lanplay.sh` (the LAN rehearsal, docs/realm/ops.md).
//!
//! `realm-lanplay --addr=192.168.1.20:7700 --ca=host.pem --bots=4 --secs=120 [--base=1000] [--field=0,1] [--fight-secs=10]`
//! One summary line, `LANPLAY ok|FAILED ...`; exit 0 ok, 1 failed, 3 host unreachable, 2 bad usage.

use realm_gateway::bot::PlayOpts;
use realm_gateway::harness::{cycle, BotStats, Prep};
use realm_gateway::tls::ClientTls;
use std::net::ToSocketAddrs;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

fn die(msg: &str) -> ! {
    eprintln!("realm-lanplay: {msg}");
    std::process::exit(2);
}

fn main() {
    let (mut addr, mut bots, mut secs, mut base, mut fields) = (String::new(), 2u64, 60u64, 1000u64, vec![0u8]);
    let mut tls = ClientTls::default();
    let mut play = PlayOpts { fight_ticks: 200, max_ticks: 20 * 90, ..PlayOpts::default() };
    for arg in std::env::args().skip(1) {
        let (k, v) = arg.split_once('=').unwrap_or((arg.as_str(), ""));
        let num = |v: &str| v.parse::<u64>().unwrap_or_else(|_| die(&format!("bad value in {arg}")));
        if tls.flag(k, v) {
            continue;
        }
        match k {
            "--addr" => addr = v.to_string(),
            "--bots" => bots = num(v),
            "--secs" => secs = num(v),
            "--base" => base = num(v),
            "--field" => fields = v.split(',').map(|f| num(f) as u8).collect(),
            "--fight-secs" => play.fight_ticks = num(v) as u32 * 20,
            "--max-secs" => play.max_ticks = num(v) as u32 * 20,
            "--help" | "-h" => {
                println!("realm-lanplay --addr=HOST:PORT {} [--bots=2] [--secs=60] [--base=1000 (bot numbers start here: one per player machine)] [--field=0,1] [--fight-secs=10] [--max-secs=90]", ClientTls::HELP);
                return;
            }
            _ => die(&format!("unknown flag {arg}")),
        }
    }
    if addr.is_empty() || bots == 0 || fields.is_empty() || fields.iter().any(|&f| f > 5) {
        die("need --addr=HOST:PORT, --bots>=1, --field in 0..5");
    }
    let cfg = tls.config().unwrap_or_else(|e| die(&e));
    // Is the host there at all? One TCP connect, so a closed port or a firewall is told apart from a TLS failure.
    let sa = addr.to_socket_addrs().ok().and_then(|mut a| a.next());
    let reach = match sa {
        Some(a) => std::net::TcpStream::connect_timeout(&a, Duration::from_secs(8)).map(|_| ()).map_err(|e| e.to_string()),
        None => Err("address does not resolve".to_string()),
    };
    if let Err(e) = reach {
        println!("LANPLAY UNREACHABLE addr={addr} ({e})");
        std::process::exit(3);
    }
    let stop = Arc::new(AtomicBool::new(false));
    let total = Arc::new(Mutex::new(BotStats::default()));
    let prep: Arc<Box<Prep>> = Arc::new(Box::new(|_| {}));
    let start = Instant::now();
    let mut threads = Vec::new();
    for b in 0..bots {
        let (addr, stop, total, play, prep, cfg, fields) = (addr.clone(), stop.clone(), total.clone(), play.clone(), prep.clone(), cfg.clone(), fields.clone());
        threads.push(std::thread::spawn(move || {
            let (id, mut n) = (base + b, 0u64);
            while !stop.load(Ordering::Relaxed) {
                let mut st = BotStats::default();
                let mut p = play.clone();
                p.seed = id ^ (n << 20);
                p.stop = Some(stop.clone());
                let field = fields[((b + n) as usize) % fields.len()];
                if let Err(e) = cycle(&addr, cfg.as_ref(), id, field, &p, &**prep, &mut st) {
                    st.errors.push(format!("bot {id}: {e}"));
                    if !stop.load(Ordering::Relaxed) {
                        std::thread::sleep(Duration::from_millis(500));
                    }
                }
                n += 1;
                total.lock().unwrap().add(&st);
            }
        }));
    }
    while start.elapsed() < Duration::from_secs(secs) {
        std::thread::sleep(Duration::from_millis(250));
    }
    stop.store(true, Ordering::Relaxed);
    for t in threads {
        let _ = t.join();
    }
    let t = total.lock().unwrap().clone();
    let has = |e: &String, w: &[&str]| w.iter().any(|w| e.contains(w));
    let handshake = t.errors.iter().filter(|e| has(e, &["handshake", "certificate", "server name", "InvalidData"])).count();
    let auth = t.errors.iter().filter(|e| has(e, &["login:", "Resp::Err", "DISABLED", "BANNED"])).count();
    let mut rtts = t.rtts_us.clone();
    rtts.sort_unstable();
    let mean = if rtts.is_empty() { 0.0 } else { rtts.iter().map(|&r| r as f64).sum::<f64>() / rtts.len() as f64 / 1000.0 };
    let p99 = if rtts.is_empty() { 0.0 } else { rtts[(rtts.len() * 99 / 100).min(rtts.len() - 1)] as f64 / 1000.0 };
    let failed_logins = t.errors.len() as u64; // every failed cycle; logins_ok counts accepted logins
    let ok = handshake == 0 && auth == 0 && t.outings > 0 && t.logins > 0 && t.mismatches == 0 && t.hash_bad == 0;
    for e in t.errors.iter().take(8) {
        eprintln!("realm-lanplay: {e}");
    }
    println!(
        "LANPLAY {} addr={addr} secs={:.0} logins_ok={} cycles_failed={failed_logins} handshake_failed={handshake} auth_failed={auth} outings={} banked={} deposits={} rtt_mean_ms={mean:.2} rtt_p99_ms={p99:.2} calls={} refused_datagrams={} hash_bad={} mismatches={}",
        if ok { "ok" } else { "FAILED" },
        start.elapsed().as_secs_f64(),
        t.logins,
        t.outings,
        t.banked_outings,
        t.deposits,
        rtts.len(),
        t.bad_datagrams,
        t.hash_bad,
        t.mismatches
    );
    std::process::exit(if ok { 0 } else { 1 });
}
