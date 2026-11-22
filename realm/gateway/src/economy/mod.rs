//! The economy between players (job E1): NPC merchants, hand-to-hand trade, the market, letters, and the
//! self-found rule. Contract: rules.md section 9, `docs/realm/store.md` (who may, ledger), `docs/realm/economy.md`.
//!
//! The store keeps every thing and every coin; this module decides what a player may ask and what it costs. All
//! writes are the server's (actor 0) after the gateway has checked the hero is the account's; the store still
//! applies TRADE_LOCKED and the self-found rule, and says nothing more than `Refused` (a botter learns nothing).
//! Nothing here reads a wall clock: every call is given `now` in milliseconds, so a simulation can run a game day
//! in a moment.

pub mod letters;
pub mod market;
pub mod merchant;
pub mod prices;
pub mod sim;
pub mod trade;
pub mod wire;
/// Its messages on the gateway wire and its dispatch (`proto::WireModule`).
pub mod gate;

use crate::proto::{code, resp_frame, Resp};
use realm_store::*;
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use wire::{EReq, EResp};

/// Why a request failed.
#[derive(Debug)]
pub enum Fail {
    Store(Error),
    /// Too many requests too fast (`LIMIT_BURST`).
    Slow,
    Bad(String),
}

impl From<Error> for Fail {
    fn from(e: Error) -> Fail {
        Fail::Store(e)
    }
}

pub type R<T> = std::result::Result<T, Fail>;

pub fn bad<T>(s: &str) -> R<T> {
    Err(Fail::Bad(s.into()))
}

/// What the economy has moved, for the simulation and the operator: coin made and destroyed by each part.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Totals {
    /// Coin destroyed as sale tax, listing fees and postage.
    pub tax: u64,
    pub fees: u64,
    pub postage: u64,
    /// Coin the merchants paid for items and materials (new coin: it enters the game here) and took for stock.
    pub npc_paid: u64,
    pub npc_took: u64,
    pub sales: u64,
    pub volume: u64,
    pub listed: u64,
    pub cancelled: u64,
    pub expired: u64,
    pub trades: u64,
    pub letters: u64,
    pub cod_volume: u64,
    pub buybacks: u64,
}

/// One market sale, for the price board and the simulation.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Sale {
    pub time: Millis,
    pub rarity: u8,
    pub level: u16,
    pub gear_slot: u8,
    pub price: u64,
    pub value: u64,
    pub seller: AccountId,
    pub buyer: AccountId,
    pub listed_at: Millis,
    /// For a stack listing: (stack kind, count).
    pub stack: Option<(u32, u64)>,
}

struct Attached {
    room: u32,
    out: Sender<Vec<u8>>,
}

#[derive(Default)]
pub(crate) struct State {
    outs: HashMap<i64, Attached>,
    pub(crate) trades: HashMap<u64, trade::Trade>,
    pub(crate) in_trade: HashMap<i64, u64>,
    pub(crate) next_session: u64,
    pub(crate) buyback: HashMap<i64, VecDeque<merchant::Buyback>>,
    pub(crate) next_buyback: u64,
    pub(crate) caps: HashMap<(i64, u16), (i64, u32)>,
    limiter: HashMap<i64, (u32, i64)>,
    pub(crate) totals: Totals,
    pub(crate) sales: Vec<Sale>,
    pub(crate) board: HashMap<(u8, u8), VecDeque<u64>>,
    pub(crate) pairs: HashMap<(AccountId, AccountId), u32>,
}

pub struct Economy {
    pub store: Arc<SqliteStore>,
    boot: u64,
    n: AtomicU64,
    pub(crate) st: Mutex<State>,
    /// One trade operation at a time: sessions are small and a lost update would be a lost offer.
    pub(crate) trade_gate: Mutex<()>,
    stop: AtomicBool,
    sweeper: Mutex<Option<std::thread::JoinHandle<()>>>,
}

fn boot_nonce() -> u64 {
    use std::hash::{BuildHasher, Hasher};
    let mut h = std::collections::hash_map::RandomState::new().build_hasher();
    h.write_u64(SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_nanos() as u64));
    h.write_u32(std::process::id());
    h.finish()
}

impl Economy {
    pub fn new(store: Arc<SqliteStore>) -> Arc<Economy> {
        Arc::new(Economy {
            store,
            boot: boot_nonce(),
            n: AtomicU64::new(1),
            st: Mutex::new(State { next_session: 1, next_buyback: 1, ..Default::default() }),
            trade_gate: Mutex::new(()),
            stop: AtomicBool::new(false),
            sweeper: Mutex::new(None),
        })
    }

    /// A fresh request id for one store call: the boot number is random, so no earlier run used it.
    pub(crate) fn meta(&self, now: Millis) -> Meta {
        Meta::new(((self.boot as u128) << 64) | self.n.fetch_add(1, Ordering::Relaxed) as u128, 0, now)
    }

    /// The hero if she is this account's and alive; and a token off her request budget.
    pub(crate) fn own(&self, account: AccountId, hero: HeroId, now: Millis) -> R<Hero> {
        let h = self.store.hero(hero)?.ok_or_else(|| Error::Missing(format!("hero {hero}")))?;
        if h.account != account {
            return Err(Error::NotYours(format!("hero {hero}")).into());
        }
        if h.deleted_at.is_some() {
            return Err(Error::Deleted.into());
        }
        self.limit(hero, now)?;
        Ok(h)
    }

    fn limit(&self, hero: HeroId, now: Millis) -> R<()> {
        use prices::{LIMIT_BURST, LIMIT_REFILL_PER_S};
        let mut st = self.st.lock().unwrap();
        let e = st.limiter.entry(hero).or_insert((LIMIT_BURST, now));
        let earned = ((now - e.1).max(0) as u64 * LIMIT_REFILL_PER_S as u64 / 1000) as u32;
        if earned > 0 {
            e.0 = (e.0 + earned).min(LIMIT_BURST);
            e.1 = now;
        }
        if e.0 == 0 {
            return Err(Fail::Slow);
        }
        e.0 -= 1;
        Ok(())
    }

    // ---- connections (pushes)

    /// A hero entered a town room: her connection can be pushed to, and she may trade with others in the room.
    pub fn attach(&self, hero: HeroId, room: u32, out: Sender<Vec<u8>>) {
        self.st.lock().unwrap().outs.insert(hero, Attached { room, out });
    }

    /// She left the town or the connection ended: her trades are called off.
    pub fn detach(&self, hero: HeroId) {
        let ids: Vec<u64> = {
            let mut st = self.st.lock().unwrap();
            st.outs.remove(&hero);
            st.in_trade.get(&hero).copied().into_iter().collect()
        };
        for id in ids {
            self.trade_end(id, hero);
        }
    }

    pub(crate) fn room_of(&self, hero: HeroId) -> Option<u32> {
        self.st.lock().unwrap().outs.get(&hero).map(|a| a.room)
    }

    pub(crate) fn push(&self, hero: HeroId, r: EResp) {
        let st = self.st.lock().unwrap();
        if let Some(a) = st.outs.get(&hero) {
            let _ = a.out.send(resp_frame(0, &Resp::EconPush(r)));
        }
    }

    // ---- the request door

    /// Answers one request from a logged-in account. `now` is the realm clock in milliseconds.
    pub fn handle(&self, account: AccountId, req: EReq, now: Millis) -> Resp {
        match self.dispatch(account, req, now) {
            Ok(r) => Resp::Econ(r),
            Err(Fail::Store(e)) => crate::gateway::err(e),
            Err(Fail::Slow) => Resp::Err { code: code::SLOW_DOWN, msg: "slow down".into() },
            Err(Fail::Bad(m)) => Resp::Err { code: code::BAD_REQUEST, msg: m },
        }
    }

    fn dispatch(&self, account: AccountId, req: EReq, now: Millis) -> R<EResp> {
        match req {
            EReq::MerchantList { hero } => self.merchant_list(account, hero, now),
            EReq::MerchantBuy { hero, offer, count } => self.merchant_buy(account, hero, offer, count, now),
            EReq::MerchantSell { hero, what } => self.merchant_sell(account, hero, what, now),
            EReq::Buyback { hero } => self.buyback_list(account, hero, now),
            EReq::BuybackTake { hero, entry } => self.buyback_take(account, hero, entry, now),
            EReq::TradeInvite { hero, with_name } => self.trade_invite(account, hero, &with_name, now),
            EReq::TradeAccept { hero, session } => self.trade_accept(account, hero, session, now),
            EReq::TradeOffer { hero, session, items, stacks } => self.trade_offer(account, hero, session, items, stacks, now),
            EReq::TradeConfirm { hero, session, version } => self.trade_confirm(account, hero, session, version, now),
            EReq::TradeCancel { hero, session } => self.trade_cancel(account, hero, session, now),
            EReq::TradeView { hero, session } => self.trade_view(account, hero, session, now),
            EReq::MarketList { hero, what, price, hours } => self.market_list(account, hero, what, price, hours, now),
            EReq::MarketSearch { hero, q } => self.market_search(account, hero, q, now),
            EReq::MarketBuy { hero, listing } => self.market_buy(account, hero, listing, now),
            EReq::MarketCancel { hero, listing } => self.market_cancel(account, hero, listing, now),
            EReq::MarketMine { hero } => self.market_mine(account, hero, now),
            EReq::MarketPrices => Ok(self.market_prices()),
            EReq::LetterSend { hero, to_name, text, things, cod } => self.letter_send(account, hero, &to_name, &text, things, cod, now),
            EReq::Inbox { hero } => self.inbox(account, hero, now),
            EReq::Outbox { hero } => self.outbox(account, hero, now),
            EReq::LetterTake { hero, letter } => self.letter_take(account, hero, letter, now),
            EReq::LetterRefuse { hero, letter } => self.letter_refuse(account, hero, letter, now),
            EReq::LetterRecall { hero, letter } => self.letter_recall(account, hero, letter, now),
        }
    }

    // ---- sweeping

    /// Ends what has run out: listings and letters go back to their senders' mail, stale invitations lapse.
    /// Returns (listings returned, letters returned).
    pub fn sweep(&self, now: Millis) -> (u32, u32) {
        let mut done = (0, 0);
        let mut skip: Vec<i64> = Vec::new();
        loop {
            let due = match self.store.parcels_due(now, 200) {
                Ok(v) => v,
                Err(_) => break,
            };
            let todo: Vec<i64> = due.into_iter().filter(|id| !skip.contains(id)).collect();
            if todo.is_empty() {
                break;
            }
            for id in todo {
                let Ok(Some(p)) = self.store.parcel(id) else {
                    skip.push(id);
                    continue;
                };
                match self.store.parcel_return(self.meta(now), id) {
                    Ok(()) => match p.kind {
                        ParcelKind::Listing => {
                            done.0 += 1;
                            self.st.lock().unwrap().totals.expired += 1;
                            self.push(p.from_hero, EResp::Notice { kind: wire::notice::EXPIRED, a: id, b: p.price, text: String::new() });
                        }
                        ParcelKind::Letter => {
                            done.1 += 1;
                            self.push(p.from_hero, EResp::Notice { kind: wire::notice::LETTER_RETURNED, a: id, b: 0, text: String::new() });
                        }
                    },
                    Err(_) => skip.push(id),
                }
            }
        }
        self.trades_lapse(now);
        done
    }

    /// Runs `sweep` once a second on its own thread (the gateway's wall clock).
    pub fn spawn_sweeper(self: &Arc<Self>) {
        let me = self.clone();
        let h = std::thread::Builder::new()
            .name("economy".into())
            .spawn(move || {
                while !me.stop.load(Ordering::Relaxed) {
                    std::thread::sleep(Duration::from_millis(500));
                    let now = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as i64);
                    me.sweep(now);
                }
            })
            .expect("thread");
        *self.sweeper.lock().unwrap() = Some(h);
    }

    pub fn stop(&self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(h) = self.sweeper.lock().unwrap().take() {
            let _ = h.join();
        }
    }

    // ---- numbers out

    pub fn totals(&self) -> Totals {
        self.st.lock().unwrap().totals.clone()
    }

    /// The sales since the last call (the simulation reads them each day).
    pub fn take_sales(&self) -> Vec<Sale> {
        std::mem::take(&mut self.st.lock().unwrap().sales)
    }

    /// Pairs of accounts that traded with each other at least `n` times on the market: a wash-trading signal for
    /// the operator (the store's `trace_forward` follows the value itself).
    pub fn repeat_pairs(&self, n: u32) -> Vec<((AccountId, AccountId), u32)> {
        let st = self.st.lock().unwrap();
        let mut v: Vec<_> = st.pairs.iter().filter(|(_, c)| **c >= n).map(|(k, c)| (*k, *c)).collect();
        v.sort();
        v
    }

    /// Coin in a hero's bag.
    pub fn coin(&self, hero: HeroId) -> u64 {
        self.store.stack(Owner::bag(hero), StackKind::COIN).unwrap_or(0)
    }
}
