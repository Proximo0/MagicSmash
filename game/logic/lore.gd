class_name Lore
extends RefCounted
## The story of a run, as data: the prologue pages, the three acts the tower's climb is split into, a line for
## every minute, the bosses' names and the endings. Text only (upper case, the pixel font's characters); the
## title draws the prologue and the arena draws the act cards and banners.

const PROLOGUE: Array = [
	["THE BLACK COMET", "WHEN THE BLACK COMET SPLIT THE SKY ABOVE ALDERMOOR, THE DEAD STOPPED SLEEPING."],
	["MORVANE", "MORVANE THE SCHOLAR READ THE NINTH PAGE OF THE ASHEN GRIMOIRE AND LEARNED THE NAME THAT DEATH ANSWERS TO."],
	["THE TOWER", "NOW HIS HORDE CLIMBS THE WIZARDS' TOWER, STAIR BY STAIR, FOR THE BOOK THAT WILL MAKE HIM A GOD."],
	["THE LAST COVEN", "FOUR WIZARDS REMAIN. THE CARDS ARE DRAWN. HOLD THE TOWER UNTIL THE COMET FALLS."],
]

## [first minute, roman numeral, name, subtitle] for each act.
const ACTS: Array = [
	[0, "I", "THE OSSUARY", "WHERE THE TOWER KEEPS ITS DEAD"],
	[5, "II", "THE BURNING LIBRARY", "EVERY BOOK A SPELL, EVERY SPELL ON FIRE"],
	[10, "III", "THE STARLESS SANCTUM", "UNDER THE COMET, MORVANE ASCENDS"],
]

## A line for each minute's banner (index = minute). Minutes with a boss use the boss banner instead.
const MINUTES: Array = [
	"THE BONES STIR",
	"THE CANDLES GUTTER",
	"SOMETHING SCRATCHES IN THE WALLS",
	"THE CRYPT DOORS GIVE WAY",
	"A COLD WIND FROM BELOW",
	"",
	"THE SHELVES ARE BURNING",
	"INK RUNS LIKE BLOOD",
	"THE PAGES WHISPER YOUR NAMES",
	"THE STAIR GROANS",
	"",
	"THE STARS GO OUT ONE BY ONE",
	"THE COMET FILLS THE SKY",
	"THE TOWER TREMBLES",
	"HE IS COMING",
]

## [name, subtitle] of each omen, the set-piece horde in the middle of an act (World.OMENS, same order).
const OMENS: Array = [
	["THE DEAD ENCIRCLE", "BACK TO BACK, WIZARDS"],
	["THE LIBRARY TAKES FLIGHT", "EVERY DOOR, EVERY BOOK"],
	["THE PROCESSION OF WRAITHS", "THEY WALK THROUGH WALLS"],
]

const LICH_NAME := "MORVANE, LICH LORD"
const ARCHLICH_NAME := "MORVANE ASCENDANT"
const ARCHLICH_TITLE := "THE ARCHLICH"

## Epithets an elite is announced with, so each tough one reads as someone from the tale.
const ELITE_EPITHETS: Array = [
	"THE UNBURIED", "COMET-BORN", "OF THE NINTH PAGE", "THE HOLLOW KING", "MORVANE'S HOUND", "THE ASHEN",
	"WARDEN OF BONES", "THE BLOODLESS", "THE STARLESS", "KEEPER OF THE CRYPT", "THE TWICE-DEAD", "GRAVE-SWORN",
]

const VICTORY_LINES: Array = [
	"THE COMET FALLS INTO THE SEA. THE DEAD SLEEP AGAIN.",
	"THE ASHEN GRIMOIRE IS SEALED. THE TOWER STANDS.",
]
const DEFEAT_LINES: Array = [
	"THE TOWER FALLS SILENT. THE COMET BURNS ON.",
	"MORVANE TURNS ANOTHER PAGE.",
]


## The act a run minute belongs to (0, 1 or 2).
static func act_of(minute: int) -> int:
	var act := 0
	for i in ACTS.size():
		if minute >= int(ACTS[i][0]):
			act = i
	return act


## Whether `minute` opens a new act (the first minute of Act II or III).
static func opens_act(minute: int) -> bool:
	for i in range(1, ACTS.size()):
		if minute == int(ACTS[i][0]):
			return true
	return false


static func act_heading(act: int) -> String:
	var a: Array = ACTS[clampi(act, 0, ACTS.size() - 1)]
	return "ACT %s" % a[1]


static func act_name(act: int) -> String:
	return ACTS[clampi(act, 0, ACTS.size() - 1)][2]


static func act_subtitle(act: int) -> String:
	return ACTS[clampi(act, 0, ACTS.size() - 1)][3]


## The banner line for a minute; past the last listed minute the final line repeats.
static func minute_line(minute: int) -> String:
	var line: String = MINUTES[clampi(minute, 0, MINUTES.size() - 1)]
	return line if not line.is_empty() else "HOLD THE TOWER"


## An ending line, picked by the run's seed so every player sees the same one.
static func ending(won: bool, seed_value: int) -> String:
	var lines: Array = VICTORY_LINES if won else DEFEAT_LINES
	return lines[absi(seed_value) % lines.size()]


## An elite's epithet, picked from a number every screen agrees on (such as where it appeared).
static func elite_epithet(n: int) -> String:
	return ELITE_EPITHETS[absi(n) % ELITE_EPITHETS.size()]


static func omen_name(i: int) -> String:
	return OMENS[clampi(i, 0, OMENS.size() - 1)][0]


static func omen_subtitle(i: int) -> String:
	return OMENS[clampi(i, 0, OMENS.size() - 1)][1]
