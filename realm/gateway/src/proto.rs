//! The gateway's wire: TCP, one frame after another, `u32 len, u8 type, u32 tag, body` (len counts type, tag
//! and body; at most `FRAME_MAX`). A request carries a tag the client chooses and the reply repeats it; what
//! the server sends by itself (town snapshots, chat, an outing's result) has tag 0.
//!
//! Strings are `u16 len, bytes` (UTF-8). A `Thing` is `u8 0, u64 item id` or `u8 1, u32 stack kind, u64 count`.

use realm_server::{put_u16, put_u32, put_u64, Rd};
use std::io::{Read, Write};

pub const FRAME_MAX: usize = 1 << 20;

// ---- requests
pub const T_LOGIN_DEV: u8 = 0x01;
pub const T_LOGIN_STEAM: u8 = 0x02;
pub const T_LIST_HEROES: u8 = 0x03;
pub const T_CREATE_HERO: u8 = 0x04;
pub const T_DELETE_HERO: u8 = 0x05;
pub const T_UNDELETE_HERO: u8 = 0x06;
pub const T_ENTER_TOWN: u8 = 0x07;
pub const T_LEAVE_TOWN: u8 = 0x08;
pub const T_TOWN_INPUT: u8 = 0x09;
pub const T_CHAT: u8 = 0x0A;
pub const T_FIELD_TICKET: u8 = 0x0B;
pub const T_INVENTORY: u8 = 0x0C;
pub const T_BANK_DEPOSIT: u8 = 0x0D;
pub const T_BANK_WITHDRAW: u8 = 0x0E;
pub const T_MAIL_SEND: u8 = 0x0F;
pub const T_MAIL_TAKE: u8 = 0x10;
pub const T_SPEND_POINT: u8 = 0x11;
pub const T_SET_DECK: u8 = 0x12;
pub const T_SET_BELT: u8 = 0x13;
pub const T_LEARN_PAGE: u8 = 0x14;
pub const T_EQUIP: u8 = 0x15;
pub const T_UNEQUIP: u8 = 0x16;
pub const T_SOCKET: u8 = 0x17;
pub const T_UNSOCKET: u8 = 0x18;
pub const T_CHOOSE_JOB: u8 = 0x19;
pub const T_PING: u8 = 0x1A;
pub const T_RENAME_HERO: u8 = 0x1B;
pub const T_SALVAGE: u8 = 0x1C;
pub const T_UPGRADE: u8 = 0x1D;
pub const T_REROLL: u8 = 0x1E;
pub const T_FUSE: u8 = 0x1F;
/// The shell's additions (job C2): the cards a hero may put in a deck, and a merchant's buy and sell.
pub const T_CARDS: u8 = 0x30;
pub const T_BUY: u8 = 0x31;
pub const T_SELL: u8 = 0x32;

// ---- replies
pub const R_OK: u8 = 0x80;
pub const R_ERR: u8 = 0x81;
pub const R_LOGIN: u8 = 0x82;
pub const R_HEROES: u8 = 0x83;
pub const R_HERO_CREATED: u8 = 0x84;
pub const R_TOWN: u8 = 0x85;
pub const R_TICKET: u8 = 0x86;
pub const R_INVENTORY: u8 = 0x87;
pub const R_PONG: u8 = 0x88;
pub const R_SMITH: u8 = 0x89;
pub const R_CARDS: u8 = 0x8A;

// ---- pushes (tag 0)
pub const P_TOWN_SNAPSHOT: u8 = 0xA0;
pub const P_TOWN_CHAT: u8 = 0xA1;
pub const P_TOWN_ARRIVE: u8 = 0xA2;
pub const P_TOWN_DEPART: u8 = 0xA3;
pub const P_OUTING: u8 = 0xA4;

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
}

pub fn put_str(w: &mut Vec<u8>, s: &str) {
    let b = s.as_bytes();
    put_u16(w, b.len().min(u16::MAX as usize) as u16);
    w.extend_from_slice(&b[..b.len().min(u16::MAX as usize)]);
}

pub fn read_str(r: &mut Rd) -> Option<String> {
    let n = r.u16()? as usize;
    String::from_utf8(r.bytes(n)?.to_vec()).ok()
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
}

impl Req {
    pub fn encode(&self) -> (u8, Vec<u8>) {
        let mut w = Vec::new();
        let t = match self {
            Req::LoginDev { name } => {
                put_str(&mut w, name);
                T_LOGIN_DEV
            }
            Req::LoginSteam { ticket } => {
                put_u16(&mut w, ticket.len() as u16);
                w.extend_from_slice(ticket);
                T_LOGIN_STEAM
            }
            Req::ListHeroes => T_LIST_HEROES,
            Req::CreateHero { name, race, class, look, self_found } => {
                put_str(&mut w, name);
                w.extend_from_slice(&[*race, *class, *self_found as u8]);
                put_u32(&mut w, *look);
                T_CREATE_HERO
            }
            Req::DeleteHero { hero } => {
                put_u64(&mut w, *hero as u64);
                T_DELETE_HERO
            }
            Req::UndeleteHero { hero } => {
                put_u64(&mut w, *hero as u64);
                T_UNDELETE_HERO
            }
            Req::RenameHero { hero, name } => {
                put_u64(&mut w, *hero as u64);
                put_str(&mut w, name);
                T_RENAME_HERO
            }
            Req::EnterTown { hero } => {
                put_u64(&mut w, *hero as u64);
                T_ENTER_TOWN
            }
            Req::LeaveTown => T_LEAVE_TOWN,
            Req::TownInput { dir } => {
                w.push(*dir);
                T_TOWN_INPUT
            }
            Req::Chat { text } => {
                put_str(&mut w, text);
                T_CHAT
            }
            Req::FieldTicket { hero, field } => {
                put_u64(&mut w, *hero as u64);
                w.push(*field);
                T_FIELD_TICKET
            }
            Req::Inventory { hero } => {
                put_u64(&mut w, *hero as u64);
                T_INVENTORY
            }
            Req::BankDeposit { hero, what, tab } => {
                put_u64(&mut w, *hero as u64);
                what.put(&mut w);
                put_u32(&mut w, *tab);
                T_BANK_DEPOSIT
            }
            Req::BankWithdraw { hero, what, tab } => {
                put_u64(&mut w, *hero as u64);
                what.put(&mut w);
                put_u32(&mut w, *tab);
                T_BANK_WITHDRAW
            }
            Req::MailSend { hero, to_name, what } => {
                put_u64(&mut w, *hero as u64);
                put_str(&mut w, to_name);
                what.put(&mut w);
                T_MAIL_SEND
            }
            Req::MailTake { hero, what } => {
                put_u64(&mut w, *hero as u64);
                what.put(&mut w);
                T_MAIL_TAKE
            }
            Req::SpendPoint { hero, stat, n } => {
                put_u64(&mut w, *hero as u64);
                w.push(*stat);
                put_u16(&mut w, *n);
                T_SPEND_POINT
            }
            Req::SetDeck { hero, cards } => {
                put_u64(&mut w, *hero as u64);
                w.push(cards.len() as u8);
                for c in cards {
                    put_u16(&mut w, *c);
                }
                T_SET_DECK
            }
            Req::SetBelt { hero, kinds } => {
                put_u64(&mut w, *hero as u64);
                for k in kinds {
                    put_u32(&mut w, *k);
                }
                T_SET_BELT
            }
            Req::LearnPage { hero, card } => {
                put_u64(&mut w, *hero as u64);
                put_u16(&mut w, *card);
                T_LEARN_PAGE
            }
            Req::Equip { hero, item } => {
                put_u64(&mut w, *hero as u64);
                put_u64(&mut w, *item as u64);
                T_EQUIP
            }
            Req::Unequip { hero, item } => {
                put_u64(&mut w, *hero as u64);
                put_u64(&mut w, *item as u64);
                T_UNEQUIP
            }
            Req::Socket { hero, item, socket, kind } => {
                put_u64(&mut w, *hero as u64);
                put_u64(&mut w, *item as u64);
                w.push(*socket);
                put_u32(&mut w, *kind);
                T_SOCKET
            }
            Req::Unsocket { hero, item, socket } => {
                put_u64(&mut w, *hero as u64);
                put_u64(&mut w, *item as u64);
                w.push(*socket);
                T_UNSOCKET
            }
            Req::ChooseJob { hero, job } => {
                put_u64(&mut w, *hero as u64);
                w.push(*job);
                T_CHOOSE_JOB
            }
            Req::Salvage { hero, item } | Req::Upgrade { hero, item } | Req::Reroll { hero, item } => {
                put_u64(&mut w, *hero as u64);
                put_u64(&mut w, *item as u64);
                match self {
                    Req::Salvage { .. } => T_SALVAGE,
                    Req::Upgrade { .. } => T_UPGRADE,
                    _ => T_REROLL,
                }
            }
            Req::Fuse { hero, stat, grade } => {
                put_u64(&mut w, *hero as u64);
                w.extend_from_slice(&[*stat, *grade]);
                T_FUSE
            }
            Req::Cards { hero } => {
                put_u64(&mut w, *hero as u64);
                T_CARDS
            }
            Req::Buy { hero, kind, n } => {
                put_u64(&mut w, *hero as u64);
                put_u32(&mut w, *kind);
                put_u32(&mut w, *n);
                T_BUY
            }
            Req::Sell { hero, item } => {
                put_u64(&mut w, *hero as u64);
                put_u64(&mut w, *item as u64);
                T_SELL
            }
            Req::Ping => T_PING,
        };
        (t, w)
    }

    pub fn decode(t: u8, b: &[u8]) -> Option<Req> {
        let mut r = Rd::new(b);
        let hero = |r: &mut Rd| r.u64().map(|v| v as i64);
        let req = match t {
            T_LOGIN_DEV => Req::LoginDev { name: read_str(&mut r)? },
            T_LOGIN_STEAM => {
                let n = r.u16()? as usize;
                Req::LoginSteam { ticket: r.bytes(n)?.to_vec() }
            }
            T_LIST_HEROES => Req::ListHeroes,
            T_CREATE_HERO => {
                let name = read_str(&mut r)?;
                Req::CreateHero { name, race: r.u8()?, class: r.u8()?, self_found: r.u8()? != 0, look: r.u32()? }
            }
            T_DELETE_HERO => Req::DeleteHero { hero: hero(&mut r)? },
            T_UNDELETE_HERO => Req::UndeleteHero { hero: hero(&mut r)? },
            T_RENAME_HERO => Req::RenameHero { hero: hero(&mut r)?, name: read_str(&mut r)? },
            T_ENTER_TOWN => Req::EnterTown { hero: hero(&mut r)? },
            T_LEAVE_TOWN => Req::LeaveTown,
            T_TOWN_INPUT => Req::TownInput { dir: r.u8()? },
            T_CHAT => Req::Chat { text: read_str(&mut r)? },
            T_FIELD_TICKET => Req::FieldTicket { hero: hero(&mut r)?, field: r.u8()? },
            T_INVENTORY => Req::Inventory { hero: hero(&mut r)? },
            T_BANK_DEPOSIT => Req::BankDeposit { hero: hero(&mut r)?, what: Thing::read(&mut r)?, tab: r.u32()? },
            T_BANK_WITHDRAW => Req::BankWithdraw { hero: hero(&mut r)?, what: Thing::read(&mut r)?, tab: r.u32()? },
            T_MAIL_SEND => Req::MailSend { hero: hero(&mut r)?, to_name: read_str(&mut r)?, what: Thing::read(&mut r)? },
            T_MAIL_TAKE => Req::MailTake { hero: hero(&mut r)?, what: Thing::read(&mut r)? },
            T_SPEND_POINT => Req::SpendPoint { hero: hero(&mut r)?, stat: r.u8()?, n: r.u16()? },
            T_SET_DECK => {
                let h = hero(&mut r)?;
                let n = r.u8()? as usize;
                let cards = (0..n).map(|_| r.u16()).collect::<Option<Vec<u16>>>()?;
                Req::SetDeck { hero: h, cards }
            }
            T_SET_BELT => Req::SetBelt { hero: hero(&mut r)?, kinds: [r.u32()?, r.u32()?, r.u32()?] },
            T_LEARN_PAGE => Req::LearnPage { hero: hero(&mut r)?, card: r.u16()? },
            T_EQUIP => Req::Equip { hero: hero(&mut r)?, item: hero(&mut r)? },
            T_UNEQUIP => Req::Unequip { hero: hero(&mut r)?, item: hero(&mut r)? },
            T_SOCKET => Req::Socket { hero: hero(&mut r)?, item: hero(&mut r)?, socket: r.u8()?, kind: r.u32()? },
            T_UNSOCKET => Req::Unsocket { hero: hero(&mut r)?, item: hero(&mut r)?, socket: r.u8()? },
            T_CHOOSE_JOB => Req::ChooseJob { hero: hero(&mut r)?, job: r.u8()? },
            T_SALVAGE => Req::Salvage { hero: hero(&mut r)?, item: hero(&mut r)? },
            T_UPGRADE => Req::Upgrade { hero: hero(&mut r)?, item: hero(&mut r)? },
            T_REROLL => Req::Reroll { hero: hero(&mut r)?, item: hero(&mut r)? },
            T_FUSE => Req::Fuse { hero: hero(&mut r)?, stat: r.u8()?, grade: r.u8()? },
            T_CARDS => Req::Cards { hero: hero(&mut r)? },
            T_BUY => Req::Buy { hero: hero(&mut r)?, kind: r.u32()?, n: r.u32()? },
            T_SELL => Req::Sell { hero: hero(&mut r)?, item: hero(&mut r)? },
            T_PING => Req::Ping,
            _ => return None,
        };
        (r.left() == 0).then_some(req)
    }
}

/// A hero as the character list shows her.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HeroInfo {
    pub id: i64,
    pub name: String,
    pub race: u8,
    pub class: u8,
    pub look: u32,
    pub job: u8,
    pub class_level: u16,
    pub class_xp: u64,
    pub unspent: u16,
    pub stats: [u16; 6],
    pub deck: Vec<u16>,
    pub belt: [u32; 3],
    pub waystones: [i32; 6],
    pub self_found: bool,
    pub deleted: bool,
}

impl HeroInfo {
    pub fn put(&self, w: &mut Vec<u8>) {
        put_u64(w, self.id as u64);
        put_str(w, &self.name);
        w.extend_from_slice(&[self.race, self.class, self.job, self.self_found as u8, self.deleted as u8]);
        put_u32(w, self.look);
        put_u16(w, self.class_level);
        put_u64(w, self.class_xp);
        put_u16(w, self.unspent);
        for s in self.stats {
            put_u16(w, s);
        }
        w.push(self.deck.len() as u8);
        for c in &self.deck {
            put_u16(w, *c);
        }
        for b in self.belt {
            put_u32(w, b);
        }
        for s in self.waystones {
            put_u32(w, s as u32);
        }
    }

    pub fn read(r: &mut Rd) -> Option<HeroInfo> {
        let id = r.u64()? as i64;
        let name = read_str(r)?;
        let (race, class, job, self_found, deleted) = (r.u8()?, r.u8()?, r.u8()?, r.u8()? != 0, r.u8()? != 0);
        let look = r.u32()?;
        let (class_level, class_xp, unspent) = (r.u16()?, r.u64()?, r.u16()?);
        let mut stats = [0u16; 6];
        for s in stats.iter_mut() {
            *s = r.u16()?;
        }
        let n = r.u8()? as usize;
        let deck = (0..n).map(|_| r.u16()).collect::<Option<Vec<u16>>>()?;
        let belt = [r.u32()?, r.u32()?, r.u32()?];
        let mut waystones = [0i32; 6];
        for s in waystones.iter_mut() {
            *s = r.u32()? as i32;
        }
        Some(HeroInfo { id, name, race, class, look, job, class_level, class_xp, unspent, stats, deck, belt, waystones, self_found, deleted })
    }
}

/// One item as the inventory lists it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ItemInfo {
    pub id: i64,
    pub base: u32,
    pub gear_slot: u8,
    pub level: u16,
    pub rarity: u8,
    pub lines: Vec<(u8, u16)>,
    pub sockets: u8,
    /// Place kind (`PlaceKind as i64`), tab and slot.
    pub kind: u8,
    pub tab: u32,
    pub slot: u32,
    /// The smith's `+` (0 to 10).
    pub plus: u8,
    /// What each socket holds (a stack kind: a rune or a monster card), 0 when empty; `sockets` entries.
    pub socketed: Vec<u32>,
}

impl ItemInfo {
    pub fn put(&self, w: &mut Vec<u8>) {
        put_u64(w, self.id as u64);
        put_u32(w, self.base);
        w.extend_from_slice(&[self.gear_slot, self.rarity, self.sockets, self.kind]);
        put_u16(w, self.level);
        put_u32(w, self.tab);
        put_u32(w, self.slot);
        w.push(self.lines.len() as u8);
        for (s, p) in &self.lines {
            w.push(*s);
            put_u16(w, *p);
        }
        w.push(self.plus);
        for i in 0..self.sockets as usize {
            put_u32(w, self.socketed.get(i).copied().unwrap_or(0));
        }
    }
    pub fn read(r: &mut Rd) -> Option<ItemInfo> {
        let id = r.u64()? as i64;
        let base = r.u32()?;
        let (gear_slot, rarity, sockets, kind) = (r.u8()?, r.u8()?, r.u8()?, r.u8()?);
        let (level, tab, slot) = (r.u16()?, r.u32()?, r.u32()?);
        let n = r.u8()? as usize;
        let lines = (0..n).map(|_| Some((r.u8()?, r.u16()?))).collect::<Option<Vec<_>>>()?;
        let plus = r.u8()?;
        let socketed = (0..sockets).map(|_| r.u32()).collect::<Option<Vec<_>>>()?;
        Some(ItemInfo { id, base, gear_slot, level, rarity, lines, sockets, kind, tab, slot, plus, socketed })
    }
}

/// A hero's things: items in her bag, worn and mail, the account's bank, and the stacks of each.
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct Inventory {
    pub items: Vec<ItemInfo>,
    /// (place kind, stack kind, count): bag, bank and mail.
    pub stacks: Vec<(u8, u32, u64)>,
}

impl Inventory {
    pub fn put(&self, w: &mut Vec<u8>) {
        put_u32(w, self.items.len() as u32);
        for i in &self.items {
            i.put(w);
        }
        put_u32(w, self.stacks.len() as u32);
        for (p, k, n) in &self.stacks {
            w.push(*p);
            put_u32(w, *k);
            put_u64(w, *n);
        }
    }
    pub fn read(r: &mut Rd) -> Option<Inventory> {
        let n = r.u32()? as usize;
        let items = (0..n).map(|_| ItemInfo::read(r)).collect::<Option<Vec<_>>>()?;
        let n = r.u32()? as usize;
        let stacks = (0..n).map(|_| Some((r.u8()?, r.u32()?, r.u64()?))).collect::<Option<Vec<_>>>()?;
        Some(Inventory { items, stacks })
    }
    /// A stack count at a place kind (`PlaceKind as u8`), 0 when there is none.
    pub fn stack(&self, place: u8, kind: u32) -> u64 {
        self.stacks.iter().find(|s| s.0 == place && s.1 == kind).map_or(0, |s| s.2)
    }
}

/// A town member as the roster lists her.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Member {
    pub id: u16,
    pub name: String,
    pub class: u8,
    pub race: u8,
    pub level: u16,
    pub look: u32,
}

impl Member {
    pub fn put(&self, w: &mut Vec<u8>) {
        put_u16(w, self.id);
        put_str(w, &self.name);
        w.extend_from_slice(&[self.class, self.race]);
        put_u16(w, self.level);
        put_u32(w, self.look);
    }
    pub fn read(r: &mut Rd) -> Option<Member> {
        Some(Member { id: r.u16()?, name: read_str(r)?, class: r.u8()?, race: r.u8()?, level: r.u16()?, look: r.u32()? })
    }
}

/// A town snapshot: every member's place, whole px, 10 times a second.
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct TownSnapshot {
    pub tick: u32,
    /// (member id, x px, y px, direction 0..8)
    pub at: Vec<(u16, u16, u16, u8)>,
}

impl TownSnapshot {
    pub fn put(&self, w: &mut Vec<u8>) {
        put_u32(w, self.tick);
        put_u16(w, self.at.len() as u16);
        for &(id, x, y, d) in &self.at {
            put_u16(w, id);
            put_u16(w, x);
            put_u16(w, y);
            w.push(d);
        }
    }
    pub fn read(r: &mut Rd) -> Option<TownSnapshot> {
        let tick = r.u32()?;
        let n = r.u16()? as usize;
        let at = (0..n).map(|_| Some((r.u16()?, r.u16()?, r.u16()?, r.u8()?))).collect::<Option<Vec<_>>>()?;
        Some(TownSnapshot { tick, at })
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
    /// Where the field host is (`host` empty: the gateway's own address), its UDP port and your ticket.
    Ticket { host: String, port: u16, ticket: u64, field: u8, copy: u8 },
    Inventory(Inventory),
    Pong,
    /// A smith's result: the item now (0 when none), its `+`, whether the step worked, and what it cost or gave:
    /// embers for an upgrade's cost or a salvage's yield, coin for a socket, a rune's stack kind for a fuse.
    Smith { item: i64, plus: u8, success: bool, amount: u64 },
    /// The deck cards a hero owns (`Req::Cards`).
    Cards(Vec<u16>),
    // pushes
    Snapshot(TownSnapshot),
    Chat { from: u16, name: String, text: String },
    Arrive(Member),
    Depart(u16),
    /// A field outing's result, applied to the store: coin banked, class XP, levels gained, potions drunk, and why
    /// she left the field (0 gate, 1 waystone, 2 disconnect, 3 kicked, 4 shutdown, 255 still there).
    Outing { hero: i64, coin: u64, xp: u64, levels: u16, potions: u32, left: u8 },
}

impl Resp {
    pub fn encode(&self) -> (u8, Vec<u8>) {
        let mut w = Vec::new();
        let t = match self {
            Resp::Ok => R_OK,
            Resp::Err { code, msg } => {
                put_u16(&mut w, *code);
                put_str(&mut w, msg);
                R_ERR
            }
            Resp::Login { account } => {
                put_u64(&mut w, *account as u64);
                R_LOGIN
            }
            Resp::Heroes(v) => {
                put_u16(&mut w, v.len() as u16);
                for h in v {
                    h.put(&mut w);
                }
                R_HEROES
            }
            Resp::HeroCreated(id) => {
                put_u64(&mut w, *id as u64);
                R_HERO_CREATED
            }
            Resp::Town { room, me, size, members } => {
                put_u32(&mut w, *room);
                put_u16(&mut w, *me);
                put_u16(&mut w, *size);
                put_u16(&mut w, members.len() as u16);
                for m in members {
                    m.put(&mut w);
                }
                R_TOWN
            }
            Resp::Ticket { host, port, ticket, field, copy } => {
                put_str(&mut w, host);
                put_u16(&mut w, *port);
                put_u64(&mut w, *ticket);
                w.extend_from_slice(&[*field, *copy]);
                R_TICKET
            }
            Resp::Inventory(i) => {
                i.put(&mut w);
                R_INVENTORY
            }
            Resp::Pong => R_PONG,
            Resp::Smith { item, plus, success, amount } => {
                put_u64(&mut w, *item as u64);
                w.extend_from_slice(&[*plus, *success as u8]);
                put_u64(&mut w, *amount);
                R_SMITH
            }
            Resp::Cards(v) => {
                put_u16(&mut w, v.len() as u16);
                for c in v {
                    put_u16(&mut w, *c);
                }
                R_CARDS
            }
            Resp::Snapshot(s) => {
                s.put(&mut w);
                P_TOWN_SNAPSHOT
            }
            Resp::Chat { from, name, text } => {
                put_u16(&mut w, *from);
                put_str(&mut w, name);
                put_str(&mut w, text);
                P_TOWN_CHAT
            }
            Resp::Arrive(m) => {
                m.put(&mut w);
                P_TOWN_ARRIVE
            }
            Resp::Depart(id) => {
                put_u16(&mut w, *id);
                P_TOWN_DEPART
            }
            Resp::Outing { hero, coin, xp, levels, potions, left } => {
                put_u64(&mut w, *hero as u64);
                put_u64(&mut w, *coin);
                put_u64(&mut w, *xp);
                put_u16(&mut w, *levels);
                put_u32(&mut w, *potions);
                w.push(*left);
                P_OUTING
            }
        };
        (t, w)
    }

    pub fn decode(t: u8, b: &[u8]) -> Option<Resp> {
        let mut r = Rd::new(b);
        let resp = match t {
            R_OK => Resp::Ok,
            R_ERR => Resp::Err { code: r.u16()?, msg: read_str(&mut r)? },
            R_LOGIN => Resp::Login { account: r.u64()? as i64 },
            R_HEROES => {
                let n = r.u16()? as usize;
                Resp::Heroes((0..n).map(|_| HeroInfo::read(&mut r)).collect::<Option<Vec<_>>>()?)
            }
            R_HERO_CREATED => Resp::HeroCreated(r.u64()? as i64),
            R_TOWN => {
                let (room, me, size) = (r.u32()?, r.u16()?, r.u16()?);
                let n = r.u16()? as usize;
                Resp::Town { room, me, size, members: (0..n).map(|_| Member::read(&mut r)).collect::<Option<Vec<_>>>()? }
            }
            R_TICKET => Resp::Ticket { host: read_str(&mut r)?, port: r.u16()?, ticket: r.u64()?, field: r.u8()?, copy: r.u8()? },
            R_INVENTORY => Resp::Inventory(Inventory::read(&mut r)?),
            R_PONG => Resp::Pong,
            R_SMITH => Resp::Smith { item: r.u64()? as i64, plus: r.u8()?, success: r.u8()? != 0, amount: r.u64()? },
            R_CARDS => {
                let n = r.u16()? as usize;
                Resp::Cards((0..n).map(|_| r.u16()).collect::<Option<Vec<_>>>()?)
            }
            P_TOWN_SNAPSHOT => Resp::Snapshot(TownSnapshot::read(&mut r)?),
            P_TOWN_CHAT => Resp::Chat { from: r.u16()?, name: read_str(&mut r)?, text: read_str(&mut r)? },
            P_TOWN_ARRIVE => Resp::Arrive(Member::read(&mut r)?),
            P_TOWN_DEPART => Resp::Depart(r.u16()?),
            P_OUTING => Resp::Outing { hero: r.u64()? as i64, coin: r.u64()?, xp: r.u64()?, levels: r.u16()?, potions: r.u32()?, left: r.u8()? },
            _ => return None,
        };
        (r.left() == 0).then_some(resp)
    }
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
    let mut b = vec![0u8; len];
    s.read_exact(&mut b)?;
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

    #[test]
    fn every_request_survives_the_wire() {
        let reqs = vec![
            Req::LoginDev { name: "ann".into() },
            Req::LoginSteam { ticket: vec![1, 2, 3] },
            Req::ListHeroes,
            Req::CreateHero { name: "Mira".into(), race: 2, class: 3, look: 77, self_found: true },
            Req::DeleteHero { hero: 5 },
            Req::UndeleteHero { hero: 5 },
            Req::RenameHero { hero: 5, name: "Nia".into() },
            Req::EnterTown { hero: 9 },
            Req::LeaveTown,
            Req::TownInput { dir: 3 },
            Req::Chat { text: "hello town".into() },
            Req::FieldTicket { hero: 4, field: 2 },
            Req::Inventory { hero: 4 },
            Req::BankDeposit { hero: 4, what: Thing::Item(12), tab: 0 },
            Req::BankWithdraw { hero: 4, what: Thing::Stack(1, 99), tab: 1 },
            Req::MailSend { hero: 4, to_name: "Bo".into(), what: Thing::Stack(100, 2) },
            Req::MailTake { hero: 4, what: Thing::Item(3) },
            Req::SpendPoint { hero: 4, stat: 2, n: 3 },
            Req::SetDeck { hero: 4, cards: vec![0, 1, 2, 3] },
            Req::SetBelt { hero: 4, kinds: [100, 0, 102] },
            Req::LearnPage { hero: 4, card: 14 },
            Req::Equip { hero: 4, item: 8 },
            Req::Unequip { hero: 4, item: 8 },
            Req::Socket { hero: 4, item: 8, socket: 1, kind: 2011 },
            Req::Unsocket { hero: 4, item: 8, socket: 0 },
            Req::ChooseJob { hero: 4, job: 3 },
            Req::Salvage { hero: 4, item: 9 },
            Req::Upgrade { hero: 4, item: 9 },
            Req::Reroll { hero: 4, item: 9 },
            Req::Fuse { hero: 4, stat: 2, grade: 1 },
            Req::Cards { hero: 4 },
            Req::Buy { hero: 4, kind: 100, n: 3 },
            Req::Sell { hero: 4, item: 9 },
            Req::Ping,
        ];
        for q in reqs {
            let (t, b) = q.encode();
            assert_eq!(Req::decode(t, &b), Some(q.clone()), "{q:?}");
            assert!(Req::decode(t, &[b.clone(), vec![0]].concat()).is_none(), "a trailing byte is refused");
        }
        assert!(Req::decode(0x77, &[]).is_none());
    }

    #[test]
    fn every_reply_and_push_survives_the_wire() {
        let hero = HeroInfo { id: 3, name: "Mira".into(), race: 1, class: 2, look: 9, job: 0, class_level: 12, class_xp: 6000, unspent: 2, stats: [1, 2, 3, 4, 0, 0], deck: vec![0, 1], belt: [100, 0, 105], waystones: [-1, 2, -1, -1, -1, -1], self_found: false, deleted: false };
        let inv = Inventory {
            items: vec![ItemInfo { id: 5, base: 2, gear_slot: 1, level: 10, rarity: 2, lines: vec![(0, 3), (2, 1)], sockets: 1, kind: 1, tab: 0, slot: 4, plus: 2, socketed: vec![2011] }],
            stacks: vec![(1, 1, 500), (3, 100, 4)],
        };
        let rs = vec![
            Resp::Ok,
            Resp::Err { code: code::FULL, msg: "bag".into() },
            Resp::Login { account: 8 },
            Resp::Heroes(vec![hero]),
            Resp::HeroCreated(11),
            Resp::Town { room: 2, me: 3, size: 4096, members: vec![Member { id: 3, name: "Mira".into(), class: 2, race: 1, level: 12, look: 9 }] },
            Resp::Ticket { host: String::new(), port: 7801, ticket: 0xDEAD_BEEF_1234, field: 1, copy: 0 },
            Resp::Inventory(inv.clone()),
            Resp::Pong,
            Resp::Smith { item: 5, plus: 3, success: true, amount: 120 },
            Resp::Cards(vec![0, 1, 12, 25]),
            Resp::Snapshot(TownSnapshot { tick: 77, at: vec![(1, 100, 200, 3), (2, 4000, 5, 0)] }),
            Resp::Chat { from: 1, name: "Bo".into(), text: "hi".into() },
            Resp::Arrive(Member { id: 4, name: "Zed".into(), class: 1, race: 0, level: 3, look: 0 }),
            Resp::Depart(4),
            Resp::Outing { hero: 3, coin: 50, xp: 700, levels: 1, potions: 2, left: 1 },
        ];
        for r in rs {
            let (t, b) = r.encode();
            assert_eq!(Resp::decode(t, &b), Some(r.clone()), "{r:?}");
        }
        assert_eq!(inv.stack(3, 100), 4);
        let f = resp_frame(9, &Resp::Pong);
        let (t, tag, body) = read_frame(&mut &f[..]).unwrap().unwrap();
        assert_eq!((t, tag, body.len()), (R_PONG, 9, 0));
        assert!(read_frame(&mut &[0xFF, 0xFF, 0xFF, 0x7F][..]).is_err(), "a huge frame is refused");
    }
}
