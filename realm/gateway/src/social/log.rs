//! The social log (job T1): what the store has no table for (guilds and their members, friends, ignores, mutes,
//! reports, the moderators' own actions) is kept as an append-only text file, one record a line, `kind<TAB>field...`
//! with tab, newline and backslash escaped. Every change is applied to the state through the same function the
//! replay uses (`Inner::apply`), so a reopened gateway holds exactly what the last one did. Each line is written and
//! flushed to the OS at once and `sync_data`'d: these are rare events (a guild joined, a ban), never chat lines.
//! The guild bank itself is in the store (ledger and all); only who may touch it lives here.

use std::fs::{File, OpenOptions};
use std::io::Write;

pub fn esc(s: &str) -> String {
    let mut o = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' => o.push_str("\\\\"),
            '\t' => o.push_str("\\t"),
            '\n' => o.push_str("\\n"),
            '\r' => {}
            c => o.push(c),
        }
    }
    o
}

pub fn unesc(s: &str) -> String {
    let mut o = String::with_capacity(s.len());
    let mut it = s.chars();
    while let Some(c) = it.next() {
        if c == '\\' {
            match it.next() {
                Some('t') => o.push('\t'),
                Some('n') => o.push('\n'),
                Some(c) => o.push(c),
                None => {}
            }
        } else {
            o.push(c);
        }
    }
    o
}

/// One line of the log.
pub fn line(kind: &str, f: &[&str]) -> String {
    let mut s = esc(kind);
    for x in f {
        s.push('\t');
        s.push_str(&esc(x));
    }
    s.push('\n');
    s
}

/// A line read back: the kind and its fields.
pub fn parse(l: &str) -> Option<(String, Vec<String>)> {
    let mut it = l.trim_end_matches('\n').split('\t');
    let kind = unesc(it.next()?);
    if kind.is_empty() {
        return None;
    }
    Some((kind, it.map(unesc).collect()))
}

pub struct LogFile {
    f: File,
}

impl LogFile {
    pub fn open(path: &std::path::Path) -> std::io::Result<(LogFile, String)> {
        let text = std::fs::read_to_string(path).unwrap_or_default();
        let f = OpenOptions::new().create(true).append(true).open(path)?;
        Ok((LogFile { f }, text))
    }
    pub fn write(&mut self, l: &str) {
        if self.f.write_all(l.as_bytes()).is_err() || self.f.sync_data().is_err() {
            eprintln!("realm-gateway: social log write failed");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_line_round_trips_with_awkward_text() {
        let l = line("gpost", &["3", "a\tb\nc\\d", "ünï"]);
        assert_eq!(l.matches('\n').count(), 1);
        let (k, f) = parse(&l).unwrap();
        assert_eq!((k.as_str(), f), ("gpost", vec!["3".to_string(), "a\tb\nc\\d".to_string(), "ünï".to_string()]));
        assert_eq!(parse("\n"), None);
    }
}
