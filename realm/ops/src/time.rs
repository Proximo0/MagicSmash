//! Wall clock text without a crate: UTC civil time from milliseconds since the epoch.

use std::time::{SystemTime, UNIX_EPOCH};

pub fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as i64)
}

/// (year, month, day, hour, minute, second) in UTC.
pub fn civil(ms: i64) -> (i64, u32, u32, u32, u32, u32) {
    let secs = ms.div_euclid(1000);
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400) as u32;
    // Howard Hinnant's days-to-civil.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let y = yoe + era * 400 + i64::from(m <= 2);
    (y, m, d, rem / 3600, rem % 3600 / 60, rem % 60)
}

/// Milliseconds since the epoch of a UTC civil time (the inverse of `civil`).
pub fn from_civil(y: i64, m: u32, d: u32, h: u32, mi: u32, s: u32) -> i64 {
    // Howard Hinnant's days-from-civil.
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y.rem_euclid(400);
    let mp = if m > 2 { m - 3 } else { m + 9 } as i64;
    let doy = (153 * mp + 2) / 5 + d as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    (days * 86_400 + (h * 3600 + mi * 60 + s) as i64) * 1000
}

/// `2026-11-22`, `2026-11-22T03:04` or `2026-11-22T03:04:05` (UTC, an optional trailing `Z`) to milliseconds.
pub fn parse_iso(s: &str) -> Option<i64> {
    let s = s.trim_end_matches('Z');
    let (date, clock) = s.split_once(['T', ' ']).unwrap_or((s, ""));
    let d: Vec<&str> = date.split('-').collect();
    if d.len() != 3 || d[0].len() != 4 {
        return None;
    }
    let (y, mo, dd): (i64, u32, u32) = (d[0].parse().ok()?, d[1].parse().ok()?, d[2].parse().ok()?);
    let c: Vec<u32> = if clock.is_empty() { vec![] } else { clock.split(':').map(|x| x.parse().ok()).collect::<Option<_>>()? };
    if !(1..=12).contains(&mo) || !(1..=31).contains(&dd) || c.len() > 3 || c.first().is_some_and(|h| *h > 23) || c.iter().skip(1).any(|v| *v > 59) {
        return None;
    }
    Some(from_civil(y, mo, dd, c.first().copied().unwrap_or(0), c.get(1).copied().unwrap_or(0), c.get(2).copied().unwrap_or(0)))
}

/// `2026-11-22T03:04:05.123Z`
pub fn iso(ms: i64) -> String {
    let (y, mo, d, h, mi, s) = civil(ms);
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{mi:02}:{s:02}.{:03}Z", ms.rem_euclid(1000))
}

/// `20261122-030405`, sorts as time does; the backup files' names.
pub fn stamp(ms: i64) -> String {
    let (y, mo, d, h, mi, s) = civil(ms);
    format!("{y:04}{mo:02}{d:02}-{h:02}{mi:02}{s:02}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_instants() {
        assert_eq!(iso(0), "1970-01-01T00:00:00.000Z");
        assert_eq!(stamp(1_700_000_000_000), "20231114-221320");
        assert_eq!(iso(951_782_400_000 + 5), "2000-02-29T00:00:00.005Z");
        assert_eq!(parse_iso("2023-11-14T22:13:20Z"), Some(1_700_000_000_000));
        assert_eq!(parse_iso("2000-02-29"), Some(951_782_400_000));
        assert_eq!(parse_iso("2000-13-01"), None);
        assert_eq!(parse_iso("7d"), None);
    }
}
