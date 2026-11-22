//! A plundered fall (job R3b, `Cmd::Plunder`): the lost haul moves to the hero who downed her once, in one
//! transaction, with ledger lines on both sides, the victim kept as each item's origin; a full bag spills to mail;
//! self-found and trade-locked heroes refuse; a crash at any point of the transaction leaves all or nothing.
mod common;
use common::*;
use realm_store::fuzz::{FuzzConfig, parent};
use realm_store::*;

struct W {
	t: T,
	a: AccountId,
	victim: HeroId,
	b: AccountId,
	winner: HeroId,
}

fn world(name: &str) -> W {
	let mut t = T::new(name);
	let a = t.account(11);
	let victim = t.hero(a, "Prey");
	let b = t.account(12);
	let winner = t.hero(b, "Hunter");
	W { t, a, victim, b, winner }
}

fn ledger(path: &std::path::Path, sql: &str) -> Vec<(String, Option<i64>, Option<i64>, Option<i64>, i64, String)> {
	let c = rusqlite::Connection::open(path).unwrap();
	let mut st = c.prepare(&format!("SELECT op, item, from_acct, to_acct, count, reason FROM ledger WHERE {sql} ORDER BY seq")).unwrap();
	st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?))).unwrap().map(|r| r.unwrap()).collect()
}

#[test]
fn a_plundered_haul_moves_once_with_ledger_lines_and_the_victim_as_origin() {
	let mut w = world("plunder-once");
	let m = w.t.m();
	let items = vec![spec(3), spec_slot(4, 2)];
	let stacks = vec![(StackKind::material(1), 7), (StackKind::rune(0, 1), 2)];
	let got = w.t.s.plunder(m, w.victim, w.winner, items.clone(), stacks.clone(), 120).unwrap();
	assert_eq!(got.len(), 2);
	for (id, p) in &got {
		assert_eq!((p.kind, p.owner), (PlaceKind::Bag, w.winner), "in the winner's bag");
		let it = w.t.s.item(*id).unwrap().unwrap();
		assert_eq!((it.origin_hero, it.origin_account), (Some(w.victim), w.a), "the victim stays the origin");
	}
	assert_eq!(w.t.s.stack(Owner::bag(w.winner), StackKind::material(1)).unwrap(), 7);
	assert_eq!(w.t.s.stack(Owner::bag(w.winner), StackKind::rune(0, 1)).unwrap(), 2);
	assert!(w.t.s.stacks(Owner { kind: PlaceKind::Mail, id: w.victim }).unwrap().is_empty(), "the waypoint is empty");
	assert!(w.t.s.items_at(PlaceKind::Mail, w.victim).unwrap().is_empty());

	// the same request again (a retried flush): applied once
	let digest = w.t.s.stats().unwrap().digest;
	let again = w.t.s.plunder(m, w.victim, w.winner, items, stacks, 120).unwrap();
	assert_eq!(again, got);
	assert_eq!(w.t.s.stats().unwrap().digest, digest, "a repeat changes nothing");
	assert_eq!(w.t.s.stack(Owner::bag(w.winner), StackKind::material(1)).unwrap(), 7);

	// both sides in the ledger: the PLUNDER row, a MINT for the victim and a MOVE to the winner for each item, a
	// CREDIT for the victim and a TRANSFER to the winner for each stack
	let rows = ledger(&w.t.path, "op IN ('PLUNDER', 'MINT', 'MOVE', 'CREDIT', 'TRANSFER') AND (from_acct IS NOT NULL OR to_acct IS NOT NULL)");
	let ops: Vec<&str> = rows.iter().map(|r| r.0.as_str()).collect();
	assert_eq!(ops, ["PLUNDER", "MINT", "MOVE", "MINT", "MOVE", "CREDIT", "TRANSFER", "CREDIT", "TRANSFER"]);
	assert_eq!((rows[0].2, rows[0].3, rows[0].4), (Some(w.a), Some(w.b), 120), "the coin, victim to winner");
	assert!(rows.iter().filter(|r| r.0 == "MINT" || r.0 == "CREDIT").all(|r| r.3 == Some(w.a)), "minted for the victim");
	assert!(rows.iter().filter(|r| r.0 == "MOVE" || r.0 == "TRANSFER").all(|r| r.2 == Some(w.a) && r.3 == Some(w.b)));

	// the botter tools: the victim's trace counts the items and stacks as hers, and the forward trace finds them
	// with the winner
	let tr = w.t.s.trace(w.a).unwrap();
	assert_eq!(tr.items.len(), 2);
	assert!(tr.items.iter().all(|i| i.holder == Some(Party::Account(w.b))));
	let mat = tr.stacks.iter().find(|s| s.kind == StackKind::material(1)).unwrap();
	assert_eq!((mat.minted, mat.holds), (7, 0));
	let hops = w.t.s.trace_forward(w.a, 1).unwrap();
	assert_eq!(hops.iter().filter(|h| h.to == Party::Account(w.b)).count(), 4);
	assert!(w.t.s.trace(w.b).unwrap().items.is_empty(), "the winner minted nothing");
	w.t.ok();
}

#[test]
fn a_full_bag_sends_the_plunder_to_the_winners_mail() {
	let mut w = world("plunder-full");
	for _ in 0..39 {
		w.t.mint_bag(w.winner, 1);
	}
	let m = w.t.m();
	let got = w.t.s.plunder(m, w.victim, w.winner, vec![spec(1), spec(2), spec(3)], vec![(StackKind::rune(0, 2), 1)], 0).unwrap();
	let kinds: Vec<PlaceKind> = got.iter().map(|g| g.1.kind).collect();
	assert_eq!(kinds, [PlaceKind::Bag, PlaceKind::Mail, PlaceKind::Mail]);
	assert!(got.iter().all(|g| g.1.owner == w.winner));
	assert_eq!(w.t.s.stack(Owner { kind: PlaceKind::Mail, id: w.winner }, StackKind::rune(0, 2)).unwrap(), 1, "a slot-taking stack too");
	w.t.ok();
}

#[test]
fn self_found_and_trade_locked_heroes_refuse_and_the_ledger_says_so() {
	let mut w = world("plunder-refused");
	let m = w.t.m();
	let lone = w.t.s.hero_create(m, w.b, "Lone", 0, 0, 0, true).unwrap();
	let m = w.t.m();
	assert!(w.t.s.plunder(m, w.victim, lone, vec![spec(1)], vec![(StackKind::material(1), 3)], 9).unwrap().is_empty());
	let m = w.t.m();
	assert!(w.t.s.plunder(m, lone, w.victim, vec![spec(1)], vec![], 0).unwrap().is_empty());
	let m = w.t.m();
	w.t.s.apply_flags(m, vec![FlagChange { account: w.b, flags: flags::TRADE_LOCKED, drops_percent: 100, banned_until: None }], "test").unwrap();
	let m = w.t.m();
	assert!(w.t.s.plunder(m, w.victim, w.winner, vec![spec(1)], vec![], 0).unwrap().is_empty());
	assert!(w.t.s.items_at(PlaceKind::Bag, lone).unwrap().is_empty() && w.t.s.items_at(PlaceKind::Bag, w.winner).unwrap().is_empty());
	let rows = ledger(&w.t.path, "op = 'PLUNDER'");
	assert_eq!(rows.len(), 3);
	assert!(rows.iter().all(|r| r.5 == "refused"));
	let m = w.t.m();
	assert!(matches!(w.t.s.plunder(m, w.victim, w.victim, vec![], vec![], 1), Err(Error::Invalid(_))), "not herself");
	w.t.ok();
}

#[test]
fn a_crash_inside_a_plunder_leaves_all_or_nothing() {
	// The crash fuzz's stream has plunders (3% of its operations): killed at every site of the store's
	// transactions, the reopened store verifies and every acknowledged plunder is there whole.
	let dir = scratch().join(format!("fuzz-plunder-{}", std::process::id()));
	let r = parent(&FuzzConfig { seed: 31_337, ops: 4000, kills: 16, dir: dir.clone(), exe: env!("CARGO_BIN_EXE_realm-store").into(), verbose: false });
	let _ = std::fs::remove_dir_all(&dir);
	assert!(r.problems.is_empty(), "{:?}", r.problems);
	assert!(r.kills * 10 >= 16 * 9, "{} kills", r.kills);
}
