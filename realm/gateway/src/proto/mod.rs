//! The gateway's wire: TCP, one frame after another, `u32 len, u8 type, u32 tag, body` (len counts type, tag
//! and body; at most `FRAME_MAX`). A request carries a tag the client chooses and the reply repeats it; what
//! the server sends by itself (town snapshots, chat, an outing's result) has tag 0.
//!
//! Strings are `u16 len, bytes` (UTF-8). A `Thing` is `u8 0, u64 item id` or `u8 1, u32 stack kind, u64 count`.
//!
//! Who owns which type byte is `ranges::TABLE`. The gateway's own messages are in `base`; every other module
//! (economy, social, world, homes) brings its messages, their coding and its dispatch in its own `gate.rs`, a
//! `WireModule` registered in `MODULES`. Decoders refuse (None) what they cannot read whole; they never panic,
//! never trust a count beyond the bytes that follow, and what they accept re-encodes to the same bytes
//! (`fuzz` checks all three).

use realm_server::{put_u16, put_u32, put_u64, Rd};
use std::io::{Read, Write};

mod base;
#[cfg(test)]
mod fuzz;
pub mod ranges;

pub use base::{HeroInfo, Inventory, ItemInfo, Member, TownSnapshot};
pub use base::{P_OUTING, P_TOWN_ARRIVE, P_TOWN_CHAT, P_TOWN_DEPART, P_TOWN_SNAPSHOT};
pub use base::{R_CARDS, R_ERR, R_HERO_CREATED, R_HEROES, R_INVENTORY, R_LOGIN, R_OK, R_PONG, R_SMITH, R_TICKET, R_TOWN};
pub use base::{
    T_BANK_DEPOSIT, T_BANK_WITHDRAW, T_BUY, T_CARDS, T_CHAT, T_CHOOSE_JOB, T_CREATE_HERO, T_DELETE_HERO, T_ENTER_TOWN, T_EQUIP, T_FIELD_TICKET, T_FUSE,
    T_INVENTORY, T_LEARN_PAGE, T_LEAVE_TOWN, T_LIST_HEROES, T_LOGIN_DEV, T_LOGIN_STEAM, T_MAIL_SEND, T_MAIL_TAKE, T_PING, T_RENAME_HERO, T_REROLL,
    T_SALVAGE, T_SELL, T_SET_BELT, T_SET_DECK, T_SOCKET, T_SPEND_POINT, T_TOWN_INPUT, T_UNDELETE_HERO, T_UNEQUIP, T_UNSOCKET, T_UPGRADE,
};

pub const FRAME_MAX: usize = 1 << 20;
/// What `read_frame` sets aside before a frame's bytes arrive.
const FRAME_FIRST_ALLOC: usize = 4096;

/// What a module's dispatch gives back: its answer (`Ok`), or the request untouched when it is not the module's.
pub type Served = std::result::Result<realm_store::Result<Resp>, Req>;

/// A module on the wire: how its `Req`/`Resp` variants are coded and how the gateway serves its requests. Each
/// function answers only for the module's own variants and tags (`None` / `Err(req)` otherwise).
pub struct WireModule {
    /// Its row in `ranges::TABLE`.
    pub module: &'static str,
    pub encode_req: fn(&Req) -> Option<(u8, Vec<u8>)>,
    pub decode_req: fn(u8, &[u8]) -> Option<Req>,
    pub encode_resp: fn(&Resp) -> Option<(u8, Vec<u8>)>,
    pub decode_resp: fn(u8, &[u8]) -> Option<Resp>,
    /// Serves a logged-in account's request; ops guards (a freeze) belong here.
    pub serve: fn(&crate::gateway::Gateway, &mut crate::gateway::Session, i64, Req) -> Served,
    /// One of each of its messages, for the round trip tests and the decoder fuzz.
    pub examples: fn() -> (Vec<Req>, Vec<Resp>),
}

/// Every module on the wire but the gateway's own. A new module: its `gate.rs` and one line here.
pub static MODULES: &[&WireModule] = &[&crate::economy::gate::WIRE, &crate::social::gate::WIRE, &crate::world::gate::WIRE, &crate::homes::gate::WIRE];

fn module_of(t: u8) -> Option<&'static WireModule> {
    let row = ranges::owner(t)?;
    MODULES.iter().copied().find(|m| m.module == row.module)
}

/// Error codes of `R_ERR`.
pub mod code {
    pub const BAD_REQUEST: u16 = 1;
    pub const NOT_LOGGED_IN: u16 = 2;
    pub const DISABLED: u16 = 3;
    pub const NOT_YOURS: u16 = 4;
    pub const FULL: u16 = 5;
    pub const MISSING: u16 = 6;
    pub const NAME_TAKEN: u16 = 7;
    pub const BAD_NAME: u16 = 8;
    pub const INSUFFICIENT: u16 = 9;
    pub const REFUSED: u16 = 10;
    pub const BUSY: u16 = 11;
    pub const BANNED: u16 = 12;
    pub const INVALID: u16 = 13;
    pub const SLOW_DOWN: u16 = 14;
    pub const INTERNAL: u16 = 15;
    pub const NO_FIELD: u16 = 16;
    /// Silenced by a moderator or by the flood limit (job T1).
    pub const MUTED: u16 = 17;
}

/// Writes a string, cut to the 65 535 bytes a `u16` can count (at a character's edge, so it stays UTF-8).
pub fn put_str(w: &mut Vec<u8>, s: &str) {
    let mut n = s.len().min(u16::MAX as usize);
    while !s.is_char_boundary(n) {
        n -= 1;
    }
    put_u16(w, n as u16);
    w.extend_from_slice(&s.as_bytes()[..n]);
}

pub fn read_str(r: &mut Rd) -> Option<String> {
    let n = r.count16()?;
    String::from_utf8(r.bytes(n)?.to_vec()).ok()
}

/// The careful reads every decoder uses on top of `Rd`.
pub trait WireRead {
    /// A flag byte: 0 or 1, anything else refused (so what is read writes back the same).
    fn flag(&mut self) -> Option<bool>;
    /// A count (u8, u16, u32) of things that follow, each at least a byte: refused when the rest of the body cannot
    /// hold that many, so a hostile count never makes a decoder allocate or loop for things that are not there.
    fn count8(&mut self) -> Option<usize>;
    fn count16(&mut self) -> Option<usize>;
    fn count32(&mut self) -> Option<usize>;
}

impl WireRead for Rd<'_> {
    fn flag(&mut self) -> Option<bool> {
        match self.u8()? {
            0 => Some(false),
            1 => Some(true),
            _ => None,
        }
    }
    fn count8(&mut self) -> Option<usize> {
        let n = self.u8()? as usize;
        (n <= self.left()).then_some(n)
    }
    fn count16(&mut self) -> Option<usize> {
        let n = self.u16()? as usize;
        (n <= self.left()).then_some(n)
    }
    fn count32(&mut self) -> Option<usize> {
        let n = self.u32()? as usize;
        (n <= self.left()).then_some(n)
    }
}

/// A thing a player moves: one item, or a count of a stack kind.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Thing {
    Item(i64),
    Stack(u32, u64),
}

impl Thing {
    pub fn put(&self, w: &mut Vec<u8>) {
        match *self {
            Thing::Item(i) => {
                w.push(0);
                put_u64(w, i as u64);
            }
            Thing::Stack(k, n) => {
                w.push(1);
                put_u32(w, k);
                put_u64(w, n);
            }
        }
    }
    pub fn read(r: &mut Rd) -> Option<Thing> {
        match r.u8()? {
            0 => Some(Thing::Item(r.u64()? as i64)),
            1 => Some(Thing::Stack(r.u32()?, r.u64()?)),
            _ => None,
        }
    }
}

/// What a client asks.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Req {
    LoginDev { name: String },
    LoginSteam { ticket: Vec<u8> },
    ListHeroes,
    CreateHero { name: String, race: u8, class: u8, look: u32, self_found: bool },
    DeleteHero { hero: i64 },
    UndeleteHero { hero: i64 },
    RenameHero { hero: i64, name: String },
    EnterTown { hero: i64 },
    LeaveTown,
    /// Direction 0..8 (the field's directions); the hero keeps walking until the next one.
    TownInput { dir: u8 },
    Chat { text: String },
    FieldTicket { hero: i64, field: u8 },
    Inventory { hero: i64 },
    BankDeposit { hero: i64, what: Thing, tab: u32 },
    BankWithdraw { hero: i64, what: Thing, tab: u32 },
    MailSend { hero: i64, to_name: String, what: Thing },
    MailTake { hero: i64, what: Thing },
    SpendPoint { hero: i64, stat: u8, n: u16 },
    SetDeck { hero: i64, cards: Vec<u16> },
    SetBelt { hero: i64, kinds: [u32; 3] },
    LearnPage { hero: i64, card: u16 },
    Equip { hero: i64, item: i64 },
    Unequip { hero: i64, item: i64 },
    Socket { hero: i64, item: i64, socket: u8, kind: u32 },
    Unsocket { hero: i64, item: i64, socket: u8 },
    ChooseJob { hero: i64, job: u8 },
    /// The smith (`realm_loot::Smith`): the server does these for coin and embers.
    Salvage { hero: i64, item: i64 },
    Upgrade { hero: i64, item: i64 },
    Reroll { hero: i64, item: i64 },
    Fuse { hero: i64, stat: u8, grade: u8 },
    /// The deck cards (0..30) the hero may put in her deck: the novice twelve, a card each even level to 24, pages learned.
    Cards { hero: i64 },
    /// A merchant sells `n` of a potion kind (a stack kind 100..106) for coin.
    Buy { hero: i64, kind: u32, n: u32 },
    /// A merchant buys an item from her bag for coin.
    Sell { hero: i64, item: i64 },
    Ping,
    // ---- the modules' requests: thin wrappers of their own wire types, coded and served by their `gate.rs`
    /// Merchants, trade, the market and letters (job E1, `economy::gate`).
    Econ(crate::economy::wire::EReq),
    /// Houses and the shared places (job H1, `homes::gate`).
    Home(crate::homes::HReq),
    /// Parties, guilds, friends, chat channels, reports (job T1, `social::gate`).
    Social(crate::social::SReq),
    /// The board, the queue, bot tickets, vaults (job W2, `world::gate`).
    World(crate::world::wire::WReq),
}

impl Req {
    pub fn encode(&self) -> (u8, Vec<u8>) {
        base::encode_req(self)
            .or_else(|| MODULES.iter().find_map(|m| (m.encode_req)(self)))
            .expect("every Req variant belongs to the core or a registered module")
    }

    /// Reads a request; `None` for a type nobody owns, a body that does not read whole, or a non-canonical one.
    pub fn decode(t: u8, b: &[u8]) -> Option<Req> {
        if !ranges::REQ_SPACE.has(t) {
            return None;
        }
        if ranges::CORE.req.has(t) {
            return base::decode_req(t, b);
        }
        (module_of(t)?.decode_req)(t, b)
    }
}

/// What the server answers or pushes, as a client reads it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Resp {
    Ok,
    Err { code: u16, msg: String },
    Login { account: i64 },
    Heroes(Vec<HeroInfo>),
    HeroCreated(i64),
    /// The room, your member id, the room's members, the town's size in px.
    Town { room: u32, me: u16, size: u16, members: Vec<Member> },
    /// Where the field host is (`host` empty: the gateway's own address), its UDP port, your ticket and its
    /// secret `key` (your HELLO must carry it; it only ever travels over the gateway's TLS).
    Ticket { host: String, port: u16, ticket: u64, field: u8, copy: u8, key: realm_server::TicketKey },
    Inventory(Inventory),
    Pong,
    /// A smith's result: the item now (0 when none), its `+`, whether the step worked, and what it cost or gave:
    /// embers for an upgrade's cost or a salvage's yield, coin for a socket, a rune's stack kind for a fuse.
    Smith { item: i64, plus: u8, success: bool, amount: u64 },
    /// The deck cards a hero owns (`Req::Cards`).
    Cards(Vec<u16>),
    /// An economy reply (`economy::wire`).
    Econ(crate::economy::wire::EResp),
    /// A social reply (job T1, tag 0x90).
    Social(crate::social::SResp),
    // pushes
    /// A social push (job T1, tag 0xB0): chat in the channels, invitations, roster changes.
    SocialPush(crate::social::SPush),
    Snapshot(TownSnapshot),
    Chat { from: u16, name: String, text: String },
    Arrive(Member),
    Depart(u16),
    /// A field outing's result, applied to the store: coin banked, class XP, levels gained, potions drunk, and why
    /// she left the field (0 gate, 1 waystone, 2 disconnect, 3 kicked, 4 shutdown, 5 her vault closed, 6 her field's host
    /// died (what was banked is kept, the haul is lost), 255 still there).
    Outing { hero: i64, coin: u64, xp: u64, levels: u16, potions: u32, left: u8 },
    /// An economy push: a trade update, a sale, a letter, an expiry.
    EconPush(crate::economy::wire::EResp),
    /// A world reply (`world::wire`).
    World(crate::world::wire::WResp),
    /// A world push: a queue place, a move to another copy, boss news.
    WorldPush(crate::world::wire::WResp),
    /// A homes reply (job H1, tag 0x8C) and push (0xA9): `homes::wire`.
    Home(crate::homes::HResp),
    HomePush(crate::homes::HResp),
}

impl Resp {
    pub fn encode(&self) -> (u8, Vec<u8>) {
        base::encode_resp(self)
            .or_else(|| MODULES.iter().find_map(|m| (m.encode_resp)(self)))
            .expect("every Resp variant belongs to the core or a registered module")
    }

    pub fn decode(t: u8, b: &[u8]) -> Option<Resp> {
        if !(ranges::REPLY_SPACE.has(t) || ranges::PUSH_SPACE.has(t)) {
            return None;
        }
        if ranges::CORE.has(t) {
            return base::decode_resp(t, b);
        }
        (module_of(t)?.decode_resp)(t, b)
    }
}

/// Reads a whole body with `f`: `None` unless every byte is used.
pub fn whole<T>(b: &[u8], f: impl FnOnce(&mut Rd) -> Option<T>) -> Option<T> {
    let mut r = Rd::new(b);
    let v = f(&mut r)?;
    (r.left() == 0).then_some(v)
}

/// A body written by `f`.
pub fn body(f: impl FnOnce(&mut Vec<u8>)) -> Vec<u8> {
    let mut w = Vec::new();
    f(&mut w);
    w
}

/// Frames: `u32 len, u8 type, u32 tag, body`.
pub fn frame(t: u8, tag: u32, body: &[u8]) -> Vec<u8> {
    let mut w = Vec::with_capacity(9 + body.len());
    put_u32(&mut w, 5 + body.len() as u32);
    w.push(t);
    put_u32(&mut w, tag);
    w.extend_from_slice(body);
    w
}

pub fn resp_frame(tag: u32, r: &Resp) -> Vec<u8> {
    let (t, body) = r.encode();
    frame(t, tag, &body)
}

/// Reads one frame (blocking): (type, tag, body). `Ok(None)` at a clean end of stream.
pub fn read_frame(s: &mut impl Read) -> std::io::Result<Option<(u8, u32, Vec<u8>)>> {
    let mut len = [0u8; 4];
    match s.read_exact(&mut len) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(e),
    }
    let len = u32::from_le_bytes(len) as usize;
    if !(5..=FRAME_MAX).contains(&len) {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "bad frame length"));
    }
    // Grown as the bytes come, so a header that promises a megabyte costs nothing until the megabyte is sent.
    let mut b = Vec::with_capacity(len.min(FRAME_FIRST_ALLOC));
    (&mut *s).take(len as u64).read_to_end(&mut b)?;
    if b.len() < len {
        return Err(std::io::Error::new(std::io::ErrorKind::UnexpectedEof, "frame cut short"));
    }
    let tag = u32::from_le_bytes([b[1], b[2], b[3], b[4]]);
    let t = b[0];
    b.drain(..5);
    Ok(Some((t, tag, b)))
}

pub fn write_all(s: &mut impl Write, b: &[u8]) -> std::io::Result<()> {
    s.write_all(b)?;
    s.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every module's examples (the core's too) read back as written; a trailing byte or a missing one is refused.
    #[test]
    fn every_message_of_every_module_survives_the_wire() {
        let mut all = vec![base::examples()];
        all.extend(MODULES.iter().map(|m| (m.examples)()));
        for (reqs, resps) in all {
            for q in reqs {
                let (t, b) = q.encode();
                assert_eq!(Req::decode(t, &b), Some(q.clone()), "{q:?}");
                assert!(Req::decode(t, &[b.clone(), vec![0]].concat()).is_none(), "a trailing byte is refused: {q:?}");
                if !b.is_empty() {
                    assert!(Req::decode(t, &b[..b.len() - 1]).is_none(), "a short {q:?} is refused");
                }
            }
            for p in resps {
                let (t, b) = p.encode();
                assert_eq!(Resp::decode(t, &b), Some(p.clone()), "{p:?}");
                assert!(Resp::decode(t, &[b.clone(), vec![0]].concat()).is_none(), "a trailing byte is refused: {p:?}");
            }
        }
        assert!(Req::decode(0x77, &[]).is_none());
        let inv = Inventory { items: vec![], stacks: vec![(3, 100, 4)] };
        assert_eq!(inv.stack(3, 100), 4);
        let f = resp_frame(9, &Resp::Pong);
        let (t, tag, body) = read_frame(&mut &f[..]).unwrap().unwrap();
        assert_eq!((t, tag, body.len()), (R_PONG, 9, 0));
        assert!(read_frame(&mut &[0xFF, 0xFF, 0xFF, 0x7F][..]).is_err(), "a huge frame is refused");
    }

    #[test]
    fn a_long_string_is_cut_at_a_character() {
        let s = "\u{e9}".repeat(40_000);
        let mut w = Vec::new();
        put_str(&mut w, &s);
        let back = read_str(&mut Rd::new(&w)).expect("still UTF-8");
        assert_eq!(back.len(), 65_534);
    }
}
