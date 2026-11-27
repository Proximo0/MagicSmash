//! The 30 cards (rules section 5), one test each, and the deck: draws, the queue, the mage's four, five copies.
mod common;
use common::*;

const DROWNED_K: u8 = 13;

/// A hero of `class` at class level `level` alone on field 2; her mods before and after `n` copies of `card`.
fn with(class: u8, level: u8, card: u8, n: u8) -> (Field, u16, Mods, Mods) {
    // Field 3 (THE PEAKS) lets a level-40 hero keep her job under the ceiling.
    let mut f = quiet(if level >= JOB_LEVEL { 3 } else { 2 });
    let (x, y) = spot(&f, 24);
    let id = add(&mut f, &bare(class, level), x, y);
    idle(&mut f, 1);
    let base = *f.mods(id).unwrap();
    f.hero_mut(id).copies[card as usize] = n;
    idle(&mut f, 1);
    let m = *f.mods(id).unwrap();
    (f, id, base, m)
}

/// Puts a monster back in place, stunned, with plenty of health (the knight's DIRK pushes).
fn pin(f: &mut Field, k: u32, x: i32, y: i32) {
    let m = f.monsters_mut();
    m.hp[k as usize] = 1_000_000;
    m.stun[k as usize] = 250;
    m.x[k as usize] = x;
    m.y[k as usize] = y;
}

fn card(name: &str) -> u8 {
    CARDS.iter().position(|c| c.name == name).unwrap_or_else(|| panic!("no card {name}")) as u8
}

/// Offers one card and picks it with the input byte.
fn offer_and_pick(f: &mut Field, id: u16, c: u8) {
    f.hero_mut(id).offers.insert(0, [c, 0, 0, 0]);
    let mut inputs = vec![0u16; f.heroes().len()];
    inputs[id as usize] = 1 << IN_PICK_SHIFT;
    f.step(&inputs);
    f.step::<u16>(&[]);
}

#[test]
fn strength_adds_10_percent_damage_a_copy() {
    let (_, _, b, m) = with(KNIGHT, 10, card("STRENGTH"), 2);
    assert_eq!(m.power * 100, b.power * 120);
}

#[test]
fn the_chariot_adds_6_percent_move() {
    let (_, _, b, m) = with(KNIGHT, 10, card("THE CHARIOT"), 3);
    assert_eq!(m.move_pct - b.move_pct, 18);
}

#[test]
fn the_magician_adds_8_percent_attack_speed() {
    let (_, _, b, m) = with(KNIGHT, 10, card("THE MAGICIAN"), 1);
    assert_eq!(m.as_pct - b.as_pct, 8);
}

#[test]
fn the_empress_adds_10_percent_health_healed_at_once() {
    let (mut f, id, _, _) = with(KNIGHT, 10, 0, 0);
    let max = f.heroes()[id as usize].max_health;
    f.hero_mut(id).health = max / 2;
    offer_and_pick(&mut f, id, card("THE EMPRESS"));
    let h = &f.heroes()[id as usize];
    assert_eq!(h.copies[card("THE EMPRESS") as usize], 1);
    assert_eq!(h.max_health, max * 110 / 100);
    assert_eq!(h.health, max / 2 + max * 10 / 100);
}

#[test]
fn temperance_regains_half_a_percent_a_second() {
    let (mut f, id, _, m) = with(KNIGHT, 10, card("TEMPERANCE"), 1);
    assert_eq!(m.regen_tenths, 5);
    let max = f.heroes()[id as usize].max_health;
    f.hero_mut(id).health = max / 2;
    f.hero_mut(id).regen = 0;
    idle(&mut f, TICK_HZ);
    assert_eq!(f.heroes()[id as usize].health, max / 2 + max * 5 / 1000);
}

#[test]
fn the_world_adds_12_percent_size() {
    let (_, _, b, m) = with(KNIGHT, 10, card("THE WORLD"), 2);
    assert_eq!((b.size_pct, m.size_pct), (100, 124));
}

#[test]
fn the_star_adds_10_percent_reach() {
    let (_, _, b, m) = with(ARCHER, 10, card("THE STAR"), 1);
    assert_eq!(m.reach_pct - b.reach_pct, 10);
}

#[test]
fn the_high_priestess_cuts_cooldowns_8_percent() {
    let (mut f, id, _, m) = with(KNIGHT, 10, card("THE HIGH PRIESTESS"), 1);
    assert_eq!(m.cdr_pct, 8);
    f.step(&[IN_SKILL1]);
    assert_eq!(f.heroes()[id as usize].cooldowns[0], SKILLS[S_PROVOKE as usize].cooldown * 92 / 100);
}

#[test]
fn wheel_of_fortune_adds_10_percent_coin() {
    let (mut f, id, b, m) = with(KNIGHT, 10, card("WHEEL OF FORTUNE"), 1);
    assert_eq!(m.coin_pct - b.coin_pct, 10);
    let (x, y) = (f.heroes()[id as usize].x, f.heroes()[id as usize].y);
    let k = mon(&mut f, DROWNED_K, 1, x + px(20), y);
    let xp = f.monsters().xp(k as usize);
    f.monsters_mut().hp[k as usize] = 1;
    f.hero_mut(id).active = f.tick();
    let c0 = f.heroes()[id as usize].coin;
    f.hero_mut(id).charge = 1_000_000;
    f.step::<u16>(&[]);
    assert_eq!(f.heroes()[id as usize].coin - c0, xp * m.coin_pct / 100);
}

#[test]
fn the_hermit_adds_8_percent_class_xp() {
    let (mut f, id, b, m) = with(KNIGHT, 10, card("THE HERMIT"), 1);
    assert_eq!(m.xp_pct - b.xp_pct, 8);
    let (x, y) = (f.heroes()[id as usize].x, f.heroes()[id as usize].y);
    let k = mon(&mut f, DROWNED_K, 5, x + px(20), y);
    let xp = f.monsters().xp(k as usize);
    f.monsters_mut().hp[k as usize] = 1;
    f.hero_mut(id).active = f.tick();
    let c0 = f.heroes()[id as usize].class_xp;
    f.hero_mut(id).charge = 1_000_000;
    f.step::<u16>(&[]);
    let race = RACES[f.heroes()[id as usize].race as usize].class_xp_pct;
    assert_eq!(f.heroes()[id as usize].class_xp - c0, xp * m.xp_pct / 100 * race / 100);
}

#[test]
fn the_hierophant_takes_5_percent_off() {
    let (_, _, b, m) = with(KNIGHT, 10, card("THE HIEROPHANT"), 1);
    assert_eq!(m.taken * 100, b.taken * 95);
}

#[test]
fn justice_returns_20_percent_of_contact_damage() {
    let (mut f, id, _, m) = with(KNIGHT, 10, card("JUSTICE"), 1);
    assert_eq!(m.reflect_pct, 20);
    let (x, y) = (f.heroes()[id as usize].x, f.heroes()[id as usize].y);
    let k = mon(&mut f, DROWNED_K, 60, x + px(10), y);
    let raw = f.monsters().damage(k as usize);
    for _ in 0..CONTACT_EVERY {
        f.hero_mut(id).charge = 0;
        let before = f.monsters().hp[k as usize];
        f.step::<u16>(&[]);
        if f.heroes()[id as usize].hurt {
            assert_eq!(before - f.monsters().hp[k as usize], raw * 20 / 100);
            return;
        }
    }
    panic!("no contact");
}

#[test]
fn the_tower_strikes_every_fifth_attack_twice() {
    let (mut f, id, _, m) = with(KNIGHT, 10, card("THE TOWER"), 1);
    assert_eq!((m.every_nth, m.nth_extra), (5, 1));
    let (x, y) = (f.heroes()[id as usize].x, f.heroes()[id as usize].y);
    let k = mon(&mut f, DROWNED_K, 60, x + px(30), y);
    let mut lost = Vec::new();
    for _ in 0..5 {
        pin(&mut f, k, x + px(30), y);
        f.hero_mut(id).charge = 1_000_000;
        f.step::<u16>(&[]);
        lost.push(1_000_000 - f.monsters().hp[k as usize]);
    }
    let attacks = f.heroes()[id as usize].attacks;
    let fifth = (5 - attacks % 5) as usize % 5;
    let one = lost.iter().copied().min().unwrap();
    for (j, &l) in lost.iter().enumerate() {
        assert_eq!(l, if j == 4 - fifth { one * 2 } else { one }, "{lost:?}");
    }
}

#[test]
fn death_adds_25_percent_under_30_percent_health() {
    let (mut f, id, _, m) = with(KNIGHT, 10, card("DEATH"), 1);
    assert_eq!((m.execute_pct, m.execute_under), (25, 30));
    let (x, y) = (f.heroes()[id as usize].x, f.heroes()[id as usize].y);
    let k = mon(&mut f, DROWNED_K, 60, x + px(30), y);
    let max = f.monsters().max_hp(k as usize);
    let mut hit = |hp: u32| {
        pin(&mut f, k, x + px(30), y);
        f.monsters_mut().hp[k as usize] = hp;
        f.hero_mut(id).charge = 1_000_000;
        f.step::<u16>(&[]);
        hp - f.monsters().hp[k as usize]
    };
    let high = hit(max);
    let low = hit(max * 29 / 100);
    assert_eq!(low, high * 125 / 100);
}

#[test]
fn the_devil_adds_18_percent_damage_and_6_percent_taken() {
    let (_, _, b, m) = with(KNIGHT, 10, card("THE DEVIL"), 1);
    assert_eq!(m.power * 100, b.power * 118);
    assert_eq!(m.taken * 100, b.taken * 106);
}

#[test]
fn the_moon_doubles_5_percent_of_hits() {
    let (mut f, id, _, m) = with(KNIGHT, 10, card("THE MOON"), 2);
    assert_eq!(m.crit_chance, 10);
    let (x, y) = (f.heroes()[id as usize].x, f.heroes()[id as usize].y);
    let k = mon(&mut f, DROWNED_K, 60, x + px(30), y);
    let (mut one, mut two) = (0, 0);
    let mut base = u32::MAX;
    let mut lost = Vec::new();
    for _ in 0..1000 {
        pin(&mut f, k, x + px(30), y);
        f.hero_mut(id).charge = 1_000_000;
        f.step::<u16>(&[]);
        let l = 1_000_000 - f.monsters().hp[k as usize];
        base = base.min(l);
        lost.push(l);
    }
    for l in lost {
        if l == base {
            one += 1
        } else if l == base * 2 {
            two += 1
        } else {
            panic!("{l} vs {base}")
        }
    }
    assert!((60..=140).contains(&two), "{two} doubles of {}", one + two);
}

#[test]
fn the_sun_gives_allies_within_100_px_3_percent() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 24);
    let s = add(&mut f, &bare(KNIGHT, 10), x, y);
    let a = add(&mut f, &bare(MAGE, 10), x + px(90), y);
    let b = add(&mut f, &bare(MAGE, 10), x + px(120), y);
    idle(&mut f, 1);
    let (pa, pb) = (f.mods(a).unwrap().power, f.mods(b).unwrap().power);
    f.hero_mut(s).copies[card("THE SUN") as usize] = 1;
    idle(&mut f, 1);
    assert_eq!(f.mods(a).unwrap().power * 100, pa * 103);
    assert_eq!(f.mods(b).unwrap().power, pb);
    // A second sun does not stack: the strongest counts.
    let c = add(&mut f, &bare(KNIGHT, 10), x + px(80), y);
    f.hero_mut(c).copies[card("THE SUN") as usize] = 1;
    idle(&mut f, 1);
    assert_eq!(f.mods(a).unwrap().power * 100, pa * 103);
}

#[test]
fn the_lovers_heal_1_percent_of_damage_at_most_2_percent_a_second() {
    let (mut f, id, _, m) = with(KNIGHT, 10, card("THE LOVERS"), 1);
    assert_eq!((m.lifesteal_pct, m.lifesteal_cap), (1, 2));
    let (x, y) = (f.heroes()[id as usize].x, f.heroes()[id as usize].y);
    let k = mon(&mut f, DROWNED_K, 60, x + px(30), y);
    let max = f.heroes()[id as usize].max_health;
    f.hero_mut(id).health = 1;
    guard(&mut f, id);
    let h0 = 1;
    for _ in 0..TICK_HZ {
        pin(&mut f, k, x + px(30), y);
        f.hero_mut(id).charge = 1_000_000;
        f.step::<u16>(&[]);
    }
    let healed = f.heroes()[id as usize].health - h0;
    assert!(healed > 0 && healed <= max * 2 / 100 + 1, "{healed} of {max}");
}

#[test]
fn the_emperor_adds_15_percent_on_elites() {
    let (mut f, id, _, m) = with(KNIGHT, 10, card("THE EMPEROR"), 1);
    assert_eq!(m.elite_pct, 15);
    let (x, y) = (f.heroes()[id as usize].x, f.heroes()[id as usize].y);
    let a = f.place_monster(DROWNED_K, 60, ELITE, x + px(30), y).unwrap();
    let b = mon(&mut f, DROWNED_K, 60, x + px(30), y + px(2));
    for k in [a, b] {
        pin(&mut f, k, x + px(30), y);
    }
    f.hero_mut(id).charge = 1_000_000;
    f.step::<u16>(&[]);
    let (la, lb) = (1_000_000 - f.monsters().hp[a as usize], 1_000_000 - f.monsters().hp[b as usize]);
    assert_eq!(la, lb * 115 / 100);
}

#[test]
fn the_hanged_man_raises_25_percent_faster_and_rises_with_15_percent_more() {
    let (_, _, b, m) = with(KNIGHT, 10, card("THE HANGED MAN"), 1);
    assert_eq!((b.raise_pct, m.raise_pct), (100, 125));
    assert_eq!((b.rise_pct, m.rise_pct), (100, 115));
}

#[test]
fn judgement_adds_12_percent_only_in_a_tide() {
    let (mut f, id, b, m) = with(KNIGHT, 10, card("JUDGEMENT"), 1);
    assert_eq!(m.power, b.power);
    f.set_tide(true);
    idle(&mut f, 1);
    assert_eq!(f.mods(id).unwrap().power * 100, b.power * 112);
}

#[test]
fn the_fool_adds_a_pierce_or_8_percent() {
    let (_, _, b, m) = with(ARCHER, 10, card("THE FOOL"), 1);
    assert_eq!((m.pierce_add, m.targets_add, m.power), (1, 1, b.power));
    let (_, _, b, m) = with(KNIGHT, 10, card("THE FOOL"), 1);
    assert_eq!((m.pierce_add, m.power * 100), (0, b.power * 108));
}

#[test]
fn nine_of_swords_pushes_6_px_further() {
    let (_, _, b, m) = with(KNIGHT, 10, card("NINE OF SWORDS"), 2);
    assert_eq!(m.push_add - b.push_add, 12);
}

#[test]
fn three_of_cups_adds_a_charge_and_potions_restore_20_percent_more() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 24);
    let mut s = bare(KNIGHT, 10);
    s.belt = [(P_HEALING, 3), (P_VEIL, 2), (P_PHOENIX, 1)];
    let id = add(&mut f, &s, x, y);
    idle(&mut f, 1);
    offer_and_pick(&mut f, id, card("THREE OF CUPS"));
    assert_eq!(f.heroes()[id as usize].belt, [(P_HEALING, 4), (P_VEIL, 3), (P_PHOENIX, 1)]);
    assert_eq!(f.mods(id).unwrap().cups_pct, 20);
    let max = f.heroes()[id as usize].max_health;
    f.hero_mut(id).health = 1;
    f.step(&[IN_POTION1]);
    assert_eq!(f.heroes()[id as usize].health, 1 + max * 35 / 100 * 120 / 100);
}

#[test]
fn ace_of_wands_cuts_the_ultimate_10_percent_or_adds_6_percent() {
    let (_, _, b, m) = with(KNIGHT, 40, card("ACE OF WANDS"), 1);
    assert_eq!((m.ult_cdr_pct, m.cdr_pct, m.power), (10, 0, b.power));
    let (_, _, b, m) = with(KNIGHT, 10, card("ACE OF WANDS"), 1);
    assert_eq!((m.ult_cdr_pct, m.power * 100), (0, b.power * 106));
}

#[test]
fn five_of_pentacles_adds_20_percent_alone() {
    let (mut f, id, b, m) = with(KNIGHT, 10, card("FIVE OF PENTACLES"), 1);
    assert_eq!(m.power * 100, b.power * 120);
    let (x, y) = (f.heroes()[id as usize].x, f.heroes()[id as usize].y);
    add(&mut f, &bare(MAGE, 10), x + px(140), y);
    idle(&mut f, 1);
    assert_eq!(f.mods(id).unwrap().power, b.power);
}

#[test]
fn six_of_cups_adds_4_percent_an_ally_at_most_20() {
    let (mut f, id, b, _) = with(KNIGHT, 10, card("SIX OF CUPS"), 1);
    let (x, y) = (f.heroes()[id as usize].x, f.heroes()[id as usize].y);
    add(&mut f, &bare(MAGE, 10), x + px(140), y);
    add(&mut f, &bare(MAGE, 10), x - px(100), y);
    idle(&mut f, 1);
    assert_eq!(f.mods(id).unwrap().power * 100, b.power * 108);
    for k in 0..6 {
        add(&mut f, &bare(MAGE, 10), x, y + px(10 * k));
    }
    idle(&mut f, 1);
    assert_eq!(f.mods(id).unwrap().power * 100, b.power * 120);
}

#[test]
fn ten_of_swords_bursts_160_px_on_being_downed() {
    let (mut f, id, _, m) = with(KNIGHT, 10, card("TEN OF SWORDS"), 1);
    assert_eq!((m.burst_px, m.burst_dmg), (160, 300));
    let (x, y) = (f.heroes()[id as usize].x, f.heroes()[id as usize].y);
    let near = mon(&mut f, DROWNED_K, 60, x + px(150), y);
    let far = mon(&mut f, DROWNED_K, 60, x + px(175), y);
    let k = mon(&mut f, DROWNED_K, 60, x + px(10), y);
    let _ = k;
    f.hero_mut(id).health = 1;
    for _ in 0..CONTACT_EVERY + 1 {
        let (hn, hf) = (f.monsters().hp[near as usize], f.monsters().hp[far as usize]);
        f.monsters_mut().stun[near as usize] = 250;
        f.monsters_mut().stun[far as usize] = 250;
        f.hero_mut(id).charge = 0;
        f.step::<u16>(&[]);
        if count(&f, DOWN) == 1 {
            assert_eq!(hn - f.monsters().hp[near as usize], 300);
            assert_eq!(hf, f.monsters().hp[far as usize]);
            return;
        }
    }
    panic!("not downed");
}

#[test]
fn queen_of_pentacles_loses_a_tenth_less_on_a_fall() {
    let (mut f, id, _, m) = with(KNIGHT, 10, card("QUEEN OF PENTACLES"), 1);
    assert_eq!(m.keep_tenths, 1);
    f.hero_mut(id).coin = 1000;
    f.hero_mut(id).health = 0;
    f.hero_mut(id).downed = 1;
    f.step::<u16>(&[]);
    assert!(f.events().contains(&Event::Fallen { hero: id, coin: 400 }));
    assert_eq!(f.heroes()[id as usize].coin, 600);
}

#[test]
fn knight_of_wands_gives_15_percent_move_for_3_s_after_a_kill() {
    let (mut f, id, b, _) = with(KNIGHT, 10, card("KNIGHT OF WANDS"), 2);
    let (x, y) = (f.heroes()[id as usize].x, f.heroes()[id as usize].y);
    let k = mon(&mut f, DROWNED_K, 1, x + px(30), y);
    f.monsters_mut().hp[k as usize] = 1;
    f.hero_mut(id).charge = 1_000_000;
    f.step::<u16>(&[]);
    assert_eq!(count(&f, KILL), 1);
    assert_eq!(f.heroes()[id as usize].fx[FX_KNIGHT_OF_WANDS as usize], secs(3) as u16);
    idle(&mut f, 1);
    assert_eq!(f.mods(id).unwrap().move_pct - b.move_pct, 30);
}

// ---- the deck

#[test]
fn entering_a_field_gives_her_opening_draw_of_three_from_the_deck() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 24);
    let s = Sheet::bench(KNIGHT, HUMAN, 30);
    let id = add(&mut f, &s, x, y);
    let h = &f.heroes()[id as usize];
    assert_eq!((h.offers.len(), h.draws, h.owed), (1, 1, 0));
    let o = h.offers[0];
    assert!(o[..3].iter().all(|c| s.deck.contains(c)) && o[3] == 0);
    assert!(o[0] != o[1] && o[1] != o[2] && o[0] != o[2]);
    // Once an outing: a hero moved to another copy brings her draws and gets no second opening draw.
    let out = f.outing(id).unwrap();
    let mut g = quiet(3);
    let j = g.join(&s, &out, x, y);
    assert_eq!((g.heroes()[j as usize].offers.len(), g.heroes()[j as usize].draws), (1, 1));
}

#[test]
fn an_elite_kill_queues_a_draw_and_a_plain_kill_does_not() {
    let mut f = quiet(2);
    let (x, y) = spot(&f, 24);
    let s = Sheet::bench(KNIGHT, HUMAN, 30);
    let id = add(&mut f, &s, x, y);
    f.hero_mut(id).offers.clear();
    for (flags, grants) in [(0, 0), (ELITE, 1)] {
        let k = f.place_monster(DROWNED_K, 25, flags, x + px(30), y).unwrap();
        f.monsters_mut().hp[k as usize] = 1;
        f.hero_mut(id).charge = 1_000_000;
        f.hero_mut(id).active = f.tick();
        f.step::<u16>(&[]);
        assert_eq!(count(&f, KILL), 1);
        assert_eq!((count(&f, GRANT), count(&f, DRAW)), (grants, grants));
    }
    assert!(f.events().contains(&Event::Grant { hero: id, source: GRANT_KILL }));
    assert_eq!(f.heroes()[id as usize].offers.len(), 1);
}

#[test]
fn a_shrine_grants_a_draw_through_grant_draw() {
    let mut f = quiet(2);
    let id = add(&mut f, &Sheet::bench(KNIGHT, HUMAN, 30), FIELD / 2, FIELD / 2);
    idle(&mut f, 1);
    let n = f.heroes()[id as usize].offers.len();
    assert!(f.grant_draw(id as usize, GRANT_SHRINE));
    assert_eq!(f.heroes()[id as usize].offers.len(), n + 1);
    assert!(f.events().contains(&Event::Grant { hero: id, source: GRANT_SHRINE }));
    assert_eq!(count(&f, DRAW), 1);
    assert!(!f.grant_draw(99, GRANT_SHRINE), "no such hero");
}

#[test]
fn the_mage_draws_four() {
    let mut f = quiet(2);
    let id = add(&mut f, &Sheet::bench(MAGE, HUMAN, 30), FIELD / 2, FIELD / 2);
    let (o, n) = roll_offer(1, id, 0, &f.heroes()[id as usize].sheet.deck, &[0; NCARDS + 1], CLASSES[MAGE as usize].passive.draw_size);
    assert_eq!(n, 4);
    assert!(o.iter().all(|&c| c != 0));
}

#[test]
fn draws_wait_in_a_queue_of_nine_and_none_is_lost() {
    let mut f = quiet(2);
    let id = add(&mut f, &Sheet::bench(KNIGHT, HUMAN, 30), FIELD / 2, FIELD / 2);
    f.hero_mut(id).offers.clear();
    f.hero_mut(id).owed = 12;
    // Any grant fills the queue from what is owed.
    f.grant_draw(id as usize, GRANT_SHRINE);
    assert_eq!(f.heroes()[id as usize].offers.len(), DRAW_QUEUE);
    assert_eq!(f.heroes()[id as usize].owed, 4);
    // Each pick lets one more in.
    let mut inputs = [1u16 << IN_PICK_SHIFT];
    f.step(&inputs);
    assert_eq!((f.heroes()[id as usize].offers.len(), f.heroes()[id as usize].owed), (DRAW_QUEUE, 3));
    inputs[0] = 0;
    f.step(&inputs);
    assert_eq!(count(&f, PICK), 0, "a held pick does not pick again");
}

#[test]
fn five_copies_at_most_and_a_full_card_is_not_offered() {
    let mut f = quiet(2);
    let s = Sheet::bench(KNIGHT, HUMAN, 30);
    let id = add(&mut f, &s, FIELD / 2, FIELD / 2);
    let mut copies = [0u8; NCARDS + 1];
    for &c in &s.deck[1..] {
        copies[c as usize] = MAX_COPIES;
    }
    for d in 0..50 {
        let (o, n) = roll_offer(7, id, d, &s.deck, &copies, 3);
        assert_eq!((n, o[0]), (1, s.deck[0]));
    }
    f.hero_mut(id).copies[s.deck[0] as usize] = MAX_COPIES;
    f.hero_mut(id).offers = vec![[s.deck[0], 0, 0, 0]];
    f.step(&[1u16 << IN_PICK_SHIFT]);
    assert_eq!(f.heroes()[id as usize].copies[s.deck[0] as usize], MAX_COPIES);
    assert_eq!(count(&f, PICK), 0);
}

#[test]
fn draws_are_the_same_whatever_else_happens() {
    let deck: Vec<u8> = (1..=20).collect();
    let c = [0u8; NCARDS + 1];
    assert_eq!(roll_offer(5, 3, 9, &deck, &c, 3), roll_offer(5, 3, 9, &deck, &c, 3));
    assert_ne!(roll_offer(5, 3, 9, &deck, &c, 3), roll_offer(5, 3, 10, &deck, &c, 3));
}
