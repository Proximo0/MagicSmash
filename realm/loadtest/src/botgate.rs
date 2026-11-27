//! `realm-loadtest bots ...`: the class bots' gates of rules section 13, measured and printed.
//!   bots alone SEEDS MINUTES CLASS_LEVEL      each class alone at the edge of THE FOOL'S ROAD
//!   bots party SEEDS TICKS [FIELD]            a knight, priest, archer and mage holding the middle ring in a tide
//!   bots jobs SEEDS HEROES CLASS_LEVEL TICKS  the two jobs of each class in a crowd
//!   bots tick HEROES MONSTERS TICKS THREADS   the tick (mean, p99 ms) of every field in a tide at its cap
//! Seeds run on `BOT_THREADS` threads (default 2).

use realm_core::bots::{Bot, Plan};
use realm_core::gates::{Outcome, alone, job_crowd, party};
use realm_core::tables::*;
use realm_core::{Config, FIELD, Field, SUB};
use realm_core::{Outing, Sheet};

fn arg(n: usize, d: u64) -> u64 {
    std::env::args().nth(n).map_or(d, |s| s.parse().unwrap_or(d))
}

/// Runs `f(seed)` for seeds 0..n on a few threads, results in seed order.
fn seeds<T: Send>(n: u64, f: impl Fn(u64) -> T + Sync) -> Vec<T> {
    let threads = std::env::var("BOT_THREADS").ok().and_then(|s| s.parse().ok()).unwrap_or(2usize).max(1);
    let mut out: Vec<Option<T>> = (0..n).map(|_| None).collect();
    let next = std::sync::atomic::AtomicU64::new(0);
    let done = std::sync::Mutex::new(&mut out);
    std::thread::scope(|s| {
        for _ in 0..threads {
            s.spawn(|| {
                loop {
                    let k = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    if k >= n {
                        break;
                    }
                    let v = f(k);
                    done.lock().unwrap()[k as usize] = Some(v);
                }
            });
        }
    });
    out.into_iter().map(|v| v.unwrap()).collect()
}

fn summary(label: &str, runs: &[Outcome]) {
    let n = runs.len();
    let undowned = runs.iter().filter(|o| o.downs == 0).count();
    let unfallen = runs.iter().filter(|o| o.fallen == 0).count();
    let kills = runs.iter().map(|o| o.kills).sum::<u64>() / n as u64;
    let draws = runs.iter().map(|o| o.draws).sum::<u32>() / n.max(1) as u32;
    let won: u32 = runs.iter().map(|o| o.won).sum();
    let lost: u32 = runs.iter().map(|o| o.lost).sum();
    let firsts: Vec<u32> = runs.iter().filter_map(|o| o.first_down.map(|t| t / TICK_HZ)).collect();
    println!(
        "{label:<10} never downed {undowned}/{n}  never fallen {unfallen}/{n}  kills/run {kills}  mean draws {draws}  tides won {won} lost {lost}  first downs (s) {firsts:?}"
    );
}

/// The step of a field with `heroes` bot heroes and `monsters` monsters, a tide on from the start and the first
/// `ticks / 3` ticks left to fill up; the mean and p99 of the rest, in milliseconds.
fn tick_cost(field: u8, heroes: u32, monsters: u32, ticks: u32, threads: usize) -> (f64, f64) {
    let mut f = Field::open(field, 900 + field as u64, Config { monsters, threads });
    f.set_clock(realm_core::tide_start(field, 0) - 20);
    let mut bots = Vec::new();
    for i in 0..heroes {
        let class = 1 + (i % 5) as u8;
        let sheet = Sheet::bench(class, (i % 4) as u8, FIELDS[field as usize].bottom);
        let n = i as i32;
        let (x, y) = (FIELD / 2 + (n % 40 - 20) * 20 * SUB, FIELD / 2 + (n / 40 - 12) * 20 * SUB);
        let id = f.join(&sheet, &Outing::new(), x, y);
        let mut plan = Plan::crowd(500);
        plan.every = 8;
        bots.push(Bot::new(id, field as u64, plan));
    }
    let mut ms = Vec::new();
    for t in 0..ticks {
        let inputs: Vec<u16> = bots.iter_mut().map(|b| b.act(&f)).collect();
        let at = std::time::Instant::now();
        f.step(&inputs);
        if t >= ticks / 3 {
            ms.push(at.elapsed().as_secs_f64() * 1000.0);
        }
    }
    ms.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let mean = ms.iter().sum::<f64>() / ms.len() as f64;
    (mean, ms[ms.len() * 99 / 100])
}

pub fn run() {
    match std::env::args().nth(2).as_deref() {
        Some("alone") => {
            let (n, minutes, level) = (arg(3, 10), arg(4, 10) as u32, arg(5, 1) as u8);
            println!("alone at the edge of THE FOOL'S ROAD, class level {level}, {minutes} min, {n} seeds");
            let classes = if level < SKILL1_LEVEL { 0..1u8 } else { 0..6u8 };
            for class in classes {
                let runs = seeds(n, |s| alone(class, level, s, minutes));
                summary(CLASSES[class as usize].name, &runs);
            }
        }
        Some("party") => {
            let (n, ticks) = (arg(3, 10), arg(4, 6_000) as u32);
            let fields: Vec<u8> = match std::env::args().nth(5) {
                Some(s) => vec![s.parse().unwrap_or(0)],
                None => (0..6).collect(),
            };
            for field in fields {
                let lead = arg(6, 100) as u32;
                let runs = seeds(n, |s| party(field, s, ticks, lead));
                summary(FIELDS[field as usize].name, &runs);
            }
        }
        Some("tick") => {
            let (heroes, monsters, ticks, threads) = (arg(3, 1_000) as u32, arg(4, 20_000) as u32, arg(5, 900) as u32, arg(6, 4) as usize);
            for field in 0..6u8 {
                let (mean, p99) = tick_cost(field, heroes, monsters, ticks, threads);
                println!("{:<18} {heroes}x{monsters} {threads} threads, tide: tick {mean:.2} ms mean, {p99:.2} ms p99", FIELDS[field as usize].name);
            }
        }
        Some("jobs") => {
            let (n, heroes, level, ticks) = (arg(3, 3), arg(4, 100) as u32, arg(5, 50) as u8, arg(6, 3_000) as u32);
            let mut sum = vec![(0u32, 0u64); JOBS.len()];
            for rows in seeds(n, |s| job_crowd(s, heroes, level, ticks)) {
                for (j, c, m) in rows {
                    sum[j as usize].0 += c;
                    sum[j as usize].1 += m * c as u64;
                }
            }
            let mean = |j: usize| sum[j].1.checked_div(sum[j].0 as u64).unwrap_or(0);
            for c in 1..6usize {
                let jobs: Vec<usize> = (0..JOBS.len()).filter(|&j| JOBS[j].class as usize == c).collect();
                let (a, b) = (mean(jobs[0]), mean(jobs[1]));
                let gap = (a.max(b) - a.min(b)) * 100 / a.max(b).max(1);
                println!("{:<8} {:<13} {a:>9}   {:<13} {b:>9}   gap {gap}%", CLASSES[c].name, JOBS[jobs[0]].name, JOBS[jobs[1]].name);
            }
        }
        _ => eprintln!("bots alone SEEDS MINUTES CLASS_LEVEL | party SEEDS TICKS [FIELD [LEAD]] | jobs SEEDS HEROES CLASS_LEVEL TICKS"),
    }
}
