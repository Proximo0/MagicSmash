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
	assert_eq(p.pots_mask_now(), 0)
	p.break_pot(3)
	assert_eq(p.pots_mask_now(), 8)
	p.crystals = 5
	assert_false(p.spend(6))
	assert_true(p.spend(5))
	assert_eq(p.crystals, 0)
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_true(back.has_secret("alcove"))
	assert_eq(back.pots_mask_now(), 8)
	back.finish_run({"score": 10, "seconds": 30.0})
	assert_eq(back.pots_mask_now(), 0, "pots did not refill after a run")


func test_breaking_a_pot_in_a_new_run_drops_the_old_runs_bits() -> void:
	var p := Profile.new()
	p.break_pot(3)
	p.finish_run({"score": 10, "seconds": 30.0})
	assert_eq(p.pots_mask_now(), 0)
	p.break_pot(1)
	assert_eq(p.pots_mask_now(), 2, "a pot from an earlier run stayed broken")


func test_bounties_scale_with_the_step_and_losing_pays_nothing_extra() -> void:
	var a := Profile.new()
	var b := Profile.new()
	var lost := {"seconds": 120.0, "kills": 500}
	assert_eq(b.finish_run(lost.merged({"seal": 9})), a.finish_run(lost), "a fast loss pays the same at any step")
	var won := {"seconds": 960.0, "kills": 3000, "liches": 4, "won": true}
	var at0 := Profile.new().finish_run(won)
	var at5 := Profile.new()
	var paid := at5.finish_run(won.merged({"seal": 5}))
	var bounty := 4 * Profile.CRYSTAL_LICH + Profile.CRYSTAL_WIN
	assert_eq(paid, at0 + roundi(bounty * Seals.crystal_mul(5)) - bounty + Seals.prize(5))
	assert_eq(at5.last_pay.prize, Seals.prize(5))
	assert_eq(at5.last_pay.card, Seals.card(5))
	assert_eq(Profile.new().finish_run(won.merged({"seal": -1})), at0 - bounty + roundi(bounty * 0.5), "APPRENTICE halves")


func test_prizes_pay_once_per_profile_and_step() -> void:
	var p := Profile.new()
	var won := {"won": true, "seal": 3}
	var first := p.finish_run(won)
	assert_eq(p.card_count(Seals.card(3)), 1, "the first win pays the Seal card")
	assert_eq(p.prize_left(3), 0)
	var second := p.finish_run(won)
	assert_eq(first - second, Seals.prize(3), "the prize pays once")
	assert_eq(p.card_count(Seals.card(3)), 1)
	assert_eq(p.last_pay.prize, 0)
	var q := Profile.from_dict(p.to_dict())
	assert_eq(q.finish_run(won), second, "a reloaded profile remembers the prize")
	assert_eq(Profile.new().finish_run({"won": true, "seal": 0}), Profile.CRYSTAL_WIN, "WIZARD pays no prize")
	assert_eq(Profile.new().prize_left(1), 50)


## An Archlich's drop picked up during the run: the first win still names the card on the results line.
func test_a_first_win_names_the_seal_card_already_owned() -> void:
	var p := Profile.new()
	p.cards[Cards.key(Seals.card(3))] = 1
	p.finish_run({"won": true, "seal": 3})
	assert_eq(p.last_pay.card, Seals.card(3))
	assert_eq(p.card_count(Seals.card(3)), 1, "not paid twice")
	assert_true(Seals.pay_line(p.last_pay).contains(" CARD"))
	p.finish_run({"won": true, "seal": 3})
	assert_eq(p.last_pay.card, -1, "a second win names none")


## A stale Net.seal (another host's lobby) falls back to an open step; open steps and APPRENTICE stay.
func test_playable_seal_falls_back_from_a_locked_step() -> void:
	var p := Profile.new()
	assert_eq(p.playable_seal(9), Seals.START_UNLOCKED, "stale locked value falls back to the highest open step")
	assert_eq(p.playable_seal(1), 1, "open value kept")
	assert_eq(p.playable_seal(0), 0)
	assert_eq(p.playable_seal(Seals.MIN), Seals.MIN, "APPRENTICE kept")
	assert_eq(p.playable_seal(-5), 0, "below the ladder: WIZARD")
	p.seal_unlocked = 4
	assert_eq(p.playable_seal(9), 4)
	assert_eq(p.playable_seal(3), 3)


func test_wins_unlock_the_ladder_in_order() -> void:
	var p := Profile.new()
	for level: int in range(Seals.MIN, Seals.MAX + 1):
		assert_eq(p.seal_open(level), level <= 1, "a new profile opens APPRENTICE to ARCHMAGE: %d" % level)
	p.finish_run({"won": false, "seal": 1})
	assert_false(p.seal_open(2), "a loss opens nothing")
	p.finish_run({"won": true, "seal": -1})
	assert_false(p.seal_open(2), "winning lower opens nothing new")
	p.finish_run({"won": true, "seal": 1})
	assert_true(p.seal_open(2))
	assert_false(p.seal_open(3))
	assert_eq(p.seal_best, 1)
	p.finish_run({"won": true, "seal": 9})
	assert_eq(p.seal_unlocked, Seals.MAX)
	assert_eq(p.seal_best, 9)
	var q := Profile.from_dict(p.to_dict())
	assert_eq(q.seal_unlocked, Seals.MAX)
	assert_eq(q.seal_best, 9)


func test_kills_and_revives_add_up() -> void:
	var p := Profile.new()
	var res := Results.new([0, 1])
	res.add(0, "revives", 2)
	res.add(1, "revives", 1)
	p.finish_run({"kills": 300, "results": res})
	p.finish_run({"kills": 200, "revives": 4})
	assert_eq(p.kills_total, 500)
	assert_eq(p.revives_total, 7)
	var q := Profile.from_dict(p.to_dict())
	assert_eq(q.kills_total, 500)
	assert_eq(q.revives_total, 7)


## A profile saved before the ladder (this exact dictionary, as JSON gives it back) loads as it did, with the
## ladder at its start.
func test_an_old_profile_loads_unchanged() -> void:
	var old: Variant = JSON.parse_string('{"version": 1, "high_score": 4321, "crystals": 77, "runs": 9, "wins": 2, ' +
		'"best_time": 812.5, "unlocks": {"vigor": 1, "luck": 2}, "cards": {"orc": 2, "lich": 1}, ' +
		'"sockets": ["", "", "orc"], "secrets": ["moon"], "pots_run": 9, "pots_mask": 3, "wishes": 5}')
	var p := Profile.from_dict(old)
	assert_eq(p.high_score, 4321)
	assert_eq(p.crystals, 77)
	assert_eq(p.runs, 9)
	assert_eq(p.wins, 2)
	assert_eq(p.level("luck"), 2)
	assert_eq(p.card_count(World.ORC), 2)
	assert_eq(p.sockets[2], "orc")
	assert_true(p.has_secret("moon"))
	assert_eq(p.wishes, 5)
	assert_eq(p.seal_unlocked, Seals.START_UNLOCKED)
	assert_eq(p.seal_best, Seals.MIN - 1)
	assert_true(p.seal_prizes.is_empty())
	assert_eq(p.kills_total, 0)
	assert_eq(p.revives_total, 0)
	var back: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	for k: String in old:
		if k != "version":
			assert_eq(back[k], old[k], k)
	var bad := Profile.from_dict({"seal_unlocked": 99, "seal_best": -50, "seal_prizes": ["3", "x", 77]})
	assert_eq(bad.seal_unlocked, Seals.MAX)
	assert_eq(bad.seal_best, Seals.MIN - 1)
	assert_eq(bad.seal_prizes.keys(), ["3"])
