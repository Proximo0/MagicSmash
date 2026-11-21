//! The state hash and the full-state bytes a lockstep client joins with.
//!
//! Hashed and saved: tick, RNG, live monsters (and which slots are free, in order), players, the flow
//! field's sources and progress, the counters. Not state: the grids (rebuilt every tick), the hurt flags
//! (output only), and the flow arrays themselves (rebuilt from their sources on load).

use crate::{Config, Field, Flow, Monsters, Player};

struct Hasher(u64);

impl Hasher {
    fn add(&mut self, v: u64) {
        self.0 = (self.0.rotate_left(5) ^ v).wrapping_mul(0x9E37_79B9_7F4A_7C15);
    }
}

impl Field {
    /// A 64-bit hash of the whole state.
    pub fn hash(&self) -> u64 {
        let mut h = Hasher(0xCBF2_9CE4_8422_2325);
        h.add(self.tick as u64);
        h.add(self.rng);
        h.add(self.alive as u64);
        let m = &self.m;
        for i in 0..m.hp.len() {
            if m.hp[i] > 0 {
                h.add(i as u64);
                h.add((m.x[i] as u32 as u64) << 32 | m.y[i] as u32 as u64);
                h.add((m.hp[i] as u64) << 16 | (m.kind[i] as u64) << 8 | m.stagger[i] as u64);
            }
        }
        h.add(self.free.len() as u64);
        for &f in &self.free {
            h.add(f as u64);
        }
        h.add(self.players.len() as u64);
        for p in &self.players {
            h.add((p.x as u32 as u64) << 32 | p.y as u32 as u64);
            h.add(player_word(p));
            h.add((p.xp as u64) << 32 | (p.level as u64) << 16 | p.max_health as u64);
        }
        h.add(self.flow.head as u64);
        for s in [&self.flow.active_sources, &self.flow.build_sources] {
            h.add(s.len() as u64);
            for &(c, p) in s {
                h.add((c as u64) << 16 | p as u64);
            }
        }
        h.add(self.kills_total);
        h.add(self.spawns_total);
        h.add(self.deaths_total);
        h.add(self.recycled_total);
        h.0
    }

    /// The whole state as bytes (what a protocol B client receives when it joins).
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut w = Vec::new();
        put(&mut w, &self.cfg.monsters.to_le_bytes());
        put(&mut w, &self.tick.to_le_bytes());
        put(&mut w, &self.rng.to_le_bytes());
        put(&mut w, &self.alive.to_le_bytes());
        for v in [self.kills_total, self.spawns_total, self.deaths_total, self.recycled_total] {
            put(&mut w, &v.to_le_bytes());
        }
        let m = &self.m;
        for i in 0..m.hp.len() {
            put(&mut w, &m.hp[i].to_le_bytes());
            if m.hp[i] > 0 {
                put(&mut w, &m.x[i].to_le_bytes());
                put(&mut w, &m.y[i].to_le_bytes());
                w.push(m.kind[i]);
                w.push(m.stagger[i]);
            }
        }
        put(&mut w, &(self.free.len() as u32).to_le_bytes());
        for &f in &self.free {
            put(&mut w, &f.to_le_bytes());
        }
        put(&mut w, &(self.players.len() as u32).to_le_bytes());
        for p in &self.players {
            put(&mut w, &p.x.to_le_bytes());
            put(&mut w, &p.y.to_le_bytes());
            put(&mut w, &player_word(p).to_le_bytes());
            put(&mut w, &p.xp.to_le_bytes());
            put(&mut w, &p.level.to_le_bytes());
            put(&mut w, &p.max_health.to_le_bytes());
        }
        put(&mut w, &(self.flow.head as u32).to_le_bytes());
        for s in [&self.flow.active_sources, &self.flow.build_sources] {
            put(&mut w, &(s.len() as u32).to_le_bytes());
            for &(c, p) in s {
                put(&mut w, &c.to_le_bytes());
                put(&mut w, &p.to_le_bytes());
            }
        }
        w
    }

    /// Rebuilds a field from `to_bytes`; `threads` is this machine's choice.
    pub fn from_bytes(b: &[u8], threads: usize) -> Option<Field> {
        let mut r = Reader { b, at: 0 };
        let monsters = r.u32()?;
        let mut f = Field::new(0, Config { monsters, threads: threads.max(1) });
        f.tick = r.u32()?;
        f.rng = r.u64()?;
        f.alive = r.u32()?;
        f.kills_total = r.u64()?;
        f.spawns_total = r.u64()?;
        f.deaths_total = r.u64()?;
        f.recycled_total = r.u64()?;
        let m: &mut Monsters = &mut f.m;
        for i in 0..monsters as usize {
            m.hp[i] = r.u16()?;
            if m.hp[i] > 0 {
                m.x[i] = r.u32()? as i32;
                m.y[i] = r.u32()? as i32;
                m.kind[i] = r.u8()?;
                m.stagger[i] = r.u8()?;
            }
        }
        let nf = r.u32()? as usize;
        f.free = (0..nf).map(|_| r.u32()).collect::<Option<_>>()?;
        let np = r.u32()? as usize;
        for _ in 0..np {
            let x = r.u32()? as i32;
            let y = r.u32()? as i32;
            let word = r.u64()?;
            let xp = r.u32()?;
            let level = r.u16()?;
            let max_health = r.u16()?;
            let mut p = player_from_word(word);
            p.x = x;
            p.y = y;
            p.xp = xp;
            p.level = level;
            p.max_health = max_health;
            f.players.push(p);
        }
        let head = r.u32()? as usize;
        let mut lists = [Vec::new(), Vec::new()];
        for l in &mut lists {
            let n = r.u32()? as usize;
            for _ in 0..n {
                l.push((r.u32()?, r.u16()?));
            }
        }
        let [active, build] = lists;
        let flow: &mut Flow = &mut f.flow;
        flow.start(active);
        flow.run(usize::MAX);
        flow.finish();
        flow.start(build);
        flow.run(head);
        if flow.head != head || r.at != b.len() {
            return None;
        }
        Some(f)
    }
}

/// Everything small about a player in one word: present, class, race, health, cooldowns, input, flags.
fn player_word(p: &Player) -> u64 {
    (p.present as u64)
        | (p.class as u64) << 1
        | (p.race as u64) << 4
        | (p.facing_left as u64) << 7
        | (p.moving as u64) << 8
        | (p.health as u64) << 16
        | (p.cooldown as u64) << 32
        | (p.skill_cd as u64) << 40
        | (p.input as u64) << 48
        | (p.dead_timer as u64) << 56
}

fn player_from_word(w: u64) -> Player {
    Player {
        present: w & 1 != 0,
        class: (w >> 1 & 7) as u8,
        race: (w >> 4 & 7) as u8,
        facing_left: w >> 7 & 1 != 0,
        moving: w >> 8 & 1 != 0,
        health: (w >> 16) as u16,
        cooldown: (w >> 32) as u8,
        skill_cd: (w >> 40) as u8,
        input: (w >> 48) as u8,
        dead_timer: (w >> 56) as u8,
        ..Player::default()
    }
}

fn put(w: &mut Vec<u8>, b: &[u8]) {
    w.extend_from_slice(b);
}

struct Reader<'a> {
    b: &'a [u8],
    at: usize,
}

impl Reader<'_> {
    fn take<const N: usize>(&mut self) -> Option<[u8; N]> {
        let s = self.b.get(self.at..self.at + N)?;
        self.at += N;
        s.try_into().ok()
    }
    fn u8(&mut self) -> Option<u8> {
        Some(self.take::<1>()?[0])
    }
    fn u16(&mut self) -> Option<u16> {
        Some(u16::from_le_bytes(self.take()?))
    }
    fn u32(&mut self) -> Option<u32> {
        Some(u32::from_le_bytes(self.take()?))
    }
    fn u64(&mut self) -> Option<u64> {
        Some(u64::from_le_bytes(self.take()?))
    }
}
