//! Crash fuzz seeds the station reported (big run ops=50000 kills=200) failing with "a parcel holding nothing"
//! (and, for a listing, "a listing with more than one entry", which counts entries <> 1). The cause was a
//! clawback that destroyed everything a parcel held in escrow and left the parcel row behind; see
//! `a_clawback_that_empties_a_parcel_ends_it` in tests/parcels.rs. Each run below is the shortest one found that
//! still fails without `parcels::end_if_empty` in the clawback (same kill spacing ops/kills = 250 where kills
//! matter), so the seeds stay covered without the full 50,000-op runs.
mod common;
use realm_store::fuzz::{FuzzConfig, parent};

fn run(seed: u64, ops: u64, kills: u64) {
	let dir = common::scratch().join(format!("fuzz-seed-{seed}-{}", std::process::id()));
	let r = parent(&FuzzConfig { seed, ops, kills, dir: dir.clone(), exe: env!("CARGO_BIN_EXE_realm-store").into(), verbose: false, plunder: false });
	let _ = std::fs::remove_dir_all(&dir);
	assert!(r.problems.is_empty(), "fuzz seed {seed} ops={ops} kills={kills}: {:?}", r.problems);
	// How many armed kill points a run reaches depends on how often this SQLite version calls its progress and
	// commit hooks (33 of 33 on 3.50, 31 of 33 on the release bundled by rusqlite 0.43), so most must land, not all.
	assert!(r.kills * 10 >= kills * 9 && r.kills <= kills, "fuzz seed {seed}: {} of the {kills} kills the run was armed for", r.kills);
}

#[test]
fn fuzz_seed_389451() {
	run(389_451, 3000, 12);
}

#[test]
fn fuzz_seed_621015() {
	run(621_015, 8250, 33);
}

#[test]
fn fuzz_seed_833761() {
	run(833_761, 12_200, 0);
}

#[test]
fn fuzz_seed_922952() {
	run(922_952, 24_400, 0);
}
