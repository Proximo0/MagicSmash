//! The world's part of the gateway wire: one request type (`T_WORLD`, a sub-byte after it), one reply type
//! (`R_WORLD`), and pushes under `P_WORLD` with tag 0. Layouts are in `docs/realm/world.md`.

use crate::proto::{put_str, read_str, WireRead};
use realm_server::{put_u16, put_u32, put_u64, Rd};

/// Its tags (`proto::ranges::WORLD`).
pub const T_WORLD: u8 = 0x60;
pub const R_WORLD: u8 = 0x91;
pub const P_WORLD: u8 = 0xB1;

const W_BOARD: u8 = 1;
const W_LEAVE_QUEUE: u8 = 2;
const W_BOT_TICKET: u8 = 3;
const W_RECALL: u8 = 4;
const W_VAULT_OPEN: u8 = 5;
const W_VAULT_JOIN: u8 = 6;

const WR_BOARD: u8 = 1;
const WR_QUEUED: u8 = 2;
const WR_VAULT: u8 = 3;
const WR_MOVED: u8 = 4;
const WR_NEWS: u8 = 5;

/// `WResp::News` kinds.
pub const NEWS_FIELD_BOSS: u8 = 1;
pub const NEWS_WORLD_BOSS: u8 = 2;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum WReq {
    /// Every field's countdowns, the world boss's next ride, the copies and the queue.
    Board,
    /// Stop waiting for a place.
    LeaveQueue { hero: i64 },
    /// Dev bots only (`--dev-bots`): a field ticket for a hero the host plays itself for `ticks`.
    BotTicket { hero: i64, field: u8, ticks: u32 },
    /// Takes a hero the host plays out of her field (banked, as a kick).
    Recall { hero: i64 },
    /// Opens a vault (row 0..4, 5 the class trial) with seals for this hero, the party's leader: costs her a VAULT
    /// KEY of the vault's field. `drive_ticks` > 0 (dev bots only): the host plays her.
    VaultOpen { hero: i64, vault: u8, seals: u8, drive_ticks: u32 },
    /// Enters an open vault by the code its leader was given (her party).
    VaultJoin { hero: i64, code: u64, drive_ticks: u32 },
}

/// One field's line on the board.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BoardField {
    pub field: u8,
    pub tide_in: u32,
    pub tide_left: u32,
    pub boss: u8,
    pub boss_in: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum WResp {
    Board { clock: u64, fields: Vec<BoardField>, world_field: u8, world_in: u32, queue: u32, copies: Vec<(u8, u8, u32)>, vaults: u32 },
    /// The realm (or the field) is full: her place in the queue, of how many. Pushed again as it changes; the
    /// ticket comes as a `Resp::Ticket` push.
    Queued { hero: i64, field: u8, place: u32, of: u32 },
    /// A vault ticket: the vault's code (for the party), where its host is, the ticket.
    Vault { code: u64, vault: u8, seals: u8, host: String, port: u16, ticket: u64 },
    /// Her copy was closed into another: send HELLO with the same ticket to this port (rules section 11).
    Moved { hero: i64, field: u8, copy: u8, host: String, port: u16, ticket: u64 },
    /// Announced to the realm: a field boss rises (`NEWS_FIELD_BOSS`, ten minutes before) or the world boss rides
    /// (`NEWS_WORLD_BOSS`, thirty minutes before) in a field, in this many ticks.
    News { kind: u8, field: u8, boss: u8, in_ticks: u32 },
}

impl WReq {
    pub fn put(&self, w: &mut Vec<u8>) {
        match self {
            WReq::Board => w.push(W_BOARD),
            WReq::LeaveQueue { hero } => {
                w.push(W_LEAVE_QUEUE);
                put_u64(w, *hero as u64);
            }
            WReq::BotTicket { hero, field, ticks } => {
                w.push(W_BOT_TICKET);
                put_u64(w, *hero as u64);
                w.push(*field);
                put_u32(w, *ticks);
            }
            WReq::Recall { hero } => {
                w.push(W_RECALL);
                put_u64(w, *hero as u64);
            }
            WReq::VaultOpen { hero, vault, seals, drive_ticks } => {
                w.push(W_VAULT_OPEN);
                put_u64(w, *hero as u64);
                w.extend_from_slice(&[*vault, *seals]);
                put_u32(w, *drive_ticks);
            }
            WReq::VaultJoin { hero, code, drive_ticks } => {
                w.push(W_VAULT_JOIN);
                put_u64(w, *hero as u64);
                put_u64(w, *code);
                put_u32(w, *drive_ticks);
            }
        }
    }

    pub fn read(r: &mut Rd) -> Option<WReq> {
        let hero = |r: &mut Rd| r.u64().map(|v| v as i64);
        Some(match r.u8()? {
            W_BOARD => WReq::Board,
            W_LEAVE_QUEUE => WReq::LeaveQueue { hero: hero(r)? },
            W_BOT_TICKET => WReq::BotTicket { hero: hero(r)?, field: r.u8()?, ticks: r.u32()? },
            W_RECALL => WReq::Recall { hero: hero(r)? },
            W_VAULT_OPEN => WReq::VaultOpen { hero: hero(r)?, vault: r.u8()?, seals: r.u8()?, drive_ticks: r.u32()? },
            W_VAULT_JOIN => WReq::VaultJoin { hero: hero(r)?, code: r.u64()?, drive_ticks: r.u32()? },
            _ => return None,
        })
    }
}

impl WResp {
    pub fn put(&self, w: &mut Vec<u8>) {
        match self {
            WResp::Board { clock, fields, world_field, world_in, queue, copies, vaults } => {
                w.push(WR_BOARD);
                put_u64(w, *clock);
                w.push(fields.len() as u8);
                for f in fields {
                    w.push(f.field);
                    put_u32(w, f.tide_in);
                    put_u32(w, f.tide_left);
                    w.push(f.boss);
                    put_u32(w, f.boss_in);
                }
                w.push(*world_field);
                put_u32(w, *world_in);
                put_u32(w, *queue);
                put_u16(w, copies.len() as u16);
                for &(f, c, n) in copies {
                    w.extend_from_slice(&[f, c]);
                    put_u32(w, n);
                }
                put_u32(w, *vaults);
            }
            WResp::Queued { hero, field, place, of } => {
                w.push(WR_QUEUED);
                put_u64(w, *hero as u64);
                w.push(*field);
                put_u32(w, *place);
                put_u32(w, *of);
            }
            WResp::Vault { code, vault, seals, host, port, ticket } => {
                w.push(WR_VAULT);
                put_u64(w, *code);
                w.extend_from_slice(&[*vault, *seals]);
                put_str(w, host);
                put_u16(w, *port);
                put_u64(w, *ticket);
            }
            WResp::Moved { hero, field, copy, host, port, ticket } => {
                w.push(WR_MOVED);
                put_u64(w, *hero as u64);
                w.extend_from_slice(&[*field, *copy]);
                put_str(w, host);
                put_u16(w, *port);
                put_u64(w, *ticket);
            }
            WResp::News { kind, field, boss, in_ticks } => {
                w.push(WR_NEWS);
                w.extend_from_slice(&[*kind, *field, *boss]);
                put_u32(w, *in_ticks);
            }
        }
    }

    pub fn read(r: &mut Rd) -> Option<WResp> {
        Some(match r.u8()? {
            WR_BOARD => {
                let clock = r.u64()?;
                let n = r.count8()?;
                let fields = (0..n)
                    .map(|_| Some(BoardField { field: r.u8()?, tide_in: r.u32()?, tide_left: r.u32()?, boss: r.u8()?, boss_in: r.u32()? }))
                    .collect::<Option<Vec<_>>>()?;
                let (world_field, world_in, queue) = (r.u8()?, r.u32()?, r.u32()?);
                let m = r.count16()?;
                let copies = (0..m).map(|_| Some((r.u8()?, r.u8()?, r.u32()?))).collect::<Option<Vec<_>>>()?;
                WResp::Board { clock, fields, world_field, world_in, queue, copies, vaults: r.u32()? }
            }
            WR_QUEUED => WResp::Queued { hero: r.u64()? as i64, field: r.u8()?, place: r.u32()?, of: r.u32()? },
            WR_VAULT => WResp::Vault { code: r.u64()?, vault: r.u8()?, seals: r.u8()?, host: read_str(r)?, port: r.u16()?, ticket: r.u64()? },
            WR_MOVED => WResp::Moved { hero: r.u64()? as i64, field: r.u8()?, copy: r.u8()?, host: read_str(r)?, port: r.u16()?, ticket: r.u64()? },
            WR_NEWS => WResp::News { kind: r.u8()?, field: r.u8()?, boss: r.u8()?, in_ticks: r.u32()? },
            _ => return None,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_world_message_reads_back_as_written() {
        let reqs = [
            WReq::Board,
            WReq::LeaveQueue { hero: 5 },
            WReq::BotTicket { hero: 6, field: 3, ticks: 900 },
            WReq::Recall { hero: 7 },
            WReq::VaultOpen { hero: 8, vault: 2, seals: 4, drive_ticks: 0 },
            WReq::VaultJoin { hero: 9, code: u64::MAX - 3, drive_ticks: 12 },
        ];
        for q in reqs {
            let mut w = Vec::new();
            q.put(&mut w);
            let mut r = Rd::new(&w);
            assert_eq!(WReq::read(&mut r), Some(q));
            assert_eq!(r.left(), 0);
        }
        let resps = [
            WResp::Board {
                clock: 123_456_789,
                fields: vec![BoardField { field: 2, tide_in: 30, tide_left: 0, boss: 2, boss_in: 9_000 }],
                world_field: 4,
                world_in: 77,
                queue: 12,
                copies: vec![(0, 0, 801), (0, 1, 20)],
                vaults: 3,
            },
            WResp::Queued { hero: 3, field: 1, place: 4, of: 9 },
            WResp::Vault { code: 99, vault: 1, seals: 8, host: "h".into(), port: 7801, ticket: 5 },
            WResp::Moved { hero: 3, field: 0, copy: 1, host: String::new(), port: 7802, ticket: 6 },
            WResp::News { kind: NEWS_WORLD_BOSS, field: 5, boss: 7, in_ticks: 36_000 },
        ];
        for p in resps {
            let mut w = Vec::new();
            p.put(&mut w);
            let mut r = Rd::new(&w);
            assert_eq!(WResp::read(&mut r), Some(p));
            assert_eq!(r.left(), 0);
        }
    }
}
