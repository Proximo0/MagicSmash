class_name Races
extends RefCounted
## Hero races (docs/classes_design.md section 3): the stat points and the trait of each, and the body the art
## paints. Pure data plus accessors; World.apply_hero and Hero read them. Append new races at the end: a hero's
## save stores the KEY, the snapshot row and the seats carry the index.

const HUMAN := 0
const ELF := 1
const DWARF := 2
const ORC := 3

## Traits: [key, name, value]. What each value means:
## SCHOLAR: share of class XP added (Hero.run_xp). FAR_SIGHT: share added to the XP magnet's reach.
## STURDY: share added to the hurt safety after a hit (World.Player.safe_mul). FURY: share of damage added at FURY_HEARTS hearts or fewer.
const TR_SCHOLAR := 0
const TR_FAR_SIGHT := 1
const TR_STURDY := 2
const TR_FURY := 3
const TRAITS: Array = [
	["scholar", "+5% CLASS XP", 0.05],
	["far_sight", "XP FLIES IN FROM 25% FARTHER", 0.25],
	["sturdy", "UNHURT 50% LONGER AFTER A HIT", 0.5],
	["fury", "+10% DAMAGE AT 2 HEARTS OR FEWER", 0.10],
]
const FURY_HEARTS := 2

## Builds the art paints a hero's body in.
const BUILD_MEDIUM := 0
const BUILD_SHORT := 1
const BUILD_TALL := 2

const R_KEY := 0
const R_NAME := 1
const R_STATS := 2 # stat points [MIGHT, FOCUS, SWIFT, VIGOR, WARD, FORTUNE] (Loot.ST_* order)
const R_TRAIT := 3
const R_BUILD := 4

## [key, name, stats, trait, build].
const ROWS: Array = [
	["human", "HUMAN", [1, 1, 1, 1, 1, 1], TR_SCHOLAR, BUILD_MEDIUM],
	["elf", "ELF", [0, 3, 4, 0, 0, 0], TR_FAR_SIGHT, BUILD_MEDIUM],
	["dwarf", "DWARF", [0, 0, 0, 4, 3, 0], TR_STURDY, BUILD_SHORT],
	["orc", "ORC", [5, 0, 0, 2, 0, 0], TR_FURY, BUILD_TALL],
]


static func count() -> int:
	return ROWS.size()


static func _race_row(r: int) -> Array:
	return ROWS[clampi(r, 0, ROWS.size() - 1)]


## The race index of a saved key, -1 when unknown.
static func index_of(key: String) -> int:
	for i: int in range(ROWS.size()):
		if ROWS[i][R_KEY] == key:
			return i
	return -1


static func key(r: int) -> String:
	return _race_row(r)[R_KEY]


static func race_name(r: int) -> String:
	return _race_row(r)[R_NAME]


## Stat points the race adds, in Loot.ST_* order.
static func stat_points(r: int) -> Array:
	return (_race_row(r)[R_STATS] as Array).duplicate()


static func trait_of(r: int) -> int:
	return int(_race_row(r)[R_TRAIT])


static func build(r: int) -> int:
	return int(_race_row(r)[R_BUILD])


static func trait_name(t: int) -> String:
	return TRAITS[clampi(t, 0, TRAITS.size() - 1)][1]


static func trait_value(t: int) -> float:
	return float(TRAITS[clampi(t, 0, TRAITS.size() - 1)][2])


## The value of race `r`'s trait when it is `t`, else 0.
static func trait_amount(r: int, t: int) -> float:
	return trait_value(t) if trait_of(r) == t else 0.0
