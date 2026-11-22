//! The host's one long-running program: starts the current release's gateway from `ops.conf`, keeps it up, and
//! tells somebody when it dies (alarm `host-death`: a log line and the hook). `running` holds the supervisor's pid
//! while it lives (restores refuse while it exists); `stop` and `restart` are files the CLI drops, so the same
//! three commands work from a .cmd, a .ps1, systemd or a hand. A killed gateway loses nothing banked (the store
//! commits before it answers), so stop is a kill: the standard library has no graceful signal.

use crate::alarm::Alarms;
use crate::config::Conf;
use crate::{log, metrics, release, time};
use std::fs::OpenOptions;
use std::path::Path;
use std::process::{Child, Command};
use std::sync::atomic::Ordering::Relaxed;
use std::time::{Duration, Instant};

pub fn start_child(root: &Path, conf_path: &Path, conf: &Conf) -> Result<Child, String> {
    let cur = release::current(root).ok_or("no current release (install one and switch to it)")?;
    let exe = release::release_dir(root, &cur).join(release::exe("realm-gateway"));
    if !exe.exists() {
        return Err(format!("{} does not exist", exe.display()));
    }
    for d in ["data", "logs"] {
        let _ = std::fs::create_dir_all(root.join(d));
    }
    let console = OpenOptions::new().create(true).append(true).open(conf.path(root, "log_dir").join("console.log")).map_err(|e| format!("console.log: {e}"))?;
    let err = console.try_clone().map_err(|e| e.to_string())?;
    let mut args = conf.gateway_args(root);
    args.push(format!("--ops-conf={}", conf_path.display()));
    Command::new(&exe).args(&args).current_dir(root).stdout(console).stderr(err).spawn().map_err(|e| format!("start {}: {e}", exe.display()))
}

/// Runs until `stop` appears. Exit code 0 on a requested stop.
pub fn run(root: &Path) -> i32 {
    let conf_path = root.join("ops.conf");
    let conf = match Conf::load(&conf_path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("realm-ops: {e}");
            return 2;
        }
    };
    let _ = std::fs::create_dir_all(conf.path(root, "log_dir"));
    let _ = log::init_named(&conf.path(root, "log_dir"), "supervisor.log", conf.num("log_max_mb"), conf.num("log_keep") as usize);
    let (stop, restart, running) = (root.join("stop"), root.join("restart"), root.join("running"));
    let _ = std::fs::remove_file(&stop);
    let _ = std::fs::remove_file(&restart);
    if running.exists() {
        eprintln!("realm-ops: {} exists: a supervisor is running (or died hard; delete the file if so)", running.display());
        return 2;
    }
    let _ = std::fs::write(&running, format!("{}\n", std::process::id()));
    let mut alarms = Alarms::new(conf.get("alarm_hook"), conf.num("alarm_cooldown_secs"));
    let mut backoff = 1u64;
    let code = 'outer: loop {
        let mut child = match start_child(root, &conf_path, &conf) {
            Ok(c) => c,
            Err(e) => {
                alarms.raise("host-death", &format!("cannot start the gateway: {e}"), time::now_ms());
                if wait_or_stop(&stop, Duration::from_secs(backoff)) {
                    break 'outer 1;
                }
                backoff = (backoff * 2).min(30);
                continue;
            }
        };
        let started = Instant::now();
        log::info("gateway_started", &[("pid", child.id().to_string()), ("release", release::current(root).unwrap_or_default())]);
        loop {
            std::thread::sleep(Duration::from_millis(250));
            if stop.exists() {
                let _ = child.kill();
                let _ = child.wait();
                log::info("gateway_stopped", &[("why", "stop requested".into())]);
                break 'outer 0;
            }
            if restart.exists() {
                let _ = std::fs::remove_file(&restart);
                let _ = child.kill();
                let _ = child.wait();
                log::info("gateway_restart", &[("release", release::current(root).unwrap_or_default())]);
                backoff = 1;
                continue 'outer;
            }
            if let Ok(Some(st)) = child.try_wait() {
                metrics::REG.errors.fetch_add(1, Relaxed);
                alarms.raise("host-death", &format!("the gateway exited ({st}); restarting in {backoff} s"), time::now_ms());
                if started.elapsed() > Duration::from_secs(60) {
                    backoff = 1;
                }
                if wait_or_stop(&stop, Duration::from_secs(backoff)) {
                    break 'outer 0;
                }
                backoff = (backoff * 2).min(30);
                continue 'outer;
            }
        }
    };
    let _ = std::fs::remove_file(&stop);
    let _ = std::fs::remove_file(&running);
    code
}

fn wait_or_stop(stop: &Path, d: Duration) -> bool {
    let t = Instant::now();
    while t.elapsed() < d {
        if stop.exists() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    false
}
