//! Letters: a short text, up to eight attachments (items, stacks, coin) and an optional cash on delivery, from
//! one hero to another by name. The things wait in the store's escrow (a letter parcel) until the addressee
//! takes them (paying the COD to the sender in the same transaction), refuses them (they go back to the
//! sender's mail) or 30 days pass (the same). The older mail place (`mail_send`, `mail_take`) stays: it is where
//! a full bag's haul lands and where returned things arrive.

use super::prices::*;
use super::wire::{notice, EItem, EResp, LetterInfo};
use super::{bad, Economy, R};
use crate::proto::Thing;
use realm_store::*;

impl Economy {
    fn letter_info(&self, p: &Parcel) -> LetterInfo {
        let name = |h: HeroId| self.store.hero(h).ok().flatten().map(|h| h.name).unwrap_or_default();
        LetterInfo {
            id: p.id,
            from: name(p.from_hero),
            to: p.to_hero.map(name).unwrap_or_default(),
            text: p.text.clone(),
            cod: p.price,
            expires: p.expires,
            items: p.items.iter().map(EItem::of).collect(),
            stacks: p.stacks.iter().map(|(k, n)| (k.0, *n)).collect(),
        }
    }

    pub(crate) fn letter_send(&self, account: AccountId, hero: HeroId, to_name: &str, text: &str, things: Vec<Thing>, cod: u64, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        if things.is_empty() || things.len() > LETTER_THINGS {
            return bad("a letter carries 1 to 8 things");
        }
        if cod > PRICE_MAX {
            return bad("price");
        }
        let to = self.store.hero_by_name(to_name)?.ok_or_else(|| Error::Missing(format!("no hero named {to_name}")))?;
        let text: String = text.chars().filter(|c| !c.is_control()).take(limits::PARCEL_TEXT_MAX).collect();
        let (mut items, mut stacks) = (Vec::new(), Vec::new());
        for t in &things {
            match *t {
                Thing::Item(i) => items.push(i),
                Thing::Stack(k, n) => stacks.push((StackKind(k), n)),
            }
        }
        let fee = POSTAGE + POSTAGE_PER_THING * things.len() as u64;
        let id = self.store.parcel_put(
            self.meta(now),
            Cmd::ParcelPut { kind: ParcelKind::Letter, from: hero, to: Some(to.id), items, stacks, price: cod, fee, expires: now + LETTER_DAYS * MS_DAY, text },
        )?;
        {
            let mut st = self.st.lock().unwrap();
            st.totals.postage += fee;
            st.totals.letters += 1;
        }
        let from = self.store.hero(hero).ok().flatten().map(|h| h.name).unwrap_or_default();
        self.push(to.id, EResp::Notice { kind: notice::LETTER, a: id, b: cod, text: from });
        Ok(EResp::Listed { id, fee })
    }

    pub(crate) fn inbox(&self, account: AccountId, hero: HeroId, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        Ok(EResp::Letters(self.store.parcels_to(hero)?.iter().filter(|p| p.kind == ParcelKind::Letter).map(|p| self.letter_info(p)).collect()))
    }

    pub(crate) fn outbox(&self, account: AccountId, hero: HeroId, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        Ok(EResp::Letters(self.store.parcels_from(hero)?.iter().filter(|p| p.kind == ParcelKind::Letter).map(|p| self.letter_info(p)).collect()))
    }

    fn letter(&self, id: i64) -> R<Parcel> {
        match self.store.parcel(id)? {
            Some(p) if p.kind == ParcelKind::Letter => Ok(p),
            _ => Err(Error::Missing(format!("letter {id}")).into()),
        }
    }

    pub(crate) fn letter_take(&self, account: AccountId, hero: HeroId, letter: i64, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        let p = self.letter(letter)?;
        if p.to_hero != Some(hero) {
            return Err(Error::NotYours(format!("letter {letter}")).into());
        }
        self.store.parcel_take(self.meta(now), letter, hero, 0)?;
        if p.price > 0 {
            self.st.lock().unwrap().totals.cod_volume += p.price;
        }
        Ok(EResp::Coin(self.coin(hero)))
    }

    pub(crate) fn letter_refuse(&self, account: AccountId, hero: HeroId, letter: i64, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        let p = self.letter(letter)?;
        if p.to_hero != Some(hero) {
            return Err(Error::NotYours(format!("letter {letter}")).into());
        }
        self.store.parcel_return(self.meta(now), letter)?;
        self.push(p.from_hero, EResp::Notice { kind: notice::LETTER_RETURNED, a: letter, b: 0, text: String::new() });
        Ok(EResp::Ok)
    }

    pub(crate) fn letter_recall(&self, account: AccountId, hero: HeroId, letter: i64, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        let p = self.letter(letter)?;
        if p.from_hero != hero {
            return Err(Error::NotYours(format!("letter {letter}")).into());
        }
        self.store.parcel_return(self.meta(now), letter)?;
        Ok(EResp::Ok)
    }
}
