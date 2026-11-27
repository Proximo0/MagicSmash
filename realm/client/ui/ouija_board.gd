class_name OuijaBoard
extends RefCounted
## Text entry like a ouija board (the Four of Wands menus' touch): the letters sit on two arcs, the digits and
## the two marks a name may hold (' and -) on a third, NO in one corner erases, YES in the other is done. The
## planchette glides to the letter under the mouse. The keyboard types as well. A screen owns one, calls
## `paint(screen, rect)` from its paint(), and passes presses ("ouija:<char>", "ouija:no", "ouija:yes") to `press`.

signal entered(text: String)

const ROW1: String = "ABCDEFGHIJKLM"
const ROW2: String = "NOPQRSTUVWXYZ"
const ROW3: String = "0123456789'-"

var text: String = ""
var max_len: int = 16
## Letters are typed in capitals when true (a dev login is not case sensitive; a hero's name keeps its case).
var upper: bool = false
var planchette: Vector2 = Vector2.ZERO
var _placed: bool = false
var _target: Vector2 = Vector2(480, 300)
var _pos: Dictionary = {}


func _cells(r: Rect2) -> Array:
	var out: Array = []
	var rows: Array[String] = [ROW1, ROW2, ROW3]
	for row in 3:
		var s: String = rows[row]
		var n: int = s.length()
		var step: float = (r.size.x - 120.0) / float(n)
		var y0: float = r.position.y + 50.0 + row * 44.0
		for i in n:
			var u: float = (float(i) + 0.5) / float(n) * 2.0 - 1.0
			var sag: float = (u * u) * (18.0 if row < 2 else 0.0)
			out.append([s[i], Vector2(r.position.x + 60.0 + (float(i) + 0.5) * step, y0 + sag)])
	return out


## Draws the board and registers its hits. `screen` must be inside its `_draw`.
func paint(screen: UiScreen, r: Rect2) -> void:
	if not _placed:
		_placed = true
		planchette = r.get_center()
		_target = planchette
	UiKit.frame(screen, r, UiKit.GOLD_DIM, Color(0.06, 0.045, 0.04, 0.97))
	# The sun and the moon in the top corners, as on the old boards.
	screen.draw_arc(r.position + Vector2(36, 34), 14.0, 0.0, TAU, 20, UiKit.GOLD_DIM, 1.0)
	for k in 8:
		var a: float = float(k) / 8.0 * TAU
		screen.draw_line(r.position + Vector2(36, 34) + Vector2.from_angle(a) * 18.0, r.position + Vector2(36, 34) + Vector2.from_angle(a) * 24.0, UiKit.GOLD_DIM, 1.0)
	screen.draw_arc(r.end - Vector2(36, r.size.y - 34), 14.0, 1.2, 5.2, 16, UiKit.GOLD_DIM, 1.0)
	# What has been spelled so far.
	var shown: String = text + ("_" if int(screen.time * 2.0) % 2 == 0 and text.length() < max_len else " ")
	UiKit.text(screen, Vector2(r.position.x + r.size.x / 2.0, r.position.y + 8.0), shown, 26, UiKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)
	var cells: Array = _cells(r)
	for c in cells:
		var ch: String = c[0]
		var at: Vector2 = c[1]
		var cr := Rect2(at - Vector2(15, 17), Vector2(30, 34))
		var id: String = "ouija:" + ch
		screen.hit(id, cr, text.length() < max_len)
		_pos[id] = at
		var hot: bool = screen.hover_id == id
		UiKit.text(screen, at - Vector2(0, 11), ch, 20, UiKit.GOLD if hot else UiKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)
		if hot:
			_target = at
	var no := Rect2(r.position + Vector2(24, r.size.y - 52), Vector2(110, 40))
	var yes := Rect2(r.end - Vector2(134, 52), Vector2(110, 40))
	screen.hit("ouija:no", no, not text.is_empty())
	screen.hit("ouija:yes", yes, true)
	for pair in [[no, "NO", "Erase", "ouija:no"], [yes, "YES", "Done", "ouija:yes"]]:
		var rr: Rect2 = pair[0]
		var hot2: bool = screen.hover_id == String(pair[3])
		UiKit.text(screen, rr.position + Vector2(55, 0), String(pair[1]), 22, UiKit.GOLD if hot2 else UiKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.text(screen, rr.position + Vector2(55, 24), String(pair[2]), 12, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		if hot2:
			_target = rr.position + Vector2(55, 12)
	UiKit.text(screen, Vector2(r.position.x + r.size.x / 2.0, r.end.y - 24.0), "Type on the keys, or click the letters.", 11, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	planchette = planchette.lerp(_target, 0.18)
	_planchette(screen, planchette)


func _planchette(ci: CanvasItem, at: Vector2) -> void:
	var body := PackedVector2Array([at + Vector2(0, -26), at + Vector2(-16, 10), at + Vector2(0, 18), at + Vector2(16, 10)])
	ci.draw_colored_polygon(body, Color(0.22, 0.1, 0.08, 0.55))
	ci.draw_polyline(PackedVector2Array([body[0], body[1], body[2], body[3], body[0]]), UiKit.GOLD, 1.0)
	ci.draw_arc(at + Vector2(0, -4), 6.0, 0.0, TAU, 14, UiKit.GOLD, 1.0)


func type_char(c: String) -> void:
	if c.length() != 1 or text.length() >= max_len:
		return
	text += c.to_upper() if upper else c


func erase() -> void:
	if not text.is_empty():
		text = text.left(text.length() - 1)


## A press id from the board ("ouija:A"); true when it was one of ours.
func press(id: String) -> bool:
	if not id.begins_with("ouija:"):
		return false
	var k: String = id.trim_prefix("ouija:")
	if k == "no":
		erase()
	elif k == "yes":
		entered.emit(text)
	else:
		type_char(k)
	return true


## A key: letters, digits, ' and - type; Backspace erases; Enter is done. True when used.
func key(e: InputEventKey) -> bool:
	if e.keycode == KEY_BACKSPACE:
		erase()
		return true
	if e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER:
		entered.emit(text)
		return true
	if e.unicode > 31 and e.unicode < 127:
		var c: String = char(e.unicode)
		var up: String = c.to_upper()
		if ROW1.contains(up) or ROW2.contains(up) or ROW3.contains(c):
			type_char(c)
			return true
	return false
