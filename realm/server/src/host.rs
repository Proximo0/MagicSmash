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

use crate::driver::{Act, Drive, Driver};
use crate::lockstep::{state_parts, InputQueue, Resend};
use crate::realm_clock::{clock_fix, RealmClock};
use crate::report::{header, report, Window};
use crate::sim::*;
use crate::snap::{encode_v0, encode_v1};
use crate::view::{build, Scratch, View};
use crate::*;
use realm_core::tables::{NO_WAYSTONE, R_BOSS_CHEST, VAULTS, VAULT_OVERTIME, BOSS_KILLED, BOSS_RISES, BOSS_LEFT, TIDE_BEGIN, TIDE_WON, TIDE_LOST, B_DEATH};
use realm_core::{ring_of, Event, Field, Outing, Sheet, Transfer, FIELD, RUN_GOING, SUB};
use realm_core::pvp::WAR_END;
use crate::lockstep::WarArm;
use std::collections::{HashMap, VecDeque};
use std::net::{SocketAddr, UdpSocket};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, AtomicU8, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex};
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
/// A vault host stays this long after its run is WON or LOST (the chest is shown), then banks everyone and
/// stops (30 s).
pub const VAULT_LINGER_TICKS: u32 = 600;
/// A vault nobody has entered this long after it opened stops (60 s, two ticket lifetimes).
pub const VAULT_EMPTY_TICKS: u32 = 1_200;
/// A vault whose run has not ended this long past its timeline and overtime is closed anyway (2 min of margin):
/// the time limit of rules section 10 is the core's; this is the host's guard against a run that never ends.
pub const VAULT_GUARD_TICKS: u32 = 2_400;
/// `HostStatus::vault` of a field host.
pub const NOT_A_VAULT: u8 = u8::MAX;

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
    /// The realm's clock: the field follows it (tides and bosses of every copy together). None: its own.
    pub clock: Option<RealmClock>,
    /// Microseconds a tick (50,000: 20 Hz). A test realm runs faster; 0 runs as fast as it can.
    pub tick_us: u32,
    /// The gateway's number for this host (in `HostMsg`s that name their host).
    pub id: u32,
    /// An unused ticket is handed back after this long (`TICKET_TTL`).
    pub ticket_ttl: Duration,
}

impl Default for HostOpts {
    fn default() -> Self {
        HostOpts {
            sim: SimOpts::default(),
            port: DEFAULT_PORT,
            report_secs: 0,
            ticks: None,
            require_tickets: false,
            allow_followers: true,
            clock: None,
            tick_us: 50_000,
            id: 0,
            ticket_ttl: TICKET_TTL,
        }
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
    /// The ticket's last flush number: a hero moved from another copy goes on counting from it, so the store's
    /// request ids (ticket and number) never repeat.
    pub seq: u32,
    /// A hero moved from another copy arrives in this ring (`Field::ring_point`), not at the gate or her waystone.
    pub arrive: Option<u8>,
    /// The host plays her itself (`driver.rs`): she joins at once, no HELLO.
    pub drive: Option<Drive>,
    /// The ticket's secret (random for each admission, from the gateway over TLS): her HELLO must prove it (it is
    /// never sent), her INPUT and BYE are tagged with it. A ticket whose key is all
    /// zeros joins nobody by HELLO.
    pub key: TicketKey,
    /// Her guild (0: none), from the gateway's social (`Social::guild_of_account`): the field tags her with it as she
    /// joins (`Field::set_guild`, carried by the join's record so followers tag her too). What a war reads.
    pub guild: u64,
}

impl Entry {
    pub fn new(ticket: u64, hero: u64, sheet: Sheet, outing: Outing) -> Entry {
        Entry { ticket, hero, sheet, outing, seq: 0, arrive: None, drive: None, key: TicketKey::default(), guild: 0 }
    }
}

#[derive(Debug)]
pub enum HostCmd {
    Admit(Entry),
    /// Takes the hero out of the field (banking everything: the operator did it, not she).
    Kick(u64),
    /// Takes the hero out to be set down in another copy of the field (rules section 11): her flush so far, then
    /// `HostMsg::Moved` with her `Transfer` (sheet, outing state, ring).
    MoveOut(u64),
    /// Banks and removes everyone, then ends the host.
    Stop,
    /// Ends at once with no flush, as a crashed process would (the kill tests).
    Abort,
    /// Arms a guild war on this copy (`Field::declare_war`, job R3b) with the next tick's record, so followers arm
    /// it at the same tick.
    War(WarArm),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Leave {
    Gate,
    Waystone,
    Disconnect,
    Kicked,
    Shutdown,
    /// Her vault's run is over (won or lost) and the vault has closed: everything banked.
    Vault,
}

impl Leave {
    /// The code the gateway's Outing push carries: 0 gate, 1 waystone, 2 disconnect, 3 kicked, 4 shutdown, 5 vault.
    pub fn code(self) -> u8 {
        match self {
            Leave::Gate => 0,
            Leave::Waystone => 1,
            Leave::Disconnect => 2,
            Leave::Kicked => 3,
            Leave::Shutdown => 4,
            Leave::Vault => 5,
        }
    }
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
    /// Section 14 (job R3): her BLOOD MARK and the ticks since her last strike on a hero (`NEVER`), sent when either
    /// changed and always when she leaves, so her next outing carries them.
    pub mark: Option<(bool, u32)>,
    /// Job R3b: which of this flush's falls (`fell`, counted from 0) were plunders, and by whom: the gateway moves
    /// what each of those falls took from her haul to that hero.
    pub plunders: Vec<Plundered>,
    /// Job R3b: the part of `coin` (banked) that she took from other heroes' hauls, as (victim, coin), first taken
    /// first banked. Not part of `coin`: the gateway banks it as the victim's coin moved to her, so the victim's
    /// trace and clawback reach it.
    pub plunder_coin: Vec<(u64, u64)>,
}

/// One plundered fall: the hero who downed her (his gateway number and ticket, he was in the field) and the coin the
/// core moved to his haul (`Event::Plunder`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Plundered {
    pub fall: u32,
    pub by_hero: u64,
    pub by_ticket: u64,
    pub coin: u64,
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
    /// The host's id (`HostOpts::id`): copies of a field share a seed, so the gateway mixes it into the roll key.
    pub host: u32,
    pub field_seed: u64,
    pub tick: u32,
    pub kills: Vec<KillRoll>,
}

/// A REWARD event (rules section 8 and 10) with the ticketed heroes it pays, for the gateway to roll its chest.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RewardBatch {
    pub host: u32,
    pub field_seed: u64,
    pub tick: u32,
    /// The event's place in the tick's list (part of the roll's key).
    pub index: u32,
    /// `R_*`.
    pub kind: u8,
    /// The field (or the vault's field), the level and a vault's seals, as the event says.
    pub source: u8,
    pub level: u8,
    pub seals: u8,
    /// The boss whose death paid it (a boss chest; its first kill gives a page), `u8::MAX` for none.
    pub boss: u8,
    /// A vault's row (`u8::MAX` in a field).
    pub vault: u8,
    /// The paid heroes with a ticket, best first, with their contribution.
    pub heroes: Vec<(Credited, u32)>,
}

/// What a host has seen, for the realm's report and the tests.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct HostCounts {
    pub tides: u32,
    pub tides_won: u32,
    pub tides_lost: u32,
    pub bosses: u32,
    pub bosses_killed: u32,
    pub bosses_left: u32,
    pub world_bosses: u32,
    pub rewards: u32,
    pub joined: u32,
    pub moved_in: u32,
    pub moved_out: u32,
    pub recalled: u32,
    /// Guild wars begun and ended in this copy (job R3b).
    pub wars_begun: u32,
    pub wars_ended: u32,
}

/// A host's state for the gateway, updated every tick.
#[derive(Debug)]
pub struct HostStatus {
    pub heroes: AtomicU32,
    pub tick: AtomicU32,
    pub clock: AtomicU64,
    pub tide: AtomicBool,
    pub boss: AtomicBool,
    /// `NOT_A_VAULT`, or the run's `RUN_*`.
    pub vault: AtomicU8,
    /// The thread has ended (any way: a stop, a vault's close, an abort or a panic).
    pub ended: AtomicBool,
    /// The gateway's hero numbers in the field now, and how many tickets wait for a HELLO.
    pub members: Mutex<Vec<u64>>,
    pub pending: AtomicU32,
    pub counts: Mutex<HostCounts>,
    /// Datagrams dropped as unproven: a HELLO without proof of its ticket's key, an INPUT or BYE from an address
    /// that has not joined, with a wrong tag or a stale counter, a follower on a ticketed field.
    pub refused: AtomicU64,
}

impl HostStatus {
    pub fn new(vault: bool) -> HostStatus {
        HostStatus {
            heroes: AtomicU32::new(0),
            tick: AtomicU32::new(0),
            clock: AtomicU64::new(0),
            tide: AtomicBool::new(false),
            boss: AtomicBool::new(false),
            vault: AtomicU8::new(if vault { RUN_GOING } else { NOT_A_VAULT }),
            ended: AtomicBool::new(false),
            members: Mutex::new(Vec::new()),
            pending: AtomicU32::new(0),
            counts: Mutex::new(HostCounts::default()),
            refused: AtomicU64::new(0),
        }
    }
}

/// Marks the status ended when the host's thread ends, whatever way it ends.
struct EndGuard(Arc<HostStatus>);

impl Drop for EndGuard {
    fn drop(&mut self) {
        // Release: whoever sees `ended` (Acquire) and then queues a message has it queued after this host's last.
        self.0.ended.store(true, Ordering::Release);
    }
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
    /// She was taken out for another copy (`HostCmd::MoveOut`), after her last flush (`seq`).
    Moved { host: u32, hero: u64, ticket: u64, seq: u32, transfer: Transfer, driven: Option<Drive> },
    /// A chest or cache is paid to ticketed heroes.
    Reward(RewardBatch),
    /// The host has stopped (cleanly: everyone flushed).
    Closed { host: u32 },
    /// Job R3b: a war's held altar ticks in this copy. `over`: its tide ended here (`War{END}`); otherwise the host
    /// stopped during the war (a copy closed into another) and this is what it held until then. Sent before `Closed`.
    War { host: u32, war: u64, held: [u32; 2], over: bool },
    /// Never sent by a host: the gateway's own note that a host is gone, queued behind that host's last messages so
    /// every flush it sent is applied before its outings are given up.
    Lost { host: u32 },
    /// Never sent by a host: the gateway's question about a host seen ended, queued behind that host's last
    /// messages (its `Closed`, if it sent one), so the answer (closed cleanly or died) does not depend on how far
    /// behind the applier is.
    Reap { host: u32 },
}

pub struct HostHandle {
    pub addr: SocketAddr,
    pub field: u8,
    pub cmds: Sender<HostCmd>,
    /// Heroes in the field now, the tide, the boss, the vault's run (for the gateway's copies and queue).
    pub status: Arc<HostStatus>,
    thread: Option<JoinHandle<()>>,
}

impl HostHandle {
    /// Heroes in the field now.
    pub fn heroes(&self) -> u32 {
        self.status.heroes.load(Ordering::Relaxed)
    }

    /// Waits for the thread if it has ended by itself (a vault closing, an abort).
    /// Joins the ended host's thread. `Some(message)` if it ended by a panic (a bug: the caller prints it).
    pub fn reap(&mut self) -> Option<String> {
        let t = self.thread.take()?;
        let e = t.join().err()?;
        Some(e.downcast_ref::<&str>().map(|s| s.to_string()).or_else(|| e.downcast_ref::<String>().cloned()).unwrap_or_else(|| "a panic with no message".into()))
    }

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
    let status = Arc::new(HostStatus::new(opts.sim.vault.is_some()));
    let (st, field) = (status.clone(), opts.sim.field);
    let thread = std::thread::Builder::new().name(format!("field-{field}-{}", addr.port())).spawn(move || run(opts, sock, rx, msgs, st))?;
    Ok(HostHandle { addr, field, cmds, status, thread: Some(thread) })
}

/// Runs a host on this thread until `opts.ticks` or a `Stop` (the crowd test's `realm-server`).
pub fn run_here(opts: HostOpts) -> std::io::Result<()> {
    let sock = UdpSocket::bind(("0.0.0.0", opts.port))?;
    let (_keep, rx) = channel();
    let vault = opts.sim.vault.is_some();
    run(opts, sock, rx, None, Arc::new(HostStatus::new(vault)));
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
                    if !realm_ops::flood::allow_udp(from.ip()) {
                        continue;
                    }
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
    /// A ticketed player: the key her HELLO proved, its nonce, and her last INPUT or BYE counter (a repeated HELLO
    /// must prove it again). 0 and None on a crowd-test server.
    key: Option<TicketKey>,
    nonce: u64,
    counter: u32,
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
    plunders: Vec<Plundered>,
    /// Coin plundered into her haul and not yet banked: (victim, coin), oldest first.
    debts: VecDeque<(u64, u64)>,
    banked: bool,
    urgent: bool,
    gate: bool,
    last_flush: u32,
    /// Her mark, the tick of her last strike on a hero (`NEVER`), and whether either changed since the last flush.
    marked: bool,
    struck: u32,
    mark_dirty: bool,
}

impl Tally {
    /// Takes what she has earned as a flush.
    fn take(&mut self, tick: u32, left: Option<Leave>) -> Flush {
        self.seq += 1;
        // Banked coin pays her plunder debts first (oldest first): that part is the victims' coin.
        let mut plunder_coin = Vec::new();
        while self.coin > 0 {
            let Some(d) = self.debts.front_mut() else { break };
            let n = d.1.min(self.coin);
            plunder_coin.push((d.0, n));
            self.coin -= n;
            d.1 -= n;
            if d.1 == 0 {
                self.debts.pop_front();
            }
        }
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
            banked: self.banked || left.is_some(),
            left,
            mark: (self.mark_dirty || left.is_some()).then(|| (self.marked, if self.struck == realm_core::tables::NEVER { self.struck } else { tick.saturating_sub(self.struck) })),
            plunders: std::mem::take(&mut self.plunders),
            plunder_coin,
        };
        self.mark_dirty = false;
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

/// Where an admitted hero appears: a moved one in her ring, in a vault near its heart, else `entry_spot`.
fn arrival(field: &Field, e: &Entry, rng: &mut u64) -> (i32, i32) {
    if let Some(ring) = e.arrive {
        return field.ring_point(ring, e.hero);
    }
    if field.vault().is_some() {
        let r = realm_core::rng_next(rng);
        let scatter = |v: u64| ((v % (2 * ENTRY_SCATTER_PX as u64 + 1)) as i32 - ENTRY_SCATTER_PX) * SUB;
        let (hx, hy) = field.terrain().heart;
        return (hx + scatter(r >> 8), hy + scatter(r >> 32));
    }
    entry_spot(field, &e.outing, rng)
}

/// A hero's `Transfer` as `Field::transfer_out` makes it, read without changing the field: the host takes her
/// out through the tick record's leave (so followers do the same) and sets her down in the other copy with a
/// join at `Field::ring_point`, which is what `transfer_in` does (tested to give the same hero).
pub fn transfer_of(field: &Field, id: u16) -> Option<Transfer> {
    let h = field.players().get(id as usize).filter(|h| h.present)?;
    Some(Transfer { sheet: h.sheet.clone(), outing: field.outing(id)?, ring: ring_of(h.x, h.y) })
}

fn run(opts: HostOpts, sock: UdpSocket, cmds: Receiver<HostCmd>, msgs: Option<Sender<HostMsg>>, status: Arc<HostStatus>) {
    let _guard = EndGuard(status.clone());
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
    let (mut send_errors, mut hellos, mut received, mut refused) = (0u64, 0u64, 0u64, 0u64);
    let mut rng = opts.sim.seed ^ 0xC11E;
    let start = Instant::now();
    let period = Duration::from_micros(opts.tick_us as u64);
    let vault_row = opts.sim.vault.map(|(v, _)| &VAULTS[(v as usize).min(VAULTS.len() - 1)]);
    let mut drivers: HashMap<u16, Driver> = HashMap::new();
    let mut vault_over: Option<u32> = None;
    let mut members_dirty = true;
    let mut counts = HostCounts::default();
    if opts.report_secs > 0 {
        header();
    }
    let mut n = 0u64;
    // Why everyone leaves when the host stops: the gateway's Stop, or the vault has closed.
    let mut stopping: Option<Leave> = None;
    // Heroes moved in and kicked in the same batch of orders: they join this tick and are kicked the next.
    let mut kick_next: Vec<u64> = Vec::new();
    'ticks: loop {
        if opts.ticks.is_some_and(|t| sim.field.tick() >= t) {
            break;
        }
        let due = start + period * n as u32;
        let now = Instant::now();
        if due > now {
            std::thread::sleep(due - now);
        } else {
            // Behind schedule: the ticks run back to back. Let every other ready thread go first each time, or a box
            // with more late hosts than cores starves the threads that answer players (on Windows a starved thread
            // waits seconds for its turn: a login reply took over 30 s on the 4-core check runner, 23 Nov 2026).
            std::thread::yield_now();
        }
        inbox.extend(rx.try_iter().filter(|(_, m)| !m.is_empty()));
        received += inbox.len() as u64;
        n += 1;
        let mut leaves: Vec<u16> = Vec::new();
        let mut finals: Vec<Flush> = Vec::new();
        let mut moved: Vec<HostMsg> = Vec::new();
        let mut joins: Vec<sim_join::Req> = Vec::new();
        let mut kicks: Vec<u64> = std::mem::take(&mut kick_next);
        // Orders from the gateway.
        for cmd in cmds.try_iter().collect::<Vec<_>>() {
            match cmd {
                HostCmd::Admit(e) => {
                    let in_field = tallies.values().any(|t| t.hero == e.hero) || pending.values().any(|(p, _)| p.hero == e.hero) || joins.iter().any(|j| j.who.is_some_and(|w| w.0 == e.hero));
                    let room = vault_row.is_none_or(|row| (sim.field.player_count() as usize + pending.len() + joins.len()) < row.party_max as usize);
                    let late = vault_row.is_some() && (vault_over.is_some() || stopping.is_some());
                    if in_field || pending.contains_key(&e.ticket) || !room || late || stopping.is_some() {
                        send_msg(HostMsg::Unused { hero: e.hero, ticket: e.ticket });
                    } else if let Some(d) = e.drive {
                        // A hero the host plays joins at once.
                        let (x, y) = arrival(&sim.field, &e, &mut rng);
                        let moved_in = e.arrive.is_some();
                        joins.push(sim_join::Req { addr: None, req: JoinReq { sheet: e.sheet, outing: e.outing, x, y, guild: e.guild }, who: Some((e.hero, e.ticket)), seq: e.seq, drive: Some(d), moved_in });
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
                    kicks.push(hero);
                }
                HostCmd::MoveOut(hero) => {
                    if let Some((&id, _)) = tallies.iter().find(|(_, t)| t.hero == hero) {
                        if let (Some(tr), Some(mut t)) = (transfer_of(&sim.field, id), tallies.remove(&id)) {
                            leaves.push(id);
                            for c in clients.values_mut().filter(|c| c.id == Some(id)) {
                                c.id = None;
                            }
                            // What she earned here goes to the store now; the haul's coin travels in her outing.
                            finals.push(t.take(sim.field.tick(), None));
                            let driven = drivers.remove(&id).map(|d| d.drive_at(sim.field.tick()));
                            moved.push(HostMsg::Moved { host: opts.id, hero, ticket: t.ticket, seq: t.seq, transfer: tr, driven });
                            counts.moved_out += 1;
                        }
                    }
                }
                HostCmd::Stop => stopping = Some(Leave::Shutdown),
                HostCmd::Abort => break 'ticks,
                HostCmd::War(a) => {
                    if vault_row.is_none() && !sim.next_wars.contains(&a) {
                        sim.next_wars.push(a);
                    }
                }
            }
        }
        // Heroes played by the host decide before anything else this tick; one who failed to get home is recalled.
        let mut driven_inputs: Vec<(u16, u16)> = Vec::new();
        for (&id, d) in drivers.iter_mut() {
            match d.act(&sim.field) {
                Act::Input(i) => driven_inputs.push((id, i)),
                Act::Recall => {
                    if let Some(t) = tallies.get(&id) {
                        kicks.push(t.hero);
                        counts.recalled += 1;
                    }
                }
            }
        }
        for hero in kicks {
            // Admitted and kicked in the same batch of orders (a starved host): she never joins. One moved in from a
            // closing copy carries her haul: she joins and is kicked next tick, so it is banked whole (handed back
            // unused, it would be banked as a disconnect, half of it lost).
            joins.retain(|j| match j.who {
                Some((h, _)) if h == hero && j.moved_in => {
                    kick_next.push(hero);
                    true
                }
                Some((h, ticket)) if h == hero => {
                    send_msg(HostMsg::Unused { hero, ticket });
                    false
                }
                _ => true,
            });
            if let Some((&id, _)) = tallies.iter().find(|(_, t)| t.hero == hero) {
                leaves.push(id);
                drivers.remove(&id);
                for c in clients.values_mut().filter(|c| c.id == Some(id)) {
                    c.id = None;
                }
                if let Some(mut t) = tallies.remove(&id) {
                    finals.push(final_flush(&mut t, &sim.field, id, sim.field.tick(), Leave::Kicked));
                }
            }
        }
        if let Some(why) = stopping {
            for (id, mut t) in tallies.drain() {
                leaves.push(id);
                finals.push(final_flush(&mut t, &sim.field, id, sim.field.tick(), why));
            }
            drivers.clear();
            for j in joins.drain(..) {
                if let Some((hero, ticket)) = j.who {
                    send_msg(HostMsg::Unused { hero, ticket });
                }
            }
            for (_, (e, _)) in pending.drain() {
                send_msg(HostMsg::Unused { hero: e.hero, ticket: e.ticket });
            }
        }
        pending.retain(|_, (e, at)| {
            let keep = at.elapsed() < opts.ticket_ttl;
            if !keep {
                send_msg(HostMsg::Unused { hero: e.hero, ticket: e.ticket });
            }
            keep
        });
        // Read everything that arrived.
        for (from, msg) in inbox.drain(..) {
            let mut r = Rd::new(&msg);
            match r.u8() {
                Some(MSG_HELLO) if stopping.is_none() => {
                    hellos += 1;
                    let Some(hello) = parse_hello(&mut r) else { continue };
                    let Hello { proto, class, race, ticket, proof } = hello;
                    if let Some(c) = clients.get(&from) {
                        // A repeated HELLO: the WELCOME was lost. A ticketed one must prove the key again, with the
                        // same nonce (a HELLO seen on the wire and replayed from here only repeats the WELCOME).
                        let same = match &c.key {
                            None => true,
                            Some(k) => hello_proves(k, &hello) && proof.is_some_and(|p| p.0 == c.nonce),
                        };
                        if let (Some(id), true) = (c.id, same) {
                            if sock.send_to(&welcome(id as u32, sim.field.tick(), c.key.as_ref().map(|k| (k, c.nonce))), from).is_err() {
                                send_errors += 1;
                            }
                        }
                        continue;
                    }
                    let mut who: Option<(u64, u64)> = None;
                    let mut req: Option<JoinReq> = None;
                    let (mut seq, mut moved_in) = (0u32, false);
                    let mut proved: Option<(TicketKey, u64)> = None;
                    if proto != PROTO_B {
                        if opts.require_tickets {
                            // The ticket names her; only proof of its key lets her in. A wrong proof leaves the ticket
                            // waiting, so a stranger who guessed a ticket number cannot burn it either.
                            let ok = pending.get(&ticket).is_some_and(|(e, _)| hello_proves(&e.key, &hello));
                            if !ok {
                                refused += 1;
                                continue;
                            }
                            let Some((e, _)) = pending.remove(&ticket) else { continue };
                            let (x, y) = arrival(&sim.field, &e, &mut rng);
                            who = Some((e.hero, e.ticket));
                            seq = e.seq;
                            moved_in = e.arrive.is_some();
                            proved = proof.map(|p| (e.key, p.0));
                            req = Some(JoinReq { sheet: e.sheet, outing: e.outing, x, y, guild: e.guild });
                        } else {
                            let rr = realm_core::rng_next(&mut rng);
                            let x = FIELD / 2 + ((rr % 400) as i32 - 200) * SUB;
                            let y = FIELD / 2 + (((rr >> 20) % 400) as i32 - 200) * SUB;
                            // The HELLO's class is 0..4 (KNIGHT to PALADIN); the core's class 0 is the NOVICE.
                            req = Some(JoinReq { sheet: Sheet::bench(1 + class.min(4), race.min(3), sim.bench_level()), outing: Outing::new(), x, y, guild: 0 });
                        }
                    } else if !opts.allow_followers || opts.require_tickets {
                        // A follower takes no ticket, so a ticketed field has none (the state stream it would send
                        // to any address is a flood tool).
                        refused += 1;
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
                        key: proved.map(|p| p.0),
                        nonce: proved.map_or(0, |p| p.1),
                        counter: 0,
                    };
                    if let Some(rq) = req {
                        joins.push(sim_join::Req { addr: Some(from), req: rq, who, seq, drive: None, moved_in });
                    }
                    clients.insert(from, c);
                }
                // A ticketed field takes a player's INPUT and BYE only sealed with her key (a right tag and a
                // counter above the last), from the address that proved her ticket; a crowd-test server takes them
                // bare too.
                Some(t @ (MSG_INPUT | MSG_SEALED_INPUT | MSG_BYE | MSG_SEALED_BYE)) => {
                    let Some(c) = clients.get_mut(&from) else {
                        refused += 1;
                        continue;
                    };
                    let sealed = matches!(t, MSG_SEALED_INPUT | MSG_SEALED_BYE);
                    if sealed {
                        let opened = c.key.as_ref().and_then(|k| unseal(k, &msg)).filter(|(n, _)| *n > c.counter);
                        let Some((n, body)) = opened else {
                            refused += 1;
                            continue;
                        };
                        c.counter = n;
                        r = Rd::new(body);
                    } else if opts.require_tickets || c.key.is_some() {
                        refused += 1;
                        continue;
                    }
                    if matches!(t, MSG_INPUT | MSG_SEALED_INPUT) {
                        if let Some(m) = parse_input(&mut r) {
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
                    } else if let Some(c) = clients.remove(&from) {
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
            let keep = c.heard.elapsed() < TIMEOUT && stopping.is_none();
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
                        let why = stopping.unwrap_or(Leave::Disconnect);
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
        let mut inputs: Vec<(u16, u16)> = clients.values().filter_map(|c| c.id.map(|id| (id, c.input))).collect();
        inputs.extend(driven_inputs.into_iter().filter(|(id, _)| !leaves.contains(id)));
        // The realm's clock: a field copy follows it (a vault keeps its own).
        if vault_row.is_none() {
            if let Some(c) = &opts.clock {
                sim.next_clock = clock_fix(sim.field.clock(), c.now());
            }
        }
        let mut row = [0f64; NCOL];
        let t0 = Instant::now();
        let reqs: Vec<JoinReq> = joins.iter().map(|j| j.req.clone()).collect();
        let ids = sim.tick(&reqs, &leaves, &inputs, &mut row);
        let tick = sim.field.tick();
        members_dirty |= !leaves.is_empty() || !joins.is_empty();
        for (j, id) in joins.iter().zip(ids) {
            if let Some(c) = j.addr.and_then(|a| clients.get_mut(&a)) {
                c.id = Some(id);
                if sock.send_to(&welcome(id as u32, tick, c.key.as_ref().map(|k| (k, c.nonce))), j.addr.unwrap_or(([0, 0, 0, 0], 0).into())).is_err() {
                    send_errors += 1;
                }
            }
            if let Some((hero, ticket)) = j.who {
                let belt_ids = sim.field.players().get(id as usize).map_or([realm_core::tables::P_NONE; 3], |h| h.belt.map(|b| b.0));
                let (marked, struck) = sim.field.players().get(id as usize).map_or((false, realm_core::tables::NEVER), |h| (h.marked, h.last_struck));
                tallies.insert(id, Tally { hero, ticket, seq: j.seq, belt_ids, xp: 0, coin: 0, potions: [0; 6], waystone: None, fell: 0, lost: 0, plunders: Vec::new(), debts: VecDeque::new(), banked: false, urgent: false, gate: false, last_flush: tick, marked, struck, mark_dirty: false });
                if let Some(d) = &j.drive {
                    drivers.insert(id, Driver::new(id, d, tick, vault_row.is_some()));
                }
                counts.joined += 1;
                counts.moved_in += j.moved_in as u32;
                send_msg(HostMsg::Joined { hero, ticket, id });
            }
        }
        // What the tick's events did to the heroes' tallies; leaves last, so a hero's other events count.
        collect(&sim.field, &mut tallies, &mut clients, &mut finals);
        for e in sim.field.events() {
            if let Event::Leave { hero } = *e {
                drivers.remove(&hero);
                members_dirty = true;
            }
        }
        let rewards = tally_realm(&sim.field, &tallies, &mut counts);
        // Job R3b: a war's end in this copy goes to the gateway, which adds up every copy's held ticks.
        for e in sim.field.events() {
            if let Event::War { war, state: WAR_END, held, .. } = *e {
                send_msg(HostMsg::War { host: opts.id, war, held, over: true });
            }
        }
        // A vault closes a while after its run ends, or when nobody came, or past its guard.
        if let Some(row) = vault_row {
            let run = sim.field.vault().map_or(RUN_GOING, |v| v.state);
            if run != RUN_GOING {
                vault_over.get_or_insert(tick);
            }
            let limit = row.minutes as u32 * 1_200 + VAULT_OVERTIME + VAULT_GUARD_TICKS;
            let empty = sim.field.player_count() == 0 && pending.is_empty() && joins.is_empty();
            let nobody_came = empty && sim.field.vault().is_some_and(|v| v.started == 0) && tick >= VAULT_EMPTY_TICKS;
            let all_gone = empty && sim.field.vault().is_some_and(|v| v.started > 0);
            if vault_over.is_some_and(|t| tick >= t + VAULT_LINGER_TICKS) || nobody_came || all_gone || sim.field.vault_ticks() > limit {
                stopping.get_or_insert(Leave::Vault);
            }
            status.vault.store(run, Ordering::Relaxed);
        }
        status.heroes.store(sim.field.player_count(), Ordering::Relaxed);
        status.pending.store(pending.len() as u32, Ordering::Relaxed);
        status.refused.store(refused, Ordering::Relaxed);
        status.tick.store(tick, Ordering::Relaxed);
        status.clock.store(sim.field.clock(), Ordering::Relaxed);
        status.tide.store(sim.field.tide(), Ordering::Relaxed);
        status.boss.store(sim.field.boss().is_some(), Ordering::Relaxed);
        if members_dirty {
            let mut m: Vec<u64> = tallies.values().map(|t| t.hero).collect();
            m.sort_unstable();
            *status.members.lock().unwrap() = m;
            *status.counts.lock().unwrap() = counts.clone();
            members_dirty = false;
        } else if tick % 20 == 0 {
            *status.counts.lock().unwrap() = counts.clone();
        }
        for t in tallies.values_mut() {
            if t.urgent || (t.xp > 0 && tick.saturating_sub(t.last_flush) >= XP_FLUSH_TICKS) {
                finals.push(t.take(tick, None));
            }
        }
        for f in finals {
            send_msg(HostMsg::Flush(f));
        }
        // A moved hero's message follows her last flush.
        for m in moved {
            send_msg(m);
        }
        if msgs.is_some() && !tallies.is_empty() {
            if let Some(mut b) = kill_batch(&sim.field, &tallies) {
                b.host = opts.id;
                send_msg(HostMsg::Kills(b));
            }
        }
        for mut r in rewards {
            r.host = opts.id;
            send_msg(HostMsg::Reward(r));
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
                        if sock.send_to(&welcome(id, tick, c.key.as_ref().map(|k| (k, c.nonce))), addr).is_err() {
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
        realm_ops::metrics::tick(opts.sim.field, row[C_TOTAL]);
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
            eprintln!("net clients={} received={received} hellos={hellos} refused={refused} send_errors={send_errors}", clients.len());
            w = Window::default();
        } else if opts.report_secs == 0 && w.ticks.len() >= 400 {
            w = Window::default();
        }
        if stopping.is_some() && tallies.is_empty() && joins.is_empty() {
            *status.counts.lock().unwrap() = counts.clone();
            status.members.lock().unwrap().clear();
            status.heroes.store(0, Ordering::Relaxed);
            // A copy closed during a war (into another copy): what it held so far still counts.
            for w in sim.field.wars().iter().filter(|w| w.on) {
                send_msg(HostMsg::War { host: opts.id, war: w.id, held: w.held, over: false });
            }
            send_msg(HostMsg::Closed { host: opts.id });
            break 'ticks;
        }
    }
}

mod sim_join {
    use super::*;
    /// A hero joining this tick: from a HELLO (`addr`), or played by the host.
    pub struct Req {
        pub addr: Option<SocketAddr>,
        pub req: JoinReq,
        pub who: Option<(u64, u64)>,
        /// Her ticket's flush number so far.
        pub seq: u32,
        pub drive: Option<Drive>,
        pub moved_in: bool,
    }
}

/// The tick's tide, boss and reward events: counted, and each REWARD's ticketed heroes for the gateway's chests.
fn tally_realm(field: &Field, tallies: &HashMap<u16, Tally>, counts: &mut HostCounts) -> Vec<RewardBatch> {
    let mut out = Vec::new();
    let mut killed = u8::MAX;
    for (index, e) in field.events().iter().enumerate() {
        match *e {
            Event::Tide { state, .. } => match state {
                TIDE_BEGIN => counts.tides += 1,
                TIDE_WON => counts.tides_won += 1,
                TIDE_LOST => counts.tides_lost += 1,
                _ => {}
            },
            Event::Boss { which, state, .. } => match state {
                BOSS_RISES => {
                    counts.bosses += 1;
                    counts.world_bosses += (which == B_DEATH) as u32;
                }
                BOSS_KILLED => {
                    counts.bosses_killed += 1;
                    killed = which;
                }
                BOSS_LEFT => counts.bosses_left += 1,
                _ => {}
            },
            Event::War { state, .. } => {
                if state == WAR_END {
                    counts.wars_ended += 1;
                } else {
                    counts.wars_begun += 1;
                }
            }
            Event::Reward { kind, source, level, seals, first, count } => {
                counts.rewards += 1;
                let heroes: Vec<(Credited, u32)> = field
                    .rewarded(first, count)
                    .iter()
                    .filter_map(|&(slot, c)| tallies.get(&slot).map(|t| (Credited { hero: t.hero, ticket: t.ticket, slot, luck: field.luck(slot) }, c)))
                    .collect();
                if !heroes.is_empty() {
                    let vault = field.vault().map_or(u8::MAX, |v| v.vault);
                    let boss = if kind == R_BOSS_CHEST { killed } else { u8::MAX };
                    out.push(RewardBatch { host: 0, field_seed: field.seed(), tick: field.tick(), index: index as u32, kind, source, level, seals, boss, vault, heroes });
                }
            }
            _ => {}
        }
    }
    out
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
    (!kills.is_empty()).then(|| KillBatch { host: 0, field_seed: field.seed(), tick: field.tick(), kills })
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
            // Section 14 (job R3): the mark taken or put down, and her strikes on heroes, go home with her.
            Event::Mark { hero, .. } => {
                if let Some(t) = tallies.get_mut(&hero) {
                    t.marked = field.players().get(hero as usize).is_some_and(|h| h.marked);
                    t.mark_dirty = true;
                }
            }
            Event::Struck { by, .. } => {
                if let Some(t) = tallies.get_mut(&by) {
                    t.struck = tick;
                    t.mark_dirty = true;
                }
            }
            Event::Fallen { hero, coin } => {
                if let Some(t) = tallies.get_mut(&hero) {
                    t.fell += 1;
                    t.lost += coin as u64;
                    t.urgent = true;
                }
            }
            // Job R3b: the core sends `Plunder` right after her `Fallen`. A plunderer still in the field (as the core
            // reads it) with a ticket gets what that fall took from her haul.
            Event::Plunder { hero, by, coin } => {
                let present = field.players().get(by as usize).is_some_and(|h| h.present);
                let winner = tallies.get(&by).filter(|_| present).map(|w| (w.hero, w.ticket));
                let mut victim = None;
                if let (Some((by_hero, by_ticket)), Some(t)) = (winner, tallies.get_mut(&hero)) {
                    if t.fell > 0 && by_hero != t.hero {
                        t.plunders.push(Plundered { fall: t.fell - 1, by_hero, by_ticket, coin: coin as u64 });
                        victim = Some(t.hero);
                    }
                }
                // The coin is in his haul now; when he banks it, it is banked as hers moved to him.
                if let (Some(v), Some(w)) = (victim, tallies.get_mut(&by)) {
                    if coin > 0 {
                        w.debts.push_back((v, coin as u64));
                    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use realm_core::Config;

    #[test]
    fn a_transfer_read_from_the_field_is_the_cores_and_lands_the_same_hero() {
        let cfg = Config { monsters: 300, threads: 1 };
        let mut a = Field::open(1, 9, cfg.clone());
        let mut b = Field::open(1, 10, cfg.clone());
        let mut a2 = Field::open(1, 9, cfg.clone());
        let mut b2 = Field::open(1, 10, cfg.clone());
        let mut o = Outing::new();
        o.coin = 77;
        o.draws = 3;
        let (x, y) = a.ring_point(realm_core::tables::RING_MIDDLE, 4);
        let ia = a.join(&Sheet::bench(2, 1, 30), &o, x, y);
        let ia2 = a2.join(&Sheet::bench(2, 1, 30), &o, x, y);
        for _ in 0..40 {
            a.step::<u16>(&[3]);
            a2.step::<u16>(&[3]);
            b.step::<u16>(&[]);
            b2.step::<u16>(&[]);
        }
        let mine = transfer_of(&a, ia).unwrap();
        let core = a2.transfer_out(ia2).unwrap();
        assert_eq!(mine, core);
        a.leave(ia);
        assert_eq!(a.hash(), a2.hash(), "a leave is the core's transfer_out");
        let (x, y) = b.ring_point(mine.ring, 42);
        let ib = b.join(&mine.sheet, &mine.outing, x, y);
        let ib2 = b2.transfer_in(&core, 42);
        assert_eq!(ib, ib2);
        assert_eq!(b.hash(), b2.hash(), "a join at ring_point is the core's transfer_in");
        assert_eq!(b.outing(ib).map(|o| o.coin), Some(77));
    }

    fn host(field: u8, vault: Option<(u8, u8)>, tx: &Sender<HostMsg>, clock: &RealmClock, id: u32) -> HostHandle {
        let sim = SimOpts { field, seed: 5 + id as u64, monsters: 300, threads: 1, bots: 0, rally_permille: 0, level: 0, vault };
        spawn(HostOpts { sim, port: 0, require_tickets: true, clock: Some(clock.clone()), tick_us: 1_000, id, ..HostOpts::default() }, Some(tx.clone())).unwrap()
    }

    fn wait<T>(rx: &Receiver<HostMsg>, secs: u64, mut pick: impl FnMut(HostMsg) -> Option<T>) -> T {
        let end = Instant::now() + Duration::from_secs(secs);
        loop {
            let left = end.saturating_duration_since(Instant::now());
            assert!(!left.is_zero(), "timed out");
            if let Ok(m) = rx.recv_timeout(left) {
                if let Some(t) = pick(m) {
                    return t;
                }
            }
        }
    }

    #[test]
    fn a_driven_hero_moves_between_copies_with_her_state_and_her_flush_numbers_go_on() {
        let (tx, rx) = channel();
        let clock = RealmClock::manual(5_000);
        let mut a = host(0, None, &tx, &clock, 1);
        let mut b = host(0, None, &tx, &clock, 2);
        let mut e = Entry::new(77, 7, Sheet::bench(1, 0, 12), Outing::new());
        e.drive = Some(Drive { seed: 3, ticks: 100_000 });
        a.cmds.send(HostCmd::Admit(e)).unwrap();
        wait(&rx, 10, |m| matches!(m, HostMsg::Joined { hero: 7, .. }).then_some(()));
        let members = |h: &HostHandle| h.status.members.lock().unwrap().clone();
        let settle = |h: &HostHandle, want: Vec<u64>| {
            let end = Instant::now() + Duration::from_secs(5);
            while members(h) != want && Instant::now() < end {
                std::thread::sleep(Duration::from_millis(2));
            }
            members(h) == want
        };
        assert!(settle(&a, vec![7]), "the status lists her once the tick is done");
        // The field follows the realm clock.
        let end = Instant::now() + Duration::from_secs(5);
        while a.status.clock.load(Ordering::Relaxed).abs_diff(5_000) > crate::realm_clock::CLOCK_SLACK + 1 && Instant::now() < end {
            std::thread::sleep(Duration::from_millis(5));
        }
        assert!(a.status.clock.load(Ordering::Relaxed).abs_diff(5_000) <= crate::realm_clock::CLOCK_SLACK + 1);
        a.cmds.send(HostCmd::MoveOut(7)).unwrap();
        let mut seq_seen = 0;
        let (seq, tr, driven) = wait(&rx, 10, |m| match m {
            HostMsg::Flush(f) => {
                assert!(f.left.is_none(), "a move is not a leave");
                seq_seen = f.seq;
                None
            }
            HostMsg::Moved { hero: 7, ticket: 77, seq, transfer, driven, host: 1 } => Some((seq, transfer, driven)),
            _ => None,
        });
        assert_eq!(seq, seq_seen, "the Moved names the last flush");
        assert!(driven.is_some());
        let mut e = Entry::new(77, 7, tr.sheet.clone(), tr.outing.clone());
        e.seq = seq;
        e.arrive = Some(tr.ring);
        e.drive = driven;
        b.cmds.send(HostCmd::Admit(e)).unwrap();
        wait(&rx, 10, |m| matches!(m, HostMsg::Joined { hero: 7, .. }).then_some(()));
        assert!(settle(&b, vec![7]));
        assert!(members(&a).is_empty(), "never in two copies");
        b.cmds.send(HostCmd::Stop).unwrap();
        let f = wait(&rx, 10, |m| match m {
            HostMsg::Flush(f) if f.left.is_some() => Some(f),
            _ => None,
        });
        assert_eq!(f.left, Some(Leave::Shutdown));
        assert_eq!(f.seq, seq + 1, "the second copy numbers on");
        wait(&rx, 10, |m| matches!(m, HostMsg::Closed { host: 2 }).then_some(()));
        b.reap();
        assert!(b.status.ended.load(Ordering::Relaxed));
        assert_eq!(b.status.counts.lock().unwrap().moved_in, 1);
        a.cmds.send(HostCmd::Abort).unwrap();
        a.reap();
        assert!(a.status.ended.load(Ordering::Relaxed), "an aborted host is seen to have ended");
    }

    #[test]
    fn a_vault_takes_a_party_of_eight_and_one_nobody_enters_closes_itself() {
        let (tx, rx) = channel();
        let clock = RealmClock::manual(0);
        let mut v = host(2, Some((0, 1)), &tx, &clock, 9);
        assert_eq!(v.status.vault.load(Ordering::Relaxed), RUN_GOING);
        for k in 0..9u64 {
            let mut e = Entry::new(100 + k, k, Sheet::bench(1, 0, 20), Outing::new());
            e.drive = Some(Drive { seed: k, ticks: 1_000_000 });
            v.cmds.send(HostCmd::Admit(e)).unwrap();
        }
        let refused = wait(&rx, 10, |m| match m {
            HostMsg::Unused { hero, .. } => Some(hero),
            _ => None,
        });
        assert_eq!(refused, 8, "the ninth of a party of eight is turned away");
        std::thread::sleep(Duration::from_millis(100));
        assert_eq!(v.heroes(), 8);
        v.cmds.send(HostCmd::Stop).unwrap();
        let mut finals = 0;
        wait(&rx, 10, |m| match m {
            HostMsg::Flush(f) if f.left == Some(Leave::Shutdown) => {
                finals += 1;
                None
            }
            HostMsg::Closed { host: 9 } => Some(()),
            _ => None,
        });
        assert_eq!(finals, 8);
        v.reap();
        let mut empty = host(3, Some((1, 0)), &tx, &clock, 10);
        wait(&rx, 20, |m| matches!(m, HostMsg::Closed { host: 10 }).then_some(()));
        empty.reap();
        assert!(empty.status.ended.load(Ordering::Relaxed));
    }

    #[test]
    fn a_reward_event_names_its_ticketed_heroes_and_the_tide_and_boss_events_are_counted() {
        let mut f = Field::open_vault(0, 0, 4, Config { monsters: 400, threads: 1 });
        let (hx, hy) = f.terrain().heart;
        let id = f.join(&Sheet::bench(0, 0, 1), &Outing::new(), hx, hy);
        let mut tallies = HashMap::new();
        tallies.insert(id, Tally { hero: 70, ticket: 700, seq: 0, belt_ids: [0; 3], xp: 0, coin: 0, potions: [0; 6], waystone: None, fell: 0, lost: 0, plunders: Vec::new(), debts: VecDeque::new(), banked: false, urgent: false, gate: false, last_flush: 0, marked: false, struck: realm_core::tables::NEVER, mark_dirty: false });
        let mut counts = HostCounts::default();
        let mut got = Vec::new();
        for _ in 0..20_000 {
            f.step::<u16>(&[0]);
            got.extend(tally_realm(&f, &tallies, &mut counts));
            if f.vault().is_some_and(|v| v.state != RUN_GOING) {
                break;
            }
        }
        assert_ne!(f.vault().unwrap().state, RUN_GOING, "a novice standing still in a level 20 vault falls");
        assert_eq!(got.len(), 1, "{got:?}");
        let r = &got[0];
        assert_eq!(r.kind, realm_core::tables::R_VAULT_LOSS);
        assert_eq!(r.vault, 0);
        assert_eq!(r.heroes.len(), 1);
        assert_eq!((r.heroes[0].0.hero, r.heroes[0].0.ticket, r.heroes[0].0.slot), (70, 700, id));
        assert_eq!(counts.rewards, 1);
        // In a field: a tide and a boss on the clock are counted once each.
        let mut g = Field::open(0, 4, Config { monsters: 200, threads: 1 });
        let mut c = HostCounts::default();
        g.set_clock(realm_core::tide_start(0, 3) - 2);
        for _ in 0..5 {
            g.step::<u16>(&[]);
            tally_realm(&g, &HashMap::new(), &mut c);
        }
        g.set_clock(realm_core::field_boss_window(0, 3).0 - 2);
        for _ in 0..5 {
            g.step::<u16>(&[]);
            tally_realm(&g, &HashMap::new(), &mut c);
        }
        assert_eq!((c.tides, c.tides_lost, c.bosses), (1, 1, 1));
    }

    /// Job R3b: a plundered fall reaches the flush with its fall number and the hero who downed her, once.
    #[test]
    fn a_plundered_fall_names_its_plunderer_in_the_victims_flush() {
        let mut f = Field::open(3, 1, Config { monsters: 4096, threads: 1 });
        f.set_births(false);
        let (cx, cy) = f.terrain().heart;
        let (x, y) = (0..400)
            .map(|k| (cx + (k % 20 - 10) * 300 * SUB, cy + (k / 20 - 10) * 300 * SUB))
            .find(|&(x, y)| !f.safe_ground(x, y) && !f.terrain().wall(x, y) && !f.terrain().wall(x + 40 * SUB, y) && !f.terrain().wall(x - 40 * SUB, y) && !f.terrain().wall(x + 20 * SUB, y))
            .expect("an open spot");
        let marked = Outing { marked: true, ..Outing::new() };
        // No PHOENIX ASH on the belt: she must fall.
        let mut sheet = Sheet::bench(1, 0, 30);
        sheet.belt = [(realm_core::tables::P_NONE, 0); 3];
        let a = f.join(&sheet, &marked, x, y);
        let b = f.join(&sheet, &marked, x + 20 * SUB, y);
        f.hero_mut(b).coin = 500;
        f.hero_mut(b).health = 1;
        let tally = |hero: u64, ticket: u64| Tally { hero, ticket, seq: 0, belt_ids: [0; 3], xp: 0, coin: 0, potions: [0; 6], waystone: None, fell: 0, lost: 0, plunders: Vec::new(), debts: VecDeque::new(), banked: false, urgent: false, gate: false, last_flush: 0, marked: true, struck: realm_core::tables::NEVER, mark_dirty: false };
        let mut tallies = HashMap::new();
        tallies.insert(a, tally(10, 100));
        tallies.insert(b, tally(20, 200));
        let (mut clients, mut finals) = (HashMap::new(), Vec::new());
        let mut slain = false;
        for _ in 0..400 {
            f.step::<u16>(&[]);
            collect(&f, &mut tallies, &mut clients, &mut finals);
            if f.downed_by(b) == a {
                slain = true;
                break;
            }
        }
        assert!(slain, "a downs b");
        // He walks off, so he does not raise her; she falls.
        let (bx, by) = (f.players()[b as usize].x, f.players()[b as usize].y);
        f.hero_mut(a).x = bx + 300 * SUB;
        f.hero_mut(a).y = by;
        for _ in 0..2_000 {
            f.step::<u16>(&[]);
            collect(&f, &mut tallies, &mut clients, &mut finals);
            if tallies[&b].fell > 0 {
                break;
            }
        }
        let fl = tallies.get_mut(&b).unwrap().take(f.tick(), None);
        assert_eq!(fl.fell, 1);
        assert_eq!(fl.plunders, vec![Plundered { fall: 0, by_hero: 10, by_ticket: 100, coin: 250 }]);
        let again = tallies.get_mut(&b).unwrap().take(f.tick(), None);
        assert!(again.plunders.is_empty(), "sent once");
        // The coin is in his haul; when he banks, the first 250 of it are hers moved to him.
        let w = tallies.get_mut(&a).unwrap();
        w.coin = 300;
        let wf = w.take(f.tick(), None);
        assert!(wf.plunders.is_empty(), "the plunderer's own flush names no fall");
        assert_eq!((wf.coin, wf.plunder_coin.clone()), (50, vec![(20, 250)]));
        let w = tallies.get_mut(&a).unwrap();
        w.coin = 70;
        let wf = w.take(f.tick(), None);
        assert_eq!((wf.coin, wf.plunder_coin), (70, vec![]), "paid once");
    }
}
