//! The simulation off the main thread. One worker thread owns the socket and the lockstep client: it reads
//! datagrams, applies every tick that has arrived (the core's whole step), predicts the own hero, and after
//! each batch of ticks builds a `Frame` (`frame.rs`) and leaves it in a slot. The main thread (the game's
//! frame) only takes the newest finished frame, so a slow tick never stalls drawing: the screen shows the
//! latest finished state.
//!
//! Main to worker: `Cmd`s on a channel (inputs, close) and the view rectangle in atomics. Worker to main:
//! the frame slot, the hero's pose, and the counters, each behind its own small lock.

use crate::draw::{DrawState, SubRect};
use crate::frame::{self, Frame};
use realm_core::FIELD;
use realm_server::client::LockstepClient;
use std::io::ErrorKind;
use std::net::UdpSocket;
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU32, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender, TryRecvError};
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

/// HELLO is repeated this often until the server answers.
const HELLO_EVERY: Duration = Duration::from_millis(500);
/// The socket is read until empty, but at most this many datagrams a pass (a join burst spreads over passes).
const READS_PER_PASS: usize = 4096;
/// The worker sleeps this long when nothing arrived.
const IDLE: Duration = Duration::from_millis(1);
/// The counters are refreshed this often.
const COUNTERS_EVERY: Duration = Duration::from_millis(100);

#[derive(Clone, Copy, Debug)]
pub enum Num {
    Int(i64),
    Float(f64),
}

/// Counters for GDScript: name and value, in a fixed order.
pub type Counters = Vec<(&'static str, Num)>;

pub enum Cmd {
    /// The core's two-byte input (`realm_core::input`), 20 times a second.
    Input(u16),
    Close,
}

/// The own hero at the latest input: where to draw her, and the plain prediction (px).
#[derive(Clone, Copy, Debug, Default)]
pub struct Pose {
    pub shown: (f32, f32),
    pub predicted: (f32, f32),
    /// Counts up on every change, so the main thread notices a new target.
    pub version: u32,
}

pub struct Shared {
    frame: Mutex<Option<Frame>>,
    applied: AtomicU32,
    view: [AtomicI32; 4],
    pose: Mutex<Pose>,
    counters: Mutex<Counters>,
    welcomed: AtomicBool,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    // A panic in the worker must not take the game's frame down with it.
    m.lock().unwrap_or_else(|e| e.into_inner())
}

impl Shared {
    fn new() -> Shared {
        Shared {
            frame: Mutex::new(None),
            applied: AtomicU32::new(0),
            view: [AtomicI32::new(0), AtomicI32::new(0), AtomicI32::new(FIELD), AtomicI32::new(FIELD)],
            pose: Mutex::new(Pose::default()),
            counters: Mutex::new(Vec::new()),
            welcomed: AtomicBool::new(false),
        }
    }

    fn view(&self) -> SubRect {
        let v = |i: usize| self.view[i].load(Ordering::Relaxed);
        SubRect { x0: v(0), y0: v(1), x1: v(2), y1: v(3) }
    }
}

/// The handle the main thread holds.
pub struct Worker {
    shared: Arc<Shared>,
    tx: Sender<Cmd>,
    thread: Option<JoinHandle<()>>,
}

impl Worker {
    pub fn start(sock: UdpSocket, client: LockstepClient) -> Worker {
        let shared = Arc::new(Shared::new());
        let (tx, rx) = channel();
        let s = shared.clone();
        let thread = std::thread::Builder::new().name("realm-sim".into()).spawn(move || run(sock, client, s, rx)).ok();
        Worker { shared, tx, thread }
    }

    pub fn send(&self, input: u16) {
        let _ = self.tx.send(Cmd::Input(input));
    }

    /// The rectangle (1/256 px) the draw buffers cover from the next frame on.
    pub fn set_view(&self, r: SubRect) {
        for (a, v) in self.shared.view.iter().zip([r.x0, r.y0, r.x1, r.y1]) {
            a.store(v, Ordering::Relaxed);
        }
    }

    /// The newest finished frame and how many ticks were applied since the last take, if there is a new one.
    pub fn take(&self) -> Option<(Frame, u32)> {
        let f = lock(&self.shared.frame).take()?;
        Some((f, self.shared.applied.swap(0, Ordering::AcqRel)))
    }

    pub fn pose(&self) -> Pose {
        *lock(&self.shared.pose)
    }

    pub fn counters(&self) -> Counters {
        lock(&self.shared.counters).clone()
    }

    pub fn welcomed(&self) -> bool {
        self.shared.welcomed.load(Ordering::Relaxed)
    }
}

impl Drop for Worker {
    fn drop(&mut self) {
        let _ = self.tx.send(Cmd::Close);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}

/// Bytes in and out over the last whole second.
#[derive(Default)]
struct Rates {
    since: Option<Instant>,
    bytes_in: u64,
    bytes_out: u64,
    sim: Duration,
    ticks: u64,
    in_per_sec: f64,
    out_per_sec: f64,
    sim_ms_per_tick: f64,
    build_ms: f64,
}

impl Rates {
    fn roll(&mut self, now: Instant) {
        let since = *self.since.get_or_insert(now);
        let dt = now - since;
        if dt >= Duration::from_secs(1) {
            let s = dt.as_secs_f64();
            self.in_per_sec = self.bytes_in as f64 / s;
            self.out_per_sec = self.bytes_out as f64 / s;
            self.sim_ms_per_tick = if self.ticks == 0 { 0.0 } else { self.sim.as_secs_f64() * 1000.0 / self.ticks as f64 };
            self.since = Some(now);
            (self.bytes_in, self.bytes_out, self.sim, self.ticks) = (0, 0, Duration::ZERO, 0);
        }
    }
}

fn pose_of(c: &LockstepClient) -> (f32, f32, f32, f32) {
    let px = |p: Option<(i32, i32)>| p.map_or((0.0, 0.0), |(x, y)| (x as f32 / realm_core::SUB as f32, y as f32 / realm_core::SUB as f32));
    let (s, p) = (px(c.predictor().shown()), px(c.predictor().predicted()));
    (s.0, s.1, p.0, p.1)
}

fn counters(c: &LockstepClient, r: &Rates) -> Counters {
    let (st, p) = (&c.stats, c.predictor());
    vec![
        ("bytes_in_per_sec", Num::Float(r.in_per_sec)),
        ("bytes_out_per_sec", Num::Float(r.out_per_sec)),
        ("sim_ms_per_tick", Num::Float(r.sim_ms_per_tick)),
        ("frame_build_ms", Num::Float(r.build_ms)),
        ("ticks_applied", Num::Int(st.ticks_applied as i64)),
        ("hash_checks_passed", Num::Int(st.hash_ok as i64)),
        ("hash_checks_failed", Num::Int(st.hash_bad as i64)),
        ("sim_ms_last", Num::Float(st.sim_last.as_secs_f64() * 1000.0)),
        ("stall_ms_max", Num::Float(st.stall_max.as_secs_f64() * 1000.0)),
        ("join_bytes", Num::Int(st.join_bytes as i64)),
        ("join_tick", Num::Int(i64::from(st.join_tick))),
        ("mispredicts", Num::Int(p.mispredicts as i64)),
        ("predictions_checked", Num::Int(p.confirms as i64)),
        ("unconfirmed_inputs", Num::Int(p.unconfirmed() as i64)),
        ("bad_datagrams", Num::Int(st.bad_datagrams as i64)),
    ]
}

fn run(sock: UdpSocket, mut client: LockstepClient, shared: Arc<Shared>, rx: Receiver<Cmd>) {
    let send = |sock: &UdpSocket, rates: &mut Rates, b: &[u8]| {
        // A full send buffer or an unreachable server is the same as a lost datagram: the protocol repeats.
        if sock.send(b).is_ok() {
            rates.bytes_out += b.len() as u64;
        }
    };
    let mut rates = Rates::default();
    let mut draw = DrawState::default();
    let mut hello_at = Instant::now();
    let mut counters_at = Instant::now();
    let mut announced = false;
    let mut buf = [0u8; 2048];
    let hello = client.hello();
    send(&sock, &mut rates, &hello);
    'main: loop {
        loop {
            match rx.try_recv() {
                Ok(Cmd::Input(input)) => {
                    if client.welcomed() {
                        let d = client.input_word(input);
                        send(&sock, &mut rates, &d);
                        let (sx, sy, px, py) = pose_of(&client);
                        let mut p = lock(&shared.pose);
                        *p = Pose { shown: (sx, sy), predicted: (px, py), version: p.version + 1 };
                    }
                }
                Ok(Cmd::Close) | Err(TryRecvError::Disconnected) => break 'main,
                Err(TryRecvError::Empty) => break,
            }
        }
        let now = Instant::now();
        if !client.welcomed() && now >= hello_at {
            hello_at = now + HELLO_EVERY;
            let hello = client.hello();
            send(&sock, &mut rates, &hello);
        }
        let mut got = false;
        for _ in 0..READS_PER_PASS {
            match sock.recv(&mut buf) {
                Ok(n) => {
                    got = true;
                    rates.bytes_in += n as u64;
                    client.receive(&buf[..n]);
                }
                // Windows reports an ICMP "port unreachable" (no server yet) as an error on the next read.
                Err(e) if e.kind() == ErrorKind::ConnectionReset => {}
                Err(_) => break,
            }
        }
        shared.welcomed.store(client.welcomed(), Ordering::Relaxed);
        let sim0 = client.stats.sim;
        let n = client.apply();
        rates.sim += client.stats.sim - sim0;
        rates.ticks += u64::from(n);
        let first = !announced && client.field().is_some();
        if n > 0 || first {
            announced = true;
            let t0 = Instant::now();
            let f = frame::build(&client, shared.view(), &mut draw);
            rates.build_ms = t0.elapsed().as_secs_f64() * 1000.0;
            let (sx, sy, px, py) = pose_of(&client);
            {
                let mut p = lock(&shared.pose);
                if p.shown != (sx, sy) || p.predicted != (px, py) {
                    *p = Pose { shown: (sx, sy), predicted: (px, py), version: p.version + 1 };
                }
            }
            *lock(&shared.frame) = Some(f);
            shared.applied.fetch_add(n, Ordering::AcqRel);
        }
        rates.roll(now);
        if now.duration_since(counters_at) >= COUNTERS_EVERY {
            counters_at = now;
            *lock(&shared.counters) = counters(&client, &rates);
        }
        if !got && n == 0 {
            std::thread::sleep(IDLE);
        }
    }
    *lock(&shared.counters) = counters(&client, &rates);
    // Sealed with the session token on a ticketed field, so the host believes it.
    let _ = sock.send(&client.bye());
}

#[cfg(test)]
mod tests {
    use super::*;
    use realm_core::input;

    #[test]
    fn a_worker_without_a_server_runs_and_stops() {
        let s = UdpSocket::bind("127.0.0.1:0").unwrap();
        let server = UdpSocket::bind("127.0.0.1:0").unwrap();
        s.connect(server.local_addr().unwrap()).unwrap();
        s.set_nonblocking(true).unwrap();
        server.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
        let w = Worker::start(s, LockstepClient::new(realm_server::PROTO_BP, 1, 0, 1));
        let mut b = [0u8; 64];
        let n = server.recv(&mut b).expect("the HELLO");
        assert_eq!(b[0], realm_server::MSG_HELLO);
        assert!(n > 1 && !w.welcomed() && w.take().is_none());
        drop(w);
        let mut got_bye = false;
        while let Ok(n) = server.recv(&mut b) {
            got_bye |= n == 1 && b[0] == realm_server::MSG_BYE;
            if got_bye {
                break;
            }
        }
        assert!(got_bye, "a BYE on drop");
    }
}
