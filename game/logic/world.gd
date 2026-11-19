class_name World
extends RefCounted
## The authoritative game simulation. Runs on the host (or offline) only.
## It knows nothing about drawing: it emits events (for effects and sound)
## and produces compact snapshots that both the host and clients render.

# Enemy types
const GOBLIN := 0
const SKELETON := 1
const SLIME := 2
const MSLIME := 3
const BAT := 4
const ORC := 5
const MAGE := 6
const LICH := 7

# Spells
const SP_ARCANE := 0
const SP_FIRE := 1
const SP_FROST := 2
const SP_STORM := 3
const SP_STAR := 4
const SPELL_NAMES := ["ARCANE BOLT", "FIREBALL", "FROST FAN", "CHAIN LIGHTNING", "STARFALL"]
const SPELL_TIME := 15.0

# Pickups
const PK_COIN := 0
const PK_GEM := 1
const PK_POTION := 2
const PK_TOME_FIRE := 3
const PK_TOME_FROST := 4
const PK_TOME_STORM := 5
const PK_TOME_STAR := 6
const PK_BOOTS := 7
const PK_ORBIT := 8

# Enemy shot kinds
const ES_ARROW := 0
const ES_ORB := 1
const ES_SKULL := 2

# Phases
const PH_INTRO := 0
const PH_FIGHT := 1
const PH_CLEAR := 2
const PH_GAMEOVER := 3

# Events: [code, x, y, a, b]
const EV_CAST := 0
const EV_HIT := 1
const EV_DIE := 2
const EV_EXPLODE := 3
const EV_ZAP := 4
const EV_NOVA := 5
const EV_PICKUP := 6
const EV_HURT := 7
const EV_PDIE := 8
const EV_DOOR := 9
const EV_ESHOT := 10
const EV_SPLIT := 11
const EV_TELE := 12
const EV_CHARGE := 13
const EV_WAVE := 14
const EV_CLEAR := 15
const EV_BOSS := 16
const EV_COMBO := 17
const EV_SPAWN := 18
const EV_POWERUP := 19
const EV_BOSSDIE := 20
const EV_GAMEOVER := 21
const EV_FROST := 22
const EV_SCORE := 23

#                  hp    spd  r   score contact
const STATS := [
	[2.0,  58.0, 5.0, 50,  1],   # goblin
	[3.0,  40.0, 5.0, 100, 1],   # skeleton
	[5.0,  34.0, 6.0, 80,  1],   # slime
	[1.5,  52.0, 4.0, 20,  1],   # mini slime
	[1.0,  88.0, 5.0, 60,  1],   # bat
	[18.0, 30.0, 8.0, 300, 2],   # orc
	[6.0,  22.0, 5.0, 250, 1],   # dark mage
	[380.0, 26.0, 14.0, 5000, 2],# lich
]

const DOORS := [Vector2(240, 30), Vector2(240, 266), Vector2(12, 148), Vector2(468, 148)]
const DOOR_DIRS := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]

const COMBO_CALLS := {10: "SMASHING!", 25: "ARCANE CARNAGE!", 50: "WIZARDLY!", 100: "TOTAL SORCERY!", 200: "LEGENDARY!"}

class Player:
	var slot := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var aim := Vector2.DOWN
	var hp := 5
	var lives := 3
	var alive := true
	var respawn := 0.0
	var invuln := 2.0
	var spell := 0
	var spell_time := 0.0
	var bombs := 2
	var fire_cd := 0.0
	var haste := 0.0
	var orbit := 0.0
	var orbit_ang := 0.0
	var flash := 0.0
	var score := 0
	var combo := 0
	var combo_t := 0.0
	var last_bomb := -1
	var moving := false
	var kills := 0

class Enemy:
	var id := 0
	var type := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var knock := Vector2.ZERO
	var hp := 1.0
	var maxhp := 1.0
	var r := 5.0
	var spd := 40.0
	var flash := 0.0
	var slow := 0.0
	var state := 0
	var timer := 0.0
	var timer2 := 0.0
	var t := 0.0
	var dir := Vector2.ZERO
	var entering := true
	var enter_dir := Vector2.ZERO
	var orbit_cd := 0.0
	var count := 0.0
	var dead := false
	var contact := 1

class Shot:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var kind := 0
	var dmg := 1.0
	var owner := 0
	var life := 1.0
	var r := 3.0
	var dead := false

class EShot:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var kind := 0
	var life := 6.0
	var r := 3.0
	var dead := false

class Pickup:
	var kind := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 10.0

var players := {} # slot -> Player
var enemies: Array[Enemy] = []
var shots: Array[Shot] = []
var eshots: Array[EShot] = []
var pickups: Array[Pickup] = []
var events: Array = []
var rng := RandomNumberGenerator.new()
var next_id := 1
var wave := 1
var phase := PH_INTRO
var phase_t := 2.5
var wave_time := 0.0
var spawn_queue: Array = []
var door_open := [0.0, 0.0, 0.0, 0.0]
var boss: Enemy = null
var powerup_timer := 8.0
var time := 0.0
var _grid := {}
const CELL := 32.0

## seed_value 0 picks a random seed (normal play); tests, sims and replays pass a fixed one.
func _init(slots: Array, seed_value: int = 0) -> void:
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	var c := G.ARENA.get_center()
	var offs := [Vector2(-24, -14), Vector2(24, -14), Vector2(-24, 14), Vector2(24, 14)]
	for s in slots:
		var p := Player.new()
		p.slot = s
		p.pos = c + offs[s % 4]
		players[s] = p
	events.append([EV_WAVE, 0, 0, wave, 0])

func pscale() -> float:
	return 1.0 + 0.55 * (players.size() - 1)

func emit(code: int, x: float = 0.0, y: float = 0.0, a: Variant = 0, b: Variant = 0) -> void:
	events.append([code, x, y, a, b])

func take_events() -> Array:
	var e := events
	events = []
	return e

# ================================================================= STEP ===
func step(dt: float, inputs: Dictionary) -> void:
	time += dt
	for i in 4:
		door_open[i] = maxf(0.0, door_open[i] - dt)
	match phase:
		PH_INTRO:
			phase_t -= dt
			if phase_t <= 0.0:
				phase = PH_FIGHT
				wave_time = 0.0
				_build_wave()
		PH_FIGHT:
			wave_time += dt
			_process_spawns()
			powerup_timer -= dt
			if powerup_timer <= 0.0:
				powerup_timer = rng.randf_range(9.0, 14.0)
				_spawn_random_powerup()
			if spawn_queue.is_empty() and enemies.is_empty():
				phase = PH_CLEAR
				phase_t = 3.5
				var bonus := 1000 * wave
				for p in players.values():
					if p.lives > 0:
						p.score += bonus
				emit(EV_CLEAR, 240, 140, wave, bonus)
		PH_CLEAR:
			phase_t -= dt
			if phase_t <= 0.0:
				wave += 1
				phase = PH_INTRO
				phase_t = 2.5
				emit(EV_WAVE, 0, 0, wave, 1 if wave % 5 == 0 else 0)
		PH_GAMEOVER:
			phase_t += dt
	_build_grid()
	for p in players.values():
		_update_player(p, dt, inputs.get(p.slot, PackedFloat32Array()))
	for e in enemies:
		if not e.dead:
			_update_enemy(e, dt)
	_update_shots(dt)
	_update_eshots(dt)
	_update_pickups(dt)
	enemies = enemies.filter(func(e): return not e.dead)
	shots = shots.filter(func(s): return not s.dead)
	eshots = eshots.filter(func(s): return not s.dead)
	if phase != PH_GAMEOVER:
		var any := false
		for p in players.values():
			if p.alive or p.lives > 0:
				any = true
		if not any:
			phase = PH_GAMEOVER
			phase_t = 0.0
			emit(EV_GAMEOVER, 0, 0, total_score(), 0)

func total_score() -> int:
	var s := 0
	for p in players.values():
		s += p.score
	return s

# ================================================================ WAVES ===
func _build_wave() -> void:
	spawn_queue.clear()
	var t := 0.6
	if wave % 5 == 0:
		_queue_group(GOBLIN, 6, rng.randi_range(0, 3), t)
		spawn_queue.append({"t": 2.5, "type": LICH, "door": 0})
		_sort_queue()
		return
	var budget := (18.0 + wave * 9.0) * pscale()
	var pool := [[GOBLIN, 1.0, 5], [BAT, 1.0, 3]]
	if wave >= 2: pool.append([SLIME, 3.0, 3])
	if wave >= 3: pool.append([SKELETON, 3.0, 3])
	if wave >= 4: pool.append([ORC, 9.0, 1])
	if wave >= 6: pool.append([MAGE, 6.0, 2])
	if wave >= 7: pool.append([ORC, 9.0, 1])
	pool.append([GOBLIN, 1.0, 5])
	while budget > 0.0:
		var pick: Array = pool[rng.randi() % pool.size()]
		var n := 1
		match pick[0]:
			GOBLIN: n = rng.randi_range(6, 10 + wave)
			BAT: n = rng.randi_range(4, 8)
			SLIME: n = rng.randi_range(2, 4)
			SKELETON: n = rng.randi_range(2, 5)
			ORC: n = 1
			MAGE: n = rng.randi_range(1, 2)
		_queue_group(pick[0], n, rng.randi_range(0, 3), t)
		budget -= pick[1] * n
		# Sometimes two doors burst open at once.
		if rng.randf() < 0.35:
			continue
		t += rng.randf_range(0.7, 1.8) * maxf(0.5, 1.0 - wave * 0.04)
	_sort_queue()

func _queue_group(type: int, n: int, door: int, t: float) -> void:
	for i in n:
		spawn_queue.append({"t": t + i * 0.18, "type": type, "door": door})

func _sort_queue() -> void:
	spawn_queue.sort_custom(func(a, b): return a.t < b.t)

func _process_spawns() -> void:
	while not spawn_queue.is_empty() and spawn_queue[0].t <= wave_time:
		var s: Dictionary = spawn_queue.pop_front()
		spawn_enemy(s.type, s.door)

func spawn_enemy(type: int, door: int, at: Variant = null) -> Enemy:
	var e := Enemy.new()
	e.id = next_id
	next_id += 1
	e.type = type
	var st: Array = STATS[type]
	var hp_scale := 1.0 + 0.07 * (wave - 1)
	if type == LICH:
		hp_scale = (1.0 + 0.6 * (players.size() - 1)) * (1.0 + 0.25 * (wave / 5 - 1))
	e.hp = st[0] * hp_scale
	e.maxhp = e.hp
	e.spd = st[1] * (1.0 + 0.02 * minf(wave, 15))
	e.r = st[2]
	e.contact = st[4]
	e.t = rng.randf() * 10.0
	e.timer = rng.randf_range(1.0, 2.5)
	if at != null:
		e.pos = at
		e.entering = false
	else:
		var jitter := Vector2(rng.randf_range(-14, 14), 0) if door < 2 else Vector2(0, rng.randf_range(-14, 14))
		e.pos = DOORS[door] + jitter
		e.enter_dir = DOOR_DIRS[door]
		if door_open[door] <= 0.0:
			emit(EV_DOOR, DOORS[door].x, DOORS[door].y, door, 0)
		door_open[door] = 1.2
	if type == LICH:
		boss = e
		e.state = 0
		e.timer = 2.0
		emit(EV_BOSS, e.pos.x, e.pos.y, 0, 0)
	enemies.append(e)
	return e

func _spawn_random_powerup() -> void:
	var kinds := [PK_TOME_FIRE, PK_TOME_FROST, PK_TOME_STORM, PK_TOME_STAR, PK_BOOTS, PK_ORBIT, PK_TOME_FIRE, PK_TOME_STORM]
	var k: int = kinds[rng.randi() % kinds.size()]
	var pos := Vector2.ZERO
	for tries in 12:
		pos = Vector2(rng.randf_range(G.ARENA.position.x + 30, G.ARENA.end.x - 30),
			rng.randf_range(G.ARENA.position.y + 24, G.ARENA.end.y - 24))
		var ok := true
		for p in players.values():
			if p.pos.distance_to(pos) < 50:
				ok = false
		if ok:
			break
	_drop(k, pos, Vector2.ZERO, 12.0)
	emit(EV_POWERUP, pos.x, pos.y, k, 0)

# =============================================================== PLAYER ===
func _update_player(p: Player, dt: float, inp: PackedFloat32Array) -> void:
	p.flash = maxf(0.0, p.flash - dt)
	p.invuln = maxf(0.0, p.invuln - dt)
	p.haste = maxf(0.0, p.haste - dt)
	p.orbit = maxf(0.0, p.orbit - dt)
	p.orbit_ang += dt * 5.5
	if p.combo_t > 0.0:
		p.combo_t -= dt
		if p.combo_t <= 0.0:
			p.combo = 0
	if not p.alive:
		if p.lives > 0 and phase != PH_GAMEOVER:
			p.respawn -= dt
			if p.respawn <= 0.0:
				p.alive = true
				p.hp = 5
				p.invuln = 2.5
				p.bombs = maxi(p.bombs, 2)
				p.pos = G.ARENA.get_center() + Vector2(rng.randf_range(-20, 20), rng.randf_range(-10, 10))
				emit(EV_SPAWN, p.pos.x, p.pos.y, p.slot, 0)
		return
	var move := Vector2.ZERO
	var aim := Vector2.ZERO
	var fire := false
	var bomb_count := -1
	if inp.size() >= 6:
		move = Vector2(inp[0], inp[1]).limit_length(1.0)
		aim = Vector2(inp[2], inp[3])
		fire = inp[4] > 0.5
		bomb_count = int(inp[5])
	var speed := 102.0 * (1.45 if p.haste > 0.0 else 1.0)
	p.vel = move * speed
	p.moving = move.length() > 0.1
	p.pos += p.vel * dt
	p.pos.x = clampf(p.pos.x, G.ARENA.position.x + 5, G.ARENA.end.x - 5)
	p.pos.y = clampf(p.pos.y, G.ARENA.position.y + 6, G.ARENA.end.y - 2)
	if aim.length() > 0.1:
		p.aim = aim.normalized()
	elif p.moving:
		p.aim = move.normalized()
	p.fire_cd -= dt
	if fire and p.fire_cd <= 0.0 and aim.length() > 0.1 and phase != PH_GAMEOVER:
		_cast(p)
	if p.spell != SP_ARCANE:
		p.spell_time -= dt
		if p.spell_time <= 0.0:
			p.spell = SP_ARCANE
	if bomb_count >= 0:
		if p.last_bomb < 0:
			p.last_bomb = bomb_count
		elif bomb_count > p.last_bomb:
			p.last_bomb = bomb_count
			if p.bombs > 0:
				_nova(p)
	if p.orbit > 0.0:
		for i in 3:
			var a := p.orbit_ang + i * TAU / 3.0
			var op := p.pos + Vector2(0, -6) + Vector2(cos(a), sin(a)) * 22.0
			for e in _query(op, 14.0):
				if e.orbit_cd <= 0.0 and op.distance_to(e.pos) < e.r + 6.0:
					e.orbit_cd = 0.3
					_damage_enemy(e, 1.5, p.slot, (e.pos - p.pos).normalized() * 80.0)

func staff_tip(p: Player) -> Vector2:
	return p.pos + Vector2(0, -7) + p.aim * 9.0

func _cast(p: Player) -> void:
	var rate_mul := 0.72 if p.haste > 0.0 else 1.0
	var tip := staff_tip(p)
	var dir := p.aim
	match p.spell:
		SP_ARCANE:
			p.fire_cd = 0.11 * rate_mul
			_shot(p, tip, dir.rotated(rng.randf_range(-0.04, 0.04)) * 310.0, 1.0, 3.0, 1.0)
		SP_FIRE:
			p.fire_cd = 0.27 * rate_mul
			_shot(p, tip, dir * 200.0, 2.0, 4.5, 1.6)
		SP_FROST:
			p.fire_cd = 0.21 * rate_mul
			for i in 5:
				var a := (i - 2) * 0.17
				_shot(p, tip, dir.rotated(a) * 255.0, 0.85, 2.5, 0.75)
		SP_STORM:
			p.fire_cd = 0.15 * rate_mul
			_chain_lightning(p, tip)
		SP_STAR:
			p.fire_cd = 0.2 * rate_mul
			for s in [-0.45, 0.45]:
				_shot(p, tip, dir.rotated(s) * 175.0, 1.35, 3.0, 2.2)
	emit(EV_CAST, tip.x, tip.y, p.spell, p.slot)

func _shot(p: Player, pos: Vector2, vel: Vector2, dmg: float, r: float, life: float) -> void:
	var s := Shot.new()
	s.pos = pos
	s.vel = vel
	s.kind = p.spell
	s.dmg = dmg
	s.owner = p.slot
	s.r = r
	s.life = life
	shots.append(s)

func _chain_lightning(p: Player, tip: Vector2) -> void:
	var pts := PackedVector2Array([tip])
	var hit := {}
	var best: Enemy = null
	var best_d := 140.0
	for e in enemies:
		if e.dead:
			continue
		var to := e.pos - tip
		var d := to.length()
		if d < best_d and to.normalized().dot(p.aim) > 0.6:
			best_d = d
			best = e
	if best == null:
		pts.append(tip + p.aim * 70.0)
		emit(EV_ZAP, tip.x, tip.y, pts, p.slot)
		return
	var cur := best
	var dmg := 1.7
	for i in 5:
		pts.append(cur.pos + Vector2(0, -4))
		hit[cur.id] = true
		_damage_enemy(cur, dmg, p.slot, p.aim * 40.0)
		var nxt: Enemy = null
		var nd := 70.0
		for e in _query(cur.pos, 70.0):
			if hit.has(e.id) or e.dead:
				continue
			var d = e.pos.distance_to(cur.pos)
			if d < nd:
				nd = d
				nxt = e
		if nxt == null:
			break
		cur = nxt
		dmg *= 0.85
	emit(EV_ZAP, tip.x, tip.y, pts, p.slot)

func _nova(p: Player) -> void:
	p.bombs -= 1
	p.invuln = maxf(p.invuln, 0.8)
	emit(EV_NOVA, p.pos.x, p.pos.y - 6, p.slot, 0)
	var radius := 150.0
	for e in enemies:
		if e.dead:
			continue
		var d := e.pos.distance_to(p.pos)
		if d < radius:
			var dmg := 40.0 if e.type == LICH else 14.0
			_damage_enemy(e, dmg, p.slot, (e.pos - p.pos).normalized() * 260.0)
	for s in eshots:
		if s.pos.distance_to(p.pos) < radius + 30:
			s.dead = true

func hurt_player(p: Player, dmg: int) -> void:
	if not p.alive or p.invuln > 0.0 or phase == PH_GAMEOVER:
		return
	p.hp -= dmg
	p.flash = 0.15
	p.invuln = 1.1
	emit(EV_HURT, p.pos.x, p.pos.y - 6, p.slot, 0)
	if p.hp <= 0:
		p.alive = false
		p.lives -= 1
		p.respawn = 2.5
		p.spell = SP_ARCANE
		p.haste = 0.0
		p.orbit = 0.0
		p.combo = 0
		emit(EV_PDIE, p.pos.x, p.pos.y - 6, p.slot, p.lives)

# ================================================================ ENEMY ===
func _nearest_player(pos: Vector2) -> Player:
	var best: Player = null
	var bd := INF
	for p in players.values():
		if not p.alive:
			continue
		var d = p.pos.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = p
	return best

func _update_enemy(e: Enemy, dt: float) -> void:
	e.t += dt
	e.flash = maxf(0.0, e.flash - dt)
	e.slow = maxf(0.0, e.slow - dt)
	e.orbit_cd = maxf(0.0, e.orbit_cd - dt)
	var sm := 0.45 if e.slow > 0.0 else 1.0
	if e.entering:
		e.pos += e.enter_dir * maxf(e.spd, 40.0) * dt
		if G.ARENA.grow(-10).has_point(e.pos):
			e.entering = false
		return
	var tgt := _nearest_player(e.pos)
	var tpos := tgt.pos if tgt else G.ARENA.get_center() + Vector2(cos(e.t * 0.5), sin(e.t * 0.7)) * 80.0
	var to := tpos - e.pos
	var dist := to.length()
	var dirv := to / maxf(dist, 0.001)
	var desired := Vector2.ZERO
	match e.type:
		GOBLIN, MSLIME:
			desired = (dirv + dirv.orthogonal() * sin(e.t * 3.0 + e.id) * 0.35).normalized() * e.spd
		BAT:
			desired = (dirv + dirv.orthogonal() * sin(e.t * 5.0 + e.id) * 1.1).normalized() * e.spd
		SLIME:
			var cyc := fmod(e.t, 1.0)
			e.state = 1 if cyc < 0.5 else 0
			desired = dirv * e.spd * 2.2 if cyc < 0.5 else Vector2.ZERO
		SKELETON:
			if dist > 125:
				desired = dirv * e.spd
			elif dist < 80:
				desired = -dirv * e.spd
			else:
				desired = dirv.orthogonal() * e.spd * (1.0 if e.id % 2 == 0 else -1.0)
			e.timer -= dt
			if e.timer <= 0.0 and tgt and dist < 240:
				e.timer = rng.randf_range(1.8, 2.8)
				var lead := tgt.pos + tgt.vel * (dist / 150.0) * 0.5
				_eshot(ES_ARROW, e.pos + Vector2(0, -7), (lead - e.pos).normalized() * 150.0, 2.5)
				emit(EV_ESHOT, e.pos.x, e.pos.y - 7, ES_ARROW, 0)
		ORC:
			match e.state:
				0:
					desired = dirv * e.spd
					e.timer -= dt
					if e.timer <= 0.0 and tgt and dist < 160:
						e.state = 1
						e.timer2 = 0.6
						e.dir = dirv
						emit(EV_CHARGE, e.pos.x, e.pos.y - 8, e.id, 0)
				1:
					e.timer2 -= dt
					desired = Vector2.ZERO
					if e.timer2 <= 0.0:
						e.state = 2
						e.timer2 = 0.6
				2:
					e.timer2 -= dt
					desired = e.dir * 240.0
					if e.timer2 <= 0.0 or not G.ARENA.grow(-9).has_point(e.pos + e.dir * 4.0):
						e.state = 0
						e.timer = rng.randf_range(2.0, 3.2)
		MAGE:
			desired = dirv.orthogonal() * e.spd * sin(e.t)
			e.timer -= dt
			if e.state == 0 and e.timer <= 0.0 and tgt:
				var old := e.pos
				var ang := rng.randf() * TAU
				var np := tgt.pos + Vector2(cos(ang), sin(ang)) * rng.randf_range(80, 130)
				np.x = clampf(np.x, G.ARENA.position.x + 14, G.ARENA.end.x - 14)
				np.y = clampf(np.y, G.ARENA.position.y + 14, G.ARENA.end.y - 6)
				e.pos = np
				emit(EV_TELE, old.x, old.y - 6, 0, 0)
				emit(EV_TELE, np.x, np.y - 6, 1, 0)
				e.state = 1
				e.timer2 = 0.55
			elif e.state == 1:
				e.timer2 -= dt
				if e.timer2 <= 0.0:
					e.state = 0
					e.timer = rng.randf_range(2.6, 3.6)
					if tgt:
						var d := (tgt.pos - e.pos).normalized()
						for a in [-0.28, 0.0, 0.28]:
							_eshot(ES_ORB, e.pos + Vector2(0, -8), d.rotated(a) * 95.0, 4.0)
						emit(EV_ESHOT, e.pos.x, e.pos.y - 8, ES_ORB, 0)
		LICH:
			desired = _update_lich(e, dt, tgt, dirv, dist)
	e.vel = e.vel.lerp(desired * sm, minf(1.0, dt * 10.0))
	e.pos += (e.vel + e.knock) * dt
	e.knock = e.knock.move_toward(Vector2.ZERO, dt * 600.0)
	# Separation so hordes spread into a crowd instead of a single blob.
	if e.type != BAT:
		for o in _query(e.pos, 16.0):
			if o == e or o.type == BAT or o.entering:
				continue
			var dv = e.pos - o.pos
			var dd = dv.length()
			var min_d = e.r + o.r
			if dd < min_d and dd > 0.01:
				var push = dv / dd * (min_d - dd) * (0.5 if o.type != LICH else 1.0)
				e.pos += push * 0.5
	e.pos.x = clampf(e.pos.x, G.ARENA.position.x + e.r, G.ARENA.end.x - e.r)
	e.pos.y = clampf(e.pos.y, G.ARENA.position.y + e.r, G.ARENA.end.y - 2)
	# Contact damage
	for p in players.values():
		if p.alive and p.invuln <= 0.0 and p.pos.distance_to(e.pos) < e.r + 5.0:
			var dmg := e.contact
			if e.type == ORC and e.state == 2:
				dmg = 2
			hurt_player(p, dmg)

func _update_lich(e: Enemy, dt: float, tgt: Player, dirv: Vector2, dist: float) -> Vector2:
	var rage := e.hp / e.maxhp < 0.5
	var desired := Vector2.ZERO
	# Drift between waypoints in the upper half of the arena.
	if e.dir == Vector2.ZERO or e.pos.distance_to(e.dir) < 8.0:
		e.dir = Vector2(rng.randf_range(G.ARENA.position.x + 60, G.ARENA.end.x - 60),
			rng.randf_range(G.ARENA.position.y + 40, G.ARENA.get_center().y + 30))
	desired = (e.dir - e.pos).normalized() * e.spd * (1.5 if rage else 1.0)
	e.timer -= dt
	e.timer2 -= dt
	match e.state:
		0: # idle drift, then choose an attack
			if e.timer <= 0.0:
				var choices := [1, 2, 3, 4, 1, 2]
				if rage:
					choices.append(5)
				e.state = choices[rng.randi() % choices.size()]
				e.timer2 = 0.0
				e.count = 0.0
				e.timer = 2.4 if e.state == 3 else 0.6
		1: # radial bursts
			desired *= 0.3
			if e.timer2 <= 0.0:
				var n := 18 if rage else 14
				var off := rng.randf() * TAU
				for i in n:
					var a := off + i * TAU / n
					_eshot(ES_SKULL, e.pos + Vector2(0, -16), Vector2(cos(a), sin(a)) * 78.0, 5.0)
				emit(EV_ESHOT, e.pos.x, e.pos.y - 16, ES_SKULL, 1)
				e.timer2 = 0.55
				e.count += 1.0
				if e.count >= 3.0:
					e.state = 0
					e.timer = 1.4 if rage else 2.0
		2: # aimed volleys at every wizard
			if e.timer2 <= 0.0:
				for p in players.values():
					if p.alive:
						var d = (p.pos - e.pos).normalized()
						for a in [-0.18, 0.0, 0.18]:
							_eshot(ES_ORB, e.pos + Vector2(0, -16), d.rotated(a) * 120.0, 4.0)
				emit(EV_ESHOT, e.pos.x, e.pos.y - 16, ES_ORB, 1)
				e.timer2 = 0.35
				e.count += 1.0
				if e.count >= (5.0 if rage else 4.0):
					e.state = 0
					e.timer = 1.6
		3: # spiral
			desired = Vector2.ZERO
			if e.timer2 <= 0.0:
				e.timer2 = 0.07
				var base := e.t * 3.2
				var arms := 3 if rage else 2
				for i in arms:
					var a := base + i * TAU / arms
					_eshot(ES_SKULL, e.pos + Vector2(0, -16), Vector2(cos(a), sin(a)) * 85.0, 5.0)
				emit(EV_ESHOT, e.pos.x, e.pos.y - 16, ES_SKULL, 2)
			if e.timer <= 0.0:
				e.state = 0
				e.timer = 1.8
		4: # summon minions from every door
			var kinds := [SKELETON, GOBLIN, BAT] if rage else [GOBLIN, GOBLIN, SKELETON]
			for d in 4:
				spawn_enemy(kinds[rng.randi() % kinds.size()], d)
				spawn_enemy(GOBLIN, d)
			emit(EV_TELE, e.pos.x, e.pos.y - 16, 2, 0)
			e.state = 0
			e.timer = 2.5
		5: # teleport to the far side of the nearest wizard, then burst
			desired = Vector2.ZERO
			if e.timer <= 0.0 and tgt:
				var old := e.pos
				var c := G.ARENA.get_center()
				var np := c - (tgt.pos - c).limit_length(90.0)
				np.y = clampf(np.y, G.ARENA.position.y + 30, G.ARENA.end.y - 10)
				e.pos = np
				e.dir = Vector2.ZERO
				emit(EV_TELE, old.x, old.y - 16, 1, 0)
				emit(EV_TELE, np.x, np.y - 16, 1, 0)
				e.state = 1
				e.count = 1.0
				e.timer2 = 0.3
	return desired

func _eshot(kind: int, pos: Vector2, vel: Vector2, r: float) -> void:
	var s := EShot.new()
	s.kind = kind
	s.pos = pos
	s.vel = vel
	s.r = r
	eshots.append(s)

func _damage_enemy(e: Enemy, dmg: float, slot: int, knock: Vector2) -> void:
	if e.dead:
		return
	e.hp -= dmg
	e.flash = 0.07
	var km := 0.15 if e.type == LICH else (0.4 if e.type == ORC else 1.0)
	e.knock += knock * km
	emit(EV_HIT, e.pos.x, e.pos.y - e.r, e.type, slot)
	if e.hp <= 0.0:
		_kill_enemy(e, slot)

func _kill_enemy(e: Enemy, slot: int) -> void:
	e.dead = true
	var p: Player = players.get(slot)
	var base: int = STATS[e.type][3]
	if p:
		p.combo += 1
		p.combo_t = 2.5
		p.kills += 1
		var mult := 1 + mini(p.combo / 10, 4)
		p.score += base * mult
		if COMBO_CALLS.has(p.combo):
			emit(EV_COMBO, e.pos.x, e.pos.y, p.combo, slot)
	emit(EV_DIE, e.pos.x, e.pos.y - e.r, e.type, slot)
	match e.type:
		SLIME:
			for i in 2:
				var m := spawn_enemy(MSLIME, 0, e.pos + Vector2(-5 + i * 10, 0))
				m.knock = Vector2(-90 + i * 180, rng.randf_range(-40, 40))
			emit(EV_SPLIT, e.pos.x, e.pos.y - 4, 0, 0)
		LICH:
			boss = null
			for o in enemies:
				if not o.dead and o != e:
					o.dead = true
					emit(EV_DIE, o.pos.x, o.pos.y - o.r, o.type, -1)
			for s in eshots:
				s.dead = true
			for i in 14:
				_drop(PK_GEM if i % 2 == 0 else PK_COIN, e.pos, Vector2.from_angle(i * TAU / 14) * 90.0)
			_drop(PK_POTION, e.pos, Vector2(0, 40))
			emit(EV_BOSSDIE, e.pos.x, e.pos.y - 14, slot, 0)
			spawn_queue.clear()
			return
	_roll_drop(e)

func _roll_drop(e: Enemy) -> void:
	var r := rng.randf()
	var big := e.type == ORC or e.type == MAGE
	var pop := Vector2.from_angle(rng.randf() * TAU) * 40.0
	if big:
		_drop(PK_GEM, e.pos, pop)
		if rng.randf() < 0.25:
			_drop([PK_TOME_FIRE, PK_TOME_FROST, PK_TOME_STORM, PK_TOME_STAR][rng.randi() % 4], e.pos, -pop)
		return
	if r < 0.22:
		_drop(PK_COIN, e.pos, pop)
	elif r < 0.27:
		_drop(PK_GEM, e.pos, pop)
	elif r < 0.29:
		_drop(PK_POTION, e.pos, pop)
	elif r < 0.315:
		_drop([PK_TOME_FIRE, PK_TOME_FROST, PK_TOME_STORM, PK_TOME_STAR][rng.randi() % 4], e.pos, pop)
	elif r < 0.322:
		_drop(PK_BOOTS, e.pos, pop)
	elif r < 0.33:
		_drop(PK_ORBIT, e.pos, pop)

func _drop(kind: int, pos: Vector2, vel: Vector2, life: float = 9.0) -> void:
	var k := Pickup.new()
	k.kind = kind
	k.pos = pos
	k.vel = vel
	k.life = life
	pickups.append(k)

# ======================================================== SHOTS/PICKUPS ===
func _update_shots(dt: float) -> void:
	var bounds := G.ARENA.grow(4)
	for s in shots:
		s.life -= dt
		if s.kind == SP_STAR:
			var best: Enemy = null
			var bd := 160.0
			for e in _query(s.pos, 160.0):
				var d = e.pos.distance_to(s.pos)
				if d < bd:
					bd = d
					best = e
			if best:
				var want := (best.pos + Vector2(0, -4) - s.pos).normalized() * s.vel.length()
				s.vel = s.vel.lerp(want, minf(1.0, dt * 5.5)).normalized() * 175.0
		s.pos += s.vel * dt
		if s.life <= 0.0 or not bounds.has_point(s.pos):
			s.dead = true
			if s.kind == SP_FIRE:
				_explode(s)
			continue
		for e in _query(s.pos, 20.0):
			if e.dead:
				continue
			var hit_pos = e.pos + Vector2(0, -e.r * 0.8)
			if s.pos.distance_to(hit_pos) < s.r + e.r + 1.0:
				s.dead = true
				if s.kind == SP_FIRE:
					_explode(s)
				else:
					_damage_enemy(e, s.dmg, s.owner, s.vel.normalized() * 70.0)
					if s.kind == SP_FROST:
						e.slow = 1.8
						emit(EV_FROST, s.pos.x, s.pos.y, 0, 0)
				break

func _explode(s: Shot) -> void:
	emit(EV_EXPLODE, s.pos.x, s.pos.y, 28, s.owner)
	for e in _query(s.pos, 40.0):
		var d = e.pos.distance_to(s.pos)
		if d < 28.0 + e.r:
			_damage_enemy(e, s.dmg + 1.5 * (1.0 - d / 40.0), s.owner, (e.pos - s.pos).normalized() * 160.0)

func _update_eshots(dt: float) -> void:
	var bounds := G.ARENA.grow(6)
	for s in eshots:
		s.life -= dt
		s.pos += s.vel * dt
		if s.life <= 0.0 or not bounds.has_point(s.pos):
			s.dead = true
			continue
		for p in players.values():
			if p.alive and p.invuln <= 0.0 and s.pos.distance_to(p.pos + Vector2(0, -6)) < s.r + 4.0:
				s.dead = true
				hurt_player(p, 1)
				break

func _update_pickups(dt: float) -> void:
	for k in pickups:
		k.life -= dt
		k.pos += k.vel * dt
		k.vel = k.vel.move_toward(Vector2.ZERO, dt * 120.0)
		k.pos.x = clampf(k.pos.x, G.ARENA.position.x + 6, G.ARENA.end.x - 6)
		k.pos.y = clampf(k.pos.y, G.ARENA.position.y + 8, G.ARENA.end.y - 4)
		for p in players.values():
			if p.alive and p.pos.distance_to(k.pos) < 11.0:
				_collect(p, k)
				k.life = -1.0
				break
	pickups = pickups.filter(func(k): return k.life > 0.0)

func _collect(p: Player, k: Pickup) -> void:
	var pts := 0
	match k.kind:
		PK_COIN: pts = 100
		PK_GEM: pts = 500
		PK_POTION:
			p.hp = mini(5, p.hp + 2)
		PK_TOME_FIRE, PK_TOME_FROST, PK_TOME_STORM, PK_TOME_STAR:
			var sp: int = k.kind - PK_TOME_FIRE + 1
			p.spell_time = SPELL_TIME + (p.spell_time if p.spell == sp else 0.0)
			p.spell = sp
		PK_BOOTS:
			p.haste = 10.0
		PK_ORBIT:
			p.orbit = 12.0
	p.score += pts
	emit(EV_PICKUP, k.pos.x, k.pos.y, k.kind, p.slot)
	if pts > 0:
		emit(EV_SCORE, k.pos.x, k.pos.y - 6, pts, p.slot)

# ================================================================ GRID ===
func _build_grid() -> void:
	_grid.clear()
	for e in enemies:
		if e.dead:
			continue
		var k := Vector2i(floori(e.pos.x / CELL), floori(e.pos.y / CELL))
		if _grid.has(k):
			_grid[k].append(e)
		else:
			_grid[k] = [e]

func _query(pos: Vector2, radius: float) -> Array:
	var out := []
	var x0 := floori((pos.x - radius) / CELL)
	var x1 := floori((pos.x + radius) / CELL)
	var y0 := floori((pos.y - radius) / CELL)
	var y1 := floori((pos.y + radius) / CELL)
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var k := Vector2i(x, y)
			if _grid.has(k):
				for e in _grid[k]:
					if not e.dead:
						out.append(e)
	return out

## Summary of the whole simulation for determinism checks (same seed + same inputs = same hash).
func state_hash() -> int:
	return hash([snapshot(), wave, phase, total_score(), rng.state])

# ============================================================ SNAPSHOT ===
func snapshot() -> Dictionary:
	var pl := PackedFloat32Array()
	for p in players.values():
		pl.append_array([p.slot, p.pos.x, p.pos.y, p.aim.x, p.aim.y, p.hp, p.lives,
			1.0 if p.alive else 0.0, p.invuln, p.spell, p.spell_time, p.bombs, p.score,
			p.combo, p.haste, p.orbit, p.orbit_ang, p.flash, 1.0 if p.moving else 0.0])
	var en := PackedFloat32Array()
	for e in enemies:
		en.append_array([e.id, e.type, e.pos.x, e.pos.y, e.flash, e.state, e.hp / e.maxhp, e.slow])
	var sh := PackedFloat32Array()
	for s in shots:
		sh.append_array([s.kind, s.pos.x, s.pos.y, s.vel.x, s.vel.y, s.owner])
	var es := PackedFloat32Array()
	for s in eshots:
		es.append_array([s.kind, s.pos.x, s.pos.y, s.vel.x, s.vel.y])
	var pk := PackedFloat32Array()
	for k in pickups:
		pk.append_array([k.kind, k.pos.x, k.pos.y, k.life])
	var bf := -1.0
	if boss and not boss.dead:
		bf = boss.hp / boss.maxhp
	return {
		"p": pl, "e": en, "s": sh, "es": es, "k": pk,
		"w": PackedFloat32Array([wave, phase, phase_t, bf, door_open[0], door_open[1], door_open[2], door_open[3]]),
	}
