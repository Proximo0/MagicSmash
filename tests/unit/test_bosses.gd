extends TestCase
## Bosses: the schedule, when a boss is due, its health by party size and its phases (game/logic/bosses.gd).


func test_default_tuning_builds_the_schedule_table() -> void:
	assert_eq(Bosses.schedule_from(Tuning.new()), Bosses.SCHEDULE)
	var t := Tuning.new()
	t.run_minutes = 3.0
	t.boss_every_min = 1.0
	assert_eq(Bosses.schedule_from(t), [[60.0, World.LICH, false], [120.0, World.LICH, false], [180.0, World.LICH, true]])


func test_due_finds_the_row_in_the_window() -> void:
	assert_eq(Bosses.due(0.0, 299.0), -1)
	assert_eq(Bosses.due(240.0, 300.0), 0)
	assert_eq(Bosses.due(300.0, 360.0), -1, "a row is due once")
	assert_eq(Bosses.due(540.0, 600.0), 1)
	assert_eq(Bosses.due(840.0, 900.0), 2)
	assert_true(Bosses.SCHEDULE[2][2], "the last row is the final")
	assert_eq(Bosses.final_time(), 900.0)


func test_health_grows_with_the_party_and_each_visit() -> void:
	var hp: float = Bestiary.KINDS[World.LICH][Bestiary.K_HP]
	for n: int in range(1, 5):
		assert_near(Bosses.health(World.LICH, 6, n, 1.0, 0.0), hp * Bosses.PARTY_HP[n - 1], 0.001)
	assert_near(Bosses.health(World.LICH, 11, 1, 1.0, 0.0), hp * (1.0 + Bosses.CYCLE_HP), 0.001, "second visit")
	assert_near(Bosses.health(World.LICH, 6, 2, 1.5, 0.06), hp * 1.6 * 1.5 * 0.94, 0.001, "seal and wounds")
	assert_near(Bosses.health(Bestiary.CHANDELIER, 6, 1, 1.0, 0.0), 240.0, 0.001)


func test_the_tuning_levers_give_the_tables() -> void:
	var t := Tuning.new()
	assert_eq(Bosses.party_hp_from(t), Bosses.PARTY_HP, "bit for bit, so the Lich's health is today's")
	assert_eq(t.boss_hp_per_cycle, Bosses.CYCLE_HP)


func test_phases_turn_at_their_lines() -> void:
	assert_eq(Bosses.phase(World.LICH, 0.51), 0)
	assert_eq(Bosses.phase(World.LICH, 0.49), 1)
	assert_eq(Bosses.phase(World.LICH, 0.7, true), 0)
	assert_eq(Bosses.phase(World.LICH, 0.6, true), 1, "the Archlich rages under FINAL_RAGE")


func test_world_spawns_and_kills_a_boss_through_bosses() -> void:
	var w := World.new([0, 1], 3)
	w.phase = World.PH_FIGHT
	var e: World.Enemy = w._spawn_boss(World.LICH, false)
	assert_true(w.boss == e)
	assert_near(e.maxhp, Bosses.health(World.LICH, 1, 2, 1.0, 0.0), 0.001)
	w.spawn_enemy(World.GOBLIN, 0, Vector2(200, 200))
	w._kill_enemy(e, 0)
	assert_true(w.boss == null, "the boss stayed")
	assert_eq(w.liches_slain, 1)
	for o: World.Enemy in w.enemies:
		assert_true(o.dead, "the field was not cleared")


func test_a_phase_turn_holds_the_boss_and_shields_it() -> void:
	var w := World.new([0], 3)
	w.phase = World.PH_FIGHT
	var e: World.Enemy = w._spawn_boss(World.LICH, false)
	w.eshot(World.ES_ORB, Vector2(100, 100), Vector2.ZERO, 3.0)
	w.phase_turn(e, 1.0)
	assert_true(w.eshots[0].dead, "the turn clears enemy shots")
	var hp := e.hp
	w._damage_enemy(e, 5.0, 0, Vector2.ZERO)
	assert_eq(e.hp, hp, "hurt while turning")
	var found := false
	for ev: Array in w.take_events():
		found = found or ev[0] == World.EV_PHASE
	assert_true(found, "no EV_PHASE")
	for _i: int in range(70):
		Bosses.think(w, e, 1.0 / 60.0, null, Vector2.RIGHT, 50.0)
	assert_eq(e.turn, 0.0)


func test_attacks_pass_min_warn() -> void:
	assert_true(BossLich.ATTACKS.is_empty(), "the Lich's attacks are shots, not rows")
	for row: Array in BossLich.ATTACKS:
		assert_true(float(row[1]) >= Hazards.min_warn(float(row[3])))
