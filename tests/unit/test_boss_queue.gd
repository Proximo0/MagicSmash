extends TestCase
## The boss queue (WorldWaves._tick_minute): every scheduled boss comes at its minute. An act boss still up when the
## next row falls due leaves (Bosses._leave: no bounty, no deed); at the final's minute a boss of another kind
## leaves and a Lich still standing ascends. Also the Lich's summons respect the enemy cap (BossLich.think).

const DT: float = 1.0 / 60.0


## A World fighting at `secs` with the act schedule, no horde, no shrines and untouchable wizards.
func _queue_world(secs: float, slots: Array = [0, 1]) -> World:
	var w := World.new(slots, 3)
	w.schedule = Bosses.SCHEDULE
	w.phase = World.PH_FIGHT
	w.wave_time = secs
	w.wave = int(secs / 60.0) + 1
	w.horde_budget = -99999.0
	w.shrine_t = 99999.0
	w.team_shrine_t = 99999.0
	for p: World.Player in w.players.values():
		p.invuln = 99999.0
	return w


## Steps the whole World `secs` seconds with no input.
func _step_for(w: World, secs: float) -> void:
	for _i: int in int(secs * 60.0):
		w.step(DT, {})


func _act_boss_notes(w: World) -> int:
	var n := 0
	for m: Array in w.record.moments:
		if int(m[1]) == Results.M_ACT_BOSS:
			n += 1
	return n


func test_the_act_ii_boss_comes_while_the_act_i_boss_is_still_up() -> void:
	var w := _queue_world(599.0)
	var chand: World.Enemy = w._spawn_boss(Bestiary.CHANDELIER, false)
	chand.hp = 1e9 # it outlives the minute whatever the wizards cast
	chand.maxhp = 1e9
	var pickups := w.pickups.size()
	_step_for(w, 5.0)
	assert_true(chand.dead, "the act I boss left at 10:00")
	assert_true(w.boss != null and w.boss.type == Bestiary.GHOSTWRITER, "the act II boss came within seconds")
	assert_eq(w.liches_slain, 0, "a boss that left counts as no kill")
	assert_eq(_act_boss_notes(w), 0, "a boss that left earns no deed")
	assert_true(w.pickups.size() <= pickups + 2, "a boss that left pays no bounty (%d pickups)" % w.pickups.size())
	assert_eq(w.lull_left, 0.0, "no lull: it did not die")


func test_the_act_ii_boss_comes_as_today_when_the_act_i_boss_is_dead() -> void:
	var w := _queue_world(599.0)
	_step_for(w, 5.0)
	assert_true(w.boss != null and w.boss.type == Bestiary.GHOSTWRITER, "the act II boss came")


func test_the_act_ii_boss_is_queued_on_the_minute_with_the_act_i_boss_up() -> void:
	var w := _queue_world(599.9)
	var chand: World.Enemy = w._spawn_boss(Bestiary.CHANDELIER, false)
	w.wave_time = 600.0
	w._tick_minute()
	assert_true(chand.dead)
	assert_true(w.boss == null, "the header clears for the next boss")
	var queued := 0
	for s: Dictionary in w.spawn_queue:
		if int(s.type) == Bestiary.GHOSTWRITER and not s.get("final", false):
			queued += 1
	assert_eq(queued, 1, "the due boss is queued once")


func test_a_minute_with_no_boss_row_leaves_the_standing_boss_alone() -> void:
	var w := _queue_world(419.9)
	var chand: World.Enemy = w._spawn_boss(Bestiary.CHANDELIER, false)
	w.wave_time = 420.0
	w._tick_minute()
	assert_false(chand.dead, "only a due row sends a boss away")
	assert_true(w.boss == chand)


func test_at_the_final_minute_another_kind_leaves() -> void:
	var w := _queue_world(899.9, [0])
	var ghost: World.Enemy = w._spawn_boss(Bestiary.GHOSTWRITER, false)
	w.wave_time = 900.0
	w._tick_minute()
	assert_true(ghost.dead, "the other boss gives way")
	assert_false(ghost.final)
	var queued := false
	for s: Dictionary in w.spawn_queue:
		queued = queued or (int(s.type) == World.LICH and s.get("final", false))
	assert_true(queued, "the final boss comes")


func test_at_the_final_minute_a_standing_lich_ascends() -> void:
	var w := _queue_world(899.9, [0])
	var lich: World.Enemy = w._spawn_boss(World.LICH, false)
	w.wave_time = 900.0
	w._tick_minute()
	assert_false(lich.dead)
	assert_true(lich.final, "the Lich still standing ascends")
	assert_true(w.boss == lich)
	for s: Dictionary in w.spawn_queue:
		assert_false(Bestiary.has_flag(int(s.type), Bestiary.F_BOSS), "no second final is queued")


func test_lich_summons_stop_at_the_enemy_cap() -> void:
	var w := _queue_world(700.0)
	var e: World.Enemy = w.spawn_enemy(World.LICH, 0, Vector2(240, 120))
	e.final = true
	e.hp = e.maxhp * 0.2 # enraged: the elite would come too
	e.enter_dir.y = 2.0 # its phase turns are done
	while w.enemies.size() < w.enemy_cap() - 3:
		w.spawn_enemy(World.GOBLIN, 0, Vector2(100, 100))
	e.state = 4
	BossLich.think(w, e, DT, w.players[0], Vector2.RIGHT, 100.0)
	assert_eq(w.enemies.size() + w.spawn_queue.size(), w.enemy_cap(), "the summons fill the cap and no more")
	e.state = 4
	BossLich.think(w, e, DT, w.players[0], Vector2.RIGHT, 100.0)
	assert_eq(w.enemies.size() + w.spawn_queue.size(), w.enemy_cap(), "a summon at the cap brings none")


func test_lich_summons_in_full_below_the_cap() -> void:
	var w := _queue_world(700.0)
	var e: World.Enemy = w.spawn_enemy(World.LICH, 0, Vector2(240, 120))
	var n := w.enemies.size() + w.spawn_queue.size()
	e.state = 4
	BossLich.think(w, e, DT, w.players[0], Vector2.RIGHT, 100.0)
	assert_eq(w.enemies.size() + w.spawn_queue.size(), n + World.DOORS.size() * 2, "two from every door")


## B2: the Lich's and the Archlich's waypoints follow the party's middle (BossLich.DRIFT_*), inside half a screen,
## even with the party at the bottom of the room or in a corner.
func test_lich_waypoints_stay_near_a_party_low_in_the_room() -> void:
	for spot: Vector2 in [Vector2(400, 420), Vector2(40, 425), Vector2(760, 60)]:
		var w := _queue_world(910.0, [0])
		w.players[0].pos = spot
		w._plist.assign(w.players.values())
		var e: World.Enemy = w.spawn_enemy(World.LICH, 0, Vector2(400, 120))
		w._make_final(e)
		e.enter_dir.y = 0.0
		var mid := w.party_center()
		for _i: int in range(600):
			e.state = 0
			e.timer = 99.0 # drift only
			e.pos += BossLich.think(w, e, DT, w.players[0], Vector2.RIGHT, 100.0) * DT
			assert_true(absf(e.dir.x - mid.x) <= BossLich.DRIFT_X and absf(e.dir.y - mid.y) <= BossLich.DRIFT_UP,
				"waypoint %s near the party at %s" % [e.dir, spot])
			assert_true(G.ARENA.has_point(e.dir), "waypoint %s inside the room" % e.dir)
			if absf(e.dir.y - mid.y) > BossLich.DRIFT_UP:
				break


## A Lich walks in from the top door. With the party low in the room it must not attack from out of sight
## (BossLich.SIGHT_INSET): it closes in at SIGHT_HASTE first, then attacks.
func test_the_lich_starts_no_attack_out_of_sight_and_closes_in() -> void:
	var w := _queue_world(910.0, [0])
	w.players[0].pos = Vector2(400, 420)
	w._plist.assign(w.players.values())
	var e: World.Enemy = w.spawn_enemy(World.LICH, 0, Vector2(400, 60))
	e.state = 0
	e.timer = 0.0 # it would choose an attack at once
	var mid := w.party_center()
	assert_false(BossLich._lich_in_sight(e.pos, mid), "the test starts with the Lich out of sight")
	var ticks := 0
	while not BossLich._lich_in_sight(e.pos, mid) and ticks < 900:
		e.pos += BossLich.think(w, e, DT, w.players[0], Vector2.DOWN, 300.0) * DT
		assert_eq(e.state, 0, "no attack starts out of sight")
		ticks += 1
	assert_true(ticks < 6 * 60, "it is in the party's sight within 6 s (took %d ticks)" % ticks)
	BossLich.think(w, e, DT, w.players[0], Vector2.DOWN, 100.0)
	assert_true(e.state != 0, "once in sight it attacks")


## The Lich's teleport lands near the party's middle (BossLich.TELE_KEEP): in sight, inside the room and never on
## top of the party, for a lone wizard, a wizard in a corner and four wizards.
func test_the_lich_teleport_lands_in_sight_and_clear_of_the_party() -> void:
	var parties: Array = [[Vector2(400, 420)], [Vector2(30, 430)], [Vector2(770, 45)],
		[Vector2(380, 230), Vector2(420, 230), Vector2(400, 200), Vector2(400, 260)]]
	for spots: Array in parties:
		var w := _queue_world(910.0, range(spots.size()))
		for i: int in spots.size():
			w.players[i].pos = spots[i]
		w._plist.assign(w.players.values())
		var mid := w.party_center()
		var e: World.Enemy = w.spawn_enemy(World.LICH, 0, Vector2(60, 60))
		for _i: int in 24:
			e.state = 5
			e.timer = 0.0
			BossLich.think(w, e, DT, w.players[0], Vector2.RIGHT, 100.0)
			assert_true(BossLich._lich_in_sight(e.pos, mid), "landing %s in sight of the party at %s" % [e.pos, mid])
			assert_true(e.pos.distance_to(mid) >= BossLich.TELE_KEEP * 0.5, "landing %s clear of the party at %s" % [e.pos, mid])
			assert_true(G.ARENA.has_point(e.pos), "landing %s inside the room" % e.pos)
