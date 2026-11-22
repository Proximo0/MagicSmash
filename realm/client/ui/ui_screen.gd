class_name UiScreen
extends Control
## A screen of the shell, drawn in code: an immediate-mode Control. `paint()` runs every frame inside `_draw`
## and calls `button()` / `hit()` for what can be clicked; the rectangles are kept for the next click. The
## shell hands a screen its keys through `on_key`. Everything a click does is `on_press(id)`, which the tests
## call through `press(id)` the same way a mouse does.
## A screen is 960 x 540; panels over the town are drawn in the same space and cover the town's input.

signal closed

var shell: Node = null
var hover_id: String = ""
var time: float = 0.0
## Modal screens swallow every key; others pass what they did not use.
var modal: bool = true
var _hits: Array = []
var _scroll: Dictionary = {}
var toast_text: String = ""
var toast_until: float = 0.0
var toast_bad: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	opened()


## Called once the screen is in the tree.
func opened() -> void:
	pass


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


func _draw() -> void:
	_hits.clear()
	paint()
	if toast_until > time and not toast_text.is_empty():
		var w: float = UiKit.text_width(toast_text, 16) + 40.0
		var r := Rect2((UiKit.W - w) / 2.0, 2.0, w, 28.0)
		UiKit.frame(self, r, UiKit.BAD if toast_bad else UiKit.GOLD, Color(0.05, 0.03, 0.03, 0.96))
		UiKit.text(self, Vector2(UiKit.W / 2.0, r.position.y + 4.0), toast_text, 16, UiKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)


## Override: draw the screen and register its buttons.
func paint() -> void:
	pass


func say(s: String, bad: bool = false) -> void:
	toast_text = s
	toast_bad = bad
	toast_until = time + 4.0


## Registers a clickable rectangle (the later one wins where two overlap).
func hit(id: String, r: Rect2, enabled: bool = true) -> void:
	_hits.append({"id": id, "rect": r, "enabled": enabled})


func button(id: String, r: Rect2, label: String, enabled: bool = true, selected: bool = false, size: int = 14) -> void:
	hit(id, r, enabled)
	UiKit.button_box(self, r, label, hover_id == id and enabled, enabled, selected, size)


func has_hit(id: String) -> bool:
	for h in _hits:
		if h["id"] == id:
			return true
	return false


func hit_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for h in _hits:
		out.append(String(h["id"]))
	return out


## Clicks a registered rectangle by id as a mouse would. False when it is not on the screen (or disabled).
func press(id: String) -> bool:
	for i in range(_hits.size() - 1, -1, -1):
		var h: Dictionary = _hits[i]
		if h["id"] == id:
			if not bool(h["enabled"]):
				return false
			on_press(id)
			return true
	return false


func _hit_at(p: Vector2) -> Dictionary:
	for i in range(_hits.size() - 1, -1, -1):
		var h: Dictionary = _hits[i]
		if (h["rect"] as Rect2).has_point(p):
			return h
	return {}


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h: Dictionary = _hit_at(e.position)
		hover_id = String(h["id"]) if not h.is_empty() else ""
		on_hover(hover_id, e.position)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			var h: Dictionary = _hit_at(e.position)
			if not h.is_empty() and bool(h["enabled"]):
				on_press(String(h["id"]))
			else:
				on_click_empty(e.position)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			var h: Dictionary = _hit_at(e.position)
			if not h.is_empty() and bool(h["enabled"]):
				on_alt_press(String(h["id"]))
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP:
			on_wheel(-1, e.position)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			on_wheel(1, e.position)
	accept_event()


func on_press(_id: String) -> void:
	pass


func on_alt_press(_id: String) -> void:
	pass


func on_hover(_id: String, _pos: Vector2) -> void:
	pass


func on_click_empty(_pos: Vector2) -> void:
	pass


func on_wheel(_dir: int, _pos: Vector2) -> void:
	pass


## Returns true when the screen used the key.
func on_key(_e: InputEventKey) -> bool:
	return false


## A scroll offset kept by name (a list's first row).
func scroll_of(name: String) -> int:
	return int(_scroll.get(name, 0))


func scroll_by(name: String, d: int, count: int, visible: int) -> void:
	_scroll[name] = clampi(scroll_of(name) + d, 0, maxi(0, count - visible))


func close() -> void:
	closed.emit()
