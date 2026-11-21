//! realm-loadtest: real UDP clients against realm-server.
//! - `--clients=N --proto=a0|a1`: players that send inputs 20 times a second, reassemble and decode every
//!   snapshot, and count bytes.
//! - `--follow`: a protocol B follower that joins from the full state, applies the stream to its own
//!   `Field` and compares every hash.

use realm_core::Field;
use realm_server::lockstep::{Assembler, Lockstep, TickRec};
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
    secs: u32,
    threads: usize,
    seed: u64,
    zoom: u8,
}

fn die(msg: &str) -> ! {
    eprintln!("realm-loadtest: {msg}");
    std::process::exit(2);
}

fn parse() -> Args {
    let mut a = Args { server: format!("127.0.0.1:{DEFAULT_PORT}"), clients: 0, proto: PROTO_A0, follow: false, secs: 10, threads: 1, seed: 1, zoom: 1 };
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
            "--secs" => a.secs = num(v) as u32,
            "--threads" => a.threads = (num(v) as usize).max(1),
            "--seed" => a.seed = num(v),
            "--zoom" => a.zoom = num(v) as u8,
            "--help" | "-h" => {
                println!("realm-loadtest [--server=127.0.0.1:7777] [--clients=N] [--proto=a0|a1] [--follow] [--secs=10] [--threads=1] [--zoom=1]");
                std::process::exit(0);
            }
            _ => die(&format!("unknown flag {arg}")),
        }
    }
    if a.clients == 0 && !a.follow {
        die("give --clients=N and/or --follow");
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

fn main() {
    let a = parse();
    let mut players: Vec<Player> = (0..a.clients)
        .map(|_| Player { sock: socket(&a.server), id: None, mv: 0, ack: 0, parts: BTreeMap::new(), ring: VecDeque::new(), bytes: 0 })
        .collect();
    let mut counts = Counts::default();
    let mut rng = a.seed;
    for (k, p) in players.iter().enumerate() {
        let _ = p.sock.send(&hello(a.proto, (k % 5) as u8, (k % 4) as u8));
    }
    // The follower.
    let fsock = a.follow.then(|| socket(&a.server));
    if let Some(s) = &fsock {
        let _ = s.send(&hello(PROTO_B, 0, 0));
    }
    let mut state: BTreeMap<u16, Vec<u8>> = BTreeMap::new();
    let mut state_tick = 0u32;
    let mut follower: Option<(Field, Lockstep)> = None;
    let mut asm = Assembler::default();
    let mut fbytes = 0u64;
    let mut frates = Vec::new();
    let mut fcpu = Vec::new();
    let (mut hash_ok, mut hash_bad) = (0u64, 0u64);
    let mut join_size = 0usize;
    let mut join_tick = 0u32;

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
            if let (Some(s), Some((f, _))) = (&fsock, &follower) {
                let _ = s.send(&input(f.tick(), 0, 1));
            } else if let Some(s) = &fsock {
                if hello_again && state_tick == 0 {
                    let _ = s.send(&hello(PROTO_B, 0, 0));
                }
                let _ = s.send(&input(0, 0, 1));
            }
        }
        if now >= next_second {
            next_second += Duration::from_secs(1);
            if now > start + Duration::from_secs(2) {
                for p in &players {
                    counts.rates.push(p.bytes as f64);
                }
                if follower.is_some() {
                    frates.push(fbytes as f64);
                }
            }
            for p in players.iter_mut() {
                p.bytes = 0;
            }
            fbytes = 0;
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
        if let Some(s) = &fsock {
            while let Ok(n) = s.recv(&mut buf) {
                fbytes += n as u64;
                let b = &buf[..n];
                match b[0] {
                    MSG_STATE if follower.is_none() => {
                        let mut r = Rd::new(&b[1..]);
                        let (Some(tick), Some(k), Some(nparts)) = (r.u32(), r.u16(), r.u16()) else { continue };
                        if tick != state_tick {
                            state.clear();
                            state_tick = tick;
                        }
                        state.insert(k, b[9..].to_vec());
                        if state.len() == nparts as usize {
                            let all: Vec<u8> = state.values().flatten().copied().collect();
                            join_size = all.len();
                            join_tick = tick;
                            follower = Some(Lockstep::from_state(&all, a.threads).unwrap_or_else(|| die("state does not parse")));
                        }
                    }
                    MSG_TICKS => {
                        let applied = follower.as_ref().map_or(state_tick, |(f, _)| f.tick());
                        asm.take(b, applied);
                    }
                    _ => {}
                }
            }
            if let Some((f, l)) = follower.as_mut() {
                while let Some(bytes) = asm.next(f.tick() + 1) {
                    let t0 = Instant::now();
                    let Some(rec) = TickRec::decode(f.tick() + 1, &bytes) else { die("bad tick record") };
                    if !l.apply(f, &rec, |_| {}) {
                        hash_bad += 1;
                    }
                    fcpu.push(t0.elapsed().as_secs_f64() * 1000.0);
                    if let Some(h) = rec.hash {
                        if f.hash() == h { hash_ok += 1 } else { hash_bad += 1 }
                    }
                }
            }
        }
        std::thread::sleep(Duration::from_millis(2));
    }
    for p in &players {
        let _ = p.sock.send(&[MSG_BYE]);
    }
    if let Some(s) = &fsock {
        let _ = s.send(&[MSG_BYE]);
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
    if a.follow {
        let r = dist(&frates);
        let c = dist(&fcpu);
        let applied = follower.as_ref().map_or(0, |(f, _)| f.tick());
        println!(
            "FOLLOW joined_tick={join_tick} join_bytes={join_size} applied_to={applied} ticks={} bytes/s mean={} p99={} cpu/tick ms mean={:.2} p99={:.2} threads={} hashes ok={hash_ok} bad={hash_bad}",
            c.n,
            kb(r.mean),
            kb(r.p99),
            c.mean,
            c.p99,
            a.threads
        );
    }
    let failed = counts.bad > 0 || hash_bad > 0 || (a.follow && hash_ok == 0) || (a.clients > 0 && counts.ok == 0);
    std::process::exit(if failed { 1 } else { 0 });
}
