//! A UDP relay that makes a bad connection: `--relay=PORT --to=HOST:PORT --loss=0.05 --delay-ms=80
//! --jitter-ms=20 [--seed=1] [--secs=N]`.
//!
//! Every client that sends to PORT gets its own socket toward the server (so the server sees one address per
//! client). Each datagram, in either direction, is dropped with the chance `loss`, otherwise delivered
//! `delay-ms` plus or minus up to `jitter-ms` later (one way, so the round trip is twice that). Jitter can
//! reorder datagrams, as a real path sometimes does. The randomness is seeded: the same seed drops the same
//! share in the same pattern for the same traffic.

use std::cmp::Reverse;
use std::collections::{BinaryHeap, HashMap};
use std::net::{SocketAddr, UdpSocket};
use std::time::{Duration, Instant};

pub struct RelayArgs {
    pub port: u16,
    pub to: String,
    /// Drop chance per datagram, in millionths.
    pub loss_ppm: u64,
    pub delay_ms: u64,
    pub jitter_ms: u64,
    pub seed: u64,
    pub secs: Option<u64>,
}

/// A client silent this long loses its session.
const IDLE: Duration = Duration::from_secs(30);

/// Where a held datagram goes: to the server from a client's session, or back to the client.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Dest {
    Server(SocketAddr),
    Client(SocketAddr),
}

/// Datagrams waiting for their delivery time; (due, order) keeps the order total, ties first in first out.
type Held = BinaryHeap<Reverse<(Instant, u64, Dest, Vec<u8>)>>;

struct Session {
    up: UdpSocket,
    heard: Instant,
}

#[derive(Default)]
struct Counts {
    sent: [u64; 2],
    dropped: [u64; 2],
}

pub fn run(a: &RelayArgs) -> std::io::Result<()> {
    let down = UdpSocket::bind(("0.0.0.0", a.port))?;
    down.set_nonblocking(true)?;
    let mut sessions: HashMap<SocketAddr, Session> = HashMap::new();
    let mut held: Held = BinaryHeap::new();
    let mut rng = a.seed;
    let mut order = 0u64;
    let mut counts = Counts::default();
    let start = Instant::now();
    let mut report = start + Duration::from_secs(10);
    let mut buf = [0u8; 2048];
    eprintln!("realm-loadtest relay: :{} -> {} loss={}ppm delay={}ms jitter={}ms seed={}", a.port, a.to, a.loss_ppm, a.delay_ms, a.jitter_ms, a.seed);
    let mut hold = |dest: Dest, b: &[u8], counts: &mut Counts, held: &mut Held| {
        let dir = matches!(dest, Dest::Client(_)) as usize;
        let r = realm_core::rng_next(&mut rng);
        if r % 1_000_000 < a.loss_ppm {
            counts.dropped[dir] += 1;
            return;
        }
        let jitter = ((r >> 20) % (2 * a.jitter_ms + 1)) as i64 - a.jitter_ms as i64;
        let due = Instant::now() + Duration::from_millis((a.delay_ms as i64 + jitter).max(0) as u64);
        order += 1;
        held.push(Reverse((due, order, dest, b.to_vec())));
    };
    loop {
        let now = Instant::now();
        if a.secs.is_some_and(|s| now >= start + Duration::from_secs(s)) {
            break;
        }
        while let Ok((n, from)) = down.recv_from(&mut buf) {
            if !sessions.contains_key(&from) {
                let up = UdpSocket::bind("0.0.0.0:0")?;
                up.connect(&a.to)?;
                up.set_nonblocking(true)?;
                sessions.insert(from, Session { up, heard: now });
            }
            if let Some(s) = sessions.get_mut(&from) {
                s.heard = now;
            }
            hold(Dest::Server(from), &buf[..n], &mut counts, &mut held);
        }
        for (&client, s) in &sessions {
            while let Ok(n) = s.up.recv(&mut buf) {
                hold(Dest::Client(client), &buf[..n], &mut counts, &mut held);
            }
        }
        while held.peek().is_some_and(|Reverse((due, ..))| *due <= now) {
            let Some(Reverse((_, _, dest, b))) = held.pop() else { break };
            match dest {
                Dest::Server(client) => {
                    if let Some(s) = sessions.get(&client) {
                        let _ = s.up.send(&b);
                        counts.sent[0] += 1;
                    }
                }
                Dest::Client(client) => {
                    let _ = down.send_to(&b, client);
                    counts.sent[1] += 1;
                }
            }
        }
        sessions.retain(|_, s| now - s.heard < IDLE);
        if now >= report {
            report += Duration::from_secs(10);
            print_counts(&counts, sessions.len());
        }
        std::thread::sleep(Duration::from_millis(1));
    }
    print_counts(&counts, sessions.len());
    Ok(())
}

fn print_counts(c: &Counts, sessions: usize) {
    let share = |d: u64, s: u64| if d + s == 0 { 0.0 } else { d as f64 * 100.0 / (d + s) as f64 };
    println!(
        "RELAY sessions={sessions} to_server sent={} dropped={} ({:.1}%) to_clients sent={} dropped={} ({:.1}%)",
        c.sent[0],
        c.dropped[0],
        share(c.dropped[0], c.sent[0]),
        c.sent[1],
        c.dropped[1],
        share(c.dropped[1], c.sent[1])
    );
}
