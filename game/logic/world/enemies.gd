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
	var desired := Brains.think(w, e, dt, tgt, dirv, dist)
	e.vel = e.vel.lerp(desired * sm, minf(1.0, dt * 10.0))
	e.pos += (e.vel + e.knock) * dt
	e.knock = e.knock.move_toward(Vector2.ZERO, dt * 600.0)
	# Separation so hordes spread into a crowd instead of a single blob.
	# Half the crowd separates each tick (alternating by id), at double strength: the same spread for half the cost.
	if e.flags & (Bestiary.F_NO_SEP | Bestiary.F_ANCHORED) == 0 and (e.id + w._tick) % 2 == 0:
		_separate(w, e)
	var at: Vector2 = e.pos
	var room: Rect2 = G.ARENA
	at.x = clampf(at.x, room.position.x + e.r, room.end.x - e.r)
	at.y = clampf(at.y, room.position.y + e.r, room.end.y - 2)
	e.pos = at
	# Contact damage. Nobody can be touched unless the nearest wizard was close when this update began: an enemy
	# moves a few pixels a step. A kind that can teleport (F_BLINK: a mage, the Lich) always checks.
	if dist < e.r + World.CONTACT_REACH or e.flags & Bestiary.F_BLINK:
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
				if o == e or o.dead or o.flags & Bestiary.F_NO_BLOCK or o.entering:
					continue
				var dv: Vector2 = pos - o.pos
				var min_d: float = er + o.r
				var d2: float = dv.length_squared()
				if d2 < min_d * min_d and d2 > 0.0001:
					var dd: float = sqrt(d2)
					pos += dv / dd * (min_d - dd) * (0.5 if o.flags & Bestiary.F_BOSS == 0 else 1.0)
	e.pos = pos


## A new enemy shot, or null past Bestiary.ESHOT_CAP (the shot is dropped).
static func _eshot(w: World, kind: int, pos: Vector2, vel: Vector2, r: float) -> World.EShot:
	if w.eshots.size() >= Bestiary.ESHOT_CAP:
		return null
	var s := World.EShot.new()
	s.kind = kind
	s.pos = pos
	s.vel = vel
	s.r = r
	w.eshots.append(s)
	return s


## A wraith phased out, or any cloaked enemy: shots fly through it and nothing hurts it.
static func _faded(w: World, e: World.Enemy) -> bool:
	return e.cloak or (e.type == World.WRAITH and e.state == 1)


## `sure`: a hit that ignores facing and shields (the nova, hazards); see Brains.filter_damage.
static func _damage_enemy(w: World, e: World.Enemy, dmg: float, slot: int, knock: Vector2, sure: bool = false) -> void:
	if w.phase == World.PH_GAMEOVER:
		return # the run is over: no kill may turn it into a victory or add to the score
	if e.dead or _faded(w, e):
		return
	dmg = Brains.filter_damage(w, e, dmg, knock, sure)
	if dmg < 0.0:
		return
	var src: World.Player = w.players.get(slot)
	if src:
		dmg *= Upgrades.damage_mul(src.upgrades) * (1.0 + src.armor[Loot.ST_MIGHT] + w.meta_damage)
	w.record.add(slot, "damage", minf(dmg, maxf(0.0, e.hp)))
	w.record.add_source(w.stat_src, minf(dmg, maxf(0.0, e.hp)))
	w.record.add_slot_source(slot, w.stat_src, minf(dmg, maxf(0.0, e.hp)))
	e.hp -= dmg
	e.flash = 0.07
	e.knock += knock * _heft(w, e)
	w.emit(World.EV_HIT, e.pos.x, e.pos.y - e.r, e.type, slot)
	if e.hp <= 0.0:
		_kill_enemy(w, e, slot)


## How far knockback and pulls move an enemy (Bestiary.K_HEFT): the Lich barely, orcs and gargoyles less than the rest.
static func _heft(w: World, e: World.Enemy) -> float:
	return Bestiary.KINDS[e.type][Bestiary.K_HEFT]


static func _kill_enemy(w: World, e: World.Enemy, slot: int) -> void:
	e.dead = true
	var p: World.Player = w.players.get(slot)
	var base: int = Bestiary.KINDS[e.type][Bestiary.K_SCORE] * (World.ELITE_REWARD if e.elite else 1) * (World.FINAL_REWARD if e.final else 1)
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
	WorldDrops._drop_xp(w, e.pos, Vector2.from_angle(w.rng.randf() * TAU) * 25.0, Bestiary.KINDS[e.type][Bestiary.K_XP] * (World.ELITE_REWARD if e.elite else 1))
	WorldDrops._roll_card(w, e)
	if e.elite:
		for i in World.ELITE_GEMS:
			WorldDrops._drop(w, World.PK_GEM if i % 2 == 0 else World.PK_COIN, e.pos, Vector2.from_angle(i * TAU / World.ELITE_GEMS) * 70.0)
		WorldDrops._drop(w, World.PK_CHEST, e.pos, Vector2(0, 30), w.tune.chest_life, int(w.tune.elite_chest_luck))
		WorldLevels._drop_party_tome(w, e.pos, WorldLevels.PARTY_TOME_ELITE)
		return
	if Brains.on_death(w, e, slot):
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
