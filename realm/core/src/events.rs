//! Events (rules section 12): the output of a tick, not state, in the contract's order. Within a kind
//! they keep the order they happened in (heroes by id, kills in the order they died).

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Event {
    Level { hero: u16, level: u16 },
    Draw { hero: u16, cards: [u8; 4], n: u8 },
    Pick { hero: u16, card: u8, copies: u8 },
    /// `which`: 1 skill 1, 2 skill 2, 3 the ultimate.
    Skill { hero: u16, which: u8 },
    Potion { hero: u16, slot: u8, left: u8 },
    Down { hero: u16 },
    Raise { hero: u16, by: u16 },
    Fallen { hero: u16, coin: u32 },
    /// `waystone` 0..6, or `NO_WAYSTONE` for the gate.
    Bank { hero: u16, coin: u32, waystone: u8 },
    Leave { hero: u16 },
    /// The credited heroes are `Field::credited(first, count)`. `flags`: `ELITE`, `CHAMPION`.
    Kill { kind: u8, level: u8, flags: u8, x: i32, y: i32, first: u32, count: u16 },
    /// Class XP earned this tick (summed).
    Xp { hero: u16, amount: u32 },
}

impl Event {
    /// Position in the contract's list.
    pub fn rank(&self) -> u8 {
        match self {
            Event::Level { .. } => 0,
            Event::Draw { .. } => 1,
            Event::Pick { .. } => 2,
            Event::Skill { .. } => 3,
            Event::Potion { .. } => 4,
            Event::Down { .. } => 5,
            Event::Raise { .. } => 6,
            Event::Fallen { .. } => 7,
            Event::Bank { .. } => 8,
            Event::Leave { .. } => 9,
            Event::Kill { .. } => 10,
            Event::Xp { .. } => 11,
        }
    }
}
