extends TestCase
## Cards: monster card data, drop chances and socket stats (game/logic/cards.gd).


func test_one_card_per_enemy_type() -> void:
	assert_eq(Cards.count(), Cards.MONSTERS + 8, "a card per enemy type, then one per Seal")
	assert_eq(Cards.MONSTERS, MonsterCard.ENEMY_SPRITES.size())
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


func test_secrets_are_listed_once_and_words_answer() -> void:
	var keys := {}
	for row: Array in Secrets.ALL:
		assert_false(keys.has(row[0]), "duplicate secret " + row[0])
		keys[row[0]] = true
	for word: String in Secrets.WORDS:
		var key: String = Secrets.WORDS[word][1]
		assert_true(key == "" or keys.has(key), word + " points at an unlisted secret")
		assert_true(PixelFont.text_width(Secrets.WORDS[word][0], 1) <= 440, word + " reply too wide")
		for ch: String in word:
			assert_true("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.".contains(ch), word + " cannot be spelled on the board")
	assert_eq(Secrets.answer(" abracadabra ")[1], "abracadabra")
	assert_true(Secrets.answer("NOTHING").is_empty())
	var p := Profile.new()
	p.find_secret("cat")
	p.find_secret("not_listed")
	assert_eq(Secrets.found(p), 1)


## The eight Seal cards: socketable like the others, never dropped by a monster's own roll.
func test_seal_cards_follow_the_monsters() -> void:
	for level: int in range(2, Seals.MAX + 1):
		var c := Seals.card(level)
		assert_eq(Cards.key(c), "seal_%d" % (level - 1))
		assert_true(Cards.socket(c) >= 0 and Cards.socket(c) < Cards.SOCKETS)
		var sockets := [-1, -1, -1]
		sockets[Cards.socket(c)] = c
		var st := Cards.socket_stats(sockets)
		assert_true(float(st[Cards.CARDS[c][3]]) > 0.0, Cards.key(c) + " adds its stat when socketed")
	for i: int in range(Cards.MONSTERS):
		assert_false(Cards.key(i).begins_with("seal_"))
