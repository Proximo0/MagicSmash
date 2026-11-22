//! Gear: bases, rarity, lines, sockets (rules section 9) and what an item is worth to a sheet.

use crate::cards::card_rule;
use crate::rng::Rng;
use crate::tables::*;
use realm_store::{ItemSpec, StackClass, StackKind};

/// A base id: `slot x 100 + tier x 10 + variant`.
pub fn base_id(slot: u8, tier: u8, variant: u8) -> u32 {
	slot as u32 * 100 + tier as u32 * 10 + variant as u32
}

/// "ASHEN LONGBOW".
pub fn base_name(base: u32) -> String {
	let (slot, tier, variant) = ((base / 100) as usize, ((base / 10) % 10) as usize, (base % 10) as usize);
	match (BASE_TIER_NAMES.get(tier), BASE_VARIANTS.get(slot).and_then(|v| v.get(variant))) {
		(Some(t), Some(v)) => format!("{t} {v}"),
		_ => format!("BASE {base}"),
	}
}

/// Points of one line at an item level before the rarity step: `1 + level / 4`.
pub fn line_points(item_level: u16) -> u32 {
	1 + item_level as u32 / 4
}

/// Points of one line of a fresh item.
pub fn line_value(item_level: u16, rarity: u8) -> u16 {
	(line_points(item_level) * RARITY_STEP_PCT[rarity as usize] / 100) as u16
}

/// Rolls a rarity of at least `min` (the tiers below are cut and the rest renormalised).
pub fn roll_rarity(rng: &mut Rng, min: u8) -> u8 {
	let total: u32 = RARITY_PER_MILLE[min as usize..].iter().sum();
	let mut pick = rng.below(total as u64) as u32;
	for r in min as usize..5 {
		if pick < RARITY_PER_MILLE[r] {
			return r as u8;
		}
		pick -= RARITY_PER_MILLE[r];
	}
	RELIC
}

/// `n` different stats out of the six.
pub fn roll_lines(rng: &mut Rng, n: usize, points: u16) -> Vec<(u8, u16)> {
	let mut pool: Vec<u8> = (0..6).collect();
	let mut out = Vec::with_capacity(n);
	for _ in 0..n.min(6) {
		let i = rng.below(pool.len() as u64) as usize;
		out.push((pool.remove(i), points));
	}
	out
}

/// A new item of a field's tier of base at an item level and rarity.
pub fn make_item(rng: &mut Rng, field: u8, item_level: u8, rarity: u8) -> ItemSpec {
	let level = item_level.clamp(1, MAX_ITEM_LEVEL) as u16;
	let total: u32 = SLOT_WEIGHT.iter().sum();
	let mut pick = rng.below(total as u64) as u32;
	let mut slot = 0u8;
	for (s, w) in SLOT_WEIGHT.iter().enumerate() {
		if pick < *w {
			slot = s as u8;
			break;
		}
		pick -= *w;
	}
	let variants = BASE_VARIANTS[slot as usize].len() as u64;
	let variant = rng.below(variants) as u8;
	let lines = roll_lines(rng, RARITY_LINES[rarity as usize], line_value(level, rarity));
	ItemSpec {
		base: base_id(slot, field.min(5), variant),
		gear_slot: slot,
		item_level: level,
		rarity,
		lines,
		sockets: RARITY_SOCKETS[rarity as usize],
		plus: 0,
		bound: false,
	}
}

/// A rolled item of `min` or better.
pub fn roll_item(rng: &mut Rng, field: u8, item_level: u8, min: u8) -> ItemSpec {
	let r = roll_rarity(rng, min);
	make_item(rng, field, item_level, r)
}

/// What a socketed card or rune adds: (stat, points).
pub fn socket_points(kind: StackKind) -> Option<(u8, u16)> {
	match kind.class()? {
		StackClass::Rune => {
			let stat = (kind.0 - 2000) / 10;
			let grade = (kind.0 - 2000) % 10;
			Some((stat as u8, *RUNE_POINTS.get((grade as usize).checked_sub(1)?)?))
		}
		StackClass::Card => card_rule(kind.0 - 5000).map(|r| (r.stat, r.points)),
		_ => None,
	}
}

/// An item's points per stat in hundredths: its lines raised 3% a plus, and what sits in its sockets. Total over
/// anything a stored row may hold: a line or socket on a stat past the six adds nothing, a plus counts at most
/// `PLUS_MAX`, a socketed kind that is no rune or known card adds nothing (`socket_points`).
pub fn item_hundredths(spec: &ItemSpec, socketed: &[Option<StackKind>]) -> [u32; 6] {
	let mut out = [0u32; 6];
	let plus = spec.plus.min(PLUS_MAX) as u32;
	for (stat, pts) in &spec.lines {
		if let Some(o) = out.get_mut(*stat as usize) {
			*o = o.saturating_add(*pts as u32 * (100 + PLUS_PCT * plus));
		}
	}
	for k in socketed.iter().flatten() {
		if let Some((stat, pts)) = socket_points(*k) {
			if let Some(o) = out.get_mut(stat as usize) {
				*o = o.saturating_add(pts as u32 * 100);
			}
		}
	}
	out
}

/// The `gear` array of a `Sheet`: the worn items summed in hundredths, then rounded to whole points.
pub fn gear_stats(worn: &[(ItemSpec, Vec<Option<StackKind>>)]) -> [u16; 6] {
	let mut h = [0u32; 6];
	for (spec, soc) in worn {
		let one = item_hundredths(spec, soc);
		for s in 0..6 {
			h[s] = h[s].saturating_add(one[s]);
		}
	}
	h.map(|v| (v.saturating_add(50) / 100).min(u16::MAX as u32) as u16)
}
