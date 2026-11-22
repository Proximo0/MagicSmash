//! Structured logs: one line per event, `2026-11-22T03:04:05.123Z LEVEL event key=value key="two words"`, to
//! `<log_dir>/realm.log`, rotated by size (`realm.log.1` is the newest old one), and to stderr when no folder is set.
//! A global sink so the gateway and the hosts call `log::info("event", &[("k", v)])` without plumbing.

use crate::time::{iso, now_ms};
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

pub struct Sink {
    dir: PathBuf,
    name: String,
    max_bytes: u64,
    keep: usize,
    file: Option<File>,
    size: u64,
}

impl Sink {
    pub fn open(dir: &Path, max_bytes: u64, keep: usize) -> std::io::Result<Sink> {
        Sink::open_named(dir, "realm.log", max_bytes, keep)
    }

    pub fn open_named(dir: &Path, name: &str, max_bytes: u64, keep: usize) -> std::io::Result<Sink> {
        std::fs::create_dir_all(dir)?;
        let mut s = Sink { dir: dir.to_path_buf(), name: name.to_string(), max_bytes: max_bytes.max(1), keep: keep.max(1), file: None, size: 0 };
        s.reopen()?;
        Ok(s)
    }

    fn path(&self, n: usize) -> PathBuf {
        self.dir.join(if n == 0 { self.name.clone() } else { format!("{}.{n}", self.name) })
    }

    fn reopen(&mut self) -> std::io::Result<()> {
        let f = OpenOptions::new().create(true).append(true).open(self.path(0))?;
        self.size = f.metadata().map_or(0, |m| m.len());
        self.file = Some(f);
        Ok(())
    }

    fn rotate(&mut self) -> std::io::Result<()> {
        self.file = None;
        let _ = std::fs::remove_file(self.path(self.keep));
        for n in (0..self.keep).rev() {
            if self.path(n).exists() {
                std::fs::rename(self.path(n), self.path(n + 1))?;
            }
        }
        self.reopen()
    }

    pub fn write_line(&mut self, line: &str) {
        if self.size + line.len() as u64 + 1 > self.max_bytes && self.size > 0 && self.rotate().is_err() {
            return;
        }
        if let Some(f) = self.file.as_mut() {
            if writeln!(f, "{line}").is_ok() {
                self.size += line.len() as u64 + 1;
            }
        }
    }
}

static SINK: Mutex<Option<Sink>> = Mutex::new(None);

/// Sends the global log to a folder (rotating). Before this, and without it, lines go to stderr.
pub fn init(dir: &Path, max_mb: u64, keep: usize) -> std::io::Result<()> {
    *SINK.lock().unwrap() = Some(Sink::open(dir, max_mb.max(1) * 1_048_576, keep)?);
    Ok(())
}

/// Like `init`, for a program that shares the folder with another (the supervisor writes `supervisor.log`).
pub fn init_named(dir: &Path, name: &str, max_mb: u64, keep: usize) -> std::io::Result<()> {
    *SINK.lock().unwrap() = Some(Sink::open_named(dir, name, max_mb.max(1) * 1_048_576, keep)?);
    Ok(())
}

pub fn init_bytes(dir: &Path, max_bytes: u64, keep: usize) -> std::io::Result<()> {
    *SINK.lock().unwrap() = Some(Sink::open(dir, max_bytes, keep)?);
    Ok(())
}

fn quote(v: &str) -> String {
    if !v.is_empty() && !v.contains(|c: char| c.is_whitespace() || c == '"' || c == '=') {
        v.to_string()
    } else {
        format!("\"{}\"", v.replace('\\', "\\\\").replace('"', "\\\"").replace('\n', "\\n"))
    }
}

pub fn format_line(at_ms: i64, level: &str, event: &str, kv: &[(&str, String)]) -> String {
    let mut l = format!("{} {level} {event}", iso(at_ms));
    for (k, v) in kv {
        l.push(' ');
        l.push_str(k);
        l.push('=');
        l.push_str(&quote(v));
    }
    l
}

pub fn log(level: &str, event: &str, kv: &[(&str, String)]) {
    let line = format_line(now_ms(), level, event, kv);
    let mut g = SINK.lock().unwrap();
    match g.as_mut() {
        Some(s) => s.write_line(&line),
        None => eprintln!("{line}"),
    }
}

pub fn info(event: &str, kv: &[(&str, String)]) {
    log("INFO", event, kv);
}

pub fn warn(event: &str, kv: &[(&str, String)]) {
    log("WARN", event, kv);
}

pub fn error(event: &str, kv: &[(&str, String)]) {
    log("ERROR", event, kv);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lines_are_structured() {
        let l = format_line(0, "INFO", "login", &[("account", "7".into()), ("name", "Ann the Grim".into()), ("e", "".into())]);
        assert_eq!(l, "1970-01-01T00:00:00.000Z INFO login account=7 name=\"Ann the Grim\" e=\"\"");
    }

    #[test]
    fn rotation_keeps_n_files_and_drops_the_rest() {
        let dir = std::env::temp_dir().join(format!("realm-ops-log-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let mut s = Sink::open(&dir, 100, 3).unwrap();
        for i in 0..60 {
            s.write_line(&format!("line number {i:04} padded out to be long enough"));
        }
        let names: Vec<String> = std::fs::read_dir(&dir).unwrap().map(|e| e.unwrap().file_name().to_string_lossy().into_owned()).collect();
        assert!(names.contains(&"realm.log".to_string()) && names.contains(&"realm.log.3".to_string()), "{names:?}");
        assert!(!names.contains(&"realm.log.4".to_string()), "{names:?}");
        let newest = std::fs::read_to_string(dir.join("realm.log")).unwrap();
        assert!(newest.contains("0059"), "the newest line is in the live file");
        assert!(newest.len() <= 100);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
