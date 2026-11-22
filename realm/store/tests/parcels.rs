//! Parcels (job E1): listings and letters in escrow, the self-found rule, flags, and verify.
mod common;
use common::*;
use realm_store::*;

const FAR: i64 = 1_800_000_000_000;

struct W {
	t: T,
	a: AccountId,
	ha: HeroId,
	b: AccountId,
	hb: HeroId,
}

fn world(name: &str) -> W {
	let mut t = T::new(name);
	let a = t.account(1);
	let ha = t.hero(a, "Seller");
	let b = t.account(2);
	let hb = t.hero(b, "Buyer");
	t.credit(Owner::bag(hb), StackKind::COIN, 1000);
	W { t, a, ha, b, hb }
}

fn listing(t: &mut T, hero: HeroId, items: Vec<ItemId>, stacks: Vec<(StackKind, u64)>, price: u64, fee: u64) -> Result<i64> {
	let m = t.m();
	t.s.parcel_put(m, Cmd::ParcelPut { kind: ParcelKind::Listing, from: hero, to: None, items, stacks, price, fee, expires: FAR, text: String::new() })
}

fn letter(t: &mut T, from: HeroId, to: HeroId, items: Vec<ItemId>, stacks: Vec<(StackKind, u64)>, cod: u64) -> Result<i64> {
	let m = t.m();
	t.s.parcel_put(m, Cmd::ParcelPut { kind: ParcelKind::Letter, from, to: Some(to), items, stacks, price: cod, fee: 0, expires: FAR, text: "hi".into() })
}

fn coin(w: &W, h: HeroId) -> u64 {
	w.t.s.stack(Owner::bag(h), StackKind::COIN).unwrap()
}

#[test]
fn a_sale_pays_the_seller_less_tax_and_moves_the_item() {
	let mut w = world("p-sale");
	let it = w.t.mint_bag(w.ha, 5);
	let id = listing(&mut w.t, w.ha, vec![it], vec![], 200, 0).unwrap();
	assert_eq!(w.t.s.item(it).unwrap().unwrap().place.kind, PlaceKind::Market);
	assert_eq!(w.t.s.listings(&ListingQuery { now: w.t.now, limit: 10, ..Default::default() }).unwrap().len(), 1);
	let m = w.t.m();
	w.t.s.parcel_take(m, id, w.hb, 10).unwrap();
	let item = w.t.s.item(it).unwrap().unwrap();
	assert_eq!((item.place.kind, item.place.owner), (PlaceKind::Bag, w.hb));
	assert_eq!(item.origin_account, w.a, "the origin survives the sale");
	assert_eq!(coin(&w, w.hb), 800);
	assert_eq!(coin(&w, w.ha), 190);
	assert!(w.t.s.parcel(id).unwrap().is_none());
	w.t.ok();
}

#[test]
fn a_buyer_who_cannot_pay_or_has_no_room_changes_nothing() {
	let mut w = world("p-fail");
	let it = w.t.mint_bag(w.ha, 5);
	let id = listing(&mut w.t, w.ha, vec![it], vec![], 5000, 0).unwrap();
	let before = w.t.s.stats().unwrap().digest;
	let m = w.t.m();
	assert!(matches!(w.t.s.parcel_take(m, id, w.hb, 0), Err(Error::Insufficient { .. })));
	assert_eq!(w.t.s.stats().unwrap().digest, before);
	let m = w.t.m();
	assert!(matches!(w.t.s.parcel_take(m, id, w.ha, 0), Err(Error::Invalid(_))), "her own listing");
	let it2 = w.t.mint_bag(w.ha, 5);
	let id2 = listing(&mut w.t, w.ha, vec![it2], vec![], 10, 0).unwrap();
	for _ in 0..40 {
		w.t.mint_bag(w.hb, 1);
	}
	let m = w.t.m();
	assert!(matches!(w.t.s.parcel_take(m, id2, w.hb, 0), Err(Error::Full(_))));
	assert_eq!(coin(&w, w.hb), 1000);
	assert_eq!(w.t.s.item(it2).unwrap().unwrap().place.kind, PlaceKind::Market);
	w.t.ok();
}

#[test]
fn a_cancel_returns_to_mail_and_a_stack_listing_works() {
	let mut w = world("p-cancel");
	w.t.credit(Owner::bag(w.ha), StackKind::material(0), 50);
	w.t.credit(Owner::bag(w.ha), StackKind::COIN, 10);
	let id = listing(&mut w.t, w.ha, vec![], vec![(StackKind::material(0), 30)], 90, 2).unwrap();
	assert_eq!(w.t.s.stack(Owner::bag(w.ha), StackKind::material(0)).unwrap(), 20);
	assert_eq!(coin(&w, w.ha), 8, "the fee is gone");
	let found = w.t.s.listings(&ListingQuery { now: w.t.now, stack: Some(StackKind::material(0)), limit: 5, ..Default::default() }).unwrap();
	assert_eq!(found.len(), 1);
	assert_eq!(found[0].stacks, vec![(StackKind::material(0), 30)]);
	let m = w.t.m();
	w.t.s.parcel_return(m, id).unwrap();
	assert_eq!(w.t.s.stack(Owner { kind: PlaceKind::Mail, id: w.ha }, StackKind::material(0)).unwrap(), 30);
	w.t.ok();
	let id = listing(&mut w.t, w.ha, vec![], vec![(StackKind::material(0), 20)], 100, 0).unwrap();
	let m = w.t.m();
	w.t.s.parcel_take(m, id, w.hb, 5).unwrap();
	assert_eq!(w.t.s.stack(Owner::bag(w.hb), StackKind::material(0)).unwrap(), 20);
	assert_eq!(coin(&w, w.ha), 8 + 95);
	w.t.ok();
}

#[test]
fn due_parcels_are_found_and_listings_hide_when_ended() {
	let mut w = world("p-due");
	let it = w.t.mint_bag(w.ha, 5);
	let m = w.t.m();
	let end = w.t.now + 5000;
	let id = w
		.t
		.s
		.parcel_put(m, Cmd::ParcelPut { kind: ParcelKind::Listing, from: w.ha, to: None, items: vec![it], stacks: vec![], price: 9, fee: 0, expires: end, text: String::new() })
		.unwrap();
	assert!(w.t.s.parcels_due(w.t.now, 10).unwrap().is_empty());
	assert_eq!(w.t.s.parcels_due(end, 10).unwrap(), vec![id]);
	assert!(w.t.s.listings(&ListingQuery { now: end, limit: 5, ..Default::default() }).unwrap().is_empty());
	let m = Meta::system(77777, end + 1000);
	assert!(matches!(w.t.s.parcel_take(m, id, w.hb, 0), Err(Error::Expired)));
	w.t.ok();
}

#[test]
fn letters_with_cash_on_delivery() {
	let mut w = world("p-letter");
	let it = w.t.mint_bag(w.ha, 5);
	let id = letter(&mut w.t, w.ha, w.hb, vec![it], vec![], 300).unwrap();
	assert_eq!(w.t.s.parcels_to(w.hb).unwrap().len(), 1);
	assert_eq!(w.t.s.parcels_from(w.ha).unwrap().len(), 1);
	let m = w.t.m();
	assert!(matches!(w.t.s.parcel_take(m, id, w.ha, 0), Err(Error::NotYours(_))));
	let m = w.t.m();
	w.t.s.parcel_take(m, id, w.hb, 0).unwrap();
	assert_eq!(coin(&w, w.hb), 700);
	assert_eq!(coin(&w, w.ha), 300);
	assert_eq!(w.t.s.item(it).unwrap().unwrap().place.owner, w.hb);
	w.t.credit(Owner::bag(w.ha), StackKind::COIN, 50);
	let id = letter(&mut w.t, w.ha, w.hb, vec![], vec![(StackKind::COIN, 100)], 0).unwrap();
	let m = w.t.m();
	w.t.s.parcel_return(m, id).unwrap();
	assert_eq!(w.t.s.stack(Owner { kind: PlaceKind::Mail, id: w.ha }, StackKind::COIN).unwrap(), 100);
	w.t.ok();
}

#[test]
fn bound_items_and_bad_shapes_are_refused() {
	let mut w = world("p-bad");
	let m = w.t.m();
	let (bound, _) = w.t.s.mint(m, Dest::bag(w.ha), ItemSpec { bound: true, ..spec(3) }, "drop").unwrap();
	assert!(matches!(listing(&mut w.t, w.ha, vec![bound], vec![], 10, 0), Err(Error::Bound(_))));
	let it = w.t.mint_bag(w.ha, 3);
	assert!(matches!(listing(&mut w.t, w.ha, vec![it], vec![], 0, 0), Err(Error::Invalid(_))), "no free listing");
	assert!(matches!(listing(&mut w.t, w.ha, vec![], vec![(StackKind::COIN, 5)], 10, 0), Err(Error::Invalid(_))));
	assert!(matches!(listing(&mut w.t, w.hb, vec![it], vec![], 10, 0), Err(Error::NotYours(_))), "not in her bag");
	assert!(matches!(letter(&mut w.t, w.ha, w.ha, vec![it], vec![], 0), Err(Error::Invalid(_))));
	let before = w.t.s.stats().unwrap().digest;
	assert!(matches!(listing(&mut w.t, w.ha, vec![it], vec![], 10, 5), Err(Error::Insufficient { .. })));
	assert_eq!(w.t.s.stats().unwrap().digest, before);
	w.t.ok();
}

#[test]
fn a_hero_with_things_in_escrow_cannot_be_deleted_and_limits_hold() {
	let mut w = world("p-limits");
	let it = w.t.mint_bag(w.ha, 5);
	listing(&mut w.t, w.ha, vec![it], vec![], 10, 0).unwrap();
	let m = w.t.by(w.a);
	assert!(matches!(w.t.s.hero_delete(m, w.ha), Err(Error::Invalid(_))));
	for _ in 1..25 {
		let it = w.t.mint_bag(w.ha, 1);
		listing(&mut w.t, w.ha, vec![it], vec![], 10, 0).unwrap();
	}
	let it = w.t.mint_bag(w.ha, 1);
	assert!(matches!(listing(&mut w.t, w.ha, vec![it], vec![], 10, 0), Err(Error::Full(_))), "25 listings a hero");
	w.t.ok();
}

#[test]
fn trade_locked_accounts_cannot_list_buy_or_send() {
	let mut w = world("p-flags");
	let it = w.t.mint_bag(w.ha, 5);
	let id = listing(&mut w.t, w.ha, vec![it], vec![], 10, 0).unwrap();
	let m = w.t.m();
	w.t.s.apply_flags(m, vec![FlagChange { account: w.b, flags: flags::TRADE_LOCKED, drops_percent: 100, banned_until: None }], "rmt").unwrap();
	let m = w.t.m();
	assert!(matches!(w.t.s.parcel_take(m, id, w.hb, 0), Err(Error::Refused)));
	let it2 = w.t.mint_bag(w.hb, 5);
	assert!(matches!(listing(&mut w.t, w.hb, vec![it2], vec![], 10, 0), Err(Error::Refused)));
	assert!(matches!(letter(&mut w.t, w.hb, w.ha, vec![it2], vec![], 0), Err(Error::Refused)));
	assert!(matches!(letter(&mut w.t, w.ha, w.hb, vec![it], vec![], 0), Err(Error::Refused)));
	let m = w.t.m();
	w.t.s.parcel_return(m, id).unwrap();
	w.t.ok();
}

#[test]
fn self_found_heroes_neither_trade_nor_market_nor_mail() {
	let mut w = world("p-sf");
	let m = w.t.m();
	let sf = w.t.s.hero_create(m, w.a, "Lonely", 0, 0, 0, true).unwrap();
	let mine = w.t.mint_bag(sf, 5);
	let other = w.t.mint_bag(w.ha, 5);
	assert!(matches!(listing(&mut w.t, sf, vec![mine], vec![], 10, 0), Err(Error::Refused)));
	assert!(matches!(letter(&mut w.t, w.ha, sf, vec![other], vec![], 0), Err(Error::Refused)));
	assert!(matches!(letter(&mut w.t, sf, w.hb, vec![mine], vec![], 0), Err(Error::Refused)));
	let m = w.t.m();
	let r = w.t.s.trade_commit(m, TradeSide { hero: sf, items: vec![mine], stacks: vec![] }, TradeSide { hero: w.hb, items: vec![], stacks: vec![] });
	assert!(matches!(r, Err(Error::Refused)));
	let m = w.t.by(w.a);
	assert!(matches!(w.t.s.move_item(m, mine, Dest::any(PlaceKind::Mail, w.ha)), Err(Error::Refused)));
	let m = w.t.by(w.a);
	assert!(matches!(w.t.s.move_item(m, other, Dest::any(PlaceKind::Mail, sf)), Err(Error::Refused)));
	// through the bank: her own items go in and come out; another hero's cannot reach her
	let m = w.t.by(w.a);
	w.t.s.move_item(m, mine, Dest::bank(w.a, 0)).unwrap();
	let m = w.t.by(w.a);
	w.t.s.move_item(m, mine, Dest::bag(sf)).unwrap();
	let m = w.t.by(w.a);
	w.t.s.move_item(m, other, Dest::bank(w.a, 0)).unwrap();
	let m = w.t.by(w.a);
	assert!(matches!(w.t.s.move_item(m, other, Dest::bag(sf)), Err(Error::Refused)));
	w.t.credit(Owner::bag(w.ha), StackKind::COIN, 10);
	let m = w.t.by(w.a);
	let r = w.t.s.stack_transfer(m, Owner::bag(w.ha), Owner { kind: PlaceKind::Mail, id: sf }, StackKind::COIN, 5);
	assert!(matches!(r, Err(Error::Refused)));
	w.t.ok();
}

#[test]
fn escrow_shows_in_trace_and_verify_catches_a_stray() {
	let mut w = world("p-trace");
	let it = w.t.mint_bag(w.ha, 5);
	let id = listing(&mut w.t, w.ha, vec![it], vec![], 100, 0).unwrap();
	let m = w.t.m();
	w.t.s.parcel_take(m, id, w.hb, 8).unwrap();
	let hops = w.t.s.trace_forward(w.a, 1).unwrap();
	assert!(hops.iter().any(|h| h.item == Some(it) && h.to == Party::Market(id)));
	let tr = w.t.s.trace(w.b).unwrap();
	assert!(tr.stacks.iter().any(|s| s.kind == StackKind::COIN));
	let flows = w.t.s.coin_flows().unwrap();
	assert!(flows.iter().any(|f| f.0 == "DEBIT" && f.1 == "tax" && f.4 == 8));
	w.t.ok();
	let c = rusqlite::Connection::open(&w.t.path).unwrap();
	c.execute("UPDATE items SET place_kind = 5, place_owner = 999, place_slot = 0, place_tab = 0 WHERE id = ?1", [it]).unwrap();
	let r = w.t.s.verify().unwrap();
	assert!(!r.ok());
}
