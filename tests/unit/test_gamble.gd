extends TestCase
## Gamble: shrine outcomes, the fate deck and costs (game/logic/gamble.gd).


func _drawable(s: String) -> bool:
	for ch: String in s:
		if not PixelFont.GLYPHS.has(ch) and not PixelFont.GLYPHS.has(ch.to_upper()):
			return false
	return true


func test_outcome_tables() -> void:
	for kind: int in [Gamble.SOLO, Gamble.TEAM]:
		var good: int = 0
		var bad: int = 0
		for i: int in range(Gamble.outcomes(kind).size()):
			# Team reel text is drawn at scale 2 in a box under 480 px; solo at scale 1 over a shrine.
			var scale: int = 2 if kind == Gamble.TEAM else 1
			assert_true(PixelFont.text_width(Gamble.outcome_name(kind, i), scale) <= 300)
			assert_true(_drawable(Gamble.outcome_name(kind, i)), Gamble.outcome_name(kind, i))
			if Gamble.is_good(kind, i):
				good += 1
			else:
				bad += 1
		assert_true(good > 0 and bad > 0, "a gamble needs a way to win and a way to lose")
	for row: Array in Gamble.SOLO_OUTCOMES:
		assert_true(float(row[2]) > 0.0)


func test_the_deck_has_eight_fates_four_a_side() -> void:
	assert_eq(Gamble.TEAM_OUTCOMES.size(), 8)
	var kind: int = 0
	for i: int in range(8):
		if Gamble.is_good(Gamble.TEAM, i):
			kind += 1
	assert_eq(kind, 4)
	assert_true(Gamble.is_good(Gamble.TEAM, Gamble.TO_FOOL) and Gamble.is_good(Gamble.TEAM, Gamble.TO_EMPEROR))
	assert_false(Gamble.is_good(Gamble.TEAM, Gamble.TO_WHEEL) or Gamble.is_good(Gamble.TEAM, Gamble.TO_HANGED))


func test_ids_0_and_1_keep_their_meaning() -> void:
	assert_eq(Gamble.TO_BLESSING, 0)
	assert_eq(Gamble.TO_CURSE, 1)
	assert_eq(Gamble.TEAM_OUTCOMES[0][0], "blessing")
	assert_eq(Gamble.TEAM_OUTCOMES[1][0], "curse")
	assert_eq(Gamble.outcome_name(Gamble.TEAM, 0), "PARTY BLESSED!")
	assert_eq(Gamble.outcome_name(Gamble.TEAM, 1), "PARTY CURSED!")
	assert_true(Gamble.is_good(Gamble.TEAM, 0))
	assert_false(Gamble.is_good(Gamble.TEAM, 1))
	assert_eq(Gamble.fate_card(0), "sun")
	assert_eq(Gamble.fate_card(1), "death")


func test_every_fate_has_a_card_and_a_drawable_line() -> void:
	var t := Tuning.new()
	for i: int in range(Gamble.TEAM_OUTCOMES.size()):
		var key := Gamble.fate_card(i)
		assert_true(TarotArt.ARCANA.has(key), "no arcana for " + key)
		var line := Gamble.fate_text(i, t)
		assert_false(line.contains("%"), line)
		assert_true(_drawable(line), "the font cannot draw: " + line)
		assert_true(PixelFont.text_width(line, 1) <= 460, "too wide for the reel: " + line)
	assert_eq(Gamble.fate_text(Gamble.TO_HANGED, t), "NOVAS SEALED FOR 60 SECONDS")
	assert_eq(Gamble.fate_text(Gamble.TO_BLESSING, t), "EVERY WIZARD GAINS 2 LEVELS")


func test_solo_roll_is_still_the_sun_or_death_coin_flip() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var counts: Array[int] = [0, 0]
	for _i: int in range(4000):
		var o := Gamble.roll(r, Gamble.TEAM)
		assert_true(o == 0 or o == 1)
		counts[o] += 1
	assert_true(absi(counts[0] - counts[1]) < 300, "team shrine should be a coin flip: %s" % [counts])


func test_the_deck_is_50_50_by_side_then_even() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var counts: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	var cruel: int = 0
	for _i: int in range(8000):
		var f := Gamble.draw_fate(r, 0.5)
		counts[f] += 1
		if not Gamble.is_good(Gamble.TEAM, f):
			cruel += 1
	assert_true(absi(cruel - 4000) < 250, "the sides should be a coin flip: %d cruel" % cruel)
	for c: int in counts:
		assert_true(absi(c - 1000) < 150, "each fate about 1 in 8: %s" % [counts])


func test_fate_cruel_0_and_1_pick_the_side() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for _i: int in range(500):
		assert_true(Gamble.is_good(Gamble.TEAM, Gamble.draw_fate(r, 0.0)), "fate_cruel 0 is always kind")
		assert_false(Gamble.is_good(Gamble.TEAM, Gamble.draw_fate(r, 1.0)), "fate_cruel 1 is always cruel")


func test_a_draw_without_the_wheel_never_turns_it() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var seen := {}
	for _i: int in range(2000):
		var f := Gamble.draw_fate(r, 1.0, false)
		assert_true(f != Gamble.TO_WHEEL)
		seen[f] = true
	assert_eq(seen.size(), 3, "the other three cruel fates still come up")


func test_cost_grows_and_team_costs_more() -> void:
	assert_eq(Gamble.cost(Gamble.SOLO, 1, 15.0, 6.0, 2.5), 15)
	assert_eq(Gamble.cost(Gamble.SOLO, 4, 15.0, 6.0, 2.5), 33)
	assert_eq(Gamble.cost(Gamble.TEAM, 1, 15.0, 6.0, 2.5), 38)
