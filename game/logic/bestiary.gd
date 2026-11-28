class_name Bestiary
extends RefCounted
## Every kind of enemy as data: the type ids, their stats and flags (KINDS), the horde director's table (HORDE),
## set-piece formations (FORMATIONS) and the seeded roll of the next group. A leaf: it knows nothing of World.
## Ids are snapshot ids: append, never reorder. Kinds past PRIEST are reserved for the bestiary jobs
## (docs/bestiary_design.md). Job K's eight kinds (BLOAT..SWORDS) think in kinds_crypt.gd, kinds_library.gd and
## kinds_sanctum.gd (BRAINS); Tuning.new_kinds scales their act weights (0: the horde rolls exactly as before them).

const GOBLIN := 0
const SKELETON := 1
const SLIME := 2
const MSLIME := 3
const BAT := 4
const ORC := 5
const MAGE := 6
const LICH := 7
const WRAITH := 8
const TOME := 9
const GARGOYLE := 10
const PRIEST := 11
## Reserved for job K (enemies) and job L (act bosses).
const BLOAT := 12
const COFFIN := 13
const GUARD := 14
const CINDERLING := 15
const CENSOR := 16
const HOUND := 17
const SHARD := 18
const SWORDS := 19
const CHANDELIER := 20
const GHOSTWRITER := 21

## Flags (KINDS column K_FLAGS).
const F_NO_SEP := 1 # never pushed out of the crowd (bats, wraiths)
const F_ANCHORED := 2 # stands where it rose: no walking, no knockback
const F_BOSS := 4 # can be World.boss (Bosses)
const F_HAZARD := 8 # makes hazard rows: never rolled while a boss is up
const F_FIXED_SPEED := 16 # its speed does not grow with the minute
const F_ARROW := 32 # the HUD points at it when it is off screen
const F_NO_BLOCK := 64 # the crowd does not push off it (bats)
const F_BLINK := 128 # can teleport, so its contact test always runs

## The most knockback an enemy can carry, px/s, before its heft: shoves add up to this and no further, so one nova
## (260) still pushes in full but a crowd of hits cannot throw an elite to the wall.
const KNOCK_MAX := 280.0

## [key, hp, spd, r, score, contact, xp, heft, flags]. hp and spd before the minute's scaling; heft scales knockback.
const K_KEY := 0
const K_HP := 1
const K_SPD := 2
const K_R := 3
const K_SCORE := 4
const K_CONTACT := 5
const K_XP := 6
const K_HEFT := 7
const K_FLAGS := 8
const KINDS: Array = [
	["goblin",      2.0,   58.0, 5.0,  50,   1, 1,  1.0,  0],
	["skeleton",    3.0,   40.0, 5.0,  100,  1, 2,  1.0,  0],
	["slime",       5.0,   34.0, 6.0,  80,   1, 2,  1.0,  0],
	["mslime",      1.5,   52.0, 4.0,  20,   1, 1,  1.0,  0],
	["bat",         1.0,   88.0, 5.0,  60,   1, 1,  1.0,  F_NO_SEP | F_NO_BLOCK],
	["orc",         18.0,  30.0, 8.0,  300,  2, 5,  0.4,  0],
	["mage",        6.0,   22.0, 5.0,  250,  1, 4,  1.0,  F_BLINK],
	["lich",        380.0, 26.0, 14.0, 5000, 2, 25, 0.15, F_BOSS | F_BLINK | F_ARROW],
	["wraith",      4.0,   44.0, 5.0,  120,  1, 2,  1.0,  F_NO_SEP],
	["tome",        3.0,   64.0, 5.0,  90,   1, 2,  1.0,  0],
	["gargoyle",    12.0,  30.0, 7.0,  260,  1, 4,  0.4,  0],
	["priest",      9.0,   24.0, 5.0,  300,  1, 5,  1.0,  0],
	# Reserved: the doc's starting values; score and heft are first guesses for job K / job L to tune.
	["bloat",       6.0,   30.0, 7.0,  100,  0, 2,  1.0,  F_HAZARD],
	["coffin",      10.0,  0.0,  8.0,  200,  0, 4,  0.0,  F_ANCHORED | F_ARROW | F_FIXED_SPEED],
	["guard",       10.0,  26.0, 7.0,  150,  1, 3,  0.6,  0],
	["cinderling",  4.0,   70.0, 5.0,  100,  1, 2,  1.0,  F_HAZARD],
	["censor",      9.0,   24.0, 6.0,  200,  1, 4,  1.0,  F_HAZARD],
	["hound",       4.0,   70.0, 5.0,  100,  1, 2,  1.0,  F_ARROW], # its ring (KindsLibrary.HOUND_RING) passes beyond half a screen; the arrow shows only while it hunts
	["shard",       22.0,  0.0,  8.0,  300,  1, 6,  0.0,  F_ANCHORED | F_HAZARD | F_FIXED_SPEED],
	["swords",      16.0,  36.0, 6.0,  300,  1, 6,  1.0,  F_HAZARD],
	# The act bosses come once each: hp is their health at their minute (5:00, 10:00) before boss_hp_mul and the
	# party row, set for fights of 50-70 s and 70-90 s casual solo (job L, on balance pass 2).
	["chandelier",  900.0, 34.0, 16.0, 5000, 0, 25, 0.15, F_BOSS | F_ARROW | F_FIXED_SPEED],
	["ghostwriter", 3800.0, 150.0, 14.0, 5000, 0, 25, 0.15, F_BOSS | F_BLINK | F_ARROW | F_FIXED_SPEED],
]

## How a group comes in: through a door (or a rift), rising from the floor near the party, or abreast at a door.
const GROUP := 0
const RISE := 1
const WALL := 2
## The horde director's table: [type, budget cost, unlocks after this many seconds of fighting, weight in act I,
## act II, act III, group min, group max, extra group max per minute, cap alive (0: none; +1 with 3 or 4 wizards),
## form]. Today's kinds weigh the same in every act; job K's kinds weigh by act (Tuning.new_kinds scales them).
const H_TYPE := 0
const H_COST := 1
const H_UNLOCK := 2
const H_W1 := 3
const H_GMIN := 6
const H_GMAX := 7
const H_EXTRA := 8
const H_CAP := 9
const H_FORM := 10
const HORDE: Array = [
	[GOBLIN,     1.0, 0.0,   2, 2, 2, 6, 10, 1, 0, GROUP],
	[BAT,        1.0, 0.0,   1, 1, 1, 4, 8,  0, 0, GROUP],
	[SLIME,      3.0, 30.0,  1, 1, 1, 2, 4,  0, 0, GROUP],
	[SKELETON,   3.0, 60.0,  1, 1, 1, 2, 5,  0, 0, GROUP],
	[ORC,        9.0, 150.0, 1, 1, 1, 1, 1,  0, 0, GROUP],
	[MAGE,       6.0, 210.0, 1, 1, 1, 1, 2,  0, 0, GROUP],
	[WRAITH,     2.0, 240.0, 1, 1, 1, 2, 4,  0, 0, GROUP],
	[TOME,       2.0, 300.0, 2, 2, 2, 3, 6,  0, 0, GROUP],
	[PRIEST,     8.0, 420.0, 1, 1, 1, 1, 1,  0, 0, GROUP],
	[GARGOYLE,   7.0, 600.0, 1, 1, 1, 1, 2,  0, 0, GROUP],
	[BLOAT,      2.0, 90.0,  1, 1, 1, 1, 2,  0, 4, GROUP],
	[COFFIN,     5.0, 120.0, 1, 1, 0, 1, 1,  0, 2, RISE],
	[GUARD,      3.0, 210.0, 1, 1, 0, 2, 3,  0, 4, WALL],
	[CINDERLING, 5.0, 330.0, 0, 1, 1, 1, 2,  0, 2, GROUP],
	[CENSOR,     6.0, 360.0, 0, 1, 0, 1, 2,  0, 2, GROUP],
	[HOUND,      2.0, 450.0, 0, 1, 1, 3, 3,  0, 6, GROUP],
	[SHARD,      8.0, 660.0, 0, 0, 1, 1, 1,  0, 1, RISE],
	[SWORDS,     7.0, 750.0, 0, 0, 1, 1, 3,  0, 3, GROUP],
]

## Where a formation comes in: one rift near the party, one door, or two opposite doors.
const AT_RIFT := 0
const AT_DOOR := 1
const AT_OPPOSITE := 2
## Set pieces: [name, unlocks after s, weight, [[type, n], ...], layout]. When any is unlocked, one roll in
## FORMATION_ROLL / Tuning.new_kinds is a formation. A part of more than one shrinks with the party (FORM_PARTY).
const FORMATIONS: Array = [
	["POWDER TRAIN", 150.0, 1, [[GOBLIN, 8], [BLOAT, 1]], AT_RIFT],
	["SHIELD WALL", 210.0, 1, [[GUARD, 3], [SKELETON, 3]], AT_DOOR],
	["FIRE DRILL", 390.0, 1, [[CINDERLING, 1], [CINDERLING, 1], [CENSOR, 1]], AT_OPPOSITE],
]
const FORMATION_ROLL := 5
## A formation part's size x this, by wizards 1..4 (rounded, at least 1), so a solo wizard meets half a POWDER TRAIN.
const FORM_PARTY: Array[float] = [0.5, 0.67, 0.83, 1.0]
## Weight steps when Tuning.new_kinds is not a whole number (see _row_weight).
const WEIGHT_STEPS := 10
## RISE: how far from the party's centre (and at least RISE_MIN from every wizard) a riser comes up, the arena
## inset it keeps, and the rift mark's size.
const RISE_MIN := 70.0
const RISE_MAX := 130.0
const RISE_MARGIN := 22.0
const RISE_SPREAD := 8.0
## Brains for the reserved kinds: type -> script path. The script has static think(w, e, dt, tgt, dirv, dist),
## on_death(w, e, slot) and filter_damage(w, e, dmg, knock, sure) (see Brains). A boss's think and death go through
## Bosses; only its filter_damage is read from here.
const BRAINS: Dictionary = {
	BLOAT: "res://game/logic/kinds_crypt.gd",
	COFFIN: "res://game/logic/kinds_crypt.gd",
	GUARD: "res://game/logic/kinds_crypt.gd",
	CINDERLING: "res://game/logic/kinds_library.gd",
	CENSOR: "res://game/logic/kinds_library.gd",
	HOUND: "res://game/logic/kinds_library.gd",
	SHARD: "res://game/logic/kinds_sanctum.gd",
	SWORDS: "res://game/logic/kinds_sanctum.gd",
	CHANDELIER: "res://game/logic/boss_chandelier.gd",
	GHOSTWRITER: "res://game/logic/boss_ghostwriter.gd",
}
## The TEN OF SWORDS' blades: an enemy shot kind after World.ES_SKULL (World.eshot takes any int).
const ES_SWORD := 3
## Most enemy shots alive at once (World.eshot drops a shot past it).
const ESHOT_CAP := 300


static func count() -> int:
	return KINDS.size()


static func flags(type: int) -> int:
	return int(KINDS[type][K_FLAGS])


static func has_flag(type: int, flag: int) -> bool:
	return int(KINDS[type][K_FLAGS]) & flag != 0


static func horde_row(type: int) -> Array:
	for row: Array in HORDE:
		if row[H_TYPE] == type:
			return row
	return HORDE[0]


## The cap on `type` alive for this many wizards (0: none).
static func cap_of(row: Array, wizards: int) -> int:
	var cap: int = row[H_CAP]
	return cap + (1 if wizards >= 3 else 0) if cap > 0 else 0


## The next thing the horde saves for: [layout, [[type, n], ...]]. A group's layout is its HORDE form (GROUP, RISE or
## WALL); a formation's is AT_RIFT, AT_DOOR or AT_OPPOSITE plus 8 (so the two never mix up). `t` is the run's
## seconds, `act` 0..2, `alive` the count per type on the floor or queued to come, `boss_alive` true while a boss
## is up or queued. Rows past their cap, and F_HAZARD kinds while a boss is up, are left out; so is a formation with
## such a part or parts that together would pass a cap. No formation unlocked: no extra roll, so the draw order is
## today's. `formations` defaults to FORMATIONS (tests pass their own). `new_kinds` (Tuning.new_kinds) scales the
## weights of job K's kinds and of the formations that hold one: at 0 they never roll and the draws are exactly
## those of the horde before them.
static func roll_group(rng: RandomNumberGenerator, t: float, act: int, alive: PackedInt32Array, wizards: int, boss_alive: bool,
		formations: Array = FORMATIONS, new_kinds: float = 1.0) -> Array:
	var steps := 1 if is_equal_approx(new_kinds, roundf(new_kinds)) else WEIGHT_STEPS
	var forms: Array = formations.filter(func(f: Array) -> bool:
		return t >= float(f[1]) and _form_weight(f, new_kinds, steps) > 0 \
				and fits(form_parts(f[3], wizards), alive, wizards, boss_alive))
	if not forms.is_empty() and rng.randi_range(1, roundi(FORMATION_ROLL / clampf(new_kinds, 0.1, 1.0))) == 1:
		var fsum := 0
		for f: Array in forms:
			fsum += _form_weight(f, new_kinds, steps)
		var fr := rng.randi_range(1, maxi(1, fsum))
		for f: Array in forms:
			fr -= _form_weight(f, new_kinds, steps)
			if fr <= 0:
				return [8 + int(f[4]), form_parts(f[3], wizards)]
	var col := H_W1 + clampi(act, 0, 2)
	var total := 0
	for row: Array in HORDE:
		if _rollable(row, t, col, alive, wizards, boss_alive):
			total += _row_weight(row, col, new_kinds, steps)
	if total <= 0:
		return [GROUP, [[GOBLIN, 1]]]
	var r := rng.randi_range(1, total)
	for row: Array in HORDE:
		var wt := _row_weight(row, col, new_kinds, steps)
		if wt <= 0 or not _rollable(row, t, col, alive, wizards, boss_alive):
			continue
		r -= wt
		if r <= 0:
			var n := rng.randi_range(row[H_GMIN], row[H_GMAX] + row[H_EXTRA] * int(t / 60.0))
			var cap := cap_of(row, wizards)
			if cap > 0:
				n = clampi(n, 1, maxi(1, cap - _alive_of(alive, row[H_TYPE])))
			return [int(row[H_FORM]), [[int(row[H_TYPE]), n]]]
	return [GROUP, [[GOBLIN, 1]]]


## A formation's parts sized for the party: a part of more than one x FORM_PARTY (a fresh copy).
static func form_parts(parts: Array, wizards: int) -> Array:
	var k: float = FORM_PARTY[clampi(wizards, 1, FORM_PARTY.size()) - 1]
	var out: Array = []
	for part: Array in parts:
		var n: int = part[1]
		out.append([int(part[0]), maxi(1, roundi(n * k)) if n > 1 else n])
	return out


## Job K's kinds (BLOAT..SWORDS): the ones Tuning.new_kinds scales.
static func is_new_kind(type: int) -> bool:
	return type >= BLOAT and type <= SWORDS


## A HORDE row's weight in column `col`, x `steps` (WEIGHT_STEPS when new_kinds is fractional, so 0.5 can halve a
## weight of 1), a new kind's scaled by new_kinds.
static func _row_weight(row: Array, col: int, new_kinds: float, steps: int) -> int:
	var wt := int(row[col]) * steps
	return roundi(wt * maxf(new_kinds, 0.0)) if is_new_kind(row[H_TYPE]) else wt


static func _form_weight(f: Array, new_kinds: float, steps: int) -> int:
	var wt := int(f[2]) * steps
	for part: Array in f[3]:
		if is_new_kind(part[0]):
			return roundi(wt * maxf(new_kinds, 0.0))
	return wt


## Whether every [type, n] part may come now: no F_HAZARD kind while a boss is up, and no capped kind past its cap
## (counting `alive`, the floor plus the queue, and the other parts of the same type).
static func fits(parts: Array, alive: PackedInt32Array, wizards: int, boss_alive: bool) -> bool:
	var want := {}
	for part: Array in parts:
		var type: int = part[0]
		if boss_alive and has_flag(type, F_HAZARD):
			return false
		want[type] = int(want.get(type, 0)) + int(part[1])
	for type: int in want:
		var cap := cap_of(horde_row(type), wizards) if _has_row(type) else 0
		if cap > 0 and _alive_of(alive, type) + int(want[type]) > cap:
			return false
	return true


## Whether a rolled group could have outgrown its caps or the boss rule since it was rolled (a capped or F_HAZARD
## part): only then is it checked again before it is spent. Never true for today's kinds.
static func needs_check(parts: Array) -> bool:
	for part: Array in parts:
		var type: int = part[0]
		if has_flag(type, F_HAZARD) or (_has_row(type) and int(horde_row(type)[H_CAP]) > 0):
			return true
	return false


## Trims a group's parts to the room left under their caps (parts of one type share it). False when a part has no
## room (or is an F_HAZARD kind while a boss is up): roll again.
static func trim(parts: Array, alive: PackedInt32Array, wizards: int, boss_alive: bool) -> bool:
	var used := {}
	for part: Array in parts:
		var type: int = part[0]
		if boss_alive and has_flag(type, F_HAZARD):
			return false
		var cap := cap_of(horde_row(type), wizards) if _has_row(type) else 0
		if cap > 0:
			var room := cap - _alive_of(alive, type) - int(used.get(type, 0))
			if room < 1:
				return false
			part[1] = mini(int(part[1]), room)
			used[type] = int(used.get(type, 0)) + int(part[1])
	return true


static func _has_row(type: int) -> bool:
	for row: Array in HORDE:
		if row[H_TYPE] == type:
			return true
	return false


static func _rollable(row: Array, t: float, col: int, alive: PackedInt32Array, wizards: int, boss_alive: bool) -> bool:
	if t < float(row[H_UNLOCK]) or int(row[col]) <= 0:
		return false
	var type: int = row[H_TYPE]
	if boss_alive and has_flag(type, F_HAZARD):
		return false
	var cap := cap_of(row, wizards)
	return cap <= 0 or _alive_of(alive, type) < cap


static func _alive_of(alive: PackedInt32Array, type: int) -> int:
	return alive[type] if type < alive.size() else 0
