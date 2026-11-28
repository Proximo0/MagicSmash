extends TestCase
## World fallen wizards: going down, the spirit, the ritual, getting up, the wipe and the call
## (game/logic/world/players.gd, World.graves / can_return / the wipe in step).

const DT: float = 1.0 / 60.0


## A party held in the intro (no horde comes), every wizard open to a hit.
func _party(n: int = 2) -> World:
	var w := World.new(range(n), 3, Tuning.new()) # its own Tuning: other tests change the shared one
	w.phase_t = 1e6
	for p: World.Player in w.players.values():
		p.invuln = 0.0
	return w


## Steps `seconds` with the same inputs every tick; returns the events.
func _run(w: World, seconds: float, inputs: Dictionary = {}) -> Array:
	var out: Array = []
	for _i: int in range(roundi(seconds / DT)):
		w.step(DT, inputs)
		out.append_array(w.take_events())
	return out


func _codes(evs: Array, code: int) -> Array:
	return evs.filter(func(e: Array) -> bool: return int(e[0]) == code)


func _nova(count: int, move: Vector2 = Vector2.ZERO) -> PackedFloat32Array:
	return PackedFloat32Array([move.x, move.y, 0, 0, 0, count])


func _fell(w: World, slot: int) -> World.Player:
	var p: World.Player = w.players[slot]
	p.invuln = 0.0
	w.hurt_player(p, 99)
	return p


func test_nobody_is_down_by_default() -> void:
	var w := World.new([0, 1], 3)
	for p: World.Player in w.players.values():
		assert_false(p.down)
		assert_near(p.down_left, 0.0)
		assert_near(p.down_t, 0.0)
		assert_near(p.revive, 0.0)
		assert_eq(p.rituals, 0)
		assert_near(p.call_t, 0.0)
		assert_true(w.can_return(p), "a wizard with lives left can come back")
	assert_true(w.graves().is_empty())
	assert_near(w.tune.down_spawn_weight, 1.0)
	var pl: PackedFloat32Array = w.snapshot()["p"]
	assert_eq(pl[World.P_DOWN], 0.0)
	assert_eq(pl[World.P_REVIVE], 0.0)
	# A downed wizard shows up as a grave.
	var p: World.Player = w.players[1]
	p.down = true
	p.down_left = 4.0
	assert_eq(w.graves(), [[1, p.pos.x, p.pos.y, 0.0, 4.0]])


func test_the_fallen_rows_hold_the_brief_numbers() -> void:
	var t := Tuning.new()
	assert_eq([t.spirit_speed, t.ritual_radius, t.ritual_hold_radius, t.ritual_time, t.ritual_step, t.ritual_drain,
		t.ritual_push, t.ritual_safe, t.down_time, t.last_stand, t.call_gap, t.return_safe],
		[45.0, 30.0, 60.0, 2.0, 0.5, 8.0, 80.0, 2.0, 10.0, 1.5, 2.0, 2.5])


func test_a_party_wizard_falls_with_her_lives() -> void:
	var w := _party()
	var p := _fell(w, 1)
	var evs := w.take_events()
	assert_true(p.down and not p.alive, "she falls as a spirit")
	assert_eq(p.lives, 3, "a fall costs no life")
	assert_near(p.down_left, w.tune.down_time)
	assert_eq(_codes(evs, World.EV_DOWN).size(), 1)
	assert_eq(int(_codes(evs, World.EV_DOWN)[0][3]), 1)
	assert_eq(w.record.downs(1), 1)
	assert_near(w.record.stat(1, "deaths"), 0.0)
	var pl: PackedFloat32Array = w.snapshot()["p"]
	assert_eq(pl[World.P_FLOATS + World.P_DOWN], 1.0)
	assert_near(pl[World.P_FLOATS + World.P_DOWN_LEFT], w.tune.down_time)
	assert_true(w.can_return(p))
	p.lives = 1
	assert_false(w.can_return(p), "on her last life only a ritual brings her back")


func test_solo_still_dies_and_respawns() -> void:
	var w := World.new([0], 3, Tuning.new())
	w.phase_t = 1e6
	var p := _fell(w, 0)
	var evs := w.take_events()
	assert_false(p.alive)
	assert_false(p.down, "a solo wizard never becomes a spirit")
	assert_eq(p.lives, 2)
	assert_near(w.record.stat(0, "deaths"), 1.0)
	assert_eq(w.record.downs(0), 0)
	assert_true(_codes(evs, World.EV_DOWN).is_empty())
	assert_eq(_codes(evs, World.EV_PDIE).size(), 1)
	_run(w, 2.6)
	assert_true(p.alive)
	assert_eq(p.hp, p.max_hp)


func test_the_spirit_walks_slow_unhurt_and_does_not_cast() -> void:
	var w := _party()
	var p := _fell(w, 1)
	var from := p.pos
	_run(w, 1.0, {1: _nova(0, Vector2.RIGHT)})
	assert_near(p.pos.x - from.x, w.tune.spirit_speed, 1.0, "45 px/s")
	w.hurt_player(p, 1)
	assert_true(_codes(w.take_events(), World.EV_HURT).is_empty(), "a spirit cannot be hurt")
	w.spawn_enemy(World.GOBLIN, 0, p.pos + Vector2(30, 0))
	_run(w, 1.0)
	for s: World.Shot in w.shots:
		assert_true(s.owner != 1, "the spirit cast nothing")


func test_the_spirit_is_leashed_to_the_standing() -> void:
	var w := _party()
	var p := _fell(w, 1)
	var q: World.Player = w.players[0]
	q.pos = Vector2(G.ARENA.position.x + 20, q.pos.y)
	p.pos = Vector2(G.ARENA.end.x - 20, q.pos.y)
	_run(w, DT)
	assert_true(p.pos.x <= q.pos.x + w.tune.leash_x + 0.01, "leashed")


func test_the_spirit_gathers_xp() -> void:
	var w := _party()
	var p := _fell(w, 1)
	w.players[0].pos = p.pos + Vector2(150, 0)
	var xp := w.party_xp
	w._drop_xp(p.pos + Vector2(2, 0), Vector2.ZERO, 3)
	_run(w, 0.1)
	assert_true(w.party_xp > xp, "her touch takes the mote")


func test_one_ally_raises_in_two_seconds_with_half_hearts_and_novas() -> void:
	var w := _party()
	var p := _fell(w, 1)
	var q: World.Player = w.players[0]
	p.bombs = 1
	q.pos = p.pos
	_run(w, w.tune.ritual_time - 0.05)
	assert_true(p.down, "not yet")
	var evs := _run(w, 0.1)
	assert_true(p.alive and not p.down, "risen")
	assert_eq(p.hp, ceili(p.max_hp / 2.0))
	assert_eq(p.bombs, 1, "novas kept")
	assert_eq(p.lives, 3)
	assert_true(p.invuln > w.tune.ritual_safe - 0.2 and q.invuln > w.tune.ritual_safe - 0.2, "both safe")
	var rv := _codes(evs, World.EV_REVIVE)
	assert_eq(rv.size(), 1)
	assert_eq([int(rv[0][3]), int(rv[0][4])], [1, 0])
	assert_eq(w.record.revives(0), 1)
	assert_eq(p.rituals, 1)


func test_two_allies_raise_in_one_second() -> void:
	var w := _party(3)
	var p := _fell(w, 2)
	w.players[0].pos = p.pos + Vector2(5, 0)
	w.players[1].pos = p.pos - Vector2(5, 0)
	_run(w, w.tune.ritual_time / 2.0 - 0.05)
	assert_true(p.down)
	_run(w, 0.1)
	assert_true(p.alive)


func test_progress_holds_near_and_drains_far() -> void:
	var w := _party()
	var p := _fell(w, 1)
	var q: World.Player = w.players[0]
	q.pos = p.pos
	_run(w, 1.0)
	assert_near(p.revive, 0.5, 0.02)
	q.pos = p.pos + Vector2(w.tune.ritual_hold_radius - 10.0, 0)
	_run(w, 2.0)
	assert_near(p.revive, 0.5, 0.02, "holds with an ally near")
	q.pos = p.pos + Vector2(w.tune.ritual_hold_radius + 40.0, 0)
	_run(w, 2.0)
	assert_near(p.revive, 0.5 - 2.0 / w.tune.ritual_drain, 0.02, "drains over 8 s")


func test_the_ritual_pushes_enemies_away_at_both_ends() -> void:
	var w := _party()
	var p := _fell(w, 1)
	var q: World.Player = w.players[0]
	var e := w.spawn_enemy(World.ORC, 0, p.pos + Vector2(20, 0))
	e.spd = 0.0
	e.hp = 1e6 # it must outlive the ritual, whatever the starting spell deals
	q.pos = p.pos
	_run(w, DT)
	assert_near(e.pos.distance_to(p.pos), w.tune.ritual_push, 2.0, "pushed when the first ally enters")
	_run(w, 1.0)
	e.pos = p.pos + Vector2(0, 15)
	_run(w, 1.1)
	assert_true(p.alive)
	assert_near(e.pos.distance_to(p.pos), w.tune.ritual_push, 2.0, "and again when she rises")


func test_each_later_ritual_takes_longer() -> void:
	var w := _party()
	var p := _fell(w, 1)
	p.rituals = 2
	w.players[0].pos = p.pos
	_run(w, w.tune.ritual_time + w.tune.ritual_step * 2.0 - 0.05)
	assert_true(p.down)
	_run(w, 0.1)
	assert_true(p.alive)


func test_down_ten_seconds_costs_a_life_and_returns_by_the_party() -> void:
	var w := _party()
	var p := _fell(w, 1)
	var q: World.Player = w.players[0]
	q.pos = p.pos + Vector2(120, 0)
	_run(w, w.tune.down_time - 0.1)
	assert_true(p.down)
	var evs := _run(w, 0.2)
	assert_true(p.alive)
	assert_eq(p.lives, 2)
	assert_near(w.record.stat(1, "deaths"), 1.0, 0.0001, "deaths counts lives lost")
	assert_true(p.pos.distance_to(q.pos) < 30.0, "back beside the party")
	assert_eq(int(_codes(evs, World.EV_REVIVE)[0][4]), -1)


func test_the_clock_stops_while_an_ally_is_inside() -> void:
	var w := _party()
	var p := _fell(w, 1)
	p.rituals = 40 # a long ritual, so it does not finish
	w.players[0].pos = p.pos
	_run(w, 3.0)
	assert_near(p.down_left, w.tune.down_time, 0.001)


func test_on_the_last_life_she_waits_for_a_ritual() -> void:
	var w := _party()
	w.players[1].lives = 1
	var p := _fell(w, 1)
	w.players[0].pos = p.pos + Vector2(120, 0)
	assert_near(p.down_left, -1.0)
	_run(w, w.tune.down_time + 3.0)
	assert_true(p.down, "still waiting")
	assert_eq(p.lives, 1)


func test_nobody_standing_the_longest_down_returns() -> void:
	var w := _party()
	var a := _fell(w, 0)
	_run(w, 3.0)
	var b := _fell(w, 1)
	_run(w, w.tune.last_stand - 0.1)
	assert_true(a.down and b.down)
	_run(w, 0.2)
	assert_true(a.alive, "the longest down gets up")
	assert_true(b.down)
	assert_eq(a.lives, 2)
	assert_true(w.phase != World.PH_GAMEOVER)


func test_nobody_standing_only_a_wizard_with_a_life_to_spare_returns() -> void:
	var w := _party()
	var a: World.Player = w.players[0]
	var b: World.Player = w.players[1]
	a.lives = 1
	b.lives = 2
	_fell(w, 0)
	_run(w, 3.0)
	_fell(w, 1)
	_run(w, w.tune.last_stand - 0.1)
	assert_true(a.down and b.down)
	_run(w, 0.2)
	assert_true(b.alive, "the one on 2 lives gets up though she fell later")
	assert_true(a.down, "the longest down is on her last life: she waits")
	assert_eq(b.lives, 1)
	assert_true(w.phase != World.PH_GAMEOVER, "not wiped")


func test_nobody_standing_and_nobody_can_return_wipes() -> void:
	var w := _party()
	for p: World.Player in w.players.values():
		p.lives = 1
	_fell(w, 0)
	_run(w, 1.0)
	assert_true(w.phase != World.PH_GAMEOVER)
	_fell(w, 1)
	_run(w, DT)
	assert_eq(w.phase, World.PH_GAMEOVER)


func test_a_slain_lich_raises_every_fallen() -> void:
	var w := _party(3)
	var a := _fell(w, 1)
	var b := _fell(w, 2)
	var lich := w.spawn_enemy(World.LICH, 0, G.ARENA.get_center() + Vector2(200, 100))
	w._damage_enemy(lich, 1e6, 0, Vector2.ZERO)
	assert_true(a.alive and b.alive)
	assert_eq(a.hp, ceili(a.max_hp / 2.0))


func test_nova_while_down_calls_every_two_seconds_and_never_fires_later() -> void:
	var w := _party()
	_run(w, DT, {1: _nova(0)})
	var p := _fell(w, 1)
	var bombs := p.bombs
	var evs := _run(w, DT, {1: _nova(1)})
	assert_eq(_codes(evs, World.EV_CALL).size(), 1)
	evs = _run(w, 0.5, {1: _nova(2)})
	assert_true(_codes(evs, World.EV_CALL).is_empty(), "2 s apart")
	evs = _run(w, 1.6, {1: _nova(2)})
	evs.append_array(_run(w, DT, {1: _nova(3)}))
	assert_eq(_codes(evs, World.EV_CALL).size(), 1)
	w.players[0].pos = p.pos
	evs = _run(w, 2.5, {1: _nova(3)})
	assert_true(p.alive)
	assert_true(_codes(evs, World.EV_NOVA).is_empty(), "the calls never fire a nova")
	assert_eq(p.bombs, bombs)


func test_l8_a_nova_pressed_while_dead_does_not_fire_at_respawn() -> void:
	var w := World.new([0], 3, Tuning.new())
	w.phase_t = 1e6
	_run(w, DT, {0: _nova(0)})
	var p := _fell(w, 0)
	var evs := _run(w, 0.5, {0: _nova(1)})
	evs.append_array(_run(w, 2.5, {0: _nova(1)}))
	assert_true(p.alive)
	assert_true(_codes(evs, World.EV_NOVA).is_empty(), "no nova of its own at the respawn")
	assert_eq(p.bombs, 2)


func test_e2_a_boss_killed_after_the_wipe_changes_nothing() -> void:
	var w := World.new([0], 3, Tuning.new())
	w.phase_t = 1e6
	w.players[0].lives = 1
	_fell(w, 0)
	_run(w, DT)
	assert_eq(w.phase, World.PH_GAMEOVER)
	var score := w.total_score()
	var lich := w.spawn_enemy(World.LICH, 0, G.ARENA.get_center())
	w._make_final(lich)
	w._damage_enemy(lich, 1e7, 0, Vector2.ZERO)
	assert_false(w.won, "a lost run stays lost")
	assert_eq(w.total_score(), score)
	assert_eq(w.players[0].kills, 0)


## Solo pin: a solo bot run plays exactly as it did before the fallen landed (hash taken on the base commit).
func test_solo_run_is_pinned() -> void:
	var w := World.new([0], 11, Tuning.new()) # its own Tuning: other tests change the shared one
	var bot := SmashBot.new(11)
	for i: int in range(60 * 40):
		if i == 60 * 20:
			w.players[0].invuln = 0.0
			w.hurt_player(w.players[0], 99) # one death and respawn in the pinned stretch
		var inp: PackedFloat32Array = bot.decide_in_world(w, 0)
		var p: World.Player = w.players[0]
		if not p.choices.is_empty():
			inp = SmashBot.with_pick(inp, p.choices, p.offer)
		w.step(DT, {0: inp})
		w.take_events()
	var rows: Array = [w.rng.state, w.wave, w.phase, w.total_score(), w.players[0].pos, w.players[0].hp,
		w.players[0].lives, w.players[0].upgrades, w.record.stat(0, "deaths"), w.enemies.size()]
	assert_near(w.record.stat(0, "deaths"), 1.0, 0.0001, "the stretch holds one death")
	assert_eq(hash(rows), SOLO_PIN, "solo plays as before")


## Re-pinned when wave 3 grew the catalogue (BONE SPEAR, VIGIL CANDLE, JUSTICE, THE LOVERS and their evolutions,
## CLEAVE): the level-up offers changed. With those rows banished the run still hashes 1036301149, the old pin.
## Re-pinned when stage 3 paired every evolution with an arcana and made THE TOWER and JUDGEMENT held (job A3): the
## rolls' weights and slots changed, and this stretch's picks came out as they did before wave 3 (1036301149 again).
## The casual's pair rule (SmashBot.PAIR_FROM_LEVEL) does not fire in it: no spell reaches level 3 in 40 s.
const SOLO_PIN := 1036301149
