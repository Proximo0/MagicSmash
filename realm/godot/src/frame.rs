//! One finished tick, ready to draw. The worker thread (`worker.rs`) builds a `Frame` from the follower's
//! field after every batch of ticks it applies; the main thread takes the newest one and hands its parts to
//! GDScript as packed arrays. No Godot types here, so it tests as plain Rust.
//!
//! What a frame holds: the two draw buffers (monsters and the other players), the own hero's numbers for the
//! HUD, effect rows (swings, rings, bolts, zones, drops, shots, statuses, raising), event rows, and the
//! world's state (tide, sites). Effect and event rows are flat floats and ints, `FX_STRIDE` and `EV_STRIDE`
//! to a row, so the boundary to GDScript costs one array each.

use crate::draw::{DrawState, SubRect};
use realm_core::tables::{Act, Shape, NFX, RAISE_NEED, SKILLS};
use realm_core::{cell_of, Event, Field, Hero, CAST1, CAST2, CAST_ULT, CELLS_W, CELL_SHIFT, DIRS, SUB};
use realm_server::client::LockstepClient;

pub const FX_STRIDE: usize = 8;
pub const EV_STRIDE: usize = 8;
/// Effect rows past this many are dropped (a crowd of a thousand heroes all casting).
pub const MAX_FX: usize = 6000;
/// Heroes past this many in one view get no aimed weapon effect (the nearest-monster search costs).
pub const MAX_AIMED: usize = 300;

/// Effect row types, the first float of a row: `[type, x, y, a, b, c, d, e]` in px.
pub mod fx {
    /// An arc toward `a` (rad) of `b` degrees, radius `c` px, class `d`.
    pub const SWING: f32 = 1.0;
    /// A circle on the hero: radius `a`, skill id `b` (-1 the weapon), class `c`.
    pub const RING: f32 = 2.0;
    /// A line to (`a`, `b`), class `c`, burst radius `d`.
    pub const BOLT: f32 = 3.0;
    /// A drop's circle: radius `a`, ticks left `b`.
    pub const DROP: f32 = 4.0;
    /// A zone: radius `a`, row `b`, ticks left `c`, age `d`.
    pub const ZONE: f32 = 5.0;
    /// A dash from here to (`a`, `b`), skill `c`.
    pub const DASH: f32 = 6.0;
    /// A monster bolt (radius 0) or lob: radius `a`, ticks left `b`, velocity px/tick (`c`, `d`).
    pub const SHOT: f32 = 7.0;
    /// A hero with effects running: bit mask over the 16 effect rows in `a`.
    pub const STATUS: f32 = 8.0;
    /// A downed hero: raise progress 0..1 in `a`, seconds left `b`.
    pub const RAISE: f32 = 9.0;
}

/// The own hero, for the HUD. Everything an int or a bool; ticks are 20 a second.
#[derive(Clone, Debug, Default)]
pub struct HeroView {
    pub id: i32,
    pub class: i32,
    pub job: i32,
    pub race: i32,
    pub class_level: i32,
    pub health: i32,
    pub max_health: i32,
    pub level: i32,
    pub xp: i32,
    pub xp_need: i32,
    pub alive: bool,
    /// Ticks left downed (0: up).
    pub downed: i32,
    /// Raise progress, percent.
    pub raise_pct: i32,
    pub coin: i32,
    /// Per slot (skill 1, skill 2, the ultimate): skill id or -1, ticks of cooldown left, its full length, rank percent.
    pub skills: [[i32; 4]; 3],
    /// Per belt slot: potion id or -1, charges, ticks of rest left.
    pub belt: [[i32; 3]; 3],
    /// The draw on offer (card ids, 0 for none), how many draws are queued behind it.
    pub offer: [i32; 4],
    pub owed: i32,
    pub copies: Vec<i32>,
    pub fx_mask: i32,
    /// Ticks of interact held at a waystone, and the waystone she banked at (7 none).
    pub hold: i32,
    pub waystone: i32,
    pub banked: bool,
    pub phoenix_used: bool,
    pub x: f32,
    pub y: f32,
    pub facing_left: bool,
    pub moving: bool,
    /// She carries the BLOOD MARK (rules section 14).
    pub marked: bool,
}

/// The field's own state that is not a figure.
#[derive(Clone, Debug, Default)]
pub struct World {
    pub field: i32,
    pub tick: u32,
    /// A tide is running.
    pub tide: bool,
    /// The realm's clock, the tide's and bosses' countdowns and the boss up now (`realm_server::world`).
    pub view: realm_server::world::WorldView,
    /// The gate, the heart, seven waystones and six altars in px: pairs.
    pub sites: Vec<f32>,
    /// Zones, drops and shots in the field (all of them, not just in view).
    pub zones: i32,
    pub drops: i32,
    pub shots: i32,
}

#[derive(Clone, Debug, Default)]
pub struct Frame {
    pub tick: u32,
    pub hash: u64,
    pub joined: bool,
    pub hero_id: i32,
    pub players: i32,
    pub monsters: i32,
    pub monster_buf: Vec<f32>,
    /// The monsters whose health bars are drawn (DrawState::bars), the same format as `monster_buf`.
    pub bar_buf: Vec<f32>,
    pub player_buf: Vec<f32>,
    pub hero: Option<HeroView>,
    pub fx: Vec<f32>,
    pub events: Vec<i32>,
    pub world: World,
}

fn px(v: i32) -> f32 {
    v as f32 / SUB as f32
}

fn hero_view(h: &Hero, id: u16) -> HeroView {
    let mut v = HeroView {
        id: i32::from(id),
        class: i32::from(h.class),
        job: if h.job == u8::MAX { -1 } else { i32::from(h.job) },
        race: i32::from(h.race),
        class_level: i32::from(h.class_level),
        health: h.health.min(i32::MAX as u32) as i32,
        max_health: h.max_health.min(i32::MAX as u32) as i32,
        level: i32::from(h.level),
        xp: h.xp.min(i32::MAX as u32) as i32,
        xp_need: 50 * i32::from(h.level),
        alive: h.alive(),
        downed: i32::from(h.downed),
        raise_pct: (h.raise.saturating_mul(100) / RAISE_NEED.max(1)).min(100) as i32,
        coin: h.coin.min(i32::MAX as u32) as i32,
        owed: i32::from(h.owed),
        copies: h.copies.iter().map(|&c| i32::from(c)).collect(),
        fx_mask: fx_mask(h),
        hold: i32::from(h.hold),
        waystone: i32::from(h.waystone),
        banked: h.banked,
        phoenix_used: h.phoenix_used,
        x: px(h.x),
        y: px(h.y),
        facing_left: h.facing_left,
        moving: h.moving,
        marked: h.marked,
        ..HeroView::default()
    };
    for slot in 0..3 {
        v.skills[slot] = match h.skill(slot) {
            Some(id) => [i32::from(id), h.cooldowns[slot].min(i32::MAX as u32) as i32, SKILLS[id as usize].cooldown as i32, h.rank_pct(id) as i32],
            None => [-1, 0, 0, 0],
        };
    }
    for (slot, &(potion, n)) in h.belt.iter().enumerate() {
        v.belt[slot] = [if potion == u8::MAX { -1 } else { i32::from(potion) }, i32::from(n), i32::from(h.belt_rest[slot])];
    }
    if let Some(o) = h.offers.first() {
        for (k, &c) in o.iter().enumerate() {
            v.offer[k] = i32::from(c);
        }
    }
    v
}

fn fx_mask(h: &Hero) -> i32 {
    (0..NFX).fold(0, |m, i| if h.fx[i] > 0 { m | 1 << i } else { m })
}

/// The nearest live monster to (x, y) within `reach` px, by the monster grid (32 px cells), as (x, y) in 1/256 px.
fn nearest(f: &Field, x: i32, y: i32, reach: i32) -> Option<(i32, i32)> {
    let g = f.grid();
    if g.start.len() <= CELLS_W * CELLS_W {
        return None;
    }
    let m = f.monsters();
    let r = reach * SUB;
    let max = CELLS_W as i32 - 1;
    let (x0, x1) = (((x - r) >> CELL_SHIFT).clamp(0, max), ((x + r) >> CELL_SHIFT).clamp(0, max));
    let (y0, y1) = (((y - r) >> CELL_SHIFT).clamp(0, max), ((y + r) >> CELL_SHIFT).clamp(0, max));
    let mut best: Option<(i64, i32, i32)> = None;
    for cy in y0..=y1 {
        for cx in x0..=x1 {
            for &i in g.cell(cell_of(cx << CELL_SHIFT, cy << CELL_SHIFT)) {
                let i = i as usize;
                if i >= m.hp.len() || m.hp[i] == 0 {
                    continue;
                }
                let (dx, dy) = (i64::from(m.x[i] - x), i64::from(m.y[i] - y));
                let d = dx * dx + dy * dy;
                if d <= i64::from(r) * i64::from(r) && best.is_none_or(|b| d < b.0) {
                    best = Some((d, m.x[i], m.y[i]));
                }
            }
        }
    }
    best.map(|b| (b.1, b.2))
}

fn weapon_reach(h: &Hero) -> i32 {
    match h.class_row().weapon.shape {
        Shape::Arc { px, .. } | Shape::Ring { px } => px,
        Shape::Bolt { reach, .. } | Shape::Drop { reach, .. } => reach,
    }
}

/// The skill's radius for a ring or pulse drawn on the caster.
fn pulse_px(act: &Act) -> i32 {
    match *act {
        Act::Ring { px, .. } | Act::GroupEffect { px, .. } | Act::GroupHeal { px, .. } | Act::Curse { px, .. } => px,
        _ => 40,
    }
}

struct Rows {
    out: Vec<f32>,
}

impl Rows {
    fn push(&mut self, row: [f32; FX_STRIDE]) {
        if self.out.len() < MAX_FX * FX_STRIDE {
            self.out.extend_from_slice(&row);
        }
    }
}

/// Effects of one hero this tick: her weapon, her casts, her dash, her statuses, her raising.
fn hero_fx(f: &Field, h: &Hero, aimed: bool, rows: &mut Rows) {
    let (hx, hy) = (px(h.x), px(h.y));
    let class = f32::from(h.class);
    if h.downed > 0 {
        let secs = h.downed as f32 / 20.0;
        rows.push([fx::RAISE, hx, hy, (h.raise as f32 / RAISE_NEED.max(1) as f32).min(1.0), secs, 0.0, 0.0, class]);
        return;
    }
    if !h.present || !h.alive() {
        return;
    }
    let mask = fx_mask(h);
    if mask != 0 {
        rows.push([fx::STATUS, hx, hy, mask as f32, 0.0, 0.0, 0.0, class]);
    }
    if let Some((fx0, fy0)) = h.dash_from {
        rows.push([fx::DASH, px(fx0), px(fy0), hx, hy, 0.0, 0.0, class]);
    }
    let reach = weapon_reach(h);
    let aim = if (h.fired || h.cast & (CAST1 | CAST2 | CAST_ULT) != 0) && aimed { nearest(f, h.x, h.y, reach) } else { None };
    let angle = match aim {
        Some((ax, ay)) => ((ay - h.y) as f32).atan2((ax - h.x) as f32),
        None => {
            let (dx, dy) = DIRS[usize::from(h.dir).min(8)];
            if dx == 0 && dy == 0 {
                0.0
            } else {
                (dy as f32).atan2(dx as f32)
            }
        }
    };
    if h.fired {
        match h.class_row().weapon.shape {
            Shape::Arc { deg, px: r } => rows.push([fx::SWING, hx, hy, angle, deg as f32, r as f32, class, 0.0]),
            Shape::Ring { px: r } => rows.push([fx::RING, hx, hy, r as f32, -1.0, class, 0.0, 0.0]),
            Shape::Bolt { reach, burst, .. } => {
                let end = match aim {
                    Some((ax, ay)) => (px(ax), px(ay)),
                    None => (hx + angle.cos() * reach as f32, hy + angle.sin() * reach as f32),
                };
                rows.push([fx::BOLT, hx, hy, end.0, end.1, class, burst as f32, 0.0]);
            }
            Shape::Drop { .. } => {}
        }
    }
    for (bit, slot) in [(CAST1, 0), (CAST2, 1), (CAST_ULT, 2)] {
        if h.cast & bit == 0 {
            continue;
        }
        let Some(id) = h.skill(slot) else { continue };
        match SKILLS[id as usize].act {
            Act::Volley { n, deg } => {
                for k in 0..n {
                    let t = if n > 1 { k as f32 / (n - 1) as f32 - 0.5 } else { 0.0 };
                    let a = angle + t * (deg as f32).to_radians();
                    rows.push([fx::BOLT, hx, hy, hx + a.cos() * reach as f32, hy + a.sin() * reach as f32, class, 0.0, 0.0]);
                }
            }
            // A dash is drawn from `dash_from`; zones and drops are state, drawn while they last.
            Act::Dash { .. } | Act::Zone { .. } | Act::Thick { .. } => {}
            ref act => rows.push([fx::RING, hx, hy, pulse_px(act) as f32, f32::from(id), class, 0.0, 0.0]),
        }
    }
}

/// An event as a row: `[rank, hero (-1 none), a, b, c, x, y, 0]`.
fn event_row(f: &Field, e: &Event) -> [i32; EV_STRIDE] {
    let at = |hero: u16| f.players().get(usize::from(hero)).map_or((0, 0), |p| (p.x / SUB, p.y / SUB));
    let rank = i32::from(e.rank());
    let (hero, a, b, c, (x, y)) = match *e {
        Event::Level { hero, level } => (i32::from(hero), i32::from(level), 0, 0, at(hero)),
        Event::Draw { hero, n, .. } => (i32::from(hero), i32::from(n), 0, 0, at(hero)),
        Event::Pick { hero, card, copies } => (i32::from(hero), i32::from(card), i32::from(copies), 0, at(hero)),
        Event::Skill { hero, which } => {
            let id = f.players().get(usize::from(hero)).and_then(|p| p.skill(usize::from(which).saturating_sub(1))).map_or(-1, i32::from);
            (i32::from(hero), i32::from(which), id, 0, at(hero))
        }
        Event::Potion { hero, slot, left } => {
            let id = f.players().get(usize::from(hero)).and_then(|p| p.belt.get(usize::from(slot))).map_or(-1, |b| if b.0 == u8::MAX { -1 } else { i32::from(b.0) });
            (i32::from(hero), i32::from(slot), i32::from(left), id, at(hero))
        }
        Event::Down { hero } | Event::Leave { hero } => (i32::from(hero), 0, 0, 0, at(hero)),
        Event::Raise { hero, by } => (i32::from(hero), i32::from(by), 0, 0, at(hero)),
        Event::Fallen { hero, coin } => (i32::from(hero), coin.min(i32::MAX as u32) as i32, 0, 0, at(hero)),
        Event::Bank { hero, coin, waystone } => (i32::from(hero), coin.min(i32::MAX as u32) as i32, i32::from(waystone), 0, at(hero)),
        Event::Kill { kind, level, flags, x, y, .. } => (-1, i32::from(kind), i32::from(level), i32::from(flags), (x / SUB, y / SUB)),
        Event::Xp { hero, amount } => (i32::from(hero), amount.min(i32::MAX as u32) as i32, 0, 0, at(hero)),
        // The BLOOD MARK's rite at a waystone: `a` is the outcome (`realm_core::pvp::MARK_*`).
        Event::Mark { hero, state } => (i32::from(hero), i32::from(state), 0, 0, at(hero)),
        // Events the tide and boss jobs add: the rank alone, for the client to learn about.
        #[allow(unreachable_patterns)]
        _ => (-1, 0, 0, 0, (0, 0)),
    };
    [rank, hero, a, b, c, x, y, 0]
}

/// Builds the frame for what the follower has applied, for the rectangle `view` (1/256 px).
pub fn build(c: &LockstepClient, view: SubRect, draw: &mut DrawState) -> Frame {
    let Some(f) = c.field() else {
        return Frame { hero_id: c.hero().map_or(-1, i32::from), ..Frame::default() };
    };
    let me = c.hero();
    let mut frame = Frame {
        tick: f.tick(),
        hash: f.hash(),
        joined: true,
        hero_id: me.map_or(-1, i32::from),
        players: f.player_count() as i32,
        monsters: f.monster_count() as i32,
        monster_buf: draw.monsters(f, view),
        bar_buf: std::mem::take(&mut draw.bars),
        player_buf: draw.players(f, view, me),
        hero: c.hero_player().zip(me).map(|(h, id)| hero_view(h, id)),
        ..Frame::default()
    };
    let t = f.terrain();
    let mut sites = vec![px(t.gate.0), px(t.gate.1), px(t.heart.0), px(t.heart.1)];
    for &(x, y) in t.waystones.iter().chain(t.altars.iter()) {
        sites.extend_from_slice(&[px(x), px(y)]);
    }
    frame.world = World {
        field: i32::from(f.field_id()),
        tick: f.tick(),
        tide: f.tide(),
        view: realm_server::world::world_view(f),
        sites,
        zones: f.zones().len() as i32,
        drops: f.drops().len() as i32,
        shots: f.shots().len() as i32,
    };
    let mut rows = Rows { out: Vec::new() };
    for z in f.zones() {
        let r = z.px * SUB;
        if z.x + r >= view.x0 && z.x - r < view.x1 && z.y + r >= view.y0 && z.y - r < view.y1 {
            rows.push([fx::ZONE, px(z.x), px(z.y), z.px as f32, f32::from(z.kind), f32::from(z.left), f32::from(z.age), 0.0]);
        }
    }
    for d in f.drops() {
        rows.push([fx::DROP, px(d.x), px(d.y), d.px as f32, f32::from(d.left), 0.0, 0.0, 0.0]);
    }
    for s in f.shots() {
        if view.contains(s.x, s.y) {
            rows.push([fx::SHOT, px(s.x), px(s.y), s.px as f32, f32::from(s.left), px(s.vx), px(s.vy), 0.0]);
        }
    }
    let mut aimed = 0;
    for (i, h) in f.players().iter().enumerate() {
        if !h.present || !(view.contains(h.x, h.y) || me == Some(i as u16)) {
            continue;
        }
        aimed += 1;
        hero_fx(f, h, aimed <= MAX_AIMED, &mut rows);
    }
    frame.fx = rows.out;
    for e in f.events() {
        let row = event_row(f, e);
        let mine = me.is_some_and(|m| row[1] == i32::from(m));
        if mine || view.contains(row[5] * SUB, row[6] * SUB) {
            frame.events.extend_from_slice(&row);
        }
    }
    frame
}

#[cfg(test)]
mod tests {
    use super::*;
    use realm_core::{Config, Outing, Sheet, FIELD};

    fn hero_field() -> Field {
        let mut f = Field::new(3, Config { monsters: 2000, threads: 1 });
        for k in 0..5u8 {
            f.join(&Sheet::bench(1 + k, k % 4, 20), &Outing::new(), FIELD / 2 + i32::from(k) * 30 * SUB, FIELD / 2);
        }
        f
    }

    #[test]
    fn every_class_shows_its_weapon_and_casts_as_effect_rows() {
        let mut f = hero_field();
        let mut kinds = std::collections::BTreeSet::new();
        for t in 0..400u32 {
            let inputs: Vec<u16> = (0..5).map(|k| realm_core::input(1 + ((t / 40 + k) % 8) as u8 | 0x10 | 0x20, 0)).collect();
            f.step(&inputs);
            let mut rows = Rows { out: Vec::new() };
            for h in f.players() {
                hero_fx(&f, h, true, &mut rows);
            }
            for r in rows.out.chunks(FX_STRIDE) {
                assert!(r.iter().all(|v| v.is_finite()));
                kinds.insert(r[0] as i32);
            }
        }
        // Arcs (knight), rings (priest), bolts (mage and archer) and statuses all appeared.
        for k in [fx::SWING, fx::RING, fx::BOLT] {
            assert!(kinds.contains(&(k as i32)), "no row of type {k}: {kinds:?}");
        }
    }

    #[test]
    fn a_downed_hero_is_a_raise_row_and_the_view_reads_the_hud_numbers() {
        let mut f = hero_field();
        f.hero_mut(0).health = 0;
        f.hero_mut(0).downed = 200;
        let mut rows = Rows { out: Vec::new() };
        hero_fx(&f, &f.players()[0], true, &mut rows);
        assert_eq!(rows.out[0], fx::RAISE);
        assert!((rows.out[4] - 10.0).abs() < 1e-3);
        let v = hero_view(&f.players()[1], 1);
        assert_eq!(v.class, 2);
        assert!(v.skills[0][0] >= 0 && v.skills[0][2] > 0, "a level 20 mage has skill 1");
        assert_eq!(v.skills[2][0], -1, "no job below 40");
        assert_eq!(v.xp_need, 50);
        assert_eq!(v.belt.len(), 3);
    }

    #[test]
    fn nearest_finds_the_closest_monster_and_nothing_beyond_reach() {
        let mut f = Field::new(3, Config { monsters: 100, threads: 1 });
        f.set_births(false);
        let id = f.join(&Sheet::bench(1, 0, 1), &Outing::new(), FIELD / 2, FIELD / 2);
        let near = f.place_monster(0, 1, 0, FIELD / 2 + 50 * SUB, FIELD / 2).unwrap();
        f.place_monster(0, 1, 0, FIELD / 2 + 300 * SUB, FIELD / 2);
        f.step(&[0u16]);
        let h = &f.players()[usize::from(id)];
        let m = f.monsters();
        let got = nearest(&f, h.x, h.y, 100).expect("one in reach");
        assert!((got.0 - m.x[near as usize]).abs() < 8 * SUB && (got.1 - m.y[near as usize]).abs() < 8 * SUB);
        assert!(nearest(&f, h.x, h.y, 10).is_none());
    }

    #[test]
    fn events_become_rows_of_eight() {
        let f = hero_field();
        let r = event_row(&f, &Event::Level { hero: 2, level: 7 });
        assert_eq!((r[0], r[1], r[2]), (0, 2, 7));
        let r = event_row(&f, &Event::Kill { kind: 3, level: 2, flags: 1, x: 5 * SUB, y: 6 * SUB, first: 0, count: 0 });
        assert_eq!((r[1], r[2], r[5], r[6]), (-1, 3, 5, 6));
    }
}
