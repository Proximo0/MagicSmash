//! Monster cards (42 kinds and 8 bosses), boss tiers and the pages of the deck (rules sections 8 and 9).
//!
//! R2 builds the bosses in `realm/core`; until its table exists this crate holds the tier list. A boss is
//! `0..8` in the order of the contract's table; 7 is the world boss.

use realm_core::tables::*;

pub const BOSS_COUNT: usize = 8;
pub const WORLD_BOSS: u8 = 7;
/// Monster card ids: kinds 0..42, then the bosses.
pub const KIND_CARDS: u32 = 42;
pub const CARD_COUNT: u32 = KIND_CARDS + BOSS_COUNT as u32;

#[derive(Clone, Copy, Debug)]
pub struct BossRow {
	pub name: &'static str,
	/// The field it rises in; the world boss rides any (field 5 is used for its level and base tier).
	pub field: u8,
	/// The page of the deck its first kill gives (0-based card index, 12 to 29).
	pub page: u8,
}

pub const BOSSES: [BossRow; BOSS_COUNT] = [
	BossRow { name: "THE HARVESTER", field: 0, page: 13 },
	BossRow { name: "THE HANGING TREE", field: 1, page: 19 },
	BossRow { name: "MOTHER OF LEECHES", field: 2, page: 17 },
	BossRow { name: "THE GOAT PROPHET", field: 3, page: 14 },
	BossRow { name: "THE CHANDELIER", field: 4, page: 12 },
	BossRow { name: "THE GHOSTWRITER", field: 4, page: 15 },
	BossRow { name: "THE UNMADE KING", field: 5, page: 18 },
	BossRow { name: "DEATH, THE PALE RIDER", field: 5, page: 20 },
];

/// Pages exist for deck cards 12 to 29 (0-based; the contract's 13 to 30).
pub const PAGE_FIRST: u32 = 12;
pub const PAGE_LAST: u32 = 29;

/// A card's rule when socketed: points of one stat (like one more line), and a percent against its own kind
/// (damage dealt to it, damage taken from it). The core does not read `own_pct` yet.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CardRule {
	pub stat: u8,
	pub points: u16,
	pub own_pct: u8,
}

pub const KIND_CARD_BASE_POINTS: u16 = 3;
pub const KIND_CARD_POINTS_PER_FIELD: u16 = 2;
pub const KIND_CARD_OWN_PCT: u8 = 10;
pub const BOSS_CARD_BASE_POINTS: u16 = 16;
pub const BOSS_CARD_POINTS_PER_FIELD: u16 = 4;
pub const BOSS_CARD_OWN_PCT: u8 = 15;
/// The stat of each boss's card.
pub const BOSS_CARD_STAT: [u8; BOSS_COUNT] = [0, 3, 3, 4, 1, 2, 0, 5];

/// The stat a kind's card gives: the first behaviour it has, in this order.
pub const STAT_BY_BEHAVIOUR: [(Beh, u8); 13] = [
	(HOWLER, 5),
	(MENDER, 3),
	(DRAINER, 3),
	(BRUTE, 3),
	(SHIELDED, 4),
	(WAILER, 4),
	(SPITTER, 1),
	(LOBBER, 1),
	(LEAPER, 2),
	(RUNNER, 2),
	(SWARM, 2),
	(BURSTER, 0),
	(WALKER, 0),
];

pub fn card_rule(card: u32) -> Option<CardRule> {
	if card < KIND_CARDS {
		let k = &KINDS[card as usize];
		let stat = STAT_BY_BEHAVIOUR.iter().find(|(b, _)| k.beh & b != 0).map(|(_, s)| *s).unwrap_or(0);
		Some(CardRule {
			stat,
			points: KIND_CARD_BASE_POINTS + KIND_CARD_POINTS_PER_FIELD * k.field as u16,
			own_pct: KIND_CARD_OWN_PCT,
		})
	} else if card < CARD_COUNT {
		let b = (card - KIND_CARDS) as usize;
		Some(CardRule {
			stat: BOSS_CARD_STAT[b],
			points: BOSS_CARD_BASE_POINTS + BOSS_CARD_POINTS_PER_FIELD * BOSSES[b].field as u16,
			own_pct: BOSS_CARD_OWN_PCT,
		})
	} else {
		None
	}
}

pub fn card_name(card: u32) -> String {
	if card < KIND_CARDS {
		format!("CARD OF {}", KINDS[card as usize].name.to_uppercase().trim_start_matches("THE "))
	} else if card < CARD_COUNT {
		format!("CARD OF {}", BOSSES[(card - KIND_CARDS) as usize].name)
	} else {
		format!("CARD {card}")
	}
}
