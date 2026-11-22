//! The numbers the realm reports: a global registry the hooks write (a tick took this long, a store write took
//! that long, an error happened) and a renderer for `/metrics` and the `/status` page. Times are kept as the
//! last `RING` samples of each series, so p50 and p99 are of recent behaviour, not of the whole uptime.

use std::sync::Mutex;
use std::sync::atomic::{AtomicI64, AtomicU64, Ordering::Relaxed};
use std::time::Instant;

/// Samples kept per series: 2 048 ticks is 102 s of a field at 20 Hz; for store writes, the last 2 048 writes.
pub const RING: usize = 2048;
/// Field kinds that have a tick series (the realm has six; room for more).
pub const KINDS: usize = 8;

pub struct Series {
    inner: Mutex<(Vec<u32>, usize, u64)>, // micros ring, next slot, total ever
}

impl Series {
    pub const fn new() -> Series {
        Series { inner: Mutex::new((Vec::new(), 0, 0)) }
    }

    pub fn record_us(&self, us: u32) {
        let mut g = self.inner.lock().unwrap();
        if g.0.len() < RING {
            g.0.push(us);
        } else {
            let i = g.1;
            g.0[i] = us;
        }
        g.1 = (g.1 + 1) % RING;
        g.2 += 1;
    }

    pub fn record_ms(&self, ms: f64) {
        self.record_us((ms * 1000.0).clamp(0.0, u32::MAX as f64) as u32);
    }

    /// (p50, p99, samples held, total ever recorded), in milliseconds; `last` limits it to the newest `last` samples.
    pub fn percentiles(&self, last: usize) -> (f64, f64, usize, u64) {
        let g = self.inner.lock().unwrap();
        let n = g.0.len();
        let mut v: Vec<u32> = if n < RING {
            g.0[n.saturating_sub(last)..].to_vec()
        } else {
            (0..last.min(n)).map(|k| g.0[(g.1 + RING - 1 - k) % RING]).collect()
        };
        let total = g.2;
        drop(g);
        let held = v.len();
        if held == 0 {
            return (0.0, 0.0, 0, total);
        }
        v.sort_unstable();
        let at = |q: f64| v[((v.len() as f64 * q) as usize).min(v.len() - 1)] as f64 / 1000.0;
        (at(0.50), at(0.99), held, total)
    }
}

impl Default for Series {
    fn default() -> Series {
        Series::new()
    }
}

pub struct Registry {
    pub tick: [Series; KINDS],
    /// When each field kind's host last finished a tick (milliseconds since `start`; 0 = never).
    pub tick_seen: [AtomicU64; KINDS],
    pub store_write: Series,
    pub store_inflight: AtomicI64,
    pub store_errors: AtomicU64,
    pub errors: AtomicU64,
    pub login_refused: AtomicU64,
    pub conn_refused: AtomicU64,
    pub frames_dropped: AtomicU64,
    pub udp_dropped: AtomicU64,
    pub alarms: AtomicU64,
    pub backups_ok: AtomicU64,
    pub backups_failed: AtomicU64,
    pub last_backup_ms: AtomicI64,
}

#[allow(clippy::declare_interior_mutable_const)]
const S: Series = Series::new();
#[allow(clippy::declare_interior_mutable_const)]
const Z: AtomicU64 = AtomicU64::new(0);

pub static REG: Registry = Registry {
    tick: [S; KINDS],
    tick_seen: [Z; KINDS],
    store_write: Series::new(),
    store_inflight: AtomicI64::new(0),
    store_errors: Z,
    errors: Z,
    login_refused: Z,
    conn_refused: Z,
    frames_dropped: Z,
    udp_dropped: Z,
    alarms: Z,
    backups_ok: Z,
    backups_failed: Z,
    last_backup_ms: AtomicI64::new(0),
};

static START: std::sync::OnceLock<Instant> = std::sync::OnceLock::new();

fn since_start_ms() -> u64 {
    START.get_or_init(Instant::now).elapsed().as_millis() as u64 + 1
}

/// Called once at startup so uptime and the stall clocks count from there.
pub fn mark_start() {
    let _ = since_start_ms();
}

/// A field host finished a tick that took `ms`.
pub fn tick(field: u8, ms: f64) {
    let k = (field as usize).min(KINDS - 1);
    REG.tick[k].record_ms(ms);
    REG.tick_seen[k].store(since_start_ms(), Relaxed);
}

/// Milliseconds since field `k` last ticked, or None if it never has.
pub fn tick_age_ms(k: usize) -> Option<u64> {
    let seen = REG.tick_seen[k.min(KINDS - 1)].load(Relaxed);
    (seen != 0).then(|| since_start_ms().saturating_sub(seen))
}

/// Times one store write (a command through the writer thread) and counts its failure.
pub fn store_call<T, E>(f: impl FnOnce() -> Result<T, E>) -> Result<T, E> {
    REG.store_inflight.fetch_add(1, Relaxed);
    let t = Instant::now();
    let r = f();
    REG.store_write.record_us(t.elapsed().as_micros().min(u32::MAX as u128) as u32);
    REG.store_inflight.fetch_sub(1, Relaxed);
    if r.is_err() {
        REG.store_errors.fetch_add(1, Relaxed);
    }
    r
}

/// What the host knows that the registry does not: players and each field copy's load.
#[derive(Clone, Debug, Default)]
pub struct Probe {
    pub players: u64,
    /// (field kind, copy, heroes)
    pub fields: Vec<(u8, u8, u32)>,
}

pub fn uptime_secs() -> u64 {
    since_start_ms() / 1000
}

/// `/metrics`: one `name value` or `name{label="x"} value` per line, Prometheus text style.
pub fn render_metrics(p: &Probe) -> String {
    let mut o = String::new();
    let mut line = |k: &str, v: String| {
        o.push_str(k);
        o.push(' ');
        o.push_str(&v);
        o.push('\n');
    };
    line("realm_uptime_seconds", uptime_secs().to_string());
    line("realm_players", p.players.to_string());
    for (f, c, n) in &p.fields {
        line(&format!("realm_field_heroes{{field=\"{f}\",copy=\"{c}\"}}"), n.to_string());
    }
    for k in 0..KINDS {
        let (p50, p99, held, total) = REG.tick[k].percentiles(RING);
        if total == 0 {
            continue;
        }
        line(&format!("realm_tick_ms{{field=\"{k}\",q=\"p50\"}}"), format!("{p50:.3}"));
        line(&format!("realm_tick_ms{{field=\"{k}\",q=\"p99\"}}"), format!("{p99:.3}"));
        line(&format!("realm_tick_samples{{field=\"{k}\"}}"), held.to_string());
    }
    let (w50, w99, _, wn) = REG.store_write.percentiles(RING);
    line("realm_store_write_ms{q=\"p50\"}", format!("{w50:.3}"));
    line("realm_store_write_ms{q=\"p99\"}", format!("{w99:.3}"));
    line("realm_store_writes_total", wn.to_string());
    line("realm_queue", REG.store_inflight.load(Relaxed).max(0).to_string());
    line("realm_store_errors_total", REG.store_errors.load(Relaxed).to_string());
    line("realm_errors_total", REG.errors.load(Relaxed).to_string());
    line("realm_login_refused_total", REG.login_refused.load(Relaxed).to_string());
    line("realm_conn_refused_total", REG.conn_refused.load(Relaxed).to_string());
    line("realm_frames_dropped_total", REG.frames_dropped.load(Relaxed).to_string());
    line("realm_udp_dropped_total", REG.udp_dropped.load(Relaxed).to_string());
    line("realm_alarms_total", REG.alarms.load(Relaxed).to_string());
    line("realm_backups_ok_total", REG.backups_ok.load(Relaxed).to_string());
    line("realm_backups_failed_total", REG.backups_failed.load(Relaxed).to_string());
    let sw = crate::switches::describe();
    line("realm_kill_switches_on", sw.0.to_string());
    o
}

/// `/status`: the page a person reads.
pub fn render_status(p: &Probe) -> String {
    let mut o = String::from("HORDE & HEARTH realm status\n");
    o.push_str(&format!("uptime        {} s\nplayers       {}\n", uptime_secs(), p.players));
    for (f, c, n) in &p.fields {
        let (p50, p99, _, total) = REG.tick[(*f as usize).min(KINDS - 1)].percentiles(RING);
        let age = tick_age_ms(*f as usize).map_or("never".to_string(), |a| format!("{a} ms ago"));
        o.push_str(&format!("field {f} copy {c}  heroes {n:<4} tick p50 {p50:.2} ms  p99 {p99:.2} ms  ({total} ticks, last {age})\n"));
    }
    let (w50, w99, _, wn) = REG.store_write.percentiles(RING);
    o.push_str(&format!("store writes  p50 {w50:.2} ms  p99 {w99:.2} ms  ({wn} writes, {} in flight)\n", REG.store_inflight.load(Relaxed).max(0)));
    o.push_str(&format!(
        "errors        store {}  other {}  alarms {}\nrefused       logins {}  connections {}  frames dropped {}  udp dropped {}\n",
        REG.store_errors.load(Relaxed),
        REG.errors.load(Relaxed),
        REG.alarms.load(Relaxed),
        REG.login_refused.load(Relaxed),
        REG.conn_refused.load(Relaxed),
        REG.frames_dropped.load(Relaxed),
        REG.udp_dropped.load(Relaxed),
    ));
    let last = REG.last_backup_ms.load(Relaxed);
    o.push_str(&format!(
        "backups       {} ok, {} failed, last {}\n",
        REG.backups_ok.load(Relaxed),
        REG.backups_failed.load(Relaxed),
        if last == 0 { "never".to_string() } else { crate::time::iso(last) }
    ));
    o.push_str(&format!("kill switches {}\n", crate::switches::describe().1));
    o
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn percentiles_of_a_known_series() {
        let s = Series::new();
        for i in 1..=100u32 {
            s.record_us(i * 1000);
        }
        let (p50, p99, held, total) = s.percentiles(RING);
        assert_eq!((held, total), (100, 100));
        assert!((p50 - 51.0).abs() < 1.01 && (p99 - 100.0).abs() < 1.01, "{p50} {p99}");
    }

    #[test]
    fn the_ring_forgets_and_last_n_is_the_newest() {
        let s = Series::new();
        for _ in 0..RING {
            s.record_us(1_000);
        }
        for _ in 0..10 {
            s.record_us(90_000);
        }
        let (_, p99, held, total) = s.percentiles(RING);
        assert_eq!((held, total), (RING, RING as u64 + 10));
        assert!(p99 < 2.0, "10 of 2048 is under 1%: {p99}");
        let (p50n, _, _, _) = s.percentiles(10);
        assert!(p50n > 89.0, "the newest 10 are all slow: {p50n}");
    }

    #[test]
    fn store_call_counts_failures() {
        let before = REG.store_errors.load(Relaxed);
        let _ = store_call(|| Err::<(), &str>("no"));
        let _ = store_call(|| Ok::<(), &str>(()));
        assert!(REG.store_errors.load(Relaxed) > before);
        assert!(render_metrics(&Probe::default()).contains("realm_store_writes_total"));
    }
}
