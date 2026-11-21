class_name Brains
extends RefCounted
## How each kind of enemy behaves: where it wants to go (think), what its death does (on_death) and how it takes a
## hit (filter_damage). Today's twelve kinds live here; an F_BOSS kind goes to Bosses; a reserved kind gets its
## brain from the script Bestiary.BRAINS names (job K's kinds_*.gd), else it walks at the nearest wizard.
## Static helpers; the first argument is the World.

## Loaded kind scripts, by path.
static var _kind_scripts: Dictionary = {}
## Where a reserved kind's brain lives: type -> script path. Bestiary.BRAINS; a test may point it elsewhere.
static var kind_brains: Dictionary = Bestiary.BRAINS


## The velocity `e` wants this tick. `tgt` is the nearest living wizard (null: none), `dirv` the unit vector to it
## (or to a wander point) and `dist` the distance.
static func think(w: World, e: World.Enemy, dt: float, tgt: World.Player, dirv: Vector2, dist: float) -> Vector2:
	if e.flags & Bestiary.F_BOSS:
		return Bosses.think(w, e, dt, tgt, dirv, dist)
	var type: int = e.type
	if type >= Bestiary.BLOAT and is_same(kind_brains, Bestiary.BRAINS):
		# The stock brains of job K's kinds, called directly and ahead of the match below: looked up and called by
		# name for every enemy on every tick they cost a full mixed floor a fifth of World.step (sim_horde).
		if type <= Bestiary.GUARD:
			return KindsCrypt.think(w, e, dt, tgt, dirv, dist)
		if type <= Bestiary.HOUND:
			return KindsLibrary.think(w, e, dt, tgt, dirv, dist)
		if type <= Bestiary.SWORDS:
			return KindsSanctum.think(w, e, dt, tgt, dirv, dist)
	var desired := Vector2.ZERO
	match type:
		World.GOBLIN, World.MSLIME:
			desired = (dirv + dirv.orthogonal() * sin(e.t * 3.0 + e.id) * 0.35).normalized() * e.spd
		World.BAT:
			desired = (dirv + dirv.orthogonal() * sin(e.t * 5.0 + e.id) * 1.1).normalized() * e.spd
		World.SLIME:
			var cyc := fmod(e.t, 1.0)
			e.state = 1 if cyc < 0.5 else 0
			desired = dirv * e.spd * 2.2 if cyc < 0.5 else Vector2.ZERO
		World.SKELETON:
			if dist > 125:
				desired = dirv * e.spd
			elif dist < 80:
				desired = -dirv * e.spd
			else:
				desired = dirv.orthogonal() * e.spd * (1.0 if e.id % 2 == 0 else -1.0)
			e.timer -= dt
			if e.timer <= 0.0 and tgt and dist < 240:
				e.timer = w.rng.randf_range(1.8, 2.8) * w.tune.enemy_shot_cd_mul
				var lead := tgt.pos + tgt.vel * (dist / w.tune.arrow_speed) * 0.5
				WorldEnemies._eshot(w, World.ES_ARROW, e.pos + Vector2(0, -7), (lead - e.pos).normalized() * w.tune.arrow_speed, 2.5)
				w.emit(World.EV_ESHOT, e.pos.x, e.pos.y - 7, World.ES_ARROW, 0)
		World.ORC:
			match e.state:
				0:
					desired = dirv * e.spd
					e.timer -= dt
					if e.timer <= 0.0 and tgt and dist < 160:
						e.state = 1
						e.timer2 = 0.6
						e.dir = dirv
						w.emit(World.EV_CHARGE, e.pos.x, e.pos.y - 8, e.id, 0)
				1:
					e.timer2 -= dt
					desired = Vector2.ZERO
					if e.timer2 <= 0.0:
						e.state = 2
						e.timer2 = 0.6
				2:
					e.timer2 -= dt
					desired = e.dir * 240.0
					if e.timer2 <= 0.0: # the room's clamp holds it in; a wall test here fizzled every charge at the bottom edge
						e.state = 0
						e.timer = w.rng.randf_range(2.0, 3.2)
		World.MAGE:
			desired = dirv.orthogonal() * e.spd * sin(e.t)
			e.timer -= dt
			if e.state == 0 and e.timer <= 0.0 and tgt:
				var old := e.pos
				var ang := w.rng.randf() * TAU
				var np := tgt.pos + Vector2(cos(ang), sin(ang)) * w.rng.randf_range(80, 130)
				np.x = clampf(np.x, G.ARENA.position.x + 14, G.ARENA.end.x - 14)
				np.y = clampf(np.y, G.ARENA.position.y + 14, G.ARENA.end.y - 6)
				e.pos = np
				w.emit(World.EV_TELE, old.x, old.y - 6, 0, 0)
				w.emit(World.EV_TELE, np.x, np.y - 6, 1, 0)
				e.state = 1
				e.timer2 = 0.55
			elif e.state == 1:
				e.timer2 -= dt
				if e.timer2 <= 0.0:
					e.state = 0
					e.timer = w.rng.randf_range(2.6, 3.6) * w.tune.enemy_shot_cd_mul
					if tgt:
						var d := (tgt.pos - e.pos).normalized()
						for a in [-0.28, 0.0, 0.28]:
							WorldEnemies._eshot(w, World.ES_ORB, e.pos + Vector2(0, -8), d.rotated(a) * w.tune.mage_orb_speed, 4.0)
						w.emit(World.EV_ESHOT, e.pos.x, e.pos.y - 8, World.ES_ORB, 0)
		World.WRAITH:
			# Straight through the crowd, fading out (state 1) for a moment in every cycle.
			var cyc := fmod(e.t, World.WRAITH_SOLID + World.WRAITH_FADED)
			e.state = 1 if cyc >= World.WRAITH_SOLID else 0
			desired = (dirv + dirv.orthogonal() * sin(e.t * 2.0 + e.id) * 0.25).normalized() * e.spd
		World.TOME:
			match e.state:
				0:
					# Circle the wizard at a reading distance, then rear up and dash through.
					var side := 1.0 if e.id % 2 == 0 else -1.0
					var ring := dirv * (dist - 70.0) * 0.04 + dirv.orthogonal() * side
					desired = ring.normalized() * e.spd
					e.timer -= dt
					if e.timer <= 0.0 and tgt and dist < 140:
						e.state = 1
						e.timer2 = 0.4
						e.dir = dirv
				1:
					e.timer2 -= dt
					desired = -e.dir * 20.0
					if e.timer2 <= 0.0:
						e.state = 2
						e.timer2 = 0.55
				2:
					e.timer2 -= dt
					desired = e.dir * 210.0
					if e.timer2 <= 0.0:
						e.state = 0
						e.timer = w.rng.randf_range(2.4, 3.6)
		World.GARGOYLE:
			# Perched as stone (state 0), then a swoop at the wizard (state 1).
			e.timer -= dt
			if e.state == 0:
				desired = Vector2.ZERO
				if e.timer <= 0.0 and tgt:
					e.state = 1
					e.timer = World.GARGOYLE_SWOOP
					e.dir = dirv
					w.emit(World.EV_CHARGE, e.pos.x, e.pos.y - 10, e.id, 0)
			else:
				e.dir = e.dir.lerp(dirv, minf(1.0, dt * 2.5)).normalized()
				desired = e.dir * 150.0
				if e.timer <= 0.0:
					e.state = 0
					e.timer = World.GARGOYLE_PERCH
		World.PRIEST:
			if dist > 150:
				desired = dirv * e.spd
			elif dist < 105:
				desired = -dirv * e.spd
			else:
				desired = dirv.orthogonal() * e.spd * (1.0 if e.id % 2 == 0 else -1.0)
			e.timer2 += dt
			e.state = 1 if fmod(e.timer2, World.PRIEST_RAISE) > World.PRIEST_RAISE - 0.6 else 0
			if e.timer2 >= World.PRIEST_RAISE:
				e.timer2 -= World.PRIEST_RAISE
				var room := w.enemy_cap() - w.enemies.size() - w.spawn_queue.size()
				var n := mini(World.PRIEST_RAISED, room)
				for k in n:
					var at := e.pos + Vector2.from_angle(w.rng.randf() * TAU) * 14.0
					at.x = clampf(at.x, G.ARENA.position.x + 8, G.ARENA.end.x - 8)
					at.y = clampf(at.y, G.ARENA.position.y + 8, G.ARENA.end.y - 4)
					WorldWaves.spawn_enemy(w, World.SKELETON, 0, at)
				if n > 0:
					w.emit(World.EV_RAISE, e.pos.x, e.pos.y, n, 0)
		_:
			var kind: GDScript = _kind_script(type)
			if kind != null:
				return kind.call("think", w, e, dt, tgt, dirv, dist)
			if not e.flags & Bestiary.F_ANCHORED:
				desired = dirv * e.spd
	return desired


## What a death does beyond the score, XP and card every kill gives. True: it has paid out (no common drop roll).
static func on_death(w: World, e: World.Enemy, slot: int) -> bool:
	if e.flags & Bestiary.F_BOSS:
		Bosses._boss_died(w, e, slot)
		return true
	match e.type:
		World.SLIME:
			for i in 2:
				var m := WorldWaves.spawn_enemy(w, World.MSLIME, 0, e.pos + Vector2(-5 + i * 10, 0))
				m.knock = Vector2(-90 + i * 180, w.rng.randf_range(-40, 40))
			w.emit(World.EV_SPLIT, e.pos.x, e.pos.y - 4, 0, 0)
		_:
			var kind: GDScript = _kind_script(e.type)
			if kind != null:
				return kind.call("on_death", w, e, slot)
	return false


## The damage a hit really does, or below 0 when it does nothing at all (no flash, no hit event). `knock` is the
## hit's push (its direction says where it came from); `sure` marks hits that ignore facing (the nova, hazards).
static func filter_damage(w: World, e: World.Enemy, dmg: float, knock: Vector2, sure: bool) -> float:
	if e.turn > 0.0:
		return -1.0 # a boss between phases
	if e.type == World.GARGOYLE and e.state == 0:
		return dmg * World.STONE_DAMAGE
	if is_same(kind_brains, Bestiary.BRAINS) and not e.flags & Bestiary.F_BOSS:
		# The stock kinds: only the guard filters a hit (see think on why this is not a looked-up call).
		return KindsCrypt.filter_damage(w, e, dmg, knock, sure) if e.type == Bestiary.GUARD else dmg
	var kind: GDScript = _kind_script(e.type)
	if kind != null:
		return kind.call("filter_damage", w, e, dmg, knock, sure)
	return dmg


## The script kind_brains (Bestiary.BRAINS) names for `type`, or null.
static func _kind_script(type: int) -> GDScript:
	var path: String = kind_brains.get(type, "")
	if path.is_empty():
		return null
	if not _kind_scripts.has(path):
		_kind_scripts[path] = load(path)
	return _kind_scripts[path]
