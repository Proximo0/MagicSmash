//! The bot gates of rules section 13, as functions the tests and `realm-loadtest bots` share: a class alone at the
//! edge, a party holding its middle ring through a tide, and a crowd that compares the two jobs of a class.
//! Every run is a pure function of its arguments (the class bots are whole-number and seeded).

use crate::bots::{Bot, Plan};
use crate::sheet::{Outing, Sheet};
use crate::tables::*;
use crate::tide::tide_start;
use crate::{Config, Event, FIELD, Field, SUB};

/// What a run came to.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Outcome {
    /// Heroes who fell (were not raised in time, PHOENIX ASH aside), and downs in all.
    pub fallen: u32,
    pub downs: u32,
    pub kills: u64,
    /// The first tick anyone was downed.
    pub first_down: Option<u32>,
    /// Tides won and lost.
    pub won: u32,
    pub lost: u32,
    /// Draws the first hero was granted (rules 5).
    pub draws: u32,
}

fn tally(f: &Field, o: &mut Outcome, t: u32) {
    for e in f.events() {
        match e {
            Event::Fallen { .. } => o.fallen += 1,
            Event::Down { .. } => {
                o.downs += 1;
                o.first_down.get_or_insert(t);
            }
            Event::Tide { state, .. } if *state == TIDE_WON => o.won += 1,
            Event::Tide { state, .. } if *state == TIDE_LOST => o.lost += 1,
            _ => {}
        }
    }
}

/// One hero of `class` alone at the first edge waystone of THE FOOL'S ROAD for `minutes`, played by a class bot.
pub fn alone(class: u8, class_level: u8, seed: u64, minutes: u32) -> Outcome {
    let mut f = Field::open(0, 100 + seed, Config { monsters: 4_096, threads: 1 });
    let mut s = Sheet::bench(class, HUMAN, class_level);
    s.deck = (1..=crate::owned_cards(class_level).min(DECK_SIZE as u8)).collect();
    let (x, y) = f.terrain().waystones[0];
    let id = f.join(&s, &Outing::new(), x, y);
    let mut bot = Bot::new(id, seed, Plan::alone(7_000));
    let mut o = Outcome::default();
    for t in 0..minutes * 60 * TICK_HZ {
        let input = bot.act(&f);
        f.step(&[input]);
        tally(&f, &mut o, t);
    }
    o.kills = f.counters().0;
    o.draws = f.heroes()[id as usize].draws + f.heroes()[id as usize].owed as u32;
    o
}

/// A party of KNIGHT, PRIEST, ARCHER and MAGE at a field's bottom level, in bench gear of that level, in the
/// middle ring for `ticks`, with the field's tide running (the clock is set so a tide begins `lead` ticks in).
pub fn party(field: u8, seed: u64, ticks: u32, lead: u32) -> Outcome {
    let row = &FIELDS[field as usize];
    let mut f = Field::open(field, 200 + seed, Config { monsters: 6_000, threads: 1 });
    f.set_clock(tide_start(field, 0) - lead as u64);
    let level = row.bottom;
    let (cx, cy) = f.terrain().waystones[0];
    let mut bots = Vec::new();
    for (k, class) in [KNIGHT, PRIEST, ARCHER, MAGE].into_iter().enumerate() {
        let mut s = Sheet::bench(class, (k % 4) as u8, level);
        s.deck = (1..=crate::owned_cards(level).min(DECK_SIZE as u8)).collect();
        let id = f.join(&s, &Outing::new(), cx + (k as i32 % 2) * 20 * SUB, cy + (k as i32 / 2) * 20 * SUB);
        let mut plan = Plan::party(4_200);
        plan.objectives = false;
        bots.push(Bot::new(id, seed, plan));
    }
    let mut o = Outcome::default();
    for t in 0..ticks {
        let inputs: Vec<u16> = bots.iter_mut().map(|b| b.act(&f)).collect();
        f.step(&inputs);
        tally(&f, &mut o, t);
    }
    o.kills = f.counters().0;
    o.draws = f.heroes()[0].draws + f.heroes()[0].owed as u32;
    o
}

/// Contribution per hero of each job over a crowd of `heroes` heroes (an even share of each of the ten jobs) at
/// the heart of THE WORLD'S EDGE for `ticks`, during a tide. Returns, per job id, (heroes, mean contribution).
pub fn job_crowd(seed: u64, heroes: u32, class_level: u8, ticks: u32) -> Vec<(u8, u32, u64)> {
    let field = 5u8;
    let mut f = Field::open(field, 300 + seed, Config { monsters: 8_000, threads: 1 });
    f.set_clock(tide_start(field, 0) - 2);
    let mut owner = Vec::new();
    let mut bots = Vec::new();
    for i in 0..heroes {
        let class = 1 + (i % 5) as u8;
        let second = (i / 5) % 2 == 1;
        let sheet = Sheet::bench(class | if second { crate::sheet::BENCH_SECOND_JOB } else { 0 }, (i % 4) as u8, class_level);
        let job = sheet.job;
        let n = i as i32;
        let (x, y) = (FIELD / 2 + (n % 10 - 5) * 24 * SUB, FIELD / 2 + (n / 10 - 5) * 24 * SUB);
        let id = f.join(&sheet, &Outing::new(), x, y);
        owner.push((id, job));
        let mut plan = Plan::crowd(500);
        plan.every = 4;
        bots.push(Bot::new(id, seed, plan));
    }
    let mut sums = vec![(0u32, 0u64); JOBS.len()];
    // The tide's verdict clears contributions: keep each hero's best.
    let mut best = vec![0u32; owner.len()];
    for _ in 0..ticks {
        let inputs: Vec<u16> = bots.iter_mut().map(|b| b.act(&f)).collect();
        f.step(&inputs);
        for (k, &(id, _)) in owner.iter().enumerate() {
            best[k] = best[k].max(f.heroes()[id as usize].tide_contrib);
        }
    }
    for (k, &(_, job)) in owner.iter().enumerate() {
        if (job as usize) < JOBS.len() {
            sums[job as usize].0 += 1;
            sums[job as usize].1 += best[k] as u64;
        }
    }
    (0..JOBS.len()).map(|j| (j as u8, sums[j].0, sums[j].1.checked_div(sums[j].0 as u64).unwrap_or(0))).collect()
}

/// The same-hash gate: `heroes` bot heroes of mixed classes and jobs, using skills, picks, potions and waystones,
/// play `ticks` of the field through a tide and a boss on 1, 2, 3 and 4 threads and on a follower loaded from
/// the bytes a third of the way in. Every hundred ticks and at the end all five hashes must agree.
/// Returns the final hash, or what differed and when.
pub fn hash_gate(field: u8, heroes: u32, ticks: u32) -> Result<u64, String> {
    let monsters = 6_000.max(heroes * 8);
    let open = |threads: usize| {
        let mut f = Field::open(field, 400 + field as u64, Config { monsters, threads });
        f.set_clock(tide_start(field, 0) - 100);
        f
    };
    let mut fields: Vec<Field> = (1..=4).map(open).collect();
    let mut bots = Vec::new();
    for i in 0..heroes {
        let class = 1 + (i % 5) as u8;
        let second = (i / 5) % 2 == 1;
        let sheet = Sheet::bench(class | if second { crate::sheet::BENCH_SECOND_JOB } else { 0 }, (i % 4) as u8, FIELDS[field as usize].bottom);
        let n = i as i32;
        let (x, y) = (FIELD / 2 + (n % 40 - 20) * 20 * SUB, FIELD / 2 + (n / 40 - 12) * 20 * SUB);
        let mut id = 0;
        for f in fields.iter_mut() {
            id = f.join(&sheet, &Outing::new(), x, y);
        }
        let mut plan = Plan::crowd(500);
        plan.every = 8;
        bots.push(Bot::new(id, field as u64, plan));
    }
    let mut follower: Option<Field> = None;
    for t in 0..ticks {
        if t == ticks / 3 {
            for f in fields.iter_mut() {
                f.summon_boss(field_boss_of(field, 0), 60_000, FIELD / 2, FIELD / 2);
            }
            follower = Field::from_bytes(&fields[0].to_bytes(), 1);
        }
        let inputs: Vec<u16> = bots.iter_mut().map(|b| b.act(&fields[0])).collect();
        for f in fields.iter_mut() {
            f.step(&inputs);
        }
        if let Some(fl) = follower.as_mut() {
            fl.step(&inputs);
        }
        if t % 100 == 99 || t + 1 == ticks {
            let h = fields[0].hash();
            for (k, f) in fields.iter().enumerate().skip(1) {
                if f.hash() != h {
                    return Err(format!("field {field}: {} threads differ at tick {t}", k + 1));
                }
            }
            if follower.as_ref().is_some_and(|fl| fl.hash() != h) {
                return Err(format!("field {field}: the follower differs at tick {t}"));
            }
        }
    }
    Ok(fields[0].hash())
}
