//! The crash fuzz. A parent runs a seeded stream of random operations through child processes (`realm-store
//! fuzz-child`), each armed to `abort()` at a chosen pass of a crash site (between statements, inside a statement,
//! in the commit, before the commit, after the commit before the reply). The child prints every batch before it
//! submits it and every reply it gets; after each kill the parent reopens the database, runs `verify`, checks that
//! every reply it was given is recorded unchanged, and resubmits the batch in flight with the same request ids
//! (as a real caller retries). The stream is a function of the seed and the database, and the crash points are
//! counted passes, so a run repeats exactly from its seed.

use crate::codec::{decode_request, decode_result, encode_request, encode_result, fnv128};
use crate::crash::{self, SITES};
use crate::read;
use crate::rng::Rng;
use crate::sqlite::{Options, SqliteStore, open_reader};
use crate::types::*;
use crate::Store;
use rusqlite::{Connection, params};
use std::collections::{HashMap, VecDeque};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub const ACCOUNTS: u64 = 60;
pub const HEROES: u64 = 200;
/// accounts, 20 hero-slot grants, heroes
const SETUP: u64 = ACCOUNTS + 20 + HEROES;
const RECENT: usize = 64;

pub fn request_id(seed: u64, idx: u64) -> RequestId {
	let mut b = [0u8; 16];
	b[..8].copy_from_slice(&seed.to_le_bytes());
	b[8..].copy_from_slice(&idx.to_le_bytes());
	fnv128(&b) | 1
}

// ---------------------------------------------------------------------------------------------------------------
// generation (child side)

struct World<'c> {
	c: &'c Connection,
	heroes: Vec<(HeroId, AccountId, u16)>,
	deleted: Vec<HeroId>,
	accounts: Vec<AccountId>,
}

impl<'c> World<'c> {
	fn load(c: &'c Connection) -> World<'c> {
		let mut heroes = Vec::new();
		let mut deleted = Vec::new();
		let mut st = c.prepare_cached("SELECT id, account, class_level, deleted_at IS NOT NULL FROM heroes ORDER BY id").unwrap();
		let rows = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get::<_, bool>(3)?))).unwrap();
		for r in rows {
			let (h, a, l, d) = r.unwrap();
			if d {
				deleted.push(h);
			} else {
				heroes.push((h, a, l));
			}
		}
		let mut st = c.prepare_cached("SELECT id FROM accounts ORDER BY id").unwrap();
		let accounts = st.query_map([], |r| r.get(0)).unwrap().map(|r| r.unwrap()).collect();
		World { c, heroes, deleted, accounts }
	}
	fn items(&self, sql_where: &str, a: i64) -> Vec<Item> {
		let mut st = self.c.prepare_cached(&format!("SELECT {} FROM items WHERE {sql_where} ORDER BY id", crate::ops::ITEM_COLS)).unwrap();
		st.query_map([a], crate::ops::item_from_row).unwrap().map(|r| r.unwrap()).collect()
	}
	fn bag(&self, h: HeroId) -> Vec<Item> {
		self.items("place_kind = 1 AND place_owner = ?1", h)
	}
	fn carried(&self, h: HeroId) -> Vec<Item> {
		self.items("place_kind IN (1, 2) AND place_owner = ?1", h)
	}
	fn kept(&self, h: HeroId, a: AccountId) -> Vec<Item> {
		let mut v = self.items("place_kind IN (1, 2, 4) AND place_owner = ?1", h);
		v.extend(self.items("place_kind IN (3, 7) AND place_owner = ?1", a));
		v
	}
	fn stack(&self, o: Owner, k: StackKind) -> u64 {
		read::stack(self.c, &o, k).unwrap_or(0)
	}
	fn bag_stacks(&self, h: HeroId) -> Vec<(StackKind, u64)> {
		read::stacks(self.c, &Owner::bag(h)).unwrap_or_default()
	}
}

fn rand_spec(r: &mut Rng, max_level: u16) -> ItemSpec {
	// flatter than the game's odds, so sockets get exercised
	let rarity = match r.below(100) {
		0..=39 => 0,
		40..=64 => 1,
		65..=84 => 2,
		85..=94 => 3,
		_ => 4,
	};
	let lines = (0..[1, 2, 3, 4, 4][rarity as usize]).map(|_| (r.below(6) as u8, 1 + r.below(15) as u16)).collect();
	ItemSpec {
		base: r.below(300) as u32,
		gear_slot: r.below(6) as u8,
		item_level: 1 + r.below(max_level.max(1) as u64 + 2) as u16,
		rarity,
		lines,
		sockets: [0, 0, 1, 1, 2][rarity as usize],
		plus: if r.chance(5) { r.below(11) as u8 } else { 0 },
		bound: r.chance(10),
	}
}

fn fallback(h: HeroId) -> Cmd {
	Cmd::StackCredit { to: Owner::bag(h), kind: StackKind::COIN, count: 1, minted: true, reason: "drop".into() }
}

fn rand_stack_kind(r: &mut Rng) -> StackKind {
	match r.below(10) {
		0..=3 => StackKind::material(r.below(7) as u32),
		4..=5 => StackKind::rune(r.below(6) as u32, 1 + r.below(2) as u32),
		6 => StackKind::key(r.below(6) as u32),
		7 => StackKind::page(12 + r.below(18) as u32),
		8 => StackKind::card(r.below(48) as u32),
		_ => StackKind::potion(r.below(6) as u32),
	}
}

fn rand_dest(r: &mut Rng, w: &World, h: HeroId, a: AccountId) -> Dest {
	let own: Vec<HeroId> = w.heroes.iter().filter(|x| x.1 == a).map(|x| x.0).collect();
	match r.below(12) {
		0..=2 => Dest::bag(*r.pick(&own).unwrap_or(&h)),
		3 => Dest::any(PlaceKind::Worn, h),
		4..=6 => Dest::bank(a, if r.chance(85) { 0 } else { 1 + r.below(2) as u32 }),
		7 => Dest::any(PlaceKind::Mail, r.pick(&w.heroes).map(|x| x.0).unwrap_or(h)),
		8 => Dest::any(PlaceKind::House, a),
		9 => Dest::any(PlaceKind::Guild, 1 + r.below(5) as i64),
		10 => Dest::at(PlaceKind::Bag, h, 0, r.below(41) as u32),
		_ => Dest::bag(r.pick(&w.heroes).map(|x| x.0).unwrap_or(h)),
	}
}

/// The op for stream index `idx`, from the seed and the database as it now is.
fn generate(seed: u64, idx: u64, w: &World, now: Millis) -> Cmd {
	let mut r = Rng::new(seed ^ idx.wrapping_mul(0x2545_f491_4f6c_dd1d));
	if idx < ACCOUNTS {
		return Cmd::AccountBySteam { steam_id: 76_561_198_000_000_000 + seed % 1000 * 1000 + idx };
	}
	if idx < ACCOUNTS + 20 {
		let a = w.accounts.get((idx - ACCOUNTS) as usize).copied().unwrap_or(1);
		return Cmd::GrantEntitlement { account: a, kind: EntitlementKind::HeroSlot, count: 1, purchase: format!("slot-{seed}-{idx}") };
	}
	if idx < SETUP {
		let j = idx - ACCOUNTS - 20;
		let a = w.accounts.get((j % ACCOUNTS) as usize).copied().unwrap_or(1);
		return Cmd::HeroCreate {
			account: a,
			name: format!("H{seed}x{j}").chars().take(16).collect(),
			race: (j % 4) as u8,
			class: (j % 8) as u8,
			look: j as u32,
			self_found: j % 10 == 0,
		};
	}
	let Some(&(h, a, lvl)) = r.pick(&w.heroes) else {
		return Cmd::AccountBySteam { steam_id: 1 };
	};
	let roll = r.below(1000);
	match roll {
		0..=199 => {
			let potions: Vec<(StackKind, u64)> = w
				.bag_stacks(h)
				.into_iter()
				.filter(|(k, _)| k.class() == Some(StackClass::Potion))
				.map(|(k, n)| (k, if r.chance(5) { n + 1 } else { 1 + r.below(n) }))
				.take(2)
				.collect();
			Cmd::Outing {
				hero: h,
				delta: OutingDelta {
					coin: r.below(500),
					xp: r.below(3000),
					levels: if lvl < 60 && r.chance(10) { 1 } else { 0 },
					items: (0..r.below(4)).map(|_| rand_spec(&mut r, lvl)).collect(),
					stacks: (0..r.below(3)).map(|_| (rand_stack_kind(&mut r), 1 + r.below(20))).collect(),
					potions_used: if r.chance(60) { potions } else { vec![] },
					waystone: if r.chance(30) { Some((r.below(6) as u8, r.below(8) as i32)) } else { None },
				},
			}
		}
		200..=279 => {
			let to = rand_dest(&mut r, w, h, a);
			let reason = *r.pick(&["drop", "cache", "chest", "merchant", "grant"]).unwrap();
			Cmd::Mint { to, spec: rand_spec(&mut r, lvl), reason: reason.into() }
		}
		280..=459 => {
			let items = w.kept(h, a);
			let Some(it) = r.pick(&items) else { return fallback(h) };
			Cmd::MoveItem { item: it.id, to: rand_dest(&mut r, w, h, a) }
		}
		460..=519 => {
			let items = w.bag(h);
			let id = r.pick(&items).map(|i| i.id).unwrap_or(1 + r.below(1000) as i64);
			Cmd::SellItem { hero: h, item: id, price: r.below(200) }
		}
		520..=569 => {
			let items: Vec<Item> = w.carried(h).into_iter().filter(|i| i.spec.sockets > 0 || r.chance(10)).collect();
			let Some(it) = r.pick(&items) else { return fallback(h) };
			let socketables: Vec<StackKind> = w.bag_stacks(h).into_iter().map(|x| x.0).filter(|k| k.socketable()).collect();
			let kind = r.pick(&socketables).copied().unwrap_or(StackKind::rune(0, 1));
			let empty = it.socketed.iter().position(|s| s.is_none()).unwrap_or(0) as u8;
			Cmd::Socket { hero: h, item: it.id, socket: if r.chance(85) { empty } else { r.below(3) as u8 }, kind }
		}
		570..=599 => {
			let items: Vec<Item> = w.carried(h).into_iter().filter(|i| i.socketed.iter().any(|s| s.is_some()) || r.chance(10)).collect();
			let Some(it) = r.pick(&items) else { return fallback(h) };
			let full = it.socketed.iter().position(|s| s.is_some()).unwrap_or(0) as u8;
			Cmd::Unsocket { hero: h, item: it.id, socket: if r.chance(85) { full } else { r.below(3) as u8 } }
		}
		600..=679 => {
			let coin = w.stack(Owner::bag(h), StackKind::COIN);
			match r.below(6) {
				0 => Cmd::StackCredit {
					to: Owner::bag(h),
					kind: StackKind::potion(r.below(6) as u32),
					count: 1 + r.below(3),
					minted: false,
					reason: "buy".into(),
				},
				1 => Cmd::StackDebit { from: Owner::bag(h), kind: StackKind::COIN, count: 1 + r.below(coin + 20), reason: "buy".into() },
				2 => Cmd::StackTransfer { from: Owner::bag(h), to: Owner::bank(a), kind: StackKind::COIN, count: 1 + r.below(coin + 5) },
				3 => {
					let b = w.stack(Owner::bank(a), StackKind::COIN);
					Cmd::StackTransfer { from: Owner::bank(a), to: Owner::bag(h), kind: StackKind::COIN, count: 1 + r.below(b + 5) }
				}
				4 => Cmd::StackTransfer {
					from: Owner::bag(h),
					to: Owner { kind: PlaceKind::Mail, id: r.pick(&w.heroes).map(|x| x.0).unwrap_or(h) },
					kind: StackKind::COIN,
					count: 1 + r.below(coin + 5),
				},
				_ => Cmd::StackTransfer {
					from: Owner::bag(h),
					to: Owner { kind: PlaceKind::Guild, id: 1 + r.below(5) as i64 },
					kind: StackKind::COIN,
					count: 1 + r.below(coin + 5),
				},
			}
		}
		680..=759 => {
			let Some(&(h2, _, _)) = r.pick(&w.heroes) else { return fallback(h) };
			let side = |r: &mut Rng, hero: HeroId| {
				let bag = w.bag(hero);
				let mut items: Vec<ItemId> = Vec::new();
				for _ in 0..r.below(3) {
					if let Some(i) = r.pick(&bag) {
						if !items.contains(&i.id) {
							items.push(i.id);
						}
					}
				}
				let coin = w.stack(Owner::bag(hero), StackKind::COIN);
				let stacks = if r.chance(50) && coin > 0 { vec![(StackKind::COIN, 1 + r.below(coin))] } else { vec![] };
				TradeSide { hero, items, stacks }
			};
			let sa = side(&mut r, h);
			let sb = side(&mut r, h2);
			Cmd::Trade { a: sa, b: sb }
		}
		760..=799 => {
			let hero = read::hero(w.c, h).ok().flatten();
			let Some(hero) = hero else { return fallback(h) };
			let mut p = hero.progress.clone();
			p.class_xp += r.below(500);
			let pts = p.class_level - 1;
			let mut stats = [0u16; 6];
			let spend = if pts > 0 { r.below(pts as u64 + 1) as u16 } else { 0 };
			for _ in 0..spend {
				stats[r.below(6) as usize] += 1;
			}
			p.stats = stats;
			p.unspent = pts - spend;
			if r.chance(5) {
				p.unspent += 1; // a bad save
			}
			p.deck = (0..12).filter(|_| r.chance(80)).collect();
			p.belt = [StackKind::potion(r.below(6) as u32).0, 0, 0];
			p.waystones[r.below(6) as usize] = r.below(8) as i32;
			Cmd::HeroSave { hero: h, progress: p }
		}
		800..=829 => match r.below(3) {
			0 => Cmd::HeroRename { hero: h, name: format!("R{}", r.below(100_000)) },
			1 => Cmd::HeroDelete { hero: h },
			_ => Cmd::HeroUndelete { hero: *r.pick(&w.deleted).unwrap_or(&h) },
		},
		830..=849 => Cmd::GrantEntitlement {
			account: a,
			kind: if r.chance(50) { EntitlementKind::BankTab } else { EntitlementKind::Look },
			count: 1,
			purchase: format!("buy-{seed}-{}", r.below(400)),
		},
		850..=869 => {
			let n = 1 + r.below(3);
			let mut changes = Vec::new();
			for _ in 0..n {
				let acct = *r.pick(&w.accounts).unwrap_or(&a);
				if changes.iter().any(|c: &FlagChange| c.account == acct) {
					continue;
				}
				let f = if r.chance(15) { flags::TRADE_LOCKED } else { 0 } | if r.chance(20) { flags::WATCHED } else { 0 };
				changes.push(FlagChange {
					account: acct,
					flags: f,
					drops_percent: if r.chance(20) { 25 } else { 100 },
					banned_until: if r.chance(15) { Some(now + 30_000) } else { None },
				});
			}
			Cmd::ApplyFlags { changes, reason: "fuzz wave".into() }
		}
		870..=884 => {
			if r.chance(50) {
				let since = (read::stats(w.c).map(|s| s.ledger_rows).unwrap_or(0) - 2000).max(0);
				let plan = read::clawback_plan(w.c, a, since).unwrap_or_default();
				Cmd::Clawback { items: plan.items.into_iter().take(6).collect(), stacks: plan.stacks.into_iter().take(6).collect(), reason: "fuzz plan".into() }
			} else {
				let items: Vec<ItemId> = w.kept(h, a).into_iter().take(2).map(|i| i.id).collect();
				let k = *r.pick(&[StackKind::COIN, StackKind::material(1), StackKind::rune(0, 1)]).unwrap();
				Cmd::Clawback { items, stacks: vec![(Owner::bag(h), k, 1 + r.below(50))], reason: "fuzz".into() }
			}
		}
		885..=899 => {
			let pages: Vec<u16> = w
				.bag_stacks(h)
				.into_iter()
				.filter(|(k, _)| k.class() == Some(StackClass::Page))
				.map(|(k, _)| (k.0 - 4000) as u16)
				.collect();
			let card = if r.chance(80) { r.pick(&pages).copied() } else { None };
			Cmd::LearnPage { hero: h, card: card.unwrap_or(12 + r.below(18) as u16) }
		}
		_ => {
			// actor-checked moves: a player moving its own things, or trying someone else's
			let items = w.kept(h, a);
			let Some(it) = r.pick(&items) else { return fallback(h) };
			Cmd::MoveItem { item: it.id, to: Dest::bank(a, 0) }
		}
	}
}

fn actor_for(seed: u64, idx: u64, cmd: &Cmd, w: &World) -> AccountId {
	let mut r = Rng::new(seed ^ idx.wrapping_mul(0x9e37_79b9) ^ 0xac7);
	if !r.chance(40) {
		return 0;
	}
	let hero_acct = |h: HeroId| w.heroes.iter().find(|x| x.0 == h).map(|x| x.1);
	let own = match cmd {
		Cmd::MoveItem { to, .. } => {
			if to.kind.hero_owned() {
				hero_acct(to.owner)
			} else if matches!(to.kind, PlaceKind::Bank | PlaceKind::House) {
				Some(to.owner)
			} else {
				None
			}
		}
		Cmd::SellItem { hero, .. } | Cmd::Socket { hero, .. } | Cmd::Unsocket { hero, .. } | Cmd::HeroSave { hero, .. } => hero_acct(*hero),
		Cmd::HeroRename { hero, .. } | Cmd::HeroDelete { hero } | Cmd::LearnPage { hero, .. } => hero_acct(*hero),
		Cmd::Trade { a, .. } => hero_acct(a.hero),
		_ => None,
	};
	if r.chance(10) {
		*r.pick(&w.accounts).unwrap_or(&0)
	} else {
		own.unwrap_or(0)
	}
}

/// The child: runs stream indices from `start` to `end` (after resubmitting the batch in flight, if any).
pub fn child(db: &Path, seed: u64, start: u64, end: u64, resubmit: Option<&Path>, recent: Option<&Path>) -> i32 {
	crash::enable_counting();
	crash::arm_from_env();
	let s = match SqliteStore::open_with(db, Options { group_window: Duration::ZERO, ..Default::default() }) {
		Ok(s) => s,
		Err(e) => {
			println!("BAD open {e}");
			return 2;
		}
	};
	let rc = open_reader(db).unwrap();
	let out = std::io::stdout();
	let mut out = out.lock();
	let mut ring: VecDeque<(Request, Result<Reply>)> = VecDeque::new();
	if let Some(p) = recent {
		for line in std::fs::read_to_string(p).unwrap_or_default().lines() {
			if let Some((q, a)) = line.split_once('\t') {
				if let (Ok(q), Ok(a)) = (decode_request(q), decode_result(a)) {
					ring.push_back((q, a));
				}
			}
		}
	}
	let emit = |out: &mut std::io::StdoutLock, lo: u64, hi: u64, reqs: Vec<Request>, ring: &mut VecDeque<(Request, Result<Reply>)>, expect: &HashMap<RequestId, Result<Reply>>| -> bool {
		writeln!(out, "B {lo} {hi} {}", reqs.len()).unwrap();
		for q in &reqs {
			writeln!(out, "C {}", encode_request(q)).unwrap();
		}
		out.flush().unwrap();
		let rs = s.submit_batch(reqs.clone());
		for (q, a) in reqs.iter().zip(rs) {
			if matches!(a, Err(Error::Db(_)) | Err(Error::Closed)) {
				writeln!(out, "BAD db error {:032x} {}", q.id, encode_result(&a)).unwrap();
				return false;
			}
			if let Some(want) = expect.get(&q.id) {
				if *want != a {
					writeln!(out, "BAD repeat {:032x} first {} now {}", q.id, encode_result(want), encode_result(&a)).unwrap();
					return false;
				}
			}
			writeln!(out, "R {:032x} {}", q.id, encode_result(&a)).unwrap();
			ring.push_back((q.clone(), a));
			if ring.len() > RECENT {
				ring.pop_front();
			}
		}
		let p = crash::passes();
		writeln!(out, "E {} {} {} {} {}", p[0], p[1], p[2], p[3], p[4]).unwrap();
		out.flush().unwrap();
		true
	};
	let mut idx = start;
	if let Some(p) = resubmit {
		let text = std::fs::read_to_string(p).unwrap_or_default();
		let mut lines = text.lines();
		if let Some(head) = lines.next() {
			let mut it = head.split_whitespace();
			let lo: u64 = it.next().and_then(|x| x.parse().ok()).unwrap_or(start);
			let hi: u64 = it.next().and_then(|x| x.parse().ok()).unwrap_or(start);
			let reqs: Vec<Request> = lines.filter_map(|l| decode_request(l).ok()).collect();
			let already = reqs.iter().filter(|q| matches!(read::request_reply(&rc, q.id), Ok(Some(_)))).count();
			writeln!(out, "A {already}").unwrap();
			if !reqs.is_empty() {
				if !emit(&mut out, lo, hi, reqs, &mut ring, &HashMap::new()) {
					return 3;
				}
				idx = hi;
			}
		}
	}
	while idx < end {
		let mut br = Rng::new(seed ^ idx ^ 0xba7c);
		let k = (1 + br.below(8)).min(end - idx);
		let w = World::load(&rc);
		let mut reqs = Vec::with_capacity(k as usize);
		let mut expect = HashMap::new();
		for j in idx..idx + k {
			let now = 1_700_000_000_000 + j as i64 * 1000;
			let mut rr = Rng::new(seed ^ j ^ 0x5eed);
			if j >= SETUP && rr.chance(4) && !ring.is_empty() {
				let (q, a) = ring[rr.below(ring.len() as u64) as usize].clone();
				if !reqs.iter().any(|x: &Request| x.id == q.id) {
					expect.insert(q.id, a);
					reqs.push(q);
					continue;
				}
			}
			let cmd = generate(seed, j, &w, now);
			let actor = actor_for(seed, j, &cmd, &w);
			let id = if let Cmd::Trade { a, b } = &cmd { crate::codec::trade_request_id(a, b, j) } else { request_id(seed, j) };
			reqs.push(Request { id, actor, now, cmd });
		}
		if !emit(&mut out, idx, idx + k, reqs, &mut ring, &expect) {
			return 3;
		}
		idx += k;
	}
	writeln!(out, "DONE").unwrap();
	out.flush().unwrap();
	s.close();
	0
}

// ---------------------------------------------------------------------------------------------------------------
// parent

#[derive(Clone, Debug)]
pub struct FuzzConfig {
	pub seed: u64,
	pub ops: u64,
	pub kills: u64,
	pub dir: PathBuf,
	pub exe: PathBuf,
	pub verbose: bool,
}

#[derive(Clone, Debug, Default)]
pub struct FuzzReport {
	pub ops: u64,
	pub kills: u64,
	pub kills_by_site: [u64; 5],
	pub children: u64,
	pub acked: u64,
	pub acked_errors: u64,
	pub resubmitted_batches: u64,
	pub resubmits_already_applied: u64,
	pub verifies: u64,
	pub final_digest: u64,
	pub final_stats: Stats,
	pub problems: Vec<String>,
	pub secs: f64,
	/// per operation: replies that were ok, and errors by kind
	pub by_op: std::collections::BTreeMap<String, (u64, std::collections::BTreeMap<String, u64>)>,
}

struct Acked {
	result: String,
}

pub fn parent(cfg: &FuzzConfig) -> FuzzReport {
	let t0 = Instant::now();
	let mut rep = FuzzReport::default();
	std::fs::create_dir_all(&cfg.dir).unwrap();
	let db = cfg.dir.join("fuzz.db");
	for s in ["", "-wal", "-shm"] {
		let _ = std::fs::remove_file(format!("{}{s}", db.display()));
	}
	let resub_path = cfg.dir.join("resubmit.txt");
	let recent_path = cfg.dir.join("recent.txt");
	let _ = std::fs::remove_file(&resub_path);
	let _ = std::fs::remove_file(&recent_path);
	let mut prng = Rng::new(cfg.seed ^ 0xf022);
	let mut next: u64 = 0;
	let mut inflight: Option<(u64, u64, Vec<String>)> = None;
	let mut acked: HashMap<RequestId, Acked> = HashMap::new();
	let mut order: Vec<RequestId> = Vec::new();
	let mut checked_upto = 0usize;
	let mut recent: VecDeque<(String, String)> = VecDeque::new();
	// passes per op of each site, learned from the children's reports
	let mut rate = [12.0f64, 200.0, 0.25, 0.25, 0.25];
	let spacing = (cfg.ops as f64 / (cfg.kills.max(1) as f64 * 1.15)).max(4.0);
	let fail = |rep: &mut FuzzReport, s: String| {
		if rep.problems.len() < 50 {
			rep.problems.push(s);
		}
	};
	while next < cfg.ops || inflight.is_some() {
		if rep.problems.len() > 0 {
			break;
		}
		// arm a crash for this child unless the kills are done (the setup phase runs unarmed to learn rates)
		let mut crash_env = None;
		if next >= SETUP && rep.kills < cfg.kills {
			let w = [30u64, 20, 15, 15, 20];
			let mut x = prng.below(100);
			let mut si = 0;
			while x >= w[si] {
				x -= w[si];
				si += 1;
			}
			let site = SITES[si];
			let mean = (spacing * rate[si]).max(1.0);
			let n = 1 + prng.below((2.0 * mean) as u64 + 1);
			crash_env = Some((site, n));
		}
		let end = if next < SETUP { SETUP.min(cfg.ops) } else { cfg.ops };
		{
			let mut f = std::fs::File::create(&recent_path).unwrap();
			for (q, a) in &recent {
				writeln!(f, "{q}\t{a}").unwrap();
			}
		}
		let mut cmd = Command::new(&cfg.exe);
		cmd.arg("fuzz-child").arg(&db).arg(cfg.seed.to_string()).arg(next.to_string()).arg(end.to_string());
		if let Some((lo, hi, lines)) = &inflight {
			let mut f = std::fs::File::create(&resub_path).unwrap();
			writeln!(f, "{lo} {hi}").unwrap();
			for l in lines {
				writeln!(f, "{l}").unwrap();
			}
			cmd.arg(&resub_path);
			rep.resubmitted_batches += 1;
		} else {
			cmd.arg("-");
		}
		cmd.arg(&recent_path);
		match crash_env {
			Some((site, n)) => {
				cmd.env("REALM_STORE_CRASH", format!("{}:{n}", site.name()));
			}
			None => {
				cmd.env_remove("REALM_STORE_CRASH");
			}
		}
		cmd.stdout(Stdio::piped()).stderr(Stdio::null());
		let mut child = cmd.spawn().expect("spawn fuzz child");
		rep.children += 1;
		let started_at = next;
		let mut cur: Option<(u64, u64, Vec<String>)> = None;
		let mut batch_results: Vec<(RequestId, String)> = Vec::new();
		let mut done = false;
		let stdout = child.stdout.take().unwrap();
		for line in BufReader::new(stdout).lines() {
			let Ok(line) = line else { break };
			let (tag, rest) = line.split_once(' ').unwrap_or((line.as_str(), ""));
			match tag {
				"B" => {
					let v: Vec<u64> = rest.split_whitespace().filter_map(|x| x.parse().ok()).collect();
					cur = Some((v[0], v[1], Vec::new()));
					batch_results.clear();
				}
				"C" => {
					if let Some(c) = cur.as_mut() {
						c.2.push(rest.to_string());
					}
				}
				"R" => {
					let (id, res) = rest.split_once(' ').unwrap_or((rest, ""));
					let id = u128::from_str_radix(id, 16).unwrap_or(0);
					batch_results.push((id, res.to_string()));
				}
				"E" => {
					let Some((_, hi, lines)) = cur.take() else { continue };
					// a resubmitted batch whose first attempt committed gets the first replies back
					for (q, (id, res)) in lines.iter().zip(batch_results.drain(..)) {
						match acked.get(&id) {
							Some(a) if a.result != res => fail(&mut rep, format!("request {id:032x}: first reply {} now {res}", a.result)),
							Some(_) => {}
							None => {
								let op = q.split_whitespace().nth(3).unwrap_or("?").to_string();
								let e = rep.by_op.entry(op).or_default();
								if res.starts_with("err") {
									rep.acked_errors += 1;
									*e.1.entry(res.split_whitespace().nth(1).unwrap_or("?").to_string()).or_insert(0) += 1;
								} else {
									e.0 += 1;
								}
								acked.insert(id, Acked { result: res.clone() });
								order.push(id);
							}
						}
						recent.push_back((q.clone(), res));
						if recent.len() > RECENT {
							recent.pop_front();
						}
					}
					inflight = None;
					next = hi;
					let p: Vec<f64> = rest.split_whitespace().filter_map(|x| x.parse().ok()).collect();
					let ops_done = (next - started_at).max(1) as f64;
					if p.len() == 5 && next > started_at + 20 {
						for i in 0..5 {
							rate[i] = 0.7 * rate[i] + 0.3 * (p[i] / ops_done).max(0.001);
						}
					}
				}
				"DONE" => done = true,
				"A" => rep.resubmits_already_applied += rest.trim().parse::<u64>().unwrap_or(0),
				"BAD" => fail(&mut rep, format!("child: {rest}")),
				_ => {}
			}
			if let Some((lo, hi, lines)) = &cur {
				inflight = Some((*lo, *hi, lines.clone()));
			}
		}
		let status = child.wait().expect("wait");
		// Unix reports an aborted child with no exit code (SIGABRT). Windows gives abort() an exit code, so there an
		// armed child that ended without DONE counts as killed.
		let killed = !status.success() && (status.code().is_none() || (cfg!(windows) && crash_env.is_some() && !done));
		if killed {
			rep.kills += 1;
			if let Some((site, _)) = crash_env {
				rep.kills_by_site[site as usize] += 1;
			}
		} else if !status.success() {
			fail(&mut rep, format!("child exited {:?}", status.code()));
		} else if !done {
			fail(&mut rep, "child ended without DONE".into());
		}
		// a resubmitted batch that was in flight when the child died stays in flight
		if inflight.is_none() && cur.is_some() {
			inflight = cur.clone();
		}
		// reopen (recovery), verify, check the acknowledged replies
		match SqliteStore::open_with(&db, Options { group_window: Duration::ZERO, ..Default::default() }) {
			Err(e) => fail(&mut rep, format!("reopen: {e}")),
			Ok(s) => {
				rep.verifies += 1;
				match s.verify() {
					Ok(v) if v.ok() => {}
					Ok(v) => {
						let msg = format!("verify after child {}: {:?}", rep.children, v.problems);
						fail(&mut rep, msg)
					}
					Err(e) => fail(&mut rep, format!("verify: {e}")),
				}
				let mut ids: Vec<RequestId> = order[checked_upto..].to_vec();
				for _ in 0..200.min(order.len()) {
					ids.push(order[prng.below(order.len() as u64) as usize]);
				}
				let rc = open_reader(&db).unwrap();
				if let Err(e) = check_acked(&rc, &ids, &acked) {
					fail(&mut rep, e);
				}
				checked_upto = order.len();
				s.close();
			}
		}
		if cfg.verbose {
			eprintln!(
				"child {} from {} to {} killed={} site={:?} acked={} rate={:.1?}",
				rep.children,
				started_at,
				next,
				killed,
				crash_env.map(|c| c.0.name()),
				acked.len(),
				rate
			);
		}
		if rep.children > cfg.kills * 4 + 1000 {
			fail(&mut rep, "too many children".into());
		}
	}
	// final: every acknowledged reply, the whole ledger
	if let Ok(rc) = open_reader(&db) {
		if let Err(e) = check_acked(&rc, &order, &acked) {
			fail(&mut rep, e);
		}
		if let Ok(st) = read::stats(&rc) {
			rep.final_digest = st.digest;
			rep.final_stats = st;
		}
		let applied_twice: i64 = rc
			.query_row(
				"SELECT count(*) FROM (SELECT request FROM ledger GROUP BY request HAVING count(*) <> max(seq) - min(seq) + 1)",
				[],
				|r| r.get(0),
			)
			.unwrap_or(-1);
		if applied_twice != 0 {
			fail(&mut rep, format!("{applied_twice} requests with split ledger rows"));
		}
	}
	rep.ops = next;
	rep.acked = acked.len() as u64;
	rep.secs = t0.elapsed().as_secs_f64();
	rep
}

fn check_acked(c: &Connection, ids: &[RequestId], acked: &HashMap<RequestId, Acked>) -> std::result::Result<(), String> {
	let mut st = c.prepare_cached("SELECT reply FROM requests WHERE id = ?1").map_err(|e| e.to_string())?;
	for id in ids {
		let a = &acked[id];
		let got: Option<String> = st.query_row(params![&id.to_be_bytes()[..]], |r| r.get(0)).ok();
		let recorded_kind = a.result.starts_with("ok") || !(a.result.starts_with("err db") || a.result.starts_with("err mismatch"));
		match got {
			Some(g) if g == a.result => {}
			None if !recorded_kind => {}
			Some(g) => return Err(format!("request {id:032x}: told {} but recorded {g}", a.result)),
			None => return Err(format!("request {id:032x}: told {} but not recorded", a.result)),
		}
	}
	Ok(())
}
