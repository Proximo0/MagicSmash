class_name Fx
extends Node2D
## Particles and effects. Normal-blended things (smoke, debris, death puffs, floating words) draw on this node;
## glowing ones (sparks, flashes, rings, lightning) draw on an additive child, so overlapping magic blooms
## brighter. Everything but the words and the rings is drawn from the Sprites atlas, so it batches.

const MAX_PARTICLES := 1200
## Floating words stay calm: at most this many at once, none longer than TEXT_LIFE, the same words near each
## other are written once, and only one- or two-letter marks ("!") may be drawn double size.
const MAX_TEXTS := 6
const TEXT_LIFE := 1.2
const TEXT_LIFE_SCALE := 0.8
const TEXT_MERGE := 64.0
const TEXT_RISE := 10.0
## A lightning bolt jumps through this many jagged shapes while it lives.
const BOLT_SHAPES := 3
## Deaths pile up in `_dying` and drain at DEATH_DRAIN a second. Past DEATH_CALM a death is only its puff, so a
## horde dying all at once (a nova) is one soft wave and not a screen of confetti.
const DEATH_CALM := 5.0
const DEATH_DRAIN := 12.0

class P:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 1.0
	var max_life := 1.0
	var size := 2.0
	var size_end := 0.0
	var c0 := Color.WHITE
	var c1 := Color.WHITE
	var drag := 0.0
	var grav := 0.0
	var add := false
	var glow := false

var parts: Array[P] = []
var rings: Array = []    # [pos, r0, r1, life, max, color, width]
var bolts: Array = []    # [shapes (each an Array of PackedVector2Array), life, max, color, nodes]
var texts: Array = []    # [pos, text, color, life, max, scale]
var flashes: Array = []  # [pos, radius, life, max, color]
var anims: Array = []    # sprite effects that play once: [frames (atlas places), pos, vel, life, max, color, additive]
var marks: Array = []    # glowing marks on the floor, drawn by `draw_floor`: [atlas place, pos, life, max, color]
var pillars: Array = []  # columns of light: [pos, life, max, color]
## Where spells were cast since the arena last looked (it raises the caster's arm and flares the staff):
## [pos, caster slot or -1].
var casts: Array = []
## Boxes new words stay out of: the arena keeps one over every wizard, so nobody is hidden behind their own
## "LEVEL UP!". A word that would start inside a box starts above it.
var keep_clear: Array[Rect2] = []
## The calm text rules (see the constants above) apply only when this is set: the arena sets it; the title and
## the sanctum keep their long, large words.
var calm := false
var add_layer: Node2D
var rng := RandomNumberGenerator.new()
var _dying := 0.0

func _ready() -> void:
	add_layer = Node2D.new()
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add_layer.material = m
	add_child(add_layer)
	add_layer.draw.connect(func() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_add()
		PerfMeter.since("fx_draw_add", t0))

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_step(delta)
	PerfMeter.since("fx_process", t0)

func _step(delta: float) -> void:
	for p in parts:
		p.life -= delta
		p.vel *= maxf(0.0, 1.0 - p.drag * delta)
		p.vel.y += p.grav * delta
		p.pos += p.vel * delta
	parts = parts.filter(func(p: P) -> bool: return p.life > 0.0)
	for r in rings:
		r[3] -= delta
	rings = rings.filter(func(r: Array) -> bool: return r[3] > 0.0)
	for b in bolts:
		b[1] -= delta
	bolts = bolts.filter(func(b: Array) -> bool: return b[1] > 0.0)
	for t in texts:
		t[3] -= delta
		t[0].y -= delta * TEXT_RISE * (t[3] / t[4])
	texts = texts.filter(func(t: Array) -> bool: return t[3] > 0.0)
	for f in flashes:
		f[2] -= delta
	flashes = flashes.filter(func(f: Array) -> bool: return f[2] > 0.0)
	for a in anims:
		a[3] -= delta
		a[1] += a[2] * delta
	anims = anims.filter(func(a: Array) -> bool: return a[3] > 0.0)
	for k in marks:
		k[2] -= delta
	marks = marks.filter(func(k: Array) -> bool: return k[2] > 0.0)
	for c in pillars:
		c[1] -= delta
	pillars = pillars.filter(func(c: Array) -> bool: return c[1] > 0.0)
	if casts.size() > 64:
		casts.clear()
	_dying = maxf(0.0, _dying - delta * DEATH_DRAIN)
	queue_redraw()
	add_layer.queue_redraw()

# ---------------------------------------------------------------- spawn --
func spawn(pos: Vector2, vel: Vector2, life: float, size: float, c0: Color, c1: Color,
		add := true, drag := 2.0, grav := 0.0, size_end := 0.0, glow := false) -> void:
	if parts.size() >= MAX_PARTICLES:
		parts.pop_front()
	var p := P.new()
	p.pos = pos
	p.vel = vel
	p.life = life
	p.max_life = life
	p.size = size
	p.size_end = size_end
	p.c0 = c0
	p.c1 = c1
	p.add = add
	p.drag = drag
	p.grav = grav
	p.glow = glow
	parts.append(p)

func burst(pos: Vector2, n: int, speed: float, life: float, size: float, c0: Color,
		c1: Color, add := true, grav := 0.0, glow := false) -> void:
	for i in n:
		var a := rng.randf() * TAU
		var s := speed * rng.randf_range(0.3, 1.0)
		spawn(pos, Vector2(cos(a), sin(a)) * s, life * rng.randf_range(0.6, 1.0), size,
			c0, c1, add, 3.0, grav, 0.0, glow)

func ring(pos: Vector2, r0: float, r1: float, life: float, color: Color, width := 2.0) -> void:
	rings.append([pos, r0, r1, life, life, color, width])

## Lightning through `points`: it keeps BOLT_SHAPES jagged shapes and jumps between them while it lives.
func bolt(points: PackedVector2Array, color: Color, life := 0.14) -> void:
	var shapes: Array = []
	for v in BOLT_SHAPES:
		var lines: Array = []
		for i in points.size() - 1:
			var seg := jag(points[i], points[i + 1], rng, 4.0)
			lines.append(seg)
			# A short fork off the middle of a long stretch.
			if seg.size() > 4 and rng.randf() < 0.6:
				var at := rng.randi_range(1, seg.size() - 2)
				var out := (seg[at + 1] - seg[at - 1]).normalized().rotated(rng.randf_range(0.5, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0))
				lines.append(PackedVector2Array([seg[at], seg[at] + out * rng.randf_range(4.0, 8.0)]))
		shapes.append(lines)
	bolts.append([shapes, life, life, color, points])

## Floating words. Callers ask for a life and a scale; with `calm` set, `text` keeps them calm (see the constants
## above).
func text(pos: Vector2, s: String, color: Color, life := 0.9, scale := 1) -> void:
	if calm:
		life = minf(life * TEXT_LIFE_SCALE, TEXT_LIFE)
		if s.length() > 2:
			scale = 1
		# The same words close by are written once: the one already up starts over.
		for t in texts:
			if t[1] == s and (t[0] as Vector2).distance_squared_to(pos) < TEXT_MERGE * TEXT_MERGE:
				t[3] = maxf(t[3], life)
				t[4] = maxf(t[4], life)
				t[2] = color
				return
	var half := PixelFont.text_width(s, scale) * 0.5
	for box: Rect2 in keep_clear:
		if pos.x + half > box.position.x and pos.x - half < box.end.x and pos.y + PixelFont.H * scale > box.position.y \
				and pos.y < box.end.y:
			pos.y = box.position.y - (PixelFont.H + 1.0) * scale
	# Other words stack above the ones they would land on.
	for i in 4:
		var clash := false
		for t in texts:
			if absf(t[0].x - pos.x) < 30.0 and absf(t[0].y - pos.y) < 8.0 * t[5]:
				clash = true
				break
		if not clash:
			break
		pos.y -= 9.0
	# Past the cap, the words with the least time left make room.
	while calm and texts.size() >= MAX_TEXTS:
		var gone := 0
		for i in texts.size():
			if texts[i][3] < texts[gone][3]:
				gone = i
		texts.remove_at(gone)
	texts.append([pos, s, color, life, life, scale])

func flash(pos: Vector2, radius: float, color: Color, life := 0.12) -> void:
	flashes.append([pos, radius, life, life, color])

## Plays the sprite frames `<prefix>_0` .. `<prefix>_<n - 1>` once at `pos`, tinted `color`.
func anim(prefix: String, n: int, pos: Vector2, life: float, color: Color, add := true, vel := Vector2.ZERO) -> void:
	anims.append([Sprites.strip(prefix, n), pos, vel, life, life, color, add])

## A mark that glows on the floor and fades (the arena draws it under the actors, see `draw_floor`).
func mark(key: String, pos: Vector2, life: float, color: Color) -> void:
	if marks.size() >= 48:
		marks.pop_front()
	marks.append([Sprites.region(key), pos, life, life, color])

# --------------------------------------------------------------- presets --
## A spell hits: a small star of sparks in the caster's colour.
func hit_spark(pos: Vector2, color: Color) -> void:
	anim("fx_spark", 3, pos, 0.13, color.lerp(Color.WHITE, 0.45))
	for i in 2:
		var a := rng.randf() * TAU
		spawn(pos, Vector2(cos(a), sin(a)) * rng.randf_range(40.0, 90.0), rng.randf_range(0.12, 0.22), 1.0, Color.WHITE, color, true, 3.0)

## A spell leaves a staff: remembered for the arena (the caster's pose, the staff's flare), and a blink.
func cast_flash(pos: Vector2, color: Color, slot := -1) -> void:
	casts.append([pos, slot])
	flash(pos, 4.0, color, 0.06)

## A fireball bursts: a flash the size of the blast, a ring, flames, and embers that arc out and fall.
func explosion(pos: Vector2, radius: float) -> void:
	flash(pos, radius * 0.9, Color("ff9a3c"), 0.16)
	flash(pos, radius * 0.5, Color("fff6c0"), 0.1)
	ring(pos, 4.0, radius + 4.0, 0.28, Color("ffcf5a"), 2.0)
	# The blast itself (a white-hot ball that opens into a ring of flame), and five tongues of the fireball's
	# own flame thrown out past it, tumbling as they go.
	anim("fx_blast", 4, pos, 0.26, Color.WHITE)
	for i in 5:
		var a := i * TAU / 5.0 + rng.randf() * 0.8
		var d := Vector2(cos(a), sin(a))
		anim("fx_fire", 4, pos + d * radius * 0.35, rng.randf_range(0.26, 0.4), Color.WHITE, true,
			d * radius * rng.randf_range(1.2, 2.0) + Vector2(0, -10))
	for i in 10:
		var a := rng.randf() * TAU
		spawn(pos, Vector2(cos(a), sin(a)) * rng.randf_range(60.0, 170.0) + Vector2(0, -40), rng.randf_range(0.45, 0.8), 1.0,
			Color("ffcf5a"), Color("c0263a"), true, 1.5, 230.0)
	for i in 4:
		var a := rng.randf() * TAU
		spawn(pos + Vector2(cos(a), sin(a)) * 6.0, Vector2(cos(a), sin(a)) * 26.0 + Vector2(0, -18),
			rng.randf_range(0.6, 1.0), rng.randf_range(3.0, 5.0), Color(0.23, 0.19, 0.31, 0.75),
			Color(0.1, 0.06, 0.14, 0.0), false, 2.0, -15.0, 6.0)

func nova(pos: Vector2, color: Color) -> void:
	flash(pos, 160.0, color.lerp(Color.WHITE, 0.5), 0.25)
	ring(pos, 6.0, 155.0, 0.45, Color.WHITE, 3.0)
	ring(pos, 2.0, 140.0, 0.6, color, 5.0)
	ring(pos, 0.0, 90.0, 0.7, color.darkened(0.2), 2.0)
	for i in 36:
		var a := i * TAU / 36.0 + rng.randf() * 0.1
		var s := rng.randf_range(160.0, 300.0)
		spawn(pos, Vector2(cos(a), sin(a)) * s, rng.randf_range(0.35, 0.7), rng.randf_range(1.0, 2.0),
			Color.WHITE, color, true, 4.0, 0.0, 0.0, true)
	for i in 10:
		var a := rng.randf() * TAU
		spawn(pos, Vector2(cos(a), sin(a)) * rng.randf_range(10, 60) + Vector2(0, -40),
			rng.randf_range(0.8, 1.4), 1.0, color.lightened(0.5), color, true, 1.0, -20.0)

## An enemy dies: a puff in its colour that opens and is gone, a few bits that fall, a wisp or two rising.
func death(pos: Vector2, type: int) -> void:
	var cols := [
		[Color("6fd23c"), Color("2f7a2a")],  # goblin
		[Color("e8dcc0"), Color("7d705c")],  # skeleton
		[Color("32e0c4"), Color("158f86")],  # slime
		[Color("32e0c4"), Color("158f86")],  # mini slime
		[Color("b07bff"), Color("4b3a78")],  # bat
		[Color("b7a98e"), Color("4a4063")],  # orc
		[Color("b07bff"), Color("3a2a5e")],  # mage
		[Color("d8fff6"), Color("3a2a5e")],  # lich
		[Color("d8fff6"), Color("158f86")],  # wraith
		[Color("e8dcc0"), Color("7a1226")],  # cursed tome
		[Color("b7a98e"), Color("4a4063")],  # gargoyle
		[Color("e8dcc0"), Color("2f7a2a")],  # bone priest
	]
	var c: Array = cols[clampi(type, 0, cols.size() - 1)]
	var big := type == 5 or type == 7 or type == 10
	var mid := pos + Vector2(0, -5)
	anim("fx_puff", 5, mid, 0.42 if big else 0.32, Color(c[0], 0.9), false, Vector2(0, -8))
	_dying += 1.0
	if _dying > DEATH_CALM and not big:
		return
	flash(mid, 9.0 if big else 6.0, c[0], 0.08)
	if big:
		anim("fx_puff", 5, mid + Vector2(5, -5), 0.5, (c[0] as Color).lerp(c[1], 0.5), false, Vector2(6, -10))
		ring(pos, 2.0, 18.0, 0.22, c[0], 1.0)
	for i in (9 if big else 4):
		var a := rng.randf_range(-PI, 0.0)
		var s := rng.randf_range(40.0, 110.0)
		spawn(mid, Vector2(cos(a), sin(a)) * s, rng.randf_range(0.35, 0.7), rng.randf_range(1.0, 2.0),
			c[0], c[1], false, 1.5, 260.0, 1.0)
	for i in (6 if big else 2):
		spawn(mid + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)),
			Vector2(rng.randf_range(-12, 12), rng.randf_range(-55, -20)), rng.randf_range(0.4, 0.8),
			1.0, Color.WHITE, c[0], true, 1.0, -10.0)

func teleport(pos: Vector2, color: Color) -> void:
	ring(pos, 14.0, 1.0, 0.3, color, 1.0)
	for i in 10:
		spawn(pos + Vector2(rng.randf_range(-6, 6), rng.randf_range(-2, 10)),
			Vector2(0, rng.randf_range(-90, -30)), rng.randf_range(0.3, 0.6), 1.0,
			Color.WHITE, color, true, 1.0)

## A blink for a pickup, a combo, a shrine: a small star and a few motes (a ring too when `n` is 12 or more).
func sparkle(pos: Vector2, color: Color, n := 10) -> void:
	anim("fx_spark", 3, pos, 0.2, color.lerp(Color.WHITE, 0.4))
	for i in mini(n, 16) / 2:
		var a := rng.randf() * TAU
		spawn(pos, Vector2(cos(a), sin(a)) * rng.randf_range(20, 60), rng.randf_range(0.3, 0.6), 1.0,
			Color.WHITE, color, true, 3.0, -20.0)
	if n >= 12:
		ring(pos, 2.0, 14.0, 0.25, color, 1.0)

## A wizard gains a level: a column of light in their colour, a ring on the floor, a star over the hat. Returns
## the column (an entry of `pillars`), so the caller can keep its place [0] on the wizard while it lasts.
func level_up(pos: Vector2, color: Color) -> Array:
	var pillar: Array = [pos, 0.6, 0.6, color]
	pillars.append(pillar)
	flash(pos + Vector2(0, -6), 16.0, color, 0.22)
	ring(pos, 2.0, 24.0, 0.45, color, 2.0)
	anim("fx_burst", 4, pos + Vector2(0, -26), 0.35, color.lerp(Color.WHITE, 0.5))
	for i in 12:
		spawn(pos + Vector2(rng.randf_range(-8, 8), rng.randf_range(-3, 2)), Vector2(0, rng.randf_range(-80, -30)),
			rng.randf_range(0.4, 0.8), 1.0, Color.WHITE, color, true, 1.0)
	return pillar

## A falling star lands: a starburst, and a mark that glows on the floor for a moment.
func star_land(pos: Vector2, color: Color, big: bool) -> void:
	anim("fx_burst", 4, pos, 0.34 if big else 0.26, color.lerp(Color.WHITE, 0.35))
	flash(pos, 11.0 if big else 7.0, color, 0.12)
	mark("fx_mark", pos + Vector2(0, 2), 1.1 if big else 0.8, Color.WHITE)
	for i in (6 if big else 3):
		var a := rng.randf() * TAU
		spawn(pos, Vector2(cos(a), sin(a)) * rng.randf_range(25.0, 70.0), rng.randf_range(0.25, 0.5), 1.0, Color.WHITE, color,
			true, 3.0, 40.0)

## Lightning between points with random midpoint jitter.
static func jag(a: Vector2, b: Vector2, rng: RandomNumberGenerator, amp := 5.0) -> PackedVector2Array:
	var out := PackedVector2Array([a])
	var n := maxi(2, int(a.distance_to(b) / 7.0))
	var perp := (b - a).normalized().orthogonal()
	for i in range(1, n):
		var t := float(i) / n
		out.append(a.lerp(b, t) + perp * rng.randf_range(-amp, amp))
	out.append(b)
	return out

# ------------------------------------------------------------------ draw --
func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_main()
	PerfMeter.since("fx_draw", t0)

func _draw_main() -> void:
	for p in parts:
		if p.add:
			continue
		_draw_p(self, p)
	_draw_anims(self, false)
	for t in texts:
		var k: float = t[3] / t[4]
		var col: Color = t[2]
		if k < 0.3:
			col.a = k / 0.3
		PixelFont.draw_centered(self, t[1], t[0].x, t[0].y, t[5], col, Color(0.05, 0.02, 0.1, col.a))

func _draw_p(ci: CanvasItem, p: P) -> void:
	var k := p.life / p.max_life
	var col := p.c1.lerp(p.c0, k)
	var s := lerpf(p.size_end, p.size, k)
	if s < 0.5:
		return
	var side := ceilf(s)
	var at := (p.pos - Vector2(s, s) * 0.5).floor()
	if p.glow:
		var g := col
		g.a *= 0.25
		Sprites.rect(ci, Rect2(at - Vector2(1, 1), Vector2(side + 2.0, side + 2.0)), g)
	Sprites.rect(ci, Rect2(at, Vector2(side, side)), col)

func _draw_anims(ci: CanvasItem, add: bool) -> void:
	for a in anims:
		if a[6] != add:
			continue
		var frames: Array = a[0]
		var k: float = 1.0 - a[3] / a[4]
		var col: Color = a[5]
		if k > 0.75:
			col.a *= (1.0 - k) * 4.0
		Sprites.draw_mid_r(ci, frames[mini(int(k * frames.size()), frames.size() - 1)], a[1], col)

## The marks on the floor. The arena calls this from its additive floor layer, under the actors.
func draw_floor(ci: CanvasItem) -> void:
	for k in marks:
		var c: Color = k[4]
		c.a *= minf(1.0, float(k[2]) / (float(k[3]) * 0.6))
		Sprites.draw_mid_r(ci, k[0], k[1], c)

func _draw_add() -> void:
	var ci := add_layer
	for f in flashes:
		var k: float = f[2] / f[3]
		var c: Color = f[4]
		c.a = 0.85 * k
		var r: float = f[1]
		if r > 44.0:
			# The few screen-wide flashes (a nova) are wider than the biggest glow sprite. They stay thin: the
			# wizards and the horde must show through, the rings carry the blast.
			c.a = 0.22 * k
			ci.draw_circle(f[0], r * (1.2 - 0.2 * k), c)
			c.a = 0.3 * k
			ci.draw_circle(f[0], r * 0.45, c)
		else:
			Sprites.glow(ci, f[0], r, c)
	for c in pillars:
		var k: float = c[1] / c[2]
		var at: Vector2 = (c[0] as Vector2).floor()
		var col: Color = c[3]
		var tall := 54.0 * (1.0 - k * 0.4)
		Sprites.rect(ci, Rect2(at.x - 5, at.y - tall, 11, tall), Color(col, 0.16 * k))
		Sprites.rect(ci, Rect2(at.x - 3, at.y - tall - 3, 7, tall + 3), Color(col, 0.3 * k))
		Sprites.rect(ci, Rect2(at.x - 1, at.y - tall - 6, 3, tall + 6), Color(1, 1, 1, 0.75 * k))
	for p in parts:
		if p.add:
			_draw_p(ci, p)
	_draw_anims(ci, true)
	for b in bolts:
		var k: float = b[1] / b[2]
		var shapes: Array = b[0]
		var lines: Array = shapes[mini(int((1.0 - k) * shapes.size()), shapes.size() - 1)]
		var fringe: Color = b[3]
		fringe.a = 0.4 * k
		var core := Color(1, 1, 1, minf(1.0, 0.4 + k))
		for seg: PackedVector2Array in lines:
			for i in seg.size() - 1:
				Sprites.line(ci, seg[i], seg[i + 1], fringe, 1)
		for seg: PackedVector2Array in lines:
			for i in seg.size() - 1:
				Sprites.line(ci, seg[i], seg[i + 1], core)
		var nodes: PackedVector2Array = b[4]
		var node_c: Color = b[3]
		node_c.a = 0.7 * k
		for i in range(1, nodes.size()):
			Sprites.glow(ci, nodes[i], 5.0, node_c)
			Sprites.draw_mid(ci, "fx_core_1", nodes[i], core)
	for r in rings:
		var k: float = 1.0 - r[3] / r[4]
		var rad: float = lerpf(r[1], r[2], 1.0 - pow(1.0 - k, 2.0))
		var c: Color = r[5]
		c.a = 1.0 - k
		if rad > 0.5:
			ci.draw_arc(r[0], rad, 0, TAU, maxi(12, int(rad)), c, r[6])
