//! The economy between players: merchants, trade, the market, letters and the self-found rule, through the
//! economy's own door (`Economy::handle`) with a clock we move, and the wire once through real sockets.

use realm_gateway::client::GatewayClient;
use realm_gateway::economy::prices::*;
use realm_gateway::economy::wire::*;
use realm_gateway::economy::Economy;
use realm_gateway::gateway::{Config, Gateway};
use realm_gateway::proto::*;
use realm_store::*;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;

static N: AtomicU64 = AtomicU64::new(1);

struct W {
    store: Arc<SqliteStore>,
    eco: Arc<Economy>,
    db: std::path::PathBuf,
    now: i64,
}

impl Drop for W {
    fn drop(&mut self) {
        self.eco.stop();
        self.store.close();
        for s in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{}{s}", self.db.display()));
        }
    }
}

fn world(name: &str) -> W {
    let db = std::env::temp_dir().join(format!("realm-eco-{}-{name}.db", std::process::id()));
    let _ = std::fs::remove_file(&db);
    let store = Arc::new(SqliteStore::open(&db).unwrap());
    W { eco: Economy::new(store.clone()), store, db, now: 1_700_000_000_000 }
}

fn sys() -> Meta {
    Meta::system(0xEC0 << 100 | N.fetch_add(1, Ordering::SeqCst) as u128, 1)
}

impl W {
    fn account(&self, name: &str) -> i64 {
        self.store.account_by_dev_name(sys(), name).unwrap()
    }
    fn hero(&self, account: i64, name: &str, level: u16, sf: bool) -> i64 {
        let h = self.store.hero_create(sys(), account, name, 1, 1, 0, sf).unwrap();
        if level > 1 {
            self.store.apply_outing(sys(), h, OutingDelta { levels: level - 1, ..Default::default() }).unwrap();
        }
        h
    }
    fn item(&self, hero: i64, level: u16, rarity: u8) -> i64 {
        let spec = ItemSpec { base: 7, gear_slot: 0, item_level: level, rarity, lines: vec![(0, 3)], sockets: 0, plus: 0, bound: false };
        self.store.mint(sys(), Dest::bag(hero), spec, "drop").unwrap().0
    }
    fn coin(&self, hero: i64, n: u64) {
        self.store.stack_credit(sys(), Owner::bag(hero), StackKind::COIN, n, true, "drop").unwrap();
    }
    fn have(&self, hero: i64) -> u64 {
        self.eco.coin(hero)
    }
    fn call(&self, account: i64, r: EReq) -> Resp {
        self.eco.handle(account, r, self.now)
    }
    fn ok(&self, account: i64, r: EReq) -> EResp {
        match self.call(account, r) {
            Resp::Econ(e) => e,
            r => panic!("{r:?}"),
        }
    }
    fn code(&self, account: i64, r: EReq) -> u16 {
        match self.call(account, r) {
            Resp::Err { code, .. } => code,
            r => panic!("expected an error: {r:?}"),
        }
    }
    fn verify(&self) {
        let r = self.store.verify().unwrap();
        assert!(r.ok(), "{:?}", r.problems);
    }
    fn place(&self, item: i64) -> Place {
        self.store.item(item).unwrap().unwrap().place
    }
}

#[test]
fn the_merchant_sells_by_field_and_buys_at_a_quarter_and_caps_a_day() {
    let mut w = world("merchant");
    let a = w.account("ann");
    let h = w.hero(a, "Annie", 25, false);
    w.coin(h, 100_000);
    let EResp::Offers(list) = w.ok(a, EReq::MerchantList { hero: h }) else { panic!() };
    assert_eq!(list.len(), 13);
    // a level 25 hero is in the MOON MARSH (top 30): a healing draught is (8 + 30) x 1
    assert_eq!(list[0].price, 38);
    assert_eq!(list[6].price, 4 + 15, "embers");
    let gear = list[7].item.as_ref().unwrap();
    assert_eq!((gear.info.level, gear.info.rarity), (25, 0));
    assert_eq!(list[7].price, (5 + 3 * 25) * 12);
    let before = w.have(h);
    w.ok(a, EReq::MerchantBuy { hero: h, offer: 0, count: 5 });
    assert_eq!(w.have(h), before - 5 * 38);
    assert_eq!(w.store.stack(Owner::bag(h), StackKind::potion(0)).unwrap(), 5);
    w.ok(a, EReq::MerchantBuy { hero: h, offer: 7, count: 1 });
    assert_eq!(w.code(a, EReq::MerchantBuy { hero: h, offer: 0, count: 16 }), code::BAD_REQUEST, "20 a day: 5 used");
    // the next day the merchant has restocked
    w.now += MS_DAY;
    w.ok(a, EReq::MerchantBuy { hero: h, offer: 0, count: 20 });
    // selling: a quarter of the value, and the item is gone
    let it = w.item(h, 25, 2);
    let value = item_value(&w.store.item(it).unwrap().unwrap().spec);
    let c0 = w.have(h);
    w.ok(a, EReq::MerchantSell { hero: h, what: Thing::Item(it) });
    assert_eq!(w.have(h), c0 + value / 4);
    assert!(w.store.item(it).unwrap().is_none());
    // and buys it back, for 110%
    let EResp::Buybacks(b) = w.ok(a, EReq::Buyback { hero: h }) else { panic!() };
    assert_eq!(b.len(), 1);
    assert_eq!(b[0].price, (value / 4) * 110 / 100);
    w.ok(a, EReq::BuybackTake { hero: h, entry: b[0].id });
    assert_eq!(w.store.items_at(PlaceKind::Bag, h).unwrap().iter().filter(|i| i.spec.rarity == 2).count(), 1);
    // embers sell by the piece; potions he does not buy
    w.store.stack_credit(sys(), Owner::bag(h), StackKind::material(0), 10, true, "drop").unwrap();
    let c0 = w.have(h);
    w.ok(a, EReq::MerchantSell { hero: h, what: Thing::Stack(1000, 10) });
    assert_eq!(w.have(h), c0 + 20);
    assert_eq!(w.code(a, EReq::MerchantSell { hero: h, what: Thing::Stack(100, 1) }), code::BAD_REQUEST);
    // never below: buying an item and selling it back loses money
    w.ok(a, EReq::MerchantBuy { hero: h, offer: 8, count: 1 });
    w.verify();
}

#[test]
fn the_market_lists_searches_sells_taxes_cancels_and_expires() {
    let w = world("market");
    let (a, b) = (w.account("ann"), w.account("bo"));
    let (ha, hb) = (w.hero(a, "Annie", 12, false), w.hero(b, "Bobby", 12, false));
    w.coin(ha, 1000);
    w.coin(hb, 10_000);
    let it = w.item(ha, 12, 2);
    let EResp::Listed { id, fee } = w.ok(a, EReq::MarketList { hero: ha, what: Thing::Item(it), price: 1000, hours: 24 }) else { panic!() };
    assert_eq!(fee, 20, "1% for each 12 hours");
    assert_eq!(w.place(it).kind, PlaceKind::Market);
    assert_eq!(w.have(ha), 1000 - 20);
    // a search finds it, with filters
    let EResp::Listings(v) = w.ok(b, EReq::MarketSearch { hero: hb, q: Search { gear_slot: 0, rarity_min: 2, level_min: 10, level_max: 14, stack: 0, price_max: 0, offset: 0 } }) else { panic!() };
    assert_eq!(v.len(), 1);
    assert_eq!((v[0].id, v[0].price, v[0].mine), (id, 1000, false));
    let EResp::Listings(none) = w.ok(b, EReq::MarketSearch { hero: hb, q: Search { gear_slot: 1, rarity_min: 0, level_min: 0, level_max: 0, stack: 0, price_max: 0, offset: 0 } }) else { panic!() };
    assert!(none.is_empty());
    // she cannot buy her own; he buys it; she gets 940, 60 is gone
    assert_eq!(w.code(a, EReq::MarketBuy { hero: ha, listing: id }), code::INVALID);
    let supply = |w: &W| w.store.stats().unwrap().coin;
    let s0 = supply(&w);
    w.ok(b, EReq::MarketBuy { hero: hb, listing: id });
    assert_eq!(w.have(hb), 9000);
    assert_eq!(w.have(ha), 1000 - 20 + 940);
    assert_eq!(supply(&w), s0 - 60, "the tax left the game");
    let item = w.store.item(it).unwrap().unwrap();
    assert_eq!((item.place.owner, item.origin_account), (hb, a), "the origin is kept");
    assert_eq!(w.eco.totals().tax, 60);
    // cancel, and only by the seller
    let it2 = w.item(hb, 12, 1);
    let EResp::Listed { id: id2, .. } = w.ok(b, EReq::MarketList { hero: hb, what: Thing::Item(it2), price: 50, hours: 12 }) else { panic!() };
    assert_eq!(w.code(a, EReq::MarketCancel { hero: ha, listing: id2 }), code::NOT_YOURS);
    w.ok(b, EReq::MarketCancel { hero: hb, listing: id2 });
    let m = w.store.items_at(PlaceKind::Mail, hb).unwrap();
    assert_eq!(m.len(), 1, "it came back to her mail");
    // expiry: a listing nobody buys goes to the seller's mail
    let it3 = w.item(hb, 12, 1);
    let EResp::Listed { id: id3, .. } = w.ok(b, EReq::MarketList { hero: hb, what: Thing::Item(it3), price: 70, hours: 12 }) else { panic!() };
    assert_eq!(w.eco.sweep(w.now + 11 * MS_HOUR), (0, 0));
    assert_eq!(w.eco.sweep(w.now + 12 * MS_HOUR), (1, 0));
    assert_eq!(w.place(it3).kind, PlaceKind::Mail);
    assert!(w.store.parcel(id3).unwrap().is_none());
    // a stack listing, and the bad shapes
    w.store.stack_credit(sys(), Owner::bag(hb), StackKind::material(0), 40, true, "drop").unwrap();
    w.ok(b, EReq::MarketList { hero: hb, what: Thing::Stack(1000, 40), price: 300, hours: 48 });
    let EResp::Listings(v) = w.ok(a, EReq::MarketSearch { hero: ha, q: Search { gear_slot: 255, rarity_min: 0, level_min: 0, level_max: 0, stack: 1000, price_max: 0, offset: 0 } }) else { panic!() };
    assert_eq!(v[0].stack, Some((1000, 40)));
    assert_eq!(w.code(a, EReq::MarketList { hero: ha, what: Thing::Item(it), price: 10, hours: 24 }), code::NOT_YOURS, "not hers now");
    let it4 = w.item(ha, 5, 0);
    assert_eq!(w.code(a, EReq::MarketList { hero: ha, what: Thing::Item(it4), price: 0, hours: 24 }), code::BAD_REQUEST);
    assert_eq!(w.code(a, EReq::MarketList { hero: ha, what: Thing::Item(it4), price: 5, hours: 7 }), code::BAD_REQUEST);
    w.verify();
}

#[test]
fn letters_carry_attachments_cash_on_delivery_refusal_and_expiry() {
    let w = world("letters");
    let (a, b) = (w.account("ann"), w.account("bo"));
    let (ha, hb) = (w.hero(a, "Annie", 12, false), w.hero(b, "Bobby", 12, false));
    w.coin(ha, 100);
    w.coin(hb, 500);
    let it = w.item(ha, 12, 2);
    let r = w.ok(a, EReq::LetterSend { hero: ha, to_name: "bobby".into(), text: "for you".into(), things: vec![Thing::Item(it)], cod: 300 });
    let EResp::Listed { id, fee } = r else { panic!() };
    assert_eq!(fee, POSTAGE + POSTAGE_PER_THING);
    let EResp::Letters(inbox) = w.ok(b, EReq::Inbox { hero: hb }) else { panic!() };
    assert_eq!((inbox.len(), inbox[0].cod, inbox[0].text.as_str(), inbox[0].from.as_str()), (1, 300, "for you", "Annie"));
    let EResp::Letters(out) = w.ok(a, EReq::Outbox { hero: ha }) else { panic!() };
    assert_eq!(out.len(), 1);
    // the item is in escrow, not in his mail: he cannot take it without paying
    assert_eq!(w.place(it).kind, PlaceKind::Market);
    assert_eq!(w.code(a, EReq::LetterTake { hero: ha, letter: id }), code::NOT_YOURS);
    w.coin(hb, 0 + 1); // keep the world in step
    w.ok(b, EReq::LetterTake { hero: hb, letter: id });
    assert_eq!(w.place(it).owner, hb);
    assert_eq!(w.have(hb), 501 - 300);
    assert_eq!(w.have(ha), 100 - fee + 300);
    // refused: back to the sender's mail; recalled: the same
    let it2 = w.item(ha, 12, 1);
    let EResp::Listed { id: l2, .. } = w.ok(a, EReq::LetterSend { hero: ha, to_name: "Bobby".into(), text: String::new(), things: vec![Thing::Item(it2)], cod: 0 }) else { panic!() };
    w.ok(b, EReq::LetterRefuse { hero: hb, letter: l2 });
    assert_eq!(w.place(it2).kind, PlaceKind::Mail);
    assert_eq!(w.place(it2).owner, ha);
    let it3 = w.item(ha, 12, 1);
    let EResp::Listed { id: l3, .. } = w.ok(a, EReq::LetterSend { hero: ha, to_name: "Bobby".into(), text: String::new(), things: vec![Thing::Item(it3)], cod: 0 }) else { panic!() };
    w.ok(a, EReq::LetterRecall { hero: ha, letter: l3 });
    assert_eq!(w.place(it3).kind, PlaceKind::Mail);
    // 30 days unopened: back to her mail, with a letter sweep
    let it4 = w.item(ha, 12, 1);
    w.ok(a, EReq::LetterSend { hero: ha, to_name: "Bobby".into(), text: String::new(), things: vec![Thing::Item(it4)], cod: 0 });
    assert_eq!(w.eco.sweep(w.now + 29 * MS_DAY), (0, 0));
    assert_eq!(w.eco.sweep(w.now + 31 * MS_DAY), (0, 1));
    assert_eq!(w.place(it4).owner, ha);
    // bad shapes: nothing, to nobody, to herself
    assert_eq!(w.code(a, EReq::LetterSend { hero: ha, to_name: "Bobby".into(), text: String::new(), things: vec![], cod: 0 }), code::BAD_REQUEST);
    assert_eq!(w.code(a, EReq::LetterSend { hero: ha, to_name: "Nobody".into(), text: String::new(), things: vec![Thing::Item(it4)], cod: 0 }), code::MISSING);
    assert_eq!(w.code(a, EReq::LetterSend { hero: ha, to_name: "Annie".into(), text: String::new(), things: vec![Thing::Item(it4)], cod: 0 }), code::INVALID);
    w.verify();
}

#[test]
fn self_found_heroes_and_trade_locked_accounts_are_refused_everywhere() {
    let w = world("sf");
    let (a, b, c) = (w.account("ann"), w.account("bo"), w.account("cy"));
    let ha = w.hero(a, "Lonely", 12, true);
    let hb = w.hero(b, "Bobby", 12, false);
    let hc = w.hero(c, "Cyrus", 12, false);
    for h in [ha, hb, hc] {
        w.coin(h, 1000);
    }
    let mine = w.item(ha, 12, 2);
    let it_b = w.item(hb, 12, 2);
    assert_eq!(w.code(a, EReq::MarketList { hero: ha, what: Thing::Item(mine), price: 10, hours: 12 }), code::REFUSED);
    assert_eq!(w.code(a, EReq::LetterSend { hero: ha, to_name: "Bobby".into(), text: String::new(), things: vec![Thing::Item(mine)], cod: 0 }), code::REFUSED);
    assert_eq!(w.code(b, EReq::LetterSend { hero: hb, to_name: "Lonely".into(), text: String::new(), things: vec![Thing::Item(it_b)], cod: 0 }), code::REFUSED);
    // she buys from the merchant and sells to him; the market is closed to her as a buyer too
    let EResp::Listed { id, .. } = w.ok(b, EReq::MarketList { hero: hb, what: Thing::Item(it_b), price: 10, hours: 12 }) else { panic!() };
    assert_eq!(w.code(a, EReq::MarketBuy { hero: ha, listing: id }), code::REFUSED);
    w.ok(a, EReq::MerchantBuy { hero: ha, offer: 0, count: 1 });
    // a trade-locked account: the flag is the operator's, every path says only "refused"
    w.store
        .apply_flags(sys(), vec![FlagChange { account: c, flags: flags::TRADE_LOCKED, drops_percent: 100, banned_until: None }], "rmt")
        .unwrap();
    assert_eq!(w.code(c, EReq::MarketBuy { hero: hc, listing: id }), code::REFUSED);
    let it_c = w.item(hc, 12, 2);
    assert_eq!(w.code(c, EReq::MarketList { hero: hc, what: Thing::Item(it_c), price: 10, hours: 12 }), code::REFUSED);
    assert_eq!(w.code(c, EReq::LetterSend { hero: hc, to_name: "Bobby".into(), text: String::new(), things: vec![Thing::Item(it_c)], cod: 0 }), code::REFUSED);
    // it can still use the merchant and sell to him
    w.ok(c, EReq::MerchantSell { hero: hc, what: Thing::Item(it_c) });
    w.verify();
}

#[test]
fn requests_are_rate_limited_per_hero() {
    let mut w = world("limit");
    let a = w.account("ann");
    let h = w.hero(a, "Annie", 5, false);
    let mut slow = 0;
    for _ in 0..(LIMIT_BURST + 5) {
        if matches!(w.call(a, EReq::MerchantList { hero: h }), Resp::Err { code: c, .. } if c == code::SLOW_DOWN) {
            slow += 1;
        }
    }
    assert_eq!(slow, 5);
    w.now += 10_000;
    assert!(matches!(w.call(a, EReq::MerchantList { hero: h }), Resp::Econ(_)));
    // another account's hero is not hers
    let b = w.account("bo");
    assert_eq!(w.code(b, EReq::MerchantList { hero: h }), code::NOT_YOURS);
}

#[test]
fn the_wire_round_trips() {
    let it = EItem { info: ItemInfo { id: 5, base: 7, gear_slot: 1, level: 12, rarity: 2, lines: vec![(0, 3), (2, 4)], sockets: 1, kind: 1, tab: 0, slot: 3, plus: 3, socketed: vec![2001] }, plus: 3, bound: false, socketed: [2001, 0] };
    let reqs = vec![
        EReq::MerchantList { hero: 3 },
        EReq::MerchantBuy { hero: 3, offer: 7, count: 2 },
        EReq::MerchantSell { hero: 3, what: Thing::Stack(1000, 9) },
        EReq::Buyback { hero: 3 },
        EReq::BuybackTake { hero: 3, entry: 9 },
        EReq::TradeInvite { hero: 3, with_name: "Bo".into() },
        EReq::TradeAccept { hero: 3, session: 4 },
        EReq::TradeOffer { hero: 3, session: 4, items: vec![1, 2], stacks: vec![(1, 5)] },
        EReq::TradeConfirm { hero: 3, session: 4, version: 6 },
        EReq::TradeCancel { hero: 3, session: 4 },
        EReq::TradeView { hero: 3, session: 4 },
        EReq::MarketList { hero: 3, what: Thing::Item(9), price: 77, hours: 24 },
        EReq::MarketSearch { hero: 3, q: Search { gear_slot: 255, rarity_min: 2, level_min: 1, level_max: 9, stack: 0, price_max: 55, offset: 40 } },
        EReq::MarketBuy { hero: 3, listing: 8 },
        EReq::MarketCancel { hero: 3, listing: 8 },
        EReq::MarketMine { hero: 3 },
        EReq::MarketPrices,
        EReq::LetterSend { hero: 3, to_name: "Bo".into(), text: "hi".into(), things: vec![Thing::Item(1), Thing::Stack(1, 2)], cod: 40 },
        EReq::Inbox { hero: 3 },
        EReq::Outbox { hero: 3 },
        EReq::LetterTake { hero: 3, letter: 5 },
        EReq::LetterRefuse { hero: 3, letter: 5 },
        EReq::LetterRecall { hero: 3, letter: 5 },
    ];
    for r in reqs {
        let (t, b) = Req::Econ(r.clone()).encode();
        assert_eq!(Req::decode(t, &b), Some(Req::Econ(r)));
    }
    let resps = vec![
        EResp::Ok,
        EResp::Offers(vec![Offer { id: 7, kind: 2, stack: 0, item: Some(it.clone()), price: 99, left: 2 }, Offer { id: 0, kind: 0, stack: 100, item: None, price: 5, left: 20 }]),
        EResp::Coin(77),
        EResp::Buybacks(vec![BuybackInfo { id: 3, item: it.clone(), price: 12, secs_left: 60 }]),
        EResp::Trade(TradeView { session: 4, state: 1, me: 1, other: 2, other_name: "Bo".into(), version: 3, lock_ms: 500, my_items: vec![it.clone()], my_stacks: vec![(1, 4)], their_items: vec![], their_stacks: vec![], my_ok: true, their_ok: false }),
        EResp::Listed { id: 4, fee: 2 },
        EResp::Listings(vec![ListingInfo { id: 4, seller: "Ann".into(), price: 100, expires: 5, item: Some(it.clone()), stack: None, mine: true }, ListingInfo { id: 5, seller: "Ann".into(), price: 100, expires: 5, item: None, stack: Some((1000, 4)), mine: false }]),
        EResp::Letters(vec![LetterInfo { id: 1, from: "A".into(), to: "B".into(), text: "t".into(), cod: 5, expires: 9, items: vec![it], stacks: vec![(1, 1)] }]),
        EResp::Prices(vec![ClassPrice { rarity: 2, band: 1, median: 400, n: 9 }]),
        EResp::Notice { kind: 1, a: 4, b: 940, text: "x".into() },
    ];
    for e in resps {
        for r in [Resp::Econ(e.clone()), Resp::EconPush(e.clone())] {
            let (t, b) = r.encode();
            assert_eq!(Resp::decode(t, &b), Some(r));
        }
    }
}

// ---- hand-to-hand trade, through real sockets (the pushes are part of it)

fn econ(c: &mut GatewayClient, r: EReq) -> std::result::Result<EResp, (u16, String)> {
    match c.call(Req::Econ(r)).unwrap() {
        Resp::Econ(e) => Ok(e),
        Resp::Err { code, msg } => Err((code, msg)),
        r => panic!("{r:?}"),
    }
}

fn view(r: std::result::Result<EResp, (u16, String)>) -> TradeView {
    match r {
        Ok(EResp::Trade(v)) => v,
        r => panic!("{r:?}"),
    }
}

fn pushed_trade(c: &mut GatewayClient) -> TradeView {
    let end = std::time::Instant::now() + Duration::from_secs(5);
    loop {
        if let Some(i) = c.pushes.iter().rposition(|p| matches!(p, Resp::EconPush(EResp::Trade(_)))) {
            let Some(Resp::EconPush(EResp::Trade(v))) = c.pushes.remove(i) else { unreachable!() };
            c.pushes.clear();
            return v;
        }
        assert!(std::time::Instant::now() < end, "no trade push");
        c.poll(Duration::from_millis(50)).unwrap();
    }
}

#[test]
fn a_trade_moves_nothing_until_both_confirm_the_same_offers() {
    let db = std::env::temp_dir().join(format!("realm-eco-{}-trade.db", std::process::id()));
    let _ = std::fs::remove_file(&db);
    let store = Arc::new(SqliteStore::open(&db).unwrap());
    let gw = Gateway::start(store.clone(), Config { dev_login: true, secret: 5, ..Config::default() });
    let l = realm_gateway::conn::listen(gw.clone(), "127.0.0.1:0").unwrap();
    let addr = l.addr.to_string();
    let mut ca = GatewayClient::connect_plain(&addr).unwrap();
    let mut cb = GatewayClient::connect_plain(&addr).unwrap();
    let Resp::Login { account: a } = ca.login("ann").unwrap() else { panic!() };
    let Resp::Login { account: b } = cb.login("bo").unwrap() else { panic!() };
    let mk = |c: &mut GatewayClient, n: &str| match c.call(Req::CreateHero { name: n.into(), race: 1, class: 1, look: 0, self_found: false }).unwrap() {
        Resp::HeroCreated(id) => id,
        r => panic!("{r:?}"),
    };
    let (ha, hb) = (mk(&mut ca, "Annie"), mk(&mut cb, "Bobby"));
    let _ = (a, b);
    let spec = ItemSpec { base: 7, gear_slot: 0, item_level: 1, rarity: 1, lines: vec![(0, 3)], sockets: 0, plus: 0, bound: false };
    let ia = store.mint(sys(), Dest::bag(ha), spec.clone(), "drop").unwrap().0;
    let ib = store.mint(sys(), Dest::bag(hb), spec.clone(), "drop").unwrap().0;
    store.stack_credit(sys(), Owner::bag(hb), StackKind::COIN, 500, true, "drop").unwrap();
    // not in a town together: no trade
    assert_eq!(econ(&mut ca, EReq::TradeInvite { hero: ha, with_name: "Bobby".into() }).unwrap_err().0, code::BAD_REQUEST);
    assert!(matches!(ca.call(Req::EnterTown { hero: ha }).unwrap(), Resp::Town { .. }));
    assert!(matches!(cb.call(Req::EnterTown { hero: hb }).unwrap(), Resp::Town { .. }));
    let v = view(econ(&mut ca, EReq::TradeInvite { hero: ha, with_name: "Bobby".into() }));
    assert_eq!(v.state, 0);
    let end = std::time::Instant::now() + Duration::from_secs(5);
    while !cb.pushes.iter().any(|p| matches!(p, Resp::EconPush(EResp::Notice { kind, .. }) if *kind == notice::INVITED)) {
        assert!(std::time::Instant::now() < end, "no invitation");
        cb.poll(Duration::from_millis(50)).unwrap();
    }
    let s = v.session;
    view(econ(&mut cb, EReq::TradeAccept { hero: hb, session: s }));
    let v = view(econ(&mut ca, EReq::TradeOffer { hero: ha, session: s, items: vec![ia], stacks: vec![] }));
    // she cannot offer his item, nor one she does not have coin for
    assert_eq!(econ(&mut ca, EReq::TradeOffer { hero: ha, session: s, items: vec![ib], stacks: vec![] }).unwrap_err().0, code::NOT_YOURS);
    assert_eq!(econ(&mut ca, EReq::TradeOffer { hero: ha, session: s, items: vec![ia], stacks: vec![(1, 5)] }).unwrap_err().0, code::INSUFFICIENT);
    let seen_by_b = pushed_trade(&mut cb);
    assert_eq!(seen_by_b.their_items.len(), 1, "he sees what she offers");
    let vb = view(econ(&mut cb, EReq::TradeOffer { hero: hb, session: s, items: vec![ib], stacks: vec![(1, 200)] }));
    let _ = pushed_trade(&mut ca);
    // a confirm of a stale version is refused; one too soon after a change is refused
    assert_eq!(econ(&mut ca, EReq::TradeConfirm { hero: ha, session: s, version: v.version }).unwrap_err().0, code::BAD_REQUEST);
    assert_eq!(econ(&mut ca, EReq::TradeConfirm { hero: ha, session: s, version: vb.version }).unwrap_err().0, code::BAD_REQUEST, "too soon");
    std::thread::sleep(Duration::from_millis(1700));
    // half a confirm moves nothing
    let h = view(econ(&mut ca, EReq::TradeConfirm { hero: ha, session: s, version: vb.version }));
    assert!(h.my_ok && !h.their_ok);
    assert_eq!(store.item(ia).unwrap().unwrap().place.owner, ha);
    // a change after her confirm clears it
    let vc = view(econ(&mut cb, EReq::TradeOffer { hero: hb, session: s, items: vec![ib], stacks: vec![(1, 100)] }));
    let seen = pushed_trade(&mut ca);
    assert!(!seen.my_ok, "her confirm is gone");
    std::thread::sleep(Duration::from_millis(1700));
    view(econ(&mut ca, EReq::TradeConfirm { hero: ha, session: s, version: vc.version }));
    let done = view(econ(&mut cb, EReq::TradeConfirm { hero: hb, session: s, version: vc.version }));
    assert_eq!(done.state, 2);
    let ia_now = store.item(ia).unwrap().unwrap();
    let ib_now = store.item(ib).unwrap().unwrap();
    assert_eq!((ia_now.place.owner, ib_now.place.owner), (hb, ha), "both moved");
    assert_eq!(ia_now.origin_hero, Some(ha), "the origin is kept");
    assert_eq!(store.stack(Owner::bag(ha), StackKind::COIN).unwrap(), 100);
    assert_eq!(store.stack(Owner::bag(hb), StackKind::COIN).unwrap(), 400);
    let r = store.verify().unwrap();
    assert!(r.ok(), "{:?}", r.problems);
    // a cancelled trade moves nothing; leaving the town cancels
    let v = view(econ(&mut ca, EReq::TradeInvite { hero: ha, with_name: "Bobby".into() }));
    view(econ(&mut cb, EReq::TradeAccept { hero: hb, session: v.session }));
    view(econ(&mut ca, EReq::TradeOffer { hero: ha, session: v.session, items: vec![ib], stacks: vec![] }));
    assert_eq!(ca.call(Req::LeaveTown).unwrap(), Resp::Ok);
    let mut seen = pushed_trade(&mut cb);
    while seen.state != 3 {
        seen = pushed_trade(&mut cb);
    }
    assert_eq!(seen.state, 3);
    assert_eq!(store.item(ib).unwrap().unwrap().place.owner, ha);
    gw.shutdown();
    store.close();
    for s in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{s}", db.display()));
    }
}

#[test]
fn a_listing_may_not_ask_more_than_ten_times_the_value() {
    let w = world("cap");
    let a = w.account("ann");
    let h = w.hero(a, "Annie", 12, false);
    w.coin(h, 100_000);
    let it = w.item(h, 12, 0);
    let cap = item_price_cap(&w.store.item(it).unwrap().unwrap().spec);
    assert_eq!(cap, (5 + 3 * 12) * 10);
    assert_eq!(w.code(a, EReq::MarketList { hero: h, what: Thing::Item(it), price: cap + 1, hours: 24 }), code::BAD_REQUEST);
    w.ok(a, EReq::MarketList { hero: h, what: Thing::Item(it), price: cap, hours: 24 });
    // a stack: the reference value of the pieces x 10
    w.store.stack_credit(sys(), Owner::bag(h), StackKind::material(0), 10, true, "drop").unwrap();
    let each = stack_ref(1000).unwrap();
    assert_eq!(w.code(a, EReq::MarketList { hero: h, what: Thing::Stack(1000, 10), price: each * 100 + 1, hours: 24 }), code::BAD_REQUEST);
    w.ok(a, EReq::MarketList { hero: h, what: Thing::Stack(1000, 10), price: each * 100, hours: 24 });
    w.verify();
}
