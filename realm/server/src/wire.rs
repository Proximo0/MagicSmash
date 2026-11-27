//! The hero on the wire: her `Sheet` and her `Outing` as the join record of protocol B carries them, and the
//! two-byte input (rules section 1).
//!
//! Sheet: `u8 class, job, race, class level, gear level`, `6 x u16 points`, `6 x u16 gear`, `u8 n deck, n x u8`,
//! `3 x (u8 potion, u8 charges)`, `u32 look`. Outing: `u8 0` (a fresh entry) or `u8 1` and every field in the
//! order of the struct (see `put_outing`).

use crate::{put_u16, put_u32, Rd};
use realm_core::tables::{BELT, DECK_SIZE, DRAW_MAX, NCARDS, NFX, RACES, CLASSES};
use realm_core::{Outing, Sheet};

/// Input byte 0 is the direction, skill 1, skill 2, the ultimate and interact; byte 1 the pick and potions.
/// The word is `byte0 | byte1 << 8`, the core's `input`.
pub const fn word_of(byte0: u8, byte1: u8) -> u16 {
    realm_core::input(byte0, byte1)
}

/// Clears the bits rules section 1 says are zero (byte 1 bits 6 and 7), and a pick of 5..7.
pub fn clean_input(w: u16) -> u16 {
    let mut w = w & 0x3FFF;
    if (w & realm_core::IN_PICK) >> realm_core::IN_PICK_SHIFT > 4 {
        w &= !realm_core::IN_PICK;
    }
    w
}

pub fn put_sheet(w: &mut Vec<u8>, s: &Sheet) {
    w.extend_from_slice(&[s.class, s.job, s.race, s.class_level, s.gear_level]);
    for v in s.points.iter().chain(s.gear.iter()) {
        put_u16(w, *v);
    }
    w.push(s.deck.len().min(DECK_SIZE) as u8);
    w.extend_from_slice(&s.deck[..s.deck.len().min(DECK_SIZE)]);
    for (p, n) in s.belt {
        w.push(p);
        w.push(n);
    }
    put_u32(w, s.look);
}

pub fn read_sheet(r: &mut Rd) -> Option<Sheet> {
    let (class, job, race, class_level, gear_level) = (r.u8()?, r.u8()?, r.u8()?, r.u8()?, r.u8()?);
    if class as usize >= CLASSES.len() || race as usize >= RACES.len() {
        return None;
    }
    let mut points = [0u16; 6];
    let mut gear = [0u16; 6];
    for v in points.iter_mut().chain(gear.iter_mut()) {
        *v = r.u16()?;
    }
    let n = r.u8()? as usize;
    if n > DECK_SIZE {
        return None;
    }
    let deck = r.bytes(n)?.to_vec();
    let mut belt = [(0u8, 0u8); BELT];
    for s in belt.iter_mut() {
        *s = (r.u8()?, r.u8()?);
    }
    let look = r.u32()?;
    Some(Sheet { class, job, race, class_level, points, gear, gear_level, deck, belt, look })
}

pub fn put_outing(w: &mut Vec<u8>, o: &Outing) {
    if *o == Outing::new() {
        w.push(0);
        return;
    }
    w.push(1);
    put_u32(w, o.health.map_or(u32::MAX, |h| h.min(u32::MAX - 1)));
    put_u16(w, o.level);
    put_u32(w, o.xp);
    w.extend_from_slice(&o.copies);
    w.push(o.offers.len() as u8);
    for off in &o.offers {
        w.extend_from_slice(off);
    }
    put_u16(w, o.owed);
    put_u32(w, o.draws);
    put_u32(w, o.coin);
    for c in o.cooldowns {
        put_u32(w, c);
    }
    match o.belt {
        Some(b) => {
            w.push(1);
            for (p, n) in b {
                w.push(p);
                w.push(n);
            }
        }
        None => w.push(0),
    }
    for t in o.belt_rest {
        put_u16(w, t);
    }
    w.push(o.phoenix_used as u8);
    for t in o.fx {
        put_u16(w, t);
    }
    w.push(o.waystone);
    w.push(o.marked as u8);
    put_u32(w, o.struck_ago);
    w.push(o.shrines);
}

pub fn read_outing(r: &mut Rd) -> Option<Outing> {
    if r.u8()? == 0 {
        return Some(Outing::new());
    }
    let mut o = Outing::new();
    let h = r.u32()?;
    o.health = (h != u32::MAX).then_some(h);
    o.level = r.u16()?;
    o.xp = r.u32()?;
    o.copies.copy_from_slice(r.bytes(NCARDS + 1)?);
    for _ in 0..r.u8()? {
        let mut off = [0u8; DRAW_MAX as usize];
        off.copy_from_slice(r.bytes(DRAW_MAX as usize)?);
        o.offers.push(off);
    }
    o.owed = r.u16()?;
    o.draws = r.u32()?;
    o.coin = r.u32()?;
    for c in o.cooldowns.iter_mut() {
        *c = r.u32()?;
    }
    if r.u8()? == 1 {
        let mut b = [(0u8, 0u8); BELT];
        for s in b.iter_mut() {
            *s = (r.u8()?, r.u8()?);
        }
        o.belt = Some(b);
    }
    for t in o.belt_rest.iter_mut() {
        *t = r.u16()?;
    }
    o.phoenix_used = r.u8()? != 0;
    for t in o.fx.iter_mut() {
        *t = r.u16()?;
    }
    let _ = NFX;
    o.waystone = r.u8()?;
    o.marked = r.u8()? != 0;
    o.struck_ago = r.u32()?;
    o.shrines = r.u8()?;
    Some(o)
}

#[cfg(test)]
mod tests {
    use super::*;
    use realm_core::tables::*;

    #[test]
    fn a_sheet_and_an_outing_survive_the_wire() {
        for class in 0..8u8 {
            let s = Sheet::bench(class, class % 4, 1 + class * 8);
            let mut w = Vec::new();
            put_sheet(&mut w, &s);
            let mut r = Rd::new(&w);
            assert_eq!(read_sheet(&mut r), Some(s));
            assert_eq!(r.left(), 0);
        }
        let mut o = Outing::new();
        let mut w = Vec::new();
        put_outing(&mut w, &o);
        assert_eq!(w, [0], "a fresh entry is one byte");
        o.health = Some(77);
        o.level = 9;
        o.xp = 1234;
        o.copies[3] = 2;
        o.offers.push([1, 2, 3, 4]);
        o.coin = 500;
        o.cooldowns = [5, 6, 7];
        o.belt = Some([(P_HEALING, 2), (P_NONE, 0), (P_PHOENIX, 1)]);
        o.fx[2] = 40;
        o.waystone = 3;
        o.struck_ago = 12;
        w.clear();
        put_outing(&mut w, &o);
        let mut r = Rd::new(&w);
        assert_eq!(read_outing(&mut r), Some(o));
        assert_eq!(r.left(), 0);
        // Cut short, it fails soft.
        assert!(read_outing(&mut Rd::new(&w[..w.len() - 1])).is_none());
    }

    #[test]
    fn the_input_word_keeps_both_bytes_and_drops_the_spare_bits() {
        let w = word_of(realm_core::IN_SKILL2 as u8 | 3, 0x0B);
        assert_eq!(w & realm_core::IN_DIR, 3);
        assert_ne!(w & realm_core::IN_SKILL2, 0);
        assert_eq!(clean_input(w), w);
        assert_eq!(clean_input(0xC000 | 5), 5);
        assert_eq!(clean_input(0x0700), 0, "a pick of 7 is no pick");
        assert_eq!(clean_input(0x0400), 0x0400);
    }
}
