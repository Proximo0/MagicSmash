extends TestCase
## Bestiary: the enemy kinds, the horde table and the group roll (game/logic/bestiary.gd).


func _alive() -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(Bestiary.count())
	return a


func test_ids_are_reserved_and_rows_are_full() -> void:
	assert_eq(Bestiary.count(), Bestiary.GHOSTWRITER + 1)
	assert_eq(World.PRIEST, Bestiary.PRIEST)
	var keys := {}
	for row: Array in Bestiary.KINDS:
		assert_eq(row.size(), Bestiary.K_FLAGS + 1, str(row[0]))
		assert_false(keys.has(row[0]), "duplicate key " + str(row[0]))
		keys[row[0]] = true
	assert_true(Bestiary.has_flag(Bestiary.LICH, Bestiary.F_BOSS))
	assert_true(Bestiary.has_flag(Bestiary.CHANDELIER, Bestiary.F_BOSS))
	assert_false(Bestiary.has_flag(Bestiary.ORC, Bestiary.F_BOSS))


func test_horde_rows_cover_every_non_boss_kind_once() -> void:
	var seen := {}
	for row: Array in Bestiary.HORDE:
		assert_eq(row.size(), Bestiary.H_FORM + 1)
		var t: int = row[Bestiary.H_TYPE]
		assert_false(seen.has(t), "two rows for %d" % t)
		seen[t] = true
		assert_false(Bestiary.has_flag(t, Bestiary.F_BOSS), "a boss in the horde")
	for t: int in range(Bestiary.BLOAT, Bestiary.SWORDS + 1):
		assert_true(seen.has(t), "no horde row for reserved kind %d" % t)
		var row: Array = Bestiary.horde_row(t)
		for c: int in range(Bestiary.H_W1, Bestiary.H_W1 + 3):
			assert_eq(int(row[c]), 0, "a reserved kind already weighs in the horde")


func test_roll_group_matches_the_old_draw_order() -> void:
	# Before job K's weights, roll_group draws exactly what WorldWaves._roll_group drew: randi(1, total), randi(size).
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	for i: int in range(200):
		var t := float(i * 5)
		var g: Array = Bestiary.roll_group(a, t, Lore.act_of(int(t / 60.0)), _alive(), 4, false)
		var total := 0
		for row: Array in Bestiary.HORDE:
			if t >= row[Bestiary.H_UNLOCK]:
				total += int(row[Bestiary.H_W1])
		var r := b.randi_range(1, total)
		var want: Array = []
		for row: Array in Bestiary.HORDE:
			if t < row[Bestiary.H_UNLOCK] or int(row[Bestiary.H_W1]) == 0:
				continue
			r -= int(row[Bestiary.H_W1])
			if r <= 0:
				want = [row[0], b.randi_range(row[Bestiary.H_GMIN], row[Bestiary.H_GMAX] + row[Bestiary.H_EXTRA] * int(t / 60.0))]
				break
		assert_eq(g[0], Bestiary.GROUP)
		assert_eq(g[1][0], want)


func test_caps_and_bosses_hold_rows_back() -> void:
	# A capped row is left out at its cap (one more with 3 or 4 wizards); F_HAZARD kinds wait while a boss is up.
	var row: Array = [Bestiary.BLOAT, 2.0, 0.0, 1, 1, 1, 1, 2, 0, 2, Bestiary.GROUP]
	var alive := _alive()
	assert_true(Bestiary._rollable(row, 10.0, Bestiary.H_W1, alive, 1, false))
	assert_false(Bestiary._rollable(row, 10.0, Bestiary.H_W1, alive, 1, true), "a hazard kind rolled during a boss")
	alive[Bestiary.BLOAT] = 2
	assert_false(Bestiary._rollable(row, 10.0, Bestiary.H_W1, alive, 2, false), "past the cap")
	assert_true(Bestiary._rollable(row, 10.0, Bestiary.H_W1, alive, 3, false), "3 wizards get one more")
	assert_eq(Bestiary.cap_of(row, 4), 3)
	assert_false(Bestiary._rollable(row, 0.0 - 1.0, Bestiary.H_W1, _alive(), 1, false), "before its unlock")


func test_world_counts_the_living_per_type() -> void:
	var w := World.new([0], 5)
	w.spawn_enemy(World.ORC, 0, Vector2(100, 100))
	w.spawn_enemy(World.ORC, 0, Vector2(120, 100))
	w.spawn_enemy(Bestiary.BLOAT, 0, Vector2(140, 100))
	w._build_grid()
	assert_eq(w.alive[World.ORC], 2)
	assert_eq(w.alive[Bestiary.BLOAT], 1)


func test_a_reserved_kind_walks_at_the_wizard_until_its_brain_lands() -> void:
	var w := World.new([0], 5)
	w.phase = World.PH_FIGHT
	var p: World.Player = w.players[0]
	for t: int in range(Bestiary.BLOAT, Bestiary.SWORDS + 1):
		var e: World.Enemy = w.spawn_enemy(t, 0, p.pos + Vector2(80, 0))
		assert_eq(e.flags, Bestiary.flags(t))
		var d0 := e.pos.distance_to(p.pos)
		for _i: int in range(30):
			WorldEnemies._update_enemy(w, e, 1.0 / 60.0)
		if Bestiary.has_flag(t, Bestiary.F_ANCHORED):
			assert_near(e.pos.distance_to(p.pos), d0, 0.01, "an anchored kind moved")
		else:
			assert_true(e.pos.distance_to(p.pos) < d0, "kind %d did not close in" % t)
		e.dead = true
	w.enemies.clear()


func test_eshots_stop_at_the_cap() -> void:
	var w := World.new([0], 5)
	for i: int in range(Bestiary.ESHOT_CAP + 20):
		w.eshot(World.ES_ORB, Vector2(200, 200), Vector2(10, 0), 3.0)
	assert_eq(w.eshots.size(), Bestiary.ESHOT_CAP)
