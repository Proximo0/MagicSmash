extends TestCase
## Fate: the fate deck a team shrine draws from (Gamble.TEAM_OUTCOMES, WorldShrines, World.EV_FATE).

const DT: float = 1.0 / 60.0
const AT := Vector2(200, 120)


func test_fate_codes_and_empty_objects() -> void:
	assert_true(World.EV_FATE > World.EV_LULL)
	var codes := [World.EV_DOWN, World.EV_REVIVE, World.EV_CALL, World.EV_REDRAW, World.EV_BANISH, World.EV_FATE,
		World.EV_SLOTS, World.EV_TALK]
	for k: int in codes.size():
		assert_eq(codes[k], World.EV_LULL + 1 + k, "event codes follow EV_LULL in order")
	var w := World.new([0], 3)
	assert_eq((w.snapshot()["o"] as PackedFloat32Array).size(), 0, "no spell objects yet")


func _world(slots: Array = [0, 1, 2, 3]) -> World:
	var w := World.new(slots, 3)
	w.phase = World.PH_FIGHT
	w.shrine_t = 99999.0
	w.team_shrine_t = 99999.0
	w.horde_budget = -99999.0
	for s: int in slots:
		(w.players[s] as World.Player).invuln = 99999.0
	return w


func _land(w: World, fate: int, slot: int = 0) -> void:
	w._resolve_gamble({"slot": slot, "kind": Gamble.TEAM, "outcome": fate, "stake": 40, "pos": AT})


## Lands every queued chain card in turn (deal, reel, land) and returns the fates drawn, in order, from EV_FATE.
func _play_out(w: World) -> Array[int]:
	var out: Array[int] = []
	for ev: Array in w.take_events():
		if ev[0] == World.EV_FATE:
			out.append(int(ev[3]))
	var guard: int = 0
	while not w._gambles.is_empty() and guard < 50:
		guard += 1
		var g: Dictionary = w._gambles.pop_front()
		w.wave_time = maxf(w.wave_time, float(g.t))
		WorldShrines._resolve_gamble(w, g)
		for ev: Array in w.take_events():
			if ev[0] == World.EV_FATE:
				out.append(int(ev[3]))
	assert_true(guard < 50, "the chain never ended")
	return out


func _elites(w: World) -> int:
	var n: int = 0
	for e: World.Enemy in w.enemies:
		if e.elite:
			n += 1
	return n


func _chests(w: World) -> int:
	var n: int = 0
	for k: World.Pickup in w.pickups:
		if k.kind == World.PK_CHEST:
			n += 1
	return n


func test_the_sun_raises_the_party_two_levels() -> void:
	var w := _world()
	_land(w, Gamble.TO_BLESSING)
	assert_eq(w.party_level, 1 + Gamble.BLESSING_LEVELS)


func test_death_takes_a_heart_and_sends_an_elite_each() -> void:
	var w := _world()
	_land(w, Gamble.TO_CURSE)
	assert_eq((w.players[2] as World.Player).hp, (w.players[2] as World.Player).max_hp - 1)
	assert_eq(_elites(w), 4)


func test_the_world_heals_and_pulls_every_gem() -> void:
	var w := _world([0, 1])
	var p: World.Player = w.players[0]
	p.hp = 1
	WorldDrops._drop(w, World.PK_XP, p.pos + Vector2(150, 0), Vector2.ZERO, 30.0, 1)
	var gem: World.Pickup = w.pickups[0]
	var far := gem.pos.distance_to(p.pos)
	_land(w, Gamble.TO_WORLD)
	assert_eq(p.hp, 1 + int(w.tune.fate_world_hearts))
	assert_true(w.gem_rush > 0.0)
	for _i: int in range(10):
		WorldDrops._update_pickups(w, DT)
	assert_true(gem.pos.distance_to(p.pos) < far - 10.0, "a far gem flies in")


func test_the_world_heals_the_fallen_only_once_they_stand() -> void:
	var w := _world([0, 1])
	var q: World.Player = w.players[1]
	q.alive = false
	q.down = true
	q.hp = 0
	_land(w, Gamble.TO_WORLD)
	WorldShrines._tick_fates(w, DT)
	assert_eq(q.hp, 0, "a spirit is not healed")
	q.down = false
	q.alive = true
	q.hp = 2
	WorldShrines._tick_fates(w, DT)
	assert_eq(q.hp, 2 + int(w.tune.fate_world_hearts), "the hearts wait for her to stand")
	WorldShrines._tick_fates(w, DT)
	assert_eq(q.hp, 2 + int(w.tune.fate_world_hearts), "and come once")


func test_the_emperor_gives_a_chest_to_each_human() -> void:
	var w := _world()
	(w.players[3] as World.Player).ai = true
	_land(w, Gamble.TO_EMPEROR)
	assert_eq(_chests(w), 3, "an apprentice gets no chest")


func test_the_hanged_man_seals_novas_and_drops_the_press() -> void:
	var w := _world([0, 1])
	var p: World.Player = w.players[0]
	_land(w, Gamble.TO_HANGED)
	assert_eq(w.nova_sealed, w.tune.fate_hanged_secs)
	var bombs := p.bombs
	var inp := PackedFloat32Array([0, 0, 0, 0, 0, 0])
	w._update_player(p, DT, inp)
	inp[5] = 1
	w._update_player(p, DT, inp)
	assert_eq(p.bombs, bombs, "a sealed nova does not fire")
	w.nova_sealed = 0.0
	w._update_player(p, DT, inp)
	assert_eq(p.bombs, bombs, "the press made while sealed is not kept for later")
	inp[5] = 2
	w._update_player(p, DT, inp)
	assert_eq(p.bombs, bombs - 1, "a new press fires once the seal is gone")
	_land(w, Gamble.TO_HANGED)
	WorldShrines._tick_fates(w, 10.0)
	assert_near(w.nova_sealed, w.tune.fate_hanged_secs - 10.0, 0.01)
	assert_true((w.snapshot()["f"] as PackedFloat32Array)[0] > 0.0, "the snapshot carries the seal")


func _potions(w: World) -> int:
	var n: int = 0
	for k: World.Pickup in w.pickups:
		if k.kind == World.PK_POTION:
			n += 1
	return n


func test_the_hierophant_stops_potions() -> void:
	var w := _world([0, 1])
	_land(w, Gamble.TO_HIEROPHANT)
	assert_eq(w.no_potions, w.tune.fate_hierophant_secs)
	var e := World.Enemy.new()
	e.type = World.SKELETON
	e.pos = AT
	for _i: int in range(1500):
		WorldDrops._roll_drop(w, e)
		WorldDrops._break_urn(w, AT)
	assert_eq(_potions(w), 0, "no potion drops while the Hierophant holds")
	w.no_potions = 0.0
	for _i: int in range(1500):
		WorldDrops._roll_drop(w, e)
		WorldDrops._break_urn(w, AT)
	assert_true(_potions(w) > 0, "potions drop again after")


func test_the_wheel_draws_two_more_and_never_itself() -> void:
	for seed_value: int in range(1, 30):
		var w := _world()
		w.rng.seed = seed_value
		w.fate_cruel = float(seed_value % 2) # all cruel (no Fool to double) or all kind after the Wheel
		_land(w, Gamble.TO_WHEEL)
		var drawn := _play_out(w)
		assert_eq(drawn[0], Gamble.TO_WHEEL)
		var fools: int = drawn.count(Gamble.TO_FOOL)
		assert_eq(drawn.size(), 3, "the wheel and two more: %s" % [drawn])
		assert_eq(drawn.count(Gamble.TO_WHEEL), 1, "the wheel cannot draw itself: %s" % [drawn])
		assert_eq(w.record.fates, drawn, "results record the fates in order")
		assert_eq(w.fate_twice, drawn[2] == Gamble.TO_FOOL, "a fool last in the chain waits for the next shrine")
		assert_true(fools <= 2)


func test_the_fool_doubles_the_next_fate() -> void:
	var w := _world()
	_land(w, Gamble.TO_FOOL)
	assert_true(w.fate_twice)
	_land(w, Gamble.TO_BLESSING)
	assert_eq(w.party_level, 1 + 2 * Gamble.BLESSING_LEVELS)
	assert_false(w.fate_twice, "only the next fate")
	_land(w, Gamble.TO_HIEROPHANT)
	assert_eq(w.no_potions, w.tune.fate_hierophant_secs)


func test_the_fool_carries_across_two_shrines() -> void:
	var w := _world()
	w.fate_cruel = 1.0
	w.team_shrine_t = 0.0
	w.shrine_t = 99999.0
	_land(w, Gamble.TO_FOOL)
	assert_true((w.snapshot()["f"] as PackedFloat32Array)[3] > 0.0, "the snapshot carries the Fool's double")
	# A second team shrine, paid by a wizard standing on it: its fate counts twice.
	WorldShrines._update_shrines(w, DT)
	var sh: World.Shrine = w.shrines[0]
	var p: World.Player = w.players[0]
	p.gold = sh.cost
	WorldShrines._bet(w, sh, p)
	var g: Dictionary = w._gambles[0]
	var fate := int(g.outcome)
	assert_false(Gamble.is_good(Gamble.TEAM, fate))
	var drawn := _play_out(w)
	assert_eq(drawn[0], Gamble.TO_FOOL)
	assert_eq(drawn[1], fate)
	match fate:
		Gamble.TO_CURSE:
			assert_eq(_elites(w), 8)
		Gamble.TO_HANGED:
			assert_eq(w.nova_sealed, 2.0 * w.tune.fate_hanged_secs)
		Gamble.TO_HIEROPHANT:
			assert_eq(w.no_potions, 2.0 * w.tune.fate_hierophant_secs)
		Gamble.TO_WHEEL:
			assert_eq(drawn.size(), 2 + 2 * int(w.tune.fate_wheel_draws), "a doubled wheel draws four: %s" % [drawn])


func test_the_fool_doubling_the_wheel_means_four_fates() -> void:
	var w := _world()
	w.fate_cruel = 1.0
	_land(w, Gamble.TO_FOOL)
	_land(w, Gamble.TO_WHEEL)
	var drawn := _play_out(w)
	assert_eq(drawn.size(), 2 + 4, "%s" % [drawn])
	assert_eq(drawn.count(Gamble.TO_WHEEL), 1)


func test_ev_fate_carries_the_id_and_the_slot() -> void:
	var w := _world()
	w.take_events()
	_land(w, Gamble.TO_EMPEROR, 2)
	var found := false
	for ev: Array in w.take_events():
		if ev[0] == World.EV_FATE:
			found = true
			assert_eq(int(ev[3]), Gamble.TO_EMPEROR)
			assert_eq(int(ev[4]), 2)
	assert_true(found)


func test_results_keep_the_fates_through_a_dict() -> void:
	var r := Results.new([0, 1])
	r.fates.append(Gamble.TO_FOOL)
	r.fates.append(Gamble.TO_WHEEL)
	var back := Results.from_dict(r.to_dict())
	assert_eq(back.fates, r.fates)
	assert_eq(Results.from_dict({}).fates.size(), 0)


func test_a_solo_run_keeps_the_sun_or_death_flip() -> void:
	var w := _world([0])
	w.fate_cruel = 1.0
	for _i: int in range(200):
		var twin := RandomNumberGenerator.new()
		twin.seed = w.rng.seed
		twin.state = w.rng.state
		var f := WorldShrines._first_draw(w, Gamble.TEAM)
		assert_eq(f, Gamble.roll(twin, Gamble.TEAM), "the same roll as before the deck")
		assert_eq(twin.state, w.rng.state, "and the same draws from the rng")
	assert_false(w.snapshot().has("f"), "no fate in force: the snapshot is as before")


func test_a_solo_run_places_the_team_shrine_as_before() -> void:
	# Today a solo run also gets the team shrine; it keeps the coin flip (above) and the old timers.
	var w := _world([0])
	w.team_shrine_t = 0.0
	WorldShrines._update_shrines(w, DT)
	assert_eq(w.shrines.size(), 1)
	assert_eq(w.shrines[0].kind, Gamble.TEAM)


func test_n10_the_boss_music_survives_a_fate_reel() -> void:
	assert_eq(ArenaFateView._after_reel_music(0.6, "music_battle"), "music_boss")
	assert_eq(ArenaFateView._after_reel_music(-1.0, "music_library"), "music_library")
	assert_eq(ArenaFateView._after_reel_music(0.0, "music_battle"), "music_battle")
