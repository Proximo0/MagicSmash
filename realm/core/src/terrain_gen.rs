//! The six terrain generators, one per terrain rule (rules section 6).

use crate::CELLS;
use crate::CELLS_W;
use crate::tables::*;
use crate::terrain::{Gen, W, near_site};

fn road_line(g: &mut Gen, cells: &[(i32, i32)]) {
    let gate = cells[0];
    let heart = cells[cells.len() - 1];
    let north = (heart.0 + g.range(-40, 40), 8);
    g.path(gate, heart, 2, 24, 6, ROAD, 0);
    g.path(heart, north, 2, 24, 5, ROAD, 0);
}

pub(crate) fn gen_road(g: &mut Gen, cells: &[(i32, i32)]) {
    g.hedges(700, 8, 8, W - 24, W - 24);
    for _ in 0..70 {
        let (x, y, w, h) = (g.range(8, W - 30), g.range(8, W - 30), g.range(8, 16), g.range(8, 16));
        if !near_site(cells, x + w / 2, y + h / 2, 24) {
            g.ruin(x, y, w, h);
        }
    }
    // The burnt chapel: a larger ruin near the heart's rim.
    let (hx, hy) = cells[cells.len() - 1];
    g.ruin(hx + 40, hy - 50, 22, 16);
    road_line(g, cells);
    // The road is clear of hedges.
    for c in 0..CELLS {
        if g.map[c] & ROAD != 0 {
            g.map[c] &= !WALL;
        }
    }
}

pub(crate) fn gen_wood(g: &mut Gen, cells: &[(i32, i32)]) {
    g.map.fill(WALL);
    let n = cells.len();
    for &(x, y) in cells {
        let r = g.range(9, 14);
        g.disc(x, y, r, 0, WALL);
    }
    let heart = cells[n - 1];
    g.disc(heart.0, heart.1, 22, 0, WALL);
    // Paths 6 to 10 cells wide: gate -> edge waystones -> middle -> rim -> heart, a ring through the
    // altars, and side paths to random clearings.
    let order = [0usize, 1, 4, 7, 14, 2, 5, 3, 6];
    for w in order.windows(2) {
        let r = g.range(WOOD_PATH_MIN, WOOD_PATH_MAX) / 2;
        g.path(cells[w[0]], cells[w[1]], r, 30, 4, 0, WALL);
    }
    for k in 0..6 {
        let (a, b) = (cells[8 + k], cells[8 + (k + 1) % 6]);
        let r = g.range(WOOD_PATH_MIN, WOOD_PATH_MAX) / 2;
        g.path(a, b, r, 30, 3, 0, WALL);
    }
    for k in 0..7 {
        let r = g.range(WOOD_PATH_MIN, WOOD_PATH_MAX) / 2;
        g.path(cells[1 + k], heart, r, 40, 4, 0, WALL);
    }
    for _ in 0..40 {
        let (x, y) = (g.range(20, W - 21), g.range(20, W - 21));
        let r = g.range(6, 12);
        g.disc(x, y, r, 0, WALL);
        let to = *cells.iter().min_by_key(|&&(sx, sy)| ((sx - x).pow(2) + (sy - y).pow(2), sx, sy)).unwrap_or(&heart);
        let pr = g.range(WOOD_PATH_MIN, WOOD_PATH_MAX) / 2;
        g.path((x, y), to, pr, 20, 3, 0, WALL);
    }
}

pub(crate) fn gen_marsh(g: &mut Gen, cells: &[(i32, i32)]) {
    g.blobs(260, 4, 14, MIRE);
    g.blobs(70, 10, 30, DARK);
    for _ in 0..40 {
        let (x, y, w, h) = (g.range(8, W - 30), g.range(8, W - 30), g.range(8, 14), g.range(8, 14));
        if !near_site(cells, x + w / 2, y + h / 2, 24) {
            g.ruin(x, y, w, h);
        }
    }
}

pub(crate) fn gen_peaks(g: &mut Gen, cells: &[(i32, i32)]) {
    // East-west ridges every 40 to 60 cells, 3 thick, wandering slowly, with passes 6 cells wide.
    let mut y0 = g.range(30, 50);
    while y0 < W - 30 {
        let mut y = y0;
        let mut next_pass = g.range(20, 60);
        let mut x = 0;
        while x < W {
            if x == next_pass {
                x += PEAKS_PASS;
                next_pass = x + g.range(40, 90);
                continue;
            }
            if x % 12 == 0 && g.r(3) == 0 {
                y = (y + g.range(-1, 1)).clamp(y0 - 10, y0 + 10);
            }
            g.rect(x, y, x, y + 2, WALL, 0);
            x += 1;
        }
        y0 += g.range(40, 60);
    }
    // Boulders.
    for _ in 0..120 {
        let (x, y, r) = (g.r(W), g.r(W), g.range(1, 3));
        if !near_site(cells, x, y, 12) {
            g.disc(x, y, r, WALL, 0);
        }
    }
}

const ROOM: i32 = 32;

pub(crate) fn gen_tower(g: &mut Gen, _cells: &[(i32, i32)]) {
    g.map.fill(WALL);
    let n = W / ROOM;
    // Room interiors leave walls 2 thick between rooms.
    for ry in 0..n {
        for rx in 0..n {
            g.rect(rx * ROOM + 1, ry * ROOM + 1, rx * ROOM + ROOM - 2, ry * ROOM + ROOM - 2, 0, WALL);
        }
    }
    // A spanning tree of doors (a depth-first maze), then extra doors and long corridors.
    let mut seen = vec![false; (n * n) as usize];
    let mut stack = vec![(n / 2, n - 1)];
    seen[((n - 1) * n + n / 2) as usize] = true;
    while let Some(&(x, y)) = stack.last() {
        let mut opts = Vec::new();
        for (ox, oy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let (nx, ny) = (x + ox, y + oy);
            if nx >= 0 && ny >= 0 && nx < n && ny < n && !seen[(ny * n + nx) as usize] {
                opts.push((nx, ny));
            }
        }
        if opts.is_empty() {
            stack.pop();
            continue;
        }
        let (nx, ny) = opts[g.r(opts.len() as i32) as usize];
        seen[(ny * n + nx) as usize] = true;
        door(g, x, y, nx, ny);
        stack.push((nx, ny));
    }
    for _ in 0..n * n / 3 {
        let (x, y) = (g.r(n), g.r(n));
        if g.r(2) == 0 && x + 1 < n {
            door(g, x, y, x + 1, y);
        } else if y + 1 < n {
            door(g, x, y, x, y + 1);
        }
    }
    for _ in 0..4 {
        let k = g.r(n);
        let horizontal = g.r(2) == 0;
        let (a, b) = (g.r(n / 2), n / 2 + g.r(n / 2));
        if horizontal {
            g.rect(a * ROOM + 4, k * ROOM + 12, b * ROOM + ROOM - 4, k * ROOM + 19, 0, WALL);
        } else {
            g.rect(k * ROOM + 12, a * ROOM + 4, k * ROOM + 19, b * ROOM + ROOM - 4, 0, WALL);
        }
    }
}

fn door(g: &mut Gen, x: i32, y: i32, nx: i32, ny: i32) {
    let off = g.range(4, ROOM - 4 - TOWER_DOOR);
    if nx != x {
        let wx = x.max(nx) * ROOM;
        g.rect(wx - 2, y * ROOM + off, wx + 1, y * ROOM + off + TOWER_DOOR - 1, 0, WALL);
    } else {
        let wy = y.max(ny) * ROOM;
        g.rect(x * ROOM + off, wy - 2, x * ROOM + off + TOWER_DOOR - 1, wy + 1, 0, WALL);
    }
}

pub(crate) fn gen_edge(g: &mut Gen, cells: &[(i32, i32)]) {
    g.map.fill(WALL);
    let mut isles: Vec<(i32, i32)> = cells.to_vec();
    for _ in 0..12 {
        isles.push((g.range(40, W - 41), g.range(40, W - 41)));
    }
    for (k, &(x, y)) in isles.iter().enumerate() {
        let r = if k == cells.len() - 1 { 30 } else { g.range(14, 26) };
        g.disc(x, y, r, 0, WALL);
    }
    // Bridges 8 cells wide along a spanning tree (nearest joined island first), plus a few more.
    let bridge_r = EDGE_BRIDGE / 2;
    let mut joined = vec![false; isles.len()];
    joined[0] = true;
    for _ in 1..isles.len() {
        let mut best = (i64::MAX, 0, 0);
        for (a, &ja) in joined.iter().enumerate() {
            if !ja {
                continue;
            }
            for (b, &jb) in joined.iter().enumerate() {
                if jb {
                    continue;
                }
                let d = ((isles[a].0 - isles[b].0) as i64).pow(2) + ((isles[a].1 - isles[b].1) as i64).pow(2);
                if d < best.0 {
                    best = (d, a, b);
                }
            }
        }
        joined[best.2] = true;
        g.line(isles[best.1], isles[best.2], bridge_r, ROAD, WALL);
    }
    for _ in 0..6 {
        let (a, b) = (g.r(isles.len() as i32) as usize, g.r(isles.len() as i32) as usize);
        if a != b {
            g.line(isles[a], isles[b], bridge_r, ROAD, WALL);
        }
    }
    // All the rules at once on the islands: mire, dark, hedges.
    let open: Vec<usize> = (0..CELLS).filter(|&c| g.map[c] & WALL == 0).collect();
    for _ in 0..60 {
        let c = open[g.r(open.len() as i32) as usize];
        let (x, y, r) = ((c % CELLS_W) as i32, (c / CELLS_W) as i32, g.range(3, 9));
        g.disc(x, y, r, MIRE, 0);
    }
    for _ in 0..30 {
        let c = open[g.r(open.len() as i32) as usize];
        let (x, y, r) = ((c % CELLS_W) as i32, (c / CELLS_W) as i32, g.range(8, 20));
        g.disc(x, y, r, DARK, 0);
    }
    for _ in 0..80 {
        let c = open[g.r(open.len() as i32) as usize];
        let (x, y) = ((c % CELLS_W) as i32, (c / CELLS_W) as i32);
        if !near_site(cells, x, y, 12) && g.map[c] & ROAD == 0 {
            let len = g.range(4, 10);
            g.rect(x, y, x + len, y, WALL, 0);
        }
    }
}
