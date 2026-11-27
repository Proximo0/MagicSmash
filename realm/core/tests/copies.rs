//! Copies of a field (rules section 11): a hero moves between copies with her outing state into the same ring,
//! every copy shares the clock, and a follower of the receiving copy stays on its hash.
mod common;
use common::*;

fn copy(seed: u64, clock: u64) -> Field {
    let mut f = Field::open(1, seed, Config { monsters: 2_000, threads: 2 });
    f.set_clock(clock);
    f
}

/// A veteran of an outing: cards, draws, coin, a draught drunk, effects, a banked waystone.
fn veteran(f: &mut Field, class: u8, x: i32, y: i32) -> u16 {
    let mut out = Outing::new();
    out.coin = 940;
    out.copies[3] = 2;
    out.copies[9] = 1;
    out.offers = vec![[1, 2, 3, 0]];
    out.draws = 12;
    out.cooldowns = [30, 0, 500];
    out.belt = Some([(P_HEALING, 1), (P_WHETSTONE, 2), (P_PHOENIX, 1)]);
    out.belt_rest = [100, 0, 0];
    out.fx[FX_AEGIS as usize] = 77;
    out.waystone = 4;
    out.health = Some(55);
    out.tide_contrib = 1_234;
    out.boss_contrib = 99;
    f.join(&Sheet::bench(class, ORC, 25), &out, x, y)
}

#[test]
fn a_hero_moves_with_everything_she_carries_into_the_same_ring() {
    for (ring, (x, y)) in
        [(RING_EDGE, (FIELD / 2, FIELD / 2 + px(7_000))), (RING_MIDDLE, (FIELD / 2 + px(4_200), FIELD / 2)), (RING_HEART, (FIELD / 2, FIELD / 2 - px(300)))]
    {
        let mut a = copy(1, 5_000);
        let mut b = copy(2, 5_000);
        let id = veteran(&mut a, MAGE, x, y);
        idle(&mut a, 5);
        idle(&mut b, 5);
        let before = a.heroes()[id as usize].clone();
        let outing = a.outing(id).unwrap();
        let t = a.transfer_out(id).expect("she is there");
        assert_eq!(t.ring, ring);
        assert!(!a.heroes()[id as usize].present, "gone from the first copy");
        assert!(a.transfer_out(id).is_none());
        let nid = b.transfer_in(&t, 42);
        let h = &b.heroes()[nid as usize];
        assert_eq!(ring_of(h.x, h.y), ring, "same ring");
        assert!(!b.terrain().wall(h.x, h.y));
        assert_eq!(b.outing(nid).unwrap(), outing, "her outing is as she left it");
        assert_eq!(h.sheet, before.sheet);
        for (name, got, want) in [
            ("coin", h.coin as i64, before.coin as i64),
            ("health", h.health as i64, before.health as i64),
            ("draws", h.draws as i64, 12),
            ("tide", h.tide_contrib as i64, 1_234),
            ("boss", h.boss_contrib as i64, 99),
        ] {
            assert_eq!(got, want, "{name}");
        }
        assert_eq!(h.copies[3], 2);
        assert_eq!(h.offers, vec![[1, 2, 3, 0]]);
        assert_eq!(h.cooldowns, before.cooldowns, "cooldowns carried");
        assert_eq!(h.waystone, 4);
        assert_eq!(h.belt[2], (P_PHOENIX, 1));
    }
}

#[test]
fn arrival_points_follow_the_seed_the_tick_and_the_salt_only() {
    let a = copy(1, 0);
    let b = copy(1, 0);
    for ring in [RING_EDGE, RING_MIDDLE, RING_HEART] {
        let mut seen = Vec::new();
        for salt in 0..20u64 {
            let p = a.ring_point(ring, salt);
            assert_eq!(p, b.ring_point(ring, salt), "the same on every machine");
            assert_eq!(ring_of(p.0, p.1), ring);
            assert!(!a.terrain().wall(p.0, p.1));
            seen.push(p);
        }
        seen.sort_unstable();
        seen.dedup();
        assert!(seen.len() >= 15, "salts spread arrivals ({} of 20)", seen.len());
    }
    // Drawing a point does not touch the field's own stream.
    let h = a.hash();
    let _ = a.ring_point(RING_MIDDLE, 3);
    assert_eq!(a.hash(), h);
}

#[test]
fn a_follower_of_the_receiving_copy_stays_on_its_hash_through_the_move() {
    let mut a = copy(1, tide_start(1, 0) - 200);
    let mut b = copy(2, tide_start(1, 0) - 200);
    for i in 0..30i32 {
        a.join(&Sheet::bench(1 + (i % 5) as u8, 0, 15), &Outing::new(), FIELD / 2 + px(i * 30 - 400), FIELD / 2 + px(3_000));
        b.join(&Sheet::bench(1 + (i % 5) as u8, 1, 15), &Outing::new(), FIELD / 2 + px(i * 30 - 400), FIELD / 2 - px(3_000));
    }
    let inputs: Vec<u16> = (0..30).map(|i| (i % 9) as u16 | IN_SKILL1).collect();
    for _ in 0..300 {
        a.step(&inputs);
        b.step(&inputs);
    }
    assert!(b.tide() && a.tide(), "both copies are mid-tide: the clock is shared");
    // A client joins B now, from bytes, and follows.
    let mut follower = Field::from_bytes(&b.to_bytes(), 1).expect("loads");
    assert_eq!(follower.hash(), b.hash());
    // Ten heroes of A move to B, one a tick, then everyone fights on.
    let mut moved = Vec::new();
    for k in 0..10u16 {
        a.step(&inputs);
        b.step(&inputs);
        follower.step(&inputs);
        let t = a.transfer_out(k).unwrap();
        let nid = b.transfer_in(&t, 1_000 + k as u64);
        let nid2 = follower.transfer_in(&t, 1_000 + k as u64);
        assert_eq!(nid, nid2, "the same slot on both");
        moved.push(nid);
        assert_eq!(b.hash(), follower.hash(), "right after move {k}");
    }
    let mut inputs: Vec<u16> = (0..45).map(|i| (i % 9) as u16 | IN_SKILL1).collect();
    inputs.truncate(b.heroes().len());
    for t in 0..400 {
        b.step(&inputs);
        follower.step(&inputs);
        assert_eq!(b.hash(), follower.hash(), "tick {t} after the moves");
    }
    assert!(moved.iter().all(|&m| b.heroes()[m as usize].present));
    assert_eq!(a.player_count(), 20);
    assert_eq!(b.player_count(), 40);
}

#[test]
fn every_copy_of_a_field_surges_and_meets_its_boss_together() {
    let start = tide_start(1, 3) - 1;
    let mut copies: Vec<Field> = (0..3).map(|i| copy(10 + i, start)).collect();
    for (k, f) in copies.iter_mut().enumerate() {
        f.set_births(false);
        for i in 0..(5 + 3 * k) as i32 {
            f.join(&Sheet::bench(KNIGHT, HUMAN, 15), &Outing::new(), FIELD / 2 + px(i * 10), FIELD / 2);
        }
    }
    let mut begins = vec![Vec::new(); 3];
    let mut rises = vec![Vec::new(); 3];
    for t in 1..=40u32 + 30 {
        if t == 4 {
            // Ten minutes later on the shared clock, as the boss rises.
            for f in copies.iter_mut() {
                f.set_clock(field_boss_window(1, 3).0 - 10);
            }
        }
        for (k, f) in copies.iter_mut().enumerate() {
            f.step::<u16>(&[]);
            for e in f.events() {
                match e {
                    Event::Tide { state: TIDE_BEGIN, .. } => begins[k].push(t),
                    Event::Boss { state: BOSS_RISES, health, .. } => rises[k].push((t, *health)),
                    _ => {}
                }
            }
        }
    }
    assert_eq!(begins, vec![vec![1u32]; 3], "all three begin on the same tick");
    assert!(rises.iter().all(|r| r.len() == 1 && r[0].0 == rises[0][0].0), "and the boss rises on the same tick: {rises:?}");
    // Each copy's boss is its own, fixed by the heroes in its heart.
    assert!(rises[0][0].1 < rises[1][0].1 && rises[1][0].1 < rises[2][0].1, "{rises:?}");
}

#[test]
fn a_downed_hero_moves_up_and_the_move_changes_no_rule_for_the_ones_left_behind() {
    let mut a = copy(1, 0);
    let mut b = copy(2, 0);
    a.set_births(false);
    let (x, y) = (FIELD / 2, FIELD / 2 + px(3_000));
    let down = a.join(&Sheet::bench(KNIGHT, HUMAN, 15), &Outing::new(), x, y);
    let stay = a.join(&Sheet::bench(PRIEST, HUMAN, 15), &Outing::new(), x + px(500), y);
    a.hero_mut(down).health = 0;
    a.hero_mut(down).downed = 100;
    idle(&mut a, 3);
    let t = a.transfer_out(down).unwrap();
    assert!(t.outing.health.unwrap() >= 1);
    let nid = b.transfer_in(&t, 5);
    assert!(b.heroes()[nid as usize].alive(), "she arrives up");
    assert!(a.heroes()[stay as usize].alive());
    assert_eq!(a.heroes_by_ring(), [0, 1, 0]);
    // The freed slot is the lowest free one for the next arrival.
    let t2 = b.transfer_out(nid).unwrap();
    assert_eq!(a.transfer_in(&t2, 6), down);
}
