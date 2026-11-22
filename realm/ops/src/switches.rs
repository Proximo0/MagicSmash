//! Kill switches, thrown from the admin console and checked by the gateway: close login, freeze trade, freeze the
//! market, stop a field kind (no new heroes enter it; those inside finish their outing and bank as usual).
//! They live in one process-wide set of atomics, and in a file beside the store when `persist` is called, so a
//! restart in the middle of an incident does not quietly reopen what was closed.

use crate::{log, metrics};
use std::path::PathBuf;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering::Relaxed};

static LOGIN: AtomicBool = AtomicBool::new(false);
static TRADE: AtomicBool = AtomicBool::new(false);
static MARKET: AtomicBool = AtomicBool::new(false);
/// Bit k = field kind k stopped.
static FIELDS: AtomicU64 = AtomicU64::new(0);
static FILE: Mutex<Option<PathBuf>> = Mutex::new(None);

pub fn login_closed() -> bool {
    LOGIN.load(Relaxed)
}
pub fn trade_frozen() -> bool {
    TRADE.load(Relaxed)
}
pub fn market_frozen() -> bool {
    MARKET.load(Relaxed)
}
pub fn field_stopped(kind: u8) -> bool {
    kind < 64 && FIELDS.load(Relaxed) >> kind & 1 == 1
}

/// Counts a refused login (for the status page) and says whether login is closed.
pub fn refuse_login() -> bool {
    let c = login_closed();
    if c {
        metrics::REG.login_refused.fetch_add(1, Relaxed);
    }
    c
}

/// (how many are thrown, a line saying which)
pub fn describe() -> (u32, String) {
    let mut on = Vec::new();
    if login_closed() {
        on.push("login closed".to_string());
    }
    if trade_frozen() {
        on.push("trade frozen".to_string());
    }
    if market_frozen() {
        on.push("market frozen".to_string());
    }
    let f = FIELDS.load(Relaxed);
    for k in 0..64 {
        if f >> k & 1 == 1 {
            on.push(format!("field {k} stopped"));
        }
    }
    (on.len() as u32, if on.is_empty() { "none".into() } else { on.join(", ") })
}

pub fn reset() {
    LOGIN.store(false, Relaxed);
    TRADE.store(false, Relaxed);
    MARKET.store(false, Relaxed);
    FIELDS.store(0, Relaxed);
}

fn save() {
    if let Some(p) = FILE.lock().unwrap().as_ref() {
        let mut t = String::new();
        for (n, on) in [("login", login_closed()), ("trade", trade_frozen()), ("market", market_frozen())] {
            if on {
                t.push_str(n);
                t.push('\n');
            }
        }
        let f = FIELDS.load(Relaxed);
        for k in 0..64 {
            if f >> k & 1 == 1 {
                t.push_str(&format!("field {k}\n"));
            }
        }
        if let Err(e) = std::fs::write(p, t) {
            log::error("switches_save_failed", &[("file", p.display().to_string()), ("error", e.to_string())]);
        }
    }
}

/// Loads the saved switches from `path` (if it exists) and saves there from now on.
pub fn persist(path: PathBuf) {
    if let Ok(t) = std::fs::read_to_string(&path) {
        for l in t.lines() {
            let w: Vec<&str> = l.split_whitespace().collect();
            let _ = apply(&w, true, false);
        }
    }
    *FILE.lock().unwrap() = Some(path);
    let d = describe();
    if d.0 > 0 {
        log::warn("switches_restored", &[("on", d.1)]);
    }
}

fn apply(w: &[&str], on: bool, announce: bool) -> Result<String, String> {
    let (what, set): (String, Box<dyn Fn()>) = match w {
        ["login"] => ("login".into(), Box::new(move || LOGIN.store(on, Relaxed))),
        ["trade"] => ("trade".into(), Box::new(move || TRADE.store(on, Relaxed))),
        ["market"] => ("market".into(), Box::new(move || MARKET.store(on, Relaxed))),
        ["field", k] => {
            let k: u8 = k.parse().ok().filter(|&k| k < 64).ok_or("a field kind is a number 0..5")?;
            (format!("field {k}"), Box::new(move || {
                if on {
                    FIELDS.fetch_or(1 << k, Relaxed);
                } else {
                    FIELDS.fetch_and(!(1 << k), Relaxed);
                }
            }))
        }
        _ => return Err("what? login | trade | market | field N".into()),
    };
    set();
    if announce {
        log::warn("kill_switch", &[("what", what.clone()), ("state", if on { "thrown" } else { "released" }.into())]);
    }
    Ok(what)
}

/// The admin console's `kill WHAT`, `revive WHAT` (`all` for every switch) and `switches`. `None`: not ours.
pub fn command(w: &[&str]) -> Option<Result<String, String>> {
    let on = match w.first().copied()? {
        "kill" => true,
        "revive" => false,
        "switches" => return Some(Ok(format!("kill switches: {}", describe().1))),
        _ => return None,
    };
    let r = if w.get(1) == Some(&"all") {
        let all: [&[&str]; 3] = [&["login"], &["trade"], &["market"]];
        for a in all {
            let _ = apply(a, on, true);
        }
        if on { FIELDS.store(0b11_1111, Relaxed) } else { FIELDS.store(0, Relaxed) }
        Ok("all".to_string())
    } else {
        apply(&w[1..], on, true)
    };
    Some(r.map(|what| {
        save();
        format!("{what} {} (switches: {})", if on { "killed" } else { "revived" }, describe().1)
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    // One test, because the switches are process-wide.
    #[test]
    fn switches_throw_release_and_persist() {
        reset();
        let dir = std::env::temp_dir().join(format!("realm-ops-sw-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("realm.db.switches");
        let _ = std::fs::remove_file(&file);
        persist(file.clone());
        assert!(command(&["ban", "x"]).is_none());
        assert!(command(&["kill", "login"]).unwrap().is_ok());
        assert!(command(&["kill", "field", "3"]).unwrap().is_ok());
        assert!(command(&["kill", "market"]).unwrap().is_ok());
        assert!(command(&["kill", "field", "x"]).unwrap().is_err());
        assert!(command(&["kill", "wat"]).unwrap().is_err());
        assert!(login_closed() && market_frozen() && !trade_frozen() && field_stopped(3) && !field_stopped(2));
        assert_eq!(describe().0, 3);
        // A restart: forget them in memory, load the file.
        let saved = std::fs::read_to_string(&file).unwrap();
        assert_eq!(saved, "login\nmarket\nfield 3\n");
        reset();
        persist(file.clone());
        assert!(login_closed() && field_stopped(3));
        assert!(command(&["revive", "all"]).unwrap().is_ok());
        assert_eq!(describe().0, 0);
        assert_eq!(std::fs::read_to_string(&file).unwrap(), "");
        assert!(command(&["kill", "all"]).unwrap().is_ok());
        assert_eq!(describe().0, 3 + 6);
        reset();
        *FILE.lock().unwrap() = None;
        let _ = std::fs::remove_dir_all(&dir);
    }
}
