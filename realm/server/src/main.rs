//! realm-server: the crowd test's 20 Hz field over UDP (protocol A v0/v1 and B), with bots.
//! `--bench` runs the same loop with no sockets and encodes every protocol for every bot.

use realm_core::Field;
use realm_server::host::{run_here, HostOpts};
use realm_server::lockstep::{Assembler, Lockstep, TickRec};
use realm_server::report::{header, report, Window};
use realm_server::sim::*;
use realm_server::snap::{encode_v0, encode_v1};
use realm_server::view::{build, Scratch, View};
use realm_server::*;
use std::time::Instant;

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
    field: u8,
    level: u8,
}

impl Args {
    fn sim_opts(&self) -> SimOpts {
        SimOpts { field: self.field, seed: self.seed, monsters: self.monsters, threads: self.threads, bots: self.bots, rally_permille: self.rally_permille, level: self.level, vault: None }
    }
}

fn parse_args() -> Args {
    let mut a = Args { port: DEFAULT_PORT, seed: 1, bots: 0, monsters: 20_000, rally_permille: 300, threads: 1, report: 5, ticks: None, bench: false, follow: false, zoom: 1, warmup: 100, field: 0, level: 0 };
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
            "--field" => a.field = (num(v) as u8).min(5),
            "--level" => a.level = (num(v) as u8).min(60),
            "--help" | "-h" => {
                println!("realm-server [--port=7777] [--seed=1] [--bots=N] [--monsters=M] [--rally=0.3] [--threads=T] [--report=secs] [--ticks=N] [--bench] [--follow] [--zoom=1] [--warmup=100] [--field=0..5] [--level=N (0: the field's top)]");
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
    let mut sim = Sim::new(&args.sim_opts());
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
            report(&sim.field, args.threads, &w, join_bytes);
            w = Window::default();
        }
    }
    if !w.ticks.is_empty() {
        report(&sim.field, args.threads, &w, sim.ls.state_bytes(&sim.field).len());
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

fn main() {
    let args = parse_args();
    if args.bench {
        bench(&args);
    } else {
        let opts = HostOpts { sim: args.sim_opts(), port: args.port, report_secs: args.report, ticks: args.ticks, ..HostOpts::default() };
        if let Err(e) = run_here(opts) {
            die(&format!("bind {}: {e}", args.port));
        }
    }
}
