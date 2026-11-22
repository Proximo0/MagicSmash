//! Flood protection at the sockets: per-IP limits on simultaneous connections, new connections and requests a
//! second (gateway TCP), and packets a second (field UDP). Fixed windows, each counted per IP: an IP that goes over
//! a limit is refused entirely for `ban_ms`. All limits are 0 (off) until `configure`, so the tests and the soak
//! (every bot is 127.0.0.1) are untouched; the host package turns them on, and loopback stays exempt.
//! The clock is a parameter (`now_ms`), so the rules are tested without sleeping.

use crate::{log, metrics};
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Mutex;
use std::sync::atomic::Ordering::Relaxed;

#[derive(Clone, Debug, Default)]
pub struct Limits {
    pub conn_per_ip: u32,
    pub conn_rate: u32,
    pub pkt_rate: u32,
    pub udp_rate: u32,
    pub window_ms: i64,
    pub ban_ms: i64,
    pub exempt: Vec<IpAddr>,
}

#[derive(Default)]
struct Entry {
    conns: u32,
    win_start: i64,
    new_conns: u32,
    frames: u32,
    udp: u32,
    banned_until: i64,
    last_seen: i64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Verdict {
    Allow,
    Refuse,
}

pub struct Flood {
    lim: Limits,
    ips: HashMap<IpAddr, Entry>,
    calls: u64,
}

impl Flood {
    pub fn new(lim: Limits) -> Flood {
        Flood { lim, ips: HashMap::new(), calls: 0 }
    }

    fn entry(&mut self, ip: IpAddr, now: i64) -> Option<&mut Entry> {
        if self.lim.exempt.contains(&ip) {
            return None;
        }
        self.calls += 1;
        if self.calls % 4096 == 0 {
            // Forget IPs that are idle with nothing open: the table stays as big as the crowd, not the history.
            let keep = self.lim.window_ms.max(self.lim.ban_ms) * 2;
            self.ips.retain(|_, e| e.conns > 0 || now - e.last_seen < keep);
        }
        let w = self.lim.window_ms.max(1);
        let e = self.ips.entry(ip).or_default();
        if now - e.win_start >= w {
            e.win_start = now;
            e.new_conns = 0;
            e.frames = 0;
            e.udp = 0;
        }
        e.last_seen = now;
        Some(e)
    }

    fn ban(lim: &Limits, e: &mut Entry, ip: IpAddr, now: i64, why: &str) {
        e.banned_until = now + lim.ban_ms;
        log::warn("flood_ban", &[("ip", ip.to_string()), ("why", why.into()), ("secs", (lim.ban_ms / 1000).to_string())]);
    }

    /// A new TCP connection from `ip`. On Allow the caller must `disconnect` when it ends.
    pub fn connect(&mut self, ip: IpAddr, now: i64) -> Verdict {
        let lim = self.lim.clone();
        let Some(e) = self.entry(ip, now) else { return Verdict::Allow };
        if e.banned_until > now {
            return Verdict::Refuse;
        }
        e.new_conns += 1;
        if lim.conn_rate > 0 && e.new_conns > lim.conn_rate {
            Self::ban(&lim, e, ip, now, "connection rate");
            return Verdict::Refuse;
        }
        if lim.conn_per_ip > 0 && e.conns >= lim.conn_per_ip {
            Self::ban(&lim, e, ip, now, "too many connections");
            return Verdict::Refuse;
        }
        e.conns += 1;
        Verdict::Allow
    }

    pub fn disconnect(&mut self, ip: IpAddr) {
        if let Some(e) = self.ips.get_mut(&ip) {
            e.conns = e.conns.saturating_sub(1);
        }
    }

    /// One request frame from a connection of `ip`.
    pub fn frame(&mut self, ip: IpAddr, now: i64) -> Verdict {
        let lim = self.lim.clone();
        let Some(e) = self.entry(ip, now) else { return Verdict::Allow };
        if e.banned_until > now {
            return Verdict::Refuse;
        }
        e.frames += 1;
        // A window's worth is the budget: `pkt_rate` a second for `window` seconds.
        if lim.pkt_rate > 0 && e.frames as i64 > lim.pkt_rate as i64 * lim.window_ms.max(1000) / 1000 {
            Self::ban(&lim, e, ip, now, "request rate");
            return Verdict::Refuse;
        }
        Verdict::Allow
    }

    /// One UDP datagram from `ip`.
    pub fn udp(&mut self, ip: IpAddr, now: i64) -> Verdict {
        let lim = self.lim.clone();
        let Some(e) = self.entry(ip, now) else { return Verdict::Allow };
        if e.banned_until > now {
            return Verdict::Refuse;
        }
        e.udp += 1;
        if lim.udp_rate > 0 && e.udp as i64 > lim.udp_rate as i64 * lim.window_ms.max(1000) / 1000 {
            Self::ban(&lim, e, ip, now, "udp rate");
            return Verdict::Refuse;
        }
        Verdict::Allow
    }

    pub fn banned(&self, ip: IpAddr, now: i64) -> bool {
        self.ips.get(&ip).is_some_and(|e| e.banned_until > now)
    }

    pub fn tracked(&self) -> usize {
        self.ips.len()
    }
}

static GLOBAL: Mutex<Option<Flood>> = Mutex::new(None);
/// Read first on every packet, so a realm with the limits off pays one relaxed load.
static ON: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Turns the global limits on. With every limit 0 this is a no-op.
pub fn configure(lim: Limits) {
    let on = lim.conn_per_ip + lim.conn_rate + lim.pkt_rate + lim.udp_rate > 0;
    *GLOBAL.lock().unwrap() = on.then(|| Flood::new(lim));
    ON.store(on, Relaxed);
}

pub fn enabled() -> bool {
    ON.load(Relaxed)
}

fn with(f: impl FnOnce(&mut Flood, i64) -> Verdict, count: impl FnOnce()) -> bool {
    if !ON.load(Relaxed) {
        return true;
    }
    let mut g = GLOBAL.lock().unwrap();
    let Some(fl) = g.as_mut() else { return true };
    if f(fl, crate::time::now_ms()) == Verdict::Allow {
        return true;
    }
    count();
    false
}

/// Gateway accept: false = close the socket at once.
pub fn allow_connect(ip: IpAddr) -> bool {
    with(|f, t| f.connect(ip, t), || {
        metrics::REG.conn_refused.fetch_add(1, Relaxed);
    })
}

pub fn connection_closed(ip: IpAddr) {
    if let Some(f) = GLOBAL.lock().unwrap().as_mut() {
        f.disconnect(ip);
    }
}

/// Gateway request: false = drop the connection.
pub fn allow_frame(ip: IpAddr) -> bool {
    with(|f, t| f.frame(ip, t), || {
        metrics::REG.frames_dropped.fetch_add(1, Relaxed);
    })
}

/// Field host datagram: false = ignore it.
pub fn allow_udp(ip: IpAddr) -> bool {
    with(|f, t| f.udp(ip, t), || {
        metrics::REG.udp_dropped.fetch_add(1, Relaxed);
    })
}

/// Reads the exempt list setting.
pub fn parse_exempt(s: &str) -> Vec<IpAddr> {
    s.split(',').filter_map(|x| x.trim().parse().ok()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ip(n: u8) -> IpAddr {
        IpAddr::from([10, 0, 0, n])
    }

    fn lim() -> Limits {
        Limits { conn_per_ip: 3, conn_rate: 5, pkt_rate: 10, udp_rate: 20, window_ms: 10_000, ban_ms: 60_000, exempt: vec!["127.0.0.1".parse().unwrap()] }
    }

    #[test]
    fn simultaneous_connections_are_capped_per_ip() {
        let mut f = Flood::new(lim());
        for _ in 0..3 {
            assert_eq!(f.connect(ip(1), 0), Verdict::Allow);
        }
        assert_eq!(f.connect(ip(1), 1), Verdict::Refuse);
        assert!(f.banned(ip(1), 2));
        // Another address is not touched, and the ban ends.
        assert_eq!(f.connect(ip(2), 2), Verdict::Allow);
        f.disconnect(ip(1));
        assert_eq!(f.connect(ip(1), 30_000), Verdict::Refuse);
        assert_eq!(f.connect(ip(1), 61_000), Verdict::Allow);
    }

    #[test]
    fn connection_rate_counts_opens_not_holds() {
        let mut f = Flood::new(lim());
        for i in 0..5 {
            assert_eq!(f.connect(ip(1), i), Verdict::Allow);
            f.disconnect(ip(1));
        }
        assert_eq!(f.connect(ip(1), 6), Verdict::Refuse);
        // A slow, steady client is never limited: one a window.
        for i in 0..20 {
            assert_eq!(f.connect(ip(3), i * 11_000), Verdict::Allow);
            f.disconnect(ip(3));
        }
    }

    #[test]
    fn packets_are_limited_per_window() {
        let mut f = Flood::new(lim());
        for _ in 0..100 {
            assert_eq!(f.frame(ip(1), 500), Verdict::Allow);
        }
        assert_eq!(f.frame(ip(1), 600), Verdict::Refuse);
        for _ in 0..200 {
            assert_eq!(f.udp(ip(2), 500), Verdict::Allow);
        }
        assert_eq!(f.udp(ip(2), 600), Verdict::Refuse);
        // The next window after the ban: allowed again.
        assert_eq!(f.udp(ip(2), 70_000), Verdict::Allow);
    }

    #[test]
    fn loopback_is_exempt_and_the_table_does_not_grow_forever() {
        let mut f = Flood::new(lim());
        let lo: IpAddr = "127.0.0.1".parse().unwrap();
        for _ in 0..1000 {
            assert_eq!(f.connect(lo, 0), Verdict::Allow);
            assert_eq!(f.udp(lo, 0), Verdict::Allow);
        }
        assert_eq!(f.tracked(), 0);
        for i in 0..10_000u32 {
            let a = IpAddr::from([10, (i >> 8) as u8, i as u8, 9]);
            f.udp(a, i as i64 * 100);
        }
        assert!(f.tracked() < 10_000, "idle IPs are pruned: {}", f.tracked());
    }

    #[test]
    fn exempt_list_parses() {
        assert_eq!(parse_exempt("127.0.0.1, ::1,junk").len(), 2);
    }
}
