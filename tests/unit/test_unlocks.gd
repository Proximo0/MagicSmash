extends TestCase
## The unlock track and the shop's gates (game/logic/profile.gd): Profile.level_open, the shelf and closed_why,
## A CLEAN SLATE, Profile.opened and Profile.locked_rows (docs/content_list.md § 43 to 45).

## § 44's "open on a new profile", as content keys.
const START := ["MAGE", "HUMAN", "ELF", "w_arcane", "w_fire", "w_frost", "w_storm", "w_star", "w_rune",
	"quick", "power", "regen", "swift", "wisdom", "magnet"]


func _rich() -> Profile:
	var p := Profile.new()
	p.crystals = 100000
	return p


func _keys(d: Dictionary) -> Array:
	var out: Array = d.keys()
	out.sort()
	return out


func _sorted(a: Array) -> Array:
	var out := a.duplicate()
	out.sort()
	return out


## Each gate: shut at the step below its Seal, open at its Seal (ARCHMAGE is step 1, SEAL I is 2).
func test_each_gate_opens_at_its_seal_win() -> void:
	var gates := [["might", 4, 5], ["might", 5, 5], ["redraw", 2, 6], ["banish", 2, 3], ["start_level", 2, 8],
		["satchel", 2, 4], ["favour", 2, 7]]
	for g: Array in gates:
		var p := Profile.new()
		p.seal_best = int(g[2]) - 1
		assert_false(p.level_open(g[0], g[1]), "%s %d open below its step" % [g[0], g[1]])
		p.seal_best = int(g[2])
		assert_true(p.level_open(g[0], g[1]), "%s %d shut at its step" % [g[0], g[1]])
	var fresh := Profile.new()
	for key: String in ["vigor", "might", "redraw", "satchel"]:
		assert_true(fresh.level_open(key, 1), key + " level 1 is open on a new profile")
	assert_true(fresh.level_open("might", 3))


## next_cost and buy refuse a level that is not open: RUNED STAFF stops at 3 until the SEAL IV win.
func test_a_gated_level_cannot_be_bought() -> void:
	var p := _rich()
	var i := Profile.meta_index("might")
	for _k: int in range(3):
		assert_true(p.buy(i))
	assert_eq(p.next_cost(i), -1)
	assert_false(p.buy(i), "level 4 before the SEAL IV win")
	assert_eq(p.closed_why(i), "WIN SEAL IV")
	p.seal_best = 5
	assert_eq(p.next_cost(i), 300)
	assert_eq(p.closed_why(i), "")
	assert_true(p.buy(i))
	assert_true(p.buy(i))
	assert_eq(p.closed_why(i), "MAX")
	assert_near(float(p.bonuses()["damage"]), 0.20)


## The shelf: the nine rows of today, in order; every unbuilt row is off it and says NOT YET.
func test_the_shelf_and_why_a_row_is_shut() -> void:
	var p := _rich()
	var keys: Array = []
	for i: int in p.shelf():
		keys.append(Profile.META[i][0])
	assert_eq(keys, ["vigor", "might", "wisdom", "fortune", "novas", "luck", "redraw", "banish", "start_level"])
	for key: String in Profile.UNBUILT:
		var i := Profile.meta_index(key)
		assert_true(i >= 0, key + " is a META row")
		assert_eq(p.closed_why(i), "NOT YET")
		assert_false(p.buy(i), key + " bought off the shelf")
	assert_eq(p.crystals, 100000)
	for i: int in range(Profile.META.size()):
		assert_true(p.closed_why(i).length() <= 12)
	for g: Array in [["redraw", "WIN SEAL V"], ["banish", "WIN SEAL II"], ["start_level", "WIN SEAL VII"],
			["satchel", "WIN SEAL III"], ["favour", "WIN SEAL VI"]]:
		assert_eq(Profile.gate_why(g[0], 2), g[1])
	assert_eq(Profile.gate_why("vigor", 2), "")


## A CLEAN SLATE: pays 50, gives the active hero her spent points back and stays at level 0; none spent, refused.
func test_a_clean_slate() -> void:
	var p := Profile.new()
	p.crystals = 120
	var h := p.active_hero()
	h.level = 5
	assert_false(p.clean_slate(), "she has spent no points")
	assert_eq(p.crystals, 120)
	assert_true(h.spend_point(Loot.ST_MIGHT))
	assert_true(h.spend_point(Loot.ST_VIGOR))
	assert_true(p.clean_slate())
	assert_eq(p.crystals, 70)
	assert_eq(h.points_spent(), 0)
	assert_eq(h.points_left(), Hero.points_for(5))
	assert_eq(p.level("respec"), 0)
	assert_eq(p.next_cost(Profile.meta_index("respec")), 50, "it can be bought again")
	assert_true(h.spend_point(Loot.ST_WARD))
	assert_true(p.clean_slate())
	assert_eq(p.crystals, 20)
	assert_true(h.spend_point(Loot.ST_WARD))
	assert_false(p.clean_slate(), "too dear")
	assert_eq(h.points_spent(), 1)
	assert_false(p.buy(Profile.meta_index("respec")), "off the shelf until the shop draws it")


## A new profile: the start list, and the keys of the deeds not built yet (THE STAR, JUDGEMENT) for everyone.
func test_a_new_profile_opens_the_start_list() -> void:
	var want := START.duplicate()
	for row: Array in Profile.OPENS:
		if row[0] == "deed" and Achievements.row_of(row[1]).is_empty():
			want.append_array(row[2])
	assert_eq(_keys(Profile.new().opened()), _sorted(want))
	assert_true(Profile.new().opened().has("star"), "LEVEL_5 is not built: THE STAR is open")
	assert_true(Profile.new().opened().has("life"), "FALLS_5 is not built: JUDGEMENT is open")
	assert_false(Profile.new().opened().has("overtime"))


## Each deed row adds exactly its keys.
func test_each_deed_opens_its_keys() -> void:
	var base := Profile.new().opened()
	var want := {
		"BOSS_CHANDELIER": ["reading", "r_wands_1", "r_cups_1", "r_swords_1", "r_pent_1", "r_wands_4"],
		"EVOLVE": ["nova"],
		"TEN_MINUTES": ["KNIGHT", "w_cleave", "DWARF"],
		"BOSS_GHOSTWRITER": ["ARCHER", "w_bone", "justice"],
		"OMENS": ["PRIEST", "ORC", "w_candle", "lovers"],
		"ARCHLICH": ["PALADIN", "overtime", "daily", "r_pent_10"],
		"COMBO_200": ["r_wands_8"], "SEAL": ["r_wands_10"], "REVIVE_3": ["r_cups_2"], "BLESSED": ["r_cups_9"],
		"CURSED": ["r_swords_3"], "JACKPOT": ["r_pent_4"], "KILLS_10K": ["r_swords_7"], "KILLS_100K": ["r_pent_9"],
		"WIN_ARCHMAGE": ["r_cups_5"], "WIN_SEAL_1": ["r_swords_10"],
	}
	for api: String in want:
		assert_false(Achievements.row_of(api).is_empty(), api + " is a deed")
		var p := Profile.new()
		p.deeds[api] = true
		var extra: Array = []
		for k: String in p.opened():
			if not base.has(k):
				extra.append(k)
		extra.sort()
		assert_eq(extra, _sorted(want[api]), api)


## Each deck opens its rows once bought.
func test_each_deck_opens_its_rows() -> void:
	var base := Profile.new().opened()
	var want := {"deck_hex": ["w_hex", "devil"], "deck_blades": ["w_blades", "empress"], "deck_priestess": ["priestess"]}
	for key: String in want:
		var p := Profile.new()
		p.unlocks[key] = 1
		var extra: Array = []
		for k: String in p.opened():
			if not base.has(k):
				extra.append(k)
		extra.sort()
		assert_eq(extra, _sorted(want[key]), key)


## A saved hero's class and race are open: an old profile with a DWARF KNIGHT keeps both (nothing is stored).
func test_a_saved_hero_opens_her_class_and_race() -> void:
	var p := Profile.new()
	assert_false(p.class_open(Classes.KNIGHT))
	assert_false(p.race_open(Races.DWARF))
	assert_true(p.class_open(Classes.MAGE))
	assert_true(p.race_open(Races.ELF))
	p.add_hero(Hero.make(Races.DWARF, Classes.KNIGHT))
	assert_true(p.class_open(Classes.KNIGHT))
	assert_true(p.race_open(Races.DWARF))
	assert_false(p.class_open(Classes.ARCHER))
	assert_false(p.opened().has("w_cleave"), "her class weapon is the World's to take out of her mask")
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_true(back.class_open(Classes.KNIGHT), "a saved hero still opens her class after a load")
	assert_false(p.to_dict().has("opened"), "opened() is never stored")


## A new profile against today's catalog: the four class weapons, their arcana, THE TOWER and the evolutions
## they hold back; an evolution opens when every row it needs is open.
func test_locked_rows_of_a_new_profile() -> void:
	var p := Profile.new()
	var want: Array[int] = []
	for k: String in ["nova", "e_fire", "w_bone", "w_candle", "justice", "lovers", "e_bone", "e_candle", "w_cleave",
			"e_cleave"] + DECK_ROWS:
		want.append(_cat(k))
	want.sort()
	assert_eq(p.locked_rows(), want)
	assert_eq(p.bonuses()["locked"], want)
	p.deeds["TEN_MINUTES"] = true
	assert_false(p.locked_rows().has(_cat("w_cleave")))
	assert_false(p.locked_rows().has(_cat("e_cleave")), "WHIRLWIND: CLEAVE and STRENGTH are open")
	p.deeds["BOSS_GHOSTWRITER"] = true
	p.deeds["OMENS"] = true
	p.deeds["EVOLVE"] = true
	var decks: Array[int] = []
	for k: String in DECK_ROWS:
		decks.append(_cat(k))
	decks.sort()
	assert_eq(p.locked_rows(), decks, "only the shop's decks stay shut")


## The rows the shopkeeper's decks open (Profile.OPENS "deck"), with the evolutions that need them.
const DECK_ROWS: Array[String] = ["priestess", "empress", "devil", "w_hex", "w_blades", "e_veil", "e_hex", "e_blades"]


func _cat(k: String) -> int:
	for i: int in range(Upgrades.count()):
		if Upgrades.key(i) == k:
			return i
	return -1
