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


func _casts(w: World, ticks: int, inp: Dictionary = {}) -> int:
	var n: int = 0
	for _i: int in range(ticks):
		w.step(DT, inp)
		for ev: Array in w.take_events():
			if ev[0] == World.EV_CAST:
				n += 1
	return n


func test_each_wizard_starts_with_its_spell() -> void:
	var w := World.new([0, 1, 2, 3], 3)
	for s: int in [0, 1, 2, 3]:
		var p := _player(w, s)
		assert_eq(p.wizard, s, "a slot with no pick plays its own colour")
		var sp: int = Wizards.start_spell(s)
		assert_eq(Upgrades.weapon_level(p.upgrades, sp), 1)
		assert_eq(p.spell, sp)
		var owned: int = 0
		for k: int in Spells.COUNT:
			owned += Upgrades.weapon_level(p.upgrades, k)
		assert_eq(owned, 1, "slot %d starts with one weapon" % s)


func test_picked_wizards_are_kept_and_sent() -> void:
	var w := World.new([0, 1], 3, null, {0: 3, 1: 1})
	assert_eq(_player(w, 0).wizard, 3)
	assert_eq(Upgrades.weapon_level(_player(w, 0).upgrades, Wizards.start_spell(3)), 1)
	assert_eq(Upgrades.weapon_level(_player(w, 0).upgrades, World.SP_ARCANE), 0)
	var pl: PackedFloat32Array = w.snapshot().p
	assert_eq(int(pl[10]), 3)
	assert_eq(int(pl[World.PLAYER_FLOATS + 10]), 1)


func test_spells_auto_cast_at_the_nearest_enemy() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	assert_eq(_casts(w, 30), 0, "cast with nothing in range")
	var e: World.Enemy = w.spawn_enemy(World.ORC, 0, p.pos + Vector2(0, 60))
	assert_true(_casts(w, 30) > 0, "no cast at an enemy in range")
	assert_true(p.aim.dot((e.pos - p.pos).normalized()) > 0.9, "aim %s does not point at the enemy" % p.aim)


func test_every_owned_weapon_casts() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	p.upgrades[Upgrades.weapon_entry(World.SP_FROST)] = 1
	var seen: Dictionary = {}
	for _i: int in range(90):
		w.step(DT, {0: PackedFloat32Array([0, 0, 1, 0, 0, 0])})
		for ev: Array in w.take_events():
			if ev[0] == World.EV_CAST:
				seen[int(ev[3])] = true
	assert_eq(seen.keys().size(), 2, "spells cast: %s" % [seen.keys()])


func test_tome_grants_and_levels_its_weapon() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	var tome := World.Pickup.new()
	tome.kind = World.PK_TOME_FIRE
	w._collect(p, tome)
	assert_eq(Upgrades.weapon_level(p.upgrades, World.SP_FIRE), 1)
	assert_eq(p.spell, World.SP_FIRE, "a new weapon tied with arcane becomes the main spell")
	w._collect(p, tome)
	assert_eq(Upgrades.weapon_level(p.upgrades, World.SP_FIRE), 2)
	p.upgrades[Upgrades.weapon_entry(World.SP_FIRE)] = Spells.MAX_LEVEL
	var score: int = p.score
	w._collect(p, tome)
	assert_eq(Upgrades.weapon_level(p.upgrades, World.SP_FIRE), Spells.MAX_LEVEL)
	assert_eq(p.score, score + 500, "a maxed weapon's tome is worth points")


func test_weapons_survive_death() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	p.upgrades[Upgrades.weapon_entry(World.SP_STAR)] = 3
	w._refresh_spell(p)
	p.invuln = 0.0
	w.hurt_player(p, 9)
	assert_false(p.alive)
	assert_eq(p.spell, World.SP_STAR)
	assert_eq(Upgrades.weapon_level(p.upgrades, World.SP_STAR), 3)


func _orcs_hit(evo: bool) -> int:
	var w := World.new([0], 3)
	var orcs: Array[World.Enemy] = []
	for i: int in range(3):
		orcs.append(w.spawn_enemy(World.ORC, 0, Vector2(200 + i * 18, 120)))
	var pierce: int = int(Spells.evo_value(World.SP_ARCANE, "pierce", 0.0)) if evo else 0
	w._shot(0, World.SP_ARCANE, evo, Vector2(170, 113), Vector2(310, 0), 1.0, pierce)
	for _i: int in range(30):
		w._build_grid()
		w._update_shots(DT)
	var hit: int = 0
	for o: World.Enemy in orcs:
		if o.hp < o.maxhp:
			hit += 1
	return hit


func test_astral_lance_pierces() -> void:
	assert_eq(_orcs_hit(false), 1)
	assert_eq(_orcs_hit(true), 3)


func _blast_zaps(evo: bool) -> bool:
	var w := World.new([0], 3)
	w.spawn_enemy(World.ORC, 0, Vector2(200, 120))
	var far: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(255, 120))
	w._build_grid()
	var s := World.Shot.new()
	s.pos = Vector2(200, 116)
	s.spell = World.SP_FIRE
	s.evo = evo
	s.dmg = 2.0
	w._explode(s)
	var zapped: bool = false
	for ev: Array in w.take_events():
		if ev[0] == World.EV_ZAP:
			zapped = true
	assert_eq(zapped, far.hp < far.maxhp, "a zap should hurt the orc out of blast range")
	return zapped


func test_thunderfire_blasts_fork_lightning() -> void:
	assert_false(_blast_zaps(false))
	assert_true(_blast_zaps(true))


func test_tempest_casts_two_chains() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	w.spawn_enemy(World.ORC, 0, p.pos + Vector2(60, -10))
	w.spawn_enemy(World.ORC, 0, p.pos + Vector2(60, 30))
	w._build_grid()
	w.take_events()
	w._cast(p, World.SP_STORM, Spells.MAX_LEVEL, true, Vector2.RIGHT)
	var zaps: int = 0
	for ev: Array in w.take_events():
		if ev[0] == World.EV_ZAP:
			zaps += 1
	assert_eq(zaps, 2)


func test_comet_rain_bursts_into_ice() -> void:
	var w := World.new([0], 3)
	var a: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(200, 120))
	var b: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(220, 120))
	w._build_grid()
	w._shot(0, World.SP_STAR, true, Vector2(200, 114), Vector2(1, 0), 2.0, 0)
	w._shot_hit(w.shots[0], a)
	assert_true(b.slow > 0.0 and b.hp < b.maxhp, "the neighbour was not caught in the burst")


func test_snapshot_sends_weapon_levels() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	p.upgrades[Upgrades.weapon_entry(World.SP_FIRE)] = Spells.MAX_LEVEL
	p.upgrades[Upgrades.evo_entry(World.SP_FIRE)] = 1
	p.upgrades[Upgrades.weapon_entry(World.SP_RUNE)] = 2
	var pl: PackedFloat32Array = w.snapshot()["p"]
	assert_eq(pl.size(), World.PLAYER_FLOATS)
	assert_eq(int(pl[World.PLAYER_WEAPONS + World.SP_ARCANE]), 1)
	assert_eq(int(pl[World.PLAYER_WEAPONS + World.SP_FIRE]), Spells.MAX_LEVEL + 1)
	assert_eq(int(pl[World.PLAYER_WEAPONS + World.SP_STAR]), 0)
	assert_eq(int(pl[World.PLAYER_WEAPONS + World.SP_RUNE]), 2)
	assert_eq(int(pl[World.PLAYER_WEAPONS + Spells.COUNT + 1]), p.max_hp, "max hearts come last")


## A world with one wizard and a rune circle inscribed at `at` (Rune Circle at `lv`, or the Seal when `evo`).
func _rune_world(at: Vector2, lv: int, evo: bool) -> World:
	var w := World.new([0], 3)
	var c := World.Rune.new()
	c.pos = at
	c.r = Spells.level_value(World.SP_RUNE, "r", lv, evo)
	c.life = Spells.level_value(World.SP_RUNE, "life", lv, evo)
	c.tick = Spells.RUNE_ARM
	c.dmg = Spells.damage(World.SP_RUNE, lv, evo)
	c.evo = evo
	c.pull = Spells.evo_value(World.SP_RUNE, "pull", 0.0) if evo else 0.0
	w.runes.append(c)
	return w


func _tick_runes(w: World, seconds: float) -> void:
	for _i: int in range(int(seconds / DT)):
		w._build_grid()
		w._update_runes(DT)
		w.runes = w.runes.filter(func(c: World.Rune) -> bool: return c.age < c.life)


func test_rune_circle_hurts_only_what_stands_in_it() -> void:
	var w := _rune_world(Vector2(200, 140), 1, false)
	var inside: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(205, 142))
	var outside: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(260, 140))
	inside.entering = false
	outside.entering = false
	_tick_runes(w, 1.0)
	assert_true(inside.hp < inside.maxhp, "the orc in the circle was not hurt")
	assert_eq(outside.hp, outside.maxhp, "the orc outside the circle was hurt")
	assert_true(inside.pos.distance_to(Vector2(205, 142)) < 0.01, "a plain rune circle moved the orc")


func test_rune_circle_ticks_then_expires() -> void:
	var w := _rune_world(Vector2(200, 140), 1, false)
	var orc: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(200, 140))
	orc.entering = false
	var life: float = w.runes[0].life
	_tick_runes(w, life + 0.2)
	assert_true(w.runes.is_empty(), "the circle outlived its life")
	var ticks: int = 1 + int((life - Spells.RUNE_ARM) / Spells.RUNE_TICK)
	assert_near(orc.maxhp - orc.hp, ticks * Spells.damage(World.SP_RUNE, 1, false), 0.01)
	var hp: float = orc.hp
	_tick_runes(w, 1.0)
	assert_eq(orc.hp, hp, "an expired circle still hurts")


func test_seal_of_solomon_pulls_enemies_in() -> void:
	var w := _rune_world(Vector2(200, 140), Spells.MAX_LEVEL, true)
	var r: float = w.runes[0].r
	var near: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(200 + r * 1.3, 140))
	var far: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(200 + r * Spells.SEAL_REACH + 20.0, 140))
	near.entering = false
	far.entering = false
	var d0: float = near.pos.distance_to(Vector2(200, 140))
	var far0: Vector2 = far.pos
	_tick_runes(w, 0.5)
	assert_true(near.pos.distance_to(Vector2(200, 140)) < d0 - 1.0, "the seal did not pull the orc in")
	assert_eq(far.pos, far0, "the seal pulled an orc out of its reach")
	var plain := _rune_world(Vector2(200, 140), Spells.MAX_LEVEL, false)
	var still: World.Enemy = plain.spawn_enemy(World.ORC, 0, Vector2(200 + r * 1.3, 140))
	still.entering = false
	_tick_runes(plain, 0.5)
	assert_eq(still.pos, Vector2(200 + r * 1.3, 140), "an unevolved circle pulled")


func test_rune_circle_goes_on_the_densest_cluster() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	var lone: World.Enemy = w.spawn_enemy(World.ORC, 0, p.pos + Vector2(-40, 0))
	lone.entering = false
	var pack := p.pos + Vector2(80, 30)
	for i: int in range(4):
		var e: World.Enemy = w.spawn_enemy(World.GOBLIN, 0, pack + Vector2(i * 4 - 6, (i % 2) * 4))
		e.entering = false
	w._build_grid()
	w.take_events()
	w._cast(p, World.SP_RUNE, 1, false, Vector2.RIGHT)
	assert_eq(w.runes.size(), 1)
	assert_true(w.runes[0].pos.distance_to(pack) < 8.0, "circle at %s, not on the pack at %s" % [w.runes[0].pos, pack])
	var inscribed: int = 0
	for ev: Array in w.take_events():
		if ev[0] == World.EV_RUNE:
			inscribed += 1
	assert_eq(inscribed, 1)


func test_rune_circles_of_one_cast_spread_out() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	for spot: Vector2 in [Vector2(-60, 0), Vector2(60, 0), Vector2(0, 60)]:
		for i: int in range(3):
			var e: World.Enemy = w.spawn_enemy(World.GOBLIN, 0, p.pos + spot + Vector2(i * 3, 0))
			e.entering = false
	w._build_grid()
	w._cast(p, World.SP_RUNE, Spells.MAX_LEVEL, false, Vector2.RIGHT)
	assert_eq(w.runes.size(), Spells.count(World.SP_RUNE, Spells.MAX_LEVEL, false))
	for a: int in range(w.runes.size()):
		for b: int in range(a + 1, w.runes.size()):
			assert_true(w.runes[a].pos.distance_to(w.runes[b].pos) > w.runes[a].r, "two circles of one cast overlap")


func test_rune_circle_with_nothing_in_range_goes_ahead() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	w._build_grid()
	w._cast(p, World.SP_RUNE, 3, false, Vector2.RIGHT)
	assert_eq(w.runes.size(), 1)
	assert_true(w.runes[0].pos.distance_to(p.pos + Vector2.RIGHT * Spells.RUNE_AIM_DIST) < 0.5)


func test_snapshot_sends_rune_circles() -> void:
	var w := _rune_world(Vector2(200, 140), Spells.MAX_LEVEL, true)
	var rn: PackedFloat32Array = w.snapshot()["r"]
	assert_eq(rn.size(), World.RUNE_FLOATS)
	assert_eq(Vector2(rn[0], rn[1]), Vector2(200, 140))
	assert_eq(rn[2], Spells.level_value(World.SP_RUNE, "r", Spells.MAX_LEVEL, true))
	assert_true(rn[6] > 0.5, "the seal is not marked evolved")


func test_rune_tome_grants_rune_circle() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	var tome := World.Pickup.new()
	tome.kind = World.PK_TOME_RUNE
	w._collect(p, tome)
	assert_eq(Upgrades.weapon_level(p.upgrades, World.SP_RUNE), 1)
	assert_eq(p.cds.size(), Spells.COUNT)


## A world past its intro whose wizards cannot be hurt, so only the horde changes.
func _fighting(tuning: Tuning = null, at_seconds: float = 0.0) -> World:
	var w := World.new([0], 3, tuning)
	w.phase = World.PH_FIGHT
	w.wave_time = at_seconds
	w.wave = int(at_seconds / 60.0) + 1
	_player(w).invuln = 99999.0
	return w


func _fielded(w: World) -> int:
	return w.enemies.size() + w.spawn_queue.size()


func test_horde_ramps_with_the_clock() -> void:
	var early := _fighting(null, 0.0)
	var late := _fighting(null, 360.0)
	early.horde_budget = 0.0
	late.horde_budget = 0.0
	for _i: int in range(600):
		early.step(DT, {})
		late.step(DT, {})
	assert_true(_fielded(late) > 2 * _fielded(early), "minute 7 fielded %d, minute 1 %d" % [_fielded(late), _fielded(early)])


func test_horde_never_clears_and_minutes_tick() -> void:
	var w := _fighting(null, 59.0)
	for _i: int in range(120):
		w.step(DT, {})
	assert_eq(w.wave, 2)
	assert_eq(w.phase, World.PH_FIGHT)


func test_lich_comes_on_its_minute() -> void:
	var w := _fighting(null, 4 * 60.0 + 59.5)
	var announced := false
	for _i: int in range(60 * 4):
		w.step(DT, {})
		for ev: Array in w.take_events():
			if ev[0] == World.EV_WAVE and int(ev[4]) == 1:
				announced = true
	assert_true(announced, "minute 5 was not announced as a boss minute")
	assert_true(w.boss != null and w.boss.type == World.LICH, "no Lich after minute 5 began")


func test_enemy_cap_holds_the_horde() -> void:
	var t := Tuning.new()
	t.set_value("horde_rate_base", 40.0)
	t.set_value("enemy_cap", 30.0)
	var w := _fighting(t, 0.0)
	# Unarmed and unable to pick anything up, so only the horde changes the count (not a lucky tome).
	_player(w).upgrades.clear()
	w.powerup_timer = INF
	for _i: int in range(60 * 10):
		w.step(DT, {})
		w.pickups.clear()
		assert_true(_fielded(w) <= 30 + 12, "fielded %d over a cap of 30" % _fielded(w))
	assert_true(_fielded(w) >= 30, "the horde should reach the cap")


func test_elites_are_tough_and_pay_out() -> void:
	var t := Tuning.new()
	t.set_value("elite_interval", 5.0)
	var w := _fighting(t, 0.0)
	var elite: World.Enemy = null
	for _i: int in range(60 * 6):
		w.step(DT, {})
		for e: World.Enemy in w.enemies:
			if e.elite:
				elite = e
		if elite:
			break
	assert_true(elite != null, "no elite after 6 s with a 5 s interval")
	var plain: World.Enemy = w.spawn_enemy(elite.type, 0, Vector2(100, 100))
	assert_near(elite.maxhp, plain.maxhp * t.elite_hp_mul, 0.001)
	_player(w).combo = 0
	var score: int = _player(w).score
	var drops: int = w.pickups.size()
	w._kill_enemy(elite, 0)
	assert_eq(_player(w).score - score, int(World.STATS[elite.type][3]) * World.ELITE_REWARD)
	var chests: int = 0
	for k: World.Pickup in w.pickups.slice(drops):
		if k.kind == World.PK_CHEST:
			chests += 1
			assert_eq(k.value, int(t.elite_chest_luck), "elite chest luck")
	assert_eq(chests, 1, "an elite drops one chest")
	assert_true(w.pickups.size() - drops >= World.ELITE_GEMS + 1)


func test_snapshot_enemy_block_size() -> void:
	var w := _fighting(null, 0.0)
	w.spawn_enemy(World.GOBLIN, 0, Vector2(100, 100)).elite = true
	w.spawn_enemy(World.BAT, 1, Vector2(140, 100))
	var en: PackedFloat32Array = w.snapshot()["e"]
	assert_eq(en.size(), World.ENEMY_FLOATS * 2)
	assert_eq(en[World.ENEMY_FLOATS - 1], 1.0, "elite flag")
	assert_eq(en[2 * World.ENEMY_FLOATS - 1], 0.0)


func test_xp_gems_merge_past_the_cap() -> void:
	var t := Tuning.new()
	t.set_value("xp_gem_cap", 10.0)
	var w := World.new([0], 3, t)
	for i: int in range(25):
		w._drop_xp(Vector2(100 + i * 10, 100), Vector2.ZERO, 2)
	var gems: int = 0
	var total: int = 0
	for k: World.Pickup in w.pickups:
		if k.kind == World.PK_XP:
			gems += 1
			total += k.value
	assert_eq(gems, 10)
	assert_eq(total, 50, "merged gems must keep every point of XP")


func test_rift_opens_away_from_wizards_then_spawns() -> void:
	var w := _fighting(null, 0.0)
	var p := _player(w)
	w._queue_rift(World.GOBLIN, 5)
	var rift: Array = []
	for ev: Array in w.take_events():
		if ev[0] == World.EV_RIFT:
			rift = ev
	assert_false(rift.is_empty(), "no rift marker")
	var at := Vector2(rift[1], rift[2])
	assert_true(at.distance_to(p.pos) >= w.tune.rift_min_dist, "rift %s too close to the wizard" % at)
	var before: int = w.enemies.size()
	w.wave_time += w.tune.rift_warning * 0.5
	w._process_spawns()
	assert_eq(w.enemies.size(), before, "spawned before the warning ran out")
	w.wave_time += w.tune.rift_warning
	w._process_spawns()
	assert_eq(w.enemies.size(), before + 5)
	for e: World.Enemy in w.enemies.slice(before):
		assert_false(e.entering)
		assert_true(e.pos.distance_to(at) < 30.0)



func _chest(w: World, luck: int = 0) -> World.Pickup:
	var k := World.Pickup.new()
	k.kind = World.PK_CHEST
	k.value = luck
	k.pos = Vector2(100, 100)
	return k


func test_chest_gives_an_item_and_announces_it() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	w.take_events()
	w._collect(p, _chest(w))
	var seen: Array = []
	for ev: Array in w.take_events():
		if ev[0] == World.EV_CHEST:
			seen = ev
	assert_false(seen.is_empty(), "no chest event")
	var item: int = int(seen[4]) / 8
	var tier: int = int(seen[4]) % 8
	assert_true(item >= 0 and item < Loot.count() and tier >= Loot.COMMON and tier <= Loot.ULTRA)


func test_armor_items_change_the_wizard() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	Loot.add_armor(p.armor, 3, Loot.EPIC) # troll hide: +2 hearts at epic
	assert_near(p.armor[Loot.ST_VIGOR], 2.0)
	# Might raises damage like Spell Power does.
	var a: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(100, 100))
	w._damage_enemy(a, 1.0, 0, Vector2.ZERO)
	var plain: float = a.maxhp - a.hp
	Loot.add_armor(p.armor, 0, Loot.COMMON)
	var b: World.Enemy = w.spawn_enemy(World.ORC, 0, Vector2(140, 100))
	w._damage_enemy(b, 1.0, 0, Vector2.ZERO)
	assert_near(b.maxhp - b.hp, plain * 1.08, 0.0001)


func test_ward_can_block_a_hit() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	p.armor[Loot.ST_WARD] = 1.0
	p.invuln = 0.0
	var hp: int = p.hp
	w.hurt_player(p, 1)
	assert_eq(p.hp, hp, "a full ward blocks every hit")


func test_coins_give_run_gold_with_greed() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	var coin := World.Pickup.new()
	coin.kind = World.PK_COIN
	w._collect(p, coin)
	assert_near(p.gold, 1.0)
	p.armor[Loot.ST_GREED] = 1.0
	var gem := World.Pickup.new()
	gem.kind = World.PK_GEM
	w._collect(p, gem)
	assert_near(p.gold, 11.0)


func test_lich_drops_a_lucky_chest_per_wizard() -> void:
	var w := World.new([0, 1, 2], 3)
	var lich: World.Enemy = w.spawn_enemy(World.LICH, 0, Vector2(240, 120))
	w._kill_enemy(lich, 0)
	var chests: int = 0
	for k: World.Pickup in w.pickups:
		if k.kind == World.PK_CHEST:
			chests += 1
			assert_eq(k.value, int(w.tune.boss_chest_luck))
	assert_eq(chests, 3)


func _shrine_world(slots: Array = [0]) -> World:
	var w := World.new(slots, 3)
	w.phase = World.PH_FIGHT
	w.shrine_t = 99999.0
	w.team_shrine_t = 99999.0
	w.horde_budget = -99999.0 # keep the arena empty
	for s: int in slots:
		_player(w, s).invuln = 99999.0
	return w


func _stand_on(w: World, sh: World.Shrine, seconds: float) -> void:
	for p: World.Player in w.players.values():
		p.pos = sh.pos
	for _i: int in range(int(seconds * 60.0)):
		for p: World.Player in w.players.values():
			p.pos = sh.pos
		w.step(DT, {})


func test_shrines_appear_on_their_timer() -> void:
	var w := _shrine_world()
	w.shrine_t = 0.5
	for _i: int in range(60):
		w.step(DT, {})
	assert_eq(w.shrines.size(), 1)
	assert_eq(w.shrines[0].kind, Gamble.SOLO)
	assert_eq(w.shrines[0].cost, Gamble.cost(Gamble.SOLO, 1, w.tune.shrine_cost_base, w.tune.shrine_cost_per_min, w.tune.team_cost_mul))


func test_a_wizard_without_gold_cannot_bet() -> void:
	var w := _shrine_world()
	w._place_shrine(Gamble.SOLO)
	var sh: World.Shrine = w.shrines[0]
	_stand_on(w, sh, 2.0)
	assert_eq(w.shrines.size(), 1, "the shrine took a bet nobody could pay")


func test_solo_bet_takes_gold_then_pays_after_the_reel() -> void:
	var w := _shrine_world()
	var p := _player(w)
	w._place_shrine(Gamble.SOLO)
	var sh: World.Shrine = w.shrines[0]
	p.gold = 100.0
	w.take_events()
	_stand_on(w, sh, w.tune.shrine_hold + 0.1)
	assert_true(w.shrines.is_empty(), "the shrine should be used")
	assert_near(p.gold, 100.0 - sh.cost)
	var done := false
	for _i: int in range(int(w.tune.shrine_reel * 60.0) + 10):
		w.step(DT, {})
		for ev: Array in w.take_events():
			if ev[0] == World.EV_GAMBLE:
				done = true
	assert_true(done, "the outcome never landed")


func test_team_blessing_levels_everyone() -> void:
	var w := _shrine_world([0, 1, 2])
	var levels: Array[int] = []
	for s: int in [0, 1, 2]:
		levels.append(_player(w, s).level)
	w._resolve_gamble({"slot": 0, "kind": Gamble.TEAM, "outcome": Gamble.TO_BLESSING, "stake": 40, "pos": Vector2(200, 120)})
	for s: int in [0, 1, 2]:
		assert_eq(_player(w, s).level, levels[s] + Gamble.BLESSING_LEVELS)


func test_team_curse_hurts_but_never_kills() -> void:
	var w := _shrine_world([0, 1])
	_player(w, 0).hp = 1
	var elites: int = 0
	w._resolve_gamble({"slot": 1, "kind": Gamble.TEAM, "outcome": Gamble.TO_CURSE, "stake": 40, "pos": Vector2(200, 120)})
	assert_eq(_player(w, 0).hp, 1)
	assert_eq(_player(w, 1).hp, _player(w, 1).max_hp - 1)
	for e: World.Enemy in w.enemies:
		if e.elite:
			elites += 1
	assert_eq(elites, 2, "the curse sends an elite per wizard")


func _final_world(slots: Array = [0]) -> World:
	var w := World.new(slots, 3)
	w.phase = World.PH_FIGHT
	w.wave_time = w.tune.run_minutes * 60.0 - 0.5
	w.wave = w.final_minute() - 1
	for p: World.Player in w.players.values():
		p.invuln = 99999.0
	return w


func test_archlich_comes_when_the_run_time_is_up() -> void:
	var w := _final_world()
	var announced := false
	for _i: int in range(60 * 4):
		w.step(DT, {})
		for ev: Array in w.take_events():
			if ev[0] == World.EV_WAVE and int(ev[4]) == 2:
				announced = true
	assert_true(announced, "the final minute was not announced")
	assert_true(w.boss != null and w.boss.final, "no Archlich after the run time")
	var lich_hp: float = World.STATS[World.LICH][0] * w._lich_hp_scale()
	assert_true(w.boss.maxhp > 2.0 * lich_hp, "Archlich hp %.0f vs Lich %.0f" % [w.boss.maxhp, lich_hp])


func test_a_lich_still_standing_ascends() -> void:
	var w := _final_world()
	var lich: World.Enemy = w.spawn_enemy(World.LICH, 0, Vector2(240, 120))
	lich.hp = 10.0
	for _i: int in range(60):
		w.step(DT, {})
	assert_true(w.boss == lich and lich.final, "the standing Lich did not become the Archlich")
	assert_true(lich.hp > 0.9 * lich.maxhp, "the Archlich was not healed: %.0f of %.0f" % [lich.hp, lich.maxhp])
	var liches: int = 0
	for e: World.Enemy in w.enemies:
		if e.type == World.LICH:
			liches += 1
	assert_eq(liches, 1)
	for s: Dictionary in w.spawn_queue:
		assert_true(s.type != World.LICH, "a second boss was queued")


func test_no_lich_visits_after_the_final_minute() -> void:
	var t := Tuning.new()
	t.run_minutes = 3.0 # the Archlich comes at 3:00
	t.boss_every_min = 1.0 # so 4:00 would otherwise bring a Lich
	t.enemy_cap = 20.0 # the horde is not under test: a small one makes 70 s of simulation take 1 s, not 20
	var w := World.new([0], 3, t)
	w.phase = World.PH_FIGHT
	w.wave = 3
	w.wave_time = 3 * 60.0 - 0.5
	_player(w).invuln = 99999.0
	var lich_minutes: int = 0
	for _i: int in range(60 * 70):
		_player(w).choices.clear() # skip level-up picks so the clock keeps running
		_player(w).pending = 0
		w.step(DT, {})
		for ev: Array in w.take_events():
			if ev[0] == World.EV_WAVE and int(ev[4]) == 1:
				lich_minutes += 1
	assert_true(w.wave >= 5, "the clock did not reach 4:00")
	# While the Archlich stands no other Lich can come anyway, so the announcement is what shows the rule held.
	assert_eq(lich_minutes, 0, "4:00 was announced as a Lich minute after the Archlich's minute")
	var liches: int = 0
	for e: World.Enemy in w.enemies:
		if e.type == World.LICH:
			liches += 1
			assert_true(e.final, "a plain Lich came after the Archlich's minute")
	assert_eq(liches, 1)


func test_slaying_the_archlich_wins_the_run() -> void:
	var w := _final_world([0, 1])
	var arch: World.Enemy = w.spawn_enemy(World.LICH, 0, Vector2(240, 120))
	w._make_final(arch)
	w.take_events()
	w._kill_enemy(arch, 1)
	var won_by: int = -1
	for ev: Array in w.take_events():
		if ev[0] == World.EV_VICTORY:
			won_by = int(ev[3])
	assert_eq(won_by, 1)
	assert_true(w.won)
	assert_eq(w.liches_slain, 1)
	var over: bool = false
	var clock: float = w.wave_time
	for _i: int in range(int((w.tune.victory_delay + 0.5) * 60.0)):
		w.step(DT, {})
		for ev: Array in w.take_events():
			if ev[0] == World.EV_GAMEOVER:
				over = true
	assert_true(over, "no results screen after the victory delay")
	assert_eq(w.phase, World.PH_GAMEOVER)
	assert_eq(w.wave_time, clock)
	assert_eq(w.enemies.size(), 0)


func test_snapshot_marks_the_archlich() -> void:
	var w := _final_world()
	var arch: World.Enemy = w.spawn_enemy(World.LICH, 0, Vector2(240, 120))
	w._make_final(arch)
	var snap: Dictionary = w.snapshot()
	var en: PackedFloat32Array = snap.e
	assert_eq(en[8], 2.0)
	var wv: PackedFloat32Array = snap.w
	assert_eq(wv[9], 1.0)


func test_the_record_notes_kills_damage_and_the_lich() -> void:
	var w := World.new([0, 1], 3)
	var lich: World.Enemy = w.spawn_enemy(World.LICH, 0, Vector2(240, 120))
	w._damage_enemy(lich, 50.0, 1, Vector2.ZERO)
	w._kill_enemy(lich, 1)
	assert_true(w.record.stat(1, "damage") >= 50.0)
	assert_eq(w.record.stat(0, "damage"), 0.0)
	assert_eq(w.record.moments.size(), 1)
	assert_eq(int(w.record.moments[0][1]), Results.M_LICH)
	assert_eq(int(w.record.moments[0][2]), 1)


func test_the_record_notes_chests_and_bets() -> void:
	var w := _shrine_world([0])
	var p := _player(w)
	w._open_chest(p, _chest(w, 5))
	assert_eq(w.record.stat(0, "chests"), 1.0)
	assert_true(w.record.stat(0, "best_tier") >= float(Loot.RARE), "luck 5 never rolls common")
	p.gold = 500.0
	w._place_shrine(Gamble.SOLO)
	var sh: World.Shrine = w.shrines[0]
	_stand_on(w, sh, w.tune.shrine_hold + 0.2)
	assert_eq(w.record.stat(0, "bets"), float(sh.cost))


func test_game_over_sends_the_record_first() -> void:
	var w := _fighting()
	_player(w).lives = 0
	_player(w).invuln = 0.0
	w.hurt_player(_player(w), 99)
	var codes: Array = []
	for _i: int in range(3):
		w.step(DT, {})
		for ev: Array in w.take_events():
			if ev[0] == World.EV_RESULTS or ev[0] == World.EV_GAMEOVER:
				codes.append(ev[0])
				if ev[0] == World.EV_RESULTS:
					var back := Results.from_dict(ev[3])
					assert_eq(back.stat(0, "deaths"), 1.0)
					assert_eq(back.stat(0, "level"), 1.0)
	assert_eq(codes, [World.EV_RESULTS, World.EV_GAMEOVER])


func test_enemy_tables_cover_every_type() -> void:
	assert_eq(World.XP_VALUES.size(), World.STATS.size(), "an XP value per enemy type")
	for row: Array in World.HORDE:
		assert_true(int(row[0]) < World.STATS.size(), "horde row for an unknown type")


func test_a_faded_wraith_cannot_be_hurt() -> void:
	var w := _fighting(null, 0.0)
	var e: World.Enemy = w.spawn_enemy(World.WRAITH, 0, Vector2(100, 100))
	var hp: float = e.hp
	e.state = 1
	w._damage_enemy(e, 1.0, 0, Vector2.ZERO)
	assert_eq(e.hp, hp, "a faded wraith took damage")
	e.state = 0
	w._damage_enemy(e, 1.0, 0, Vector2.ZERO)
	assert_true(e.hp < hp, "a solid wraith should take damage")


func test_a_wraith_fades_on_its_cycle() -> void:
	var w := _fighting(null, 0.0)
	var e: World.Enemy = w.spawn_enemy(World.WRAITH, 0, Vector2(100, 100))
	e.hp = 99999.0 # out of reach of the wizard's spells
	var faded := false
	var solid := false
	for _i: int in range(int(60 * (World.WRAITH_SOLID + World.WRAITH_FADED) * 1.2)):
		w.step(DT, {})
		faded = faded or e.state == 1
		solid = solid or e.state == 0
	assert_true(faded and solid, "a wraith should be both solid and faded in one cycle")


func test_stone_gargoyle_shrugs_off_damage() -> void:
	var w := _fighting(null, 0.0)
	var stone: World.Enemy = w.spawn_enemy(World.GARGOYLE, 0, Vector2(100, 100))
	var flying: World.Enemy = w.spawn_enemy(World.GARGOYLE, 0, Vector2(300, 100))
	stone.state = 0
	flying.state = 1
	var hp: float = stone.hp
	w._damage_enemy(stone, 2.0, 0, Vector2.ZERO)
	w._damage_enemy(flying, 2.0, 0, Vector2.ZERO)
	assert_near(hp - stone.hp, (hp - flying.hp) * World.STONE_DAMAGE, 0.001)


func test_bone_priest_raises_skeletons() -> void:
	var w := _fighting(null, 0.0)
	var priest: World.Enemy = w.spawn_enemy(World.PRIEST, 0, Vector2(120, 120))
	priest.hp = 99999.0
	var raised := 0
	for _i: int in range(int(60 * (World.PRIEST_RAISE + 0.5))):
		w.step(DT, {})
		for ev: Array in w.take_events():
			if int(ev[0]) == World.EV_RAISE:
				raised += int(ev[3])
	assert_true(not priest.dead, "the priest should still stand")
	assert_eq(raised, World.PRIEST_RAISED, "one raising in one cycle")


func test_an_omen_rings_the_party_on_its_minute() -> void:
	var w := _fighting(null, 0.0)
	var omen: Array = World.OMENS[0]
	w.wave = int(omen[0]) - 1
	w.wave_time = (int(omen[0]) - 1) * 60.0 + 0.01
	w.spawn_queue.clear()
	w.take_events()
	w._tick_minute()
	var announced := false
	for ev: Array in w.take_events():
		announced = announced or int(ev[0]) == World.EV_OMEN
	assert_true(announced, "the omen is announced")
	var ringed := 0
	var c: Vector2 = _player(w).pos
	for q: Dictionary in w.spawn_queue:
		if int(q.type) == int(omen[1]) and q.has("at"):
			ringed += 1
			assert_true((q.at as Vector2).distance_to(c) <= World.OMEN_RING_R + 0.5, "ring spawns stay on the ring")
	assert_eq(ringed, int(omen[2]))


func test_omens_have_lore_and_skip_lich_minutes() -> void:
	assert_eq(Lore.OMENS.size(), World.OMENS.size())
	var w := _fighting(null, 0.0)
	for o: Array in World.OMENS:
		var wave: int = o[0]
		assert_true(w._lich_visits(wave) == w._lich_visits(wave - 1), "an omen shares a minute with the Lich")


func test_a_kill_can_drop_its_card_and_picking_it_up_announces_it() -> void:
	var w := World.new([0], 3)
	w.tune.card_chance = 1.0
	var p := _player(w)
	var e: World.Enemy = w.spawn_enemy(World.BAT, 0, Vector2(150, 120))
	w._kill_enemy(e, 0)
	var card: World.Pickup = null
	for k: World.Pickup in w.pickups:
		if k.kind == World.PK_CARD:
			card = k
	assert_true(card != null, "no card dropped at chance 1")
	assert_eq(card.value, World.BAT)
	w.take_events()
	w._collect(p, card)
	var seen := false
	for ev: Array in w.take_events():
		if ev[0] == World.EV_CARD:
			seen = int(ev[3]) == World.BAT and int(ev[4]) == 0
	assert_true(seen, "no card event")
	assert_eq(w.cards_found, [World.BAT] as Array[int])


func test_rare_and_ultra_chests_open_at_their_floor() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	for kind: int in [World.PK_CHEST_RARE, World.PK_CHEST_ULTRA]:
		for _i: int in range(20):
			var k := _chest(w, 0)
			k.kind = kind
			w.take_events()
			w._collect(p, k)
			for ev: Array in w.take_events():
				if ev[0] == World.EV_CHEST:
					var floor_tier: int = Loot.RARE if kind == World.PK_CHEST_RARE else Loot.LEGENDARY
					assert_true(int(ev[4]) % 8 >= floor_tier, "a chest opened below its floor")


func test_any_kill_can_drop_a_rare_chest() -> void:
	var w := World.new([0], 3)
	w.tune.rare_drop_chance = 1.0
	var e: World.Enemy = w.spawn_enemy(World.GOBLIN, 0, Vector2(150, 120))
	w._kill_enemy(e, 0)
	var kinds: Array = w.pickups.map(func(k: World.Pickup) -> int: return k.kind)
	assert_true(kinds.has(World.PK_CHEST_RARE), "no rare chest at chance 1")


func test_socketed_cards_reach_every_wizard() -> void:
	var w := World.new([0, 1], 3)
	var hp0: int = _player(w).max_hp
	var armor := Loot.empty_stats()
	armor[Loot.ST_MIGHT] = 0.1
	armor[Loot.ST_VIGOR] = 2.0
	w.apply_meta({"armor": armor})
	for p: World.Player in w.players.values():
		assert_near(float(p.armor[Loot.ST_MIGHT]), 0.1)
		assert_eq(p.max_hp, hp0 + 2)


func test_urns_stand_along_the_walls_each_minute() -> void:
	var w := World.new([0], 3)
	w._refill_urns()
	assert_eq(w.urns.size(), int(w.tune.urn_count))
	w.urns.clear()
	w.wave_time = 60.0 * w.wave + 1.0
	w._tick_minute()
	assert_eq(w.urns.size(), int(w.tune.urn_count), "a new minute did not refill the urns")
	var inner := G.ARENA.grow(-24.0)
	for u: Vector2 in w.urns:
		assert_true(G.ARENA.has_point(u), "urn outside the arena")
		assert_false(inner.has_point(u), "urn in the middle of the floor at %s" % u)


func test_walking_into_an_urn_breaks_it_and_announces_it() -> void:
	var w := World.new([0], 3)
	w.urns = [Vector2(100, 100)] as Array[Vector2]
	var p := _player(w)
	p.pos = Vector2(102, 100)
	w.take_events()
	w._update_urns()
	assert_true(w.urns.is_empty(), "the urn did not break")
	var seen := false
	for ev: Array in w.take_events():
		seen = seen or ev[0] == World.EV_URN
	assert_true(seen, "no urn event")


func test_an_urn_card_is_marked_as_from_an_urn() -> void:
	var w := World.new([0], 3)
	w.tune.urn_card_chance = 1.0
	w._break_urn(Vector2(120, 120))
	var card: World.Pickup = null
	for k: World.Pickup in w.pickups:
		if k.kind == World.PK_CARD:
			card = k
	assert_true(card != null, "no card from the urn at chance 1")
	w.take_events()
	w._collect(_player(w), card)
	for ev: Array in w.take_events():
		if ev[0] == World.EV_CARD:
			assert_true(int(ev[3]) < Cards.count(), "card index carries the urn mark")
			assert_true(int(ev[4]) >= 8, "the event does not say it came from an urn")


func test_wizards_stay_on_one_screen() -> void:
	var w := World.new([0, 1], 3)
	var a := _player(w, 0)
	var b := _player(w, 1)
	b.pos = Vector2(G.ARENA.position.x + 10, 200)
	a.pos = b.pos
	for _i: int in range(600):
		w._update_player(a, 1.0 / 60.0, PackedFloat32Array([1, 0, 0, 0, 0, 0]))
	assert_true(a.pos.x - b.pos.x <= w.tune.leash_x + 0.01, "a wizard walked off the shared screen")
	assert_true(a.pos.x - b.pos.x > w.tune.leash_x - 5.0, "the leash held too short")


func test_rifts_open_near_the_party_not_across_the_arena() -> void:
	var w := World.new([0], 3)
	var p := _player(w)
	p.pos = G.ARENA.position + Vector2(60, 60)
	for _i: int in range(20):
		var at := w._spot_near_party(w.tune.rift_min_dist, w.tune.rift_max_dist, 22.0)
		var d := at.distance_to(p.pos)
		assert_true(d >= w.tune.rift_min_dist - 0.5 and d <= w.tune.rift_max_dist + 1.0, "rift %d px away" % d)
