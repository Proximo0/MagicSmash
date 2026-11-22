//! The social calls on the wire (job T1). Requests are tags `0x40..=0x5F`, replies `R_SOCIAL` 0x90, pushes `P_SOCIAL`
//! 0xB0. The codec is here so `proto.rs` only carries one variant of each; `docs/realm/social.md` lists every tag.

use crate::proto::{put_str, read_str, ItemInfo, Thing};
use realm_server::{put_u16, put_u32, put_u64, Rd};

pub const T_SOC_FIRST: u8 = 0x40;
pub const T_SOC_LAST: u8 = 0x5F;
pub const R_SOCIAL: u8 = 0x90;
pub const P_SOCIAL: u8 = 0xB0;

/// Chat channels. Say (the town room) is the older `Req::Chat`; these are the rest.
pub mod chan {
    pub const SAY: u8 = 0;
    pub const TOWN: u8 = 1;
    pub const TRADE: u8 = 2;
    pub const PARTY: u8 = 3;
    pub const GUILD: u8 = 4;
    pub const WHISPER: u8 = 5;
    pub const COUNT: usize = 6;
}

/// What a client asks. Every request names the acting hero (the one in town or field on this connection).
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SReq {
    /// `chan` TOWN, TRADE, PARTY, GUILD or WHISPER; `to` is the hero's name for a whisper.
    Talk { hero: i64, chan: u8, to: String, text: String },
    PartyInvite { hero: i64, name: String },
    PartyAnswer { hero: i64, inviter: i64, accept: bool },
    PartyLeave { hero: i64 },
    PartyKick { hero: i64, target: i64 },
    PartyLead { hero: i64, target: i64 },
    /// The leader calls the party to a field: members are told and then ask for their tickets, which share a copy.
    PartyGo { hero: i64, field: u8 },
    PartyInfo { hero: i64 },
    GuildCreate { hero: i64, name: String },
    GuildInvite { hero: i64, name: String },
    GuildAnswer { hero: i64, guild: u64, accept: bool },
    GuildLeave { hero: i64 },
    GuildKick { hero: i64, target: i64 },
    /// Sets an account's rank (0 leader .. 3 recruit); rank 0 hands the guild over.
    GuildRank { hero: i64, target: i64, rank: u8 },
    GuildPerms { hero: i64, rank: u8, perms: u16 },
    GuildMotd { hero: i64, text: String },
    GuildPost { hero: i64, text: String },
    GuildUnpost { hero: i64, post: u64 },
    GuildBank { hero: i64, what: Thing, tab: u32, deposit: bool },
    GuildBankView { hero: i64, tab: u32 },
    GuildInfo { hero: i64 },
    GuildDisband { hero: i64 },
    FriendAdd { hero: i64, name: String },
    FriendAnswer { hero: i64, from: i64, accept: bool },
    FriendRemove { hero: i64, target: i64 },
    Ignore { hero: i64, name: String, on: bool },
    Lists { hero: i64 },
    /// `reason` 0 spam, 1 abuse, 2 cheating, 3 name, 4 other.
    Report { hero: i64, name: String, reason: u8, text: String },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PartyMember {
    pub hero: i64,
    pub name: String,
    pub class: u8,
    pub level: u16,
    pub online: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PartyView {
    pub id: u64,
    pub leader: i64,
    pub members: Vec<PartyMember>,
    /// The field copy the party's tickets share: (field, copy), if one is set.
    pub copy: Option<(u8, u8)>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GuildMember {
    pub account: i64,
    pub name: String,
    pub rank: u8,
    pub online: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Post {
    pub id: u64,
    pub author: String,
    pub text: String,
    /// Unix ms.
    pub at: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GuildView {
    pub id: u64,
    pub name: String,
    pub motd: String,
    pub my_rank: u8,
    /// Permission bits (`guild::perm`) of ranks 0..4.
    pub perms: [u16; 4],
    pub members: Vec<GuildMember>,
    pub board: Vec<Post>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FriendRow {
    pub account: i64,
    pub name: String,
    pub online: bool,
    /// 0 offline, 1 town, 2 field.
    pub place: u8,
}

#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct Lists {
    pub friends: Vec<FriendRow>,
    /// Friend requests waiting for her answer: (account, name).
    pub pending: Vec<(i64, String)>,
    pub ignores: Vec<(i64, String)>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SResp {
    Party(Option<PartyView>),
    Guild(Option<GuildView>),
    GuildCreated(u64),
    Bank { items: Vec<ItemInfo>, stacks: Vec<(u32, u64)> },
    Lists(Lists),
    Reported(u64),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SPush {
    /// A chat line: `chan`, who said it, to whom (whispers) and the text.
    Chat { chan: u8, from: String, to: String, text: String },
    PartyInvite { inviter: i64, name: String },
    PartyUpdate(Option<PartyView>),
    PartyGo { field: u8 },
    GuildInvite { guild: u64, guild_name: String, from: String },
    /// Roster, ranks, motd, board or perms changed: ask `GuildInfo` again.
    GuildChanged,
    FriendRequest { from: i64, name: String },
    FriendStatus { account: i64, name: String, online: bool, place: u8 },
    /// The server says something to this player (muted, silenced, kicked, a rule).
    Notice { text: String },
}

// ---- writing and reading helpers

fn put_i(w: &mut Vec<u8>, v: i64) {
    put_u64(w, v as u64);
}

fn rd_i(r: &mut Rd) -> Option<i64> {
    Some(r.u64()? as i64)
}

fn put_bool(w: &mut Vec<u8>, b: bool) {
    w.push(b as u8);
}

fn put_opt_copy(w: &mut Vec<u8>, c: Option<(u8, u8)>) {
    match c {
        Some((f, k)) => w.extend_from_slice(&[1, f, k]),
        None => w.extend_from_slice(&[0, 0, 0]),
    }
}

fn rd_opt_copy(r: &mut Rd) -> Option<Option<(u8, u8)>> {
    let (p, f, k) = (r.u8()?, r.u8()?, r.u8()?);
    Some((p != 0).then_some((f, k)))
}

impl PartyView {
    fn put(&self, w: &mut Vec<u8>) {
        put_u64(w, self.id);
        put_i(w, self.leader);
        put_opt_copy(w, self.copy);
        w.push(self.members.len() as u8);
        for m in &self.members {
            put_i(w, m.hero);
            put_str(w, &m.name);
            w.push(m.class);
            put_u16(w, m.level);
            put_bool(w, m.online);
        }
    }
    fn read(r: &mut Rd) -> Option<PartyView> {
        let (id, leader, copy) = (r.u64()?, rd_i(r)?, rd_opt_copy(r)?);
        let n = r.u8()? as usize;
        let members = (0..n)
            .map(|_| Some(PartyMember { hero: rd_i(r)?, name: read_str(r)?, class: r.u8()?, level: r.u16()?, online: r.u8()? != 0 }))
            .collect::<Option<Vec<_>>>()?;
        Some(PartyView { id, leader, members, copy })
    }
}

fn put_party(w: &mut Vec<u8>, p: &Option<PartyView>) {
    match p {
        Some(p) => {
            w.push(1);
            p.put(w);
        }
        None => w.push(0),
    }
}

fn rd_party(r: &mut Rd) -> Option<Option<PartyView>> {
    Some(if r.u8()? != 0 { Some(PartyView::read(r)?) } else { None })
}

impl GuildView {
    fn put(&self, w: &mut Vec<u8>) {
        put_u64(w, self.id);
        put_str(w, &self.name);
        put_str(w, &self.motd);
        w.push(self.my_rank);
        for p in self.perms {
            put_u16(w, p);
        }
        put_u16(w, self.members.len() as u16);
        for m in &self.members {
            put_i(w, m.account);
            put_str(w, &m.name);
            w.push(m.rank);
            put_bool(w, m.online);
        }
        put_u16(w, self.board.len() as u16);
        for p in &self.board {
            put_u64(w, p.id);
            put_str(w, &p.author);
            put_str(w, &p.text);
            put_i(w, p.at);
        }
    }
    fn read(r: &mut Rd) -> Option<GuildView> {
        let (id, name, motd, my_rank) = (r.u64()?, read_str(r)?, read_str(r)?, r.u8()?);
        let perms = [r.u16()?, r.u16()?, r.u16()?, r.u16()?];
        let n = r.u16()? as usize;
        let members = (0..n)
            .map(|_| Some(GuildMember { account: rd_i(r)?, name: read_str(r)?, rank: r.u8()?, online: r.u8()? != 0 }))
            .collect::<Option<Vec<_>>>()?;
        let n = r.u16()? as usize;
        let board = (0..n).map(|_| Some(Post { id: r.u64()?, author: read_str(r)?, text: read_str(r)?, at: rd_i(r)? })).collect::<Option<Vec<_>>>()?;
        Some(GuildView { id, name, motd, my_rank, perms, members, board })
    }
}

impl SReq {
    /// The request's tag and body. Tags run 0x40 upward in the order of the enum.
    pub fn encode(&self) -> (u8, Vec<u8>) {
        let mut w = Vec::new();
        let t = match self {
            SReq::Talk { hero, chan, to, text } => {
                put_i(&mut w, *hero);
                w.push(*chan);
                put_str(&mut w, to);
                put_str(&mut w, text);
                0x40
            }
            SReq::PartyInvite { hero, name } => {
                put_i(&mut w, *hero);
                put_str(&mut w, name);
                0x41
            }
            SReq::PartyAnswer { hero, inviter, accept } => {
                put_i(&mut w, *hero);
                put_i(&mut w, *inviter);
                put_bool(&mut w, *accept);
                0x42
            }
            SReq::PartyLeave { hero } => {
                put_i(&mut w, *hero);
                0x43
            }
            SReq::PartyKick { hero, target } => {
                put_i(&mut w, *hero);
                put_i(&mut w, *target);
                0x44
            }
            SReq::PartyLead { hero, target } => {
                put_i(&mut w, *hero);
                put_i(&mut w, *target);
                0x45
            }
            SReq::PartyGo { hero, field } => {
                put_i(&mut w, *hero);
                w.push(*field);
                0x46
            }
            SReq::PartyInfo { hero } => {
                put_i(&mut w, *hero);
                0x47
            }
            SReq::GuildCreate { hero, name } => {
                put_i(&mut w, *hero);
                put_str(&mut w, name);
                0x48
            }
            SReq::GuildInvite { hero, name } => {
                put_i(&mut w, *hero);
                put_str(&mut w, name);
                0x49
            }
            SReq::GuildAnswer { hero, guild, accept } => {
                put_i(&mut w, *hero);
                put_u64(&mut w, *guild);
                put_bool(&mut w, *accept);
                0x4A
            }
            SReq::GuildLeave { hero } => {
                put_i(&mut w, *hero);
                0x4B
            }
            SReq::GuildKick { hero, target } => {
                put_i(&mut w, *hero);
                put_i(&mut w, *target);
                0x4C
            }
            SReq::GuildRank { hero, target, rank } => {
                put_i(&mut w, *hero);
                put_i(&mut w, *target);
                w.push(*rank);
                0x4D
            }
            SReq::GuildPerms { hero, rank, perms } => {
                put_i(&mut w, *hero);
                w.push(*rank);
                put_u16(&mut w, *perms);
                0x4E
            }
            SReq::GuildMotd { hero, text } => {
                put_i(&mut w, *hero);
                put_str(&mut w, text);
                0x4F
            }
            SReq::GuildPost { hero, text } => {
                put_i(&mut w, *hero);
                put_str(&mut w, text);
                0x50
            }
            SReq::GuildUnpost { hero, post } => {
                put_i(&mut w, *hero);
                put_u64(&mut w, *post);
                0x51
            }
            SReq::GuildBank { hero, what, tab, deposit } => {
                put_i(&mut w, *hero);
                what.put(&mut w);
                put_u32(&mut w, *tab);
                put_bool(&mut w, *deposit);
                0x52
            }
            SReq::GuildBankView { hero, tab } => {
                put_i(&mut w, *hero);
                put_u32(&mut w, *tab);
                0x53
            }
            SReq::GuildInfo { hero } => {
                put_i(&mut w, *hero);
                0x54
            }
            SReq::GuildDisband { hero } => {
                put_i(&mut w, *hero);
                0x55
            }
            SReq::FriendAdd { hero, name } => {
                put_i(&mut w, *hero);
                put_str(&mut w, name);
                0x56
            }
            SReq::FriendAnswer { hero, from, accept } => {
                put_i(&mut w, *hero);
                put_i(&mut w, *from);
                put_bool(&mut w, *accept);
                0x57
            }
            SReq::FriendRemove { hero, target } => {
                put_i(&mut w, *hero);
                put_i(&mut w, *target);
                0x58
            }
            SReq::Ignore { hero, name, on } => {
                put_i(&mut w, *hero);
                put_str(&mut w, name);
                put_bool(&mut w, *on);
                0x59
            }
            SReq::Lists { hero } => {
                put_i(&mut w, *hero);
                0x5A
            }
            SReq::Report { hero, name, reason, text } => {
                put_i(&mut w, *hero);
                put_str(&mut w, name);
                w.push(*reason);
                put_str(&mut w, text);
                0x5B
            }
        };
        (t, w)
    }

    pub fn decode(t: u8, b: &[u8]) -> Option<SReq> {
        let mut r = Rd::new(b);
        let r = &mut r;
        let hero = rd_i(r)?;
        let q = match t {
            0x40 => SReq::Talk { hero, chan: r.u8()?, to: read_str(r)?, text: read_str(r)? },
            0x41 => SReq::PartyInvite { hero, name: read_str(r)? },
            0x42 => SReq::PartyAnswer { hero, inviter: rd_i(r)?, accept: r.u8()? != 0 },
            0x43 => SReq::PartyLeave { hero },
            0x44 => SReq::PartyKick { hero, target: rd_i(r)? },
            0x45 => SReq::PartyLead { hero, target: rd_i(r)? },
            0x46 => SReq::PartyGo { hero, field: r.u8()? },
            0x47 => SReq::PartyInfo { hero },
            0x48 => SReq::GuildCreate { hero, name: read_str(r)? },
            0x49 => SReq::GuildInvite { hero, name: read_str(r)? },
            0x4A => SReq::GuildAnswer { hero, guild: r.u64()?, accept: r.u8()? != 0 },
            0x4B => SReq::GuildLeave { hero },
            0x4C => SReq::GuildKick { hero, target: rd_i(r)? },
            0x4D => SReq::GuildRank { hero, target: rd_i(r)?, rank: r.u8()? },
            0x4E => SReq::GuildPerms { hero, rank: r.u8()?, perms: r.u16()? },
            0x4F => SReq::GuildMotd { hero, text: read_str(r)? },
            0x50 => SReq::GuildPost { hero, text: read_str(r)? },
            0x51 => SReq::GuildUnpost { hero, post: r.u64()? },
            0x52 => SReq::GuildBank { hero, what: Thing::read(r)?, tab: r.u32()?, deposit: r.u8()? != 0 },
            0x53 => SReq::GuildBankView { hero, tab: r.u32()? },
            0x54 => SReq::GuildInfo { hero },
            0x55 => SReq::GuildDisband { hero },
            0x56 => SReq::FriendAdd { hero, name: read_str(r)? },
            0x57 => SReq::FriendAnswer { hero, from: rd_i(r)?, accept: r.u8()? != 0 },
            0x58 => SReq::FriendRemove { hero, target: rd_i(r)? },
            0x59 => SReq::Ignore { hero, name: read_str(r)?, on: r.u8()? != 0 },
            0x5A => SReq::Lists { hero },
            0x5B => SReq::Report { hero, name: read_str(r)?, reason: r.u8()?, text: read_str(r)? },
            _ => return None,
        };
        (r.left() == 0).then_some(q)
    }
}

impl SResp {
    pub fn encode(&self) -> Vec<u8> {
        let mut w = Vec::new();
        match self {
            SResp::Party(p) => {
                w.push(0);
                put_party(&mut w, p);
            }
            SResp::Guild(g) => {
                w.push(1);
                match g {
                    Some(g) => {
                        w.push(1);
                        g.put(&mut w);
                    }
                    None => w.push(0),
                }
            }
            SResp::GuildCreated(id) => {
                w.push(2);
                put_u64(&mut w, *id);
            }
            SResp::Bank { items, stacks } => {
                w.push(3);
                put_u32(&mut w, items.len() as u32);
                for i in items {
                    i.put(&mut w);
                }
                put_u32(&mut w, stacks.len() as u32);
                for (k, n) in stacks {
                    put_u32(&mut w, *k);
                    put_u64(&mut w, *n);
                }
            }
            SResp::Lists(l) => {
                w.push(4);
                put_u16(&mut w, l.friends.len() as u16);
                for f in &l.friends {
                    put_i(&mut w, f.account);
                    put_str(&mut w, &f.name);
                    put_bool(&mut w, f.online);
                    w.push(f.place);
                }
                put_u16(&mut w, l.pending.len() as u16);
                for (a, n) in &l.pending {
                    put_i(&mut w, *a);
                    put_str(&mut w, n);
                }
                put_u16(&mut w, l.ignores.len() as u16);
                for (a, n) in &l.ignores {
                    put_i(&mut w, *a);
                    put_str(&mut w, n);
                }
            }
            SResp::Reported(id) => {
                w.push(5);
                put_u64(&mut w, *id);
            }
        }
        w
    }

    pub fn decode(b: &[u8]) -> Option<SResp> {
        let mut r = Rd::new(b);
        let r = &mut r;
        let v = match r.u8()? {
            0 => SResp::Party(rd_party(r)?),
            1 => SResp::Guild(if r.u8()? != 0 { Some(GuildView::read(r)?) } else { None }),
            2 => SResp::GuildCreated(r.u64()?),
            3 => {
                let n = r.u32()? as usize;
                let items = (0..n).map(|_| ItemInfo::read(r)).collect::<Option<Vec<_>>>()?;
                let n = r.u32()? as usize;
                let stacks = (0..n).map(|_| Some((r.u32()?, r.u64()?))).collect::<Option<Vec<_>>>()?;
                SResp::Bank { items, stacks }
            }
            4 => {
                let n = r.u16()? as usize;
                let friends = (0..n)
                    .map(|_| Some(FriendRow { account: rd_i(r)?, name: read_str(r)?, online: r.u8()? != 0, place: r.u8()? }))
                    .collect::<Option<Vec<_>>>()?;
                let n = r.u16()? as usize;
                let pending = (0..n).map(|_| Some((rd_i(r)?, read_str(r)?))).collect::<Option<Vec<_>>>()?;
                let n = r.u16()? as usize;
                let ignores = (0..n).map(|_| Some((rd_i(r)?, read_str(r)?))).collect::<Option<Vec<_>>>()?;
                SResp::Lists(Lists { friends, pending, ignores })
            }
            5 => SResp::Reported(r.u64()?),
            _ => return None,
        };
        (r.left() == 0).then_some(v)
    }
}

impl SPush {
    pub fn encode(&self) -> Vec<u8> {
        let mut w = Vec::new();
        match self {
            SPush::Chat { chan, from, to, text } => {
                w.push(0);
                w.push(*chan);
                put_str(&mut w, from);
                put_str(&mut w, to);
                put_str(&mut w, text);
            }
            SPush::PartyInvite { inviter, name } => {
                w.push(1);
                put_i(&mut w, *inviter);
                put_str(&mut w, name);
            }
            SPush::PartyUpdate(p) => {
                w.push(2);
                put_party(&mut w, p);
            }
            SPush::PartyGo { field } => {
                w.push(3);
                w.push(*field);
            }
            SPush::GuildInvite { guild, guild_name, from } => {
                w.push(4);
                put_u64(&mut w, *guild);
                put_str(&mut w, guild_name);
                put_str(&mut w, from);
            }
            SPush::GuildChanged => w.push(5),
            SPush::FriendRequest { from, name } => {
                w.push(6);
                put_i(&mut w, *from);
                put_str(&mut w, name);
            }
            SPush::FriendStatus { account, name, online, place } => {
                w.push(7);
                put_i(&mut w, *account);
                put_str(&mut w, name);
                put_bool(&mut w, *online);
                w.push(*place);
            }
            SPush::Notice { text } => {
                w.push(8);
                put_str(&mut w, text);
            }
        }
        w
    }

    pub fn decode(b: &[u8]) -> Option<SPush> {
        let mut r = Rd::new(b);
        let r = &mut r;
        let v = match r.u8()? {
            0 => SPush::Chat { chan: r.u8()?, from: read_str(r)?, to: read_str(r)?, text: read_str(r)? },
            1 => SPush::PartyInvite { inviter: rd_i(r)?, name: read_str(r)? },
            2 => SPush::PartyUpdate(rd_party(r)?),
            3 => SPush::PartyGo { field: r.u8()? },
            4 => SPush::GuildInvite { guild: r.u64()?, guild_name: read_str(r)?, from: read_str(r)? },
            5 => SPush::GuildChanged,
            6 => SPush::FriendRequest { from: rd_i(r)?, name: read_str(r)? },
            7 => SPush::FriendStatus { account: rd_i(r)?, name: read_str(r)?, online: r.u8()? != 0, place: r.u8()? },
            8 => SPush::Notice { text: read_str(r)? },
            _ => return None,
        };
        (r.left() == 0).then_some(v)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_social_request_survives_the_wire() {
        let reqs = vec![
            SReq::Talk { hero: 1, chan: chan::WHISPER, to: "Bob".into(), text: "hi".into() },
            SReq::PartyInvite { hero: 1, name: "Bob".into() },
            SReq::PartyAnswer { hero: 1, inviter: 2, accept: true },
            SReq::PartyLeave { hero: 1 },
            SReq::PartyKick { hero: 1, target: 2 },
            SReq::PartyLead { hero: 1, target: 2 },
            SReq::PartyGo { hero: 1, field: 3 },
            SReq::PartyInfo { hero: 1 },
            SReq::GuildCreate { hero: 1, name: "The Pale".into() },
            SReq::GuildInvite { hero: 1, name: "Bob".into() },
            SReq::GuildAnswer { hero: 1, guild: 9, accept: false },
            SReq::GuildLeave { hero: 1 },
            SReq::GuildKick { hero: 1, target: 5 },
            SReq::GuildRank { hero: 1, target: 5, rank: 1 },
            SReq::GuildPerms { hero: 1, rank: 2, perms: 0x1F },
            SReq::GuildMotd { hero: 1, text: "m".into() },
            SReq::GuildPost { hero: 1, text: "p".into() },
            SReq::GuildUnpost { hero: 1, post: 4 },
            SReq::GuildBank { hero: 1, what: Thing::Item(7), tab: 2, deposit: true },
            SReq::GuildBank { hero: 1, what: Thing::Stack(1, 50), tab: 0, deposit: false },
            SReq::GuildBankView { hero: 1, tab: 3 },
            SReq::GuildInfo { hero: 1 },
            SReq::GuildDisband { hero: 1 },
            SReq::FriendAdd { hero: 1, name: "Bob".into() },
            SReq::FriendAnswer { hero: 1, from: 2, accept: true },
            SReq::FriendRemove { hero: 1, target: 2 },
            SReq::Ignore { hero: 1, name: "Bob".into(), on: true },
            SReq::Lists { hero: 1 },
            SReq::Report { hero: 1, name: "Bob".into(), reason: 2, text: "gold".into() },
        ];
        for q in reqs {
            let (t, b) = q.encode();
            assert!((T_SOC_FIRST..=T_SOC_LAST).contains(&t));
            assert_eq!(SReq::decode(t, &b), Some(q.clone()), "{q:?}");
            assert_eq!(SReq::decode(t, &b[..b.len() - 1]), None, "a short {q:?} is refused");
        }
    }

    #[test]
    fn every_social_reply_and_push_survives_the_wire() {
        let party = PartyView { id: 3, leader: 1, copy: Some((2, 1)), members: vec![PartyMember { hero: 1, name: "Ann".into(), class: 2, level: 7, online: true }] };
        let guild = GuildView {
            id: 4,
            name: "G".into(),
            motd: "m".into(),
            my_rank: 1,
            perms: [255, 100, 12, 4],
            members: vec![GuildMember { account: 5, name: "Ann".into(), rank: 0, online: false }],
            board: vec![Post { id: 1, author: "Ann".into(), text: "t".into(), at: 99 }],
        };
        let resps = vec![
            SResp::Party(Some(party.clone())),
            SResp::Party(None),
            SResp::Guild(Some(guild)),
            SResp::Guild(None),
            SResp::GuildCreated(4),
            SResp::Bank { items: vec![], stacks: vec![(1, 20)] },
            SResp::Lists(Lists { friends: vec![FriendRow { account: 2, name: "B".into(), online: true, place: 1 }], pending: vec![(3, "C".into())], ignores: vec![(4, "D".into())] }),
            SResp::Reported(12),
        ];
        for s in resps {
            assert_eq!(SResp::decode(&s.encode()), Some(s.clone()), "{s:?}");
        }
        let pushes = vec![
            SPush::Chat { chan: chan::GUILD, from: "A".into(), to: String::new(), text: "x".into() },
            SPush::PartyInvite { inviter: 2, name: "A".into() },
            SPush::PartyUpdate(Some(party)),
            SPush::PartyGo { field: 1 },
            SPush::GuildInvite { guild: 2, guild_name: "G".into(), from: "A".into() },
            SPush::GuildChanged,
            SPush::FriendRequest { from: 2, name: "A".into() },
            SPush::FriendStatus { account: 2, name: "A".into(), online: false, place: 0 },
            SPush::Notice { text: "muted".into() },
        ];
        for p in pushes {
            assert_eq!(SPush::decode(&p.encode()), Some(p.clone()), "{p:?}");
        }
    }
}
