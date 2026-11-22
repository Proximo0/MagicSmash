//! The loot stream: splitmix64, seeded per roll from a server secret and the field's own event position, so a
//! replay of the same field with the same secret gives the same drops, and no client (which lacks the secret)
//! can predict one.

#[derive(Clone, Debug)]
pub struct Rng(u64);

pub fn mix(a: u64, b: u64) -> u64 {
	let mut z = a ^ b.wrapping_add(0x9e37_79b9_7f4a_7c15).wrapping_add(a << 6).wrapping_add(a >> 2);
	z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
	z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
	z ^ (z >> 31)
}

impl Rng {
	pub fn new(seed: u64) -> Rng {
		Rng(seed ^ 0x6c07_8965_d1ce_f00d)
	}
	pub fn next(&mut self) -> u64 {
		self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
		let mut z = self.0;
		z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
		z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
		z ^ (z >> 31)
	}
	/// 0..n (n > 0), from the high bits (no modulo bias worth measuring at these sizes: n < 2^32).
	pub fn below(&mut self, n: u64) -> u64 {
		(((self.next() >> 32) as u128 * n.max(1) as u128) >> 32) as u64
	}
	/// `lo..=hi`
	pub fn between(&mut self, lo: u64, hi: u64) -> u64 {
		lo + self.below(hi - lo + 1)
	}
}
