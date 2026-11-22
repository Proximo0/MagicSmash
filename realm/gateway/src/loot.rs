//! The gateway's side of loot (`realm-loot`, rules section 9): the per-outing haul and roll gate, the rolls
//! for a field host's kills, the first kill of each boss a hero has made (the loot crate leaves that memory to
//! this job), and chests and caches for the events the core will add (tides and bosses).
//!
//! Where drops go: a roll the haul does not hold (RARE and better, cards, pages, keys, runes) is written to the
//! store at once (`deliver`); the rest (COMMON and UNCOMMON items, materials) waits in the hero's `Haul` and is
//! banked with her coin at the same flush (a BANK, the gate, a waystone, a kick, a stop) or halved by a fall.
//! A disconnect halves it once, as a fall does, and banks what is left.

use realm_loot::rng::{mix, Rng};
use realm_loot::{Haul, RollGate};
use std::collections::HashSet;
use std::io::Write;
use std::path::{Path, PathBuf};

/// One outing's loot state for one hero.
pub struct TicketLoot {
    pub haul: Haul,
    pub gate: RollGate,
    /// The account's drops percent, read from the store at the first roll.
    pub pct: Option<u8>,
    /// Counts the deliveries, so each has its own request id.
    pub n: u32,
}

impl TicketLoot {
    pub fn new() -> TicketLoot {
        TicketLoot { haul: Haul::new(), gate: RollGate::new(), pct: None, n: 0 }
    }
}

impl Default for TicketLoot {
    fn default() -> Self {
        TicketLoot::new()
    }
}

/// The request id of delivery `n` of an outing: no flush id (the ticket and a small seq, with the attempt in
/// bits 40 and up) can equal it, since bit 31 is set.
pub fn delivery_id(ticket: u64, n: u32) -> u128 {
    ((ticket as u128) << 64) | 0x8000_0000u128 | n as u128
}

/// The stream a fall of the haul uses: the server's secret, the ticket and the flush number.
pub fn fall_rng(secret: u64, ticket: u64, seq: u32) -> Rng {
    Rng::new(mix(secret ^ ticket, 0xFA11_0000 | seq as u64))
}

/// Which hero has made her first kill of which boss. The first kill of a boss gives its page, so a hero must
/// not get it twice: the set is kept in a file beside the database (one `hero boss` line each, flushed at
/// once), because the store has no record of it. Without a path it lives in memory only.
pub struct FirstKills {
    path: Option<PathBuf>,
    seen: HashSet<(i64, u8)>,
}

impl FirstKills {
    pub fn open(path: Option<&Path>) -> FirstKills {
        let mut seen = HashSet::new();
        if let Some(p) = path {
            if let Ok(text) = std::fs::read_to_string(p) {
                for line in text.lines() {
                    let mut it = line.split_whitespace();
                    if let (Some(h), Some(b)) = (it.next().and_then(|v| v.parse().ok()), it.next().and_then(|v| v.parse().ok())) {
                        seen.insert((h, b));
                    }
                }
            }
        }
        FirstKills { path: path.map(Path::to_path_buf), seen }
    }

    /// True the first time a hero kills a boss (and remembers it), false after.
    pub fn first(&mut self, hero: i64, boss: u8) -> bool {
        if !self.seen.insert((hero, boss)) {
            return false;
        }
        if let Some(p) = &self.path {
            if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) {
                let _ = writeln!(f, "{hero} {boss}");
                let _ = f.sync_data();
            }
        }
        true
    }
}

/// What a REWARD event gives (the core will have them with tides and bosses): the loot crate's `Source` with
/// the first-kill fact filled in by the gateway.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RewardKind {
    Tide { field: u8, level: u8 },
    Boss { boss: u8, level: u8 },
    World { level: u8, top: bool },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_first_kill_is_remembered_across_a_restart() {
        let path = std::env::temp_dir().join(format!("realm-firstkills-{}.txt", std::process::id()));
        let _ = std::fs::remove_file(&path);
        {
            let mut f = FirstKills::open(Some(&path));
            assert!(f.first(7, 2));
            assert!(!f.first(7, 2), "the second kill is not a first");
            assert!(f.first(7, 3));
            assert!(f.first(8, 2), "another hero's first");
        }
        let mut again = FirstKills::open(Some(&path));
        assert!(!again.first(7, 2) && !again.first(7, 3) && !again.first(8, 2));
        assert!(again.first(9, 0));
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn deliveries_and_flushes_never_share_a_request_id() {
        let t = 0xABCD_EF01_2345u64;
        for n in 0..1000u32 {
            for seq in 0..1000u32 {
                for attempt in 0..8u128 {
                    assert_ne!(delivery_id(t, n), ((t as u128) << 64) | seq as u128 | (attempt << 40));
                }
            }
        }
    }
}
