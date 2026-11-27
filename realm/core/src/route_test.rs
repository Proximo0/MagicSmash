//! Monster routing in tight spaces (rules 4, "Routing"): a crowd behind a corridor one or two cells wide with two
//! corners, a hero beyond it. Counts monsters stuck (no progress on the flow in `STUCK_TICKS`) and monsters
//! overlapping a wall (any point within `BODY_PX` of their centre on a wall cell), sampled every `SAMPLE` ticks.

use crate::tables::*;
use crate::terrain::Terrain;
use crate::{CELL_SHIFT, CELLS, CELLS_W, Config, Field, Outing, SUB, Sheet, cell_of};

const SAMPLE: u32 = 10;
const STUCK_TICKS: u32 = 40;
const BODY_PX: i32 = 8;
const CROWD: usize = 300;
const TICKS: u32 = 900;

fn corridor_map(w: i32) -> Vec<u8> {
    let mut map = vec![WALL; CELLS];
    let mut open = |x0: i32, y0: i32, x1: i32, y1: i32| {
        for y in y0..=y1 {
            for x in x0..=x1 {
                map[y as usize * CELLS_W + x as usize] = 0;
            }
        }
    };
    // Room A (the crowd), a corridor east, a corner north, a corner east, room B (the hero).
    open(120, 235, 135, 250);
    open(136, 242, 155, 241 + w);
    open(155 - w + 1, 222, 155, 241 + w);
    open(155, 222, 165, 221 + w);
    open(166, 212, 180, 232);
    map
}

fn corridor_terrain(w: i32) -> Terrain {
    let map = corridor_map(w);
    let edges = crate::terrain::edges_of(&map);
    let c = |x: i32, y: i32| ((x << CELL_SHIFT) + (1 << (CELL_SHIFT - 1)), (y << CELL_SHIFT) + (1 << (CELL_SHIFT - 1)));
    Terrain { field: 0, map, gate: c(125, 240), waystones: [c(125, 240); 7], altars: [c(125, 240); 6], heart: c(175, 222), quiet: Vec::new(), hash: 1, edges }
}

pub struct Route {
    pub stuck: u64,
    pub overlaps: u64,
    pub arrived: u64,
    pub inside_wall: u64,
}

pub fn run_corridor(w: i32) -> Route {
    let mut f = Field::open_with(0, 7, Config { monsters: 2_000, threads: 1 }, corridor_terrain(w));
    f.set_births(false);
    let (hx, hy) = ((176 << CELL_SHIFT) + 16 * SUB, (222 << CELL_SHIFT) + 16 * SUB);
    let id = f.join(&Sheet::bench(0, 0, 1), &Outing::new(), hx, hy);
    for k in 0..CROWD {
        let (x, y) = (120 + (k % 16) as i32, 235 + (k / 16) as i32 * 16 / 19);
        f.place_monster(2, 1, 0, (x << CELL_SHIFT) + 16 * SUB, (y << CELL_SHIFT) + 16 * SUB);
    }
    let n = f.monsters().hp.len();
    let mut hist: Vec<Vec<u16>> = Vec::new();
    let mut r = Route { stuck: 0, overlaps: 0, arrived: 0, inside_wall: 0 };
    let wall = |t: &Terrain, x: i32, y: i32| t.wall(x, y);
    for tick in 1..=TICKS {
        {
            // The hero cannot fall and does not strike: the crowd is only measured.
            let h = f.hero_mut(id);
            h.max_health = 1_000_000_000;
            h.health = 1_000_000_000;
            h.charge = 0;
        }
        f.step(&[0u16]);
        if tick % SAMPLE != 0 {
            continue;
        }
        let m = f.monsters();
        let t = f.terrain();
        let mut now = vec![u16::MAX; n];
        for i in 0..n {
            if m.hp[i] == 0 {
                continue;
            }
            let (x, y) = (m.x[i], m.y[i]);
            if wall(t, x, y) {
                r.inside_wall += 1;
            }
            let b = BODY_PX * SUB;
            if [(b, 0), (-b, 0), (0, b), (0, -b), (b * 7 / 10, b * 7 / 10), (-b * 7 / 10, b * 7 / 10), (b * 7 / 10, -b * 7 / 10), (-b * 7 / 10, -b * 7 / 10)]
                .iter()
                .any(|&(ox, oy)| wall(t, x + ox, y + oy))
            {
                r.overlaps += 1;
            }
            let d = f.flow_dist(cell_of(x, y));
            now[i] = d;
            // Stuck: no step closer on the flow over the window, while still more than 3 cells out.
            let back = (STUCK_TICKS / SAMPLE) as usize;
            if hist.len() >= back && d != u16::MAX && d > 100 {
                let old = hist[hist.len() - back][i];
                if old != u16::MAX && d >= old {
                    r.stuck += 1;
                }
            }
        }
        hist.push(now);
    }
    let m = f.monsters();
    for i in 0..n {
        if m.hp[i] > 0 && (m.x[i] >> CELL_SHIFT) >= 156 && (m.y[i] >> CELL_SHIFT) <= 232 {
            r.arrived += 1;
        }
    }
    r
}

#[test]
fn a_crowd_streams_through_corridors_one_and_two_cells_wide() {
    for w in [1, 2] {
        let r = run_corridor(w);
        println!(
            "ROUTE corridor {w} cell(s): {} stuck samples, {} wall overlaps, {} inside a wall, {} of {CROWD} through in {TICKS} ticks",
            r.stuck, r.overlaps, r.inside_wall, r.arrived
        );
        assert_eq!(r.inside_wall, 0, "no monster stands in a wall");
        // Before the routing of rules 4 (no step back, bodies off the walls, no straight dash round a corner) the
        // one-cell corridor gave 2,767 stuck samples, 1,026 wall overlaps and 109 through; two cells 174, 5 and 130.
        assert_eq!(r.overlaps, 0, "{w} cell(s): no body rubs a wall");
        let (stuck_max, through_min) = if w == 1 { (1_500, 140) } else { (160, 110) };
        assert!(r.stuck <= stuck_max && r.arrived >= through_min, "{w} cell(s): {} stuck, {} through", r.stuck, r.arrived);
    }
}
