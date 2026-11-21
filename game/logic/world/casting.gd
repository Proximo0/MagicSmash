class_name WorldCasting
extends RefCounted
## Spells for World: auto-casting, shots, chain lightning, rune circles and what shots do on a hit. Static helpers; the first argument is the World.


## Every owned spell weapon casts on its own cooldown: along the aim stick when it is held, otherwise at the
## nearest enemy within tune.auto_aim_range. Nothing in range and no aim: the weapons wait, ready.
static func _auto_cast(w: World, p: World.Player, dt: float, aim: Vector2) -> void:
	var dir := Vector2.ZERO
	if aim.length() > 0.1:
		dir = aim.normalized()
	else:
		var tgt := _nearest_enemy(w, p.pos, w.tune.auto_aim_range)
		if tgt:
			dir = (tgt.pos + Vector2(0, -4) - (p.pos + Vector2(0, -7))).normalized()
			p.aim = dir
	var rate_mul: float = (w.tune.haste_rate_mul if p.haste > 0.0 else 1.0) * Upgrades.cast_mul(p.upgrades) * w.tune.spell_cd_mul \
		* (1.0 - p.armor[Loot.ST_FOCUS])
	for sp in Spells.COUNT:
		var lv := Upgrades.weapon_level(p.upgrades, sp)
		if lv <= 0:
			continue
		p.cds[sp] = maxf(0.0, p.cds[sp] - dt)
		if p.cds[sp] > 0.0 or dir == Vector2.ZERO:
			continue
		var evo := Upgrades.evolved(p.upgrades, sp)
		p.cds[sp] = Spells.cooldown(sp, lv, evo) * rate_mul
		_cast(w, p, sp, lv, evo, dir)


## Nearest living enemy inside the arena within `radius` of `pos`, or null.
static func _nearest_enemy(w: World, pos: Vector2, radius: float) -> World.Enemy:
	var best: World.Enemy = null
	var bd := radius * radius
	for e in w.enemies:
		if e.dead or e.entering:
			continue
		var d := e.pos.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = e
	return best


static func _cast(w: World, p: World.Player, sp: int, lv: int, evo: bool, dir: Vector2) -> void:
	w.stat_src = sp
	var tip := p.pos + Vector2(0, -7) + dir * 9.0
	var n := Spells.count(sp, lv, evo)
	var dmg := Spells.damage(sp, lv, evo)
	if sp == World.SP_RUNE:
		_inscribe_runes(w, p, lv, evo, dir, n, dmg)
	elif sp == World.SP_STORM:
		var chains := int(Spells.evo_value(sp, "chains", 1.0)) if evo else 1
		var range_mul := Spells.TEMPEST_RANGE_MUL if evo else 1.0
		var hit := {}
		for c in chains:
			_chain_lightning(w, p.slot, tip, dir.rotated((c - (chains - 1) * 0.5) * 0.5), n, dmg, range_mul, hit)
	else:
		var spread := Spells.stat(sp, "spread")
		var speed := Spells.stat(sp, "speed")
		var pierce := int(Spells.evo_value(sp, "pierce", 0.0)) if evo else 0
		for i in n:
			var a := (i - (n - 1) * 0.5) * spread
			if sp == World.SP_ARCANE:
				a += w.rng.randf_range(-0.04, 0.04)
			_shot(w, p.slot, sp, evo, tip, dir.rotated(a) * speed, dmg, pierce)
	w.emit(World.EV_CAST, tip.x, tip.y, sp, p.slot)


static func _shot(w: World, slot: int, sp: int, evo: bool, pos: Vector2, vel: Vector2, dmg: float, pierce: int) -> void:
	var s := World.Shot.new()
	s.pos = pos
	s.vel = vel
	s.spell = sp
	s.evo = evo
	s.kind = sp + (Spells.COUNT if evo else 0)
	s.dmg = dmg
	s.owner = slot
	s.r = Spells.stat(sp, "r")
	s.life = Spells.stat(sp, "life")
	s.pierce = pierce
	w.shots.append(s)


## Inscribes `n` rune circles, each on the densest cluster of enemies within Spells.RUNE_RANGE of the wizard
## that no circle of this cast already covers; with no enemy in range, one circle goes ahead along `dir`.
static func _inscribe_runes(w: World, p: World.Player, lv: int, evo: bool, dir: Vector2, n: int, dmg: float) -> void:
	var radius := Spells.level_value(World.SP_RUNE, "r", lv, evo)
	var near: Array[World.Enemy] = []
	for e: World.Enemy in w._query(p.pos, Spells.RUNE_RANGE):
		if not e.entering and not WorldEnemies._faded(w, e) and e.pos.distance_to(p.pos) <= Spells.RUNE_RANGE:
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
		centres.append(p.pos + dir * Spells.RUNE_AIM_DIST)
	for c: Vector2 in centres:
		var rn := World.Rune.new()
		rn.pos = Vector2(clampf(c.x, G.ARENA.position.x + 4.0, G.ARENA.end.x - 4.0),
			clampf(c.y, G.ARENA.position.y + 4.0, G.ARENA.end.y - 4.0))
		rn.r = radius
		rn.life = Spells.level_value(World.SP_RUNE, "life", lv, evo)
		rn.tick = Spells.RUNE_ARM
		rn.dmg = dmg
		rn.owner = p.slot
		rn.evo = evo
		rn.pull = Spells.evo_value(World.SP_RUNE, "pull", 0.0) if evo else 0.0
		w.runes.append(rn)
		w.emit(World.EV_RUNE, rn.pos.x, rn.pos.y, rn.r, p.slot + (8 if evo else 0))


## Lightning from `tip` to the nearest enemy roughly along `dir`, then `jumps - 1` jumps foe to foe.
## Enemies in `hit` are skipped, so several chains of one cast find different foes.
static func _chain_lightning(w: World, slot: int, tip: Vector2, dir: Vector2, jumps: int, dmg: float, range_mul: float, hit: Dictionary) -> void:
	var best: World.Enemy = null
	var best_d := Spells.CHAIN_FIRST_RANGE * range_mul
	for e in w.enemies:
		if e.dead or hit.has(e.id):
			continue
		var to := e.pos - tip
		var d := to.length()
		if d < best_d and to.normalized().dot(dir) > 0.6:
			best_d = d
			best = e
	if best == null:
		w.emit(World.EV_ZAP, tip.x, tip.y, PackedVector2Array([tip, tip + dir * Spells.CHAIN_JUMP_RANGE * range_mul]), slot)
		return
	_zap_chain(w, slot, tip, best, jumps, dmg, Spells.CHAIN_JUMP_RANGE * range_mul, hit, dir)


## Lightning from `from` through `first` and on to the nearest unhit enemy within `jump_range`, up to `jumps` foes.
static func _zap_chain(w: World, slot: int, from: Vector2, first: World.Enemy, jumps: int, dmg: float, jump_range: float, hit: Dictionary, push: Vector2) -> void:
	var pts := PackedVector2Array([from])
	var cur := first
	for i in jumps:
		pts.append(cur.pos + Vector2(0, -4))
		hit[cur.id] = true
		WorldEnemies._damage_enemy(w, cur, dmg, slot, push * 40.0)
		var nxt: World.Enemy = null
		var nd := jump_range
		for e in w._query(cur.pos, jump_range):
			if hit.has(e.id) or e.dead:
				continue
			var d: float = e.pos.distance_to(cur.pos)
			if d < nd:
				nd = d
				nxt = e
		if nxt == null:
			break
		cur = nxt
		dmg *= Spells.CHAIN_FALLOFF
	w.emit(World.EV_ZAP, from.x, from.y, pts, slot)


## The main spell is the highest weapon (an evolved one beats any level); ties go to the later spell.
static func _refresh_spell(w: World, p: World.Player) -> void:
	var best := -1
	for sp in Spells.COUNT:
		var lv := _weapon_snap(w, p, sp)
		if lv > 0 and lv >= best:
			best = lv
			p.spell = sp


## Weapon level as sent in snapshots: 0 not owned, 1..MAX_LEVEL, MAX_LEVEL + 1 evolved.
static func _weapon_snap(w: World, p: World.Player, sp: int) -> int:
	if Upgrades.evolved(p.upgrades, sp):
		return Spells.MAX_LEVEL + 1
	return Upgrades.weapon_level(p.upgrades, sp)


static func _update_shots(w: World, dt: float) -> void:
	var bounds := G.ARENA.grow(4)
	for s in w.shots:
		if s.dead:
			continue
		w.stat_src = s.spell
		s.life -= dt
		if s.spell == World.SP_STAR:
			var best: World.Enemy = null
			var bd := 160.0
			for e in w._query(s.pos, 160.0):
				if s.hits.has(e.id):
					continue
				var d = e.pos.distance_to(s.pos)
				if d < bd:
					bd = d
					best = e
			if best:
				var speed := Spells.stat(World.SP_STAR, "speed")
				var want := (best.pos + Vector2(0, -4) - s.pos).normalized() * speed
				s.vel = s.vel.lerp(want, minf(1.0, dt * 5.5)).normalized() * speed
		s.pos += s.vel * dt
		if s.life <= 0.0 or not bounds.has_point(s.pos):
			s.dead = true
			if s.spell == World.SP_FIRE:
				_explode(w, s)
			continue
		for e in w._query(s.pos, 20.0):
			if e.dead or s.hits.has(e.id) or WorldEnemies._faded(w, e):
				continue
			var hit_pos = e.pos + Vector2(0, -e.r * 0.8)
			if s.pos.distance_to(hit_pos) < s.r + e.r + 1.0:
				_shot_hit(w, s, e)
				break


static func _shot_hit(w: World, s: World.Shot, e: World.Enemy) -> void:
	if s.spell == World.SP_FIRE:
		s.dead = true
		_explode(w, s)
		return
	if s.spell == World.SP_FROST:
		var slow := Spells.evo_value(World.SP_FROST, "slow", Spells.FROST_SLOW) if s.evo else Spells.FROST_SLOW
		if _frost_hit(w, e, slow, s.dmg, s.owner, s.vel.normalized() * 70.0):
			w.emit(World.EV_FROST, s.pos.x, s.pos.y, 0, 0)
	else:
		WorldEnemies._damage_enemy(w, e, s.dmg, s.owner, s.vel.normalized() * 70.0)
	if s.evo and s.spell == World.SP_STAR:
		_frost_burst(w, s, e)
	if s.pierce > 0:
		s.pierce -= 1
		s.hits[e.id] = true
	else:
		s.dead = true


## Comet Rain: a star that hits bursts into ice, slowing and hurting every other enemy nearby.
static func _frost_burst(w: World, s: World.Shot, center: World.Enemy) -> void:
	var radius := Spells.evo_value(World.SP_STAR, "burst", 0.0)
	w.emit(World.EV_FROST, s.pos.x, s.pos.y, radius, 0)
	for e in w._query(s.pos, radius + 8.0):
		if e == center or e.dead or e.pos.distance_to(s.pos) > radius + e.r:
			continue
		_frost_hit(w, e, Spells.FROST_SLOW, s.dmg * Spells.BURST_DMG, s.owner, (e.pos - s.pos).normalized() * 60.0)


## A frost hit: the slow is on before the damage (a kill by frost counts as frosted: a bloat makes no blast) and is
## taken back when the hit did nothing (a guard's shield, a faded wraith). True when it landed.
static func _frost_hit(w: World, e: World.Enemy, slow: float, dmg: float, slot: int, knock: Vector2) -> bool:
	var was := e.slow
	var hp := e.hp
	e.slow = slow
	WorldEnemies._damage_enemy(w, e, dmg, slot, knock)
	if e.dead or e.hp < hp:
		return true
	e.slow = was
	return false


static func _explode(w: World, s: World.Shot) -> void:
	w.emit(World.EV_EXPLODE, s.pos.x, s.pos.y, 28, s.owner)
	for e in w._query(s.pos, 40.0):
		var d = e.pos.distance_to(s.pos)
		if d < 28.0 + e.r:
			WorldEnemies._damage_enemy(w, e, s.dmg + 1.5 * (1.0 - d / 40.0), s.owner, (e.pos - s.pos).normalized() * 160.0)
	if s.evo:
		# Thunderfire: lightning forks from the blast to the nearest survivor.
		var tgt := _nearest_enemy(w, s.pos, Spells.CHAIN_JUMP_RANGE)
		if tgt:
			var jumps := int(Spells.evo_value(World.SP_FIRE, "chain", 0.0))
			_zap_chain(w, s.owner, s.pos, tgt, jumps, s.dmg * Spells.CHAIN_FALLOFF, Spells.CHAIN_JUMP_RANGE, {}, Vector2.ZERO)


## Rune circles age, tick damage on every enemy standing in them, and (the Seal of Solomon) pull enemies in.
static func _update_runes(w: World, dt: float) -> void:
	w.stat_src = World.SP_RUNE
	for c: World.Rune in w.runes:
		c.age += dt
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
		for e: World.Enemy in w._query(c.pos, c.r + World.CELL * 0.5):
			if e.pos.distance_to(c.pos) <= c.r + e.r * 0.5:
				WorldEnemies._damage_enemy(w, e, c.dmg, c.owner, Vector2.ZERO)
