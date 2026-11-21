extends TestCase
## THE GHOST WRITER (game/logic/boss_ghostwriter.gd): spelled words in the header, her fixed order, NAME on the
## named wizards, SHELF's odd then even lanes, GOODBYE's check, her turn, a fallen wizard on the floor.

const DT := 1.0 / 60.0


## A world with `n` wizards around the middle and the Ghost Writer in, at minute 11 (her 10:00 visit).
func _ghost_world(n: int) -> Array:
	var w := World.new(range(n), 7)
	w.phase = World.PH_FIGHT
	w.wave = 11
	w.wave_time = 600.0
	var c := G.ARENA.get_center()
	for p: World.Player in w.players.values():
		p.pos = c + Vector2.from_angle(TAU * p.slot / maxi(n, 1)) * 30.0
		p.invuln = 999.0
	var e: World.Enemy = w._spawn_boss(Bestiary.GHOSTWRITER, false)
	e.entering = false
	e.pos = c + Vector2(0, -90)
	_ghost_run(w, e, DT)
	return [w, e]


## Runs only her and the rows for `secs`; `seen` gathers the words she starts and every row she lays.
func _ghost_run(w: World, e: World.Enemy, secs: float, seen: Dictionary = {}) -> void:
	w._plist.assign(w.players.values())
	for _i: int in int(secs / DT):
		if e.dead:
			return
		var was := w.boss_arg
		WorldEnemies._update_enemy(w, e, DT)
		w._update_hazards(DT)
		WorldEnemies._update_eshots(w, DT)
		if w.boss_arg != was and BossGhostwriter.word_of(w.boss_arg) != BossGhostwriter.WORD_NONE:
			(seen.get_or_add("words", []) as Array).append(BossGhostwriter.word_of(w.boss_arg))
			(seen.get_or_add("args", []) as Array).append(w.boss_arg)
		for h: Hazards.Hazard in w.hazards:
			(seen.get_or_add("rows", {}) as Dictionary)[h.id] = h


func test_attacks_pass_min_warn() -> void:
	for row: Array in BossGhostwriter.ATTACKS:
		if int(row[2]) >= 0:
			assert_true(float(row[1]) >= Hazards.min_warn(float(row[3])), "row %s" % [row])


func test_the_order_is_fixed_and_every_row_warns_long_enough() -> void:
	var made: Array = _ghost_world(2)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	var seen := {}
	_ghost_run(w, e, 30.0, seen)
	var flat: Array = []
	for entry: Array in BossGhostwriter.ORDER_1:
		flat.append_array(entry)
	assert_true((seen.words as Array).size() >= 5, "words %s" % [seen.words])
	for i: int in (seen.words as Array).size():
		assert_eq(seen.words[i], flat[i % flat.size()], "word %d" % i)
	for h: Hazards.Hazard in (seen.rows as Dictionary).values():
		assert_true(h.warn0 >= Hazards.min_warn(h.r) - 0.001, "kind %d r %.0f warned %.2f" % [h.kind, h.r, h.warn0])


func test_a_word_is_spelled_in_the_header() -> void:
	var made: Array = _ghost_world(1)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	BossGhostwriter.spell(w, e, BossGhostwriter.WORD_SHELF)
	assert_eq(BossGhostwriter.word_of(w.boss_arg), BossGhostwriter.WORD_SHELF)
	assert_eq(int(w.boss_t), 1, "the first letter shows at once")
	_ghost_run(w, e, BossGhostwriter.LETTER * 2.5)
	assert_eq(int(w.snapshot().w[World.W_BOSS_T]), 3)
	assert_eq(BossGhostwriter.word_text(int(w.snapshot().w[World.W_BOSS_ARG]), {}), "SHELF")
	var arg := BossGhostwriter.encode(BossGhostwriter.WORD_NAME, 2, 0)
	assert_eq(BossGhostwriter.named(arg), [2, 0] as Array[int])
	assert_eq(BossGhostwriter.word_text(arg, {0: "VIOLET", 2: "EMERALD"}), "EMERALD&VIOLET")


func test_shelf_lights_odd_then_even_lanes() -> void:
	var made: Array = _ghost_world(1)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	BossGhostwriter.spell(w, e, BossGhostwriter.WORD_SHELF)
	var odd: Array[float] = []
	for h: Hazards.Hazard in w.hazards:
		if h.kind == Hazards.FLAME:
			odd.append(h.a.x)
	assert_eq(odd.size(), BossGhostwriter.SHELF_LANES / 2)
	for i: int in odd.size():
		assert_near(odd[i], G.ARENA.position.x + BossGhostwriter.SHELF_HW + 2 * i * Bosses.SHELF_STEP, 0.01, "an odd lane")
	var warn := 5 * BossGhostwriter.LETTER + BossGhostwriter.WORD_PAD
	_ghost_run(w, e, warn + DT * 2)
	var even: Array[float] = []
	for h: Hazards.Hazard in w.hazards:
		if h.kind == Hazards.FLAME and h.warn > 0.0:
			even.append(h.a.x)
			assert_near(h.warn0, Bosses.SHELF_EVEN_WARN, 0.001)
	assert_eq(even.size(), BossGhostwriter.SHELF_LANES / 2, "the even lanes come as the odd ones burn")
	for x: float in even:
		assert_true(odd.has(x - Bosses.SHELF_STEP), "an even lane right of an odd one")


func test_name_follows_the_named_wizard_and_leaves_fire() -> void:
	var made: Array = _ghost_world(2)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	BossGhostwriter.spell(w, e, BossGhostwriter.WORD_NAME)
	var named := BossGhostwriter.named(w.boss_arg)
	assert_eq(named.size(), 1)
	var p: World.Player = w.players[named[0]]
	assert_eq(BossGhostwriter.word_text(w.boss_arg, BossGhostwriter.names_in(w)), Wizards.wizard_name(p.wizard))
	var blast := Bosses.last_row(w, e, Hazards.BLAST)
	assert_eq(blast.follow, p.slot)
	p.pos += Vector2(40, 0)
	_ghost_run(w, e, 0.2)
	assert_true(blast.a.distance_to(p.pos) < 1.0, "it follows")
	_ghost_run(w, e, blast.warn + 0.1)
	var fire := Bosses.last_row(w, e, Hazards.FIRE)
	assert_true(fire != null and fire.r == Bosses.LEFT_FIRE_R, "no fire left")


func test_goodbye_stops_at_its_share_and_drops_one_potion() -> void:
	var made: Array = _ghost_world(1)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	for round: int in 2:
		BossGhostwriter.spell(w, e, BossGhostwriter.WORD_GOODBYE)
		_ghost_run(w, e, 0.6)
		assert_eq(e.state, BossGhostwriter.BYE)
		assert_near(BossGhostwriter.filter_damage(w, e, 1.0, Vector2.ZERO, false), BossGhostwriter.VULN, 0.001)
		e.hp -= e.maxhp * BossGhostwriter.BYE_SHARE * 0.5
		_ghost_run(w, e, DT)
		assert_near(w.boss_meter, 0.5, 0.01, "the meter shows the share dealt")
		e.hp -= e.maxhp * BossGhostwriter.BYE_SHARE * 0.5
		_ghost_run(w, e, DT)
		assert_eq(e.state, BossGhostwriter.STAGGER)
		assert_eq(int(w.boss_t), BossGhostwriter.BYE_STOP, "G-O-O-D")
		var potions := 0
		for k: World.Pickup in w.pickups:
			potions += 1 if k.kind == World.PK_POTION else 0
		assert_eq(potions, 1, "one potion in all (round %d)" % round)
		_ghost_run(w, e, BossGhostwriter.STAGGER_S + 0.1)
	assert_eq(w.eshots.size(), 0, "no rings when it was stopped")


func test_goodbye_unanswered_fires_three_rings() -> void:
	var made: Array = _ghost_world(1)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	BossGhostwriter.spell(w, e, BossGhostwriter.WORD_GOODBYE)
	_ghost_run(w, e, 7 * BossGhostwriter.BYE_LETTER + BossGhostwriter.WORD_PAD + BossGhostwriter.BYE_EVERY * 2 + 0.1)
	assert_eq(w.eshots.size(), BossGhostwriter.BYE_RINGS * BossGhostwriter.BYE_RING_N)
	for s: World.EShot in w.eshots:
		assert_near(s.vel.length(), BossGhostwriter.BYE_SPEED, 0.01)


func test_she_turns_at_half_and_names_two_in_a_big_party() -> void:
	var made: Array = _ghost_world(3)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	_ghost_run(w, e, 3.0)
	e.hp = e.maxhp * 0.51
	_ghost_run(w, e, 0.1)
	assert_eq(e.turn, 0.0)
	e.hp = e.maxhp * 0.49
	_ghost_run(w, e, DT)
	assert_true(e.turn > 0.0, "no turn under half")
	var seen := {}
	_ghost_run(w, e, BossGhostwriter.TURN_S + BossGhostwriter.GAP_2 + 0.2, seen)
	assert_eq(seen.words[0], BossGhostwriter.WORD_NAME, "phase 2 opens with NAME")
	assert_eq(BossGhostwriter.named(seen.args[0]).size(), 2, "two names with three wizards")
	_ghost_run(w, e, 4.0, seen)
	assert_eq(seen.words[1], BossGhostwriter.WORD_FIRE, "NAME+FIRE")


func test_a_fallen_wizard_is_never_named() -> void:
	var made: Array = _ghost_world(2)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	WorldPlayers._fall(w, w.players[1])
	var seen := {}
	_ghost_run(w, e, 30.0, seen)
	e.hp = e.maxhp * 0.4
	_ghost_run(w, e, 30.0, seen)
	assert_false(e.dead)
	for arg: int in seen.args:
		assert_false(1 in BossGhostwriter.named(arg), "named the spirit")
	for h: Hazards.Hazard in (seen.rows as Dictionary).values():
		assert_true(h.follow != 1, "a row follows the spirit")


func test_health_from_the_tables_at_minute_ten() -> void:
	for n: int in [1, 4]:
		var w := World.new(range(n), 5)
		w.wave = 11
		w.wave_time = 600.0
		var e: World.Enemy = w._spawn_boss(Bestiary.GHOSTWRITER, false)
		assert_near(e.maxhp, float(Bestiary.KINDS[Bestiary.GHOSTWRITER][Bestiary.K_HP]) * w.tune.boss_hp_mul * Bosses.PARTY_HP[n - 1], 0.01,
			"no cycle growth: she comes once")


## Every living wizard is named in turn: over a round of NAMEs each is called, none twice before the rest.
func test_name_takes_turns_with_2_3_and_4_wizards() -> void:
	for n: int in [2, 3, 4]:
		for phase2: bool in [false, true]:
			var made: Array = _ghost_world(n)
			var w: World = made[0]
			var e: World.Enemy = made[1]
			if phase2:
				e.enter_dir.y += 1.0 # turned
			var per_cast := 2 if phase2 and n >= BossGhostwriter.TWO_NAMES_AT else 1
			var called: Array[int] = []
			for _k: int in n * 2:
				BossGhostwriter.spell(w, e, BossGhostwriter.WORD_NAME)
				called.append_array(BossGhostwriter.named(w.boss_arg))
				w.hazards.clear()
			assert_eq(called.size(), n * 2 * per_cast)
			for s: int in n:
				assert_eq(called.count(s), 2 * per_cast, "%d wizards, phase %d: slot %d named %d times in %s" % [n, 2 if phase2 else 1, s, called.count(s), called])


func test_the_stagger_potion_heeds_the_hierophant() -> void:
	var made: Array = _ghost_world(1)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	w.no_potions = 30.0
	BossGhostwriter.spell(w, e, BossGhostwriter.WORD_GOODBYE)
	_ghost_run(w, e, 0.5)
	e.hp -= e.maxhp * BossGhostwriter.BYE_SHARE
	_ghost_run(w, e, 2 * DT)
	assert_eq(e.state, BossGhostwriter.STAGGER)
	for k: World.Pickup in w.pickups:
		assert_true(k.kind != World.PK_POTION, "a potion under THE HIEROPHANT")


func test_fire_never_runs_without_its_lane() -> void:
	var made: Array = _ghost_world(1)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	while w.add_hazard(Hazards.MARK, Vector2(30, 50), Vector2(40, 50), 2.0, 9.0, 9.0, -1, 0, true) != null:
		pass
	BossGhostwriter.spell(w, e, BossGhostwriter.WORD_FIRE)
	assert_true(Bosses.last_row(w, e, Hazards.LANE) == null)
	_ghost_run(w, e, 3.0)
	assert_true(e.state != BossGhostwriter.RUN, "charged with no lane")


func test_her_death_is_her_own_moment_not_the_lich() -> void:
	var made: Array = _ghost_world(1)
	var w: World = made[0]
	var e: World.Enemy = made[1]
	w._kill_enemy(e, 0)
	var kinds: Array = []
	for m: Array in w.record.moments:
		kinds.append(int(m[1]))
	assert_false(Results.M_LICH in kinds, "an act boss is not the Lich")
	assert_true(Results.M_ACT_BOSS in kinds)
	for m: Array in w.record.moments:
		if int(m[1]) == Results.M_ACT_BOSS:
			assert_eq(Results.moment_text(m), "P1 SLEW THE GHOST WRITER")
