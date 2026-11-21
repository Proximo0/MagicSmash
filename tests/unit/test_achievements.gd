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
