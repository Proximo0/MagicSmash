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


func test_evolution_needs_max_weapon_and_partner() -> void:
	var levels: Dictionary = {}
	var evo: int = Upgrades.evo_entry(World.SP_FIRE)
	levels[Upgrades.weapon_entry(World.SP_FIRE)] = Spells.MAX_LEVEL - 1
	levels[Upgrades.NOVA] = 1
	assert_false(Upgrades.available(levels, evo), "offered before fireball is maxed")
	levels[Upgrades.weapon_entry(World.SP_FIRE)] = Spells.MAX_LEVEL
	levels.erase(Upgrades.NOVA)
	assert_false(Upgrades.available(levels, evo), "offered without THE TOWER")
	levels[Upgrades.NOVA] = 1
	assert_true(Upgrades.available(levels, evo))
	assert_true(Upgrades.take(levels, evo))
	assert_true(Upgrades.evolved(levels, World.SP_FIRE))
	assert_false(Upgrades.available(levels, evo), "an evolution is taken once")


func test_new_weapons_are_offered() -> void:
	var seen: Dictionary = {}
	for s: int in range(1, 40):
		for idx: int in Upgrades.roll(_rng(s), {}, 3):
			if Upgrades.is_weapon(idx):
				seen[idx] = true
			assert_false(Upgrades.is_evolution(idx), "evolution offered from nothing")
	# Every built spell but CLEAVE, a class weapon only a knight starts with (its row requires itself).
	var unbuilt := 0
	for sp: int in range(Spells.COUNT):
		if Upgrades.UNBUILT.has(Upgrades.weapon_entry(sp)):
			unbuilt += 1
			assert_false(seen.has(Upgrades.weapon_entry(sp)), "an unbuilt spell offered")
	assert_eq(seen.size(), Spells.COUNT - 1 - unbuilt, "weapons offered: %s" % [seen.keys()])
	assert_false(seen.has(Upgrades.W_CLEAVE), "CLEAVE offered to a wizard who does not hold it")


func test_names_and_effects_fit_a_tray_row() -> void:
	# The level-up tray shows each card as one row: the title (Upgrades.row_name) on one line, the effect beside the
	# level on the next.
	var longest_name := ""
	var longest_effect := ""
	for i: int in Upgrades.count():
		var name := Upgrades.row_name(i)
		var effect := Upgrades.description(i)
		assert_true(name.length() <= TarotArt.ROW_TITLE_CHARS, "%s: name longer than %d" % [name, TarotArt.ROW_TITLE_CHARS])
		assert_true(effect.length() <= TarotArt.ROW_EFFECT_CHARS, "%s: effect '%s' longer than %d" % [name, effect, TarotArt.ROW_EFFECT_CHARS])
		if name.length() > longest_name.length():
			longest_name = name
		if effect.length() > longest_effect.length():
			longest_effect = effect
	# A row is 116 px: 11 for the button, then the text; the effect keeps 4 px clear of the 3-letter level at the
	# right edge (each glyph run has a 1 px outline).
	assert_true(11 + PixelFont.text_width(longest_name) + 1 <= 116, "%s does not fit a row" % longest_name)
	assert_true(11 + PixelFont.text_width(longest_effect) + 4 + PixelFont.text_width("2/5") <= 116,
		"%s does not fit beside the level" % longest_effect)


## CUPS heals a heart (WorldLevels); "+1 HEART" is what the cards say for one more heart to hold.
func test_cups_says_it_heals() -> void:
	var row: Array = Upgrades.CATALOG[Upgrades.M_CUPS]
	assert_eq(str(row[0]), "cups")
	assert_true(str(row[2]).begins_with("HEAL"), "CUPS reads '%s'" % str(row[2]))

