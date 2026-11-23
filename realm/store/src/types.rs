//! The store's vocabulary: ids, places, stack kinds, items, heroes, commands, replies and errors.

use std::fmt;

pub type AccountId = i64;
pub type HeroId = i64;
pub type ItemId = i64;
pub type GuildId = i64;
/// A caller-chosen request id. A repeated id returns the first reply and changes nothing.
pub type RequestId = u128;
/// Milliseconds since the Unix epoch, given by the caller (the store never reads a clock).
pub type Millis = i64;

/// Limits of the game's containers (rules: bag 40, bank 100 a tab, 3 free hero slots, 6 gear slots).
pub mod limits {
	pub const BAG_SLOTS: u32 = 40;
	pub const WORN_SLOTS: u32 = 6;
	pub const BANK_SLOTS: u32 = 100;
	pub const FREE_BANK_TABS: u32 = 1;
	pub const FREE_HERO_SLOTS: u32 = 3;
	/// Mail is where a haul overflows when the bag is full, so it has no slot limit.
	pub const MAIL_SLOTS: u32 = u32::MAX;
	pub const HOUSE_SLOTS: u32 = 200;
	pub const GUILD_SLOTS: u32 = 100;
	pub const GUILD_TABS: u32 = 8;
	pub const TRADE_SLOTS: u32 = 16;
	/// A parcel (listing or letter) holds up to this many items.
	pub const MARKET_SLOTS: u32 = 8;
	/// A parcel holds at most this many entries (items plus stack kinds).
	pub const PARCEL_ENTRIES: usize = 8;
	pub const PARCEL_TEXT_MAX: usize = 200;
	/// Open listings a hero may have, and unclaimed letters one hero may have waiting.
	pub const LISTINGS_PER_HERO: i64 = 25;
	pub const LETTERS_PER_HERO: i64 = 50;
	pub const PARCEL_PRICE_MAX: u64 = 1_000_000_000_000;
	pub const MAX_LEVEL: u16 = 60;
	pub const DECK_SIZE: usize = 20;
	pub const DECK_CARDS: u16 = 30;
	pub const NOVICE_CARDS: u16 = 12;
	pub const BELT: usize = 3;
	/// Bank tabs an account may own at most (the free one and those bought).
	pub const BANK_TABS_MAX: u32 = 8;
	pub const FIELDS: usize = 6;
	pub const MAX_SOCKETS: u8 = 2;
	pub const MAX_LINES: usize = 4;
	pub const NAME_MIN: usize = 3;
	pub const NAME_MAX: usize = 16;
	/// A deleted hero may be restored for 7 days.
	pub const UNDELETE_MS: i64 = 7 * 24 * 3600 * 1000;
	/// A batch of queued commands shares one transaction, up to this many.
	pub const MAX_BATCH: usize = 512;
}

/// Where an item lives. Each place holds one item; each item has exactly one place.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum PlaceKind {
	/// owner = hero, slot 0..40
	Bag = 1,
	/// owner = hero, slot = gear slot 0..6
	Worn = 2,
	/// owner = account, tab, slot 0..100
	Bank = 3,
	/// owner = hero (the recipient)
	Mail = 4,
	/// owner = market listing
	Market = 5,
	/// owner = trade session
	Trade = 6,
	/// owner = account
	House = 7,
	/// owner = guild, tab
	Guild = 8,
}

impl PlaceKind {
	pub const ALL: [PlaceKind; 8] = [
		PlaceKind::Bag,
		PlaceKind::Worn,
		PlaceKind::Bank,
		PlaceKind::Mail,
		PlaceKind::Market,
		PlaceKind::Trade,
		PlaceKind::House,
		PlaceKind::Guild,
	];
	pub fn from_i64(v: i64) -> Option<PlaceKind> {
		PlaceKind::ALL.iter().copied().find(|k| *k as i64 == v)
	}
	pub fn name(self) -> &'static str {
		match self {
			PlaceKind::Bag => "bag",
			PlaceKind::Worn => "worn",
			PlaceKind::Bank => "bank",
			PlaceKind::Mail => "mail",
			PlaceKind::Market => "market",
			PlaceKind::Trade => "trade",
			PlaceKind::House => "house",
			PlaceKind::Guild => "guild",
		}
	}
	/// Slots per tab.
	pub fn slots(self) -> u32 {
		use limits::*;
		match self {
			PlaceKind::Bag => BAG_SLOTS,
			PlaceKind::Worn => WORN_SLOTS,
			PlaceKind::Bank => BANK_SLOTS,
			PlaceKind::Mail => MAIL_SLOTS,
			PlaceKind::Market => MARKET_SLOTS,
			PlaceKind::Trade => TRADE_SLOTS,
			PlaceKind::House => HOUSE_SLOTS,
			PlaceKind::Guild => GUILD_SLOTS,
		}
	}
	pub fn has_tabs(self) -> bool {
		matches!(self, PlaceKind::Bank | PlaceKind::Guild)
	}
	/// Is the owner a hero (else an account, guild, listing or session)?
	pub fn hero_owned(self) -> bool {
		matches!(self, PlaceKind::Bag | PlaceKind::Worn | PlaceKind::Mail)
	}
}

/// One item's place: (kind, owner, tab, slot). `tab` is 0 except in BANK and GUILD.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Place {
	pub kind: PlaceKind,
	pub owner: i64,
	pub tab: u32,
	pub slot: u32,
}

impl fmt::Display for Place {
	fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
		write!(f, "{}:{}:{}:{}", self.kind.name(), self.owner, self.tab, self.slot)
	}
}

/// Where to put an item: a place, or the first free slot of a container when `slot` is None.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Dest {
	pub kind: PlaceKind,
	pub owner: i64,
	pub tab: u32,
	pub slot: Option<u32>,
}

impl Dest {
	pub fn any(kind: PlaceKind, owner: i64) -> Dest {
		Dest { kind, owner, tab: 0, slot: None }
	}
	pub fn at(kind: PlaceKind, owner: i64, tab: u32, slot: u32) -> Dest {
		Dest { kind, owner, tab, slot: Some(slot) }
	}
	pub fn bag(hero: HeroId) -> Dest {
		Dest::any(PlaceKind::Bag, hero)
	}
	pub fn bank(account: AccountId, tab: u32) -> Dest {
		Dest { kind: PlaceKind::Bank, owner: account, tab, slot: None }
	}
}

/// Who holds a stack: a container (kind, owner). Bank stacks are the account's, not a tab's.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Owner {
	pub kind: PlaceKind,
	pub id: i64,
}

impl Owner {
	pub fn bag(hero: HeroId) -> Owner {
		Owner { kind: PlaceKind::Bag, id: hero }
	}
	pub fn bank(account: AccountId) -> Owner {
		Owner { kind: PlaceKind::Bank, id: account }
	}
}

/// A countable thing. Ranges: coin 1; potion 100+p; material 1000+m; rune 2000+stat*10+grade; vault key 3000+field;
/// page 4000+card; monster card 5000+card.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct StackKind(pub u32);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StackClass {
	Coin,
	Potion,
	Material,
	Rune,
	Key,
	Page,
	Card,
}

impl StackKind {
	pub const COIN: StackKind = StackKind(1);
	pub fn potion(p: u32) -> StackKind {
		assert!(p < 100);
		StackKind(100 + p)
	}
	pub fn material(m: u32) -> StackKind {
		assert!(m < 1000);
		StackKind(1000 + m)
	}
	/// stat 0..6, grade 1..=3
	pub fn rune(stat: u32, grade: u32) -> StackKind {
		assert!(stat < 6 && (1..=3).contains(&grade));
		StackKind(2000 + stat * 10 + grade)
	}
	pub fn key(field: u32) -> StackKind {
		assert!(field < 100);
		StackKind(3000 + field)
	}
	pub fn page(card: u32) -> StackKind {
		assert!(card < 100);
		StackKind(4000 + card)
	}
	pub fn card(card: u32) -> StackKind {
		assert!(card < 5000);
		StackKind(5000 + card)
	}
	pub fn class(self) -> Option<StackClass> {
		let v = self.0;
		Some(match v {
			1 => StackClass::Coin,
			100..=199 => StackClass::Potion,
			1000..=1999 => StackClass::Material,
			2000..=2999 => {
				let stat = (v - 2000) / 10;
				let grade = (v - 2000) % 10;
				if stat < 6 && (1..=3).contains(&grade) {
					StackClass::Rune
				} else {
					return None;
				}
			}
			3000..=3099 => StackClass::Key,
			4000..=4099 => StackClass::Page,
			5000..=9999 => StackClass::Card,
			_ => return None,
		})
	}
	/// In a bag, these take one slot a kind (rules: potions, runes, keys and pages; monster cards too).
	pub fn takes_bag_slot(self) -> bool {
		matches!(
			self.class(),
			Some(StackClass::Potion | StackClass::Rune | StackClass::Key | StackClass::Page | StackClass::Card)
		)
	}
	pub fn socketable(self) -> bool {
		matches!(self.class(), Some(StackClass::Rune | StackClass::Card))
	}
}

/// What an item is, fixed at mint (sockets fill and empty later).
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ItemSpec {
	pub base: u32,
	/// WEAPON 0, HEAD 1, BODY 2, HANDS 3, FEET 4, CHARM 5
	pub gear_slot: u8,
	pub item_level: u16,
	/// COMMON 0, UNCOMMON 1, RARE 2, EPIC 3, RELIC 4
	pub rarity: u8,
	/// (stat 0..6, points), 1 to 4 lines
	pub lines: Vec<(u8, u16)>,
	pub sockets: u8,
	pub plus: u8,
	pub bound: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Item {
	pub id: ItemId,
	pub spec: ItemSpec,
	/// One entry per socket: what it holds.
	pub socketed: Vec<Option<StackKind>>,
	pub place: Place,
	pub minted: Millis,
	/// who it was minted for, kept forever through every move and trade
	pub origin_account: AccountId,
	pub origin_hero: Option<HeroId>,
	/// the ledger row that minted it
	pub mint_seq: i64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Account {
	pub id: AccountId,
	pub steam_id: Option<u64>,
	pub dev_name: Option<String>,
	pub created: Millis,
	pub banned_until: Option<Millis>,
	/// bits of `flags::*`
	pub flags: u64,
	/// with DROPS_REDUCED: the percent of normal drops the loot service gives (the store only records it)
	pub drops_percent: u8,
}

/// Account flag bits, set by an operator (`apply_flags`), each change a ledger row.
pub mod flags {
	/// trade, market, mail with attachments, guild bank deposits and withdrawals, and every other move of value
	/// between this account and any other party refuse with `Error::Refused`
	pub const TRADE_LOCKED: u64 = 1;
	/// recorded only: the gateway routes such accounts to their own field copies
	pub const SHADOWED: u64 = 2;
	/// recorded only, with `drops_percent`: the loot service reads it
	pub const DROPS_REDUCED: u64 = 4;
	/// a marker with no effect
	pub const WATCHED: u64 = 8;
	pub const ALL: u64 = TRADE_LOCKED | SHADOWED | DROPS_REDUCED | WATCHED;
}

/// One account's new flags in a ban wave. The values replace the old ones.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FlagChange {
	pub account: AccountId,
	pub flags: u64,
	pub drops_percent: u8,
	pub banned_until: Option<Millis>,
}

/// Feats a hero earns for good (`Cmd::HeroFeat`, `Store::feats`).
pub mod feats {
	/// She passed THE CLASS TRIAL (vault row 5): the trainer may give her a job.
	pub const CLASS_TRIAL: u8 = 1;
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum EntitlementKind {
	BankTab = 1,
	HeroSlot = 2,
	Look = 3,
}

impl EntitlementKind {
	pub fn from_i64(v: i64) -> Option<EntitlementKind> {
		match v {
			1 => Some(EntitlementKind::BankTab),
			2 => Some(EntitlementKind::HeroSlot),
			3 => Some(EntitlementKind::Look),
			_ => None,
		}
	}
}

/// A hero's kept progress, written by `hero_save`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Progress {
	pub job: u8,
	pub class_level: u16,
	pub class_xp: u64,
	/// points spent in MIGHT, FOCUS, SWIFT, VIGOR, WARD, FORTUNE
	pub stats: [u16; 6],
	pub unspent: u16,
	pub deck: Vec<u16>,
	/// potion stack kinds, 0 = empty
	pub belt: [u32; 3],
	/// waystone per field, -1 = none
	pub waystones: [i32; 6],
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Hero {
	pub id: HeroId,
	pub account: AccountId,
	pub name: String,
	pub race: u8,
	pub class: u8,
	pub look: u32,
	pub progress: Progress,
	pub self_found: bool,
	pub created: Millis,
	pub deleted_at: Option<Millis>,
}

/// What a finished outing brings home, applied in one transaction.
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct OutingDelta {
	pub coin: u64,
	pub xp: u64,
	/// class levels gained (each pays one unspent stat point)
	pub levels: u16,
	/// items to mint into the bag (overflow goes to the hero's mail)
	pub items: Vec<ItemSpec>,
	/// materials, keys, pages, runes, cards banked
	pub stacks: Vec<(StackKind, u64)>,
	/// potions drunk (debited from the bag)
	pub potions_used: Vec<(StackKind, u64)>,
	/// (field, waystone) the hero last claimed
	pub waystone: Option<(u8, i32)>,
	/// Job R3b: banked coin she took from other heroes' hauls (victim, coin), banked as theirs: a CREDIT minted for
	/// the victim and a TRANSFER to her bag, so the victim's trace and clawback reach it. Not part of `coin`.
	pub plundered: Vec<(HeroId, u64)>,
}

/// One side of a trade: items and stacks leaving this hero's bag for the other's.
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct TradeSide {
	pub hero: HeroId,
	pub items: Vec<ItemId>,
	pub stacks: Vec<(StackKind, u64)>,
}

/// Every change the store makes. Each is one transaction, all or nothing.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Cmd {
	AccountBySteam { steam_id: u64 },
	AccountByDevName { name: String },
	/// operator: set accounts' flags and bans in one transaction (a ban wave)
	ApplyFlags { changes: Vec<FlagChange>, reason: String },
	/// operator: remove items wherever they are and debit stacks (to zero at most), op CLAWBACK
	Clawback { items: Vec<ItemId>, stacks: Vec<(Owner, StackKind, u64)>, reason: String },
	HeroCreate { account: AccountId, name: String, race: u8, class: u8, look: u32, self_found: bool },
	HeroRename { hero: HeroId, name: String },
	HeroDelete { hero: HeroId },
	HeroUndelete { hero: HeroId },
	HeroSave { hero: HeroId, progress: Progress },
	LearnPage { hero: HeroId, card: u16 },
	Mint { to: Dest, spec: ItemSpec, reason: String },
	MoveItem { item: ItemId, to: Dest },
	SellItem { hero: HeroId, item: ItemId, price: u64 },
	Socket { hero: HeroId, item: ItemId, socket: u8, kind: StackKind },
	Unsocket { hero: HeroId, item: ItemId, socket: u8 },
	/// `minted`: new value entering the game (a drop, a haul, a grant), counted to the owner's account in a trace;
	/// false for value bought with other value (a potion from a merchant)
	StackCredit { to: Owner, kind: StackKind, count: u64, minted: bool, reason: String },
	StackDebit { from: Owner, kind: StackKind, count: u64, reason: String },
	StackTransfer { from: Owner, to: Owner, kind: StackKind, count: u64 },
	Outing { hero: HeroId, delta: OutingDelta },
	/// A plundered fall (rules section 14, the server only): what hero `from`'s haul lost goes to hero `to`, who
	/// downed her. The haul was never in the store, so each item is minted for her (she stays its origin) and moved
	/// to the winner's bag (his mail when the bag is full); each stack is credited to her and transferred the same
	/// way. `coin` is only recorded on the PLUNDER row: it is in the winner's haul and moves when he banks it
	/// (`OutingDelta::plundered`). Nothing is lost: bound items, and everything when the winner may not take it
	/// (deleted, self-found on either side, a trade lock), stay with her (her bag, her mail when full).
	Plunder { from: HeroId, to: HeroId, items: Vec<ItemSpec>, stacks: Vec<(StackKind, u64)>, coin: u64 },
	Trade { a: TradeSide, b: TradeSide },
	GrantEntitlement { account: AccountId, kind: EntitlementKind, count: u32, purchase: String },
	/// A hero buys one more of an entitlement for coin (the server only; a coin sink, e.g. a bank tab): her
	/// account must hold exactly `have` of it now (so a repeated or stale request buys nothing), `price` coin is
	/// debited from her bag and destroyed (a DEBIT row with `reason`) and the count rises by one (an ENTITLE row);
	/// one transaction.
	BuyEntitlement { hero: HeroId, kind: EntitlementKind, have: u32, price: u64, reason: String },
	/// A hero earns a feat (the server only): a fact about her kept for good, such as passing THE CLASS TRIAL
	/// (`feats::CLASS_TRIAL`). Earning one she has is a no-op. A FEAT row records it.
	HeroFeat { hero: HeroId, feat: u8 },
	/// A hero takes a job (the server only, after its checks): `price` coin is debited from her bag and destroyed
	/// (a DEBIT row, reason "job") and her job set, in one transaction. `price` 0 debits nothing.
	TakeJob { hero: HeroId, job: u8, price: u64 },
	/// Moves things from a hero's bag into escrow as a parcel (the server only; the gateway checks consent). A
	/// listing is one item or one stack for `price` coin; a letter is up to eight entries for the hero `to`, with
	/// `price` the cash on delivery (0 for a gift). `fee` coin is taken from the sender's bag and destroyed.
	ParcelPut { kind: ParcelKind, from: HeroId, to: Option<HeroId>, items: Vec<ItemId>, stacks: Vec<(StackKind, u64)>, price: u64, fee: u64, expires: Millis, text: String },
	/// A buyer (listing) or the addressee (letter) takes the parcel: the price moves from her bag to the sender's
	/// bag, `tax` of it is destroyed, the things go to her bag; one transaction.
	ParcelTake { parcel: i64, hero: HeroId, tax: u64 },
	/// The things go to the sender's mail and the parcel ends (a cancelled or expired listing, a letter refused or
	/// expired).
	ParcelReturn { parcel: i64 },
}

/// What a parcel is.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ParcelKind {
	Listing = 1,
	Letter = 2,
}

impl ParcelKind {
	pub fn from_i64(v: i64) -> Option<ParcelKind> {
		match v {
			1 => Some(ParcelKind::Listing),
			2 => Some(ParcelKind::Letter),
			_ => None,
		}
	}
}

/// A parcel and what it holds.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Parcel {
	pub id: i64,
	pub kind: ParcelKind,
	pub from_hero: HeroId,
	pub from_account: AccountId,
	pub to_hero: Option<HeroId>,
	pub price: u64,
	pub created: Millis,
	pub expires: Millis,
	pub text: String,
	/// the sending hero's name
	pub from_name: String,
	pub items: Vec<Item>,
	pub stacks: Vec<(StackKind, u64)>,
}

/// A market search: listings that have not ended, cheapest first. Every filter is optional; item filters
/// (`gear_slot` to `level_max`) match listings of an item, `stack` one of that kind.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ListingQuery {
	pub now: Millis,
	pub gear_slot: Option<u8>,
	pub rarity_min: Option<u8>,
	pub level_min: Option<u16>,
	pub level_max: Option<u16>,
	pub stack: Option<StackKind>,
	pub price_max: Option<u64>,
	pub seller_not: Option<HeroId>,
	pub limit: u32,
	pub offset: u32,
}

impl Cmd {
	pub fn name(&self) -> &'static str {
		match self {
			Cmd::AccountBySteam { .. } => "account_by_steam",
			Cmd::AccountByDevName { .. } => "account_by_dev_name",
			Cmd::ApplyFlags { .. } => "apply_flags",
			Cmd::Clawback { .. } => "clawback",
			Cmd::HeroCreate { .. } => "hero_create",
			Cmd::HeroRename { .. } => "hero_rename",
			Cmd::HeroDelete { .. } => "hero_delete",
			Cmd::HeroUndelete { .. } => "hero_undelete",
			Cmd::HeroSave { .. } => "hero_save",
			Cmd::LearnPage { .. } => "learn_page",
			Cmd::Mint { .. } => "mint",
			Cmd::MoveItem { .. } => "move_item",
			Cmd::SellItem { .. } => "sell_item",
			Cmd::Socket { .. } => "socket",
			Cmd::Unsocket { .. } => "unsocket",
			Cmd::StackCredit { .. } => "stack_credit",
			Cmd::StackDebit { .. } => "stack_debit",
			Cmd::StackTransfer { .. } => "stack_transfer",
			Cmd::Outing { .. } => "outing",
			Cmd::Plunder { .. } => "plunder",
			Cmd::Trade { .. } => "trade",
			Cmd::GrantEntitlement { .. } => "grant_entitlement",
			Cmd::BuyEntitlement { .. } => "buy_entitlement",
			Cmd::HeroFeat { .. } => "hero_feat",
			Cmd::TakeJob { .. } => "take_job",
			Cmd::ParcelPut { .. } => "parcel_put",
			Cmd::ParcelTake { .. } => "parcel_take",
			Cmd::ParcelReturn { .. } => "parcel_return",
		}
	}
}

/// Who asks. `actor` 0 is the server itself; otherwise an account, whose ownership and ban are checked.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Request {
	pub id: RequestId,
	pub actor: AccountId,
	pub now: Millis,
	pub cmd: Cmd,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Reply {
	Done,
	Account(AccountId),
	Hero(HeroId),
	/// an item and where it now is
	Item(ItemId, Place),
	/// items minted by an outing and where they went
	Items(Vec<(ItemId, Place)>),
	/// a stack's balance after the change
	Count(u64),
	/// whether this purchase granted now (false: it had already granted), and the new total
	Granted { new: bool, total: u32 },
	/// what a clawback removed, which listed items no longer existed, and what stacks fell short
	Clawback { removed: Vec<ItemId>, missing: Vec<ItemId>, shortfall: Vec<(Owner, StackKind, u64)> },
	/// the id of a new parcel
	Parcel(i64),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Error {
	/// no free slot, or a slot or hero limit reached
	Full(String),
	/// no such account, hero, item, socket or stack
	Missing(String),
	/// the actor does not own it
	NotYours(String),
	Banned { until: Millis },
	/// refused by an account flag (TRADE_LOCKED); deliberately says nothing more
	Refused,
	/// the hero is deleted
	Deleted,
	/// undelete after the 7-day window
	Expired,
	NameTaken,
	BadName,
	/// the target slot holds another item
	SlotTaken(Place),
	/// the hero's class level is below the item's level
	LevelTooLow { need: u16, have: u16 },
	/// a stack has less than asked
	Insufficient { kind: StackKind, have: u64, want: u64 },
	/// a bound item cannot be traded
	Bound(ItemId),
	/// arguments the store refuses (out of range, wrong kind, a rule broken)
	Invalid(String),
	/// this request id was already used for different arguments
	RequestMismatch,
	/// the database failed; nothing was recorded, the request may be retried with the same id
	Db(String),
	/// the store is shut down
	Closed,
}

impl Error {
	/// Domain errors are part of a request's reply and are kept with it; Db and Closed are not.
	pub fn is_recorded(&self) -> bool {
		!matches!(self, Error::Db(_) | Error::Closed | Error::RequestMismatch)
	}
}

impl fmt::Display for Error {
	fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
		write!(f, "{self:?}")
	}
}

impl std::error::Error for Error {}

impl From<rusqlite::Error> for Error {
	fn from(e: rusqlite::Error) -> Error {
		Error::Db(e.to_string())
	}
}

pub type Result<T> = std::result::Result<T, Error>;

/// Counts from `stats`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Stats {
	pub schema_version: i64,
	pub accounts: i64,
	pub heroes: i64,
	pub deleted_heroes: i64,
	pub items: i64,
	pub stacks: i64,
	pub coin: i64,
	pub ledger_rows: i64,
	pub requests: i64,
	pub db_bytes: i64,
	/// FNV hash over items and stacks, to compare two databases
	pub digest: u64,
}

/// What `verify` found. `problems` is empty when every invariant holds.
#[derive(Clone, Debug, Default)]
pub struct VerifyReport {
	pub items: i64,
	pub stacks: i64,
	pub ledger_rows: i64,
	pub requests: i64,
	pub problems: Vec<String>,
}

/// Who holds value: an account, or a guild bank, market listing or trade session.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Party {
	Account(AccountId),
	Guild(GuildId),
	Market(i64),
	Trade(i64),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TracedItem {
	pub item: ItemId,
	pub mint_seq: i64,
	pub origin_hero: Option<HeroId>,
	/// None when destroyed (sold or clawed back)
	pub place: Option<Place>,
	/// the party holding it now
	pub holder: Option<Party>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct TracedStack {
	pub kind: StackKind,
	/// value this account minted (outing coin and stacks, drops, grants, merchant coin for sold items)
	pub minted: u64,
	/// debited out of the game (potions drunk, bought things, sockets, fees)
	pub spent: u64,
	/// moved to other parties
	pub sent: Vec<(Party, u64)>,
	/// moved in from other parties
	pub received: Vec<(Party, u64)>,
	/// what the account holds now (bags, mail of its heroes, bank, house)
	pub holds: u64,
}

/// `trace(account)`: everything the account minted and where it went, one hop.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Trace {
	pub account: AccountId,
	pub items: Vec<TracedItem>,
	pub stacks: Vec<TracedStack>,
}

/// One onward move found by `trace_forward`: at `depth` 1 the traced account's own sends, then the sends of
/// what the receivers got from the level before (items by id, stacks by kind, after the receipt).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Hop {
	pub depth: u32,
	pub seq: i64,
	pub from: Party,
	pub to: Party,
	pub item: Option<ItemId>,
	pub stack: Option<StackKind>,
	pub count: u64,
}

/// A list for `clawback`, built from the ledger by `clawback_plan`.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ClawbackPlan {
	pub items: Vec<ItemId>,
	pub stacks: Vec<(Owner, StackKind, u64)>,
}

impl VerifyReport {
	pub fn ok(&self) -> bool {
		self.problems.is_empty()
	}
}
