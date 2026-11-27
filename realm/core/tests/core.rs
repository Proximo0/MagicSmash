//! Determinism (threads, save and load) in all six fields with scripted heroes, and the core's laws.
mod common;
use common::*;

/// Scripted heroes of every class and job at the field's top level: around the heart, and a few at a
/// waystone holding interact.
fn scripted(field: u8, threads: usize) -> Field {
    let mut f = Field::open(field, 40 + field as u64, Config { monsters: 5000, threads });
    let top = FIELDS[field as usize].top;
    let (cx, cy) = (FIELD / 2, FIELD / 2);
    for i in 0..36i32 {
        let class = 1 + (i % 5) as u8 | if i % 10 >= 5 { 8 } else { 0 };
        let mut s = Sheet::bench(class, (i % 4) as u8, top);
        s.deck = (1..=30).collect();
        s.belt = [(P_HEALING, 3), (P_VEIL + (i % 4) as u8, 2), (P_PHOENIX, 1)];
        let (x, y) = if i < 30 { (cx + (i % 6 - 3) * px(40), cy + (i / 6 - 3) * px(40)) } else { f.terrain().waystones[(i % 7) as usize] };
        f.join(&s, &Outing::new(), x, y);
    }
    f
}

fn script(f: &Field) -> Vec<u16> {
    let t = f.tick();
    (0..f.heroes().len() as u32)
        .map(|i| {
            let h = &f.heroes()[i as usize];
            if i >= 30 {
                // Waystone heroes: hold interact, let go now and then.
                return if (t / 70 + i) % 3 == 2 { 0 } else { IN_INTERACT };
            }
            let r = (t / 16).wrapping_mul(2_654_435_761) ^ i.wrapping_mul(40_503);
            let dir = ((r >> 7) % 9) as u16;
            let skills = if (r >> 3) % 4 == 0 { IN_SKILL1 | IN_SKILL2 | IN_ULT } else { 0 };
            let mut b1 = 0u16;
            if (t + i) % 6 == 0 && !h.offers.is_empty() {
                b1 |= 1 + ((r >> 11) % 3) as u16;
            }
            if (t + i * 7) % 120 == 0 {
                b1 |= 1 << (3 + (i % 3));
            }
            dir | skills | b1 << 8
        })
        .collect()
}

#[test]
fn every_field_same_hash_on_1_2_3_4_threads_and_through_save_and_load() {
    for field in 0..6u8 {
        let mut fs: Vec<Field> = (1..=4).map(|t| scripted(field, t)).collect();
        let mut loaded: Option<Field> = None;
        let mut seen = [0usize; 12];
        for t in 1..=360u32 {
            let inp = script(&fs[0]);
            for f in fs.iter_mut() {
                f.step(&inp);
            }
            if let Some(l) = loaded.as_mut() {
                l.step(&inp);
            }
            for e in fs[0].events() {
                seen[e.rank() as usize] += 1;
            }
            if t == 180 {
                let bytes = fs[1].to_bytes();
                let l = Field::from_bytes(&bytes, 3).expect("load");
                assert_eq!(l.hash(), fs[1].hash(), "field {field}: loaded hash");
                loaded = Some(l);
            }
            if t % 60 == 0 {
                let h = fs[0].hash();
                for (k, f) in fs.iter().enumerate() {
                    assert_eq!(f.hash(), h, "field {field}: {} threads vs 1 at tick {t}", k + 1);
                }
                if let Some(l) = loaded.as_ref() {
                    assert_eq!(l.hash(), h, "field {field}: loaded vs kept at tick {t}");
                }
            }
        }
        assert!(seen[SKILL as usize] > 20, "field {field}: skills {seen:?}");
        assert!(seen[PICK as usize] > 5, "field {field}: picks {seen:?}");
        assert!(seen[POTION as usize] > 5, "field {field}: potions {seen:?}");
        assert!(seen[BANK as usize] > 0, "field {field}: banks {seen:?}");
        assert!(seen[KILL as usize] > 50, "field {field}: kills {seen:?}");
    }
}

#[test]
fn a_different_seed_differs() {
    let mut a = Field::open(0, 7, Config { monsters: 2000, threads: 1 });
    let mut b = Field::open(0, 8, Config { monsters: 2000, threads: 1 });
    for f in [&mut a, &mut b] {
        f.join(&Sheet::bench(1, 0, 10), &Outing::new(), FIELD / 2, FIELD / 2);
        idle(f, 50);
    }
    assert_ne!(a.hash(), b.hash());
}

#[test]
fn load_rejects_damaged_state() {
    let mut f = scripted(2, 1);
    idle(&mut f, 30);
    let mut b = f.to_bytes();
    assert!(Field::from_bytes(&b[..b.len() - 1], 1).is_none());
    b.push(0);
    assert!(Field::from_bytes(&b, 1).is_none());
}

#[test]
fn the_reserved_pvp_state_is_saved_and_hashed() {
    let mut f = quiet(0);
    let id = add(&mut f, &bare(1, 20), FIELD / 2, FIELD / 2);
    let h0 = f.hash();
    f.hero_mut(id).marked = true;
    let h1 = f.hash();
    assert_ne!(h0, h1);
    f.hero_mut(id).last_struck = 5;
    assert_ne!(f.hash(), h1);
    let l = Field::from_bytes(&f.to_bytes(), 1).unwrap();
    assert!(l.heroes()[id as usize].marked);
    assert_eq!(l.heroes()[id as usize].last_struck, 5);
}

#[test]
fn an_outing_carries_to_another_copy() {
    let mut a = scripted(0, 1);
    for _ in 0..200 {
        let inp = script(&a);
        a.step(&inp);
    }
    let o = a.outing(3).expect("present");
    let sheet = a.heroes()[3].sheet.clone();
    let mut b = quiet(0);
    let id = b.join(&sheet, &o, FIELD / 2, FIELD / 2);
    let h = &b.heroes()[id as usize];
    let ha = &a.heroes()[3];
    assert_eq!((h.health, h.draws, h.owed, h.coin, h.copies, h.belt), (ha.health, ha.draws, ha.owed, ha.coin, ha.copies, ha.belt));
    assert_eq!(b.outing(id).unwrap().offers, o.offers);
}

#[test]
fn no_float_in_the_core_source() {
    fn files(dir: &std::path::Path, out: &mut Vec<std::path::PathBuf>) {
        for e in std::fs::read_dir(dir).unwrap() {
            let p = e.unwrap().path();
            if p.is_dir() {
                files(&p, out);
            } else {
                out.push(p);
            }
        }
    }
    let mut all = Vec::new();
    files(std::path::Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/src")), &mut all);
    let banned = [["f", "32"].concat(), ["f", "64"].concat()];
    for path in &all {
        let text = std::fs::read_to_string(path).unwrap();
        for word in text.split(|c: char| !c.is_ascii_alphanumeric() && c != '_') {
            for b in &banned {
                let hit = word.strip_suffix(b.as_str()).is_some_and(|head| head.is_empty() || head.ends_with(|c: char| c.is_ascii_digit() || c == '_'));
                assert!(!hit, "{} uses {word}", path.display());
            }
        }
        let b = text.as_bytes();
        for i in 1..b.len().saturating_sub(1) {
            let lit = b[i] == b'.' && b[i - 1].is_ascii_digit() && b[i + 1].is_ascii_digit();
            let tuple = i >= 2 && b[i - 2] == b'.';
            assert!(!lit || tuple, "{} has a float literal near byte {i}", path.display());
        }
        assert!(!text.contains("HashMap") && !text.contains("HashSet"), "{} uses a hashed container", path.display());
        assert!(text.lines().count() <= 640, "{} is over 600 lines", path.display());
    }
    assert!(all.len() >= 10);
}

#[test]
fn births_stay_out_of_every_screen_and_off_walls() {
    for field in [0u8, 1, 4] {
        let mut f = Field::open(field, 3, Config { monsters: 6000, threads: 2 });
        for i in 0..24i32 {
            f.join(&Sheet::bench(1 + (i % 5) as u8, 0, 30), &Outing::new(), FIELD / 2 + (i % 6 - 3) * px(300), FIELD / 2 + (i / 6 - 2) * px(300));
        }
        let (hw, hh) = (VIEW_W / 2 * SUB, VIEW_H / 2 * SUB);
        let mut checked = 0;
        for t in 0..200u32 {
            let inp: Vec<u16> = (0..24u32).map(|i| ((t / 20 + i) % 9) as u16).collect();
            f.step(&inp);
            let m = f.monsters();
            for &id in f.last_spawns() {
                let i = id as usize;
                assert!(!f.terrain().wall(m.x[i], m.y[i]), "field {field}: born on a wall");
                if f.events().iter().any(|e| matches!(e, Event::Kill { .. })) {
                    // Splitters' children open where their parent died: not births.
                    continue;
                }
                for p in f.heroes().iter().filter(|p| p.alive()) {
                    assert!((p.x - m.x[i]).abs() >= hw || (p.y - m.y[i]).abs() >= hh, "field {field}: born in view");
                }
                checked += 1;
            }
        }
        assert!(checked > 1000, "field {field}: {checked}");
    }
}

#[test]
fn density_target_is_400_plus_ring_weights_up_to_the_cap_and_60_a_hero_below_7() {
    let mut f = Field::open(2, 9, Config { monsters: 20_000, threads: 2 });
    let t = f.terrain().clone();
    // One hero in each ring: edge (a waystone), middle (a waystone), heart (the centre).
    f.join(&Sheet::bench(1, 0, 25), &Outing::new(), t.waystones[0].0, t.waystones[0].1);
    f.join(&Sheet::bench(1, 0, 25), &Outing::new(), t.waystones[3].0, t.waystones[3].1);
    f.join(&Sheet::bench(1, 0, 25), &Outing::new(), FIELD / 2, FIELD / 2);
    idle(&mut f, 3);
    let want = 3 * DENSITY_BASE_PER_HERO + RING_WEIGHT[0] + RING_WEIGHT[1] + RING_WEIGHT[2];
    assert!(f.monster_count() >= want && f.monster_count() < want + 8, "{} vs {want}", f.monster_count());
    // Seven heroes and more: the whole base.
    for k in 0..5 {
        f.join(&Sheet::bench(1, 0, 25), &Outing::new(), FIELD / 2 + px(40 * k), FIELD / 2);
    }
    idle(&mut f, 3);
    let want = DENSITY_BASE + RING_WEIGHT[0] + RING_WEIGHT[1] + 6 * RING_WEIGHT[2];
    assert!(f.monster_count() >= want && f.monster_count() < want + 8, "{} vs {want}", f.monster_count());
    let mut capped = Field::open(2, 9, Config { monsters: 50, threads: 1 });
    capped.join(&Sheet::bench(1, 0, 25), &Outing::new(), FIELD / 2, FIELD / 2);
    idle(&mut capped, 3);
    assert_eq!(capped.monster_count(), 50);
}

#[test]
fn a_monster_left_64_cells_behind_is_recycled() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 8);
    add(&mut f, &bare(1, 25), x, y);
    let far = f.place_monster(kind("drowned"), 20, 0, (x + px(2300)).min(FIELD - px(40)), y).unwrap();
    let near = mon(&mut f, kind("drowned"), 20, x + px(300), y);
    idle(&mut f, 14);
    assert_eq!(f.monsters().hp[far as usize], 0);
    assert!(f.recycled() >= 1);
    assert!(f.monsters().hp[near as usize] > 0);
}
