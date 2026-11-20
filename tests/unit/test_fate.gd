extends TestCase
## Fate: the fates a reel can draw (World.EV_FATE; later its own module). Pins the neutral defaults the wave 2
## core landed: the event code exists after the lull's and the spell object list is empty.


func test_fate_codes_and_empty_objects() -> void:
	assert_true(World.EV_FATE > World.EV_LULL)
	var codes := [World.EV_DOWN, World.EV_REVIVE, World.EV_CALL, World.EV_REDRAW, World.EV_BANISH, World.EV_FATE,
		World.EV_SLOTS, World.EV_TALK]
	for k: int in codes.size():
		assert_eq(codes[k], World.EV_LULL + 1 + k, "event codes follow EV_LULL in order")
	var w := World.new([0], 3)
	assert_eq((w.snapshot()["o"] as PackedFloat32Array).size(), 0, "no spell objects yet")
