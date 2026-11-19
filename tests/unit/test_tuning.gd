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


func test_cast_cd_maps_each_spell() -> void:
	var t := Tuning.new()
	assert_near(t.cast_cd(World.SP_ARCANE), t.cast_cd_arcane)
	assert_near(t.cast_cd(World.SP_FIRE), t.cast_cd_fire)
	assert_near(t.cast_cd(World.SP_FROST), t.cast_cd_frost)
	assert_near(t.cast_cd(World.SP_STORM), t.cast_cd_storm)
	assert_near(t.cast_cd(World.SP_STAR), t.cast_cd_star)


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


func test_bigger_spawn_budget_queues_more_enemies() -> void:
	var big := Tuning.new()
	big.set_value("spawn_budget_base", 120.0)
	var a := World.new([0], 9)
	var b := World.new([0], 9, big)
	# Step through the intro so the first wave is built.
	for _i: int in range(200):
		a.step(DT, {})
		b.step(DT, {})
	assert_true(b.spawn_queue.size() + b.enemies.size() > a.spawn_queue.size() + a.enemies.size(),
		"budget 120 should queue more than budget 18")
