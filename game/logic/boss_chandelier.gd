class_name BossChandelier
extends RefCounted
## THE BONE CHANDELIER (act I, 5:00): falls on you, then rolls. Phase 1, ALOFT: it drifts over the party and runs
## DRIP, DROP, RAIN, DROP in a fixed order with GAP_ALOFT s between. At PHASE_AT its chain snaps (a heavy BLAST
## under it) and it becomes THE WHEEL: ROLL, RAIN, ROLL, LAST CANDLE, HOP with GAP_WHEEL s between. Every attack is
## hazard rows (Bosses._landings runs their extras) or enemy shots. Static helpers; the first argument is the World.
## Enemy.state is the step below (the arena draws aloft, grounded, wheel and dizzy from it), Enemy.count the order
## index, Enemy.timer the step's clock, Enemy.timer2 the trail clock or the row it waits on, Enemy.dir the heading,
## Enemy.enter_dir.x the slot it drops on or the legs rolled.

enum { GAP, DRIP_WARN, DRIP, DROP_TRACK, DROP_LOCK, GROUNDED, RAIN, ROLL_WARN, ROLL, DIZZY, CANDLE, WHEEL_GAP,
	HOP_TRACK, HOP_LOCK, HOP_DOWN }
## The first step of THE WHEEL: every step from here on is phase 2.
const WHEEL_FIRST := ROLL_WARN
## The fixed attack orders, by the step each attack starts with.
const ORDER_ALOFT: Array[int] = [DRIP_WARN, DROP_TRACK, RAIN, DROP_TRACK]
const ORDER_WHEEL: Array[int] = [ROLL_WARN, RAIN, ROLL_WARN, CANDLE, HOP_TRACK]

## Its attacks as [state, warn s, hazard kind, r] (r: radius or half-width px).
const ATTACKS: Array = [
	[DRIP_WARN, 0.9, Hazards.LANE, 10.0], # DRIP: the lane it glides
	[DRIP, 0.47, Hazards.FLAME, 8.0], # DRIP: the wax behind it (laid with none: add_hazard raises it to min_warn)
	[DROP_TRACK, 2.5, Hazards.BLAST, 44.0], # DROP: 1.4 s chase, 1.1 s locked
	[RAIN, 0.9, Hazards.BLAST, 13.0],
	[GAP, 1.3, Hazards.BLAST, 50.0], # THE CHAIN SNAPS
	[ROLL_WARN, 0.8, Hazards.LANE, 18.0],
	[ROLL, 0.5, Hazards.FLAME, 10.0], # behind each leg (raised like DRIP's)
	[CANDLE, 3.5, Hazards.SAFE, 40.0],
	[HOP_TRACK, 1.9, Hazards.BLAST, 40.0], # HOP: 0.9 s track, 1.0 s locked
]

const GAP_ALOFT := 1.6
const GAP_WHEEL := 1.2
## Phase 1 hovers this far from the party's middle, px.
const HOVER := 70.0
## Phase 2 rolls about this far from the party's middle between attacks, px.
const WHEEL_KEEP := 90.0
## Damage taken while grounded or dizzy.
const VULN := 1.5
## How often a glide lays its trail, s.
const TRAIL_STEP := 0.25

const DRIP_HW := 10.0
const DRIP_PAST := 160.0
const DRIP_WARN_S := 0.9
const DRIP_SPEED := 90.0
const DRIP_FLAME_HW := 8.0
const DRIP_HOT := 4.0

const DROP_R := 44.0
const DROP_SPEED := 80.0
const DROP_TRACK_S := 1.4
const DROP_LOCK_S := 1.1
const DROP_GROUNDED := 3.5
const BONES := 12
const BONE_SPEED := 85.0
const ES_BONE := World.ES_SKULL # no bone shot yet: the skull's look

const RAIN_S := 3.0
const RAIN_EVERY := 0.3
const RAIN_R := 13.0
const RAIN_WARN := 0.9
const RAIN_LEAD := 0.4 # s of the aimed wizard's walk it leads
const RAIN_SPREAD := 70.0 # the second drop lands within this of the party's middle

const SNAP_R := 50.0
const SNAP_WARN := 1.3
const SNAP_TURN := 1.6 # the turn holds a little past the blast

const ROLL_HW := 18.0
const ROLL_WARN_S := 0.8
const ROLL_SPEED := 170.0
const ROLL_LEGS := 3
const ROLL_FLAME_HW := 10.0
const ROLL_HOT := 3.0
const ROLL_TRAMPLE := 30.0 # x the minute's enemy hp scale
const DIZZY_S := 2.5

const CANDLE_R := 40.0
const CANDLE_WARN := 3.5
const CANDLE_HOT := 0.2

const HOP_SPEED := 90.0
const HOP_TRACK_S := 0.9
const HOP_LOCK_S := 1.0
const HOP_R := 40.0
const HOP_GROUNDED := 2.5

const HOT_BLAST := 0.15 # how long a blast stays hot, s
## Contact hearts: aloft, grounded or dizzy, the wheel.
const CONTACT_ALOFT := 0
const CONTACT_DOWN := 1
const CONTACT_WHEEL := 2


static func think(w: World, e: World.Enemy, dt: float, _tgt: World.Player, _dirv: Vector2, _dist: float) -> Vector2:
	if e.enter_dir.y < 1.0 and Bosses.phase(e.type, e.hp / e.maxhp) >= 1:
		_snap(w, e)
		return Vector2.ZERO
	e.timer -= dt
	match e.state:
		GAP, WHEEL_GAP:
			_hover(w, e, dt)
			if e.timer <= 0.0:
				_next(w, e)
		DRIP_WARN:
			if e.timer <= 0.0:
				var lane := Bosses.last_row(w, e, Hazards.LANE)
				e.state = DRIP
				e.timer2 = 0.0
				e.timer = (e.pos.distance_to(lane.b) if lane != null else 0.0) / DRIP_SPEED
				if lane != null:
					e.dir = (lane.b - e.pos).normalized()
		DRIP:
			_glide_trail(w, e, dt, DRIP_SPEED, DRIP_FLAME_HW, DRIP_HOT)
			if e.timer <= 0.0:
				Bosses.trail(w, e, e.dir, DRIP_SPEED, e.timer2, DRIP_FLAME_HW, DRIP_HOT)
				_rest(e)
		DROP_TRACK, HOP_TRACK:
			var p: World.Player = w.players.get(int(e.enter_dir.x))
			var h := Bosses.row(w, int(e.timer2))
			if p != null and p.alive:
				Bosses.glide(e, p.pos, DROP_SPEED if e.state == DROP_TRACK else HOP_SPEED, dt)
			if h != null:
				w.move_hazard(h, e.pos, e.pos)
			if e.timer <= 0.0:
				e.state = DROP_LOCK if e.state == DROP_TRACK else HOP_LOCK
		DROP_LOCK, HOP_LOCK:
			var h := Bosses.row(w, int(e.timer2))
			if h == null or h.fired:
				_land(w, e)
		GROUNDED, HOP_DOWN, DIZZY:
			if e.timer <= 0.0:
				_rest(e)
		RAIN:
			e.timer2 -= dt
			if e.timer2 <= 0.0:
				_rain(w, e)
				e.timer2 += RAIN_EVERY
			if e.timer <= 0.0:
				_rest(e)
		ROLL_WARN:
			if e.timer <= 0.0:
				var lane := Bosses.last_row(w, e, Hazards.LANE)
				e.state = ROLL
				e.timer2 = 0.0
				e.timer = (e.pos.distance_to(lane.b) if lane != null else 0.0) / ROLL_SPEED
				if lane != null:
					e.dir = (lane.b - e.pos).normalized()
		ROLL:
			_glide_trail(w, e, dt, ROLL_SPEED, ROLL_FLAME_HW, ROLL_HOT, true)
			if e.timer <= 0.0:
				Bosses.trail(w, e, e.dir, ROLL_SPEED, e.timer2, ROLL_FLAME_HW, ROLL_HOT)
				_leg_done(w, e)
		CANDLE:
			_hover(w, e, dt)
			if e.timer <= 0.0:
				_rest(e)
	e.contact = contact_of(e.state)
	return Vector2.ZERO


## A hit while it lies grounded or dizzy does VULN x (Brains.filter_damage, through Bestiary.BRAINS).
static func filter_damage(_w: World, e: World.Enemy, dmg: float, _knock: Vector2, _sure: bool) -> float:
	return dmg * VULN if is_down(e.state) else dmg


static func on_death(_w: World, _e: World.Enemy, _slot: int) -> bool:
	return false


static func is_down(state: int) -> bool:
	return state == GROUNDED or state == HOP_DOWN or state == DIZZY


## Its contact hearts in a step: none aloft, one grounded or dizzy, two as the wheel.
static func contact_of(state: int) -> int:
	if is_down(state):
		return CONTACT_DOWN
	return CONTACT_WHEEL if state >= WHEEL_FIRST and not is_aloft(state) else CONTACT_ALOFT


## Whether it is off the floor: phase 1 but grounded, and a HOP in the air. The arena draws it raised.
static func is_aloft(state: int) -> bool:
	return (state < WHEEL_FIRST and state != GROUNDED) or state == HOP_TRACK or state == HOP_LOCK


## The attack the order holds next.
static func _next(w: World, e: World.Enemy) -> void:
	var order: Array[int] = ORDER_WHEEL if e.enter_dir.y >= 1.0 else ORDER_ALOFT
	var step: int = order[int(e.count) % order.size()]
	e.count += 1.0
	match step:
		DRIP_WARN:
			var c := w.party_center()
			var dir := (c - e.pos).normalized() if c.distance_to(e.pos) > 20.0 else Vector2.DOWN
			var end := Bosses.inside(c + dir * DRIP_PAST)
			w.add_hazard(Hazards.LANE, e.pos, end, DRIP_HW, DRIP_WARN_S, DRIP_WARN_S + e.pos.distance_to(end) / DRIP_SPEED, -1, e.id)
			e.state = DRIP_WARN
			e.timer = DRIP_WARN_S
		DROP_TRACK, HOP_TRACK:
			var knot := Bosses.knot_of(w)
			var drop := step == DROP_TRACK
			var warn := (DROP_TRACK_S + DROP_LOCK_S) if drop else (HOP_TRACK_S + HOP_LOCK_S)
			var h := w.add_hazard(Hazards.BLAST, e.pos, e.pos, DROP_R if drop else HOP_R, warn, HOT_BLAST, -1, e.id)
			if knot == null or h == null:
				_rest(e)
				return
			h.aux = Bosses.AUX_HEAVY
			e.state = step
			e.timer = DROP_TRACK_S if drop else HOP_TRACK_S
			e.timer2 = h.id
			e.enter_dir.x = knot.slot
		RAIN:
			e.state = RAIN
			e.timer = RAIN_S
			e.timer2 = 0.0
			e.enter_dir.x = 0.0 # drops so far
		ROLL_WARN:
			var far := Bosses.farthest_from(w, e.pos)
			var dir := (far.pos - e.pos).normalized() if far != null and far.pos.distance_to(e.pos) > 1.0 else Vector2.RIGHT
			e.enter_dir.x = 0.0 # legs rolled
			_roll_lane(w, e, dir)
		CANDLE:
			var at := Bosses.candle_spot(w, e.pos)
			w.add_hazard(Hazards.SAFE, at, at, CANDLE_R, CANDLE_WARN, CANDLE_HOT, -1, e.id)
			e.state = CANDLE
			e.timer = CANDLE_WARN + CANDLE_HOT


## Back to drifting until the next attack.
static func _rest(e: World.Enemy) -> void:
	var wheel := e.enter_dir.y >= 1.0
	e.state = WHEEL_GAP if wheel else GAP
	e.timer = GAP_WHEEL if wheel else GAP_ALOFT


## Between attacks: aloft it hangs HOVER px from the party on its own side; the wheel keeps WHEEL_KEEP px off.
static func _hover(w: World, e: World.Enemy, dt: float) -> void:
	var c := w.party_center()
	var off := (e.pos - c).normalized() if e.pos.distance_to(c) > 1.0 else Vector2.UP
	Bosses.glide(e, Bosses.inside(c + off * (WHEEL_KEEP if e.enter_dir.y >= 1.0 else HOVER)), e.spd, dt)


## Glides along e.dir at `speed`, laying FLAME every TRAIL_STEP s (and with `trample`, crushing the enemies it rolls
## over).
static func _glide_trail(w: World, e: World.Enemy, dt: float, speed: float, hw: float, hot: float, trample: bool = false) -> void:
	e.pos += e.dir * speed * minf(dt, maxf(e.timer + dt, 0.0))
	e.timer2 += dt
	if e.timer2 >= TRAIL_STEP:
		Bosses.trail(w, e, e.dir, speed, e.timer2, hw, hot)
		if trample:
			Bosses.crush(w, e.pos, e.r + 6.0, ROLL_TRAMPLE, 140.0)
		e.timer2 = 0.0


## DROP or HOP lands: the row's blast hurts (Bosses._landings), bones fly, and it lies grounded.
static func _land(w: World, e: World.Enemy) -> void:
	Bosses.ring(w, ES_BONE, e.pos, BONES, BONE_SPEED, 0.0)
	w.emit(World.EV_TELE, e.pos.x, e.pos.y, 1, 0)
	var hop := e.state == HOP_LOCK
	e.state = HOP_DOWN if hop else GROUNDED
	e.timer = HOP_GROUNDED if hop else DROP_GROUNDED


## One RAIN beat: a drop led onto an aimed wizard (the two aims take turns) and one near the party's middle.
static func _rain(w: World, e: World.Enemy) -> void:
	var aim := Bosses.aims(w, e)
	if not aim.is_empty():
		var p: World.Player = aim[int(e.enter_dir.x) % aim.size()]
		var at := Bosses.inside(p.pos + p.vel * RAIN_LEAD)
		w.add_hazard(Hazards.BLAST, at, at, RAIN_R, RAIN_WARN, HOT_BLAST, -1, e.id)
	var near := Bosses.inside(w.party_center() + Vector2.from_angle(w.rng.randf() * TAU) * w.rng.randf() * RAIN_SPREAD)
	w.add_hazard(Hazards.BLAST, near, near, RAIN_R, RAIN_WARN, HOT_BLAST, -1, e.id)
	e.enter_dir.x += 1.0


## A ROLL leg's lane from where it stands to the wall along `dir`; it squashes ROLL_WARN_S s first.
static func _roll_lane(w: World, e: World.Enemy, dir: Vector2) -> void:
	var end := Bosses.to_wall(e.pos, dir, e.r)
	w.add_hazard(Hazards.LANE, e.pos, end, ROLL_HW, ROLL_WARN_S, ROLL_WARN_S + e.pos.distance_to(end) / ROLL_SPEED, -1, e.id)
	e.dir = dir
	e.state = ROLL_WARN
	e.timer = ROLL_WARN_S


## A leg ends at a wall: it bounces into the next leg, or after ROLL_LEGS lies dizzy.
static func _leg_done(w: World, e: World.Enemy) -> void:
	e.enter_dir.x += 1.0
	if e.enter_dir.x >= ROLL_LEGS:
		e.state = DIZZY
		e.timer = DIZZY_S
		return
	var r := G.ARENA.grow(-e.r - 1.0)
	var dir := e.dir
	if e.pos.x <= r.position.x or e.pos.x >= r.end.x:
		dir.x = -dir.x
	if e.pos.y <= r.position.y or e.pos.y >= r.end.y:
		dir.y = -dir.y
	if dir == e.dir:
		dir = -dir
	_roll_lane(w, e, dir)


## THE CHAIN SNAPS at PHASE_AT: the attack under way stops, a heavy BLAST falls under it, it turns into the wheel.
static func _snap(w: World, e: World.Enemy) -> void:
	Bosses.drop_warnings(w, e)
	var h := w.add_hazard(Hazards.BLAST, e.pos, e.pos, SNAP_R, SNAP_WARN, HOT_BLAST, -1, e.id)
	if h != null:
		h.aux = Bosses.AUX_HEAVY
	e.enter_dir.y = 1.0
	e.count = 0.0
	e.state = WHEEL_GAP
	e.timer = GAP_WHEEL
	e.contact = CONTACT_ALOFT
	w.phase_turn(e, SNAP_TURN)
