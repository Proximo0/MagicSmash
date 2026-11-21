class_name BossLich
extends RefCounted
## The Lich (a visit past the act bosses) and the Archlich (15:00, the Lich made final): today's calm set, and the
## enraged set under Bosses.phase 1. The Archlich has three phases (Bosses.phase): LICH LORD, the calm set; at
## ARCH_ASCEND, THE ASCENSION (a turn of ASCEND_TURN s: the field clears, the wizards heal ASCEND_HEAL) and
## ASCENDANT, the enraged set with COMETFALL every third attack; at ARCH_PAGE, THE NINTH PAGE (a PAGE_TURN s turn):
## as ASCENDANT plus a NAME every fourth attack (spelled in the header like the Ghost Writer's) and LAST CANDLE
## every CANDLE_EVERY s. Archlich memory: Enemy.enter_dir.y the turns made, .x the attacks started; boss_meter
## the seconds to the next LAST CANDLE. Static helpers; the first argument is the World.

## Its attacks as [state, warn s, hazard kind, r]. The Lich's own are enemy shots and minions; the Archlich's
## phases add these rows.
const ATTACKS: Array = [
	[COMETFALL, 1.4, Hazards.BLAST, 30.0],
	[COMETFALL, 0.67, Hazards.FIRE, 22.0], # what a comet leaves (laid with none: add_hazard raises it)
	[NAME, 4 * 0.32 + 0.3, Hazards.BLAST, 30.0],
	[0, 3.5, Hazards.SAFE, 40.0], # LAST CANDLE, alongside any attack
]
## The Archlich's own steps, after the Lich's 0..5.
const COMETFALL := 6
const NAME := 7
const ASCEND_TURN := 3.0
const ASCEND_HEAL := 2
const PAGE_TURN := 2.5
const COMET_EVERY := 3
const NAME_EVERY := 4
const COMETS := 3
const COMET_R := 30.0
const COMET_WARN := 1.4
const COMET_SPREAD := 60.0 # the comet that is not aimed lands within this of the party's middle
const CANDLE_EVERY := 30.0
const CANDLE_R := 40.0
const CANDLE_WARN := 3.5
const CANDLE_HOT := 0.2
const HOT_BLAST := 0.15


static func think(w: World, e: World.Enemy, dt: float, tgt: World.Player, dirv: Vector2, dist: float) -> Vector2:
	var ph := Bosses.phase(e.type, e.hp / e.maxhp, e.final)
	if e.final and ph > int(e.enter_dir.y):
		_arch_turn(w, e, int(e.enter_dir.y) + 1) # one phase a turn: a hit past both lines still ascends first
		return Vector2.ZERO
	var rage := ph >= 1
	if e.final and ph >= 2:
		w.boss_meter -= dt
		if w.boss_meter <= 0.0:
			w.boss_meter = CANDLE_EVERY
			var at := Bosses.candle_spot(w, e.pos)
			if at != Vector2.INF: # skipped when no spot is within reach of every wizard
				w.add_hazard(Hazards.SAFE, at, at, CANDLE_R, CANDLE_WARN, CANDLE_HOT, -1, e.id)
	var desired := Vector2.ZERO
	# Drift between waypoints in the upper half of the arena.
	if e.dir == Vector2.ZERO or e.pos.distance_to(e.dir) < 8.0:
		e.dir = Vector2(w.rng.randf_range(G.ARENA.position.x + 60, G.ARENA.end.x - 60),
			w.rng.randf_range(G.ARENA.position.y + 40, G.ARENA.get_center().y + 30))
	desired = (e.dir - e.pos).normalized() * e.spd * (1.5 if rage else 1.0)
	e.timer -= dt
	e.timer2 -= dt
	match e.state:
		0: # idle drift, then choose an attack
			if e.timer <= 0.0:
				var choices := [1, 2, 3, 4, 1, 2]
				if rage:
					choices.append(5)
				e.state = choices[w.rng.randi() % choices.size()]
				e.timer2 = 0.0
				e.count = 0.0
				e.timer = 2.4 if e.state == 3 else 0.6
				if e.final:
					e.enter_dir.x += 1.0
					var n := int(e.enter_dir.x)
					if ph >= 2 and n % NAME_EVERY == 0:
						_arch_name(w, e)
					elif ph >= 1 and n % COMET_EVERY == 0:
						_cometfall(w, e)
		COMETFALL:
			desired *= 0.3
			if e.timer <= 0.0:
				e.state = 0
				e.timer = 1.4 * w.tune.boss_rest_mul
		NAME: # e.timer counts the spelling down from n letters + WORD_PAD
			desired *= 0.3
			var n := BossGhostwriter.word_text(w.boss_arg, BossGhostwriter.names_in(w)).length()
			var spelt := n * BossGhostwriter.LETTER + BossGhostwriter.WORD_PAD - e.timer
			w.boss_t = minf(float(n), floorf(spelt / BossGhostwriter.LETTER) + 1.0)
			if e.timer <= 0.0:
				w.boss_arg = 0
				w.boss_t = 0.0
				e.state = 0
				e.timer = 1.4 * w.tune.boss_rest_mul
		1: # radial bursts
			desired *= 0.3
			if e.timer2 <= 0.0:
				var n := 18 if rage else 14
				var off := w.rng.randf() * TAU
				for i in n:
					var a := off + i * TAU / n
					WorldEnemies._eshot(w, World.ES_SKULL, e.pos + Vector2(0, -16), Vector2(cos(a), sin(a)) * 78.0, 5.0)
				w.emit(World.EV_ESHOT, e.pos.x, e.pos.y - 16, World.ES_SKULL, 1)
				e.timer2 = 0.55
				e.count += 1.0
				if e.count >= 3.0:
					e.state = 0
					e.timer = (1.4 if rage else 2.0) * w.tune.boss_rest_mul
		2: # aimed volleys at every wizard
			if e.timer2 <= 0.0:
				for p in w.players.values():
					if p.alive:
						var d: Vector2 = (p.pos + Vector2(0, -6) - (e.pos + Vector2(0, -16))).normalized() # muzzle to the hit centre
						for a in [-0.18, 0.0, 0.18]:
							WorldEnemies._eshot(w, World.ES_ORB, e.pos + Vector2(0, -16), d.rotated(a) * 120.0, 4.0)
				w.emit(World.EV_ESHOT, e.pos.x, e.pos.y - 16, World.ES_ORB, 1)
				e.timer2 = 0.35
				e.count += 1.0
				if e.count >= (5.0 if rage else 4.0):
					e.state = 0
					e.timer = 1.6 * w.tune.boss_rest_mul
		3: # spiral
			desired = Vector2.ZERO
			if e.timer2 <= 0.0:
				e.timer2 = 0.07
				var base := e.t * 3.2
				var arms := 3 if rage else 2
				for i in arms:
					var a := base + i * TAU / arms
					WorldEnemies._eshot(w, World.ES_SKULL, e.pos + Vector2(0, -16), Vector2(cos(a), sin(a)) * 85.0, 5.0)
				w.emit(World.EV_ESHOT, e.pos.x, e.pos.y - 16, World.ES_SKULL, 2)
			if e.timer <= 0.0:
				e.state = 0
				e.timer = 1.8 * w.tune.boss_rest_mul
		4: # summon minions from every door
			if w.phase != World.PH_GAMEOVER: # a lost run's results screen stays quiet
				var kinds := [World.SKELETON, World.GOBLIN, World.BAT] if rage else [World.GOBLIN, World.GOBLIN, World.SKELETON]
				for d in 4:
					WorldWaves.spawn_enemy(w, kinds[w.rng.randi() % kinds.size()], d)
					WorldWaves.spawn_enemy(w, World.GOBLIN, d)
				if e.final and rage:
					WorldWaves._spawn_elite(w)
			w.emit(World.EV_TELE, e.pos.x, e.pos.y - 16, 2, 0)
			e.state = 0
			e.timer = 2.5 * w.tune.boss_rest_mul
		5: # teleport to the far side of the nearest wizard, then burst
			desired = Vector2.ZERO
			if e.timer <= 0.0 and tgt:
				var old := e.pos
				var c := G.ARENA.get_center()
				var np := c - (tgt.pos - c).limit_length(90.0)
				np.y = clampf(np.y, G.ARENA.position.y + 30, G.ARENA.end.y - 10)
				e.pos = np
				e.dir = Vector2.ZERO
				w.emit(World.EV_TELE, old.x, old.y - 16, 1, 0)
				w.emit(World.EV_TELE, np.x, np.y - 16, 1, 0)
				e.state = 1
				e.count = 1.0
				e.timer2 = 0.3
	return desired


## The Archlich turns to phase `ph`: THE ASCENSION clears the field and heals, THE NINTH PAGE starts its candles.
static func _arch_turn(w: World, e: World.Enemy, ph: int) -> void:
	Bosses.drop_warnings(w, e)
	e.enter_dir.y = float(ph)
	e.state = 0
	e.timer = 1.0
	w.boss_arg = 0
	w.boss_t = 0.0
	if ph == 1:
		for o: World.Enemy in w.enemies:
			if not o.dead and o != e:
				o.dead = true
				w.emit(World.EV_DIE, o.pos.x, o.pos.y - o.r, o.type, -1)
		for p: World.Player in w.players.values():
			if p.alive:
				p.hp = mini(p.max_hp, p.hp + ASCEND_HEAL)
		w.phase_turn(e, ASCEND_TURN)
	else:
		w.boss_meter = 0.0 # the first LAST CANDLE as the page turns
		w.phase_turn(e, PAGE_TURN)


## COMETFALL: COMETS heavy blasts that leave fire, one on each aimed wizard and the rest near the party.
static func _cometfall(w: World, e: World.Enemy) -> void:
	var aim := Bosses.aims(w, e)
	for i: int in COMETS:
		var at: Vector2
		if i < aim.size():
			at = aim[i].pos
		else:
			at = w.party_center() + Vector2.from_angle(w.rng.randf() * TAU) * w.rng.randf() * COMET_SPREAD
		at = Bosses.inside(at)
		var h := w.add_hazard(Hazards.BLAST, at, at, COMET_R, COMET_WARN, HOT_BLAST, -1, e.id)
		if h != null:
			h.aux = Bosses.AUX_HEAVY | Bosses.AUX_FIRE
	e.state = COMETFALL
	e.timer = COMET_WARN


## A NAME on THE NINTH PAGE: the Ghost Writer's, one wizard, spelled in the header over the Archlich.
static func _arch_name(w: World, e: World.Enemy) -> void:
	var slots := BossGhostwriter.name_targets(w, e, int(e.enter_dir.x) / NAME_EVERY)
	if slots.is_empty():
		return
	w.boss_arg = BossGhostwriter.encode(BossGhostwriter.WORD_NAME, slots[0])
	w.boss_t = 1.0
	var n := BossGhostwriter.word_text(w.boss_arg, BossGhostwriter.names_in(w)).length()
	BossGhostwriter.cast_names(w, e, slots, n * BossGhostwriter.LETTER + BossGhostwriter.WORD_PAD)
	e.state = NAME
	e.timer = n * BossGhostwriter.LETTER + BossGhostwriter.WORD_PAD
