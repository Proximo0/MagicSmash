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
	var s := Sanctum.new(1, Sanctum.ALL_POTS)
	for b: bool in s.broken:
		assert_true(b)


func test_one_smashed_pot_does_not_break_the_rest_next_visit() -> void:
	var p := Profile.new()
	p.break_pot(0)
	var s := Sanctum.new(1, p.pots_mask_now())
	assert_true(s.broken[0])
	assert_false(s.broken[1], "another pot came back broken")
	assert_eq(s.broken.count(true), 1)
	p.finish_run(10, 30.0, 0, 0)
	assert_eq(p.pots_mask_now(), 0, "pots did not refill after a run")
	var old := Profile.from_dict({"runs": 2, "pots_run": 2})
	assert_eq(old.pots_mask_now(), Sanctum.ALL_POTS, "an old save keeps its pots broken")


func test_the_well_never_pays_out_more_than_it_takes() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var total := 0
	for i: int in range(1, 9001):
		total += Sanctum.wish_payout(i, false, r)
	assert_true(total < 9000, "the well paid %d crystals for 9000" % total)
	assert_eq(Sanctum.wish_payout(9, true, r), Secrets.NINTH_CRYSTALS, "the first ninth wish pays")


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


func test_the_ninth_wish_pays_only_the_first_time() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var p := Profile.new()
	var ninths := 0
	var paid_30 := 0
	for i: int in range(1, 28):
		var res := Sanctum.toss(p, r)
		if res.ninth:
			ninths += 1
			assert_eq(i, 9, "the secret was found on toss %d" % i)
			assert_eq(res.back, Secrets.NINTH_CRYSTALS)
		if res.back == Secrets.NINTH_CRYSTALS:
			paid_30 += 1
	assert_eq(p.wishes, 27)
	assert_true(p.has_secret("ninth"))
	assert_eq(ninths, 1, "tosses 9, 18 and 27 must find the secret exactly once")
	assert_eq(paid_30, 1, "the prize was paid more than once")
