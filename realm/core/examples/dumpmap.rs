use realm_core::*;
fn main() {
    let out = std::env::args().nth(1).unwrap();
    let mut all = Vec::new();
    for field in 0..6u8 {
        let f = Field::open(field, 1, Config { monsters: 10, threads: 1 });
        all.extend_from_slice(&f.terrain().map);
        for s in f.terrain().sites() { all.extend_from_slice(&((s.0 >> CELL_SHIFT) as u16).to_le_bytes()); all.extend_from_slice(&((s.1 >> CELL_SHIFT) as u16).to_le_bytes()); }
    }
    std::fs::write(out, all).unwrap();
}
