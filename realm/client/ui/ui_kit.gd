class_name UiKit
extends RefCounted
## The shell's look, drawn by code: black ground, bone text, dried-blood red, tallow gold; thin ornate frames with
## notched corners, rune accents. Everything draws into a CanvasItem inside its `_draw`. The shell's canvas is
## 960 x 540 (the project's 480 x 270 doubled), so text can be 12 to 40 px.

const W: float = 960.0
const H: float = 540.0
const BLACK: Color = Color(0.03, 0.026, 0.034)
const INK: Color = Color(0.075, 0.062, 0.07)
const INK_LIGHT: Color = Color(0.11, 0.09, 0.1)
const BONE: Color = Color(0.88, 0.84, 0.72)
const BONE_DIM: Color = Color(0.6, 0.56, 0.47)
const BLOOD: Color = Color(0.5, 0.09, 0.09)
const BLOOD_BRIGHT: Color = Color(0.78, 0.15, 0.13)
const GOLD: Color = Color(0.85, 0.68, 0.3)
const GOLD_DIM: Color = Color(0.5, 0.4, 0.2)
const GOOD: Color = Color(0.55, 0.8, 0.5)
const BAD: Color = Color(0.9, 0.35, 0.3)
const FONT_NAMES: PackedStringArray = ["Georgia", "Palatino Linotype", "Book Antiqua", "DejaVu Serif", "Liberation Serif", "Times New Roman", "serif"]

## Runes drawn as polylines in a unit square (0..1), an accent beside titles and on cards.
const RUNES: Array = [
	[[0.5, 0.0, 0.5, 1.0], [0.5, 0.2, 0.9, 0.5], [0.5, 0.5, 0.9, 0.8]],
	[[0.2, 0.0, 0.2, 1.0], [0.2, 0.0, 0.8, 0.3], [0.8, 0.3, 0.2, 0.55]],
	[[0.1, 0.1, 0.9, 0.9], [0.9, 0.1, 0.1, 0.9], [0.5, 0.0, 0.5, 1.0]],
	[[0.5, 0.0, 0.1, 0.5], [0.1, 0.5, 0.5, 1.0], [0.5, 1.0, 0.9, 0.5], [0.9, 0.5, 0.5, 0.0]],
	[[0.2, 0.0, 0.2, 1.0], [0.8, 0.0, 0.8, 1.0], [0.2, 0.5, 0.8, 0.5]],
	[[0.5, 0.0, 0.5, 1.0], [0.1, 0.3, 0.5, 0.0], [0.9, 0.3, 0.5, 0.0], [0.1, 0.7, 0.9, 0.7]],
	[[0.2, 0.0, 0.8, 0.5], [0.8, 0.5, 0.2, 1.0], [0.8, 0.0, 0.8, 1.0]],
	[[0.1, 0.0, 0.5, 0.5], [0.5, 0.5, 0.9, 0.0], [0.5, 0.5, 0.5, 1.0]]]

static var _font: Font = null


static func font() -> Font:
	if _font == null:
		var sf := SystemFont.new()
		sf.font_names = FONT_NAMES
		sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font = sf
	return _font


static func text_width(s: String, size: int) -> float:
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Text with its top-left at `pos`. `align` LEFT, CENTER (pos.x is the middle), RIGHT (pos.x is the right edge).
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int = 14, col: Color = BONE, align: int = HORIZONTAL_ALIGNMENT_LEFT, shadow: bool = true) -> void:
	var f: Font = font()
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x: float = pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	var base := Vector2(x, pos.y + f.get_ascent(size))
	if shadow:
		ci.draw_string(f, base + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.8))
	ci.draw_string(f, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Wrapped text inside a width; returns the height used.
static func paragraph(ci: CanvasItem, pos: Vector2, s: String, width: float, size: int = 13, col: Color = BONE_DIM) -> float:
	var f: Font = font()
	var lines: PackedStringArray = []
	for para in s.split("\n"):
		var line: String = ""
		for word in para.split(" "):
			var t: String = word if line.is_empty() else line + " " + word
			if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and not line.is_empty():
				lines.append(line)
				line = word
			else:
				line = t
		lines.append(line)
	var lh: float = f.get_height(size) + 1.0
	for i in lines.size():
		text(ci, pos + Vector2(0, i * lh), lines[i], size, col)
	return lines.size() * lh


static func fill(ci: CanvasItem, r: Rect2, col: Color) -> void:
	ci.draw_rect(r, col)


## A thin double frame with notched corners.
static func frame(ci: CanvasItem, r: Rect2, col: Color = GOLD_DIM, fill_col: Color = Color(0.05, 0.042, 0.05, 0.94)) -> void:
	if fill_col.a > 0.0:
		ci.draw_rect(r, fill_col)
	var n: float = 5.0
	var pts := PackedVector2Array([
		r.position + Vector2(n, 0), r.position + Vector2(r.size.x - n, 0), r.position + Vector2(r.size.x, n),
		r.position + Vector2(r.size.x, r.size.y - n), r.position + Vector2(r.size.x - n, r.size.y),
		r.position + Vector2(n, r.size.y), r.position + Vector2(0, r.size.y - n), r.position + Vector2(0, n),
		r.position + Vector2(n, 0)])
	ci.draw_polyline(pts, col, 1.0)
	var inner: Rect2 = r.grow(-3.0)
	ci.draw_rect(inner, Color(col.r, col.g, col.b, col.a * 0.45), false, 1.0)
	for c in [r.position, r.position + Vector2(r.size.x, 0), r.position + Vector2(0, r.size.y), r.end]:
		ci.draw_circle(c, 1.5, col)


static func rune(ci: CanvasItem, at: Vector2, idx: int, size: float, col: Color = GOLD, width: float = 1.5) -> void:
	var r: Array = RUNES[posmod(idx, RUNES.size())]
	for seg in r:
		var s: Array = seg
		ci.draw_line(at + Vector2(float(s[0]), float(s[1])) * size, at + Vector2(float(s[2]), float(s[3])) * size, col, width)


## A rune each side of a title, and a rule under it.
static func title(ci: CanvasItem, centre: Vector2, s: String, size: int = 26, col: Color = BONE) -> void:
	text(ci, centre, s, size, col, HORIZONTAL_ALIGNMENT_CENTER)
	var w: float = text_width(s, size)
	var y: float = centre.y + size * 0.1
	rune(ci, Vector2(centre.x - w / 2.0 - size * 1.2, y), 0, size * 0.8, GOLD)
	rune(ci, Vector2(centre.x + w / 2.0 + size * 0.4, y), 3, size * 0.8, GOLD)
	ci.draw_line(Vector2(centre.x - w / 2.0, centre.y + size * 1.35), Vector2(centre.x + w / 2.0, centre.y + size * 1.35), GOLD_DIM, 1.0)


static func bar(ci: CanvasItem, r: Rect2, frac: float, col: Color = BLOOD_BRIGHT) -> void:
	ci.draw_rect(r, Color(0.02, 0.02, 0.025))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	ci.draw_rect(r, GOLD_DIM, false, 1.0)


static func button_box(ci: CanvasItem, r: Rect2, label: String, hover: bool, enabled: bool, selected: bool, size: int = 14) -> void:
	var edge: Color = GOLD if (hover or selected) else GOLD_DIM
	var body: Color = Color(0.16, 0.05, 0.05, 0.96) if selected else (Color(0.12, 0.09, 0.09, 0.96) if hover else Color(0.07, 0.058, 0.066, 0.96))
	if not enabled:
		edge = Color(0.3, 0.28, 0.25)
		body = Color(0.05, 0.045, 0.05, 0.9)
	frame(ci, r, edge, body)
	var col: Color = (BONE if enabled else Color(0.4, 0.38, 0.34))
	if hover and enabled:
		col = GOLD
	text(ci, Vector2(r.position.x + r.size.x / 2.0, r.position.y + (r.size.y - font().get_height(size)) / 2.0), label, size, col, HORIZONTAL_ALIGNMENT_CENTER)


## A flickering candle, for the title and the card reader.
static func candle(ci: CanvasItem, at: Vector2, t: float, seed_: float = 0.0) -> void:
	var fl: float = 0.85 + 0.15 * sin(t * 9.0 + seed_) * sin(t * 5.3 + seed_ * 2.0)
	ci.draw_rect(Rect2(at + Vector2(-3, 0), Vector2(6, 22)), Color(0.8, 0.76, 0.62))
	ci.draw_circle(at + Vector2(0, -5), 9.0 * fl, Color(0.95, 0.6, 0.15, 0.12))
	ci.draw_circle(at + Vector2(0, -4), 4.5 * fl, Color(0.95, 0.65, 0.2, 0.3))
	var flame := PackedVector2Array([at + Vector2(-2, -1), at + Vector2(0, -9 * fl), at + Vector2(2, -1)])
	ci.draw_colored_polygon(flame, Color(1.0, 0.82, 0.35))


## Dark vignette and a few drifting motes behind a whole screen.
static func backdrop(ci: CanvasItem, t: float) -> void:
	ci.draw_rect(Rect2(0, 0, W, H), BLACK)
	for i in 40:
		var fx: float = fposmod(float(i) * 97.3 + t * (4.0 + (i % 5)), W)
		var fy: float = fposmod(float(i) * 61.7 - t * (6.0 + (i % 3) * 2.0), H)
		ci.draw_rect(Rect2(fx, fy, 1.5, 1.5), Color(0.55, 0.4, 0.25, 0.25 + 0.15 * sin(t * 2.0 + i)))
	for k in 6:
		var a: float = 0.05 * (6 - k)
		ci.draw_rect(Rect2(0, 0, W, 8 * (k + 1)), Color(0, 0, 0, a))
		ci.draw_rect(Rect2(0, H - 8 * (k + 1), W, 8 * (k + 1)), Color(0, 0, 0, a))
