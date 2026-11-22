//! Living together (job T1) through real sockets: chat channels and their limits, parties, guilds and the guild bank
//! (through the store, no copy), friends and ignores, mute, report, and the moderators' console (silence, kick, ban,
//! ban wave). Flood and abuse tests included.

use realm_gateway::client::GatewayClient;
use realm_gateway::gateway::{Config, Gateway};
use realm_gateway::proto::*;
use realm_gateway::social::admin::{parse_span, Console, PERM_MS};
use realm_gateway::social::{chan, perm, Refuse, SPush, SReq, SResp};
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
    n: std::cell::Cell<u128>,
}

impl Drop for World {
    fn drop(&mut self) {
        self.gw.shutdown();
        for s in ["", ".social", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{}{s}", self.db.display()));
        }
    }
}

fn world(name: &str, copies: usize) -> World {
    let db = std::env::temp_dir().join(format!("realm-soc-{}-{name}.db", std::process::id()));
    for s in ["", ".social", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{s}", db.display()));
    }
    let store = Arc::new(SqliteStore::open(&db).unwrap());
    let gw = Gateway::start(store.clone(), Config { dev_login: true, secret: 5, ..Config::default() });
    gw.social.persist(std::path::Path::new(&format!("{}.social", db.display()))).unwrap();
    for c in 0..copies {
        let sim = SimOpts { field: 0, seed: 3 + c as u64, monsters: 50, threads: 1, bots: 0, rally_permille: 0, level: 0 };
        gw.add_host(HostOpts { sim, port: 0, ..HostOpts::default() }).unwrap();
    }
    let l = realm_gateway::conn::listen(gw.clone(), "127.0.0.1:0").unwrap();
    World { gw, store, addr: l.addr.to_string(), _l: l, db, n: std::cell::Cell::new(0) }
}

impl World {
    fn sys(&self) -> Meta {
        self.n.set(self.n.get() + 1);
        Meta::system(0x7100 << 100 | self.n.get(), 1)
    }
    fn console(&self) -> Console<'_> {
        Console { store: &self.store, social: &self.gw.social, live: Some(&self.gw), op: "mod1".into() }
    }
}

/// A logged-in player with one hero standing in town.
struct P {
    c: GatewayClient,
    hero: i64,
    account: i64,
    name: String,
}

fn player(w: &World, who: &str, hero_name: &str) -> P {
    let mut c = GatewayClient::connect(&w.addr).unwrap();
    let Resp::Login { account } = c.login(who).unwrap() else { panic!() };
    let Resp::HeroCreated(hero) = c.call(Req::CreateHero { name: hero_name.into(), race: 1, class: 1, look: 0, self_found: false }).unwrap() else { panic!() };
    assert!(matches!(c.call(Req::EnterTown { hero }).unwrap(), Resp::Town { .. }));
    P { c, hero, account, name: hero_name.into() }
}

fn soc(p: &mut P, q: SReq) -> Resp {
    p.c.call(Req::Social(q)).unwrap()
}

fn ok(r: Resp) {
    assert_eq!(r, Resp::Ok);
}

fn joined(r: Resp) {
    assert!(matches!(r, Resp::Social(SResp::Guild(Some(_)))), "{r:?}");
}

fn code_of(r: Resp) -> u16 {
    match r {
        Resp::Err { code, .. } => code,
        r => panic!("expected an error, got {r:?}"),
    }
}

fn say(p: &mut P, chan: u8, to: &str, text: &str) -> Resp {
    let hero = p.hero;
    soc(p, SReq::Talk { hero, chan, to: to.into(), text: text.into() })
}

/// The next chat push on a channel within a moment.
fn hear(p: &mut P, ch: u8) -> Option<(String, String)> {
    p.c.wait_push(Duration::from_millis(600), |r| match r {
        Resp::SocialPush(SPush::Chat { chan, from, text, .. }) if *chan == ch => Some((from.clone(), text.clone())),
        _ => None,
    })
    .unwrap()
}

fn hears_nothing(p: &mut P, ch: u8) -> bool {
    p.c.wait_push(Duration::from_millis(300), |r| matches!(r, Resp::SocialPush(SPush::Chat { chan, .. }) if *chan == ch).then_some(())).unwrap().is_none()
}

fn push_of<T>(p: &mut P, pick: impl FnMut(&SPush) -> Option<T>) -> Option<T> {
    let mut pick = pick;
    p.c.wait_push(Duration::from_secs(2), |r| if let Resp::SocialPush(s) = r { pick(s) } else { None }).unwrap()
}

fn make_party(w: &World, names: &[&str]) -> Vec<P> {
    let mut ps: Vec<P> = names.iter().map(|n| player(w, &format!("acct{n}"), n)).collect();
    let leader = ps[0].hero;
    for i in 1..ps.len() {
        let l = ps[0].name.clone();
        let name = ps[i].name.clone();
        ok(soc(&mut ps[0], SReq::PartyInvite { hero: leader, name }));
        let h = ps[i].hero;
        assert!(push_of(&mut ps[i], |p| matches!(p, SPush::PartyInvite { inviter, .. } if *inviter == leader).then_some(())).is_some(), "{l} invited");
        assert!(matches!(soc(&mut ps[i], SReq::PartyAnswer { hero: h, inviter: leader, accept: true }), Resp::Social(SResp::Party(Some(_)))));
    }
    ps
}

#[test]
fn channels_reach_the_right_ears_and_the_filter_masks() {
    let w = world("chan", 1);
    let (mut ann, mut bob, mut cat) = (player(&w, "ann", "Annie"), player(&w, "bob", "Bobby"), player(&w, "cat", "Catty"));
    // Town and trade are heard by everyone present.
    ok(say(&mut ann, chan::TOWN, "", "anyone about?"));
    assert_eq!(hear(&mut bob, chan::TOWN), Some(("Annie".into(), "anyone about?".into())));
    assert_eq!(hear(&mut cat, chan::TOWN), Some(("Annie".into(), "anyone about?".into())));
    ok(say(&mut bob, chan::TRADE, "", "selling a ring"));
    assert_eq!(hear(&mut cat, chan::TRADE).unwrap().1, "selling a ring");
    // The filter masks the line before it goes out; a link is refused.
    ok(say(&mut ann, chan::TOWN, "", "oh sh1t"));
    assert_eq!(hear(&mut bob, chan::TOWN).unwrap().1, "oh ****");
    assert_eq!(code_of(say(&mut ann, chan::TOWN, "", "buy at www.gold.example")), code::REFUSED);
    // A whisper reaches one hero (and echoes to the speaker); a missing hero or channel is an error.
    ok(say(&mut ann, chan::WHISPER, "bobby", "psst"));
    assert_eq!(hear(&mut bob, chan::WHISPER), Some(("Annie".into(), "psst".into())));
    assert_eq!(hear(&mut ann, chan::WHISPER), Some(("Annie".into(), "psst".into())));
    assert!(hears_nothing(&mut cat, chan::WHISPER));
    assert_eq!(code_of(say(&mut ann, chan::WHISPER, "nobodyhere", "x")), code::MISSING);
    assert_eq!(code_of(say(&mut ann, chan::PARTY, "", "x")), code::BAD_REQUEST, "no party");
    assert_eq!(code_of(say(&mut ann, chan::GUILD, "", "x")), code::BAD_REQUEST, "no guild");
    assert_eq!(code_of(say(&mut ann, 9, "", "x")), code::BAD_REQUEST);
    assert_eq!(code_of(say(&mut ann, chan::TOWN, "", "   ")), code::BAD_REQUEST);
    // Say is the town room (the older call) and goes through the same gate.
    ok(ann.c.call(Req::Chat { text: "hi room".into() }).unwrap());
    assert!(bob.c.wait_push(Duration::from_secs(2), |r| matches!(r, Resp::Chat { text, .. } if text == "hi room").then_some(())).unwrap().is_some());
    ok(ann.c.call(Req::Chat { text: "oh fuck".into() }).unwrap());
    assert!(bob.c.wait_push(Duration::from_secs(2), |r| matches!(r, Resp::Chat { text, .. } if text == "oh ****").then_some(())).unwrap().is_some());
    // Another account may not speak as her hero, nor a hero not yet in a town.
    let mut eve = GatewayClient::connect(&w.addr).unwrap();
    eve.login("eve").unwrap();
    assert_eq!(code_of(eve.call(Req::Social(SReq::Talk { hero: ann.hero, chan: chan::TOWN, to: String::new(), text: "x".into() })).unwrap()), code::NOT_YOURS);
}

#[test]
fn friends_are_mutual_and_ignores_are_quiet() {
    let w = world("friends", 1);
    let (mut ann, mut bob, mut cat) = (player(&w, "ann", "Annie"), player(&w, "bob", "Bobby"), player(&w, "cat", "Catty"));
    let (ha, hb) = (ann.hero, bob.hero);
    ok(soc(&mut ann, SReq::FriendAdd { hero: ha, name: "Bobby".into() }));
    let from = push_of(&mut bob, |p| if let SPush::FriendRequest { from, name } = p { Some((*from, name.clone())) } else { None }).unwrap();
    assert_eq!(from, (ann.account, "Annie".to_string()));
    let Resp::Social(SResp::Lists(l)) = soc(&mut bob, SReq::Lists { hero: hb }) else { panic!() };
    assert_eq!((l.friends.len(), l.pending.len()), (0, 1));
    ok(soc(&mut bob, SReq::FriendAnswer { hero: hb, from: ann.account, accept: true }));
    let Resp::Social(SResp::Lists(l)) = soc(&mut ann, SReq::Lists { hero: ha }) else { panic!() };
    assert_eq!((l.friends.len(), l.friends[0].name.as_str(), l.friends[0].online, l.friends[0].place), (1, "Bobby", true, 1));
    // A friend's departure is pushed.
    drop(bob);
    let st = push_of(&mut ann, |p| if let SPush::FriendStatus { online: false, name, .. } = p { Some(name.clone()) } else { None });
    assert_eq!(st.as_deref(), Some("Bobby"));
    let Resp::Social(SResp::Lists(l)) = soc(&mut ann, SReq::Lists { hero: ha }) else { panic!() };
    assert!(!l.friends[0].online);
    ok(soc(&mut ann, SReq::FriendRemove { hero: ha, target: l.friends[0].account }));
    assert_eq!(code_of(soc(&mut ann, SReq::FriendRemove { hero: ha, target: 99 })), code::MISSING);
    assert_eq!(code_of(soc(&mut ann, SReq::FriendAdd { hero: ha, name: "Annie".into() })), code::BAD_REQUEST);

    // Ignore: Cat ignores Ann; Ann's town line, whisper, party invite and friend request do not reach her, and Ann
    // is not told.
    let hc = cat.hero;
    ok(soc(&mut cat, SReq::Ignore { hero: hc, name: "Annie".into(), on: true }));
    ok(say(&mut ann, chan::TOWN, "", "hello Catty"));
    ok(say(&mut ann, chan::WHISPER, "Catty", "hello again"));
    ok(soc(&mut ann, SReq::PartyInvite { hero: ha, name: "Catty".into() }));
    ok(soc(&mut ann, SReq::FriendAdd { hero: ha, name: "Catty".into() }));
    assert!(hears_nothing(&mut cat, chan::TOWN));
    assert!(hears_nothing(&mut cat, chan::WHISPER));
    assert!(push_of(&mut cat, |p| matches!(p, SPush::PartyInvite { .. } | SPush::FriendRequest { .. }).then_some(())).is_none());
    let Resp::Social(SResp::Lists(l)) = soc(&mut cat, SReq::Lists { hero: hc }) else { panic!() };
    assert_eq!((l.ignores.len(), l.pending.len()), (1, 0));
    // Un-ignore restores it.
    ok(soc(&mut cat, SReq::Ignore { hero: hc, name: "Annie".into(), on: false }));
    ok(say(&mut ann, chan::TOWN, "", "welcome back"));
    assert_eq!(hear(&mut cat, chan::TOWN).unwrap().1, "welcome back");
}

#[test]
fn parties_of_eight_with_a_leader_a_chat_and_a_shared_copy() {
    let w = world("party", 2);
    let names = ["Ana", "Bea", "Cai", "Dov", "Eli", "Fay", "Gus", "Hal"];
    let mut ps = make_party(&w, &names);
    let leader = ps[0].hero;
    // Eight is the most; a ninth is refused.
    let mut nine = player(&w, "acctNine", "Ivo");
    assert_eq!(code_of(soc(&mut ps[0], SReq::PartyInvite { hero: leader, name: "Ivo".into() })), code::FULL);
    let h3 = ps[3].hero;
    let Resp::Social(SResp::Party(Some(v))) = soc(&mut ps[3], SReq::PartyInfo { hero: h3 }) else { panic!() };
    assert_eq!((v.members.len(), v.leader), (8, leader));
    // Only the leader invites, kicks, leads and calls.
    let (h1, h2) = (ps[1].hero, ps[2].hero);
    assert_eq!(code_of(soc(&mut ps[1], SReq::PartyInvite { hero: h1, name: "Ivo".into() })), code::REFUSED);
    assert_eq!(code_of(soc(&mut ps[1], SReq::PartyKick { hero: h1, target: h2 })), code::REFUSED);
    assert_eq!(code_of(soc(&mut ps[1], SReq::PartyLead { hero: h1, target: h2 })), code::REFUSED);
    assert_eq!(code_of(soc(&mut ps[1], SReq::PartyGo { hero: h1, field: 0 })), code::REFUSED);
    // Party chat is for the party only.
    ok(say(&mut ps[4], chan::PARTY, "", "stack up"));
    for p in ps.iter_mut() {
        assert_eq!(hear(p, chan::PARTY).unwrap().1, "stack up");
    }
    assert!(hears_nothing(&mut nine, chan::PARTY));
    // The leader calls the party to field 0; every member's ticket is for the same copy, and each has her own.
    ok(soc(&mut ps[0], SReq::PartyGo { hero: leader, field: 0 }));
    assert!(push_of(&mut ps[5], |p| matches!(p, SPush::PartyGo { field: 0 }).then_some(())).is_some());
    let mut tickets = Vec::new();
    for p in ps.iter_mut() {
        let Resp::Ticket { ticket, copy, field, .. } = p.c.call(Req::FieldTicket { hero: p.hero, field: 0 }).unwrap() else { panic!() };
        tickets.push((ticket, copy, field));
    }
    assert!(tickets.iter().all(|t| t.1 == tickets[0].1 && t.2 == 0), "{tickets:?}");
    let mut uniq: Vec<u64> = tickets.iter().map(|t| t.0).collect();
    uniq.sort();
    uniq.dedup();
    assert_eq!(uniq.len(), 8, "a ticket each: loot is per hero");
}

#[test]
fn party_leave_kick_and_lead_pass_on() {
    let w = world("party2", 1);
    let mut ps = make_party(&w, &["Ana", "Bea", "Cai"]);
    let (ha, hb, hc) = (ps[0].hero, ps[1].hero, ps[2].hero);
    ok(soc(&mut ps[0], SReq::PartyLead { hero: ha, target: hb }));
    let v = push_of(&mut ps[2], |p| if let SPush::PartyUpdate(Some(v)) = p { (v.leader == hb).then(|| v.clone()) } else { None }).unwrap();
    assert_eq!(v.members.len(), 3);
    // The new leader removes Cai; she is told, and the party is of two.
    ok(soc(&mut ps[1], SReq::PartyKick { hero: hb, target: hc }));
    assert!(push_of(&mut ps[2], |p| matches!(p, SPush::PartyUpdate(None)).then_some(())).is_some());
    assert!(matches!(soc(&mut ps[2], SReq::PartyInfo { hero: hc }), Resp::Social(SResp::Party(None))));
    // The leader leaves: a party of one is no party.
    ok(soc(&mut ps[1], SReq::PartyLeave { hero: hb }));
    assert!(matches!(soc(&mut ps[0], SReq::PartyInfo { hero: ha }), Resp::Social(SResp::Party(None))));
    assert_eq!(code_of(soc(&mut ps[0], SReq::PartyLeave { hero: ha })), code::BAD_REQUEST);
    // A declined or unknown invitation, and one already in a party.
    ok(soc(&mut ps[0], SReq::PartyInvite { hero: ha, name: "Cai".into() }));
    ok(soc(&mut ps[2], SReq::PartyAnswer { hero: hc, inviter: ha, accept: false }));
    assert_eq!(code_of(soc(&mut ps[2], SReq::PartyAnswer { hero: hc, inviter: ha, accept: true })), code::MISSING);
    // A dropped connection leaves the party.
    let mut ps2 = make_party(&w, &["Dov", "Eli"]);
    let (hd, he) = (ps2[0].hero, ps2[1].hero);
    let _ = he;
    drop(ps2.remove(1));
    std::thread::sleep(Duration::from_millis(300));
    assert!(matches!(soc(&mut ps2[0], SReq::PartyInfo { hero: hd }), Resp::Social(SResp::Party(None))));
}

#[test]
fn guilds_ranks_permissions_board_and_a_bank_with_no_copy() {
    let w = world("guild", 1);
    let (mut ann, mut bob, mut cat) = (player(&w, "ann", "Annie"), player(&w, "bob", "Bobby"), player(&w, "cat", "Catty"));
    let (ha, hb, hc) = (ann.hero, bob.hero, cat.hero);
    assert_eq!(code_of(soc(&mut ann, SReq::GuildCreate { hero: ha, name: "x".into() })), code::BAD_NAME);
    let Resp::Social(SResp::GuildCreated(gid)) = soc(&mut ann, SReq::GuildCreate { hero: ha, name: "The Pale Court".into() }) else { panic!() };
    assert_eq!(code_of(soc(&mut bob, SReq::GuildCreate { hero: hb, name: "the pale court".into() })), code::NAME_TAKEN);
    assert_eq!(code_of(soc(&mut ann, SReq::GuildCreate { hero: ha, name: "Another One".into() })), code::BUSY);
    // Invite, answer.
    ok(soc(&mut ann, SReq::GuildInvite { hero: ha, name: "Bobby".into() }));
    let gi = push_of(&mut bob, |p| if let SPush::GuildInvite { guild, guild_name, from } = p { Some((*guild, guild_name.clone(), from.clone())) } else { None }).unwrap();
    assert_eq!(gi, (gid, "The Pale Court".to_string(), "Annie".to_string()));
    let Resp::Social(SResp::Guild(Some(v))) = soc(&mut bob, SReq::GuildAnswer { hero: hb, guild: gid, accept: true }) else { panic!() };
    assert_eq!((v.my_rank, v.members.len()), (3, 2), "a new member is a recruit");
    ok(soc(&mut ann, SReq::GuildInvite { hero: ha, name: "Catty".into() }));
    joined(soc(&mut cat, SReq::GuildAnswer { hero: hc, guild: gid, accept: true }));
    // A recruit may not invite, kick or post; the leader promotes Bob to officer and Cat to member.
    assert_eq!(code_of(soc(&mut bob, SReq::GuildInvite { hero: hb, name: "Annie".into() })), code::REFUSED);
    assert_eq!(code_of(soc(&mut bob, SReq::GuildPost { hero: hb, text: "hi".into() })), code::REFUSED);
    assert_eq!(code_of(soc(&mut bob, SReq::GuildRank { hero: hb, target: cat.account, rank: 2 })), code::REFUSED);
    ok(soc(&mut ann, SReq::GuildRank { hero: ha, target: bob.account, rank: 1 }));
    ok(soc(&mut ann, SReq::GuildRank { hero: ha, target: cat.account, rank: 2 }));
    assert_eq!(code_of(soc(&mut bob, SReq::GuildRank { hero: hb, target: ann.account, rank: 3 })), code::REFUSED, "not above you");
    assert_eq!(code_of(soc(&mut bob, SReq::GuildRank { hero: hb, target: cat.account, rank: 1 })), code::REFUSED, "not to your own rank");
    assert_eq!(code_of(soc(&mut bob, SReq::GuildPerms { hero: hb, rank: 2, perms: 255 })), code::REFUSED, "only the leader sets permissions");
    // Motd and board, and guild chat for members only.
    ok(soc(&mut bob, SReq::GuildMotd { hero: hb, text: "Tide at dusk".into() }));
    ok(soc(&mut cat, SReq::GuildPost { hero: hc, text: "who has a lantern?".into() }));
    let Resp::Social(SResp::Guild(Some(v))) = soc(&mut cat, SReq::GuildInfo { hero: hc }) else { panic!() };
    assert_eq!((v.motd.as_str(), v.board.len(), v.board[0].author.as_str()), ("Tide at dusk", 1, "Catty"));
    let post = v.board[0].id;
    assert_eq!(code_of(soc(&mut cat, SReq::GuildUnpost { hero: hc, post: 999 })), code::MISSING);
    ok(say(&mut cat, chan::GUILD, "", "o7"));
    assert_eq!(hear(&mut ann, chan::GUILD).unwrap(), ("Catty".into(), "o7".into()));
    let mut out = player(&w, "dan", "Danny");
    let hd = out.hero;
    assert!(hears_nothing(&mut out, chan::GUILD));

    // The bank: Cat (member: deposit, no withdraw) deposits an item and coin; she cannot take them back out; Bob
    // (officer) can. Every move is one store call and the ledger can account for all of it.
    let item = w.store.mint(w.sys(), Dest::bag(hc), ItemSpec { base: 1, gear_slot: 1, item_level: 3, rarity: 1, lines: vec![(0, 2)], sockets: 1, plus: 0, bound: false }, "grant").unwrap().0;
    w.store.stack_credit(w.sys(), Owner::bag(hc), StackKind::COIN, 500, true, "grant").unwrap();
    let guild_owner = Owner { kind: PlaceKind::Guild, id: gid as i64 };
    assert_eq!(code_of(soc(&mut ann, SReq::GuildBank { hero: ha, what: realm_gateway::proto::Thing::Item(item), tab: 0, deposit: true })), code::NOT_YOURS, "not in Ann's bag");
    ok(soc(&mut cat, SReq::GuildBank { hero: hc, what: Thing::Item(item), tab: 2, deposit: true }));
    ok(soc(&mut cat, SReq::GuildBank { hero: hc, what: Thing::Stack(1, 200), tab: 0, deposit: true }));
    assert_eq!(code_of(soc(&mut cat, SReq::GuildBank { hero: hc, what: Thing::Stack(1, 9999), tab: 0, deposit: true })), code::INSUFFICIENT);
    let it = w.store.item(item).unwrap().unwrap();
    assert_eq!((it.place.kind, it.place.owner, it.place.tab), (PlaceKind::Guild, gid as i64, 2));
    // The one row is in the guild bank; the bag holds none; the coin is conserved.
    assert!(w.store.items_at(PlaceKind::Bag, hc).unwrap().iter().all(|i| i.id != item));
    assert_eq!(w.store.items_at(PlaceKind::Guild, gid as i64).unwrap().iter().filter(|i| i.id == item).count(), 1);
    assert_eq!(w.store.stack(guild_owner, StackKind::COIN).unwrap() + w.store.stack(Owner::bag(hc), StackKind::COIN).unwrap(), 500);
    let Resp::Social(SResp::Bank { items, stacks }) = soc(&mut bob, SReq::GuildBankView { hero: hb, tab: 2 }) else { panic!() };
    assert_eq!((items.len(), stacks), (1, vec![(1, 200)]));
    assert_eq!(code_of(soc(&mut cat, SReq::GuildBank { hero: hc, what: Thing::Item(item), tab: 0, deposit: false })), code::REFUSED);
    assert_eq!(code_of(soc(&mut cat, SReq::GuildBank { hero: hc, what: Thing::Stack(1, 10), tab: 0, deposit: false })), code::REFUSED);
    assert_eq!(code_of(soc(&mut out, SReq::GuildBankView { hero: hd, tab: 0 })), code::BAD_REQUEST, "no guild, no bank");
    ok(soc(&mut bob, SReq::GuildBank { hero: hb, what: Thing::Item(item), tab: 0, deposit: false }));
    assert_eq!(w.store.item(item).unwrap().unwrap().place.kind, PlaceKind::Bag);
    ok(soc(&mut bob, SReq::GuildBank { hero: hb, what: Thing::Stack(1, 150), tab: 0, deposit: false }));
    assert_eq!(w.store.stack(guild_owner, StackKind::COIN).unwrap(), 50);
    // The leader lets members withdraw items but not coin (WITHDRAW without COIN).
    ok(soc(&mut ann, SReq::GuildPerms { hero: ha, rank: 2, perms: perm::DEPOSIT | perm::WITHDRAW | perm::POST }));
    ok(soc(&mut bob, SReq::GuildBank { hero: hb, what: Thing::Item(item), tab: 1, deposit: true }));
    ok(soc(&mut cat, SReq::GuildBank { hero: hc, what: Thing::Item(item), tab: 1, deposit: false }));
    assert_eq!(code_of(soc(&mut cat, SReq::GuildBank { hero: hc, what: Thing::Stack(1, 10), tab: 0, deposit: false })), code::REFUSED, "no coin for a member");
    // A bank whose item is Bob's cannot be emptied by Cat from the wrong place.
    assert_eq!(code_of(soc(&mut cat, SReq::GuildBank { hero: hc, what: Thing::Item(item), tab: 0, deposit: false })), code::NOT_YOURS, "it is in her bag now");
    // The ledger replays clean: nothing was copied or lost.
    let rep = w.store.verify().unwrap();
    assert!(rep.problems.is_empty(), "{:?}", rep.problems);
    // Board: a post is removed by its author; an officer removes others'.
    ok(soc(&mut cat, SReq::GuildUnpost { hero: hc, post }));
    // Leaving, kicking, and disbanding with a stocked bank.
    assert_eq!(code_of(soc(&mut ann, SReq::GuildLeave { hero: ha })), code::REFUSED, "hand over first");
    ok(soc(&mut ann, SReq::GuildKick { hero: ha, target: bob.account }));
    assert_eq!(code_of(soc(&mut bob, SReq::GuildBankView { hero: hb, tab: 0 })), code::BAD_REQUEST, "a removed member has no bank");
    assert_eq!(code_of(soc(&mut cat, SReq::GuildKick { hero: hc, target: ann.account })), code::REFUSED);
}

#[test]
fn a_stocked_guild_is_not_disbanded_and_a_guild_survives_a_restart() {
    let w = world("restart", 1);
    let (mut ann, mut bob) = (player(&w, "ann", "Annie"), player(&w, "bob", "Bobby"));
    let (ha, hb) = (ann.hero, bob.hero);
    let Resp::Social(SResp::GuildCreated(gid)) = soc(&mut ann, SReq::GuildCreate { hero: ha, name: "Ash Wardens".into() }) else { panic!() };
    ok(soc(&mut ann, SReq::GuildInvite { hero: ha, name: "Bobby".into() }));
    joined(soc(&mut bob, SReq::GuildAnswer { hero: hb, guild: gid, accept: true }));
    ok(soc(&mut ann, SReq::GuildMotd { hero: ha, text: "ash and ember".into() }));
    ok(soc(&mut ann, SReq::GuildPerms { hero: ha, rank: 3, perms: perm::DEPOSIT | perm::WITHDRAW | perm::COIN }));
    ok(soc(&mut ann, SReq::GuildPost { hero: ha, text: "meet at the gate".into() }));
    ok(soc(&mut ann, SReq::FriendAdd { hero: ha, name: "Bobby".into() }));
    ok(soc(&mut bob, SReq::FriendAnswer { hero: hb, from: ann.account, accept: true }));
    w.store.stack_credit(w.sys(), Owner::bag(hb), StackKind::COIN, 90, true, "grant").unwrap();
    ok(soc(&mut bob, SReq::GuildBank { hero: hb, what: Thing::Stack(1, 90), tab: 0, deposit: true }));
    assert_eq!(code_of(soc(&mut ann, SReq::GuildDisband { hero: ha })), code::INVALID, "empty the bank first");
    // A kicked member is out; the leader cannot leave while others stay.
    ok(soc(&mut ann, SReq::GuildKick { hero: ha, target: bob.account }));
    assert!(matches!(soc(&mut bob, SReq::GuildInfo { hero: hb }), Resp::Social(SResp::Guild(None))));
    ok(soc(&mut ann, SReq::GuildInvite { hero: ha, name: "Bobby".into() }));
    joined(soc(&mut bob, SReq::GuildAnswer { hero: hb, guild: gid, accept: true }));
    // Restart: a new Social replays the log into the same state.
    let again = realm_gateway::social::Social::default();
    again.persist(std::path::Path::new(&format!("{}.social", w.db.display()))).unwrap();
    let g = again.guild_snapshot(gid).expect("the guild is back");
    assert_eq!((g.name.as_str(), g.motd.as_str(), g.members, g.board, g.perms[3]), ("Ash Wardens", "ash and ember", vec![(ann.account, 0), (bob.account, 3)], vec!["meet at the gate".to_string()], perm::DEPOSIT | perm::WITHDRAW | perm::COIN));
    let l = again.lists_snapshot(ann.account);
    assert_eq!((l.0, l.1), (vec![bob.account], vec![]), "friends are kept");
    // Ignoring ends the friendship, and that is kept too.
    ok(soc(&mut ann, SReq::Ignore { hero: ha, name: "Bobby".into(), on: true }));
    let again2 = realm_gateway::social::Social::default();
    again2.persist(std::path::Path::new(&format!("{}.social", w.db.display()))).unwrap();
    assert_eq!(again2.lists_snapshot(ann.account), (vec![], vec![bob.account]), "ignores are kept");
    assert_eq!(again2.lists_snapshot(bob.account), (vec![], vec![]));
    // Empty the bank; now the leader (alone after Bob leaves) may disband.
    ok(soc(&mut bob, SReq::GuildBank { hero: hb, what: Thing::Stack(1, 90), tab: 0, deposit: false }));
    ok(soc(&mut bob, SReq::GuildLeave { hero: hb }));
    ok(soc(&mut ann, SReq::GuildLeave { hero: ha }));
    assert!(matches!(soc(&mut ann, SReq::GuildInfo { hero: ha }), Resp::Social(SResp::Guild(None))));
    let r = w.store.verify().unwrap();
    assert!(r.problems.is_empty(), "{:?}", r.problems);
}

/// Abuse tests: floods, mutes, reports, kicks and bans, with the console.
#[test]
fn a_flood_of_a_thousand_lines_a_second_is_limited_and_silences_the_bot() {
    let w = world("flood", 1);
    let mut bot = player(&w, "bot", "Botty");
    let mut listener = player(&w, "ear", "Earnest");
    // 1,000 lines as fast as the socket takes them, on the town channel: a burst gets through, the rest are
    // refused, and the strikes silence the bot.
    let (mut sent, mut slow, mut muted) = (0u32, 0u32, 0u32);
    let hero = bot.hero;
    for i in 0..1000 {
        match bot.c.call(Req::Social(SReq::Talk { hero, chan: chan::TOWN, to: String::new(), text: format!("buy gold {i}") })).unwrap() {
            Resp::Ok => sent += 1,
            Resp::Err { code, .. } if code == code::SLOW_DOWN => slow += 1,
            Resp::Err { code, .. } if code == code::MUTED => muted += 1,
            r => panic!("{r:?}"),
        }
    }
    assert!(sent <= 6, "{sent} lines got through of 1000");
    assert!(slow >= 25 && muted > 900, "slow {slow} muted {muted}");
    assert!(w.gw.social.muted_until(bot.account, realm_gateway::gateway::now_ms()).is_some(), "the flood silenced her");
    assert!(w.gw.social.admin_log(10).iter().any(|l| l.1 == "auto" && l.2.contains("flood")), "and it is logged");
    // The listener heard no more than what got through.
    let mut heard = 0;
    while hear(&mut listener, chan::TOWN).is_some() {
        heard += 1;
    }
    assert_eq!(heard, sent);
    // She is silent on the other channels too.
    assert_eq!(code_of(say(&mut bot, chan::WHISPER, "Earnest", "x")), code::MUTED);
    assert_eq!(code_of(bot.c.call(Req::Chat { text: "x".into() }).unwrap()), code::MUTED);
}

#[test]
fn many_bots_at_a_thousand_lines_a_second_are_limited_by_the_gate() {
    // The gate itself at a simulated rate (no sockets): 20 bots, 50 lines each a second, over 10 seconds on
    // spread channels; every bot passes only about its bucket allows and is silenced when it keeps pushing.
    let social = realm_gateway::social::Social::default();
    let chans = [chan::SAY, chan::TOWN, chan::TRADE, chan::PARTY, chan::GUILD, chan::WHISPER];
    let (mut passed, mut total) = (0u32, 0u32);
    for ms in 0..10_000i64 {
        for bot in 0..20i64 {
            // 1,000 lines a second over all bots: one bot per 20 ms tick sends a line each ms.
            if ms % 20 == bot {
                total += 1;
                if social.gate(100 + bot, chans[(ms as usize / 20) % 6], "spam spam", ms).is_ok() {
                    passed += 1;
                }
            }
        }
    }
    assert_eq!(total, 10_000);
    // 50 lines a second a bot, 20 bots: unlimited it would be 10,000 lines. Each bot is silenced for five minutes
    // after its first strikes, so what passes is a burst each.
    assert!(passed <= 20 * 16, "{passed} of {total} passed");
    for bot in 0..20 {
        assert!(social.muted_until(100 + bot, 10_000).is_some());
    }
    // A polite player at a chat's pace is never refused: one line every 2 s on town.
    let mut polite = 0;
    for k in 0..100i64 {
        if social.gate(500, chan::TOWN, "hello", k * 2_000).is_ok() {
            polite += 1;
        }
    }
    assert_eq!(polite, 100);
    assert_eq!(social.gate(501, chan::SAY, "x", 0), Ok("x".to_string()));
    assert_eq!(social.gate(501, chan::SAY, "  ", 0), Err(Refuse::Empty));
}

#[test]
fn a_silenced_player_is_silent_everywhere_and_speaks_again_when_lifted() {
    let w = world("mute", 1);
    let (mut ann, mut bob) = (player(&w, "ann", "Annie"), player(&w, "bob", "Bobby"));
    let (ha, hb) = (ann.hero, bob.hero);
    let Resp::Social(SResp::GuildCreated(gid)) = soc(&mut ann, SReq::GuildCreate { hero: ha, name: "Loud Ones".into() }) else { panic!() };
    ok(soc(&mut ann, SReq::GuildInvite { hero: ha, name: "Bobby".into() }));
    joined(soc(&mut bob, SReq::GuildAnswer { hero: hb, guild: gid, accept: true }));
    ok(soc(&mut ann, SReq::PartyInvite { hero: ha, name: "Bobby".into() }));
    assert!(matches!(soc(&mut bob, SReq::PartyAnswer { hero: hb, inviter: ha, accept: true }), Resp::Social(SResp::Party(Some(_)))));
    ok(soc(&mut ann, SReq::GuildPerms { hero: ha, rank: 3, perms: perm::POST | perm::DEPOSIT }));
    let out = w.console().run("silence Annie 30m spamming gold");
    assert!(out.contains("Annie") && out.contains("silenced"), "{out}");
    assert!(push_of(&mut ann, |p| matches!(p, SPush::Notice { .. }).then_some(())).is_some(), "she is told");
    for ch in [chan::TOWN, chan::TRADE, chan::PARTY, chan::GUILD] {
        assert_eq!(code_of(say(&mut ann, ch, "", "hello")), code::MUTED, "channel {ch}");
    }
    assert_eq!(code_of(say(&mut ann, chan::WHISPER, "Bobby", "hello")), code::MUTED);
    assert_eq!(code_of(ann.c.call(Req::Chat { text: "hello".into() }).unwrap()), code::MUTED);
    // The leader is silent on the board too (she may still do bank and rank work: silence is about speech).
    assert_eq!(code_of(soc(&mut ann, SReq::GuildPost { hero: ha, text: "hello".into() })), code::MUTED);
    assert_eq!(code_of(soc(&mut ann, SReq::GuildMotd { hero: ha, text: "hello".into() })), code::MUTED);
    for ch in [chan::TOWN, chan::TRADE, chan::PARTY, chan::GUILD, chan::WHISPER] {
        assert!(hears_nothing(&mut bob, ch), "Bobby heard channel {ch}");
    }
    assert!(!bob.c.wait_push(Duration::from_millis(200), |r| matches!(r, Resp::Chat { .. }).then_some(())).unwrap().is_some());
    // Bobby is not muted.
    ok(say(&mut bob, chan::PARTY, "", "can you hear me"));
    assert_eq!(hear(&mut ann, chan::PARTY).unwrap().1, "can you hear me", "she may listen");
    assert_eq!(hear(&mut bob, chan::PARTY).unwrap().1, "can you hear me", "and he hears himself");
    // The silence is in the log, and it is kept across a restart.
    let log = w.console().run("log 5");
    assert!(log.contains("mod1: silence") && log.contains("spamming gold"), "{log}");
    let again = realm_gateway::social::Social::default();
    again.persist(std::path::Path::new(&format!("{}.social", w.db.display()))).unwrap();
    assert!(again.muted_until(ann.account, realm_gateway::gateway::now_ms()).is_some());
    // Lifted.
    assert!(w.console().run("unsilence Annie").contains("may speak"));
    ok(say(&mut ann, chan::PARTY, "", "thanks"));
    assert_eq!(hear(&mut bob, chan::PARTY).unwrap().1, "thanks");
    let again = realm_gateway::social::Social::default();
    again.persist(std::path::Path::new(&format!("{}.social", w.db.display()))).unwrap();
    assert!(again.muted_until(ann.account, realm_gateway::gateway::now_ms()).is_none(), "a lifted silence is lifted after a restart too");
}

#[test]
fn reports_carry_the_last_lines_and_the_console_reads_and_closes_them() {
    let w = world("report", 1);
    let (mut ann, mut bob, mut cat) = (player(&w, "ann", "Annie"), player(&w, "bob", "Bobby"), player(&w, "cat", "Catty"));
    for t in ["selling gold cheap", "visit my page", "gold gold gold"] {
        ok(say(&mut ann, chan::TOWN, "", t));
        std::thread::sleep(Duration::from_millis(20));
    }
    let hb = bob.hero;
    let Resp::Social(SResp::Reported(id)) = soc(&mut bob, SReq::Report { hero: hb, name: "Annie".into(), reason: 0, text: "gold spam".into() }) else { panic!() };
    assert_eq!(id, 1);
    assert_eq!(code_of(soc(&mut bob, SReq::Report { hero: hb, name: "Catty".into(), reason: 1, text: "x".into() })), code::SLOW_DOWN, "one at a time");
    assert_eq!(code_of(soc(&mut bob, SReq::Report { hero: hb, name: "Bobby".into(), reason: 1, text: "x".into() })), code::BAD_REQUEST);
    assert_eq!(code_of(soc(&mut bob, SReq::Report { hero: hb, name: "Nobody".into(), reason: 1, text: "x".into() })), code::MISSING);
    assert_eq!(code_of(soc(&mut bob, SReq::Report { hero: hb, name: "Annie".into(), reason: 9, text: "x".into() })), code::BAD_REQUEST);
    let hc = cat.hero;
    ok_report(soc(&mut cat, SReq::Report { hero: hc, name: "Annie".into(), reason: 1, text: "rude".into() }));
    let out = w.console().run("reports");
    assert!(out.contains("Bobby") && out.contains("reports Annie") && out.contains("spam") && out.contains("gold spam"), "{out}");
    assert!(out.contains("visit my page") && out.contains("gold gold gold"), "evidence: {out}");
    assert!(w.console().run("resolve 1").contains("closed"));
    assert!(w.console().run("resolve 1").starts_with("error"), "twice");
    let out = w.console().run("reports");
    assert!(!out.contains("gold spam") && out.contains("rude"), "{out}");
    assert!(w.console().run("reports all").contains("closed by mod1"));
    let _ = (&mut ann, &mut cat);
}

fn ok_report(r: Resp) {
    assert!(matches!(r, Resp::Social(SResp::Reported(_))), "{r:?}");
}

#[test]
fn a_ban_ends_sessions_and_refuses_login_and_a_wave_bans_by_flag() {
    let w = world("ban", 1);
    let (mut ann, mut bob, mut cat) = (player(&w, "ann", "Annie"), player(&w, "bob", "Bobby"), player(&w, "cat", "Catty"));
    // Annie is in a field, Bobby in town.
    let Resp::Ticket { .. } = ann.c.call(Req::FieldTicket { hero: ann.hero, field: 0 }).unwrap() else { panic!() };
    assert!(w.gw.is_placed(ann.hero));
    let out = w.console().run("ban Annie 24h cheating with a cheat engine");
    assert!(out.contains("banned") && out.contains("1 hero"), "{out}");
    // Her connection is closed by the server.
    let mut closed = false;
    for _ in 0..30 {
        if ann.c.call(Req::Ping).is_err() {
            closed = true;
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    assert!(closed, "the session ended");
    // Login is refused for the length of the ban; the store has the ban and its ledger row.
    let mut again = GatewayClient::connect(&w.addr).unwrap();
    assert_eq!(code_of(again.login("ann").unwrap()), code::BANNED);
    let acct = w.store.account(ann.account).unwrap().unwrap();
    assert!(acct.banned_until.is_some_and(|u| u > realm_gateway::gateway::now_ms()));
    // She is out of her field (kicked and banked) once the host has sent her result.
    let mut free = false;
    for _ in 0..60 {
        if !w.gw.is_placed(ann.hero) {
            free = true;
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    assert!(free, "her hero is out of the field");
    // She is gone from town chat.
    assert!(!w.gw.social.is_present(ann.hero));
    // The others are untouched.
    ok(say(&mut bob, chan::TOWN, "", "she is gone"));
    assert_eq!(hear(&mut cat, chan::TOWN).unwrap().1, "she is gone");
    // Lifting it lets her log in.
    assert!(w.console().run("unban Annie").contains("may log in"));
    assert!(matches!(again.login("ann").unwrap(), Resp::Login { .. }));
    // A wave: flag two accounts watched and shadowed, then ban everyone carrying `watched`.
    assert!(w.console().run("flag Bobby watched").contains("watched"));
    assert!(w.console().run("flag Catty watched,drops_reduced drops=50").contains("drops_reduced"));
    assert!(w.console().run("who Catty").contains("drops 50%"));
    assert!(w.console().run("flag Nobody watched").starts_with("error"));
    assert!(w.console().run("flag Annie sparkly").starts_with("error"));
    let out = w.console().run("banwave watched 2h flagged by the loot audit");
    assert!(out.contains("2 account(s) banned") && out.contains("2 hero"), "{out}");
    for c in [&mut bob.c, &mut cat.c] {
        let mut closed = false;
        for _ in 0..30 {
            if c.call(Req::Ping).is_err() {
                closed = true;
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        assert!(closed);
    }
    for who in ["bob", "cat"] {
        let mut g = GatewayClient::connect(&w.addr).unwrap();
        assert_eq!(code_of(g.login(who).unwrap()), code::BANNED);
    }
    // Annie, not flagged, still logs in. Flags survive the ban (they were kept, not replaced).
    assert!(matches!(GatewayClient::connect(&w.addr).unwrap().login("ann").unwrap(), Resp::Login { .. }));
    assert_eq!(w.store.account(cat.account).unwrap().unwrap().flags, realm_store::flags::WATCHED | realm_store::flags::DROPS_REDUCED);
    assert_eq!(w.store.account(cat.account).unwrap().unwrap().drops_percent, 50);
    // Everything is in the moderators' log, with who did it.
    let log = w.console().run("log 20");
    for want in ["mod1: ban #1", "mod1: unban #1", "mod1: flag #2", "mod1: banwave watched"] {
        assert!(log.contains(want), "{want} in {log}");
    }
    assert!(w.console().run("banwave watched 2h").contains("2 account(s)"), "a second wave is harmless");
    assert!(w.console().run("banwave sparkly 2h").starts_with("error"));
    assert!(w.console().run("ban Annie").starts_with("error"), "an incomplete command");
    let r = w.store.verify().unwrap();
    assert!(r.problems.is_empty(), "{:?}", r.problems);
}

#[test]
fn kick_ends_a_session_without_a_ban_and_the_admin_port_needs_its_token() {
    let w = world("kick", 1);
    let mut ann = player(&w, "ann", "Annie");
    let addr = realm_gateway::social::admin::serve(w.gw.clone(), 0, "0123456789abcdef0123".into()).unwrap();
    let ask = |token: &str, line: &str| -> String {
        use std::io::{Read, Write};
        let mut s = std::net::TcpStream::connect(addr).unwrap();
        s.write_all(format!("{token}\tremote\n{line}\n").as_bytes()).unwrap();
        let mut o = String::new();
        s.read_to_string(&mut o).unwrap();
        o
    };
    assert!(ask("wrong", "who Annie").starts_with("error: bad token"));
    assert!(ask("0123456789abcdef0123", "who Annie").contains("online true"));
    assert!(ask("0123456789abcdef0123", "kick Annie bad manners").contains("1 hero(es) removed"));
    let mut closed = false;
    for _ in 0..30 {
        if ann.c.call(Req::Ping).is_err() {
            closed = true;
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    assert!(closed);
    // A kick is not a ban: she logs in again.
    assert!(matches!(GatewayClient::connect(&w.addr).unwrap().login("ann").unwrap(), Resp::Login { .. }));
    assert!(w.console().run("log").contains("remote: kick"), "the operator's name is in the log");
    assert!(ask("0123456789abcdef0123", "help").contains("banwave"));
}

#[test]
fn the_offline_console_reads_what_a_stopped_gateway_left() {
    let w = world("offline", 1);
    let (mut ann, mut bob) = (player(&w, "ann", "Annie"), player(&w, "bob", "Bobby"));
    let hb = bob.hero;
    ok(say(&mut ann, chan::TOWN, "", "free gold here"));
    ok_report(soc(&mut bob, SReq::Report { hero: hb, name: "Annie".into(), reason: 0, text: "spam".into() }));
    let db = w.db.display().to_string();
    // The binary's own client side: cli over --db (the store is shared; the social log is read from its file).
    let args = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
    assert_eq!(realm_gateway::social::admin::cli(&args(&["--db", &db])), 2);
    assert_eq!(realm_gateway::social::admin::cli(&args(&[&format!("--db={db}"), "--op=night", "reports"])), 0);
    assert_eq!(realm_gateway::social::admin::cli(&args(&[&format!("--db={db}"), "--op=night", "ban", "Annie", "perm"])), 0);
    assert!(w.store.account(ann.account).unwrap().unwrap().banned_until.is_some_and(|u| u >= PERM_MS));
    assert_eq!(realm_gateway::social::admin::cli(&args(&[&format!("--db={db}"), "ban", "Nobody", "1h"])), 1);
    assert_eq!(parse_span("1h", 'm'), Some(3_600_000));
}
