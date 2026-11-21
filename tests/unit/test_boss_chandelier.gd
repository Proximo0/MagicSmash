extends TestCase
## THE BONE CHANDELIER (game/logic/boss_chandelier.gd): its rows' warnings, its fixed order, whom it aims at, the
## chain snapping at half health, DROP on the tightest knot, the wheel's roll, a fallen wizard on the floor.

const DT := 1.0 / 60.0


## A world with `n` wizards spread around the middle and the Chandelier in, at minute 6 (its 5:00 visit).
func _chand_world(n: int) -> Array:
	var w := World.new(range(n), 5)
	w.phase = World.PH_FIGHT
	w.wave = 6
	w.wave_time = 300.0
	var c := G.ARENA.get_center()
	for p: World.Player in w.players.values():
		p.pos = c + Vector2.from_angle(TAU * p.slot / maxi(n, 1)) * 30.0
		p.invuln = 999.0
	var e: World.Enemy = w._spawn_boss(Bestiary.CHANDELIER, false)
	e.entering = false
	e.pos = c + Vector2(0, -90)
	_chand_run(w, e, DT) # its first think clears what it carried in from the door
	return [w, e]


## Runs only the boss and the rows for `secs` (the horde stays out); `seen` gathers each step it starts and each
## row it lays.
func _chand_run(w: World, e: World.Enemy, secs: float, seen: Dictionary = {}) -> void:
	w._plist.assign(w.players.values())
	for _i: int in int(secs / DT):
		if e.dead:
			return
		var was := e.state
		WorldEnemies._update_enemy(w, e, DT)
		w._update_hazards(DT)
		if e.state != was:
			(seen.get_or_add("steps", []) as Array).append(e.state)
		for h: Hazards.Hazard in w.hazards:
			(seen.get_or_add("rows", {}) as Dictionary)[h.id] = h


func test_attacks_pass_min_warn() -> void:
	for row: Array in BossChandelier.ATTACKS:
		assert_true(float(row[1]) >= Hazards.min_warn(float(row[3])), "row %s" % [row])


func test_every_row_it_lays_warns_long_enough() -> void:
	var made: Array = _chand_world(2)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	var seen := {}
	_chand_run(w, e, 40.0, seen)
	e.hp = e.maxhp * 0.45
	_chand_run(w, e, 45.0, seen)
	var kinds := {}
	for h: Hazards.Hazard in (seen.rows as Dictionary).values():
		kinds[h.kind] = true
		assert_true(h.warn0 >= Hazards.min_warn(h.r) - 0.001, "kind %d r %.0f warned %.2f" % [h.kind, h.r, h.warn0])
	for k: int in [Hazards.LANE, Hazards.FLAME, Hazards.BLAST, Hazards.SAFE]:
		assert_true(kinds.has(k), "never laid kind %d" % k)


func test_the_order_is_fixed() -> void:
	var made: Array = _chand_world(1)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	var seen := {}
	_chand_run(w, e, 60.0, seen)
	var starts: Array = []
	for s: int in seen.steps:
		if s in [BossChandelier.DRIP_WARN, BossChandelier.DROP_TRACK, BossChandelier.RAIN]:
			starts.append(s)
	assert_true(starts.size() >= 6, "too few attacks: %s" % [starts])
	for i: int in starts.size():
		assert_eq(starts[i], BossChandelier.ORDER_ALOFT[i % BossChandelier.ORDER_ALOFT.size()], "attack %d" % i)


func test_rain_aims_at_two_wizards_at_most() -> void:
	var made: Array = _chand_world(4)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	var c := w.party_center()
	var i := 0
	for p: World.Player in w.players.values():
		p.pos = c + Vector2.from_angle(TAU * i / 4.0) * 150.0
		i += 1
	assert_true(Bosses.aims(w, e).size() <= 2)
	e.state = BossChandelier.GAP
	e.count = 2.0 # RAIN is next
	e.timer = 0.0
	var seen := {}
	_chand_run(w, e, BossChandelier.RAIN_S, seen)
	var aimed := {}
	var rows := 0
	for h: Hazards.Hazard in (seen.rows as Dictionary).values():
		if h.kind != Hazards.BLAST:
			continue
		rows += 1
		if h.a.distance_to(w.party_center()) <= BossChandelier.RAIN_SPREAD + 1.0:
			continue
		for p: World.Player in w.players.values():
			if p.pos.distance_to(h.a) < 1.0:
				aimed[p.slot] = true
	assert_true(rows >= 18, "rain laid %d rows" % rows)
	assert_true(aimed.size() >= 1 and aimed.size() <= 2, "aimed at %s" % [aimed.keys()])


func test_the_chain_snaps_at_half_health() -> void:
	var made: Array = _chand_world(1)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	_chand_run(w, e, 0.1)
	e.hp = e.maxhp * 0.51
	_chand_run(w, e, 0.1)
	assert_eq(e.turn, 0.0, "turned above half")
	e.hp = e.maxhp * 0.49
	_chand_run(w, e, DT)
	assert_true(e.turn > 0.0, "no turn under half")
	var snap := Bosses.last_row(w, e, Hazards.BLAST)
	assert_true(snap != null and snap.r == BossChandelier.SNAP_R and snap.aux & Bosses.AUX_HEAVY, "no heavy snap blast")
	_chand_run(w, e, BossChandelier.SNAP_TURN + BossChandelier.GAP_WHEEL + 0.2)
	assert_true(e.state >= BossChandelier.WHEEL_FIRST, "not the wheel: %d" % e.state)


func test_drop_falls_on_the_tightest_knot_for_two_hearts() -> void:
	var made: Array = _chand_world(3)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	w.players[0].pos = e.pos + Vector2(0, 40) # alone, nearest the boss
	w.players[1].pos = e.pos + Vector2(120, 100)
	w.players[2].pos = e.pos + Vector2(140, 105) # a knot of two
	assert_eq(Bosses.knot_of(w).slot, 1)
	e.state = BossChandelier.GAP
	e.count = 1.0 # DROP is next
	e.timer = 0.0
	_chand_run(w, e, DT * 2)
	assert_eq(e.state, BossChandelier.DROP_TRACK)
	assert_eq(int(e.enter_dir.x), 1, "it chases the knot")
	for p: World.Player in w.players.values():
		p.invuln = 0.0
		p.hp = 5
	_chand_run(w, e, BossChandelier.DROP_TRACK_S + BossChandelier.DROP_LOCK_S + 0.1)
	assert_eq(e.state, BossChandelier.GROUNDED)
	assert_true(e.pos.distance_to(w.players[1].pos) < 60.0, "it fell far from the knot")
	assert_eq(w.players[1].hp, 5 - Bosses.HEAVY_HEARTS, "the drop hurts two hearts")
	assert_eq(w.players[0].hp, 5, "the lone wizard was hit")
	var bones := 0
	for s: World.EShot in w.eshots:
		bones += 1 if not s.dead else 0
	assert_eq(bones, BossChandelier.BONES)
	assert_near(BossChandelier.filter_damage(w, e, 2.0, Vector2.ZERO, false), 2.0 * BossChandelier.VULN, 0.001, "grounded takes more")
	assert_eq(e.contact, BossChandelier.CONTACT_DOWN)


func test_the_wheel_rolls_three_legs_then_lies_dizzy() -> void:
	var made: Array = _chand_world(2)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	_chand_run(w, e, 0.1)
	e.hp = e.maxhp * 0.4
	_chand_run(w, e, BossChandelier.SNAP_TURN + 0.1)
	e.timer = 0.0
	var seen := {}
	_chand_run(w, e, 12.0, seen)
	var legs := 0
	for s: int in seen.steps:
		legs += 1 if s == BossChandelier.ROLL else 0
		if s == BossChandelier.DIZZY:
			break
	assert_eq(legs, BossChandelier.ROLL_LEGS)
	assert_true(BossChandelier.DIZZY in seen.steps, "never dizzy")
	var lanes := 0
	for h: Hazards.Hazard in (seen.rows as Dictionary).values():
		if h.kind == Hazards.LANE and h.r == BossChandelier.ROLL_HW:
			lanes += 1
			assert_true(G.ARENA.has_point(h.b), "a lane leaves the room")
	assert_true(lanes >= BossChandelier.ROLL_LEGS, "a lane for each leg")


func test_last_candle_reaches_every_wizard_and_prefers_a_grave() -> void:
	var w := World.new([0, 1, 2], 5)
	w.phase = World.PH_FIGHT
	var c := G.ARENA.get_center()
	w.players[0].pos = c + Vector2(-120, 0)
	w.players[1].pos = c + Vector2(120, 0)
	w.players[2].pos = c + Vector2(0, 100)
	var at := Bosses.candle_spot(w, c + Vector2(0, -150))
	for p: World.Player in w.players.values():
		assert_true(p.pos.distance_to(at) <= Bosses.CANDLE_REACH, "too far from %d" % p.slot)
	WorldPlayers._fall(w, w.players[2])
	w.players[2].pos = c + Vector2(0, 40)
	assert_eq(Bosses.candle_spot(w, c + Vector2(0, -150)), w.players[2].pos, "the grave first")
	w.players[0].pos = c + Vector2(-200, 0)
	assert_true(Bosses.candle_spot(w, c) != w.players[2].pos, "a grave too far from a wizard")


func test_a_fallen_wizard_is_never_aimed_at() -> void:
	var made: Array = _chand_world(2)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	WorldPlayers._fall(w, w.players[1])
	w.players[1].pos = e.pos + Vector2(0, 10)
	for _k: int in 3:
		assert_eq(Bosses.knot_of(w).slot, 0)
		assert_eq(Bosses.farthest_from(w, e.pos).slot, 0)
		_chand_run(w, e, 25.0)
	e.hp = e.maxhp * 0.4
	_chand_run(w, e, 40.0)
	assert_false(e.dead)


func test_health_from_the_tables() -> void:
	for n: int in [1, 4]:
		var w := World.new(range(n), 5)
		w.wave = 6
		w.wave_time = 300.0
		var e: World.Enemy = w._spawn_boss(Bestiary.CHANDELIER, false)
		assert_near(e.maxhp, float(Bestiary.KINDS[Bestiary.CHANDELIER][Bestiary.K_HP]) * w.tune.boss_hp_mul * Bosses.PARTY_HP[n - 1], 0.01)


func test_its_death_clears_the_floor_and_starts_the_lull() -> void:
	var made: Array = _chand_world(2)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	_chand_run(w, e, 8.0)
	assert_false(w.hazards.is_empty())
	w._kill_enemy(e, 0)
	assert_true(w.hazards.is_empty())
	assert_true(w.lull_left > 0.0)
	assert_true(w.boss == null)


func test_a_candle_out_of_reach_is_skipped() -> void:
	var made: Array = _chand_world(2)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	var c := G.ARENA.get_center()
	w.players[0].pos = c + Vector2(-200, 0)
	w.players[1].pos = c + Vector2(200, 0)
	assert_eq(Bosses.candle_spot(w, c + Vector2(0, -100)), Vector2.INF, "no spot reaches both")
	e.enter_dir.y = 1.0
	e.state = BossChandelier.WHEEL_GAP
	e.count = 3.0 # LAST CANDLE is next
	e.timer = 0.0
	var seen := {}
	_chand_run(w, e, 2 * DT, seen)
	for h: Hazards.Hazard in (seen.get("rows", {}) as Dictionary).values():
		assert_true(h.kind != Hazards.SAFE, "a candle nobody could share")
	assert_eq(e.state, BossChandelier.WHEEL_GAP)


func test_no_roll_or_drip_without_its_lane() -> void:
	var made: Array = _chand_world(1)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	while w.add_hazard(Hazards.MARK, Vector2(30, 50), Vector2(40, 50), 2.0, 9.0, 9.0, -1, 0, true) != null:
		pass
	e.state = BossChandelier.GAP
	e.count = 0.0 # DRIP is next
	e.timer = 0.0
	_chand_run(w, e, 2 * DT)
	assert_eq(e.state, BossChandelier.GAP, "dripped with no lane")
	e.enter_dir.y = 1.0
	e.state = BossChandelier.WHEEL_GAP
	e.count = 0.0 # ROLL is next
	e.timer = 0.0
	_chand_run(w, e, 2 * DT)
	assert_eq(e.state, BossChandelier.WHEEL_GAP, "rolled with no lane")
