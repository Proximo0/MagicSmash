extends TestCase
## World: the authoritative simulation (game/logic/world.gd).

const DT: float = 1.0 / 60.0


func _run_bots(seed_value: int, slots: Array, ticks: int) -> World:
	var w := World.new(slots, seed_value)
	var bots: Dictionary = {}
	for s: int in slots:
		bots[s] = SmashBot.new(seed_value + s)
	for _i: int in range(ticks):
		var inputs: Dictionary = {}
		for s: int in slots:
			inputs[s] = (bots[s] as SmashBot).decide_in_world(w, s)
		w.step(DT, inputs)
	return w


func test_same_seed_same_run() -> void:
	var a: World = _run_bots(7, [0, 1], 900)
	var b: World = _run_bots(7, [0, 1], 900)
	assert_eq(a.state_hash(), b.state_hash(), "seed 7 runs diverged")


func test_different_seed_different_run() -> void:
	var a: World = _run_bots(7, [0, 1], 900)
	var b: World = _run_bots(8, [0, 1], 900)
	assert_true(a.state_hash() != b.state_hash(), "seeds 7 and 8 gave the same run")


func test_first_wave_spawns_after_intro() -> void:
	var w := World.new([0], 3)
	assert_eq(w.phase, World.PH_INTRO)
	for _i: int in range(60 * 6):
		w.step(DT, {})
	assert_eq(w.phase, World.PH_FIGHT)
	assert_true(w.enemies.size() > 0, "no enemies 6 s into wave 1")


func test_player_stays_inside_arena() -> void:
	var w := World.new([0], 3)
	var right := PackedFloat32Array([1, 0, 0, 0, 0, 0])
	for _i: int in range(60 * 5):
		w.step(DT, {0: right})
	var p: World.Player = w.players[0]
	assert_true(p.pos.x <= G.ARENA.end.x, "player left the arena: x=%.1f" % p.pos.x)


func test_nova_spends_a_bomb() -> void:
	var w := World.new([0], 3)
	var p: World.Player = w.players[0]
	var bombs: int = p.bombs
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 0])})
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 1])})
	assert_eq(p.bombs, bombs - 1)


func test_total_score_sums_players() -> void:
	var w := World.new([0, 1], 3)
	(w.players[0] as World.Player).score = 120
	(w.players[1] as World.Player).score = 30
	assert_eq(w.total_score(), 150)


func _player(w: World, slot: int = 0) -> World.Player:
	return w.players[slot] as World.Player


func _kill_one(w: World) -> World.Enemy:
	var e: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(100, 100))
	w._kill_enemy(e, 0)
	return e


func test_kills_drop_xp_gems_worth_the_enemy_value() -> void:
	var w := World.new([0], 3)
	_kill_one(w)
	var gems: Array = w.pickups.filter(func(k: World.Pickup) -> bool: return k.kind == World.PK_XP)
	assert_eq(gems.size(), 1)
	assert_eq((gems[0] as World.Pickup).value, World.XP_VALUES[World.ORC])


func test_collecting_xp_levels_up_and_offers_choices() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	w.gain_xp(p, w.tune.xp_to_next(1))
	assert_eq(p.level, 2)
	assert_eq(p.xp, 0)
	assert_eq(p.pending, 1)
	w.step(DT, {})
	assert_eq(p.choices.size(), int(w.tune.level_choices))
	assert_eq(p.pending, 0)
	assert_true(w.is_picking())


func test_world_waits_while_a_player_picks() -> void:
	var w := World.new([0, 1], 3)
	for _i: int in range(60 * 5):
		w.step(DT, {})
	w.gain_xp(_player(w), w.tune.xp_to_next(1))
	w.step(DT, {})
	var t0: float = w.time
	var e_pos: Array = w.enemies.map(func(e: World.Enemy) -> Vector2: return e.pos)
	for _i: int in range(120):
		w.step(DT, {})
	assert_near(w.time, t0, 0.0001, "time moved during a pick")
	assert_eq(w.enemies.map(func(e: World.Enemy) -> Vector2: return e.pos), e_pos, "enemies moved during a pick")


func test_pick_applies_upgrade_and_resumes() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	w.gain_xp(p, w.tune.xp_to_next(1))
	w.step(DT, {})
	var want: int = p.choices[1]
	var t0: float = w.time
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, p.offer])})
	assert_eq(Upgrades.level_of(p.upgrades, want), 1)
	assert_true(p.choices.is_empty())
	assert_false(w.is_picking())
	assert_true(w.time > t0, "world should run again on the pick tick")


func test_pick_for_a_stale_offer_is_ignored() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	w.gain_xp(p, w.tune.xp_to_next(1))
	w.step(DT, {})
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, p.offer - 1])})
	assert_true(w.is_picking(), "a pick naming an old offer must not apply")


func test_two_level_ups_offer_twice() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	w.gain_xp(p, w.tune.xp_to_next(1) + w.tune.xp_to_next(2))
	assert_eq(p.level, 3)
	w.step(DT, {})
	var first_offer: int = p.offer
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, p.offer])})
	assert_eq(p.offer, first_offer + 1, "second offer should open right after the first pick")
	assert_true(w.is_picking())


func test_each_player_picks_for_themselves() -> void:
	var w := World.new([0, 1], 3)
	w.gain_xp(_player(w, 0), w.tune.xp_to_next(1))
	w.gain_xp(_player(w, 1), w.tune.xp_to_next(1))
	w.step(DT, {})
	var p0 := _player(w, 0)
	var p1 := _player(w, 1)
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, p0.offer])})
	assert_true(p0.choices.is_empty())
	assert_true(w.is_picking(), "P2 has not picked yet")
	w.step(DT, {1: PackedFloat32Array([0, 0, 0, 0, 0, 0, 2, p1.offer])})
	assert_false(w.is_picking())


func test_nova_press_during_pick_does_not_fire_later() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 0])})
	w.gain_xp(p, w.tune.xp_to_next(1))
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 0])})
	var bombs: int = p.bombs
	# Space confirms the card and also bumps the nova counter.
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 1, -1, p.offer])})
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 1, 0, p.offer])})
	w.step(DT, {0: PackedFloat32Array([0, 0, 0, 0, 0, 1])})
	assert_eq(p.bombs, bombs + (1 if Upgrades.level_of(p.upgrades, Upgrades.NOVA) > 0 else 0), "nova fired after the pick")


func test_power_upgrade_raises_damage() -> void:
	var w := World.new([0], 3)
	var a: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(100, 100))
	w._damage_enemy(a, 1.0, 0, Vector2.ZERO)
	var plain: float = a.maxhp - a.hp
	Upgrades.take(_player(w).upgrades, Upgrades.POWER)
	var b: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(140, 100))
	w._damage_enemy(b, 1.0, 0, Vector2.ZERO)
	assert_near(b.maxhp - b.hp, plain * 1.15, 0.0001)


func test_xp_gem_flies_to_a_near_wizard() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	w._drop(World.PK_XP, p.pos + Vector2(20, 0), Vector2.ZERO, 30.0, 3)
	for _i: int in range(60):
		w.step(DT, {})
	assert_eq(p.xp, 3, "the gem should have reached the wizard")


func test_snapshot_player_block_size() -> void:
	var w := World.new([0, 1], 3)
	assert_eq((w.snapshot()["p"] as PackedFloat32Array).size(), World.PLAYER_FLOATS * 2)
