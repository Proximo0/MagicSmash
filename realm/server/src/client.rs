//! A protocol B client with no socket: a follower (HELLO proto 3) or a lockstep player (proto 4).
//!
//! The caller owns the socket and the clock: it sends `hello()` until `welcomed()`, hands every datagram
//! to `receive`, calls `apply` to run every tick that has fully arrived, and sends `input` 20 times a
//! second (the INPUT also acknowledges the ticks applied, which is what makes the server repeat lost ones).
//! `realm-loadtest` and the Godot module (`realm/godot`) both drive this.

use crate::lockstep::{take_seq_head, Assembler, Lockstep, TickRec, INPUT_REPEAT};
use crate::predict::Predictor;
use crate::{hello_ticket, input, input_seq, input_word, seal, welcome_mac, Rd, TicketKey, MSG_BYE, MSG_PLAYER_TICKS, MSG_STATE, MSG_TICKS, MSG_WELCOME, PROTO_BP};
use realm_core::{Field, Player};
use std::collections::{BTreeMap, VecDeque};
use std::time::{Duration, Instant};

/// What a client has seen and done, for counters and reports.
#[derive(Clone, Debug, Default)]
pub struct ClientStats {
    pub ticks_applied: u64,
    pub hash_ok: u64,
    pub hash_bad: u64,
    /// Time spent applying ticks (decode and simulate), in total and for the last tick.
    pub sim: Duration,
    pub sim_last: Duration,
    /// The state the client joined from: its tick and size in bytes.
    pub join_tick: u32,
    pub join_bytes: usize,
    /// The longest wall time between two applied ticks after the first: how long a loss stalled it.
    pub stall_max: Duration,
    /// Datagrams that did not parse.
    pub bad_datagrams: u64,
}

pub struct LockstepClient {
    proto: u32,
    class: u8,
    race: u8,
    ticket: u64,
    /// A ticketed player: the ticket's key (never sent: it keys the HELLO's proof, the WELCOME's check and every
    /// INPUT's and BYE's tag), this session's nonce, and the last counter sealed.
    key: Option<TicketKey>,
    nonce: u64,
    counter: u32,
    threads: usize,
    welcomed: bool,
    hero: Option<u16>,
    state_tick: u32,
    state: BTreeMap<u16, Vec<u8>>,
    game: Option<(Field, Lockstep)>,
    asm: Assembler,
    /// Seq of this player's input in force at each tick (from `0x92` heads), from the confirmed tick on.
    seq_at: BTreeMap<u32, u32>,
    pred: Predictor,
    /// This player's newest moves, newest first, repeated in each INPUT.
    recent: VecDeque<u16>,
    last_apply: Option<Instant>,
    pub stats: ClientStats,
}

impl LockstepClient {
    /// `proto` is `PROTO_B` (follow only) or `PROTO_BP` (a player of `class` and `race`). `threads` is
    /// the follower field's worker threads (never changes the result).
    pub fn new(proto: u32, class: u8, race: u8, threads: usize) -> LockstepClient {
        LockstepClient {
            proto,
            class,
            race,
            ticket: 0,
            key: None,
            nonce: 0,
            counter: 0,
            threads: threads.max(1),
            welcomed: false,
            hero: None,
            state_tick: 0,
            state: BTreeMap::new(),
            game: None,
            asm: Assembler::default(),
            seq_at: BTreeMap::new(),
            pred: Predictor::default(),
            recent: VecDeque::new(),
            last_apply: None,
            stats: ClientStats::default(),
        }
    }

    /// A lockstep player of a hero the gateway named: `ticket` and `key` are what `FIELD_TICKET` returned. The
    /// field host takes her sheet and outing from the store, so no class or race goes with it.
    pub fn with_ticket(ticket: u64, key: TicketKey, threads: usize) -> LockstepClient {
        let mut c = LockstepClient::new(PROTO_BP, 0, 0, threads);
        c.ticket = ticket;
        c.key = Some(key);
        // Any value this key has not proved before will do (the key is new for each admission); the clock makes it
        // differ between two clients given the same key by mistake.
        let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_nanos() as u64);
        c.nonce = key.tag(&[b"N", &t.to_le_bytes()]);
        c
    }

    pub fn hello(&self) -> Vec<u8> {
        hello_ticket(self.proto, self.class, self.race, self.ticket, self.key.as_ref().map(|k| (k, self.nonce)))
    }

    /// The BYE to send when leaving (sealed for a ticketed player).
    pub fn bye(&mut self) -> Vec<u8> {
        self.sealed(vec![MSG_BYE])
    }

    fn sealed(&mut self, msg: Vec<u8>) -> Vec<u8> {
        match self.key {
            Some(k) => {
                self.counter += 1;
                seal(&k, self.counter, &msg)
            }
            None => msg,
        }
    }

    /// True once the server has answered the HELLO.
    pub fn welcomed(&self) -> bool {
        self.welcomed
    }

    /// This player's id in the field (none for a follower).
    pub fn hero(&self) -> Option<u16> {
        self.hero
    }

    /// The field at the confirmed tick, once the join state has arrived.
    pub fn field(&self) -> Option<&Field> {
        self.game.as_ref().map(|(f, _)| f)
    }

    /// The last tick applied (0 before joining).
    pub fn tick(&self) -> u32 {
        self.field().map_or(0, |f| f.tick())
    }

    /// The hero at the confirmed tick.
    pub fn hero_player(&self) -> Option<&Player> {
        self.field()?.players().get(self.hero? as usize).filter(|p| p.present)
    }

    pub fn predictor(&self) -> &Predictor {
        &self.pred
    }

    /// Takes one datagram from the server; ticks wait for `apply`.
    pub fn receive(&mut self, b: &[u8]) {
        let ok = match b.first() {
            Some(&MSG_WELCOME) => self.take_welcome(&b[1..]),
            Some(&MSG_STATE) => self.take_state(b),
            Some(&MSG_TICKS) => self.asm.take(b, self.applied_or_state()),
            Some(&MSG_PLAYER_TICKS) => self.take_player_ticks(b),
            _ => None,
        };
        if ok.is_none() {
            self.stats.bad_datagrams += 1;
        }
    }

    fn applied_or_state(&self) -> u32 {
        self.game.as_ref().map_or(self.state_tick, |(f, _)| f.tick())
    }

    fn take_welcome(&mut self, b: &[u8]) -> Option<()> {
        let mut r = Rd::new(b);
        let id = r.u32()?;
        let tick = r.u32()?;
        // hz, width, height, then (to a ticketed player) the MAC over her nonce: without it, nothing changes.
        if let Some(k) = &self.key {
            r.bytes(10)?;
            if r.u64()? != welcome_mac(k, self.nonce, id, tick) {
                return None;
            }
        }
        self.welcomed = true;
        if self.proto == PROTO_BP && id != u32::MAX {
            self.hero = Some(id as u16);
        }
        Some(())
    }

    /// A join state part. A newer state than the field replaces it once complete (the server sends one
    /// again when a client fell too far behind to catch up from the repeated ticks).
    fn take_state(&mut self, b: &[u8]) -> Option<()> {
        let mut r = Rd::new(&b[1..]);
        let (tick, k, n) = (r.u32()?, r.u16()?, r.u16()?);
        if self.game.as_ref().is_some_and(|(f, _)| f.tick() >= tick) {
            return Some(());
        }
        if tick != self.state_tick {
            self.state.clear();
            self.state_tick = tick;
        }
        self.state.insert(k, b[9..].to_vec());
        if self.state.len() == n as usize {
            let all: Vec<u8> = std::mem::take(&mut self.state).into_values().flatten().collect();
            let game = Lockstep::from_state(&all, self.threads)?;
            self.stats.join_tick = tick;
            self.stats.join_bytes = all.len();
            self.game = Some(game);
            self.seq_at.retain(|&t, _| t >= tick);
            self.confirm();
        }
        Some(())
    }

    fn take_player_ticks(&mut self, b: &[u8]) -> Option<()> {
        let (first, seqs, rest) = take_seq_head(b)?;
        let from = self.applied_or_state();
        for (k, &s) in seqs.iter().enumerate() {
            let t = first + k as u32;
            if t >= from {
                self.seq_at.insert(t, s);
            }
        }
        self.asm.take(rest, from)
    }

    /// Applies every tick that has fully arrived, checking hashes; returns how many.
    pub fn apply(&mut self) -> u32 {
        let Some((f, l)) = self.game.as_mut() else {
            return 0;
        };
        let mut n = 0;
        let now = Instant::now();
        while let Some(bytes) = self.asm.next(f.tick() + 1) {
            let t0 = Instant::now();
            let Some(rec) = TickRec::decode(f.tick() + 1, &bytes) else {
                self.stats.bad_datagrams += 1;
                break;
            };
            if !l.apply(f, &rec, |_| {}) {
                self.stats.hash_bad += 1;
            }
            if let Some(h) = rec.hash {
                if f.hash() == h {
                    self.stats.hash_ok += 1;
                } else {
                    self.stats.hash_bad += 1;
                }
            }
            self.stats.sim_last = t0.elapsed();
            self.stats.sim += self.stats.sim_last;
            self.stats.ticks_applied += 1;
            n += 1;
        }
        if n > 0 {
            if let Some(last) = self.last_apply {
                self.stats.stall_max = self.stats.stall_max.max(now - last);
            }
            self.last_apply = Some(now);
            self.confirm();
        }
        n
    }

    /// Hands the confirmed hero and the seq in force at the confirmed tick to the predictor.
    fn confirm(&mut self) {
        let tick = self.tick();
        while self.seq_at.first_key_value().is_some_and(|(&t, _)| t < tick) {
            self.seq_at.pop_first();
        }
        let seq = self.seq_at.get(&tick).copied();
        let Some(p) = self.hero_player() else { return };
        let (x, y, alive) = (p.x, p.y, p.alive());
        let (Some((field, _)), Some(id)) = (&self.game, self.hero) else { return };
        // Before the first head the hero has used no input of ours yet.
        self.pred.confirm(x, y, alive, seq.unwrap_or(0), |x, y, mv| field.walk(id, x, y, mv));
    }

    /// The INPUT for this client's next tick when only byte 0 is used (direction 0..8, bit 4 skill 1, bit 7
    /// interact): see `input_word`.
    pub fn input(&mut self, mv: u8) -> Vec<u8> {
        self.input_word(mv as u16)
    }

    /// The INPUT for this client's next tick: both input bytes of rules section 1 (`realm_core::IN_*`, picks
    /// and potions in byte 1) as one word. A player's moves its predicted hero at once; a follower's only
    /// acknowledges. Send it 20 times a second; a pick or potion should be held for a few inputs, since the
    /// server uses one input a tick and may drop the oldest when the client runs ahead.
    pub fn input_word(&mut self, word: u16) -> Vec<u8> {
        // Acknowledge only a whole state: while it downloads the server keeps sending its parts.
        let ack = self.tick();
        if self.proto == PROTO_BP {
            let word = crate::wire::clean_input(word);
            let walker = self.game.as_ref().map(|g| &g.0).zip(self.hero);
            let seq = self.pred.push(word, |x, y, w| walker.map_or((x, y), |(f, id)| f.walk(id, x, y, w)));
            self.recent.push_front(word);
            self.recent.truncate(INPUT_REPEAT + 1);
            let d = input_seq(ack, seq, self.recent.make_contiguous());
            self.sealed(d)
        } else {
            let _ = input_word;
            self.sealed(input(ack, 0, 1))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lockstep::{pack_reserving, put_seq_head, seq_head_len, state_parts, Join, HASH_EVERY};
    use crate::{welcome, PROTO_B};
    use realm_core::{Config, FIELD};

    #[test]
    fn a_ticketed_client_proves_its_key_without_sending_it_and_believes_only_a_welcome_with_it() {
        let key = TicketKey([9; 16]);
        let mut other = key;
        other.0[15] ^= 0x80;
        let mut c = LockstepClient::with_ticket(77, key, 1);
        let hello = c.hello();
        assert!(!hello.windows(16).any(|w| w == key.0), "the key is not in the HELLO");
        let h = crate::parse_hello(&mut Rd::new(&hello[1..])).unwrap();
        assert!(crate::hello_proves(&key, &h) && !crate::hello_proves(&other, &h) && !crate::hello_proves(&TicketKey::default(), &h));
        let nonce = h.proof.unwrap().0;
        // A blind WELCOME (none, a wrong key, another nonce) changes nothing; hers does.
        for spoof in [welcome(3, 10, None), welcome(3, 10, Some((&other, nonce))), welcome(3, 10, Some((&key, nonce ^ 1)))] {
            c.receive(&spoof);
            assert!(!c.welcomed() && c.hero().is_none());
        }
        c.receive(&welcome(3, 10, Some((&key, nonce))));
        assert!(c.welcomed() && c.hero() == Some(3));
        // Her INPUTs and BYE are sealed, counters rising; a changed byte or another key fails to open.
        let a = c.input_word(1);
        let b = c.bye();
        let (na, body) = crate::unseal(&key, &a).unwrap();
        assert_eq!(crate::parse_input(&mut Rd::new(body)).map(|m| m.word), Some(1));
        let (nb, _) = crate::unseal(&key, &b).unwrap();
        assert!(nb > na);
        assert!(crate::unseal(&other, &a).is_none());
        let mut t = a.clone();
        t[6] ^= 1;
        assert!(crate::unseal(&key, &t).is_none());
    }

    /// A server in miniature: a field, the lockstep inputs, and every encoded record.
    struct Mini {
        field: Field,
        ls: Lockstep,
        recs: Vec<(u32, Vec<u8>)>,
        /// The realm clock for the next record (the host's `Sim::next_clock`).
        clock: Option<u64>,
    }

    impl Mini {
        fn new(monsters: u32) -> Mini {
            Mini { field: Field::new(5, Config { monsters, threads: 1 }), ls: Lockstep::default(), recs: Vec::new(), clock: None }
        }

        fn tick(&mut self, joins: Vec<Join>, want: &[u8]) {
            let mut rec = TickRec { tick: self.field.tick() + 1, joins, clock: self.clock.take(), ..TickRec::default() };
            let want: Vec<u16> = want.iter().map(|&mv| mv as u16).collect();
            rec.changes = self.ls.changes(&rec, &want);
            assert!(self.ls.apply(&mut self.field, &rec, |_| {}));
            if rec.tick % HASH_EVERY == 0 {
                rec.hash = Some(self.field.hash());
            }
            let mut b = Vec::new();
            rec.encode(&mut b);
            self.recs.push((rec.tick, b));
        }

        /// The datagrams for a client that acknowledged `ack`, with a seq head when `seqs` is given.
        fn send(&self, ack: u32, seqs: Option<&[(u32, u32)]>) -> Vec<Vec<u8>> {
            let recs: Vec<(u32, &[u8])> = self.recs.iter().filter(|(t, _)| *t > ack).map(|(t, b)| (*t, b.as_slice())).collect();
            let mut out = Vec::new();
            match seqs {
                Some(s) => {
                    let s: Vec<u32> = s.iter().filter(|(t, _)| *t > ack).map(|&(_, q)| q).collect();
                    pack_reserving(&recs, seq_head_len(s.len()), &mut out);
                    put_seq_head(ack + 1, &s, &mut out[0]);
                }
                None => pack_reserving(&recs, 0, &mut out),
            }
            out
        }
    }

    #[test]
    fn a_follower_joins_from_the_state_and_matches_every_hash() {
        let mut m = Mini::new(1500);
        let bots: Vec<Join> = (0..12u16).map(|k| Join::bench(k, (k % 5) as u8, (k % 4) as u8, 1 + k as u8 * 4, FIELD / 2 + k as i32 * 9000, FIELD / 2)).collect();
        m.tick(bots, &[]);
        let want = |t: u32| -> Vec<u8> { (0..12u32).map(|i| ((i + t / 9) % 9) as u8).collect() };
        for t in 2..=30 {
            m.tick(Vec::new(), &want(t));
        }
        let mut c = LockstepClient::new(PROTO_B, 0, 0, 1);
        c.receive(&welcome(u32::MAX, 30, None));
        assert!(c.welcomed() && c.hero().is_none());
        for p in state_parts(30, &m.ls.state_bytes(&m.field)) {
            c.receive(&p);
        }
        assert_eq!(c.tick(), 30);
        for t in 31..=200 {
            m.tick(Vec::new(), &want(t));
            // Every third send is lost; the next one repeats what was not acknowledged.
            if t % 3 != 0 {
                for d in m.send(c.tick(), None) {
                    c.receive(&d);
                }
            }
            c.apply();
        }
        assert_eq!(c.tick(), 200);
        assert_eq!(c.stats.hash_bad, 0);
        assert_eq!(c.stats.hash_ok, 9);
        assert_eq!(c.stats.bad_datagrams, 0);
        assert_eq!(c.field().map(|f| f.hash()), Some(m.field.hash()));
    }

    #[test]
    fn a_player_predicts_its_hero_from_the_seq_heads() {
        // No monsters: nothing may kill the hero, which would rightly break the prediction.
        let mut m = Mini::new(0);
        m.tick(vec![Join::bench(0, 1, 2, 1, FIELD / 2, FIELD / 2)], &[]);
        let mut c = LockstepClient::new(PROTO_BP, 1, 2, 1);
        c.receive(&welcome(0, 1, None));
        assert_eq!(c.hero(), Some(0));
        for p in state_parts(1, &m.ls.state_bytes(&m.field)) {
            c.receive(&p);
        }
        // The server uses each input two ticks after it was sent.
        let mut seqs: Vec<(u32, u32)> = Vec::new();
        let mut sent: Vec<(u32, u8)> = Vec::new();
        for t in 2..=120u32 {
            let mv = 1 + (t / 10 % 8) as u8;
            let d = c.input(mv);
            let seq = Rd::new(&d[8..]).u32().unwrap_or(0);
            sent.push((seq, mv));
            let (s, inp) = if sent.len() > 2 { sent[sent.len() - 3] } else { (0, 0) };
            m.tick(Vec::new(), &[inp]);
            seqs.push((t, s));
            for d in m.send(c.tick(), Some(&seqs)) {
                c.receive(&d);
            }
            c.apply();
            let hero = c.hero_player().map(|p| (p.x, p.y));
            assert_eq!(hero, Some((m.field.players()[0].x, m.field.players()[0].y)));
        }
        let p = c.predictor();
        assert_eq!(c.stats.hash_bad, 0);
        assert!(p.confirms > 100, "{} confirms", p.confirms);
        assert_eq!(p.mispredicts, 0);
        assert_eq!(p.unconfirmed(), 2);
    }

    /// A follower's field moves only by the records. A boss the host summons outside them (a host-side call after
    /// its tick) never reaches a hero already in the field: no monster to draw, and the hashes part. A boss the
    /// realm clock raises (the clock rides in the record) rises on her copy in the same tick, and a hero who
    /// joins while it is up gets it in the state.
    #[test]
    fn a_boss_reaches_a_follower_through_the_record_or_the_state_and_no_other_way() {
        let follow = |m: &Mini, c: &mut LockstepClient| {
            for d in m.send(c.tick(), None) {
                c.receive(&d);
            }
            c.apply();
        };
        let fid = 1;
        let mut m = Mini::new(300);
        m.field = Field::open(fid, 5, Config { monsters: 300, threads: 1 });
        m.tick(vec![Join::bench(0, 1, 0, 1, FIELD / 2, FIELD / 2)], &[]);
        let mut c = LockstepClient::new(PROTO_B, 0, 0, 1);
        c.receive(&welcome(u32::MAX, 1, None));
        for p in state_parts(1, &m.ls.state_bytes(&m.field)) {
            c.receive(&p);
        }
        // Host side only: the summon is not in any record.
        m.tick(Vec::new(), &[0]);
        m.field.summon_boss(realm_core::tables::B_HANGING_TREE, 2_000_000, FIELD / 2 + 90 * realm_core::SUB, FIELD / 2);
        for _ in 0..HASH_EVERY {
            m.tick(Vec::new(), &[0]);
        }
        follow(&m, &mut c);
        assert_eq!(c.tick(), m.field.tick());
        assert!(m.field.boss().is_some() && c.field().unwrap().boss().is_none(), "the summon stays on the host");
        assert!(c.stats.hash_bad > 0, "and the hashes part");
        // The clock in the record: the field's boss rises on both copies.
        let mut m = Mini::new(300);
        m.field = Field::open(fid, 5, Config { monsters: 300, threads: 1 });
        m.tick(vec![Join::bench(0, 1, 0, 1, FIELD / 2, FIELD / 2)], &[]);
        let mut c = LockstepClient::new(PROTO_B, 0, 0, 1);
        c.receive(&welcome(u32::MAX, 1, None));
        for p in state_parts(1, &m.ls.state_bytes(&m.field)) {
            c.receive(&p);
        }
        m.clock = Some(realm_core::field_boss_window(fid, 3).0 - 2);
        for _ in 0..2 * HASH_EVERY {
            m.tick(Vec::new(), &[0]);
            follow(&m, &mut c);
        }
        let up = m.field.boss().cloned().expect("the clock raised the boss");
        assert_eq!(up.which, realm_core::tables::field_boss_of(fid, 0));
        assert_eq!(c.field().unwrap().boss(), Some(&up));
        assert_eq!(c.field().unwrap().boss_pos(), m.field.boss_pos());
        assert_eq!((c.stats.hash_bad, c.stats.hash_ok), (0, 2));
        // A hero who joins while it is up.
        let mut late = LockstepClient::new(PROTO_B, 0, 0, 1);
        let t = m.field.tick();
        late.receive(&welcome(u32::MAX, t, None));
        for p in state_parts(t, &m.ls.state_bytes(&m.field)) {
            late.receive(&p);
        }
        assert_eq!(late.field().and_then(|f| f.boss()), Some(&up));
        m.tick(Vec::new(), &[0]);
        follow(&m, &mut late);
        assert_eq!(late.field().map(|f| (f.hash(), f.boss_pos())), Some((m.field.hash(), m.field.boss_pos())));
    }
}
