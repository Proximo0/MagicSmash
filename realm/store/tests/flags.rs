//! The lead's addition: origins, account flags, trace, trace_forward, clawback, ban waves.
mod common;
use common::*;
use realm_store::*;

fn trade(t: &mut T, a: HeroId, ai: Vec<ItemId>, acoin: u64, b: HeroId, bi: Vec<ItemId>) -> Result<()> {
	let sa = TradeSide { hero: a, items: ai, stacks: if acoin > 0 { vec![(StackKind::COIN, acoin)] } else { vec![] } };
	let sb = TradeSide { hero: b, items: bi, stacks: vec![] };
	t.n += 1;
	t.now += 1000;
	let m = Meta::system(trade_request_id(&sa, &sb, t.n as u64), t.now);
	t.s.trade_commit(m, sa, sb)
}

#[test]
fn farm_trace_and_clawback() {
	let mut t = T::new("farm");
	let farm = t.account(100);
	let hf = t.hero(farm, "Farmer");
	let buyers: Vec<AccountId> = (0..3).map(|i| t.account(200 + i)).collect();
	let hb: Vec<HeroId> = buyers.iter().enumerate().map(|(i, a)| t.hero(*a, &format!("Buyer{i}"))).collect();
	let c1 = t.account(300);
	let hc1 = t.hero(c1, "Second");
	let c2 = t.account(301);
	let hc2 = t.hero(c2, "Third");
	let clean = t.account(400);
	let hclean = t.hero(clean, "Honest");
	let before_farm = t.s.stats().unwrap().ledger_rows;

	// the farm mints by playing: items and coin
	let m = t.m();
	let got = t
		.s
		.apply_outing(m, hf, OutingDelta { coin: 1000, items: (0..8).map(|_| spec(1)).collect(), stacks: vec![(StackKind::card(3), 1)], ..Default::default() })
		.unwrap();
	let farm_items: Vec<ItemId> = got.iter().map(|(i, _)| *i).collect();
	let honest_item = t.mint_bag(hclean, 1);
	let b0_own = t.mint_bag(hb[0], 1);
	t.credit(Owner::bag(hb[0]), StackKind::COIN, 50);

	// sold to three buyers
	trade(&mut t, hf, vec![farm_items[0], farm_items[1]], 300, hb[0], vec![]).unwrap();
	trade(&mut t, hf, vec![farm_items[2]], 200, hb[1], vec![]).unwrap();
	trade(&mut t, hf, vec![farm_items[3]], 100, hb[2], vec![]).unwrap();
	// buyer 0 passes one farm item and coin onward, and an item of its own
	trade(&mut t, hb[0], vec![farm_items[0], b0_own], 250, hc1, vec![]).unwrap();
	// buyer 1 deposits into a guild bank; a guild mate takes it out (guild moves are the server's, for the gateway)
	let m = t.m();
	t.s.move_item(m, farm_items[2], Dest::any(PlaceKind::Guild, 7)).unwrap();
	let m = t.m();
	t.s.move_item(m, farm_items[2], Dest::bag(hc2)).unwrap();
	// the farm wears one, banks one, houses one, mails one to itself; the card goes into a worn item's socket
	let m = t.m();
	t.s.move_item(m, farm_items[4], Dest::any(PlaceKind::Worn, hf)).unwrap();
	let m = t.m();
	t.s.move_item(m, farm_items[5], Dest::bank(farm, 0)).unwrap();
	let m = t.m();
	t.s.move_item(m, farm_items[6], Dest::any(PlaceKind::House, farm)).unwrap();
	let m = t.m();
	t.s.move_item(m, farm_items[7], Dest::any(PlaceKind::Mail, hf)).unwrap();
	let m = t.m();
	t.s.socket(m, hf, farm_items[4], 0, StackKind::card(3)).unwrap();
	// the farm sells one to a merchant (destroyed): it shows in the trace with no place
	let m = t.m();
	let (sold, _) = t.s.mint(m, Dest::bag(hf), spec(1), "drop").unwrap();
	let m = t.m();
	t.s.sell_item(m, hf, sold, 40).unwrap();

	// trace: every item it minted with its holder; coin minted, sent per buyer, held
	let tr = t.s.trace(farm).unwrap();
	assert_eq!(tr.items.len(), 9);
	let holder = |id: ItemId| tr.items.iter().find(|x| x.item == id).unwrap().holder;
	assert_eq!(holder(farm_items[0]), Some(Party::Account(c1)));
	assert_eq!(holder(farm_items[1]), Some(Party::Account(buyers[0])));
	assert_eq!(holder(farm_items[2]), Some(Party::Account(c2)));
	assert_eq!(holder(farm_items[3]), Some(Party::Account(buyers[2])));
	assert_eq!(holder(farm_items[5]), Some(Party::Account(farm)));
	assert_eq!(tr.items.iter().find(|x| x.item == sold).unwrap().place, None);
	let coin = tr.stacks.iter().find(|s| s.kind == StackKind::COIN).unwrap();
	assert_eq!(coin.minted, 1040);
	assert_eq!(coin.sent, vec![(Party::Account(buyers[0]), 300), (Party::Account(buyers[1]), 200), (Party::Account(buyers[2]), 100)]);
	assert_eq!(coin.holds, 440);
	let card = tr.stacks.iter().find(|s| s.kind == StackKind::card(3)).unwrap();
	assert_eq!((card.minted, card.spent, card.holds), (1, 1, 0));
	for it in &tr.items {
		if let Some(i) = t.s.item(it.item).unwrap() {
			assert_eq!(i.origin_account, farm);
			assert_eq!(i.origin_hero, Some(hf));
		}
	}

	// forward to depth 2: the buyers, then what buyer 0 and buyer 1 passed on of it (not buyer 0's own item)
	let hops = t.s.trace_forward(farm, 2).unwrap();
	let d2: Vec<&Hop> = hops.iter().filter(|h| h.depth == 2).collect();
	assert!(hops.iter().filter(|h| h.depth == 1).all(|h| h.from == Party::Account(farm)));
	assert_eq!(hops.iter().filter(|h| h.depth == 1 && h.item.is_some()).count(), 4);
	assert!(d2.iter().any(|h| h.item == Some(farm_items[0]) && h.to == Party::Account(c1)));
	assert!(d2.iter().any(|h| h.stack == Some(StackKind::COIN) && h.to == Party::Account(c1) && h.count == 250));
	assert!(d2.iter().any(|h| h.item == Some(farm_items[2]) && h.to == Party::Guild(7)));
	assert!(!d2.iter().any(|h| h.item == Some(b0_own)), "buyer 0's own item is not followed");
	let hops3 = t.s.trace_forward(farm, 3).unwrap();
	assert!(hops3.iter().any(|h| h.depth == 3 && h.item == Some(farm_items[2]) && h.to == Party::Account(c2)));

	// clawback from the plan: exactly the farm's items, wherever they are; coin from the farm, then the buyers
	let plan = t.s.clawback_plan(farm, before_farm).unwrap();
	let mut want: Vec<ItemId> = farm_items.clone();
	want.sort();
	let mut planned = plan.items.clone();
	planned.sort();
	assert_eq!(planned, want);
	let coin_planned: u64 = plan.stacks.iter().filter(|(_, k, _)| *k == StackKind::COIN).map(|(_, _, n)| n).sum();
	// one hop: the farm's 440, buyer 0's 100 left of 300 (250 went on to c1), buyer 1's 200, buyer 2's 100
	assert_eq!(coin_planned, 840);
	let mut plan = plan;
	// the card sits in a socket of a worn item that is itself clawed; claw the card from the bag to show a shortfall
	plan.stacks.push((Owner::bag(hf), StackKind::card(3), 1));
	let m = t.m();
	let (removed, missing, shortfall) = t.s.clawback(m, plan.clone(), "farm wave 1").unwrap();
	assert_eq!(removed.len(), 8);
	assert!(missing.is_empty());
	assert_eq!(shortfall, vec![(Owner::bag(hf), StackKind::card(3), 1)], "its socket went with the item");
	for i in &farm_items {
		assert!(t.s.item(*i).unwrap().is_none());
	}
	assert!(t.s.item(honest_item).unwrap().is_some());
	assert!(t.s.item(b0_own).unwrap().is_some());
	assert_eq!(t.s.stack(Owner::bag(hf), StackKind::COIN).unwrap(), 0);
	// coin is fungible: buyer 0 holds 100 (its own 50 + 300 - 250) and the plan takes up to the 300 it got
	assert_eq!(t.s.stack(Owner::bag(hb[0]), StackKind::COIN).unwrap(), 0);
	assert_eq!(t.s.stack(Owner::bag(hc1), StackKind::COIN).unwrap(), 250, "depth 2 is not in a one-hop plan");
	// again with the same request: same reply, nothing more
	let again = t.s.clawback(m, plan, "farm wave 1").unwrap();
	assert_eq!(again.0, removed);
	t.ok();
}

#[test]
fn clawback_from_socket_and_everywhere() {
	let mut t = T::new("claw");
	let a = t.account(1);
	let h = t.hero(a, "Morwen");
	let rune = StackKind::rune(4, 2);
	t.credit(Owner::bag(h), rune, 2);
	let i = t.mint_bag(h, 1);
	let m = t.m();
	t.s.socket(m, h, i, 0, rune).unwrap();
	let m = t.m();
	t.s.socket(m, h, i, 1, rune).unwrap();
	let m = t.m();
	let (gi, _) = t.s.mint(m, Dest::any(PlaceKind::Guild, 3), spec(1), "grant").unwrap();
	let m = t.m();
	let r = t
		.s
		.clawback(m, ClawbackPlan { items: vec![gi, 424242], stacks: vec![(Owner::bag(h), rune, 3)] }, "test")
		.unwrap();
	assert_eq!(r.0, vec![gi]);
	assert_eq!(r.1, vec![424242]);
	assert_eq!(r.2, vec![(Owner::bag(h), rune, 1)]);
	assert_eq!(t.s.item(i).unwrap().unwrap().socketed, vec![None, None]);
	t.ok();
}

#[test]
fn trade_locked_moves_no_value() {
	let mut t = T::new("lock");
	let l = t.account(1);
	let o = t.account(2);
	let hl = t.hero(l, "Locked");
	let hl2 = t.hero(l, "Lockedtoo");
	let ho = t.hero(o, "Other");
	let items: Vec<ItemId> = (0..10).map(|_| t.mint_bag(hl, 1)).collect();
	let theirs = t.mint_bag(ho, 1);
	t.credit(Owner::bag(hl), StackKind::COIN, 1000);
	t.credit(Owner::bag(ho), StackKind::COIN, 1000);
	t.credit(Owner::bank(l), StackKind::material(1), 10);
	let m = t.m();
	t.s.apply_flags(m, vec![FlagChange { account: l, flags: flags::TRADE_LOCKED | flags::WATCHED, drops_percent: 100, banned_until: None }], "rmt").unwrap();
	let before = t.s.stats().unwrap().digest;
	let i = items[0];
	let coin = StackKind::COIN;
	// every operation of the trait that can carry value between two parties, both directions
	let mut attempts: Vec<(&str, Result<()>)> = Vec::new();
	let mut mv = |t: &mut T, name: &'static str, item: ItemId, to: Dest| {
		let m = t.m();
		attempts.push((name, t.s.move_item(m, item, to).map(|_| ())));
	};
	mv(&mut t, "move_item to other's bag", i, Dest::bag(ho));
	mv(&mut t, "move_item to other's mail (mail with attachment)", i, Dest::any(PlaceKind::Mail, ho));
	mv(&mut t, "move_item to other's bank", i, Dest::bank(o, 0));
	mv(&mut t, "move_item to other's house", i, Dest::any(PlaceKind::House, o));
	mv(&mut t, "move_item to a guild bank", i, Dest::any(PlaceKind::Guild, 5));
	mv(&mut t, "move_item from other into locked bag", theirs, Dest::bag(hl));
	mv(&mut t, "move_item from other into locked mail", theirs, Dest::any(PlaceKind::Mail, hl));
	let mut st = |t: &mut T, name: &'static str, from: Owner, to: Owner, k: StackKind| {
		let m = t.m();
		attempts.push((name, t.s.stack_transfer(m, from, to, k, 1).map(|_| ())));
	};
	st(&mut t, "stack_transfer to other's bag", Owner::bag(hl), Owner::bag(ho), coin);
	st(&mut t, "stack_transfer to other's mail", Owner::bag(hl), Owner { kind: PlaceKind::Mail, id: ho }, coin);
	st(&mut t, "stack_transfer to other's bank", Owner::bank(l), Owner::bank(o), StackKind::material(1));
	st(&mut t, "stack_transfer to other's house", Owner::bank(l), Owner { kind: PlaceKind::House, id: o }, StackKind::material(1));
	st(&mut t, "stack_transfer to a guild bank", Owner::bag(hl), Owner { kind: PlaceKind::Guild, id: 5 }, coin);
	st(&mut t, "stack_transfer from other into locked", Owner::bag(ho), Owner::bag(hl), coin);
	attempts.push(("trade_commit giving", trade(&mut t, hl, vec![i], 5, ho, vec![])));
	attempts.push(("trade_commit receiving", trade(&mut t, ho, vec![theirs], 5, hl, vec![])));
	attempts.push(("trade_commit coin only", trade(&mut t, hl, vec![], 1, ho, vec![])));
	for (name, r) in &attempts {
		assert_eq!(*r, Err(Error::Refused), "{name}");
	}
	assert_eq!(attempts.len(), 16);
	assert_eq!(t.s.stats().unwrap().digest, before, "nothing moved");
	// the rest of the trait cannot carry value to another account: mint, sell, socket, unsocket, stack credit and
	// debit, outing, hero ops, learn page and entitlements act on one party only. Within its own account the
	// locked account still plays: bag to bank, to its other hero's mail, to its house.
	let m = t.m();
	t.s.move_item(m, items[1], Dest::bank(l, 0)).unwrap();
	let m = t.m();
	t.s.move_item(m, items[2], Dest::any(PlaceKind::Mail, hl2)).unwrap();
	let m = t.m();
	t.s.stack_transfer(m, Owner::bag(hl), Owner::bank(l), coin, 10).unwrap();
	let m = t.m();
	t.s.sell_item(m, hl, items[3], 5).unwrap();
	let m = t.m();
	t.s.apply_outing(m, hl, OutingDelta { coin: 5, ..Default::default() }).unwrap();
	// unlocked, it trades again
	let m = t.m();
	t.s.apply_flags(m, vec![FlagChange { account: l, flags: 0, drops_percent: 100, banned_until: None }], "cleared").unwrap();
	trade(&mut t, hl, vec![i], 5, ho, vec![]).unwrap();
	t.ok();
}

#[test]
fn ban_wave_is_one_transaction() {
	let mut t = T::new("wave");
	let accts: Vec<AccountId> = (0..4).map(|i| t.account(10 + i)).collect();
	let wave: Vec<FlagChange> = accts[..3]
		.iter()
		.map(|a| FlagChange { account: *a, flags: flags::SHADOWED | flags::DROPS_REDUCED, drops_percent: 10, banned_until: Some(9_999_999_999_999) })
		.collect();
	// one bad entry refuses the whole wave
	let mut bad = wave.clone();
	bad.push(FlagChange { account: 9999, flags: 0, drops_percent: 0, banned_until: None });
	let m = t.m();
	assert!(matches!(t.s.apply_flags(m, bad, "wave"), Err(Error::Missing(_))));
	assert_eq!(t.s.account(accts[0]).unwrap().unwrap().flags, 0);
	let m = t.m();
	assert!(matches!(
		t.s.apply_flags(m, vec![FlagChange { account: accts[0], flags: 1 << 10, drops_percent: 0, banned_until: None }], "wave"),
		Err(Error::Invalid(_))
	));
	let m = t.m();
	t.s.apply_flags(m, wave, "wave 2026-11").unwrap();
	for a in &accts[..3] {
		let acc = t.s.account(*a).unwrap().unwrap();
		assert_eq!((acc.flags, acc.drops_percent, acc.banned_until), (flags::SHADOWED | flags::DROPS_REDUCED, 10, Some(9_999_999_999_999)));
	}
	assert_eq!(t.s.account(accts[3]).unwrap().unwrap().flags, 0);
	let m = t.by(accts[0]);
	assert!(matches!(t.s.hero_create(m, accts[0], "Banned", 0, 0, 0, false), Err(Error::Banned { .. })));
	t.ok();
}
