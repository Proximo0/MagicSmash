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

## [key, name, description, crystal cost per level] (docs/content_list.md § 45). The number of costs is the max
## level. Effects per level are in EFFECTS. Append new unlocks at the end; keys are what the save file stores.
## A CLEAN SLATE (`respec`) is bought each time and never gains a level (clean_slate).
const META: Array = [
	["vigor", "WARDED ROBES", "+1 HEART", [40, 160]],
	["might", "RUNED STAFF", "+4% DAMAGE", [30, 70, 150, 300, 600]],
	["wisdom", "FORBIDDEN LORE", "+6% XP", [30, 80, 200]],
	["fortune", "MIDAS' PURSE", "+15% GOLD", [20, 60, 150]],
	["novas", "BOTTLED STAR", "+1 NOVA", [40, 140]],
	["luck", "FOUR-LEAF RUNE", "LUCKIER CHESTS", [80, 240]],
	["redraw", "THE SECOND GLANCE", "+1 REDRAW EACH RUN", [60, 220]],
	["banish", "THE BLACK RIBBON", "+1 BANISH EACH RUN", [60, 220]],
	["start_level", "THE HEAD START", "THE PARTY STARTS A LEVEL UP", [120, 400]],
	["satchel", "THE SATCHEL", "+1 POCKET FOR EVERY HERO", [300, 900]],
	["favour", "THE READER'S FAVOUR", "DEAL THE READING AGAIN, THEN 4", [250, 750]],
	["respec", "A CLEAN SLATE", "HER STAT POINTS BACK TO SPEND", [50]],
	["deck_hex", "THE WITCH'S DECK", "OPENS HEX AND THE DEVIL", [150]],
	["deck_blades", "THE DUELLIST'S DECK", "OPENS SPIRIT BLADES, THE EMPRESS", [150]],
	["deck_priestess", "THE VEILED DECK", "OPENS THE HIGH PRIESTESS", [200]],
]
const RESPEC := "respec"

## Bonus per level for each META key, as World.apply_meta reads them. satchel, respec and the decks have no run
## effect (the satchel's pockets live on the heroes; the decks open content: OPENS).
const EFFECTS := {
	"vigor": ["hearts", 1.0],
	"might": ["damage", 0.04],
	"wisdom": ["xp", 0.06],
	"fortune": ["gold", 0.15],
	"novas": ["novas", 1.0],
	"luck": ["luck", 1.0],
	"redraw": ["redraws", 1.0],
	"banish": ["banishes", 1.0],
	"start_level": ["start_level", 1.0],
	"favour": ["favour", 1.0],
}

## The shop levels a Seal win holds back (CL § 43): META key -> {level -> the ladder step (Seals) whose win opens
## it}. A step is won when seal_best is at least it. A level not named here is open on a new profile.
const GATES := {
	"might": {4: 5, 5: 5},
	"redraw": {2: 6},
	"banish": {2: 3},
	"start_level": {2: 8},
	"satchel": {2: 4},
	"favour": {2: 7},
}

## META keys whose effect is not in the game yet: off the shelf (shelf, closed_why "NOT YET"). Each job that builds
## a row takes its key off (redraw, banish and start_level are built: WorldLevels._shop_start); respec stays until the
## shop screen can draw a row without levels.
const UNBUILT: Array[String] = ["satchel", "favour", "respec", "deck_hex", "deck_blades", "deck_priestess"]
## closed_why's words: maxed, not built yet, a Seal win to come ("WIN " + Seals.title), no points to give back.
const WHY_MAX := "MAX"
const WHY_UNBUILT := "NOT YET"
const WHY_WIN := "WIN "
const WHY_NO_POINTS := "NO POINTS"

## The unlock track (CL § 44): [kind, source, content keys]. kind "start": open on a new profile; "deed": open once
## the deed (an Achievements api name) is earned, and for everyone while Achievements.LIST lacks it; "deck": open
## once the META key is bought. Keys are Upgrades catalog keys, Reading keys, class and race names, "reading",
## "overtime" and "daily". An evolution is never listed: it opens when every row its catalog `requires` names is
## open (locked_rows). A saved hero's class and race are open too (opened).
const OPENS: Array = [
	["start", "", ["MAGE", "HUMAN", "ELF", "w_arcane", "w_fire", "w_frost", "w_storm", "w_star", "w_rune",
		"quick", "power", "regen", "swift", "wisdom", "magnet"]],
	["deed", "LEVEL_5", ["star"]],
	["deed", "BOSS_CHANDELIER", ["reading", "r_wands_1", "r_cups_1", "r_swords_1", "r_pent_1", "r_wands_4"]],
	["deed", "EVOLVE", ["nova"]],
	["deed", "TEN_MINUTES", ["KNIGHT", "w_cleave", "DWARF"]],
	["deed", "FALLS_5", ["life"]],
	["deed", "BOSS_GHOSTWRITER", ["ARCHER", "w_bone", "justice"]],
	["deed", "OMENS", ["PRIEST", "ORC", "w_candle", "lovers"]],
	["deed", "ARCHLICH", ["PALADIN", "overtime", "daily", "r_pent_10"]],
	["deed", "COMBO_200", ["r_wands_8"]],
	["deed", "SEAL", ["r_wands_10"]],
	["deed", "REVIVE_3", ["r_cups_2"]],
	["deed", "BLESSED", ["r_cups_9"]],
	["deed", "CURSED", ["r_swords_3"]],
	["deed", "JACKPOT", ["r_pent_4"]],
	["deed", "KILLS_10K", ["r_swords_7"]],
	["deed", "KILLS_100K", ["r_pent_9"]],
	["deed", "WIN_ARCHMAGE", ["r_cups_5"]],
	["deed", "WIN_SEAL_1", ["r_swords_10"]],
	["deck", "deck_hex", ["w_hex", "devil"]],
	["deck", "deck_blades", ["w_blades", "empress"]],
	["deck", "deck_priestess", ["priestess"]],
]
## The catalog kinds the unlock track can lock (locked_rows).
const LOCKABLE_KINDS: Array[int] = [Upgrades.SPELL, Upgrades.PASSIVE, Upgrades.INSTANT, Upgrades.EVOLUTION]

## Crystals a run pays: one per CRYSTAL_SECONDS survived, one per CRYSTAL_KILLS kills, CRYSTAL_LICH per Lich slain
## (the Archlich counts as one) and CRYSTAL_WIN for a won run.
const CRYSTAL_SECONDS := 30.0
const CRYSTAL_KILLS := 250
const CRYSTAL_LICH := 10
const CRYSTAL_WIN := 25
## Urns broken over every run (Profile.urns) after which each run is given the urn card (bonuses' "urn_card"), until
## the secret "urn_card" (a card found in an arena urn) is found.
const URN_CARD_AFTER := 120

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
var talked := {} # chat keys already told ("<speaker>/first"): a first visit is greeted once, not every launch
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
var urns := 0 # urns broken over every run (World.urns_broken, run_so_far's "urns"); see URN_CARD_AFTER
## The Book of Deeds: the api names (Achievements.LIST) of every deed earned, in the order earned (name -> true).
## A name this build does not know stays in the save. Each deed's crystals are paid once, when it is first earned.
var deeds := {}
## What the last finish_run paid for its step, for the results screen (not saved): seal, mul (the bounty
## multiplier), bounty (crystals the multiplier added or took), prize (a first win's crystals), card (the Seal card
## a first win paid, -1 none), deeds (api names earned this run, in order) and deeds_pay (their crystals).
var last_pay := {}
## Levels the last finish_run gave each saved hero (profile index -> levels gained; not saved).
var last_hero_levels := {}
## Loaded from a file a newer build wrote (its "version" above VERSION; not saved). Its extra data would be lost
## on the next write, so Save never writes it back (Save.newer_save()).
var newer := false


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


## Where a held hero index `idx` lands after hero `removed` is deleted: -1 when it was that hero, one lower when it
## sat above her, itself otherwise. The active index and every lobby seat's hero follow this one rule.
static func index_after_removal(idx: int, removed: int) -> int:
	if idx == removed:
		return -1
	return idx - 1 if idx > removed else idx


## Deletes hero `i`. The last hero cannot go (a profile always has one); the active index follows (when she was the
## active one, the hero who takes her place is).
func remove_hero(i: int) -> bool:
	if i < 0 or i >= heroes.size() or heroes.size() <= 1:
		return false
	heroes.remove_at(i)
	hero = clampi(hero if hero == i else index_after_removal(hero, i), 0, heroes.size() - 1)
	return true


## All the crystals the last run brought: finish_run's own pay plus its deeds' (`earned` is what finish_run returned).
func run_gain(earned: int) -> int:
	return earned + int(last_pay.get("deeds_pay", 0))


## The chat key of a speaker's first visit.
static func first_key(speaker: int) -> String:
	return "%d/first" % speaker


## True the first time `key` (a chat's "<speaker>/first") is asked about on this profile, and never again: the
## greeting of a first visit is told once across launches. Saved with the profile.
func first_time(key: String) -> bool:
	if talked.has(key):
		return false
	talked[key] = true
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


## The ladder step whose win opens level `lv` of META row `key`, or Seals.MIN - 1 when no win holds it back.
static func gate_step(key: String, lv: int) -> int:
	var g: Dictionary = GATES.get(key, {})
	return int(g.get(lv, Seals.MIN - 1))


## What a Seal gate says in the place of a price ("WIN SEAL IV"), "" for a level no win holds back.
static func gate_why(key: String, lv: int) -> String:
	var step := gate_step(key, lv)
	return "" if step < Seals.MIN else WHY_WIN + Seals.title(step)


## True when this profile's wins open level `lv` of META row `key` (CL § 43).
func level_open(key: String, lv: int) -> bool:
	return seal_best >= gate_step(key, lv)


## Crystal cost of the next level of META[i], or -1 when it is maxed or a Seal win still holds that level back.
func next_cost(i: int) -> int:
	var key: String = META[i][0]
	var lv: int = level(key)
	var costs: Array = META[i][3]
	if lv >= costs.size() or not level_open(key, lv + 1):
		return -1
	return int(costs[lv])


## The META rows on sale (indices, in order): every row whose effect is built (not on UNBUILT).
static func shelf() -> Array[int]:
	var out: Array[int] = []
	for i: int in range(META.size()):
		if not UNBUILT.has(META[i][0]):
			out.append(i)
	return out


## Why META[i] cannot be bought now, in at most 12 letters: "" when it can (crystals aside), "NOT YET" for a row off
## the shelf, "MAX", "WIN SEAL IV" and its kin for a gated level, "NO POINTS" for a clean slate with nothing to
## give back.
func closed_why(i: int) -> String:
	var key: String = META[i][0]
	if UNBUILT.has(key):
		return WHY_UNBUILT
	if key == RESPEC:
		return "" if active_hero().points_spent() > 0 else WHY_NO_POINTS
	var lv: int = level(key)
	if lv >= max_level(i):
		return WHY_MAX
	return gate_why(key, lv + 1) if not level_open(key, lv + 1) else ""


## Spends crystals on the next level of META[i]. False if it is off the shelf, maxed, held back or too dear.
## A CLEAN SLATE goes through clean_slate.
func buy(i: int) -> bool:
	if i < 0 or i >= META.size() or UNBUILT.has(META[i][0]):
		return false
	if META[i][0] == RESPEC:
		return clean_slate()
	var c: int = next_cost(i)
	if c < 0 or c > crystals:
		return false
	crystals -= c
	unlocks[META[i][0]] = level(META[i][0]) + 1
	return true


## A CLEAN SLATE: pays its price and gives the active hero her spent stat points back to spend again. The row
## stays at level 0, so it can be bought again. False when she has spent none or it is too dear.
func clean_slate() -> bool:
	var c: int = int((META[meta_index(RESPEC)][3] as Array)[0])
	if active_hero().points_spent() <= 0 or c > crystals:
		return false
	crystals -= c
	active_hero().refund_points()
	return true


## Every content key open to this profile (key -> true; OPENS): the start list, the keys of its deeds (and of a
## deed this build does not hold yet), of its decks, and the class and race name of every saved hero. Computed,
## never stored, so an old save opens everything its record proves.
func opened() -> Dictionary:
	var out := {}
	for row: Array in OPENS:
		var src: String = row[1]
		var open := false
		match str(row[0]):
			"start":
				open = true
			"deed":
				open = has_deed(src) or Achievements.row_of(src).is_empty()
			"deck":
				open = level(src) >= 1
		if open:
			for k: String in row[2]:
				out[k] = true
	for h: Hero in heroes:
		out[Classes.class_name_of(h.cls)] = true
		out[Races.race_name(h.race)] = true
	return out


## The Upgrades.CATALOG rows (SPELL, PASSIVE, INSTANT, EVOLUTION) this profile has not opened, sorted. A row is
## found by its key; an evolution is open when every row its `requires` names is open. The World takes a wizard's
## own class weapon, its arcana and its evolution out of her mask (docs/stage3_brief.md § 4.3).
func locked_rows() -> Array[int]:
	var open := opened()
	var out: Array[int] = []
	for i: int in range(Upgrades.count()):
		var kd := Upgrades.kind(i)
		if not LOCKABLE_KINDS.has(kd):
			continue
		var ok := open.has(Upgrades.key(i))
		if kd == Upgrades.EVOLUTION:
			ok = true
			for req: Array in Upgrades.CATALOG[i][Upgrades.C_REQUIRES]:
				ok = ok and open.has(Upgrades.key(int(req[0])))
		if not ok:
			out.append(i)
	return out


## The hero builder's locks: a class or race is open when its name is (opened).
func class_open(c: int) -> bool:
	return opened().has(Classes.class_name_of(c))


func race_open(r: int) -> bool:
	return opened().has(Races.race_name(r))


## What the unlocks add to a run: {hearts, damage, xp, gold, novas, luck, redraws, banishes, start_level, favour}
## (zero when nothing is bought), the same for every seat, and "locked" (locked_rows: World.apply_meta's mask). No
## "armor": a hero's socketed cards reach the World only through her own hero (World.apply_hero -> Hero.stats),
## so they count once and only for her.
func bonuses() -> Dictionary:
	var out := {}
	for key: String in EFFECTS:
		var eff: Array = EFFECTS[key]
		out[eff[0]] = float(out.get(eff[0], 0.0)) + float(eff[1]) * level(key)
	out["urn_card"] = urns >= URN_CARD_AFTER and not has_secret("urn_card") # a bool, World.apply_meta reads it
	out["locked"] = locked_rows()
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


## Monster cards found, the Seal cards left out: what the ALL_CARDS deed counts (Achievements' "cards" rule).
func monster_cards_owned() -> int:
	var n := 0
	for i: int in range(Cards.count()):
		if Cards.enemy(i) >= 0 and card_count(i) > 0:
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
	urns += maxi(0, int(run.get("urns", 0)))
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
	last_pay = {"seal": seal, "mul": mul, "bounty": bounty(liches, won, mul) - bounty(liches, won), "prize": 0, "card": -1,
		"deeds": [], "deeds_pay": 0}
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
	if res is Results: # a run with no record (a bare dictionary) earns no deeds
		_book_deeds(run, res as Results, won, seconds)
	return earned


## Adds the deeds this run earned (Achievements.earned with `run.party` and this profile's totals), pays their
## crystals once and tells last_pay which they were. The crystals go to the balance, not to finish_run's return
## (the run's own pay).
func _book_deeds(run: Dictionary, record: Results, won: bool, seconds: float) -> void:
	var party: Dictionary = {}
	var given: Variant = run.get("party", {})
	if given is Dictionary:
		party = (given as Dictionary).duplicate()
	party.merge(deed_facts(), true)
	var fresh: Array = []
	var pay := 0
	for api: Variant in Achievements.earned(record, won, seconds, party):
		if not deeds.has(str(api)):
			deeds[str(api)] = true
			fresh.append(str(api))
			pay += Achievements.crystals_of(str(api))
	crystals += pay
	last_pay["deeds"] = fresh
	last_pay["deeds_pay"] = pay


## What the deeds that count over every run read from this profile (see Achievements.earned).
func deed_facts() -> Dictionary:
	var top := 0
	for h: Hero in heroes:
		top = maxi(top, h.level)
	var found := 0
	for row: Array in Secrets.ALL:
		if secrets.has(str(row[0])):
			found += 1
	return {"revives_total": revives_total, "kills_total": kills_total, "hero_level": top, "cards": cards_owned(),
		"monster_cards": monster_cards_owned(), "secrets": found}


func has_deed(api: String) -> bool:
	return deeds.has(api)


## How many of the catalogue's deeds are earned (a name this build does not know is kept but not counted).
func deeds_earned() -> int:
	var n := 0
	for row: Array in Achievements.LIST:
		if deeds.has(str(row[Achievements.C_API])):
			n += 1
	return n


func to_dict() -> Dictionary:
	return {"version": VERSION, "high_score": high_score, "crystals": crystals, "runs": runs, "wins": wins,
		"best_time": best_time, "unlocks": unlocks.duplicate(), "cards": cards.duplicate(), "sockets": sockets.duplicate(), "secrets": secrets.keys(), "pots_run": pots_run, "pots_mask": pots_mask, "wishes": wishes,
		"seal_unlocked": seal_unlocked, "seal_best": seal_best, "seal_prizes": seal_prizes.keys(), "kills_total": kills_total,
		"revives_total": revives_total, "urns": urns, "deeds": deeds.keys(), "talked": talked.keys(), "heroes": heroes.map(func(h: Hero) -> Dictionary: return h.to_dict()), "hero": hero}


## Saved keys from_dict reads with int() or float(), and the same in each saved hero (Hero.from_dict).
const NUMBER_KEYS := ["version", "high_score", "crystals", "runs", "wins", "best_time", "pots_run", "pots_mask",
	"wishes", "seal_unlocked", "seal_best", "kills_total", "revives_total", "hero", "urns"]
const HERO_NUMBER_KEYS := ["school", "look", "level", "xp"]


## Whether int() and float() take `v` without a script error: a JSON number, bool or string (a list, a map or null
## fails).
static func profile_number_ok(v: Variant) -> bool:
	return v is int or v is float or v is bool or v is String


## Whether every value from_dict converts to a number is one profile_number_ok takes. A file that fails this
## parsed as JSON but is damaged: from_dict returns null for it, and Save treats it like unparsable text.
static func profile_types_ok(d: Dictionary) -> bool:
	for k: String in NUMBER_KEYS:
		if d.has(k) and not profile_number_ok(d[k]):
			return false
	for field: String in ["unlocks", "cards"]:
		var m: Variant = d.get(field, {})
		if m is Dictionary:
			for v: Variant in (m as Dictionary).values():
				if not profile_number_ok(v):
					return false
	var hs: Variant = d.get("heroes", [])
	if hs is Array:
		for hd: Variant in hs:
			if not hd is Dictionary:
				continue
			for k: String in HERO_NUMBER_KEYS:
				if (hd as Dictionary).has(k) and not profile_number_ok(hd[k]):
					return false
			var pt: Variant = (hd as Dictionary).get("points", [])
			if pt is Array:
				for v: Variant in pt:
					if not profile_number_ok(v):
						return false
	return true


## Whether a newer build wrote `d` (its "version" is a number above VERSION).
static func profile_from_newer(d: Dictionary) -> bool:
	var v: Variant = d.get("version", VERSION)
	return profile_number_ok(v) and int(v) > VERSION


## A profile from saved data. Unknown keys are ignored, unknown unlocks dropped and levels clamped, so an old
## or hand-edited file still loads. Null when a value has the wrong type (profile_types_ok). A file from a newer
## build (version above VERSION) loads as well as it can and is marked `newer`; with a wrong type it is an empty
## profile marked `newer`, never null.
static func from_dict(d: Dictionary) -> Profile:
	if not profile_types_ok(d):
		if not profile_from_newer(d):
			return null
		# Not damage: a newer build may store a value another way. An empty profile marked `newer` plays, and Save
		# neither writes it nor puts the file aside, so the newer build finds its save whole.
		var blank := Profile.new()
		blank.newer = true
		return blank
	var p := Profile.new()
	p.newer = profile_from_newer(d)
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
	p.urns = maxi(0, int(d.get("urns", 0)))
	var dd: Variant = d.get("deeds", [])
	if dd is Array:
		for k: Variant in dd:
			p.deeds[str(k)] = true # unknown names stay: a newer build may know them
	var tk: Variant = d.get("talked", [])
	if tk is Array:
		for k: Variant in tk:
			p.talked[str(k)] = true
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
