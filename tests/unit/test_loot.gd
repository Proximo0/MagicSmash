extends TestCase
## Loot: rarity tiers, chest items and armor stats (game/logic/loot.gd).


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


func test_tables_line_up() -> void:
	assert_eq(Loot.RARITY_NAMES.size(), Loot.ULTRA + 1)
	assert_eq(Loot.RARITY_WEIGHTS.size(), Loot.ULTRA + 1)
	assert_eq(Loot.RARITY_MUL.size(), Loot.ULTRA + 1)
	assert_eq(Loot.STAT_CAPS.size(), Loot.STAT_COUNT)
	var keys: Dictionary = {}
	for i: int in range(Loot.count()):
		var row: Array = Loot.ITEMS[i]
		assert_false(keys.has(row[0]), "duplicate item " + str(row[0]))
		keys[row[0]] = true
		# A chest reel box fits one name above a wizard.
		assert_true(PixelFont.text_width(Loot.item_name(i), 1) <= 100, str(row[0]) + " name too wide")
	for i: int in range(1, Loot.ULTRA + 1):
		assert_true(float(Loot.RARITY_MUL[i]) > float(Loot.RARITY_MUL[i - 1]), "tiers must get stronger")


func test_rarity_odds_and_luck() -> void:
	var plain: Array[int] = [0, 0, 0, 0, 0]
	var lucky: Array[int] = [0, 0, 0, 0, 0]
	var r := _rng(4)
	for _i: int in range(20000):
		plain[Loot.roll_rarity(r, 0.0)] += 1
		lucky[Loot.roll_rarity(r, 5.0)] += 1
	assert_true(plain[Loot.COMMON] > plain[Loot.RARE] and plain[Loot.RARE] > plain[Loot.EPIC], "plain %s" % [plain])
	assert_eq(plain[Loot.ULTRA] + lucky[Loot.ULTRA], 0, "a chest never rolls ULTRA RARE (only an ULTRA RARE run's chest)")
	assert_true(plain[Loot.LEGENDARY] > 0, "legendary never rolled in 20000 chests")
	assert_true(plain[Loot.LEGENDARY] < 200, "legendary is too common: %d" % plain[Loot.LEGENDARY])
	assert_true(lucky[Loot.LEGENDARY] > plain[Loot.LEGENDARY], "luck raises legendary")
	assert_eq(lucky[Loot.COMMON], 0, "luck 5 should never roll common")


func test_rolls_are_seeded() -> void:
	assert_eq(Loot.roll_item(_rng(9)), Loot.roll_item(_rng(9)))
	assert_eq(Loot.roll_rarity(_rng(9), 1.0), Loot.roll_rarity(_rng(9), 1.0))


## The item roll as it was before tiers mattered (one draw over every weight).
func _plain_item(rng: RandomNumberGenerator) -> int:
	var total: float = 0.0
	for row: Array in Loot.ITEMS:
		total += float(row[5])
	var r: float = rng.randf() * total
	for i: int in range(Loot.count()):
		r -= float(Loot.ITEMS[i][5])
		if r < 0.0:
			return i
	return Loot.count() - 1


## A LEGENDARY or ULTRA RARE chest never rolls an item that does not grow with its tier (the ELIXIR heals to full at
## every tier): 10 000 of each find none, and the others share its weight. Below LEGENDARY every seed rolls the item
## it always did, so every share is unchanged.
func test_no_flat_item_at_legendary_or_above() -> void:
	var elixir := -1
	var total := 0.0
	var flat_w := 0.0
	for i: int in range(Loot.count()):
		total += float(Loot.ITEMS[i][5])
		if Loot.flat(i):
			flat_w += float(Loot.ITEMS[i][5])
		if Loot.ITEMS[i][0] == "elixir":
			elixir = i
	assert_true(Loot.flat(elixir), "the ELIXIR is the same at every tier")
	for i: int in range(Loot.count()):
		if not Loot.flat(i):
			assert_true(Loot.value(i, Loot.LEGENDARY) > Loot.value(i, Loot.COMMON), Loot.item_name(i) + " grows")
	var n := 10000
	var r := _rng(21)
	for tier: int in [Loot.LEGENDARY, Loot.ULTRA]:
		var seen: Array[int] = []
		seen.resize(Loot.count())
		for _i: int in range(n):
			seen[Loot.roll_item(r, tier)] += 1
		assert_eq(seen[elixir], 0, "no elixir at %s" % Loot.RARITY_NAMES[tier])
		for i: int in range(Loot.count()):
			var want := 0.0 if Loot.flat(i) else float(Loot.ITEMS[i][5]) / (total - flat_w)
			assert_near(float(seen[i]) / n, want, 0.015, "%s at %s" % [Loot.item_name(i), Loot.RARITY_NAMES[tier]])
	for tier: int in [Loot.COMMON, Loot.RARE, Loot.EPIC]:
		for s: int in range(1, 2001):
			assert_eq(Loot.roll_item(_rng(s), tier), _plain_item(_rng(s)), "seed %d at %s" % [s, Loot.RARITY_NAMES[tier]])
	var one := _rng(3)
	Loot.roll_item(one, Loot.ULTRA)
	var ref := _rng(3)
	ref.randf()
	assert_eq(one.state, ref.state, "one draw at any tier")


func test_armor_stacks_up_to_its_cap() -> void:
	var stats: Array = Loot.empty_stats()
	for _i: int in range(50):
		Loot.add_armor(stats, 4, Loot.ULTRA)
	assert_near(stats[Loot.ST_WARD], float(Loot.STAT_CAPS[Loot.ST_WARD]))
	assert_near(Loot.value(0, Loot.LEGENDARY), 0.08 * 3.0)
	assert_eq(Loot.value(3, Loot.COMMON), 1.0, "troll hide is at least one heart")


func test_run_rolls_are_seeded_and_their_own_stream() -> void:
	assert_eq(Loot.run_rolls(Loot.run_stream(77)), Loot.run_rolls(Loot.run_stream(77)))
	assert_false(Loot.run_rolls(Loot.run_stream(77)) == Loot.run_rolls(Loot.run_stream(78)))
	var main := _rng(77)
	assert_false(Loot.run_stream(77).randf() == main.randf(), "the run's loot stream is not the main stream")
	var d := Loot.run_rolls(Loot.run_stream(5))
	for k: String in ["ultra", "ultra_at", "card", "card_at", "card_urn", "card_kind"]:
		assert_true(float(d[k]) >= 0.0 and float(d[k]) < 1.0, k)


## The run's draws come off its stream in this order, the card's kind last, so every older draw keeps its value for
## every seed.
func test_run_rolls_keep_their_order() -> void:
	for s: int in [1, 5, 77, 4242]:
		var d := Loot.run_rolls(Loot.run_stream(s))
		var r := Loot.run_stream(s)
		for k: String in ["ultra", "ultra_at", "card", "card_at", "card_urn", "card_kind"]:
			assert_eq(float(d[k]), r.randf(), "%s, seed %d" % [k, s])
		assert_eq(d.size(), 6)


## Over 20 000 seeds about 1 run in 100 is an ULTRA RARE run and about 1 in 100 a card run (within a third), and the
## two are not the same runs.
func test_one_run_in_a_hundred_over_twenty_thousand_seeds() -> void:
	var tune := Tuning.new()
	var ultra_chance := Loot.ultra_run_chance(tune.ultra_run_chance, 0.0, tune.ultra_run_luck, tune.ultra_run_cap)
	var card_chance := Cards.card_run_chance(tune.card_run_chance, 1.0)
	assert_near(ultra_chance, 0.01)
	assert_near(card_chance, 0.01)
	var ultra := 0
	var card := 0
	var both := 0
	var n := 20000
	for s: int in range(1, n + 1):
		var d := Loot.run_rolls(Loot.run_stream(s))
		var u := float(d.ultra) < ultra_chance
		var c := float(d.card) < card_chance
		ultra += 1 if u else 0
		card += 1 if c else 0
		both += 1 if u and c else 0
	assert_true(absf(ultra - n * 0.01) < n * 0.01 / 3.0, "ultra runs %d of %d" % [ultra, n])
	assert_true(absf(card - n * 0.01) < n * 0.01 / 3.0, "card runs %d of %d" % [card, n])
	assert_true(both < 10, "ultra and card runs are independent: %d both" % both)


func test_luck_raises_the_ultra_run_up_to_its_cap() -> void:
	assert_near(Loot.ultra_run_chance(0.01, 0.0, 0.002, 0.03), 0.01)
	assert_near(Loot.ultra_run_chance(0.01, 3.0, 0.002, 0.03), 0.016)
	assert_near(Loot.ultra_run_chance(0.01, 50.0, 0.002, 0.03), 0.03)
	assert_near(Loot.ultra_run_chance(0.01, -4.0, 0.002, 0.03), 0.01, 0.0001, "no luck below none")
	assert_near(Loot.ultra_run_chance(1.0, 0.0, 0.002, 0.03), 1.0, 0.0001, "a forced run is not capped below its base")


func test_moment_is_a_share_of_the_run() -> void:
	assert_near(Loot.moment(0.0, 0.1, 0.7, 900.0), 90.0)
	assert_near(Loot.moment(1.0, 0.1, 0.7, 900.0), 630.0)
	assert_near(Loot.moment(0.5, 0.1, 0.7, 900.0), 360.0)
	assert_near(Loot.moment(2.0, 0.1, 0.7, 900.0), 630.0)
