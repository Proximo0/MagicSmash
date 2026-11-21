//! realm-server: the crowd test's 20 Hz field over UDP (protocol A v0/v1 and B), with bots.
//! `--bench` runs the same loop with no sockets and encodes every protocol for every bot.

use realm_core::{Config, Field, Phase, FIELD, SUB};
use realm_server::bots::{join_spot, Bot};
use realm_server::lockstep::{pack, state_parts, Assembler, Join, Lockstep, TickRec, HASH_EVERY};
use realm_server::snap::{encode_v0, encode_v1};
use realm_server::stats::{dist, kb, Dist};
use realm_server::view::{build, Scratch, View};
use realm_server::*;
use std::collections::{HashMap, VecDeque};
use std::net::{SocketAddr, UdpSocket};
use std::time::{Duration, Instant};

#[derive(Clone, Debug)]
struct Args {
    port: u16,
    seed: u64,
    bots: u32,
    monsters: u32,
    rally_permille: u32,
    threads: usize,
    report: u32,
    ticks: Option<u32>,
    bench: bool,
    follow: bool,
    zoom: u8,
    warmup: u32,
}

fn parse_args() -> Args {
    let mut a = Args { port: DEFAULT_PORT, seed: 1, bots: 0, monsters: 20_000, rally_permille: 300, threads: 1, report: 5, ticks: None, bench: false, follow: false, zoom: 1, warmup: 100 };
    for arg in std::env::args().skip(1) {
        let (k, v) = arg.split_once('=').unwrap_or((arg.as_str(), ""));
        let num = |v: &str| v.parse::<u64>().unwrap_or_else(|_| die(&format!("bad value in {arg}")));
        match k {
            "--port" => a.port = num(v) as u16,
            "--seed" => a.seed = num(v),
            "--bots" => a.bots = num(v) as u32,
            "--monsters" => a.monsters = num(v) as u32,
            "--rally" => a.rally_permille = permille(v).unwrap_or_else(|| die("bad --rally")),
            "--threads" => a.threads = (num(v) as usize).max(1),
            "--report" => a.report = (num(v) as u32).max(1),
            "--ticks" => a.ticks = Some(num(v) as u32),
            "--bench" => a.bench = true,
            "--follow" => a.follow = true,
            "--zoom" => a.zoom = num(v) as u8,
            "--warmup" => a.warmup = num(v) as u32,
            "--help" | "-h" => {
                println!("realm-server [--port=7777] [--seed=1] [--bots=N] [--monsters=M] [--rally=0.3] [--threads=T] [--report=secs] [--ticks=N] [--bench] [--follow] [--zoom=1] [--warmup=100]");
                std::process::exit(0);
            }
            _ => die(&format!("unknown flag {arg}")),
        }
    }
    a
}

fn die(msg: &str) -> ! {
    eprintln!("realm-server: {msg}");
    std::process::exit(2);
}

/// "0.3" -> 300 without floats in the sim path.
fn permille(v: &str) -> Option<u32> {
    let (i, f) = v.split_once('.').unwrap_or((v, ""));
    let i: u32 = if i.is_empty() { 0 } else { i.parse().ok()? };
    let mut f3 = f.chars().chain("000".chars()).take(3).collect::<String>();
    if f3.is_empty() {
        f3 = "0".into();
    }
    Some((i * 1000 + f3.parse::<u32>().ok()?).min(1000))
}

// Timed columns, ms per tick.
const C_FLOW: usize = 0;
const C_MOVE: usize = 1;
const C_GRID: usize = 2;
const C_FIGHT: usize = 3;
const C_SPAWN: usize = 4;
const C_INPUT: usize = 5;
const C_BOTS: usize = 6;
const C_A0: usize = 7;
const C_A1: usize = 8;
const C_B: usize = 9;
const C_TOTAL: usize = 10;
const NCOL: usize = 11;
const COL_NAMES: [&str; NCOL] = ["flow", "move", "grid", "fight", "spawn", "input", "bots", "encA0", "encA1", "encB", "tick"];

/// One report window's numbers.
#[derive(Default)]
struct Window {
    ticks: Vec<[f64; NCOL]>,
    a0: Vec<f64>,
    a1: Vec<f64>,
    b: Vec<f64>,
    view_mon: Vec<f64>,
    view_ply: Vec<f64>,
    follow_ms: Vec<f64>,
    hash_ok: u64,
    hash_bad: u64,
}

struct Sim {
    args: Args,
    field: Field,
    ls: Lockstep,
    bots: Vec<Bot>,
    rng: u64,
    /// Encoded B records of the last ticks.
    history: VecDeque<(u32, Vec<u8>)>,
    tick_time: u16,
}

const HISTORY: usize = 64;

impl Sim {
    fn new(args: &Args) -> Sim {
        let field = Field::new(args.seed, Config { monsters: args.monsters, threads: args.threads });
        Sim { args: args.clone(), field, ls: Lockstep::default(), bots: Vec::new(), rng: args.seed ^ 0xB07, history: VecDeque::new(), tick_time: 0 }
    }

    /// Ids the next joins will get: the lowest free slots after this tick's leaves.
    fn predict_ids(&self, leaves: &[u16], n: usize) -> Vec<u16> {
        let ps = self.field.players();
        let mut taken: Vec<bool> = ps.iter().map(|p| p.present).collect();
        for &l in leaves {
            if let Some(t) = taken.get_mut(l as usize) {
                *t = false;
            }
        }
        let mut out = Vec::new();
        let mut i = 0;
        while out.len() < n {
            if i >= taken.len() {
                taken.push(false);
            }
            if !taken[i] {
                taken[i] = true;
                out.push(i as u16);
            }
            i += 1;
        }
        out
    }

    /// One tick: bots decide, the record is built and applied through the lockstep path, B is encoded.
    /// `joins` are (class, race, x, y); returns their ids.
    fn tick(&mut self, joins: &[(u8, u8, i32, i32)], leaves: &[u16], client_inputs: &[(u16, u8)], row: &mut [f64; NCOL]) -> Vec<u16> {
        let t0 = Instant::now();
        // Bots joining at the start.
        let mut joins = joins.to_vec();
        let mut new_bots = 0;
        if self.field.tick() == 0 {
            for k in 0..self.args.bots {
                let rally = (k as u64 * 1000 / self.args.bots.max(1) as u64) < self.args.rally_permille as u64;
                joins.push(join_spot(&mut self.rng, rally));
                new_bots += 1;
            }
            // Bots first so they take the low ids.
            joins.rotate_right(new_bots);
        }
        for b in &mut self.bots {
            b.decide(&self.field);
        }
        let ids = self.predict_ids(leaves, joins.len());
        for (k, &id) in ids.iter().take(new_bots).enumerate() {
            let rally = (k as u64 * 1000 / self.args.bots.max(1) as u64) < self.args.rally_permille as u64;
            self.bots.push(Bot::new(id, rally, self.args.seed));
        }
        let t_bots = Instant::now();
        let mut rec = TickRec { tick: self.field.tick() + 1, leaves: leaves.to_vec(), ..TickRec::default() };
        for (j, &id) in joins.iter().zip(&ids) {
            rec.joins.push(Join { id, class: j.0, race: j.1, x: j.2, y: j.3 });
        }
        let slots = self.field.players().len().max(ids.iter().map(|&i| i as usize + 1).max().unwrap_or(0));
        let mut want = vec![0u8; slots];
        for b in &self.bots {
            want[b.id as usize] = b.input;
        }
        for &(id, inp) in client_inputs {
            if let Some(w) = want.get_mut(id as usize) {
                *w = inp;
            }
        }
        for &l in leaves {
            if let Some(w) = want.get_mut(l as usize) {
                *w = 0;
            }
        }
        rec.changes = self.ls.changes(&rec, &want);
        let mut last = Instant::now();
        let mut marks = [0f64; 6];
        let ok = self.ls.apply(&mut self.field, &rec, |ph| {
            let now = Instant::now();
            let ms = (now - last).as_secs_f64() * 1000.0;
            last = now;
            let col = match ph {
                Phase::Input => C_INPUT,
                Phase::Flow => C_FLOW,
                Phase::Grid => C_GRID,
                Phase::Move => C_MOVE,
                Phase::Fight => C_FIGHT,
                Phase::Spawn => C_SPAWN,
            };
            marks[col.min(5)] += ms;
        });
        assert!(ok, "join ids or tick went wrong");
        row[..6].copy_from_slice(&marks);
        let step_ms = (Instant::now() - t_bots).as_secs_f64() * 1000.0;
        row[C_BOTS] = (t_bots - t0).as_secs_f64() * 1000.0;
        self.tick_time = (step_ms * 100.0).min(65535.0) as u16;
        let tb = Instant::now();
        if rec.tick % HASH_EVERY == 0 {
            rec.hash = Some(self.field.hash());
        }
        let mut bytes = Vec::new();
        rec.encode(&mut bytes);
        self.history.push_back((rec.tick, bytes));
        if self.history.len() > HISTORY {
            self.history.pop_front();
        }
        row[C_B] = (Instant::now() - tb).as_secs_f64() * 1000.0;
        ids.into_iter().skip(new_bots).collect()
    }

    /// B datagrams for a client that has applied up to `ack` (at most `HISTORY` ticks back).
    fn b_datagrams(&self, ack: u32, out: &mut Vec<Vec<u8>>) {
        let recs: Vec<(u32, &[u8])> = self.history.iter().filter(|(t, _)| *t > ack).map(|(t, b)| (*t, b.as_slice())).collect();
        pack(&recs, out);
    }
}

fn header() {
    println!(
        "{:>13} {:>3} {:>6} | {:>13} | {} | {:>13} {:>13} {:>13} | {:>9} {:>9} | {:>7} | {:>11} | {}",
        "players x mon", "thr", "tick",
        "tick ms m/p99",
        COL_NAMES[..C_TOTAL].iter().map(|n| format!("{n:>11}")).collect::<Vec<_>>().join(" "),
        "A0 B/s m/p99", "A1 B/s m/p99", "B B/s m/p99",
        "mon view", "ply view", "join B", "follow ms", "hash"
    );
}

fn md(d: Dist) -> String {
    format!("{:.2}/{:.2}", d.mean, d.p99)
}

fn report(sim: &Sim, w: &Window, join_bytes: usize) {
    let col = |c: usize| dist(&w.ticks.iter().map(|r| r[c]).collect::<Vec<_>>());
    let bw = |v: &[f64]| {
        let d = dist(v);
        if d.n == 0 { "-".to_string() } else { format!("{}/{}", kb(d.mean), kb(d.p99)) }
    };
    let vm = dist(&w.view_mon);
    let vp = dist(&w.view_ply);
    let fl = dist(&w.follow_ms);
    let f = &sim.field;
    println!(
        "{:>13} {:>3} {:>6} | {:>13} | {} | {:>13} {:>13} {:>13} | {:>9} {:>9} | {:>7} | {:>11} | {}",
        format!("{}x{}", f.player_count(), f.monster_count()),
        sim.args.threads,
        f.tick(),
        md(col(C_TOTAL)),
        (0..C_TOTAL).map(|c| format!("{:>11}", md(col(c)))).collect::<Vec<_>>().join(" "),
        bw(&w.a0),
        bw(&w.a1),
        bw(&w.b),
        if vm.n == 0 { "-".into() } else { format!("{:.0}/{:.0}", vm.mean, vm.p99) },
        if vp.n == 0 { "-".into() } else { format!("{:.0}/{:.0}", vp.mean, vp.p99) },
        kb(join_bytes as f64),
        if fl.n == 0 { "-".into() } else { md(fl) },
        if w.hash_ok + w.hash_bad == 0 { "-".into() } else if w.hash_bad == 0 { format!("ok {}", w.hash_ok) } else { format!("BAD {}/{}", w.hash_bad, w.hash_ok + w.hash_bad) }
    );
}

/// Per-bot measuring state in the bench.
#[derive(Default)]
struct BenchClient {
    /// The last two snapshots: v1 is coded against the older one (the client acknowledges a snapshot
    /// about 200 ms after it was sent).
    ring: [View; 2],
    a0: u64,
    a1: u64,
    view_mon: u32,
    view_ply: u32,
    parts: Vec<Vec<u8>>,
    scratch: Scratch,
}

fn bench(args: &Args) {
    let mut sim = Sim::new(args);
    let mut clients: Vec<BenchClient> = Vec::new();
    let mut w = Window::default();
    let mut follower: Option<(Field, Lockstep, Assembler)> = None;
    let mut join_bytes = 0;
    let mut b_dgrams = Vec::new();
    let mut b_sec = 0u64;
    let total = args.ticks.unwrap_or(20 * 30);
    let t = args.threads;
    header();
    let wall = Instant::now();
    for _ in 0..total {
        let mut row = [0f64; NCOL];
        let t0 = Instant::now();
        sim.tick(&[], &[], &[], &mut row);
        let tick = sim.field.tick();
        if clients.len() < sim.bots.len() {
            clients.resize_with(sim.bots.len(), BenchClient::default);
        }
        // Protocol A at 10 Hz for every bot, split over the threads.
        if tick % 2 == 0 {
            let chunk = clients.len().div_ceil(t).max(1);
            let field = &sim.field;
            let bots = &sim.bots;
            let (zoom, tt) = (args.zoom, sim.tick_time);
            let ta = Instant::now();
            std::thread::scope(|s| {
                for (k, cs) in clients.chunks_mut(chunk).enumerate() {
                    s.spawn(move || {
                        for (j, c) in cs.iter_mut().enumerate() {
                            let id = bots[k * chunk + j].id;
                            let [old, newer] = &mut c.ring;
                            std::mem::swap(old, newer);
                            build(field, id, zoom, tt, &mut c.scratch, newer);
                            encode_v0(newer, &mut c.parts);
                            c.a0 += c.parts.iter().map(|p| p.len() as u64).sum::<u64>();
                            c.view_mon = newer.monsters.len() as u32;
                            c.view_ply = (newer.players.len() + newer.crowd.len()) as u32;
                        }
                    });
                }
            });
            let tb = Instant::now();
            std::thread::scope(|s| {
                for cs in clients.chunks_mut(chunk) {
                    s.spawn(move || {
                        for c in cs.iter_mut() {
                            let base = (c.ring[0].tick != 0).then_some(&c.ring[0]);
                            encode_v1(&c.ring[1], base, &mut c.parts);
                            c.a1 += c.parts.iter().map(|p| p.len() as u64).sum::<u64>();
                        }
                    });
                }
            });
            row[C_A0] = (tb - ta).as_secs_f64() * 1000.0;
            row[C_A1] = tb.elapsed().as_secs_f64() * 1000.0;
            if tick > args.warmup {
                for c in &clients {
                    w.view_mon.push(c.view_mon as f64);
                    w.view_ply.push(c.view_ply as f64);
                }
            }
        }
        // Protocol B: each tick's datagrams carry this tick and the one before (an ack one tick behind).
        let tb = Instant::now();
        sim.b_datagrams(tick.saturating_sub(2), &mut b_dgrams);
        row[C_B] += tb.elapsed().as_secs_f64() * 1000.0;
        b_sec += b_dgrams.iter().map(|d| d.len() as u64).sum::<u64>();
        row[C_TOTAL] = t0.elapsed().as_secs_f64() * 1000.0;
        // Per-second byte rates per client.
        if tick % 20 == 0 {
            if tick > args.warmup {
                for c in &clients {
                    w.a0.push(c.a0 as f64);
                    w.a1.push(c.a1 as f64);
                }
                w.b.push(b_sec as f64);
            }
            for c in &mut clients {
                c.a0 = 0;
                c.a1 = 0;
            }
            b_sec = 0;
        }
        // The in-process follower: joins at the end of warmup, then decodes and applies the B stream.
        if args.follow {
            if tick == args.warmup.max(1) {
                let st = sim.ls.state_bytes(&sim.field);
                join_bytes = st.len();
                let (f, l) = Lockstep::from_state(&st, 1).expect("state");
                follower = Some((f, l, Assembler::default()));
            } else if let Some((f, l, asm)) = follower.as_mut() {
                let tf = Instant::now();
                for d in &b_dgrams {
                    asm.take(d, f.tick()).expect("B datagram");
                }
                while let Some(bytes) = asm.next(f.tick() + 1) {
                    let rec = TickRec::decode(f.tick() + 1, &bytes).expect("B record");
                    assert!(l.apply(f, &rec, |_| {}), "follower join ids");
                    if let Some(h) = rec.hash {
                        if f.hash() == h { w.hash_ok += 1 } else { w.hash_bad += 1 }
                    }
                }
                w.follow_ms.push(tf.elapsed().as_secs_f64() * 1000.0);
            }
        }
        if tick > args.warmup {
            w.ticks.push(row);
        }
        if tick % (args.report * 20) == 0 && !w.ticks.is_empty() {
            if join_bytes == 0 || !args.follow {
                join_bytes = sim.ls.state_bytes(&sim.field).len();
            }
            report(&sim, &w, join_bytes);
            w = Window::default();
        }
    }
    if !w.ticks.is_empty() {
        report(&sim, &w, sim.ls.state_bytes(&sim.field).len());
    }
    let (kills, spawns, deaths) = sim.field.counters();
    println!(
        "BENCH {}x{} threads={} ticks={} wall={:.1}s kills={kills} spawns={spawns} deaths={deaths} recycled={} hash={:016x}",
        sim.field.player_count(),
        sim.field.monster_count(),
        t,
        sim.field.tick(),
        wall.elapsed().as_secs_f64(),
        sim.field.recycled(),
        sim.field.hash()
    );
}

struct Client {
    proto: u32,
    id: Option<u16>,
    input: u8,
    zoom: u8,
    ack: u32,
    heard: Instant,
    /// A v1 client's recent snapshots, for its acknowledged base.
    ring: VecDeque<View>,
    /// B: the tick of the state last sent, and whether the follower has acknowledged past it.
    state_tick: Option<u32>,
    /// B: the state being sent, a few parts a tick, and the next part.
    state: Vec<Vec<u8>>,
    state_next: usize,
    bytes: u64,
    view_mon: u32,
    view_ply: u32,
}

const STATE_PARTS_PER_TICK: usize = 48;
const TIMEOUT: Duration = Duration::from_secs(5);

fn serve(args: &Args) {
    let sock = UdpSocket::bind(("0.0.0.0", args.port)).unwrap_or_else(|e| die(&format!("bind {}: {e}", args.port)));
    sock.set_nonblocking(true).expect("nonblocking");
    eprintln!("realm-server: udp {} seed={} bots={} monsters={} rally={}/1000 threads={}", args.port, args.seed, args.bots, args.monsters, args.rally_permille, args.threads);
    let mut sim = Sim::new(args);
    let mut clients: HashMap<SocketAddr, Client> = HashMap::new();
    let mut w = Window::default();
    let mut scratch = Scratch::default();
    let mut out = Vec::new();
    let mut buf = [0u8; 2048];
    let mut rng = args.seed ^ 0xC11E;
    let start = Instant::now();
    let period = Duration::from_millis(50);
    header();
    let mut n = 0u64;
    loop {
        if args.ticks.is_some_and(|t| sim.field.tick() >= t) {
            break;
        }
        let due = start + period * n as u32;
        let now = Instant::now();
        if due > now {
            std::thread::sleep(due - now);
        }
        n += 1;
        // Read everything that arrived.
        let mut joins = Vec::new();
        let mut join_addrs = Vec::new();
        let mut leaves = Vec::new();
        while let Ok((len, from)) = sock.recv_from(&mut buf) {
            let mut r = Rd::new(&buf[..len]);
            match r.u8() {
                Some(MSG_HELLO) => {
                    let (Some(proto), Some(class), Some(race)) = (r.u32(), r.u8(), r.u8()) else { continue };
                    if let Some(c) = clients.get(&from) {
                        // A repeated HELLO: the WELCOME was lost.
                        if let Some(id) = c.id {
                            let _ = sock.send_to(&welcome(id as u32, sim.field.tick()), from);
                        }
                        continue;
                    }
                    let c = Client { proto, id: None, input: 0, zoom: 1, ack: 0, heard: Instant::now(), ring: VecDeque::new(), state_tick: None, state: Vec::new(), state_next: 0, bytes: 0, view_mon: 0, view_ply: 0 };
                    if proto != PROTO_B {
                        let rr = realm_core::rng_next(&mut rng);
                        let x = FIELD / 2 + ((rr % 400) as i32 - 200) * SUB;
                        let y = FIELD / 2 + (((rr >> 20) % 400) as i32 - 200) * SUB;
                        joins.push((class, race, x, y));
                        join_addrs.push(from);
                    }
                    clients.insert(from, c);
                }
                Some(MSG_INPUT) => {
                    if let (Some(c), Some(ack), Some(mv), Some(zoom)) = (clients.get_mut(&from), r.u32(), r.u8(), r.u8()) {
                        c.ack = c.ack.max(ack);
                        c.input = mv & 0x8F;
                        c.zoom = zoom;
                        c.heard = Instant::now();
                    }
                }
                Some(MSG_BYE) => {
                    if let Some(c) = clients.remove(&from) {
                        leaves.extend(c.id);
                    }
                }
                _ => {}
            }
        }
        clients.retain(|_, c| {
            let keep = c.heard.elapsed() < TIMEOUT;
            if !keep {
                leaves.extend(c.id);
            }
            keep
        });
        let inputs: Vec<(u16, u8)> = clients.values().filter_map(|c| c.id.map(|id| (id, c.input))).collect();
        let mut row = [0f64; NCOL];
        let t0 = Instant::now();
        let ids = sim.tick(&joins, &leaves, &inputs, &mut row);
        let tick = sim.field.tick();
        for (addr, id) in join_addrs.iter().zip(ids) {
            if let Some(c) = clients.get_mut(addr) {
                c.id = Some(id);
                let _ = sock.send_to(&welcome(id as u32, tick), addr);
            }
        }
        // Snapshots at 10 Hz, B every tick.
        for (addr, c) in clients.iter_mut() {
            match (c.proto, c.id) {
                (PROTO_B, _) => {
                    let tc = Instant::now();
                    let behind = c.state_tick.is_some_and(|st| c.ack >= st && c.ack + (HISTORY as u32) < tick);
                    let stale = c.state_tick.is_some_and(|st| c.ack < st && tick >= st + HISTORY as u32 - 8);
                    if c.state_tick.is_none() || behind || stale {
                        c.state = state_parts(tick, &sim.ls.state_bytes(&sim.field));
                        c.state_tick = Some(tick);
                        c.state_next = 0;
                        let _ = sock.send_to(&welcome(u32::MAX, tick), addr);
                    }
                    let st = c.state_tick.unwrap_or(0);
                    if c.ack < st {
                        // Still joining: a few state parts a tick (a burst would overflow the client's buffer),
                        // over and over until acknowledged.
                        for _ in 0..STATE_PARTS_PER_TICK {
                            let p = &c.state[c.state_next % c.state.len()];
                            c.state_next += 1;
                            c.bytes += p.len() as u64;
                            let _ = sock.send_to(p, addr);
                        }
                    }
                    sim.b_datagrams(c.ack.max(st), &mut out);
                    for d in &out {
                        c.bytes += d.len() as u64;
                        let _ = sock.send_to(d, addr);
                    }
                    row[C_B] += tc.elapsed().as_secs_f64() * 1000.0;
                }
                (_, Some(id)) if tick % 2 == 0 => {
                    let tc = Instant::now();
                    let mut v = View::default();
                    build(&sim.field, id, c.zoom, sim.tick_time, &mut scratch, &mut v);
                    if c.proto == PROTO_A1 {
                        let base = c.ring.iter().find(|b| b.tick == c.ack);
                        encode_v1(&v, base, &mut out);
                    } else {
                        encode_v0(&v, &mut out);
                    }
                    for d in &out {
                        c.bytes += d.len() as u64;
                        let _ = sock.send_to(d, addr);
                    }
                    c.view_mon = v.monsters.len() as u32;
                    c.view_ply = (v.players.len() + v.crowd.len()) as u32;
                    if c.proto == PROTO_A1 {
                        c.ring.push_back(v);
                        while c.ring.len() > 32 {
                            c.ring.pop_front();
                        }
                    }
                    row[if c.proto == PROTO_A1 { C_A1 } else { C_A0 }] += tc.elapsed().as_secs_f64() * 1000.0;
                }
                _ => {}
            }
        }
        row[C_TOTAL] = t0.elapsed().as_secs_f64() * 1000.0;
        w.ticks.push(row);
        if tick % 20 == 0 {
            for c in clients.values_mut() {
                let v = c.bytes as f64;
                match c.proto {
                    PROTO_A0 => w.a0.push(v),
                    PROTO_A1 => w.a1.push(v),
                    _ => w.b.push(v),
                }
                if c.proto != PROTO_B && c.id.is_some() {
                    w.view_mon.push(c.view_mon as f64);
                    w.view_ply.push(c.view_ply as f64);
                }
                c.bytes = 0;
            }
        }
        if tick % (args.report * 20) == 0 {
            report(&sim, &w, sim.ls.state_bytes(&sim.field).len());
            w = Window::default();
        }
    }
}

fn main() {
    let args = parse_args();
    if args.bench {
        bench(&args);
    } else {
        serve(&args);
    }
}
