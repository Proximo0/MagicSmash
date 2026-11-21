//! A small seeded generator (splitmix64) for tests, the fuzz and the bench.

#[derive(Clone, Debug)]
pub struct Rng(u64);

impl Rng {
	pub fn new(seed: u64) -> Rng {
		Rng(seed ^ 0x9e37_79b9_7f4a_7c15)
	}
	pub fn next(&mut self) -> u64 {
		self.0 = self.0.wrapping_add(0x9e37_79b9_7f4a_7c15);
		let mut z = self.0;
		z = (z ^ (z >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
		z = (z ^ (z >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
		z ^ (z >> 31)
	}
	/// 0..n (n > 0)
	pub fn below(&mut self, n: u64) -> u64 {
		self.next() % n.max(1)
	}
	pub fn chance(&mut self, percent: u64) -> bool {
		self.below(100) < percent
	}
	pub fn pick<'a, T>(&mut self, v: &'a [T]) -> Option<&'a T> {
		if v.is_empty() { None } else { Some(&v[self.below(v.len() as u64) as usize]) }
	}
	pub fn u128(&mut self) -> u128 {
		((self.next() as u128) << 64) | self.next() as u128
	}
}
