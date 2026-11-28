extends TestCase
## The hooks every cast and every hit reads (docs/stage3_brief.md § 4.5): THE STAR's missiles (WorldCasting._missiles),
## THE EMPRESS's area (WorldCasting._area), the attacker's and the foe's damage multipliers (WorldEnemies._dealt_mul,
## _taken_mul); the two arcana built on them, `star` and `empress`, and the use counters of the ten arcana of today
## (`quick`, `power`, `lovers`, `justice`, `swift`, `regen`, `magnet`, `wisdom`, `nova`, `life`) at their events.

const DT := 1.0 / 60.0
## THE STAR's missiles and THE EMPRESS's area by level, as content list § 39 has them.
const STAR_LEVELS: Array[int] = [1, 2]
const EMPRESS_LEVELS: Array[float] = [1.1, 1.2, 1.3]
## The bolt spells and what each one's count is, at level 1 with THE STAR at 0, 1 and 2 (content list § 38).
const BOLT_COUNTS: Dictionary = {
	World.SP_ARCANE: [1, 2, 3], World.SP_FIRE: [1, 2, 3], World.SP_FROST: [3, 4, 5], World.SP_STAR: [2, 3, 4],
	World.SP_BONE: [2, 3, 4],
}
## Past a reach by this many px: just outside it.
const JUST := 2.0


## A world past its intro with `n` wizards at fixed spots apart, unhurtable.
func _world(n: int = 1) -> World:
	var slots: Array = []
	for i: int in range(n):
		slots.append(i)
	var w := World.new(slots, 11, Tuning.new())
	w.phase = World.PH_FIGHT
	for i: int in range(n):
		var p: World.Player = w.players[i]
		p.pos = Vector2(300 + i * 200, 240)
		p.invuln = 999.0
	w._plist.assign(w.players.values())
	return w


## A tough orc that has walked in.
func _orc(w: World, at: Vector2) -> World.Enemy:
	var e: World.Enemy = w.spawn_enemy(World.ORC, 0, at)
	e.entering = false
	e.hp = 100000.0
	e.maxhp = 100000.0
	return e


## Sets row `idx` of `p` to `lv` (0: she does not hold it).
func _hold(p: World.Player, idx: int, lv: int) -> void:
	if lv <= 0:
		p.upgrades.erase(idx)
	else:
		p.upgrades[idx] = lv


func _hurt(foes: Array) -> int:
	var n := 0
	for e: World.Enemy in foes:
		if e.hp < e.maxhp:
			n += 1
	return n


func _codes(evs: Array, code: int) -> Array:
	return evs.filter(func(ev: Array) -> bool: return int(ev[0]) == code)


## A block of `cols` x `rows` orcs `gap` px apart, its near edge `ahead` px to the right of `at`.
func _block(w: World, at: Vector2, ahead: float, cols: int, rows: int, gap: float) -> Array:
	var out: Array = []
	for c: int in range(cols):
		for r: int in range(rows):
			out.append(_orc(w, at + Vector2(ahead + c * gap, (r - (rows - 1) * 0.5) * gap)))
	return out


# --------------------------------------------------------------------------------------------- the hooks by level --

func test_missiles_and_area_follow_the_levels() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	assert_eq(WorldCasting._missiles(p), 0, "THE STAR's missiles without her")
	assert_eq(WorldCasting._area(p), 1.0, "THE EMPRESS's area without her")
	assert_eq(WorldCasting._missiles(null), 0, "no wizard: no missiles")
	assert_eq(WorldCasting._area(null), 1.0, "no wizard: the plain area")
	for lv: int in range(1, STAR_LEVELS.size() + 1):
		_hold(p, Upgrades.STAR, lv)
		assert_eq(WorldCasting._missiles(p), STAR_LEVELS[lv - 1], "star %d" % lv)
	for lv: int in range(1, EMPRESS_LEVELS.size() + 1):
		_hold(p, Upgrades.EMPRESS, lv)
		assert_near(WorldCasting._area(p), EMPRESS_LEVELS[lv - 1], 0.000001, "empress %d" % lv)
	assert_eq(Upgrades.max_level(Upgrades.STAR), STAR_LEVELS.size())
	assert_eq(Upgrades.max_level(Upgrades.EMPRESS), EMPRESS_LEVELS.size())


func test_the_two_cards_are_dealt_like_any_arcana_and_complete_no_pair_yet() -> void:
	for idx: int in [Upgrades.STAR, Upgrades.EMPRESS]:
		assert_false(Upgrades.UNBUILT.has(idx), Upgrades.key(idx) + " still on the shelf")
		assert_true(Upgrades.available({Upgrades.W_ARCANE: 1}, idx, Upgrades.SLOTS_EARLY), Upgrades.key(idx))
		assert_true(Upgrades.take({Upgrades.W_ARCANE: 1}, idx), Upgrades.key(idx))
	# Their evolutions are still unbuilt: neither card completes a pair.
	assert_true(Upgrades.UNBUILT.has(Upgrades.E_LODESTAR) and Upgrades.UNBUILT.has(Upgrades.E_BLADES))
	assert_false(Upgrades.pairs_with({Upgrades.W_ARCANE: 5}, Upgrades.STAR), "THE STAR pairs with LODESTAR, unbuilt")
	assert_false(Upgrades.pairs_with({Upgrades.W_BLADES: 5}, Upgrades.EMPRESS), "THE EMPRESS pairs with DANSE MACABRE")
	# A wizard rolls them: both show up in a thousand hands.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := {}
	for _k: int in range(1000):
		for c: int in Upgrades.roll(rng, {Upgrades.W_ARCANE: 1}, 3, Upgrades.SLOTS_EARLY):
			seen[c] = true
	assert_true(seen.has(Upgrades.STAR), "THE STAR never rolled")
	assert_true(seen.has(Upgrades.EMPRESS), "THE EMPRESS never rolled")


# ------------------------------------------------------------------------------------------- THE STAR by cast kind --

func test_every_bolt_spell_sends_a_bolt_more_for_each_missile() -> void:
	for sp: int in BOLT_COUNTS:
		var want: Array = BOLT_COUNTS[sp]
		for m: int in range(3):
			for evo: int in [0, 1]:
				var w := _world()
				var p: World.Player = w.players[0]
				_hold(p, Upgrades.STAR, m)
				var lv := 1 if evo == 0 else Spells.MAX_LEVEL
				w.shots.clear()
				WorldCasting._cast(w, p, sp, lv, evo, Vector2.RIGHT)
				var n := int(want[m]) if evo == 0 else Spells.count(sp, lv, evo) + m
				assert_eq(w.shots.size(), n, "%s evo %d star %d" % [Spells.spell_name(sp), evo, m])


func test_a_fan_of_more_bolts_is_wider() -> void:
	var widths: Array[float] = []
	for m: int in range(3):
		var w := _world()
		var p: World.Player = w.players[0]
		_hold(p, Upgrades.STAR, m)
		WorldCasting._cast(w, p, World.SP_FROST, 1, 0, Vector2.RIGHT)
		var lo := INF
		var hi := -INF
		for s: World.Shot in w.shots:
			lo = minf(lo, s.vel.angle())
			hi = maxf(hi, s.vel.angle())
		widths.append(hi - lo)
	assert_true(widths[1] > widths[0] and widths[2] > widths[1], "the fan did not widen: %s" % str(widths))


func test_a_chain_jumps_once_more_for_each_missile() -> void:
	for evo: int in [0, 1]:
		for m: int in range(3):
			var w := _world()
			var p: World.Player = w.players[0]
			_hold(p, Upgrades.STAR, m)
			var foes := _block(w, p.pos + Vector2(0, -7), 24.0, 6, 6, 13.0)
			w._build_grid()
			var lv := 1 if evo == 0 else Spells.MAX_LEVEL
			WorldCasting._cast(w, p, World.SP_STORM, lv, evo, Vector2.RIGHT)
			var chains := int(Spells.evo_value(World.SP_STORM, "chains", evo, 1.0))
			var want := chains * (Spells.count(World.SP_STORM, lv, evo) + m)
			if evo == 0:
				assert_eq(want, [3, 4, 5][m], "the list's jumps")
			assert_eq(_hurt(foes), want, "chain evo %d star %d" % [evo, m])


## Five lone foes far enough apart that each is a cluster of its own, for circles of `radius` px or less.
func _clusters(w: World, at: Vector2, dist: float) -> Array:
	var out: Array = []
	for i: int in range(5):
		out.append(_orc(w, at + Vector2.from_angle(i * TAU / 5.0) * dist))
	return out


func test_runes_and_lights_set_a_circle_more_for_each_missile() -> void:
	# Rune circles: foes 70 px out, 82 px apart (more than the Seal's 32 x Spells.RUNE_SPACING).
	for evo: int in [0, 1]:
		for m: int in range(3):
			var w := _world()
			var p: World.Player = w.players[0]
			_hold(p, Upgrades.STAR, m)
			_clusters(w, p.pos, 70.0)
			w._build_grid()
			var lv := 1 if evo == 0 else Spells.MAX_LEVEL
			WorldCasting._cast(w, p, World.SP_RUNE, lv, evo, Vector2.RIGHT)
			assert_eq(w.runes.size(), Spells.count(World.SP_RUNE, lv, evo) + m, "runes evo %d star %d" % [evo, m])
			if evo == 0:
				assert_eq(w.runes.size(), [1, 2, 3][m])
	# Candle lights: foes 55 px out (within Spells.CANDLE_RANGE), 64 px apart (more than 32 x RUNE_SPACING).
	for evo: int in [0, 1]:
		for m: int in range(3):
			var w := _world()
			var p: World.Player = w.players[0]
			_hold(p, Upgrades.STAR, m)
			_clusters(w, p.pos, 55.0)
			w._build_grid()
			var lv := 1 if evo == 0 else Spells.MAX_LEVEL
			WorldCasting._cast(w, p, World.SP_CANDLE, lv, evo, Vector2.RIGHT)
			assert_eq(w.runes.size(), Spells.count(World.SP_CANDLE, lv, evo) + m, "lights evo %d star %d" % [evo, m])


## Orcs `d` px from the sweep's centre at each of `degrees` off the swing (to the right).
func _fan_of_foes(w: World, from: Vector2, d: float, degrees: Array) -> Array:
	var out: Array = []
	for deg: float in degrees:
		out.append(_orc(w, from + Vector2.from_angle(deg_to_rad(deg)) * d))
	return out


func test_a_sweep_sends_no_missile_and_its_arc_widens_by_half_for_each() -> void:
	var half := Spells.stat(World.SP_CLEAVE, "arc") * 0.5
	assert_near(Tuning.new().star_sweep_arc, 0.5, 0.000001, "the list's half again")
	# Foes 20 px out at 0, 62, 88 and 120 degrees: inside the plain half arc (50), one and a half (75), twice (100).
	var want: Array[int] = [1, 2, 3]
	for m: int in range(3):
		var w := _world()
		var p: World.Player = w.players[0]
		_hold(p, Upgrades.STAR, m)
		var from := p.pos + Vector2(0, -4)
		var foes := _fan_of_foes(w, from, 20.0, [0.0, 62.0, 88.0, 120.0])
		w._build_grid()
		w.take_events()
		WorldCasting._cast(w, p, World.SP_CLEAVE, 1, 0, Vector2.RIGHT)
		assert_eq(_hurt(foes), want[m], "sweep star %d" % m)
		var sweeps := _codes(w.take_events(), World.EV_SWEEP)
		assert_eq(sweeps.size(), 1)
		var sw: Vector3 = sweeps[0][3]
		assert_near(sw.x, 0.0, 0.0001, "the swing's angle")
		assert_near(sw.z, half * (1.0 + 0.5 * m), 0.0001, "the half arc the event carries")
		assert_near(sw.y, Spells.stat(World.SP_CLEAVE, "r"), 0.0001, "the reach the event carries")
		assert_eq(w.shots.size(), 0, "a sweep sent a missile")
	# Where it swings: a foe at 62 degrees is outside the plain arc along the aim, inside it with one missile.
	for m: int in range(2):
		var w := _world()
		var p: World.Player = w.players[0]
		_hold(p, Upgrades.STAR, m)
		var from := p.pos + Vector2(0, -4)
		_fan_of_foes(w, from, 20.0, [62.0])
		w._build_grid()
		var dir := WorldCastSweep._sweep_dir(w, p, World.SP_CLEAVE, Vector2.RIGHT)
		if m == 0:
			assert_near(dir.angle(), deg_to_rad(62.0), 0.01, "it turns to the foe outside the plain arc")
		else:
			assert_eq(dir, Vector2.RIGHT, "the wider arc swings along the aim")


## Each caster returns what it sent in the units of its count, which _cast compares with the spell's own count.
func test_each_caster_returns_what_it_sent() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	var tip := p.pos + Vector2(0, -7) + Vector2.RIGHT * WorldCasting.STAFF_REACH
	assert_eq(WorldCastBolts._cast_bolts(w, p, World.SP_FROST, 1, 0, Vector2.RIGHT, tip, 5, 1.0), 5, "bolts")
	assert_eq(WorldCastSweep._cast_sweep(w, p, World.SP_CLEAVE, 1, 0, Vector2.RIGHT, tip, 2, 1.0), 2, "a sweep")
	assert_eq(WorldCastChain._cast_chain(w, p, World.SP_STORM, 1, 0, Vector2.RIGHT, tip, 4, 1.0), 0, "a chain at nobody")
	assert_eq(WorldCastCircles._cast_rune(w, p, World.SP_RUNE, 1, 0, Vector2.RIGHT, tip, 3, 1.0), 1, "one rune ahead")
	assert_eq(WorldCastCircles._cast_candle(w, p, World.SP_CANDLE, 1, 0, Vector2.RIGHT, tip, 3, 1.0), 1, "one light ahead")
	# Two foes in the cone: a chain of 4 strikes both, and says 2.
	var foes := _block(w, p.pos + Vector2(0, -7), 30.0, 2, 1, 14.0)
	w._build_grid()
	assert_eq(WorldCastChain._cast_chain(w, p, World.SP_STORM, 1, 0, Vector2.RIGHT, tip, 4, 1.0), 2, "the foes struck")
	assert_eq(_hurt(foes), 2)
	# A crowd: TEMPEST's two chains of 4 strike eight foes, and the caster says the most one chain struck, 4.
	var cw := _world()
	var cp: World.Player = cw.players[0]
	var crowd := _block(cw, cp.pos + Vector2(0, -7), 30.0, 6, 6, 13.0)
	cw._build_grid()
	assert_eq(WorldCastChain._cast_chain(cw, cp, World.SP_STORM, Spells.MAX_LEVEL, 1, Vector2.RIGHT, tip, 4, 1.0), 4,
		"the most foes one chain struck")
	assert_eq(_hurt(crowd), 8, "two chains of four")
	var far := _world()
	var q: World.Player = far.players[0]
	_clusters(far, q.pos, 70.0)
	far._build_grid()
	assert_eq(WorldCastCircles._cast_rune(far, q, World.SP_RUNE, 1, 0, Vector2.RIGHT, tip, 3, 1.0), 3, "runes placed")
	assert_eq(far.runes.size(), 3)


# -------------------------------------------------------------------------------------- THE EMPRESS, every area --

## A FIREBALL shot of wizard 0 at `at`, already flying.
func _fireball(w: World, at: Vector2, evo: int = 0) -> World.Shot:
	return WorldCastBolts._shot(w, 0, World.SP_FIRE, evo, at, Vector2(200, 0), 1.0, 0)


func test_a_blast_and_its_reach_widen() -> void:
	var radius := Spells.stat(World.SP_FIRE, "blast")
	var reach := Spells.stat(World.SP_FIRE, "blast_reach")
	var bonus := Spells.stat(World.SP_FIRE, "blast_bonus")
	for lv: int in [0, 3]:
		var w := _world()
		var p: World.Player = w.players[0]
		_hold(p, Upgrades.EMPRESS, lv)
		var at := Vector2(300, 150)
		var edge := _orc(w, at)
		edge.pos = at + Vector2(radius + edge.r + JUST, 0)
		var near := _orc(w, at + Vector2(0, 20))
		w._build_grid()
		w.take_events()
		WorldCastBolts._explode(w, _fireball(w, at))
		var area := 1.3 if lv == 3 else 1.0
		if lv == 0:
			assert_eq(edge.hp, edge.maxhp, "a foe just outside the plain blast was hit")
		else:
			assert_true(edge.hp < edge.maxhp, "THE EMPRESS's blast missed the foe at its edge")
		# The reach the bonus fades over widens too: the same foe takes more.
		var want := 1.0 + bonus * (1.0 - near.pos.distance_to(at) / (reach * area))
		assert_near(near.maxhp - near.hp, want, 0.0001, "the reach (lv %d)" % lv)
		var ev: Array = _codes(w.take_events(), World.EV_EXPLODE)
		assert_eq(int(ev[0][3]), int(radius * area), "the radius the view draws")
		# THUNDERFIRE blasts with FIREBALL's radius (its zap then strikes too): widened alike.
		w.take_events()
		WorldCastBolts._explode(w, _fireball(w, at, 1))
		assert_eq(int(_codes(w.take_events(), World.EV_EXPLODE)[0][3]), int(radius * area), "THUNDERFIRE's radius")


func test_thunderfire_s_zap_reach_is_not_an_area() -> void:
	for lv: int in [0, 3]:
		var w := _world()
		var p: World.Player = w.players[0]
		_hold(p, Upgrades.EMPRESS, lv)
		var at := Vector2(300, 150)
		var far := _orc(w, at + Vector2(Spells.CHAIN_JUMP_RANGE + 5.0, 0))
		w._build_grid()
		WorldCastBolts._explode(w, _fireball(w, at, 1))
		assert_eq(far.hp, far.maxhp, "the zap jumped past its range (empress %d)" % lv)
		var near := _orc(w, at + Vector2(Spells.CHAIN_JUMP_RANGE - 5.0, 0))
		w._build_grid()
		WorldCastBolts._explode(w, _fireball(w, at, 1))
		assert_true(near.hp < near.maxhp, "the zap missed a foe in range (empress %d)" % lv)
	# Its later jumps neither: a first foe 50 px out (outside the blast), a second just past a jump beyond it.
	for lv: int in [0, 3]:
		var w := _world()
		_hold(w.players[0], Upgrades.EMPRESS, lv)
		var at := Vector2(300, 150)
		var first := _orc(w, at + Vector2(50, 0))
		var past := _orc(w, first.pos + Vector2(0, Spells.CHAIN_JUMP_RANGE + JUST))
		w._build_grid()
		WorldCastBolts._explode(w, _fireball(w, at, 1))
		assert_true(first.hp < first.maxhp, "the zap missed its first foe (empress %d)" % lv)
		assert_eq(past.hp, past.maxhp, "the zap's later jump went past its range (empress %d)" % lv)


## A chain's jumps and its first reach are no area (Contract 3: the list names none).
func test_the_empress_widens_neither_a_chain_s_jumps_nor_its_first_reach() -> void:
	for lv: int in [0, 3]:
		var w := _world()
		var p: World.Player = w.players[0]
		_hold(p, Upgrades.EMPRESS, lv)
		var tip := p.pos + Vector2(0, -7) + Vector2.RIGHT * WorldCasting.STAFF_REACH
		var first := _orc(w, tip + Vector2(20, 0))
		var past := _orc(w, first.pos + Vector2(Spells.CHAIN_JUMP_RANGE + JUST, 0))
		w._build_grid()
		WorldCasting._cast(w, p, World.SP_STORM, 1, 0, Vector2.RIGHT)
		assert_true(first.hp < first.maxhp, "the chain missed its first foe (empress %d)" % lv)
		assert_eq(past.hp, past.maxhp, "a jump went past CHAIN_JUMP_RANGE (empress %d)" % lv)
		# A lone foe just past the first reach, measured from the staff's base.
		var lone := _world()
		var q: World.Player = lone.players[0]
		_hold(q, Upgrades.EMPRESS, lv)
		var far := _orc(lone, q.pos + Vector2(0, -7) + Vector2.RIGHT * (Spells.CHAIN_FIRST_RANGE + JUST))
		lone._build_grid()
		WorldCasting._cast(lone, q, World.SP_STORM, 1, 0, Vector2.RIGHT)
		assert_eq(far.hp, far.maxhp, "a chain reached past CHAIN_FIRST_RANGE (empress %d)" % lv)


## JUSTICE's burst is no spell's area: THE EMPRESS leaves its radius alone.
func test_the_empress_does_not_widen_a_justice_burst() -> void:
	var w := _world()
	_hold(w.players[0], Upgrades.EMPRESS, 3)
	var at := Vector2(400, 300)
	var inside := _orc(w, at)
	inside.pos = at + Vector2(0, Upgrades.JUSTICE_RADIUS + inside.r - JUST)
	var past := _orc(w, at)
	past.pos = at + Vector2(Upgrades.JUSTICE_RADIUS + past.r + JUST, 0)
	w._build_grid()
	w.bursts.append([at, 5.0, 0])
	WorldCasting._update_bursts(w)
	assert_true(inside.hp < inside.maxhp, "the burst missed a foe inside its radius")
	assert_eq(past.hp, past.maxhp, "a JUSTICE burst reached past its radius with THE EMPRESS")


func test_a_frost_burst_widens() -> void:
	var radius := Spells.evo_value(World.SP_STAR, "burst", 1, 0.0)
	for lv: int in [0, 3]:
		var w := _world()
		var p: World.Player = w.players[0]
		_hold(p, Upgrades.EMPRESS, lv)
		var at := Vector2(300, 150)
		var center := _orc(w, at)
		var edge := _orc(w, at)
		edge.pos = at + Vector2(radius + edge.r + JUST, 0)
		w._build_grid()
		w.take_events()
		var s := WorldCastBolts._shot(w, 0, World.SP_STAR, 1, at, Vector2(175, 0), 3.0, 0)
		WorldCastBolts._frost_burst(w, s, center)
		if lv == 0:
			assert_eq(edge.hp, edge.maxhp, "a foe just outside the plain burst was hit")
		else:
			assert_true(edge.hp < edge.maxhp and edge.slow > 0.0, "THE EMPRESS's burst missed the foe at its edge")
		var ev: Array = _codes(w.take_events(), World.EV_FROST)
		assert_near(float(ev[0][3]), radius * (1.3 if lv == 3 else 1.0), 0.0001, "the radius the view draws")


func test_a_splinter_flies_further() -> void:
	for lv: int in [0, 3]:
		var w := _world()
		var p: World.Player = w.players[0]
		_hold(p, Upgrades.EMPRESS, lv)
		var at := Vector2(300, 250)
		var first := _orc(w, at)
		var spear := WorldCastBolts._shot(w, 0, World.SP_BONE, 1, at, Vector2(Spells.stat(World.SP_BONE, "speed"), 0), 5.0,
			Spells.PIERCE_ALL)
		# A foe whose hit point is 100 px up: past a plain splinter's flight (0.3 s at 275 px/s), inside 1.3 times it.
		var target := _orc(w, at)
		target.pos = at + Vector2(0, -100.0 + target.r * 0.8)
		w._build_grid()
		WorldCastBolts._shot_hit(w, spear, first)
		var splinters: Array = w.shots.filter(func(x: World.Shot) -> bool: return x.splinter)
		assert_eq(splinters.size(), int(Spells.evo_value(World.SP_BONE, "splinter", 1, 0.0)))
		for x: World.Shot in splinters:
			assert_near(x.life, Spells.SPLINTER_LIFE * (1.3 if lv == 3 else 1.0), 0.000001, "a splinter's flight")
		for _i: int in range(int(0.6 / DT)):
			w._build_grid()
			WorldCastBolts._update_shots(w, DT)
			w.shots = w.shots.filter(func(x: World.Shot) -> bool: return not x.dead)
		if lv == 0:
			assert_eq(target.hp, target.maxhp, "a plain splinter flew too far")
		else:
			assert_true(target.hp < target.maxhp, "THE EMPRESS's splinter fell short")


func _burn(w: World, seconds: float) -> void:
	for _i: int in range(int(seconds / DT)):
		w._build_grid()
		w._plist.assign(w.players.values())
		WorldCastCircles._update_runes(w, DT)


func test_a_rune_circle_and_a_light_widen_but_last_as_long() -> void:
	for sp: int in [World.SP_RUNE, World.SP_CANDLE]:
		for lv: int in [0, 3]:
			var w := _world(2)
			var p: World.Player = w.players[0]
			var ally: World.Player = w.players[1]
			_hold(p, Upgrades.EMPRESS, lv)
			w._build_grid()
			w.take_events()
			WorldCasting._cast(w, p, sp, 1, 0, Vector2.RIGHT) # nobody in range: one circle ahead along the aim
			assert_eq(w.runes.size(), 1)
			var c: World.Rune = w.runes[0]
			var plain := Spells.level_value(sp, "r", 1, 0)
			var area := 1.3 if lv == 3 else 1.0
			assert_near(c.r, plain * area, 0.0001, "%s radius" % Spells.spell_name(sp))
			assert_near(c.life, Spells.level_value(sp, "life", 1, 0), 0.000001, "the duration is never scaled")
			var ev: Array = _codes(w.take_events(), World.EV_RUNE)
			assert_near(float(ev[0][3]), c.r, 0.0001, "the radius the view draws")
			var edge := _orc(w, c.pos)
			edge.pos = c.pos + Vector2(plain + edge.r * 0.5 + JUST, 0)
			ally.pos = c.pos + Vector2(0, plain + JUST)
			ally.vigil = 0.0
			_burn(w, 1.0)
			if lv == 0:
				assert_eq(edge.hp, edge.maxhp, "%s: a foe just outside the plain circle was burnt" % Spells.spell_name(sp))
			else:
				assert_true(edge.hp < edge.maxhp, "%s: the wider circle missed the foe at its edge" % Spells.spell_name(sp))
			if sp == World.SP_CANDLE:
				assert_eq(ally.vigil > 0.0, lv == 3, "the light's haste reaches as far as its radius")


func test_a_sweep_reaches_further() -> void:
	var reach := Spells.stat(World.SP_CLEAVE, "r")
	for lv: int in [0, 3]:
		var w := _world()
		var p: World.Player = w.players[0]
		_hold(p, Upgrades.EMPRESS, lv)
		var from := p.pos + Vector2(0, -4)
		var edge := _orc(w, from)
		edge.pos = from + Vector2(reach + edge.r + JUST, 0)
		w._build_grid()
		var dir := WorldCastSweep._sweep_dir(w, p, World.SP_CLEAVE, Vector2.ZERO)
		assert_eq(dir != Vector2.ZERO, lv == 3, "where a sweep waits follows its reach")
		w.take_events()
		WorldCasting._cast(w, p, World.SP_CLEAVE, 1, 0, Vector2.RIGHT)
		assert_eq(edge.hp < edge.maxhp, lv == 3, "a sweep's reach with THE EMPRESS at %d" % lv)
		var sw: Vector3 = _codes(w.take_events(), World.EV_SWEEP)[0][3]
		assert_near(sw.y, reach * (1.3 if lv == 3 else 1.0), 0.0001, "the reach the view draws")


# ------------------------------------------------------------------------------------- what is drawn follows it --

## The arena draws a sweep, a blast and a frost burst at the sizes their events carry (the World's), never at sizes
## of its own; the arena is built bare, as test_input_pause builds it.
func test_the_arena_draws_the_sizes_the_world_used() -> void:
	var a := Arena.new()
	a.fx = Fx.new()
	# A CLEAVE swung with THE EMPRESS III (its reach 1.3 times) and THE STAR II (its half arc twice as wide).
	var reach := Spells.stat(World.SP_CLEAVE, "r") * 1.3
	var half := Spells.stat(World.SP_CLEAVE, "arc") * 0.5 * 2.0
	ArenaEvents._handle_events(a, [[World.EV_SWEEP, 100.0, 100.0, Vector3(0.5, reach, half), 0]])
	assert_eq(a.fx.swings.size(), 1)
	var swing: Array = a.fx.swings[0] # [pos, radius, middle angle, half width, ...]
	assert_near(float(swing[1]), reach, 0.0001, "the reach drawn")
	assert_near(float(swing[2]), 0.5, 0.0001, "the angle drawn")
	assert_near(float(swing[3]), half, 0.0001, "the half arc drawn")
	# A plain FIREBALL's blast and one THE EMPRESS III widened: the ring reaches past each radius, and the scorch is
	# BLAST_SCORCH under the plain one and as much wider under the wide one.
	var plain := Spells.stat(World.SP_FIRE, "blast")
	for r: int in [int(plain), int(plain * 1.3)]:
		var before := a.fx.rings.size()
		ArenaEvents._handle_events(a, [[World.EV_EXPLODE, 200.0, 100.0, r, 0]])
		var widest := 0.0
		for ring: Array in a.fx.rings.slice(before):
			widest = maxf(widest, float(ring[2]))
		assert_true(widest >= float(r), "the ring of a %d px blast reaches %.1f px" % [r, widest])
		var scorch := float(a.decals[a.decals.size() - 1][2])
		assert_near(scorch, ArenaEvents.BLAST_SCORCH * r / plain, 0.0001, "the scorch of a %d px blast" % r)
		if r == int(plain):
			assert_near(scorch, ArenaEvents.BLAST_SCORCH, 0.0001, "a plain blast's scorch")
	# A COMET RAIN frost burst widened to 1.3 times: its ring is the burst's radius.
	var frost := Spells.evo_value(World.SP_STAR, "burst", 1, 0.0) * 1.3
	var at := a.fx.rings.size()
	ArenaEvents._handle_events(a, [[World.EV_FROST, 300.0, 100.0, frost, 0]])
	assert_eq(a.fx.rings.size(), at + 1)
	assert_near(float(a.fx.rings[at][2]), frost, 0.0001, "the frost ring")
	# A bare arena never ran _ready, so the node it makes at its birth is nobody's child yet: free it too.
	a.fx.free()
	a.root.free()
	a.free()
	# The events played their sounds on the Sfx pool: stop them, or a test process that ends at once leaves with a
	# playback alive (a leak warning at exit).
	for pl: AudioStreamPlayer in Sfx._players:
		pl.stop()


# ------------------------------------------------------------------------------------------------ the damage hooks --

func test_dealt_mul_is_the_product_of_its_parts() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	assert_eq(WorldEnemies._dealt_mul(w, p), 1.0, "a plain wizard")
	assert_eq(WorldEnemies._dealt_mul(w, null), 1.0, "no wizard")
	p.upgrades[Upgrades.POWER] = 3
	p.upgrades[Upgrades.M_WANDS] = 2
	p.armor[Loot.ST_MIGHT] = 0.1
	w.meta_damage = 0.05
	p.fury = 0.25
	p.hp = Races.FURY_HEARTS
	var strength := float(Upgrades.CATALOG[Upgrades.POWER][Upgrades.C_VALUES][2])
	var wands := 1.0 + 2.0 * float(Upgrades.CATALOG[Upgrades.M_WANDS][Upgrades.C_VALUES][0])
	assert_near(strength, 1.45, 0.000001)
	var want := strength * wands * (1.0 + 0.1 + 0.05 + 0.25)
	assert_near(WorldEnemies._dealt_mul(w, p), want, 0.000001, "STRENGTH 3, WANDS, the staff, the shop and fury")
	p.hp = Races.FURY_HEARTS + 1
	assert_near(WorldEnemies._dealt_mul(w, p), strength * wands * (1.0 + 0.1 + 0.05), 0.000001, "no fury above its hearts")
	p.hp = Races.FURY_HEARTS
	p.ai = true
	assert_near(WorldEnemies._dealt_mul(w, p), want * w.tune.apprentice_damage, 0.000001, "an apprentice's share")
	# _damage_enemy multiplies by both hooks.
	var e := _orc(w, Vector2(500, 300))
	assert_eq(WorldEnemies._taken_mul(w, e), 1.0, "a foe takes damage as it is today")
	w._damage_enemy(e, 2.0, 0, Vector2.ZERO)
	assert_near(e.maxhp - e.hp, 2.0 * want * w.tune.apprentice_damage, 0.0001)


# ---------------------------------------------------------------------------------------------------- the credits --

func test_the_magician_is_credited_at_a_cast_on_the_shorter_cooldown() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	p.upgrades[Upgrades.W_FIRE] = 1 # two spells: two casts
	_orc(w, p.pos + Vector2(60, 0))
	w._build_grid()
	WorldCasting._auto_cast(w, p, DT, Vector2.ZERO)
	assert_eq(w.record.used("quick"), 0, "credited without the card")
	p.cds.fill(0.0)
	p.upgrades[Upgrades.QUICK] = 1
	WorldCasting._auto_cast(w, p, DT, Vector2.ZERO)
	assert_eq(w.record.used_by(0, "quick"), 2, "one credit a cast")
	WorldCasting._auto_cast(w, p, DT, Vector2.ZERO)
	assert_eq(w.record.used("quick"), 2, "credited while nothing was cast")
	# A cooldown the floor holds already is no shorter for the card.
	p.cds.fill(0.0)
	p.armor[Loot.ST_FOCUS] = 0.9
	WorldCasting._auto_cast(w, p, DT, Vector2.ZERO)
	assert_eq(w.record.used("quick"), 2, "credited at the cast floor")


func test_the_lovers_are_credited_at_a_cast_near_an_ally() -> void:
	var w := _world(2)
	var p: World.Player = w.players[0]
	var ally: World.Player = w.players[1]
	p.upgrades[Upgrades.W_FIRE] = 1 # two spells: two casts
	_orc(w, p.pos + Vector2(60, 0))
	w._build_grid()
	ally.pos = p.pos + Vector2(0, Upgrades.LOVERS_RANGE - JUST)
	WorldCasting._auto_cast(w, p, DT, Vector2.ZERO)
	assert_eq(w.record.used("lovers"), 0, "credited without the card")
	p.upgrades[Upgrades.LOVERS] = 1
	p.cds.fill(0.0)
	WorldCasting._auto_cast(w, p, DT, Vector2.ZERO)
	assert_eq(w.record.used_by(0, "lovers"), 2, "one credit a cast with an ally near")
	WorldCasting._auto_cast(w, p, DT, Vector2.ZERO)
	assert_eq(w.record.used("lovers"), 2, "credited while nothing was cast")
	p.cds.fill(0.0)
	ally.pos = p.pos + Vector2(0, Upgrades.LOVERS_RANGE + JUST)
	WorldCasting._auto_cast(w, p, DT, Vector2.ZERO)
	assert_eq(w.record.used("lovers"), 2, "credited alone")
	p.cds.fill(0.0)
	ally.pos = p.pos + Vector2(0, 10)
	ally.down = true
	WorldCasting._auto_cast(w, p, DT, Vector2.ZERO)
	assert_eq(w.record.used("lovers"), 2, "a fallen ally counted")


func test_strength_is_credited_at_a_kill_never_at_a_hit() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	var e := _orc(w, Vector2(500, 300))
	w._damage_enemy(e, 1e7, 0, Vector2.ZERO)
	assert_true(e.dead)
	assert_eq(w.record.used("power"), 0, "credited without the card")
	p.upgrades[Upgrades.POWER] = 1
	var tough := _orc(w, Vector2(500, 300))
	w._damage_enemy(tough, 1.0, 0, Vector2.ZERO)
	assert_eq(w.record.used("power"), 0, "credited at a hit")
	var weak := _orc(w, Vector2(500, 300))
	w._damage_enemy(weak, 1e7, 0, Vector2.ZERO)
	assert_eq(w.record.used_by(0, "power"), 1, "her kill")


## A blast that hits twenty foes and kills none credits nothing, whatever she holds.
func test_no_credit_is_called_for_a_hit() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	for idx: int in [Upgrades.POWER, Upgrades.STAR, Upgrades.EMPRESS, Upgrades.JUSTICE, Upgrades.QUICK, Upgrades.SWIFT,
			Upgrades.MAGNET, Upgrades.WISDOM, Upgrades.REGEN, Upgrades.LOVERS]:
		p.upgrades[idx] = Upgrades.max_level(idx)
	var at := Vector2(300, 150)
	var foes: Array = []
	for i: int in range(20):
		foes.append(_orc(w, at + Vector2.from_angle(i * TAU / 20.0) * float(4 + i)))
	w._build_grid()
	WorldCastBolts._explode(w, _fireball(w, at))
	assert_eq(_hurt(foes), 20, "the blast missed")
	assert_true(w.record.uses.is_empty(), "a hit credited %s" % str(w.record.uses))


func test_justice_is_credited_at_a_burst() -> void:
	var w := _world()
	for i: int in range(50):
		w._damage_enemy(_orc(w, Vector2(400, 300)), 1e7, 0, Vector2.ZERO)
	assert_true(w.bursts.is_empty())
	WorldCasting._update_bursts(w)
	assert_eq(w.record.used("justice"), 0, "credited without the card")
	w.players[0].upgrades[Upgrades.JUSTICE] = 3
	var tries := 0
	while w.bursts.is_empty() and tries < 300:
		w._damage_enemy(_orc(w, Vector2(400, 300)), 1e7, 0, Vector2.ZERO)
		tries += 1
	assert_eq(w.record.used("justice"), 0, "credited at the kill, before the burst")
	var n := w.bursts.size()
	assert_true(n > 0, "no burst in %d kills" % tries)
	w._build_grid()
	WorldCasting._update_bursts(w)
	assert_eq(w.record.used_by(0, "justice"), n, "one credit a burst")


## Steps the World `seconds` with seat `slot` walking along `move` (the other seats stand still).
func _walk(w: World, seconds: float, move: Vector2, slot: int = 0) -> void:
	for _i: int in range(int(seconds / DT)):
		for p: World.Player in w.players.values():
			p.invuln = 999.0
		w.step(DT, {slot: PackedFloat32Array([move.x, move.y, 0.0, 0.0, 0.0, 0.0])})


func test_the_chariot_is_credited_each_second_she_moves() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	_walk(w, 2.5, Vector2(0, 0.5))
	assert_eq(w.record.used("swift"), 0, "credited without the card")
	p.upgrades[Upgrades.SWIFT] = 1
	_walk(w, 2.0, Vector2.ZERO)
	assert_eq(w.record.used("swift"), 0, "credited standing still")
	var t0 := floori(w.time)
	_walk(w, 3.0, Vector2(0, -0.5))
	assert_eq(w.record.used_by(0, "swift"), floori(w.time) - t0, "one credit a game second")


## A second she walked in counts even when she stands still at its turn (`Player.swift_moved` holds it).
func test_the_chariot_counts_a_second_she_moved_in_but_stood_at_its_turn() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	p.upgrades[Upgrades.SWIFT] = 1
	var walk := PackedFloat32Array([0.0, 0.5, 0.0, 0.0, 0.0, 0.0])
	var still := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var moved_steps := 0
	var turns := 0
	for _i: int in range(180):
		w.time += DT
		var turn := floori(w.time) > floori(w.time - DT)
		if turn:
			turns += 1
		else:
			moved_steps += 1
		WorldPlayers._update_player(w, p, DT, still if turn else walk)
		p.pos = Vector2(300, 240)
	assert_eq(moved_steps, 178)
	assert_eq(w.record.used_by(0, "swift"), turns, "she moved in %d of 180 steps, %d seconds turned" % [moved_steps, turns])


func test_temperance_is_credited_at_a_heart_it_gives_back() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	var every := float(Upgrades.CATALOG[Upgrades.REGEN][Upgrades.C_VALUES][2])
	p.hp = p.max_hp - 2
	for _i: int in range(int((every + 1.0) / DT)):
		WorldPlayers._update_player(w, p, DT, PackedFloat32Array())
	assert_eq(w.record.used("regen"), 0, "credited without the card")
	p.upgrades[Upgrades.REGEN] = 3
	var hp := p.hp
	for _i: int in range(int((every + 1.0) / DT)):
		WorldPlayers._update_player(w, p, DT, PackedFloat32Array())
	assert_eq(p.hp, hp + 1)
	assert_eq(w.record.used_by(0, "regen"), 1, "a heart back")
	for _i: int in range(int((every * 2.0 + 1.0) / DT)):
		WorldPlayers._update_player(w, p, DT, PackedFloat32Array())
	assert_eq(p.hp, p.max_hp)
	assert_eq(w.record.used("regen"), 2, "credited at full hearts")


## Plays the floor's pickups until gem `k` is taken or `seconds` pass; true when it was taken.
func _pull(w: World, k: World.Pickup, seconds: float) -> bool:
	for _i: int in range(int(seconds / DT)):
		WorldDrops._update_pickups(w, DT)
		if not w.pickups.has(k):
			return true
	return false


func _gem(w: World, at: Vector2, vel: Vector2 = Vector2.ZERO) -> World.Pickup:
	WorldDrops._drop_xp(w, at, vel, 1)
	return w.pickups[w.pickups.size() - 1]


func test_the_moon_is_credited_for_a_gem_from_beyond_the_plain_reach() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	var plain := w.tune.xp_magnet_radius
	var beyond := plain + 10.0
	var k := _gem(w, p.pos + Vector2(beyond, 0))
	assert_false(_pull(w, k, 1.0), "a plain magnet pulled a gem beyond its reach")
	assert_eq(w.record.used("magnet"), 0, "credited without the card")
	p.upgrades[Upgrades.MAGNET] = 1
	assert_true(_pull(w, k, 2.0), "THE MOON did not pull the gem")
	assert_eq(w.record.used_by(0, "magnet"), 1, "one credit for the gem")
	# A gem that still drifts from its kill when she pulls it counts too, once.
	var drift := _gem(w, p.pos + Vector2(0, beyond), Vector2(25, 0))
	assert_true(_pull(w, drift, 2.0))
	assert_eq(w.record.used("magnet"), 2, "a drifting gem")
	# A gem inside the plain reach owes her nothing.
	var close := _gem(w, p.pos + Vector2(-(plain - 10.0), 0))
	assert_true(_pull(w, close, 2.0))
	assert_eq(w.record.used("magnet"), 2, "credited a gem inside the plain reach")
	# Nor does one during a lull, when every magnet reaches the whole floor.
	w.lull_left = 5.0
	var lull := _gem(w, p.pos + Vector2(0, -120))
	assert_true(_pull(w, lull, 2.0))
	assert_eq(w.record.used("magnet"), 2, "credited a gem in a lull")


## A gem THE MOON began to pull for A that B takes on its way never came to A (`Pickup.moon`, credited at `_collect`).
func test_the_moon_is_not_credited_for_a_gem_another_took() -> void:
	var w := _world(2)
	var a: World.Player = w.players[0]
	var b: World.Player = w.players[1]
	a.upgrades[Upgrades.MAGNET] = 1
	var plain := w.tune.xp_magnet_radius
	var gem_at := Vector2(200, 200)
	a.pos = gem_at + Vector2(plain + 20.0, 0) # beyond her plain reach, inside THE MOON's
	b.pos = gem_at + Vector2(plain + 4.0, 0) # on the gem's way, beyond B's plain reach
	var k := _gem(w, gem_at)
	assert_true(_pull(w, k, 2.0), "the gem was taken")
	assert_eq(w.record.used_by(0, "magnet"), 0, "A was credited for a gem B took")


func test_the_hermit_is_credited_for_a_gem_whose_xp_it_raised() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	var k := World.Pickup.new()
	k.kind = World.PK_XP
	k.value = 4
	WorldDrops._collect(w, p, k)
	assert_eq(w.record.used("wisdom"), 0, "credited without the card")
	p.upgrades[Upgrades.WISDOM] = 1
	var xp := w.party_xp
	WorldDrops._collect(w, p, k) # 4 x 1.15 = 4.6: 5
	assert_eq(w.record.used_by(0, "wisdom"), 1, "a gem it raised")
	assert_true(w.party_xp > xp + 4 or w.party_level > 1)
	k.value = 1
	WorldDrops._collect(w, p, k) # 1 x 1.15 rounds to 1: nothing raised
	assert_eq(w.record.used("wisdom"), 1, "credited a gem it did not raise")
	p.upgrades[Upgrades.WISDOM] = 3
	WorldDrops._collect(w, p, k) # 1 x 1.5 rounds to 2
	assert_eq(w.record.used("wisdom"), 2)


func test_the_tower_and_judgement_are_credited_at_the_pick_by_pick_and_by_give() -> void:
	for by_give: bool in [false, true]:
		var w := _world()
		var p: World.Player = w.players[0]
		var bombs := p.bombs
		var lives := p.lives
		for idx: int in [Upgrades.M_SWORDS, Upgrades.W_FIRE]:
			if by_give:
				WorldGrants.give(w, p, idx)
			else:
				WorldLevels._pick(w, p, idx)
		assert_eq(w.record.used("nova") + w.record.used("life"), 0, "SWORDS or another card credited them")
		for idx: int in [Upgrades.NOVA, Upgrades.LIFE]:
			assert_true(by_give or Upgrades.available(p.upgrades, idx, w.slot_cap(), p.banned), Upgrades.key(idx))
			if by_give:
				WorldGrants.give(w, p, idx)
			else:
				WorldLevels._pick(w, p, idx)
		assert_eq(p.bombs, bombs + 2, "SWORDS and THE TOWER")
		assert_eq(p.lives, lives + 1)
		assert_eq(w.record.used_by(0, "nova"), 1, "THE TOWER's charge (give %s)" % str(by_give))
		assert_eq(w.record.used_by(0, "life"), 1, "JUDGEMENT's life (give %s)" % str(by_give))


func test_the_star_is_credited_at_a_cast_that_sent_more() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	WorldCasting._cast(w, p, World.SP_ARCANE, 1, 0, Vector2.RIGHT)
	assert_eq(w.record.used("star"), 0, "credited without the card")
	p.upgrades[Upgrades.STAR] = 1
	WorldCasting._cast(w, p, World.SP_ARCANE, 1, 0, Vector2.RIGHT)
	assert_eq(w.record.used_by(0, "star"), 1, "a bolt more")
	# A chain with one foe in reach and a rune circle with none send nothing more for her.
	var lone := _orc(w, p.pos + Vector2(40, -7))
	w._build_grid()
	WorldCasting._cast(w, p, World.SP_STORM, 1, 0, Vector2.RIGHT)
	assert_true(lone.hp < lone.maxhp)
	var far := World.new([0], 11, Tuning.new())
	far.players[0].upgrades[Upgrades.STAR] = 2
	far._build_grid()
	WorldCasting._cast(far, far.players[0], World.SP_RUNE, 1, 0, Vector2.RIGHT)
	assert_eq(far.runes.size(), 1)
	assert_eq(w.record.used("star") + far.record.used("star"), 1, "credited a cast that sent no more")
	# A crowd: the chain jumps further; a sweep's arc is wider.
	_block(w, p.pos + Vector2(0, -7), 60.0, 4, 4, 13.0)
	w._build_grid()
	WorldCasting._cast(w, p, World.SP_STORM, 1, 0, Vector2.RIGHT)
	assert_eq(w.record.used("star"), 2, "a jump more")
	WorldCasting._cast(w, p, World.SP_CLEAVE, 1, 0, Vector2.RIGHT)
	assert_eq(w.record.used("star"), 3, "a wider arc")


func test_the_empress_is_credited_at_a_cast_whose_area_she_widened() -> void:
	var w := _world()
	var p: World.Player = w.players[0]
	WorldCasting._cast(w, p, World.SP_FIRE, 1, 0, Vector2.RIGHT)
	assert_eq(w.record.used("empress"), 0, "credited without the card")
	p.upgrades[Upgrades.EMPRESS] = 1
	# [spell, evolution, has an area]
	var rows: Array = [[World.SP_FIRE, 0, true], [World.SP_FIRE, 1, true], [World.SP_STAR, 1, true],
		[World.SP_BONE, 1, true], [World.SP_RUNE, 0, true], [World.SP_CANDLE, 0, true], [World.SP_CLEAVE, 0, true],
		[World.SP_ARCANE, 0, false], [World.SP_FROST, 0, false], [World.SP_STORM, 0, false], [World.SP_STAR, 0, false],
		[World.SP_BONE, 0, false], [World.SP_ARCANE, 1, false]]
	for row: Array in rows:
		var was := w.record.used_by(0, "empress")
		WorldCasting._cast(w, p, int(row[0]), Spells.MAX_LEVEL, int(row[1]), Vector2.RIGHT)
		assert_eq(w.record.used_by(0, "empress") - was, 1 if bool(row[2]) else 0,
			"%s evo %d" % [Spells.spell_name(int(row[0])), int(row[1])])


## `key` was credited `n` times to seat 1, whose card acted, and never to seat 0.
func _credited_to_seat_1(w: World, key: String, n: int = 1) -> void:
	assert_eq(w.record.used_by(1, key), n, key + ": the seat whose card acted")
	assert_eq(w.record.used_by(0, key), 0, key + ": credited to seat 0")


## Every credit lands on the seat whose card acted (`w.record.use(key, p.slot)`): seat 1 holds the card and acts,
## seat 0 stands by. The other credit tests play seat 0, where a credit sent to seat 0 by mistake would pass.
func test_each_credit_goes_to_the_seat_whose_card_acted() -> void:
	# At a cast: THE MAGICIAN, THE LOVERS (seat 0 near her), THE STAR and THE EMPRESS.
	var w := _world(2)
	var q: World.Player = w.players[1]
	w.players[0].pos = q.pos + Vector2(0, 10)
	for idx: int in [Upgrades.QUICK, Upgrades.LOVERS]:
		q.upgrades[idx] = 1
	_orc(w, q.pos + Vector2(60, 0))
	w._build_grid()
	WorldCasting._auto_cast(w, q, DT, Vector2.ZERO) # her one spell: one cast
	_credited_to_seat_1(w, "quick")
	_credited_to_seat_1(w, "lovers")
	q.upgrades[Upgrades.STAR] = 1
	q.upgrades[Upgrades.EMPRESS] = 1
	WorldCasting._cast(w, q, World.SP_FIRE, 1, 0, Vector2.RIGHT)
	_credited_to_seat_1(w, "star")
	_credited_to_seat_1(w, "empress")
	# At a kill and at a burst: STRENGTH and JUSTICE.
	w = _world(2)
	w.players[1].upgrades[Upgrades.POWER] = 1
	w.players[1].upgrades[Upgrades.JUSTICE] = 3
	var kills := 0
	while w.bursts.is_empty() and kills < 300:
		w._damage_enemy(_orc(w, Vector2(400, 300)), 1e7, 1, Vector2.ZERO)
		kills += 1
	_credited_to_seat_1(w, "power", kills)
	var n := w.bursts.size()
	assert_true(n > 0, "no burst in %d kills" % kills)
	w._build_grid()
	WorldCasting._update_bursts(w)
	_credited_to_seat_1(w, "justice", n)
	# At a gem: THE MOON pulls one from beyond her plain reach, THE HERMIT raises one.
	w = _world(2)
	q = w.players[1]
	q.upgrades[Upgrades.MAGNET] = 1
	q.upgrades[Upgrades.WISDOM] = 1
	assert_true(_pull(w, _gem(w, q.pos + Vector2(w.tune.xp_magnet_radius + 10.0, 0)), 2.0), "THE MOON did not pull")
	_credited_to_seat_1(w, "magnet")
	var k := World.Pickup.new()
	k.kind = World.PK_XP
	k.value = 4
	WorldDrops._collect(w, q, k) # 4 x 1.15: 5 (the pulled gem was 1 XP: 1 x 1.15 raised nothing)
	_credited_to_seat_1(w, "wisdom")
	# Each game second she walks: THE CHARIOT; a heart back: TEMPERANCE.
	w = _world(2)
	q = w.players[1]
	q.upgrades[Upgrades.SWIFT] = 1
	var t0 := floori(w.time)
	_walk(w, 2.5, Vector2(0, -0.5), 1)
	_credited_to_seat_1(w, "swift", floori(w.time) - t0)
	w = _world(2)
	q = w.players[1]
	q.upgrades[Upgrades.REGEN] = 3
	q.hp = q.max_hp - 2
	for _i: int in range(int((float(Upgrades.CATALOG[Upgrades.REGEN][Upgrades.C_VALUES][2]) + 1.0) / DT)):
		WorldPlayers._update_player(w, q, DT, PackedFloat32Array())
	_credited_to_seat_1(w, "regen")
	# At the pick, by a pick and by a give: THE TOWER and JUDGEMENT.
	for by_give: bool in [false, true]:
		w = _world(2)
		q = w.players[1]
		for idx: int in [Upgrades.NOVA, Upgrades.LIFE]:
			if by_give:
				WorldGrants.give(w, q, idx)
			else:
				WorldLevels._pick(w, q, idx)
		_credited_to_seat_1(w, "nova")
		_credited_to_seat_1(w, "life")


# ------------------------------------------------------------------------------------------------------- the bots --

func test_the_bots_know_the_two_new_cards() -> void:
	var taste: Dictionary = SmashBot.PASSIVE_TASTE
	assert_true(taste.has("star") and taste.has("empress"))
	for k: String in ["star", "empress"]:
		assert_true(float(taste[k]) < float(taste["quick"]), "%s under THE MAGICIAN" % k)
	assert_true(float(taste["star"]) > float(taste["life"]), "THE STAR over a lone arcana")
	assert_true(float(taste["star"]) > float(taste["empress"]), "THE STAR first: she adds more in a crowd")
	var lv := {Upgrades.W_ARCANE: 4}
	for s: int in range(1, 30):
		# The novice takes the card that completes a pair (THE MAGICIAN for ASTRAL LANCE) over one that completes none.
		assert_eq(SmashBot.new(s, SmashBot.NOVICE).pick_card([Upgrades.STAR, Upgrades.QUICK], lv), 1, "novice seed %d" % s)
		assert_eq(SmashBot.new(s, SmashBot.NOVICE).pick_card([Upgrades.EMPRESS, Upgrades.QUICK], lv), 1, "novice seed %d" % s)
		# The casual: THE STAR before THE EMPRESS, STRENGTH and THE MAGICIAN before both.
		assert_eq(SmashBot.new(s, SmashBot.CASUAL).pick_card([Upgrades.EMPRESS, Upgrades.STAR], lv), 1, "casual seed %d" % s)
		assert_eq(SmashBot.new(s, SmashBot.CASUAL).pick_card([Upgrades.STAR, Upgrades.POWER], lv), 1, "casual seed %d" % s)
		assert_eq(SmashBot.new(s, SmashBot.CASUAL).pick_card([Upgrades.STAR, Upgrades.QUICK], lv), 1, "casual seed %d" % s)
	# The veteran plans for ASTRAL LANCE: THE MAGICIAN first; with no plan in the hand, by taste.
	var vet := SmashBot.new(1, SmashBot.VETERAN)
	assert_eq(vet.pick_card([Upgrades.STAR, Upgrades.EMPRESS, Upgrades.QUICK], lv), 2, "the plan first")
	assert_eq(vet.pick_card([Upgrades.EMPRESS, Upgrades.STAR], lv), 1)
	assert_true(vet._plan_target(lv) == Upgrades.E_ARCANE, "the veteran plans ASTRAL LANCE")
