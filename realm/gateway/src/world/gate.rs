//! The world on the gateway wire (job W2, `proto::ranges::WORLD`): `Req::World` under `T_WORLD`, `Resp::World`
//! under `R_WORLD` and `Resp::WorldPush` under `P_WORLD`.

use super::wire::*;
use crate::gateway::{Gateway, Session};
use crate::proto::{body, whole, Req, Resp, Served, WireModule};

pub static WIRE: WireModule = WireModule { module: "world", encode_req, decode_req, encode_resp, decode_resp, serve, examples };

fn encode_req(q: &Req) -> Option<(u8, Vec<u8>)> {
    let Req::World(q) = q else { return None };
    Some((T_WORLD, body(|w| q.put(w))))
}

fn decode_req(t: u8, b: &[u8]) -> Option<Req> {
    if t != T_WORLD {
        return None;
    }
    whole(b, WReq::read).map(Req::World)
}

fn encode_resp(p: &Resp) -> Option<(u8, Vec<u8>)> {
    match p {
        Resp::World(e) => Some((R_WORLD, body(|w| e.put(w)))),
        Resp::WorldPush(e) => Some((P_WORLD, body(|w| e.put(w)))),
        _ => None,
    }
}

fn decode_resp(t: u8, b: &[u8]) -> Option<Resp> {
    match t {
        R_WORLD => whole(b, WResp::read).map(Resp::World),
        P_WORLD => whole(b, WResp::read).map(Resp::WorldPush),
        _ => None,
    }
}

fn serve(gw: &Gateway, s: &mut Session, account: i64, req: Req) -> Served {
    let Req::World(q) = req else { return Err(req) };
    Ok(gw.world_request(s, account, q))
}

fn examples() -> (Vec<Req>, Vec<Resp>) {
    let reqs = vec![
        WReq::Board,
        WReq::LeaveQueue { hero: 5 },
        WReq::BotTicket { hero: 6, field: 3, ticks: 900 },
        WReq::Recall { hero: 7 },
        WReq::VaultOpen { hero: 8, vault: 2, seals: 4, drive_ticks: 0 },
        WReq::VaultJoin { hero: 9, code: u64::MAX - 3, drive_ticks: 12 },
        WReq::Trial { hero: 10 },
    ];
    let resps = vec![
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
        WResp::Vault { code: 99, vault: 1, seals: 8, host: "h".into(), port: 7801, ticket: 5, key: realm_server::TicketKey([3; 16]) },
        WResp::Moved { hero: 3, field: 0, copy: 1, host: String::new(), port: 7802, ticket: 6, key: realm_server::TicketKey([4; 16]) },
        WResp::News { kind: NEWS_WORLD_BOSS, field: 5, boss: 7, in_ticks: 36_000 },
        WResp::Trial { hero: 3, level: 10, passed: false, job: 15, job_level: 40, job_price: 1_447_133 },
    ];
    let mut out: Vec<Resp> = resps.iter().cloned().map(Resp::World).collect();
    out.extend(resps.into_iter().map(Resp::WorldPush));
    (reqs.into_iter().map(Req::World).collect(), out)
}
