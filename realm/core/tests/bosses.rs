//! Bosses (rules section 8): the table against the contract, the eight attack shapes, phases, health, chests,
//! the world boss.
mod common;
use common::*;

const TIDE_EV: u8 = 12;
const REWARD_EV: u8 = 15;

fn contract() -> String {
    std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../../docs/realm/rules.md")).expect("docs/realm/rules.md")
}

fn table(doc: &str, head: &str) -> Vec<Vec<String>> {
    let lines: Vec<&str> = doc.lines().collect();
    let at = lines.iter().position(|l| l.starts_with(head)).unwrap_or_else(|| panic!("no table {head}"));
    lines[at + 2..].iter().take_while(|l| l.starts_with('|')).map(|l| l.trim_matches('|').split('|').map(|c| c.trim().to_string()).collect()).collect()
}

fn shape_idx(which: u8, shape: u8) -> u8 {
    BOSSES[which as usize]
        .attacks
        .iter()
        .position(|a| a.shape == shape)
        .unwrap_or_else(|| panic!("{} has no {}", BOSSES[which as usize].name, ATTACK_NAMES[shape as usize])) as u8
}

fn atk(which: u8, shape: u8) -> Atk {
    BOSSES[which as usize].attacks[shape_idx(which, shape) as usize]
}

/// A quiet field of `field` with a held boss of row `which` at an open square, and its place.
fn boss_arena(_field: u8, which: u8) -> (Field, i32, i32) {
    // The ground is THE FOOL'S ROAD's open middle whichever field the boss belongs to: a shape does not read the map.
    let mut f = quiet(0);
    let (x, y) = spot(&f, 40);
    // A hero far away keeps the field alive (flow, grids); the tests add their own near the boss.
    f.summon_boss(which, 1_000_000_000, x, y);
    f.hold_boss();
    (f, x, y)
}

fn boss_events(f: &Field) -> Vec<(u8, u8, u32)> {
    f.events().iter().filter_map(|e| if let Event::Boss { which, state, health } = *e { Some((which, state, health)) } else { None }).collect()
}

/// Steps until hero `q` is hurt; the tick count (1-based), or None in `max` ticks.
fn until_hurt(f: &mut Field, q: u16, max: u32) -> Option<u32> {
    for t in 1..=max {
        f.step::<u16>(&[]);
        if f.heroes()[q as usize].hurt {
            return Some(t);
        }
    }
    None
}

fn lost(f: &Field, q: u16, before: u32) -> u32 {
    before - f.heroes()[q as usize].health
}

#[test]
fn the_boss_table_matches_the_contract() {
    let rows = table(&contract(), "| Boss | Field | Moves | Attacks");
    assert_eq!(rows.len(), 8, "seven field bosses and the world boss");
    let kinds_of = |s: &str| -> Option<u8> { KINDS.iter().position(|k| s.contains(k.name)).map(|k| k as u8) };
    for r in &rows {
        let names: Vec<&str> = r[0].split(" and ").collect();
        for (i, name) in names.iter().enumerate() {
            let name = name.split(" in turn").next().unwrap().split(" (world boss)").next().unwrap().trim();
            let which = BOSSES.iter().position(|b| b.name == name).unwrap_or_else(|| panic!("no boss {name}"));
            let b = &BOSSES[which];
            let want_field = ["Fool's Road", "Hanged Wood", "Moon Marsh", "Hermit's Peaks", "Tower", "World's Edge"].iter().position(|n| r[1].contains(n));
            if let Some(fl) = want_field {
                assert_eq!(b.field as usize, fl, "{name}");
            } else {
                assert_eq!(b.field, ANY_FIELD, "{name}: {}", r[1]);
            }
            assert_eq!(b.speed > 0, r[2].contains("walks"), "{name}: {}", r[2]);
            assert_eq!(b.attacks.iter().any(|a| a.shape == A_LANES), r[2].contains("lanes") || r[3].contains("lanes"), "{name}");
            // Each shape the contract names is in the row; numbers where it gives them.
            for (si, sname) in ATTACK_NAMES.iter().enumerate() {
                let named = r[3].contains(sname);
                let has = b.attacks.iter().any(|a| a.shape == si as u8);
                if named && *sname != "lanes" {
                    assert!(has, "{name} lacks {sname}");
                }
                if has && !named && !r[2].contains(sname) && name != "THE UNMADE KING" && !name.starts_with("DEATH") && i == 0 {
                    // The only extras the table does not spell out: the pull before the tree's slam is spelled, the
                    // chandelier's two named attacks too. A shape in a row but not in the contract is a mistake.
                    panic!("{name} has {sname}, the contract does not");
                }
            }
            // The numbers.
            let cell = r[3].replace("hanged men", "hanged man");
            let words: Vec<&str> = cell.split([';', ',']).map(|s| s.trim()).collect();
            for w in words {
                let n: Vec<i32> = w.split(|c: char| !c.is_ascii_digit()).filter(|s| !s.is_empty()).map(|s| s.parse().unwrap()).collect();
                if w.starts_with("sweep") && !n.is_empty() {
                    assert_eq!(atk(which as u8, A_SWEEP).px, n[0], "{name} sweep");
                }
                if w.starts_with("slam") && !n.is_empty() {
                    assert_eq!(atk(which as u8, A_SLAM).px, n[0], "{name} slam");
                }
                if w.starts_with("pull") && !n.is_empty() {
                    assert_eq!(atk(which as u8, A_PULL).px, n[0], "{name} pull");
                }
                if w.starts_with("candles") && n.len() == 2 {
                    let a = atk(which as u8, A_CANDLES);
                    assert_eq!((a.count as i32, a.px), (n[0], n[1]), "{name} candles");
                }
                if w.starts_with("call") && !n.is_empty() && !w.contains("tide") {
                    let a = atk(which as u8, A_CALL);
                    assert_eq!(a.count as i32, n[0], "{name} call");
                    let k = kinds_of(w).unwrap_or_else(|| panic!("{name}: no kind in {w}"));
                    assert_eq!(a.kind, k, "{name} call kind");
                }
            }
        }
    }
    // The world boss calls a tide's worth of the field's kinds; the Unmade King has every shape and two at once.
    assert_eq!(atk(B_DEATH, A_CALL).kind, CALL_FIELD_KINDS);
    for s in 0..ATTACK_SHAPES as u8 {
        assert!(BOSSES[B_UNMADE_KING as usize].attacks.iter().any(|a| a.shape == s), "the king lacks {}", ATTACK_NAMES[s as usize]);
    }
    assert_eq!(BOSSES[B_UNMADE_KING as usize].twice_from, 1);
    assert_eq!(atk(B_UNMADE_KING, A_LANES).phase, 1, "lanes at half health");
    // Every attack is complete: a shape that needs a duration or a reach has one; chains point at a real attack.
    for b in BOSSES.iter() {
        assert!(!b.attacks.is_empty());
        assert!(KINDS.len() > b.carrier as usize);
        for a in b.attacks {
            assert!(a.warn > 0, "{}: every shape is drawn first", b.name);
            if a.shape == A_SWEEP || a.shape == A_WALL {
                assert!(a.dur > 0, "{}", b.name);
            }
            if matches!(a.shape, A_CANDLES | A_LANES | A_MIRE) {
                assert!(a.reach > 0 && a.count > 0, "{}", b.name);
            }
            if a.shape == A_MIRE {
                assert!(a.dur > 0);
            }
            if a.shape == A_CALL {
                assert!(a.count > 0 && (a.kind == CALL_FIELD_KINDS || (a.kind as usize) < KINDS.len()));
            }
            if a.then != NO_NEXT {
                assert!((a.then as usize) < b.attacks.len());
            }
            assert!(a.phase <= BOSS_PHASES.len() as u8);
        }
    }
}

#[test]
fn a_slam_is_drawn_then_lands_on_a_ring_around_the_boss() {
    let (mut f, x, y) = boss_arena(0, B_HARVESTER);
    let a = atk(B_HARVESTER, A_SLAM);
    let near = add(&mut f, &bare(MAGE, 10), x + px(100), y);
    let far = add(&mut f, &bare(MAGE, 10), x + px(400), y);
    f.step::<u16>(&[]);
    let (nh, fh) = (f.heroes()[near as usize].health, f.heroes()[far as usize].health);
    f.cast_boss(shape_idx(B_HARVESTER, A_SLAM));
    let t = until_hurt(&mut f, near, 200).expect("it lands");
    assert_eq!(t, a.warn as u32 + 1, "drawn for `warn` ticks, then lands");
    let expect = nh as u64 * a.dmg as u64 / 1000;
    let taken = lost(&f, near, nh) as u64;
    assert!(taken >= expect * 95 / 100 && taken <= expect, "{taken} of {expect}: a share of her health");
    assert_eq!(f.heroes()[far as usize].health, fh, "outside the ring: untouched");
    assert!(f.boss().unwrap().casts.is_empty(), "one landing");
}

#[test]
fn candles_fall_on_heroes_in_reach_and_not_on_the_rest() {
    let (mut f, x, y) = boss_arena(1, B_HANGING_TREE);
    let a = atk(B_HANGING_TREE, A_CANDLES);
    let in_reach: Vec<u16> = (0..3).map(|i| add(&mut f, &bare(MAGE, 10), x + px(200 + i * 100), y + px(i * 60))).collect();
    let out = add(&mut f, &bare(MAGE, 10), x + px(a.reach + 300), y);
    f.step::<u16>(&[]);
    f.cast_boss(shape_idx(B_HANGING_TREE, A_CANDLES));
    let before: Vec<u32> = in_reach.iter().map(|&q| f.heroes()[q as usize].health).collect();
    f.step::<u16>(&[]);
    assert_eq!(f.boss().unwrap().casts[0].pts.len(), 3, "a circle on each hero in reach (at most `count`)");
    for _ in 0..a.warn {
        f.step::<u16>(&[]);
    }
    for (k, &q) in in_reach.iter().enumerate() {
        assert!(lost(&f, q, before[k]) > 0, "hero {k} was under a candle");
    }
    assert_eq!(f.heroes()[out as usize].health, f.heroes()[out as usize].max_health);
}

#[test]
fn a_sweep_turns_and_hurts_what_it_crosses() {
    let (mut f, x, y) = boss_arena(0, B_HARVESTER);
    let a = atk(B_HARVESTER, A_SWEEP);
    let first = add(&mut f, &bare(MAGE, 10), x + px(150), y);
    f.step::<u16>(&[]);
    f.cast_boss(shape_idx(B_HARVESTER, A_SWEEP));
    f.step::<u16>(&[]);
    let c = f.boss().unwrap().casts[0].clone();
    // The beam starts on the hero it picked; a hero opposite is reached half a turn (about 120 ticks) later.
    let ang = (c.angle >> 4) as f64 + 180.0;
    let (ox, oy) = ((ang.to_radians().cos() * 150.0) as i32, (ang.to_radians().sin() * 150.0) as i32);
    let opposite = add(&mut f, &bare(MAGE, 10), x + px(ox), y + px(oy));
    let beam_start = ((c.angle >> 4) as f64).to_radians();
    f.hero_mut(first).x = x + px((beam_start.cos() * 150.0) as i32);
    f.hero_mut(first).y = y + px((beam_start.sin() * 150.0) as i32);
    let (mut first_hit, mut opposite_hit) = (None, None);
    let slot = f.boss().unwrap().slot as usize;
    for t in 0..(a.warn + a.dur + 10) as u32 {
        for q in [first, opposite] {
            f.hero_mut(q).health = f.heroes()[q as usize].max_health;
        }
        // The harvester walks; the test holds it where the beam was drawn.
        f.monsters_mut().x[slot] = x;
        f.monsters_mut().y[slot] = y;
        f.step::<u16>(&[]);
        if f.heroes()[first as usize].hurt && first_hit.is_none() {
            first_hit = Some(t);
        }
        if f.heroes()[opposite as usize].hurt && opposite_hit.is_none() {
            opposite_hit = Some(t);
        }
    }
    let (fh, oh) = (first_hit.expect("the hero on the beam"), opposite_hit.expect("the beam turned to her"));
    assert!(fh <= a.warn as u32 + 6, "hit as it goes live: {fh}");
    assert!(oh > fh + 90, "the beam turns: {fh} then {oh}");
    assert!(f.boss().unwrap().casts.is_empty(), "over after `dur`");
}

#[test]
fn two_sweeps_turn_opposite_ways() {
    let (mut f, x, y) = boss_arena(3, B_GOAT_PROPHET);
    let a = atk(B_GOAT_PROPHET, A_SWEEP);
    assert_eq!(a.count, 2);
    let first = add(&mut f, &bare(MAGE, 10), x + px(200), y);
    f.step::<u16>(&[]);
    f.cast_boss(shape_idx(B_GOAT_PROPHET, A_SWEEP));
    f.step::<u16>(&[]);
    let base = (f.boss().unwrap().casts[0].angle >> 4) as f64;
    let at = |deg: f64| (x + px((deg.to_radians().cos() * 200.0) as i32), y + px((deg.to_radians().sin() * 200.0) as i32));
    // After 40 active ticks (1.5 degrees each) beam 0 is at +60 degrees and beam 1 at 180 - 60.
    let (px0, py0) = at(base + 60.0);
    let (px1, py1) = at(base + 180.0 - 60.0);
    let (px2, py2) = at(base + 180.0 + 60.0);
    let h0 = add(&mut f, &bare(MAGE, 10), px0, py0);
    let h1 = add(&mut f, &bare(MAGE, 10), px1, py1);
    let h2 = add(&mut f, &bare(MAGE, 10), px2, py2);
    f.hero_mut(first).x = at(base).0;
    f.hero_mut(first).y = at(base).1;
    let mut hit = [None; 3];
    for t in 0..(a.warn + 60) as u32 {
        for q in [h0, h1, h2, first] {
            f.hero_mut(q).health = f.heroes()[q as usize].max_health;
        }
        f.step::<u16>(&[]);
        for (k, q) in [h0, h1, h2].into_iter().enumerate() {
            if f.heroes()[q as usize].hurt && hit[k].is_none() {
                hit[k] = Some(t);
            }
        }
    }
    let (t0, t1) = (hit[0].expect("beam 0 reached +60"), hit[1].expect("beam 1 reached 180 - 60"));
    assert!((t0 as i32 - t1 as i32).abs() <= 6, "both at once: {t0} {t1}");
    assert!(hit[2].is_none_or(|t| t > t0 + 20), "the other way round is not where beam 1 is: {:?}", hit[2]);
}

#[test]
fn a_lane_ride_carries_the_boss_across_its_ground_and_strikes_each_hero_once_a_ride() {
    let (mut f, x, y) = boss_arena(4, B_GHOSTWRITER);
    let a = atk(B_GHOSTWRITER, A_LANES);
    assert_eq!(a.count, 2);
    let hero = add(&mut f, &bare(MAGE, 10), x + px(600), y);
    f.hero_mut(hero).max_health = 1_000_000;
    f.hero_mut(hero).health = 1_000_000;
    f.step::<u16>(&[]);
    f.cast_boss(shape_idx(B_GHOSTWRITER, A_LANES));
    let (mut hits, mut far) = (0, 0i64);
    let mut telegraph_seen = false;
    for _ in 0..(a.warn as u32 + 52) * 2 + 40 {
        f.step::<u16>(&[]);
        hits += f.heroes()[hero as usize].hurt as u32;
        let (bx, _) = f.boss_pos().unwrap();
        far = far.max(((bx - x) as i64).abs() / SUB as i64);
        telegraph_seen |= f.boss().unwrap().casts.first().is_some_and(|c| c.pts.len() == 1 && c.age < a.warn);
    }
    assert!(telegraph_seen, "the lane is drawn first");
    assert!(far >= 900, "the boss rode {far} px");
    assert_eq!(hits, 2, "once on the way out and once on the way back");
    assert!(f.boss().unwrap().casts.is_empty());
}

#[test]
fn a_call_brings_the_named_clutch_and_the_second_kind() {
    for (field, which, kind_name, n, second) in [
        (0u8, B_HARVESTER, "carrion crow", 30usize, None),
        (1, B_HANGING_TREE, "hanged man", 20, None),
        (2, B_MOTHER, "leech", 60, None),
        (3, B_GOAT_PROPHET, "goat cultist", 12, Some(("bone piper", 1usize))),
        (4, B_CHANDELIER, "cinderling", 40, None),
    ] {
        let (mut f, x, y) = boss_arena(field, which);
        add(&mut f, &bare(KNIGHT, 10), x + px(300), y);
        guard(&mut f, 0);
        f.step::<u16>(&[]);
        let before = f.monster_count();
        let a = atk(which, A_CALL);
        f.cast_boss(shape_idx(which, A_CALL));
        for _ in 0..a.warn {
            f.step::<u16>(&[]);
            assert_eq!(f.monster_count(), before, "{} calls only when the warning is over", BOSSES[which as usize].name);
            guard(&mut f, 0);
        }
        f.step::<u16>(&[]);
        let m = f.monsters();
        let k = kind(kind_name) as usize;
        let count = |kd: usize| (0..m.len()).filter(|&i| m.hp[i] > 0 && m.kind[i] as usize == kd && m.flags[i] & BOSS == 0).count();
        // Some of them may be dead of the hero's blows already; most are there.
        assert!(count(k) >= n * 9 / 10 && count(k) <= n, "{kind_name}: {} of {n}", count(k));
        if let Some((k2, n2)) = second {
            assert_eq!(count(kind(k2) as usize), n2);
        }
        let (bx, by) = f.boss_pos().unwrap();
        for i in 0..m.len() {
            if m.hp[i] > 0 && m.kind[i] as usize == k && m.flags[i] & BOSS == 0 {
                assert!(dist(m.x[i], m.y[i], bx, by) <= 175 * SUB as i64, "called around the boss");
            }
        }
        assert_eq!(m.level[(0..m.len()).find(|&i| m.hp[i] > 0 && m.kind[i] as usize == k && m.flags[i] & BOSS == 0).unwrap()], FIELDS[0].top);
    }
}

#[test]
fn mire_zones_slow_heroes_and_dry_up() {
    let (mut f, x, y) = boss_arena(2, B_MOTHER);
    let a = atk(B_MOTHER, A_MIRE);
    let in_reach = add(&mut f, &bare(MAGE, 10), x + px(300), y);
    let out = add(&mut f, &bare(MAGE, 10), x + px(a.reach + 400), y);
    f.step::<u16>(&[]);
    let (m0, m1) = (f.mods(in_reach).unwrap().move_pct, f.mods(out).unwrap().move_pct);
    f.cast_boss(shape_idx(B_MOTHER, A_MIRE));
    for _ in 0..a.warn + 2 {
        f.step::<u16>(&[]);
    }
    assert_eq!(f.boss().unwrap().mires.len(), 1, "a patch under the one hero in reach");
    assert_eq!(f.mods(in_reach).unwrap().move_pct, m0 - 40, "slowed 40%");
    assert_eq!(f.mods(out).unwrap().move_pct, m1, "the other is not");
    for _ in 0..a.dur {
        f.step::<u16>(&[]);
    }
    assert!(f.boss().unwrap().mires.is_empty());
    assert_eq!(f.mods(in_reach).unwrap().move_pct, m0, "dried up");
}

#[test]
fn a_pull_drags_heroes_inward_and_the_chained_slam_then_hits_them() {
    let (mut f, x, y) = boss_arena(1, B_HANGING_TREE);
    let pull = atk(B_HANGING_TREE, A_PULL);
    let slam = atk(B_HANGING_TREE, A_SLAM);
    assert_eq!(pull.then, shape_idx(B_HANGING_TREE, A_SLAM), "pull then slam");
    let hero = add(&mut f, &bare(MAGE, 10), x + px(280), y);
    let out = add(&mut f, &bare(MAGE, 10), x + px(pull.px + 100), y);
    f.step::<u16>(&[]);
    let start = f.heroes()[hero as usize].x;
    let h0 = f.heroes()[hero as usize].health;
    f.cast_boss(shape_idx(B_HANGING_TREE, A_PULL));
    for _ in 0..pull.warn + 1 {
        f.step::<u16>(&[]);
    }
    let pulled = (start - f.heroes()[hero as usize].x) / SUB;
    assert!((135..=145).contains(&pulled), "dragged 140 px: {pulled}");
    assert_eq!(f.heroes()[out as usize].x, x + px(pull.px + 100), "beyond the reach: untouched");
    assert_eq!(f.heroes()[hero as usize].health, h0, "the pull itself does no harm");
    assert!(f.boss().unwrap().casts.iter().any(|c| c.atk == pull.then), "the slam is already drawn");
    for _ in 0..slam.warn + 2 {
        f.step::<u16>(&[]);
    }
    assert!(f.heroes()[hero as usize].health < h0, "inside 200 px now, the slam lands on her");
}

#[test]
fn a_ring_of_fire_closes_and_leaves_a_door() {
    let (mut f, x, y) = boss_arena(4, B_GHOSTWRITER);
    let a = atk(B_GHOSTWRITER, A_WALL);
    let on_ring = add(&mut f, &bare(MAGE, 10), x, y);
    let away = add(&mut f, &bare(MAGE, 10), x, y);
    let in_door = add(&mut f, &bare(MAGE, 10), x, y);
    let inside = add(&mut f, &bare(MAGE, 10), x, y);
    f.step::<u16>(&[]);
    f.cast_boss(shape_idx(B_GHOSTWRITER, A_WALL));
    f.step::<u16>(&[]);
    let door = (f.boss().unwrap().casts[0].angle >> 4) as f64;
    let at = |deg: f64, r: i32| (x + px((deg.to_radians().cos() * r as f64) as i32), y + px((deg.to_radians().sin() * r as f64) as i32));
    // On the ring's path: 20 px inside its start radius, where it passes over a hero standing still.
    let r0 = a.px - 20;
    for (q, deg, r) in [(on_ring, door + 180.0, r0), (away, door + 90.0, r0), (in_door, door, r0), (inside, door, 0)] {
        let (hx, hy) = at(deg, r);
        f.hero_mut(q).x = hx;
        f.hero_mut(q).y = hy;
    }
    let hurt_at = |f: &mut Field, hs: &[u16], ticks: u32| {
        let mut hit = vec![false; hs.len()];
        for _ in 0..ticks {
            for &q in hs {
                f.hero_mut(q).health = f.heroes()[q as usize].max_health;
            }
            f.step::<u16>(&[]);
            for (k, &q) in hs.iter().enumerate() {
                hit[k] |= f.heroes()[q as usize].hurt;
            }
        }
        hit
    };
    let hit = hurt_at(&mut f, &[on_ring, away, in_door, inside], a.warn as u32 + 40);
    assert!(hit[0] && hit[1], "on the ring's path: burned as it passes");
    assert!(!hit[2], "in the door: safe");
    assert!(!hit[3], "in the middle: the ring stops at 60 px");
    // It closes on the ones who stay: 100 px from the centre, away from the door.
    let (hx, hy) = at(door + 90.0, 100);
    f.hero_mut(inside).x = hx;
    f.hero_mut(inside).y = hy;
    let hit = hurt_at(&mut f, &[inside], a.dur as u32);
    assert!(hit[0], "the ring closes over her");
    assert!(f.boss().unwrap().casts.is_empty());
}

#[test]
fn a_boss_takes_no_stun_slow_or_push_and_does_not_walk_by_the_flow_when_rooted() {
    let (mut f, x, y) = boss_arena(1, B_HANGING_TREE);
    add(&mut f, &bare(KNIGHT, 10), x + px(100), y);
    let slot = f.boss().unwrap().slot as usize;
    assert!(f.monsters().immovable(slot));
    f.monsters_mut().stun[slot] = 0;
    let pos = f.boss_pos().unwrap();
    for _ in 0..200 {
        f.step::<u16>(&[]);
    }
    assert_eq!(f.boss_pos().unwrap(), pos, "a rooted boss stays");
    assert_eq!(f.monsters().stun[slot], 0);
    // A walker walks (THE HARVESTER, 20 px/s).
    let (mut g, x, y) = boss_arena(0, B_HARVESTER);
    add(&mut g, &bare(KNIGHT, 10), x + px(600), y);
    let p0 = g.boss_pos().unwrap();
    for _ in 0..100 {
        g.step::<u16>(&[]);
    }
    let p1 = g.boss_pos().unwrap();
    assert!(dist(p0.0, p0.1, p1.0, p1.1) >= 95 * SUB as i64 && dist(p0.0, p0.1, p1.0, p1.1) <= 105 * SUB as i64, "20 px/s for 5 s");
}

#[test]
fn a_drainer_boss_heals_by_half_of_what_she_deals() {
    let (mut f, x, y) = boss_arena(2, B_MOTHER);
    let a = atk(B_MOTHER, A_SLAM);
    let hero = add(&mut f, &bare(MAGE, 10), x + px(60), y);
    f.step::<u16>(&[]);
    let slot = f.boss().unwrap().slot as usize;
    let maxhp = f.boss().unwrap().max_hp;
    f.monsters_mut().hp[slot] = maxhp / 2;
    let h0 = f.heroes()[hero as usize].health;
    f.cast_boss(shape_idx(B_MOTHER, A_SLAM));
    for _ in 0..100 {
        // Her blows would wound the boss too: hold the hero's weapon back.
        f.hero_mut(hero).charge = 0;
        f.step::<u16>(&[]);
        if f.heroes()[hero as usize].hurt {
            break;
        }
    }
    let taken = lost(&f, hero, h0) as u64;
    assert_eq!(a.dmg, 400);
    let healed = f.monsters().hp[slot] as u64 - (maxhp / 2) as u64;
    assert_eq!(healed, taken / 2, "she heals half of what she dealt");
}

fn rise_field(field: u8, n: u32, heroes: u32) -> Field {
    let mut f = Field::open(field, 7, Config { monsters: 512, threads: 1 });
    f.set_births(false);
    let (rise, _) = field_boss_window(field, n);
    f.set_clock(rise - 1);
    for i in 0..heroes as i32 {
        f.join(&Sheet::bench(KNIGHT, HUMAN, 10), &Outing::new(), FIELD / 2 + px(i % 10 * 20 - 100), FIELD / 2 + px(i / 10 * 20 - 100));
    }
    f
}

#[test]
fn a_field_boss_rises_at_the_heart_with_health_from_the_heroes_there_and_leaves_after_eight_minutes() {
    let mut f = rise_field(0, 3, 5);
    let mut rises = Vec::new();
    for _ in 0..2 {
        f.step::<u16>(&[]);
        rises.extend(boss_events(&f));
    }
    // (40,000 + 6,000 x 5) x 262% (level 10).
    assert_eq!(rises, vec![(B_HARVESTER, BOSS_RISES, 183_400)]);
    let (hp, max) = f.boss_health().unwrap();
    assert_eq!((hp, max), (183_400, 183_400));
    let (bx, by) = f.boss_pos().unwrap();
    assert!(dist(bx, by, FIELD / 2, FIELD / 2) < 200 * SUB as i64, "at the heart");
    let slot = f.boss().unwrap().slot;
    assert_eq!(f.monsters().kind[slot as usize], KINDS.iter().position(|k| k.name == "gravedigger").unwrap() as u8);
    assert_eq!(f.monsters().flags[slot as usize], BOSS);
    // 8 minutes: it leaves, once; no second boss for the same tide.
    let mut left = 0;
    let mut risen_again = 0;
    for _ in 0..9_700 {
        f.step::<u16>(&[]);
        for e in boss_events(&f) {
            left += (e.1 == BOSS_LEFT) as u32;
            risen_again += (e.1 == BOSS_RISES) as u32;
        }
    }
    assert_eq!((left, risen_again), (1, 0));
    assert!(f.boss().is_none());
    assert_eq!(f.monster_count(), 0, "its slot is free");
    assert_eq!(f.heroes()[0].boss_contrib, 0);
}

#[test]
fn health_counts_at_most_six_hundred_in_the_heart_and_none_from_other_rings() {
    let mut f = Field::open(0, 7, Config { monsters: 64, threads: 1 });
    f.set_births(false);
    let (rise, _) = field_boss_window(0, 3);
    f.set_clock(rise - 1);
    for i in 0..650i32 {
        f.join(&Sheet::bench(KNIGHT, HUMAN, 10), &Outing::new(), FIELD / 2 + px(i % 26 * 12 - 150), FIELD / 2 + px(i / 26 * 12 - 150));
    }
    for i in 0..10i32 {
        f.join(&Sheet::bench(KNIGHT, HUMAN, 10), &Outing::new(), FIELD / 2 + px(3_000 + i * 10), FIELD / 2);
    }
    f.step::<u16>(&[]);
    // 600 counted: (40,000 + 6,000 x 600) x 262%.
    assert_eq!(f.boss_health().unwrap().1, 3_640_000 * 262 / 100);
}

#[test]
fn a_tide_won_makes_the_boss_a_fifth_weaker_and_a_tide_lost_makes_it_hit_a_fifth_harder() {
    let n = 3;
    for won in [true, false] {
        let mut f = Field::open(0, 7, Config { monsters: 64, threads: 1 });
        f.set_births(false);
        f.set_clock(tide_start(0, n) - 1);
        let h = f.join(&Sheet::bench(KNIGHT, HUMAN, 10), &Outing::new(), FIELD / 2, FIELD / 2);
        f.step::<u16>(&[]);
        if won {
            // Two heroes on the lit altars for a minute.
            let lit: Vec<usize> = (0..6).filter(|&a| f.altars()[a].state == ALTAR_LIT).collect();
            for &a in &lit[..2] {
                let (ax, ay) = f.terrain().altars[a];
                f.join(&Sheet::bench(KNIGHT, HUMAN, 10), &Outing::new(), ax, ay);
            }
            let mut verdict = 0;
            for _ in 0..1_300 {
                f.step::<u16>(&[]);
                for e in f.events() {
                    if let Event::Tide { state, .. } = e {
                        verdict = *state;
                    }
                }
            }
            assert_eq!(verdict, TIDE_WON);
        } else {
            for _ in 0..6_100 {
                f.step::<u16>(&[]);
            }
            assert_eq!(f.realm().result, TIDE_LOST);
        }
        let _ = h;
        let (rise, _) = field_boss_window(0, n);
        f.set_clock(rise - 1);
        f.step::<u16>(&[]);
        let hp = f.boss_health().unwrap().1 as u64;
        let heart = f.heroes().iter().filter(|h| h.present && dist(h.x, h.y, FIELD / 2, FIELD / 2) < 2_500 * SUB as i64).count() as u64;
        let full = (40_000 + 6_000 * heart) * 262 / 100;
        if won {
            assert_eq!(hp, full * 80 / 100, "20% less health");
            assert_eq!(f.boss().unwrap().dmg_pct, 100);
        } else {
            assert_eq!(hp, full, "full health");
            assert_eq!(f.boss().unwrap().dmg_pct, 120, "20% more damage");
        }
    }
}

#[test]
fn the_tower_alternates_its_two_bosses() {
    for (n, which) in [(3u32, B_CHANDELIER), (7, B_GHOSTWRITER), (11, B_CHANDELIER)] {
        let mut f = rise_field(4, n, 2);
        f.step::<u16>(&[]);
        assert_eq!(f.boss().unwrap().which, which, "tide {n}");
    }
    for (field, which) in [(0u8, B_HARVESTER), (1, B_HANGING_TREE), (2, B_MOTHER), (3, B_GOAT_PROPHET), (5, B_UNMADE_KING)] {
        assert_eq!(field_boss_of(field, 0), which);
        assert_eq!(BOSSES[which as usize].field, field);
    }
}

#[test]
fn phases_come_at_two_thirds_and_one_third_health_once_each() {
    let (mut f, x, y) = boss_arena(0, B_HARVESTER);
    add(&mut f, &bare(KNIGHT, 10), x + px(900), y);
    let slot = f.boss().unwrap().slot as usize;
    let max = f.boss().unwrap().max_hp;
    let mut phases = Vec::new();
    for hp_pct in [90u32, 70, 65, 60, 40, 30, 20] {
        f.monsters_mut().hp[slot] = (max as u64 * hp_pct as u64 / 100) as u32;
        for _ in 0..3 {
            f.step::<u16>(&[]);
            for e in boss_events(&f) {
                if e.1 == BOSS_PHASE {
                    phases.push((hp_pct, e.2));
                }
            }
        }
    }
    assert_eq!(phases.len(), 2, "{phases:?}");
    assert_eq!(phases[0].0, 65);
    assert_eq!(phases[1].0, 30);
    assert_eq!(f.boss().unwrap().phase, 2);
    // Each phase shortens the rest between casts by 20%.
}

/// Runs a boss that casts by itself for `ticks` with its health held at `pct`, against one hero who cannot die;
/// returns the shapes seen and the most casts out at once.
fn cast_for(f: &mut Field, hero: u16, (x, y): (i32, i32), pct: u64, ticks: u32) -> ([bool; ATTACK_SHAPES], usize) {
    let which = f.boss().unwrap().which;
    let row = &BOSSES[which as usize];
    let slot = f.boss().unwrap().slot as usize;
    let max = f.boss().unwrap().max_hp as u64;
    let (mut shapes, mut most) = ([false; ATTACK_SHAPES], 0);
    for _ in 0..ticks {
        f.monsters_mut().hp[slot] = (max * pct / 100) as u32;
        f.step::<u16>(&[]);
        let Some(b) = f.boss() else { break };
        most = most.max(b.casts.len());
        for c in &b.casts {
            shapes[row.attacks[c.atk as usize].shape as usize] = true;
        }
        let h = f.hero_mut(hero);
        h.health = h.max_health;
        h.x = x + px(500);
        h.y = y;
    }
    (shapes, most)
}

#[test]
fn the_unmade_king_adds_lanes_and_casts_two_at_once_from_the_first_phase() {
    let mut f = quiet(0);
    let (x, y) = spot(&f, 40);
    let hero = add(&mut f, &bare(KNIGHT, 10), x + px(500), y);
    f.hero_mut(hero).max_health = 1_000_000_000;
    f.summon_boss(B_UNMADE_KING, 1_000_000_000, x, y);
    let (calm, most0) = cast_for(&mut f, hero, (x, y), 90, 3_000);
    assert!(!calm[A_LANES as usize], "no lanes above two thirds");
    for s in [A_SWEEP, A_SLAM, A_CALL, A_WALL, A_MIRE, A_CANDLES, A_PULL] {
        assert!(calm[s as usize], "phase 0 casts {}", ATTACK_NAMES[s as usize]);
    }
    assert_eq!(most0, 1, "one at a time");
    let (hard, most1) = cast_for(&mut f, hero, (x, y), 60, 3_000);
    assert!(hard[A_LANES as usize], "lanes from the first phase");
    assert_eq!(most1, 2, "two at a time");
}

#[test]
fn a_boss_is_not_recycled_and_keeps_its_slot_far_from_every_hero() {
    let (mut f, _, _) = boss_arena(1, B_HANGING_TREE);
    add(&mut f, &bare(KNIGHT, 10), px(1_200), px(15_000));
    for _ in 0..400 {
        f.step::<u16>(&[]);
    }
    assert!(f.boss().is_some());
    assert_eq!(f.recycled(), 0);
}

#[test]
fn a_boss_killed_pays_a_chest_once_to_heroes_past_the_floor() {
    let mut f = rise_field(0, 3, 4);
    f.step::<u16>(&[]);
    f.hold_boss();
    let slot = f.boss().unwrap().slot as usize;
    let max = f.boss().unwrap().max_hp;
    let floor = (max as u64 * 2 / 1000) as u32;
    assert_eq!(floor, 335);
    // Heroes 0 and 1 are past the floor, 2 exactly on it, 3 just under.
    f.hero_mut(0).boss_contrib = floor * 10;
    f.hero_mut(1).boss_contrib = floor + 1;
    f.hero_mut(2).boss_contrib = floor;
    f.hero_mut(3).boss_contrib = floor - 1;
    let coin0: Vec<u32> = (0..4).map(|i| f.heroes()[i].coin).collect();
    f.monsters_mut().hp[slot] = 1;
    let (bx, by) = f.boss_pos().unwrap();
    f.hero_mut(0).x = bx;
    f.hero_mut(0).y = by;
    let mut events = Vec::new();
    let mut rewards = Vec::new();
    let mut kills = 0;
    for _ in 0..30 {
        f.step::<u16>(&[]);
        events.extend(boss_events(&f));
        for e in f.events() {
            match *e {
                Event::Reward { kind, first, count, .. } => rewards.push((kind, f.rewarded(first, count).to_vec())),
                Event::Kill { flags, .. } if flags & BOSS != 0 => kills += 1,
                _ => {}
            }
        }
    }
    assert_eq!(events.iter().filter(|e| e.1 == BOSS_KILLED).count(), 1, "KILLED once: {events:?}");
    assert_eq!(kills, 1, "one KILL event with the boss flag");
    assert_eq!(rewards.len(), 1);
    assert_eq!(rewards[0].0, R_BOSS_CHEST);
    let ids: Vec<u16> = rewards[0].1.iter().map(|p| p.0).collect();
    assert_eq!(ids, vec![0, 1, 2], "best first, ties by id, the floor itself counts");
    for i in 0..3 {
        assert!(f.heroes()[i].coin > coin0[i], "hero {i} has coin");
    }
    assert_eq!(f.heroes()[3].coin, coin0[3]);
    assert!(f.boss().is_none());
    assert_eq!(f.monster_count(), 0);
}

#[test]
fn the_world_boss_has_ten_times_the_health_a_hundred_relics_and_an_epic_for_all() {
    let (k, field, start) = (0u32, world_ride(0).0, world_ride(0).1);
    let mut f = Field::open(field, 7, Config { monsters: 64, threads: 1 });
    f.set_births(false);
    f.set_clock(start - 1);
    for i in 0..150i32 {
        f.join(&Sheet::bench(KNIGHT, HUMAN, 10), &Outing::new(), FIELD / 2 + px(i % 15 * 12 - 90), FIELD / 2 + px(i / 15 * 12 - 60));
    }
    f.step::<u16>(&[]);
    let b = f.boss().unwrap().clone();
    assert_eq!(b.which, B_DEATH);
    assert!(b.world);
    assert_eq!(b.window, k);
    // 10 x (40,000 + 6,000 x 150) x 262%.
    assert_eq!(b.max_hp as u64, 10 * 940_000 * 262 / 100);
    assert_eq!(b.leaves, start + 18_000 - 1 + 1, "stays 15 minutes");
    f.hold_boss();
    for i in 0..150usize {
        f.hero_mut(i as u16).boss_contrib = 1_000_000 + i as u32 * 1_000;
    }
    f.hero_mut(0).boss_contrib = 0;
    let slot = b.slot as usize;
    f.monsters_mut().hp[slot] = 1;
    let (bx, by) = f.boss_pos().unwrap();
    f.hero_mut(7).x = bx;
    f.hero_mut(7).y = by;
    let mut rewards = Vec::new();
    for _ in 0..30 {
        f.step::<u16>(&[]);
        for e in f.events() {
            if let Event::Reward { kind, first, count, .. } = *e {
                rewards.push((kind, f.rewarded(first, count).to_vec()));
            }
        }
    }
    assert_eq!(rewards.len(), 2);
    assert_eq!(rewards[0].0, R_WORLD_RELIC);
    assert_eq!(rewards[0].1.len(), 100, "a hundred highest contributions");
    assert_eq!(rewards[0].1[0].0, 149);
    assert!(rewards[0].1.iter().all(|p| p.1 >= 1_000_000 + 50 * 1_000 - 1_000), "the highest hundred");
    assert_eq!(rewards[1].0, R_WORLD_EPIC);
    assert_eq!(rewards[1].1.len(), 149, "an epic for everyone past the floor (hero 0 gave nothing)");
    // It rides once: not again until the next ride.
    for _ in 0..40 {
        f.step::<u16>(&[]);
    }
    assert!(f.boss().is_none());
    let _ = REWARD_EV;
    let _ = TIDE_EV;
}

#[test]
fn the_world_boss_leaves_after_fifteen_minutes_and_rides_only_its_own_field() {
    let (field, start, end) = world_ride(1);
    let mut other = Field::open(0, 7, Config { monsters: 64, threads: 1 });
    other.set_births(false);
    other.set_clock(start);
    add(&mut other, &bare(KNIGHT, 10), FIELD / 2, FIELD / 2);
    other.step::<u16>(&[]);
    assert!(other.boss().is_none(), "ride 1 is in field {field}");
    let mut f = Field::open(field, 7, Config { monsters: 64, threads: 1 });
    f.set_births(false);
    f.set_clock(end - 3);
    add(&mut f, &bare(KNIGHT, 10), FIELD / 2, FIELD / 2);
    f.set_clock(start - 1);
    f.step::<u16>(&[]);
    assert!(f.boss().is_some());
    f.set_clock(end - 2);
    let mut left = 0;
    for _ in 0..5 {
        f.step::<u16>(&[]);
        left += boss_events(&f).iter().filter(|e| e.1 == BOSS_LEFT).count();
    }
    assert_eq!(left, 1);
    assert!(f.boss().is_none());
}

#[test]
fn a_saved_field_mid_boss_and_mid_tide_loads_to_the_same_hash_two_hundred_ticks_later() {
    for (field, set) in [(1u8, 0u32), (4, 1)] {
        let mut f = Field::open(field, 11, Config { monsters: 3_000, threads: 2 });
        let n = 3 + 4 * set;
        // Mid-tide: three ticks into tide n - 1, then jump to the boss.
        f.set_clock(tide_start(field, n - 1) - 2);
        for i in 0..24i32 {
            f.join(&Sheet::bench(1 + (i % 5) as u8, i as u8 % 4, 20), &Outing::new(), FIELD / 2 + px(i % 6 * 40 - 100), FIELD / 2 + px(i / 6 * 40 - 80));
        }
        let inputs: Vec<u16> = (0..24).map(|i| (i % 9) as u16 | IN_SKILL1).collect();
        for _ in 0..300 {
            f.step(&inputs);
        }
        assert!(f.tide(), "mid-tide");
        let mut g = Field::from_bytes(&f.to_bytes(), 3).expect("loads mid-tide");
        assert_eq!(f.hash(), g.hash());
        for _ in 0..200 {
            f.step(&inputs);
            g.step(&inputs);
        }
        assert_eq!(f.hash(), g.hash(), "mid-tide, 200 ticks later");
        // Mid-boss, with casts out.
        f.set_clock(field_boss_window(field, n).0 - 1);
        g.set_clock(field_boss_window(field, n).0 - 1);
        for _ in 0..400 {
            f.step(&inputs);
            g.step(&inputs);
        }
        assert!(f.boss().is_some(), "boss risen");
        let mut h = Field::from_bytes(&f.to_bytes(), 1).expect("loads mid-boss");
        assert_eq!(f.hash(), h.hash());
        let mut casting = false;
        for _ in 0..200 {
            f.step(&inputs);
            h.step(&inputs);
            casting |= !f.boss().unwrap().casts.is_empty();
            assert_eq!(f.hash(), h.hash());
        }
        assert!(casting, "the boss cast within the 200 ticks");
        assert_eq!(f.hash(), h.hash(), "mid-boss, 200 ticks later");
    }
}
