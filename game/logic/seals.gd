class_name Seals
extends RefCounted
## The difficulty ladder: APPRENTICE (-1), WIZARD (0, the game as tuned), ARCHMAGE (1), then the Seals I to VIII
## (2 to 9), each one harder than the last, with one new rule and better rewards. Pure data plus lookups: World
## copies `values(level)` into its fields in apply_seal (never into Tuning), Profile pays the rewards, the lobby,
## the HUD and the results screen show the names. This file is the data file for the ladder's numbers.

const MIN := -1
const MAX := 9
## Steps open on a new profile: APPRENTICE, WIZARD and ARCHMAGE. A win at a step opens the next.
const START_UNLOCKED := 1

const NAMES := ["APPRENTICE", "WIZARD", "ARCHMAGE"]
const NUMERALS := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"]

## What WIZARD plays like: every value neutral. A step's values start from these.
## hp, horde, boss, speed, potions: enemy health, horde budget rate, Lich and Archlich health, enemy speed and the
## chance a plain kill drops a potion, as multipliers. hearts: hearts every wizard starts with, added.
## crystals: multiplier on the boss and win bounties. luck: added to chest luck; card odds +card_per_luck each.
## ultra: ultra-rare chests and ULTRA RARE loot can drop. The rest are the Seals' rules (RULES).
const BASE := {
	"hp": 1.0, "horde": 1.0, "boss": 1.0, "speed": 1.0, "potions": 1.0, "hearts": 0,
	"crystals": 1.0, "luck": 0, "ultra": true,
	"rift": 1.0, "potion_heal": 2, "group": 1.0, "cap": 0, "elite_hp": 1.0, "escort": 0,
	"cruel": 0.0, "hand": 0, "lives": 0, "solo_lives": 0, "judgement": true, "ritual": 1.0,
}

## APPRENTICE and ARCHMAGE: their own scalars (part 3b of docs/wave2_brief.md; the balance job tunes them).
const APPRENTICE := {"hp": 0.75, "boss": 0.7, "hearts": 2, "potions": 2.0, "ultra": false}
const ARCHMAGE := {"hp": 1.08, "boss": 1.15}
## What each Seal adds on top of the step below it.
const PER_SEAL := {"hp": 0.03, "horde": 0.03, "boss": 0.06}

## Crystal multiplier and luck per step, MIN to MAX.
const CRYSTALS := [0.5, 1.0, 1.5, 2.0, 2.5, 3.25, 4.0, 5.0, 6.5, 8.0, 10.0]
const LUCK := [0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 10]
## Card drop odds added per point of luck.
const CARD_PER_LUCK := 0.1
## A first win's crystal prize: PRIZE_BASE x step squared, from ARCHMAGE (1) up.
const PRIZE_BASE := 50

## The Seals' rules, I to VIII: [name, what the lobby says, the values it sets]. Rules are cumulative.
## HUNGER: plain kills drop potions 0.6 times as often (no potions at all was a wall: solo bots fell from 3 wins
## in 6 to none). Elites and bosses drop as before. AMBUSH: rift warning x0.5. FAMINE: a
## potion heals one heart, not two. LEGION: groups x1.25, enemy cap 325. CHAMPIONS: elites x1.5 health, each
## with an escort of plain enemies of its kind. MISFORTUNE: fate_cruel 0.6. SILENCE: level-ups deal 2 cards.
## DARKNESS: one life (two for a wizard with no ally), no JUDGEMENT card, rituals take twice as long.
const RULES: Array = [
	["HUNGER", "FEWER POTIONS FROM KILLS", {"potions": 0.6}],
	["AMBUSH", "RIFTS WARN HALF AS LONG", {"rift": 0.5}],
	["FAMINE", "POTIONS HEAL 1 HEART", {"potion_heal": 1}],
	["LEGION", "GROUPS 25% BIGGER", {"group": 1.25, "cap": 325}],
	["CHAMPIONS", "ESCORTED ELITES", {"elite_hp": 1.5, "escort": 4}],
	["MISFORTUNE", "CRUEL FATES", {"cruel": 0.6}],
	["SILENCE", "2-CARD LEVEL-UPS", {"hand": 2}],
	["DARKNESS", "1 LIFE, NO JUDGEMENT", {"lives": 1, "solo_lives": 2, "judgement": false, "ritual": 2.0}],
]
const DESCRIBE_LOW := ["GENTLER FOES, MORE POTIONS", "THE TOWER AS IT STANDS", "TOUGHER FOES AND BOSSES"]


## The step's values: BASE with the step's scalars and every rule up to it.
static func values(level: int) -> Dictionary:
	level = clampi(level, MIN, MAX)
	var v: Dictionary = BASE.duplicate()
	v.crystals = float(CRYSTALS[level - MIN])
	v.luck = int(LUCK[level - MIN])
	if level < 0:
		v.merge(APPRENTICE, true)
		return v
	if level == 0:
		return v
	v.merge(ARCHMAGE, true)
	for k: String in PER_SEAL:
		v[k] = float(v[k]) + float(PER_SEAL[k]) * (level - 1)
	for i: int in range(level - 1):
		v.merge(RULES[i][2], true)
	return v


## "APPRENTICE", "WIZARD", "ARCHMAGE", "SEAL I" ... "SEAL VIII".
static func title(level: int) -> String:
	level = clampi(level, MIN, MAX)
	return NAMES[level - MIN] if level <= 1 else "SEAL " + NUMERALS[level - 2]


## The Seal's Roman numeral ("I" for SEAL I), or "" below the Seals.
static func numeral(level: int) -> String:
	return NUMERALS[level - 2] if level >= 2 and level <= MAX else ""


## One line: what the step changes (a Seal's own new rule, the rules below it still hold).
static func describe(level: int) -> String:
	level = clampi(level, MIN, MAX)
	if level <= 1:
		return DESCRIBE_LOW[level - MIN]
	return "%s: %s" % [RULES[level - 2][0], RULES[level - 2][1]]


static func crystal_mul(level: int) -> float:
	return float(CRYSTALS[clampi(level, MIN, MAX) - MIN])


static func luck(level: int) -> int:
	return int(LUCK[clampi(level, MIN, MAX) - MIN])


## The crystals a first win at the step pays (none below ARCHMAGE).
static func prize(level: int) -> int:
	return PRIZE_BASE * level * level if level >= 1 and level <= MAX else 0


## The Cards index of the Seal's own card (dropped only by its Archlich, paid on its first win), or -1.
static func card(level: int) -> int:
	return Cards.index_of("seal_%d" % (level - 1)) if level >= 2 and level <= MAX else -1


## The step a Seal card belongs to, or MIN - 1 for any other card.
static func of_card(idx: int) -> int:
	for level: int in range(2, MAX + 1):
		if card(level) == idx:
			return level
	return MIN - 1


## The results screen's line for what a finished run's step paid (Profile.last_pay): the step, the bounty
## multiplier and what it added, and a first win's prize and Seal card.
static func pay_line(pay: Dictionary) -> String:
	var level := int(pay.get("seal", 0))
	var mul := float(pay.get("mul", crystal_mul(level)))
	var line := "%s  BOUNTIES X%s" % [title(level), mul_text(mul)]
	var extra := int(pay.get("bounty", 0))
	if extra != 0:
		line += " %+d" % extra
	if int(pay.get("prize", 0)) > 0:
		line += "  FIRST WIN +%d" % int(pay.prize)
	if int(pay.get("card", -1)) >= 0:
		line += "  " + Cards.card_name(int(pay.card)) + " CARD"
	return line


## The lobby row's three texts for a step: its name, its rule (describe) and, at the right, the crystal
## multiplier and the unclaimed first-win prize (`prize_left`, 0 for none), or LOCKED when it is not open.
static func row(level: int, open: bool, prize_left: int) -> PackedStringArray:
	var right := "LOCKED"
	if open:
		right = "CRYSTALS X" + mul_text(crystal_mul(level))
		if prize_left > 0:
			right += "  PRIZE %d" % prize_left
	return PackedStringArray([title(level), describe(level), right])


## A multiplier as the screens print it: 1, 1.5, 3.25.
static func mul_text(mul: float) -> String:
	return ("%.2f" % mul).rstrip("0").rstrip(".")
