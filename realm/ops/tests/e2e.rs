//! The proof (job O1): a release, a rollback and a restore, end to end, through the real `realm-ops` program on a
//! temp folder; plus the supervisor keeping a gateway up and raising the host-death alarm (Unix: the stand-in
//! gateway is a shell script). Runs on Linux in CI and on Windows (everything but the supervisor).

use realm_ops::{backup, release, rehearse};
use realm_store::SqliteStore;
use std::path::{Path, PathBuf};
use std::process::Command;

fn ops(root: &Path, args: &[&str]) -> (bool, String) {
    let o = Command::new(env!("CARGO_BIN_EXE_realm-ops")).args(args).arg(format!("--root={}", root.display())).output().expect("run realm-ops");
    let text = format!("{}{}", String::from_utf8_lossy(&o.stdout), String::from_utf8_lossy(&o.stderr));
    (o.status.success(), text.trim().to_string())
}

fn ok(root: &Path, args: &[&str]) -> String {
    let (good, t) = ops(root, args);
    assert!(good, "realm-ops {args:?} failed: {t}");
    t
}

fn temp(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("realm-ops-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// A folder of "built programs": the real realm-ops, and stand-ins for the gateway and the server.
fn bins(dir: &Path) -> PathBuf {
    let b = dir.join("bins");
    std::fs::create_dir_all(&b).unwrap();
    for n in ["realm-ops", "realm-gateway", "realm-server"] {
        std::fs::copy(env!("CARGO_BIN_EXE_realm-ops"), b.join(release::exe(n))).unwrap();
    }
    b
}

fn digest(db: &Path) -> u64 {
    backup::check(db).expect("the store verifies").1
}

#[test]
fn a_release_a_rollback_and_a_restore_end_to_end() {
    let d = temp("e2e");
    let b = bins(&d);
    let host = d.join("host");
    let host_files = Path::new(env!("CARGO_MANIFEST_DIR")).join("host");

    // The first install: a whole host folder with its scripts and a config that parses.
    let t = ok(&host, &["package", &format!("--bins={}", b.display()), &format!("--out={}", host.display()), "--version=v1", &format!("--host={}", host_files.display())]);
    assert!(t.contains("package ok version=v1"), "{t}");
    for f in ["ops.conf", "start.cmd", "start.ps1", "stop.cmd", "stop.ps1", "realm.service", "start.sh", "current"] {
        assert!(host.join(f).exists(), "{f} is in the host package");
    }
    assert!(realm_ops::config::Conf::load(&host.join("ops.conf")).is_ok());
    assert_eq!(release::current(&host).as_deref(), Some("v1"));

    // A store with play in it, backed up through the CLI.
    let db = host.join("data/realm.db");
    {
        let s = SqliteStore::open(&db).unwrap();
        rehearse::play(&s, 0, 30).unwrap();
    }
    let t = ok(&host, &["backup"]);
    assert!(t.starts_with("backup ok "), "{t}");
    let before = digest(&db);
    assert!(ok(&host, &["backups"]).starts_with("1 backups"));

    // RELEASE: a second build, installed beside the first, switched to; the store is never touched.
    let r2 = d.join("rel-v2");
    ok(&host, &["package", &format!("--bins={}", b.display()), &format!("--out={}", r2.display()), "--version=v2"]);
    assert!(ok(&host, &["install", &r2.display().to_string()]).contains("installed v2"));
    assert!(ops(&host, &["install", &r2.display().to_string()]).1.contains("already installed"), "a version is never overwritten");
    let t = ok(&host, &["switch", "v2"]);
    assert!(t.contains("current is now v2"), "{t}");
    assert_eq!(release::current(&host).as_deref(), Some("v2"));
    assert!(ok(&host, &["releases"]).contains("v2 schema="));
    assert_eq!(digest(&db), before, "the store is untouched by a switch");
    assert!(host.join("backups/pre-switch").exists(), "a switch takes a pre-switch backup");

    // Play goes on under v2 (the store changes), then ROLLBACK: the pointer goes back, the store keeps the play.
    {
        let s = SqliteStore::open(&db).unwrap();
        rehearse::play(&s, 500, 3).unwrap();
    }
    let after_play = digest(&db);
    let t = ok(&host, &["rollback"]);
    assert!(t.contains("current is now v1"), "{t}");
    assert_eq!(release::current(&host).as_deref(), Some("v1"));
    assert_eq!(digest(&db), after_play, "a rollback keeps the store");
    assert_eq!(release::pointer(&host, "previous").as_deref(), Some("v2"));

    // The schema guard: a release older than the store's schema is refused, nothing changes.
    let old = d.join("rel-old");
    ok(&host, &["package", &format!("--bins={}", b.display()), &format!("--out={}", old.display()), "--version=old"]);
    release::write_release(&old, &release::Release { version: "old".into(), schema: release::built_schema() - 1 }).unwrap();
    ok(&host, &["install", &old.display().to_string()]);
    let (good, t) = ops(&host, &["switch", "old"]);
    assert!(!good && t.contains("refused"), "{t}");
    assert_eq!(release::current(&host).as_deref(), Some("v1"));
    // A newer schema is fine (the new program migrates the store when it starts).
    let newer = d.join("rel-newer");
    ok(&host, &["package", &format!("--bins={}", b.display()), &format!("--out={}", newer.display()), "--version=newer"]);
    release::write_release(&newer, &release::Release { version: "newer".into(), schema: release::built_schema() + 1 }).unwrap();
    ok(&host, &["install", &newer.display().to_string()]);
    ok(&host, &["switch", "newer"]);

    // RESTORE: the store is wrecked, the realm is "running" (refused), then stopped (restored from the newest backup).
    let want = backup::check(&backup::list(&host.join("backups")).pop().unwrap().1).unwrap().1;
    for suffix in ["", "-wal", "-shm"] {
        let p = PathBuf::from(format!("{}{suffix}", db.display()));
        if suffix.is_empty() {
            std::fs::write(&p, vec![0xCDu8; 20_000]).unwrap();
        } else {
            let _ = std::fs::remove_file(p);
        }
    }
    assert!(backup::check(&db).is_err());
    std::fs::write(host.join("running"), "1").unwrap();
    let (good, t) = ops(&host, &["restore"]);
    assert!(!good && t.contains("running"), "{t}");
    std::fs::remove_file(host.join("running")).unwrap();
    let t = ok(&host, &["restore"]);
    assert!(t.starts_with("restore ok"), "{t}");
    assert_eq!(digest(&db), want, "the restored store is the backup");
    assert!(std::fs::read_dir(host.join("data")).unwrap().flatten().any(|e| e.file_name().to_string_lossy().contains("before-restore")), "the wrecked file is set aside");
    let t = ok(&host, &["drill"]);
    assert!(t.starts_with("drill ok "), "{t}");

    // The one-line rehearsal the station runs.
    let t = ok(&host, &["rehearse", &format!("--dir={}", d.join("rehearsal").display())]);
    assert!(t.starts_with("OPS ok "), "{t}");
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_rollback_over_a_migrated_store_needs_the_pre_switch_backup() {
    let d = temp("migrated");
    let b = bins(&d);
    let host = d.join("host");
    ok(&host, &["package", &format!("--bins={}", b.display()), &format!("--out={}", host.display()), "--version=v1", &format!("--host={}", Path::new(env!("CARGO_MANIFEST_DIR")).join("host").display())]);
    let db = host.join("data/realm.db");
    // v1 is the build before the newest schema step: its store is one step behind this build's.
    let n = release::built_schema();
    {
        let c = rusqlite::Connection::open(&db).unwrap();
        c.execute_batch("PRAGMA journal_mode = WAL;").unwrap();
        for step in &realm_store::schema::STEPS[..n - 1] {
            c.execute_batch(step).unwrap();
        }
    }
    assert_eq!(release::store_schema(&db).unwrap(), Some(n - 1));
    release::write_release(&host.join("releases/v1"), &release::Release { version: "v1".into(), schema: n - 1 }).unwrap();
    let r2 = d.join("rel-v2");
    ok(&host, &["package", &format!("--bins={}", b.display()), &format!("--out={}", r2.display()), "--version=v2"]);
    ok(&host, &["install", &r2.display().to_string()]);
    // The switch is allowed (a newer release) and backs the old store up first.
    ok(&host, &["switch", "v2"]);
    let pre = backup::check(&backup::list(&host.join("backups/pre-switch")).pop().unwrap().1).unwrap();
    assert_eq!(pre.2, (n - 1) as i64, "the pre-switch backup is at the old schema");
    // v2 runs: opening the store migrates it, and play goes on.
    {
        let s = SqliteStore::open(&db).unwrap();
        rehearse::play(&s, 100, 2).unwrap();
    }
    assert_eq!(release::store_schema(&db).unwrap(), Some(n));
    let (good, t) = ops(&host, &["rollback"]);
    assert!(!good && t.contains("restore-pre-switch"), "a plain rollback over a migrated store is refused: {t}");
    assert_eq!(release::current(&host).as_deref(), Some("v2"));
    // The realm is "running": the explicit way back refuses; stopped, it restores the old store and then switches.
    std::fs::write(host.join("running"), "1").unwrap();
    assert!(!ops(&host, &["rollback", "--restore-pre-switch"]).0);
    std::fs::remove_file(host.join("running")).unwrap();
    let t = ok(&host, &["rollback", "--restore-pre-switch"]);
    assert!(t.contains("current is now v1"), "{t}");
    assert_eq!(release::store_schema(&db).unwrap(), Some(n - 1), "the pre-switch store is back");
    let _ = std::fs::remove_dir_all(&d);
}

#[cfg(unix)]
#[test]
fn the_supervisor_keeps_the_gateway_up_and_alarms_when_it_dies() {
    use std::os::unix::fs::PermissionsExt;
    let d = temp("super");
    let b = bins(&d);
    let host = d.join("host");
    ok(&host, &["package", &format!("--bins={}", b.display()), &format!("--out={}", host.display()), "--version=v1", &format!("--host={}", Path::new(env!("CARGO_MANIFEST_DIR")).join("host").display())]);
    // The stand-in gateway: the first run dies at once, later ones stay up until asked to stop (the file
    // `gateway.stop` in the host folder, its working folder), as the real one does. It records each start and stop.
    let gw = host.join("releases/v1/realm-gateway");
    std::fs::write(&gw, format!("#!/bin/sh\necho start >> {0}/starts.txt\nif [ $(wc -l < {0}/starts.txt) -lt 2 ]; then exit 3; fi\nwhile [ ! -f gateway.stop ]; do sleep 0.1; done\necho stop >> {0}/stops.txt\nexit 0\n", host.display())).unwrap();
    std::fs::set_permissions(&gw, std::fs::Permissions::from_mode(0o755)).unwrap();
    let hook = host.join("hook.sh");
    std::fs::write(&hook, format!("#!/bin/sh\necho \"$1|$2\" >> {}/alarms.txt\n", host.display())).unwrap();
    std::fs::set_permissions(&hook, std::fs::Permissions::from_mode(0o755)).unwrap();
    let conf = std::fs::read_to_string(host.join("ops.conf")).unwrap().replace("alarm_hook = \n", &format!("alarm_hook = {}\n", hook.display()));
    std::fs::write(host.join("ops.conf"), conf).unwrap();

    let mut sup = Command::new(env!("CARGO_BIN_EXE_realm-ops")).args(["run", &format!("--root={}", host.display())]).spawn().unwrap();
    let t0 = std::time::Instant::now();
    let starts = || std::fs::read_to_string(host.join("starts.txt")).map_or(0, |t| t.lines().count());
    while starts() < 2 && t0.elapsed().as_secs() < 20 {
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    assert_eq!(starts(), 2, "the dead gateway was started again");
    assert!(host.join("running").exists());
    std::thread::sleep(std::time::Duration::from_millis(500));
    let alarms = std::fs::read_to_string(host.join("alarms.txt")).unwrap_or_default();
    assert!(alarms.starts_with("host-death|"), "the hook heard of the death: {alarms:?}");
    // A second supervisor is refused; restart relaunches; stop ends it all.
    let (good, said) = ops(&host, &["stop", "--nothing"]);
    assert!(good && said.contains("stopped in"), "{said}");
    assert!(!host.join("running").exists(), "the stop returns once the supervisor has ended");
    assert_eq!(std::fs::read_to_string(host.join("stops.txt")).unwrap_or_default().lines().count(), 1, "the gateway was asked, not killed");
    let st = sup.wait().unwrap();
    assert!(st.success(), "the supervisor ends on stop");
    assert!(!host.join("running").exists());

    // A gateway that does not stop when asked is killed after the grace, and the stop says so and fails.
    std::fs::write(&gw, format!("#!/bin/sh\necho start >> {0}/starts.txt\nexec sleep 120\n", host.display())).unwrap();
    let mut sup = Command::new(env!("CARGO_BIN_EXE_realm-ops")).args(["run", &format!("--root={}", host.display())]).spawn().unwrap();
    let t0 = std::time::Instant::now();
    while starts() < 3 && t0.elapsed().as_secs() < 20 {
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    assert_eq!(starts(), 3);
    let t = std::time::Instant::now();
    let (good, said) = ops(&host, &["stop"]);
    assert!(!good && said.contains("was killed"), "a forced stop fails and says why: {said}");
    assert!(t.elapsed() >= realm_ops::supervise::STOP_GRACE, "killed only after the grace");
    assert!(sup.wait().unwrap().success());
    assert!(!host.join("running").exists());
    let _ = std::fs::remove_dir_all(&d);
}
