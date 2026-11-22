//! Players against players (rules section 14, job R3): the BLOOD MARK, guild altar wars, duels in the town's
//! training yard and marked realms. `docs/realm/pvp.md` has every number and why.
//!
//! Who may strike whom is one relation, `Field::foes(a, b)`:
//! - two heroes who both carry the BLOOD MARK (`Hero::marked`; in a marked realm everyone past class level 20 has
//!   it for good);
//! - two members of the two guilds of a war that is on (declared for this field's tide, running while the tide
//!   runs): marked against each other only;
//! - the two heroes of a running duel (a yard field, `open_duel`): against each other only;
//! - and never when either stands on safe ground (300 px of a waystone or the gate; the yard has none).
//!
//! Hero strikes on heroes are gathered with the monster strikes (`attack.rs`), only for heroes who can strike
//! anyone (`flagged`), through the hero grid, and applied in hero order: 40% of the blow's damage to a monster,
//! then the target's own reductions. An unmarked hero cannot heal, shield, buff or raise a flagged hero who struck
//! a hero in the last 60 s. A hero downed by a hero's blow who FALLS loses her haul's share to the hero who downed
//! her (event `Plunder`).
//!
//! State: the per-hero mark and last-struck tick were in the hero bytes from the first day. The rest (the realm
//! flag, wars, the duel, guild tags and who downed whom) is one block appended to the state bytes only when any of
//! it is set, so a field without PvP has the same bytes and hash as before. A yard is the vault byte `YARD`.

use crate::events::Event;
use crate::hero::{Hero, rise_up};
use crate::tables::*;
use crate::util::{d2, grid_box};
use crate::{Config, FIELD, Field, PCELL_SHIFT, PCELLS_W, SUB, terrain};

/// The state block's bytes.
mod codec;

/// Input byte 1, bit 6: with interact held at a waystone, the hold is the mark's rite instead of banking.
pub const IN_MARK: u16 = 0x4000;
/// Class level (the hero's own, not the counted one) to take the mark.
pub const MARK_LEVEL: u8 = 20;
/// Holding interact (with `IN_MARK`) within `WAYSTONE_PX` of a waystone this long takes or puts down the mark.
pub const MARK_HOLD: u16 = secs(5) as u16;
/// A hero's blow on a hero: this share of what it does to a monster.
pub const PVP_DAMAGE_PCT: u64 = 40;
/// An unmarked hero cannot help a marked hero who struck a hero this recently.
pub const HELP_BAN_TICKS: u32 = secs(60);
/// While marked: coin from kills and luck.
pub const MARK_COIN_PCT: u32 = 25;
pub const MARK_LUCK: i32 = 15;
/// The mark cannot be put down until this long after the last strike on a hero.
pub const MARK_WAIT_TICKS: u32 = secs(600);
/// Safe ground: within this of a waystone or the gate.
pub const SAFE_PX: i32 = 300;
/// A marked realm marks every hero whose class level is above this, for good.
pub const REALM_MARK_ABOVE: u8 = 20;
/// A duel ends at a down or after this long.
pub const DUEL_TICKS: u32 = secs(180);
/// The training yard: an open square this wide, the duellists placed this far apart.
pub const YARD_PX: i32 = 640;
pub const YARD_START_PX: i32 = 200;
/// The level the yard counts from (no ceiling in town: the class cap).
pub const YARD_TOP: u8 = CLASS_LEVEL_MAX;
/// Monster pool of a yard (none are born; the pool only has to exist).
pub const YARD_MONSTERS: u32 = 16;
/// The vault byte of a yard in the state bytes.
pub const YARD: u8 = 254;
/// No hero.
pub const NOBODY: u16 = u16::MAX;

/// `Event::Mark` states.
pub const MARK_TAKEN: u8 = 1;
pub const MARK_PUT_DOWN: u8 = 2;
/// Refused: class level under 20.
pub const MARK_LOW_LEVEL: u8 = 3;
/// Refused: she struck a hero less than ten minutes ago.
pub const MARK_WAIT: u8 = 4;
/// Refused: a marked realm's mark is for good.
pub const MARK_FOR_GOOD: u8 = 5;
/// A marked realm marked her as she came in (or as the flag was set).
pub const MARK_REALM: u8 = 6;

/// `Event::War` states and winners.
pub const WAR_BEGIN: u8 = 1;
pub const WAR_END: u8 = 2;
pub const WAR_DRAW: u8 = 2;
/// `Event::Duel` states.
pub const DUEL_BEGIN: u8 = 1;
pub const DUEL_WON: u8 = 2;
pub const DUEL_DRAW: u8 = 3;
/// A duel's state.
pub const DUEL_READY: u8 = 0;
pub const DUEL_RUNNING: u8 = 1;
pub const DUEL_OVER: u8 = 2;

/// A guild war over one tide of this field: `guilds[0]` against `guilds[1]`, held altar ticks per side.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct War {
    /// The gateway's id for it (named in its events).
    pub id: u64,
    pub guilds: [u64; 2],
    /// The tide (its index on this field's clock) it is fought in.
    pub tide: u32,
    pub held: [u32; 2],
    /// The tide is running and the war with it.
    pub on: bool,
}

/// A duel of two heroes in a yard.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Duel {
    pub heroes: [u16; 2],
    pub started: u32,
    pub state: u8,
}

/// The PvP part of a field's state.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Pvp {
    /// Every hero past class level 20 carries the mark for good.
    pub marked_realm: bool,
    pub wars: Vec<War>,
    pub duel: Option<Duel>,
    /// A guild tag per hero slot (0: none): what a war reads.
    pub guild: Vec<u64>,
    /// Who downed each downed hero with a blow (`NOBODY`: a monster, or she is up).
    pub downer: Vec<u16>,
    /// A yard (not state: the vault byte says so).
    pub yard: bool,
}

impl Pvp {
    /// Nothing to save: the field's bytes stay those of a field without PvP.
    pub fn is_empty(&self) -> bool {
        !self.marked_realm && self.wars.is_empty() && self.duel.is_none() && self.guild.iter().all(|&g| g == 0) && self.downer.iter().all(|&d| d == NOBODY)
    }
    fn guild_of(&self, i: usize) -> u64 {
        self.guild.get(i).copied().unwrap_or(0)
    }
    pub(crate) fn downer_of(&self, i: usize) -> u16 {
        self.downer.get(i).copied().unwrap_or(NOBODY)
    }
    fn set_downer(&mut self, i: usize, by: u16) {
        if self.downer.len() <= i {
            self.downer.resize(i + 1, NOBODY);
        }
        self.downer[i] = by;
    }
    /// The war side (war index, 0 or 1) of a guild in a war that is on.
    fn side(&self, guild: u64) -> impl Iterator<Item = (usize, usize)> + '_ {
        self.wars
            .iter()
            .enumerate()
            .filter(move |(_, w)| w.on && guild != 0)
            .filter_map(move |(k, w)| w.guilds.iter().position(|&g| g == guild).map(|s| (k, s)))
    }
    fn duellist(&self, i: usize) -> bool {
        self.duel.is_some_and(|d| d.state == DUEL_RUNNING && d.heroes.contains(&(i as u16)))
    }
}

/// A hero's blow on a hero, gathered with the monster hits: raw damage before the target's reductions.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PHit {
    pub to: u16,
    pub by: u16,
    pub dmg: u32,
}

impl Field {
    // ---- the public calls (the server's, the tools' and the tests')

    /// Turns the marked realm flag on (marks every present hero past level 20 for good) or off.
    pub fn set_marked_realm(&mut self, on: bool) {
        self.pvp.marked_realm = on;
        if on {
            for i in 0..self.heroes.len() {
                let h = &mut self.heroes[i];
                if h.present && !h.marked && h.sheet.class_level > REALM_MARK_ABOVE {
                    h.marked = true;
                    self.events.push(Event::Mark { hero: i as u16, state: MARK_REALM });
                }
            }
        }
    }
    pub fn marked_realm(&self) -> bool {
        self.pvp.marked_realm
    }
    /// Tags a hero with her guild (0: none), which is what a war reads. The server calls it as she joins.
    pub fn set_guild(&mut self, id: u16, guild: u64) {
        let i = id as usize;
        if self.pvp.guild.len() <= i {
            self.pvp.guild.resize(i + 1, 0);
        }
        self.pvp.guild[i] = guild;
    }
    pub fn guild(&self, id: u16) -> u64 {
        self.pvp.guild_of(id as usize)
    }
    /// Declares war `id` between two guilds for this field's tide `tide`. It starts with that tide (or now, if that
    /// tide is running) and ends with it. False if the guilds are the same, either is 0, or either is already at war
    /// in that tide.
    pub fn declare_war(&mut self, id: u64, a: u64, b: u64, tide: u32) -> bool {
        if a == 0 || b == 0 || a == b || self.pvp.wars.iter().any(|w| w.tide == tide && (w.guilds.contains(&a) || w.guilds.contains(&b))) {
            return false;
        }
        let on = self.tide && self.realm.tide_index == tide;
        self.pvp.wars.push(War { id, guilds: [a, b], tide, held: [0, 0], on });
        if on {
            self.events.push(Event::War { war: id, state: WAR_BEGIN, winner: WAR_DRAW, held: [0, 0] });
        }
        true
    }
    /// Calls off a war that has not begun (or is running: it ends as a draw with no result for either).
    pub fn cancel_war(&mut self, id: u64) -> bool {
        let n = self.pvp.wars.len();
        self.pvp.wars.retain(|w| w.id != id);
        n != self.pvp.wars.len()
    }
    pub fn wars(&self) -> &[War] {
        &self.pvp.wars
    }

    /// The town's training yard for one duel: an open square, no monsters, no tides, no safe ground.
    pub fn open_duel(seed: u64, cfg: Config) -> Field {
        let cfg = Config { monsters: cfg.monsters.min(YARD_MONSTERS), threads: cfg.threads };
        let mut f = Field::open_with(0, seed, cfg, terrain::build_yard(seed));
        f.births = false;
        f.pvp.yard = true;
        f
    }
    pub fn is_yard(&self) -> bool {
        self.pvp.yard
    }
    /// Where the two duellists stand at the start.
    pub fn yard_spots(&self) -> [(i32, i32); 2] {
        let (cx, cy) = (FIELD / 2, FIELD / 2);
        [(cx - YARD_START_PX / 2 * SUB, cy), (cx + YARD_START_PX / 2 * SUB, cy)]
    }
    /// Starts the duel of two heroes in this yard (the next tick sends `DUEL_BEGIN`). False if not a yard, a duel
    /// was already started, or the two are not two present heroes.
    pub fn start_duel(&mut self, a: u16, b: u16) -> bool {
        let ok = |i: u16| self.heroes.get(i as usize).is_some_and(|h| h.present);
        if !self.pvp.yard || self.pvp.duel.is_some() || a == b || !ok(a) || !ok(b) {
            return false;
        }
        self.pvp.duel = Some(Duel { heroes: [a, b], started: self.tick, state: DUEL_READY });
        true
    }
    pub fn duel(&self) -> Option<&Duel> {
        self.pvp.duel.as_ref()
    }
    /// Who downed a downed hero with a blow (`NOBODY` if a monster did, or she is up).
    pub fn downed_by(&self, id: u16) -> u16 {
        self.pvp.downer_of(id as usize)
    }

    // ---- the relation

    /// True when she can strike or be struck by somebody at all: the mark, a war that is on for her guild, a duel.
    pub fn flagged(&self, i: usize) -> bool {
        let Some(h) = self.heroes.get(i) else { return false };
        h.present && ((h.marked && !self.pvp.yard) || self.pvp.duellist(i) || self.pvp.side(self.pvp.guild_of(i)).next().is_some())
    }

    /// Safe ground: within 300 px of a waystone or the gate. A yard has none; a vault is safe everywhere (a party's
    /// run against the timeline, not a place to fight each other).
    pub fn safe_ground(&self, x: i32, y: i32) -> bool {
        if self.realm.vault.is_some() {
            return true;
        }
        if self.pvp.yard {
            return false;
        }
        let r = (SAFE_PX * SUB) as i64;
        let t = &self.terrain;
        d2(x, y, t.gate.0, t.gate.1) <= r * r || t.waystones.iter().any(|&(wx, wy)| d2(x, y, wx, wy) <= r * r)
    }

    /// Whether `a` and `b` are marked against each other (the relation only: where they stand and whether they are
    /// up is `foes`).
    pub fn hostile(&self, a: usize, b: usize) -> bool {
        if a == b {
            return false;
        }
        let (Some(ha), Some(hb)) = (self.heroes.get(a), self.heroes.get(b)) else { return false };
        if !ha.present || !hb.present {
            return false;
        }
        if self.pvp.yard {
            return self.pvp.duel.is_some_and(|d| d.state == DUEL_RUNNING && (d.heroes == [a as u16, b as u16] || d.heroes == [b as u16, a as u16]));
        }
        if ha.marked && hb.marked {
            return true;
        }
        let (ga, gb) = (self.pvp.guild_of(a), self.pvp.guild_of(b));
        ga != 0 && gb != 0 && ga != gb && self.pvp.side(ga).any(|(k, s)| self.pvp.wars[k].guilds[1 - s] == gb)
    }

    /// `a` may strike `b` now: hostile, `b` up, and neither on safe ground.
    pub fn foes(&self, a: usize, b: usize) -> bool {
        self.hostile(a, b) && self.heroes[b].alive() && !self.safe_ground(self.heroes[b].x, self.heroes[b].y) && !self.safe_ground(self.heroes[a].x, self.heroes[a].y)
    }

    /// `helper` may heal, shield, buff or raise `target`: always, unless the target is flagged and struck a hero in
    /// the last 60 s and the helper is not flagged herself.
    pub fn may_help(&self, helper: usize, target: usize) -> bool {
        if helper == target {
            return true;
        }
        let t = &self.heroes[target];
        let hot = t.last_struck != NEVER && self.tick.saturating_sub(t.last_struck) < HELP_BAN_TICKS && self.flagged(target);
        !hot || self.flagged(helper)
    }

    /// Living foes of hero `a` within `r` (sub units) of a point, by id.
    pub(crate) fn foes_in_circle(&self, a: usize, x: i32, y: i32, r: i32) -> Vec<u16> {
        let mut v = Vec::new();
        let rr = r as i64 * r as i64;
        grid_box(&self.hgrid, PCELLS_W, PCELL_SHIFT, x - r, y - r, x + r, y + r, |q| {
            let h = &self.heroes[q as usize];
            if d2(h.x, h.y, x, y) <= rr && self.foes(a, q as usize) {
                v.push(q as u16);
            }
        });
        v.sort_unstable();
        v
    }

    /// The nearest living foe of `a` within `r` of her, and its squared distance.
    pub(crate) fn nearest_foe(&self, a: usize, r: i32) -> Option<(u16, i64)> {
        let (x, y) = (self.heroes[a].x, self.heroes[a].y);
        let mut best: Option<(u16, i64)> = None;
        for q in self.foes_in_circle(a, x, y, r) {
            let d = d2(self.heroes[q as usize].x, self.heroes[q as usize].y, x, y);
            if best.is_none_or(|(_, bd)| d < bd) {
                best = Some((q, d));
            }
        }
        best
    }

    /// Living foes of `a` within `hw` of the segment from (ax, ay) to (bx, by), nearest the start first.
    pub(crate) fn foes_on_line(&self, a: usize, ax: i32, ay: i32, bx: i32, by: i32, hw: i32) -> Vec<u16> {
        let (lx, ly) = ((bx - ax) as i64, (by - ay) as i64);
        let ll = lx * lx + ly * ly;
        let (x0, x1) = (ax.min(bx) - hw, ax.max(bx) + hw);
        let (y0, y1) = (ay.min(by) - hw, ay.max(by) + hw);
        let mut v: Vec<(i64, u16)> = Vec::new();
        grid_box(&self.hgrid, PCELLS_W, PCELL_SHIFT, x0, y0, x1, y1, |q| {
            let h = &self.heroes[q as usize];
            let (px, py) = ((h.x - ax) as i64, (h.y - ay) as i64);
            let t = if ll == 0 { 0 } else { ((px * lx + py * ly) as i128 * 1024 / ll as i128).clamp(0, 1024) as i64 };
            let (cx, cy) = (lx * t / 1024, ly * t / 1024);
            let (dx, dy) = (px - cx, py - cy);
            if dx * dx + dy * dy <= hw as i64 * hw as i64 && self.foes(a, q as usize) {
                v.push((t, q as u16));
            }
        });
        v.sort_unstable();
        v.into_iter().map(|(_, q)| q).collect()
    }

    // ---- inside the tick

    /// Start of a tick: slots of heroes who left lose their tags; a hero who is up was downed by nobody; a duel
    /// that was started begins.
    pub(crate) fn pvp_begin(&mut self) {
        let n = self.heroes.len();
        if self.pvp.guild.len() > n {
            self.pvp.guild.truncate(n);
        }
        if self.pvp.downer.len() > n {
            self.pvp.downer.truncate(n);
        }
        for i in 0..n {
            let h = &self.heroes[i];
            if !h.present {
                if let Some(g) = self.pvp.guild.get_mut(i) {
                    *g = 0;
                }
            }
            if !(h.present && h.downed > 0) {
                if let Some(d) = self.pvp.downer.get_mut(i) {
                    *d = NOBODY;
                }
            }
        }
        if let Some(d) = self.pvp.duel.as_mut() {
            if d.state == DUEL_READY {
                d.state = DUEL_RUNNING;
                d.started = self.tick;
                self.events.push(Event::Duel { state: DUEL_BEGIN, winner: d.heroes[0], loser: d.heroes[1] });
            }
        }
    }

    /// A hero joins: a marked realm marks her if she is past level 20; her slot has no tag yet.
    pub(crate) fn pvp_join(&mut self, id: u16) {
        let i = id as usize;
        if let Some(g) = self.pvp.guild.get_mut(i) {
            *g = 0;
        }
        if let Some(d) = self.pvp.downer.get_mut(i) {
            *d = NOBODY;
        }
        let h = &mut self.heroes[i];
        if self.pvp.marked_realm && !h.marked && h.sheet.class_level > REALM_MARK_ABOVE {
            h.marked = true;
            self.events.push(Event::Mark { hero: id, state: MARK_REALM });
        }
    }

    /// The mark's rite at a waystone is done: take the mark, or put it down, or say why not.
    pub(crate) fn mark_rite(&mut self, i: usize) {
        let tick = self.tick;
        let realm = self.pvp.marked_realm;
        let h = &mut self.heroes[i];
        let state = if h.marked {
            if realm && h.sheet.class_level > REALM_MARK_ABOVE {
                MARK_FOR_GOOD
            } else if h.last_struck != NEVER && tick.saturating_sub(h.last_struck) < MARK_WAIT_TICKS {
                MARK_WAIT
            } else {
                h.marked = false;
                MARK_PUT_DOWN
            }
        } else if h.sheet.class_level < MARK_LEVEL {
            MARK_LOW_LEVEL
        } else {
            h.marked = true;
            MARK_TAKEN
        };
        self.events.push(Event::Mark { hero: i as u16, state });
    }

    /// The tick's hero-on-hero blows, in the order gathered (hero order): checked again (an earlier blow may have
    /// downed the target), then dealt as damage through the target's reductions.
    pub(crate) fn apply_phits(&mut self, phits: Vec<PHit>, killed: &mut Vec<(u32, u16)>) {
        let tick = self.tick;
        for p in phits {
            let (to, by) = (p.to as usize, p.by as usize);
            if !self.hostile(by, to) || !self.heroes[to].alive() || self.safe_ground(self.heroes[to].x, self.heroes[to].y) {
                continue;
            }
            let a = &mut self.heroes[by];
            a.last_struck = tick;
            a.active = tick;
            let taken = self.hurt_hero(to, p.dmg, killed);
            self.events.push(Event::Struck { hero: p.to, by: p.by, raw: p.dmg, amount: taken });
            if self.heroes[to].downed > 0 {
                self.pvp.set_downer(to, p.by);
                self.events.push(Event::Slain { hero: p.to, by: p.by });
            }
        }
    }

    /// She FELL after a hero downed her: what her haul lost goes to that hero (if still in the field).
    pub(crate) fn plunder(&mut self, i: usize, lost: u32) {
        let by = self.pvp.downer_of(i);
        if by == NOBODY {
            return;
        }
        self.pvp.set_downer(i, NOBODY);
        let got = match self.heroes.get_mut(by as usize) {
            Some(h) if h.present => {
                h.coin = h.coin.saturating_add(lost);
                lost
            }
            _ => 0,
        };
        self.events.push(Event::Plunder { hero: i as u16, by, coin: got });
    }

    /// A tide begins: its wars go on.
    pub(crate) fn wars_begin(&mut self, n: u32) {
        self.pvp.wars.retain(|w| w.tide >= n);
        for w in self.pvp.wars.iter_mut().filter(|w| w.tide == n) {
            w.on = true;
            w.held = [0, 0];
            self.events.push(Event::War { war: w.id, state: WAR_BEGIN, winner: WAR_DRAW, held: [0, 0] });
        }
    }

    /// The tide ends: its wars end with a winner (more held altar time) or a draw.
    pub(crate) fn wars_end(&mut self) {
        let mut k = 0;
        while k < self.pvp.wars.len() {
            let w = self.pvp.wars[k];
            if w.on {
                let winner = match w.held[0].cmp(&w.held[1]) {
                    std::cmp::Ordering::Greater => 0,
                    std::cmp::Ordering::Less => 1,
                    std::cmp::Ordering::Equal => WAR_DRAW,
                };
                self.events.push(Event::War { war: w.id, state: WAR_END, winner, held: w.held });
                self.pvp.wars.remove(k);
            } else {
                k += 1;
            }
        }
    }

    /// Held altar time of a tide: every tick, a lit or held altar with members of one side of a war within its
    /// circle and none of the other counts a tick for that side.
    pub(crate) fn wars_altars(&mut self) {
        if !self.pvp.wars.iter().any(|w| w.on) {
            return;
        }
        let r = ALTAR_HOLD_PX * SUB;
        for a in 0..6 {
            let st = self.realm.altars[a].state;
            if st != ALTAR_LIT && st != ALTAR_HELD {
                continue;
            }
            let (ax, ay) = self.terrain.altars[a];
            let mut near: Vec<u64> = Vec::new();
            grid_box(&self.hgrid, PCELLS_W, PCELL_SHIFT, ax - r, ay - r, ax + r, ay + r, |q| {
                let h = &self.heroes[q as usize];
                let g = self.pvp.guild_of(q as usize);
                if g != 0 && h.alive() && d2(h.x, h.y, ax, ay) <= r as i64 * r as i64 {
                    near.push(g);
                }
            });
            for w in self.pvp.wars.iter_mut().filter(|w| w.on) {
                let there = [near.contains(&w.guilds[0]), near.contains(&w.guilds[1])];
                if there[0] != there[1] {
                    let s = if there[0] { 0 } else { 1 };
                    w.held[s] = w.held[s].saturating_add(1);
                }
            }
        }
    }

    /// End of a tick in a yard: the duel ends at a down (or both: a draw) or at three minutes (more health in
    /// thousandths wins; equal is a draw). Both stand up whole: a duel costs no haul and nobody falls.
    pub(crate) fn duel_end_check(&mut self) {
        let Some(d) = self.pvp.duel else { return };
        if d.state != DUEL_RUNNING {
            return;
        }
        let [a, b] = d.heroes;
        let (ha, hb) = (&self.heroes[a as usize], &self.heroes[b as usize]);
        let (da, db) = (!ha.present || ha.downed > 0, !hb.present || hb.downed > 0);
        let frac = |h: &Hero| if h.present { h.health as u64 * 1000 / h.max_health.max(1) as u64 } else { 0 };
        let result = if da || db {
            Some(match (da, db) {
                (true, true) => (DUEL_DRAW, a, b),
                (true, false) => (DUEL_WON, b, a),
                _ => (DUEL_WON, a, b),
            })
        } else if self.tick.saturating_sub(d.started) >= DUEL_TICKS {
            let (fa, fb) = (frac(ha), frac(hb));
            Some(if fa > fb {
                (DUEL_WON, a, b)
            } else if fb > fa {
                (DUEL_WON, b, a)
            } else {
                (DUEL_DRAW, a, b)
            })
        } else {
            None
        };
        if let Some((state, winner, loser)) = result {
            self.pvp.duel = Some(Duel { state: DUEL_OVER, ..d });
            for q in [a, b] {
                self.pvp.set_downer(q as usize, NOBODY);
                let h = &mut self.heroes[q as usize];
                if h.present {
                    rise_up(h, 100);
                }
            }
            self.events.push(Event::Duel { state, winner, loser });
        }
    }
}
