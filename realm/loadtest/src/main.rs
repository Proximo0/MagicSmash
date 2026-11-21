//! realm-loadtest: real UDP clients against realm-server, and a lossy relay.
//! - `--clients=N --proto=a0|a1`: players that send inputs 20 times a second, reassemble and decode every
//!   snapshot, and count bytes.
//! - `--follow`: a protocol B follower that joins from the full state, applies the stream to its own
//!   `Field` and compares every hash.
//! - `--players=N`: protocol B lockstep players (HELLO proto 4): each joins the field, sends inputs that
//!   enter the tick stream, follows the whole field, checks every hash and predicts its own hero.
//! - `--relay=PORT --to=HOST:PORT [--loss=0.05 --delay-ms=80 --jitter-ms=20 --seed=1 --secs=N]`: no clients;
//!   a relay that drops and delays datagrams both ways (`relay.rs`).

mod relay;

use realm_server::client::LockstepClient;
use realm_server::snap::{decode, peek};
use realm_server::stats::{dist, kb};
use realm_server::view::{box_size, View};
use realm_server::*;
use std::collections::{BTreeMap, VecDeque};
use std::net::UdpSocket;
use std::time::{Duration, Instant};

struct Args {
    server: String,
    clients: u32,
    proto: u32,
    follow: bool,
    players: u32,
    secs: u32,
    threads: usize,
    seed: u64,
    zoom: u8,
    relay: Option<u16>,
    to: String,
    loss_ppm: u64,
    delay_ms: u64,
    jitter_ms: u64,
}

fn die(msg: &str) -> ! {
    eprintln!("realm-loadtest: {msg}");
    std::process::exit(2);
}

fn parse() -> Args {
    let mut a = Args {
        server: format!("127.0.0.1:{DEFAULT_PORT}"),
        clients: 0,
        proto: PROTO_A0,
        follow: false,
        players: 0,
        secs: 10,
        threads: 1,
        seed: 1,
        zoom: 1,
        relay: None,
        to: format!("127.0.0.1:{DEFAULT_PORT}"),
        loss_ppm: 50_000,
        delay_ms: 80,
        jitter_ms: 20,
    };
    let mut secs_given = false;
    for arg in std::env::args().skip(1) {
        let (k, v) = arg.split_once('=').unwrap_or((arg.as_str(), ""));
        let num = |v: &str| v.parse::<u64>().unwrap_or_else(|_| die(&format!("bad value in {arg}")));
        match k {
            "--server" => a.server = v.to_string(),
            "--clients" => a.clients = num(v) as u32,
            "--proto" => {
                a.proto = match v {
                    "a0" => PROTO_A0,
                    "a1" => PROTO_A1,
                    _ => die("--proto is a0 or a1"),
                }
            }
            "--follow" => a.follow = true,
            "--players" => a.players = num(v) as u32,
            "--secs" => {
                a.secs = num(v) as u32;
                secs_given = true;
            }
            "--relay" => a.relay = Some(num(v) as u16),
            "--to" => a.to = v.to_string(),
            "--loss" => {
                let share = v.parse::<f64>().ok().filter(|l| (0.0..=1.0).contains(l)).unwrap_or_else(|| die("--loss is a share from 0 to 1"));
                a.loss_ppm = (share * 1_000_000.0).round() as u64;
            }
            "--delay-ms" => a.delay_ms = num(v),
            "--jitter-ms" => a.jitter_ms = num(v),
            "--threads" => a.threads = (num(v) as usize).max(1),
            "--seed" => a.seed = num(v),
            "--zoom" => a.zoom = num(v) as u8,
            "--help" | "-h" => {
                println!("realm-loadtest [--server=127.0.0.1:7777] [--clients=N] [--proto=a0|a1] [--follow] [--players=N] [--secs=10] [--threads=1] [--zoom=1]");
                println!("realm-loadtest --relay=PORT --to=HOST:PORT [--loss=0.05] [--delay-ms=80] [--jitter-ms=20] [--seed=1] [--secs=N]");
                std::process::exit(0);
            }
            _ => die(&format!("unknown flag {arg}")),
        }
    }
    if a.relay.is_some() {
        // A relay runs until stopped unless given --secs.
        if !secs_given {
            a.secs = 0;
        }
    } else if a.clients == 0 && !a.follow && a.players == 0 {
        die("give --clients=N, --follow and/or --players=N, or --relay=PORT");
    }
    a
}

fn socket(server: &str) -> UdpSocket {
    let s = UdpSocket::bind("0.0.0.0:0").expect("bind");
    s.connect(server).unwrap_or_else(|e| die(&format!("connect {server}: {e}")));
    s.set_nonblocking(true).expect("nonblocking");
    s
}

struct Player {
    sock: UdpSocket,
    id: Option<u32>,
    mv: u8,
    ack: u32,
    parts: BTreeMap<u32, Vec<Vec<u8>>>,
    ring: VecDeque<View>,
    bytes: u64,
}

#[derive(Default)]
struct Counts {
    ok: u64,
    bad: u64,
    incomplete: u64,
    mon: Vec<f64>,
    ply: Vec<f64>,
    rates: Vec<f64>,
    first_bad: Option<String>,
}

/// Checks a decoded view against what the contract promises.
fn check(v: &View, zoom: u8) -> Result<(), String> {
    let (w, h) = box_size(zoom);
    if v.monsters.len() > 1500 || v.players.len() > 200 || v.crowd.len() > 1000 {
        return Err("list too long".into());
    }
    if !v.monsters.windows(2).all(|p| p[0].id < p[1].id) {
        return Err("monsters not by id".into());
    }
    let inside = |x: u16, y: u16| (x as i32) >= v.ox && (x as i32) < v.ox + w && (y as i32) >= v.oy && (y as i32) < v.oy + h;
    if !v.monsters.iter().all(|m| inside(m.x, m.y)) || !v.players.iter().all(|p| inside(p.x, p.y)) {
        return Err("outside the interest box".into());
    }
    if v.me_x as i32 >= w || v.me_y as i32 >= h {
        return Err("me outside the box".into());
    }
    Ok(())
}

/// A protocol B client on its own socket.
struct BClient {
    sock: UdpSocket,
    c: LockstepClient,
    mv: u8,
    bytes: u64,
    bytes_out: u64,
    rates: Vec<f64>,
    joined_secs: u32,
}

impl BClient {
    fn new(server: &str, c: LockstepClient) -> BClient {
        BClient { sock: socket(server), c, mv: 0, bytes: 0, bytes_out: 0, rates: Vec::new(), joined_secs: 0 }
    }
}

fn main() {
    let a = parse();
    if let Some(port) = a.relay {
        let r = relay::RelayArgs { port, to: a.to.clone(), loss_ppm: a.loss_ppm, delay_ms: a.delay_ms, jitter_ms: a.jitter_ms, seed: a.seed, secs: (a.secs > 0).then_some(a.secs as u64) };
        if let Err(e) = relay::run(&r) {
            die(&format!("relay: {e}"));
        }
        return;
    }
    let mut players: Vec<Player> = (0..a.clients)
        .map(|_| Player { sock: socket(&a.server), id: None, mv: 0, ack: 0, parts: BTreeMap::new(), ring: VecDeque::new(), bytes: 0 })
        .collect();
    let mut counts = Counts::default();
    let mut rng = a.seed;
    for (k, p) in players.iter().enumerate() {
        let _ = p.sock.send(&hello(a.proto, (k % 5) as u8, (k % 4) as u8));
    }
    // Protocol B: the follower (no player) and the lockstep players, each a full field of its own.
    let mut bs: Vec<BClient> = Vec::new();
    if a.follow {
        bs.push(BClient::new(&a.server, LockstepClient::new(PROTO_B, 0, 0, a.threads)));
    }
    for k in 0..a.players {
        bs.push(BClient::new(&a.server, LockstepClient::new(PROTO_BP, (k % 5) as u8, ((k + 1) % 4) as u8, a.threads)));
    }
    for b in &bs {
        let _ = b.sock.send(&b.c.hello());
    }

    let start = Instant::now();
    let end = start + Duration::from_secs(a.secs as u64);
    let mut next_input = start;
    let mut input_round = 0u64;
    let mut next_second = start + Duration::from_secs(1);
    let mut buf = [0u8; 2048];
    while Instant::now() < end {
        let now = Instant::now();
        if now >= next_input {
            next_input += Duration::from_millis(50);
            input_round += 1;
            let hello_again = input_round % 20 == 0;
            for (k, p) in players.iter_mut().enumerate() {
                if p.id.is_none() && hello_again {
                    let _ = p.sock.send(&hello(a.proto, (k % 5) as u8, (k % 4) as u8));
                }
                let r = realm_core::rng_next(&mut rng);
                if r % 40 == 0 {
                    p.mv = ((r >> 8) % 9) as u8;
                }
                let _ = p.sock.send(&input(p.ack, p.mv, a.zoom));
            }
            for b in bs.iter_mut() {
                if !b.c.welcomed() && hello_again {
                    let _ = b.sock.send(&b.c.hello());
                }
                let r = realm_core::rng_next(&mut rng);
                if r % 40 == 0 {
                    b.mv = ((r >> 8) % 9) as u8;
                }
                let d = b.c.input(b.mv);
                b.bytes_out += d.len() as u64;
                let _ = b.sock.send(&d);
            }
        }
        if now >= next_second {
            next_second += Duration::from_secs(1);
            if now > start + Duration::from_secs(2) {
                for p in &players {
                    counts.rates.push(p.bytes as f64);
                }
                // Whole seconds of following only: the second with the join download is left out.
                for b in bs.iter_mut().filter(|b| b.c.field().is_some()) {
                    b.joined_secs += 1;
                    if b.joined_secs > 1 {
                        b.rates.push(b.bytes as f64);
                    }
                }
            }
            for p in players.iter_mut() {
                p.bytes = 0;
            }
            for b in bs.iter_mut() {
                b.bytes = 0;
            }
        }
        for p in players.iter_mut() {
            while let Ok(n) = p.sock.recv(&mut buf) {
                p.bytes += n as u64;
                let b = &buf[..n];
                match b[0] {
                    MSG_WELCOME => p.id = Rd::new(&b[1..]).u32(),
                    MSG_SNAPSHOT | MSG_SNAPSHOT_V1 => {
                        let Some((_, tick, _, parts, base_tick)) = peek(b) else {
                            counts.bad += 1;
                            continue;
                        };
                        let e = p.parts.entry(tick).or_default();
                        e.push(b.to_vec());
                        if e.len() < parts as usize {
                            continue;
                        }
                        let all = p.parts.remove(&tick).unwrap_or_default();
                        // Older unfinished snapshots are lost.
                        while p.parts.first_key_value().is_some_and(|(&t, _)| t < tick) {
                            p.parts.pop_first();
                            counts.incomplete += 1;
                        }
                        let base = p.ring.iter().find(|v| v.tick == base_tick);
                        match decode(&all, base).and_then(|v| check(&v, a.zoom).map(|_| v)) {
                            Ok(v) => {
                                counts.ok += 1;
                                counts.mon.push(v.monsters.len() as f64);
                                counts.ply.push((v.players.len() + v.crowd.len()) as f64);
                                p.ack = p.ack.max(v.tick);
                                p.ring.push_back(v);
                                while p.ring.len() > 16 {
                                    p.ring.pop_front();
                                }
                            }
                            Err(e) => {
                                counts.bad += 1;
                                counts.first_bad.get_or_insert(e);
                            }
                        }
                    }
                    _ => counts.bad += 1,
                }
            }
        }
        for b in bs.iter_mut() {
            while let Ok(n) = b.sock.recv(&mut buf) {
                b.bytes += n as u64;
                b.c.receive(&buf[..n]);
            }
            b.c.apply();
        }
        std::thread::sleep(Duration::from_millis(2));
    }
    for p in &players {
        let _ = p.sock.send(&[MSG_BYE]);
    }
    for b in &bs {
        let _ = b.sock.send(&[MSG_BYE]);
    }
    if a.clients > 0 {
        let r = dist(&counts.rates);
        let m = dist(&counts.mon);
        let pl = dist(&counts.ply);
        let joined = players.iter().filter(|p| p.id.is_some()).count();
        println!(
            "LOADTEST {} clients={} joined={joined} secs={} snapshots ok={} bad={} incomplete={} bytes/s per client mean={} p99={} view monsters {:.0}/{:.0} players {:.0}/{:.0}{}",
            if a.proto == PROTO_A1 { "a1" } else { "a0" },
            a.clients,
            a.secs,
            counts.ok,
            counts.bad,
            counts.incomplete,
            kb(r.mean),
            kb(r.p99),
            m.mean,
            m.p99,
            pl.mean,
            pl.p99,
            counts.first_bad.map(|e| format!(" first_bad=\"{e}\"")).unwrap_or_default()
        );
    }
    for (k, b) in bs.iter().enumerate() {
        let st = &b.c.stats;
        let r = dist(&b.rates);
        let cpu = st.sim.as_secs_f64() * 1000.0 / st.ticks_applied.max(1) as f64;
        let p = b.c.predictor();
        let who = match b.c.hero() {
            Some(id) => format!("PLAYER id={id} mispredicts={}/{}", p.mispredicts, p.confirms),
            None if k == 0 && a.follow => "FOLLOW".to_string(),
            None => "PLAYER id=none".to_string(),
        };
        println!(
            "{who} joined_tick={} join_bytes={} applied_to={} ticks={} bytes/s in mean={} p99={} out={} cpu/tick ms={cpu:.2} stall_ms max={} threads={} hashes ok={} bad={} bad_datagrams={}",
            st.join_tick,
            st.join_bytes,
            b.c.tick(),
            st.ticks_applied,
            kb(r.mean),
            kb(r.p99),
            kb(b.bytes_out as f64 / a.secs.max(1) as f64),
            st.stall_max.as_millis(),
            a.threads,
            st.hash_ok,
            st.hash_bad,
            st.bad_datagrams
        );
    }
    let b_failed = bs.iter().any(|b| b.c.stats.hash_bad > 0 || b.c.stats.hash_ok == 0 || b.c.stats.bad_datagrams > 0);
    let failed = counts.bad > 0 || b_failed || (a.clients > 0 && counts.ok == 0);
    std::process::exit(if failed { 1 } else { 0 });
}
