class_name ArenaDrawEnemies
extends RefCounted
## Arena: enemy glows, the enemies and their bars.
## Static helpers: `a` is the Arena that owns the state.

## Under the sprites, in one pass, so the sprites batch together: the shadows of the kinds that fly (set down the
## floor from the sprite, which stays on the body that spells hit), then the halo of each elite and of the Lich.
static func _draw_enemy_glows(a: Arena, ci: CanvasItem) -> void:
	var halos: Array = []
	for e: Dictionary in a.ve.values():
		match int(e.type):
			World.BAT:
				ArenaDrawWorld._shadow(a, ci, e.pos + Vector2(0, 6), 8)
			World.TOME:
				ArenaDrawWorld._shadow(a, ci, e.pos + Vector2(0, 5), 10)
			World.GARGOYLE:
				if e.state == 1:
					ArenaDrawWorld._shadow(a, ci, e.pos + Vector2(0, 6), 14)
			World.LICH:
				halos.append(e)
			Bestiary.CHANDELIER, Bestiary.GHOSTWRITER:
				ArenaDrawBoss.shadow(a, ci, e)
		if e.elite:
			halos.append(e)
	for e: Dictionary in halos:
		if e.type == World.LICH:
			var glow := Color(1, 1, 1, 0.75 + 0.25 * sin(a.time * 4.0))
			Sprites.draw_at(ci, "archlich_halo" if e.final else "lich_halo", e.pos + Vector2(0, 9), false, false, glow)
		else:
			Sprites.draw_at(ci, "elite_halo", e.pos + Vector2(0, 6), false, false, Color(1, 1, 1, 0.7 + 0.3 * sin(a.time * 6.0 + e.t)))


## One enemy: the frame its type and state call for (see `SpritesEnemies`), anchored bottom centre on its feet.
static func _draw_enemy(a: Arena, ci: CanvasItem, e: Dictionary) -> void:
	var t: int = e.type
	var st: int = e.state
	# A snapshot carries the state but not its age, so the view times each state: hops, wind-ups and wakes read it.
	if e.get("st", -1) != st:
		e.st = st
		e.st_t = a.time
	var since: float = a.time - float(e.st_t)
	var cyc: Array = a.ENEMY_KEYS[t]
	var fi := int(e.t * a.ENEMY_ANIM[t]) % cyc.size()
	var key: String = cyc[fi]
	# Face the nearest wizard; hold the facing while that wizard is almost straight above or below.
	var near_dx := 0.0
	var nd := INF
	for p in a.vp.values():
		if p.alive:
			var d: float = p.pos.distance_squared_to(e.pos)
			if d < nd:
				nd = d
				near_dx = p.pos.x - e.pos.x
	var turn := absf(near_dx) > 3.0
	var feet: Vector2 = e.pos + Vector2(0, 1)
	var mod := Color.WHITE
	if e.slow > 0.0:
		mod = Color(0.6, 0.9, 1.4)
	match t:
		World.SLIME:
			# The hop: it stretches off the floor, hangs in the air and squashes where it lands.
			if st == 1:
				var u := clampf(since / 0.5, 0.0, 1.0)
				key = "slime_c" if u < 0.2 else ("slime_d" if u < 0.85 else "slime_b")
				feet.y -= roundf(sin(u * PI) * 5.0)
			elif since < 0.12:
				key = "slime_b"
		World.MSLIME:
			if fi == 1:
				feet.y -= 2.0
		World.BAT:
			turn = false
			feet.y -= 1.0 + roundf(sin(e.t * 8.0))
		World.ORC:
			if st == 1:
				# The wind-up: the club goes up and the brute shakes with it.
				key = "orc_wind"
				feet.x += float(int(a.time * 30.0) % 2)
			elif st == 2:
				key = "orc_charge" if int(a.time * 12.0) % 2 == 0 else "orc_charge2"
		World.MAGE:
			if st == 1:
				key = "mage_cast"
		World.LICH:
			turn = false
			feet.y -= 3.0 + roundf(sin(e.t * 2.0) * 1.5)
			if st == 5:
				# About to step through the dark: its fire flares and it flickers.
				key = "lich_cast"
				mod.a = 0.6 + 0.3 * sin(a.time * 30.0)
			elif st >= 1 and st <= 3 and int(a.time * 8.0) % 3 != 0:
				key = "lich_cast"
			if e.final:
				key = "arch" + key
		World.WRAITH:
			feet.y -= 1.0 + roundf(sin(e.t * 3.0))
			if st == 1:
				# Faded: only its rim is left, and spells pass through.
				key = "wraith_fade_a" if fi == 0 else "wraith_fade_b"
				mod.a = 0.55 + 0.15 * sin(a.time * 20.0)
		World.TOME:
			feet.y -= 1.0 + roundf(sin(e.t * 6.0))
			if st == 1:
				key = "tome_rear"
				feet.x += float(int(a.time * 30.0) % 2)
			elif st == 2:
				key = "tome_dash" if int(a.time * 14.0) % 2 == 0 else "tome_rear"
		World.GARGOYLE:
			# It flies in from the door with its wings out and lands where it first stops. From then on it is
			# stone whenever it perches: it does not turn, and its eyes light shortly before it wakes.
			if st == 1:
				e.down = true
			elif not e.get("down", false):
				var moved: bool = e.pos.distance_squared_to(e.get("at", Vector2.INF)) > 0.04
				e.at = e.pos
				e.still = 0 if moved else int(e.get("still", 0)) + 1
				e.down = e.still >= 6
			if st == 1 or not e.down:
				feet.y -= 2.0 + float(fi)
			else:
				turn = false
				key = "gargoyle_wake" if since > World.GARGOYLE_PERCH - 0.5 else "gargoyle_a"
				mod = mod * Color(0.86, 0.86, 0.94)
		World.PRIEST:
			if st == 1:
				key = "priest_raise"
		Bestiary.CHANDELIER, Bestiary.GHOSTWRITER:
			var pose := ArenaDrawBoss.pose(a, e)
			turn = false
			feet += pose[0]
			mod = mod * (pose[1] as Color)
		_:
			if Bestiary.is_new_kind(t):
				var look: Array = EnemyView.state_look(a, e, feet, mod)
				feet = look[0]
				mod = look[1]
	if turn:
		e.flip = near_dx < 0.0
	var elite: bool = e.elite
	if elite:
		key = "elite_" + key
	var flash: bool = e.flash > 0.0 and (t != World.LICH or not Save.settings.strobes() or int(a.time * 40.0) % 3 == 0)
	if not EnemyView.draw_still(ci, e, feet, flash, mod, a.time):
		Sprites.draw_at(ci, key, feet, e.flip, flash, mod)
	if Bestiary.is_new_kind(t):
		EnemyView.draw_state(a, ci, e, feet)
	if elite:
		# The mark of an elite: a small crown that bobs over its head, above the health bar.
		Sprites.draw_at(ci, "elite_mark", e.pos + Vector2(0, -5.0 - SpritesEnemies.TOP[t] + roundf(sin(a.time * 4.0 + e.t))))


## Health bars over the big enemies and the elites, once they are hurt. Drawn after every sprite, so they do not
## split the sprite batch.
static func _draw_enemy_bars(a: Arena, ci: CanvasItem) -> void:
	for e: Dictionary in a.ve.values():
		var t: int = e.type
		var elite: bool = e.elite
		if e.hpf < 1.0 and (elite or t == World.ORC or t == World.GARGOYLE):
			var w := 16.0 if elite else 12.0
			var bp: Vector2 = (e.pos + Vector2(-w / 2.0, -3.0 - SpritesEnemies.TOP[t])).floor()
			ci.draw_rect(Rect2(bp - Vector2(1, 1), Vector2(w + 2, 4)), Color("c48a10") if elite else Color("0b0716"))
			ci.draw_rect(Rect2(bp, Vector2(w, 2)), Color("2a1f45"))
			ci.draw_rect(Rect2(bp, Vector2(ceilf(w * e.hpf), 2)), Color("ff3b5c"))
