//! The state hash and the full-state bytes a lockstep client joins with.
//!
//! Saved (and hashed, since the hash is taken over the saved bytes): field id, seed, tick, RNG, the tide
//! flag, the counters, the terrain's hash (the map itself is rebuilt from field id and seed), every
//! monster, the free slots in order, every hero (sheet and outing, timers, effects, the reserved section
//! 14 state), zones, drops, monster shots, and the flow field's sources and progress. Not state: the
//! grids, the aura map, the mods, events, the monsters' hurt flags (a hero's is state: the next tick's banking
//! reads it).

use crate::boss::{Boss, Cast, Mire};
use crate::flow::Flow;
use crate::hero::Hero;
use crate::sheet::Sheet;
use crate::tables::*;
use crate::tide::{Altar, Realm};
use crate::vault::VaultRun;
use crate::{Config, Drop, Field, Shot, Zone, terrain};

/// Format version of `to_bytes`.
pub const STATE_VERSION: u32 = 4;
/// The vault byte of a field (not a vault).
const NO_VAULT: u8 = u8::MAX;

impl Field {
    /// A 64-bit hash of the whole state.
    pub fn hash(&self) -> u64 {
        let b = self.to_bytes();
        let mut h = 0xCBF2_9CE4_8422_2325u64;
        for ch in b.chunks(8) {
            let mut w = [0u8; 8];
            w[..ch.len()].copy_from_slice(ch);
            h = (h.rotate_left(5) ^ u64::from_le_bytes(w)).wrapping_mul(0x9E37_79B9_7F4A_7C15);
        }
        h ^ b.len() as u64
    }

    /// The whole state as bytes (what a protocol B client receives when it joins).
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut w = W(Vec::with_capacity(64 + self.m.len() * 8));
        w.u32(STATE_VERSION);
        w.u8(self.field);
        w.u64(self.seed);
        match &self.realm.vault {
            Some(v) => {
                w.u8(v.vault);
                w.u8(v.seals);
            }
            None if self.pvp.yard => {
                w.u8(crate::pvp::YARD);
                w.u8(0);
            }
            None => {
                w.u8(NO_VAULT);
                w.u8(0);
            }
        }
        w.u32(self.cfg.monsters);
        w.u32(self.tick);
        w.u64(self.rng);
        w.u32(self.alive);
        w.u8(self.tide as u8 | (self.births as u8) << 1);
        for v in [self.kills_total, self.spawns_total, self.deaths_total, self.recycled_total] {
            w.u64(v);
        }
        w.u64(self.terrain.hash);
        let m = &self.m;
        for i in 0..m.len() {
            w.u32(m.hp[i]);
            if m.hp[i] > 0 {
                w.i32(m.x[i]);
                w.i32(m.y[i]);
                for b in [m.kind[i], m.level[i], m.flags[i], m.stun[i], m.slow[i], m.curse[i], m.timer[i]] {
                    w.u8(b);
                }
            }
        }
        w.u32(self.free.len() as u32);
        for &f in &self.free {
            w.u32(f);
        }
        w.u32(self.heroes.len() as u32);
        for h in &self.heroes {
            w.hero(h);
        }
        w.u32(self.zones.len() as u32);
        for z in &self.zones {
            w.i32(z.x);
            w.i32(z.y);
            w.i32(z.px);
            w.u8(z.kind);
            w.u16(z.owner);
            w.u16(z.left);
            w.u16(z.age);
            w.u32(z.dmg);
            w.u32(z.heal_tenths);
        }
        w.u32(self.drops.len() as u32);
        for d in &self.drops {
            w.i32(d.x);
            w.i32(d.y);
            w.i32(d.px);
            w.u16(d.left);
            w.u32(d.dmg);
            w.u16(d.hero);
            w.u8(d.stun);
        }
        w.u32(self.shots.len() as u32);
        for s in &self.shots {
            w.i32(s.x);
            w.i32(s.y);
            w.i32(s.vx);
            w.i32(s.vy);
            w.u16(s.left);
            w.u32(s.dmg);
            w.i32(s.px);
        }
        for s in [&self.flow.active_sources, &self.flow.build_sources] {
            w.u32(s.len() as u32);
            for &(c, h, d) in s {
                w.u32(c);
                w.u16(h);
                w.u16(d);
            }
        }
        w.u32(self.flow.progress() as u32);
        w.realm(&self.realm);
        // Section 14's block, only when there is something in it: a field without PvP keeps its bytes and hash.
        if !self.pvp.is_empty() {
            self.pvp.write(&mut w.0);
        }
        w.0
    }

    /// Rebuilds a field from `to_bytes`; `threads` is this machine's choice.
    pub fn from_bytes(b: &[u8], threads: usize) -> Option<Field> {
        let mut r = R { b, at: 0 };
        if r.u32()? != STATE_VERSION {
            return None;
        }
        let field = r.u8()?;
        if field as usize >= FIELDS.len() {
            return None;
        }
        let seed = r.u64()?;
        let (vault, seals) = (r.u8()?, r.u8()?);
        let monsters = r.u32()?;
        // Every monster slot is at least its 4 hp bytes below, so a count the bytes cannot hold is a lie: refuse it before
        // the pool (tens of bytes a slot) is allocated.
        if monsters as usize > r.b.len().saturating_sub(r.at) / 4 {
            return None;
        }
        let cfg = Config { monsters, threads: threads.max(1) };
        let mut f = if vault == NO_VAULT {
            Field::open(field, seed, cfg)
        } else if vault == crate::pvp::YARD && field == 0 && seals == 0 {
            Field::open_duel(seed, cfg)
        } else if (vault as usize) < VAULTS.len() && VAULTS[vault as usize].field == field {
            Field::open_vault(vault, seals, seed, cfg)
        } else {
            return None;
        };
        f.tick = r.u32()?;
        f.rng = r.u64()?;
        f.alive = r.u32()?;
        let flags = r.u8()?;
        f.tide = flags & 1 != 0;
        f.births = flags & 2 != 0;
        f.kills_total = r.u64()?;
        f.spawns_total = r.u64()?;
        f.deaths_total = r.u64()?;
        f.recycled_total = r.u64()?;
        if r.u64()? != f.terrain.hash {
            return None;
        }
        let _ = terrain::flood;
        let m = &mut f.m;
        for i in 0..monsters as usize {
            m.hp[i] = r.u32()?;
            if m.hp[i] > 0 {
                m.x[i] = r.i32()?;
                m.y[i] = r.i32()?;
                m.kind[i] = r.u8()?;
                m.level[i] = r.u8()?;
                m.flags[i] = r.u8()?;
                m.stun[i] = r.u8()?;
                m.slow[i] = r.u8()?;
                m.curse[i] = r.u8()?;
                m.timer[i] = r.u8()?;
                if m.kind[i] as usize >= KINDS.len() {
                    return None;
                }
            }
        }
        let nf = r.u32()? as usize;
        f.free = (0..nf).map(|_| r.u32()).collect::<Option<_>>()?;
        let nh = r.u32()? as usize;
        for _ in 0..nh {
            let h = r.hero()?;
            f.heroes.push(h);
        }
        for _ in 0..r.u32()? {
            f.zones.push(Zone {
                x: r.i32()?,
                y: r.i32()?,
                px: r.i32()?,
                kind: r.u8()?,
                owner: r.u16()?,
                left: r.u16()?,
                age: r.u16()?,
                dmg: r.u32()?,
                heal_tenths: r.u32()?,
            });
        }
        for _ in 0..r.u32()? {
            f.drops.push(Drop { x: r.i32()?, y: r.i32()?, px: r.i32()?, left: r.u16()?, dmg: r.u32()?, hero: r.u16()?, stun: r.u8()? });
        }
        for _ in 0..r.u32()? {
            f.shots.push(Shot { x: r.i32()?, y: r.i32()?, vx: r.i32()?, vy: r.i32()?, left: r.u16()?, dmg: r.u32()?, px: r.i32()? });
        }
        let mut lists = [Vec::new(), Vec::new()];
        for l in &mut lists {
            for _ in 0..r.u32()? {
                let cell = r.u32()?;
                // A source outside the grid would index past the flow field (found by the wire fuzz, seed 273593).
                if cell as usize >= crate::CELLS {
                    return None;
                }
                l.push((cell, r.u16()?, r.u16()?));
            }
        }
        let progress = r.u32()? as usize;
        let [active, build] = lists;
        let map = &f.terrain.map;
        let flow: &mut Flow = &mut f.flow;
        flow.start(active);
        flow.run(usize::MAX, map);
        flow.finish();
        f.src_d0.resize(f.heroes.len(), 0);
        for &(_, h, d) in &f.flow.active_sources {
            if let Some(s) = f.src_d0.get_mut(h as usize) {
                *s = d;
            }
        }
        f.flow.start(build);
        f.flow.run(progress, &f.terrain.map);
        let realm = r.realm()?;
        if let Some(b) = &realm.boss {
            f.m.boss_max = b.max_hp;
        }
        f.realm = realm;
        if r.at < b.len() {
            let yard = f.pvp.yard;
            f.pvp = crate::pvp::Pvp::read(b, &mut r.at, f.heroes.len())?;
            f.pvp.yard = yard;
        }
        if f.flow.progress() != progress || r.at != b.len() {
            return None;
        }
        Some(f)
    }
}

struct W(Vec<u8>);

impl W {
    fn u8(&mut self, v: u8) {
        self.0.push(v);
    }
    fn u16(&mut self, v: u16) {
        self.0.extend_from_slice(&v.to_le_bytes());
    }
    fn u32(&mut self, v: u32) {
        self.0.extend_from_slice(&v.to_le_bytes());
    }
    fn i32(&mut self, v: i32) {
        self.0.extend_from_slice(&v.to_le_bytes());
    }
    fn u64(&mut self, v: u64) {
        self.0.extend_from_slice(&v.to_le_bytes());
    }
    fn sheet(&mut self, s: &Sheet) {
        for b in [s.class, s.job, s.race, s.class_level, s.gear_level] {
            self.u8(b);
        }
        for v in s.points.iter().chain(s.gear.iter()) {
            self.u16(*v);
        }
        self.u8(s.deck.len() as u8);
        for &c in &s.deck {
            self.u8(c);
        }
        for (p, n) in s.belt {
            self.u8(p);
            self.u8(n);
        }
        self.u32(s.look);
    }
    fn hero(&mut self, h: &Hero) {
        self.u8(h.present as u8);
        if !h.present {
            return;
        }
        self.i32(h.x);
        self.i32(h.y);
        self.sheet(&h.sheet);
        for b in [h.class, h.job, h.race, h.class_level] {
            self.u8(b);
        }
        for v in h.stats {
            self.u16(v);
        }
        self.u32(h.health);
        self.u32(h.max_health);
        self.u16(h.level);
        self.u32(h.xp);
        for c in h.copies {
            self.u8(c);
        }
        self.u8(h.offers.len() as u8);
        for o in &h.offers {
            for &c in o {
                self.u8(c);
            }
        }
        self.u16(h.owed);
        self.u32(h.draws);
        self.u32(h.coin);
        self.u32(h.charge);
        self.u32(h.attacks);
        for c in h.cooldowns {
            self.u32(c);
        }
        for (p, n) in h.belt {
            self.u8(p);
            self.u8(n);
        }
        for t in h.belt_rest {
            self.u16(t);
        }
        self.u8(h.phoenix_used as u8);
        for t in h.fx {
            self.u16(t);
        }
        self.u16(h.downed);
        self.u32(h.raise);
        self.u16(h.hold);
        self.u8(h.waystone);
        self.u8(h.banked as u8);
        self.u32(h.active);
        self.u32(h.regen);
        self.u32(h.lovers);
        self.u32(h.lovers_carry);
        self.u8(h.marked as u8);
        self.u32(h.last_struck);
        self.u16(h.input);
        // `hurt` is read by the next tick's banking hold (a hit pauses it), so it is state (job B1 found a loaded
        // copy that counted one tick more of a hold than the field it was saved from).
        self.u8(h.facing_left as u8 | (h.moving as u8) << 1 | (h.wailed as u8) << 2 | (h.hurt as u8) << 3);
        self.u8(h.dir);
        self.u16(h.idle);
        self.u32(h.tide_contrib);
        self.u32(h.boss_contrib);
        self.u8(h.shrines);
    }
    fn realm(&mut self, s: &Realm) {
        self.u64(s.clock);
        self.u32(s.tide_index);
        self.u32(s.tide_seen);
        self.u32(s.factor);
        for a in &s.altars {
            self.u8(a.state);
            self.u32(a.progress);
            self.u32(a.hp);
        }
        self.u64(s.quick_until);
        self.u8(s.result);
        self.u32(s.result_index);
        self.u32(s.boss_seen);
        self.u32(s.world_seen);
        match &s.boss {
            None => self.u8(0),
            Some(b) => {
                self.u8(1);
                for v in [b.which, b.phase, b.world as u8] {
                    self.u8(v);
                }
                self.u32(b.slot);
                self.u32(b.max_hp);
                self.u64(b.leaves);
                self.u32(b.dmg_pct);
                self.u64(b.next_at);
                self.u32(b.cycle);
                self.u32(b.window);
                self.u32(b.casts.len() as u32);
                for c in &b.casts {
                    self.u8(c.atk);
                    self.u16(c.age);
                    self.i32(c.x);
                    self.i32(c.y);
                    self.i32(c.angle);
                    self.u16(c.rides);
                    self.u32(c.pts.len() as u32);
                    for &(x, y) in &c.pts {
                        self.i32(x);
                        self.i32(y);
                    }
                    self.u32(c.hit.len() as u32);
                    for &q in &c.hit {
                        self.u16(q);
                    }
                }
                self.u32(b.mires.len() as u32);
                for m in &b.mires {
                    self.i32(m.x);
                    self.i32(m.y);
                    self.i32(m.px);
                    self.u16(m.left);
                }
            }
        }
        match &s.vault {
            None => self.u8(0),
            Some(v) => {
                self.u8(1);
                for b in [v.vault, v.seals, v.state, v.minute_seen, v.next_boss] {
                    self.u8(b);
                }
                self.u32(v.started);
                self.u32(v.ended);
            }
        }
    }
}

struct R<'a> {
    b: &'a [u8],
    at: usize,
}

impl R<'_> {
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
    fn i32(&mut self) -> Option<i32> {
        Some(i32::from_le_bytes(self.take()?))
    }
    fn u64(&mut self) -> Option<u64> {
        Some(u64::from_le_bytes(self.take()?))
    }
    fn sheet(&mut self) -> Option<Sheet> {
        let (class, job, race, class_level, gear_level) = (self.u8()?, self.u8()?, self.u8()?, self.u8()?, self.u8()?);
        let mut points = [0u16; 6];
        let mut gear = [0u16; 6];
        for v in points.iter_mut().chain(gear.iter_mut()) {
            *v = self.u16()?;
        }
        let n = self.u8()? as usize;
        let deck = (0..n).map(|_| self.u8()).collect::<Option<Vec<u8>>>()?;
        let mut belt = [(0u8, 0u8); BELT];
        for s in belt.iter_mut() {
            *s = (self.u8()?, self.u8()?);
        }
        let look = self.u32()?;
        Some(Sheet { class, job, race, class_level, points, gear, gear_level, deck, belt, look })
    }
    fn hero(&mut self) -> Option<Hero> {
        if self.u8()? == 0 {
            return Some(Hero::default());
        }
        let mut h = Hero { present: true, x: self.i32()?, y: self.i32()?, sheet: self.sheet()?, ..Hero::default() };
        h.class = self.u8()?;
        h.job = self.u8()?;
        h.race = self.u8()?;
        h.class_level = self.u8()?;
        if h.class as usize >= CLASSES.len() || h.race as usize >= RACES.len() {
            return None;
        }
        for v in h.stats.iter_mut() {
            *v = self.u16()?;
        }
        h.health = self.u32()?;
        h.max_health = self.u32()?;
        h.level = self.u16()?;
        h.xp = self.u32()?;
        for c in h.copies.iter_mut() {
            *c = self.u8()?;
        }
        let n = self.u8()? as usize;
        for _ in 0..n {
            let mut o = [0u8; DRAW_MAX as usize];
            for c in o.iter_mut() {
                *c = self.u8()?;
            }
            h.offers.push(o);
        }
        h.owed = self.u16()?;
        h.draws = self.u32()?;
        h.coin = self.u32()?;
        h.charge = self.u32()?;
        h.attacks = self.u32()?;
        for c in h.cooldowns.iter_mut() {
            *c = self.u32()?;
        }
        for s in h.belt.iter_mut() {
            *s = (self.u8()?, self.u8()?);
        }
        for t in h.belt_rest.iter_mut() {
            *t = self.u16()?;
        }
        h.phoenix_used = self.u8()? != 0;
        for t in h.fx.iter_mut() {
            *t = self.u16()?;
        }
        h.downed = self.u16()?;
        h.raise = self.u32()?;
        h.hold = self.u16()?;
        h.waystone = self.u8()?;
        h.banked = self.u8()? != 0;
        h.active = self.u32()?;
        h.regen = self.u32()?;
        h.lovers = self.u32()?;
        h.lovers_carry = self.u32()?;
        h.marked = self.u8()? != 0;
        h.last_struck = self.u32()?;
        h.input = self.u16()?;
        let fl = self.u8()?;
        h.facing_left = fl & 1 != 0;
        h.moving = fl & 2 != 0;
        h.wailed = fl & 4 != 0;
        h.hurt = fl & 8 != 0;
        h.dir = self.u8()?;
        h.idle = self.u16()?;
        h.tide_contrib = self.u32()?;
        h.boss_contrib = self.u32()?;
        h.shrines = self.u8()?;
        Some(h)
    }
    fn realm(&mut self) -> Option<Realm> {
        let mut s = Realm::new();
        s.clock = self.u64()?;
        s.tide_index = self.u32()?;
        s.tide_seen = self.u32()?;
        s.factor = self.u32()?;
        for a in s.altars.iter_mut() {
            *a = Altar { state: self.u8()?, progress: self.u32()?, hp: self.u32()? };
        }
        s.quick_until = self.u64()?;
        s.result = self.u8()?;
        s.result_index = self.u32()?;
        s.boss_seen = self.u32()?;
        s.world_seen = self.u32()?;
        if self.u8()? == 1 {
            let (which, phase, world) = (self.u8()?, self.u8()?, self.u8()? != 0);
            if which as usize >= BOSSES.len() {
                return None;
            }
            let mut b = Boss {
                which,
                slot: self.u32()?,
                max_hp: 0,
                phase,
                leaves: 0,
                dmg_pct: 0,
                next_at: 0,
                cycle: 0,
                casts: Vec::new(),
                mires: Vec::new(),
                world,
                window: 0,
            };
            b.max_hp = self.u32()?;
            b.leaves = self.u64()?;
            b.dmg_pct = self.u32()?;
            b.next_at = self.u64()?;
            b.cycle = self.u32()?;
            b.window = self.u32()?;
            for _ in 0..self.u32()? {
                let mut c = Cast {
                    atk: self.u8()?,
                    age: self.u16()?,
                    x: self.i32()?,
                    y: self.i32()?,
                    angle: self.i32()?,
                    pts: Vec::new(),
                    hit: Vec::new(),
                    rides: self.u16()?,
                };
                if c.atk as usize >= BOSSES[which as usize].attacks.len() {
                    return None;
                }
                for _ in 0..self.u32()? {
                    c.pts.push((self.i32()?, self.i32()?));
                }
                for _ in 0..self.u32()? {
                    c.hit.push(self.u16()?);
                }
                b.casts.push(c);
            }
            for _ in 0..self.u32()? {
                b.mires.push(Mire { x: self.i32()?, y: self.i32()?, px: self.i32()?, left: self.u16()? });
            }
            s.boss = Some(b);
        }
        if self.u8()? == 1 {
            let (vault, seals, state, minute_seen, next_boss) = (self.u8()?, self.u8()?, self.u8()?, self.u8()?, self.u8()?);
            s.vault = Some(VaultRun { vault, seals, state, started: self.u32()?, minute_seen, next_boss, ended: self.u32()? });
        }
        Some(s)
    }
}
