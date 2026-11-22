//! HORDE & HEARTH's loot, on the server only (rules section 9, `docs/realm/economy.md` part 1).
//!
//! The API for the gateway and field hosts:
//! - `roll(secret, &RollKey, &Credit, &Source, &mut RollGate) -> Vec<Found>`: what one credited hero gets from a
//!   `KILL` event (`Source::Kill`) or a `REWARD` (`TideCache`, `BossChest`, `WorldChest`). `Source::from_kill`
//!   reads a core event. Seeded from the server secret and the event's place in the field's output.
//! - `Haul::take(found)` keeps the haul's share (COMMON and UNCOMMON items, materials) and gives back the rest;
//!   `deliver(store, meta, hero, &kept)` writes those to the store; `Haul::into_delta` joins the haul to an outing.
//! - `Smith::new(store, secret)`: `salvage`, `upgrade`, `reroll`, `socket`, `unsocket`, `fuse`.
//! - Every mint goes through the `Store` trait as the server (actor 0): an origin and a ledger row each.

pub mod apply;
pub mod cards;
pub mod gear;
pub mod haul;
pub mod rng;
pub mod roll;
pub mod smith;
pub mod tables;

pub use apply::{deliver, drops_percent_of, sub_id, Delivered};
pub use haul::Haul;
pub use roll::{power_coin, reduced_percent, roll, roll_seed, scaled, Credit, Found, Reason, RollGate, RollKey, Source, What};
pub use smith::{Cost, Salvaged, Smith, Upgraded};

impl Source {
	/// The source of a core `Event::Kill`; None for any other event.
	pub fn from_kill(e: &realm_core::Event) -> Option<Source> {
		match *e {
			realm_core::Event::Kill { kind, level, flags, .. } => Some(Source::Kill { kind, level, flags }),
			_ => None,
		}
	}
}
