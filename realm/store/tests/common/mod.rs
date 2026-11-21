#![allow(dead_code)]
use realm_store::*;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

static NEXT: AtomicU64 = AtomicU64::new(1);

pub fn scratch() -> PathBuf {
	let base = std::env::var("REALM_STORE_SCRATCH")
		.unwrap_or_else(|_| "/tmp/claude-0/-home-claude/cbab541d-d45d-5962-9206-62d4e6e4c68f/scratchpad/store".into());
	let d = PathBuf::from(base).join("tests");
	std::fs::create_dir_all(&d).unwrap();
	d
}

pub fn fresh(name: &str) -> PathBuf {
	let p = scratch().join(format!("{name}-{}-{}.db", std::process::id(), NEXT.fetch_add(1, Ordering::SeqCst)));
	for s in ["", "-wal", "-shm"] {
		let _ = std::fs::remove_file(format!("{}{s}", p.display()));
	}
	p
}

/// A test store with a zero group window (tests call one at a time).
pub struct T {
	pub s: SqliteStore,
	pub path: PathBuf,
	pub n: u128,
	pub now: i64,
}

impl T {
	pub fn new(name: &str) -> T {
		let path = fresh(name);
		let s = SqliteStore::open_with(&path, Options { group_window: Duration::ZERO, ..Default::default() }).unwrap();
		T { s, path, n: 1000, now: 1_700_000_000_000 }
	}
	/// A fresh system request id.
	pub fn m(&mut self) -> Meta {
		self.n += 1;
		self.now += 1000;
		Meta::system(self.n, self.now)
	}
	pub fn by(&mut self, actor: AccountId) -> Meta {
		let mut m = self.m();
		m.actor = actor;
		m
	}
	pub fn account(&mut self, steam: u64) -> AccountId {
		let m = self.m();
		self.s.account_by_steam(m, steam).unwrap()
	}
	pub fn hero(&mut self, account: AccountId, name: &str) -> HeroId {
		let m = self.m();
		self.s.hero_create(m, account, name, 0, 0, 0, false).unwrap()
	}
	pub fn mint_bag(&mut self, hero: HeroId, level: u16) -> ItemId {
		let m = self.m();
		self.s.mint(m, Dest::bag(hero), spec(level), "drop").unwrap().0
	}
	pub fn credit(&mut self, o: Owner, k: StackKind, n: u64) -> u64 {
		let m = self.m();
		self.s.stack_credit(m, o, k, n, true, "drop").unwrap()
	}
	pub fn ok(&self) {
		let r = self.s.verify().unwrap();
		assert!(r.ok(), "verify: {:?}", r.problems);
	}
}

impl Drop for T {
	fn drop(&mut self) {
		self.s.close();
		for s in ["", "-wal", "-shm"] {
			let _ = std::fs::remove_file(format!("{}{s}", self.path.display()));
		}
	}
}

pub fn spec(level: u16) -> ItemSpec {
	ItemSpec { base: 7, gear_slot: 0, item_level: level, rarity: 2, lines: vec![(0, 3), (3, 2)], sockets: 2, plus: 0, bound: false }
}

pub fn spec_slot(level: u16, slot: u8) -> ItemSpec {
	ItemSpec { gear_slot: slot, ..spec(level) }
}
