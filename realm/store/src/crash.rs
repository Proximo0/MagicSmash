//! Injected crashes for the crash fuzz: `abort()` at the Nth pass of a site. Disarmed (the default) a site costs
//! one relaxed atomic load. Armed from the `REALM_STORE_CRASH=site:n` environment variable by the fuzz child only.

use std::sync::atomic::{AtomicU64, Ordering};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Site {
	/// before each SQL statement an operation runs (between a transaction's statements)
	Stmt = 0,
	/// SQLite's progress handler, every 64 virtual machine steps (inside a statement)
	Progress = 1,
	/// SQLite's commit hook: the commit has begun, nothing is in the WAL yet
	Commit = 2,
	/// the commit returned, no reply has been sent
	AfterCommit = 3,
	/// a batch's statements are done, before COMMIT is issued
	BeforeCommit = 4,
}

pub const SITES: [Site; 5] = [Site::Stmt, Site::Progress, Site::Commit, Site::AfterCommit, Site::BeforeCommit];

impl Site {
	pub fn name(self) -> &'static str {
		match self {
			Site::Stmt => "stmt",
			Site::Progress => "progress",
			Site::Commit => "commit",
			Site::AfterCommit => "aftercommit",
			Site::BeforeCommit => "beforecommit",
		}
	}
	pub fn parse(s: &str) -> Option<Site> {
		SITES.iter().copied().find(|x| x.name() == s)
	}
}

static ARMED: [AtomicU64; 5] = [AtomicU64::new(0), AtomicU64::new(0), AtomicU64::new(0), AtomicU64::new(0), AtomicU64::new(0)];

/// Abort on the `n`th pass of `site` (n >= 1).
pub fn arm(site: Site, n: u64) {
	ARMED[site as usize].store(n, Ordering::SeqCst);
}

pub fn armed(site: Site) -> bool {
	ARMED[site as usize].load(Ordering::Relaxed) != 0
}

static PASSES: [AtomicU64; 5] = [AtomicU64::new(0), AtomicU64::new(0), AtomicU64::new(0), AtomicU64::new(0), AtomicU64::new(0)];
static COUNTING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

/// Count passes of every site (the fuzz uses the counts to aim its crashes).
pub fn enable_counting() {
	COUNTING.store(true, Ordering::SeqCst);
}

pub fn counting() -> bool {
	COUNTING.load(Ordering::Relaxed)
}

pub fn passes() -> [u64; 5] {
	let mut v = [0; 5];
	for (i, p) in PASSES.iter().enumerate() {
		v[i] = p.load(Ordering::SeqCst);
	}
	v
}

#[inline]
pub fn point(site: Site) {
	if COUNTING.load(Ordering::Relaxed) {
		PASSES[site as usize].fetch_add(1, Ordering::Relaxed);
	}
	let a = &ARMED[site as usize];
	if a.load(Ordering::Relaxed) == 0 {
		return;
	}
	if a.fetch_sub(1, Ordering::SeqCst) == 1 {
		std::process::abort();
	}
}

/// Reads `REALM_STORE_CRASH=site:n`.
pub fn arm_from_env() {
	if let Ok(v) = std::env::var("REALM_STORE_CRASH") {
		if let Some((s, n)) = v.split_once(':') {
			if let (Some(site), Ok(n)) = (Site::parse(s), n.parse::<u64>()) {
				if n > 0 {
					arm(site, n);
				}
			}
		}
	}
}
