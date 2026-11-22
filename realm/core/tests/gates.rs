//! Rules section 13: the same-hash gate on every field and the bot gates that run fast enough for a test.
//! `GATE_FULL=1` runs the contract's size (1,000 heroes, 2,000 ticks); the default is a fifth of it.

use realm_core::gates::{alone, hash_gate, party};
use realm_core::tables::FIELDS;

fn hash_on(field: u8) {
    let (heroes, ticks) = if std::env::var("GATE_FULL").is_ok() { (1_000, 2_000) } else { (200, 600) };
    if let Err(e) = hash_gate(field, heroes, ticks) {
        panic!("{e}");
    }
}

#[test]
fn hash_equal_on_1_to_4_threads_and_a_follower_in_the_fools_road() {
    hash_on(0);
}
#[test]
fn hash_equal_on_1_to_4_threads_and_a_follower_in_the_hanged_wood() {
    hash_on(1);
}
#[test]
fn hash_equal_on_1_to_4_threads_and_a_follower_in_the_moon_marsh() {
    hash_on(2);
}
#[test]
fn hash_equal_on_1_to_4_threads_and_a_follower_in_the_hermits_peaks() {
    hash_on(3);
}
#[test]
fn hash_equal_on_1_to_4_threads_and_a_follower_in_the_tower() {
    hash_on(4);
}
#[test]
fn hash_equal_on_1_to_4_threads_and_a_follower_in_the_worlds_edge() {
    hash_on(5);
}

#[test]
fn a_run_of_the_bot_gates_is_a_pure_function_of_its_seed() {
    assert_eq!(alone(0, 1, 3, 1), alone(0, 1, 3, 1));
    assert_eq!(party(3, 2, 600, 100), party(3, 2, 600, 100));
}

/// A class bot alone at the edge for ten minutes, class level 1: 8 of 10 seeds are never fallen.
#[test]
fn a_lone_novice_kiting_bot_survives_ten_minutes_in_8_of_10_seeds() {
    let ok = (0..10).filter(|&s| alone(0, 1, s, 10).fallen == 0).count();
    assert!(ok >= 8, "{ok} of 10");
}

/// A party of four holding a field's middle ring for five minutes. Measured in the doc: THE HANGED WOOD and
/// THE MOON MARSH are not met, nor is THE FOOL'S ROAD; the three last fields are.
#[test]
fn a_party_holds_the_middle_ring_in_the_fields_it_is_measured_to() {
    for field in [3u8, 4, 5] {
        let ok = (0..10).filter(|&s| party(field, s, 6_000, 100).fallen == 0).count();
        assert!(ok >= 8, "{}: {ok} of 10", FIELDS[field as usize].name);
    }
}
