class_name Profile
extends RefCounted
## The player's progress between runs: best score, crystals (earned by playing, never bought) and the meta
## unlocks bought with them. Pure data: the Save autoload loads and writes it, World reads `bonuses()` at the
## start of a run. In co-op the host's profile powers the whole party, so friends who join through Remote Play
## get the same head start.

## 2: heroes (Hero) hold the card sockets; a version 1 save becomes one HUMAN MAGE holding its sockets.
const VERSION := 2
## Saved heroes at most.
const MAX_HEROES := 8

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
## The saved heroes (Hero), at least one and at most MAX_HEROES, and the one the next run plays (an index).
var heroes: Array = [Hero.new()]
var hero := 0
## The active hero's sockets: Cards key in the hat, robe and staff ("" for empty). The socket calls below work on it.
var sockets: Array[String]:
	get:
		return active_hero().sockets
var secrets := {} # secret key -> true, once found (the Sanctum alcove, title easter eggs, Ouija words)
var wishes := 0 # crystals tossed into the Sanctum's wishing well, ever
var pots_run := -1 # the run count when the Sanctum's pots were last smashed; they refill after the next run
var pots_mask := 0 # which pots (a bit per Sanctum.POTS index) were smashed then; valid only while pots_run == runs
## The difficulty ladder (Seals): the highest step open, the highest step won (Seals.MIN - 1 for none) and the
## steps whose first-win prize is paid (str(step) -> true). Totals over every run: kills and rituals finished.
var seal_unlocked := Seals.START_UNLOCKED
var seal_best := Seals.MIN - 1
var seal_prizes := {}
var kills_total := 0
var revives_total := 0
## What the last finish_run paid for its step, for the results screen (not saved): seal, mul (the bounty
## multiplier), bounty (crystals the multiplier added or took), prize (a first win's crystals), card (the Seal card
## a first win paid, -1 none).
var last_pay := {}
## Levels the last finish_run gave each saved hero (profile index -> levels gained; not saved).
var last_hero_levels := {}


## The hero the next run plays.
func active_hero() -> Hero:
	return heroes[clampi(hero, 0, heroes.size() - 1)]


## Adds a hero and makes it the active one. False when MAX_HEROES are saved already.
func add_hero(h: Hero) -> bool:
	if heroes.size() >= MAX_HEROES:
		return false
	heroes.append(h)
	hero = heroes.size() - 1
	return true


## Deletes hero `i`. The last hero cannot go (a profile always has one); the active index follows.
func remove_hero(i: int) -> bool:
	if i < 0 or i >= heroes.size() or heroes.size() <= 1:
		return false
	heroes.remove_at(i)
	if hero > i or hero >= heroes.size():
		hero = maxi(0, hero - 1)
	return true


## The hero the next run plays.
func active_hero() -> Hero:
	return heroes[clampi(hero, 0, heroes.size() - 1)]


## Adds a hero and makes it the active one. False when MAX_HEROES are saved already.
func add_hero(h: Hero) -> bool:
	if heroes.size() >= MAX_HEROES:
		return false
	heroes.append(h)
	hero = heroes.size() - 1
	return true


## Deletes hero `i`. The last hero cannot go (a profile always has one); the active index follows.
func remove_hero(i: int) -> bool:
	if i < 0 or i >= heroes.size() or heroes.size() <= 1:
		return false
	heroes.remove_at(i)
	if hero > i or hero >= heroes.size():
		hero = maxi(0, hero - 1)
	return true


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


## The Sanctum pots smashed since the last run, as a bit mask (0 once a run has been played since).
func pots_mask_now() -> int:
	return pots_mask if pots_run == runs else 0


## Books that Sanctum pot `i` was smashed this visit.
func break_pot(i: int) -> void:
	pots_mask = pots_mask_now() | (1 << i)
	pots_run = runs


## Spends `cost` crystals. False (and nothing spent) if there are too few.
func spend(cost: int) -> bool:
	if cost > crystals:
		return false
	crystals -= cost
	return true


func unsocket(s: int) -> void:
	if s >= 0 and s < Cards.SOCKETS:
		sockets[s] = ""


## `mul` (Seals.crystal_mul) scales only the Lich and win bounties, so losing fast at a high step pays nothing extra.
static func crystals_for_run(seconds: float, kills: int, liches: int, won: bool = false, mul: float = 1.0) -> int:
	return int(seconds / CRYSTAL_SECONDS) + kills / CRYSTAL_KILLS + bounty(liches, won, mul)


## The Lich and win bounties at a step's multiplier, rounded.
static func bounty(liches: int, won: bool, mul: float = 1.0) -> int:
	return roundi((liches * CRYSTAL_LICH + (CRYSTAL_WIN if won else 0)) * mul)


func seal_open(level: int) -> bool:
	return level >= Seals.MIN and level <= seal_unlocked


## The step a run may start at from `level` (a stale Net.seal from another host's lobby can be locked here):
## the level when open, else the highest open step below it, or WIZARD for anything under the ladder.
func playable_seal(level: int) -> int:
	if level < Seals.MIN:
		return 0
	return mini(level, seal_unlocked)


func prize_claimed(level: int) -> bool:
	return seal_prizes.has(str(level))


## The first-win prize still waiting at a step (0 when paid or when the step pays none).
func prize_left(level: int) -> int:
	return 0 if prize_claimed(level) else Seals.prize(level)


## Books a finished run: best score and time, wins, crystals earned. Returns the crystals it paid. `run` holds
## score, seconds, kills, liches, won, seal, and revives or results (the run's Results, whose rituals are added up);
## missing keys count 0 / false. The step (seal) scales the bounties; a win opens the next step and, the first
## time at a step, pays its prize and Seal card. `heroes` (profile hero indices, each counted once) are the
## saved heroes this machine's seats played: each earns the run's class XP (last_hero_levels says the levels gained).
func finish_run(run: Dictionary) -> int:
	var score := int(run.get("score", 0))
	var seconds := float(run.get("seconds", 0.0))
	var kills := int(run.get("kills", 0))
	var liches := int(run.get("liches", 0))
	var won := bool(run.get("won", false))
	var seal := clampi(int(run.get("seal", 0)), Seals.MIN, Seals.MAX)
	runs += 1
	kills_total += maxi(0, kills)
	revives_total += maxi(0, int(run.get("revives", 0)))
	var res: Variant = run.get("results")
	if res is Results:
		for slot: Variant in (res as Results).stats:
			revives_total += (res as Results).revives(int(slot))
	if won:
		wins += 1
	high_score = maxi(high_score, score)
	best_time = maxf(best_time, seconds)
	var mul := Seals.crystal_mul(seal)
	var earned: int = crystals_for_run(seconds, kills, liches, won, mul)
	last_pay = {"seal": seal, "mul": mul, "bounty": bounty(liches, won, mul) - bounty(liches, won), "prize": 0, "card": -1}
	if won:
		seal_best = maxi(seal_best, seal)
		seal_unlocked = clampi(maxi(seal_unlocked, seal + 1), Seals.START_UNLOCKED, Seals.MAX)
		if not prize_claimed(seal) and (Seals.prize(seal) > 0 or Seals.card(seal) >= 0):
			seal_prizes[str(seal)] = true
			last_pay.prize = Seals.prize(seal)
			earned += Seals.prize(seal)
			var sc := Seals.card(seal)
			if sc >= 0:
				last_pay.card = sc # named even when the Archlich's drop already brought it this run
				if card_count(sc) == 0:
					cards[Cards.key(sc)] = 1
	crystals += earned
	last_hero_levels = {}
	var seen: Array[int] = []
	for v: Variant in run.get("heroes", []):
		var hi := int(v)
		if hi < 0 or hi >= heroes.size() or seen.has(hi):
			continue
		seen.append(hi)
		last_hero_levels[hi] = heroes[hi].add_xp(heroes[hi].run_xp(seconds, liches, won, mul))
	return earned


func to_dict() -> Dictionary:
	return {"version": VERSION, "high_score": high_score, "crystals": crystals, "runs": runs, "wins": wins,
		"best_time": best_time, "unlocks": unlocks.duplicate(), "cards": cards.duplicate(), "sockets": sockets.duplicate(), "secrets": secrets.keys(), "pots_run": pots_run, "pots_mask": pots_mask, "wishes": wishes,
		"seal_unlocked": seal_unlocked, "seal_best": seal_best, "seal_prizes": seal_prizes.keys(), "kills_total": kills_total,
		"revives_total": revives_total, "heroes": heroes.map(func(h: Hero) -> Dictionary: return h.to_dict()), "hero": hero}


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
	# An old save has no mask: its pots all stay broken until the next run, as they always did.
	p.pots_mask = int(d.get("pots_mask", Sanctum.ALL_POTS)) & Sanctum.ALL_POTS
	p.wishes = maxi(0, int(d.get("wishes", 0)))
	# The ladder: an old save has none of these and starts at the default (ARCHMAGE open, nothing won).
	p.seal_unlocked = clampi(int(d.get("seal_unlocked", Seals.START_UNLOCKED)), Seals.START_UNLOCKED, Seals.MAX)
	p.seal_best = clampi(int(d.get("seal_best", Seals.MIN - 1)), Seals.MIN - 1, Seals.MAX)
	var sp: Variant = d.get("seal_prizes", [])
	if sp is Array:
		for k: Variant in sp:
			if str(k).is_valid_int() and int(str(k)) >= Seals.MIN and int(str(k)) <= Seals.MAX:
				p.seal_prizes[str(int(str(k)))] = true
	p.kills_total = maxi(0, int(d.get("kills_total", 0)))
	p.revives_total = maxi(0, int(d.get("revives_total", 0)))
	# Heroes. A version 1 save has none: it becomes one HUMAN MAGE holding its sockets (it never saved a school,
	# so she casts slot 0's ARCANE BOLT). Top-level "sockets" is a copy of the active hero's, kept for old builds.
	var hs: Variant = d.get("heroes", [])
	p.heroes = []
	if hs is Array:
		for hd: Variant in hs:
			if hd is Dictionary and p.heroes.size() < MAX_HEROES:
				p.heroes.append(Hero.from_dict(hd))
	if p.heroes.is_empty():
		p.heroes = [Hero.from_dict({"sockets": d.get("sockets", [])})]
	p.hero = clampi(int(d.get("hero", 0)), 0, p.heroes.size() - 1)
	for h: Hero in p.heroes:
		for s: int in range(Cards.SOCKETS):
			var idx: int = Cards.index_of(h.sockets[s])
			if idx >= 0 and p.card_count(idx) <= 0:
				h.sockets[s] = ""
	return p
