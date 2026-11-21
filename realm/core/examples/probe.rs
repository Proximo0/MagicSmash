use realm_core::*;
fn main() {
    let n: u32 = std::env::args().nth(1).unwrap().parse().unwrap();
    let mut f = Field::new(1, Config { monsters: 100000, threads: 1 });
    let mut s = 7u64;
    for _ in 0..n { let r = rng_next(&mut s); f.join(0,0, ((r%16000) as i32+192)*SUB, (((r>>20)%16000) as i32+192)*SUB); }
    for _ in 0..40 { f.step(&[]); if f.tick()%5==0 { println!("t={} alive={} spawned={}", f.tick(), f.monster_count(), f.last_spawns().len()); } }
}
