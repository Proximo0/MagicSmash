//! Homes on the gateway wire (job H1, `proto::ranges::HOMES`): `Req::Home` under `T_HOME`, `Resp::Home` under
//! `R_HOME` and `Resp::HomePush` under `P_HOME`.

use super::wire::*;
use crate::gateway::{Gateway, Session};
use crate::proto::{body, whole, ItemInfo, Req, Resp, Served, WireModule};

pub static WIRE: WireModule = WireModule { module: "homes", encode_req, decode_req, encode_resp, decode_resp, serve, examples };

fn encode_req(q: &Req) -> Option<(u8, Vec<u8>)> {
    let Req::Home(q) = q else { return None };
    Some((T_HOME, body(|w| q.put(w))))
}

fn decode_req(t: u8, b: &[u8]) -> Option<Req> {
    if t != T_HOME {
        return None;
    }
    whole(b, HReq::read).map(Req::Home)
}

fn encode_resp(p: &Resp) -> Option<(u8, Vec<u8>)> {
    match p {
        Resp::Home(h) => Some((R_HOME, body(|w| h.put(w)))),
        Resp::HomePush(h) => Some((P_HOME, body(|w| h.put(w)))),
        _ => None,
    }
}

fn decode_resp(t: u8, b: &[u8]) -> Option<Resp> {
    match t {
        R_HOME => whole(b, HResp::read).map(Resp::Home),
        P_HOME => whole(b, HResp::read).map(Resp::HomePush),
        _ => None,
    }
}

fn serve(gw: &Gateway, s: &mut Session, account: i64, req: Req) -> Served {
    let Req::Home(q) = req else { return Err(req) };
    Ok(Ok(gw.homes.handle(gw, s, account, q)))
}

fn examples() -> (Vec<Req>, Vec<Resp>) {
    let item = |slot: u32| ItemInfo { id: 5, base: 9000, gear_slot: 5, level: 1, rarity: 0, lines: vec![(0, 0)], sockets: 0, kind: 7, tab: 0, slot, plus: 0, socketed: vec![] };
    let reqs = vec![
        HReq::Streets { hero: 1 },
        HReq::Street { hero: 1, street: 3 },
        HReq::Buy { hero: 1, street: 2, plot: 5 },
        HReq::Rent { hero: 1, street: 2, plot: 5, weeks: 3 },
        HReq::Renew { hero: 1, weeks: 1 },
        HReq::Release { hero: 1 },
        HReq::Rule { hero: 1, rule: 2 },
        HReq::Name { hero: 1, name: "The Lantern".into() },
        HReq::Go { hero: 1, kind: 6, arg: 77 },
        HReq::House { hero: 1 },
        HReq::Place { hero: 1, item: 9, cell: 123 },
        HReq::Move { hero: 1, item: 9, cell: 4 },
        HReq::Pickup { hero: 1, item: 9 },
        HReq::Sign { hero: 1, text: "hi".into() },
        HReq::Wipe { hero: 1, entry: 8 },
        HReq::Craft { hero: 1, kind: 103 },
        HReq::Catalogue { hero: 1 },
        HReq::Strike { hero: 1 },
        HReq::YardBoard { hero: 1 },
        HReq::Sit { hero: 1 },
        HReq::Stand { hero: 1 },
        HReq::Status { hero: 1 },
        HReq::Stalls { hero: 1, offset: 40 },
        HReq::Where { hero: 1 },
    ];
    let e = EntryInfo { id: 3, at: 99, name: "Bob".into(), text: "nice".into() };
    let resps = vec![
        HResp::Ok,
        HResp::Streets { open: 2, taken: vec![24, 3], mine: Some(5) },
        HResp::Streets { open: 1, taken: vec![0], mine: None },
        HResp::Street { street: 1, plots: vec![PlotInfo { index: 2, owner: "Ann".into(), status: 2, rule: 1, name: "Home".into(), buy: 5, rent: 6, until: 77 }] },
        HResp::House(HouseView { plot: 4, owner: "Ann".into(), name: "H".into(), rule: 0, status: 1, until: 0, mine: true, items: vec![item(12)], book: vec![e.clone()] }),
        HResp::Moved { item: 5, house: true, cell: 12 },
        HResp::Crafted(item(0)),
        HResp::Paid { plot: 1, until: 5, coin: 6 },
        HResp::Strike { damage: 10, total: 100, dps: 55, count: 10, best: 60 },
        HResp::Board(vec![("Ann".into(), 2, 300)]),
        HResp::Rest { sitting: true, secs: 4, rested_ms: 5, pct: 10 },
        HResp::Stalls(vec![Stall { seller: "Zed".into(), listings: 3, cheapest: 40 }]),
        HResp::Where { kind: 6, arg: 9 },
        HResp::Catalogue(vec![(0, 1001, 4, 60)]),
        HResp::Book(vec![e]),
        HResp::Notice { kind: 0, a: 1, text: "Bob".into() },
    ];
    let mut out: Vec<Resp> = resps.iter().cloned().map(Resp::Home).collect();
    out.extend(resps.into_iter().map(Resp::HomePush));
    (reqs.into_iter().map(Req::Home).collect(), out)
}
