extends TestCase
## Cards: monster card data, drop chances and socket stats (game/logic/cards.gd).


func test_one_card_per_enemy_type() -> void:
	assert_eq(Cards.count(), 12 + 8, "a card per first-act monster, then one per Seal")
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


func test_card_run_chance_and_the_card_a_kill_drops() -> void:
	assert_near(Cards.card_run_chance(0.01, 1.0), 0.01)
	assert_near(Cards.card_run_chance(0.01, 1.5), 0.015, 0.0001, "the Seals' card odds raise it")
	assert_near(Cards.card_run_chance(1.0, 1.5), 1.0)
	assert_eq(Cards.run_card(World.GOBLIN, false, -1), Cards.for_enemy(World.GOBLIN))
	assert_eq(Cards.run_card(World.LICH, false, Seals.card(5)), Cards.for_enemy(World.LICH), "a Lich visit: the Lich card")
	assert_eq(Cards.run_card(World.LICH, true, Seals.card(5)), Seals.card(5), "a Seal's Archlich: its Seal card")
	assert_eq(Cards.run_card(World.LICH, true, -1), Cards.for_enemy(World.LICH))
	assert_eq(Cards.run_card(99, false, -1), -1)


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
	for i: int in range(Cards.count()):
		assert_eq(Cards.enemy(i) < 0, Cards.key(i).begins_with("seal_"), Cards.key(i))


## Cards map to enemy kinds explicitly: the first twelve kinds have their card, Seal cards have no kind, and the
## newer kinds (Bestiary ids 12 and up) have none, so their kills never drop a Seal card.
func test_cards_map_to_enemies_by_kind_not_index() -> void:
	for t: int in range(12):
		var c := Cards.for_enemy(t)
		assert_true(c >= 0, "kind %d has a card" % t)
		assert_eq(Cards.enemy(c), t)
		assert_true(Cards.enemy(c) < MonsterCard.ENEMY_SPRITES.size(), "a sprite for its face")
	for t: int in range(12, Bestiary.count()):
		assert_eq(Cards.for_enemy(t), -1, "kind %d has no card yet" % t)
		assert_eq(Cards.run_card(t, false, -1), -1)
	assert_eq(Cards.for_enemy(-1), -1)
	assert_eq(Cards.enemy(-1), -1)
	assert_eq(Cards.enemy(99), -1)
	for i: int in range(200):
		var r := RandomNumberGenerator.new()
		r.seed = i
		assert_true(Cards.enemy(Sanctum.roll_card(r)) >= 0, "pots and urns never hand out a Seal card")


## The album (game/ui/card_album.gd) pages its grid: every page's cells sit above the info panel, inside 270 px,
## and up/down reach every card.
func test_album_pages_fit_and_reach_every_card() -> void:
	var album := CardAlbum.new()
	assert_eq(CardAlbum.pages(), 2)
	for i: int in range(Cards.count()):
		album.sel = i
		var r := album._cell(i)
		assert_true(r.end.y + 2 <= 202 and r.position.y >= 30, "card %d sits in the grid" % i)
		assert_true(r.end.x <= 472)
	var seen := {}
	for start: int in range(CardAlbum.COLS):
		var i := start
		for k: int in range(10):
			seen[i] = true
			i = CardAlbum._row_step(i, 1)
	assert_eq(seen.size(), Cards.count(), "down reaches every card")
	assert_eq(CardAlbum._row_step(0, -1), 18, "up from the top wraps to the last card in that column")
	assert_eq(CardAlbum._row_step(15, 1), 3, "down past a short last row wraps to the first row")
	album.sel = 3
	album._turn(1)
	assert_eq(album.sel, 15)
	album._turn(1)
	assert_eq(album.sel, 3)
	album.sel = 11
	album._turn(1)
	assert_eq(album.sel, 19, "a short page takes its last card")


## The monster cards are the ones a kind of monster drops (12 today); the Seal cards are not among them.
func test_monster_count_leaves_out_the_seal_cards() -> void:
	var n := 0
	for i: int in range(Cards.count()):
		n += 1 if Cards.enemy(i) >= 0 else 0
	assert_eq(Cards.monster_count(), n)
	assert_eq(Cards.monster_count(), 12)
	assert_true(Cards.monster_count() < Cards.count())
