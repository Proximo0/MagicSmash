//! Every file kept beside the store is named through `realm_ops::sides`, so the backup copies it. This scans the
//! realm's sources for a `<db>.x` path built by hand: a new kept file must be added to `SIDES` and named with
//! `side(db, X)`, or this test fails.

use realm_ops::sides::{side, SIDES, SOCIAL, WORDS};
use std::path::Path;

/// Built by hand and allowed: `side` itself, the restore's set-aside copy of a wrecked store, the dev certificate
/// (made again when missing, never kept), and the words file read as `<social log>.words`, which is
/// `side(db, WORDS)` (checked below).
const ALLOWED: [&str; 6] = [
    "\"{}.{ext}\", db.display()",
    "\"{}.before-restore-",
    "{db}.dev-cert.pem",
    "{db}.dev-key.pem",
    "{db}.dev-cert.names",
    "\"{}.words\", path.display()",
];

fn scan(dir: &Path, out: &mut Vec<String>) {
    for e in std::fs::read_dir(dir).unwrap().flatten() {
        let p = e.path();
        if p.is_dir() {
            scan(&p, out);
        } else if p.extension().is_some_and(|x| x == "rs") {
            let text = std::fs::read_to_string(&p).unwrap();
            // Sources only: a `#[cfg(test)]` module at the end of a file makes its own scratch files.
            let src = text.split("#[cfg(test)]").next().unwrap_or("");
            for (i, line) in src.lines().enumerate() {
                let code = line.trim_start();
                if code.starts_with("//") {
                    continue;
                }
                let by_hand = code.contains("\"{db}.") || (code.contains("\"{}.") && (code.contains("db.display()") || code.contains("path.display()")));
                if by_hand && !ALLOWED.iter().any(|a| code.contains(a)) {
                    out.push(format!("{}:{}: {}", p.display(), i + 1, code));
                }
            }
        }
    }
}

#[test]
fn every_kept_file_is_named_through_sides() {
    let realm = Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap();
    let mut found = Vec::new();
    for c in ["core", "server", "gateway", "store", "loot", "ops", "loadtest"] {
        let src = realm.join(c).join("src");
        if src.exists() {
            scan(&src, &mut found);
        }
    }
    assert!(found.is_empty(), "side files named by hand (add them to realm_ops::sides::SIDES and use side()):\n{}", found.join("\n"));
    let db = Path::new("data/realm.db");
    assert_eq!(side(db, WORDS), Path::new(&format!("{}.words", side(db, SOCIAL).display())));
    let mut s = SIDES.to_vec();
    s.sort();
    s.dedup();
    assert_eq!(s.len(), SIDES.len(), "no side twice");
}
