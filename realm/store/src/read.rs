//! Reads on any connection (the store's read-only one, a backup file): rows to types, verify with ledger replay,
//! stats, trace, trace_forward and clawback_plan.

use crate::codec::{Dec, fnv64};
use crate::ops::{ITEM_COLS, item_from_row, party_of, spec_data, split_nums};
use crate::types::*;
use rusqlite::{Connection, OptionalExtension, params};
use std::collections::{BTreeMap, BTreeSet, HashMap};

pub const HERO_COLS: &str = "id, account, name, race, class, look, job, class_level, class_xp, stats, unspent, deck, \
	belt, waystones, self_found, created, deleted_at";

pub fn hero_from_row(r: &rusqlite::Row) -> rusqlite::Result<Hero> {
	let stats: Vec<u16> = split_nums(&r.get::<_, String>(9)?);
	let belt: Vec<u32> = split_nums(&r.get::<_, String>(12)?);
	let ways: Vec<i32> = split_nums(&r.get::<_, String>(13)?);
	let mut p = Progress {
		job: r.get(6)?,
		class_level: r.get(7)?,
		class_xp: r.get::<_, i64>(8)? as u64,
		stats: [0; 6],
		unspent: r.get(10)?,
		deck: split_nums(&r.get::<_, String>(11)?),
		belt: [0; 3],
		waystones: [-1; 6],
	};
	for (i, s) in stats.iter().take(6).enumerate() {
		p.stats[i] = *s;
	}
	for (i, s) in belt.iter().take(3).enumerate() {
		p.belt[i] = *s;
	}
	for (i, s) in ways.iter().take(6).enumerate() {
		p.waystones[i] = *s;
	}
	Ok(Hero {
		id: r.get(0)?,
		account: r.get(1)?,
		name: r.get(2)?,
		race: r.get(3)?,
		class: r.get(4)?,
		look: r.get(5)?,
		progress: p,
		self_found: r.get::<_, i64>(14)? != 0,
		created: r.get(15)?,
		deleted_at: r.get(16)?,
	})
}

pub fn account(c: &Connection, id: AccountId) -> Result<Option<Account>> {
	Ok(c.prepare_cached(
		"SELECT id, steam_id, dev_name, created, banned_until, flags, drops_percent FROM accounts WHERE id = ?1",
	)?
	.query_row([id], |r| {
		Ok(Account {
			id: r.get(0)?,
			steam_id: r.get::<_, Option<i64>>(1)?.map(|v| v as u64),
			dev_name: r.get(2)?,
			created: r.get(3)?,
			banned_until: r.get(4)?,
			flags: r.get::<_, i64>(5)? as u64,
			drops_percent: r.get(6)?,
		})
	})
	.optional()?)
}

pub fn hero(c: &Connection, id: HeroId) -> Result<Option<Hero>> {
	Ok(c.prepare_cached(&format!("SELECT {HERO_COLS} FROM heroes WHERE id = ?1"))?.query_row([id], hero_from_row).optional()?)
}

/// The live hero holding a name (names are unique without regard to case). A deleted hero is not found.
/// Accounts with any of the flag bits in `mask` set, by id (the moderators' ban wave).
pub fn accounts_flagged(c: &Connection, mask: u64) -> Result<Vec<Account>> {
	let mut st = c.prepare_cached("SELECT id FROM accounts WHERE flags & ?1 != 0 ORDER BY id")?;
	let ids = st.query_map([mask as i64], |r| r.get::<_, i64>(0))?.collect::<rusqlite::Result<Vec<_>>>()?;
	let mut out = Vec::new();
	for id in ids {
		if let Some(a) = account(c, id)? {
			out.push(a);
		}
	}
	Ok(out)
}

pub fn hero_by_name(c: &Connection, name: &str) -> Result<Option<Hero>> {
	let key = name.to_ascii_lowercase();
	Ok(c.prepare_cached(&format!("SELECT {HERO_COLS} FROM heroes WHERE name_key = ?1 AND name_held = 1 AND deleted_at IS NULL"))?
		.query_row([key], hero_from_row)
		.optional()?)
}

pub fn heroes(c: &Connection, account: AccountId, include_deleted: bool) -> Result<Vec<Hero>> {
	let mut st = c.prepare_cached(&format!(
		"SELECT {HERO_COLS} FROM heroes WHERE account = ?1 AND (?2 OR deleted_at IS NULL) ORDER BY id"
	))?;
	let v = st.query_map(params![account, include_deleted], hero_from_row)?.collect::<rusqlite::Result<Vec<_>>>()?;
	Ok(v)
}

pub fn item(c: &Connection, id: ItemId) -> Result<Option<Item>> {
	Ok(c.prepare_cached(&format!("SELECT {ITEM_COLS} FROM items WHERE id = ?1"))?.query_row([id], item_from_row).optional()?)
}

pub fn items_at(c: &Connection, kind: PlaceKind, owner: i64) -> Result<Vec<Item>> {
	let mut st = c.prepare_cached(&format!(
		"SELECT {ITEM_COLS} FROM items WHERE place_kind = ?1 AND place_owner = ?2 ORDER BY place_tab, place_slot"
	))?;
	let v = st.query_map(params![kind as i64, owner], item_from_row)?.collect::<rusqlite::Result<Vec<_>>>()?;
	Ok(v)
}

pub fn stack(c: &Connection, o: &Owner, k: StackKind) -> Result<u64> {
	Ok(c.prepare_cached("SELECT count FROM stacks WHERE owner_kind = ?1 AND owner = ?2 AND kind = ?3")?
		.query_row(params![o.kind as i64, o.id, k.0], |r| r.get::<_, i64>(0))
		.optional()?
		.unwrap_or(0) as u64)
}

pub fn stacks(c: &Connection, o: &Owner) -> Result<Vec<(StackKind, u64)>> {
	let mut st = c.prepare_cached("SELECT kind, count FROM stacks WHERE owner_kind = ?1 AND owner = ?2 ORDER BY kind")?;
	let v = st
		.query_map(params![o.kind as i64, o.id], |r| Ok((StackKind(r.get(0)?), r.get::<_, i64>(1)? as u64)))?
		.collect::<rusqlite::Result<Vec<_>>>()?;
	Ok(v)
}

/// The cards an account has learned from pages (the deck cards 12 to 29 it owns beyond its level's), ascending.
pub fn owned_cards(c: &Connection, account: AccountId) -> Result<Vec<u16>> {
	let mut st = c.prepare_cached("SELECT card FROM owned_cards WHERE account = ?1 ORDER BY card")?;
	Ok(st.query_map([account], |r| r.get::<_, u16>(0))?.collect::<rusqlite::Result<Vec<_>>>()?)
}

/// The feats a hero has earned (`types::feats`), ascending.
pub fn feats(c: &Connection, hero: HeroId) -> Result<Vec<u8>> {
	let mut st = c.prepare_cached("SELECT feat FROM feats WHERE hero = ?1 ORDER BY feat")?;
	Ok(st.query_map([hero], |r| r.get::<_, u8>(0))?.collect::<rusqlite::Result<Vec<_>>>()?)
}

pub fn entitlements(c: &Connection, account: AccountId) -> Result<Vec<(EntitlementKind, u32)>> {
	let mut st = c.prepare_cached("SELECT kind, count FROM entitlements WHERE account = ?1 ORDER BY kind")?;
	let v = st
		.query_map([account], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, u32>(1)?)))?
		.collect::<rusqlite::Result<Vec<_>>>()?;
	Ok(v.into_iter().filter_map(|(k, n)| EntitlementKind::from_i64(k).map(|k| (k, n))).collect())
}

/// The stored reply of a request, if it was recorded.
pub fn request_reply(c: &Connection, id: RequestId) -> Result<Option<(i64, String, i64, i64)>> {
	Ok(c.prepare_cached("SELECT args, reply, ledger_first, ledger_last FROM requests WHERE id = ?1")?
		.query_row([&id.to_be_bytes()[..]], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)))
		.optional()?)
}

fn q1(c: &Connection, sql: &str) -> Result<i64> {
	Ok(c.query_row(sql, [], |r| r.get::<_, Option<i64>>(0))?.unwrap_or(0))
}

pub fn stats(c: &Connection) -> Result<Stats> {
	let mut h: Vec<u8> = Vec::new();
	{
		let mut st = c.prepare(&format!("SELECT {ITEM_COLS} FROM items ORDER BY id"))?;
		let rows = st.query_map([], item_from_row)?;
		for it in rows {
			let it = it?;
			h.extend_from_slice(format!("{} {} {} {:?}|", it.id, spec_data(&it.spec), it.place, it.socketed).as_bytes());
		}
		let mut st = c.prepare("SELECT owner_kind, owner, kind, count FROM stacks WHERE count > 0 ORDER BY 1, 2, 3")?;
		let mut rows = st.query([])?;
		while let Some(r) = rows.next()? {
			let v: (i64, i64, i64, i64) = (r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?);
			h.extend_from_slice(format!("{v:?}").as_bytes());
		}
	}
	let page_count = q1(c, "PRAGMA page_count")?;
	let page_size = q1(c, "PRAGMA page_size")?;
	Ok(Stats {
		schema_version: crate::schema::version(c)?,
		accounts: q1(c, "SELECT count(*) FROM accounts")?,
		heroes: q1(c, "SELECT count(*) FROM heroes WHERE deleted_at IS NULL")?,
		deleted_heroes: q1(c, "SELECT count(*) FROM heroes WHERE deleted_at IS NOT NULL")?,
		items: q1(c, "SELECT count(*) FROM items")?,
		stacks: q1(c, "SELECT count(*) FROM stacks WHERE count > 0")?,
		coin: q1(c, "SELECT sum(count) FROM stacks WHERE kind = 1")?,
		ledger_rows: q1(c, "SELECT count(*) FROM ledger")?,
		requests: q1(c, "SELECT count(*) FROM requests")?,
		db_bytes: page_count * page_size,
		digest: fnv64(&h),
	})
}

// ---------------------------------------------------------------------------------------------------------------
// verify

#[derive(Clone, Debug, PartialEq, Eq)]
struct RItem {
	place: (i64, i64, i64, i64),
	spec: String,
	socks: [Option<i64>; 2],
	origin_account: i64,
	origin_hero: Option<i64>,
	mint_seq: i64,
}

struct LedgerRow {
	seq: i64,
	op: String,
	item: Option<i64>,
	stack: Option<i64>,
	from: Option<(i64, i64, Option<i64>, Option<i64>)>,
	to: Option<(i64, i64, Option<i64>, Option<i64>)>,
	to_acct: Option<i64>,
	count: i64,
	data: String,
}

fn cols4(k: Option<i64>, o: Option<i64>, t: Option<i64>, s: Option<i64>) -> Option<(i64, i64, Option<i64>, Option<i64>)> {
	Some((k?, o?, t, s))
}

fn full_place(p: Option<(i64, i64, Option<i64>, Option<i64>)>) -> Option<(i64, i64, i64, i64)> {
	let p = p?;
	Some((p.0, p.1, p.2?, p.3?))
}

/// Replays the whole ledger from an empty state and returns the items and nonzero stacks it implies.
fn replay(c: &Connection, problems: &mut Vec<String>) -> Result<(BTreeMap<i64, RItem>, BTreeMap<(i64, i64, i64), i64>, i64)> {
	let mut items: BTreeMap<i64, RItem> = BTreeMap::new();
	let mut stacks: BTreeMap<(i64, i64, i64), i64> = BTreeMap::new();
	let mut st = c.prepare(
		"SELECT seq, op, item, stack_kind, from_kind, from_owner, from_tab, from_slot, to_kind, to_owner, to_tab, \
		to_slot, to_acct, count, data FROM ledger ORDER BY seq",
	)?;
	let mut rows = st.query([])?;
	let mut n = 0i64;
	let bad = |problems: &mut Vec<String>, s: String| {
		if problems.len() < 50 {
			problems.push(s);
		}
	};
	while let Some(r) = rows.next()? {
		n += 1;
		let row = LedgerRow {
			seq: r.get(0)?,
			op: r.get(1)?,
			item: r.get(2)?,
			stack: r.get(3)?,
			from: cols4(r.get(4)?, r.get(5)?, r.get(6)?, r.get(7)?),
			to: cols4(r.get(8)?, r.get(9)?, r.get(10)?, r.get(11)?),
			to_acct: r.get(12)?,
			count: r.get(13)?,
			data: r.get(14)?,
		};
		if let Some(id) = row.item {
			let from = full_place(row.from);
			let to = full_place(row.to);
			match row.op.as_str() {
				"MINT" => {
					let Some(to) = to else {
						bad(problems, format!("ledger {}: mint with no place", row.seq));
						continue;
					};
					let origin_hero = if matches!(to.0, 1 | 2 | 4) { Some(to.1) } else { None };
					let it = RItem {
						place: to,
						spec: row.data.clone(),
						socks: [None, None],
						origin_account: row.to_acct.unwrap_or(0),
						origin_hero,
						mint_seq: row.seq,
					};
					if items.insert(id, it).is_some() {
						bad(problems, format!("ledger {}: item {id} minted twice", row.seq));
					}
				}
				"MOVE" | "TRADE" => match items.get_mut(&id) {
					Some(it) if Some(it.place) == from && to.is_some() => it.place = to.unwrap(),
					_ => bad(problems, format!("ledger {}: move of item {id} not from its place", row.seq)),
				},
				"DESTROY" | "CLAWBACK" if row.stack.is_none() => match items.get(&id) {
					Some(it) if Some(it.place) == from => {
						items.remove(&id);
					}
					_ => bad(problems, format!("ledger {}: removal of item {id} not at its place", row.seq)),
				},
				"SOCKET" | "UNSOCKET" | "CLAWBACK" => {
					let idx: usize = row.data.trim().parse().unwrap_or(9);
					match items.get_mut(&id) {
						Some(it) if idx < 2 => {
							let want_full = row.op == "SOCKET";
							if it.socks[idx].is_some() == want_full {
								bad(problems, format!("ledger {}: socket {idx} of item {id} in the wrong state", row.seq));
							}
							it.socks[idx] = if want_full { row.stack } else { None };
						}
						_ => bad(problems, format!("ledger {}: socket row for missing item {id}", row.seq)),
					}
				}
				_ => bad(problems, format!("ledger {}: unknown item op {}", row.seq, row.op)),
			}
		} else if let Some(k) = row.stack {
			if row.count <= 0 {
				bad(problems, format!("ledger {}: stack row with count {}", row.seq, row.count));
			}
			if let Some(f) = row.from {
				let e = stacks.entry((f.0, f.1, k)).or_insert(0);
				*e -= row.count;
				if *e < 0 {
					bad(problems, format!("ledger {}: stack ({}, {}, {k}) below zero in replay", row.seq, f.0, f.1));
				}
			}
			if let Some(t) = row.to {
				*stacks.entry((t.0, t.1, k)).or_insert(0) += row.count;
			}
		}
	}
	stacks.retain(|_, v| *v != 0);
	Ok((items, stacks, n))
}

/// Checks every invariant. Run inside one read transaction for a consistent picture.
pub fn verify(c: &Connection) -> Result<VerifyReport> {
	c.execute_batch("BEGIN")?;
	let r = verify_inner(c);
	let _ = c.execute_batch("COMMIT");
	r
}

fn verify_inner(c: &Connection) -> Result<VerifyReport> {
	let mut rep = VerifyReport::default();
	let p = &mut rep.problems;
	let add = |p: &mut Vec<String>, s: String| {
		if p.len() < 100 {
			p.push(s);
		}
	};
	let qc: String = c.query_row("PRAGMA quick_check", [], |r| r.get(0))?;
	if qc != "ok" {
		add(p, format!("quick_check: {qc}"));
	}
	{
		let mut st = c.prepare("PRAGMA foreign_key_check")?;
		let mut rows = st.query([])?;
		if let Some(r) = rows.next()? {
			add(p, format!("foreign key broken in {}", r.get::<_, String>(0)?));
		}
	}
	let checks: [(&str, &str); 14] = [
		(
			"two items in one place",
			"SELECT count(*) FROM (SELECT 1 FROM items GROUP BY place_kind, place_owner, place_tab, place_slot HAVING count(*) > 1)",
		),
		("an item left in trade staging", "SELECT count(*) FROM items WHERE place_kind = 6 AND place_owner = 0"),
		("a bag slot out of range", "SELECT count(*) FROM items WHERE place_kind = 1 AND (place_slot >= 40 OR place_tab <> 0)"),
		("a worn item in the wrong slot", "SELECT count(*) FROM items WHERE place_kind = 2 AND (place_slot <> gear_slot OR place_tab <> 0)"),
		(
			"a worn item above the hero's level",
			"SELECT count(*) FROM items i JOIN heroes h ON h.id = i.place_owner WHERE i.place_kind = 2 AND i.item_level > h.class_level",
		),
		("a bank slot out of range", "SELECT count(*) FROM items WHERE place_kind = 3 AND place_slot >= 100"),
		(
			"a bank tab not open",
			"SELECT count(*) FROM items i WHERE place_kind = 3 AND place_tab >= 1 + coalesce((SELECT count FROM entitlements e \
			WHERE e.account = i.place_owner AND e.kind = 1), 0)",
		),
		(
			"an item of a hero that does not exist",
			"SELECT count(*) FROM items WHERE place_kind IN (1, 2, 4) AND place_owner NOT IN (SELECT id FROM heroes)",
		),
		(
			"an item of an account that does not exist",
			"SELECT count(*) FROM items WHERE place_kind IN (3, 7) AND place_owner NOT IN (SELECT id FROM accounts)",
		),
		("a stack below zero", "SELECT count(*) FROM stacks WHERE count < 0"),
		("a stack held by worn gear", "SELECT count(*) FROM stacks WHERE owner_kind = 2"),
		("a house slot out of range", "SELECT count(*) FROM items WHERE place_kind = 7 AND place_slot >= 200"),
		("a guild slot out of range", "SELECT count(*) FROM items WHERE place_kind = 8 AND (place_slot >= 100 OR place_tab >= 8)"),
		(
			"a bag over 40 slots",
			"SELECT count(*) FROM (SELECT h.id, (SELECT count(*) FROM items WHERE place_kind = 1 AND place_owner = h.id) + \
			(SELECT count(*) FROM stacks WHERE owner_kind = 1 AND owner = h.id AND count > 0 AND ((kind BETWEEN 100 AND 199) \
			OR (kind BETWEEN 2000 AND 2999) OR (kind BETWEEN 3000 AND 3099) OR (kind BETWEEN 4000 AND 4099) OR \
			(kind BETWEEN 5000 AND 9999))) AS used FROM heroes h) WHERE used > 40",
		),
	];
	for (what, sql) in checks {
		let n = q1(c, sql)?;
		if n > 0 {
			add(p, format!("{what}: {n}"));
		}
	}
	let over = q1(
		c,
		"SELECT count(*) FROM accounts a WHERE (SELECT count(*) FROM heroes h WHERE h.account = a.id AND h.deleted_at IS NULL) > \
		3 + coalesce((SELECT count FROM entitlements e WHERE e.account = a.id AND e.kind = 2), 0)",
	)?;
	if over > 0 {
		add(p, format!("accounts over their hero slots: {over}"));
	}
	// sockets hold only socketable kinds and only within the item's sockets
	let badsock = q1(
		c,
		"SELECT count(*) FROM items WHERE (sock0 IS NOT NULL AND (sockets < 1 OR NOT ((sock0 BETWEEN 2000 AND 2999) OR \
		(sock0 BETWEEN 5000 AND 9999)))) OR (sock1 IS NOT NULL AND (sockets < 2 OR NOT ((sock1 BETWEEN 2000 AND 2999) OR \
		(sock1 BETWEEN 5000 AND 9999))))",
	)?;
	if badsock > 0 {
		add(p, format!("bad socket contents: {badsock}"));
	}

	crate::parcels::check(c, p)?;

	// replay
	let (ritems, rstacks, nrows) = replay(c, p)?;
	rep.ledger_rows = nrows;
	let mut cur_items: BTreeMap<i64, RItem> = BTreeMap::new();
	{
		let mut st = c.prepare(&format!("SELECT {ITEM_COLS} FROM items ORDER BY id"))?;
		let rows = st.query_map([], item_from_row)?;
		for it in rows {
			let it = it?;
			let mut socks = [None, None];
			for (i, s) in it.socketed.iter().enumerate() {
				socks[i] = s.map(|k| k.0 as i64);
			}
			cur_items.insert(
				it.id,
				RItem {
					place: (it.place.kind as i64, it.place.owner, it.place.tab as i64, it.place.slot as i64),
					spec: spec_data(&it.spec),
					socks,
					origin_account: it.origin_account,
					origin_hero: it.origin_hero,
					mint_seq: it.mint_seq,
				},
			);
		}
	}
	rep.items = cur_items.len() as i64;
	if cur_items != ritems {
		let mut shown = 0;
		for (id, it) in &cur_items {
			if ritems.get(id) != Some(it) && shown < 10 {
				add(p, format!("item {id} differs from the ledger: now {it:?}, ledger {:?}", ritems.get(id)));
				shown += 1;
			}
		}
		for id in ritems.keys() {
			if !cur_items.contains_key(id) && shown < 10 {
				add(p, format!("item {id} is in the ledger but not in items"));
				shown += 1;
			}
		}
	}
	let mut cur_stacks: BTreeMap<(i64, i64, i64), i64> = BTreeMap::new();
	{
		let mut st = c.prepare("SELECT owner_kind, owner, kind, count FROM stacks WHERE count <> 0")?;
		let mut rows = st.query([])?;
		while let Some(r) = rows.next()? {
			cur_stacks.insert((r.get(0)?, r.get(1)?, r.get(2)?), r.get(3)?);
		}
	}
	rep.stacks = cur_stacks.len() as i64;
	if cur_stacks != rstacks {
		let keys: BTreeSet<_> = cur_stacks.keys().chain(rstacks.keys()).copied().collect();
		let mut shown = 0;
		for k in keys {
			if cur_stacks.get(&k) != rstacks.get(&k) && shown < 10 {
				add(p, format!("stack {k:?} is {:?}, the ledger says {:?}", cur_stacks.get(&k), rstacks.get(&k)));
				shown += 1;
			}
		}
	}

	// each request was applied once: its ledger rows fill exactly its recorded range
	rep.requests = q1(c, "SELECT count(*) FROM requests")?;
	let mut ranges: HashMap<Vec<u8>, (i64, i64)> = HashMap::new();
	{
		let mut st = c.prepare("SELECT id, ledger_first, ledger_last, reply FROM requests")?;
		let mut rows = st.query([])?;
		while let Some(r) = rows.next()? {
			let id: Vec<u8> = r.get(0)?;
			let reply: String = r.get(3)?;
			if Dec::new(&reply).result().is_err() {
				add(p, format!("request {} has an unreadable reply", hex(&id)));
			}
			ranges.insert(id, (r.get(1)?, r.get(2)?));
		}
	}
	{
		let mut st = c.prepare("SELECT request, min(seq), max(seq), count(*) FROM ledger GROUP BY request")?;
		let mut rows = st.query([])?;
		let mut seen = 0usize;
		while let Some(r) = rows.next()? {
			let id: Vec<u8> = r.get(0)?;
			let (lo, hi, n): (i64, i64, i64) = (r.get(1)?, r.get(2)?, r.get(3)?);
			seen += 1;
			match ranges.get(&id) {
				None => add(p, format!("ledger rows of request {} with no request record", hex(&id))),
				Some((f, l)) => {
					if *f != lo || *l != hi || n != hi - lo + 1 {
						add(p, format!("request {}: ledger rows {lo}..{hi} ({n}) but recorded {f}..{l}", hex(&id)));
					}
				}
			}
		}
		let nonempty = ranges.values().filter(|(f, l)| l >= f).count();
		if nonempty != seen {
			add(p, format!("{nonempty} requests record ledger rows but {seen} have them"));
		}
	}
	Ok(rep)
}

pub fn hex(b: &[u8]) -> String {
	b.iter().map(|x| format!("{x:02x}")).collect()
}

// ---------------------------------------------------------------------------------------------------------------
// trace

fn party_cols(acct: Option<i64>, kind: Option<i64>, owner: Option<i64>) -> Option<Party> {
	if let Some(a) = acct {
		return Some(Party::Account(a));
	}
	match PlaceKind::from_i64(kind?)? {
		PlaceKind::Guild => Some(Party::Guild(owner?)),
		PlaceKind::Market => Some(Party::Market(owner?)),
		PlaceKind::Trade => Some(Party::Trade(owner?)),
		_ => None,
	}
}

/// The containers holding a party's stacks.
pub fn party_owners(c: &Connection, p: Party) -> Result<Vec<Owner>> {
	Ok(match p {
		Party::Account(a) => {
			let mut v = vec![Owner::bank(a), Owner { kind: PlaceKind::House, id: a }];
			for h in heroes(c, a, true)? {
				v.push(Owner::bag(h.id));
				v.push(Owner { kind: PlaceKind::Mail, id: h.id });
			}
			v
		}
		Party::Guild(g) => vec![Owner { kind: PlaceKind::Guild, id: g }],
		Party::Market(m) => vec![Owner { kind: PlaceKind::Market, id: m }],
		Party::Trade(t) => vec![Owner { kind: PlaceKind::Trade, id: t }],
	})
}

struct Move {
	seq: i64,
	item: Option<i64>,
	stack: Option<i64>,
	from: Option<Party>,
	to: Option<Party>,
	to_kind: Option<i64>,
	count: i64,
	minted: bool,
	op: String,
}

const MOVE_COLS: &str = "seq, item, stack_kind, from_acct, from_kind, from_owner, to_acct, to_kind, to_owner, count, minted, op";

fn move_row(r: &rusqlite::Row) -> rusqlite::Result<Move> {
	Ok(Move {
		seq: r.get(0)?,
		item: r.get(1)?,
		stack: r.get(2)?,
		from: party_cols(r.get(3)?, r.get(4)?, r.get(5)?),
		to: party_cols(r.get(6)?, r.get(7)?, r.get(8)?),
		to_kind: r.get(7)?,
		count: r.get(9)?,
		minted: r.get::<_, i64>(10)? != 0,
		op: r.get(11)?,
	})
}

/// Ledger rows leaving a party (from its side), in seq order.
fn rows_from(c: &Connection, p: Party) -> Result<Vec<Move>> {
	let (sql, a, b) = match p {
		Party::Account(a) => (format!("SELECT {MOVE_COLS} FROM ledger WHERE from_acct = ?1 AND ?2 = ?2 ORDER BY seq"), a, 0),
		Party::Guild(g) => (format!("SELECT {MOVE_COLS} FROM ledger WHERE from_kind = 8 AND from_owner = ?1 AND ?2 = ?2 ORDER BY seq"), g, 0),
		Party::Market(m) => (format!("SELECT {MOVE_COLS} FROM ledger WHERE from_kind = ?2 AND from_owner = ?1 ORDER BY seq"), m, 5),
		Party::Trade(t) => (format!("SELECT {MOVE_COLS} FROM ledger WHERE from_kind = ?2 AND from_owner = ?1 ORDER BY seq"), t, 6),
	};
	let mut st = c.prepare_cached(&sql)?;
	let v = st.query_map(params![a, b], move_row)?.collect::<rusqlite::Result<Vec<_>>>()?;
	Ok(v)
}

pub fn trace(c: &Connection, account: AccountId) -> Result<Trace> {
	c.execute_batch("BEGIN")?;
	let r = trace_inner(c, account);
	let _ = c.execute_batch("COMMIT");
	r
}

fn trace_inner(c: &Connection, account: AccountId) -> Result<Trace> {
	let me = Party::Account(account);
	let mut out = Trace { account, ..Default::default() };
	{
		let mut st = c.prepare_cached(
			"SELECT seq, item, to_kind, to_owner FROM ledger WHERE to_acct = ?1 AND op = 'MINT' AND item IS NOT NULL ORDER BY seq",
		)?;
		let rows = st
			.query_map([account], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?, r.get::<_, i64>(3)?)))?
			.collect::<rusqlite::Result<Vec<_>>>()?;
		for (seq, id, tk, to) in rows {
			let cur = item(c, id)?;
			let holder = match &cur {
				Some(it) => party_of(c, it.place.kind, it.place.owner).ok(),
				None => None,
			};
			out.items.push(TracedItem {
				item: id,
				mint_seq: seq,
				origin_hero: if matches!(tk, 1 | 2 | 4) { Some(to) } else { None },
				place: cur.map(|i| i.place),
				holder,
			});
		}
	}
	let mut by_kind: BTreeMap<u32, (TracedStack, BTreeMap<Party, u64>, BTreeMap<Party, u64>)> = BTreeMap::new();
	let mut st = c.prepare_cached(&format!(
		"SELECT {MOVE_COLS} FROM ledger WHERE item IS NULL AND stack_kind IS NOT NULL AND (from_acct = ?1 OR to_acct = ?1) ORDER BY seq"
	))?;
	let rows = st.query_map([account], move_row)?.collect::<rusqlite::Result<Vec<_>>>()?;
	for m in rows {
		let k = m.stack.unwrap_or(0) as u32;
		let e = by_kind.entry(k).or_insert_with(|| (TracedStack { kind: StackKind(k), ..Default::default() }, BTreeMap::new(), BTreeMap::new()));
		let n = m.count.max(0) as u64;
		match (m.from, m.to) {
			(None, Some(t)) if t == me => {
				if m.minted {
					e.0.minted += n;
				} else {
					*e.2.entry(Party::Account(0)).or_insert(0) += n;
				}
			}
			(Some(f), None) if f == me => e.0.spent += n,
			(Some(f), Some(t)) if f == me && t != me => *e.1.entry(t).or_insert(0) += n,
			(Some(f), Some(t)) if t == me && f != me => *e.2.entry(f).or_insert(0) += n,
			_ => {}
		}
	}
	for (k, (mut ts, sent, recv)) in by_kind {
		ts.sent = sent.into_iter().collect();
		ts.received = recv.into_iter().collect();
		let mut holds = 0;
		for o in party_owners(c, me)? {
			holds += stack(c, &o, StackKind(k))?;
		}
		ts.holds = holds;
		out.stacks.push(ts);
	}
	// kinds held but never moved through this account's ledger rows (none should exist; shown for completeness)
	Ok(out)
}

#[derive(Clone)]
enum Taint {
	All,
	Some { items: HashMap<i64, i64>, kinds: HashMap<i64, i64> },
}

/// Follows what the account sent, then what the receivers sent of it, to `depth` hops.
pub fn trace_forward(c: &Connection, account: AccountId, depth: u32) -> Result<Vec<Hop>> {
	c.execute_batch("BEGIN")?;
	let r = forward_inner(c, account, depth);
	let _ = c.execute_batch("COMMIT");
	r
}

fn forward_inner(c: &Connection, account: AccountId, depth: u32) -> Result<Vec<Hop>> {
	let mut hops = Vec::new();
	let mut seen: BTreeSet<i64> = BTreeSet::new();
	let mut level: BTreeMap<Party, Taint> = BTreeMap::new();
	level.insert(Party::Account(account), Taint::All);
	for d in 1..=depth {
		let mut next: BTreeMap<Party, Taint> = BTreeMap::new();
		for (p, taint) in &level {
			for m in rows_from(c, *p)? {
				let Some(to) = m.to else { continue };
				if to == *p || m.to_kind.is_none() || !(m.op == "MOVE" || m.op == "TRADE" || m.op == "TRANSFER") {
					continue;
				}
				let follows = match taint {
					Taint::All => true,
					Taint::Some { items, kinds } => match (m.item, m.stack) {
						(Some(i), _) => items.get(&i).is_some_and(|s| m.seq > *s),
						(None, Some(k)) => kinds.get(&k).is_some_and(|s| m.seq > *s),
						_ => false,
					},
				};
				if !follows || !seen.insert(m.seq) {
					continue;
				}
				hops.push(Hop {
					depth: d,
					seq: m.seq,
					from: *p,
					to,
					item: m.item,
					stack: m.stack.map(|k| StackKind(k as u32)),
					count: m.count.max(0) as u64,
				});
				let e = next.entry(to).or_insert_with(|| Taint::Some { items: HashMap::new(), kinds: HashMap::new() });
				if let Taint::Some { items, kinds } = e {
					match (m.item, m.stack) {
						(Some(i), _) => {
							let s = items.entry(i).or_insert(m.seq);
							*s = (*s).min(m.seq);
						}
						(None, Some(k)) => {
							let s = kinds.entry(k).or_insert(m.seq);
							*s = (*s).min(m.seq);
						}
						_ => {}
					}
				}
			}
		}
		level = next;
		if level.is_empty() {
			break;
		}
	}
	Ok(hops)
}

/// A clawback list for what an account minted after `since_seq`: its items that still exist, wherever they are;
/// for each stack kind, up to the amount minted, taken first from the account's own holdings, then from each
/// party it sent that kind to (up to what it sent).
pub fn clawback_plan(c: &Connection, account: AccountId, since_seq: i64) -> Result<ClawbackPlan> {
	c.execute_batch("BEGIN")?;
	let r = plan_inner(c, account, since_seq);
	let _ = c.execute_batch("COMMIT");
	r
}

fn plan_inner(c: &Connection, account: AccountId, since: i64) -> Result<ClawbackPlan> {
	let me = Party::Account(account);
	let mut plan = ClawbackPlan::default();
	{
		let mut st = c.prepare_cached(
			"SELECT l.item FROM ledger l JOIN items i ON i.id = l.item WHERE l.to_acct = ?1 AND l.op = 'MINT' AND l.seq > ?2 ORDER BY l.seq",
		)?;
		plan.items = st.query_map(params![account, since], |r| r.get(0))?.collect::<rusqlite::Result<Vec<_>>>()?;
	}
	let mut minted: BTreeMap<i64, u64> = BTreeMap::new();
	let mut sent: BTreeMap<i64, BTreeMap<Party, u64>> = BTreeMap::new();
	{
		let mut st = c.prepare_cached(&format!(
			"SELECT {MOVE_COLS} FROM ledger WHERE item IS NULL AND stack_kind IS NOT NULL AND seq > ?2 AND (from_acct = ?1 OR to_acct = ?1) ORDER BY seq"
		))?;
		let rows = st.query_map(params![account, since], move_row)?.collect::<rusqlite::Result<Vec<_>>>()?;
		for m in rows {
			let k = m.stack.unwrap_or(0);
			match (m.from, m.to) {
				(None, Some(t)) if t == me && m.minted => *minted.entry(k).or_insert(0) += m.count as u64,
				(Some(f), Some(t)) if f == me && t != me => *sent.entry(k).or_default().entry(t).or_insert(0) += m.count as u64,
				_ => {}
			}
		}
	}
	for (k, m) in minted {
		let kind = StackKind(k as u32);
		let mut left = m;
		let take_from = |p: Party, cap: u64, left: &mut u64, plan: &mut ClawbackPlan| -> Result<()> {
			let mut cap = cap.min(*left);
			for o in party_owners(c, p)? {
				if cap == 0 {
					break;
				}
				let have = stack(c, &o, kind)?;
				let t = have.min(cap);
				if t > 0 {
					plan.stacks.push((o, kind, t));
					cap -= t;
					*left -= t;
				}
			}
			Ok(())
		};
		take_from(me, u64::MAX, &mut left, &mut plan)?;
		for (p, n) in sent.get(&k).cloned().unwrap_or_default() {
			if left == 0 {
				break;
			}
			take_from(p, n, &mut left, &mut plan)?;
		}
	}
	// merge repeated owners
	let mut merged: BTreeMap<(Owner, StackKind), u64> = BTreeMap::new();
	for (o, k, n) in plan.stacks.drain(..) {
		*merged.entry((o, k)).or_insert(0) += n;
	}
	plan.stacks = merged.into_iter().map(|((o, k), n)| (o, k, n)).collect();
	Ok(plan)
}

/// Coin by ledger op and reason: (op, reason, minted, rows, total). The faucets are the minted CREDIT rows and the
/// sinks the DEBIT and CLAWBACK rows; `TRANSFER` rows (between parties) net to zero over the whole game.
pub fn coin_flows(c: &Connection) -> Result<Vec<(String, String, bool, i64, i64)>> {
	let mut st = c.prepare(
		"SELECT op, reason, minted, count(*), sum(count) FROM ledger WHERE stack_kind = 1 GROUP BY op, reason, minted ORDER BY op, reason",
	)?;
	let v = st
		.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get::<_, i64>(2)? != 0, r.get(3)?, r.get(4)?)))?
		.collect::<rusqlite::Result<Vec<_>>>()?;
	Ok(v)
}
