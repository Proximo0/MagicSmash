//! The places a hero can walk to, and the numbers of the street and the house grid. A place is a kind and an
//! argument (a street number, a house plot, a guild); `key` makes the number a `Towns` room is tagged with.
//! Every number here is explained in `docs/realm/homes.md`.

pub const PLAZA: u8 = 0;
pub const TAVERN: u8 = 1;
pub const MARKET: u8 = 2;
pub const GUILD_HALL: u8 = 3;
pub const YARD: u8 = 4;
pub const STREET: u8 = 5;
pub const HOUSE: u8 = 6;
pub const KINDS: u8 = 7;

/// The room tag of a place. The plaza with argument 0 is key 0, the room every hero arrives in.
pub fn key(kind: u8, arg: u32) -> u64 {
    ((kind as u64) << 32) | arg as u64
}

/// (heroes a room holds, whether another room opens when it is full). Houses, guild halls and streets are one room
/// each per argument: a full house says so. The public squares open another room.
pub fn rules(kind: u8) -> Option<(usize, bool)> {
    Some(match kind {
        PLAZA => (100, true),
        TAVERN => (60, true),
        MARKET => (100, true),
        YARD => (40, true),
        GUILD_HALL => (100, false),
        STREET => (100, false),
        HOUSE => (HOUSE_VISITORS, false),
        _ => return None,
    })
}

/// Heroes inside one house at once, the owner included.
pub const HOUSE_VISITORS: usize = 16;

// ---- streets and plots
pub const PLOTS_PER_STREET: u32 = 24;
/// A street opens when the one before has this many plots taken (three in four), so a new account finds a free
/// plot on a street that is alive, and a street is never a row of 24 empty doors.
pub const STREET_OPENS_AT: u32 = 18;
/// Streets there can ever be (the plot number is a u32: 24 x this stays far inside it).
pub const STREETS_MAX: u32 = 10_000;

/// Plot ids count from 0: street 1 holds 0..24. Streets count from 1.
pub fn plot_id(street: u32, index: u32) -> u32 {
    (street - 1) * PLOTS_PER_STREET + index
}
pub fn street_of(plot: u32) -> u32 {
    plot / PLOTS_PER_STREET + 1
}
pub fn index_of(plot: u32) -> u32 {
    plot % PLOTS_PER_STREET
}

/// What a plot costs relative to the base, in percent: the first six doors face the plaza end, the last six are the
/// back lane.
pub fn tier_pct(index: u32) -> u64 {
    match index {
        0..=5 => 200,
        6..=17 => 100,
        _ => 70,
    }
}

// ---- the house grid: two rooms of 10 x 10 cells, one cell a piece of furniture. A cell number is
// `room * 100 + y * 10 + x` and is the item's slot in the store's HOUSE place (200 slots).
pub const GRID_W: u32 = 10;
pub const GRID_H: u32 = 10;
pub const ROOMS: u32 = 2;
pub const CELLS: u32 = GRID_W * GRID_H * ROOMS;
/// A house room is drawn in the 4096 px room with a cell this wide, the grid centred.
pub const CELL_PX: u32 = 128;
pub const GRID_ORIGIN_PX: u32 = (4096 - GRID_W * CELL_PX) / 2;

pub fn cell_xy(cell: u32) -> (u32, u32, u32) {
    let r = cell / (GRID_W * GRID_H);
    let c = cell % (GRID_W * GRID_H);
    (r, c % GRID_W, c / GRID_W)
}
/// Centre of a cell in the room's px.
pub fn cell_px(cell: u32) -> (u16, u16) {
    let (_, x, y) = cell_xy(cell);
    ((GRID_ORIGIN_PX + x * CELL_PX + CELL_PX / 2) as u16, (GRID_ORIGIN_PX + y * CELL_PX + CELL_PX / 2) as u16)
}

// ---- campfires: where a hero may sit. A hero is "at" a fire when she is within `FIRE_REACH_PX` of it.
pub const FIRE_REACH_PX: i32 = 160;
const PLAZA_FIRES: [(u16, u16); 2] = [(1850, 2048), (2250, 2048)];
const TAVERN_FIRES: [(u16, u16); 1] = [(2048, 2048)];
const YARD_FIRES: [(u16, u16); 1] = [(2300, 2200)];
const HALL_FIRES: [(u16, u16); 1] = [(2048, 1800)];

/// The fixed fires of a place (a house has one where its HEARTH stands).
pub fn fires(kind: u8) -> &'static [(u16, u16)] {
    match kind {
        PLAZA => &PLAZA_FIRES,
        TAVERN => &TAVERN_FIRES,
        YARD => &YARD_FIRES,
        GUILD_HALL => &HALL_FIRES,
        _ => &[],
    }
}

pub fn near(a: (u16, u16), b: (u16, u16), reach: i32) -> bool {
    let (dx, dy) = (a.0 as i64 - b.0 as i64, a.1 as i64 - b.1 as i64);
    dx * dx + dy * dy <= (reach as i64) * (reach as i64)
}
