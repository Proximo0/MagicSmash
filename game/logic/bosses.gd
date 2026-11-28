class_name Bosses
extends RefCounted
## The bosses: when they come (SCHEDULE), their health by party size and visit, their phases, and what World does
## when one arrives, turns a phase and dies. Any F_BOSS kind can be World.boss; each has its own file with `think`
## and `ATTACKS` (BossLich). Static helpers; World-taking ones have the World first.

## [run s, Bestiary type, final]: the act bosses, THE BONE CHANDELIER at 5:00 and THE GHOST WRITER at 10:00, then
## the Archlich at 15:00. It is what schedule_from() builds from the default Tuning (boss_every_min, run_minutes).
const SCHEDULE: Array = [[300.0, Bestiary.CHANDELIER, false], [600.0, Bestiary.GHOSTWRITER, false], [900.0, Bestiary.LICH, true]]
## The kinds of the schedule's visits before the final, in order; any later visit is the Lich.
const ACT_KINDS: Array = [Bestiary.CHANDELIER, Bestiary.GHOSTWRITER]
## Morvane's visits: [run s, ward base]. Not World.boss; nothing reads this until the act-boss job.
const VISITS: Array = [[420.0, 150.0], [720.0, 400.0]]
## A boss's health multiplier by party size (1 to 4 wizards), and its growth each time the same kind returns (the
## Lich's second visit has 1.25x). The values the default Tuning gives (boss_hp_per_player, boss_hp_per_cycle, still
## the balance levers): World passes party_hp_from(tune) and the cycle row, the same numbers bit for bit.
const PARTY_HP: Array = [1.0, 1.5, 2.0, 2.5]
const CYCLE_HP := 2.0
## Choosing who takes a card left on the floor at the win (_pay_floor_cards): squared px added to a fallen wizard's
## and to an apprentice's distance, so a standing human always comes first, then a standing apprentice.
const CARD_FALLEN_FAR := 1e9
const CARD_APPRENTICE_FAR := 1e6
## The Archlich's own growth over its kind's health. Before the act bosses the Lich came at 5:00 and 10:00 too and
## the cycle row made the third visit 5x; each kind now comes once, so it is written here (today's health: 6 cost
## the solo veteran bots a win at 18:00; job L).
const FINAL_HP := 5.0
## The Lich's enraged set starts under half health.
const LICH_RAGE := 0.5
## The Archlich's three phases: LICH LORD down to ARCH_ASCEND, ASCENDANT down to ARCH_PAGE, then THE NINTH PAGE.
const ARCH_ASCEND := 0.75
const ARCH_PAGE := 0.35
## A boss with no phase table of its own turns at half health.
const PHASE_AT := 0.5


## The schedule from the Tuning: a visit every boss_every_min minutes before run_minutes (the ACT_KINDS in order,
## then the Lich), the final Lich then.
static func schedule_from(tune: Tuning) -> Array:
	var rows: Array = []
	var every := maxi(1, int(tune.boss_every_min))
	var end := int(tune.run_minutes)
	var m := every
	while m < end:
		rows.append([m * 60.0, ACT_KINDS[rows.size()] if rows.size() < ACT_KINDS.size() else Bestiary.LICH, false])
		m += every
	rows.append([end * 60.0, Bestiary.LICH, true])
	return rows


## The schedule row whose time falls in (prev_t, t], or -1.
static func due(prev_t: float, t: float, sched: Array = SCHEDULE) -> int:
	for i in sched.size():
		var at: float = sched[i][0]
		if at > prev_t and at <= t:
			return i
	return -1


## The run second of the final boss (the first final row; the last row if none is final).
static func final_time(sched: Array = SCHEDULE) -> float:
	for row: Array in sched:
		if row[2]:
			return row[0]
	return sched[-1][0] if not sched.is_empty() else INF


## PARTY_HP from the Tuning's boss_hp_per_player.
static func party_hp_from(tune: Tuning) -> Array:
	var out: Array = []
	for n: int in range(1, PARTY_HP.size() + 1):
		out.append(1.0 + tune.boss_hp_per_player * (n - 1))
	return out


## The PARTY_HP share for World `w`'s party: the row of its size, or, with apprentices (each counts
## tune.apprentice_scale of a wizard, World.party_weight), a straight line between the two rows around its weight.
static func party_share(w: World) -> float:
	var table := party_hp_from(w.tune)
	var n := clampf(w.party_weight(), 1.0, float(table.size()))
	var lo := int(floor(n))
	if lo >= table.size() or n == float(lo):
		return float(table[lo - 1])
	return lerpf(float(table[lo - 1]), float(table[lo]), n - float(lo))


## A boss's health in World `w` now (its schedule, party size and Tuning levers).
static func health_in(w: World, type: int) -> float:
	return w.tune.boss_hp_mul * health(type, w.wave, 1, w.seal_boss, 0.0, w.schedule, [party_share(w)], w.tune.boss_hp_per_cycle)


## The final boss's health in World `w`: its kind's health with no cycle growth (FINAL_HP stands for it), times
## final_hp_mul and the final_hp_per_player share.
static func final_health_in(w: World, type: int) -> float:
	return w.tune.boss_hp_mul * health(type, w.wave, 1, w.seal_boss, 0.0, w.schedule, [party_share(w)], 0.0) \
		* FINAL_HP * w.tune.final_hp_mul * (1.0 + w.tune.final_hp_per_player * (w.party_weight() - 1.0))


## How many rows of `type` come at or before run second `t` (the Lich's visits so far).
static func visits(type: int, t: float, sched: Array = SCHEDULE) -> int:
	var n := 0
	for row: Array in sched:
		if int(row[1]) == type and float(row[0]) <= t:
			n += 1
	return n


## A boss's health on minute `wave` for `wizards` wizards: its KINDS hp, times PARTY_HP, times CYCLE_HP growth for
## each earlier visit of its kind, times the difficulty's `seal_mul`, less the `wounds` share (broken wards).
static func health(type: int, wave: int, wizards: int, seal_mul: float, wounds: float, sched: Array = SCHEDULE,
		party: Array = PARTY_HP, cycle: float = CYCLE_HP) -> float:
	var scale: float = party[clampi(wizards, 1, party.size()) - 1] * (1.0 + cycle * maxi(0, visits(type, (wave - 1) * 60.0, sched) - 1))
	return float(Bestiary.KINDS[type][Bestiary.K_HP]) * scale * seal_mul * (1.0 - wounds)


## The phase a boss is in at this health fraction: 0 first, 1 after its first turn. The Lich rages (1) under
## LICH_RAGE; the Archlich (`final`) is ASCENDANT (1) under ARCH_ASCEND and on THE NINTH PAGE (2) under ARCH_PAGE.
static func phase(type: int, hp_frac: float, final: bool = false) -> int:
	match type:
		Bestiary.LICH:
			if final:
				return 2 if hp_frac < ARCH_PAGE else (1 if hp_frac < ARCH_ASCEND else 0)
			return 1 if hp_frac < LICH_RAGE else 0
	return 0 if hp_frac >= PHASE_AT else 1


## The boss's brain. Its rows about to land act first (_landings). While it turns a phase (phase_turn) it holds
## still and nothing hurts it.
static func think(w: World, e: World.Enemy, dt: float, tgt: World.Player, dirv: Vector2, dist: float) -> Vector2:
	if e.state == FRESH:
		e.state = 0
		e.enter_dir = Vector2.ZERO
		e.dir = Vector2.ZERO
		e.count = 0.0
		e.timer2 = 0.0
	_landings(w, e, dt)
	if e.turn > 0.0:
		e.turn = maxf(0.0, e.turn - dt)
		return Vector2.ZERO
	match e.type:
		Bestiary.LICH:
			return BossLich.think(w, e, dt, tgt, dirv, dist)
		Bestiary.CHANDELIER:
			return BossChandelier.think(w, e, dt, tgt, dirv, dist)
		Bestiary.GHOSTWRITER:
			return BossGhostwriter.think(w, e, dt, tgt, dirv, dist)
	return dirv * e.spd


# ======================================================= SHARED ATTACKS ===
# A boss's own memory past its entry lives in Enemy.enter_dir (unused once it is in): y counts the phase turns it
# has made, x is the boss file's. An act boss arrives FRESH: its first think clears that memory (the door's heading
# is in enter_dir until then) and starts it at step 0.
const FRESH := 99 # not -1: the arena times states from a -1 "none seen"

## What a boss row does as it lands, beyond its kind (Hazard.aux bits on a boss's BLAST, FLAME or SAFE row):
## AUX_HEAVY hurts HEAVY_HEARTS, AUX_FIRE leaves a FIRE disc, AUX_SHELF lights the lane SHELF_STEP px to its right.
const AUX_HEAVY := 1
const AUX_FIRE := 2
const AUX_SHELF := 4
const HEAVY_HEARTS := 2
## The FIRE a NAME leaves: radius px, burn s.
const LEFT_FIRE_R := 22.0
const LEFT_FIRE_HOT := 5.0
## SHELF's second set of lanes: the step to the right px, warning s, burn s.
const SHELF_STEP := 76.0
const SHELF_EVEN_WARN := 1.3
const SHELF_HOT := 0.6
## LAST CANDLE: the SAFE disc may lie at most this far from any living wizard, px; else it sits CANDLE_OFF px from
## the party's middle on the side away from the boss.
const CANDLE_REACH := 150.0
const CANDLE_OFF := 60.0
## Allies within this many px of a wizard make a knot (DROP falls on the tightest).
const KNOT_R := 40.0
## How far rows keep off the arena's walls, px.
const WALL_INSET := 12.0


## The boss rows turning hot this tick act first (World runs the rows after the enemies): a heavy blast hurts its
## wizards HEAVY_HEARTS (the row's own heart then finds them shielded), a NAME leaves fire, a SHELF lane lights the
## next. Runs during a phase turn too.
static func _landings(w: World, e: World.Enemy, dt: float) -> void:
	var adds: Array[Hazards.Hazard] = []
	for h: Hazards.Hazard in w.hazards:
		if not h.boss or h.fired or h.warn > dt or h.aux == 0 or h.owner != e.id:
			continue
		if h.kind != Hazards.BLAST and h.kind != Hazards.FLAME and h.kind != Hazards.SAFE:
			continue
		if h.aux & AUX_HEAVY:
			for p: World.Player in w.players.values():
				if p.alive and Hazards.contains(h, p.pos):
					WorldPlayers.hurt_player(w, p, HEAVY_HEARTS)
		if h.aux & AUX_FIRE:
			adds.append(h)
		if h.aux & AUX_SHELF:
			adds.append(h)
		h.aux = 0 # landed: acts once
	for h: Hazards.Hazard in adds:
		if h.kind == Hazards.BLAST:
			w.add_hazard(Hazards.FIRE, h.a, h.a, LEFT_FIRE_R, 0.0, LEFT_FIRE_HOT, -1, e.id)
		else:
			var step := Vector2(SHELF_STEP, 0.0)
			if h.a.x + SHELF_STEP < G.ARENA.end.x:
				w.add_hazard(Hazards.FLAME, h.a + step, h.b + step, h.r, SHELF_EVEN_WARN, SHELF_HOT, -1, e.id)


## The living wizards a boss may aim at, at most two: the one in the tightest knot (most allies within KNOT_R, then
## nearest the boss), then the one farthest from the boss. Fallen spirits are never aimed at.
static func aims(w: World, e: World.Enemy) -> Array[World.Player]:
	var live: Array[World.Player] = []
	for p: World.Player in w.players.values():
		if p.alive:
			live.append(p)
	var out: Array[World.Player] = []
	if live.is_empty():
		return out
	var knot := knot_of(w)
	out.append(knot)
	var far: World.Player = null
	for p: World.Player in live:
		if p != knot and (far == null or p.pos.distance_squared_to(e.pos) > far.pos.distance_squared_to(e.pos)):
			far = p
	if far != null:
		out.append(far)
	return out


## The living wizard with the most living allies within KNOT_R (ties: the lowest slot), or null.
static func knot_of(w: World) -> World.Player:
	var best: World.Player = null
	var best_n := -1
	for p: World.Player in w.players.values():
		if not p.alive:
			continue
		var n := 0
		for q: World.Player in w.players.values():
			if q != p and q.alive and q.pos.distance_to(p.pos) <= KNOT_R:
				n += 1
		if n > best_n or (n == best_n and p.slot < best.slot):
			best = p
			best_n = n
	return best


## The living wizard farthest from `at`, or null.
static func farthest_from(w: World, at: Vector2) -> World.Player:
	var best: World.Player = null
	for p: World.Player in w.players.values():
		if p.alive and (best == null or p.pos.distance_squared_to(at) > best.pos.distance_squared_to(at)):
			best = p
	return best


## Where LAST CANDLE's SAFE disc goes: on a fallen wizard's grave when every living wizard is within CANDLE_REACH of
## it, else CANDLE_OFF px from the party's middle away from the boss at `from`, pulled in until no living wizard is
## over CANDLE_REACH from it, else the middle of the party's spread. Vector2.INF when no spot is within reach of every
## living wizard (or none lives): that candle is skipped, since a SAFE disc someone cannot reach is a sure hit.
static func candle_spot(w: World, from: Vector2) -> Vector2:
	var live: Array[Vector2] = []
	for p: World.Player in w.players.values():
		if p.alive:
			live.append(p.pos)
	if live.is_empty():
		return Vector2.INF
	for p: World.Player in w.players.values():
		if p.down and _reach_all(live, p.pos):
			return p.pos
	var c := w.party_center()
	var away := (c - from).normalized() if c.distance_to(from) > 1.0 else Vector2.DOWN
	var steps := 6
	for k: int in range(steps, -1, -1):
		var at := inside(c + away * CANDLE_OFF * k / steps)
		if _reach_all(live, at):
			return at
	var lo := live[0]
	var hi := live[0]
	for v: Vector2 in live:
		lo = lo.min(v)
		hi = hi.max(v)
	var mid := inside((lo + hi) * 0.5)
	return mid if _reach_all(live, mid) else Vector2.INF


static func _reach_all(live: Array[Vector2], at: Vector2) -> bool:
	for v: Vector2 in live:
		if v.distance_to(at) > CANDLE_REACH:
			return false
	return true


## `p` kept WALL_INSET px inside the arena.
static func inside(p: Vector2) -> Vector2:
	var r := G.ARENA.grow(-WALL_INSET)
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))


## Where a ray from `from` along `dir` meets the arena kept `inset` px inside its walls.
static func to_wall(from: Vector2, dir: Vector2, inset: float) -> Vector2:
	var r := G.ARENA.grow(-inset)
	var p := Vector2(clampf(from.x, r.position.x, r.end.x), clampf(from.y, r.position.y, r.end.y))
	var t := INF
	if dir.x > 0.001:
		t = minf(t, (r.end.x - p.x) / dir.x)
	elif dir.x < -0.001:
		t = minf(t, (r.position.x - p.x) / dir.x)
	if dir.y > 0.001:
		t = minf(t, (r.end.y - p.y) / dir.y)
	elif dir.y < -0.001:
		t = minf(t, (r.position.y - p.y) / dir.y)
	return p if t == INF else p + dir * maxf(t, 0.0)


## Moves `e` straight toward `to` at `speed`; true once it is there. Bosses steer their scripted paths this way (the
## brain then wants no velocity), so a lane is walked exactly.
static func glide(e: World.Enemy, to: Vector2, speed: float, dt: float) -> bool:
	e.pos = e.pos.move_toward(to, speed * dt)
	return e.pos.distance_to(to) < 0.5


## The boss's own row with id `id`, or null once it is gone.
static func row(w: World, id: int) -> Hazards.Hazard:
	for h: Hazards.Hazard in w.hazards:
		if h.id == id:
			return h
	return null


## Its latest row of `kind` still on the floor, or null.
static func last_row(w: World, e: World.Enemy, kind: int) -> Hazards.Hazard:
	for i: int in range(w.hazards.size() - 1, -1, -1):
		var h: Hazards.Hazard = w.hazards[i]
		if h.owner == e.id and h.kind == kind:
			return h
	return null


## Removes the boss's rows still warning (a phase turn cancels the attack under way; its fire stays).
static func drop_warnings(w: World, e: World.Enemy) -> void:
	w.hazards = w.hazards.filter(func(h: Hazards.Hazard) -> bool: return h.owner != e.id or h.fired)


## A ring of `n` enemy shots of `kind` from `at` at `speed` px/s, turned by `off` rad.
static func ring(w: World, kind: int, at: Vector2, n: int, speed: float, off: float) -> void:
	for i: int in n:
		w.eshot(kind, at, Vector2.from_angle(off + TAU * i / n) * speed, 3.0)
	w.emit(World.EV_ESHOT, at.x, at.y, kind, 1)


## Lays a stretch of burning trail behind a boss gliding along `dir` at `speed`: from where it was `secs` ago to now.
static func trail(w: World, e: World.Enemy, dir: Vector2, speed: float, secs: float, hw: float, hot: float) -> void:
	if secs <= 0.0:
		return
	w.add_hazard(Hazards.FLAME, e.pos - dir * speed * secs, e.pos, hw, 0.0, hot, -1, e.id)


## Hurts the enemies (not bosses) within `r` px of `at` by `dmg` x the minute's enemy hp scale, shoving them out.
static func crush(w: World, at: Vector2, r: float, dmg: float, shove: float) -> void:
	var hit := dmg * WorldWaves._hp_scale(w)
	for o: World.Enemy in w._query(at, r + World.CELL):
		if o.dead or o.flags & Bestiary.F_BOSS or o.pos.distance_to(at) > r + o.r:
			continue
		w.damage_enemy(o, hit, -1, (o.pos - at).normalized() * shove, true)


## Brings a boss in now at door 0 (World.spawn_enemy makes it World.boss); `final` makes it the run's last.
static func _spawn_boss(w: World, type: int, final: bool) -> World.Enemy:
	var e := WorldWaves.spawn_enemy(w, type, 0)
	if final:
		_make_final(w, e)
	return e


## What spawn_enemy does for an F_BOSS kind: it becomes World.boss and announces itself.
static func _arrive(w: World, e: World.Enemy) -> void:
	w.boss = e
	_clear_header(w)
	e.state = 0 if e.type == Bestiary.LICH else FRESH
	e.timer = 2.0
	w.emit(World.EV_BOSS, e.pos.x, e.pos.y, 0, e.type)


## The header a boss fills (boss_t, boss_arg, boss_meter) starts empty for each boss.
static func _clear_header(w: World) -> void:
	w.boss_t = 0.0
	w.boss_arg = 0
	w.boss_meter = 0.0


## A boss leaves without dying (the final boss of another kind replaces it): no reward, no lull, the header clears.
static func _leave(w: World, e: World.Enemy) -> void:
	e.dead = true
	w.emit(World.EV_DIE, e.pos.x, e.pos.y - e.r, e.type, -1)
	if w.boss == e:
		w.boss = null
	_clear_header(w)


## Turns a Lich into the Archlich: final_hp_mul times the HP, full health, a bigger body and a meaner pattern.
static func _make_final(w: World, e: World.Enemy) -> void:
	e.final = true
	e.maxhp = final_health_in(w, e.type)
	e.hp = e.maxhp
	e.r += 3.0
	e.state = FRESH
	e.timer = 2.0
	w.emit(World.EV_BOSS, e.pos.x, e.pos.y, 1, e.type)


## A boss turns a phase: it stands untouchable for `secs`, the enemy shots and the regular hazards clear, and
## EV_PHASE tells the arena (a = type, b = the phase it turns to).
static func phase_turn(w: World, e: World.Enemy, secs: float) -> void:
	e.turn = secs
	for s: World.EShot in w.eshots:
		s.dead = true
	w.clear_hazards(false)
	w.emit(World.EV_PHASE, e.pos.x, e.pos.y, e.type, phase(e.type, e.hp / e.maxhp, e.final))


## A boss died (Brains.on_death): the field clears, it pays out (the final boss only its burst of gems and coins),
## the fallen rise, the lull starts (or the run is won). Moved whole from the Lich branch of WorldEnemies._kill_enemy.
static func _boss_died(w: World, e: World.Enemy, slot: int) -> void:
	_clear_header(w)
	w.boss = null
	w.liches_slain += 1
	if e.final:
		w.record.note(w.wave_time, Results.M_ARCHLICH, slot)
	elif e.type == World.LICH:
		w.record.note(w.wave_time, Results.M_LICH, slot) # the LICH achievement reads this
	else:
		w.record.note(w.wave_time, Results.M_ACT_BOSS, slot, e.type)
	for o in w.enemies:
		if not o.dead and o != e:
			o.dead = true
			w.emit(World.EV_DIE, o.pos.x, o.pos.y - o.r, o.type, -1)
	for s in w.eshots:
		s.dead = true
	for i in 14:
		WorldDrops._drop(w, World.PK_GEM if i % 2 == 0 else World.PK_COIN, e.pos, Vector2.from_angle(i * TAU / 14) * 90.0)
	if not e.final: # the final boss ends the run: a chest, potion or tome would lie there unused
		if w.no_potions <= 0.0: WorldDrops._drop(w, World.PK_POTION, e.pos, Vector2(0, 40)) # THE HIEROPHANT
		WorldLevels._drop_party_tome(w, e.pos)
		for i in w.players.size():
			WorldDrops._drop(w, World.PK_CHEST, e.pos, Vector2.from_angle(PI * 0.5 + (i - (w.players.size() - 1) * 0.5) * 0.7) * 60.0,
				w.tune.chest_life, int(w.tune.boss_chest_luck))
	w.emit(World.EV_BOSSDIE, e.pos.x, e.pos.y - 14, slot, 1 if e.final else 0)
	WorldPlayers.raise_fallen(w, slot)
	if e.final:
		_pay_floor_cards(w, slot)
		w.won = true
		w.victory_t = w.tune.victory_delay
		for q: World.Player in w.players.values():
			q.invuln = maxf(q.invuln, w.tune.victory_delay + 1.0)
		w.emit(World.EV_VICTORY, e.pos.x, e.pos.y, slot, 0)
	w.spawn_queue.clear()
	w.horde_budget = 0.0
	w._next_group = []
	if not e.final and w.tune.lull_seconds > 0.0:
		w.lull_left = w.tune.lull_seconds
		var c := w.party_center()
		w.emit(World.EV_LULL, c.x, c.y, w.lull_left, 0)
	w.clear_hazards(true)


## The Archlich's card (and any other on the floor) goes to the slayer, else the nearest wizard (a living human
## first, then a living apprentice: an apprentice takes no cards while a human can), so the win cannot leave it behind.
static func _pay_floor_cards(w: World, slot: int) -> void:
	for k: World.Pickup in w.pickups:
		if k.kind != World.PK_CARD or k.life <= 0.0:
			continue
		var who: World.Player = w.players.get(slot)
		if who == null or not who.alive or who.ai:
			var best := INF
			for q: World.Player in w.players.values():
				var d := q.pos.distance_squared_to(k.pos) + (0.0 if q.alive else CARD_FALLEN_FAR) \
					+ (CARD_APPRENTICE_FAR if q.ai else 0.0)
				if d < best:
					best = d
					who = q
		if who == null:
			return
		k.life = -1.0
		WorldDrops._collect(w, who, k)
