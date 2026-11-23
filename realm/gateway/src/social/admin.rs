//! The moderator console (job T1): `realm-gateway admin ...`.
//!
//! One command interpreter (`Console::run`) over the store and the social state, used three ways: by the running
//! gateway for a loopback TCP admin port (`--admin-port`, guarded by the token in `{db}.admin`), by the
//! `admin --connect=ADDR --token-file=FILE <command>` client that talks to that port, and offline by
//! `admin --db=realm.db <command>` (for when the server is stopped; reads reports, bans, flags). Every command that
//! changes anything is logged with the operator's name (`--op=NAME`) in the social log's `admin` records, and bans
//! and flags leave their rows in the store's ledger too.
//!
//! Commands: `silence NAME SPAN [reason]`, `unsilence NAME`, `kick NAME [reason]`, `ban NAME SPAN [reason]`,
//! `unban NAME`, `flag NAME FLAGS` (comma list of trade_locked, shadowed, drops_reduced, watched, or `none`; with
//! `drops=PCT`), `banwave FLAG SPAN [reason]`, `reports [all] [N]`, `resolve ID`, `who NAME`, `log [N]`, `help`.
//! NAME is a hero's name or `#ACCOUNT`; SPAN is `30m`, `2h`, `7d` or `perm` (minutes for a silence, hours for a ban
//! when there is no unit).

use super::Social;
use crate::gateway::{now_ms, Gateway};
use realm_store::{flags, Account, FlagChange, Store};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::sync::Arc;

/// "Forever": the year 3000.
pub const PERM_MS: i64 = 32_503_680_000_000;

pub struct Console<'a> {
    pub store: &'a realm_store::SqliteStore,
    pub social: &'a Social,
    /// The running gateway, when there is one (kicks reach into fields only through it).
    pub live: Option<&'a Gateway>,
    pub op: String,
}

/// `30m`, `2h`, `7d`, `perm`, or a bare number of `default_unit` ('m' or 'h') into milliseconds.
pub fn parse_span(s: &str, default_unit: char) -> Option<i64> {
    if s.eq_ignore_ascii_case("perm") || s.eq_ignore_ascii_case("forever") {
        return Some(PERM_MS);
    }
    let (num, unit) = match s.chars().last()? {
        c if c.is_ascii_digit() => (s, default_unit),
        c => (&s[..s.len() - c.len_utf8()], c),
    };
    let n: i64 = num.parse().ok()?;
    let unit_ms = match unit {
        's' => 1000,
        'm' => 60_000,
        'h' => 3_600_000,
        'd' => 86_400_000,
        _ => return None,
    };
    (n > 0).then(|| n.checked_mul(unit_ms)).flatten().filter(|v| *v < PERM_MS)
}

pub fn flag_bit(name: &str) -> Option<u64> {
    Some(match name.to_ascii_lowercase().as_str() {
        "trade_locked" => flags::TRADE_LOCKED,
        "shadowed" => flags::SHADOWED,
        "drops_reduced" => flags::DROPS_REDUCED,
        "watched" => flags::WATCHED,
        _ => return None,
    })
}

fn flag_names(f: u64) -> String {
    let v: Vec<&str> = [(flags::TRADE_LOCKED, "trade_locked"), (flags::SHADOWED, "shadowed"), (flags::DROPS_REDUCED, "drops_reduced"), (flags::WATCHED, "watched")]
        .iter()
        .filter(|(b, _)| f & b != 0)
        .map(|(_, n)| *n)
        .collect();
    if v.is_empty() { "none".into() } else { v.join(",") }
}

fn until_text(u: i64, now: i64) -> String {
    if u <= now {
        "no".into()
    } else if u >= PERM_MS {
        "forever".into()
    } else {
        format!("for {} min", (u - now + 59_999) / 60_000)
    }
}

impl Console<'_> {
    fn account_of(&self, who: &str) -> Result<(i64, String), String> {
        if let Some(n) = who.strip_prefix('#') {
            let id: i64 = n.parse().map_err(|_| format!("bad account {who}"))?;
            return match self.store.account(id) {
                Ok(Some(_)) => Ok((id, self.social.name_of(id))),
                _ => Err(format!("no account {id}")),
            };
        }
        match self.store.hero_by_name(who) {
            Ok(Some(h)) => {
                self.social.note_name(h.account, &h.name);
                Ok((h.account, h.name))
            }
            _ => Err(format!("no hero named {who}")),
        }
    }

    fn account(&self, id: i64) -> Result<Account, String> {
        self.store.account(id).map_err(|e| e.to_string())?.ok_or_else(|| format!("no account {id}"))
    }

    fn set_ban(&self, id: i64, until: Option<i64>, reason: &str) -> Result<(), String> {
        let a = self.account(id)?;
        let c = FlagChange { account: id, flags: a.flags, drops_percent: a.drops_percent, banned_until: until };
        self.store.apply_flags(self.social.meta(0), vec![c], reason).map_err(|e| e.to_string())
    }

    /// Takes the account's heroes out of the game now.
    fn throw_out(&self, id: i64, notice: &str) -> usize {
        let heroes = self.social.end_sessions(id, notice);
        if let Some(gw) = self.live {
            for h in &heroes {
                gw.kick(*h);
            }
        }
        heroes.len()
    }

    /// Runs one command line and returns what to print.
    pub fn run(&self, line: &str) -> String {
        let now = now_ms();
        let w: Vec<&str> = line.split_whitespace().collect();
        let rest = |from: usize| w.get(from..).map(|s| s.join(" ")).unwrap_or_default();
        let out = match w.first().copied() {
            None | Some("help") => Ok(HELP.trim().to_string()),
            Some("kill" | "revive" | "switches") => realm_ops::switches::command(&w).unwrap_or_else(|| Err("kill what?".into())).inspect(|_| {
                self.social.log_admin(now, &self.op, line.trim());
            }),
            Some("silence") if w.len() >= 3 => self.account_of(w[1]).and_then(|(id, name)| {
                let span = parse_span(w[2], 'm').ok_or("bad span (30m, 2h, 7d, perm)")?;
                let reason = rest(3);
                self.social.silence(id, now.saturating_add(span).min(PERM_MS), &reason, &self.op, now);
                Ok(format!("{name} (#{id}) is silenced {}", until_text(now + span, now)))
            }),
            Some("unsilence") if w.len() == 2 => self.account_of(w[1]).map(|(id, name)| {
                self.social.silence(id, 0, "lifted", &self.op, now);
                format!("{name} (#{id}) may speak")
            }),
            Some("kick") if w.len() >= 2 => self.account_of(w[1]).map(|(id, name)| {
                let n = self.throw_out(id, "A moderator has removed you from the game.");
                self.social.log_admin(now, &self.op, &format!("kick #{id} {}", rest(2)));
                format!("{name} (#{id}) kicked, {n} hero(es) removed")
            }),
            Some("ban") if w.len() >= 3 => self.account_of(w[1]).and_then(|(id, name)| {
                let span = parse_span(w[2], 'h').ok_or("bad span (30m, 2h, 7d, perm)")?;
                let until = now.saturating_add(span).min(PERM_MS);
                self.set_ban(id, Some(until), &format!("ban by {}: {}", self.op, rest(3)))?;
                self.social.log_admin(now, &self.op, &format!("ban #{id} until {until} {}", rest(3)));
                let n = self.throw_out(id, "You have been banned.");
                Ok(format!("{name} (#{id}) banned {}, {n} hero(es) removed", until_text(until, now)))
            }),
            Some("unban") if w.len() == 2 => self.account_of(w[1]).and_then(|(id, name)| {
                self.set_ban(id, None, &format!("unban by {}", self.op))?;
                self.social.log_admin(now, &self.op, &format!("unban #{id}"));
                Ok(format!("{name} (#{id}) may log in"))
            }),
            Some("flag") if w.len() >= 3 => self.account_of(w[1]).and_then(|(id, name)| {
                let a = self.account(id)?;
                let mut f = 0u64;
                let mut drops = a.drops_percent;
                for part in w[2..].iter().flat_map(|p| p.split(',')) {
                    if let Some(p) = part.strip_prefix("drops=") {
                        drops = p.parse::<u8>().ok().filter(|p| *p <= 100).ok_or("drops=0..100")?;
                    } else if part != "none" {
                        f |= flag_bit(part).ok_or_else(|| format!("unknown flag {part}"))?;
                    }
                }
                let c = FlagChange { account: id, flags: f, drops_percent: drops, banned_until: a.banned_until };
                self.store.apply_flags(self.social.meta(0), vec![c], &format!("flag by {}", self.op)).map_err(|e| e.to_string())?;
                self.social.log_admin(now, &self.op, &format!("flag #{id} {} drops={drops}", flag_names(f)));
                Ok(format!("{name} (#{id}) flags: {}", flag_names(f)))
            }),
            Some("banwave") if w.len() >= 3 => (|| {
                let mask = flag_bit(w[1]).ok_or_else(|| format!("unknown flag {}", w[1]))?;
                let span = parse_span(w[2], 'h').ok_or("bad span (30m, 2h, 7d, perm)")?;
                let until = now.saturating_add(span).min(PERM_MS);
                let hit = self.store.accounts_flagged(mask).map_err(|e| e.to_string())?;
                if hit.is_empty() {
                    return Ok(format!("no account is flagged {}", w[1]));
                }
                let changes: Vec<FlagChange> =
                    hit.iter().map(|a| FlagChange { account: a.id, flags: a.flags, drops_percent: a.drops_percent, banned_until: Some(until) }).collect();
                self.store.apply_flags(self.social.meta(0), changes, &format!("ban wave {} by {}: {}", w[1], self.op, rest(3))).map_err(|e| e.to_string())?;
                let ids: Vec<String> = hit.iter().map(|a| a.id.to_string()).collect();
                self.social.log_admin(now, &self.op, &format!("banwave {} until {until} accounts {}", w[1], ids.join(",")));
                let removed: usize = hit.iter().map(|a| self.throw_out(a.id, "You have been banned.")).sum();
                Ok(format!("{} account(s) banned {}, {removed} hero(es) removed", hit.len(), until_text(until, now)))
            })(),
            Some("reports") => {
                let all = w.get(1) == Some(&"all");
                let n = w.iter().skip(1).find_map(|x| x.parse::<usize>().ok()).unwrap_or(20);
                let rs = self.social.reports(!all, n);
                if rs.is_empty() {
                    Ok("no reports".into())
                } else {
                    let mut s = String::new();
                    for (r, by, on) in rs {
                        let reason = super::modtools::REASONS.get(r.reason as usize).copied().unwrap_or("?");
                        s.push_str(&format!("#{} {} {by} (#{}) reports {on} (#{}) for {reason}{}: {}\n", r.id, r.at, r.reporter, r.target, r.done.as_ref().map_or(String::new(), |d| format!(" [closed by {d}]")), r.text));
                        for e in r.evidence {
                            s.push_str(&format!("    | {e}\n"));
                        }
                    }
                    Ok(s.trim_end().to_string())
                }
            }
            Some("resolve") if w.len() == 2 => match w[1].parse::<u64>() {
                Ok(id) if self.social.close_report(id, &self.op, now) => Ok(format!("report {id} closed")),
                _ => Err("no such open report".to_string()),
            },
            Some("who") if w.len() == 2 => self.account_of(w[1]).and_then(|(id, name)| {
                let a = self.account(id)?;
                let heroes = self.store.heroes(id, false).map_err(|e| e.to_string())?;
                let names: Vec<String> = heroes.iter().map(|h| h.name.clone()).collect();
                Ok(format!(
                    "{name} (#{id}) heroes [{}] flags {} drops {}% banned {} silenced {} online {}",
                    names.join(", "),
                    flag_names(a.flags),
                    a.drops_percent,
                    until_text(a.banned_until.unwrap_or(0), now),
                    until_text(self.social.muted_until(id, now).unwrap_or(0), now),
                    !self.social.heroes_of(id).is_empty()
                ))
            }),
            Some("log") => {
                let n = w.get(1).and_then(|x| x.parse::<usize>().ok()).unwrap_or(20);
                let l = self.social.admin_log(n);
                Ok(if l.is_empty() { "the log is empty".into() } else { l.iter().map(|(at, op, line)| format!("{at} {op}: {line}")).collect::<Vec<_>>().join("\n") })
            }
            Some(other) => Err(format!("unknown or incomplete command {other:?}; try help")),
        };
        match out {
            Ok(s) => s,
            Err(e) => format!("error: {e}"),
        }
    }
}

const HELP: &str = "
silence NAME SPAN [reason]   unsilence NAME     (SPAN: 30m 2h 7d perm; a silence is heard by no channel)
kick NAME [reason]           ban NAME SPAN [reason]    unban NAME
flag NAME FLAGS [drops=PCT]  FLAGS: trade_locked,shadowed,drops_reduced,watched or none
banwave FLAG SPAN [reason]   ban every account carrying FLAG
reports [all] [N]            resolve ID        who NAME        log [N]
kill WHAT | revive WHAT      WHAT: login | trade | market | field N | all     switches (shows them)
NAME is a hero's name or #ACCOUNT.";

fn rand64(salt: u64) -> u64 {
    use std::hash::{BuildHasher, Hasher};
    let mut h = std::collections::hash_map::RandomState::new().build_hasher();
    h.write_u64(salt);
    h.write_u32(std::process::id());
    h.write_u64(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_nanos() as u64));
    h.finish()
}

/// The admin file beside the db: a token for the loopback port (made the first time).
pub fn load_token(path: &std::path::Path) -> String {
    if let Ok(t) = std::fs::read_to_string(path) {
        let t = t.trim().to_string();
        if t.len() >= 16 {
            return t;
        }
    }
    let t = format!("{:016x}{:016x}", rand64(1), rand64(2));
    let _ = std::fs::write(path, format!("{t}\n"));
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
    }
    t
}

/// Serves the console on a loopback port: a client sends `token<TAB>operator` and then a command line, and reads
/// the reply until the connection closes. Returns the address.
pub fn serve(gw: Arc<Gateway>, port: u16, token: String) -> std::io::Result<SocketAddr> {
    let l = TcpListener::bind(("127.0.0.1", port))?;
    let addr = l.local_addr()?;
    std::thread::Builder::new().name("admin".into()).spawn(move || {
        for s in l.incoming().flatten() {
            let (gw, token) = (gw.clone(), token.clone());
            let _ = std::thread::Builder::new().name("admin-conn".into()).spawn(move || answer(&gw, &token, s));
        }
    })?;
    Ok(addr)
}

fn answer(gw: &Gateway, token: &str, s: TcpStream) {
    let _ = s.set_read_timeout(Some(std::time::Duration::from_secs(10)));
    let Ok(mut w) = s.try_clone() else { return };
    let mut r = BufReader::new(s.take(4096));
    let (mut head, mut cmd) = (String::new(), String::new());
    if r.read_line(&mut head).is_err() || r.read_line(&mut cmd).is_err() {
        return;
    }
    let (tok, op) = head.trim_end().split_once('\t').unwrap_or((head.trim_end(), "admin"));
    // Constant-time compare: no early exit on the first wrong byte.
    let ok = tok.len() == token.len() && tok.bytes().zip(token.bytes()).fold(0u8, |a, (x, y)| a | (x ^ y)) == 0;
    if !ok {
        let _ = w.write_all(b"error: bad token\n");
        return;
    }
    let op: String = op.chars().filter(|c| c.is_alphanumeric() || *c == '_' || *c == '-').take(24).collect();
    let console = Console { store: &gw.store, social: &gw.social, live: Some(gw), op: if op.is_empty() { "admin".into() } else { op } };
    let out = console.run(cmd.trim());
    let _ = w.write_all(out.as_bytes());
    let _ = w.write_all(b"\n");
}

/// `realm-gateway admin ...`: returns the process exit code.
pub fn cli(args: &[String]) -> i32 {
    let (mut db, mut connect, mut token_file, mut op) = (None, None, None, "console".to_string());
    let mut words = Vec::new();
    for a in args {
        match a.split_once('=') {
            Some(("--db", v)) => db = Some(v.to_string()),
            Some(("--connect", v)) => connect = Some(v.to_string()),
            Some(("--token-file", v)) => token_file = Some(v.to_string()),
            Some(("--op", v)) => op = v.to_string(),
            _ => words.push(a.clone()),
        }
    }
    let line = words.join(" ");
    if let Some(addr) = connect {
        let Some(tf) = token_file else {
            eprintln!("admin: --connect needs --token-file=FILE (the db's .admin file)");
            return 2;
        };
        let token = std::fs::read_to_string(&tf).unwrap_or_default();
        let mut s = match TcpStream::connect(&addr) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("admin: cannot reach {addr}: {e}");
                return 2;
            }
        };
        let _ = s.write_all(format!("{}\t{op}\n{line}\n", token.trim()).as_bytes());
        let mut out = String::new();
        let _ = std::io::Read::read_to_string(&mut s, &mut out);
        print!("{out}");
        return i32::from(out.starts_with("error:"));
    }
    let Some(db) = db else {
        eprintln!("usage: realm-gateway admin (--db=realm.db | --connect=127.0.0.1:PORT --token-file=realm.db.admin) [--op=NAME] COMMAND...   (try: help)");
        return 2;
    };
    let store = match realm_store::SqliteStore::open(&db) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("admin: open {db}: {e}");
            return 2;
        }
    };
    let social = Social::default();
    if let Err(e) = social.persist(&realm_ops::sides::side(db.as_ref(), realm_ops::sides::SOCIAL)) {
        eprintln!("admin: social log: {e}");
        return 2;
    }
    // Switches thrown here are saved beside the store, and the realm reads them when it next starts.
    realm_ops::switches::persist(realm_ops::sides::side(db.as_ref(), realm_ops::sides::SWITCHES));
    let out = Console { store: &store, social: &social, live: None, op }.run(&line);
    println!("{out}");
    i32::from(out.starts_with("error:"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn spans() {
        assert_eq!(parse_span("30m", 'h'), Some(30 * 60_000));
        assert_eq!(parse_span("2", 'h'), Some(2 * 3_600_000));
        assert_eq!(parse_span("2", 'm'), Some(2 * 60_000));
        assert_eq!(parse_span("7d", 'h'), Some(7 * 86_400_000));
        assert_eq!(parse_span("perm", 'h'), Some(PERM_MS));
        assert_eq!(parse_span("0m", 'h'), None);
        assert_eq!(parse_span("x", 'h'), None);
        assert_eq!(parse_span("5w", 'h'), None);
    }
}
