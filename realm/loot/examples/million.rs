//! Rolls a million kills over the six fields and prints each rate beside the contract's:
//! `cargo run --release -p realm-loot --example million`.
use realm_core::tables::{FIELDS, KINDS};
use realm_core::{CHAMPION, ELITE};
use realm_loot::rng::Rng;
use realm_loot::*;
use realm_store::StackClass;

fn main() {
	let mut rng = Rng::new(2026);
	let n = 1_000_000u64;
	// kills, items, embers, runes, pages, keys, cards, field material, kept items
	let mut t = [[0u64; 9]; 3];
	let mut rar = [0u64; 5];
	for i in 0..n {
		let f = &FIELDS[(i % 6) as usize];
		let kind = f.first_kind + rng.below(f.kind_count as u64) as u8;
		let _ = &KINDS[kind as usize];
		let level = f.bottom + rng.below((f.top - f.bottom + 1) as u64) as u8;
		let (tier, flags) = match rng.below(2000) {
			0 => (2, CHAMPION),
			x if x % 50 == 1 => (1, ELITE),
			_ => (0, 0),
		};
		t[tier][0] += 1;
		let key = RollKey { field_seed: 1, tick: i as u32, index: 0, slot: 0 };
		for d in roll(7, &key, &Credit::plain(), &Source::Kill { kind, level, flags }, &mut RollGate::new()) {
			match d.what {
				What::Item(s) => {
					t[tier][1] += 1;
					t[tier][8] += d.kept as u64;
					rar[s.rarity as usize] += 1;
				}
				What::Stack(k, _) => match k.class().unwrap() {
					StackClass::Material if k.0 == 1000 => t[tier][2] += 1,
					StackClass::Material => t[tier][7] += 1,
					StackClass::Rune => t[tier][3] += 1,
					StackClass::Page => t[tier][4] += 1,
					StackClass::Key => t[tier][5] += 1,
					StackClass::Card => t[tier][6] += 1,
					_ => {}
				},
			}
		}
	}
	let names = ["monster", "ELITE", "CHAMPION"];
	let cols = ["items", "embers", "runes", "pages", "keys", "cards", "field material", "kept items"];
	println!("| tier | kills | {} |\n|---|---|{}", cols.join(" | "), "---|".repeat(cols.len()));
	for (i, row) in t.iter().enumerate() {
		let cells: Vec<String> = (1..9).map(|c| format!("{} (1 in {:.0})", row[c], row[0] as f64 / row[c].max(1) as f64)).collect();
		println!("| {} | {} | {} |", names[i], row[0], cells.join(" | "));
	}
	println!("items by rarity: {rar:?}");
}
