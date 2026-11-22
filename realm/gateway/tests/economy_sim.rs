//! The proof of the economy: bots play accelerated game days on the real store and economy door. No price runs
//! away, no item is copied (store verify and the ledger replay agree), the coin supply curve is printed.
//! The quick variant (200 bots, 30 days) runs by default; the full 2,000 x 90 proof is `#[ignore]`d.

use realm_gateway::economy::sim::{run, Config};

fn prove(bots: usize, days: u32, farms: usize, name: &str) {
    let db = std::env::temp_dir().join(format!("realm-economy-{name}-{}.db", std::process::id()));
    let cfg = Config { bots, days, seed: 1, threads: 1, db: db.clone(), farms, quiet: true };
    let r = run(&cfg);
    r.print();
    for s in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{s}", db.display()));
    }
    let f = r.failures();
    assert!(f.is_empty(), "economy failed: {f:#?}");
}

#[test]
fn two_hundred_bots_over_thirty_days_hold_their_prices_and_copy_nothing() {
    prove(200, 30, 4, "quick");
}

// ~340 s: the `economy` station job runs it (`cargo test --release -p realm-gateway -- --ignored`).
#[test]
#[ignore]
fn two_thousand_bots_over_ninety_days_hold_their_prices_and_copy_nothing() {
    prove(2000, 90, 20, "full");
}
