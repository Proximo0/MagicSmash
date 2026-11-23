//! The schema and its migrations. `migrate` runs at open: it reads `schema_version` and applies every later step,
//! each in its own transaction. Version 1 is the first design; version 2 adds origins, flags and ledger parties.

use rusqlite::{Connection, OptionalExtension};

pub const LATEST: i64 = 4;

pub const V1: &str = r#"
CREATE TABLE schema_version (version INTEGER NOT NULL);
INSERT INTO schema_version VALUES (1);

CREATE TABLE accounts (
	id INTEGER PRIMARY KEY,
	steam_id INTEGER UNIQUE,
	dev_name TEXT UNIQUE,
	created INTEGER NOT NULL,
	banned_until INTEGER,
	flags INTEGER NOT NULL DEFAULT 0,
	CHECK (steam_id IS NOT NULL OR dev_name IS NOT NULL)
);

CREATE TABLE entitlements (
	account INTEGER NOT NULL REFERENCES accounts(id),
	kind INTEGER NOT NULL,
	count INTEGER NOT NULL CHECK (count >= 0),
	PRIMARY KEY (account, kind)
) WITHOUT ROWID;

CREATE TABLE purchases (
	purchase TEXT PRIMARY KEY,
	account INTEGER NOT NULL REFERENCES accounts(id),
	kind INTEGER NOT NULL,
	count INTEGER NOT NULL,
	time INTEGER NOT NULL
) WITHOUT ROWID;

CREATE TABLE heroes (
	id INTEGER PRIMARY KEY,
	account INTEGER NOT NULL REFERENCES accounts(id),
	name TEXT NOT NULL,
	name_key TEXT NOT NULL,
	name_held INTEGER NOT NULL DEFAULT 1,
	race INTEGER NOT NULL,
	class INTEGER NOT NULL,
	job INTEGER NOT NULL DEFAULT 0,
	look INTEGER NOT NULL,
	class_level INTEGER NOT NULL DEFAULT 1 CHECK (class_level BETWEEN 1 AND 60),
	class_xp INTEGER NOT NULL DEFAULT 0 CHECK (class_xp >= 0),
	stats TEXT NOT NULL,
	unspent INTEGER NOT NULL DEFAULT 0 CHECK (unspent >= 0),
	deck TEXT NOT NULL,
	belt TEXT NOT NULL,
	waystones TEXT NOT NULL,
	self_found INTEGER NOT NULL DEFAULT 0,
	created INTEGER NOT NULL,
	deleted_at INTEGER
);
CREATE UNIQUE INDEX heroes_name ON heroes (name_key) WHERE name_held = 1;
CREATE INDEX heroes_account ON heroes (account);

CREATE TABLE owned_cards (
	account INTEGER NOT NULL REFERENCES accounts(id),
	card INTEGER NOT NULL,
	PRIMARY KEY (account, card)
) WITHOUT ROWID;

CREATE TABLE items (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	base INTEGER NOT NULL,
	gear_slot INTEGER NOT NULL CHECK (gear_slot BETWEEN 0 AND 5),
	item_level INTEGER NOT NULL,
	rarity INTEGER NOT NULL CHECK (rarity BETWEEN 0 AND 4),
	lines TEXT NOT NULL,
	sockets INTEGER NOT NULL CHECK (sockets BETWEEN 0 AND 2),
	sock0 INTEGER,
	sock1 INTEGER,
	plus INTEGER NOT NULL DEFAULT 0,
	bound INTEGER NOT NULL DEFAULT 0,
	place_kind INTEGER NOT NULL CHECK (place_kind BETWEEN 1 AND 8),
	place_owner INTEGER NOT NULL,
	place_tab INTEGER NOT NULL,
	place_slot INTEGER NOT NULL,
	minted INTEGER NOT NULL,
	UNIQUE (place_kind, place_owner, place_tab, place_slot)
);

CREATE TABLE stacks (
	owner_kind INTEGER NOT NULL,
	owner INTEGER NOT NULL,
	kind INTEGER NOT NULL,
	count INTEGER NOT NULL CHECK (count >= 0),
	PRIMARY KEY (owner_kind, owner, kind)
) WITHOUT ROWID;

CREATE TABLE ledger (
	seq INTEGER PRIMARY KEY,
	time INTEGER NOT NULL,
	request BLOB NOT NULL,
	actor INTEGER NOT NULL,
	op TEXT NOT NULL,
	item INTEGER,
	stack_kind INTEGER,
	from_kind INTEGER, from_owner INTEGER, from_tab INTEGER, from_slot INTEGER,
	to_kind INTEGER, to_owner INTEGER, to_tab INTEGER, to_slot INTEGER,
	count INTEGER NOT NULL DEFAULT 0,
	reason TEXT NOT NULL DEFAULT '',
	data TEXT NOT NULL DEFAULT ''
);
CREATE INDEX ledger_request ON ledger (request);
CREATE INDEX ledger_item ON ledger (item) WHERE item IS NOT NULL;

CREATE TABLE requests (
	id BLOB PRIMARY KEY,
	args INTEGER NOT NULL,
	op TEXT NOT NULL,
	reply TEXT NOT NULL,
	ledger_first INTEGER NOT NULL,
	ledger_last INTEGER NOT NULL,
	time INTEGER NOT NULL
) WITHOUT ROWID;
"#;

/// Version 2 (the lead's addition of 21 Nov): every item keeps who it was minted for and its mint row; accounts
/// get operator flags with a drops percent; ledger rows name the account on each side and whether value was
/// minted. Backfilled from the ledger.
pub const V2: &str = r#"
ALTER TABLE items ADD COLUMN origin_account INTEGER NOT NULL DEFAULT 0;
ALTER TABLE items ADD COLUMN origin_hero INTEGER;
ALTER TABLE items ADD COLUMN mint_seq INTEGER NOT NULL DEFAULT 0;
ALTER TABLE accounts ADD COLUMN drops_percent INTEGER NOT NULL DEFAULT 100;
ALTER TABLE ledger ADD COLUMN from_acct INTEGER;
ALTER TABLE ledger ADD COLUMN to_acct INTEGER;
ALTER TABLE ledger ADD COLUMN minted INTEGER NOT NULL DEFAULT 0;

UPDATE ledger SET from_acct = CASE
	WHEN from_kind IN (1, 2, 4) THEN (SELECT account FROM heroes WHERE heroes.id = ledger.from_owner)
	WHEN from_kind IN (3, 7) THEN from_owner END
	WHERE from_kind IS NOT NULL;
UPDATE ledger SET to_acct = CASE
	WHEN to_kind IN (1, 2, 4) THEN (SELECT account FROM heroes WHERE heroes.id = ledger.to_owner)
	WHEN to_kind IN (3, 7) THEN to_owner END
	WHERE to_kind IS NOT NULL;
UPDATE ledger SET minted = 1 WHERE op = 'MINT' OR (op = 'CREDIT' AND reason <> 'unsocket' AND reason <> 'buy');

UPDATE items SET
	mint_seq = (SELECT min(seq) FROM ledger WHERE ledger.item = items.id AND ledger.op = 'MINT'),
	origin_account = coalesce((SELECT to_acct FROM ledger WHERE ledger.item = items.id AND ledger.op = 'MINT'
		ORDER BY seq LIMIT 1), 0),
	origin_hero = (SELECT CASE WHEN to_kind IN (1, 2, 4) THEN to_owner END FROM ledger
		WHERE ledger.item = items.id AND ledger.op = 'MINT' ORDER BY seq LIMIT 1);

CREATE INDEX items_origin ON items (origin_account);
CREATE INDEX ledger_from_acct ON ledger (from_acct) WHERE from_acct IS NOT NULL;
CREATE INDEX ledger_to_acct ON ledger (to_acct) WHERE to_acct IS NOT NULL;
CREATE INDEX ledger_from_guild ON ledger (from_owner) WHERE from_kind = 8;
UPDATE schema_version SET version = 2;
"#;

/// Version 3 (job E1, additive): parcels. A parcel is what the market and letters hold in escrow: a listing
/// (one item or one stack for a price, any hero may buy) or a letter (attachments for one hero, with an optional
/// cash-on-delivery price). Its things sit in the MARKET place (items) and the MARKET stack owner, owner = the
/// parcel id; this table is the record: who sent it, to whom, the price and when it ends. Ids are never reused.
pub const V3: &str = r#"
CREATE TABLE parcels (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	kind INTEGER NOT NULL CHECK (kind IN (1, 2)),
	from_hero INTEGER NOT NULL REFERENCES heroes(id),
	to_hero INTEGER REFERENCES heroes(id),
	price INTEGER NOT NULL CHECK (price >= 0),
	created INTEGER NOT NULL,
	expires INTEGER NOT NULL,
	text TEXT NOT NULL DEFAULT '',
	-- a listing's one entry, copied here so a search is an index walk and not a scan of every listing
	gear_slot INTEGER,
	item_level INTEGER,
	rarity INTEGER,
	stack_kind INTEGER
);
CREATE INDEX parcels_from ON parcels (from_hero);
CREATE INDEX parcels_to ON parcels (to_hero) WHERE to_hero IS NOT NULL;
CREATE INDEX parcels_expires ON parcels (expires);
CREATE INDEX parcels_kind ON parcels (kind, expires);
CREATE INDEX parcels_slot_price ON parcels (gear_slot, price) WHERE kind = 1 AND gear_slot IS NOT NULL;
CREATE INDEX parcels_stack_price ON parcels (stack_kind, price) WHERE kind = 1 AND stack_kind IS NOT NULL;
CREATE INDEX parcels_price ON parcels (price) WHERE kind = 1;
UPDATE schema_version SET version = 3;
"#;

/// Version 4 (additive): feats, what a hero has done for good (`Cmd::HeroFeat`; 1: she passed THE CLASS TRIAL).
pub const V4: &str = r#"
CREATE TABLE feats (
	hero INTEGER NOT NULL REFERENCES heroes(id),
	feat INTEGER NOT NULL,
	time INTEGER NOT NULL,
	PRIMARY KEY (hero, feat)
) WITHOUT ROWID;
UPDATE schema_version SET version = 4;
"#;

pub const STEPS: [&str; 4] = [V1, V2, V3, V4];

pub fn version(c: &Connection) -> rusqlite::Result<i64> {
	let has: Option<String> = c
		.query_row("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'schema_version'", [], |r| r.get(0))
		.optional()?;
	if has.is_none() {
		return Ok(0);
	}
	c.query_row("SELECT version FROM schema_version", [], |r| r.get(0))
}

/// Brings the database from its version up to `target`, one transaction a step. Returns the steps applied.
pub fn migrate_to(c: &Connection, target: i64) -> rusqlite::Result<Vec<i64>> {
	let mut done = Vec::new();
	loop {
		let v = version(c)?;
		if v >= target {
			return Ok(done);
		}
		c.execute_batch("BEGIN IMMEDIATE")?;
		// another opener may have migrated between the read and the lock
		let v2 = version(c)?;
		if v2 != v {
			c.execute_batch("ROLLBACK")?;
			continue;
		}
		match c.execute_batch(STEPS[v as usize]) {
			Ok(()) => c.execute_batch("COMMIT")?,
			Err(e) => {
				let _ = c.execute_batch("ROLLBACK");
				return Err(e);
			}
		}
		done.push(v + 1);
	}
}

pub fn migrate(c: &Connection) -> rusqlite::Result<Vec<i64>> {
	migrate_to(c, LATEST)
}
