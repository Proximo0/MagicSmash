//! Rolls: what one credited hero gets from one kill, one cache or one chest. Each roll is seeded from the
//! server's secret and the position of the event in the field's output, so a replay gives the same drops.

use crate::cards::*;
use crate::gear::roll_item;
use crate::rng::{mix, Rng};
use crate::tables::*;
use realm_core::tables::{FIELDS, KINDS};
use realm_core::{CHAMPION, ELITE};
use realm_store::{ItemSpec, StackKind};

/// Where an event sits in a field's output, and who is credited. `slot` is the hero's slot in the field.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RollKey {
	pub field_seed: u64,
	pub tick: u32,
	/// The index of the event in that tick's list.
	pub index: u32,
	pub slot: u16,
}

/// What a roll needs to know of the hero and her account.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Credit {
	/// FORTUNE points, GAMBLER'S COIN and the rest: each adds 1% to the chance of an item roll.
	pub luck: u32,
	/// 100, or the account's `drops_percent` while DROPS_REDUCED is set (`reduced_percent`).
	pub drops_percent: u8,
}

impl Credit {
	pub fn plain() -> Credit {
		Credit { luck: 0, drops_percent: 100 }
	}
}

/// The percent of normal drops an account gets (`Account.flags`, `Account.drops_percent`).
pub fn reduced_percent(flags: u64, drops_percent: u8) -> u8 {
	if flags & realm_store::flags::DROPS_REDUCED != 0 { drops_percent.min(100) } else { 100 }
}

/// What gives the roll.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Source {
	/// A `KILL` event: kind, level and flags (`ELITE`, `CHAMPION`).
	Kill { kind: u8, level: u8, flags: u8 },
	/// A tide's `REWARD`: the TIDE CACHE of a won tide in a field.
	TideCache { field: u8, level: u8 },
	/// A field boss's `REWARD`: the BOSS CHEST. `first_kill` is the hero's first kill of this boss.
	BossChest { boss: u8, level: u8, first_kill: bool },
	/// The world boss's `REWARD`: `top` is for the hundred highest contributions.
	WorldChest { level: u8, top: bool },
}

/// Why a drop exists: the store's mint reason and the ledger text of its stacks.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Reason {
	Drop,
	Cache,
	Chest,
}

impl Reason {
	pub fn mint(self) -> &'static str {
		match self {
			Reason::Drop => "drop",
			Reason::Cache => "cache",
			Reason::Chest => "chest",
		}
	}
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum What {
	Item(ItemSpec),
	/// A stack: coin, material, rune, page, key or monster card.
	Stack(StackKind, u64),
}

/// One thing a hero gets. `kept` ones are written to the store at once; the others go into the haul and
/// are banked (or lost to a fall) with it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Found {
	pub what: What,
	pub kept: bool,
	pub reason: Reason,
}

/// A hero's last twelve item-roll ticks (the cap of non-boss item rolls a minute).
#[derive(Clone, Debug, Default)]
pub struct RollGate {
	stamps: [u32; ITEM_ROLLS_PER_MINUTE],
	next: usize,
	used: usize,
}

impl RollGate {
	pub fn new() -> RollGate {
		RollGate::default()
	}
	/// Takes one roll at `tick` if fewer than the cap were taken in the minute before.
	pub fn take(&mut self, tick: u32) -> bool {
		if self.used == ITEM_ROLLS_PER_MINUTE && tick.saturating_sub(self.stamps[self.next]) < ITEM_ROLL_WINDOW_TICKS {
			return false;
		}
		self.stamps[self.next] = tick;
		self.next = (self.next + 1) % ITEM_ROLLS_PER_MINUTE;
		self.used = (self.used + 1).min(ITEM_ROLLS_PER_MINUTE);
		true
	}
}

/// The seed of a roll. `salt` separates the kinds of source at the same event.
pub fn roll_seed(secret: u64, key: &RollKey, salt: u64) -> u64 {
	let a = mix(secret, key.field_seed);
	let b = mix(a, key.tick as u64 | (key.index as u64) << 32);
	mix(mix(b, key.slot as u64), salt)
}

struct Roller {
	rng: Rng,
	pct: u8,
	luck: u32,
	out: Vec<Found>,
}

impl Roller {
	/// A chance of one in `n`; the account's reduced percent thins it further.
	fn one_in(&mut self, n: u32) -> bool {
		self.pass() && self.rng.below(n as u64) == 0
	}
	fn pass(&mut self) -> bool {
		self.pct >= 100 || self.rng.below(100) < self.pct as u64
	}
	/// One in `n`, with luck.
	fn lucky(&mut self, n: u32) -> bool {
		self.pass() && self.rng.below(n as u64 * 100) < (100 + self.luck as u64 * LUCK_PCT_PER_POINT as u64)
	}
	fn stack(&mut self, kind: StackKind, n: u64, kept: bool, reason: Reason) {
		if n > 0 {
			self.out.push(Found { what: What::Stack(kind, n), kept, reason });
		}
	}
	fn item(&mut self, field: u8, level: u8, min: u8, reason: Reason, haul_ok: bool) {
		let spec = roll_item(&mut self.rng, field, level, min);
		let kept = !haul_ok || spec.rarity >= FIRST_KEPT_RARITY;
		self.out.push(Found { what: What::Item(spec), kept, reason });
	}
	fn stat(&mut self) -> u32 {
		self.rng.below(6) as u32
	}
	fn embers(&mut self, range: (u64, u64), level: u8, kept: bool, reason: Reason) {
		let n = self.rng.between(range.0, range.1);
		self.stack(StackKind::material(EMBERS), scaled(n, level), kept, reason);
	}
}

/// Embers and field materials: `n x (100 + 6 x (level - 1))%`, at least one.
pub fn scaled(n: u64, level: u8) -> u64 {
	(n * (100 + EMBER_PCT_PER_LEVEL as u64 * (level.max(1) as u64 - 1)) / 100).max(1)
}

/// Coin of a cache or chest: `base x (100 + 12 x (level - 1))%`.
pub fn power_coin(base: u64, level: u8) -> u64 {
	base * (100 + POWER_PCT_PER_LEVEL as u64 * (level.max(1) as u64 - 1)) / 100
}

/// What one credited hero gets from `src`. `gate` is her item-roll cap; it is used by the non-boss item
/// rolls of kills only. Drops come out in a fixed order.
pub fn roll(secret: u64, key: &RollKey, credit: &Credit, src: &Source, gate: &mut RollGate) -> Vec<Found> {
	let salt = match src {
		Source::Kill { kind, .. } => *kind as u64,
		Source::TideCache { field, .. } => 100 + *field as u64,
		Source::BossChest { boss, .. } => 200 + *boss as u64,
		Source::WorldChest { .. } => 300,
	};
	let mut r = Roller { rng: Rng::new(roll_seed(secret, key, salt)), pct: credit.drops_percent, luck: credit.luck, out: Vec::new() };
	match *src {
		Source::Kill { kind, level, flags } => kill(&mut r, key, gate, kind, level, flags),
		Source::TideCache { field, level } => {
			for _ in 0..TIDE_ITEM_ROLLS {
				if r.pass() {
					r.item(field, level, TIDE_MIN_RARITY, Reason::Cache, false);
				}
			}
			r.embers(EMBER_TIDE, level, true, Reason::Cache);
			r.stack(StackKind::material(FIELD_MATERIAL_BASE + field as u32), scaled(TIDE_FIELD_MATERIAL, level), true, Reason::Cache);
			r.stack(StackKind::COIN, power_coin(TIDE_COIN, level), true, Reason::Cache);
		}
		Source::BossChest { boss, level, first_kill } => {
			let b = &BOSSES[boss as usize % BOSS_COUNT];
			for _ in 0..BOSS_ITEM_ROLLS {
				if r.pass() {
					r.item(b.field, level, BOSS_MIN_RARITY, Reason::Chest, false);
				}
			}
			if r.one_in(CARD_BOSS_ONE_IN) {
				r.stack(StackKind::card(KIND_CARDS + boss as u32), 1, true, Reason::Chest);
			}
			if r.pass() {
				let stat = r.stat();
				r.stack(StackKind::rune(stat, RUNE_BOSS_GRADE), 1, true, Reason::Chest);
			}
			if r.one_in(TROPHY_ONE_IN) {
				r.stack(StackKind::material(TROPHY_BASE + boss as u32), 1, true, Reason::Chest);
			}
			if first_kill {
				r.stack(StackKind::page(b.page as u32), 1, true, Reason::Chest);
			}
			r.embers(EMBER_BOSS, level, true, Reason::Chest);
			r.stack(StackKind::material(FIELD_MATERIAL_BASE + b.field as u32), scaled(BOSS_FIELD_MATERIAL, level), true, Reason::Chest);
			r.stack(StackKind::COIN, power_coin(BOSS_COIN, level), true, Reason::Chest);
		}
		Source::WorldChest { level, top } => {
			let min = if top { WORLD_TOP_MIN_RARITY } else { WORLD_MIN_RARITY };
			if r.pass() {
				r.item(5, level, min, Reason::Chest, false);
			}
			if r.one_in(CARD_BOSS_ONE_IN) {
				r.stack(StackKind::card(KIND_CARDS + WORLD_BOSS as u32), 1, true, Reason::Chest);
			}
			if r.one_in(TROPHY_ONE_IN) {
				r.stack(StackKind::material(TROPHY_BASE + WORLD_BOSS as u32), 1, true, Reason::Chest);
			}
			r.embers(EMBER_WORLD, level, true, Reason::Chest);
			r.stack(StackKind::COIN, power_coin(WORLD_COIN, level), true, Reason::Chest);
		}
	}
	r.out
}

fn kill(r: &mut Roller, key: &RollKey, gate: &mut RollGate, kind: u8, level: u8, flags: u8) {
	let k = &KINDS[kind as usize % KINDS.len()];
	let field = k.field;
	let champion = flags & CHAMPION != 0;
	let elite = flags & ELITE != 0 && !champion;
	// the item roll
	let hit = if champion {
		r.pass()
	} else if elite {
		r.lucky(ELITE_ITEM_ONE_IN)
	} else {
		r.lucky(MONSTER_ITEM_ONE_IN)
	};
	if hit && gate.take(key.tick) {
		let min = if champion { CHAMPION_MIN_RARITY } else { COMMON };
		r.item(field, level, min, Reason::Drop, true);
	}
	// the monster card of its kind
	if r.one_in(if champion { CARD_CHAMPION_ONE_IN } else { CARD_KIND_ONE_IN }) {
		r.stack(StackKind::card(kind as u32), 1, true, Reason::Drop);
	}
	if elite {
		if r.one_in(RUNE_ELITE_ONE_IN) {
			let stat = r.stat();
			r.stack(StackKind::rune(stat, RUNE_ELITE_GRADE), 1, true, Reason::Drop);
		}
		if r.one_in(PAGE_ELITE_ONE_IN) {
			let card = PAGE_FIRST + r.rng.below((PAGE_LAST - PAGE_FIRST + 1) as u64) as u32;
			r.stack(StackKind::page(card), 1, true, Reason::Drop);
		}
		if FIELDS[field as usize].top >= KEY_MIN_FIELD_TOP && r.one_in(KEY_ELITE_ONE_IN) {
			r.stack(StackKind::key(field as u32), 1, true, Reason::Drop);
		}
		if r.one_in(FIELD_MATERIAL_ELITE_ONE_IN) {
			r.stack(StackKind::material(FIELD_MATERIAL_BASE + field as u32), scaled(1, level), false, Reason::Drop);
		}
		if r.pass() {
			r.embers(EMBER_ELITE, level, false, Reason::Drop);
		}
	} else if champion {
		if r.pass() {
			r.embers(EMBER_CHAMPION, level, false, Reason::Drop);
			r.stack(StackKind::material(FIELD_MATERIAL_BASE + field as u32), scaled(FIELD_MATERIAL_CHAMPION, level), false, Reason::Drop);
		}
	} else if r.one_in(EMBER_MONSTER_ONE_IN) {
		r.stack(StackKind::material(EMBERS), scaled(1, level), false, Reason::Drop);
	}
}
