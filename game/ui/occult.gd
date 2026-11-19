class_name Occult
extends RefCounted
## The occult look shared by every menu: rune-edged panels with sigils in the corners, candles, a pentagram
## cursor. Drawing only; colours live here so the title, lobby, pause and results screens match.

const INK := Color("0b0716")
const FILL := Color(0.07, 0.025, 0.13, 0.94)
const VIOLET := Color("7b4dff")
const DEEP := Color("4b2ab8")
const BONE := Color("e8dcc0")
const GOLD := Color("ffd94d")
const BLOOD := Color("c0263a")
const DIM := Color("b8a8d8")
const FLAME := Color("ffcf5a")

## Runes as line segments in a 4x6 box (x, y, x, y).
const RUNES: Array = [
	[0, 0, 0, 6, 0, 1, 3, 0, 0, 3, 3, 2], # fehu
	[0, 0, 0, 6, 0, 0, 3, 3, 3, 3, 3, 6], # ur
	[1, 0, 1, 6, 1, 1, 3, 3, 3, 3, 1, 5], # thurisaz
	[0, 0, 0, 6, 0, 0, 3, 2, 0, 3, 3, 5], # ansuz-ish
	[2, 0, 2, 6, 0, 2, 4, 2, 0, 4, 4, 4], # cross
	[0, 0, 4, 6, 4, 0, 0, 6], # gebo
	[2, 0, 2, 6, 0, 1, 2, 3, 4, 1, 2, 3], # algiz
	[0, 6, 2, 0, 2, 0, 4, 6, 1, 3, 3, 3], # eye
]


## A dark panel with a double border, a strip of runes along the top and bottom edges and a sigil in each
## corner. `t` makes the runes glow in a slow wave.
static func frame(ci: CanvasItem, r: Rect2, t: float = 0.0, runes: bool = true) -> void:
	ci.draw_rect(r.grow(3), INK)
	ci.draw_rect(r, FILL)
	_box(ci, r.grow(1), VIOLET)
	_box(ci, r.grow(-2), Color(DEEP, 0.7))
	if runes and r.size.x > 60:
		var n := int((r.size.x - 28) / 9.0)
		var x0 := r.position.x + (r.size.x - n * 9) / 2.0 + 2
		for i in n:
			var glow := 0.25 + 0.35 * maxf(0.0, sin(t * 2.0 - i * 0.45))
			rune(ci, Vector2(x0 + i * 9, r.position.y - 4), (i * 5 + 3) % RUNES.size(), Color(VIOLET, glow + 0.2))
			rune(ci, Vector2(x0 + i * 9, r.end.y - 3), (i * 3 + 1) % RUNES.size(), Color(DEEP, glow + 0.15))
	for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		sigil(ci, c, 5.0, t)


static func _box(ci: CanvasItem, r: Rect2, c: Color) -> void:
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), c)
	ci.draw_rect(Rect2(Vector2(r.position.x, r.end.y - 1), Vector2(r.size.x, 1)), c)
	ci.draw_rect(Rect2(r.position, Vector2(1, r.size.y)), c)
	ci.draw_rect(Rect2(Vector2(r.end.x - 1, r.position.y), Vector2(1, r.size.y)), c)


## One rune, 4x6 pixels, its top left at `p`.
static func rune(ci: CanvasItem, p: Vector2, i: int, c: Color) -> void:
	var seg: Array = RUNES[wrapi(i, 0, RUNES.size())]
	for k in range(0, seg.size(), 4):
		ci.draw_line(p + Vector2(seg[k], seg[k + 1]), p + Vector2(seg[k + 2], seg[k + 3]), c, 1.0)


## A small ringed pentagram on a dark disc, for panel corners.
static func sigil(ci: CanvasItem, c: Vector2, r: float, t: float = 0.0) -> void:
	ci.draw_circle(c, r + 1.5, INK)
	ci.draw_arc(c, r, 0.0, TAU, 16, VIOLET, 1.0)
	pentagram(ci, c, r - 1.0, Color(BONE, 0.65 + 0.2 * sin(t * 1.7 + c.x)), 0.0)


## A five-pointed star drawn in one stroke, point up, turned by `rot` radians.
static func pentagram(ci: CanvasItem, c: Vector2, r: float, col: Color, rot: float = 0.0) -> void:
	var pts := PackedVector2Array()
	for k in 6:
		var a := rot - PI / 2.0 + (k * 2) * TAU / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	ci.draw_polyline(pts, col, 1.0)


## The menu cursor: a slowly turning pentagram with a gold glint.
static func cursor(ci: CanvasItem, c: Vector2, t: float) -> void:
	ci.draw_circle(c, 5.0, Color(BLOOD, 0.35))
	pentagram(ci, c, 4.5, GOLD, t * 1.5)
	ci.draw_rect(Rect2(c - Vector2(0.5, 0.5), Vector2(1, 1)), Color.WHITE)


## A candle standing on `base` (bottom centre) with a flickering flame. `seed_v` keeps neighbours out of step.
static func candle(ci: CanvasItem, base: Vector2, t: float, seed_v: float = 0.0, h: int = 8) -> void:
	var flick := sin(t * 11.0 + seed_v * 7.0) * 0.5 + sin(t * 17.0 + seed_v) * 0.5
	ci.draw_circle(base - Vector2(0, h + 3), 7.0 + flick, Color(1.0, 0.7, 0.3, 0.08))
	ci.draw_rect(Rect2(base + Vector2(-2, -h), Vector2(4, h)), BONE)
	ci.draw_rect(Rect2(base + Vector2(1, -h), Vector2(1, h)), Color("b8a888"))
	ci.draw_rect(Rect2(base + Vector2(-2, -h), Vector2(1, 2)), Color("fff6e0"))
	ci.draw_rect(Rect2(base + Vector2(0, -h - 1), Vector2(1, 1)), INK)
	var fh := 3 + int(flick > 0.3)
	var fx := float(int(flick * 1.2))
	ci.draw_rect(Rect2(base + Vector2(-1 + fx * 0.5, -h - 1 - fh), Vector2(2, fh)), FLAME)
	ci.draw_rect(Rect2(base + Vector2(fx * 0.5, -h - fh), Vector2(1, fh - 1)), Color.WHITE)


## A row of `n` options' selection bar: dark red wash with bone rules above and below.
static func highlight(ci: CanvasItem, r: Rect2, t: float) -> void:
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	ci.draw_rect(r, Color(BLOOD, 0.22 + 0.12 * pulse))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(BONE, 0.5))
	ci.draw_rect(Rect2(Vector2(r.position.x, r.end.y - 1), Vector2(r.size.x, 1)), Color(BONE, 0.5))
