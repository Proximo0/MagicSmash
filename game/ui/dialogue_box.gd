class_name DialogueBox
extends RefCounted
## The talk box (Talk): the speaker's tall portrait in a panel on the left, a text box along the bottom with the
## speaker's name, the line typing out in up to two rows and a confirm prompt. Confirm completes the typing, then
## closes the box. A missing picture is replaced by a dark silhouette panel with the name.

const CHARS_PER_SEC := 50.0
const PANEL := Rect2(6, 132, 90, 124) # ends above the sanctum's bottom row of counts and keys
const BOX := Rect2(100, 190, 374, 66)
const TEXT_AT := Vector2(110, 210)
const ROW_H := 10
const GROUP := "portraits/characters"

var active := false
var line: Dictionary = {}
var typed := 0.0


## Opens the box on a line from Talk.pick (an empty one opens nothing).
func open(l: Dictionary) -> void:
	if l.is_empty():
		return
	line = l
	typed = 0.0
	active = true


func total_chars() -> int:
	var n := 0
	for row: String in line.get("rows", []):
		n += row.length()
	return n


func is_typed() -> bool:
	return typed >= float(total_chars())


## Completes the typing at once.
func finish() -> void:
	typed = float(total_chars())


func update(delta: float) -> void:
	if active and not is_typed():
		typed += delta * CHARS_PER_SEC


## Takes an input event while open. Returns true when the box closed on it. Confirm finishes the typing, then
## closes; back closes at once.
func handle(event: InputEvent) -> bool:
	if not active:
		return false
	var tap: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if PlayerInput.back_pressed(event):
		active = false
		return true
	if PlayerInput.confirm_device(event) != -99 or tap:
		if not is_typed():
			finish()
		else:
			active = false
			return true
	return false


func draw(ci: CanvasItem, t: float) -> void:
	if not active:
		return
	var who: String = line.name
	_draw_panel(ci, who, String(line.portrait) + "_tall")
	ci.draw_rect(BOX, Occult.INK)
	ci.draw_rect(BOX.grow(-1), Color("1a0f2e"))
	ci.draw_rect(BOX, Occult.GOLD, false, 1.0)
	PixelFont.draw(ci, who, Vector2(TEXT_AT.x, BOX.position.y + 6), 1, Occult.GOLD, Occult.INK)
	var left := int(typed)
	var y := TEXT_AT.y
	for row: String in line.rows:
		var shown := row.substr(0, mini(left, row.length()))
		PixelFont.draw(ci, shown, Vector2(TEXT_AT.x, y), 1, Occult.BONE)
		left -= row.length()
		y += ROW_H
	if is_typed() and int(t * 2.0) % 2 == 0:
		var key := "ENTER" if G.local_devices.is_empty() or G.local_devices[0] == G.DEV_KBM else "A"
		var txt := key + " >"
		PixelFont.draw(ci, txt, Vector2(BOX.end.x - 6 - PixelFont.text_width(txt), BOX.end.y - 11), 1, Color("c9b8ff"))


func _draw_panel(ci: CanvasItem, who: String, key: String) -> void:
	ci.draw_rect(PANEL, Occult.GOLD)
	ci.draw_rect(PANEL.grow(-1), Color("0e0a14"))
	if not Art.draw(ci, GROUP, key, PANEL.grow(-1)):
		draw_stand_in(ci, PANEL.grow(-1), who)


## The plain stand-in for a missing picture: a dark head and shoulders and the name.
static func draw_stand_in(ci: CanvasItem, r: Rect2, who: String) -> void:
	var c := r.get_center()
	var dim := Color("2a2040")
	ci.draw_circle(c + Vector2(0, -12), minf(r.size.x, r.size.y) * 0.18, dim)
	ci.draw_rect(Rect2(c.x - r.size.x * 0.3, c.y + 2, r.size.x * 0.6, r.size.y * 0.4), dim)
	PixelFont.draw_centered(ci, who, c.x, r.end.y - 10, 1, Color("8a7aaa"))
