//! Pulling the rug on bot and farm accounts, by hand only: `trace`, `plan`, `clawback`, `flag` and `wave`
//! (docs/realm/ops.md "Pulling the rug"). Nothing in the realm calls this on its own: it runs when an operator
//! types `realm-ops trace ...` (on a stopped realm or a backup copy with `--db=FILE`), or the same words reach the
//! running gateway's admin console as `rug ...` over the loopback admin port (the store has one writer, the
//! gateway, so a second process must not write to a live store).
//!
//! The command is one line of words. `--key=value` options carry no spaces; `--reason=` is last and takes the rest
//! of the line. File contents travel inline (`--items=`, `--stacks=` for a plan file, `--lines=` for a wave file),
//! so the console needs no file of the operator's machine. Every change goes through the store's own operations
//! (`clawback`, `apply_flags`) as the server (actor 0), so each leaves its ledger rows. Without `--yes`, a change
//! only prints what it would do.

use crate::time;
use realm_store::{flags, read, sqlite, Account, AccountId, ClawbackPlan, FlagChange, Hop, Item, ItemId, Meta, Owner, Party, Place, PlaceKind, SqliteStore, StackKind, Store};
use std::collections::{BTreeMap, BTreeSet};

/// "Forever": the year 3000 (the same as the console's `ban NAME perm`).
pub const PERM_MS: i64 = 32_503_680_000_000;

/// What a command did: the text to print, the accounts banned now (the live console throws their heroes out),
/// and a line for the moderators' admin log when something changed.
#[derive(Debug, Default)]
pub struct Done {
    pub text: String,
    pub banned: Vec<AccountId>,
    pub log: Option<String>,
}

/// The words of one command line.
#[derive(Debug, Default)]
pub struct Line {
    pub pos: Vec<String>,
    pub opts: BTreeMap<String, String>,
    pub flags: BTreeSet<String>,
    pub reason: Option<String>,
}

pub fn parse(line: &str) -> Line {
    let (head, reason) = match line.find("--reason=").filter(|i| *i == 0 || line[..*i].ends_with(char::is_whitespace)) {
        Some(i) => (&line[..i], Some(line[i + 9..].trim().to_string()).filter(|r| !r.is_empty())),
        None => (line, None),
    };
    let mut l = Line { reason, ..Default::default() };
    for w in head.split_whitespace() {
        match w.strip_prefix("--") {
            Some(o) => match o.split_once('=') {
                Some((k, v)) => {
                    l.opts.insert(k.to_string(), v.to_string());
                }
                None => {
                    l.flags.insert(o.to_string());
                }
            },
            None => l.pos.push(w.to_string()),
        }
    }
    l
}

/// Text that may hold spaces and commas, made one word of a comma list (and back).
pub fn enc(s: &str) -> String {
    s.replace('%', "%25").replace(',', "%2C").replace(char::is_whitespace, "%20")
}

pub fn dec(s: &str) -> String {
    s.replace("%20", " ").replace("%2C", ",").replace("%25", "%")
}

/// A wave file (one account per line: `12`, `#12` or a hero's name) as a `--lines=` value; blank lines keep their
/// place so a bad line is reported by its number.
pub fn wave_lines(text: &str) -> String {
    text.lines().map(|l| enc(l.trim())).collect::<Vec<_>>().join(",")
}

/// A plan file (what `plan` prints: lines `item ID ...` and `stack PLACE OWNER KIND COUNT ...`; others ignored).
pub fn parse_plan(text: &str) -> Result<ClawbackPlan, String> {
    let mut p = ClawbackPlan::default();
    for (n, line) in text.lines().enumerate() {
        let w: Vec<&str> = line.split_whitespace().collect();
        let bad = || format!("plan line {}: {line:?}", n + 1);
        match w.first().copied() {
            Some("item") => p.items.push(w.get(1).and_then(|x| x.parse().ok()).ok_or_else(bad)?),
            Some("stack") => {
                let kind = w.get(1).and_then(|k| PlaceKind::ALL.iter().copied().find(|p| p.name() == *k)).ok_or_else(bad)?;
                let owner: i64 = w.get(2).and_then(|x| x.parse().ok()).ok_or_else(bad)?;
                let sk: u32 = w.get(3).and_then(|x| x.parse().ok()).ok_or_else(bad)?;
                let count: u64 = w.get(4).and_then(|x| x.parse().ok()).ok_or_else(bad)?;
                p.stacks.push((Owner { kind, id: owner }, StackKind(sk), count));
            }
            _ => {}
        }
    }
    Ok(p)
}

/// A plan as `--items=` and `--stacks=` words.
pub fn plan_words(p: &ClawbackPlan) -> String {
    let items: Vec<String> = p.items.iter().map(|i| i.to_string()).collect();
    let stacks: Vec<String> = p.stacks.iter().map(|(o, k, n)| format!("{}:{}:{}:{n}", o.kind.name(), o.id, k.0)).collect();
    format!("--items={} --stacks={}", items.join(","), stacks.join(","))
}

fn plan_from_words(items: &str, stacks: &str) -> Result<ClawbackPlan, String> {
    let mut text = String::new();
    for i in items.split(',').filter(|s| !s.is_empty()) {
        text.push_str(&format!("item {i}\n"));
    }
    for s in stacks.split(',').filter(|s| !s.is_empty()) {
        text.push_str(&format!("stack {}\n", s.replace(':', " ")));
    }
    parse_plan(&text)
}

fn kind_name(k: StackKind) -> String {
    use realm_store::StackClass::*;
    match k.class() {
        Some(Coin) => "coin".into(),
        Some(Potion) => format!("potion {}", k.0 - 100),
        Some(Material) => format!("material {}", k.0 - 1000),
        Some(Rune) => format!("rune {}", k.0 - 2000),
        Some(Key) => format!("key {}", k.0 - 3000),
        Some(Page) => format!("page {}", k.0 - 4000),
        Some(Card) => format!("card {}", k.0 - 5000),
        None => format!("kind {}", k.0),
    }
}

fn party(p: &Party) -> String {
    match p {
        Party::Account(a) => format!("#{a}"),
        Party::Guild(g) => format!("guild {g}"),
        Party::Market(m) => format!("listing {m}"),
        Party::Trade(t) => format!("trade {t}"),
    }
}

fn json_str(s: &str) -> String {
    let mut o = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

fn json_opt<T: ToString>(v: Option<T>) -> String {
    v.map_or("null".into(), |v| v.to_string())
}

fn hop_json(h: &Hop) -> String {
    format!(
        "{{\"depth\":{},\"seq\":{},\"from\":{},\"to\":{},\"item\":{},\"stack\":{},\"count\":{}}}",
        h.depth,
        h.seq,
        json_str(&party(&h.from)),
        json_str(&party(&h.to)),
        json_opt(h.item),
        json_opt(h.stack.map(|k| k.0)),
        h.count
    )
}

fn hop_text(h: &Hop) -> String {
    let what = match (h.item, h.stack) {
        (Some(i), _) => format!("item {i}"),
        (None, Some(k)) => format!("{} x{}", kind_name(k), h.count),
        _ => "?".into(),
    };
    format!("  hop {} seq {}: {} -> {} {what}", h.depth, h.seq, party(&h.from), party(&h.to))
}

/// The rug commands over one store. `meta` gives a fresh server request (actor 0) for each change.
pub struct Rug<'a> {
    pub store: &'a SqliteStore,
    pub meta: &'a dyn Fn() -> Meta,
    pub op: &'a str,
    pub now: i64,
}

impl Rug<'_> {
    fn e<T>(r: realm_store::Result<T>) -> Result<T, String> {
        r.map_err(|e| e.to_string())
    }

    /// `12`, `#12`, or a hero's name.
    pub fn account_of(&self, who: &str) -> Result<Account, String> {
        let id = match who.trim_start_matches('#').parse::<AccountId>() {
            Ok(id) => id,
            Err(_) => match Self::e(self.store.hero_by_name(who))? {
                Some(h) => h.account,
                None => return Err(format!("no account or hero {who:?}")),
            },
        };
        Self::e(self.store.account(id))?.ok_or_else(|| format!("no account {id}"))
    }

    /// The account holding a place (None for a guild bank, listing or trade session).
    fn account_at(&self, p: &Place) -> Option<AccountId> {
        match p.kind {
            PlaceKind::Bag | PlaceKind::Worn | PlaceKind::Mail => self.store.hero(p.owner).ok().flatten().map(|h| h.account),
            PlaceKind::Bank | PlaceKind::House => Some(p.owner),
            _ => None,
        }
    }

    fn owner_account(&self, o: &Owner) -> Option<AccountId> {
        self.account_at(&Place { kind: o.kind, owner: o.id, tab: 0, slot: 0 })
    }

    fn holder_text(&self, p: &Place) -> String {
        match (self.account_at(p), p.kind) {
            (Some(a), _) => format!("#{a}"),
            (None, PlaceKind::Guild) => format!("guild {}", p.owner),
            (None, PlaceKind::Market) => format!("listing {}", p.owner),
            (None, PlaceKind::Trade) => format!("trade {}", p.owner),
            (None, _) => "?".into(),
        }
    }

    /// Items the account holds now that were minted for someone else.
    fn held_from_others(&self, account: AccountId) -> Result<Vec<Item>, String> {
        let mut v = Vec::new();
        for h in Self::e(self.store.heroes(account, true))? {
            for k in [PlaceKind::Bag, PlaceKind::Worn, PlaceKind::Mail] {
                v.extend(Self::e(self.store.items_at(k, h.id))?);
            }
        }
        for k in [PlaceKind::Bank, PlaceKind::House] {
            v.extend(Self::e(self.store.items_at(k, account))?);
        }
        v.retain(|i| i.origin_account != account);
        v.sort_by_key(|i| i.id);
        Ok(v)
    }

    /// `since`: `seq:N`, a UTC date (`2026-11-20`, `2026-11-20T18:00`), unix ms, or a span back from now (`7d`, `12h`).
    fn since_seq(&self, since: Option<&String>) -> Result<i64, String> {
        let Some(s) = since else { return Ok(0) };
        if let Some(n) = s.strip_prefix("seq:") {
            return n.parse().map_err(|_| format!("bad --since {s}"));
        }
        let t = if let Some(t) = time::parse_iso(s) {
            t
        } else if let Ok(ms) = s.parse::<i64>() {
            ms
        } else {
            let (num, unit) = s.split_at(s.len().saturating_sub(1));
            let n: i64 = num.parse().map_err(|_| format!("bad --since {s} (seq:N, 2026-11-20, 2026-11-20T18:00, unix ms, or 7d / 12h / 30m ago)"))?;
            let unit_ms = match unit {
                "d" => 86_400_000,
                "h" => 3_600_000,
                "m" => 60_000,
                _ => return Err(format!("bad --since {s}")),
            };
            self.now - n * unit_ms
        };
        let c = Self::e(sqlite::open_reader(self.store.path()))?;
        Self::e(read::seq_before(&c, t))
    }

    /// Runs one command line.
    pub fn run(&self, line: &str) -> Result<Done, String> {
        let l = parse(line);
        let cmd = l.pos.first().map(|s| s.as_str()).unwrap_or("");
        match cmd {
            "trace" => self.trace(&l).map(|text| Done { text, ..Default::default() }),
            "plan" => {
                let a = self.account_of(l.pos.get(1).ok_or("plan ACCOUNT")?)?;
                let p = self.plan(&l, a.id)?;
                Ok(Done { text: self.plan_text(a.id, &p), ..Default::default() })
            }
            "clawback" => self.clawback(&l),
            "flag" => {
                let who = l.pos.get(1).ok_or("flag ACCOUNT lock|shadow|ban|clear")?;
                let action = l.pos.get(2).ok_or("flag ACCOUNT lock|shadow|ban|clear")?;
                self.flags(&l, action, &[(1, who.clone())])
            }
            "wave" => {
                let action = l.pos.get(1).ok_or("wave FILE lock|shadow|ban|clear")?;
                let lines: Vec<(usize, String)> =
                    l.opts.get("lines").map(|s| s.split(',').map(dec).enumerate().map(|(i, s)| (i + 1, s)).filter(|(_, s)| !s.trim().is_empty()).collect()).unwrap_or_default();
                if lines.is_empty() {
                    return Err("the wave file names no account".into());
                }
                self.flags(&l, action, &lines)
            }
            other => Err(format!("unknown rug command {other:?}: trace, plan, clawback, flag, wave")),
        }
    }

    fn trace(&self, l: &Line) -> Result<String, String> {
        let target = l.pos.get(1).ok_or("trace ACCOUNT | #ACCOUNT | hero:NAME | hero:ID | item:ID")?;
        let json = l.flags.contains("json");
        let depth: u32 = l.opts.get("depth").map(|d| d.parse().map_err(|_| "bad --depth")).transpose()?.unwrap_or(3);
        if let Some(id) = target.strip_prefix("item:") {
            let id: ItemId = id.parse().map_err(|_| format!("bad item {id}"))?;
            return self.trace_item(id, depth.max(16), json);
        }
        let (account, head) = if let Some(h) = target.strip_prefix("hero:") {
            let hero = match h.parse::<i64>() {
                Ok(id) => Self::e(self.store.hero(id))?,
                Err(_) => Self::e(self.store.hero_by_name(h))?,
            }
            .ok_or_else(|| format!("no hero {h}"))?;
            (hero.account, format!("hero {} ({}) of #{}", hero.name, hero.id, hero.account))
        } else {
            let a = self.account_of(target)?;
            (a.id, format!("account #{}", a.id))
        };
        let tr = Self::e(self.store.trace(account))?;
        let hops = Self::e(self.store.trace_forward(account, depth))?;
        let others = self.held_from_others(account)?;
        if json {
            let items: Vec<String> = tr
                .items
                .iter()
                .map(|i| {
                    format!(
                        "{{\"item\":{},\"mint_seq\":{},\"origin_hero\":{},\"place\":{},\"holder\":{}}}",
                        i.item,
                        i.mint_seq,
                        json_opt(i.origin_hero),
                        i.place.map_or("null".into(), |p| json_str(&p.to_string())),
                        i.holder.map_or("null".into(), |h| json_str(&party(&h)))
                    )
                })
                .collect();
            let pairs = |v: &[(Party, u64)]| v.iter().map(|(p, n)| format!("[{},{n}]", json_str(&party(p)))).collect::<Vec<_>>().join(",");
            let stacks: Vec<String> = tr
                .stacks
                .iter()
                .map(|s| format!("{{\"kind\":{},\"minted\":{},\"spent\":{},\"holds\":{},\"sent\":[{}],\"received\":[{}]}}", s.kind.0, s.minted, s.spent, s.holds, pairs(&s.sent), pairs(&s.received)))
                .collect();
            let held: Vec<String> = others.iter().map(|i| format!("{{\"item\":{},\"origin_account\":{},\"place\":{}}}", i.id, i.origin_account, json_str(&i.place.to_string()))).collect();
            let hops: Vec<String> = hops.iter().map(hop_json).collect();
            return Ok(format!(
                "{{\"account\":{account},\"depth\":{depth},\"items\":[{}],\"stacks\":[{}],\"held_from_others\":[{}],\"hops\":[{}]}}",
                items.join(","),
                stacks.join(","),
                held.join(","),
                hops.join(",")
            ));
        }
        let mut o = format!("trace {head}\nminted items: {}\n", tr.items.len());
        for i in &tr.items {
            match (i.place, i.holder) {
                (Some(p), h) => o.push_str(&format!("  item {} minted seq {}: now {p} held by {}\n", i.item, i.mint_seq, h.map_or("?".into(), |h| party(&h)))),
                (None, _) => o.push_str(&format!("  item {} minted seq {}: gone (sold or clawed back)\n", i.item, i.mint_seq)),
            }
        }
        o.push_str("stacks (came from / went to):\n");
        for s in &tr.stacks {
            let list = |v: &[(Party, u64)]| if v.is_empty() { "nobody".to_string() } else { v.iter().map(|(p, n)| format!("{} {n}", party(p))).collect::<Vec<_>>().join(", ") };
            o.push_str(&format!(
                "  {}: minted {} spent {} holds {}; received from {}; sent to {}\n",
                kind_name(s.kind),
                s.minted,
                s.spent,
                s.holds,
                list(&s.received),
                list(&s.sent)
            ));
        }
        o.push_str(&format!("items held that were minted for others: {}\n", others.len()));
        for i in &others {
            o.push_str(&format!("  item {} minted for #{} at {}\n", i.id, i.origin_account, i.place));
        }
        o.push_str(&format!("onward moves (depth {depth}): {}\n", hops.len()));
        for h in &hops {
            o.push_str(&hop_text(h));
            o.push('\n');
        }
        Ok(o.trim_end().to_string())
    }

    fn trace_item(&self, id: ItemId, depth: u32, json: bool) -> Result<String, String> {
        // a destroyed item has no row: find it in its minter's trace (any account's), else say so
        let item = Self::e(self.store.item(id))?;
        let Some(it) = item else { return Err(format!("item {id} does not exist now (sold or clawed back): trace its minter's account")) };
        let path: Vec<Hop> = Self::e(self.store.trace_forward(it.origin_account, depth))?.into_iter().filter(|h| h.item == Some(id)).collect();
        if json {
            return Ok(format!(
                "{{\"item\":{id},\"origin_account\":{},\"origin_hero\":{},\"mint_seq\":{},\"place\":{},\"holder\":{},\"hops\":[{}]}}",
                it.origin_account,
                json_opt(it.origin_hero),
                it.mint_seq,
                json_str(&it.place.to_string()),
                json_str(&self.holder_text(&it.place)),
                path.iter().map(hop_json).collect::<Vec<_>>().join(",")
            ));
        }
        let mut o = format!(
            "trace item {id}: minted for #{} (hero {}) at seq {}; now {} held by {}\npath: {} move(s)\n",
            it.origin_account,
            json_opt(it.origin_hero),
            it.mint_seq,
            it.place,
            self.holder_text(&it.place),
            path.len()
        );
        for h in &path {
            o.push_str(&hop_text(h));
            o.push('\n');
        }
        Ok(o.trim_end().to_string())
    }

    /// The plan for `account`: what it minted (since `--since`); with `--origin=FARM`, the part of FARM's plan
    /// that `account` holds now.
    fn plan(&self, l: &Line, account: AccountId) -> Result<ClawbackPlan, String> {
        let since = self.since_seq(l.opts.get("since"))?;
        match l.opts.get("origin") {
            None => Self::e(self.store.clawback_plan(account, since)),
            Some(o) => {
                let farm = self.account_of(o)?;
                let mut p = Self::e(self.store.clawback_plan(farm.id, since))?;
                p.items.retain(|i| self.store.item(*i).ok().flatten().is_some_and(|it| self.account_at(&it.place) == Some(account)));
                p.stacks.retain(|(o, _, _)| self.owner_account(o) == Some(account));
                Ok(p)
            }
        }
    }

    /// A plan printed so it can be read and kept as a plan file (`clawback --plan-file`).
    pub fn plan_text(&self, account: AccountId, p: &ClawbackPlan) -> String {
        let mut o = format!("plan for #{account}: {} item(s), {} stack(s)\n", p.items.len(), p.stacks.len());
        for i in &p.items {
            match self.store.item(*i).ok().flatten() {
                Some(it) => o.push_str(&format!("item {i} at {} held by {} (minted for #{})\n", it.place, self.holder_text(&it.place), it.origin_account)),
                None => o.push_str(&format!("item {i} (gone)\n")),
            }
        }
        let mut totals: BTreeMap<StackKind, u64> = BTreeMap::new();
        for (ow, k, n) in &p.stacks {
            *totals.entry(*k).or_default() += n;
            let who = self.owner_account(ow).map_or("?".into(), |a| format!("#{a}"));
            o.push_str(&format!("stack {} {} {} {n}  ({} from {} {} of {who})\n", ow.kind.name(), ow.id, k.0, kind_name(*k), ow.kind.name(), ow.id));
        }
        let t: Vec<String> = totals.iter().map(|(k, n)| format!("{} {n}", kind_name(*k))).collect();
        o.push_str(&format!("total items {} stacks {}", p.items.len(), if t.is_empty() { "none".into() } else { t.join(", ") }));
        o
    }

    fn clawback(&self, l: &Line) -> Result<Done, String> {
        let a = self.account_of(l.pos.get(1).ok_or("clawback ACCOUNT --reason TEXT [--plan-file FILE] [--yes]")?)?;
        let plan = match (l.opts.get("items"), l.opts.get("stacks")) {
            (None, None) => self.plan(l, a.id)?,
            (i, s) => plan_from_words(i.map_or("", |s| s), s.map_or("", |s| s))?,
        };
        let mut text = self.plan_text(a.id, &plan);
        if !l.flags.contains("yes") {
            text.push_str("\ndry run: nothing changed (add --yes to claw this back)");
            return Ok(Done { text, ..Default::default() });
        }
        let reason = l.reason.as_deref().ok_or("clawback needs --reason TEXT")?;
        if plan.items.is_empty() && plan.stacks.is_empty() {
            return Ok(Done { text: format!("{text}\nnothing to claw back"), ..Default::default() });
        }
        let before = Self::e(self.store.stats())?.ledger_rows;
        let (removed, missing, short) = Self::e(self.store.clawback((self.meta)(), plan, &format!("clawback #{} by {}: {reason}", a.id, self.op)))?;
        let rows = Self::e(self.store.stats())?.ledger_rows - before;
        let ids = |v: &[ItemId]| v.iter().map(|i| i.to_string()).collect::<Vec<_>>().join(",");
        let shortfall: Vec<String> = short.iter().map(|(o, k, n)| format!("{} {} {} {n}", o.kind.name(), o.id, kind_name(*k))).collect();
        text.push_str(&format!(
            "\nclawback #{}: removed {} item(s) [{}], missing {} [{}], shortfall {}; ledger rows +{rows}",
            a.id,
            removed.len(),
            ids(&removed),
            missing.len(),
            ids(&missing),
            if shortfall.is_empty() { "none".into() } else { shortfall.join(", ") }
        ));
        Ok(Done { text, banned: vec![], log: Some(format!("rug clawback #{} removed {} missing {} short {}: {reason}", a.id, removed.len(), missing.len(), short.len())) })
    }

    fn flags(&self, l: &Line, action: &str, who: &[(usize, String)]) -> Result<Done, String> {
        let change = |a: &Account| -> Result<FlagChange, String> {
            let mut c = FlagChange { account: a.id, flags: a.flags, drops_percent: a.drops_percent, banned_until: a.banned_until };
            match action {
                "lock" => c.flags |= flags::TRADE_LOCKED,
                "shadow" => c.flags |= flags::SHADOWED,
                "ban" => c.banned_until = Some(PERM_MS),
                "clear" => {
                    c.flags = 0;
                    c.banned_until = None;
                }
                _ => return Err(format!("unknown action {action:?}: lock, shadow, ban or clear")),
            }
            Ok(c)
        };
        let yes = l.flags.contains("yes");
        let mut o = String::new();
        let (mut changes, mut bad, mut seen) = (Vec::new(), 0usize, BTreeSet::new());
        for (n, w) in who {
            let a = match self.account_of(w.trim()) {
                Ok(a) => a,
                Err(e) => {
                    bad += 1;
                    o.push_str(&format!("line {n} {:?}: {e}\n", w.trim()));
                    continue;
                }
            };
            if !seen.insert(a.id) {
                o.push_str(&format!("line {n} #{}: listed twice, once is enough\n", a.id));
                continue;
            }
            let c = change(&a)?;
            o.push_str(&format!(
                "#{}: flags {} -> {}, banned {} -> {}\n",
                a.id,
                flag_names(a.flags),
                flag_names(c.flags),
                ban_text(a.banned_until, self.now),
                ban_text(c.banned_until, self.now)
            ));
            changes.push(c);
        }
        let n = changes.len();
        if !yes {
            o.push_str(&format!("total {n} account(s) {action}, {bad} bad line(s); dry run: nothing changed (add --yes)"));
            return Ok(Done { text: o, ..Default::default() });
        }
        let reason = l.reason.as_deref().ok_or("flag and wave need --reason TEXT")?;
        if n > 0 {
            Self::e(self.store.apply_flags((self.meta)(), changes.clone(), &format!("rug {action} by {}: {reason}", self.op)))?;
        }
        o.push_str(&format!("total {n} account(s) {action}, {bad} bad line(s); applied"));
        let ids: Vec<String> = changes.iter().map(|c| c.account.to_string()).collect();
        let banned = if action == "ban" { changes.iter().map(|c| c.account).collect() } else { vec![] };
        Ok(Done { text: o, banned, log: (n > 0).then(|| format!("rug {action} accounts {}: {reason}", ids.join(","))) })
    }
}

fn flag_names(f: u64) -> String {
    let v: Vec<&str> = [(flags::TRADE_LOCKED, "trade_locked"), (flags::SHADOWED, "shadowed"), (flags::DROPS_REDUCED, "drops_reduced"), (flags::WATCHED, "watched")]
        .iter()
        .filter(|(b, _)| f & b != 0)
        .map(|(_, n)| *n)
        .collect();
    if v.is_empty() { "none".into() } else { v.join(",") }
}

fn ban_text(u: Option<i64>, now: i64) -> String {
    match u {
        Some(u) if u >= PERM_MS => "forever".into(),
        Some(u) if u > now => format!("until {}", time::iso(u)),
        _ => "no".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn words() {
        let l = parse("clawback #3 --since=7d --yes --reason=farm bots, wave 2");
        assert_eq!(l.pos, vec!["clawback", "#3"]);
        assert_eq!(l.opts.get("since").map(|s| s.as_str()), Some("7d"));
        assert!(l.flags.contains("yes"));
        assert_eq!(l.reason.as_deref(), Some("farm bots, wave 2"));
        assert_eq!(dec(&enc("a b,c%d")), "a b,c%d");
        assert!(!enc("a b,c").contains([' ', ',']));
        let p = parse_plan("plan for #1\nitem 5 at bag\nstack bank 2 1 40  (coin)\ntotal").unwrap();
        assert_eq!(p.items, vec![5]);
        assert_eq!(p.stacks, vec![(Owner { kind: PlaceKind::Bank, id: 2 }, StackKind::COIN, 40)]);
        assert_eq!(plan_from_words("5", "bank:2:1:40").unwrap(), p);
        assert!(parse_plan("stack bank x 1 4").is_err());
    }
}
