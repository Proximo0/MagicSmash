//! Guild wars through the lockstep wire (job R3b): a war armed by a tick record reaches two copies of a field and a
//! follower, the guild of each join travels in its record, the follower's hash equals the host's through the war's
//! begin and end, a copy opened during the war begins it at once, and a hero moved between copies keeps her tag.

use realm_core::pvp::{WAR_BEGIN, WAR_END};
use realm_core::tables::TIDE_LEN;
use realm_core::{tide_start, Event, Field, Outing, Sheet};
use realm_server::host::transfer_of;
use realm_server::lockstep::{Lockstep, TickRec, WarArm};
use realm_server::sim::{JoinReq, Sim, SimOpts, NCOL};

const F: u8 = 3;
const G1: u64 = 0xA11CE;
const G2: u64 = 0xB0B;
const WAR: u64 = 77;

fn sim(seed: u64, clock: u64) -> Sim {
    let mut s = Sim::new(&SimOpts { field: F, seed, monsters: 300, threads: 1, bots: 0, rally_permille: 0, level: 0, vault: None });
    s.next_clock = Some(clock);
    s
}

fn hero(x: i32, y: i32, guild: u64) -> JoinReq {
    JoinReq { sheet: Sheet::bench(1, 0, 60), outing: Outing::new(), x, y, guild }
}

/// One tick of the host; the follower applies the same record from its bytes and must hash the same.
fn tick(s: &mut Sim, joins: &[JoinReq], leaves: &[u16], follower: Option<&mut (Field, Lockstep)>) -> Vec<u16> {
    let mut row = [0f64; NCOL];
    let ids = s.tick(joins, leaves, &[], &mut row);
    if let Some((ff, fl)) = follower {
        let (t, bytes) = s.history.back().unwrap();
        let rec = TickRec::decode(*t, bytes).expect("the record decodes");
        assert!(fl.apply(ff, &rec, |_| {}), "the follower applies tick {t}");
        assert_eq!(ff.hash(), s.field.hash(), "follower hash at tick {t}");
    }
    ids
}

fn war_events(f: &Field) -> Vec<(u64, u8, [u32; 2])> {
    f.events().iter().filter_map(|e| if let Event::War { war, state, held, .. } = *e { Some((war, state, held)) } else { None }).collect()
}

#[test]
fn a_war_armed_by_record_reaches_two_copies_and_a_follower_keeps_the_hash_through_it() {
    let start = tide_start(F, 0);
    let (mut a, mut b) = (sim(9, start - 40), sim(9, start - 40));
    tick(&mut a, &[], &[], None);
    tick(&mut b, &[], &[], None);
    let mut fo = Lockstep::from_state(&a.ls.state_bytes(&a.field), 1).expect("a follower joins");
    // Copy a: one of guild 1 at each altar, two of guild 2 by the heart. Copy b: one of each.
    let alt = a.field.terrain().altars;
    let (hx, hy) = a.field.terrain().heart;
    let mut joins: Vec<JoinReq> = alt.iter().map(|&(x, y)| hero(x, y, G1)).collect();
    joins.push(hero(hx, hy, G2));
    joins.push(hero(hx, hy, 0));
    let ids = tick(&mut a, &joins, &[], Some(&mut fo));
    tick(&mut b, &[hero(hx, hy, G1), hero(hx, hy, G2)], &[], None);
    for (id, j) in ids.iter().zip(&joins) {
        assert_eq!((a.field.guild(*id), fo.0.guild(*id)), (j.guild, j.guild), "the join's guild on the host and the follower");
    }
    // Armed on both copies with the next record; the follower arms it too.
    let arm = WarArm { id: WAR, a: G1, b: G2, tide: 0 };
    a.next_wars.push(arm);
    b.next_wars.push(arm);
    tick(&mut a, &[], &[], Some(&mut fo));
    tick(&mut b, &[], &[], None);
    for f in [&a.field, &b.field, &fo.0] {
        assert_eq!(f.wars().iter().map(|w| (w.id, w.guilds, w.tide, w.on)).collect::<Vec<_>>(), vec![(WAR, [G1, G2], 0, false)]);
    }
    // The tide begins the war on both copies.
    let (mut began_a, mut began_b) = (false, false);
    for _ in 0..80 {
        tick(&mut a, &[], &[], Some(&mut fo));
        tick(&mut b, &[], &[], None);
        began_a |= war_events(&a.field).contains(&(WAR, WAR_BEGIN, [0, 0]));
        began_b |= war_events(&b.field).contains(&(WAR, WAR_BEGIN, [0, 0]));
    }
    assert!(began_a && began_b, "the war begins in both copies");
    // A hero of guild 2 joins during the war: her tag comes in the record.
    let late = tick(&mut a, &[hero(hx, hy, G2)], &[], Some(&mut fo))[0];
    assert_eq!((a.field.guild(late), fo.0.guild(late)), (G2, G2));
    for _ in 0..300 {
        tick(&mut a, &[], &[], Some(&mut fo));
    }
    // To the tide's end (the clock jump is in the record, so the follower follows).
    a.next_clock = Some(start + TIDE_LEN as u64 - 5);
    b.next_clock = Some(start + TIDE_LEN as u64 - 5);
    let (mut end_a, mut end_b) = (None, None);
    for _ in 0..40 {
        tick(&mut a, &[], &[], Some(&mut fo));
        tick(&mut b, &[], &[], None);
        end_a = end_a.or(war_events(&a.field).into_iter().find(|e| e.1 == WAR_END));
        end_b = end_b.or(war_events(&b.field).into_iter().find(|e| e.1 == WAR_END));
    }
    let (end_a, end_b) = (end_a.expect("the war ends in copy a"), end_b.expect("the war ends in copy b"));
    assert!(end_a.2[0] > 0 && end_a.2[1] == 0, "guild 1 held the altars of copy a alone: {:?}", end_a.2);
    assert_eq!(end_b.0, WAR);
    assert!(a.field.wars().is_empty() && b.field.wars().is_empty() && fo.0.wars().is_empty());
}

#[test]
fn a_copy_opened_during_the_war_begins_it_at_once_and_a_moved_hero_keeps_her_guild() {
    let start = tide_start(F, 0);
    let mut a = sim(4, start + 100);
    tick(&mut a, &[], &[], None);
    let (hx, hy) = a.field.terrain().heart;
    let id = tick(&mut a, &[hero(hx, hy, G1)], &[], None)[0];
    // A copy that opens with the tide running is armed and begins the war in that very tick.
    a.next_wars.push(WarArm { id: WAR, a: G1, b: G2, tide: 0 });
    tick(&mut a, &[], &[], None);
    assert!(a.field.wars()[0].on);
    assert!(war_events(&a.field).contains(&(WAR, WAR_BEGIN, [0, 0])));
    // A merge: she leaves copy a for copy c (also at war) with her guild from the gateway.
    let mut c = sim(4, start + 100);
    tick(&mut c, &[], &[], None);
    let mut fo = Lockstep::from_state(&c.ls.state_bytes(&c.field), 1).unwrap();
    c.next_wars.push(WarArm { id: WAR, a: G1, b: G2, tide: 0 });
    tick(&mut c, &[], &[], Some(&mut fo));
    let tr = transfer_of(&a.field, id).expect("she is in copy a");
    tick(&mut a, &[], &[id], None);
    let (x, y) = c.field.ring_point(tr.ring, 1);
    let moved = tick(&mut c, &[JoinReq { sheet: tr.sheet, outing: tr.outing, x, y, guild: G1 }], &[], Some(&mut fo))[0];
    assert_eq!((c.field.guild(moved), fo.0.guild(moved)), (G1, G1));
    assert!(c.field.wars()[0].on && fo.0.wars()[0].on, "the war goes on where she arrives");
    // Arming twice is refused the same way on the host and the follower (the hash stays equal).
    c.next_wars.push(WarArm { id: WAR, a: G1, b: G2, tide: 0 });
    tick(&mut c, &[], &[], Some(&mut fo));
    assert_eq!(c.field.wars().len(), 1);
}
