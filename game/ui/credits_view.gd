class_name CreditsView
extends RefCounted
## The CREDITS board of the title menu: the roll from Credits, scrolling up by itself inside an Occult frame. Up and
## down (keys, stick, d-pad, mouse wheel) scroll by hand and stop the automatic scroll; the roll stops at its end.
## B, ESC or a tap leaves.

const FRAME := Rect2(4, 4, 472, 262)
## The strip the lines move in; a line is drawn only when it lies wholly inside it, fading near both edges.
const VIEW_TOP := 16.0
const VIEW_BOTTOM := 254.0
const FADE := 22.0
const CENTER_X := 240.0
## Pixels a second the roll climbs by itself, and the pixels one key press or wheel notch moves it.
const AUTO_SPEED := 14.0
const HAND_STEP := 22.0
## The roll starts this far below its first line, so the title rises into view.
const LEAD_IN := 70.0
## Height each kind of line takes, and the space after the last line.
const HEIGHTS := {Credits.HEAD: 18.0, Credits.LINE: 11.0, Credits.GAP: 10.0}
const TAIL := 40.0
## The longest frame of a time step, so a stall does not throw the roll forward.
const MAX_DT := 0.1

var _rows: Array = []
var _tops: PackedFloat32Array = PackedFloat32Array()
var _height := 0.0
var _scroll := 0.0
var _auto := true
var _last_t := -1.0


func open() -> void:
	_rows = Credits.roll(Credits.MAKER, Credits.PICTURES_BY, Engine.has_singleton("SentrySDK"), G.VERSION,
		Engine.get_copyright_info())
	_tops.clear()
	var y := 0.0
	for r: Array in _rows:
		_tops.append(y)
		y += float(HEIGHTS[r[0]])
	_height = y + TAIL
	_scroll = -LEAD_IN
	_auto = true
	_last_t = -1.0


## The furthest the roll scrolls: its last line ends at the bottom of the strip.
func max_scroll() -> float:
	return maxf(0.0, _height - (VIEW_BOTTOM - VIEW_TOP))


func scroll_pos() -> float:
	return _scroll


func is_auto() -> bool:
	return _auto


## Puts the roll at `pos` (kept between its lead-in and its end) and stops the automatic scroll.
func scroll_to(pos: float) -> void:
	_auto = false
	_scroll = clampf(pos, -LEAD_IN, max_scroll())


func draw(ci: CanvasItem, t: float) -> void:
	var dt := 0.0 if _last_t < 0.0 else clampf(t - _last_t, 0.0, MAX_DT)
	_last_t = t
	if _auto:
		_scroll = minf(_scroll + AUTO_SPEED * dt, max_scroll())
	ci.draw_rect(Rect2(Vector2.ZERO, G.SCREEN), Color(0.02, 0.0, 0.05, 0.92))
	Occult.frame(ci, FRAME, t)
	for i: int in range(_rows.size()):
		var kind: int = _rows[i][0]
		if kind == Credits.GAP:
			continue
		var y := VIEW_TOP + _tops[i] - _scroll
		var h := float(PixelFont.H * (Credits.HEAD_SCALE if kind == Credits.HEAD else Credits.LINE_SCALE))
		if y < VIEW_TOP or y + h > VIEW_BOTTOM:
			continue
		var a := clampf(minf(y - VIEW_TOP, VIEW_BOTTOM - (y + h)) / FADE + 0.15, 0.0, 1.0)
		var col: Color = Occult.GOLD if kind == Credits.HEAD else Occult.BONE
		var scale := Credits.HEAD_SCALE if kind == Credits.HEAD else Credits.LINE_SCALE
		PixelFont.draw_centered(ci, String(_rows[i][1]), CENTER_X, y, scale, Color(col, a), Color(Occult.INK, a))
	PixelFont.draw_centered(ci, "ESC/B: BACK", CENTER_X, 258, 1, Color(1, 1, 1, 0.45), Occult.INK)


## Handles one input event. Returns true when the screen closes.
func handle(event: InputEvent) -> bool:
	if PlayerInput.back_pressed(event):
		Sfx.play("menu_select")
		return true
	var d := PlayerInput.menu_dir(event)
	if d == 0 and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			d = -1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			d = 1
	if d != 0:
		scroll_to(_scroll + d * HAND_STEP)
		return false
	var tap: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if tap:
		Sfx.play("menu_select")
		return true
	return false
