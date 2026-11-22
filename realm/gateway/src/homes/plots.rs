//! Who holds which plot, how it is paid for, the visiting rule of each house and its guestbook. Pure state: every
//! call is given `now`; with a file open each change is also appended to it as one tab-separated line, and `open`
//! replays the file (the same way the social log does). The coin is the store's: `mod.rs` debits it first, and a
//! plot changes hands here only after the store says the coin is gone.

use super::place::*;
use std::collections::{BTreeMap, HashMap, VecDeque};
use std::io::Write;

pub const MS_DAY: i64 = 86_400_000;
/// A plot's price to buy (at tier 100%), and a week's rent. A house is the coin sink the economy was short of
/// (economy.md, open questions): 60,000 is a third of what a hero has hauled by day 60 (180k), taken once; rent is
/// 400 a week, a hundred and fifty weeks to equal a purchase, so renting is how a new hero starts and buying is
/// for the one who stays (it also opens the second room and never lapses). Plots on the plaza end cost double.
pub const BUY_BASE: u64 = 60_000;
pub const RENT_WEEK: u64 = 400;
pub const WEEK_MS: i64 = 7 * MS_DAY;
/// Rent is paid ahead up to this many weeks; after it runs out the owner has a grace period to renew before the
/// plot is free for anyone (her things stay in the house place; she can always pick them up).
pub const RENT_WEEKS_MAX: u8 = 4;
pub const GRACE_MS: i64 = 14 * MS_DAY;
/// A visiting rule.
pub const OPEN: u8 = 0;
pub const FRIENDS: u8 = 1;
pub const GUILD: u8 = 2;
pub const LOCKED: u8 = 3;
pub const NAME_MAX: usize = 24;
pub const BOOK_MAX: usize = 50;
pub const BOOK_TEXT_MAX: usize = 80;
/// One account signs one guestbook at most this often (10 minutes), so a book is not one visitor's wall.
pub const SIGN_GAP_MS: i64 = 10 * 60_000;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tenure {
    Owned,
    Rented { until: i64 },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Plot {
    pub owner: i64,
    pub owner_name: String,
    pub tenure: Tenure,
    pub rule: u8,
    pub name: String,
    pub since: i64,
}

/// What a plot is right now.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Status {
    Free,
    Owned(i64),
    Rented(i64),
    /// Rent ran out; the holder may still renew until `until + GRACE_MS`.
    Lapsed(i64),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Entry {
    pub id: u64,
    pub at: i64,
    pub account: i64,
    pub name: String,
    pub text: String,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Refuse {
    Taken,
    NotOpen,
    HaveOne,
    NoPlot,
    Lapsed,
    BadWeeks,
    Gap,
    Empty,
}

#[derive(Default)]
pub struct Registry {
    plots: BTreeMap<u32, Plot>,
    of: HashMap<i64, u32>,
    books: HashMap<u32, VecDeque<Entry>>,
    last_sign: HashMap<(u32, i64), i64>,
    next_entry: u64,
    file: Option<std::fs::File>,
}

pub fn buy_price(index: u32) -> u64 {
    BUY_BASE * tier_pct(index) / 100
}
pub fn rent_price(index: u32, weeks: u8) -> u64 {
    RENT_WEEK * tier_pct(index) / 100 * weeks as u64
}

/// Text with control characters, tabs and newlines taken out, cut to `max` characters.
pub fn clean(s: &str, max: usize) -> String {
    s.chars().filter(|c| !c.is_control()).take(max).collect::<String>().trim().to_string()
}

impl Registry {
    pub fn new() -> Registry {
        Registry { next_entry: 1, ..Registry::default() }
    }

    /// Opens (and replays) a file; later changes are appended to it.
    pub fn open(path: &std::path::Path) -> std::io::Result<Registry> {
        let mut r = Registry::new();
        if let Ok(text) = std::fs::read_to_string(path) {
            for line in text.lines() {
                let f: Vec<&str> = line.split('\t').collect();
                r.apply(&f);
            }
        }
        r.file = Some(std::fs::OpenOptions::new().create(true).append(true).open(path)?);
        Ok(r)
    }

    fn apply(&mut self, f: &[&str]) {
        let n = |i: usize| f.get(i).and_then(|s| s.parse::<i64>().ok()).unwrap_or(0);
        let t = |i: usize| f.get(i).copied().unwrap_or("").to_string();
        match f.first().copied() {
            Some("plot") => {
                let id = n(1) as u32;
                let tenure = if n(5) == 0 { Tenure::Owned } else { Tenure::Rented { until: n(6) } };
                self.free_plot(id);
                self.of.retain(|_, p| *p != id);
                self.of.insert(n(2), id);
                self.plots.insert(id, Plot { owner: n(2), owner_name: t(3), tenure, rule: n(4) as u8, name: t(7), since: n(8) });
            }
            Some("free") => self.free_plot(n(1) as u32),
            Some("rule") => {
                if let Some(p) = self.plots.get_mut(&(n(1) as u32)) {
                    p.rule = n(2) as u8;
                }
            }
            Some("name") => {
                if let Some(p) = self.plots.get_mut(&(n(1) as u32)) {
                    p.name = t(2);
                }
            }
            Some("sign") => {
                let e = Entry { id: n(2) as u64, at: n(3), account: n(4), name: t(5), text: t(6) };
                self.next_entry = self.next_entry.max(e.id + 1);
                self.last_sign.insert((n(1) as u32, e.account), e.at);
                let b = self.books.entry(n(1) as u32).or_default();
                b.push_back(e);
                while b.len() > BOOK_MAX {
                    b.pop_front();
                }
            }
            Some("wipe") => {
                if let Some(b) = self.books.get_mut(&(n(1) as u32)) {
                    b.retain(|e| e.id != n(2) as u64);
                }
            }
            _ => {}
        }
    }

    fn log(&mut self, f: &[String]) {
        if let Some(file) = &mut self.file {
            let _ = writeln!(file, "{}", f.join("\t"));
        }
    }

    fn free_plot(&mut self, id: u32) {
        if let Some(p) = self.plots.remove(&id) {
            if self.of.get(&p.owner) == Some(&id) {
                self.of.remove(&p.owner);
            }
        }
        self.books.remove(&id);
        self.last_sign.retain(|(pl, _), _| *pl != id);
    }

    pub fn status(&self, plot: u32, now: i64) -> Status {
        match self.plots.get(&plot) {
            None => Status::Free,
            Some(p) => match p.tenure {
                Tenure::Owned => Status::Owned(p.owner),
                Tenure::Rented { until } if until > now => Status::Rented(p.owner),
                Tenure::Rented { until } if until + GRACE_MS > now => Status::Lapsed(p.owner),
                Tenure::Rented { .. } => Status::Free,
            },
        }
    }

    pub fn plot(&self, plot: u32) -> Option<&Plot> {
        self.plots.get(&plot)
    }

    /// The plot an account holds (the grace period counts: she has it until it is free for others).
    pub fn plot_of(&self, account: i64, now: i64) -> Option<u32> {
        let id = *self.of.get(&account)?;
        (self.status(id, now) != Status::Free).then_some(id)
    }

    /// Taken plots on a street.
    pub fn taken_on(&self, street: u32, now: i64) -> u32 {
        (0..PLOTS_PER_STREET).filter(|i| self.status(plot_id(street, *i), now) != Status::Free).count() as u32
    }

    /// Streets that are open: one, and one more each time the last one has `STREET_OPENS_AT` plots taken.
    pub fn streets_open(&self, now: i64) -> u32 {
        let mut n = 1;
        while n < STREETS_MAX && self.taken_on(n, now) >= STREET_OPENS_AT {
            n += 1;
        }
        n
    }

    fn put(&mut self, id: u32, p: Plot, now: i64) {
        // A plot that fell free to a stranger: its old holder's records go.
        if self.status(id, now) == Status::Free {
            self.free_plot(id);
        }
        let (mode, until) = match p.tenure {
            Tenure::Owned => (0, 0),
            Tenure::Rented { until } => (1, until),
        };
        let line = ["plot".to_string(), id.to_string(), p.owner.to_string(), p.owner_name.clone(), p.rule.to_string(), mode.to_string(), until.to_string(), p.name.clone(), p.since.to_string()];
        self.of.insert(p.owner, id);
        self.plots.insert(id, p);
        self.log(&line);
    }

    /// Checks a plot may be bought or rented by `account` (the coin is the caller's next step).
    pub fn can_take(&self, plot: u32, account: i64, now: i64) -> Result<(), Refuse> {
        if street_of(plot) > self.streets_open(now) || street_of(plot) > STREETS_MAX {
            return Err(Refuse::NotOpen);
        }
        if let Some(mine) = self.plot_of(account, now) {
            if mine != plot {
                return Err(Refuse::HaveOne);
            }
        }
        match self.status(plot, now) {
            Status::Free => Ok(()),
            Status::Owned(o) | Status::Rented(o) | Status::Lapsed(o) if o == account => Ok(()),
            _ => Err(Refuse::Taken),
        }
    }

    pub fn buy(&mut self, plot: u32, account: i64, name: &str, now: i64) -> Result<(), Refuse> {
        self.can_take(plot, account, now)?;
        let keep = self.plots.get(&plot).filter(|p| p.owner == account).cloned();
        let p = Plot { owner: account, owner_name: name.into(), tenure: Tenure::Owned, rule: keep.as_ref().map_or(OPEN, |p| p.rule), name: keep.as_ref().map_or(String::new(), |p| p.name.clone()), since: keep.map_or(now, |p| p.since) };
        self.put(plot, p, now);
        Ok(())
    }

    /// Rents or extends: `weeks` more, from now or from where the rent ends, at most `RENT_WEEKS_MAX` ahead.
    pub fn rent(&mut self, plot: u32, account: i64, name: &str, weeks: u8, now: i64) -> Result<i64, Refuse> {
        if weeks == 0 || weeks > RENT_WEEKS_MAX {
            return Err(Refuse::BadWeeks);
        }
        self.can_take(plot, account, now)?;
        let keep = self.plots.get(&plot).filter(|p| p.owner == account).cloned();
        let from = match keep.as_ref().map(|p| p.tenure) {
            Some(Tenure::Owned) => return Err(Refuse::BadWeeks),
            Some(Tenure::Rented { until }) if until > now => until,
            _ => now,
        };
        let until = from + weeks as i64 * WEEK_MS;
        if until > now + RENT_WEEKS_MAX as i64 * WEEK_MS {
            return Err(Refuse::BadWeeks);
        }
        let p = Plot { owner: account, owner_name: name.into(), tenure: Tenure::Rented { until }, rule: keep.as_ref().map_or(OPEN, |p| p.rule), name: keep.as_ref().map_or(String::new(), |p| p.name.clone()), since: keep.map_or(now, |p| p.since) };
        self.put(plot, p, now);
        Ok(until)
    }

    pub fn release(&mut self, account: i64, now: i64) -> Result<u32, Refuse> {
        let id = self.plot_of(account, now).ok_or(Refuse::NoPlot)?;
        self.free_plot(id);
        self.log(&["free".into(), id.to_string()]);
        Ok(id)
    }

    fn mine(&mut self, account: i64, now: i64) -> Result<(u32, &mut Plot), Refuse> {
        let id = self.plot_of(account, now).ok_or(Refuse::NoPlot)?;
        Ok((id, self.plots.get_mut(&id).ok_or(Refuse::NoPlot)?))
    }

    pub fn set_rule(&mut self, account: i64, rule: u8, now: i64) -> Result<(), Refuse> {
        if rule > LOCKED {
            return Err(Refuse::NotOpen);
        }
        let (id, p) = self.mine(account, now)?;
        p.rule = rule;
        self.log(&["rule".into(), id.to_string(), rule.to_string()]);
        Ok(())
    }

    pub fn set_name(&mut self, account: i64, name: &str, now: i64) -> Result<(), Refuse> {
        let name = clean(name, NAME_MAX);
        let (id, p) = self.mine(account, now)?;
        p.name = name.clone();
        self.log(&["name".into(), id.to_string(), name]);
        Ok(())
    }

    // ---- guestbook

    pub fn sign(&mut self, plot: u32, account: i64, name: &str, text: &str, now: i64) -> Result<Entry, Refuse> {
        let text = clean(text, BOOK_TEXT_MAX);
        if text.is_empty() {
            return Err(Refuse::Empty);
        }
        if self.last_sign.get(&(plot, account)).is_some_and(|&t| now - t < SIGN_GAP_MS) {
            return Err(Refuse::Gap);
        }
        let e = Entry { id: self.next_entry, at: now, account, name: name.into(), text };
        self.apply(&["sign", &plot.to_string(), &e.id.to_string(), &now.to_string(), &account.to_string(), name, &e.text]);
        self.log(&["sign".into(), plot.to_string(), e.id.to_string(), now.to_string(), account.to_string(), name.into(), e.text.clone()]);
        Ok(e)
    }

    /// Newest first.
    pub fn book(&self, plot: u32) -> Vec<Entry> {
        self.books.get(&plot).map(|b| b.iter().rev().cloned().collect()).unwrap_or_default()
    }

    pub fn wipe(&mut self, plot: u32, entry: u64) -> bool {
        let Some(b) = self.books.get_mut(&plot) else { return false };
        let n = b.len();
        b.retain(|e| e.id != entry);
        let gone = b.len() < n;
        if gone {
            self.log(&["wipe".into(), plot.to_string(), entry.to_string()]);
        }
        gone
    }

    pub fn owned_count(&self) -> usize {
        self.plots.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_plot_is_bought_once_one_to_an_account_and_prices_follow_the_tier() {
        let mut r = Registry::new();
        r.buy(plot_id(1, 7), 1, "Ann", 0).unwrap();
        assert_eq!(r.buy(plot_id(1, 7), 2, "Bob", 0), Err(Refuse::Taken));
        assert_eq!(r.buy(plot_id(1, 8), 1, "Ann", 0), Err(Refuse::HaveOne));
        assert_eq!(r.plot_of(1, 0), Some(7));
        assert_eq!((buy_price(0), buy_price(10), buy_price(23)), (120_000, 60_000, 42_000));
        assert_eq!(rent_price(0, 2), 1_600);
        assert_eq!(rent_price(23, 1), 280);
        assert_eq!(r.release(1, 0), Ok(7));
        r.buy(plot_id(1, 8), 1, "Ann", 0).unwrap();
        assert_eq!(r.release(9, 0), Err(Refuse::NoPlot));
    }

    #[test]
    fn rent_runs_out_gets_a_grace_and_then_the_plot_is_free_for_anyone() {
        let mut r = Registry::new();
        let p = plot_id(1, 3);
        let until = r.rent(p, 1, "Ann", 2, 0).unwrap();
        assert_eq!(until, 2 * WEEK_MS);
        assert_eq!(r.status(p, 1), Status::Rented(1));
        assert_eq!(r.rent(p, 1, "Ann", 3, 1), Err(Refuse::BadWeeks), "five weeks ahead is too many");
        assert_eq!(r.rent(p, 1, "Ann", 0, 1), Err(Refuse::BadWeeks));
        assert_eq!(r.rent(p, 1, "Ann", 2, 1), Ok(4 * WEEK_MS), "renewing adds to what is left");
        assert_eq!(r.status(p, 4 * WEEK_MS + 5), Status::Lapsed(1));
        assert_eq!(r.rent(p, 2, "Bob", 1, 4 * WEEK_MS + 5), Err(Refuse::Taken), "not in the grace");
        assert_eq!(r.rent(p, 1, "Ann", 1, 4 * WEEK_MS + 5), Ok(5 * WEEK_MS + 5), "renewing in the grace starts from now");
        let later = 5 * WEEK_MS + GRACE_MS + 10;
        assert_eq!(r.status(p, later), Status::Free);
        assert_eq!(r.plot_of(1, later), None);
        r.buy(p, 2, "Bob", later).unwrap();
        assert_eq!(r.status(p, later), Status::Owned(2));
        assert_eq!(r.plot_of(1, later), None);
        // Renting a bought plot makes no sense.
        assert_eq!(r.rent(p, 2, "Bob", 1, later), Err(Refuse::BadWeeks));
    }

    #[test]
    fn a_street_opens_the_next_when_three_in_four_are_taken() {
        let mut r = Registry::new();
        assert_eq!(r.streets_open(0), 1);
        assert_eq!(r.buy(plot_id(2, 0), 99, "Z", 0), Err(Refuse::NotOpen));
        for i in 0..STREET_OPENS_AT {
            r.buy(plot_id(1, i), 100 + i as i64, "A", 0).unwrap();
        }
        assert_eq!(r.streets_open(0), 2);
        r.buy(plot_id(2, 0), 99, "Z", 0).unwrap();
        assert_eq!(street_of(plot_id(2, 0)), 2);
        assert_eq!(index_of(plot_id(2, 5)), 5);
    }

    #[test]
    fn rules_names_and_the_guestbook_survive_a_restart() {
        let path = std::env::temp_dir().join(format!("homes-plots-{}.log", std::process::id()));
        let _ = std::fs::remove_file(&path);
        {
            let mut r = Registry::open(&path).unwrap();
            r.buy(plot_id(1, 2), 1, "Ann", 5).unwrap();
            r.rent(plot_id(1, 3), 2, "Bob", 1, 6).unwrap();
            r.set_rule(1, FRIENDS, 7).unwrap();
            r.set_name(1, "  The\tLantern\n House  ", 7).unwrap();
            assert_eq!(r.set_rule(1, 9, 7), Err(Refuse::NotOpen));
            r.sign(2, 2, "Bob", "lovely\thearth", 10).unwrap();
            assert_eq!(r.sign(2, 2, "Bob", "again", 11), Err(Refuse::Gap));
            assert_eq!(r.sign(2, 3, "Cy", "   ", 11), Err(Refuse::Empty));
            let e = r.sign(2, 3, "Cy", "x", 11).unwrap();
            let gone = r.sign(2, 4, "Di", "y", 12).unwrap();
            assert!(r.wipe(2, gone.id) && !r.wipe(2, gone.id));
            assert_eq!(e.id, 2);
        }
        let r = Registry::open(&path).unwrap();
        assert_eq!(r.plot_of(1, 20), Some(2));
        assert_eq!(r.plot(2).unwrap().rule, FRIENDS);
        assert_eq!(r.plot(2).unwrap().name, "TheLantern House");
        assert!(matches!(r.status(3, 20), Status::Rented(2)));
        let b = r.book(2);
        assert_eq!(b.iter().map(|e| e.text.as_str()).collect::<Vec<_>>(), vec!["x", "lovelyhearth"]);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn a_book_keeps_the_last_fifty() {
        let mut r = Registry::new();
        r.buy(0, 1, "A", 0).unwrap();
        for k in 0..60 {
            r.sign(0, 10 + k, "v", &format!("n{k}"), 1_000_000).unwrap();
        }
        let b = r.book(0);
        assert_eq!((b.len(), b[0].text.as_str(), b[49].text.as_str()), (BOOK_MAX, "n59", "n10"));
    }
}
