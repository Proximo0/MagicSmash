//! The realm follower inside Godot: a GDExtension with one class, `RealmLink`.
//!
//! `RealmLink` holds a worker thread (`worker.rs`) with the UDP socket and a protocol B lockstep player
//! (`realm_server::client`): the whole field, simulated from every player's inputs off the main thread, its
//! hash checked against the server's, and the player's own hero predicted. GDScript takes the newest finished
//! frame (`frame.rs`) once per game frame; nothing crosses the boundary per entity.
//!
//! Units: positions handed to GDScript are px (floats).

use godot::prelude::*;
use realm_core::tables::{Act, BOSSES, CARDS, KINDS, POTIONS, SKILLS};
use realm_core::{input, CLASSES, FIELD_PX, SUB};
use realm_server::client::LockstepClient;
use realm_server::PROTO_BP;
use std::io::ErrorKind;
use std::net::{ToSocketAddrs, UdpSocket};

mod draw;
mod frame;
mod worker;

use frame::{Frame, HeroView};
use worker::{Num, Worker};

struct RealmExtension;

#[gdextension]
unsafe impl ExtensionLibrary for RealmExtension {}

/// Button bits of `send_input`'s `buttons`.
const BTN_SKILL1: i32 = 1;
const BTN_SKILL2: i32 = 2;
const BTN_ULT: i32 = 4;
const BTN_INTERACT: i32 = 8;
/// Bits 4, 5 and 6: potion slots 1 to 3.
const BTN_POTION_SHIFT: i32 = 4;
/// Bit 7: the BLOOD MARK's rite (`IN_MARK`, input byte 1 bit 6), held with interact at a waystone.
const BTN_MARK: i32 = 128;

/// The core's two-byte input from the GDScript form: direction 0..8, button bits, a card pick 0..4.
fn core_input(direction: i32, buttons: i32, pick: i32) -> u16 {
    let b0 = direction.clamp(0, 8) as u8
        | if buttons & BTN_SKILL1 != 0 { 0x10 } else { 0 }
        | if buttons & BTN_SKILL2 != 0 { 0x20 } else { 0 }
        | if buttons & BTN_ULT != 0 { 0x40 } else { 0 }
        | if buttons & BTN_INTERACT != 0 { 0x80 } else { 0 };
    let potions = ((buttons >> BTN_POTION_SHIFT) & 7) as u8;
    let mark = if buttons & BTN_MARK != 0 { (realm_core::IN_MARK >> 8) as u8 } else { 0 };
    input(b0, pick.clamp(0, 4) as u8 | potions << 3 | mark)
}

/// One lockstep player's connection to a realm server, for GDScript.
///
/// `connect_to_host` starts a worker thread that holds the socket and the whole field and simulates every
/// tick as it arrives. Every game frame call `poll`: it takes the newest finished frame (the number of ticks
/// it applied is the return value) and the reads below return that frame's parts. 20 times a second
/// `send_input`. Nothing here waits for the simulation.
#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct RealmLink {
    worker: Option<Worker>,
    frame: Frame,
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
        let client = LockstepClient::new(PROTO_BP, class.clamp(0, 4) as u8, race.clamp(0, 3) as u8, self.threads.max(1) as usize);
        self.open_link(host, port, client)
    }

    /// As `connect_to_host`, for a field host behind a gateway: `ticket` is what the gateway's FIELD_TICKET
    /// returned (a 64-bit number, passed as its two halves `ticket_high` and `ticket_low`, each 0 to
    /// 4294967295) and `key` its 16-byte secret (the HELLO proves the ticket with it); the host takes the hero's
    /// sheet from the store. False when the key is not 16 bytes.
    #[func]
    fn connect_with_ticket(&mut self, host: GString, port: i32, ticket_high: i64, ticket_low: i64, key: PackedByteArray) -> bool {
        let ticket = ((ticket_high as u64 & 0xFFFF_FFFF) << 32) | (ticket_low as u64 & 0xFFFF_FFFF);
        let Ok(key) = <[u8; 16]>::try_from(key.to_vec().as_slice()).map(realm_server::TicketKey) else {
            godot_error!("RealmLink: a field ticket's key is 16 bytes");
            return false;
        };
        let client = LockstepClient::with_ticket(ticket, key, self.threads.max(1) as usize);
        self.open_link(host, port, client)
    }

    fn open_link(&mut self, host: GString, port: i32, client: LockstepClient) -> bool {
        self.worker = None;
        self.frame = Frame::default();
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
                self.worker = Some(Worker::start(sock, client));
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
        self.worker = None;
    }

    /// Takes the newest finished frame from the worker, if there is a new one; returns how many ticks it
    /// applied since the last take (0: nothing new, keep drawing the last frame).
    #[func]
    fn poll(&mut self) -> i32 {
        let Some((f, n)) = self.worker.as_ref().and_then(Worker::take) else { return 0 };
        self.frame = f;
        n as i32
    }

    /// Sends this tick's input: `direction` 0 none, 1 E, 2 SE, 3 S, 4 SW, 5 W, 6 NW, 7 N, 8 NE; `buttons`
    /// bit 0 skill 1, 1 skill 2, 2 the ultimate, 3 interact, 4 to 6 potion slots 1 to 3, 7 the BLOOD MARK's rite
    /// (with interact, at a waystone); `pick` a card 1..4
    /// from the draw on offer (0 none). Call it 20 times a second; the worker predicts the hero at once.
    #[func]
    fn send_input(&mut self, direction: i32, buttons: i32, pick: i32) {
        if let Some(w) = self.worker.as_ref() {
            w.send(core_input(direction, buttons, pick));
        }
    }

    /// The rectangle (px) the draw buffers should cover, from the next finished frame on.
    #[func]
    fn set_view(&mut self, rect: Rect2i) {
        if let Some(w) = self.worker.as_ref() {
            w.set_view(sub_rect(rect));
        }
    }

    /// True once the server has answered the HELLO (the field may still be downloading).
    #[func]
    fn is_welcomed(&self) -> bool {
        self.worker.as_ref().is_some_and(Worker::welcomed)
    }

    /// True once the server answered and the whole field has downloaded.
    #[func]
    fn is_joined(&self) -> bool {
        self.frame.joined
    }

    /// This player's id in the field, or -1.
    #[func]
    fn hero_id(&self) -> i32 {
        if self.frame.joined {
            self.frame.hero_id
        } else {
            -1
        }
    }

    /// The last tick in the frame (0 before joining).
    #[func]
    fn confirmed_tick(&self) -> i64 {
        i64::from(self.frame.tick)
    }

    /// The state hash at the frame's tick (its 64 bits as an int).
    #[func]
    fn confirmed_hash(&self) -> i64 {
        self.frame.hash as i64
    }

    /// The predicted hero (px): the confirmed hero with every input the server has not used replayed.
    #[func]
    fn predicted_position(&self) -> Vector2 {
        self.worker.as_ref().map_or(Vector2::ZERO, |w| {
            let p = w.pose().predicted;
            Vector2::new(p.0, p.1)
        })
    }

    /// The prediction with what it was made from, all from one moment of the worker (the frame, `hero_view`
    /// and `counters` are published at other moments: after a stall they can be ticks apart). Keys: `tick`
    /// (the confirmed tick), `confirmed` (the hero there, px), `alive`, `predicted` (px, as
    /// `predicted_position`) and `unconfirmed` (the inputs replayed on top). Empty before the first input or tick.
    #[func]
    fn prediction(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(p) = self.worker.as_ref().map(Worker::pose).filter(|p| p.version > 0) else { return d };
        d.set("tick", i64::from(p.tick));
        d.set("confirmed", Vector2::new(p.confirmed.0, p.confirmed.1));
        d.set("alive", p.alive);
        d.set("predicted", Vector2::new(p.predicted.0, p.predicted.1));
        d.set("unconfirmed", i64::from(p.unconfirmed));
        d
    }

    /// Where to draw the hero after the latest input (px): the prediction with corrections smoothed out.
    #[func]
    fn shown_position(&self) -> Vector2 {
        self.worker.as_ref().map_or(Vector2::ZERO, |w| {
            let p = w.pose().shown;
            Vector2::new(p.0, p.1)
        })
    }

    /// Changes whenever the shown position does (an input, or a correction from a confirmed tick).
    #[func]
    fn shown_version(&self) -> i32 {
        self.worker.as_ref().map_or(0, |w| w.pose().version as i32)
    }

    /// The hero at the frame's tick, for the HUD; empty before joining. Keys: `id class job race
    /// class_level health max_health level xp xp_need alive downed raise_pct coin x y facing_left moving
    /// fx_mask hold waystone banked phoenix_used owed`; `skills` (3 x `[id, cooldown left, cooldown, rank %]`,
    /// id -1 for none), `belt` (3 x `[potion, charges, rest left]`), `offer` (4 card ids, 0 for none) and
    /// `copies` (card id to copies, index 0 unused). Ticks are 20 a second.
    #[func]
    fn hero_view(&self) -> VarDictionary {
        self.frame.hero.as_ref().map_or_else(VarDictionary::new, hero_dict)
    }

    /// The monsters in view as a MultiMesh buffer (2D transform, colour, custom data: 16 floats a figure)
    /// sorted by depth. The custom data holds the offset back to where the monster was in the previous
    /// frame (blend it out in the shader), its kind (the atlas frame) and a bob seed.
    #[func]
    fn monster_buffer(&self) -> PackedFloat32Array {
        PackedFloat32Array::from(self.frame.monster_buf.as_slice())
    }

    /// As `monster_buffer` for players other than this one (frame `class * 4 + race`, class 0 the NOVICE).
    #[func]
    fn player_buffer(&self) -> PackedFloat32Array {
        PackedFloat32Array::from(self.frame.player_buf.as_slice())
    }

    /// Effect rows of this tick, 8 floats each: `[type, x, y, a, b, c, d, e]` in px (see `frame::fx`):
    /// 1 swing, 2 ring, 3 bolt, 4 drop, 5 zone, 6 dash, 7 monster shot, 8 status, 9 raising.
    #[func]
    fn fx_rows(&self) -> PackedFloat32Array {
        PackedFloat32Array::from(self.frame.fx.as_slice())
    }

    /// Event rows of this tick, 8 ints each: `[rank, hero or -1, a, b, c, x px, y px, 0]`; rank is the
    /// contract's order: 0 level, 1 draw, 2 pick, 3 skill, 4 potion, 5 down, 6 raise, 7 fallen, 8 bank,
    /// 9 leave, 10 kill, 11 xp.
    #[func]
    fn event_rows(&self) -> PackedInt32Array {
        PackedInt32Array::from(self.frame.events.as_slice())
    }

    /// The field's own state: `field`, `tick`, `tide` (a tide is running), `sites` (px pairs: the gate, the
    /// heart, seven waystones, six altars), `quiet` (4 floats a quiet zone: x, y, radius px, shrine or -1),
    /// `zones`, `drops`, `shots`; the realm clock's `clock`, `tide_in` and
    /// `tide_left` (ticks), `altars` (state, held, health per altar), `next_boss` and `next_boss_in`, `world_field`
    /// and `world_in`, and `boss` (`name`, `health`, `max_health`, `x`, `y` px, `world`, `leaves_in`) while one is up.
    #[func]
    fn world(&self) -> VarDictionary {
        let w = &self.frame.world;
        let mut d = VarDictionary::new();
        d.set("field", w.field);
        d.set("tick", i64::from(w.tick));
        d.set("tide", w.tide);
        d.set("sites", &(PackedFloat32Array::from(w.sites.as_slice())).to_variant());
        d.set("quiet", &(PackedFloat32Array::from(w.quiet.as_slice())).to_variant());
        d.set("zones", w.zones);
        d.set("drops", w.drops);
        d.set("shots", w.shots);
        let v = &w.view;
        let t = |x: u64| x.min(i64::MAX as u64) as i64;
        d.set("clock", t(v.clock));
        d.set("tide_in", t(v.tide_in));
        d.set("tide_left", t(v.tide_left));
        d.set("quick", v.quick);
        let altars: Vec<i64> = v.altars.iter().flat_map(|a| [i64::from(a.0), i64::from(a.1), i64::from(a.2)]).collect();
        d.set("altars", &PackedInt64Array::from(altars.as_slice()).to_variant());
        d.set("next_boss", i64::from(v.next_boss.0));
        d.set("next_boss_in", t(v.next_boss.1));
        d.set("world_field", i64::from(v.world_field));
        d.set("world_in", t(v.world_in));
        if let Some(b) = &v.boss {
            let mut bd = VarDictionary::new();
            bd.set("which", i64::from(b.which));
            bd.set("name", b.name);
            bd.set("health", i64::from(b.health));
            bd.set("max_health", i64::from(b.max_health));
            bd.set("x", b.x);
            bd.set("y", b.y);
            bd.set("world", b.world);
            bd.set("leaves_in", t(b.leaves_in));
            d.set("boss", &bd.to_variant());
        }
        d
    }

    #[func]
    fn player_count(&self) -> i32 {
        self.frame.players
    }

    #[func]
    fn monster_count(&self) -> i32 {
        self.frame.monsters
    }

    /// The counters: `bytes_in_per_sec`, `bytes_out_per_sec`, `sim_ms_per_tick` and `frame_build_ms` over
    /// the last whole second; `ticks_applied`, `hash_checks_passed`, `hash_checks_failed`, `sim_ms_last`,
    /// `stall_ms_max` (the longest wait between two applied ticks), `join_bytes`, `join_tick`, `mispredicts`,
    /// `predictions_checked`, `unconfirmed_inputs` and `bad_datagrams` since connecting.
    #[func]
    fn counters(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        let Some(w) = self.worker.as_ref() else { return d };
        for (k, v) in w.counters() {
            match v {
                Num::Int(i) => d.set(k, i),
                Num::Float(x) => d.set(k, x),
            }
        }
        d
    }

    /// The field's side in px.
    #[func]
    fn field_size() -> i32 {
        FIELD_PX
    }

    /// Monster kinds the core has (42).
    /// The core's two-byte input word `send_input` sends for these arguments (for the client's checks).
    #[func]
    fn input_word(direction: i32, buttons: i32, pick: i32) -> i32 {
        i32::from(core_input(direction, buttons, pick))
    }

    #[func]
    fn kind_count() -> i32 {
        KINDS.len() as i32
    }

    /// One kind's `name`, `field`, `beh` (behaviour bits), `health` and `speed`.
    #[func]
    fn kind_info(kind: i32) -> VarDictionary {
        let mut d = VarDictionary::new();
        if let Some(k) = KINDS.get(kind.max(0) as usize) {
            d.set("name", &(GString::from(k.name)).to_variant());
            d.set("field", i32::from(k.field));
            d.set("beh", i32::from(k.beh));
            d.set("health", k.health as i32);
            d.set("speed", k.speed as i32);
        }
        d
    }

    /// A boss row's `name` and `carrier` (the monster kind it is born from and drawn as when it has no art of its own).
    #[func]
    fn boss_info(which: i32) -> VarDictionary {
        let mut d = VarDictionary::new();
        if let Some(b) = BOSSES.get(which.max(0) as usize) {
            d.set("name", &(GString::from(b.name)).to_variant());
            d.set("carrier", i32::from(b.carrier));
        }
        d
    }

    /// A skill's `name`, `level`, `cooldown` (ticks) and `act` (the kind of effect, for its colour).
    #[func]
    fn skill_info(id: i32) -> VarDictionary {
        let mut d = VarDictionary::new();
        if let Some(s) = SKILLS.get(id.max(0) as usize) {
            d.set("name", &(GString::from(s.name)).to_variant());
            d.set("level", i32::from(s.level));
            d.set("cooldown", s.cooldown as i32);
            d.set("act", &(GString::from(act_name(&s.act))).to_variant());
        }
        d
    }

    #[func]
    fn card_name(id: i32) -> GString {
        GString::from(CARDS.get(id.max(0) as usize).map_or("", |c| c.name))
    }

    #[func]
    fn potion_name(id: i32) -> GString {
        GString::from(POTIONS.get(id.max(0) as usize).map_or("", |p| p.name))
    }

    /// A class's name (0 NOVICE, 1 KNIGHT, 2 MAGE, 3 ARCHER, 4 PRIEST, 5 PALADIN).
    #[func]
    fn class_name(id: i32) -> GString {
        GString::from(CLASSES.get(id.max(0) as usize).map_or("", |c| c.name))
    }
}

fn act_name(a: &Act) -> &'static str {
    match a {
        Act::HealSelf { .. } => "heal",
        Act::SelfEffect { .. } => "self",
        Act::GroupEffect { .. } => "group",
        Act::GroupHeal { .. } => "groupheal",
        Act::Ring { .. } => "ring",
        Act::Thick { .. } => "drop",
        Act::Volley { .. } => "volley",
        Act::Dash { .. } => "dash",
        Act::Zone { .. } => "zone",
        Act::Curse { .. } => "curse",
    }
}

fn hero_dict(h: &HeroView) -> VarDictionary {
    let mut d = VarDictionary::new();
    let ints = [
        ("id", h.id),
        ("class", h.class),
        ("job", h.job),
        ("race", h.race),
        ("class_level", h.class_level),
        ("health", h.health),
        ("max_health", h.max_health),
        ("level", h.level),
        ("xp", h.xp),
        ("xp_need", h.xp_need),
        ("downed", h.downed),
        ("raise_pct", h.raise_pct),
        ("coin", h.coin),
        ("owed", h.owed),
        ("fx_mask", h.fx_mask),
        ("hold", h.hold),
        ("waystone", h.waystone),
    ];
    for (k, v) in ints {
        d.set(k, v);
    }
    for (k, v) in [("alive", h.alive), ("banked", h.banked), ("phoenix_used", h.phoenix_used), ("facing_left", h.facing_left), ("moving", h.moving), ("marked", h.marked)] {
        d.set(k, v);
    }
    d.set("x", h.x);
    d.set("y", h.y);
    let skills: Vec<i32> = h.skills.iter().flatten().copied().collect();
    let belt: Vec<i32> = h.belt.iter().flatten().copied().collect();
    d.set("skills", &(PackedInt32Array::from(skills.as_slice())).to_variant());
    d.set("belt", &(PackedInt32Array::from(belt.as_slice())).to_variant());
    d.set("offer", &(PackedInt32Array::from(&h.offer[..])).to_variant());
    d.set("copies", &(PackedInt32Array::from(h.copies.as_slice())).to_variant());
    d
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_gdscript_buttons_become_the_cores_two_bytes() {
        assert_eq!(core_input(3, 0, 0), input(3, 0));
        assert_eq!(core_input(8, BTN_SKILL1 | BTN_SKILL2 | BTN_ULT | BTN_INTERACT, 0), input(8 | 0xF0, 0));
        assert_eq!(core_input(0, 2 << BTN_POTION_SHIFT, 4), input(0, 4 | 2 << 3));
        assert_eq!(core_input(99, 0, 99), input(8, 4));
        // The BLOOD MARK's rite: interact and IN_MARK together, nothing else changed.
        let rite = core_input(0, BTN_INTERACT | BTN_MARK, 0);
        assert_eq!(rite, input(0x80, 0) | realm_core::IN_MARK);
        assert_eq!(rite & realm_core::IN_INTERACT, realm_core::IN_INTERACT);
    }
}
