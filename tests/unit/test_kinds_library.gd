extends TestCase
## KindsLibrary: the CINDERLING, THE CENSOR and the ASH HOUND (game/logic/kinds_library.gd).

const DT := 1.0 / 60.0


func _lib_world(slots: Array = [0]) -> World:
	var w := World.new(slots, 5)
	w.phase = World.PH_FIGHT
	for p: World.Player in w.players.values():
		p.invuln = 999.0
	return w


## Runs the enemies and the hazard rows `secs` seconds, the way World.step orders them, with no horde.
func _lib_tick(w: World, secs: float) -> void:
	for _i: int in range(roundi(secs / DT)):
		w._build_grid()
		w._plist.assign(w.players.values())
		for e: World.Enemy in w.enemies:
			if not e.dead:
				WorldEnemies._update_enemy(w, e, DT)
		WorldHazards._update_hazards(w, DT)
		w.enemies = w.enemies.filter(func(e: World.Enemy) -> bool: return not e.dead)


func _rows(w: World, kind: int) -> Array:
	return w.hazards.filter(func(h: Hazards.Hazard) -> bool: return h.kind == kind)


## A cinderling 110 px from the wizard, just about to kindle.
func _kindling(w: World) -> World.Enemy:
	var p: World.Player = w.players[0]
	var e := w.spawn_enemy(Bestiary.CINDERLING, 0, p.pos + Vector2(110, 0))
	e.timer = 0.0
	_lib_tick(w, DT * 2.0)
	assert_eq(e.state, KindsLibrary.CS_KINDLE, "it kindles from inside its band")
	return e


func test_cinderling_marks_its_line_then_runs_it_in_fire() -> void:
	var w := _lib_world()
	var p: World.Player = w.players[0]
	var e := _kindling(w)
	var mark: Array = _rows(w, Hazards.MARK)
	assert_eq(mark.size(), 1)
	var m: Hazards.Hazard = mark[0]
	assert_near(m.a.distance_to(m.b), KindsLibrary.CINDER_LEN, 0.5)
	assert_near(Geometry2D.get_closest_point_to_segment(p.pos, m.a, m.b).distance_to(p.pos), 0.0, 0.5, "through a still target")
	var start := e.pos
	_lib_tick(w, KindsLibrary.CINDER_KINDLE + 0.6)
	assert_eq(e.state, KindsLibrary.CS_RUN)
	var flame: Array = _rows(w, Hazards.FLAME)
	assert_eq(flame.size(), 1, "the run lays fire")
	var f: Hazards.Hazard = flame[0]
	assert_true(f.a.distance_to(f.b) > 80.0, "the line grows behind it")
	assert_true(e.pos.distance_to(start) > 80.0)
	_lib_tick(w, 1.0)
	assert_eq(e.state, KindsLibrary.CS_HOLD, "the run ends")
	assert_true(f.a.distance_to(f.b) >= KindsLibrary.CINDER_LEN - 12.0)
	_lib_tick(w, KindsLibrary.CINDER_BURN - 0.3)
	assert_eq(_rows(w, Hazards.FLAME).size(), 1, "it burns on")
	_lib_tick(w, 0.6)
	assert_false(w.hazards.has(f), "then it is out")


func test_cinderling_leads_a_moving_target() -> void:
	var w := _lib_world()
	var p: World.Player = w.players[0]
	p.vel = Vector2(0, 100)
	var e := _kindling(w)
	var m: Hazards.Hazard = _rows(w, Hazards.MARK)[0]
	var ahead := p.pos + Vector2(0, KindsLibrary.CINDER_AHEAD)
	assert_near(Geometry2D.get_closest_point_to_segment(ahead, m.a, m.b).distance_to(ahead), 0.0, 0.5)
	assert_true(e.dir.y > 0.0)


func test_a_cinderling_killed_kindling_leaves_no_row() -> void:
	var w := _lib_world()
	var e := _kindling(w)
	w.damage_enemy(e, 99.0, 0, Vector2.ZERO)
	_lib_tick(w, 2.0)
	assert_eq(w.hazards.size(), 0, "no mark, no fire")


func test_a_cinderling_killed_mid_run_stops_the_fire() -> void:
	var w := _lib_world()
	var e := _kindling(w)
	_lib_tick(w, KindsLibrary.CINDER_KINDLE + 0.5)
	var f: Hazards.Hazard = _rows(w, Hazards.FLAME)[0]
	w.damage_enemy(e, 99.0, 0, Vector2.ZERO)
	var tip := f.b
	assert_true(tip.distance_to(f.a) < KindsLibrary.CINDER_LEN - 40.0)
	_lib_tick(w, 0.5)
	assert_eq(f.b, tip, "no more fire is laid")


func test_censor_throws_at_the_release_point() -> void:
	var w := _lib_world()
	var p: World.Player = w.players[0]
	var e := w.spawn_enemy(Bestiary.CENSOR, 0, p.pos + Vector2(120, 0))
	e.timer = 0.0
	_lib_tick(w, DT * 2.0)
	assert_eq(e.state, KindsLibrary.ZS_WIND)
	p.pos += Vector2(0, 30) # she walks on during the wind-up
	_lib_tick(w, KindsLibrary.CENSOR_WIND)
	var fire: Array = _rows(w, Hazards.FIRE)
	assert_eq(fire.size(), 1)
	var h: Hazards.Hazard = fire[0]
	assert_eq(h.a, p.pos, "at her feet as he lets go, no lead")
	assert_near(h.r, KindsLibrary.CENSOR_FIRE_R)
	assert_near(h.warn, KindsLibrary.CENSOR_FIRE_WARN, 0.02)
	_lib_tick(w, KindsLibrary.CENSOR_EVERY - 0.2)
	assert_eq(_rows(w, Hazards.FIRE).size(), 1, "one throw every 4 s")


func test_censor_panics_inside_60_px() -> void:
	var w := _lib_world()
	var p: World.Player = w.players[0]
	var e := w.spawn_enemy(Bestiary.CENSOR, 0, p.pos + Vector2(50, 0))
	e.timer = 0.0
	_lib_tick(w, 0.3)
	assert_eq(e.state, KindsLibrary.ZS_PANIC)
	assert_eq(_rows(w, Hazards.FIRE).size(), 0, "no throws in a panic")
	assert_true(e.vel.length() > e.spd * 1.3, "he backs off fast")
	assert_true(e.pos.distance_to(p.pos) > 50.0)


func test_hound_stray_scan() -> void:
	var w := _lib_world([0, 1, 2, 3])
	var d: World.Player = w.players[3]
	d.pos = Vector2(215, 210)
	var a: World.Player = w.players[0]
	var b: World.Player = w.players[1]
	var c: World.Player = w.players[2]
	a.pos = Vector2(200, 200)
	b.pos = Vector2(230, 200)
	c.pos = Vector2(200, 300)
	assert_eq(KindsLibrary.stray_of(w, Vector2.ZERO), -1, "100 px from an ally is no stray")
	c.pos = Vector2(400, 200)
	assert_eq(KindsLibrary.stray_of(w, Vector2.ZERO), 2)
	# c stands by a grave: a reviver is never picked.
	d.alive = false
	d.down = true
	d.pos = Vector2(420, 200)
	assert_eq(KindsLibrary.stray_of(w, Vector2.ZERO), -1, "a wizard within 40 px of a grave is never picked")
	d.pos = Vector2(470, 260)
	assert_eq(KindsLibrary.stray_of(w, Vector2.ZERO), 2, "the grave out of reach: she is the stray again")


func test_hounds_howl_then_hunt_the_stray_until_she_rejoins() -> void:
	var w := _lib_world([0, 1])
	var a: World.Player = w.players[0]
	var b: World.Player = w.players[1]
	a.pos = Vector2(240, 200)
	b.pos = Vector2(240, 380)
	var e := w.spawn_enemy(Bestiary.HOUND, 0, Vector2(400, 300))
	_lib_tick(w, KindsLibrary.HOUND_PROWL - 0.5)
	assert_eq(e.state % KindsLibrary.HOUND_SLOT_STEP, KindsLibrary.HS_CIRCLE, "it prowls first")
	_lib_tick(w, 1.0)
	var phase: int = e.state % KindsLibrary.HOUND_SLOT_STEP
	assert_true(phase == KindsLibrary.HS_HOWL or phase == KindsLibrary.HS_HUNT, "it named the stray")
	_lib_tick(w, KindsLibrary.HOUND_HOWL)
	assert_eq(e.state % KindsLibrary.HOUND_SLOT_STEP, KindsLibrary.HS_HUNT)
	assert_near(e.vel.length(), KindsLibrary.HOUND_SPEED, 1.0, "fixed hunting speed")
	var prey: int = int(e.count)
	(w.players[1 - prey] as World.Player).pos = (w.players[prey] as World.Player).pos + Vector2(30, 0)
	_lib_tick(w, DT * 2.0)
	assert_eq(e.state, KindsLibrary.HS_CIRCLE, "the hunt ends once the stray is back with an ally")


func test_a_solo_hound_prowls_then_hunts_three_seconds() -> void:
	var w := _lib_world()
	var p: World.Player = w.players[0]
	var e := w.spawn_enemy(Bestiary.HOUND, 0, p.pos + Vector2(160, 0))
	_lib_tick(w, KindsLibrary.HOUND_PROWL + KindsLibrary.HOUND_SCAN + KindsLibrary.HOUND_HOWL + 0.1)
	assert_eq(e.state % KindsLibrary.HOUND_SLOT_STEP, KindsLibrary.HS_HUNT)
	_lib_tick(w, KindsLibrary.HOUND_HUNT_SOLO)
	assert_eq(e.state, KindsLibrary.HS_CIRCLE, "a solo hunt lasts 3 s")


func test_hound_turns_at_most_its_rate() -> void:
	var w := _lib_world()
	var p: World.Player = w.players[0]
	var e := w.spawn_enemy(Bestiary.HOUND, 0, p.pos + Vector2(100, 0))
	KindsLibrary._hound_set(e, KindsLibrary.HS_HUNT, 0)
	e.dir = Vector2.RIGHT # running away from her
	_lib_tick(w, 0.5)
	assert_near(absf(e.dir.angle()), KindsLibrary.HOUND_TURN * 0.5, 0.05)


func test_two_strays_tie_and_each_hound_takes_the_nearer() -> void:
	var w := _lib_world([0, 1])
	var a: World.Player = w.players[0]
	var b: World.Player = w.players[1]
	a.pos = Vector2(100, 200)
	b.pos = Vector2(400, 200)
	assert_eq(KindsLibrary.stray_of(w, Vector2(380, 150)), 1, "a hound by b hunts b")
	assert_eq(KindsLibrary.stray_of(w, Vector2(120, 150)), 0, "a hound by a hunts a")
	a.pos = Vector2(400, 200)
	b.pos = Vector2(100, 200)
	assert_eq(KindsLibrary.stray_of(w, Vector2(380, 150)), 0, "the other order")
	assert_eq(KindsLibrary.stray_of(w, Vector2(120, 150)), 1)


func test_two_of_four_alive_tie_the_same_way() -> void:
	var w := _lib_world([0, 1, 2, 3])
	for s: int in [2, 3]:
		var q: World.Player = w.players[s]
		q.alive = false
		q.down = true
		q.pos = Vector2(250, 380)
	(w.players[0] as World.Player).pos = Vector2(100, 200)
	(w.players[1] as World.Player).pos = Vector2(400, 200)
	assert_eq(KindsLibrary.stray_of(w, Vector2(390, 120)), 1)
	assert_eq(KindsLibrary.stray_of(w, Vector2(90, 120)), 0)


func test_hounds_hunt_the_last_wizard_standing() -> void:
	var w := _lib_world([0, 1, 2, 3])
	var last: World.Player = w.players[0]
	for s: int in [1, 2, 3]:
		var q: World.Player = w.players[s]
		q.alive = false
		q.down = true
		q.pos = last.pos + Vector2(20, 0) # she stands by their graves
	assert_eq(KindsLibrary.stray_of(w, Vector2.ZERO), 0)
	var e := w.spawn_enemy(Bestiary.HOUND, 0, last.pos + Vector2(160, 0))
	_lib_tick(w, KindsLibrary.HOUND_PROWL + KindsLibrary.HOUND_SCAN + KindsLibrary.HOUND_HOWL + 0.1)
	assert_eq(e.state % KindsLibrary.HOUND_SLOT_STEP, KindsLibrary.HS_HUNT, "not circling forever")
	_lib_tick(w, KindsLibrary.HOUND_HUNT_SOLO)
	assert_eq(e.state, KindsLibrary.HS_CIRCLE, "solo rules: a 3 s hunt")


func test_a_pushed_kindling_cinderling_still_burns_its_mark() -> void:
	var w := _lib_world()
	var e := _kindling(w)
	var m: Hazards.Hazard = _rows(w, Hazards.MARK)[0]
	var a := m.a
	var b := m.b
	e.knock = Vector2(0, 300) # a spell shoves it off its line
	_lib_tick(w, KindsLibrary.CINDER_KINDLE + 0.5)
	var f: Hazards.Hazard = _rows(w, Hazards.FLAME)[0]
	assert_eq(f.a, a, "the fire starts where the mark does")
	var off := Geometry2D.get_closest_point_to_segment(f.b, a, b).distance_to(f.b)
	assert_near(off, 0.0, 0.01, "the fire grows along the mark")
	assert_true(f.a.distance_to(f.b) > 40.0)
