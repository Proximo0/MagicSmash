class_name WorldCasting
extends RefCounted
## Spells for World: auto-casting, shots, chain lightning, rune circles and candles, the sweep, what shots do on a
## hit and JUSTICE's bursts. Static helpers; the first argument is the World.


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
	# The wizard's own cast-rate bonuses never cut a cooldown below Spells.CAST_FLOOR of itself. The cast-speed
	# bonuses (THE LOVERS, a vigil candle) add up and divide the cooldown (exactly 1 without them).
	var rate_mul: float = maxf(Spells.CAST_FLOOR, (w.tune.haste_rate_mul if p.haste > 0.0 else 1.0) * Upgrades.cast_mul(p.upgrades)
		* (1.0 - p.armor[Loot.ST_FOCUS]) / (1.0 + _cast_speed(w, p))) * w.tune.spell_cd_mul
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
		var cast_dir := dir
		if Spells.cast_kind(sp) == "sweep":
			# A sweep waits, ready, until a foe is within its reach, and swings at the nearest one (or along the aim).
			cast_dir = _sweep_dir(w, p, sp, aim)
			if cast_dir == Vector2.ZERO:
				p.cds[sp] = 0.0
				continue
		var evo := Upgrades.evolved(p.upgrades, sp)
		p.cds[sp] = Spells.cooldown(sp, lv, evo) * rate_mul + (left if running else 0.0)
		_cast(w, p, sp, lv, evo, cast_dir)


## Where a sweep of `sp` swings: along the aim stick when it is held and a foe stands in that arc, else at the
## nearest foe the swing can reach (the same reach test as _cast_sweep); ZERO when it can reach none (it does not
## swing at the air).
static func _sweep_dir(w: World, p: World.Player, sp: int, aim: Vector2) -> Vector2:
	var reach := Spells.stat(sp, "r")
	var half := Spells.stat(sp, "arc") * 0.5
	var from := p.pos + Vector2(0, -4)
	var held := aim.length() > 0.1
	var want := aim.normalized() if held else Vector2.ZERO
	var best := Vector2.ZERO
	var best_d := INF
	for e: World.Enemy in w._query(from, reach + World.CELL * 0.5):
		if e.dead or e.entering or WorldEnemies._faded(w, e):
			continue
		var to := e.pos - from
		var d := to.length()
		if d - e.r > reach:
			continue
		if held and (d <= e.r or absf(want.angle_to(to)) <= half):
			return want
		if d < best_d:
			best_d = d
			best = to / d if d > 0.01 else Vector2.RIGHT
	return best


## Cast speed added to a wizard's own (0 without any): THE LOVERS (near a standing ally, or half alone) plus
## Spells.VIGIL_HASTE while a vigil candle's light still hastens her.
static func _cast_speed(w: World, p: World.Player) -> float:
	var out := Spells.VIGIL_HASTE if p.vigil > 0.0 else 0.0
	if Upgrades.level_of(p.upgrades, Upgrades.LOVERS) > 0:
		var together := false
		for q: World.Player in w._plist:
			if q != p and q.alive and not q.down and q.pos.distance_to(p.pos) <= Upgrades.LOVERS_RANGE:
				together = true
				break
		out += Upgrades.lovers_bonus(p.upgrades, together)
	return out


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
	"candle": _cast_candle,
	"sweep": _cast_sweep,
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


## "candle": `n` lights (circles of kind Spells.CIRCLE_CANDLE) on the densest clusters within Spells.CANDLE_RANGE.
static func _cast_candle(w: World, p: World.Player, sp: int, lv: int, evo: bool, dir: Vector2, _tip: Vector2, n: int, dmg: float) -> void:
	_place_circles(w, p, sp, lv, evo, dir, n, dmg, Spells.CANDLE_RANGE, Spells.CANDLE_AIM_DIST, Spells.CIRCLE_CANDLE)


## "sweep": one swing of an arc `arc` radians wide reaching `r` px along `dir`; every enemy it reaches is hit once
## and knocked back (EV_SWEEP draws it).
static func _cast_sweep(w: World, p: World.Player, sp: int, _lv: int, _evo: bool, dir: Vector2, _tip: Vector2, _n: int, dmg: float) -> void:
	var reach := Spells.stat(sp, "r")
	var half := Spells.stat(sp, "arc") * 0.5
	var from := p.pos + Vector2(0, -4)
	for e: World.Enemy in w._query(from, reach + World.CELL * 0.5):
		if e.dead or e.entering or WorldEnemies._faded(w, e):
			continue
		var to := e.pos - from
		var d := to.length()
		if d - e.r > reach or (d > e.r and absf(dir.angle_to(to)) > half):
			continue
		WorldEnemies._damage_enemy(w, e, dmg, p.slot, (to / maxf(d, 0.01)) * Spells.SWEEP_KNOCK)
	w.emit(World.EV_SWEEP, from.x, from.y, dir.angle(), p.slot)


static func _shot(w: World, slot: int, sp: int, evo: bool, pos: Vector2, vel: Vector2, dmg: float, pierce: int) -> World.Shot:
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


## Inscribes `n` rune circles (see _place_circles) within Spells.RUNE_RANGE of the wizard.
static func _inscribe_runes(w: World, p: World.Player, lv: int, evo: bool, dir: Vector2, n: int, dmg: float) -> void:
	_place_circles(w, p, World.SP_RUNE, lv, evo, dir, n, dmg, Spells.RUNE_RANGE, Spells.RUNE_AIM_DIST, Spells.CIRCLE_RUNE)


## Sets `n` circles of spell `sp` (kind `kind`), each on the densest cluster of enemies within `reach` of the
## wizard that no circle of this cast already covers; with no enemy in range, one circle goes `aim_dist` ahead
## along `dir`.
static func _place_circles(w: World, p: World.Player, sp: int, lv: int, evo: bool, dir: Vector2, n: int, dmg: float,
		reach: float, aim_dist: float, kind: int) -> void:
	var radius := Spells.level_value(sp, "r", lv, evo)
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
		rn.pull = Spells.evo_value(sp, "pull", 0.0) if evo else 0.0
		rn.kind = kind
		w.runes.append(rn)
		w.emit(World.EV_RUNE, rn.pos.x, rn.pos.y, rn.r, p.slot + (8 if evo else 0) + 16 * kind)


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
	if s.evo and Spells.evo_value(s.spell, "burst", 0.0) > 0.0:
		_frost_burst(w, s, e)
	if s.evo and not s.splinter and Spells.evo_value(s.spell, "splinter", 0.0) > 0.0:
		_splinter(w, s, e)
	if s.pierce != 0:
		if s.pierce > 0:
			s.pierce -= 1
		s.hits[e.id] = true
	else:
		s.dead = true


## Ossuary Lance: splinters fly sideways (square to the spear, both ways in turn) from the foe it hit, each a
## Spells.SPLINTER_DMG share of the spear's damage; they never hit that foe and never splinter again.
static func _splinter(w: World, s: World.Shot, e: World.Enemy) -> void:
	var n := int(Spells.evo_value(s.spell, "splinter", 0.0))
	var side := s.vel.orthogonal()
	for i in n:
		var v := side * (1.0 if i % 2 == 0 else -1.0)
		var sp := _shot(w, s.owner, s.spell, s.evo, s.pos, v.rotated((i / 2) * 0.3), s.dmg * Spells.SPLINTER_DMG, 0)
		sp.kind = Spells.shot_kind(s.spell, false)
		sp.splinter = true
		sp.life = Spells.SPLINTER_LIFE
		sp.hits[e.id] = true


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
	if Upgrades.evolved(p.upgrades, World.SP_CANDLE):
		return Spells.evo_value(World.SP_CANDLE, "heal_every", 0.0)
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


## JUSTICE: a foe slain by a wizard holding it may burst (queued in w.bursts, set off by _update_bursts). Bosses
## and foes slain by a burst never burst.
static func _justice(w: World, e: World.Enemy, slot: int) -> void:
	if w.bursting or e.flags & Bestiary.F_BOSS:
		return
	var p: World.Player = w.players.get(slot)
	if p == null:
		return
	var chance := Upgrades.justice_chance(p.upgrades)
	if chance > 0.0 and w.rng.randf() < chance:
		w.bursts.append([e.pos, e.maxhp * Upgrades.JUSTICE_SHARE, slot])


## The queued JUSTICE bursts go off: every enemy within Upgrades.JUSTICE_RADIUS takes the burst's damage. Kills
## they make never burst (w.bursting), so the queue empties in one pass.
static func _update_bursts(w: World) -> void:
	if w.bursts.is_empty():
		return
	w.bursting = true
	w.stat_src = Results.SRC_JUSTICE
	var queued := w.bursts
	w.bursts = []
	for b: Array in queued:
		var at: Vector2 = b[0]
		w.emit(World.EV_BURST, at.x, at.y, Upgrades.JUSTICE_RADIUS, int(b[2]))
		for e: World.Enemy in w._query(at, Upgrades.JUSTICE_RADIUS + World.CELL * 0.5):
			if not e.dead and e.pos.distance_to(at) <= Upgrades.JUSTICE_RADIUS + e.r:
				WorldEnemies._damage_enemy(w, e, float(b[1]), int(b[2]), (e.pos - at).normalized() * Spells.BLAST_KNOCK)
	w.bursting = false
