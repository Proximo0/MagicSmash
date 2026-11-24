//! The balance runs of job B1 (`docs/realm/balance.md`), printed as the tables of that document:
//!   balance probe SEEDS MINUTES [L,L,...]     each class alone and in a party of five at chosen class levels
//!   balance career SEEDS PER MINUTES FAST [HOURS]   cohorts of careers 1 to 60 (`career.rs`)
//!   balance gates SEEDS                       the party gate (all six fields) and the jobs gate of rules 13
//! `BOT_THREADS` (default 2) threads.

use crate::career::*;
use realm_core::gates::{Outcome, job_crowd, party};
use realm_core::tables::*;

pub fn threads() -> usize {
    std::env::var("BOT_THREADS").ok().and_then(|s| s.parse().ok()).unwrap_or(2usize).max(1)
}

/// Rates of one class at one level: class XP, kills, downs and falls an hour of play, alone and in a party.
#[derive(Clone, Copy, Debug, Default)]
pub struct Rate {
    pub xp: u64,
    pub kills: u64,
    pub downs: u64,
    pub falls: u64,
    pub coin: u64,
}

pub const TICKS_HOUR: u64 = 3_600 * TICK_HZ as u64;

fn per_hour(p: &Played, ticks: u64) -> Rate {
    Rate {
        xp: p.xp * TICKS_HOUR / ticks,
        kills: p.kills * TICKS_HOUR / ticks,
        downs: p.downs * TICKS_HOUR / ticks,
        falls: p.falls * TICKS_HOUR / ticks,
        coin: (p.kill_coin + p.chest_coin) * TICKS_HOUR / ticks,
    }
}

/// The probe at one level and seed: `[alone, party]` x the five classes (KNIGHT..PALADIN; NOVICEs below 10).
pub fn probe(level: u8, seed: u64, ticks: u32) -> [[Rate; 5]; 2] {
    let mut out = [[Rate::default(); 5]; 2];
    let (field, ring) = Career::place(level);
    let classes = [KNIGHT, MAGE, ARCHER, PRIEST, PALADIN];
    let hero = |k: usize| Career::at_level(k, classes[k], seed % 2 == 1, (k as u64 + seed) as u8 % 4, level, seed);
    let sheets: Vec<_> = (0..5).map(|k| (hero(k).sheet(), 1u64, BANK_KILLS * 2 * (100 + 12 * (level as u32 - 1)) / 100)).collect();
    let alone = Instance { field, seed: 7_000 + seed * 64 + level as u64, clock: probe_clock(field, seed), groups: (0..5).map(|k| Group { members: vec![k], ring_px: ring }).collect() };
    let party = Instance { field, seed: 8_000 + seed * 64 + level as u64, clock: probe_clock(field, seed + 1), groups: vec![Group { members: (0..5).collect(), ring_px: ring }] };
    let both = [alone, party];
    let res = par_map(&both, 2, |inst| run(inst, &sheets, ticks));
    for (m, played) in res.iter().enumerate() {
        for k in 0..5 {
            out[m][k] = per_hour(&played[k], ticks as u64);
        }
    }
    out
}

/// A clock just after one of the field's tides: the next is 25 minutes away (a probe is outside the tide).
fn probe_clock(field: u8, seed: u64) -> u64 {
    realm_core::tide_start(field, 1 + (seed % 3) as u32) + TIDE_LEN as u64 + 20
}

pub const PROBE_LEVELS: [u8; 13] = [1, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60];

/// Probe rates per level (rows) for `seeds` seeds, summed and divided.
pub fn probe_table(levels: &[u8], seeds: u64, ticks: u32) -> Vec<(u8, [[Rate; 5]; 2])> {
    let jobs: Vec<(u8, u64)> = levels.iter().flat_map(|&l| (0..seeds).map(move |s| (l, s))).collect();
    let res = par_map(&jobs, (threads() / 2).max(1), |&(l, s)| probe(l, s, ticks));
    let mut out = Vec::new();
    for (i, &l) in levels.iter().enumerate() {
        let mut sum = [[Rate::default(); 5]; 2];
        for s in 0..seeds as usize {
            let r = &res[i * seeds as usize + s];
            for m in 0..2 {
                for k in 0..5 {
                    let (a, b) = (&mut sum[m][k], &r[m][k]);
                    a.xp += b.xp / seeds;
                    a.kills += b.kills / seeds;
                    a.downs += b.downs;
                    a.falls += b.falls;
                    a.coin += b.coin / seeds;
                }
            }
        }
        out.push((l, sum));
    }
    out
}

fn median(mut v: Vec<u64>) -> u64 {
    v.sort();
    if v.is_empty() { 0 } else { v[v.len() / 2] }
}

pub fn print_probe(rows: &[(u8, [[Rate; 5]; 2])]) {
    let names = ["KNIGHT", "MAGE", "ARCHER", "PRIEST", "PALADIN"];
    for (m, mode) in ["alone", "party of five"].iter().enumerate() {
        println!("class XP an hour, {mode} (kills an hour; downs and falls summed over seeds)");
        println!("{:>5} {:>8} | {}", "level", "median", names.map(|n| format!("{n:>22}")).join(""));
        for (l, r) in rows {
            let med = median(r[m].iter().map(|x| x.xp).collect());
            let cells: Vec<String> = r[m]
                .iter()
                .map(|x| format!("{:>9}{:>+4}% {:>4}k {}/{}", x.xp, pct_off(x.xp, med), x.kills, x.downs, x.falls))
                .collect();
            println!("{l:>5} {med:>8} | {}", cells.join(""));
        }
    }
}

pub fn pct_off(v: u64, med: u64) -> i64 {
    if med == 0 { 0 } else { (v as i64 - med as i64) * 100 / med as i64 }
}

// ---- the class XP table

/// The first levels come at a rate that slows gently: level 2 after a minute, 9 to 10 in four.
pub const EARLY_POWER: f64 = 1.5;

/// Credited hours to reach a class level, the curve of rules 2 made smooth: between two targets (and from level 1
/// to the first, with the same power as the next piece) hours grow as a power of the level.
pub fn target_hours(level: u8) -> f64 {
    let l = level.clamp(1, CLASS_LEVEL_MAX) as f64;
    if l <= 1.0 {
        return 0.0;
    }
    let pts: Vec<(f64, f64)> = CURVE.iter().map(|&(a, h)| (a as f64, h)).collect();
    let q = |a: (f64, f64), b: (f64, f64)| (b.1 / a.1).ln() / (b.0 / a.0).ln();
    if l <= pts[0].0 {
        // From 1 (no time) to the first target: hours x ((l - 1) / (first - 1)) ^ `EARLY_POWER`.
        return pts[0].1 * ((l - 1.0) / (pts[0].0 - 1.0)).powf(EARLY_POWER);
    }
    for w in pts.windows(2) {
        if l <= w[1].0 {
            return w[0].1 * (l / w[0].0).powf(q(w[0], w[1]));
        }
    }
    pts[pts.len() - 1].1
}

/// The class XP table that gives `target_hours` at the measured rates: XP from L to L + 1 is the rate at L
/// (the mean of L and L + 1 in logs) times the hours the curve gives that level, to three figures.
pub fn fit_class_xp(rows: &[(u8, u64)]) -> [u32; 59] {
    let mut out = [0u32; 59];
    for l in 1..60u8 {
        let hours = target_hours(l + 1) - target_hours(l);
        let rate = best_rate(rows, l).1;
        out[l as usize - 1] = three_figures((rate * hours).max(10.0) as u64) as u32;
    }
    out
}

pub fn three_figures(v: u64) -> u64 {
    let mut m = 1;
    while v / m >= 1_000 {
        m *= 10;
    }
    (v + m / 2) / m * m
}

/// Hours to each class level that a class XP table gives at measured rates.
pub fn hours_from(table: &[u32], rows: &[(u8, u64)]) -> [f64; 61] {
    let mut h = [0f64; 61];
    for l in 1..60usize {
        let rate = best_rate(rows, l as u8).1;
        h[l + 1] = h[l] + table[l - 1] as f64 / rate;
    }
    h
}

/// The career rate of a level: the harmonic mean of the median class alone and in a party (half of the careers
/// play alone, half in parties, so this is the rate at which the median career's time passes).
pub fn career_rate(r: &[[Rate; 5]; 2]) -> u64 {
    let s = median(r[0].iter().map(|x| x.xp).collect()).max(1);
    let p = median(r[1].iter().map(|x| x.xp).collect()).max(1);
    2 * s * p / (s + p)
}

// ---- careers

/// Hours (credited) when a career reached a level, or None.
pub fn hours_at(c: &Career, level: usize) -> Option<f64> {
    let t = c.reached[level];
    (t != u64::MAX).then(|| t as f64 / TICKS_HOUR as f64)
}

/// Plays cohorts until each is played out (`Cohort::finished`: all 60, or those below 60 have `max_hours` credited);
/// returns every career. `progress` is called after every round with the seed index and the cohort.
pub fn careers(seeds: u64, per: usize, pace: Pace, max_hours: u64, mut progress: impl FnMut(u64, &Cohort)) -> Vec<Career> {
    let mut all = Vec::new();
    for s in 0..seeds {
        let mut c = Cohort::new(1_000 + s, per);
        while !c.finished(max_hours) {
            c.round(pace);
            progress(s, &c);
        }
        all.extend(c.careers);
    }
    all
}

/// One progress line of a cohort (never starting `BALANCE `, the summary's word): round, careers still below 60,
/// their lowest level and fewest credited hours, and the levels with `levels`.
pub fn progress_line(s: u64, c: &Cohort, levels: bool) -> String {
    let live: Vec<&Career> = c.careers.iter().filter(|x| x.level < CLASS_LEVEL_MAX).collect();
    let low = live.iter().map(|x| x.level).min().unwrap_or(CLASS_LEVEL_MAX);
    let hours = live.iter().map(|x| x.ticks).min().unwrap_or(0) as f64 / TICKS_HOUR as f64;
    let mut line = format!("balance progress seed {s} round {} below_60 {}/{} lowest_level {low} fewest_hours {hours:.1}", c.round, live.len(), c.careers.len());
    if levels {
        let lv: Vec<u8> = c.careers.iter().map(|x| x.level).collect();
        line += &format!(" levels {lv:?}");
    }
    line
}

/// The curve targets of rules 2: hours to class level 10, 20, 40, 60.
pub const CURVE: [(usize, f64); 4] = [(10, 25.0 / 60.0), (20, 4.0), (40, 25.0), (60, 80.0)];
/// No class more than this far behind the median at any band (percent).
pub const BEHIND_MAX_PCT: i64 = 15;

/// Per class (KNIGHT..PALADIN) the median hours to each level 1..60.
pub fn class_hours(all: &[Career]) -> Vec<[Option<f64>; 61]> {
    (1..6u8)
        .map(|class| {
            let mine: Vec<&Career> = all.iter().filter(|c| c.class == class).collect();
            let mut row = [None; 61];
            for (l, cell) in row.iter_mut().enumerate().skip(1) {
                let mut v: Vec<f64> = mine.iter().filter_map(|c| hours_at(c, l)).collect();
                if v.len() * 2 >= mine.len() && !v.is_empty() {
                    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
                    // The median of all her careers (those that did not reach it count as the slowest).
                    let n = mine.len();
                    v.resize(n, f64::INFINITY);
                    *cell = Some(if n % 2 == 1 { v[n / 2] } else { (v[n / 2 - 1] + v[n / 2]) / 2.0 });
                }
            }
            row
        })
        .collect()
}

/// Per class and band, class XP an hour (from the bands' own books), and the worst gap behind the median.
pub fn band_rates(all: &[Career]) -> (Vec<[u64; BANDS]>, [u64; BANDS], i64) {
    let mut rates = Vec::new();
    for class in 1..6u8 {
        let mut row = [0u64; BANDS];
        for b in 0..BANDS {
            let (xp, t) = all.iter().filter(|c| c.class == class).fold((0u64, 0u64), |a, c| (a.0 + c.bands[b].xp, a.1 + c.bands[b].ticks));
            row[b] = if t == 0 { 0 } else { xp * TICKS_HOUR / t };
        }
        rates.push(row);
    }
    let mut med = [0u64; BANDS];
    let mut worst = 0i64;
    for b in 1..BANDS - 1 {
        med[b] = median(rates.iter().map(|r| r[b]).collect());
        for r in &rates {
            if r[b] > 0 {
                worst = worst.min(pct_off(r[b], med[b]));
            }
        }
    }
    med[0] = median(rates.iter().map(|r| r[0]).collect());
    (rates, med, worst)
}

pub fn print_careers(all: &[Career]) {
    let names = ["KNIGHT", "MAGE", "ARCHER", "PRIEST", "PALADIN"];
    let hours = class_hours(all);
    println!("median hours to a class level (credited field time), {} careers", all.len());
    print!("{:>8}", "level");
    for n in names {
        print!("{n:>9}");
    }
    println!("{:>9}{:>9}", "median", "target");
    for l in [5usize, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60] {
        print!("{l:>8}");
        let mut v = Vec::new();
        for h in &hours {
            match h[l] {
                Some(x) => {
                    v.push(x);
                    print!("{x:>9.2}");
                }
                None => print!("{:>9}", "-"),
            }
        }
        v.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let med = v.get(v.len() / 2).copied().unwrap_or(f64::NAN);
        let target = if CURVE.iter().any(|t| t.0 == l) { format!("{:.2}", target_hours(l as u8)) } else { format!("({:.2})", target_hours(l as u8)) };
        println!("{med:>9.2}{target:>9}");
    }
    let (rates, med, worst) = band_rates(all);
    println!("class XP an hour by band (percent off the band's median)");
    print!("{:>8}", "band");
    for n in names {
        print!("{n:>15}");
    }
    println!("{:>10}", "median");
    for b in 0..BANDS - 1 {
        print!("{:>8}", format!("{}-{}", (b * 10).max(1), b * 10 + 9));
        for r in &rates {
            print!("{:>10}{:>+4}%", r[b], pct_off(r[b], med[b]));
        }
        println!("{:>10}", med[b]);
    }
    println!("worst class behind its band's median (bands 10-59): {worst}%");
    // Life: kills, downs, falls, party share.
    println!("per hour, all careers by band: kills, downs, falls; outings in a party");
    for b in 0..BANDS - 1 {
        let (mut t, mut k, mut d, mut f, mut o, mut p) = (0u64, 0u64, 0u64, 0u64, 0u64, 0u64);
        for c in all {
            let x = &c.bands[b];
            t += x.ticks;
            k += x.kills;
            d += x.downs;
            f += x.falls;
            o += x.outings;
            p += x.partied;
        }
        let h = t.max(1) as f64 / TICKS_HOUR as f64;
        println!("{:>8} kills {:>7.0} downs {:>5.2} falls {:>5.2} party {:>3}%", format!("{}-{}", (b * 10).max(1), b * 10 + 9), k as f64 / h, d as f64 / h, f as f64 / h, p * 100 / o.max(1));
    }
    print_book(all);
}

pub fn career_book(all: &[Career]) -> (Book, [Book; BANDS]) {
    let mut total = Book::default();
    let mut bands = [Book::default(); BANDS];
    for c in all {
        for (b, band) in c.bands.iter().enumerate() {
            total.add(&band.book);
            bands[b].add(&band.book);
        }
    }
    (total, bands)
}

pub fn print_book(all: &[Career]) {
    let (total, bands) = career_book(all);
    println!("coin per career (minted by monsters and the merchant; sunk), by band");
    println!(
        "{:>8} {:>11} {:>10} {:>10} | {:>9} {:>9} {:>9} {:>9} {:>10} {:>8} | {:>6} {:>10}",
        "band", "kills", "chests", "merchant", "falls", "potions", "repair", "fares", "smith", "tax", "sunk%", "market"
    );
    let n = all.len().max(1) as u64;
    let row = |name: String, b: &Book| {
        println!(
            "{:>8} {:>11} {:>10} {:>10} | {:>9} {:>9} {:>9} {:>9} {:>10} {:>8} | {:>5}% {:>10}",
            name,
            b.kills / n,
            b.chests / n,
            b.merchant / n,
            b.fall / n,
            b.potions / n,
            b.repair / n,
            b.travel / n,
            b.smith / n,
            b.tax / n,
            b.sunk() * 100 / b.monsters().max(1),
            b.market / n
        );
    };
    for (b, book) in bands.iter().enumerate().take(BANDS - 1) {
        row(format!("{}-{}", (b * 10).max(1), b * 10 + 9), book);
    }
    row("career".into(), &total);
    println!(
        "sinks remove {}% of what monsters mint and {}% of all minted (with the merchant)",
        total.sunk() * 100 / total.monsters().max(1),
        total.sunk() * 100 / total.minted().max(1)
    );
}

// ---- gates of rules 13

/// The forced sinks (falls, potions, repair, fares) remove at least this percent of what monsters mint in an hour at
/// every band; the smith, the market's tax and what a hero chooses to spend remove the rest (balance.md).
pub const FORCED_SINK_MIN_PCT: u64 = 40;
/// Bounds on the jobs gate's own-contribution gaps (percent, by class, NOVICE unused) the short test (1 seed, 50
/// heroes, 1,200 ticks) holds the pairs to: the full gate's gaps (balance.md) with room for the short run's noise.
pub const JOB_GAP_REPORTED_PCT: [u64; 6] = [0, 75, 45, 80, 90, 45];

pub fn party_gate(seeds: u64, ticks: u32, fields: &[u8]) -> Vec<(u8, u32)> {
    let jobs: Vec<(u8, u64)> = fields.iter().flat_map(|&f| (0..seeds).map(move |s| (f, s))).collect();
    let res: Vec<Outcome> = par_map(&jobs, threads(), |&(f, s)| party(f, s, ticks, 100));
    fields.iter().enumerate().map(|(i, &f)| (f, res[i * seeds as usize..(i + 1) * seeds as usize].iter().filter(|o| o.fallen == 0).count() as u32)).collect()
}

/// Mean measure of each job over `seeds` crowds; returns per class (first job, second job, gap percent).
pub fn jobs_gate(seeds: u64, heroes: u32, level: u8, ticks: u32) -> Vec<(u8, u64, u64, u64)> {
    let jobs: Vec<u64> = (0..seeds).collect();
    let mut sum = vec![(0u32, 0u64); JOBS.len()];
    for rows in par_map(&jobs, threads(), |&s| job_crowd(s, heroes, level, ticks)) {
        for (j, c, m) in rows {
            sum[j as usize].0 += c;
            sum[j as usize].1 += m * c as u64;
        }
    }
    let mean = |j: usize| sum[j].1.checked_div(sum[j].0 as u64).unwrap_or(0);
    (1..6u8)
        .map(|c| {
            let (a, b) = (mean(CLASSES[c as usize].jobs[0] as usize), mean(CLASSES[c as usize].jobs[1] as usize));
            (c, a, b, (a.max(b) - a.min(b)) * 100 / a.max(b).max(1))
        })
        .collect()
}

/// The role-aware jobs measure (job B1): the crowd's class XP per hero over `ticks` when every hero of `class`
/// takes its first or its second job (the other classes split evenly). A tank or healer job is worth what it does
/// for the crowd (kills it enables, falls it prevents), which a hero's own contribution does not count.
pub fn crowd_value(seed: u64, heroes: u32, level: u8, ticks: u32, class: u8, second: bool) -> u64 {
    use realm_core::{Config, FIELD, Field, Outing, SUB, Sheet};
    use realm_core::bots::{Bot, Plan};
    let field = 5u8;
    let mut f = Field::open(field, 300 + seed, Config { monsters: 8_000, threads: 1 });
    f.set_clock(realm_core::tide_start(field, 0) - 2);
    let mut bots = Vec::new();
    for i in 0..heroes {
        let c = 1 + (i % 5) as u8;
        let job2 = if c == class { second } else { (i / 5) % 2 == 1 };
        let mut sheet = Sheet::bench(c, (i % 4) as u8, level);
        if level >= JOB_LEVEL {
            sheet.job = CLASSES[c as usize].jobs[job2 as usize];
        }
        let n = i as i32;
        let id = f.join(&sheet, &Outing::new(), FIELD / 2 + (n % 10 - 5) * 24 * SUB, FIELD / 2 + (n / 10 - 5) * 24 * SUB);
        let mut plan = Plan::crowd(500);
        plan.every = 4;
        bots.push(Bot::new(id, seed, plan));
    }
    let mut xp = 0u64;
    for _ in 0..ticks {
        let inputs: Vec<u16> = bots.iter_mut().map(|b| b.act(&f)).collect();
        f.step(&inputs);
        for e in f.events() {
            if let realm_core::Event::Xp { amount, .. } = *e {
                xp += amount as u64;
            }
        }
    }
    xp / heroes as u64
}

fn arg(n: usize, d: u64) -> u64 {
    std::env::args().nth(n).map_or(d, |s| s.parse().unwrap_or(d))
}

pub fn main() {
    match std::env::args().nth(2).as_deref() {
        Some("probe") => {
            let (seeds, minutes) = (arg(3, 2), arg(4, 10) as u32);
            let levels: Vec<u8> = std::env::args().nth(5).map_or(PROBE_LEVELS.to_vec(), |s| s.split(',').filter_map(|x| x.parse().ok()).collect());
            let rows = probe_table(&levels, seeds, minutes * 60 * TICK_HZ);
            print_probe(&rows);
            let rates: Vec<(u8, u64)> = rows.iter().map(|(l, r)| (*l, career_rate(r))).collect();
            println!("career rate (harmonic mean of alone and party medians): {rates:?}");
            if rates.len() > 1 {
                println!("fitted CLASS_XP: {:?}", fit_class_xp(&rates));
            }
        }
        Some("career") => {
            let (seeds, per, minutes, fast, hours) = (arg(3, 1), arg(4, 2) as usize, arg(5, 20) as u32, arg(6, 1), arg(7, 200));
            let pace = Pace { ticks: minutes * 60 * TICK_HZ, fast, threads: threads() };
            // A progress line on stdout every round (a round of 20-minute outings is a minute or two on 2 threads), so a run killed at its time
            // limit still says how far it got; BALANCE_PROGRESS adds every career's level.
            let levels = std::env::var("BALANCE_PROGRESS").is_ok();
            let started = std::time::Instant::now();
            let all = careers(seeds, per, pace, hours, |s, c| println!("{} secs {:.0}", progress_line(s, c, levels), started.elapsed().as_secs_f64()));
            print_careers(&all);
            let hours = class_hours(&all);
            let (_, _, worst) = band_rates(&all);
            let (book, _) = career_book(&all);
            let med = |l: usize| {
                let mut v: Vec<f64> = hours.iter().filter_map(|h| h[l]).collect();
                v.sort_by(|a, b| a.partial_cmp(b).unwrap());
                v.get(v.len() / 2).copied().unwrap_or(f64::NAN)
            };
            println!(
                "BALANCE careers={} h10={:.2} h20={:.1} h40={:.1} h60={:.1} worst_class={}% sunk={}%",
                all.len(),
                med(10),
                med(20),
                med(40),
                med(60),
                worst,
                book.sunk() * 100 / book.monsters().max(1)
            );
        }
        Some("gates") => {
            let seeds = arg(3, 10);
            for (f, ok) in party_gate(seeds, 6_000, &[0, 1, 2, 3, 4, 5]) {
                println!("party gate {:<18} never fallen {ok}/{seeds}", FIELDS[f as usize].name);
            }
            for (c, a, b, gap) in jobs_gate(arg(4, 3), 100, 50, 3_000) {
                let j = CLASSES[c as usize].jobs;
                println!("jobs gate {:<8} {:<13} {a:>9}  {:<13} {b:>9}  gap {gap}%", CLASSES[c as usize].name, JOBS[j[0] as usize].name, JOBS[j[1] as usize].name);
            }
        }
        Some("fit") => {
            // The class XP table fitted to the measured rates, and the hours the current table gives.
            let fit = fit_class_xp(&CAREER_XP_HOUR);
            println!("fitted CLASS_XP: {fit:?}");
            let now = hours_from(&CLASS_XP, &CAREER_XP_HOUR);
            for (l, t) in CURVE {
                println!("level {l}: target {t:.2} h, CLASS_XP gives {:.2} h, the fit {:.2} h", now[l], hours_from(&fit, &CAREER_XP_HOUR)[l]);
            }
        }
        Some("jobs") => {
            // Both measures of the jobs gate: each job's own contribution, and the crowd's XP with the class on it.
            let (seeds, heroes, level, ticks) = (arg(3, 2), arg(4, 100) as u32, arg(5, 50) as u8, arg(6, 3_000) as u32);
            let own = jobs_gate(seeds, heroes, level, ticks);
            let runs: Vec<(u8, bool, u64)> = (1..6u8).flat_map(|c| [false, true].into_iter().flat_map(move |j| (0..seeds).map(move |s| (c, j, s)))).collect();
            let vals = par_map(&runs, threads(), |&(c, j, s)| crowd_value(s, heroes, level, ticks, c, j));
            for (k, (c, a, b, gap)) in own.iter().enumerate() {
                let n = seeds as usize;
                let va: u64 = vals[k * 2 * n..k * 2 * n + n].iter().sum::<u64>() / seeds;
                let vb: u64 = vals[k * 2 * n + n..(k + 1) * 2 * n].iter().sum::<u64>() / seeds;
                let cgap = (va.max(vb) - va.min(vb)) * 100 / va.max(vb).max(1);
                let j = CLASSES[*c as usize].jobs;
                println!(
                    "jobs {:<8} {:<13} own {a:>9} crowd {va:>8} | {:<13} own {b:>9} crowd {vb:>8} | own gap {gap}% crowd gap {cgap}%",
                    CLASSES[*c as usize].name, JOBS[j[0] as usize].name, JOBS[j[1] as usize].name
                );
            }
        }
        _ => eprintln!("balance probe SEEDS MINUTES [L,L] | career SEEDS PER MINUTES FAST [HOURS] | gates SEEDS [JOB_SEEDS] | jobs SEEDS HEROES LEVEL TICKS | fit"),
    }
}
