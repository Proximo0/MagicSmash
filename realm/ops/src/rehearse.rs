//! The rehearsal (`realm-ops rehearse`, the station word `ops`, and the end-to-end test): on a scratch folder,
//! make a store with play in it, back it up on the clock's code path while writes go on, wreck the live file,
//! restore, drill, and run a release, a rollback and the schema-downgrade refusal. One line out, an error on any
//! step that does not do what it says.

use crate::{backup, release};
use realm_store::{Cmd, Meta, SqliteStore, Store};
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering::Relaxed};

fn ensure(c: bool, what: &str) -> Result<(), String> {
    if c { Ok(()) } else { Err(format!("rehearsal failed: {what}")) }
}

/// Adds `n` accounts with a hero each. Request ids start at `from` and must not repeat.
pub fn play(store: &SqliteStore, from: u64, n: u64) -> Result<(), String> {
    for i in from..from + n {
        let now = 1_700_000_000_000 + i as i64;
        let id = store.account_by_dev_name(Meta::system(1 << 50 | i as u128 * 2, now), &format!("rehearsal-{i}")).map_err(|e| e.to_string())?;
        store
            .run(Meta::new(1 << 50 | (i as u128 * 2 + 1), id, now), Cmd::HeroCreate { account: id, name: format!("Hero{i}"), race: 0, class: 1, look: 0, self_found: false })
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

fn fake_release(dir: &Path, version: &str, schema: usize) -> Result<(), String> {
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    std::fs::write(dir.join(release::exe("realm-gateway")), format!("gateway {version}")).map_err(|e| e.to_string())?;
    release::write_release(dir, &release::Release { version: version.into(), schema }).map_err(|e| e.to_string())
}

pub fn rehearse(dir: &Path, now_ms: i64) -> Result<String, String> {
    let _ = std::fs::remove_dir_all(dir);
    let (data, backups) = (dir.join("data"), dir.join("backups"));
    std::fs::create_dir_all(&data).map_err(|e| e.to_string())?;
    let db = data.join("realm.db");
    let store = Arc::new(SqliteStore::open(&db).map_err(|e| e.to_string())?);
    std::fs::write(format!("{}.secret", db.display()), "12345").map_err(|e| e.to_string())?;
    play(&store, 0, 40)?;

    // Backups while writes go on: a writer thread keeps adding heroes through the first one.
    let stop = Arc::new(AtomicBool::new(false));
    let w = {
        let (s, stop) = (store.clone(), stop.clone());
        std::thread::spawn(move || {
            let mut i = 1000;
            while !stop.load(Relaxed) {
                if play(&s, i, 1).is_err() {
                    break;
                }
                i += 1;
            }
        })
    };
    let first = backup::backup_now(&db, &backups, 3, 0, now_ms);
    stop.store(true, Relaxed);
    let _ = w.join();
    first?;
    for k in 1..=4 {
        play(&store, 100 * k, 5)?;
        backup::backup_now(&db, &backups, 3, 0, now_ms + k as i64 * 3_600_000)?;
    }
    let all = backup::list(&backups);
    ensure(all.len() == 3, &format!("retention kept {} backups, wanted 3", all.len()))?;
    ensure(backups.join(format!("{}.secret", all[0].1.file_name().unwrap().to_string_lossy())).exists(), "the side file travels with its backup")?;
    let newest = all.last().unwrap().1.clone();
    let (_, want, _) = backup::check(&newest)?;

    // Wreck the live store and put it back.
    store.close();
    drop(store);
    std::fs::write(&db, vec![0xABu8; 16384]).map_err(|e| e.to_string())?;
    for suffix in ["-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{suffix}", db.display()));
    }
    ensure(backup::check(&db).is_err(), "the wrecked file should fail its check")?;
    let got = backup::restore(&newest, &db, now_ms + 10 * 3_600_000)?;
    ensure(got == want, "restored digest equals the backup's")?;
    let (_, again, _) = backup::check(&db)?;
    ensure(again == want, "the live store verifies after restore")?;
    ensure(data.join("realm.db.before-restore-".to_string() + &crate::time::stamp(now_ms + 10 * 3_600_000)).exists(), "the wrecked file is set aside, not deleted")?;
    let drilled = backup::drill(&backups, &dir.join("scratch"), now_ms + 11 * 3_600_000)?;

    // Release, rollback, and the refusals.
    let root = dir.join("host");
    std::fs::create_dir_all(root.join("releases")).map_err(|e| e.to_string())?;
    let s = release::built_schema();
    let (r1, r2, old) = (dir.join("in/v1"), dir.join("in/v2"), dir.join("in/old"));
    fake_release(&r1, "v1", s)?;
    fake_release(&r2, "v2", s)?;
    fake_release(&old, "ancient", s - 1)?;
    release::install(&root, &r1)?;
    release::install(&root, &r2)?;
    ensure(release::install(&root, &r2).is_err(), "a version is never overwritten")?;
    release::install(&root, &old)?;
    release::switch(&root, "v1", &db, &backups, now_ms)?;
    release::switch(&root, "v2", &db, &backups, now_ms + 1000)?;
    ensure(release::current(&root).as_deref() == Some("v2"), "switched to v2")?;
    let refused = release::switch(&root, "ancient", &db, &backups, now_ms + 2000);
    ensure(refused.as_ref().is_err_and(|e| e.contains("refused")), "a schema downgrade is refused")?;
    ensure(release::current(&root).as_deref() == Some("v2"), "a refused switch changes nothing")?;
    release::rollback(&root, &db, &backups, false, false, now_ms + 3000)?;
    ensure(release::current(&root).as_deref() == Some("v1"), "rolled back to v1")?;
    let (_, after, _) = backup::check(&db)?;
    ensure(after == want, "the store came through switch and rollback untouched")?;
    Ok(format!("OPS ok backups=3 restored_digest={want:016x} {drilled} release=v1->v2->v1 downgrade=refused"))
}

#[cfg(test)]
mod tests {
    #[test]
    fn the_rehearsal_passes() {
        let dir = std::env::temp_dir().join(format!("realm-ops-rehearse-{}", std::process::id()));
        let line = super::rehearse(&dir, 1_700_000_000_000).expect("rehearsal");
        assert!(line.starts_with("OPS ok "), "{line}");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
