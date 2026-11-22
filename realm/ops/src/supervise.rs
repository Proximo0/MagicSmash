//! The host's one long-running program: starts the current release's gateway from `ops.conf`, keeps it up, and
//! tells somebody when it dies (alarm `host-death`: a log line and the hook). `running` holds the supervisor's pid
//! while it lives (restores refuse while it exists); `stop` and `restart` are files the CLI drops, so the same
//! three commands work from a .cmd, a .ps1, systemd or a hand. On stop and restart the supervisor asks the gateway
//! to stop (the file `runtime::GATEWAY_STOP`, as the standard library has no graceful signal): it banks every hero
//! in a field and exits. Only a gateway that has not exited within `STOP_GRACE` is killed (logged
//! `gateway_stop_forced`); a killed gateway loses the unbanked hauls, nothing banked (the store commits before it
//! answers).

use crate::alarm::Alarms;
use crate::config::Conf;
use crate::{log, metrics, release, time};
use std::fs::OpenOptions;
use std::path::Path;
use std::process::{Child, Command};
use std::sync::atomic::Ordering::Relaxed;
use std::time::{Duration, Instant};

/// How long a gateway asked to stop has to bank its fields and exit before it is killed. `realm-ops stop` waits a
/// little longer than this for the supervisor (systemd's `TimeoutStopSec` in realm.service is above both).
pub const STOP_GRACE: Duration = Duration::from_secs(20);

/// The supervisor's last word on a requested stop, in the host folder: `clean` (the gateway banked its fields and
/// exited) or `forced` (killed after `STOP_GRACE`: heroes in fields lost their unbanked hauls).
pub const STOPPED: &str = "stopped";

/// Asks the gateway to stop and waits up to `grace` for it to exit; kills it after that. True: it stopped by itself.
pub fn stop_child(root: &Path, child: &mut Child, grace: Duration) -> bool {
    let ask = root.join(crate::runtime::GATEWAY_STOP);
    let _ = std::fs::write(&ask, "");
    let t = Instant::now();
    let clean = loop {
        if let Ok(Some(_)) = child.try_wait() {
            break true;
        }
        if t.elapsed() >= grace {
            let _ = child.kill();
            let _ = child.wait();
            break false;
        }
        std::thread::sleep(Duration::from_millis(100));
    };
    let _ = std::fs::remove_file(&ask);
    if clean {
        log::info("gateway_stop_clean", &[("ms", t.elapsed().as_millis().to_string())]);
    } else {
        log::warn("gateway_stop_forced", &[("after_ms", t.elapsed().as_millis().to_string())]);
    }
    clean
}

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
    // A stop request left over (a supervisor that died mid-stop) must not stop the new gateway.
    let _ = std::fs::remove_file(root.join(crate::runtime::GATEWAY_STOP));
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
                    // No gateway was running: the stop killed nothing.
                    let _ = std::fs::write(root.join(STOPPED), "clean\n");
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
                let clean = stop_child(root, &mut child, STOP_GRACE);
                // `realm-ops stop` reads this once `running` is gone, and fails on a forced stop.
                let _ = std::fs::write(root.join(STOPPED), if clean { "clean\n" } else { "forced\n" });
                log::info("gateway_stopped", &[("why", "stop requested".into()), ("clean", clean.to_string())]);
                break 'outer 0;
            }
            if restart.exists() {
                let _ = std::fs::remove_file(&restart);
                stop_child(root, &mut child, STOP_GRACE);
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
                    // No gateway was running: the stop killed nothing.
                    let _ = std::fs::write(root.join(STOPPED), "clean\n");
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
