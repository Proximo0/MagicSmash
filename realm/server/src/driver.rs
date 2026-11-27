//! A hero the host plays itself: the realm's bots (the long soak and the compressed week) are real heroes from
//! the store with a ticket, but their input comes from the core's class bot (`realm_core::bots`) on the host,
//! not from a client over UDP, so a test realm of hundreds of heroes costs no follower simulations. Their inputs
//! go into the tick record like any other (followers see them as players).
//!
//! A driven hero fights for her outing's ticks (`Drive::ticks`), then walks to the nearest waystone and holds
//! interact until she banks and leaves (rules section 7). If she has not left `DRIVE_HOME_TICKS` later (walls,
//! a crowd on the stone) the host recalls her, which banks everything as a kick does. In a vault she fights
//! until the run ends (no waystones).

use crate::bots::dir_toward;
use realm_core::bots::{Bot, Plan};
use realm_core::tables::WAYSTONE_PX;
use realm_core::{Field, IN_DIR, IN_INTERACT, IN_SKILL1, IN_SKILL2, SUB};

/// Ticks a driven hero has to reach a waystone and leave before she is recalled (60 s).
pub const DRIVE_HOME_TICKS: u32 = 1_200;
/// The ring a driven hero patrolled in a field (px from the heart) before she delved from quiet zone to quiet zone
/// (`Plan::delve`, rules 6); kept for tools that still patrol.
pub const DRIVE_RING_PX: i32 = 4_200;
/// She walks straight at the stone; stuck this many ticks on a wall, she wanders a little.
const STUCK_TICKS: u32 = 30;
const WANDER_TICKS: u32 = 20;

/// The order to play a hero: the bot's seed and how long she fights before going home.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Drive {
    pub seed: u64,
    pub ticks: u32,
}

pub struct Driver {
    id: u16,
    seed: u64,
    bot: Bot,
    home_at: u32,
    give_up_at: u32,
    vault: bool,
    last: (i32, i32),
    still: u32,
    wander: u32,
}

/// What a driven hero does this tick.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Act {
    Input(u16),
    /// Take her out (banked, as a kick).
    Recall,
}

impl Driver {
    pub fn new(id: u16, d: &Drive, tick: u32, vault: bool) -> Driver {
        let home_at = tick.saturating_add(d.ticks);
        Driver {
            id,
            seed: d.seed,
            bot: Bot::new(id, d.seed, Plan::delve()),
            home_at,
            give_up_at: home_at.saturating_add(DRIVE_HOME_TICKS),
            vault,
            last: (0, 0),
            still: 0,
            wander: 0,
        }
    }

    /// The order that is left at `tick` (for a hero moved to another copy).
    pub fn drive_at(&self, tick: u32) -> Drive {
        Drive { seed: self.seed, ticks: self.home_at.saturating_sub(tick) }
    }

    pub fn act(&mut self, f: &Field) -> Act {
        let tick = f.tick();
        if self.vault || tick < self.home_at {
            return Act::Input(self.bot.act(f));
        }
        if tick >= self.give_up_at {
            return Act::Recall;
        }
        let Some(h) = f.players().get(self.id as usize).filter(|h| h.present) else { return Act::Input(0) };
        if !h.alive() {
            return Act::Input(0);
        }
        let t = f.terrain();
        let (wx, wy) = t.waystones.iter().copied().min_by_key(|&(wx, wy)| (wx as i64 - h.x as i64).pow(2) + (wy as i64 - h.y as i64).pow(2)).unwrap_or(t.gate);
        let (dx, dy) = (wx - h.x, wy - h.y);
        let reach = ((WAYSTONE_PX - 12) * SUB) as i64;
        if (dx as i64).pow(2) + (dy as i64).pow(2) <= reach * reach {
            // At the stone: hold interact, fight with skills where she stands.
            let fight = self.bot.act(f) & !IN_DIR;
            return Act::Input(fight | IN_INTERACT | IN_SKILL1 | IN_SKILL2);
        }
        if (h.x, h.y) == self.last {
            self.still += 1;
        } else {
            self.still = 0;
        }
        self.last = (h.x, h.y);
        if self.still > STUCK_TICKS {
            self.wander = WANDER_TICKS;
            self.still = 0;
        }
        if self.wander > 0 {
            self.wander -= 1;
            return Act::Input(((tick / 5) % 8 + 1) as u16);
        }
        Act::Input(dir_toward(dx, dy) as u16)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use realm_core::{Config, Event, Outing, Sheet};

    #[test]
    fn a_driven_hero_fights_then_banks_and_leaves_by_a_waystone_or_is_recalled() {
        let mut f = Field::open(0, 11, Config { monsters: 300, threads: 1 });
        let (wx, wy) = f.terrain().waystones[0];
        let id = f.join(&Sheet::bench(1, 0, 12), &Outing::new(), wx + 200 * SUB, wy);
        let mut d = Driver::new(id, &Drive { seed: 5, ticks: 100 }, f.tick(), false);
        let (mut left, mut recalled) = (false, false);
        for _ in 0..100 + DRIVE_HOME_TICKS + 5 {
            let inp = match d.act(&f) {
                Act::Input(i) => i,
                Act::Recall => {
                    recalled = true;
                    break;
                }
            };
            let mut inputs = vec![0u16; f.players().len()];
            inputs[id as usize] = inp;
            f.step(&inputs);
            if f.events().iter().any(|e| matches!(e, Event::Leave { hero } if *hero == id)) {
                left = true;
                break;
            }
        }
        assert!(left || recalled, "she went home one way or the other");
        assert!(left, "from 200 px of a waystone on the road she leaves by it");
    }
}
