//! A field host: one field copy's 20 Hz loop on its own thread group (the simulation's worker threads and the
//! host's receive thread), serving protocol A and B over UDP.
//!
//! Two ways to run it:
//! - the crowd test's server (`realm-server`): no tickets, bots, a HELLO's class and race make a bench hero;
//! - a field behind a gateway (`realm-gateway`): `require_tickets`. The gateway sends `HostCmd::Admit` with a
//!   hero's sheet and outing and a ticket; the client's HELLO carries the ticket; the host joins her. What she
//!   does leaves as `HostMsg::Flush`: banked coin, class XP, potions drunk and a waystone claimed, as it
//!   happens (every BANK, every potion, every `XP_FLUSH_TICKS` for XP) and once more, final, when she leaves
//!   by the gate or a waystone, or disconnects, is kicked or the host stops. The gateway applies each flush to
//!   the store. A final flush names why she left (`Leave`).
//!
//! What a hero who disconnects keeps: her haul's coin is not banked, so she loses half of it as if she had
//! fallen (`coin / 2`, the core's fall rule) and the rest is banked. The gate, a waystone, a kick and a stop
//! bank all of it. Rolls of items and a fall's loss of half the haul's items are the loot job's: it adds them
//! to the flush on the gateway's side.

use crate::lockstep::{state_parts, InputQueue, Resend};
use crate::report::{header, report, Window};
use crate::sim::*;
use crate::snap::{encode_v0, encode_v1};
use crate::view::{build, Scratch, View};
use crate::*;
use realm_core::tables::NO_WAYSTONE;
use realm_core::{Event, Field, Outing, Sheet, FIELD, SUB};
use std::collections::{HashMap, VecDeque};
use std::net::{SocketAddr, UdpSocket};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

pub const STATE_PARTS_PER_TICK: usize = 48;
pub const TIMEOUT: Duration = Duration::from_secs(5);
/// A ticket nobody used is dropped after this long.
pub const TICKET_TTL: Duration = Duration::from_secs(30);
/// A hero's class XP goes to the store at least this often while she earns it (10 s).
pub const XP_FLUSH_TICKS: u32 = 200;
/// How far in from the gate a hero with no waystone appears (px).
pub const GATE_ENTRY_PX: i32 = 120;
/// Scatter of a hero's entry point, each way (px).
pub const ENTRY_SCATTER_PX: i32 = 30;

#[derive(Clone, Debug)]
pub struct HostOpts {
    pub sim: SimOpts,
    /// 0 picks a free port; read it from `HostHandle::addr`.
    pub port: u16,
    /// A report row every this many seconds of game time (0: none).
    pub report_secs: u32,
    pub ticks: Option<u32>,
    /// Only a ticket from the gateway joins a hero (a follower needs none, see `allow_followers`).
    pub require_tickets: bool,
    pub allow_followers: bool,
}

impl Default for HostOpts {
    fn default() -> Self {
        HostOpts { sim: SimOpts::default(), port: DEFAULT_PORT, report_secs: 0, ticks: None, require_tickets: false, allow_followers: true }
    }
}

/// A hero the gateway lets in: `hero` is the gateway's own number for her (the store's hero id), `ticket` is
/// what her client will send in HELLO.
#[derive(Clone, Debug)]
pub struct Entry {
    pub ticket: u64,
    pub hero: u64,
    pub sheet: Sheet,
    pub outing: Outing,
}

#[derive(Debug)]
pub enum HostCmd {
    Admit(Entry),
    /// Takes the hero out of the field (banking everything: the operator did it, not she).
    Kick(u64),
    /// Banks and removes everyone, then ends the host.
    Stop,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Leave {
    Gate,
    Waystone,
    Disconnect,
    Kicked,
    Shutdown,
}

/// What a hero earned since her last flush. Apply every field to the store, in one request.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Flush {
    pub hero: u64,
    pub ticket: u64,
    /// 1, 2, 3 ... per hero and ticket: with the ticket it names this flush, so applying it twice is harmless.
    pub seq: u32,
    /// Coin banked (BANK events; for a disconnect the half of the haul she keeps).
    pub coin: u64,
    /// Coin the haul lost (FALLEN, and half of a disconnected hero's haul): information, never applied.
    pub lost_coin: u64,
    /// Class XP earned.
    pub xp: u64,
    /// Potions drunk, by potion id (the core's `P_*`); a PHOENIX ASH that raised her counts.
    pub potions: [u32; 6],
    /// A waystone she claimed this flush (0..6).
    pub waystone: Option<u8>,
    pub fell: u32,
    /// The haul she carries is safe with this flush: a BANK happened, or she left by the gate, a waystone, a kick
    /// or a stop. A flush without it (XP, a potion) leaves the haul where it is; a disconnect banks it after the
    /// loss of half (`left` is `Disconnect`).
    pub banked: bool,
    /// None: she is still in the field.
    pub left: Option<Leave>,
}

/// One credited hero of a kill.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Credited {
    pub hero: u64,
    pub ticket: u64,
    /// Her slot in the field (part of the roll's key).
    pub slot: u16,
    /// `Field::luck`: FORTUNE and GAMBLER'S COIN.
    pub luck: i32,
}

/// A `KILL` event with the ticketed heroes it credits. `index` is the event's place in the tick's list.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KillRoll {
    pub index: u32,
    pub kind: u8,
    pub level: u8,
    pub flags: u8,
    pub credited: Vec<Credited>,
}

/// The kills of one tick that credit ticketed heroes: what the loot rolls need (`realm_loot::RollKey`).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KillBatch {
    pub field_seed: u64,
    pub tick: u32,
    pub kills: Vec<KillRoll>,
}

#[derive(Debug)]
pub enum HostMsg {
    Flush(Flush),
    /// Kills this tick that credit ticketed heroes. Sent after the tick's flushes: an event order of BANK, FALLEN,
    /// then KILL means the drops of a kill land in the haul after the bank or the fall.
    Kills(KillBatch),
    /// A ticket was never used (expired, or the hero was already in the field).
    Unused { hero: u64, ticket: u64 },
    /// She is in the field as hero slot `id`.
    Joined { hero: u64, ticket: u64, id: u16 },
    /// The host has stopped.
    Closed,
}

pub struct HostHandle {
    pub addr: SocketAddr,
    pub field: u8,
    pub cmds: Sender<HostCmd>,
    /// Heroes in the field now (for the gateway to choose the emptier copy).
    pub heroes: Arc<AtomicU32>,
    thread: Option<JoinHandle<()>>,
}

impl HostHandle {
    pub fn stop(&mut self) {
        let _ = self.cmds.send(HostCmd::Stop);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}

impl Drop for HostHandle {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Starts a host on its own thread.
pub fn spawn(opts: HostOpts, msgs: Option<Sender<HostMsg>>) -> std::io::Result<HostHandle> {
    let sock = UdpSocket::bind(("0.0.0.0", opts.port))?;
    let addr = sock.local_addr()?;
    let (cmds, rx) = channel();
    let heroes = Arc::new(AtomicU32::new(0));
    let (h2, field) = (heroes.clone(), opts.sim.field);
    let thread = std::thread::Builder::new().name(format!("field-{field}-{}", addr.port())).spawn(move || run(opts, sock, rx, msgs, h2))?;
    Ok(HostHandle { addr, field, cmds, heroes, thread: Some(thread) })
}

/// Runs a host on this thread until `opts.ticks` or a `Stop` (the crowd test's `realm-server`).
pub fn run_here(opts: HostOpts) -> std::io::Result<()> {
    let sock = UdpSocket::bind(("0.0.0.0", opts.port))?;
    let (_keep, rx) = channel();
    run(opts, sock, rx, None, Arc::new(AtomicU32::new(0)));
    Ok(())
}

/// The packets received by a thread that does nothing else: the default receive buffer holds a few hundred
/// datagrams, fewer than a thousand clients send while one tick encodes.
fn receiver(sock: &UdpSocket) -> Receiver<(SocketAddr, Vec<u8>)> {
    let (tx, rx) = channel::<(SocketAddr, Vec<u8>)>();
    let rsock = sock.try_clone().expect("clone socket");
    // The socket is closed to the thread by its own read timeout when the host ends (the thread then stops).
    let _ = rsock.set_read_timeout(Some(Duration::from_millis(200)));
    std::thread::spawn(move || {
        let mut buf = [0u8; 2048];
        loop {
            match rsock.recv_from(&mut buf) {
                Ok((len, from)) => {
                    if tx.send((from, buf[..len].to_vec())).is_err() {
                        break;
                    }
                }
                // Windows reports an earlier send to a client that has gone (ICMP port unreachable) as an
                // error on the next receive: the socket is still good.
                Err(e) if e.kind() == std::io::ErrorKind::ConnectionReset => {}
                Err(e) if matches!(e.kind(), std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut) => {
                    if tx.send((rsock.local_addr().unwrap_or(([0, 0, 0, 0], 0).into()), Vec::new())).is_err() {
                        break;
                    }
                }
                Err(e) => {
                    eprintln!("realm host: receive: {e}");
                    std::thread::sleep(Duration::from_millis(10));
                }
            }
        }
    });
    rx
}

struct Client {
    proto: u32,
    id: Option<u16>,
    input: u16,
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
    /// B: which records to send this tick.
    resend: Resend,
    /// A lockstep player: its numbered inputs, and the seq in force at each recent tick.
    queue: InputQueue,
    seqs: VecDeque<(u32, u32)>,
    bytes: u64,
    view_mon: u32,
    view_ply: u32,
}

/// What a ticketed hero has earned and not yet sent.
struct Tally {
    hero: u64,
    ticket: u64,
    seq: u32,
    /// The potion id in each belt slot when she entered.
    belt_ids: [u8; 3],
    xp: u64,
    coin: u64,
    potions: [u32; 6],
    waystone: Option<u8>,
    fell: u32,
    lost: u64,
    banked: bool,
    urgent: bool,
    gate: bool,
    last_flush: u32,
}

impl Tally {
    /// Takes what she has earned as a flush.
    fn take(&mut self, tick: u32, left: Option<Leave>) -> Flush {
        self.seq += 1;
        let f = Flush {
            hero: self.hero,
            ticket: self.ticket,
            seq: self.seq,
            coin: self.coin,
            lost_coin: self.lost,
            xp: self.xp,
            potions: self.potions,
            waystone: self.waystone,
            fell: self.fell,
            banked: self.banked || matches!(left, Some(Leave::Gate | Leave::Waystone | Leave::Kicked | Leave::Shutdown | Leave::Disconnect)),
            left,
        };
        self.banked = false;
        self.coin = 0;
        self.lost = 0;
        self.xp = 0;
        self.potions = [0; 6];
        self.waystone = None;
        self.fell = 0;
        self.urgent = false;
        self.last_flush = tick;
        f
    }
}

/// Where a hero appears: at her waystone if she has claimed one, else a little inside the gate.
pub fn entry_spot(field: &Field, outing: &Outing, rng: &mut u64) -> (i32, i32) {
    let r = realm_core::rng_next(rng);
    let scatter = |v: u64| ((v % (2 * ENTRY_SCATTER_PX as u64 + 1)) as i32 - ENTRY_SCATTER_PX) * SUB;
    let t = field.terrain();
    let (bx, by) = match t.waystones.get(outing.waystone as usize) {
        Some(&w) if outing.waystone != NO_WAYSTONE => w,
        _ => {
            let (gx, gy) = t.gate;
            let (dx, dy) = (FIELD / 2 - gx, FIELD / 2 - gy);
            if dx.abs() > dy.abs() { (gx + dx.signum() * GATE_ENTRY_PX * SUB, gy) } else { (gx, gy + dy.signum() * GATE_ENTRY_PX * SUB) }
        }
    };
    (bx + scatter(r >> 8), by + scatter(r >> 32))
}

fn run(opts: HostOpts, sock: UdpSocket, cmds: Receiver<HostCmd>, msgs: Option<Sender<HostMsg>>, heroes_count: Arc<AtomicU32>) {
    let rx = receiver(&sock);
    let local = sock.local_addr().map(|a| a.port()).unwrap_or(0);
    if opts.report_secs > 0 {
        let a = &opts.sim;
        eprintln!("realm-server: udp {local} field={} seed={} bots={} monsters={} rally={}/1000 threads={}", a.field, a.seed, a.bots, a.monsters, a.rally_permille, a.threads);
    }
    let send_msg = |m: HostMsg| {
        if let Some(tx) = &msgs {
            let _ = tx.send(m);
        }
    };
    let mut sim = Sim::new(&opts.sim);
    let mut clients: HashMap<SocketAddr, Client> = HashMap::new();
    let mut pending: HashMap<u64, (Entry, Instant)> = HashMap::new();
    let mut tallies: HashMap<u16, Tally> = HashMap::new();
    let mut w = Window::default();
    let mut scratch = Scratch::default();
    let mut out = Vec::new();
    let mut inbox: Vec<(SocketAddr, Vec<u8>)> = Vec::new();
    let (mut send_errors, mut hellos, mut received) = (0u64, 0u64, 0u64);
    let mut rng = opts.sim.seed ^ 0xC11E;
    let start = Instant::now();
    let period = Duration::from_millis(50);
    if opts.report_secs > 0 {
        header();
    }
    let mut n = 0u64;
    let mut stopping = false;
    'ticks: loop {
        if opts.ticks.is_some_and(|t| sim.field.tick() >= t) {
            break;
        }
        let due = start + period * n as u32;
        let now = Instant::now();
        if due > now {
            std::thread::sleep(due - now);
        }
        inbox.extend(rx.try_iter().filter(|(_, m)| !m.is_empty()));
        received += inbox.len() as u64;
        n += 1;
        let mut leaves: Vec<u16> = Vec::new();
        let mut finals: Vec<Flush> = Vec::new();
        // Orders from the gateway.
        for cmd in cmds.try_iter().collect::<Vec<_>>() {
            match cmd {
                HostCmd::Admit(e) => {
                    let in_field = tallies.values().any(|t| t.hero == e.hero) || pending.values().any(|(p, _)| p.hero == e.hero);
                    if in_field || pending.contains_key(&e.ticket) {
                        send_msg(HostMsg::Unused { hero: e.hero, ticket: e.ticket });
                    } else {
                        pending.insert(e.ticket, (e, Instant::now()));
                    }
                }
                HostCmd::Kick(hero) => {
                    // A ticket not yet used is handed back too (a ban must not wait out its 30 s).
                    pending.retain(|_, (e, _)| {
                        let go = e.hero == hero;
                        if go {
                            send_msg(HostMsg::Unused { hero: e.hero, ticket: e.ticket });
                        }
                        !go
                    });
                    if let Some((&id, _)) = tallies.iter().find(|(_, t)| t.hero == hero) {
                        leaves.push(id);
                        for c in clients.values_mut().filter(|c| c.id == Some(id)) {
                            c.id = None;
                        }
                        if let Some(mut t) = tallies.remove(&id) {
                            finals.push(final_flush(&mut t, &sim.field, id, sim.field.tick(), Leave::Kicked));
                        }
                    }
                }
                HostCmd::Stop => stopping = true,
            }
        }
        if stopping {
            for (id, mut t) in tallies.drain() {
                leaves.push(id);
                finals.push(final_flush(&mut t, &sim.field, id, sim.field.tick(), Leave::Shutdown));
            }
            for (_, (e, _)) in pending.drain() {
                send_msg(HostMsg::Unused { hero: e.hero, ticket: e.ticket });
            }
        }
        pending.retain(|_, (e, at)| {
            let keep = at.elapsed() < TICKET_TTL;
            if !keep {
                send_msg(HostMsg::Unused { hero: e.hero, ticket: e.ticket });
            }
            keep
        });
        // Read everything that arrived.
        let mut joins: Vec<sim_join::Req> = Vec::new();
        for (from, msg) in inbox.drain(..) {
            let mut r = Rd::new(&msg);
            match r.u8() {
                Some(MSG_HELLO) if !stopping => {
                    hellos += 1;
                    let Some((proto, class, race, ticket)) = parse_hello(&mut r) else { continue };
                    if let Some(c) = clients.get(&from) {
                        // A repeated HELLO: the WELCOME was lost.
                        if let Some(id) = c.id {
                            if sock.send_to(&welcome(id as u32, sim.field.tick()), from).is_err() {
                                send_errors += 1;
                            }
                        }
                        continue;
                    }
                    let mut who: Option<(u64, u64)> = None;
                    let mut req: Option<JoinReq> = None;
                    if proto != PROTO_B {
                        if opts.require_tickets {
                            let Some((e, _)) = pending.remove(&ticket) else { continue };
                            let (x, y) = entry_spot(&sim.field, &e.outing, &mut rng);
                            who = Some((e.hero, e.ticket));
                            req = Some(JoinReq { sheet: e.sheet, outing: e.outing, x, y });
                        } else {
                            let rr = realm_core::rng_next(&mut rng);
                            let x = FIELD / 2 + ((rr % 400) as i32 - 200) * SUB;
                            let y = FIELD / 2 + (((rr >> 20) % 400) as i32 - 200) * SUB;
                            // The HELLO's class is 0..4 (KNIGHT to PALADIN); the core's class 0 is the NOVICE.
                            req = Some(JoinReq { sheet: Sheet::bench(1 + class.min(4), race.min(3), sim.bench_level()), outing: Outing::new(), x, y });
                        }
                    } else if !opts.allow_followers {
                        continue;
                    }
                    let c = Client {
                        proto,
                        id: None,
                        input: 0,
                        zoom: 1,
                        ack: 0,
                        heard: Instant::now(),
                        ring: VecDeque::new(),
                        state_tick: None,
                        state: Vec::new(),
                        state_next: 0,
                        resend: Resend::default(),
                        queue: InputQueue::default(),
                        seqs: VecDeque::new(),
                        bytes: 0,
                        view_mon: 0,
                        view_ply: 0,
                    };
                    if let Some(rq) = req {
                        joins.push(sim_join::Req { addr: from, req: rq, who });
                    }
                    clients.insert(from, c);
                }
                Some(MSG_INPUT) => {
                    if let (Some(c), Some(m)) = (clients.get_mut(&from), parse_input(&mut r)) {
                        c.ack = c.ack.max(m.ack);
                        c.resend.on_ack(m.ack, sim.field.tick());
                        c.zoom = m.zoom;
                        c.heard = Instant::now();
                        // A lockstep player numbers its inputs and repeats the last few; they wait in its queue.
                        match m.seq_words {
                            Some((seq, words)) => c.queue.take(seq, &words),
                            None => c.input = m.word,
                        }
                    }
                }
                Some(MSG_BYE) => {
                    if let Some(c) = clients.remove(&from) {
                        if let Some(id) = c.id {
                            leaves.push(id);
                            if let Some(mut t) = tallies.remove(&id) {
                                finals.push(final_flush(&mut t, &sim.field, id, sim.field.tick(), Leave::Disconnect));
                            }
                        }
                    }
                }
                _ => {}
            }
        }
        let mut gone = Vec::new();
        clients.retain(|a, c| {
            let keep = c.heard.elapsed() < TIMEOUT && !stopping;
            if !keep {
                gone.push((*a, c.id));
            }
            keep
        });
        for (_, id) in gone {
            if let Some(id) = id {
                if !leaves.contains(&id) {
                    leaves.push(id);
                    if let Some(mut t) = tallies.remove(&id) {
                        let why = if stopping { Leave::Shutdown } else { Leave::Disconnect };
                        finals.push(final_flush(&mut t, &sim.field, id, sim.field.tick(), why));
                    }
                }
            }
        }
        // A hero who is already gone from the field (she left by the gate this very tick) has no slot to leave.
        leaves.retain(|&id| sim.field.players().get(id as usize).is_some_and(|p| p.present));
        for c in clients.values_mut().filter(|c| c.proto == PROTO_BP) {
            c.input = c.queue.next_tick();
        }
        let inputs: Vec<(u16, u16)> = clients.values().filter_map(|c| c.id.map(|id| (id, c.input))).collect();
        let mut row = [0f64; NCOL];
        let t0 = Instant::now();
        let reqs: Vec<JoinReq> = joins.iter().map(|j| j.req.clone()).collect();
        let ids = sim.tick(&reqs, &leaves, &inputs, &mut row);
        let tick = sim.field.tick();
        for (j, id) in joins.iter().zip(ids) {
            if let Some(c) = clients.get_mut(&j.addr) {
                c.id = Some(id);
                if sock.send_to(&welcome(id as u32, tick), j.addr).is_err() {
                    send_errors += 1;
                }
            }
            if let Some((hero, ticket)) = j.who {
                let belt_ids = sim.field.players().get(id as usize).map_or([realm_core::tables::P_NONE; 3], |h| h.belt.map(|b| b.0));
                tallies.insert(id, Tally { hero, ticket, seq: 0, belt_ids, xp: 0, coin: 0, potions: [0; 6], waystone: None, fell: 0, lost: 0, banked: false, urgent: false, gate: false, last_flush: tick });
                send_msg(HostMsg::Joined { hero, ticket, id });
            }
        }
        heroes_count.store(sim.field.player_count(), Ordering::Relaxed);
        // What the tick's events did to the heroes' tallies; leaves last, so a hero's other events count.
        collect(&sim.field, &mut tallies, &mut clients, &mut finals);
        for t in tallies.values_mut() {
            if t.urgent || (t.xp > 0 && tick.saturating_sub(t.last_flush) >= XP_FLUSH_TICKS) {
                finals.push(t.take(tick, None));
            }
        }
        for f in finals {
            send_msg(HostMsg::Flush(f));
        }
        if msgs.is_some() && !tallies.is_empty() {
            if let Some(b) = kill_batch(&sim.field, &tallies) {
                send_msg(HostMsg::Kills(b));
            }
        }
        for c in clients.values_mut().filter(|c| c.proto == PROTO_BP && c.id.is_some()) {
            c.seqs.push_back((tick, c.queue.seq));
            if c.seqs.len() > HISTORY {
                c.seqs.pop_front();
            }
        }
        // Snapshots at 10 Hz, B every tick.
        for (addr, c) in clients.iter_mut() {
            match (c.proto, c.id) {
                (PROTO_B | PROTO_BP, _) => {
                    let tc = Instant::now();
                    let behind = c.state_tick.is_some_and(|st| c.ack >= st && c.ack + (HISTORY as u32) < tick);
                    let stale = c.state_tick.is_some_and(|st| c.ack < st && tick >= st + HISTORY as u32 - 8);
                    if c.state_tick.is_none() || behind || stale {
                        c.state = state_parts(tick, &sim.ls.state_bytes(&sim.field));
                        c.state_tick = Some(tick);
                        c.state_next = 0;
                        c.resend = Resend::default();
                        let id = c.id.map_or(u32::MAX, |i| i as u32);
                        if sock.send_to(&welcome(id, tick), addr).is_err() {
                            send_errors += 1;
                        }
                    }
                    let st = c.state_tick.unwrap_or(0);
                    if c.ack < st {
                        // Still joining: a few state parts a tick (a burst would overflow the client's buffer),
                        // over and over until acknowledged.
                        for _ in 0..STATE_PARTS_PER_TICK {
                            let p = &c.state[c.state_next % c.state.len()];
                            c.state_next += 1;
                            c.bytes += p.len() as u64;
                            if sock.send_to(p, addr).is_err() {
                                send_errors += 1;
                            }
                        }
                    }
                    // Each tick's record once, and again only after a round trip without an acknowledgement.
                    let floor = c.ack.max(st);
                    let have: Vec<u32> = sim.history.iter().map(|(t, _)| *t).filter(|&t| t > floor).collect();
                    let ticks = c.resend.pick(tick, have.into_iter());
                    if !ticks.is_empty() {
                        sim.b_datagrams_for(&ticks, &c.seqs, &mut out);
                        for d in &out {
                            c.bytes += d.len() as u64;
                            if sock.send_to(d, addr).is_err() {
                                send_errors += 1;
                            }
                        }
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
                        if sock.send_to(d, addr).is_err() {
                            send_errors += 1;
                        }
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
                if matches!(c.proto, PROTO_A0 | PROTO_A1) && c.id.is_some() {
                    w.view_mon.push(c.view_mon as f64);
                    w.view_ply.push(c.view_ply as f64);
                }
                c.bytes = 0;
            }
        }
        if opts.report_secs > 0 && tick % (opts.report_secs * 20) == 0 {
            report(&sim.field, opts.sim.threads, &w, sim.ls.state_bytes(&sim.field).len());
            eprintln!("net clients={} received={received} hellos={hellos} send_errors={send_errors}", clients.len());
            w = Window::default();
        } else if opts.report_secs == 0 && w.ticks.len() >= 400 {
            w = Window::default();
        }
        if stopping {
            break 'ticks;
        }
    }
    send_msg(HostMsg::Closed);
}

mod sim_join {
    use super::*;
    /// A hello that is joining this tick.
    pub struct Req {
        pub addr: SocketAddr,
        pub req: JoinReq,
        pub who: Option<(u64, u64)>,
    }
}

/// The flush of a hero who is leaving by someone's choice: the haul's coin is read from the field (she is
/// still in her slot; the leave is applied at the start of the next tick).
fn final_flush(t: &mut Tally, field: &Field, id: u16, tick: u32, why: Leave) -> Flush {
    let haul = field.outing(id).map_or(0, |o| o.coin as u64);
    match why {
        // Pulled the plug: the haul is not banked, she loses half of it as a fall would.
        Leave::Disconnect => {
            let lost = haul / 2;
            t.coin += haul - lost;
            t.lost += lost;
        }
        _ => t.coin += haul,
    }
    t.take(tick, Some(why))
}

/// The tick's kills that credit ticketed heroes still in the field (a hero who left this tick took no part).
fn kill_batch(field: &Field, tallies: &HashMap<u16, Tally>) -> Option<KillBatch> {
    let mut kills = Vec::new();
    for (index, e) in field.events().iter().enumerate() {
        if let Event::Kill { kind, level, flags, first, count, .. } = *e {
            let credited: Vec<Credited> = field
                .credited(first, count)
                .iter()
                .filter_map(|&slot| tallies.get(&slot).map(|t| Credited { hero: t.hero, ticket: t.ticket, slot, luck: field.luck(slot) }))
                .collect();
            if !credited.is_empty() {
                kills.push(KillRoll { index: index as u32, kind, level, flags, credited });
            }
        }
    }
    (!kills.is_empty()).then(|| KillBatch { field_seed: field.seed(), tick: field.tick(), kills })
}

/// Turns a tick's events into the heroes' tallies. A hero who left by the gate or a waystone is flushed and
/// her client forgets her slot.
fn collect(field: &Field, tallies: &mut HashMap<u16, Tally>, clients: &mut HashMap<SocketAddr, Client>, finals: &mut Vec<Flush>) {
    let tick = field.tick();
    for e in field.events() {
        match *e {
            Event::Xp { hero, amount } => {
                if let Some(t) = tallies.get_mut(&hero) {
                    t.xp += amount as u64;
                }
            }
            Event::Potion { hero, slot, .. } => {
                if let Some(t) = tallies.get_mut(&hero) {
                    if let Some(&p) = t.belt_ids.get(slot as usize) {
                        if (p as usize) < t.potions.len() {
                            t.potions[p as usize] += 1;
                            t.urgent = true;
                        }
                    }
                }
            }
            Event::Fallen { hero, coin } => {
                if let Some(t) = tallies.get_mut(&hero) {
                    t.fell += 1;
                    t.lost += coin as u64;
                    t.urgent = true;
                }
            }
            Event::Bank { hero, coin, waystone } => {
                if let Some(t) = tallies.get_mut(&hero) {
                    t.coin += coin as u64;
                    t.banked = true;
                    if waystone == NO_WAYSTONE {
                        t.gate = true;
                    } else {
                        t.waystone = Some(waystone);
                    }
                    t.urgent = true;
                }
            }
            _ => {}
        }
    }
    for e in field.events() {
        if let Event::Leave { hero } = *e {
            if let Some(mut t) = tallies.remove(&hero) {
                let why = if t.gate { Leave::Gate } else { Leave::Waystone };
                finals.push(t.take(tick, Some(why)));
            }
            for c in clients.values_mut().filter(|c| c.id == Some(hero)) {
                c.id = None;
            }
        }
    }
}
