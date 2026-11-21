use realm_core::*;

/// A small field with a few players spread around the centre and a fixed input script.
fn field(seed: u64, players: u16, monsters: u32, threads: usize) -> Field {
    let mut f = Field::new(seed, Config { monsters, threads });
    for i in 0..players as i32 {
        let x = FIELD / 2 + (i % 8 - 4) * 300 * SUB;
        let y = FIELD / 2 + (i / 8 - 2) * 300 * SUB;
        f.join((i % 5) as u8, (i % 4) as u8, x, y);
    }
    f
}

fn inputs(tick: u32, n: usize) -> Vec<u8> {
    (0..n)
        .map(|i| {
            let r = (tick / 20).wrapping_mul(2_654_435_761) ^ (i as u32).wrapping_mul(40_503);
            let dir = (r >> 7) % 9;
            let skill = if (r >> 3) % 13 == 0 { INPUT_SKILL } else { 0 };
            dir as u8 | skill
        })
        .collect()
}

fn run(f: &mut Field, ticks: u32) {
    for _ in 0..ticks {
        let inp = inputs(f.tick(), f.players().len());
        f.step(&inp);
    }
}

#[test]
fn same_seed_same_hash() {
    let mut a = field(7, 24, 3000, 1);
    let mut b = field(7, 24, 3000, 1);
    run(&mut a, 300);
    run(&mut b, 300);
    assert_eq!(a.hash(), b.hash());
    let mut c = field(8, 24, 3000, 1);
    run(&mut c, 300);
    assert_ne!(a.hash(), c.hash(), "a different seed should differ");
}

#[test]
fn thread_count_does_not_change_the_hash() {
    let mut a = field(11, 40, 8000, 1);
    let mut b = field(11, 40, 8000, 4);
    let mut c = field(11, 40, 8000, 3);
    for t in 0..600 {
        let inp = inputs(t, 40);
        a.step(&inp);
        b.step(&inp);
        c.step(&inp);
        if t % 100 == 99 {
            assert_eq!(a.hash(), b.hash(), "1 vs 4 threads at tick {}", a.tick());
            assert_eq!(a.hash(), c.hash(), "1 vs 3 threads at tick {}", a.tick());
        }
    }
    let (kills, _, _) = a.counters();
    assert!(kills > 0, "the test should include fighting");
}

#[test]
fn saved_state_follows_the_same_path() {
    let mut a = field(5, 30, 5000, 2);
    run(&mut a, 137);
    let bytes = a.to_bytes();
    let mut b = Field::from_bytes(&bytes, 1).expect("load");
    assert_eq!(a.hash(), b.hash());
    for _ in 0..200 {
        let inp = inputs(a.tick(), a.players().len());
        a.step(&inp);
        b.step(&inp);
    }
    assert_eq!(a.hash(), b.hash());
}

#[test]
fn no_float_in_the_core_source() {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/src");
    let banned = [["f", "32"].concat(), ["f", "64"].concat()];
    let mut files = 0;
    for e in std::fs::read_dir(dir).unwrap() {
        let path = e.unwrap().path();
        let text = std::fs::read_to_string(&path).unwrap();
        files += 1;
        for word in text.split(|c: char| !c.is_ascii_alphanumeric() && c != '_') {
            for b in &banned {
                // `f32` itself, or a literal suffix such as `1f64` / `1_f32`.
                let hit = word.strip_suffix(b.as_str()).is_some_and(|head| {
                    head.is_empty() || head.ends_with(|c: char| c.is_ascii_digit() || c == '_')
                });
                assert!(!hit, "{} uses {word}", path.display());
            }
        }
        // A float literal such as `1.5` (but not a range `0..8`).
        let b = text.as_bytes();
        for i in 1..b.len().saturating_sub(1) {
            let lit = b[i] == b'.' && b[i - 1].is_ascii_digit() && b[i + 1].is_ascii_digit();
            let tuple = i >= 2 && b[i - 2] == b'.';
            assert!(!lit || tuple, "{} has a float literal near byte {i}", path.display());
        }
    }
    assert!(files >= 2);
}

#[test]
fn spawns_stay_out_of_every_view() {
    let mut f = field(3, 32, 6000, 2);
    let (hw, hh) = (VIEW_W / 2 * SUB, VIEW_H / 2 * SUB);
    let mut checked = 0;
    for _ in 0..400 {
        let inp = inputs(f.tick(), f.players().len());
        f.step(&inp);
        let m = f.monsters();
        for &id in f.last_spawns() {
            let i = id as usize;
            for p in f.players().iter().filter(|p| p.alive()) {
                assert!(
                    (p.x - m.x[i]).abs() >= hw || (p.y - m.y[i]).abs() >= hh,
                    "monster {id} spawned inside a view at tick {}",
                    f.tick()
                );
            }
            checked += 1;
        }
    }
    assert!(checked > 6000, "only {checked} spawns checked");
}

#[test]
fn monster_count_holds_its_target() {
    let mut f = field(9, 32, 5000, 2);
    for _ in 0..400 {
        let inp = inputs(f.tick(), f.players().len());
        f.step(&inp);
        assert_eq!(f.monster_count(), 5000, "tick {}", f.tick());
    }
    let (kills, spawns, _) = f.counters();
    assert!(kills > 100 && spawns == 5000 + kills + f.recycled());
}

#[test]
fn dead_player_respawns_at_the_centre_after_3_s() {
    // One archer in a crowd it cannot hold: it dies, then comes back 60 ticks later.
    let mut f = Field::new(1, Config { monsters: 4000, threads: 1 });
    let id = f.join(2, 0, 2000 * SUB, 2000 * SUB) as usize;
    let mut died = None;
    for _ in 0..4000 {
        f.step(&[0]);
        let p = &f.players()[id];
        if died.is_none() && p.health == 0 {
            died = Some(f.tick());
            assert_eq!(p.dead_timer, RESPAWN_TICKS);
        }
        if let Some(t) = died {
            if f.tick() < t + RESPAWN_TICKS as u32 {
                assert_eq!(f.players()[id].health, 0, "back too early at {}", f.tick());
            } else {
                let p = &f.players()[id];
                assert_eq!(f.tick(), t + RESPAWN_TICKS as u32);
                assert_eq!((p.x, p.y), (FIELD / 2, FIELD / 2));
                assert_eq!(p.health, p.max_health);
                return;
            }
        }
    }
    panic!("the player never died (died at {died:?})");
}
