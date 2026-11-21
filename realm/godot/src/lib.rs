//! The realm follower inside Godot: a GDExtension with one class, `RealmLink`.
//!
//! `RealmLink` holds the UDP socket and a protocol B lockstep player (`realm_server::client`): the whole
//! field, simulated from every player's inputs, its hash checked against the server's, and the player's own
//! hero predicted. GDScript calls it a few times a frame; nothing crosses the boundary per entity. The
//! drawing reads return one packed array for every figure in a rectangle.
//!
//! Units: positions handed to GDScript are px (floats in `Vector2` and the draw buffers) or 1/256 px
//! (ints in `monsters_in` and `players_in`, exact).

use godot::prelude::*;
use realm_core::{Field, FIELD_PX, SUB};
use realm_server::client::LockstepClient;
use realm_server::PROTO_BP;
use std::io::ErrorKind;
use std::net::{ToSocketAddrs, UdpSocket};
use std::time::{Duration, Instant};

mod draw;

struct RealmExtension;

#[gdextension]
unsafe impl ExtensionLibrary for RealmExtension {}

/// HELLO is repeated this often until the server answers.
const HELLO_EVERY: Duration = Duration::from_millis(500);
/// The socket is read until empty, but at most this many datagrams a poll (a join burst spreads over frames).
const READS_PER_POLL: usize = 4096;
const MSG_BYE: u8 = 0x03;

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

/// A connection: the socket and the lockstep player.
struct Link {
    sock: UdpSocket,
    client: LockstepClient,
    hello_at: Instant,
    rates: Rates,
}

impl Link {
    fn send(&mut self, b: &[u8]) {
        // A full send buffer or an unreachable server is the same as a lost datagram: the protocol repeats.
        if self.sock.send(b).is_ok() {
            self.rates.bytes_out += b.len() as u64;
        }
    }
}

impl Drop for Link {
    fn drop(&mut self) {
        let _ = self.sock.send(&[MSG_BYE]);
    }
}

/// One lockstep player's connection to a realm server, for GDScript.
///
/// `connect_to_host`, then every frame `poll` (it applies every tick that has arrived) and 20 times a second
/// `send_input`. Read the field through the bulk reads and the counters.
#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct RealmLink {
    link: Option<Link>,
    draw: draw::DrawState,
    /// Worker threads for the follower's simulation (the result is the same for any count).
    #[var]
    #[init(val = 2)]
    threads: i32,
}

#[godot_api]
impl RealmLink {
    /// Opens a socket toward `host:port` and starts joining as a player of `class` (0..4) and `race`
    /// (0..3). False (and an error printed) when the address does not resolve or the socket cannot open.
    #[func]
    fn connect_to_host(&mut self, host: GString, port: i32, class: i32, race: i32) -> bool {
        self.link = None;
        self.draw = draw::DrawState::default();
        let addr = format!("{host}:{port}");
        let opened = (|| -> std::io::Result<UdpSocket> {
            let target = addr.to_socket_addrs()?.next().ok_or_else(|| std::io::Error::new(ErrorKind::NotFound, "no address"))?;
            let sock = UdpSocket::bind(if target.is_ipv4() { "0.0.0.0:0" } else { "[::]:0" })?;
            sock.connect(target)?;
            sock.set_nonblocking(true)?;
            Ok(sock)
        })();
        match opened {
            Ok(sock) => {
                let client = LockstepClient::new(PROTO_BP, class.clamp(0, 4) as u8, race.clamp(0, 3) as u8, self.threads.max(1) as usize);
                let mut link = Link { sock, client, hello_at: Instant::now(), rates: Rates::default() };
                let hello = link.client.hello();
                link.send(&hello);
                self.link = Some(link);
                true
            }
            Err(e) => {
                godot_error!("RealmLink: cannot open {addr}: {e}");
                false
            }
        }
    }

    /// Leaves the field (a BYE) and closes the socket.
    #[func]
    fn close(&mut self) {
        self.link = None;
    }

    /// Reads every datagram waiting, applies every tick that has fully arrived and returns how many.
    #[func]
    fn poll(&mut self) -> i32 {
        let Some(link) = self.link.as_mut() else { return 0 };
        let now = Instant::now();
        if !link.client.welcomed() && now >= link.hello_at {
            link.hello_at = now + HELLO_EVERY;
            let hello = link.client.hello();
            link.send(&hello);
        }
        let mut buf = [0u8; 2048];
        for _ in 0..READS_PER_POLL {
            match link.sock.recv(&mut buf) {
                Ok(n) => {
                    link.rates.bytes_in += n as u64;
                    link.client.receive(&buf[..n]);
                }
                // Windows reports an ICMP "port unreachable" (no server yet) as an error on the next read.
                Err(e) if e.kind() == ErrorKind::ConnectionReset => {}
                Err(_) => break,
            }
        }
        let sim0 = link.client.stats.sim;
        let n = link.client.apply();
        link.rates.sim += link.client.stats.sim - sim0;
        link.rates.ticks += n as u64;
        link.rates.roll(now);
        n as i32
    }

    /// Sends this tick's input: `direction` 0 none, 1 E, 2 SE, 3 S, 4 SW, 5 W, 6 NW, 7 N, 8 NE, and the
    /// skill. Call it 20 times a second; it moves the predicted hero one tick at once.
    #[func]
    fn send_input(&mut self, direction: i32, skill: bool) {
        let Some(link) = self.link.as_mut() else { return };
        if !link.client.welcomed() {
            return;
        }
        let mv = direction.clamp(0, 8) as u8 | if skill { realm_core::INPUT_SKILL } else { 0 };
        let d = link.client.input(mv);
        link.send(&d);
    }

    fn client(&self) -> Option<&LockstepClient> {
        self.link.as_ref().map(|l| &l.client)
    }

    fn field(&self) -> Option<&Field> {
        self.client()?.field()
    }

    /// True once the server answered and the whole field has downloaded.
    #[func]
    fn is_joined(&self) -> bool {
        self.field().is_some()
    }

    /// This player's id in the field, or -1.
    #[func]
    fn hero_id(&self) -> i32 {
        self.client().and_then(|c| c.hero()).map_or(-1, i32::from)
    }

    /// The last tick confirmed by the server and applied here (0 before joining).
    #[func]
    fn confirmed_tick(&self) -> i64 {
        self.client().map_or(0, |c| c.tick() as i64)
    }

    /// The state hash at the confirmed tick (its 64 bits as an int).
    #[func]
    fn confirmed_hash(&self) -> i64 {
        self.field().map_or(0, |f| f.hash() as i64)
    }

    /// The predicted hero (px): the confirmed hero with every input the server has not used replayed.
    #[func]
    fn predicted_position(&self) -> Vector2 {
        px(self.client().and_then(|c| c.predictor().predicted()))
    }

    /// Where to draw the hero after the latest input (px): the prediction with corrections smoothed out.
    #[func]
    fn shown_position(&self) -> Vector2 {
        px(self.client().and_then(|c| c.predictor().shown()))
    }

    /// The hero at the confirmed tick: `[health, max health, level, alive (0 or 1)]`, empty before joining.
    #[func]
    fn hero_state(&self) -> PackedInt32Array {
        let Some(p) = self.client().and_then(|c| c.hero_player()) else { return PackedInt32Array::new() };
        PackedInt32Array::from(&[i32::from(p.health), i32::from(p.max_health), i32::from(p.level), i32::from(p.alive())][..])
    }

    #[func]
    fn player_count(&self) -> i32 {
        self.field().map_or(0, |f| f.player_count() as i32)
    }

    #[func]
    fn monster_count(&self) -> i32 {
        self.field().map_or(0, |f| f.monster_count() as i32)
    }

    /// The counters: `bytes_in_per_sec`, `bytes_out_per_sec` and `sim_ms_per_tick` over the last whole
    /// second; `ticks_applied`, `hash_checks_passed`, `hash_checks_failed`, `sim_ms_last`, `stall_ms_max`
    /// (the longest wait between two applied ticks), `join_bytes`, `join_tick`, `mispredicts`,
    /// `predictions_checked`, `unconfirmed_inputs` and `bad_datagrams` since connecting.
    #[func]
    fn counters(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(link) = self.link.as_ref() else { return d };
        let (st, p, r) = (&link.client.stats, link.client.predictor(), &link.rates);
        let entries: [(&str, Variant); 14] = [
            ("bytes_in_per_sec", r.in_per_sec.to_variant()),
            ("bytes_out_per_sec", r.out_per_sec.to_variant()),
            ("sim_ms_per_tick", r.sim_ms_per_tick.to_variant()),
            ("ticks_applied", (st.ticks_applied as i64).to_variant()),
            ("hash_checks_passed", (st.hash_ok as i64).to_variant()),
            ("hash_checks_failed", (st.hash_bad as i64).to_variant()),
            ("sim_ms_last", (st.sim_last.as_secs_f64() * 1000.0).to_variant()),
            ("stall_ms_max", (st.stall_max.as_secs_f64() * 1000.0).to_variant()),
            ("join_bytes", (st.join_bytes as i64).to_variant()),
            ("join_tick", i64::from(st.join_tick).to_variant()),
            ("mispredicts", (p.mispredicts as i64).to_variant()),
            ("predictions_checked", (p.confirms as i64).to_variant()),
            ("unconfirmed_inputs", (p.unconfirmed() as i64).to_variant()),
            ("bad_datagrams", (st.bad_datagrams as i64).to_variant()),
        ];
        for (k, v) in entries {
            d.set(k, &v);
        }
        d
    }

    /// The monsters in `rect` (px), sorted by id: 5 ints each, `id, x, y, kind (0..7), flags` with x and y in
    /// 1/256 px and flags bit 0 elite, bit 1 hurt this tick.
    #[func]
    fn monsters_in(&self, rect: Rect2i) -> PackedInt32Array {
        let Some(f) = self.field() else { return PackedInt32Array::new() };
        let out = draw::monsters_in(f, sub_rect(rect));
        PackedInt32Array::from(out.as_slice())
    }

    /// The players in `rect` (px), sorted by id: 6 ints each, `id, x, y, class, race, flags` with x and y in
    /// 1/256 px and flags bit 0 faces left, bit 1 moving, bit 2 hurt this tick, bit 3 dead, bit 4 this player.
    #[func]
    fn players_in(&self, rect: Rect2i) -> PackedInt32Array {
        let Some(f) = self.field() else { return PackedInt32Array::new() };
        let me = self.client().and_then(|c| c.hero());
        let out = draw::players_in(f, sub_rect(rect), me);
        PackedInt32Array::from(out.as_slice())
    }

    /// The drawing fast path for monsters: a MultiMesh buffer (2D transform, colour, custom data: 16 floats
    /// a figure) for every monster in `rect` (px). The custom data holds the offset back to where the monster
    /// was at the previous call (blend it out in the shader), its kind (the atlas frame) and a bob seed.
    #[func]
    fn monster_buffer(&mut self, rect: Rect2i) -> PackedFloat32Array {
        let Some(f) = self.link.as_ref().and_then(|l| l.client.field()) else { return PackedFloat32Array::new() };
        let out = self.draw.monsters(f, sub_rect(rect));
        PackedFloat32Array::from(out.as_slice())
    }

    /// As `monster_buffer` for players other than this one (frame `class * 4 + race`).
    #[func]
    fn player_buffer(&mut self, rect: Rect2i) -> PackedFloat32Array {
        let Some(c) = self.link.as_ref().map(|l| &l.client) else { return PackedFloat32Array::new() };
        let Some(f) = c.field() else { return PackedFloat32Array::new() };
        let out = self.draw.players(f, sub_rect(rect), c.hero());
        PackedFloat32Array::from(out.as_slice())
    }

    /// The field's side in px.
    #[func]
    fn field_size() -> i32 {
        FIELD_PX
    }
}

fn px(p: Option<(i32, i32)>) -> Vector2 {
    p.map_or(Vector2::ZERO, |(x, y)| Vector2::new(x as f32 / SUB as f32, y as f32 / SUB as f32))
}

/// A px rectangle as (x0, y0, x1, y1) in 1/256 px, end exclusive.
fn sub_rect(r: Rect2i) -> draw::SubRect {
    let clamp = |v: i32| v.clamp(-FIELD_PX, 2 * FIELD_PX) * SUB;
    draw::SubRect {
        x0: clamp(r.position.x),
        y0: clamp(r.position.y),
        x1: clamp(r.position.x.saturating_add(r.size.x)),
        y1: clamp(r.position.y.saturating_add(r.size.y)),
    }
}
