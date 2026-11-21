class_name Hazards
extends RefCounted
## Hazard rows: an area on the floor that warns (a dashed rim, its fill growing) and then turns hot for a while.
## A disc (centre a, radius r) or a line (a to b, half-width r). Hot rows hurt wizards inside (outside, for an
## inverted row such as SAFE); some act once as they turn hot (a blast that hurts enemies too, a ring of shots,
## an enemy landing). A leaf: it knows nothing of World; World.add_hazard, move_hazard and _update_hazards run them.
## Every warning lasts at least min_warn(r): a wizard at full walking speed can always leave in time.

## Floats per row in snapshot()["hz"]: id, kind, x, y, x2, y2, r, warn_left, warn_total, hot_left.
const FLOATS := 10
const CAP := 48 # rows at once, boss rows included
const CAP_REGULAR := 32 # rows not made by a boss
const WARN_BUDGET := 6 # regular rows warning at once within WARN_RANGE of the party
const WARN_RANGE := 260.0
## How near the nova must be to clear a regular row, px (a boss's rows stay).
const NOVA_CLEAR := 150.0
## The fair-walk rule: warn >= WARN_BASE + (r + WARN_PAD) / WARN_SPEED (a wizard's walk, px/s, with margin).
const WARN_BASE := 0.3
const WARN_PAD := 4.0
const WARN_SPEED := 71.0
## A ring of shots (on_hot SHOTS): aux = eshot kind * SHOT_KIND + count; their speed, px/s, and life, s.
const SHOT_KIND := 100
const SHOT_SPEED := 95.0
const SHOT_LIFE := 2.2
const SHOT_R := 3.0
## The body a bot keeps out of a row, px.
const BOT_MARGIN := 5.0

enum { MARK, BLAST, FIRE, FLAME, FALL, BEAM, BURST, LANE, SAFE }
const DISC := 0
const LINE := 1
const ON_NONE := 0
const ON_BLAST := 1
const ON_SHOTS := 2
const ON_SPAWN := 3
## [shape, hearts while hot, on_hot, foe damage (x the minute's enemy hp scale), foe shove px/s, inverted, bots avoid]
const K_SHAPE := 0
const K_HEARTS := 1
const K_ON_HOT := 2
const K_FOE_DMG := 3
const K_FOE_SHOVE := 4
const K_INVERTED := 5
const K_AVOID := 6
const KINDS: Array = [
	[LINE, 0, ON_NONE, 0.0, 0.0, false, false], # MARK: a path shown, never hot
	[DISC, 1, ON_BLAST, 6.0, 120.0, false, true], # BLAST: hurts wizards and enemies once
	[DISC, 1, ON_NONE, 0.0, 0.0, false, true], # FIRE: a burning patch
	[LINE, 1, ON_NONE, 0.0, 0.0, false, true], # FLAME: a burning line
	[DISC, 1, ON_SPAWN, 0.0, 0.0, false, true], # FALL: something lands (aux = enemy type)
	[LINE, 1, ON_NONE, 0.0, 0.0, false, true], # BEAM: a brain turns it while hot
	[DISC, 0, ON_SHOTS, 0.0, 0.0, false, false], # BURST: a ring of shots
	[LINE, 0, ON_NONE, 0.0, 0.0, false, true], # LANE: where a boss is about to go
	[DISC, 2, ON_NONE, 0.0, 0.0, true, true], # SAFE: everyone outside it is hurt
]


class Hazard:
	var id := 0
	var kind := 0
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var r := 12.0
	var warn := 0.8 # s left of the warning
	var warn0 := 0.8 # the whole warning, s
	var hot := 0.15 # s left hot, once the warning is over
	var slot := -1 # the wizard credited for what it does to enemies
	var owner := 0 # the enemy id that made it (0: none); its death during the warning removes the row
	var follow := -1 # a wizard slot it follows while warning, until `lock` s are left
	var lock := 0.0
	var aux := 0 # on_hot argument (enemy type, shot ring)
	var boss := false # made by the boss: not capped as regular, not cleared by the nova
	var fired := false # on_hot has run


## The shortest fair warning for a row of radius or half-width `r`.
static func min_warn(r: float) -> float:
	return WARN_BASE + (r + WARN_PAD) / WARN_SPEED


static func contains(h: Hazard, p: Vector2) -> bool:
	return _inside(int(KINDS[h.kind][K_SHAPE]), h.a, h.b, h.r, p)


static func _inside(shape: int, a: Vector2, b: Vector2, r: float, p: Vector2) -> bool:
	if shape == DISC:
		return p.distance_squared_to(a) <= r * r
	return p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, a, b)) <= r * r


## Whether one more row fits: never past CAP; a forced row only needs that; a regular one also stays under
## CAP_REGULAR and the WARN_BUDGET of warnings near the party.
static func can_add(rows: Array[Hazard], party: Vector2, boss: bool, forced: bool) -> bool:
	if rows.size() >= CAP:
		return false
	if forced or boss:
		return true
	var regular := 0
	var warning := 0
	for h: Hazard in rows:
		if h.boss:
			continue
		regular += 1
		if h.warn > 0.0 and h.a.distance_to(party) <= WARN_RANGE:
			warning += 1
	return regular < CAP_REGULAR and warning < WARN_BUDGET


## Runs the rows' clocks: a warning row following a wizard (`wizards`: slot -> position) moves with them until it
## locks; a row whose warning ends turns hot. Returns the rows that turned hot this tick.
static func tick(rows: Array[Hazard], dt: float, wizards: Dictionary) -> Array[Hazard]:
	var turned: Array[Hazard] = []
	for h: Hazard in rows:
		if h.warn > 0.0:
			if h.follow >= 0 and h.warn > h.lock and wizards.has(h.follow):
				var to: Vector2 = wizards[h.follow]
				h.b += to - h.a
				h.a = to
			h.warn -= dt
			if h.warn <= 0.0:
				h.warn = 0.0
				turned.append(h)
		else:
			h.hot -= dt
	return turned


static func pack(rows: Array[Hazard]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for h: Hazard in rows:
		out.append_array([h.id, h.kind, h.a.x, h.a.y, h.b.x, h.b.y, h.r, h.warn, h.warn0, maxf(h.hot, 0.0)])
	return out


## Where a bot at `me` walking at `speed` (reacting `react` s late) should lean to keep out of the rows in `hz`
## (pack layout): away from a row it stands in that is hot or will be before it could walk out, into a SAFE disc
## that will be. Zero when nothing threatens; longer for more urgent rows.
static func steer(hz: PackedFloat32Array, me: Vector2, speed: float, react: float) -> Vector2:
	var out := Vector2.ZERO
	var i := 0
	while i + FLOATS <= hz.size():
		var kind := int(hz[i + 1])
		var row: Array = KINDS[kind]
		if row[K_AVOID]:
			var a := Vector2(hz[i + 2], hz[i + 3])
			var b := Vector2(hz[i + 4], hz[i + 5])
			var r: float = hz[i + 6] + BOT_MARGIN
			var warn: float = hz[i + 7]
			var near := a if int(row[K_SHAPE]) == DISC else Geometry2D.get_closest_point_to_segment(me, a, b)
			var off := me - near
			var d := off.length()
			if d < 0.01:
				off = (b - a).orthogonal() if int(row[K_SHAPE]) == LINE and a != b else Vector2.RIGHT
				d = 0.0
			var dir := off.normalized()
			var walk: float = ((r - d) if not row[K_INVERTED] else (d - hz[i + 6] + BOT_MARGIN)) / maxf(speed, 1.0)
			if walk > 0.0:
				var urgency := clampf(1.0 - (warn - react - walk) / 1.5, 0.2, 1.0)
				out += (-dir if row[K_INVERTED] else dir) * urgency
		i += FLOATS
	return out


## The rows of `hz` that reach within `reach` px of `p` (a bot's walk this think), same layout.
static func near(hz: PackedFloat32Array, p: Vector2, reach: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var i := 0
	while i + FLOATS <= hz.size():
		var a := Vector2(hz[i + 2], hz[i + 3])
		var b := Vector2(hz[i + 4], hz[i + 5])
		var r: float = hz[i + 6] + reach
		if bool(KINDS[int(hz[i + 1])][K_INVERTED]) or p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, a, b)) <= r * r:
			out.append_array(hz.slice(i, i + FLOATS))
		i += FLOATS
	return out


## The centre of a SAFE disc in `hz`, or Vector2.INF.
static func goal(hz: PackedFloat32Array) -> Vector2:
	var i := 0
	while i + FLOATS <= hz.size():
		if int(hz[i + 1]) == SAFE:
			return Vector2(hz[i + 2], hz[i + 3])
		i += FLOATS
	return Vector2.INF
