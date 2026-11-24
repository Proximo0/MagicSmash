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

/// A store that fails under the sim must say how: an outing the store refused or an INTERNAL economy reply fails the
/// run with its count and the first error text (station 24 Nov printed only "outing_failed: 19613").
#[test]
fn store_failures_fail_the_run_with_the_first_error_text() {
    use realm_gateway::economy::sim::Report;
    let mut r = Report::default();
    assert!(r.failures().is_empty());
    r.counters.insert("outing_failed".into(), 3);
    r.first_errors.insert("outing_failed".into(), "day 7: Db(\"database is locked\")".into());
    r.counters.insert("err15".into(), 2);
    r.first_errors.insert("err15".into(), "MarketList: internal error".into());
    let f = r.failures();
    assert!(f.contains(&"outing_failed: 3 (first: day 7: Db(\"database is locked\"))".to_string()), "{f:#?}");
    assert!(f.contains(&"err15: 2 (first: MarketList: internal error)".to_string()), "{f:#?}");
}
