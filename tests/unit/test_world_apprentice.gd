extends TestCase
## World apprentices: computer wizards that fill a seat (game/logic/world.gd humans and pscale).
## Pins the neutral defaults the wave 2 core landed.


func test_every_wizard_is_human_by_default() -> void:
	var w := World.new([0, 1, 2], 3)
	assert_eq(w.humans().size(), 3)
	for p: World.Player in w.players.values():
		assert_false(p.ai)
		assert_eq(p.trait_a, 0)
		assert_eq(p.trait_b, 0)
	assert_near(w.tune.apprentice_scale, 1.0)
	assert_near(w.pscale(), 1.0 + w.tune.spawn_party_scale * 2.0, 0.0001, "three full wizards")
	var pl: PackedFloat32Array = w.snapshot()["p"]
	assert_eq(pl[World.P_AI], 0.0)
	for k: int in [World.P_RACE, World.P_CLASS, World.P_LOOK, World.P_CLASS_LEVEL]:
		assert_eq(pl[k], 0.0, "races and classes are reserved at 0")
	assert_near(w.players[0].threat, 1.0)
	var seated := World.new([0], 3, null, {}, {0: {"ai": false, "race": 2, "cls": 1, "look": 5, "cls_level": 3}})
	var row: PackedFloat32Array = seated.snapshot()["p"]
	assert_eq([int(row[World.P_RACE]), int(row[World.P_CLASS]), int(row[World.P_LOOK]), int(row[World.P_CLASS_LEVEL])],
		[2, 1, 5, 3], "roster extras pass through to the row untouched")
	w.players[2].ai = true
	assert_eq(w.humans().size(), 2)
	assert_eq(G.DEV_AI, -2)
	assert_eq(G.DEV_KB2, -3)
