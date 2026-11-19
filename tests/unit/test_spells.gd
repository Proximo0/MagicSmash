extends TestCase
## Spells: spell weapon stats and evolutions (game/logic/spells.gd), and how they line up with Upgrades.


func test_one_stat_row_and_evolution_per_spell() -> void:
	assert_eq(Spells.COUNT, World.SP_STAR + 1)
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
