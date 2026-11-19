class_name Gamble
extends RefCounted
## Gamble shrines: what a shrine costs and what it can pay out. Pure data plus a seeded roll; World places
## shrines, takes the gold and applies the outcome after the reel. Shrines take run gold only (earned in play,
## gone when the run ends), never anything bought.

const SOLO := 0
const TEAM := 1

## Solo shrine outcomes: [key, name, weight, good]. Indices are sent in events, so append new ones at the end.
const SO_JACKPOT := 0 # a lucky chest
const SO_CHEST := 1 # a plain chest
const SO_DOUBLE := 2 # the stake back twice
const SO_NOTHING := 3
const SO_CURSE := 4 # lose a heart (never the last one)
const SOLO_OUTCOMES: Array = [
	["jackpot", "JACKPOT!", 12.0, true],
	["chest", "TREASURE", 30.0, true],
	["double", "DOUBLE GOLD", 18.0, true],
	["nothing", "NOTHING...", 22.0, false],
	["curse", "CURSED!", 18.0, false],
]

## Team shrine outcomes: one wizard bets for the whole party.
const TO_BLESSING := 0 # every wizard gains levels
const TO_CURSE := 1 # every wizard loses a heart and an elite comes for each of them
const TEAM_OUTCOMES: Array = [
	["blessing", "PARTY BLESSED!", 50.0, true],
	["curse", "PARTY CURSED!", 50.0, false],
]

## Levels each wizard gains from a team blessing.
const BLESSING_LEVELS := 2


static func outcomes(kind: int) -> Array:
	return TEAM_OUTCOMES if kind == TEAM else SOLO_OUTCOMES


static func outcome_name(kind: int, idx: int) -> String:
	return outcomes(kind)[idx][1]


static func is_good(kind: int, idx: int) -> bool:
	return bool(outcomes(kind)[idx][3])


static func roll(rng: RandomNumberGenerator, kind: int) -> int:
	var table: Array = outcomes(kind)
	var total: float = 0.0
	for row: Array in table:
		total += float(row[2])
	var r: float = rng.randf() * total
	for i: int in range(table.size()):
		r -= float(table[i][2])
		if r < 0.0:
			return i
	return table.size() - 1


## Gold a shrine of `kind` costs at `minute` of the run (from 1), given the tuning's base and growth.
static func cost(kind: int, minute: int, base: float, per_min: float, team_mul: float) -> int:
	var c: float = base + per_min * maxi(0, minute - 1)
	if kind == TEAM:
		c *= team_mul
	return int(round(c))
