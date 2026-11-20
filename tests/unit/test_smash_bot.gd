extends TestCase
## SmashBot: the shared play-bot brain (game/logic/smash_bot.gd).

const CENTER := Vector2(400, 238)
const DT: float = 1.0 / 60.0
const ARENA := Rect2(25, 44, 750, 392)


func _decide(me: Vector2, enemies: Array[Vector2], shots: Array[Vector2] = []) -> PackedFloat32Array:
	var pk: Array[Vector2] = []
	return SmashBot.new(1).decide(0, me, CENTER, 0.0, enemies, shots, pk)


## A small kinematic stage: the wizard walks where the bot says (no clamping, so a test sees where it would go),
## enemies and shots fly along their velocities, and enemies may home in at `chase` px/s. Returns
## {path: positions per tick, hit: closest gap to any body or shot, picked: kinds collected}.
func _stage(bot: SmashBot, me: Vector2, seconds: float, enemies: Array, shots: Array, pickups: Array,
		ctx: Dictionary = {}, chase: float = 0.0) -> Dictionary:
	var path: Array[Vector2] = []
	var gap: float = INF
	var picked: Array[int] = []
	var t: float = 0.0
	var c: Dictionary = ctx.duplicate()
	c.arena = ctx.get("arena", ARENA)
	for _i: int in range(int(seconds / DT)):
		var ep: Array[Vector2] = []
		var ev: Array = []
		for e: Array in enemies:
			if chase > 0.0:
				e[1] = (me - (e[0] as Vector2)).normalized() * chase
			ep.append(e[0])
			ev.append(e[1])
		var sp: Array[Vector2] = []
		var sv: Array = []
		for s: Array in shots:
			sp.append(s[0])
			sv.append(s[1])
		var kp: Array[Vector2] = []
		var kk: Array = []
		for k: Array in pickups:
			kp.append(k[0])
			kk.append(k[1])
		c.enemy_vel = ev
		c.shot_vel = sv
		c.pickup_kinds = kk
		var out: PackedFloat32Array = bot.decide(0, me, CENTER, t, ep, sp, kp, Vector2.INF, c)
		me += Vector2(out[0], out[1]).limit_length(1.0) * SmashBot.WALK_SPEED * DT
		t += DT
		for e: Array in enemies:
			e[0] = (e[0] as Vector2) + (e[1] as Vector2) * DT
			gap = minf(gap, (e[0] as Vector2).distance_to(me) - 5.0 - 5.0)
		for s: Array in shots:
			s[0] = (s[0] as Vector2) + (s[1] as Vector2) * DT
			gap = minf(gap, (s[0] as Vector2).distance_to(me + SmashBot.CHEST) - 3.0 - 4.0)
		for k: Array in pickups.duplicate():
			if (k[0] as Vector2).distance_to(me) < 11.0:
				picked.append(int(k[1]))
				pickups.erase(k)
		path.append(me)
	return {"path": path, "gap": gap, "picked": picked, "end": me}


func test_aims_and_fires_at_nearest_enemy() -> void:
	var en: Array[Vector2] = [CENTER + Vector2(100, 0), CENTER + Vector2(0, 30)]
	var out: PackedFloat32Array = _decide(CENTER, en)
	assert_near(out[2], 0.0, 0.001, "aim x")
	assert_true(out[3] > 0.0, "should aim down at the nearer enemy")
	assert_eq(out[4], 1.0, "fire")


func test_holds_fire_with_no_enemies() -> void:
	var en: Array[Vector2] = []
	var out: PackedFloat32Array = _decide(CENTER, en)
	assert_eq(out[4], 0.0)


func test_moves_away_from_a_close_shot() -> void:
	var en: Array[Vector2] = []
	var shots: Array[Vector2] = [CENTER + SmashBot.CHEST + Vector2(5, 0)]
	var out: PackedFloat32Array = _decide(CENTER, en, shots)
	assert_true(out[0] < 0.0, "should step left, away from the shot")


func test_move_is_unit_length_at_most() -> void:
	var en: Array[Vector2] = [CENTER + Vector2(3, 0), CENTER + Vector2(-3, 1), CENTER + Vector2(0, 4)]
	var out: PackedFloat32Array = _decide(CENTER, en)
	assert_true(Vector2(out[0], out[1]).length() <= 1.0001)


func test_pick_policy_prefers_power() -> void:
	var offer: Array[int] = [Upgrades.NOVA, Upgrades.POWER, Upgrades.SWIFT]
	assert_eq(SmashBot.choose_pick(offer), 1)
	var none: Array[int] = []
	assert_eq(SmashBot.choose_pick(none), -1)


func test_with_pick_appends_card_and_offer() -> void:
	var offer: Array[int] = [Upgrades.SWIFT, Upgrades.LIFE]
	var out: PackedFloat32Array = SmashBot.with_pick(PackedFloat32Array([0, 0, 0, 0, 0, 3]), offer, 7)
	assert_eq(out.size(), 8)
	assert_eq(int(out[6]), 0, "swift beats second wind")
	assert_eq(int(out[7]), 7, "offer id")
	assert_eq(int(out[5]), 3, "nova count kept")


func test_persona_names_round_trip() -> void:
	for id: int in [SmashBot.NOVICE, SmashBot.CASUAL, SmashBot.VETERAN]:
		assert_eq(SmashBot.persona_from_name(SmashBot.persona_name(id)), id)
	assert_eq(SmashBot.persona_from_name("nobody"), -1)


func test_veteran_finishes_an_evolution() -> void:
	var bot := SmashBot.new(1, SmashBot.VETERAN)
	# Fireball at 5 needs Chain Lightning to evolve: the veteran takes the partner over raw power.
	var lv := {Upgrades.weapon_entry(World.SP_FIRE): 5}
	var partner: int = int(Upgrades.CATALOG[Upgrades.evo_entry(World.SP_FIRE)][5][1][0])
	var offer: Array[int] = [Upgrades.POWER, partner, Upgrades.SWIFT]
	assert_eq(bot.pick_card(offer, lv), 1, "takes the partner spell")
	lv[partner] = 1
	var evo: Array[int] = [Upgrades.QUICK, Upgrades.evo_entry(World.SP_FIRE)]
	assert_eq(bot.pick_card(evo, lv), 1, "then the evolution")


func test_casual_takes_damage_first() -> void:
	var bot := SmashBot.new(1, SmashBot.CASUAL)
	var offer: Array[int] = [Upgrades.SWIFT, Upgrades.MAGNET, Upgrades.POWER]
	assert_eq(bot.pick_card(offer, {}), 2)


func _world_inputs(seed_value: int, persona: int) -> Array:
	var w := World.new([0, 1], seed_value)
	var bots: Array[SmashBot] = [SmashBot.new(seed_value, persona), SmashBot.new(seed_value + 1, persona)]
	var seen: Array = []
	for _i: int in range(300):
		var inputs: Dictionary = {}
		for s: int in range(2):
			inputs[s] = bots[s].decide_in_world(w, s)
			seen.append(inputs[s])
		w.step(DT, inputs)
	return [hash(seen), w.state_hash()]


func test_same_seed_same_inputs() -> void:
	for persona: int in [SmashBot.NOVICE, SmashBot.VETERAN]:
		var a: Array = _world_inputs(11, persona)
		var b: Array = _world_inputs(11, persona)
		assert_eq(a[0], b[0], "inputs diverged for persona %d" % persona)
		assert_eq(a[1], b[1], "world diverged for persona %d" % persona)


func test_calm_scene_holds_a_steady_heading() -> void:
	for persona: int in [SmashBot.NOVICE, SmashBot.CASUAL, SmashBot.VETERAN]:
		var bot := SmashBot.new(3, persona)
		# A few enemies far off, nothing near: a person walks a line, not a zigzag.
		var far: Array = [[CENTER + Vector2(300, 150), Vector2.ZERO], [CENTER + Vector2(-320, -160), Vector2.ZERO]]
		var r: Dictionary = _stage(bot, CENTER + Vector2(-100, 40), 2.0, far, [], [])
		var flips: int = 0
		var path: Array = r.path
		var last := Vector2.ZERO
		for i: int in range(1, path.size()):
			var step: Vector2 = path[i] - path[i - 1]
			if step.length() < 0.5:
				continue
			if last != Vector2.ZERO and absf(last.angle_to(step)) > PI * 0.5:
				flips += 1
			last = step
		assert_true(flips <= 1, "persona %d flipped heading %d times in 2 s" % [persona, flips])


func test_sidesteps_a_shot_on_a_collision_course() -> void:
	for persona: int in [SmashBot.CASUAL, SmashBot.VETERAN]:
		var bot := SmashBot.new(5, persona)
		var me := CENTER
		var shots: Array = [[me + SmashBot.CHEST + Vector2(90, 0), Vector2(-150, 0)]]
		var r: Dictionary = _stage(bot, me, 1.0, [], shots, [])
		assert_true(r.gap > 0.0, "persona %d was hit by the shot (gap %.1f)" % [persona, r.gap])


func test_leaves_a_closing_ring_through_the_widest_gap() -> void:
	for persona: int in [SmashBot.CASUAL, SmashBot.VETERAN]:
		var bot := SmashBot.new(7, persona)
		var me := CENTER
		var ring: Array = []
		# 16 slots of 22.5 degrees: a wide gap round 180 degrees (4 slots out) and a narrow one at 0 (1 slot out).
		for i: int in range(16):
			if i == 0 or (i >= 7 and i <= 10):
				continue
			var at: Vector2 = me + Vector2.from_angle(i * TAU / 16.0) * 70.0
			ring.append([at, (me - at).normalized() * 30.0])
		var r: Dictionary = _stage(bot, me, 1.5, ring, [], [])
		var out: Vector2 = (r.end as Vector2) - me
		assert_true(r.gap > 0.0, "persona %d touched the ring (gap %.1f)" % [persona, r.gap])
		assert_true(out.length() > 70.0, "persona %d still inside the ring" % persona)
		assert_true(absf(out.angle_to(Vector2.LEFT)) < PI * 0.3, "persona %d left by %s, not the wide gap" % [persona, out])


func test_fetches_a_potion_when_hurt_and_walks_past_it_at_full_health() -> void:
	var me := CENTER
	var mote := me + Vector2(120, 0)
	var potion := me + Vector2(50, 45)
	var hurt := SmashBot.new(9, SmashBot.CASUAL)
	var r: Dictionary = _stage(hurt, me, 2.5, [], [], [[potion, World.PK_POTION], [mote, World.PK_XP]],
		{"hp": 2, "max_hp": 5})
	assert_true((r.picked as Array).has(World.PK_POTION), "hurt wizard should fetch the potion")
	var full := SmashBot.new(9, SmashBot.CASUAL)
	r = _stage(full, me, 2.5, [], [], [[potion, World.PK_POTION], [mote, World.PK_XP]], {"hp": 5, "max_hp": 5})
	assert_false((r.picked as Array).has(World.PK_POTION), "full health should leave the potion")
	assert_true((r.picked as Array).has(World.PK_XP), "and take the XP mote")


func test_stays_inside_the_arena_and_the_leash() -> void:
	# Enemies chase it from the middle toward the left wall; the leash box is tighter than the arena.
	var bot := SmashBot.new(13, SmashBot.CASUAL)
	var me := Vector2(ARENA.position.x + 30, CENTER.y)
	var pack: Array = []
	for i: int in range(8):
		pack.append([me + Vector2(70, -60 + i * 17), Vector2.ZERO])
	var leash := Rect2(ARENA.position.x, CENTER.y - 90, 300, 180)
	var r: Dictionary = _stage(bot, me, 3.0, pack, [], [], {"leash": leash, "mates": [Vector2(200, CENTER.y)]}, 45.0)
	for p: Vector2 in r.path:
		assert_true(ARENA.grow(2.0).has_point(p), "left the arena at %s" % p)
		assert_true(leash.grow(4.0).has_point(p), "broke the leash at %s" % p)
		if not ARENA.grow(2.0).has_point(p) or not leash.grow(4.0).has_point(p):
			break
