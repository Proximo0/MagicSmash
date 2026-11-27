//! The flow field: distance (in tenths of a cell) from every hero monsters may chase, rebuilt in slices
//! while monsters read the finished one. Walls and quiet zones are closed and corners are not cut. A hero's cell is
//! seeded with a head start by threat (rules section 3), so the horde bends toward the tanks.

use crate::{CELLS, CELLS_W};

pub const UNREACHED: u16 = u16::MAX;
/// One step between neighbouring cells, in distance units (tenths of a cell).
pub const STEP: u16 = 10;
/// The eight neighbours, E first and clockwise (y grows down).
pub const NEIGHBOURS: [(i32, i32); 8] = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)];

/// A source: (cell, hero, starting distance).
pub type Source = (u32, u16, u16);

pub struct Flow {
    pub dist: Vec<u16>,
    pub src: Vec<u16>,
    bdist: Vec<u16>,
    bsrc: Vec<u16>,
    queue: Vec<u32>,
    pub head: usize,
    /// Sources not yet seeded, sorted by starting distance; `seeded` of them are in.
    seeded: usize,
    pub active_sources: Vec<Source>,
    pub build_sources: Vec<Source>,
}

impl Flow {
    pub fn new() -> Flow {
        Flow {
            dist: vec![UNREACHED; CELLS],
            src: vec![0; CELLS],
            bdist: vec![UNREACHED; CELLS],
            bsrc: vec![0; CELLS],
            queue: Vec::with_capacity(CELLS),
            head: 0,
            seeded: 0,
            active_sources: Vec::new(),
            build_sources: Vec::new(),
        }
    }

    /// Starts a rebuild. Sources are sorted by (distance, hero) so the seeding order is fixed.
    pub fn start(&mut self, mut sources: Vec<Source>) {
        sources.sort_by_key(|&(c, h, d)| (d, h, c));
        self.bdist.fill(UNREACHED);
        // A cell the search does not reach keeps no source from an older build (a loaded field has none).
        self.bsrc.fill(0);
        self.queue.clear();
        self.head = 0;
        self.seeded = 0;
        self.build_sources = sources;
    }

    /// Pops at most `budget` cells (a seed counts as one); true when the search is done.
    /// A seed joins when the frontier reaches its starting distance, so the queue stays in order.
    pub fn run(&mut self, budget: usize, walls: &[u8]) -> bool {
        let mut n = 0;
        loop {
            if n >= budget {
                break;
            }
            let next_q = (self.head < self.queue.len()).then(|| self.bdist[self.queue[self.head] as usize]);
            let next_s = self.build_sources.get(self.seeded).map(|s| s.2);
            let c = match (next_q, next_s) {
                (None, None) => break,
                (Some(q), Some(s)) if s <= q => self.seed(),
                (None, Some(_)) => self.seed(),
                _ => {
                    let c = self.queue[self.head] as usize;
                    self.head += 1;
                    Some(c)
                }
            };
            n += 1;
            let Some(c) = c else { continue };
            self.expand(c, walls);
        }
        self.head == self.queue.len() && self.seeded == self.build_sources.len()
    }

    fn seed(&mut self) -> Option<usize> {
        let (c, h, d) = self.build_sources[self.seeded];
        self.seeded += 1;
        let c = c as usize;
        if self.bdist[c] <= d {
            return None;
        }
        self.bdist[c] = d;
        self.bsrc[c] = h;
        Some(c)
    }

    fn expand(&mut self, c: usize, walls: &[u8]) {
        let d = self.bdist[c].saturating_add(STEP);
        let s = self.bsrc[c];
        let cx = (c % CELLS_W) as i32;
        let cy = (c / CELLS_W) as i32;
        let w = CELLS_W as i32;
        for (ox, oy) in NEIGHBOURS {
            let nx = cx + ox;
            let ny = cy + oy;
            if nx < 0 || ny < 0 || nx >= w || ny >= w {
                continue;
            }
            let nc = ny as usize * CELLS_W + nx as usize;
            if walls[nc] & crate::tables::MONSTER_BLOCK != 0 {
                continue;
            }
            if ox != 0 && oy != 0 {
                // No cutting corners.
                let a = cy as usize * CELLS_W + nx as usize;
                let b = ny as usize * CELLS_W + cx as usize;
                if walls[a] & crate::tables::MONSTER_BLOCK != 0 || walls[b] & crate::tables::MONSTER_BLOCK != 0 {
                    continue;
                }
            }
            if self.bdist[nc] > d {
                self.bdist[nc] = d;
                self.bsrc[nc] = s;
                self.queue.push(nc as u32);
            }
        }
    }

    pub fn finish(&mut self) {
        std::mem::swap(&mut self.dist, &mut self.bdist);
        std::mem::swap(&mut self.src, &mut self.bsrc);
        self.active_sources = std::mem::take(&mut self.build_sources);
    }

    /// Pops done so far in the current build (for saving: replaying this many pops rebuilds it).
    pub fn progress(&self) -> usize {
        self.head + self.seeded
    }
}

impl Default for Flow {
    fn default() -> Self {
        Flow::new()
    }
}
