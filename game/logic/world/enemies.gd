class_name WorldEnemies
extends RefCounted
## Enemies for World: targeting, movement and attacks, separation, enemy shots, damage and death. Static helpers; the first argument is the World.


static func _nearest_player(w: World, pos: Vector2) -> World.Player:
	if w._plist.size() != w.players.size():
		w._plist.assign(w.players.values())
	var best: World.Player = null
	var bd := INF
	for p: World.Player in w._plist:
		if not p.alive:
			continue
		var d := p.pos.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = p
	return best


static func _update_enemy(w: World, e: World.Enemy, dt: float) -> void:
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
	var tgt := _nearest_player(w, e.pos)
	var tpos := tgt.pos if tgt else G.ARENA.get_center() + Vector2(cos(e.t * 0.5), sin(e.t * 0.7)) * 80.0
	var to := tpos - e.pos
	var dist := to.length()
	var dirv := to / maxf(dist, 0.001)
	var desired := Vector2.ZERO
	match e.type:
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
				e.timer = w.rng.randf_range(1.8, 2.8)
				var lead := tgt.pos + tgt.vel * (dist / 150.0) * 0.5
				_eshot(w, World.ES_ARROW, e.pos + Vector2(0, -7), (lead - e.pos).normalized() * 150.0, 2.5)
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
					if e.timer2 <= 0.0 or not G.ARENA.grow(-9).has_point(e.pos + e.dir * 4.0):
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
					e.timer = w.rng.randf_range(2.6, 3.6)
					if tgt:
						var d := (tgt.pos - e.pos).normalized()
						for a in [-0.28, 0.0, 0.28]:
							_eshot(w, World.ES_ORB, e.pos + Vector2(0, -8), d.rotated(a) * 95.0, 4.0)
						w.emit(World.EV_ESHOT, e.pos.x, e.pos.y - 8, World.ES_ORB, 0)
		World.LICH:
			desired = WorldBosses._update_lich(w, e, dt, tgt, dirv, dist)
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
				var room := int(w.tune.enemy_cap) - w.enemies.size() - w.spawn_queue.size()
				var n := mini(World.PRIEST_RAISED, room)
				for k in n:
					var at := e.pos + Vector2.from_angle(w.rng.randf() * TAU) * 14.0
					at.x = clampf(at.x, G.ARENA.position.x + 8, G.ARENA.end.x - 8)
					at.y = clampf(at.y, G.ARENA.position.y + 8, G.ARENA.end.y - 4)
					WorldWaves.spawn_enemy(w, World.SKELETON, 0, at)
				if n > 0:
					w.emit(World.EV_RAISE, e.pos.x, e.pos.y, n, 0)
	e.vel = e.vel.lerp(desired * sm, minf(1.0, dt * 10.0))
	e.pos += (e.vel + e.knock) * dt
	e.knock = e.knock.move_toward(Vector2.ZERO, dt * 600.0)
	# Separation so hordes spread into a crowd instead of a single blob.
	# Half the crowd separates each tick (alternating by id), at double strength: the same spread for half the cost.
	if e.type != World.BAT and e.type != World.WRAITH and (e.id + w._tick) % 2 == 0:
		_separate(w, e)
	var at: Vector2 = e.pos
	var room: Rect2 = G.ARENA
	at.x = clampf(at.x, room.position.x + e.r, room.end.x - e.r)
	at.y = clampf(at.y, room.position.y + e.r, room.end.y - 2)
	e.pos = at
	# Contact damage. Nobody can be touched unless the nearest wizard was close when this update began: an enemy
	# moves a few pixels a step. A mage and the Lich can teleport, so they always check.
	if dist < e.r + World.CONTACT_REACH or e.type == World.MAGE or e.type == World.LICH:
		for p: World.Player in w._plist:
			if p.alive and p.invuln <= 0.0 and p.pos.distance_to(e.pos) < e.r + 5.0:
				var dmg := e.contact
				if (e.type == World.ORC and e.state == 2) or (e.type == World.GARGOYLE and e.state == 1):
					dmg = 2
				WorldPlayers.hurt_player(w, p, dmg)


## Pushes `e` out of the enemies it overlaps, reading the grid cells directly (this runs for half the horde
## every tick, so it avoids _query's array).
static func _separate(w: World, e: World.Enemy) -> void:
	# The position lives in a local and is written back once: reading and writing a field of an object costs about
	# twice a local, and this loop touched e.pos for every neighbour.
	var pos: Vector2 = e.pos
	var er: float = e.r
	var x0 := floori((pos.x - 16.0) / World.CELL)
	var y0 := floori((pos.y - 16.0) / World.CELL)
	for cx: int in range(x0, x0 + 2):
		for cy: int in range(y0, y0 + 2):
			var cell: Array = w._grid.get(Vector2i(cx, cy), World._NO_CELL)
			for o: World.Enemy in cell:
				if o == e or o.dead or o.type == World.BAT or o.entering:
					continue
				var dv: Vector2 = pos - o.pos
				var min_d: float = er + o.r
				var d2: float = dv.length_squared()
				if d2 < min_d * min_d and d2 > 0.0001:
					var dd: float = sqrt(d2)
					pos += dv / dd * (min_d - dd) * (0.5 if o.type != World.LICH else 1.0)
	e.pos = pos


static func _eshot(w: World, kind: int, pos: Vector2, vel: Vector2, r: float) -> void:
	var s := World.EShot.new()
	s.kind = kind
	s.pos = pos
	s.vel = vel
	s.r = r
	w.eshots.append(s)


## A wraith phased out: shots fly through it and nothing hurts it.
static func _faded(w: World, e: World.Enemy) -> bool:
	return e.type == World.WRAITH and e.state == 1


static func _damage_enemy(w: World, e: World.Enemy, dmg: float, slot: int, knock: Vector2) -> void:
	if e.dead or _faded(w, e):
		return
	if e.type == World.GARGOYLE and e.state == 0:
		dmg *= World.STONE_DAMAGE
	var src: World.Player = w.players.get(slot)
	if src:
		dmg *= Upgrades.damage_mul(src.upgrades) * (1.0 + src.armor[Loot.ST_MIGHT] + w.meta_damage)
	w.record.add(slot, "damage", minf(dmg, maxf(0.0, e.hp)))
	w.record.add_source(w.stat_src, minf(dmg, maxf(0.0, e.hp)))
	e.hp -= dmg
	e.flash = 0.07
	e.knock += knock * _heft(w, e)
	w.emit(World.EV_HIT, e.pos.x, e.pos.y - e.r, e.type, slot)
	if e.hp <= 0.0:
		_kill_enemy(w, e, slot)


## How far knockback and pulls move an enemy: the Lich barely, orcs and gargoyles less than the rest.
static func _heft(w: World, e: World.Enemy) -> float:
	return 0.15 if e.type == World.LICH else (0.4 if e.type == World.ORC or e.type == World.GARGOYLE else 1.0)


static func _kill_enemy(w: World, e: World.Enemy, slot: int) -> void:
	e.dead = true
	var p: World.Player = w.players.get(slot)
	var base: int = World.STATS[e.type][3] * (World.ELITE_REWARD if e.elite else 1) * (World.FINAL_REWARD if e.final else 1)
	if p:
		p.combo += 1
		p.combo_t = 2.5
		p.kills += 1
		var mult := 1 + mini(p.combo / 10, 4)
		p.score += base * mult
		if World.COMBO_CALLS.has(p.combo):
			w.emit(World.EV_COMBO, e.pos.x, e.pos.y, p.combo, slot)
		w.record.best(slot, "best_combo", p.combo)
		if p.combo in Results.COMBO_MOMENTS:
			w.record.note(w.wave_time, Results.M_COMBO, slot, p.combo)
		if e.elite:
			w.record.add(slot, "elites", 1)
	w.emit(World.EV_DIE, e.pos.x, e.pos.y - e.r, e.type, slot)
	WorldDrops._drop_xp(w, e.pos, Vector2.from_angle(w.rng.randf() * TAU) * 25.0, World.XP_VALUES[e.type] * (World.ELITE_REWARD if e.elite else 1))
	WorldDrops._roll_card(w, e)
	if e.elite:
		for i in World.ELITE_GEMS:
			WorldDrops._drop(w, World.PK_GEM if i % 2 == 0 else World.PK_COIN, e.pos, Vector2.from_angle(i * TAU / World.ELITE_GEMS) * 70.0)
		WorldDrops._drop(w, World.PK_CHEST, e.pos, Vector2(0, 30), w.tune.chest_life, int(w.tune.elite_chest_luck))
		return
	match e.type:
		World.SLIME:
			for i in 2:
				var m := WorldWaves.spawn_enemy(w, World.MSLIME, 0, e.pos + Vector2(-5 + i * 10, 0))
				m.knock = Vector2(-90 + i * 180, w.rng.randf_range(-40, 40))
			w.emit(World.EV_SPLIT, e.pos.x, e.pos.y - 4, 0, 0)
		World.LICH:
			w.boss = null
			w.liches_slain += 1
			w.record.note(w.wave_time, Results.M_ARCHLICH if e.final else Results.M_LICH, slot)
			for o in w.enemies:
				if not o.dead and o != e:
					o.dead = true
					w.emit(World.EV_DIE, o.pos.x, o.pos.y - o.r, o.type, -1)
			for s in w.eshots:
				s.dead = true
			for i in 14:
				WorldDrops._drop(w, World.PK_GEM if i % 2 == 0 else World.PK_COIN, e.pos, Vector2.from_angle(i * TAU / 14) * 90.0)
			WorldDrops._drop(w, World.PK_POTION, e.pos, Vector2(0, 40))
			for i in w.players.size():
				WorldDrops._drop(w, World.PK_CHEST, e.pos, Vector2.from_angle(PI * 0.5 + (i - (w.players.size() - 1) * 0.5) * 0.7) * 60.0,
					w.tune.chest_life, int(w.tune.boss_chest_luck))
			w.emit(World.EV_BOSSDIE, e.pos.x, e.pos.y - 14, slot, 1 if e.final else 0)
			if e.final:
				w.won = true
				w.victory_t = w.tune.victory_delay
				for q: World.Player in w.players.values():
					q.invuln = maxf(q.invuln, w.tune.victory_delay + 1.0)
				w.emit(World.EV_VICTORY, e.pos.x, e.pos.y, slot, 0)
			w.spawn_queue.clear()
			w.horde_budget = 0.0
			w._next_group = []
			if not e.final and w.tune.lull_seconds > 0.0:
				w.lull_left = w.tune.lull_seconds
				var c := w.party_center()
				w.emit(World.EV_LULL, c.x, c.y, w.lull_left, 0)
			return
	WorldDrops._roll_drop(w, e)


static func _update_eshots(w: World, dt: float) -> void:
	var bounds := G.ARENA.grow(6)
	for s in w.eshots:
		s.life -= dt
		s.pos += s.vel * dt
		if s.life <= 0.0 or not bounds.has_point(s.pos):
			s.dead = true
			continue
		for p in w.players.values():
			if p.alive and p.invuln <= 0.0 and s.pos.distance_to(p.pos + Vector2(0, -6)) < s.r + 4.0:
				s.dead = true
				WorldPlayers.hurt_player(w, p, 1)
				break
