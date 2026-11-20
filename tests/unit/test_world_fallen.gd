extends TestCase
## World fallen wizards: going down, graves, revives and the wipe (game/logic/world.gd, world/players.gd).
## Pins the neutral defaults the wave 2 core landed.


func test_nobody_is_down_by_default() -> void:
	var w := World.new([0, 1], 3)
	for p: World.Player in w.players.values():
		assert_false(p.down)
		assert_near(p.down_left, 0.0)
		assert_near(p.down_t, 0.0)
		assert_near(p.revive, 0.0)
		assert_eq(p.rituals, 0)
		assert_near(p.call_t, 0.0)
		assert_true(w.can_return(p), "a wizard with lives left can come back")
	assert_true(w.graves().is_empty())
	assert_near(w.tune.down_spawn_weight, 1.0)
	var pl: PackedFloat32Array = w.snapshot()["p"]
	assert_eq(pl[World.P_DOWN], 0.0)
	assert_eq(pl[World.P_REVIVE], 0.0)
	# A downed wizard shows up as a grave (the shape later jobs fill).
	var p: World.Player = w.players[1]
	p.down = true
	p.down_left = 4.0
	assert_eq(w.graves(), [[1, p.pos.x, p.pos.y, 0.0, 4.0]])
