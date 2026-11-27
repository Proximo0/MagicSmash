//! Quiet zones and shrines (rules 6.1), the fuller fields (rules 6) and the delving bot: zones placed by the seed,
//! every walkable cell reachable, no births and no monsters inside, a monster found inside pushed out, a hero inside
//! out of reach, a shrine's draw once an outing, and a delving bot that does not wait by the entrance.
mod common;
use common::*;
use realm_core::bots::{Bot, Plan};

const SEEDS: u64 = 12;

fn cell(x: i32, y: i32) -> usize {
    cell_of(x, y)
}

fn shrine_zones(t: &Terrain) -> Vec<QuietZone> {
    let mut v: Vec<QuietZone> = t.quiet.iter().copied().filter(|z| z.shrine != NO_SHRINE).collect();
    v.sort_by_key(|z| z.shrine);
    v
}

#[test]
fn every_field_has_an_entrance_three_to_five_intermissions_and_a_ward_round_every_waystone() {
    for field in 0..6u8 {
        let mut counts = Vec::new();
        for seed in 1..=SEEDS {
            let f = Field::open(field, seed, Config { monsters: 64, threads: 1 });
            let t = f.terrain();
            check_terrain(t).unwrap_or_else(|e| panic!("field {field} seed {seed}: {e}"));
            let s = shrine_zones(t);
            let mids = s.len() - 1;
            assert!((3..=5).contains(&mids), "field {field} seed {seed}: {mids} intermissions");
            counts.push(mids);
            // The entrance: its shrine first, the gate inside it.
            assert_eq!(s[0].shrine, 0);
            assert!(t.quiet(t.gate.0, t.gate.1), "field {field} seed {seed}: the gate is in the entrance's quiet zone");
            // Intermissions deeper and deeper (nearer the heart), all beyond the heart's rim.
            let depth: Vec<i64> = s[1..].iter().map(|z| dist(z.x, z.y, FIELD / 2, FIELD / 2) / SUB as i64).collect();
            assert!(depth.windows(2).all(|w| w[0] > w[1]), "field {field} seed {seed}: {depth:?}");
            assert!(depth.iter().all(|&d| d >= HEART_PX as i64 && d <= MIDDLE_PX as i64 + 600), "field {field} seed {seed}: {depth:?}");
            // Every shrine and every waystone on quiet ground.
            for z in &t.quiet {
                assert!(t.quiet(z.x, z.y) && !t.wall(z.x, z.y), "field {field} seed {seed}: zone at {:?}", (z.x, z.y));
            }
            for &(x, y) in &t.waystones {
                assert!(t.quiet(x, y), "field {field} seed {seed}: a waystone outside a quiet zone");
            }
        }
        println!("QUIET field {field}: intermissions over {SEEDS} seeds {counts:?}, plus the entrance and 7 waystone wards");
    }
}

/// Open cells, and the biggest piece of them joined 4-ways.
fn components(map: &[u8]) -> (usize, usize) {
    let mut seen = vec![false; CELLS];
    let (mut open, mut best) = (0, 0);
    let mut q = Vec::new();
    for s in 0..CELLS {
        if map[s] & WALL != 0 {
            continue;
        }
        open += 1;
        if seen[s] {
            continue;
        }
        seen[s] = true;
        q.clear();
        q.push(s);
        let mut h = 0;
        while h < q.len() {
            let c = q[h];
            h += 1;
            let (x, y) = ((c % CELLS_W) as i32, (c / CELLS_W) as i32);
            for (ox, oy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let (nx, ny) = (x + ox, y + oy);
                if nx >= 0 && ny >= 0 && nx < CELLS_W as i32 && ny < CELLS_W as i32 {
                    let n = ny as usize * CELLS_W + nx as usize;
                    if !seen[n] && map[n] & WALL == 0 {
                        seen[n] = true;
                        q.push(n);
                    }
                }
            }
        }
        best = best.max(q.len());
    }
    (open, best)
}

#[test]
fn every_walkable_cell_of_every_field_is_reachable_from_the_gate_over_many_seeds() {
    for field in 0..6u8 {
        let (mut open_min, mut walls_max) = (usize::MAX, 0usize);
        for seed in 1..=SEEDS {
            let f = Field::open(field, seed, Config { monsters: 64, threads: 1 });
            let t = f.terrain();
            let g = ((t.gate.0 >> CELL_SHIFT), (t.gate.1 >> CELL_SHIFT));
            let reach = flood(&t.map, g);
            let open = t.map.iter().filter(|&&c| c & WALL == 0).count();
            let reached = reach.iter().filter(|&&r| r).count();
            assert_eq!(open, reached, "field {field} seed {seed}: {} walkable cells cut off", open - reached);
            // Monsters reach every walkable cell outside the quiet zones too (they walk round the zones).
            let mut closed = t.map.clone();
            for c in closed.iter_mut() {
                if *c & QUIET != 0 {
                    *c |= WALL;
                }
            }
            let (mopen, mreached) = components(&closed);
            assert!(mreached * 100 >= mopen * 98, "field {field} seed {seed}: monsters reach {mreached} of {mopen} cells in one piece");
            open_min = open_min.min(open);
            walls_max = walls_max.max(CELLS - open);
        }
        // Enough ground is left to fight on.
        // Enough ground is left to fight on (THE HANGED WOOD is tree walls with paths: a sixth).
        assert!(open_min > CELLS / 6, "field {field}: only {open_min} walkable cells");
        println!("FIELD {field}: walkable at least {open_min} of {CELLS} cells, walls at most {walls_max}, all reachable over {SEEDS} seeds");
    }
}

#[test]
fn nothing_is_born_in_a_quiet_zone_and_no_monster_walks_into_one() {
    for field in 0..6u8 {
        let mut f = Field::open(field, 3, Config { monsters: 3_000, threads: 2 });
        let z = shrine_zones(f.terrain())[1];
        // One hero in the zone, one just outside it: the horde comes for the one outside and gathers at the border.
        let inside = add(&mut f, &bare(KNIGHT, 10), z.x, z.y);
        let (ox, oy) = f.terrain().nearest_open(z.x + ((z.r + 3) << CELL_SHIFT), z.y);
        let out = add(&mut f, &bare(KNIGHT, 10), ox, oy);
        for _ in 0..400 {
            for id in [inside, out] {
                let h = f.hero_mut(id);
                h.max_health = 1_000_000;
                h.health = 1_000_000;
            }
            f.step(&[0u16, 0]);
            let m = f.monsters();
            let t = f.terrain();
            for i in 0..m.hp.len() {
                if m.hp[i] > 0 {
                    assert!(t.map[cell(m.x[i], m.y[i])] & QUIET == 0, "field {field}: a monster in a quiet zone at tick {}", f.tick());
                }
            }
        }
        assert!(f.monster_count() > 50, "field {field}: births go on outside ({})", f.monster_count());
        assert_eq!(f.heroes()[inside as usize].health, 1_000_000, "field {field}: the hero inside was hurt");
    }
}

#[test]
fn a_hero_inside_is_out_of_reach_and_a_monster_found_inside_is_pushed_out() {
    let mut f = quiet(0);
    let z = shrine_zones(f.terrain())[2];
    let id = add(&mut f, &bare(KNIGHT, 10), z.x + px(20), z.y);
    let hp0 = f.heroes()[id as usize].health;
    // Monsters placed on her and around: the ones inside leave, none strikes her.
    let mut ids = Vec::new();
    for k in 0..12 {
        let (dx, dy) = ((k % 4 - 2) * 12, (k / 4 - 1) * 12);
        ids.push(mon(&mut f, kind("scarecrow"), 1, z.x + px(dx), z.y + px(dy)));
    }
    let mut out_at = 0;
    for t in 1..=200u32 {
        f.hero_mut(id).charge = 0;
        step(&mut f, &[0]);
        let m = f.monsters();
        if out_at == 0 && ids.iter().all(|&i| m.hp[i as usize] == 0 || !f.terrain().quiet(m.x[i as usize], m.y[i as usize])) {
            out_at = t;
        }
    }
    assert!(out_at > 0 && out_at < 120, "pushed out by tick {out_at}");
    assert_eq!(f.heroes()[id as usize].health, hp0, "no blow lands inside");
}

#[test]
fn a_shrine_gives_one_draw_once_an_outing() {
    let mut f = quiet(0);
    let s = shrine_zones(f.terrain());
    let z = s[1];
    let sheet = Sheet::bench(KNIGHT, HUMAN, 10);
    let id = add(&mut f, &sheet, z.x + px(100), z.y);
    step(&mut f, &[0]);
    assert!(f.heroes()[id as usize].offers.is_empty());
    // Walk onto it: one draw.
    f.hero_mut(id).x = z.x;
    f.hero_mut(id).y = z.y;
    step(&mut f, &[0]);
    assert_eq!(count(&f, 1), 1, "a DRAW event");
    assert_eq!(f.heroes()[id as usize].offers.len(), 1);
    assert_eq!(f.heroes()[id as usize].shrines, 1 << z.shrine);
    // Standing on it, leaving and coming back: nothing more.
    for _ in 0..40 {
        step(&mut f, &[0]);
    }
    f.hero_mut(id).x = z.x + px(200);
    step(&mut f, &[0]);
    f.hero_mut(id).x = z.x;
    step(&mut f, &[0]);
    assert_eq!(f.heroes()[id as usize].offers.len(), 1, "once a shrine");
    // Another shrine is another draw; the touched ones go with her to another copy.
    let z2 = s[2];
    f.hero_mut(id).x = z2.x;
    f.hero_mut(id).y = z2.y;
    step(&mut f, &[0]);
    assert_eq!(f.heroes()[id as usize].offers.len(), 2);
    let o = f.outing(id).unwrap();
    assert_eq!(o.shrines, (1 << z.shrine) | (1 << z2.shrine));
    let mut g = quiet(0);
    let id2 = g.join(&sheet, &o, z.x, z.y);
    step(&mut g, &[0]);
    assert_eq!(g.heroes()[id2 as usize].offers.len(), 2, "no second draw from a shrine touched in another copy");
}

#[test]
fn a_delving_bot_leaves_the_entrance_and_walks_deep_from_zone_to_zone() {
    for field in [0u8, 1, 4] {
        let mut f = Field::open(field, 21, Config { monsters: 2_000, threads: 2 });
        let (gx, gy) = f.terrain().gate;
        let id = add(&mut f, &Sheet::bench(KNIGHT, HUMAN, (FIELDS[field as usize].bottom + 2).min(60)), gx, gy);
        let mut bot = Bot::new(id, 9, Plan::delve());
        let s = shrine_zones(f.terrain());
        let mut deepest = 0usize;
        let mut near_gate = 0u32;
        let ticks = 20 * 60 * 4;
        for _ in 0..ticks {
            let inp = bot.act(&f);
            f.step(&[inp]);
            let h = &f.heroes()[id as usize];
            if !h.present {
                break;
            }
            if dist(h.x, h.y, gx, gy) < px(600) as i64 {
                near_gate += 1;
            }
            for (k, z) in s.iter().enumerate() {
                if dist(h.x, h.y, z.x, z.y) < ((z.r as i64) << CELL_SHIFT) {
                    deepest = deepest.max(k);
                }
            }
        }
        println!("DELVE field {field}: deepest shrine zone {deepest} of {}, {near_gate} of {ticks} ticks within 600 px of the gate", s.len() - 1);
        assert!(deepest >= 2, "field {field}: reached only zone {deepest}");
        assert!(near_gate < ticks / 6, "field {field}: waited by the entrance {near_gate} ticks");
    }
}
