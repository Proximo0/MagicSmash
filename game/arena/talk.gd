class_name ArenaTalk
extends RefCounted
## Arena: Morvane's lines during the lull (World.EV_TALK is not emitted by the World; the arena starts a line when
## the lull begins, see ArenaEvents). A small box with his small portrait near the top; it types the line out,
## stays a few seconds and fades. It takes no input and blocks nothing.
## Static helpers: `a` is the Arena that owns the state.

const SHOW_SECS := 6.0
const FADE_SECS := 0.5
const TYPE_CPS := 40.0
const BOX := Rect2(58, 31, 364, 36)
const PIC := Rect2(62, 33, 28, 32)

static var _line: Dictionary = {}
static var _t0 := 0.0
static var _last := -1
static var _rng := RandomNumberGenerator.new()


## Morvane speaks: a line for the act the run is in, never the one he said last.
static func start(a: Arena) -> void:
	_rng.randomize()
	_line = Talk.pick(Talk.MORVANE, {"lull": true, "act": a.act, "last": _last}, _rng)
	if not _line.is_empty():
		_last = int(_line.id)
		_t0 = a.time


static func draw(a: Arena, ci: CanvasItem, dark: Color) -> void:
	if _line.is_empty():
		return
	var k := a.time - _t0
	if k < 0.0 or k > SHOW_SECS:
		_line = {}
		return
	var alpha := clampf(minf(k, SHOW_SECS - k) / FADE_SECS, 0.0, 1.0)
	ci.draw_rect(BOX, Color(0.04, 0.0, 0.1, 0.85 * alpha))
	ci.draw_rect(BOX, Color(Occult.GOLD, alpha), false, 1.0)
	var pic := Rect2(PIC.position, PIC.size)
	if not Art.draw(ci, DialogueBox.GROUP, String(_line.portrait), pic, Color(1, 1, 1, alpha)):
		DialogueBox.draw_stand_in(ci, pic, "")
	var x := PIC.end.x + 6.0
	PixelFont.draw(ci, String(_line.name), Vector2(x, BOX.position.y + 4), 1, Color(Occult.GOLD, alpha), Color(dark, alpha))
	var left := int(k * TYPE_CPS)
	var y := BOX.position.y + 14.0
	for row: String in _line.rows:
		PixelFont.draw(ci, row.substr(0, mini(left, row.length())), Vector2(x, y), 1, Color(Occult.BONE, alpha), Color(dark, alpha))
		left -= row.length()
		y += 9.0
