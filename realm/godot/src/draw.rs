//! Bulk reads of the field for drawing, with no Godot types so they test as plain Rust.
//!
//! `monsters_in` and `players_in` are the plain reads: ints, sorted by id. `DrawState` builds the drawing
//! fast path: a MultiMesh buffer per call, sorted by depth (feet lower on screen drawn later), where each
//! figure carries the offset back to where it stood at the previous call so the shader can blend between
//! the 20 ticks a second at any frame rate with no per-figure work in GDScript.

use realm_core::{Field, SUB};

/// A rectangle in 1/256 px, end exclusive.
#[derive(Clone, Copy, Debug)]
pub struct SubRect {
    pub x0: i32,
    pub y0: i32,
    pub x1: i32,
    pub y1: i32,
}

impl SubRect {
    fn contains(&self, x: i32, y: i32) -> bool {
        x >= self.x0 && x < self.x1 && y >= self.y0 && y < self.y1
    }
}

pub const MON_ELITE: i32 = 1;
pub const MON_HURT: i32 = 2;
pub const PLY_LEFT: i32 = 1;
pub const PLY_MOVING: i32 = 2;
pub const PLY_HURT: i32 = 4;
pub const PLY_DEAD: i32 = 8;
pub const PLY_ME: i32 = 16;

/// The stand-in pictures: eight monster frames shared by the core's kinds, and five classes by four races
/// (a NOVICE is drawn as the first class) until the field client loads the real sheets by name.
const MONSTER_FRAMES: usize = 8;
const HERO_CLASSES: usize = 5;
const HERO_RACES: usize = 4;

fn monster_frame(kind: u8) -> usize {
    usize::from(kind) % MONSTER_FRAMES
}

fn hero_frame(class: u8, race: u8) -> usize {
    (usize::from(class).max(1) - 1).min(HERO_CLASSES - 1) * HERO_RACES + usize::from(race).min(HERO_RACES - 1)
}

/// `id, x, y, picture, flags` for every live monster in `r`, by id.
pub fn monsters_in(f: &Field, r: SubRect) -> Vec<i32> {
    let m = f.monsters();
    let mut out = Vec::new();
    for i in 0..m.hp.len() {
        if m.hp[i] > 0 && r.contains(m.x[i], m.y[i]) {
            let flags = if m.is_elite(i) { MON_ELITE } else { 0 } | if m.hurt[i] != 0 { MON_HURT } else { 0 };
            out.extend_from_slice(&[i as i32, m.x[i], m.y[i], monster_frame(m.kind[i]) as i32, flags]);
        }
    }
    out
}

/// `id, x, y, class, race, flags` for every present player in `r`, by id.
pub fn players_in(f: &Field, r: SubRect, me: Option<u16>) -> Vec<i32> {
    let mut out = Vec::new();
    for (i, p) in f.players().iter().enumerate() {
        if p.present && r.contains(p.x, p.y) {
            let flags = [(p.facing_left, PLY_LEFT), (p.moving, PLY_MOVING), (p.hurt, PLY_HURT), (!p.alive(), PLY_DEAD), (me == Some(i as u16), PLY_ME)]
                .iter()
                .fold(0, |a, &(on, bit)| if on { a | bit } else { a });
            out.extend_from_slice(&[i as i32, p.x, p.y, (hero_frame(p.class, p.race) / 4) as i32, i32::from(p.race), flags]);
        }
    }
    out
}

/// Floats per figure in a draw buffer: a 2D transform (8), a colour (4), custom data (4: the offset back to
/// the previous position in px divided by the figure's scale, the atlas frame, a bob seed that is 0 for a
/// figure standing still).
pub const STRIDE: usize = 16;
/// A figure that moved farther than this (px) since the previous call is not blended: another monster took
/// the slot, or a player respawned.
pub const BLEND_MAX_PX: i32 = 48;
pub const ELITE_SCALE: f32 = 1.25;
const WHITE: [f32; 4] = [1.0, 1.0, 1.0, 1.0];
const HURT: [f32; 4] = [1.0, 0.3, 0.3, 1.0];
const ELITE: [f32; 4] = [1.0, 0.82, 0.3, 1.0];
const DEAD: [f32; 4] = [0.55, 0.55, 0.6, 0.45];
/// Bob seeds run 1..=BOB_SEEDS so neighbours bob out of step.
const BOB_SEEDS: usize = 31;

/// Where each id stood at the last call, and in which call.
#[derive(Default)]
struct Seen {
    x: Vec<i32>,
    y: Vec<i32>,
    call: Vec<u32>,
    now: u32,
}

impl Seen {
    fn begin(&mut self, ids: usize) {
        self.now += 1;
        if self.call.len() < ids {
            self.x.resize(ids, 0);
            self.y.resize(ids, 0);
            self.call.resize(ids, 0);
        }
    }

    /// The offset (px) from `x, y` back to where `id` stood at the previous call, or zero.
    fn back(&mut self, id: usize, x: i32, y: i32) -> (f32, f32) {
        let (dx, dy) = (self.x[id] - x, self.y[id] - y);
        let near = dx.abs().max(dy.abs()) <= BLEND_MAX_PX * SUB;
        let back = if self.call[id] + 1 == self.now && near { (dx as f32 / SUB as f32, dy as f32 / SUB as f32) } else { (0.0, 0.0) };
        (self.x[id], self.y[id], self.call[id]) = (x, y, self.now);
        back
    }
}

/// The previous positions behind the draw buffers.
#[derive(Default)]
pub struct DrawState {
    monsters: Seen,
    players: Seen,
    order: Vec<(i32, u32)>,
}

/// One figure into a draw buffer. The shader moves vertices before the instance's transform scales them, so
/// the offset back to the previous position goes in divided by the scale (a figure facing left has -1).
fn put(out: &mut Vec<f32>, x: i32, y: i32, sx: f32, sy: f32, tint: [f32; 4], back: (f32, f32), frame: usize, bob: usize) {
    let (fx, fy) = (x as f32 / SUB as f32, y as f32 / SUB as f32);
    out.extend_from_slice(&[sx, 0.0, 0.0, fx, 0.0, sy, 0.0, fy]);
    out.extend_from_slice(&tint);
    out.extend_from_slice(&[back.0 / sx, back.1 / sy, frame as f32, bob as f32]);
}

impl DrawState {
    /// Every live monster in `r`, deepest first: frame = kind, elites larger and gold, hurt ones red.
    pub fn monsters(&mut self, f: &Field, r: SubRect) -> Vec<f32> {
        let m = f.monsters();
        self.monsters.begin(m.hp.len());
        self.order.clear();
        for i in 0..m.hp.len() {
            if m.hp[i] > 0 && r.contains(m.x[i], m.y[i]) {
                self.order.push((m.y[i], i as u32));
            }
        }
        self.order.sort_unstable();
        let mut out = Vec::with_capacity(self.order.len() * STRIDE);
        for &(_, id) in &self.order {
            let i = id as usize;
            let elite = m.is_elite(i);
            let s = if elite { ELITE_SCALE } else { 1.0 };
            let tint = if m.hurt[i] != 0 { HURT } else if elite { ELITE } else { WHITE };
            let back = self.monsters.back(i, m.x[i], m.y[i]);
            put(&mut out, m.x[i], m.y[i], s, s, tint, back, monster_frame(m.kind[i]), 0);
        }
        out
    }

    /// Every present player in `r` but `me`, deepest first: frame = class * 4 + race, flipped when facing
    /// left, red when hurt, faded while dead.
    pub fn players(&mut self, f: &Field, r: SubRect, me: Option<u16>) -> Vec<f32> {
        let ps = f.players();
        self.players.begin(ps.len());
        self.order.clear();
        for (i, p) in ps.iter().enumerate() {
            if p.present && me != Some(i as u16) && r.contains(p.x, p.y) {
                self.order.push((p.y, i as u32));
            }
        }
        self.order.sort_unstable();
        let mut out = Vec::with_capacity(self.order.len() * STRIDE);
        for &(_, id) in &self.order {
            let i = id as usize;
            let p = &ps[i];
            let tint = if !p.alive() { DEAD } else if p.hurt { HURT } else { WHITE };
            let back = self.players.back(i, p.x, p.y);
            let sx = if p.facing_left { -1.0 } else { 1.0 };
            let bob = if p.moving && p.alive() { 1 + i % BOB_SEEDS } else { 0 };
            put(&mut out, p.x, p.y, sx, 1.0, tint, back, hero_frame(p.class, p.race), bob);
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use realm_core::{Config, Outing, Sheet, FIELD};

    /// Frames in the hero atlas (class x race).
    const HERO_FRAMES: usize = HERO_CLASSES * HERO_RACES;

    fn join(f: &mut Field, class: u8, race: u8, x: i32, y: i32) -> u16 {
        f.join(&Sheet::bench(1 + class, race, 1), &Outing::new(), x, y)
    }

    const ALL: SubRect = SubRect { x0: 0, y0: 0, x1: FIELD, y1: FIELD };

    fn busy_field() -> Field {
        let mut f = Field::new(9, Config { monsters: 3000, threads: 1 });
        for k in 0..6 {
            join(&mut f, k as u8 % 5, k as u8 % 4, FIELD / 2 + k * 40 * SUB, FIELD / 2);
        }
        for t in 0..60u32 {
            f.step(&[1, 2, 3, 4, 5, (t % 9) as u8]);
        }
        f
    }

    #[test]
    fn the_reads_are_sorted_by_id_and_inside_the_rect() {
        let f = busy_field();
        let half = SubRect { x0: FIELD / 2 - 600 * SUB, y0: FIELD / 2 - 600 * SUB, x1: FIELD / 2, y1: FIELD / 2 + 600 * SUB };
        let ms = monsters_in(&f, half);
        assert!(ms.len() > 5 * 50, "only {} monsters in view", ms.len() / 5);
        assert!(ms.chunks(5).zip(ms.chunks(5).skip(1)).all(|(a, b)| a[0] < b[0]));
        assert!(ms.chunks(5).all(|m| half.contains(m[1], m[2]) && (0..8).contains(&m[3])));
        // No cap: every live monster comes back for the whole field.
        assert_eq!(monsters_in(&f, ALL).len() / 5, f.monster_count() as usize);
        let ps = players_in(&f, ALL, Some(2));
        assert_eq!(ps.len() / 6, 6);
        assert!(ps.chunks(6).zip(ps.chunks(6).skip(1)).all(|(a, b)| a[0] < b[0]));
        assert_eq!(ps.chunks(6).filter(|p| p[5] & PLY_ME != 0).map(|p| p[0]).collect::<Vec<_>>(), vec![2]);
    }

    #[test]
    fn the_draw_buffer_blends_from_the_previous_call() {
        let mut f = busy_field();
        let mut d = DrawState::default();
        let first = d.monsters(&f, ALL);
        assert_eq!(first.len(), f.monster_count() as usize * STRIDE);
        assert!(first.chunks(STRIDE).all(|c| c[12] == 0.0 && c[13] == 0.0), "nothing to blend from on the first call");
        let before: std::collections::HashMap<u32, (f32, f32)> =
            monsters_in(&f, ALL).chunks(5).map(|m| (m[0] as u32, (m[1] as f32 / SUB as f32, m[2] as f32 / SUB as f32))).collect();
        f.step(&[1u16, 2, 3, 4, 5, 6]);
        let next = d.monsters(&f, ALL);
        let now = monsters_in(&f, ALL);
        let mut blended = 0;
        // Depth order: feet lower on screen come later.
        assert!(next.chunks(STRIDE).zip(next.chunks(STRIDE).skip(1)).all(|(a, b)| a[7] <= b[7]));
        for m in now.chunks(5) {
            let (x, y) = (m[1] as f32 / SUB as f32, m[2] as f32 / SUB as f32);
            let c = next.chunks(STRIDE).find(|c| (c[3] - x).abs() < 1e-3 && (c[7] - y).abs() < 1e-3).expect("drawn");
            match before.get(&(m[0] as u32)) {
                Some(&(px, py)) if (px - x).abs().max((py - y).abs()) <= BLEND_MAX_PX as f32 => {
                    // Scaled back by the transform, the offset lands on the previous position.
                    assert!((c[12] * c[0] - (px - x)).abs() < 1e-3 && (c[13] * c[5] - (py - y)).abs() < 1e-3);
                    blended += 1;
                }
                _ => assert!(c[12] == 0.0 && c[13] == 0.0),
            }
        }
        // Nearly every monster was there a tick ago and moved a step: all of those blend.
        assert!(blended > 300 && blended * 10 >= now.len() / 5 * 9, "{blended} of {} blended", now.len() / 5);
    }

    #[test]
    fn a_flipped_figure_blends_the_right_way() {
        let mut f = Field::new(9, Config { monsters: 0, threads: 1 });
        join(&mut f, 0, 0, FIELD / 2, FIELD / 2);
        let other = join(&mut f, 1, 1, FIELD / 2 + 100 * SUB, FIELD / 2);
        let mut d = DrawState::default();
        d.players(&f, ALL, Some(0));
        // West: the player faces left (scale -1) and was one step to the right of where it is now.
        let was = f.players()[other as usize].x;
        f.step(&[0u16, 5]);
        let walked = (was - f.players()[other as usize].x) as f32 / SUB as f32;
        assert!(walked > 2.0, "{walked}");
        let b = d.players(&f, ALL, Some(0));
        assert_eq!(b[0], -1.0);
        assert!((b[12] * b[0] - walked).abs() < 1e-3, "{}", b[12]);
    }

    #[test]
    fn the_player_buffer_leaves_out_this_player() {
        let f = busy_field();
        let mut d = DrawState::default();
        let b = d.players(&f, ALL, Some(0));
        assert_eq!(b.len(), 5 * STRIDE);
        assert!(b.chunks(STRIDE).all(|c| (c[14] as usize) < HERO_FRAMES));
    }
}
