extends TestCase
## Bots and the eight kinds' warnings (SmashBot with Hazards.steer / threat): a casual and a veteran bot, alone with
## one danger, walk out of a censor's FIRE, a cinderling's MARK and FLAME and a shard's turning BEAM in time.

const DT := 1.0 / 60.0


func _bots_world() -> World:
	var t := Tuning.new()
	t.enemy_cap = 0.0
	t.elite_interval = 9999.0
	var w := World.new([0], 3, t)
	w.phase = World.PH_FIGHT
	w.powerup_timer = 9999.0
	(w.players[0] as World.Player).invuln = 0.0
	return w


## Steps `secs` with the bot driving slot 0; returns the hearts lost.
func _bots_run(w: World, bot: SmashBot, secs: float) -> int:
	var p: World.Player = w.players[0]
	var hp := p.hp
	for _i: int in range(roundi(secs / DT)):
		p.invuln = minf(p.invuln, 0.0) if p.hp == hp else p.invuln
		w.step(DT, {0: bot.decide_in_world(w, 0)})
	return hp - p.hp


func test_bots_leave_a_fire_thrown_at_their_feet() -> void:
	for persona: int in [SmashBot.CASUAL, SmashBot.VETERAN]:
		for s: int in range(4):
			var w := _bots_world()
			var p: World.Player = w.players[0]
			w.add_hazard(Hazards.FIRE, p.pos, p.pos, KindsLibrary.CENSOR_FIRE_R, KindsLibrary.CENSOR_FIRE_WARN,
				KindsLibrary.CENSOR_FIRE_HOT)
			assert_eq(_bots_run(w, SmashBot.new(s + 1, persona), 4.0), 0, "persona %d seed %d burned" % [persona, s])


func test_bots_dodge_a_censors_throws() -> void:
	for persona: int in [SmashBot.CASUAL, SmashBot.VETERAN]:
		for s: int in range(3):
			var w := _bots_world()
			var p: World.Player = w.players[0]
			var e := w.spawn_enemy(Bestiary.CENSOR, 0, p.pos + Vector2.from_angle(s * 2.1) * 120.0)
			e.hp = 9999.0
			e.timer = 0.0
			assert_eq(_bots_run(w, SmashBot.new(s + 1, persona), 9.0), 0, "persona %d seed %d burned" % [persona, s])


func test_bots_leave_a_cinderlings_line() -> void:
	for persona: int in [SmashBot.CASUAL, SmashBot.VETERAN]:
		for s: int in range(4):
			var w := _bots_world()
			var p: World.Player = w.players[0]
			var e := w.spawn_enemy(Bestiary.CINDERLING, 0, p.pos + Vector2.from_angle(s * 1.3) * 110.0)
			e.hp = 9999.0
			e.timer = 0.0
			assert_eq(_bots_run(w, SmashBot.new(s + 1, persona), 4.0), 0, "persona %d seed %d burned" % [persona, s])


func test_bots_keep_out_of_a_turning_beam() -> void:
	for persona: int in [SmashBot.CASUAL, SmashBot.VETERAN]:
		for s: int in range(4):
			var w := _bots_world()
			var p: World.Player = w.players[0]
			var e := w.spawn_enemy(Bestiary.SHARD, 0, p.pos + Vector2.from_angle(s * 1.3) * 70.0)
			e.state = KindsSanctum.SS_IDLE
			e.hp = 9999.0
			assert_eq(_bots_run(w, SmashBot.new(s + 1, persona), 12.0), 0, "persona %d seed %d burned" % [persona, s])
