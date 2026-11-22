//! Campfires. A hero sits at a fire (within `FIRE_REACH_PX` of one); if she stays seated for `SIT_MS` she is
//! RESTED for `RESTED_MS` more: `RESTED_XP_PCT` percent more class XP on what a field flush banks while it lasts.
//! Sitting again while rested only adds up to the cap (`RESTED_CAP_MS`), so a long sit is not a stockpile.
//! Standing up, walking away (more than `SEAT_DRIFT_PX` from the seat) or leaving the place ends the sit.

pub const SIT_MS: i64 = 60_000;
pub const RESTED_MS: i64 = 30 * 60_000;
pub const RESTED_CAP_MS: i64 = 60 * 60_000;
pub const RESTED_XP_PCT: u64 = 10;
pub const SEAT_DRIFT_PX: i32 = 40;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Rest {
    /// When she sat down and where (None: standing).
    pub sat: Option<(i64, (u16, u16))>,
    pub rested_until: i64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct View {
    pub sitting: bool,
    pub secs: u32,
    pub rested_ms: u32,
    pub pct: u8,
}

impl Rest {
    pub fn sit(&mut self, now: i64, at: (u16, u16)) {
        if self.sat.is_none() {
            self.sat = Some((now, at));
        }
    }

    /// Settles a sit that has lasted: each whole `SIT_MS` seated earns a rest; walking off ends the sit. `at`: where she
    /// stands (None: not in the place any more).
    pub fn settle(&mut self, now: i64, at: Option<(u16, u16)>) {
        let Some((since, seat)) = self.sat else { return };
        let sits = ((now - since).max(0) / SIT_MS) as u32;
        let mut from = self.rested_until.max(now);
        for _ in 0..sits {
            from = (from + RESTED_MS).min(now + RESTED_CAP_MS);
        }
        if sits > 0 {
            self.rested_until = from;
            self.sat = Some((since + sits as i64 * SIT_MS, seat));
        }
        if at.is_none_or(|a| !super::place::near(a, seat, SEAT_DRIFT_PX)) {
            self.sat = None;
        }
    }

    pub fn stand(&mut self, now: i64, at: Option<(u16, u16)>) {
        self.settle(now, at);
        self.sat = None;
    }

    pub fn pct(&self, now: i64) -> u64 {
        if self.rested_until > now {
            RESTED_XP_PCT
        } else {
            0
        }
    }

    pub fn view(&self, now: i64) -> View {
        View { sitting: self.sat.is_some(), secs: self.sat.map_or(0, |(s, _)| ((now - s).max(0) / 1000) as u32), rested_ms: (self.rested_until - now).clamp(0, u32::MAX as i64) as u32, pct: self.pct(now) as u8 }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_minute_by_the_fire_makes_her_rested_for_half_an_hour_and_walking_off_forfeits_it() {
        let mut r = Rest::default();
        r.sit(0, (100, 100));
        r.settle(30_000, Some((100, 100)));
        assert_eq!(r.pct(30_000), 0);
        r.settle(SIT_MS, Some((110, 100)));
        assert_eq!((r.pct(SIT_MS), r.view(SIT_MS).rested_ms as i64), (RESTED_XP_PCT, RESTED_MS));
        // The sit goes on: another minute adds another half hour (up to the cap).
        r.settle(2 * SIT_MS, Some((100, 100)));
        assert_eq!(r.view(2 * SIT_MS).rested_ms as i64, RESTED_MS * 2 - SIT_MS);
        for k in 3..200 {
            r.settle(k * SIT_MS, Some((100, 100)));
        }
        assert_eq!(r.view(199 * SIT_MS).rested_ms as i64, RESTED_CAP_MS);
        // Walking away ends the sit but keeps what she earned.
        r.settle(200 * SIT_MS, Some((400, 100)));
        assert!(!r.view(200 * SIT_MS).sitting);
        assert_eq!(r.pct(200 * SIT_MS), RESTED_XP_PCT);
        assert_eq!(r.pct(200 * SIT_MS + RESTED_CAP_MS + 1), 0);
        // A short sit earns nothing.
        let mut q = Rest::default();
        q.sit(0, (1, 1));
        q.stand(SIT_MS - 1, Some((1, 1)));
        assert_eq!(q.pct(SIT_MS), 0);
    }
}
