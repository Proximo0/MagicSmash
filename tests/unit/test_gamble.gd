extends TestCase
## Gamble: shrine outcomes and costs (game/logic/gamble.gd).


func test_outcome_tables() -> void:
	for kind: int in [Gamble.SOLO, Gamble.TEAM]:
		var good: int = 0
		var bad: int = 0
		for i: int in range(Gamble.outcomes(kind).size()):
			assert_true(float(Gamble.outcomes(kind)[i][2]) > 0.0)
			# Team reel text is drawn at scale 2 in a box under 480 px; solo at scale 1 over a shrine.
			var scale: int = 2 if kind == Gamble.TEAM else 1
			assert_true(PixelFont.text_width(Gamble.outcome_name(kind, i), scale) <= 300)
			if Gamble.is_good(kind, i):
				good += 1
			else:
				bad += 1
		assert_true(good > 0 and bad > 0, "a gamble needs a way to win and a way to lose")
	assert_eq(Gamble.TEAM_OUTCOMES.size(), 2)


func test_roll_follows_weights() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var counts: Array[int] = [0, 0]
	for _i: int in range(4000):
		counts[Gamble.roll(r, Gamble.TEAM)] += 1
	assert_true(absi(counts[0] - counts[1]) < 300, "team shrine should be a coin flip: %s" % [counts])


func test_cost_grows_and_team_costs_more() -> void:
	assert_eq(Gamble.cost(Gamble.SOLO, 1, 15.0, 6.0, 2.5), 15)
	assert_eq(Gamble.cost(Gamble.SOLO, 4, 15.0, 6.0, 2.5), 33)
	assert_eq(Gamble.cost(Gamble.TEAM, 1, 15.0, 6.0, 2.5), 38)
