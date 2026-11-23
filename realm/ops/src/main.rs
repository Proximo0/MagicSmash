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
  trace TARGET [--depth N] [--json]          TARGET: ACCOUNT, #ACCOUNT, hero:NAME|ID, item:ID: where its coin and
                            items came from and went
  plan ACCOUNT [--since T] [--origin FARM]   the clawback plan, changing nothing (T: 2026-11-20[T18:00], 7d, seq:N)
  clawback ACCOUNT --reason TEXT [--plan-file FILE] [--since T] [--origin FARM] [--yes]
  flag ACCOUNT lock|shadow|ban|clear --reason TEXT [--yes]
  wave FILE lock|shadow|ban|clear --reason TEXT [--yes]    one account per line
                            by hand only; without --yes nothing changes. Through the running realm's admin port, or
                            --db=FILE for a stopped realm or a backup copy (docs/realm/ops.md, Pulling the rug)
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

/// One command line to the running realm's admin console (loopback port, token in `<db>.admin`).
fn admin(root: &Path, line: &str) -> Result<String, String> {
    let c = load(root)?;
    let port = c.num("admin_port");
    if port == 0 {
        return Err("admin_port is 0 (off) in ops.conf".into());
    }
    let token = std::fs::read_to_string(realm_ops::sides::side(&c.path(root, "db"), realm_ops::sides::ADMIN)).map_err(|e| format!("admin token: {e}"))?;
    let mut s = std::net::TcpStream::connect(("127.0.0.1", port as u16)).map_err(|e| format!("the realm's admin port {port} does not answer: {e}"))?;
    std::io::Write::write_all(&mut s, format!("{}\tops\n{line}\n", token.trim()).as_bytes()).map_err(|e| e.to_string())?;
    let mut out = String::new();
    let _ = std::io::Read::read_to_string(&mut s, &mut out);
    if out.starts_with("error:") { Err(out.trim().to_string()) } else { Ok(out.trim().to_string()) }
}

/// trace, plan, clawback, flag, wave (`realm_ops::rug`): with `--db=FILE` on that store (a stopped realm or a
/// backup copy), else through the running realm's admin console. Files are read here and sent inline.
fn rug(args: &[String], root: &Path, now: i64) -> Result<String, String> {
    const VALUED: [&str; 7] = ["reason", "since", "origin", "plan-file", "depth", "db", "root"];
    let (mut pos, mut opts, mut flags) = (Vec::new(), Vec::<(String, String)>::new(), Vec::new());
    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.strip_prefix("--") {
            Some(o) => match o.split_once('=') {
                Some((k, v)) => opts.push((k.to_string(), v.to_string())),
                None if VALUED.contains(&o) => opts.push((o.to_string(), it.next().ok_or(format!("--{o} needs a value"))?.clone())),
                None => flags.push(o.to_string()),
            },
            None => pos.push(a.clone()),
        }
    }
    let opt = |k: &str| opts.iter().rev().find(|(n, _)| n == k).map(|(_, v)| v.clone());
    let mut words: Vec<String> = Vec::new();
    if pos[0] == "wave" {
        let (Some(file), Some(action)) = (pos.get(1), pos.get(2)) else { return Err("wave FILE lock|shadow|ban|clear --reason TEXT [--yes]".into()) };
        let text = std::fs::read_to_string(file).map_err(|e| format!("{file}: {e}"))?;
        words.extend(["wave".to_string(), action.clone(), format!("--lines={}", realm_ops::rug::wave_lines(&text))]);
    } else {
        words.extend(pos.iter().cloned());
    }
    if let Some(f) = opt("plan-file") {
        let text = std::fs::read_to_string(&f).map_err(|e| format!("{f}: {e}"))?;
        words.push(realm_ops::rug::plan_words(&realm_ops::rug::parse_plan(&text)?));
    }
    for k in ["since", "origin", "depth"] {
        if let Some(v) = opt(k) {
            words.push(format!("--{k}={v}"));
        }
    }
    words.extend(flags.iter().map(|f| format!("--{f}")));
    if let Some(r) = opt("reason") {
        words.push(format!("--reason={}", r.replace(['\n', '\r'], " ")));
    }
    let line = words.join(" ");
    let Some(db) = opt("db").map(PathBuf::from) else { return admin(root, &format!("rug {line}")) };
    if release::running(root) {
        if let Ok(c) = load(root) {
            let live = c.path(root, "db");
            if std::fs::canonicalize(&live).ok() == std::fs::canonicalize(&db).ok() {
                return Err("the realm is running on this store: leave out --db to go through its admin port".into());
            }
        }
    }
    if !db.exists() {
        return Err(format!("no store at {}", db.display()));
    }
    let store = realm_store::SqliteStore::open(&db).map_err(|e| format!("open {}: {e}", db.display()))?;
    let n = std::cell::Cell::new(0u128);
    let meta = || {
        n.set(n.get() + 1);
        realm_store::Meta::system(((now as u128) << 64) | (1 << 62) | (u128::from(std::process::id()) << 24) | n.get(), time::now_ms())
    };
    let op = std::env::var("USER").or_else(|_| std::env::var("USERNAME")).unwrap_or_else(|_| "ops".into());
    let r = realm_ops::rug::Rug { store: &store, meta: &meta, op: &op, now }.run(&line);
    store.close();
    r.map(|d| d.text)
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
            let said = root.join(supervise::STOPPED);
            let _ = std::fs::remove_file(&said);
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
            let secs = t.elapsed().as_secs_f64();
            match std::fs::read_to_string(&said).unwrap_or_default().trim() {
                "forced" => Err(format!(
                    "stopped in {secs:.1} s, but the gateway did not bank its fields and exit within {} s and was killed: heroes in fields lost their unbanked hauls (logs/supervisor.log, logs/realm.log)",
                    supervise::STOP_GRACE.as_secs()
                )),
                "clean" => Ok(format!("stopped in {secs:.1} s")),
                // A supervisor of an older release says nothing: it killed the gateway.
                _ => Err(format!("stopped in {secs:.1} s, but the supervisor did not say the gateway stopped cleanly (an older release kills it)")),
            }
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
            let words: Vec<&str> = args.iter().filter(|a| !a.starts_with("--")).map(|a| a.as_str()).collect();
            admin(&root, &words.join(" "))
        }
        "trace" | "plan" | "clawback" | "flag" | "wave" => rug(args, &root, now),
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
            let r = backup::restore(&from, &c.path(&root, "db"), now)?;
            let mut out = format!("restore ok from {} digest={:016x}", from.display(), r.digest);
            for n in &r.notes {
                out.push_str(&format!("\nNOTE {n}"));
            }
            Ok(out)
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
