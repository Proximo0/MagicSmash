//! Town rooms. A room holds at most `ROOM_MAX` heroes; the next arrival opens another. Heroes walk with the
//! field's directions at the field's speed; the server sends every member a snapshot 10 times a second
//! (`TownSnapshot`: id, x, y in whole px, direction) and each arrival, departure and chat line as it happens.
//! Houses, stations and the plaza (H1, C2) build on this: a room is a flat square of `TOWN_PX` px for now.

use crate::proto::{resp_frame, Member, Resp, TownSnapshot};
use realm_core::{DIAG_DEN, DIAG_NUM, DIRS, HERO_STEP, SUB};
use std::collections::BTreeMap;
use std::sync::mpsc::Sender;
use std::sync::Mutex;

/// Heroes in one room.
pub const ROOM_MAX: usize = 100;
/// A room's side in px.
pub const TOWN_PX: u16 = 4096;
/// Snapshots a second; a room step moves a hero this many field ticks' worth.
pub const STEP_HZ: u32 = 10;
pub const TICKS_PER_STEP: i32 = realm_core::TICK_HZ as i32 / STEP_HZ as i32;
/// A chat line is at most this many characters.
pub const CHAT_MAX: usize = 200;
/// A member may send this many lines in a burst, and earns one back every `CHAT_REFILL_STEPS` steps (1 s).
pub const CHAT_BURST: u32 = 5;
pub const CHAT_REFILL_STEPS: u32 = STEP_HZ;
/// Who stands in the middle of the square when they arrive: a scatter of this many px each way.
pub const ARRIVE_SCATTER_PX: i32 = 200;

#[derive(Debug, PartialEq, Eq)]
pub enum ChatError {
    SlowDown,
    Empty,
}

struct Mem {
    info: Member,
    x: i32,
    y: i32,
    dir: u8,
    out: Sender<Vec<u8>>,
    tokens: u32,
}

struct Room {
    id: u32,
    /// Which place this room is (`homes::place::key`); 0 is the plaza, where every hero arrives.
    place: u64,
    next: u16,
    members: BTreeMap<u16, Mem>,
}

#[derive(Default)]
struct Inner {
    rooms: Vec<Room>,
    next_room: u32,
    tick: u32,
}

#[derive(Default)]
pub struct Towns {
    inner: Mutex<Inner>,
}

/// A line cleaned for the room: control characters dropped, at most `CHAT_MAX` characters.
pub fn clean_chat(text: &str) -> String {
    text.chars().filter(|c| !c.is_control()).take(CHAT_MAX).collect::<String>().trim().to_string()
}

impl Towns {
    /// Puts a hero in the first room with space. Returns (room id, her member id, the members now, including her).
    pub fn enter(&self, info: Member, out: Sender<Vec<u8>>) -> (u32, u16, Vec<Member>) {
        self.enter_at(0, ROOM_MAX, true, info, out).expect("the plaza overflows into new rooms")
    }

    /// Puts a hero in a room of the place `place` with fewer than `cap` heroes; with `overflow` a new room opens when
    /// all are full (else None: the place is full). Rooms of different places never mix.
    pub fn enter_at(&self, place: u64, cap: usize, overflow: bool, mut info: Member, out: Sender<Vec<u8>>) -> Option<(u32, u16, Vec<Member>)> {
        let mut g = self.inner.lock().unwrap();
        let at = match g.rooms.iter().position(|r| r.place == place && r.members.len() < cap) {
            Some(i) => i,
            None => {
                if !overflow && g.rooms.iter().any(|r| r.place == place) {
                    return None;
                }
                g.next_room += 1;
                let id = g.next_room;
                g.rooms.push(Room { id, place, next: 0, members: BTreeMap::new() });
                g.rooms.len() - 1
            }
        };
        let room = &mut g.rooms[at];
        // The lowest id not in use, so ids stay small.
        let id = (0..=u16::MAX).find(|i| !room.members.contains_key(i)).unwrap_or(0);
        room.next = room.next.max(id + 1);
        info.id = id;
        let c = (TOWN_PX as i32 / 2) * SUB;
        let sc = ARRIVE_SCATTER_PX * SUB;
        let (x, y) = (c + (id as i32 * 7919 % (2 * ARRIVE_SCATTER_PX + 1) - ARRIVE_SCATTER_PX) * SUB, c + (id as i32 * 104729 % (2 * ARRIVE_SCATTER_PX + 1) - ARRIVE_SCATTER_PX) * SUB);
        debug_assert!(x >= c - sc && y >= c - sc);
        let arrive = resp_frame(0, &Resp::Arrive(info.clone()));
        for m in room.members.values() {
            let _ = m.out.send(arrive.clone());
        }
        room.members.insert(id, Mem { info, x, y, dir: 0, out, tokens: CHAT_BURST });
        let members = room.members.values().map(|m| m.info.clone()).collect();
        Some((room.id, id, members))
    }

    /// Where a member stands, in whole px, and which place her room is.
    pub fn position(&self, room: u32, id: u16) -> Option<(u16, u16, u64)> {
        let g = self.inner.lock().unwrap();
        let r = g.rooms.iter().find(|r| r.id == room)?;
        let m = r.members.get(&id)?;
        Some(((m.x / SUB) as u16, (m.y / SUB) as u16, r.place))
    }

    /// Members of a room (for a place's own pushes).
    pub fn members_of(&self, room: u32) -> Vec<Member> {
        let g = self.inner.lock().unwrap();
        g.rooms.iter().find(|r| r.id == room).map(|r| r.members.values().map(|m| m.info.clone()).collect()).unwrap_or_default()
    }

    /// Sends a frame to everyone in a room.
    pub fn broadcast(&self, room: u32, frame: &[u8]) {
        let g = self.inner.lock().unwrap();
        if let Some(r) = g.rooms.iter().find(|r| r.id == room) {
            for m in r.members.values() {
                let _ = m.out.send(frame.to_vec());
            }
        }
    }

    pub fn leave(&self, room: u32, id: u16) {
        let mut g = self.inner.lock().unwrap();
        if let Some(r) = g.rooms.iter_mut().find(|r| r.id == room) {
            if r.members.remove(&id).is_some() {
                let f = resp_frame(0, &Resp::Depart(id));
                for m in r.members.values() {
                    let _ = m.out.send(f.clone());
                }
            }
        }
        // A room nobody is in goes, unless it is the only one.
        if g.rooms.len() > 1 {
            g.rooms.retain(|r| !r.members.is_empty());
        }
    }

    pub fn input(&self, room: u32, id: u16, dir: u8) {
        let mut g = self.inner.lock().unwrap();
        if let Some(m) = g.rooms.iter_mut().find(|r| r.id == room).and_then(|r| r.members.get_mut(&id)) {
            m.dir = dir.min(8);
        }
    }

    pub fn chat(&self, room: u32, id: u16, text: &str) -> Result<(), ChatError> {
        let text = clean_chat(text);
        if text.is_empty() {
            return Err(ChatError::Empty);
        }
        let mut g = self.inner.lock().unwrap();
        let Some(r) = g.rooms.iter_mut().find(|r| r.id == room) else { return Err(ChatError::Empty) };
        let Some(m) = r.members.get_mut(&id) else { return Err(ChatError::Empty) };
        if m.tokens == 0 {
            return Err(ChatError::SlowDown);
        }
        m.tokens -= 1;
        let f = resp_frame(0, &Resp::Chat { from: id, name: m.info.name.clone(), text });
        for m in r.members.values() {
            let _ = m.out.send(f.clone());
        }
        Ok(())
    }

    /// One step (a tenth of a second): walks every member and sends each room's snapshot.
    pub fn step(&self) {
        let mut g = self.inner.lock().unwrap();
        g.tick += 1;
        let tick = g.tick;
        let lim = TOWN_PX as i32 * SUB - 1;
        for r in g.rooms.iter_mut() {
            let mut snap = TownSnapshot { tick, at: Vec::with_capacity(r.members.len()) };
            for (&id, m) in r.members.iter_mut() {
                let (ux, uy) = DIRS[m.dir as usize];
                let s = HERO_STEP * TICKS_PER_STEP;
                let s = if ux != 0 && uy != 0 { s * DIAG_NUM / DIAG_DEN } else { s };
                m.x = (m.x + ux * s).clamp(0, lim);
                m.y = (m.y + uy * s).clamp(0, lim);
                if tick % CHAT_REFILL_STEPS == 0 && m.tokens < CHAT_BURST {
                    m.tokens += 1;
                }
                snap.at.push((id, (m.x / SUB) as u16, (m.y / SUB) as u16, m.dir));
            }
            if r.members.is_empty() {
                continue;
            }
            let f = resp_frame(0, &Resp::Snapshot(snap));
            for m in r.members.values() {
                let _ = m.out.send(f.clone());
            }
        }
    }

    /// Heroes in all rooms.
    pub fn population(&self) -> usize {
        self.inner.lock().unwrap().rooms.iter().map(|r| r.members.len()).sum()
    }

    pub fn rooms(&self) -> usize {
        self.inner.lock().unwrap().rooms.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proto::read_frame;
    use std::sync::mpsc::{channel, Receiver};

    fn member(name: &str) -> Member {
        Member { id: 0, name: name.into(), class: 1, race: 0, level: 5, look: 0 }
    }

    fn drain(rx: &Receiver<Vec<u8>>) -> Vec<Resp> {
        rx.try_iter()
            .map(|f| {
                let (t, _, b) = read_frame(&mut &f[..]).unwrap().unwrap();
                Resp::decode(t, &b).unwrap()
            })
            .collect()
    }

    #[test]
    fn a_room_fills_then_another_opens_and_chat_stays_in_the_room() {
        let towns = Towns::default();
        let mut rxs = Vec::new();
        let mut seats = Vec::new();
        for k in 0..ROOM_MAX + 3 {
            let (tx, rx) = channel();
            let (room, id, _) = towns.enter(member(&format!("h{k}")), tx);
            seats.push((room, id));
            rxs.push(rx);
        }
        assert_eq!(towns.rooms(), 2);
        assert_eq!(seats[0].0, 1);
        assert_eq!(seats[ROOM_MAX].0, 2);
        assert_eq!(towns.population(), ROOM_MAX + 3);
        for rx in &rxs {
            drain(rx);
        }
        towns.chat(seats[0].0, seats[0].1, "  hello\u{7} town ").unwrap();
        let first = drain(&rxs[0]);
        assert_eq!(first, vec![Resp::Chat { from: seats[0].1, name: "h0".into(), text: "hello town".into() }]);
        assert_eq!(drain(&rxs[ROOM_MAX]), vec![], "another room hears nothing");
        // A burst of five, then slow down, then a second later one more.
        for _ in 0..CHAT_BURST - 1 {
            towns.chat(seats[0].0, seats[0].1, "x").unwrap();
        }
        assert_eq!(towns.chat(seats[0].0, seats[0].1, "x"), Err(ChatError::SlowDown));
        for _ in 0..CHAT_REFILL_STEPS {
            towns.step();
        }
        towns.chat(seats[0].0, seats[0].1, "x").unwrap();
        assert_eq!(towns.chat(seats[0].0, seats[0].1, "   "), Err(ChatError::Empty));
    }

    #[test]
    fn heroes_walk_at_the_fields_speed_and_the_snapshot_says_where() {
        let towns = Towns::default();
        let (tx, rx) = channel();
        let (room, me, members) = towns.enter(member("walker"), tx);
        assert_eq!(members.len(), 1);
        drain(&rx);
        towns.step();
        let at = |rx: &Receiver<Vec<u8>>| match drain(rx).pop() {
            Some(Resp::Snapshot(s)) => s.at[0],
            other => panic!("{other:?}"),
        };
        let (_, x0, y0, _) = at(&rx);
        towns.input(room, me, 1);
        for _ in 0..STEP_HZ {
            towns.step();
        }
        let (_, x1, y1, d) = at(&rx);
        // One second east is the hero's 60 px.
        assert_eq!((x1 as i32 - x0 as i32, y1, d), (60, y0, 1));
        // Walls: a long walk stops at the edge.
        for _ in 0..STEP_HZ * 120 {
            towns.step();
        }
        let (_, x2, _, _) = at(&rx);
        assert_eq!(x2, TOWN_PX - 1);
        towns.leave(room, me);
        assert_eq!(towns.population(), 0);
    }

    #[test]
    fn rooms_of_different_places_never_mix_and_a_place_without_overflow_says_full() {
        let towns = Towns::default();
        let mut rx = Vec::new();
        let mut enter = |place: u64, cap: usize, overflow: bool| {
            let (tx, r) = channel();
            rx.push(r);
            towns.enter_at(place, cap, overflow, member("x"), tx)
        };
        let (plaza, ..) = enter(0, 2, true).unwrap();
        let (house, ..) = enter(7, 2, false).unwrap();
        assert_ne!(plaza, house);
        assert_eq!(enter(7, 2, false).unwrap().0, house);
        assert!(enter(7, 2, false).is_none(), "a full house opens no second room");
        assert_eq!(enter(0, 2, true).unwrap().0, plaza);
        let (plaza2, ..) = enter(0, 2, true).unwrap();
        assert_ne!(plaza2, plaza, "a public place opens another room");
        assert_eq!(towns.rooms(), 3);
        assert_eq!(towns.position(house, 0).map(|p| p.2), Some(7));
        assert_eq!(towns.members_of(house).len(), 2);
    }
}
