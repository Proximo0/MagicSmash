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
## Where it drifts between attacks, measured from the party's middle so it stays inside half a screen (240 x 135
## px) like the act bosses (BossChandelier.HOVER, BossGhostwriter.KEEP_MIN..KEEP_MAX): up to DRIFT_X px to either
## side and DRIFT_LOW..DRIFT_UP px above the party (below it when the wall is in the way), kept inside the room. A
## waypoint the party has left behind by more than that is picked again.
const DRIFT_X := 140.0
const DRIFT_LOW := 60.0
const DRIFT_UP := 100.0
## It chooses an attack only inside the screen a party sees round its middle (half of G.SCREEN each way, SIGHT_INSET
## px in), and strides SIGHT_HASTE times as fast while it is outside: it walks in from the top door, and a party low in
## the room would otherwise be shot from out of sight.
const SIGHT_INSET := 16.0
const SIGHT_HASTE := 3.0
## Its teleport lands TELE_KEEP px from the party's middle, across it from the wizard it follows (any side when
## that wizard is the middle), and on the other side when a wall cuts that spot short.
const TELE_KEEP := 80.0


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
	# Drift between waypoints near the party, above it (DRIFT_*).
	var mid := w.party_center()
	if e.dir == Vector2.ZERO or e.pos.distance_to(e.dir) < 8.0 or absf(e.dir.x - mid.x) > DRIFT_X or absf(e.dir.y - mid.y) > DRIFT_UP:
		e.dir = _lich_waypoint(w, mid)
	var seen := _lich_in_sight(e.pos, mid)
	desired = (e.dir - e.pos).normalized() * e.spd * (1.5 if rage else 1.0) * (1.0 if seen else SIGHT_HASTE)
	e.timer -= dt
	e.timer2 -= dt
	match e.state:
		0: # idle drift, then choose an attack (never from out of the party's sight: it closes in first)
			if e.timer <= 0.0 and seen:
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
				# Never past the horde's cap (World.enemy_cap), like the priest's raising and the coffin's brood.
				var room := w.enemy_cap() - w.enemies.size() - w.spawn_queue.size()
				for d in World.DOORS.size():
					if room <= 0:
						break
					WorldWaves.spawn_enemy(w, kinds[w.rng.randi() % kinds.size()], d)
					room -= 1
					if room > 0:
						WorldWaves.spawn_enemy(w, World.GOBLIN, d)
						room -= 1
				if e.final and rage and room > 0:
					WorldWaves._spawn_elite(w)
			w.emit(World.EV_TELE, e.pos.x, e.pos.y - 16, 2, 0)
			e.state = 0
			e.timer = 2.5 * w.tune.boss_rest_mul
		5: # teleport to the far side of the nearest wizard, then burst
			desired = Vector2.ZERO
			if e.timer <= 0.0 and tgt:
				var old := e.pos
				var np := _lich_landing(w, tgt.pos)
				e.pos = np
				e.dir = Vector2.ZERO
				w.emit(World.EV_TELE, old.x, old.y - 16, 1, 0)
				w.emit(World.EV_TELE, np.x, np.y - 16, 1, 0)
				e.state = 1
				e.count = 1.0
				e.timer2 = 0.3
	return desired


## True when `at` is inside the screen a party sees round its middle `c` (SIGHT_INSET px in from the edges).
static func _lich_in_sight(at: Vector2, c: Vector2) -> bool:
	return absf(at.x - c.x) <= G.SCREEN.x * 0.5 - SIGHT_INSET and absf(at.y - c.y) <= G.SCREEN.y * 0.5 - SIGHT_INSET


## Where a teleport lands (TELE_KEEP): across the party's middle from `from` (the wizard it follows), a direction
## off the seeded dice when that wizard stands on the middle (a lone wizard always does), inside the room.
static func _lich_landing(w: World, from: Vector2) -> Vector2:
	var c := w.party_center()
	var away := c - from
	if away.length() < 1.0:
		away = Vector2.from_angle(w.rng.randf() * TAU)
	away = away.normalized() * TELE_KEEP
	var np := Bosses.inside(c + away)
	if np.distance_to(c) < TELE_KEEP * 0.5: # a wall cut it short: the other side of the party
		np = Bosses.inside(c - away)
	return np


## A drift waypoint around the party's middle `c` (DRIFT_*): above the party, or below it when that spot would be
## outside the room's top, clamped inside the walls (Bosses.inside).
static func _lich_waypoint(w: World, c: Vector2) -> Vector2:
	var dx := w.rng.randf_range(-DRIFT_X, DRIFT_X)
	var dy := w.rng.randf_range(DRIFT_LOW, DRIFT_UP)
	var y := c.y - dy
	if y < G.ARENA.position.y + Bosses.WALL_INSET:
		y = c.y + dy
	return Bosses.inside(Vector2(c.x + dx, y))


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
