//! Short versions of the balance gates of job B1 (`docs/realm/balance.md`). The full runs are
//! `realm-loadtest balance career|probe|gates|jobs` and the station word `balance`.

use realm_core::tables::*;
use realm_loadtest::balance::*;
use realm_loadtest::career::*;

#[test]
fn the_class_xp_table_is_the_fit_and_meets_the_curve_at_the_measured_rates() {
    assert_eq!(fit_class_xp(&CAREER_XP_HOUR), CLASS_XP, "CLASS_XP is `balance fit` of CAREER_XP_HOUR");
    let h = hours_from(&CLASS_XP, &CAREER_XP_HOUR);
    for (level, target) in CURVE {
        assert!((h[level] - target).abs() <= target * 0.03, "level {level}: {:.2} h, target {target} h", h[level]);
    }
    // Every level takes some time, and the hours only grow.
    for l in 2..=60 {
        assert!(h[l] > h[l - 1], "level {l}");
    }
}

#[test]
fn a_hero_fights_where_her_level_pays_best_within_five_levels() {
    for level in 1..=60u8 {
        let (field, ring) = Career::place_for(level);
        let (best, _) = best_rate(&MEASURED_XP_HOUR, level);
        assert!(best <= level && best + STAY_LEVELS >= level);
        assert!(FIELDS[field as usize].bottom <= level, "never a field above her");
        assert!((RING_MIN_PX..=RING_MAX_PX).contains(&ring));
    }
    // A level of the first field's ring: monsters of her level less the margin.
    let (f, r) = Career::place(5);
    assert_eq!(f, 0);
    let monster = realm_core::level_at(0, realm_core::FIELD / 2 + r * realm_core::SUB, realm_core::FIELD / 2);
    assert!((3..=5).contains(&monster), "monsters of level {monster} for a hero of 5");
}

#[test]
fn a_cohort_of_careers_is_a_pure_function_of_its_seed_and_books_every_coin() {
    let pace = Pace { ticks: 1_200, fast: 8, threads: 2 };
    let run = || {
        let mut c = Cohort::new(5, 2);
        for _ in 0..2 {
            c.round(pace);
        }
        c.careers.iter().map(|x| (x.level, x.xp, x.coin, x.embers, x.bands[0].kills)).collect::<Vec<_>>()
    };
    let a = run();
    assert_eq!(a, run(), "same seed, same careers");
    assert!(a.iter().all(|x| x.1 > 0 && x.4 > 0), "every career killed and earned XP: {a:?}");
    assert!(a.iter().any(|x| x.0 > 1), "someone levelled");
}

#[test]
fn town_charges_sinks_and_keeps_the_coin_book_whole() {
    // A level-35 hero back from an hour (credited) with known takings.
    let mut c = Career::at_level(0, KNIGHT, false, HUMAN, 35, 3);
    c.coin = 1_000_000;
    let p = Played { xp: 10_000, kills: 400, kill_coin: 9_000, chest_coin: 1_000, falls: 1, fall_coin: 500, ..Default::default() };
    let before = c.coin;
    c.town(&p, 3_600 * TICK_HZ as u64 / 4, 4, false, realm_loot::sinks::travel_cost(3, 1));
    let b = &c.bands[band_of(35)].book;
    assert_eq!((b.kills, b.chests, b.fall), (36_000, 4_000, 2_000));
    assert!(b.repair > 0 && b.travel > 0);
    // What she holds is what she had, plus what she minted, less what was sunk or paid to other players.
    assert_eq!(c.coin as i64, before as i64 + b.minted() as i64 - b.sunk() as i64 - b.market as i64);
    assert_eq!(c.level, 35.max(c.level));
}

#[test]
fn the_sinks_remove_what_monsters_mint_over_an_hour_at_every_band() {
    // One outing of each band's middle level, played 2 minutes and credited 60 (k = 30), then a visit to town.
    let mut got = Vec::new();
    for level in [15u8, 25, 35, 45, 55] {
        let (field, ring) = Career::place(level);
        let mut c = Career::at_level(0, PALADIN, false, HUMAN, level, 9);
        c.coin = 0;
        let k = 30;
        let inst = Instance { field, seed: 40 + level as u64, clock: realm_core::tide_start(field, 1) + TIDE_LEN as u64 + 20, groups: vec![Group { members: vec![0], ring_px: ring }] };
        let played = run(&inst, &[(c.sheet(), k, u32::MAX)], 2_400);
        let fare = realm_loot::sinks::travel_cost(field, realm_core::ring_of(realm_core::FIELD / 2 + ring * realm_core::SUB, realm_core::FIELD / 2));
        c.town(&played[0], 2_400, k, false, fare);
        let b = &c.bands[band_of(level)].book;
        assert!(b.monsters() > 0, "level {level} minted nothing");
        let forced = b.fall + b.potions + b.repair + b.travel;
        got.push((level, forced * 100 / b.monsters().max(1), b.fall * 100 / b.monsters().max(1), b.repair * 100 / b.monsters().max(1)));
    }
    // (level, forced %, of which falls %, of which repair %) of what monsters minted.
    assert!(got.iter().all(|g| g.1 >= FORCED_SINK_MIN_PCT), "{got:?}");
}

#[test]
fn the_party_gate_short() {
    // Two seeds of 2 minutes on the first three fields, where the party gate fails (rules 13): a guard that the
    // measure runs and does not get worse than measured (2 of 6). The full gate (balance.md) is not met.
    let got = party_gate(2, 2_400, &[0, 1, 2]);
    let fallen_free: u32 = got.iter().map(|g| g.1).sum();
    assert!(fallen_free >= 2, "parties never fallen, of 6: {got:?}");
}

#[test]
fn the_jobs_gate_short() {
    // One crowd of 50 at class level 50 for 1,200 ticks: the measure runs and the pairs are within the bounds
    // balance.md reports for the full gate.
    for (class, a, b, gap) in jobs_gate(1, 50, 50, 1_200) {
        assert!(a > 0 && b > 0, "class {class}: {a} {b}");
        assert!(gap <= JOB_GAP_REPORTED_PCT[class as usize], "class {class}: gap {gap}%");
    }
}
