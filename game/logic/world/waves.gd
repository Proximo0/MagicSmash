class_name WorldWaves
extends RefCounted
## The horde for World: the run's minutes, omens, rifts, groups through the doors, elites and powerups. Static helpers; the first argument is the World.


## A new minute: announce it. At every boss_every_min minute mark (5:00, 10:00, ...) the Lich comes, unless it is
## still here.
static func _tick_minute(w: World) -> void:
	var minute := int(w.wave_time / 60.0) + 1
	if minute <= w.wave:
		return
	w.wave = minute
	WorldDrops._refill_urns(w)
	if w.wave >= final_minute(w) and not w._final_called:
		w._final_called = true
		w.emit(World.EV_WAVE, 0, 0, w.wave, 2)
		if w.boss != null and not w.boss.dead:
			WorldBosses._make_final(w, w.boss) # a Lich still standing ascends
		else:
			w.spawn_queue.append({"t": w.wave_time + 2.5, "type": World.LICH, "door": 0, "final": true})
			_sort_queue(w)
		return
	var boss_minute := w.wave < final_minute(w) and WorldBosses._lich_visits(w, w.wave) > WorldBosses._lich_visits(w, w.wave - 1)
	w.emit(World.EV_WAVE, 0, 0, w.wave, 1 if boss_minute else 0)
	for i in World.OMENS.size():
		if int(World.OMENS[i][0]) == w.wave:
			_queue_omen(w, i)
	if boss_minute and w.boss == null:
		w.spawn_queue.append({"t": w.wave_time + 2.5, "type": World.LICH, "door": 0})
		_sort_queue(w)


## Starts omen `i`: announces it and queues its horde OMEN_WARN seconds out.
static func _queue_omen(w: World, i: int) -> void:
	var o: Array = World.OMENS[i]
	var type: int = o[1]
	var n: int = o[2]
	var t := w.wave_time + World.OMEN_WARN
	if not o[3]:
		w.emit(World.EV_OMEN, G.ARENA.get_center().x, G.ARENA.get_center().y, i, 0)
		for d in World.DOORS.size():
			_queue_group(w, type, n / World.DOORS.size(), d, t)
		_sort_queue(w)
		return
	var c := Vector2.ZERO
	var alive := 0
	for p: World.Player in w.players.values():
		if p.alive:
			c += p.pos
			alive += 1
	c = c / alive if alive > 0 else G.ARENA.get_center()
	w.emit(World.EV_OMEN, c.x, c.y, i, World.OMEN_RING_R)
	var inner := G.ARENA.grow(-10.0)
	for k in n:
		var at := c + Vector2.from_angle(TAU * k / n) * World.OMEN_RING_R
		at = Vector2(clampf(at.x, inner.position.x, inner.end.x), clampf(at.y, inner.position.y, inner.end.y))
		w.spawn_queue.append({"t": t + k * 0.02, "type": type, "door": 0, "at": at})
	_sort_queue(w)


## The minute the Archlich comes: the one that starts at run_minutes:00. No Lich visits after it.
static func final_minute(w: World) -> int:
	return int(w.tune.run_minutes) + 1


## The horde earns spawn budget every second (more each minute, scaled by party size, less while the Lich is
## up) and spends it on the group it rolled, from a random door. At the enemy cap it holds: enemies on the field
## and enemies still queued both count, so the field never grows much past the cap.
static func _direct_horde(w: World, dt: float) -> void:
	if w.lull_left > 0.0:
		return # the lull: no groups, elites or rifts, and no budget earned
	w.elite_t += dt
	if w.elite_t >= w.tune.elite_interval:
		w.elite_t -= w.tune.elite_interval
		_spawn_elite(w)
	if w.enemies.size() + w.spawn_queue.size() >= int(w.tune.enemy_cap):
		return
	var rate := (w.tune.horde_rate_base + w.tune.horde_rate_per_min * w.wave_time / 60.0) * w.pscale()
	if w.boss != null:
		rate *= w.tune.horde_boss_mul
	w.horde_budget += rate * dt
	if w._next_group.is_empty():
		w._next_group = _roll_group(w)
	var cost: float = _horde_row(w, w._next_group[0])[1] * w._next_group[1]
	if w.horde_budget >= cost:
		w.horde_budget -= cost
		if w.rng.randf() < w.tune.rift_share:
			_queue_rift(w, w._next_group[0], w._next_group[1])
		else:
			_queue_group(w, w._next_group[0], w._next_group[1], _pick_door(w), w.wave_time)
		_sort_queue(w)
		w._next_group = []


## A rift: a marker opens somewhere in the arena away from the wizards, and after tune.rift_warning the
## group bursts out of it in a clump, so the horde surrounds the party instead of queuing at the doors.
static func _queue_rift(w: World, type: int, n: int) -> void:
	var best := _spot_near_party(w, w.tune.rift_min_dist, w.tune.rift_max_dist, 22.0)
	var spread := 6.0 + 3.0 * sqrt(float(n))
	w.emit(World.EV_RIFT, best.x, best.y, spread, w.tune.rift_warning)
	for i in n:
		var off := Vector2.from_angle(w.rng.randf() * TAU) * w.rng.randf() * spread
		w.spawn_queue.append({"t": w.wave_time + w.tune.rift_warning + i * 0.03, "type": type, "door": 0, "at": best + off})


## A door for a group: usually the one nearest the party (the arena is bigger than the screen, and a far door
## would leave the group walking for half a minute), otherwise any door.
static func _pick_door(w: World) -> int:
	if w.rng.randf() >= w.tune.door_near_share:
		return w.rng.randi_range(0, World.DOORS.size() - 1)
	var c := w.party_center()
	var best := 0
	for d in World.DOORS.size():
		if (World.DOORS[d] as Vector2).distance_to(c) < (World.DOORS[best] as Vector2).distance_to(c):
			best = d
	return best


## A point in the arena (inset by `margin`) between `min_dist` and `max_dist` from the middle of the party and at
## least `min_dist` from every living wizard: just off the edge of the screen, the way a survivors horde closes
## in. Falls back to the try farthest from the wizards.
static func _spot_near_party(w: World, min_dist: float, max_dist: float, margin: float) -> Vector2:
	var area := G.ARENA.grow(-margin)
	var c := w.party_center()
	var best := area.get_center()
	var best_d := -1.0
	for tries in 12:
		var at := c + Vector2.from_angle(w.rng.randf() * TAU) * w.rng.randf_range(min_dist, maxf(min_dist, max_dist))
		at = at.clamp(area.position, area.end)
		var d := INF
		for p: World.Player in w.players.values():
			if p.alive:
				d = minf(d, p.pos.distance_to(at))
		if d > best_d:
			best_d = d
			best = at
		if d >= min_dist:
			break
	return best


## A weighted pick among the unlocked HORDE rows, with its group size: [type, count].
static func _roll_group(w: World) -> Array:
	var total := 0
	for row: Array in World.HORDE:
		if w.wave_time >= row[2]:
			total += int(row[3])
	var r := w.rng.randi_range(1, total)
	for row: Array in World.HORDE:
		if w.wave_time < row[2]:
			continue
		r -= int(row[3])
		if r <= 0:
			return [row[0], w.rng.randi_range(row[4], row[5] + row[6] * (w.wave - 1))]
	return [World.GOBLIN, 1]


static func _horde_row(w: World, type: int) -> Array:
	for row: Array in World.HORDE:
		if row[0] == type:
			return row
	return World.HORDE[0]


## An elite: a big, glowing, much tougher enemy that pays out in XP, gems and a tome.
static func _spawn_elite(w: World) -> void:
	var type := World.SKELETON
	var roll := w.rng.randf()
	if w.wave >= 10:
		type = World.GARGOYLE if roll < 0.4 else (World.PRIEST if roll < 0.7 else World.ORC)
	elif w.wave >= 6:
		type = World.PRIEST if roll < 0.35 else (World.ORC if roll < 0.7 else World.MAGE)
	elif w.wave >= 4:
		type = World.ORC if roll < 0.6 else World.MAGE
	elif w.wave >= 2:
		type = World.ORC
	var e := spawn_enemy(w, type, _pick_door(w))
	e.elite = true
	e.hp *= w.tune.elite_hp_mul
	e.maxhp = e.hp
	e.r += 2.0
	w.emit(World.EV_ELITE, e.pos.x, e.pos.y, e.type, 0)


static func _queue_group(w: World, type: int, n: int, door: int, t: float) -> void:
	for i in n:
		w.spawn_queue.append({"t": t + i * World.DOOR_STAGGER, "type": type, "door": door})


static func _sort_queue(w: World) -> void:
	w.spawn_queue.sort_custom(func(a, b): return a.t < b.t)


static func _process_spawns(w: World) -> void:
	if w.lull_left > 0.0:
		return # queued spawns (an omen's horde, the next Lich) wait for the lull to end
	while not w.spawn_queue.is_empty() and w.spawn_queue[0].t <= w.wave_time:
		var s: Dictionary = w.spawn_queue.pop_front()
		var e := spawn_enemy(w, s.type, s.door, s.get("at"))
		if s.get("final", false):
			WorldBosses._make_final(w, e)


static func spawn_enemy(w: World, type: int, door: int, at: Variant = null) -> World.Enemy:
	var e := World.Enemy.new()
	e.id = w.next_id
	w.next_id += 1
	e.type = type
	var st: Array = World.STATS[type]
	var hp_scale := (1.0 + w.tune.enemy_hp_per_min * (w.wave - 1)) * pow(w.tune.enemy_hp_growth, w.wave - 1) \
		* (1.0 + w.tune.enemy_hp_per_player * (w.players.size() - 1))
	if type == World.LICH:
		hp_scale = WorldBosses._lich_hp_scale(w)
	e.hp = st[0] * hp_scale
	e.maxhp = e.hp
	e.spd = st[1] * w.tune.enemy_speed_mul * (1.0 + w.tune.enemy_speed_per_min * minf(w.wave, w.tune.enemy_speed_min_cap))
	e.r = st[2]
	e.contact = st[4]
	e.t = w.rng.randf() * 10.0
	e.timer = w.rng.randf_range(1.0, 2.5)
	if at != null:
		e.pos = at
		e.entering = false
	else:
		var jitter := Vector2(w.rng.randf_range(-14, 14), 0) if door < 2 else Vector2(0, w.rng.randf_range(-14, 14))
		e.pos = World.DOORS[door] + jitter
		e.enter_dir = World.DOOR_DIRS[door]
		if w.door_open[door] <= 0.0:
			w.emit(World.EV_DOOR, World.DOORS[door].x, World.DOORS[door].y, door, 0)
		w.door_open[door] = 1.2
	if type == World.LICH:
		w.boss = e
		e.state = 0
		e.timer = 2.0
		w.emit(World.EV_BOSS, e.pos.x, e.pos.y, 0, 0)
	w.enemies.append(e)
	return e


static func _spawn_random_powerup(w: World) -> void:
	var kinds := World.TOMES + [World.PK_BOOTS, World.PK_ORBIT, World.PK_TOME_FIRE, World.PK_TOME_STORM]
	var k: int = kinds[w.rng.randi() % kinds.size()]
	var pos := Vector2.ZERO
	for tries in 12:
		pos = Vector2(w.rng.randf_range(G.ARENA.position.x + 30, G.ARENA.end.x - 30),
			w.rng.randf_range(G.ARENA.position.y + 24, G.ARENA.end.y - 24))
		var ok := true
		for p in w.players.values():
			if p.pos.distance_to(pos) < 50:
				ok = false
		if ok:
			break
	WorldDrops._drop(w, k, pos, Vector2.ZERO, 12.0)
	w.emit(World.EV_POWERUP, pos.x, pos.y, k, 0)
