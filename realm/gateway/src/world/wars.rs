//! Guild wars in the field hosts (job R3b, `docs/realm/pvp.md`): the bridge between the gateway's social (where a
//! war is declared and accepted) and the core's `Field::declare_war` on every copy of the field.
//!
//! - Arming (world thread, every step): each accepted war of a field's current or next tide (`Social::wars_for`) is
//!   sent to every open copy of that field that has not had it (`HostCmd::War`). The host puts it in the next tick's
//!   record, so followers arm it at the same tick. A copy that opens during the war is armed at its next step, and
//!   since the tide is running the core begins the war there at once.
//! - The result (applier thread): every armed copy reports its held altar ticks (`HostMsg::War`): at the tide's end,
//!   or when it stops during the war (a copy merged into another). The war's result is the sum over its copies; it
//!   goes to `Social::war_result` when every armed copy has reported or is gone, or `WAR_FINISH_GRACE_TICKS` after
//!   the tide's end with what has come in (a copy that never saw the war, say armed as its tide ended, reports
//!   nothing).

use crate::gateway::Gateway;
use realm_core::pvp::WAR_DRAW;
use realm_core::tables::TIDE_LEN;
use realm_core::tide_start;
use realm_server::host::HostCmd;
use realm_server::lockstep::WarArm;
use std::collections::{HashMap, HashSet};
use std::sync::atomic::Ordering;

/// A war is settled with what its copies reported this long after its tide ended (realm ticks: 20 s), within
/// social's own `WAR_RESULT_GRACE_TICKS` (1 min), after which it would end as a draw.
pub const WAR_FINISH_GRACE_TICKS: u64 = 20 * realm_core::TICK_HZ as u64;

/// One war across the copies of its field.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct WarTally {
    pub field: u8,
    pub tide: u32,
    /// Copies (host ids) it was armed on, and those that reported or are gone.
    pub hosts: HashSet<u32>,
    pub done: HashSet<u32>,
    /// Held altar ticks of each side, summed over the copies.
    pub held: [u64; 2],
}

/// The bridge's memory (in memory only: a restart re-arms from social at the next step; what the old copies held is
/// gone with them).
#[derive(Debug, Default)]
pub struct Wars {
    pub tallies: HashMap<u64, WarTally>,
    /// Wars settled here (social is told once).
    pub settled: HashSet<u64>,
}

/// The index of the tide of `field` that is running at `now` or comes next.
pub fn tide_now_or_next(field: u8, now: u64) -> u32 {
    let mut n = 0u32;
    while tide_start(field, n) + TIDE_LEN as u64 <= now {
        n += 1;
    }
    n
}

/// The winning side of summed held ticks (0, 1, or `WAR_DRAW`).
pub fn winner_of(held: [u64; 2]) -> u8 {
    match held[0].cmp(&held[1]) {
        std::cmp::Ordering::Greater => 0,
        std::cmp::Ordering::Less => 1,
        std::cmp::Ordering::Equal => WAR_DRAW,
    }
}

impl Gateway {
    /// Arms the accepted wars of each field's running or next tide on every open copy that lacks them, and settles
    /// wars whose copies are all done or whose grace has passed.
    pub(crate) fn arm_wars(&self, fields: &[u8]) {
        let now = self.world.clock.now();
        for &field in fields {
            let tide = tide_now_or_next(field, now);
            let wars = self.social.wars_for(field, tide);
            if wars.is_empty() {
                continue;
            }
            let hosts = self.hosts.lock().unwrap();
            let mut w = self.world.wars.lock().unwrap();
            for (id, a, b) in wars {
                if w.settled.contains(&id) {
                    continue;
                }
                let t = w.tallies.entry(id).or_insert_with(|| WarTally { field, tide, ..WarTally::default() });
                for h in hosts.iter().filter(|h| h.vault.is_none() && h.field == field && !h.stopping && !h.handle.status.ended.load(Ordering::Relaxed)) {
                    // A closing copy is armed too: the heroes still in it fight until they are moved.
                    if t.hosts.insert(h.id) {
                        let _ = h.handle.cmds.send(HostCmd::War(WarArm { id, a, b, tide }));
                    }
                }
            }
        }
        let due: Vec<u64> = {
            let w = self.world.wars.lock().unwrap();
            w.tallies.iter().filter(|(_, t)| tide_start(t.field, t.tide) + TIDE_LEN as u64 + WAR_FINISH_GRACE_TICKS <= now).map(|(id, _)| *id).collect()
        };
        for id in due {
            self.settle_war(id);
        }
    }

    /// A copy's held ticks of a war (`HostMsg::War`): added to the war's sum; settled when every armed copy is done.
    pub(crate) fn on_war(&self, host: u32, war: u64, held: [u32; 2], _over: bool) {
        let ready = {
            let mut w = self.world.wars.lock().unwrap();
            if w.settled.contains(&war) {
                return;
            }
            let t = w.tallies.entry(war).or_default();
            t.hosts.insert(host);
            if !t.done.insert(host) {
                return;
            }
            t.held[0] += held[0] as u64;
            t.held[1] += held[1] as u64;
            t.done.is_superset(&t.hosts)
        };
        if ready {
            self.settle_war(war);
        }
    }

    /// A copy has closed or died: it reports nothing more, so the wars waiting on it may be settled.
    pub(crate) fn wars_host_gone(&self, host: u32) {
        let now = self.world.clock.now();
        let ready: Vec<u64> = {
            let mut w = self.world.wars.lock().unwrap();
            w.tallies
                .iter_mut()
                .filter(|(_, t)| t.hosts.contains(&host))
                .filter_map(|(id, t)| {
                    t.done.insert(host);
                    // Only a war whose tide has begun is settled by a copy going: one armed for a later tide waits
                    // for the copies that will fight it.
                    (t.done.is_superset(&t.hosts) && tide_start(t.field, t.tide) <= now).then_some(*id)
                })
                .collect()
        };
        for id in ready {
            self.settle_war(id);
        }
    }

    /// The war's result to social: the side that held more over all its copies wins.
    fn settle_war(&self, war: u64) {
        let t = {
            let mut w = self.world.wars.lock().unwrap();
            let Some(t) = w.tallies.remove(&war) else { return };
            w.settled.insert(war);
            t
        };
        let held = [t.held[0].min(u32::MAX as u64) as u32, t.held[1].min(u32::MAX as u64) as u32];
        self.social.war_result(war, winner_of(t.held), held);
    }

    /// The tally of a war (tests).
    pub fn war_tally(&self, war: u64) -> Option<WarTally> {
        self.world.wars.lock().unwrap().tallies.get(&war).cloned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gateway::Config;
    use realm_server::realm_clock::RealmClock;
    use realm_store::SqliteStore;
    use std::sync::Arc;
    use std::time::{Duration, Instant};

    fn until(what: &str, mut ok: impl FnMut() -> bool) {
        let t = Instant::now();
        while !ok() {
            assert!(t.elapsed() < Duration::from_secs(30), "timed out waiting for {what}");
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    fn counts(gw: &Gateway, host: u32) -> realm_server::host::HostCounts {
        gw.hosts.lock().unwrap().iter().find(|h| h.id == host).map(|h| h.handle.status.counts.lock().unwrap().clone()).unwrap_or_default()
    }

    /// The bridge end to end on real hosts: a war accepted in social is armed on both copies of its field before
    /// the tide and begins in both; a copy opened during the war is armed and begins it at once; that copy closing
    /// into another (a merge) reports what it held; at the tide's end the copies' sums reach social, once.
    #[test]
    fn a_war_is_armed_on_every_copy_survives_a_merge_and_its_result_reaches_social() {
        let db = std::env::temp_dir().join(format!("realm-wars-bridge-{}.db", std::process::id()));
        for s in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{}{s}", db.display()));
        }
        let clock = RealmClock::manual(0);
        let mut cfg = Config { dev_login: true, secret: 5, ..Config::default() };
        cfg.world.clock = Some(clock.clone());
        cfg.world.monsters = 200;
        cfg.world.tick_us = 5_000;
        let gw = Gateway::start(Arc::new(SqliteStore::open(&db).unwrap()), cfg);
        let field = 2u8;
        let (_, h1) = gw.open_copy(field, 0).unwrap();
        let (_, h2) = gw.open_copy(field, 0).unwrap();
        const WAR: u64 = 41;
        {
            let mut g = gw.social.inner.lock().unwrap();
            g.commit("wdecl", &[&WAR.to_string(), "7", "8", &field.to_string(), "0"]);
            g.commit("wacc", &[&WAR.to_string()]);
        }
        assert_eq!(gw.social.wars_for(field, 0), vec![(WAR, 7, 8)]);
        until("both copies armed", || gw.war_tally(WAR).is_some_and(|t| t.hosts == HashSet::from([h1, h2])));
        let start = tide_start(field, 0);
        clock.set(start + 5);
        until("the war begins in both copies", || counts(&gw, h1).wars_begun == 1 && counts(&gw, h2).wars_begun == 1);
        // A copy that opens during the war is armed and begins it at once.
        let (_, h3) = gw.open_copy(field, 0).unwrap();
        until("the new copy begins the war", || counts(&gw, h3).wars_begun == 1);
        assert!(gw.war_tally(WAR).unwrap().hosts.contains(&h3));
        // It closes into the first copy (a merge): what it held is reported before it closes; the war goes on.
        gw.hosts.lock().unwrap().iter_mut().find(|h| h.id == h3).unwrap().closing = Some(h1);
        until("the merged copy reported", || gw.war_tally(WAR).is_some_and(|t| t.done.contains(&h3)));
        assert!(gw.social.wars_for(field, 0) == vec![(WAR, 7, 8)], "not settled while two copies fight");
        // The tide ends: both copies end the war, the sums go to social once.
        clock.set(start + TIDE_LEN as u64 + 2);
        until("the result reaches social", || gw.social.wars_for(field, 0).is_empty());
        until("both copies ended it", || counts(&gw, h1).wars_ended == 1 && counts(&gw, h2).wars_ended == 1);
        assert!(gw.world.wars.lock().unwrap().settled.contains(&WAR) && gw.war_tally(WAR).is_none());
        gw.shutdown();
        for s in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{}{s}", db.display()));
        }
    }

    #[test]
    fn the_copies_held_ticks_are_summed_and_settled_when_the_last_reports() {
        let db = std::env::temp_dir().join(format!("realm-wars-sum-{}.db", std::process::id()));
        let _ = std::fs::remove_file(&db);
        let gw = Gateway::start(Arc::new(SqliteStore::open(&db).unwrap()), Config { dev_login: true, secret: 5, ..Config::default() });
        {
            let mut g = gw.social.inner.lock().unwrap();
            g.commit("wdecl", &["5", "7", "8", "1", "0"]);
            g.commit("wacc", &["5"]);
        }
        gw.world.wars.lock().unwrap().tallies.insert(5, WarTally { field: 1, tide: 0, hosts: HashSet::from([10, 11]), ..WarTally::default() });
        gw.on_war(10, 5, [30, 0], false);
        gw.on_war(10, 5, [30, 0], true);
        assert_eq!(gw.war_tally(5).unwrap().held, [30, 0], "a copy counts once");
        assert_eq!(gw.social.wars_for(1, 0).len(), 1, "waiting for the other copy");
        gw.on_war(11, 5, [0, 45], true);
        assert!(gw.war_tally(5).is_none() && gw.social.wars_for(1, 0).is_empty(), "settled: side 1 held more in all");
        gw.on_war(11, 5, [0, 45], true);
        assert!(gw.war_tally(5).is_none(), "a late report changes nothing");
        gw.shutdown();
        let _ = std::fs::remove_file(&db);
    }

    #[test]
    fn the_tide_now_or_next_is_the_running_one_then_the_next() {
        let f = 2;
        assert_eq!(tide_now_or_next(f, 0), 0);
        let s = tide_start(f, 3);
        assert_eq!(tide_now_or_next(f, s), 3, "running");
        assert_eq!(tide_now_or_next(f, s + TIDE_LEN as u64 - 1), 3, "still running");
        assert_eq!(tide_now_or_next(f, s + TIDE_LEN as u64), 4, "over: the next");
        assert_eq!(winner_of([5, 3]), 0);
        assert_eq!(winner_of([5, 7]), 1);
        assert_eq!(winner_of([4, 4]), WAR_DRAW);
    }
}
