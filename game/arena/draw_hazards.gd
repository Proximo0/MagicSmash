class_name ArenaDrawHazards
extends RefCounted
## Arena: hazard rows (Hazards) on the floor layer. A bone-white dashed rim shows the whole area from the first
## frame; a red fill grows to it while the warning runs and burns full while hot. SAFE rows are gold. Three draw
## calls for every row together: one triangle batch for the fills, one dashed multiline per rim colour.

const RIM := Color("e8dcc0")
const FILL := Color("c0263a")
const GOLD := Color("ffd94d")
const SEGMENTS := 24 # around a disc; every other one is a dash
const DASH := 4.0 # px of a line row's dash


static func draw(a: Arena, ci: CanvasItem) -> void:
	var hz: PackedFloat32Array = a.vhz
	if hz.is_empty():
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rim := PackedVector2Array()
	var gold := PackedVector2Array()
	var i := 0
	while i + Hazards.FLOATS <= hz.size():
		var kind := int(hz[i + 1])
		var at := Vector2(hz[i + 2], hz[i + 3])
		var to := Vector2(hz[i + 4], hz[i + 5])
		var r: float = hz[i + 6]
		var warn: float = hz[i + 7]
		var warn0: float = maxf(hz[i + 8], 0.001)
		var safe := kind == Hazards.SAFE
		var k := 1.0 - clampf(warn / warn0, 0.0, 1.0)
		var hot := warn <= 0.0
		var base := GOLD if safe else FILL
		var alpha := (0.5 + 0.15 * sin(a.time * 14.0)) if hot else 0.18 + 0.27 * k
		var col := Color(base, alpha)
		var dashes := gold if safe else rim
		if int(Hazards.KINDS[kind][Hazards.K_SHAPE]) == Hazards.DISC:
			_fan(pts, cols, idx, at, maxf(r * k, 1.0), col)
			for s: int in range(0, SEGMENTS, 2):
				dashes.append(at + Vector2.from_angle(TAU * s / SEGMENTS) * r)
				dashes.append(at + Vector2.from_angle(TAU * (s + 1) / SEGMENTS) * r)
		else:
			var along := (to - at).normalized() if to != at else Vector2.RIGHT
			var side := along.orthogonal()
			_quad(pts, cols, idx, at, to, side * maxf(r * k, 0.5), col)
			for edge: Vector2 in [side * r, -side * r]:
				var len := at.distance_to(to)
				var d := 0.0
				while d < len:
					dashes.append(at + along * d + edge)
					dashes.append(at + along * minf(d + DASH, len) + edge)
					d += DASH * 2.0
			for end: Vector2 in [at, to]:
				dashes.append(end + side * r)
				dashes.append(end - side * r)
		i += Hazards.FLOATS
	if not idx.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)
	if not rim.is_empty():
		ci.draw_multiline(rim, RIM, 1.0)
	if not gold.is_empty():
		ci.draw_multiline(gold, GOLD, 1.0)


static func _fan(pts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, c: Vector2, r: float, col: Color) -> void:
	var o := pts.size()
	pts.append(c)
	cols.append(col)
	for s: int in range(SEGMENTS):
		pts.append(c + Vector2.from_angle(TAU * s / SEGMENTS) * r)
		cols.append(col)
	for s: int in range(SEGMENTS):
		idx.append_array([o, o + 1 + s, o + 1 + (s + 1) % SEGMENTS])


static func _quad(pts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array, a: Vector2, b: Vector2, half: Vector2, col: Color) -> void:
	var o := pts.size()
	pts.append_array([a + half, b + half, b - half, a - half])
	for _n: int in range(4):
		cols.append(col)
	idx.append_array([o, o + 1, o + 2, o, o + 2, o + 3])
