//! The haul (rules section 6), the six potions (section 7), class XP and the draws a kill grants, and the events (section 12):
//! each fires once and only once.
mod common;
use common::*;

const DROWNED_K: u8 = 13;

fn one(class: u8, level: u8) -> (Field, u16) {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 24);
    let id = add(&mut f, &bare(class, level), x, y);
    idle(&mut f, 1);
    (f, id)
}

fn at(f: &Field, id: u16) -> (i32, i32) {
    (f.heroes()[id as usize].x, f.heroes()[id as usize].y)
}

/// Kills one monster next to the hero with her weapon this tick.
fn kill_one(f: &mut Field, id: u16, kind: u8, level: u8) {
    let (x, y) = at(f, id);
    let k = mon(f, kind, level, x + px(30), y);
    f.monsters_mut().hp[k as usize] = 1;
    f.hero_mut(id).charge = 1_000_000;
    f.step::<u16>(&[]);
}

fn put_at_waystone(f: &mut Field, id: u16, w: usize) {
    let (wx, wy) = f.terrain().waystones[w];
    let h = f.hero_mut(id);
    h.x = wx;
    h.y = wy;
}

fn input_for(f: &Field, id: u16, v: u16) -> Vec<u16> {
    let mut i = vec![0u16; f.heroes().len()];
    i[id as usize] = v;
    i
}

// ---- banking

#[test]
fn holding_at_a_waystone_for_3_s_banks_and_a_second_hold_leaves() {
    let (mut f, id) = one(KNIGHT, 10);
    put_at_waystone(&mut f, id, 2);
    f.hero_mut(id).coin = 700;
    let inp = input_for(&f, id, IN_INTERACT);
    for _ in 0..BANK_HOLD - 1 {
        f.step(&inp);
        assert_eq!(count(&f, BANK), 0);
    }
    f.step(&inp);
    assert!(f.events().contains(&Event::Bank { hero: id, coin: 700, waystone: 2 }));
    assert_eq!(f.heroes()[id as usize].coin, 0);
    f.step(&inp);
    assert_eq!(count(&f, BANK), 0, "once");
    for _ in 0..BANK_HOLD - 2 {
        f.step(&inp);
    }
    assert_eq!(count(&f, LEAVE), 0);
    f.step(&inp);
    assert!(f.events().contains(&Event::Leave { hero: id }));
    assert!(!f.heroes()[id as usize].present);
    f.step(&inp);
    assert_eq!(count(&f, LEAVE), 0, "once");
}

#[test]
fn being_struck_pauses_the_hold_for_that_tick_and_does_not_start_it_over() {
    let (mut f, id) = one(KNIGHT, 10);
    put_at_waystone(&mut f, id, 0);
    let inp = input_for(&f, id, IN_INTERACT);
    for _ in 0..BANK_HOLD / 2 {
        f.step(&inp);
    }
    let (x, y) = at(&f, id);
    let k = mon(&mut f, DROWNED_K, 1, x + px(10), y);
    for _ in 0..CONTACT_EVERY {
        f.monsters_mut().stun[k as usize] = 0;
        f.step(&inp);
        if f.heroes()[id as usize].hurt {
            break;
        }
    }
    let held = f.heroes()[id as usize].hold;
    assert!(held >= BANK_HOLD / 2, "kept: {held}");
    f.monsters_mut().hp[k as usize] = 0;
    // The tick after a hit adds nothing; the ones after it do.
    f.step(&inp);
    let after = f.heroes()[id as usize].hold;
    assert!(after <= held + 1 && after >= held, "paused: {held} then {after}");
}

#[test]
fn the_second_hold_banks_what_was_picked_up_since_before_it_leaves() {
    let (mut f, id) = one(KNIGHT, 10);
    put_at_waystone(&mut f, id, 1);
    let inp = input_for(&f, id, IN_INTERACT);
    for _ in 0..BANK_HOLD {
        f.step(&inp);
    }
    assert!(f.heroes()[id as usize].banked);
    f.hero_mut(id).coin = 55;
    for _ in 0..BANK_HOLD {
        f.step(&inp);
        if count(&f, LEAVE) > 0 {
            break;
        }
    }
    assert!(f.events().contains(&Event::Bank { hero: id, coin: 55, waystone: 1 }));
    assert!(f.events().contains(&Event::Leave { hero: id }));
}

#[test]
fn walking_south_out_of_the_gate_banks_and_leaves() {
    let (mut f, id) = one(KNIGHT, 10);
    let (gx, gy) = f.terrain().gate;
    f.hero_mut(id).x = gx;
    f.hero_mut(id).y = gy - px(GATE_PX / 2);
    f.hero_mut(id).coin = 33;
    // South is direction bits 0b0010 (down).
    let south = (1..16u16).find(|&d| {
        let mut g = quiet(2);
        let (x, y) = spot(&g, 24);
        let i = add(&mut g, &bare(KNIGHT, 10), x, y);
        g.step(&[d]);
        let h = &g.heroes()[i as usize];
        h.y > y && h.x == x
    });
    let inp = input_for(&f, id, south.expect("a south input"));
    f.step(&inp);
    assert!(f.events().contains(&Event::Bank { hero: id, coin: 33, waystone: NO_WAYSTONE }));
    assert!(f.events().contains(&Event::Leave { hero: id }));
    assert!(!f.heroes()[id as usize].present);
}

// ---- downed, raised, fallen

fn down(f: &mut Field, id: u16) {
    let h = f.hero_mut(id);
    h.health = 0;
    h.downed = DOWNED_TICKS;
    h.raise = 0;
}

#[test]
fn an_ally_standing_near_raises_in_2_s_a_priest_in_1() {
    for (class, ticks) in [(KNIGHT, secs(2)), (PRIEST, secs(1))] {
        let mut f = quiet(2);
        let (x, y) = spot(&f, 24);
        let d = add(&mut f, &bare(MAGE, 10), x, y);
        let r = add(&mut f, &bare(class, 10), x + px(RAISE_PX - 5), y);
        idle(&mut f, 1);
        down(&mut f, d);
        let max = f.heroes()[d as usize].max_health;
        for t in 1..=ticks {
            f.step::<u16>(&[]);
            let up = f.events().contains(&Event::Raise { hero: d, by: r });
            assert_eq!(up, t == ticks, "tick {t} of {ticks}");
        }
        let h = &f.heroes()[d as usize];
        assert_eq!((h.downed, h.health), (0, max * RISE_HEALTH_PCT / 100));
        assert!(h.has_fx(FX_RAISED));
        idle(&mut f, 1);
        assert_eq!(count(&f, RAISE), 0, "once");
    }
}

#[test]
fn stepping_away_restarts_the_raise() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 24);
    let d = add(&mut f, &bare(MAGE, 10), x, y);
    let r = add(&mut f, &bare(KNIGHT, 10), x + px(20), y);
    idle(&mut f, 1);
    down(&mut f, d);
    idle(&mut f, 20);
    assert!(f.heroes()[d as usize].raise > 0);
    f.hero_mut(r).x = x + px(RAISE_PX + 20);
    idle(&mut f, 2);
    assert_eq!(f.heroes()[d as usize].raise, 0);
}

#[test]
fn a_downed_hero_not_raised_in_15_s_falls_loses_half_the_haul_and_wakes_at_her_waystone() {
    let (mut f, id) = one(KNIGHT, 10);
    put_at_waystone(&mut f, id, 3);
    let inp = input_for(&f, id, IN_INTERACT);
    for _ in 0..BANK_HOLD {
        f.step(&inp);
    }
    f.hero_mut(id).x += px(200);
    f.hero_mut(id).coin = 901;
    down(&mut f, id);
    for _ in 0..DOWNED_TICKS - 1 {
        f.step::<u16>(&[]);
        assert_eq!(count(&f, FALLEN), 0);
    }
    f.step::<u16>(&[]);
    assert!(f.events().contains(&Event::Fallen { hero: id, coin: 450 }));
    let h = &f.heroes()[id as usize];
    assert_eq!((h.coin, h.health, (h.x, h.y)), (451, h.max_health, f.terrain().waystones[3]));
    f.step::<u16>(&[]);
    assert_eq!(count(&f, FALLEN), 0, "once");
}

#[test]
fn with_no_waystone_she_wakes_at_the_gate() {
    let (mut f, id) = one(KNIGHT, 10);
    down(&mut f, id);
    f.hero_mut(id).downed = 1;
    f.step::<u16>(&[]);
    assert_eq!(count(&f, FALLEN), 1);
    assert_eq!(at(&f, id), f.terrain().gate);
}

#[test]
fn a_hero_is_downed_once() {
    let (mut f, id) = one(MAGE, 1);
    let (x, y) = at(&f, id);
    f.hero_mut(id).health = 1;
    mon(&mut f, DROWNED_K, 60, x + px(10), y);
    let mut downs = 0;
    for _ in 0..40 {
        f.hero_mut(id).charge = 0;
        f.step::<u16>(&[]);
        downs += count(&f, DOWN);
    }
    assert_eq!(downs, 1);
    assert!(f.heroes()[id as usize].downed > 0);
}

// ---- potions

fn belt(class: u8, p: u8, n: u8) -> (Field, u16) {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 24);
    let mut s = bare(class, 10);
    s.belt = [(p, n), (P_NONE, 0), (P_NONE, 0)];
    let id = add(&mut f, &s, x, y);
    idle(&mut f, 1);
    (f, id)
}

#[test]
fn healing_draught_heals_35_percent_and_rests_10_s() {
    let (mut f, id) = belt(KNIGHT, P_HEALING, 3);
    let max = f.heroes()[id as usize].max_health;
    f.hero_mut(id).health = 1;
    f.step(&[IN_POTION1]);
    assert_eq!(f.heroes()[id as usize].health, 1 + max * 35 / 100);
    assert!(f.events().contains(&Event::Potion { hero: id, slot: 0, left: 2 }));
    // Pressed again while resting: nothing.
    f.step(&[0u16]);
    f.step(&[IN_POTION1]);
    assert_eq!(count(&f, POTION), 0);
    assert_eq!(f.heroes()[id as usize].belt[0], (P_HEALING, 2));
    idle(&mut f, secs(10));
    f.step(&[IN_POTION1]);
    assert_eq!(f.heroes()[id as usize].belt[0], (P_HEALING, 1));
}

#[test]
fn a_held_potion_key_drinks_once() {
    let (mut f, id) = belt(KNIGHT, P_HEALING, 3);
    for _ in 0..secs(12) {
        f.step(&[IN_POTION1]);
    }
    assert_eq!(f.heroes()[id as usize].belt[0], (P_HEALING, 2));
}

#[test]
fn veil_of_ash_is_3_s_unhurt() {
    let (mut f, id) = belt(KNIGHT, P_VEIL, 2);
    f.step(&[IN_POTION1]);
    assert_eq!(f.heroes()[id as usize].fx[FX_VEIL as usize], secs(3) as u16);
    idle(&mut f, 1);
    assert!(f.mods(id).unwrap().unhurt);
}

#[test]
fn whetstone_oil_adds_20_percent_for_30_s() {
    let (mut f, id) = belt(KNIGHT, P_WHETSTONE, 2);
    let p0 = f.mods(id).unwrap().power;
    f.step(&[IN_POTION1]);
    idle(&mut f, 1);
    assert_eq!(f.mods(id).unwrap().power * 100, p0 * 120);
    idle(&mut f, secs(30));
    assert_eq!(f.mods(id).unwrap().power, p0);
}

#[test]
fn scholars_ink_adds_50_percent_xp_for_2_minutes() {
    let (mut f, id) = belt(KNIGHT, P_INK, 1);
    let x0 = f.mods(id).unwrap().xp_pct;
    f.step(&[IN_POTION1]);
    idle(&mut f, 1);
    assert_eq!(f.mods(id).unwrap().xp_pct, x0 + 50);
    assert_eq!(f.heroes()[id as usize].fx[FX_INK as usize], secs(120) as u16 - 1);
}

#[test]
fn gamblers_coin_adds_20_luck_for_2_minutes() {
    let (mut f, id) = belt(KNIGHT, P_GAMBLER, 1);
    let l0 = f.luck(id);
    f.step(&[IN_POTION1]);
    idle(&mut f, 1);
    assert_eq!(f.luck(id), l0 + 20);
}

#[test]
fn phoenix_ash_is_not_drunk_but_rises_her_once_instead_of_falling() {
    let (mut f, id) = belt(KNIGHT, P_PHOENIX, 1);
    f.step(&[IN_POTION1]);
    assert_eq!(count(&f, POTION), 0);
    let max = f.heroes()[id as usize].max_health;
    f.hero_mut(id).coin = 100;
    down(&mut f, id);
    f.hero_mut(id).downed = 1;
    f.step(&[0u16]);
    assert_eq!(count(&f, FALLEN), 0);
    assert!(f.events().contains(&Event::Potion { hero: id, slot: 0, left: 0 }));
    let h = &f.heroes()[id as usize];
    assert_eq!((h.health, h.coin, h.phoenix_used), (max * 30 / 100, 100, true));
    down(&mut f, id);
    f.hero_mut(id).downed = 1;
    f.step(&[0u16]);
    assert_eq!(count(&f, FALLEN), 1);
}

// ---- class XP, kills, draws from kills

#[test]
fn a_kill_credits_every_active_hero_within_200_px_once() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 30);
    let a = add(&mut f, &bare(KNIGHT, 10), x, y);
    let b = add(&mut f, &bare(MAGE, 10), x + px(150), y);
    let c = add(&mut f, &bare(MAGE, 10), x + px(260), y);
    let idle_one = add(&mut f, &bare(MAGE, 10), x - px(100), y);
    idle(&mut f, 1);
    let t = f.tick();
    for i in [a, b, c] {
        f.hero_mut(i).active = t;
    }
    f.hero_mut(idle_one).active = 0;
    let xp0: Vec<u32> = f.heroes().iter().map(|h| h.class_xp).collect();
    kill_one(&mut f, a, DROWNED_K, 5);
    let kills: Vec<Event> = f.events().iter().copied().filter(|e| e.rank() == KILL).collect();
    assert_eq!(kills.len(), 1);
    let Event::Kill { kind, level, first, count: n, .. } = kills[0] else { unreachable!() };
    assert_eq!((kind, level), (DROWNED_K, 5));
    assert_eq!(f.credited(first, n), &[a, b]);
    assert!(f.heroes()[a as usize].class_xp > xp0[a as usize] && f.heroes()[b as usize].class_xp > xp0[b as usize]);
    assert_eq!(f.heroes()[c as usize].class_xp, xp0[c as usize]);
    assert_eq!(f.heroes()[idle_one as usize].class_xp, xp0[idle_one as usize], "not active: no share");
    f.step::<u16>(&[]);
    assert_eq!(count(&f, KILL), 0, "once");
}

#[test]
fn class_xp_only_from_monsters_at_most_10_levels_below() {
    let (mut f, id) = one(KNIGHT, 30);
    f.hero_mut(id).active = f.tick();
    kill_one(&mut f, id, DROWNED_K, 19);
    assert_eq!(count(&f, XP), 0);
    f.hero_mut(id).active = f.tick();
    kill_one(&mut f, id, DROWNED_K, 20);
    assert_eq!(count(&f, XP), 1);
    f.step::<u16>(&[]);
    assert_eq!(count(&f, XP), 0, "once");
}

#[test]
fn there_is_no_field_level_kills_leave_damage_alone_and_pay_class_xp() {
    let (mut f, id) = one(KNIGHT, 10);
    let p1 = f.mods(id).unwrap().power;
    for _ in 0..30 {
        f.hero_mut(id).active = f.tick();
        kill_one(&mut f, id, DROWNED_K, 5);
        assert_eq!(count(&f, GRANT), 0, "a plain kill grants no draw");
    }
    idle(&mut f, 1);
    assert_eq!(f.mods(id).unwrap().power, p1, "damage = base x weapon x MIGHT x cards x effects, no outing term");
    // Class XP: the kill's XP x the class XP percent x the race's (HUMAN 105%), booked on the hero and in XP.
    let (mut g, j) = one(KNIGHT, 10);
    g.hero_mut(j).active = g.tick();
    let (x, y) = at(&g, j);
    let k = mon(&mut g, DROWNED_K, 5, x + px(30), y);
    let xp = g.monsters().xp(k as usize);
    g.monsters_mut().hp[k as usize] = 1;
    g.hero_mut(j).charge = 1_000_000;
    g.step::<u16>(&[]);
    let want = xp * g.mods(j).unwrap().xp_pct / 100 * RACES[HUMAN as usize].class_xp_pct / 100;
    assert_eq!(g.heroes()[j as usize].class_xp, want);
    assert!(g.events().contains(&Event::Xp { hero: j, amount: want }));
}

#[test]
fn an_elite_champion_or_boss_kill_grants_a_draw_to_every_active_sharer() {
    for flags in [ELITE, CHAMPION, BOSS] {
        let mut f = quiet(2);
        let (x, y) = spot(&f, 30);
        let a = add(&mut f, &Sheet::bench(KNIGHT, HUMAN, 10), x, y);
        let b = add(&mut f, &Sheet::bench(MAGE, HUMAN, 10), x + px(150), y);
        let c = add(&mut f, &Sheet::bench(MAGE, HUMAN, 10), x + px(260), y);
        let idle_one = add(&mut f, &Sheet::bench(MAGE, HUMAN, 10), x - px(100), y);
        idle(&mut f, 1);
        let d0: Vec<u32> = f.heroes().iter().map(|h| h.draws + h.owed as u32).collect();
        let t = f.tick();
        for i in [a, b, c] {
            f.hero_mut(i).active = t;
        }
        f.hero_mut(idle_one).active = 0;
        let k = f.place_monster(DROWNED_K, 5, flags, x + px(30), y).expect("room");
        f.monsters_mut().hp[k as usize] = 1;
        f.hero_mut(a).charge = 1_000_000;
        f.step::<u16>(&[]);
        let d1: Vec<u32> = f.heroes().iter().map(|h| h.draws + h.owed as u32).collect();
        assert_eq!([a, b, c, idle_one].map(|i| d1[i as usize] - d0[i as usize]), [1, 1, 0, 0], "flags {flags}");
        let grants: Vec<Event> = f.events().iter().copied().filter(|e| e.rank() == GRANT).collect();
        assert_eq!(grants, vec![Event::Grant { hero: a, source: GRANT_KILL }, Event::Grant { hero: b, source: GRANT_KILL }]);
        f.step::<u16>(&[]);
        assert_eq!(count(&f, GRANT), 0, "once");
    }
}

#[test]
fn skill_and_pick_and_draw_events_fire_once() {
    let (mut f, id) = one(KNIGHT, 10);
    for t in 0..5 {
        f.step(&[IN_SKILL1]);
        assert_eq!(count(&f, SKILL), (t == 0) as usize);
    }
    f.hero_mut(id).offers.push([1, 2, 3, 0]);
    f.step(&[2u16 << IN_PICK_SHIFT]);
    assert!(f.events().contains(&Event::Pick { hero: id, card: 2, copies: 1 }));
    f.step(&[2u16 << IN_PICK_SHIFT]);
    assert_eq!(count(&f, PICK), 0);
}

#[test]
fn events_come_in_the_contracts_order() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 24);
    let id = add(&mut f, &Sheet::bench(KNIGHT, HUMAN, 10), x, y);
    let mut ranks = Vec::new();
    for _ in 0..secs(20) {
        let (hx, hy) = at(&f, id);
        if f.tick() % 7 == 0 {
            // Every third an ELITE: its kill grants a draw (GRANT, DRAW) in the same tick as KILL and XP.
            let flags = if f.tick() % 21 == 0 { ELITE } else { 0 };
            let k = f.place_monster(DROWNED_K, 10, flags, hx + px(30), hy).expect("room");
            f.monsters_mut().hp[k as usize] = 1;
        }
        f.step(&[IN_SKILL1 | IN_POTION1]);
        let r: Vec<u8> = f.events().iter().map(|e| e.rank()).collect();
        assert!(r.windows(2).all(|w| w[0] <= w[1]), "{r:?}");
        ranks.extend(r);
    }
    ranks.sort();
    ranks.dedup();
    assert!(ranks.len() >= 5, "{ranks:?}");
}
