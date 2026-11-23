//! Seeded fuzz of the server's network decoders (`WIRE_FUZZ_ITERS`, default 20000; `WIRE_FUZZ_SEED`): HELLO and
//! INPUT, tick records (with their PvP block of GUILD and WAR entries, job R3b), the `0x92` head, the tick datagram assembler, snapshots, and a join state. Each must refuse or
//! decode, never panic and never allocate much more than the bytes it was given; valid messages must round trip.

use crate::lockstep::{pack_reserving, put_seq_head, state_parts, take_seq_head, Assembler, Join, Lockstep, TickRec, WarArm};
use crate::probe::{biggest, iters, mutate, reset, seed, Rng};
use crate::snap::{decode, encode_v0, encode_v1};
use crate::view::{MRec, PRec, View};
use crate::{hello_ticket, input_seq, parse_hello, parse_input, Rd, MAX_DATAGRAM};
use realm_core::{Config, Field};

fn cap(n: usize) -> usize {
    64 * n + 16 * 1024
}

/// Mangle a message, or make noise.
fn hostile(rng: &mut Rng, good: &[u8]) -> Vec<u8> {
    match rng.below(5) {
        0 => rng.bytes(64),
        _ => mutate(rng, good),
    }
}

fn within(what: &str, bad: &[u8]) {
    assert!(biggest() <= cap(bad.len()), "{what}: {} bytes made a decoder ask for {} at once: {bad:02x?}", bad.len(), biggest());
}

#[test]
fn hello_and_input_round_trip_and_survive_hostile_bytes() {
    let mut rng = Rng(seed());
    for _ in 0..iters() {
        let (c, r, t) = (rng.next() as u8, rng.next() as u8, rng.next());
        let h = hello_ticket(rng.next() as u32, c, r, t, None);
        let mut rd = Rd::new(&h[1..]);
        assert_eq!(parse_hello(&mut rd).map(|x| (x.class, x.race, x.ticket)), Some((c, r, t)));
        let words: Vec<u16> = (0..1 + rng.below(4)).map(|_| rng.next() as u16 & 0x07FF).collect();
        let seq = rng.next() as u32;
        let i = input_seq(rng.next() as u32, seq, &words);
        let m = parse_input(&mut Rd::new(&i[1..])).expect("a valid input parses");
        assert_eq!(m.seq_words.as_ref().map(|s| s.0), Some(seq));
        assert_eq!(m.seq_words.unwrap().1.len(), words.len());
        for good in [&h, &i] {
            let bad = hostile(&mut rng, &good[1..]);
            reset();
            let _ = parse_hello(&mut Rd::new(&bad));
            let _ = parse_input(&mut Rd::new(&bad));
            within("hello/input", &bad);
        }
    }
}

fn rec(rng: &mut Rng, tick: u32) -> TickRec {
    let mut t = TickRec { tick, ..TickRec::default() };
    for k in 0..rng.below(3) {
        t.joins.push(Join::bench(k as u16, rng.below(5) as u8, rng.below(4) as u8, 1 + rng.below(40) as u8, rng.next() as i32 >> 8, rng.next() as i32 >> 8));
    }
    t.leaves = (0..rng.below(4)).map(|_| rng.next() as u16).collect();
    let mut slot = 0u16;
    for _ in 0..rng.below(6) {
        slot = slot.saturating_add(rng.below(300) as u16);
        t.changes.push((slot, rng.next() as u16));
    }
    t.hash = (rng.below(2) == 1).then(|| rng.next());
    t.clock = (rng.below(2) == 1).then(|| rng.next());
    // Job R3b: the PvP block, a GUILD entry for some joins and a few WAR entries.
    for j in t.joins.iter_mut() {
        if rng.below(2) == 1 {
            j.guild = 1 + (rng.next() >> 1);
        }
    }
    for _ in 0..rng.below(3) {
        t.wars.push(WarArm { id: rng.next(), a: rng.next(), b: rng.next(), tide: rng.next() as u32 });
    }
    t
}

#[test]
fn tick_records_and_the_datagram_layers_survive_hostile_bytes() {
    let mut rng = Rng(seed() ^ 1);
    for n in 0..iters() {
        let t = rec(&mut rng, n as u32 + 1);
        let mut w = Vec::new();
        t.encode(&mut w);
        assert_eq!(TickRec::decode(t.tick, &w).as_ref(), Some(&t));
        let bad = hostile(&mut rng, &w);
        reset();
        let _ = TickRec::decode(1, &bad);
        within("TickRec", &bad);

        // 0x90 datagrams, with a head on some.
        let mut out = Vec::new();
        pack_reserving(&[(t.tick, &w)], 0, &mut out);
        let mut asm = Assembler::default();
        for d in &out {
            asm.take(d, 0).expect("a valid datagram");
        }
        assert_eq!(asm.next(t.tick).as_deref(), Some(&w[..]));
        let seqs: Vec<u32> = (0..rng.below(5)).map(|_| rng.next() as u32).collect();
        let mut head = out[0].clone();
        put_seq_head(t.tick, &seqs, &mut head);
        let (f, s, rest) = take_seq_head(&head).expect("a valid head");
        assert_eq!((f, &s, rest), (t.tick, &seqs, &out[0][..]));
        for good in [&head, &out[0]] {
            let bad = hostile(&mut rng, good);
            reset();
            let _ = take_seq_head(&bad);
            let mut asm = Assembler::default();
            let _ = asm.take(&bad, rng.below(4) as u32);
            let _ = asm.next(1);
            within("datagram", &bad);
        }
    }
}

fn view(rng: &mut Rng) -> View {
    // Invariant (view::build): the origin is clamped into the field, 0 <= ox, oy < FIELD_PX, so a monster's
    // world px never wraps a u16, and every monster is inside the box, ox <= x < ox + w and oy <= y < oy + h
    // with w, h at most 2 048 and 1 208: the 12 and 11 bits of a full monster always hold its offset.
    let fp = realm_core::FIELD_PX as usize;
    let mut v = View { tick: 1 + rng.below(1000) as u32, ox: rng.below(fp) as i32, oy: rng.below(fp) as i32, me_x: rng.below(2000) as u16, me_y: rng.below(2000) as u16, health: rng.next() as u16, level: rng.below(60) as u16, field_players: rng.below(500) as u32, field_monsters: rng.below(9000) as u32, tick_time: rng.next() as u16, ..View::default() };
    let mut id = 0u16;
    for _ in 0..rng.below(8) {
        id = id.saturating_add(1 + rng.below(40) as u16);
        v.players.push(PRec { id, x: rng.next() as u16, y: rng.next() as u16, cr: rng.below(32) as u8, flags: rng.below(8) as u8 });
    }
    v.crowd = (0..rng.below(8)).map(|_| (rng.next() as u16, rng.next() as u16)).collect();
    // (a monster is packed as 12 and 11 bits from the view's origin, so it stands near it)
    let mut id = 0u32;
    for _ in 0..rng.below(12) {
        id += 1 + rng.below(50) as u32;
        v.monsters.push(MRec { id, x: (v.ox + rng.below(4000) as i32) as u16, y: (v.oy + rng.below(2000) as i32) as u16, attrs: rng.next() as u8 & 0x7F, hurt: rng.below(2) == 1 });
    }
    v
}

#[test]
fn snapshots_round_trip_and_survive_hostile_parts() {
    let mut rng = Rng(seed() ^ 2);
    for _ in 0..iters() {
        let v = view(&mut rng);
        let mut parts = Vec::new();
        encode_v0(&v, &mut parts);
        assert_eq!(decode(&parts, None).as_ref(), Ok(&v));
        let mut p1 = Vec::new();
        encode_v1(&v, None, &mut p1);
        assert_eq!(decode(&p1, None).as_ref(), Ok(&v));
        // A v1 against a base, decoded against a (maybe wrong) base.
        // (a delta carries at most 8 px a tick, so the next view is the last one nudged; a nudged monster stays
        // inside the window from the origin, as `build` keeps it: it never goes above oy, x stays below ox + 4 096)
        let mut v2 = v.clone();
        v2.tick = v.tick + 1;
        for m in v2.monsters.iter_mut() {
            m.x += rng.below(8) as u16;
            m.y -= (rng.below(8) as u16).min(m.y - v.oy as u16);
        }
        for p in v2.players.iter_mut() {
            p.x = p.x.wrapping_add(rng.below(8) as u16);
            p.flags = rng.below(8) as u8;
        }
        if rng.below(2) == 1 {
            v2.monsters.pop();
        }
        let mut p2 = Vec::new();
        encode_v1(&v2, Some(&v), &mut p2);
        assert_eq!(decode(&p2, Some(&v)).as_ref(), Ok(&v2));
        for set in [&parts, &p1, &p2] {
            let mut bad: Vec<Vec<u8>> = set.clone();
            let k = rng.below(bad.len());
            bad[k] = hostile(&mut rng, &set[k]);
            if rng.below(8) == 0 {
                bad.truncate(rng.below(bad.len() + 1));
            }
            let total: usize = bad.iter().map(Vec::len).sum();
            reset();
            let _ = decode(&bad, Some(&v));
            let _ = decode(&bad, None);
            assert!(biggest() <= cap(total), "snapshot of {total} bytes made decode ask for {}", biggest());
        }
        assert!(parts.iter().all(|p| p.len() <= MAX_DATAGRAM));
    }
}

#[test]
fn a_join_state_round_trips_and_survives_hostile_bytes() {
    let mut rng = Rng(seed() ^ 3);
    let mut f = Field::new(4, Config { monsters: 40, threads: 1 });
    f.join(&realm_core::Sheet::bench(1, 1, 5), &realm_core::Outing::new(), 1000, 1000);
    let ls = Lockstep { inputs: vec![0, 3, 5] };
    let good = ls.state_bytes(&f);
    let (g, l) = Lockstep::from_state(&good, 1).expect("a state reads back");
    assert_eq!((l.inputs, g.to_bytes()), (ls.inputs.clone(), f.to_bytes()));
    // The parts the join sends are the same bytes cut up.
    assert_eq!(state_parts(7, &good).iter().map(|p| p.len() - 9).sum::<usize>(), good.len());
    reset();
    let _ = Lockstep::from_state(&good, 1);
    let fixed = biggest();
    for _ in 0..(iters() / 200).max(100) {
        let bad = hostile(&mut rng, &good);
        reset();
        let _ = Lockstep::from_state(&bad, 1);
        assert!(biggest() <= fixed + cap(bad.len()), "{} bytes made from_state ask for {} (a good one asks {fixed})", bad.len(), biggest());
    }
}
