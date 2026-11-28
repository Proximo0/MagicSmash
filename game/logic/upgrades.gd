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
## The Minor Arcana: they fill a hand that would be short (fewer than World.tune.level_choices cards left to learn).
const M_CUPS := 20
const M_PENTACLES := 21
const M_SWORDS := 22
const M_WANDS := 23
const MINORS: Array[int] = [M_CUPS, M_PENTACLES, M_SWORDS, M_WANDS]
## Wave 3: two spells, their partner passives and their evolutions, then the knight's CLEAVE (a class weapon: it
## requires itself, so only a hero who starts with it is ever offered it), then its evolution WHIRLWIND
## (CLEAVE at its top level and STRENGTH, a passive no other spell pairs with: requiring CLEAVE, it is a knight's
## alone).
const W_BONE := 24
const W_CANDLE := 25
const JUSTICE := 26
const LOVERS := 27
const E_BONE := 28
const E_CANDLE := 29
const W_CLEAVE := 30
const E_CLEAVE := 31

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
## A slot cap that never binds: (spell slots, passive slots).
const UNCAPPED := Vector2i(99, 99)
## The slots every wizard has (spells, passives) until the first boss falls, and after.
const SLOTS_EARLY := Vector2i(3, 3)
const SLOTS_LATE := Vector2i(4, 4)
## A row that completes a pair (see pairs_with) weighs this many times its weight in a roll.
const PARTNER_WEIGHT := 4.0
## Redraws and banishes each wizard has for a run.
const REDRAWS := 2
const BANISHES := 2
## Input field 6 (the card taken) beyond a card index: REDRAW_INPUT redraws the hand; BANISH_INPUT + c banishes
## card c (it leaves this wizard's pool for the run) and redraws.
const REDRAW_INPUT := -2
const BANISH_INPUT := 10

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
	# Minor Arcana: never rolled, only dealt into a short hand; taken any number of times (values[0] each time).
	["cups", "CUPS", "HEAL 1 HEART", 1.0, [1.0], [], MINOR, -1],
	["pentacles", "PENTACLES", "+10 GOLD", 1.0, [10.0], [], MINOR, -1],
	["swords", "SWORDS", "+1 NOVA", 1.0, [1.0], [], MINOR, -1],
	["wands", "WANDS", "+3% DAMAGE", 1.0, [0.03], [], MINOR, -1],
	["w_bone", "BONE SPEAR", "PIERCES ALL", 9.0, [1.0, 2.0, 3.0, 4.0, 5.0], [], SPELL, 6],
	["w_candle", "VIGIL CANDLE", "HASTING LIGHT", 9.0, [1.0, 2.0, 3.0, 4.0, 5.0], [], SPELL, 7],
	# JUSTICE: the chance a slain foe bursts (JUSTICE_SHARE of its health within JUSTICE_RADIUS px).
	["justice", "JUSTICE", "FOES BURST", 7.0, [0.06, 0.12, 0.18], [], PASSIVE, -1],
	# THE LOVERS: cast speed within LOVERS_RANGE px of an ally (an apprentice counts), LOVERS_ALONE of it alone.
	["lovers", "THE LOVERS", "HASTE TOGETHER", 7.0, [0.08, 0.16, 0.24], [], PASSIVE, -1],
	["e_bone", "OSSUARY LANCE", "SPLINTER HITS", 40.0, [1.0], [[W_BONE, 5], [JUSTICE, 1]], EVOLUTION, 6],
	["e_candle", "CONSECRATION", "HEALING LIGHT", 40.0, [1.0], [[W_CANDLE, 5], [LOVERS, 1]], EVOLUTION, 7],
	["w_cleave", "CLEAVE", "A SWEEPING ARC", 9.0, [1.0, 2.0, 3.0, 4.0, 5.0], [[W_CLEAVE, 1]], SPELL, 8],
	["e_cleave", "WHIRLWIND", "A FULL CIRCLE", 40.0, [1.0], [[W_CLEAVE, 5], [POWER, 1]], EVOLUTION, 8],
]
## JUSTICE's burst: the share of the slain foe's max health it deals, and its radius, px.
const JUSTICE_SHARE := 0.6
const JUSTICE_RADIUS := 30.0
## THE LOVERS: how near an ally must stand, px, and the share of the bonus she keeps alone.
const LOVERS_RANGE := 60.0
const LOVERS_ALONE := 0.5


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


## The row that pairs with `spell` for its evolution: the evolution's requirement other than the spell itself
## (a SPELL row today; a PASSIVE row for later spells), or -1.
static func partner_row(spell: int) -> int:
	var e := evo_entry(spell)
	var own := weapon_entry(spell)
	if e < 0:
		return -1
	for req: Array in CATALOG[e][C_REQUIRES]:
		if int(req[0]) != own:
			return int(req[0])
	return -1


## True if `spell` can still evolve for a wizard: not evolved yet, its evolution not banished, and its own row
## either maxed or not banished.
static func _can_evolve(levels: Dictionary, spell: int, banned: Dictionary) -> bool:
	if evolved(levels, spell) or banned.has(evo_entry(spell)):
		return false
	return weapon_level(levels, spell) >= max_level(weapon_entry(spell)) or not banned.has(weapon_entry(spell))


## True if taking `idx` (not owned yet) completes a pair: it is the partner of an owned spell that can still
## evolve, or it is a spell whose partner is owned (and whose evolution is not banished). Banishes in `banned`.
static func pairs_with(levels: Dictionary, idx: int, banned: Dictionary = {}) -> bool:
	if idx < 0 or idx >= CATALOG.size() or level_of(levels, idx) > 0:
		return false
	if kind(idx) == SPELL and level_of(levels, partner_row(spell_of(idx))) > 0 and _can_evolve(levels, spell_of(idx), banned):
		return true
	for sp: int in Spells.COUNT:
		if partner_row(sp) == idx and weapon_level(levels, sp) > 0 and _can_evolve(levels, sp, banned):
			return true
	return false


## True if some row of `of_kind` that the wizard does not own, has not banished and could take would complete a
## pair: then the last free slot of that kind is kept for one.
static func _pair_wanted(levels: Dictionary, of_kind: int, banned: Dictionary) -> bool:
	for i: int in range(CATALOG.size()):
		if kind(i) == of_kind and not banned.has(i) and _requirements_met(levels, i) and pairs_with(levels, i, banned):
			return true
	return false


static func _requirements_met(levels: Dictionary, idx: int) -> bool:
	for req: Array in CATALOG[idx][C_REQUIRES]:
		if level_of(levels, int(req[0])) < int(req[1]):
			return false
	return true


## True if `idx` can be offered: below its max level, every requirement holds, it is not banished, and a new
## SPELL or PASSIVE row still has a free slot under `cap` (spell slots, passive slots). The last free slot of a
## kind is kept for a row that completes a pair (pairs_with) while one is still to be had. Minor Arcana are never
## available: they only fill a short hand (minor_fill).
static func available(levels: Dictionary, idx: int, cap: Vector2i = UNCAPPED, banned: Dictionary = {}) -> bool:
	if idx < 0 or idx >= CATALOG.size() or kind(idx) == MINOR or level_of(levels, idx) >= max_level(idx):
		return false
	if not _requirements_met(levels, idx):
		return false
	if banned.has(idx):
		return false
	if level_of(levels, idx) == 0 and cap != UNCAPPED and (kind(idx) == SPELL or kind(idx) == PASSIVE):
		var used := slots_used(levels)
		var have := used.x if kind(idx) == SPELL else used.y
		var room := cap.x if kind(idx) == SPELL else cap.y
		if have >= room:
			return false
		if have == room - 1 and not pairs_with(levels, idx, banned) and _pair_wanted(levels, kind(idx), banned):
			return false
	return true


## How much a wizard who picks at once (a bot or an apprentice) wants `idx` next, higher first: an evolution,
## then a row that completes a pair, then a spell it already casts (the higher the sooner), then a new spell,
## then a passive, then an instant, then a Minor Arcana card; ties go by the row's weight.
static func pick_score(levels: Dictionary, idx: int) -> float:
	var w := float(CATALOG[idx][C_WEIGHT])
	match kind(idx):
		EVOLUTION:
			return 500.0 + w
		SPELL:
			if pairs_with(levels, idx):
				return 400.0 + w
			if level_of(levels, idx) > 0:
				return 300.0 + level_of(levels, idx) * 10.0 + w
			return 200.0 + w
		PASSIVE:
			if pairs_with(levels, idx):
				return 400.0 + w
			return (150.0 if level_of(levels, idx) > 0 else 100.0) + w
		MINOR:
			return w
	return 10.0 + w


## The card of `choices` that pick_score likes best (an index into `choices`), or -1 for an empty hand.
static func best_pick(levels: Dictionary, choices: Array[int]) -> int:
	var best := -1
	var bs := -INF
	for c: int in range(choices.size()):
		var sc := pick_score(levels, choices[c])
		if sc > bs:
			bs = sc
			best = c
	return best


## The weight `idx` has in a roll for a wizard with `levels` and banishes `banned`: its row's weight,
## PARTNER_WEIGHT times when it completes a pair.
static func roll_weight(levels: Dictionary, idx: int, banned: Dictionary = {}) -> float:
	var w := float(CATALOG[idx][C_WEIGHT])
	return w * PARTNER_WEIGHT if pairs_with(levels, idx, banned) else w


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


## STRENGTH's multiplier, times 1 + WANDS' bonus for each WANDS taken.
static func damage_mul(levels: Dictionary) -> float:
	return value(levels, POWER, 1.0) * (1.0 + level_of(levels, M_WANDS) * float(CATALOG[M_WANDS][C_VALUES][0]))


## Seconds per regenerated heart, or 0 for no regeneration.
static func regen_interval(levels: Dictionary) -> float:
	return value(levels, REGEN, 0.0)


static func magnet_mul(levels: Dictionary) -> float:
	return value(levels, MAGNET, 1.0)


static func xp_mul(levels: Dictionary) -> float:
	return value(levels, WISDOM, 1.0)


## JUSTICE: the chance a foe this wizard slays bursts, 0 without it.
static func justice_chance(levels: Dictionary) -> float:
	return value(levels, JUSTICE, 0.0)


## THE LOVERS: the cast speed added near an ally (`together`) or alone, 0 without it.
static func lovers_bonus(levels: Dictionary, together: bool) -> float:
	return value(levels, LOVERS, 0.0) * (1.0 if together else LOVERS_ALONE)


## Up to `n` different upgrades the player can still take (available under `cap` and `banned`), drawn by
## roll_weight without replacement from `rng`. Empty when everything is maxed.
static func roll(rng: RandomNumberGenerator, levels: Dictionary, n: int, cap: Vector2i = UNCAPPED,
		banned: Dictionary = {}) -> Array[int]:
	var pool: Array[int] = []
	var weights: Array[float] = []
	for i: int in range(CATALOG.size()):
		if available(levels, i, cap, banned):
			pool.append(i)
			weights.append(roll_weight(levels, i, banned))
	var out: Array[int] = []
	while out.size() < n and not pool.is_empty():
		var total: float = 0.0
		for wt: float in weights:
			total += wt
		var r: float = rng.randf() * total
		var at: int = pool.size() - 1
		for k: int in range(pool.size()):
			r -= weights[k]
			if r < 0.0:
				at = k
				break
		out.append(pool[at])
		pool.remove_at(at)
		weights.remove_at(at)
	return out


## Fills `hand` up to `n` cards with different Minor Arcana drawn from `rng` (a hand short of cards to learn).
static func minor_fill(rng: RandomNumberGenerator, hand: Array[int], n: int) -> void:
	var left: Array[int] = MINORS.duplicate()
	while hand.size() < n and not left.is_empty():
		hand.append(left.pop_at(rng.randi() % left.size()))


## Raises `idx` by one level in `levels`. Returns false if it is unknown or already maxed. A Minor Arcana card is
## counted each time it is taken.
static func take(levels: Dictionary, idx: int) -> bool:
	if idx >= 0 and idx < CATALOG.size() and kind(idx) == MINOR:
		levels[idx] = level_of(levels, idx) + 1
		return true
	if not available(levels, idx):
		return false
	levels[idx] = level_of(levels, idx) + 1
	return true
