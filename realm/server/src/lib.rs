//! The crowd test's server side as a library: interest views, protocol A (v0 and v1) and B coding, bots,
//! and stats. `main.rs` is the UDP server and the `--bench`; `realm-loadtest` uses the decoders.

pub mod bots;
pub mod client;
pub mod lockstep;
pub mod predict;
pub mod snap;
pub mod stats;
pub mod view;

pub const DEFAULT_PORT: u16 = 7777;
/// Largest datagram payload either side sends.
pub const MAX_DATAGRAM: usize = 1200;
/// IP + UDP header bytes per datagram, for wire totals.
pub const UDP_OVERHEAD: usize = 28;

pub const MSG_HELLO: u8 = 0x01;
pub const MSG_INPUT: u8 = 0x02;
pub const MSG_BYE: u8 = 0x03;
pub const MSG_WELCOME: u8 = 0x81;
pub const MSG_SNAPSHOT: u8 = 0x82;
/// Protocol A version 1 snapshot (deltas): the core job's extension.
pub const MSG_SNAPSHOT_V1: u8 = 0x83;
/// Protocol B: tick records.
pub const MSG_TICKS: u8 = 0x90;
/// Protocol B: the full state a joining follower starts from, in parts.
pub const MSG_STATE: u8 = 0x91;
/// Protocol B to a lockstep player: the seqs of its inputs in force at recent ticks, then a `0x90` datagram.
pub const MSG_PLAYER_TICKS: u8 = 0x92;

/// HELLO `proto` values: 1 is protocol A v0 (the contract); 2, 3 and 4 are extensions.
pub const PROTO_A0: u32 = 1;
pub const PROTO_A1: u32 = 2;
/// A protocol B follower with no player.
pub const PROTO_B: u32 = 3;
/// A protocol B lockstep player: it joins the field, its inputs enter the tick stream, and it follows.
pub const PROTO_BP: u32 = 4;

pub fn put_u16(w: &mut Vec<u8>, v: u16) {
    w.extend_from_slice(&v.to_le_bytes());
}
pub fn put_u32(w: &mut Vec<u8>, v: u32) {
    w.extend_from_slice(&v.to_le_bytes());
}
pub fn put_i32(w: &mut Vec<u8>, v: i32) {
    w.extend_from_slice(&v.to_le_bytes());
}
pub fn put_u64(w: &mut Vec<u8>, v: u64) {
    w.extend_from_slice(&v.to_le_bytes());
}
/// LEB128.
pub fn put_varint(w: &mut Vec<u8>, mut v: u32) {
    while v >= 0x80 {
        w.push(v as u8 | 0x80);
        v >>= 7;
    }
    w.push(v as u8);
}

/// A little-endian reader that fails soft (`None`) on short input.
pub struct Rd<'a> {
    pub b: &'a [u8],
    pub at: usize,
}

impl<'a> Rd<'a> {
    pub fn new(b: &'a [u8]) -> Rd<'a> {
        Rd { b, at: 0 }
    }
    pub fn left(&self) -> usize {
        self.b.len() - self.at
    }
    pub fn bytes(&mut self, n: usize) -> Option<&'a [u8]> {
        let s = self.b.get(self.at..self.at + n)?;
        self.at += n;
        Some(s)
    }
    pub fn u8(&mut self) -> Option<u8> {
        Some(self.bytes(1)?[0])
    }
    pub fn u16(&mut self) -> Option<u16> {
        Some(u16::from_le_bytes(self.bytes(2)?.try_into().ok()?))
    }
    pub fn u32(&mut self) -> Option<u32> {
        Some(u32::from_le_bytes(self.bytes(4)?.try_into().ok()?))
    }
    pub fn i32(&mut self) -> Option<i32> {
        Some(self.u32()? as i32)
    }
    pub fn u64(&mut self) -> Option<u64> {
        Some(u64::from_le_bytes(self.bytes(8)?.try_into().ok()?))
    }
    pub fn varint(&mut self) -> Option<u32> {
        let mut v = 0u32;
        for shift in (0..35).step_by(7) {
            let b = self.u8()?;
            v |= ((b & 0x7F) as u32) << shift;
            if b & 0x80 == 0 {
                return Some(v);
            }
        }
        None
    }
}

/// HELLO: `0x01, u32 proto, u8 class, u8 race`.
pub fn hello(proto: u32, class: u8, race: u8) -> Vec<u8> {
    let mut w = vec![MSG_HELLO];
    put_u32(&mut w, proto);
    w.push(class);
    w.push(race);
    w
}

/// INPUT: `0x02, u32 last snapshot tick seen, u8 move, u8 zoom`.
pub fn input(ack: u32, mv: u8, zoom: u8) -> Vec<u8> {
    let mut w = vec![MSG_INPUT];
    put_u32(&mut w, ack);
    w.push(mv);
    w.push(zoom);
    w
}

/// A lockstep player's INPUT: `0x02, u32 ticks applied, u8 move, u8 zoom, u32 seq, u8 n, n x u8 move`:
/// `moves[0]` is this input's move and the rest repeat the moves of seqs `seq - 1`, `seq - 2`, ...
pub fn input_seq(ack: u32, seq: u32, moves: &[u8]) -> Vec<u8> {
    let mut w = input(ack, moves.first().copied().unwrap_or(0), 1);
    put_u32(&mut w, seq);
    let earlier = moves.get(1..).unwrap_or_default();
    w.push(earlier.len() as u8);
    w.extend_from_slice(earlier);
    w
}

/// WELCOME: `0x81, u32 player id, u32 tick, u16 tick hz, u32 field width px, u32 field height px`.
pub fn welcome(id: u32, tick: u32) -> Vec<u8> {
    let mut w = vec![MSG_WELCOME];
    put_u32(&mut w, id);
    put_u32(&mut w, tick);
    put_u16(&mut w, realm_core::TICK_HZ as u16);
    put_u32(&mut w, realm_core::FIELD_PX as u32);
    put_u32(&mut w, realm_core::FIELD_PX as u32);
    w
}
