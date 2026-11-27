//! Shared helpers for the core tests: quiet fields (no births), bare sheets, placed monsters.
#![allow(dead_code)]

pub use realm_core::tables::*;
pub use realm_core::*;

/// A field with births off and one thread.
pub fn quiet(field: u8) -> Field {
    let mut f = Field::open(field, 1, Config { monsters: 4096, threads: 1 });
    f.set_births(false);
    f
}

/// The centre of an open square of `cells` cells nearest the heart (sub units).
pub fn spot(f: &Field, cells: i32) -> (i32, i32) {
    let t = f.terrain();
    let c = CELLS_W as i32 / 2;
    for r in 0..c {
        for oy in -r..=r {
            for ox in -r..=r {
                if ox.abs() != r && oy.abs() != r {
                    continue;
                }
                let (cx, cy) = (c + ox, c + oy);
                if cx - cells / 2 < 0 || cy - cells / 2 < 0 || cx + cells / 2 >= CELLS_W as i32 || cy + cells / 2 >= CELLS_W as i32 {
                    continue;
                }
                let mut ok = true;
                'scan: for y in cy - cells / 2..=cy + cells / 2 {
                    for x in cx - cells / 2..=cx + cells / 2 {
                        if t.map[(y * CELLS_W as i32 + x) as usize] & (WALL | MIRE | ROAD) != 0 {
                            ok = false;
                            break 'scan;
                        }
                    }
                }
                if ok {
                    let half = 1 << (CELL_SHIFT - 1);
                    return ((cx << CELL_SHIFT) + half, (cy << CELL_SHIFT) + half);
                }
            }
        }
    }
    panic!("no open square of {cells} cells");
}

/// A sheet with no points and no gear (race stats only), deck and belt empty.
pub fn bare(class: u8, level: u8) -> Sheet {
    let mut s = Sheet::bench(class, HUMAN, level);
    s.points = [0; 6];
    s.gear = [0; 6];
    s.deck = Vec::new();
    s.belt = [(P_NONE, 0); BELT];
    s
}

pub fn add(f: &mut Field, s: &Sheet, x: i32, y: i32) -> u16 {
    f.join(s, &Outing::new(), x, y)
}

pub fn px(v: i32) -> i32 {
    v * SUB
}

/// Steps with every hero's input.
pub fn step(f: &mut Field, inputs: &[u16]) {
    f.step(inputs);
}

pub fn idle(f: &mut Field, n: u32) {
    for _ in 0..n {
        f.step::<u16>(&[]);
    }
}

/// Steps until the flow field has been built around the heroes (no input).
pub fn warm(f: &mut Field) {
    idle(f, 12);
}

pub fn mon(f: &mut Field, kind: u8, level: u8, x: i32, y: i32) -> u32 {
    f.place_monster(kind, level, 0, x, y).expect("room")
}

/// Keeps a hero unhurt (AEGIS) so a test can watch her.
pub fn guard(f: &mut Field, id: u16) {
    f.hero_mut(id).fx[FX_AEGIS as usize] = 1_000;
}

/// Events of a kind in the last tick.
pub fn count(f: &Field, rank: u8) -> usize {
    f.events().iter().filter(|e| e.rank() == rank).count()
}

pub const GRANT: u8 = 0;
pub const DRAW: u8 = 1;
pub const PICK: u8 = 2;
pub const SKILL: u8 = 3;
pub const POTION: u8 = 4;
pub const DOWN: u8 = 5;
pub const RAISE: u8 = 6;
pub const FALLEN: u8 = 7;
pub const BANK: u8 = 8;
pub const LEAVE: u8 = 9;
pub const KILL: u8 = 10;
pub const XP: u8 = 11;

/// Kind id by name.
pub fn kind(name: &str) -> u8 {
    KINDS.iter().position(|k| k.name == name).unwrap_or_else(|| panic!("no kind {name}")) as u8
}

pub fn dist(ax: i32, ay: i32, bx: i32, by: i32) -> i64 {
    let (dx, dy) = ((ax - bx) as i64, (ay - by) as i64);
    ((dx * dx + dy * dy) as u64).isqrt() as i64
}
