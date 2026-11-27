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

## The game's pixel faces, by The Soft Type Project (SIL OFL 1.1, no reserved name; licences beside them in
## ui/fonts as OFL-<Name>.txt): Jersey (10, 15, 20, 25) for every word and number, Jacquard (12, 24, pixel
## blackletter) for titles, headers and names. The number in a name is its capital height in design pixels; a face
## is crisp only at a size that makes each design pixel a whole number of pixels, and its em is EM design pixels,
## so its sizes are roundi(EM * k) (Jersey10 19, 37, 56; Jersey15 27; Jersey20 34; Jersey25 41; Jacquard12 21, 42;
## Jacquard24 43, 86). Measured from the outlines, 27 Nov: at the size of its name a face's pixels are uneven.
## Each face: path, em in design px, capital height, descender (design px, below the baseline).
const FACES: Dictionary = {
	"jersey10": ["res://ui/fonts/Jersey10-Regular.ttf", 56.0 / 3.0, 10, 2],
	"jersey15": ["res://ui/fonts/Jersey15-Regular.ttf", 27.0, 15, 4],
	"jersey20": ["res://ui/fonts/Jersey20-Regular.ttf", 34.0, 20, 5],
	"jersey25": ["res://ui/fonts/Jersey25-Regular.ttf", 41.0, 25, 6],
	"jacquard12": ["res://ui/fonts/Jacquard12-Regular.ttf", 21.0, 12, 3],
	"jacquard24": ["res://ui/fonts/Jacquard24-Regular.ttf", 43.0, 24, 6],
}
const FONT_BODY: String = "res://ui/fonts/Jersey10-Regular.ttf"
const FONT_DISPLAY: String = "res://ui/fonts/Jacquard24-Regular.ttf"
## The old serif TTFs stand behind the pixel faces only for a character they lack (a name typed in another script).
const FALLBACK_BODY: String = "res://ui/fonts/DejaVuSerif.ttf"
const FALLBACK_DISPLAY: String = "res://ui/fonts/IMFellDWPica.ttf"

static var _faces: Dictionary = {}


## A face by name (FACES), set up for pixels in code (no import settings are committed): no antialiasing, no
## hinting, whole-pixel positions, no system fonts, and rasterised at the canvas's own size (oversampling 1), so
## the window's stretch enlarges its pixels with nearest filtering instead of redrawing it at a size between them.
static func face(name: String) -> Font:
	if _faces.has(name):
		return _faces[name]
	var f: Font = null
	var row: Array = FACES.get(name, FACES["jersey10"])
	if ResourceLoader.exists(String(row[0])):
		var ff: FontFile = load(String(row[0])) as FontFile
		if ff != null:
			ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			ff.hinting = TextServer.HINTING_NONE
			ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			ff.allow_system_fallback = false
			ff.oversampling = 1.0
			var fb_path: String = FALLBACK_DISPLAY if name.begins_with("jacquard") else FALLBACK_BODY
			if ff.fallbacks.is_empty() and ResourceLoader.exists(fb_path):
				var fb: Font = load(fb_path) as Font
				if fb != null:
					ff.fallbacks = [fb]
			f = ff
	if f == null:
		var sf := SystemFont.new()
		sf.font_names = FONT_NAMES
		f = sf
	_faces[name] = f
	return f


## The crisp size of a face at k canvas px a design px, its capital height and descender there.
static func crisp(name: String, k: int = 1) -> int:
	return roundi(float(FACES[name][1]) * k)


static func cap(name: String, k: int = 1) -> int:
	return int(FACES[name][2]) * k


static func descent(name: String, k: int = 1) -> int:
	return int(FACES[name][3]) * k


## The text face (Jersey10) and the title face (Jacquard24).
static func font() -> Font:
	return face("jersey10")


static func display_font() -> Font:
	return face("jacquard24")


## What a request of `size` (the screens' numbers, from the serif days) draws with on the shell's 960 x 540 canvas:
## [face name, k]. Body: to 17 Jersey10 (capitals 10 px), to 23 Jersey15 (15), to 31 Jersey20 (20), else Jersey25
## (25). Titles: under 22 Jacquard12 (12), to 47 Jacquard24 (24), else Jacquard24 at 2 (48). One design px is one
## canvas px (1.5 screen px in the 1440 x 810 window, 2 in 1920 x 1080), the title screen's name two.
static func pick(size: int, display: bool = false) -> Array:
	if display:
		if size < 22:
			return ["jacquard12", 1]
		return ["jacquard24", 1] if size < 48 else ["jacquard24", 2]
	if size <= 17:
		return ["jersey10", 1]
	if size <= 23:
		return ["jersey15", 1]
	return ["jersey20", 1] if size <= 31 else ["jersey25", 1]


## The face and size a request draws with, for Controls (a Label's font and font_size).
static func pick_font(size: int, display: bool = false) -> Font:
	return face(String(pick(size, display)[0]))


static func px(size: int, display: bool = false) -> int:
	var p: Array = pick(size, display)
	return crisp(String(p[0]), int(p[1]))


## Blackletter is never set in capitals alone (joined capitals cannot be read): a title in capitals is drawn in
## title case, small words lower ("THE BANK OF BONES" -> "The Bank of Bones"). Mixed case is left as written.
const SMALL_WORDS: PackedStringArray = ["of", "the", "and", "a", "an", "at", "in", "on", "to", "for", "by", "or", "from", "with", "into"]


static func title_case(s: String) -> String:
	if s != s.to_upper():
		return s
	var words: PackedStringArray = s.to_lower().split(" ")
	for i in words.size():
		var w: String = words[i]
		if w.is_empty() or (i > 0 and SMALL_WORDS.has(w)):
			continue
		words[i] = w.left(1).to_upper() + w.substr(1)
	return " ".join(words)


static func _is_display(f: Font) -> bool:
	return f != null and (f == face("jacquard24") or f == face("jacquard12"))


static func text_width(s: String, size: int, f: Font = null) -> float:
	var p: Array = pick(size, _is_display(f))
	if String(p[0]).begins_with("jacquard"):
		s = title_case(s)
	return face(String(p[0])).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, crisp(String(p[0]), int(p[1]))).x


## The space from the top of one line to the next: a gap of 0.3 capitals, the capitals, the descender, 2 px.
static func line_height(size: int, f: Font = null) -> float:
	var p: Array = pick(size, _is_display(f))
	var n: String = String(p[0])
	var k: int = int(p[1])
	return float(_pad(n, k) + cap(n, k) + descent(n, k) + 2)


static func _pad(name: String, k: int) -> int:
	return ceili(cap(name, k) * 0.3)


## Text with its top at `pos` (a gap of 0.3 capitals, then the capitals: the serif's old place), whole pixels only.
## `with` = display_font() asks for the title face.
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int = 14, col: Color = BONE, align: int = HORIZONTAL_ALIGNMENT_LEFT, shadow: bool = true, with: Font = null) -> void:
	var p: Array = pick(size, _is_display(with))
	var n: String = String(p[0])
	var k: int = int(p[1])
	var f: Font = face(n)
	var fs: int = crisp(n, k)
	if n.begins_with("jacquard"):
		s = title_case(s)
	var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x: float = pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	var base := Vector2(x, pos.y + _pad(n, k) + cap(n, k)).round()
	if shadow:
		ci.draw_string(f, base + Vector2(k, k), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
	ci.draw_string(f, base, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## `s` broken into lines no wider than `width` at a requested size (at spaces; a word wider than a line stands alone).
static func wrap(s: String, size: int, width: float) -> PackedStringArray:
	var p: Array = pick(size)
	var f: Font = face(String(p[0]))
	var fs: int = crisp(String(p[0]), int(p[1]))
	var lines: PackedStringArray = []
	for para in s.split("\n"):
		var line: String = ""
		for word in para.split(" "):
			var t: String = word if line.is_empty() else line + " " + word
			if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width and not line.is_empty():
				lines.append(line)
				line = word
			else:
				line = t
		lines.append(line)
	return lines


## Wrapped text inside a width; returns the height used.
static func paragraph(ci: CanvasItem, pos: Vector2, s: String, width: float, size: int = 13, col: Color = BONE_DIM) -> float:
	var lines: PackedStringArray = wrap(s, size, width)
	var lh: float = line_height(size)
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


## The size a panel's title is drawn at: the big title face when it fits in `room` px with its runes, else the small.
static func title_size(s: String, room: float) -> int:
	return 22 if text_width(s, 22, display_font()) + 80.0 <= room else 20


## A rune each side of a title, and a rule under it.
static func title(ci: CanvasItem, centre: Vector2, s: String, size: int = 26, col: Color = BONE) -> void:
	var f: Font = display_font()
	text(ci, centre, s, size, col, HORIZONTAL_ALIGNMENT_CENTER, true, f)
	var w: float = text_width(s, size, f)
	var p: Array = pick(size, true)
	var ch: float = float(_pad(String(p[0]), int(p[1])) + cap(String(p[0]), int(p[1])))
	var rs: float = ch * 0.7
	var y: float = centre.y + ch - rs
	rune(ci, Vector2(centre.x - w / 2.0 - rs - 14.0, y), 0, rs, GOLD, 2.0)
	rune(ci, Vector2(centre.x + w / 2.0 + 14.0, y), 3, rs, GOLD, 2.0)
	var ry: float = centre.y + ch + float(descent(String(p[0]), int(p[1]))) + 4.0
	ci.draw_line(Vector2(centre.x - w / 2.0, ry), Vector2(centre.x + w / 2.0, ry), GOLD_DIM, 2.0)


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
	text(ci, Vector2(r.position.x + r.size.x / 2.0, r.position.y + (r.size.y - line_height(size)) / 2.0), label, size, col, HORIZONTAL_ALIGNMENT_CENTER)


## A slow gold pulse round a rectangle: the thing to do next (the way out of town, the field to enter).
static func glow(ci: CanvasItem, r: Rect2, t: float) -> void:
	var k: float = 0.5 + 0.5 * sin(t * 4.0)
	ci.draw_rect(r.grow(3.0 + 3.0 * k), Color(GOLD, 0.25 + 0.55 * k), false, 2.0)
	ci.draw_rect(r.grow(8.0 + 5.0 * k), Color(GOLD, 0.12 + 0.2 * k), false, 1.0)


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
