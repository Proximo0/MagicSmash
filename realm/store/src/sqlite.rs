//! The SQLite store: one writer thread owning the write connection, fed through a channel, with group commit;
//! a second, read-only connection for reads.

use crate::codec::{args_hash, decode_result, encode_result};
use crate::crash::{self, Site};
use crate::ops::{self, Tx};
use crate::read;
use crate::schema;
use crate::types::limits::MAX_BATCH;
use crate::types::*;
use crate::Store;
use rusqlite::backup::Backup;
use rusqlite::{Connection, OpenFlags, params};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender, TryRecvError};
use std::sync::Mutex;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

#[derive(Clone, Debug)]
pub struct Options {
	/// Commands arriving within this time of a batch's first share its transaction. Zero (the default): a batch is
	/// whatever is queued when the writer is free, so commands arriving during a commit form the next batch. A
	/// fixed 20 ms window measured 3 to 4 times slower here (see docs/realm/store.md).
	pub group_window: Duration,
	pub max_batch: usize,
	/// `synchronous = FULL` (the default: a reply means the change is on disk). False is for simulations that test
	/// rules and not crashes: it keeps WAL but does not fsync at each commit.
	pub durable: bool,
}

impl Default for Options {
	fn default() -> Options {
		Options { group_window: Duration::ZERO, max_batch: MAX_BATCH, durable: true }
	}
}

enum Job {
	One(Request, Sender<Result<Reply>>),
	Many(Vec<Request>, Sender<Vec<Result<Reply>>>),
}

impl Job {
	fn len(&self) -> usize {
		match self {
			Job::One(..) => 1,
			Job::Many(v, _) => v.len(),
		}
	}
}

pub struct SqliteStore {
	path: PathBuf,
	tx: Mutex<Option<Sender<Job>>>,
	writer: Mutex<Option<JoinHandle<()>>>,
	read: Mutex<Connection>,
}

fn pragmas(c: &Connection) -> rusqlite::Result<()> {
	c.busy_timeout(Duration::from_secs(10))?;
	// a page cache of 64 MB (the default is 2 MB): the request table is keyed by random ids, so its pages are
	// touched all over and a small cache turned every insert into a read from the file once the store was big
	c.execute_batch("PRAGMA foreign_keys = ON; PRAGMA synchronous = FULL; PRAGMA cache_size = -65536;")?;
	Ok(())
}

/// Opens the write connection: WAL, synchronous FULL, foreign keys, migrations.
pub fn open_writer(path: &Path) -> Result<Connection> {
	let c = Connection::open(path)?;
	pragmas(&c)?;
	let mode: String = c.query_row("PRAGMA journal_mode = WAL", [], |r| r.get(0))?;
	if mode != "wal" {
		return Err(Error::Db(format!("journal mode {mode}")));
	}
	schema::migrate(&c)?;
	Ok(c)
}

pub fn open_reader(path: &Path) -> Result<Connection> {
	let c = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX)?;
	c.busy_timeout(Duration::from_secs(10))?;
	c.execute_batch("PRAGMA cache_size = -65536;")?;
	Ok(c)
}

struct Writer {
	c: Connection,
	seq: i64,
	/// a savepoint could not be undone or released: the batch's transaction must not commit
	poisoned: bool,
}

impl Writer {
	fn load_seq(c: &Connection) -> Result<i64> {
		Ok(c.query_row("SELECT coalesce(max(seq), 0) + 1 FROM ledger", [], |r| r.get(0))?)
	}

	fn run_one(&mut self, req: &Request) -> Result<Reply> {
		let args = args_hash(req.actor, &req.cmd);
		let key = req.id.to_be_bytes();
		crash::point(Site::Stmt);
		if let Some((a, reply, _, _)) = read::request_reply(&self.c, req.id)? {
			if a != args {
				return Err(Error::RequestMismatch);
			}
			return decode_result(&reply)?;
		}
		self.c.execute_batch("SAVEPOINT cmd")?;
		let first = self.seq;
		let mut t = Tx { c: &self.c, req, seq: first };
		let r = ops::apply(&mut t);
		let after = t.seq;
		let recorded = match &r {
			Ok(_) => true,
			Err(e) => e.is_recorded(),
		};
		let mut last = first - 1;
		if let Err(e) = &r {
			if let Err(rb) = self.c.execute_batch("ROLLBACK TO cmd") {
				let _ = self.c.execute_batch("RELEASE cmd");
				self.poisoned = true;
				return Err(Error::Db(format!("rollback after {e}: {rb}")));
			}
		} else {
			last = after - 1;
		}
		if recorded {
			let ins = self
				.c
				.prepare_cached(
					"INSERT INTO requests (id, args, op, reply, ledger_first, ledger_last, time) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
				)
				.and_then(|mut s| s.execute(params![&key[..], args, req.cmd.name(), encode_result(&r), first, last, req.now]));
			if let Err(e) = ins {
				let rb = self.c.execute_batch("ROLLBACK TO cmd");
				let rel = self.c.execute_batch("RELEASE cmd");
				if rb.is_err() || rel.is_err() {
					self.poisoned = true;
				}
				return Err(e.into());
			}
		}
		if let Err(e) = self.c.execute_batch("RELEASE cmd") {
			self.poisoned = true;
			return Err(e.into());
		}
		if r.is_ok() {
			self.seq = after;
		}
		r
	}

	/// One transaction for the whole batch; replies only after COMMIT returns.
	fn run_batch(&mut self, reqs: &[&Request]) -> Vec<Result<Reply>> {
		if let Err(e) = self.c.execute_batch("BEGIN IMMEDIATE") {
			return reqs.iter().map(|_| Err(Error::Db(e.to_string()))).collect();
		}
		self.poisoned = false;
		let mut out = Vec::with_capacity(reqs.len());
		for r in reqs {
			if self.poisoned {
				break;
			}
			let res = self.run_one(r);
			out.push(res);
		}
		if self.poisoned {
			// a savepoint was left in an unknown state: undo the whole batch, tell every caller it failed
			let _ = self.c.execute_batch("ROLLBACK");
			self.poisoned = false;
			self.seq = Writer::load_seq(&self.c).unwrap_or(self.seq);
			return reqs.iter().map(|_| Err(Error::Db("batch rolled back: a savepoint failed".into()))).collect();
		}
		crash::point(Site::BeforeCommit);
		match self.c.execute_batch("COMMIT") {
			Ok(()) => {
				crash::point(Site::AfterCommit);
				out
			}
			Err(e) => {
				let _ = self.c.execute_batch("ROLLBACK");
				self.seq = Writer::load_seq(&self.c).unwrap_or(self.seq);
				reqs.iter().map(|_| Err(Error::Db(format!("commit: {e}")))).collect()
			}
		}
	}

	fn serve(mut self, rx: Receiver<Job>, opts: Options) {
		while let Ok(first) = rx.recv() {
			let deadline = Instant::now() + opts.group_window;
			let mut n = first.len();
			let mut jobs = vec![first];
			while n < opts.max_batch {
				let next = match rx.try_recv() {
					Ok(j) => Some(j),
					Err(TryRecvError::Disconnected) => None,
					Err(TryRecvError::Empty) => {
						let now = Instant::now();
						if now >= deadline {
							None
						} else {
							match rx.recv_timeout(deadline - now) {
								Ok(j) => Some(j),
								Err(RecvTimeoutError::Timeout | RecvTimeoutError::Disconnected) => None,
							}
						}
					}
				};
				match next {
					Some(j) => {
						n += j.len();
						jobs.push(j);
					}
					None => break,
				}
			}
			let mut reqs: Vec<&Request> = Vec::with_capacity(n);
			for j in &jobs {
				match j {
					Job::One(r, _) => reqs.push(r),
					Job::Many(v, _) => reqs.extend(v.iter()),
				}
			}
			let mut results = self.run_batch(&reqs).into_iter();
			for j in jobs {
				match j {
					Job::One(_, tx) => {
						let _ = tx.send(results.next().unwrap());
					}
					Job::Many(v, tx) => {
						let rs: Vec<_> = results.by_ref().take(v.len()).collect();
						let _ = tx.send(rs);
					}
				}
			}
		}
	}
}

impl SqliteStore {
	pub fn open(path: impl AsRef<Path>) -> Result<SqliteStore> {
		SqliteStore::open_with(path, Options::default())
	}

	pub fn open_with(path: impl AsRef<Path>, opts: Options) -> Result<SqliteStore> {
		let path = path.as_ref().to_path_buf();
		let mut c = open_writer(&path)?;
		if !opts.durable {
			c.execute_batch("PRAGMA synchronous = OFF")?;
		}
		if crash::armed(Site::Commit) || crash::counting() {
			c.commit_hook(Some(|| {
				crash::point(Site::Commit);
				false
			}))?;
		}
		if crash::armed(Site::Progress) || crash::counting() {
			c.progress_handler(
				64,
				Some(|| {
					crash::point(Site::Progress);
					false
				}),
			)?;
		}
		let seq = Writer::load_seq(&c)?;
		let read = open_reader(&path)?;
		let (tx, rx) = mpsc::channel();
		let w = Writer { c, seq, poisoned: false };
		let h = std::thread::Builder::new()
			.name("store-writer".into())
			.spawn(move || w.serve(rx, opts))
			.map_err(|e| Error::Db(e.to_string()))?;
		Ok(SqliteStore { path, tx: Mutex::new(Some(tx)), writer: Mutex::new(Some(h)), read: Mutex::new(read) })
	}

	pub fn path(&self) -> &Path {
		&self.path
	}

	fn sender(&self) -> Result<Sender<Job>> {
		self.tx.lock().unwrap().clone().ok_or(Error::Closed)
	}

	fn with_read<T>(&self, f: impl FnOnce(&Connection) -> Result<T>) -> Result<T> {
		let c = self.read.lock().unwrap();
		f(&c)
	}

	/// Stops the writer after the commands already queued.
	pub fn close(&self) {
		self.tx.lock().unwrap().take();
		if let Some(h) = self.writer.lock().unwrap().take() {
			let _ = h.join();
		}
	}

	/// The stored reply of a request (for checks).
	pub fn recorded(&self, id: RequestId) -> Result<Option<(Result<Reply>, i64, i64)>> {
		self.with_read(|c| match read::request_reply(c, id)? {
			Some((_, rep, f, l)) => Ok(Some((decode_result(&rep)?, f, l))),
			None => Ok(None),
		})
	}
}

impl Drop for SqliteStore {
	fn drop(&mut self) {
		self.close();
	}
}

/// Copies a live database to `dest` with SQLite's backup API in one step: it reads one WAL snapshot, so writers
/// keep going, and the copy is that snapshot. Then verifies the copy.
pub fn backup_file(src: &Path, dest: &Path) -> Result<VerifyReport> {
	backup_copy(src, dest)?;
	let d = open_reader(dest)?;
	read::verify(&d)
}

/// The copy half of `backup_file`, without the verify: the operations tool uses it for a store older than this
/// build's schema (the full verify knows only the newest tables) and checks the copy its own way.
pub fn backup_copy(src: &Path, dest: &Path) -> Result<()> {
	for suffix in ["", "-wal", "-shm"] {
		let p = PathBuf::from(format!("{}{suffix}", dest.display()));
		if p.exists() {
			std::fs::remove_file(&p).map_err(|e| Error::Db(format!("remove {}: {e}", p.display())))?;
		}
	}
	let s = open_reader(src)?;
	let mut d = Connection::open(dest)?;
	let b = Backup::new(&s, &mut d)?;
	b.step(-1)?;
	Ok(())
}

/// Replaces `dest` (no store may have it open) with the verified contents of the backup `src`, then verifies.
pub fn restore_file(src: &Path, dest: &Path) -> Result<VerifyReport> {
	{
		let s = open_reader(src)?;
		let rep = read::verify(&s)?;
		if !rep.ok() {
			return Err(Error::Invalid(format!("backup fails verify: {:?}", rep.problems)));
		}
	}
	{
		let s = open_reader(src)?;
		let mut d = Connection::open(dest)?;
		d.busy_timeout(Duration::from_secs(10))?;
		let b = Backup::new(&s, &mut d)?;
		b.step(-1)?;
	}
	let d = open_writer(dest)?;
	read::verify(&d)
}

impl Store for SqliteStore {
	fn submit(&self, req: Request) -> Result<Reply> {
		let (tx, rx) = mpsc::channel();
		self.sender()?.send(Job::One(req, tx)).map_err(|_| Error::Closed)?;
		rx.recv().map_err(|_| Error::Closed)?
	}

	fn submit_batch(&self, reqs: Vec<Request>) -> Vec<Result<Reply>> {
		let n = reqs.len();
		let (tx, rx) = mpsc::channel();
		let sent = self.sender().and_then(|s| s.send(Job::Many(reqs, tx)).map_err(|_| Error::Closed));
		match sent.and_then(|_| rx.recv().map_err(|_| Error::Closed)) {
			Ok(v) => v,
			Err(e) => (0..n).map(|_| Err(e.clone())).collect(),
		}
	}

	fn account(&self, id: AccountId) -> Result<Option<Account>> {
		self.with_read(|c| read::account(c, id))
	}
	fn accounts_flagged(&self, mask: u64) -> Result<Vec<Account>> {
		self.with_read(|c| read::accounts_flagged(c, mask))
	}
	fn hero(&self, id: HeroId) -> Result<Option<Hero>> {
		self.with_read(|c| read::hero(c, id))
	}
	fn heroes(&self, account: AccountId, include_deleted: bool) -> Result<Vec<Hero>> {
		self.with_read(|c| read::heroes(c, account, include_deleted))
	}
	fn hero_by_name(&self, name: &str) -> Result<Option<Hero>> {
		self.with_read(|c| read::hero_by_name(c, name))
	}
	fn item(&self, id: ItemId) -> Result<Option<Item>> {
		self.with_read(|c| read::item(c, id))
	}
	fn items_at(&self, kind: PlaceKind, owner: i64) -> Result<Vec<Item>> {
		self.with_read(|c| read::items_at(c, kind, owner))
	}
	fn stack(&self, owner: Owner, kind: StackKind) -> Result<u64> {
		self.with_read(|c| read::stack(c, &owner, kind))
	}
	fn stacks(&self, owner: Owner) -> Result<Vec<(StackKind, u64)>> {
		self.with_read(|c| read::stacks(c, &owner))
	}
	fn owned_cards(&self, account: AccountId) -> Result<Vec<u16>> {
		self.with_read(|c| read::owned_cards(c, account))
	}
	fn entitlements(&self, account: AccountId) -> Result<Vec<(EntitlementKind, u32)>> {
		self.with_read(|c| read::entitlements(c, account))
	}
	fn trace(&self, account: AccountId) -> Result<Trace> {
		self.with_read(|c| read::trace(c, account))
	}
	fn trace_forward(&self, account: AccountId, depth: u32) -> Result<Vec<Hop>> {
		self.with_read(|c| read::trace_forward(c, account, depth))
	}
	fn clawback_plan(&self, account: AccountId, since_seq: i64) -> Result<ClawbackPlan> {
		self.with_read(|c| read::clawback_plan(c, account, since_seq))
	}
	fn verify(&self) -> Result<VerifyReport> {
		let c = open_reader(&self.path)?;
		read::verify(&c)
	}
	fn backup(&self, dest: &Path) -> Result<VerifyReport> {
		backup_file(&self.path, dest)
	}
	fn stats(&self) -> Result<Stats> {
		let c = open_reader(&self.path)?;
		read::stats(&c)
	}
	fn coin_flows(&self) -> Result<Vec<(String, String, bool, i64, i64)>> {
		let c = open_reader(&self.path)?;
		read::coin_flows(&c)
	}
	fn parcel(&self, id: i64) -> Result<Option<Parcel>> {
		self.with_read(|c| crate::parcels::parcel(c, id))
	}
	fn parcels_from(&self, hero: HeroId) -> Result<Vec<Parcel>> {
		self.with_read(|c| crate::parcels::parcels_from(c, hero))
	}
	fn parcels_to(&self, hero: HeroId) -> Result<Vec<Parcel>> {
		self.with_read(|c| crate::parcels::parcels_to(c, hero))
	}
	fn parcels_due(&self, now: Millis, limit: u32) -> Result<Vec<i64>> {
		self.with_read(|c| crate::parcels::parcels_due(c, now, limit))
	}
	fn listings(&self, q: &ListingQuery) -> Result<Vec<Parcel>> {
		self.with_read(|c| crate::parcels::listings(c, q))
	}
}
