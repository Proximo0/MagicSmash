extends TestCase
## Upgrades: the level-up catalogue, seeded roll and effect values (game/logic/upgrades.gd).


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func test_catalog_rows_are_well_formed() -> void:
	var keys: Dictionary = {}
	for i: int in range(Upgrades.count()):
		var row: Array = Upgrades.CATALOG[i]
		assert_false(keys.has(row[0]), "duplicate key " + str(row[0]))
		keys[row[0]] = true
		assert_true(float(row[3]) > 0.0, str(row[0]) + " needs a positive weight")
		assert_true(Upgrades.max_level(i) >= 1, str(row[0]) + " needs at least one level")
		# Names and descriptions must fit a 140 px pick card (6 px per glyph at scale 1).
		assert_true(PixelFont.text_width(Upgrades.display_name(i), 1) <= 134, str(row[0]) + " name too wide")
		assert_true(PixelFont.text_width(Upgrades.description(i), 1) <= 134, str(row[0]) + " description too wide")


func test_roll_gives_distinct_choices() -> void:
	var out: Array[int] = Upgrades.roll(_rng(1), {}, 3)
	assert_eq(out.size(), 3)
	assert_true(out[0] != out[1] and out[1] != out[2] and out[0] != out[2], "duplicates in %s" % [out])


func test_roll_is_seeded() -> void:
	assert_eq(Upgrades.roll(_rng(42), {}, 3), Upgrades.roll(_rng(42), {}, 3))
	var differs := false
	for s: int in range(1, 20):
		if Upgrades.roll(_rng(s), {}, 3) != Upgrades.roll(_rng(42), {}, 3):
			differs = true
	assert_true(differs, "every seed rolled the same offer")


func test_roll_skips_maxed_and_runs_dry() -> void:
	var levels: Dictionary = {}
	for i: int in range(Upgrades.count()):
		levels[i] = Upgrades.max_level(i)
	levels.erase(Upgrades.POWER)
	assert_eq(Upgrades.roll(_rng(3), levels, 3), [Upgrades.POWER] as Array[int])
	levels[Upgrades.POWER] = Upgrades.max_level(Upgrades.POWER)
	assert_true(Upgrades.roll(_rng(3), levels, 3).is_empty())


func test_take_levels_up_to_max() -> void:
	var levels: Dictionary = {}
	for _i: int in range(Upgrades.max_level(Upgrades.MAGNET)):
		assert_true(Upgrades.take(levels, Upgrades.MAGNET))
	assert_false(Upgrades.take(levels, Upgrades.MAGNET), "took past max level")
	assert_false(Upgrades.take(levels, -1))
	assert_false(Upgrades.take(levels, Upgrades.count()))


func test_effect_values_follow_level() -> void:
	var levels: Dictionary = {}
	assert_near(Upgrades.damage_mul(levels), 1.0)
	assert_near(Upgrades.regen_interval(levels), 0.0)
	Upgrades.take(levels, Upgrades.POWER)
	assert_near(Upgrades.damage_mul(levels), 1.15)
	Upgrades.take(levels, Upgrades.POWER)
	assert_near(Upgrades.damage_mul(levels), 1.30)
	Upgrades.take(levels, Upgrades.QUICK)
	assert_true(Upgrades.cast_mul(levels) < 1.0, "quick cast should shorten cooldowns")
	Upgrades.take(levels, Upgrades.SWIFT)
	assert_true(Upgrades.move_mul(levels) > 1.0)
