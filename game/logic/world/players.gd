class_name WorldPlayers
extends RefCounted
## Wizards for World: movement, the leash, the nova and taking hits. Static helpers; the first argument is the World.


static func _update_player(w: World, p: World.Player, dt: float, inp: PackedFloat32Array) -> void:
	p.flash = maxf(0.0, p.flash - dt)
	p.invuln = maxf(0.0, p.invuln - dt)
	p.haste = maxf(0.0, p.haste - dt)
	p.orbit = maxf(0.0, p.orbit - dt)
	p.orbit_ang += dt * 5.5
	if p.combo_t > 0.0:
		p.combo_t -= dt
		if p.combo_t <= 0.0:
			p.combo = 0
	if not p.alive:
		if p.lives > 0 and w.phase != World.PH_GAMEOVER:
			p.respawn -= dt
			if p.respawn <= 0.0:
				p.alive = true
				p.hp = p.max_hp
				p.invuln = 2.5
				p.bombs = maxi(p.bombs, 2)
				# Back beside the party (the arena is bigger than the screen), or mid-arena when nobody is up.
				p.pos = w.party_center() + Vector2(w.rng.randf_range(-20, 20), w.rng.randf_range(-10, 10))
				p.pos = p.pos.clamp(G.ARENA.position + Vector2(5, 6), G.ARENA.end - Vector2(5, 2))
				w.emit(World.EV_SPAWN, p.pos.x, p.pos.y, p.slot, 0)
		return
	var regen := Upgrades.regen_interval(p.upgrades)
	if regen > 0.0 and p.hp < p.max_hp:
		p.regen_t += dt
		if p.regen_t >= regen:
			p.regen_t = 0.0
			p.hp += 1
	else:
		p.regen_t = 0.0
	var move := Vector2.ZERO
	var aim := Vector2.ZERO
	var bomb_count := -1
	if inp.size() >= 6:
		move = Vector2(inp[0], inp[1]).limit_length(1.0)
		aim = Vector2(inp[2], inp[3])
		bomb_count = int(inp[5])
	var speed: float = w.tune.player_speed * Upgrades.move_mul(p.upgrades) * (1.0 + p.armor[Loot.ST_SWIFT]) \
		* (w.tune.haste_speed_mul if p.haste > 0.0 else 1.0)
	p.vel = move * speed
	p.moving = move.length() > 0.1
	p.pos += p.vel * dt
	p.pos.x = clampf(p.pos.x, G.ARENA.position.x + 5, G.ARENA.end.x - 5)
	p.pos.y = clampf(p.pos.y, G.ARENA.position.y + 6, G.ARENA.end.y - 2)
	_leash(w, p)
	if aim.length() > 0.1:
		p.aim = aim.normalized()
	elif p.moving:
		p.aim = move.normalized()
	if w.phase != World.PH_GAMEOVER:
		WorldCasting._auto_cast(w, p, dt, aim)
	if bomb_count >= 0:
		if p.last_bomb < 0:
			p.last_bomb = bomb_count
		elif bomb_count > p.last_bomb:
			p.last_bomb = bomb_count
			if p.bombs > 0:
				_nova(w, p)
	if p.orbit > 0.0:
		w.stat_src = Results.SRC_ORBIT
		for i in 3:
			var a := p.orbit_ang + i * TAU / 3.0
			var op := p.pos + Vector2(0, -6) + Vector2(cos(a), sin(a)) * 22.0
			for e in w._query(op, 14.0):
				if e.orbit_cd <= 0.0 and op.distance_to(e.pos) < e.r + 6.0:
					e.orbit_cd = 0.3
					WorldEnemies._damage_enemy(w, e, 1.5, p.slot, (e.pos - p.pos).normalized() * 80.0)


## Wizards share one screen: none may get further than tune.leash_x / leash_y from any other living wizard.
static func _leash(w: World, p: World.Player) -> void:
	for q: World.Player in w.players.values():
		if q == p or not q.alive:
			continue
		p.pos.x = clampf(p.pos.x, q.pos.x - w.tune.leash_x, q.pos.x + w.tune.leash_x)
		p.pos.y = clampf(p.pos.y, q.pos.y - w.tune.leash_y, q.pos.y + w.tune.leash_y)


static func _nova(w: World, p: World.Player) -> void:
	w.stat_src = Results.SRC_NOVA
	p.bombs -= 1
	p.invuln = maxf(p.invuln, 0.8)
	w.emit(World.EV_NOVA, p.pos.x, p.pos.y - 6, p.slot, 0)
	var radius := 150.0
	for e in w.enemies:
		if e.dead:
			continue
		var d := e.pos.distance_to(p.pos)
		if d < radius:
			var dmg := 40.0 if e.type == World.LICH else 14.0
			WorldEnemies._damage_enemy(w, e, dmg, p.slot, (e.pos - p.pos).normalized() * 260.0)
	for s in w.eshots:
		if s.pos.distance_to(p.pos) < radius + 30:
			s.dead = true


static func hurt_player(w: World, p: World.Player, dmg: int) -> void:
	if not p.alive or p.invuln > 0.0 or w.phase == World.PH_GAMEOVER:
		return
	if p.armor[Loot.ST_WARD] > 0.0 and w.rng.randf() < p.armor[Loot.ST_WARD]:
		p.invuln = 0.5
		w.emit(World.EV_WARD, p.pos.x, p.pos.y - 6, p.slot, 0)
		return
	p.hp -= dmg
	p.flash = 0.15
	p.invuln = 1.1
	w.emit(World.EV_HURT, p.pos.x, p.pos.y - 6, p.slot, 0)
	if p.hp <= 0:
		p.alive = false
		p.lives -= 1
		p.respawn = 2.5
		p.haste = 0.0
		p.orbit = 0.0
		p.combo = 0
		w.record.add(p.slot, "deaths", 1)
		w.emit(World.EV_PDIE, p.pos.x, p.pos.y - 6, p.slot, p.lives)
