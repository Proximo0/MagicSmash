extends TestCase
## ArenaBg: the baked backdrop of each act (game/arena/arena_bg.gd, game/art/arena_art_*.gd). The art contract
## says the floor is the quietest layer on screen: dark, with no flagstone much brighter than the one beside it.


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func test_each_act_bakes_a_dark_floor() -> void:
	var a := Rect2i(G.ARENA)
	for act in ArenaBg.ACTS:
		var img := ArenaBg.build(act).get_image()
		assert_eq(img.get_size(), Vector2i(G.WORLD), "act %d size" % act)
		var sum := 0.0
		var n := 0
		var bright := 0
		for y in range(a.position.y, a.end.y, 3):
			for x in range(a.position.x, a.end.x, 3):
				var l := _luma(img.get_pixel(x, y))
				sum += l
				n += 1
				if l > 0.45:
					bright += 1
		assert_true(sum / n < 0.22, "act %d floor luminance %.3f is over the budget" % [act, sum / n])
		assert_true(float(bright) / n < 0.01, "act %d has %d bright floor samples" % [act, bright])


func test_neighbouring_flagstones_are_close() -> void:
	var w := int(G.WORLD.x)
	for act in ArenaBg.ACTS:
		var img := ArenaBg.build(act).get_image()
		var ids := ArenaBg.stone_map(act)
		# The step across each joint, a few pixels either side of it, averaged per pair of stones.
		var pairs := {}
		for y in range(int(G.ARENA.position.y), int(G.ARENA.end.y), 2):
			for x in range(int(G.ARENA.position.x), int(G.ARENA.end.x) - 3):
				var id := ids[y * w + x]
				var other := ids[y * w + x + 2]
				if id < 0 or other < 0 or id == other:
					continue
				var key := Vector2i(mini(id, other), maxi(id, other))
				var acc: Array = pairs.get(key, [0.0, 0])
				acc[0] += absf(_luma(img.get_pixel(x, y)) - _luma(img.get_pixel(x + 2, y)))
				acc[1] += 1
				pairs[key] = acc
		var worst := 0.0
		for key: Vector2i in pairs:
			var acc: Array = pairs[key]
			if acc[1] >= 5:
				worst = maxf(worst, acc[0] / acc[1])
		assert_true(pairs.size() > 100, "act %d has a stone map" % act)
		assert_true(worst < 0.09, "act %d: two flagstones %.3f apart" % [act, worst])


func test_scene_has_what_the_arena_draws() -> void:
	for act in ArenaBg.ACTS:
		var s := ArenaBg.scene(act)
		assert_true(s.has("flames") and s.has("glows") and s.has("doors"), "act %d scene keys" % act)
		assert_true(s.flames.size() >= 8, "act %d has lamps" % act)
		assert_eq(s.doors.size(), World.DOORS.size(), "act %d doors" % act)
		for i in World.DOORS.size():
			var r: Rect2 = s.doors[i]
			assert_true(r.grow(12.0).has_point(World.DOORS[i]), "act %d door %d is where monsters come in" % [act, i])
		for f: Array in s.flames:
			assert_true(Rect2(Vector2.ZERO, G.WORLD).has_point(f[0]), "act %d flame on the picture" % act)


func test_bake_is_the_same_every_time() -> void:
	var a := ArenaArtOssuary.bake({})
	var b := ArenaArtOssuary.bake({})
	assert_true(a.get_data() == b.get_data(), "the Ossuary bakes to the same picture twice")
