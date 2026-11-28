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


## WHIRLWIND needs CLEAVE, which only a knight holds: a veteran without it never plans for it (its STRENGTH alone
## would look like a finished half), and a knight does.
func test_veteran_plans_whirlwind_only_with_cleave() -> void:
	var bot := SmashBot.new(1, SmashBot.VETERAN)
	var mage := {Upgrades.POWER: 1, Upgrades.weapon_entry(World.SP_ARCANE): 3}
	assert_true(bot._plan_target(mage) != Upgrades.E_CLEAVE, "a mage chases WHIRLWIND")
	var knight := {Upgrades.POWER: 1, Upgrades.W_CLEAVE: 3}
	assert_eq(bot._plan_target(knight), Upgrades.E_CLEAVE)
	var offer: Array[int] = [Upgrades.SWIFT, Upgrades.W_CLEAVE]
	assert_eq(bot.pick_card(offer, knight), 1, "the knight does not level CLEAVE toward WHIRLWIND")
	assert_true(SmashBot.PICK_PRIORITY.has(Upgrades.E_CLEAVE))


func test_casual_takes_damage_first() -> void:
	var bot := SmashBot.new(1, SmashBot.CASUAL)
	var offer: Array[int] = [Upgrades.SWIFT, Upgrades.MAGNET, Upgrades.POWER]
	assert_eq(bot.pick_card(offer, {}), 2)


## The arcana that completes a pair opens an evolution: the casual (damage first) and the novice (what is shiny)
## both take it over a plain card, and the evolution over it.
func test_casual_and_novice_take_the_arcana_that_completes_a_pair() -> void:
	var lv := {Upgrades.W_STORM: 3}
	var offer: Array[int] = [Upgrades.POWER, Upgrades.SWIFT, Upgrades.W_STORM]
	for id: int in [SmashBot.CASUAL, SmashBot.NOVICE]:
		for seed_value: int in 8:
			assert_eq(SmashBot.new(seed_value, id).pick_card(offer, lv), 1, "THE CHARIOT pairs with CHAIN LIGHTNING")
	var casual := SmashBot.new(1, SmashBot.CASUAL)
	assert_eq(casual.pick_card(offer, {Upgrades.W_STORM: 3, Upgrades.SWIFT: 1}), 0, "held already, it is a plain level: STRENGTH first")
	assert_eq(casual.pick_card(offer, {Upgrades.W_STORM: 1}), 0, "her spell is far from its top: damage now comes first")
	var no_power: Array[int] = [Upgrades.W_FIRE, Upgrades.SWIFT, Upgrades.W_STORM]
	for early: int in range(1, SmashBot.PAIR_FROM_LEVEL):
		assert_eq(casual.pick_card(no_power, {Upgrades.W_STORM: early}), 2, "a spell level before the arcana, at level %d" % early)
	assert_eq(casual.pick_card(no_power, {Upgrades.W_STORM: SmashBot.PAIR_FROM_LEVEL}), 1, "the arcana from PAIR_FROM_LEVEL")
	assert_eq(SmashBot._pair_spell_level({Upgrades.W_STORM: 4, Upgrades.W_FIRE: 2}, Upgrades.SWIFT), 4)
	assert_eq(SmashBot._pair_spell_level({Upgrades.W_FIRE: 2}, Upgrades.SWIFT), 0, "THE CHARIOT pairs with no spell she holds")
	var evo: Array[int] = [Upgrades.SWIFT, Upgrades.E_STORM, Upgrades.POWER]
	for id: int in [SmashBot.CASUAL, SmashBot.NOVICE]:
		assert_eq(SmashBot.new(1, id).pick_card(evo, {Upgrades.W_STORM: 5, Upgrades.REGEN: 1}), 1, "the evolution first")


## A veteran plans only for an evolution she can still take: never an unbuilt one, never the other road of a
## spell she has evolved.
func test_veteran_never_plans_an_unbuilt_or_shut_evolution() -> void:
	var bot := SmashBot.new(1, SmashBot.VETERAN)
	assert_false(SmashBot._plan_open({Upgrades.W_ARCANE: 5, Upgrades.QUICK: 1, Upgrades.E_ARCANE: 1}, Upgrades.E_LODESTAR),
		"ASTRAL LANCE taken shuts LODESTAR")
	assert_false(SmashBot._plan_open({Upgrades.W_ARCANE: 5, Upgrades.E_ARCANE: 1}, Upgrades.E_ARCANE), "taken already")
	assert_true(SmashBot._plan_open({Upgrades.W_ARCANE: 5}, Upgrades.E_ARCANE))
	for e: int in Upgrades.UNBUILT:
		if not Upgrades.is_evolution(e):
			continue
		var lv := {}
		for r: Array in Upgrades.CATALOG[e][Upgrades.C_REQUIRES]:
			lv[int(r[0])] = int(r[1])
		assert_true(bot._plan_target(lv) != e, "%s is unbuilt" % Upgrades.key(e))


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


func test_a_fallen_bot_drifts_to_the_nearest_standing_mate() -> void:
	var me := Vector2(100, 100)
	assert_eq(SmashBot.spirit_drift(me, [Vector2(300, 100), Vector2(100, 40)]), Vector2.UP, "the nearer mate")
	assert_eq(SmashBot.spirit_drift(me, []), Vector2.ZERO, "nobody standing: she stays")
	assert_eq(SmashBot.spirit_drift(me, [me + Vector2(SmashBot.SPIRIT_CLOSE - 1.0, 0)]), Vector2.ZERO, "close enough")
	var bot := SmashBot.new(1)
	var inp := bot.spirit_input(me, [Vector2(160, 100)])
	assert_eq([inp[0], inp[1], inp[4], inp[5]], [1.0, 0.0, 0.0, float(bot.nova_count)], "walks, never casts or calls")


## A checksum of what classless bots press (three casual wizards and a classless apprentice, seed 5, 10 s of run
## clock, the apprentice's input included): the pin was taken
## before the class play landed, so a seat with no class plays exactly as before. Refresh it only for a change
## that is meant to move classless bots (the world itself: spells, enemies).
const CLASSLESS_PIN := 242283988


func test_a_seat_with_no_class_plays_as_before() -> void:
	var w := World.new([0, 1, 2, 3], 5, null, {}, {3: {"ai": true}})
	var bots: Array[SmashBot] = []
	for s: int in range(3):
		bots.append(SmashBot.new(50 + s, SmashBot.CASUAL))
	var sum: int = 0
	for i: int in range(600):
		var inputs: Dictionary = {}
		for s: int in range(3):
			inputs[s] = bots[s].decide_in_world(w, s)
		inputs = WorldApprentices.with_inputs(w, inputs)
		for s: int in range(4):
			var inp: PackedFloat32Array = inputs[s]
			for k: int in range(6):
				sum = (sum * 31 + int(roundf(inp[k] * 1000.0)) + i) % 1000000007
		w.step(DT, inputs)
	assert_eq(sum, CLASSLESS_PIN)


## A World of heroes for the class-play tests: `classes` slot -> Classes index (-1: no hero), placed at `at` (slot ->
## offset from the arena centre), unhurt timers cleared, goblins (immortal, standing) at `goblins` (offsets).
func _heroes(classes: Dictionary, at: Dictionary, goblins: Array) -> World:
	var w := World.new(classes.keys(), 9)
	w.phase_t = 100.0 # the intro holds: no horde of its own
	var c := G.ARENA.get_center()
	for s: int in classes:
		var p: World.Player = w.players[s]
		if int(classes[s]) >= 0:
			w.apply_hero(p, Hero.make(Races.HUMAN, int(classes[s]), p.wizard).to_dict())
		p.pos = c + (at[s] as Vector2)
		p.invuln = 0.0
	for g: Vector2 in goblins:
		var e: World.Enemy = w.spawn_enemy(World.GOBLIN, 0, c + g)
		e.hp = 1e6
	w._build_grid()
	return w


## True when a veteran (it never forgets) in slot `slot` presses its skill on its first decision (which acts at once).
func _presses(w: World, slot: int) -> bool:
	var bot := SmashBot.new(3, SmashBot.VETERAN)
	return int(bot.decide_in_world(w, slot)[5]) > 0


func _ring(center: Vector2, r: float, n: int, from: float = 0.0, arc: float = TAU) -> Array:
	var out: Array = []
	for i: int in range(n):
		out.append(center + Vector2.from_angle(from + arc * i / n) * r)
	return out


func test_provoke_when_enemies_are_on_an_ally() -> void:
	var on_mate := _heroes({0: Classes.KNIGHT, 1: -1}, {0: Vector2(40, 0), 1: Vector2.ZERO}, _ring(Vector2.ZERO, 16.0, 4))
	assert_true(_presses(on_mate, 0), "several enemies on an ally")
	var calm := _heroes({0: Classes.KNIGHT, 1: -1}, {0: Vector2(40, 0), 1: Vector2.ZERO}, [Vector2(-150, 0)])
	assert_false(_presses(calm, 0), "nothing near anyone")
	var solo := _heroes({0: Classes.KNIGHT}, {0: Vector2.ZERO}, [Vector2(60, 0), Vector2(-60, 10)])
	assert_false(_presses(solo, 0), "solo and in no danger: nothing to gain")


func test_volley_rolls_away_from_a_crowd() -> void:
	# Goblins close on the archer's right half: she rolls left, out of them.
	var w := _heroes({0: Classes.ARCHER}, {0: Vector2.ZERO}, _ring(Vector2.ZERO, 15.0, 7, -PI * 0.5, PI))
	var bot := SmashBot.new(3, SmashBot.VETERAN)
	var out: PackedFloat32Array = bot.decide_in_world(w, 0)
	assert_eq(int(out[5]), 1, "a crowd on her: VOLLEY")
	assert_true(out[0] < -0.5, "rolling away from the crowd (%.2f, %.2f)" % [out[0], out[1]])
	var open := _heroes({0: Classes.ARCHER}, {0: Vector2.ZERO}, [Vector2(80, 0)])
	assert_false(_presses(open, 0), "one goblin far off: keep the charge")


func test_sanctuary_when_the_party_is_hurt_or_an_ally_is_down() -> void:
	var hurt := _heroes({0: Classes.PRIEST, 1: -1}, {0: Vector2(30, 0), 1: Vector2.ZERO}, [])
	hurt.players[1].hp = 2
	hurt.players[0].hp -= 1
	assert_true(_presses(hurt, 0), "four hearts to heal")
	var full := _heroes({0: Classes.PRIEST, 1: -1}, {0: Vector2(30, 0), 1: Vector2.ZERO}, [])
	full.players[1].hp -= 1
	assert_false(_presses(full, 0), "one heart missing: not worth a charge")
	var fallen := _heroes({0: Classes.PRIEST, 1: -1, 2: -1}, {0: Vector2(30, 0), 1: Vector2.ZERO, 2: Vector2(0, 40)}, [])
	fallen.hurt_player(fallen.players[1], 99)
	assert_true(fallen.players[1].down)
	assert_true(_presses(fallen, 0), "a fallen ally in her radius rises")


func test_aegis_when_allies_beside_her_are_about_to_be_hit() -> void:
	var goblins: Array = [Vector2(-14, 0), Vector2(0, -14), Vector2(36, -14), Vector2(36, 14)]
	var hit := _heroes({0: Classes.PALADIN, 1: -1}, {0: Vector2(36, 0), 1: Vector2.ZERO}, goblins)
	assert_true(_presses(hit, 0), "two heroes in her radius about to be hit")
	var far := _heroes({0: Classes.PALADIN, 1: -1}, {0: Vector2(36, 0), 1: Vector2.ZERO}, [Vector2(-120, 0)])
	assert_false(_presses(far, 0), "nobody about to be hit")


func test_a_tank_guards_the_ally_under_attack_and_a_healer_keeps_close() -> void:
	# The knight starts beside a mage away from the goblins on a second mage: it walks toward that crowd.
	var w := _heroes({0: Classes.KNIGHT, 1: -1, 2: -1}, {0: Vector2(-60, 0), 1: Vector2(-80, 0), 2: Vector2(40, 0)},
		_ring(Vector2(40, 0), 30.0, 3, -0.6, 1.2))
	var bot := SmashBot.new(3, SmashBot.VETERAN)
	var out: PackedFloat32Array = bot.decide_in_world(w, 0)
	assert_true(out[0] > 0.5, "the tank heads for the ally under attack (%.2f, %.2f)" % [out[0], out[1]])
	# The priest, far from a hurt ally, walks to her.
	var h := _heroes({0: Classes.PRIEST, 1: -1}, {0: Vector2(-90, 0), 1: Vector2(20, 0)}, [Vector2(120, 0)])
	h.players[1].hp = 2
	var pb := SmashBot.new(3, SmashBot.VETERAN)
	var po: PackedFloat32Array = pb.decide_in_world(h, 0)
	assert_true(po[0] > 0.5, "the healer closes on the hurt ally (%.2f, %.2f)" % [po[0], po[1]])


## A hero whose class weapon is a sweep (the knight) closes on the nearest enemy solo, where a mage keeps away
## from the same goblin.
func test_a_solo_knight_closes_to_its_sweep_while_a_mage_keeps_off() -> void:
	var knight := _heroes({0: Classes.KNIGHT}, {0: Vector2(-60, 0)}, [Vector2(30, 0)])
	var out: PackedFloat32Array = SmashBot.new(3, SmashBot.VETERAN).decide_in_world(knight, 0)
	assert_true(out[0] > 0.5, "the knight walks to the goblin (%.2f, %.2f)" % [out[0], out[1]])
	var mage := _heroes({0: Classes.MAGE}, {0: Vector2(-60, 0)}, [Vector2(30, 0)])
	var mo: PackedFloat32Array = SmashBot.new(3, SmashBot.VETERAN).decide_in_world(mage, 0)
	assert_true(mo[0] < 0.5, "the mage does not walk into it (%.2f, %.2f)" % [mo[0], mo[1]])


## Beside the boss a melee knight keeps within its sweep's reach (SmashBot.MELEE_BAND), where a casual mage at the
## same spot backs off to her band.
func test_a_knight_keeps_the_boss_within_its_sweep() -> void:
	var out: Array = []
	for cls: int in [Classes.KNIGHT, Classes.MAGE]:
		var w := _heroes({0: cls}, {0: Vector2(-45, 0)}, [])
		var lich: World.Enemy = w.spawn_enemy(Bestiary.LICH, 0, G.ARENA.get_center())
		lich.entering = false
		w.boss = lich
		w._build_grid()
		out.append(SmashBot.new(3, SmashBot.CASUAL).decide_in_world(w, 0))
	assert_true((out[0] as PackedFloat32Array)[0] >= 0.0, "the knight backed off the boss")
	assert_true((out[1] as PackedFloat32Array)[0] < 0.0, "the mage stood inside her band")


func test_a_knight_with_whirlwind_fights_at_its_longer_reach() -> void:
	var reaches: Array[float] = []
	for evolved: bool in [false, true]:
		var w := _heroes({0: Classes.KNIGHT}, {0: Vector2(-45, 0)}, [])
		var p: World.Player = w.players[0]
		if evolved:
			p.upgrades[Upgrades.weapon_entry(World.SP_CLEAVE)] = Spells.MAX_LEVEL
			p.upgrades[Upgrades.E_CLEAVE] = 1
		w._build_grid()
		var bot := SmashBot.new(3, SmashBot.CASUAL)
		bot.decide_in_world(w, 0)
		reaches.append(bot._melee_r)
	assert_near(reaches[0], Spells.stat(World.SP_CLEAVE, "r"), 0.001)
	assert_near(reaches[1], Spells.level_value(World.SP_CLEAVE, "r", Spells.MAX_LEVEL, 1), 0.001)
	assert_true(reaches[1] > reaches[0], "WHIRLWIND reaches further than CLEAVE")
