class_name Bosses
extends RefCounted
## The bosses: when they come (SCHEDULE), their health by party size and visit, their phases, and what World does
## when one arrives, turns a phase and dies. Any F_BOSS kind can be World.boss; each has its own file with `think`
## and `ATTACKS` (BossLich). Static helpers; World-taking ones have the World first.

## [run s, Bestiary type, final]: today's schedule, the Lich at 5:00 and 10:00 and the Archlich at 15:00. It is what
## schedule_from() builds from the default Tuning (boss_every_min, run_minutes); the act-boss job's switch makes
## World read this table instead (CHANDELIER at 300 s, GHOSTWRITER at 600 s).
const SCHEDULE: Array = [[300.0, Bestiary.LICH, false], [600.0, Bestiary.LICH, false], [900.0, Bestiary.LICH, true]]
## Morvane's visits: [run s, ward base]. Not World.boss; nothing reads this until the act-boss job.
const VISITS: Array = [[420.0, 150.0], [720.0, 400.0]]
## A boss's health multiplier by party size (1 to 4 wizards), and its growth each time the same kind returns (the
## Lich's second visit has 1.25x). The values the default Tuning gives (boss_hp_per_player, boss_hp_per_cycle, still
## the balance levers): World passes party_hp_from(tune) and the cycle row, the same numbers bit for bit.
const PARTY_HP: Array = [1.0, 1.6, 2.2, 2.8]
const CYCLE_HP := 0.25
## Today's rage line: the Lich's enraged set starts under half health, the Archlich's under FINAL_RAGE.
const LICH_RAGE := 0.5
## A boss with no phase table of its own turns at half health.
const PHASE_AT := 0.5


## Today's schedule from the Tuning: a Lich every boss_every_min minutes before run_minutes, the final Lich then.
static func schedule_from(tune: Tuning) -> Array:
	var rows: Array = []
	var every := maxi(1, int(tune.boss_every_min))
	var end := int(tune.run_minutes)
	var m := every
	while m < end:
		rows.append([m * 60.0, Bestiary.LICH, false])
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


## A boss's health in World `w` now (its schedule, party size and Tuning levers).
static func health_in(w: World, type: int) -> float:
	return health(type, w.wave, w.players.size(), 1.0, 0.0, w.schedule, party_hp_from(w.tune), w.tune.boss_hp_per_cycle)


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
## LICH_RAGE, the Archlich (`final`) under World.FINAL_RAGE.
static func phase(type: int, hp_frac: float, final: bool = false) -> int:
	match type:
		Bestiary.LICH:
			return 1 if hp_frac < (World.FINAL_RAGE if final else LICH_RAGE) else 0
	return 0 if hp_frac >= PHASE_AT else 1


## The boss's brain. While it turns a phase (phase_turn) it holds still and nothing hurts it.
static func think(w: World, e: World.Enemy, dt: float, tgt: World.Player, dirv: Vector2, dist: float) -> Vector2:
	if e.turn > 0.0:
		e.turn = maxf(0.0, e.turn - dt)
		return Vector2.ZERO
	match e.type:
		Bestiary.LICH:
			return BossLich.think(w, e, dt, tgt, dirv, dist)
	return dirv * e.spd


## Brings a boss in now at door 0 (World.spawn_enemy makes it World.boss); `final` makes it the run's last.
static func _spawn_boss(w: World, type: int, final: bool) -> World.Enemy:
	var e := WorldWaves.spawn_enemy(w, type, 0)
	if final:
		_make_final(w, e)
	return e


## What spawn_enemy does for an F_BOSS kind: it becomes World.boss and announces itself.
static func _arrive(w: World, e: World.Enemy) -> void:
	w.boss = e
	e.state = 0
	e.timer = 2.0
	w.emit(World.EV_BOSS, e.pos.x, e.pos.y, 0, 0)


## Turns a Lich into the Archlich: final_hp_mul times the HP, full health, a bigger body and a meaner pattern.
static func _make_final(w: World, e: World.Enemy) -> void:
	e.final = true
	e.maxhp = health_in(w, e.type) * w.tune.final_hp_mul
	e.hp = e.maxhp
	e.r += 3.0
	e.state = 0
	e.timer = 2.0
	w.emit(World.EV_BOSS, e.pos.x, e.pos.y, 1, 0)


## A boss turns a phase: it stands untouchable for `secs`, the enemy shots and the regular hazards clear, and
## EV_PHASE tells the arena (a = type, b = the phase it turns to).
static func phase_turn(w: World, e: World.Enemy, secs: float) -> void:
	e.turn = secs
	for s: World.EShot in w.eshots:
		s.dead = true
	w.clear_hazards(false)
	w.emit(World.EV_PHASE, e.pos.x, e.pos.y, e.type, phase(e.type, e.hp / e.maxhp, e.final))


## A boss died (Brains.on_death): the field clears, it pays out, the fallen rise, the lull starts (or the run is
## won). Moved whole from the Lich branch of WorldEnemies._kill_enemy.
static func _boss_died(w: World, e: World.Enemy, slot: int) -> void:
	w.boss = null
	w.liches_slain += 1
	w.record.note(w.wave_time, Results.M_ARCHLICH if e.final else Results.M_LICH, slot)
	for o in w.enemies:
		if not o.dead and o != e:
			o.dead = true
			w.emit(World.EV_DIE, o.pos.x, o.pos.y - o.r, o.type, -1)
	for s in w.eshots:
		s.dead = true
	for i in 14:
		WorldDrops._drop(w, World.PK_GEM if i % 2 == 0 else World.PK_COIN, e.pos, Vector2.from_angle(i * TAU / 14) * 90.0)
	if w.no_potions <= 0.0: WorldDrops._drop(w, World.PK_POTION, e.pos, Vector2(0, 40)) # THE HIEROPHANT
	for i in w.players.size():
		WorldDrops._drop(w, World.PK_CHEST, e.pos, Vector2.from_angle(PI * 0.5 + (i - (w.players.size() - 1) * 0.5) * 0.7) * 60.0,
			w.tune.chest_life, int(w.tune.boss_chest_luck))
	w.emit(World.EV_BOSSDIE, e.pos.x, e.pos.y - 14, slot, 1 if e.final else 0)
	WorldPlayers.raise_fallen(w, slot)
	if e.final:
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
