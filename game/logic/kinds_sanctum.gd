class_name KindsSanctum
extends RefCounted
## Job K's sanctum kinds (docs/bestiary_design.md section 1): the COMET SHARD and the TEN OF SWORDS.
## Brains reads think, on_death and filter_damage from here (Bestiary.BRAINS). Static; the first argument is the World.

## COMET SHARD: the one the horde raises is a seed. Its first think picks a landing spot SHARD_MIN..SHARD_MAX px from
## the party's centre (inset SHARD_MARGIN), SHARD_CLEAR px from every wizard and SHARD_APART from other shards, lays
## a FALL disc there (the landed shard spawns as it turns hot) and goes. SHARD_TRIES spots are tried.
const SHARD_MIN := 70.0
const SHARD_MAX := 120.0
const SHARD_MARGIN := 22.0
const SHARD_CLEAR := 30.0
const SHARD_APART := 180.0
const SHARD_TRIES := 12
const SHARD_FALL_R := 18.0
const SHARD_FALL_WARN := 1.2
const SHARD_FALL_HOT := 0.2
## A landed shard: SHARD_BEAM_AT s after landing a BEAM line SHARD_BEAM_LEN long, half-width SHARD_BEAM_HALF, warns
## SHARD_BEAM_WARN s pointing at the widest wizard-free angle, then turns SHARD_SPIN rad/s while hot. At SHARD_LIFE s
## it burns out (gone, no drop).
const SHARD_BEAM_AT := 1.5
const SHARD_BEAM_LEN := 120.0
const SHARD_BEAM_HALF := 4.0
const SHARD_BEAM_WARN := 1.0
const SHARD_SPIN := 0.6
const SHARD_LIFE := 30.0
## Shard states (Enemy.state): a seed, landed and idle, the beam warning, the beam turning.
const SS_SEED := 0
const SS_IDLE := 1
const SS_CHARGE := 2
const SS_BEAM := 3
## TEN OF SWORDS: on death a BURST disc this wide kneels SWORDS_KNEEL s, then rings SWORDS_RING Bestiary.ES_SWORD
## shots (Hazards.SHOT_SPEED, SHOT_LIFE).
const SWORDS_BURST_R := 22.0
const SWORDS_KNEEL := 0.7
const SWORDS_RING := 10
const SWORDS_BURST_HOT := 0.1


static func think(w: World, e: World.Enemy, dt: float, _tgt: World.Player, dirv: Vector2, _dist: float) -> Vector2:
	if e.type == Bestiary.SHARD:
		return _shard_think(w, e, dt)
	return dirv * e.spd


static func on_death(w: World, e: World.Enemy, slot: int) -> bool:
	if e.type == Bestiary.SHARD:
		_shard_beam_off(w, e)
	else:
		var h := w.add_hazard(Hazards.BURST, e.pos, e.pos, SWORDS_BURST_R, SWORDS_KNEEL, SWORDS_BURST_HOT, slot)
		if h != null:
			h.aux = Bestiary.ES_SWORD * Hazards.SHOT_KIND + SWORDS_RING
	return false


static func filter_damage(_w: World, _e: World.Enemy, dmg: float, _knock: Vector2, _sure: bool) -> float:
	return dmg


## Enemy.timer2: age since landing; Enemy.count: the BEAM row's id + 1 (0: none yet); Enemy.dir: the beam's heading.
static func _shard_think(w: World, e: World.Enemy, dt: float) -> Vector2:
	if e.state == SS_SEED:
		_shard_seed(w, e)
		return Vector2.ZERO
	e.timer2 += dt
	if e.timer2 >= SHARD_LIFE:
		_shard_beam_off(w, e)
		e.dead = true
		w.emit(World.EV_DIE, e.pos.x, e.pos.y - e.r, e.type, -1)
		return Vector2.ZERO
	if e.count <= 0.0:
		if e.timer2 >= SHARD_BEAM_AT:
			e.dir = Vector2.from_angle(widest_gap(w, e.pos))
			var h := w.add_hazard(Hazards.BEAM, e.pos, e.pos + e.dir * SHARD_BEAM_LEN, SHARD_BEAM_HALF, SHARD_BEAM_WARN,
				SHARD_LIFE - e.timer2 - SHARD_BEAM_WARN, -1, e.id)
			if h != null:
				e.count = h.id + 1
				e.state = SS_CHARGE
		return Vector2.ZERO
	var beam := KindsLibrary.row_by_id(w, int(e.count) - 1)
	if beam == null:
		e.count = 0.0 # the nova cleared it: a new one warns again
		e.state = SS_IDLE
		return Vector2.ZERO
	if beam.warn <= 0.0:
		e.state = SS_BEAM
		e.dir = e.dir.rotated(SHARD_SPIN * dt * (1.0 if e.id % 2 == 0 else -1.0))
		w.move_hazard(beam, e.pos, e.pos + e.dir * SHARD_BEAM_LEN)
	return Vector2.ZERO


static func _shard_beam_off(w: World, e: World.Enemy) -> void:
	if e.count > 0.0:
		var beam := KindsLibrary.row_by_id(w, int(e.count) - 1)
		if beam != null:
			beam.warn = 0.0
			beam.fired = true
			beam.hot = 0.0
	e.count = 0.0


## The middle of the widest angle around `at` with no living wizard in it, rad (any angle with no wizard at all).
static func widest_gap(w: World, at: Vector2) -> float:
	var angs: Array[float] = []
	for p: World.Player in w.players.values():
		if p.alive:
			angs.append((p.pos - at).angle())
	if angs.is_empty():
		return 0.0
	angs.sort()
	var best := angs[0] + PI
	var best_gap := -1.0
	for i: int in range(angs.size()):
		var a0: float = angs[i]
		var a1: float = angs[(i + 1) % angs.size()] + (TAU if i + 1 >= angs.size() else 0.0)
		if a1 - a0 > best_gap:
			best_gap = a1 - a0
			best = (a0 + a1) * 0.5
	return best


## A seed: lands where it rose if that spot keeps the rules, else on the best of SHARD_TRIES spots; lays the FALL and
## goes. Nothing lands past the cap (counting falls still in the air). With the floor full of rows it lands at once.
static func _shard_seed(w: World, e: World.Enemy) -> void:
	for h: Hazards.Hazard in w.hazards:
		if h.kind == Hazards.FALL and h.aux == Bestiary.SHARD and h.fired and h.a.distance_squared_to(e.pos) < 1.0:
			e.state = SS_IDLE # it just landed
			return
	var others: Array[Vector2] = []
	for o: World.Enemy in w.enemies:
		if o != e and not o.dead and o.type == Bestiary.SHARD:
			others.append(o.pos)
	for h: Hazards.Hazard in w.hazards:
		if h.kind == Hazards.FALL and h.aux == Bestiary.SHARD and not h.fired:
			others.append(h.a)
	e.dead = true
	if others.size() >= Bestiary.cap_of(Bestiary.horde_row(Bestiary.SHARD), w.players.size()):
		return
	var c := w.party_center()
	var best := e.pos
	var best_score := _shard_spot_score(w, e.pos, c, others)
	var tries := 0
	while best_score < 0.0 and tries < SHARD_TRIES:
		tries += 1
		var area := G.ARENA.grow(-SHARD_MARGIN)
		var at := (c + Vector2.from_angle(w.rng.randf() * TAU) * w.rng.randf_range(SHARD_MIN, SHARD_MAX)).clamp(area.position, area.end)
		var score := _shard_spot_score(w, at, c, others)
		if score > best_score:
			best_score = score
			best = at
	var h := w.add_hazard(Hazards.FALL, best, best, SHARD_FALL_R, SHARD_FALL_WARN, SHARD_FALL_HOT)
	if h != null:
		h.aux = Bestiary.SHARD
	else:
		e.dead = false
		e.state = SS_IDLE


## 0 or more when `at` keeps every landing rule; below 0 by how far it misses them (the least bad wins).
static func _shard_spot_score(w: World, at: Vector2, c: Vector2, others: Array[Vector2]) -> float:
	var miss := 0.0
	var dc := at.distance_to(c)
	miss += maxf(0.0, SHARD_MIN - dc) + maxf(0.0, dc - SHARD_MAX)
	for p: World.Player in w.players.values():
		if p.alive:
			miss += maxf(0.0, SHARD_CLEAR - p.pos.distance_to(at))
	for o: Vector2 in others:
		miss += maxf(0.0, SHARD_APART - o.distance_to(at)) * 0.25
	return -miss
