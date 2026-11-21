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
	# The wizard's own cast-rate bonuses never cut a cooldown below Spells.CAST_FLOOR of itself.
	var rate_mul: float = maxf(Spells.CAST_FLOOR, (w.tune.haste_rate_mul if p.haste > 0.0 else 1.0) * Upgrades.cast_mul(p.upgrades)
		* (1.0 - p.armor[Loot.ST_FOCUS])) * w.tune.spell_cd_mul
	for sp in Spells.COUNT:
		var lv := Upgrades.weapon_level(p.upgrades, sp)
		if lv <= 0:
			continue
		# A running timer keeps the fraction of a tick it overshot, so cooldowns are not rounded up to whole
		# ticks; a weapon that waited (no target) is ready at 0 and casts on its full cooldown from then.
		var running := p.cds[sp] > 0.0
		var left: float = p.cds[sp] - dt
		if left > 0.0 or dir == Vector2.ZERO:
			p.cds[sp] = maxf(0.0, left)
			continue
		var evo := Upgrades.evolved(p.upgrades, sp)
		p.cds[sp] = Spells.cooldown(sp, lv, evo) * rate_mul + (left if running else 0.0)
		_cast(w, p, sp, lv, evo, dir)


## Nearest living enemy inside the arena within `radius` of `pos`, or null.
static func _nearest_enemy(w: World, pos: Vector2, radius: float) -> World.Enemy:
	var best: World.Enemy = null
	var bd := radius * radius
	for e in w.enemies:
		if e.dead or e.entering or WorldEnemies._faded(w, e):
			continue
		var d := e.pos.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = e
	return best


## One caster per Spells.STATS "cast" kind. Each takes (w, p, sp, lv, evo, dir, tip, n, dmg); a new kind is one
## function here plus its row in this table and in Spells.STATS.
## How far the staff's tip is from its base (the wizard's hand, 7 px above the feet) along the aim, px.
const STAFF_REACH := 9.0

static var CASTS := {
	"bolt": _cast_bolts,
	"chain": _cast_chain,
	"rune": _cast_rune,
}


static func _cast(w: World, p: World.Player, sp: int, lv: int, evo: bool, dir: Vector2) -> void:
	w.stat_src = sp
	var tip := p.pos + Vector2(0, -7) + dir * STAFF_REACH
	var caster: Callable = CASTS[Spells.cast_kind(sp)]
	caster.call(w, p, sp, lv, evo, dir, tip, Spells.count(sp, lv, evo), Spells.damage(sp, lv, evo))
	w.emit(World.EV_CAST, tip.x, tip.y, sp, p.slot)


## "bolt": `n` projectiles fanned `spread` apart along `dir`, each nudged by the row's jitter.
static func _cast_bolts(w: World, p: World.Player, sp: int, _lv: int, evo: bool, dir: Vector2, tip: Vector2, n: int, dmg: float) -> void:
	var spread := Spells.stat(sp, "spread")
	var speed := Spells.stat(sp, "speed")
	var jitter := Spells.bolt_value(sp, "jitter", evo, 0.0)
	var pierce := int(Spells.evo_value(sp, "pierce", 0.0)) if evo else 0
	for i in n:
		var a := (i - (n - 1) * 0.5) * spread
		if jitter > 0.0:
			a += w.rng.randf_range(-jitter, jitter)
		_shot(w, p.slot, sp, evo, tip, dir.rotated(a) * speed, dmg, pierce)


## "chain": lightning foe to foe, `n` jumps; Tempest casts several chains with a longer reach.
static func _cast_chain(w: World, p: World.Player, sp: int, _lv: int, evo: bool, dir: Vector2, tip: Vector2, n: int, dmg: float) -> void:
	var chains := int(Spells.evo_value(sp, "chains", 1.0)) if evo else 1
	var range_mul := Spells.TEMPEST_RANGE_MUL if evo else 1.0
	var hit := {}
	for c in chains:
		_chain_lightning(w, p.slot, tip, dir.rotated((c - (chains - 1) * 0.5) * 0.5), n, dmg, range_mul, hit)


## The staff's base: where a chain lightning's cone is measured from (its bolt is drawn from the tip).
static func _staff_base(tip: Vector2, dir: Vector2) -> Vector2:
	return tip - dir * STAFF_REACH


## "rune": circles inscribed on the floor.
static func _cast_rune(w: World, p: World.Player, _sp: int, lv: int, evo: bool, dir: Vector2, _tip: Vector2, n: int, dmg: float) -> void:
	_inscribe_runes(w, p, lv, evo, dir, n, dmg)


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


## Lightning from `tip` to the nearest enemy roughly along `dir`, then `jumps - 1` jumps foe to foe. The cone
## and the range are measured from the staff's base, so an enemy touching the wizard (inside the tip) is struck.
## Enemies in `hit` and faded wraiths are skipped, so several chains of one cast find different foes.
static func _chain_lightning(w: World, slot: int, tip: Vector2, dir: Vector2, jumps: int, dmg: float, range_mul: float, hit: Dictionary) -> void:
	var best: World.Enemy = null
	var best_d := Spells.CHAIN_FIRST_RANGE * range_mul
	var base := _staff_base(tip, dir)
	for e in w.enemies:
		if e.dead or hit.has(e.id) or WorldEnemies._faded(w, e):
			continue
		var to := e.pos - base
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
			if hit.has(e.id) or e.dead or WorldEnemies._faded(w, e):
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
			var best: World.Enemy = null
			var bd := home
			for e in w._query(s.pos, home):
				if s.hits.has(e.id) or WorldEnemies._faded(w, e):
					continue
				var d = e.pos.distance_to(s.pos)
				if d < bd:
					bd = d
					best = e
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
	if s.evo and Spells.evo_value(s.spell, "burst", 0.0) > 0.0:
		_frost_burst(w, s, e)
	if s.pierce > 0:
		s.pierce -= 1
		s.hits[e.id] = true
	else:
		s.dead = true


## Comet Rain: a star that hits bursts into ice, slowing and hurting every other enemy nearby.
static func _frost_burst(w: World, s: World.Shot, center: World.Enemy) -> void:
	var radius := Spells.evo_value(s.spell, "burst", 0.0)
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
## blast_reach. An evolution with "chain" (Thunderfire) forks lightning from it to the nearest survivor.
static func _explode(w: World, s: World.Shot) -> void:
	var radius := Spells.bolt_value(s.spell, "blast", s.evo, 0.0)
	var reach := Spells.bolt_value(s.spell, "blast_reach", s.evo, radius)
	var bonus := Spells.bolt_value(s.spell, "blast_bonus", s.evo, 0.0)
	w.emit(World.EV_EXPLODE, s.pos.x, s.pos.y, int(radius), s.owner)
	for e in w._query(s.pos, reach):
		var d = e.pos.distance_to(s.pos)
		if d < radius + e.r:
			WorldEnemies._damage_enemy(w, e, s.dmg + bonus * (1.0 - d / reach), s.owner, (e.pos - s.pos).normalized() * Spells.BLAST_KNOCK)
	var jumps := int(Spells.evo_value(s.spell, "chain", 0.0)) if s.evo else 0
	if jumps > 0:
		var tgt := _nearest_enemy(w, s.pos, Spells.CHAIN_JUMP_RANGE)
		if tgt:
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
