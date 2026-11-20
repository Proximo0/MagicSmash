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
## Spell weapons, one row per World.SP_* spell (weapon_entry finds them by their `spell` column).
const W_ARCANE := 8
const W_FIRE := 9
const W_FROST := 10
const W_STORM := 11
const W_STAR := 12
const W_RUNE := 13
## Their evolutions (evo_entry finds them by kind and `spell`).
const E_ARCANE := 14
const E_FIRE := 15
const E_FROST := 16
const E_STORM := 17
const E_STAR := 18
const E_RUNE := 19

## Row kinds (the `kind` column). A SPELL takes a spell slot and a PASSIVE a passive slot (World.slot_cap); an
## INSTANT acts once when taken; an EVOLUTION replaces its spell in the same slot; a MINOR arcana card fills a
## short hand.
const PASSIVE := 0
const INSTANT := 1
const SPELL := 2
const EVOLUTION := 3
const MINOR := 4
## Column indices of a CATALOG row.
const C_KEY := 0
const C_WEIGHT := 3
const C_VALUES := 4
const C_REQUIRES := 5
const C_KIND := 6
const C_SPELL := 7
## A slot cap that never binds: (spell slots, passive slots). Today's play has no slot limit.
const UNCAPPED := Vector2i(99, 99)

## [key, name, short description, weight, values per level, requires, kind, spell]. Passives are named for the
## Major Arcana tarot card they are drawn as (TarotArt). Indices are the constants above and are sent in
## snapshots. The catalogue is append-only: a new row goes at the end and no row ever moves (nothing saved holds
## an id, but both sides of a LAN game must agree). `requires` is a list of [entry, minimum level] that must all
## hold before the entry can be offered. `kind` is one of the kinds above; `spell` is the World.SP_* spell of a
## SPELL or EVOLUTION row, -1 otherwise. Spell names and evolution names match Spells.
const CATALOG: Array = [
	["swift", "THE CHARIOT", "MOVE FASTER", 10.0, [1.08, 1.16, 1.24, 1.32, 1.40], [], PASSIVE, -1],
	["quick", "THE MAGICIAN", "CAST FASTER", 10.0, [0.92, 0.85, 0.79, 0.74, 0.70], [], PASSIVE, -1],
	["power", "STRENGTH", "MORE DAMAGE", 10.0, [1.15, 1.30, 1.45, 1.60, 1.80], [], PASSIVE, -1],
	["regen", "TEMPERANCE", "HEAL OVER TIME", 6.0, [18.0, 12.0, 8.0], [], PASSIVE, -1],
	["magnet", "THE MOON", "WIDER XP PULL", 7.0, [1.6, 2.2, 3.0], [], PASSIVE, -1],
	["wisdom", "THE HERMIT", "MORE XP", 7.0, [1.15, 1.30, 1.50], [], PASSIVE, -1],
	["nova", "THE TOWER", "+1 NOVA NOW", 5.0, [1.0, 1.0, 1.0, 1.0, 1.0], [], INSTANT, -1],
	["life", "JUDGEMENT", "+1 LIFE NOW", 3.0, [1.0, 1.0], [], INSTANT, -1],
	["w_arcane", "ARCANE BOLT", "AUTO-AIM BOLTS", 9.0, [1.0, 2.0, 3.0, 4.0, 5.0], [], SPELL, 0],
	["w_fire", "FIREBALL", "BURSTS ON HIT", 9.0, [1.0, 2.0, 3.0, 4.0, 5.0], [], SPELL, 1],
	["w_frost", "FROST FAN", "SLOWS ENEMIES", 9.0, [1.0, 2.0, 3.0, 4.0, 5.0], [], SPELL, 2],
	["w_storm", "CHAIN LIGHTNING", "CHAINS TO FOES", 9.0, [1.0, 2.0, 3.0, 4.0, 5.0], [], SPELL, 3],
	["w_star", "STARFALL", "HOMING STARS", 9.0, [1.0, 2.0, 3.0, 4.0, 5.0], [], SPELL, 4],
	["w_rune", "RUNE CIRCLE", "BURNING SIGILS", 9.0, [1.0, 2.0, 3.0, 4.0, 5.0], [], SPELL, 5],
	["e_arcane", "ASTRAL LANCE", "PIERCING BOLTS", 40.0, [1.0], [[W_ARCANE, 5], [W_STAR, 1]], EVOLUTION, 0],
	["e_fire", "THUNDERFIRE", "ZAPPING BLASTS", 40.0, [1.0], [[W_FIRE, 5], [W_STORM, 1]], EVOLUTION, 1],
	["e_frost", "BLIZZARD", "A STORM OF ICE", 40.0, [1.0], [[W_FROST, 5], [W_ARCANE, 1]], EVOLUTION, 2],
	["e_storm", "TEMPEST", "TWIN CHAINS", 40.0, [1.0], [[W_STORM, 5], [W_FIRE, 1]], EVOLUTION, 3],
	["e_star", "COMET RAIN", "ICY STARBURSTS", 40.0, [1.0], [[W_STAR, 5], [W_FROST, 1]], EVOLUTION, 4],
	["e_rune", "SEAL OF SOLOMON", "SIGILS PULL IN", 40.0, [1.0], [[W_RUNE, 5], [W_STAR, 1]], EVOLUTION, 5],
]


static func count() -> int:
	return CATALOG.size()


static func max_level(idx: int) -> int:
	return (CATALOG[idx][C_VALUES] as Array).size()


static func display_name(idx: int) -> String:
	return CATALOG[idx][1]


static func key(idx: int) -> String:
	return CATALOG[idx][0]


static func description(idx: int) -> String:
	return CATALOG[idx][2]


static func kind(idx: int) -> int:
	return int(CATALOG[idx][C_KIND])


## The World.SP_* spell of a SPELL or EVOLUTION row, -1 for any other row.
static func spell_of(idx: int) -> int:
	return int(CATALOG[idx][C_SPELL])


## For an EVOLUTION row, the SPELL row it evolves; -1 for any other row.
static func evolves(idx: int) -> int:
	if kind(idx) != EVOLUTION:
		return -1
	return weapon_entry(spell_of(idx))


## The SPELL and EVOLUTION row of each World.SP_* spell, built once from the kind and spell columns.
static var _weapon_rows: Array[int] = []
static var _evo_rows: Array[int] = []


static func _index_rows() -> void:
	_weapon_rows.resize(Spells.COUNT)
	_weapon_rows.fill(-1)
	_evo_rows.resize(Spells.COUNT)
	_evo_rows.fill(-1)
	for i: int in range(CATALOG.size()):
		var sp: int = spell_of(i)
		if sp < 0 or sp >= Spells.COUNT:
			continue
		if kind(i) == SPELL:
			_weapon_rows[sp] = i
		elif kind(i) == EVOLUTION:
			_evo_rows[sp] = i


static func weapon_entry(spell: int) -> int:
	if _weapon_rows.is_empty():
		_index_rows()
	return _weapon_rows[spell]


static func evo_entry(spell: int) -> int:
	if _evo_rows.is_empty():
		_index_rows()
	return _evo_rows[spell]


static func is_weapon(idx: int) -> bool:
	return idx >= 0 and idx < CATALOG.size() and kind(idx) == SPELL


static func is_evolution(idx: int) -> bool:
	return idx >= 0 and idx < CATALOG.size() and kind(idx) == EVOLUTION


## Spell weapon level 0..Spells.MAX_LEVEL.
static func weapon_level(levels: Dictionary, spell: int) -> int:
	return level_of(levels, weapon_entry(spell))


static func evolved(levels: Dictionary, spell: int) -> bool:
	return level_of(levels, evo_entry(spell)) > 0


## Slots in use: (SPELL rows owned, PASSIVE rows owned). Evolutions share their spell's slot; instants and minor
## arcana take none.
static func slots_used(levels: Dictionary) -> Vector2i:
	var out := Vector2i.ZERO
	for i: Variant in levels:
		var idx := int(i)
		if level_of(levels, idx) <= 0 or idx < 0 or idx >= CATALOG.size():
			continue
		match kind(idx):
			SPELL:
				out.x += 1
			PASSIVE:
				out.y += 1
	return out


## The owned rows of one kind, in the order they were taken (a Dictionary keeps its insertion order).
static func slot_ids(levels: Dictionary, of_kind: int) -> Array[int]:
	var out: Array[int] = []
	for i: Variant in levels:
		var idx := int(i)
		if idx >= 0 and idx < CATALOG.size() and level_of(levels, idx) > 0 and kind(idx) == of_kind:
			out.append(idx)
	return out


## True if `idx` is below its max level, every requirement holds, it is not banished, and a new SPELL or
## PASSIVE row still has a free slot under `cap` (spell slots, passive slots).
static func available(levels: Dictionary, idx: int, cap: Vector2i = UNCAPPED, banned: Dictionary = {}) -> bool:
	if idx < 0 or idx >= CATALOG.size() or level_of(levels, idx) >= max_level(idx):
		return false
	for req: Array in CATALOG[idx][C_REQUIRES]:
		if level_of(levels, int(req[0])) < int(req[1]):
			return false
	if banned.has(idx):
		return false
	if level_of(levels, idx) == 0 and cap != UNCAPPED:
		var used := slots_used(levels)
		if kind(idx) == SPELL and used.x >= cap.x:
			return false
		if kind(idx) == PASSIVE and used.y >= cap.y:
			return false
	return true


## How much a wizard who picks at once (an apprentice) wants `idx` next, higher first: an evolution, then a
## spell it already casts, then a new spell, then a passive, then an instant; ties go by the row's weight.
## Nothing reads it yet.
static func pick_score(levels: Dictionary, idx: int) -> float:
	var w := float(CATALOG[idx][C_WEIGHT])
	match kind(idx):
		EVOLUTION:
			return 400.0 + w
		SPELL:
			return (300.0 if level_of(levels, idx) > 0 else 200.0) + w
		PASSIVE:
			return 100.0 + w
	return w


static func level_of(levels: Dictionary, idx: int) -> int:
	return int(levels.get(idx, 0))


## Effect value at the player's current level of `idx`, or `none` when they don't have it.
static func value(levels: Dictionary, idx: int, none: float) -> float:
	var lv: int = level_of(levels, idx)
	if lv <= 0:
		return none
	var vals: Array = CATALOG[idx][C_VALUES]
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


## Up to `n` different upgrades the player can still take (available under `cap` and `banned`), drawn by weight
## without replacement from `rng`. Empty when everything is maxed.
static func roll(rng: RandomNumberGenerator, levels: Dictionary, n: int, cap: Vector2i = UNCAPPED,
		banned: Dictionary = {}) -> Array[int]:
	var pool: Array[int] = []
	for i: int in range(CATALOG.size()):
		if available(levels, i, cap, banned):
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
