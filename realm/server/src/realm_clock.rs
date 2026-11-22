//! The realm's one clock (rules section 8): tides, altars, field bosses and the world boss of every field and every
//! copy run from it. The gateway owns it; each field host reads it every tick and, when its field's clock has
//! drifted from it, puts the realm's value into that tick's record (`TickRec::clock`), so the host and every
//! follower set it at the same tick and the hash stays equal.
//!
//! The clock is in ticks (20 a second). On a live realm it runs at the wall's pace from an epoch the gateway keeps
//! beside its store (`realm.db.epoch`), so a restart does not move a tide. A test realm may run it faster
//! (`speed` clock ticks for each 50 ms) to live a compressed week, or set it by hand (`manual`).

use realm_core::TICK_HZ;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Instant;

/// A field copy's clock may be this many ticks off the realm's before a record corrects it (half a second): a host
/// that sleeps a little long catches up by itself, and a record without a clock costs a byte less.
pub const CLOCK_SLACK: u64 = 10;

#[derive(Debug)]
enum Src {
    Wall { start: Instant, base: u64, speed: u64 },
    Manual(AtomicU64),
}

/// A handle to the realm's clock: cheap to clone, read from any thread.
#[derive(Clone, Debug)]
pub struct RealmClock(Arc<Src>);

impl RealmClock {
    /// A clock that reads `base` now and moves `speed` ticks every 50 ms of the wall (1: the live realm).
    pub fn wall(base: u64, speed: u32) -> RealmClock {
        RealmClock(Arc::new(Src::Wall { start: Instant::now(), base, speed: speed.max(1) as u64 }))
    }

    /// A clock that moves only when `set` is called (tests).
    pub fn manual(at: u64) -> RealmClock {
        RealmClock(Arc::new(Src::Manual(AtomicU64::new(at))))
    }

    /// The realm clock now, in ticks.
    pub fn now(&self) -> u64 {
        match &*self.0 {
            Src::Wall { start, base, speed } => base + start.elapsed().as_millis() as u64 * TICK_HZ as u64 / 1000 * speed,
            Src::Manual(v) => v.load(Ordering::Relaxed),
        }
    }

    /// Sets a manual clock (a wall clock ignores it).
    pub fn set(&self, ticks: u64) {
        if let Src::Manual(v) = &*self.0 {
            v.store(ticks, Ordering::Relaxed);
        }
    }

    /// Clock ticks per field tick (1 on a live realm).
    pub fn speed(&self) -> u64 {
        match &*self.0 {
            Src::Wall { speed, .. } => *speed,
            Src::Manual(_) => 1,
        }
    }
}

/// What a host puts in the next record so that its field's clock reads `realm` after the step: `None` while the
/// field (whose step adds one) is within `CLOCK_SLACK` of it.
pub fn clock_fix(field_clock: u64, realm: u64) -> Option<u64> {
    let next = field_clock + 1;
    (next.abs_diff(realm) > CLOCK_SLACK).then(|| realm.saturating_sub(1))
}

/// The realm's clock from an epoch kept in a file (unix milliseconds, written the first time), at `speed`.
pub fn clock_from_epoch(path: &std::path::Path, speed: u32) -> RealmClock {
    let now_ms = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_millis() as u64);
    let epoch = match std::fs::read_to_string(path).ok().and_then(|t| t.trim().parse::<u64>().ok()) {
        Some(e) if e <= now_ms => e,
        _ => {
            let _ = std::fs::write(path, format!("{now_ms}\n"));
            now_ms
        }
    };
    RealmClock::wall((now_ms - epoch) * TICK_HZ as u64 / 1000 * speed.max(1) as u64, speed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_field_within_the_slack_is_left_alone_and_one_beyond_it_is_set() {
        assert_eq!(clock_fix(99, 100), None);
        assert_eq!(clock_fix(99 - CLOCK_SLACK, 100), None);
        assert_eq!(clock_fix(98 - CLOCK_SLACK, 100), Some(99));
        assert_eq!(clock_fix(500, 100), Some(99), "a field ahead is set back");
        assert_eq!(clock_fix(0, 0), None);
    }

    #[test]
    fn a_manual_clock_moves_only_when_set_and_a_wall_clock_moves_at_its_speed() {
        let m = RealmClock::manual(7);
        assert_eq!(m.now(), 7);
        m.set(70);
        assert_eq!(m.clone().now(), 70);
        let w = RealmClock::wall(1_000, 100);
        std::thread::sleep(std::time::Duration::from_millis(60));
        assert!(w.now() >= 1_000 + 100, "60 ms at speed 100 is at least one 50 ms step: {}", w.now());
        assert_eq!(w.speed(), 100);
    }

    #[test]
    fn the_epoch_is_kept_so_a_restart_reads_on() {
        let p = std::env::temp_dir().join(format!("realm-epoch-{}.txt", std::process::id()));
        let _ = std::fs::remove_file(&p);
        let a = clock_from_epoch(&p, 1).now();
        let back = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as u64 - 3_600_000;
        std::fs::write(&p, format!("{back}\n")).unwrap();
        let b = clock_from_epoch(&p, 1).now();
        assert!(a < 5, "a new realm starts at 0: {a}");
        assert!((71_990..=72_100).contains(&b), "an hour later the clock reads an hour: {b}");
        let _ = std::fs::remove_file(&p);
    }
}
