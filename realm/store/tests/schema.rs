//! Migrations from version 1 up, and verify catching tampering.
mod common;
use common::*;
use realm_store::*;
use rusqlite::{Connection, params};

#[test]
fn migrate_v1_with_data() {
	let path = fresh("v1");
	{
		let c = Connection::open(&path).unwrap();
		c.execute_batch("PRAGMA journal_mode = WAL").unwrap();
		assert_eq!(schema::migrate_to(&c, 1).unwrap(), vec![1]);
		// a version 1 store: an account, a hero, an item minted into its bag, coin, a move to the bank
		let req = 7u128.to_be_bytes();
		c.execute_batch("BEGIN").unwrap();
		c.execute("INSERT INTO accounts (id, steam_id, created) VALUES (1, 55, 0)", []).unwrap();
		c.execute(
			"INSERT INTO heroes (id, account, name, name_key, race, class, look, stats, deck, belt, waystones, created) \
			VALUES (1, 1, 'Old', 'old', 0, 0, 0, '0,0,0,0,0,0', '0,1,2', '0,0,0', '-1,-1,-1,-1,-1,-1', 0)",
			[],
		)
		.unwrap();
		let sp = ops::spec_data(&spec(1));
		c.execute(
			"INSERT INTO items (id, base, gear_slot, item_level, rarity, lines, sockets, place_kind, place_owner, place_tab, place_slot, minted) \
			VALUES (1, 7, 0, 1, 2, '0:3,3:2', 2, 3, 1, 0, 4, 0)",
			[],
		)
		.unwrap();
		c.execute("INSERT INTO stacks VALUES (1, 1, 1, 30)", []).unwrap();
		c.execute(
			"INSERT INTO ledger (seq, time, request, actor, op, item, to_kind, to_owner, to_tab, to_slot, count, reason, data) \
			VALUES (1, 0, ?1, 0, 'MINT', 1, 1, 1, 0, 0, 1, 'drop', ?2)",
			params![&req[..], sp],
		)
		.unwrap();
		c.execute(
			"INSERT INTO ledger (seq, time, request, actor, op, item, from_kind, from_owner, from_tab, from_slot, to_kind, to_owner, to_tab, to_slot, count) \
			VALUES (2, 0, ?1, 0, 'MOVE', 1, 1, 1, 0, 0, 3, 1, 0, 4, 1)",
			params![&req[..]],
		)
		.unwrap();
		c.execute(
			"INSERT INTO ledger (seq, time, request, actor, op, stack_kind, to_kind, to_owner, count, reason) VALUES (3, 0, ?1, 0, 'CREDIT', 1, 1, 1, 30, 'drop')",
			params![&req[..]],
		)
		.unwrap();
		c.execute("INSERT INTO requests VALUES (?1, 0, 'x', 'ok done', 1, 3, 0)", params![&req[..]]).unwrap();
		c.execute_batch("COMMIT").unwrap();
	}
	let s = SqliteStore::open(&path).unwrap();
	let st = s.stats().unwrap();
	assert_eq!(st.schema_version, schema::LATEST);
	let it = s.item(1).unwrap().unwrap();
	assert_eq!((it.origin_account, it.origin_hero, it.mint_seq), (1, Some(1), 1));
	let r = s.verify().unwrap();
	assert!(r.ok(), "{:?}", r.problems);
	let tr = s.trace(1).unwrap();
	assert_eq!(tr.items.len(), 1);
	assert_eq!(tr.stacks[0].minted, 30);
	// the store works on after migrating
	s.mint(Meta::system(99, 5), Dest::bag(1), spec(1), "drop").unwrap();
	assert!(s.verify().unwrap().ok());
	s.close();
	// reopening applies nothing
	let c = Connection::open(&path).unwrap();
	assert_eq!(schema::migrate(&c).unwrap(), Vec::<i64>::new());
}

#[test]
fn fresh_database_is_latest() {
	let path = fresh("v0");
	let s = SqliteStore::open(&path).unwrap();
	assert_eq!(s.stats().unwrap().schema_version, schema::LATEST);
	assert!(s.verify().unwrap().ok());
}

#[test]
fn verify_catches_tampering() {
	let mut t = T::new("tamper");
	let a = t.account(1);
	let h = t.hero(a, "Morwen");
	let i = t.mint_bag(h, 1);
	t.credit(Owner::bag(h), StackKind::COIN, 10);
	t.ok();
	t.s.close();
	let c = Connection::open(&t.path).unwrap();
	// a coin from nowhere
	c.execute("UPDATE stacks SET count = 11 WHERE kind = 1", []).unwrap();
	let r = read::verify(&c).unwrap();
	assert!(r.problems.iter().any(|p| p.contains("stack")), "{:?}", r.problems);
	c.execute("UPDATE stacks SET count = 10 WHERE kind = 1", []).unwrap();
	assert!(read::verify(&c).unwrap().ok());
	// an item moved with no ledger row
	c.execute("UPDATE items SET place_slot = 9 WHERE id = ?1", [i]).unwrap();
	assert!(!read::verify(&c).unwrap().ok());
	c.execute("UPDATE items SET place_slot = 0 WHERE id = ?1", [i]).unwrap();
	// a request applied twice: its ledger rows repeated after the range
	c.execute(
		"INSERT INTO ledger (seq, time, request, actor, op, stack_kind, to_kind, to_owner, count, reason, minted) \
		SELECT (SELECT max(seq) + 1 FROM ledger), time, request, actor, op, stack_kind, to_kind, to_owner, count, reason, minted FROM ledger WHERE op = 'CREDIT'",
		[],
	)
	.unwrap();
	c.execute("UPDATE stacks SET count = 20 WHERE kind = 1", []).unwrap();
	let r = read::verify(&c).unwrap();
	assert!(r.problems.iter().any(|p| p.contains("request")), "{:?}", r.problems);
	// a bag over 40
	let c2 = Connection::open(&t.path).unwrap();
	drop(c2);
}
