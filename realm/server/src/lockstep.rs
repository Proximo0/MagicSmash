//! Protocol B: every client runs the whole field; the server sends what changed each tick.
//!
//! A tick record (this job's packing): `u16 n joins, [u16 id, u8 class, u8 race, u8 level, i32 x, i32 y]`,
//! `u16 n leaves, [u16 id]`, `u16 n changes, [varint slot gap, u16 input]` (inputs persist until changed),
//! `u8 has hash, [u64 hash after the tick]` (every 20 ticks).
//!
//! Datagram `0x90, u8 n records`, then records `u32 tick, u8 frag, u8 frags, u16 len, bytes`; a record too
//! big for one datagram goes in fragments. The server repeats every tick after the client's
//! acknowledgement (INPUT's `u32` field), so a lost datagram costs a repeat, not a desync.
//!
//! Joining: `0x91, u32 tick, u16 part, u16 parts, bytes` carries the state after `tick`: the field
//! `u32 n` and the persistent `u16` inputs, then the field (`Field::to_bytes`).
//!
//! The server drives its own field through `Lockstep::apply`, the same code the follower runs, so both
//! apply joins, leaves and inputs in the same order.

use crate::{put_i32, put_u16, put_u32, put_u64, put_varint, Rd, MAX_DATAGRAM, MSG_STATE, MSG_TICKS};
use realm_core::{Field, Outing, Phase, Sheet};

pub const HASH_EVERY: u32 = 20;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Join {
    pub id: u16,
    pub class: u8,
    pub race: u8,
    pub level: u8,
    pub x: i32,
    pub y: i32,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct TickRec {
    pub tick: u32,
    pub joins: Vec<Join>,
    pub leaves: Vec<u16>,
    pub changes: Vec<(u16, u16)>,
    pub hash: Option<u64>,
}

impl TickRec {
    pub fn encode(&self, w: &mut Vec<u8>) {
        put_u16(w, self.joins.len() as u16);
        for j in &self.joins {
            put_u16(w, j.id);
            w.push(j.class);
            w.push(j.race);
            w.push(j.level);
            put_i32(w, j.x);
            put_i32(w, j.y);
        }
        put_u16(w, self.leaves.len() as u16);
        for &l in &self.leaves {
            put_u16(w, l);
        }
        put_u16(w, self.changes.len() as u16);
        let mut prev = 0u32;
        for &(slot, inp) in &self.changes {
            put_varint(w, slot as u32 - prev);
            prev = slot as u32;
            put_u16(w, inp);
        }
        match self.hash {
            Some(h) => {
                w.push(1);
                put_u64(w, h);
            }
            None => w.push(0),
        }
    }

    pub fn decode(tick: u32, b: &[u8]) -> Option<TickRec> {
        let mut r = Rd::new(b);
        let mut t = TickRec { tick, ..TickRec::default() };
        for _ in 0..r.u16()? {
            t.joins.push(Join { id: r.u16()?, class: r.u8()?, race: r.u8()?, level: r.u8()?, x: r.i32()?, y: r.i32()? });
        }
        for _ in 0..r.u16()? {
            t.leaves.push(r.u16()?);
        }
        let mut prev = 0u32;
        for _ in 0..r.u16()? {
            prev += r.varint()?;
            t.changes.push((prev as u16, r.u16()?));
        }
        if r.u8()? == 1 {
            t.hash = Some(r.u64()?);
        }
        (r.left() == 0).then_some(t)
    }
}

/// The input bytes every player holds, kept beside the field on both sides.
#[derive(Clone, Debug, Default)]
pub struct Lockstep {
    pub inputs: Vec<u16>,
}

impl Lockstep {
    /// Leaves, then joins (ids must come out as recorded), then input changes, then the step.
    /// Returns false if a join got a different id (a desync).
    pub fn apply(&mut self, f: &mut Field, rec: &TickRec, mark: impl FnMut(Phase)) -> bool {
        let mut ok = true;
        for &l in &rec.leaves {
            f.leave(l);
            if let Some(i) = self.inputs.get_mut(l as usize) {
                *i = 0;
            }
        }
        for j in &rec.joins {
            let id = f.join(&Sheet::bench(j.class, j.race, j.level), &Outing::new(), j.x, j.y);
            ok &= id == j.id;
            if self.inputs.len() <= id as usize {
                self.inputs.resize(id as usize + 1, 0);
            }
            self.inputs[id as usize] = 0;
        }
        for &(slot, inp) in &rec.changes {
            if self.inputs.len() <= slot as usize {
                self.inputs.resize(slot as usize + 1, 0);
            }
            self.inputs[slot as usize] = inp;
        }
        f.step_with(&self.inputs, mark);
        ok && f.tick() == rec.tick
    }

    /// The changes that turn the held inputs into `want`, after `rec`'s leaves and joins reset theirs.
    pub fn changes(&self, rec: &TickRec, want: &[u16]) -> Vec<(u16, u16)> {
        let mut held = self.inputs.clone();
        for &id in rec.leaves.iter().chain(rec.joins.iter().map(|j| &j.id)) {
            if let Some(i) = held.get_mut(id as usize) {
                *i = 0;
            }
        }
        let mut out = Vec::new();
        for (i, &w) in want.iter().enumerate() {
            if held.get(i).copied().unwrap_or(0) != w {
                out.push((i as u16, w));
            }
        }
        out
    }

    /// `u32 n, n u16 inputs`, then the field.
    pub fn state_bytes(&self, f: &Field) -> Vec<u8> {
        let mut b = Vec::new();
        put_u32(&mut b, self.inputs.len() as u32);
        self.inputs.iter().for_each(|&i| put_u16(&mut b, i));
        b.extend_from_slice(&f.to_bytes());
        b
    }

    pub fn from_state(b: &[u8], threads: usize) -> Option<(Field, Lockstep)> {
        let mut r = Rd::new(b);
        let n = r.u32()? as usize;
        let inputs = (0..n).map(|_| r.u16()).collect::<Option<Vec<u16>>>()?;
        let f = Field::from_bytes(&b[4 + 2 * n..], threads)?;
        Some((f, Lockstep { inputs }))
    }
}

const REC_HEAD: usize = 8;
const FRAG_MAX: usize = MAX_DATAGRAM - 2 - REC_HEAD;

/// Packs encoded tick records (tick, bytes) into datagrams, fragmenting big ones.
pub fn pack(recs: &[(u32, &[u8])], out: &mut Vec<Vec<u8>>) {
    out.clear();
    let mut cur: Vec<u8> = Vec::new();
    for &(tick, bytes) in recs {
        let frags = bytes.len().div_ceil(FRAG_MAX).max(1);
        for k in 0..frags {
            let piece = &bytes[k * FRAG_MAX..((k + 1) * FRAG_MAX).min(bytes.len())];
            if !cur.is_empty() && cur.len() + REC_HEAD + piece.len() > MAX_DATAGRAM {
                out.push(std::mem::take(&mut cur));
            }
            if cur.is_empty() {
                cur.extend_from_slice(&[MSG_TICKS, 0]);
            }
            put_u32(&mut cur, tick);
            cur.push(k as u8);
            cur.push(frags as u8);
            put_u16(&mut cur, piece.len() as u16);
            cur.extend_from_slice(piece);
            cur[1] += 1;
        }
    }
    if !cur.is_empty() {
        out.push(cur);
    }
}

/// Reassembles tick records from datagrams on the follower's side.
#[derive(Default)]
pub struct Assembler {
    pending: std::collections::BTreeMap<u32, Vec<Option<Vec<u8>>>>,
}

impl Assembler {
    /// Takes a `0x90` datagram; records at or before `applied` are dropped.
    pub fn take(&mut self, b: &[u8], applied: u32) -> Option<()> {
        let mut r = Rd::new(b);
        if r.u8()? != MSG_TICKS {
            return None;
        }
        for _ in 0..r.u8()? {
            let tick = r.u32()?;
            let k = r.u8()? as usize;
            let n = r.u8()? as usize;
            let len = r.u16()? as usize;
            let piece = r.bytes(len)?;
            if tick <= applied {
                continue;
            }
            let e = self.pending.entry(tick).or_insert_with(|| vec![None; n]);
            if k < e.len() {
                e[k] = Some(piece.to_vec());
            }
        }
        Some(())
    }

    /// The next record's bytes if tick `next` is complete.
    pub fn next(&mut self, next: u32) -> Option<Vec<u8>> {
        let e = self.pending.get(&next)?;
        if e.iter().any(|p| p.is_none()) {
            return None;
        }
        let e = self.pending.remove(&next)?;
        while self.pending.first_key_value().is_some_and(|(&t, _)| t < next) {
            self.pending.pop_first();
        }
        Some(e.into_iter().flatten().flatten().collect())
    }
}

/// Splits a state into `0x91` parts.
pub fn state_parts(tick: u32, b: &[u8]) -> Vec<Vec<u8>> {
    let chunk = MAX_DATAGRAM - 9;
    let n = b.len().div_ceil(chunk).max(1);
    (0..n)
        .map(|k| {
            let mut w = vec![MSG_STATE];
            put_u32(&mut w, tick);
            put_u16(&mut w, k as u16);
            put_u16(&mut w, n as u16);
            w.extend_from_slice(&b[k * chunk..((k + 1) * chunk).min(b.len())]);
            w
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use realm_core::{Config, FIELD, SUB};

    #[test]
    fn a_follower_from_packed_records_keeps_the_same_hash() {
        let mut server = Field::new(21, Config { monsters: 6000, threads: 3 });
        let mut ls = Lockstep::default();
        let mut follower: Option<(Field, Lockstep)> = None;
        let mut asm = Assembler::default();
        let mut dgrams = Vec::new();
        let mut checked = 0;
        for t in 1..=400u32 {
            let mut rec = TickRec { tick: t, ..TickRec::default() };
            if t <= 3 {
                for k in 0..20u16 {
                    rec.joins.push(Join { id: (t as u16 - 1) * 20 + k, class: (k % 5) as u8, race: (k % 4) as u8, level: 1, x: FIELD / 2 + k as i32 * 50 * SUB, y: FIELD / 2 });
                }
            }
            if t == 150 {
                rec.leaves.push(5);
            }
            if t == 160 {
                rec.joins.push(Join { id: 5, class: 1, race: 1, level: 1, x: FIELD / 3, y: FIELD / 3 });
            }
            let want: Vec<u16> = (0..60u32).map(|i| if i == 5 && (150..160).contains(&t) { 0 } else { ((i * 7 + t / 15) % 9) as u16 }).collect();
            rec.changes = ls.changes(&rec, &want);
            assert!(ls.apply(&mut server, &rec, |_| {}));
            if t % HASH_EVERY == 0 {
                rec.hash = Some(server.hash());
            }
            let mut bytes = Vec::new();
            rec.encode(&mut bytes);
            if t == 50 {
                let st = ls.state_bytes(&server);
                follower = Some(Lockstep::from_state(&st, 1).expect("state"));
                continue;
            }
            pack(&[(t, &bytes)], &mut dgrams);
            if let Some((f, fl)) = follower.as_mut() {
                for d in &dgrams {
                    asm.take(d, f.tick()).unwrap();
                }
                let got = TickRec::decode(t, &asm.next(f.tick() + 1).unwrap()).unwrap();
                assert_eq!(got, rec);
                assert!(fl.apply(f, &got, |_| {}));
                if let Some(h) = got.hash {
                    assert_eq!(f.hash(), h, "tick {t}");
                    checked += 1;
                }
            }
        }
        assert!(checked >= 17);
    }
}
