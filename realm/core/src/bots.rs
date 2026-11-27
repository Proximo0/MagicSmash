//! Class bots: players that play each class the way a careful person would, in whole numbers, from the field's
//! public state alone (so a test, the load test and a bench all drive them the same way). A bot does not cheat:
//! it reads what a client sees (monsters, heroes, the boss and its drawn shapes) and answers with the two input
//! bytes.
//!
//! Every `every` ticks (staggered by id) a bot decides a direction by adding up:
//! - fleeing: away from every monster within reach, weighted by 1 / distance squared (less for a melee class);
//! - a goal, the first that applies: raise a downed ally; leave a boss shape that is about to land; hold a lit
//!   altar in a tide; walk to the boss; bank at a waystone with a full haul; patrol a ring of the field
//!   (clockwise, which keeps a lone hero moving along the edge) or the middle of a vault;
//! and then presses what its class does best: skills when the crowd is thick or a boss is near, the healer's
//! skills when an ally is hurt, a draught under 45% health, WHETSTONE OIL in a thick fight, and the best card of
//! an offer for its role.

use crate::geo::in_beam;
use crate::hero::*;
use crate::tables::*;
use crate::util::{at_angle, d2, grid_box, isqrt, rng_next};
use crate::{CELL_SHIFT, CELLS_W, FIELD, Field, PCELL_SHIFT, PCELLS_W, SUB};

mod delve;
mod nav;

/// How a class fights.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Role {
    /// Stands in the thick of it (KNIGHT, PALADIN).
    Melee,
    /// Keeps away (MAGE, ARCHER, NOVICE).
    Ranged,
    /// Stays near allies (PRIEST).
    Healer,
}

pub fn role_of(class: u8) -> Role {
    match class {
        KNIGHT | PALADIN => Role::Melee,
        PRIEST => Role::Healer,
        _ => Role::Ranged,
    }
}

/// What a bot is told about its place in the world.
#[derive(Clone, Copy, Debug)]
pub struct Plan {
    /// Ticks between decisions.
    pub every: u32,
    /// The radius from the heart it patrols (px); a vault is patrolled at a quarter of it.
    pub ring_px: i32,
    /// Walks to a waystone and banks when the haul is this big (`u32::MAX`: never).
    pub bank_coin: u32,
    /// Goes to altars in a tide and to the boss when one is up.
    pub objectives: bool,
    /// Walks toward the heart when farther than `rally_px` (the dense fight of a crowd test), 0: not.
    pub rally_px: i32,
    /// Hunts her foes (section 14) when she can strike heroes: walks to the nearest one off safe ground.
    pub hunt: bool,
    /// Delves (rules 6, quiet zones): walks deep into the field from quiet zone to quiet zone, fighting on the way, and back
    /// out again; under `RETREAT_PCT` health she goes to the nearest quiet zone and rests there.
    pub delve: bool,
}

impl Plan {
    /// A lone hero of the edge, as the kiting gate plays: a careful decision every 2 ticks.
    pub fn alone(ring_px: i32) -> Plan {
        Plan { every: 2, ring_px, bank_coin: u32::MAX, objectives: false, rally_px: 0, hunt: false, delve: false }
    }
    /// A hero in a party or a crowd, with every objective.
    pub fn party(ring_px: i32) -> Plan {
        Plan { every: 2, ring_px, bank_coin: 400, objectives: true, rally_px: 0, hunt: false, delve: false }
    }
    /// One of a crowd of a thousand: a decision every 8 ticks.
    pub fn crowd(rally_px: i32) -> Plan {
        Plan { every: 8, ring_px: 4_200, bank_coin: u32::MAX, objectives: true, rally_px, hunt: false, delve: false }
    }
    /// A hero who delves from the entrance through the quiet zones to the heart's rim and back, with every objective
    /// but banking (her driver or player sends her to a waystone when the outing is over)
    /// (the realm's driven heroes and the playbot's way).
    pub fn delve() -> Plan {
        Plan { delve: true, bank_coin: u32::MAX, ..Plan::party(4_200) }
    }
    /// A marked hero of a crowd who hunts the other marked (job R3's proof): a crowd bot with `hunt`.
    pub fn hunter(rally_px: i32) -> Plan {
        Plan { hunt: true, ..Plan::crowd(rally_px) }
    }
}

/// A hunter looks for foes this far (px), and keeps this distance by role (melee, healer, ranged).
pub const HUNT_PX: i32 = 900;
const HUNT_KEEP: [i64; 3] = [24, 120, 160];
/// Under this share of health (percent) a hunter backs away from the foe instead.
const HUNT_FLEE_PCT: u32 = 30;

#[derive(Clone, Debug)]
pub struct Bot {
    pub id: u16,
    pub plan: Plan,
    pub input: u16,
    rng: u64,
    /// Navigation around walls (job B1): the waypoint (px) toward the patrol's target and the tick to look again.
    nav: Option<(i32, i32)>,
    nav_until: u32,
    /// A delve: the shrine zone she walks to next, whether she is on the way in (else out), and her rest.
    leg: u8,
    inward: bool,
    resting: bool,
    rest_until: u32,
    banking: bool,
}

/// Fixed point of the flee vector: a monster at 100 px weighs `FLEE_K / 100`.
const FLEE_K: i64 = 100_000;
/// Monsters counted at most, and how far ahead they are predicted (ticks).
const NEAR_MAX: usize = 96;
/// Heroes of a party this small or smaller all stay with each other, as healers do in any crowd.
const PARTY_MAX: usize = 8;
/// A hero in a party stands and fights when this many monsters are within 60 px: running from a crowd that fast does not work.
const STAND_CROWD: u32 = 1_000;
/// A hero raises a downed ally when at most this many monsters are within 60 px of her.
const RAISE_CROWD: u32 = 3;
/// A melee hero walks into a crowd of at most this many within 400 px.
const ENGAGE_MAX: u32 = 0;
/// The flee vector's constant and the share (tenths) of the kinematic risk in a direction's score.
const FLEE_VEC_K: i64 = 1 << 14;
const RISK_W: i64 = 0;
const HORIZON_TICKS: i64 = 40;
/// The strength of a goal against the flee vector (a goal is this many monsters at 10 px, in effect).
const GOAL_W: i64 = 90;
/// The pull of a patrol against fleeing: a hundredth of a monster's push at 1 px, like a slow orbit.
const PATROL_W: i64 = 8;
/// Card preference by role: the first of these in an offer is taken.
const PICKS_MELEE: [u8; 12] = [4, 12, 5, 1, 3, 19, 2, 13, 7, 14, 17, 25];
const PICKS_RANGED: [u8; 12] = [3, 1, 2, 4, 8, 12, 5, 19, 7, 23, 22, 17];
const PICKS_HEALER: [u8; 12] = [4, 12, 5, 21, 2, 3, 8, 17, 19, 1, 7, 24];

impl Bot {
    pub fn new(id: u16, seed: u64, plan: Plan) -> Bot {
        Bot { id, plan, input: 0, rng: seed ^ (id as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15), nav: None, nav_until: 0, leg: 1, inward: true, resting: false, rest_until: 0, banking: false }
    }

    /// The input word for this tick: a new decision every `plan.every` ticks (staggered by id), else the last.
    pub fn act(&mut self, f: &Field) -> u16 {
        if (f.tick() + self.id as u32) % self.plan.every == 0 {
            self.input = self.decide(f);
        }
        self.input
    }

    fn decide(&mut self, f: &Field) -> u16 {
        let Some(h) = f.heroes().get(self.id as usize).filter(|h| h.alive()) else {
            return 0;
        };
        let role = role_of(h.class);
        let (x, y) = (h.x / SUB, h.y / SUB);
        let vault = f.vault().is_some();
        let m = f.monsters();
        // Monsters near: a flee vector and counts.
        let reach = match role {
            Role::Melee => {
                if self.plan.objectives {
                    160
                } else {
                    110
                }
            }
            Role::Healer => 160,
            Role::Ranged => 120,
        };
        let flee_w = match role {
            Role::Melee => {
                if self.plan.objectives {
                    2
                } else {
                    1
                }
            }
            Role::Healer => 2,
            Role::Ranged => 1,
        };
        // Each monster near: its place relative to the hero and its walking speed, in sixteenths of a px (a tick).
        let mut near: Vec<(i64, i64, i64)> = Vec::new();
        let (mut n60, mut n150) = (0u32, 0u32);
        let (mut fx, mut fy) = (0i64, 0i64);
        let r = reach * SUB;
        grid_box(f.grid(), CELLS_W, CELL_SHIFT, h.x - r, h.y - r, h.x + r, h.y + r, |i| {
            let i = i as usize;
            if m.hp[i] == 0 || m.flags[i] & crate::BOSS != 0 {
                return;
            }
            let (dx, dy) = (((h.x - m.x[i]) / SUB) as i64, ((h.y - m.y[i]) / SUB) as i64);
            let dd = dx * dx + dy * dy;
            if dd < (reach as i64) * (reach as i64) {
                n60 += (dd < 60 * 60) as u32;
                n150 += (dd < 150 * 150) as u32;
                let w = FLEE_VEC_K / dd.max(16);
                fx += dx * w / 8;
                fy += dy * w / 8;
                if near.len() < NEAR_MAX {
                    let mut sp = m.row(i).speed as i64;
                    if m.slow[i] > 0 {
                        sp /= 2;
                    }
                    if m.stun[i] > 0 {
                        sp = 0;
                    }
                    near.push((-dx * 16, -dy * 16, sp * 16 / TICK_HZ as i64));
                }
            }
        });
        let (mut vx, mut vy) = (fx * flee_w / 3, fy * flee_w / 3);
        let mut press = 0u16;
        let mut b1 = 0u16;
        let mut boss_near = false;

        // Goals, in order of priority.
        let mut goal: Option<(i32, i32, i64)> = None;
        // A downed ally to raise, when the crowd on her is thin.
        if n60 <= RAISE_CROWD {
            let mut best: Option<(i64, i32, i32)> = None;
            for (q, a) in f.heroes().iter().enumerate() {
                // Not her prey (a hunter does not raise a hero she is marked against), and not one the help ban
                // keeps her from raising.
                if q as u16 != self.id && a.present && a.downed > 0 && !(self.plan.hunt && f.hostile(self.id as usize, q)) && f.may_help(self.id as usize, q) {
                    let dd = d2(a.x, a.y, h.x, h.y) / (SUB as i64 * SUB as i64);
                    if dd < 400 * 400 && best.is_none_or(|(bd, _, _)| dd < bd) {
                        best = Some((dd, a.x / SUB, a.y / SUB));
                    }
                }
            }
            if let Some((dd, ax, ay)) = best {
                if dd > 25 * 25 {
                    goal = Some((ax, ay, if h.health * 2 > h.max_health { GOAL_W * 2 } else { GOAL_W * 2 }));
                } else {
                    // Stand by her: the raise takes two seconds within 40 px.
                    goal = Some((x, y, 0));
                    vx = 0;
                    vy = 0;
                }
            }
        }
        // A foe to hunt (section 14): the nearest one she could strike, at her role's distance; away when hurt.
        if goal.is_none() && self.plan.hunt && f.flagged(self.id as usize) {
            let r = HUNT_PX * SUB;
            let me = self.id as usize;
            let mut best: Option<(i64, u32)> = None;
            grid_box(f.player_grid(), PCELLS_W, PCELL_SHIFT, h.x - r, h.y - r, h.x + r, h.y + r, |q| {
                let a = &f.heroes()[q as usize];
                let dd = d2(a.x, a.y, h.x, h.y);
                if dd <= r as i64 * r as i64 && f.hostile(me, q as usize) && a.alive() && !f.safe_ground(a.x, a.y) && best.is_none_or(|(bd, bq)| dd < bd || (dd == bd && q < bq)) {
                    best = Some((dd, q));
                }
            });
            if let Some((dd, q)) = best {
                let a = &f.heroes()[q as usize];
                let (ax, ay) = (a.x / SUB, a.y / SUB);
                let d = isqrt(dd) / SUB as i64;
                let keep = HUNT_KEEP[match role {
                    Role::Melee => 0,
                    Role::Healer => 1,
                    Role::Ranged => 2,
                }];
                if h.health * 100 < h.max_health * HUNT_FLEE_PCT {
                    goal = Some((x + (x - ax), y + (y - ay), GOAL_W * 2));
                } else if d > keep {
                    goal = Some((ax, ay, GOAL_W * 2));
                } else if d < keep / 2 {
                    goal = Some((x + (x - ax), y + (y - ay), GOAL_W / 2));
                } else {
                    goal = Some((x, y, 0));
                }
            }
        }
        // A lobbed or bursting circle about to land on her, or a bolt about to pass through her: step out of it.
        let (ax, ay) = nav::dodge(f, h);
        vx += ax;
        vy += ay;
        // A boss shape about to land: leave it.
        if let Some(b) = f.boss() {
            let (bx, by) = f.boss_pos().map(|(a, c)| (a / SUB, c / SUB)).unwrap_or((x, y));
            let row = &BOSSES[b.which as usize];
            let (mut ax, mut ay) = (0i64, 0i64);
            let mut avoid = false;
            for c in &b.casts {
                let a = &row.attacks[c.atk as usize];
                let (cx, cy) = (c.x / SUB, c.y / SUB);
                let away = |px: i32, py: i32, r: i32, ax: &mut i64, ay: &mut i64| -> bool {
                    let (dx, dy) = ((x - px) as i64, (y - py) as i64);
                    let d = isqrt(dx * dx + dy * dy).max(1);
                    if d < r as i64 + 40 {
                        *ax += dx * 4_000 / d;
                        *ay += dy * 4_000 / d;
                        true
                    } else {
                        false
                    }
                };
                match a.shape {
                    A_SLAM | A_PULL => avoid |= away(bx, by, a.px, &mut ax, &mut ay),
                    A_CANDLES | A_MIRE => {
                        for &(px, py) in &c.pts {
                            avoid |= away(px / SUB, py / SUB, a.px, &mut ax, &mut ay);
                        }
                    }
                    A_SWEEP => {
                        let beams = a.count.max(1) as i32;
                        let t = (c.age as i32 - a.warn as i32).max(0);
                        for k in 0..beams {
                            let dir = if k % 2 == 0 { 1 } else { -1 };
                            let ang = c.angle + k * 360 * 16 / beams + dir * crate::boss::SWEEP_TURN16 * (t + 12);
                            if in_beam(bx * SUB, by * SUB, ang, a.px + 30, 60, h.x, h.y) {
                                let (ox, oy) = ((x - bx) as i64, (y - by) as i64);
                                let d = isqrt(ox * ox + oy * oy).max(1);
                                ax += ox * 4_000 / d;
                                ay += oy * 4_000 / d;
                                avoid = true;
                            }
                        }
                    }
                    A_LANES => {
                        if let Some(&(ex, ey)) = c.pts.first() {
                            // Away from the line: along its normal.
                            let (lx, ly) = ((ex - c.x) as i64, (ey - c.y) as i64);
                            let ll = isqrt(lx * lx + ly * ly).max(1);
                            let (nx, ny) = (-ly / ll, lx / ll);
                            let (px, py) = ((h.x - c.x) as i64, (h.y - c.y) as i64);
                            let side = px * nx + py * ny;
                            let along = (px * lx + py * ly) / ll;
                            if side.abs() < (a.px as i64 + 60) * SUB as i64 && along > -(100 * SUB as i64) && along < ll + 100 * SUB as i64 {
                                let s = if side >= 0 { 1 } else { -1 };
                                ax += nx * s * 4_000 / 1_000;
                                ay += ny * s * 4_000 / 1_000;
                                avoid = true;
                            }
                        }
                    }
                    A_WALL => {
                        let t = (c.age as i32 - a.warn as i32).max(0);
                        let r = a.px - (a.px - crate::boss::WALL_END_PX) * t.min(a.dur as i32) / a.dur.max(1) as i32;
                        let d = isqrt(((x - cx) as i64).pow(2) + ((y - cy) as i64).pow(2));
                        if d < r as i64 + 70 {
                            // Through the door.
                            let (dx, dy) = at_angle((c.angle >> 4).rem_euclid(360), 1000);
                            let (gx, gy) = (cx + dx * (r + 120) / 1000, cy + dy * (r + 120) / 1000);
                            goal = Some((gx, gy, GOAL_W * 8));
                            avoid = true;
                        }
                    }
                    _ => {}
                }
            }
            if avoid && goal.is_none_or(|g| g.2 < GOAL_W * 8) {
                vx += ax;
                vy += ay;
                goal = None;
            }
            let d = isqrt(((x - bx) as i64).pow(2) + ((y - by) as i64).pow(2));
            boss_near = d < 400;
            if goal.is_none() && self.plan.objectives {
                let hold = match role {
                    Role::Melee => 60,
                    Role::Healer => 80,
                    Role::Ranged => 220,
                };
                if d > hold {
                    goal = Some((bx, by, GOAL_W));
                } else if d < hold / 2 && role == Role::Ranged {
                    goal = Some((x + (x - bx), y + (y - by), GOAL_W / 2));
                }
            }
        }
        // A lit altar of a tide: go and stay within its circle.
        if goal.is_none() && self.plan.objectives && f.tide() && f.boss().is_none() {
            let mut best: Option<(i64, usize)> = None;
            for a in 0..6 {
                if f.altars()[a].state == ALTAR_LIT {
                    let (ax, ay) = f.terrain().altars[a];
                    let dd = d2(ax, ay, h.x, h.y);
                    if best.is_none_or(|(bd, _)| dd < bd) {
                        best = Some((dd, a));
                    }
                }
            }
            if let Some((dd, a)) = best {
                let (ax, ay) = f.terrain().altars[a];
                if dd > (90 * SUB as i64) * (90 * SUB as i64) {
                    goal = Some((ax / SUB, ay / SUB, GOAL_W * 2));
                } else {
                    // Inside the circle: drift back to its middle slowly while the fight pushes around.
                    goal = Some((ax / SUB, ay / SUB, GOAL_W / 3));
                }
            }
        }
        // A full haul: bank at the nearest waystone.
        let mut interact = false;
        // A delving hero who set out for the stone keeps going when a monster comes near (else she sways between
        // the stone and her way whenever one is at the edge of 150 px).
        if self.plan.delve && (h.coin < self.plan.bank_coin || h.banked) {
            self.banking = false;
        }
        let go_bank = h.coin >= self.plan.bank_coin && (n150 == 0 || self.banking);
        if goal.is_none() && !vault && go_bank {
            self.banking = self.plan.delve;
            let w = f.terrain().waystones.iter().enumerate().map(|(_, p)| *p).min_by_key(|&(wx, wy)| d2(wx, wy, h.x, h.y));
            if let Some((wx, wy)) = w {
                if d2(wx, wy, h.x, h.y) < (WAYSTONE_PX as i64 * SUB as i64 - 8 * SUB as i64).pow(2) {
                    // On the stone: hold interact until banked, then go.
                    interact = !h.banked;
                    goal = Some((x, y, 0));
                    vx = 0;
                    vy = 0;
                    if h.banked {
                        goal = None;
                    }
                } else if !h.banked {
                    goal = Some((wx / SUB, wy / SUB, GOAL_W * 2));
                    // A delving hero walks round the walls between, as on her way.
                    if self.plan.delve {
                        if let Some((px, py)) = self.waypoint(f, x, y, wx / SUB, wy / SUB) {
                            goal = Some((px, py, GOAL_W * 2));
                        }
                    }
                }
            }
        }
        // A delve: on to the next quiet zone, or back to the nearest one to rest.
        if goal.is_none() && self.plan.delve && !vault && !f.terrain().quiet.is_empty() {
            if let Some((gx, gy, w)) = self.delve_goal(f, h) {
                match self.waypoint(f, x, y, gx, gy) {
                    Some((wx, wy)) => goal = Some((wx, wy, w.max(1))),
                    None if w == 0 => {
                        goal = Some((x, y, 0));
                        if (x - gx).abs() + (y - gy).abs() > 24 {
                            goal = Some((gx, gy, GOAL_W / 3));
                        }
                    }
                    None => goal = Some((gx, gy, w)),
                }
            }
        }
        // Patrol: a ring clockwise around the heart; a vault's middle; a crowd's heart.
        if goal.is_none() {
            let (cx, cy) = (FIELD / 2 / SUB, FIELD / 2 / SUB);
            let (rx, ry) = ((x - cx) as i64, (y - cy) as i64);
            let rl = isqrt(rx * rx + ry * ry).max(1);
            if self.plan.rally_px > 0 && rl > self.plan.rally_px as i64 {
                goal = Some((cx, cy, GOAL_W));
            } else if vault {
                goal = Some((cx, cy, if rl > 500 { GOAL_W } else { GOAL_W / 6 }));
                // Circle a little so a crowd on her does not stop her.
                vx += -ry * 600 / rl;
                vy += rx * 600 / rl;
            } else if self.plan.rally_px == 0 {
                let ring = if role == Role::Ranged || self.plan.ring_px > 0 { self.plan.ring_px as i64 } else { 4_200 };
                let (tx, ty) = (-ry * PATROL_W / rl, rx * PATROL_W / rl);
                let pull = ((ring - rl) * PATROL_W / 400).clamp(-PATROL_W, PATROL_W);
                // The patrol's target: a point of the ring a little ahead. When walls stand between, walk the
                // way around them that a search of the cells finds, as a person would.
                let (ax, ay) = (rx - ry * nav::NAV_AHEAD_PCT / 100, ry + rx * nav::NAV_AHEAD_PCT / 100);
                let al = isqrt(ax * ax + ay * ay).max(1);
                let (gx, gy) = ((cx as i64 + ax * ring / al) as i32, (cy as i64 + ay * ring / al) as i32);
                match self.waypoint(f, x, y, gx, gy) {
                    Some((wx, wy)) => {
                        let (ex, ey) = ((wx - x) as i64, (wy - y) as i64);
                        let d = isqrt(ex * ex + ey * ey).max(1);
                        vx += ex * nav::NAV_W / d;
                        vy += ey * nav::NAV_W / d;
                    }
                    None => {
                        vx += tx + pull * rx / rl;
                        vy += ty + pull * ry / rl;
                    }
                }
            }
        }
        // Healers stay with the party.
        if (role == Role::Healer && f.heroes().len() > 1) || (f.heroes().len() > 1 && f.heroes().len() <= PARTY_MAX) {
            let (mut sx, mut sy, mut n) = (0i64, 0i64, 0i64);
            for (q, a) in f.heroes().iter().enumerate() {
                if q as u16 != self.id && a.alive() && d2(a.x, a.y, h.x, h.y) < (300 * SUB as i64) * (300 * SUB as i64) {
                    sx += (a.x / SUB) as i64;
                    sy += (a.y / SUB) as i64;
                    n += 1;
                }
            }
            if n > 0 && goal.is_none_or(|g| g.2 < GOAL_W) {
                let (ex, ey) = ((sx / n - x as i64), (sy / n - y as i64));
                let d = isqrt(ex * ex + ey * ey).max(1);
                if d > 60 {
                    vx += ex * GOAL_W / d;
                    vy += ey * GOAL_W / d;
                }
            }
        }
        if let Some((gx, gy, w)) = goal {
            let (ex, ey) = ((gx - x) as i64, (gy - y) as i64);
            let d = isqrt(ex * ex + ey * ey).max(1);
            vx += ex * w / d;
            vy += ey * w / d;
        }
        // Melee engages: a thin crowd is walked into.
        if role == Role::Melee && n150 < 3 && goal.is_none_or(|g| g.2 < GOAL_W) {
            let r = 400 * SUB;
            let mut near: Option<(i64, i32, i32)> = None;
            let mut seen = 0u32;
            grid_box(f.grid(), CELLS_W, CELL_SHIFT, h.x - r, h.y - r, h.x + r, h.y + r, |i| {
                let i = i as usize;
                if m.hp[i] > 0 && m.flags[i] & crate::BOSS == 0 {
                    seen += 1;
                    let dd = d2(m.x[i], m.y[i], h.x, h.y);
                    if near.is_none_or(|(bd, _, _)| dd < bd) {
                        near = Some((dd, m.x[i] / SUB, m.y[i] / SUB));
                    }
                }
            });
            if let Some((_, mx, my)) = near.filter(|_| seen <= ENGAGE_MAX) {
                let (ex, ey) = ((mx - x) as i64, (my - y) as i64);
                let d = isqrt(ex * ex + ey * ey).max(1);
                vx += ex * GOAL_W / d;
                vy += ey * GOAL_W / d;
            }
        }

        let vmag = isqrt(vx * vx + vy * vy);
        // The direction: the best of the eight that does not walk into a wall.
        let mut best = (i64::MIN, 0u16);
        let start = (rng_next(&mut self.rng) % 8) as usize;
        // The second pass, when all eight are shut by the near walls or the rim, asks only that the next step is free.
        for pass in 0..2u8 {
            if best.1 != 0 {
                break;
            }
            for j in 0..8 {
                let k = (start + j) % 8 + 1;
                let (ox, oy) = DIRS[k];
                let ahead = |px: i32| f.terrain().wall(h.x + ox * px * SUB, h.y + oy * px * SUB);
                if ahead(20)
                    || (pass == 0
                        && (ahead(44)
                            || (!vault
                                && ((h.x + ox * 60 * SUB) < 300 * SUB
                                    || (h.y + oy * 60 * SUB) < 300 * SUB
                                    || (h.x + ox * 60 * SUB) > FIELD - 300 * SUB
                                    || (h.y + oy * 60 * SUB) > FIELD - 300 * SUB))))
                {
                    continue;
                }
                let len = if ox != 0 && oy != 0 { 181 } else { 256 };
                // Risk: how close each monster comes in the next `HORIZON_TICKS` if it walks straight at where the hero
                // is now while she walks this way.
                let hv = HERO_STEP as i64 * 16 / SUB as i64;
                let (hvx, hvy) = (ox as i64 * hv * len as i64 / 256, oy as i64 * hv * len as i64 / 256);
                let mut risk = 0i64;
                for &(rx, ry, sp) in &near {
                    let d = isqrt(rx * rx + ry * ry).max(1);
                    // The monster's velocity, toward the hero (at the origin).
                    let (mvx, mvy) = (-rx * sp / d, -ry * sp / d);
                    let (vrx, vry) = (mvx - hvx, mvy - hvy);
                    let vv = vrx * vrx + vry * vry;
                    let t = if vv == 0 { 0 } else { (-(rx * vrx + ry * vry) / vv).clamp(0, HORIZON_TICKS) };
                    let (cx, cy) = (rx + vrx * t, ry + vry * t);
                    let dmin2 = (cx * cx + cy * cy) / 256;
                    risk += FLEE_K / (dmin2 + 100);
                }
                let s = (ox as i64 * vx + oy as i64 * vy) * len / 256 - risk * RISK_W * flee_w / 3 / 10;
                let s = s + if k as u16 == self.input & 15 { vmag / 5 } else { 0 };
                if s > best.0 {
                    best = (s, k as u16);
                }
            }
        }
        let still = goal.is_some_and(|g| g.2 == 0 && vx == 0 && vy == 0);
        let dir = if still || (self.plan.objectives && n60 >= STAND_CROWD && goal.is_none_or(|g| g.2 < GOAL_W * 4)) { 0 } else { best.1 };

        // Skills.
        let hurt_ally = f.heroes().iter().enumerate().any(|(q, a)| {
            q as u16 != self.id
                && a.present
                && (a.downed > 0 || a.health * 2 < a.max_health)
                && d2(a.x, a.y, h.x, h.y) < (200 * SUB as i64) * (200 * SUB as i64)
        });
        let thick = n150 >= 3 || (n60 >= 3 && role != Role::Ranged);
        if thick || boss_near || (role == Role::Healer && hurt_ally) || (h.health * 2 < h.max_health && n60 > 0) {
            press |= IN_SKILL1 | IN_SKILL2;
        }
        if n150 >= 5 || boss_near || (role == Role::Healer && hurt_ally && n150 > 2) {
            press |= IN_ULT;
        }
        if interact {
            press |= IN_INTERACT;
        }

        // Cards and potions fire on the press: let go every other decision.
        let released = self.input & 0xFF00 == 0;
        if released {
            if !h.offers.is_empty() {
                let picks: &[u8] = match role {
                    Role::Melee => &PICKS_MELEE,
                    Role::Ranged => &PICKS_RANGED,
                    Role::Healer => &PICKS_HEALER,
                };
                let offer = &h.offers[0];
                let mut choice = 1u16;
                'find: for &want in picks {
                    for (k, &c) in offer.iter().enumerate() {
                        if c == want && h.copies[c as usize] < MAX_COPIES {
                            choice = k as u16 + 1;
                            break 'find;
                        }
                    }
                }
                // Never pick a slot that is empty (a draw of three has no fourth).
                if offer[(choice - 1) as usize] == 0 {
                    choice = 1;
                }
                b1 |= choice << IN_PICK_SHIFT;
            }
            for (slot, &(p, n)) in h.belt.iter().enumerate() {
                if n == 0 || h.belt_rest[slot] > 0 {
                    continue;
                }
                let low = h.health * 100 < h.max_health * 45;
                let fire = match p {
                    P_HEALING => low,
                    P_VEIL => h.health * 100 < h.max_health * 30 && n60 > 2,
                    P_WHETSTONE => n150 >= 8 || boss_near,
                    P_INK | P_GAMBLER => true,
                    _ => false,
                };
                if fire {
                    b1 |= IN_POTION1 << slot;
                    break;
                }
            }
        }
        let _ = (PCELLS_W, PCELL_SHIFT);
        dir | press | b1
    }
}
