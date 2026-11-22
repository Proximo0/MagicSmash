//! The crowd test's server side as a library: interest views, protocol A (v0 and v1) and B coding, bots,
//! and stats. `main.rs` is the UDP server and the `--bench`; `realm-loadtest` uses the decoders.

pub mod bots;
pub mod client;
pub mod driver;
pub mod host;
pub mod lockstep;
pub mod mac;
#[cfg(test)]
mod probe;
pub mod predict;
pub mod realm_clock;
pub mod report;
pub mod sim;
pub mod snap;
pub mod stats;
pub mod view;
pub mod wire;
pub mod world;
#[cfg(test)]
mod wirefuzz;

pub const DEFAULT_PORT: u16 = 7777;
/// Largest datagram payload either side sends.
pub const MAX_DATAGRAM: usize = 1200;
/// IP + UDP header bytes per datagram, for wire totals.
pub const UDP_OVERHEAD: usize = 28;

/// The skill bit a client that only knows skill 1 sets in byte 0 (the core's `IN_SKILL1`).
pub const WIRE_SKILL: u8 = realm_core::IN_SKILL1 as u8;

pub const MSG_HELLO: u8 = 0x01;
pub const MSG_INPUT: u8 = 0x02;
pub const MSG_BYE: u8 = 0x03;
/// A ticketed player's INPUT: `0x04, u32 counter, <the INPUT after its message byte>, u64 tag` (`seal`).
pub const MSG_SEALED_INPUT: u8 = 0x04;
/// A ticketed player's BYE: `0x05, u32 counter, u64 tag`.
pub const MSG_SEALED_BYE: u8 = 0x05;

/// The secret a field ticket carries (`docs/realm/wire.md`, "Transport security"): 128 random bits from the gateway,
/// fresh for each admission, sent only over the gateway's TLS. It keys the field MACs (`mac::siphash24`) and never
/// crosses UDP. Its Debug shows no bytes.
#[derive(Clone, Copy, PartialEq, Eq, Default)]
pub struct TicketKey(pub [u8; 16]);

impl std::fmt::Debug for TicketKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("TicketKey(<redacted>)")
    }
}

impl TicketKey {
    pub fn is_zero(&self) -> bool {
        self.0 == [0; 16]
    }
    /// The 8-byte tag over `parts` (each a domain byte or field, in order).
    pub fn tag(&self, parts: &[&[u8]]) -> u64 {
        mac::siphash24(&self.0, &parts.concat())
    }
}
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

/// HELLO: `0x01, u32 proto, u8 class, u8 race, u64 ticket, [u64 nonce, u64 mac]`. A field host that was given a
/// gateway wants a ticket (from `FIELD_TICKET`) and proof of its key: the client's `nonce` and
/// `mac = SipHash(key, "H", proto, ticket, nonce)`; it ignores class and race. A crowd-test server has no tickets and
/// joins a bench hero of that class (0..4 is KNIGHT to PALADIN) and race.
pub fn hello(proto: u32, class: u8, race: u8) -> Vec<u8> {
    hello_ticket(proto, class, race, 0, None)
}

pub fn hello_mac(key: &TicketKey, proto: u32, ticket: u64, nonce: u64) -> u64 {
    key.tag(&[b"H", &proto.to_le_bytes(), &ticket.to_le_bytes(), &nonce.to_le_bytes()])
}

/// `proof`: the ticket's key and this client's nonce (the key itself is not sent).
pub fn hello_ticket(proto: u32, class: u8, race: u8, ticket: u64, proof: Option<(&TicketKey, u64)>) -> Vec<u8> {
    let mut w = vec![MSG_HELLO];
    put_u32(&mut w, proto);
    w.push(class);
    w.push(race);
    put_u64(&mut w, ticket);
    if let Some((key, nonce)) = proof {
        put_u64(&mut w, nonce);
        put_u64(&mut w, hello_mac(key, proto, ticket, nonce));
    }
    w
}

/// A parsed HELLO (`ticket` 0 and `proof` None when the client sent none). `proof` is (nonce, mac).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Hello {
    pub proto: u32,
    pub class: u8,
    pub race: u8,
    pub ticket: u64,
    pub proof: Option<(u64, u64)>,
}

pub fn parse_hello(r: &mut Rd) -> Option<Hello> {
    let (proto, class, race) = (r.u32()?, r.u8()?, r.u8()?);
    let ticket = r.u64().unwrap_or(0);
    let proof = match (r.u64(), r.u64()) {
        (Some(n), Some(m)) => Some((n, m)),
        _ => None,
    };
    Some(Hello { proto, class, race, ticket, proof })
}

/// True when `proof` proves `key` for this HELLO.
pub fn hello_proves(key: &TicketKey, h: &Hello) -> bool {
    !key.is_zero() && h.proof.is_some_and(|(nonce, mac)| hello_mac(key, h.proto, h.ticket, nonce) == mac)
}

/// Seals a client's INPUT or BYE (`MSG_INPUT`/`MSG_BYE` as built below) with the session's key: `0x04|0x05, u32
/// counter, body, u64 tag` where `tag = SipHash(key, type, counter, body)`. The counter must rise with every datagram;
/// the host drops a stale or repeated one.
pub fn seal(key: &TicketKey, counter: u32, msg: &[u8]) -> Vec<u8> {
    let (t, body) = match msg.first() {
        Some(&MSG_INPUT) => (MSG_SEALED_INPUT, &msg[1..]),
        Some(&MSG_BYE) => (MSG_SEALED_BYE, &msg[1..]),
        _ => return msg.to_vec(),
    };
    let mut w = Vec::with_capacity(msg.len() + 12);
    w.push(t);
    put_u32(&mut w, counter);
    w.extend_from_slice(body);
    put_u64(&mut w, key.tag(&[&[t], &counter.to_le_bytes(), body]));
    w
}

/// Opens a sealed datagram: its counter and body when the tag is the key's, else None.
pub fn unseal<'a>(key: &TicketKey, msg: &'a [u8]) -> Option<(u32, &'a [u8])> {
    let t = *msg.first()?;
    if !matches!(t, MSG_SEALED_INPUT | MSG_SEALED_BYE) || msg.len() < 13 || key.is_zero() {
        return None;
    }
    let counter = u32::from_le_bytes(msg[1..5].try_into().ok()?);
    let (body, tag) = msg[5..].split_at(msg.len() - 13);
    let tag = u64::from_le_bytes(tag.try_into().ok()?);
    (key.tag(&[&[t], &counter.to_le_bytes(), body]) == tag).then_some((counter, body))
}

/// INPUT: `0x02, u32 ticks applied, u8 byte 0, u8 zoom, u8 byte 1` (rules section 1: direction and skills,
/// then the pick and potions). A byte-0-only client sends 0 for byte 1.
pub fn input(ack: u32, mv: u8, zoom: u8) -> Vec<u8> {
    input_word(ack, mv as u16, zoom)
}

pub fn input_word(ack: u32, word: u16, zoom: u8) -> Vec<u8> {
    let mut w = vec![MSG_INPUT];
    put_u32(&mut w, ack);
    w.push(word as u8);
    w.push(zoom);
    w.push((word >> 8) as u8);
    w
}

/// A lockstep player's INPUT: the INPUT above, then `u32 seq, u8 n, n x u16 word`: `words[0]` is this
/// input's word and the rest repeat the words of seqs `seq - 1`, `seq - 2`, ...
pub fn input_seq(ack: u32, seq: u32, words: &[u16]) -> Vec<u8> {
    let mut w = input_word(ack, words.first().copied().unwrap_or(0), 1);
    put_u32(&mut w, seq);
    let earlier = words.get(1..).unwrap_or_default();
    w.push(earlier.len() as u8);
    for &e in earlier {
        put_u16(&mut w, e);
    }
    w
}

/// An INPUT read back: `seq_words` is `Some((seq, [word of seq, word of seq - 1, ...]))` for a lockstep player.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InputMsg {
    pub ack: u32,
    pub word: u16,
    pub zoom: u8,
    pub seq_words: Option<(u32, Vec<u16>)>,
}

/// Reads an INPUT after its message byte. Fails soft on short input.
pub fn parse_input(r: &mut Rd) -> Option<InputMsg> {
    let ack = r.u32()?;
    let b0 = r.u8()?;
    let zoom = r.u8()?;
    let b1 = r.u8()?;
    let word = wire::clean_input(wire::word_of(b0, b1));
    let seq_words = match r.u32() {
        Some(seq) => {
            let mut words = vec![word];
            for _ in 0..r.u8()? {
                words.push(wire::clean_input(r.u16()?));
            }
            Some((seq, words))
        }
        None => None,
    };
    Some(InputMsg { ack, word, zoom, seq_words })
}

/// WELCOME: `0x81, u32 player id, u32 tick, u16 tick hz, u32 field width px, u32 field height px, [u64 mac]`. To
/// a ticketed player the host adds `mac = SipHash(key, "W", nonce, id, tick)` over her HELLO's nonce, so a WELCOME
/// nobody with the key sent is not believed.
pub fn welcome(id: u32, tick: u32, auth: Option<(&TicketKey, u64)>) -> Vec<u8> {
    let mut w = vec![MSG_WELCOME];
    put_u32(&mut w, id);
    put_u32(&mut w, tick);
    put_u16(&mut w, realm_core::TICK_HZ as u16);
    put_u32(&mut w, realm_core::FIELD_PX as u32);
    put_u32(&mut w, realm_core::FIELD_PX as u32);
    if let Some((key, nonce)) = auth {
        put_u64(&mut w, welcome_mac(key, nonce, id, tick));
    }
    w
}

pub fn welcome_mac(key: &TicketKey, nonce: u64, id: u32, tick: u32) -> u64 {
    key.tag(&[b"W", &nonce.to_le_bytes(), &id.to_le_bytes(), &tick.to_le_bytes()])
}
