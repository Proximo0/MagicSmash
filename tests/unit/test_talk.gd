extends TestCase
## Talk: the tower's people and their lines (game/logic/talk.gd): every condition has lines, every line fits the
## talk box in two rows, picks do not repeat and the portraits exist in Art's list.


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	return r


func test_every_condition_has_a_line() -> void:
	for sp: int in Talk.CONDITIONS:
		for cond: String in Talk.CONDITIONS[sp]:
			var n := 0
			for l: Array in Talk.LINES:
				if int(l[0]) == sp and l[1] == cond:
					n += 1
			assert_true(n > 0, "speaker %d has no %s line" % [sp, cond])


func test_every_line_uses_a_known_condition_and_speaker() -> void:
	for l: Array in Talk.LINES:
		assert_true(Talk.CONDITIONS.has(int(l[0])), "unknown speaker in " + String(l[2]))
		assert_true((Talk.CONDITIONS[int(l[0])] as Array).has(l[1]), "unknown condition " + String(l[1]))


func test_every_line_fits_two_rows_of_the_box() -> void:
	for l: Array in Talk.LINES:
		var rows := Talk.wrap_rows(String(l[2]))
		assert_true(rows.size() <= Talk.TEXT_ROWS, "too long: " + String(l[2]))
		for row: String in rows:
			assert_true(PixelFont.text_width(row) <= Talk.TEXT_W, "row too wide: " + row)
		for i: int in range(String(l[2]).length()):
			assert_true(PixelFont.GLYPHS.has(String(l[2])[i]), "no glyph for %s in %s" % [String(l[2])[i], l[2]])


func test_line_count_per_speaker() -> void:
	for sp: int in Talk.CONDITIONS:
		var n := Talk.LINES.filter(func(l: Array) -> bool: return int(l[0]) == sp).size()
		assert_true(n >= 8 and n <= 12, "speaker %d has %d lines" % [sp, n])


func test_pick_never_repeats_the_last_line() -> void:
	var r := _rng()
	for sp: int in Talk.CONDITIONS:
		var last := -1
		for _i: int in range(60):
			var l := Talk.pick(sp, {"result": "loss", "act": 1, "seal": 2, "last": last}, r)
			assert_false(l.is_empty())
			assert_true(int(l.id) != last, "repeated line %d" % last)
			last = int(l.id)


func test_conditions_pick_their_lines() -> void:
	var r := _rng()
	assert_eq(Talk.LINES[Talk.pick(Talk.MORVANE, {"first": true}, r).id][1], "first")
	assert_eq(Talk.LINES[Talk.pick(Talk.CARD_READER, {"new_card": true}, r).id][1], "new_card")
	assert_eq(Talk.LINES[Talk.pick(Talk.MORVANE, {"lull": true, "act": 2}, r).id][1], "act3")
	for _i: int in range(20):
		var l := Talk.pick(Talk.MORVANE, {"result": "win"}, r)
		assert_true(["win", "idle"].has(Talk.LINES[l.id][1]))
	var ids := Talk.candidates(Talk.SHOPKEEPER, {"seal": 3, "apprentice": true, "act": 0, "result": "win"})
	var conds: Array = ids.map(func(i: int) -> String: return Talk.LINES[i][1])
	for c: String in ["win", "act1", "seal", "apprentice", "idle"]:
		assert_true(conds.has(c), "missing " + c)


func test_empty_context_falls_back_to_idle() -> void:
	for sp: int in Talk.CONDITIONS:
		assert_eq(Talk.LINES[Talk.pick(sp, {}, _rng()).id][1], "idle")


func test_portraits_exist_in_art() -> void:
	for sp: Array in Talk.SPEAKERS:
		assert_true(Art.wanted().has(["portraits/characters", sp[1]]), sp[1])
		assert_true(Art.wanted().has(["portraits/characters", sp[1] + "_tall"]), sp[1])


func test_wrap_rows() -> void:
	assert_eq(Talk.wrap_rows("AB CD EF", 5), ["AB CD", "EF"] as Array[String])
	assert_eq(Talk.wrap_rows("", 5).size(), 0)
