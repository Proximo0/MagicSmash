//! Vaults (rules section 10): the arena, the timeline, bosses at minutes 5, 10 and 15, seals, the party failing,
//! the chest, the class trial.
mod common;
use common::*;

fn vault(v: u8, seals: u8) -> Field {
    Field::open_vault(v, seals, 5, Config { monsters: 2_048, threads: 1 })
}

/// Joins `n` strong heroes at the middle of the arena (they cannot die unless a test lets them).
fn party(f: &mut Field, n: u32, class_level: u8) -> Vec<u16> {
    (0..n as i32)
        .map(|i| {
            let id = f.join(&Sheet::bench(1 + (i % 5) as u8, HUMAN, class_level), &Outing::new(), FIELD / 2 + px(i * 24 - 90), FIELD / 2 + px(-150));
            f.hero_mut(id).max_health = 100_000_000;
            f.hero_mut(id).health = 100_000_000;
            id
        })
        .collect()
}

fn vault_events(f: &Field) -> Vec<(u8, u8)> {
    f.events().iter().filter_map(|e| if let Event::Vault { state, n } = *e { Some((state, n)) } else { None }).collect()
}

#[test]
fn the_vault_table_matches_the_contract() {
    assert_eq!(VAULTS.len(), 6, "five vaults and the class trial");
    for (i, level) in [20u8, 30, 40, 50, 60].into_iter().enumerate() {
        let v = &VAULTS[i];
        assert_eq!(v.level, level);
        assert_eq!(v.minutes, 15);
        assert_eq!(v.party_max, 8);
        assert_eq!(v.seals_max, 8, "seals I to VIII");
        assert_eq!(v.bosses.map(|b| b.0), [5, 10, 15], "act bosses at minutes 5 and 10, the ARCHLICH at 15");
        assert_eq!(v.bosses.map(|b| BOSSES[b.1 as usize].tier), [TIER_ACT, TIER_ACT, TIER_ARCHLICH]);
        assert_eq!(BOSSES[v.bosses[2].1 as usize].name, "THE ARCHLICH");
        assert_eq!(v.timeline.len(), 15, "a timeline of what is born each minute");
        assert!(v.timeline.windows(2).all(|w| w[1].target > w[0].target), "it only gets worse");
        assert!(v.timeline.iter().all(|m| m.burst > 0));
        let kinds = &KINDS[v.first_kind as usize..(v.first_kind + v.kind_count) as usize];
        assert!(kinds.iter().all(|k| k.field >= v.field.saturating_sub(1) && k.field <= 5), "{}", v.name);
    }
    let t = &VAULTS[VAULT_CLASS_TRIAL as usize];
    assert_eq!((t.party_max, t.seals_max), (1, 0), "a vault row for one hero");
    assert_eq!(VAULT_ARENA_PX, 2_048);
    assert_eq!((SEAL_PCT, chest_rolls(0), chest_rolls(8)), (25, 2, 10), "every seal adds 25% and one more roll");
    assert_eq!((seal_scale(0), seal_scale(8)), (100, 300));
}

#[test]
fn the_arena_is_two_thousand_pixels_walled_with_no_gate_and_no_waystones() {
    let f = vault(0, 0);
    let t = f.terrain();
    let open: Vec<usize> = (0..CELLS).filter(|&c| t.map[c] & WALL == 0).collect();
    let (mut x0, mut x1) = (CELLS_W, 0);
    for &c in &open {
        x0 = x0.min(c % CELLS_W);
        x1 = x1.max(c % CELLS_W);
    }
    assert_eq!(x1 - x0 + 1, 64, "64 cells of 32 px");
    assert!(open.len() > 64 * 64 * 8 / 10, "mostly open ground, some pillars");
    assert!(t.wall(0, 0) && t.wall(t.gate.0, t.gate.1) && t.waystones.iter().all(|&(x, y)| t.wall(x, y)), "nobody can bank or leave by the gate");
    assert!(!t.wall(FIELD / 2, FIELD / 2) && f.field_id() == 2);
    let again = vault(0, 0);
    assert_eq!(again.terrain().hash, t.hash, "from its seed");
    let g = Field::open_vault(0, 0, 6, Config { monsters: 64, threads: 1 });
    assert_ne!(g.terrain().hash, t.hash, "pillars follow the seed");
}

#[test]
fn heroes_are_counted_at_the_vaults_level_and_monsters_are_born_at_it_from_its_own_kinds() {
    let mut f = vault(1, 0);
    let ids = party(&mut f, 3, 60);
    assert_eq!(f.heroes()[ids[0] as usize].class_level, 32, "a level 60 hero counts as the vault's level 30 + 2");
    assert_eq!(f.top_level(), 30);
    for _ in 0..200 {
        f.step::<u16>(&[]);
    }
    let row = &VAULTS[1];
    let m = f.monsters();
    let alive: Vec<usize> = (0..m.len()).filter(|&i| m.hp[i] > 0).collect();
    assert!(alive.len() > 50, "{}", alive.len());
    for &i in &alive {
        assert_eq!(m.level[i], 30);
        assert!(m.kind[i] >= row.first_kind && m.kind[i] < row.first_kind + row.kind_count, "{}", KINDS[m.kind[i] as usize].name);
    }
}

#[test]
fn each_minute_has_its_target_and_a_clutch_at_its_start() {
    let mut f = vault(0, 0);
    party(&mut f, 8, 30);
    let row = &VAULTS[0];
    let mut starts = Vec::new();
    let mut at_minute_end: Vec<usize> = Vec::new();
    for t in 1..=3 * 1_200u32 {
        f.step::<u16>(&[]);
        // The run's clock is the tick (the first hero came at tick 1): minute m opens at tick 1,200 m.
        if t == 1 || t % 1_200 == 0 {
            starts.push(f.last_spawns().len());
        }
        if t % 1_200 == 1_199 {
            at_minute_end.push(f.monster_count() as usize);
        }
    }
    for (m, s) in starts.iter().enumerate() {
        assert!(*s >= row.timeline[m].burst as usize, "minute {m} opened with its clutch ({s})");
    }
    // Eight heroes: the timeline's own number (births stop at it; the party kills some).
    assert!(at_minute_end[0] <= row.timeline[0].target as usize + 40 && at_minute_end[0] >= row.timeline[0].target as usize / 2, "{at_minute_end:?}");
    assert!(at_minute_end[2] > at_minute_end[0], "the crowd grows: {at_minute_end:?}");
    // Fewer heroes, fewer monsters.
    let mut small = vault(0, 0);
    party(&mut small, 1, 30);
    for _ in 0..1_000 {
        small.step::<u16>(&[]);
    }
    assert!(small.monster_count() as usize * 2 < at_minute_end[0], "{} against {}", small.monster_count(), at_minute_end[0]);
}

#[test]
fn every_seal_adds_a_quarter_to_monster_health_and_damage() {
    let k = kind("goat cultist");
    let hp = |seals: u8| {
        let mut f = vault(1, seals);
        f.set_births(false);
        let m = mon(&mut f, k, 30, FIELD / 2, FIELD / 2);
        (f.monsters().max_hp(m as usize), f.monsters().damage(m as usize), f.monsters().hp[m as usize])
    };
    let (h0, d0, c0) = hp(0);
    assert_eq!(c0, h0);
    for seals in 1..=8u8 {
        let (h, d, c) = hp(seals);
        assert_eq!(c, h, "born at full health");
        let want = (100 + 25 * seals as u32) as u64;
        assert_eq!(h as u64, h0 as u64 * want / 100, "health at seal {seals}");
        assert!(d as u64 >= d0 as u64 * want / 100 - 1 && d as u64 <= d0 as u64 * want / 100 + 1, "damage at seal {seals}: {d} vs {d0}");
    }
    assert_eq!(vault(1, 12).vault().unwrap().seals, 8, "no more than VIII");
}

#[test]
fn a_party_of_eight_at_most_and_one_for_the_trial() {
    let mut f = vault(0, 0);
    for i in 0..8 {
        assert!(f.vault_has_room(), "{i}");
        party(&mut f, 1, 30);
    }
    assert!(!f.vault_has_room());
    let mut t = vault(VAULT_CLASS_TRIAL, 3);
    assert_eq!(t.vault().unwrap().seals, 0);
    party(&mut t, 1, 10);
    assert!(!t.vault_has_room());
}

#[test]
fn the_downed_wait_and_the_party_fails_when_all_are_down_with_coin_for_the_minutes() {
    let mut f = vault(0, 0);
    let ids = party(&mut f, 3, 30);
    for _ in 0..1_300 {
        f.step::<u16>(&[]);
    }
    assert!(f.vault().unwrap().state == RUN_GOING);
    // One goes down: after 15 s she is still down (no waystone to wake at) and nothing fell.
    f.hero_mut(ids[0]).health = 0;
    f.hero_mut(ids[0]).downed = DOWNED_TICKS;
    f.hero_mut(ids[0]).x += px(400);
    let mut fallen = 0;
    for _ in 0..DOWNED_TICKS as u32 + 100 {
        f.step::<u16>(&[]);
        fallen += count(&f, FALLEN);
    }
    assert!(f.heroes()[ids[0] as usize].downed > 0 && fallen == 0, "waits to be raised");
    assert!(f.vault().unwrap().state == RUN_GOING, "two stand");
    // The rest go down: the vault is lost, once, with coin for the whole minutes survived.
    let coin0 = f.heroes()[ids[1] as usize].coin;
    for &q in &ids[1..] {
        f.hero_mut(q).health = 0;
        f.hero_mut(q).downed = DOWNED_TICKS;
    }
    let mut lost = Vec::new();
    let mut rewards = Vec::new();
    for _ in 0..40 {
        f.step::<u16>(&[]);
        lost.extend(vault_events(&f).into_iter().filter(|e| e.0 == VAULT_LOST));
        for e in f.events() {
            if let Event::Reward { kind, first, count, .. } = *e {
                rewards.push((kind, f.rewarded(first, count).to_vec()));
            }
        }
    }
    let minutes = (f.vault().unwrap().ended - f.vault().unwrap().started + 1) / 1_200;
    assert_eq!(lost, vec![(VAULT_LOST, minutes as u8)], "LOST once, with the minutes survived");
    assert_eq!(f.vault().unwrap().state, RUN_LOST);
    assert_eq!(rewards.len(), 1);
    assert_eq!(rewards[0].0, R_VAULT_LOSS);
    assert_eq!(rewards[0].1.len(), 3);
    let want = coin_at(COIN_VAULT_PER_MINUTE * minutes, 20);
    assert_eq!(f.heroes()[ids[1] as usize].coin - coin0, want);
    // Over: no more births.
    let n = f.monster_count();
    idle(&mut f, 300);
    assert!(f.monster_count() <= n);
}

/// Plays a vault: a party that cannot die, each boss made weak and struck at once. Returns the events by tick.
fn play(v: u8, seals: u8, heroes: u32, until: u32, kill: bool) -> (Field, Vec<(u32, Event)>) {
    let mut f = vault(v, seals);
    let ids = party(&mut f, heroes, 30);
    let mut log = Vec::new();
    for t in 1..=until {
        for &q in &ids {
            let h = f.hero_mut(q);
            h.health = h.max_health;
            h.downed = 0;
        }
        f.step::<u16>(&[]);
        for e in f.events() {
            log.push((t, *e));
        }
        if kill {
            if let Some((_, max)) = f.boss_health() {
                let slot = f.boss().unwrap().slot as usize;
                if f.monsters().hp[slot] > 1 {
                    f.monsters_mut().hp[slot] = 1;
                }
                let (bx, by) = f.boss_pos().unwrap();
                for &q in &ids {
                    let h = f.hero_mut(q);
                    h.x = bx;
                    h.y = by;
                }
                let _ = max;
            }
        }
    }
    (f, log)
}

#[test]
fn killing_the_two_acts_and_the_archlich_wins_with_a_chest_for_the_heroes_past_the_floor() {
    let (f, log) = play(2, 3, 8, 18_000 + 2_000, true);
    let vs: Vec<(u32, u8, u8)> = log.iter().filter_map(|(t, e)| if let Event::Vault { state, n } = e { Some((*t, *state, *n)) } else { None }).collect();
    assert_eq!(vs[0], (1, VAULT_START, 0));
    let acts: Vec<&(u32, u8, u8)> = vs.iter().filter(|v| v.1 == VAULT_ACT).collect();
    assert_eq!(acts.len(), 3, "{vs:?}");
    assert_eq!(acts.iter().map(|a| a.2).collect::<Vec<_>>(), vec![1, 2, 3]);
    // Minutes 5, 10 and 15 of the run (the first hero came at tick 1).
    assert_eq!(acts[0].0, 5 * 1_200, "minute five");
    assert!(acts[1].0 >= 10 * 1_200 && acts[1].0 < 10 * 1_200 + 200, "minute ten, after the first act's boss fell: {}", acts[1].0);
    assert!(acts[2].0 >= 15 * 1_200 && acts[2].0 < 15 * 1_200 + 200, "minute fifteen: {}", acts[2].0);
    let won: Vec<_> = vs.iter().filter(|v| v.1 == VAULT_WON).collect();
    assert_eq!(won.len(), 1, "WON once");
    assert_eq!(won[0].2, 3, "with its three seals");
    let bosses: Vec<(u8, u8)> = log.iter().filter_map(|(_, e)| if let Event::Boss { which, state, .. } = e { Some((*which, *state)) } else { None }).collect();
    assert_eq!(bosses.iter().filter(|b| b.1 == BOSS_RISES).map(|b| b.0).collect::<Vec<_>>(), vec![B_WARDEN, B_REGENT, B_ARCHLICH]);
    assert_eq!(bosses.iter().filter(|b| b.1 == BOSS_KILLED).count(), 3);
    let rewards: Vec<&Event> = log.iter().filter(|(_, e)| matches!(e, Event::Reward { .. })).map(|(_, e)| e).collect();
    assert_eq!(rewards.len(), 1, "one chest for the run");
    let Event::Reward { kind, seals, level, .. } = rewards[0] else { unreachable!() };
    assert_eq!((*kind, *seals, *level), (R_VAULT_CHEST, 3, 40));
    assert_eq!(f.vault().unwrap().state, RUN_WON);
    assert_eq!(chest_rolls(3), 5);
}

#[test]
fn the_archlich_not_killed_in_three_more_minutes_loses_the_vault() {
    // Three heroes (four left the ARCHLICH at 2% when they were the test's party, and the monsters' tighter routing of
    // rules 4 tipped that over; three leave it at about 16%).
    let (f, log) = play(0, 0, 3, 15 * 1_200 + 3 * 1_200 + 100, false);
    let lost: Vec<u32> = log.iter().filter_map(|(t, e)| if matches!(e, Event::Vault { state: VAULT_LOST, .. }) { Some(*t) } else { None }).collect();
    // The act bosses were never killed either: the timeline slips, and the clock still runs out.
    assert_eq!(lost.len(), 1);
    assert_eq!(lost[0], 18 * 1_200, "at minute 18");
    assert_eq!(f.vault().unwrap().state, RUN_LOST);
}

#[test]
fn a_vault_boss_has_health_from_the_party_the_level_and_the_seals() {
    for (seals, heroes) in [(0u8, 1u32), (0, 8), (4, 8)] {
        let (f, _) = play(1, seals, heroes, 5 * 1_200 + 2, false);
        let (_, max) = f.boss_health().unwrap();
        let base = (VAULTS[1].hp_base + VAULTS[1].hp_per_hero * heroes) as u64;
        // Level 30: 100 + 18 x 29 = 622%.
        let want = base * 622 / 100 * (100 + 25 * seals as u64) / 100;
        assert!((max as u64).abs_diff(want) <= 4, "seals {seals} heroes {heroes}: {max} vs {want}");
        assert_eq!(f.boss().unwrap().dmg_pct, 100 + 25 * seals as u32, "its blows grow with the seals");
    }
}

#[test]
fn the_class_trial_is_won_by_one_hero_killing_its_warden() {
    let (f, log) = play(VAULT_CLASS_TRIAL, 0, 1, 4 * 1_200 + 400, true);
    let vs: Vec<(u8, u8)> = log.iter().filter_map(|(_, e)| if let Event::Vault { state, n } = e { Some((*state, *n)) } else { None }).collect();
    assert_eq!(vs, vec![(VAULT_START, 0), (VAULT_ACT, 1), (VAULT_WON, 0)]);
    assert_eq!(f.vault().unwrap().state, RUN_WON);
    assert_eq!(BOSSES[B_TRIAL as usize].tier, TIER_TRIAL);
}

#[test]
fn the_timeline_waits_for_the_first_hero_and_a_saved_vault_loads_to_the_same_hash() {
    let mut f = vault(0, 2);
    idle(&mut f, 500);
    assert_eq!(f.vault_ticks(), 0, "no hero yet: the clock of the run has not started");
    assert_eq!(f.monster_count(), 0);
    party(&mut f, 4, 30);
    for _ in 0..5 * 1_200 + 100 {
        f.step::<u16>(&[]);
    }
    assert!(f.boss().is_some(), "the first act is up");
    let mut g = Field::from_bytes(&f.to_bytes(), 2).expect("loads");
    assert_eq!(f.hash(), g.hash());
    for _ in 0..300 {
        f.step::<u16>(&[]);
        g.step::<u16>(&[]);
    }
    assert_eq!(f.hash(), g.hash());
    assert_eq!(g.vault().unwrap().seals, 2);
}
