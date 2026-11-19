class_name PixelFont
## Hand-made 5x7 bitmap font drawn with rects, so every letter stays crisp
## at any integer scale. Used for the HUD, menus and the title logo.

const W := 5
const H := 7

const GLYPHS := {
	"A": ["01110","10001","10001","11111","10001","10001","10001"],
	"B": ["11110","10001","10001","11110","10001","10001","11110"],
	"C": ["01110","10001","10000","10000","10000","10001","01110"],
	"D": ["11110","10001","10001","10001","10001","10001","11110"],
	"E": ["11111","10000","10000","11110","10000","10000","11111"],
	"F": ["11111","10000","10000","11110","10000","10000","10000"],
	"G": ["01110","10001","10000","10111","10001","10001","01111"],
	"H": ["10001","10001","10001","11111","10001","10001","10001"],
	"I": ["01110","00100","00100","00100","00100","00100","01110"],
	"J": ["00111","00010","00010","00010","00010","10010","01100"],
	"K": ["10001","10010","10100","11000","10100","10010","10001"],
	"L": ["10000","10000","10000","10000","10000","10000","11111"],
	"M": ["10001","11011","10101","10101","10001","10001","10001"],
	"N": ["10001","10001","11001","10101","10011","10001","10001"],
	"O": ["01110","10001","10001","10001","10001","10001","01110"],
	"P": ["11110","10001","10001","11110","10000","10000","10000"],
	"Q": ["01110","10001","10001","10001","10101","10010","01101"],
	"R": ["11110","10001","10001","11110","10100","10010","10001"],
	"S": ["01111","10000","10000","01110","00001","00001","11110"],
	"T": ["11111","00100","00100","00100","00100","00100","00100"],
	"U": ["10001","10001","10001","10001","10001","10001","01110"],
	"V": ["10001","10001","10001","10001","10001","01010","00100"],
	"W": ["10001","10001","10001","10101","10101","10101","01010"],
	"X": ["10001","10001","01010","00100","01010","10001","10001"],
	"Y": ["10001","10001","01010","00100","00100","00100","00100"],
	"Z": ["11111","00001","00010","00100","01000","10000","11111"],
	"0": ["01110","10001","10011","10101","11001","10001","01110"],
	"1": ["00100","01100","00100","00100","00100","00100","01110"],
	"2": ["01110","10001","00001","00010","00100","01000","11111"],
	"3": ["11110","00001","00001","01110","00001","00001","11110"],
	"4": ["00010","00110","01010","10010","11111","00010","00010"],
	"5": ["11111","10000","11110","00001","00001","10001","01110"],
	"6": ["00110","01000","10000","11110","10001","10001","01110"],
	"7": ["11111","00001","00010","00100","01000","01000","01000"],
	"8": ["01110","10001","10001","01110","10001","10001","01110"],
	"9": ["01110","10001","10001","01111","00001","00010","01100"],
	" ": ["00000","00000","00000","00000","00000","00000","00000"],
	".": ["00000","00000","00000","00000","00000","01100","01100"],
	",": ["00000","00000","00000","00000","01100","00100","01000"],
	"!": ["00100","00100","00100","00100","00100","00000","00100"],
	"?": ["01110","10001","00001","00010","00100","00000","00100"],
	":": ["00000","01100","01100","00000","01100","01100","00000"],
	"-": ["00000","00000","00000","11111","00000","00000","00000"],
	"+": ["00000","00100","00100","11111","00100","00100","00000"],
	"x": ["00000","00000","10001","01010","00100","01010","10001"],
	"/": ["00001","00010","00010","00100","01000","01000","10000"],
	"'": ["00100","00100","01000","00000","00000","00000","00000"],
	"<": ["00010","00100","01000","10000","01000","00100","00010"],
	">": ["01000","00100","00010","00001","00010","00100","01000"],
	"#": ["01010","11111","01010","01010","01010","11111","01010"],
	"*": ["00000","10101","01110","11111","01110","10101","00000"],
	"=": ["00000","00000","11111","00000","11111","00000","00000"],
	"(": ["00010","00100","01000","01000","01000","00100","00010"],
	")": ["01000","00100","00010","00010","00010","00100","01000"],
	"%": ["11001","11010","00010","00100","01000","01011","10011"],
	"_": ["00000","00000","00000","00000","00000","00000","11111"],
}

static var _cache := {}

static func _rows(ch: String) -> Array:
	if GLYPHS.has(ch):
		return GLYPHS[ch]
	var up := ch.to_upper()
	if GLYPHS.has(up):
		return GLYPHS[up]
	return GLYPHS["?"]

## Pixel offsets of the lit cells of a glyph, cached.
static func cells(ch: String) -> PackedVector2Array:
	if _cache.has(ch):
		return _cache[ch]
	var out := PackedVector2Array()
	var rows := _rows(ch)
	for y in H:
		var r: String = rows[y]
		for x in W:
			if r[x] == "1":
				out.append(Vector2(x, y))
	_cache[ch] = out
	return out

static func text_width(text: String, scale: int = 1, spacing: int = 1) -> int:
	if text.is_empty():
		return 0
	return (text.length() * (W + spacing) - spacing) * scale

## Draws text with an optional 1px-per-scale outline (8 directions) and shadow.
static func draw(ci: CanvasItem, text: String, pos: Vector2, scale: int = 1,
		color: Color = Color.WHITE, outline: Color = Color(0, 0, 0, 0),
		shadow: Color = Color(0, 0, 0, 0), spacing: int = 1) -> void:
	pos = pos.floor()
	if shadow.a > 0.0:
		_draw_raw(ci, text, pos + Vector2(scale, scale) * 2, scale, shadow, spacing, scale)
	if outline.a > 0.0:
		_draw_raw(ci, text, pos, scale, outline, spacing, scale)
	_draw_raw(ci, text, pos, scale, color, spacing, 0)

static func _draw_raw(ci: CanvasItem, text: String, pos: Vector2, scale: int,
		color: Color, spacing: int, grow: int) -> void:
	var x := pos.x
	for i in text.length():
		var ch := text[i]
		for c in cells(ch):
			ci.draw_rect(Rect2(x + c.x * scale - grow, pos.y + c.y * scale - grow,
				scale + grow * 2, scale + grow * 2), color)
		x += (W + spacing) * scale

static func draw_centered(ci: CanvasItem, text: String, center_x: float, y: float,
		scale: int = 1, color: Color = Color.WHITE, outline: Color = Color(0, 0, 0, 0),
		shadow: Color = Color(0, 0, 0, 0)) -> void:
	var w := text_width(text, scale)
	draw(ci, text, Vector2(center_x - w / 2.0, y), scale, color, outline, shadow)

## Per-row gradient fill, used for the big title letters.
static func draw_gradient(ci: CanvasItem, text: String, pos: Vector2, scale: int,
		top: Color, bottom: Color, wave_t: float = 0.0, wave_amp: float = 0.0) -> void:
	var x := pos.x
	for i in text.length():
		var ch := text[i]
		var dy := floorf(sin(wave_t + i * 0.55) * wave_amp)
		for c in cells(ch):
			var col := top.lerp(bottom, c.y / float(H - 1))
			ci.draw_rect(Rect2(x + c.x * scale, pos.y + dy + c.y * scale, scale, scale), col)
			# Top-left highlight on each cell for a chunky bevel look.
			if scale >= 4:
				ci.draw_rect(Rect2(x + c.x * scale, pos.y + dy + c.y * scale, scale, 1),
					col.lightened(0.35))
		x += (W + 1) * scale
