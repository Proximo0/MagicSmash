//! Homes and the shared places (job H1) through real sockets: streets of 24 plots bought or rented with coin from
//! the bag, furniture crafted and placed on the grid (an item moves, never copies), the visiting rules, the
//! guestbook, the training yard, campfires and the market square. The proof: 24 houses on a street visited by 200
//! bots, then the store's verify and a count of every item.

use realm_gateway::client::GatewayClient;
use realm_gateway::gateway::{Config, Gateway};
use realm_gateway::homes::place::*;
use realm_gateway::homes::plots::{BUY_BASE, RENT_WEEK};
use realm_gateway::homes::{HReq, HResp};
use realm_gateway::proto::*;
use realm_gateway::social::{SReq, SResp};
use realm_store::*;
use std::collections::BTreeSet;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

struct World {
    gw: Arc<Gateway>,
    store: Arc<SqliteStore>,
    addr: String,
    _l: realm_gateway::conn::Listener,
    db: std::path::PathBuf,
    n: AtomicU64,
}

impl Drop for World {
    fn drop(&mut self) {
        self.gw.shutdown();
        for s in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{}{s}", self.db.display()));
        }
    }
}

fn world(name: &str) -> World {
    let db = std::env::temp_dir().join(format!("realm-homes-{}-{name}.db", std::process::id()));
    for s in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{s}", db.display()));
    }
    let store = Arc::new(SqliteStore::open(&db).unwrap());
    let gw = Gateway::start(store.clone(), Config { dev_login: true, secret: 9, ..Config::default() });
    let l = realm_gateway::conn::listen(gw.clone(), "127.0.0.1:0").unwrap();
    World { gw, store, addr: l.addr.to_string(), _l: l, db, n: AtomicU64::new(1) }
}

impl World {
    fn sys(&self) -> Meta {
        Meta::system(0x4801 << 100 | self.n.fetch_add(1, Ordering::Relaxed) as u128, 1)
    }
    fn give(&self, hero: i64, kind: StackKind, n: u64) {
        self.store.stack_credit(self.sys(), Owner::bag(hero), kind, n, true, "grant").unwrap();
    }
    fn coin(&self, hero: i64) -> u64 {
        self.store.stack(Owner::bag(hero), StackKind::COIN).unwrap()
    }
}

struct P {
    c: GatewayClient,
    hero: i64,
    account: i64,
    name: String,
}

fn player(w: &World, who: &str) -> P {
    let mut c = GatewayClient::connect_plain(&w.addr).unwrap();
    let Resp::Login { account } = c.login(who).unwrap() else { panic!() };
    let name = format!("H{who}");
    let Resp::HeroCreated(hero) = c.call(Req::CreateHero { name: name.clone(), race: 1, class: 1, look: 0, self_found: false }).unwrap() else { panic!() };
    assert!(matches!(c.call(Req::EnterTown { hero }).unwrap(), Resp::Town { .. }));
    P { c, hero, account, name }
}

fn call(p: &mut P, q: HReq) -> Resp {
    p.c.call(Req::Home(q)).unwrap()
}

fn home(p: &mut P, q: HReq) -> HResp {
    match call(p, q.clone()) {
        Resp::Home(h) => h,
        r => panic!("{q:?} -> {r:?}"),
    }
}

fn code_of(r: Resp) -> u16 {
    match r {
        Resp::Err { code, .. } => code,
        r => panic!("expected an error, got {r:?}"),
    }
}

fn go(p: &mut P, kind: u8, arg: u32) -> Resp {
    let h = p.hero;
    call(p, HReq::Go { hero: h, kind, arg })
}

fn walk_in(p: &mut P, plot: u32) -> Resp {
    go(p, STREET, street_of(plot));
    go(p, HOUSE, plot)
}

fn rent(p: &mut P, plot: u32, weeks: u8) -> Resp {
    let h = p.hero;
    go(p, STREET, street_of(plot));
    call(p, HReq::Rent { hero: h, street: street_of(plot), plot: index_of(plot) as u8, weeks })
}

fn craft(w: &World, p: &mut P, kind: u16) -> i64 {
    let h = p.hero;
    match home(p, HReq::Craft { hero: h, kind }) {
        HResp::Crafted(i) => {
            assert!(w.store.item(i.id).unwrap().is_some());
            i.id
        }
        r => panic!("{r:?}"),
    }
}

fn stock(w: &World, p: &P) {
    w.give(p.hero, StackKind::COIN, 3_000);
    w.give(p.hero, StackKind::material(1), 20);
    w.give(p.hero, StackKind::material(2), 20);
    w.give(p.hero, StackKind::material(10), 2);
}

/// Every item an account has anywhere it can keep furniture: the hero's bag and the house place.
fn things(w: &World, p: &P) -> BTreeSet<i64> {
    let mut s: BTreeSet<i64> = w.store.items_at(PlaceKind::Bag, p.hero).unwrap().iter().map(|i| i.id).collect();
    s.extend(w.store.items_at(PlaceKind::House, p.account).unwrap().iter().map(|i| i.id));
    s
}

#[test]
fn a_street_of_24_houses_is_visited_by_200_bots_and_no_item_is_copied_or_lost() {
    let w = world("street");
    // 24 owners: twelve rent a plot, twelve buy one; each crafts a chair, a table and a trophy plaque and places them.
    let mut owners: Vec<P> = Vec::new();
    for i in 0..24u32 {
        let mut p = player(&w, &format!("own{i}"));
        stock(&w, &mut p);
        w.give(p.hero, StackKind::COIN, 130_000);
        let h = p.hero;
        go(&mut p, STREET, 1);
        let r = if i < 12 {
            call(&mut p, HReq::Rent { hero: h, street: 1, plot: i as u8, weeks: 2 })
        } else {
            call(&mut p, HReq::Buy { hero: h, street: 1, plot: i as u8 })
        };
        assert!(matches!(r, Resp::Home(HResp::Paid { plot, .. }) if plot == i), "{r:?}");
        owners.push(p);
    }
    // The street is full enough that a second one is open.
    let h0 = owners[0].hero;
    let Resp::Home(HResp::Streets { open, taken, .. }) = call(&mut owners[0], HReq::Streets { hero: h0 }) else { panic!() };
    assert_eq!((open, taken), (2, vec![24, 0]));
    // Ten of the bought houses and the rest are open; four are for friends, four are locked.
    let mut before: Vec<BTreeSet<i64>> = Vec::new();
    for (i, p) in owners.iter_mut().enumerate() {
        let h = p.hero;
        assert!(matches!(walk_in(p, i as u32), Resp::Town { .. }));
        let a = craft(&w, p, 0);
        let b = craft(&w, p, 4);
        let t = craft(&w, p, realm_gateway::homes::catalogue::TROPHY_CRAFT);
        for (k, item) in [a, b, t].into_iter().enumerate() {
            let r = home(p, HReq::Place { hero: h, item, cell: (k * 11) as u16 });
            assert_eq!(r, HResp::Moved { item, house: true, cell: (k * 11) as u16 });
        }
        let rule = match i {
            16..=19 => 1,
            20..=23 => 3,
            _ => 0,
        };
        assert_eq!(home(p, HReq::Rule { hero: h, rule }), HResp::Ok);
        assert_eq!(home(p, HReq::Name { hero: h, name: format!("House {i}") }), HResp::Ok);
        // Pick one up and put it back in another cell: the same item, once.
        let HResp::Moved { house: false, .. } = home(p, HReq::Pickup { hero: h, item: a }) else { panic!() };
        assert_eq!(home(p, HReq::Place { hero: h, item: a, cell: 55 }), HResp::Moved { item: a, house: true, cell: 55 });
        assert_eq!(home(p, HReq::Move { hero: h, item: a, cell: 56 }), HResp::Moved { item: a, house: true, cell: 56 });
        before.push(things(&w, p));
        assert_eq!(before[i].len(), 3, "three things, none made twice");
    }

    // 200 bots walk the street.
    let visited = std::sync::atomic::AtomicU32::new(0);
    let refused = std::sync::atomic::AtomicU32::new(0);
    std::thread::scope(|s| {
        for k in 0..200u32 {
            let (w, visited, refused) = (&w, &visited, &refused);
            s.spawn(move || {
                let mut p = player(w, &format!("bot{k}"));
                let plot = k % 24;
                let h = p.hero;
                assert!(matches!(go(&mut p, STREET, 1), Resp::Town { .. }));
                let Resp::Home(HResp::Street { plots, .. }) = call(&mut p, HReq::Street { hero: h, street: 1 }) else { panic!() };
                assert_eq!(plots.iter().filter(|x| x.status != 0).count(), 24);
                assert_eq!(plots[plot as usize].name, format!("House {plot}"));
                match go(&mut p, HOUSE, plot) {
                    Resp::Town { members, .. } => {
                        assert!(plot < 16, "only open houses let a stranger in");
                        assert!(!members.is_empty());
                        let HResp::House(v) = home(&mut p, HReq::House { hero: h }) else { panic!() };
                        assert_eq!((v.items.len(), v.mine, v.plot), (3, false, plot));
                        assert!(v.items.iter().all(|i| i.kind == PlaceKind::House as u8));
                        assert_eq!(home(&mut p, HReq::Sign { hero: h, text: format!("lovely, from bot {k}") }), HResp::Ok);
                        assert!(matches!(go(&mut p, PLAZA, 0), Resp::Town { .. }));
                        visited.fetch_add(1, Ordering::Relaxed);
                    }
                    Resp::Err { code, .. } => {
                        assert!(plot >= 16, "an open house refused a visitor (code {code})");
                        assert_eq!(code, code::REFUSED);
                        refused.fetch_add(1, Ordering::Relaxed);
                    }
                    r => panic!("{r:?}"),
                }
            });
        }
    });
    // Houses 0..16 had 9 or 8 visitors each: (200 = 24 x 8 + 8).
    let expect_in: u32 = (0..200u32).filter(|k| k % 24 < 16).count() as u32;
    assert_eq!((visited.load(Ordering::Relaxed), refused.load(Ordering::Relaxed)), (expect_in, 200 - expect_in));
    // The owners hear of it, the guestbooks hold the lines, and the things are where they were.
    for (i, p) in owners.iter_mut().enumerate() {
        let h = p.hero;
        assert!(matches!(call(p, HReq::Where { hero: h }), Resp::Home(HResp::Where { kind: HOUSE, arg }) if arg == i as u32));
        let HResp::House(v) = home(p, HReq::House { hero: h }) else { panic!() };
        let want = if i < 16 { (0..200u32).filter(|k| k % 24 == i as u32).count() } else { 0 };
        assert_eq!(v.book.len(), want, "house {i}");
        assert!(v.mine);
        assert_eq!(things(&w, p), before[i], "nothing copied, nothing lost in house {i}");
        let mut seen = 0;
        while p.c.pushes.iter().any(|r| matches!(r, Resp::HomePush(HResp::Notice { kind: 1, .. }))) {
            p.c.pushes.pop_front();
            seen += 1;
        }
        let _ = seen;
    }
    let report = w.store.verify().unwrap();
    assert_eq!(report.problems, Vec::<String>::new());
    // Every piece of furniture exists once and sits in exactly one place.
    let mut all = BTreeSet::new();
    for p in &owners {
        for id in things(&w, p) {
            assert!(all.insert(id), "item {id} in two places");
            assert_eq!(w.store.item(id).unwrap().unwrap().place.owner == p.account || w.store.item(id).unwrap().unwrap().place.owner == p.hero, true);
        }
    }
    assert_eq!(all.len(), 72);
}

#[test]
fn plots_cost_coin_from_the_bag_one_house_to_an_account_and_a_rented_house_has_one_room() {
    let w = world("plots");
    let mut ann = player(&w, "ann");
    let mut bob = player(&w, "bob");
    let (ha, hb) = (ann.hero, bob.hero);
    stock(&w, &ann);
    stock(&w, &bob);
    w.give(ha, StackKind::COIN, 100_000);
    let c0 = w.coin(ha);
    // She must stand on the street.
    assert_eq!(code_of(call(&mut ann, HReq::Buy { hero: ha, street: 1, plot: 10 })), code::BAD_REQUEST);
    go(&mut ann, STREET, 1);
    assert_eq!(code_of(go(&mut ann, STREET, 1)), code::BAD_REQUEST, "already there");
    assert_eq!(code_of(go(&mut ann, STREET, 2)), code::INVALID, "a street not yet open");
    assert_eq!(code_of(go(&mut ann, HOUSE, 10)), code::MISSING, "no one lives there");
    assert_eq!(call(&mut ann, HReq::Buy { hero: ha, street: 1, plot: 10 }), Resp::Home(HResp::Paid { plot: 10, until: 0, coin: BUY_BASE }));
    assert_eq!(w.coin(ha), c0 - BUY_BASE);
    assert_eq!(code_of(call(&mut ann, HReq::Buy { hero: ha, street: 1, plot: 11 })), code::BUSY, "one house to an account");
    assert_eq!(code_of(call(&mut ann, HReq::Renew { hero: ha, weeks: 1 })), code::INVALID, "a bought house needs no rent");
    // Bob cannot take hers, and a plot he cannot pay for costs nothing.
    go(&mut bob, STREET, 1);
    assert_eq!(code_of(call(&mut bob, HReq::Buy { hero: hb, street: 1, plot: 10 })), code::BUSY);
    let c1 = w.coin(hb);
    assert_eq!(code_of(call(&mut bob, HReq::Buy { hero: hb, street: 1, plot: 5 })), code::INSUFFICIENT);
    assert_eq!(w.coin(hb), c1);
    assert_eq!(code_of(call(&mut bob, HReq::Rent { hero: hb, street: 1, plot: 23, weeks: 5 })), code::INVALID);
    let Resp::Home(HResp::Paid { plot: 23, until, coin }) = call(&mut bob, HReq::Rent { hero: hb, street: 1, plot: 23, weeks: 2 }) else { panic!() };
    assert_eq!(coin, RENT_WEEK * 70 / 100 * 2);
    assert!(until > 0);
    assert_eq!(w.coin(hb), c1 - coin);
    assert_eq!(code_of(call(&mut bob, HReq::Rent { hero: hb, street: 1, plot: 23, weeks: 3 })), code::INVALID, "more than four weeks ahead");
    assert!(matches!(call(&mut bob, HReq::Renew { hero: hb, weeks: 2 }), Resp::Home(HResp::Paid { .. })));
    // The street shows who lives where.
    let Resp::Home(HResp::Street { plots, .. }) = call(&mut bob, HReq::Street { hero: hb, street: 1 }) else { panic!() };
    assert_eq!((plots[10].owner.as_str(), plots[10].status, plots[23].status, plots[0].status), ("Hann", 1, 2, 0));
    // Rooms: both rooms for the owner, the first only for the renter.
    assert!(matches!(walk_in(&mut ann, 10), Resp::Town { .. }));
    assert!(matches!(walk_in(&mut bob, 23), Resp::Town { .. }));
    let (ca, cb) = (craft(&w, &mut ann, 0), craft(&w, &mut bob, 0));
    assert_eq!(home(&mut ann, HReq::Place { hero: ha, item: ca, cell: 150 }), HResp::Moved { item: ca, house: true, cell: 150 });
    assert_eq!(code_of(call(&mut bob, HReq::Place { hero: hb, item: cb, cell: 150 })), code::REFUSED);
    assert_eq!(code_of(call(&mut bob, HReq::Place { hero: hb, item: cb, cell: 200 })), code::BAD_REQUEST);
    assert_eq!(home(&mut bob, HReq::Place { hero: hb, item: cb, cell: 99 }), HResp::Moved { item: cb, house: true, cell: 99 });
    // A cell holds one thing; a house is not a bag: gear does not go in.
    let cb2 = craft(&w, &mut bob, 0);
    assert_eq!(code_of(call(&mut bob, HReq::Place { hero: hb, item: cb2, cell: 99 })), code::INVALID);
    let gear = w.store.mint(w.sys(), Dest::bag(hb), ItemSpec { base: 1, gear_slot: 1, item_level: 1, rarity: 0, lines: vec![(0, 1)], sockets: 0, plus: 0, bound: false }, "grant").unwrap().0;
    assert_eq!(code_of(call(&mut bob, HReq::Place { hero: hb, item: gear, cell: 3 })), code::BAD_REQUEST);
    // She cannot place from, or into, another's house, and cannot pick up what is not hers.
    assert_eq!(code_of(call(&mut bob, HReq::Pickup { hero: hb, item: ca })), code::NOT_YOURS);
    assert_eq!(code_of(call(&mut ann, HReq::Place { hero: ha, item: cb2, cell: 3 })), code::NOT_YOURS);
    // The carpenter wants her materials and coin; a refused craft takes nothing.
    let poor = player(&w, "poor");
    let mut poor = poor;
    let hp = poor.hero;
    let coin_before = w.coin(hp);
    assert_eq!(code_of(call(&mut poor, HReq::Craft { hero: hp, kind: 0 })), code::INSUFFICIENT);
    assert_eq!(code_of(call(&mut poor, HReq::Craft { hero: hp, kind: 77 })), code::BAD_REQUEST);
    assert_eq!(w.coin(hp), coin_before);
    w.give(hp, StackKind::material(1), 4);
    assert_eq!(code_of(call(&mut poor, HReq::Craft { hero: hp, kind: 0 })), code::INSUFFICIENT, "the coin is short");
    assert_eq!(w.store.stack(Owner::bag(hp), StackKind::material(1)).unwrap(), 4, "and the material was not kept");
    // Letting go of a house keeps the things: they can be picked up from anywhere in town.
    assert_eq!(home(&mut ann, HReq::Release { hero: ha }), HResp::Ok);
    go(&mut ann, PLAZA, 0);
    assert_eq!(home(&mut ann, HReq::Pickup { hero: ha, item: ca }), HResp::Moved { item: ca, house: false, cell: 0 });
    assert_eq!(w.store.item(ca).unwrap().unwrap().place.kind, PlaceKind::Bag);
    assert_eq!(w.store.verify().unwrap().problems, Vec::<String>::new());
}

fn befriend(a: &mut P, b: &mut P) {
    let (ha, hb) = (a.hero, b.hero);
    let name = b.name.clone();
    assert_eq!(a.c.call(Req::Social(SReq::FriendAdd { hero: ha, name })).unwrap(), Resp::Ok);
    assert_eq!(b.c.call(Req::Social(SReq::FriendAnswer { hero: hb, from: a.account, accept: true })).unwrap(), Resp::Ok);
}

#[test]
fn who_may_visit_follows_the_rule_friends_guild_locked_and_ignores() {
    let w = world("rules");
    let mut ann = player(&w, "ann");
    let mut bob = player(&w, "bob");
    let mut cy = player(&w, "cy");
    let mut di = player(&w, "di");
    let ha = ann.hero;
    stock(&w, &ann);
    assert!(matches!(rent(&mut ann, 3, 1), Resp::Home(HResp::Paid { .. })));
    // The owner's own door is always open to her; an open house takes anyone.
    assert!(matches!(go(&mut ann, HOUSE, 3), Resp::Town { .. }));
    assert!(matches!(walk_in(&mut bob, 3), Resp::Town { .. }));
    assert!(matches!(go(&mut bob, PLAZA, 0), Resp::Town { .. }));
    // Locked.
    assert_eq!(home(&mut ann, HReq::Rule { hero: ha, rule: 3 }), HResp::Ok);
    assert_eq!(code_of(go(&mut bob, HOUSE, 3)), code::REFUSED);
    assert_eq!(code_of(call(&mut ann, HReq::Rule { hero: ha, rule: 4 })), code::INVALID);
    // Friends: only once she has said yes.
    assert_eq!(home(&mut ann, HReq::Rule { hero: ha, rule: 1 }), HResp::Ok);
    assert_eq!(code_of(go(&mut bob, HOUSE, 3)), code::REFUSED);
    befriend(&mut ann, &mut bob);
    assert!(matches!(go(&mut bob, HOUSE, 3), Resp::Town { .. }));
    // Guild: members of her guild, not friends.
    assert_eq!(home(&mut ann, HReq::Rule { hero: ha, rule: 2 }), HResp::Ok);
    go(&mut bob, PLAZA, 0);
    assert_eq!(code_of(go(&mut bob, HOUSE, 3)), code::REFUSED, "a friend is not a guildmate");
    let Resp::Social(SResp::GuildCreated(_)) = ann.c.call(Req::Social(SReq::GuildCreate { hero: ha, name: "The Lantern Club".into() })).unwrap() else { panic!() };
    assert_eq!(ann.c.call(Req::Social(SReq::GuildInvite { hero: ha, name: cy.name.clone() })).unwrap(), Resp::Ok);
    let hc = cy.hero;
    let Some(gid) = cy.c.wait_push(std::time::Duration::from_secs(2), |r| match r {
        Resp::SocialPush(realm_gateway::social::SPush::GuildInvite { guild, .. }) => Some(*guild),
        _ => None,
    }).unwrap() else { panic!("no invitation") };
    assert!(matches!(cy.c.call(Req::Social(SReq::GuildAnswer { hero: hc, guild: gid, accept: true })).unwrap(), Resp::Social(SResp::Guild(Some(_)))));
    assert!(matches!(walk_in(&mut cy, 3), Resp::Town { .. }));
    assert_eq!(code_of(walk_in(&mut di, 3)), code::REFUSED);
    // The guild hall: members only, one room for them.
    assert!(matches!(go(&mut ann, GUILD_HALL, 0), Resp::Town { .. }));
    assert_eq!(code_of(go(&mut di, GUILD_HALL, 0)), code::REFUSED);
    // An ignored visitor is turned away from an open house.
    assert_eq!(home(&mut ann, HReq::Rule { hero: ha, rule: 0 }), HResp::Ok);
    assert!(matches!(walk_in(&mut di, 3), Resp::Town { .. }));
    go(&mut di, PLAZA, 0);
    assert_eq!(ann.c.call(Req::Social(SReq::Ignore { hero: ha, name: di.name.clone(), on: true })).unwrap(), Resp::Ok);
    assert_eq!(code_of(go(&mut di, HOUSE, 3)), code::REFUSED);
    // Signing: the owner does not sign her own book; one line each ten minutes; nothing outside a house.
    let hd = di.hero;
    assert_eq!(code_of(call(&mut di, HReq::Sign { hero: hd, text: "x".into() })), code::BAD_REQUEST, "not in a house");
    let hb = bob.hero;
    assert!(matches!(go(&mut bob, HOUSE, 3), Resp::Town { .. }));
    assert_eq!(home(&mut bob, HReq::Sign { hero: hb, text: "a lovely hearth".into() }), HResp::Ok);
    assert_eq!(code_of(call(&mut bob, HReq::Sign { hero: hb, text: "again".into() })), code::SLOW_DOWN);
    assert_eq!(code_of(call(&mut ann, HReq::Sign { hero: ha, text: "mine".into() })), code::BAD_REQUEST);
    // The owner reads it and wipes it.
    assert!(matches!(walk_in(&mut ann, 3), Resp::Town { .. }));
    let HResp::House(v) = home(&mut ann, HReq::House { hero: ha }) else { panic!() };
    assert_eq!((v.book.len(), v.book[0].name.as_str()), (1, "Hbob"));
    assert_eq!(home(&mut ann, HReq::Wipe { hero: ha, entry: v.book[0].id }), HResp::Ok);
    assert_eq!(code_of(call(&mut ann, HReq::Wipe { hero: ha, entry: v.book[0].id })), code::MISSING);
    // The owner was told of each visit.
    assert!(ann.c.wait_push(std::time::Duration::from_secs(1), |r| matches!(r, Resp::HomePush(HResp::Notice { kind: 0, .. })).then_some(())).unwrap().is_some());
}

#[test]
fn a_full_house_keeps_the_door_shut_and_rooms_of_other_places_do_not_mix() {
    let w = world("full");
    let mut ann = player(&w, "ann");
    stock(&w, &ann);
    assert!(matches!(rent(&mut ann, 0, 1), Resp::Home(HResp::Paid { .. })));
    assert!(matches!(go(&mut ann, HOUSE, 0), Resp::Town { .. }));
    let mut guests = Vec::new();
    for k in 0..HOUSE_VISITORS - 1 {
        let mut g = player(&w, &format!("g{k}"));
        assert!(matches!(walk_in(&mut g, 0), Resp::Town { .. }), "guest {k}");
        guests.push(g);
    }
    let mut late = player(&w, "late");
    assert_eq!(code_of(walk_in(&mut late, 0)), code::FULL);
    // She is still on the street, in a room with no guests of the house.
    let h = late.hero;
    assert!(matches!(call(&mut late, HReq::Where { hero: h }), Resp::Home(HResp::Where { kind: STREET, arg: 1 })));
    // A guest who leaves makes room.
    assert!(matches!(go(&mut guests[0], PLAZA, 0), Resp::Town { .. }));
    assert!(matches!(go(&mut late, HOUSE, 0), Resp::Town { .. }));
}

#[test]
fn the_yard_reports_damage_the_tavern_market_and_campfires_are_places() {
    let w = world("places");
    let mut ann = player(&w, "ann");
    let ha = ann.hero;
    // Tavern, market, yard, plaza: each a place.
    for (kind, name) in [(TAVERN, "tavern"), (MARKET, "market"), (YARD, "yard")] {
        assert!(matches!(go(&mut ann, kind, 0), Resp::Town { .. }), "{name}");
        assert!(matches!(call(&mut ann, HReq::Where { hero: ha }), Resp::Home(HResp::Where { kind: k, .. }) if k == kind));
    }
    // The dummy: one strike answers with damage and a dps; a second at once is too fast; the board keeps the best.
    let HResp::Strike { damage, total, count, .. } = home(&mut ann, HReq::Strike { hero: ha }) else { panic!() };
    assert!(damage > 0);
    assert_eq!((total, count), (damage as u64, 1));
    assert_eq!(code_of(call(&mut ann, HReq::Strike { hero: ha })), code::SLOW_DOWN);
    assert_eq!(home(&mut ann, HReq::YardBoard { hero: ha }), HResp::Board(vec![]), "one blow is no record");
    // Away from the yard there is no dummy.
    go(&mut ann, TAVERN, 0);
    assert_eq!(code_of(call(&mut ann, HReq::Strike { hero: ha })), code::BAD_REQUEST);
    // The market square's stalls: a listing from another hero shows as a stall.
    let mut bob = player(&w, "bob");
    let hb = bob.hero;
    w.give(hb, StackKind::COIN, 100);
    let it = w.store.mint(w.sys(), Dest::bag(hb), ItemSpec { base: 1, gear_slot: 1, item_level: 3, rarity: 1, lines: vec![(0, 2)], sockets: 0, plus: 0, bound: false }, "grant").unwrap().0;
    let r = bob.c.call(Req::Econ(realm_gateway::economy::wire::EReq::MarketList { hero: hb, what: Thing::Item(it), price: 12, hours: 12 })).unwrap();
    assert!(matches!(r, Resp::Econ(realm_gateway::economy::wire::EResp::Listed { .. })), "{r:?}");
    assert_eq!(code_of(call(&mut ann, HReq::Stalls { hero: ha, offset: 0 })), code::BAD_REQUEST, "the stalls stand in the market");
    go(&mut ann, MARKET, 0);
    let HResp::Stalls(v) = home(&mut ann, HReq::Stalls { hero: ha, offset: 0 }) else { panic!() };
    assert_eq!(v.len(), 1);
    assert_eq!((v[0].seller.as_str(), v[0].listings, v[0].cheapest), ("Hbob", 1, 12));
    // A fire: she arrives a little way from it; walking to it she may sit, away from it she may not.
    go(&mut ann, TAVERN, 0);
    let mut sat = None;
    // The tavern hearth is in the middle of the room; walk toward it until she is close.
    let south = realm_core::DIRS.iter().position(|d| *d == (0, 1)).unwrap() as u8;
    let east = realm_core::DIRS.iter().position(|d| *d == (1, 0)).unwrap() as u8;
    assert_eq!(code_of(call(&mut ann, HReq::Sit { hero: ha })), code::BAD_REQUEST, "no fire near her");
    ann.c.call(Req::TownInput { dir: south }).unwrap();
    for step in 0..60 {
        std::thread::sleep(std::time::Duration::from_millis(150));
        if step % 2 == 1 {
            ann.c.call(Req::TownInput { dir: east }).unwrap();
        } else {
            ann.c.call(Req::TownInput { dir: south }).unwrap();
        }
        if let Resp::Home(HResp::Rest { sitting: true, .. }) = call(&mut ann, HReq::Sit { hero: ha }) {
            sat = Some(step);
            break;
        }
    }
    assert!(sat.is_some(), "she reached the fire");
    ann.c.call(Req::TownInput { dir: 0 }).unwrap();
    let HResp::Rest { sitting, pct, .. } = home(&mut ann, HReq::Status { hero: ha }) else { panic!() };
    assert!(sitting);
    assert_eq!(pct, 0, "a minute is needed");
    let HResp::Rest { sitting, .. } = home(&mut ann, HReq::Stand { hero: ha }) else { panic!() };
    assert!(!sitting);
    assert_eq!(w.gw.homes.rested_pct(ha, realm_gateway::gateway::now_ms()), 0);
    // Catalogue: 24 pieces and 8 plaques.
    let HResp::Catalogue(c) = home(&mut ann, HReq::Catalogue { hero: ha }) else { panic!() };
    assert_eq!(c.len(), 32);
}

#[test]
fn furniture_is_not_worn_and_a_plaque_is_neither_sold_nor_listed() {
    let w = world("wear");
    let mut ann = player(&w, "ann");
    let h = ann.hero;
    stock(&w, &ann);
    w.give(h, StackKind::COIN, 1_000);
    let chair = craft(&w, &mut ann, 0);
    let plaque = craft(&w, &mut ann, realm_gateway::homes::catalogue::TROPHY_CRAFT);
    for it in [chair, plaque] {
        assert_eq!(code_of(ann.c.call(Req::Equip { hero: h, item: it }).unwrap()), code::BAD_REQUEST);
        assert_eq!(w.store.item(it).unwrap().unwrap().place.kind, PlaceKind::Bag);
    }
    assert_eq!(code_of(ann.c.call(Req::Sell { hero: h, item: plaque }).unwrap()), code::BAD_REQUEST);
    let sell = Req::Econ(realm_gateway::economy::wire::EReq::MerchantSell { hero: h, what: Thing::Item(plaque) });
    assert_eq!(code_of(ann.c.call(sell).unwrap()), code::BAD_REQUEST);
    let list = Req::Econ(realm_gateway::economy::wire::EReq::MarketList { hero: h, what: Thing::Item(plaque), price: 5, hours: 12 });
    assert_eq!(code_of(ann.c.call(list).unwrap()), code::BAD_REQUEST);
    assert_eq!(w.store.item(plaque).unwrap().unwrap().place.kind, PlaceKind::Bag);
}
