//! The market: a listing puts one item (or one stack) into the store's escrow for a price; anyone else may
//! buy it; the seller may cancel; what nobody buys comes back to her mail when it ends. Each sale destroys a
//! tax, each listing a fee (`prices`), which makes the market the main coin sink between players.
//!
//! All of it is the store's `ParcelPut`, `ParcelTake` and `ParcelReturn`: one transaction each, so an item is
//! never in two places or none, and a failed purchase changes nothing.

use super::prices::*;
use super::wire::{notice, ClassPrice, EItem, EResp, ListingInfo, Search};
use super::{bad, Economy, Sale, R};
use crate::proto::Thing;
use realm_store::*;

/// The price-board class of an item: rarity and ten-level band.
pub fn class_of(rarity: u8, level: u16) -> (u8, u8) {
    (rarity, ((level.max(1) - 1) / 10).min(5) as u8)
}

fn median(v: &mut [u64]) -> u64 {
    v.sort_unstable();
    v[v.len() / 2]
}

impl Economy {
    fn listing_info(&self, p: &Parcel, mine: Option<HeroId>) -> ListingInfo {
        let seller = p.from_name.clone();
        ListingInfo {
            id: p.id,
            seller,
            price: p.price,
            expires: p.expires,
            item: p.items.first().map(EItem::of),
            stack: p.stacks.first().map(|(k, n)| (k.0, *n)),
            mine: mine == Some(p.from_hero),
        }
    }

    pub(crate) fn market_list(&self, account: AccountId, hero: HeroId, what: Thing, price: u64, hours: u16, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        if !HOURS.contains(&hours) {
            return bad("a listing lasts 12, 24 or 48 hours");
        }
        if price == 0 || price > PRICE_MAX {
            return bad("price");
        }
        let (items, stacks) = match what {
            Thing::Item(i) => {
                let it = self.store.item(i)?.ok_or_else(|| Error::Missing(format!("item {i}")))?;
                if it.place.kind != PlaceKind::Bag || it.place.owner != hero {
                    return Err(Error::NotYours(format!("item {i} is not in her bag")).into());
                }
                if price > item_price_cap(&it.spec) {
                    return bad("that price is more than the market allows for such an item");
                }
                (vec![i], vec![])
            }
            Thing::Stack(k, n) => {
                let Some(each) = stack_ref(k) else { return bad("that is not sold on the market") };
                if n == 0 || price > each.saturating_mul(n).saturating_mul(PRICE_CAP_MUL) {
                    return bad("that price is more than the market allows for such a stack");
                }
                (vec![], vec![(StackKind(k), n)])
            }
        };
        let fee = fee_of(price, hours);
        let id = self.store.parcel_put(
            self.meta(now),
            Cmd::ParcelPut { kind: ParcelKind::Listing, from: hero, to: None, items, stacks, price, fee, expires: now + hours as i64 * MS_HOUR, text: String::new() },
        )?;
        let mut st = self.st.lock().unwrap();
        st.totals.fees += fee;
        st.totals.listed += 1;
        Ok(EResp::Listed { id, fee })
    }

    pub(crate) fn market_search(&self, account: AccountId, hero: HeroId, q: Search, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        let query = ListingQuery {
            now,
            gear_slot: (q.gear_slot < 6).then_some(q.gear_slot),
            rarity_min: (q.rarity_min > 0).then_some(q.rarity_min),
            level_min: (q.level_min > 0).then_some(q.level_min),
            level_max: (q.level_max > 0).then_some(q.level_max),
            stack: (q.stack > 0).then_some(StackKind(q.stack)),
            price_max: (q.price_max > 0).then_some(q.price_max),
            seller_not: None,
            limit: PAGE,
            offset: q.offset,
        };
        let v = self.store.listings(&query)?;
        Ok(EResp::Listings(v.iter().map(|p| self.listing_info(p, Some(hero))).collect()))
    }

    pub(crate) fn market_mine(&self, account: AccountId, hero: HeroId, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        let v = self.store.parcels_from(hero)?;
        Ok(EResp::Listings(v.iter().filter(|p| p.kind == ParcelKind::Listing).map(|p| self.listing_info(p, Some(hero))).collect()))
    }

    pub(crate) fn market_buy(&self, account: AccountId, hero: HeroId, listing: i64, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        let p = self.store.parcel(listing)?.ok_or_else(|| Error::Missing(format!("listing {listing}")))?;
        if p.kind != ParcelKind::Listing {
            return Err(Error::Missing(format!("listing {listing}")).into());
        }
        let tax = tax_of(p.price);
        self.store.parcel_take(self.meta(now), listing, hero, tax)?;
        let (rarity, level, slot, value) = match p.items.first() {
            Some(i) => (i.spec.rarity, i.spec.item_level, i.spec.gear_slot, super::prices::item_value(&i.spec)),
            None => (0, 0, 255, 0),
        };
        {
            let mut st = self.st.lock().unwrap();
            st.totals.sales += 1;
            st.totals.volume += p.price;
            st.totals.tax += tax;
            *st.pairs.entry((p.from_account, account)).or_insert(0) += 1;
            if let Some(i) = p.items.first() {
                let c = class_of(i.spec.rarity, i.spec.item_level);
                let d = st.board.entry(c).or_default();
                d.push_back(p.price);
                while d.len() > 64 {
                    d.pop_front();
                }
            }
            st.sales.push(Sale { time: now, rarity, level, gear_slot: slot, price: p.price, value, seller: p.from_account, buyer: account, listed_at: p.created, stack: p.stacks.first().map(|(k, n)| (k.0, *n)) });
        }
        self.push(p.from_hero, EResp::Notice { kind: notice::SOLD, a: listing, b: p.price - tax, text: String::new() });
        Ok(EResp::Coin(self.coin(hero)))
    }

    pub(crate) fn market_cancel(&self, account: AccountId, hero: HeroId, listing: i64, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        let p = self.store.parcel(listing)?.ok_or_else(|| Error::Missing(format!("listing {listing}")))?;
        if p.kind != ParcelKind::Listing || p.from_hero != hero {
            return Err(Error::NotYours(format!("listing {listing}")).into());
        }
        self.store.parcel_return(self.meta(now), listing)?;
        self.st.lock().unwrap().totals.cancelled += 1;
        Ok(EResp::Ok)
    }

    /// The median of the last sales in each class that has had any (at most 64 kept per class).
    pub(crate) fn market_prices(&self) -> EResp {
        let st = self.st.lock().unwrap();
        let mut v: Vec<ClassPrice> = st
            .board
            .iter()
            .filter(|(_, d)| !d.is_empty())
            .map(|(c, d)| ClassPrice { rarity: c.0, band: c.1, median: median(&mut d.iter().copied().collect::<Vec<_>>()), n: d.len() as u32 })
            .collect();
        v.sort_by_key(|p| (p.rarity, p.band));
        EResp::Prices(v)
    }
}
