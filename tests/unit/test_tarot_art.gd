extends TestCase
## TarotArt: the code emblems (16x16 ASCII maps), the Major Arcana names and which emblem a key shows.

## The twelve keys of stage 3 that each have an emblem of their own.
const OWN_KEYS: Array[String] = ["priestess", "empress", "devil", "star", "w_hex", "w_blades", "e_lodestar", "e_greek",
	"e_veil", "e_dies", "e_hex", "e_blades"]
## The evolutions of today: none has an emblem of its own, each shows its spell's.
const PLAIN_EVOLUTIONS: Array[String] = ["e_arcane", "e_fire", "e_frost", "e_storm", "e_star", "e_rune", "e_bone",
	"e_candle", "e_cleave"]


## True when an icon file replaces the code emblem of this key (the pixel tests then do not apply).
func _tarot_icon_file(key: String) -> bool:
	return Still.icon(Still.icon_of(key), TarotArt.EMBLEM_ICON) != null


func _tarot_pixels(tex: Texture2D) -> PackedByteArray:
	return tex.get_image().get_data()


func test_every_map_is_16_by_16_of_palette_letters() -> void:
	for key: String in TarotArt.EMBLEMS:
		var rows: Array = TarotArt.EMBLEMS[key]
		assert_eq(rows.size(), 16, key + " rows")
		for row: String in rows:
			assert_eq(row.length(), 16, key + " row width")
			for ch in row:
				assert_true(ch == "." or TarotArt.PALETTE.has(ch), "%s has the letter %s" % [key, ch])


func test_no_two_maps_are_equal() -> void:
	var seen := {}
	for key: String in TarotArt.EMBLEMS:
		var flat := "".join(TarotArt.EMBLEMS[key])
		assert_false(seen.has(flat), "%s repeats %s" % [key, seen.get(flat, "")])
		seen[flat] = key


func test_the_twelve_new_keys_have_their_own_map() -> void:
	for key in OWN_KEYS:
		assert_true(TarotArt.EMBLEMS.has(key), key)


func test_emblem_shows_the_own_map_pixels() -> void:
	for key in OWN_KEYS:
		if _tarot_icon_file(key):
			continue
		var img := TarotArt.emblem(key).get_image()
		var rows: Array = TarotArt.EMBLEMS[key]
		assert_eq(img.get_width(), 16, key)
		assert_eq(img.get_height(), 16, key)
		for y in 16:
			var row: String = rows[y]
			for x in 16:
				var px := img.get_pixel(x, y)
				if row[x] == ".":
					assert_eq(px.a, 0.0, "%s clear at %d,%d" % [key, x, y])
				else:
					assert_true(px.is_equal_approx(TarotArt.PALETTE[row[x]]), "%s colour at %d,%d" % [key, x, y])


func test_an_evolution_with_its_own_map_no_longer_shows_its_spell_or_starfall() -> void:
	var spells := {"e_lodestar": "w_arcane", "e_greek": "w_fire", "e_veil": "w_frost", "e_dies": "w_storm",
		"e_hex": "w_hex", "e_blades": "w_blades"}
	for key: String in spells:
		if _tarot_icon_file(key):
			continue
		var spell: String = spells[key]
		assert_true(_tarot_pixels(TarotArt.emblem(key)) != _tarot_pixels(TarotArt.emblem("w_star")), key + " is not STARFALL")
		assert_true(_tarot_pixels(TarotArt.emblem(key)) != _tarot_pixels(TarotArt.emblem(spell)), key + " is not its spell")


func test_an_evolution_without_a_map_shows_its_spells() -> void:
	for key in PLAIN_EVOLUTIONS:
		assert_false(TarotArt.EMBLEMS.has(key), key + " has no own map")
		if _tarot_icon_file(key):
			continue
		var spell: String = "w_" + key.substr(2)
		if Still.icon("spell_" + key.substr(2), TarotArt.EMBLEM_ICON) != null:
			continue
		assert_eq(_tarot_pixels(TarotArt.emblem(key)), _tarot_pixels(TarotArt.emblem(spell)), key)
	assert_eq(_tarot_pixels(TarotArt.emblem("e_bone")), _tarot_pixels(TarotArt.emblem("w_bone")))


func test_an_unknown_key_shows_the_starfall_map() -> void:
	for key in ["nope_such", "e_nope_such"]:
		var img := TarotArt.emblem(key).get_image()
		assert_eq(img.get_pixel(7, 1), TarotArt.PALETTE["y"], key)
		assert_eq(img.get_pixel(0, 0).a, 0.0, key)


func test_the_new_arcana_names() -> void:
	assert_eq(TarotArt.ARCANA["priestess"], ["II", "THE HIGH PRIESTESS"])
	assert_eq(TarotArt.ARCANA["empress"], ["III", "THE EMPRESS"])
	assert_eq(TarotArt.ARCANA["devil"], ["XV", "THE DEVIL"])
	assert_eq(TarotArt.ARCANA["star"], ["XVII", "THE STAR"])
	assert_eq(TarotArt.heading("priestess"), "II")
	assert_eq(TarotArt.heading("star"), "XVII")


func test_every_non_minor_catalog_row_has_art() -> void:
	for i in Upgrades.count():
		if Upgrades.kind(i) == Upgrades.MINOR:
			continue
		var key := Upgrades.key(i)
		var has_art := TarotArt.EMBLEMS.has(key) or _tarot_icon_file(key)
		if not has_art and key.begins_with("e_"):
			var rest := key.substr(2)
			has_art = TarotArt.EMBLEMS.has("w_" + rest) or Still.icon("spell_" + rest, TarotArt.EMBLEM_ICON) != null
		assert_true(has_art, key + " has no emblem")
