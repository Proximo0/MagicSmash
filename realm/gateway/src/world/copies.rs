//! Copies of a field (rules section 11), as a pure planner the gateway's world thread asks once a step.
//!
//! - A copy holds at most `cap` heroes (1,000). Load is counted in tickets (heroes in the copy and on their way),
//!   so a burst of arrivals cannot overfill a copy between two reads of its host.
//! - New arrivals and whole parties go to the emptiest open copy with room for all of them (`choose`).
//! - A new copy opens when every open copy has passed `open_at` (800) and the field has fewer than `max_copies`.
//! - When the two emptiest open copies together hold under `merge_under` (500) for `merge_grace_ms` (a minute, so
//!   a dip does not close a copy that refills), the emptier is closed into the other, and only while no tide runs
//!   in them and no boss is up ("at the end of its tide": the altars, a boss fight and their contributions are not
//!   cut off halfway). Its heroes are
//!   moved with their outing state to the same ring of the other copy.

/// The numbers of rules section 11 (a test realm uses smaller ones with the same logic).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CopyRules {
    pub cap: u32,
    pub open_at: u32,
    pub merge_under: u32,
    pub max_copies: u32,
    pub merge_grace_ms: u64,
}

impl Default for CopyRules {
    fn default() -> Self {
        CopyRules { cap: 1_000, open_at: 800, merge_under: 500, max_copies: 4, merge_grace_ms: 60_000 }
    }
}

/// One copy as the planner sees it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CopyLoad {
    /// The gateway's host id.
    pub id: u32,
    /// Tickets on it (heroes there and on their way).
    pub heroes: u32,
    /// A tide runs in it, or a boss is up (a merge waits for both to end).
    pub tide: bool,
    /// It is being closed into another.
    pub closing: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Plan {
    Open,
    Merge { from: u32, into: u32 },
}

/// The open copy with the fewest heroes that has room for `party` more (ties: the older copy). None: all full.
pub fn choose(loads: &[CopyLoad], rules: &CopyRules, party: u32) -> Option<u32> {
    loads.iter().filter(|c| !c.closing && c.heroes + party <= rules.cap).min_by_key(|c| (c.heroes, c.id)).map(|c| c.id)
}

/// A field's memory between steps: since when its two emptiest copies have been under the merge line.
#[derive(Clone, Debug, Default)]
pub struct Planner {
    under_since: Option<u64>,
}

impl Planner {
    pub fn plan(&mut self, loads: &[CopyLoad], rules: &CopyRules, now_ms: u64) -> Option<Plan> {
        let mut open: Vec<&CopyLoad> = loads.iter().filter(|c| !c.closing).collect();
        if open.is_empty() || (open.len() < rules.max_copies as usize && open.iter().all(|c| c.heroes >= rules.open_at)) {
            self.under_since = None;
            return Some(Plan::Open);
        }
        if open.len() < 2 || loads.iter().any(|c| c.closing) {
            self.under_since = None;
            return None;
        }
        open.sort_by_key(|c| (c.heroes, u32::MAX - c.id));
        let (a, b) = (open[0], open[1]);
        if a.heroes + b.heroes >= rules.merge_under {
            self.under_since = None;
            return None;
        }
        let since = *self.under_since.get_or_insert(now_ms);
        if now_ms.saturating_sub(since) < rules.merge_grace_ms || a.tide || b.tide {
            return None;
        }
        self.under_since = None;
        Some(Plan::Merge { from: a.id, into: b.id })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn c(id: u32, heroes: u32) -> CopyLoad {
        CopyLoad { id, heroes, tide: false, closing: false }
    }

    #[test]
    fn arrivals_and_parties_go_to_the_emptiest_copy_with_room() {
        let r = CopyRules::default();
        assert_eq!(choose(&[c(1, 900), c(2, 300)], &r, 1), Some(2));
        assert_eq!(choose(&[c(1, 300), c(2, 300)], &r, 1), Some(1), "ties: the older copy");
        assert_eq!(choose(&[c(1, 995), c(2, 996)], &r, 8), None, "a party of eight fits nowhere");
        assert_eq!(choose(&[c(1, 992), c(2, 996)], &r, 8), Some(1));
        assert_eq!(choose(&[c(1, 1_000)], &r, 1), None);
        let mut closing = c(3, 0);
        closing.closing = true;
        assert_eq!(choose(&[c(1, 500), closing], &r, 1), Some(1), "never into a closing copy");
    }

    #[test]
    fn a_copy_opens_when_every_copy_has_passed_800_up_to_the_most() {
        let r = CopyRules::default();
        let mut p = Planner::default();
        assert_eq!(p.plan(&[], &r, 0), Some(Plan::Open), "a field always has a copy");
        assert_eq!(p.plan(&[c(1, 799)], &r, 0), None);
        assert_eq!(p.plan(&[c(1, 800)], &r, 0), Some(Plan::Open));
        assert_eq!(p.plan(&[c(1, 900), c(2, 100)], &r, 0), None, "the second copy takes the arrivals");
        assert_eq!(p.plan(&[c(1, 900), c(2, 850)], &r, 0), Some(Plan::Open));
        let full: Vec<CopyLoad> = (1..=4).map(|i| c(i, 1_000)).collect();
        assert_eq!(p.plan(&full, &r, 0), None, "no more than max_copies: the queue holds the rest");
    }

    #[test]
    fn two_copies_under_500_merge_after_the_grace_and_not_in_a_tide() {
        let r = CopyRules::default();
        let mut p = Planner::default();
        let loads = [c(1, 300), c(2, 150)];
        assert_eq!(p.plan(&loads, &r, 1_000), None, "the grace starts");
        assert_eq!(p.plan(&loads, &r, 30_000), None);
        let mut tide = loads;
        tide[0].tide = true;
        tide[1].tide = true;
        assert_eq!(p.plan(&tide, &r, 61_000), None, "not while a tide runs");
        assert_eq!(p.plan(&loads, &r, 61_000), Some(Plan::Merge { from: 2, into: 1 }), "the emptier closes into the other");
        // A dip that refills does not close a copy.
        let mut q = Planner::default();
        assert_eq!(q.plan(&loads, &r, 0), None);
        assert_eq!(q.plan(&[c(1, 300), c(2, 250)], &r, 30_000), None);
        assert_eq!(q.plan(&loads, &r, 61_000), None, "the grace started over");
        assert_eq!(q.plan(&[c(1, 300), c(2, 199)], &r, 30_000), None);
        // Equal loads: the newer copy closes.
        let mut e = Planner::default();
        e.plan(&[c(1, 100), c(2, 100)], &r, 0);
        assert_eq!(e.plan(&[c(1, 100), c(2, 100)], &r, 60_000), Some(Plan::Merge { from: 2, into: 1 }));
        // One closing at a time.
        let mut closing = c(3, 10);
        closing.closing = true;
        let mut f = Planner::default();
        f.plan(&[c(1, 10), c(2, 10), closing], &r, 0);
        assert_eq!(f.plan(&[c(1, 10), c(2, 10), closing], &r, 90_000), None);
    }
}
