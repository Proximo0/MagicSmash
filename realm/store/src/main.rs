//! realm-store: verify, backup, restore, stats, trace, fuzz, bench.

use realm_store::fuzz::{self, FuzzConfig};
use realm_store::rng::Rng;
use realm_store::sqlite::open_reader;
use realm_store::*;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Duration, Instant};

const USAGE: &str = "usage: realm-store <command>
  verify <db>                      check every invariant (replays the ledger)
  backup <db> <file>               online backup while writes go on, then verify the copy
  restore <file> <db>              verify the backup, copy it over <db> (store stopped), verify
  stats <db>                       counts and a digest of items and stacks
  trace <db> <account> [depth]     what an account minted, where it went, onward to depth
  fuzz [--seed=N] [--ops=N] [--kills=N] [--dir=D] [-v]
                                   crash fuzz in child processes; exit 1 on any problem
  bench [--dir=D] [--secs=N] [--threads=N] [--window=MS]
                                   outing deltas and item moves a second, alone and with a backup running";

fn flag(args: &[String], name: &str) -> Option<String> {
	args.iter().find_map(|a| a.strip_prefix(&format!("--{name}=")).map(|s| s.to_string()))
}

fn num(args: &[String], name: &str, def: u64) -> u64 {
	flag(args, name).and_then(|s| s.parse().ok()).unwrap_or(def)
}

fn scratch() -> PathBuf {
	PathBuf::from("/tmp/claude-0/-home-claude/cbab541d-d45d-5962-9206-62d4e6e4c68f/scratchpad/store")
}

fn print_report(what: &str, r: &VerifyReport) -> i32 {
	if r.ok() {
		println!("STORE {what} ok items={} stacks={} ledger={} requests={}", r.items, r.stacks, r.ledger_rows, r.requests);
		0
	} else {
		for p in &r.problems {
			println!("  {p}");
		}
		println!("STORE {what} FAILED problems={}", r.problems.len());
		1
	}
}

fn main() {
	let args: Vec<String> = std::env::args().skip(1).collect();
	let code = match args.first().map(|s| s.as_str()) {
		Some("verify") if args.len() == 2 => match open_reader(Path::new(&args[1])).and_then(|c| read::verify(&c)) {
			Ok(r) => print_report("verify", &r),
			Err(e) => {
				println!("STORE verify FAILED {e}");
				1
			}
		},
		Some("backup") if args.len() == 3 => {
			let t = Instant::now();
			match backup_file(Path::new(&args[1]), Path::new(&args[2])) {
				Ok(r) => {
					let c = print_report("backup", &r);
					println!("backup took {:.2} s", t.elapsed().as_secs_f64());
					c
				}
				Err(e) => {
					println!("STORE backup FAILED {e}");
					1
				}
			}
		}
		Some("restore") if args.len() == 3 => match restore_file(Path::new(&args[1]), Path::new(&args[2])) {
			Ok(r) => print_report("restore", &r),
			Err(e) => {
				println!("STORE restore FAILED {e}");
				1
			}
		},
		Some("stats") if args.len() == 2 => match open_reader(Path::new(&args[1])).and_then(|c| read::stats(&c)) {
			Ok(s) => {
				println!("{s:#?}");
				0
			}
			Err(e) => {
				println!("STORE stats FAILED {e}");
				1
			}
		},
		Some("trace") if args.len() >= 3 => {
			let c = open_reader(Path::new(&args[1])).expect("open");
			let a: i64 = args[2].parse().expect("account");
			let depth: u32 = args.get(3).and_then(|s| s.parse().ok()).unwrap_or(1);
			let t = read::trace(&c, a).expect("trace");
			println!("account {a}: {} items minted", t.items.len());
			for it in &t.items {
				println!("  item {} minted at {} now {:?} held by {:?}", it.item, it.mint_seq, it.place, it.holder);
			}
			for s in &t.stacks {
				println!(
					"  kind {}: minted {} spent {} holds {} sent {:?} received {:?}",
					s.kind.0, s.minted, s.spent, s.holds, s.sent, s.received
				);
			}
			for h in read::trace_forward(&c, a, depth).expect("forward") {
				println!("  hop {} seq {} {:?} -> {:?} item {:?} stack {:?} x{}", h.depth, h.seq, h.from, h.to, h.item, h.stack, h.count);
			}
			0
		}
		Some("fuzz-child") if args.len() == 7 => {
			let resub = if args[5] == "-" { None } else { Some(PathBuf::from(&args[5])) };
			fuzz::child(
				Path::new(&args[1]),
				args[2].parse().unwrap(),
				args[3].parse().unwrap(),
				args[4].parse().unwrap(),
				resub.as_deref(),
				Some(Path::new(&args[6])),
			)
		}
		Some("fuzz") => {
			let cfg = FuzzConfig {
				seed: num(&args, "seed", 1),
				ops: num(&args, "ops", 100_000),
				kills: num(&args, "kills", 300),
				dir: flag(&args, "dir").map(PathBuf::from).unwrap_or_else(|| scratch().join("fuzz")),
				exe: std::env::current_exe().unwrap(),
				verbose: args.iter().any(|a| a == "-v"),
			};
			let r = fuzz::parent(&cfg);
			for p in &r.problems {
				println!("  {p}");
			}
			let st = &r.final_stats;
			println!(
				"STORE fuzz {} seed={} ops={} kills={} (stmt={} progress={} commit={} aftercommit={} beforecommit={}) children={} \
				verifies={} acked={} acked_errors={} resubmitted={} already_applied={} items={} stacks={} ledger={} digest={:016x} secs={:.1}",
				if r.problems.is_empty() { "ok" } else { "FAILED" },
				cfg.seed,
				r.ops,
				r.kills,
				r.kills_by_site[0],
				r.kills_by_site[1],
				r.kills_by_site[2],
				r.kills_by_site[3],
				r.kills_by_site[4],
				r.children,
				r.verifies,
				r.acked,
				r.acked_errors,
				r.resubmitted_batches,
				r.resubmits_already_applied,
				st.items,
				st.stacks,
				st.ledger_rows,
				r.final_digest,
				r.secs
			);
			if args.iter().any(|a| a == "--ops-table") {
				for (op, (ok, errs)) in &r.by_op {
					println!("  {op:20} ok {ok:6}  errors {errs:?}");
				}
			}
			if r.problems.is_empty() { 0 } else { 1 }
		}
		Some("bench") => bench(&args),
		_ => {
			println!("{USAGE}");
			2
		}
	};
	std::process::exit(code);
}

fn bench_spec(r: &mut Rng) -> ItemSpec {
	ItemSpec { base: r.below(300) as u32, gear_slot: r.below(6) as u8, item_level: 1, rarity: 0, lines: vec![(0, 2)], sockets: 0, plus: 0, bound: false }
}

struct Phase {
	ops: u64,
	secs: f64,
	p50_ms: f64,
	p99_ms: f64,
	backups: u64,
}

fn run_phase(s: &Arc<SqliteStore>, heroes: &[(HeroId, AccountId)], moving: &[ItemId], kind: &str, threads: usize, secs: u64, with_backup: bool, dir: &Path, base_id: u128) -> Phase {
	let stop = Arc::new(AtomicBool::new(false));
	let count = Arc::new(AtomicU64::new(0));
	let mut hs = Vec::new();
	for th in 0..threads {
		let s = s.clone();
		let stop = stop.clone();
		let count = count.clone();
		let heroes = heroes.to_vec();
		let moving = moving.to_vec();
		let kind = kind.to_string();
		hs.push(std::thread::spawn(move || {
			let mut r = Rng::new(th as u64 * 7919 + 1);
			let mut lat = Vec::new();
			let mut k: u128 = 0;
			// each thread owns heroes th, th + threads, ...: its moves never collide with another thread's
			let mine: Vec<usize> = (th..heroes.len()).step_by(threads).collect();
			let mut in_bank = vec![false; mine.len()];
			while !stop.load(Ordering::Relaxed) {
				k += 1;
				let id = base_id + (th as u128) * 1_000_000_000 + k;
				let pick = r.below(mine.len() as u64) as usize;
				let (h, a) = heroes[mine[pick]];
				let m = Meta::system(id, 1_800_000_000_000 + k as i64);
				let t = Instant::now();
				let res = if kind == "outing" {
					let d = OutingDelta {
						coin: 1 + r.below(300),
						xp: r.below(2000),
						items: if r.chance(12) { vec![bench_spec(&mut r)] } else { vec![] },
						stacks: vec![(StackKind::material(r.below(6) as u32), 1 + r.below(5))],
						..Default::default()
					};
					s.apply_outing(m, h, d).map(|_| ())
				} else {
					let item = moving[mine[pick]];
					let to = if in_bank[pick] { Dest::bag(h) } else { Dest::bank(a, 0) };
					in_bank[pick] = !in_bank[pick];
					s.move_item(m, item, to).map(|_| ())
				};
				res.expect("bench op");
				lat.push(t.elapsed().as_secs_f64() * 1000.0);
				count.fetch_add(1, Ordering::Relaxed);
			}
			// put every moving item back in its bag (not counted), so later outings cannot take its slot
			for (i, b) in in_bank.iter().enumerate() {
				if *b {
					k += 1;
					let (h, _) = heroes[mine[i]];
					s.move_item(Meta::system(base_id + (th as u128) * 1_000_000_000 + k, 1), moving[mine[i]], Dest::bag(h)).expect("return");
				}
			}
			lat
		}));
	}
	let backups = Arc::new(AtomicU64::new(0));
	let bk = if with_backup {
		let s = s.clone();
		let stop = stop.clone();
		let backups = backups.clone();
		let dest = dir.join("bench-backup.db");
		Some(std::thread::spawn(move || {
			while !stop.load(Ordering::Relaxed) {
				let r = s.backup(&dest).expect("backup");
				assert!(r.ok(), "backup verify {:?}", r.problems);
				backups.fetch_add(1, Ordering::Relaxed);
			}
		}))
	} else {
		None
	};
	let t0 = Instant::now();
	std::thread::sleep(Duration::from_secs(secs));
	stop.store(true, Ordering::Relaxed);
	let elapsed = t0.elapsed().as_secs_f64();
	let mut lat: Vec<f64> = Vec::new();
	for h in hs {
		lat.extend(h.join().unwrap());
	}
	if let Some(b) = bk {
		b.join().unwrap();
	}
	lat.sort_by(|a, b| a.partial_cmp(b).unwrap());
	let q = |p: f64| if lat.is_empty() { 0.0 } else { lat[((lat.len() - 1) as f64 * p) as usize] };
	Phase { ops: count.load(Ordering::Relaxed), secs: elapsed, p50_ms: q(0.5), p99_ms: q(0.99), backups: backups.load(Ordering::Relaxed) }
}

fn bench(args: &[String]) -> i32 {
	let dir = flag(args, "dir").map(PathBuf::from).unwrap_or_else(|| scratch().join("bench"));
	let secs = num(args, "secs", 5);
	let threads = (num(args, "threads", 64) as usize).clamp(1, 200);
	let window = num(args, "window", 0);
	std::fs::create_dir_all(&dir).unwrap();
	let db = dir.join("bench.db");
	for s in ["", "-wal", "-shm"] {
		let _ = std::fs::remove_file(format!("{}{s}", db.display()));
	}
	let s = Arc::new(SqliteStore::open_with(&db, Options { group_window: Duration::from_millis(window), ..Default::default() }).unwrap());
	// setup through batches: 60 accounts, 200 heroes, one item each to move
	let mut n: u128 = 1;
	let mut reqs = Vec::new();
	for i in 0..60u64 {
		n += 1;
		reqs.push(Request { id: n, actor: 0, now: 1, cmd: Cmd::AccountBySteam { steam_id: 9_000 + i } });
	}
	let accts: Vec<AccountId> = s.submit_batch(reqs).into_iter().map(|r| match r.unwrap() {
		Reply::Account(a) => a,
		_ => unreachable!(),
	}).collect();
	let mut reqs = Vec::new();
	for (i, a) in accts.iter().enumerate().take(20) {
		n += 1;
		reqs.push(Request { id: n, actor: 0, now: 1, cmd: Cmd::GrantEntitlement { account: *a, kind: EntitlementKind::HeroSlot, count: 1, purchase: format!("b{i}") } });
	}
	s.submit_batch(reqs);
	let mut reqs = Vec::new();
	for j in 0..200usize {
		n += 1;
		let a = accts[j % 60];
		reqs.push(Request { id: n, actor: 0, now: 1, cmd: Cmd::HeroCreate { account: a, name: format!("Bench{j}"), race: 0, class: 0, look: 0, self_found: false } });
	}
	let heroes: Vec<(HeroId, AccountId)> = s.submit_batch(reqs).into_iter().enumerate().map(|(j, r)| match r.unwrap() {
		Reply::Hero(h) => (h, accts[j % 60]),
		_ => unreachable!(),
	}).collect();
	let mut reqs = Vec::new();
	let mut r = Rng::new(5);
	for (h, _) in &heroes {
		n += 1;
		reqs.push(Request { id: n, actor: 0, now: 1, cmd: Cmd::Mint { to: Dest::bag(*h), spec: bench_spec(&mut r), reason: "grant".into() } });
	}
	let moving: Vec<ItemId> = s.submit_batch(reqs).into_iter().map(|r| match r.unwrap() {
		Reply::Item(i, _) => i,
		_ => unreachable!(),
	}).collect();
	println!("bench: {threads} callers, group window {window} ms, synchronous=FULL, {secs} s a phase, db {}", db.display());
	let mut base: u128 = 1 << 100;
	for (kind, bk) in [("outing", false), ("move", false), ("outing", true), ("move", true)] {
		base += 1 << 90;
		let p = run_phase(&s, &heroes, &moving, kind, threads, secs, bk, &dir, base);
		println!(
			"  {:7} {:13} {:7.0} ops/s  ({} ops)  p50 {:.1} ms  p99 {:.1} ms{}",
			kind,
			if bk { "with backup" } else { "alone" },
			p.ops as f64 / p.secs,
			p.ops,
			p.p50_ms,
			p.p99_ms,
			if bk { format!("  backups done {}", p.backups) } else { String::new() }
		);
	}
	let st = s.stats().unwrap();
	let v = s.verify().unwrap();
	println!("  db {:.1} MB, ledger {} rows, verify {}", st.db_bytes as f64 / 1e6, st.ledger_rows, if v.ok() { "ok" } else { "FAILED" });
	s.close();
	if v.ok() { 0 } else { 1 }
}
