//! Who may run what: the four holes the review found, and every command walked as a player against another
//! account's things (refused, nothing changed) and as the server (works).
mod common;
use common::*;
use realm_store::*;

const FAR: i64 = 1_800_000_000_000;

struct W {
	t: T,
	x: AccountId,
	hx: HeroId,
	y: AccountId,
	hy: HeroId,
	/// in y's bag, two sockets, empty
	iy: ItemId,
	/// in y's bag, a rune in socket 0
	sy: ItemId,
}

fn world(name: &str) -> W {
	let mut t = T::new(name);
	let x = t.account(1);
	let hx = t.hero(x, "Thief");
	let y = t.account(2);
	let hy = t.hero(y, "Victim");
	let iy = t.mint_bag(hy, 1);
	let sy = t.mint_bag(hy, 1);
	t.credit(Owner::bag(hy), StackKind::COIN, 500);
	t.credit(Owner::bag(hy), StackKind::rune(0, 1), 3);
	t.credit(Owner::bag(hy), StackKind::page(20), 1);
	let m = t.m();
	t.s.socket(m, hy, sy, 0, StackKind::rune(0, 1)).unwrap();
	// x has a listing (parcel 1) of an item for 40 coin
	let lx = t.mint_bag(hx, 1);
	let m = t.m();
	let parcel = t.s.parcel_put(m, Cmd::ParcelPut { kind: ParcelKind::Listing, from: hx, to: None, items: vec![lx], stacks: vec![], price: 40, fee: 0, expires: FAR, text: String::new() }).unwrap();
	assert_eq!(parcel, 1);
	W { t, x, hx, y, hy, iy, sy }
}

/// Fails to compile when a command is added without a case here.
fn case_name(c: &Cmd) -> &'static str {
	match c {
		Cmd::AccountBySteam { .. }
		| Cmd::AccountByDevName { .. }
		| Cmd::ApplyFlags { .. }
		| Cmd::HeroCreate { .. }
		| Cmd::HeroRename { .. }
		| Cmd::HeroDelete { .. }
		| Cmd::HeroUndelete { .. }
		| Cmd::HeroSave { .. }
		| Cmd::LearnPage { .. }
		| Cmd::Mint { .. }
		| Cmd::MoveItem { .. }
		| Cmd::SellItem { .. }
		| Cmd::Socket { .. }
		| Cmd::Unsocket { .. }
		| Cmd::StackCredit { .. }
		| Cmd::StackDebit { .. }
		| Cmd::StackTransfer { .. }
		| Cmd::Outing { .. }
		| Cmd::Trade { .. }
		| Cmd::GrantEntitlement { .. }
		| Cmd::ParcelPut { .. }
		| Cmd::ParcelTake { .. }
		| Cmd::ParcelReturn { .. }
		| Cmd::Clawback { .. } => c.name(),
	}
}

const VARIANTS: usize = 24;

/// One command of every kind, each aimed at y's things.
fn cases(w: &W) -> Vec<Cmd> {
	let save = Progress {
		job: 2,
		class_level: 1,
		class_xp: 0,
		stats: [0; 6],
		unspent: 0,
		deck: (0..12).collect(),
		belt: [0, 0, 0],
		waystones: [-1; 6],
	};
	vec![
		Cmd::AccountBySteam { steam_id: 99 },
		Cmd::AccountByDevName { name: "made-up".into() },
		Cmd::ApplyFlags { changes: vec![FlagChange { account: w.y, flags: 0, drops_percent: 100, banned_until: Some(i64::MAX) }], reason: "grief".into() },
		Cmd::HeroCreate { account: w.y, name: "Planted".into(), race: 0, class: 0, look: 0, self_found: false },
		Cmd::HeroRename { hero: w.hy, name: "Renamed".into() },
		Cmd::HeroDelete { hero: w.hy },
		Cmd::HeroUndelete { hero: w.hy },
		Cmd::HeroSave { hero: w.hy, progress: save },
		Cmd::LearnPage { hero: w.hy, card: 20 },
		Cmd::Mint { to: Dest::bag(w.hy), spec: spec(1), reason: "drop".into() },
		Cmd::MoveItem { item: w.iy, to: Dest::bank(w.y, 0) },
		Cmd::SellItem { hero: w.hy, item: w.iy, price: 10 },
		Cmd::Socket { hero: w.hy, item: w.iy, socket: 0, kind: StackKind::rune(0, 1) },
		Cmd::Unsocket { hero: w.hy, item: w.sy, socket: 0 },
		Cmd::StackCredit { to: Owner::bag(w.hy), kind: StackKind::COIN, count: 5, minted: true, reason: "drop".into() },
		Cmd::StackDebit { from: Owner::bag(w.hy), kind: StackKind::COIN, count: 5, reason: "buy".into() },
		Cmd::StackTransfer { from: Owner::bag(w.hy), to: Owner::bank(w.y), kind: StackKind::COIN, count: 5 },
		Cmd::Outing { hero: w.hy, delta: OutingDelta { coin: 10, ..Default::default() } },
		Cmd::Trade {
			a: TradeSide { hero: w.hx, items: vec![], stacks: vec![] },
			b: TradeSide { hero: w.hy, items: vec![w.iy], stacks: vec![(StackKind::COIN, 500)] },
		},
		Cmd::GrantEntitlement { account: w.y, kind: EntitlementKind::HeroSlot, count: 5, purchase: "invented".into() },
		Cmd::Clawback { items: vec![w.iy], stacks: vec![(Owner::bag(w.hy), StackKind::COIN, 500)], reason: "grief".into() },
		Cmd::ParcelPut { kind: ParcelKind::Listing, from: w.hy, to: None, items: vec![w.iy], stacks: vec![], price: 50, fee: 0, expires: FAR, text: String::new() },
		Cmd::ParcelTake { parcel: 1, hero: w.hy, tax: 4 },
		Cmd::ParcelReturn { parcel: 1 },
	]
}

fn run(w: &mut W, actor: AccountId, cmd: Cmd) -> Result<Reply> {
	w.t.n += 1;
	w.t.now += 1000;
	let r = Request { id: w.t.n, actor, now: w.t.now, cmd };
	w.t.s.submit(r)
}

#[test]
fn every_command_by_table() {
	let probe = world("auth-names");
	let all = cases(&probe);
	let mut names: Vec<&str> = all.iter().map(case_name).collect();
	names.sort();
	names.dedup();
	assert_eq!(names.len(), VARIANTS, "one case per command");
	drop(probe);
	for i in 0..VARIANTS {
		// a player against another account's things: refused, nothing changed
		let mut w = world("auth-player");
		if matches!(cases(&w)[i], Cmd::HeroUndelete { .. }) {
			let m = w.t.m();
			w.t.s.hero_delete(m, w.hy).unwrap();
		}
		let cmd = cases(&w)[i].clone();
		let name = cmd.name();
		let before = w.t.s.stats().unwrap();
		let x = w.x;
		let r = run(&mut w, x, cmd.clone());
		assert!(matches!(r, Err(Error::NotYours(_))), "{name} by a player on another's things: {r:?}");
		let after = w.t.s.stats().unwrap();
		assert_eq!((before.digest, before.accounts, before.heroes), (after.digest, after.accounts, after.heroes), "{name} changed state");
		assert_eq!(w.t.s.account(w.y).unwrap().unwrap().banned_until, None);
		w.t.ok();

		// the server: it works
		let mut w = world("auth-server");
		if matches!(cmd, Cmd::HeroUndelete { .. }) {
			let m = w.t.m();
			w.t.s.hero_delete(m, w.hy).unwrap();
		}
		let c = cases(&w)[i].clone();
		let r = run(&mut w, 0, c);
		assert!(r.is_ok(), "{name} by the server: {r:?}");
		w.t.ok();

		// the owner on its own things: allowed exactly for the Owner commands
		let mut w = world("auth-owner");
		if matches!(cmd, Cmd::HeroUndelete { .. }) {
			let m = w.t.m();
			w.t.s.hero_delete(m, w.hy).unwrap();
		}
		let y = w.y;
		let c = cases(&w)[i].clone();
		let r = run(&mut w, y, c);
		match who_may(&cmd) {
			Who::Owner => assert!(r.is_ok(), "{name} by the owner: {r:?}"),
			Who::Server => assert!(matches!(r, Err(Error::NotYours(_))), "{name} by the owner: {r:?}"),
		}
		w.t.ok();
	}
}

#[test]
fn hole_trade_takes_without_giving() {
	let mut w = world("hole-trade");
	let before = w.t.s.stats().unwrap().digest;
	let m = w.t.by(w.x);
	let r = w.t.s.trade_commit(
		m,
		TradeSide { hero: w.hx, items: vec![], stacks: vec![] },
		TradeSide { hero: w.hy, items: vec![w.iy], stacks: vec![(StackKind::COIN, 500)] },
	);
	assert!(matches!(r, Err(Error::NotYours(_))), "{r:?}");
	assert_eq!(w.t.s.stats().unwrap().digest, before);
	assert_eq!(w.t.s.item(w.iy).unwrap().unwrap().place.owner, w.hy);
	w.t.ok();
}

#[test]
fn hole_clawback_by_a_player() {
	let mut w = world("hole-claw");
	let before = w.t.s.stats().unwrap().digest;
	let m = w.t.by(w.x);
	let r = w.t.s.clawback(m, ClawbackPlan { items: vec![w.iy], stacks: vec![(Owner::bag(w.hy), StackKind::COIN, 500)] }, "grief");
	assert!(matches!(r, Err(Error::NotYours(_))), "{r:?}");
	assert_eq!(w.t.s.stats().unwrap().digest, before);
	w.t.ok();
}

#[test]
fn hole_apply_flags_by_a_player() {
	let mut w = world("hole-flags");
	let m = w.t.m();
	w.t.s.apply_flags(m, vec![FlagChange { account: w.x, flags: flags::TRADE_LOCKED, drops_percent: 100, banned_until: None }], "rmt").unwrap();
	// the locked account cannot clear its own flags
	let m = w.t.by(w.x);
	let r = w.t.s.apply_flags(m, vec![FlagChange { account: w.x, flags: 0, drops_percent: 100, banned_until: None }], "self");
	assert!(matches!(r, Err(Error::NotYours(_))), "{r:?}");
	assert_eq!(w.t.s.account(w.x).unwrap().unwrap().flags, flags::TRADE_LOCKED);
	// nor ban another
	let m = w.t.by(w.x);
	let r = w.t.s.apply_flags(m, vec![FlagChange { account: w.y, flags: 0, drops_percent: 100, banned_until: Some(i64::MAX) }], "grief");
	assert!(matches!(r, Err(Error::NotYours(_))), "{r:?}");
	assert_eq!(w.t.s.account(w.y).unwrap().unwrap().banned_until, None);
	w.t.ok();
}

#[test]
fn hole_grant_entitlement_by_a_player() {
	let mut w = world("hole-ent");
	let m = w.t.by(w.x);
	let r = w.t.s.grant_entitlement(m, w.x, EntitlementKind::HeroSlot, 10, "invented-1");
	assert!(matches!(r, Err(Error::NotYours(_))), "{r:?}");
	let m = w.t.by(w.x);
	let r = w.t.s.grant_entitlement(m, w.x, EntitlementKind::BankTab, 10, "invented-2");
	assert!(matches!(r, Err(Error::NotYours(_))), "{r:?}");
	assert!(w.t.s.entitlements(w.x).unwrap().is_empty());
	w.t.ok();
}

#[test]
fn player_save_cannot_raise_progress() {
	let mut w = world("save-auth");
	let base = Progress {
		job: 0,
		class_level: 1,
		class_xp: 0,
		stats: [0; 6],
		unspent: 0,
		deck: (0..12).collect(),
		belt: [0, 0, 0],
		waystones: [-1; 6],
	};
	let m = w.t.by(w.y);
	let r = w.t.s.hero_save(m, w.hy, Progress { class_level: 2, unspent: 1, ..base.clone() });
	assert!(matches!(r, Err(Error::NotYours(_))), "{r:?}");
	let m = w.t.by(w.y);
	let r = w.t.s.hero_save(m, w.hy, Progress { class_xp: 50, ..base.clone() });
	assert!(matches!(r, Err(Error::NotYours(_))), "{r:?}");
	// the server raises it; then the player respends points, picks a job, sets deck and belt
	let m = w.t.m();
	w.t.s.hero_save(m, w.hy, Progress { class_level: 5, class_xp: 900, unspent: 4, ..base.clone() }).unwrap();
	let m = w.t.by(w.y);
	w.t.s
		.hero_save(m, w.hy, Progress { class_level: 5, class_xp: 900, stats: [2, 0, 1, 0, 0, 0], unspent: 1, job: 3, deck: (0..10).collect(), belt: [StackKind::potion(1).0, 0, 0], ..base })
		.unwrap();
	w.t.ok();
}

#[test]
fn player_own_moves_and_guild() {
	let mut w = world("own-moves");
	let hy2 = w.t.hero(w.y, "Victimtoo");
	let y = w.y;
	let m = w.t.by(y);
	w.t.s.move_item(m, w.iy, Dest::any(PlaceKind::Mail, hy2)).unwrap();
	let m = w.t.by(y);
	w.t.s.move_item(m, w.iy, Dest::any(PlaceKind::House, y)).unwrap();
	let m = w.t.by(y);
	assert!(matches!(w.t.s.move_item(m, w.iy, Dest::any(PlaceKind::Guild, 1)), Err(Error::NotYours(_))));
	let m = w.t.by(y);
	assert!(matches!(w.t.s.move_item(m, w.iy, Dest::any(PlaceKind::Mail, w.hx)), Err(Error::NotYours(_))));
	let m = w.t.by(y);
	assert!(matches!(
		w.t.s.stack_transfer(m, Owner::bag(w.hy), Owner { kind: PlaceKind::Guild, id: 1 }, StackKind::COIN, 1),
		Err(Error::NotYours(_))
	));
	let m = w.t.by(y);
	w.t.s.stack_transfer(m, Owner::bag(w.hy), Owner::bag(hy2), StackKind::COIN, 1).unwrap();
	w.t.ok();
}
