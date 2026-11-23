//! Every file the realm keeps beside its store `<db>`, by extension, in one list. Their writers (gateway, field
//! hosts, ops) name them through `side` with these constants, and backup, prune and restore copy every one in
//! `SIDES`: a new kept file is added here or it has no name (`tests/sides.rs` fails on a `<db>.x` path built
//! anywhere else).

use std::path::{Path, PathBuf};

/// The tickets key (`--secret` when not given).
pub const SECRET: &str = "secret";
/// The admin console's token.
pub const ADMIN: &str = "admin";
/// The social log (friends, guilds, mail, reports, moderation).
pub const SOCIAL: &str = "social";
/// The world's first boss kills.
pub const BOSSKILLS: &str = "bosskills";
/// The kill switches thrown.
pub const SWITCHES: &str = "switches";
/// The plot registry: who owns or rents every house.
pub const HOMES: &str = "homes";
/// The realm clock's epoch (unix ms, written once): every tide and day turns on it.
pub const EPOCH: &str = "epoch";
/// The operator's extra masked words (read beside the social log, which names it).
pub const WORDS: &str = "social.words";

/// Every kept side file. Not here (made again when missing, never kept): the `--dev-cert` files.
pub const SIDES: [&str; 8] = [SECRET, ADMIN, SOCIAL, BOSSKILLS, SWITCHES, HOMES, EPOCH, WORDS];

/// The side file `<db>.<ext>` (`ext` one of `SIDES`).
pub fn side(db: &Path, ext: &str) -> PathBuf {
    debug_assert!(SIDES.contains(&ext), "{ext} is not in SIDES");
    PathBuf::from(format!("{}.{ext}", db.display()))
}
