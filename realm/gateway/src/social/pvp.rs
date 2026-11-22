//! Players against players at the gateway (job R3, rules section 14): guild altar wars (declare, accept, list, call
//! off; officers and the leader only), duels in the town's training yard (challenge, accept, decline; the duel is a
//! core yard field stepped here from the duellists' town input), and the BLOOD MARK's book (a hero's mark and her
//! last strike on a hero, kept between outings so leaving the field does not clear the ten-minute wait).
//! `docs/realm/pvp.md` has every number and why.
//!
//! Wars are kept through the social log like guilds (`wdecl`, `wacc`, `woff`, `wend`); the mark book too (`mark`).
//! Duels and challenges live in memory: a restart ends them with no result.

use super::*;
use realm_core::pvp::{DUEL_DRAW, DUEL_WON, MARK_WAIT_TICKS};
use realm_core::tables::{FIELDS, NEVER};
use realm_core::{tide_start, Config, Event, Field, Outing, TICK_HZ};

/// A war is for the field's first tide that starts at least this long after the declaration (realm ticks: 2 min),
/// so the other guild has time to answer and to gather.
pub const WAR_LEAD_TICKS: u64 = 2 * 60 * TICK_HZ as u64;
/// Ranks that may declare, accept or call off a war: the leader (0) and officers (1).
pub const WAR_RANK_MAX: u8 = 1;
/// Wars a guild may have declared or accepted and not yet fought.
pub const WARS_PER_GUILD: usize = 3;
/// A duel challenge lives this long.
pub const DUEL_OFFER_MS: i64 = 30_000;
/// Core ticks a duel steps per town step (town 10 Hz, core 20 Hz).
pub const DUEL_TICKS_PER_STEP: u32 = realm_core::TICK_HZ / crate::town::STEP_HZ;
/// Monsters a yard's pool holds (none are born).
pub const YARD_POOL: u32 = 16;

/// A declared war.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WarRec {
    pub id: u64,
    pub guilds: [u64; 2],
    pub field: u8,
    pub tide: u32,
    pub accepted: bool,
}

/// A running duel: its yard, the heroes (store ids) and their slots, the last town direction of each.
pub struct DuelRun {
    pub id: u64,
    pub heroes: [i64; 2],
    pub names: [String; 2],
    pub ids: [u16; 2],
    pub field: Field,
    pub input: [u16; 2],
}

/// The first tide of `field` that starts at `now + WAR_LEAD_TICKS` or later.
pub fn next_war_tide(field: u8, now: u64) -> u32 {
    let mut n = 0u32;
    while tide_start(field, n) < now + WAR_LEAD_TICKS {
        n += 1;
    }
    n
}

impl Inner {
    fn war_view(&self, w: &WarRec) -> WarView {
        let name = |g: u64| self.guilds.get(&g).map(|g| g.name.clone()).unwrap_or_default();
        WarView { id: w.id, guilds: w.guilds, names: [name(w.guilds[0]), name(w.guilds[1])], field: w.field, tide: w.tide, accepted: w.accepted }
    }

    fn tell_guilds(&self, guilds: [u64; 2], p: &SPush) {
        for g in guilds {
            if let Some(g) = self.guilds.get(&g) {
                for a in g.members.keys() {
                    self.send_account(*a, p);
                }
            }
        }
    }

    /// Wars whose tide has begun without an answer are off (their guilds are told).
    fn prune_wars(&mut self, now: u64) {
        let stale: Vec<(u64, [u64; 2])> = self.wars.values().filter(|w| !w.accepted && tide_start(w.field, w.tide) <= now).map(|w| (w.id, w.guilds)).collect();
        for (id, guilds) in stale {
            self.commit("woff", &[&id.to_string()]);
            self.tell_guilds(guilds, &SPush::WarOff { war: id });
        }
    }

    /// Her guild and rank, if she may speak for it in a war.
    fn war_officer(&self, me: &Me) -> R<u64> {
        let id = *self.guild_of.get(&me.account).ok_or_else(|| bad("you are in no guild"))?;
        let rank = self.guilds[&id].members[&me.account].rank;
        if rank > WAR_RANK_MAX {
            return Err(fail(code::REFUSED, "only officers declare and answer wars"));
        }
        Ok(id)
    }

    pub(crate) fn apply_pvp(&mut self, kind: &str, f: &[String]) {
        let n = |i: usize| f.get(i).and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
        match kind {
            "wdecl" => {
                let w = WarRec { id: n(0), guilds: [n(1), n(2)], field: n(3) as u8, tide: n(4) as u32, accepted: false };
                self.next_war = self.next_war.max(w.id + 1);
                self.wars.insert(w.id, w);
            }
            "wacc" => {
                if let Some(w) = self.wars.get_mut(&n(0)) {
                    w.accepted = true;
                }
            }
            "woff" | "wend" => {
                self.wars.remove(&n(0));
            }
            "mark" => {
                let at = f.get(2).and_then(|s| s.parse::<i64>().ok()).unwrap_or(i64::MIN);
                self.marks.insert(n(0) as i64, (n(1) != 0, at));
            }
            _ => {}
        }
    }
}

impl Social {
    pub(crate) fn war_declare(&self, gw: &Gateway, me: &Me, foe: &str, field: u8) -> R {
        if field as usize >= FIELDS.len() {
            return Err(bad("no such field"));
        }
        let now = gw.world.clock.now();
        let mut g = self.inner.lock().unwrap();
        g.prune_wars(now);
        let mine = g.war_officer(me)?;
        let want = foe.trim().to_lowercase();
        let theirs = g.guilds.values().find(|x| x.name.to_lowercase() == want).map(|x| x.id).ok_or_else(|| fail(code::MISSING, "no guild by that name"))?;
        if theirs == mine {
            return Err(bad("a guild cannot war on itself"));
        }
        let tide = next_war_tide(field, now);
        for k in [mine, theirs] {
            if g.wars.values().filter(|w| w.guilds.contains(&k)).count() >= WARS_PER_GUILD {
                return Err(fail(code::REFUSED, "too many wars waiting"));
            }
            if g.wars.values().any(|w| w.field == field && w.tide == tide && w.guilds.contains(&k)) {
                return Err(fail(code::REFUSED, "already at war in that tide"));
            }
        }
        let id = g.next_war;
        g.commit("wdecl", &[&id.to_string(), &mine.to_string(), &theirs.to_string(), &field.to_string(), &tide.to_string()]);
        let view = g.war_view(&g.wars[&id]);
        g.tell_guilds([mine, theirs], &SPush::War(view.clone()));
        Ok(Resp::Social(SResp::WarDeclared(view)))
    }

    pub(crate) fn war_answer(&self, gw: &Gateway, me: &Me, war: u64, accept: bool) -> R {
        let now = gw.world.clock.now();
        let mut g = self.inner.lock().unwrap();
        g.prune_wars(now);
        let mine = g.war_officer(me)?;
        let w = g.wars.get(&war).cloned().ok_or_else(|| fail(code::MISSING, "no such war"))?;
        if !w.guilds.contains(&mine) {
            return Err(fail(code::NOT_YOURS, "not your guild's war"));
        }
        if accept {
            if w.guilds[1] != mine {
                return Err(bad("the other guild accepts"));
            }
            if w.accepted {
                return Err(bad("already accepted"));
            }
            g.commit("wacc", &[&war.to_string()]);
            let view = g.war_view(&g.wars[&war]);
            g.tell_guilds(w.guilds, &SPush::War(view));
        } else {
            if w.accepted && tide_start(w.field, w.tide) <= now {
                return Err(fail(code::REFUSED, "the war is being fought"));
            }
            g.commit("woff", &[&war.to_string()]);
            g.tell_guilds(w.guilds, &SPush::WarOff { war });
        }
        Ok(Resp::Ok)
    }

    pub(crate) fn war_list(&self, gw: &Gateway, me: &Me) -> R {
        let mut g = self.inner.lock().unwrap();
        g.prune_wars(gw.world.clock.now());
        let Some(&mine) = g.guild_of.get(&me.account) else { return Ok(Resp::Social(SResp::Wars(Vec::new()))) };
        let v = g.wars.values().filter(|w| w.guilds.contains(&mine)).map(|w| g.war_view(w)).collect();
        Ok(Resp::Social(SResp::Wars(v)))
    }

    /// The accepted wars of a field's tide, as (war, declaring guild, accepting guild): what a field copy is told
    /// with `Field::declare_war` before the tide.
    pub fn wars_for(&self, field: u8, tide: u32) -> Vec<(u64, u64, u64)> {
        let g = self.inner.lock().unwrap();
        g.wars.values().filter(|w| w.accepted && w.field == field && w.tide == tide).map(|w| (w.id, w.guilds[0], w.guilds[1])).collect()
    }

    /// The guild an account belongs to (0: none): what a field is told with `Field::set_guild` as she joins.
    pub fn guild_of_account(&self, account: i64) -> u64 {
        self.inner.lock().unwrap().guild_of.get(&account).copied().unwrap_or(0)
    }

    /// A field's `Event::War` end: the winning side (0 or 1, else a draw) and the held ticks. Both guilds are told
    /// and the war is done. False if no such war (already reported by another copy).
    pub fn war_result(&self, war: u64, winner: u8, held: [u32; 2]) -> bool {
        let mut g = self.inner.lock().unwrap();
        let Some(w) = g.wars.get(&war).cloned() else { return false };
        let guild = if winner < 2 { w.guilds[winner as usize] } else { 0 };
        g.commit("wend", &[&war.to_string(), &guild.to_string(), &held[0].to_string(), &held[1].to_string()]);
        g.tell_guilds(w.guilds, &SPush::WarResult { war, winner: guild, held });
        true
    }

    // ---- duels

    pub(crate) fn duel(&self, gw: &Gateway, me: &Me, op: u8, name: &str, now: i64) -> R {
        let other = self.hero_named(gw, name)?;
        if other.id == me.hero {
            return Err(bad("a duel needs two"));
        }
        match op {
            duel_op::CHALLENGE => {
                let mut g = self.inner.lock().unwrap();
                g.duel_offers.retain(|_, exp| *exp > now);
                let in_town = |h: i64| g.online.get(&h).is_some_and(|p| p.place == PLACE_TOWN);
                if !in_town(me.hero) || !in_town(other.id) {
                    return Err(fail(code::REFUSED, "both must be in town"));
                }
                if g.in_duel.contains_key(&me.hero) || g.in_duel.contains_key(&other.id) {
                    return Err(fail(code::BUSY, "already in a duel"));
                }
                if g.ignores(other.account, me.account) {
                    return Err(fail(code::REFUSED, "she is not taking challenges"));
                }
                g.duel_offers.insert((other.id, me.hero), now + DUEL_OFFER_MS);
                g.send(other.id, SPush::DuelChallenge { from: me.hero, name: me.name.clone() });
                Ok(Resp::Ok)
            }
            duel_op::DECLINE => {
                let mut g = self.inner.lock().unwrap();
                if g.duel_offers.remove(&(me.hero, other.id)).is_none() {
                    return Err(fail(code::MISSING, "no such challenge"));
                }
                g.send(other.id, SPush::DuelDeclined { name: me.name.clone() });
                Ok(Resp::Ok)
            }
            _ => {
                // The sheets come from the store before the lock.
                let mine = gw.store.hero(me.hero).map_err(store_err)?.ok_or_else(|| fail(code::MISSING, "no hero"))?;
                let sa = crate::sheet::sheet_of(&*gw.store, &other).map_err(store_err)?;
                let sb = crate::sheet::sheet_of(&*gw.store, &mine).map_err(store_err)?;
                let seed = gw.random();
                let mut g = self.inner.lock().unwrap();
                match g.duel_offers.remove(&(me.hero, other.id)) {
                    Some(exp) if exp > now => {}
                    _ => return Err(fail(code::MISSING, "no such challenge")),
                }
                let in_town = |h: i64| g.online.get(&h).is_some_and(|p| p.place == PLACE_TOWN);
                if !in_town(me.hero) || !in_town(other.id) {
                    return Err(fail(code::REFUSED, "both must be in town"));
                }
                if g.in_duel.contains_key(&me.hero) || g.in_duel.contains_key(&other.id) {
                    return Err(fail(code::BUSY, "already in a duel"));
                }
                let id = g.next_duel.max(1);
                g.next_duel = id + 1;
                let run = open_duel(id, [other.id, me.hero], [other.name.clone(), me.name.clone()], [&sa, &sb], seed);
                for k in 0..2 {
                    g.in_duel.insert(run.heroes[k], id);
                    g.send(run.heroes[k], SPush::DuelStart { duel: id, foe: run.heroes[1 - k], name: run.names[1 - k].clone(), seed });
                }
                g.duels.insert(id, run);
                Ok(Resp::Ok)
            }
        }
    }

    /// A duellist's town direction (0..8) steers her in the yard; her weapon fires by itself.
    pub fn duel_input(&self, hero: i64, dir: u8) {
        let mut g = self.inner.lock().unwrap();
        let Some(&id) = g.in_duel.get(&hero) else { return };
        if let Some(d) = g.duels.get_mut(&id) {
            let k = (d.heroes[1] == hero) as usize;
            d.input[k] = dir.min(8) as u16;
        }
    }

    /// One town step of every duel: `DUEL_TICKS_PER_STEP` core ticks, then the ends (a down, three minutes, or a
    /// duellist gone: she forfeits). Returns the results of this step as (duel, winner, loser, draw).
    pub fn run_duels(&self) -> Vec<(u64, i64, i64, bool)> {
        let mut g = self.inner.lock().unwrap();
        let mut done = Vec::new();
        let ids: Vec<u64> = g.duels.keys().copied().collect();
        for id in ids {
            let gone: Vec<bool> = {
                let d = &g.duels[&id];
                d.heroes.iter().map(|h| !g.online.get(h).is_some_and(|p| p.place == PLACE_TOWN)).collect()
            };
            let d = g.duels.get_mut(&id).unwrap();
            let mut end = match (gone[0], gone[1]) {
                (true, true) => Some((d.heroes[0], d.heroes[1], true)),
                (true, false) => Some((d.heroes[1], d.heroes[0], false)),
                (false, true) => Some((d.heroes[0], d.heroes[1], false)),
                _ => None,
            };
            for _ in 0..DUEL_TICKS_PER_STEP {
                if end.is_some() {
                    break;
                }
                let mut inputs = vec![0u16; d.field.heroes().len()];
                for k in 0..2 {
                    inputs[d.ids[k] as usize] = d.input[k];
                }
                d.field.step(&inputs);
                for e in d.field.events() {
                    if let Event::Duel { state, winner, loser } = *e {
                        if state == DUEL_WON || state == DUEL_DRAW {
                            let who = |slot: u16| d.heroes[(d.ids[1] == slot) as usize];
                            end = Some((who(winner), who(loser), state == DUEL_DRAW));
                        }
                    }
                }
            }
            if let Some((w, l, draw)) = end {
                let d = g.duels.remove(&id).unwrap();
                for h in d.heroes {
                    g.in_duel.remove(&h);
                    g.send(h, SPush::DuelResult { duel: id, winner: w, loser: l, draw });
                }
                g.commit("duel", &[&id.to_string(), &w.to_string(), &l.to_string(), &(draw as u8).to_string()]);
                done.push((id, w, l, draw));
            }
        }
        done
    }

    pub fn in_duel(&self, hero: i64) -> bool {
        self.inner.lock().unwrap().in_duel.contains_key(&hero)
    }

    // ---- the mark's book

    /// What a field reports of her mark as she leaves it: carried, with her last strike `struck_ago` ticks before
    /// `now` (ms), into her next outing.
    pub fn note_mark(&self, hero: i64, marked: bool, struck_ago: u32, now: i64) {
        let at = if struck_ago == NEVER { i64::MIN } else { now - struck_ago as i64 * 1000 / TICK_HZ as i64 };
        let mut g = self.inner.lock().unwrap();
        if g.marks.get(&hero) == Some(&(marked, at)) || (!marked && at == i64::MIN && !g.marks.contains_key(&hero)) {
            return;
        }
        g.commit("mark", &[&hero.to_string(), &(marked as u8).to_string(), &at.to_string()]);
    }

    /// Fills her outing's mark and last strike from the book (unmarked, never struck, if it has nothing).
    pub fn outing_mark(&self, hero: i64, now: i64, o: &mut Outing) {
        let g = self.inner.lock().unwrap();
        let Some(&(marked, at)) = g.marks.get(&hero) else { return };
        o.marked = marked;
        o.struck_ago = if at == i64::MIN {
            NEVER
        } else {
            let ticks = (now - at).max(0) * TICK_HZ as i64 / 1000;
            if ticks >= MARK_WAIT_TICKS as i64 { NEVER } else { ticks as u32 }
        };
    }
}

/// A duel's yard with both heroes in it and the duel started.
pub fn open_duel(id: u64, heroes: [i64; 2], names: [String; 2], sheets: [&realm_core::Sheet; 2], seed: u64) -> DuelRun {
    let mut field = Field::open_duel(seed, Config { monsters: YARD_POOL, threads: 1 });
    let spots = field.yard_spots();
    let a = field.join(sheets[0], &Outing::new(), spots[0].0, spots[0].1);
    let b = field.join(sheets[1], &Outing::new(), spots[1].0, spots[1].1);
    field.start_duel(a, b);
    DuelRun { id, heroes, names, ids: [a, b], field, input: [0, 0] }
}
