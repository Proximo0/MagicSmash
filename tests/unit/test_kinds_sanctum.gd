extends TestCase
## KindsSanctum: the COMET SHARD and the TEN OF SWORDS (game/logic/kinds_sanctum.gd).

const DT := 1.0 / 60.0


func _sanc_world() -> World:
	var w := World.new([0], 5)
	w.phase = World.PH_FIGHT
	for p: World.Player in w.players.values():
		p.invuln = 999.0
	return w


## Runs the enemies and the hazard rows `secs` seconds, the way World.step orders them, with no horde.
func _sanc_tick(w: World, secs: float) -> void:
	for _i: int in range(roundi(secs / DT)):
		w._build_grid()
		w._plist.assign(w.players.values())
		for e: World.Enemy in w.enemies:
			if not e.dead:
				WorldEnemies._update_enemy(w, e, DT)
		WorldHazards._update_hazards(w, DT)
		WorldEnemies._update_eshots(w, DT)
		w.enemies = w.enemies.filter(func(e: World.Enemy) -> bool: return not e.dead)
		w.eshots = w.eshots.filter(func(s: World.EShot) -> bool: return not s.dead)


func _shards(w: World) -> Array:
	return w.enemies.filter(func(e: World.Enemy) -> bool: return e.type == Bestiary.SHARD and not e.dead)


func _row(w: World, kind: int) -> Hazards.Hazard:
	for h: Hazards.Hazard in w.hazards:
		if h.kind == kind:
			return h
	return null


## A seed risen 100 px from the party, run until its shard has landed. Returns the landed shard.
func _landed(w: World) -> World.Enemy:
	var c := w.party_center()
	w.spawn_enemy(Bestiary.SHARD, 0, c + Vector2(100, 0))
	_sanc_tick(w, DT)
	assert_eq(_shards(w).size(), 0, "the seed goes")
	var fall := _row(w, Hazards.FALL)
	assert_true(fall != null, "a FALL warns where it lands")
	assert_near(fall.r, KindsSanctum.SHARD_FALL_R)
	assert_near(fall.warn, KindsSanctum.SHARD_FALL_WARN, 0.02)
	assert_true(fall.a.distance_to(c) >= KindsSanctum.SHARD_MIN - 0.5 and fall.a.distance_to(c) <= KindsSanctum.SHARD_MAX + 0.5)
	_sanc_tick(w, KindsSanctum.SHARD_FALL_WARN + 2.0 * DT)
	var s: Array = _shards(w)
	assert_eq(s.size(), 1, "the shard lands as the FALL turns hot")
	assert_eq((s[0] as World.Enemy).pos, fall.a)
	return s[0]


func test_shard_beam_turns_0_6_rad_s_and_burns_out_at_30_s() -> void:
	var w := _sanc_world()
	var e := _landed(w)
	assert_eq(e.state, KindsSanctum.SS_IDLE)
	_sanc_tick(w, KindsSanctum.SHARD_BEAM_AT + 0.1)
	var beam := _row(w, Hazards.BEAM)
	assert_true(beam != null, "the beam warns after 1.5 s")
	assert_near(beam.a.distance_to(beam.b), KindsSanctum.SHARD_BEAM_LEN, 0.01)
	var p: World.Player = w.players[0]
	assert_near(absf((beam.b - beam.a).angle_to(p.pos - e.pos)), PI, 0.01, "away from the only wizard")
	_sanc_tick(w, KindsSanctum.SHARD_BEAM_WARN)
	assert_true(beam.warn <= 0.0)
	var a0 := (beam.b - beam.a).angle()
	_sanc_tick(w, 1.0)
	assert_near(absf(angle_difference(a0, (beam.b - beam.a).angle())), KindsSanctum.SHARD_SPIN, 0.02)
	assert_near(beam.a.distance_to(beam.b), KindsSanctum.SHARD_BEAM_LEN, 0.01)
	_sanc_tick(w, KindsSanctum.SHARD_LIFE - e.timer2 - 0.1)
	assert_eq(_shards(w).size(), 1, "still burning just before 30 s")
	assert_true(w.hazards.has(beam))
	_sanc_tick(w, 0.2)
	assert_eq(_shards(w).size(), 0, "burnt out")
	assert_false(w.hazards.has(beam), "the beam goes with it")


func test_a_broken_shard_takes_its_beam() -> void:
	var w := _sanc_world()
	var e := _landed(w)
	_sanc_tick(w, KindsSanctum.SHARD_BEAM_AT + KindsSanctum.SHARD_BEAM_WARN + 0.5)
	assert_true(_row(w, Hazards.BEAM) != null)
	w.damage_enemy(e, 999.0, 0, Vector2.ZERO)
	_sanc_tick(w, DT)
	assert_true(_row(w, Hazards.BEAM) == null)


func test_shards_keep_apart_and_the_cap_counts_falls() -> void:
	var w := _sanc_world()
	var c := w.party_center()
	var cap := Bestiary.cap_of(Bestiary.horde_row(Bestiary.SHARD), 1)
	for i: int in range(cap + 2):
		w.spawn_enemy(Bestiary.SHARD, 0, c + Vector2.from_angle(i * 0.3) * 100.0)
	_sanc_tick(w, DT)
	var falls: Array = w.hazards.filter(func(h: Hazards.Hazard) -> bool: return h.kind == Hazards.FALL)
	assert_eq(falls.size(), cap, "no more falls than the cap")
	for i: int in range(falls.size()):
		for j: int in range(i):
			assert_true((falls[i] as Hazards.Hazard).a.distance_to((falls[j] as Hazards.Hazard).a) >= 120.0, "shards land apart")


func test_widest_gap() -> void:
	var w := World.new([0, 1], 5)
	var a: World.Player = w.players[0]
	var b: World.Player = w.players[1]
	a.pos = Vector2(300, 200)
	b.pos = Vector2(200, 300)
	var ang := KindsSanctum.widest_gap(w, Vector2(200, 200))
	assert_near(absf(angle_difference(ang, deg_to_rad(-135.0))), 0.0, 0.01)


func test_swords_kneel_then_fire_ten() -> void:
	var w := _sanc_world()
	var p: World.Player = w.players[0]
	var e := w.spawn_enemy(Bestiary.SWORDS, 0, p.pos + Vector2(120, 0))
	w.damage_enemy(e, 999.0, 0, Vector2.ZERO)
	var h := _row(w, Hazards.BURST)
	assert_true(h != null, "it kneels")
	assert_near(h.r, KindsSanctum.SWORDS_BURST_R)
	assert_near(h.warn, KindsSanctum.SWORDS_KNEEL)
	assert_eq(w.eshots.size(), 0)
	_sanc_tick(w, KindsSanctum.SWORDS_KNEEL - 0.05)
	assert_eq(w.eshots.size(), 0, "no blades while it kneels")
	_sanc_tick(w, 0.1)
	assert_eq(w.eshots.size(), KindsSanctum.SWORDS_RING)
	for s: World.EShot in w.eshots:
		assert_eq(s.kind, Bestiary.ES_SWORD)
		assert_near(s.vel.length(), Hazards.SHOT_SPEED, 0.01)
		assert_near(s.life, Hazards.SHOT_LIFE, 0.1)


func test_swords_fire_none_past_the_shot_cap() -> void:
	var w := _sanc_world()
	var p: World.Player = w.players[0]
	for i: int in range(Bestiary.ESHOT_CAP - 4):
		var s := w.eshot(World.ES_ORB, G.ARENA.get_center() + Vector2(-150, 0), Vector2.ZERO, 3.0)
		s.life = 99.0
	var e := w.spawn_enemy(Bestiary.SWORDS, 0, p.pos + Vector2(120, 0))
	w.damage_enemy(e, 999.0, 0, Vector2.ZERO)
	_sanc_tick(w, KindsSanctum.SWORDS_KNEEL + 0.1)
	assert_eq(w.eshots.size(), Bestiary.ESHOT_CAP)
	var swords := w.eshots.filter(func(s: World.EShot) -> bool: return s.kind == Bestiary.ES_SWORD).size()
	assert_eq(swords, 4, "only the room left under the cap")
