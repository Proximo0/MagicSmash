//! Alarms: a log line every time, and a hook script (rate limited per kind) for a person to be told. The three the
//! plan names: tick budget breach, store errors, host death (a stalled field host here; a dead process is the
//! supervisor's, which calls `raise` too). `evaluate` is the pure rule, `Alarms` the cooldown and the hook.

use crate::{log, metrics};
use std::collections::HashMap;
use std::sync::atomic::Ordering::Relaxed;

#[derive(Clone, Debug)]
pub struct Limits {
    pub tick_budget_ms: f64,
    pub stall_ms: u64,
    pub store_errors_per_min: u64,
}

/// What the evaluator looks at: per field (p99 of the recent ticks, ticks recorded, ms since the last tick) and the
/// store error total.
#[derive(Clone, Debug, Default)]
pub struct Reading {
    pub fields: Vec<(u8, f64, u64, Option<u64>)>,
    pub store_errors_total: u64,
}

#[derive(Default)]
pub struct Evaluator {
    /// (time, total) at each of the last minute's readings, for the error rate.
    errors: Vec<(i64, u64)>,
}

impl Evaluator {
    /// The alarms this reading raises, as (kind, message). Kinds: tick-budget, host-stall, store-errors.
    pub fn evaluate(&mut self, lim: &Limits, r: &Reading, now_ms: i64) -> Vec<(&'static str, String)> {
        let mut out = Vec::new();
        for &(f, p99, ticks, age) in &r.fields {
            if ticks >= 100 && p99 > lim.tick_budget_ms {
                out.push(("tick-budget", format!("field {f}: tick p99 {p99:.1} ms is over the {:.0} ms budget", lim.tick_budget_ms)));
            }
            if let Some(a) = age {
                if a > lim.stall_ms {
                    out.push(("host-stall", format!("field {f}: no tick finished for {} s", a / 1000)));
                }
            }
        }
        self.errors.push((now_ms, r.store_errors_total));
        self.errors.retain(|&(t, _)| now_ms - t <= 60_000);
        let first = self.errors.first().map_or(0, |e| e.1);
        let n = r.store_errors_total.saturating_sub(first);
        if lim.store_errors_per_min > 0 && n >= lim.store_errors_per_min {
            out.push(("store-errors", format!("{n} store errors in the last minute")));
        }
        out
    }
}

pub struct Alarms {
    hook: String,
    cooldown_ms: i64,
    last: HashMap<String, i64>,
}

impl Alarms {
    pub fn new(hook: &str, cooldown_secs: u64) -> Alarms {
        Alarms { hook: hook.to_string(), cooldown_ms: cooldown_secs as i64 * 1000, last: HashMap::new() }
    }

    /// Logs the alarm; runs the hook unless the same kind ran it inside the cooldown. True when the hook ran.
    pub fn raise(&mut self, kind: &str, msg: &str, now_ms: i64) -> bool {
        metrics::REG.alarms.fetch_add(1, Relaxed);
        log::error("ALARM", &[("kind", kind.to_string()), ("msg", msg.to_string())]);
        if self.hook.is_empty() || self.last.get(kind).is_some_and(|&t| now_ms - t < self.cooldown_ms) {
            return false;
        }
        self.last.insert(kind.to_string(), now_ms);
        run_hook(&self.hook, kind, msg);
        true
    }
}

/// Runs the hook script with (kind, message) as arguments and in ALARM_KIND / ALARM_MSG. On its own thread: a hook
/// that hangs must not stop the watcher. A .ps1 is run through PowerShell, a .cmd/.bat through cmd.
pub fn run_hook(hook: &str, kind: &str, msg: &str) {
    let (hook, kind, msg) = (hook.to_string(), kind.to_string(), msg.to_string());
    let _ = std::thread::Builder::new().name("alarm-hook".into()).spawn(move || {
        let mut c = if hook.ends_with(".ps1") {
            let mut c = std::process::Command::new("powershell");
            c.args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", &hook]);
            c
        } else if hook.ends_with(".cmd") || hook.ends_with(".bat") {
            let mut c = std::process::Command::new("cmd");
            c.args(["/C", &hook]);
            c
        } else {
            std::process::Command::new(&hook)
        };
        match c.arg(&kind).arg(&msg).env("ALARM_KIND", &kind).env("ALARM_MSG", &msg).status() {
            Ok(s) if s.success() => {}
            Ok(s) => log::warn("alarm_hook_failed", &[("hook", hook.clone()), ("status", s.to_string())]),
            Err(e) => log::warn("alarm_hook_failed", &[("hook", hook.clone()), ("error", e.to_string())]),
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lim() -> Limits {
        Limits { tick_budget_ms: 50.0, stall_ms: 10_000, store_errors_per_min: 5 }
    }

    #[test]
    fn a_tick_budget_breach_stall_and_error_burst_each_alarm() {
        let mut e = Evaluator::default();
        let ok = Reading { fields: vec![(0, 20.0, 1000, Some(40))], store_errors_total: 0 };
        assert!(e.evaluate(&lim(), &ok, 0).is_empty());
        let slow = Reading { fields: vec![(2, 61.0, 1000, Some(40)), (3, 5.0, 1000, Some(30_000))], store_errors_total: 0 };
        let a = e.evaluate(&lim(), &slow, 1000);
        assert_eq!(a.iter().map(|x| x.0).collect::<Vec<_>>(), ["tick-budget", "host-stall"]);
        // Too few samples to judge a p99.
        let cold = Reading { fields: vec![(2, 99.0, 10, Some(40))], store_errors_total: 0 };
        assert!(e.evaluate(&lim(), &cold, 2000).is_empty());
        // Errors: 5 inside a minute alarm; the same 5 spread over two minutes do not.
        let burst = Reading { fields: vec![], store_errors_total: 5 };
        assert_eq!(e.evaluate(&lim(), &burst, 3000)[0].0, "store-errors");
        let mut e = Evaluator::default();
        for (t, n) in [(0, 0u64), (50_000, 3), (100_000, 5), (150_000, 7)] {
            assert!(e.evaluate(&lim(), &Reading { fields: vec![], store_errors_total: n }, t).is_empty(), "t={t}");
        }
    }

    #[test]
    fn the_hook_runs_once_per_cooldown() {
        let mut a = Alarms::new("", 300);
        assert!(!a.raise("x", "no hook", 0));
        // With a hook name that cannot run: still counts as run (the failure is logged), and the cooldown holds.
        let mut a = Alarms::new("/definitely/not/a/hook", 300);
        assert!(a.raise("tick-budget", "m", 0));
        assert!(!a.raise("tick-budget", "m", 299_000));
        assert!(a.raise("store-errors", "m", 299_000));
        assert!(a.raise("tick-budget", "m", 301_000));
    }
}
