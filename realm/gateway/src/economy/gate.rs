//! The economy on the gateway wire (job E1, `proto::ranges::ECONOMY`): `Req::Econ` under `T_ECON`, `Resp::Econ`
//! under `R_ECON`, `Resp::EconPush` under `P_ECON`, and the operators' trade and market freezes.

use super::wire::*;
use crate::gateway::{now_ms, Gateway, Session};
use crate::proto::{body, code, whole, Req, Resp, Served, Thing, WireModule};

pub static WIRE: WireModule = WireModule { module: "economy", encode_req, decode_req, encode_resp, decode_resp, serve, examples };

fn encode_req(q: &Req) -> Option<(u8, Vec<u8>)> {
    let Req::Econ(e) = q else { return None };
    Some((T_ECON, body(|w| e.put(w))))
}

fn decode_req(t: u8, b: &[u8]) -> Option<Req> {
    if t != T_ECON {
        return None;
    }
    whole(b, EReq::read).map(Req::Econ)
}

fn encode_resp(p: &Resp) -> Option<(u8, Vec<u8>)> {
    match p {
        Resp::Econ(e) => Some((R_ECON, body(|w| e.put(w)))),
        Resp::EconPush(e) => Some((P_ECON, body(|w| e.put(w)))),
        _ => None,
    }
}

fn decode_resp(t: u8, b: &[u8]) -> Option<Resp> {
    match t {
        R_ECON => whole(b, EResp::read).map(Resp::Econ),
        P_ECON => whole(b, EResp::read).map(Resp::EconPush),
        _ => None,
    }
}

fn serve(gw: &Gateway, _s: &mut Session, account: i64, req: Req) -> Served {
    let Req::Econ(e) = req else { return Err(req) };
    let trade = matches!(e, EReq::TradeInvite { .. } | EReq::TradeAccept { .. } | EReq::TradeOffer { .. } | EReq::TradeConfirm { .. });
    let market = matches!(e, EReq::MarketList { .. } | EReq::MarketBuy { .. });
    if (trade && realm_ops::switches::trade_frozen()) || (market && realm_ops::switches::market_frozen()) {
        return Ok(Ok(Resp::Err { code: code::DISABLED, msg: "frozen by the operators for the moment".into() }));
    }
    Ok(Ok(gw.economy.handle(account, e, now_ms())))
}

fn examples() -> (Vec<Req>, Vec<Resp>) {
    let info = crate::proto::ItemInfo { id: 5, base: 2, gear_slot: 1, level: 10, rarity: 2, lines: vec![(0, 3)], sockets: 2, kind: 1, tab: 0, slot: 4, plus: 1, socketed: vec![2011, 0] };
    let item = EItem { info, plus: 1, bound: true, socketed: [2011, 0] };
    let reqs = vec![
        EReq::MerchantList { hero: 1 },
        EReq::MerchantBuy { hero: 1, offer: 2, count: 3 },
        EReq::MerchantSell { hero: 1, what: Thing::Stack(5, 6) },
        EReq::Buyback { hero: 1 },
        EReq::BuybackTake { hero: 1, entry: 4 },
        EReq::TradeInvite { hero: 1, with_name: "Bo".into() },
        EReq::TradeAccept { hero: 1, session: 9 },
        EReq::TradeOffer { hero: 1, session: 9, items: vec![3, 4], stacks: vec![(1, 50)] },
        EReq::TradeConfirm { hero: 1, session: 9, version: 2 },
        EReq::TradeCancel { hero: 1, session: 9 },
        EReq::TradeView { hero: 1, session: 9 },
        EReq::MarketList { hero: 1, what: Thing::Item(7), price: 500, hours: 24 },
        EReq::MarketSearch { hero: 1, q: Search { gear_slot: 255, rarity_min: 1, level_min: 2, level_max: 30, stack: 0, price_max: 900, offset: 40 } },
        EReq::MarketBuy { hero: 1, listing: 8 },
        EReq::MarketCancel { hero: 1, listing: 8 },
        EReq::MarketMine { hero: 1 },
        EReq::MarketPrices,
        EReq::LetterSend { hero: 1, to_name: "Bo".into(), text: "for you".into(), things: vec![Thing::Item(3), Thing::Stack(1, 9)], cod: 10 },
        EReq::Inbox { hero: 1 },
        EReq::Outbox { hero: 1 },
        EReq::LetterTake { hero: 1, letter: 2 },
        EReq::LetterRefuse { hero: 1, letter: 2 },
        EReq::LetterRecall { hero: 1, letter: 2 },
        EReq::BankTabs { hero: 1 },
        EReq::BankTabBuy { hero: 1, owned: 2 },
    ];
    let trade = TradeView {
        session: 9,
        state: 1,
        me: 1,
        other: 2,
        other_name: "Bo".into(),
        version: 3,
        lock_ms: 500,
        my_items: vec![item.clone()],
        my_stacks: vec![(1, 40)],
        their_items: vec![],
        their_stacks: vec![],
        my_ok: true,
        their_ok: false,
    };
    let letter = LetterInfo { id: 3, from: "Ann".into(), to: "Bo".into(), text: "hi".into(), cod: 0, expires: 99, items: vec![item.clone()], stacks: vec![(1, 2)] };
    let listing = |item: Option<EItem>, stack: Option<(u32, u64)>, mine: bool| ListingInfo { id: 4, seller: "Ann".into(), price: 70, expires: 1000, item, stack, mine };
    let resps = vec![
        EResp::Ok,
        EResp::Offers(vec![Offer { id: 0, kind: 0, stack: 100, item: None, price: 25, left: 20 }, Offer { id: 1, kind: 2, stack: 0, item: Some(item.clone()), price: 400, left: 1 }]),
        EResp::Coin(1234),
        EResp::Buybacks(vec![BuybackInfo { id: 6, item: item.clone(), price: 80, secs_left: 300 }]),
        EResp::Trade(trade),
        EResp::Listed { id: 4, fee: 7 },
        EResp::Listings(vec![listing(Some(item), None, true), listing(None, Some((1, 30)), false), listing(None, None, false)]),
        EResp::Letters(vec![letter]),
        EResp::Prices(vec![ClassPrice { rarity: 2, band: 1, median: 300, n: 12 }]),
        EResp::Notice { kind: notice::SOLD, a: 4, b: 70, text: "Bo".into() },
        EResp::BankTabs { owned: 2, max: 8, price: 12_000 },
    ];
    let mut out: Vec<Resp> = resps.iter().cloned().map(Resp::Econ).collect();
    out.extend(resps.into_iter().map(Resp::EconPush));
    (reqs.into_iter().map(Req::Econ).collect(), out)
}
