//! Seeded fuzz of the field state reader (`WIRE_FUZZ_ITERS`, default 20000; see probe.rs). The PvP block's is in pvp/codec.rs.

use crate::probe::{biggest, iters, mutate, reset, seed, Rng};
use crate::{Config, Field};

/// A lying length may not make `from_bytes` allocate more than the pool a field of that many bytes could be:
/// the terrain is a fixed cost, so the cap is that plus a multiple of the input.
#[test]
fn a_field_state_round_trips_and_survives_hostile_bytes() {
    let mut rng = Rng(seed() ^ 0xF1E1D);
    let f = Field::new(5, Config { monsters: 40, threads: 1 });
    let good = f.to_bytes();
    let back = Field::from_bytes(&good, 1).expect("a field reads back");
    assert_eq!(back.to_bytes(), good);
    reset();
    let _ = Field::from_bytes(&good, 1);
    let fixed = biggest();
    // Building a terrain is slow, so a field is read a two-hundredth as often as the small codecs.
    for _ in 0..(iters() / 200).max(100) {
        let bad = match rng.below(5) {
            0 => rng.bytes(96),
            _ => mutate(&mut rng, &good),
        };
        reset();
        let _ = Field::from_bytes(&bad, 1);
        assert!(biggest() <= fixed + 64 * bad.len() + 16 * 1024, "{} bytes made from_bytes ask for {} at once (a good state asks {fixed}): {:02x?}", bad.len(), biggest(), &bad[..bad.len().min(64)]);
    }
}
