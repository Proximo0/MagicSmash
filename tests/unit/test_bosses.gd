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
	assert_near(Bosses.health(World.LICH, 6, 2, 1.5, 0.06), hp * Bosses.PARTY_HP[1] * 1.5 * 0.94, 0.001, "seal and wounds")
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
	assert_near(e.maxhp, Bosses.health(World.LICH, 1, 2, 1.0, 0.0) * w.tune.boss_hp_mul, 0.001)
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


## The act-boss schedule job L will switch to.
const ACT_SCHEDULE: Array = [[300.0, Bestiary.CHANDELIER, false], [600.0, Bestiary.GHOSTWRITER, false], [900.0, Bestiary.LICH, true]]


func test_the_header_starts_empty_for_each_boss() -> void:
	var w := World.new([0], 3)
	w.phase = World.PH_FIGHT
	w.boss_t = 2.0
	w.boss_arg = 9
	w.boss_meter = 0.5
	var e: World.Enemy = w._spawn_boss(World.LICH, false)
	assert_eq([w.boss_t, w.boss_arg, w.boss_meter], [0.0, 0, 0.0], "an arrival clears the header")
	w.boss_t = 1.0
	w.boss_arg = 3
	w.boss_meter = 0.2
	w._kill_enemy(e, 0)
	assert_eq([w.boss_t, w.boss_arg, w.boss_meter], [0.0, 0, 0.0], "a death clears the header")


func test_a_non_lich_boss_end_to_end() -> void:
	var w := World.new([0, 1, 2], 3)
	w.schedule = ACT_SCHEDULE
	w.phase = World.PH_FIGHT
	w.wave = 6
	w.wave_time = 300.0
	var e: World.Enemy = w._spawn_boss(Bestiary.CHANDELIER, false)
	assert_true(w.boss == e)
	assert_near(e.maxhp, Bosses.health_in(w, Bestiary.CHANDELIER), 0.001)
	assert_near(e.maxhp, 240.0 * Bosses.PARTY_HP[2] * w.tune.boss_hp_mul, 0.001, "first visit, three wizards")
	assert_near(e.spd, float(Bestiary.KINDS[Bestiary.CHANDELIER][Bestiary.K_SPD]), 0.001, "a fixed speed")
	var p0: World.Player = w.players[0]
	var d0 := e.pos.distance_to(p0.pos)
	for _i: int in range(60):
		WorldEnemies._update_enemy(w, e, 1.0 / 60.0)
	assert_true(e.pos.distance_to(p0.pos) < d0 or not e.entering, "it should come in")
	assert_eq(Bosses.phase(e.type, 0.51), 0)
	assert_eq(Bosses.phase(e.type, 0.49), 1)
	e.hp = e.maxhp * 0.4
	assert_eq(int(w.snapshot().w[World.W_BOSS_PHASE]), 1)
	assert_eq(int(w.snapshot().w[World.W_BOSS_TYPE]), Bestiary.CHANDELIER)
	w.add_hazard(Hazards.FIRE, Vector2(100, 100), Vector2(100, 100), 20.0, 1.0, 1.0, -1, e.id)
	w._kill_enemy(e, 0)
	assert_true(w.boss == null)
	assert_true(w.hazards.is_empty(), "its death clears the floor")
	assert_true(w.lull_left > 0.0, "a lull follows a boss that is not the final")
	assert_eq(int(w.snapshot().w[World.W_BOSS_TYPE]), -1)


func test_the_final_minute_with_another_kind_of_boss_up() -> void:
	var w := World.new([0], 3)
	w.schedule = ACT_SCHEDULE
	w.phase = World.PH_FIGHT
	w.wave = 15
	w.wave_time = 899.0
	var ghost: World.Enemy = w._spawn_boss(Bestiary.GHOSTWRITER, false)
	w.wave_time = 900.0
	w._tick_minute()
	assert_true(ghost.dead, "the other boss gives way")
	assert_true(w.boss == null)
	var queued := false
	for s: Dictionary in w.spawn_queue:
		queued = queued or (int(s.type) == World.LICH and s.get("final", false))
	assert_true(queued, "the scheduled final boss comes")
	assert_false(ghost.final)
