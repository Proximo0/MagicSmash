//! Social on the gateway wire (job T1, `proto::ranges::SOCIAL`): `Req::Social` under its tags `T_SOC_FIRST..=
//! T_SOC_LAST`, `Resp::Social` under `R_SOCIAL` and `Resp::SocialPush` under `P_SOCIAL`. Chat's flood limit and
//! mutes are `Social::gate`, inside `Social::handle`.

use super::wire::*;
use crate::gateway::{Gateway, Session};
use crate::proto::{Req, Resp, Served, Thing, WireModule};

pub static WIRE: WireModule = WireModule { module: "social", encode_req, decode_req, encode_resp, decode_resp, serve, examples };

fn encode_req(q: &Req) -> Option<(u8, Vec<u8>)> {
    let Req::Social(q) = q else { return None };
    Some(q.encode())
}

fn decode_req(t: u8, b: &[u8]) -> Option<Req> {
    if !(T_SOC_FIRST..=T_SOC_LAST).contains(&t) {
        return None;
    }
    SReq::decode(t, b).map(Req::Social)
}

fn encode_resp(p: &Resp) -> Option<(u8, Vec<u8>)> {
    match p {
        Resp::Social(s) => Some((R_SOCIAL, s.encode())),
        Resp::SocialPush(s) => Some((P_SOCIAL, s.encode())),
        _ => None,
    }
}

fn decode_resp(t: u8, b: &[u8]) -> Option<Resp> {
    match t {
        R_SOCIAL => SResp::decode(b).map(Resp::Social),
        P_SOCIAL => SPush::decode(b).map(Resp::SocialPush),
        _ => None,
    }
}

fn serve(gw: &Gateway, s: &mut Session, account: i64, req: Req) -> Served {
    let Req::Social(q) = req else { return Err(req) };
    Ok(Ok(gw.social.handle(gw, s, account, q)))
}

fn examples() -> (Vec<Req>, Vec<Resp>) {
    let item = crate::proto::ItemInfo { id: 5, base: 2, gear_slot: 1, level: 10, rarity: 2, lines: vec![(0, 3)], sockets: 1, kind: 1, tab: 0, slot: 4, plus: 0, socketed: vec![0] };
    let reqs = vec![
        SReq::Talk { hero: 1, chan: chan::WHISPER, to: "Bob".into(), text: "hi".into() },
        SReq::PartyInvite { hero: 1, name: "Bob".into() },
        SReq::PartyAnswer { hero: 1, inviter: 2, accept: true },
        SReq::PartyLeave { hero: 1 },
        SReq::PartyKick { hero: 1, target: 2 },
        SReq::PartyLead { hero: 1, target: 2 },
        SReq::PartyGo { hero: 1, field: 3 },
        SReq::PartyInfo { hero: 1 },
        SReq::GuildCreate { hero: 1, name: "The Pale".into() },
        SReq::GuildInvite { hero: 1, name: "Bob".into() },
        SReq::GuildAnswer { hero: 1, guild: 9, accept: false },
        SReq::GuildLeave { hero: 1 },
        SReq::GuildKick { hero: 1, target: 5 },
        SReq::GuildRank { hero: 1, target: 5, rank: 1 },
        SReq::GuildPerms { hero: 1, rank: 2, perms: 0x1F },
        SReq::GuildMotd { hero: 1, text: "m".into() },
        SReq::GuildPost { hero: 1, text: "p".into() },
        SReq::GuildUnpost { hero: 1, post: 4 },
        SReq::GuildBank { hero: 1, what: Thing::Item(7), tab: 2, deposit: true },
        SReq::GuildBankView { hero: 1, tab: 3 },
        SReq::GuildInfo { hero: 1 },
        SReq::GuildDisband { hero: 1 },
        SReq::FriendAdd { hero: 1, name: "Bob".into() },
        SReq::FriendAnswer { hero: 1, from: 2, accept: true },
        SReq::FriendRemove { hero: 1, target: 2 },
        SReq::Ignore { hero: 1, name: "Bob".into(), on: true },
        SReq::Lists { hero: 1 },
        SReq::Report { hero: 1, name: "Bob".into(), reason: 2, text: "gold".into() },
    ];
    let party = PartyView { id: 3, leader: 1, copy: Some((2, 1)), members: vec![PartyMember { hero: 1, name: "Ann".into(), class: 2, level: 7, online: true }] };
    let guild = GuildView {
        id: 4,
        name: "G".into(),
        motd: "m".into(),
        my_rank: 1,
        perms: [255, 100, 12, 4],
        members: vec![GuildMember { account: 5, name: "Ann".into(), rank: 0, online: false }],
        board: vec![Post { id: 1, author: "Ann".into(), text: "t".into(), at: 99 }],
    };
    let resps = vec![
        SResp::Party(Some(party.clone())),
        SResp::Party(Some(PartyView { copy: None, ..party.clone() })),
        SResp::Party(None),
        SResp::Guild(Some(guild)),
        SResp::Guild(None),
        SResp::GuildCreated(4),
        SResp::Bank { items: vec![item], stacks: vec![(1, 20)] },
        SResp::Lists(Lists { friends: vec![FriendRow { account: 2, name: "B".into(), online: true, place: 1 }], pending: vec![(3, "C".into())], ignores: vec![(4, "D".into())] }),
        SResp::Reported(12),
    ];
    let pushes = vec![
        SPush::Chat { chan: chan::GUILD, from: "A".into(), to: String::new(), text: "x".into() },
        SPush::PartyInvite { inviter: 2, name: "A".into() },
        SPush::PartyUpdate(Some(party)),
        SPush::PartyGo { field: 1 },
        SPush::GuildInvite { guild: 2, guild_name: "G".into(), from: "A".into() },
        SPush::GuildChanged,
        SPush::FriendRequest { from: 2, name: "A".into() },
        SPush::FriendStatus { account: 2, name: "A".into(), online: false, place: 0 },
        SPush::Notice { text: "muted".into() },
    ];
    let mut out: Vec<Resp> = resps.into_iter().map(Resp::Social).collect();
    out.extend(pushes.into_iter().map(Resp::SocialPush));
    (reqs.into_iter().map(Req::Social).collect(), out)
}
