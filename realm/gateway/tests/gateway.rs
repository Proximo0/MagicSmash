//! The gateway through real sockets: login, characters, towns and chat, field tickets, the bank, mail, spends and
//! the smith, each through the store's own rules.

use realm_gateway::client::GatewayClient;
use realm_gateway::gateway::{Config, Gateway};
use realm_gateway::proto::*;
use realm_server::host::HostOpts;
use realm_server::sim::SimOpts;
use realm_store::*;
use std::sync::Arc;
use std::time::Duration;

struct World {
    gw: Arc<Gateway>,
    store: Arc<SqliteStore>,
    addr: String,
    _l: realm_gateway::conn::Listener,
    db: std::path::PathBuf,
}

impl Drop for World {
    fn drop(&mut self) {
        self.gw.shutdown();
        let _ = std::fs::remove_file(&self.db);
    }
}

fn world(name: &str, dev_login: bool) -> World {
    world_with(name, Config { dev_login, secret: 77, ..Config::default() })
}

fn world_with(name: &str, cfg: Config) -> World {
    let db = std::env::temp_dir().join(format!("realm-gw-{}-{name}.db", std::process::id()));
    let _ = std::fs::remove_file(&db);
    let store = Arc::new(SqliteStore::open(&db).unwrap());
    let gw = Gateway::start(store.clone(), cfg);
    let sim = SimOpts { field: 0, seed: 3, monsters: 100, threads: 1, bots: 0, rally_permille: 0, level: 0, vault: None };
    gw.add_host(HostOpts { sim, port: 0, ..HostOpts::default() }).unwrap();
    let l = realm_gateway::conn::listen(gw.clone(), "127.0.0.1:0").unwrap();
    World { gw, store, addr: l.addr.to_string(), _l: l, db }
}

fn login(w: &World, name: &str) -> GatewayClient {
    let mut c = GatewayClient::connect(&w.addr).unwrap();
    assert!(matches!(c.login(name).unwrap(), Resp::Login { .. }));
    c
}

fn make_hero(c: &mut GatewayClient, name: &str, class: u8) -> i64 {
    match c.call(Req::CreateHero { name: name.into(), race: 1, class, look: 4, self_found: false }).unwrap() {
        Resp::HeroCreated(id) => id,
        r => panic!("{r:?}"),
    }
}

fn code_of(r: Resp) -> u16 {
    match r {
        Resp::Err { code, .. } => code,
        r => panic!("expected an error, got {r:?}"),
    }
}

fn sys(_w: &World, n: u128) -> Meta {
    Meta::system(0xE57 << 100 | n, 1)
}

fn spec(slot: u8) -> ItemSpec {
    ItemSpec { base: 1, gear_slot: slot, item_level: 3, rarity: 1, lines: vec![(0, 2)], sockets: 1, plus: 0, bound: false }
}

#[test]
fn login_characters_and_the_rules_of_a_name() {
    let off = world("off", false);
    let mut c = GatewayClient::connect(&off.addr).unwrap();
    assert_eq!(code_of(c.login("x").unwrap()), code::DISABLED, "dev login is behind its flag");
    assert_eq!(code_of(c.call(Req::LoginSteam { ticket: vec![1] }).unwrap()), code::DISABLED);
    assert_eq!(code_of(c.call(Req::ListHeroes).unwrap()), code::NOT_LOGGED_IN);

    let w = world("chars", true);
    let mut ann = login(&w, "ann");
    assert_eq!(ann.heroes().unwrap(), vec![]);
    assert_eq!(code_of(ann.call(Req::CreateHero { name: "Nov".into(), race: 0, class: 0, look: 0, self_found: false }).unwrap()), code::BAD_REQUEST, "a hero picks one of the five classes");
    let h = make_hero(&mut ann, "Annabel", 3);
    assert_eq!(code_of(ann.call(Req::CreateHero { name: "annabel".into(), race: 0, class: 1, look: 0, self_found: false }).unwrap()), code::NAME_TAKEN);
    assert_eq!(code_of(ann.call(Req::CreateHero { name: "a b".into(), race: 0, class: 1, look: 0, self_found: false }).unwrap()), code::BAD_NAME);
    let list = ann.heroes().unwrap();
    assert_eq!((list.len(), list[0].id, list[0].class, list[0].race, list[0].class_level, list[0].job), (1, h, 3, 1, 1, realm_core::tables::NONE));
    // Another account cannot touch her.
    let mut bo = login(&w, "bobby");
    assert_eq!(code_of(bo.call(Req::DeleteHero { hero: h }).unwrap()), code::NOT_YOURS);
    assert_eq!(code_of(bo.call(Req::EnterTown { hero: h }).unwrap()), code::NOT_YOURS);
    // Delete and bring back.
    assert_eq!(ann.call(Req::DeleteHero { hero: h }).unwrap(), Resp::Ok);
    assert!(ann.heroes().unwrap()[0].deleted);
    assert_eq!(ann.call(Req::UndeleteHero { hero: h }).unwrap(), Resp::Ok);
    assert!(!ann.heroes().unwrap()[0].deleted);
    // The same account logs in again to the same heroes.
    let mut again = login(&w, "ann");
    assert_eq!(again.heroes().unwrap().len(), 1);
}

#[test]
fn towns_hold_heroes_once_and_carry_chat_and_snapshots() {
    let w = world("town", true);
    let (mut ann, mut bo) = (login(&w, "ann"), login(&w, "bobby"));
    let (ha, hb) = (make_hero(&mut ann, "Annie", 1), make_hero(&mut bo, "Bobby", 2));
    let Resp::Town { room, me: ma, members, .. } = ann.call(Req::EnterTown { hero: ha }).unwrap() else { panic!() };
    assert_eq!((room, members.len()), (1, 1));
    // A hero is in one place.
    let mut ann2 = login(&w, "ann");
    assert_eq!(code_of(ann2.call(Req::EnterTown { hero: ha }).unwrap()), code::BUSY);
    let Resp::Town { room: rb, me: mb, members, .. } = bo.call(Req::EnterTown { hero: hb }).unwrap() else { panic!() };
    assert_eq!((rb, members.len()), (1, 2));
    // Ann is told of Bo's arrival, and Bo's chat reaches her.
    assert!(ann.wait_push(Duration::from_secs(2), |r| matches!(r, Resp::Arrive(m) if m.name == "Bobby" && m.id == mb).then_some(())).unwrap().is_some());
    assert_eq!(bo.call(Req::Chat { text: "hello Ann".into() }).unwrap(), Resp::Ok);
    let got = ann.wait_push(Duration::from_secs(2), |r| if let Resp::Chat { from, name, text } = r { Some((*from, name.clone(), text.clone())) } else { None }).unwrap();
    assert_eq!(got, Some((mb, "Bobby".to_string(), "hello Ann".to_string())));
    // Snapshots: Ann walks and the snapshot moves her.
    assert_eq!(ann.call(Req::TownInput { dir: 1 }).unwrap(), Resp::Ok);
    let pos = |c: &mut GatewayClient, who: u16| -> (u16, u16) {
        c.wait_push(Duration::from_secs(2), |r| if let Resp::Snapshot(s) = r { s.at.iter().find(|a| a.0 == who).map(|a| (a.1, a.2)) } else { None }).unwrap().expect("a snapshot")
    };
    let first = pos(&mut bo, ma);
    // Snapshots queue on the socket, so read on until she has walked.
    let mut later = first;
    for _ in 0..60 {
        later = pos(&mut bo, ma);
        if later.0 > first.0 + 30 {
            break;
        }
    }
    assert!(later.0 > first.0 + 30, "{first:?} -> {later:?}");
    // Leaving frees her: another connection of hers may go in, and Bo is told.
    assert_eq!(ann.call(Req::LeaveTown).unwrap(), Resp::Ok);
    assert!(bo.wait_push(Duration::from_secs(2), |r| matches!(r, Resp::Depart(i) if *i == ma).then_some(())).unwrap().is_some());
    assert!(matches!(ann2.call(Req::EnterTown { hero: ha }).unwrap(), Resp::Town { .. }));
    // A connection that closes frees its hero too.
    drop(ann2);
    std::thread::sleep(Duration::from_millis(300));
    assert!(matches!(ann.call(Req::EnterTown { hero: ha }).unwrap(), Resp::Town { .. }));
}

#[test]
fn a_field_ticket_hands_the_hero_to_a_host_and_she_is_in_one_place() {
    let w = world("ticket", true);
    let mut ann = login(&w, "ann");
    let h = make_hero(&mut ann, "Annie", 1);
    assert_eq!(code_of(ann.call(Req::FieldTicket { hero: h, field: 6 }).unwrap()), code::BAD_REQUEST);
    assert_eq!(code_of(ann.call(Req::FieldTicket { hero: h, field: 3 }).unwrap()), code::NO_FIELD, "only field 0 is open here");
    assert!(matches!(ann.call(Req::EnterTown { hero: h }).unwrap(), Resp::Town { .. }));
    let Resp::Ticket { port, ticket, field, copy, .. } = ann.call(Req::FieldTicket { hero: h, field: 0 }).unwrap() else { panic!() };
    assert_eq!((field, copy), (0, 0));
    assert!(port > 0 && ticket != 0);
    assert!(w.gw.is_placed(h));
    assert_eq!(code_of(ann.call(Req::FieldTicket { hero: h, field: 0 }).unwrap()), code::BUSY);
    assert_eq!(code_of(ann.call(Req::EnterTown { hero: h }).unwrap()), code::BUSY, "she left the town for the field");
}

#[test]
fn the_bank_and_mail_go_through_the_stores_rules() {
    let w = world("bank", true);
    let (mut ann, mut bo) = (login(&w, "ann"), login(&w, "bobby"));
    let (ha, hb) = (make_hero(&mut ann, "Annie", 1), make_hero(&mut bo, "Bobby", 2));
    let ha2 = make_hero(&mut ann, "AnnTwo", 4);
    let item = w.store.mint(sys(&w, 1), Dest::bag(ha), spec(0), "grant").unwrap().0;
    let other = w.store.mint(sys(&w, 2), Dest::bag(hb), spec(1), "grant").unwrap().0;
    w.store.stack_credit(sys(&w, 3), Owner::bag(ha), StackKind::COIN, 500, true, "grant").unwrap();
    w.store.stack_credit(sys(&w, 4), Owner::bag(ha), StackKind::potion(0), 3, true, "grant").unwrap();

    // Bank: an item and some coin in, and the rules of whose it is.
    assert_eq!(ann.call(Req::BankDeposit { hero: ha, what: Thing::Item(item), tab: 0 }).unwrap(), Resp::Ok);
    assert_eq!(ann.call(Req::BankDeposit { hero: ha, what: Thing::Stack(1, 200), tab: 0 }).unwrap(), Resp::Ok);
    let inv = ann.inventory(ha).unwrap();
    assert_eq!((inv.stack(1, 1), inv.stack(3, 1)), (300, 200));
    assert!(inv.items.iter().any(|i| i.id == item && i.kind == PlaceKind::Bank as u8));
    assert_eq!(code_of(ann.call(Req::BankDeposit { hero: ha, what: Thing::Stack(1, 9999), tab: 0 }).unwrap()), code::INSUFFICIENT);
    assert_eq!(code_of(ann.call(Req::BankDeposit { hero: ha, what: Thing::Item(other), tab: 0 }).unwrap()), code::NOT_YOURS, "Bo's item");
    assert_eq!(code_of(bo.call(Req::BankWithdraw { hero: hb, what: Thing::Item(item), tab: 0 }).unwrap()), code::NOT_YOURS, "Ann's bank");
    assert_eq!(ann.call(Req::BankWithdraw { hero: ha, what: Thing::Item(item), tab: 0 }).unwrap(), Resp::Ok);
    assert_eq!(ann.call(Req::BankWithdraw { hero: ha, what: Thing::Stack(1, 50), tab: 0 }).unwrap(), Resp::Ok);
    assert_eq!(ann.inventory(ha).unwrap().stack(1, 1), 350);

    // Mail to another player's hero is the server's move, after the gateway checked the item is in her bag: the
    // store itself refuses the player doing it.
    let direct = w.store.move_item(Meta::new(0xAB1, w.store.heroes(1, false).unwrap()[0].account, 1), item, Dest::any(PlaceKind::Mail, hb));
    assert!(matches!(direct, Err(Error::NotYours(_)) | Err(Error::Refused)), "{direct:?}");
    assert_eq!(ann.call(Req::MailSend { hero: ha, to_name: "bobby".into(), what: Thing::Item(item) }).unwrap(), Resp::Ok);
    assert_eq!(ann.call(Req::MailSend { hero: ha, to_name: "Bobby".into(), what: Thing::Stack(100, 2) }).unwrap(), Resp::Ok);
    assert_eq!(code_of(ann.call(Req::MailSend { hero: ha, to_name: "Bobby".into(), what: Thing::Item(other) }).unwrap()), code::NOT_YOURS, "not hers to send");
    assert_eq!(code_of(ann.call(Req::MailSend { hero: ha, to_name: "Nobody".into(), what: Thing::Item(item) }).unwrap()), code::MISSING);
    assert_eq!(code_of(ann.call(Req::MailSend { hero: ha, to_name: "Annie".into(), what: Thing::Item(item) }).unwrap()), code::BAD_REQUEST, "to herself");
    assert_eq!(code_of(ann.call(Req::MailSend { hero: ha, to_name: "Bobby".into(), what: Thing::Stack(100, 99) }).unwrap()), code::INSUFFICIENT);
    let mail = bo.inventory(hb).unwrap();
    assert!(mail.items.iter().any(|i| i.id == item && i.kind == PlaceKind::Mail as u8));
    assert_eq!(mail.stack(4, 100), 2);
    assert_eq!(code_of(ann.call(Req::MailTake { hero: ha, what: Thing::Item(item) }).unwrap()), code::NOT_YOURS, "it is in Bo's mail");
    assert_eq!(bo.call(Req::MailTake { hero: hb, what: Thing::Item(item) }).unwrap(), Resp::Ok);
    assert_eq!(bo.call(Req::MailTake { hero: hb, what: Thing::Stack(100, 2) }).unwrap(), Resp::Ok);
    let bag = bo.inventory(hb).unwrap();
    assert!(bag.items.iter().any(|i| i.id == item && i.kind == PlaceKind::Bag as u8));
    assert_eq!(bag.stack(1, 100), 2);
    // Her own other hero is the player's own move.
    let mine = w.store.mint(sys(&w, 5), Dest::bag(ha), spec(2), "grant").unwrap().0;
    assert_eq!(ann.call(Req::MailSend { hero: ha, to_name: "AnnTwo".into(), what: Thing::Item(mine) }).unwrap(), Resp::Ok);
    assert!(ann.inventory(ha2).unwrap().items.iter().any(|i| i.id == mine && i.kind == PlaceKind::Mail as u8));
    // A TRADE_LOCKED account cannot send value to another.
    let acct = w.store.heroes(1, false).unwrap()[0].account;
    w.store.apply_flags(sys(&w, 6), vec![FlagChange { account: acct, flags: flags::TRADE_LOCKED, drops_percent: 100, banned_until: None }], "test").unwrap();
    let lock = w.store.mint(sys(&w, 7), Dest::bag(ha), spec(3), "grant").unwrap().0;
    assert_eq!(code_of(ann.call(Req::MailSend { hero: ha, to_name: "Bobby".into(), what: Thing::Item(lock) }).unwrap()), code::REFUSED);
}

#[test]
fn spends_and_the_smith_are_the_players_own() {
    let w = world("spend", true);
    let mut ann = login(&w, "ann");
    let h = make_hero(&mut ann, "Annie", 1);
    // Two levels earned on a field: the store pays one point each.
    let d = OutingDelta { xp: 1100, levels: 2, ..OutingDelta::default() };
    w.store.apply_outing(sys(&w, 1), h, d).unwrap();
    assert_eq!(ann.heroes().unwrap()[0].unspent, 2);
    assert_eq!(code_of(ann.call(Req::SpendPoint { hero: h, stat: 0, n: 3 }).unwrap()), code::BAD_REQUEST);
    assert_eq!(code_of(ann.call(Req::SpendPoint { hero: h, stat: 6, n: 1 }).unwrap()), code::BAD_REQUEST);
    assert_eq!(ann.call(Req::SpendPoint { hero: h, stat: 0, n: 2 }).unwrap(), Resp::Ok);
    let info = &ann.heroes().unwrap()[0];
    assert_eq!((info.stats[0], info.unspent, info.class_level), (2, 0, 3));
    // The deck: cards she owns; one she does not is refused by the store.
    assert_eq!(ann.call(Req::SetDeck { hero: h, cards: vec![0, 1, 2] }).unwrap(), Resp::Ok);
    assert_eq!(ann.heroes().unwrap()[0].deck, vec![0, 1, 2]);
    assert_eq!(code_of(ann.call(Req::SetDeck { hero: h, cards: vec![29] }).unwrap()), code::MISSING);
    assert_eq!(code_of(ann.call(Req::ChooseJob { hero: h, job: 0 }).unwrap()), code::BAD_REQUEST, "a job comes at class level 40");
    // The belt: potions only.
    w.store.stack_credit(sys(&w, 2), Owner::bag(h), StackKind::potion(0), 3, true, "grant").unwrap();
    assert_eq!(ann.call(Req::SetBelt { hero: h, kinds: [100, 0, 0] }).unwrap(), Resp::Ok);
    assert_eq!(code_of(ann.call(Req::SetBelt { hero: h, kinds: [1, 0, 0] }).unwrap()), code::INVALID);
    // Worn gear and the sheet the field will get.
    let sword = w.store.mint(sys(&w, 3), Dest::bag(h), ItemSpec { item_level: 2, ..spec(0) }, "grant").unwrap().0;
    assert_eq!(ann.call(Req::Equip { hero: h, item: sword }).unwrap(), Resp::Ok);
    let hero = w.store.hero(h).unwrap().unwrap();
    let sheet = realm_gateway::sheet::sheet_of(&*w.store, &hero).unwrap();
    assert_eq!((sheet.class, sheet.race, sheet.class_level, sheet.points[0], sheet.gear[0], sheet.gear_level), (1, 1, 3, 2, 2, 2));
    assert_eq!(sheet.belt[0], (0, 3));
    assert_eq!(sheet.deck, vec![1, 2, 3], "the store counts cards from 0, the core from 1");
    assert_eq!(ann.call(Req::Unequip { hero: h, item: sword }).unwrap(), Resp::Ok);
    // The smith: a salvage gives embers and removes the item.
    let junk = w.store.mint(sys(&w, 4), Dest::bag(h), spec(4), "grant").unwrap().0;
    let Resp::Smith { amount, success, .. } = ann.call(Req::Salvage { hero: h, item: junk }).unwrap() else { panic!() };
    assert!(success && amount > 0);
    assert!(w.store.item(junk).unwrap().is_none());
    assert_eq!(w.store.verify().unwrap().problems, Vec::<String>::new());
}

/// What the shell (job C2) added to the gateway: the item list carries `+` and what the sockets hold, the deck cards
/// a hero may use, a merchant's buy and sell, and the dev kit a new hero gets under `--dev-grant`.
#[test]
fn the_shells_calls_cards_merchants_and_the_dev_kit() {
    let w = world_with("shell", Config { dev_login: true, dev_grant: true, secret: 77, ..Config::default() });
    let mut ann = login(&w, "ann");
    let h = make_hero(&mut ann, "Annie", 1);
    // The kit: coin, embers, runes, two draughts and three items of level 1.
    let inv = ann.inventory(h).unwrap();
    assert_eq!((inv.stack(1, 1), inv.stack(1, 1000), inv.stack(1, 2001), inv.stack(1, 100)), (3500, 30, 4, 2));
    assert_eq!(inv.items.len(), 3);
    assert!(inv.items.iter().all(|i| i.level == 1 && i.kind == PlaceKind::Bag as u8 && i.plus == 0));
    // No kit without the flag.
    let plain = world("shell-plain", true);
    let mut bo = login(&plain, "bo");
    let hb = make_hero(&mut bo, "Bobby", 2);
    assert!(bo.inventory(hb).unwrap().items.is_empty());

    // A socketed rune and a plus show in the list.
    let rare = inv.items.iter().find(|i| i.rarity == 2).unwrap().id;
    assert_eq!(ann.call(Req::Socket { hero: h, item: rare, socket: 0, kind: 2001 }).unwrap().clone(), Resp::Smith { item: rare, plus: 0, success: true, amount: 10 });
    let Resp::Smith { item: up, plus, .. } = ann.call(Req::Upgrade { hero: h, item: rare }).unwrap() else { panic!() };
    assert_eq!(plus, 1);
    let it = ann.inventory(h).unwrap().items.into_iter().find(|i| i.id == up).unwrap();
    assert_eq!((it.plus, it.socketed.clone()), (1, vec![2001]));

    // The deck cards: the novice twelve at level 1; a hero of level 5 has two more.
    assert_eq!(ann.call(Req::Cards { hero: h }).unwrap(), Resp::Cards((0..12).collect()));
    let mut cy = login(&w, "cy");
    let hc = make_hero(&mut cy, "Cyrus", 2);
    assert_eq!(code_of(ann.call(Req::Cards { hero: hc }).unwrap()), code::NOT_YOURS, "not her hero");
    w.store.stack_credit(sys(&w, 90), Owner::bag(h), StackKind::page(25), 1, true, "grant").unwrap();
    assert_eq!(ann.call(Req::LearnPage { hero: h, card: 25 }).unwrap(), Resp::Ok);
    assert_eq!(ann.call(Req::Cards { hero: h }).unwrap(), Resp::Cards((0..12).chain([25]).collect()));

    // Buy: a draught is 20 coin; the price list is the merchant's; coin and bag judge the rest.
    let coin0 = ann.inventory(h).unwrap().stack(1, 1);
    let Resp::Smith { amount, .. } = ann.call(Req::Buy { hero: h, kind: 100, n: 3 }).unwrap() else { panic!() };
    assert_eq!(amount, 60);
    let inv = ann.inventory(h).unwrap();
    assert_eq!((inv.stack(1, 1), inv.stack(1, 100)), (coin0 - 60, 5));
    assert_eq!(code_of(ann.call(Req::Buy { hero: h, kind: 1, n: 1 }).unwrap()), code::BAD_REQUEST, "coin is not for sale");
    assert_eq!(code_of(ann.call(Req::Buy { hero: h, kind: 100, n: 0 }).unwrap()), code::BAD_REQUEST);
    assert_eq!(code_of(ann.call(Req::Buy { hero: h, kind: 105, n: 99 }).unwrap()), code::INSUFFICIENT, "400 coin each");
    assert_eq!(ann.inventory(h).unwrap().stack(1, 1), coin0 - 60, "a refused purchase takes nothing");
    // Sell: a common item level 1 pays 2 coin; an item that is not in her bag is refused.
    let common = inv.items.iter().find(|i| i.rarity == 0).unwrap().id;
    let before = ann.inventory(h).unwrap().stack(1, 1);
    assert_eq!(ann.call(Req::Sell { hero: h, item: common }).unwrap(), Resp::Smith { item: 0, plus: 0, success: true, amount: 2 });
    assert_eq!(ann.inventory(h).unwrap().stack(1, 1), before + 2);
    assert_eq!(code_of(ann.call(Req::Sell { hero: h, item: common }).unwrap()), code::MISSING, "it is gone");
    assert_eq!(w.store.verify().unwrap().problems, Vec::<String>::new());
}

