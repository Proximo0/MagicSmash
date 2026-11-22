//! Parcels (job E1): the escrow behind the market and letters. A parcel's things sit in the MARKET place (items,
//! slots 0 to 7) and under the MARKET stack owner, both keyed by the parcel id, and the `parcels` row says who
//! sent it, to whom, for what price and until when. Three commands, all the server's (the gateway checks
//! consent): `put` moves things from a hero's bag into escrow, `take` pays and delivers, `give_back` returns the
//! things to the sender's mail. Each is one transaction with ledger rows (MOVE and TRANSFER, which the replay
//! already understands, and a DEBIT for each fee and tax), so nothing is ever in two places or in none.

use crate::ops::*;
use crate::types::limits::*;
use crate::types::*;
use rusqlite::{Connection, OptionalExtension, ToSql, params};

struct Row {
	kind: ParcelKind,
	from_hero: HeroId,
	to_hero: Option<HeroId>,
	price: u64,
	expires: Millis,
}

fn load(t: &Tx, id: i64) -> Result<Row> {
	t.one("SELECT id, kind, from_hero, to_hero, price, expires FROM parcels WHERE id = ?1", [id], |r| {
		Ok(Row {
			kind: ParcelKind::from_i64(r.get(1)?).unwrap_or(ParcelKind::Letter),
			from_hero: r.get(2)?,
			to_hero: r.get(3)?,
			price: r.get::<_, i64>(4)? as u64,
			expires: r.get(5)?,
		})
	})?
	.ok_or_else(|| Error::Missing(format!("parcel {id}")))
}

#[allow(clippy::too_many_arguments)]
pub fn put(
	t: &mut Tx,
	kind: ParcelKind,
	from: HeroId,
	to: Option<HeroId>,
	items: &[ItemId],
	stacks: &[(StackKind, u64)],
	price: u64,
	fee: u64,
	expires: Millis,
	text: &str,
) -> Result<Reply> {
	let now = t.req.now;
	let h = t.live_hero(from)?;
	let from_party = Party::Account(h.account);
	if items.len() + stacks.len() > PARCEL_ENTRIES || items.len() + stacks.len() == 0 {
		return Err(inv(format!("a parcel holds 1 to {PARCEL_ENTRIES} entries")));
	}
	if price > PARCEL_PRICE_MAX || fee > PARCEL_PRICE_MAX {
		return Err(inv("price"));
	}
	if expires <= now {
		return Err(inv("a parcel must end after it starts"));
	}
	if text.len() > PARCEL_TEXT_MAX {
		return Err(inv("text too long"));
	}
	let mut seen = std::collections::BTreeSet::new();
	for (k, n) in stacks {
		Tx::check_kind(*k, *n)?;
		if !seen.insert(k.0) {
			return Err(inv("a stack kind listed twice"));
		}
	}
	let mut ids = std::collections::BTreeSet::new();
	for id in items {
		if !ids.insert(*id) {
			return Err(inv(format!("item {id} listed twice")));
		}
	}
	let to_acct = match (kind, to) {
		(ParcelKind::Listing, None) => {
			if price == 0 || items.len() + stacks.len() != 1 {
				return Err(inv("a listing is one item or one stack for a price"));
			}
			if stacks.iter().any(|(k, _)| *k == StackKind::COIN) {
				return Err(inv("coin is not sold for coin"));
			}
			None
		}
		(ParcelKind::Listing, Some(_)) => return Err(inv("a listing has no addressee")),
		(ParcelKind::Letter, Some(to)) => {
			if to == from {
				return Err(inv("a letter goes to another hero"));
			}
			let th = t.live_hero(to)?;
			Some(th.account)
		}
		(ParcelKind::Letter, None) => return Err(inv("a letter needs an addressee")),
	};
	// the flags and the self-found rule, before anything moves
	match to_acct {
		None => t.check_flow(from_party, Party::Market(0))?,
		Some(a) => t.check_flow(from_party, Party::Account(a))?,
	}
	if t.is_self_found(from)? || to.map(|x| t.is_self_found(x)).transpose()?.unwrap_or(false) {
		return Err(Error::Refused);
	}
	let (open, cap, what): (i64, i64, &str) = match kind {
		ParcelKind::Listing => (
			t.one("SELECT count(*) FROM parcels WHERE kind = 1 AND from_hero = ?1", [from], |r| r.get(0))?.unwrap_or(0),
			LISTINGS_PER_HERO,
			"open listings",
		),
		ParcelKind::Letter => (
			t.one("SELECT count(*) FROM parcels WHERE kind = 2 AND to_hero = ?1", [to.unwrap_or(0)], |r| r.get(0))?.unwrap_or(0),
			LETTERS_PER_HERO,
			"letters waiting",
		),
	};
	if open >= cap {
		return Err(Error::Full(format!("{what} of the hero")));
	}
	// the fee is taken first (so a hero short of it fails before anything moves)
	let bag = Owner::bag(from);
	if fee > 0 {
		t.stack_sub(&bag, StackKind::COIN, fee)?;
		t.debit_row("DEBIT", &bag, from_party, StackKind::COIN, fee, if kind == ParcelKind::Listing { "listing fee" } else { "postage" })?;
	}
	// load and check what leaves the bag before anything is written
	let mut loaded = Vec::with_capacity(items.len());
	for item in items {
		let it = t.carried(from, *item, false)?;
		if it.spec.bound {
			return Err(Error::Bound(*item));
		}
		loaded.push(it);
	}
	for (k, n) in stacks {
		let have = t.stack_get(&bag, *k)?;
		if have < *n {
			return Err(Error::Insufficient { kind: *k, have, want: *n });
		}
	}
	// a listing's entry is kept in the parcel row for the search
	let (gs, lv, ra, sk) = match (kind, loaded.first(), stacks.first()) {
		(ParcelKind::Listing, Some(it), _) => (Some(it.spec.gear_slot), Some(it.spec.item_level), Some(it.spec.rarity), None),
		(ParcelKind::Listing, None, Some((k, _))) => (None, None, None, Some(k.0)),
		_ => (None, None, None, None),
	};
	t.exec(
		"INSERT INTO parcels (kind, from_hero, to_hero, price, created, expires, text, gear_slot, item_level, rarity, stack_kind) \
		VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
		params![kind as i64, from, to, price as i64, now, expires, text, gs, lv, ra, sk],
	)?;
	let id = t.c.last_insert_rowid();
	let esc = Owner { kind: PlaceKind::Market, id };
	for (slot, it) in loaded.iter().enumerate() {
		let p = Place { kind: PlaceKind::Market, owner: id, tab: 0, slot: slot as u32 };
		t.set_place(it.id, &p)?;
		t.move_row("MOVE", it, from_party, &p, Party::Market(id))?;
	}
	for (k, n) in stacks {
		t.stack_sub(&bag, *k, *n)?;
		t.stack_set(&esc, *k, *n)?;
		stack_row(t, &bag, from_party, &esc, Party::Market(id), *k, *n, "")?;
	}
	Ok(Reply::Parcel(id))
}

#[allow(clippy::too_many_arguments)]
fn stack_row(t: &mut Tx, from: &Owner, fp: Party, to: &Owner, tp: Party, k: StackKind, n: u64, reason: &str) -> Result<()> {
	t.ledger(crate::ops::Row {
		op: "TRANSFER",
		stack: Some(k),
		from: Some(owner_cols(from)),
		from_acct: acct_of(fp),
		to: Some(owner_cols(to)),
		to_acct: acct_of(tp),
		count: n,
		reason,
		..Default::default()
	})?;
	Ok(())
}

fn contents(t: &Tx, id: i64) -> Result<(Vec<Item>, Vec<(StackKind, u64)>)> {
	let items = {
		crate::crash::point(crate::crash::Site::Stmt);
		let mut st = t.c.prepare_cached(&format!("SELECT {ITEM_COLS} FROM items WHERE place_kind = 5 AND place_owner = ?1 ORDER BY place_slot"))?;
		st.query_map([id], item_from_row)?.collect::<rusqlite::Result<Vec<_>>>()?
	};
	let stacks = {
		crate::crash::point(crate::crash::Site::Stmt);
		let mut st = t.c.prepare_cached("SELECT kind, count FROM stacks WHERE owner_kind = 5 AND owner = ?1 ORDER BY kind")?;
		st.query_map([id], |r| Ok((StackKind(r.get(0)?), r.get::<_, i64>(1)? as u64)))?.collect::<rusqlite::Result<Vec<_>>>()?
	};
	Ok((items, stacks))
}

pub fn take(t: &mut Tx, parcel: i64, hero: HeroId, tax: u64) -> Result<Reply> {
	let now = t.req.now;
	let p = load(t, parcel)?;
	let taker = t.live_hero(hero)?;
	let seller = t.hero_row(p.from_hero)?;
	if p.expires <= now {
		return Err(Error::Expired);
	}
	match p.kind {
		ParcelKind::Listing => {
			if taker.account == seller.account {
				return Err(inv("a hero cannot buy her own account's listing"));
			}
			if tax > p.price {
				return Err(inv("tax above price"));
			}
		}
		ParcelKind::Letter => {
			if p.to_hero != Some(hero) {
				return Err(Error::NotYours(format!("letter {parcel}")));
			}
			if tax != 0 {
				return Err(inv("a letter carries no tax"));
			}
		}
	}
	let tp = Party::Account(taker.account);
	let sp = Party::Account(seller.account);
	t.check_flow(sp, tp)?;
	if t.is_self_found(hero)? || t.is_self_found(p.from_hero)? {
		return Err(Error::Refused);
	}
	let esc = Owner { kind: PlaceKind::Market, id: parcel };
	let mp = Party::Market(parcel);
	let (items, stacks) = contents(t, parcel)?;
	let bag = Owner::bag(hero);
	// the price first: a buyer who cannot pay changes nothing
	if p.price > 0 {
		let sb = Owner::bag(p.from_hero);
		t.stack_sub(&bag, StackKind::COIN, p.price)?;
		t.stack_add(&sb, StackKind::COIN, p.price)?;
		stack_row(t, &bag, tp, &sb, sp, StackKind::COIN, p.price, if p.kind == ParcelKind::Listing { "sale" } else { "cod" })?;
		if tax > 0 {
			t.stack_sub(&sb, StackKind::COIN, tax)?;
			t.debit_row("DEBIT", &sb, sp, StackKind::COIN, tax, "tax")?;
		}
	}
	for it in &items {
		let (place, party) = t.resolve(&Dest::bag(hero), &it.spec, false)?;
		t.set_place(it.id, &place)?;
		t.move_row("MOVE", it, mp, &place, party)?;
	}
	for (k, n) in &stacks {
		t.stack_sub(&esc, *k, *n)?;
		t.stack_add(&bag, *k, *n)?;
		stack_row(t, &esc, mp, &bag, tp, *k, *n, "")?;
	}
	t.exec("DELETE FROM parcels WHERE id = ?1", [parcel])?;
	Ok(Reply::Done)
}

pub fn give_back(t: &mut Tx, parcel: i64) -> Result<Reply> {
	let p = load(t, parcel)?;
	let sender = t.live_hero(p.from_hero)?;
	let sp = Party::Account(sender.account);
	let esc = Owner { kind: PlaceKind::Market, id: parcel };
	let mp = Party::Market(parcel);
	let mail = Owner { kind: PlaceKind::Mail, id: p.from_hero };
	let (items, stacks) = contents(t, parcel)?;
	for it in &items {
		let (place, party) = t.resolve(&Dest::any(PlaceKind::Mail, p.from_hero), &it.spec, false)?;
		t.set_place(it.id, &place)?;
		t.move_row("MOVE", it, mp, &place, party)?;
	}
	for (k, n) in &stacks {
		t.stack_sub(&esc, *k, *n)?;
		t.stack_add(&mail, *k, *n)?;
		stack_row(t, &esc, mp, &mail, sp, *k, *n, "returned")?;
	}
	t.exec("DELETE FROM parcels WHERE id = ?1", [parcel])?;
	Ok(Reply::Done)
}

// ---- reads

const COLS: &str = "p.id, p.kind, p.from_hero, h.account, p.to_hero, p.price, p.created, p.expires, p.text, h.name";

fn parcel_from_row(r: &rusqlite::Row) -> rusqlite::Result<Parcel> {
	Ok(Parcel {
		id: r.get(0)?,
		kind: ParcelKind::from_i64(r.get(1)?).unwrap_or(ParcelKind::Letter),
		from_hero: r.get(2)?,
		from_account: r.get(3)?,
		to_hero: r.get(4)?,
		price: r.get::<_, i64>(5)? as u64,
		created: r.get(6)?,
		expires: r.get(7)?,
		text: r.get(8)?,
		from_name: r.get(9)?,
		items: Vec::new(),
		stacks: Vec::new(),
	})
}

/// Loads what each parcel holds with two queries (not two a parcel).
fn fill(c: &Connection, mut v: Vec<Parcel>) -> Result<Vec<Parcel>> {
	if v.is_empty() {
		return Ok(v);
	}
	let ids = v.iter().map(|p| p.id.to_string()).collect::<Vec<_>>().join(",");
	let mut items: std::collections::HashMap<i64, Vec<Item>> = std::collections::HashMap::new();
	{
		let mut st = c.prepare(&format!("SELECT {ITEM_COLS} FROM items WHERE place_kind = 5 AND place_owner IN ({ids}) ORDER BY place_slot"))?;
		for it in st.query_map([], item_from_row)? {
			let it = it?;
			items.entry(it.place.owner).or_default().push(it);
		}
	}
	let mut stacks: std::collections::HashMap<i64, Vec<(StackKind, u64)>> = std::collections::HashMap::new();
	{
		let mut st = c.prepare(&format!("SELECT owner, kind, count FROM stacks WHERE owner_kind = 5 AND owner IN ({ids}) ORDER BY kind"))?;
		for r in st.query_map([], |r| Ok((r.get::<_, i64>(0)?, StackKind(r.get(1)?), r.get::<_, i64>(2)? as u64)))? {
			let (o, k, n) = r?;
			stacks.entry(o).or_default().push((k, n));
		}
	}
	for p in &mut v {
		p.items = items.remove(&p.id).unwrap_or_default();
		p.stacks = stacks.remove(&p.id).unwrap_or_default();
	}
	Ok(v)
}

pub fn parcel(c: &Connection, id: i64) -> Result<Option<Parcel>> {
	let one = c
		.prepare_cached(&format!("SELECT {COLS} FROM parcels p JOIN heroes h ON h.id = p.from_hero WHERE p.id = ?1"))?
		.query_row([id], parcel_from_row)
		.optional()?;
	Ok(fill(c, one.into_iter().collect())?.pop())
}

/// What a hero sent and has in escrow: her listings and her letters in transit, oldest first.
pub fn parcels_from(c: &Connection, hero: HeroId) -> Result<Vec<Parcel>> {
	let v = c
		.prepare_cached(&format!("SELECT {COLS} FROM parcels p JOIN heroes h ON h.id = p.from_hero WHERE p.from_hero = ?1 ORDER BY p.id"))?
		.query_map([hero], parcel_from_row)?
		.collect::<rusqlite::Result<Vec<_>>>()?;
	fill(c, v)
}

/// The letters waiting for a hero, oldest first.
pub fn parcels_to(c: &Connection, hero: HeroId) -> Result<Vec<Parcel>> {
	let v = c
		.prepare_cached(&format!("SELECT {COLS} FROM parcels p JOIN heroes h ON h.id = p.from_hero WHERE p.to_hero = ?1 ORDER BY p.id"))?
		.query_map([hero], parcel_from_row)?
		.collect::<rusqlite::Result<Vec<_>>>()?;
	fill(c, v)
}

/// Ids of parcels that ended at or before `now`, oldest end first.
pub fn parcels_due(c: &Connection, now: Millis, limit: u32) -> Result<Vec<i64>> {
	let v = c
		.prepare_cached("SELECT id FROM parcels WHERE expires <= ?1 ORDER BY expires, id LIMIT ?2")?
		.query_map(params![now, limit], |r| r.get(0))?
		.collect::<rusqlite::Result<Vec<_>>>()?;
	Ok(v)
}

/// Open listings, cheapest first. The filters walk the parcel row's own columns (indexed by slot and price).
pub fn listings(c: &Connection, q: &ListingQuery) -> Result<Vec<Parcel>> {
	let mut sql = format!("SELECT {COLS} FROM parcels p JOIN heroes h ON h.id = p.from_hero WHERE p.kind = 1 AND p.expires > ?1");
	let mut args: Vec<Box<dyn ToSql>> = vec![Box::new(q.now)];
	let add = |sql_part: &str, v: Box<dyn ToSql>, sql: &mut String, args: &mut Vec<Box<dyn ToSql>>| {
		args.push(v);
		sql.push_str(&sql_part.replace('?', &format!("?{}", args.len())));
	};
	if let Some(g) = q.gear_slot {
		add(" AND p.gear_slot = ?", Box::new(g), &mut sql, &mut args);
	}
	if let Some(r) = q.rarity_min {
		add(" AND p.rarity >= ?", Box::new(r), &mut sql, &mut args);
	}
	if let Some(l) = q.level_min {
		add(" AND p.item_level >= ?", Box::new(l), &mut sql, &mut args);
	}
	if let Some(l) = q.level_max {
		add(" AND p.item_level <= ?", Box::new(l), &mut sql, &mut args);
	}
	if let Some(k) = q.stack {
		add(" AND p.stack_kind = ?", Box::new(k.0), &mut sql, &mut args);
	}
	if let Some(m) = q.price_max {
		add(" AND p.price <= ?", Box::new(m as i64), &mut sql, &mut args);
	}
	if let Some(h) = q.seller_not {
		add(" AND p.from_hero <> ?", Box::new(h), &mut sql, &mut args);
	}
	args.push(Box::new(q.limit.clamp(1, 500)));
	args.push(Box::new(q.offset));
	sql.push_str(&format!(" ORDER BY p.price, p.id LIMIT ?{} OFFSET ?{}", args.len() - 1, args.len()));
	let refs: Vec<&dyn ToSql> = args.iter().map(|b| b.as_ref()).collect();
	let v = c.prepare_cached(&sql)?.query_map(refs.as_slice(), parcel_from_row)?.collect::<rusqlite::Result<Vec<_>>>()?;
	fill(c, v)
}

/// Verify: every parcel holds something, and nothing sits in escrow without a parcel.
pub fn check(c: &Connection, problems: &mut Vec<String>) -> Result<()> {
	let q = |sql: &str| -> Result<i64> { Ok(c.query_row(sql, [], |r| r.get(0))?) };
	for (what, sql) in [
		("an item in escrow with no parcel", "SELECT count(*) FROM items WHERE place_kind = 5 AND place_owner NOT IN (SELECT id FROM parcels)"),
		("a stack in escrow with no parcel", "SELECT count(*) FROM stacks WHERE owner_kind = 5 AND owner NOT IN (SELECT id FROM parcels)"),
		("an escrow slot out of range", "SELECT count(*) FROM items WHERE place_kind = 5 AND (place_slot >= 8 OR place_tab <> 0)"),
		(
			"a parcel holding nothing",
			"SELECT count(*) FROM parcels p WHERE NOT EXISTS (SELECT 1 FROM items WHERE place_kind = 5 AND place_owner = p.id) \
			AND NOT EXISTS (SELECT 1 FROM stacks WHERE owner_kind = 5 AND owner = p.id)",
		),
		("a listing with more than one entry", "SELECT count(*) FROM parcels p WHERE kind = 1 AND (SELECT count(*) FROM items WHERE place_kind = 5 AND place_owner = p.id) + (SELECT count(*) FROM stacks WHERE owner_kind = 5 AND owner = p.id) <> 1"),
		("a letter with no addressee", "SELECT count(*) FROM parcels WHERE kind = 2 AND to_hero IS NULL"),
	] {
		let n = q(sql)?;
		if n > 0 && problems.len() < 100 {
			problems.push(format!("{what}: {n}"));
		}
	}
	Ok(())
}
