//! A client that joins mid-game loads the saved bytes: whatever the running field still reads must be in them.
//! These are the cases a review found where it was not (a hero who left by herself; a flow rebuilt with
//! nobody alive).
mod common;
use common::*;

/// Steps `a` and its saved-and-loaded copy with no input and compares their hashes every tick.
fn same_after_load(a: &mut Field, ticks: u32) {
    let mut b = Field::from_bytes(&a.to_bytes(), 1).expect("loads");
    assert_eq!(a.hash(), b.hash(), "at the load");
    for t in 1..=ticks {
        idle(a, 1);
        idle(&mut b, 1);
        assert_eq!(a.hash(), b.hash(), "tick {t} after the load");
    }
}

#[test]
fn a_hero_who_walked_out_of_the_gate_is_not_read_again() {
    let mut f = quiet(0);
    let (hx, hy) = spot(&f, 8);
    add(&mut f, &bare(KNIGHT, 10), hx, hy);
    let (gx, gy) = f.terrain().gate;
    let leaver = add(&mut f, &bare(KNIGHT, 10), gx, gy - px(60));
    let scarecrow = kind("scarecrow");
    for k in 0..40 {
        mon(&mut f, scarecrow, 1, gx + px(k % 8 * 30 - 105), gy - px(150 + k / 8 * 50));
    }
    idle(&mut f, 30);
    let mut inputs = vec![0u16; leaver as usize + 1];
    inputs[leaver as usize] = 3;
    for _ in 0..200 {
        if !f.heroes()[leaver as usize].present {
            break;
        }
        f.step(&inputs);
    }
    assert!(!f.heroes()[leaver as usize].present, "she never reached the gate");
    same_after_load(&mut f, 60);
}

#[test]
fn a_hero_who_left_from_a_waystone_is_not_read_again() {
    let mut f = quiet(0);
    let (hx, hy) = spot(&f, 8);
    add(&mut f, &bare(KNIGHT, 10), hx, hy);
    let (wx, wy) = f.terrain().waystones[1];
    let leaver = add(&mut f, &bare(KNIGHT, 10), wx, wy);
    guard(&mut f, leaver);
    let scarecrow = kind("scarecrow");
    for k in 0..40 {
        mon(&mut f, scarecrow, 1, wx + px(k % 8 * 30 - 105), wy - px(150 + k / 8 * 50));
    }
    let mut inputs = vec![0u16; leaver as usize + 1];
    inputs[leaver as usize] = IN_INTERACT;
    for _ in 0..2 * BANK_HOLD + 4 {
        if !f.heroes()[leaver as usize].present {
            break;
        }
        f.step(&inputs);
    }
    assert!(!f.heroes()[leaver as usize].present, "she never left");
    same_after_load(&mut f, 60);
}

#[test]
fn a_flow_built_with_nobody_alive_loads_the_same() {
    let mut f = quiet(1);
    let (x, y) = spot(&f, 8);
    let far = add(&mut f, &bare(KNIGHT, 20), x + px(1500), y);
    let near = add(&mut f, &bare(KNIGHT, 20), x, y);
    idle(&mut f, 40);
    f.leave(far);
    f.leave(near);
    idle(&mut f, 30);
    let wight = kind("bark wight");
    for k in 0..4 {
        mon(&mut f, wight, 30, x - px(20 + k * 6), y - px(20));
    }
    let id = add(&mut f, &Sheet::bench(KNIGHT, HUMAN, 20), x, y);
    let every = f.heroes()[id as usize].class_row().weapon.every * 100;
    f.hero_mut(id).charge = every;
    same_after_load(&mut f, 40);
}
