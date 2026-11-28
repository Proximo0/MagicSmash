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


func test_a_raised_fall_counts_against_untouchable() -> void:
	var r := Results.new([0, 1, 2])
	r.add(0, "damage", 10.0)
	r.add(0, "deaths", 1.0)
	r.add(1, "downs", 2.0) # fell twice and was raised both times, never lost a life
	assert_eq(r.awards(), [[0, "MVP"], [1, Results.TEAM_PLAYER], [2, "UNTOUCHABLE"]],
		"the wizard who never fell is untouchable, not the one raised twice")
	assert_near(r.stat(1, "falls"), 2.0)


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


## Use counters (docs/stage3_brief.md § 4.4): a use counts for the run and, when it names a seat, for that seat; both
## travel through to_dict / from_dict, and a damaged record counts nothing it cannot read.
func test_use_counters_count_the_run_and_the_seat() -> void:
	var r := Results.new([0, 2])
	assert_eq(r.used("quick"), 0, "a row nobody used counts 0")
	r.use("quick", 2)
	r.use("quick", 2, 3)
	r.use("quick", 0)
	r.use("seal_3")
	assert_eq(r.used("quick"), 5, "the run's count is every seat's")
	assert_eq(r.used_by(2, "quick"), 4)
	assert_eq(r.used_by(0, "quick"), 1)
	assert_eq(r.used("seal_3"), 1)
	assert_eq(r.used_by(2, "seal_3"), 0, "a use with no seat is the table's alone")
	assert_eq(r.used_by(1, "quick"), 0, "a seat that used nothing counts 0")
	var back := Results.from_dict(r.to_dict())
	assert_eq(back.used("quick"), 5)
	assert_eq(back.used_by(2, "quick"), 4)
	assert_eq(back.used_by(0, "quick"), 1)
	assert_eq(back.used("seal_3"), 1)
	# A record that went through JSON holds its seats as text; a damaged one holds anything.
	var text := Results.from_dict({"uses": {"quick": 2.0}, "uses_by": {"2": {"quick": 2.0}}})
	assert_eq(text.used("quick"), 2)
	assert_eq(text.used_by(2, "quick"), 2)
	var bad := Results.from_dict({"uses": {"quick": "x", "swift": -4, 7: 1}, "uses_by": {"z": {"quick": 1}, 1: "y", 3: {"quick": []}}})
	assert_eq(bad.used("quick"), 0, "a count that is not a number is dropped")
	assert_eq(bad.used("swift"), 0, "a count below 0 is dropped")
	assert_eq(bad.uses.size(), 0, "a key that is not text is dropped")
	assert_eq(bad.uses_by.size(), 0, "a seat that is not a number, and a row that is not a table, are dropped")
	assert_eq(Results.from_dict({}).used("quick"), 0, "an old record has no counters")


## Damage by spell per wizard: kept per slot and source, and it travels through to_dict / from_dict.
func test_damage_by_spell_per_wizard() -> void:
	var r := Results.new([0, 1])
	r.add_slot_source(0, World.SP_FIRE, 10.0)
	r.add_slot_source(0, World.SP_FIRE, 5.0)
	r.add_slot_source(0, Results.SRC_NOVA, 3.0)
	r.add_slot_source(1, World.SP_ARCANE, 7.0)
	var back := Results.from_dict(r.to_dict())
	assert_eq(float(back.slot_source_damage[0][World.SP_FIRE]), 15.0)
	assert_eq(float(back.slot_source_damage[0][Results.SRC_NOVA]), 3.0)
	assert_eq(float(back.slot_source_damage[1][World.SP_ARCANE]), 7.0)
	assert_false((back.slot_source_damage[1] as Dictionary).has(World.SP_FIRE))


## World records each wizard's damage under the spell that dealt it.
func test_world_records_damage_by_spell_per_wizard() -> void:
	var w := World.new([0, 1], 3)
	var e: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(100, 100))
	w.stat_src = World.SP_FROST
	w._damage_enemy(e, 2.0, 1, Vector2.ZERO)
	assert_true(float(w.record.slot_source_damage[1][World.SP_FROST]) > 0.0)
	assert_false(w.record.slot_source_damage.has(0))


func test_damage_rows_order_ties_and_cut() -> void:
	var r := Results.new([0, 1])
	r.add_slot_source(0, World.SP_FIRE, 300.0)
	r.add_slot_source(0, World.SP_FROST, 300.0)
	r.add_slot_source(0, World.SP_ARCANE, 300.0)
	r.add_slot_source(0, Results.SRC_NOVA, 500.0)
	r.add_slot_source(0, Results.SRC_ORBIT, 5.0) # 0.4%: under the cut
	var rows: Array = r.damage_rows(0)
	assert_eq(rows.size(), 4, "the tiny source is left out")
	assert_eq(int(rows[0][0]), Results.SRC_NOVA, "most damage first")
	assert_eq([int(rows[1][0]), int(rows[2][0]), int(rows[3][0])], [World.SP_ARCANE, World.SP_FIRE, World.SP_FROST], "ties: lower source first")
	assert_eq(int(rows[0][2]), 35)
	var sum := 0
	for row: Array in rows:
		sum += int(row[2])
	assert_true(sum <= 100, "shares add up to at most 100")


func test_damage_rows_limit_and_nothing_dealt() -> void:
	var r := Results.new([0, 1])
	for sp: int in range(Results.DAMAGE_ROWS + 2):
		r.add_slot_source(0, sp, 100.0)
	assert_eq(r.damage_rows(0).size(), Results.DAMAGE_ROWS)
	assert_eq(r.damage_rows(0, 2).size(), 2)
	assert_true(r.damage_rows(1).is_empty(), "a wizard who dealt nothing")
	assert_true(r.damage_rows(7).is_empty(), "no such wizard")
	r.add_slot_source(1, World.SP_FIRE, 0.0)
	assert_true(r.damage_rows(1).is_empty(), "zero damage is no row")


func test_damage_rows_survive_the_wire() -> void:
	var r := Results.new([0])
	r.add_slot_source(0, World.SP_FIRE, 70.0)
	r.add_slot_source(0, Results.SRC_ORBIT, 30.0)
	assert_eq(Results.from_dict(r.to_dict()).damage_rows(0), r.damage_rows(0))


func test_source_names() -> void:
	assert_eq(Results.source_name(Results.SRC_NOVA, Classes.KNIGHT), "NOVA")
	assert_eq(Results.source_name(Results.SRC_JUSTICE, Classes.KNIGHT), "JUSTICE")
	var cls := Classes.KNIGHT
	assert_eq(Results.source_name(Classes.weapon(cls), cls), Classes.weapon_name(cls), "the class weapon by its class name")
	assert_eq(Results.source_name(World.SP_FIRE, cls), Spells.spell_name(World.SP_FIRE))
	assert_eq(Results.source_name(999, cls), "OTHER")


## The results screen's climb line: under the deeds of a lost run with no win yet, within the deed lines' budget.
func test_the_climb_hint_fits_the_deed_lines() -> void:
	assert_eq(ArenaResultsView.foot_lines([], false), [] as Array[String])
	assert_eq(ArenaResultsView.foot_lines([], true), [ArenaResultsView.CLIMB_HINT] as Array[String])
	var many: Array = []
	for row: Array in Achievements.LIST.slice(0, Achievements.RESULT_LINES + 2):
		many.append(str(row[Achievements.C_API]))
	var lines := ArenaResultsView.foot_lines(many, true)
	assert_eq(lines.size(), Achievements.RESULT_LINES)
	assert_eq(lines[-1], ArenaResultsView.CLIMB_HINT)
	assert_eq(lines[-2], "+%d MORE DEEDS" % (many.size() - Achievements.RESULT_LINES + 2))
	assert_true(PixelFont.text_width(ArenaResultsView.CLIMB_HINT, 1) <= 470, "the climb line is wider than the screen")
	var with_card := ArenaResultsView.foot_lines(many, true, [0])
	assert_eq(with_card.size(), Achievements.RESULT_LINES)
	assert_eq(with_card[0], "CARD FOUND: %s" % Cards.card_name(0))
	assert_eq(with_card[1], "+%d MORE DEEDS" % many.size())
	assert_eq(ArenaResultsView.foot_lines([], true, [0]), ["CARD FOUND: %s" % Cards.card_name(0), ArenaResultsView.CLIMB_HINT] as Array[String])
