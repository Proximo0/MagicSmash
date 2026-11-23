//! Coin sinks paid in town (job B1, `docs/realm/balance.md`): repairing worn gear after an outing and the fare to a
//! waystone; and the income table the smith's coin prices follow. Numbers only; the gateway charges them (W2/E1).
//!
//! A kill pays its XP in coin (rules 9), and a hero kills thousands an hour, so what a hero earns an hour grows about
//! seven hundredfold from THE FOOL'S ROAD to THE WORLD'S EDGE. A sink priced by item level alone would be nothing at
//! the top or everything at the bottom, so these are priced in hours of the income of the field an item's level
//! belongs to (`INCOME_PER_HOUR`, measured by `realm-loadtest balance career`).

use crate::roll::power_coin;
use realm_core::tables::FIELDS;
use realm_store::ItemSpec;

/// The price base of every sink: coin an hour of the field a level belongs to (the last whose bottom it has
/// reached), measured by B1's careers (balance.md). Fields 0 to 2 are held at about half their measured kill income
/// (2k, 166k, 210k): careers fall there often, a fall wears gear (`REPAIR_FALL_MINUTES`), and at the full income the
/// repair alone took more than the kills paid. Fields 3 to 5 are 1.7, 2 and 1.25 times it (805k, 1.56M, 3.7M), so
/// that the repair and the smith together take what the kills mint there.
pub const INCOME_PER_HOUR: [u64; 6] = [1_500, 90_000, 90_000, 1_400_000, 3_200_000, 4_600_000];

/// Repair of one worn item for an hour in a field, in hundredths of a percent of the income an hour of its level.
pub const REPAIR_BP_PER_HOUR: u64 = 600;
/// Repair by rarity: a finer item costs more to mend (COMMON to RELIC).
pub const REPAIR_RARITY_PCT: [u64; 5] = [100, 110, 125, 150, 200];
/// Each smith step (+1) adds this percent to the repair.
pub const REPAIR_PLUS_PCT: u64 = 5;
/// A fall wears every worn item as much as this many minutes in the field.
pub const REPAIR_FALL_MINUTES: u64 = 15;
/// The least repair of an item an hour (coin), so the first field is not free.
pub const REPAIR_MIN_PER_HOUR: u64 = 10;

/// The fare to a waystone, in hundredths of a percent of an hour's income of the field, by ring (edge, middle,
/// heart). The gate at the south edge is free.
pub const TRAVEL_BP: [u64; 3] = [100, 200, 300];
/// The least fare (coin).
pub const TRAVEL_MIN: u64 = 20;

/// The smith's coin for a step to +s is at least this many hundredths of a percent of an hour's income at the
/// item's level, x s^2 (`smith::upgrade_cost`): +1 to +5 is 0.8 hours of income a piece.
pub const SMITH_STEP_BP: u64 = 150;

/// Taking a job at the trainer (rules section 3, after THE CLASS TRIAL): this many hundredths of a percent of an
/// hour's income at her class level, half an hour's. A one-off sink at level 40, where the glut begins: about
/// 1.4 million coin at level 40, which a career mints in 20 to 40 minutes there (balance.md, the coin book).
pub const JOB_CHANGE_BP: u64 = 5_000;

/// The price of the 2nd to the 8th bank tab (the first is free; the account owns them, so the price does not
/// follow a hero's level). Each about four times the last: the 2nd is two hours of THE FOOL'S ROAD's income, a
/// first goal; the 8th is about two and a half hours of THE WORLD'S EDGE's. All seven are 16.3 million, about a
/// tenth of what a career mints, nearly all of it at the top where coin piles up (economy.md, the coin glut).
pub const BANK_TAB_PRICE: [u64; 7] = [3_000, 12_000, 50_000, 200_000, 800_000, 3_200_000, 12_000_000];

/// The trainer's price for a job at a class level.
pub fn job_change_cost(level: u16) -> u64 {
	income_per_hour(level) * JOB_CHANGE_BP / 10_000
}

/// The price of the next bank tab for an account that owns `owned` tabs (the free one counted), or None when it
/// has every tab there is.
pub fn bank_tab_price(owned: u32) -> Option<u64> {
	BANK_TAB_PRICE.get((owned as usize).checked_sub(1)?).copied()
}

/// The field a level belongs to for prices: the last whose bottom level it has reached.
pub fn price_field(level: u16) -> usize {
	(0..FIELDS.len()).rev().find(|&f| FIELDS[f].bottom as u16 <= level).unwrap_or(0)
}

/// Income an hour at a level (`INCOME_PER_HOUR` of its field, grown within the field like a kill's coin).
pub fn income_per_hour(level: u16) -> u64 {
	let f = price_field(level);
	let bottom = FIELDS[f].bottom.max(1);
	let mid = (FIELDS[f].bottom + FIELDS[f].top) / 2;
	// The table is the field's middle level; a level above or below it scales by the monsters' power.
	let at = |l: u8| power_coin(1_000, l.max(bottom));
	INCOME_PER_HOUR[f] * at(level.min(60) as u8) / at(mid)
}

/// The repair of one worn item after `minutes` in a field with `falls` falls.
pub fn repair_cost(spec: &ItemSpec, minutes: u64, falls: u64) -> u64 {
	let hour = (income_per_hour(spec.item_level) * REPAIR_BP_PER_HOUR / 10_000).max(REPAIR_MIN_PER_HOUR);
	let hour = hour * REPAIR_RARITY_PCT[spec.rarity.min(4) as usize] / 100 * (100 + REPAIR_PLUS_PCT * spec.plus as u64) / 100;
	hour * (minutes + falls * REPAIR_FALL_MINUTES) / 60
}

/// The fare to a waystone in `ring` (0 edge, 1 middle, 2 heart) of `field`.
pub fn travel_cost(field: u8, ring: u8) -> u64 {
	let f = (field as usize).min(FIELDS.len() - 1);
	(INCOME_PER_HOUR[f] * TRAVEL_BP[(ring as usize).min(2)] / 10_000).max(TRAVEL_MIN)
}

#[cfg(test)]
mod tests {
	use super::*;

	fn item(level: u16, rarity: u8, plus: u8) -> ItemSpec {
		ItemSpec { base: 0, gear_slot: 0, item_level: level, rarity, lines: vec![(0, 1)], sockets: 0, plus, bound: false }
	}

	#[test]
	fn repair_grows_with_level_rarity_plus_time_and_falls() {
		assert!(repair_cost(&item(30, 0, 0), 60, 0) > repair_cost(&item(10, 0, 0), 60, 0));
		assert!(repair_cost(&item(55, 0, 0), 60, 0) > repair_cost(&item(30, 0, 0), 60, 0));
		assert!(repair_cost(&item(30, 2, 0), 60, 0) > repair_cost(&item(30, 1, 0), 60, 0));
		assert!(repair_cost(&item(30, 2, 5), 60, 0) > repair_cost(&item(30, 2, 0), 60, 0));
		assert_eq!(repair_cost(&item(30, 0, 0), 0, 4), repair_cost(&item(30, 0, 0), REPAIR_FALL_MINUTES * 4, 0));
		assert_eq!(repair_cost(&item(60, 4, 10), 0, 0), 0);
		assert!(repair_cost(&item(1, 0, 0), 60, 0) >= REPAIR_MIN_PER_HOUR);
		// An hour of six UNCOMMON pieces of a level costs about 6 x 6.6% of that level's income.
		let six = 6 * repair_cost(&item(35, 1, 0), 60, 0);
		let inc = income_per_hour(35);
		assert!(six * 100 > inc * 37 && six * 100 < inc * 42, "{six} of {inc}");
	}

	#[test]
	fn income_follows_the_fields_and_grows_within_one() {
		assert_eq!(price_field(9), 0);
		assert_eq!(price_field(10), 1);
		assert_eq!(price_field(60), 5);
		assert_eq!(income_per_hour(35), INCOME_PER_HOUR[3]);
		assert!(income_per_hour(39) > income_per_hour(31));
	}

	#[test]
	fn the_job_and_the_bank_tabs_cost_what_balance_md_says() {
		let job = job_change_cost(40);
		assert!((1_000_000..2_000_000).contains(&job), "a job at 40 costs {job}");
		assert!(BANK_TAB_PRICE.windows(2).all(|w| w[1] > w[0]), "each tab dearer than the last");
		assert_eq!(bank_tab_price(1), Some(3_000));
		assert_eq!(bank_tab_price(7), Some(12_000_000));
		assert_eq!(bank_tab_price(8), None);
		assert_eq!(bank_tab_price(0), None);
		assert_eq!(BANK_TAB_PRICE.len() as u32 + 1, realm_store::types::limits::BANK_TABS_MAX);
	}

	#[test]
	fn the_fare_grows_with_the_field_and_the_ring() {
		assert!(travel_cost(5, 0) > travel_cost(1, 0));
		assert!(travel_cost(2, 2) > travel_cost(2, 1) && travel_cost(2, 1) > travel_cost(2, 0));
		assert_eq!(travel_cost(0, 0), TRAVEL_MIN);
	}
}
