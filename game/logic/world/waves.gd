class_name WorldWaves
extends RefCounted
## The horde for World: the run's minutes, omens, rifts, groups through the doors, elites and powerups. Static helpers; the first argument is the World.


## A new minute: announce it. When a boss of w.schedule (Bosses) falls on this minute mark it comes, and a boss
## still up leaves (Bosses._leave: no bounty, no deed), so every boss arrives at its minute; the final row's minute
## brings the final boss, or makes a standing Lich final.
static func _tick_minute(w: World) -> void:
	var minute := int(w.wave_time / 60.0) + 1
	if minute <= w.wave:
		return
	w.wave = minute
	WorldDrops._refill_urns(w)
	if w.wave >= final_minute(w) and not w._final_called:
		w._final_called = true
		w.emit(World.EV_WAVE, 0, 0, w.wave, 2)
		var final_type := _final_type(w)
		if w.boss != null and not w.boss.dead and w.boss.type == final_type:
			Bosses._make_final(w, w.boss) # a Lich still standing ascends
		else:
			if w.boss != null and not w.boss.dead:
				Bosses._leave(w, w.boss) # a boss of another kind gives way to the final one
			w.spawn_queue.append({"t": w.wave_time + 2.5, "type": final_type, "door": 0, "final": true})
			_sort_queue(w)
		return
	var due := Bosses.due((w.wave - 2) * 60.0, (w.wave - 1) * 60.0, w.schedule)
	var boss_minute := w.wave < final_minute(w) and due >= 0
	w.emit(World.EV_WAVE, 0, 0, w.wave, 1 if boss_minute else 0)
	for i in World.OMENS.size():
		if int(World.OMENS[i][0]) == w.wave:
			_queue_omen(w, i)
	if boss_minute:
		if w.boss != null and not w.boss.dead:
			Bosses._leave(w, w.boss) # an act boss still up gives way to the next, as to the final one
		w.spawn_queue.append({"t": w.wave_time + 2.5, "type": int(w.schedule[due][1]), "door": 0})
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


## The minute the Archlich comes: the one that starts at the schedule's final row (run_minutes:00 today). No
## boss visits after it.
static func final_minute(w: World) -> int:
	return int(Bosses.final_time(w.schedule) / 60.0) + 1


## The kind of the schedule's final boss.
static func _final_type(w: World) -> int:
	for row: Array in w.schedule:
		if row[2]:
			return int(row[1])
	return World.LICH


## The horde earns spawn budget every second (more each minute, scaled by party size, less while the Lich is
## up) and spends it on the group it rolled, from a random door. At the enemy cap it holds: enemies on the field
## and enemies still queued both count, so the field never grows much past the cap.
static func _direct_horde(w: World, dt: float) -> void:
	if w.lull_left > 0.0:
		return # the lull: no groups, elites or rifts, and no budget earned
	w.elite_t += dt
	if w.elite_t >= w.tune.elite_interval:
		w.elite_t -= w.tune.elite_interval
		_spawn_elite(w, true)
	if w.enemies.size() + w.spawn_queue.size() >= w.enemy_cap(): # LEGION
		return
	var rate := (w.tune.horde_rate_base + w.tune.horde_rate_per_min * w.wave_time / 60.0) * w.pscale() * w.seal_horde
	if w.boss != null:
		rate *= w.tune.horde_boss_mul
	w.horde_budget += rate * dt
	if w._next_group.is_empty():
		w._next_group = _roll_group(w)
	var parts: Array = w._next_group[1]
	if Bestiary.needs_check(parts) and not Bestiary.trim(parts, _fielded(w), w.players.size(), _boss_coming(w)):
		w._next_group = [] # its cap filled or a boss came while the horde saved for it: roll again next tick
		return
	var cost := 0.0
	for part: Array in w._next_group[1]:
		cost += float(Bestiary.horde_row(part[0])[Bestiary.H_COST]) * int(part[1])
	if w.horde_budget >= cost:
		w.horde_budget -= cost
		_queue_rolled(w, w._next_group)
		_sort_queue(w)
		w._next_group = []


## A rift: a marker opens somewhere in the arena away from the wizards, and after tune.rift_warning the
## group bursts out of it in a clump, so the horde surrounds the party instead of queuing at the doors.
static func _queue_rift(w: World, type: int, n: int) -> void:
	var best := _spot_near_party(w, w.tune.rift_min_dist, w.tune.rift_max_dist, 22.0)
	var spread := 6.0 + 3.0 * sqrt(float(n))
	w.emit(World.EV_RIFT, best.x, best.y, spread, w.tune.rift_warning * w.seal_rift) # AMBUSH
	for i in n:
		var off := Vector2.from_angle(w.rng.randf() * TAU) * w.rng.randf() * spread
		w.spawn_queue.append({"t": w.wave_time + w.tune.rift_warning * w.seal_rift + i * 0.03, "type": type, "door": 0, "at": best + off})


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


## The next group or formation (Bestiary.roll_group): [layout, [[type, count], ...]].
static func _roll_group(w: World) -> Array:
	var rolled: Array = Bestiary.roll_group(w.rng, w.wave_time, Lore.act_of(w.wave - 1), _fielded(w), w.players.size(), _boss_coming(w),
		Bestiary.FORMATIONS, w.tune.new_kinds)
	if w.seal_group != 1.0: # LEGION: bigger groups
		for part: Array in rolled[1]:
			part[1] = int(round(int(part[1]) * w.seal_group))
	return rolled


## Enemies per Bestiary type on the floor or queued to come (doors, rifts, risers), counted now.
static func _fielded(w: World) -> PackedInt32Array:
	var n := PackedInt32Array()
	n.resize(Bestiary.count())
	for e: World.Enemy in w.enemies:
		if not e.dead:
			n[e.type] += 1
	for s: Dictionary in w.spawn_queue:
		n[int(s.type)] += 1
	return n


## True while a boss is up or queued to come.
static func _boss_coming(w: World) -> bool:
	if w.boss != null and not w.boss.dead:
		return true
	for s: Dictionary in w.spawn_queue:
		if Bestiary.has_flag(int(s.type), Bestiary.F_BOSS):
			return true
	return false


## Queues a rolled group by its layout. A plain group comes through a door or, one time in tune.rift_share, a rift;
## RISE comes up from the floor near the party; WALL comes abreast through one door; a formation (layout 8+) by
## its Bestiary.AT_* layout.
static func _queue_rolled(w: World, g: Array) -> void:
	var layout: int = g[0]
	var parts: Array = g[1]
	match layout:
		Bestiary.GROUP:
			var type: int = parts[0][0]
			var n: int = parts[0][1]
			if w.rng.randf() < w.tune.rift_share:
				_queue_rift(w, type, n)
			else:
				_queue_group(w, type, n, _pick_door(w), w.wave_time)
		Bestiary.RISE:
			for part: Array in parts:
				for k in int(part[1]):
					var at := _spot_near_party(w, Bestiary.RISE_MIN, Bestiary.RISE_MAX, Bestiary.RISE_MARGIN)
					w.emit(World.EV_RIFT, at.x, at.y, Bestiary.RISE_SPREAD, w.tune.rift_warning * w.seal_rift) # AMBUSH
					w.spawn_queue.append({"t": w.wave_time + w.tune.rift_warning * w.seal_rift, "type": part[0], "door": 0, "at": at})
		Bestiary.WALL:
			var door := _pick_door(w)
			for part: Array in parts:
				_queue_group(w, part[0], part[1], door, w.wave_time, 0.0)
		_:
			var door := _pick_door(w)
			for i in parts.size():
				var part: Array = parts[i]
				match layout - 8:
					Bestiary.AT_RIFT:
						_queue_rift(w, part[0], part[1])
					Bestiary.AT_OPPOSITE:
						_queue_group(w, part[0], part[1], door if i % 2 == 0 else door ^ 1, w.wave_time)
					_:
						_queue_group(w, part[0], part[1], door, w.wave_time)


## An elite: a big, glowing, much tougher enemy that pays out in XP, gems and a tome. `timed`: one of the horde's
## own timed elites (_direct_horde), the only ones CHAMPIONS escorts (not a curse's or the Archlich's).
static func _spawn_elite(w: World, timed: bool = false) -> void:
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
	e.hp *= w.tune.elite_hp_mul * w.seal_elite_hp # CHAMPIONS
	e.maxhp = e.hp
	e.r += 2.0
	w.emit(World.EV_ELITE, e.pos.x, e.pos.y, e.type, 0)
	# CHAMPIONS: an escort of its own kind through its door, trimmed to the room under the enemy cap.
	var escort := mini(w.seal_escort, w.enemy_cap() - w.enemies.size() - w.spawn_queue.size()) if timed else 0
	if escort > 0:
		_queue_group(w, e.type, escort, World.DOOR_DIRS.find(e.enter_dir), w.wave_time + World.DOOR_STAGGER)
		_sort_queue(w)


static func _queue_group(w: World, type: int, n: int, door: int, t: float, stagger: float = World.DOOR_STAGGER) -> void:
	for i in n:
		w.spawn_queue.append({"t": t + i * stagger, "type": type, "door": door})


static func _sort_queue(w: World) -> void:
	w.spawn_queue.sort_custom(func(a, b): return a.t < b.t)


static func _process_spawns(w: World) -> void:
	if w.lull_left > 0.0:
		return # queued spawns (an omen's horde, the next Lich) wait for the lull to end
	while not w.spawn_queue.is_empty() and w.spawn_queue[0].t <= w.wave_time:
		var s: Dictionary = w.spawn_queue.pop_front()
		var e := spawn_enemy(w, s.type, s.door, s.get("at"))
		if s.get("final", false):
			Bosses._make_final(w, e)


## The health multiplier of a horde enemy spawned this minute: the flat lever, the difficulty step, a little per
## minute, compound growth
## per minute and a share per extra wizard.
static func _hp_scale(w: World) -> float:
	return w.tune.enemy_hp_mul * w.seal_hp * (1.0 + w.tune.enemy_hp_per_min * (w.wave - 1)) * pow(w.tune.enemy_hp_growth, w.wave - 1) \
		* (1.0 + w.tune.enemy_hp_per_player * (w.party_weight() - 1.0))


static func spawn_enemy(w: World, type: int, door: int, at: Variant = null) -> World.Enemy:
	var e := World.Enemy.new()
	e.id = w.next_id
	w.next_id += 1
	e.type = type
	var st: Array = Bestiary.KINDS[type]
	e.flags = st[Bestiary.K_FLAGS]
	if e.flags & Bestiary.F_BOSS:
		e.hp = Bosses.health_in(w, type)
	else:
		e.hp = st[Bestiary.K_HP] * _hp_scale(w)
	e.maxhp = e.hp
	e.spd = st[Bestiary.K_SPD]
	if not e.flags & Bestiary.F_FIXED_SPEED:
		e.spd *= w.tune.enemy_speed_mul * w.seal_speed * (1.0 + w.tune.enemy_speed_per_min * minf(w.wave, w.tune.enemy_speed_min_cap))
	e.r = st[Bestiary.K_R]
	e.contact = st[Bestiary.K_CONTACT]
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
	if e.flags & Bestiary.F_BOSS:
		Bosses._arrive(w, e)
	w.enemies.append(e)
	return e


static func _spawn_random_powerup(w: World) -> void:
	var kinds := [World.PK_BOOTS, World.PK_ORBIT]
	if w.tune.floor_tomes >= 0.5: # spell tomes appear only while tune.floor_tomes is on
		kinds = World.TOMES + [World.PK_BOOTS, World.PK_ORBIT, World.PK_TOME_FIRE, World.PK_TOME_STORM]
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
