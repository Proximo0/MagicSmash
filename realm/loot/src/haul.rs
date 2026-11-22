//! The loot half of a hero's haul: COMMON and UNCOMMON items and materials not yet banked (rules section 7).

use crate::rng::Rng;
use crate::roll::{Found, What};
use realm_store::{ItemSpec, OutingDelta, StackKind};
use std::collections::BTreeMap;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Haul {
	pub items: Vec<ItemSpec>,
	pub stacks: BTreeMap<u32, u64>,
}

impl Haul {
	pub fn new() -> Haul {
		Haul::default()
	}
	pub fn add_item(&mut self, spec: ItemSpec) {
		self.items.push(spec);
	}
	pub fn add_stack(&mut self, kind: StackKind, n: u64) {
		let e = self.stacks.entry(kind.0).or_insert(0);
		*e = e.saturating_add(n);
	}
	/// Takes in a drop that is not kept; returns it back when it is (to be written to the store at once).
	pub fn take(&mut self, f: Found) -> Option<Found> {
		if f.kept {
			return Some(f);
		}
		match f.what {
			What::Item(s) => self.add_item(s),
			What::Stack(k, n) => self.add_stack(k, n),
		}
		None
	}
	pub fn is_empty(&self) -> bool {
		self.items.is_empty() && self.stacks.is_empty()
	}
	/// A fall: half the items (rounded down, the server picks which) and half of each material (rounded down)
	/// are lost. Returns what was lost.
	pub fn fall(&mut self, rng: &mut Rng) -> Haul {
		let mut lost = Haul::new();
		let n = self.items.len() / 2;
		for _ in 0..n {
			let i = rng.below(self.items.len() as u64) as usize;
			lost.items.push(self.items.remove(i));
		}
		for (k, v) in self.stacks.iter_mut() {
			let half = *v / 2;
			*v -= half;
			if half > 0 {
				lost.stacks.insert(*k, half);
			}
		}
		self.stacks.retain(|_, v| *v > 0);
		lost
	}
	/// Adds the haul to an outing's delta (the store mints the items and credits the stacks as `haul`).
	pub fn into_delta(self, mut d: OutingDelta) -> OutingDelta {
		d.items.extend(self.items);
		d.stacks.extend(self.stacks.into_iter().map(|(k, v)| (StackKind(k), v)));
		d
	}
}
