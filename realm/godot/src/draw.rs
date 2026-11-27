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
    pub fn contains(&self, x: i32, y: i32) -> bool {
        x >= self.x0 && x < self.x1 && y >= self.y0 && y < self.y1
    }
}

#[cfg(test)]
pub const MON_ELITE: i32 = 1;
#[cfg(test)]
pub const MON_HURT: i32 = 2;
#[cfg(test)]
pub const PLY_LEFT: i32 = 1;
#[cfg(test)]
pub const PLY_MOVING: i32 = 2;
#[cfg(test)]
pub const PLY_HURT: i32 = 4;
#[cfg(test)]
pub const PLY_DEAD: i32 = 8;
#[cfg(test)]
pub const PLY_ME: i32 = 16;

/// The atlas frames: one per monster kind (the core's 42), and one per class (NOVICE and the five classes)
/// by race. The field client builds the atlases from art files by name, with stand-ins for missing ones.
pub const MONSTER_FRAMES: usize = realm_core::KINDS.len();
pub const HERO_CLASSES: usize = 6;
pub const HERO_RACES: usize = 4;

fn monster_frame(kind: u8) -> usize {
    usize::from(kind).min(MONSTER_FRAMES - 1)
}

/// The first field bosses have art slots of their own after the kinds (the client appends them to the atlas in
/// this order: `FieldArt.boss_entries`); the monster that is the running boss is drawn from its slot.
pub const BOSS_ART: usize = 12;

fn boss_frame(f: &Field, slot: usize) -> Option<usize> {
    f.boss().filter(|b| b.slot as usize == slot && usize::from(b.which) < BOSS_ART).map(|b| MONSTER_FRAMES + usize::from(b.which))
}

/// Kinds that stand off and throw (the core's SPITTER and LOBBER): their attack strip follows their throw timer.
fn ranged(kind: u8) -> bool {
    use realm_core::tables::kinds::{LOBBER, SPITTER};
    realm_core::KINDS.get(usize::from(kind)).is_some_and(|k| k.beh & (SPITTER | LOBBER) != 0)
}

fn hero_frame(class: u8, race: u8) -> usize {
    usize::from(class).min(HERO_CLASSES - 1) * HERO_RACES + usize::from(race).min(HERO_RACES - 1)
}

/// `id, x, y, picture, flags` for every live monster in `r`, by id.
#[cfg(test)]
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
#[cfg(test)]
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
const CHAMP: [f32; 4] = [0.85, 0.45, 1.0, 1.0];
const CURSED: [f32; 4] = [0.65, 0.45, 0.85, 1.0];
const STUNNED: [f32; 4] = [0.6, 0.75, 1.0, 1.0];
const SLOWED: [f32; 4] = [0.55, 0.85, 0.95, 1.0];
pub const CHAMP_SCALE: f32 = 1.6;
const DEAD: [f32; 4] = [0.55, 0.55, 0.6, 0.45];
/// Bob seeds run 1..=BOB_SEEDS so neighbours bob out of step.
const BOB_SEEDS: usize = 31;
/// Instance float 14 is `kind + STATE_STEP * state` and float 15 is `bob + BOB_STEP * age` (age in ticks since
/// the state began; heroes are always state 0, age 0). The shader (figures.gdshader) decodes both.
pub const STATE_STEP: usize = 64;
pub const BOB_STEP: usize = 32;
/// States: the walk strip (or a still), the attack, hit and die strips.
pub const ST_WALK: usize = 0;
pub const ST_ATK: usize = 1;
pub const ST_HIT: usize = 2;
pub const ST_DIE: usize = 3;
/// Ticks a hit strip plays (FieldAnim.HIT_S 0.15 s at 20 a second), an attack strip 6 (ATK_S 0.3), a die strip
/// (DIE_S 0.6): the shader spreads the strip's frames over them.
pub const HIT_TICKS: u32 = 3;
pub const DIE_TICKS: u32 = 12;
/// A corpse holds the die strip's last frame this many ticks more, fading out.
pub const FADE_TICKS: u32 = 8;
/// The core keeps no attack timer for monsters: one within this many px of a living hero is attacking (the
/// core's contact reach is 20 px), repeating its strip every ATK_PERIOD ticks (the core's contact cadence).
const ATTACK_PX: i32 = 24;
const ATK_PERIOD: u32 = 10;

/// Where each id stood at the last call, and in which call.
#[derive(Default)]
struct Seen {
    x: Vec<i32>,
    y: Vec<i32>,
    call: Vec<u32>,
    /// Which way each id last moved sideways: -1 left, 1 right (a monster is drawn mirrored by it).
    face: Vec<f32>,
    /// The call at which each id was last hurt (monsters only).
    hit_at: Vec<u32>,
    now: u32,
}

/// A monster that died in view: drawn playing its die strip where it fell, until it has faded.
struct Ghost {
    x: i32,
    y: i32,
    frame: usize,
    scale: f32,
    face: f32,
    born: u32,
}

impl Seen {
    fn begin(&mut self, ids: usize) {
        self.now += 1;
        if self.call.len() < ids {
            self.x.resize(ids, 0);
            self.y.resize(ids, 0);
            self.call.resize(ids, 0);
            self.face.resize(ids, 1.0);
            self.hit_at.resize(ids, 0);
        }
    }

    /// The offset (px) from `x, y` back to where `id` stood at the previous call, or zero.
    fn back(&mut self, id: usize, x: i32, y: i32) -> (f32, f32) {
        let (dx, dy) = (self.x[id] - x, self.y[id] - y);
        let near = dx.abs().max(dy.abs()) <= BLEND_MAX_PX * SUB;
        let back = if self.call[id] + 1 == self.now && near { (dx as f32 / SUB as f32, dy as f32 / SUB as f32) } else { (0.0, 0.0) };
        (self.x[id], self.y[id], self.call[id]) = (x, y, self.now);
        if back.0 > 0.0 {
            self.face[id] = -1.0;
        } else if back.0 < 0.0 {
            self.face[id] = 1.0;
        }
        back
    }
}

/// The previous positions behind the draw buffers.
#[derive(Default)]
pub struct DrawState {
    monsters: Seen,
    players: Seen,
    order: Vec<(i32, u32)>,
    ghosts: Vec<Ghost>,
    /// The running boss's slot and art frame, kept so its ghost is drawn with its own art after it dies.
    boss_at: Option<(usize, usize)>,
    /// The last `monsters` call's barred monsters within BAR_RADIUS_PX of the view's centre: the same 16 floats
    /// a figure as the monster buffer (figures_bar.gdshader reads them), in the same order.
    pub bars: Vec<f32>,
}

/// Health bars are drawn only for monsters within this many px of the view's centre (the camera follows the
/// hero): the bars' MultiMesh holds just those, so a full horde on screen costs the bar pass a few hundred
/// instances instead of every drawn monster (measured 27 Nov: a bar pass over 20,000 drawn monsters added 30 % to
/// their render on the build machine; docs/realm/client.md "Health bars").
pub const BAR_RADIUS_PX: i64 = 480;

/// A health bar rides in the tint's alpha, which is 1 for every living monster: `0.5 + b / 512` with b in 1..=255
/// (the health left, rounded up so a living monster never shows an empty bar) for a monster that is hurt or is
/// an elite, a champion or a boss; exactly 1 for none. (Instance colours above 1 draw black boxes in the GL
/// compatibility renderer, so the bar lives below 1.) figures.gdshader draws a living monster opaque whatever its
/// alpha (`bars` batch only; a ghost's alpha is its fade) and figures_bar.gdshader draws the bar from it.
pub fn with_bar(mut tint: [f32; 4], hp: u32, max: u32, always: bool) -> [f32; 4] {
    let max = max.max(1);
    if hp < max || always {
        let b = ((hp.min(max) as u64 * 255).div_ceil(max as u64)).clamp(1, 255);
        tint[3] = 0.5 + b as f32 / 512.0;
    }
    tint
}

/// One figure into a draw buffer. The shader moves vertices before the instance's transform scales them, so
/// the offset back to the previous position goes in divided by the scale (a figure facing left has -1).
fn put(out: &mut Vec<f32>, x: i32, y: i32, sx: f32, sy: f32, tint: [f32; 4], back: (f32, f32), frame: usize, bob: usize) {
    put_state(out, x, y, sx, sy, tint, back, frame, ST_WALK, bob, 0);
}

#[allow(clippy::too_many_arguments)]
fn put_state(out: &mut Vec<f32>, x: i32, y: i32, sx: f32, sy: f32, tint: [f32; 4], back: (f32, f32), frame: usize, state: usize, bob: usize, age: u32) {
    let (fx, fy) = (x as f32 / SUB as f32, y as f32 / SUB as f32);
    out.extend_from_slice(&[sx, 0.0, 0.0, fx, 0.0, sy, 0.0, fy]);
    out.extend_from_slice(&tint);
    out.extend_from_slice(&[back.0 / sx, back.1 / sy, (frame + STATE_STEP * state) as f32, (bob + BOB_STEP * age as usize) as f32]);
}

impl DrawState {
    /// Every live monster in `r`, deepest first: frame = kind, elites larger and gold, hurt ones red. A monster
    /// hurt in the last HIT_TICKS calls shows its hit strip, one within reach of a living hero its attack strip,
    /// and one that was drawn at the previous call but is dead now stays as a ghost on its die strip (all read
    /// from the field; the field keeps no clock for them, so this buffer does).
    pub fn monsters(&mut self, f: &Field, r: SubRect) -> Vec<f32> {
        let m = f.monsters();
        self.monsters.begin(m.hp.len());
        let now = self.monsters.now;
        let n = m.hp.len();
        if let Some(b) = f.boss() {
            self.boss_at = boss_frame(f, b.slot as usize).map(|fr| (b.slot as usize, fr));
        } else if self.boss_at.is_some_and(|(slot, _)| slot < n && m.hp[slot] > 0 && !m.is_boss(slot)) {
            self.boss_at = None; // the slot was taken by an ordinary monster
        }
        // Deaths since the last call, from where they stood.
        for i in 0..n {
            if m.hp[i] == 0 && self.monsters.call[i] != 0 && self.monsters.call[i] + 1 == now {
                let (x, y) = (self.monsters.x[i], self.monsters.y[i]);
                let s = if m.is_champion(i) { CHAMP_SCALE } else if m.is_elite(i) { ELITE_SCALE } else { 1.0 };
                let frame = match self.boss_at {
                    Some((slot, fr)) if slot == i => fr,
                    _ => monster_frame(m.kind[i]),
                };
                self.ghosts.push(Ghost { x, y, frame, scale: s, face: self.monsters.face[i], born: now });
            }
        }
        self.ghosts.retain(|g| now - g.born < DIE_TICKS + FADE_TICKS);
        let heroes: Vec<(i32, i32)> = f.players().iter().filter(|p| p.present && p.alive()).map(|p| (p.x, p.y)).collect();
        let reach = ATTACK_PX as i64 * SUB as i64;
        self.bars.clear();
        let (cx, cy) = ((r.x0 as i64 + r.x1 as i64) / 2, (r.y0 as i64 + r.y1 as i64) / 2);
        let bar_r = BAR_RADIUS_PX * SUB as i64;
        self.order.clear();
        for i in 0..n {
            if m.hp[i] > 0 && r.contains(m.x[i], m.y[i]) {
                self.order.push((m.y[i], i as u32));
            }
        }
        for (k, g) in self.ghosts.iter().enumerate() {
            if r.contains(g.x, g.y) {
                self.order.push((g.y, (n + k) as u32));
            }
        }
        self.order.sort_unstable();
        let mut out = Vec::with_capacity(self.order.len() * STRIDE);
        for &(_, id) in &self.order {
            let i = id as usize;
            if i >= n {
                let g = &self.ghosts[i - n];
                let age = now - g.born;
                let fade = age.saturating_sub(DIE_TICKS) as f32 / FADE_TICKS as f32;
                let tint = [0.8, 0.8, 0.8, 1.0 - fade];
                put_state(&mut out, g.x, g.y, g.scale * g.face, g.scale, tint, (0.0, 0.0), g.frame, ST_DIE, 0, age);
                continue;
            }
            let (elite, champ) = (m.is_elite(i), m.is_champion(i));
            let s = if champ { CHAMP_SCALE } else if elite { ELITE_SCALE } else { 1.0 };
            let tint = if m.hurt[i] != 0 {
                HURT
            } else if m.curse[i] != 0 {
                CURSED
            } else if m.stun[i] != 0 {
                STUNNED
            } else if m.slow[i] != 0 {
                SLOWED
            } else if champ {
                CHAMP
            } else if elite {
                ELITE
            } else {
                WHITE
            };
            let tint = with_bar(tint, m.hp[i], m.max_hp(i), elite || champ || m.is_boss(i));
            let back = self.monsters.back(i, m.x[i], m.y[i]);
            if m.hurt[i] != 0 {
                self.monsters.hit_at[i] = now;
            }
            // A monster that moved since the last call steps through its walk frames, out of step with its
            // neighbours by its slot; one standing still shows frame 0.
            let bob = if back != (0.0, 0.0) { 1 + i % BOB_SEEDS } else { 0 };
            let since_hit = now - self.monsters.hit_at[i];
            let (state, age) = if self.monsters.hit_at[i] != 0 && since_hit < HIT_TICKS {
                (ST_HIT, since_hit)
            } else if m.stun[i] == 0 && ranged(m.kind[i]) && back == (0.0, 0.0) && (1..ATK_PERIOD as u8).contains(&m.timer[i]) {
                // A spitter or lobber standing to throw: its strip ends on the tick it lets go (its timer at 0).
                (ST_ATK, ATK_PERIOD - m.timer[i] as u32)
            } else if m.stun[i] == 0 && heroes.iter().any(|&(hx, hy)| {
                let (dx, dy) = ((hx - m.x[i]) as i64, (hy - m.y[i]) as i64);
                dx * dx + dy * dy <= reach * reach
            }) {
                (ST_ATK, (now + i as u32) % ATK_PERIOD)
            } else {
                (ST_WALK, 0)
            };
            put_state(&mut out, m.x[i], m.y[i], s * self.monsters.face[i], s, tint, back, boss_frame(f, i).unwrap_or_else(|| monster_frame(m.kind[i])), state, bob, age);
            let (dx, dy) = (m.x[i] as i64 - cx, m.y[i] as i64 - cy);
            if tint[3] < 1.0 && dx * dx + dy * dy <= bar_r * bar_r {
                self.bars.extend_from_slice(&out[out.len() - STRIDE..]);
            }
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
        assert!(ms.chunks(5).all(|m| half.contains(m[1], m[2]) && (0..42).contains(&m[3])));
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
        // A monster steps its walk frames (a bob seed) exactly when it has an offset back to blend from.
        let walking = |c: &[f32]| c[14] < STATE_STEP as f32;
        assert!(next.chunks(STRIDE).filter(|c| walking(c)).all(|c| (c[15] > 0.0) == (c[12] != 0.0 || c[13] != 0.0) && c[15] <= BOB_SEEDS as f32));
        assert!(first.chunks(STRIDE).filter(|c| walking(c)).all(|c| c[15] == 0.0), "standing monsters show frame 0");
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

    fn lone(hero_at: Option<i32>) -> (Field, usize) {
        let mut f = Field::new(9, Config { monsters: 1, threads: 1 });
        join(&mut f, 1, 0, hero_at.unwrap_or(100) * SUB, 100 * SUB);
        let m = f.monsters_mut();
        (m.x[0], m.y[0], m.hp[0]) = (2000 * SUB, 2000 * SUB, 50);
        (f, 0)
    }

    fn states(b: &[f32]) -> Vec<(usize, usize, u32)> {
        b.chunks(STRIDE).map(|c| (c[14] as usize / STATE_STEP, c[14] as usize % STATE_STEP, c[15] as u32 / BOB_STEP as u32)).collect()
    }

    #[test]
    fn a_monster_far_from_heroes_walks_and_one_in_reach_attacks() {
        let (mut f, _) = lone(None);
        let mut d = DrawState::default();
        assert_eq!(states(&d.monsters(&f, ALL)), vec![(ST_WALK, 0, 0)], "no strips needed for the old look");
        let m = f.monsters_mut();
        (m.x[0], m.y[0]) = (110 * SUB, 100 * SUB);
        let a = states(&d.monsters(&f, ALL));
        assert_eq!((a[0].0, a[0].1), (ST_ATK, 0));
        assert!(a[0].2 < ATK_PERIOD);
    }

    #[test]
    fn a_spitter_standing_to_throw_winds_up_to_the_tick_it_lets_go() {
        let (mut f, _) = lone(None);
        let mut d = DrawState::default();
        let spitter = realm_core::KINDS.iter().position(|k| k.beh & realm_core::tables::kinds::SPITTER != 0).unwrap() as u8;
        let m = f.monsters_mut();
        (m.kind[0], m.timer[0]) = (spitter, 30);
        d.monsters(&f, ALL);
        assert_eq!(states(&d.monsters(&f, ALL))[0].0, ST_WALK, "far from its next throw it only stands");
        f.monsters_mut().timer[0] = 3;
        assert_eq!(states(&d.monsters(&f, ALL))[0], (ST_ATK, usize::from(spitter), ATK_PERIOD - 3));
        f.monsters_mut().timer[0] = 1;
        assert_eq!(states(&d.monsters(&f, ALL))[0], (ST_ATK, usize::from(spitter), ATK_PERIOD - 1));
        f.monsters_mut().kind[0] = 0;
        assert_eq!(realm_core::KINDS[0].beh & realm_core::tables::kinds::SPITTER, 0);
        assert_eq!(states(&d.monsters(&f, ALL))[0].0, ST_WALK, "a kind that does not throw ignores the timer");
    }

    #[test]
    fn a_hit_plays_for_a_few_calls() {
        let (mut f, _) = lone(None);
        let mut d = DrawState::default();
        d.monsters(&f, ALL);
        f.monsters_mut().hurt[0] = 1;
        assert_eq!(states(&d.monsters(&f, ALL))[0], (ST_HIT, 0, 0));
        f.monsters_mut().hurt[0] = 0;
        assert_eq!(states(&d.monsters(&f, ALL))[0], (ST_HIT, 0, 1));
        assert_eq!(states(&d.monsters(&f, ALL))[0], (ST_HIT, 0, 2));
        assert_eq!(states(&d.monsters(&f, ALL))[0].0, ST_WALK, "back to walking after HIT_TICKS");
    }

    #[test]
    fn a_death_leaves_one_ghost_that_fades_and_expires() {
        let (mut f, _) = lone(None);
        let mut d = DrawState::default();
        assert_eq!(d.monsters(&f, ALL).len(), STRIDE);
        f.monsters_mut().hp[0] = 0;
        let b = d.monsters(&f, ALL);
        assert_eq!(b.len(), STRIDE, "the corpse stays");
        assert_eq!(states(&b)[0], (ST_DIE, 0, 0));
        assert_eq!((b[3], b[7]), (2000.0, 2000.0));
        assert_eq!(b[11], 1.0);
        let mut calls = 1;
        let mut last = b;
        loop {
            let b = d.monsters(&f, ALL);
            if b.is_empty() {
                break;
            }
            assert_eq!(b.len(), STRIDE, "once, not again");
            assert_eq!(states(&b)[0].2, calls);
            last = b;
            calls += 1;
            assert!(calls < 100);
        }
        assert_eq!(calls, DIE_TICKS + FADE_TICKS);
        assert!(last[11] < 0.2, "faded by the end: {}", last[11]);
        assert!(d.monsters(&f, ALL).is_empty(), "never again");
    }

    #[test]
    fn a_monster_that_left_the_view_alive_leaves_no_ghost() {
        let (f, _) = lone(None);
        let mut d = DrawState::default();
        d.monsters(&f, ALL);
        let away = SubRect { x0: 0, y0: 0, x1: 500 * SUB, y1: 500 * SUB };
        assert!(d.monsters(&f, away).is_empty());
    }

    #[test]
    fn a_bar_rides_in_the_alpha_only_for_the_hurt_and_the_ranked() {
        assert_eq!(with_bar(WHITE, 50, 50, false)[3], 1.0, "a whole common monster has no bar");
        assert_eq!(with_bar(WHITE, 50, 50, true)[3], 0.5 + 255.0 / 512.0, "an elite's bar is full");
        assert_eq!(with_bar(WHITE, 25, 50, false)[3], 0.5 + 128.0 / 512.0);
        assert_eq!(with_bar(WHITE, 1, 100_000, false)[3], 0.5 + 1.0 / 512.0, "a living monster's bar is never empty");
        let (mut f, _) = lone(None);
        f.monsters_mut().flags[0] = 0;
        let mx = f.monsters().max_hp(0);
        f.monsters_mut().hp[0] = mx;
        let b = DrawState::default().monsters(&f, ALL);
        assert!(b.chunks(STRIDE).all(|c| c[11] == 1.0), "a fresh monster shows no bar");
        f.monsters_mut().hp[0] /= 2;
        let mut d = DrawState::default();
        let b = d.monsters(&f, ALL);
        assert!(b.chunks(STRIDE).any(|c| c[11] > 0.5 && c[11] < 1.0), "a hurt one does");
        let near = SubRect { x0: 1500 * SUB, y0: 1500 * SUB, x1: 2500 * SUB, y1: 2500 * SUB };
        assert_eq!(d.monsters(&f, near).len(), STRIDE);
        assert_eq!(d.bars.len(), STRIDE, "a hurt one near the view's centre is in the bars' buffer");
        let far = SubRect { x0: 1900 * SUB, y0: 1900 * SUB, x1: 4000 * SUB, y1: 4000 * SUB };
        assert_eq!(d.monsters(&f, far).len(), STRIDE, "drawn");
        assert!(d.bars.is_empty(), "but not its bar: it is over BAR_RADIUS_PX from the centre");
    }

    #[test]
    fn the_player_buffer_leaves_out_this_player() {
        let f = busy_field();
        let mut d = DrawState::default();
        let b = d.players(&f, ALL, Some(0));
        assert_eq!(b.len(), 5 * STRIDE);
        assert!(b.chunks(STRIDE).all(|c| (c[14] as usize) < HERO_FRAMES));
    }

    /// The entry the shader draws an instance from: its frame without the state (draw.rs `put_state`).
    fn entry_at(buf: &[f32], x: i32, y: i32) -> Option<usize> {
        let (fx, fy) = (x as f32 / SUB as f32, y as f32 / SUB as f32);
        buf.chunks(STRIDE).find(|c| (c[3] - fx).abs() < 1e-3 && (c[7] - fy).abs() < 1e-3).map(|c| c[14] as usize % STATE_STEP)
    }

    /// The running boss is drawn from its art slot after the kinds, the same for a boss the realm clock raised in the
    /// step (how every peer gets one), for a hero who joined from the state while it is up, and for a summoned one.
    #[test]
    fn the_running_boss_is_drawn_from_its_own_art_slot() {
        use realm_core::{field_boss_window, tables::field_boss_of, tables::BOSSES};
        let view = |x: i32, y: i32| SubRect { x0: x - 900 * SUB, y0: y - 600 * SUB, x1: x + 900 * SUB, y1: y + 600 * SUB };
        for field in 0..realm_core::tables::FIELDS.len() as u8 {
            // A field's own boss rising on the clock (rules 8: at the heart, in the step).
            let mut f = Field::open(field, 9, Config { monsters: 400, threads: 1 });
            let (hx, hy) = f.terrain().heart;
            join(&mut f, 1, 0, hx, hy);
            f.set_clock(field_boss_window(field, 3).0 - 2);
            for _ in 0..5 {
                f.step(&[0u16]);
            }
            let which = f.boss().map(|b| b.which).expect("the clock raised the boss");
            assert_eq!(which, field_boss_of(field, 0));
            let (bx, by) = f.boss_pos().unwrap();
            let mut d = DrawState::default();
            let buf = d.monsters(&f, view(hx, hy));
            assert_eq!(entry_at(&buf, bx, by), Some(MONSTER_FRAMES + which as usize), "{} from its slot", BOSSES[which as usize].name);
            // A hero who joins now gets the field's bytes: the boss is in them and drawn the same.
            let g = Field::from_bytes(&f.to_bytes(), 1).expect("state");
            assert_eq!(g.boss(), f.boss());
            let buf = DrawState::default().monsters(&g, view(hx, hy));
            assert_eq!(entry_at(&buf, bx, by), Some(MONSTER_FRAMES + which as usize));
        }
        // A summoned boss (tools) the same, for every boss; one past the art slots would be drawn as its carrier kind.
        for which in 0..BOSSES.len() as u8 {
            let mut f = Field::new(9, Config { monsters: 400, threads: 1 });
            join(&mut f, 1, 0, FIELD / 2, FIELD / 2);
            f.summon_boss(which, 2_000_000, FIELD / 2 + 90 * SUB, FIELD / 2);
            f.step(&[0u16]);
            let (bx, by) = f.boss_pos().unwrap();
            let buf = DrawState::default().monsters(&f, view(FIELD / 2, FIELD / 2));
            let want = if usize::from(which) < BOSS_ART { MONSTER_FRAMES + usize::from(which) } else { usize::from(BOSSES[which as usize].carrier) };
            assert_eq!(entry_at(&buf, bx, by), Some(want));
        }
    }
}
