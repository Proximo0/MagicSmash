//! realm-soak: bots through the whole stack (gateway, town, field hosts, store) for a time, then a check of the
//! store. One summary line; exits 1 if a bot saw the store differ from what the gateway reported, a bot hit an
//! error, or `verify` found a problem.
//!
//! `realm-soak --bots=40 --secs=7200 --fields=0,1,2,3,4,5 --monsters=3000 --threads=1 --db=/tmp/soak.db`

use realm_gateway::bot::PlayOpts;
use realm_gateway::harness::{run_soak, SoakOpts};

fn die(msg: &str) -> ! {
    eprintln!("realm-soak: {msg}");
    std::process::exit(2);
}

fn main() {
    let mut o = SoakOpts { progress_secs: 60, ..SoakOpts::default() };
    let mut play = PlayOpts::default();
    for arg in std::env::args().skip(1) {
        let (k, v) = arg.split_once('=').unwrap_or((arg.as_str(), ""));
        let num = |v: &str| v.parse::<u64>().unwrap_or_else(|_| die(&format!("bad value in {arg}")));
        match k {
            "--bots" => o.bots = num(v) as u32,
            "--secs" => o.secs = num(v),
            "--fields" => o.fields = v.split(',').map(|f| num(f) as u8).collect(),
            "--monsters" => o.monsters = num(v) as u32,
            "--threads" => o.threads = num(v).max(1) as usize,
            "--db" => o.db = Some(v.into()),
            "--seed" => o.seed = num(v),
            "--progress" => o.progress_secs = num(v),
            "--fast" => o.fast = true,
            "--tls" => o.tls = true,
            "--fight-secs" => play.fight_ticks = num(v) as u32 * 20,
            "--max-secs" => play.max_ticks = num(v) as u32 * 20,
            "--help" | "-h" => {
                println!("realm-soak [--bots=8] [--secs=60] [--fields=0,1,2] [--monsters=1500] [--threads=1] [--db=PATH] [--seed=1] [--progress=60] [--fast] [--fight-secs=20] [--max-secs=240] [--tls (the gateway and the bots over TLS)]");
                return;
            }
            _ => die(&format!("unknown flag {arg}")),
        }
    }
    if o.fields.is_empty() || o.fields.iter().any(|&f| f > 5) {
        die("--fields are 0..5");
    }
    o.play = play;
    match run_soak(&o) {
        Ok(r) => {
            for e in r.stats.errors.iter().take(10) {
                eprintln!("realm-soak: {e}");
            }
            println!("{}", r.line());
            std::process::exit(if r.ok() { 0 } else { 1 });
        }
        Err(e) => die(&e),
    }
}
