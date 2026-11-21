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
	# Job K's act weights (docs/bestiary_design.md section 1, W I/II/III).
	var acts := {Bestiary.BLOAT: [1, 1, 1], Bestiary.COFFIN: [1, 1, 0], Bestiary.GUARD: [1, 1, 0],
		Bestiary.CINDERLING: [0, 2, 1], Bestiary.CENSOR: [0, 2, 0], Bestiary.HOUND: [0, 1, 1], Bestiary.SHARD: [0, 0, 1],
		Bestiary.SWORDS: [0, 0, 2]}
	for t: int in range(Bestiary.BLOAT, Bestiary.SWORDS + 1):
		assert_true(seen.has(t), "no horde row for reserved kind %d" % t)
		assert_true(Bestiary.is_new_kind(t))
		var row: Array = Bestiary.horde_row(t)
		assert_eq(row.slice(Bestiary.H_W1, Bestiary.H_W1 + 3), acts[t], "act weights of %d" % t)
		assert_true(Bestiary.BRAINS.has(t), "kind %d has a brain" % t)


func test_roll_group_matches_the_old_draw_order() -> void:
	# With Tuning.new_kinds at 0, roll_group draws exactly what WorldWaves._roll_group drew before job K's kinds:
	# randi(1, total), randi(size), no formation roll.
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	for i: int in range(200):
		var t := float(i * 5)
		var g: Array = Bestiary.roll_group(a, t, Lore.act_of(int(t / 60.0)), _alive(), 4, false, Bestiary.FORMATIONS, 0.0)
		var total := 0
		for row: Array in Bestiary.HORDE:
			if t >= row[Bestiary.H_UNLOCK] and not Bestiary.is_new_kind(row[0]):
				total += int(row[Bestiary.H_W1])
		var r := b.randi_range(1, total)
		var want: Array = []
		for row: Array in Bestiary.HORDE:
			if t < row[Bestiary.H_UNLOCK] or int(row[Bestiary.H_W1]) == 0 or Bestiary.is_new_kind(row[0]):
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


func test_a_reserved_kind_with_no_brain_walks_at_the_wizard() -> void:
	var saved: Dictionary = Brains.kind_brains
	Brains.kind_brains = {}
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
	Brains.kind_brains = saved


func test_eshots_stop_at_the_cap() -> void:
	var w := World.new([0], 5)
	for i: int in range(Bestiary.ESHOT_CAP + 20):
		w.eshot(World.ES_ORB, Vector2(200, 200), Vector2(10, 0), 3.0)
	assert_eq(w.eshots.size(), Bestiary.ESHOT_CAP)


func test_brains_dispatch_through_the_kind_table() -> void:
	var saved: Dictionary = Brains.kind_brains
	Brains.kind_brains = {Bestiary.BLOAT: "res://tests/unit/brain_stub.gd"}
	var w := World.new([0], 5)
	w.phase = World.PH_FIGHT
	var p: World.Player = w.players[0]
	var e: World.Enemy = w.spawn_enemy(Bestiary.BLOAT, 0, p.pos + Vector2(80, 0))
	var y0 := e.pos.y
	for _i: int in range(10):
		WorldEnemies._update_enemy(w, e, 1.0 / 60.0)
	assert_eq(e.state, 7, "think did not run")
	assert_true(e.pos.y < y0, "the stub walks up")
	var hp := e.hp
	w.damage_enemy(e, 1.0, 0, Vector2.ZERO)
	assert_eq(e.hp, hp, "filter_damage blocked nothing")
	w.damage_enemy(e, 1.0, 0, Vector2.ZERO, true)
	assert_true(e.hp < hp, "a sure hit should land")
	w._kill_enemy(e, 0)
	assert_eq(w.boss_arg, 4242, "on_death did not run")
	Brains.kind_brains = saved
	assert_eq(Brains.kind_brains, Bestiary.BRAINS)


func test_formations_keep_caps_and_the_boss_rule() -> void:
	# A test formation: two bloats (F_HAZARD, cap 6) and three goblins, from 0 s, always rolled (weight 1).
	var forms: Array = [["TEST", 0.0, 1, [[Bestiary.BLOAT, 2], [World.GOBLIN, 3]], Bestiary.AT_DOOR]]
	var rng := RandomNumberGenerator.new()
	var seen := false
	for i: int in range(40):
		rng.seed = i
		var g: Array = Bestiary.roll_group(rng, 10.0, 0, _alive(), 1, false, forms)
		seen = seen or g[0] == 8 + Bestiary.AT_DOOR
	assert_true(seen, "the formation never rolled")
	for i: int in range(40):
		rng.seed = i
		assert_true(Bestiary.roll_group(rng, 10.0, 0, _alive(), 1, true, forms)[0] < 8, "a hazard formation during a boss")
		var full := _alive()
		full[Bestiary.BLOAT] = 5
		assert_true(Bestiary.roll_group(rng, 10.0, 0, full, 1, false, forms)[0] < 8, "a formation past its cap")


func test_queued_spawns_count_and_a_saved_group_is_checked_again() -> void:
	var w := World.new([0], 5)
	w.spawn_queue.append({"t": 1.0, "type": Bestiary.BLOAT, "door": 0})
	w.spawn_enemy(Bestiary.BLOAT, 0, Vector2(100, 100))
	assert_eq(WorldWaves._fielded(w)[Bestiary.BLOAT], 2, "the queue counts")
	assert_false(WorldWaves._boss_coming(w))
	w.spawn_queue.append({"t": 2.0, "type": World.LICH, "door": 0})
	assert_true(WorldWaves._boss_coming(w), "a queued boss counts")
	# A saved bloat group is dropped once a boss is coming, and trimmed to the room under its cap.
	assert_false(Bestiary.trim([[Bestiary.BLOAT, 2]], WorldWaves._fielded(w), 1, true))
	var parts: Array = [[Bestiary.BLOAT, 6]]
	assert_true(Bestiary.trim(parts, WorldWaves._fielded(w), 1, false))
	assert_eq(parts[0][1], 6 - 2)
	assert_false(Bestiary.needs_check([[World.GOBLIN, 9], [World.ORC, 1]]), "today's kinds are never checked again")
	w.phase = World.PH_FIGHT
	w._next_group = [Bestiary.GROUP, [[Bestiary.BLOAT, 2]]]
	w.horde_budget = 1000.0
	var queued := w.spawn_queue.size()
	WorldWaves._direct_horde(w, 1.0 / 60.0)
	assert_eq(w.spawn_queue.size(), queued, "a hazard group was spent while a boss was coming")
	assert_true(w._next_group.is_empty(), "the saved group should be rolled again")


func test_rise_wall_and_opposite_doors_queue_where_they_should() -> void:
	var w := World.new([0, 1], 5)
	w.phase = World.PH_FIGHT
	var c := w.party_center()
	WorldWaves._queue_rolled(w, [Bestiary.RISE, [[Bestiary.COFFIN, 2]]])
	assert_eq(w.spawn_queue.size(), 2)
	for s: Dictionary in w.spawn_queue:
		assert_eq(int(s.type), Bestiary.COFFIN)
		assert_true(s.has("at"), "a riser comes up from the floor")
		assert_true((s.at as Vector2).distance_to(c) <= Bestiary.RISE_MAX + 1.0)
		assert_near(float(s.t), w.tune.rift_warning, 0.001)
	w.spawn_queue.clear()
	WorldWaves._queue_rolled(w, [Bestiary.WALL, [[Bestiary.GUARD, 3]]])
	assert_eq(w.spawn_queue.size(), 3)
	for s: Dictionary in w.spawn_queue:
		assert_eq(int(s.door), int(w.spawn_queue[0].door), "a wall comes through one door")
		assert_eq(float(s.t), float(w.spawn_queue[0].t), "abreast")
	w.spawn_queue.clear()
	WorldWaves._queue_rolled(w, [8 + Bestiary.AT_OPPOSITE, [[Bestiary.CINDERLING, 1], [Bestiary.CINDERLING, 1], [Bestiary.CENSOR, 1]]])
	assert_eq(w.spawn_queue.size(), 3)
	var d0: int = w.spawn_queue[0].door
	assert_eq(int(w.spawn_queue[1].door), d0 ^ 1, "the second part takes the opposite door")
	assert_eq(int(w.spawn_queue[2].door), d0)


func test_new_kinds_scale_the_horde_and_zero_drops_them() -> void:
	var rng := RandomNumberGenerator.new()
	var seen := {}
	for i: int in range(600):
		var g: Array = Bestiary.roll_group(rng, 800.0, 2, _alive(), 1, false, Bestiary.FORMATIONS, 0.0)
		assert_true(g[0] < 8, "no formation holds only old kinds")
		for part: Array in g[1]:
			assert_false(Bestiary.is_new_kind(part[0]), "a new kind rolled with new_kinds 0")
		g = Bestiary.roll_group(rng, 800.0, 2, _alive(), 1, false, Bestiary.FORMATIONS, 0.5)
		for part: Array in g[1]:
			seen[part[0]] = true
	assert_true(seen.has(Bestiary.SWORDS) and seen.has(Bestiary.SHARD), "act III's kinds roll at half weight")
	var t := Tuning.new()
	assert_near(t.new_kinds, 1.0, 0.0001)
	assert_true(t.set_value("new_kinds", 0.0), "playtest --tune=new_kinds:0 reaches the row")


func test_caps_hold_with_the_queue_counted() -> void:
	var w := World.new([0], 5)
	w.phase = World.PH_FIGHT
	w.wave_time = 200.0
	for i: int in range(6):
		w.spawn_queue.append({"t": 999.0, "type": Bestiary.BLOAT, "door": 0})
	for i: int in range(400):
		var g: Array = WorldWaves._roll_group(w)
		for part: Array in g[1]:
			assert_true(int(part[0]) != Bestiary.BLOAT, "a bloat past its cap of 6 (all queued)")
	w.spawn_queue.clear()
	var alive := _alive()
	alive[Bestiary.CINDERLING] = 2
	assert_false(Bestiary.fits([[Bestiary.CINDERLING, 1], [Bestiary.CINDERLING, 1]], alive, 1, false), "parts of one type add up")
	var parts: Array = [[Bestiary.CINDERLING, 1], [Bestiary.CINDERLING, 1], [Bestiary.CENSOR, 1]]
	assert_false(Bestiary.trim(parts, alive, 1, false), "the second cinderling has no room")


func test_no_hazard_kind_rolls_during_a_boss() -> void:
	var rng := RandomNumberGenerator.new()
	for act: int in range(3):
		for i: int in range(500):
			var g: Array = Bestiary.roll_group(rng, 900.0, act, _alive(), 4, true)
			for part: Array in g[1]:
				assert_false(Bestiary.has_flag(part[0], Bestiary.F_HAZARD), "kind %d rolled during a boss" % part[0])


func test_every_new_kind_warning_is_fair() -> void:
	var rows: Array = [
		[KindsCrypt.BLOAT_BLAST_R, KindsCrypt.BLOAT_BLAST_WARN],
		[KindsLibrary.CINDER_HALF, KindsLibrary.CINDER_KINDLE],
		[KindsLibrary.CENSOR_FIRE_R, KindsLibrary.CENSOR_FIRE_WARN],
		[KindsSanctum.SHARD_FALL_R, KindsSanctum.SHARD_FALL_WARN],
		[KindsSanctum.SHARD_BEAM_HALF, KindsSanctum.SHARD_BEAM_WARN],
		[KindsSanctum.SWORDS_BURST_R, KindsSanctum.SWORDS_KNEEL],
	]
	for r: Array in rows:
		assert_true(float(r[1]) >= Hazards.min_warn(float(r[0])), "warning %.2f s for r %.0f" % [r[1], r[0]])
