class_name FieldFx
extends Node2D
## Skills and effects drawn for every class, from the effect and event rows of RealmLink's frame (field px).
## Two instances share this script: `under_figures` draws what lies on the ground (zones, drop circles, the
## raise ring), the other draws what flies and flashes over the figures (swings, rings, bolts, dashes,
## monster shots, statuses, bursts, floating words).
## Rows come once a tick (20 a second); a swing or a bolt lasts one tick in the core, so it is drawn for a
## little longer here (LIFE_S) and fades. Zones, drops, shots and statuses are state: drawn from the newest rows.

const FX_SWING: int = 1
const FX_RING: int = 2
const FX_BOLT: int = 3
const FX_DROP: int = 4
const FX_ZONE: int = 5
const FX_DASH: int = 6
const FX_SHOT: int = 7
const FX_STATUS: int = 8
const FX_RAISE: int = 9
const STRIDE: int = 8
const EV_STRIDE: int = 8
## Event ranks (the contract's order).
const EV_LEVEL: int = 0
const EV_DRAW: int = 1
const EV_PICK: int = 2
const EV_SKILL: int = 3
const EV_POTION: int = 4
const EV_DOWN: int = 5
const EV_RAISE: int = 6
const EV_FALLEN: int = 7
const EV_BANK: int = 8
const EV_LEAVE: int = 9
const EV_KILL: int = 10
const EV_XP: int = 11
## How long a one-tick swing, ring or bolt stays on screen (s).
const LIFE_S: float = 0.22
const TEXT_LIFE_S: float = 1.1
## Rows taken from one frame, transient effects alive at once and particles alive at once.
const MAX_ROWS: int = 500
const MAX_ITEMS: int = 900
const MAX_BURSTS_PER_FRAME: int = 60
const ELITE: int = 1
const CHAMPION: int = 2
## A hero stands within this many px of a downed ally to raise her.
const RAISE_PX: float = 40.0
# Look of the area telegraphs: thin crisp outlines, faint fills (never above FILL_ALPHA_MAX). Tune here.
const FILL_ALPHA: float = 0.08        # zone and lobbed-circle fills, under the figures
const FILL_ALPHA_MAX: float = 0.12    # a drop circle's fill when it lands
const OVER_FILL_ALPHA: float = 0.05   # fills of effects drawn over the figures (swings, rings, bursts)
const EDGE_ALPHA: float = 0.65        # the outline of every area
const EDGE_ALPHA_SOFT: float = 0.35   # inner, secondary arcs

## Class colours: novice, knight, mage, archer, priest, paladin.
const CLASS_COL: Array[Color] = [
	Color(0.8, 0.8, 0.8), Color(0.85, 0.9, 1.0), Color(1.0, 0.55, 0.15),
	Color(0.65, 0.95, 0.4), Color(1.0, 0.95, 0.6), Color(0.75, 0.88, 1.0)]
## Zone rows: tumble, consecrate, rampart, hail, pyre.
const ZONE_COL: Array[Color] = [
	Color(0.4, 0.85, 0.8), Color(1.0, 0.92, 0.5), Color(0.45, 0.6, 1.0), Color(0.8, 0.92, 1.0), Color(1.0, 0.45, 0.15)]
## Hero effect rows (the core's FX_ order): provoke, aegis, rampart, blood rage, benediction, martyr, crusade,
## deadeye, raised, veil, whetstone, ink, gambler, knight of wands, shield, dash.
const STATUS_COL: Array[Color] = [
	Color(0.95, 0.3, 0.25), Color(0.75, 0.9, 1.0), Color(0.45, 0.6, 1.0), Color(0.75, 0.1, 0.15),
	Color(1.0, 0.9, 0.4), Color(1.0, 0.97, 0.8), Color(1.0, 0.8, 0.2), Color(0.5, 1.0, 0.45),
	Color(0.6, 1.0, 0.7), Color(0.7, 0.7, 0.8), Color(1.0, 0.6, 0.2), Color(0.5, 0.6, 1.0),
	Color(0.5, 0.9, 0.4), Color(0.9, 0.9, 0.5), Color(0.85, 0.95, 1.0), Color(1, 1, 1, 0)]
const ACT_COL: Dictionary = {
	"heal": Color(0.5, 1.0, 0.55), "self": Color(1.0, 0.6, 0.3), "group": Color(1.0, 0.9, 0.45),
	"groupheal": Color(1.0, 1.0, 0.75), "ring": Color(1.0, 0.7, 0.35), "curse": Color(0.7, 0.4, 0.95),
	"volley": Color(0.65, 0.95, 0.4), "dash": Color(0.8, 0.9, 1.0), "zone": Color(1.0, 0.9, 0.5), "drop": Color(1.0, 0.5, 0.2)}

var under_figures: bool = false
## Screen px per field px (the width of a one-pixel line is its inverse).
var px_scale: float = 1.0
## The newest effect rows (state: zones, drops, shots, statuses, raising).
var rows: PackedFloat32Array = PackedFloat32Array()
var frame_time: float = 0.0
var my_id: int = -1
## Effects alive, by kind, and their count for the HUD.
var drawn_items: int = 0
var _items: Array[Dictionary] = []
## Circles already filled this draw (x, y, radius): fills that overlap most of one are skipped so alpha never piles up.
var _filled: PackedVector3Array = PackedVector3Array()
var _skill_col: Dictionary = {}


func ingest(new_rows: PackedFloat32Array) -> void:
	var now: float = Time.get_ticks_usec() / 1000000.0
	rows = new_rows
	frame_time = now
	if under_figures:
		return
	var n: int = mini(new_rows.size() / STRIDE, MAX_ROWS * 4)
	var taken: int = 0
	for i in n:
		var o: int = i * STRIDE
		var t: int = int(new_rows[o])
		if t != FX_SWING and t != FX_RING and t != FX_BOLT and t != FX_DASH:
			continue
		taken += 1
		if taken > MAX_ROWS:
			break
		_add({"k": t, "x": new_rows[o + 1], "y": new_rows[o + 2], "a": new_rows[o + 3], "b": new_rows[o + 4],
			"c": new_rows[o + 5], "d": new_rows[o + 6], "t": now, "life": LIFE_S})


## Event rows into bursts and floating words (the sound hooks read the same rows).
func events(ev: PackedInt32Array) -> void:
	if under_figures:
		return
	var now: float = Time.get_ticks_usec() / 1000000.0
	var bursts: int = 0
	for i in ev.size() / EV_STRIDE:
		var o: int = i * EV_STRIDE
		var rank: int = ev[o]
		var p := Vector2(ev[o + 5], ev[o + 6])
		var mine: bool = ev[o + 1] == my_id
		match rank:
			EV_KILL:
				bursts += 1
				if bursts <= MAX_BURSTS_PER_FRAME:
					var flags: int = ev[o + 4]
					var n: int = 9 if flags & (ELITE | CHAMPION) else 4
					var col: Color = Color(0.85, 0.45, 1.0) if flags & CHAMPION else (Color(1.0, 0.82, 0.3) if flags & ELITE else Color(0.9, 0.35, 0.3))
					_add({"k": 20, "x": p.x, "y": p.y, "a": n, "b": float(ev[o + 2]), "c": col.to_html(false), "t": now, "life": 0.45})
			EV_LEVEL:
				if mine:
					_add({"k": 21, "x": p.x, "y": p.y, "a": 0.0, "b": 0.0, "c": "LEVEL %d" % ev[o + 2], "d": Color(1.0, 0.95, 0.5), "t": now, "life": TEXT_LIFE_S * 1.5})
				_add({"k": FX_RING, "x": p.x, "y": p.y, "a": 60.0, "b": -2.0, "c": 0.0, "d": 0.0, "t": now, "life": 0.5})
			EV_DOWN:
				_add({"k": 21, "x": p.x, "y": p.y - 14.0, "a": 0.0, "b": 0.0, "c": "DOWN", "d": Color(1.0, 0.35, 0.3), "t": now, "life": TEXT_LIFE_S})
			EV_RAISE:
				_add({"k": 21, "x": p.x, "y": p.y - 14.0, "a": 0.0, "b": 0.0, "c": "RAISED", "d": Color(0.6, 1.0, 0.7), "t": now, "life": TEXT_LIFE_S})
				_add({"k": FX_RING, "x": p.x, "y": p.y, "a": RAISE_PX * 1.5, "b": -3.0, "c": 0.0, "d": 0.0, "t": now, "life": 0.5})
			EV_FALLEN:
				_add({"k": 21, "x": p.x, "y": p.y - 14.0, "a": 0.0, "b": 0.0, "c": "FALLEN -%d" % ev[o + 2], "d": Color(0.75, 0.75, 0.8), "t": now, "life": TEXT_LIFE_S * 1.5})
			EV_BANK:
				if mine:
					_add({"k": 21, "x": p.x, "y": p.y - 16.0, "a": 0.0, "b": 0.0, "c": "BANKED %d" % ev[o + 2], "d": Color(1.0, 0.85, 0.3), "t": now, "life": TEXT_LIFE_S * 1.5})
					_add({"k": FX_RING, "x": p.x, "y": p.y, "a": 48.0, "b": -4.0, "c": 0.0, "d": 0.0, "t": now, "life": 0.6})
			EV_POTION:
				if mine:
					_add({"k": 21, "x": p.x, "y": p.y - 14.0, "a": 0.0, "b": 0.0, "c": RealmLink.potion_name(ev[o + 4]), "d": Color(0.9, 0.95, 1.0), "t": now, "life": TEXT_LIFE_S})


func _add(d: Dictionary) -> void:
	if _items.size() >= MAX_ITEMS:
		_items.pop_front()
	_items.append(d)


func _col_of_skill(id: int) -> Color:
	if id < 0:
		return Color(1.0, 0.95, 0.7)
	if not _skill_col.has(id):
		var act: String = String(RealmLink.skill_info(id).get("act", "ring"))
		_skill_col[id] = ACT_COL.get(act, Color(1, 1, 1))
	return _skill_col[id]


## Floating words in Jersey10 with as many screen px a design px as the HUD's at every zoom: the zoom's whole
## multiple of its crisp size (UiKit.crisp), so no zoom smears it.
func _fk() -> int:
	return clampi(roundi(get_viewport().get_final_transform().x.x / px_scale), 1, 8)


func _fs() -> int:
	return UiKit.crisp("jersey10", _fk())


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var now: float = Time.get_ticks_usec() / 1000000.0
	var w: float = 1.0 / px_scale
	var wall: float = float(Time.get_ticks_msec()) / 1000.0
	_filled.clear()
	if under_figures:
		_draw_ground(wall, w)
		return
	_draw_state(wall, w)
	# Transient effects: drop those past their life, draw the rest.
	var keep: Array[Dictionary] = []
	for it in _items:
		var age: float = now - float(it["t"])
		if age > float(it["life"]):
			continue
		keep.append(it)
		_draw_item(it, age / float(it["life"]), w)
	_items = keep
	drawn_items = _items.size()


## Fills a telegraph circle unless one of about the same place and size was filled this draw: ten shots at one spot
## must not add up to a solid disc.
func _fill_once(p: Vector2, r: float, col: Color) -> void:
	for f in _filled:
		if Vector2(f.x, f.y).distance_to(p) < 0.5 * maxf(r, f.z):
			return
	_filled.append(Vector3(p.x, p.y, r))
	draw_circle(p, r, col)


func _draw_ground(wall: float, w: float) -> void:
	for i in rows.size() / STRIDE:
		var o: int = i * STRIDE
		var t: int = int(rows[o])
		var p := Vector2(rows[o + 1], rows[o + 2])
		match t:
			FX_ZONE:
				var r: float = rows[o + 3]
				var col: Color = ZONE_COL[clampi(int(rows[o + 4]), 0, ZONE_COL.size() - 1)]
				var left: float = rows[o + 5]
				var fade: float = clampf(left / 20.0, 0.0, 1.0)
				_fill_once(p, r, Color(col.r, col.g, col.b, FILL_ALPHA * fade))
				draw_arc(p, r, wall * 0.6, wall * 0.6 + TAU, 40, Color(col.r, col.g, col.b, EDGE_ALPHA * fade), 1.5 * w, true)
				draw_arc(p, r * 0.6, -wall * 0.9, -wall * 0.9 + TAU * 0.75, 28, Color(col.r, col.g, col.b, EDGE_ALPHA_SOFT * fade), 1.0 * w, true)
			FX_DROP:
				var r2: float = rows[o + 3]
				var left2: float = rows[o + 4]
				var k: float = clampf(1.0 - left2 / 30.0, 0.0, 1.0)
				_fill_once(p, r2, Color(1.0, 0.35, 0.1, lerpf(0.05, FILL_ALPHA_MAX, k)))
				draw_arc(p, r2, 0.0, TAU, 36, Color(1.0, 0.6, 0.25, EDGE_ALPHA), 1.5 * w, true)
				draw_arc(p, r2 * k, 0.0, TAU, 28, Color(1.0, 0.85, 0.5, EDGE_ALPHA), 1.0 * w, true)
			FX_RAISE:
				var prog: float = rows[o + 3]
				draw_arc(p, RAISE_PX, 0.0, TAU, 28, Color(0.5, 1.0, 0.65, 0.25), 1.0 * w, true)
				if prog > 0.0:
					draw_arc(p, RAISE_PX, -PI / 2.0, -PI / 2.0 + TAU * prog, 28, Color(0.5, 1.0, 0.65, 0.95), 2.0 * w, true)
				_word(p + Vector2(0, -20), "%ds" % ceili(rows[o + 4]), Color(1.0, 0.5, 0.45))


func _draw_state(wall: float, w: float) -> void:
	for i in rows.size() / STRIDE:
		var o: int = i * STRIDE
		var t: int = int(rows[o])
		var p := Vector2(rows[o + 1], rows[o + 2])
		if t == FX_SHOT:
			var r: float = rows[o + 3]
			if r > 0.0:
				# A lobbed circle: landing soon.
				draw_arc(p, r, 0.0, TAU, 28, Color(0.95, 0.4, 0.3, EDGE_ALPHA), 1.5 * w, true)
				_fill_once(p, r, Color(0.95, 0.3, 0.2, FILL_ALPHA))
			else:
				var v := Vector2(rows[o + 5], rows[o + 6])
				draw_line(p - v * 2.5, p, Color(0.8, 0.5, 1.0, 0.55), 2.0 * w)
				draw_circle(p, 2.2, Color(0.9, 0.7, 1.0))
		elif t == FX_STATUS:
			var mask: int = int(rows[o + 3])
			var k: int = 0
			for b in STATUS_COL.size():
				if mask & (1 << b) and STATUS_COL[b].a > 0.0:
					var col: Color = STATUS_COL[b]
					var rad: float = 11.0 + 2.5 * k
					draw_arc(p + Vector2(0, -6), rad, wall * 1.5 + b, wall * 1.5 + b + TAU * 0.8, 24, Color(col.r, col.g, col.b, 0.85), 1.3 * w, true)
					k += 1


func _draw_item(it: Dictionary, f: float, w: float) -> void:
	var p := Vector2(it["x"], it["y"])
	var k: int = int(it["k"])
	var fade: float = 1.0 - f
	match k:
		FX_SWING:
			var cls: int = clampi(int(float(it["d"])), 0, CLASS_COL.size() - 1)
			var col: Color = CLASS_COL[cls]
			var ang: float = float(it["a"])
			var half: float = deg_to_rad(float(it["b"])) / 2.0
			var r: float = float(it["c"])
			var pts := PackedVector2Array([p])
			for s in 11:
				var a: float = ang - half + 2.0 * half * s / 10.0
				pts.append(p + Vector2(cos(a), sin(a)) * r * (0.55 + 0.45 * minf(f * 3.0, 1.0)))
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, OVER_FILL_ALPHA * fade))
			draw_arc(p, r * (0.55 + 0.45 * minf(f * 3.0, 1.0)), ang - half, ang + half, 14, Color(col.r, col.g, col.b, EDGE_ALPHA * fade), 2.0 * w, true)
		FX_RING:
			var sk: int = int(float(it["b"]))
			var rr: float = float(it["a"]) * (0.25 + 0.75 * minf(f * 2.5, 1.0))
			var c2: Color
			if sk == -2:
				c2 = Color(1.0, 0.95, 0.5)
			elif sk == -3:
				c2 = Color(0.5, 1.0, 0.65)
			elif sk == -4:
				c2 = Color(1.0, 0.85, 0.3)
			elif sk == -1:
				c2 = CLASS_COL[clampi(int(float(it["c"])), 0, CLASS_COL.size() - 1)]
			else:
				c2 = _col_of_skill(sk)
			draw_circle(p, rr, Color(c2.r, c2.g, c2.b, OVER_FILL_ALPHA * fade))
			draw_arc(p, rr, 0.0, TAU, 36, Color(c2.r, c2.g, c2.b, EDGE_ALPHA * fade), (2.5 if sk >= 0 else 1.5) * w, true)
		FX_BOLT:
			var cls2: int = clampi(int(float(it["c"])), 0, CLASS_COL.size() - 1)
			var col2: Color = CLASS_COL[cls2]
			var to := Vector2(float(it["a"]), float(it["b"]))
			draw_line(p, to, Color(col2.r, col2.g, col2.b, 0.9 * fade), 2.0 * w)
			draw_line(p, to, Color(1, 1, 1, 0.6 * fade), 0.8 * w)
			var burst: float = float(it["d"])
			if burst > 0.0:
				draw_circle(to, burst * minf(f * 2.0 + 0.3, 1.0), Color(col2.r, col2.g, col2.b, OVER_FILL_ALPHA * fade))
				draw_arc(to, burst * minf(f * 2.0 + 0.3, 1.0), 0.0, TAU, 24, Color(1.0, 0.8, 0.4, EDGE_ALPHA * fade), 1.5 * w, true)
		FX_DASH:
			var to2 := Vector2(float(it["a"]), float(it["b"]))
			draw_line(p, to2, Color(0.85, 0.92, 1.0, 0.7 * fade), 6.0 * fade * w + 1.0 * w)
			draw_line(p, to2, Color(1, 1, 1, 0.8 * fade), 1.5 * w)
		20:
			# A burst of specks, flying out and falling a little.
			var col3 := Color.html(String(it["c"]))
			var n: int = int(float(it["a"]))
			var seed_v: float = float(it["b"]) * 1.7 + p.x * 0.13
			for s in n:
				var a2: float = seed_v + TAU * s / float(n)
				var d: float = (6.0 + 8.0 * fmod(seed_v + s * 3.1, 3.0)) * (1.0 - fade * fade)
				var q: Vector2 = p + Vector2(cos(a2) * d, sin(a2) * d * 0.7 + 10.0 * f * f - 6.0)
				draw_rect(Rect2(q - Vector2.ONE, Vector2(2, 2)), Color(col3.r, col3.g, col3.b, fade))
		21:
			var rise: float = 18.0 * f
			var col4: Color = it["d"]
			var word: String = String(it["c"])
			_word(p + Vector2(0, -26.0 - rise), word, Color(col4.r, col4.g, col4.b, minf(fade * 2.0, 1.0)), 0.6 * fade)


## A word centred on `at` (its baseline), in the body face with a one-design-pixel shadow (no outline: a pixel
## face's outline would be smoothed).
func _word(at: Vector2, word: String, col: Color, shadow: float = 0.8) -> void:
	var f: Font = UiKit.font()
	var fs: int = _fs()
	var one: float = float(_fk())
	var x: float = roundf((at.x - f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / 2.0) / one) * one
	var y: float = roundf(at.y / one) * one
	draw_string(f, Vector2(x + one, y + one), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, shadow))
	draw_string(f, Vector2(x, y), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
