class_name WorldHazards
extends RefCounted
## Hazard rows for World (Hazards): adding and moving them, running them each step between the enemies and the
## shots, and the nova clearing them. Static helpers; the first argument is the World.


## A new row, or null when Hazards.can_add says the floor is full (`forced` skips the regular caps). The warning is
## never shorter than Hazards.min_warn(r) for a row that can hurt. `owner` is the enemy id that made it: its death
## during the warning removes the row; the boss's rows are boss rows.
static func add_hazard(w: World, kind: int, a: Vector2, b: Vector2, r: float, warn: float, hot: float, slot: int = -1,
		owner: int = 0, forced: bool = false) -> Hazards.Hazard:
	var boss := w.boss != null and owner != 0 and owner == w.boss.id
	if not Hazards.can_add(w.hazards, w.party_center(), boss, forced):
		return null
	var h := Hazards.Hazard.new()
	h.id = w.next_hazard_id
	w.next_hazard_id += 1
	h.kind = kind
	h.a = a
	h.b = b
	h.r = r
	var row: Array = Hazards.KINDS[kind]
	if int(row[Hazards.K_HEARTS]) > 0 or row[Hazards.K_INVERTED]:
		warn = maxf(warn, Hazards.min_warn(r))
	h.warn = warn
	h.warn0 = warn
	h.hot = hot
	h.slot = slot
	h.owner = owner
	h.boss = boss
	w.hazards.append(h)
	return h


static func move_hazard(_w: World, h: Hazards.Hazard, a: Vector2, b: Vector2) -> void:
	h.a = a
	h.b = b


## One step: rows whose maker died while warning go; the clocks run; rows turning hot fire their on_hot once; hot
## rows hurt the wizards in them (outside, for an inverted row); spent rows go.
static func _update_hazards(w: World, dt: float) -> void:
	if w.hazards.is_empty():
		return
	var owned := false
	for h: Hazards.Hazard in w.hazards:
		owned = owned or (h.owner != 0 and h.warn > 0.0)
	if owned:
		var living := {}
		for e: World.Enemy in w.enemies:
			if not e.dead:
				living[e.id] = true
		w.hazards = w.hazards.filter(func(h: Hazards.Hazard) -> bool: return h.warn <= 0.0 or h.owner == 0 or living.has(h.owner))
	var at := {}
	for p: World.Player in w._plist:
		if p.alive:
			at[p.slot] = p.pos
	for h: Hazards.Hazard in Hazards.tick(w.hazards, dt, at):
		_fire(w, h)
	for h: Hazards.Hazard in w.hazards:
		if h.warn > 0.0 or h.hot <= 0.0:
			continue
		var row: Array = Hazards.KINDS[h.kind]
		var hearts: int = row[Hazards.K_HEARTS]
		if hearts <= 0:
			continue
		for p: World.Player in w._plist:
			if p.alive and p.invuln <= 0.0 and Hazards.contains(h, p.pos) != bool(row[Hazards.K_INVERTED]):
				WorldPlayers.hurt_player(w, p, hearts)
	for h: Hazards.Hazard in w.hazards:
		if h.warn <= 0.0 and h.hot <= 0.0:
			w.hazards = w.hazards.filter(func(o: Hazards.Hazard) -> bool: return o.warn > 0.0 or o.hot > 0.0)
			break


## What a row does once, as it turns hot (Hazards.tick hands each row over once): a blast that hurts and shoves
## enemies (credited to its slot), a ring of enemy shots, or an enemy landing.
static func _fire(w: World, h: Hazards.Hazard) -> void:
	var row: Array = Hazards.KINDS[h.kind]
	match int(row[Hazards.K_ON_HOT]):
		Hazards.ON_BLAST:
			var dmg: float = float(row[Hazards.K_FOE_DMG]) * (1.0 + w.tune.enemy_hp_per_min * (w.wave - 1))
			for e: World.Enemy in w._query(h.a, h.r + World.CELL):
				if e.dead or e.id == h.owner or (h.boss and e.flags & Bestiary.F_BOSS):
					continue # a blast spares its maker, and a boss's blast spares the bosses
				if Hazards.contains(h, e.pos):
					var push: Vector2 = (e.pos - h.a).normalized() * float(row[Hazards.K_FOE_SHOVE])
					WorldEnemies._damage_enemy(w, e, dmg, h.slot, push, true)
		Hazards.ON_SHOTS:
			var n: int = h.aux % Hazards.SHOT_KIND
			for i in n:
				var dir := Vector2.from_angle(TAU * i / maxi(n, 1))
				var s := WorldEnemies._eshot(w, h.aux / Hazards.SHOT_KIND, h.a, dir * Hazards.SHOT_SPEED, Hazards.SHOT_R)
				if s != null:
					s.life = Hazards.SHOT_LIFE
		Hazards.ON_SPAWN:
			WorldWaves.spawn_enemy(w, h.aux, 0, h.a)


## The nova clears the regular rows within Hazards.NOVA_CLEAR of `at`.
static func nova_clear(w: World, at: Vector2) -> void:
	w.hazards = w.hazards.filter(func(h: Hazards.Hazard) -> bool:
		return h.boss or Geometry2D.get_closest_point_to_segment(at, h.a, h.b).distance_to(at) > Hazards.NOVA_CLEAR)
