extends TestCase
## Tuning: the live-tunable gameplay numbers (game/debug/tuning.gd).

const DT: float = 1.0 / 60.0


func test_defaults_match_fields() -> void:
	var t := Tuning.new()
	for f: Array in Tuning.FIELDS:
		assert_near(float(t.get(f[0])), float(f[1]), 0.0001, str(f[0]))


func test_every_field_has_a_var_and_sane_range() -> void:
	var t := Tuning.new()
	var seen: Dictionary = {}
	for f: Array in Tuning.FIELDS:
		var name: String = f[0]
		assert_false(seen.has(name), "duplicate field " + name)
		seen[name] = true
		assert_true(name in t, "no var for " + name)
		assert_true(float(f[2]) <= float(f[1]) and float(f[1]) <= float(f[3]), name + " default outside its range")
		assert_true(float(f[4]) > 0.0, name + " needs a positive step")
		assert_true(str(f[6]).length() > 0, name + " needs a doc line")


func test_template_rows_are_gone() -> void:
	assert_true(Tuning.field_info("gravity").is_empty())
	assert_true(Tuning.field_info("move_speed").is_empty())


func test_set_value_clamps() -> void:
	var t := Tuning.new()
	assert_true(t.set_value("player_speed", 1000.0))
	assert_near(t.player_speed, 220.0)
	assert_true(t.set_value("player_speed", -5.0))
	assert_near(t.player_speed, 40.0)


func test_unknown_field_rejected() -> void:
	assert_false(Tuning.new().set_value("nope", 1.0))


func test_diff_and_dict_round_trip() -> void:
	var t := Tuning.new()
	t.set_value("player_speed", 130.0)
	assert_eq(t.diff_from_defaults().keys(), ["player_speed"])
	var u := Tuning.new()
	assert_eq(u.apply_dict(t.to_dict()), Tuning.FIELDS.size())
	assert_near(u.player_speed, 130.0)


func test_xp_curve_starts_at_first_level_and_grows() -> void:
	var t := Tuning.new()
	assert_eq(t.xp_to_next(1), int(t.xp_first_level))
	assert_eq(t.xp_to_next(0), t.xp_to_next(1), "levels below 1 count as level 1")
	var prev: int = 0
	for level: int in range(1, 41):
		var need: int = t.xp_to_next(level)
		assert_true(need > prev, "xp_to_next(%d)=%d is not above level %d's %d" % [level, need, level - 1, prev])
		prev = need


func test_spell_cd_mul_scales_cast_rate() -> void:
	# Doubling every spell cooldown halves how often the starting arcane bolt casts.
	var slow := Tuning.new()
	slow.set_value("spell_cd_mul", 2.0)
	var aim_right: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 1.0, 0.0, 0.0, 0.0])
	var counts: Array[int] = []
	for w: World in [World.new([0], 5), World.new([0], 5, slow)]:
		var casts: int = 0
		for _i: int in range(120):
			w.step(1.0 / 60.0, {0: aim_right})
			for ev: Array in w.take_events():
				if ev[0] == World.EV_CAST:
					casts += 1
		counts.append(casts)
	assert_true(counts[0] >= 10, "arcane cast %d times in 2 s" % counts[0])
	assert_true(absi(counts[0] - 2 * counts[1]) <= 1, "casts %d vs %d" % [counts[0], counts[1]])


func test_world_reads_its_tuning() -> void:
	# A faster player tuning moves the wizard further in the same input and time.
	var fast := Tuning.new()
	fast.set_value("player_speed", 200.0)
	var a := World.new([0], 5)
	var b := World.new([0], 5, fast)
	var right: PackedFloat32Array = PackedFloat32Array([1.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var x0: float = (a.players[0] as World.Player).pos.x
	for _i: int in range(30):
		a.step(DT, {0: right})
		b.step(DT, {0: right})
	var da: float = (a.players[0] as World.Player).pos.x - x0
	var db: float = (b.players[0] as World.Player).pos.x - x0
	assert_near(da, 102.0 * 0.5, 0.5, "default speed")
	assert_near(db, 200.0 * 0.5, 0.5, "tuned speed")


func test_faster_horde_rate_spawns_more_enemies() -> void:
	var big := Tuning.new()
	big.set_value("horde_rate_base", 20.0)
	var small := Tuning.new()
	small.set_value("horde_rate_base", 2.0)
	var a := World.new([0], 9, small)
	var b := World.new([0], 9, big)
	# Through the intro and 10 s of fighting.
	for _i: int in range(750):
		a.step(DT, {})
		b.step(DT, {})
	assert_true(b.spawn_queue.size() + b.enemies.size() > 2 * (a.spawn_queue.size() + a.enemies.size()),
		"rate 20 should field far more than rate 2 (%d vs %d)" % [b.spawn_queue.size() + b.enemies.size(), a.spawn_queue.size() + a.enemies.size()])


func test_shared_xp_rows_have_their_defaults_and_ranges() -> void:
	var t := Tuning.new()
	assert_near(t.xp_party_scale, 0.8)
	t.set_value("xp_party_scale", 5.0)
	assert_near(t.xp_party_scale, 2.0, 0.0001, "xp_party_scale is not clamped to 2")


func test_level_up_rows_have_their_defaults_and_the_pick_clock_is_gone() -> void:
	var t := Tuning.new()
	assert_near(t.pick_shock_radius, 44.0)
	assert_near(t.pick_shock_push, 220.0)
	assert_near(t.lull_seconds, 20.0)
	assert_eq(Tuning.field_info("pick_shock_radius")["group"], "XP")
	assert_eq(Tuning.field_info("pick_shock_push")["group"], "XP")
	assert_eq(Tuning.field_info("lull_seconds")["group"], Tuning.field_info("horde_rate_base")["group"])
	t.set_value("pick_shock_radius", -5.0)
	assert_near(t.pick_shock_radius, 0.0, 0.0001, "pick_shock_radius is not clamped to 0")
	t.set_value("pick_shock_push", 9999.0)
	assert_near(t.pick_shock_push, 600.0, 0.0001, "pick_shock_push is not clamped to 600")
	t.set_value("lull_seconds", 99.0)
	assert_near(t.lull_seconds, 60.0, 0.0001, "lull_seconds is not clamped to 60")
	assert_true(Tuning.field_info("pick_seconds").is_empty(), "the pick clock row is still there")
	assert_false("pick_seconds" in t, "the pick clock field is still there")
