extends TestCase
## World builds: spell and passive slots, the catalogue's kind and spell columns, redraws and banishes
## (game/logic/upgrades.gd, game/logic/world/levels.gd). Pins the neutral defaults the wave 2 core landed.


func test_neutral_build_defaults() -> void:
	var w := World.new([0], 3)
	var p: World.Player = w.players[0]
	assert_eq(w.slot_cap(), Upgrades.UNCAPPED, "no slot cap until the slots job lands")
	assert_eq(p.redraws, 0)
	assert_eq(p.banishes, 0)
	assert_true(p.banned.is_empty())
	assert_eq(Upgrades.slots_used(p.upgrades), Vector2i(1, 0), "the starting spell takes one spell slot")
	assert_eq(Upgrades.slot_ids(p.upgrades, Upgrades.SPELL), [Upgrades.weapon_entry(Wizards.start_spell(0))] as Array[int])
	# Every row has a kind, and SPELL / EVOLUTION rows name their spell; today's ids stay.
	assert_eq(Upgrades.kind(Upgrades.POWER), Upgrades.PASSIVE)
	assert_eq(Upgrades.kind(Upgrades.NOVA), Upgrades.INSTANT)
	for sp: int in Spells.COUNT:
		assert_eq(Upgrades.spell_of(Upgrades.weapon_entry(sp)), sp)
		assert_eq(Upgrades.kind(Upgrades.evo_entry(sp)), Upgrades.EVOLUTION)
		assert_eq(Upgrades.evolves(Upgrades.evo_entry(sp)), Upgrades.weapon_entry(sp))
	assert_eq(Upgrades.weapon_entry(World.SP_ARCANE), Upgrades.W_ARCANE)
	assert_eq(Upgrades.evo_entry(World.SP_RUNE), Upgrades.E_RUNE)
	assert_eq(Upgrades.evolves(Upgrades.POWER), -1)
	# A cap and a banishment bind only when given.
	var lv := {Upgrades.W_FIRE: 1}
	assert_true(Upgrades.available(lv, Upgrades.W_FROST))
	assert_false(Upgrades.available(lv, Upgrades.W_FROST, Vector2i(1, 1)), "a full spell slot")
	assert_true(Upgrades.available(lv, Upgrades.W_FIRE, Vector2i(1, 1)), "a spell owned levels up past the cap")
	assert_false(Upgrades.available(lv, Upgrades.POWER, Vector2i(4, 0)), "no passive slot")
	assert_false(Upgrades.available(lv, Upgrades.POWER, Upgrades.UNCAPPED, {Upgrades.POWER: true}), "banished")
	assert_true(Upgrades.pick_score(lv, Upgrades.E_FIRE) > Upgrades.pick_score(lv, Upgrades.W_FIRE))
	assert_true(Upgrades.pick_score(lv, Upgrades.W_FIRE) > Upgrades.pick_score(lv, Upgrades.POWER))
