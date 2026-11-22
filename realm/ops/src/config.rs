//! The one config file (`ops.conf`): `key = value` lines, `#` comments. `SETTINGS` is the whole list with each
//! default and what it does; `template()` writes the shipped file from it, so the file and the code cannot drift
//! (a test pins that). Unknown keys and unreadable numbers are errors, never ignored.

use std::collections::HashMap;
use std::path::Path;

pub struct Setting {
    pub key: &'static str,
    pub default: &'static str,
    pub doc: &'static str,
}

const fn s(key: &'static str, default: &'static str, doc: &'static str) -> Setting {
    Setting { key, default, doc }
}

pub const SETTINGS: &[Setting] = &[
    // The realm itself (they become realm-gateway flags).
    s("db", "data/realm.db", "The store file (SQLite). Its .secret, .admin, .social and .bosskills files sit beside it and are backed up with it. Relative paths are inside the host folder."),
    s("bind", "0.0.0.0", "Address the gateway's TCP port listens on. 127.0.0.1 keeps the realm private (a test on one PC)."),
    s("port", "7700", "Gateway TCP port (login, heroes, town). Forward it on the router."),
    s("public_host", "", "The address clients are told to send field UDP to (the PC's public name or IP). Empty: the address the client used."),
    s("fields", "0,1,2,3,4,5", "Field kinds to host: 0 THE FOOL'S ROAD .. 5. Leaving one out is how a box too small for all six runs part of the realm."),
    s("copies", "1", "Copies of each field kind (a second copy opens a second horde of the same field)."),
    s("field_port", "7800", "First UDP port of the field hosts; each field copy takes the next one (copies x fields ports). Forward the range."),
    s("monsters", "20000", "Monster count of each field's horde. 20000 is the design size; lower it on a weak PC."),
    s("threads", "1", "Simulation threads per field host. The result is the same for any number; more only helps a big field."),
    s("seed", "1", "Seed of the fields. Change it only for a new realm; it decides every field's layout."),
    s("admin_port", "7701", "Loopback admin console port (kill switches, moderators). 0 turns the console off. The token is in <db>.admin."),
    s("dev_login", "no", "yes lets anyone log in by a made-up name. Closed test and tests only; never on a public realm."),
    // Logs.
    s("log_dir", "logs", "Where structured logs go (realm.log, rotated)."),
    s("log_max_mb", "10", "Rotate realm.log when it reaches this many megabytes."),
    s("log_keep", "10", "Rotated logs kept (realm.log.1 .. realm.log.N); older ones are deleted."),
    // Metrics.
    s("metrics_port", "7790", "Loopback-only HTTP port: /metrics (text lines), /status (the page), /health. 0 turns it off. Never forwarded."),
    // Alarms.
    s("tick_budget_ms", "50", "A field tick must finish inside this (the 20 Hz period). The alarm fires when the 99th percentile of the last 200 ticks is over it."),
    s("stall_secs", "10", "A field host that has not finished a tick for this long is dead or stuck: alarm host-stall."),
    s("store_error_limit", "5", "Store errors in one minute that raise the store-errors alarm."),
    s("alarm_hook", "", "A script run on each alarm with the kind and the message as arguments (and ALARM_KIND, ALARM_MSG in the environment). Mail, a Discord webhook, a phone push: whatever you wire. Empty: log line only."),
    s("alarm_cooldown_secs", "300", "The same alarm kind runs the hook at most once in this time (it is logged every time)."),
    // Backups.
    s("backup_dir", "backups", "Where backups go: realm-YYYYMMDD-HHMMSS.db and the side files. Put it on another disk when you can."),
    s("backup_every_mins", "60", "Backup clock. 0 turns it off (not advised). Each backup is SQLite's online backup, so play goes on while it runs."),
    s("backup_keep", "48", "Backups kept; the oldest are deleted after each good one. With 60 minutes that is two days; the daily keeper below is separate."),
    s("backup_daily_keep", "14", "Besides those, the first backup of each day is kept for this many days (a long tail for an old mistake)."),
    // Flood protection.
    s("flood_conn_per_ip", "0", "Most simultaneous gateway connections from one IP. 0 = no limit. Households share an IP: 20 is a fair public value."),
    s("flood_conn_rate", "0", "Most new gateway connections from one IP in flood_window_secs. 0 = no limit. 10 is a fair public value."),
    s("flood_pkt_rate", "0", "Most gateway requests (frames) a second from one IP, averaged over the window (a burst of one window is allowed). 0 = no limit. 100 is a fair public value."),
    s("flood_udp_rate", "0", "Most field UDP packets a second from one IP (a client sends 20 a second per hero). 0 = no limit. 400 is a fair public value."),
    s("flood_window_secs", "10", "The window the connection and packet rates are counted over."),
    s("flood_ban_secs", "60", "An IP over a limit is refused completely for this long."),
    s("flood_exempt", "127.0.0.1,::1", "IPs never limited (this PC's own tools and tests). Comma separated."),
];

#[derive(Clone, Debug)]
pub struct Conf {
    vals: HashMap<String, String>,
}

impl Default for Conf {
    fn default() -> Conf {
        Conf { vals: SETTINGS.iter().map(|s| (s.key.to_string(), s.default.to_string())).collect() }
    }
}

impl Conf {
    pub fn parse(text: &str) -> Result<Conf, String> {
        let mut c = Conf::default();
        for (n, line) in text.lines().enumerate() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let Some((k, v)) = line.split_once('=') else { return Err(format!("line {}: expected key = value", n + 1)) };
            let (k, v) = (k.trim(), v.trim());
            let Some(st) = SETTINGS.iter().find(|s| s.key == k) else { return Err(format!("line {}: unknown setting {k:?}", n + 1)) };
            if !st.default.is_empty() && st.default.chars().all(|c| c.is_ascii_digit()) && v.parse::<u64>().is_err() {
                return Err(format!("line {}: {k} must be a whole number, got {v:?}", n + 1));
            }
            c.vals.insert(k.to_string(), v.to_string());
        }
        Ok(c)
    }

    pub fn load(path: &Path) -> Result<Conf, String> {
        let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
        Conf::parse(&text).map_err(|e| format!("{}: {e}", path.display()))
    }

    pub fn get(&self, key: &str) -> &str {
        self.vals.get(key).map(|s| s.as_str()).unwrap_or_else(|| panic!("no setting {key}"))
    }

    pub fn num(&self, key: &str) -> u64 {
        self.get(key).parse().unwrap_or(0)
    }

    pub fn yes(&self, key: &str) -> bool {
        matches!(self.get(key), "yes" | "true" | "on" | "1")
    }

    pub fn set(&mut self, key: &str, v: &str) {
        assert!(SETTINGS.iter().any(|s| s.key == key), "no setting {key}");
        self.vals.insert(key.to_string(), v.to_string());
    }

    /// A path setting inside `root` unless it is absolute.
    pub fn path(&self, root: &Path, key: &str) -> std::path::PathBuf {
        let p = Path::new(self.get(key));
        if p.is_absolute() {
            p.to_path_buf()
        } else {
            // Join part by part so a relative "data/realm.db" uses this OS's separator throughout.
            self.get(key).split(['/', '\\']).filter(|c| !c.is_empty()).fold(root.to_path_buf(), |acc, c| acc.join(c))
        }
    }

    /// The realm-gateway flags this config means (paths resolved against `root`).
    pub fn gateway_args(&self, root: &Path) -> Vec<String> {
        let mut a = vec![
            format!("--db={}", self.path(root, "db").display()),
            format!("--bind={}", self.get("bind")),
            format!("--port={}", self.get("port")),
            format!("--fields={}", self.get("fields")),
            format!("--copies={}", self.get("copies")),
            format!("--field-port={}", self.get("field_port")),
            format!("--monsters={}", self.get("monsters")),
            format!("--threads={}", self.get("threads")),
            format!("--seed={}", self.get("seed")),
        ];
        if !self.get("public_host").is_empty() {
            a.push(format!("--public-host={}", self.get("public_host")));
        }
        if self.num("admin_port") > 0 {
            a.push(format!("--admin-port={}", self.get("admin_port")));
        }
        if self.yes("dev_login") {
            a.push("--dev-login".into());
        }
        a
    }
}

/// The shipped `ops.conf`: every setting, its default and its explanation.
pub fn template() -> String {
    let mut t = String::from("# Horde & Hearth host config. Every setting is here with its default; delete none, change what you need.\n# Relative paths are inside the host folder. Lines are `key = value`. Restart the realm after a change.\n");
    for st in SETTINGS {
        t.push_str(&format!("\n# {}\n{} = {}\n", st.doc, st.key, st.default));
    }
    t
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_template_parses_to_the_defaults() {
        let c = Conf::parse(&template()).unwrap();
        for st in SETTINGS {
            assert_eq!(c.get(st.key), st.default);
        }
    }

    #[test]
    fn bad_files_are_refused() {
        assert!(Conf::parse("nonsense = 1").unwrap_err().contains("unknown setting"));
        assert!(Conf::parse("port = abc").unwrap_err().contains("whole number"));
        assert!(Conf::parse("port 7700").is_err());
        let c = Conf::parse("# c\nport = 9000\n").unwrap();
        assert_eq!(c.num("port"), 9000);
        let db = Path::new("/r").join("data").join("realm.db");
        assert!(c.gateway_args(Path::new("/r")).contains(&format!("--db={}", db.display())), "{:?}", c.gateway_args(Path::new("/r")));
    }

    #[test]
    fn keys_are_unique() {
        let mut k: Vec<&str> = SETTINGS.iter().map(|s| s.key).collect();
        k.sort();
        k.dedup();
        assert_eq!(k.len(), SETTINGS.len());
    }
}
