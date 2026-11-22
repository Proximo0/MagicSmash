//! Writing drops to the store. Every mint is a store request by the server (actor 0), so each one has an
//! origin (the hero's account) and a ledger row; this crate has no other way to make an item or a stack.

use crate::rng::mix;
use crate::roll::{Found, What};
use realm_store::*;

/// A request id for part `i` of the operation `id` (so a retry of the whole repeats every part's id).
pub fn sub_id(id: RequestId, i: u32) -> RequestId {
	let hi = mix(id as u64, i as u64 ^ 0x5bd1_e995);
	let lo = mix((id >> 64) as u64, hi ^ i as u64);
	(hi as u128) << 64 | lo as u128
}

pub fn request(m: Meta, i: u32, cmd: Cmd) -> Request {
	Request { id: sub_id(m.id, i), actor: 0, now: m.now, cmd }
}

/// What `deliver` did.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Delivered {
	pub items: Vec<(ItemId, Place)>,
	pub stacks: Vec<(StackKind, u64)>,
	/// How many went to the hero's mail because the bag was full.
	pub mailed: u32,
	/// Drops the store refused, by index in the list given (a deleted hero, for one).
	pub failed: Vec<(usize, Error)>,
}

/// Writes kept drops for a hero: items into the bag and stacks into the bag's stacks, with mail as the
/// overflow when a bag is full. One transaction for the lot, then one more for any overflow. `m.id` names the
/// call: repeating it repeats nothing.
pub fn deliver<S: Store + ?Sized>(store: &S, m: Meta, hero: HeroId, drops: &[Found]) -> Delivered {
	let mut out = Delivered::default();
	let build = |to_mail: bool, d: &Found| -> Cmd {
		match &d.what {
			What::Item(spec) => {
				let to = if to_mail { Dest::any(PlaceKind::Mail, hero) } else { Dest::bag(hero) };
				Cmd::Mint { to, spec: spec.clone(), reason: d.reason.mint().into() }
			}
			What::Stack(kind, n) => {
				let to = if to_mail { Owner { kind: PlaceKind::Mail, id: hero } } else { Owner::bag(hero) };
				Cmd::StackCredit { to, kind: *kind, count: *n, minted: true, reason: d.reason.mint().into() }
			}
		}
	};
	if drops.is_empty() {
		return out;
	}
	let reqs: Vec<Request> = drops.iter().enumerate().map(|(i, d)| request(m, i as u32, build(false, d))).collect();
	let replies = store.submit_batch(reqs);
	let mut overflow = Vec::new();
	for (i, r) in replies.into_iter().enumerate() {
		match r {
			Ok(Reply::Item(id, p)) => out.items.push((id, p)),
			Ok(Reply::Count(_)) => {
				if let What::Stack(k, n) = &drops[i].what {
					out.stacks.push((*k, *n));
				}
			}
			Ok(_) => {}
			Err(Error::Full(_)) => overflow.push(i),
			Err(e) => out.failed.push((i, e)),
		}
	}
	if !overflow.is_empty() {
		let reqs: Vec<Request> = overflow.iter().map(|&i| request(m, 1000 + i as u32, build(true, &drops[i]))).collect();
		for (&i, r) in overflow.iter().zip(store.submit_batch(reqs)) {
			match r {
				Ok(Reply::Item(id, p)) => {
					out.items.push((id, p));
					out.mailed += 1;
				}
				Ok(Reply::Count(_)) => {
					if let What::Stack(k, n) = &drops[i].what {
						out.stacks.push((*k, *n));
					}
					out.mailed += 1;
				}
				Ok(_) => {}
				Err(e) => out.failed.push((i, e)),
			}
		}
	}
	out
}

/// The percent of normal drops an account gets, read from the store.
pub fn drops_percent_of<S: Store + ?Sized>(store: &S, account: AccountId) -> Result<u8> {
	Ok(match store.account(account)? {
		Some(a) => crate::roll::reduced_percent(a.flags, a.drops_percent),
		None => 100,
	})
}
