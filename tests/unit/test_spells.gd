extends TestCase
## Spells: spell weapon stats and evolutions (game/logic/spells.gd), and how they line up with Upgrades.


func test_one_stat_row_and_evolution_per_spell() -> void:
	assert_eq(Spells.COUNT, World.SP_RUNE + 1)
	assert_eq(Spells.STATS.size(), Spells.COUNT)
	assert_eq(Spells.EVOS.size(), Spells.COUNT)


func test_levels_get_stronger() -> void:
	for sp: int in range(Spells.COUNT):
		for key: String in ["cd", "dmg", "n"]:
			assert_eq((Spells.STATS[sp][key] as Array).size(), Spells.MAX_LEVEL, "%s %s" % [Spells.spell_name(sp), key])
		for lv: int in range(2, Spells.MAX_LEVEL + 1):
			assert_true(Spells.cooldown(sp, lv, false) <= Spells.cooldown(sp, lv - 1, false), "%s cd rises at %d" % [Spells.spell_name(sp), lv])
			assert_true(Spells.damage(sp, lv, false) >= Spells.damage(sp, lv - 1, false), "%s dmg drops at %d" % [Spells.spell_name(sp), lv])
			assert_true(Spells.count(sp, lv, false) >= Spells.count(sp, lv - 1, false), "%s count drops at %d" % [Spells.spell_name(sp), lv])


func test_evolution_beats_max_level() -> void:
	for sp: int in range(Spells.COUNT):
		var top: float = Spells.damage(sp, Spells.MAX_LEVEL, false) * Spells.count(sp, Spells.MAX_LEVEL, false) / Spells.cooldown(sp, Spells.MAX_LEVEL, false)
		var evo: float = Spells.damage(sp, 0, true) * Spells.count(sp, 0, true) / Spells.cooldown(sp, 0, true)
		assert_true(evo > top, "%s evolution %.1f dps-ish is not above level 5's %.1f" % [Spells.spell_name(sp), evo, top])


func test_catalog_matches_spells() -> void:
	for sp: int in range(Spells.COUNT):
		var w: int = Upgrades.weapon_entry(sp)
		var e: int = Upgrades.evo_entry(sp)
		assert_true(Upgrades.is_weapon(w) and Upgrades.is_evolution(e))
		assert_eq(Upgrades.display_name(w), Spells.spell_name(sp))
		assert_eq(Upgrades.max_level(w), Spells.MAX_LEVEL)
		assert_eq(Upgrades.display_name(e), str(Spells.EVOS[sp]["name"]))
		assert_eq(Upgrades.description(e), str(Spells.EVOS[sp]["desc"]))
		assert_true(Spells.partner(sp) != sp, Spells.spell_name(sp) + " partners itself")
		assert_eq(Upgrades.CATALOG[e][5], [[w, Spells.MAX_LEVEL], [Upgrades.weapon_entry(Spells.partner(sp)), 1]],
			Spells.spell_name(sp) + " evolution requirements do not match its partner")


func test_rune_circle_grows_with_level_and_evolution() -> void:
	for lv: int in range(2, Spells.MAX_LEVEL + 1):
		assert_true(Spells.level_value(World.SP_RUNE, "r", lv, false) >= Spells.level_value(World.SP_RUNE, "r", lv - 1, false))
		assert_true(Spells.level_value(World.SP_RUNE, "life", lv, false) >= Spells.level_value(World.SP_RUNE, "life", lv - 1, false))
	var top_r: float = Spells.level_value(World.SP_RUNE, "r", Spells.MAX_LEVEL, false)
	var top_life: float = Spells.level_value(World.SP_RUNE, "life", Spells.MAX_LEVEL, false)
	assert_true(Spells.level_value(World.SP_RUNE, "r", 0, true) > top_r, "the seal is not bigger")
	assert_true(Spells.level_value(World.SP_RUNE, "life", 0, true) > top_life, "the seal does not last longer")
	assert_true(Spells.evo_value(World.SP_RUNE, "pull", 0.0) > 0.0, "the seal does not pull")
	assert_eq(Spells.partner(World.SP_RUNE), World.SP_STAR)
	assert_eq(Spells.level_value(World.SP_STAR, "speed", 3, false), Spells.stat(World.SP_STAR, "speed"))


## A rune circle trades single-target damage for area: what one circle deals to one enemy standing in it, per
## second of cooldown, stays under Starfall's at every level (the horde-level balance is checked in sims).
func test_rune_circle_trades_focus_for_area() -> void:
	for lv: int in range(1, Spells.MAX_LEVEL + 1):
		var ticks: float = 1.0 + floorf((Spells.level_value(World.SP_RUNE, "life", lv, false) - Spells.RUNE_ARM) / Spells.RUNE_TICK)
		var rune: float = Spells.damage(World.SP_RUNE, lv, false) * ticks / Spells.cooldown(World.SP_RUNE, lv, false)
		var star: float = Spells.damage(World.SP_STAR, lv, false) * Spells.count(World.SP_STAR, lv, false) / Spells.cooldown(World.SP_STAR, lv, false)
		assert_true(rune < star, "level %d: rune %.2f vs starfall %.2f" % [lv, rune, star])


## Every spell names a cast kind World can cast, and only bolts carry bolt behaviours.
func test_every_spell_has_a_cast_kind() -> void:
	for sp: int in range(Spells.COUNT):
		assert_true(WorldCasting.CASTS.has(Spells.cast_kind(sp)), Spells.spell_name(sp) + " has no caster")
		if Spells.cast_kind(sp) != "bolt":
			for key: String in ["jitter", "home", "blast", "slow"]:
				assert_eq(Spells.bolt_value(sp, key, false, 0.0), 0.0, "%s %s" % [Spells.spell_name(sp), key])
	assert_eq(Spells.bolt_value(World.SP_FROST, "slow", false, 0.0), Spells.FROST_SLOW)
	assert_eq(Spells.bolt_value(World.SP_FROST, "slow", true, 0.0), float(Spells.EVOS[World.SP_FROST]["slow"]))
	assert_true(Spells.bolt_value(World.SP_STAR, "home", false, 0.0) > 0.0)
	assert_true(Spells.bolt_value(World.SP_FIRE, "blast", false, 0.0) > 0.0)
