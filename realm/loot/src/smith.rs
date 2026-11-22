//! The smith: salvage, upgrade, socket, unsocket, reroll and rune fusing. Every operation conserves value or
//! destroys it, never copies it: costs are debited before anything is made, a destroyed item is gone from the
//! store before its replacement exists, and a failed part is refunded.
//!
//! The store has no call that rewrites an item in place, so upgrade and reroll destroy the item and mint its
//! replacement in the same slot in one transaction (a new id). That would launder an item's origin, so the
//! smith refuses items whose origin account is not the hero's own (`Error::Refused`). A store call
//! `ItemRewrite { hero, item, spec }` that keeps `origin_account` and `mint_seq` would remove both limits.

use crate::apply::{request, sub_id};
use crate::gear::{line_value, roll_lines};
use crate::rng::{mix, Rng};
use crate::tables::*;
use realm_store::*;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Cost {
	pub embers: u64,
	pub coin: u64,
}

fn ember() -> StackKind {
	StackKind::material(EMBERS)
}

// ---- the price list

/// Embers a salvaged item gives.
pub fn salvage_embers(spec: &ItemSpec) -> u64 {
	let base = (1 + spec.item_level as u64 / SALVAGE_LEVEL_DIV) * SALVAGE_RARITY_MUL[spec.rarity as usize];
	base * (100 + SALVAGE_PLUS_PCT * spec.plus as u64) / 100
}

/// The cost of the next step, or None at +10.
pub fn upgrade_cost(spec: &ItemSpec) -> Option<Cost> {
	if spec.plus >= PLUS_MAX {
		return None;
	}
	let s = spec.plus as u64 + 1;
	let l = spec.item_level as u64;
	// The coin follows what a hero of the item's level earns an hour (job B1, `sinks.rs`), never below the old price.
	let by_income = crate::sinks::income_per_hour(spec.item_level) * crate::sinks::SMITH_STEP_BP * s * s / 10_000;
	Some(Cost {
		embers: (UPGRADE_EMBER_BASE + l / UPGRADE_EMBER_LEVEL_DIV) * s,
		coin: (UPGRADE_COIN_PER_LEVEL * l * s * s).max(by_income),
	})
}

/// Chance in percent that the next step works.
pub fn upgrade_success_pct(spec: &ItemSpec) -> u32 {
	UPGRADE_SUCCESS_PCT[(spec.plus as usize).min(PLUS_MAX as usize - 1)]
}

pub fn reroll_cost(spec: &ItemSpec) -> Cost {
	let l = spec.item_level as u64;
	let r = spec.rarity as u64 + 1;
	Cost {
		embers: (REROLL_EMBER_BASE + l / REROLL_EMBER_LEVEL_DIV) * r * (10 + spec.plus as u64) / 10,
		coin: REROLL_COIN_PER_LEVEL * l * r,
	}
}

pub fn socket_coin(spec: &ItemSpec) -> u64 {
	SOCKET_COIN_PER_LEVEL * spec.item_level as u64
}
pub fn unsocket_coin(spec: &ItemSpec) -> u64 {
	UNSOCKET_COIN_PER_LEVEL * spec.item_level as u64
}
/// Coin to fuse three runes of `grade` (1 or 2).
pub fn fuse_coin(grade: u32) -> u64 {
	FUSE_COIN[grade as usize - 1]
}

// ---- results

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Salvaged {
	pub embers: u64,
	/// Cards and runes that were in its sockets and are back in the bag.
	pub returned: Vec<StackKind>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Upgraded {
	pub success: bool,
	/// The item now (a new id when it was rewritten, the same one when the step failed).
	pub item: ItemId,
	pub plus: u8,
	pub spent: Cost,
}

pub struct Smith<'a, S: Store + ?Sized> {
	pub store: &'a S,
	/// The server's secret (the same one that seeds drops).
	pub secret: u64,
}

fn inv(s: &str) -> Error {
	Error::Invalid(s.into())
}

impl<'a, S: Store + ?Sized> Smith<'a, S> {
	pub fn new(store: &'a S, secret: u64) -> Smith<'a, S> {
		Smith { store, secret }
	}

	fn hero_of(&self, hero: HeroId) -> Result<Hero> {
		match self.store.hero(hero)? {
			Some(h) if h.deleted_at.is_none() => Ok(h),
			Some(_) => Err(Error::Deleted),
			None => Err(Error::Missing(format!("hero {hero}"))),
		}
	}

	/// An item in the hero's bag (or on her, when `worn_ok`).
	fn carried(&self, hero: HeroId, item: ItemId, worn_ok: bool) -> Result<Item> {
		let it = self.store.item(item)?.ok_or_else(|| Error::Missing(format!("item {item}")))?;
		let ok = it.place.owner == hero && (it.place.kind == PlaceKind::Bag || (worn_ok && it.place.kind == PlaceKind::Worn));
		if ok { Ok(it) } else { Err(Error::NotYours(format!("item {item} is not carried by hero {hero}"))) }
	}

	fn have(&self, hero: HeroId, kind: StackKind) -> Result<u64> {
		self.store.stack(Owner::bag(hero), kind)
	}

	fn need(&self, hero: HeroId, want: &[(StackKind, u64)]) -> Result<()> {
		for (k, n) in want {
			let have = self.have(hero, *k)?;
			if have < *n {
				return Err(Error::Insufficient { kind: *k, have, want: *n });
			}
		}
		Ok(())
	}

	fn refund(&self, m: Meta, part: u32, hero: HeroId, kind: StackKind, n: u64) {
		if n > 0 {
			let _ = self.store.submit(request(m, part, Cmd::StackCredit { to: Owner::bag(hero), kind, count: n, minted: false, reason: "refund".into() }));
		}
	}

	/// Debits every cost in one transaction; if any part fails the rest are refunded and the error returned.
	fn debit_all(&self, m: Meta, part: u32, hero: HeroId, costs: &[(StackKind, u64)], reason: &str) -> Result<()> {
		let costs: Vec<(StackKind, u64)> = costs.iter().copied().filter(|c| c.1 > 0).collect();
		if costs.is_empty() {
			return Ok(());
		}
		let reqs = costs
			.iter()
			.enumerate()
			.map(|(i, (k, n))| request(m, part + i as u32, Cmd::StackDebit { from: Owner::bag(hero), kind: *k, count: *n, reason: reason.into() }))
			.collect();
		let rs = self.store.submit_batch(reqs);
		if let Some(e) = rs.iter().find_map(|r| r.as_ref().err().cloned()) {
			for (i, r) in rs.iter().enumerate() {
				if r.is_ok() {
					self.refund(m, part + 100 + i as u32, hero, costs[i].0, costs[i].1);
				}
			}
			return Err(e);
		}
		Ok(())
	}

	/// Empties every socket of an item into the bag; returns what came out.
	fn empty_sockets(&self, m: Meta, part: u32, hero: HeroId, it: &Item) -> Result<Vec<(u8, StackKind)>> {
		let held: Vec<(u8, StackKind)> = it.socketed.iter().enumerate().filter_map(|(i, s)| s.map(|k| (i as u8, k))).collect();
		let reqs = held.iter().map(|(i, _)| request(m, part + *i as u32, Cmd::Unsocket { hero, item: it.id, socket: *i })).collect::<Vec<_>>();
		if reqs.is_empty() {
			return Ok(held);
		}
		for r in self.store.submit_batch(reqs) {
			r?;
		}
		Ok(held)
	}

	/// Destroys an item (its sockets already emptied) and gives embers.
	pub fn salvage(&self, m: Meta, hero: HeroId, item: ItemId) -> Result<Salvaged> {
		self.hero_of(hero)?;
		let it = self.carried(hero, item, false)?;
		let embers = salvage_embers(&it.spec);
		let held = self.empty_sockets(m, 0, hero, &it)?;
		self.store.run(Meta { id: sub_id(m.id, 10), actor: 0, now: m.now }, Cmd::SellItem { hero, item, price: 0 })?;
		self.store.run(
			Meta { id: sub_id(m.id, 11), actor: 0, now: m.now },
			Cmd::StackCredit { to: Owner::bag(hero), kind: ember(), count: embers, minted: false, reason: "salvage".into() },
		)?;
		Ok(Salvaged { embers, returned: held.into_iter().map(|(_, k)| k).collect() })
	}

	/// Raises an item one step (+1 to +10). Steps above +5 can fail: the embers are lost, the item never is.
	pub fn upgrade(&self, m: Meta, hero: HeroId, item: ItemId) -> Result<Upgraded> {
		let h = self.hero_of(hero)?;
		let it = self.carried(hero, item, false)?;
		let cost = upgrade_cost(&it.spec).ok_or_else(|| inv("already +10"))?;
		self.need(hero, &[(ember(), cost.embers), (StackKind::COIN, cost.coin)])?;
		let step = it.spec.plus + 1;
		let mut rng = Rng::new(mix(self.secret, m.id as u64 ^ (m.id >> 64) as u64));
		let works = step <= UPGRADE_SAFE_STEPS || rng.below(100) < upgrade_success_pct(&it.spec) as u64;
		if !works {
			self.debit_all(m, 20, hero, &[(ember(), cost.embers)], "smith fail")?;
			return Ok(Upgraded { success: false, item, plus: it.spec.plus, spent: Cost { embers: cost.embers, coin: 0 } });
		}
		if it.origin_account != h.account {
			return Err(Error::Refused);
		}
		let mut spec = it.spec.clone();
		spec.plus = step;
		let new = self.rewrite(m, hero, &it, spec, &[(ember(), cost.embers), (StackKind::COIN, cost.coin)], "upgrade")?;
		Ok(Upgraded { success: true, item: new, plus: step, spent: cost })
	}

	/// Draws the item's lines again (same rarity, level, base and plus).
	pub fn reroll(&self, m: Meta, hero: HeroId, item: ItemId) -> Result<ItemId> {
		let h = self.hero_of(hero)?;
		let it = self.carried(hero, item, false)?;
		if it.origin_account != h.account {
			return Err(Error::Refused);
		}
		let cost = reroll_cost(&it.spec);
		self.need(hero, &[(ember(), cost.embers), (StackKind::COIN, cost.coin)])?;
		let mut rng = Rng::new(mix(self.secret, (m.id as u64 ^ (m.id >> 64) as u64) ^ 0x7265_726f_6c6c));
		let mut spec = it.spec.clone();
		spec.lines = roll_lines(&mut rng, spec.lines.len(), line_value(spec.item_level, spec.rarity));
		self.rewrite(m, hero, &it, spec, &[(ember(), cost.embers), (StackKind::COIN, cost.coin)], "reroll")
	}

	/// Costs, then: sockets emptied, the old item destroyed, the new one made in its slot, sockets refilled.
	fn rewrite(&self, m: Meta, hero: HeroId, old: &Item, new: ItemSpec, costs: &[(StackKind, u64)], why: &str) -> Result<ItemId> {
		self.debit_all(m, 30, hero, costs, why)?;
		let held = match self.empty_sockets(m, 40, hero, old) {
			Ok(h) => h,
			Err(e) => {
				for (k, n) in costs {
					self.refund(m, 50 + k.0, hero, *k, *n);
				}
				return Err(e);
			}
		};
		let slot = old.place.slot;
		let rs = self.store.submit_batch(vec![
			request(m, 60, Cmd::SellItem { hero, item: old.id, price: 0 }),
			request(m, 61, Cmd::Mint { to: Dest::at(PlaceKind::Bag, hero, 0, slot), spec: new, reason: "grant".into() }),
		]);
		let mut rs = rs.into_iter();
		let sold = rs.next().unwrap();
		let minted = rs.next().unwrap();
		match (sold, minted) {
			(Ok(_), Ok(Reply::Item(id, _))) => {
				let socks: Vec<Request> = held
					.iter()
					.map(|(i, k)| request(m, 70 + *i as u32, Cmd::Socket { hero, item: id, socket: *i, kind: *k }))
					.collect();
				if !socks.is_empty() {
					// a refused refill leaves the card or rune in the bag: nothing is lost
					let _ = self.store.submit_batch(socks);
				}
				Ok(id)
			}
			(Err(e), _) => {
				for (k, n) in costs {
					self.refund(m, 50 + k.0, hero, *k, *n);
				}
				Err(e)
			}
			(Ok(_), Err(e)) => Err(e),
			(Ok(_), Ok(_)) => Err(inv("unexpected reply")),
		}
	}

	/// Puts a card or rune from the bag into an empty socket for coin.
	pub fn socket(&self, m: Meta, hero: HeroId, item: ItemId, socket: u8, kind: StackKind) -> Result<u64> {
		self.hero_of(hero)?;
		let it = self.carried(hero, item, true)?;
		let coin = socket_coin(&it.spec);
		self.need(hero, &[(StackKind::COIN, coin)])?;
		self.with_coin(m, hero, coin, "socket", Cmd::Socket { hero, item, socket, kind })?;
		Ok(coin)
	}

	/// Takes the card or rune out of a socket (back into the bag) for coin.
	pub fn unsocket(&self, m: Meta, hero: HeroId, item: ItemId, socket: u8) -> Result<u64> {
		self.hero_of(hero)?;
		let it = self.carried(hero, item, true)?;
		let coin = unsocket_coin(&it.spec);
		self.need(hero, &[(StackKind::COIN, coin)])?;
		self.with_coin(m, hero, coin, "unsocket", Cmd::Unsocket { hero, item, socket })?;
		Ok(coin)
	}

	fn with_coin(&self, m: Meta, hero: HeroId, coin: u64, why: &str, cmd: Cmd) -> Result<()> {
		self.debit_all(m, 0, hero, &[(StackKind::COIN, coin)], why)?;
		if let Err(e) = self.store.submit(request(m, 5, cmd)) {
			self.refund(m, 6, hero, StackKind::COIN, coin);
			return Err(e);
		}
		Ok(())
	}

	/// Three runes of a grade into one of the next, for coin. Returns the new rune's kind.
	pub fn fuse(&self, m: Meta, hero: HeroId, stat: u32, grade: u32) -> Result<StackKind> {
		self.hero_of(hero)?;
		if stat >= 6 || !(1..=2).contains(&grade) {
			return Err(inv("fuse: stat 0..6, grade 1 or 2"));
		}
		let from = StackKind::rune(stat, grade);
		let to = StackKind::rune(stat, grade + 1);
		let coin = fuse_coin(grade);
		self.need(hero, &[(from, FUSE_COUNT), (StackKind::COIN, coin)])?;
		self.debit_all(m, 0, hero, &[(from, FUSE_COUNT), (StackKind::COIN, coin)], "fuse")?;
		let r = self.store.submit(request(m, 5, Cmd::StackCredit { to: Owner::bag(hero), kind: to, count: 1, minted: false, reason: "fuse".into() }));
		if let Err(e) = r {
			self.refund(m, 6, hero, from, FUSE_COUNT);
			self.refund(m, 7, hero, StackKind::COIN, coin);
			return Err(e);
		}
		Ok(to)
	}
}
