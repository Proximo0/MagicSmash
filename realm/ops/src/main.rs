//! realm-ops: the host's tool. `realm-ops help` lists the commands.

use realm_ops::config::{self, Conf};
use realm_ops::{backup, release, rehearse, runtime, supervise, time};
use std::net::SocketAddr;
use std::path::{Path, PathBuf};

const USAGE: &str = "realm-ops <command> [--root=DIR]      (--root defaults to the folder holding this program's releases, or .)
  run                       keep the realm up from ops.conf (the .cmd/.ps1/systemd entry point)
  stop | restart            ask the running supervisor (restart picks up a switched release)
  status                    the status page of the running realm (loopback metrics)
  kill WHAT | revive WHAT | switches   kill switches of the running realm (WHAT: login trade market field N all)
  backup                    one verified online backup now
  backups                   list backups
  restore [FILE] [--force]  stop the realm first; verify the backup (newest by default), set the live store
                            aside as .before-restore-STAMP, put the backup in, verify
  drill                     restore the newest backup to a scratch file and verify it (the realm keeps running)
  releases | install DIR | switch VERSION | rollback [--restore-pre-switch] [--force]
  package --bins=DIR --out=DIR --version=V [--host=DIR]
                            --host: a whole host folder (config, scripts, the release); without: just a release
  config-template           print ops.conf with every setting documented
  rehearse [--dir=DIR]      backup, wreck, restore, drill, release, rollback on a scratch folder (prints OPS ok ...)";

fn flag(args: &[String], name: &str) -> Option<String> {
    args.iter().find_map(|a| a.strip_prefix(&format!("--{name}=")).map(|s| s.to_string()))
}

fn has(args: &[String], name: &str) -> bool {
    args.iter().any(|a| a == &format!("--{name}"))
}

fn root_of(args: &[String]) -> PathBuf {
    if let Some(r) = flag(args, "root") {
        return PathBuf::from(r);
    }
    // <root>/releases/<v>/realm-ops: the root is three up.
    if let Some(r) = std::env::current_exe().ok().and_then(|e| e.parent()?.parent()?.parent().map(|p| p.to_path_buf())) {
        if r.join("ops.conf").exists() {
            return r;
        }
    }
    PathBuf::from(".")
}

fn load(root: &Path) -> Result<Conf, String> {
    Conf::load(&root.join("ops.conf"))
}

fn go(args: &[String]) -> Result<String, String> {
    let cmd = args.first().map(|s| s.as_str()).unwrap_or("help");
    let root = root_of(args);
    let now = time::now_ms();
    match cmd {
        "help" | "--help" | "-h" => Ok(USAGE.to_string()),
        "config-template" => Ok(config::template().trim_end().to_string()),
        "rehearse" => {
            let dir = flag(args, "dir").map(PathBuf::from).unwrap_or_else(|| std::env::temp_dir().join(format!("realm-ops-rehearse-{}", std::process::id())));
            let r = rehearse::rehearse(&dir, now);
            let _ = std::fs::remove_dir_all(&dir);
            r
        }
        "package" => {
            let bins = flag(args, "bins").ok_or("--bins=DIR")?;
            let out = flag(args, "out").ok_or("--out=DIR")?;
            let v = flag(args, "version").ok_or("--version=V")?;
            let r = match flag(args, "host") {
                Some(h) => release::make_host(Path::new(&bins), Path::new(&h), Path::new(&out), &v)?,
                None => release::make_release(Path::new(&bins), Path::new(&out), &v)?,
            };
            Ok(format!("package ok version={} schema={} at {out}", r.version, r.schema))
        }
        "run" => {
            let code = supervise::run(&root);
            std::process::exit(code);
        }
        "stop" | "restart" => {
            if !release::running(&root) {
                return Err(format!("no supervisor is running in {}", root.display()));
            }
            std::fs::write(root.join(cmd), "").map_err(|e| e.to_string())?;
            if cmd == "restart" {
                return Ok("restart requested".into());
            }
            // The stop returns when the supervisor has ended (its gateway banked and exited, or was killed after
            // the grace), so a service manager that kills what is left after this command kills nothing.
            let t = std::time::Instant::now();
            let bound = supervise::STOP_GRACE + std::time::Duration::from_secs(5);
            while release::running(&root) {
                if t.elapsed() > bound {
                    return Err(format!("stop requested, but the supervisor is still running after {} s", bound.as_secs()));
                }
                std::thread::sleep(std::time::Duration::from_millis(100));
            }
            Ok(format!("stopped in {:.1} s", t.elapsed().as_secs_f64()))
        }
        "status" => {
            let c = load(&root)?;
            let port = c.num("metrics_port") as u16;
            if port == 0 {
                return Err("metrics_port is 0 (off) in ops.conf".into());
            }
            runtime::fetch(SocketAddr::from(([127, 0, 0, 1], port)), "/status").map_err(|e| format!("the realm is not answering on 127.0.0.1:{port}: {e}"))
        }
        "kill" | "revive" | "switches" => {
            let c = load(&root)?;
            let port = c.num("admin_port");
            if port == 0 {
                return Err("admin_port is 0 (off) in ops.conf".into());
            }
            let token = std::fs::read_to_string(realm_ops::sides::side(&c.path(&root, "db"), realm_ops::sides::ADMIN)).map_err(|e| format!("admin token: {e}"))?;
            let mut s = std::net::TcpStream::connect(("127.0.0.1", port as u16)).map_err(|e| format!("the realm's admin port {port} does not answer: {e}"))?;
            let words: Vec<&str> = args.iter().filter(|a| !a.starts_with("--")).map(|a| a.as_str()).collect();
            std::io::Write::write_all(&mut s, format!("{}\tops\n{}\n", token.trim(), words.join(" ")).as_bytes()).map_err(|e| e.to_string())?;
            let mut out = String::new();
            let _ = std::io::Read::read_to_string(&mut s, &mut out);
            if out.starts_with("error:") { Err(out.trim().to_string()) } else { Ok(out.trim().to_string()) }
        }
        "backup" => {
            let c = load(&root)?;
            let m = backup::backup_now(&c.path(&root, "db"), &c.path(&root, "backup_dir"), c.num("backup_keep") as usize, c.num("backup_daily_keep") as usize, now)?;
            Ok(format!("backup ok {} bytes={} items={} stacks={} ledger={}", m.file.display(), m.bytes, m.items, m.stacks, m.ledger_rows))
        }
        "backups" => {
            let c = load(&root)?;
            let l = backup::list(&c.path(&root, "backup_dir"));
            Ok(format!("{} backups\n{}", l.len(), l.iter().map(|(s, p)| format!("{s}  {}", p.display())).collect::<Vec<_>>().join("\n")))
        }
        "restore" => {
            let c = load(&root)?;
            if release::running(&root) && !has(args, "force") {
                return Err("the realm is running: stop it first (or --force if the `running` file is stale)".into());
            }
            let from = match args.get(1).filter(|a| !a.starts_with("--")) {
                Some(f) => PathBuf::from(f),
                None => backup::list(&c.path(&root, "backup_dir")).pop().ok_or("no backups")?.1,
            };
            let d = backup::restore(&from, &c.path(&root, "db"), now)?;
            Ok(format!("restore ok from {} digest={d:016x}", from.display()))
        }
        "drill" => {
            let c = load(&root)?;
            backup::drill(&c.path(&root, "backup_dir"), &root.join("drill"), now)
        }
        "releases" => {
            let cur = release::current(&root);
            Ok(release::list(&root).iter().map(|r| format!("{} schema={}{}", r.version, r.schema, if cur.as_deref() == Some(&r.version) { "  <- current" } else { "" })).collect::<Vec<_>>().join("\n"))
        }
        "install" => release::install(&root, Path::new(args.get(1).ok_or("install DIR")?)).map(|r| format!("installed {} (schema {}); `switch {}` to use it", r.version, r.schema, r.version)),
        "switch" => {
            let c = load(&root)?;
            release::switch(&root, args.get(1).ok_or("switch VERSION")?, &c.path(&root, "db"), &c.path(&root, "backup_dir"), now)
        }
        "rollback" => {
            let c = load(&root)?;
            release::rollback(&root, &c.path(&root, "db"), &c.path(&root, "backup_dir"), has(args, "restore-pre-switch"), has(args, "force"), now)
        }
        other => Err(format!("unknown command {other:?}\n{USAGE}")),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match go(&args) {
        Ok(s) => println!("{s}"),
        Err(e) => {
            eprintln!("realm-ops: {e}");
            std::process::exit(1);
        }
    }
}
