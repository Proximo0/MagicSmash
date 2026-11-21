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

## Team shrine outcomes, the fate deck: one wizard bets for the whole party and a tarot card is turned.
## [key, name, weight, good, tarot key (TarotArt.ARCANA), what it does (the reel's line; %d is its number)]. Ids travel in events
## and Results.fates, so append new fates at the end. The weight is the old coin flip a solo run still makes
## (roll()); a party draws from the deck instead (draw_fate()): a side, then a fate of that side.
const TO_BLESSING := 0 # THE SUN: every wizard gains levels
const TO_CURSE := 1 # DEATH: every wizard loses a heart and an elite comes for each of them
const TO_WORLD := 2 # THE WORLD: every XP gem flies to the party, everyone heals
const TO_EMPEROR := 3 # THE EMPEROR: a chest for each human wizard
const TO_FOOL := 4 # THE FOOL: the next fate drawn counts twice
const TO_HANGED := 5 # THE HANGED MAN: novas sealed for a while
const TO_HIEROPHANT := 6 # THE HIEROPHANT: no potions drop for a while
const TO_WHEEL := 7 # WHEEL OF FORTUNE: more fates are drawn at once (never the Wheel again in that chain)
const TEAM_OUTCOMES: Array = [
	["blessing", "PARTY BLESSED!", 50.0, true, "sun", "EVERY WIZARD GAINS %d LEVELS"],
	["curse", "PARTY CURSED!", 50.0, false, "death", "A HEART LOST AND AN ELITE FOR EACH WIZARD"],
	["world", "THE WORLD!", 0.0, true, "world", "EVERY GEM FLIES IN, ALL HEAL %d HEARTS"],
	["emperor", "THE EMPEROR!", 0.0, true, "emperor", "A CHEST FOR EACH WIZARD"],
	["fool", "THE FOOL!", 0.0, true, "fool", "THE NEXT FATE COUNTS TWICE"],
	["hanged", "HANGED MAN!", 0.0, false, "hanged", "NOVAS SEALED FOR %d SECONDS"],
	["hierophant", "HIEROPHANT!", 0.0, false, "hierophant", "NO POTIONS DROP FOR %d SECONDS"],
	["wheel", "WHEEL TURNS!", 0.0, false, "wheel", "%d MORE FATES ARE DRAWN AT ONCE"],
]

## Levels each wizard gains from a team blessing.
const BLESSING_LEVELS := 2


static func outcomes(kind: int) -> Array:
	return TEAM_OUTCOMES if kind == TEAM else SOLO_OUTCOMES


static func outcome_name(kind: int, idx: int) -> String:
	return outcomes(kind)[idx][1]


static func is_good(kind: int, idx: int) -> bool:
	return bool(outcomes(kind)[idx][3])


## The tarot card a fate shows (a TarotArt.ARCANA key) and its line saying what it does.
static func fate_card(idx: int) -> String:
	return TEAM_OUTCOMES[idx][4]


static func fate_text(idx: int, tune: Tuning) -> String:
	var text: String = TEAM_OUTCOMES[idx][5]
	if not text.contains("%d"):
		return text
	var n: float = BLESSING_LEVELS
	match idx:
		TO_WORLD:
			n = tune.fate_world_hearts
		TO_HANGED:
			n = tune.fate_hanged_secs
		TO_HIEROPHANT:
			n = tune.fate_hierophant_secs
		TO_WHEEL:
			n = tune.fate_wheel_draws
	return text % int(n)


## One card from the fate deck: the cruel side with chance `cruel`, then each fate of that side alike.
## `wheel` false leaves WHEEL OF FORTUNE out (a chain it started never draws it again).
static func draw_fate(rng: RandomNumberGenerator, cruel: float, wheel: bool = true) -> int:
	var cruel_side := rng.randf() < cruel
	var pool: Array[int] = []
	for i: int in range(TEAM_OUTCOMES.size()):
		if bool(TEAM_OUTCOMES[i][3]) != cruel_side and (wheel or i != TO_WHEEL):
			pool.append(i)
	return pool[rng.randi() % pool.size()]


## A weighted roll over the table (a solo shrine; a team shrine in a solo run: the old Sun-or-Death flip).
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
