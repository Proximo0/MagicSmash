//! Test support for the wire fuzz tests: a counting allocator (the biggest single allocation per thread), a seeded
//! xorshift generator and the mutations. `WIRE_FUZZ_ITERS` (default 20000) sets the iterations, `WIRE_FUZZ_SEED` the seed.

use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;

struct Probe;

thread_local! {
    static BIGGEST: Cell<usize> = const { Cell::new(0) };
}

fn note(n: usize) {
    let _ = BIGGEST.try_with(|b| b.set(b.get().max(n)));
}

unsafe impl GlobalAlloc for Probe {
    unsafe fn alloc(&self, l: Layout) -> *mut u8 {
        note(l.size());
        unsafe { System.alloc(l) }
    }
    unsafe fn alloc_zeroed(&self, l: Layout) -> *mut u8 {
        note(l.size());
        unsafe { System.alloc_zeroed(l) }
    }
    unsafe fn realloc(&self, p: *mut u8, l: Layout, n: usize) -> *mut u8 {
        note(n);
        unsafe { System.realloc(p, l, n) }
    }
    unsafe fn dealloc(&self, p: *mut u8, l: Layout) {
        unsafe { System.dealloc(p, l) }
    }
}

#[global_allocator]
static PROBE: Probe = Probe;

/// Forget the biggest allocation so far.
pub fn reset() {
    BIGGEST.with(|c| c.set(0));
}

/// The biggest single allocation since `reset`.
pub fn biggest() -> usize {
    BIGGEST.with(|c| c.get())
}

pub fn iters() -> usize {
    std::env::var("WIRE_FUZZ_ITERS").ok().and_then(|v| v.parse().ok()).unwrap_or(20_000)
}

pub fn seed() -> u64 {
    std::env::var("WIRE_FUZZ_SEED").ok().and_then(|v| v.parse().ok()).unwrap_or(0x5EED_CAFE)
}

pub struct Rng(pub u64);

impl Rng {
    pub fn next(&mut self) -> u64 {
        // xorshift64*
        let mut x = self.0 | 1;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
    pub fn below(&mut self, n: usize) -> usize {
        (self.next() % n.max(1) as u64) as usize
    }
    /// 0..max random bytes.
    pub fn bytes(&mut self, max: usize) -> Vec<u8> {
        let n = self.below(max);
        (0..n).map(|_| self.next() as u8).collect()
    }
}

/// A mangled copy of a valid message: truncated, bits flipped, bytes spliced in, a run of 0xFF (a length or count lying
/// as large as it gets), a byte set at random, or flips and a cut.
pub fn mutate(rng: &mut Rng, b: &[u8]) -> Vec<u8> {
    let mut b = b.to_vec();
    match rng.below(6) {
        0 => b.truncate(rng.below(b.len() + 1)),
        1 => {
            for _ in 0..1 + rng.below(4) {
                if !b.is_empty() {
                    let i = rng.below(b.len());
                    b[i] ^= 1 << rng.below(8);
                }
            }
        }
        2 => {
            let at = rng.below(b.len() + 1);
            let extra = rng.bytes(9);
            b.splice(at..at, extra);
        }
        3 => {
            let at = rng.below(b.len() + 1);
            let n = (1 + rng.below(4)).min(b.len() - at);
            b[at..at + n].fill(0xFF);
        }
        4 if !b.is_empty() => {
            let i = rng.below(b.len());
            b[i] = rng.next() as u8;
        }
        _ => {
            if !b.is_empty() {
                let i = rng.below(b.len());
                b[i] ^= 1 << rng.below(8);
            }
            b.truncate(rng.below(b.len() + 1));
        }
    }
    b
}
