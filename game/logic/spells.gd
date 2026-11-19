class_name Spells
extends RefCounted
## Spell weapons: per-level stats and the evolutions. Pure data plus lookups; World casts with these numbers.
## A wizard's weapon level lives in their upgrades Dictionary (Upgrades.weapon_entry(spell)); an evolution is
## its own upgrade entry (Upgrades.evo_entry(spell)) that needs the weapon at MAX_LEVEL plus a partner spell.

const COUNT := 5
const MAX_LEVEL := 5

## Per spell (World.SP_* order). Arrays are per level 1..MAX_LEVEL.
## cd: seconds between casts. dmg: damage per hit. n: bolts, fireballs, shards, chain jumps or stars.
## speed px/s, r: hit radius px, life: seconds, spread: radians between projectiles.
const STATS: Array = [
	{"name": "ARCANE BOLT", "cd": [0.16, 0.15, 0.14, 0.13, 0.12], "dmg": [1.0, 1.15, 1.3, 1.45, 1.6],
		"n": [1, 1, 2, 2, 3], "speed": 310.0, "r": 3.0, "life": 1.0, "spread": 0.12},
	{"name": "FIREBALL", "cd": [1.2, 1.1, 1.0, 0.9, 0.8], "dmg": [2.0, 2.4, 2.8, 3.2, 3.8],
		"n": [1, 1, 2, 2, 3], "speed": 200.0, "r": 4.5, "life": 1.6, "spread": 0.3},
	{"name": "FROST FAN", "cd": [1.0, 0.95, 0.9, 0.85, 0.8], "dmg": [0.85, 0.95, 1.05, 1.15, 1.3],
		"n": [3, 4, 5, 6, 7], "speed": 255.0, "r": 2.5, "life": 0.75, "spread": 0.17},
	{"name": "CHAIN LIGHTNING", "cd": [0.9, 0.8, 0.7, 0.65, 0.6], "dmg": [1.7, 1.9, 2.1, 2.3, 2.6],
		"n": [3, 4, 5, 6, 7], "speed": 0.0, "r": 0.0, "life": 0.0, "spread": 0.0},
	{"name": "STARFALL", "cd": [1.1, 1.0, 0.9, 0.8, 0.7], "dmg": [1.35, 1.5, 1.65, 1.8, 2.0],
		"n": [2, 2, 3, 3, 4], "speed": 175.0, "r": 3.0, "life": 2.2, "spread": 0.45},
]

## Evolutions, per base spell. partner: the other spell the wizard must own. The stats replace the level-5
## numbers. pierce: extra enemies a projectile passes through. Specials (World reads them):
## chain: lightning jumps from each fireball blast. chains: separate lightning chains per cast.
## slow: seconds an enemy stays slowed. burst: radius of a frost burst where a star hits.
const EVOS: Array = [
	{"name": "ASTRAL LANCE", "desc": "PIERCING BOLTS", "partner": 4,
		"cd": 0.09, "dmg": 2.2, "n": 3, "pierce": 2},
	{"name": "THUNDERFIRE", "desc": "BLASTS FORK LIGHTNING", "partner": 3,
		"cd": 0.75, "dmg": 4.4, "n": 3, "chain": 3},
	{"name": "BLIZZARD", "desc": "A STORM OF ICE", "partner": 0,
		"cd": 0.7, "dmg": 1.5, "n": 9, "pierce": 1, "slow": 3.5},
	{"name": "TEMPEST", "desc": "TWIN LIGHTNING CHAINS", "partner": 1,
		"cd": 0.5, "dmg": 3.0, "n": 9, "chains": 2},
	{"name": "COMET RAIN", "desc": "STARS BURST INTO ICE", "partner": 2,
		"cd": 0.6, "dmg": 2.6, "n": 6, "burst": 30.0},
]

## Slow applied by a frost shard that has not evolved, seconds.
const FROST_SLOW := 1.8
## Range of an un-evolved chain lightning's first jump and later jumps, px; Tempest adds TEMPEST_RANGE_MUL.
const CHAIN_FIRST_RANGE := 140.0
const CHAIN_JUMP_RANGE := 70.0
const TEMPEST_RANGE_MUL := 1.5
## Share of a star's damage that Comet Rain's frost burst deals to each other enemy in its radius.
const BURST_DMG := 0.5
## Damage kept on each further chain jump.
const CHAIN_FALLOFF := 0.85


static func spell_name(spell: int) -> String:
	return STATS[spell]["name"]


static func _at(spell: int, key: String, level: int) -> float:
	var vals: Array = STATS[spell][key]
	return float(vals[clampi(level, 1, MAX_LEVEL) - 1])


## Seconds between casts at `level` (1..MAX_LEVEL), or the evolution's when `evolved`.
static func cooldown(spell: int, level: int, evolved: bool) -> float:
	if evolved:
		return float(EVOS[spell]["cd"])
	return _at(spell, "cd", level)


static func damage(spell: int, level: int, evolved: bool) -> float:
	if evolved:
		return float(EVOS[spell]["dmg"])
	return _at(spell, "dmg", level)


static func count(spell: int, level: int, evolved: bool) -> int:
	if evolved:
		return int(EVOS[spell]["n"])
	return int(_at(spell, "n", level))


## A number from STATS that does not change with level (speed, r, life, spread).
static func stat(spell: int, key: String) -> float:
	return float(STATS[spell][key])


## An evolution special (pierce, chain, chains, slow, burst), or `none` when this spell has no such special.
static func evo_value(spell: int, key: String, none: float) -> float:
	return float(EVOS[spell].get(key, none))


static func partner(spell: int) -> int:
	return int(EVOS[spell]["partner"])
