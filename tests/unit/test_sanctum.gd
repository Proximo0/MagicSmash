extends TestCase
## Sanctum: walking, pots, the tired wall and the things to use (game/logic/sanctum.gd).

const DT := 1.0 / 60.0


func _walk(s: Sanctum, dir: Vector2, seconds: float) -> void:
	for _i: int in range(int(seconds / DT)):
		s.step(DT, dir)


func test_walls_hold_the_wizard_in() -> void:
	var s := Sanctum.new(1)
	_walk(s, Vector2.LEFT, 10.0)
	assert_true(Sanctum.ROOM.has_point(s.pos), "walked out of the room at %s" % s.pos)
	_walk(s, Vector2.DOWN, 10.0)
	assert_true(Sanctum.ROOM.has_point(s.pos), "walked out of the room at %s" % s.pos)


func test_walking_into_a_pot_breaks_it_once() -> void:
	var s := Sanctum.new(1)
	s.pos = Sanctum.POTS[5] + Vector2(20, 0)
	_walk(s, Vector2.LEFT, 1.0)
	assert_true(s.broken[5], "the pot did not break")
	var pots := 0
	for e: Array in s.take_events():
		if e[0] == Sanctum.EV_POT:
			pots += 1
			assert_eq(e[1], 5)
	assert_eq(pots, 1)
	_walk(s, Vector2.RIGHT, 0.3)
	_walk(s, Vector2.LEFT, 0.5)
	assert_true(s.take_events().filter(func(e: Array) -> bool: return e[0] == Sanctum.EV_POT).is_empty(), "a broken pot broke again")


func test_pots_start_broken_until_the_next_run() -> void:
	var s := Sanctum.new(1, true)
	for b: bool in s.broken:
		assert_true(b)


func test_pots_hold_crystals_and_rarely_cards() -> void:
	var got := {"": 0, "crystals": 0, "card": 0}
	for seed_value: int in range(400):
		var s := Sanctum.new(seed_value)
		s._break_pot(0)
		var what: Array = s.take_events()[0][2]
		got[what[0]] += 1
	assert_true(got["crystals"] > 80 and got["crystals"] < 250, "crystal pots: %d of 400" % got["crystals"])
	assert_true(got["card"] < 20, "too many cards in pots: %d" % got["card"])


func test_pushing_the_cracked_wall_opens_the_alcove() -> void:
	var s := Sanctum.new(1)
	s.pos = Vector2(412, Sanctum.ROOM.position.y + 6)
	_walk(s, Vector2.UP, Sanctum.CRACK_PUSH * 0.5)
	assert_false(s.crack_open, "the wall opened too soon")
	_walk(s, Vector2.UP, Sanctum.CRACK_PUSH + 0.2)
	assert_true(s.crack_open, "the wall did not give way")
	_walk(s, Vector2.UP, 1.0)
	assert_true(Sanctum.ALCOVE.has_point(s.pos), "did not reach the alcove: %s" % s.pos)
	var codes: Array = s.take_events().map(func(e: Array) -> int: return e[0])
	assert_true(codes.has(Sanctum.EV_CRACK) and codes.has(Sanctum.EV_ALCOVE))
	assert_eq(s.near_thing(), Sanctum.CAT)


func test_a_plain_wall_does_not_open() -> void:
	var s := Sanctum.new(1)
	s.pos = Vector2(240, Sanctum.ROOM.position.y + 6)
	_walk(s, Vector2.UP, 5.0)
	assert_false(s.crack_open)


func test_use_reaches_the_nearest_thing() -> void:
	var s := Sanctum.new(1)
	s.pos = Sanctum.THINGS[Sanctum.WELL][1] + Vector2(-10, 0)
	assert_eq(s.use(), Sanctum.WELL)
	s.pos = Vector2(240, 180)
	assert_eq(s.use(), -1)


func test_sealed_decks_draw_the_lich_rarely() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var lich := 0
	for _i: int in range(2000):
		var idx := Sanctum.roll_card(r)
		assert_true(idx >= 0 and idx < Cards.count())
		if idx == World.LICH:
			lich += 1
	assert_true(lich > 0 and lich < 60, "lich drawn %d of 2000" % lich)


func test_texts_fit_the_screen() -> void:
	for f: String in Sanctum.FORTUNES:
		assert_true(PixelFont.text_width(f, 1) <= 440, f)
