//! Releases and rollback. The host folder (`root`) holds `releases/<version>/` (the programs of one build and its
//! `release.txt`), two pointer files `current` and `previous`, and the things no release owns: `data/` (the store),
//! `backups/`, `logs/`, `ops.conf`. Switching is writing two small files, so it never touches the store. Two rules:
//! the store's schema only goes up (a release whose newest schema step is older than the store's is refused: the
//! older program would run a database it cannot read), and a switch takes a verified backup of the store first, so
//! a bad release that migrated the store can be undone with `rollback --restore-pre-switch`.

use crate::backup;
use realm_store::schema;
use std::path::{Path, PathBuf};

/// The newest schema step this build knows (the store's `STEPS`).
pub fn built_schema() -> usize {
    schema::STEPS.len()
}

pub fn exe(name: &str) -> String {
    if cfg!(windows) { format!("{name}.exe") } else { name.to_string() }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Release {
    pub version: String,
    pub schema: usize,
}

pub fn read_release(dir: &Path) -> Result<Release, String> {
    let t = std::fs::read_to_string(dir.join("release.txt")).map_err(|e| format!("{}: {e}", dir.join("release.txt").display()))?;
    let get = |k: &str| t.lines().find_map(|l| l.strip_prefix(&format!("{k}=")).map(|v| v.trim().to_string()));
    let version = get("version").ok_or("release.txt has no version=")?;
    let schema = get("schema").and_then(|s| s.parse().ok()).ok_or("release.txt has no schema=N")?;
    if version.is_empty() || version.contains(['/', '\\', ' ']) || version.starts_with('.') {
        return Err(format!("bad version name {version:?}"));
    }
    Ok(Release { version, schema })
}

pub fn write_release(dir: &Path, r: &Release) -> std::io::Result<()> {
    std::fs::write(dir.join("release.txt"), format!("version={}\nschema={}\n", r.version, r.schema))
}

fn copy_dir(from: &Path, to: &Path) -> Result<(), String> {
    std::fs::create_dir_all(to).map_err(|e| format!("create {}: {e}", to.display()))?;
    for e in std::fs::read_dir(from).map_err(|e| format!("read {}: {e}", from.display()))?.flatten() {
        let (src, dst) = (e.path(), to.join(e.file_name()));
        if src.is_dir() {
            copy_dir(&src, &dst)?;
        } else {
            std::fs::copy(&src, &dst).map_err(|e| format!("copy {}: {e}", src.display()))?;
        }
    }
    Ok(())
}

/// Builds a release folder `out` from a folder of built programs (realm-gateway, realm-server, realm-ops,
/// realm-store; the first three are required).
pub fn make_release(bins: &Path, out: &Path, version: &str) -> Result<Release, String> {
    let r = Release { version: version.to_string(), schema: built_schema() };
    if version.is_empty() || version.contains(['/', '\\', ' ']) {
        return Err(format!("bad version name {version:?}"));
    }
    std::fs::create_dir_all(out).map_err(|e| format!("create {}: {e}", out.display()))?;
    for (n, need) in [("realm-gateway", true), ("realm-server", true), ("realm-ops", true), ("realm-store", false)] {
        let src = bins.join(exe(n));
        if src.exists() {
            std::fs::copy(&src, out.join(exe(n))).map_err(|e| format!("copy {}: {e}", src.display()))?;
        } else if need {
            return Err(format!("{} is missing", src.display()));
        }
    }
    write_release(out, &r).map_err(|e| e.to_string())?;
    Ok(r)
}

/// The first install: the whole host folder at `root` (config, scripts, folders, the release, `current` set).
pub fn make_host(bins: &Path, host_files: &Path, root: &Path, version: &str) -> Result<Release, String> {
    let r = make_release(bins, &root.join("releases").join(version), version)?;
    copy_dir(host_files, root)?;
    std::fs::write(root.join("ops.conf"), crate::config::template()).map_err(|e| e.to_string())?;
    for d in ["data", "backups", "logs"] {
        std::fs::create_dir_all(root.join(d)).map_err(|e| e.to_string())?;
    }
    write_pointer(root, "current", version)?;
    Ok(r)
}

fn write_pointer(root: &Path, name: &str, v: &str) -> Result<(), String> {
    let tmp = root.join(format!("{name}.tmp"));
    std::fs::write(&tmp, format!("{v}\n")).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, root.join(name)).map_err(|e| e.to_string())
}

pub fn pointer(root: &Path, name: &str) -> Option<String> {
    std::fs::read_to_string(root.join(name)).ok().map(|s| s.trim().to_string()).filter(|s| !s.is_empty())
}

pub fn current(root: &Path) -> Option<String> {
    pointer(root, "current")
}

pub fn release_dir(root: &Path, v: &str) -> PathBuf {
    root.join("releases").join(v)
}

pub fn list(root: &Path) -> Vec<Release> {
    let mut v: Vec<Release> = std::fs::read_dir(root.join("releases")).into_iter().flatten().flatten().filter_map(|e| read_release(&e.path()).ok()).collect();
    v.sort_by(|a, b| a.version.cmp(&b.version));
    v
}

/// Copies a release folder into `releases/<its version>`; an existing version is never overwritten.
pub fn install(root: &Path, from: &Path) -> Result<Release, String> {
    let r = read_release(from)?;
    if !from.join(exe("realm-gateway")).exists() {
        return Err(format!("{} has no {}", from.display(), exe("realm-gateway")));
    }
    let to = release_dir(root, &r.version);
    if to.exists() {
        return Err(format!("release {} is already installed (versions are never overwritten)", r.version));
    }
    let part = root.join("releases").join(format!(".installing-{}", r.version));
    let _ = std::fs::remove_dir_all(&part);
    copy_dir(from, &part)?;
    std::fs::rename(&part, &to).map_err(|e| format!("install {}: {e}", r.version))?;
    Ok(r)
}

/// The store's schema version, or None when there is no store yet.
pub fn store_schema(db: &Path) -> Result<Option<usize>, String> {
    if !db.exists() {
        return Ok(None);
    }
    let c = realm_store::sqlite::open_reader(db).map_err(|e| format!("open {}: {e}", db.display()))?;
    schema::version(&c).map(|v| Some(v as usize)).map_err(|e| format!("schema of {}: {e}", db.display()))
}

pub fn running(root: &Path) -> bool {
    root.join("running").exists()
}

/// Makes `version` the current release. Refuses an unknown version and a schema downgrade; takes a verified
/// pre-switch backup of the store; touches nothing else. The running gateway is not stopped: restart it.
pub fn switch(root: &Path, version: &str, db: &Path, backup_dir: &Path, at_ms: i64) -> Result<String, String> {
    let dir = release_dir(root, version);
    let rel = read_release(&dir).map_err(|e| format!("release {version} is not installed: {e}"))?;
    let cur = current(root);
    if let Some(have) = store_schema(db)? {
        if rel.schema < have {
            return Err(format!(
                "refused: the store is at schema {have} and release {version} knows only up to {}; a program cannot run a newer store. To go back anyway: stop the realm and run `rollback --restore-pre-switch` (restores the backup taken before the switch that migrated it, losing play since)",
                rel.schema
            ));
        }
        if cur.as_deref() != Some(version) {
            let pre = backup_dir.join("pre-switch");
            backup::backup_now(db, &pre, 3, 0, at_ms).map_err(|e| format!("pre-switch backup failed, nothing switched: {e}"))?;
        }
    }
    if cur.as_deref() == Some(version) {
        return Ok(format!("{version} is already current"));
    }
    if let Some(c) = &cur {
        write_pointer(root, "previous", c)?;
    }
    write_pointer(root, "current", version)?;
    Ok(format!("current is now {version} (was {}); restart the realm to run it", cur.as_deref().unwrap_or("none")))
}

/// Back to `previous`. With `restore_pre_switch` the store is also put back to the newest pre-switch backup
/// (the realm must be stopped, and play since that backup is lost); without it a store that has moved on to a newer
/// schema refuses the old release.
pub fn rollback(root: &Path, db: &Path, backup_dir: &Path, restore_pre_switch: bool, force: bool, at_ms: i64) -> Result<String, String> {
    let Some(prev) = pointer(root, "previous") else { return Err("there is no previous release to go back to".into()) };
    if restore_pre_switch {
        if running(root) && !force {
            return Err("the realm is running (stop it first, or --force if its `running` file is stale)".into());
        }
        let Some((_, newest)) = backup::list(&backup_dir.join("pre-switch")).pop() else { return Err("no pre-switch backup to restore".into()) };
        let r = backup::restore(&newest, db, at_ms)?;
        // The store is back at the older schema now, so the guard in `switch` passes.
        return switch(root, &prev, db, backup_dir, at_ms).map(|out| r.notes.iter().fold(out, |o, n| format!("{o}\nNOTE {n}")));
    }
    switch(root, &prev, db, backup_dir, at_ms)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn release_files_round_trip_and_reject_bad_names() {
        let dir = std::env::temp_dir().join(format!("realm-ops-rel-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        write_release(&dir, &Release { version: "v1".into(), schema: 3 }).unwrap();
        assert_eq!(read_release(&dir).unwrap(), Release { version: "v1".into(), schema: 3 });
        std::fs::write(dir.join("release.txt"), "version=../x\nschema=3\n").unwrap();
        assert!(read_release(&dir).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
