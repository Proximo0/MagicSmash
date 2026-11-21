use realm_core::*;
fn main() {
    let mut f = Field::open(0, 7, Config { monsters: 3000, threads: 1 });
    for i in 0..20 {
        let s = Sheet::bench((i % 6) as u8, 0, 12);
        f.join(&s, &Outing::new(), FIELD / 2 + (i % 5 - 2) * 40 * SUB, FIELD / 2 + (i / 5 - 2) * 40 * SUB);
    }
    let mut credits = 0; let mut kills = 0;
    for _ in 0..400 {
        f.step(&[0u16; 20]);
        for e in f.events() { if let Event::Kill { count, .. } = e { credits += *count as u32; kills += 1; } }
    }
    for h in f.heroes() { println!("class {} lvl {} xp {} coin {} hp {}/{} active {} attacks {}", h.class, h.level, h.xp, h.coin, h.health, h.max_health, h.active, h.attacks); }
    println!("kills {kills} credits {credits}");
}
