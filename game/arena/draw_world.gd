class_name ArenaDrawWorld
extends RefCounted
## Arena: the floor, env, hint, runes, entities, wizards and staffs.
## Static helpers: `a` is the Arena that owns the state.

## The play window: what the HUD band leaves of the screen.
const PLAY_WINDOW := Rect2(0, G.HUD_H, G.SCREEN.x, G.SCREEN.y - G.HUD_H)
## Pixels of floor kept between a wizard's body and the window's edge.
const VIEW_MARGIN := 2.0


## Eases the camera toward the living humans (all living wizards when none is human, everyone when none lives).
## It keeps today's centring, shifts only as far as needed to keep every body inside the window, and stays inside
## the arena image. The HUD band covers the top of the screen, so the view may rise by the band's height.
static func _follow_party(a: Arena, dt: float) -> void:
	var members := camera_members(a.vp.values())
	if members.is_empty():
		return
	var first: bool = a.cam == Vector2.ZERO and a.time < 0.2
	a.cam = wanted_camera(members) if first else eased_camera(a.cam, members, minf(1.0, dt * a.CAM_EASE))


## True for a wizard who is still in the run: standing, or fallen and walking as a spirit (her view row says
## alive = false while she is down).
static func in_the_run(p: Dictionary) -> bool:
	return p.alive or p.get("down", false)


## Whose feet the camera frames, from view dictionaries (pos, alive, ai): every living human wizard, standing or
## fallen (her spirit counts); failing that every living wizard; failing that everyone.
static func camera_members(people: Array) -> Array[Vector2]:
	for pass_i in 3:
		var out: Array[Vector2] = []
		for p: Dictionary in people:
			if pass_i == 0 and (not in_the_run(p) or p.get("ai", false)):
				continue
			if pass_i == 1 and not in_the_run(p):
				continue
			out.append(p.pos)
		if not out.is_empty():
			return out
	return []


## The box around these feet.
static func feet_box(feet: Array[Vector2]) -> Rect2:
	var box := Rect2(feet[0], Vector2.ZERO)
	for q: Vector2 in feet:
		box = box.expand(q)
	return box


## The camera that shows these feet: their box centred in the play window, shifted only as far as needed to put every
## body (ArenaTrayArt.WIZARD_BOX) inside the window with VIEW_MARGIN to spare, then clamped to the world.
static func wanted_camera(feet: Array[Vector2]) -> Vector2:
	return held_in_view(feet_box(feet).get_center() - Vector2(G.SCREEN.x / 2.0, (G.SCREEN.y + G.HUD_H) / 2.0), feet)


## `cam` moved as little as it takes to show every body of these feet inside the window with VIEW_MARGIN to spare
## (on an axis too short for them all: the middle), then kept inside the arena image.
static func held_in_view(cam: Vector2, feet: Array[Vector2]) -> Vector2:
	var box := feet_box(feet)
	var body := ArenaTrayArt.WIZARD_BOX
	var inner := PLAY_WINDOW.grow(-VIEW_MARGIN)
	var lo := box.end + body.end - inner.end
	var hi := box.position + body.position - inner.position
	for k in 2:
		cam[k] = (lo[k] + hi[k]) / 2.0 if lo[k] > hi[k] else clampf(cam[k], lo[k], hi[k])
	return cam.clamp(Vector2(0.0, -G.HUD_H), G.WORLD - G.SCREEN)


## The camera one frame on: eased by `k` (0 to 1) toward the wanted one, and never so far behind a running party
## that a body leaves the window.
static func eased_camera(cam: Vector2, feet: Array[Vector2], k: float) -> Vector2:
	return held_in_view(cam.lerp(wanted_camera(feet), k), feet)


## The largest leash (across, up and down between two wizards' feet) the play window has room for: the window less
## the margins, less one body.
static func leash_room() -> Vector2:
	return PLAY_WINDOW.size - Vector2.ONE * 2.0 * VIEW_MARGIN - ArenaTrayArt.WIZARD_BOX.size


static func _draw_decals(a: Arena) -> void:
	for d in a.decals:
		var c: Color = d[1]
		c.a = clampf(d[3] / 4.0, 0.0, 1.0) * 0.42
		var p: Vector2 = d[0]
		var s: float = d[2]
		var seed: int = d[4]
		# A squashed blob of rects: rects batch into one draw call, where circles cost one call each.
		var r := s * 0.6
		var o := p.floor()
		a.decal_layer.draw_rect(Rect2(o.x - r, o.y - r * 0.35, r * 2.0, r * 0.7), c)
		a.decal_layer.draw_rect(Rect2(o.x - r * 0.7, o.y - r * 0.55, r * 1.4, r * 1.1), c)
		for k in 4:
			var q := Vector2(((seed >> (k * 4)) % 13) - 6, (((seed >> (k * 4 + 2)) % 9) - 4) * 0.55) * s * 0.18
			var dr := s * 0.3
			a.decal_layer.draw_rect(Rect2((o + q - Vector2(dr, dr * 0.55)).floor(), Vector2(dr * 2.0, dr * 1.1)), c)


static func _draw_env(a: Arena) -> void:
	var ci := a.env_layer
	ArenaDrawHazards.draw(a, ci)
	# Rune circles: a dark scorched disc under the glow, so the ring reads on any floor.
	for c: Array in a.vr:
		var k := _rune_alpha(a, c)
		ci.draw_circle(c[0], float(c[1]) * _rune_grow(a, c) + 1.0, Color(0.06, 0.0, 0.05, 0.45 * k))
	# Flames on the backdrop's candles and fire bowls. While the backdrop fades to a new act, the old act's
	# flames fade out with its picture and the new act's fade in.
	var k := _act_blend(a)
	if k < 1.0:
		ArenaArtLive.draw(ci, ArenaBg.scene(a._prev_act), a.time, 1.0 - k)
	ArenaArtLive.draw(ci, ArenaBg.scene(a.act), a.time, k)


static func _draw_env_add(a: Arena) -> void:
	var ci := a.env_add
	# The light of those flames, the seal breathing, each door's glow, flaring while monsters come through, and
	# the rings under the wizards.
	var k := _act_blend(a)
	if k < 1.0:
		ArenaArtLive.draw_glow(ci, ArenaBg.scene(a._prev_act), a.time, a.door_anim, 1.0 - k)
	ArenaArtLive.draw_glow(ci, ArenaBg.scene(a.act), a.time, a.door_anim, k)
	_draw_runes(a, ci)
	# Each wizard's ring glows on the floor in their colour, over the decals, under the shadows and every foot.
	for p: Dictionary in a.vp.values():
		if p.alive:
			var at := (p.pos as Vector2) + Vector2(0, 0.5)
			var beat := 0.85 + 0.15 * sin(a.time * 3.0 + float(p.slot))
			Sprites.draw_mid(ci, "wiz_ring", at, Color(G.player_fx(p.slot), beat))
			Sprites.draw_mid(ci, "wiz_ring", at, Color(G.player_color(p.slot), 0.5 * beat))


## How far the backdrop has faded to the current act: 1 when no fade is running.
static func _act_blend(a: Arena) -> float:
	return 1.0 if a._act_fade < 0.0 else clampf(a._act_fade / 2.0, 0.0, 1.0)


## How far a rune circle has drawn itself in (0..1), from its age.
static func _rune_grow(a: Arena, c: Array) -> float:
	return clampf(float(c[2]) / a.RUNE_DRAW_IN, 0.0, 1.0)


## A rune circle's brightness: up while it draws in, down over its last RUNE_FADE seconds.
static func _rune_alpha(a: Arena, c: Array) -> float:
	return clampf((float(c[3]) - float(c[2])) / a.RUNE_FADE, 0.0, 1.0) * (0.4 + 0.6 * _rune_grow(a, c))


## Active rune circles on the additive floor layer: a double ring with gold runes turning between, a pentagram
## inside (a hexagram for the Seal of Solomon, with motes drawn inward), flaring on every damage tick.
## The first-run controls hint: a small occult panel low on the screen that slides in and out.
static func _draw_hint(a: Arena, ci: CanvasItem) -> void:
	if a._hint_t < 0.0 or a._hint_t >= a.HINT_LIFE:
		return
	var k := minf(1.0, minf(a._hint_t, a.HINT_LIFE - a._hint_t) * 3.0)
	var r := Rect2(96, 206 + (1.0 - k) * 70.0, 288, 46)
	Occult.frame(ci, r, a.time, false)
	var y := r.position.y + 4
	for l: Array in a.HINT_LINES:
		PixelFont.draw(ci, l[0], Vector2(r.position.x + 8, y), 1, Color("ffd94d"))
		PixelFont.draw(ci, l[1], Vector2(r.position.x + 44, y), 1, Color("fff6e0"))
		y += 10


## The additive floor layer's magic, under the actors: the marks fallen stars leave, and the active rune circles.
## A circle is a ring with two broken rings turning inside it, as on the Sanctum's portal, a slow wheel of gold
## runes between them and a pentagram in the middle (a hexagram for the Seal of Solomon, with motes drawn
## inward); all of it flares on every damage tick.
static func _draw_runes(a: Arena, ci: CanvasItem) -> void:
	a.fx.draw_floor(ci)
	var runes: Array = Sprites.strip("fx_rune", Occult.RUNES.size())
	for c: Array in a.vr:
		var at: Vector2 = (c[0] as Vector2).floor() + Vector2(0.5, 0.5)
		var evo: bool = c[5]
		var r: float = roundf(float(c[1]) * (0.6 + 0.4 * _rune_grow(a, c)))
		var k := _rune_alpha(a, c)
		var since := fposmod(float(c[2]) - Spells.RUNE_ARM, Spells.RUNE_TICK)
		var flare := clampf(1.0 - since / (Spells.RUNE_TICK * 0.5), 0.0, 1.0) if float(c[2]) >= Spells.RUNE_ARM else 0.0
		if int(c[6]) == Spells.CIRCLE_CANDLE:
			_draw_candle(a, ci, c, at, r, k, flare)
			continue
		var col: Color = a.SEAL_RING if evo else a.SPELL_COLORS[World.SP_RUNE]
		var glyph: Color = a.SEAL_WHITE if evo else a.RUNE_GOLD
		var turn := (a.time * 0.5 + float(c[4])) * (1.0 if int(c[4]) % 2 == 0 else -1.0)
		ci.draw_circle(at, r, Color(col, (0.05 + 0.09 * flare) * k))
		var segs := 48 if r > 24.0 else 32
		ci.draw_arc(at, r, 0.0, TAU, segs, Color(col, (0.75 + 0.25 * flare) * k), 1.0)
		ci.draw_arc(at, r - 2.0, turn * 1.6, turn * 1.6 + TAU * 0.8, segs, Color(col, (0.4 + 0.3 * flare) * k), 1.0)
		ci.draw_arc(at, r - 10.0, -turn * 2.2, -turn * 2.2 + TAU * 0.8, segs, Color(col, (0.5 + 0.3 * flare) * k), 1.0)
		var n := maxi(5, int(TAU * (r - 6.0) / 11.0))
		var gc := Color(glyph, (0.6 + 0.4 * flare) * k)
		for g in n:
			var ang := turn + g * TAU / n
			Sprites.draw_mid_r(ci, runes[(g * 3 + int(c[4])) % runes.size()], at + Vector2.from_angle(ang) * (r - 6.0), gc)
		var inner := r - 11.0
		if evo:
			# The Seal of Solomon: two interlaced triangles, and motes pulled toward the centre.
			for t in 2:
				var tri := PackedVector2Array()
				for v in 4:
					tri.append(at + Vector2.from_angle(-turn * 0.5 + t * PI + v * TAU / 3.0 - PI / 2.0) * inner)
				ci.draw_polyline(tri, Color(a.SEAL_WHITE, (0.6 + 0.4 * flare) * k), 1.0)
			var reach := float(c[1]) * Spells.SEAL_REACH
			for m in 10:
				var f := fposmod(a.time * 0.8 + m * 0.37, 1.0)
				var mp := at + Vector2.from_angle(m * 2.4 + turn * 0.3) * lerpf(reach, r * 0.3, f)
				Sprites.rect(ci, Rect2(mp.floor(), Vector2(1, 1)), Color(a.SEAL_WHITE, 0.7 * k * (1.0 - f * 0.5)))
		elif inner > 3.0:
			Occult.pentagram(ci, at, inner, Color(col, (0.3 + 0.4 * flare) * k), -turn * 0.5)


## The colour of a circle in the snapshot: a rune circle's (the Seal's when evolved) or a light's (VIGIL CANDLE's
## flame, or the class skin's: the priest's HOLY LIGHT is white).
static func _circle_color(a: Arena, c: Array) -> Color:
	if int(c[6]) == Spells.CIRCLE_CANDLE:
		return ArenaDrawFx._spell_color(a, World.SP_CANDLE, int(c[4]))
	return a.SEAL_RING if c[5] else a.SPELL_COLORS[World.SP_RUNE]


## A vigil candle's light: a warm disc with a ring, flaring on each burn, and a candle in the middle; the priest's
## HOLY LIGHT is white with a cross instead, and CONSECRATION adds a gold outer ring.
static func _draw_candle(a: Arena, ci: CanvasItem, c: Array, at: Vector2, r: float, k: float, flare: float) -> void:
	var col := _circle_color(a, c)
	var holy := ArenaDrawFx._skin(a, int(c[4]), World.SP_CANDLE) == "holy_light"
	ci.draw_circle(at, r, Color(col, (0.08 + 0.1 * flare) * k))
	var segs := 40 if r > 24.0 else 28
	ci.draw_arc(at, r, 0.0, TAU, segs, Color(col, (0.7 + 0.3 * flare) * k), 1.0)
	if c[5]:
		ci.draw_arc(at, r + 2.0, 0.0, TAU, segs, Color(a.RUNE_GOLD, 0.6 * k), 1.0)
	var base := at.floor()
	var flick := 1.0 if int(a.time * 8.0 + float(c[4])) % 2 == 0 else 0.0
	Sprites.glow(ci, base + Vector2(0, -4), 8.0 + 3.0 * flare, Color(col, 0.5 * k))
	if holy:
		Sprites.rect(ci, Rect2(base.x, base.y - 9.0, 1.0, 11.0), Color(Color.WHITE, k))
		Sprites.rect(ci, Rect2(base.x - 3.0, base.y - 6.0, 7.0, 1.0), Color(Color.WHITE, k))
	else:
		Sprites.rect(ci, Rect2(base.x - 1.0, base.y - 4.0, 3.0, 6.0), Color(Color("fff6e0"), k))
		Sprites.rect(ci, Rect2(base.x, base.y - 7.0 - flick, 1.0, 3.0 + flick), Color(Color.WHITE, k))
		Sprites.rect(ci, Rect2(base.x - 1.0, base.y - 6.0, 3.0, 2.0), Color(col, k))


## The shadow under an actor or a pickup: a squat lozenge `w` wide, from the atlas so it batches with the sprites.
static func _shadow(a: Arena, ci: CanvasItem, pos: Vector2, w: float) -> void:
	var h := maxf(2.0, floorf(w * 0.35))
	var at := (pos - Vector2(w / 2.0, h / 2.0)).floor()
	Sprites.rect(ci, Rect2(at.x + 1.0, at.y, w - 2.0, h), a.SHADOW_COLOR)
	Sprites.rect(ci, Rect2(at.x + 2.0, at.y - 1.0, w - 4.0, h + 2.0), a.SHADOW_COLOR)


## A pillar of light over a card or a rare chest so it is seen across a crowded arena, and a glint that comes
## and goes over it.
static func _draw_treasure_glow(a: Arena, ci: CanvasItem, kind: int, pos: Vector2) -> void:
	var col := ArenaDrawFx._pickup_color(a, kind)
	var pulse := 0.5 + 0.5 * sin(a.time * 5.0 + pos.x)
	var tall := 60.0 if kind != World.PK_CHEST_RARE else 30.0
	var at := pos.floor()
	for i: int in range(3):
		var w := 7.0 - i * 2.0
		Sprites.rect(ci, Rect2(at.x - floorf(w / 2.0), at.y - tall, w, tall), Color(col, (0.07 + 0.05 * pulse) * (i + 1)))
	if kind == World.PK_CHEST_ULTRA:
		col = Color.from_hsv(fposmod(a.time * 0.5, 1.0), 0.6, 1.0)
	Sprites.glow(ci, pos + Vector2(0, -4), 8.0 + 2.0 * pulse, Color(col, 0.3))
	var beat := a.time * 1.6 + pos.x * 0.37
	var f := int(fposmod(beat, 1.0) * 8.0)
	if f < 3:
		var spot := int(floorf(beat)) * 7
		Sprites.draw_mid_r(ci, Sprites.strip("fx_spark", 3)[f], pos + Vector2((spot % 11) - 5, -5 - (spot % 6)), col.lerp(Color.WHITE, 0.6))


static func _draw_entities(a: Arena) -> void:
	var ci := a.ent_layer
	ArenaFateView._draw_shrines(a, ci)
	for u: Vector2 in a.vu:
		_shadow(a, ci, u + Vector2(0, 1), 10)
		Sprites.draw_at(ci, "urn", u + Vector2(0, 1))
	# Pickups: calm on the floor. The motes come in hundreds, so they neither bob nor cast a shadow, and each
	# twinkles for a blink every couple of seconds.
	var xp_r := Sprites.region("xp")
	var xp_twinkle := Sprites.region("xp_1")
	var coins: Array = [Sprites.region("coin"), Sprites.region("coin_1"), Sprites.region("coin_2"), Sprites.region("coin_3")]
	var glints: Array = Sprites.strip("fx_spark", 3)
	for k in a.vk:
		var kind: int = k[0]
		var pos: Vector2 = k[1]
		var life: float = k[2]
		if life < 3.0 and int(life * 10.0) % 2 == 0:
			continue
		if kind == World.PK_XP:
			var lit := fposmod(a.time * 0.45 + pos.x * 0.173 + pos.y * 0.291, 1.0) < 0.05
			Sprites.draw_mid_r(ci, xp_twinkle if lit else xp_r, pos + Vector2(0, -2))
			continue
		var bob := floorf(sin(a.time * 3.0 + pos.x) * 1.5)
		var chest := kind == World.PK_CHEST or kind == World.PK_CHEST_RARE or kind == World.PK_CHEST_ULTRA
		if kind >= World.PK_CARD:
			_draw_treasure_glow(a, ci, kind, pos)
		_shadow(a, ci, pos + Vector2(0, 1), 12 if chest else 8)
		if kind == World.PK_COIN:
			Sprites.draw_mid_r(ci, coins[int(a.time * 7.0 + pos.x * 0.31) & 3], pos + Vector2(0, -5 + bob))
		elif chest:
			# A chest sits on the floor; a glint crosses its lid now and then.
			Sprites.draw_at(ci, a.PICKUP_KEYS[kind], pos + Vector2(0, 2))
			var beat := a.time * 0.8 + pos.x * 0.21
			var f := int(fposmod(beat, 1.0) * 10.0)
			if f < 3:
				Sprites.draw_mid_r(ci, glints[f], pos + Vector2(-4 + (int(floorf(beat)) % 3) * 4, -8))
		else:
			Sprites.draw_at(ci, a.PICKUP_KEYS[kind], pos + Vector2(0, -2 + bob))
	# Collect drawables sorted by y
	var list := []
	for p in a.vp.values():
		if p.alive:
			list.append([p.pos.y, 0, p])
	for e in a.ve.values():
		list.append([e.pos.y, 1, e])
	list.sort_custom(func(x, y): return x[0] < y[0])
	for it in list:
		if it[1] == 0:
			_shadow(a, ci, it[2].pos, 12)
		else:
			var e: Dictionary = it[2]
			if a.ENEMY_SHADOW[e.type] > 0 and e.type != World.BAT and not (e.type == World.GARGOYLE and e.state == 1):
				_shadow(a, ci, e.pos, a.ENEMY_SHADOW[e.type])
	ArenaDrawEnemies._draw_enemy_glows(a, ci)
	# The wizards themselves stand on their own layer, over the crowd and out of the room's dark (`_draw_wizards`).
	for it in list:
		if it[1] == 1:
			ArenaDrawEnemies._draw_enemy(a, ci, it[2])


## How far below the old P-tag's top a wizard's pip sits, and how far apart two pips must be.
const PIP_DROP := 4.0
const PIP_GAP := 8.0
## The rim round a wizard drawn from her picture: an apprentice's (and its dark line) is this opaque, so humans stand out.
const RIM_AI_ALPHA := 0.5
## The dark disc behind a wizard (see `_draw_player`).
const WIZ_BACKING := Color(0.03, 0.02, 0.08, 0.5)


## The wizards' layer, above the room's light map and the enemy crowd: every wizard with its halo, the enemies'
## bars, the pips that say whose wizard is whose, and the ghosts of the fallen.
static func _draw_wizards(a: Arena) -> void:
	var ci := a.wiz_layer
	var list: Array = []
	for p: Dictionary in a.vp.values():
		if p.alive:
			list.append(p)
	list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return (x.pos as Vector2).y < (y.pos as Vector2).y)
	ArenaDrawEnemies._draw_enemy_bars(a, ci)
	ArenaDrawFallen.draw(a, ci)
	for p: Dictionary in list:
		_draw_player(a, ci, p)
	if a.vp.size() > 1 or Net.is_online():
		_draw_pips(a, ci, list)
	EnemyView.draw_marks(a, ci)
	for g: Array in a._ghosts:
		var k: float = g[1] / a.GHOST_LIFE
		var gp: Vector2 = g[0] + Vector2(sin(k * 9.0) * 3.0, -40.0 * k)
		Sprites.draw_at(ci, "wiz%d_up_i0" % g[2], gp.round(), false, false, Color(0.7, 0.9, 1.3, 0.6 * (1.0 - k)))


## A small pip in each wizard's colour over the hat, in place of a P-tag. Pips of wizards standing together are
## pushed apart sideways so no two overlap.
static func _draw_pips(a: Arena, ci: CanvasItem, list: Array) -> void:
	var at: Array[Vector2] = []
	for p: Dictionary in list:
		var up: float = (a.TAG_UP_ORBS if p.orbit > 0.0 else a.TAG_UP) - PIP_DROP
		at.append(Vector2(roundf(p.pos.x), roundf(p.pos.y - up)))
	for _pass in 3:
		for i in at.size():
			for j in range(i + 1, at.size()):
				var d := at[j] - at[i]
				if absf(d.x) < PIP_GAP and absf(d.y) < 6.0:
					var push := ceilf((PIP_GAP - absf(d.x)) / 2.0)
					var s := 1.0 if d.x > 0.0 or (d.x == 0.0 and j > i) else -1.0
					at[i].x -= push * s
					at[j].x += push * s
	var bob := floorf(sin(a.time * 3.0) * 0.99 + 0.5)
	for i in list.size():
		var p: Dictionary = list[i]
		if p.invuln > 0.0 and int(a.time * 20.0) % 2 == 0 and p.invuln < 2.4:
			continue
		Sprites.draw_mid(ci, "wiz_pip", at[i] + Vector2(0, bob), G.player_color(p.slot).lerp(Color.WHITE, 0.25))


## One wizard: the walk cycle (or the idle breath), the casting pose for a moment after a spell leaves, the staff
## (behind the body when they face away), over its halo.
static func _draw_player(a: Arena, ci: CanvasItem, p: Dictionary) -> void:
	var slot: int = p.slot
	if p.invuln > 0.0 and int(a.time * 20.0) % 2 == 0 and p.invuln < 2.4:
		return
	var aim: Vector2 = p.aim
	var dirkey := "down"
	var flip := false
	if absf(aim.y) > absf(aim.x) * 1.1:
		dirkey = "up" if aim.y < 0 else "down"
	else:
		dirkey = "side"
		flip = aim.x < 0
	var casting: bool = a.time - float(p.get("cast_at", -9.0)) < a.CAST_POSE
	var key := SpritesWizards.frame_key(G.wizard_of(slot), dirkey, p.moving, int(p.walk_t), int(a.time * 2.0 + slot * 0.5), casting,
		aim.x >= 0.0)
	var feet: Vector2 = p.pos + Vector2(0, 1)
	var still := Still.hero_name(int(p.get("cls", 0)), bool(p.get("ai", false)), int(p.get("race", -1)))
	if not still.is_empty():
		_draw_player_still(a, ci, p, still, feet, -1 if flip else 1)
		return
	# Haste afterimages
	if p.haste > 0.0:
		for gi in range(2, p.ghosts.size(), 2):
			var gc := Color(0.56, 0.89, 1.0, 0.35 - gi * 0.035)
			Sprites.draw_at(ci, key, p.ghosts[gi] + Vector2(0, 1), flip, true, gc)
	var grip: Vector2 = p.pos + SpritesWizards.grip(dirkey, aim)
	var tip: Vector2 = p.pos + Vector2(0, -7) + aim * 9.0
	if dirkey == "up":
		_draw_staff(a, ci, grip, tip, slot)
	# A soft dark backing, so a wizard standing in a blast or a cloud of smoke still stands out of it.
	Sprites.glow(ci, p.pos + Vector2(0, -10), 15.0, WIZ_BACKING)
	# The halo: a rim in the wizard's colour round the sprite's own outline, and a dark line round that, so the
	# wizard stands out of any crowd or floor.
	Sprites.draw_at(ci, key + "~", feet + Vector2(0, SpritesWizards.HALO), flip, false, G.player_color(slot).lerp(Color.WHITE, 0.3))
	Sprites.draw_at(ci, key, feet, flip, p.flash > 0.0)
	if dirkey != "up":
		_draw_staff(a, ci, grip, tip, slot)


## A wizard drawn from her one still picture: the seat's ring under her feet (the pip over her stays), the soft
## backing, haste afterimages, the picture moved by `Still.motion`. The picture holds its own weapon, so no staff.
static func _draw_player_still(a: Arena, ci: CanvasItem, p: Dictionary, still: String, feet: Vector2, facing: int) -> void:
	var slot: int = p.slot
	var t: float = a.time + slot * 0.5
	if p.haste > 0.0:
		for gi in range(2, p.ghosts.size(), 2):
			Still.draw(ci, still, p.ghosts[gi] + Vector2(0, 1), facing, t, true, Color(0.56, 0.89, 1.0, 0.35 - gi * 0.035))
	Sprites.glow(ci, p.pos + Vector2(0, -10), 15.0, WIZ_BACKING)
	Sprites.draw_mid(ci, "wiz_ring", feet + Vector2(0, -1), Color(G.player_color(slot).lerp(Color.WHITE, 0.3), Still.RING_ALPHA))
	var rim := G.player_color(slot).lerp(Color.WHITE, 0.3)
	var fade := RIM_AI_ALPHA if bool(p.get("ai", false)) else 1.0
	Still.draw_rim(ci, still, feet, facing, t, bool(p.moving), Color(rim, fade), Color(Sprites.OUTLINE, fade))
	Still.draw(ci, still, feet, facing, t, bool(p.moving), Color.WHITE, p.flash > 0.0)


## A wizard's staff: a wooden shaft through the grip with a short butt behind it and a gold band under the head,
## and the head itself where the simulation casts from (`tip`). Its glow, and the flare of a cast, are drawn with
## the shots on the additive layer.
static func _draw_staff(a: Arena, ci: CanvasItem, grip: Vector2, tip: Vector2, slot: int) -> void:
	var along := tip - grip
	var u := along.normalized() if along.length() > 0.5 else Vector2.DOWN
	var butt := grip - u * 3.0
	Sprites.line(ci, butt, tip, Sprites.OUTLINE, 1)
	Sprites.line(ci, butt, tip, a.STAFF_WOOD)
	Sprites.line(ci, tip - u * 3.0, tip, a.STAFF_BAND)
	Sprites.draw_mid(ci, "fx_staff_%d" % G.wizard_of(slot), tip)
