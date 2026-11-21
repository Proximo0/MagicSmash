class_name WorldBosses
extends RefCounted
## The Lich and the Archlich for World: their behaviour, scaling and visits. Static helpers; the first argument is the World.


## Turns a Lich into the Archlich: final_hp_mul times the HP, full health, a bigger body and a meaner pattern.
static func _make_final(w: World, e: World.Enemy) -> void:
	e.final = true
	e.maxhp = World.STATS[World.LICH][0] * _lich_hp_scale(w) * w.tune.final_hp_mul \
		* (1.0 + w.tune.final_hp_per_player * (w.players.size() - 1))
	e.hp = e.maxhp
	e.r += 3.0
	e.state = 0
	e.timer = 2.0
	w.emit(World.EV_BOSS, e.pos.x, e.pos.y, 1, 0)


static func _lich_hp_scale(w: World) -> float:
	return w.tune.boss_hp_mul * (1.0 + w.tune.boss_hp_per_player * (w.players.size() - 1)) * (1.0 + w.tune.boss_hp_per_cycle * maxi(0, _lich_visits(w, w.wave) - 1))


## How many Lich visits are due by the start of `minute` (minute 1 starts at 0:00).
static func _lich_visits(w: World, minute: int) -> int:
	return (minute - 1) / int(w.tune.boss_every_min)


static func _update_lich(w: World, e: World.Enemy, dt: float, tgt: World.Player, dirv: Vector2, dist: float) -> Vector2:
	var rage := e.hp / e.maxhp < (World.FINAL_RAGE if e.final else 0.5)
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
						var d = (p.pos - e.pos).normalized()
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
