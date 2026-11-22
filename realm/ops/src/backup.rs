//! Backups on a clock, and the restore drill. A backup is SQLite's online backup (`realm_store::backup_file`: writers
//! keep going), written under a `.part` name, then opened again and verified (the store's full `verify`: every
//! invariant, the ledger replayed) before it gets its real name; a backup that does not verify is deleted and is an
//! error, never "kept anyway". Every file the realm keeps beside its store (`SIDES`: the `.secret` tickets key,
//! `.admin` token, `.social` log, `.bosskills`, `.switches`, the `.homes` plot registry, the realm clock's `.epoch`
//! and the operator's `.social.words`) is copied beside it. Retention: the newest `keep`, plus the first backup of each of the last
//! `daily_keep` days. `restore` and `drill` prove the way back.
//! (`backup_copy` is a store addition: the copy without its verify, for stores a schema behind.)

use crate::time::{civil, stamp};
use realm_store::sqlite::open_reader;
use realm_store::read;
use std::path::{Path, PathBuf};

pub use crate::sides::{side, SIDES};

#[derive(Clone, Debug)]
pub struct Made {
    pub file: PathBuf,
    pub bytes: u64,
    pub items: i64,
    pub stacks: i64,
    pub ledger_rows: i64,
    pub digest: u64,
}

fn name(stamp: &str) -> String {
    format!("realm-{stamp}.db")
}

/// Opens a database read-only and checks it. At this build's schema: the store's full verify (every invariant, the
/// ledger replayed) and the stats digest. At an older schema (a store a release behind, as a pre-switch backup is
/// meant to be): the full verify knows only the newest tables, so it is SQLite's `quick_check` and a digest of 0; the
/// older release's own `realm-store verify` does the full one. Returns (report, digest, schema).
pub fn check(path: &Path) -> Result<(realm_store::VerifyReport, u64, i64), String> {
    let c = open_reader(path).map_err(|e| format!("open {}: {e}", path.display()))?;
    let schema = realm_store::schema::version(&c).map_err(|e| format!("{} is not a realm store: {e}", path.display()))?;
    if (schema as usize) < crate::release::built_schema() {
        let q: String = c.query_row("PRAGMA quick_check", [], |r| r.get(0)).map_err(|e| format!("quick_check {}: {e}", path.display()))?;
        if q != "ok" {
            return Err(format!("{} fails quick_check: {q}", path.display()));
        }
        return Ok((realm_store::VerifyReport { items: 0, stacks: 0, ledger_rows: 0, requests: 0, problems: vec![] }, 0, schema));
    }
    let rep = read::verify(&c).map_err(|e| format!("verify {}: {e}", path.display()))?;
    if !rep.ok() {
        return Err(format!("{} fails verify: {}", path.display(), rep.problems.iter().take(3).cloned().collect::<Vec<_>>().join("; ")));
    }
    let st = read::stats(&c).map_err(|e| format!("stats {}: {e}", path.display()))?;
    Ok((rep, st.digest, st.schema_version))
}

/// One backup of `db` into `dir` named for `at_ms`, verified, then `prune`d.
pub fn backup_now(db: &Path, dir: &Path, keep: usize, daily_keep: usize, at_ms: i64) -> Result<Made, String> {
    std::fs::create_dir_all(dir).map_err(|e| format!("create {}: {e}", dir.display()))?;
    let stamp = stamp(at_ms);
    let part = dir.join(format!("realm-{stamp}.part"));
    let dest = dir.join(name(&stamp));
    realm_store::backup_copy(db, &part).map_err(|e| {
        let _ = std::fs::remove_file(&part);
        format!("backup {}: {e}", db.display())
    })?;
    // The independent check: open the copy fresh and run verify, the same call the restore will trust.
    let (rep, digest, _) = check(&part).inspect_err(|_| {
        let _ = std::fs::remove_file(&part);
    })?;
    for suffix in ["-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{suffix}", part.display()));
    }
    std::fs::rename(&part, &dest).map_err(|e| format!("rename backup: {e}"))?;
    for ext in SIDES {
        let s = side(db, ext);
        if s.exists() {
            std::fs::copy(&s, dir.join(format!("{}.{ext}", name(&stamp)))).map_err(|e| format!("copy {}: {e}", s.display()))?;
        }
    }
    let bytes = std::fs::metadata(&dest).map_or(0, |m| m.len());
    prune(dir, keep, daily_keep);
    Ok(Made { file: dest, bytes, items: rep.items, stacks: rep.stacks, ledger_rows: rep.ledger_rows, digest })
}

/// The backups in `dir`, oldest first: (stamp, path).
pub fn list(dir: &Path) -> Vec<(String, PathBuf)> {
    let mut v: Vec<(String, PathBuf)> = std::fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| {
            let n = e.file_name().to_string_lossy().into_owned();
            let s = n.strip_prefix("realm-")?.strip_suffix(".db")?.to_string();
            (s.len() == 15 && s.as_bytes()[8] == b'-').then(|| (s, e.path()))
        })
        .collect();
    v.sort();
    v
}

/// Keeps the newest `keep` and the first of each of the newest `daily_keep` days; deletes the rest (with their side files).
pub fn prune(dir: &Path, keep: usize, daily_keep: usize) -> usize {
    let all = list(dir);
    let mut keepers: Vec<bool> = vec![false; all.len()];
    for k in all.len().saturating_sub(keep.max(1))..all.len() {
        keepers[k] = true;
    }
    let newest_days: std::collections::BTreeSet<&str> = all.iter().map(|a| &a.0[..8]).collect::<std::collections::BTreeSet<_>>().into_iter().rev().take(daily_keep).collect();
    for (i, (s, _)) in all.iter().enumerate() {
        if newest_days.contains(&s[..8]) && (i == 0 || all[i - 1].0[..8] != s[..8]) {
            keepers[i] = true;
        }
    }
    let mut gone = 0;
    for (i, (s, p)) in all.iter().enumerate() {
        if !keepers[i] {
            let _ = std::fs::remove_file(p);
            for ext in SIDES {
                let _ = std::fs::remove_file(dir.join(format!("{}.{ext}", name(s))));
            }
            gone += 1;
        }
    }
    gone
}

/// Restores `from` (a backup file) over `db`: verifies it first, sets the current store and its WAL files aside as
/// `<db>.before-restore-<stamp>` (never deleted: undoing a bad restore is a rename), copies the backup and its side
/// files in, and verifies the result. The gateway must be stopped. Returns the restored stats digest.
pub fn restore(from: &Path, db: &Path, at_ms: i64) -> Result<u64, String> {
    let (_, want, _) = check(from)?;
    let aside = stamp(at_ms);
    for suffix in ["", "-wal", "-shm"] {
        let cur = PathBuf::from(format!("{}{suffix}", db.display()));
        if cur.exists() {
            std::fs::rename(&cur, PathBuf::from(format!("{}.before-restore-{aside}{suffix}", db.display()))).map_err(|e| format!("set aside {}: {e}", cur.display()))?;
        }
    }
    realm_store::backup_copy(from, db).map_err(|e| format!("restore: {e}"))?;
    let (_, got, _) = check(db)?;
    if got != want {
        return Err(format!("restored digest {got:x} differs from the backup's {want:x}"));
    }
    let fname = from.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    for ext in SIDES {
        let s = from.with_file_name(format!("{fname}.{ext}"));
        if s.exists() {
            let _ = std::fs::copy(&s, side(db, ext));
        }
    }
    Ok(got)
}

/// The drill: restore the newest backup in `dir` to a scratch file (not the live store), verify it, and compare it
/// with the backup it came from. Proves the files on disk are a way back. Returns a one-line summary.
pub fn drill(dir: &Path, scratch: &Path, at_ms: i64) -> Result<String, String> {
    let all = list(dir);
    let Some((s, newest)) = all.last() else { return Err(format!("no backups in {}", dir.display())) };
    std::fs::create_dir_all(scratch).map_err(|e| format!("create {}: {e}", scratch.display()))?;
    let target = scratch.join("drill.db");
    for suffix in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{suffix}", target.display()));
    }
    let digest = restore(newest, &target, at_ms)?;
    let (rep, _, schema) = check(&target)?;
    let (y, m, d, ..) = civil(at_ms);
    Ok(format!("drill ok backup={s} schema={schema} items={} stacks={} ledger={} digest={digest:016x} on {y:04}-{m:02}-{d:02}", rep.items, rep.stacks, rep.ledger_rows))
}

/// How old the newest backup is (ms), by its name; None with no backups.
pub fn newest_age_ms(dir: &Path, now_ms: i64) -> Option<i64> {
    let (s, _) = list(dir).pop()?;
    let p = |a: usize, b: usize| s[a..b].parse::<i64>().ok();
    let days = days_from_civil(p(0, 4)?, p(4, 6)?, p(6, 8)?);
    let secs = days * 86_400 + p(9, 11)? * 3600 + p(11, 13)? * 60 + p(13, 15)?;
    Some(now_ms - secs * 1000)
}

fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y.rem_euclid(400);
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn days_and_names_agree_with_the_clock() {
        let at = 1_700_000_000_000;
        let dir = std::env::temp_dir().join(format!("realm-ops-age-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join(name(&stamp(at))), b"x").unwrap();
        assert_eq!(newest_age_ms(&dir, at + 5000), Some(5000));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn prune_keeps_the_newest_and_one_a_day() {
        let dir = std::env::temp_dir().join(format!("realm-ops-prune-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let day = 86_400_000i64;
        let t0 = 1_700_000_000_000 - 1_700_000_000_000 % day; // midnight
        // Four days, six backups a day, four hours apart.
        for d in 0..4 {
            for h in 0..6 {
                let f = dir.join(name(&stamp(t0 + d * day + h * 4 * 3_600_000 + 1000)));
                std::fs::write(&f, b"x").unwrap();
                std::fs::write(format!("{}.secret", f.display()), b"s").unwrap();
            }
        }
        let gone = prune(&dir, 4, 2);
        let left: Vec<String> = list(&dir).into_iter().map(|x| x.0).collect();
        // The newest 4 (day 3, hours 8..20) plus the first backup of each of the 2 newest days (day 2 and day 3, 00:00).
        assert_eq!(left.len(), 6, "{left:?}");
        assert_eq!(gone, 24 - 6);
        assert!(left[0].ends_with("000001"), "the first backup of day 2 stays: {left:?}");
        assert!(!dir.join(format!("{}.secret", name(&stamp(t0 + 1000)))).exists(), "side files go with their backup");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
