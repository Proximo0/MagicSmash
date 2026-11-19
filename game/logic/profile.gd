class_name Profile
extends RefCounted
## The player's progress between runs: best score, crystals (earned by playing, never bought) and the meta
## unlocks bought with them. Pure data: the Save autoload loads and writes it, World reads `bonuses()` at the
## start of a run. In co-op the host's profile powers the whole party, so friends who join through Remote Play
## get the same head start.

const VERSION := 1

## [key, name, description, crystal cost per level]. The number of costs is the max level. Effects per level
## are in EFFECTS. Append new unlocks at the end; keys are what the save file stores.
const META: Array = [
	["vigor", "WARDED ROBES", "+1 HEART", [30, 90]],
	["might", "RUNED STAFF", "+5% DAMAGE", [20, 50, 110]],
	["wisdom", "FORBIDDEN LORE", "+6% XP", [20, 50, 110]],
	["fortune", "MIDAS' PURSE", "+15% GOLD", [15, 40, 90]],
	["novas", "BOTTLED STAR", "+1 NOVA", [25, 70]],
	["luck", "FOUR-LEAF RUNE", "LUCKIER CHESTS", [60, 160]],
]

## Bonus per level for each META key, as World.apply_meta reads them.
const EFFECTS := {
	"vigor": ["hearts", 1.0],
	"might": ["damage", 0.05],
	"wisdom": ["xp", 0.06],
	"fortune": ["gold", 0.15],
	"novas": ["novas", 1.0],
	"luck": ["luck", 1.0],
}

## Crystals a run pays: one per CRYSTAL_SECONDS survived, one per CRYSTAL_KILLS kills, CRYSTAL_LICH per Lich slain
## (the Archlich counts as one) and CRYSTAL_WIN for a won run.
const CRYSTAL_SECONDS := 30.0
const CRYSTAL_KILLS := 250
const CRYSTAL_LICH := 10
const CRYSTAL_WIN := 25

var high_score := 0
var crystals := 0
var runs := 0
var wins := 0
var best_time := 0.0
var unlocks := {} # META key -> level bought


static func meta_index(key: String) -> int:
	for i: int in range(META.size()):
		if META[i][0] == key:
			return i
	return -1


static func max_level(i: int) -> int:
	return (META[i][3] as Array).size()


func level(key: String) -> int:
	return int(unlocks.get(key, 0))


## Crystal cost of the next level of META[i], or -1 when it is maxed.
func next_cost(i: int) -> int:
	var lv: int = level(META[i][0])
	var costs: Array = META[i][3]
	return int(costs[lv]) if lv < costs.size() else -1


## Spends crystals on the next level of META[i]. False if it is maxed or too dear.
func buy(i: int) -> bool:
	var c: int = next_cost(i)
	if c < 0 or c > crystals:
		return false
	crystals -= c
	unlocks[META[i][0]] = level(META[i][0]) + 1
	return true


## What the unlocks add to a run: {hearts, damage, xp, gold, novas, luck}, zero when nothing is bought.
func bonuses() -> Dictionary:
	var out := {"hearts": 0.0, "damage": 0.0, "xp": 0.0, "gold": 0.0, "novas": 0.0, "luck": 0.0}
	for key: String in EFFECTS:
		var eff: Array = EFFECTS[key]
		out[eff[0]] = float(out[eff[0]]) + float(eff[1]) * level(key)
	return out


static func crystals_for_run(seconds: float, kills: int, liches: int, won: bool = false) -> int:
	return int(seconds / CRYSTAL_SECONDS) + kills / CRYSTAL_KILLS + liches * CRYSTAL_LICH + (CRYSTAL_WIN if won else 0)


## Books a finished run: best score and time, wins, crystals earned. Returns the crystals it paid.
func finish_run(score: int, seconds: float, kills: int, liches: int, won: bool = false) -> int:
	runs += 1
	if won:
		wins += 1
	high_score = maxi(high_score, score)
	best_time = maxf(best_time, seconds)
	var earned: int = crystals_for_run(seconds, kills, liches, won)
	crystals += earned
	return earned


func to_dict() -> Dictionary:
	return {"version": VERSION, "high_score": high_score, "crystals": crystals, "runs": runs, "wins": wins,
		"best_time": best_time, "unlocks": unlocks.duplicate()}


## A profile from saved data. Unknown keys are ignored, unknown unlocks dropped and levels clamped, so an old
## or hand-edited file still loads.
static func from_dict(d: Dictionary) -> Profile:
	var p := Profile.new()
	p.high_score = maxi(0, int(d.get("high_score", 0)))
	p.crystals = maxi(0, int(d.get("crystals", 0)))
	p.runs = maxi(0, int(d.get("runs", 0)))
	p.wins = maxi(0, int(d.get("wins", 0)))
	p.best_time = maxf(0.0, float(d.get("best_time", 0.0)))
	var u: Variant = d.get("unlocks", {})
	if u is Dictionary:
		for key: Variant in u:
			var i: int = meta_index(str(key))
			if i >= 0:
				p.unlocks[str(key)] = clampi(int(u[key]), 0, max_level(i))
	return p
