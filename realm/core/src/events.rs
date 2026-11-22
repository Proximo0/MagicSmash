//! Events (rules section 12): the output of a tick, not state, in the contract's order. Within a kind
//! they keep the order they happened in (heroes by id, kills in the order they died).

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Event {
    Level {
        hero: u16,
        level: u16,
    },
    Draw {
        hero: u16,
        cards: [u8; 4],
        n: u8,
    },
    Pick {
        hero: u16,
        card: u8,
        copies: u8,
    },
    /// `which`: 1 skill 1, 2 skill 2, 3 the ultimate.
    Skill {
        hero: u16,
        which: u8,
    },
    Potion {
        hero: u16,
        slot: u8,
        left: u8,
    },
    Down {
        hero: u16,
    },
    Raise {
        hero: u16,
        by: u16,
    },
    Fallen {
        hero: u16,
        coin: u32,
    },
    /// `waystone` 0..6, or `NO_WAYSTONE` for the gate.
    Bank {
        hero: u16,
        coin: u32,
        waystone: u8,
    },
    Leave {
        hero: u16,
    },
    /// The credited heroes are `Field::credited(first, count)`. `flags`: `ELITE`, `CHAMPION`.
    Kill {
        kind: u8,
        level: u8,
        flags: u8,
        x: i32,
        y: i32,
        first: u32,
        count: u16,
    },
    /// Class XP earned this tick (summed).
    Xp {
        hero: u16,
        amount: u32,
    },
    /// A tide of the field began, was WON or LOST (`TIDE_BEGIN`, `TIDE_WON`, `TIDE_LOST`); `index` counts its tides.
    Tide {
        state: u8,
        index: u32,
    },
    /// An altar of the six lit, was HELD, was RUINED, or went dark (`ALTAR_*`).
    Altar {
        index: u8,
        state: u8,
    },
    /// A boss (`which` is a `BOSSES` row) rose, entered a phase (`health` is its health then), was killed or left.
    Boss {
        which: u8,
        state: u8,
        health: u32,
    },
    /// A chest is paid (`R_*`): the heroes past the floor are `Field::rewarded(first, count)`, best first, each with
    /// her contribution (a lost vault: her coin). `source` is the field, `level` the field's top or the vault's
    /// level, `seals` a vault's seals.
    Reward {
        kind: u8,
        source: u8,
        level: u8,
        seals: u8,
        first: u32,
        count: u16,
    },
    /// A vault run started, a boss rose (`n` of them), was WON (`n` seals) or LOST (`n` minutes survived).
    Vault {
        state: u8,
        n: u8,
    },
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
            Event::Tide { .. } => 12,
            Event::Altar { .. } => 13,
            Event::Boss { .. } => 14,
            Event::Reward { .. } => 15,
            Event::Vault { .. } => 16,
        }
    }
}
