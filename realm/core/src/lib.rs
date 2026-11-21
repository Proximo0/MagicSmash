//! The crowd test's simulation: one field, players and a horde, whole numbers only.
//!
//! Positions are `i32` in 1/256 px, time is ticks (20 a second). The same seed, joins and inputs give the
//! same state on every machine and for every thread count; `Field::hash` is the proof. The core takes no
//! clock and does no I/O: `step_with` calls a marker after each phase so the caller can time them.

use std::thread;

mod state;
mod tables;

pub use tables::{Class, Kind, CLASSES, KINDS};

/// Sub-pixel units per pixel.
pub const SUB: i32 = 256;
/// Field side in px.
pub const FIELD_PX: i32 = 16_384;
/// Field side in sub-pixel units.
pub const FIELD: i32 = FIELD_PX * SUB;
pub const TICK_HZ: u32 = 20;
/// Flow and monster-grid cells are 32 px: a position in sub units shifted by 13.
pub const CELL_SHIFT: u32 = 13;
pub const CELLS_W: usize = 512;
pub const CELLS: usize = CELLS_W * CELLS_W;
/// Player-grid cells are 256 px.
pub const PCELL_SHIFT: u32 = 16;
pub const PCELLS_W: usize = 64;
pub const PCELLS: usize = PCELLS_W * PCELLS_W;
/// The view every spawn stays out of, in px.
pub const VIEW_W: i32 = 480;
pub const VIEW_H: i32 = 270;
pub const SPAWN_MIN_PX: i32 = 400;
pub const SPAWN_MAX_PX: i32 = 700;
pub const SPAWN_TRIES: u32 = 16;
/// Spawning gives up for the tick after this many monsters found no place.
pub const SPAWN_FAILS_PER_TICK: u32 = 1024;
pub const RESPAWN_TICKS: u8 = 60;
/// Player speed 60 px/s is 3 px a tick; the diagonal is 3 px times 181/256.
pub const PLAYER_STEP: i32 = 3 * SUB;
pub const PLAYER_DIAG: i32 = PLAYER_STEP * 181 / 256;
/// Monsters at most this many to a 32 px cell before they are pushed to a less crowded neighbour.
pub const CROWD_CAP: u32 = 6;
/// Cells popped by the flow field's breadth-first search per tick (a full refresh in 8 ticks).
pub const FLOW_SLICE: usize = 32_768;
pub const UNREACHED: u16 = u16::MAX;
/// A monster this close (px) to a player hurts it; one this close to its target stops.
pub const CONTACT_PX: i32 = 20;
pub const STOP_PX: i32 = 14;
/// Contact damage lands every 10 ticks per player.
pub const CONTACT_EVERY: u32 = 10;
pub const XP_SHARE_PX: i32 = 200;
/// A monster this many flow cells (32 px) from the nearest player is recycled (2 048 px).
pub const RECYCLE_CELLS: u16 = 64;
pub const STAGGER_TICKS: u8 = 2;
pub const SKILL_COOLDOWN: u8 = 100;
pub const ELITE_ONE_IN: u64 = 50;
pub const ELITE_HEALTH_MUL: u16 = 4;
pub const ELITE_XP_MUL: u32 = 3;
/// Monster queries widen by this much (sub units) because the grid is built before monsters move.
pub const GRID_MARGIN: i32 = 8 * SUB;

/// Input byte: direction 0..8 in the low bits, bit 7 the skill.
pub const INPUT_SKILL: u8 = 0x80;

#[derive(Clone, Debug)]
pub struct Config {
    /// The monster count spawning keeps.
    pub monsters: u32,
    /// Worker threads for the heavy phases; never changes the result.
    pub threads: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Phase {
    Input,
    Flow,
    Grid,
    Move,
    Fight,
    Spawn,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Player {
    pub present: bool,
    pub x: i32,
    pub y: i32,
    pub class: u8,
    pub race: u8,
    pub health: u16,
    pub max_health: u16,
    pub level: u16,
    pub xp: u32,
    pub cooldown: u8,
    pub skill_cd: u8,
    pub input: u8,
    pub facing_left: bool,
    pub moving: bool,
    /// Hurt this tick: output only, not state (not hashed, not saved).
    pub hurt: bool,
    pub dead_timer: u8,
}

impl Player {
    pub fn alive(&self) -> bool {
        self.present && self.health > 0
    }
}

/// Monsters as flat arrays indexed by id (slot). A slot with `hp == 0` is empty.
#[derive(Clone, Debug, Default)]
pub struct Monsters {
    pub x: Vec<i32>,
    pub y: Vec<i32>,
    pub hp: Vec<u16>,
    /// Kind in bits 0..2, elite in bit 3.
    pub kind: Vec<u8>,
    pub stagger: Vec<u8>,
    /// Hurt this tick: output only.
    pub hurt: Vec<u8>,
}

impl Monsters {
    pub fn max_hp(&self, i: usize) -> u16 {
        let k = self.kind[i];
        let base = KINDS[(k & 7) as usize].health;
        if k & 8 != 0 { base * ELITE_HEALTH_MUL } else { base }
    }
}

/// The flow field: breadth-first distance (in cells) from every live player's cell, and which player.
/// It is rebuilt in slices into `b*` while monsters read the finished one.
struct Flow {
    dist: Vec<u16>,
    src: Vec<u16>,
    bdist: Vec<u16>,
    bsrc: Vec<u16>,
    queue: Vec<u32>,
    head: usize,
    active_sources: Vec<(u32, u16)>,
    build_sources: Vec<(u32, u16)>,
}

impl Flow {
    fn new() -> Flow {
        Flow {
            dist: vec![UNREACHED; CELLS],
            src: vec![0; CELLS],
            bdist: vec![UNREACHED; CELLS],
            bsrc: vec![0; CELLS],
            queue: Vec::with_capacity(CELLS),
            head: 0,
            active_sources: Vec::new(),
            build_sources: Vec::new(),
        }
    }

    fn start(&mut self, sources: Vec<(u32, u16)>) {
        self.bdist.fill(UNREACHED);
        self.queue.clear();
        self.head = 0;
        for &(c, p) in &sources {
            let c = c as usize;
            if self.bdist[c] == UNREACHED {
                self.bdist[c] = 0;
                self.bsrc[c] = p;
                self.queue.push(c as u32);
            }
        }
        self.build_sources = sources;
    }

    /// Pops at most `budget` cells; true when the search is done.
    fn run(&mut self, budget: usize) -> bool {
        let mut n = 0;
        while self.head < self.queue.len() && n < budget {
            let c = self.queue[self.head] as usize;
            self.head += 1;
            n += 1;
            let d = self.bdist[c] + 1;
            let s = self.bsrc[c];
            let cx = (c % CELLS_W) as i32;
            let cy = (c / CELLS_W) as i32;
            for (ox, oy) in NEIGHBOURS {
                let nx = cx + ox;
                let ny = cy + oy;
                if nx < 0 || ny < 0 || nx >= CELLS_W as i32 || ny >= CELLS_W as i32 {
                    continue;
                }
                let nc = ny as usize * CELLS_W + nx as usize;
                if self.bdist[nc] == UNREACHED {
                    self.bdist[nc] = d;
                    self.bsrc[nc] = s;
                    self.queue.push(nc as u32);
                }
            }
        }
        self.head == self.queue.len()
    }

    fn finish(&mut self) {
        std::mem::swap(&mut self.dist, &mut self.bdist);
        std::mem::swap(&mut self.src, &mut self.bsrc);
        self.active_sources = std::mem::take(&mut self.build_sources);
    }
}

/// The eight neighbours, E first and clockwise (y grows down).
pub const NEIGHBOURS: [(i32, i32); 8] = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)];

/// Input directions 1..8 as steps in sub units.
pub const DIRS: [(i32, i32); 9] = [
    (0, 0),
    (PLAYER_STEP, 0),
    (PLAYER_DIAG, PLAYER_DIAG),
    (0, PLAYER_STEP),
    (-PLAYER_DIAG, PLAYER_DIAG),
    (-PLAYER_STEP, 0),
    (-PLAYER_DIAG, -PLAYER_DIAG),
    (0, -PLAYER_STEP),
    (PLAYER_DIAG, -PLAYER_DIAG),
];

/// A counting-sort grid: `items[start[c]..start[c + 1]]` are the ids in cell `c`, in id order.
#[derive(Clone, Debug, Default)]
pub struct Grid {
    pub start: Vec<u32>,
    pub items: Vec<u32>,
}

impl Grid {
    fn new(cells: usize) -> Grid {
        Grid { start: vec![0; cells + 1], items: Vec::new() }
    }

    pub fn cell(&self, c: usize) -> &[u32] {
        &self.items[self.start[c] as usize..self.start[c + 1] as usize]
    }

    pub fn count(&self, c: usize) -> u32 {
        self.start[c + 1] - self.start[c]
    }

    /// Rebuilds from `(id, cell)` pairs given in id order.
    fn build(&mut self, cells_of: &[(u32, u32)]) {
        let cells = self.start.len() - 1;
        self.start.fill(0);
        for &(_, c) in cells_of {
            self.start[c as usize] += 1;
        }
        let mut sum = 0u32;
        for c in 0..cells {
            let t = self.start[c];
            self.start[c] = sum;
            sum += t;
        }
        self.start[cells] = sum;
        self.items.resize(sum as usize, 0);
        for &(id, c) in cells_of {
            let s = &mut self.start[c as usize];
            self.items[*s as usize] = id;
            *s += 1;
        }
        for c in (1..=cells).rev() {
            self.start[c] = self.start[c - 1];
        }
        self.start[0] = 0;
    }
}

pub struct Field {
    cfg: Config,
    tick: u32,
    rng: u64,
    m: Monsters,
    free: Vec<u32>,
    alive: u32,
    players: Vec<Player>,
    flow: Flow,
    grid: Grid,
    pgrid: Grid,
    // scratch, rebuilt every tick
    mcells: Vec<(u32, u32)>,
    pcells: Vec<(u32, u32)>,
    live: Vec<u16>,
    hits: Vec<(u32, u16)>,
    spawned: Vec<u32>,
    killed: Vec<u32>,
    // counters (state)
    kills_total: u64,
    spawns_total: u64,
    deaths_total: u64,
    recycled_total: u64,
}

/// splitmix64.
pub fn rng_next(s: &mut u64) -> u64 {
    *s = s.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let mut z = *s;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

#[inline]
pub fn cell_of(x: i32, y: i32) -> usize {
    ((y >> CELL_SHIFT) as usize) * CELLS_W + (x >> CELL_SHIFT) as usize
}

#[inline]
pub fn pcell_of(x: i32, y: i32) -> usize {
    ((y >> PCELL_SHIFT) as usize) * PCELLS_W + (x >> PCELL_SHIFT) as usize
}

#[inline]
fn clamp_pos(v: i32) -> i32 {
    v.clamp(0, FIELD - 1)
}

/// Calls `f` for every id in the cells of `g` (side `w`, cell shift `shift`) overlapping the box.
#[inline]
pub fn grid_box(g: &Grid, w: usize, shift: u32, x0: i32, y0: i32, x1: i32, y1: i32, mut f: impl FnMut(u32)) {
    let lim = w as i32 - 1;
    let cx0 = (x0 >> shift).clamp(0, lim);
    let cy0 = (y0 >> shift).clamp(0, lim);
    let cx1 = (x1 >> shift).clamp(0, lim);
    let cy1 = (y1 >> shift).clamp(0, lim);
    for cy in cy0..=cy1 {
        let row = cy as usize * w;
        for cx in cx0..=cx1 {
            for &id in g.cell(row + cx as usize) {
                f(id);
            }
        }
    }
}

#[inline]
fn d2(ax: i32, ay: i32, bx: i32, by: i32) -> i64 {
    let dx = (ax - bx) as i64;
    let dy = (ay - by) as i64;
    dx * dx + dy * dy
}

/// Splits `0..n` into `t` contiguous ranges.
fn chunk_len(n: usize, t: usize) -> usize {
    n.div_ceil(t.max(1)).max(1)
}

impl Field {
    pub fn new(seed: u64, cfg: Config) -> Field {
        let cap = cfg.monsters as usize;
        let m = Monsters {
            x: vec![0; cap],
            y: vec![0; cap],
            hp: vec![0; cap],
            kind: vec![0; cap],
            stagger: vec![0; cap],
            hurt: vec![0; cap],
        };
        Field {
            cfg,
            tick: 0,
            rng: seed,
            m,
            free: (0..cap as u32).rev().collect(),
            alive: 0,
            players: Vec::new(),
            flow: Flow::new(),
            grid: Grid::new(CELLS),
            pgrid: Grid::new(PCELLS),
            mcells: Vec::new(),
            pcells: Vec::new(),
            live: Vec::new(),
            hits: Vec::new(),
            spawned: Vec::new(),
            killed: Vec::new(),
            kills_total: 0,
            spawns_total: 0,
            deaths_total: 0,
            recycled_total: 0,
        }
    }

    pub fn set_threads(&mut self, threads: usize) {
        self.cfg.threads = threads.max(1);
    }
    pub fn config(&self) -> &Config {
        &self.cfg
    }
    pub fn tick(&self) -> u32 {
        self.tick
    }
    pub fn monsters(&self) -> &Monsters {
        &self.m
    }
    pub fn monster_count(&self) -> u32 {
        self.alive
    }
    pub fn players(&self) -> &[Player] {
        &self.players
    }
    pub fn player_count(&self) -> u32 {
        self.players.iter().filter(|p| p.present).count() as u32
    }
    /// The monster grid, built this tick before monsters moved: widen queries by `GRID_MARGIN`.
    pub fn grid(&self) -> &Grid {
        &self.grid
    }
    /// The player grid (256 px cells, live players), built this tick after players moved.
    pub fn player_grid(&self) -> &Grid {
        &self.pgrid
    }
    /// Monster ids spawned in the last step.
    pub fn last_spawns(&self) -> &[u32] {
        &self.spawned
    }
    /// Monster ids killed in the last step.
    pub fn last_kills(&self) -> &[u32] {
        &self.killed
    }
    /// (kills, spawns, player deaths).
    pub fn counters(&self) -> (u64, u64, u64) {
        (self.kills_total, self.spawns_total, self.deaths_total)
    }
    /// Monsters freed because every player had left them far behind.
    pub fn recycled(&self) -> u64 {
        self.recycled_total
    }
    /// Flow distance (cells) at a cell, for bots and tests.
    pub fn flow_dist(&self, c: usize) -> u16 {
        self.flow.dist[c]
    }

    /// Adds a player at a position (sub units) and returns its id: the lowest free slot.
    pub fn join(&mut self, class: u8, race: u8, x: i32, y: i32) -> u16 {
        let id = match self.players.iter().position(|p| !p.present) {
            Some(i) => i,
            None => {
                self.players.push(Player::default());
                self.players.len() - 1
            }
        };
        assert!(id < u16::MAX as usize, "too many players");
        let mh = max_health(1);
        self.players[id] = Player {
            present: true,
            x: clamp_pos(x),
            y: clamp_pos(y),
            class: class % CLASSES.len() as u8,
            race: race % 4,
            health: mh,
            max_health: mh,
            level: 1,
            ..Player::default()
        };
        id as u16
    }

    pub fn leave(&mut self, id: u16) {
        if let Some(p) = self.players.get_mut(id as usize) {
            *p = Player::default();
        }
    }

    pub fn step(&mut self, inputs: &[u8]) {
        self.step_with(inputs, |_| {});
    }

    /// One tick. `inputs[id]` is player `id`'s input byte (missing means none). `mark` is called after
    /// each phase.
    pub fn step_with(&mut self, inputs: &[u8], mut mark: impl FnMut(Phase)) {
        self.tick += 1;
        self.phase_input(inputs);
        mark(Phase::Input);
        self.phase_flow();
        mark(Phase::Flow);
        self.phase_grid();
        mark(Phase::Grid);
        self.phase_move();
        mark(Phase::Move);
        self.phase_fight();
        mark(Phase::Fight);
        self.phase_spawn();
        mark(Phase::Spawn);
    }

    fn phase_input(&mut self, inputs: &[u8]) {
        let centre = FIELD / 2;
        for (i, p) in self.players.iter_mut().enumerate() {
            if !p.present {
                continue;
            }
            if p.dead_timer > 0 {
                p.dead_timer -= 1;
                if p.dead_timer == 0 {
                    p.x = centre;
                    p.y = centre;
                    p.health = p.max_health;
                }
                p.moving = false;
                continue;
            }
            let inp = inputs.get(i).copied().unwrap_or(0);
            p.input = inp;
            let dir = (inp & 0x0F).min(8) as usize;
            let (sx, sy) = DIRS[dir];
            p.moving = dir != 0;
            if sx < 0 {
                p.facing_left = true;
            } else if sx > 0 {
                p.facing_left = false;
            }
            p.x = clamp_pos(p.x + sx);
            p.y = clamp_pos(p.y + sy);
        }
    }

    fn phase_flow(&mut self) {
        if self.flow.run(FLOW_SLICE) {
            self.flow.finish();
            let sources = self.player_sources();
            self.flow.start(sources);
        }
    }

    fn player_sources(&self) -> Vec<(u32, u16)> {
        self.players
            .iter()
            .enumerate()
            .filter(|(_, p)| p.alive())
            .map(|(i, p)| (cell_of(p.x, p.y) as u32, i as u16))
            .collect()
    }

    fn phase_grid(&mut self) {
        self.mcells.clear();
        let m = &mut self.m;
        for i in 0..m.hp.len() {
            if m.hp[i] > 0 {
                let c = cell_of(m.x[i], m.y[i]);
                let d = self.flow.dist[c];
                if d != UNREACHED && d > RECYCLE_CELLS {
                    // Left far behind by every player: free the slot so spawning puts it back in play.
                    m.hp[i] = 0;
                    self.free.push(i as u32);
                    self.alive -= 1;
                    self.recycled_total += 1;
                    continue;
                }
                self.mcells.push((i as u32, c as u32));
            }
        }
        self.grid.build(&self.mcells);
        self.pcells.clear();
        self.live.clear();
        for (i, p) in self.players.iter().enumerate() {
            if p.alive() {
                self.pcells.push((i as u32, pcell_of(p.x, p.y) as u32));
                self.live.push(i as u16);
            }
        }
        self.pgrid.build(&self.pcells);
    }

    fn phase_move(&mut self) {
        let n = self.m.hp.len();
        let t = self.cfg.threads.max(1);
        let chunk = chunk_len(n, t);
        let ctx = MoveCtx {
            dist: &self.flow.dist,
            src: &self.flow.src,
            grid: &self.grid,
            players: &self.players,
            hp: &self.m.hp,
            kind: &self.m.kind,
        };
        let xs = self.m.x.chunks_mut(chunk);
        let ys = self.m.y.chunks_mut(chunk);
        let st = self.m.stagger.chunks_mut(chunk);
        if t == 1 {
            for (k, ((x, y), s)) in xs.zip(ys).zip(st).enumerate() {
                ctx.run(k * chunk, x, y, s);
            }
        } else {
            let ctx = &ctx;
            thread::scope(|sc| {
                for (k, ((x, y), s)) in xs.zip(ys).zip(st).enumerate() {
                    sc.spawn(move || ctx.run(k * chunk, x, y, s));
                }
            });
        }
    }

    fn phase_fight(&mut self) {
        self.m.hurt.fill(0);
        let n = self.players.len();
        let t = self.cfg.threads.max(1);
        let chunk = chunk_len(n, t);
        let ctx = FightCtx { tick: self.tick, m: &self.m, grid: &self.grid };
        let mut outs: Vec<(Vec<(u32, u16)>, u64)> = Vec::new();
        if t == 1 || n < 64 {
            let mut hits = std::mem::take(&mut self.hits);
            hits.clear();
            let mut deaths = 0;
            for (i, p) in self.players.iter_mut().enumerate() {
                deaths += ctx.player(i, p, &mut hits) as u64;
            }
            outs.push((hits, deaths));
        } else {
            let ctx = &ctx;
            thread::scope(|sc| {
                let hs: Vec<_> = self
                    .players
                    .chunks_mut(chunk)
                    .enumerate()
                    .map(|(k, ps)| {
                        sc.spawn(move || {
                            let mut hits = Vec::new();
                            let mut deaths = 0u64;
                            for (j, p) in ps.iter_mut().enumerate() {
                                deaths += ctx.player(k * chunk + j, p, &mut hits) as u64;
                            }
                            (hits, deaths)
                        })
                    })
                    .collect();
                for h in hs {
                    outs.push(h.join().expect("fight worker"));
                }
            });
        }
        // Apply in player order: the same on any thread count.
        self.killed.clear();
        for (hits, deaths) in &outs {
            self.deaths_total += deaths;
            for &(id, dmg) in hits {
                let i = id as usize;
                if self.m.hp[i] == 0 {
                    continue;
                }
                self.m.hp[i] = self.m.hp[i].saturating_sub(dmg);
                self.m.hurt[i] = 1;
                self.m.stagger[i] = STAGGER_TICKS;
                if self.m.hp[i] == 0 {
                    self.killed.push(id);
                }
            }
        }
        if let Some((h, _)) = outs.into_iter().next() {
            self.hits = h;
        }
        let r = XP_SHARE_PX * SUB;
        let r2 = (r as i64) * (r as i64);
        for k in 0..self.killed.len() {
            let i = self.killed[k] as usize;
            let (x, y) = (self.m.x[i], self.m.y[i]);
            let kind = self.m.kind[i];
            let mut xp = KINDS[(kind & 7) as usize].xp;
            if kind & 8 != 0 {
                xp *= ELITE_XP_MUL;
            }
            let players = &mut self.players;
            grid_box(&self.pgrid, PCELLS_W, PCELL_SHIFT, x - r, y - r, x + r, y + r, |pid| {
                let p = &mut players[pid as usize];
                if p.alive() && d2(p.x, p.y, x, y) <= r2 {
                    gain_xp(p, xp);
                }
            });
            self.free.push(i as u32);
            self.alive -= 1;
            self.kills_total += 1;
        }
    }

    fn phase_spawn(&mut self) {
        self.spawned.clear();
        if self.live.is_empty() {
            return;
        }
        let span = (SPAWN_MAX_PX * 2 + 1) as u64;
        let (min2, max2) = ((SPAWN_MIN_PX * SPAWN_MIN_PX) as i64, (SPAWN_MAX_PX * SPAWN_MAX_PX) as i64);
        let (hw, hh) = (VIEW_W / 2 * SUB, VIEW_H / 2 * SUB);
        let mut fails = 0;
        while let Some(&slot) = self.free.last() {
            let mut placed = None;
            for _ in 0..SPAWN_TRIES {
                let r = rng_next(&mut self.rng);
                let p = &self.players[self.live[(r % self.live.len() as u64) as usize] as usize];
                let dx = ((r >> 16) % span) as i32 - SPAWN_MAX_PX;
                let dy = ((r >> 32) % span) as i32 - SPAWN_MAX_PX;
                let dd = (dx * dx + dy * dy) as i64;
                if dd < min2 || dd > max2 {
                    continue;
                }
                let x = p.x + dx * SUB;
                let y = p.y + dy * SUB;
                if x < 0 || y < 0 || x >= FIELD || y >= FIELD {
                    continue;
                }
                let mut seen = false;
                let players = &self.players;
                grid_box(&self.pgrid, PCELLS_W, PCELL_SHIFT, x - hw, y - hh, x + hw, y + hh, |pid| {
                    let q = &players[pid as usize];
                    if (q.x - x).abs() < hw && (q.y - y).abs() < hh {
                        seen = true;
                    }
                });
                if !seen {
                    placed = Some((x, y));
                    break;
                }
            }
            let Some((x, y)) = placed else {
                fails += 1;
                if fails >= SPAWN_FAILS_PER_TICK {
                    break;
                }
                continue;
            };
            let r = rng_next(&mut self.rng);
            let kind = (r % 8) as u8;
            let elite = (r >> 8) % ELITE_ONE_IN == 0;
            let i = slot as usize;
            self.free.pop();
            self.m.x[i] = x;
            self.m.y[i] = y;
            self.m.kind[i] = kind | if elite { 8 } else { 0 };
            self.m.hp[i] = self.m.max_hp(i);
            self.m.stagger[i] = 0;
            self.m.hurt[i] = 0;
            self.alive += 1;
            self.spawns_total += 1;
            self.spawned.push(slot);
        }
    }
}

pub fn max_health(level: u16) -> u16 {
    200u16.saturating_add(20u16.saturating_mul(level.saturating_sub(1)))
}

fn gain_xp(p: &mut Player, xp: u32) {
    p.xp += xp;
    while p.level < 999 && p.xp >= 50 * p.level as u32 {
        p.xp -= 50 * p.level as u32;
        p.level += 1;
        p.max_health = max_health(p.level);
        p.health = (p.health + 20).min(p.max_health);
    }
}

struct MoveCtx<'a> {
    dist: &'a [u16],
    src: &'a [u16],
    grid: &'a Grid,
    players: &'a [Player],
    hp: &'a [u16],
    kind: &'a [u8],
}

impl MoveCtx<'_> {
    fn run(&self, base: usize, xs: &mut [i32], ys: &mut [i32], st: &mut [u8]) {
        for j in 0..xs.len() {
            let i = base + j;
            if self.hp[i] == 0 {
                continue;
            }
            if st[j] > 0 {
                st[j] -= 1;
                continue;
            }
            let (x, y) = (xs[j], ys[j]);
            let c = cell_of(x, y);
            let d = self.dist[c];
            if d == UNREACHED {
                continue;
            }
            let step = KINDS[(self.kind[i] & 7) as usize].speed as i32 * SUB / TICK_HZ as i32;
            let mut target = None;
            if d <= 2 && self.grid.count(c) <= CROWD_CAP {
                let p = &self.players[self.src[c] as usize];
                if p.alive() {
                    target = Some((p.x, p.y, STOP_PX * SUB));
                }
            }
            let (tx, ty, stop) = match target {
                Some(t) => t,
                None => {
                    // Down the field; an over-full neighbour costs like a step uphill per 2 extra monsters.
                    let cx = (c % CELLS_W) as i32;
                    let cy = (c / CELLS_W) as i32;
                    let mut best = (i64::MAX, cx, cy);
                    for (ox, oy) in NEIGHBOURS {
                        let nx = cx + ox;
                        let ny = cy + oy;
                        if nx < 0 || ny < 0 || nx >= CELLS_W as i32 || ny >= CELLS_W as i32 {
                            continue;
                        }
                        let nc = ny as usize * CELLS_W + nx as usize;
                        let nd = self.dist[nc];
                        if nd == UNREACHED {
                            continue;
                        }
                        let over = self.grid.count(nc).saturating_sub(CROWD_CAP) as i64;
                        let score = nd as i64 * 8 + over * 4;
                        if score < best.0 {
                            best = (score, nx, ny);
                        }
                    }
                    // Aim at the cell centre plus a per-monster offset so a crowd does not form a line.
                    let h = (i as u32).wrapping_mul(2_654_435_761);
                    let jx = ((h >> 8) % 17) as i32 - 8;
                    let jy = ((h >> 20) % 17) as i32 - 8;
                    let half = 1 << (CELL_SHIFT - 1);
                    ((best.1 << CELL_SHIFT) + half + jx * SUB, (best.2 << CELL_SHIFT) + half + jy * SUB, 0)
                }
            };
            let dx = (tx - x) as i64;
            let dy = (ty - y) as i64;
            let len = ((dx * dx + dy * dy) as u64).isqrt() as i64;
            if len <= stop as i64 {
                continue;
            }
            let go = (len - stop as i64).min(step as i64);
            xs[j] = clamp_pos(x + (dx * go / len) as i32);
            ys[j] = clamp_pos(y + (dy * go / len) as i32);
        }
    }
}

struct FightCtx<'a> {
    tick: u32,
    m: &'a Monsters,
    grid: &'a Grid,
}

impl FightCtx<'_> {
    /// Contact damage to the player and its attacks; true when the player died.
    fn player(&self, id: usize, p: &mut Player, hits: &mut Vec<(u32, u16)>) -> bool {
        p.hurt = false;
        if !p.alive() {
            return false;
        }
        let m = self.m;
        if (self.tick + id as u32) % CONTACT_EVERY == 0 {
            let r = CONTACT_PX * SUB;
            let r2 = (r as i64) * (r as i64);
            let mut dmg = 0u32;
            self.near(p.x, p.y, r, |i| {
                if m.hp[i] > 0 && d2(m.x[i], m.y[i], p.x, p.y) <= r2 {
                    dmg += KINDS[(m.kind[i] & 7) as usize].damage as u32;
                }
            });
            if dmg > 0 {
                p.hurt = true;
                if dmg >= p.health as u32 {
                    p.health = 0;
                    p.dead_timer = RESPAWN_TICKS;
                    return true;
                }
                p.health -= dmg as u16;
            }
        }
        let class = &CLASSES[p.class as usize];
        // Levels add 5% each up to 3x, so a lone player stays mortal.
        let power = 10 + (p.level.min(41) as u32 - 1) / 2;
        if p.cooldown > 0 {
            p.cooldown -= 1;
        } else {
            p.cooldown = class.cooldown;
            let dmg = (class.area_damage as u32 * power / 10) as u16;
            self.area(p.x, p.y, class.area_px * SUB, dmg, hits);
            if let Some(i) = self.nearest(p.x, p.y, class.bolt_px * SUB) {
                hits.push((i, (class.bolt_damage as u32 * power / 10) as u16));
            }
        }
        if p.skill_cd > 0 {
            p.skill_cd -= 1;
        } else if p.input & INPUT_SKILL != 0 {
            p.skill_cd = SKILL_COOLDOWN;
            let dmg = (class.area_damage as u32 * 3 * power / 10) as u16;
            self.area(p.x, p.y, class.area_px * 2 * SUB, dmg, hits);
        }
        false
    }

    fn near(&self, x: i32, y: i32, r: i32, mut f: impl FnMut(usize)) {
        let r = r + GRID_MARGIN;
        grid_box(self.grid, CELLS_W, CELL_SHIFT, x - r, y - r, x + r, y + r, |i| f(i as usize));
    }

    fn area(&self, x: i32, y: i32, r: i32, dmg: u16, hits: &mut Vec<(u32, u16)>) {
        let m = self.m;
        let r2 = (r as i64) * (r as i64);
        self.near(x, y, r, |i| {
            if m.hp[i] > 0 && d2(m.x[i], m.y[i], x, y) <= r2 {
                hits.push((i as u32, dmg));
            }
        });
    }

    /// The nearest live monster within `r` (ties to the lower id), searching rings of cells outward.
    fn nearest(&self, x: i32, y: i32, r: i32) -> Option<u32> {
        let m = self.m;
        let r2 = (r as i64) * (r as i64);
        let cx = x >> CELL_SHIFT;
        let cy = y >> CELL_SHIFT;
        let rings = ((r + GRID_MARGIN) >> CELL_SHIFT) + 1;
        let mut best: Option<(i64, u32)> = None;
        let lim = CELLS_W as i32 - 1;
        for ring in 0..=rings {
            for oy in -ring..=ring {
                let edge = oy == -ring || oy == ring;
                let mut ox = -ring;
                while ox <= ring {
                    let (nx, ny) = (cx + ox, cy + oy);
                    if nx >= 0 && ny >= 0 && nx <= lim && ny <= lim {
                        for &id in self.grid.cell(ny as usize * CELLS_W + nx as usize) {
                            let i = id as usize;
                            if m.hp[i] == 0 {
                                continue;
                            }
                            let dd = d2(m.x[i], m.y[i], x, y);
                            if dd <= r2 && best.is_none_or(|(bd, bi)| dd < bd || (dd == bd && id < bi)) {
                                best = Some((dd, id));
                            }
                        }
                    }
                    ox += if edge { 1 } else { 2 * ring.max(1) };
                }
            }
            // Anything in a farther ring is at least `ring` cells away, less the movement margin.
            if let Some((bd, _)) = best {
                let safe = ((ring << CELL_SHIFT) - GRID_MARGIN).max(0) as i64;
                if bd <= safe * safe {
                    break;
                }
            }
        }
        best.map(|(_, id)| id)
    }
}
