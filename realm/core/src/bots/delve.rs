//! The delve (rules 6, quiet zones): a bot walks from the entrance through the quiet zones' shrines to the deepest one and back,
//! fighting on the way, and when hurt goes to the nearest quiet zone to rest.

use super::{Bot, GOAL_W, Role, role_of};
use crate::hero::Hero;
use crate::util::d2;
use crate::{CELL_SHIFT, Field, SUB};

/// A delving hero under this share of health (percent) goes to the nearest quiet zone, and rests there until
/// `REST_UNTIL_PCT` or `REST_TICKS` have passed (no field heals by itself: a draught or TEMPERANCE does).
const RETREAT_PCT: u32 = 40;
const REST_UNTIL_PCT: u32 = 80;
const REST_TICKS: u32 = 200;
/// The pull of a delve's next zone: under `GOAL_W` so a melee hero still walks into a thin crowd on the way.
const DELVE_W: i64 = GOAL_W * 2 / 3;
/// A melee hero or healer above this share of health (percent) pushes on through a crowd.
const DELVE_PUSH_PCT: u32 = 60;

impl Bot {
    /// The delve's target (px) and pull: the next shrine zone in depth order (ping-pong between the first and the
    /// deepest intermission), or, hurt, the nearest quiet zone of any kind with a strong pull, and once inside it a
    /// rest (pull 0) until she is well or the rest is over.
    pub(super) fn delve_goal(&mut self, f: &Field, h: &Hero) -> Option<(i32, i32, i64)> {
        let t = f.terrain();
        let tick = f.tick();
        let me = (h.x, h.y);
        if h.health * 100 < h.max_health * RETREAT_PCT && !self.resting {
            self.resting = true;
            self.rest_until = u32::MAX;
        }
        if self.resting {
            if t.quiet(h.x, h.y) && self.rest_until == u32::MAX {
                self.rest_until = tick + REST_TICKS;
            }
            if h.health * 100 >= h.max_health * REST_UNTIL_PCT || tick >= self.rest_until {
                self.resting = false;
            } else {
                let z = t.quiet.iter().min_by_key(|z| (d2(z.x, z.y, me.0, me.1), z.x, z.y))?;
                let inside = t.quiet(h.x, h.y);
                return Some((z.x / SUB, z.y / SUB, if inside { 0 } else { GOAL_W * 3 }));
            }
        }
        let mut route: Vec<&crate::QuietZone> = t.quiet.iter().filter(|z| z.shrine != crate::NO_SHRINE && z.shrine > 0).collect();
        route.sort_by_key(|z| z.shrine);
        if route.is_empty() {
            return None;
        }
        let n = route.len() as u8;
        self.leg = self.leg.clamp(1, n);
        let z = route[self.leg as usize - 1];
        let reach = ((z.r - 2).max(1) << CELL_SHIFT) as i64;
        if d2(z.x, z.y, me.0, me.1) <= reach * reach {
            // Reached: on to the next, turning at either end.
            if self.inward && self.leg >= n {
                self.inward = false;
            } else if !self.inward && self.leg <= 1 {
                self.inward = true;
            }
            self.leg = if self.inward { (self.leg + 1).min(n) } else { self.leg.saturating_sub(1).max(1) };
            self.nav = None;
        }
        let z = route[self.leg as usize - 1];
        // Well and able to stand in a crowd: a pull stronger than the flight, so a horde waiting at a quiet zone's
        // edge is fought through instead of holding her in the zone.
        let strong = role_of(h.class) != Role::Ranged && h.health * 100 >= h.max_health * DELVE_PUSH_PCT;
        Some((z.x / SUB, z.y / SUB, if strong { GOAL_W * 2 } else { DELVE_W }))
    }
}
