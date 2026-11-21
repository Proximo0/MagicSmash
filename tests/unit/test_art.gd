extends TestCase
## Art: the loader for the owner's painted pictures (game/art/art.gd). Pixel data is not checked (a headless run
## may hold none); the tests cover the list of wanted names, the files in assets/art and missing keys.


func test_wanted_keys_are_unique() -> void:
	var seen := {}
	for w: Array in Art.wanted():
		var id: String = w[0] + "/" + w[1]
		assert_false(seen.has(id), "duplicate " + id)
		seen[id] = true
		assert_true(Art.GROUPS.has(w[0]), "unknown group " + id)
	assert_eq(seen.size(), 12 + 8 + 2 + 22 + 4 + 1 + 20 + 12) # 8: the Seal cards (cards/monsters/seal_1 to seal_8)


func test_every_file_in_the_project_is_wanted() -> void:
	var wanted := Art.wanted()
	var files := Art.listed(Art.RES_ROOT)
	assert_true(files.size() > 0, "assets/art is empty")
	for f: Array in files:
		assert_true(wanted.has(f), "stray file %s/%s.png" % [f[0], f[1]])


func test_missing_key_gives_null() -> void:
	assert_eq(Art.tex("cards/tarot", "no_such_card"), null)
	assert_eq(Art.tex("cards/tarot", "no_such_card", Vector2i(20, 40)), null)
	assert_false(Art.has("nope/group", "x"))
	assert_eq(Art.find("cards/tarot", "no_such_card"), "")


func test_every_arcana_title_has_a_wanted_slug() -> void:
	var tarot: Array = []
	for w: Array in Art.wanted():
		if w[0] == "cards/tarot":
			tarot.append(w[1])
	for key: String in TarotArt.ARCANA:
		var slug := Art.slug(TarotArt.ARCANA[key][1])
		assert_true(tarot.has(slug), "no wanted tarot key for " + slug)
	assert_eq(Art.slug("THE CHARIOT"), "the_chariot")
	assert_true(tarot.has("card_back"))


func test_every_monster_card_is_wanted() -> void:
	var monsters: Array = []
	for w: Array in Art.wanted():
		if w[0] == "cards/monsters":
			monsters.append(w[1])
	for i: int in range(Cards.count()):
		assert_true(monsters.has(Cards.key(i)), Cards.key(i))
