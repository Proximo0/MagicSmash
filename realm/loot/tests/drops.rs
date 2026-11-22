//! The proof of rules section 9: a million kills across all six fields, every drop rate against the contract.

use realm_core::tables::{FIELDS, KINDS};
use realm_core::{CHAMPION, ELITE};
use realm_loot::cards::*;
use realm_loot::gear::*;
use realm_loot::rng::Rng;
use realm_loot::tables::*;
use realm_loot::*;
use realm_store::StackKind;

const SECRET: u64 = 0xfeed_beef;

fn key(i: u64) -> RollKey {
	RollKey { field_seed: 7, tick: i as u32, index: (i >> 20) as u32, slot: (i % 13) as u16 }
}

/// |count - n p| within 5 sigma (and a little slack for tiny expectations).
fn near(what: &str, count: u64, n: u64, p: f64) {
	let mean = n as f64 * p;
	let tol = 5.0 * (n as f64 * p * (1.0 - p)).sqrt() + 1.0;
	assert!((count as f64 - mean).abs() <= tol, "{what}: got {count}, expected {mean:.1} +- {tol:.1} (n={n}, p={p})");
}

fn pick_kind(rng: &mut Rng, field: usize) -> u8 {
	let f = &FIELDS[field];
	let total: u32 = (0..f.kind_count as usize).map(|i| KINDS[f.first_kind as usize + i].weight).sum();
	let mut p = rng.below(total as u64) as u32;
	for i in 0..f.kind_count as usize {
		let k = f.first_kind as usize + i;
		if p < KINDS[k].weight {
			return k as u8;
		}
		p -= KINDS[k].weight;
	}
	unreachable!()
}

fn check_item(spec: &realm_store::ItemSpec, field: u8, level: u8, min: u8) {
	assert!(spec.rarity >= min, "rarity {} below {}", spec.rarity, min);
	assert_eq!(spec.item_level, level as u16);
	assert_eq!(spec.lines.len(), RARITY_LINES[spec.rarity as usize]);
	assert_eq!(spec.sockets, RARITY_SOCKETS[spec.rarity as usize]);
	assert_eq!(spec.plus, 0);
	let mut stats: Vec<u8> = spec.lines.iter().map(|l| l.0).collect();
	stats.sort();
	stats.dedup();
	assert_eq!(stats.len(), spec.lines.len(), "lines draw different stats");
	for (_, pts) in &spec.lines {
		assert_eq!(*pts, line_value(level as u16, spec.rarity));
	}
	assert_eq!(spec.gear_slot as u32, spec.base / 100);
	assert_eq!((spec.base / 10 % 10) as u8, field);
	assert!(spec.lines.iter().all(|l| l.1 >= 1));
}

#[derive(Default, Clone, Copy)]
struct Tier {
	kills: u64,
	items: u64,
	embers: u64,
	material: u64,
	runes: u64,
	pages: u64,
	keys: u64,
	cards: u64,
	kept_items: u64,
	haul_items: u64,
}

#[test]
fn a_million_kills_match_the_contract() {
	let mut rng = Rng::new(99);
	let mut t = [Tier::default(); 3]; // monster, elite, champion
	let mut keys_by_field = [0u64; 6];
	let mut elites_by_field = [0u64; 6];
	let mut rarity_of_items = [0u64; 5];
	let mut slots = [0u64; 6];
	let n = 1_000_000u64;
	for i in 0..n {
		let field = (i % 6) as usize;
		let f = &FIELDS[field];
		let kind = pick_kind(&mut rng, field);
		let level = f.bottom + rng.below((f.top - f.bottom + 1) as u64) as u8;
		let (tier, flags) = match rng.below(2000) {
			0 => (2, CHAMPION),
			x if x % 50 == 1 => (1, ELITE),
			_ => (0, 0),
		};
		t[tier].kills += 1;
		if tier == 1 {
			elites_by_field[field] += 1;
		}
		let min = if tier == 2 { UNCOMMON } else { COMMON };
		let drops = roll(SECRET, &key(i), &Credit::plain(), &Source::Kill { kind, level, flags }, &mut RollGate::new());
		for d in &drops {
			match &d.what {
				What::Item(s) => {
					check_item(s, field as u8, level, min);
					t[tier].items += 1;
					rarity_of_items[s.rarity as usize] += 1;
					slots[s.gear_slot as usize] += 1;
					assert_eq!(d.kept, s.rarity >= RARE, "RARE and better are kept, the rest ride in the haul");
					if d.kept { t[tier].kept_items += 1 } else { t[tier].haul_items += 1 }
				}
				What::Stack(k, c) => match k.class().unwrap() {
					realm_store::StackClass::Material if k.0 == 1000 => {
						t[tier].embers += 1;
						assert!(!d.kept && *c >= 1);
					}
					realm_store::StackClass::Material => {
						t[tier].material += 1;
						assert_eq!(k.0, 1000 + 1 + field as u32);
						assert!(!d.kept);
					}
					realm_store::StackClass::Rune => {
						t[tier].runes += 1;
						assert_eq!(k.0 % 10, 1, "elite runes are grade I");
						assert!(d.kept);
					}
					realm_store::StackClass::Page => {
						t[tier].pages += 1;
						assert!((4000 + PAGE_FIRST..=4000 + PAGE_LAST).contains(&k.0));
						assert!(d.kept);
					}
					realm_store::StackClass::Key => {
						t[tier].keys += 1;
						keys_by_field[field] += 1;
						assert_eq!(k.0, 3000 + field as u32);
					}
					realm_store::StackClass::Card => {
						t[tier].cards += 1;
						assert_eq!(k.0, 5000 + kind as u32, "a kind's own card");
						assert!(d.kept);
					}
					c => panic!("a kill dropped {c:?}"),
				},
			}
		}
	}
	let (m, e, c) = (t[0], t[1], t[2]);
	assert!(m.kills > 900_000 && e.kills > 15_000 && c.kills > 300, "kills {} {} {}", m.kills, e.kills, c.kills);
	// the item roll: monster 1 in 400, ELITE 1 in 20, CHAMPION always
	near("monster item", m.items, m.kills, 1.0 / 400.0);
	near("elite item", e.items, e.kills, 1.0 / 20.0);
	assert_eq!(c.items, c.kills, "a champion always rolls an item");
	// the extra rolls belong to elites only
	assert_eq!(m.runes + m.pages + m.keys + m.material, 0);
	assert_eq!(c.runes + c.pages + c.keys, 0);
	near("elite rune", e.runes, e.kills, 1.0 / 30.0);
	near("elite page", e.pages, e.kills, 1.0 / 300.0);
	near("elite material", e.material, e.kills, 0.5);
	near("monster embers", m.embers, m.kills, 1.0 / 8.0);
	assert_eq!(e.embers, e.kills);
	// vault keys: 1 in 150 from an elite of a field whose top level is 20 or more
	assert_eq!(keys_by_field[0], 0, "THE FOOL'S ROAD tops at 10: no keys");
	for f in 1..6 {
		near(&format!("keys field {f}"), keys_by_field[f], elites_by_field[f], 1.0 / 150.0);
	}
	// cards (monster and elite share the 1 in 20,000)
	near("cards", m.cards + e.cards, m.kills + e.kills, 1.0 / 20_000.0);
	// RARE and better are kept, others ride in the haul
	assert_eq!(m.kept_items + e.kept_items + c.kept_items, rarity_of_items[2..].iter().sum::<u64>());
	// rarity: contract shares from the roll itself over many draws (the kills above give too few RELIC)
	let items: u64 = rarity_of_items.iter().sum();
	assert!(items > 3_000, "items {items}");
	for r in 0..2 {
		// champions start at UNCOMMON, so skew COMMON a little low: allow their 500 items
		let p = RARITY_PER_MILLE[r] as f64 / 1000.0;
		let tol = 5.0 * (items as f64 * p * (1.0 - p)).sqrt() + c.kills as f64;
		assert!((rarity_of_items[r] as f64 - items as f64 * p).abs() <= tol, "rarity {r}: {rarity_of_items:?}");
	}
	let mean_slot = items as f64 / 6.0;
	for s in 0..6 {
		assert!((slots[s] as f64 - mean_slot).abs() < 5.0 * (mean_slot).sqrt() + 5.0, "slot {s}: {slots:?}");
	}
}

#[test]
fn rarity_shares_match_the_contract() {
	let mut rng = Rng::new(5);
	let n = 4_000_000u64;
	let mut got = [0u64; 5];
	let mut above = [0u64; 5];
	for _ in 0..n {
		got[roll_rarity(&mut rng, COMMON) as usize] += 1;
	}
	for _ in 0..n {
		above[roll_rarity(&mut rng, UNCOMMON) as usize] += 1;
	}
	for r in 0..5 {
		near(&format!("rarity {r}"), got[r], n, RARITY_PER_MILLE[r] as f64 / 1000.0);
	}
	assert_eq!(above[0], 0, "a champion's roll never gives COMMON");
	for r in 1..5 {
		near(&format!("rarity {r} from UNCOMMON"), above[r], n, RARITY_PER_MILLE[r] as f64 / 400.0);
	}
}

#[test]
fn every_kind_drops_its_own_card_one_in_twenty_thousand() {
	let mut rng = Rng::new(3);
	let per = 300_000u64;
	let mut total = 0;
	for kind in 0..42u8 {
		let f = &FIELDS[KINDS[kind as usize].field as usize];
		let mut hits = 0;
		for i in 0..per {
			let level = f.bottom + rng.below((f.top - f.bottom + 1) as u64) as u8;
			let d = roll(SECRET, &key(i + kind as u64 * per), &Credit::plain(), &Source::Kill { kind, level, flags: 0 }, &mut RollGate::new());
			hits += d.iter().filter(|x| matches!(x.what, What::Stack(k, _) if k == StackKind::card(kind as u32))).count() as u64;
		}
		near(&format!("card of kind {kind}"), hits, per, 1.0 / 20_000.0);
		total += hits;
	}
	near("all kind cards", total, 42 * per, 1.0 / 20_000.0);
}

#[test]
fn champions_and_bosses_drop_cards_at_their_rates() {
	let n = 400_000u64;
	let (mut champ, mut boss) = (0, 0);
	for i in 0..n {
		let d = roll(SECRET, &key(i), &Credit::plain(), &Source::Kill { kind: 5, level: 8, flags: CHAMPION }, &mut RollGate::new());
		champ += d.iter().filter(|x| matches!(x.what, What::Stack(k, _) if k == StackKind::card(5))).count() as u64;
		let d = roll(SECRET, &key(i), &Credit::plain(), &Source::BossChest { boss: 3, level: 38, first_kill: false }, &mut RollGate::new());
		boss += d.iter().filter(|x| matches!(x.what, What::Stack(k, _) if k == StackKind::card(42 + 3))).count() as u64;
	}
	near("champion card 1 in 200", champ, n, 1.0 / 200.0);
	near("boss card 1 in 100", boss, n, 1.0 / 100.0);
}

#[test]
fn luck_and_reduced_drops_scale_the_item_chance() {
	let n = 1_500_000u64;
	let count = |c: Credit| {
		let mut items = 0;
		for i in 0..n {
			let d = roll(SECRET, &key(i), &c, &Source::Kill { kind: 2, level: 5, flags: 0 }, &mut RollGate::new());
			items += d.iter().filter(|x| matches!(x.what, What::Item(_))).count() as u64;
		}
		items
	};
	near("luck 0", count(Credit { luck: 0, drops_percent: 100 }), n, 1.0 / 400.0);
	near("luck 100 doubles", count(Credit { luck: 100, drops_percent: 100 }), n, 2.0 / 400.0);
	near("luck 25", count(Credit { luck: 25, drops_percent: 100 }), n, 1.25 / 400.0);
	near("reduced to 40%", count(Credit { luck: 0, drops_percent: 40 }), n, 0.4 / 400.0);
}

#[test]
fn the_cap_is_twelve_item_rolls_a_minute() {
	let mut g = RollGate::new();
	let ok = (0..30).filter(|_| g.take(0)).count();
	assert_eq!(ok, 12);
	assert!(!g.take(1_199));
	assert!(g.take(1_200), "the minute has passed since the first of the twelve");
	// a champion every tick gets 12 items in a minute and no more
	let mut gate = RollGate::new();
	let mut items = 0;
	for tick in 0..2_400u32 {
		let k = RollKey { field_seed: 1, tick, index: 0, slot: 0 };
		let d = roll(SECRET, &k, &Credit::plain(), &Source::Kill { kind: 0, level: 3, flags: CHAMPION }, &mut gate);
		items += d.iter().filter(|x| matches!(x.what, What::Item(_))).count();
	}
	assert_eq!(items, 24);
}

#[test]
fn a_replay_gives_the_same_drops() {
	let src = Source::Kill { kind: 9, level: 12, flags: ELITE };
	let mut a = Vec::new();
	let mut b = Vec::new();
	for i in 0..20_000u64 {
		a.push(roll(SECRET, &key(i), &Credit::plain(), &src, &mut RollGate::new()));
		b.push(roll(SECRET, &key(i), &Credit::plain(), &src, &mut RollGate::new()));
	}
	assert_eq!(a, b);
	let other: Vec<_> = (0..20_000u64).map(|i| roll(SECRET + 1, &key(i), &Credit::plain(), &src, &mut RollGate::new())).collect();
	assert_ne!(a, other, "another secret rolls differently");
	// two heroes credited with the same kill roll for themselves
	let mut k1 = key(5);
	let mut k2 = key(5);
	k1.slot = 1;
	k2.slot = 2;
	let many = |k: &RollKey| (0..2000).map(|j| roll(SECRET, &RollKey { tick: j, ..*k }, &Credit::plain(), &src, &mut RollGate::new())).collect::<Vec<_>>();
	assert_ne!(many(&k1), many(&k2));
}

#[test]
fn chests_hold_what_the_contract_says() {
	for boss in 0..BOSS_COUNT as u8 - 1 {
		let b = &BOSSES[boss as usize];
		let level = FIELDS[b.field as usize].top;
		for i in 0..200 {
			let d = roll(SECRET, &key(i), &Credit::plain(), &Source::BossChest { boss, level, first_kill: i == 0 }, &mut RollGate::new());
			let items: Vec<_> = d.iter().filter_map(|x| if let What::Item(s) = &x.what { Some(s) } else { None }).collect();
			assert_eq!(items.len(), 2, "two item rolls");
			for s in &items {
				check_item(s, b.field, level, RARE);
			}
			assert!(d.iter().all(|x| x.kept), "a chest is kept at once");
			let stacks: Vec<_> = d.iter().filter_map(|x| if let What::Stack(k, n) = &x.what { Some((*k, *n)) } else { None }).collect();
			assert!(stacks.iter().any(|(k, _)| *k == StackKind::rune(0, 2) || (0..6).any(|s| *k == StackKind::rune(s, 2))), "a grade II rune");
			assert!(stacks.iter().any(|(k, n)| *k == StackKind::COIN && *n >= power_coin(BOSS_COIN, level)));
			assert!(stacks.iter().any(|(k, _)| k.0 == 1000));
			let page = StackKind::page(b.page as u32);
			assert_eq!(stacks.iter().any(|(k, _)| *k == page), i == 0, "the page comes with the first kill only");
		}
	}
	for i in 0..200 {
		let d = roll(SECRET, &key(i), &Credit::plain(), &Source::WorldChest { level: 60, top: true }, &mut RollGate::new());
		let s = d.iter().find_map(|x| if let What::Item(s) = &x.what { Some(s) } else { None }).unwrap();
		assert_eq!(s.rarity, RELIC);
		assert_eq!(s.sockets, 2);
		let d = roll(SECRET, &key(i), &Credit::plain(), &Source::WorldChest { level: 60, top: false }, &mut RollGate::new());
		let s = d.iter().find_map(|x| if let What::Item(s) = &x.what { Some(s) } else { None }).unwrap();
		assert!(s.rarity >= EPIC);
	}
	for i in 0..200 {
		let d = roll(SECRET, &key(i), &Credit::plain(), &Source::TideCache { field: 2, level: 25 }, &mut RollGate::new());
		let n = d.iter().filter(|x| matches!(x.what, What::Item(_))).count();
		assert_eq!(n, 3);
		assert!(d.iter().all(|x| x.kept));
		for x in &d {
			if let What::Item(s) = &x.what {
				check_item(s, 2, 25, UNCOMMON);
			}
		}
	}
}

#[test]
fn gear_numbers_follow_the_contract() {
	// 1 + item level / 4 points x the step
	assert_eq!(line_value(1, COMMON), 1);
	assert_eq!(line_value(40, COMMON), 11);
	assert_eq!(line_value(40, UNCOMMON), 13);
	assert_eq!(line_value(40, RARE), 16);
	assert_eq!(line_value(40, EPIC), 20);
	assert_eq!(line_value(60, RELIC), 38);
	// the core's bench sheet assumes the same points
	for l in 1..=60u16 {
		assert_eq!(line_points(l), realm_core::line_points(l as u8));
	}
	// +3% a plus, summed in hundredths
	let mut rng = Rng::new(1);
	let mut s = make_item(&mut rng, 4, 40, RELIC);
	let base = item_hundredths(&s, &[]);
	s.plus = 10;
	let up = item_hundredths(&s, &[]);
	for i in 0..6 {
		assert_eq!(up[i], base[i] / 100 * 130);
	}
	// a rune or a card in a socket adds its points
	let with = item_hundredths(&s, &[Some(StackKind::rune(2, 3)), Some(StackKind::card(42))]);
	assert_eq!(with[2], up[2] + 700 + if card_rule(42).unwrap().stat == 2 { card_rule(42).unwrap().points as u32 * 100 } else { 0 });
}
