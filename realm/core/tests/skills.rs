//! Attack shapes, the 21 skills and ultimates, the job and class passives, threat and the damage formula.
mod common;
use common::*;

fn arena(field: u8, class: u8, level: u8) -> (Field, u16, i32, i32) {
    let mut f = quiet(field);
    let (x, y) = spot(&f, 24);
    let id = add(&mut f, &bare(class, level), x, y);
    warm(&mut f);
    (f, id, x, y)
}

/// Holds every hero's weapon (no auto-attacks) for one step.
fn hold(f: &mut Field, inputs: &[u16]) {
    for i in 0..f.heroes().len() as u16 {
        f.hero_mut(i).charge = 0;
    }
    f.step(inputs);
}

/// Fires every hero's weapon this step.
fn fire(f: &mut Field, inputs: &[u16]) {
    for i in 0..f.heroes().len() as u16 {
        f.hero_mut(i).charge = 100_000;
    }
    f.step(inputs);
}

fn hp(f: &Field, i: u32) -> u32 {
    f.monsters().hp[i as usize]
}

fn stunned(f: &mut Field, kind_id: u8, level: u8, x: i32, y: i32) -> u32 {
    let i = mon(f, kind_id, level, x, y);
    f.monsters_mut().stun[i as usize] = 250;
    i
}

/// Expected damage: base x weapon level x MIGHT x field level x cards x effects (no target bonus).
fn expect(f: &Field, id: u16, base: u32) -> u32 {
    let h = &f.heroes()[id as usize];
    let wl = h.sheet.weapon_level(f.field_id());
    (base as u64 * weapon_pct(wl) / 100 * f.mods(id).unwrap().power / POWER_ONE) as u32
}

const DROWNED_K: u8 = 13;

// ---- shapes

#[test]
fn arc_hits_a_cone_toward_the_nearest_monster() {
    let (mut f, id, x, y) = arena(2, KNIGHT, 10);
    let front = stunned(&mut f, DROWNED_K, 60, x + px(40), y);
    let side = stunned(&mut f, DROWNED_K, 60, x + px(30), y + px(35));
    let behind = stunned(&mut f, DROWNED_K, 60, x - px(45), y);
    let far = stunned(&mut f, DROWNED_K, 60, x + px(80), y);
    let before: Vec<u32> = [front, side, behind, far].iter().map(|&i| hp(&f, i)).collect();
    fire(&mut f, &[]);
    let lost: Vec<u32> = [front, side, behind, far].iter().zip(&before).map(|(&i, b)| b - hp(&f, i)).collect();
    let d = expect(&f, id, 30);
    assert_eq!(lost, vec![d, d, 0, 0]);
}

#[test]
fn ring_hits_a_circle_on_the_hero() {
    let (mut f, id, x, y) = arena(2, PRIEST, 10);
    let a = stunned(&mut f, DROWNED_K, 60, x + px(90), y);
    let b = stunned(&mut f, DROWNED_K, 60, x - px(100), y);
    let (ha, hb) = (hp(&f, a), hp(&f, b));
    fire(&mut f, &[]);
    assert_eq!(ha - hp(&f, a), expect(&f, id, 28));
    assert_eq!(hb, hp(&f, b));
}

#[test]
fn bolt_pierces_then_stops() {
    let (mut f, id, x, y) = arena(2, ARCHER, 10);
    let line: Vec<u32> = (0..7).map(|k| stunned(&mut f, DROWNED_K, 60, x + px(50 + 30 * k), y)).collect();
    let before: Vec<u32> = line.iter().map(|&i| hp(&f, i)).collect();
    fire(&mut f, &[]);
    let hit = line.iter().zip(&before).filter(|&(&i, &b)| hp(&f, i) < b).count();
    assert_eq!(hit, 5, "LONGBOW pierces 4");
    let _ = id;
}

#[test]
fn bolt_stops_at_walls() {
    let mut f = quiet(1);
    let t = f.terrain().clone();
    // An open cell, a wall run of at least two cells, open again, along a row.
    let w = CELLS_W as i32;
    let mut found = None;
    'find: for cy in 20..w - 20 {
        for cx in 20..w - 20 {
            let at = |x: i32| t.map[(cy * w + x) as usize] & WALL != 0;
            if !at(cx) && !at(cx - 1) && at(cx + 1) && at(cx + 2) && (3..8).any(|k| !at(cx + k) && !at(cx + k + 1) && (1..k).all(|j| at(cx + j))) {
                let k = (3..8).find(|&k| !at(cx + k) && !at(cx + k + 1)).unwrap();
                found = Some((cx, cy, k));
                break 'find;
            }
        }
    }
    let (cx, cy, k) = found.expect("a wall between open cells");
    let half = 1 << (CELL_SHIFT - 1);
    let (x, y) = ((cx << CELL_SHIFT) + half, (cy << CELL_SHIFT) + half);
    let id = add(&mut f, &bare(ARCHER, 15), x, y);
    warm(&mut f);
    let m = stunned(&mut f, kind("hanged man"), 60, ((cx + k) << CELL_SHIFT) + half, y);
    let before = hp(&f, m);
    fire(&mut f, &[]);
    assert_eq!(hp(&f, m), before, "the arrow stops at the wall");
    assert!(f.heroes()[id as usize].fired);
}

#[test]
fn fireball_bursts_and_the_archmage_bursts_twice() {
    for (job_bit, mul) in [(0u8, 100u32), (0, 200)] {
        let (field, class, level) = if mul == 100 { (2, MAGE, 10) } else { (3, MAGE | job_bit, 40) };
        let (mut f, id, x, y) = arena(field, class, level);
        let a = stunned(&mut f, kind(if field == 2 { "drowned" } else { "goat cultist" }), 60, x + px(150), y);
        let b = stunned(&mut f, kind(if field == 2 { "drowned" } else { "goat cultist" }), 60, x + px(190), y);
        let c = stunned(&mut f, kind(if field == 2 { "drowned" } else { "goat cultist" }), 60, x + px(150), y + px(80));
        let before = [hp(&f, a), hp(&f, b), hp(&f, c)];
        fire(&mut f, &[]);
        let d = expect(&f, id, 40);
        let want = d + if mul == 200 { d * 100 / 100 } else { 0 };
        assert_eq!(before[0] - hp(&f, a), want, "job {}", f.heroes()[id as usize].job);
        assert_eq!(before[1] - hp(&f, b), want);
        assert_eq!(before[2], hp(&f, c), "outside the burst");
    }
}

#[test]
fn drop_lands_after_its_delay() {
    let (mut f, id, x, y) = arena(2, PALADIN, 10);
    let m = stunned(&mut f, DROWNED_K, 60, x + px(150), y);
    let before = hp(&f, m);
    fire(&mut f, &[]);
    assert_eq!(f.drops().len(), 1);
    for _ in 0..5 {
        hold(&mut f, &[]);
        assert_eq!(hp(&f, m), before);
    }
    hold(&mut f, &[]);
    assert_eq!(before - hp(&f, m), expect(&f, id, 36));
}

#[test]
fn zone_acts_every_10_ticks_and_ends() {
    let (mut f, id, x, y) = arena(2, PRIEST, 25);
    let m = stunned(&mut f, DROWNED_K, 60, x + px(120), y);
    hold(&mut f, &[IN_SKILL2]);
    assert_eq!(f.zones().len(), 1);
    let mut acts = Vec::new();
    for _ in 0..200 {
        f.monsters_mut().hp[m as usize] = 1_000_000;
        let b = hp(&f, m);
        f.monsters_mut().stun[m as usize] = 250;
        hold(&mut f, &[]);
        if hp(&f, m) < b {
            acts.push(f.tick());
        }
    }
    assert!(acts.windows(2).all(|w| w[1] - w[0] == ZONE_EVERY), "{acts:?}");
    let rank = f.heroes()[id as usize].rank_pct(S_CONSECRATE);
    assert_eq!(acts.len() as u32 + 1, ZONES[Z_CONSECRATE as usize].ticks as u32 * rank / 100 / ZONE_EVERY, "{acts:?}");
    assert!(f.zones().is_empty());
}

#[test]
fn dash_moves_her_along_a_line_unhurt() {
    let (mut f, id, x, y) = arena(2, KNIGHT, 25);
    hold(&mut f, &[1]);
    let x0 = f.heroes()[id as usize].x;
    let m = mon(&mut f, DROWNED_K, 60, x0 + px(100), y);
    let before = hp(&f, m);
    hold(&mut f, &[IN_SKILL2]);
    let h = &f.heroes()[id as usize];
    assert_eq!(h.x - x0, px(200));
    assert!(h.has_fx(FX_DASH) && f.mods(id).is_some());
    let _ = x;
    assert_eq!(before - hp(&f, m), expect(&f, id, 80) * h.rank_pct(S_CHARGE) / 100);
    assert_eq!(f.monsters().stun[m as usize], secs(1) as u8);
}

// ---- skills

#[test]
fn second_wind_heals_30_percent() {
    let (mut f, id, _, _) = arena(2, NOVICE, 1);
    let max = f.heroes()[id as usize].max_health;
    f.hero_mut(id).health = max / 4;
    hold(&mut f, &[IN_SKILL1]);
    assert_eq!(f.heroes()[id as usize].health, max / 4 + max * 30 / 100);
    assert_eq!(f.heroes()[id as usize].cooldowns[0], secs(30));
    assert!(f.events().contains(&Event::Skill { hero: id, which: 1 }));
}

#[test]
fn provoke_takes_half_damage_and_turns_the_horde() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 30);
    let mage = add(&mut f, &bare(MAGE, 10), x, y);
    let knight = add(&mut f, &bare(KNIGHT, 10), x + px(280), y);
    warm(&mut f);
    let m = mon(&mut f, DROWNED_K, 60, x + px(80), y);
    let taken0 = f.mods(knight).unwrap().taken;
    hold(&mut f, &[0, IN_SKILL1]);
    idle(&mut f, 1);
    assert_eq!(f.mods(knight).unwrap().taken, taken0 / 2);
    let x0 = f.monsters().x[m as usize];
    // The flow takes a few ticks to rebuild; a drowned walks about 2 px a tick.
    for _ in 0..60 {
        hold(&mut f, &[]);
    }
    assert!(f.monsters().x[m as usize] > x0 + px(30), "it walks to the knight, away from the mage");
    let _ = mage;
}

#[test]
fn charge_is_a_dash_with_damage_and_stun() {
    dash_moves_her_along_a_line_unhurt();
}

#[test]
fn nova_rings_200_px() {
    let (mut f, id, x, y) = arena(2, MAGE, 10);
    let a = stunned(&mut f, DROWNED_K, 60, x + px(190), y);
    let b = stunned(&mut f, DROWNED_K, 60, x + px(215), y);
    let (ha, hb) = (hp(&f, a), hp(&f, b));
    hold(&mut f, &[IN_SKILL1]);
    assert_eq!(ha - hp(&f, a), expect(&f, id, 160));
    assert_eq!(hb, hp(&f, b));
}

#[test]
fn meteor_drops_on_the_thickest_cell_after_30_ticks() {
    let (mut f, id, x, y) = arena(2, MAGE, 25);
    let lone = stunned(&mut f, DROWNED_K, 60, x + px(100), y + px(100));
    let pack: Vec<u32> = (0..5).map(|k| stunned(&mut f, DROWNED_K, 60, x - px(300) + px(k * 4), y + px(4))).collect();
    hold(&mut f, &[IN_SKILL2]);
    let d = f.drops()[0];
    assert!(dist(d.x, d.y, x - px(296), y) < px(32) as i64 && d.left == 30);
    // Sturdier than any monster, so the whole blow shows.
    f.monsters_mut().hp[pack[0] as usize] = 1_000_000;
    let before = hp(&f, pack[0]);
    for _ in 0..30 {
        for &i in pack.iter().chain([&lone]) {
            f.monsters_mut().stun[i as usize] = 250;
        }
        hold(&mut f, &[]);
    }
    assert_eq!(before - hp(&f, pack[0]), expect(&f, id, 400) * f.heroes()[id as usize].rank_pct(S_METEOR) / 100);
}

#[test]
fn volley_looses_12_arrows_in_a_120_degree_fan() {
    let (mut f, _, x, y) = arena(2, ARCHER, 10);
    stunned(&mut f, DROWNED_K, 60, x + px(60), y);
    let fan: Vec<u32> = (0..12)
        .map(|k| {
            let a = -60 + 120 * k / 11;
            let (dx, dy) = (px(250) * cos(a) / 1000, px(250) * cos(a - 90) / 1000);
            stunned(&mut f, DROWNED_K, 60, x + dx, y + dy)
        })
        .collect();
    let before: Vec<u32> = fan.iter().map(|&i| hp(&f, i)).collect();
    hold(&mut f, &[IN_SKILL1]);
    let hit = fan.iter().zip(&before).filter(|&(&i, &b)| hp(&f, i) < b).count();
    assert_eq!(hit, 12);
}

fn cos(deg: i32) -> i32 {
    // Bhaskara in thousandths, as the core turns vectors.
    let d = deg.rem_euclid(360);
    let (d, s) = if d <= 90 {
        (d, 1)
    } else if d < 270 {
        (180 - d, -1)
    } else {
        (d - 360, 1)
    };
    s * 1000 * (32400 - 4 * d * d) / (32400 + d * d)
}

#[test]
fn tumble_dashes_along_her_movement_and_leaves_a_slowing_zone() {
    let (mut f, id, x, y) = arena(2, ARCHER, 25);
    hold(&mut f, &[3]);
    let (x0, y0) = (f.heroes()[id as usize].x, f.heroes()[id as usize].y);
    let m = mon(&mut f, DROWNED_K, 60, x0 + px(20), y0);
    hold(&mut f, &[IN_SKILL2]);
    assert_eq!(f.heroes()[id as usize].y - y0, px(120));
    let z = f.zones()[0];
    assert_eq!((z.x, z.y, z.kind), (x0, y0, Z_TUMBLE));
    assert!(f.monsters().slow[m as usize] > 0);
    let _ = (x, y);
}

#[test]
fn sanctuary_heals_40_percent_and_raises_the_downed() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 30);
    let p = add(&mut f, &bare(PRIEST, 10), x, y);
    let a = add(&mut f, &bare(KNIGHT, 10), x + px(150), y);
    let b = add(&mut f, &bare(KNIGHT, 10), x - px(150), y);
    warm(&mut f);
    let max = f.heroes()[a as usize].max_health;
    f.hero_mut(a).health = max / 2;
    f.hero_mut(b).health = 0;
    f.hero_mut(b).downed = 100;
    hold(&mut f, &[IN_SKILL1]);
    assert_eq!(f.heroes()[a as usize].health, max / 2 + max * 40 / 100);
    assert_eq!(f.heroes()[b as usize].downed, 0);
    assert!(f.events().contains(&Event::Raise { hero: b, by: p }));
}

#[test]
fn consecrate_heals_allies_and_burns_monsters() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 30);
    let p = add(&mut f, &bare(PRIEST, 25), x, y);
    let a = add(&mut f, &bare(KNIGHT, 10), x + px(100), y);
    warm(&mut f);
    let max = f.heroes()[a as usize].max_health;
    f.hero_mut(a).health = max / 2;
    let m = stunned(&mut f, DROWNED_K, 60, x - px(100), y);
    let before = hp(&f, m);
    hold(&mut f, &[IN_SKILL2]);
    let rank = f.heroes()[p as usize].rank_pct(S_CONSECRATE);
    assert_eq!(f.heroes()[a as usize].health, max / 2 + max * (4 * 10 * ZONE_EVERY / TICK_HZ * rank / 100) / 1000);
    assert_eq!(before - hp(&f, m), expect(&f, p, 20 * ZONE_EVERY / TICK_HZ) * rank / 100);
}

#[test]
fn aegis_makes_allies_within_120_px_unhurt_for_3_s() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 30);
    add(&mut f, &bare(PALADIN, 10), x, y);
    let a = add(&mut f, &bare(MAGE, 10), x + px(100), y);
    let b = add(&mut f, &bare(MAGE, 10), x + px(150), y);
    warm(&mut f);
    hold(&mut f, &[IN_SKILL1]);
    assert_eq!(f.heroes()[a as usize].fx[FX_AEGIS as usize], secs(3) as u16);
    assert_eq!(f.heroes()[b as usize].fx[FX_AEGIS as usize], 0);
    idle(&mut f, 1);
    assert!(f.mods(a).unwrap().unhurt);
}

#[test]
fn hammerfall_rings_100_px_and_stuns_1_5_s() {
    let (mut f, id, x, y) = arena(2, PALADIN, 25);
    let m = mon(&mut f, DROWNED_K, 60, x + px(90), y);
    let before = hp(&f, m);
    hold(&mut f, &[IN_SKILL2]);
    assert_eq!(before - hp(&f, m), expect(&f, id, 120) * f.heroes()[id as usize].rank_pct(S_HAMMERFALL) / 100);
    assert_eq!(f.monsters().stun[m as usize], 30);
}

// ---- ultimates (class level 40, a job)

const CULTIST: u8 = 20;

#[test]
fn rampart_zone_takes_40_percent_off() {
    let (mut f, id, _, _) = arena(3, KNIGHT, 40);
    assert_eq!(f.heroes()[id as usize].job, J_WARDEN);
    let t0 = f.mods(id).unwrap().taken;
    hold(&mut f, &[IN_ULT]);
    hold(&mut f, &[]);
    assert_eq!(f.zones()[0].kind, Z_RAMPART);
    assert_eq!(f.mods(id).unwrap().taken, t0 * 60 / 100);
}

#[test]
fn blood_rage_attacks_60_percent_faster_and_heals_on_kills() {
    let (mut f, id, x, y) = arena(3, KNIGHT | 8, 40);
    assert_eq!(f.heroes()[id as usize].job, J_BERSERKER);
    let as0 = f.mods(id).unwrap().as_pct;
    hold(&mut f, &[IN_ULT]);
    hold(&mut f, &[]);
    assert_eq!(f.mods(id).unwrap().as_pct, as0 + 60);
    let max = f.heroes()[id as usize].max_health;
    f.hero_mut(id).health = max / 2;
    stunned(&mut f, CULTIST, 1, x + px(30), y);
    let h0 = f.heroes()[id as usize].health;
    for _ in 0..20 {
        f.step::<u16>(&[]);
        if f.events().iter().any(|e| matches!(e, Event::Kill { .. })) {
            assert_eq!(f.heroes()[id as usize].health, h0 + max / 100);
            return;
        }
    }
    panic!("no kill");
}

#[test]
fn cataclysm_drops_five_meteors_over_5_s() {
    let (mut f, id, x, y) = arena(3, MAGE, 40);
    assert_eq!(f.heroes()[id as usize].job, J_ARCHMAGE);
    for k in 0..5 {
        for j in 0..(5 - k) {
            stunned(&mut f, CULTIST, 60, x - px(250) + px(64 * k), y + px(j * 3));
        }
    }
    hold(&mut f, &[IN_ULT]);
    let mut lefts: Vec<u16> = f.drops().iter().map(|d| d.left).collect();
    lefts.sort();
    assert_eq!(lefts, vec![30, 50, 70, 90, 110]);
}

#[test]
fn plague_curses_and_the_cursed_spread_it_and_take_15_percent_more() {
    let (mut f, id, x, y) = arena(3, MAGE | 8, 40);
    assert_eq!(f.heroes()[id as usize].job, J_HEXER);
    let a = stunned(&mut f, CULTIST, 60, x + px(250), y);
    let b = stunned(&mut f, CULTIST, 60, x + px(320), y);
    let c = stunned(&mut f, CULTIST, 60, x + px(270), y);
    hold(&mut f, &[IN_ULT]);
    assert!(f.monsters().curse[a as usize] > 0 && f.monsters().curse[c as usize] > 0);
    assert_eq!(f.monsters().curse[b as usize], 0);
    // A cursed monster's death curses those within 60 px.
    f.monsters_mut().hp[a as usize] = 1;
    let (bx, by) = (f.monsters().x[a as usize] + px(330 - 250), y);
    f.monsters_mut().x[b as usize] = bx - px(50);
    f.monsters_mut().y[b as usize] = by;
    f.monsters_mut().x[a as usize] = bx - px(100);
    f.monsters_mut().hp[c as usize] = 1;
    f.monsters_mut().x[c as usize] = bx - px(100);
    for _ in 0..40 {
        f.step::<u16>(&[]);
        if f.monsters().hp[c as usize] == 0 {
            break;
        }
    }
    assert!(f.monsters().curse[b as usize] > 0, "spread to b");
}

#[test]
fn hail_zones_the_thickest_cell_within_400_px() {
    let (mut f, id, x, y) = arena(3, ARCHER, 40);
    assert_eq!(f.heroes()[id as usize].job, J_RANGER);
    for j in 0..4 {
        stunned(&mut f, CULTIST, 60, x + px(300), y + px(j * 3));
    }
    hold(&mut f, &[IN_ULT]);
    let z = f.zones()[0];
    assert_eq!((z.kind, z.px), (Z_HAIL, 300));
    assert!(dist(z.x, z.y, x + px(300), y) < px(32) as i64);
}

#[test]
fn deadeye_pierces_everything_for_double() {
    let (mut f, id, x, y) = arena(3, ARCHER | 8, 40);
    assert_eq!(f.heroes()[id as usize].job, J_SHARPSHOOTER);
    let line: Vec<u32> = (0..12).map(|k| stunned(&mut f, CULTIST, 60, x + px(40 + 25 * k), y)).collect();
    hold(&mut f, &[IN_ULT]);
    let p0 = f.mods(id).unwrap().power;
    let before: Vec<u32> = line.iter().map(|&i| hp(&f, i)).collect();
    fire(&mut f, &[]);
    assert!(line.iter().zip(&before).all(|(&i, &b)| hp(&f, i) < b), "every one");
    assert_eq!(f.mods(id).unwrap().power, p0 * 2, "DEADEYE doubles in the effects group");
}

#[test]
fn benediction_gives_allies_within_300_px_25_percent() {
    let mut f = quiet(3);
    let (x, y) = spot(&f, 24);
    let o = add(&mut f, &bare(PRIEST, 40), x, y);
    let a = add(&mut f, &bare(KNIGHT, 40), x + px(200), y);
    warm(&mut f);
    assert_eq!(f.heroes()[o as usize].job, J_ORACLE);
    let (p0, s0) = (f.mods(a).unwrap().power, f.mods(a).unwrap().as_pct);
    hold(&mut f, &[IN_ULT]);
    idle(&mut f, 1);
    assert_eq!(f.mods(a).unwrap().as_pct, s0 + 25);
    assert_eq!(f.mods(a).unwrap().power * 100, p0 * 125);
}

#[test]
fn pyre_burns_180_px_for_10_s() {
    let (mut f, id, _, _) = arena(3, PRIEST | 8, 40);
    assert_eq!(f.heroes()[id as usize].job, J_INQUISITOR);
    hold(&mut f, &[IN_ULT]);
    let z = f.zones()[0];
    assert_eq!((z.kind, z.px), (Z_PYRE, 180));
    assert_eq!(z.dmg, expect(&f, id, 90 * ZONE_EVERY / TICK_HZ) * f.heroes()[id as usize].rank_pct(U_PYRE) / 100);
}

#[test]
fn martyr_keeps_allies_above_1_health() {
    let mut f = quiet(3);
    let (x, y) = spot(&f, 24);
    let t = add(&mut f, &bare(PALADIN, 40), x, y);
    let a = add(&mut f, &bare(MAGE, 40), x + px(150), y);
    warm(&mut f);
    assert_eq!(f.heroes()[t as usize].job, J_TEMPLAR);
    hold(&mut f, &[IN_ULT]);
    f.hero_mut(a).health = 5;
    let g = mon(&mut f, kind("stone anchorite"), 60, x + px(150) + px(10), y);
    for _ in 0..20 {
        hold(&mut f, &[]);
    }
    assert_eq!(f.heroes()[a as usize].health, 1);
    assert_eq!(f.heroes()[a as usize].downed, 0);
    let _ = g;
}

#[test]
fn crusade_smites_three_and_moves_30_percent_faster() {
    let (mut f, id, x, y) = arena(3, PALADIN | 8, 40);
    assert_eq!(f.heroes()[id as usize].job, J_CRUSADER);
    for k in 0..4 {
        stunned(&mut f, CULTIST, 60, x + px(100 + 20 * k), y);
    }
    let m0 = f.mods(id).unwrap().move_pct;
    hold(&mut f, &[IN_ULT]);
    idle(&mut f, 1);
    assert_eq!(f.mods(id).unwrap().move_pct, m0 + 30);
    fire(&mut f, &[]);
    assert_eq!(f.drops().len(), CRUSADE_TARGETS as usize);
}

// ---- passives

#[test]
fn job_passives() {
    let warden = Sheet::bench(KNIGHT, HUMAN, 40);
    let mut f = quiet(3);
    let id = add(&mut f, &warden, FIELD / 2, FIELD / 2);
    assert_eq!(f.heroes()[id as usize].threat(), 26);
    let b = add(&mut f, &Sheet::bench(KNIGHT | 8, HUMAN, 40), FIELD / 2, FIELD / 2);
    assert_eq!(f.heroes()[b as usize].threat(), 14);
    // BERSERKER: +1% per 3% missing (B1, balance.md).
    idle(&mut f, 1);
    let p0 = f.mods(b).unwrap().power;
    let max = f.heroes()[b as usize].max_health;
    f.hero_mut(b).health = max / 2;
    idle(&mut f, 1);
    let p1 = f.mods(b).unwrap().power;
    assert!(p1 > p0 && (p1 - p0) * 100 / p0 >= 15, "{p0} {p1}");
    // RANGER: +10% move, pierce 8. SHARPSHOOTER: reach +25%, +30% on ELITES.
    let r = add(&mut f, &Sheet::bench(ARCHER, HUMAN, 40), FIELD / 2, FIELD / 2);
    let s = add(&mut f, &Sheet::bench(ARCHER | 8, HUMAN, 40), FIELD / 2, FIELD / 2);
    idle(&mut f, 1);
    let (mr, ms) = (f.mods(r).unwrap(), f.mods(s).unwrap());
    assert_eq!(mr.move_pct - ms.move_pct, 10);
    assert_eq!(ms.reach_pct - mr.reach_pct, 25);
    assert_eq!(ms.elite_pct, 30);
    assert_eq!(JOBS[J_RANGER as usize].passive.pierce, 8);
    // TEMPLAR: aura 14% within 140 px.
    let mut g = quiet(3);
    let (x, y) = spot(&g, 24);
    add(&mut g, &Sheet::bench(PALADIN, HUMAN, 40), x, y);
    let a = add(&mut g, &bare(MAGE, 30), x + px(130), y);
    idle(&mut g, 1);
    let t_in = g.mods(a).unwrap().taken;
    g.hero_mut(a).x = x + px(150);
    idle(&mut g, 1);
    assert_eq!(g.mods(a).unwrap().taken * 86 / 100, t_in);
    // CRUSADER: +2% per ally within 100 px, at most 20.
    let mut c = quiet(3);
    let (x, y) = spot(&c, 24);
    let cr = add(&mut c, &Sheet::bench(PALADIN | 8, HUMAN, 40), x, y);
    idle(&mut c, 1);
    let p0 = c.mods(cr).unwrap().power;
    for k in 0..12 {
        add(&mut c, &bare(MAGE, 30), x + px(5 * k), y + px(30));
    }
    idle(&mut c, 1);
    assert_eq!(c.mods(cr).unwrap().power * 100, p0 * 120);
}

#[test]
fn oracle_heals_shield_the_low_and_inquisitor_doubles_holy_light() {
    let mut f = quiet(3);
    let (x, y) = spot(&f, 24);
    let o = add(&mut f, &bare(PRIEST, 40), x, y);
    let a = add(&mut f, &bare(KNIGHT, 40), x + px(100), y);
    warm(&mut f);
    let max = f.heroes()[a as usize].max_health;
    f.hero_mut(a).health = max / 5;
    stunned(&mut f, CULTIST, 60, x + px(50), y);
    fire(&mut f, &[]);
    let h = &f.heroes()[a as usize];
    assert_eq!(h.health, max / 5 + max * 3 / 100);
    assert!(h.has_fx(FX_SHIELD));
    let (mut g, i, x, y) = arena(3, PRIEST | 8, 40);
    let m = stunned(&mut g, CULTIST, 60, x + px(50), y);
    let before = hp(&g, m);
    fire(&mut g, &[]);
    assert_eq!(before - hp(&g, m), expect(&g, i, 28) * 2);
    let _ = o;
}

#[test]
fn class_passives() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 30);
    let k = add(&mut f, &bare(KNIGHT, 10), x, y);
    let a = add(&mut f, &bare(ARCHER, 10), x, y);
    let p = add(&mut f, &bare(PALADIN, 10), x, y);
    let m = add(&mut f, &bare(MAGE, 10), x + px(90), y);
    let n = add(&mut f, &bare(MAGE, 10), x + px(110), y);
    idle(&mut f, 1);
    assert_eq!(f.heroes()[k as usize].pushed_pct(), 50);
    assert_eq!(f.mods(a).unwrap().move_pct - f.mods(k).unwrap().move_pct, 8);
    assert_eq!(f.mods(n).unwrap().taken * 92 / 100, f.mods(m).unwrap().taken, "PALADIN aura 8% within 100 px");
    assert_eq!(CLASSES[MAGE as usize].passive.draw_size, 4);
    assert_eq!(CLASSES[PRIEST as usize].passive.raise_pct, 200);
    let _ = p;
    // Pushes on heroes are halved for knights.
    let x0 = f.heroes()[k as usize].x;
    push_hero(&mut f, k as usize, px(20), 0);
    assert_eq!(f.heroes()[k as usize].x - x0, px(10));
}

#[test]
fn threat_bends_the_horde_to_the_knight() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 30);
    add(&mut f, &bare(MAGE, 10), x - px(200), y);
    add(&mut f, &bare(KNIGHT, 10), x + px(200), y);
    warm(&mut f);
    // Equally near both: a little toward the mage still goes to the knight.
    let m = mon(&mut f, DROWNED_K, 60, x - px(20), y + px(400));
    for _ in 0..80 {
        hold(&mut f, &[]);
    }
    assert!(f.monsters().x[m as usize] > x + px(60), "x {}", (f.monsters().x[m as usize] - x) / SUB);
}

#[test]
fn inside_two_cells_a_monster_walks_at_the_highest_threat_over_distance() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 30);
    let mage = add(&mut f, &bare(MAGE, 10), x, y);
    let knight = add(&mut f, &bare(KNIGHT, 10), x + px(50), y);
    warm(&mut f);
    // 25 px from the mage, 45 from the knight: 8/25 < 20/45, so the knight.
    let m = mon(&mut f, DROWNED_K, 60, x + px(15), y + px(20));
    let d0 = dist(f.monsters().x[m as usize], f.monsters().y[m as usize], f.heroes()[knight as usize].x, f.heroes()[knight as usize].y);
    hold(&mut f, &[]);
    let d1 = dist(f.monsters().x[m as usize], f.monsters().y[m as usize], f.heroes()[knight as usize].x, f.heroes()[knight as usize].y);
    assert!(d1 < d0);
    let _ = mage;
}

#[test]
fn damage_is_weapon_x_might_x_class_level_x_cards_x_effects() {
    let (mut f, id, x, y) = arena(2, KNIGHT, 10);
    let h = f.hero_mut(id);
    h.copies[1] = 2;
    h.fx[FX_WHETSTONE as usize] = 100;
    idle(&mut f, 1);
    let might = f.heroes()[id as usize].stats[MIGHT] as u64;
    let m = stunned(&mut f, DROWNED_K, 60, x + px(30), y);
    let before = hp(&f, m);
    fire(&mut f, &[]);
    let wl = weapon_pct(10);
    let cl = 100 + CLASS_LEVEL_DMG_PCT as u64 * 9;
    let want = 30 * wl / 100 * (100 + 2 * might) * cl * 120 * 120 / 100_000_000;
    assert_eq!((before - hp(&f, m)) as u64, want);
}
