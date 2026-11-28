class_name WorldCastBolts
extends RefCounted
## Bolt casts for World: the "bolt" caster, shots in flight (homing, bursting), what a shot does on a hit
## (frost, splinters, blasts). Static helpers; the first argument is the World.


## "bolt": `n` projectiles fanned `spread` apart along `dir`, each nudged by the row's jitter (THE STAR's missiles are
## more of them: a wider fan). Returns `n`, every one sent.
static func _cast_bolts(w: World, p: World.Player, sp: int, _lv: int, evo: int, dir: Vector2, tip: Vector2, n: int, dmg: float) -> int:
	var spread := Spells.stat(sp, "spread")
	var speed := Spells.stat(sp, "speed")
	var jitter := Spells.bolt_value(sp, "jitter", evo, 0.0)
	var pierce := int(Spells.bolt_value(sp, "pierce", evo, 0.0))
	# A class skin's range (the LONGBOW) stretches the flight; every other bolt flies its row's life.
	var reach := Classes.skin_value(p.skin, "range") if sp == p.class_weapon else 0.0
	for i in n:
		var a := (i - (n - 1) * 0.5) * spread
		if jitter > 0.0:
			a += w.rng.randf_range(-jitter, jitter)
		var s := _shot(w, p.slot, sp, evo, tip, dir.rotated(a) * speed, dmg, pierce)
		if reach > 0.0:
			s.life = reach / speed
	return n


static func _shot(w: World, slot: int, sp: int, evo: int, pos: Vector2, vel: Vector2, dmg: float, pierce: int) -> World.Shot:
	var s := World.Shot.new()
	s.pos = pos
	s.vel = vel
	s.spell = sp
	s.evo = evo
	s.kind = Spells.shot_kind(sp, evo)
	s.dmg = dmg
	s.owner = slot
	s.r = Spells.stat(sp, "r")
	s.life = Spells.stat(sp, "life")
	s.pierce = pierce
	w.shots.append(s)
	return s


## Bolts fly, home in (a row with "home"), burst when they run out (a row with "blast") and hit the first enemy
## they touch.
static func _update_shots(w: World, dt: float) -> void:
	var bounds := G.ARENA.grow(4)
	for s in w.shots:
		if s.dead:
			continue
		w.stat_src = s.spell
		s.life -= dt
		var home := Spells.bolt_value(s.spell, "home", s.evo, 0.0)
		if home > 0.0:
			var best := _homing_target(w, s, home)
			if best:
				var speed := Spells.stat(s.spell, "speed")
				var want := (best.pos + Vector2(0, -4) - s.pos).normalized() * speed
				s.vel = s.vel.lerp(want, minf(1.0, dt * Spells.bolt_value(s.spell, "turn", s.evo, 0.0))).normalized() * speed
		s.pos += s.vel * dt
		if s.life <= 0.0 or not bounds.has_point(s.pos):
			s.dead = true
			if Spells.bolt_value(s.spell, "blast", s.evo, 0.0) > 0.0:
				_explode(w, s)
			continue
		for e in w._query(s.pos, 20.0):
			if e.dead or s.hits.has(e.id) or WorldEnemies._faded(w, e):
				continue
			var hit_pos = e.pos + Vector2(0, -e.r * 0.8)
			if s.pos.distance_to(hit_pos) < s.r + e.r + 1.0:
				_shot_hit(w, s, e)
				break


## The nearest enemy within `home` of homing shot `s` that it has not hit and that has not faded, or null. It looks
## close by first and widens only when it finds nobody near enough: a foe found well inside a ring is nearer than
## every foe outside it, so the answer (ties too: _query walks the same cells in the same order) is that of one wide
## search, for a fraction of the work in a crowd. One wide search per star per step was most of a step at the enemy
## cap. The grid is a step old, so a ring only counts up to HOME_RING_SLACK short of its edge: a foe that walked in
## since the grid was built is still found.
static func _homing_target(w: World, s: World.Shot, home: float) -> World.Enemy:
	var ring := minf(home, Spells.HOME_RING)
	while true:
		var best: World.Enemy = null
		var bd := home
		for e: World.Enemy in w._query(s.pos, ring):
			if s.hits.has(e.id) or WorldEnemies._faded(w, e):
				continue
			var d := e.pos.distance_to(s.pos)
			if d < bd:
				bd = d
				best = e
		if ring >= home or (best != null and bd <= ring - Spells.HOME_RING_SLACK):
			return best
		ring = minf(home, ring * Spells.HOME_RING_GROW)
	return null


static func _shot_hit(w: World, s: World.Shot, e: World.Enemy) -> void:
	if Spells.bolt_value(s.spell, "blast", s.evo, 0.0) > 0.0:
		s.dead = true
		_explode(w, s)
		return
	var slow := Spells.bolt_value(s.spell, "slow", s.evo, 0.0)
	if slow > 0.0:
		if _frost_hit(w, e, slow, s.dmg, s.owner, s.vel.normalized() * Spells.BOLT_KNOCK):
			w.emit(World.EV_FROST, s.pos.x, s.pos.y, 0, 0)
	else:
		WorldEnemies._damage_enemy(w, e, s.dmg, s.owner, s.vel.normalized() * Spells.BOLT_KNOCK)
	if Spells.evo_value(s.spell, "burst", s.evo, 0.0) > 0.0:
		_frost_burst(w, s, e)
	if not s.splinter and Spells.evo_value(s.spell, "splinter", s.evo, 0.0) > 0.0:
		_splinter(w, s, e)
	if s.pierce != 0:
		if s.pierce > 0:
			s.pierce -= 1
		s.hits[e.id] = true
	else:
		s.dead = true


## Ossuary Lance: splinters fly sideways (square to the spear, both ways in turn) from the foe it hit, each a
## Spells.SPLINTER_DMG share of the spear's damage; they never hit that foe and never splinter again. Their flight
## (Spells.SPLINTER_LIFE at the spear's speed) is an area THE EMPRESS widens, read at the hit.
static func _splinter(w: World, s: World.Shot, e: World.Enemy) -> void:
	var n := int(Spells.evo_value(s.spell, "splinter", s.evo, 0.0))
	var side := s.vel.orthogonal()
	for i in n:
		var v := side * (1.0 if i % 2 == 0 else -1.0)
		var sp := _shot(w, s.owner, s.spell, s.evo, s.pos, v.rotated((i / 2) * 0.3), s.dmg * Spells.SPLINTER_DMG, 0)
		sp.kind = Spells.shot_kind(s.spell, 0)
		sp.splinter = true
		sp.life = Spells.SPLINTER_LIFE * WorldCasting._area(w.players.get(s.owner))
		sp.hits[e.id] = true


## Comet Rain: a star that hits bursts into ice, slowing and hurting every other enemy nearby (the burst's radius
## times THE EMPRESS's area, read at the hit; EV_FROST carries it to the view).
static func _frost_burst(w: World, s: World.Shot, center: World.Enemy) -> void:
	var radius := Spells.evo_value(s.spell, "burst", s.evo, 0.0) * WorldCasting._area(w.players.get(s.owner))
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


## A blast: every enemy within the row's blast radius takes the bolt's damage plus a bonus that fades over
## blast_reach; THE EMPRESS's area widens both, read at the hit (EV_EXPLODE carries the radius to the view). An
## evolution with "chain" (Thunderfire) forks lightning from it to the nearest survivor: that reach is not an area.
static func _explode(w: World, s: World.Shot) -> void:
	var area := WorldCasting._area(w.players.get(s.owner))
	var radius := Spells.bolt_value(s.spell, "blast", s.evo, 0.0)
	var reach := Spells.bolt_value(s.spell, "blast_reach", s.evo, radius) * area
	radius *= area
	var bonus := Spells.bolt_value(s.spell, "blast_bonus", s.evo, 0.0)
	w.emit(World.EV_EXPLODE, s.pos.x, s.pos.y, int(radius), s.owner)
	for e in w._query(s.pos, reach):
		var d = e.pos.distance_to(s.pos)
		if d < radius + e.r:
			WorldEnemies._damage_enemy(w, e, s.dmg + bonus * (1.0 - d / reach), s.owner, (e.pos - s.pos).normalized() * Spells.BLAST_KNOCK)
	var jumps := int(Spells.evo_value(s.spell, "chain", s.evo, 0.0))
	if jumps > 0:
		var tgt := WorldCasting._nearest_enemy(w, s.pos, Spells.CHAIN_JUMP_RANGE)
		if tgt:
			WorldCastChain._zap_chain(w, s.owner, s.pos, tgt, jumps, s.dmg * Spells.CHAIN_FALLOFF, Spells.CHAIN_JUMP_RANGE, {}, Vector2.ZERO)
