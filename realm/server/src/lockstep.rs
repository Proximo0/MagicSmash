//! Protocol B: every client runs the whole field; the server sends what changed each tick.
//!
//! A tick record (this job's packing): `u16 n joins, [u16 id, sheet, outing, i32 x, i32 y]` (`wire.rs`),
//! `u16 n leaves, [u16 id]`, `u16 n changes, [varint slot gap, u16 input]` (inputs persist until changed),
//! `u8 flags`: bit 0 `u64 hash after the tick` (every 20 ticks), bit 1 `u64 realm clock`, bit 2 the PvP block
//! (job R3b): `u16 n`, then n tagged entries from the PvP span of `gateway/src/proto/ranges.rs`:
//! `0x74 GUILD u16 id, u64 guild` (the guild of this record's join `id`, never 0) and
//! `0x75 WAR u64 war, u64 guild a, u64 guild b, u32 tide` (`Field::declare_war`). A record with neither has no
//! block, so a field without guilds or wars sends the same bytes as before.
//!
//! Datagram `0x90, u8 n records`, then records `u32 tick, u8 frag, u8 frags, u16 len, bytes`; a record too
//! big for one datagram goes in fragments. The server repeats every tick after the client's
//! acknowledgement (INPUT's `u32` field), so a lost datagram costs a repeat, not a desync.
//!
//! Joining: `0x91, u32 tick, u16 part, u16 parts, bytes` carries the state after `tick`: the field
//! `u32 n` and the persistent `u16` inputs, then the field (`Field::to_bytes`).
//!
//! A lockstep player (HELLO proto 4) is a follower whose own inputs enter the stream. Its INPUT adds
//! `u32 seq, u8 n, n x u16 word` (a number per input sent, from 1, and the two-byte inputs of seqs `seq - 1`
//! back to `seq - n`, so one lost INPUT costs nothing). The server queues them and uses one a tick
//! (`InputQueue`). The first B datagram of each tick's send to a player is
//! `0x92, u32 first tick, u8 n, n x u32 seq` (the seq of the input in force for that player at ticks
//! `first .. first + n`, every tick after its acknowledgement) followed by a whole `0x90` datagram. That is
//! what lets the player replay only the inputs the server has not used yet (`predict.rs`).
//!
//! The server drives its own field through `Lockstep::apply`, the same code the follower runs, so both
//! apply joins, leaves and inputs in the same order.

use crate::{put_i32, put_u16, put_u32, put_u64, put_varint, Rd, MAX_DATAGRAM, MSG_PLAYER_TICKS, MSG_STATE, MSG_TICKS};
use crate::wire::{put_outing, put_sheet, read_outing, read_sheet};
use realm_core::{Field, Outing, Phase, Sheet};

pub const HASH_EVERY: u32 = 20;

/// A hero entering the field: her saved sheet and her outing state (a fresh one, or the one she left another
/// copy with), where she stands, and the slot the core must give her (every follower checks it).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Join {
    pub id: u16,
    pub sheet: Sheet,
    pub outing: Outing,
    pub x: i32,
    pub y: i32,
    /// Her guild (0: none), tagged with `Field::set_guild` as she joins (a GUILD entry of the PvP block).
    pub guild: u64,
}

impl Join {
    /// A bench hero (bots, the crowd test's HELLO class and race): see `Sheet::bench`.
    pub fn bench(id: u16, class: u8, race: u8, level: u8, x: i32, y: i32) -> Join {
        Join { id, sheet: Sheet::bench(class, race, level), outing: Outing::new(), x, y, guild: 0 }
    }
}

/// The PvP block's entry tags: the PvP span reserved in `gateway/src/proto/ranges.rs` (requests 0x74..0x77).
pub const REC_GUILD: u8 = 0x74;
pub const REC_WAR: u8 = 0x75;

/// A war the gateway arms on a field copy (`Field::declare_war`): every copy of the field and every follower apply
/// it at the same tick, so their hashes stay equal.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WarArm {
    pub id: u64,
    pub a: u64,
    pub b: u64,
    pub tide: u32,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct TickRec {
    pub tick: u32,
    pub joins: Vec<Join>,
    pub leaves: Vec<u16>,
    pub changes: Vec<(u16, u16)>,
    pub hash: Option<u64>,
    /// The realm clock to set before the step (the step then adds one): the server's copy follows the realm's one
    /// clock this way, and every follower with it. None: the field's own clock runs on.
    pub clock: Option<u64>,
    /// Wars armed before the step, after the joins (WAR entries of the PvP block).
    pub wars: Vec<WarArm>,
}

impl TickRec {
    pub fn encode(&self, w: &mut Vec<u8>) {
        put_u16(w, self.joins.len() as u16);
        for j in &self.joins {
            put_u16(w, j.id);
            put_sheet(w, &j.sheet);
            put_outing(w, &j.outing);
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
        // Flags: bit 0 a hash follows, bit 1 a clock follows, bit 2 the PvP block follows.
        let guilds = self.joins.iter().filter(|j| j.guild != 0).count();
        // `Sim::tick` keeps guilded joins and wars within a u16 together; a record past it is a bug, never sent cut.
        let pvp = guilds + self.wars.len();
        assert!(pvp <= u16::MAX as usize, "a PvP block of {pvp} entries");
        w.push(self.hash.is_some() as u8 | (self.clock.is_some() as u8) << 1 | ((pvp > 0) as u8) << 2);
        if let Some(h) = self.hash {
            put_u64(w, h);
        }
        if let Some(c) = self.clock {
            put_u64(w, c);
        }
        if pvp > 0 {
            put_u16(w, pvp as u16);
            for j in self.joins.iter().filter(|j| j.guild != 0) {
                w.push(REC_GUILD);
                put_u16(w, j.id);
                put_u64(w, j.guild);
            }
            for a in &self.wars {
                w.push(REC_WAR);
                put_u64(w, a.id);
                put_u64(w, a.a);
                put_u64(w, a.b);
                put_u32(w, a.tide);
            }
        }
    }

    pub fn decode(tick: u32, b: &[u8]) -> Option<TickRec> {
        let mut r = Rd::new(b);
        let mut t = TickRec { tick, ..TickRec::default() };
        for _ in 0..r.u16()? {
            t.joins.push(Join { id: r.u16()?, sheet: read_sheet(&mut r)?, outing: read_outing(&mut r)?, x: r.i32()?, y: r.i32()?, guild: 0 });
        }
        for _ in 0..r.u16()? {
            t.leaves.push(r.u16()?);
        }
        let mut prev = 0u32;
        for _ in 0..r.u16()? {
            prev = prev.checked_add(r.varint()?)?;
            t.changes.push((u16::try_from(prev).ok()?, r.u16()?));
        }
        let flags = r.u8()?;
        if flags & !7 != 0 {
            return None;
        }
        if flags & 1 != 0 {
            t.hash = Some(r.u64()?);
        }
        if flags & 2 != 0 {
            t.clock = Some(r.u64()?);
        }
        if flags & 4 != 0 {
            let n = r.u16()?;
            if n == 0 {
                return None;
            }
            for _ in 0..n {
                match r.u8()? {
                    REC_GUILD => {
                        let (id, guild) = (r.u16()?, r.u64()?);
                        // The guild of a join of this record, once, and never 0 (0 is written as no entry).
                        let j = t.joins.iter_mut().find(|j| j.id == id && j.guild == 0)?;
                        if guild == 0 {
                            return None;
                        }
                        j.guild = guild;
                    }
                    REC_WAR => t.wars.push(WarArm { id: r.u64()?, a: r.u64()?, b: r.u64()?, tide: r.u32()? }),
                    _ => return None,
                }
            }
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
    /// Leaves, then joins (ids must come out as recorded) with their guilds, then wars, input changes, the clock,
    /// then the step.
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
            let id = f.join(&j.sheet, &j.outing, j.x, j.y);
            ok &= id == j.id;
            if j.guild != 0 {
                f.set_guild(id, j.guild);
            }
            if self.inputs.len() <= id as usize {
                self.inputs.resize(id as usize + 1, 0);
            }
            self.inputs[id as usize] = 0;
        }
        for a in &rec.wars {
            // Refused (`false`) the same way on every copy and follower: the state stays equal either way.
            f.declare_war(a.id, a.a, a.b, a.tide);
        }
        for &(slot, inp) in &rec.changes {
            if self.inputs.len() <= slot as usize {
                self.inputs.resize(slot as usize + 1, 0);
            }
            self.inputs[slot as usize] = inp;
        }
        if let Some(c) = rec.clock {
            f.set_clock(c);
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

/// Packs encoded tick records (tick, bytes) into datagrams, fragmenting big ones, leaving `reserve` bytes
/// free in the first datagram for a head put in front of it (`put_seq_head`).
pub fn pack_reserving(recs: &[(u32, &[u8])], reserve: usize, out: &mut Vec<Vec<u8>>) {
    out.clear();
    let mut cur: Vec<u8> = Vec::new();
    for &(tick, bytes) in recs {
        let frags = bytes.len().div_ceil(FRAG_MAX - reserve).max(1);
        let size = bytes.len().div_ceil(frags).max(1);
        for k in 0..frags {
            let piece = &bytes[k * size..((k + 1) * size).min(bytes.len())];
            let room = if out.is_empty() { MAX_DATAGRAM - reserve } else { MAX_DATAGRAM };
            if !cur.is_empty() && cur.len() + REC_HEAD + piece.len() > room {
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

/// The longest seq list a player head carries (the server keeps this many ticks of history).
pub const SEQS_MAX: usize = 64;
/// `0x92, u32 first tick, u8 n`.
const SEQ_HEAD: usize = 6;

/// The bytes a player head adds in front of the first datagram for `n` seqs.
pub fn seq_head_len(n: usize) -> usize {
    SEQ_HEAD + 4 * n.min(SEQS_MAX)
}

/// Turns the first datagram of a send into a `0x92` one: the seqs in force at ticks `first..`, then the
/// datagram as it was. Only the last `SEQS_MAX` seqs are kept.
pub fn put_seq_head(first: u32, seqs: &[u32], dgram: &mut Vec<u8>) {
    let skip = seqs.len().saturating_sub(SEQS_MAX);
    let seqs = &seqs[skip..];
    let mut w = Vec::with_capacity(seq_head_len(seqs.len()) + dgram.len());
    w.push(MSG_PLAYER_TICKS);
    put_u32(&mut w, first + skip as u32);
    w.push(seqs.len() as u8);
    for &s in seqs {
        put_u32(&mut w, s);
    }
    w.extend_from_slice(dgram);
    *dgram = w;
}

/// Splits a `0x92` datagram into (first tick, seqs) and the `0x90` datagram it carries.
pub fn take_seq_head(b: &[u8]) -> Option<(u32, Vec<u32>, &[u8])> {
    let mut r = Rd::new(b);
    if r.u8()? != MSG_PLAYER_TICKS {
        return None;
    }
    let first = r.u32()?;
    let n = r.u8()? as usize;
    let seqs = (0..n).map(|_| r.u32()).collect::<Option<Vec<u32>>>()?;
    Some((first, seqs, &b[r.at..]))
}

/// Earlier inputs repeated in each lockstep player's INPUT.
pub const INPUT_REPEAT: usize = 3;
/// Inputs a player may have waiting on the server; beyond this the oldest go (the client runs fast).
pub const INPUT_QUEUE_MAX: usize = 3;

/// A lockstep player's inputs on the server: each tick uses the next one in seq order, so inputs that
/// arrive unevenly (jitter) still move the hero one input a tick, as the player's prediction assumes. With
/// none waiting the last one holds (the core reads picks and potions as edges, so a held word does not
/// pick or drink twice).
#[derive(Clone, Debug, Default)]
pub struct InputQueue {
    newest: u32,
    queue: std::collections::VecDeque<(u32, u16)>,
    /// The input in force and its seq.
    pub seq: u32,
    pub input: u16,
}

impl InputQueue {
    /// An INPUT: `words[0]` is `seq`'s word, `words[k]` is `seq - k`'s. Seqs already seen are ignored.
    pub fn take(&mut self, seq: u32, words: &[u16]) {
        for k in (0..words.len()).rev() {
            let Some(s) = seq.checked_sub(k as u32).filter(|&s| s > self.newest) else { continue };
            self.newest = s;
            self.queue.push_back((s, words[k]));
        }
        while self.queue.len() > INPUT_QUEUE_MAX {
            self.queue.pop_front();
        }
    }

    /// The input for the next tick.
    pub fn next_tick(&mut self) -> u16 {
        if let Some((s, m)) = self.queue.pop_front() {
            self.seq = s;
            self.input = m;
        }
        self.input
    }
}

/// Which records a client gets this tick: every new one at once, and one it has not acknowledged only after
/// a whole round trip has passed since it was last sent (then again after another), so a client with a
/// 160 ms round trip is not sent every tick four times over. The round trip is measured from the client's own
/// acknowledgements, in server ticks, smoothed over 4.
#[derive(Clone, Debug)]
pub struct Resend {
    /// tick -> the server tick it was last sent at, for ticks not yet acknowledged.
    sent: std::collections::BTreeMap<u32, u32>,
    /// tick -> the server tick it was first sent at (for the round trip sample).
    first: std::collections::BTreeMap<u32, u32>,
    acked: u32,
    /// Smoothed round trip in quarter ticks.
    srtt4: u32,
}

/// The round trip assumed before the first acknowledgement (200 ms).
pub const RTT_START: u32 = 4;
/// A record is sent again when its last send is older than `rtt + RESEND_SLACK` ticks.
pub const RESEND_SLACK: u32 = 1;

impl Default for Resend {
    fn default() -> Self {
        Resend { sent: Default::default(), first: Default::default(), acked: 0, srtt4: RTT_START * 4 }
    }
}

impl Resend {
    /// The client says it has applied every tick up to `ack`; `now` is the server's tick count.
    pub fn on_ack(&mut self, ack: u32, now: u32) {
        if ack > self.acked {
            if let Some(&f) = self.first.get(&ack) {
                let sample = now.saturating_sub(f).max(1);
                self.srtt4 = ((3 * self.srtt4 + 4 * sample + 2) / 4).max(4);
            }
            self.acked = ack;
            self.sent = self.sent.split_off(&(ack + 1));
            self.first = self.first.split_off(&(ack + 1));
        }
    }

    /// The ticks to send now out of `have` (ascending): the new ones, and the old ones a round trip has
    /// passed on. Ticks at or before the acknowledgement are skipped. Marks the picked ones sent.
    pub fn pick(&mut self, now: u32, have: impl Iterator<Item = u32>) -> Vec<u32> {
        let wait = self.rtt() + RESEND_SLACK;
        let mut out = Vec::new();
        for t in have.filter(|&t| t > self.acked) {
            let due = match self.sent.get(&t) {
                None => true,
                Some(&at) => now.saturating_sub(at) >= wait,
            };
            if due {
                self.sent.insert(t, now);
                self.first.entry(t).or_insert(now);
                out.push(t);
            }
        }
        out
    }

    /// The smoothed round trip in server ticks, rounded up.
    pub fn rtt(&self) -> u32 {
        self.srtt4.div_ceil(4)
    }

    pub fn acked(&self) -> u32 {
        self.acked
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
                    rec.joins.push(Join::bench((t as u16 - 1) * 20 + k, (k % 5) as u8, (k % 4) as u8, 1 + (k % 3) as u8 * 20, FIELD / 2 + k as i32 * 50 * SUB, FIELD / 2));
                }
            }
            if t == 150 {
                rec.leaves.push(5);
            }
            if t == 160 {
                rec.joins.push({ let mut j = Join::bench(5, 1, 1, 30, FIELD / 3, FIELD / 3); j.outing.coin = 90; j.outing.draws = 4; j });
            }
            // The realm clock moves the field into a tide, and later to a field boss's rising, on both sides.
            let fid = server.field_id();
            if t == 100 {
                rec.clock = Some(realm_core::tide_start(fid, 0) - 3);
            }
            if t == 300 {
                rec.clock = Some(realm_core::field_boss_window(fid, 3).0 - 2);
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
            pack_reserving(&[(t, &bytes)], 0, &mut dgrams);
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
        assert!(server.boss().is_some(), "the clock raised the field boss");
        assert!(follower.unwrap().0.boss().is_some());
    }

    #[test]
    fn a_seq_head_fits_in_front_of_full_datagrams() {
        let big: Vec<u8> = (0..5000u32).map(|i| (i * 7) as u8).collect();
        let small = vec![9u8; 300];
        let recs: Vec<(u32, &[u8])> = vec![(10, &small), (11, &big), (12, &small)];
        let seqs: Vec<u32> = (100..200).collect();
        let mut out = Vec::new();
        pack_reserving(&recs, seq_head_len(seqs.len()), &mut out);
        put_seq_head(10, &seqs, &mut out[0]);
        assert!(out.iter().all(|d| d.len() <= MAX_DATAGRAM));
        let (first, got, rest) = take_seq_head(&out[0]).expect("head");
        // Only the last SEQS_MAX seqs travel, so the first tick moves up with them.
        assert_eq!((first, got.len(), got[0]), (10 + 36, SEQS_MAX, 136));
        let mut asm = Assembler::default();
        asm.take(rest, 9).expect("rest is a 0x90 datagram");
        for d in &out[1..] {
            asm.take(d, 9).expect("datagram");
        }
        assert_eq!(asm.next(10), Some(small.clone()));
        assert_eq!(asm.next(11), Some(big));
        assert_eq!(asm.next(12), Some(small));
    }

    #[test]
    fn the_input_queue_uses_one_input_a_tick_in_seq_order() {
        let mut q = InputQueue::default();
        // Two INPUTs arrive in one tick (jitter), then none: still one a tick.
        q.take(1, &[3]);
        q.take(2, &[4, 3]);
        assert_eq!((q.next_tick(), q.seq), (3, 1));
        assert_eq!((q.next_tick(), q.seq), (4, 2));
        assert_eq!((q.next_tick(), q.seq), (4, 2), "nothing waiting: the last input holds");
        // INPUT 3 is lost; 4 repeats its move.
        q.take(4, &[6, 5, 4]);
        assert_eq!((q.next_tick(), q.seq), (5, 3));
        assert_eq!((q.next_tick(), q.seq), (6, 4));
        // A stale INPUT changes nothing.
        q.take(2, &[1]);
        assert_eq!((q.next_tick(), q.seq), (6, 4));
    }

    #[test]
    fn the_input_queue_drops_the_oldest_beyond_its_limit() {
        let mut q = InputQueue::default();
        for s in 1..=6u32 {
            q.take(s, &[s as u16 | INPUT_SKILL_BIT]);
        }
        assert_eq!(q.next_tick(), 4 | INPUT_SKILL_BIT);
        assert_eq!(q.seq, 4);
    }

    /// One run of a lossy link, `resend` or not: returns (bytes the server sent, ticks the client applied,
    /// the longest run of server ticks the client stood still after the join).
    fn run_link(resend: bool, one_way: u32, loss_pct: u64, total: u32) -> (u64, u32, u32) {
        let rec = |t: u32| -> Vec<u8> { (0..60u32).map(|i| (t.wrapping_mul(31) + i) as u8).collect() };
        let mut asm = Assembler::default();
        let mut rs = Resend::default();
        let mut rng = 12345u64;
        let lost = |rng: &mut u64| {
            *rng = rng.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            (*rng >> 33) % 100 < loss_pct
        };
        // (arrives at server tick, payload)
        let mut to_client: Vec<(u32, Vec<Vec<u8>>)> = Vec::new();
        let mut to_server: Vec<(u32, u32)> = Vec::new();
        let (mut ack_at_server, mut applied, mut bytes) = (0u32, 0u32, 0u64);
        let (mut still, mut worst) = (0u32, 0u32);
        for n in 1..=total {
            // The server hears the acknowledgements that arrive now.
            for &(_, a) in to_server.iter().filter(|(at, _)| *at <= n) {
                ack_at_server = ack_at_server.max(a);
            }
            to_server.retain(|(at, _)| *at > n);
            rs.on_ack(ack_at_server, n);
            let have = (ack_at_server + 1)..=n;
            let ticks: Vec<u32> = if resend { rs.pick(n, have) } else { have.collect() };
            let owned: Vec<Vec<u8>> = ticks.iter().map(|&t| rec(t)).collect();
            let recs: Vec<(u32, &[u8])> = ticks.iter().zip(&owned).map(|(&t, b)| (t, b.as_slice())).collect();
            let mut out = Vec::new();
            pack_reserving(&recs, 0, &mut out);
            bytes += out.iter().map(|d| d.len() as u64).sum::<u64>();
            if !lost(&mut rng) {
                to_client.push((n + one_way, out));
            }
            // The client takes what arrives now, applies what it can, and acknowledges.
            for (_, ds) in to_client.iter().filter(|(at, _)| *at <= n) {
                for d in ds {
                    asm.take(d, applied).unwrap();
                }
            }
            to_client.retain(|(at, _)| *at > n);
            let before = applied;
            while let Some(b) = asm.next(applied + 1) {
                assert_eq!(b, rec(applied + 1));
                applied += 1;
            }
            still = if applied > before { 0 } else { still + 1 };
            worst = worst.max(still);
            if !lost(&mut rng) {
                to_server.push((n + one_way, applied));
            }
        }
        (bytes, applied, worst)
    }

    #[test]
    fn a_tick_is_repeated_only_after_one_round_trip() {
        // 80 ms each way is 4 ticks each way; 5% of datagrams lost each way.
        let (old_bytes, old_applied, old_worst) = run_link(false, 4, 5, 600);
        let (new_bytes, new_applied, new_worst) = run_link(true, 4, 5, 600);
        println!("LINK old bytes={old_bytes} applied={old_applied} worst_stall={old_worst} new bytes={new_bytes} applied={new_applied} worst_stall={new_worst}");
        assert!(old_applied > 580 && new_applied > 580, "{old_applied} {new_applied}");
        assert!(new_bytes * 2 < old_bytes, "bytes {new_bytes} against {old_bytes}");
        // The price is one more round trip (rtt + slack ticks) on a lost record, not a stall without end.
        assert!(new_worst <= 4 + old_worst + 6, "stall {new_worst} against {old_worst}");
        // With no loss nothing is ever sent twice.
        let (clean_bytes, clean_applied, _) = run_link(true, 4, 0, 600);
        let (once, _, _) = run_link(false, 0, 0, 600);
        assert!(clean_applied > 590);
        assert!(clean_bytes < once * 11 / 10, "{clean_bytes} against {once}");
    }

    #[test]
    fn the_round_trip_is_learned_from_the_acknowledgements() {
        let mut rs = Resend::default();
        let mut now = 0;
        for t in 1..=40u32 {
            now += 1;
            assert_eq!(rs.pick(now, t..=t), vec![t]);
            // The ack of tick t comes 10 ticks later.
            if t > 10 {
                rs.on_ack(t - 10, now);
            }
        }
        assert!((9..=11).contains(&rs.rtt()), "rtt {}", rs.rtt());
        // Unacknowledged ticks are sent again only once rtt + slack ticks have gone by.
        let again = rs.pick(now + 1, 31..=40);
        assert!(again.is_empty(), "{again:?}");
        let again = rs.pick(now + rs.rtt() + RESEND_SLACK, 31..=40);
        assert_eq!(again.len(), 10);
    }

    const INPUT_SKILL_BIT: u16 = realm_core::IN_SKILL1;
}
