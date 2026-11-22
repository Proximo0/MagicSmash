//! Players against players at the gateway (job R3) through real sockets: guild altar wars (declare, accept, list,
//! call off; officers only; the field's view; the result; kept through a restart), duels in the training yard
//! (challenge, decline, accept, busy, steered by town input to a result for both), and the BLOOD MARK's book.

use realm_core::tables::NEVER;
use realm_core::{tide_start, Outing};
use realm_gateway::client::GatewayClient;
use realm_gateway::gateway::{Config, Gateway};
use realm_gateway::proto::*;
use realm_gateway::social::{duel_op, SPush, SReq, SResp, WarView};
use realm_store::*;
use std::sync::Arc;
use std::time::Duration;

struct World {
    gw: Arc<Gateway>,
    addr: String,
    _l: realm_gateway::conn::Listener,
    db: std::path::PathBuf,
}

impl Drop for World {
    fn drop(&mut self) {
        self.gw.shutdown();
        for s in ["", ".social", "-wal", "-shm"] {
            let _ = std::fs::remove_file(format!("{}{s}", self.db.display()));
        }
    }
}

fn world(name: &str) -> World {
    let db = std::env::temp_dir().join(format!("realm-pvp-{}-{name}.db", std::process::id()));
    for s in ["", ".social", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{s}", db.display()));
    }
    let store = Arc::new(SqliteStore::open(&db).unwrap());
    let gw = Gateway::start(store, Config { dev_login: true, secret: 5, ..Config::default() });
    gw.social.persist(std::path::Path::new(&format!("{}.social", db.display()))).unwrap();
    let l = realm_gateway::conn::listen(gw.clone(), "127.0.0.1:0").unwrap();
    World { gw, addr: l.addr.to_string(), _l: l, db }
}

struct P {
    c: GatewayClient,
    hero: i64,
    account: i64,
}

fn player(w: &World, who: &str, hero_name: &str) -> P {
    let mut c = GatewayClient::connect(&w.addr).unwrap();
    let Resp::Login { account } = c.login(who).unwrap() else { panic!() };
    let Resp::HeroCreated(hero) = c.call(Req::CreateHero { name: hero_name.into(), race: 1, class: 1, look: 0, self_found: false }).unwrap() else { panic!() };
    assert!(matches!(c.call(Req::EnterTown { hero }).unwrap(), Resp::Town { .. }));
    P { c, hero, account }
}

fn soc(p: &mut P, q: SReq) -> Resp {
    p.c.call(Req::Social(q)).unwrap()
}

fn code_of(r: Resp) -> u16 {
    match r {
        Resp::Err { code, .. } => code,
        r => panic!("expected an error, got {r:?}"),
    }
}

fn push_of<T>(p: &mut P, pick: impl FnMut(&SPush) -> Option<T>) -> Option<T> {
    let mut pick = pick;
    p.c.wait_push(Duration::from_secs(3), |r| if let Resp::SocialPush(s) = r { pick(s) } else { None }).unwrap()
}

fn guild(p: &mut P, name: &str) -> u64 {
    let hero = p.hero;
    let Resp::Social(SResp::GuildCreated(g)) = soc(p, SReq::GuildCreate { hero, name: name.into() }) else { panic!() };
    g
}

#[test]
fn altar_wars_are_declared_accepted_listed_fought_and_called_off_by_officers() {
    let w = world("wars");
    let (mut ann, mut bob, mut cat) = (player(&w, "ann", "Annie"), player(&w, "bob", "Bobby"), player(&w, "cat", "Catty"));
    let (ha, hb, hc) = (ann.hero, bob.hero, cat.hero);
    let ga = guild(&mut ann, "Ash Wardens");
    let gb = guild(&mut bob, "Pale Court");
    ok(soc(&mut ann, SReq::GuildInvite { hero: ha, name: "Catty".into() }));
    assert!(matches!(soc(&mut cat, SReq::GuildAnswer { hero: hc, guild: ga, accept: true }), Resp::Social(SResp::Guild(Some(_)))));
    // A recruit may not; a guild may not war on itself; the field must exist.
    assert_eq!(code_of(soc(&mut cat, SReq::WarDeclare { hero: hc, foe: "Pale Court".into(), field: 2 })), code::REFUSED);
    assert_eq!(code_of(soc(&mut ann, SReq::WarDeclare { hero: ha, foe: "ash wardens".into(), field: 2 })), code::BAD_REQUEST);
    assert_eq!(code_of(soc(&mut ann, SReq::WarDeclare { hero: ha, foe: "Pale Court".into(), field: 9 })), code::BAD_REQUEST);
    assert_eq!(code_of(soc(&mut ann, SReq::WarDeclare { hero: ha, foe: "Nobody Here".into(), field: 2 })), code::MISSING);
    // The leader declares for THE MOON MARSH's next tide at least two minutes away.
    let Resp::Social(SResp::WarDeclared(v)) = soc(&mut ann, SReq::WarDeclare { hero: ha, foe: "pale court".into(), field: 2 }) else { panic!() };
    let now = w.gw.world.clock.now();
    assert!(tide_start(2, v.tide) >= now + realm_gateway::social::pvp::WAR_LEAD_TICKS);
    assert!(v.tide == 0 || tide_start(2, v.tide - 1) < now + realm_gateway::social::pvp::WAR_LEAD_TICKS);
    assert_eq!((v.guilds, v.names.clone(), v.field, v.accepted), ([ga, gb], ["Ash Wardens".to_string(), "Pale Court".to_string()], 2, false));
    let seen = push_of(&mut bob, |p| if let SPush::War(x) = p { Some(x.clone()) } else { None }).expect("the other guild is told");
    assert_eq!(seen, v);
    assert!(push_of(&mut cat, |p| matches!(p, SPush::War(_)).then_some(())).is_some(), "her own guild too");
    assert_eq!(code_of(soc(&mut ann, SReq::WarDeclare { hero: ha, foe: "Pale Court".into(), field: 2 })), code::REFUSED, "one war a tide");
    assert!(w.gw.social.wars_for(2, v.tide).is_empty(), "not fought until accepted");
    // The declarer cannot accept; the other guild's leader does.
    assert_eq!(code_of(soc(&mut ann, SReq::WarAnswer { hero: ha, war: v.id, accept: true })), code::BAD_REQUEST);
    assert_eq!(code_of(soc(&mut cat, SReq::WarAnswer { hero: hc, war: v.id, accept: false })), code::REFUSED);
    ok(soc(&mut bob, SReq::WarAnswer { hero: hb, war: v.id, accept: true }));
    let acc = push_of(&mut ann, |p| if let SPush::War(x) = p { x.accepted.then(|| x.clone()) } else { None }).expect("accepted");
    assert_eq!(acc.id, v.id);
    let Resp::Social(SResp::Wars(list)) = soc(&mut bob, SReq::WarList { hero: hb }) else { panic!() };
    assert_eq!(list, vec![WarView { accepted: true, ..v.clone() }]);
    // What a field copy of THE MOON MARSH is told before the tide, and the guild of a member.
    assert_eq!(w.gw.social.wars_for(2, v.tide), vec![(v.id, ga, gb)]);
    assert_eq!((w.gw.social.guild_of_account(cat.account), w.gw.social.guild_of_account(bob.account)), (ga, gb));
    // Kept through a restart.
    let again = realm_gateway::social::Social::default();
    again.persist(std::path::Path::new(&format!("{}.social", w.db.display()))).unwrap();
    assert_eq!(again.wars_for(2, v.tide), vec![(v.id, ga, gb)]);
    // The field's result: both guilds hear the winner; the war is done.
    assert!(w.gw.social.war_result(v.id, 0, [900, 40]));
    assert!(!w.gw.social.war_result(v.id, 0, [900, 40]), "a second copy's report is ignored");
    for p in [&mut ann, &mut bob] {
        let r = push_of(p, |x| if let SPush::WarResult { war, winner, held } = x { Some((*war, *winner, *held)) } else { None });
        assert_eq!(r, Some((v.id, ga, [900, 40])));
    }
    let Resp::Social(SResp::Wars(list)) = soc(&mut ann, SReq::WarList { hero: ha }) else { panic!() };
    assert!(list.is_empty());
    // Declared again and called off by the other side.
    let Resp::Social(SResp::WarDeclared(v2)) = soc(&mut ann, SReq::WarDeclare { hero: ha, foe: "Pale Court".into(), field: 4 }) else { panic!() };
    ok(soc(&mut bob, SReq::WarAnswer { hero: hb, war: v2.id, accept: false }));
    assert_eq!(push_of(&mut ann, |p| if let SPush::WarOff { war } = p { Some(*war) } else { None }), Some(v2.id));
    let Resp::Social(SResp::Wars(list)) = soc(&mut ann, SReq::WarList { hero: ha }) else { panic!() };
    assert!(list.is_empty());
    let again = realm_gateway::social::Social::default();
    again.persist(std::path::Path::new(&format!("{}.social", w.db.display()))).unwrap();
    assert!(again.wars_for(2, v.tide).is_empty() && again.wars_for(4, v2.tide).is_empty(), "ended and called-off wars stay gone");
}

fn ok(r: Resp) {
    assert_eq!(r, Resp::Ok);
}

#[test]
fn a_duel_is_challenged_declined_accepted_and_fought_to_a_result_for_both() {
    let w = world("duel");
    let (mut ann, mut bob, mut cat) = (player(&w, "ann", "Annie"), player(&w, "bob", "Bobby"), player(&w, "cat", "Catty"));
    let (ha, hb, hc) = (ann.hero, bob.hero, cat.hero);
    assert_eq!(code_of(soc(&mut ann, SReq::Duel { hero: ha, op: duel_op::CHALLENGE, name: "Annie".into() })), code::BAD_REQUEST);
    assert_eq!(code_of(soc(&mut bob, SReq::Duel { hero: hb, op: duel_op::ACCEPT, name: "Annie".into() })), code::MISSING, "no challenge yet");
    // Challenge and decline.
    ok(soc(&mut ann, SReq::Duel { hero: ha, op: duel_op::CHALLENGE, name: "Bobby".into() }));
    assert_eq!(push_of(&mut bob, |p| if let SPush::DuelChallenge { from, name } = p { Some((*from, name.clone())) } else { None }), Some((ha, "Annie".into())));
    ok(soc(&mut bob, SReq::Duel { hero: hb, op: duel_op::DECLINE, name: "Annie".into() }));
    assert_eq!(push_of(&mut ann, |p| if let SPush::DuelDeclined { name } = p { Some(name.clone()) } else { None }), Some("Bobby".into()));
    // Challenge and accept: both are told the duel and the yard's seed.
    ok(soc(&mut ann, SReq::Duel { hero: ha, op: duel_op::CHALLENGE, name: "Bobby".into() }));
    assert!(push_of(&mut bob, |p| matches!(p, SPush::DuelChallenge { .. }).then_some(())).is_some());
    ok(soc(&mut bob, SReq::Duel { hero: hb, op: duel_op::ACCEPT, name: "Annie".into() }));
    let sa = push_of(&mut ann, |p| if let SPush::DuelStart { duel, foe, seed, .. } = p { Some((*duel, *foe, *seed)) } else { None }).unwrap();
    let sb = push_of(&mut bob, |p| if let SPush::DuelStart { duel, foe, seed, .. } = p { Some((*duel, *foe, *seed)) } else { None }).unwrap();
    assert_eq!((sa.0, sa.1, sa.2), (sb.0, hb, sb.2));
    assert_eq!(sb.1, ha);
    assert!(w.gw.social.in_duel(ha) && w.gw.social.in_duel(hb) && !w.gw.social.in_duel(hc));
    assert_eq!(code_of(soc(&mut cat, SReq::Duel { hero: hc, op: duel_op::CHALLENGE, name: "Annie".into() })), code::BUSY);
    // They walk at each other (east and west) and fight; the steps are run here as well as by the town's ticker.
    assert_eq!(ann.c.call(Req::TownInput { dir: 3 }).unwrap(), Resp::Ok);
    assert_eq!(bob.c.call(Req::TownInput { dir: 7 }).unwrap(), Resp::Ok);
    let mut result = None;
    for _ in 0..realm_core::pvp::DUEL_TICKS {
        if let Some(r) = w.gw.social.run_duels().into_iter().next() {
            result = Some(r);
            break;
        }
        if !w.gw.social.in_duel(ha) {
            break;
        }
    }
    let ra = push_of(&mut ann, |p| if let SPush::DuelResult { duel, winner, loser, draw } = p { Some((*duel, *winner, *loser, *draw)) } else { None }).expect("a result for her");
    let rb = push_of(&mut bob, |p| if let SPush::DuelResult { duel, winner, loser, draw } = p { Some((*duel, *winner, *loser, *draw)) } else { None }).expect("a result for him");
    assert_eq!(ra, rb);
    assert_eq!(ra.0, sa.0);
    assert!((ra.1, ra.2) == (ha, hb) || (ra.1, ra.2) == (hb, ha));
    if let Some(r) = result {
        assert_eq!(r, ra);
    }
    assert!(!w.gw.social.in_duel(ha) && !w.gw.social.in_duel(hb));
}

#[test]
fn a_duellist_who_leaves_forfeits() {
    let w = world("forfeit");
    let (mut ann, mut bob) = (player(&w, "ann", "Annie"), player(&w, "bob", "Bobby"));
    let (ha, hb) = (ann.hero, bob.hero);
    ok(soc(&mut ann, SReq::Duel { hero: ha, op: duel_op::CHALLENGE, name: "Bobby".into() }));
    assert!(push_of(&mut bob, |p| matches!(p, SPush::DuelChallenge { .. }).then_some(())).is_some());
    ok(soc(&mut bob, SReq::Duel { hero: hb, op: duel_op::ACCEPT, name: "Annie".into() }));
    assert!(push_of(&mut ann, |p| matches!(p, SPush::DuelStart { .. }).then_some(())).is_some());
    drop(bob);
    let mut r = None;
    for _ in 0..200 {
        if let Some(x) = w.gw.social.run_duels().into_iter().next() {
            r = Some(x);
            break;
        }
        if !w.gw.social.in_duel(ha) {
            break;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    let got = r.or_else(|| push_of(&mut ann, |p| if let SPush::DuelResult { duel, winner, loser, draw } = p { Some((*duel, *winner, *loser, *draw)) } else { None }));
    let (_, winner, loser, draw) = got.expect("the duel ends");
    assert_eq!((winner, loser, draw), (ha, hb, false));
}

#[test]
fn the_mark_and_its_wait_are_kept_between_outings_and_restarts() {
    let w = world("marks");
    let s = &w.gw.social;
    let now = 1_000_000i64;
    let mut o = Outing::new();
    s.outing_mark(7, now, &mut o);
    assert_eq!((o.marked, o.struck_ago), (false, NEVER), "nothing in the book: unmarked");
    // She left the field marked, having struck a hero 100 ticks (5 s) before.
    s.note_mark(7, true, 100, now);
    let mut o = Outing::new();
    s.outing_mark(7, now + 10_000, &mut o);
    assert_eq!((o.marked, o.struck_ago), (true, 100 + 200), "ten seconds later the wait has run 300 ticks");
    // Ten minutes after the strike, the wait is over (but she is still marked).
    let mut o = Outing::new();
    s.outing_mark(7, now + 600_000, &mut o);
    assert_eq!((o.marked, o.struck_ago), (true, NEVER));
    // Kept through a restart.
    let again = realm_gateway::social::Social::default();
    again.persist(std::path::Path::new(&format!("{}.social", w.db.display()))).unwrap();
    let mut o = Outing::new();
    again.outing_mark(7, now + 10_000, &mut o);
    assert_eq!((o.marked, o.struck_ago), (true, 300));
    // Put down.
    s.note_mark(7, false, NEVER, now + 700_000);
    let mut o = Outing::new();
    s.outing_mark(7, now + 700_000, &mut o);
    assert_eq!((o.marked, o.struck_ago), (false, NEVER));
}
