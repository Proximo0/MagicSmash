//! The six fields (rules section 6): level ranges, kinds, terrain rules and the sites table.

/// The terrain rules, one generator each (`terrain.rs`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Rule {
    /// Open; hedges and ruins; a plague road (heroes walk 10% faster on it).
    Road,
    /// Tree walls with paths 6 to 10 cells wide.
    Wood,
    /// Mire slows heroes 30%; dark fog.
    Marsh,
    /// Ridges with passes 6 cells wide; spitters hold the high side.
    Peaks,
    /// Rooms and corridors, doors 6 cells wide.
    Tower,
    /// Islands joined by bridges 8 cells wide; all rules at once.
    Edge,
}

/// A site: angle in degrees clockwise from east (y down) and distance from the heart in px.
pub type Site = (i32, i32);

#[derive(Clone, Copy, Debug)]
pub struct FieldRow {
    pub name: &'static str,
    pub bottom: u8,
    pub top: u8,
    pub rule: Rule,
    /// Its kinds are `KINDS[first..first + count]`.
    pub first_kind: u8,
    pub kind_count: u8,
    /// Seven WAYSTONES: three in the edge ring, three in the middle, one on the heart's rim.
    pub waystones: [Site; 7],
    /// Six WAR ALTAR sites in the middle ring.
    pub altars: [Site; 6],
    /// Spitter bolts fly over walls (they hold the high side).
    pub high_ground: bool,
}

const EDGE_R: i32 = 7_000;
const MID_R: i32 = 4_200;
const RIM_R: i32 = 2_400;
const ALTAR_R: i32 = 4_600;

pub const FIELDS: [FieldRow; 6] = [
    FieldRow {
        name: "THE FOOL'S ROAD",
        bottom: 1,
        top: 10,
        rule: Rule::Road,
        first_kind: 0,
        kind_count: 6,
        waystones: [(115, EDGE_R), (215, EDGE_R), (340, EDGE_R), (60, MID_R), (180, MID_R), (300, MID_R), (100, RIM_R)],
        altars: [(30, ALTAR_R), (90, ALTAR_R), (150, ALTAR_R), (210, ALTAR_R), (270, ALTAR_R), (330, ALTAR_R)],
        high_ground: false,
    },
    FieldRow {
        name: "THE HANGED WOOD",
        bottom: 10,
        top: 20,
        rule: Rule::Wood,
        first_kind: 6,
        kind_count: 7,
        waystones: [(120, EDGE_R), (230, EDGE_R), (350, EDGE_R), (45, MID_R), (165, MID_R), (285, MID_R), (80, RIM_R)],
        altars: [(15, ALTAR_R), (75, ALTAR_R), (135, ALTAR_R), (195, ALTAR_R), (255, ALTAR_R), (315, ALTAR_R)],
        high_ground: false,
    },
    FieldRow {
        name: "THE MOON MARSH",
        bottom: 20,
        top: 30,
        rule: Rule::Marsh,
        first_kind: 13,
        kind_count: 7,
        waystones: [(110, EDGE_R), (200, EDGE_R), (320, EDGE_R), (70, MID_R), (190, MID_R), (310, MID_R), (120, RIM_R)],
        altars: [(40, ALTAR_R), (100, ALTAR_R), (160, ALTAR_R), (220, ALTAR_R), (280, ALTAR_R), (340, ALTAR_R)],
        high_ground: false,
    },
    FieldRow {
        name: "THE HERMIT'S PEAKS",
        bottom: 30,
        top: 40,
        rule: Rule::Peaks,
        first_kind: 20,
        kind_count: 7,
        waystones: [(125, EDGE_R), (225, EDGE_R), (330, EDGE_R), (50, MID_R), (170, MID_R), (290, MID_R), (90, RIM_R)],
        altars: [(20, ALTAR_R), (80, ALTAR_R), (140, ALTAR_R), (200, ALTAR_R), (260, ALTAR_R), (320, ALTAR_R)],
        high_ground: true,
    },
    FieldRow {
        name: "THE TOWER",
        bottom: 40,
        top: 50,
        rule: Rule::Tower,
        first_kind: 27,
        kind_count: 8,
        waystones: [(135, EDGE_R), (225, EDGE_R), (315, EDGE_R), (45, MID_R), (135, MID_R), (270, MID_R), (90, RIM_R)],
        altars: [(0, ALTAR_R), (60, ALTAR_R), (120, ALTAR_R), (180, ALTAR_R), (240, ALTAR_R), (300, ALTAR_R)],
        high_ground: false,
    },
    FieldRow {
        name: "THE WORLD'S EDGE",
        bottom: 50,
        top: 60,
        rule: Rule::Edge,
        first_kind: 35,
        kind_count: 7,
        waystones: [(105, EDGE_R), (210, EDGE_R), (335, EDGE_R), (65, MID_R), (185, MID_R), (305, MID_R), (110, RIM_R)],
        altars: [(25, ALTAR_R), (85, ALTAR_R), (145, ALTAR_R), (205, ALTAR_R), (265, ALTAR_R), (325, ALTAR_R)],
        high_ground: true,
    },
];

/// Class XP (and coin) of a kill by the kind's field, in percent (job B1, `balance.md`). THE TOWER's rooms and
/// corridors let a hero kill about a tenth of what the open fields give an hour, so a kill there pays more;
/// without it the curve fell eightfold at level 40 and a hero of 40 to 50 was better off in THE HERMIT'S PEAKS.
pub const FIELD_KILL_XP_PCT: [u32; 6] = [100, 100, 100, 100, 800, 100];

// ---- rings
pub const HEART_PX: i32 = 2_500;
pub const MIDDLE_PX: i32 = 6_000;
/// Levels spread from the rim (this far from the heart) to the centre.
pub const LEVEL_RIM_PX: i32 = 8_192;
pub const RING_EDGE: u8 = 0;
pub const RING_MIDDLE: u8 = 1;
pub const RING_HEART: u8 = 2;
/// Density: target = min(cap, 400 + ring weight per hero).
pub const DENSITY_BASE: u32 = 400;
/// The base is at most this much a hero, so a hero alone (or a small party) is not met by the whole 400:
/// a change from the contract, from the lone kiting bot (rules_built.md).
pub const DENSITY_BASE_PER_HERO: u32 = 60;
pub const RING_WEIGHT: [u32; 3] = [12, 20, 32];
/// The gate from town sits this far in from the south edge (px).
pub const GATE_INSET_PX: i32 = 96;

// ---- terrain
pub const WALL: u8 = 1;
pub const MIRE: u8 = 2;
pub const ROAD: u8 = 4;
pub const DARK: u8 = 8;
/// No passage narrower than this many cells.
pub const MIN_PASSAGE: i32 = 6;
/// Open ground kept around every site (cells).
pub const SITE_CLEAR: i32 = 6;
pub const ROAD_MOVE_PCT: i32 = 10;
pub const MIRE_MOVE_PCT: i32 = -30;
/// Births 400 to 700 px from a hero, 250 to 450 when she stands in the dark.
pub const BIRTH_MIN_PX: i32 = 400;
pub const BIRTH_MAX_PX: i32 = 700;
pub const DARK_BIRTH_MIN_PX: i32 = 250;
pub const DARK_BIRTH_MAX_PX: i32 = 450;
pub const WOOD_PATH_MIN: i32 = 6;
pub const WOOD_PATH_MAX: i32 = 10;
pub const PEAKS_PASS: i32 = 6;
pub const TOWER_DOOR: i32 = 6;
pub const EDGE_BRIDGE: i32 = 8;
