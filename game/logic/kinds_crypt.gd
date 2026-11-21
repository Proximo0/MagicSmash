class_name KindsCrypt
extends RefCounted
## Job K's crypt kinds (docs/bestiary_design.md section 1): the BLOAT, the RESTLESS COFFIN and the TOMB GUARD.
## Brains reads think, on_death and filter_damage from here (Bestiary.BRAINS). Static; the first argument is the World.

## BLOAT: it pops itself this near a wizard. Its death is a Hazards.BLAST (hearts, foe damage x the minute's hp
## scale and shove in Hazards.KINDS) of this radius, warning and hot time, credited to the killer; none if frosted.
const BLOAT_POP := 16.0
const BLOAT_BLAST_R := 30.0
const BLOAT_BLAST_WARN := 0.9
const BLOAT_BLAST_HOT := 0.15
## RESTLESS COFFIN: seconds shut, then rattling; then it hatches COFFIN_BROOD skeletons (one more from
## COFFIN_LATE run seconds; fewer at the horde's cap) in a ring this wide and is gone. Broken, it drops a gem
## thrown up this fast.
const COFFIN_SHUT := 4.0
const COFFIN_RATTLE := 2.0
const COFFIN_BROOD := 3
const COFFIN_LATE := 600.0
const COFFIN_RING := 10.0
const COFFIN_GEM_KICK := 40.0
## Coffin states (Enemy.state, what the view shows).
const ST_SHUT := 0
const ST_RATTLE := 1
## TOMB GUARD: how fast its facing turns to the nearest wizard, rad/s; a hit whose push comes from within GUARD_ARC
## of the facing does nothing. Its facing goes out in Enemy.state as one of GUARD_FACINGS steps (0: +x, clockwise
## on screen); the "BLOCKED" spark at most every GUARD_SPARK s.
const GUARD_TURN := 1.2
const GUARD_ARC := 70.0 * PI / 180.0
const GUARD_FACINGS := 16
const GUARD_SPARK := 0.4


static func think(w: World, e: World.Enemy, dt: float, tgt: World.Player, dirv: Vector2, dist: float) -> Vector2:
	match e.type:
		Bestiary.BLOAT:
			if tgt != null and dist <= BLOAT_POP:
				_bloat_pop(w, e)
				return Vector2.ZERO
			return dirv * e.spd
		Bestiary.COFFIN:
			return _coffin_think(w, e, dt)
	return _guard_think(e, dt, dirv)


static func on_death(w: World, e: World.Enemy, slot: int) -> bool:
	match e.type:
		Bestiary.BLOAT:
			if e.slow <= 0.0:
				_bloat_blast(w, e, slot)
		Bestiary.COFFIN:
			WorldDrops._drop(w, World.PK_GEM, e.pos, Vector2(0, -COFFIN_GEM_KICK))
			return true
	return false


static func filter_damage(w: World, e: World.Enemy, dmg: float, knock: Vector2, sure: bool) -> float:
	if e.type != Bestiary.GUARD or sure or knock.length_squared() < 0.0001 or e.dir == Vector2.ZERO:
		return dmg
	if absf(e.dir.angle_to(-knock)) > GUARD_ARC:
		return dmg
	if e.timer <= 0.0:
		e.timer = GUARD_SPARK
		w.emit(World.EV_WARD, e.pos.x, e.pos.y - e.r, -1, 0)
	return -1.0


## A bloat reaches a wizard: its body leaves the list (no XP, no drop) and it blasts, credited to nobody.
static func _bloat_pop(w: World, e: World.Enemy) -> void:
	e.dead = true
	w.emit(World.EV_DIE, e.pos.x, e.pos.y - e.r, e.type, -1)
	if e.slow <= 0.0:
		_bloat_blast(w, e, -1)


static func _bloat_blast(w: World, e: World.Enemy, slot: int) -> void:
	w.add_hazard(Hazards.BLAST, e.pos, e.pos, BLOAT_BLAST_R, BLOAT_BLAST_WARN, BLOAT_BLAST_HOT, slot)


## Enemy.timer2 is the coffin's age: shut, rattling, then it hatches and is gone (nothing drops).
static func _coffin_think(w: World, e: World.Enemy, dt: float) -> Vector2:
	e.timer2 += dt
	if e.timer2 >= COFFIN_SHUT + COFFIN_RATTLE - 0.0001:
		# The brood never lifts the crowd past the horde's cap (tune.enemy_cap), which bounds the cost of a step.
		var n := mini(COFFIN_BROOD + (1 if w.wave_time >= COFFIN_LATE else 0), maxi(0, int(w.tune.enemy_cap) - w.enemies.size()))
		for i: int in range(n):
			w.spawn_enemy(World.SKELETON, 0, e.pos + Vector2.from_angle(TAU * i / n) * COFFIN_RING)
		if n > 0:
			w.emit(World.EV_RAISE, e.pos.x, e.pos.y, n, 0)
		e.dead = true
		return Vector2.ZERO
	e.state = ST_RATTLE if e.timer2 >= COFFIN_SHUT else ST_SHUT
	return Vector2.ZERO


## The guard's facing (Enemy.dir) turns toward the nearest wizard at GUARD_TURN while it walks there.
static func _guard_think(e: World.Enemy, dt: float, dirv: Vector2) -> Vector2:
	e.timer -= dt
	if e.dir == Vector2.ZERO:
		e.dir = dirv
	var ang := e.dir.angle()
	ang += clampf(angle_difference(ang, dirv.angle()), -GUARD_TURN * dt, GUARD_TURN * dt)
	e.dir = Vector2.from_angle(ang)
	e.state = posmod(roundi(ang / TAU * GUARD_FACINGS), GUARD_FACINGS)
	return dirv * e.spd
