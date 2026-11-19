class_name Upgrades
extends RefCounted
## Level-up upgrades: the catalogue, the seeded roll of choices, and the effect values World reads.
## A player's upgrades are a Dictionary {upgrade index: level}. Every number here is data: `values[level - 1]`
## is the effect at that level, and the number of values is the max level.

const SWIFT := 0
const QUICK := 1
const POWER := 2
const REGEN := 3
const MAGNET := 4
const WISDOM := 5
const NOVA := 6
const LIFE := 7
## Spell weapons, one entry per World.SP_* spell (see weapon_entry), then their evolutions (evo_entry).
const W_FIRST := 8
const EVO_FIRST := 13

## [key, name, short description, weight, values per level, requires]. Passives are named for the Major Arcana
## tarot card they are drawn as (TarotArt). Indices are the constants above and are
## sent in snapshots, so append new upgrades at the end. `requires` is a list of [entry, minimum level] that
## must all hold before the entry can be offered. Spell names and evolution names match Spells.
const CATALOG: Array = [
	["swift", "THE CHARIOT", "MOVE FASTER", 10.0, [1.08, 1.16, 1.24, 1.32, 1.40], []],
	["quick", "THE MAGICIAN", "CAST FASTER", 10.0, [0.92, 0.85, 0.79, 0.74, 0.70], []],
	["power", "STRENGTH", "MORE DAMAGE", 10.0, [1.15, 1.30, 1.45, 1.60, 1.80], []],
	["regen", "TEMPERANCE", "HEAL OVER TIME", 6.0, [18.0, 12.0, 8.0], []],
	["magnet", "THE MOON", "PULL XP FROM AFAR", 7.0, [1.6, 2.2, 3.0], []],
	["wisdom", "THE HERMIT", "MORE XP", 7.0, [1.15, 1.30, 1.50], []],
	["nova", "THE TOWER", "+1 NOVA NOW", 5.0, [1.0, 1.0, 1.0, 1.0, 1.0], []],
	["life", "JUDGEMENT", "+1 LIFE NOW", 3.0, [1.0, 1.0], []],
	["w_arcane", "ARCANE BOLT", "AUTO-CAST BOLTS", 9.0, [1.0, 2.0, 3.0, 4.0, 5.0], []],
	["w_fire", "FIREBALL", "EXPLODES ON HIT", 9.0, [1.0, 2.0, 3.0, 4.0, 5.0], []],
	["w_frost", "FROST FAN", "SLOWS ENEMIES", 9.0, [1.0, 2.0, 3.0, 4.0, 5.0], []],
	["w_storm", "CHAIN LIGHTNING", "JUMPS FOE TO FOE", 9.0, [1.0, 2.0, 3.0, 4.0, 5.0], []],
	["w_star", "STARFALL", "HOMING STARS", 9.0, [1.0, 2.0, 3.0, 4.0, 5.0], []],
	["e_arcane", "ASTRAL LANCE", "PIERCING BOLTS", 40.0, [1.0], [[8, 5], [12, 1]]],
	["e_fire", "THUNDERFIRE", "BLASTS FORK LIGHTNING", 40.0, [1.0], [[9, 5], [11, 1]]],
	["e_frost", "BLIZZARD", "A STORM OF ICE", 40.0, [1.0], [[10, 5], [8, 1]]],
	["e_storm", "TEMPEST", "TWIN LIGHTNING CHAINS", 40.0, [1.0], [[11, 5], [9, 1]]],
	["e_star", "COMET RAIN", "STARS BURST INTO ICE", 40.0, [1.0], [[12, 5], [10, 1]]],
]


static func count() -> int:
	return CATALOG.size()


static func max_level(idx: int) -> int:
	return (CATALOG[idx][4] as Array).size()


static func display_name(idx: int) -> String:
	return CATALOG[idx][1]


static func key(idx: int) -> String:
	return CATALOG[idx][0]


static func description(idx: int) -> String:
	return CATALOG[idx][2]


static func weapon_entry(spell: int) -> int:
	return W_FIRST + spell


static func evo_entry(spell: int) -> int:
	return EVO_FIRST + spell


static func is_weapon(idx: int) -> bool:
	return idx >= W_FIRST and idx < EVO_FIRST


static func is_evolution(idx: int) -> bool:
	return idx >= EVO_FIRST and idx < CATALOG.size()


## Spell weapon level 0..Spells.MAX_LEVEL.
static func weapon_level(levels: Dictionary, spell: int) -> int:
	return level_of(levels, weapon_entry(spell))


static func evolved(levels: Dictionary, spell: int) -> bool:
	return level_of(levels, evo_entry(spell)) > 0


## True if `idx` is below its max level and every requirement holds.
static func available(levels: Dictionary, idx: int) -> bool:
	if idx < 0 or idx >= CATALOG.size() or level_of(levels, idx) >= max_level(idx):
		return false
	for req: Array in CATALOG[idx][5]:
		if level_of(levels, int(req[0])) < int(req[1]):
			return false
	return true


static func level_of(levels: Dictionary, idx: int) -> int:
	return int(levels.get(idx, 0))


## Effect value at the player's current level of `idx`, or `none` when they don't have it.
static func value(levels: Dictionary, idx: int, none: float) -> float:
	var lv: int = level_of(levels, idx)
	if lv <= 0:
		return none
	var vals: Array = CATALOG[idx][4]
	return float(vals[mini(lv, vals.size()) - 1])


static func move_mul(levels: Dictionary) -> float:
	return value(levels, SWIFT, 1.0)


static func cast_mul(levels: Dictionary) -> float:
	return value(levels, QUICK, 1.0)


static func damage_mul(levels: Dictionary) -> float:
	return value(levels, POWER, 1.0)


## Seconds per regenerated heart, or 0 for no regeneration.
static func regen_interval(levels: Dictionary) -> float:
	return value(levels, REGEN, 0.0)


static func magnet_mul(levels: Dictionary) -> float:
	return value(levels, MAGNET, 1.0)


static func xp_mul(levels: Dictionary) -> float:
	return value(levels, WISDOM, 1.0)


## Up to `n` different upgrades the player can still take, drawn by weight without replacement from `rng`.
## Empty when everything is maxed.
static func roll(rng: RandomNumberGenerator, levels: Dictionary, n: int) -> Array[int]:
	var pool: Array[int] = []
	for i: int in range(CATALOG.size()):
		if available(levels, i):
			pool.append(i)
	var out: Array[int] = []
	while out.size() < n and not pool.is_empty():
		var total: float = 0.0
		for i: int in pool:
			total += float(CATALOG[i][3])
		var r: float = rng.randf() * total
		var pick: int = pool[pool.size() - 1]
		for i: int in pool:
			r -= float(CATALOG[i][3])
			if r < 0.0:
				pick = i
				break
		out.append(pick)
		pool.erase(pick)
	return out


## Raises `idx` by one level in `levels`. Returns false if it is unknown or already maxed.
static func take(levels: Dictionary, idx: int) -> bool:
	if not available(levels, idx):
		return false
	levels[idx] = level_of(levels, idx) + 1
	return true
