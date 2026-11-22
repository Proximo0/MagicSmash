//! A small text encoding for commands, replies and errors (no serde): space-separated tokens, strings as `x<hex>`.
//! Used for the request table (kept replies), the argument hash of a request, and the fuzz pipe.

use crate::types::*;

#[derive(Default)]
pub struct Enc {
	pub s: String,
}

impl Enc {
	pub fn new() -> Enc {
		Enc { s: String::new() }
	}
	fn tok(&mut self, t: &str) {
		if !self.s.is_empty() {
			self.s.push(' ');
		}
		self.s.push_str(t);
	}
	pub fn u(&mut self, v: u64) -> &mut Self {
		self.tok(&v.to_string());
		self
	}
	pub fn i(&mut self, v: i64) -> &mut Self {
		self.tok(&v.to_string());
		self
	}
	pub fn b(&mut self, v: bool) -> &mut Self {
		self.u(v as u64)
	}
	pub fn s(&mut self, v: &str) -> &mut Self {
		let mut t = String::with_capacity(1 + v.len() * 2);
		t.push('x');
		for byte in v.bytes() {
			t.push_str(&format!("{byte:02x}"));
		}
		self.tok(&t);
		self
	}
	pub fn w(&mut self, word: &str) -> &mut Self {
		self.tok(word);
		self
	}
	pub fn opt_i(&mut self, v: Option<i64>) -> &mut Self {
		match v {
			Some(x) => self.w("S").i(x),
			None => self.w("N"),
		}
	}
	pub fn place(&mut self, p: &Place) -> &mut Self {
		self.u(p.kind as u64).i(p.owner).u(p.tab as u64).u(p.slot as u64)
	}
	pub fn dest(&mut self, d: &Dest) -> &mut Self {
		self.u(d.kind as u64).i(d.owner).u(d.tab as u64).opt_i(d.slot.map(|s| s as i64))
	}
	pub fn owner(&mut self, o: &Owner) -> &mut Self {
		self.u(o.kind as u64).i(o.id)
	}
	pub fn spec(&mut self, sp: &ItemSpec) -> &mut Self {
		self.u(sp.base as u64).u(sp.gear_slot as u64).u(sp.item_level as u64).u(sp.rarity as u64);
		self.u(sp.lines.len() as u64);
		for (st, pts) in &sp.lines {
			self.u(*st as u64).u(*pts as u64);
		}
		self.u(sp.sockets as u64).u(sp.plus as u64).b(sp.bound)
	}
	pub fn stacks(&mut self, v: &[(StackKind, u64)]) -> &mut Self {
		self.u(v.len() as u64);
		for (k, c) in v {
			self.u(k.0 as u64).u(*c);
		}
		self
	}
	fn side(&mut self, t: &TradeSide) -> &mut Self {
		self.i(t.hero).u(t.items.len() as u64);
		for it in &t.items {
			self.i(*it);
		}
		self.stacks(&t.stacks)
	}
	pub fn progress(&mut self, p: &Progress) -> &mut Self {
		self.u(p.job as u64).u(p.class_level as u64).u(p.class_xp);
		for s in p.stats {
			self.u(s as u64);
		}
		self.u(p.unspent as u64).u(p.deck.len() as u64);
		for c in &p.deck {
			self.u(*c as u64);
		}
		for b in p.belt {
			self.u(b as u64);
		}
		for w in p.waystones {
			self.i(w as i64);
		}
		self
	}
	pub fn cmd(&mut self, c: &Cmd) -> &mut Self {
		self.w(c.name());
		match c {
			Cmd::AccountBySteam { steam_id } => self.u(*steam_id),
			Cmd::AccountByDevName { name } => self.s(name),
			Cmd::ApplyFlags { changes, reason } => {
				self.u(changes.len() as u64);
				for c in changes {
					self.i(c.account).u(c.flags).u(c.drops_percent as u64).opt_i(c.banned_until);
				}
				self.s(reason)
			}
			Cmd::Clawback { items, stacks, reason } => {
				self.u(items.len() as u64);
				for it in items {
					self.i(*it);
				}
				self.u(stacks.len() as u64);
				for (o, k, c) in stacks {
					self.owner(o).u(k.0 as u64).u(*c);
				}
				self.s(reason)
			}
			Cmd::HeroCreate { account, name, race, class, look, self_found } => {
				self.i(*account).s(name).u(*race as u64).u(*class as u64).u(*look as u64).b(*self_found)
			}
			Cmd::HeroRename { hero, name } => self.i(*hero).s(name),
			Cmd::HeroDelete { hero } | Cmd::HeroUndelete { hero } => self.i(*hero),
			Cmd::HeroSave { hero, progress } => self.i(*hero).progress(progress),
			Cmd::LearnPage { hero, card } => self.i(*hero).u(*card as u64),
			Cmd::Mint { to, spec, reason } => self.dest(to).spec(spec).s(reason),
			Cmd::MoveItem { item, to } => self.i(*item).dest(to),
			Cmd::SellItem { hero, item, price } => self.i(*hero).i(*item).u(*price),
			Cmd::Socket { hero, item, socket, kind } => self.i(*hero).i(*item).u(*socket as u64).u(kind.0 as u64),
			Cmd::Unsocket { hero, item, socket } => self.i(*hero).i(*item).u(*socket as u64),
			Cmd::StackCredit { to, kind, count, minted, reason } => {
				self.owner(to).u(kind.0 as u64).u(*count).b(*minted).s(reason)
			}
			Cmd::StackDebit { from, kind, count, reason } => self.owner(from).u(kind.0 as u64).u(*count).s(reason),
			Cmd::StackTransfer { from, to, kind, count } => self.owner(from).owner(to).u(kind.0 as u64).u(*count),
			Cmd::Outing { hero, delta } => {
				self.i(*hero).u(delta.coin).u(delta.xp).u(delta.levels as u64).u(delta.items.len() as u64);
				for sp in &delta.items {
					self.spec(sp);
				}
				self.stacks(&delta.stacks).stacks(&delta.potions_used);
				match delta.waystone {
					Some((f, w)) => self.w("S").u(f as u64).i(w as i64),
					None => self.w("N"),
				}
			}
			Cmd::Trade { a, b } => self.side(a).side(b),
			Cmd::GrantEntitlement { account, kind, count, purchase } => {
				self.i(*account).u(*kind as u64).u(*count as u64).s(purchase)
			}
			Cmd::ParcelPut { kind, from, to, items, stacks, price, fee, expires, text } => {
				self.u(*kind as u64).i(*from).opt_i(*to);
				self.u(items.len() as u64);
				for it in items {
					self.i(*it);
				}
				self.stacks(stacks).u(*price).u(*fee).i(*expires).s(text)
			}
			Cmd::ParcelTake { parcel, hero, tax } => self.i(*parcel).i(*hero).u(*tax),
			Cmd::ParcelReturn { parcel } => self.i(*parcel),
		}
	}
	pub fn request(&mut self, r: &Request) -> &mut Self {
		self.w(&format!("{:032x}", r.id)).i(r.actor).i(r.now).cmd(&r.cmd)
	}
	pub fn result(&mut self, r: &Result<Reply>) -> &mut Self {
		match r {
			Ok(rep) => {
				self.w("ok");
				match rep {
					Reply::Done => self.w("done"),
					Reply::Account(a) => self.w("account").i(*a),
					Reply::Hero(h) => self.w("hero").i(*h),
					Reply::Item(id, p) => self.w("item").i(*id).place(p),
					Reply::Items(v) => {
						self.w("items").u(v.len() as u64);
						for (id, p) in v {
							self.i(*id).place(p);
						}
						self
					}
					Reply::Count(c) => self.w("count").u(*c),
					Reply::Parcel(p) => self.w("parcel").i(*p),
					Reply::Granted { new, total } => self.w("granted").b(*new).u(*total as u64),
					Reply::Clawback { removed, missing, shortfall } => {
						self.w("clawback").u(removed.len() as u64);
						for i in removed {
							self.i(*i);
						}
						self.u(missing.len() as u64);
						for i in missing {
							self.i(*i);
						}
						self.u(shortfall.len() as u64);
						for (o, k, c) in shortfall {
							self.owner(o).u(k.0 as u64).u(*c);
						}
						self
					}
				}
			}
			Err(e) => {
				self.w("err");
				match e {
					Error::Full(s) => self.w("full").s(s),
					Error::Missing(s) => self.w("missing").s(s),
					Error::NotYours(s) => self.w("notyours").s(s),
					Error::Banned { until } => self.w("banned").i(*until),
					Error::Refused => self.w("refused"),
					Error::Deleted => self.w("deleted"),
					Error::Expired => self.w("expired"),
					Error::NameTaken => self.w("nametaken"),
					Error::BadName => self.w("badname"),
					Error::SlotTaken(p) => self.w("slottaken").place(p),
					Error::LevelTooLow { need, have } => self.w("level").u(*need as u64).u(*have as u64),
					Error::Insufficient { kind, have, want } => self.w("insufficient").u(kind.0 as u64).u(*have).u(*want),
					Error::Bound(i) => self.w("bound").i(*i),
					Error::Invalid(s) => self.w("invalid").s(s),
					Error::RequestMismatch => self.w("mismatch"),
					Error::Db(s) => self.w("db").s(s),
					Error::Closed => self.w("closed"),
				}
			}
		}
	}
}

pub struct Dec<'a> {
	it: std::str::SplitAsciiWhitespace<'a>,
}

fn bad(what: &str) -> Error {
	Error::Invalid(format!("decode: {what}"))
}

impl<'a> Dec<'a> {
	pub fn new(s: &'a str) -> Dec<'a> {
		Dec { it: s.split_ascii_whitespace() }
	}
	pub fn word(&mut self) -> Result<&'a str> {
		self.it.next().ok_or_else(|| bad("end"))
	}
	pub fn u(&mut self) -> Result<u64> {
		self.word()?.parse().map_err(|_| bad("u64"))
	}
	pub fn i(&mut self) -> Result<i64> {
		self.word()?.parse().map_err(|_| bad("i64"))
	}
	fn u32(&mut self) -> Result<u32> {
		u32::try_from(self.u()?).map_err(|_| bad("u32"))
	}
	fn u16(&mut self) -> Result<u16> {
		u16::try_from(self.u()?).map_err(|_| bad("u16"))
	}
	fn u8(&mut self) -> Result<u8> {
		u8::try_from(self.u()?).map_err(|_| bad("u8"))
	}
	fn count(&mut self) -> Result<usize> {
		let n = self.u()? as usize;
		if n > 1_000_000 {
			return Err(bad("count"));
		}
		Ok(n)
	}
	pub fn b(&mut self) -> Result<bool> {
		Ok(self.u()? != 0)
	}
	pub fn s(&mut self) -> Result<String> {
		let w = self.word()?;
		let h = w.strip_prefix('x').ok_or_else(|| bad("str"))?;
		if h.len() % 2 != 0 {
			return Err(bad("hex"));
		}
		let mut out = Vec::with_capacity(h.len() / 2);
		for i in (0..h.len()).step_by(2) {
			out.push(u8::from_str_radix(&h[i..i + 2], 16).map_err(|_| bad("hex"))?);
		}
		String::from_utf8(out).map_err(|_| bad("utf8"))
	}
	fn opt_i(&mut self) -> Result<Option<i64>> {
		match self.word()? {
			"S" => Ok(Some(self.i()?)),
			"N" => Ok(None),
			_ => Err(bad("opt")),
		}
	}
	fn kind(&mut self) -> Result<PlaceKind> {
		PlaceKind::from_i64(self.i()?).ok_or_else(|| bad("place kind"))
	}
	pub fn place(&mut self) -> Result<Place> {
		Ok(Place { kind: self.kind()?, owner: self.i()?, tab: self.u32()?, slot: self.u32()? })
	}
	fn dest(&mut self) -> Result<Dest> {
		let kind = self.kind()?;
		let owner = self.i()?;
		let tab = self.u32()?;
		let slot = match self.opt_i()? {
			Some(s) => Some(u32::try_from(s).map_err(|_| bad("slot"))?),
			None => None,
		};
		Ok(Dest { kind, owner, tab, slot })
	}
	fn owner(&mut self) -> Result<Owner> {
		Ok(Owner { kind: self.kind()?, id: self.i()? })
	}
	pub fn spec(&mut self) -> Result<ItemSpec> {
		let base = self.u32()?;
		let gear_slot = self.u8()?;
		let item_level = self.u16()?;
		let rarity = self.u8()?;
		let n = self.u()? as usize;
		if n > 16 {
			return Err(bad("lines"));
		}
		let mut lines = Vec::with_capacity(n);
		for _ in 0..n {
			lines.push((self.u8()?, self.u16()?));
		}
		Ok(ItemSpec { base, gear_slot, item_level, rarity, lines, sockets: self.u8()?, plus: self.u8()?, bound: self.b()? })
	}
	fn stacks(&mut self) -> Result<Vec<(StackKind, u64)>> {
		let n = self.u()? as usize;
		if n > 100_000 {
			return Err(bad("stacks"));
		}
		let mut v = Vec::with_capacity(n);
		for _ in 0..n {
			v.push((StackKind(self.u32()?), self.u()?));
		}
		Ok(v)
	}
	fn side(&mut self) -> Result<TradeSide> {
		let hero = self.i()?;
		let n = self.u()? as usize;
		if n > 100_000 {
			return Err(bad("items"));
		}
		let mut items = Vec::with_capacity(n);
		for _ in 0..n {
			items.push(self.i()?);
		}
		Ok(TradeSide { hero, items, stacks: self.stacks()? })
	}
	fn progress(&mut self) -> Result<Progress> {
		let job = self.u8()?;
		let class_level = self.u16()?;
		let class_xp = self.u()?;
		let mut stats = [0u16; 6];
		for s in stats.iter_mut() {
			*s = self.u16()?;
		}
		let unspent = self.u16()?;
		let n = self.u()? as usize;
		if n > 1000 {
			return Err(bad("deck"));
		}
		let mut deck = Vec::with_capacity(n);
		for _ in 0..n {
			deck.push(self.u16()?);
		}
		let mut belt = [0u32; 3];
		for b in belt.iter_mut() {
			*b = self.u32()?;
		}
		let mut waystones = [0i32; 6];
		for w in waystones.iter_mut() {
			*w = i32::try_from(self.i()?).map_err(|_| bad("waystone"))?;
		}
		Ok(Progress { job, class_level, class_xp, stats, unspent, deck, belt, waystones })
	}
	pub fn cmd(&mut self) -> Result<Cmd> {
		let name = self.word()?;
		Ok(match name {
			"account_by_steam" => Cmd::AccountBySteam { steam_id: self.u()? },
			"account_by_dev_name" => Cmd::AccountByDevName { name: self.s()? },
			"apply_flags" => {
				let n = self.count()?;
				let mut changes = Vec::with_capacity(n);
				for _ in 0..n {
					changes.push(FlagChange {
						account: self.i()?,
						flags: self.u()?,
						drops_percent: self.u8()?,
						banned_until: self.opt_i()?,
					});
				}
				Cmd::ApplyFlags { changes, reason: self.s()? }
			}
			"clawback" => {
				let n = self.count()?;
				let mut items = Vec::with_capacity(n);
				for _ in 0..n {
					items.push(self.i()?);
				}
				let n = self.count()?;
				let mut stacks = Vec::with_capacity(n);
				for _ in 0..n {
					stacks.push((self.owner()?, StackKind(self.u32()?), self.u()?));
				}
				Cmd::Clawback { items, stacks, reason: self.s()? }
			}
			"hero_create" => Cmd::HeroCreate {
				account: self.i()?,
				name: self.s()?,
				race: self.u8()?,
				class: self.u8()?,
				look: self.u32()?,
				self_found: self.b()?,
			},
			"hero_rename" => Cmd::HeroRename { hero: self.i()?, name: self.s()? },
			"hero_delete" => Cmd::HeroDelete { hero: self.i()? },
			"hero_undelete" => Cmd::HeroUndelete { hero: self.i()? },
			"hero_save" => Cmd::HeroSave { hero: self.i()?, progress: self.progress()? },
			"learn_page" => Cmd::LearnPage { hero: self.i()?, card: self.u16()? },
			"mint" => Cmd::Mint { to: self.dest()?, spec: self.spec()?, reason: self.s()? },
			"move_item" => Cmd::MoveItem { item: self.i()?, to: self.dest()? },
			"sell_item" => Cmd::SellItem { hero: self.i()?, item: self.i()?, price: self.u()? },
			"socket" => Cmd::Socket { hero: self.i()?, item: self.i()?, socket: self.u8()?, kind: StackKind(self.u32()?) },
			"unsocket" => Cmd::Unsocket { hero: self.i()?, item: self.i()?, socket: self.u8()? },
			"stack_credit" => Cmd::StackCredit {
				to: self.owner()?,
				kind: StackKind(self.u32()?),
				count: self.u()?,
				minted: self.b()?,
				reason: self.s()?,
			},
			"stack_debit" => Cmd::StackDebit {
				from: self.owner()?,
				kind: StackKind(self.u32()?),
				count: self.u()?,
				reason: self.s()?,
			},
			"stack_transfer" => Cmd::StackTransfer {
				from: self.owner()?,
				to: self.owner()?,
				kind: StackKind(self.u32()?),
				count: self.u()?,
			},
			"outing" => {
				let hero = self.i()?;
				let coin = self.u()?;
				let xp = self.u()?;
				let levels = self.u16()?;
				let n = self.u()? as usize;
				if n > 10_000 {
					return Err(bad("outing items"));
				}
				let mut items = Vec::with_capacity(n);
				for _ in 0..n {
					items.push(self.spec()?);
				}
				let stacks = self.stacks()?;
				let potions_used = self.stacks()?;
				let waystone = match self.word()? {
					"S" => Some((self.u8()?, i32::try_from(self.i()?).map_err(|_| bad("waystone"))?)),
					"N" => None,
					_ => return Err(bad("opt")),
				};
				Cmd::Outing { hero, delta: OutingDelta { coin, xp, levels, items, stacks, potions_used, waystone } }
			}
			"trade" => Cmd::Trade { a: self.side()?, b: self.side()? },
			"grant_entitlement" => Cmd::GrantEntitlement {
				account: self.i()?,
				kind: EntitlementKind::from_i64(self.i()?).ok_or_else(|| bad("entitlement"))?,
				count: self.u32()?,
				purchase: self.s()?,
			},
			"parcel_put" => {
				let kind = ParcelKind::from_i64(self.i()?).ok_or_else(|| bad("parcel kind"))?;
				let from = self.i()?;
				let to = self.opt_i()?;
				let n = self.count()?;
				let mut items = Vec::with_capacity(n);
				for _ in 0..n {
					items.push(self.i()?);
				}
				Cmd::ParcelPut { kind, from, to, items, stacks: self.stacks()?, price: self.u()?, fee: self.u()?, expires: self.i()?, text: self.s()? }
			}
			"parcel_take" => Cmd::ParcelTake { parcel: self.i()?, hero: self.i()?, tax: self.u()? },
			"parcel_return" => Cmd::ParcelReturn { parcel: self.i()? },
			_ => return Err(bad("cmd name")),
		})
	}
	pub fn request(&mut self) -> Result<Request> {
		let id = u128::from_str_radix(self.word()?, 16).map_err(|_| bad("request id"))?;
		Ok(Request { id, actor: self.i()?, now: self.i()?, cmd: self.cmd()? })
	}
	pub fn result(&mut self) -> Result<Result<Reply>> {
		match self.word()? {
			"ok" => Ok(Ok(match self.word()? {
				"done" => Reply::Done,
				"account" => Reply::Account(self.i()?),
				"hero" => Reply::Hero(self.i()?),
				"item" => Reply::Item(self.i()?, self.place()?),
				"items" => {
					let n = self.u()? as usize;
					if n > 100_000 {
						return Err(bad("items"));
					}
					let mut v = Vec::with_capacity(n);
					for _ in 0..n {
						v.push((self.i()?, self.place()?));
					}
					Reply::Items(v)
				}
				"count" => Reply::Count(self.u()?),
				"parcel" => Reply::Parcel(self.i()?),
				"granted" => Reply::Granted { new: self.b()?, total: self.u32()? },
				"clawback" => {
					let n = self.count()?;
					let mut removed = Vec::with_capacity(n);
					for _ in 0..n {
						removed.push(self.i()?);
					}
					let n = self.count()?;
					let mut missing = Vec::with_capacity(n);
					for _ in 0..n {
						missing.push(self.i()?);
					}
					let n = self.count()?;
					let mut shortfall = Vec::with_capacity(n);
					for _ in 0..n {
						shortfall.push((self.owner()?, StackKind(self.u32()?), self.u()?));
					}
					Reply::Clawback { removed, missing, shortfall }
				}
				_ => return Err(bad("reply")),
			})),
			"err" => Ok(Err(match self.word()? {
				"full" => Error::Full(self.s()?),
				"missing" => Error::Missing(self.s()?),
				"notyours" => Error::NotYours(self.s()?),
				"banned" => Error::Banned { until: self.i()? },
				"refused" => Error::Refused,
				"deleted" => Error::Deleted,
				"expired" => Error::Expired,
				"nametaken" => Error::NameTaken,
				"badname" => Error::BadName,
				"slottaken" => Error::SlotTaken(self.place()?),
				"level" => Error::LevelTooLow { need: self.u16()?, have: self.u16()? },
				"insufficient" => Error::Insufficient { kind: StackKind(self.u32()?), have: self.u()?, want: self.u()? },
				"bound" => Error::Bound(self.i()?),
				"invalid" => Error::Invalid(self.s()?),
				"mismatch" => Error::RequestMismatch,
				"db" => Error::Db(self.s()?),
				"closed" => Error::Closed,
				_ => return Err(bad("error")),
			})),
			_ => Err(bad("result")),
		}
	}
}

pub fn encode_cmd(c: &Cmd) -> String {
	let mut e = Enc::new();
	e.cmd(c);
	e.s
}

pub fn encode_request(r: &Request) -> String {
	let mut e = Enc::new();
	e.request(r);
	e.s
}

pub fn encode_result(r: &Result<Reply>) -> String {
	let mut e = Enc::new();
	e.result(r);
	e.s
}

pub fn decode_request(s: &str) -> Result<Request> {
	Dec::new(s).request()
}

pub fn decode_result(s: &str) -> Result<Result<Reply>> {
	Dec::new(s).result()
}

/// FNV-1a 64.
pub fn fnv64(bytes: &[u8]) -> u64 {
	let mut h: u64 = 0xcbf2_9ce4_8422_2325;
	for b in bytes {
		h ^= *b as u64;
		h = h.wrapping_mul(0x0000_0100_0000_01b3);
	}
	h
}

/// FNV-1a 128 (for request ids derived from content, such as a trade's two lists).
pub fn fnv128(bytes: &[u8]) -> u128 {
	let mut h: u128 = 0x6c62_272e_07bb_0142_62b8_2175_6295_c58d;
	for b in bytes {
		h ^= *b as u128;
		h = h.wrapping_mul(0x0000_0000_0100_0000_0000_0000_0000_013b);
	}
	h
}

/// The hash of a request's arguments (actor and command, not the time), kept with its reply.
pub fn args_hash(actor: AccountId, c: &Cmd) -> i64 {
	let mut e = Enc::new();
	e.i(actor).cmd(c);
	fnv64(e.s.as_bytes()) as i64
}

/// The request id of a trade: both sides' lists hashed, the sides in hero order, so both parties derive the
/// same id and a changed list is a different trade.
pub fn trade_request_id(a: &TradeSide, b: &TradeSide, session: u64) -> RequestId {
	let (x, y) = if a.hero <= b.hero { (a, b) } else { (b, a) };
	let mut e = Enc::new();
	e.w("trade").u(session).side(x).side(y);
	fnv128(e.s.as_bytes())
}
