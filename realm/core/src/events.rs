//! Events (rules section 12): the output of a tick, not state, in the contract's order. Within a kind
//! they keep the order they happened in (heroes by id, kills in the order they died).

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Event {
    /// A draw was granted (rules 5): `source` is `GRANT_ENTER`, `GRANT_KILL` or `GRANT_SHRINE`. Its DRAW follows
    /// at once while the queue has room.
    Grant {
        hero: u16,
        source: u8,
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
    /// Section 14 (job R3), appended after the contract's list. The BLOOD MARK was taken, put down, or refused
    /// (`MARK_*` in `pvp.rs`), or a marked realm marked her.
    Mark {
        hero: u16,
        state: u8,
    },
    /// A hero's blow struck a hero: `raw` before her reductions, `amount` taken.
    Struck {
        hero: u16,
        by: u16,
        raw: u32,
        amount: u32,
    },
    /// A hero's blow downed her (a `Down` event of the same tick says so too).
    Slain {
        hero: u16,
        by: u16,
    },
    /// She FELL after a hero downed her: the coin her haul lost went to `by` (0 if `by` had left). The server moves
    /// the haul's lost items to `by` likewise.
    Plunder {
        hero: u16,
        by: u16,
        coin: u32,
    },
    /// A guild war began or ended with its tide; `winner` 0 or 1 (`guilds[winner]`) or `WAR_DRAW`; held altar ticks.
    War {
        war: u64,
        state: u8,
        winner: u8,
        held: [u32; 2],
    },
    /// A duel began, was won or was drawn.
    Duel {
        state: u8,
        winner: u16,
        loser: u16,
    },
}

impl Event {
    /// Position in the contract's list.
    pub fn rank(&self) -> u8 {
        match self {
            Event::Grant { .. } => 0,
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
            Event::Mark { .. } => 17,
            Event::Struck { .. } => 18,
            Event::Slain { .. } => 19,
            Event::Plunder { .. } => 20,
            Event::War { .. } => 21,
            Event::Duel { .. } => 22,
        }
    }
}
