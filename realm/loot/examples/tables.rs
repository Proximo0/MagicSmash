//! Prints the loot tables as markdown for `docs/realm/economy.md`: `cargo run --release -p realm-loot --example tables`.
use realm_core::tables::FIELDS;
use realm_loot::cards::*;
use realm_loot::gear::*;
use realm_loot::smith::*;
use realm_loot::tables::*;
use realm_loot::{power_coin, scaled};
use realm_store::ItemSpec;

fn spec(level: u16, rarity: u8, plus: u8) -> ItemSpec {
	ItemSpec { base: 0, gear_slot: 0, item_level: level, rarity, lines: vec![(0, 1)], sockets: 0, plus, bound: false }
}

fn main() {
	println!("| card | name | stat | points | own kind % |\n|---|---|---|---|---|");
	for c in 0..CARD_COUNT {
		let r = card_rule(c).unwrap();
		println!("| {c} | {} | {} | {} | {} |", card_name(c), STAT_NAMES[r.stat as usize], r.points, r.own_pct);
	}
	println!();
	println!("| level | COMMON line | UNCOMMON | RARE | EPIC | RELIC |\n|---|---|---|---|---|---|");
	for l in [1u16, 10, 20, 30, 40, 50, 60] {
		println!("| {l} | {} | {} | {} | {} | {} |", line_value(l, 0), line_value(l, 1), line_value(l, 2), line_value(l, 3), line_value(l, 4));
	}
	println!();
	println!("| item level | salvage COMMON | RARE | RELIC | step +1 | step +5 | step +10 | all ten steps | reroll COMMON | reroll RELIC |\n|---|---|---|---|---|---|---|---|---|---|");
	for l in [1u16, 10, 20, 30, 40, 50, 60] {
		let (mut e, mut c) = (0, 0);
		for p in 0..10 {
			let k = upgrade_cost(&spec(l, 0, p)).unwrap();
			e += k.embers;
			c += k.coin;
		}
		let s = |p| upgrade_cost(&spec(l, 0, p)).unwrap();
		let (r0, r4) = (reroll_cost(&spec(l, 0, 0)), reroll_cost(&spec(l, 4, 0)));
		println!(
			"| {l} | {} | {} | {} | {}e {}c | {}e {}c | {}e {}c | {e}e {c}c | {}e {}c | {}e {}c |",
			salvage_embers(&spec(l, 0, 0)),
			salvage_embers(&spec(l, 2, 0)),
			salvage_embers(&spec(l, 4, 0)),
			s(0).embers,
			s(0).coin,
			s(4).embers,
			s(4).coin,
			s(9).embers,
			s(9).coin,
			r0.embers,
			r0.coin,
			r4.embers,
			r4.coin
		);
	}
	println!();
	println!("| field | top level | embers per 1,000 kills | coin of a boss chest |\n|---|---|---|---|");
	for f in FIELDS.iter() {
		let one = (scaled(1, f.top) as f64) / EMBER_MONSTER_ONE_IN as f64 * 0.97 + scaled(3, f.top) as f64 * 0.02 + scaled(10, f.top) as f64 * 0.0005;
		println!("| {} | {} | {:.0} | {} |", f.name, f.top, one * 1000.0, power_coin(BOSS_COIN, f.top));
	}
	println!();
	println!("| boss | field | page (card) | card stat |\n|---|---|---|---|");
	for (i, b) in BOSSES.iter().enumerate() {
		println!("| {} | {} | {} | {} |", b.name, FIELDS[b.field as usize].name, b.page + 1, STAT_NAMES[BOSS_CARD_STAT[i] as usize]);
	}
}
