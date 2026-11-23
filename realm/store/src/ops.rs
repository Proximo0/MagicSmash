//! The operations, applied inside the writer's open transaction. Each runs in its own savepoint (the writer's
//! job): an error leaves nothing behind. Every change writes ledger rows here, in the same transaction.

use crate::codec::{Enc, encode_cmd};
use crate::crash::{self, Site};
use crate::types::limits::*;
use crate::types::*;
use rusqlite::{Connection, OptionalExtension, Params, params};

/// The state of one command being applied.
pub struct Tx<'c> {
	pub c: &'c Connection,
	pub req: &'c Request,
	/// the next ledger seq (the writer keeps it across the batch)
	pub seq: i64,
}

#[derive(Clone, Copy, Debug)]
pub struct HeroRow {
	pub id: HeroId,
	pub account: AccountId,
	pub class_level: u16,
	pub deleted_at: Option<Millis>,
}

#[derive(Clone, Copy, Debug)]
pub struct AccountRow {
	pub id: AccountId,
	pub flags: u64,
	pub banned_until: Option<Millis>,
}

/// One ledger row being written.
#[derive(Default)]
pub struct Row<'a> {
	pub op: &'a str,
	pub item: Option<ItemId>,
	pub stack: Option<StackKind>,
	pub from: Option<(PlaceKind, i64, Option<u32>, Option<u32>)>,
	pub from_acct: Option<AccountId>,
	pub to: Option<(PlaceKind, i64, Option<u32>, Option<u32>)>,
	pub to_acct: Option<AccountId>,
	pub count: u64,
	pub minted: bool,
	pub reason: &'a str,
	pub data: String,
}

pub(crate) fn place_cols(p: &Place) -> (PlaceKind, i64, Option<u32>, Option<u32>) {
	(p.kind, p.owner, Some(p.tab), Some(p.slot))
}

pub(crate) fn owner_cols(o: &Owner) -> (PlaceKind, i64, Option<u32>, Option<u32>) {
	(o.kind, o.id, None, None)
}

pub fn spec_lines(lines: &[(u8, u16)]) -> String {
	lines.iter().map(|(s, p)| format!("{s}:{p}")).collect::<Vec<_>>().join(",")
}

pub fn parse_lines(s: &str) -> Vec<(u8, u16)> {
	s.split(',')
		.filter(|x| !x.is_empty())
		.filter_map(|x| {
			let (a, b) = x.split_once(':')?;
			Some((a.parse().ok()?, b.parse().ok()?))
		})
		.collect()
}

pub fn join_nums<T: ToString>(v: &[T]) -> String {
	v.iter().map(|x| x.to_string()).collect::<Vec<_>>().join(",")
}

pub fn split_nums<T: std::str::FromStr>(s: &str) -> Vec<T> {
	s.split(',').filter(|x| !x.is_empty()).filter_map(|x| x.parse().ok()).collect()
}

pub fn spec_data(sp: &ItemSpec) -> String {
	let mut e = Enc::new();
	e.spec(sp);
	e.s
}

pub const ITEM_COLS: &str = "id, base, gear_slot, item_level, rarity, lines, sockets, sock0, sock1, plus, bound, \
	place_kind, place_owner, place_tab, place_slot, minted, origin_account, origin_hero, mint_seq";

pub fn item_from_row(r: &rusqlite::Row) -> rusqlite::Result<Item> {
	let sockets: u8 = r.get(6)?;
	let s0: Option<u32> = r.get(7)?;
	let s1: Option<u32> = r.get(8)?;
	let socketed = [s0, s1].iter().take(sockets as usize).map(|s| s.map(StackKind)).collect();
	let lines: String = r.get(5)?;
	let kind: i64 = r.get(11)?;
	Ok(Item {
		id: r.get(0)?,
		spec: ItemSpec {
			base: r.get(1)?,
			gear_slot: r.get(2)?,
			item_level: r.get(3)?,
			rarity: r.get(4)?,
			lines: parse_lines(&lines),
			sockets,
			plus: r.get(9)?,
			bound: r.get::<_, i64>(10)? != 0,
		},
		socketed,
		place: Place {
			kind: PlaceKind::from_i64(kind).unwrap_or(PlaceKind::Trade),
			owner: r.get(12)?,
			tab: r.get(13)?,
			slot: r.get(14)?,
		},
		minted: r.get(15)?,
		origin_account: r.get(16)?,
		origin_hero: r.get(17)?,
		mint_seq: r.get(18)?,
	})
}

pub(crate) fn inv(s: impl Into<String>) -> Error {
	Error::Invalid(s.into())
}

pub(crate) fn i64_of(v: u64, what: &str) -> Result<i64> {
	i64::try_from(v).map_err(|_| inv(format!("{what} too large")))
}

/// The holder of value at a place: the account for hero and account containers.
pub fn party_of(c: &Connection, kind: PlaceKind, owner: i64) -> Result<Party> {
	Ok(match kind {
		PlaceKind::Bag | PlaceKind::Worn | PlaceKind::Mail => {
			let acct: Option<i64> =
				c.prepare_cached("SELECT account FROM heroes WHERE id = ?1")?.query_row([owner], |r| r.get(0)).optional()?;
			Party::Account(acct.ok_or_else(|| Error::Missing(format!("hero {owner}")))?)
		}
		PlaceKind::Bank | PlaceKind::House => Party::Account(owner),
		PlaceKind::Guild => Party::Guild(owner),
		PlaceKind::Market => Party::Market(owner),
		PlaceKind::Trade => Party::Trade(owner),
	})
}

pub fn acct_of(p: Party) -> Option<AccountId> {
	match p {
		Party::Account(a) => Some(a),
		_ => None,
	}
}

impl<'c> Tx<'c> {
	pub(crate) fn exec<P: Params>(&self, sql: &str, p: P) -> Result<usize> {
		crash::point(Site::Stmt);
		Ok(self.c.prepare_cached(sql)?.execute(p)?)
	}

	pub(crate) fn one<T, P: Params, F: FnOnce(&rusqlite::Row) -> rusqlite::Result<T>>(&self, sql: &str, p: P, f: F) -> Result<Option<T>> {
		crash::point(Site::Stmt);
		Ok(self.c.prepare_cached(sql)?.query_row(p, f).optional()?)
	}

	pub fn ledger(&mut self, r: Row) -> Result<i64> {
		let seq = self.seq;
		let f = r.from;
		let t = r.to;
		self.exec(
			"INSERT INTO ledger (seq, time, request, actor, op, item, stack_kind, from_kind, from_owner, from_tab, \
			from_slot, to_kind, to_owner, to_tab, to_slot, count, reason, data, from_acct, to_acct, minted) \
			VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21)",
			params![
				seq,
				self.req.now,
				&self.req.id.to_be_bytes()[..],
				self.req.actor,
				r.op,
				r.item,
				r.stack.map(|k| k.0),
				f.map(|x| x.0 as i64),
				f.map(|x| x.1),
				f.and_then(|x| x.2),
				f.and_then(|x| x.3),
				t.map(|x| x.0 as i64),
				t.map(|x| x.1),
				t.and_then(|x| x.2),
				t.and_then(|x| x.3),
				i64_of(r.count, "count")?,
				r.reason,
				r.data,
				r.from_acct,
				r.to_acct,
				r.minted as i64,
			],
		)?;
		self.seq += 1;
		Ok(seq)
	}

	// ---- loading and checks ----

	pub fn account_row(&self, id: AccountId) -> Result<AccountRow> {
		self.one("SELECT id, flags, banned_until FROM accounts WHERE id = ?1", [id], |r| {
			Ok(AccountRow { id: r.get(0)?, flags: r.get::<_, i64>(1)? as u64, banned_until: r.get(2)? })
		})?
		.ok_or_else(|| Error::Missing(format!("account {id}")))
	}

	pub fn hero_row(&self, id: HeroId) -> Result<HeroRow> {
		self.one("SELECT id, account, class_level, deleted_at FROM heroes WHERE id = ?1", [id], |r| {
			Ok(HeroRow { id: r.get(0)?, account: r.get(1)?, class_level: r.get(2)?, deleted_at: r.get(3)? })
		})?
		.ok_or_else(|| Error::Missing(format!("hero {id}")))
	}

	/// The actor exists and is not banned.
	pub fn check_actor(&self) -> Result<()> {
		if self.req.actor == 0 {
			return Ok(());
		}
		let a = self.account_row(self.req.actor)?;
		if let Some(until) = a.banned_until {
			if until > self.req.now {
				return Err(Error::Banned { until });
			}
		}
		Ok(())
	}

	fn mine(&self, account: AccountId, what: &str) -> Result<()> {
		if self.req.actor != 0 && self.req.actor != account {
			return Err(Error::NotYours(what.to_string()));
		}
		Ok(())
	}

	/// A live hero the actor may act for.
	pub fn own_hero(&self, id: HeroId) -> Result<HeroRow> {
		let h = self.hero_row(id)?;
		self.mine(h.account, &format!("hero {id}"))?;
		if h.deleted_at.is_some() {
			return Err(Error::Deleted);
		}
		Ok(h)
	}

	/// A live hero, whoever asks (a mail recipient, a trade partner).
	pub(crate) fn live_hero(&self, id: HeroId) -> Result<HeroRow> {
		let h = self.hero_row(id)?;
		if h.deleted_at.is_some() {
			return Err(Error::Deleted);
		}
		Ok(h)
	}

	pub(crate) fn party(&self, kind: PlaceKind, owner: i64) -> Result<Party> {
		party_of(self.c, kind, owner)
	}

	/// TRADE_LOCKED: no value moves between a locked account and any other party, in either direction.
	pub(crate) fn is_self_found(&self, hero: HeroId) -> Result<bool> {
		Ok(self.one("SELECT self_found FROM heroes WHERE id = ?1", [hero], |r| r.get::<_, i64>(0))?.unwrap_or(0) != 0)
	}

	/// The self-found rule. A self-found hero's items are hers alone and she holds only what was minted for her:
	/// she gives nothing to another hero, and an item enters her containers only if she is its origin hero.
	/// (The bank and the house belong to the account, so she may use them for her own things.)
	pub(crate) fn self_found_gate(&self, it: &Item, from: Option<HeroId>, to: Option<HeroId>) -> Result<()> {
		if from == to {
			return Ok(());
		}
		if let Some(f) = from {
			if to.is_some() && self.is_self_found(f)? {
				return Err(Error::Refused);
			}
		}
		if let Some(h) = to {
			if it.origin_hero != Some(h) && self.is_self_found(h)? {
				return Err(Error::Refused);
			}
		}
		Ok(())
	}

	pub(crate) fn check_flow(&self, from: Party, to: Party) -> Result<()> {
		if from == to {
			return Ok(());
		}
		for p in [from, to] {
			if let Party::Account(a) = p {
				if self.account_row(a)?.flags & flags::TRADE_LOCKED != 0 {
					return Err(Error::Refused);
				}
			}
		}
		Ok(())
	}

	/// The actor may take from (or put into) this party's holdings. An account touches only its own; guild banks,
	/// listings and trade sessions are the server's (guild membership lives in the gateway).
	fn may_touch(&self, p: Party, what: &str) -> Result<()> {
		match p {
			Party::Account(a) => self.mine(a, what),
			Party::Guild(_) | Party::Market(_) | Party::Trade(_) => {
				if self.req.actor != 0 {
					Err(Error::NotYours(what.to_string()))
				} else {
					Ok(())
				}
			}
		}
	}

	pub fn entitlement(&self, account: AccountId, kind: EntitlementKind) -> Result<u32> {
		Ok(self
			.one("SELECT count FROM entitlements WHERE account = ?1 AND kind = ?2", params![account, kind as i64], |r| {
				r.get(0)
			})?
			.unwrap_or(0))
	}

	fn bank_tabs(&self, account: AccountId) -> Result<u32> {
		Ok(FREE_BANK_TABS + self.entitlement(account, EntitlementKind::BankTab)?)
	}

	fn hero_slots(&self, account: AccountId) -> Result<u32> {
		Ok(FREE_HERO_SLOTS + self.entitlement(account, EntitlementKind::HeroSlot)?)
	}

	/// Slots used in a hero's bag: its items plus one a kind for potions, runes, keys, pages and cards.
	pub fn bag_used(&self, hero: HeroId) -> Result<u32> {
		let items: i64 = self
			.one("SELECT count(*) FROM items WHERE place_kind = 1 AND place_owner = ?1", [hero], |r| r.get(0))?
			.unwrap_or(0);
		let stacks: i64 = self
			.one(
				"SELECT count(*) FROM stacks WHERE owner_kind = 1 AND owner = ?1 AND count > 0 AND \
				((kind BETWEEN 100 AND 199) OR (kind BETWEEN 2000 AND 2999) OR (kind BETWEEN 3000 AND 3099) OR \
				(kind BETWEEN 4000 AND 4099) OR (kind BETWEEN 5000 AND 9999))",
				[hero],
				|r| r.get(0),
			)?
			.unwrap_or(0);
		Ok((items + stacks) as u32)
	}

	/// Checks the container exists, the tab is open and the actor may use it. Returns the party.
	fn container(&self, kind: PlaceKind, owner: i64, tab: u32) -> Result<Party> {
		match kind {
			PlaceKind::Bag | PlaceKind::Worn | PlaceKind::Mail => {
				self.live_hero(owner)?;
			}
			PlaceKind::Bank | PlaceKind::House => {
				self.account_row(owner)?;
			}
			PlaceKind::Guild => {
				if owner <= 0 {
					return Err(Error::Missing(format!("guild {owner}")));
				}
			}
			PlaceKind::Market | PlaceKind::Trade => {
				if owner <= 0 {
					return Err(Error::Missing(format!("{} {owner}", kind.name())));
				}
			}
		}
		let tabs = match kind {
			PlaceKind::Bank => self.bank_tabs(owner)?,
			PlaceKind::Guild => GUILD_TABS,
			_ => 1,
		};
		if tab >= tabs {
			return Err(if kind == PlaceKind::Bank {
				Error::Full(format!("bank tab {tab} not open"))
			} else {
				inv(format!("{} has no tab {tab}", kind.name()))
			});
		}
		self.party(kind, owner)
	}

	pub(crate) fn taken(&self, kind: PlaceKind, owner: i64, tab: u32, slot: u32) -> Result<Option<ItemId>> {
		self.one(
			"SELECT id FROM items WHERE place_kind = ?1 AND place_owner = ?2 AND place_tab = ?3 AND place_slot = ?4",
			params![kind as i64, owner, tab, slot],
			|r| r.get(0),
		)
	}

	fn first_free(&self, kind: PlaceKind, owner: i64, tab: u32) -> Result<Option<u32>> {
		crash::point(Site::Stmt);
		let mut st = self.c.prepare_cached(
			"SELECT place_slot FROM items WHERE place_kind = ?1 AND place_owner = ?2 AND place_tab = ?3 ORDER BY place_slot",
		)?;
		let mut rows = st.query(params![kind as i64, owner, tab])?;
		let mut want: u32 = 0;
		while let Some(r) = rows.next()? {
			let s: u32 = r.get(0)?;
			if s > want {
				break;
			}
			if s == want {
				want += 1;
			}
		}
		Ok(if want < kind.slots() { Some(want) } else { None })
	}

	/// Resolves a destination for an item (not yet there), checking every slot rule. `moving_within` is true when
	/// the item is already in the same bag (a bag reorder does not need a new slot).
	pub fn resolve(&self, d: &Dest, spec: &ItemSpec, moving_within: bool) -> Result<(Place, Party)> {
		let party = self.container(d.kind, d.owner, d.tab)?;
		if !d.kind.has_tabs() && d.tab != 0 {
			return Err(inv("tab must be 0"));
		}
		if d.kind == PlaceKind::Worn {
			let h = self.hero_row(d.owner)?;
			if let Some(s) = d.slot {
				if s != spec.gear_slot as u32 {
					return Err(inv(format!("gear slot {} cannot go in worn slot {s}", spec.gear_slot)));
				}
			}
			if spec.item_level > h.class_level {
				return Err(Error::LevelTooLow { need: spec.item_level, have: h.class_level });
			}
			let slot = spec.gear_slot as u32;
			let p = Place { kind: d.kind, owner: d.owner, tab: 0, slot };
			if self.taken(d.kind, d.owner, 0, slot)?.is_some() {
				return Err(Error::SlotTaken(p));
			}
			return Ok((p, party));
		}
		if d.kind == PlaceKind::Bag && !moving_within && self.bag_used(d.owner)? >= BAG_SLOTS {
			return Err(Error::Full(format!("bag of hero {}", d.owner)));
		}
		let slot = match d.slot {
			Some(s) => {
				if s >= d.kind.slots() {
					return Err(inv(format!("{} has no slot {s}", d.kind.name())));
				}
				let p = Place { kind: d.kind, owner: d.owner, tab: d.tab, slot: s };
				if self.taken(d.kind, d.owner, d.tab, s)?.is_some() {
					return Err(Error::SlotTaken(p));
				}
				s
			}
			None => self.first_free(d.kind, d.owner, d.tab)?.ok_or_else(|| {
				Error::Full(format!("{} {} tab {}", d.kind.name(), d.owner, d.tab))
			})?,
		};
		Ok((Place { kind: d.kind, owner: d.owner, tab: d.tab, slot }, party))
	}

	pub fn load_item(&self, id: ItemId) -> Result<Item> {
		self.one(&format!("SELECT {ITEM_COLS} FROM items WHERE id = ?1"), [id], item_from_row)?
			.ok_or_else(|| Error::Missing(format!("item {id}")))
	}

	pub(crate) fn set_place(&self, id: ItemId, p: &Place) -> Result<()> {
		self.exec(
			"UPDATE items SET place_kind = ?2, place_owner = ?3, place_tab = ?4, place_slot = ?5 WHERE id = ?1",
			params![id, p.kind as i64, p.owner, p.tab, p.slot],
		)?;
		Ok(())
	}

	// ---- stacks ----

	pub fn stack_get(&self, o: &Owner, k: StackKind) -> Result<u64> {
		Ok(self
			.one(
				"SELECT count FROM stacks WHERE owner_kind = ?1 AND owner = ?2 AND kind = ?3",
				params![o.kind as i64, o.id, k.0],
				|r| r.get::<_, i64>(0),
			)?
			.unwrap_or(0) as u64)
	}

	/// Checks a stack owner may hold stacks and returns its party.
	pub(crate) fn stack_owner(&self, o: &Owner) -> Result<Party> {
		match o.kind {
			PlaceKind::Worn => Err(inv("worn holds no stacks")),
			_ => self.container(o.kind, o.id, 0),
		}
	}

	pub(crate) fn stack_set(&self, o: &Owner, k: StackKind, n: u64) -> Result<()> {
		if n == 0 {
			self.exec(
				"DELETE FROM stacks WHERE owner_kind = ?1 AND owner = ?2 AND kind = ?3",
				params![o.kind as i64, o.id, k.0],
			)?;
		} else {
			self.exec(
				"INSERT INTO stacks (owner_kind, owner, kind, count) VALUES (?1, ?2, ?3, ?4) \
				ON CONFLICT (owner_kind, owner, kind) DO UPDATE SET count = excluded.count",
				params![o.kind as i64, o.id, k.0, i64_of(n, "stack")?],
			)?;
		}
		Ok(())
	}

	/// Adds to a stack; a new slot-taking kind in a bag needs a free slot.
	pub fn stack_add(&self, o: &Owner, k: StackKind, n: u64) -> Result<u64> {
		let have = self.stack_get(o, k)?;
		if have == 0 && o.kind == PlaceKind::Bag && k.takes_bag_slot() && self.bag_used(o.id)? >= BAG_SLOTS {
			return Err(Error::Full(format!("bag of hero {}", o.id)));
		}
		let total = have.checked_add(n).ok_or_else(|| inv("stack overflow"))?;
		i64_of(total, "stack")?;
		self.stack_set(o, k, total)?;
		Ok(total)
	}

	pub fn stack_sub(&self, o: &Owner, k: StackKind, n: u64) -> Result<u64> {
		let have = self.stack_get(o, k)?;
		if have < n {
			return Err(Error::Insufficient { kind: k, have, want: n });
		}
		self.stack_set(o, k, have - n)?;
		Ok(have - n)
	}

	pub(crate) fn check_kind(k: StackKind, count: u64) -> Result<()> {
		if k.class().is_none() {
			return Err(inv(format!("no stack kind {}", k.0)));
		}
		if count == 0 {
			return Err(inv("count must be above zero"));
		}
		i64_of(count, "count")?;
		Ok(())
	}

	pub(crate) fn credit_row(&mut self, o: &Owner, party: Party, k: StackKind, n: u64, minted: bool, reason: &str) -> Result<()> {
		self.ledger(Row {
			op: "CREDIT",
			stack: Some(k),
			to: Some(owner_cols(o)),
			to_acct: acct_of(party),
			count: n,
			minted,
			reason,
			..Default::default()
		})?;
		Ok(())
	}

	pub(crate) fn debit_row(&mut self, op: &str, o: &Owner, party: Party, k: StackKind, n: u64, reason: &str) -> Result<()> {
		self.ledger(Row {
			op,
			stack: Some(k),
			from: Some(owner_cols(o)),
			from_acct: acct_of(party),
			count: n,
			reason,
			..Default::default()
		})?;
		Ok(())
	}

	// ---- items ----

	pub(crate) fn check_spec(sp: &ItemSpec) -> Result<()> {
		if sp.gear_slot >= WORN_SLOTS as u8 {
			return Err(inv("gear slot"));
		}
		if sp.rarity > 4 {
			return Err(inv("rarity"));
		}
		if sp.item_level == 0 || sp.item_level > MAX_LEVEL {
			return Err(inv("item level"));
		}
		if sp.lines.is_empty() || sp.lines.len() > MAX_LINES || sp.lines.iter().any(|(s, _)| *s >= 6) {
			return Err(inv("lines"));
		}
		if sp.sockets > MAX_SOCKETS {
			return Err(inv("sockets"));
		}
		if sp.plus > 10 {
			return Err(inv("plus"));
		}
		Ok(())
	}

	/// Inserts a new item at a resolved place and writes its MINT row.
	fn mint_at(&mut self, p: &Place, party: Party, sp: &ItemSpec, reason: &str) -> Result<ItemId> {
		let origin_hero = if p.kind.hero_owned() { Some(p.owner) } else { None };
		let origin_account = acct_of(party).unwrap_or(0);
		let mint_seq = self.seq;
		self.exec(
			"INSERT INTO items (base, gear_slot, item_level, rarity, lines, sockets, plus, bound, place_kind, \
			place_owner, place_tab, place_slot, minted, origin_account, origin_hero, mint_seq) \
			VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)",
			params![
				sp.base,
				sp.gear_slot,
				sp.item_level,
				sp.rarity,
				spec_lines(&sp.lines),
				sp.sockets,
				sp.plus,
				sp.bound as i64,
				p.kind as i64,
				p.owner,
				p.tab,
				p.slot,
				self.req.now,
				origin_account,
				origin_hero,
				mint_seq
			],
		)?;
		let id = self.c.last_insert_rowid();
		self.ledger(Row {
			op: "MINT",
			item: Some(id),
			to: Some(place_cols(p)),
			to_acct: acct_of(party),
			count: 1,
			minted: true,
			reason,
			data: spec_data(sp),
			..Default::default()
		})?;
		Ok(id)
	}

	pub(crate) fn move_row(&mut self, op: &str, it: &Item, from_party: Party, to: &Place, to_party: Party) -> Result<()> {
		self.ledger(Row {
			op,
			item: Some(it.id),
			from: Some(place_cols(&it.place)),
			from_acct: acct_of(from_party),
			to: Some(place_cols(to)),
			to_acct: acct_of(to_party),
			count: 1,
			..Default::default()
		})?;
		Ok(())
	}

	fn destroy(&mut self, it: &Item, party: Party, op: &str, reason: &str) -> Result<()> {
		self.exec("DELETE FROM items WHERE id = ?1", [it.id])?;
		let mut data = String::new();
		for (i, s) in it.socketed.iter().enumerate() {
			if let Some(k) = s {
				data.push_str(&format!("sock{i}={} ", k.0));
			}
		}
		self.ledger(Row {
			op,
			item: Some(it.id),
			from: Some(place_cols(&it.place)),
			from_acct: acct_of(party),
			count: 1,
			reason,
			data: data.trim_end().to_string(),
			..Default::default()
		})?;
		Ok(())
	}

	/// An item the hero carries (bag, or worn when `worn_ok`).
	pub(crate) fn carried(&self, hero: HeroId, item: ItemId, worn_ok: bool) -> Result<Item> {
		let it = self.load_item(item)?;
		let ok = it.place.owner == hero
			&& (it.place.kind == PlaceKind::Bag || (worn_ok && it.place.kind == PlaceKind::Worn));
		if !ok {
			return Err(Error::NotYours(format!("item {item} is not carried by hero {hero}")));
		}
		Ok(it)
	}
}

fn check_name(name: &str) -> Result<String> {
	let n = name.chars().count();
	let first_ok = name.chars().next().is_some_and(|c| c.is_ascii_alphabetic());
	let chars_ok = name.chars().all(|c| c.is_ascii_alphanumeric() || c == '\'' || c == '-');
	if !(NAME_MIN..=NAME_MAX).contains(&n) || !first_ok || !chars_ok {
		return Err(Error::BadName);
	}
	Ok(name.to_ascii_lowercase())
}

pub(crate) fn check_reason(r: &str) -> Result<()> {
	if r.is_empty() || r.len() > 64 {
		return Err(inv("reason must be 1 to 64 bytes"));
	}
	Ok(())
}

pub const MINT_REASONS: [&str; 6] = ["drop", "cache", "chest", "merchant", "grant", "haul"];

/// May this hero put `card` in her deck?
fn card_owned(t: &Tx, account: AccountId, level: u16, card: u16) -> Result<bool> {
	if card < NOVICE_CARDS {
		return Ok(true);
	}
	// each even class level to 24 adds one card
	if card < NOVICE_CARDS + 12 && level >= 2 * (card - NOVICE_CARDS + 1) {
		return Ok(true);
	}
	Ok(t
		.one("SELECT 1 FROM owned_cards WHERE account = ?1 AND card = ?2", params![account, card], |r| r.get::<_, i64>(0))?
		.is_some())
}

/// Applies one command. The caller wraps it in a savepoint.
/// Who may run a command.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Who {
	/// actor 0 only: it creates value, removes someone else's, or changes standing
	Server,
	/// the server, or an account acting on its own things (checked by each operation)
	Owner,
}

/// The one table of who may run what. No wildcard: a new command must be placed here to compile.
pub fn who_may(c: &Cmd) -> Who {
	match c {
		Cmd::AccountBySteam { .. } => Who::Server,
		Cmd::AccountByDevName { .. } => Who::Server,
		Cmd::ApplyFlags { .. } => Who::Server,
		Cmd::Clawback { .. } => Who::Server,
		Cmd::GrantEntitlement { .. } => Who::Server,
		Cmd::BuyEntitlement { .. } => Who::Server,
		Cmd::HeroFeat { .. } => Who::Server,
		Cmd::TakeJob { .. } => Who::Server,
		Cmd::Mint { .. } => Who::Server,
		Cmd::StackCredit { .. } => Who::Server,
		Cmd::StackDebit { .. } => Who::Server,
		Cmd::Outing { .. } => Who::Server,
		Cmd::Plunder { .. } => Who::Server,
		Cmd::SellItem { .. } => Who::Server,
		Cmd::Trade { .. } => Who::Server,
		Cmd::HeroCreate { .. } => Who::Owner,
		Cmd::HeroRename { .. } => Who::Owner,
		Cmd::HeroDelete { .. } => Who::Owner,
		Cmd::HeroUndelete { .. } => Who::Owner,
		Cmd::HeroSave { .. } => Who::Owner,
		Cmd::LearnPage { .. } => Who::Owner,
		Cmd::MoveItem { .. } => Who::Owner,
		Cmd::Socket { .. } => Who::Owner,
		Cmd::Unsocket { .. } => Who::Owner,
		Cmd::StackTransfer { .. } => Who::Owner,
		Cmd::ParcelPut { .. } => Who::Server,
		Cmd::ParcelTake { .. } => Who::Server,
		Cmd::ParcelReturn { .. } => Who::Server,
	}
}

pub fn apply(t: &mut Tx) -> Result<Reply> {
	t.check_actor()?;
	if t.req.actor != 0 && who_may(&t.req.cmd) == Who::Server {
		return Err(Error::NotYours(format!("{} is the server's", t.req.cmd.name())));
	}
	let req = t.req;
	let now = req.now;
	match &req.cmd {
		Cmd::AccountBySteam { steam_id } => {
			let sid = i64_of(*steam_id, "steam id")?;
			if let Some(id) = t.one("SELECT id FROM accounts WHERE steam_id = ?1", [sid], |r| r.get(0))? {
				return Ok(Reply::Account(id));
			}
			t.exec("INSERT INTO accounts (steam_id, created) VALUES (?1, ?2)", params![sid, now])?;
			let id = t.c.last_insert_rowid();
			t.ledger(Row { op: "ACCOUNT", data: format!("steam {steam_id} id {id}"), to_acct: Some(id), ..Default::default() })?;
			Ok(Reply::Account(id))
		}
		Cmd::AccountByDevName { name } => {
			if name.is_empty() || name.len() > 32 {
				return Err(Error::BadName);
			}
			if let Some(id) = t.one("SELECT id FROM accounts WHERE dev_name = ?1", [name], |r| r.get(0))? {
				return Ok(Reply::Account(id));
			}
			t.exec("INSERT INTO accounts (dev_name, created) VALUES (?1, ?2)", params![name, now])?;
			let id = t.c.last_insert_rowid();
			t.ledger(Row { op: "ACCOUNT", data: format!("dev {name} id {id}"), to_acct: Some(id), ..Default::default() })?;
			Ok(Reply::Account(id))
		}
		Cmd::ApplyFlags { changes, reason } => {
			check_reason(reason)?;
			if changes.is_empty() {
				return Err(inv("no accounts"));
			}
			for ch in changes {
				if ch.flags & !flags::ALL != 0 || ch.drops_percent > 100 {
					return Err(inv("flags"));
				}
				let old = t.account_row(ch.account)?;
				let old_pct: i64 = t.one("SELECT drops_percent FROM accounts WHERE id = ?1", [ch.account], |r| r.get(0))?.unwrap_or(100);
				t.exec(
					"UPDATE accounts SET flags = ?2, drops_percent = ?3, banned_until = ?4 WHERE id = ?1",
					params![ch.account, ch.flags as i64, ch.drops_percent, ch.banned_until],
				)?;
				t.ledger(Row {
					op: "FLAGS",
					to_acct: Some(ch.account),
					reason,
					data: format!(
						"flags {}->{} drops {}->{} ban {:?}->{:?}",
						old.flags, ch.flags, old_pct, ch.drops_percent, old.banned_until, ch.banned_until
					),
					..Default::default()
				})?;
			}
			Ok(Reply::Done)
		}
		Cmd::HeroCreate { account, name, race, class, look, self_found } => {
			t.account_row(*account)?;
			t.mine(*account, "account")?;
			let key = check_name(name)?;
			if *race >= 4 || *class >= 16 {
				return Err(inv("race or class"));
			}
			let live: i64 = t
				.one("SELECT count(*) FROM heroes WHERE account = ?1 AND deleted_at IS NULL", [account], |r| r.get(0))?
				.unwrap_or(0);
			if live as u32 >= t.hero_slots(*account)? {
				return Err(Error::Full("hero slots".into()));
			}
			release_stale_name(t, &key)?;
			if t.one("SELECT id FROM heroes WHERE name_key = ?1 AND name_held = 1", [&key], |r| r.get::<_, i64>(0))?.is_some() {
				return Err(Error::NameTaken);
			}
			let deck: Vec<u16> = (0..NOVICE_CARDS).collect();
			t.exec(
				"INSERT INTO heroes (account, name, name_key, race, class, look, stats, deck, belt, waystones, \
				self_found, created) VALUES (?1, ?2, ?3, ?4, ?5, ?6, '0,0,0,0,0,0', ?7, '0,0,0', '-1,-1,-1,-1,-1,-1', ?8, ?9)",
				params![account, name, key, race, class, look, join_nums(&deck), *self_found as i64, now],
			)?;
			let id = t.c.last_insert_rowid();
			t.ledger(Row {
				op: "HERO_CREATE",
				to_acct: Some(*account),
				data: format!("hero {id} name {name} race {race} class {class} self_found {}", *self_found as u8),
				..Default::default()
			})?;
			Ok(Reply::Hero(id))
		}
		Cmd::HeroRename { hero, name } => {
			let h = t.own_hero(*hero)?;
			let key = check_name(name)?;
			release_stale_name(t, &key)?;
			if let Some(other) = t.one("SELECT id FROM heroes WHERE name_key = ?1 AND name_held = 1", [&key], |r| r.get::<_, i64>(0))? {
				if other != *hero {
					return Err(Error::NameTaken);
				}
			}
			let old: String = t.one("SELECT name FROM heroes WHERE id = ?1", [hero], |r| r.get(0))?.unwrap_or_default();
			t.exec("UPDATE heroes SET name = ?2, name_key = ?3, name_held = 1 WHERE id = ?1", params![hero, name, key])?;
			t.ledger(Row { op: "HERO_RENAME", to_acct: Some(h.account), data: format!("hero {hero} {old} -> {name}"), ..Default::default() })?;
			Ok(Reply::Done)
		}
		Cmd::HeroDelete { hero } => {
			let h = t.own_hero(*hero)?;
			// what she has in escrow (a listing, a letter with cash on delivery) would be stranded
			if t.one("SELECT 1 FROM parcels WHERE from_hero = ?1 LIMIT 1", [hero], |r| r.get::<_, i64>(0))?.is_some() {
				return Err(inv("the hero has things on the market or in letters in transit"));
			}
			t.exec("UPDATE heroes SET deleted_at = ?2 WHERE id = ?1", params![hero, now])?;
			t.ledger(Row { op: "HERO_DELETE", to_acct: Some(h.account), data: format!("hero {hero}"), ..Default::default() })?;
			Ok(Reply::Done)
		}
		Cmd::HeroUndelete { hero } => {
			let h = t.hero_row(*hero)?;
			t.mine(h.account, &format!("hero {hero}"))?;
			let Some(at) = h.deleted_at else {
				return Err(inv("hero is not deleted"));
			};
			if now - at > UNDELETE_MS {
				return Err(Error::Expired);
			}
			let live: i64 = t
				.one("SELECT count(*) FROM heroes WHERE account = ?1 AND deleted_at IS NULL", [h.account], |r| r.get(0))?
				.unwrap_or(0);
			if live as u32 >= t.hero_slots(h.account)? {
				return Err(Error::Full("hero slots".into()));
			}
			let (key, held): (String, i64) =
				t.one("SELECT name_key, name_held FROM heroes WHERE id = ?1", [hero], |r| Ok((r.get(0)?, r.get(1)?)))?.unwrap();
			if held == 0 {
				if t.one("SELECT id FROM heroes WHERE name_key = ?1 AND name_held = 1", [&key], |r| r.get::<_, i64>(0))?.is_some() {
					return Err(Error::NameTaken);
				}
			}
			t.exec("UPDATE heroes SET deleted_at = NULL, name_held = 1 WHERE id = ?1", [hero])?;
			t.ledger(Row { op: "HERO_UNDELETE", to_acct: Some(h.account), data: format!("hero {hero}"), ..Default::default() })?;
			Ok(Reply::Done)
		}
		Cmd::HeroSave { hero, progress: p } => {
			let h = t.own_hero(*hero)?;
			let (xp, lvl): (i64, u16) =
				t.one("SELECT class_xp, class_level FROM heroes WHERE id = ?1", [hero], |r| Ok((r.get(0)?, r.get(1)?)))?.unwrap();
			if p.class_level == 0 || p.class_level > MAX_LEVEL || p.class_level < lvl {
				return Err(inv("class level"));
			}
			if (p.class_xp as i128) < xp as i128 {
				return Err(inv("class xp never goes down"));
			}
			// only the server applies progress: an account may respend points, pick a job, set deck and belt
			if t.req.actor != 0 && (p.class_level != lvl || p.class_xp as i128 != xp as i128) {
				return Err(Error::NotYours("class level and xp are the server's".into()));
			}
			let spent: u32 = p.stats.iter().map(|s| *s as u32).sum::<u32>() + p.unspent as u32;
			if spent != p.class_level as u32 - 1 {
				return Err(inv(format!("stat points {spent} != level - 1")));
			}
			if p.job >= 16 {
				return Err(inv("job"));
			}
			if p.deck.len() > DECK_SIZE {
				return Err(inv("deck holds 20 cards"));
			}
			let mut seen = std::collections::BTreeSet::new();
			for c in &p.deck {
				if *c >= DECK_CARDS || !seen.insert(*c) {
					return Err(inv(format!("deck card {c}")));
				}
				if !card_owned(t, h.account, p.class_level, *c)? {
					return Err(Error::Missing(format!("card {c} not owned")));
				}
			}
			for b in p.belt {
				if b != 0 && StackKind(b).class() != Some(StackClass::Potion) {
					return Err(inv(format!("belt holds potions, not {b}")));
				}
			}
			if p.waystones.iter().any(|w| *w < -1) {
				return Err(inv("waystone"));
			}
			t.exec(
				"UPDATE heroes SET job = ?2, class_level = ?3, class_xp = ?4, stats = ?5, unspent = ?6, deck = ?7, \
				belt = ?8, waystones = ?9 WHERE id = ?1",
				params![
					hero,
					p.job,
					p.class_level,
					i64_of(p.class_xp, "xp")?,
					join_nums(&p.stats),
					p.unspent,
					join_nums(&p.deck),
					join_nums(&p.belt),
					join_nums(&p.waystones)
				],
			)?;
			let mut e = Enc::new();
			e.progress(p);
			t.ledger(Row { op: "HERO_SAVE", to_acct: Some(h.account), data: format!("hero {hero} {}", e.s), ..Default::default() })?;
			Ok(Reply::Done)
		}
		Cmd::LearnPage { hero, card } => {
			let h = t.own_hero(*hero)?;
			if *card < NOVICE_CARDS || *card >= DECK_CARDS {
				return Err(inv(format!("no page for card {card}")));
			}
			if t.one("SELECT 1 FROM owned_cards WHERE account = ?1 AND card = ?2", params![h.account, card], |r| r.get::<_, i64>(0))?.is_some() {
				return Err(inv("card already owned"));
			}
			let o = Owner::bag(*hero);
			let k = StackKind::page(*card as u32);
			t.stack_sub(&o, k, 1)?;
			t.debit_row("DEBIT", &o, Party::Account(h.account), k, 1, "learn")?;
			t.exec("INSERT INTO owned_cards (account, card) VALUES (?1, ?2)", params![h.account, card])?;
			t.ledger(Row { op: "LEARN", to_acct: Some(h.account), data: format!("hero {hero} card {card}"), ..Default::default() })?;
			Ok(Reply::Done)
		}
		Cmd::Mint { to, spec, reason } => {
			if !MINT_REASONS.contains(&reason.as_str()) {
				return Err(inv(format!("mint reason {reason}")));
			}
			Tx::check_spec(spec)?;
			if matches!(to.kind, PlaceKind::Market | PlaceKind::Trade) {
				return Err(inv("cannot mint into a market listing or trade"));
			}
			let (p, party) = t.resolve(to, spec, false)?;
			t.may_touch(party, "destination")?;
			let id = t.mint_at(&p, party, spec, reason)?;
			Ok(Reply::Item(id, p))
		}
		Cmd::MoveItem { item, to } => {
			let it = t.load_item(*item)?;
			let movable = |k: PlaceKind| !matches!(k, PlaceKind::Market | PlaceKind::Trade);
			if !movable(it.place.kind) {
				return Err(inv(format!("item {item} is in a {}", it.place.kind.name())));
			}
			if !movable(to.kind) {
				return Err(inv("items reach a market or trade only through those operations"));
			}
			if it.place.kind.hero_owned() && it.place.kind != PlaceKind::Mail {
				t.live_hero(it.place.owner)?;
			}
			let from_party = t.party(it.place.kind, it.place.owner)?;
			t.may_touch(from_party, &format!("item {item}"))?;
			let within = to.kind == PlaceKind::Bag && it.place.kind == PlaceKind::Bag && it.place.owner == to.owner;
			if within && to.slot.is_none() {
				return Err(inv("item is already there"));
			}
			let (p, to_party) = t.resolve(to, &it.spec, within)?;
			if p == it.place {
				return Err(inv("item is already there"));
			}
			// an account puts things only in its own places (mail to its own heroes); the server may send anywhere
			t.may_touch(to_party, "destination")?;
			t.check_flow(from_party, to_party)?;
			let hero_of = |k: PlaceKind, o: i64| if k.hero_owned() { Some(o) } else { None };
			t.self_found_gate(&it, hero_of(it.place.kind, it.place.owner), hero_of(p.kind, p.owner))?;
			t.set_place(it.id, &p)?;
			t.move_row("MOVE", &it, from_party, &p, to_party)?;
			Ok(Reply::Item(it.id, p))
		}
		Cmd::SellItem { hero, item, price } => {
			let h = t.own_hero(*hero)?;
			let it = t.carried(*hero, *item, false)?;
			if *price > 1_000_000_000_000 {
				return Err(inv("price"));
			}
			let party = Party::Account(h.account);
			t.destroy(&it, party, "DESTROY", "sell")?;
			let o = Owner::bag(*hero);
			let total = if *price > 0 {
				let n = t.stack_add(&o, StackKind::COIN, *price)?;
				t.credit_row(&o, party, StackKind::COIN, *price, true, "sell")?;
				n
			} else {
				t.stack_get(&o, StackKind::COIN)?
			};
			Ok(Reply::Count(total))
		}
		Cmd::Socket { hero, item, socket, kind } => {
			let h = t.own_hero(*hero)?;
			let it = t.carried(*hero, *item, true)?;
			if !kind.socketable() {
				return Err(inv(format!("{} does not go in a socket", kind.0)));
			}
			if *socket >= it.spec.sockets {
				return Err(Error::Missing(format!("socket {socket} of item {item}")));
			}
			if it.socketed[*socket as usize].is_some() {
				return Err(inv(format!("socket {socket} is full")));
			}
			let o = Owner::bag(*hero);
			let party = Party::Account(h.account);
			t.stack_sub(&o, *kind, 1)?;
			t.debit_row("DEBIT", &o, party, *kind, 1, "socket")?;
			t.exec(&format!("UPDATE items SET sock{socket} = ?2 WHERE id = ?1"), params![item, kind.0])?;
			t.ledger(Row {
				op: "SOCKET",
				item: Some(*item),
				stack: Some(*kind),
				from: Some(place_cols(&it.place)),
				from_acct: Some(h.account),
				count: 1,
				data: socket.to_string(),
				..Default::default()
			})?;
			Ok(Reply::Done)
		}
		Cmd::Unsocket { hero, item, socket } => {
			let h = t.own_hero(*hero)?;
			let it = t.carried(*hero, *item, true)?;
			if *socket >= it.spec.sockets {
				return Err(Error::Missing(format!("socket {socket} of item {item}")));
			}
			let Some(kind) = it.socketed[*socket as usize] else {
				return Err(Error::Missing(format!("socket {socket} of item {item} is empty")));
			};
			t.exec(&format!("UPDATE items SET sock{socket} = NULL WHERE id = ?1"), [item])?;
			t.ledger(Row {
				op: "UNSOCKET",
				item: Some(*item),
				stack: Some(kind),
				from: Some(place_cols(&it.place)),
				from_acct: Some(h.account),
				count: 1,
				data: socket.to_string(),
				..Default::default()
			})?;
			let o = Owner::bag(*hero);
			t.stack_add(&o, kind, 1)?;
			t.credit_row(&o, Party::Account(h.account), kind, 1, false, "unsocket")?;
			Ok(Reply::Done)
		}
		Cmd::StackCredit { to, kind, count, minted, reason } => {
			Tx::check_kind(*kind, *count)?;
			check_reason(reason)?;
			let party = t.stack_owner(to)?;
			t.may_touch(party, "stack owner")?;
			let n = t.stack_add(to, *kind, *count)?;
			t.credit_row(to, party, *kind, *count, *minted, reason)?;
			Ok(Reply::Count(n))
		}
		Cmd::StackDebit { from, kind, count, reason } => {
			Tx::check_kind(*kind, *count)?;
			check_reason(reason)?;
			let party = t.stack_owner(from)?;
			t.may_touch(party, "stack owner")?;
			let n = t.stack_sub(from, *kind, *count)?;
			t.debit_row("DEBIT", from, party, *kind, *count, reason)?;
			Ok(Reply::Count(n))
		}
		Cmd::StackTransfer { from, to, kind, count } => {
			Tx::check_kind(*kind, *count)?;
			if from == to {
				return Err(inv("same owner"));
			}
			if matches!(from.kind, PlaceKind::Market | PlaceKind::Trade) || matches!(to.kind, PlaceKind::Market | PlaceKind::Trade) {
				return Err(inv("stacks reach a market or trade only through those operations"));
			}
			let fp = t.stack_owner(from)?;
			t.may_touch(fp, "stack owner")?;
			let tp = t.stack_owner(to)?;
			t.may_touch(tp, "destination")?;
			t.check_flow(fp, tp)?;
			if from.kind.hero_owned() && to.kind.hero_owned() && from.id != to.id {
				// stacks have no origin, so a self-found hero neither gives nor takes them from another hero
				if t.is_self_found(from.id)? || t.is_self_found(to.id)? {
					return Err(Error::Refused);
				}
			}
			let n = t.stack_sub(from, *kind, *count)?;
			t.stack_add(to, *kind, *count)?;
			t.ledger(Row {
				op: "TRANSFER",
				stack: Some(*kind),
				from: Some(owner_cols(from)),
				from_acct: acct_of(fp),
				to: Some(owner_cols(to)),
				to_acct: acct_of(tp),
				count: *count,
				..Default::default()
			})?;
			Ok(Reply::Count(n))
		}
		Cmd::Outing { hero, delta: d } => outing(t, *hero, d),
		Cmd::Plunder { from, to, items, stacks, coin } => plunder(t, *from, *to, items, stacks, *coin),
		Cmd::Trade { a, b } => trade(t, a, b),
		Cmd::GrantEntitlement { account, kind, count, purchase } => {
			t.account_row(*account)?;
			if *count == 0 || *count > 1000 || purchase.is_empty() || purchase.len() > 128 {
				return Err(inv("entitlement count or purchase id"));
			}
			if let Some((acct, k, c)) = t.one(
				"SELECT account, kind, count FROM purchases WHERE purchase = ?1",
				[purchase],
				|r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?, r.get::<_, u32>(2)?)),
			)? {
				if acct != *account || k != *kind as i64 || c != *count {
					return Err(inv(format!("purchase {purchase} was granted with other terms")));
				}
				return Ok(Reply::Granted { new: false, total: t.entitlement(*account, *kind)? });
			}
			t.exec(
				"INSERT INTO purchases (purchase, account, kind, count, time) VALUES (?1, ?2, ?3, ?4, ?5)",
				params![purchase, account, *kind as i64, count, now],
			)?;
			let total = t.entitlement(*account, *kind)? + count;
			t.exec(
				"INSERT INTO entitlements (account, kind, count) VALUES (?1, ?2, ?3) \
				ON CONFLICT (account, kind) DO UPDATE SET count = excluded.count",
				params![account, *kind as i64, total],
			)?;
			t.ledger(Row {
				op: "ENTITLE",
				to_acct: Some(*account),
				count: *count as u64,
				reason: "purchase",
				data: format!("kind {} purchase {purchase} total {total}", *kind as i64),
				..Default::default()
			})?;
			Ok(Reply::Granted { new: true, total })
		}
		Cmd::BuyEntitlement { hero, kind, have, price, reason } => {
			check_reason(reason)?;
			let h = t.live_hero(*hero)?;
			let now_have = t.entitlement(h.account, *kind)?;
			if now_have != *have {
				return Err(inv(format!("she has {now_have} of that, not {have}")));
			}
			if *kind == EntitlementKind::BankTab && FREE_BANK_TABS + now_have >= BANK_TABS_MAX {
				return Err(Error::Full(format!("{BANK_TABS_MAX} bank tabs is the most")));
			}
			if *price > 0 {
				let o = Owner::bag(*hero);
				t.stack_sub(&o, StackKind::COIN, *price)?;
				t.debit_row("DEBIT", &o, Party::Account(h.account), StackKind::COIN, *price, reason)?;
			}
			let total = now_have + 1;
			t.exec(
				"INSERT INTO entitlements (account, kind, count) VALUES (?1, ?2, ?3) \
				ON CONFLICT (account, kind) DO UPDATE SET count = excluded.count",
				params![h.account, *kind as i64, total],
			)?;
			t.ledger(Row {
				op: "ENTITLE",
				to_acct: Some(h.account),
				count: 1,
				reason,
				data: format!("kind {} hero {hero} price {price} total {total}", *kind as i64),
				..Default::default()
			})?;
			Ok(Reply::Granted { new: true, total })
		}
		Cmd::HeroFeat { hero, feat } => {
			let h = t.live_hero(*hero)?;
			if *feat == 0 {
				return Err(inv("feat"));
			}
			if t.one("SELECT 1 FROM feats WHERE hero = ?1 AND feat = ?2", params![hero, feat], |r| r.get::<_, i64>(0))?.is_none() {
				t.exec("INSERT INTO feats (hero, feat, time) VALUES (?1, ?2, ?3)", params![hero, feat, now])?;
				t.ledger(Row { op: "FEAT", to_acct: Some(h.account), data: format!("hero {hero} feat {feat}"), ..Default::default() })?;
			}
			Ok(Reply::Done)
		}
		Cmd::TakeJob { hero, job, price } => {
			let h = t.live_hero(*hero)?;
			if *job >= 16 {
				return Err(inv("job"));
			}
			if *price > 0 {
				let o = Owner::bag(*hero);
				t.stack_sub(&o, StackKind::COIN, *price)?;
				t.debit_row("DEBIT", &o, Party::Account(h.account), StackKind::COIN, *price, "job")?;
			}
			t.exec("UPDATE heroes SET job = ?2 WHERE id = ?1", params![hero, job])?;
			t.ledger(Row { op: "JOB", to_acct: Some(h.account), data: format!("hero {hero} job {job} price {price}"), ..Default::default() })?;
			Ok(Reply::Done)
		}
		Cmd::Clawback { items, stacks, reason } => clawback(t, items, stacks, reason),
		Cmd::ParcelPut { kind, from, to, items, stacks, price, fee, expires, text } => {
			crate::parcels::put(t, *kind, *from, *to, items, stacks, *price, *fee, *expires, text)
		}
		Cmd::ParcelTake { parcel, hero, tax } => crate::parcels::take(t, *parcel, *hero, *tax),
		Cmd::ParcelReturn { parcel } => crate::parcels::give_back(t, *parcel),
	}
}

/// A name a hero deleted more than 7 days ago no longer holds.
fn release_stale_name(t: &Tx, key: &str) -> Result<()> {
	t.exec(
		"UPDATE heroes SET name_held = 0 WHERE name_key = ?1 AND name_held = 1 AND deleted_at IS NOT NULL AND deleted_at < ?2",
		params![key, t.req.now - UNDELETE_MS],
	)?;
	Ok(())
}

fn outing(t: &mut Tx, hero: HeroId, d: &OutingDelta) -> Result<Reply> {
	let h = t.own_hero(hero)?;
	let party = Party::Account(h.account);
	let bag = Owner::bag(hero);
	let mail = Owner { kind: PlaceKind::Mail, id: hero };
	for (k, n) in &d.potions_used {
		if k.class() != Some(StackClass::Potion) {
			return Err(inv(format!("{} is not a potion", k.0)));
		}
		Tx::check_kind(*k, *n)?;
		t.stack_sub(&bag, *k, *n)?;
		t.debit_row("DEBIT", &bag, party, *k, *n, "drunk")?;
	}
	if d.coin > 0 {
		i64_of(d.coin, "coin")?;
		t.stack_add(&bag, StackKind::COIN, d.coin)?;
		t.credit_row(&bag, party, StackKind::COIN, d.coin, true, "haul")?;
	}
	for (k, n) in &d.stacks {
		Tx::check_kind(*k, *n)?;
		// a new slot-taking kind with no room in the bag goes to the hero's mail: nothing banked is dropped
		let to = match t.stack_add(&bag, *k, *n) {
			Ok(_) => bag,
			Err(Error::Full(_)) => {
				t.stack_add(&mail, *k, *n)?;
				mail
			}
			Err(e) => return Err(e),
		};
		t.credit_row(&to, party, *k, *n, true, "haul")?;
	}
	for &(victim, n) in &d.plundered {
		i64_of(n, "coin")?;
		if n == 0 {
			return Err(inv("plundered coin must be above zero"));
		}
		plundered_coin(t, victim, hero, party, n)?;
	}
	let mut minted = Vec::with_capacity(d.items.len());
	for sp in &d.items {
		Tx::check_spec(sp)?;
		let (p, pp) = match t.resolve(&Dest::bag(hero), sp, false) {
			Ok(x) => x,
			Err(Error::Full(_)) => t.resolve(&Dest::any(PlaceKind::Mail, hero), sp, false)?,
			Err(e) => return Err(e),
		};
		let id = t.mint_at(&p, pp, sp, "haul")?;
		minted.push((id, p));
	}
	let (lvl, xp, unspent): (u16, i64, u16) = t
		.one("SELECT class_level, class_xp, unspent FROM heroes WHERE id = ?1", [hero], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)))?
		.unwrap();
	let new_lvl = lvl as u32 + d.levels as u32;
	if new_lvl > MAX_LEVEL as u32 {
		return Err(inv("class level above 60"));
	}
	let new_xp = (xp as u64).checked_add(d.xp).ok_or_else(|| inv("xp"))?;
	let mut ways: Vec<i32> = split_nums(&t.one("SELECT waystones FROM heroes WHERE id = ?1", [hero], |r| r.get::<_, String>(0))?.unwrap());
	if let Some((f, w)) = d.waystone {
		if f as usize >= FIELDS || w < -1 {
			return Err(inv("waystone"));
		}
		ways[f as usize] = w;
	}
	t.exec(
		"UPDATE heroes SET class_level = ?2, class_xp = ?3, unspent = ?4, waystones = ?5 WHERE id = ?1",
		params![hero, new_lvl, i64_of(new_xp, "xp")?, unspent as u32 + d.levels as u32, join_nums(&ways)],
	)?;
	t.ledger(Row {
		op: "OUTING",
		to_acct: Some(h.account),
		count: d.xp,
		data: format!("hero {hero} xp {} levels {} items {} coin {}", d.xp, d.levels, d.items.len(), d.coin),
		..Default::default()
	})?;
	Ok(Reply::Items(minted))
}

/// Coin a hero banks that she took in a plunder (`OutingDelta::plundered`): a CREDIT minted for the victim (in her
/// mail, a waypoint inside the transaction) and a TRANSFER to the winner's bag, so the victim's trace, forward trace
/// and clawback plan reach it. When the two may not trade (self-found, a trade lock, the victim deleted) it is banked
/// as the winner's own haul, as before job R3b.
fn plundered_coin(t: &mut Tx, victim: HeroId, hero: HeroId, party: Party, n: u64) -> Result<()> {
	let bag = Owner::bag(hero);
	let vh = t.hero_row(victim).ok().filter(|v| v.deleted_at.is_none() && victim != hero);
	let ok = match &vh {
		Some(v) => !t.is_self_found(victim)? && !t.is_self_found(hero)? && t.check_flow(Party::Account(v.account), party).is_ok(),
		None => false,
	};
	let Some(v) = vh.filter(|_| ok) else {
		t.stack_add(&bag, StackKind::COIN, n)?;
		return t.credit_row(&bag, party, StackKind::COIN, n, true, "haul");
	};
	let vp = Party::Account(v.account);
	let way = Owner { kind: PlaceKind::Mail, id: victim };
	t.stack_add(&way, StackKind::COIN, n)?;
	t.credit_row(&way, vp, StackKind::COIN, n, true, "plunder")?;
	t.stack_sub(&way, StackKind::COIN, n)?;
	t.stack_add(&bag, StackKind::COIN, n)?;
	t.ledger(Row {
		op: "TRANSFER",
		stack: Some(StackKind::COIN),
		from: Some(owner_cols(&way)),
		from_acct: Some(v.account),
		to: Some(owner_cols(&bag)),
		to_acct: acct_of(party),
		count: n,
		reason: "plunder",
		..Default::default()
	})?;
	Ok(())
}

/// Puts one item or stack of a plundered haul down: minted for the victim (she stays its origin hero and account;
/// her mail is the waypoint when it goes on to the winner), then moved to the winner's bag, his mail when the bag is
/// full. With no winner it stays with her: her bag, her mail when full. Mail has no limit, so nothing is dropped.
fn plunder_item(t: &mut Tx, from: HeroId, fp: Party, win: Option<(HeroId, Party)>, sp: &ItemSpec) -> Result<(ItemId, Place)> {
	let Some((to, _)) = win else {
		let (p, pp) = match t.resolve(&Dest::bag(from), sp, false) {
			Ok(x) => x,
			Err(Error::Full(_)) => t.resolve(&Dest::any(PlaceKind::Mail, from), sp, false)?,
			Err(e) => return Err(e),
		};
		let id = t.mint_at(&p, pp, sp, "haul")?;
		return Ok((id, p));
	};
	let (p, _) = t.resolve(&Dest::any(PlaceKind::Mail, from), sp, false)?;
	let id = t.mint_at(&p, fp, sp, "plunder")?;
	let it = t.load_item(id)?;
	let (dest, dp) = match t.resolve(&Dest::bag(to), sp, false) {
		Ok(x) => x,
		Err(Error::Full(_)) => t.resolve(&Dest::any(PlaceKind::Mail, to), sp, false)?,
		Err(e) => return Err(e),
	};
	t.set_place(id, &dest)?;
	t.move_row("MOVE", &it, fp, &dest, dp)?;
	Ok((id, dest))
}

fn plunder_stack(t: &mut Tx, from: HeroId, fp: Party, win: Option<(HeroId, Party)>, k: StackKind, n: u64) -> Result<()> {
	let spill = |t: &mut Tx, h: HeroId| -> Result<Owner> {
		let bag = Owner::bag(h);
		match t.stack_add(&bag, k, n) {
			Ok(_) => Ok(bag),
			Err(Error::Full(_)) => {
				let mail = Owner { kind: PlaceKind::Mail, id: h };
				t.stack_add(&mail, k, n)?;
				Ok(mail)
			}
			Err(e) => Err(e),
		}
	};
	let Some((to, tp)) = win else {
		let o = spill(t, from)?;
		return t.credit_row(&o, fp, k, n, true, "haul");
	};
	let way = Owner { kind: PlaceKind::Mail, id: from };
	t.stack_add(&way, k, n)?;
	t.credit_row(&way, fp, k, n, true, "plunder")?;
	t.stack_sub(&way, k, n)?;
	let dest = spill(t, to)?;
	t.ledger(Row {
		op: "TRANSFER",
		stack: Some(k),
		from: Some(owner_cols(&way)),
		from_acct: acct_of(fp),
		to: Some(owner_cols(&dest)),
		to_acct: acct_of(tp),
		count: n,
		reason: "plunder",
		..Default::default()
	})?;
	Ok(())
}

/// A plundered fall (`Cmd::Plunder`), one transaction with ledger lines on both sides: the PLUNDER row (victim's
/// account to the winner's; `coin` is only recorded: the coin is in the winner's haul and moves when he banks it,
/// `OutingDelta::plundered`), then each item and stack minted for the victim and moved to the winner
/// (`plunder_item`, `plunder_stack`). Nothing is ever lost: a bound item, and everything when the winner may not take
/// it (deleted, self-found on either side, a trade lock), stays with the victim (her bag, or her mail).
fn plunder(t: &mut Tx, from: HeroId, to: HeroId, items: &[ItemSpec], stacks: &[(StackKind, u64)], coin: u64) -> Result<Reply> {
	if from == to {
		return Err(inv("a hero cannot plunder herself"));
	}
	i64_of(coin, "coin")?;
	let hf = t.live_hero(from)?;
	let fp = Party::Account(hf.account);
	for sp in items {
		Tx::check_spec(sp)?;
	}
	for (k, n) in stacks {
		Tx::check_kind(*k, *n)?;
	}
	let ht = t.hero_row(to).ok().filter(|h| h.deleted_at.is_none());
	// The self-found rule (she gives nothing to another hero, and holds only what was minted for her) and a
	// trade lock (no value moves between a locked account and another) hold for a plunder too.
	let win = match &ht {
		Some(h) if !t.is_self_found(from)? && !t.is_self_found(to)? && t.check_flow(fp, Party::Account(h.account)).is_ok() => {
			Some((to, Party::Account(h.account)))
		}
		_ => None,
	};
	let bound = items.iter().filter(|sp| sp.bound).count();
	t.ledger(Row {
		op: "PLUNDER",
		from_acct: Some(hf.account),
		to_acct: ht.as_ref().map(|h| h.account),
		count: coin,
		reason: if win.is_some() { "plunder" } else { "refused" },
		data: format!("hero {from} -> hero {to} items {} bound {bound} stacks {} coin {coin}", items.len(), stacks.len()),
		..Default::default()
	})?;
	let mut placed = Vec::with_capacity(items.len());
	for sp in items {
		// A bound item is never plundered: it stays with her.
		placed.push(plunder_item(t, from, fp, if sp.bound { None } else { win }, sp)?);
	}
	for (k, n) in stacks {
		plunder_stack(t, from, fp, win, *k, *n)?;
	}
	Ok(Reply::Items(placed))
}

fn trade(t: &mut Tx, a: &TradeSide, b: &TradeSide) -> Result<Reply> {
	if a.hero == b.hero {
		return Err(inv("a hero cannot trade with herself"));
	}
	let ha = t.live_hero(a.hero)?;
	let hb = t.live_hero(b.hero)?;
	let pa = Party::Account(ha.account);
	let pb = Party::Account(hb.account);
	t.check_flow(pa, pb)?;
	if t.is_self_found(a.hero)? || t.is_self_found(b.hero)? {
		return Err(Error::Refused);
	}
	let mut ids = std::collections::BTreeSet::new();
	let mut staged = Vec::new();
	for (side, other) in [(a, b), (b, a)] {
		for id in &side.items {
			if !ids.insert(*id) {
				return Err(inv(format!("item {id} listed twice")));
			}
			let it = t.carried(side.hero, *id, false)?;
			if it.spec.bound {
				return Err(Error::Bound(*id));
			}
			staged.push((it, other.hero));
		}
		for (k, n) in &side.stacks {
			Tx::check_kind(*k, *n)?;
		}
	}
	// stage every traded item off both bags first, so the receivers' slots are free to reuse
	for (i, (it, _)) in staged.iter().enumerate() {
		t.set_place(it.id, &Place { kind: PlaceKind::Trade, owner: 0, tab: 0, slot: i as u32 })?;
	}
	for side in [a, b] {
		let o = Owner::bag(side.hero);
		for (k, n) in &side.stacks {
			t.stack_sub(&o, *k, *n)?;
		}
	}
	for (it, to_hero) in &staged {
		let (p, to_party) = t.resolve(&Dest::bag(*to_hero), &it.spec, false)?;
		let from_party = if *to_hero == b.hero { pa } else { pb };
		t.set_place(it.id, &p)?;
		t.move_row("TRADE", it, from_party, &p, to_party)?;
	}
	for (side, other, fp, tp) in [(a, b, pa, pb), (b, a, pb, pa)] {
		let from = Owner::bag(side.hero);
		let to = Owner::bag(other.hero);
		for (k, n) in &side.stacks {
			t.stack_add(&to, *k, *n)?;
			t.ledger(Row {
				op: "TRADE",
				stack: Some(*k),
				from: Some(owner_cols(&from)),
				from_acct: acct_of(fp),
				to: Some(owner_cols(&to)),
				to_acct: acct_of(tp),
				count: *n,
				..Default::default()
			})?;
		}
	}
	Ok(Reply::Done)
}

/// Items of a container that hold `kind` in a socket, for a stack clawback that finds the stack short.
fn socket_holders(t: &Tx, o: &Owner, kind: StackKind) -> Result<Vec<(ItemId, u8)>> {
	let kinds: Vec<i64> = match o.kind {
		PlaceKind::Bag => vec![PlaceKind::Bag as i64, PlaceKind::Worn as i64],
		k => vec![k as i64],
	};
	let mut out = Vec::new();
	for k in kinds {
		crash::point(Site::Stmt);
		let mut st = t.c.prepare_cached(
			"SELECT id, sock0, sock1 FROM items WHERE place_kind = ?1 AND place_owner = ?2 AND (sock0 = ?3 OR sock1 = ?3) ORDER BY id",
		)?;
		let rows = st.query_map(params![k, o.id, kind.0], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, Option<u32>>(1)?, r.get::<_, Option<u32>>(2)?)))?;
		for r in rows {
			let (id, s0, s1) = r?;
			if s0 == Some(kind.0) {
				out.push((id, 0));
			}
			if s1 == Some(kind.0) {
				out.push((id, 1));
			}
		}
	}
	Ok(out)
}

fn clawback(t: &mut Tx, items: &[ItemId], stacks: &[(Owner, StackKind, u64)], reason: &str) -> Result<Reply> {
	check_reason(reason)?;
	let mut removed = Vec::new();
	let mut missing = Vec::new();
	let mut seen = std::collections::BTreeSet::new();
	// parcels whose escrow this clawback touches: one left holding nothing ends with it (fuzz seed 922952)
	let mut parcels = std::collections::BTreeSet::new();
	for id in items {
		if !seen.insert(*id) {
			continue;
		}
		match t.load_item(*id) {
			Ok(it) => {
				if it.place.kind == PlaceKind::Market {
					parcels.insert(it.place.owner);
				}
				let party = t.party(it.place.kind, it.place.owner).unwrap_or(Party::Account(0));
				t.destroy(&it, party, "CLAWBACK", reason)?;
				removed.push(*id);
			}
			Err(Error::Missing(_)) => missing.push(*id),
			Err(e) => return Err(e),
		}
	}
	let mut shortfall = Vec::new();
	for (o, k, want) in stacks {
		Tx::check_kind(*k, *want)?;
		if o.kind == PlaceKind::Worn {
			return Err(inv("worn holds no stacks"));
		}
		let party = party_of(t.c, o.kind, o.id).unwrap_or(Party::Account(0));
		let have = t.stack_get(o, *k)?;
		let take = have.min(*want);
		if take > 0 {
			if o.kind == PlaceKind::Market {
				parcels.insert(o.id);
			}
			t.stack_sub(o, *k, take)?;
			t.debit_row("CLAWBACK", o, party, *k, take, reason)?;
		}
		let mut left = *want - take;
		if left > 0 && k.socketable() {
			for (id, sock) in socket_holders(t, o, *k)? {
				if left == 0 {
					break;
				}
				let it = t.load_item(id)?;
				t.exec(&format!("UPDATE items SET sock{sock} = NULL WHERE id = ?1"), [id])?;
				t.ledger(Row {
					op: "CLAWBACK",
					item: Some(id),
					stack: Some(*k),
					from: Some(place_cols(&it.place)),
					from_acct: acct_of(party),
					count: 1,
					reason,
					data: sock.to_string(),
					..Default::default()
				})?;
				left -= 1;
			}
		}
		if left > 0 {
			shortfall.push((*o, *k, left));
		}
	}
	for p in parcels {
		crate::parcels::end_if_empty(t, p)?;
	}
	Ok(Reply::Clawback { removed, missing, shortfall })
}

/// The command text a request's argument hash covers, for diagnostics.
pub fn describe(c: &Cmd) -> String {
	encode_cmd(c)
}
