extends TestCase
## Achievements: the Steam achievement catalogue and which ones a run earns (game/logic/achievements.gd).


func test_api_names_are_unique_and_upper_case() -> void:
	var seen := {}
	for n: String in Achievements.api_names():
		assert_false(seen.has(n), "duplicate " + n)
		assert_eq(n, n.to_upper())
		seen[n] = true
	assert_eq(seen.size(), Achievements.LIST.size())


func test_a_short_lost_run_earns_nothing() -> void:
	var r := Results.new([0])
	assert_eq(Achievements.earned(r, false, 120.0), [])


func test_a_flawless_solo_win() -> void:
	var r := Results.new([0])
	r.note(905.0, Results.M_ARCHLICH, 0)
	var got: Array = Achievements.earned(r, true, 1000.0)
	for n: String in ["ARCHLICH", "SOLO_WIN", "FLAWLESS", "LICH", "TEN_MINUTES"]:
		assert_true(got.has(n), "missing " + n)
	assert_false(got.has("PARTY_WIN"))


func test_a_four_wizard_win_with_a_death_is_not_flawless() -> void:
	var r := Results.new([0, 1, 2, 3])
	r.add(2, "deaths", 1.0)
	var got: Array = Achievements.earned(r, true, 1000.0)
	assert_true(got.has("PARTY_WIN"))
	assert_false(got.has("FLAWLESS"))
	assert_false(got.has("SOLO_WIN"))


func test_a_win_with_one_raised_fall_is_not_flawless() -> void:
	var r := Results.new([0, 1])
	r.add(1, "downs", 1.0) # fell once and was raised: no life lost
	var got: Array = Achievements.earned(r, true, 1000.0)
	assert_true(got.has("ARCHLICH"))
	assert_false(got.has("FLAWLESS"))


func test_moments_earn_their_achievements() -> void:
	var r := Results.new([0, 1])
	r.note(100.0, Results.M_BLESSING, 1)
	r.note(200.0, Results.M_CHEST, 0, Loot.LEGENDARY)
	r.note(300.0, Results.M_COMBO, 0, 100)
	var got: Array = Achievements.earned(r, false, 400.0)
	assert_eq(got, ["BLESSED"], "legendary is not ultra and x100 is not x200")
	r.note(310.0, Results.M_CHEST, 1, Loot.ULTRA)
	r.note(320.0, Results.M_COMBO, 1, 200)
	r.note(330.0, Results.M_CURSE, 0)
	r.note(340.0, Results.M_JACKPOT, 0)
	r.note(350.0, Results.M_EVOLVE, 0, Upgrades.evo_entry(World.SP_FIRE))
	got = Achievements.earned(r, false, 400.0)
	for n: String in ["BLESSED", "CURSED", "JACKPOT", "ULTRA", "EVOLVE", "COMBO_200"]:
		assert_true(got.has(n), "missing " + n)


func test_platform_is_a_no_op_in_scripted_runs() -> void:
	assert_false(Platform.ready_ok)
	assert_eq(Platform.finish_run(Results.new([0]), true, 1000.0), 0)


func test_the_seal_and_the_omens() -> void:
	var r := Results.new([0])
	r.note(400.0, Results.M_EVOLVE, 0, Upgrades.evo_entry(World.SP_FIRE))
	var got: Array = Achievements.earned(r, false, Achievements.omens_survived() - 1.0)
	assert_false(got.has("SEAL"), "another evolution is not the seal")
	assert_false(got.has("OMENS"), "the last omen's minute is not over")
	r.note(500.0, Results.M_EVOLVE, 0, Upgrades.evo_entry(World.SP_RUNE))
	got = Achievements.earned(r, false, Achievements.omens_survived())
	assert_true(got.has("SEAL"))
	assert_true(got.has("OMENS"))


# ---- The Book of Deeds: the added catalogue rows and their rules ----

func _won(classes: Array, races: Array = [], seal: int = 0, seconds: float = 1000.0, ai: Array = []) -> Array:
	var slots: Array = []
	for i: int in range(classes.size()):
		slots.append(i)
	var r := Results.new(slots)
	for s: int in ai:
		r.ai[s] = true
	var rs := races if not races.is_empty() else classes.map(func(_c: Variant) -> int: return Races.HUMAN)
	return [r, Achievements.earned(r, true, seconds, {"classes": classes, "races": rs, "seal": seal})]


func test_rows_have_rewards_in_range_and_a_rule_or_a_steam_rule() -> void:
	var old: Array = ["ARCHLICH", "SOLO_WIN", "PARTY_WIN", "FLAWLESS", "LICH", "TEN_MINUTES", "BLESSED", "CURSED", "JACKPOT",
		"ULTRA", "EVOLVE", "COMBO_200", "SEAL", "OMENS"]
	for i: int in range(old.size()):
		assert_eq(Achievements.LIST[i][Achievements.C_API], old[i], "the Steam rows keep their order")
	for row: Array in Achievements.LIST:
		var c: int = row[Achievements.C_CRYSTALS]
		assert_true(c >= 5 and c <= 50, "%s pays %d" % [row[0], c])
		assert_true(old.has(row[0]) or Achievements.RULES.has(row[0]), "no rule for " + str(row[0]))
	for api: String in Achievements.RULES:
		assert_false(Achievements.row_of(api).is_empty(), "rule without a row: " + api)
	assert_true(Achievements.count() >= 40)


func test_a_win_with_each_class_earns_its_deed_and_only_its_own() -> void:
	var pairs := {Classes.MAGE: "WIN_MAGE", Classes.KNIGHT: "WIN_KNIGHT", Classes.ARCHER: "WIN_ARCHER",
		Classes.PRIEST: "WIN_PRIEST", Classes.PALADIN: "WIN_PALADIN"}
	for c: int in pairs:
		var got: Array = _won([c])[1]
		for other: int in pairs:
			assert_eq(got.has(pairs[other]), other == c, "class %d vs %s" % [c, pairs[other]])
	var r := Results.new([0])
	assert_false(Achievements.earned(r, false, 1000.0, {"classes": [Classes.MAGE]}).has("WIN_MAGE"), "a loss earns no win deed")


func test_a_win_with_each_race_earns_its_deed() -> void:
	var pairs := {Races.HUMAN: "WIN_HUMAN", Races.ELF: "WIN_ELF", Races.DWARF: "WIN_DWARF", Races.ORC: "WIN_ORC"}
	for rc: int in pairs:
		var got: Array = _won([Classes.MAGE], [rc])[1]
		for other: int in pairs:
			assert_eq(got.has(pairs[other]), other == rc, "race %d vs %s" % [rc, pairs[other]])
	assert_eq(Races.count(), pairs.size(), "a new race needs a deed")


func test_the_trinity_needs_a_tank_a_healer_and_a_ranged_hero() -> void:
	assert_true(_won([Classes.KNIGHT, Classes.PRIEST, Classes.ARCHER])[1].has("TRINITY"))
	assert_true(_won([Classes.PALADIN, Classes.PRIEST, Classes.ARCHER])[1].has("TRINITY"), "a paladin tanks")
	assert_false(_won([Classes.KNIGHT, Classes.PRIEST, Classes.MAGE])[1].has("TRINITY"), "no ranged hero")
	assert_false(_won([Classes.KNIGHT, Classes.ARCHER])[1].has("TRINITY"))
	var r := Results.new([0, 1, 2])
	assert_false(Achievements.earned(r, false, 100.0, {"classes": [1, 3, 2]}).has("TRINITY"), "lost")


func test_each_evolution_has_a_deed_and_earns_it() -> void:
	var seen := 0
	for sp: int in range(Spells.COUNT):
		if not Spells.has_evolution(sp) or sp == World.SP_RUNE:
			continue
		var api := ""
		for a: String in Achievements.RULES:
			if Achievements.RULES[a][0] == "evo" and Achievements.RULES[a][1] == sp:
				api = a
		assert_false(api.is_empty(), "no deed for the evolution of spell %d" % sp)
		assert_true(Achievements.row_of(api)[Achievements.C_DESC].to_upper().contains(str(Spells.EVOS[sp].name)),
			api + " names its evolution")
		var r := Results.new([0])
		assert_false(Achievements.earned(r, false, 10.0).has(api))
		r.note(50.0, Results.M_EVOLVE, 0, Upgrades.evo_entry(sp))
		var got: Array = Achievements.earned(r, false, 60.0)
		assert_true(got.has(api), api)
		assert_eq(got.size(), 2 + (1 if sp == World.SP_RUNE else 0), "EVOLVE and only this spell's deed")
		seen += 1
	assert_eq(seen, 8)


func test_act_bosses_earn_their_deeds() -> void:
	var r := Results.new([0])
	assert_false(Achievements.earned(r, false, 10.0).has("BOSS_CHANDELIER"))
	r.note(300.0, Results.M_ACT_BOSS, 0, Bestiary.CHANDELIER)
	var got: Array = Achievements.earned(r, false, 400.0)
	assert_true(got.has("BOSS_CHANDELIER"))
	assert_false(got.has("BOSS_GHOSTWRITER"))
	r.note(500.0, Results.M_ACT_BOSS, 0, Bestiary.GHOSTWRITER)
	assert_true(Achievements.earned(r, false, 600.0).has("BOSS_GHOSTWRITER"))


func test_seal_deeds_one_per_step() -> void:
	var apis := ["WIN_ARCHMAGE", "WIN_SEAL_1", "WIN_SEAL_2", "WIN_SEAL_3", "WIN_SEAL_4", "WIN_SEAL_5", "WIN_SEAL_6",
		"WIN_SEAL_7", "WIN_SEAL_8"]
	assert_eq(apis.size(), Seals.MAX - 1 + 1 - 0, "one deed for each of ARCHMAGE and the Seals")
	for step: int in range(1, Seals.MAX + 1):
		var got: Array = _won([Classes.MAGE], [], step)[1]
		for k: int in range(apis.size()):
			assert_eq(got.has(apis[k]), k + 1 <= step, "step %d vs %s" % [step, apis[k]])
	assert_false(_won([Classes.MAGE], [], 0)[1].has("WIN_ARCHMAGE"), "WIZARD is not ARCHMAGE")
	var r := Results.new([0])
	assert_false(Achievements.earned(r, false, 100.0, {"seal": 9}).has("WIN_SEAL_8"), "lost")


func test_revive_deeds() -> void:
	var r := Results.new([0, 1])
	r.add(0, "revives", 2.0)
	assert_false(Achievements.earned(r, false, 10.0).has("REVIVE_3"))
	r.add(1, "revives", 1.0)
	assert_true(Achievements.earned(r, false, 10.0).has("REVIVE_3"), "counted over the party")
	assert_false(Achievements.earned(r, false, 10.0, {"revives_total": 24}).has("REVIVE_25"))
	assert_true(Achievements.earned(r, false, 10.0, {"revives_total": 25}).has("REVIVE_25"))


func test_kill_hero_card_and_secret_totals() -> void:
	var r := Results.new([0])
	var cases := [["KILLS_1K", "kills_total", 1000], ["KILLS_10K", "kills_total", 10000], ["KILLS_100K", "kills_total", 100000],
		["HERO_10", "hero_level", Achievements.HERO_LEVEL], ["ALL_CARDS", "monster_cards", Cards.monster_count()],
		["ALL_SECRETS", "secrets", Secrets.count()], ["FIRST_CARD", "cards", 1]]
	for c: Array in cases:
		assert_false(Achievements.earned(r, false, 10.0, {c[1]: int(c[2]) - 1}).has(c[0]), "one short of " + c[0])
		assert_true(Achievements.earned(r, false, 10.0, {c[1]: int(c[2])}).has(c[0]), c[0])
	assert_false(Achievements.earned(r, false, 10.0).has("KILLS_1K"), "no facts, no deed")


## THE FULL DECK counts monster cards only: every monster card earns it, Seal cards add nothing to it.
func test_all_cards_counts_monster_cards_only() -> void:
	var r := Results.new([0])
	var all := {"cards": Cards.monster_count(), "monster_cards": Cards.monster_count()}
	assert_true(Achievements.earned(r, false, 10.0, all).has("ALL_CARDS"), "every monster card, no Seal card")
	var seals := {"cards": Cards.count() - 1, "monster_cards": Cards.monster_count() - 1}
	assert_false(Achievements.earned(r, false, 10.0, seals).has("ALL_CARDS"), "every Seal card does not stand in for one")
	assert_false(Achievements.earned(r, false, 10.0, {"cards": Cards.count()}).has("ALL_CARDS"), "no monster count, no deed")


func test_apprentices_deed_needs_a_win_with_a_human_and_only_apprentices() -> void:
	var yes: Array = _won([Classes.MAGE, Classes.KNIGHT, Classes.PRIEST], [], 0, 1000.0, [1, 2])
	assert_true(yes[1].has("APPRENTICES"))
	assert_false(_won([Classes.MAGE, Classes.KNIGHT, Classes.PRIEST], [], 0, 1000.0, [2])[1].has("APPRENTICES"), "a second human")
	assert_false(_won([Classes.MAGE], [], 0, 1000.0, [])[1].has("APPRENTICES"), "alone")
	var r := Results.new([0, 1])
	r.ai[1] = true
	assert_false(Achievements.earned(r, false, 1000.0).has("APPRENTICES"), "lost")


func test_fast_win_needs_four_heroes_and_under_sixteen_minutes() -> void:
	var four := [Classes.MAGE, Classes.KNIGHT, Classes.PRIEST, Classes.ARCHER]
	assert_true(_won(four, [], 0, Achievements.FAST_SECONDS - 1.0)[1].has("FAST_WIN"))
	assert_false(_won(four, [], 0, Achievements.FAST_SECONDS)[1].has("FAST_WIN"), "too slow")
	assert_false(_won(four.slice(0, 3), [], 0, 800.0)[1].has("FAST_WIN"), "three heroes")


func test_result_lines_cap_at_three_with_a_more_line() -> void:
	assert_eq(Achievements.result_lines([]), [])
	assert_eq(Achievements.result_lines(["KILLS_1K"]), ["DEED: BODY COUNT +10"])
	assert_eq(Achievements.result_lines(["KILLS_1K", "WIN_MAGE", "LICH"]).size(), 3)
	var many := Achievements.result_lines(["KILLS_1K", "WIN_MAGE", "LICH", "OMENS", "SOLO_WIN"])
	assert_eq(many.size(), 3)
	assert_eq(many[2], "+3 MORE DEEDS")
	var card := Cards.for_enemy(World.BAT)
	assert_eq(Achievements.result_lines([], [card]), ["CARD FOUND: " + Cards.card_name(card)])
	var mixed := Achievements.result_lines(["KILLS_1K", "WIN_MAGE", "LICH"], [card])
	assert_eq(mixed, ["CARD FOUND: " + Cards.card_name(card), "DEED: BODY COUNT +10", "+2 MORE DEEDS"], "a card shares the deeds' lines")
	assert_eq(Achievements.result_lines(["KILLS_1K"], [card, card, card])[2], "+2 MORE")


## The owner's numbers: ULTRA RARE (an ULTRA RARE run is about 1 in 100) pays 50, the first card 25, at the end of LIST.
func test_ultra_and_first_card_pay() -> void:
	assert_eq(Achievements.crystals_of("ULTRA"), 50)
	assert_eq(Achievements.crystals_of("FIRST_CARD"), 25)
	assert_eq(str(Achievements.LIST[-1][Achievements.C_API]), "FIRST_CARD")
	var prof := Profile.new()
	assert_false(Achievements.earned(Results.new([0]), false, 10.0, prof.deed_facts()).has("FIRST_CARD"))
	prof.add_card(Cards.for_enemy(World.BAT))
	assert_true(Achievements.earned(Results.new([0]), false, 10.0, prof.deed_facts()).has("FIRST_CARD"), "from the profile's cards")


func test_secret_flags() -> void:
	assert_true(Achievements.is_secret("WIN_SEAL_8"))
	assert_false(Achievements.is_secret("WIN_MAGE"))
	assert_false(Achievements.is_secret("NO_SUCH_DEED"))
	assert_eq(Achievements.crystals_of("NO_SUCH_DEED"), 0)


func test_an_apprentice_earns_no_class_or_race_deed() -> void:
	var rows: Array = [{"cls": Classes.MAGE, "race": Races.ELF, "ai": false},
		{"cls": Classes.KNIGHT, "race": Races.ORC, "ai": true}, {"cls": Classes.PRIEST, "race": Races.DWARF}]
	var party := Achievements.party_of(rows, 3)
	assert_eq(party.classes, [Classes.MAGE, Classes.PRIEST], "the apprentice knight was counted")
	assert_eq(party.races, [Races.ELF, Races.DWARF])
	assert_eq(party.seal, 3)
