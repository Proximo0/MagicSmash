//! Loot against a real store: nothing mints without a ledger row and an origin, delivery is idempotent and
//! overflows to mail, and the smith conserves or destroys value and never copies it.

use realm_core::{CHAMPION, ELITE};
use realm_loot::cards::*;
use realm_loot::gear::*;
use realm_loot::rng::Rng;
use realm_loot::smith::*;
use realm_loot::tables::*;
use realm_loot::*;
use realm_store::*;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(1);
const SECRET: u64 = 424242;

struct Env {
	path: PathBuf,
	s: SqliteStore,
	account: AccountId,
	hero: HeroId,
	n: std::cell::Cell<u128>,
}

fn scratch() -> PathBuf {
	let d = std::env::var("REALM_LOOT_SCRATCH").map(PathBuf::from).unwrap_or_else(|_| std::env::temp_dir().join("realm-loot-tests"));
	std::fs::create_dir_all(&d).unwrap();
	d
}

impl Env {
	fn new(name: &str) -> Env {
		let path = scratch().join(format!("{name}-{}-{}.db", std::process::id(), NEXT.fetch_add(1, Ordering::SeqCst)));
		for s in ["", "-wal", "-shm"] {
			let _ = std::fs::remove_file(format!("{}{s}", path.display()));
		}
		let s = SqliteStore::open_with(&path, Options { group_window: std::time::Duration::ZERO, ..Default::default() }).unwrap();
		let mut e = Env { path, s, account: 0, hero: 0, n: std::cell::Cell::new(1 << 40) };
		let m = e.m();
		e.account = e.s.account_by_dev_name(m, "smithy").unwrap();
		let m = e.m();
		e.hero = e.s.hero_create(m, e.account, "Ashen", 0, 0, 0, false).unwrap();
		e
	}
	fn m(&self) -> Meta {
		self.n.set(self.n.get() + 1);
		Meta::system(self.n.get(), 1_700_000_000_000 + self.n.get() as i64)
	}
	fn smith(&self) -> Smith<'_, SqliteStore> {
		Smith::new(&self.s, SECRET)
	}
	fn give(&self, kind: StackKind, n: u64) {
		let m = self.m();
		let f = Found { what: What::Stack(kind, n), kept: true, reason: Reason::Drop };
		let d = deliver(&self.s, m, self.hero, &[f]);
		assert!(d.failed.is_empty(), "{:?}", d.failed);
	}
	fn give_item(&self, spec: ItemSpec) -> ItemId {
		let m = self.m();
		let f = Found { what: What::Item(spec), kept: true, reason: Reason::Drop };
		deliver(&self.s, m, self.hero, &[f]).items[0].0
	}
	fn stack(&self, k: StackKind) -> u64 {
		self.s.stack(Owner::bag(self.hero), k).unwrap()
	}
	fn item(&self, id: ItemId) -> Option<Item> {
		self.s.item(id).unwrap()
	}
	fn bag_items(&self) -> Vec<Item> {
		self.s.items_at(PlaceKind::Bag, self.hero).unwrap()
	}
	fn ok(&self) {
		let v = self.s.verify().unwrap();
		assert!(v.ok(), "store invariants: {:?}", v.problems);
	}
	/// (MINT rows, items destroyed rows, items alive)
	fn mint_rows(&self) -> (i64, i64, i64) {
		let c = rusqlite::Connection::open(&self.path).unwrap();
		let one = |sql: &str| c.query_row(sql, [], |r| r.get::<_, i64>(0)).unwrap();
		(
			one("SELECT COUNT(*) FROM ledger WHERE op = 'MINT'"),
			one("SELECT COUNT(*) FROM ledger WHERE op = 'DESTROY'"),
			one("SELECT COUNT(*) FROM items"),
		)
	}
}

fn rare_item(rng: &mut Rng, level: u8, rarity: u8) -> ItemSpec {
	make_item(rng, 0, level, rarity)
}

#[test]
fn nothing_mints_without_a_ledger_row_and_an_origin() {
	let e = Env::new("ledger");
	let mut rng = Rng::new(1);
	let mut delivered_items = 0;
	let mut haul = Haul::new();
	for i in 0..6_000u64 {
		let field = (i % 6) as u8;
		let flags = match i % 7 {
			0 => ELITE,
			1 if i % 14 == 1 => CHAMPION,
			_ => 0,
		};
		let kind = realm_core::tables::FIELDS[field as usize].first_kind + (rng.below(6) as u8);
		let key = RollKey { field_seed: 3, tick: i as u32 * 40, index: 0, slot: 0 };
		let drops = roll(SECRET, &key, &Credit { luck: 400, drops_percent: 100 }, &Source::Kill { kind, level: 5 + field * 10, flags }, &mut RollGate::new());
		let kept: Vec<Found> = drops.into_iter().filter_map(|d| haul.take(d)).collect();
		let m = e.m();
		let d = deliver(&e.s, m, e.hero, &kept);
		assert!(d.failed.is_empty(), "{:?}", d.failed);
		delivered_items += d.items.len() as i64;
	}
	// chests too
	let m = e.m();
	let chest = roll(SECRET, &RollKey { field_seed: 1, tick: 1, index: 1, slot: 1 }, &Credit::plain(), &Source::BossChest { boss: 6, level: 58, first_kill: true }, &mut RollGate::new());
	delivered_items += deliver(&e.s, m, e.hero, &chest).items.len() as i64;
	// the haul is banked by an outing: those mints are ledger rows too
	let before = e.s.stats().unwrap();
	let hauled = haul.items.len() as i64;
	let m = e.m();
	let minted = e.s.apply_outing(m, e.hero, haul.into_delta(OutingDelta::default())).unwrap();
	assert_eq!(minted.len() as i64, hauled);
	let after = e.s.stats().unwrap();
	assert!(after.ledger_rows > before.ledger_rows);
	let (mints, destroyed, alive) = e.mint_rows();
	assert_eq!(mints, delivered_items + hauled);
	assert_eq!(destroyed, 0);
	assert_eq!(alive, mints, "every item alive has exactly one MINT row");
	assert!(alive > 100, "the run made {alive} items");
	// every item has an origin: the account, the hero, and the row that minted it
	let mut seen = 0;
	for kind in [PlaceKind::Bag, PlaceKind::Mail] {
		for it in e.s.items_at(kind, e.hero).unwrap() {
			assert_eq!(it.origin_account, e.account);
			assert_eq!(it.origin_hero, Some(e.hero));
			assert!(it.mint_seq > 0);
			seen += 1;
		}
	}
	assert_eq!(seen, alive);
	// stacks: the trace counts them as minted by the account, and the ledger replay agrees with the state
	let tr = e.s.trace(e.account).unwrap();
	assert!(tr.stacks.iter().any(|t| t.kind == StackKind::material(EMBERS) && t.minted > 0));
	for t in &tr.stacks {
		assert_eq!(t.minted, t.holds + t.spent, "kind {:?}: every unit held was minted", t.kind);
	}
	e.ok();
}

#[test]
fn a_hero_with_no_account_gets_nothing() {
	let e = Env::new("nobody");
	let m = Meta::system(77, 5);
	let f = Found { what: What::Stack(StackKind::COIN, 5), kept: true, reason: Reason::Drop };
	let d = deliver(&e.s, m, 9999, &[f]);
	assert_eq!(d.failed.len(), 1);
	assert!(d.stacks.is_empty());
	e.ok();
}

#[test]
fn delivery_is_idempotent_and_overflows_to_mail() {
	let e = Env::new("mail");
	let mut rng = Rng::new(2);
	let drops: Vec<Found> = (0..45).map(|_| Found { what: What::Item(rare_item(&mut rng, 10, RARE)), kept: true, reason: Reason::Chest }).collect();
	let m = e.m();
	let d = deliver(&e.s, m, e.hero, &drops);
	assert_eq!(d.items.len(), 45);
	assert_eq!(d.mailed, 5, "40 fit in the bag, the other 5 went to mail");
	assert_eq!(e.bag_items().len(), 40);
	// the same call again changes nothing
	let again = deliver(&e.s, m, e.hero, &drops);
	assert_eq!(again.items.len(), 45);
	assert_eq!(e.s.stats().unwrap().items, 45);
	e.ok();
}

#[test]
fn account_drop_reduction_is_read_from_the_store() {
	let e = Env::new("reduced");
	assert_eq!(drops_percent_of(&e.s, e.account).unwrap(), 100);
	let m = e.m();
	e.s.apply_flags(m, vec![FlagChange { account: e.account, flags: flags::DROPS_REDUCED, drops_percent: 25, banned_until: None }], "test").unwrap();
	assert_eq!(drops_percent_of(&e.s, e.account).unwrap(), 25);
}

#[test]
fn salvage_destroys_the_item_and_returns_its_sockets() {
	let e = Env::new("salvage");
	let mut rng = Rng::new(3);
	let mut spec = rare_item(&mut rng, 40, RELIC);
	spec.plus = 2;
	let id = e.give_item(spec.clone());
	e.give(StackKind::rune(1, 2), 1);
	e.give(StackKind::card(3), 1);
	e.give(StackKind::COIN, 1000);
	for (i, k) in [StackKind::rune(1, 2), StackKind::card(3)].into_iter().enumerate() {
		e.smith().socket(e.m(), e.hero, id, i as u8, k).unwrap();
	}
	assert_eq!(e.stack(StackKind::rune(1, 2)), 0);
	let coin = e.stack(StackKind::COIN);
	let s = e.smith().salvage(e.m(), e.hero, id).unwrap();
	assert_eq!(s.embers, salvage_embers(&spec));
	assert_eq!(s.embers, (1 + 40 / 10) * 16 * 120 / 100);
	assert_eq!(s.returned.len(), 2);
	assert!(e.item(id).is_none(), "the item is gone");
	assert_eq!(e.stack(StackKind::material(EMBERS)), s.embers);
	assert_eq!(e.stack(StackKind::rune(1, 2)), 1, "its rune came back");
	assert_eq!(e.stack(StackKind::card(3)), 1);
	assert_eq!(e.stack(StackKind::COIN), coin, "salvage costs no coin");
	// not hers: refused, and nothing changes
	let m = e.m();
	let a2 = e.s.account_by_dev_name(m, "other").unwrap();
	let m = e.m();
	let h2 = e.s.hero_create(m, a2, "Other", 0, 0, 0, false).unwrap();
	let id2 = e.give_item(rare_item(&mut rng, 5, COMMON));
	assert!(matches!(e.smith().salvage(e.m(), h2, id2), Err(Error::NotYours(_))));
	assert!(e.item(id2).is_some());
	e.ok();
}

#[test]
fn upgrades_cost_exactly_and_keep_sockets() {
	let e = Env::new("upgrade");
	let mut rng = Rng::new(4);
	let spec = rare_item(&mut rng, 30, RARE);
	let mut id = e.give_item(spec.clone());
	e.give(StackKind::rune(0, 3), 1);
	e.give(StackKind::material(EMBERS), 5_000);
	e.give(StackKind::COIN, 1_000_000);
	e.smith().socket(e.m(), e.hero, id, 0, StackKind::rune(0, 3)).unwrap();
	let mut cur = spec.clone();
	for step in 1..=5u8 {
		let (emb, coin) = (e.stack(StackKind::material(EMBERS)), e.stack(StackKind::COIN));
		let cost = upgrade_cost(&cur).unwrap();
		assert_eq!(cost.embers, (2 + 30 / 3) * step as u64);
		assert_eq!(cost.coin, 4 * 30 * (step as u64).pow(2));
		let up = e.smith().upgrade(e.m(), e.hero, id).unwrap();
		assert!(up.success, "steps to +5 never fail");
		assert_eq!(up.plus, step);
		assert!(e.item(id).is_none(), "the old id is destroyed");
		id = up.item;
		let it = e.item(id).unwrap();
		assert_eq!(it.spec.plus, step);
		assert_eq!(it.spec.lines, spec.lines);
		assert_eq!(it.spec.base, spec.base);
		assert_eq!(it.socketed, vec![Some(StackKind::rune(0, 3))], "the rune stayed in its socket");
		assert_eq!(it.origin_account, e.account);
		assert_eq!(e.stack(StackKind::material(EMBERS)), emb - cost.embers);
		assert_eq!(e.stack(StackKind::COIN), coin - cost.coin);
		cur.plus = step;
	}
	assert_eq!(e.bag_items().len(), 1, "one item, never two");
	assert_eq!(e.stack(StackKind::rune(0, 3)), 0, "the rune is in the socket only");
	e.ok();
}

#[test]
fn a_failed_step_above_plus_five_costs_embers_and_never_the_item() {
	let e = Env::new("fail");
	let mut rng = Rng::new(5);
	e.give(StackKind::material(EMBERS), 1_000_000);
	e.give(StackKind::COIN, 100_000_000);
	let (mut failed, mut won) = (0, 0);
	for i in 0..120 {
		let mut spec = rare_item(&mut rng, 20, EPIC);
		spec.plus = 7; // the +8 step works 50% of the time
		let id = e.give_item(spec.clone());
		let (emb, coin) = (e.stack(StackKind::material(EMBERS)), e.stack(StackKind::COIN));
		let cost = upgrade_cost(&spec).unwrap();
		let up = e.smith().upgrade(e.m(), e.hero, id).unwrap();
		if up.success {
			won += 1;
			assert_eq!(up.plus, 8);
			assert_eq!(e.item(up.item).unwrap().spec.plus, 8);
			assert_eq!(e.stack(StackKind::material(EMBERS)), emb - cost.embers);
			assert_eq!(e.stack(StackKind::COIN), coin - cost.coin);
		} else {
			failed += 1;
			assert_eq!(up.item, id, "the item is the same one");
			assert_eq!(e.item(id).unwrap().spec, spec);
			assert_eq!(e.stack(StackKind::material(EMBERS)), emb - cost.embers, "the embers are lost");
			assert_eq!(e.stack(StackKind::COIN), coin, "no coin on a failure");
		}
		let _ = i;
		// clear the bag for the next
		let items = e.bag_items();
		for it in items {
			e.smith().salvage(e.m(), e.hero, it.id).unwrap();
		}
	}
	assert!((30..=90).contains(&failed) && (30..=90).contains(&won), "failed {failed}, won {won}: about half each");
	// +10 is the top
	let mut top = rare_item(&mut rng, 20, EPIC);
	top.plus = 10;
	let id = e.give_item(top);
	assert!(matches!(e.smith().upgrade(e.m(), e.hero, id), Err(Error::Invalid(_))));
	e.ok();
}

#[test]
fn a_repeated_request_repeats_nothing() {
	let e = Env::new("repeat");
	let mut rng = Rng::new(6);
	let id = e.give_item(rare_item(&mut rng, 12, UNCOMMON));
	e.give(StackKind::material(EMBERS), 500);
	e.give(StackKind::COIN, 5_000);
	let m = e.m();
	let a = e.smith().upgrade(m, e.hero, id).unwrap();
	let emb = e.stack(StackKind::material(EMBERS));
	// the same id again: the old item is gone, so the repeat is refused and nothing is charged twice
	assert!(e.smith().upgrade(m, e.hero, id).is_err());
	assert_eq!(e.stack(StackKind::material(EMBERS)), emb);
	assert_eq!(e.bag_items().len(), 1);
	assert_eq!(e.bag_items()[0].id, a.item);
	e.ok();
}

#[test]
fn insufficient_costs_change_nothing() {
	let e = Env::new("poor");
	let mut rng = Rng::new(7);
	let id = e.give_item(rare_item(&mut rng, 50, RARE));
	e.give(StackKind::material(EMBERS), 3);
	e.give(StackKind::COIN, 10);
	let before = e.s.stats().unwrap();
	for r in [
		e.smith().upgrade(e.m(), e.hero, id).map(|_| ()),
		e.smith().reroll(e.m(), e.hero, id).map(|_| ()),
		e.smith().socket(e.m(), e.hero, id, 0, StackKind::rune(0, 1)).map(|_| ()),
		e.smith().fuse(e.m(), e.hero, 0, 1).map(|_| ()),
	] {
		assert!(matches!(r, Err(Error::Insufficient { .. })), "{r:?}");
	}
	let after = e.s.stats().unwrap();
	assert_eq!(before.digest, after.digest);
	assert!(e.item(id).is_some());
}

#[test]
fn reroll_redraws_lines_only() {
	let e = Env::new("reroll");
	let mut rng = Rng::new(8);
	let mut spec = rare_item(&mut rng, 36, EPIC);
	spec.plus = 4;
	let mut id = e.give_item(spec.clone());
	e.give(StackKind::material(EMBERS), 10_000);
	e.give(StackKind::COIN, 10_000_000);
	let mut changed = false;
	for _ in 0..8 {
		let (emb, coin) = (e.stack(StackKind::material(EMBERS)), e.stack(StackKind::COIN));
		let cost = reroll_cost(&spec);
		assert_eq!(cost.embers, (6 + 18) * 4 * 14 / 10);
		assert_eq!(cost.coin, 30 * 36 * 4);
		id = e.smith().reroll(e.m(), e.hero, id).unwrap();
		let it = e.item(id).unwrap();
		assert_eq!(it.spec.rarity, spec.rarity);
		assert_eq!(it.spec.item_level, spec.item_level);
		assert_eq!(it.spec.plus, 4);
		assert_eq!(it.spec.base, spec.base);
		assert_eq!(it.spec.lines.len(), 4);
		assert_eq!(it.spec.lines[0].1, spec.lines[0].1);
		changed |= it.spec.lines != spec.lines;
		assert_eq!(e.stack(StackKind::material(EMBERS)), emb - cost.embers);
		assert_eq!(e.stack(StackKind::COIN), coin - cost.coin);
		assert_eq!(e.bag_items().len(), 1);
	}
	assert!(changed);
	e.ok();
}

#[test]
fn an_item_from_another_account_cannot_be_rewritten() {
	let e = Env::new("origin");
	let mut rng = Rng::new(9);
	// an item minted for another account's hero, then traded here
	let m = e.m();
	let a2 = e.s.account_by_dev_name(m, "seller").unwrap();
	let m = e.m();
	let h2 = e.s.hero_create(m, a2, "Seller", 0, 0, 0, false).unwrap();
	let m = e.m();
	let (foreign, _) = e.s.mint(m, Dest::bag(h2), rare_item(&mut rng, 10, RARE), "drop").unwrap();
	let m = e.m();
	e.s.trade_commit(
		Meta::system(realm_store::trade_request_id(&TradeSide { hero: h2, items: vec![foreign], stacks: vec![] }, &TradeSide { hero: e.hero, items: vec![], stacks: vec![] }, 1), m.now),
		TradeSide { hero: h2, items: vec![foreign], stacks: vec![] },
		TradeSide { hero: e.hero, items: vec![], stacks: vec![] },
	)
	.unwrap();
	e.give(StackKind::material(EMBERS), 1_000);
	e.give(StackKind::COIN, 100_000);
	assert_eq!(e.smith().upgrade(e.m(), e.hero, foreign).unwrap_err(), Error::Refused);
	assert_eq!(e.smith().reroll(e.m(), e.hero, foreign).unwrap_err(), Error::Refused);
	assert_eq!(e.stack(StackKind::material(EMBERS)), 1_000, "nothing was charged");
	// salvage is fine: it only destroys
	e.smith().salvage(e.m(), e.hero, foreign).unwrap();
	e.ok();
}

#[test]
fn fuse_three_into_one() {
	let e = Env::new("fuse");
	e.give(StackKind::rune(4, 1), 7);
	e.give(StackKind::COIN, 1_000);
	let k = e.smith().fuse(e.m(), e.hero, 4, 1).unwrap();
	assert_eq!(k, StackKind::rune(4, 2));
	assert_eq!(e.stack(StackKind::rune(4, 1)), 4);
	assert_eq!(e.stack(StackKind::rune(4, 2)), 1);
	assert_eq!(e.stack(StackKind::COIN), 900);
	e.smith().fuse(e.m(), e.hero, 4, 1).unwrap();
	assert_eq!(e.stack(StackKind::rune(4, 1)), 1);
	e.give(StackKind::rune(4, 2), 1);
	e.smith().fuse(e.m(), e.hero, 4, 2).unwrap();
	assert_eq!(e.stack(StackKind::rune(4, 3)), 1);
	assert_eq!(e.stack(StackKind::rune(4, 2)), 0);
	assert!(e.smith().fuse(e.m(), e.hero, 4, 3).is_err(), "grade III is the top");
	e.ok();
}

#[test]
fn socket_and_unsocket_cost_coin_and_move_the_stack() {
	let e = Env::new("socket");
	let mut rng = Rng::new(10);
	let id = e.give_item(rare_item(&mut rng, 20, RARE));
	e.give(StackKind::card(5), 1);
	e.give(StackKind::COIN, 1_000);
	assert_eq!(e.smith().socket(e.m(), e.hero, id, 0, StackKind::card(5)).unwrap(), 200);
	assert_eq!(e.stack(StackKind::COIN), 800);
	assert_eq!(e.stack(StackKind::card(5)), 0);
	// a second socket does not exist on a RARE: refused, and the coin comes back
	e.give(StackKind::card(6), 1);
	assert!(e.smith().socket(e.m(), e.hero, id, 1, StackKind::card(6)).is_err());
	assert_eq!(e.stack(StackKind::COIN), 800);
	assert_eq!(e.smith().unsocket(e.m(), e.hero, id, 0).unwrap(), 500);
	assert_eq!(e.stack(StackKind::card(5)), 1);
	assert_eq!(e.stack(StackKind::COIN), 300);
	e.ok();
}

/// A seeded run of every smith operation: the value in the store (items, and cards and runes in bags and in
/// sockets) never grows except by what the test itself hands out, and the ledger replays to the state.
#[test]
fn smith_operations_conserve_or_destroy_never_copy() {
	let e = Env::new("conserve");
	let mut rng = Rng::new(11);
	e.give(StackKind::material(EMBERS), 50_000);
	e.give(StackKind::COIN, 50_000_000);
	for s in 0..6 {
		e.give(StackKind::rune(s, 1), 9);
		e.give(StackKind::rune(s, 2), 3);
	}
	for c in [0u32, 7, 20, 42, 49] {
		e.give(StackKind::card(c), 2);
	}
	for i in 0..12 {
		e.give_item(make_item(&mut rng, (i % 6) as u8, 10 + i as u8 * 4, (i % 5) as u8));
	}
	let value = |e: &Env| -> (u64, u64, u64) {
		// (runes and cards held or socketed, items, embers)
		let mut sock = 0u64;
		let mut items = 0u64;
		for kind in [PlaceKind::Bag, PlaceKind::Worn] {
			for it in e.s.items_at(kind, e.hero).unwrap() {
				items += 1;
				sock += it.socketed.iter().flatten().count() as u64;
			}
		}
		let held: u64 = e
			.s
			.stacks(Owner::bag(e.hero))
			.unwrap()
			.iter()
			.filter(|(k, _)| k.socketable())
			.map(|(_, n)| *n)
			.sum();
		(held + sock, items, e.stack(StackKind::material(EMBERS)))
	};
	let start = value(&e);
	let mut salvaged_embers = 0;
	let mut fused = 0u64;
	for _ in 0..400 {
		let items = e.bag_items();
		if items.is_empty() {
			break;
		}
		let it = &items[rng.below(items.len() as u64) as usize];
		let (v0, i0, _) = value(&e);
		match rng.below(7) {
			0 => {
				if let Ok(up) = e.smith().upgrade(e.m(), e.hero, it.id) {
					let _ = up;
					assert_eq!(value(&e).1, i0, "an upgrade keeps the item count");
					assert_eq!(value(&e).0, v0, "and every card and rune");
				}
			}
			1 => {
				if e.smith().reroll(e.m(), e.hero, it.id).is_ok() {
					assert_eq!(value(&e).1, i0);
					assert_eq!(value(&e).0, v0);
				}
			}
			2 if items.len() > 6 => {
				let before = e.stack(StackKind::material(EMBERS));
				if let Ok(s) = e.smith().salvage(e.m(), e.hero, it.id) {
					salvaged_embers += s.embers;
					assert_eq!(value(&e).1, i0 - 1);
					assert_eq!(value(&e).0, v0, "salvage returns what was socketed");
					assert_eq!(e.stack(StackKind::material(EMBERS)), before + s.embers);
				}
			}
			3 | 4 => {
				let kind = if rng.below(2) == 0 { StackKind::rune(rng.below(6) as u32, 1 + rng.below(2) as u32) } else { StackKind::card([0u32, 7, 20, 42, 49][rng.below(5) as usize]) };
				let _ = e.smith().socket(e.m(), e.hero, it.id, rng.below(2) as u8, kind);
				assert_eq!(value(&e).0, v0, "a socket moves a card, it never makes one");
			}
			5 => {
				let _ = e.smith().unsocket(e.m(), e.hero, it.id, rng.below(2) as u8);
				assert_eq!(value(&e).0, v0);
			}
			_ => {
				let (s, g) = (rng.below(6) as u32, 1 + rng.below(2) as u32);
				let had = e.stack(StackKind::rune(s, g));
				if e.smith().fuse(e.m(), e.hero, s, g).is_ok() {
					fused += 1;
					assert_eq!(e.stack(StackKind::rune(s, g)), had - 3);
					assert_eq!(value(&e).0, v0 - 2, "three runes become one: value is destroyed");
				}
			}
		}
	}
	let end = value(&e);
	assert!(end.0 + 2 * fused == start.0, "cards and runes: {start:?} -> {end:?}, fused {fused}");
	assert!(end.1 <= start.1);
	assert!(fused > 0 && salvaged_embers > 0, "the run used the smith: fused {fused}, embers {salvaged_embers}");
	e.ok();
	// and every item that lives has one MINT row; destroyed ones have one DESTROY row
	let (mints, destroyed, alive) = e.mint_rows();
	assert_eq!(mints - destroyed, alive);
}

#[test]
fn worn_items_wait_for_the_bag() {
	let e = Env::new("worn");
	let mut rng = Rng::new(12);
	let id = e.give_item(rare_item(&mut rng, 1, COMMON));
	let m = e.m();
	e.s.move_item(m, id, Dest::at(PlaceKind::Worn, e.hero, 0, 0)).unwrap_or_else(|_| Place { kind: PlaceKind::Bag, owner: 0, tab: 0, slot: 0 });
	if e.item(id).unwrap().place.kind == PlaceKind::Worn {
		e.give(StackKind::material(EMBERS), 100);
		e.give(StackKind::COIN, 1000);
		assert!(matches!(e.smith().upgrade(e.m(), e.hero, id), Err(Error::NotYours(_))));
	}
	e.ok();
}

#[test]
fn gear_stats_sum_worn_items_in_hundredths() {
	let mut rng = Rng::new(13);
	let a = make_item(&mut rng, 0, 4, UNCOMMON);
	let w = [(a.clone(), vec![]), (a.clone(), vec![Some(StackKind::rune(0, 1))])];
	let g = gear_stats(&w);
	let mut expect = [0u32; 6];
	for (s, p) in &a.lines {
		expect[*s as usize] += *p as u32 * 2;
	}
	expect[0] += 2;
	assert_eq!(g.map(|v| v as u32), expect);
	assert_eq!(base_name(base_id(3, 5, 1)), "ASHEN GAUNTLETS");
	let _ = (CARD_COUNT, BOSS_COUNT);
}
