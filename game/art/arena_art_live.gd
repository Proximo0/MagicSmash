class_name ArenaArtLive
extends RefCounted
## What moves on an arena backdrop. The baked picture (ArenaBg) has dark wicks, cold fire bowls and a seal whose
## grooves barely glow; the arena draws these over it every frame: flames, their flickering light, the seal
## breathing and its runes lighting in turn, and the flare of a door while monsters come through it.
##
## Everything reads the act's scene (ArenaBg.scene): "flames" [[position, kind], ...], "glows" [[centre, radii],
## ...], "doors" [Rect2 per World.DOORS entry], "seal" (see ArenaArtRoom.seal), and the colours "flame" (tip,
## middle, core and the low edge of a fire), "fire" (the light flames throw), "door_light" and "seal_light".
## Rects batch into one draw call and so do draws of one texture, so the whole layer costs a handful of calls.

const CANDLE := 0
const FIRE := 1

const _TIP := Color("ff9a3c")
const _MID := Color("ffcf5a")
const _CORE := Color("fff3c4")
const _FIRE_LOW := Color("c85a1e")
## Defaults and tables kept as constants so drawing makes no arrays each frame.
const _FLAME: Array = [_TIP, _MID, _CORE, _FIRE_LOW]
const _TONGUES: Array[int] = [2, 4, 6, 4, 2]
const _NONE: Array = []

static var _soft: ImageTexture


## A round falloff, white, for every soft light on the additive layer.
static func _soft_tex() -> ImageTexture:
	if _soft == null:
		_soft = ImageTexture.create_from_image(ArenaArtCanvas.pool(32, 32, 1.0, 1.8))
	return _soft


static func _hash(a: int, b: int) -> int:
	var h := (a * 374761393 + b * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h ^ (h >> 16)


## Flames, on the ordinary layer under the monsters. `alpha` fades them in with a new act's backdrop.
static func draw(ci: CanvasItem, scene: Dictionary, time: float, alpha: float = 1.0) -> void:
	var flames: Array = scene.get("flames", _NONE)
	var cols: Array = scene.get("flame", _FLAME)
	var tip := Color(cols[0] as Color, alpha)
	var mid := Color(cols[1] as Color, alpha)
	var core := Color(cols[2] as Color, alpha)
	var low := Color(cols[3] as Color, alpha)
	for i in flames.size():
		var f: Array = flames[i]
		var p: Vector2 = f[0]
		var tick := int(time * 9.0 + i * 0.37)
		var h := _hash(i, tick)
		if int(f[1]) == FIRE:
			# A fire bowl: five tongues, the middle one tallest.
			for k in range(-2, 3):
				var tall: int = _TONGUES[k + 2] + ((h >> ((k + 2) * 3)) & 3) - 1
				ci.draw_rect(Rect2(p.x + k, p.y - tall, 1, tall), low if absi(k) == 2 else tip)
				if absi(k) <= 1 and tall > 2:
					ci.draw_rect(Rect2(p.x + k, p.y - tall + 2, 1, tall - 2), mid)
			ci.draw_rect(Rect2(p.x, p.y - 2, 1, 2), core)
			continue
		# A candle: a bright bead on the wick, a tongue above it that leans and gutters.
		var frame := h & 7
		ci.draw_rect(Rect2(p.x, p.y - 1, 1, 1), core)
		ci.draw_rect(Rect2(p.x, p.y - 2, 1, 1), mid)
		if frame < 6:
			var lean := 1 if frame == 4 else (-1 if frame == 5 else 0)
			ci.draw_rect(Rect2(p.x + lean, p.y - 3, 1, 1), tip)
		if frame < 3:
			ci.draw_rect(Rect2(p.x - 1, p.y - 1, 3, 1), Color(tip, 0.5 * alpha))


## Light, on the additive layer under the monsters. `open` is how far each of the four doors has flared (0..1).
static func draw_glow(ci: CanvasItem, scene: Dictionary, time: float, open: Array, alpha: float = 1.0) -> void:
	var soft := _soft_tex()
	var fire: Color = scene.get("fire", Color(1.0, 0.55, 0.18))
	# The pools the lamps throw on the floor are baked; this is only their flicker.
	var glows: Array = scene.get("glows", _NONE)
	for i in glows.size():
		var g: Array = glows[i]
		var c: Vector2 = g[0]
		var r: Vector2 = g[1]
		var f := 0.6 + 0.4 * sin(time * 11.0 + i * 1.7) * sin(time * 6.3 + i * 2.9)
		ci.draw_texture_rect(soft, Rect2(c - r, r * 2.0), false, Color(fire, 0.075 * f * alpha))
	var flames: Array = scene.get("flames", _NONE)
	for i in flames.size():
		var f: Array = flames[i]
		var p: Vector2 = f[0]
		var k := 0.8 + 0.2 * sin(time * 13.0 + i * 2.3)
		if int(f[1]) == FIRE:
			ci.draw_texture_rect(soft, Rect2(p.x - 14.0, p.y - 15.0, 29.0, 24.0), false, Color(fire, 0.5 * k * alpha))
		else:
			ci.draw_texture_rect(soft, Rect2(p.x - 6.0, p.y - 8.0, 13.0, 12.0), false, Color(fire, 0.42 * k * alpha))
	_draw_doors(ci, scene, time, open, alpha)
	if scene.has("seal"):
		_draw_seal(ci, scene, time, alpha)


## Each door glows a little all the time and flares while a group is coming through it.
static func _draw_doors(ci: CanvasItem, scene: Dictionary, time: float, open: Array, alpha: float) -> void:
	var soft := _soft_tex()
	var doors: Array = scene.get("doors", _NONE)
	var col: Color = scene.get("door_light", Color(1.0, 0.16, 0.2))
	for i in mini(doors.size(), open.size()):
		var r: Rect2 = doors[i]
		var o: float = open[i]
		var idle := 0.10 + 0.05 * sin(time * 1.7 + i * 1.9)
		var flick := 0.8 + 0.2 * sin(time * 17.0 + i) * sin(time * 9.1 + i * 3.0)
		# In the opening.
		var inside := r.grow(4.0)
		ci.draw_texture_rect(soft, inside, false, Color(col, (idle + 0.75 * o * flick) * alpha))
		if o <= 0.0:
			continue
		# On the floor in front of it: a fan of light into the room.
		var into := Vector2(0, 1)
		match i:
			1: into = Vector2(0, -1)
			2: into = Vector2(1, 0)
			3: into = Vector2(-1, 0)
		var mouth := r.get_center() + into * (r.size * 0.5)
		var across := Vector2(absf(into.y), absf(into.x))
		var half := across * 54.0 + Vector2(absf(into.x), absf(into.y)) * 70.0
		ci.draw_texture_rect(soft, Rect2(mouth + into * 6.0 - half, half * 2.0), false, Color(col, 0.5 * o * flick * alpha))
		var hot := Color(col.r, col.g + 0.3, col.b + 0.1)
		half = across * 22.0 + Vector2(absf(into.x), absf(into.y)) * 20.0
		ci.draw_texture_rect(soft, Rect2(mouth - half, half * 2.0), false, Color(hot, 0.5 * o * flick * alpha))


## The seal breathes: its grooves brighten and dim, a wave of light goes round its runes, and three motes
## circle the outer ring.
static func _draw_seal(ci: CanvasItem, scene: Dictionary, time: float, alpha: float) -> void:
	var seal: Dictionary = scene.seal
	var c: Vector2 = seal.c
	var squash: float = seal.squash
	var col: Color = scene.get("seal_light", Color(0.35, 0.9, 1.0))
	var breath := 0.5 + 0.5 * sin(time * 1.3)
	var rx: float = float(seal.rx) + 26.0
	ci.draw_texture_rect(_soft_tex(), Rect2(c.x - rx, c.y - rx * squash, rx * 2.0, rx * squash * 2.0), false,
		Color(col, (0.05 + 0.04 * breath) * alpha))
	if seal.has("tex"):
		ci.draw_texture(seal.tex, seal.at, Color(col, (0.16 + 0.17 * breath) * alpha))
	var runes: Array = seal.get("runes", _NONE)
	var n := runes.size()
	for i in n:
		# Two crests chase each other round the band.
		var k := maxf(0.0, cos(i * TAU / n * 2.0 - time * 0.9))
		k = k * k * k
		if k < 0.06:
			continue
		var lit := Color(col.lerp(Color.WHITE, 0.35 * k), k * alpha)
		for p: Vector2 in runes[i]:
			ci.draw_rect(Rect2(p, Vector2.ONE), lit)
	var ring: float = seal.rings[0]
	for m in 3:
		for t in 4:
			var a := time * 0.5 + m * TAU / 3.0 - t * 0.045
			var p := (c + Vector2(cos(a) * ring, sin(a) * ring * squash)).round()
			ci.draw_rect(Rect2(p, Vector2.ONE), Color(col.lerp(Color.WHITE, 0.5), (0.9 - t * 0.22) * alpha))


## Sparks from the fire bowls, and embers blown into the room through a door that has flared.
static func sparks(fx: Fx, scene: Dictionary, rng: RandomNumberGenerator, dt: float, open: Array) -> void:
	var fire: Color = scene.get("fire", Color(1.0, 0.55, 0.18))
	for f: Array in scene.get("flames", _NONE):
		if int(f[1]) != FIRE or rng.randf() > dt * 7.0:
			continue
		var p: Vector2 = f[0]
		fx.spawn(p + Vector2(rng.randf_range(-2.0, 2.0), -4.0), Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-26.0, -12.0)),
			rng.randf_range(0.4, 0.9), 1.0, fire.lerp(Color.WHITE, 0.4), Color(fire.r * 0.8, fire.g * 0.25, fire.b * 0.2), true, 1.0, -8.0)
	var doors: Array = scene.get("doors", _NONE)
	var col: Color = scene.get("door_light", Color(1.0, 0.16, 0.2))
	for i in mini(doors.size(), open.size()):
		var o: float = open[i]
		if o < 0.3 or rng.randf() > dt * 22.0 * o:
			continue
		var r: Rect2 = doors[i]
		var into := Vector2(0, 1)
		match i:
			1: into = Vector2(0, -1)
			2: into = Vector2(1, 0)
			3: into = Vector2(-1, 0)
		var across := Vector2(absf(into.y), absf(into.x))
		var mouth := r.get_center() + into * (r.size * 0.5)
		var half := absf(across.dot(r.size)) * 0.5
		var p := mouth + across * rng.randf_range(-half, half)
		var v := into * rng.randf_range(24.0, 70.0) + across * rng.randf_range(-16.0, 16.0) + Vector2(0, -8)
		fx.spawn(p, v, rng.randf_range(0.5, 1.2), 1.0, col.lerp(Color(1.0, 0.8, 0.5), 0.5), Color(col.r * 0.5, 0.0, col.b * 0.4), true, 1.5, -6.0)
