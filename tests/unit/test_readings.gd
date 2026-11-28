extends TestCase
## Readings: the sixteen Minor Arcana a table is dealt before a run (game/logic/readings.gd), the deal, the vote,
## and World.apply_reading merging a Reading's values into the run after the Seal's (docs/content_list.md § 42).

const KEYS := ["r_wands_1", "r_wands_4", "r_wands_8", "r_wands_10", "r_cups_1", "r_cups_2", "r_cups_5", "r_cups_9",
	"r_swords_1", "r_swords_3", "r_swords_7", "r_swords_10", "r_pent_1", "r_pent_4", "r_pent_9", "r_pent_10"]
const NAMES := ["ACE OF WANDS", "FOUR OF WANDS", "EIGHT OF WANDS", "TEN OF WANDS", "ACE OF CUPS", "TWO OF CUPS",
	"FIVE OF CUPS", "NINE OF CUPS", "ACE OF SWORDS", "THREE OF SWORDS", "SEVEN OF SWORDS", "TEN OF SWORDS",
	"ACE OF PENTACLES", "FOUR OF PENTACLES", "NINE OF PENTACLES", "TEN OF PENTACLES"]
const SEAL_FIELDS := ["seal_hp", "seal_horde", "seal_boss", "seal_speed", "seal_potions"]
## The whole table as `deal`'s last argument: no row left out as unbuilt.
const ALL_BUILT: Array[String] = []


func _all_open() -> Dictionary:
	var open := {}
	for k: String in KEYS:
		open[k] = true
	return open


func _world(level: int, key: String, slots: Array = [0, 1], seed_value: int = 7) -> World:
	var w := World.new(slots, seed_value, Tuning.new())
	w.apply_seal(level)
	w.apply_reading(key)
	return w


# ---------------------------------------------------------------- the rows ---
func test_sixteen_keys_and_names_in_order() -> void:
	assert_eq(Readings.ROWS.size(), 16)
	for i: int in range(Readings.ROWS.size()):
		var row: Array = Readings.ROWS[i]
		assert_eq(row.size(), 5, "row %d: key, name, words, party only, values" % i)
		assert_eq(row[Readings.KEY], KEYS[i])
		assert_eq(row[Readings.NAME], NAMES[i])
		assert_eq(Readings.index_of(KEYS[i]), i)
		assert_true(row[Readings.VALUES] is Dictionary)
	assert_eq(Readings.index_of(""), -1)
	assert_eq(Readings.index_of("r_cups_99"), -1)


func test_words_fit_a_card() -> void:
	for row: Array in Readings.ROWS:
		var words: String = row[Readings.WORDS]
		var lines := words.split("\n")
		assert_true(lines.size() >= 1 and lines.size() <= Readings.WORD_LINES, "%s: at most 3 lines" % row[0])
		for line: String in lines:
			assert_true(line.length() > 0 and line.length() <= Readings.WORD_WIDTH, "%s: '%s' at most 18" % [row[0], line])
		assert_eq(words, words.to_upper(), "%s: capitals" % row[0])


func test_only_two_of_cups_is_party() -> void:
	for k: String in KEYS:
		assert_eq(Readings.party_only(k), k == "r_cups_2", k)
	assert_false(Readings.party_only(""))
	assert_false(Readings.party_only("nope"))


func test_values_lookup() -> void:
	assert_eq(Readings.values(""), {})
	assert_eq(Readings.values("nope"), {})
	assert_eq(int(Readings.values("r_cups_1").hearts), 2)
	assert_near(float(Readings.values("r_pent_9").hp), 1.2)
	assert_near(float(Readings.values("r_swords_10").horde), 1.2)
	assert_near(float(Readings.values("r_wands_8").pace), 1.2)
	assert_eq(Readings.values("r_wands_8").size(), 1, "EIGHT OF WANDS is one number, the run's clock")
	assert_eq(Readings.values("r_wands_10").slots, [5, 2])
	# A copy: changing it does not change the table.
	var v := Readings.values("r_cups_1")
	v.hearts = 99
	assert_eq(int(Readings.values("r_cups_1").hearts), 2)


func test_every_own_key_has_a_world_field_with_a_neutral_default() -> void:
	var w := World.new([0], 1)
	for row: Array in Readings.ROWS:
		for k: String in (row[Readings.VALUES] as Dictionary):
			if Readings.MERGE_MUL.has(k) or Readings.MERGE_ADD.has(k):
				continue
			var f := "read_" + k
			assert_true(f in w, "%s: World.%s" % [row[0], f])
			var d: Variant = w.get(f)
			var neutral: bool = (d is float and (d == 1.0 or d == 0.0)) or (d is int and d == 0) or (d is bool and d == false) \
				or (d is Array and (d as Array).is_empty())
			assert_true(neutral, "%s neutral by default" % f)
			assert_eq(typeof(d), typeof((row[Readings.VALUES] as Dictionary)[k]), "%s: same type as the value" % f)


# ---------------------------------------------------------------- the deal ---
func test_same_seed_same_hand() -> void:
	var a := RandomNumberGenerator.new()
	a.seed = 42
	var b := RandomNumberGenerator.new()
	b.seed = 42
	var ha := Readings.deal(a, _all_open(), 2, 3, ALL_BUILT)
	var hb := Readings.deal(b, _all_open(), 2, 3, ALL_BUILT)
	assert_eq(ha, hb)
	assert_eq(ha.size(), 3)
	var seen := {}
	for k: String in ha:
		assert_false(seen.has(k), "different keys")
		seen[k] = true
		assert_true(Readings.index_of(k) >= 0)
	# Some other seed deals some other hand (the deal uses the rng at all).
	var differs := false
	for s: int in range(1, 20):
		var c := RandomNumberGenerator.new()
		c.seed = s
		if Readings.deal(c, _all_open(), 2, 3, ALL_BUILT) != ha:
			differs = true
	assert_true(differs)


func test_no_party_card_for_one_seat() -> void:
	for s: int in range(60):
		var r := RandomNumberGenerator.new()
		r.seed = s
		var hand := Readings.deal(r, _all_open(), 1, 15, ALL_BUILT)
		assert_eq(hand.size(), 15, "sixteen open, one PARTY left out")
		assert_false(hand.has("r_cups_2"))
	var r2 := RandomNumberGenerator.new()
	r2.seed = 3
	assert_true(Readings.deal(r2, _all_open(), 2, 16, ALL_BUILT).has("r_cups_2"), "two seats: dealt")


func test_only_open_rows_are_dealt() -> void:
	var open := {"r_cups_1": true, "r_pent_9": true, "r_swords_10": true, "r_wands_8": false}
	for s: int in range(40):
		var r := RandomNumberGenerator.new()
		r.seed = s
		for k: String in Readings.deal(r, open, 4, 2, ALL_BUILT):
			assert_true(k in ["r_cups_1", "r_pent_9", "r_swords_10"], k)


func test_n_larger_than_the_pool() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 9
	var hand := Readings.deal(r, {"r_cups_1": true, "r_cups_2": true}, 1, 3, ALL_BUILT)
	assert_eq(hand, ["r_cups_1"] as Array[String])
	assert_eq(Readings.deal(r, {}, 4, 3, ALL_BUILT).size(), 0)
	assert_eq(Readings.deal(r, {"r_cups_1": true, "r_pent_1": true}, 2, 3, ALL_BUILT).size(), 2)


func test_an_unbuilt_row_is_never_dealt() -> void:
	for k: String in Readings.UNBUILT:
		assert_true(Readings.index_of(k) >= 0, "%s is a row" % k)
	var built := 0
	for k: String in KEYS:
		if not Readings.UNBUILT.has(k):
			built += 1
	for s: int in range(40):
		var r := RandomNumberGenerator.new()
		r.seed = s
		var hand := Readings.deal(r, _all_open(), 4, 16)
		assert_eq(hand.size(), built, "every built row and no other")
		for k: String in hand:
			assert_false(Readings.UNBUILT.has(k), k)
	# The list is `deal`'s own default, and a caller's list is obeyed the same way.
	var r3 := RandomNumberGenerator.new()
	r3.seed = 5
	var left: Array[String] = ["r_cups_1", "r_pent_9"]
	var hand3 := Readings.deal(r3, {"r_cups_1": true, "r_pent_9": true, "r_swords_10": true}, 4, 3, left)
	assert_eq(hand3, ["r_swords_10"] as Array[String])


# ---------------------------------------------------------------- the vote ---
func test_vote_majority() -> void:
	assert_eq(Readings.vote([0, 2, 2, 1], 4), 2)
	assert_eq(Readings.vote([1, 1, -1], 3), 1)


func test_vote_tie_goes_to_the_first_seat() -> void:
	assert_eq(Readings.vote([2, 1], 2), 2, "seat 1's pick among the tied")
	assert_eq(Readings.vote([2, 0, 0, 2], 4), 2)


func test_vote_tie_without_the_first_seat_goes_low() -> void:
	assert_eq(Readings.vote([-1, 2, 1], 3), 1, "seat 1 abstains: lowest tied")
	assert_eq(Readings.vote([0, 2, 2, 1, 1], 5), 1, "seat 1's pick is not among the tied")


func test_vote_nobody() -> void:
	assert_eq(Readings.vote([-1, -1], 2), 0)
	assert_eq(Readings.vote([], 0), 0)


# --------------------------------------------------------- apply_reading ---
func test_empty_reading_leaves_the_world_as_it_was() -> void:
	var a := World.new([0, 1], 7)
	var b := World.new([0, 1], 7)
	a.apply_seal(3)
	b.apply_seal(3)
	b.apply_reading("")
	b.apply_reading("r_nope")
	assert_eq(b.reading, "")
	for f: String in SEAL_FIELDS:
		assert_eq(b.get(f), a.get(f), f)
	for row: Array in Readings.ROWS:
		for k: String in (row[Readings.VALUES] as Dictionary):
			if "read_" + k in b:
				assert_eq(b.get("read_" + k), a.get("read_" + k), k)
	for s: int in [0, 1]:
		assert_eq(b.players[s].max_hp, a.players[s].max_hp)
		assert_eq(b.players[s].hp, a.players[s].hp)
	assert_eq(b.record.uses, a.record.uses)
	for _i: int in range(120):
		a.step(1.0 / 60.0, {})
		b.step(1.0 / 60.0, {})
	assert_eq(a.state_hash(), b.state_hash(), "no Reading plays exactly like before")
	assert_eq(int((b.snapshot()["w"] as PackedFloat32Array)[World.W_READING]), -1)


func test_ace_of_cups_gives_two_hearts() -> void:
	var a := _world(0, "")
	var b := _world(0, "r_cups_1", [0, 1, 2])
	for s: int in [0, 1, 2]:
		assert_eq(b.players[s].max_hp, a.players[0].max_hp + 2, "max hearts")
		assert_eq(b.players[s].hp, a.players[0].hp + 2, "starts full")
	# On top of APPRENTICE's own +2: hearts add.
	var e := _world(World.SEAL_EASY, "r_cups_1")
	assert_eq(e.players[0].max_hp, World.BASE_HEARTS + int(Seals.APPRENTICE.hearts) + 2)


func test_seal_values_multiply_at_wizard_and_at_a_seal() -> void:
	var plain := _world(0, "")
	var nine := _world(0, "r_pent_9")
	assert_near(nine.seal_hp, 1.2, 0.0001, "WIZARD: the Reading alone")
	assert_near(nine.seal_boss, 1.2, 0.0001, "a boss is a foe")
	var arch := _world(1, "")
	var arch9 := _world(1, "r_pent_9")
	assert_near(arch9.seal_hp, arch.seal_hp * 1.2, 0.0001, "ARCHMAGE x NINE OF PENTACLES")
	assert_near(arch9.seal_boss, arch.seal_boss * 1.2, 0.0001, "ARCHMAGE's bosses x NINE OF PENTACLES")
	var hunger := _world(2, "")
	var hunger9 := _world(2, "r_pent_9")
	assert_near(hunger9.seal_potions, hunger.seal_potions, 0.0001, "HUNGER's potions as they were")
	assert_near(hunger9.seal_speed, hunger.seal_speed, 0.0001, "a number the Reading does not name stays")
	var ten := _world(9, "r_swords_10")
	assert_near(ten.seal_horde, float(Seals.values(9).horde) * 1.2, 0.0001, "SEAL VIII's horde x TEN OF SWORDS")
	assert_near(plain.seal_hp, 1.0)


func test_nine_of_pentacles_foes_have_a_fifth_more_health() -> void:
	var a := _world(0, "")
	var b := _world(0, "r_pent_9")
	var g0 := WorldWaves.spawn_enemy(a, World.GOBLIN, 0)
	var g1 := WorldWaves.spawn_enemy(b, World.GOBLIN, 0)
	assert_near(g1.hp / g0.hp, 1.2, 0.001)


func test_nine_of_pentacles_bosses_have_a_fifth_more_health() -> void:
	var a := _world(0, "")
	var b := _world(0, "r_pent_9")
	assert_near(Bosses.health_in(b, World.LICH) / Bosses.health_in(a, World.LICH), 1.2, 0.001)
	assert_near(Bosses.final_health_in(b, World.LICH) / Bosses.final_health_in(a, World.LICH), 1.2, 0.001)


func test_eight_of_wands_is_the_clock_and_nothing_else() -> void:
	var a := _world(1, "")
	var b := _world(1, "r_wands_8")
	assert_near(b.read_pace, 1.2)
	for f: String in SEAL_FIELDS:
		assert_eq(b.get(f), a.get(f), "%s: the clock speeds foes up, not a second number" % f)
	assert_near(b.read_xp, 1.0, 0.0001, "XP comes faster with the clock")


func test_ten_of_swords_horde_is_a_fifth_bigger() -> void:
	var got := {}
	for key: String in ["", "r_swords_10"]:
		var w := _world(0, key, [0], 11)
		w.phase = World.PH_FIGHT
		w.wave_time = 120.0
		w.wave = 3
		w.horde_budget = 0.0
		WorldWaves._direct_horde(w, 0.001)
		got[key] = w.horde_budget
	assert_true(float(got[""]) > 0.0)
	assert_near(float(got["r_swords_10"]) / float(got[""]), 1.2, 0.0001)


func test_every_read_field_is_set() -> void:
	for row: Array in Readings.ROWS:
		var w := _world(0, row[Readings.KEY])
		assert_eq(w.reading, row[Readings.KEY])
		var v: Dictionary = row[Readings.VALUES]
		for k: String in v:
			if Readings.MERGE_MUL.has(k) or Readings.MERGE_ADD.has(k):
				continue
			assert_eq(w.get("read_" + k), v[k], "%s: read_%s" % [row[0], k])


func test_header_and_use_counter() -> void:
	var w := _world(0, "r_swords_3")
	var hdr: PackedFloat32Array = w.snapshot()["w"]
	assert_eq(hdr.size(), World.W_FLOATS)
	assert_eq(World.W_READING, 19)
	assert_eq(int(hdr[World.W_READING]), Readings.index_of("r_swords_3"))
	assert_eq(w.record.used("r_swords_3"), 0, "a Reading with a rule is credited where the rule fires")
	assert_eq(_world(0, "r_cups_1").record.used("r_cups_1"), 1, "only merged numbers: credited once when applied")
	assert_eq(_world(0, "").record.used("r_cups_1"), 0)
	assert_eq(int((_world(0, "r_wands_1").snapshot()["w"] as PackedFloat32Array)[World.W_READING]), 0)
