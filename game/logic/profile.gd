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
var cards := {} # Cards key -> how many found
var sockets: Array[String] = ["", "", ""] # Cards key socketed in the hat, robe and staff ("" for empty)
var secrets := {} # secret key -> true, once found (the Sanctum alcove, title easter eggs, Ouija words)
var wishes := 0 # crystals tossed into the Sanctum's wishing well, ever
var pots_run := -1 # the run count when the Sanctum's pots were last smashed; they refill after the next run


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


## What the unlocks add to a run: {hearts, damage, xp, gold, novas, luck} (zero when nothing is bought) and
## "armor": the socketed cards' stats in Loot.empty_stats layout.
func bonuses() -> Dictionary:
	var out := {"hearts": 0.0, "damage": 0.0, "xp": 0.0, "gold": 0.0, "novas": 0.0, "luck": 0.0}
	for key: String in EFFECTS:
		var eff: Array = EFFECTS[key]
		out[eff[0]] = float(out[eff[0]]) + float(eff[1]) * level(key)
	out["armor"] = Cards.socket_stats(socket_indices())
	return out


## How many of card `idx` the player has found.
func card_count(idx: int) -> int:
	return int(cards.get(Cards.key(idx), 0))


## Books a found card. Returns true if it is the first of its kind.
func add_card(idx: int) -> bool:
	if idx < 0 or idx >= Cards.count():
		return false
	var first := card_count(idx) == 0
	cards[Cards.key(idx)] = card_count(idx) + 1
	return first


func cards_owned() -> int:
	var n := 0
	for i: int in range(Cards.count()):
		if card_count(i) > 0:
			n += 1
	return n


## Card index in each socket, -1 for empty.
func socket_indices() -> Array[int]:
	var out: Array[int] = []
	for s: int in range(Cards.SOCKETS):
		out.append(Cards.index_of(sockets[s]))
	return out


## Puts an owned card in its own socket (replacing what was there). False if not owned.
func socket_card(idx: int) -> bool:
	if idx < 0 or idx >= Cards.count() or card_count(idx) <= 0:
		return false
	sockets[Cards.socket(idx)] = Cards.key(idx)
	return true


## Marks a secret found. Returns true the first time.
func find_secret(k: String) -> bool:
	if secrets.has(k):
		return false
	secrets[k] = true
	return true


func has_secret(k: String) -> bool:
	return secrets.has(k)


## True if the Sanctum's pots were already smashed since the last run.
func pots_smashed() -> bool:
	return pots_run == runs


## Spends `cost` crystals. False (and nothing spent) if there are too few.
func spend(cost: int) -> bool:
	if cost > crystals:
		return false
	crystals -= cost
	return true


func unsocket(s: int) -> void:
	if s >= 0 and s < Cards.SOCKETS:
		sockets[s] = ""


static func crystals_for_run(seconds: float, kills: int, liches: int, won: bool = false) -> int:
	return int(seconds / CRYSTAL_SECONDS) + kills / CRYSTAL_KILLS + liches * CRYSTAL_LICH + (CRYSTAL_WIN if won else 0)


## Books a finished run: best score and time, wins, crystals earned. Returns the crystals it paid. `run` holds
## score, seconds, kills, liches and won (missing keys count 0 / false); a "seal" key is carried but not read yet.
func finish_run(run: Dictionary) -> int:
	var score := int(run.get("score", 0))
	var seconds := float(run.get("seconds", 0.0))
	var kills := int(run.get("kills", 0))
	var liches := int(run.get("liches", 0))
	var won := bool(run.get("won", false))
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
		"best_time": best_time, "unlocks": unlocks.duplicate(), "cards": cards.duplicate(), "sockets": sockets.duplicate(), "secrets": secrets.keys(), "pots_run": pots_run, "wishes": wishes}


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
	var c: Variant = d.get("cards", {})
	if c is Dictionary:
		for key: Variant in c:
			if Cards.index_of(str(key)) >= 0 and int(c[key]) > 0:
				p.cards[str(key)] = int(c[key])
	var se: Variant = d.get("secrets", [])
	if se is Array:
		for k: Variant in se:
			p.secrets[str(k)] = true
	p.pots_run = int(d.get("pots_run", -1))
	p.wishes = maxi(0, int(d.get("wishes", 0)))
	var so: Variant = d.get("sockets", [])
	if so is Array:
		for s: int in range(mini((so as Array).size(), Cards.SOCKETS)):
			var idx: int = Cards.index_of(str(so[s]))
			if idx >= 0 and Cards.socket(idx) == s and p.card_count(idx) > 0:
				p.sockets[s] = str(so[s])
	return p
