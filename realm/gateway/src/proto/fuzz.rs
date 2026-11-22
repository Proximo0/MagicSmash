//! The decoder fuzz: std only, seeded, so CI runs it with the tests. Every decoder on the gateway wire (through
//! `Req::decode`, `Resp::decode` and `read_frame`) is fed random frames, every module's example frames cut short,
//! bit-flipped, with bytes spliced in and with counts blown up. Each must refuse (None / Err) or decode; never panic;
//! never allocate much more than the frame it was given; and what it decodes must encode back to the same bytes.
//!
//! `REALM_FUZZ_CASES=N` runs N cases (default 200 000); `REALM_FUZZ_SEED=S` another seed.

use super::*;
use std::alloc::{GlobalAlloc, Layout, System};
use std::cell::Cell;

/// The system allocator, remembering the largest single allocation each thread asked for.
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

/// The most a decoder may ask for at once: a few times the frame (structs are wider than their bytes, vectors
/// double), plus a little.
fn alloc_cap(frame: usize) -> usize {
    64 * frame + 16 * 1024
}

struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        // splitmix64
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }
    fn below(&mut self, n: usize) -> usize {
        (self.next() % n.max(1) as u64) as usize
    }
    fn bytes(&mut self, n: usize) -> Vec<u8> {
        (0..n).map(|_| self.next() as u8).collect()
    }
}

/// Every module's example frames: (type, body).
fn corpus() -> Vec<(u8, Vec<u8>)> {
    let mut all = vec![base::examples()];
    all.extend(MODULES.iter().map(|m| (m.examples)()));
    let mut out = Vec::new();
    for (reqs, resps) in all {
        out.extend(reqs.iter().map(Req::encode));
        out.extend(resps.iter().map(Resp::encode));
    }
    out
}

/// One frame through both decoders: refuse or decode to something that writes back the same bytes, within the cap.
fn check(t: u8, b: &[u8]) {
    let cap = alloc_cap(b.len() + 5);
    BIGGEST.with(|c| c.set(0));
    let q = Req::decode(t, b);
    let p = Resp::decode(t, b);
    let big = BIGGEST.with(|c| c.get());
    assert!(big <= cap, "type {t:#04x}, {} bytes {:02x?}: a decoder asked for {big} bytes at once", b.len(), b);
    if let Some(q) = q {
        assert_eq!(q.encode(), (t, b.to_vec()), "type {t:#04x} {:02x?} decoded to {q:?}, which writes back differently", b);
    }
    if let Some(p) = p {
        assert_eq!(p.encode(), (t, b.to_vec()), "type {t:#04x} {:02x?} decoded to {p:?}, which writes back differently", b);
    }
}

/// A mangled copy of a valid frame.
fn mutate(rng: &mut Rng, t: u8, b: &[u8]) -> (u8, Vec<u8>) {
    let mut t = t;
    let mut b = b.to_vec();
    match rng.below(6) {
        // cut short
        0 => b.truncate(rng.below(b.len() + 1)),
        // a few bits flipped (the type byte too, now and then)
        1 => {
            for _ in 0..1 + rng.below(4) {
                if b.is_empty() || rng.below(16) == 0 {
                    t ^= 1 << rng.below(8);
                } else {
                    let i = rng.below(b.len());
                    b[i] ^= 1 << rng.below(8);
                }
            }
        }
        // random bytes spliced in
        2 => {
            let at = rng.below(b.len() + 1);
            let k = 1 + rng.below(8);
            let extra = rng.bytes(k);
            b.splice(at..at, extra);
        }
        // a run of 0xFF (a count or a length as big as it gets)
        3 => {
            let at = rng.below(b.len() + 1);
            let n = (1 + rng.below(4)).min(b.len() - at);
            b[at..at + n].fill(0xFF);
        }
        // one byte set to a random value
        4 if !b.is_empty() => {
            let i = rng.below(b.len());
            b[i] = rng.next() as u8;
        }
        // flips and a cut
        _ => {
            if !b.is_empty() {
                let i = rng.below(b.len());
                b[i] ^= 1 << rng.below(8);
            }
            b.truncate(rng.below(b.len() + 1));
        }
    }
    (t, b)
}

#[test]
fn no_decoder_panics_allocates_wildly_or_reads_what_it_cannot_write_back() {
    let cases: usize = std::env::var("REALM_FUZZ_CASES").ok().and_then(|v| v.parse().ok()).unwrap_or(200_000);
    let seed: u64 = std::env::var("REALM_FUZZ_SEED").ok().and_then(|v| v.parse().ok()).unwrap_or(0x5EED_F00D);
    let mut rng = Rng(seed);
    let corpus = corpus();
    for (t, b) in &corpus {
        check(*t, b);
    }
    for _ in 0..cases {
        match rng.below(8) {
            // pure noise on any type byte
            0 => {
                let t = rng.next() as u8;
                let n = rng.below(48);
                let b = rng.bytes(n);
                check(t, &b);
            }
            // noise behind a valid sub-byte prefix
            1 => {
                let (t, b) = &corpus[rng.below(corpus.len())];
                let keep = rng.below(b.len().min(2) + 1);
                let mut v = b[..keep].to_vec();
                let n = rng.below(48);
                v.extend(rng.bytes(n));
                check(*t, &v);
            }
            _ => {
                let (t, b) = &corpus[rng.below(corpus.len())];
                let (t, b) = mutate(&mut rng, *t, b);
                check(t, &b);
            }
        }
    }
}

#[test]
fn frames_from_a_hostile_stream_are_refused_without_a_big_buffer() {
    let mut rng = Rng(7);
    for i in 0..20_000 {
        let mut s = Vec::new();
        // a header that promises much, then a little
        let len: u32 = match i % 3 {
            0 => rng.next() as u32,
            1 => FRAME_MAX as u32,
            _ => rng.below(64) as u32,
        };
        s.extend_from_slice(&len.to_le_bytes());
        let n = rng.below(64);
        s.extend(rng.bytes(n));
        BIGGEST.with(|c| c.set(0));
        let got = read_frame(&mut &s[..]);
        let big = BIGGEST.with(|c| c.get());
        assert!(big <= alloc_cap(s.len()), "a {len} byte header with {n} bytes behind it made read_frame ask for {big} bytes");
        match got {
            Ok(Some((t, tag, body))) => {
                assert!(len as usize >= 5 && body.len() == len as usize - 5);
                assert_eq!(frame(t, tag, &body), s[..len as usize + 4].to_vec());
            }
            Ok(None) | Err(_) => {}
        }
    }
}
