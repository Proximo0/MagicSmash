use realm_core::*;
use std::time::Instant;
fn main() {
    for field in 0..6u8 {
        for seed in 1..13u64 {
            let t0 = Instant::now();
            let f = Field::open(field, seed, Config { monsters: 100, threads: 1 });
            let walls = f.terrain().map.iter().filter(|&&c| c & tables::WALL != 0).count();
            println!("field {field} seed {seed} walls {:.1}% check {:?} {:?}", walls as f64 * 100.0 / CELLS as f64, check_terrain(f.terrain()), t0.elapsed());
        }
    }
}
