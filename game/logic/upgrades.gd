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

## [key, name, short description, weight, values per level]. Indices are the constants above and are sent
## in snapshots, so append new upgrades at the end.
const CATALOG: Array = [
	["swift", "SWIFT FEET", "MOVE FASTER", 10.0, [1.08, 1.16, 1.24, 1.32, 1.40]],
	["quick", "QUICK CAST", "CAST FASTER", 10.0, [0.92, 0.85, 0.79, 0.74, 0.70]],
	["power", "SPELL POWER", "MORE DAMAGE", 10.0, [1.15, 1.30, 1.45, 1.60, 1.80]],
	["regen", "REGENERATE", "HEAL OVER TIME", 6.0, [18.0, 12.0, 8.0]],
	["magnet", "MAGNET", "PULL XP FROM AFAR", 7.0, [1.6, 2.2, 3.0]],
	["wisdom", "WISDOM", "MORE XP", 7.0, [1.15, 1.30, 1.50]],
	["nova", "NOVA CHARGE", "+1 NOVA NOW", 5.0, [1.0, 1.0, 1.0, 1.0, 1.0]],
	["life", "SECOND WIND", "+1 LIFE NOW", 3.0, [1.0, 1.0]],
]


static func count() -> int:
	return CATALOG.size()


static func max_level(idx: int) -> int:
	return (CATALOG[idx][4] as Array).size()


static func display_name(idx: int) -> String:
	return CATALOG[idx][1]


static func description(idx: int) -> String:
	return CATALOG[idx][2]


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
		if level_of(levels, i) < max_level(i):
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
	if idx < 0 or idx >= CATALOG.size() or level_of(levels, idx) >= max_level(idx):
		return false
	levels[idx] = level_of(levels, idx) + 1
	return true
