//! realm-world: the world's proof at any length (job W2, `docs/realm/world.md`). A realm of six fields and vaults
//! lives `--days` of its clock in `--secs` of real time with `--bots` bots; one `WORLD ok ...` line.
//!
//! `realm-world --bots=200 --days=7 --secs=7200` is the station's long version (the word `world`): a week in two
//! hours, hosts at 20 Hz.

use realm_gateway::world::week::{run_week, WeekOpts};

fn die(msg: &str) -> ! {
    eprintln!("realm-world: {msg}");
    std::process::exit(2);
}

fn main() {
    let mut o = WeekOpts::default();
    for arg in std::env::args().skip(1) {
        let (k, v) = arg.split_once('=').unwrap_or((arg.as_str(), ""));
        let num = |v: &str| v.parse::<f64>().unwrap_or_else(|_| die(&format!("bad value in {arg}")));
        match k {
            "--bots" => o.bots = num(v) as u32,
            "--days" => o.days = num(v),
            "--secs" => o.secs = num(v),
            "--monsters" => o.monsters = num(v) as u32,
            "--vault-monsters" => o.vault_monsters = num(v) as u32,
            "--tick-us" => o.tick_us = num(v) as u32,
            "--vault-tick-us" => o.vault_tick_us = num(v) as u32,
            "--copy-cap" => o.copies.cap = num(v) as u32,
            "--open-at" => o.copies.open_at = num(v) as u32,
            "--merge-under" => o.copies.merge_under = num(v) as u32,
            "--max-copies" => o.copies.max_copies = num(v) as u32,
            "--merge-grace-ms" => o.copies.merge_grace_ms = num(v) as u64,
            "--realm-cap" => o.realm_cap = num(v) as u32,
            "--vault-max" => o.vault_max = num(v) as u32,
            "--outing-ticks" => o.outing_ticks = num(v) as u32,
            "--recall-secs" => o.recall_secs = num(v),
            "--vault-every" => o.vault_every = num(v) as u64,
            "--no-kill" => o.kill = false,
            "--seed" => o.seed = num(v) as u64,
            "--db" => o.db = Some(v.into()),
            "--progress" => o.progress_secs = num(v) as u64,
            "--tls" => o.tls = true,
            "--help" | "-h" => {
                println!("realm-world [--bots=40] [--days=7] [--secs=40] [--monsters=300] [--vault-monsters=600] [--tick-us=2000] [--vault-tick-us=250] [--copy-cap=8] [--open-at=6] [--merge-under=4] [--max-copies=3] [--merge-grace-ms=500] [--realm-cap=30] [--vault-max=3] [--outing-ticks=400] [--recall-secs=240] [--vault-every=3] [--no-kill] [--seed=7] [--db=PATH] [--progress=SECS] [--tls]");
                return;
            }
            _ => die(&format!("unknown flag {arg}")),
        }
    }
    match run_week(&o) {
        Ok(r) => {
            for e in r.errors.iter().take(10) {
                eprintln!("{e}");
            }
            for m in r.coin_mismatches.iter().take(10) {
                eprintln!("{m}");
            }
            println!("{}", r.line());
            std::process::exit(if r.ok() { 0 } else { 1 });
        }
        Err(e) => die(&e),
    }
}
