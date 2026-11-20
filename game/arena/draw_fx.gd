class_name ArenaDrawFx
extends RefCounted
## Arena: ambient trails and torches, spell and pickup colours, spell shots and enemy shots.
## Static helpers: `a` is the Arena that owns the state.

static func _spell_color(a: Arena, sp: int, slot: int) -> Color:
	if sp == World.SP_ARCANE:
		return G.player_fx(slot)
	return a.SPELL_COLORS[sp]


static func _pickup_color(a: Arena, k: int) -> Color:
	match k:
		World.PK_COIN: return Color("ffd94d")
		World.PK_GEM: return Color("4dfff0")
		World.PK_POTION: return Color("ff3b5c")
		World.PK_TOME_FIRE: return a.SPELL_COLORS[1]
		World.PK_TOME_FROST: return a.SPELL_COLORS[2]
		World.PK_TOME_STORM: return a.SPELL_COLORS[3]
		World.PK_TOME_STAR: return a.SPELL_COLORS[4]
		World.PK_TOME_RUNE: return a.SPELL_COLORS[5]
		World.PK_BOOTS: return Color("8fe3ff")
		World.PK_ORBIT: return Sprites.ORBIT_COLOR
		World.PK_XP: return Sprites.XP_COLOR
		World.PK_CHEST: return Color("ffd94d")
		World.PK_CARD: return Color("ff4df2")
		World.PK_CHEST_RARE: return Color("8fe3ff")
		World.PK_CHEST_ULTRA: return Color("c9a6ff")
	return Color.WHITE


## Once a frame: what the shots, the rune circles, the enemies and the wizards shed, and the view state that
## follows from the snapshot rather than from an event (who is casting, who took a level-up card, which star landed).
static func _emit_trails(a: Arena, dt: float) -> void:
	var stars: Array = []
	for s in a.vs:
		var p: Vector2 = s[1]
		match s[0]:
			World.SP_ARCANE:
				# The comet is a sprite with its own tail; only the Astral Lance sheds motes.
				if s[4] and a._fx_rng.randf() < 0.3:
					var col := G.player_fx(s[3])
					a.fx.spawn(p, Vector2(a._fx_rng.randf_range(-12, 12), a._fx_rng.randf_range(-12, 12)), 0.22, 1.0, Color.WHITE, col, true, 3.0)
			World.SP_FIRE:
				# A lick of flame left behind every frame; now and then an ember that falls, or smoke.
				a.fx.spawn(p + Vector2(a._fx_rng.randf_range(-1.5, 1.5), a._fx_rng.randf_range(-1.5, 1.5)), -s[2] * 0.12 + Vector2(0, -14),
					0.26, 3.0 if s[4] else 2.0, Color("ffcf5a"), Color("c85a1e"), true, 3.0, -20.0, 0.0, true)
				if a._fx_rng.randf() < 0.25:
					a.fx.spawn(p, Vector2(a._fx_rng.randf_range(-25, 25), a._fx_rng.randf_range(-30, 0)), 0.5, 1.0, Color("fff6c0"),
						Color("c0263a"), true, 1.0, 160.0)
				if a._fx_rng.randf() < 0.12:
					a.fx.spawn(p, Vector2(a._fx_rng.randf_range(-8, 8), -12), 0.6, 2.0, Color(0.23, 0.19, 0.31, 0.6), Color(0.1, 0.06, 0.14, 0.0),
						false, 1.0, -10.0, 4.0)
			World.SP_FROST:
				if a._fx_rng.randf() < 0.2:
					a.fx.spawn(p, Vector2(a._fx_rng.randf_range(-10, 10), a._fx_rng.randf_range(-10, 10)), 0.25, 1.0, Color.WHITE,
						a.SPELL_COLORS[World.SP_FROST], true, 2.0)
			World.SP_STAR:
				stars.append(s)
				if a._fx_rng.randf() < 0.5:
					a.fx.spawn(p + Vector2(a._fx_rng.randf_range(-2, 2), a._fx_rng.randf_range(-2, 2)), Vector2(a._fx_rng.randf_range(-8, 8), 10),
						0.45, 1.0, Color.WHITE, a.SPELL_COLORS[World.SP_STAR], true, 2.0, 30.0)
	# A star that was here a frame ago and is nowhere near now has landed: a burst, and a mark on the floor.
	var reach := maxf(24.0, 420.0 * dt)
	for old: Array in a._stars_seen:
		var alive := false
		for s: Array in stars:
			if (s[1] as Vector2).distance_squared_to(old[0]) < reach * reach:
				alive = true
				break
		if not alive:
			a.fx.star_land((old[0] as Vector2) + (old[1] as Vector2) * dt, a.SPELL_COLORS[World.SP_STAR], old[2])
	a._stars_seen.clear()
	for s: Array in stars:
		a._stars_seen.append([s[1], s[2], s[4]])
	for c: Array in a.vr:
		if a._fx_rng.randf() < (0.3 if c[5] else 0.18):
			var at: Vector2 = c[0] + Vector2.from_angle(a._fx_rng.randf() * TAU) * float(c[1])
			a.fx.spawn(at, Vector2(0, a._fx_rng.randf_range(-22, -8)), 0.5, 1.0, a.RUNE_GOLD, a.SPELL_COLORS[World.SP_RUNE], true, 1.0)
	for e in a.ve.values():
		if e.type == World.LICH and a._fx_rng.randf() < 0.4:
			a.fx.spawn(e.pos + Vector2(a._fx_rng.randf_range(-14, 14), a._fx_rng.randf_range(-24, 0)), Vector2(0, a._fx_rng.randf_range(-30, -10)),
				0.7, 1.0, Color("d8fff6"), Color("158f86"), true, 1.0)
		elif e.slow > 0.0 and a._fx_rng.randf() < 0.1:
			a.fx.spawn(e.pos + Vector2(a._fx_rng.randf_range(-5, 5), -a._fx_rng.randf_range(0, 10)), Vector2(0, -8), 0.4, 1.0, Color.WHITE,
				a.SPELL_COLORS[World.SP_FROST], true)
		elif e.type == World.MAGE and e.state == 1:
			# A mage gathering its shot burns red: the colour of everything an enemy throws.
			a.fx.spawn(e.pos + Vector2(a._fx_rng.randf_range(-6, 6), -8 + a._fx_rng.randf_range(-4, 4)), Vector2(0, -20), 0.3, 1.0,
				Color("ffcf5a"), Color("c0263a"), true)
	a.fx.keep_clear.clear()
	var tagged := a.vp.size() > 1 or Net.is_online()
	for p: Dictionary in a.vp.values():
		if not p.alive:
			continue
		# Floating words start above the wizard (and the P-tag), never across them.
		var head := 24.0
		if tagged:
			head = (a.TAG_UP_ORBS if p.orbit > 0.0 else a.TAG_UP) + 2.0
		a.fx.keep_clear.append(Rect2(p.pos.x - 9.0, p.pos.y - head, 18.0, head + 2.0))
		var tip: Vector2 = (p.target as Vector2) + Vector2(0, -7) + (p.aim as Vector2) * 9.0
		for c: Array in a.fx.casts:
			# Matched by the caster's slot; by staff distance only when the cast did not say who cast it.
			var mine: bool = int(c[1]) == int(p.slot) if int(c[1]) >= 0 \
					else (c[0] as Vector2).distance_squared_to(tip) < a.CAST_NEAR * a.CAST_NEAR
			if mine:
				p["flare_at"] = a.time
				if a.time - float(p.get("cast_at", -9.0)) > a.CAST_EVERY:
					p["cast_at"] = a.time
				break
		# The column of light walks with its wizard.
		var pillar: Array = p.get("pillar", [])
		if not pillar.is_empty():
			if float(pillar[1]) > 0.0:
				pillar[0] = p.pos
			else:
				p.erase("pillar")
		if p.haste > 0.0 and p.moving and a._fx_rng.randf() < 0.4:
			a.fx.spawn(p.pos + Vector2(a._fx_rng.randf_range(-3, 3), 0), Vector2(0, -10), 0.35, 1.0, Color.WHITE, Color("8fe3ff"), true)
	a.fx.casts.clear()


static func _torch_fx(a: Arena, dt: float) -> void:
	# Sparks rise from the fires of the backdrop that shows most: the old act's for the first half of a fade.
	var from := a._prev_act if a._act_fade >= 0.0 and a._act_fade < 1.0 else a.act
	ArenaArtLive.sparks(a.fx, ArenaBg.scene(from), a._fx_rng, dt, a.door_anim)


## The wizards' magic, on the additive layer over the actors: every shot is a glow and one or two sprites from
## the atlas, plotted for its direction, so hundreds of them are one batch. An evolved spell is the grown form of
## the same shape. Also here: the glow of each staff head (it flares on a cast), the rune shield's orbs, a red
## halo under every enemy shot, and the auras of the Lich and of a mage gathering its shot.
static func _draw_shots(a: Arena) -> void:
	var ci := a.shot_layer
	var bolts: Array = Sprites.strip("fx_bolt", Sprites.DIRS)
	var lances: Array = Sprites.strip("fx_lance", Sprites.DIRS)
	var shards: Array = Sprites.strip("fx_shard", Sprites.DIRS)
	var big_shards: Array = Sprites.strip("fx_shardx", Sprites.DIRS)
	var fires: Array = Sprites.strip("fx_fire", 4)
	var big_fires: Array = Sprites.strip("fx_firex", 4)
	var stars: Array = Sprites.strip("fx_star", 4)
	var big_stars: Array = Sprites.strip("fx_starx", 4)
	var core := Sprites.region("fx_core_0")
	var big_core := Sprites.region("fx_core_1")
	var tick := int(a.time * 12.0)
	var fire_glow := Color(a.SPELL_COLORS[World.SP_FIRE], 0.4)
	var frost_glow := Color(a.SPELL_COLORS[World.SP_FROST], 0.3)
	var star_col: Color = a.SPELL_COLORS[World.SP_STAR]
	for s in a.vs:
		var p: Vector2 = s[1]
		var v: Vector2 = s[2]
		var evo: bool = s[4]
		match s[0]:
			World.SP_ARCANE:
				# A small comet in its caster's colour with a white head; the Astral Lance is a long pointed one
				# with a white comet inside it.
				var col := G.player_fx(s[3])
				var d := Sprites.dir16(v)
				Sprites.glow(ci, p, 5.0 if evo else 3.5, Color(col, 0.4))
				Sprites.draw_mid_r(ci, lances[d] if evo else bolts[d], p, col)
				Sprites.draw_mid_r(ci, bolts[d] if evo else core, p)
			World.SP_FIRE:
				# A tumbling flame: four frames a quarter turn apart, each ball out of step with the next.
				var f := (tick + int(absf(v.x) * 7.0 + absf(v.y) * 3.0)) & 3
				Sprites.glow(ci, p, 13.0 if evo else 9.0, fire_glow)
				Sprites.draw_mid_r(ci, big_fires[f] if evo else fires[f], p)
			World.SP_FROST:
				var d := Sprites.dir16(v)
				Sprites.glow(ci, p, 5.0 if evo else 3.0, frost_glow)
				Sprites.draw_mid_r(ci, big_shards[d] if evo else shards[d], p)
			World.SP_STAR:
				# A falling star: a twinkling star with a comet's tail (the mark and the burst when it lands are Fx's).
				var d := Sprites.dir16(v)
				Sprites.glow(ci, p, 10.0 if evo else 7.0, Color(star_col, 0.4))
				Sprites.draw_mid_r(ci, lances[d] if evo else bolts[d], p, Color(star_col, 0.7))
				Sprites.draw_mid_r(ci, big_stars[tick & 3] if evo else stars[tick & 3], p)
	# Staff heads and the rune shield's orbs
	var orb := Sprites.region("fx_orb")
	var orb_glow := Color(Sprites.ORBIT_COLOR, 0.4)
	for slot in a.vp:
		var p: Dictionary = a.vp[slot]
		if not p.alive:
			continue
		var aim: Vector2 = p.aim
		var tip: Vector2 = p.pos + Vector2(0, -7) + aim * 9.0
		var sc := G.player_fx(slot)
		# A staff held away from the camera is behind the wizard's hat: its light is dimmer, and never white.
		var hidden := aim.y < 0.0 and absf(aim.y) > absf(aim.x) * 1.1
		if a.time - float(p.get("flare_at", -9.0)) < a.CAST_FLARE:
			Sprites.glow(ci, tip, 5.0, Color(sc, 0.5 if hidden else 0.95))
			if not hidden:
				Sprites.draw_mid_r(ci, big_core, tip)
		else:
			Sprites.glow(ci, tip, 3.5 if hidden else 5.0, Color(sc, 0.4 + 0.12 * sin(a.time * 6.0 + slot)))
		if p.orbit > 0.0 and (p.orbit > 2.0 or int(a.time * 10) % 2 == 0):
			for i in 3:
				var ang: float = p.orbit_ang + i * TAU / 3.0
				var op: Vector2 = p.pos + Vector2(0, -6) + Vector2(cos(ang), sin(ang)) * 22.0
				Sprites.glow(ci, op, 6.0, orb_glow)
				Sprites.draw_mid_r(ci, orb, op)
	# Danger is red: a halo under each enemy shot, and round a mage that is gathering one.
	var danger := Color(0.75, 0.15, 0.23, 0.5)
	for s in a.ves:
		Sprites.glow(ci, s[1], 5.0, danger)
	for e in a.ve.values():
		if e.type == World.LICH:
			Sprites.glow(ci, e.pos + Vector2(0, -14), 28.0, Color(0.2, 0.88, 0.77, 0.1 + 0.03 * sin(a.time * 3.0)))
		elif e.type == World.MAGE and e.state == 1:
			Sprites.glow(ci, e.pos + Vector2(0, -8), 7.0, danger)


## Enemy shots, over everything: a dark rim round a blood-red body with an orange core, so none can be taken for
## a wizard's magic or for a pickup. Arrows are plotted for their direction; orbs and skulls pulse.
static func _draw_eshots(a: Arena) -> void:
	var ci := a.eshot_layer
	var arrows: Array = Sprites.strip("fx_earrow", Sprites.DIRS)
	var orbs: Array = Sprites.strip("fx_eorb", 2)
	var skulls: Array = Sprites.strip("fx_eskull", 2)
	var beat := int(a.time * 8.0) & 1
	for s in a.ves:
		var p: Vector2 = s[1]
		match s[0]:
			World.ES_ARROW:
				var v: Vector2 = s[2]
				Sprites.draw_mid_r(ci, arrows[Sprites.dir16(v)], p - v.normalized() * 4.0)
			World.ES_ORB:
				Sprites.draw_mid_r(ci, orbs[beat], p)
			World.ES_SKULL:
				Sprites.draw_mid_r(ci, skulls[beat], p)
