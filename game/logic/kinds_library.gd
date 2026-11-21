class_name KindsLibrary
extends RefCounted
## Job K's library kinds (docs/bestiary_design.md section 1): the CINDERLING, THE CENSOR and the ASH HOUND.
## Brains reads think, on_death and filter_damage from here (Bestiary.BRAINS). Static; the first argument is the World.

## CINDERLING: holds this band from the nearest wizard for a random while, kindles (a MARK line through the point
## CINDER_AHEAD px ahead of its target, CINDER_LEN long), then runs it at CINDER_SPEED (fixed) for CINDER_RUN s
## laying a FLAME line of half-width CINDER_HALF that burns CINDER_BURN s more.
const CINDER_NEAR := 90.0
const CINDER_FAR := 130.0
const CINDER_HOLD_MIN := 1.5
const CINDER_HOLD_MAX := 2.5
const CINDER_KINDLE := 0.6
const CINDER_AHEAD := 30.0
const CINDER_LEN := 210.0
const CINDER_SPEED := 190.0
const CINDER_RUN := 1.1
const CINDER_HALF := 5.0
const CINDER_BURN := 3.0
## Cinderling states (Enemy.state).
const CS_HOLD := 0
const CS_KINDLE := 1
const CS_RUN := 2
## THE CENSOR: holds this band; every CENSOR_EVERY s, with the nearest wizard CENSOR_MIN..CENSOR_MAX px away, winds up
## CENSOR_WIND s and throws a FIRE disc at that wizard's feet as it lets go. A wizard within CENSOR_MIN: panic, no
## throws, it backs off at CENSOR_PANIC x its speed.
const CENSOR_NEAR := 100.0
const CENSOR_FAR := 150.0
const CENSOR_EVERY := 4.0
const CENSOR_MIN := 60.0
const CENSOR_MAX := 200.0
const CENSOR_WIND := 0.5
const CENSOR_FIRE_R := 22.0
const CENSOR_FIRE_WARN := 1.2
const CENSOR_FIRE_HOT := 3.0
const CENSOR_PANIC := 1.5
## Censor states (Enemy.state).
const ZS_WALK := 0
const ZS_WIND := 1
const ZS_PANIC := 2
## ASH HOUND: the pack circles the party's centre at HOUND_RING px (HOUND_LEAD rad ahead of where it stands). Every
## HOUND_SCAN s a circling hound names the stray (stray_of); within HOUND_REACH px of it, it howls HOUND_HOWL s and
## hunts at HOUND_SPEED (fixed), turning at most HOUND_TURN rad/s, for HOUND_HUNT s or until the stray is within
## HOUND_SAFE px of an ally. It circles HOUND_PROWL s before it may hunt (solo: prowl, then hunt HOUND_HUNT_SOLO s).
const HOUND_RING := 150.0
const HOUND_LEAD := 0.5
const HOUND_SCAN := 0.5
const HOUND_STRAY := 140.0
const HOUND_GRAVE := 40.0
const HOUND_REACH := 260.0
const HOUND_HOWL := 0.7
const HOUND_SPEED := 125.0
const HOUND_TURN := 1.6
const HOUND_HUNT := 4.0
const HOUND_HUNT_SOLO := 3.0
const HOUND_SAFE := 60.0
const HOUND_PROWL := 4.0
## Hound phases; Enemy.state = phase + HOUND_SLOT_STEP * (target slot + 1) so the view can mark the hunted.
const HS_CIRCLE := 0
const HS_HOWL := 1
const HS_HUNT := 2
const HOUND_SLOT_STEP := 4


static func think(w: World, e: World.Enemy, dt: float, tgt: World.Player, dirv: Vector2, dist: float) -> Vector2:
	match e.type:
		Bestiary.CINDERLING:
			return _cinder_think(w, e, dt, tgt, dirv, dist)
		Bestiary.CENSOR:
			return _censor_think(w, e, dt, tgt, dirv, dist)
	return _hound_think(w, e, dt)


static func on_death(_w: World, _e: World.Enemy, _slot: int) -> bool:
	return false # a cinderling's MARK goes with it (its owner); its laid FLAME simply stops growing


static func filter_damage(_w: World, _e: World.Enemy, dmg: float, _knock: Vector2, _sure: bool) -> float:
	return dmg


## Toward the band [near, far] from the nearest wizard; standing in it.
static func _band_walk(e: World.Enemy, dirv: Vector2, dist: float, near: float, far: float) -> Vector2:
	if dist > far:
		return dirv * e.spd
	if dist < near:
		return -dirv * e.spd
	return Vector2.ZERO


## The row with this id, or null.
static func row_by_id(w: World, id: int) -> Hazards.Hazard:
	for h: Hazards.Hazard in w.hazards:
		if h.id == id:
			return h
	return null


## Enemy.timer: the hold left; Enemy.timer2: the kindle or the run left; Enemy.dir: the run's heading; Enemy.count:
## the FLAME row's id (-1: none).
static func _cinder_think(w: World, e: World.Enemy, dt: float, tgt: World.Player, dirv: Vector2, dist: float) -> Vector2:
	match e.state:
		CS_KINDLE:
			e.timer2 -= dt
			if e.timer2 <= 0.0:
				e.state = CS_RUN
				e.timer2 = CINDER_RUN
				var warn := Hazards.min_warn(CINDER_HALF)
				var h := w.add_hazard(Hazards.FLAME, e.pos, e.pos, CINDER_HALF, warn, CINDER_RUN - warn + CINDER_BURN)
				e.count = h.id if h != null else -1
			return Vector2.ZERO
		CS_RUN:
			e.timer2 -= dt
			var h := row_by_id(w, int(e.count)) if e.count >= 0 else null
			var along := 0.0
			if h != null:
				along = clampf((e.pos - h.a).dot(e.dir), 0.0, CINDER_LEN)
				w.move_hazard(h, h.a, h.a + e.dir * along)
			if e.timer2 <= 0.0 or along >= CINDER_LEN:
				e.state = CS_HOLD
				e.timer = w.rng.randf_range(CINDER_HOLD_MIN, CINDER_HOLD_MAX)
				e.count = -1
				return Vector2.ZERO
			e.vel = e.dir * CINDER_SPEED
			return e.vel
	var v := _band_walk(e, dirv, dist, CINDER_NEAR, CINDER_FAR)
	if tgt == null or v != Vector2.ZERO:
		return v
	e.timer -= dt
	if e.timer > 0.0:
		return v
	var aim := tgt.pos + (tgt.vel.normalized() * CINDER_AHEAD if tgt.vel.length_squared() > 1.0 else Vector2.ZERO)
	e.dir = (aim - e.pos).normalized() if aim.distance_squared_to(e.pos) > 1.0 else dirv
	if w.add_hazard(Hazards.MARK, e.pos, e.pos + e.dir * CINDER_LEN, CINDER_HALF, CINDER_KINDLE, 0.0, -1, e.id) == null:
		e.timer = w.rng.randf_range(CINDER_HOLD_MIN, CINDER_HOLD_MAX)
		return v
	e.state = CS_KINDLE
	e.timer2 = CINDER_KINDLE
	return v


## Enemy.timer: the throw's cooldown; Enemy.timer2: the wind-up left; Enemy.count: the slot it throws at.
static func _censor_think(w: World, e: World.Enemy, dt: float, tgt: World.Player, dirv: Vector2, dist: float) -> Vector2:
	e.timer = maxf(0.0, e.timer - dt)
	if tgt != null and dist < CENSOR_MIN:
		e.state = ZS_PANIC
		return -dirv * e.spd * CENSOR_PANIC
	if e.state == ZS_WIND:
		e.timer2 -= dt
		if e.timer2 > 0.0:
			return Vector2.ZERO
		e.state = ZS_WALK
		e.timer = CENSOR_EVERY
		var p: World.Player = w.players.get(int(e.count))
		if p != null and p.alive:
			w.add_hazard(Hazards.FIRE, p.pos, p.pos, CENSOR_FIRE_R, CENSOR_FIRE_WARN, CENSOR_FIRE_HOT, -1, e.id)
		return Vector2.ZERO
	e.state = ZS_WALK
	if tgt != null and e.timer <= 0.0 and dist >= CENSOR_MIN and dist <= CENSOR_MAX:
		e.state = ZS_WIND
		e.timer2 = CENSOR_WIND
		e.count = tgt.slot
		return Vector2.ZERO
	return _band_walk(e, dirv, dist, CENSOR_NEAR, CENSOR_FAR)


## The stray the hounds hunt: the living wizard farthest from their nearest living ally, if that is over HOUND_STRAY
## px, never one within HOUND_GRAVE px of a fallen wizard (a reviver). -1: none. Solo (one wizard in the run): that
## wizard while alive.
static func stray_of(w: World) -> int:
	var living: Array[World.Player] = []
	for p: World.Player in w.players.values():
		if p.alive:
			living.append(p)
	if w.players.size() == 1:
		return living[0].slot if living.size() == 1 else -1
	var graves: Array = w.graves()
	var best := -1
	var best_d := HOUND_STRAY
	for p: World.Player in living:
		var near := INF
		for o: World.Player in living:
			if o != p:
				near = minf(near, p.pos.distance_to(o.pos))
		if near == INF or near <= best_d:
			continue
		var reviving := false
		for g: Array in graves:
			reviving = reviving or p.pos.distance_to(Vector2(g[1], g[2])) <= HOUND_GRAVE
		if not reviving:
			best = p.slot
			best_d = near
	return best


## Whether `p` is back within HOUND_SAFE px of a living ally.
static func _hound_safe(w: World, p: World.Player) -> bool:
	for o: World.Player in w.players.values():
		if o != p and o.alive and o.pos.distance_to(p.pos) <= HOUND_SAFE:
			return true
	return false


## Enemy.timer: the scan clock; Enemy.timer2: the phase's clock; Enemy.count: the hunted slot; Enemy.dir: heading.
static func _hound_think(w: World, e: World.Enemy, dt: float) -> Vector2:
	var phase := e.state % HOUND_SLOT_STEP
	e.timer2 += dt
	var prey: World.Player = w.players.get(int(e.count)) if phase != HS_CIRCLE else null
	if phase != HS_CIRCLE and (prey == null or not prey.alive):
		phase = _hound_set(e, HS_CIRCLE, -1)
	match phase:
		HS_HOWL:
			if e.timer2 >= HOUND_HOWL:
				_hound_set(e, HS_HUNT, prey.slot)
				if e.dir == Vector2.ZERO:
					e.dir = (prey.pos - e.pos).normalized()
			return Vector2.ZERO
		HS_HUNT:
			var solo := w.players.size() == 1
			if e.timer2 >= (HOUND_HUNT_SOLO if solo else HOUND_HUNT) or (not solo and _hound_safe(w, prey)):
				_hound_set(e, HS_CIRCLE, -1)
			else:
				var ang := e.dir.angle()
				ang += clampf(angle_difference(ang, (prey.pos - e.pos).angle()), -HOUND_TURN * dt, HOUND_TURN * dt)
				e.dir = Vector2.from_angle(ang)
				e.vel = e.dir * HOUND_SPEED
				return e.vel
	var c := w.party_center()
	var off := e.pos - c
	if off.length_squared() < 1.0:
		off = Vector2.RIGHT
	var spot := c + off.normalized().rotated(HOUND_LEAD if e.id % 2 == 0 else -HOUND_LEAD) * HOUND_RING
	var v := (spot - e.pos).normalized() * e.spd if spot.distance_squared_to(e.pos) > 4.0 else Vector2.ZERO
	if v != Vector2.ZERO:
		e.dir = v.normalized()
	e.timer -= dt
	if e.timer <= 0.0:
		e.timer = HOUND_SCAN
		if e.timer2 >= HOUND_PROWL:
			var slot := stray_of(w)
			var p: World.Player = w.players.get(slot)
			if p != null and p.pos.distance_to(e.pos) <= HOUND_REACH:
				_hound_set(e, HS_HOWL, slot)
				return Vector2.ZERO
	return v


static func _hound_set(e: World.Enemy, phase: int, slot: int) -> int:
	e.state = phase + (HOUND_SLOT_STEP * (slot + 1) if slot >= 0 else 0)
	e.count = slot
	e.timer2 = 0.0
	return phase
