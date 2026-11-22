//! One test per monster behaviour (rules section 4).
mod common;
use common::*;

/// Steps with the listed heroes' weapons held (they never fire).
fn still(f: &mut Field, ids: &[u16], inputs: &[u16]) {
    for &i in ids {
        f.hero_mut(i).charge = 0;
    }
    f.step(inputs);
}

fn setup(field: u8, class: u8, level: u8) -> (Field, u16, i32, i32) {
    let mut f = quiet(field);
    let (x, y) = spot(&f, 40);
    let id = add(&mut f, &bare(class, level), x, y);
    warm(&mut f);
    (f, id, x, y)
}

fn taken(f: &Field, id: u16, raw: u32) -> u32 {
    (raw as u64 * f.mods(id).unwrap().taken / POWER_ONE) as u32
}

#[test]
fn walker_follows_the_flow_and_hits_on_contact_every_10_ticks() {
    let (mut f, id, x, y) = setup(2, 0, 1);
    let w = mon(&mut f, kind("drowned"), 1, x + px(300), y);
    for _ in 0..40 {
        still(&mut f, &[id], &[]);
    }
    let m = f.monsters();
    let moved = (x + px(300)) - m.x[w as usize];
    let step = KINDS[kind("drowned") as usize].speed as i32 * SUB / TICK_HZ as i32;
    // It starts by steering to its cell's centre, then walks at its speed.
    assert!(moved >= step * 30 && moved <= step * 41, "moved {moved}, step {step}");
    // Contact: next to her it hits once per 10 ticks, for its damage after her reductions.
    f.monsters_mut().x[w as usize] = x + px(10);
    f.monsters_mut().y[w as usize] = y;
    let mut hits = Vec::new();
    for _ in 0..30 {
        let before = f.heroes()[id as usize].health;
        still(&mut f, &[id], &[]);
        let after = f.heroes()[id as usize].health;
        if after < before {
            hits.push((f.tick(), before - after));
        }
    }
    assert_eq!(hits.len(), 3, "{hits:?}");
    assert!(hits.iter().all(|&(t, _)| (t + id as u32) % CONTACT_EVERY == 0));
    let raw = f.monsters().damage(w as usize);
    assert_eq!(hits[0].1, taken(&f, id, raw));
}

#[test]
fn swarm_is_born_in_clutches_of_8() {
    let mut f = Field::open(0, 5, Config { monsters: 3000, threads: 1 });
    f.join(&Sheet::bench(1, 0, 10), &Outing::new(), FIELD / 2, FIELD / 2);
    let rat = kind("plague rat");
    let mut best = 0;
    for _ in 0..3 {
        f.step::<u16>(&[]);
        let m = f.monsters();
        let s = f.last_spawns();
        let mut k = 0;
        while k < s.len() {
            let i = s[k] as usize;
            if m.kind[i] != rat {
                k += 1;
                continue;
            }
            let mut run = 1;
            while k + run < s.len()
                && m.kind[s[k + run] as usize] == rat
                && dist(m.x[i], m.y[i], m.x[s[k + run] as usize], m.y[s[k + run] as usize]) <= px(3 * 18) as i64
            {
                run += 1;
            }
            best = best.max(run);
            k += run;
        }
    }
    assert_eq!(best, SWARM_CLUTCH as usize);
    assert_eq!(KINDS[kind("wood wolf") as usize].clutch, 4);
    assert_eq!(KINDS[kind("pit hound") as usize].clutch, 4);
}

#[test]
fn runner_sprints_at_double_speed_for_1_s_within_160_px_then_rests_2_s() {
    let (mut f, id, x, y) = setup(2, 0, 1);
    let c = mon(&mut f, kind("carrion crow"), 60, x - px(150), y);
    let step = KINDS[kind("carrion crow") as usize].speed as i32 * SUB / TICK_HZ as i32;
    let mut moves = Vec::new();
    for _ in 0..64 {
        let x0 = f.monsters().x[c as usize];
        // She walks east, so it chases without catching her.
        still(&mut f, &[id], &[1]);
        moves.push(f.monsters().x[c as usize] - x0);
    }
    let sprint = moves.iter().take(20).filter(|&&d| d >= step * 17 / 10).count();
    let rest = moves.iter().skip(20).take(40).filter(|&&d| d <= step + 2).count();
    assert_eq!(sprint, 20, "{moves:?}");
    assert_eq!(rest, 40, "{moves:?}");
}

#[test]
fn brute_cannot_be_pushed_stunned_or_slowed() {
    let (mut f, id, x, y) = setup(2, PALADIN, 25);
    let b = mon(&mut f, kind("corpse barge"), 60, x + px(30), y);
    let w = mon(&mut f, kind("drowned"), 60, x - px(30), y);
    f.step(&[IN_SKILL2]);
    let m = f.monsters();
    assert_eq!(m.stun[b as usize], 0);
    assert!(m.stun[w as usize] > 0);
    // Pushes and slows.
    let (mut f, id2, x, y) = setup(2, KNIGHT, 10);
    let b = mon(&mut f, kind("corpse barge"), 60, x + px(40), y);
    let w = mon(&mut f, kind("drowned"), 60, x + px(40), y + px(8));
    let (bx, wx) = (f.monsters().x[b as usize], f.monsters().x[w as usize]);
    for i in [b, w] {
        f.monsters_mut().stun[i as usize] = 200;
    }
    f.hero_mut(id2).charge = 1_000;
    f.step::<u16>(&[]);
    assert_eq!(f.monsters().x[b as usize], bx, "brute pushed");
    assert!(f.monsters().x[w as usize] > wx + px(8), "walker not pushed");
    let _ = id;
    let mut s = quiet(2);
    let (x, y) = spot(&s, 40);
    let a = add(&mut s, &bare(ARCHER, 25), x, y);
    warm(&mut s);
    let b = mon(&mut s, kind("corpse barge"), 60, x - px(10), y);
    let w = mon(&mut s, kind("drowned"), 60, x - px(10), y + px(5));
    s.hero_mut(a).dir = 1;
    s.step(&[IN_SKILL2]);
    s.step::<u16>(&[]);
    assert_eq!(s.monsters().slow[b as usize], 0);
    assert!(s.monsters().slow[w as usize] > 0);
}

#[test]
fn shielded_takes_30_percent_less_from_the_front() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 40);
    let a = add(&mut f, &bare(ARCHER, 10), x, y);
    let b = add(&mut f, &bare(PRIEST, 10), x + px(470), y);
    warm(&mut f);
    let wight = kind("bark wight");
    let w1 = mon(&mut f, wight, 60, x + px(100), y);
    let w2 = mon(&mut f, wight, 60, x + px(340), y);
    let hp0 = (f.monsters().hp[w1 as usize], f.monsters().hp[w2 as usize]);
    f.hero_mut(a).charge = 10_000;
    for i in [w1, w2] {
        f.monsters_mut().stun[i as usize] = 200;
    }
    f.hero_mut(b).charge = 0;
    f.step::<u16>(&[]);
    let lost1 = hp0.0 - f.monsters().hp[w1 as usize];
    let lost2 = hp0.1 - f.monsters().hp[w2 as usize];
    assert!(lost2 > 0);
    assert_eq!(lost1, lost2 * SHIELD_FRONT_TAKEN_PCT / 100, "front {lost1} back {lost2}");
}

#[test]
fn burster_bursts_40_px_for_double_damage_after_10_ticks() {
    let (mut f, id, x, y) = setup(2, KNIGHT, 25);
    let k = kind("bloated pilgrim");
    let b = mon(&mut f, k, 1, x + px(30), y);
    let dmg = f.monsters().damage(b as usize);
    let mut died = None;
    for _ in 0..40 {
        f.step::<u16>(&[]);
        if died.is_none() && f.events().iter().any(|e| matches!(e, Event::Kill { kind, .. } if *kind == k)) {
            died = Some(f.tick());
            assert_eq!(f.shots().len(), 1);
            assert_eq!(f.shots()[0].px, BURST_PX);
            assert_eq!(f.shots()[0].dmg, dmg * BURST_DAMAGE_MUL);
        }
        if let Some(t) = died {
            if f.tick() == t + BURST_DELAY as u32 - 1 {
                let before = f.heroes()[id as usize].health;
                f.step::<u16>(&[]);
                let after = f.heroes()[id as usize].health;
                assert_eq!(before - after, taken(&f, id, dmg * BURST_DAMAGE_MUL));
                assert!(f.shots().is_empty());
                return;
            }
        }
    }
    panic!("never died");
}

#[test]
fn splitter_opens_into_4_of_its_smaller_kind() {
    let (mut f, _, x, y) = setup(2, KNIGHT, 30);
    let barge = kind("corpse barge");
    mon(&mut f, barge, 1, x + px(30), y);
    for _ in 0..60 {
        f.step::<u16>(&[]);
        if f.events().iter().any(|e| matches!(e, Event::Kill { kind, .. } if *kind == barge)) {
            let m = f.monsters();
            let kids: Vec<u32> = f.last_spawns().to_vec();
            assert_eq!(kids.len(), SPLIT_INTO as usize);
            assert!(kids.iter().all(|&i| m.kind[i as usize] == DROWNED && m.level[i as usize] == 1));
            return;
        }
    }
    panic!("never died");
}

#[test]
fn spitter_stops_at_150_px_and_throws_a_slow_bolt_every_2_s() {
    let (mut f, id, x, y) = setup(0, 0, 1);
    let s = mon(&mut f, kind("penitent"), 60, x + px(145), y);
    let x0 = f.monsters().x[s as usize];
    let mut thrown = Vec::new();
    let mut hurt = 0;
    for _ in 0..90 {
        let n = f.shots().len();
        still(&mut f, &[id], &[]);
        if f.shots().len() > n {
            thrown.push(f.tick());
            let sh = f.shots().last().unwrap();
            let v = ((sh.vx as i64).pow(2) + (sh.vy as i64).pow(2)).isqrt() as i32;
            assert!((v - SPIT_SPEED_PX_S * SUB / TICK_HZ as i32).abs() <= 2);
        }
        if f.heroes()[id as usize].hurt {
            hurt += 1;
        }
    }
    assert_eq!(f.monsters().x[s as usize], x0, "a spitter in range stands");
    assert!(thrown.len() >= 2 && thrown[1] - thrown[0] == SPIT_EVERY as u32, "{thrown:?}");
    assert!(hurt >= 2, "its bolts reach her");
}

#[test]
fn lobber_stops_at_250_px_and_lobs_a_50_px_circle_landing_after_1_s() {
    let (mut f, id, x, y) = setup(2, 0, 1);
    let l = mon(&mut f, kind("toadstone"), 60, x + px(240), y);
    let x0 = f.monsters().x[l as usize];
    for _ in 0..10 {
        let n = f.shots().len();
        still(&mut f, &[id], &[]);
        if f.shots().len() > n {
            let s = *f.shots().last().unwrap();
            assert_eq!((s.x, s.y, s.px, s.left), (x, y, LOB_PX, LOB_DELAY));
            let before = f.heroes()[id as usize].health;
            for _ in 0..LOB_DELAY {
                still(&mut f, &[id], &[]);
            }
            assert!(f.heroes()[id as usize].health < before, "the lob lands on her");
            assert_eq!(f.monsters().x[l as usize], x0);
            return;
        }
    }
    panic!("never lobbed");
}

#[test]
fn leaper_jumps_onto_the_hero_with_the_lowest_threat_every_5_s() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 40);
    let k = add(&mut f, &bare(KNIGHT, 10), x, y);
    let m = add(&mut f, &bare(MAGE, 10), x + px(60), y);
    warm(&mut f);
    let s = mon(&mut f, kind("noose spider"), 60, x - px(100), y);
    f.hero_mut(k).charge = 0;
    f.hero_mut(m).charge = 0;
    f.step::<u16>(&[]);
    let (sx, sy) = (f.monsters().x[s as usize], f.monsters().y[s as usize]);
    let mh = &f.heroes()[m as usize];
    assert!(dist(sx, sy, mh.x, mh.y) <= px(STOP_PX + 1) as i64, "it lands by the mage");
    assert_eq!(f.monsters().timer[s as usize], LEAP_EVERY - 1);
}

fn cultist_speed(with_piper: bool) -> i32 {
    let (mut f, id, x, y) = setup(3, 0, 1);
    let c = mon(&mut f, kind("goat cultist"), 60, x + px(400), y);
    if with_piper {
        let p = mon(&mut f, kind("bone piper"), 60, x + px(450), y);
        f.monsters_mut().stun[p as usize] = 200;
    }
    let x0 = f.monsters().x[c as usize];
    still(&mut f, &[id], &[]);
    x0 - f.monsters().x[c as usize]
}

#[test]
fn howler_makes_monsters_within_100_px_20_percent_faster() {
    let (slow, fast) = (cultist_speed(false), cultist_speed(true));
    assert_eq!(fast, slow * HOWL_SPEED_PCT as i32 / 100, "{slow} {fast}");
}

#[test]
fn mender_heals_4_percent_every_2_s_without_stacking() {
    let (mut f, id, x, y) = setup(2, 0, 1);
    let d = mon(&mut f, kind("drowned"), 60, x + px(400), y);
    for k in 0..2 {
        let h = mon(&mut f, kind("bog hag"), 60, x + px(420), y + px(20 * k));
        f.monsters_mut().stun[h as usize] = 250;
    }
    f.monsters_mut().stun[d as usize] = 250;
    let max = f.monsters().max_hp(d as usize);
    f.monsters_mut().hp[d as usize] = max / 2;
    let mut heals = Vec::new();
    for _ in 0..85 {
        let before = f.monsters().hp[d as usize];
        still(&mut f, &[id], &[]);
        let after = f.monsters().hp[d as usize];
        if after > before {
            heals.push((f.tick(), after - before));
        }
    }
    assert_eq!(heals.len(), 2, "{heals:?}");
    assert!(heals.iter().all(|&(t, a)| t % MEND_EVERY == 0 && a == max * MEND_PCT / 100));
}

fn hero_step(with_wailer: bool) -> i32 {
    let (mut f, id, x, y) = setup(2, 0, 1);
    if with_wailer {
        let w = mon(&mut f, kind("marsh light"), 60, x - px(40), y);
        f.monsters_mut().stun[w as usize] = 250;
        still(&mut f, &[id], &[]);
    }
    let x0 = f.heroes()[id as usize].x;
    still(&mut f, &[id], &[1]);
    f.heroes()[id as usize].x - x0
}

#[test]
fn wailer_slows_heroes_within_80_px_by_20_percent() {
    let (free, slowed) = (hero_step(false), hero_step(true));
    let step = HERO_STEP;
    assert_eq!(free, step * 101 / 100, "a HUMAN has SWIFT 1");
    assert_eq!(slowed, step * (101 + WAIL_MOVE_PCT) / 100);
}

#[test]
fn drainer_heals_itself_for_the_damage_it_deals() {
    let (mut f, id, x, y) = setup(2, 0, 1);
    let l = mon(&mut f, kind("leech"), 60, x + px(10), y);
    f.monsters_mut().hp[l as usize] = 50;
    for _ in 0..12 {
        let (hb, mb) = (f.heroes()[id as usize].health, f.monsters().hp[l as usize]);
        still(&mut f, &[id], &[]);
        let (ha, ma) = (f.heroes()[id as usize].health, f.monsters().hp[l as usize]);
        if ha < hb {
            assert_eq!(ma - mb, hb - ha);
            return;
        }
    }
    panic!("never hit");
}
