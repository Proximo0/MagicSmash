//! HORDE & HEARTH's store: accounts, heroes, items, stacks, entitlements and the ledger.
//!
//! Everything is kept: every change is one transaction with its ledger rows; every request carries an id and a
//! repeated id returns the first reply and changes nothing. `Store` is the interface; `SqliteStore` implements it
//! with SQLite (WAL, synchronous FULL, one writer thread with group commit). See `docs/realm/store.md`.

pub mod codec;
pub mod crash;
pub mod fuzz;
pub mod ops;
pub mod parcels;
pub mod read;
pub mod rng;
pub mod schema;
pub mod sqlite;
pub mod types;

pub use codec::trade_request_id;
pub use ops::{Who, who_may};
pub use sqlite::{Options, SqliteStore, backup_copy, backup_file, restore_file};
pub use types::*;

use std::path::Path;

/// Request id, acting account (0 = the server) and the caller's clock for one operation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Meta {
	pub id: RequestId,
	pub actor: AccountId,
	pub now: Millis,
}

impl Meta {
	pub fn new(id: RequestId, actor: AccountId, now: Millis) -> Meta {
		Meta { id, actor, now }
	}
	pub fn system(id: RequestId, now: Millis) -> Meta {
		Meta { id, actor: 0, now }
	}
}

fn unexpected(r: Reply) -> Error {
	Error::Db(format!("unexpected reply {r:?}"))
}

/// The store's operations. Changes go through `submit`; the typed methods below build the command and read the
/// reply. Reads see every change whose reply has been returned.
pub trait Store: Send + Sync {
	/// Applies one request in its own transaction (or a shared group commit); replies after the commit.
	fn submit(&self, req: Request) -> Result<Reply>;
	/// Applies requests in order in one transaction, each in its own savepoint; replies after the commit.
	fn submit_batch(&self, reqs: Vec<Request>) -> Vec<Result<Reply>>;

	// ---- reads ----
	fn account(&self, id: AccountId) -> Result<Option<Account>>;
	/// Accounts with any of the `flags::*` bits in `mask` set, by id (the moderators' ban wave by flag).
	fn accounts_flagged(&self, mask: u64) -> Result<Vec<Account>>;
	fn hero(&self, id: HeroId) -> Result<Option<Hero>>;
	fn heroes(&self, account: AccountId, include_deleted: bool) -> Result<Vec<Hero>>;
	/// The live hero with this name (case does not matter), for mail and whispers.
	fn hero_by_name(&self, name: &str) -> Result<Option<Hero>>;
	fn item(&self, id: ItemId) -> Result<Option<Item>>;
	fn items_at(&self, kind: PlaceKind, owner: i64) -> Result<Vec<Item>>;
	fn stack(&self, owner: Owner, kind: StackKind) -> Result<u64>;
	fn stacks(&self, owner: Owner) -> Result<Vec<(StackKind, u64)>>;
	fn entitlements(&self, account: AccountId) -> Result<Vec<(EntitlementKind, u32)>>;
	/// The cards the account has learned from pages (the shell lists a hero's deck cards with it).
	fn owned_cards(&self, account: AccountId) -> Result<Vec<u16>>;
	/// Everything the account minted and where it is, and per stack kind minted, spent, sent, received, held.
	fn trace(&self, account: AccountId) -> Result<Trace>;
	/// What the account sent, and what its receivers sent onward of it, to `depth` hops.
	fn trace_forward(&self, account: AccountId, depth: u32) -> Result<Vec<Hop>>;
	/// A clawback list for what the account minted after ledger row `since_seq`.
	fn clawback_plan(&self, account: AccountId, since_seq: i64) -> Result<ClawbackPlan>;
	/// Every invariant, with a replay of the whole ledger.
	fn verify(&self) -> Result<VerifyReport>;
	/// An online backup to a file while writes continue, verified.
	fn backup(&self, dest: &Path) -> Result<VerifyReport>;
	fn stats(&self) -> Result<Stats>;
	/// Coin by ledger op and reason: (op, reason, minted, rows, total).
	fn coin_flows(&self) -> Result<Vec<(String, String, bool, i64, i64)>>;
	/// One parcel (a market listing or a letter) with what it holds.
	fn parcel(&self, id: i64) -> Result<Option<Parcel>>;
	/// A hero's own listings and letters in transit.
	fn parcels_from(&self, hero: HeroId) -> Result<Vec<Parcel>>;
	/// Letters waiting for a hero.
	fn parcels_to(&self, hero: HeroId) -> Result<Vec<Parcel>>;
	/// Ids of parcels whose time has come (to return to their senders).
	fn parcels_due(&self, now: Millis, limit: u32) -> Result<Vec<i64>>;
	/// Open listings by price, filtered.
	fn listings(&self, q: &ListingQuery) -> Result<Vec<Parcel>>;

	// ---- typed operations ----
	fn run(&self, m: Meta, cmd: Cmd) -> Result<Reply> {
		self.submit(Request { id: m.id, actor: m.actor, now: m.now, cmd })
	}
	/// Get or create the account of a Steam id.
	fn account_by_steam(&self, m: Meta, steam_id: u64) -> Result<AccountId> {
		match self.run(m, Cmd::AccountBySteam { steam_id })? {
			Reply::Account(a) => Ok(a),
			r => Err(unexpected(r)),
		}
	}
	/// Get or create a dev account by name (no Steam).
	fn account_by_dev_name(&self, m: Meta, name: &str) -> Result<AccountId> {
		match self.run(m, Cmd::AccountByDevName { name: name.into() })? {
			Reply::Account(a) => Ok(a),
			r => Err(unexpected(r)),
		}
	}
	/// Operator: set flags, drops percent and ban of many accounts at once (a ban wave).
	fn apply_flags(&self, m: Meta, changes: Vec<FlagChange>, reason: &str) -> Result<()> {
		self.run(m, Cmd::ApplyFlags { changes, reason: reason.into() }).map(|_| ())
	}
	fn hero_create(&self, m: Meta, account: AccountId, name: &str, race: u8, class: u8, look: u32, self_found: bool) -> Result<HeroId> {
		match self.run(m, Cmd::HeroCreate { account, name: name.into(), race, class, look, self_found })? {
			Reply::Hero(h) => Ok(h),
			r => Err(unexpected(r)),
		}
	}
	fn hero_rename(&self, m: Meta, hero: HeroId, name: &str) -> Result<()> {
		self.run(m, Cmd::HeroRename { hero, name: name.into() }).map(|_| ())
	}
	/// Soft delete: restorable for 7 days; items stay where they are.
	fn hero_delete(&self, m: Meta, hero: HeroId) -> Result<()> {
		self.run(m, Cmd::HeroDelete { hero }).map(|_| ())
	}
	fn hero_undelete(&self, m: Meta, hero: HeroId) -> Result<()> {
		self.run(m, Cmd::HeroUndelete { hero }).map(|_| ())
	}
	/// Class level and xp (never down), stat points, job, deck, belt, waystones.
	fn hero_save(&self, m: Meta, hero: HeroId, progress: Progress) -> Result<()> {
		self.run(m, Cmd::HeroSave { hero, progress }).map(|_| ())
	}
	/// Turns a page in the bag into an owned deck card for the account.
	fn learn_page(&self, m: Meta, hero: HeroId, card: u16) -> Result<()> {
		self.run(m, Cmd::LearnPage { hero, card }).map(|_| ())
	}
	/// A new item at a place (or the first free slot); reason drop, cache, chest, merchant, grant or haul.
	fn mint(&self, m: Meta, to: Dest, spec: ItemSpec, reason: &str) -> Result<(ItemId, Place)> {
		match self.run(m, Cmd::Mint { to, spec, reason: reason.into() })? {
			Reply::Item(i, p) => Ok((i, p)),
			r => Err(unexpected(r)),
		}
	}
	/// Bag, worn, bank, mail, house, guild; checks slots, tabs, wear level, ownership, TRADE_LOCKED.
	fn move_item(&self, m: Meta, item: ItemId, to: Dest) -> Result<Place> {
		match self.run(m, Cmd::MoveItem { item, to })? {
			Reply::Item(_, p) => Ok(p),
			r => Err(unexpected(r)),
		}
	}
	/// Destroys a bag item and credits its price in coin to the bag; returns the coin after.
	fn sell_item(&self, m: Meta, hero: HeroId, item: ItemId, price: u64) -> Result<u64> {
		match self.run(m, Cmd::SellItem { hero, item, price })? {
			Reply::Count(c) => Ok(c),
			r => Err(unexpected(r)),
		}
	}
	/// One card or rune from the bag into an empty socket of a carried item.
	fn socket(&self, m: Meta, hero: HeroId, item: ItemId, socket: u8, kind: StackKind) -> Result<()> {
		self.run(m, Cmd::Socket { hero, item, socket, kind }).map(|_| ())
	}
	fn unsocket(&self, m: Meta, hero: HeroId, item: ItemId, socket: u8) -> Result<()> {
		self.run(m, Cmd::Unsocket { hero, item, socket }).map(|_| ())
	}
	fn stack_credit(&self, m: Meta, to: Owner, kind: StackKind, count: u64, minted: bool, reason: &str) -> Result<u64> {
		match self.run(m, Cmd::StackCredit { to, kind, count, minted, reason: reason.into() })? {
			Reply::Count(c) => Ok(c),
			r => Err(unexpected(r)),
		}
	}
	fn stack_debit(&self, m: Meta, from: Owner, kind: StackKind, count: u64, reason: &str) -> Result<u64> {
		match self.run(m, Cmd::StackDebit { from, kind, count, reason: reason.into() })? {
			Reply::Count(c) => Ok(c),
			r => Err(unexpected(r)),
		}
	}
	/// Returns the source's balance after.
	fn stack_transfer(&self, m: Meta, from: Owner, to: Owner, kind: StackKind, count: u64) -> Result<u64> {
		match self.run(m, Cmd::StackTransfer { from, to, kind, count })? {
			Reply::Count(c) => Ok(c),
			r => Err(unexpected(r)),
		}
	}
	/// Banks a haul, adds xp and levels, uses up potions, sets a waystone, atomically. Returns minted items.
	fn apply_outing(&self, m: Meta, hero: HeroId, delta: OutingDelta) -> Result<Vec<(ItemId, Place)>> {
		match self.run(m, Cmd::Outing { hero, delta })? {
			Reply::Items(v) => Ok(v),
			r => Err(unexpected(r)),
		}
	}
	/// A plundered fall (rules section 14): the haul a hero lost goes to the hero who downed her, in one
	/// transaction. Returns where each item landed (the winner's bag, or her mail when the bag is full).
	fn plunder(&self, m: Meta, from: HeroId, to: HeroId, items: Vec<ItemSpec>, stacks: Vec<(StackKind, u64)>, coin: u64) -> Result<Vec<(ItemId, Place)>> {
		match self.run(m, Cmd::Plunder { from, to, items, stacks, coin })? {
			Reply::Items(v) => Ok(v),
			r => Err(unexpected(r)),
		}
	}
	/// Two heroes swap items and stacks between their bags atomically. Use `trade_request_id` for `m.id`.
	/// Escrow a listing or letter from a hero's bag (the server only).
	fn parcel_put(&self, m: Meta, cmd: Cmd) -> Result<i64> {
		match self.run(m, cmd)? {
			Reply::Parcel(p) => Ok(p),
			r => Err(unexpected(r)),
		}
	}
	/// Pay for and take a parcel (a buyer, or the addressee of a letter).
	fn parcel_take(&self, m: Meta, parcel: i64, hero: HeroId, tax: u64) -> Result<()> {
		self.run(m, Cmd::ParcelTake { parcel, hero, tax }).map(|_| ())
	}
	/// End a parcel: its things go to the sender's mail.
	fn parcel_return(&self, m: Meta, parcel: i64) -> Result<()> {
		self.run(m, Cmd::ParcelReturn { parcel }).map(|_| ())
	}
	fn trade_commit(&self, m: Meta, a: TradeSide, b: TradeSide) -> Result<()> {
		self.run(m, Cmd::Trade { a, b }).map(|_| ())
	}
	/// Once per purchase id; returns whether it granted now and the new total.
	fn grant_entitlement(&self, m: Meta, account: AccountId, kind: EntitlementKind, count: u32, purchase: &str) -> Result<(bool, u32)> {
		match self.run(m, Cmd::GrantEntitlement { account, kind, count, purchase: purchase.into() })? {
			Reply::Granted { new, total } => Ok((new, total)),
			r => Err(unexpected(r)),
		}
	}
	/// Operator: removes items wherever they are and debits stacks (to zero at most; then from sockets).
	fn clawback(&self, m: Meta, plan: ClawbackPlan, reason: &str) -> Result<(Vec<ItemId>, Vec<ItemId>, Vec<(Owner, StackKind, u64)>)> {
		match self.run(m, Cmd::Clawback { items: plan.items, stacks: plan.stacks, reason: reason.into() })? {
			Reply::Clawback { removed, missing, shortfall } => Ok((removed, missing, shortfall)),
			r => Err(unexpected(r)),
		}
	}
}
