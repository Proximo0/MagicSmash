//! Hand-to-hand trade. Two heroes in the same town room: one invites, the other accepts, each sets what she
//! gives, each confirms the exact offers she sees, and only when both have confirmed the same version does the
//! gateway make ONE store transaction (`trade_commit`) that moves both sides at once. Until then nothing moves: a
//! half confirm, a changed offer, a cancel, a lapse or a disconnect leaves every item where it was.
//!
//! The scam guards: a change of either offer clears both confirms and a confirm names the version it saw; a
//! confirm is accepted only `CONFIRM_DELAY_MS` after the last change; items are checked to be in the giver's
//! bag and not bound when offered and again by the store when committed. The store applies TRADE_LOCKED and
//! the self-found rule and says only `Refused`; the origin of every item survives the trade.

use super::prices::*;
use super::wire::{notice, EItem, EResp, TradeView};
use super::{bad, Economy, Fail, R};
use realm_store::*;

#[derive(Clone, Debug, Default)]
pub struct Side {
    pub items: Vec<i64>,
    pub stacks: Vec<(u32, u64)>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TState {
    Invited,
    Open,
    Done,
    Cancelled,
}

#[derive(Clone)]
pub struct Trade {
    pub id: u64,
    pub heroes: [i64; 2],
    pub names: [String; 2],
    pub state: TState,
    pub offer: [Side; 2],
    pub ok: [bool; 2],
    pub version: u32,
    pub changed: Millis,
    pub touched: Millis,
    pub attempts: u32,
}

impl Trade {
    fn index(&self, hero: i64) -> Option<usize> {
        self.heroes.iter().position(|h| *h == hero)
    }
}

impl Economy {
    fn items_of(&self, ids: &[i64]) -> Vec<EItem> {
        ids.iter().filter_map(|i| self.store.item(*i).ok().flatten()).map(|i| EItem::of(&i)).collect()
    }

    fn view_of(&self, t: &Trade, me: usize, now: Millis) -> TradeView {
        let you = 1 - me;
        TradeView {
            session: t.id,
            state: match t.state {
                TState::Invited => 0,
                TState::Open => 1,
                TState::Done => 2,
                TState::Cancelled => 3,
            },
            me: t.heroes[me],
            other: t.heroes[you],
            other_name: t.names[you].clone(),
            version: t.version,
            lock_ms: (t.changed + CONFIRM_DELAY_MS - now).max(0) as u32,
            my_items: self.items_of(&t.offer[me].items),
            my_stacks: t.offer[me].stacks.clone(),
            their_items: self.items_of(&t.offer[you].items),
            their_stacks: t.offer[you].stacks.clone(),
            my_ok: t.ok[me],
            their_ok: t.ok[you],
        }
    }

    /// Tells both sides where the trade stands (the caller's reply carries its own view).
    fn trade_push(&self, t: &Trade, except: Option<i64>, now: Millis) {
        for i in 0..2 {
            if Some(t.heroes[i]) != except {
                self.push(t.heroes[i], EResp::Trade(self.view_of(t, i, now)));
            }
        }
    }

    /// Runs `f` on the trade she is in; the lock is not held across store calls.
    fn trade_of(&self, hero: i64, session: u64) -> R<Trade> {
        let st = self.st.lock().unwrap();
        match st.trades.get(&session) {
            Some(t) if t.index(hero).is_some() => Ok(t.clone()),
            _ => Err(Error::Missing(format!("trade {session}")).into()),
        }
    }

    fn trade_save(&self, t: Trade) {
        let mut st = self.st.lock().unwrap();
        if matches!(t.state, TState::Done | TState::Cancelled) {
            for h in t.heroes {
                if st.in_trade.get(&h) == Some(&t.id) {
                    st.in_trade.remove(&h);
                }
            }
            st.trades.remove(&t.id);
        } else {
            st.trades.insert(t.id, t);
        }
    }

    pub(crate) fn trade_invite(&self, account: AccountId, hero: HeroId, with_name: &str, now: Millis) -> R<EResp> {
        let _gate = self.trade_gate.lock().unwrap();
        let me = self.own(account, hero, now)?;
        let other = self.store.hero_by_name(with_name)?.ok_or_else(|| Error::Missing(format!("no hero named {with_name}")))?;
        if other.id == hero {
            return bad("that is you");
        }
        if me.self_found || other.self_found {
            return Err(Error::Refused.into());
        }
        match (self.room_of(hero), self.room_of(other.id)) {
            (Some(a), Some(b)) if a == b => {}
            _ => return bad("she is not here"),
        }
        let t = {
            let mut st = self.st.lock().unwrap();
            if st.in_trade.contains_key(&hero) || st.in_trade.contains_key(&other.id) {
                return Err(Fail::Store(Error::Invalid("already trading".into())));
            }
            let id = st.next_session;
            st.next_session += 1;
            st.in_trade.insert(hero, id);
            st.in_trade.insert(other.id, id);
            let t = Trade {
                id,
                heroes: [hero, other.id],
                names: [me.name.clone(), other.name.clone()],
                state: TState::Invited,
                offer: [Side::default(), Side::default()],
                ok: [false; 2],
                version: 0,
                changed: now,
                touched: now,
                attempts: 0,
            };
            st.trades.insert(id, t.clone());
            t
        };
        self.push(other.id, EResp::Notice { kind: notice::INVITED, a: t.id as i64, b: 0, text: me.name.clone() });
        Ok(EResp::Trade(self.view_of(&t, 0, now)))
    }

    pub(crate) fn trade_accept(&self, account: AccountId, hero: HeroId, session: u64, now: Millis) -> R<EResp> {
        let _gate = self.trade_gate.lock().unwrap();
        self.own(account, hero, now)?;
        let mut t = self.trade_of(hero, session)?;
        if t.state != TState::Invited || t.index(hero) != Some(1) {
            return bad("nothing to accept");
        }
        t.state = TState::Open;
        t.changed = now;
        t.touched = now;
        let v = self.view_of(&t, 1, now);
        self.trade_push(&t, Some(hero), now);
        self.trade_save(t);
        Ok(EResp::Trade(v))
    }

    pub(crate) fn trade_offer(&self, account: AccountId, hero: HeroId, session: u64, items: Vec<i64>, stacks: Vec<(u32, u64)>, now: Millis) -> R<EResp> {
        let _gate = self.trade_gate.lock().unwrap();
        self.own(account, hero, now)?;
        let mut t = self.trade_of(hero, session)?;
        if t.state != TState::Open {
            return bad("the trade is not open");
        }
        let me = t.index(hero).unwrap();
        if items.len() + stacks.len() > 16 {
            return bad("at most 16 things");
        }
        let mut seen = std::collections::BTreeSet::new();
        for id in &items {
            if !seen.insert(*id) {
                return bad("an item twice");
            }
            let it = self.store.item(*id)?.ok_or_else(|| Error::Missing(format!("item {id}")))?;
            if it.place.kind != PlaceKind::Bag || it.place.owner != hero {
                return Err(Error::NotYours(format!("item {id} is not in her bag")).into());
            }
            if it.spec.bound {
                return Err(Error::Bound(*id).into());
            }
        }
        let mut kinds = std::collections::BTreeSet::new();
        for (k, n) in &stacks {
            if *n == 0 || !kinds.insert(*k) {
                return bad("a stack twice, or none of it");
            }
            let have = self.store.stack(Owner::bag(hero), StackKind(*k))?;
            if have < *n {
                return Err(Error::Insufficient { kind: StackKind(*k), have, want: *n }.into());
            }
        }
        t.offer[me] = Side { items, stacks };
        t.ok = [false; 2];
        t.version += 1;
        t.changed = now;
        t.touched = now;
        let v = self.view_of(&t, me, now);
        self.trade_push(&t, Some(hero), now);
        self.trade_save(t);
        Ok(EResp::Trade(v))
    }

    pub(crate) fn trade_confirm(&self, account: AccountId, hero: HeroId, session: u64, version: u32, now: Millis) -> R<EResp> {
        let _gate = self.trade_gate.lock().unwrap();
        self.own(account, hero, now)?;
        let mut t = self.trade_of(hero, session)?;
        if t.state != TState::Open {
            return bad("the trade is not open");
        }
        let me = t.index(hero).unwrap();
        if version != t.version {
            return bad("the offer changed: look again");
        }
        if now < t.changed + CONFIRM_DELAY_MS {
            return bad("the offer changed a moment ago");
        }
        t.ok[me] = true;
        t.touched = now;
        if !(t.ok[0] && t.ok[1]) {
            let v = self.view_of(&t, me, now);
            self.trade_push(&t, Some(hero), now);
            self.trade_save(t);
            return Ok(EResp::Trade(v));
        }
        // both confirmed the same version: one transaction. A fresh attempt number gives a fresh request id (a
        // failed commit is kept by the store as the answer to its id, so a retry must not reuse it).
        t.attempts += 1;
        let side = |i: usize| TradeSide { hero: t.heroes[i], items: t.offer[i].items.clone(), stacks: t.offer[i].stacks.iter().map(|(k, n)| (StackKind(*k), *n)).collect() };
        let (a, b) = (side(0), side(1));
        let key = (t.id << 20) | t.attempts as u64;
        let mut m = self.meta(now);
        m.id = trade_request_id(&a, &b, key);
        match self.store.trade_commit(m, a, b) {
            Ok(()) => {
                t.state = TState::Done;
                self.st.lock().unwrap().totals.trades += 1;
                let v = self.view_of(&t, me, now);
                self.trade_push(&t, Some(hero), now);
                self.trade_save(t);
                Ok(EResp::Trade(v))
            }
            Err(Error::Refused) => {
                // a flag or the self-found rule: the trade ends and neither side learns why
                t.state = TState::Cancelled;
                self.trade_push(&t, Some(hero), now);
                self.trade_save(t);
                Err(Error::Refused.into())
            }
            Err(e) => {
                // full bag, an item gone: the offers stay, the confirms go
                t.ok = [false; 2];
                t.version += 1;
                t.changed = now;
                self.trade_push(&t, Some(hero), now);
                self.trade_save(t);
                Err(e.into())
            }
        }
    }

    pub(crate) fn trade_cancel(&self, account: AccountId, hero: HeroId, session: u64, now: Millis) -> R<EResp> {
        let _gate = self.trade_gate.lock().unwrap();
        self.own(account, hero, now)?;
        let mut t = self.trade_of(hero, session)?;
        t.state = TState::Cancelled;
        self.trade_push(&t, Some(hero), now);
        let v = self.view_of(&t, t.index(hero).unwrap(), now);
        self.trade_save(t);
        Ok(EResp::Trade(v))
    }

    pub(crate) fn trade_view(&self, account: AccountId, hero: HeroId, session: u64, now: Millis) -> R<EResp> {
        let _gate = self.trade_gate.lock().unwrap();
        self.own(account, hero, now)?;
        let t = self.trade_of(hero, session)?;
        Ok(EResp::Trade(self.view_of(&t, t.index(hero).unwrap(), now)))
    }

    /// A hero's connection ended (or she left the room): her trade is called off.
    pub(crate) fn trade_end(&self, session: u64, leaver: i64) {
        let _gate = self.trade_gate.lock().unwrap();
        let Ok(mut t) = self.trade_of(leaver, session) else { return };
        t.state = TState::Cancelled;
        self.trade_push(&t, Some(leaver), 0);
        self.trade_save(t);
    }

    /// Invitations unanswered for `INVITE_MS` and open trades idle for `TRADE_IDLE_MS` lapse.
    pub(crate) fn trades_lapse(&self, now: Millis) {
        let _gate = self.trade_gate.lock().unwrap();
        let stale: Vec<u64> = {
            let st = self.st.lock().unwrap();
            st.trades
                .values()
                .filter(|t| match t.state {
                    TState::Invited => now - t.touched > INVITE_MS,
                    _ => now - t.touched > TRADE_IDLE_MS,
                })
                .map(|t| t.id)
                .collect()
        };
        for id in stale {
            let hero = { self.st.lock().unwrap().trades.get(&id).map(|t| t.heroes[0]) };
            if let Some(h) = hero {
                if let Ok(mut t) = self.trade_of(h, id) {
                    t.state = TState::Cancelled;
                    self.trade_push(&t, None, now);
                    self.trade_save(t);
                }
            }
        }
    }
}
