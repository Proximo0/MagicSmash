class_name WorldPlayers
extends RefCounted
## Wizards for World: movement, the leash, the nova, taking hits and the fallen. Static helpers; the first argument
## is the World.
##
## The fallen (a party of two or more; a solo wizard dies and respawns as before; the numbers are Tuning's "Fallen"
## rows): at 0 hearts a wizard falls (EV_DOWN) and walks as a spirit, slow, leashed to the standing, unhurt and not
## casting, still gathering XP. A ritual circle sits on her: each standing ally inside it raises her, and the
## progress holds while one stays near. With more than one life she also gets up by herself after tune.down_time
## (for a life); with one life only a ritual, a slain Lich, or nothing raises her.

## How close a spirit must be to an XP mote to take it, px.
const SPIRIT_REACH := 11.0


static func _update_player(w: World, p: World.Player, dt: float, inp: PackedFloat32Array) -> void:
	if not input_finite(inp):
		inp = PackedFloat32Array() # a bad packet (NaN or inf) moves nothing and aims nowhere
	p.flash = maxf(0.0, p.flash - dt)
	p.invuln = maxf(0.0, p.invuln - dt)
	p.haste = maxf(0.0, p.haste - dt)
	p.vigil = maxf(0.0, p.vigil - dt)
	p.orbit = maxf(0.0, p.orbit - dt)
	p.orbit_ang += dt * 5.5
	if p.combo_t > 0.0:
		p.combo_t -= dt
		if p.combo_t <= 0.0:
			p.combo = 0
	if not p.alive:
		# A nova pressed while not standing is spent here (a call for help, or nothing), never at the return.
		var pressed := false
		if inp.size() >= 6:
			var bc := int(inp[5])
			pressed = p.last_bomb >= 0 and bc > p.last_bomb
			if p.last_bomb < 0 or bc > p.last_bomb:
				p.last_bomb = bc
		if p.down:
			_update_spirit(w, p, dt, inp, pressed)
			return
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
			w.record.use("regen", p.slot)
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
		* (w.tune.haste_speed_mul if p.haste > 0.0 else 1.0) * p.walk_mul
	p.vel = move * speed
	p.moving = move.length() > 0.1
	if p.moving and not p.swift_moved and Upgrades.level_of(p.upgrades, Upgrades.SWIFT) > 0: p.swift_moved = true
	if p.swift_moved and floori(w.time) > floori(w.time - dt):
		p.swift_moved = false
		w.record.use("swift", p.slot)
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
			if p.bombs > 0 and w.nova_sealed <= 0.0: # THE HANGED MAN: a press while sealed is spent, not kept
				_skill(w, p)
	if p.orbit > 0.0:
		w.stat_src = Results.SRC_ORBIT
		for i in 3:
			var a := p.orbit_ang + i * TAU / 3.0
			var op := p.pos + Vector2(0, -6) + Vector2(cos(a), sin(a)) * 22.0
			for e in w._query(op, 14.0):
				if e.orbit_cd <= 0.0 and op.distance_to(e.pos) < e.r + 6.0:
					e.orbit_cd = 0.3
					WorldEnemies._damage_enemy(w, e, 1.5, p.slot, (e.pos - p.pos).normalized() * 80.0)


## True when every number of an input packet is finite.
static func input_finite(inp: PackedFloat32Array) -> bool:
	for v: float in inp:
		if not is_finite(v):
			return false
	return true


## Wizards share one screen: none may get further than tune.leash_x / leash_y from any other living wizard.
static func _leash(w: World, p: World.Player) -> void:
	for q: World.Player in w.players.values():
		if q == p or not q.alive:
			continue
		p.pos.x = clampf(p.pos.x, q.pos.x - w.tune.leash_x, q.pos.x + w.tune.leash_x)
		p.pos.y = clampf(p.pos.y, q.pos.y - w.tune.leash_y, q.pos.y + w.tune.leash_y)


## The nova button: the wizard's class skill (Classes.SKILLS), each for one nova charge. A wizard with no hero,
## and every MAGE, novas as ever.
static func _skill(w: World, p: World.Player) -> void:
	if p.skill == Classes.SK_NOVA:
		_nova(w, p)
		return
	p.bombs -= 1
	w.emit(World.EV_SKILL, p.pos.x, p.pos.y - 6, p.slot, p.skill)
	match p.skill:
		Classes.SK_PROVOKE:
			_provoke(w, p)
		Classes.SK_VOLLEY:
			_volley(w, p)
		Classes.SK_SANCTUARY:
			_sanctuary(w, p)
		Classes.SK_AEGIS:
			_aegis(w, p)


## PROVOKE (the knight): every enemy (not a boss) within its radius wants her for its taunt seconds, whoever is
## nearer, and she takes no damage for its safe seconds.
static func _provoke(w: World, p: World.Player) -> void:
	var sk := Classes.SK_PROVOKE
	var r := Classes.skill_value(sk, "radius")
	var secs := Classes.skill_value(sk, "taunt")
	for e: World.Enemy in w.enemies:
		if e.dead or e.flags & Bestiary.F_BOSS or e.pos.distance_to(p.pos) > r:
			continue
		e.taunt = p
		e.taunt_t = secs
	p.invuln = maxf(p.invuln, Classes.skill_value(sk, "safe"))


## VOLLEY (the archer): she rolls its roll px along her movement (along her aim when standing still), unhurt for
## its safe seconds, then looses its arrows in a fan behind her: her weapon's shots at its level (a weapon that
## flies no bolts looses ARCANE BOLTs).
static func _volley(w: World, p: World.Player) -> void:
	var sk := Classes.SK_VOLLEY
	var dir := p.vel.normalized() if p.moving and p.vel.length() > 0.01 else p.aim.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	p.pos += dir * Classes.skill_value(sk, "roll")
	p.pos = p.pos.clamp(G.ARENA.position + Vector2(5, 6), G.ARENA.end - Vector2(5, 2))
	_leash(w, p)
	p.invuln = maxf(p.invuln, Classes.skill_value(sk, "safe"))
	var sp := Classes.weapon(p.cls)
	if Spells.cast_kind(sp) != "bolt":
		sp = World.SP_ARCANE
	var lv := maxi(1, Upgrades.weapon_level(p.upgrades, sp))
	var dmg := Spells.damage(sp, lv, 0)
	var speed := Spells.stat(sp, "speed") * Classes.skill_value(sk, "speed_mul", 1.0)
	var n := int(Classes.skill_value(sk, "arrows"))
	var fan := Classes.skill_value(sk, "fan")
	var back := -dir
	var tip := p.pos + Vector2(0, -7)
	# Her arrows fly the LONGBOW's range, as her own shots do (WorldCastBolts._cast_bolts).
	var reach := Classes.skin_value(p.skin, "range") if sp == p.class_weapon else 0.0
	w.stat_src = sp
	for i: int in range(n):
		var a := (i / maxf(1.0, n - 1.0) - 0.5) * fan
		var s := WorldCastBolts._shot(w, p.slot, sp, false, tip, back.rotated(a) * speed, dmg, 0)
		if reach > 0.0:
			s.life = reach / speed


## SANCTUARY (the priest): every standing hero heals its hearts (EV_HEAL), then the fallen within its radius rise.
static func _sanctuary(w: World, p: World.Player) -> void:
	var sk := Classes.SK_SANCTUARY
	var heal := int(Classes.skill_value(sk, "heal"))
	var r := Classes.skill_value(sk, "radius")
	for q: World.Player in w.players.values():
		if q.alive and q.hp < q.max_hp:
			var got := mini(heal, q.max_hp - q.hp)
			q.hp += got
			w.emit(World.EV_HEAL, q.pos.x, q.pos.y - 6, q.slot, got)
	for q: World.Player in w.players.values():
		if q.down and q.pos.distance_to(p.pos) <= r:
			q.rituals += 1 # it counts as a ritual: the next one on this hero takes longer
			w.record.add(p.slot, "revives", 1)
			_rise(w, q, p.slot)


## AEGIS (the paladin): heroes within its radius (her too) take no damage for its safe seconds.
static func _aegis(w: World, p: World.Player) -> void:
	var sk := Classes.SK_AEGIS
	var r := Classes.skill_value(sk, "radius")
	for q: World.Player in w.players.values():
		if q.alive and q.pos.distance_to(p.pos) <= r:
			q.invuln = maxf(q.invuln, Classes.skill_value(sk, "safe"))


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
			var dmg := 40.0 if e.flags & Bestiary.F_BOSS else 14.0
			WorldEnemies._damage_enemy(w, e, dmg, p.slot, (e.pos - p.pos).normalized() * 260.0, true)
	for s in w.eshots:
		if s.pos.distance_to(p.pos) < radius + 30:
			s.dead = true
	WorldHazards.nova_clear(w, p.pos)


static func hurt_player(w: World, p: World.Player, dmg: int) -> void:
	if not p.alive or p.invuln > 0.0 or w.phase == World.PH_GAMEOVER:
		return
	var ward: float = p.armor[Loot.ST_WARD]
	for q: World.Player in w._plist: # a PALADIN's aura: one aura counts, within the cap
		if q.aura_r > 0.0 and q.alive and q.pos.distance_to(p.pos) <= q.aura_r:
			ward = minf(ward + q.aura_ward, float(Loot.STAT_CAPS[Loot.ST_WARD]))
			break
	if ward > 0.0 and w.rng.randf() < ward:
		p.invuln = 0.5
		w.emit(World.EV_WARD, p.pos.x, p.pos.y - 6, p.slot, 0)
		return
	p.hp -= dmg
	p.flash = 0.15
	p.invuln = Classes.hurt_safe(p.cls) * p.safe_mul # STURDY: a dwarf's lasts longer
	w.emit(World.EV_HURT, p.pos.x, p.pos.y - 6, p.slot, 0)
	if p.hp <= 0:
		if w.players.size() >= 2:
			_fall(w, p)
			return
		p.alive = false
		p.lives -= 1
		p.respawn = 2.5
		p.haste = 0.0
		p.orbit = 0.0
		p.combo = 0
		w.record.add(p.slot, "deaths", 1)
		w.emit(World.EV_PDIE, p.pos.x, p.pos.y - 6, p.slot, p.lives)


# ========================================================== THE FALLEN ===

## A wizard of a party falls: she becomes a spirit with her lives untouched.
static func _fall(w: World, p: World.Player) -> void:
	p.hp = 0
	p.alive = false
	p.down = true
	p.down_t = 0.0
	p.revive = 0.0
	p.down_left = w.tune.down_time if p.lives > 1 else -1.0
	p.haste = 0.0
	p.orbit = 0.0
	p.combo = 0
	w.record.add(p.slot, "downs", 1)
	w.emit(World.EV_DOWN, p.pos.x, p.pos.y, p.slot, 0)
	# The old death event still carries the fall's burst, sound and "DOWN!" text (and the playtest's counts).
	w.emit(World.EV_PDIE, p.pos.x, p.pos.y - 6, p.slot, p.lives)


## One tick of a spirit: the call, the slow walk, the XP she touches, the ritual on her and her own clock.
static func _update_spirit(w: World, p: World.Player, dt: float, inp: PackedFloat32Array, pressed: bool) -> void:
	p.down_t += dt
	p.call_t = maxf(0.0, p.call_t - dt)
	if pressed and p.call_t <= 0.0 and w.phase != World.PH_GAMEOVER:
		p.call_t = w.tune.call_gap
		w.emit(World.EV_CALL, p.pos.x, p.pos.y, p.slot, 0)
	var move := Vector2(inp[0], inp[1]).limit_length(1.0) if inp.size() >= 2 else Vector2.ZERO
	p.vel = move * w.tune.spirit_speed
	p.moving = move.length() > 0.1
	if p.moving:
		p.aim = move.normalized()
	p.pos += p.vel * dt
	p.pos = p.pos.clamp(G.ARENA.position + Vector2(5, 6), G.ARENA.end - Vector2(5, 2))
	_leash(w, p)
	if w.phase == World.PH_GAMEOVER:
		return
	_spirit_xp(w, p)
	if WorldApprentices.gets_up(w, p):
		_rise(w, p, -1) # an apprentice gets up by itself, free
		return
	var inside: Array[World.Player] = []
	var near := false
	for q: World.Player in w.players.values():
		if q == p or not q.alive:
			continue
		var d := q.pos.distance_to(p.pos)
		if d <= w.tune.ritual_radius:
			inside.append(q)
		if d <= w.tune.ritual_hold_radius:
			near = true
	if not inside.is_empty():
		if p.revive <= 0.0:
			_ritual_push(w, p.pos)
		var raise := 0.0 # each raiser counts her ritual_mul (a PRIEST twice): the count of them, exactly, otherwise
		for q: World.Player in inside:
			raise += q.ritual_mul
		p.revive += dt * raise / ((w.tune.ritual_time + w.tune.ritual_step * p.rituals) * w.seal_ritual) # DARKNESS
		if p.revive >= 1.0:
			p.rituals += 1
			for q: World.Player in inside:
				q.invuln = maxf(q.invuln, w.tune.ritual_safe)
				w.record.add(q.slot, "revives", 1)
			_ritual_push(w, p.pos)
			_rise(w, p, inside[0].slot)
			return
	elif not near:
		p.revive = maxf(0.0, p.revive - dt / w.tune.ritual_drain)
	if p.lives <= 1:
		p.down_left = -1.0
		return
	if p.down_left < 0.0:
		p.down_left = w.tune.down_time # a life gained while down starts her clock
	if inside.is_empty():
		p.down_left -= dt
	if p.down_left <= 0.0:
		_get_up(w, p)


## A spirit takes the XP motes she touches and draws in the ones in her magnet's reach (a standing wizard's
## magnet, run after this, wins a mote both reach).
static func _spirit_xp(w: World, p: World.Player) -> void:
	var reach := w.tune.xp_magnet_radius * Upgrades.magnet_mul(p.upgrades) * p.reach_mul
	var took := false
	for k: World.Pickup in w.pickups:
		if k.kind != World.PK_XP or k.life <= 0.0:
			continue
		var d := k.pos.distance_to(p.pos)
		if d < SPIRIT_REACH:
			WorldDrops._collect(w, p, k)
			k.life = -1.0
			took = true
		elif d < reach:
			k.vel = (p.pos - k.pos).normalized() * w.tune.xp_magnet_speed
	if took:
		w.pickups = w.pickups.filter(func(k: World.Pickup) -> bool: return k.life > 0.0)


## Every enemy (not a boss) within tune.ritual_push of `at` is set down that far away from it.
static func _ritual_push(w: World, at: Vector2) -> void:
	for e: World.Enemy in w._query(at, w.tune.ritual_push):
		if e.flags & Bestiary.F_BOSS or e.entering:
			continue
		var d := e.pos - at
		var l := d.length()
		if l >= w.tune.ritual_push:
			continue
		var dir := d / l if l > 0.01 else Vector2.RIGHT
		e.pos = (at + dir * w.tune.ritual_push).clamp(G.ARENA.position + Vector2(e.r, e.r), G.ARENA.end - Vector2(e.r, e.r))


## The fallen wizard stands again where her spirit is, with half her hearts (rounded up) and her novas, safe for
## tune.ritual_safe. `by` is the slot that raised her (-1: none).
static func _rise(w: World, p: World.Player, by: int) -> void:
	_stand(w, p)
	p.hp = ceili(p.max_hp / 2.0)
	p.invuln = maxf(p.invuln, w.tune.ritual_safe)
	w.emit(World.EV_REVIVE, p.pos.x, p.pos.y, p.slot, by)
	w.emit(World.EV_SPAWN, p.pos.x, p.pos.y, p.slot, 0)


## The fallen wizard gets up by herself for a life: full hearts, beside the party (where she is, if nobody stands).
static func _get_up(w: World, p: World.Player) -> void:
	p.lives -= 1
	w.record.add(p.slot, "deaths", 1)
	var anyone := false
	for q: World.Player in w.players.values():
		if q.alive:
			anyone = true
	if anyone:
		p.pos = w.party_center() + Vector2(w.rng.randf_range(-20, 20), w.rng.randf_range(-10, 10))
		p.pos = p.pos.clamp(G.ARENA.position + Vector2(5, 6), G.ARENA.end - Vector2(5, 2))
	_stand(w, p)
	p.hp = p.max_hp
	p.invuln = w.tune.return_safe
	p.bombs = maxi(p.bombs, 2)
	w.emit(World.EV_REVIVE, p.pos.x, p.pos.y, p.slot, -1)
	w.emit(World.EV_SPAWN, p.pos.x, p.pos.y, p.slot, 0)


static func _stand(_w: World, p: World.Player) -> void:
	p.alive = true
	p.down = false
	p.down_t = 0.0
	p.down_left = 0.0
	p.revive = 0.0


## A slain Lich raises every fallen wizard (`slot` slew it).
static func raise_fallen(w: World, slot: int) -> void:
	for p: World.Player in w.players.values():
		if p.down:
			_rise(w, p, slot)


## With nobody standing, the longest-down wizard with a life to spare gets up within tune.last_stand. Called each step
## before the wipe test.
static func _last_stand(w: World) -> void:
	var best: World.Player = null
	for p: World.Player in w.players.values():
		if p.alive:
			return
		if p.down and p.lives > 1 and (best == null or p.down_t > best.down_t):
			best = p
	if best != null:
		best.down_left = minf(best.down_left, w.tune.last_stand)
