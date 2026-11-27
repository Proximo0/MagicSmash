//! HORDE & HEARTH's simulation core: one field (rules.md sections 1 to 7 and 12), whole numbers only.
//!
//! Positions are `i32` in 1/256 px, time is ticks (20 a second). The same field id, seed, joins and
//! inputs give the same state on every machine and for every thread count; `Field::hash` is the proof.
//! The core takes no clock and does no I/O: `step_with` calls a marker after each phase so the caller can
//! time them. Every number is in `tables/`.

mod act;
mod attack;
mod boss;
pub mod bots;
mod combat;
mod deck;
mod events;
mod flow;
pub mod gates;
mod geo;
mod hero;
mod mods;
mod monster;
pub mod pvp;
#[cfg(test)]
mod probe;
#[cfg(test)]
mod wirefuzz;
mod sheet;
mod spawn;
mod state;
pub mod tables;
mod terrain;
mod terrain_gen;
mod tide;
mod transfer;
mod util;
mod vault;

pub use act::walk_step;
pub use attack::Hit;
pub use boss::{Boss, Cast, Mire};
pub use geo::{in_beam, near_segment};
pub use deck::{CardMods, card_mods, roll as roll_offer};
pub use events::Event;
pub use flow::{NEIGHBOURS, STEP as FLOW_STEP, UNREACHED};
pub use hero::*;
pub use mods::*;
pub use pvp::{Duel, IN_MARK, PHit, Pvp, War};
pub use monster::{BOSS, CHAMPION, CLUTCH_PX, ELITE, Monsters, level_scale, max_hp};
pub use sheet::{Outing, Sheet, class_progress, class_xp_to_reach, line_points, owned_cards};
pub use tables::{CLASSES, KINDS, Kind, TICK_HZ};
pub use terrain::{Terrain, check as check_terrain, level_at, narrow_count, ring_of};
pub use tide::{
    Altar, Realm, boss_due, coin_at, field_boss_window, next_field_boss, next_world_boss, tide_countdown, tide_last, tide_running, tide_start, world_ride,
};
pub use transfer::Transfer;
pub use util::{Grid, grid_box, rng_next};
pub use vault::{RUN_GOING, RUN_LOST, RUN_WON, VaultRun, chest_rolls, seal_scale};

use flow::{Flow, Source};
use tables::*;
use util::par_ranges;

/// A class row (kept under the crowd test's name).
pub type Class = tables::ClassRow;
/// The crowd test called a hero a player.
pub type Player = Hero;

/// Sub-pixel units per pixel.
pub const SUB: i32 = 256;
/// Field side in px.
pub const FIELD_PX: i32 = 16_384;
/// Field side in sub-pixel units.
pub const FIELD: i32 = FIELD_PX * SUB;
/// Flow, terrain and monster-grid cells are 32 px: a position in sub units shifted by 13.
pub const CELL_SHIFT: u32 = 13;
pub const CELLS_W: usize = 512;
pub const CELLS: usize = CELLS_W * CELLS_W;
/// Hero-grid cells are 64 px.
pub const PCELL_SHIFT: u32 = 14;
pub const PCELLS_W: usize = 256;
pub const PCELLS: usize = PCELLS_W * PCELLS_W;
/// The screen, which births stay out of.
pub const VIEW_W: i32 = 480;
pub const VIEW_H: i32 = 270;
/// Monster queries widen by this much (sub units) because the grid is built before monsters move.
pub const GRID_MARGIN: i32 = 12 * SUB;
/// Cells popped by the flow field's search per tick.
pub const FLOW_SLICE: usize = 32_768;
/// Flow head start: every hero's cell starts this far out (tenths of a cell), less `(26 - threat tenths) x 2`
/// cells by threat; a hero using PROVOKE starts at 0, so monsters within 200 px come for him.
pub const FLOW_LEAD: i32 = 70;
pub const THREAT_TOP: i32 = 26;
pub const THREAT_HEAD_MUL: i32 = 2;
/// PROVOKE's threat for the close-range choice (tenths).
pub const PROVOKE_THREAT: i32 = 100;

#[derive(Clone, Debug)]
pub struct Config {
    /// The monster cap (and pool size): births keep the field at `min(cap, 400 + ring weights)`.
    pub monsters: u32,
    /// Worker threads for the heavy phases; never changes the result.
    pub threads: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    /// Heroes: auras, timers, potions, picks, skills without monsters, movement, banking, falls.
    Input,
    Flow,
    /// Recycling, the monster and hero grids, the aura map.
    Grid,
    /// Monster movement and behaviours, throws.
    Move,
    /// Hero strikes, zones, drops, contact, shots, kills with credit, XP and coin.
    Fight,
    /// Births, then the events are put in order.
    Spawn,
}

/// A zone: a circle on the ground that acts every `ZONE_EVERY` ticks.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Zone {
    pub x: i32,
    pub y: i32,
    pub px: i32,
    pub kind: u8,
    pub owner: u16,
    pub left: u16,
    pub age: u16,
    /// Monster damage per act.
    pub dmg: u32,
    /// Ally healing per act, tenths of a percent.
    pub heal_tenths: u32,
}

/// A drop: a circle landing after `left` ticks.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Drop {
    pub x: i32,
    pub y: i32,
    pub px: i32,
    pub left: u16,
    pub dmg: u32,
    pub hero: u16,
    pub stun: u8,
}

/// A monster bolt (`px == 0`, moving) or a lobbed or bursting circle (`px` radius, landing at `left` 0).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Shot {
    pub x: i32,
    pub y: i32,
    pub vx: i32,
    pub vy: i32,
    pub left: u16,
    pub dmg: u32,
    pub px: i32,
}

pub struct Field {
    pub(crate) cfg: Config,
    pub(crate) field: u8,
    pub(crate) seed: u64,
    pub(crate) tick: u32,
    pub(crate) rng: u64,
    pub(crate) terrain: Terrain,
    pub(crate) m: Monsters,
    pub(crate) free: Vec<u32>,
    pub(crate) alive: u32,
    pub(crate) heroes: Vec<Hero>,
    pub(crate) flow: Flow,
    pub(crate) zones: Vec<Zone>,
    pub(crate) drops: Vec<Drop>,
    pub(crate) shots: Vec<Shot>,
    /// A tide is running (rules 8; JUDGEMENT reads it).
    pub(crate) tide: bool,
    /// The clock, the tide's altars, the boss and the vault run: state.
    pub(crate) realm: tide::Realm,
    /// Players against players (section 14): the realm flag, wars, a duel, guild tags, who downed whom.
    pub(crate) pvp: pvp::Pvp,
    /// Births on (a field) or off (tools, tests; later a vault's timeline).
    pub(crate) births: bool,
    pub(crate) kills_total: u64,
    pub(crate) spawns_total: u64,
    pub(crate) deaths_total: u64,
    pub(crate) recycled_total: u64,
    // ---- rebuilt every tick (not state)
    pub(crate) grid: Grid,
    pub(crate) hgrid: Grid,
    pub(crate) aura: Vec<u8>,
    pub(crate) aura_cells: Vec<u32>,
    pub(crate) aura_list: Vec<u32>,
    pub(crate) mods: Vec<Mods>,
    pub(crate) threat: Vec<i32>,
    /// Each hero's flow head start in the finished flow field.
    pub(crate) src_d0: Vec<u16>,
    pub(crate) events: Vec<Event>,
    pub(crate) credits: Vec<u16>,
    /// The heroes of this tick's REWARD events and their contributions.
    pub(crate) reward_list: Vec<(u16, u32)>,
    pub(crate) mcells: Vec<(u32, u32)>,
    pub(crate) hcells: Vec<(u32, u32)>,
    pub(crate) live: Vec<u16>,
    pub(crate) spawned: Vec<u32>,
    pub(crate) dealt: Vec<u32>,
    pub(crate) cxp: Vec<u32>,
}

#[inline]
pub fn cell_of(x: i32, y: i32) -> usize {
    ((y >> CELL_SHIFT) as usize) * CELLS_W + (x >> CELL_SHIFT) as usize
}

#[inline]
pub fn pcell_of(x: i32, y: i32) -> usize {
    ((y >> PCELL_SHIFT) as usize) * PCELLS_W + (x >> PCELL_SHIFT) as usize
}

impl Field {
    /// THE FOOL'S ROAD (field 0) from a seed.
    pub fn new(seed: u64, cfg: Config) -> Field {
        Field::open(0, seed, cfg)
    }

    /// A field (0..5) from its row and a seed: its terrain, level range and kinds.
    pub fn open(field: u8, seed: u64, cfg: Config) -> Field {
        let field = field.min(FIELDS.len() as u8 - 1);
        Field::open_with(field, seed, cfg, terrain::build(field, seed))
    }

    /// A field (or a vault's arena) over a terrain already built.
    pub(crate) fn open_with(field: u8, seed: u64, cfg: Config, terrain: Terrain) -> Field {
        let cap = cfg.monsters as usize;
        Field {
            cfg: Config { monsters: cfg.monsters, threads: cfg.threads.max(1) },
            field,
            seed,
            tick: 0,
            rng: seed,
            terrain,
            m: Monsters::new(cap),
            free: (0..cap as u32).rev().collect(),
            alive: 0,
            heroes: Vec::new(),
            flow: Flow::new(),
            zones: Vec::new(),
            drops: Vec::new(),
            shots: Vec::new(),
            tide: false,
            realm: tide::Realm::new(),
            pvp: pvp::Pvp::default(),
            births: true,
            kills_total: 0,
            spawns_total: 0,
            deaths_total: 0,
            recycled_total: 0,
            grid: Grid::new(CELLS),
            hgrid: Grid::new(PCELLS),
            aura: vec![0; CELLS],
            aura_cells: Vec::new(),
            aura_list: Vec::new(),
            mods: Vec::new(),
            threat: Vec::new(),
            src_d0: Vec::new(),
            events: Vec::new(),
            credits: Vec::new(),
            reward_list: Vec::new(),
            mcells: Vec::new(),
            hcells: Vec::new(),
            live: Vec::new(),
            spawned: Vec::new(),
            dealt: Vec::new(),
            cxp: Vec::new(),
        }
    }

    pub fn set_threads(&mut self, threads: usize) {
        self.cfg.threads = threads.max(1);
    }
    pub fn config(&self) -> &Config {
        &self.cfg
    }
    pub fn field_id(&self) -> u8 {
        self.field
    }
    pub fn seed(&self) -> u64 {
        self.seed
    }
    pub fn tick(&self) -> u32 {
        self.tick
    }
    pub fn terrain(&self) -> &Terrain {
        &self.terrain
    }
    pub fn monsters(&self) -> &Monsters {
        &self.m
    }
    pub fn monster_count(&self) -> u32 {
        self.alive
    }
    pub fn heroes(&self) -> &[Hero] {
        &self.heroes
    }
    /// The crowd test's name for `heroes`.
    pub fn players(&self) -> &[Hero] {
        &self.heroes
    }
    pub fn player_count(&self) -> u32 {
        self.heroes.iter().filter(|p| p.present).count() as u32
    }
    /// This tick's derived numbers of a hero.
    pub fn mods(&self, id: u16) -> Option<&Mods> {
        self.mods.get(id as usize)
    }
    /// Where hero `id` would be after one tick of walking from (x, y) with `input`, at the speed she had in
    /// the last tick (none before her first). Skills that move a hero (a charge, a tumble) are not part of it.
    pub fn walk(&self, id: u16, x: i32, y: i32, input: u16) -> (i32, i32) {
        let move_pct = self.mods.get(id as usize).map_or(0, |m| m.move_pct);
        walk_step(&self.terrain, move_pct, x, y, (input & IN_DIR) as usize)
    }
    /// Luck for the server's item rolls: FORTUNE and GAMBLER'S COIN.
    pub fn luck(&self, id: u16) -> i32 {
        self.mods.get(id as usize).map_or(0, |m| m.luck)
    }
    pub fn zones(&self) -> &[Zone] {
        &self.zones
    }
    pub fn drops(&self) -> &[Drop] {
        &self.drops
    }
    pub fn shots(&self) -> &[Shot] {
        &self.shots
    }
    pub fn tide(&self) -> bool {
        self.tide
    }
    /// Tools and tests: a tide's flag alone (the schedule drives it in a running field).
    pub fn set_tide(&mut self, on: bool) {
        self.tide = on;
    }
    /// The monster grid, built this tick before monsters moved: widen queries by `GRID_MARGIN`.
    pub fn grid(&self) -> &Grid {
        &self.grid
    }
    /// The hero grid (64 px cells, heroes up and alive), built after heroes moved.
    pub fn player_grid(&self) -> &Grid {
        &self.hgrid
    }
    /// The last tick's events, in the contract's order.
    pub fn events(&self) -> &[Event] {
        &self.events
    }
    /// The heroes a `Kill` event credits.
    pub fn credited(&self, first: u32, count: u16) -> &[u16] {
        &self.credits[first as usize..first as usize + count as usize]
    }
    /// Monster ids born in the last step (births and splitters' children).
    pub fn last_spawns(&self) -> &[u32] {
        &self.spawned
    }
    /// (kills, births, heroes downed).
    pub fn counters(&self) -> (u64, u64, u64) {
        (self.kills_total, self.spawns_total, self.deaths_total)
    }
    pub fn recycled(&self) -> u64 {
        self.recycled_total
    }
    pub fn flow_dist(&self, c: usize) -> u16 {
        self.flow.dist[c]
    }
    /// Births on or off (state). Off, the field keeps only the monsters placed or already alive.
    pub fn set_births(&mut self, on: bool) {
        self.births = on;
    }
    /// Tools and tests: a monster of a kind at a point (no screen rule); its id, or None when full.
    pub fn place_monster(&mut self, kind: u8, level: u8, flags: u8, x: i32, y: i32) -> Option<u32> {
        let slot = self.free.pop()?;
        self.birth(slot as usize, kind % KINDS.len() as u8, level.max(1), flags, x.clamp(0, FIELD - 1), y.clamp(0, FIELD - 1));
        Some(slot)
    }
    /// Tools and tests: a hero's state.
    pub fn hero_mut(&mut self, id: u16) -> &mut Hero {
        &mut self.heroes[id as usize]
    }
    /// Tools and tests: the monster arrays.
    pub fn monsters_mut(&mut self) -> &mut Monsters {
        &mut self.m
    }
    /// Tools and tests: removes a monster.
    pub fn remove_monster(&mut self, i: u32) {
        if self.m.hp[i as usize] > 0 {
            self.m.hp[i as usize] = 0;
            self.free.push(i);
            self.alive -= 1;
        }
    }
    /// The outing state of a hero, to carry to another copy of this field.
    pub fn outing(&self, id: u16) -> Option<Outing> {
        self.heroes.get(id as usize).filter(|h| h.present).map(|h| h.outing(self.tick))
    }

    /// Adds a hero (her sheet and outing) at a position, moved off walls, and returns her id: the lowest
    /// free slot.
    pub fn join(&mut self, sheet: &Sheet, outing: &Outing, x: i32, y: i32) -> u16 {
        let id = match self.heroes.iter().position(|p| !p.present) {
            Some(i) => i,
            None => {
                self.heroes.push(Hero::default());
                self.heroes.len() - 1
            }
        };
        assert!(id < u16::MAX as usize, "too many heroes");
        let (x, y) = self.terrain.nearest_open(x, y);
        let mut h = Hero::enter_top(sheet, outing, self.top_level(), x, y);
        // A strike older than every section-14 window (the mark's ten minutes) is as good as none: a field younger
        // than her wait would otherwise read it as tick 0, a fresh strike.
        h.last_struck = if outing.struck_ago >= pvp::MARK_WAIT_TICKS { NEVER } else { self.tick.saturating_sub(outing.struck_ago) };
        self.heroes[id] = h;
        // Her opening draw (rules 5), once an outing: a hero moved between copies (section 11) brings her draws.
        // Joining is not a tick, so its GRANT and DRAW events are cleared by the next step; the offer is state.
        if outing.draws == 0 && outing.owed == 0 && outing.offers.is_empty() {
            self.grant_draw(id, GRANT_ENTER);
        }
        self.pvp_join(id as u16);
        id as u16
    }

    pub fn leave(&mut self, id: u16) {
        if let Some(p) = self.heroes.get_mut(id as usize) {
            *p = Hero::default();
        }
        self.forget_slot(id);
    }

    pub fn step<I: Copy + Into<u16>>(&mut self, inputs: &[I]) {
        self.step_with(inputs, |_| {});
    }

    /// One tick. `inputs[id]` is hero `id`'s two input bytes (byte 0 low; a `u8` is byte 0 alone);
    /// missing means none. `mark` is called after each phase.
    pub fn step_with<I: Copy + Into<u16>>(&mut self, inputs: &[I], mut mark: impl FnMut(Phase)) {
        self.tick += 1;
        self.events.clear();
        self.credits.clear();
        self.reward_list.clear();
        self.spawned.clear();
        let words: Vec<u16> = inputs.iter().map(|&i| i.into()).collect();
        self.build_hero_grid();
        self.realm_begin();
        self.pvp_begin();
        self.compute_mods();
        self.phase_heroes(&words);
        self.pvp_settle();
        mark(Phase::Input);
        self.phase_flow();
        mark(Phase::Flow);
        self.build_monster_grid();
        self.build_hero_grid();
        mark(Phase::Grid);
        self.phase_move();
        mark(Phase::Move);
        self.phase_fight();
        if self.pvp.yard {
            self.duel_end_check();
        }
        mark(Phase::Fight);
        if self.births {
            self.phase_spawn();
        }
        self.events.sort_by_key(|e| e.rank());
        mark(Phase::Spawn);
    }

    fn compute_mods(&mut self) {
        let this = &*self;
        let parts =
            par_ranges(self.heroes.len(), self.cfg.threads, combat::FIGHT_MIN_PER_THREAD, |a, b| (a..b).map(|i| mods::mods_of(this, i)).collect::<Vec<_>>());
        self.mods = parts.into_iter().flatten().collect();
    }

    pub(crate) fn build_hero_grid(&mut self) {
        self.hcells.clear();
        self.live.clear();
        self.threat.clear();
        for (i, p) in self.heroes.iter().enumerate() {
            let t = if p.has_fx(FX_PROVOKE) { PROVOKE_THREAT } else { p.threat() };
            self.threat.push(t);
            if p.alive() {
                self.hcells.push((i as u32, pcell_of(p.x, p.y) as u32));
                self.live.push(i as u16);
            }
        }
        self.hgrid.build(&self.hcells);
    }

    fn phase_flow(&mut self) {
        if self.flow.run(FLOW_SLICE, &self.terrain.map) {
            self.flow.finish();
            self.src_d0.clear();
            self.src_d0.resize(self.heroes.len(), 0);
            for &(_, h, d) in &self.flow.active_sources {
                if let Some(s) = self.src_d0.get_mut(h as usize) {
                    *s = d;
                }
            }
            let sources = self.flow_sources();
            self.flow.start(sources);
        }
    }

    /// Heroes monsters chase (up, not downed) with their head start by threat.
    pub(crate) fn flow_sources(&self) -> Vec<Source> {
        self.heroes
            .iter()
            .enumerate()
            .filter(|(_, p)| p.alive())
            .map(|(i, p)| {
                let d = if p.has_fx(FX_PROVOKE) { 0 } else { FLOW_LEAD + ((THREAT_TOP - p.threat()) * THREAT_HEAD_MUL).max(0) };
                (cell_of(p.x, p.y) as u32, i as u16, d as u16)
            })
            .collect()
    }
}
