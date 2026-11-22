//! One field copy's simulation as the server runs it: the field, the lockstep state, the bots, and the
//! encoded record of every recent tick. `bench` (no sockets) and the field host (`host.rs`) both drive it.

use crate::bots::{join_spot, Bot};
use crate::lockstep::{pack_reserving, put_seq_head, seq_head_len, Join, Lockstep, TickRec, HASH_EVERY};
use realm_core::{Config, Field, Outing, Phase, Sheet};
use std::collections::VecDeque;
use std::time::Instant;

// Timed columns, ms per tick.
pub const C_FLOW: usize = 0;
pub const C_MOVE: usize = 1;
pub const C_GRID: usize = 2;
pub const C_FIGHT: usize = 3;
pub const C_SPAWN: usize = 4;
pub const C_INPUT: usize = 5;
pub const C_BOTS: usize = 6;
pub const C_A0: usize = 7;
pub const C_A1: usize = 8;
pub const C_B: usize = 9;
pub const C_TOTAL: usize = 10;
pub const NCOL: usize = 11;
pub const COL_NAMES: [&str; NCOL] = ["flow", "move", "grid", "fight", "spawn", "input", "bots", "encA0", "encA1", "encB", "tick"];

/// Encoded B records kept for resending.
pub const HISTORY: usize = 64;

/// What makes a simulation: the field, its seed, the monster cap, worker threads, the bots, the level the
/// crowd test's bench heroes join at (0: the field's top).
#[derive(Clone, Debug)]
pub struct SimOpts {
    pub field: u8,
    pub seed: u64,
    pub monsters: u32,
    pub threads: usize,
    pub bots: u32,
    pub rally_permille: u32,
    pub level: u8,
}

impl Default for SimOpts {
    fn default() -> Self {
        SimOpts { field: 0, seed: 1, monsters: 20_000, threads: 1, bots: 0, rally_permille: 300, level: 0 }
    }
}

/// A hero to join this tick: her sheet, her outing state and where she appears.
#[derive(Clone, Debug)]
pub struct JoinReq {
    pub sheet: Sheet,
    pub outing: Outing,
    pub x: i32,
    pub y: i32,
}

pub struct Sim {
    pub opts: SimOpts,
    pub field: Field,
    pub ls: Lockstep,
    pub bots: Vec<Bot>,
    rng: u64,
    /// Encoded B records of the last ticks.
    pub history: VecDeque<(u32, Vec<u8>)>,
    pub tick_time: u16,
}

impl Sim {
    pub fn new(opts: &SimOpts) -> Sim {
        let field = Field::open(opts.field, opts.seed, Config { monsters: opts.monsters, threads: opts.threads });
        Sim { opts: opts.clone(), field, ls: Lockstep::default(), bots: Vec::new(), rng: opts.seed ^ 0xB07, history: VecDeque::new(), tick_time: 0 }
    }

    /// Ids the next joins will get: the lowest free slots after this tick's leaves.
    pub fn predict_ids(&self, leaves: &[u16], n: usize) -> Vec<u16> {
        let ps = self.field.players();
        let mut taken: Vec<bool> = ps.iter().map(|p| p.present).collect();
        for &l in leaves {
            if let Some(t) = taken.get_mut(l as usize) {
                *t = false;
            }
        }
        let mut out = Vec::new();
        let mut i = 0;
        while out.len() < n {
            if i >= taken.len() {
                taken.push(false);
            }
            if !taken[i] {
                taken[i] = true;
                out.push(i as u16);
            }
            i += 1;
        }
        out
    }

    /// One tick: bots decide, the record is built and applied through the lockstep path, B is encoded.
    /// `client_inputs` are (hero id, two-byte input). Returns the ids `joins` got.
    pub fn tick(&mut self, joins: &[JoinReq], leaves: &[u16], client_inputs: &[(u16, u16)], row: &mut [f64; NCOL]) -> Vec<u16> {
        let t0 = Instant::now();
        // Bots joining at the start, first so they take the low ids.
        let mut all: Vec<JoinReq> = Vec::new();
        let mut new_bots = 0;
        if self.field.tick() == 0 {
            for k in 0..self.opts.bots {
                let rally = (k as u64 * 1000 / self.opts.bots.max(1) as u64) < self.opts.rally_permille as u64;
                let (class, race, x, y) = join_spot(&mut self.rng, rally);
                let level = self.bench_level();
                all.push(JoinReq { sheet: Sheet::bench(class, race, level), outing: Outing::new(), x, y });
                new_bots += 1;
            }
        }
        all.extend(joins.iter().cloned());
        for b in &mut self.bots {
            b.decide(&self.field);
        }
        let ids = self.predict_ids(leaves, all.len());
        for (k, &id) in ids.iter().take(new_bots).enumerate() {
            let rally = (k as u64 * 1000 / self.opts.bots.max(1) as u64) < self.opts.rally_permille as u64;
            self.bots.push(Bot::new(id, rally, self.opts.seed));
        }
        let t_bots = Instant::now();
        let mut rec = TickRec { tick: self.field.tick() + 1, leaves: leaves.to_vec(), ..TickRec::default() };
        for (j, &id) in all.iter().zip(&ids) {
            rec.joins.push(Join { id, sheet: j.sheet.clone(), outing: j.outing.clone(), x: j.x, y: j.y });
        }
        let slots = self.field.players().len().max(ids.iter().map(|&i| i as usize + 1).max().unwrap_or(0));
        let mut want = vec![0u16; slots];
        for b in &self.bots {
            want[b.id as usize] = b.input;
        }
        for &(id, inp) in client_inputs {
            if let Some(w) = want.get_mut(id as usize) {
                *w = inp;
            }
        }
        for &l in leaves {
            if let Some(w) = want.get_mut(l as usize) {
                *w = 0;
            }
        }
        rec.changes = self.ls.changes(&rec, &want);
        let mut last = Instant::now();
        let mut marks = [0f64; 6];
        let ok = self.ls.apply(&mut self.field, &rec, |ph| {
            let now = Instant::now();
            let ms = (now - last).as_secs_f64() * 1000.0;
            last = now;
            let col = match ph {
                Phase::Input => C_INPUT,
                Phase::Flow => C_FLOW,
                Phase::Grid => C_GRID,
                Phase::Move => C_MOVE,
                Phase::Fight => C_FIGHT,
                Phase::Spawn => C_SPAWN,
            };
            marks[col.min(5)] += ms;
        });
        assert!(ok, "join ids or tick went wrong");
        row[..6].copy_from_slice(&marks);
        let step_ms = (Instant::now() - t_bots).as_secs_f64() * 1000.0;
        row[C_BOTS] = (t_bots - t0).as_secs_f64() * 1000.0;
        self.tick_time = (step_ms * 100.0).min(65535.0) as u16;
        let tb = Instant::now();
        if rec.tick % HASH_EVERY == 0 {
            rec.hash = Some(self.field.hash());
        }
        let mut bytes = Vec::new();
        rec.encode(&mut bytes);
        self.history.push_back((rec.tick, bytes));
        if self.history.len() > HISTORY {
            self.history.pop_front();
        }
        row[C_B] = (Instant::now() - tb).as_secs_f64() * 1000.0;
        ids.into_iter().skip(new_bots).collect()
    }

    /// The class level bench heroes join at.
    pub fn bench_level(&self) -> u8 {
        if self.opts.level == 0 { realm_core::tables::FIELDS[self.opts.field as usize].top } else { self.opts.level }
    }

    /// B datagrams for a client that has applied up to `ack` (at most `HISTORY` ticks back).
    pub fn b_datagrams(&self, ack: u32, out: &mut Vec<Vec<u8>>) {
        let ticks: Vec<u32> = self.history.iter().map(|(t, _)| *t).filter(|&t| t > ack).collect();
        self.b_datagrams_for(&ticks, &VecDeque::new(), out);
    }

    /// The datagrams carrying the records of `ticks` (ascending). A lockstep player's `seqs` (tick, seq of its
    /// input in force) for those ticks go in a `0x92` head on the first datagram, one per tick from the first
    /// to the last tick sent (the ticks between that are not sent too, so the list stays contiguous).
    pub fn b_datagrams_for(&self, ticks: &[u32], seqs: &VecDeque<(u32, u32)>, out: &mut Vec<Vec<u8>>) {
        let recs: Vec<(u32, &[u8])> = self.history.iter().filter(|(t, _)| ticks.binary_search(t).is_ok()).map(|(t, b)| (*t, b.as_slice())).collect();
        let (Some(&lo), Some(&hi)) = (ticks.first(), ticks.last()) else {
            out.clear();
            return;
        };
        let mine: Vec<u32> = seqs.iter().filter(|(t, _)| (lo..=hi).contains(t)).map(|&(_, s)| s).collect();
        let first = seqs.iter().find(|(t, _)| (lo..=hi).contains(t)).map(|&(t, _)| t);
        match first {
            Some(first) => {
                pack_reserving(&recs, seq_head_len(mine.len()), out);
                if let Some(d) = out.first_mut() {
                    put_seq_head(first, &mine, d);
                }
            }
            None => pack_reserving(&recs, 0, out),
        }
    }
}
