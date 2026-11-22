//! Vaults (rules section 10): the Four of Wands run for a party of up to eight on this core with a `Vault` row
//! instead of a field's. An arena of 2,048 px, a timeline of what is born each minute, bosses at fixed minutes
//! (the last ends the run), seals that harden it, no waystones. The class trial is a row for one hero.

use crate::boss::Boss;
use crate::events::Event;
use crate::monster::level_scale;
use crate::tables::*;
use crate::tide::coin_at;
use crate::{Config, Field, terrain};

pub const RUN_GOING: u8 = 0;
pub const RUN_WON: u8 = 1;
pub const RUN_LOST: u8 = 2;

/// A vault's run: which vault, its seals, and where the timeline is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct VaultRun {
    pub vault: u8,
    pub seals: u8,
    pub state: u8,
    /// The tick the first hero arrived (the timeline runs from there); 0 until then.
    pub started: u32,
    /// Minutes whose clutch has been born (the minute index plus one).
    pub minute_seen: u8,
    /// Bosses risen so far.
    pub next_boss: u8,
    /// The tick the run ended.
    pub ended: u32,
}

impl Field {
    /// A vault (0..4 by level 20 to 60, 5 the class trial) with `seals` (at most the row's), from a seed.
    pub fn open_vault(vault: u8, seals: u8, seed: u64, cfg: Config) -> Field {
        let v = vault.min(VAULTS.len() as u8 - 1);
        let row = &VAULTS[v as usize];
        let seals = seals.min(row.seals_max);
        let mut f = Field::open_with(row.field, seed, cfg, terrain::build_vault(row.field, seed));
        f.realm.vault = Some(VaultRun { vault: v, seals, state: RUN_GOING, started: 0, minute_seen: 0, next_boss: 0, ended: 0 });
        f.m.scale_pct = seal_scale(seals);
        f
    }

    pub fn vault(&self) -> Option<&VaultRun> {
        self.realm.vault.as_ref()
    }

    /// A vault has room for another hero (at most the row's party).
    pub fn vault_has_room(&self) -> bool {
        match &self.realm.vault {
            Some(v) => self.heroes.iter().filter(|h| h.present).count() < VAULTS[v.vault as usize].party_max as usize,
            None => true,
        }
    }

    /// Ticks of the run so far (0 before the first hero).
    pub fn vault_ticks(&self) -> u32 {
        match &self.realm.vault {
            Some(v) if v.started > 0 => self.tick - v.started + 1,
            _ => 0,
        }
    }

    /// The tick of the vault's timeline the next births follow.
    pub(crate) fn vault_target(&self) -> u32 {
        let Some(v) = &self.realm.vault else { return 0 };
        let row = &VAULTS[v.vault as usize];
        let minute = (self.vault_ticks() / secs(60)).min(row.minutes as u32 - 1) as usize;
        let n = self.heroes.iter().filter(|h| h.present).count() as u32;
        row.timeline[minute].target as u32 * (n + 2) / (VAULT_PARTY_MAX as u32 + 2)
    }

    /// Births go on while a vault is running (and always in a field).
    pub(crate) fn vault_births_on(&self) -> bool {
        self.realm.vault.as_ref().is_none_or(|v| v.state == RUN_GOING)
    }

    pub(crate) fn vault_begin(&mut self) {
        let Some(mut run) = self.realm.vault else {
            return;
        };
        if run.state != RUN_GOING {
            return;
        }
        let present = self.heroes.iter().filter(|h| h.present).count();
        if run.started == 0 {
            if present == 0 {
                return;
            }
            run.started = self.tick;
            self.events.push(Event::Vault { state: VAULT_START, n: 0 });
        }
        let row = &VAULTS[run.vault as usize];
        let t = self.tick - run.started + 1;
        let minute = t / secs(60);
        if minute < row.minutes as u32 && run.minute_seen as u32 <= minute {
            run.minute_seen = minute as u8 + 1;
            let m = row.timeline[minute as usize];
            let kind = row.first_kind + m.burst_kind % row.kind_count;
            for _ in 0..m.burst {
                let Some((x, y)) = self.find_birth() else {
                    break;
                };
                let Some(slot) = self.free.pop() else { break };
                self.birth(slot as usize, kind, row.level, 0, x, y);
                self.spawned.push(slot);
            }
        }
        if (run.next_boss as usize) < row.bosses.len() && self.realm.boss.is_none() {
            let (at, which) = row.bosses[run.next_boss as usize];
            if at != NO_MINUTE && t >= at as u32 * secs(60) {
                run.next_boss += 1;
                let party = present.max(1) as u64;
                let seal = 100 + SEAL_PCT as u64 * run.seals as u64;
                let base = row.hp_base as u64 + row.hp_per_hero as u64 * party;
                let hp = level_scale(base as u32, row.level, HEALTH_PCT_PER_LEVEL) as u64 * BOSSES[which as usize].health_pct as u64 / 100 * seal / 100;
                let (x, y) = self.terrain.nearest_open(self.terrain.heart.0, self.terrain.heart.1);
                self.realm.vault = Some(run);
                self.spawn_boss(which, hp.clamp(1, u32::MAX as u64) as u32, row.level, x, y, seal as u32, u64::MAX, false, run.next_boss as u32);
                self.events.push(Event::Vault { state: VAULT_ACT, n: run.next_boss });
            }
        }
        // The party fails when every hero is down, or when the time is up.
        let all_down = present > 0 && self.heroes.iter().all(|h| !h.present || !h.alive());
        let limit = row.minutes as u32 * secs(60) + VAULT_OVERTIME;
        self.realm.vault = Some(run);
        if all_down || t >= limit {
            self.vault_lost(t);
        }
    }

    /// The run is lost: coin for the minutes survived.
    fn vault_lost(&mut self, t: u32) {
        let Some(mut run) = self.realm.vault else {
            return;
        };
        let row = &VAULTS[run.vault as usize];
        run.state = RUN_LOST;
        run.ended = self.tick;
        self.realm.vault = Some(run);
        self.births = false;
        let minutes = (t / secs(60)).min(row.minutes as u32);
        self.events.push(Event::Vault { state: VAULT_LOST, n: minutes as u8 });
        let coin = coin_at(COIN_VAULT_PER_MINUTE * minutes, row.level);
        let list: Vec<(u16, u32)> = self.heroes.iter().enumerate().filter(|(_, h)| h.present).map(|(i, _)| (i as u16, coin)).collect();
        self.pay(R_VAULT_LOSS, row.field, row.level, run.seals, list, coin, usize::MAX);
    }

    /// The last boss fell: a VAULT CHEST for every hero past the floor.
    pub(crate) fn vault_won(&mut self, list: Vec<(u16, u32)>) {
        let Some(mut run) = self.realm.vault else {
            return;
        };
        if run.state != RUN_GOING {
            return;
        }
        let row = &VAULTS[run.vault as usize];
        run.state = RUN_WON;
        run.ended = self.tick;
        self.realm.vault = Some(run);
        self.births = false;
        self.events.push(Event::Vault { state: VAULT_WON, n: run.seals });
        self.pay(R_VAULT_CHEST, row.field, row.level, run.seals, list, coin_at(COIN_VAULT_CHEST, row.level), usize::MAX);
        for h in self.heroes.iter_mut() {
            h.boss_contrib = 0;
        }
    }

    /// The vault's running boss (for tests and the client): same as `boss`.
    pub fn vault_boss(&self) -> Option<&Boss> {
        self.realm.boss.as_ref()
    }
}

/// Monster health and damage percent at a number of seals.
pub fn seal_scale(seals: u8) -> u32 {
    100 + SEAL_PCT * seals as u32
}

/// The rolls a vault chest holds: the contract's two, and one more per seal.
pub fn chest_rolls(seals: u8) -> u8 {
    ROLLS_VAULT_CHEST + seals
}
