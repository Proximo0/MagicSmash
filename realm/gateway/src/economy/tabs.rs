//! Bank tabs bought for coin (a coin sink). The account owns its tabs (`EntitlementKind::BankTab`, the first is
//! free); the next costs `realm_loot::sinks::bank_tab_price`, rising, up to `limits::BANK_TABS_MAX`. The store
//! debits the coin and opens the tab in one transaction (`Cmd::BuyEntitlement`: a DEBIT row "bank tab" and an
//! ENTITLE row), and refuses a count the account has already passed, so a doubled click buys one tab.

use super::wire::EResp;
use super::{bad, Economy, R};
use realm_loot::sinks::bank_tab_price;
use realm_store::types::limits::{BANK_TABS_MAX, FREE_BANK_TABS};
use realm_store::*;

impl Economy {
    fn tabs_owned(&self, account: AccountId) -> R<u32> {
        let bought = self.store.entitlements(account)?.into_iter().find(|(k, _)| *k == EntitlementKind::BankTab).map_or(0, |(_, n)| n);
        Ok((FREE_BANK_TABS + bought).min(BANK_TABS_MAX))
    }

    fn tabs_view(&self, account: AccountId) -> R<EResp> {
        let owned = self.tabs_owned(account)?;
        Ok(EResp::BankTabs { owned, max: BANK_TABS_MAX, price: bank_tab_price(owned).unwrap_or(0) })
    }

    pub(crate) fn bank_tabs(&self, account: AccountId, hero: HeroId, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        self.tabs_view(account)
    }

    pub(crate) fn bank_tab_buy(&self, account: AccountId, hero: HeroId, owned: u32, now: Millis) -> R<EResp> {
        self.own(account, hero, now)?;
        let have = self.tabs_owned(account)?;
        if owned != have {
            return bad("the bank's book changed: look again");
        }
        let Some(price) = bank_tab_price(have) else { return bad("the bank has no more tabs to sell") };
        let carried = self.coin(hero);
        if carried < price {
            return bad(&format!("the next tab costs {} coin and she carries {}", crate::gateway::commas(price), crate::gateway::commas(carried)));
        }
        self.store.buy_entitlement(self.meta(now), hero, EntitlementKind::BankTab, have - FREE_BANK_TABS, price, "bank tab")?;
        self.st.lock().unwrap().totals.tabs += price;
        self.tabs_view(account)
    }
}
