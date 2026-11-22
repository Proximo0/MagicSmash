//! What runs inside the gateway process once `--ops-conf` is given: the log sink, the flood limits, the saved kill
//! switches, the loopback metrics server, the watcher that evaluates the alarms every second, and the backup clock.
//! `start` returns at once; the threads end with the process.

use crate::alarm::{Alarms, Evaluator, Limits, Reading};
use crate::config::Conf;
use crate::metrics::{self, Probe};
use crate::{flood, log, switches, time};
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

/// What the gateway tells the runtime about itself, on demand.
pub type ProbeFn = Arc<dyn Fn() -> Probe + Send + Sync>;

pub struct Running {
    /// The metrics address (loopback), when it is on.
    pub metrics: Option<SocketAddr>,
}

pub fn flood_limits(c: &Conf) -> flood::Limits {
    flood::Limits {
        conn_per_ip: c.num("flood_conn_per_ip") as u32,
        conn_rate: c.num("flood_conn_rate") as u32,
        pkt_rate: c.num("flood_pkt_rate") as u32,
        udp_rate: c.num("flood_udp_rate") as u32,
        window_ms: c.num("flood_window_secs") as i64 * 1000,
        ban_ms: c.num("flood_ban_secs") as i64 * 1000,
        exempt: flood::parse_exempt(c.get("flood_exempt")),
    }
}

/// The file (in the host folder, beside ops.conf) that asks a running gateway to stop: it banks every hero in a
/// field, ends its hosts and exits. `realm-ops stop` and `restart` have the supervisor drop it (`supervise`).
pub const GATEWAY_STOP: &str = "gateway.stop";

pub fn start(c: &Conf, root: &Path, probe: ProbeFn) -> std::io::Result<Running> {
    metrics::mark_start();
    log::init(&c.path(root, "log_dir"), c.num("log_max_mb"), c.num("log_keep") as usize)?;
    let db = c.path(root, "db");
    switches::persist(crate::sides::side(&db, crate::sides::SWITCHES));
    flood::configure(flood_limits(c));
    log::info("realm_start", &[("db", db.display().to_string()), ("fields", c.get("fields").to_string()), ("flood", flood::enabled().to_string())]);

    let mut running = Running { metrics: None };
    let port = c.num("metrics_port") as u16;
    if port > 0 {
        let l = TcpListener::bind(("127.0.0.1", port))?;
        running.metrics = Some(l.local_addr()?);
        serve_metrics(l, probe.clone());
    }
    watch(c, probe);
    if c.num("backup_every_mins") > 0 {
        backup_clock(c, root);
    }
    Ok(running)
}

/// Starts only the metrics server on an address (port 0 = a free one); for tests and the rehearsal.
pub fn serve_on(port: u16, probe: ProbeFn) -> std::io::Result<SocketAddr> {
    let l = TcpListener::bind(("127.0.0.1", port))?;
    let a = l.local_addr()?;
    serve_metrics(l, probe);
    Ok(a)
}

fn serve_metrics(l: TcpListener, probe: ProbeFn) {
    let _ = std::thread::Builder::new().name("metrics".into()).spawn(move || {
        for s in l.incoming().flatten() {
            // One request at a time, with a short fuse: this is a status page, not a server.
            let _ = answer(s, &probe);
        }
    });
}

fn answer(mut s: TcpStream, probe: &ProbeFn) -> std::io::Result<()> {
    s.set_read_timeout(Some(Duration::from_secs(2)))?;
    s.set_write_timeout(Some(Duration::from_secs(2)))?;
    if !s.peer_addr().is_ok_and(|a| a.ip().is_loopback()) {
        return Ok(());
    }
    // Read to the end of the request head (a client may send it in pieces).
    let mut buf = [0u8; 2048];
    let mut n = 0;
    while n < buf.len() && !buf[..n].windows(4).any(|w| w == b"\r\n\r\n") {
        let k = s.read(&mut buf[n..])?;
        if k == 0 {
            break;
        }
        n += k;
    }
    let head = String::from_utf8_lossy(&buf[..n]);
    let path = head.split_whitespace().nth(1).unwrap_or("/");
    let (code, body) = match path.split('?').next().unwrap_or("/") {
        "/metrics" => ("200 OK", metrics::render_metrics(&probe())),
        "/" | "/status" => ("200 OK", metrics::render_status(&probe())),
        "/health" => ("200 OK", "ok\n".to_string()),
        _ => ("404 Not Found", "not found\n".to_string()),
    };
    s.write_all(format!("HTTP/1.1 {code}\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}", body.len()).as_bytes())
}

/// GET `path` from a loopback metrics server; the body.
pub fn fetch(addr: SocketAddr, path: &str) -> Result<String, String> {
    let mut s = TcpStream::connect_timeout(&addr, Duration::from_secs(2)).map_err(|e| e.to_string())?;
    s.set_read_timeout(Some(Duration::from_secs(5))).map_err(|e| e.to_string())?;
    s.write_all(format!("GET {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n").as_bytes()).map_err(|e| e.to_string())?;
    let mut t = String::new();
    s.read_to_string(&mut t).map_err(|e| e.to_string())?;
    t.split_once("\r\n\r\n").map(|(_, b)| b.to_string()).ok_or_else(|| "no body".to_string())
}

pub fn reading() -> Reading {
    let fields = (0..metrics::KINDS)
        .filter_map(|k| {
            let (_, p99, _, total) = metrics::REG.tick[k].percentiles(200);
            (total > 0).then(|| (k as u8, p99, total.min(200), metrics::tick_age_ms(k)))
        })
        .collect();
    Reading { fields, store_errors_total: metrics::REG.store_errors.load(std::sync::atomic::Ordering::Relaxed) }
}

fn watch(c: &Conf, _probe: ProbeFn) {
    let lim = Limits { tick_budget_ms: c.num("tick_budget_ms") as f64, stall_ms: c.num("stall_secs") * 1000, store_errors_per_min: c.num("store_error_limit") };
    let mut alarms = Alarms::new(c.get("alarm_hook"), c.num("alarm_cooldown_secs"));
    let mut ev = Evaluator::default();
    let _ = std::thread::Builder::new().name("ops-watch".into()).spawn(move || {
        loop {
            std::thread::sleep(Duration::from_secs(1));
            let now = time::now_ms();
            for (kind, msg) in ev.evaluate(&lim, &reading(), now) {
                alarms.raise(kind, &msg, now);
            }
        }
    });
}

#[cfg(feature = "store")]
fn backup_clock(c: &Conf, root: &Path) {
    let (db, dir) = (c.path(root, "db"), c.path(root, "backup_dir"));
    let (every, keep, daily) = (c.num("backup_every_mins"), c.num("backup_keep") as usize, c.num("backup_daily_keep") as usize);
    let mut alarms = Alarms::new(c.get("alarm_hook"), c.num("alarm_cooldown_secs"));
    let _ = std::thread::Builder::new().name("ops-backup".into()).spawn(move || {
        // First one a minute after start, unless a recent one exists (restarts must not skip a whole interval).
        let mut wait = match crate::backup::newest_age_ms(&dir, time::now_ms()) {
            Some(age) => (every as i64 * 60_000 - age).clamp(60_000, every as i64 * 60_000),
            None => 60_000,
        };
        loop {
            std::thread::sleep(Duration::from_millis(wait as u64));
            wait = every as i64 * 60_000;
            let now = time::now_ms();
            match crate::backup::backup_now(&db, &dir, keep, daily, now) {
                Ok(m) => {
                    metrics::REG.backups_ok.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    metrics::REG.last_backup_ms.store(now, std::sync::atomic::Ordering::Relaxed);
                    log::info("backup_ok", &[("file", m.file.display().to_string()), ("bytes", m.bytes.to_string()), ("items", m.items.to_string()), ("ledger", m.ledger_rows.to_string())]);
                }
                Err(e) => {
                    metrics::REG.backups_failed.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    alarms.raise("backup-failed", &e, now);
                }
            }
        }
    });
}

#[cfg(not(feature = "store"))]
fn backup_clock(_: &Conf, _: &Path) {}
