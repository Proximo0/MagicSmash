extends TestCase
## The team shrine the whole table pays into (WorldShrines pot, its snapshot row, the play-bot's rule).

const DT: float = 1.0 / 60.0
const AT := Vector2(200, 120)
const FAR := Vector2(420, 300)
const COST := 120


func _world(slots: Array = [0, 1]) -> World:
	var w := World.new(slots, 3)
	w.phase = World.PH_FIGHT
	w.shrine_t = 99999.0
	w.team_shrine_t = 99999.0
	w.horde_budget = -99999.0
	for s: int in slots:
		var p: World.Player = w.players[s]
		p.invuln = 99999.0
		p.pos = FAR + Vector2(s * 3, 0)
		p.gold = 1000.0
	return w


func _shrine(w: World, kind: int = Gamble.TEAM) -> World.Shrine:
	var sh := World.Shrine.new()
	sh.kind = kind
	sh.pos = AT
	sh.cost = COST
	sh.life = 99.0
	w.shrines.append(sh)
	return sh


func _stand(w: World, slots: Array) -> void:
	for s: int in slots:
		(w.players[s] as World.Player).pos = AT


func _tick(w: World, seconds: float) -> void:
	for _i: int in range(roundi(seconds / DT)):
		WorldShrines._update_shrines(w, DT)


func _row(w: World) -> Array:
	return WorldShrines.snapshot_shrines(w)[0]


func _spent(w: World, slot: int) -> float:
	return 1000.0 - (w.players[slot] as World.Player).gold


func test_two_wizards_fill_the_pot_in_team_pay_time_and_each_pays_half() -> void:
	var w := _world([0, 1])
	var sh := _shrine(w)
	_stand(w, [0, 1])
	_tick(w, w.tune.team_pay_time - 0.1)
	assert_eq(w.shrines.size(), 1, "not full before team_pay_time")
	assert_near(_row(w)[4], (w.tune.team_pay_time - 0.1) / w.tune.team_pay_time, 0.01, "the row's fraction is pot / price")
	assert_eq(int(_row(w)[6]), 0, "nobody else is needed")
	_tick(w, 0.2)
	assert_true(w.shrines.is_empty(), "the full pot bets")
	assert_eq(w._gambles.size(), 1)
	assert_eq(int(w._gambles[0].stake), COST, "the stake is the price")
	assert_near(_spent(w, 0), COST / 2.0, 0.001)
	assert_near(_spent(w, 1), COST / 2.0, 0.001)
	assert_eq(sh.life, 0.0)


func test_one_wizard_with_a_living_partner_elsewhere_fills_nothing() -> void:
	var w := _world([0, 1])
	var sh := _shrine(w)
	assert_eq(int(_row(w)[6]), 2, "two wizards needed while nobody stands")
	_stand(w, [0])
	_tick(w, 3.0)
	assert_near(sh.pot, 0.0)
	assert_near(_spent(w, 0), 0.0)
	assert_eq(int(_row(w)[6]), 1, "one more needed")
	assert_eq(w.shrines.size(), 1)


func test_the_pot_waits_when_one_steps_out() -> void:
	var w := _world([0, 1])
	var sh := _shrine(w)
	_stand(w, [0, 1])
	_tick(w, w.tune.team_pay_time / 2.0)
	var half := sh.pot
	(w.players[1] as World.Player).pos = FAR
	_tick(w, 3.0)
	assert_near(sh.pot, half, 0.0001, "the pot never drains while the shrine lives")


func test_a_lone_survivor_may_fill_it() -> void:
	var w := _world([0, 1])
	var sh := _shrine(w)
	(w.players[1] as World.Player).alive = false
	(w.players[1] as World.Player).down = true
	assert_eq(int(_row(w)[6]), 1, "one living human: one is enough")
	_stand(w, [0])
	_tick(w, w.tune.team_pay_time + 0.1)
	assert_true(w.shrines.is_empty())
	assert_near(_spent(w, 0), float(COST), 0.001)
	assert_eq(int(w._gambles[0].slot), 0)
	assert_true(sh.pot >= COST - 0.001)


func test_a_solo_run_needs_one() -> void:
	var w := _world([0])
	_shrine(w)
	assert_eq(int(_row(w)[6]), 1)
	_stand(w, [0])
	WorldShrines._update_shrines(w, DT)
	assert_eq(int(_row(w)[6]), 0)


func test_an_apprentice_is_not_a_partner_and_never_pays() -> void:
	var w := World.new([0, 1], 3, null, {}, {1: {"ai": true}})
	w.phase = World.PH_FIGHT
	w.shrine_t = 99999.0
	w.team_shrine_t = 99999.0
	for p: World.Player in w.players.values():
		p.gold = 1000.0
	_shrine(w)
	_stand(w, [0, 1])
	assert_eq(int(_row(w)[6]), 0, "one living human: she alone is enough")
	_tick(w, w.tune.team_pay_time + 0.1)
	assert_near((w.players[1] as World.Player).gold, 1000.0, 0.0001, "the apprentice pays nothing")
	assert_near((w.players[0] as World.Player).gold, 1000.0 - COST, 0.001)


func test_a_wizard_who_runs_dry_is_covered_by_the_other() -> void:
	var w := _world([0, 1])
	(w.players[0] as World.Player).gold = 10.0
	_shrine(w)
	_stand(w, [0, 1])
	_tick(w, w.tune.team_pay_time + 0.05)
	assert_true(w.shrines.is_empty(), "the other covers in the same step: the pot fills on time")
	assert_near((w.players[0] as World.Player).gold, 0.0, 0.0001)
	assert_near(_spent(w, 1), COST - 10.0, 0.001)
	assert_eq(int(w._gambles[0].slot), 1, "the biggest payer is who")


func test_a_broke_wizard_still_counts_as_the_second() -> void:
	var w := _world([0, 1])
	(w.players[0] as World.Player).gold = 0.0
	_shrine(w)
	_stand(w, [0, 1])
	_tick(w, w.tune.team_pay_time + 0.05)
	assert_true(w.shrines.is_empty())
	assert_near(_spent(w, 1), float(COST), 0.001)


func test_four_wizards_pay_a_quarter_each_and_a_tie_goes_to_the_lowest_slot() -> void:
	var w := _world([0, 1, 2, 3])
	_shrine(w)
	_stand(w, [3, 1, 2, 0])
	_tick(w, w.tune.team_pay_time + 0.05)
	assert_true(w.shrines.is_empty())
	for s: int in 4:
		assert_near(_spent(w, s), COST / 4.0, 0.001)
	assert_eq(int(w._gambles[0].slot), 0, "a tie goes to the lowest slot")


func test_bets_are_booked_only_at_the_bet_each_her_own_share() -> void:
	var w := _world([0, 1])
	(w.players[1] as World.Player).gold = 20.0
	_shrine(w)
	_stand(w, [0, 1])
	_tick(w, w.tune.team_pay_time / 2.0)
	assert_eq(w.record.stat(0, "bets"), 0.0, "nothing booked before the bet")
	assert_eq(w.record.stat(1, "bets"), 0.0)
	_tick(w, w.tune.team_pay_time)
	assert_near(w.record.stat(0, "bets"), COST - 20.0, 0.001)
	assert_near(w.record.stat(1, "bets"), 20.0, 0.001)


func test_a_shrine_that_fades_half_full_gives_everything_back() -> void:
	var w := _world([0, 1, 2])
	(w.players[2] as World.Player).gold = 7.25
	var sh := _shrine(w)
	_stand(w, [0, 1, 2])
	_tick(w, w.tune.team_pay_time / 2.0)
	assert_true(sh.pot > 0.0)
	sh.life = DT / 2.0
	WorldShrines._update_shrines(w, DT)
	assert_true(w.shrines.is_empty(), "it faded")
	assert_true(w._gambles.is_empty(), "no bet")
	assert_near((w.players[0] as World.Player).gold, 1000.0, 0.0001)
	assert_near((w.players[1] as World.Player).gold, 1000.0, 0.0001)
	assert_near((w.players[2] as World.Player).gold, 7.25, 0.0001)
	assert_eq(w.record.stat(0, "bets"), 0.0)


func test_the_rows_seventh_value_while_wizards_step_in() -> void:
	var w := _world([0, 1, 2])
	_shrine(w)
	_shrine(w, Gamble.SOLO)
	var rows := WorldShrines.snapshot_shrines(w)
	assert_eq(rows[0].size(), 7)
	assert_eq(int(rows[0][6]), 2)
	assert_eq(int(rows[1][6]), 0, "a solo shrine never needs anyone")
	assert_eq(int(rows[0][5]), COST, "the first six keep their places")
	assert_near(rows[0][1], AT.x)
	_stand(w, [2])
	assert_eq(int(WorldShrines.snapshot_shrines(w)[0][6]), 1)
	_stand(w, [1])
	assert_eq(int(WorldShrines.snapshot_shrines(w)[0][6]), 0)


func test_a_solo_shrine_behaves_as_before() -> void:
	var w := _world([0, 1])
	var sh := _shrine(w, Gamble.SOLO)
	_stand(w, [0, 1])
	_tick(w, w.tune.shrine_hold - 0.1)
	assert_eq(w.shrines.size(), 1)
	assert_near(_row(w)[4], (w.tune.shrine_hold - 0.1) / w.tune.shrine_hold, 0.02)
	_tick(w, 0.2)
	assert_true(w.shrines.is_empty())
	assert_near(_spent(w, 0), float(COST), 0.0001, "the first who can pay pays it all")
	assert_near(_spent(w, 1), 0.0)
	assert_eq(w.record.stat(0, "bets"), float(COST))
	assert_eq(sh.who, 0)


func test_the_team_price_is_shared() -> void:
	var t := Tuning.new()
	assert_near(t.team_cost_mul, 1.5)
	assert_near(t.team_pay_time, 2.0)


func test_a_fate_that_lands_is_credited_once() -> void:
	var w := _world([0, 1])
	w.fate_twice = true # THE FOOL doubles it; it is still one fate landed
	w._resolve_gamble({"slot": 1, "kind": Gamble.TEAM, "outcome": Gamble.TO_EMPEROR, "stake": 40, "pos": AT})
	assert_eq(w.record.used("emperor"), 1)
	for i: int in Gamble.TEAM_OUTCOMES.size():
		if i != Gamble.TO_EMPEROR:
			assert_eq(w.record.used(Gamble.TEAM_OUTCOMES[i][0]), 0)


func test_a_paid_pot_credits_the_fate_it_draws() -> void:
	var w := _world([0, 1])
	_shrine(w)
	_stand(w, [0, 1])
	_tick(w, w.tune.team_pay_time + 0.1)
	assert_eq(w.record.fates.size(), 0, "nothing lands while the reel spins")
	w.wave_time += w.tune.team_reel + 0.1 # the reel lands on the fight's clock
	WorldShrines._update_shrines(w, DT)
	assert_eq(w.record.fates.size(), 1)
	var fate := int(w.record.fates[0])
	assert_eq(w.record.used(Gamble.TEAM_OUTCOMES[fate][0]), 1)


# ------------------------------------------------------------------ bots ---
func _rows(frac: float, need: int = 1) -> Array:
	return [[Gamble.TEAM, AT.x, AT.y, 50.0, frac, COST, need]]


func test_a_bot_goes_when_the_table_can_pay() -> void:
	var me := AT + Vector2(60, 0)
	assert_eq(SmashBot.shrine_goal(me, 10.0, _rows(0.5), 60.0), AT, "the table covers the half the pot lacks")
	assert_eq(SmashBot.shrine_goal(me, 10.0, _rows(0.0), 60.0), Vector2.INF, "the table cannot cover the price")
	assert_eq(SmashBot.shrine_goal(me, 0.0, _rows(0.5), 600.0), Vector2.INF, "she has no gold herself")
	var solo := [[Gamble.SOLO, AT.x, AT.y, 50.0, 0.0, COST, 0]]
	assert_eq(SmashBot.shrine_goal(me, COST, solo, COST), AT, "a solo shrine: she pays it alone, as before")
	assert_eq(SmashBot.shrine_goal(me, COST - 1.0, solo, 9999.0), Vector2.INF)


func test_a_bot_gives_up_after_shrine_patience() -> void:
	var bot := SmashBot.new(1)
	var t := 0.0
	while t < SmashBot.SHRINE_PATIENCE - 0.2:
		assert_eq(bot.shrine_pick(AT, 100.0, 300.0, _rows(0.25), t), AT, "she waits for a partner")
		t += 0.1
	t += 0.4
	assert_eq(bot.shrine_pick(AT, 100.0, 300.0, _rows(0.25), t), Vector2.INF, "no growth for SHRINE_PATIENCE: she gives up")
	assert_eq(bot.shrine_pick(AT, 100.0, 300.0, _rows(0.5), t + 0.1), Vector2.INF, "alone in it she stays away, whatever the pot shows")


## A bot that has just given up the shrine at AT (she stood there alone for SHRINE_PATIENCE), and the time it is now.
func _bot_that_gave_up() -> Array:
	var bot := SmashBot.new(1)
	var t := 0.0
	while bot.shrine_pick(AT, 100.0, 300.0, _rows(0.25), t).is_finite():
		t += 0.1
	return [bot, t]


func test_a_bot_that_gave_up_comes_back_when_a_partner_steps_in() -> void:
	var got := _bot_that_gave_up()
	var bot: SmashBot = got[0]
	var t: float = got[1]
	var away := AT + Vector2(80, 0)
	assert_eq(bot.shrine_pick(away, 100.0, 300.0, _rows(0.25, 2), t + 0.1), Vector2.INF, "nobody stands in it: she stays away")
	assert_eq(bot.shrine_pick(away, 100.0, 300.0, _rows(0.25, 1), t + 0.2), AT, "a partner stands in it: she goes back")
	assert_eq(bot.shrine_pick(away, 100.0, 300.0, _rows(0.25, 2), t + 0.3), AT, "and is on her way even if the partner steps out")
	# Back in it, her patience starts over: she waits SHRINE_PATIENCE again before she gives it up a second time.
	t += 0.4
	var stood := 0.0
	while bot.shrine_pick(AT, 100.0, 300.0, _rows(0.25, 1), t).is_finite():
		t += 0.1
		stood += 0.1
	assert_near(stood, SmashBot.SHRINE_PATIENCE, 0.25)


func test_a_bot_leaving_a_shrine_turns_back_when_a_partner_steps_in_beside_her() -> void:
	var got := _bot_that_gave_up()
	var bot: SmashBot = got[0]
	var t: float = got[1]
	assert_eq(bot.shrine_pick(AT, 100.0, 300.0, _rows(0.25, 1), t + 0.1), Vector2.INF, "still alone in it")
	assert_eq(bot.shrine_pick(AT, 100.0, 300.0, _rows(0.25, 0), t + 0.2), AT, "two stand in it now: the pot will fill")


func test_the_last_wizard_left_takes_up_a_shrine_she_gave_up() -> void:
	var got := _bot_that_gave_up()
	var bot: SmashBot = got[0]
	var t: float = got[1]
	var away := AT + Vector2(80, 0)
	# Her partner fell: the row needs one wizard, and that is her. Her own gold must cover what the pot lacks.
	assert_eq(bot.shrine_pick(away, 100.0, 100.0, _rows(0.25, 1), t + 0.1), AT)


func test_a_bot_keeps_paying_while_the_pot_grows() -> void:
	var bot := SmashBot.new(1)
	var t := 0.0
	var frac := 0.0
	while t < SmashBot.SHRINE_PATIENCE * 2.0:
		assert_eq(bot.shrine_pick(AT, 100.0, 300.0, _rows(frac, 0), t), AT)
		t += 0.1
		frac += 0.01


func test_patience_counts_only_while_she_stands_there() -> void:
	var bot := SmashBot.new(1)
	var away := AT + Vector2(80, 0)
	for i: int in 100:
		assert_eq(bot.shrine_pick(away, 100.0, 300.0, _rows(0.25), i * 0.1), AT, "walking there is not waiting")
