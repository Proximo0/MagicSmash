mod common;
use common::*;
use realm_store::types::limits::*;
use realm_store::*;
use std::sync::Arc;
use std::time::Duration;

#[test]
fn account_get_or_create() {
	let mut t = T::new("acct");
	let a = t.account(76561198000000001);
	let b = t.account(76561198000000001);
	assert_eq!(a, b);
	let c = t.account(76561198000000002);
	assert_ne!(a, c);
	let m = t.m();
	let d1 = t.s.account_by_dev_name(m, "devbox").unwrap();
	let d2 = t.s.account_by_dev_name(m, "devbox").unwrap();
	assert_eq!(d1, d2);
	let m = t.m();
	assert_eq!(t.s.account_by_dev_name(m, ""), Err(Error::BadName));
	let acc = t.s.account(a).unwrap().unwrap();
	assert_eq!(acc.steam_id, Some(76561198000000001));
	assert_eq!(acc.flags, 0);
	assert_eq!(t.s.stats().unwrap().accounts, 3);
	t.ok();
}

#[test]
fn hero_create_slots_names() {
	let mut t = T::new("hero");
	let a = t.account(1);
	let b = t.account(2);
	let h1 = t.hero(a, "Morwen");
	t.hero(a, "Brannoc");
	t.hero(a, "Isolde");
	let m = t.m();
	assert!(matches!(t.s.hero_create(m, a, "Fourth", 0, 0, 0, false), Err(Error::Full(_))));
	let m = t.m();
	assert_eq!(t.s.grant_entitlement(m, a, EntitlementKind::HeroSlot, 1, "steam-tx-1").unwrap(), (true, 1));
	let h4 = t.hero(a, "Fourth");
	let m = t.m();
	assert_eq!(t.s.hero_create(m, b, "morwen", 0, 0, 0, false), Err(Error::NameTaken));
	let m = t.m();
	assert_eq!(t.s.hero_create(m, b, "x", 0, 0, 0, false), Err(Error::BadName));
	let m = t.m();
	assert_eq!(t.s.hero_create(m, b, "9lives", 0, 0, 0, false), Err(Error::BadName));
	let m = t.m();
	assert_eq!(t.s.hero_create(m, b, "has space", 0, 0, 0, false), Err(Error::BadName));
	let m = t.m();
	assert!(matches!(t.s.hero_create(m, b, "Okname", 9, 0, 0, false), Err(Error::Invalid(_))));
	// not yours
	let m = t.by(b);
	assert!(matches!(t.s.hero_create(m, a, "Sneaky", 0, 0, 0, false), Err(Error::NotYours(_))));
	let m = t.by(b);
	assert!(matches!(t.s.hero_rename(m, h1, "Stolen"), Err(Error::NotYours(_))));
	// rename, case change of own name allowed
	let m = t.by(a);
	t.s.hero_rename(m, h1, "MORWEN").unwrap();
	let m = t.m();
	t.s.hero_rename(m, h4, "Quartus").unwrap();
	let m = t.m();
	assert_eq!(t.s.hero_rename(m, h4, "isolde"), Err(Error::NameTaken));
	assert_eq!(t.s.hero(h1).unwrap().unwrap().name, "MORWEN");
	assert_eq!(t.s.heroes(a, false).unwrap().len(), 4);
	let m = t.m();
	assert!(matches!(t.s.hero_rename(m, 999, "Nobody"), Err(Error::Missing(_))));
	t.ok();
}

#[test]
fn hero_delete_undelete() {
	let mut t = T::new("del");
	let a = t.account(1);
	let b = t.account(2);
	let h = t.hero(a, "Morwen");
	let item = t.mint_bag(h, 1);
	let m = t.m();
	t.s.hero_delete(m, h).unwrap();
	let m = t.m();
	assert_eq!(t.s.hero_delete(m, h), Err(Error::Deleted));
	assert_eq!(t.s.heroes(a, false).unwrap().len(), 0);
	assert_eq!(t.s.heroes(a, true).unwrap().len(), 1);
	// the name stays held for 7 days; the item stays
	let m = t.m();
	assert_eq!(t.s.hero_create(m, b, "Morwen", 0, 0, 0, false), Err(Error::NameTaken));
	assert!(t.s.item(item).unwrap().is_some());
	let m = t.m();
	assert!(matches!(t.s.move_item(m, item, Dest::bank(a, 0)), Err(Error::Deleted)));
	let m = t.m();
	t.s.hero_undelete(m, h).unwrap();
	let m = t.m();
	assert!(matches!(t.s.hero_undelete(m, h), Err(Error::Invalid(_))));
	// past 7 days: expired, and the name is free
	let m = t.m();
	t.s.hero_delete(m, h).unwrap();
	t.now += UNDELETE_MS + 1;
	let m = t.m();
	assert_eq!(t.s.hero_undelete(m, h), Err(Error::Expired));
	let m = t.m();
	t.s.hero_create(m, b, "morwen", 0, 0, 0, false).unwrap();
	// undelete with full slots
	let mut t2 = T::new("del2");
	let a = t2.account(1);
	let h = t2.hero(a, "One");
	let m = t2.m();
	t2.s.hero_delete(m, h).unwrap();
	t2.hero(a, "Two");
	t2.hero(a, "Three");
	t2.hero(a, "Four");
	let m = t2.m();
	assert!(matches!(t2.s.hero_undelete(m, h), Err(Error::Full(_))));
	t.ok();
	t2.ok();
}

fn progress(level: u16) -> Progress {
	Progress {
		job: 1,
		class_level: level,
		class_xp: 5000,
		stats: [level - 1, 0, 0, 0, 0, 0],
		unspent: 0,
		deck: (0..12).collect(),
		belt: [StackKind::potion(0).0, 0, 0],
		waystones: [3, -1, -1, -1, -1, -1],
	}
}

#[test]
fn hero_save_rules() {
	let mut t = T::new("save");
	let a = t.account(1);
	let h = t.hero(a, "Morwen");
	let m = t.m();
	t.s.hero_save(m, h, progress(10)).unwrap();
	let got = t.s.hero(h).unwrap().unwrap().progress;
	assert_eq!(got, progress(10));
	let m = t.m();
	assert!(matches!(t.s.hero_save(m, h, progress(9)), Err(Error::Invalid(_))), "level never goes down");
	let mut p = progress(10);
	p.class_xp = 10;
	let m = t.m();
	assert!(matches!(t.s.hero_save(m, h, p), Err(Error::Invalid(_))), "xp never goes down");
	let mut p = progress(10);
	p.unspent = 3;
	let m = t.m();
	assert!(matches!(t.s.hero_save(m, h, p), Err(Error::Invalid(_))), "points add up");
	let mut p = progress(10);
	p.deck.push(25);
	let m = t.m();
	assert!(matches!(t.s.hero_save(m, h, p.clone()), Err(Error::Missing(_))), "card 25 not owned");
	let mut p2 = progress(10);
	p2.deck.push(13); // unlocked at level 4
	let m = t.m();
	t.s.hero_save(m, h, p2).unwrap();
	let mut p3 = progress(10);
	p3.deck.push(0);
	let m = t.m();
	assert!(matches!(t.s.hero_save(m, h, p3), Err(Error::Invalid(_))), "duplicate card");
	let mut p4 = progress(10);
	p4.belt[1] = StackKind::COIN.0;
	let m = t.m();
	assert!(matches!(t.s.hero_save(m, h, p4), Err(Error::Invalid(_))), "belt holds potions");
	// learning the page owns the card
	let m = t.m();
	assert!(matches!(t.s.learn_page(m, h, 25), Err(Error::Insufficient { .. })));
	t.credit(Owner::bag(h), StackKind::page(25), 1);
	let m = t.m();
	t.s.learn_page(m, h, 25).unwrap();
	let m = t.m();
	assert!(matches!(t.s.learn_page(m, h, 25), Err(Error::Invalid(_))));
	let m = t.m();
	t.s.hero_save(m, h, p).unwrap();
	t.ok();
}

#[test]
fn mint_rules_and_idempotency() {
	let mut t = T::new("mint");
	let a = t.account(1);
	let h = t.hero(a, "Morwen");
	let m = t.m();
	let (id, place) = t.s.mint(m, Dest::bag(h), spec(1), "drop").unwrap();
	assert_eq!(place, Place { kind: PlaceKind::Bag, owner: h, tab: 0, slot: 0 });
	// the same request again: same reply, no second item
	assert_eq!(t.s.mint(m, Dest::bag(h), spec(1), "drop").unwrap(), (id, place));
	assert_eq!(t.s.items_at(PlaceKind::Bag, h).unwrap().len(), 1);
	// same id, other arguments
	assert_eq!(t.s.mint(m, Dest::bag(h), spec(2), "drop"), Err(Error::RequestMismatch));
	let it = t.s.item(id).unwrap().unwrap();
	assert_eq!(it.origin_account, a);
	assert_eq!(it.origin_hero, Some(h));
	let m = t.m();
	assert!(matches!(t.s.mint(m, Dest::bag(h), spec(1), "found it"), Err(Error::Invalid(_))));
	let m = t.m();
	assert_eq!(t.s.mint(m, Dest::at(PlaceKind::Bag, h, 0, 0), spec(1), "drop"), Err(Error::SlotTaken(place)));
	let m = t.m();
	assert!(matches!(t.s.mint(m, Dest::at(PlaceKind::Bag, h, 0, 40), spec(1), "drop"), Err(Error::Invalid(_))));
	let m = t.m();
	assert!(matches!(t.s.mint(m, Dest::bank(a, 1), spec(1), "drop"), Err(Error::Full(_))), "tab 1 not open");
	let m = t.m();
	assert_eq!(t.s.mint(m, Dest::any(PlaceKind::Worn, h), spec(5), "drop"), Err(Error::LevelTooLow { need: 5, have: 1 }));
	let m = t.m();
	assert!(matches!(t.s.mint(m, Dest::bag(h), ItemSpec { rarity: 9, ..spec(1) }, "drop"), Err(Error::Invalid(_))));
	let m = t.m();
	assert!(matches!(t.s.mint(m, Dest::any(PlaceKind::Market, 5), spec(1), "drop"), Err(Error::Invalid(_))));
	let m = t.m();
	assert!(matches!(t.s.mint(m, Dest::bag(777), spec(1), "drop"), Err(Error::Missing(_))));
	for _ in 1..40 {
		t.mint_bag(h, 1);
	}
	let m = t.m();
	assert!(matches!(t.s.mint(m, Dest::bag(h), spec(1), "drop"), Err(Error::Full(_))));
	// a failed request keeps its reply: repeated after room is made it still says Full
	let failed = m;
	let first = t.s.items_at(PlaceKind::Bag, h).unwrap()[0].id;
	let m = t.m();
	t.s.move_item(m, first, Dest::bank(a, 0)).unwrap();
	assert!(matches!(t.s.mint(failed, Dest::bag(h), spec(1), "drop"), Err(Error::Full(_))));
	let m = t.m();
	t.s.mint(m, Dest::bag(h), spec(1), "drop").unwrap();
	t.ok();
}

#[test]
fn bank_tabs_and_slots() {
	let mut t = T::new("bank");
	let a = t.account(1);
	let h = t.hero(a, "Morwen");
	for _ in 0..BANK_SLOTS {
		let m = t.m();
		t.s.mint(m, Dest::bank(a, 0), spec(1), "grant").unwrap();
	}
	let m = t.m();
	assert!(matches!(t.s.mint(m, Dest::bank(a, 0), spec(1), "grant"), Err(Error::Full(_))));
	let m = t.m();
	t.s.grant_entitlement(m, a, EntitlementKind::BankTab, 1, "p-1").unwrap();
	let m = t.m();
	let (_, p) = t.s.mint(m, Dest::bank(a, 1), spec(1), "grant").unwrap();
	assert_eq!((p.tab, p.slot), (1, 0));
	let i = t.mint_bag(h, 1);
	let m = t.m();
	assert!(matches!(t.s.move_item(m, i, Dest::bank(a, 0)), Err(Error::Full(_))));
	let m = t.m();
	assert_eq!(t.s.move_item(m, i, Dest::at(PlaceKind::Bank, a, 1, 5)).unwrap().slot, 5);
	t.ok();
}

#[test]
fn moves() {
	let mut t = T::new("move");
	let a = t.account(1);
	let b = t.account(2);
	let h = t.hero(a, "Morwen");
	let h2 = t.hero(a, "Brannoc");
	let g = t.hero(b, "Gwyn");
	let i = t.mint_bag(h, 3);
	// wear: level too low, then after levelling
	let m = t.m();
	assert_eq!(t.s.move_item(m, i, Dest::any(PlaceKind::Worn, h)), Err(Error::LevelTooLow { need: 3, have: 1 }));
	let m = t.m();
	t.s.hero_save(m, h, Progress { stats: [2, 0, 0, 0, 0, 0], ..progress(3) }).unwrap();
	let m = t.m();
	assert!(matches!(t.s.move_item(m, i, Dest::at(PlaceKind::Worn, h, 0, 2)), Err(Error::Invalid(_))), "wrong gear slot");
	let m = t.m();
	let p = t.s.move_item(m, i, Dest::any(PlaceKind::Worn, h)).unwrap();
	assert_eq!(p, Place { kind: PlaceKind::Worn, owner: h, tab: 0, slot: 0 });
	let j = t.mint_bag(h, 1);
	let m = t.m();
	assert_eq!(t.s.move_item(m, j, Dest::any(PlaceKind::Worn, h)), Err(Error::SlotTaken(p)));
	// bag reorder in a full bag works
	for _ in 0..39 {
		t.mint_bag(h, 1);
	}
	let m = t.m();
	assert!(matches!(t.s.move_item(m, i, Dest::bag(h)), Err(Error::Full(_))));
	let m = t.m();
	t.s.move_item(m, j, Dest::bank(a, 0)).unwrap();
	let m = t.m();
	t.s.move_item(m, j, Dest::at(PlaceKind::Bag, h, 0, 0)).unwrap();
	let k = t.s.items_at(PlaceKind::Bag, h).unwrap()[5].id;
	let m = t.m();
	assert!(matches!(t.s.move_item(m, k, Dest::at(PlaceKind::Bag, h, 0, 0)), Err(Error::SlotTaken(_))));
	// house, guild, mail to another account's hero, mail to own other hero
	let m = t.by(a);
	assert_eq!(t.s.move_item(m, k, Dest::any(PlaceKind::House, a)).unwrap().kind, PlaceKind::House);
	let m = t.by(a);
	assert!(matches!(t.s.move_item(m, k, Dest::any(PlaceKind::Guild, 9)), Err(Error::NotYours(_))), "guild banks are the server's");
	let m = t.m();
	assert_eq!(t.s.move_item(m, k, Dest::any(PlaceKind::Guild, 9)).unwrap().kind, PlaceKind::Guild);
	let m = t.m();
	assert_eq!(t.s.move_item(m, k, Dest::bag(g)).unwrap().owner, g, "guild member takes it out, through the server");
	let m = t.by(b);
	assert!(matches!(t.s.move_item(m, k, Dest::any(PlaceKind::Mail, h2)), Err(Error::NotYours(_))), "a player mails only its own heroes");
	let m = t.m();
	assert_eq!(t.s.move_item(m, k, Dest::any(PlaceKind::Mail, h2)).unwrap().kind, PlaceKind::Mail);
	// not yours
	let m = t.by(b);
	assert!(matches!(t.s.move_item(m, k, Dest::bag(g)), Err(Error::NotYours(_))));
	let m = t.by(a);
	assert!(matches!(t.s.move_item(m, k, Dest::bank(b, 0)), Err(Error::NotYours(_))));
	let m = t.by(a);
	t.s.move_item(m, k, Dest::bag(h2)).unwrap();
	let m = t.m();
	assert!(matches!(t.s.move_item(m, k, Dest::bag(h2)), Err(Error::Invalid(_))), "already there");
	let m = t.m();
	assert!(matches!(t.s.move_item(m, 9999, Dest::bag(h2)), Err(Error::Missing(_))));
	let m = t.m();
	assert!(matches!(t.s.move_item(m, k, Dest::any(PlaceKind::Trade, 1)), Err(Error::Invalid(_))));
	// a banned actor is refused
	let m = t.m();
	t.s.apply_flags(m, vec![FlagChange { account: a, flags: 0, drops_percent: 100, banned_until: Some(t.now + 10_000_000) }], "test").unwrap();
	let m = t.by(a);
	assert!(matches!(t.s.move_item(m, k, Dest::bank(a, 0)), Err(Error::Banned { .. })));
	t.ok();
}

#[test]
fn sell() {
	let mut t = T::new("sell");
	let a = t.account(1);
	let h = t.hero(a, "Morwen");
	let h2 = t.hero(a, "Brannoc");
	let i = t.mint_bag(h, 1);
	let m = t.m();
	assert!(matches!(t.s.sell_item(m, h2, i, 50), Err(Error::NotYours(_))));
	let m = t.m();
	assert_eq!(t.s.sell_item(m, h, i, 50).unwrap(), 50);
	assert_eq!(t.s.sell_item(m, h, i, 50).unwrap(), 50, "repeat: same reply, no second credit");
	assert_eq!(t.s.stack(Owner::bag(h), StackKind::COIN).unwrap(), 50);
	assert!(t.s.item(i).unwrap().is_none());
	let m = t.m();
	assert!(matches!(t.s.sell_item(m, h, i, 50), Err(Error::Missing(_))));
	t.ok();
}

#[test]
fn sockets() {
	let mut t = T::new("sock");
	let a = t.account(1);
	let h = t.hero(a, "Morwen");
	let i = t.mint_bag(h, 1);
	let rune = StackKind::rune(0, 1);
	let card = StackKind::card(7);
	let m = t.m();
	assert!(matches!(t.s.socket(m, h, i, 0, rune), Err(Error::Insufficient { .. })));
	t.credit(Owner::bag(h), rune, 2);
	t.credit(Owner::bag(h), card, 1);
	let m = t.m();
	assert!(matches!(t.s.socket(m, h, i, 0, StackKind::COIN), Err(Error::Invalid(_))));
	let m = t.m();
	assert!(matches!(t.s.socket(m, h, i, 2, rune), Err(Error::Missing(_))));
	let m = t.m();
	t.s.socket(m, h, i, 0, rune).unwrap();
	let m = t.m();
	assert!(matches!(t.s.socket(m, h, i, 0, rune), Err(Error::Invalid(_))), "socket full");
	let m = t.m();
	t.s.socket(m, h, i, 1, card).unwrap();
	assert_eq!(t.s.item(i).unwrap().unwrap().socketed, vec![Some(rune), Some(card)]);
	assert_eq!(t.s.stack(Owner::bag(h), rune).unwrap(), 1);
	assert_eq!(t.s.stack(Owner::bag(h), card).unwrap(), 0);
	let m = t.m();
	t.s.unsocket(m, h, i, 1).unwrap();
	let m = t.m();
	assert!(matches!(t.s.unsocket(m, h, i, 1), Err(Error::Missing(_))));
	assert_eq!(t.s.stack(Owner::bag(h), card).unwrap(), 1);
	// unsocket needs a bag slot for a new kind: fill the bag
	let m = t.m();
	t.s.socket(m, h, i, 1, card).unwrap();
	for _ in 0..38 {
		t.mint_bag(h, 1);
	}
	// bag: 39 items + rune kind = 40
	let m = t.m();
	assert!(matches!(t.s.unsocket(m, h, i, 1), Err(Error::Full(_))));
	let m = t.m();
	t.s.unsocket(m, h, i, 0).unwrap(); // runes of that kind already take a slot
	t.ok();
}

#[test]
fn stacks_credit_debit_transfer() {
	let mut t = T::new("stack");
	let a = t.account(1);
	let b = t.account(2);
	let h = t.hero(a, "Morwen");
	let coin = StackKind::COIN;
	let m = t.m();
	assert_eq!(t.s.stack_credit(m, Owner::bag(h), coin, 100, true, "drop").unwrap(), 100);
	assert_eq!(t.s.stack_credit(m, Owner::bag(h), coin, 100, true, "drop").unwrap(), 100, "repeat");
	let m = t.m();
	assert_eq!(t.s.stack_debit(m, Owner::bag(h), coin, 30, "buy").unwrap(), 70);
	let m = t.m();
	assert_eq!(t.s.stack_debit(m, Owner::bag(h), coin, 71, "buy"), Err(Error::Insufficient { kind: coin, have: 70, want: 71 }));
	let m = t.m();
	assert_eq!(t.s.stack_transfer(m, Owner::bag(h), Owner::bank(a), coin, 20).unwrap(), 50);
	assert_eq!(t.s.stack(Owner::bank(a), coin).unwrap(), 20);
	let m = t.m();
	assert!(matches!(t.s.stack_credit(m, Owner::bag(h), StackKind(77), 1, true, "drop"), Err(Error::Invalid(_))));
	let m = t.m();
	assert!(matches!(t.s.stack_credit(m, Owner::bag(h), coin, 0, true, "drop"), Err(Error::Invalid(_))));
	let m = t.m();
	assert!(matches!(t.s.stack_credit(m, Owner { kind: PlaceKind::Worn, id: h }, coin, 1, true, "drop"), Err(Error::Invalid(_))));
	let m = t.by(b);
	assert!(matches!(t.s.stack_transfer(m, Owner::bank(a), Owner::bank(b), coin, 1), Err(Error::NotYours(_))));
	let m = t.m();
	assert!(matches!(t.s.stack_transfer(m, Owner::bank(a), Owner::bank(a), coin, 1), Err(Error::Invalid(_))));
	// potion kinds take bag slots; coin and materials do not
	for _ in 0..39 {
		t.mint_bag(h, 1);
	}
	t.credit(Owner::bag(h), StackKind::material(3), 500);
	t.credit(Owner::bag(h), StackKind::potion(0), 3);
	let m = t.m();
	assert!(matches!(t.s.stack_credit(m, Owner::bag(h), StackKind::potion(1), 1, true, "drop"), Err(Error::Full(_))));
	t.credit(Owner::bag(h), StackKind::potion(0), 3);
	t.ok();
}

#[test]
fn outing_delta() {
	let mut t = T::new("outing");
	let a = t.account(1);
	let h = t.hero(a, "Morwen");
	t.credit(Owner::bag(h), StackKind::potion(0), 3);
	for _ in 0..37 {
		t.mint_bag(h, 1);
	}
	// bag: 37 items + potion = 38 used
	let d = OutingDelta {
		coin: 250,
		xp: 900,
		levels: 2,
		items: vec![spec(1), spec(2), spec(3), spec(4)],
		stacks: vec![(StackKind::material(1), 40), (StackKind::key(2), 1), (StackKind::rune(1, 1), 1)],
		potions_used: vec![(StackKind::potion(0), 3)],
		waystone: Some((1, 4)),
	};
	let m = t.m();
	let got = t.s.apply_outing(m, h, d.clone()).unwrap();
	assert_eq!(got.len(), 4);
	// potion used frees its slot: 37 + key + rune = 39, so one item fits, three go to mail
	let in_bag = got.iter().filter(|(_, p)| p.kind == PlaceKind::Bag).count();
	assert_eq!(in_bag, 1);
	assert_eq!(got.iter().filter(|(_, p)| p.kind == PlaceKind::Mail).count(), 3);
	assert_eq!(t.s.apply_outing(m, h, d.clone()).unwrap(), got, "repeat: same reply");
	assert_eq!(t.s.stack(Owner::bag(h), StackKind::COIN).unwrap(), 250);
	assert_eq!(t.s.stack(Owner::bag(h), StackKind::potion(0)).unwrap(), 0);
	let hero = t.s.hero(h).unwrap().unwrap();
	assert_eq!((hero.progress.class_level, hero.progress.class_xp, hero.progress.unspent), (3, 900, 2));
	assert_eq!(hero.progress.waystones[1], 4);
	// potions it does not have: nothing at all is applied
	let m = t.m();
	let bad = OutingDelta { coin: 99, potions_used: vec![(StackKind::potion(0), 1)], ..Default::default() };
	assert!(matches!(t.s.apply_outing(m, h, bad), Err(Error::Insufficient { .. })));
	assert_eq!(t.s.stack(Owner::bag(h), StackKind::COIN).unwrap(), 250);
	let m = t.m();
	assert!(matches!(t.s.apply_outing(m, h, OutingDelta { levels: 60, ..Default::default() }), Err(Error::Invalid(_))));
	// a new slot kind with a full bag goes to mail
	let m = t.m();
	t.s.apply_outing(m, h, OutingDelta { stacks: vec![(StackKind::page(20), 1)], ..Default::default() }).unwrap();
	assert_eq!(t.s.stack(Owner { kind: PlaceKind::Mail, id: h }, StackKind::page(20)).unwrap(), 1);
	t.ok();
}

#[test]
fn trade() {
	let mut t = T::new("trade");
	let a = t.account(1);
	let b = t.account(2);
	let ha = t.hero(a, "Morwen");
	let hb = t.hero(b, "Gwyn");
	let i1 = t.mint_bag(ha, 1);
	let i2 = t.mint_bag(ha, 1);
	let j1 = t.mint_bag(hb, 1);
	t.credit(Owner::bag(ha), StackKind::COIN, 500);
	t.credit(Owner::bag(hb), StackKind::rune(2, 2), 3);
	let sa = TradeSide { hero: ha, items: vec![i1, i2], stacks: vec![(StackKind::COIN, 200)] };
	let sb = TradeSide { hero: hb, items: vec![j1], stacks: vec![(StackKind::rune(2, 2), 2)] };
	let rid = trade_request_id(&sa, &sb, 1);
	assert_eq!(rid, trade_request_id(&sb, &sa, 1), "both parties derive the same id");
	t.now += 1000;
	let m = Meta::system(rid, t.now);
	t.s.trade_commit(m, sa.clone(), sb.clone()).unwrap();
	t.s.trade_commit(m, sa.clone(), sb.clone()).unwrap();
	assert_eq!(t.s.item(i1).unwrap().unwrap().place.owner, hb);
	assert_eq!(t.s.item(j1).unwrap().unwrap().place.owner, ha);
	assert_eq!(t.s.stack(Owner::bag(ha), StackKind::COIN).unwrap(), 300);
	assert_eq!(t.s.stack(Owner::bag(hb), StackKind::COIN).unwrap(), 200);
	assert_eq!(t.s.stack(Owner::bag(ha), StackKind::rune(2, 2)).unwrap(), 2);
	assert_eq!(t.s.item(i1).unwrap().unwrap().origin_account, a, "origin survives a trade");
	// bound
	let m = t.m();
	let (bound, _) = t.s.mint(m, Dest::bag(ha), ItemSpec { bound: true, ..spec(1) }, "chest").unwrap();
	let m = t.m();
	assert_eq!(
		t.s.trade_commit(m, TradeSide { hero: ha, items: vec![bound], stacks: vec![] }, TradeSide { hero: hb, ..Default::default() }),
		Err(Error::Bound(bound))
	);
	// not carried, insufficient, self
	let m = t.m();
	assert!(matches!(
		t.s.trade_commit(m, TradeSide { hero: ha, items: vec![i1], stacks: vec![] }, TradeSide { hero: hb, ..Default::default() }),
		Err(Error::NotYours(_))
	));
	let m = t.m();
	assert!(matches!(
		t.s.trade_commit(m, TradeSide { hero: ha, items: vec![], stacks: vec![(StackKind::COIN, 9999)] }, TradeSide { hero: hb, ..Default::default() }),
		Err(Error::Insufficient { .. })
	));
	let m = t.m();
	assert!(matches!(t.s.trade_commit(m, TradeSide { hero: ha, ..Default::default() }, TradeSide { hero: ha, ..Default::default() }), Err(Error::Invalid(_))));
	// receiver's bag full: nothing moves
	for _ in 0..37 {
		t.mint_bag(hb, 1);
	}
	let before = t.s.stats().unwrap().digest;
	let m = t.m();
	assert!(matches!(
		t.s.trade_commit(m, TradeSide { hero: ha, items: vec![j1], stacks: vec![(StackKind::COIN, 1)] }, TradeSide { hero: hb, ..Default::default() }),
		Err(Error::Full(_))
	));
	assert_eq!(t.s.stats().unwrap().digest, before);
	// swapping in a full bag works when the receiver gives as much
	let mine = t.s.items_at(PlaceKind::Bag, hb).unwrap()[3].id;
	let m = t.m();
	t.s.trade_commit(m, TradeSide { hero: ha, items: vec![j1], stacks: vec![] }, TradeSide { hero: hb, items: vec![mine], stacks: vec![] }).unwrap();
	t.ok();
}

#[test]
fn entitlements_once_per_purchase() {
	let mut t = T::new("ent");
	let a = t.account(1);
	let m = t.m();
	assert_eq!(t.s.grant_entitlement(m, a, EntitlementKind::Look, 1, "tx-9").unwrap(), (true, 1));
	let m2 = t.m();
	assert_eq!(t.s.grant_entitlement(m2, a, EntitlementKind::Look, 1, "tx-9").unwrap(), (false, 1), "new request, same purchase");
	assert_eq!(t.s.grant_entitlement(m, a, EntitlementKind::Look, 1, "tx-9").unwrap(), (true, 1), "same request: first reply");
	let m = t.m();
	assert!(matches!(t.s.grant_entitlement(m, a, EntitlementKind::BankTab, 1, "tx-9"), Err(Error::Invalid(_))));
	let m = t.m();
	assert_eq!(t.s.grant_entitlement(m, a, EntitlementKind::Look, 2, "tx-10").unwrap(), (true, 3));
	assert_eq!(t.s.entitlements(a).unwrap(), vec![(EntitlementKind::Look, 3)]);
	let m = t.m();
	assert!(matches!(t.s.grant_entitlement(m, 404, EntitlementKind::Look, 1, "tx-11"), Err(Error::Missing(_))));
	t.ok();
}

#[test]
fn group_commit_many_threads() {
	let path = fresh("group");
	let s = Arc::new(SqliteStore::open_with(&path, Options { group_window: Duration::from_millis(20), ..Default::default() }).unwrap());
	let a = s.account_by_steam(Meta::system(1, 1), 5).unwrap();
	let mut heroes = Vec::new();
	for i in 0..3 {
		heroes.push(s.hero_create(Meta::system(10 + i, 1), a, &format!("Hero{i}"), 0, 0, 0, false).unwrap());
	}
	let mut hs = Vec::new();
	for th in 0..12u128 {
		let s = s.clone();
		let h = heroes[(th % 3) as usize];
		hs.push(std::thread::spawn(move || {
			for k in 0..30u128 {
				let id = 1_000_000 + th * 1000 + k;
				s.stack_credit(Meta::system(id, 2), Owner::bag(h), StackKind::COIN, 1, true, "drop").unwrap();
			}
		}));
	}
	for h in hs {
		h.join().unwrap();
	}
	let total: u64 = heroes.iter().map(|h| s.stack(Owner::bag(*h), StackKind::COIN).unwrap()).sum();
	assert_eq!(total, 360);
	assert!(s.verify().unwrap().ok());
	s.close();
}

#[test]
fn batch_errors_roll_back_alone() {
	let mut t = T::new("batch");
	let a = t.account(1);
	let h = t.hero(a, "Morwen");
	let mk = |id: u128, cmd: Cmd| Request { id, actor: 0, now: 5, cmd };
	let rs = t.s.submit_batch(vec![
		mk(9001, Cmd::StackCredit { to: Owner::bag(h), kind: StackKind::COIN, count: 10, minted: true, reason: "drop".into() }),
		mk(9002, Cmd::StackDebit { from: Owner::bag(h), kind: StackKind::COIN, count: 11, reason: "buy".into() }),
		mk(9003, Cmd::StackDebit { from: Owner::bag(h), kind: StackKind::COIN, count: 4, reason: "buy".into() }),
		mk(9001, Cmd::StackCredit { to: Owner::bag(h), kind: StackKind::COIN, count: 10, minted: true, reason: "drop".into() }),
	]);
	assert_eq!(rs[0], Ok(Reply::Count(10)));
	assert!(matches!(rs[1], Err(Error::Insufficient { .. })));
	assert_eq!(rs[2], Ok(Reply::Count(6)));
	assert_eq!(rs[3], Ok(Reply::Count(10)), "repeat inside the batch");
	assert_eq!(t.s.stack(Owner::bag(h), StackKind::COIN).unwrap(), 6);
	t.ok();
}

#[test]
fn backup_and_restore() {
	let mut t = T::new("bk");
	let a = t.account(1);
	let h = t.hero(a, "Morwen");
	for _ in 0..10 {
		t.mint_bag(h, 1);
	}
	t.credit(Owner::bag(h), StackKind::COIN, 77);
	let bk = fresh("bk-copy");
	let rep = t.s.backup(&bk).unwrap();
	assert!(rep.ok() && rep.items == 10, "{rep:?}");
	let digest = t.s.stats().unwrap().digest;
	// change the live one, then restore the backup into a new file and compare
	t.mint_bag(h, 1);
	let target = fresh("bk-restored");
	let rep = restore_file(&bk, &target).unwrap();
	assert!(rep.ok());
	let restored = SqliteStore::open(&target).unwrap();
	assert_eq!(restored.stats().unwrap().digest, digest);
	assert_eq!(restored.stack(Owner::bag(h), StackKind::COIN).unwrap(), 77);
	restored.close();
	// a backup made while writers run
	t.s.close();
	let s = Arc::new(SqliteStore::open_with(&t.path, Options { group_window: Duration::ZERO, ..Default::default() }).unwrap());
	let w = {
		let s = s.clone();
		std::thread::spawn(move || {
			for k in 0..300u128 {
				s.stack_credit(Meta::system(5_000_000 + k, 9), Owner::bag(h), StackKind::COIN, 1, true, "drop").unwrap();
			}
		})
	};
	let bk2 = fresh("bk-live");
	let rep = s.backup(&bk2).unwrap();
	w.join().unwrap();
	assert!(rep.ok(), "{:?}", rep.problems);
	s.close();
}
