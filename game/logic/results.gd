class_name Results
extends RefCounted
## The record of one run for the results screen: per-wizard stats, the team's best moments and the awards.
## World notes things as they happen; `to_dict()` travels to clients with the game over event, and the arena
## draws the screen from `from_dict()`. Pure data, no clock: moments carry the run time World passes in.

## Moments: [key, text (%s is the wizard, %v the detail), weight]. Indices travel in the record, so append new
## ones at the end. Higher weights rank first on the screen; ties go to the later moment.
const M_LICH := 0
const M_ARCHLICH := 1
const M_CHEST := 2 # value = Loot tier (legendary and up are noted)
const M_BLESSING := 3
const M_CURSE := 4
const M_JACKPOT := 5
const M_COMBO := 6 # value = combo count
const M_EVOLVE := 7 # value = Upgrades index of the evolution
const MOMENTS: Array = [
	["lich", "%s SLEW THE LICH LORD", 60],
	["archlich", "%s SLEW THE ARCHLICH", 100],
	["chest", "%s FOUND %v", 50],
	["blessing", "%s BLESSED THE PARTY", 70],
	["curse", "%s CURSED THE PARTY", 75],
	["jackpot", "%s HIT THE JACKPOT", 45],
	["combo", "%s CHAINED A %v COMBO", 40],
	["evolve", "%s EVOLVED %v", 30],
]

## Combos worth a moment, and how many moments the screen shows.
const COMBO_MOMENTS := [100, 200, 400]
const SHOWN_MOMENTS := 4

## Stat keys kept per wizard. Every one starts at 0.
const STATS := ["damage", "kills", "elites", "best_combo", "chests", "best_tier", "gold", "bets", "deaths", "level"]

## Awards: [title, stat, true if the lowest value wins], best first. An award goes only to the wizard who really
## leads its stat; a wizard who leads several shows the first. In a party, anyone left without one is a TEAM PLAYER.
const AWARDS: Array = [
	["MVP", "damage", false],
	["SLAYER", "kills", false],
	["HIGH ROLLER", "bets", false],
	["LUCKY", "best_tier", false],
	["GOLD DIGGER", "gold", false],
	["UNTOUCHABLE", "deaths", true],
]
const TEAM_PLAYER := "TEAM PLAYER"

var stats := {} # slot -> {stat key -> number}
var moments: Array = [] # [t, kind, slot, value]


func _init(slots: Array = []) -> void:
	for s: int in slots:
		join(s)


## Adds a wizard (a late joiner starts from zero).
func join(slot: int) -> void:
	if stats.has(slot):
		return
	var row := {}
	for k: String in STATS:
		row[k] = 0.0
	stats[slot] = row


func add(slot: int, key: String, amount: float) -> void:
	if stats.has(slot):
		stats[slot][key] = float(stats[slot][key]) + amount


## Keeps the larger of the stat and `value`.
func best(slot: int, key: String, value: float) -> void:
	if stats.has(slot):
		stats[slot][key] = maxf(float(stats[slot][key]), value)


func set_stat(slot: int, key: String, value: float) -> void:
	if stats.has(slot):
		stats[slot][key] = value


func stat(slot: int, key: String) -> float:
	return float(stats.get(slot, {}).get(key, 0.0))


func note(t: float, kind: int, slot: int, value: int = 0) -> void:
	moments.append([t, kind, slot, value])


## The best `n` moments, best first: by weight, then the later one.
func top_moments(n: int = SHOWN_MOMENTS) -> Array:
	var out: Array = moments.duplicate()
	out.sort_custom(func(a: Array, b: Array) -> bool:
		var wa: int = MOMENTS[a[1]][2]
		var wb: int = MOMENTS[b[1]][2]
		if wa != wb:
			return wa > wb
		return float(a[0]) > float(b[0]))
	return out.slice(0, n)


## [slot, title] for each wizard, in slot order: the first award whose stat they lead (ties go to the lower
## slot). A stat nobody scored on, or a lowest-wins stat the whole party ties on, gives no award. With two or
## more wizards, one who leads nothing is a TEAM PLAYER; a solo wizard with nothing gets no title.
func awards() -> Array:
	var slots: Array = stats.keys()
	slots.sort()
	var title := {}
	for row: Array in AWARDS:
		var key: String = row[1]
		var low: bool = row[2]
		var lead: int = -1
		var spread := false
		for s: int in slots:
			var v: float = stat(s, key)
			if v != stat(slots[0], key):
				spread = true
			if lead < 0 or (v < stat(lead, key) if low else v > stat(lead, key)):
				lead = s
		if lead < 0 or title.has(lead):
			continue
		if (low and not spread) or (not low and stat(lead, key) <= 0.0):
			continue
		title[lead] = row[0]
	var out: Array = []
	for s: int in slots:
		if title.has(s):
			out.append([s, title[s]])
		elif slots.size() > 1:
			out.append([s, TEAM_PLAYER])
	return out


## The line the screen shows for a moment, with the wizard as P1..P4.
static func moment_text(m: Array) -> String:
	var kind: int = m[1]
	var detail := ""
	match kind:
		M_CHEST:
			detail = Loot.RARITY_NAMES[clampi(int(m[3]), 0, Loot.ULTRA)] + " LOOT"
		M_COMBO:
			detail = "x%d" % int(m[3])
		M_EVOLVE:
			detail = Upgrades.display_name(int(m[3]))
	var who := "P%d" % (int(m[2]) + 1)
	return String(MOMENTS[kind][1]).replace("%s", who).replace("%v", detail)


func to_dict() -> Dictionary:
	var st := {}
	for s: int in stats:
		st[s] = (stats[s] as Dictionary).duplicate()
	return {"stats": st, "moments": moments.duplicate(true)}


## A record from to_dict() (or from the network): unknown moment kinds are dropped.
static func from_dict(d: Dictionary) -> Results:
	var r := Results.new()
	var st: Variant = d.get("stats", {})
	if st is Dictionary:
		for s: Variant in st:
			r.join(int(s))
			var row: Variant = st[s]
			if row is Dictionary:
				for k: String in STATS:
					r.stats[int(s)][k] = float((row as Dictionary).get(k, 0.0))
	var ms: Variant = d.get("moments", [])
	if ms is Array:
		for m: Variant in ms:
			if m is Array and (m as Array).size() == 4 and int(m[1]) >= 0 and int(m[1]) < MOMENTS.size():
				r.moments.append([float(m[0]), int(m[1]), int(m[2]), int(m[3])])
	return r
