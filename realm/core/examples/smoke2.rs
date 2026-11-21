use realm_core::*;
use std::time::Instant;
fn main() {
    let field: u8 = std::env::args().nth(1).map_or(0, |s| s.parse().unwrap());
    let heroes: i32 = std::env::args().nth(2).map_or(60, |s| s.parse().unwrap());
    let mons: u32 = std::env::args().nth(3).map_or(5000, |s| s.parse().unwrap());
    let threads: usize = std::env::args().nth(4).map_or(1, |s| s.parse().unwrap());
    let ticks: u32 = std::env::args().nth(5).map_or(400, |s| s.parse().unwrap());
    let mut f = Field::open(field, 7, Config { monsters: mons, threads });
    let lvl = tables::FIELDS[field as usize].bottom;
    for i in 0..heroes {
        let class = (i % 6) as u8 | if i % 12 >= 6 { 8 } else { 0 };
        let s = Sheet::bench(class, (i % 4) as u8, lvl.max(45));
        let x = FIELD / 2 + (i % 20 - 10) * 30 * SUB;
        let y = FIELD / 2 + (i / 20 - 5) * 30 * SUB;
        f.join(&s, &Outing::new(), x, y);
    }
    let mut counts = [0u32; 12];
    let t0 = Instant::now();
    for t in 0..ticks {
        let inp: Vec<u16> = (0..heroes as u32).map(|i| {
            let r = (t / 20).wrapping_mul(2_654_435_761) ^ i.wrapping_mul(40_503);
            let dir = ((r >> 7) % 9) as u8;
            let b0 = dir | if (r >> 3) % 5 == 0 { 0x70 } else { 0 };
            let b1 = if t % 40 == (i % 40) { 1 } else { 0 } | if t % 200 == 3 { 0x08 } else { 0 };
            input(b0, b1)
        }).collect();
        f.step(&inp);
        for e in f.events() { counts[e.rank() as usize] += 1; }
    }
    let el = t0.elapsed();
    let (k, s, d) = f.counters();
    let lv: u32 = f.heroes().iter().map(|h| h.level as u32).sum();
    println!("field {field} {}x{} ticks {ticks} {:.2} ms/tick kills {k} births {s} downs {d} recycled {} avg level {} events {:?} hash {:016x}", f.player_count(), f.monster_count(), el.as_secs_f64()*1000.0/ticks as f64, f.recycled(), lv / heroes.max(1) as u32, counts, f.hash());
}
