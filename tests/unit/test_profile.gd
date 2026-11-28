extends TestCase
## Profile: crystals, meta unlocks and the saved form (game/logic/profile.gd), and the Save autoload's rules.


## The rows that have no effect in a run: the satchel (pockets on the profile), a clean slate and the three decks.
const NO_RUN_EFFECT := ["satchel", "respec", "deck_hex", "deck_blades", "deck_priestess"]


func test_meta_rows_match_effects() -> void:
	for i: int in range(Profile.META.size()):
		var key: String = Profile.META[i][0]
		assert_true(Profile.EFFECTS.has(key) != NO_RUN_EFFECT.has(key), key + ": an effect, or named as having none")
		assert_true(Profile.max_level(i) >= 1)
		var costs: Array = Profile.META[i][3]
		for k: int in range(1, costs.size()):
			assert_true(int(costs[k]) > int(costs[k - 1]), key + " costs must rise")
		# One unlock row: a name of at most 19 letters (113 px), a description of at most 33 (200 px).
		assert_true(str(Profile.META[i][1]).length() <= 19, key + " name too long")
		assert_true(PixelFont.text_width(Profile.META[i][1], 1) <= 113, key + " name too wide")
		assert_true(str(Profile.META[i][2]).length() <= 33, key + " description too long")
		assert_true(PixelFont.text_width(Profile.META[i][2], 1) <= 200, key + " description too wide")


## CL § 45: the fifteen rows in order with their names and prices; the fourteen that stay bought cost 6,170.
func test_the_shop_rows_and_prices() -> void:
	var want := [
		["vigor", "WARDED ROBES", [40, 160]],
		["might", "RUNED STAFF", [30, 70, 150, 300, 600]],
		["wisdom", "FORBIDDEN LORE", [30, 80, 200]],
		["fortune", "MIDAS' PURSE", [20, 60, 150]],
		["novas", "BOTTLED STAR", [40, 140]],
		["luck", "FOUR-LEAF RUNE", [80, 240]],
		["redraw", "THE SECOND GLANCE", [60, 220]],
		["banish", "THE BLACK RIBBON", [60, 220]],
		["start_level", "THE HEAD START", [120, 400]],
		["satchel", "THE SATCHEL", [300, 900]],
		["favour", "THE READER'S FAVOUR", [250, 750]],
		["respec", "A CLEAN SLATE", [50]],
		["deck_hex", "THE WITCH'S DECK", [150]],
		["deck_blades", "THE DUELLIST'S DECK", [150]],
		["deck_priestess", "THE VEILED DECK", [200]],
	]
	assert_eq(Profile.META.size(), want.size())
	var kept := 0
	for i: int in range(want.size()):
		var row: Array = Profile.META[i]
		assert_eq([row[0], row[1], row[3]], want[i])
		if row[0] != "respec":
			for c: int in row[3]:
				kept += c
	assert_eq(kept, 6170, "the fourteen rows that stay bought")
	assert_near(float(Profile.EFFECTS["might"][1]), 0.04)
	assert_eq(Profile.EFFECTS["redraw"], ["redraws", 1.0])
	assert_eq(Profile.EFFECTS["banish"], ["banishes", 1.0])
	assert_eq(Profile.EFFECTS["start_level"], ["start_level", 1.0])
	assert_eq(Profile.EFFECTS["favour"], ["favour", 1.0])


func test_buy_spends_crystals_up_to_max() -> void:
	var p := Profile.new()
	var i: int = Profile.meta_index("vigor")
	assert_false(p.buy(i), "bought with no crystals")
	p.crystals = 1000
	var spent: int = 0
	for _k: int in range(Profile.max_level(i)):
		spent += p.next_cost(i)
		assert_true(p.buy(i))
	assert_eq(p.next_cost(i), -1)
	assert_false(p.buy(i), "bought past max")
	assert_eq(p.crystals, 1000 - spent)
	assert_near(float(p.bonuses()["hearts"]), float(Profile.max_level(i)))


func test_runs_earn_crystals() -> void:
	var p := Profile.new()
	var earned: int = p.finish_run({"score": 12345, "seconds": 300.0, "kills": 600, "liches": 1})
	assert_eq(earned, 10 + 2 + Profile.CRYSTAL_LICH)
	assert_eq(p.crystals, earned)
	assert_eq(p.high_score, 12345)
	p.finish_run({"score": 10, "seconds": 20.0})
	assert_eq(p.high_score, 12345, "a worse run keeps the best score")
	assert_eq(p.runs, 2)
	assert_eq(p.wins, 0)


func test_a_won_run_pays_the_win_bonus_and_counts() -> void:
	var p := Profile.new()
	var earned: int = p.finish_run({"score": 1, "won": true})
	assert_eq(earned, Profile.CRYSTAL_WIN)
	assert_eq(p.wins, 1)
	assert_eq(Profile.from_dict(p.to_dict()).wins, 1)


func test_round_trip_and_bad_data() -> void:
	var p := Profile.new()
	p.crystals = 77
	p.unlocks = {"might": 2}
	var q := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(q.crystals, 77)
	assert_eq(q.level("might"), 2)
	var bad := Profile.from_dict({"crystals": -5, "unlocks": {"might": 99, "nonsense": 3}})
	assert_eq(bad.crystals, 0)
	assert_eq(bad.level("might"), Profile.max_level(Profile.meta_index("might")))
	assert_false(bad.unlocks.has("nonsense"))


func test_scripted_runs_never_write_or_get_unlocks() -> void:
	assert_true(Flags.is_scripted_run(), "unit tests are a scripted run")
	assert_false(Save.write(), "Save wrote player data in a scripted run")
	assert_true(Save.run_bonuses().is_empty())


func test_world_applies_meta_bonuses() -> void:
	var w := World.new([0, 1], 3)
	w.apply_meta({"hearts": 2.0, "novas": 1.0, "damage": 0.1, "luck": 1.0})
	for s: int in [0, 1]:
		var p: World.Player = w.players[s]
		assert_eq(p.max_hp, World.BASE_HEARTS + 2)
		assert_eq(p.hp, p.max_hp)
		assert_eq(p.bombs, 3)
	var e: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(100, 100))
	w._damage_enemy(e, 1.0, 0, Vector2.ZERO)
	assert_near(e.maxhp - e.hp, 1.1, 0.0001)


func test_cards_collect_socket_and_save() -> void:
	var p := Profile.new()
	assert_false(p.socket_card(World.ORC), "socketed a card not owned")
	assert_true(p.add_card(World.ORC), "first orc card is not new")
	assert_false(p.add_card(World.ORC), "second orc card counted as new")
	assert_eq(p.card_count(World.ORC), 2)
	assert_eq(p.cards_owned(), 1)
	assert_true(p.socket_card(World.ORC))
	assert_eq(p.socket_indices(), [-1, -1, World.ORC] as Array[int])
	assert_near(float(Cards.socket_stats(p.socket_indices())[Loot.ST_MIGHT]), 0.10)
	assert_false(p.bonuses().has("armor"), "cards reach a run only through their hero")
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(back.card_count(World.ORC), 2)
	assert_eq(back.socket_indices(), [-1, -1, World.ORC] as Array[int])
	p.unsocket(Cards.STAFF)
	assert_eq(p.socket_indices(), [-1, -1, -1] as Array[int])


func test_saved_sockets_drop_cards_not_owned_or_misplaced() -> void:
	var d := {"cards": {"orc": 1, "bogus": 3}, "sockets": ["orc", "bat", "orc"]}
	var p := Profile.from_dict(d)
	assert_eq(p.card_count(World.ORC), 1)
	assert_eq(p.cards_owned(), 1)
	assert_eq(p.socket_indices(), [-1, -1, World.ORC] as Array[int])


func test_secrets_pots_and_spending_save() -> void:
	var p := Profile.new()
	assert_true(p.find_secret("alcove"))
	assert_false(p.find_secret("alcove"))
	assert_eq(p.pots_mask_now(), 0)
	p.break_pot(3)
	assert_eq(p.pots_mask_now(), 8)
	p.crystals = 5
	assert_false(p.spend(6))
	assert_true(p.spend(5))
	assert_eq(p.crystals, 0)
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_true(back.has_secret("alcove"))
	assert_eq(back.pots_mask_now(), 8)
	back.finish_run({"score": 10, "seconds": 30.0})
	assert_eq(back.pots_mask_now(), 0, "pots did not refill after a run")


func test_breaking_a_pot_in_a_new_run_drops_the_old_runs_bits() -> void:
	var p := Profile.new()
	p.break_pot(3)
	p.finish_run({"score": 10, "seconds": 30.0})
	assert_eq(p.pots_mask_now(), 0)
	p.break_pot(1)
	assert_eq(p.pots_mask_now(), 2, "a pot from an earlier run stayed broken")


func test_bounties_scale_with_the_step_and_losing_pays_nothing_extra() -> void:
	var a := Profile.new()
	var b := Profile.new()
	var lost := {"seconds": 120.0, "kills": 500}
	assert_eq(b.finish_run(lost.merged({"seal": 9})), a.finish_run(lost), "a fast loss pays the same at any step")
	var won := {"seconds": 960.0, "kills": 3000, "liches": 4, "won": true}
	var at0 := Profile.new().finish_run(won)
	var at5 := Profile.new()
	var paid := at5.finish_run(won.merged({"seal": 5}))
	var bounty := 4 * Profile.CRYSTAL_LICH + Profile.CRYSTAL_WIN
	assert_eq(paid, at0 + roundi(bounty * Seals.crystal_mul(5)) - bounty + Seals.prize(5))
	assert_eq(at5.last_pay.prize, Seals.prize(5))
	assert_eq(at5.last_pay.card, Seals.card(5))
	assert_eq(Profile.new().finish_run(won.merged({"seal": -1})), at0 - bounty + roundi(bounty * 0.5), "APPRENTICE halves")


func test_prizes_pay_once_per_profile_and_step() -> void:
	var p := Profile.new()
	var won := {"won": true, "seal": 3}
	var first := p.finish_run(won)
	assert_eq(p.card_count(Seals.card(3)), 1, "the first win pays the Seal card")
	assert_eq(p.prize_left(3), 0)
	var second := p.finish_run(won)
	assert_eq(first - second, Seals.prize(3), "the prize pays once")
	assert_eq(p.card_count(Seals.card(3)), 1)
	assert_eq(p.last_pay.prize, 0)
	var q := Profile.from_dict(p.to_dict())
	assert_eq(q.finish_run(won), second, "a reloaded profile remembers the prize")
	assert_eq(Profile.new().finish_run({"won": true, "seal": 0}), Profile.CRYSTAL_WIN, "WIZARD pays no prize")
	assert_eq(Profile.new().prize_left(1), 50)


## An Archlich's drop picked up during the run: the first win still names the card on the results line.
func test_a_first_win_names_the_seal_card_already_owned() -> void:
	var p := Profile.new()
	p.cards[Cards.key(Seals.card(3))] = 1
	p.finish_run({"won": true, "seal": 3})
	assert_eq(p.last_pay.card, Seals.card(3))
	assert_eq(p.card_count(Seals.card(3)), 1, "not paid twice")
	assert_true(Seals.pay_line(p.last_pay).contains(" CARD"))
	p.finish_run({"won": true, "seal": 3})
	assert_eq(p.last_pay.card, -1, "a second win names none")


## A stale Net.seal (another host's lobby) falls back to an open step; open steps and APPRENTICE stay.
func test_playable_seal_falls_back_from_a_locked_step() -> void:
	var p := Profile.new()
	assert_eq(p.playable_seal(9), Seals.START_UNLOCKED, "stale locked value falls back to the highest open step")
	assert_eq(p.playable_seal(1), 1, "open value kept")
	assert_eq(p.playable_seal(0), 0)
	assert_eq(p.playable_seal(Seals.MIN), Seals.MIN, "APPRENTICE kept")
	assert_eq(p.playable_seal(-5), 0, "below the ladder: WIZARD")
	p.seal_unlocked = 4
	assert_eq(p.playable_seal(9), 4)
	assert_eq(p.playable_seal(3), 3)


func test_wins_unlock_the_ladder_in_order() -> void:
	var p := Profile.new()
	for level: int in range(Seals.MIN, Seals.MAX + 1):
		assert_eq(p.seal_open(level), level <= 1, "a new profile opens APPRENTICE to ARCHMAGE: %d" % level)
	p.finish_run({"won": false, "seal": 1})
	assert_false(p.seal_open(2), "a loss opens nothing")
	p.finish_run({"won": true, "seal": -1})
	assert_false(p.seal_open(2), "winning lower opens nothing new")
	p.finish_run({"won": true, "seal": 1})
	assert_true(p.seal_open(2))
	assert_false(p.seal_open(3))
	assert_eq(p.seal_best, 1)
	p.finish_run({"won": true, "seal": 9})
	assert_eq(p.seal_unlocked, Seals.MAX)
	assert_eq(p.seal_best, 9)
	var q := Profile.from_dict(p.to_dict())
	assert_eq(q.seal_unlocked, Seals.MAX)
	assert_eq(q.seal_best, 9)


func test_kills_and_revives_add_up() -> void:
	var p := Profile.new()
	var res := Results.new([0, 1])
	res.add(0, "revives", 2)
	res.add(1, "revives", 1)
	p.finish_run({"kills": 300, "results": res})
	p.finish_run({"kills": 200, "revives": 4})
	assert_eq(p.kills_total, 500)
	assert_eq(p.revives_total, 7)
	var q := Profile.from_dict(p.to_dict())
	assert_eq(q.kills_total, 500)
	assert_eq(q.revives_total, 7)


## A profile saved before the ladder (this exact dictionary, as JSON gives it back) loads as it did, with the
## ladder at its start.
func test_an_old_profile_loads_unchanged() -> void:
	var old: Variant = JSON.parse_string('{"version": 1, "high_score": 4321, "crystals": 77, "runs": 9, "wins": 2, ' +
		'"best_time": 812.5, "unlocks": {"vigor": 1, "luck": 2}, "cards": {"orc": 2, "lich": 1}, ' +
		'"sockets": ["", "", "orc"], "secrets": ["moon"], "pots_run": 9, "pots_mask": 3, "wishes": 5}')
	var p := Profile.from_dict(old)
	assert_eq(p.high_score, 4321)
	assert_eq(p.crystals, 77)
	assert_eq(p.runs, 9)
	assert_eq(p.wins, 2)
	assert_eq(p.level("luck"), 2)
	assert_eq(p.card_count(World.ORC), 2)
	assert_eq(p.sockets[2], "orc")
	assert_true(p.has_secret("moon"))
	assert_eq(p.wishes, 5)
	assert_eq(p.seal_unlocked, Seals.START_UNLOCKED)
	assert_eq(p.seal_best, Seals.MIN - 1)
	assert_true(p.seal_prizes.is_empty())
	assert_eq(p.kills_total, 0)
	assert_eq(p.revives_total, 0)
	var back: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	for k: String in old:
		if k != "version":
			assert_eq(back[k], old[k], k)
	var bad := Profile.from_dict({"seal_unlocked": 99, "seal_best": -50, "seal_prizes": ["3", "x", 77]})
	assert_eq(bad.seal_unlocked, Seals.MAX)
	assert_eq(bad.seal_best, Seals.MIN - 1)
	assert_eq(bad.seal_prizes.keys(), ["3"])


## Version 2: a version 1 save becomes one HUMAN MAGE holding its sockets, and nothing else it held is lost.
func test_a_version_1_profile_becomes_one_human_mage() -> void:
	var old: Variant = JSON.parse_string('{"version": 1, "high_score": 4321, "crystals": 77, "runs": 9, "wins": 2, ' +
		'"best_time": 812.5, "unlocks": {"vigor": 1, "luck": 2}, "cards": {"orc": 2, "bat": 1}, ' +
		'"sockets": ["bat", "", "orc"], "secrets": ["moon"], "pots_run": 9, "pots_mask": 3, "wishes": 5, ' +
		'"seal_unlocked": 3, "seal_best": 2, "seal_prizes": ["1", "2"], "kills_total": 900, "revives_total": 4}')
	var p := Profile.from_dict(old)
	assert_eq(p.heroes.size(), 1)
	var h: Hero = p.heroes[0]
	assert_eq([h.race, h.cls, h.school, h.level], [Races.HUMAN, Classes.MAGE, 0, 1])
	assert_eq(h.sockets, ["bat", "", "orc"] as Array[String], "the old sockets")
	assert_eq(p.active_hero(), h)
	assert_eq(p.socket_indices(), [Cards.index_of("bat"), -1, World.ORC] as Array[int])
	var back: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	assert_eq(int(back["version"]), Profile.VERSION)
	assert_eq(Profile.VERSION, 2)
	for k: String in old:
		if k != "version":
			assert_eq(back[k], old[k], k)
	assert_eq((back["heroes"] as Array).size(), 1)


func test_heroes_round_trip_and_keep_their_own_sockets() -> void:
	var p := Profile.new()
	assert_eq(p.heroes.size(), 1, "a new profile has its first hero")
	p.add_card(World.ORC)
	p.add_card(Cards.index_of("bat"))
	assert_true(p.socket_card(World.ORC))
	var k := Hero.make(Races.ORC, Classes.KNIGHT, 0, "grok")
	k.add_xp(300)
	k.spend_point(Loot.ST_MIGHT)
	assert_true(p.add_hero(k))
	assert_eq(p.hero, 1, "a new hero is the active one")
	assert_eq(p.socket_indices(), [-1, -1, -1] as Array[int], "each hero has its own sockets")
	assert_true(p.socket_card(Cards.index_of("bat")))
	assert_near(float(Cards.socket_stats(p.socket_indices())[Loot.ST_SWIFT]), 0.10, 0.0001, "the active hero's cards")
	assert_eq(p.socket_indices(), [Cards.index_of("bat"), -1, -1] as Array[int])
	var q := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(q.heroes.size(), 2)
	assert_eq(q.hero, 1)
	assert_eq((q.heroes[0] as Hero).to_dict(), (p.heroes[0] as Hero).to_dict())
	assert_eq((q.heroes[1] as Hero).to_dict(), k.to_dict())
	assert_eq(q.active_hero().name, "GROK")
	assert_eq(q.socket_indices(), [Cards.index_of("bat"), -1, -1] as Array[int])


func test_at_most_eight_heroes_and_never_none() -> void:
	var p := Profile.new()
	for i: int in range(Profile.MAX_HEROES - 1):
		assert_true(p.add_hero(Hero.make(Races.ELF, i % Classes.count())))
	assert_false(p.add_hero(Hero.new()), "a ninth hero")
	var d := p.to_dict()
	(d["heroes"] as Array).append(Hero.new().to_dict())
	assert_eq(Profile.from_dict(d).heroes.size(), Profile.MAX_HEROES, "a hand-edited ninth is dropped")
	p.hero = 3
	assert_true(p.remove_hero(1))
	assert_eq(p.hero, 2, "the active hero is still the same one")
	assert_false(p.remove_hero(99))
	while p.heroes.size() > 1:
		assert_true(p.remove_hero(0))
	assert_false(p.remove_hero(0), "the last hero stays")
	assert_eq(p.hero, 0)


func test_saved_heroes_drop_cards_not_owned() -> void:
	var d := {"cards": {"orc": 1}, "hero": 7, "heroes": [{"race": "elf", "cls": "archer", "sockets": ["", "", "orc"]},
		{"race": "orc", "cls": "priest", "sockets": ["bat", "", ""]}, "junk"]}
	var p := Profile.from_dict(d)
	assert_eq(p.heroes.size(), 2)
	assert_eq(p.hero, 1, "clamped")
	assert_eq((p.heroes[0] as Hero).sockets[2], "orc")
	assert_eq((p.heroes[1] as Hero).sockets[0], "", "the bat card is not owned")
	assert_eq((p.heroes[1] as Hero).cls, Classes.PRIEST)


func test_finish_run_pays_class_xp_once_per_hero() -> void:
	var p := Profile.new()
	var want: int = p.heroes[0].run_xp(300.0, 1, true, 1.0)
	assert_true(want > 0)
	p.finish_run({"seconds": 300.0, "liches": 1, "won": true, "heroes": [0, 0]})
	var q := Profile.new()
	var h: Hero = q.heroes[0]
	var gained := h.add_xp(want)
	assert_eq(p.heroes[0].level, h.level, "once, not twice")
	assert_eq(p.heroes[0].xp, h.xp)
	assert_eq(int(p.last_hero_levels[0]), gained)


func test_finish_run_without_or_with_bad_hero_indices_pays_nothing() -> void:
	var p := Profile.new()
	p.finish_run({"seconds": 600.0, "liches": 1, "won": true})
	assert_eq(p.heroes[0].xp, 0)
	assert_eq(p.heroes[0].level, 1)
	p.finish_run({"seconds": 600.0, "won": true, "heroes": [5, -1]})
	assert_eq(p.heroes[0].xp, 0)
	assert_true(p.last_hero_levels.is_empty())


# ---- The Book of Deeds ----

func _record(won: bool = true) -> Results:
	var r := Results.new([0])
	r.note(900.0, Results.M_ARCHLICH, 0)
	return r


func test_a_new_and_an_old_profile_have_no_deeds() -> void:
	assert_true(Profile.new().deeds.is_empty())
	assert_true(Profile.from_dict({"runs": 3}).deeds.is_empty(), "an old save")
	assert_eq(Profile.new().deeds_earned(), 0)


func test_finish_run_books_deeds_and_pays_them_once() -> void:
	var p := Profile.new()
	var run := {"score": 1, "seconds": 1000.0, "won": true, "results": _record(), "party": {"classes": [Classes.MAGE], "races": [Races.HUMAN]}}
	var before := p.crystals
	var paid := p.finish_run(run)
	var deeds_pay := int(p.last_pay.deeds_pay)
	assert_true(deeds_pay > 0)
	assert_eq(p.crystals, before + paid + deeds_pay, "deed crystals go to the balance, not the run's return")
	for api: String in ["ARCHLICH", "SOLO_WIN", "WIN_MAGE", "WIN_HUMAN"]:
		assert_true(p.has_deed(api), api)
		assert_true((p.last_pay.deeds as Array).has(api), api)
	var sum := 0
	for api: Variant in p.last_pay.deeds:
		sum += Achievements.crystals_of(str(api))
	assert_eq(sum, deeds_pay)
	# The same run again: nothing new, nothing paid.
	before = p.crystals
	paid = p.finish_run(run)
	assert_eq(p.last_pay.deeds, [])
	assert_eq(p.last_pay.deeds_pay, 0)
	assert_eq(p.crystals, before + paid)


func test_a_run_without_a_record_earns_no_deeds() -> void:
	var p := Profile.new()
	p.finish_run({"score": 1, "seconds": 1000.0, "won": true})
	assert_true(p.deeds.is_empty())
	assert_eq(p.last_pay.deeds, [])


func test_totals_deeds_use_the_profile() -> void:
	var p := Profile.new()
	p.kills_total = 995
	p.finish_run({"kills": 10, "seconds": 5.0, "results": Results.new([0])})
	assert_true(p.has_deed("KILLS_1K"))
	assert_false(p.has_deed("KILLS_10K"))
	var f := p.deed_facts()
	assert_eq(f.kills_total, 1005)
	assert_eq(f.hero_level, 1)
	assert_eq(f.cards, 0)
	assert_eq(f.secrets, 0)


func test_deeds_round_trip_and_unknown_names_stay() -> void:
	var p := Profile.new()
	p.deeds["SOLO_WIN"] = true
	p.deeds["FROM_A_NEWER_BUILD"] = true
	var q := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_true(q.has_deed("SOLO_WIN"))
	assert_true(q.has_deed("FROM_A_NEWER_BUILD"), "kept, not dropped")
	assert_eq(q.deeds.keys(), ["SOLO_WIN", "FROM_A_NEWER_BUILD"])
	assert_eq(q.deeds_earned(), 1, "the count is of the catalogue only")
	assert_true(q.to_dict().deeds is Array)


func test_removing_a_hero_moves_the_held_indices() -> void:
	assert_eq(Profile.index_after_removal(3, 1), 2, "above the removed one shifts down")
	assert_eq(Profile.index_after_removal(0, 1), 0, "below stays")
	assert_eq(Profile.index_after_removal(1, 1), -1, "the removed one is gone")
	assert_eq(Profile.index_after_removal(-1, 1), -1, "a guest stays a guest")


func test_removing_hero_keeps_the_active_hero_right() -> void:
	var p := Profile.new()
	p.heroes.clear()
	for nm: String in ["A", "B", "C", "D"]:
		p.add_hero(Hero.make(Races.HUMAN, Classes.KNIGHT, 0, nm))
	p.hero = 2
	assert_true(p.remove_hero(0))
	assert_eq(p.active_hero().name, "C", "a hero below the active one went")
	assert_true(p.remove_hero(p.hero))
	assert_eq(p.active_hero().name, "D", "the active one went: the next takes her place")
	assert_true(p.remove_hero(p.hero))
	assert_eq(p.active_hero().name, "B", "the last active one went: the one before")


func test_first_visit_is_told_once_across_a_reload() -> void:
	var p := Profile.new()
	var key := Profile.first_key(Talk.SHOPKEEPER)
	assert_true(p.first_time(key))
	assert_false(p.first_time(key), "a second visit")
	var q := Profile.from_dict(p.to_dict())
	assert_false(q.first_time(key), "a second visit after a reload")
	assert_true(q.first_time(Profile.first_key(Talk.MORVANE)), "another speaker is still new")
	assert_true(Profile.from_dict({}).talked.is_empty(), "an old save has none")


func test_run_gain_adds_the_deeds_pay() -> void:
	var p := Profile.new()
	p.last_pay = {"deeds_pay": 30}
	assert_eq(p.run_gain(100), 130)
	p.last_pay = {}
	assert_eq(p.run_gain(100), 100, "no deeds booked")


## The real chain a run takes (Arena: apply_meta(bonuses) for every seat, then apply_hero per seat): a socketed
## +1 HEART card gives its own hero exactly +1 heart and the other seat none.
func test_a_socketed_card_counts_once_and_only_for_its_hero() -> void:
	var ooze := Cards.index_of("slime")
	var p := Profile.new()
	assert_true(p.add_card(ooze))
	assert_true(p.socket_card(ooze))
	var other := Hero.make(Races.HUMAN, Classes.MAGE, 0, "other")
	assert_true(p.add_hero(other))
	p.hero = 0
	var bare := World.new([0, 1], 3, Tuning.new())
	bare.apply_hero(bare.players[0], Hero.make(Races.HUMAN, Classes.MAGE).to_dict())
	bare.apply_hero(bare.players[1], other.to_dict())
	var w := World.new([0, 1], 3, Tuning.new())
	w.apply_meta(p.bonuses())
	w.apply_hero(w.players[0], (p.heroes[0] as Hero).to_dict())
	w.apply_hero(w.players[1], (p.heroes[1] as Hero).to_dict())
	var p0: World.Player = w.players[0]
	var p1: World.Player = w.players[1]
	assert_eq(p0.max_hp, (bare.players[0] as World.Player).max_hp + 1, "the card's own hero: +1 heart")
	assert_eq(p1.max_hp, (bare.players[1] as World.Player).max_hp, "the other seat: no card heart")


## ALL_CARDS reads "monster_cards" (Achievements' "cards" rule): every monster card, the Seal cards left out.
func test_deed_facts_count_monster_cards_apart_from_seal_cards() -> void:
	var p := Profile.new()
	var seal_cards := 0
	for i: int in range(Cards.count()):
		if Cards.enemy(i) < 0:
			assert_true(p.add_card(i))
			seal_cards += 1
	assert_true(seal_cards > 0, "the deck has no Seal card to test with")
	assert_eq(int(p.deed_facts().monster_cards), 0, "Seal cards counted as monster cards")
	assert_eq(int(p.deed_facts().cards), seal_cards)
	for i: int in range(Cards.count()):
		if Cards.enemy(i) >= 0:
			assert_true(p.add_card(i))
	assert_eq(int(p.deed_facts().monster_cards), Cards.monster_count())
	assert_eq(p.monster_cards_owned(), Cards.monster_count())
	assert_eq(int(p.deed_facts().cards), Cards.count())


## The whole chain: a run booked on a profile that holds every monster card (and no Seal card) earns ALL_CARDS.
func test_a_run_with_every_monster_card_earns_all_cards() -> void:
	var p := Profile.new()
	for i: int in range(Cards.count()):
		if Cards.enemy(i) >= 0:
			assert_true(p.add_card(i))
	p.finish_run({"score": 10, "seconds": 30.0, "results": Results.new()})
	assert_true(p.deeds.has("ALL_CARDS"), "every monster card is owned, the deed is not")



## The lifetime urn count (Profile.urns) and the urn card it brings (bonuses' "urn_card", Profile.URN_CARD_AFTER).
func test_urns_add_up_over_runs_and_send_the_urn_card() -> void:
	var p := Profile.new()
	p.urns = Profile.URN_CARD_AFTER - 1
	assert_false(bool(p.bonuses().get("urn_card", true)))
	p.urns = Profile.URN_CARD_AFTER
	assert_true(bool(p.bonuses().get("urn_card", false)))
	assert_true(p.find_secret("urn_card"))
	assert_false(bool(p.bonuses().get("urn_card", true)), "the secret is found")
	var q := Profile.new()
	q.finish_run({"score": 1, "seconds": 10.0, "urns": 5})
	assert_eq(q.urns, 5)
	q.finish_run({"score": 1, "seconds": 10.0, "urns": -9})
	assert_eq(q.urns, 5, "a negative count took urns away")
	q.finish_run({"score": 1, "seconds": 10.0})
	assert_eq(q.urns, 5, "a run with no count")


func test_urns_survive_a_save_and_a_wrong_type_is_damage() -> void:
	var p := Profile.new()
	p.urns = 77
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(back.urns, 77)
	assert_eq(Profile.from_dict({"runs": 2}).urns, 0, "an old save has no urns")
	assert_eq(Profile.from_dict({"urns": -4}).urns, 0)
	assert_true(Profile.NUMBER_KEYS.has("urns"))
	assert_false(Profile.profile_types_ok({"urns": []}))
	assert_eq(Profile.from_dict({"urns": {}}), null, "a damaged urn count loaded")
	assert_eq(Profile.from_dict({"kills_total": {}}), null, "the other number keys behave the same")
