//! The six fields (rules section 6): generators and their checks, sites, rings, levels by distance, the
//! terrain rules (road, mire, dark, walls) and the level ceiling.
mod common;
use common::*;

fn cells_with(t: &Terrain, bit: u8) -> usize {
    t.map.iter().filter(|&&c| c & bit != 0).count()
}

fn dist_px(x: i32, y: i32) -> i64 {
    dist(x, y, FIELD / 2, FIELD / 2) / SUB as i64
}

#[test]
fn every_field_passes_its_checks_and_is_the_same_from_the_same_seed() {
    for field in 0..6u8 {
        let mut hashes = Vec::new();
        for seed in [1u64, 2, 99] {
            let f = Field::open(field, seed, Config { monsters: 64, threads: 1 });
            check_terrain(f.terrain()).unwrap_or_else(|e| panic!("field {field} seed {seed}: {e}"));
            assert_eq!(narrow_count(&f.terrain().map), 0, "field {field} seed {seed}");
            let g = Field::open(field, seed, Config { monsters: 64, threads: 3 });
            assert_eq!(f.terrain().hash, g.terrain().hash);
            hashes.push(f.terrain().hash);
        }
        hashes.dedup();
        assert_eq!(hashes.len(), 3, "field {field}: seeds make different maps");
    }
}

#[test]
fn sites_three_waystones_at_the_edge_three_in_the_middle_one_on_the_hearts_rim_six_altars_in_the_middle() {
    for field in 0..6u8 {
        let f = Field::open(field, 5, Config { monsters: 64, threads: 1 });
        let t = f.terrain();
        let rings: Vec<u8> = t.waystones.iter().map(|&(x, y)| ring_of(x, y)).collect();
        assert_eq!(rings.iter().filter(|&&r| r == RING_EDGE).count(), 3, "field {field}: {rings:?}");
        assert_eq!(rings[..6].iter().filter(|&&r| r == RING_MIDDLE).count(), 3, "field {field}: {rings:?}");
        let rim = t.waystones[6];
        assert!((dist_px(rim.0, rim.1) - HEART_PX as i64).abs() <= 128, "field {field}: rim waystone at {}", dist_px(rim.0, rim.1));
        assert!(t.altars.iter().all(|&(x, y)| ring_of(x, y) == RING_MIDDLE), "field {field}");
        assert!(t.sites().iter().all(|&(x, y)| !t.wall(x, y)), "field {field}");
        // The gate at the south edge.
        assert_eq!(t.gate.0, FIELD / 2);
        assert!(t.gate.1 > FIELD - px(2 * GATE_INSET_PX), "field {field}");
    }
}

#[test]
fn each_generator_lays_its_own_ground() {
    let t: Vec<Terrain> = (0..6u8).map(|f| Field::open(f, 4, Config { monsters: 64, threads: 1 }).terrain().clone()).collect();
    let all = CELLS;
    // THE FOOL'S ROAD: open, a road, hedges.
    assert!(cells_with(&t[0], ROAD) > 0 && cells_with(&t[0], WALL) < all / 4);
    // No slowing ground and no dark on the road field (its ponds are deep water, `WATER`: wall with the mire bit).
    assert_eq!(t[0].map.iter().filter(|&&c| c & MIRE != 0 && c & WALL == 0).count() + cells_with(&t[0], DARK), 0);
    // THE HANGED WOOD and THE TOWER: walls everywhere.
    assert!(cells_with(&t[1], WALL) > all / 5, "wood {}", cells_with(&t[1], WALL));
    assert!(cells_with(&t[4], WALL) > all / 10, "tower {}", cells_with(&t[4], WALL));
    // THE MOON MARSH: mire and dark.
    assert!(cells_with(&t[2], MIRE) > all / 20 && cells_with(&t[2], DARK) > 0);
    // THE HERMIT'S PEAKS: ridges.
    assert!(cells_with(&t[3], WALL) > all / 20);
    // THE WORLD'S EDGE: all at once.
    for bit in [WALL, MIRE, ROAD, DARK] {
        assert!(cells_with(&t[5], bit) > 0, "edge lacks {bit}");
    }
    assert_eq!(FIELDS.iter().map(|r| r.rule).collect::<Vec<_>>(), vec![Rule::Road, Rule::Wood, Rule::Marsh, Rule::Peaks, Rule::Tower, Rule::Edge]);
}

#[test]
fn levels_spread_from_the_rim_to_the_centre() {
    for field in 0..6u8 {
        let row = &FIELDS[field as usize];
        assert_eq!(level_at(field, FIELD / 2, FIELD / 2), row.top);
        assert_eq!(level_at(field, FIELD / 2, FIELD / 2 + px(LEVEL_RIM_PX)), row.bottom);
        assert_eq!(level_at(field, 0, 0), row.bottom);
        let mut last = row.top;
        for d in (0..LEVEL_RIM_PX).step_by(256) {
            let l = level_at(field, FIELD / 2 + px(d), FIELD / 2);
            assert!(l <= last && l >= row.bottom);
            last = l;
        }
    }
    assert_eq!([FIELDS[0].bottom, FIELDS[0].top, FIELDS[5].bottom, FIELDS[5].top], [1, 10, 50, 60]);
}

#[test]
fn rings_by_distance_from_the_heart() {
    let c = FIELD / 2;
    assert_eq!(ring_of(c, c + px(HEART_PX - 1)), RING_HEART);
    assert_eq!(ring_of(c, c + px(HEART_PX)), RING_MIDDLE);
    assert_eq!(ring_of(c, c + px(MIDDLE_PX - 1)), RING_MIDDLE);
    assert_eq!(ring_of(c, c + px(MIDDLE_PX)), RING_EDGE);
}

/// A hero standing on a cell with `bit` (and no other ground bit), and her move speed against open ground.
fn move_on(field: u8, bit: u8) -> i32 {
    let mut f = quiet(field);
    let t = f.terrain().clone();
    let half = 1 << (CELL_SHIFT - 1);
    let find = |want: u8| {
        (0..CELLS)
            .find(|&c| {
                let (cx, cy) = ((c % CELLS_W) as i32, (c / CELLS_W) as i32);
                cx > 2 && cy > 2 && cx < CELLS_W as i32 - 2 && [c - 1, c, c + 1].iter().all(|&k| t.map[k] & (WALL | MIRE | ROAD | DARK) == want)
            })
            .map(|c| ((((c % CELLS_W) as i32) << CELL_SHIFT) + half, (((c / CELLS_W) as i32) << CELL_SHIFT) + half))
            .expect("a cell")
    };
    let (ax, ay) = find(0);
    let (bx, by) = find(bit);
    let a = add(&mut f, &bare(KNIGHT, 10), ax, ay);
    let b = add(&mut f, &bare(KNIGHT, 10), bx, by);
    idle(&mut f, 1);
    f.mods(b).unwrap().move_pct - f.mods(a).unwrap().move_pct
}

#[test]
fn heroes_walk_10_percent_faster_on_the_road() {
    assert_eq!(move_on(0, ROAD), ROAD_MOVE_PCT);
    assert_eq!(ROAD_MOVE_PCT, 10);
}

#[test]
fn mire_slows_heroes_30_percent_not_monsters() {
    assert_eq!(move_on(2, MIRE), MIRE_MOVE_PCT);
    assert_eq!(MIRE_MOVE_PCT, -30);
    // A monster crosses mire as fast as open ground.
    let mut f = quiet(2);
    let t = f.terrain().clone();
    let half = 1 << (CELL_SHIFT - 1);
    let row = (100..CELLS_W - 100)
        .flat_map(|cy| (100..CELLS_W - 100).map(move |cx| (cx, cy)))
        .find(|&(cx, cy)| {
            (0..20).all(|k| t.map[cy * CELLS_W + cx + k] & (WALL | MIRE) == MIRE)
                && (0..20).all(|k| t.map[(cy + 1) * CELLS_W + cx + k] & WALL == 0)
                && (0..20).all(|k| t.map[(cy - 1) * CELLS_W + cx + k] & WALL == 0)
        })
        .expect("a mire run");
    let y = ((row.1 as i32) << CELL_SHIFT) + half;
    let hx = (((row.0 + 19) as i32) << CELL_SHIFT) + half;
    let h = add(&mut f, &bare(KNIGHT, 10), hx, y);
    guard(&mut f, h);
    warm(&mut f);
    let m = mon(&mut f, kind("drowned"), 20, ((row.0 as i32) << CELL_SHIFT) + half, y);
    let x0 = f.monsters().x[m as usize];
    for _ in 0..20 {
        f.hero_mut(h).charge = 0;
        f.step::<u16>(&[]);
    }
    let moved = (f.monsters().x[m as usize] - x0) / SUB;
    let speed = KINDS[kind("drowned") as usize].speed as i32;
    assert!(moved >= speed * 9 / 10, "moved {moved} px in a second at {speed} px/s");
}

#[test]
fn in_the_dark_births_come_250_to_450_px_away() {
    let mut f = Field::open(2, 8, Config { monsters: 2000, threads: 1 });
    let t = f.terrain().clone();
    let half = 1 << (CELL_SHIFT - 1);
    let c = (0..CELLS)
        .find(|&c| {
            t.map[c] & DARK != 0 && t.map[c] & WALL == 0 && ring_of(((c % CELLS_W) as i32) << CELL_SHIFT, ((c / CELLS_W) as i32) << CELL_SHIFT) == RING_MIDDLE
        })
        .expect("a dark cell");
    let (x, y) = ((((c % CELLS_W) as i32) << CELL_SHIFT) + half, (((c / CELLS_W) as i32) << CELL_SHIFT) + half);
    // Seven heroes on one spot, so the whole base of 400 is born around them.
    for _ in 0..7 {
        let h = add(&mut f, &bare(KNIGHT, 10), x, y);
        guard(&mut f, h);
    }
    f.step::<u16>(&[]);
    let spawns: Vec<u32> = f.last_spawns().to_vec();
    assert!(spawns.len() > 100, "{}", spawns.len());
    let m = f.monsters();
    let mut seed_points = 0;
    for &i in &spawns {
        let d = dist(m.x[i as usize], m.y[i as usize], x, y) / SUB as i64;
        // Clutch members stand up to two steps off their first.
        assert!(d >= DARK_BIRTH_MIN_PX as i64 - 2 * CLUTCH_PX as i64 && d <= DARK_BIRTH_MAX_PX as i64 + 2 * CLUTCH_PX as i64, "{d}");
        if d >= DARK_BIRTH_MIN_PX as i64 && d <= DARK_BIRTH_MAX_PX as i64 {
            seed_points += 1;
        }
    }
    assert!(seed_points * 10 > spawns.len() * 8);
}

#[test]
fn the_ceiling_counts_a_veteran_as_the_top_level_plus_two() {
    let s = Sheet::bench(KNIGHT, HUMAN, 60);
    assert_eq!(s.counted_level(0), 12);
    assert_eq!(s.counted_level(5), 60);
    assert_eq!(s.weapon_level(0), 12);
    let low = s.stats(0);
    let high = s.stats(5);
    assert!(low.iter().zip(&high).all(|(a, b)| a <= b) && low != high);
    // The job and the skills she cannot count are off in a low field.
    let mut f = quiet(0);
    let id = add(&mut f, &s, FIELD / 2, FIELD / 2);
    assert_eq!(f.heroes()[id as usize].class_level, 12);
    assert_eq!(f.heroes()[id as usize].job, NONE);
}

#[test]
fn monster_levels_follow_where_they_are_born() {
    let mut f = Field::open(0, 3, Config { monsters: 3000, threads: 1 });
    let a = add(&mut f, &bare(KNIGHT, 10), FIELD / 2, FIELD / 2 + px(7000));
    guard(&mut f, a);
    f.step::<u16>(&[]);
    let m = f.monsters();
    for &i in f.last_spawns() {
        let i = i as usize;
        let want = level_at(0, m.x[i], m.y[i]) as i32;
        assert!((m.level[i] as i32 - want).abs() <= 1, "clutch members share their first's level");
    }
}
