//! The gateway's own messages (module `core` in `ranges`): login, heroes, the town, the bag and bank, the smith,
//! field tickets. Every other module's messages are in its own `gate.rs`.

use super::{put_str, read_str, Req, Resp, Thing, WireRead};
use realm_server::{put_u16, put_u32, put_u64, Rd};

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
        let (race, class, job, self_found, deleted) = (r.u8()?, r.u8()?, r.u8()?, r.flag()?, r.flag()?);
        let look = r.u32()?;
        let (class_level, class_xp, unspent) = (r.u16()?, r.u64()?, r.u16()?);
        let mut stats = [0u16; 6];
        for s in stats.iter_mut() {
            *s = r.u16()?;
        }
        let n = r.count8()?;
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
        let n = r.count8()?;
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
        let n = r.count32()?;
        let items = (0..n).map(|_| ItemInfo::read(r)).collect::<Option<Vec<_>>>()?;
        let n = r.count32()?;
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
        let n = r.count16()?;
        let at = (0..n).map(|_| Some((r.u16()?, r.u16()?, r.u16()?, r.u8()?))).collect::<Option<Vec<_>>>()?;
        Some(TownSnapshot { tick, at })
    }
}


pub fn encode_req(q: &Req) -> Option<(u8, Vec<u8>)> {
    let mut w = Vec::new();
    let t = match q {
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
            match q {
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
        _ => return None,
    };
    Some((t, w))
}

pub fn decode_req(t: u8, b: &[u8]) -> Option<Req> {
    let mut r = Rd::new(b);
    let hero = |r: &mut Rd| r.u64().map(|v| v as i64);
    let req = match t {
        T_LOGIN_DEV => Req::LoginDev { name: read_str(&mut r)? },
        T_LOGIN_STEAM => {
            let n = r.count16()?;
            Req::LoginSteam { ticket: r.bytes(n)?.to_vec() }
        }
        T_LIST_HEROES => Req::ListHeroes,
        T_CREATE_HERO => {
            let name = read_str(&mut r)?;
            Req::CreateHero { name, race: r.u8()?, class: r.u8()?, self_found: r.flag()?, look: r.u32()? }
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
            let n = r.count8()?;
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

pub fn encode_resp(p: &Resp) -> Option<(u8, Vec<u8>)> {
    let mut w = Vec::new();
    let t = match p {
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
        _ => return None,
    };
    Some((t, w))
}

pub fn decode_resp(t: u8, b: &[u8]) -> Option<Resp> {
    let mut r = Rd::new(b);
    let resp = match t {
        R_OK => Resp::Ok,
        R_ERR => Resp::Err { code: r.u16()?, msg: read_str(&mut r)? },
        R_LOGIN => Resp::Login { account: r.u64()? as i64 },
        R_HEROES => {
            let n = r.count16()?;
            Resp::Heroes((0..n).map(|_| HeroInfo::read(&mut r)).collect::<Option<Vec<_>>>()?)
        }
        R_HERO_CREATED => Resp::HeroCreated(r.u64()? as i64),
        R_TOWN => {
            let (room, me, size) = (r.u32()?, r.u16()?, r.u16()?);
            let n = r.count16()?;
            Resp::Town { room, me, size, members: (0..n).map(|_| Member::read(&mut r)).collect::<Option<Vec<_>>>()? }
        }
        R_TICKET => Resp::Ticket { host: read_str(&mut r)?, port: r.u16()?, ticket: r.u64()?, field: r.u8()?, copy: r.u8()? },
        R_INVENTORY => Resp::Inventory(Inventory::read(&mut r)?),
        R_PONG => Resp::Pong,
        R_SMITH => Resp::Smith { item: r.u64()? as i64, plus: r.u8()?, success: r.flag()?, amount: r.u64()? },
        R_CARDS => {
            let n = r.count16()?;
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

/// One of each core message, for the round trip tests and the decoder fuzz.
#[cfg(test)]
pub(super) fn examples() -> (Vec<Req>, Vec<Resp>) {
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
    ];
    let hero = HeroInfo { id: 3, name: "Mira".into(), race: 1, class: 2, look: 9, job: 0, class_level: 12, class_xp: 6000, unspent: 2, stats: [1, 2, 3, 4, 0, 0], deck: vec![0, 1], belt: [100, 0, 105], waystones: [-1, 2, -1, -1, -1, -1], self_found: false, deleted: false };
    let inv = Inventory {
        items: vec![ItemInfo { id: 5, base: 2, gear_slot: 1, level: 10, rarity: 2, lines: vec![(0, 3), (2, 1)], sockets: 1, kind: 1, tab: 0, slot: 4, plus: 2, socketed: vec![2011] }],
        stacks: vec![(1, 1, 500), (3, 100, 4)],
    };
    let resps = vec![
        Resp::Ok,
        Resp::Err { code: super::code::FULL, msg: "bag".into() },
        Resp::Login { account: 8 },
        Resp::Heroes(vec![hero]),
        Resp::HeroCreated(11),
        Resp::Town { room: 2, me: 3, size: 4096, members: vec![Member { id: 3, name: "Mira".into(), class: 2, race: 1, level: 12, look: 9 }] },
        Resp::Ticket { host: String::new(), port: 7801, ticket: 0xDEAD_BEEF_1234, field: 1, copy: 0 },
        Resp::Inventory(inv),
        Resp::Pong,
        Resp::Smith { item: 5, plus: 3, success: true, amount: 120 },
        Resp::Cards(vec![0, 1, 12, 25]),
        Resp::Snapshot(TownSnapshot { tick: 77, at: vec![(1, 100, 200, 3), (2, 4000, 5, 0)] }),
        Resp::Chat { from: 1, name: "Bo".into(), text: "hi".into() },
        Resp::Arrive(Member { id: 4, name: "Zed".into(), class: 1, race: 0, level: 3, look: 0 }),
        Resp::Depart(4),
        Resp::Outing { hero: 3, coin: 50, xp: 700, levels: 1, potions: 2, left: 1 },
    ];
    (reqs, resps)
}
