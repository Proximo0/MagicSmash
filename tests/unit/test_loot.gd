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
	assert_true(plain[Loot.ULTRA] > 0, "ultra rare never rolled in 20000 chests")
	assert_true(plain[Loot.ULTRA] < 400, "ultra rare is too common: %d" % plain[Loot.ULTRA])
	assert_eq(lucky[Loot.COMMON], 0, "luck 5 should never roll common")


func test_rolls_are_seeded() -> void:
	assert_eq(Loot.roll_item(_rng(9)), Loot.roll_item(_rng(9)))
	assert_eq(Loot.roll_rarity(_rng(9), 1.0), Loot.roll_rarity(_rng(9), 1.0))


func test_armor_stacks_up_to_its_cap() -> void:
	var stats: Array = Loot.empty_stats()
	for _i: int in range(50):
		Loot.add_armor(stats, 4, Loot.ULTRA)
	assert_near(stats[Loot.ST_WARD], float(Loot.STAT_CAPS[Loot.ST_WARD]))
	assert_near(Loot.value(0, Loot.LEGENDARY), 0.08 * 3.0)
	assert_eq(Loot.value(3, Loot.COMMON), 1.0, "troll hide is at least one heart")
