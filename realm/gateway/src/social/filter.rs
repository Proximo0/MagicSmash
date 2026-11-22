//! The word filter hook and the rate limits for chat (job T1).
//!
//! The filter is a function the operator can replace (`Social::set_filter`); the default masks a short list of words
//! (case, spacing tricks and the common digit swaps do not hide them), refuses links, and refuses a run of one
//! character longer than `RUN_MAX`. The limiter is a token bucket per account and channel, plus one over all channels,
//! with strikes: too many refusals in a short time silence the account for a while.

use super::wire::chan;
use std::collections::HashMap;

/// What the filter says about a line.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Verdict {
    /// Send this text (maybe masked).
    Pass(String),
    /// Do not send it at all.
    Block,
}

pub type Filter = Box<dyn Fn(&str) -> Verdict + Send + Sync>;

/// A line may hold this many of one character in a row (so "aaaaaaaaaaaaa" is spam).
pub const RUN_MAX: usize = 8;

/// Words masked by the default filter; the operator adds more with `{db}.social.words` (one a line).
pub const DEFAULT_WORDS: [&str; 8] = ["fuck", "shit", "cunt", "bitch", "nigger", "faggot", "whore", "asshole"];

fn plain(c: char) -> char {
    match c {
        '0' => 'o',
        '1' | '!' | '|' => 'i',
        '3' => 'e',
        '4' | '@' => 'a',
        '5' | '$' => 's',
        '7' => 't',
        c => c.to_ascii_lowercase(),
    }
}

/// The default filter over `words`.
pub fn default_filter(words: Vec<String>) -> Filter {
    Box::new(move |text: &str| {
        let low = text.to_ascii_lowercase();
        if low.contains("http://") || low.contains("https://") || low.contains("www.") || low.contains(".com/") {
            return Verdict::Block;
        }
        let mut run = 0usize;
        let mut last = None;
        for c in text.chars() {
            if Some(c) == last {
                run += 1;
                if run > RUN_MAX {
                    return Verdict::Block;
                }
            } else {
                run = 1;
                last = Some(c);
            }
        }
        // Mask by position over the letters only, so "f u c k" and "f.u.c.k" are caught and the line keeps its shape.
        let chars: Vec<char> = text.chars().collect();
        let mut keep: Vec<(usize, char)> = Vec::new();
        for (i, c) in chars.iter().enumerate() {
            if c.is_alphanumeric() || "@$!|".contains(*c) {
                keep.push((i, plain(*c)));
            }
        }
        let flat: Vec<char> = keep.iter().map(|k| k.1).collect();
        let mut out = chars.clone();
        for w in words.iter().filter(|w| !w.is_empty()) {
            let w: Vec<char> = w.to_ascii_lowercase().chars().collect();
            if w.len() > flat.len() {
                continue;
            }
            for s in 0..=flat.len() - w.len() {
                if flat[s..s + w.len()] == w[..] {
                    for k in &keep[s..s + w.len()] {
                        out[k.0] = '*';
                    }
                }
            }
        }
        Verdict::Pass(out.into_iter().collect())
    })
}

/// (burst, one more every `refill_ms`) for a channel.
pub fn channel_limit(chan: u8) -> (u32, i64) {
    match chan {
        chan::SAY => (5, 1000),
        chan::TOWN => (3, 2000),
        chan::TRADE => (2, 10_000),
        chan::PARTY => (8, 500),
        chan::GUILD => (6, 1000),
        chan::WHISPER => (5, 1000),
        _ => (3, 2000),
    }
}

/// One bucket over all channels together: a burst of 10 lines and 4 a second.
pub const ALL_BURST: u32 = 10;
pub const ALL_REFILL_MS: i64 = 250;
/// This many refusals for rate inside `STRIKE_WINDOW_MS` silence the account for `AUTO_SILENCE_MS`.
pub const STRIKES_MAX: u32 = 30;
pub const STRIKE_WINDOW_MS: i64 = 10_000;
pub const AUTO_SILENCE_MS: i64 = 5 * 60_000;

#[derive(Clone, Copy, Debug)]
struct Bucket {
    tokens: u32,
    at: i64,
}

impl Bucket {
    fn full(burst: u32, now: i64) -> Bucket {
        Bucket { tokens: burst, at: now }
    }
    fn refill(&mut self, burst: u32, every_ms: i64, now: i64) {
        let gained = ((now - self.at).max(0) / every_ms) as u64;
        if gained > 0 {
            self.tokens = (self.tokens as u64 + gained).min(burst as u64) as u32;
            self.at += gained as i64 * every_ms;
        }
        if self.tokens == burst {
            self.at = now;
        }
    }
}

/// What the limiter decided.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Limit {
    Ok,
    /// Refused for rate.
    Slow,
    /// Refused, and this refusal was the last strike: silence her.
    Flood,
}

#[derive(Default)]
pub struct Limiter {
    by_chan: HashMap<(i64, u8), Bucket>,
    all: HashMap<i64, Bucket>,
    strikes: HashMap<i64, (i64, u32)>,
}

impl Limiter {
    /// Takes a token for a line on `chan` from `account` at `now` (ms).
    pub fn take(&mut self, account: i64, chan: u8, now: i64) -> Limit {
        let (burst, every) = channel_limit(chan);
        let c = self.by_chan.entry((account, chan)).or_insert_with(|| Bucket::full(burst, now));
        c.refill(burst, every, now);
        let a = self.all.entry(account).or_insert_with(|| Bucket::full(ALL_BURST, now));
        a.refill(ALL_BURST, ALL_REFILL_MS, now);
        if c.tokens > 0 && a.tokens > 0 {
            c.tokens -= 1;
            a.tokens -= 1;
            return Limit::Ok;
        }
        let s = self.strikes.entry(account).or_insert((now, 0));
        if now - s.0 > STRIKE_WINDOW_MS {
            *s = (now, 0);
        }
        s.1 += 1;
        if s.1 >= STRIKES_MAX {
            self.strikes.remove(&account);
            return Limit::Flood;
        }
        Limit::Slow
    }

    /// Forgets an account's buckets (she went away for good).
    pub fn forget(&mut self, account: i64) {
        self.all.remove(&account);
        self.strikes.remove(&account);
        self.by_chan.retain(|k, _| k.0 != account);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pass(f: &Filter, s: &str) -> String {
        match f(s) {
            Verdict::Pass(t) => t,
            Verdict::Block => "<blocked>".into(),
        }
    }

    #[test]
    fn the_default_filter_masks_words_through_tricks_and_blocks_links_and_runs() {
        let f = default_filter(DEFAULT_WORDS.iter().map(|s| s.to_string()).collect());
        assert_eq!(pass(&f, "well hello there"), "well hello there");
        assert_eq!(pass(&f, "this is SHIT ok"), "this is **** ok");
        assert_eq!(pass(&f, "sh1t and f.u.c.k"), "**** and *.*.*.*");
        assert_eq!(pass(&f, "go to http://spam.example"), "<blocked>");
        assert_eq!(pass(&f, "www.gold.example"), "<blocked>");
        assert_eq!(pass(&f, "aaaaaaaaaaaaaaa"), "<blocked>");
        assert_eq!(pass(&f, "aaaaaaaa fine"), "aaaaaaaa fine");
        // A word of the operator's own.
        let g = default_filter(vec!["lich".into()]);
        assert_eq!(pass(&g, "the Lich king"), "the **** king");
    }

    #[test]
    fn buckets_burst_refill_and_strike() {
        let mut l = Limiter::default();
        // A say burst of 5, then slow, then one back a second later.
        for _ in 0..5 {
            assert_eq!(l.take(1, chan::SAY, 0), Limit::Ok);
        }
        assert_eq!(l.take(1, chan::SAY, 10), Limit::Slow);
        assert_eq!(l.take(1, chan::SAY, 1010), Limit::Ok);
        // Another account is not touched.
        assert_eq!(l.take(2, chan::SAY, 1010), Limit::Ok);
        // 1,000 lines inside one second: the first few pass, the flood is refused and the strikes end in a Flood.
        let mut l = Limiter::default();
        let (mut ok, mut slow, mut flood) = (0, 0, 0);
        for i in 0..1000 {
            match l.take(9, chan::TOWN, i) {
                Limit::Ok => ok += 1,
                Limit::Slow => slow += 1,
                Limit::Flood => flood += 1,
            }
        }
        assert_eq!(ok, 3, "a town burst of 3");
        assert!(flood >= 1 && slow >= 1 && ok + slow + flood == 1000);
    }

    #[test]
    fn the_all_channel_bucket_caps_a_spread_flood() {
        let mut l = Limiter::default();
        let chans = [chan::SAY, chan::TOWN, chan::TRADE, chan::PARTY, chan::GUILD, chan::WHISPER];
        let mut ok = 0;
        for i in 0..600 {
            if l.take(5, chans[i % 6], (i / 6) as i64) == Limit::Ok {
                ok += 1;
            }
        }
        assert!(ok <= ALL_BURST, "{ok} lines passed in 100 ms over every channel");
    }
}
