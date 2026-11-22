//! `realm-economy`: the economy simulation (bots on the real store and economy door, game days accelerated).
//!
//! `realm-economy --bots=2000 --days=90 [--seed=N] [--threads=N] [--farms=N] [--db=PATH] [--quiet]`
//! Prints the coin supply curve, the coin flows, the price bands and the guards, then one `ECONOMY ok ...` line
//! (or `ECONOMY failed` and each reason, exit 1).

use realm_gateway::economy::sim::{run, Config};

fn main() {
    let mut cfg = Config { bots: 2000, days: 90, seed: 1, threads: 1, db: std::env::temp_dir().join(format!("realm-economy-{}.db", std::process::id())), farms: 20, quiet: false };
    for a in std::env::args().skip(1) {
        let (k, v) = a.split_once('=').unwrap_or((a.as_str(), ""));
        match k {
            "--bots" => cfg.bots = v.parse().expect("--bots=N"),
            "--days" => cfg.days = v.parse().expect("--days=N"),
            "--seed" => cfg.seed = v.parse().expect("--seed=N"),
            "--threads" => cfg.threads = v.parse().expect("--threads=N"),
            "--farms" => cfg.farms = v.parse().expect("--farms=N"),
            "--db" => cfg.db = v.into(),
            "--quiet" => cfg.quiet = true,
            _ => {
                eprintln!("unknown flag {a}");
                std::process::exit(2);
            }
        }
    }
    let r = run(&cfg);
    r.print();
    let f = r.failures();
    for s in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{}{s}", cfg.db.display()));
    }
    if f.is_empty() {
        let c = &r.counters;
        println!(
            "ECONOMY ok bots={} days={} secs={:.0} sales={} tax={} coin_per_bot={} listings={} trades={} letters={} refused={}",
            r.bots,
            r.days,
            r.secs,
            r.totals.sales,
            r.totals.tax,
            r.supply.last().map_or(0, |s| s.per_bot),
            r.totals.listed,
            r.totals.trades,
            r.totals.letters,
            c.get("refused_ok").copied().unwrap_or(0)
        );
    } else {
        for s in &f {
            println!("  FAIL {s}");
        }
        println!("ECONOMY failed {} problems", f.len());
        std::process::exit(1);
    }
}
