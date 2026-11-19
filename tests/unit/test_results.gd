extends TestCase
## Results: the run record behind the results screen (game/logic/results.gd).


func test_moments_rank_by_weight_then_latest() -> void:
	var r := Results.new([0, 1])
	r.note(10.0, Results.M_COMBO, 0, 100)
	r.note(300.0, Results.M_LICH, 1)
	r.note(600.0, Results.M_LICH, 0)
	r.note(905.0, Results.M_ARCHLICH, 1)
	r.note(200.0, Results.M_EVOLVE, 0, Upgrades.evo_entry(World.SP_FIRE))
	var top: Array = r.top_moments(3)
	assert_eq(top.size(), 3)
	assert_eq(int(top[0][1]), Results.M_ARCHLICH)
	assert_eq(float(top[1][0]), 600.0, "the later Lich ranks first")
	assert_eq(float(top[2][0]), 300.0)


func test_moment_text_names_the_wizard_and_detail() -> void:
	assert_eq(Results.moment_text([0.0, Results.M_ARCHLICH, 2, 0]), "P3 SLEW THE ARCHLICH")
	assert_eq(Results.moment_text([0.0, Results.M_CHEST, 0, Loot.ULTRA]), "P1 FOUND ULTRA RARE LOOT")
	assert_eq(Results.moment_text([0.0, Results.M_COMBO, 1, 200]), "P2 CHAINED A x200 COMBO")
	var evo: int = Upgrades.evo_entry(World.SP_FIRE)
	assert_eq(Results.moment_text([0.0, Results.M_EVOLVE, 0, evo]), "P1 EVOLVED " + Upgrades.display_name(evo))


func test_awards_go_to_real_leaders() -> void:
	var r := Results.new([0, 1, 2])
	r.add(0, "damage", 900.0)
	r.add(1, "damage", 500.0)
	r.add(0, "kills", 300.0)
	r.add(1, "kills", 200.0)
	r.add(2, "bets", 40.0)
	assert_eq(r.awards(), [[0, "MVP"], [1, Results.TEAM_PLAYER], [2, "HIGH ROLLER"]],
		"the MVP also leads kills, so nobody else is called the slayer")


func test_no_award_for_nothing() -> void:
	var r := Results.new([0, 1])
	assert_eq(r.awards(), [[0, Results.TEAM_PLAYER], [1, Results.TEAM_PLAYER]])
	var solo := Results.new([0])
	assert_eq(solo.awards(), [], "a solo wizard with nothing gets no title")
	solo.add(0, "damage", 10.0)
	assert_eq(solo.awards(), [[0, "MVP"]])


func test_untouchable_needs_a_difference() -> void:
	var r := Results.new([0, 1])
	r.add(0, "damage", 10.0)
	r.add(0, "deaths", 2.0)
	assert_eq(r.awards(), [[0, "MVP"], [1, "UNTOUCHABLE"]])
	var even := Results.new([0, 1])
	even.add(0, "damage", 10.0)
	assert_eq(even.awards(), [[0, "MVP"], [1, Results.TEAM_PLAYER]], "equal deaths give no untouchable")


func test_round_trip_and_bad_data() -> void:
	var r := Results.new([0, 3])
	r.add(3, "gold", 42.0)
	r.note(61.0, Results.M_JACKPOT, 3)
	var back := Results.from_dict(r.to_dict())
	assert_eq(back.stat(3, "gold"), 42.0)
	assert_eq(back.moments, [[61.0, Results.M_JACKPOT, 3, 0]])
	var bad := Results.from_dict({"stats": {1: "x"}, "moments": [[1.0, 99, 0, 0], "y"]})
	assert_eq(bad.stat(1, "gold"), 0.0)
	assert_eq(bad.moments.size(), 0)
