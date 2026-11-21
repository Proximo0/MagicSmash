extends TestCase
## Hazards: hazard rows, their caps, clocks and packing (game/logic/hazards.gd), and World running them
## (game/logic/world/hazards.gd), including the fair-walk rule.

const DT: float = 1.0 / 60.0


func _row(kind: int, a: Vector2, b: Vector2, r: float, warn: float = 0.8, hot: float = 0.5) -> Hazards.Hazard:
	var h := Hazards.Hazard.new()
	h.kind = kind
	h.a = a
	h.b = b
	h.r = r
	h.warn = warn
	h.warn0 = warn
	h.hot = hot
	return h


## A quiet World with one wizard and no horde.
func _quiet() -> World:
	var t := Tuning.new()
	t.enemy_cap = 0.0
	t.elite_interval = 9999.0
	var w := World.new([0], 3, t)
	w.phase = World.PH_FIGHT
	w.powerup_timer = 9999.0
	(w.players[0] as World.Player).invuln = 0.0
	return w


func test_min_warn_follows_the_rule() -> void:
	assert_near(Hazards.min_warn(30.0), 0.3 + 34.0 / 71.0)
	assert_true(Hazards.min_warn(40.0) > Hazards.min_warn(10.0))


func test_contains_discs_and_lines() -> void:
	var d := _row(Hazards.FIRE, Vector2(100, 100), Vector2(100, 100), 20.0)
	assert_true(Hazards.contains(d, Vector2(110, 110)))
	assert_false(Hazards.contains(d, Vector2(120, 115)))
	var l := _row(Hazards.FLAME, Vector2(0, 50), Vector2(200, 50), 5.0)
	assert_true(Hazards.contains(l, Vector2(150, 54)))
	assert_false(Hazards.contains(l, Vector2(150, 57)))
	assert_false(Hazards.contains(l, Vector2(210, 50)), "past the line's end")


func test_caps_hold() -> void:
	var rows: Array[Hazards.Hazard] = []
	var party := Vector2(200, 200)
	for i: int in range(Hazards.WARN_BUDGET):
		assert_true(Hazards.can_add(rows, party, false, false))
		rows.append(_row(Hazards.FIRE, party, party, 10.0))
	assert_false(Hazards.can_add(rows, party, false, false), "past the warning budget")
	assert_true(Hazards.can_add(rows, party, true, false), "boss rows skip the budget")
	assert_true(Hazards.can_add(rows, party, false, true), "forced rows skip the budget")
	for h: Hazards.Hazard in rows:
		h.warn = 0.0
	while rows.size() < Hazards.CAP_REGULAR:
		rows.append(_row(Hazards.FIRE, party, party, 10.0, 0.0))
	assert_false(Hazards.can_add(rows, party, false, false), "past the regular cap")
	while rows.size() < Hazards.CAP:
		rows.append(_row(Hazards.FIRE, party, party, 10.0, 0.0))
	assert_false(Hazards.can_add(rows, party, true, true), "nothing passes CAP")


func test_tick_follows_then_locks_then_turns_hot() -> void:
	var h := _row(Hazards.BLAST, Vector2(10, 10), Vector2(10, 10), 30.0, 1.0)
	h.follow = 0
	h.lock = 0.5
	var rows: Array[Hazards.Hazard] = [h]
	var turned: Array[Hazards.Hazard] = Hazards.tick(rows, 0.25, {0: Vector2(50, 60)})
	assert_eq(h.a, Vector2(50, 60), "it follows while warning")
	assert_true(turned.is_empty())
	Hazards.tick(rows, 0.3, {0: Vector2(70, 60)})
	Hazards.tick(rows, 0.1, {0: Vector2(90, 60)})
	assert_eq(h.a, Vector2(70, 60), "it locks with `lock` s left")
	turned = Hazards.tick(rows, 0.5, {})
	assert_eq(turned.size(), 1)
	assert_eq(h.warn, 0.0)
	Hazards.tick(rows, 0.1, {})
	assert_near(h.hot, 0.4)


func test_pack_and_goal() -> void:
	var rows: Array[Hazards.Hazard] = [_row(Hazards.FIRE, Vector2(1, 2), Vector2(3, 4), 5.0, 0.6, 2.0),
		_row(Hazards.SAFE, Vector2(30, 40), Vector2(30, 40), 40.0, 3.5)]
	rows[0].id = 7
	var hz := Hazards.pack(rows)
	assert_eq(hz.size(), Hazards.FLOATS * 2)
	assert_eq(int(hz[0]), 7)
	assert_eq(int(hz[1]), Hazards.FIRE)
	assert_near(hz[6], 5.0)
	assert_near(hz[7], 0.6)
	assert_near(hz[9], 2.0)
	assert_eq(Hazards.goal(hz), Vector2(30, 40))
	assert_eq(Hazards.goal(Hazards.pack([] as Array[Hazards.Hazard])), Vector2.INF)


func test_steer_leans_out_of_a_row_and_into_safety() -> void:
	var fire: Array[Hazards.Hazard] = [_row(Hazards.FIRE, Vector2(100, 100), Vector2(100, 100), 22.0, 0.3)]
	var push := Hazards.steer(Hazards.pack(fire), Vector2(110, 100), 102.0, 0.2)
	assert_true(push.x > 0.0, "should lean away from the centre")
	assert_eq(Hazards.steer(Hazards.pack(fire), Vector2(200, 100), 102.0, 0.2), Vector2.ZERO)
	var safe: Array[Hazards.Hazard] = [_row(Hazards.SAFE, Vector2(100, 100), Vector2(100, 100), 40.0, 1.0)]
	assert_true(Hazards.steer(Hazards.pack(safe), Vector2(200, 100), 102.0, 0.2).x < 0.0, "should lean into the SAFE disc")
	var mark: Array[Hazards.Hazard] = [_row(Hazards.MARK, Vector2(0, 100), Vector2(200, 100), 4.0)]
	assert_eq(Hazards.steer(Hazards.pack(mark), Vector2(100, 100), 102.0, 0.2), Vector2.ZERO, "a MARK is only a sign")


func test_a_wizard_can_always_walk_out_in_time() -> void:
	# The fair-walk rule: a wizard standing at the worst spot (the centre), who reacts after WARN_BASE and then
	# walks at full speed, is out before the row turns hot, for every disc radius and line half-width the bestiary
	# uses, at exactly min_warn.
	for shape: int in [Hazards.FIRE, Hazards.FLAME]:
		for r: float in [4.0, 5.0, 8.0, 10.0, 13.0, 18.0, 22.0, 30.0, 40.0, 44.0, 50.0]:
			var w := _quiet()
			var p: World.Player = w.players[0]
			var at := p.pos
			var h := w.add_hazard(shape, at - Vector2(0, 80) if shape == Hazards.FLAME else at,
				at + Vector2(0, 80) if shape == Hazards.FLAME else at, r, 0.0, 0.5)
			assert_near(h.warn, Hazards.min_warn(r), 0.0001, "the warning is raised to min_warn")
			var hp := p.hp
			var steps := int(ceilf((h.warn0 + 0.6) / DT))
			for i: int in range(steps):
				var walk := i * DT >= Hazards.WARN_BASE
				w.step(DT, {0: PackedFloat32Array([1.0 if walk else 0.0, 0, 0, 0, 0, 0])})
			assert_eq(p.hp, hp, "kind %d r %.0f: a wizard walking out was hurt" % [shape, r])


func test_a_hot_row_hurts_and_a_still_wizard_is_hit() -> void:
	var w := _quiet()
	var p: World.Player = w.players[0]
	var hp := p.hp
	w.add_hazard(Hazards.FIRE, p.pos, p.pos, 20.0, 0.5, 1.0)
	for _i: int in range(60):
		w.step(DT, {})
	assert_eq(p.hp, hp - 1)
	for _i: int in range(60):
		w.step(DT, {})
	assert_true(w.hazards.is_empty(), "a spent row stays")


func test_safe_hurts_those_outside() -> void:
	var w := _quiet()
	var p: World.Player = w.players[0]
	var hp := p.hp
	w.add_hazard(Hazards.SAFE, p.pos + Vector2(100, 0), p.pos + Vector2(100, 0), 40.0, 0.5, 0.2)
	for _i: int in range(60):
		w.step(DT, {})
	assert_eq(p.hp, hp - int(Hazards.KINDS[Hazards.SAFE][Hazards.K_HEARTS]))


func test_a_blast_hurts_enemies_once_and_credits_the_slot() -> void:
	var w := _quiet()
	var p: World.Player = w.players[0]
	p.invuln = 999.0
	var at := p.pos + Vector2(w.tune.auto_aim_range + 60.0, 0) # out of the wizard's auto-aim
	var e: World.Enemy = w.spawn_enemy(World.ORC, 0, at)
	e.hp = 1000.0
	w.add_hazard(Hazards.BLAST, at, at, 30.0, 0.8, 0.3, 0)
	for _i: int in range(80):
		w.step(DT, {})
	assert_near(1000.0 - e.hp, float(Hazards.KINDS[Hazards.BLAST][Hazards.K_FOE_DMG]), 0.01, "one blast, at the minute's scale")
	assert_true(w.record.stat(0, "damage") > 0.0, "the slot gets the credit")


func test_rows_spawn_and_shoot() -> void:
	var w := _quiet()
	var p: World.Player = w.players[0]
	p.invuln = 999.0
	var fall := w.add_hazard(Hazards.FALL, Vector2(300, 150), Vector2(300, 150), 18.0, 1.2, 0.2)
	fall.aux = World.GOBLIN
	var burst := w.add_hazard(Hazards.BURST, Vector2(200, 300), Vector2(200, 300), 22.0, 0.7, 0.2)
	burst.aux = World.ES_SKULL * Hazards.SHOT_KIND + 10
	for _i: int in range(80):
		w.step(DT, {})
	assert_eq(w.enemies.size(), 1, "the fall lands an enemy")
	assert_eq(w.eshots.size(), 10, "the burst fires its ring")


func test_an_owner_dying_in_the_warning_removes_its_row() -> void:
	var w := _quiet()
	var e: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(300, 300))
	w.add_hazard(Hazards.FIRE, Vector2(100, 100), Vector2(100, 100), 20.0, 1.0, 1.0, -1, e.id)
	w.step(DT, {})
	assert_eq(w.hazards.size(), 1)
	w._kill_enemy(e, 0)
	w.step(DT, {})
	assert_true(w.hazards.is_empty())


func test_the_nova_clears_regular_rows_only() -> void:
	var w := _quiet()
	var p: World.Player = w.players[0]
	var boss: World.Enemy = w._spawn_boss(World.LICH, false)
	w.add_hazard(Hazards.FIRE, p.pos + Vector2(40, 0), p.pos + Vector2(40, 0), 20.0, 2.0, 1.0)
	w.add_hazard(Hazards.FIRE, p.pos + Vector2(300, 0), p.pos + Vector2(300, 0), 20.0, 2.0, 1.0)
	var mine := w.add_hazard(Hazards.FIRE, p.pos + Vector2(0, 40), p.pos + Vector2(0, 40), 20.0, 2.0, 1.0, -1, boss.id)
	assert_true(mine.boss)
	WorldPlayers._nova(w, p)
	assert_eq(w.hazards.size(), 2, "the near regular row goes, the far one and the boss's stay")
	w._kill_enemy(boss, 0)
	assert_true(w.hazards.is_empty(), "a boss's death clears the floor")


func test_snapshot_carries_rows_and_the_boss_header() -> void:
	var w := _quiet()
	var snap := w.snapshot()
	assert_eq(snap.w.size(), World.W_FLOATS)
	assert_eq(int(snap.w[World.W_BOSS_TYPE]), -1)
	assert_true((snap.hz as PackedFloat32Array).is_empty())
	var boss: World.Enemy = w._spawn_boss(World.LICH, false)
	boss.hp = boss.maxhp * 0.4
	w.boss_meter = 0.25
	w.add_hazard(Hazards.LANE, Vector2(0, 100), Vector2(400, 100), 12.0, 1.0, 0.5)
	snap = w.snapshot()
	assert_eq(int(snap.w[World.W_BOSS_TYPE]), World.LICH)
	assert_eq(int(snap.w[World.W_BOSS_PHASE]), 1)
	assert_near(snap.w[World.W_BOSS_METER], 0.25)
	assert_eq((snap.hz as PackedFloat32Array).size(), Hazards.FLOATS)


func test_a_bot_steers_out_of_warned_rows() -> void:
	for kind: int in [Hazards.FIRE, Hazards.FLAME]:
		var w := _quiet()
		var p: World.Player = w.players[0]
		var bot := SmashBot.new(4)
		var at := p.pos
		var b := at + (Vector2(0, 120) if kind == Hazards.FLAME else Vector2.ZERO)
		w.add_hazard(kind, at - (b - at), b, 22.0 if kind == Hazards.FIRE else 10.0, 1.4, 1.0)
		var hp := p.hp
		for _i: int in range(150):
			w.step(DT, {0: bot.decide_in_world(w, 0)})
		assert_eq(p.hp, hp, "kind %d: the bot stood in a hot row" % kind)
