//! Reports, silences and the moderators' hooks into live sessions (job T1). The console (`admin.rs`) is the only
//! caller of everything but `report`, and every call is logged: the `admin` records in the social log say who did
//! what and when, and a ban or flag also leaves its row in the store's ledger.

use super::*;

/// A player may file one report in this many ms, and keep this many open.
pub const REPORT_GAP_MS: i64 = 30_000;
pub const REPORT_OPEN_MAX: usize = 20;
pub const REPORT_TEXT_MAX: usize = 200;
pub const REASONS: [&str; 5] = ["spam", "abuse", "cheating", "name", "other"];

impl Social {
    pub(super) fn report(&self, gw: &Gateway, me: &Me, name: &str, reason: u8, text: &str, now: i64) -> R {
        if reason as usize >= REASONS.len() {
            return Err(bad("reason 0 to 4"));
        }
        let t = self.hero_named(gw, name)?;
        if t.account == me.account {
            return Err(bad("not yourself"));
        }
        let mut g = self.inner.lock().unwrap();
        if g.last_report.get(&me.account).is_some_and(|at| now - at < REPORT_GAP_MS) {
            return Err(fail(code::SLOW_DOWN, "one report at a time"));
        }
        if g.reports.iter().filter(|r| r.reporter == me.account && r.done.is_none()).count() >= REPORT_OPEN_MAX {
            return Err(fail(code::FULL, "too many open reports"));
        }
        // The same player's open report on the same account is one report.
        if g.reports.iter().any(|r| r.reporter == me.account && r.target == t.account && r.done.is_none()) {
            return Err(fail(code::BUSY, "you already reported her"));
        }
        let evidence: Vec<String> = g
            .recent
            .iter()
            .rev()
            .filter(|l| l.account == t.account)
            .take(EVIDENCE_LINES)
            .map(|l| format!("{} ch{} {}", l.at, l.chan, l.text))
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
            .collect();
        let id = g.reports.iter().map(|r| r.id).max().unwrap_or(0) + 1;
        let text: String = crate::town::clean_chat(text).chars().take(REPORT_TEXT_MAX).collect();
        g.last_report.insert(me.account, now);
        g.commit(
            "report",
            &[&id.to_string(), &now.to_string(), &me.account.to_string(), &t.account.to_string(), &reason.to_string(), &text, &evidence.join("\u{1f}")],
        );
        if g.names.get(&t.account) != Some(&t.name) {
            g.commit("name", &[&t.account.to_string(), &t.name]);
        }
        Ok(Resp::Social(SResp::Reported(id)))
    }

    // ---- moderator calls (from the console)

    /// Writes one line to the moderators' log.
    pub fn log_admin(&self, now: i64, op: &str, line: &str) {
        self.inner.lock().unwrap().commit("admin", &[&now.to_string(), op, line]);
    }

    /// Silences `account` until `until` (ms); `until` 0 lifts it. Told to her, and logged.
    pub fn silence(&self, account: i64, until: i64, reason: &str, op: &str, now: i64) {
        let mut g = self.inner.lock().unwrap();
        g.commit("mute", &[&account.to_string(), &until.to_string(), reason]);
        let line = if until > 0 { format!("silence #{account} until {until} {reason}") } else { format!("unsilence #{account} {reason}") };
        g.commit("admin", &[&now.to_string(), op, &line]);
        let text = if until > 0 { "A moderator has silenced you." } else { "You may speak again." };
        g.send_account(account, &SPush::Notice { text: text.into() });
    }

    pub fn muted_until(&self, account: i64, now: i64) -> Option<i64> {
        self.inner.lock().unwrap().muted_until(account, now)
    }

    /// Ends every session of the account: she is told, her connections are closed (an empty frame tells the
    /// connection's writer to stop) and her presence goes. Returns the heroes that were present, so the caller
    /// can take them out of their fields.
    pub fn end_sessions(&self, account: i64, notice: &str) -> Vec<i64> {
        let mut g = self.inner.lock().unwrap();
        let heroes: Vec<i64> = g.by_account.get(&account).cloned().unwrap_or_default();
        g.send_account(account, &SPush::Notice { text: notice.into() });
        let mut closed = Vec::new();
        for h in &heroes {
            if let Some(p) = g.online.get(h) {
                if !closed.contains(&p.conn) {
                    closed.push(p.conn);
                    let _ = p.out.send(Vec::new());
                }
            }
        }
        for c in closed {
            let gone: Vec<(i64, i64)> = g.online.values().filter(|p| p.conn == c).map(|p| (p.hero, p.account)).collect();
            for (h, a) in gone {
                g.leave_presence(h, a, c);
            }
        }
        heroes
    }

    pub fn reports(&self, open_only: bool, limit: usize) -> Vec<(Report, String, String)> {
        let g = self.inner.lock().unwrap();
        g.reports
            .iter()
            .filter(|r| !open_only || r.done.is_none())
            .rev()
            .take(limit)
            .map(|r| (r.clone(), g.name_of(r.reporter), g.name_of(r.target)))
            .collect()
    }

    pub fn close_report(&self, id: u64, op: &str, now: i64) -> bool {
        let mut g = self.inner.lock().unwrap();
        if !g.reports.iter().any(|r| r.id == id && r.done.is_none()) {
            return false;
        }
        g.commit("rdone", &[&id.to_string(), op]);
        g.commit("admin", &[&now.to_string(), op, &format!("closed report {id}")]);
        true
    }

    pub fn admin_log(&self, limit: usize) -> Vec<(i64, String, String)> {
        let g = self.inner.lock().unwrap();
        let skip = g.admin_log.len().saturating_sub(limit);
        g.admin_log.iter().skip(skip).cloned().collect()
    }

    /// The name last seen for an account (or `#id`).
    pub fn name_of(&self, account: i64) -> String {
        self.inner.lock().unwrap().name_of(account)
    }

    /// Notes a name for an account (the console learns it from the store).
    pub fn note_name(&self, account: i64, name: &str) {
        let mut g = self.inner.lock().unwrap();
        if g.names.get(&account).map(|s| s.as_str()) != Some(name) {
            g.commit("name", &[&account.to_string(), name]);
        }
    }

    /// Heroes now present for an account.
    pub fn heroes_of(&self, account: i64) -> Vec<i64> {
        self.inner.lock().unwrap().by_account.get(&account).cloned().unwrap_or_default()
    }
}
