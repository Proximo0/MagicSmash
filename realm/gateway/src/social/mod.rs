//! Living together (job T1): parties, guilds, friends and ignores, chat channels with limits and a word filter, mute,
//! report and the moderators' tools. `docs/realm/social.md` has every number and why.
//!
//! The gateway owns one `Social`. A hero is *present* from the moment she enters a town (or asks for a field ticket)
//! until her connection ends: presence is how a line finds its listeners. Everything lives behind one mutex; the
//! only calls out of it are pushes onto connection channels (never blocking) and, for the guild bank, store calls
//! made after the lock is let go.

pub mod admin;
mod filter;
mod guild;
mod lists;
mod log;
mod modtools;
mod party;
pub mod wire;
/// Its messages on the gateway wire and its dispatch (`proto::WireModule`).
pub mod gate;

pub use filter::{default_filter, Filter, Verdict};
pub use guild::{perm, GuildSnap};
pub use wire::*;

use crate::gateway::{now_ms, Gateway, Session};
use crate::proto::{code, resp_frame, Resp};
use realm_store::{Hero, Store};
use std::collections::{BTreeMap, BTreeSet, HashMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::Sender;
use std::sync::{Mutex, RwLock};

/// A party holds at most this many heroes.
pub const PARTY_MAX: usize = 8;
/// A guild holds at most this many accounts.
pub const GUILD_MAX: usize = 100;
/// Friends and ignores an account may keep.
pub const LIST_MAX: usize = 100;
/// An invitation (party, guild) lives this long; a friend request a day.
pub const INVITE_TTL_MS: i64 = 60_000;
pub const GUILD_INVITE_TTL_MS: i64 = 5 * 60_000;
pub const FRIEND_REQ_TTL_MS: i64 = 24 * 3600_000;
/// The party's shared copy is remembered this long after the last ticket that used it.
pub const PARTY_COPY_TTL_MS: i64 = 10 * 60_000;
/// Lines of recent chat kept for report evidence, and lines of one account shown in a report.
pub const RECENT_MAX: usize = 4096;
pub const EVIDENCE_LINES: usize = 10;
/// Where a present hero is.
pub const PLACE_TOWN: u8 = 1;
pub const PLACE_FIELD: u8 = 2;
/// Moderator log lines kept in memory (the file keeps all).
pub const ADMIN_LOG_KEEP: usize = 5000;

pub(crate) type R<T = Resp> = Result<T, Resp>;

pub(crate) fn fail(code: u16, msg: &str) -> Resp {
    Resp::Err { code, msg: msg.into() }
}

pub(crate) fn bad(msg: &str) -> Resp {
    fail(code::BAD_REQUEST, msg)
}

pub(crate) fn store_err(e: realm_store::Error) -> Resp {
    crate::gateway::err(e)
}

/// Why a line was not sent.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Refuse {
    Empty,
    Muted { until: i64 },
    Slow,
    /// The flood limit was hit: she is silenced for a while.
    Flood,
    Filtered,
}

impl Refuse {
    pub fn resp(&self) -> Resp {
        match self {
            Refuse::Empty => bad("empty line"),
            Refuse::Muted { .. } => fail(code::MUTED, "you are silenced"),
            Refuse::Slow => fail(code::SLOW_DOWN, "slow down"),
            Refuse::Flood => fail(code::MUTED, "silenced for flooding"),
            Refuse::Filtered => fail(code::REFUSED, "that line is not allowed"),
        }
    }
}

pub struct Presence {
    pub hero: i64,
    pub account: i64,
    pub name: String,
    pub class: u8,
    pub level: u16,
    pub conn: u64,
    pub out: Sender<Vec<u8>>,
    pub place: u8,
}

pub struct Mute {
    pub until: i64,
    pub reason: String,
}

pub struct GuildMem {
    pub rank: u8,
    pub joined: i64,
}

pub struct Guild {
    pub id: u64,
    pub name: String,
    pub motd: String,
    pub members: BTreeMap<i64, GuildMem>,
    pub perms: [u16; 4],
    pub board: VecDeque<Post>,
}

pub struct Party {
    pub id: u64,
    pub leader: i64,
    pub members: Vec<i64>,
    pub copy: Option<(u8, u8, i64)>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Report {
    pub id: u64,
    pub at: i64,
    pub reporter: i64,
    pub target: i64,
    pub reason: u8,
    pub text: String,
    pub evidence: Vec<String>,
    /// Who closed it (a moderator's name), if closed.
    pub done: Option<String>,
}

pub struct ChatLine {
    pub at: i64,
    pub account: i64,
    pub chan: u8,
    pub text: String,
}

#[derive(Default)]
pub(crate) struct Inner {
    pub online: HashMap<i64, Presence>,
    pub by_account: HashMap<i64, Vec<i64>>,
    pub names: HashMap<i64, String>,
    pub parties: HashMap<u64, Party>,
    pub party_of: HashMap<i64, u64>,
    pub next_party: u64,
    /// (invitee hero, inviter hero) -> expires.
    pub party_invites: HashMap<(i64, i64), i64>,
    pub guilds: BTreeMap<u64, Guild>,
    pub guild_of: HashMap<i64, u64>,
    pub next_guild: u64,
    pub next_post: u64,
    /// (invitee account, guild) -> (inviter name, expires).
    pub guild_invites: HashMap<(i64, u64), (String, i64)>,
    pub friends: HashMap<i64, BTreeSet<i64>>,
    pub ignores: HashMap<i64, BTreeSet<i64>>,
    /// (to, from) -> expires.
    pub friend_reqs: HashMap<(i64, i64), i64>,
    pub mutes: HashMap<i64, Mute>,
    pub reports: Vec<Report>,
    pub last_report: HashMap<i64, i64>,
    pub admin_log: VecDeque<(i64, String, String)>,
    pub limiter: filter::Limiter,
    pub recent: VecDeque<ChatLine>,
    pub log: Option<log::LogFile>,
    pub replaying: bool,
}

pub struct Social {
    pub(crate) inner: Mutex<Inner>,
    filter: RwLock<Filter>,
    boot: u64,
    n: AtomicU64,
}

impl Default for Social {
    fn default() -> Social {
        use std::hash::{BuildHasher, Hasher};
        let boot = std::collections::hash_map::RandomState::new().build_hasher().finish();
        let inner = Inner { next_party: 1, next_guild: 1, next_post: 1, ..Inner::default() };
        Social { inner: Mutex::new(inner), filter: RwLock::new(default_filter(filter::DEFAULT_WORDS.iter().map(|s| s.to_string()).collect())), boot, n: AtomicU64::new(1) }
    }
}

pub(crate) fn push_frame(p: SPush) -> Vec<u8> {
    resp_frame(0, &Resp::SocialPush(p))
}

impl Inner {
    pub fn send(&self, hero: i64, p: SPush) {
        if let Some(pr) = self.online.get(&hero) {
            let _ = pr.out.send(push_frame(p));
        }
    }

    /// To every connection of the account (once each).
    pub fn send_account(&self, account: i64, p: &SPush) {
        let f = push_frame(p.clone());
        let mut seen = Vec::new();
        for h in self.by_account.get(&account).into_iter().flatten() {
            if let Some(pr) = self.online.get(h) {
                if !seen.contains(&pr.conn) {
                    seen.push(pr.conn);
                    let _ = pr.out.send(f.clone());
                }
            }
        }
    }

    pub fn is_online(&self, account: i64) -> bool {
        self.by_account.get(&account).is_some_and(|v| !v.is_empty())
    }

    /// 0 offline, 1 town, 2 field.
    pub fn place_of(&self, account: i64) -> u8 {
        self.by_account.get(&account).into_iter().flatten().filter_map(|h| self.online.get(h)).map(|p| p.place).max().unwrap_or(0)
    }

    pub fn name_of(&self, account: i64) -> String {
        self.names.get(&account).cloned().unwrap_or_else(|| format!("#{account}"))
    }

    pub fn ignores(&self, listener: i64, speaker: i64) -> bool {
        self.ignores.get(&listener).is_some_and(|s| s.contains(&speaker))
    }

    pub fn muted_until(&self, account: i64, now: i64) -> Option<i64> {
        self.mutes.get(&account).filter(|m| m.until > now).map(|m| m.until)
    }

    /// Applies a record to the state; with a log open it is written too (unless replaying).
    pub fn commit(&mut self, kind: &str, f: &[&str]) {
        let owned: Vec<String> = f.iter().map(|s| s.to_string()).collect();
        self.apply(kind, &owned);
        if !self.replaying {
            if let Some(l) = self.log.as_mut() {
                l.write(&log::line(kind, f));
            }
        }
    }

    fn apply(&mut self, kind: &str, f: &[String]) {
        let n = |i: usize| f.get(i).and_then(|s| s.parse::<i64>().ok()).unwrap_or(0);
        let s = |i: usize| f.get(i).cloned().unwrap_or_default();
        match kind {
            "name" => {
                self.names.insert(n(0), s(1));
            }
            "gnew" => {
                let id = n(0) as u64;
                let mut g = Guild { id, name: s(1), motd: String::new(), members: BTreeMap::new(), perms: guild::DEFAULT_PERMS, board: VecDeque::new() };
                g.members.insert(n(2), GuildMem { rank: 0, joined: n(3) });
                self.guild_of.insert(n(2), id);
                self.guilds.insert(id, g);
                self.next_guild = self.next_guild.max(id + 1);
            }
            "gjoin" => {
                if let Some(g) = self.guilds.get_mut(&(n(0) as u64)) {
                    g.members.insert(n(1), GuildMem { rank: n(2).clamp(0, 3) as u8, joined: n(3) });
                    self.guild_of.insert(n(1), g.id);
                }
            }
            "gleave" => {
                if let Some(g) = self.guilds.get_mut(&(n(0) as u64)) {
                    g.members.remove(&n(1));
                }
                if self.guild_of.get(&n(1)) == Some(&(n(0) as u64)) {
                    self.guild_of.remove(&n(1));
                }
            }
            "grank" => {
                if let Some(m) = self.guilds.get_mut(&(n(0) as u64)).and_then(|g| g.members.get_mut(&n(1))) {
                    m.rank = n(2).clamp(0, 3) as u8;
                }
            }
            "gperms" => {
                if let Some(g) = self.guilds.get_mut(&(n(0) as u64)) {
                    if let Some(p) = g.perms.get_mut(n(1).clamp(0, 3) as usize) {
                        *p = n(2) as u16;
                    }
                }
            }
            "gmotd" => {
                if let Some(g) = self.guilds.get_mut(&(n(0) as u64)) {
                    g.motd = s(1);
                }
            }
            "gpost" => {
                if let Some(g) = self.guilds.get_mut(&(n(0) as u64)) {
                    g.board.push_back(Post { id: n(1) as u64, author: s(2), text: s(3), at: n(4) });
                    while g.board.len() > guild::BOARD_MAX {
                        g.board.pop_front();
                    }
                }
                self.next_post = self.next_post.max(n(1) as u64 + 1);
            }
            "gunpost" => {
                if let Some(g) = self.guilds.get_mut(&(n(0) as u64)) {
                    g.board.retain(|p| p.id != n(1) as u64);
                }
            }
            "gdisband" => {
                if let Some(g) = self.guilds.remove(&(n(0) as u64)) {
                    for a in g.members.keys() {
                        self.guild_of.remove(a);
                    }
                }
            }
            "friend" => {
                let (a, b, on) = (n(0), n(1), n(2) != 0);
                for (x, y) in [(a, b), (b, a)] {
                    let set = self.friends.entry(x).or_default();
                    if on {
                        set.insert(y);
                    } else {
                        set.remove(&y);
                    }
                }
            }
            "ignore" => {
                let set = self.ignores.entry(n(0)).or_default();
                if n(2) != 0 {
                    set.insert(n(1));
                } else {
                    set.remove(&n(1));
                }
            }
            "mute" => {
                if n(1) <= 0 {
                    self.mutes.remove(&n(0));
                } else {
                    self.mutes.insert(n(0), Mute { until: n(1), reason: s(2) });
                }
            }
            "report" => {
                let evidence = s(6).split('\u{1f}').filter(|x| !x.is_empty()).map(|x| x.to_string()).collect();
                self.reports.push(Report { id: n(0) as u64, at: n(1), reporter: n(2), target: n(3), reason: n(4) as u8, text: s(5), evidence, done: None });
            }
            "rdone" => {
                if let Some(r) = self.reports.iter_mut().find(|r| r.id == n(0) as u64) {
                    r.done = Some(s(1));
                }
            }
            "admin" => {
                self.admin_log.push_back((n(0), s(1), s(2)));
                while self.admin_log.len() > ADMIN_LOG_KEEP {
                    self.admin_log.pop_front();
                }
            }
            _ => {}
        }
    }
}

/// Who is acting: her hero, account and name, checked present on this connection.
pub(crate) struct Me {
    pub hero: i64,
    pub account: i64,
    pub name: String,
}

impl Social {
    /// Opens the log at `path`: replays it into the state, then appends every later change to it. Also reads
    /// `path.words` (one word a line) into the default filter if there is one.
    pub fn persist(&self, path: &std::path::Path) -> std::io::Result<()> {
        let (file, text) = log::LogFile::open(path)?;
        let mut g = self.inner.lock().unwrap();
        g.replaying = true;
        for l in text.lines() {
            if let Some((k, f)) = log::parse(l) {
                g.apply(&k, &f);
            }
        }
        g.replaying = false;
        g.log = Some(file);
        drop(g);
        let words = std::path::PathBuf::from(format!("{}.words", path.display()));
        if let Ok(t) = std::fs::read_to_string(words) {
            let mut w: Vec<String> = filter::DEFAULT_WORDS.iter().map(|s| s.to_string()).collect();
            w.extend(t.lines().map(|l| l.trim().to_string()).filter(|l| !l.is_empty()));
            self.set_filter(default_filter(w));
        }
        Ok(())
    }

    /// Replaces the word filter (the hook).
    pub fn set_filter(&self, f: Filter) {
        *self.filter.write().unwrap() = f;
    }

    /// A request id no earlier run used (store ids must not repeat across runs).
    pub(crate) fn meta(&self, actor: i64) -> realm_store::Meta {
        let id = ((self.boot as u128) << 64) | (1u128 << 63) | self.n.fetch_add(1, Ordering::Relaxed) as u128;
        realm_store::Meta::new(id, actor, now_ms())
    }

    // ---- presence

    /// A hero is present on a connection (town or field). Idempotent for the same connection.
    #[allow(clippy::too_many_arguments)]
    pub fn attach(&self, hero: i64, account: i64, name: &str, class: u8, level: u16, conn: u64, out: Sender<Vec<u8>>, place: u8) {
        let mut g = self.inner.lock().unwrap();
        let was_online = g.is_online(account);
        if let Some(old) = g.online.get(&hero) {
            if old.conn != conn {
                let (a, c) = (old.account, old.conn);
                g.drop_presence(hero, a, c);
            }
        }
        g.online.insert(hero, Presence { hero, account, name: name.to_string(), class, level, conn, out, place });
        let list = g.by_account.entry(account).or_default();
        if !list.contains(&hero) {
            list.push(hero);
        }
        if g.names.get(&account).map(|s| s.as_str()) != Some(name) {
            g.commit("name", &[&account.to_string(), name]);
        }
        if !was_online {
            g.tell_friends(account, true);
        }
        g.party_changed_for(hero);
    }

    /// The connection has ended (or been closed by a moderator): every hero on it goes.
    pub fn detach_conn(&self, conn: u64) {
        let mut g = self.inner.lock().unwrap();
        let gone: Vec<(i64, i64)> = g.online.values().filter(|p| p.conn == conn).map(|p| (p.hero, p.account)).collect();
        for (h, a) in gone {
            g.leave_presence(h, a, conn);
        }
    }

    /// One hero leaves (she went back to the hero list) while the connection stays.
    pub fn detach_hero(&self, hero: i64, conn: u64) {
        let mut g = self.inner.lock().unwrap();
        if let Some(a) = g.online.get(&hero).filter(|p| p.conn == conn).map(|p| p.account) {
            g.leave_presence(hero, a, conn);
        }
    }

    /// Is this hero present and does she belong to this account?
    pub fn is_present(&self, hero: i64) -> bool {
        self.inner.lock().unwrap().online.contains_key(&hero)
    }

    pub fn online_count(&self) -> usize {
        self.inner.lock().unwrap().online.len()
    }

    // ---- chat

    /// Checks a line from `account` on `chan` and returns the text to send (filtered, cleaned), or why not.
    /// Order: empty, muted, rate (a flood silences her), filter. A muted account is refused on every channel.
    pub fn gate(&self, account: i64, chan: u8, text: &str, now: i64) -> Result<String, Refuse> {
        let text = crate::town::clean_chat(text);
        if text.is_empty() {
            return Err(Refuse::Empty);
        }
        let mut g = self.inner.lock().unwrap();
        if let Some(until) = g.muted_until(account, now) {
            return Err(Refuse::Muted { until });
        }
        match g.limiter.take(account, chan, now) {
            filter::Limit::Ok => {}
            filter::Limit::Slow => return Err(Refuse::Slow),
            filter::Limit::Flood => {
                let until = now + filter::AUTO_SILENCE_MS;
                g.commit("mute", &[&account.to_string(), &until.to_string(), "flood"]);
                g.commit("admin", &[&now.to_string(), "auto", &format!("silence #{account} 5m flood")]);
                g.send_account(account, &SPush::Notice { text: "You are silenced for flooding.".into() });
                return Err(Refuse::Flood);
            }
        }
        drop(g);
        let out = match (self.filter.read().unwrap())(&text) {
            Verdict::Pass(t) => t,
            Verdict::Block => return Err(Refuse::Filtered),
        };
        let mut g = self.inner.lock().unwrap();
        g.recent.push_back(ChatLine { at: now, account, chan, text: out.clone() });
        while g.recent.len() > RECENT_MAX {
            g.recent.pop_front();
        }
        Ok(out)
    }

    fn me(&self, s: &Session, account: i64, hero: i64) -> R<Me> {
        let g = self.inner.lock().unwrap();
        match g.online.get(&hero) {
            Some(p) if p.account == account && p.conn == s.conn => Ok(Me { hero, account, name: p.name.clone() }),
            Some(_) => Err(fail(code::NOT_YOURS, "that hero is not yours here")),
            None => Err(fail(code::BAD_REQUEST, "enter the town first")),
        }
    }

    /// Answers one social request from the session's account.
    pub fn handle(&self, gw: &Gateway, s: &Session, account: i64, req: SReq) -> Resp {
        match self.run(gw, s, account, req) {
            Ok(r) | Err(r) => r,
        }
    }

    fn run(&self, gw: &Gateway, s: &Session, account: i64, req: SReq) -> R {
        let hero = match &req {
            SReq::Talk { hero, .. }
            | SReq::PartyInvite { hero, .. }
            | SReq::PartyAnswer { hero, .. }
            | SReq::PartyLeave { hero }
            | SReq::PartyKick { hero, .. }
            | SReq::PartyLead { hero, .. }
            | SReq::PartyGo { hero, .. }
            | SReq::PartyInfo { hero }
            | SReq::GuildCreate { hero, .. }
            | SReq::GuildInvite { hero, .. }
            | SReq::GuildAnswer { hero, .. }
            | SReq::GuildLeave { hero }
            | SReq::GuildKick { hero, .. }
            | SReq::GuildRank { hero, .. }
            | SReq::GuildPerms { hero, .. }
            | SReq::GuildMotd { hero, .. }
            | SReq::GuildPost { hero, .. }
            | SReq::GuildUnpost { hero, .. }
            | SReq::GuildBank { hero, .. }
            | SReq::GuildBankView { hero, .. }
            | SReq::GuildInfo { hero }
            | SReq::GuildDisband { hero }
            | SReq::FriendAdd { hero, .. }
            | SReq::FriendAnswer { hero, .. }
            | SReq::FriendRemove { hero, .. }
            | SReq::Ignore { hero, .. }
            | SReq::Lists { hero }
            | SReq::Report { hero, .. } => *hero,
        };
        let me = self.me(s, account, hero)?;
        let now = now_ms();
        match req {
            SReq::Talk { chan, to, text, .. } => self.talk(gw, &me, chan, &to, &text, now),
            SReq::PartyInvite { name, .. } => self.party_invite(gw, &me, &name, now),
            SReq::PartyAnswer { inviter, accept, .. } => self.party_answer(&me, inviter, accept, now),
            SReq::PartyLeave { .. } => self.party_leave(&me),
            SReq::PartyKick { target, .. } => self.party_kick(&me, target),
            SReq::PartyLead { target, .. } => self.party_lead(&me, target),
            SReq::PartyGo { field, .. } => self.party_go(&me, field),
            SReq::PartyInfo { .. } => self.party_info(&me),
            SReq::GuildCreate { name, .. } => self.guild_create(&me, &name, now),
            SReq::GuildInvite { name, .. } => self.guild_invite(gw, &me, &name, now),
            SReq::GuildAnswer { guild, accept, .. } => self.guild_answer(&me, guild, accept, now),
            SReq::GuildLeave { .. } => self.guild_leave(gw, &me),
            SReq::GuildKick { target, .. } => self.guild_kick(&me, target),
            SReq::GuildRank { target, rank, .. } => self.guild_rank(&me, target, rank),
            SReq::GuildPerms { rank, perms, .. } => self.guild_perms(&me, rank, perms),
            SReq::GuildMotd { text, .. } => self.guild_motd(&me, &text, now),
            SReq::GuildPost { text, .. } => self.guild_post(&me, &text, now),
            SReq::GuildUnpost { post, .. } => self.guild_unpost(&me, post),
            SReq::GuildBank { what, tab, deposit, .. } => self.guild_bank(gw, &me, what, tab, deposit),
            SReq::GuildBankView { tab, .. } => self.guild_bank_view(gw, &me, tab),
            SReq::GuildInfo { .. } => self.guild_info(&me),
            SReq::GuildDisband { .. } => self.guild_disband(gw, &me),
            SReq::FriendAdd { name, .. } => self.friend_add(gw, &me, &name, now),
            SReq::FriendAnswer { from, accept, .. } => self.friend_answer(&me, from, accept, now),
            SReq::FriendRemove { target, .. } => self.friend_remove(&me, target),
            SReq::Ignore { name, on, .. } => self.ignore(gw, &me, &name, on),
            SReq::Lists { .. } => self.lists(&me, now),
            SReq::Report { name, reason, text, .. } => self.report(gw, &me, &name, reason, &text, now),
        }
    }

    /// A hero by name from the store (live heroes only).
    pub(crate) fn hero_named(&self, gw: &Gateway, name: &str) -> R<Hero> {
        match gw.store.hero_by_name(name.trim()) {
            Ok(Some(h)) => Ok(h),
            Ok(None) => Err(fail(code::MISSING, "no hero by that name")),
            Err(e) => Err(store_err(e)),
        }
    }

    fn talk(&self, gw: &Gateway, me: &Me, chan: u8, to: &str, text: &str, now: i64) -> R {
        if !(wire::chan::TOWN..wire::chan::COUNT as u8).contains(&chan) {
            return Err(bad("no such channel"));
        }
        // Who may hear it is settled before a token is spent, so a line to nobody costs her nothing.
        let target = if chan == wire::chan::WHISPER { Some(self.hero_named(gw, to)?) } else { None };
        {
            let g = self.inner.lock().unwrap();
            match chan {
                wire::chan::PARTY if !g.party_of.contains_key(&me.hero) => return Err(bad("you are in no party")),
                wire::chan::GUILD if !g.guild_of.contains_key(&me.account) => return Err(bad("you are in no guild")),
                _ => {}
            }
        }
        let text = self.gate(me.account, chan, text, now).map_err(|r| r.resp())?;
        let g = self.inner.lock().unwrap();
        let line = |to: &str| SPush::Chat { chan, from: me.name.clone(), to: to.to_string(), text: text.clone() };
        match chan {
            wire::chan::TOWN | wire::chan::TRADE => {
                let f = push_frame(line(""));
                let mut seen = Vec::new();
                for p in g.online.values() {
                    if !seen.contains(&p.conn) && !g.ignores(p.account, me.account) {
                        seen.push(p.conn);
                        let _ = p.out.send(f.clone());
                    }
                }
            }
            wire::chan::PARTY => {
                let id = g.party_of[&me.hero];
                let f = push_frame(line(""));
                for h in &g.parties[&id].members {
                    if let Some(p) = g.online.get(h).filter(|p| !g.ignores(p.account, me.account)) {
                        let _ = p.out.send(f.clone());
                    }
                }
            }
            wire::chan::GUILD => {
                let id = g.guild_of[&me.account];
                for a in g.guilds[&id].members.keys().filter(|a| !g.ignores(**a, me.account)) {
                    g.send_account(*a, &line(""));
                }
            }
            _ => {
                let t = target.expect("whisper target");
                if t.account == me.account {
                    return Err(bad("whisper to yourself?"));
                }
                if !g.is_online(t.account) {
                    return Err(fail(code::MISSING, "she is not here"));
                }
                // The speaker hears it echoed (so her client shows it); an ignoring listener hears nothing and
                // the speaker is not told.
                if !g.ignores(t.account, me.account) {
                    g.send_account(t.account, &line(&t.name));
                }
                g.send_account(me.account, &line(&t.name));
            }
        }
        Ok(Resp::Ok)
    }
}

impl Inner {
    /// Removes the presence record (no pushes).
    fn drop_presence(&mut self, hero: i64, account: i64, _conn: u64) {
        self.online.remove(&hero);
        if let Some(v) = self.by_account.get_mut(&account) {
            v.retain(|h| *h != hero);
            if v.is_empty() {
                self.by_account.remove(&account);
            }
        }
    }

    /// A hero leaves for good: out of her party, friends told when the last of her account's heroes goes.
    fn leave_presence(&mut self, hero: i64, account: i64, conn: u64) {
        self.party_remove(hero, "left");
        self.drop_presence(hero, account, conn);
        if !self.is_online(account) {
            self.tell_friends(account, false);
            self.limiter.forget(account);
        }
    }

    fn tell_friends(&self, account: i64, online: bool) {
        let Some(fr) = self.friends.get(&account) else { return };
        let place = if online { self.place_of(account).max(1) } else { 0 };
        let p = SPush::FriendStatus { account, name: self.name_of(account), online, place };
        for f in fr {
            if self.is_online(*f) {
                self.send_account(*f, &p);
            }
        }
    }
}
