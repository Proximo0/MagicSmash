//! Protocol A snapshots: version 0 exactly as the contract writes it, and version 1 (changes against the
//! last snapshot the client acknowledged). Both split into parts of at most `MAX_DATAGRAM` bytes.
//!
//! Version 1 (this job's choice), message `0x83`: `u32 tick, u8 part, u8 parts, u32 base tick` (0: none),
//! part 0's header as v0, then per part `u16 n players, u16 n crowd, u16 n monsters` and the lists:
//! - players and monsters by id, each `varint(id gap << 2 | mode)` then by mode:
//!   - monster: 0 same as base; 1 one byte of world-px change (dx + 8 | (dy + 8) << 4); 2 the v0 4 bytes;
//!     3 the change byte and an attrs byte (v0 4th byte, hurt in bit 7);
//!   - player: 0 same as base; 1 the change byte and the flags byte; 2 `u16 dx, u16 dy, u8 class | race << 3,
//!     u8 flags`; 3 the change byte only;
//! - crowd as v0.
//!
//! A listed id with a non-full mode takes the rest from the base; a base entry not listed is gone.

use crate::view::{MRec, PRec, View};
use crate::{put_i32, put_u16, put_u32, put_varint, Rd, MAX_DATAGRAM, MSG_SNAPSHOT, MSG_SNAPSHOT_V1};

const SECT_PLAYERS: usize = 0;
const SECT_CROWD: usize = 1;
const SECT_MONSTERS: usize = 2;

struct Parts<'a> {
    out: &'a mut Vec<Vec<u8>>,
    cur: Vec<u8>,
    counts_at: usize,
    n: [u16; 3],
    prev: [u32; 3],
    tag: u8,
    tick: u32,
    base_tick: Option<u32>,
    tmp: Vec<u8>,
}

impl Parts<'_> {
    fn open(&mut self, v: Option<&View>) {
        let mut b = Vec::with_capacity(MAX_DATAGRAM);
        b.push(self.tag);
        put_u32(&mut b, self.tick);
        b.push(self.out.len() as u8);
        b.push(0);
        if let Some(bt) = self.base_tick {
            put_u32(&mut b, bt);
        }
        if let Some(v) = v {
            put_i32(&mut b, v.ox);
            put_i32(&mut b, v.oy);
            put_u16(&mut b, v.me_x);
            put_u16(&mut b, v.me_y);
            put_u16(&mut b, v.health);
            put_u16(&mut b, v.level);
            put_u32(&mut b, v.field_players);
            put_u32(&mut b, v.field_monsters);
            put_u16(&mut b, v.tick_time);
        }
        self.counts_at = b.len();
        b.extend_from_slice(&[0; 6]);
        self.cur = b;
        self.n = [0; 3];
        self.prev = [0; 3];
    }

    fn close(&mut self) {
        let mut b = std::mem::take(&mut self.cur);
        for (k, n) in self.n.iter().enumerate() {
            b[self.counts_at + 2 * k..self.counts_at + 2 * k + 2].copy_from_slice(&n.to_le_bytes());
        }
        self.out.push(b);
    }

    /// Adds an item; `enc(prev id in this section and part, buffer)` writes it.
    fn add(&mut self, sect: usize, id: u32, enc: impl Fn(u32, &mut Vec<u8>)) {
        self.tmp.clear();
        enc(self.prev[sect], &mut self.tmp);
        if self.cur.len() + self.tmp.len() > MAX_DATAGRAM {
            self.close();
            self.open(None);
            self.tmp.clear();
            enc(0, &mut self.tmp);
        }
        self.cur.extend_from_slice(&self.tmp);
        self.n[sect] += 1;
        self.prev[sect] = id;
    }

    fn finish(mut self) {
        self.close();
        let parts = self.out.len() as u8;
        for b in self.out.iter_mut() {
            b[6] = parts;
        }
    }
}

/// A full monster is 12 and 11 bits from the view's origin; `view::build` only sends monsters inside its box
/// (at most 2 048 by 1 208 px), so an offset outside that window is a bug upstream that would decode elsewhere.
fn mon_v0(m: &MRec, v: &View, w: &mut Vec<u8>) {
    debug_assert!(
        (0..0x1000).contains(&(m.x as i32 - v.ox)) && (0..0x800).contains(&(m.y as i32 - v.oy)),
        "monster {} at ({}, {}) is outside the 12/11-bit window from origin ({}, {})",
        m.id,
        m.x,
        m.y,
        v.ox,
        v.oy
    );
    let dx = (m.x as i32 - v.ox) as u32 & 0xFFF;
    let dy = (m.y as i32 - v.oy) as u32 & 0x7FF;
    let packed = dx | dy << 12 | (m.hurt as u32) << 23;
    w.extend_from_slice(&packed.to_le_bytes()[..3]);
    w.push(m.attrs);
}

/// Version 0 parts for a view.
pub fn encode_v0(v: &View, out: &mut Vec<Vec<u8>>) {
    out.clear();
    let mut p = Parts { out, cur: Vec::new(), counts_at: 0, n: [0; 3], prev: [0; 3], tag: MSG_SNAPSHOT, tick: v.tick, base_tick: None, tmp: Vec::new() };
    p.open(Some(v));
    for q in &v.players {
        p.add(SECT_PLAYERS, q.id as u32, |_, w| {
            put_u16(w, q.id);
            put_u16(w, (q.x as i32 - v.ox) as u16);
            put_u16(w, (q.y as i32 - v.oy) as u16);
            w.push(q.cr);
            w.push(q.flags);
        });
    }
    for &(x, y) in &v.crowd {
        p.add(SECT_CROWD, 0, |_, w| {
            put_u16(w, (x as i32 - v.ox) as u16);
            put_u16(w, (y as i32 - v.oy) as u16);
        });
    }
    for m in &v.monsters {
        p.add(SECT_MONSTERS, m.id, |prev, w| {
            put_varint(w, m.id - prev);
            mon_v0(m, v, w);
        });
    }
    p.finish();
}

fn small(d: i32) -> bool {
    (-8..=7).contains(&d)
}

fn delta_byte(dx: i32, dy: i32) -> u8 {
    ((dx + 8) as u8) | ((dy + 8) as u8) << 4
}

/// Version 1 parts: `base` is the snapshot the client acknowledged, with its tick (None: send everything).
pub fn encode_v1(v: &View, base: Option<&View>, out: &mut Vec<Vec<u8>>) {
    out.clear();
    let base_tick = base.map_or(0, |b| b.tick);
    let mut p = Parts { out, cur: Vec::new(), counts_at: 0, n: [0; 3], prev: [0; 3], tag: MSG_SNAPSHOT_V1, tick: v.tick, base_tick: Some(base_tick), tmp: Vec::new() };
    p.open(Some(v));
    let empty = View::default();
    let b = base.unwrap_or(&empty);
    let mut j = 0;
    for q in &v.players {
        while j < b.players.len() && b.players[j].id < q.id {
            j += 1;
        }
        let old = b.players.get(j).filter(|o| o.id == q.id && o.cr == q.cr);
        p.add(SECT_PLAYERS, q.id as u32, |prev, w| {
            let gap = (q.id as u32 - prev) << 2;
            match old {
                Some(o) if small(q.x as i32 - o.x as i32) && small(q.y as i32 - o.y as i32) => {
                    let (dx, dy) = (q.x as i32 - o.x as i32, q.y as i32 - o.y as i32);
                    if o.flags == q.flags && dx == 0 && dy == 0 {
                        put_varint(w, gap);
                    } else if o.flags == q.flags {
                        put_varint(w, gap | 3);
                        w.push(delta_byte(dx, dy));
                    } else {
                        put_varint(w, gap | 1);
                        w.push(delta_byte(dx, dy));
                        w.push(q.flags);
                    }
                }
                _ => {
                    put_varint(w, gap | 2);
                    put_u16(w, (q.x as i32 - v.ox) as u16);
                    put_u16(w, (q.y as i32 - v.oy) as u16);
                    w.push(q.cr);
                    w.push(q.flags);
                }
            }
        });
    }
    for &(x, y) in &v.crowd {
        p.add(SECT_CROWD, 0, |_, w| {
            put_u16(w, (x as i32 - v.ox) as u16);
            put_u16(w, (y as i32 - v.oy) as u16);
        });
    }
    let mut j = 0;
    for m in &v.monsters {
        while j < b.monsters.len() && b.monsters[j].id < m.id {
            j += 1;
        }
        let old = b.monsters.get(j).filter(|o| o.id == m.id);
        p.add(SECT_MONSTERS, m.id, |prev, w| {
            let gap = (m.id - prev) << 2;
            match old {
                Some(o) if small(m.x as i32 - o.x as i32) && small(m.y as i32 - o.y as i32) => {
                    let (dx, dy) = (m.x as i32 - o.x as i32, m.y as i32 - o.y as i32);
                    let same = o.attrs == m.attrs && o.hurt == m.hurt;
                    if same && dx == 0 && dy == 0 {
                        put_varint(w, gap);
                    } else if same {
                        put_varint(w, gap | 1);
                        w.push(delta_byte(dx, dy));
                    } else {
                        put_varint(w, gap | 3);
                        w.push(delta_byte(dx, dy));
                        w.push(m.attrs | (m.hurt as u8) << 7);
                    }
                }
                _ => {
                    put_varint(w, gap | 2);
                    mon_v0(m, v, w);
                }
            }
        });
    }
    p.finish();
}

/// Tick, part, parts and (v1) base tick of a snapshot datagram.
pub fn peek(b: &[u8]) -> Option<(u8, u32, u8, u8, u32)> {
    let mut r = Rd::new(b);
    let tag = r.u8()?;
    let tick = r.u32()?;
    let part = r.u8()?;
    let parts = r.u8()?;
    let base = if tag == MSG_SNAPSHOT_V1 { r.u32()? } else { 0 };
    Some((tag, tick, part, parts, base))
}

/// Decodes all parts of one snapshot (any order) into a view in world px. `base` is the view the
/// v1 parts name as their base (ignored for v0).
pub fn decode(parts: &[Vec<u8>], base: Option<&View>) -> Result<View, String> {
    let mut v = View::default();
    let mut sorted: Vec<&Vec<u8>> = parts.iter().collect();
    sorted.sort_by_key(|b| b.get(5).copied().unwrap_or(0));
    let mut want = None;
    for (k, b) in sorted.iter().enumerate() {
        let (tag, tick, part, nparts, base_tick) = peek(b).ok_or("short header")?;
        if part as usize != k || nparts as usize != parts.len() {
            return Err(format!("part {part} of {nparts}, have {}", parts.len()));
        }
        let v1 = tag == MSG_SNAPSHOT_V1;
        if tag != MSG_SNAPSHOT && !v1 {
            return Err(format!("tag {tag:#x}"));
        }
        if *want.get_or_insert((tick, base_tick)) != (tick, base_tick) {
            return Err("parts disagree".into());
        }
        let b0 = if v1 && base_tick != 0 {
            let bv = base.ok_or("no base")?;
            if bv.tick != base_tick {
                return Err(format!("base {} is not {base_tick}", bv.tick));
            }
            Some(bv)
        } else {
            None
        };
        let mut r = Rd::new(b);
        r.at = if v1 { 11 } else { 7 };
        v.tick = tick;
        if k == 0 {
            v.ox = r.i32().ok_or("short")?;
            v.oy = r.i32().ok_or("short")?;
            v.me_x = r.u16().ok_or("short")?;
            v.me_y = r.u16().ok_or("short")?;
            v.health = r.u16().ok_or("short")?;
            v.level = r.u16().ok_or("short")?;
            v.field_players = r.u32().ok_or("short")?;
            v.field_monsters = r.u32().ok_or("short")?;
            v.tick_time = r.u16().ok_or("short")?;
        }
        decode_lists(&mut r, &mut v, v1, b0).ok_or_else(|| format!("bad lists in part {k}"))?;
        if r.left() != 0 {
            return Err(format!("{} bytes left in part {k}", r.left()));
        }
    }
    Ok(v)
}

fn undelta(o: (u16, u16), d: u8) -> (u16, u16) {
    ((o.0 as i32 + (d & 15) as i32 - 8) as u16, (o.1 as i32 + (d >> 4) as i32 - 8) as u16)
}

fn decode_lists(r: &mut Rd, v: &mut View, v1: bool, base: Option<&View>) -> Option<()> {
    let np = r.u16()?;
    let nc = r.u16()?;
    let nm = r.u16()?;
    let (ox, oy) = (v.ox, v.oy);
    let px = |d: u16, o: i32| (d as i32).wrapping_add(o) as u16;
    let mut prev = 0u32;
    for _ in 0..np {
        if !v1 {
            let id = r.u16()?;
            let (dx, dy) = (r.u16()?, r.u16()?);
            v.players.push(PRec { id, x: px(dx, ox), y: px(dy, oy), cr: r.u8()?, flags: r.u8()? });
            continue;
        }
        let g = r.varint()?;
        let id = prev.checked_add(g >> 2)?;
        prev = id;
        let rec = if g & 3 == 2 {
            let (dx, dy) = (r.u16()?, r.u16()?);
            PRec { id: id as u16, x: px(dx, ox), y: px(dy, oy), cr: r.u8()?, flags: r.u8()? }
        } else {
            let o = *base?.players.iter().find(|o| o.id as u32 == id)?;
            match g & 3 {
                0 => o,
                1 => {
                    let (x, y) = undelta((o.x, o.y), r.u8()?);
                    PRec { x, y, flags: r.u8()?, ..o }
                }
                _ => {
                    let (x, y) = undelta((o.x, o.y), r.u8()?);
                    PRec { x, y, ..o }
                }
            }
        };
        v.players.push(rec);
    }
    for _ in 0..nc {
        let (dx, dy) = (r.u16()?, r.u16()?);
        v.crowd.push((px(dx, ox), px(dy, oy)));
    }
    prev = 0;
    for _ in 0..nm {
        let g = r.varint()?;
        let (gap, mode) = if v1 { (g >> 2, g & 3) } else { (g, 2) };
        let id = prev.checked_add(gap)?;
        prev = id;
        let rec = if mode == 2 {
            let b = r.bytes(3)?;
            let packed = b[0] as u32 | (b[1] as u32) << 8 | (b[2] as u32) << 16;
            let attrs = r.u8()?;
            MRec { id, x: px((packed & 0xFFF) as u16, ox), y: px((packed >> 12 & 0x7FF) as u16, oy), attrs, hurt: packed >> 23 != 0 }
        } else {
            let bm = &base?.monsters;
            let o = bm[bm.binary_search_by_key(&id, |m| m.id).ok()?];
            match mode {
                0 => o,
                1 => {
                    let (x, y) = undelta((o.x, o.y), r.u8()?);
                    MRec { x, y, ..o }
                }
                _ => {
                    let (x, y) = undelta((o.x, o.y), r.u8()?);
                    let a = r.u8()?;
                    MRec { id, x, y, attrs: a & 0x7F, hurt: a >> 7 != 0 }
                }
            }
        };
        v.monsters.push(rec);
    }
    Some(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::view::{build, Scratch};
    use realm_core::{Config, Field, FIELD, SUB};

    #[test]
    fn v0_and_v1_decode_to_the_same_view() {
        let mut f = Field::new(3, Config { monsters: 20_000, threads: 2 });
        for i in 0..300 {
            f.join(&realm_core::Sheet::bench((i % 5) as u8, (i % 4) as u8, 1), &realm_core::Outing::new(), FIELD / 2 + (i % 20 - 10) * 40 * SUB, FIELD / 2 + (i / 20 - 7) * 40 * SUB);
        }
        let mut s = Scratch::default();
        let mut views: Vec<View> = Vec::new();
        let mut parts = Vec::new();
        for t in 0..80u32 {
            let inp: Vec<u8> = (0..300u32).map(|i| ((i + t / 10) % 9) as u8).collect();
            f.step(&inp);
            if t % 2 == 1 {
                continue;
            }
            for zoom in [1u8, 4] {
                let mut v = View::default();
                build(&f, 7, zoom, 123, &mut s, &mut v);
                encode_v0(&v, &mut parts);
                assert!(parts.iter().all(|p| p.len() <= MAX_DATAGRAM));
                let d0 = decode(&parts, None).expect("v0");
                assert_eq!(d0, v);
                let base = if zoom == 1 { views.last() } else { None };
                encode_v1(&v, base, &mut parts);
                let d1 = decode(&parts, base).expect("v1");
                assert_eq!(d1, v);
                if zoom == 1 {
                    views.push(v);
                }
            }
        }
        let last = views.last().unwrap();
        assert!(last.monsters.len() > 50 && last.players.len() > 20, "{} {}", last.monsters.len(), last.players.len());
    }

    fn mon(id: u32, x: u16, y: u16) -> MRec {
        MRec { id, x, y, attrs: 26, hurt: true }
    }

    /// Monsters at the window's corners, moved by the widest deltas, and one moved too far for a delta.
    #[test]
    fn monsters_at_the_window_edges_round_trip_against_a_base() {
        let (ox, oy) = (16_384 - 2_048, 0);
        let base = View { tick: 9, ox, oy, monsters: vec![mon(1, ox as u16, 7), mon(2, ox as u16 + 4_088, 2_040), mon(3, ox as u16 + 500, 300)], ..View::default() };
        let next = View { tick: 10, ox, oy, monsters: vec![mon(1, ox as u16 + 7, 0), mon(2, ox as u16 + 4_095, 2_047), mon(3, ox as u16, 2_047)], ..View::default() };
        let mut parts = Vec::new();
        encode_v1(&next, Some(&base), &mut parts);
        assert_eq!(decode(&parts, Some(&base)), Ok(next.clone()));
        encode_v1(&next, None, &mut parts);
        assert_eq!(decode(&parts, None), Ok(next));
    }

    /// Fuzz seeds 689518 and 422455 (2M iterations): the fuzz view had an origin of oy = 7 798 784 (0 mod 65 536),
    /// a monster at y = 2, then nudged to y = 65 532 (4 px above the origin). The u16 wrap made the delta big, so the
    /// monster went full and its negative 11-bit offset decoded as y = 2 044. `build` never makes such a view; the
    /// encoder now says so in a debug build rather than send it.
    #[test]
    #[cfg(debug_assertions)]
    #[should_panic(expected = "outside the 12/11-bit window")]
    fn a_monster_above_the_origin_is_refused_by_the_encoder() {
        let base = View { tick: 1, ox: -3_916_321, oy: 7_798_784, monsters: vec![mon(47, 17_916, 2)], ..View::default() };
        let next = View { tick: 2, monsters: vec![mon(47, 17_921, 65_532)], ..base.clone() };
        encode_v1(&next, Some(&base), &mut Vec::new());
    }
}
