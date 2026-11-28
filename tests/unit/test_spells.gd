extends TestCase
## Spells: spell weapon stats and evolutions (game/logic/spells.gd), and how they line up with Upgrades.


func test_one_stat_row_and_evolution_per_spell() -> void:
	assert_eq(Spells.COUNT, World.SP_BLADES + 1)
	assert_eq(Spells.STATS.size(), Spells.COUNT)
	assert_eq(Spells.EVOS.size(), Spells.COUNT)


func test_levels_get_stronger() -> void:
	for sp: int in range(Spells.COUNT):
		for key: String in ["cd", "dmg", "n"]:
			assert_eq((Spells.STATS[sp][key] as Array).size(), Spells.MAX_LEVEL, "%s %s" % [Spells.spell_name(sp), key])
		for lv: int in range(2, Spells.MAX_LEVEL + 1):
			assert_true(Spells.cooldown(sp, lv, 0) <= Spells.cooldown(sp, lv - 1, 0), "%s cd rises at %d" % [Spells.spell_name(sp), lv])
			assert_true(Spells.damage(sp, lv, 0) >= Spells.damage(sp, lv - 1, 0), "%s dmg drops at %d" % [Spells.spell_name(sp), lv])
			assert_true(Spells.count(sp, lv, 0) >= Spells.count(sp, lv - 1, 0), "%s count drops at %d" % [Spells.spell_name(sp), lv])


func test_evolution_beats_max_level() -> void:
	for sp: int in range(Spells.COUNT):
		if not Spells.has_evolution(sp):
			continue
		var top: float = Spells.damage(sp, Spells.MAX_LEVEL, 0) * Spells.count(sp, Spells.MAX_LEVEL, 0) / Spells.cooldown(sp, Spells.MAX_LEVEL, 0)
		var evo: float = Spells.damage(sp, 0, 1) * Spells.count(sp, 0, 1) / Spells.cooldown(sp, 0, 1)
		assert_true(evo > top, "%s evolution %.1f dps-ish is not above level 5's %.1f" % [Spells.spell_name(sp), evo, top])


func test_catalog_matches_spells() -> void:
	for sp: int in range(Spells.COUNT):
		var w: int = Upgrades.weapon_entry(sp)
		var e: int = Upgrades.evo_entry(sp)
		assert_true(Upgrades.is_weapon(w))
		assert_eq(Upgrades.display_name(w), Spells.spell_name(sp))
		assert_eq(Upgrades.max_level(w), Spells.MAX_LEVEL)
		if not Spells.has_evolution(sp):
			assert_eq(e, -1, Spells.spell_name(sp) + " has an evolution row but no EVOS row")
			continue
		assert_true(Upgrades.is_evolution(e))
		assert_eq(Upgrades.display_name(e), str(Spells.EVOS[sp]["name"]))
		assert_eq(Upgrades.description(e), str(Spells.EVOS[sp]["desc"]))
		for evo: int in range(1, Spells.evolutions(sp) + 1):
			var ee: int = Upgrades.evo_entry(sp, evo)
			var row := Spells.evo_row(sp, evo)
			assert_eq(Upgrades.display_name(ee), str(row["name"]))
			assert_eq(Upgrades.description(ee), str(row["desc"]))
			var partner: int = _row_of(Spells.passive_partner(sp, evo))
			assert_true(partner >= 0, Spells.spell_name(sp) + " has no partner")
			assert_eq(Upgrades.kind(partner), Upgrades.PASSIVE, Spells.spell_name(sp) + " pairs with a spell")
			assert_eq(Upgrades.CATALOG[ee][5], [[w, Spells.MAX_LEVEL], [partner, 1]],
				Spells.spell_name(sp) + " evolution requirements do not match its partner")


static func _row_of(key: String) -> int:
	for i: int in range(Upgrades.count()):
		if Upgrades.key(i) == key:
			return i
	return -1


func test_rune_circle_grows_with_level_and_evolution() -> void:
	for lv: int in range(2, Spells.MAX_LEVEL + 1):
		assert_true(Spells.level_value(World.SP_RUNE, "r", lv, 0) >= Spells.level_value(World.SP_RUNE, "r", lv - 1, 0))
		assert_true(Spells.level_value(World.SP_RUNE, "life", lv, 0) >= Spells.level_value(World.SP_RUNE, "life", lv - 1, 0))
	var top_r: float = Spells.level_value(World.SP_RUNE, "r", Spells.MAX_LEVEL, 0)
	var top_life: float = Spells.level_value(World.SP_RUNE, "life", Spells.MAX_LEVEL, 0)
	assert_true(Spells.level_value(World.SP_RUNE, "r", 0, 1) > top_r, "the seal is not bigger")
	assert_true(Spells.level_value(World.SP_RUNE, "life", 0, 1) > top_life, "the seal does not last longer")
	assert_true(Spells.evo_value(World.SP_RUNE, "pull", 1, 0.0) > 0.0, "the seal does not pull")
	assert_eq(Spells.passive_partner(World.SP_RUNE), "magnet")
	assert_eq(Spells.level_value(World.SP_STAR, "speed", 3, 0), Spells.stat(World.SP_STAR, "speed"))


## A rune circle trades single-target damage for area: what one circle deals to one enemy standing in it, per
## second of cooldown, stays under Starfall's at every level (the horde-level balance is checked in sims).
func test_rune_circle_trades_focus_for_area() -> void:
	for lv: int in range(1, Spells.MAX_LEVEL + 1):
		var ticks: float = 1.0 + floorf((Spells.level_value(World.SP_RUNE, "life", lv, 0) - Spells.RUNE_ARM) / Spells.RUNE_TICK)
		var rune: float = Spells.damage(World.SP_RUNE, lv, 0) * ticks / Spells.cooldown(World.SP_RUNE, lv, 0)
		var star: float = Spells.damage(World.SP_STAR, lv, 0) * Spells.count(World.SP_STAR, lv, 0) / Spells.cooldown(World.SP_STAR, lv, 0)
		assert_true(rune < star, "level %d: rune %.2f vs starfall %.2f" % [lv, rune, star])


## Every spell names a cast kind World can cast, and only bolts carry bolt behaviours.
func test_every_spell_has_a_cast_kind() -> void:
	for sp: int in range(Spells.COUNT):
		if not Upgrades.UNBUILT.has(Upgrades.weapon_entry(sp)): # an unbuilt spell's caster comes with its row
			assert_true(WorldCasting.CASTS.has(Spells.cast_kind(sp)), Spells.spell_name(sp) + " has no caster")
		if Spells.cast_kind(sp) != "bolt":
			for key: String in ["jitter", "home", "blast", "slow"]:
				assert_eq(Spells.bolt_value(sp, key, 0, 0.0), 0.0, "%s %s" % [Spells.spell_name(sp), key])
	assert_eq(Spells.bolt_value(World.SP_FROST, "slow", 0, 0.0), Spells.FROST_SLOW)
	assert_eq(Spells.bolt_value(World.SP_FROST, "slow", 1, 0.0), float(Spells.EVOS[World.SP_FROST]["slow"]))
	assert_true(Spells.bolt_value(World.SP_STAR, "home", 0, 0.0) > 0.0)
	assert_true(Spells.bolt_value(World.SP_FIRE, "blast", 0, 0.0) > 0.0)
