extends TestCase
## Cards: monster card data, drop chances and socket stats (game/logic/cards.gd).


func test_one_card_per_enemy_type() -> void:
	assert_eq(Cards.count(), 12)
	var keys := {}
	for i: int in range(Cards.count()):
		assert_false(keys.has(Cards.key(i)), "duplicate key " + Cards.key(i))
		keys[Cards.key(i)] = true
		assert_eq(Cards.index_of(Cards.key(i)), i)
		assert_true(Cards.socket(i) >= 0 and Cards.socket(i) < Cards.SOCKETS)
		# The album and the reveal draw these on a 50 px card and a 104 px socket box.
		assert_true(PixelFont.text_width(Cards.card_name(i).trim_prefix("THE "), 1) <= 96, Cards.key(i) + " name too wide")
		assert_true(PixelFont.text_width(Cards.bonus_text(i), 1) <= 88, Cards.key(i) + " bonus too wide")
		assert_true(PixelFont.text_width(Cards.lore(i), 1) <= 320, Cards.key(i) + " lore too wide")
	assert_eq(Cards.key(World.LICH), "lich")
	assert_eq(Cards.index_of("nope"), -1)


func test_every_socket_has_a_card() -> void:
	var per := [0, 0, 0]
	for i: int in range(Cards.count()):
		per[Cards.socket(i)] += 1
	for s: int in range(Cards.SOCKETS):
		assert_true(per[s] >= 2, Cards.SOCKET_NAMES[s] + " has too few cards")


func test_drop_chance_favours_elites_and_the_lich() -> void:
	assert_near(Cards.drop_chance(World.GOBLIN, false, 0.001, 20.0, 0.3), 0.001)
	assert_near(Cards.drop_chance(World.GOBLIN, true, 0.001, 20.0, 0.3), 0.02)
	assert_near(Cards.drop_chance(World.LICH, false, 0.001, 20.0, 0.3), 0.3)
	assert_eq(Cards.drop_chance(99, false, 0.001, 20.0, 0.3), 0.0)


func test_socket_stats_only_count_cards_in_their_own_socket() -> void:
	var orc: int = World.ORC # staff, +10% damage
	var bat: int = World.BAT # hat, +10% speed
	var st := Cards.socket_stats([bat, -1, orc])
	assert_near(float(st[Loot.ST_MIGHT]), 0.10)
	assert_near(float(st[Loot.ST_SWIFT]), 0.10)
	var wrong := Cards.socket_stats([orc, orc, -1])
	for v: Variant in wrong:
		assert_eq(float(v), 0.0, "a card in the wrong socket counted")
