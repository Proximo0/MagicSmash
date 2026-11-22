//! Copies of a field (rules section 11): a hero moves from one copy to another with her outing state, into the
//! same ring. The two calls are made at the same tick of the stream on the server and on every follower, so the
//! hash stays equal everywhere: `transfer_in` draws no random numbers from the field's stream, only from the seed
//! and the salt it is given.

use crate::sheet::{Outing, Sheet};
use crate::tables::*;
use crate::terrain::ring_of;
use crate::util::{at_angle, mix};
use crate::{Field, SUB};

/// Edge-ring arrivals stay this far from the heart at most (px), inside the walls of every field.
pub const ARRIVE_EDGE_MAX_PX: i32 = 7_800;
/// Tries at an open point of the ring before falling back to the ring's waystone.
pub const ARRIVE_TRIES: u64 = 32;

/// A hero in transit: her sheet, her outing and the ring she left from.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Transfer {
    pub sheet: Sheet,
    pub outing: Outing,
    pub ring: u8,
}

impl Field {
    /// Takes a hero out of this copy to be set down in another. None if the slot is empty. A downed hero arrives
    /// up (health at least 1), the way a hero does at any `join`.
    pub fn transfer_out(&mut self, id: u16) -> Option<Transfer> {
        let h = self.heroes.get(id as usize).filter(|h| h.present)?;
        let t = Transfer { sheet: h.sheet.clone(), outing: h.outing(self.tick), ring: ring_of(h.x, h.y) };
        self.leave(id);
        Some(t)
    }

    /// Sets a transferred hero down in this copy at an open point of the same ring; `salt` (the server uses the
    /// character's number) spreads arrivals. Returns her id.
    pub fn transfer_in(&mut self, t: &Transfer, salt: u64) -> u16 {
        let (x, y) = self.ring_point(t.ring, salt);
        self.join(&t.sheet, &t.outing, x, y)
    }

    /// An open point of a ring, from the seed, the tick and the salt alone.
    pub fn ring_point(&self, ring: u8, salt: u64) -> (i32, i32) {
        let (lo, hi) = match ring {
            RING_HEART => (0, HEART_PX),
            RING_MIDDLE => (HEART_PX, MIDDLE_PX),
            _ => (MIDDLE_PX, ARRIVE_EDGE_MAX_PX),
        };
        for k in 0..ARRIVE_TRIES {
            let r = mix(self.seed, salt, self.tick as u64 * 64 + k, 0xA881_0000 + ring as u64);
            let dist = lo + ((r >> 8) % (hi - lo) as u64) as i32;
            let (dx, dy) = at_angle((r % 360) as i32, dist * SUB);
            let (x, y) = (self.terrain.heart.0 + dx, self.terrain.heart.1 + dy);
            if x > 0 && y > 0 && x < crate::FIELD && y < crate::FIELD && !self.terrain.wall(x, y) && ring_of(x, y) == ring {
                return (x, y);
            }
        }
        let (x, y) = match ring {
            RING_HEART => self.terrain.heart,
            RING_MIDDLE => self.terrain.waystones[3],
            _ => self.terrain.waystones[0],
        };
        self.terrain.nearest_open(x, y)
    }

    /// Heroes present, by ring (edge, middle, heart): what the server balances copies by.
    pub fn heroes_by_ring(&self) -> [u32; 3] {
        let mut n = [0u32; 3];
        for h in self.heroes.iter().filter(|h| h.present) {
            n[ring_of(h.x, h.y) as usize] += 1;
        }
        n
    }
}
