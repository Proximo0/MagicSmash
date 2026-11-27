//! Tides and altars (rules section 8): the schedule, the surge, the altars, the verdict and the cache.
mod common;
use common::*;

pub const TIDE: u8 = 12;
pub const ALTAR: u8 = 13;
pub const BOSS_EV: u8 = 14;
pub const REWARD: u8 = 15;

/// A quiet field whose clock stands `before` ticks before its `n`-th tide.
fn before_tide(field: u8, n: u32, before: u64) -> Field {
    let mut f = quiet(field);
    f.set_clock(tide_start(field, n) - before);
    f
}

fn tide_events(f: &Field) -> Vec<(u8, u32)> {
    f.events().iter().filter_map(|e| if let Event::Tide { state, index } = e { Some((*state, *index)) } else { None }).collect()
}

fn altar_events(f: &Field) -> Vec<(u8, u8)> {
    f.events().iter().filter_map(|e| if let Event::Altar { index, state } = e { Some((*index, *state)) } else { None }).collect()
}

/// Joins a hero standing on altar `a` of the field.
fn on_altar(f: &mut Field, a: usize, class: u8) -> u16 {
    let (x, y) = f.terrain().altars[a];
    add(f, &bare(class, 10), x, y)
}

fn lit(f: &Field) -> Vec<usize> {
    (0..6).filter(|&a| f.altars()[a].state == ALTAR_LIT).collect()
}

#[test]
fn the_schedule_staggers_six_fields_and_every_tide_is_five_minutes_in_thirty() {
    for field in 0..6u8 {
        let first = tide_start(field, 0);
        assert_eq!(first, 12_000 + 3_600 * field as u64, "field {field}: 10 minutes in, 3 minutes apart");
        assert_eq!(tide_start(field, 1) - first, 36_000, "every 30 minutes");
        assert_eq!(tide_running(first - 1, field), None);
        assert_eq!(tide_running(first, field), Some(0));
        assert_eq!(tide_running(first + 5 * 60 * 20 - 1, field), Some(0), "five minutes long");
        assert_eq!(tide_running(first + 5 * 60 * 20, field), None);
        assert_eq!(tide_running(first + 36_000, field), Some(1));
        assert_eq!(tide_countdown(first - 100, field), (100, 0));
        assert_eq!(tide_countdown(first + 100, field), (0, 6_000 - 100));
        assert_eq!(tide_countdown(first + 7_000, field), (36_000 - 7_000, 0));
    }
    assert!(!boss_due(0) && !boss_due(2) && boss_due(3) && boss_due(7), "a boss after every fourth tide");
    let (rise, leave) = field_boss_window(0, 3);
    assert_eq!(rise, tide_start(0, 3) + 6_000 + 600, "30 seconds after the tide ends");
    assert_eq!(leave - rise, 9_600, "stays 8 minutes");
    assert_eq!(next_field_boss(0, 0), (3, rise));
}

#[test]
fn the_world_boss_rides_every_six_hours_in_turn_between_a_fields_tides_and_its_boss() {
    for k in 0..24u32 {
        let (field, start, end) = world_ride(k);
        assert_eq!(field as u32, k % 6, "in turn");
        assert_eq!(end - start, 18_000, "stays 15 minutes");
        assert!(start >= k as u64 * 432_000 && start < (k as u64 + 1) * 432_000, "every six hours");
        // Never over one of its own field's tides or field bosses.
        for n in 0..=(end / 36_000 + 1) as u32 {
            let (a, b) = (tide_start(field, n), tide_start(field, n) + 6_000);
            assert!(end <= a || start >= b, "ride {k} over a tide");
            if boss_due(n) {
                let (rise, leave) = field_boss_window(field, n);
                assert!(end <= rise || start >= leave, "ride {k} over a field boss");
            }
        }
    }
    let (k, field, start) = next_world_boss(0);
    assert_eq!((k, field), (0, 0));
    assert_eq!(start, world_ride(0).1);
    assert_eq!(next_world_boss(start + 1).0, 0, "running");
    assert_eq!(next_world_boss(world_ride(0).2).0, 1);
}

#[test]
fn a_tide_begins_once_lights_three_altars_and_ends_once() {
    let mut f = before_tide(0, 0, 3);
    let (sx, sy) = spot(&f, 8);
    add(&mut f, &bare(KNIGHT, 10), sx, sy);
    let mut begun = 0;
    let mut lit_events = 0;
    for _ in 0..6 {
        f.step::<u16>(&[]);
        begun += tide_events(&f).iter().filter(|e| e.0 == 0).count();
        lit_events += altar_events(&f).iter().filter(|e| e.1 == ALTAR_LIT).count();
    }
    assert!(f.tide(), "the tide runs");
    assert_eq!(begun, 1, "TIDE(begin) fires once");
    assert_eq!(lit_events, 3, "three altars light, once each");
    assert_eq!(lit(&f).len(), 3);
    // Run to the end: LOST once, the altars go dark once each.
    let (mut lost, mut dark) = (0, 0);
    for _ in 0..6_100 {
        f.step::<u16>(&[]);
        lost += tide_events(&f).iter().filter(|e| e.0 == TIDE_LOST).count();
        dark += altar_events(&f).iter().filter(|e| e.1 == ALTAR_OUT).count();
    }
    assert!(!f.tide());
    assert_eq!((lost, dark), (1, 3));
    assert_eq!(f.realm().result, TIDE_LOST);
}

#[test]
fn the_three_lit_altars_follow_the_seed_and_differ_between_tides() {
    let mut sets = Vec::new();
    for n in 0..4u32 {
        let mut f = before_tide(2, n, 1);
        f.step::<u16>(&[]);
        let l = lit(&f);
        assert_eq!(l.len(), 3);
        sets.push(l.clone());
        let mut g = before_tide(2, n, 1);
        g.step::<u16>(&[]);
        assert_eq!(lit(&g), l, "same seed, same altars");
    }
    assert!(sets.iter().any(|s| *s != sets[0]), "tides light different altars");
}

#[test]
fn the_target_doubles_in_a_tide_of_a_crowd_up_to_the_cap_and_not_for_a_small_party() {
    let run = |clock: u64, cap: u32, heroes: i32| {
        let mut f = Field::open(0, 5, Config { monsters: cap, threads: 1 });
        f.set_clock(clock);
        let (x, y) = spot(&f, 6);
        for i in 0..heroes {
            f.join(&Sheet::bench(KNIGHT, HUMAN, 10), &Outing::new(), x + px(i % 8 * 20), y + px(i / 8 * 20));
        }
        for _ in 0..300 {
            f.step::<u16>(&[]);
        }
        f.monster_count()
    };
    // A crowd of 40 (`TIDE_FULL_AT`): the contract's double.
    let calm = run(100, 4_000, 40);
    let tide = run(tide_start(0, 0) - 2, 4_000, 40);
    assert!(calm >= 400 && calm <= 2_000, "calm {calm}");
    assert!(tide > calm * 17 / 10, "a tide keeps about twice as many: {tide} vs {calm}");
    let capped = run(tide_start(0, 0) - 2, 600, 40);
    assert!(capped <= 600, "never past the cap: {capped}");
    // A party of four (`TIDE_FULL_FROM`): no more than calm.
    let (calm4, tide4) = (run(100, 4_000, 4), run(tide_start(0, 0) - 2, 4_000, 4));
    assert!(tide4 <= calm4 + calm4 / 10, "a small party's tide is not doubled: {tide4} vs {calm4}");
    assert_eq!(tide_target_pct(TIDE_FULL_FROM), 100);
    assert_eq!(tide_target_pct(TIDE_FULL_AT), TIDE_TARGET_MUL * 100);
    assert!(tide_target_pct(22) > 100 && tide_target_pct(22) < TIDE_TARGET_MUL * 100);
}

#[test]
fn monsters_move_a_fifth_faster_in_a_tide_and_for_two_minutes_after_a_lost_one() {
    // The walk of a scarecrow over 10 ticks, with the clock `clock` ticks in, after `run` ticks of warm-up.
    let walk = |clock: u64, run: u32| {
        let mut f = Field::open(0, 3, Config { monsters: 64, threads: 1 });
        f.set_births(false);
        f.set_clock(clock);
        let (x, y) = spot(&f, 20);
        let id = add(&mut f, &bare(KNIGHT, 10), x, y);
        guard(&mut f, id);
        f.step::<u16>(&[]);
        let m = mon(&mut f, kind("scarecrow"), 1, x + px(300), y);
        for _ in 0..run {
            f.hero_mut(id).fx[FX_AEGIS as usize] = 1_000;
            f.step::<u16>(&[]);
            f.monsters_mut().x[m as usize] = x + px(300);
            f.monsters_mut().y[m as usize] = y;
        }
        let x0 = f.monsters().x[m as usize];
        idle(&mut f, 10);
        (x0 - f.monsters().x[m as usize]).abs() as i64
    };
    let calm = walk(100, 12);
    let tide = walk(tide_start(0, 0) - 1, 12);
    assert!(tide * 100 >= calm * 118 && tide * 100 <= calm * 122, "{tide} vs {calm}");
    // A tide that runs out unwon: the horde stays quick for two minutes, then calm again.
    let end = tide_start(0, 0) + 6_000;
    assert_eq!(walk(end - 20, 20 + 60), tide, "quick just after a lost tide");
    assert_eq!(walk(end - 20, 20 + 2_400 - 30), tide, "still quick a little before two minutes");
    assert_eq!(walk(end - 20, 20 + 2_400 + 30), calm, "calm after two minutes");
}

#[test]
fn two_altars_held_win_the_tide_and_pay_the_cache() {
    let mut f = before_tide(0, 0, 1);
    f.step::<u16>(&[]);
    let l = lit(&f);
    let (a, b) = (on_altar(&mut f, l[0], KNIGHT), on_altar(&mut f, l[1], MAGE));
    let third = on_altar(&mut f, l[2], PRIEST);
    for h in [a, b, third] {
        f.hero_mut(h).tide_contrib = 100_000;
    }
    f.hero_mut(third).tide_contrib = 0;
    let coin0 = f.heroes()[a as usize].coin;
    let (mut held_at, mut won_at) = (Vec::new(), None);
    let mut rewards = Vec::new();
    for t in 1..=1_300u32 {
        f.step::<u16>(&[]);
        for (i, s) in altar_events(&f) {
            if s == ALTAR_HELD {
                held_at.push((t, i));
            }
        }
        if tide_events(&f).iter().any(|e| e.0 == TIDE_WON) {
            won_at = Some(t);
        }
        for e in f.events() {
            if let Event::Reward { kind, first, count, source, level, seals } = *e {
                rewards.push((kind, f.rewarded(first, count).to_vec(), source, level, seals));
            }
        }
    }
    // One hero holds an altar for 60 seconds: 1,200 ticks.
    assert_eq!(held_at.len(), 3, "three held (a hero on each): {held_at:?}");
    assert!(held_at.iter().all(|&(t, _)| (1_199..=1_201).contains(&t)), "{held_at:?}");
    assert_eq!(won_at, Some(held_at[1].0), "WON at the second altar, not the third (two win)");
    // The tide stopped when it was won: the third altar is not held later than the second.
    assert!(!f.tide());
    assert_eq!(rewards.len(), 1, "one cache, once");
    let (kind, paid, source, level, _) = &rewards[0];
    assert_eq!(*kind, R_TIDE_CACHE);
    assert_eq!((*source, *level), (0, 10));
    let ids: Vec<u16> = paid.iter().map(|p| p.0).collect();
    assert!(ids.contains(&a) && ids.contains(&b), "heroes past the floor are paid");
    assert!(!ids.contains(&third) || f.heroes()[third as usize].tide_contrib == 0, "a hero under the floor is not");
    assert!(f.heroes()[a as usize].coin > coin0, "the cache holds coin");
    assert_eq!(f.heroes()[a as usize].tide_contrib, 0, "contribution resets after the verdict");
}

#[test]
fn the_hold_needs_sixty_hero_seconds_times_the_heroes_in_the_field_over_twenty() {
    // 40 heroes: factor 2: an altar needs 120 hero-seconds. 40 heroes on one altar hold it in 3 seconds.
    let mut f = before_tide(0, 0, 1);
    for i in 0..40 {
        let (sx, sy) = spot(&f, 8);
        add(&mut f, &bare(KNIGHT, 10), sx + px(i * 3), sy);
    }
    f.step::<u16>(&[]);
    assert_eq!(f.realm().factor, 2);
    let a = lit(&f)[0];
    let (ax, ay) = f.terrain().altars[a];
    for i in 0..40u16 {
        f.hero_mut(i).x = ax + px(i as i32 % 8 * 4);
        f.hero_mut(i).y = ay + px(i as i32 / 8 * 4);
    }
    let mut held = None;
    for t in 1..=200u32 {
        f.step::<u16>(&[]);
        if altar_events(&f).iter().any(|e| e.0 == a as u8 && e.1 == ALTAR_HELD) {
            held = Some(t);
            break;
        }
    }
    // 120 hero-seconds = 2,400 hero-ticks; 40 heroes a tick: 60 ticks.
    assert_eq!(held, Some(60));
}

#[test]
fn monsters_at_an_altar_ruin_it() {
    let mut f = before_tide(0, 0, 1);
    f.step::<u16>(&[]);
    let a = lit(&f)[0];
    let (ax, ay) = f.terrain().altars[a];
    let hp0 = f.altars()[a].hp;
    // 8,000 at the field's top level 10: 262% = 20,960.
    assert_eq!(hp0, 20_960);
    let k = kind("gravedigger");
    for i in 0..40 {
        let m = mon(&mut f, k, 10, ax + px(i % 8 * 6 - 20), ay + px(i / 8 * 6 - 12));
        f.monsters_mut().stun[m as usize] = 0;
    }
    let mut ruined = 0;
    for _ in 0..600 {
        f.step::<u16>(&[]);
        ruined += altar_events(&f).iter().filter(|e| e.0 == a as u8 && e.1 == ALTAR_RUINED).count();
    }
    assert_eq!(ruined, 1, "RUINED fires once");
    assert_eq!(f.altars()[a].state, ALTAR_RUINED);
    // A ruined altar cannot be held later.
    assert!(f.altars()[a].hp == 0);
}

#[test]
fn contribution_is_damage_healing_and_half_the_damage_taken_and_standing_still_earns_nothing() {
    let mut f = before_tide(0, 0, 1);
    let (x, y) = spot(&f, 10);
    let walker = add(&mut f, &bare(KNIGHT, 10), x, y);
    let sitter = add(&mut f, &bare(KNIGHT, 10), x + px(200), y);
    f.step::<u16>(&[]);
    assert_eq!(f.heroes()[walker as usize].tide_contrib, 0);
    let big = kind("gravedigger");
    let mut inputs = vec![0u16; 2];
    // Damage taken counts half: a gravedigger hits her for its damage, and only half of what lands is credited.
    for q in [walker, sitter] {
        let (hx, hy) = (f.heroes()[q as usize].x, f.heroes()[q as usize].y);
        let m = mon(&mut f, big, 30, hx, hy);
        f.monsters_mut().hp[m as usize] = 1_000_000;
    }
    f.hero_mut(sitter).idle = STILL_TICKS - 1;
    let (mut taken_w, mut dealt_w) = (0u32, 0u32);
    for t in 0..60u32 {
        inputs[walker as usize] = if t % 2 == 0 { 1 } else { 5 };
        let (h0, c0) = (f.heroes()[walker as usize].health, f.heroes()[walker as usize].tide_contrib);
        f.step(&inputs);
        let h1 = f.heroes()[walker as usize].health;
        let gained = f.heroes()[walker as usize].tide_contrib - c0;
        taken_w += h0.saturating_sub(h1) / 2;
        dealt_w += gained;
    }
    let w = f.heroes()[walker as usize].tide_contrib;
    let s = f.heroes()[sitter as usize].tide_contrib;
    assert!(w > 0 && dealt_w > 0, "a hero in the fight earns: {w}");
    assert!(taken_w > 0, "and was hurt");
    assert!(f.heroes()[sitter as usize].idle >= STILL_TICKS, "she stood still");
    // The sitter earned only in the first tick, before she had stood still for 10 seconds.
    assert!(s * 5 < w, "standing still earns nothing: {s} against {w}");
    let s1 = f.heroes()[sitter as usize].tide_contrib;
    for _ in 0..40 {
        f.step(&inputs);
    }
    assert_eq!(f.heroes()[sitter as usize].tide_contrib, s1, "no more once she has stood still");
}

#[test]
fn healing_done_counts_for_the_healer() {
    let mut f = before_tide(0, 0, 1);
    let (x, y) = spot(&f, 10);
    let priest = add(&mut f, &bare(PRIEST, 10), x, y);
    let hurt = add(&mut f, &bare(KNIGHT, 10), x + px(30), y);
    f.step::<u16>(&[]);
    f.hero_mut(hurt).health = 10;
    guard(&mut f, priest);
    guard(&mut f, hurt);
    let m = mon(&mut f, kind("gravedigger"), 30, x + px(20), y);
    f.monsters_mut().hp[m as usize] = 1_000_000;
    f.monsters_mut().stun[m as usize] = 255;
    let mut inputs = vec![0u16; 2];
    for t in 0..200 {
        inputs[priest as usize] = if t % 2 == 0 { 1 } else { 5 };
        f.monsters_mut().stun[m as usize] = 255;
        f.step(&inputs);
    }
    // Her own weapon heals allies (HOLY LIGHT).
    assert!(f.heroes()[hurt as usize].health > 10);
    assert!(f.heroes()[priest as usize].tide_contrib > 0, "she earned from healing");
}
