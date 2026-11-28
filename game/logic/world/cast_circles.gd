class_name WorldCastCircles
extends RefCounted
## Circle casts for World: the "rune" and "candle" casters, placing circles, circles ticking and pulling, a
## vigil candle's haste and the lights that heal. Static helpers; the first argument is the World.


## "rune": circles inscribed on the floor. Returns the circles placed.
static func _cast_rune(w: World, p: World.Player, _sp: int, lv: int, evo: int, dir: Vector2, _tip: Vector2, n: int, dmg: float) -> int:
	return _inscribe_runes(w, p, lv, evo, dir, n, dmg)


## "candle": `n` lights (circles of kind Spells.CIRCLE_CANDLE) on the densest clusters within Spells.CANDLE_RANGE.
## Returns the lights set.
static func _cast_candle(w: World, p: World.Player, sp: int, lv: int, evo: int, dir: Vector2, _tip: Vector2, n: int, dmg: float) -> int:
	return _place_circles(w, p, sp, lv, evo, dir, n, dmg, Spells.CANDLE_RANGE, Spells.CANDLE_AIM_DIST, Spells.CIRCLE_CANDLE)


## Inscribes `n` rune circles (see _place_circles) within Spells.RUNE_RANGE of the wizard; returns how many.
static func _inscribe_runes(w: World, p: World.Player, lv: int, evo: int, dir: Vector2, n: int, dmg: float) -> int:
	return _place_circles(w, p, World.SP_RUNE, lv, evo, dir, n, dmg, Spells.RUNE_RANGE, Spells.RUNE_AIM_DIST, Spells.CIRCLE_RUNE)


## Sets `n` circles of spell `sp` (kind `kind`), each on the densest cluster of enemies within `reach` of the
## wizard that no circle of this cast already covers; with no enemy in range, one circle goes `aim_dist` ahead
## along `dir`. Returns the circles set. A circle's radius is its row's times THE EMPRESS's area, read at the cast
## (the clusters are measured with it too); its life is the row's.
static func _place_circles(w: World, p: World.Player, sp: int, lv: int, evo: int, dir: Vector2, n: int, dmg: float,
		reach: float, aim_dist: float, kind: int) -> int:
	var radius := Spells.level_value(sp, "r", lv, evo) * WorldCasting._area(p)
	var near: Array[World.Enemy] = []
	for e: World.Enemy in w._query(p.pos, reach):
		if not e.entering and not WorldEnemies._faded(w, e) and e.pos.distance_to(p.pos) <= reach:
			near.append(e)
	var centres: Array[Vector2] = []
	for i in n:
		var best := Vector2.INF
		var best_n := 0
		var best_d := INF
		for e: World.Enemy in near:
			var covered := false
			for c: Vector2 in centres:
				if c.distance_to(e.pos) < radius * Spells.RUNE_SPACING:
					covered = true
					break
			if covered:
				continue
			var sum := Vector2.ZERO
			var cnt := 0
			for o: World.Enemy in w._query(e.pos, radius):
				if not o.entering and o.pos.distance_to(e.pos) <= radius:
					sum += o.pos
					cnt += 1
			var d := e.pos.distance_squared_to(p.pos)
			if cnt > best_n or (cnt == best_n and d < best_d):
				best_n = cnt
				best_d = d
				best = sum / maxf(1.0, float(cnt))
		if best == Vector2.INF:
			break
		centres.append(best)
	if centres.is_empty():
		centres.append(p.pos + dir * aim_dist)
	for c: Vector2 in centres:
		var rn := World.Rune.new()
		rn.pos = Vector2(clampf(c.x, G.ARENA.position.x + 4.0, G.ARENA.end.x - 4.0),
			clampf(c.y, G.ARENA.position.y + 4.0, G.ARENA.end.y - 4.0))
		rn.r = radius
		rn.life = Spells.level_value(sp, "life", lv, evo)
		rn.tick = Spells.RUNE_ARM
		rn.dmg = dmg
		rn.owner = p.slot
		rn.evo = evo
		rn.pull = Spells.evo_value(sp, "pull", evo, 0.0)
		rn.kind = kind
		w.runes.append(rn)
		w.emit(World.EV_RUNE, rn.pos.x, rn.pos.y, rn.r, p.slot + Spells.evo_bits(evo) + 16 * kind)
	return centres.size()


## Rune circles age, tick damage on every enemy standing in them, and (the Seal of Solomon) pull enemies in.
static func _update_runes(w: World, dt: float) -> void:
	w.stat_src = World.SP_RUNE
	var lights := false
	for c: World.Rune in w.runes:
		c.age += dt
		if c.kind == Spells.CIRCLE_CANDLE:
			lights = true
			_vigil(w, c)
		if c.pull > 0.0:
			var reach := c.r * Spells.SEAL_REACH
			for e: World.Enemy in w._query(c.pos, reach):
				if e.entering or e.dead:
					continue
				var to := c.pos - e.pos
				var d := to.length()
				if d > reach or d < 1.0:
					continue
				e.pos += to / d * minf(d, c.pull * WorldEnemies._heft(w, e) * dt)
		c.tick -= dt
		if c.tick > 0.0 or c.age > c.life:
			continue
		c.tick += Spells.RUNE_TICK
		w.stat_src = World.SP_CANDLE if c.kind == Spells.CIRCLE_CANDLE else World.SP_RUNE
		for e: World.Enemy in w._query(c.pos, c.r + World.CELL * 0.5):
			if e.pos.distance_to(c.pos) <= c.r + e.r * 0.5:
				WorldEnemies._damage_enemy(w, e, c.dmg, c.owner, Vector2.ZERO)
	if lights:
		_light_heals(w, dt)


## A vigil candle's light: every standing hero inside it (the caster too) casts faster for Spells.VIGIL_AFTER s.
static func _vigil(w: World, c: World.Rune) -> void:
	if c.age > c.life:
		return
	for q: World.Player in w._plist:
		if q.alive and not q.down and q.pos.distance_to(c.pos) <= c.r:
			q.vigil = Spells.VIGIL_AFTER


## Seconds between the hearts `p`'s lights heal (the priest's HOLY LIGHT, else CONSECRATION), 0 when they heal none.
static func _heal_every(p: World.Player) -> float:
	if p.class_weapon == World.SP_CANDLE and Classes.skin_value(p.skin, "heal_every") > 0.0:
		return Classes.skin_value(p.skin, "heal_every")
	var evo := Upgrades.evo_of(p.upgrades, World.SP_CANDLE)
	if evo > 0:
		return Spells.evo_value(World.SP_CANDLE, "heal_every", evo, 0.0)
	return 0.0


## Lights that heal: while a healer has a light burning her timer runs; once it is due, the most hurt standing hero
## inside one of her lights (fewest hearts, then the lower slot) heals (HOLY LIGHT's `heal`, else one heart).
static func _light_heals(w: World, dt: float) -> void:
	for p: World.Player in w._plist:
		var every := _heal_every(p)
		if every <= 0.0:
			continue
		var best: World.Player = null
		var burning := false
		for c: World.Rune in w.runes:
			if c.kind != Spells.CIRCLE_CANDLE or c.owner != p.slot or c.age > c.life:
				continue
			burning = true
			for q: World.Player in w._plist:
				if q.alive and not q.down and q.hp < q.max_hp and q.pos.distance_to(c.pos) <= c.r \
						and (best == null or q.hp < best.hp or (q.hp == best.hp and q.slot < best.slot)):
					best = q
		if not burning:
			continue
		p.light_heal_t = minf(every, p.light_heal_t + dt)
		if best == null or p.light_heal_t < every:
			continue
		p.light_heal_t = 0.0
		var hearts := int(Classes.skin_value(p.skin, "heal", 1.0)) if p.class_weapon == World.SP_CANDLE else 1
		var got := mini(maxi(1, hearts), best.max_hp - best.hp)
		best.hp += got
		w.emit(World.EV_HEAL, best.pos.x, best.pos.y - 6, best.slot, got)
