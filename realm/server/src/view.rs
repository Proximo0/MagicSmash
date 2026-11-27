//! What one player is sent: the interest box and the players and monsters in it, in world px.

use realm_core::{grid_box, Field, CELLS_W, CELL_SHIFT, FIELD_PX, GRID_MARGIN, PCELLS_W, PCELL_SHIFT, SUB};

pub const NEAR_PLAYERS: usize = 200;
pub const CROWD_MAX: usize = 1000;
pub const MONSTERS_MAX: usize = 1500;
pub const BOX_MARGIN: i32 = 64;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MRec {
    pub id: u32,
    pub x: u16,
    pub y: u16,
    /// `kind` 3 bits | health in eighths 3 bits | elite 1 bit (the v0 4th byte).
    pub attrs: u8,
    pub hurt: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PRec {
    pub id: u16,
    pub x: u16,
    pub y: u16,
    /// `class | race << 3`.
    pub cr: u8,
    /// bit 0 faces left, bit 1 moving, bit 2 hurt this tick.
    pub flags: u8,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct View {
    pub tick: u32,
    pub ox: i32,
    pub oy: i32,
    pub me_x: u16,
    pub me_y: u16,
    pub health: u16,
    /// Her class level (the field has no level of its own).
    pub level: u16,
    pub field_players: u32,
    pub field_monsters: u32,
    pub tick_time: u16,
    /// Sorted by id.
    pub players: Vec<PRec>,
    /// World px.
    pub crowd: Vec<(u16, u16)>,
    /// Sorted by id.
    pub monsters: Vec<MRec>,
}

/// The interest box size in px for a zoom: the view times zoom plus the margin on every side.
pub fn box_size(zoom: u8) -> (i32, i32) {
    let z = match zoom {
        2 => 2,
        4 => 4,
        _ => 1,
    };
    (realm_core::VIEW_W * z + 2 * BOX_MARGIN, realm_core::VIEW_H * z + 2 * BOX_MARGIN)
}

pub fn hp_eighths(hp: u32, max: u32) -> u8 {
    if hp == 0 || max == 0 {
        return 0;
    }
    (((hp as u64 * 8 - 1) / max as u64).min(7)) as u8
}

/// Scratch reused across views so a thousand of them a tick do not allocate.
#[derive(Default)]
pub struct Scratch {
    near: Vec<(i64, u32)>,
}

/// Builds player `id`'s view. `tick_time` is the last tick's server time in 1/100 ms.
pub fn build(f: &Field, id: u16, zoom: u8, tick_time: u16, s: &mut Scratch, out: &mut View) {
    let p = &f.players()[id as usize];
    let (w, h) = box_size(zoom);
    let px = p.x / SUB;
    let py = p.y / SUB;
    let ox = (px - w / 2).clamp(0, FIELD_PX - w);
    let oy = (py - h / 2).clamp(0, FIELD_PX - h);
    out.tick = f.tick();
    out.ox = ox;
    out.oy = oy;
    out.me_x = (px - ox) as u16;
    out.me_y = (py - oy) as u16;
    out.health = p.health.min(u16::MAX as u32) as u16;
    out.level = p.sheet.class_level as u16;
    out.field_players = f.player_count();
    out.field_monsters = f.monster_count();
    out.tick_time = tick_time;
    let (bx0, by0, bx1, by1) = (ox * SUB, oy * SUB, (ox + w) * SUB, (oy + h) * SUB);

    // Monsters: every live one in the box, the nearest 1 500 if more, sent by id.
    let m = f.monsters();
    s.near.clear();
    let near = &mut s.near;
    grid_box(f.grid(), CELLS_W, CELL_SHIFT, bx0 - GRID_MARGIN, by0 - GRID_MARGIN, bx1 + GRID_MARGIN, by1 + GRID_MARGIN, |i| {
        let k = i as usize;
        let (x, y) = (m.x[k], m.y[k]);
        if m.hp[k] > 0 && x >= bx0 && x < bx1 && y >= by0 && y < by1 {
            let dx = (x - p.x) as i64;
            let dy = (y - p.y) as i64;
            near.push((dx * dx + dy * dy, i));
        }
    });
    if near.len() > MONSTERS_MAX {
        near.select_nth_unstable(MONSTERS_MAX - 1);
        near.truncate(MONSTERS_MAX);
    }
    near.sort_unstable_by_key(|&(_, i)| i);
    out.monsters.clear();
    for &(_, i) in near.iter() {
        let k = i as usize;
        let kind = m.kind[k];
        out.monsters.push(MRec {
            id: i,
            x: (m.x[k] / SUB) as u16,
            y: (m.y[k] / SUB) as u16,
            attrs: (kind & 7) | hp_eighths(m.hp[k], m.max_hp(k)) << 3 | (m.is_elite(k) as u8) << 6,
            hurt: m.hurt[k] != 0,
        });
    }

    // Players: the nearest 200 in the box (never me) by id, then up to 1 000 more as the crowd.
    let ps = f.players();
    near.clear();
    grid_box(f.player_grid(), PCELLS_W, PCELL_SHIFT, bx0, by0, bx1, by1, |i| {
        let q = &ps[i as usize];
        if i != id as u32 && q.alive() && q.x >= bx0 && q.x < bx1 && q.y >= by0 && q.y < by1 {
            let dx = (q.x - p.x) as i64;
            let dy = (q.y - p.y) as i64;
            near.push((dx * dx + dy * dy, i));
        }
    });
    let keep = NEAR_PLAYERS + CROWD_MAX;
    if near.len() > keep {
        near.select_nth_unstable(keep - 1);
        near.truncate(keep);
    }
    if near.len() > NEAR_PLAYERS {
        near.select_nth_unstable(NEAR_PLAYERS - 1);
    }
    let split = near.len().min(NEAR_PLAYERS);
    near[..split].sort_unstable_by_key(|&(_, i)| i);
    near[split..].sort_unstable_by_key(|&(_, i)| i);
    out.players.clear();
    out.crowd.clear();
    for (n, &(_, i)) in near.iter().enumerate() {
        let q = &ps[i as usize];
        let (x, y) = ((q.x / SUB) as u16, (q.y / SUB) as u16);
        if n < split {
            out.players.push(PRec {
                id: i as u16,
                x,
                y,
                cr: q.class | q.race << 3,
                flags: q.facing_left as u8 | (q.moving as u8) << 1 | (q.hurt as u8) << 2,
            });
        } else {
            out.crowd.push((x, y));
        }
    }
}
