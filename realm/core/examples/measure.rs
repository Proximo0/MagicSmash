//! Measurements for `docs/realm/rules_built.md` (a tool, not part of the core):
//!   measure phases FIELD THREADS [TICKS] [WARMUP]   core tick cost per phase, 1,000 heroes, 20,000 monsters
//!   measure killtime                                ticks for a hero of a walker's level to kill it, per class
//!   measure kite CLASS_LEVEL SEEDS MINUTES          a kiting bot of each class alone at the edge of field 0
//!   measure pace SEEDS MINUTES                      kills of a class bot alone at each field's bottom and middle
use realm_core::tables::*;
use realm_core::*;
use std::time::Instant;

fn arg(n: usize, d: u64) -> u64 {
    std::env::args().nth(n).map_or(d, |s| s.parse().expect("number"))
}

fn rng(s: &mut u64) -> u64 {
    rng_next(s)
}

fn pctl(v: &mut [f64], p: usize) -> f64 {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    v[(v.len() * p / 100).min(v.len() - 1)]
}

/// Monsters in the 3 x 3 cells around a point.
fn crowd(f: &Field, x: i32, y: i32, half: i32) -> u32 {
    let g = f.grid();
    let (cx, cy) = (x >> CELL_SHIFT, y >> CELL_SHIFT);
    let mut n = 0;
    for yy in (cy - half).max(0)..=(cy + half).min(CELLS_W as i32 - 1) {
        for xx in (cx - half).max(0)..=(cx + half).min(CELLS_W as i32 - 1) {
            n += g.count(yy as usize * CELLS_W + xx as usize);
        }
    }
    n
}

/// The direction (1..8) toward the emptiest of the eight blocks 128 px out, or 0.
fn emptiest(f: &Field, x: i32, y: i32, r: &mut u64) -> u16 {
    let mut best = (u32::MAX, 0u16);
    let start = (rng(r) % 8) as usize;
    for j in 0..8 {
        let k = (start + j) % 8;
        let (ox, oy) = NEIGHBOURS[k];
        let (bx, by) = (x + ox * 128 * SUB, y + oy * 128 * SUB);
        if bx < 300 * SUB || by < 300 * SUB || bx > FIELD - 300 * SUB || by > FIELD - 300 * SUB || f.terrain().wall(bx, by) {
            continue;
        }
        let n = crowd(f, bx, by, 1);
        if n < best.0 {
            best = (n, k as u16 + 1);
        }
    }
    best.1
}

// ---- phases

fn phases() {
    let field = arg(2, 0) as u8;
    let threads = arg(3, 4) as usize;
    let ticks = arg(4, 600) as u32;
    let warmup = arg(5, 200) as u32;
    let heroes = 1000u32;
    let mut f = Field::open(field, 1, Config { monsters: 20_000, threads });
    let top = FIELDS[field as usize].top;
    let mut r = 0x5EED_u64 ^ field as u64;
    let mut rally = Vec::new();
    for i in 0..heroes {
        let v = rng(&mut r);
        let class = 1 + (v % 5) as u8 | (((v >> 5) & 1) as u8) << 3;
        let is_rally = i % 10 < 3;
        let (x, y) = if is_rally {
            (FIELD / 2 + ((v >> 16) % 600) as i32 * SUB - 300 * SUB, FIELD / 2 + ((v >> 40) % 600) as i32 * SUB - 300 * SUB)
        } else {
            (((v >> 16) % 15_984) as i32 * SUB + 200 * SUB, ((v >> 40) % 15_984) as i32 * SUB + 200 * SUB)
        };
        f.join(&Sheet::bench(class, (v >> 8) as u8 % 4, top), &Outing::new(), x, y);
        rally.push(is_rally);
    }
    let mut inputs = vec![0u16; heroes as usize];
    let names = ["input", "flow", "grid", "move", "fight", "spawn"];
    let mut per: Vec<Vec<f64>> = vec![Vec::new(); 6];
    let mut total = Vec::new();
    for t in 0..warmup + ticks {
        for i in 0..heroes as usize {
            if (t + i as u32) % 8 != 0 {
                continue;
            }
            let h = &f.heroes()[i];
            if !h.alive() {
                inputs[i] = 0;
                continue;
            }
            let mut b1 = 0u16;
            if !h.offers.is_empty() {
                b1 |= 1 << IN_PICK_SHIFT;
            }
            if h.health * 100 < h.max_health * 40 {
                b1 |= IN_POTION1;
            }
            let dir = if crowd(&f, h.x, h.y, 2) > 12 {
                let d = emptiest(&f, h.x, h.y, &mut r);
                if rng(&mut r) % 4 == 0 { d | IN_SKILL1 | IN_SKILL2 | IN_ULT } else { d }
            } else if rally[i] && dist_px(h.x, h.y, FIELD / 2, FIELD / 2) > 300 {
                let (dx, dy) = (FIELD / 2 - h.x, FIELD / 2 - h.y);
                let k = NEIGHBOURS.iter().position(|&(ox, oy)| ox == dx.signum() && oy == dy.signum()).unwrap_or(0);
                k as u16 + 1
            } else {
                (rng(&mut r) % 9) as u16
            };
            // A pick or potion fires on the press, so let go every other decision.
            inputs[i] = dir | if inputs[i] & 0xFF00 == 0 { b1 } else { 0 };
        }
        let mut last = Instant::now();
        let t0 = last;
        let mut row = [0f64; 6];
        f.step_with(&inputs, |p| {
            let now = Instant::now();
            let k = match p {
                Phase::Input => 0,
                Phase::Flow => 1,
                Phase::Grid => 2,
                Phase::Move => 3,
                Phase::Fight => 4,
                Phase::Spawn => 5,
            };
            row[k] = (now - last).as_secs_f64() * 1000.0;
            last = now;
        });
        if t >= warmup {
            for k in 0..6 {
                per[k].push(row[k]);
            }
            total.push(t0.elapsed().as_secs_f64() * 1000.0);
        }
    }
    let mean = |v: &[f64]| v.iter().sum::<f64>() / v.len() as f64;
    let mut line = format!("field {field} threads {threads} {}x{} |", f.player_count(), f.monster_count());
    for k in 0..6 {
        let m = mean(&per[k]);
        line += &format!(" {} {:.2}/{:.2}", names[k], m, pctl(&mut per[k], 99));
    }
    let m = mean(&total);
    let (kills, births, downs) = f.counters();
    line += &format!(
        " | tick {:.2}/{:.2} max {:.2} | kills {kills} births {births} downs {downs} recycled {}",
        m,
        pctl(&mut total, 99),
        pctl(&mut total, 100),
        f.recycled()
    );
    println!("{line}");
}

// ---- kill time

/// The walker a hero of `level` meets: the walker of the field that starts at that level (THE WORLD'S EDGE has
/// none; it gets THE TOWER's swords).
fn walker_for(level: u8) -> (u8, u8) {
    let field = ((level / 10) as usize).min(5) as u8;
    let pick = |f: u8| (0..KINDS.len()).filter(|&k| KINDS[k].field == f && KINDS[k].beh == WALKER).max_by_key(|&k| KINDS[k].health);
    let k = pick(field).or_else(|| (0..KINDS.len()).find(|&k| KINDS[k].name == "swords")).unwrap();
    (field, k as u8)
}

fn killtime() {
    println!("seconds = walker health / the hero's damage a second on it (one walker, alone, no cards)");
    println!("level | walker (field) hp | NOVICE KNIGHT MAGE ARCHER PRIEST PALADIN | mean of the five classes");
    let mut worst: (f64, f64) = (f64::MAX, 0.0);
    for level in [1u8, 10, 20, 30, 40, 50, 60] {
        let (field, kind) = walker_for(level);
        let hp = max_hp(kind, level, 0);
        let mut line = format!("{level:>5} | {} ({field}) {hp}", KINDS[kind as usize].name);
        let mut sum = 0.0;
        for class in 0..6u8 {
            let mut f = Field::open(field, 3, Config { monsters: 64, threads: 1 });
            f.set_births(false);
            let (x, y) = f.terrain().waystones[6];
            let id = f.join(&Sheet::bench(class, HUMAN, level), &Outing::new(), x, y);
            f.hero_mut(id).fx[FX_AEGIS as usize] = 60_000;
            for _ in 0..12 {
                f.step::<u16>(&[]);
            }
            let reach = match CLASSES[f.heroes()[id as usize].class as usize].weapon.shape {
                Shape::Arc { px, .. } => px / 2,
                Shape::Ring { px } => px / 2,
                Shape::Bolt { .. } => 100,
                Shape::Drop { .. } => 100,
            };
            let (hx, hy) = (f.heroes()[id as usize].x, f.heroes()[id as usize].y);
            let m = f.place_monster(kind, level, 0, hx + reach * SUB, hy).unwrap();
            const BIG: u32 = 1_000_000_000;
            const WINDOW: u32 = 20 * TICK_HZ;
            let mut dealt = 0f64;
            for _ in 0..WINDOW {
                let mm = f.monsters_mut();
                mm.x[m as usize] = hx + reach * SUB;
                mm.y[m as usize] = hy;
                mm.stun[m as usize] = 250;
                mm.hp[m as usize] = BIG;
                let before = f.monsters().hp[m as usize];
                f.step::<u16>(&[]);
                dealt += (before - f.monsters().hp[m as usize]) as f64;
            }
            let secs = hp as f64 / (dealt / (WINDOW / TICK_HZ) as f64);
            if class > 0 && level >= 10 {
                sum += secs;
                worst = (worst.0.min(secs), worst.1.max(secs));
            }
            line += &format!(" {secs:.2}");
        }
        if level >= 10 {
            line += &format!(" | {:.2}", sum / 5.0);
        }
        println!("{line}");
    }
    println!("classes at 10 to 60: fastest {:.2} s, slowest {:.2} s", worst.0, worst.1);
}

// ---- kiting

fn kite() {
    let class_level = arg(2, 1) as u8;
    let seeds = arg(3, 10);
    let minutes = arg(4, 10) as u32;
    println!("class level {class_level}, {seeds} seeds, {minutes} min alone at the edge of field 0");
    // Below class level 10 every class is a NOVICE: one run stands for all six.
    let classes = if class_level < SKILL1_LEVEL { 0..1u8 } else { 0..6u8 };
    for class in classes {
        let (mut survived, mut unfallen) = (0, 0);
        let (mut kills, mut levels, mut first_down) = (0u64, 0u32, Vec::new());
        for seed in 0..seeds {
            let mut f = Field::open(0, 100 + seed, Config { monsters: 4096, threads: 1 });
            let mut s = Sheet::bench(class, HUMAN, class_level);
            s.deck = (1..=owned_cards(class_level).min(DECK_SIZE as u8)).collect();
            let (x, y) = f.terrain().waystones[0];
            let id = f.join(&s, &Outing::new(), x, y);
            let mut input = 0u16;
            let mut down_at = None;
            let mut fell = false;
            for t in 0..minutes * 60 * TICK_HZ {
                let h = &f.heroes()[id as usize];
                if t % 2 == 0 && h.alive() {
                    // Kite: away from every monster within 200 px (weighted by 1 / distance), while orbiting
                    // the heart clockwise at the middle of the edge ring; around walls by trying the neighbours.
                    let (mut vx, mut vy) = (0f64, 0f64);
                    let m = f.monsters();
                    let mut near = 0;
                    grid_box(f.grid(), CELLS_W, CELL_SHIFT, h.x - 200 * SUB, h.y - 200 * SUB, h.x + 200 * SUB, h.y + 200 * SUB, |i| {
                        let i = i as usize;
                        let (dx, dy) = ((h.x - m.x[i]) as f64 / SUB as f64, (h.y - m.y[i]) as f64 / SUB as f64);
                        let d2 = (dx * dx + dy * dy).max(16.0);
                        if m.hp[i] > 0 && d2 < 200.0 * 200.0 {
                            vx += dx / d2;
                            vy += dy / d2;
                            near += 1;
                        }
                    });
                    let (cx, cy) = ((h.x - FIELD / 2) as f64 / SUB as f64, (h.y - FIELD / 2) as f64 / SUB as f64);
                    let r = (cx * cx + cy * cy).sqrt().max(1.0);
                    // Tangent (clockwise, y down) plus a pull back to radius 7,000 px.
                    let (tx, ty) = (-cy / r, cx / r);
                    let pull = ((7_000.0 - r) / 500.0).clamp(-1.0, 1.0);
                    let orbit = 0.004;
                    vx += orbit * (tx + pull * cx / r);
                    vy += orbit * (ty + pull * cy / r);
                    let want = vy.atan2(vx);
                    let mut best = (f64::MAX, 0u16);
                    for (k, &(ox, oy)) in NEIGHBOURS.iter().enumerate() {
                        let len = if ox != 0 && oy != 0 { 1.414 } else { 1.0 };
                        if f.terrain().wall(h.x + ox * 24 * SUB, h.y + oy * 24 * SUB) || f.terrain().wall(h.x + ox * 48 * SUB, h.y + oy * 48 * SUB) {
                            continue;
                        }
                        let a = (oy as f64 / len).atan2(ox as f64 / len);
                        let mut d = (a - want).abs();
                        if d > std::f64::consts::PI {
                            d = 2.0 * std::f64::consts::PI - d;
                        }
                        if d < best.0 {
                            best = (d, k as u16 + 1);
                        }
                    }
                    let dir = best.1;
                    let mut b1 = 0u16;
                    if !h.offers.is_empty() && input & IN_PICK == 0 {
                        b1 |= 1 << IN_PICK_SHIFT;
                    }
                    if h.health * 100 < h.max_health * 45 && input & IN_POTION1 == 0 {
                        b1 |= IN_POTION1;
                    }
                    let skills = if near > 6 { IN_SKILL1 | IN_SKILL2 | IN_ULT } else { 0 };
                    input = dir | skills | b1;
                }
                f.step(&[input]);
                if std::env::var("TRACE").is_ok() && t % 20 == 0 && t < 600 {
                    let h = &f.heroes()[id as usize];
                    let (mut n60, mut n150) = (0, 0);
                    let m = f.monsters();
                    for i in 0..m.len() {
                        if m.hp[i] > 0 {
                            let d = dist_px(m.x[i], m.y[i], h.x, h.y);
                            n60 += (d < 60) as u32;
                            n150 += (d < 150) as u32;
                        }
                    }
                    eprintln!(
                        "t {:>3}s hp {}/{} alive {} n60 {n60} n150 {n150} kills {} dir {} pos {},{} ring {}",
                        t / 20,
                        h.health,
                        h.max_health,
                        f.monster_count(),
                        f.counters().0,
                        input & 15,
                        h.x / SUB,
                        h.y / SUB,
                        ring_of(h.x, h.y)
                    );
                }
                fell |= f.events().iter().any(|e| matches!(e, Event::Fallen { .. }));
                if down_at.is_none() && f.events().contains(&Event::Down { hero: id }) {
                    down_at = Some(t);
                }
            }
            let h = &f.heroes()[id as usize];
            unfallen += !fell as u32;
            if down_at.is_none() {
                survived += 1;
            } else {
                first_down.push(down_at.unwrap() / TICK_HZ);
            }
            kills += f.counters().0;
            levels += h.draws + h.owed as u32;
        }
        println!(
            "{:<8} never downed {survived}/{seeds}  never fallen (PHOENIX ASH) {unfallen}/{seeds}  kills/run {}  draws {}  first downs (s) {:?}",
            CLASSES[class as usize].name,
            kills / seeds,
            levels / seeds as u32,
            first_down
        );
    }
}

// ---- pace: kills a class-level hero makes alone in each field

/// One class bot of `class` at `level`, alone in `field` on the ring of her level, for `minutes`: (kills, the
/// time-weighted damage percent of her field level).
fn pace_run(field: u8, class: u8, level: u8, seed: u64, minutes: u32) -> (u64, u64) {
    let row = &FIELDS[field as usize];
    let span = (row.top - row.bottom).max(1) as i32;
    let ring = ((row.top - level) as i32 * LEVEL_RIM_PX / span).clamp(1_500, 7_200);
    let mut f = Field::open(field, 500 + seed, Config { monsters: 4_096, threads: 1 });
    let mut s = Sheet::bench(class, HUMAN, level);
    s.deck = (1..=owned_cards(level).min(DECK_SIZE as u8)).collect();
    let c = FIELD / 2;
    let r = |p: &(i32, i32)| ((((p.0 - c) as i64).pow(2) + ((p.1 - c) as i64).pow(2)) as f64).sqrt() / SUB as f64;
    let w = *f.terrain().waystones.iter().min_by_key(|p| (r(p) - ring as f64).abs() as i64).unwrap();
    let id = f.join(&s, &Outing::new(), w.0, w.1);
    let mut bot = bots::Bot::new(id, seed, bots::Plan::alone(ring));
    let ticks = minutes * 60 * TICK_HZ;
    let mut dmg = 0u64;
    for _ in 0..ticks {
        let input = bot.act(&f);
        f.step(&[input]);
        dmg += field_dmg_pct(&f, id);
    }
    (f.counters().0, dmg / ticks as u64)
}

/// The damage percent of the outing (100: there is no field level since 27 Nov; the pre-change run printed
/// `100 + 4 x (field level - 1)`, at most 260, here, see rules_built.md).
fn field_dmg_pct(_f: &Field, _id: u16) -> u64 {
    100
}

fn pace() {
    let seeds = arg(2, 3);
    let minutes = arg(3, 5) as u32;
    println!("pace: one class bot alone on the ring of her level, {seeds} seeds, {minutes} min; kills/run (field-level dmg %)");
    println!("field class-level | KNIGHT MAGE ARCHER PRIEST PALADIN | mean kills");
    let mut jobs = Vec::new();
    for field in 0..6u8 {
        let row = &FIELDS[field as usize];
        for level in [row.bottom.max(10), (row.bottom.max(10) + row.top) / 2] {
            for class in 1..6u8 {
                jobs.push((field, level, class));
            }
        }
    }
    let threads = std::env::var("THREADS").ok().and_then(|s| s.parse().ok()).unwrap_or(2usize);
    let next = std::sync::atomic::AtomicUsize::new(0);
    let out = std::sync::Mutex::new(vec![(0u64, 0u64); jobs.len()]);
    std::thread::scope(|sc| {
        for _ in 0..threads {
            sc.spawn(|| loop {
                let j = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                let Some(&(field, level, class)) = jobs.get(j) else { break };
                let (mut k, mut d) = (0, 0);
                for seed in 0..seeds {
                    let (a, b) = pace_run(field, class, level, seed, minutes);
                    k += a;
                    d += b;
                }
                out.lock().unwrap()[j] = (k / seeds, d / seeds);
            });
        }
    });
    let out = out.into_inner().unwrap();
    for (n, chunk) in out.chunks(5).enumerate() {
        let (field, level, _) = jobs[n * 5];
        let mut line = format!("{field} {level:>5} |");
        for &(k, d) in chunk {
            line += &format!(" {k:>5} ({d}%)");
        }
        line += &format!(" | {}", chunk.iter().map(|x| x.0).sum::<u64>() / 5);
        println!("{line}");
    }
}

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("phases") => phases(),
        Some("killtime") => killtime(),
        Some("kite") => kite(),
        Some("pace") => pace(),
        _ => eprintln!("measure phases FIELD THREADS [TICKS] [WARMUP] | killtime | kite CLASS_LEVEL SEEDS MINUTES"),
    }
}
