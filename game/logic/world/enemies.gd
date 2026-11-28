class_name WorldEnemies
extends RefCounted
## Enemies for World: targeting, movement and attacks, separation, enemy shots, damage and death. Static helpers; the first argument is the World.


## The standing wizard the horde wants at `pos`: the least distance / threat (Player.threat_k is 1 / threat^2, so a
## squared distance times it; with every threat 1 this is the nearest wizard, exactly).
static func _nearest_player(w: World, pos: Vector2) -> World.Player:
	if w._plist.size() != w.players.size():
		w._plist.assign(w.players.values())
	var best: World.Player = null
	var bd := INF
	for p: World.Player in w._plist:
		if not p.alive:
			continue
		var d := p.pos.distance_squared_to(pos) * p.threat_k
		if d < bd:
			bd = d
			best = p
	return best


static func _update_enemy(w: World, e: World.Enemy, dt: float) -> void:
	# This runs for every enemy on every tick (most of a step at the enemy cap), so it reads each field once into a
	# local, leaves a timer that is not running alone, and finds the nearest wizard in place.
	e.t += dt
	if e.flash > 0.0:
		e.flash = maxf(0.0, e.flash - dt)
	var sm := 1.0
	if e.slow > 0.0:
		var slow: float = maxf(0.0, e.slow - dt)
		e.slow = slow
		if slow > 0.0:
			sm = 0.45
	if e.orbit_cd > 0.0:
		e.orbit_cd = maxf(0.0, e.orbit_cd - dt)
	if e.entering:
		e.pos += e.enter_dir * maxf(e.spd, 40.0) * dt
		if G.ARENA.grow(-10).has_point(e.pos):
			e.entering = false
		if w._sep_ok and e.gi >= 0:
			w._sep_pos[e.gi] = e.pos
		return
	var from: Vector2 = e.pos
	var tgt: World.Player = null # _nearest_player, in place
	var bd := INF
	for p: World.Player in w._plist:
		if p.alive:
			var d: float = p.pos.distance_squared_to(from) * p.threat_k
			if d < bd:
				bd = d
				tgt = p
	# A PROVOKE holds it on its taunter, who may not be the nearest: then any wizard may be in reach of a touch.
	var taunted := false
	if e.taunt_t > 0.0:
		e.taunt_t -= dt
		if e.taunt.alive and e.taunt_t > 0.0 and w.players.get(e.taunt.slot) == e.taunt: # not a seat that left
			tgt = e.taunt
			taunted = true
	var tpos: Vector2 = tgt.pos if tgt else G.ARENA.get_center() + Vector2(cos(e.t * 0.5), sin(e.t * 0.7)) * 80.0
	var to := tpos - from
	var dist := to.length()
	var dirv := to / maxf(dist, 0.001)
	var desired := Brains.think(w, e, dt, tgt, dirv, dist)
	var vel: Vector2 = e.vel.lerp(desired * sm, minf(1.0, dt * 10.0))
	e.vel = vel
	var knock: Vector2 = e.knock
	var at: Vector2 = e.pos # read again: a brain may have moved it (a blink)
	if knock != Vector2.ZERO:
		at += (vel + knock) * dt
		e.knock = knock.move_toward(Vector2.ZERO, dt * 600.0)
	else:
		at += vel * dt
	var flags: int = e.flags
	# Separation so hordes spread into a crowd instead of a single blob.
	# Half the crowd separates each tick (alternating by id), at double strength: the same spread for half the cost.
	if flags & (Bestiary.F_NO_SEP | Bestiary.F_ANCHORED) == 0 and (e.id + w._tick) % 2 == 0:
		e.pos = at
		_separate(w, e)
		at = e.pos
	var er: float = e.r
	var room: Rect2 = G.ARENA
	at.x = clampf(at.x, room.position.x + er, room.end.x - er)
	at.y = clampf(at.y, room.position.y + er, room.end.y - 2)
	e.pos = at
	if w._sep_ok and e.gi >= 0:
		w._sep_pos[e.gi] = at
	# Contact damage. Nobody can be touched unless the nearest wizard was close when this update began: an enemy
	# moves a few pixels a step. A kind that can teleport (F_BLINK: a mage, the Lich) always checks.
	# A kind with no contact damage (a bloat, a coffin) touches nobody, so it gives no free hurt-invulnerability either.
	# Threat can pick a wizard further than the nearest: at most World.threat_spread times as far as one in reach, so
	# the reach grows by that (it is CONTACT_REACH, as ever, while every threat is the same: the spread is 1).
	if e.contact > 0 and (dist < (er + World.CONTACT_REACH) * w.threat_spread or flags & Bestiary.F_BLINK or taunted):
		for p: World.Player in w._plist:
			if p.alive and p.invuln <= 0.0 and p.pos.distance_to(e.pos) < e.r + 5.0:
				var dmg := e.contact
				if (e.type == World.ORC and e.state == 2) or (e.type == World.GARGOYLE and e.state == 1):
					dmg = 2
				WorldPlayers.hurt_player(w, p, dmg)


## Pushes `e` out of the enemies it overlaps. It reads World's separation copy (see World._sep_cells), not the
## neighbours themselves: a neighbour object is only looked at once it is close enough to touch.
static func _separate(w: World, e: World.Enemy) -> void:
	if not w._sep_ok:
		_sep_fill(w)
	var sp: PackedVector2Array = w._sep_pos
	var sr: PackedFloat64Array = w._sep_r
	var cells: Dictionary = w._sep_cells
	# The position lives in a local and is written back once: reading and writing a field of an object costs about
	# twice a local, and this loop touched e.pos for every neighbour.
	var pos: Vector2 = e.pos
	var er: float = e.r
	var x0 := floori((pos.x - 16.0) / World.CELL)
	var y0 := floori((pos.y - 16.0) / World.CELL)
	for cx: int in range(x0, x0 + 2):
		for cy: int in range(y0, y0 + 2):
			var cell: PackedInt32Array = cells.get(Vector2i(cx, cy), World._NO_ROWS)
			for j: int in cell:
				var dv: Vector2 = pos - sp[j]
				var min_d: float = er + sr[j]
				var d2: float = dv.length_squared()
				if d2 >= min_d * min_d or d2 <= 0.0001:
					continue
				var o: World.Enemy = w._sep_who[j]
				if o == e or o.dead or o.flags & Bestiary.F_NO_BLOCK or o.entering:
					continue
				var dd: float = sqrt(d2)
				pos += dv / dd * (min_d - dd) * (0.5 if o.flags & Bestiary.F_BOSS == 0 else 1.0)
	e.pos = pos


## Fills the separation copy from the enemies as they stand now. World.step calls it before the enemies move;
## after that each _update_enemy writes its own row, since nothing else moves an enemy until the horde is done.
static func _sep_fill(w: World) -> void:
	var who: Array[World.Enemy] = w._sep_who
	var n := who.size()
	var sp: PackedVector2Array = w._sep_pos
	var sr: PackedFloat64Array = w._sep_r
	sp.resize(n)
	sr.resize(n)
	for i: int in n:
		var e: World.Enemy = who[i]
		sp[i] = e.pos
		sr[i] = e.r
		e.gi = i
	w._sep_ok = true


## A new enemy shot, or null past Bestiary.ESHOT_CAP (the shot is dropped).
static func _eshot(w: World, kind: int, pos: Vector2, vel: Vector2, r: float) -> World.EShot:
	if w.eshots.size() >= Bestiary.ESHOT_CAP:
		return null
	var s := World.EShot.new()
	s.kind = kind
	s.pos = pos
	s.vel = vel
	s.r = r
	w.eshots.append(s)
	return s


## A wraith phased out, or any cloaked enemy: shots fly through it and nothing hurts it.
static func _faded(w: World, e: World.Enemy) -> bool:
	return e.cloak or (e.type == World.WRAITH and e.state == 1)


## Everything wizard `src` multiplies the damage she deals by (docs/stage3_brief.md § 4.5): STRENGTH and WANDS
## (Upgrades.damage_mul), times 1 + her staff and armour's might, the shop's damage and an ORC's fury at
## Races.FURY_HEARTS hearts or fewer (+ 0.0 for everyone else, exact), times an apprentice's share. 1 with no
## wizard (a hazard's, or a seat that left).
static func _dealt_mul(w: World, src: World.Player) -> float:
	if src == null:
		return 1.0
	return Upgrades.damage_mul(src.upgrades) * (1.0 + src.armor[Loot.ST_MIGHT] + w.meta_damage
		+ (src.fury if src.hp <= Races.FURY_HEARTS else 0.0)) * (w.tune.apprentice_damage if src.ai else 1.0)


## Everything foe `e` multiplies the damage it takes by (docs/stage3_brief.md § 4.5): 1 today; a hex and PROVOKE's
## second effect come with their jobs.
static func _taken_mul(w: World, e: World.Enemy) -> float:
	return 1.0


## `sure`: a hit that ignores facing and shields (the nova, hazards); see Brains.filter_damage. The damage is
## multiplied by _dealt_mul and _taken_mul and by nothing else.
static func _damage_enemy(w: World, e: World.Enemy, dmg: float, slot: int, knock: Vector2, sure: bool = false) -> void:
	if w.phase == World.PH_GAMEOVER:
		return # the run is over: no kill may turn it into a victory or add to the score
	if e.dead or _faded(w, e):
		return
	dmg = Brains.filter_damage(w, e, dmg, knock, sure)
	if dmg < 0.0:
		return
	dmg *= _dealt_mul(w, w.players.get(slot)) * _taken_mul(w, e)
	w.record.add(slot, "damage", minf(dmg, maxf(0.0, e.hp)))
	w.record.add_source(w.stat_src, minf(dmg, maxf(0.0, e.hp)))
	w.record.add_slot_source(slot, w.stat_src, minf(dmg, maxf(0.0, e.hp)))
	e.hp -= dmg
	e.flash = 0.07
	var heft := _heft(w, e)
	e.knock = (e.knock + knock * heft).limit_length(Bestiary.KNOCK_MAX * heft) # shoves add up, but only to a cap
	w.emit(World.EV_HIT, e.pos.x, e.pos.y - e.r, e.type, slot)
	if e.hp <= 0.0:
		_kill_enemy(w, e, slot)


## How far knockback and pulls move an enemy (Bestiary.K_HEFT): the Lich barely, orcs and gargoyles less than the rest.
static func _heft(w: World, e: World.Enemy) -> float:
	return Bestiary.KINDS[e.type][Bestiary.K_HEFT]


static func _kill_enemy(w: World, e: World.Enemy, slot: int) -> void:
	e.dead = true
	var p: World.Player = w.players.get(slot)
	var base: int = Bestiary.KINDS[e.type][Bestiary.K_SCORE] * (World.ELITE_REWARD if e.elite else 1) * (World.FINAL_REWARD if e.final else 1)
	if p:
		p.combo += 1
		p.combo_t = 2.5
		p.kills += 1
		var mult := 1 + mini(p.combo / 10, 4)
		p.score += base * mult
		if World.COMBO_CALLS.has(p.combo):
			w.emit(World.EV_COMBO, e.pos.x, e.pos.y, p.combo, slot)
		w.record.best(slot, "best_combo", p.combo)
		if p.combo in Results.COMBO_MOMENTS:
			w.record.note(w.wave_time, Results.M_COMBO, slot, p.combo)
		if e.elite:
			w.record.add(slot, "elites", 1)
		if Upgrades.level_of(p.upgrades, Upgrades.POWER) > 0:
			w.record.use("power", slot) # STRENGTH: credited at her kill, never at a hit
	w.emit(World.EV_DIE, e.pos.x, e.pos.y - e.r, e.type, slot)
	WorldCasting._justice(w, e, slot)
	WorldDrops._drop_xp(w, e.pos, Vector2.from_angle(w.rng.randf() * TAU) * 25.0, Bestiary.KINDS[e.type][Bestiary.K_XP] * (World.ELITE_REWARD if e.elite else 1))
	WorldDrops._roll_card(w, e)
	if e.elite:
		for i in World.ELITE_GEMS:
			WorldDrops._drop(w, World.PK_GEM if i % 2 == 0 else World.PK_COIN, e.pos, Vector2.from_angle(i * TAU / World.ELITE_GEMS) * 70.0)
		WorldDrops._drop(w, World.PK_CHEST, e.pos, Vector2(0, 30), w.tune.chest_life, int(w.tune.elite_chest_luck))
		WorldLevels._drop_party_tome(w, e.pos, w.tune.party_tome_elite)
		Brains.on_death(w, e, slot) # its death still acts (a shard's beam ends); the elite's own drops replace the roll
		return
	if Brains.on_death(w, e, slot):
		return
	WorldDrops._roll_drop(w, e)


static func _update_eshots(w: World, dt: float) -> void:
	var bounds := G.ARENA.grow(6)
	for s in w.eshots:
		s.life -= dt
		s.pos += s.vel * dt
		if s.life <= 0.0 or not bounds.has_point(s.pos):
			s.dead = true
			continue
		for p in w.players.values():
			if p.alive and p.invuln <= 0.0 and s.pos.distance_to(p.pos + Vector2(0, -6)) < s.r + 4.0:
				s.dead = true
				WorldPlayers.hurt_player(w, p, 1)
				break
