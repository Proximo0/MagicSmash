//! NPC merchants. One merchant per field's town, and a hero meets the one of her own field (`prices::field_of`
//! her class level): he sells the six potions, embers and six pieces of COMMON gear at her level, all at prices
//! that rise with the field; he buys items at a quarter of their value and embers and materials by the piece. A
//! sold item can be bought back for a while. The merchant creates and destroys value through the store as the
//! server: coin from a sale is new coin (`minted`), coin paid for stock is destroyed.

use super::prices::*;
use super::wire::{BuybackInfo, EItem, EResp, Offer};
use super::{bad, Economy, R};
use crate::proto::Thing;
use realm_loot::gear::{base_id, line_value};
use realm_store::*;
use std::collections::VecDeque;

pub struct Buyback {
    pub id: u64,
    pub spec: ItemSpec,
    pub paid: u64,
    pub until: Millis,
}

/// The offer ids: potions 0 to 5, embers 6, gear 7 to 12 (the gear slot is the id minus 7).
pub const OFFER_EMBERS: u16 = 6;
pub const OFFER_GEAR: u16 = 7;
pub const OFFERS: u16 = 13;

/// The gear the merchant sells a hero: COMMON, her level, one line (the stat of the slot), the base of her
/// field's tier. Item level is her class level so she can wear it at once.
pub fn gear_for(hero: &Hero, slot: u8) -> ItemSpec {
    let level = hero.progress.class_level.clamp(1, 60);
    let tier = field_of(level) as u8;
    let variant = if slot == 0 { hero.class % 6 } else { hero.race % 3 };
    ItemSpec {
        base: base_id(slot, tier, variant),
        gear_slot: slot,
        item_level: level,
        rarity: 0,
        lines: vec![(slot % 6, line_value(level, 0))],
        sockets: 0,
        plus: 0,
        bound: false,
    }
}

fn day_of(now: Millis) -> i64 {
    now.div_euclid(MS_DAY)
}

impl Economy {
    fn daily_left(&self, hero: HeroId, offer: u16, now: Millis) -> u32 {
        let cap = match offer {
            0..=5 => DAILY_POTIONS,
            OFFER_EMBERS => DAILY_EMBERS,
            _ => DAILY_GEAR,
        };
        let st = self.st.lock().unwrap();
        match st.caps.get(&(hero, offer)) {
            Some((d, n)) if *d == day_of(now) => cap.saturating_sub(*n),
            _ => cap,
        }
    }

    fn daily_used(&self, hero: HeroId, offer: u16, n: u32, now: Millis) {
        let mut st = self.st.lock().unwrap();
        let e = st.caps.entry((hero, offer)).or_insert((day_of(now), 0));
        if e.0 != day_of(now) {
            *e = (day_of(now), 0);
        }
        e.1 += n;
    }

    pub fn merchant_offers(&self, h: &Hero, now: Millis) -> Vec<Offer> {
        let level = h.progress.class_level;
        let mut v = Vec::with_capacity(OFFERS as usize);
        for p in 0..6u16 {
            v.push(Offer { id: p, kind: 0, stack: StackKind::potion(p as u32).0, item: None, price: potion_price(p as usize, level), left: self.daily_left(h.id, p, now) });
        }
        v.push(Offer { id: OFFER_EMBERS, kind: 1, stack: StackKind::material(0).0, item: None, price: ember_price(level), left: self.daily_left(h.id, OFFER_EMBERS, now) });
        for s in 0..6u8 {
            let spec = gear_for(h, s);
            let price = gear_price(&spec);
            let item = Item { id: 0, spec, socketed: vec![], place: Place { kind: PlaceKind::Bag, owner: h.id, tab: 0, slot: 0 }, minted: 0, origin_account: h.account, origin_hero: Some(h.id), mint_seq: 0 };
            v.push(Offer { id: OFFER_GEAR + s as u16, kind: 2, stack: 0, item: Some(EItem::of(&item)), price, left: self.daily_left(h.id, OFFER_GEAR + s as u16, now) });
        }
        v
    }

    pub(crate) fn merchant_list(&self, account: AccountId, hero: HeroId, now: Millis) -> R<EResp> {
        let h = self.own(account, hero, now)?;
        Ok(EResp::Offers(self.merchant_offers(&h, now)))
    }

    pub(crate) fn merchant_buy(&self, account: AccountId, hero: HeroId, offer: u16, count: u32, now: Millis) -> R<EResp> {
        let h = self.own(account, hero, now)?;
        if offer >= OFFERS || count == 0 {
            return bad("no such offer");
        }
        let list = self.merchant_offers(&h, now);
        let o = &list[offer as usize];
        if count > o.left {
            return bad("the merchant has no more of that today");
        }
        if o.kind == 2 && count > 1 && o.left < count {
            return bad("the merchant has no more of that today");
        }
        let total = o.price.checked_mul(count as u64).ok_or(super::Fail::Bad("price".into()))?;
        let bag = Owner::bag(hero);
        self.store.stack_debit(self.meta(now), bag, StackKind::COIN, total, "buy")?;
        let made: Result<()> = (|| {
            match o.kind {
                0 | 1 => {
                    self.store.stack_credit(self.meta(now), bag, StackKind(o.stack), count as u64, false, "buy")?;
                }
                _ => {
                    let spec = gear_for(&h, (offer - OFFER_GEAR) as u8);
                    for _ in 0..count {
                        self.store.mint(self.meta(now), Dest::bag(hero), spec.clone(), "merchant")?;
                    }
                }
            }
            Ok(())
        })();
        if let Err(e) = made {
            // nothing is kept half-bought: the coin comes back (it is the same coin, not new)
            let _ = self.store.stack_credit(self.meta(now), bag, StackKind::COIN, total, false, "refund");
            return Err(e.into());
        }
        self.daily_used(hero, offer, count, now);
        self.st.lock().unwrap().totals.npc_took += total;
        Ok(EResp::Coin(self.coin(hero)))
    }

    pub(crate) fn merchant_sell(&self, account: AccountId, hero: HeroId, what: Thing, now: Millis) -> R<EResp> {
        let h = self.own(account, hero, now)?;
        let bag = Owner::bag(hero);
        match what {
            Thing::Item(id) => {
                let it = self.store.item(id)?.ok_or_else(|| Error::Missing(format!("item {id}")))?;
                if it.place.kind != PlaceKind::Bag || it.place.owner != hero {
                    return Err(Error::NotYours(format!("item {id} is not in her bag")).into());
                }
                if it.socketed.iter().any(|s| s.is_some()) {
                    return bad("empty the sockets first");
                }
                let price = npc_pays(&it.spec);
                self.store.sell_item(self.meta(now), hero, id, price)?;
                let mut st = self.st.lock().unwrap();
                st.totals.npc_paid += price;
                let bid = st.next_buyback;
                st.next_buyback += 1;
                let list = st.buyback.entry(hero).or_default();
                list.push_back(Buyback { id: bid, spec: it.spec, paid: price, until: now + BUYBACK_MS });
                while list.len() > BUYBACK_KEEP {
                    list.pop_front();
                }
            }
            Thing::Stack(kind, count) => {
                let k = StackKind(kind);
                let each = match kind {
                    1000 => EMBER_SELL,
                    1001..=1006 => FIELD_MATERIAL_SELL,
                    1010..=1017 => TROPHY_SELL,
                    _ => return bad("the merchant does not buy that"),
                };
                if count == 0 {
                    return bad("count");
                }
                let pay = each.checked_mul(count).ok_or(super::Fail::Bad("count".into()))?;
                self.store.stack_debit(self.meta(now), bag, k, count, "sell")?;
                self.store.stack_credit(self.meta(now), bag, StackKind::COIN, pay, true, "sell")?;
                self.st.lock().unwrap().totals.npc_paid += pay;
            }
        }
        let _ = h;
        Ok(EResp::Coin(self.coin(hero)))
    }

    pub(crate) fn buyback_list(&self, account: AccountId, hero: HeroId, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        let mut st = self.st.lock().unwrap();
        let list: &mut VecDeque<Buyback> = st.buyback.entry(hero).or_default();
        list.retain(|b| b.until > now);
        let v = list
            .iter()
            .map(|b| {
                let item = Item { id: 0, spec: b.spec.clone(), socketed: vec![], place: Place { kind: PlaceKind::Bag, owner: hero, tab: 0, slot: 0 }, minted: 0, origin_account: account, origin_hero: Some(hero), mint_seq: 0 };
                let mut e = EItem::of(&item);
                e.info.id = b.id as i64;
                BuybackInfo { id: b.id, item: e, price: b.paid * BUYBACK_PCT / 100, secs_left: ((b.until - now) / 1000) as u32 }
            })
            .collect();
        Ok(EResp::Buybacks(v))
    }

    /// Buys back a sold item: the merchant paid `paid`, she pays 110% of it, and the item is made again for her
    /// (a new id; the store cannot bring a destroyed item back, and its origin is now this hero).
    pub(crate) fn buyback_take(&self, account: AccountId, hero: HeroId, entry: u64, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        let b = {
            let mut st = self.st.lock().unwrap();
            let list = st.buyback.entry(hero).or_default();
            list.retain(|b| b.until > now);
            let Some(i) = list.iter().position(|b| b.id == entry) else {
                return Err(Error::Missing(format!("buyback {entry}")).into());
            };
            list.remove(i).unwrap()
        };
        let cost = b.paid * BUYBACK_PCT / 100;
        let bag = Owner::bag(hero);
        let r = self.store.stack_debit(self.meta(now), bag, StackKind::COIN, cost, "buy").and_then(|_| {
            self.store.mint(self.meta(now), Dest::bag(hero), b.spec.clone(), "merchant").inspect_err(|_| {
                let _ = self.store.stack_credit(self.meta(now), bag, StackKind::COIN, cost, false, "refund");
            })
        });
        if let Err(e) = r {
            // still hers to buy back
            self.st.lock().unwrap().buyback.entry(hero).or_default().push_back(b);
            return Err(e.into());
        }
        let mut st = self.st.lock().unwrap();
        st.totals.npc_took += cost;
        st.totals.buybacks += 1;
        drop(st);
        Ok(EResp::Coin(self.coin(hero)))
    }
}
