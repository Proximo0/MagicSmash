//! The training yard's dummy. A hero strikes it as often as her weapon allows (the server keeps the pace: a strike
//! sent sooner than `every` less a tenth is refused); each strike does what her weapon does to a target with no
//! armour (`weapon damage x weapon level % x MIGHT %`, the same factors the field's `power` uses), and the dummy
//! says her damage per second over the last ten seconds. A round ends after `IDLE_MS` without a strike. The best
//! full round (at least `MIN_BEST_MS` long, so one lucky blow is not a record) goes on the yard's board.

use std::collections::VecDeque;

pub const WINDOW_MS: i64 = 10_000;
pub const IDLE_MS: i64 = 5_000;
pub const MIN_BEST_MS: i64 = 5_000;
/// A strike may come this much (percent of the weapon's interval) early, for jitter on the line.
pub const EARLY_PCT: i64 = 90;
pub const BOARD_KEEP: usize = 20;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Dummy {
    strikes: VecDeque<(i64, u32)>,
    start: i64,
    last: i64,
    every: i64,
    pub total: u64,
    pub count: u32,
    pub best: u32,
}

#[derive(Debug, PartialEq, Eq)]
pub struct Hit {
    pub damage: u32,
    pub total: u64,
    pub dps: u32,
    pub count: u32,
    pub best: u32,
}

impl Dummy {
    /// A strike at `now` of `damage`, her weapon swinging every `every_ms`. None: too soon.
    pub fn strike(&mut self, now: i64, damage: u32, every_ms: i64) -> Option<Hit> {
        if self.count > 0 && now - self.last < every_ms * EARLY_PCT / 100 {
            return None;
        }
        if self.count == 0 || now - self.last > IDLE_MS {
            *self = Dummy { best: self.best, start: now, ..Dummy::default() };
        }
        self.last = now;
        self.every = every_ms;
        self.count += 1;
        self.total += damage as u64;
        self.strikes.push_back((now, damage));
        while self.strikes.front().is_some_and(|&(t, _)| now - t >= WINDOW_MS) {
            self.strikes.pop_front();
        }
        let dps = self.dps(now);
        if now - self.start >= MIN_BEST_MS {
            self.best = self.best.max(dps);
        }
        Some(Hit { damage, total: self.total, dps, count: self.count, best: self.best })
    }

    /// Damage per second: what the window holds over the round's age plus one swing (the first blow starts a swing
    /// that has not ended), a second at least and ten at most.
    pub fn dps(&self, now: i64) -> u32 {
        let span = (now - self.start + self.every).clamp(1000, WINDOW_MS);
        let sum: u64 = self.strikes.iter().filter(|&&(t, _)| now - t < WINDOW_MS).map(|&(_, d)| d as u64).sum();
        (sum * 1000 / span as u64).min(u32::MAX as u64) as u32
    }
}

/// What one strike of a weapon does: base x weapon level percent x (100 + MIGHT percent x MIGHT points) / 10,000.
pub fn strike_damage(weapon_damage: u32, weapon_pct: u64, might_pct: u64, might_points: u64) -> u32 {
    (weapon_damage as u64 * weapon_pct / 100 * (100 + might_pct * might_points) / 100).min(u32::MAX as u64) as u32
}

/// The best rounds, highest first, one line a hero.
#[derive(Default)]
pub struct Board {
    rows: Vec<(i64, String, u8, u32)>,
}

impl Board {
    pub fn note(&mut self, hero: i64, name: &str, class: u8, dps: u32) {
        if let Some(r) = self.rows.iter_mut().find(|r| r.0 == hero) {
            if dps <= r.3 {
                return;
            }
            r.3 = dps;
        } else {
            self.rows.push((hero, name.into(), class, dps));
        }
        self.rows.sort_by(|a, b| b.3.cmp(&a.3).then(a.0.cmp(&b.0)));
        self.rows.truncate(BOARD_KEEP);
    }
    pub fn top(&self) -> Vec<(String, u8, u32)> {
        self.rows.iter().map(|r| (r.1.clone(), r.2, r.3)).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dps_is_the_window_over_the_round_and_pace_is_kept() {
        let mut d = Dummy::default();
        // 100 damage every 500 ms for 12 s: 200 dps once the round is ten seconds old.
        let mut last = None;
        for k in 0..=24 {
            last = d.strike(k * 500, 100, 500);
        }
        let h = last.unwrap();
        assert_eq!((h.dps, h.count, h.total), (200, 25, 2500), "20 blows in the window over 10 s");
        assert_eq!(d.strike(12_000 + 100, 100, 500), None, "too soon");
        assert_eq!(d.count, 25);
        assert_eq!(d.best, 200);
        // A pause longer than IDLE_MS starts a new round; the best is kept.
        let h = d.strike(30_000, 100, 500).unwrap();
        assert_eq!((h.count, h.total, h.best), (1, 100, 200));
        assert_eq!(h.dps, 100, "a round counts at least a second");
    }

    #[test]
    fn one_blow_is_no_record_and_the_board_keeps_each_heros_best() {
        let mut d = Dummy::default();
        let h = d.strike(0, 5000, 500).unwrap();
        assert_eq!((h.dps, h.best), (5000, 0));
        let mut b = Board::default();
        b.note(1, "Ann", 1, 100);
        b.note(2, "Bob", 2, 300);
        b.note(1, "Ann", 1, 50);
        b.note(1, "Ann", 1, 200);
        assert_eq!(b.top(), vec![("Bob".to_string(), 2, 300), ("Ann".to_string(), 1, 200)]);
        for k in 0..40 {
            b.note(10 + k, "x", 0, k as u32);
        }
        assert_eq!(b.top().len(), BOARD_KEEP);
    }

    #[test]
    fn a_strike_is_weapon_level_and_might() {
        assert_eq!(strike_damage(10, 155, 2, 0), 15);
        assert_eq!(strike_damage(10, 200, 2, 50), 40);
    }
}
