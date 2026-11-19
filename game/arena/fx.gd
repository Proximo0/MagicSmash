class_name Fx
extends Node2D
## Particle and effect system. Normal-blended particles (smoke, debris,
## text) draw on this node; glowing particles, rings and lightning draw on
## an additive child so overlapping magic blooms brighter.

const MAX_PARTICLES := 1600

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
var bolts: Array = []    # [points, life, max, color]
var texts: Array = []    # [pos, text, color, life, max, scale]
var flashes: Array = []  # [pos, radius, life, max, color]
var add_layer: Node2D
var rng := RandomNumberGenerator.new()

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
	parts = parts.filter(func(p): return p.life > 0.0)
	for r in rings:
		r[3] -= delta
	rings = rings.filter(func(r): return r[3] > 0.0)
	for b in bolts:
		b[1] -= delta
	bolts = bolts.filter(func(b): return b[1] > 0.0)
	for t in texts:
		t[3] -= delta
		t[0].y -= delta * 14.0 * (t[3] / t[4])
	texts = texts.filter(func(t): return t[3] > 0.0)
	for f in flashes:
		f[2] -= delta
	flashes = flashes.filter(func(f): return f[2] > 0.0)
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

func bolt(points: PackedVector2Array, color: Color, life := 0.14) -> void:
	bolts.append([points, life, life, color])

func text(pos: Vector2, s: String, color: Color, life := 0.9, scale := 1) -> void:
	# Stack popups that would land on top of each other.
	for i in 4:
		var clash := false
		for t in texts:
			if absf(t[0].x - pos.x) < 30.0 and absf(t[0].y - pos.y) < 8.0 * t[5]:
				clash = true
				break
		if not clash:
			break
		pos.y -= 9.0
	texts.append([pos, s, color, life, life, scale])

func flash(pos: Vector2, radius: float, color: Color, life := 0.12) -> void:
	flashes.append([pos, radius, life, life, color])

# --------------------------------------------------------------- presets --
func hit_spark(pos: Vector2, color: Color) -> void:
	burst(pos, 5, 90.0, 0.22, 1.0, Color.WHITE, color, true)
	flash(pos, 5.0, color, 0.06)

func cast_flash(pos: Vector2, color: Color) -> void:
	flash(pos, 4.0, color, 0.05)
	burst(pos, 2, 40.0, 0.15, 1.0, Color.WHITE, color, true)

func explosion(pos: Vector2, radius: float) -> void:
	flash(pos, radius * 0.9, Color(1.0, 0.7, 0.3), 0.12)
	ring(pos, 4.0, radius + 6.0, 0.3, Color(1.0, 0.6, 0.2), 2.0)
	for i in 26:
		var a := rng.randf() * TAU
		var s := rng.randf_range(20.0, 130.0)
		spawn(pos, Vector2(cos(a), sin(a)) * s, rng.randf_range(0.25, 0.55), rng.randf_range(2.0, 4.0),
			Color(1.0, 0.95, 0.5), Color(0.9, 0.15, 0.05), true, 5.0, -30.0, 0.0, true)
	for i in 10:
		var a := rng.randf() * TAU
		spawn(pos + Vector2(cos(a), sin(a)) * 6.0, Vector2(cos(a), sin(a)) * 30.0 + Vector2(0, -20),
			rng.randf_range(0.6, 1.1), rng.randf_range(3.0, 5.0), Color(0.3, 0.25, 0.3, 0.8),
			Color(0.1, 0.08, 0.12, 0.0), false, 2.0, -15.0, 6.0)
	for i in 8:
		var a := rng.randf() * TAU
		spawn(pos, Vector2(cos(a), sin(a)) * rng.randf_range(60, 160), 0.5, 1.0,
			Color(1, 1, 0.8), Color(1, 0.5, 0.1), true, 1.5, 180.0)

func nova(pos: Vector2, color: Color) -> void:
	flash(pos, 160.0, color.lerp(Color.WHITE, 0.5), 0.25)
	ring(pos, 6.0, 155.0, 0.45, Color.WHITE, 3.0)
	ring(pos, 2.0, 140.0, 0.6, color, 5.0)
	ring(pos, 0.0, 90.0, 0.7, color.darkened(0.2), 2.0)
	for i in 90:
		var a := i * TAU / 90.0 + rng.randf() * 0.05
		var s := rng.randf_range(160.0, 300.0)
		spawn(pos, Vector2(cos(a), sin(a)) * s, rng.randf_range(0.35, 0.7), rng.randf_range(1.0, 3.0),
			Color.WHITE, color, true, 4.0, 0.0, 0.0, true)
	for i in 30:
		var a := rng.randf() * TAU
		spawn(pos, Vector2(cos(a), sin(a)) * rng.randf_range(10, 60) + Vector2(0, -40),
			rng.randf_range(0.8, 1.4), 1.0, color.lightened(0.5), color, true, 1.0, -20.0)

func death(pos: Vector2, type: int) -> void:
	var cols := [
		[Color("8bff4d"), Color("2f7a2a")],  # goblin
		[Color("fff6e0"), Color("b7a98e")],  # skeleton
		[Color("7dfff0"), Color("158f86")],  # slime
		[Color("7dfff0"), Color("158f86")],  # mini slime
		[Color("e07bff"), Color("5a1a8a")],  # bat
		[Color("c8e070"), Color("4d5166")],  # orc
		[Color("ff4df2"), Color("3b1f6e")],  # mage
		[Color("4dfff0"), Color("4a1a7a")],  # lich
		[Color("d8fff6"), Color("4f9a94")],  # wraith
		[Color("efe2c0"), Color("8a1f2c")],  # cursed tome
		[Color("c8c4d8"), Color("57546a")],  # gargoyle
		[Color("6dff9a"), Color("2e1a12")],  # bone priest
	]
	var c: Array = cols[clampi(type, 0, cols.size() - 1)]
	var big := type == 5 or type == 7 or type == 10
	flash(pos, 14.0 if big else 9.0, c[0], 0.1)
	ring(pos, 2.0, 18.0 if big else 12.0, 0.22, c[0], 1.0)
	# Chunky gibs that fall with gravity (normal blend)
	for i in (16 if big else 9):
		var a := rng.randf_range(-PI, 0.0)
		var s := rng.randf_range(40.0, 120.0)
		spawn(pos, Vector2(cos(a), sin(a)) * s, rng.randf_range(0.4, 0.8), rng.randf_range(1.0, 2.5),
			c[0], c[1], false, 1.5, 260.0, 1.0)
	# Magic soul sparkles rising (additive)
	for i in (14 if big else 7):
		spawn(pos + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)),
			Vector2(rng.randf_range(-20, 20), rng.randf_range(-60, -20)), rng.randf_range(0.4, 0.9),
			1.0, Color.WHITE, c[0], true, 1.0, -10.0)

func teleport(pos: Vector2, color: Color) -> void:
	ring(pos, 14.0, 1.0, 0.3, color, 1.0)
	for i in 18:
		spawn(pos + Vector2(rng.randf_range(-6, 6), rng.randf_range(-2, 10)),
			Vector2(0, rng.randf_range(-90, -30)), rng.randf_range(0.3, 0.6), 1.0,
			Color.WHITE, color, true, 1.0)

func sparkle(pos: Vector2, color: Color, n := 10) -> void:
	for i in n:
		var a := rng.randf() * TAU
		spawn(pos, Vector2(cos(a), sin(a)) * rng.randf_range(20, 70), rng.randf_range(0.3, 0.7), 1.0,
			Color.WHITE, color, true, 3.0, -20.0)
	ring(pos, 2.0, 14.0, 0.25, color, 1.0)

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
	for t in texts:
		var k: float = t[3] / t[4]
		var col: Color = t[2]
		if k < 0.3:
			col.a = k / 0.3
		var blink := k > 0.85 and int(t[3] * 30.0) % 2 == 0
		PixelFont.draw_centered(self, t[1], t[0].x, t[0].y, t[5], Color.WHITE if blink else col,
			Color(0.05, 0.02, 0.1, col.a))

func _draw_p(ci: CanvasItem, p: P) -> void:
	var k := p.life / p.max_life
	var col := p.c1.lerp(p.c0, k)
	var s := lerpf(p.size_end, p.size, k)
	if s < 0.5:
		return
	if p.glow:
		var g := col
		g.a *= 0.25
		ci.draw_rect(Rect2(p.pos - Vector2(s, s), Vector2(s * 2.0, s * 2.0)), g)
	ci.draw_rect(Rect2((p.pos - Vector2(s, s) * 0.5).floor(), Vector2(ceilf(s), ceilf(s))), col)

func _draw_add() -> void:
	var ci := add_layer
	for f in flashes:
		var k: float = f[2] / f[3]
		var c: Color = f[4]
		c.a = 0.55 * k
		ci.draw_circle(f[0], f[1] * (1.2 - 0.2 * k), c)
		c.a = 0.8 * k
		ci.draw_circle(f[0], f[1] * 0.45, c)
	for p in parts:
		if p.add:
			_draw_p(ci, p)
	for r in rings:
		var k: float = 1.0 - r[3] / r[4]
		var rad: float = lerpf(r[1], r[2], 1.0 - pow(1.0 - k, 2.0))
		var c: Color = r[5]
		c.a = 1.0 - k
		if rad > 0.5:
			ci.draw_arc(r[0], rad, 0, TAU, maxi(12, int(rad)), c, r[6])
	for b in bolts:
		var pts: PackedVector2Array = b[0]
		var c: Color = b[3]
		var k: float = b[1] / b[2]
		for i in pts.size() - 1:
			var seg := jag(pts[i], pts[i + 1], rng, 4.0)
			var glow := c
			glow.a = 0.35 * k
			ci.draw_polyline(seg, glow, 4.0)
			var core := c.lerp(Color.WHITE, 0.6)
			core.a = k
			ci.draw_polyline(seg, core, 1.0)
		for pt in pts:
			var g := c
			g.a = 0.5 * k
			ci.draw_circle(pt, 4.0, g)
