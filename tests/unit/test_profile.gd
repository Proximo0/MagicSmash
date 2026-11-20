extends TestCase
## Profile: crystals, meta unlocks and the saved form (game/logic/profile.gd), and the Save autoload's rules.


func test_meta_rows_match_effects() -> void:
	for i: int in range(Profile.META.size()):
		var key: String = Profile.META[i][0]
		assert_true(Profile.EFFECTS.has(key), key + " has no effect")
		assert_true(Profile.max_level(i) >= 1)
		var costs: Array = Profile.META[i][3]
		for k: int in range(1, costs.size()):
			assert_true(int(costs[k]) > int(costs[k - 1]), key + " costs must rise")
		# One unlock row: name, pips and description fit the 400 px panel.
		assert_true(PixelFont.text_width(Profile.META[i][1], 1) <= 100, key + " name too wide")
		assert_true(PixelFont.text_width(Profile.META[i][2], 1) <= 200, key + " description too wide")


func test_buy_spends_crystals_up_to_max() -> void:
	var p := Profile.new()
	var i: int = Profile.meta_index("vigor")
	assert_false(p.buy(i), "bought with no crystals")
	p.crystals = 1000
	var spent: int = 0
	for _k: int in range(Profile.max_level(i)):
		spent += p.next_cost(i)
		assert_true(p.buy(i))
	assert_eq(p.next_cost(i), -1)
	assert_false(p.buy(i), "bought past max")
	assert_eq(p.crystals, 1000 - spent)
	assert_near(float(p.bonuses()["hearts"]), float(Profile.max_level(i)))


func test_runs_earn_crystals() -> void:
	var p := Profile.new()
	var earned: int = p.finish_run({"score": 12345, "seconds": 300.0, "kills": 600, "liches": 1})
	assert_eq(earned, 10 + 2 + Profile.CRYSTAL_LICH)
	assert_eq(p.crystals, earned)
	assert_eq(p.high_score, 12345)
	p.finish_run({"score": 10, "seconds": 20.0})
	assert_eq(p.high_score, 12345, "a worse run keeps the best score")
	assert_eq(p.runs, 2)
	assert_eq(p.wins, 0)


func test_a_won_run_pays_the_win_bonus_and_counts() -> void:
	var p := Profile.new()
	var earned: int = p.finish_run({"score": 1, "won": true})
	assert_eq(earned, Profile.CRYSTAL_WIN)
	assert_eq(p.wins, 1)
	assert_eq(Profile.from_dict(p.to_dict()).wins, 1)


func test_round_trip_and_bad_data() -> void:
	var p := Profile.new()
	p.crystals = 77
	p.unlocks = {"might": 2}
	var q := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(q.crystals, 77)
	assert_eq(q.level("might"), 2)
	var bad := Profile.from_dict({"crystals": -5, "unlocks": {"might": 99, "nonsense": 3}})
	assert_eq(bad.crystals, 0)
	assert_eq(bad.level("might"), Profile.max_level(Profile.meta_index("might")))
	assert_false(bad.unlocks.has("nonsense"))


func test_scripted_runs_never_write_or_get_unlocks() -> void:
	assert_true(Flags.is_scripted_run(), "unit tests are a scripted run")
	assert_false(Save.write(), "Save wrote player data in a scripted run")
	assert_true(Save.run_bonuses().is_empty())


func test_world_applies_meta_bonuses() -> void:
	var w := World.new([0, 1], 3)
	w.apply_meta({"hearts": 2.0, "novas": 1.0, "damage": 0.1, "luck": 1.0})
	for s: int in [0, 1]:
		var p: World.Player = w.players[s]
		assert_eq(p.max_hp, World.BASE_HEARTS + 2)
		assert_eq(p.hp, p.max_hp)
		assert_eq(p.bombs, 3)
	var e: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(100, 100))
	w._damage_enemy(e, 1.0, 0, Vector2.ZERO)
	assert_near(e.maxhp - e.hp, 1.1, 0.0001)


func test_cards_collect_socket_and_save() -> void:
	var p := Profile.new()
	assert_false(p.socket_card(World.ORC), "socketed a card not owned")
	assert_true(p.add_card(World.ORC), "first orc card is not new")
	assert_false(p.add_card(World.ORC), "second orc card counted as new")
	assert_eq(p.card_count(World.ORC), 2)
	assert_eq(p.cards_owned(), 1)
	assert_true(p.socket_card(World.ORC))
	assert_eq(p.socket_indices(), [-1, -1, World.ORC] as Array[int])
	assert_near(float((p.bonuses()["armor"] as Array)[Loot.ST_MIGHT]), 0.10)
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(back.card_count(World.ORC), 2)
	assert_eq(back.socket_indices(), [-1, -1, World.ORC] as Array[int])
	p.unsocket(Cards.STAFF)
	assert_eq(p.socket_indices(), [-1, -1, -1] as Array[int])


func test_saved_sockets_drop_cards_not_owned_or_misplaced() -> void:
	var d := {"cards": {"orc": 1, "bogus": 3}, "sockets": ["orc", "bat", "orc"]}
	var p := Profile.from_dict(d)
	assert_eq(p.card_count(World.ORC), 1)
	assert_eq(p.cards_owned(), 1)
	assert_eq(p.socket_indices(), [-1, -1, World.ORC] as Array[int])


func test_secrets_pots_and_spending_save() -> void:
	var p := Profile.new()
	assert_true(p.find_secret("alcove"))
	assert_false(p.find_secret("alcove"))
	assert_false(p.pots_smashed())
	p.pots_run = p.runs
	assert_true(p.pots_smashed())
	p.crystals = 5
	assert_false(p.spend(6))
	assert_true(p.spend(5))
	assert_eq(p.crystals, 0)
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_true(back.has_secret("alcove"))
	assert_true(back.pots_smashed())
	back.finish_run({"score": 10, "seconds": 30.0})
	assert_false(back.pots_smashed(), "pots did not refill after a run")
