//! Guilds of up to `GUILD_MAX` accounts: four ranks (0 leader, 1 officer, 2 member, 3 recruit), a permission word per
//! rank, a message of the day, a board, guild chat and a bank.
//!
//! The bank is the store's GUILD place (8 tabs of 100 slots) and its stacks; the store lets only the server move value
//! there, so every move goes through `guild_bank` after the gateway has checked the member's rank. A deposit or
//! withdrawal is one `MoveItem` or `StackTransfer`: the item row is moved, never copied, and the ledger records
//! who. Between the permission check and the store call the guild lock is let go (the store call fsyncs); a member
//! kicked in that instant may finish one move. The leader's guild cannot be disbanded or left empty-handed while
//! its bank holds anything, so nothing is orphaned.

use super::*;
use crate::proto::Thing;
use realm_store::{Cmd, Dest, Owner, PlaceKind, StackKind, Store};

/// Permission bits of a rank.
pub mod perm {
    pub const INVITE: u16 = 1;
    pub const KICK: u16 = 2;
    pub const DEPOSIT: u16 = 4;
    pub const WITHDRAW: u16 = 8;
    pub const POST: u16 = 16;
    pub const MOTD: u16 = 32;
    /// Withdraw coin (as well as `WITHDRAW`).
    pub const COIN: u16 = 64;
    /// Promote and demote ranks below her own.
    pub const RANKS: u16 = 128;
    pub const ALL: u16 = 255;
}

/// Leader and officers may everything the rules allow them; members deposit and post; recruits only deposit.
pub const DEFAULT_PERMS: [u16; 4] = [perm::ALL, perm::ALL, perm::DEPOSIT | perm::POST, perm::DEPOSIT];
pub const BOARD_MAX: usize = 50;
pub const POST_MAX: usize = 300;
pub const MOTD_MAX: usize = 200;
pub const NAME_MIN: usize = 3;
pub const NAME_MAX: usize = 20;
pub const BANK_TABS: u32 = realm_store::limits::GUILD_TABS;

/// A guild name: 3 to 20 characters, letters, digits, spaces, `'` and `-`, first a letter, no doubled space.
pub fn valid_guild_name(n: &str) -> bool {
    let c: Vec<char> = n.chars().collect();
    (NAME_MIN..=NAME_MAX).contains(&c.len())
        && c[0].is_alphabetic()
        && c.iter().all(|x| x.is_alphanumeric() || *x == ' ' || *x == '\'' || *x == '-')
        && !n.contains("  ")
        && !n.ends_with(' ')
}

/// A rank's bits for a guild member (the leader has them all, always).
fn bits(g: &Guild, rank: u8) -> u16 {
    if rank == 0 {
        perm::ALL
    } else {
        g.perms[rank as usize & 3]
    }
}

impl Inner {
    fn guild_of_me(&self, me: &Me) -> R<(&Guild, u8)> {
        let id = self.guild_of.get(&me.account).ok_or_else(|| bad("you are in no guild"))?;
        let g = &self.guilds[id];
        Ok((g, g.members[&me.account].rank))
    }

    fn guild_may(&self, me: &Me, p: u16) -> R<(&Guild, u8)> {
        let (g, rank) = self.guild_of_me(me)?;
        if bits(g, rank) & p != p {
            return Err(fail(code::REFUSED, "your rank may not"));
        }
        Ok((g, rank))
    }

    fn guild_changed(&self, id: u64) {
        if let Some(g) = self.guilds.get(&id) {
            for a in g.members.keys() {
                self.send_account(*a, &SPush::GuildChanged);
            }
        }
    }

    fn guild_view(&self, me: i64, id: u64) -> GuildView {
        let g = &self.guilds[&id];
        let mut members: Vec<GuildMember> =
            g.members.iter().map(|(a, m)| GuildMember { account: *a, name: self.name_of(*a), rank: m.rank, online: self.is_online(*a) }).collect();
        members.sort_by(|a, b| (a.rank, a.name.to_lowercase()).cmp(&(b.rank, b.name.to_lowercase())));
        GuildView {
            id,
            name: g.name.clone(),
            motd: g.motd.clone(),
            my_rank: g.members[&me].rank,
            perms: g.perms,
            members,
            board: g.board.iter().cloned().collect(),
        }
    }
}

impl Social {
    pub(super) fn guild_create(&self, me: &Me, name: &str, now: i64) -> R {
        let name = name.trim().to_string();
        if !valid_guild_name(&name) {
            return Err(fail(code::BAD_NAME, "a guild name is 3 to 20 letters, digits, spaces, ' and -"));
        }
        let text = self.gate_name(&name)?;
        let mut g = self.inner.lock().unwrap();
        if g.guild_of.contains_key(&me.account) {
            return Err(fail(code::BUSY, "you are in a guild"));
        }
        if g.guilds.values().any(|x| x.name.eq_ignore_ascii_case(&text)) {
            return Err(fail(code::NAME_TAKEN, "that guild name is taken"));
        }
        let id = g.next_guild;
        g.commit("gnew", &[&id.to_string(), &text, &me.account.to_string(), &now.to_string()]);
        Ok(Resp::Social(SResp::GuildCreated(id)))
    }

    /// A guild name goes through the word filter too (a masked name is refused, not changed).
    fn gate_name(&self, name: &str) -> R<String> {
        match (self.filter.read().unwrap())(name) {
            Verdict::Pass(t) if t == name => Ok(t),
            _ => Err(fail(code::BAD_NAME, "that name is not allowed")),
        }
    }

    pub(super) fn guild_invite(&self, gw: &Gateway, me: &Me, name: &str, now: i64) -> R {
        let t = self.hero_named(gw, name)?;
        let mut g = self.inner.lock().unwrap();
        let (gu, _) = g.guild_may(me, perm::INVITE)?;
        let (gid, gname, size) = (gu.id, gu.name.clone(), gu.members.len());
        if size >= GUILD_MAX {
            return Err(fail(code::FULL, "the guild is full"));
        }
        if g.guild_of.contains_key(&t.account) {
            return Err(fail(code::BUSY, "she is in a guild"));
        }
        if !g.is_online(t.account) {
            return Err(fail(code::MISSING, "she is not here"));
        }
        g.guild_invites.retain(|_, (_, e)| *e > now);
        if !g.ignores(t.account, me.account) {
            g.guild_invites.insert((t.account, gid), (me.name.clone(), now + GUILD_INVITE_TTL_MS));
            g.send_account(t.account, &SPush::GuildInvite { guild: gid, guild_name: gname, from: me.name.clone() });
        }
        Ok(Resp::Ok)
    }

    pub(super) fn guild_answer(&self, me: &Me, guild: u64, accept: bool, now: i64) -> R {
        let mut g = self.inner.lock().unwrap();
        let Some((_, exp)) = g.guild_invites.remove(&(me.account, guild)) else {
            return Err(fail(code::MISSING, "no such invitation"));
        };
        if !accept {
            return Ok(Resp::Ok);
        }
        if exp <= now {
            return Err(fail(code::MISSING, "that invitation ran out"));
        }
        if g.guild_of.contains_key(&me.account) {
            return Err(fail(code::BUSY, "you are in a guild"));
        }
        let Some(gu) = g.guilds.get(&guild) else { return Err(fail(code::MISSING, "that guild is gone")) };
        if gu.members.len() >= GUILD_MAX {
            return Err(fail(code::FULL, "the guild is full"));
        }
        g.commit("gjoin", &[&guild.to_string(), &me.account.to_string(), "3", &now.to_string()]);
        g.guild_changed(guild);
        let v = g.guild_view(me.account, guild);
        Ok(Resp::Social(SResp::Guild(Some(v))))
    }

    /// Is the guild's bank empty (no item in any tab, no stack)?
    fn bank_empty(gw: &Gateway, id: u64) -> R<bool> {
        let items = gw.store.items_at(PlaceKind::Guild, id as i64).map_err(store_err)?;
        let stacks = gw.store.stacks(Owner { kind: PlaceKind::Guild, id: id as i64 }).map_err(store_err)?;
        Ok(items.is_empty() && stacks.iter().all(|(_, n)| *n == 0))
    }

    pub(super) fn guild_leave(&self, gw: &Gateway, me: &Me) -> R {
        let (id, rank, size) = {
            let g = self.inner.lock().unwrap();
            let (gu, rank) = g.guild_of_me(me)?;
            (gu.id, rank, gu.members.len())
        };
        if rank == 0 {
            if size > 1 {
                return Err(fail(code::REFUSED, "hand the guild to another first"));
            }
            return self.guild_disband(gw, me);
        }
        let mut g = self.inner.lock().unwrap();
        g.commit("gleave", &[&id.to_string(), &me.account.to_string()]);
        g.guild_changed(id);
        g.send_account(me.account, &SPush::GuildChanged);
        Ok(Resp::Ok)
    }

    pub(super) fn guild_disband(&self, gw: &Gateway, me: &Me) -> R {
        let id = {
            let g = self.inner.lock().unwrap();
            let (gu, rank) = g.guild_of_me(me)?;
            if rank != 0 {
                return Err(fail(code::REFUSED, "only the leader disbands"));
            }
            gu.id
        };
        if !Self::bank_empty(gw, id)? {
            return Err(fail(code::INVALID, "empty the guild bank first"));
        }
        let mut g = self.inner.lock().unwrap();
        if !g.guilds.contains_key(&id) {
            return Ok(Resp::Ok);
        }
        let members: Vec<i64> = g.guilds[&id].members.keys().copied().collect();
        g.commit("gdisband", &[&id.to_string()]);
        for a in members {
            g.send_account(a, &SPush::GuildChanged);
        }
        Ok(Resp::Ok)
    }

    pub(super) fn guild_kick(&self, me: &Me, target: i64) -> R {
        let mut g = self.inner.lock().unwrap();
        let (gu, rank) = g.guild_may(me, perm::KICK)?;
        let trank = gu.members.get(&target).ok_or_else(|| fail(code::MISSING, "not a member"))?.rank;
        if target == me.account || rank >= trank {
            return Err(fail(code::REFUSED, "you may only remove those below you"));
        }
        let id = gu.id;
        g.commit("gleave", &[&id.to_string(), &target.to_string()]);
        g.send_account(target, &SPush::Notice { text: "You were removed from the guild.".into() });
        g.send_account(target, &SPush::GuildChanged);
        g.guild_changed(id);
        Ok(Resp::Ok)
    }

    pub(super) fn guild_rank(&self, me: &Me, target: i64, new: u8) -> R {
        if new > 3 {
            return Err(bad("ranks are 0 to 3"));
        }
        let mut g = self.inner.lock().unwrap();
        let (gu, rank) = g.guild_may(me, perm::RANKS)?;
        let trank = gu.members.get(&target).ok_or_else(|| fail(code::MISSING, "not a member"))?.rank;
        if target == me.account {
            return Err(bad("not yourself"));
        }
        let id = gu.id;
        if new == 0 {
            // Handing over: only the leader, and she steps down to officer.
            if rank != 0 {
                return Err(fail(code::REFUSED, "only the leader hands over"));
            }
            g.commit("grank", &[&id.to_string(), &target.to_string(), "0"]);
            g.commit("grank", &[&id.to_string(), &me.account.to_string(), "1"]);
        } else {
            if rank >= trank || rank >= new {
                return Err(fail(code::REFUSED, "you may only rank those below you, to ranks below you"));
            }
            g.commit("grank", &[&id.to_string(), &target.to_string(), &new.to_string()]);
        }
        g.guild_changed(id);
        Ok(Resp::Ok)
    }

    pub(super) fn guild_perms(&self, me: &Me, rank: u8, perms: u16) -> R {
        if !(1..=3).contains(&rank) || perms & !perm::ALL != 0 {
            return Err(bad("rank 1 to 3, permission bits within 255"));
        }
        let mut g = self.inner.lock().unwrap();
        let (gu, r) = g.guild_of_me(me)?;
        if r != 0 {
            return Err(fail(code::REFUSED, "only the leader sets permissions"));
        }
        let id = gu.id;
        g.commit("gperms", &[&id.to_string(), &rank.to_string(), &perms.to_string()]);
        g.guild_changed(id);
        Ok(Resp::Ok)
    }

    pub(super) fn guild_motd(&self, me: &Me, text: &str, now: i64) -> R {
        {
            let g = self.inner.lock().unwrap();
            g.guild_may(me, perm::MOTD)?;
        }
        let text = self.guild_text(me, text, MOTD_MAX, now, true)?;
        let mut g = self.inner.lock().unwrap();
        let (gu, _) = g.guild_may(me, perm::MOTD)?;
        let id = gu.id;
        g.commit("gmotd", &[&id.to_string(), &text]);
        g.guild_changed(id);
        Ok(Resp::Ok)
    }

    /// Text a member puts in a guild's place (motd, board): not when muted, cleaned, filtered, within `max`. The motd may be
    /// empty (clearing it).
    fn guild_text(&self, me: &Me, text: &str, max: usize, now: i64, may_be_empty: bool) -> R<String> {
        let t: String = crate::town::clean_chat(text).chars().take(max).collect();
        if t.is_empty() {
            return if may_be_empty { Ok(t) } else { Err(bad("empty text")) };
        }
        if let Some(until) = self.inner.lock().unwrap().muted_until(me.account, now) {
            return Err(Refuse::Muted { until }.resp());
        }
        match (self.filter.read().unwrap())(&t) {
            Verdict::Pass(t) => Ok(t),
            Verdict::Block => Err(Refuse::Filtered.resp()),
        }
    }

    pub(super) fn guild_post(&self, me: &Me, text: &str, now: i64) -> R {
        {
            let g = self.inner.lock().unwrap();
            g.guild_may(me, perm::POST)?;
        }
        let text = self.guild_text(me, text, POST_MAX, now, false)?;
        // A board is chat in a slow place: it shares the guild channel's bucket.
        match self.inner.lock().unwrap().limiter.take(me.account, wire::chan::GUILD, now) {
            filter::Limit::Ok => {}
            _ => return Err(Refuse::Slow.resp()),
        }
        let mut g = self.inner.lock().unwrap();
        let (gu, _) = g.guild_may(me, perm::POST)?;
        let id = gu.id;
        let pid = g.next_post;
        g.commit("gpost", &[&id.to_string(), &pid.to_string(), &me.name, &text, &now.to_string()]);
        g.guild_changed(id);
        Ok(Resp::Ok)
    }

    pub(super) fn guild_unpost(&self, me: &Me, post: u64) -> R {
        let mut g = self.inner.lock().unwrap();
        let (gu, rank) = g.guild_of_me(me)?;
        let p = gu.board.iter().find(|p| p.id == post).ok_or_else(|| fail(code::MISSING, "no such post"))?;
        let own = p.author == me.name;
        if !own && bits(gu, rank) & perm::KICK == 0 {
            return Err(fail(code::REFUSED, "your rank may not"));
        }
        let id = gu.id;
        g.commit("gunpost", &[&id.to_string(), &post.to_string()]);
        g.guild_changed(id);
        Ok(Resp::Ok)
    }

    pub(super) fn guild_info(&self, me: &Me) -> R {
        let g = self.inner.lock().unwrap();
        Ok(Resp::Social(SResp::Guild(g.guild_of.get(&me.account).map(|id| g.guild_view(me.account, *id)))))
    }

    pub(super) fn guild_bank_view(&self, gw: &Gateway, me: &Me, tab: u32) -> R {
        let id = {
            let g = self.inner.lock().unwrap();
            g.guild_of_me(me)?.0.id
        };
        if tab >= BANK_TABS {
            return Err(bad("no such tab"));
        }
        let items = gw.store.items_at(PlaceKind::Guild, id as i64).map_err(store_err)?;
        let items = items.iter().filter(|i| i.place.tab == tab).map(crate::gateway::item_info).collect();
        let stacks = gw.store.stacks(Owner { kind: PlaceKind::Guild, id: id as i64 }).map_err(store_err)?;
        Ok(Resp::Social(SResp::Bank { items, stacks: stacks.into_iter().map(|(k, n)| (k.0, n)).collect() }))
    }

    /// A deposit (her bag to the guild's tab) or withdrawal (the guild's bank to her bag). The store moves the one
    /// row or the count; there is no copy and nothing in between.
    pub(super) fn guild_bank(&self, gw: &Gateway, me: &Me, what: Thing, tab: u32, deposit: bool) -> R {
        if tab >= BANK_TABS {
            return Err(bad("no such tab"));
        }
        let coin = matches!(what, Thing::Stack(k, _) if k == StackKind::COIN.0);
        let need = match (deposit, coin) {
            (true, _) => perm::DEPOSIT,
            (false, true) => perm::WITHDRAW | perm::COIN,
            (false, false) => perm::WITHDRAW,
        };
        let gid = {
            let g = self.inner.lock().unwrap();
            g.guild_may(me, need)?.0.id as i64
        };
        let cmd = match what {
            Thing::Item(item) => {
                let it = gw.store.item(item).map_err(store_err)?.ok_or_else(|| fail(code::MISSING, "no such item"))?;
                if deposit {
                    if it.place.kind != PlaceKind::Bag || it.place.owner != me.hero {
                        return Err(fail(code::NOT_YOURS, "that item is not in her bag"));
                    }
                    Cmd::MoveItem { item, to: Dest { kind: PlaceKind::Guild, owner: gid, tab, slot: None } }
                } else {
                    if it.place.kind != PlaceKind::Guild || it.place.owner != gid {
                        return Err(fail(code::NOT_YOURS, "that item is not in the guild bank"));
                    }
                    Cmd::MoveItem { item, to: Dest::bag(me.hero) }
                }
            }
            Thing::Stack(kind, count) => {
                let guild = Owner { kind: PlaceKind::Guild, id: gid };
                let (from, to) = if deposit { (Owner::bag(me.hero), guild) } else { (guild, Owner::bag(me.hero)) };
                Cmd::StackTransfer { from, to, kind: StackKind(kind), count }
            }
        };
        // The guild's bank belongs to no player, so the server acts, after the checks above.
        gw.store.run(self.meta(0), cmd).map_err(store_err)?;
        Ok(Resp::Ok)
    }
}

/// A guild as tests and tools read it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GuildSnap {
    pub name: String,
    pub motd: String,
    /// (account, rank).
    pub members: Vec<(i64, u8)>,
    pub board: Vec<String>,
    pub perms: [u16; 4],
}

impl Social {
    pub fn guild_snapshot(&self, id: u64) -> Option<GuildSnap> {
        let g = self.inner.lock().unwrap();
        let gu = g.guilds.get(&id)?;
        Some(GuildSnap {
            name: gu.name.clone(),
            motd: gu.motd.clone(),
            members: gu.members.iter().map(|(a, m)| (*a, m.rank)).collect(),
            board: gu.board.iter().map(|p| p.text.clone()).collect(),
            perms: gu.perms,
        })
    }

    /// (friends, ignores) of an account.
    pub fn lists_snapshot(&self, account: i64) -> (Vec<i64>, Vec<i64>) {
        let g = self.inner.lock().unwrap();
        (g.friends.get(&account).into_iter().flatten().copied().collect(), g.ignores.get(&account).into_iter().flatten().copied().collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn guild_names() {
        assert!(valid_guild_name("The Pale Court"));
        assert!(valid_guild_name("Ash-born"));
        assert!(!valid_guild_name("ab"));
        assert!(!valid_guild_name("1st Guild"));
        assert!(!valid_guild_name("Two  Spaces"));
        assert!(!valid_guild_name("Tab\tname"));
        assert!(!valid_guild_name(&"x".repeat(21)));
    }
}
