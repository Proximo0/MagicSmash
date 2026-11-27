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
## Menu moves with the keyboard (arrows / Tab pick a button, Enter / Space press it, Esc / Backspace go back): off on
## the town itself, where the move keys walk. `nav_focus` is true once a key has picked a button (until the mouse moves).
var nav_enabled: bool = true
var nav_focus: bool = false
var _scroll: Dictionary = {}
var toast_text: String = ""
var toast_until: float = 0.0
var toast_bad: bool = false


func _ready() -> void:
	# The shell's canvas is 960 x 540 (Shell.use_shell_canvas), but a Control anchored to the full rect of a
	# CanvasLayer takes the project's 480 x 270 viewport size: clicks below or right of that missed every button
	# (Curtis's playtest, 25 Nov). The screen is sized to the canvas it draws in.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = Vector2(UiKit.W, UiKit.H)
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
	if nav_focus and not hover_id.is_empty():
		var h: Dictionary = _hit_by_id(hover_id)
		if not h.is_empty():
			var r: Rect2 = (h["rect"] as Rect2).grow(3.0)
			draw_rect(r, Color(UiKit.GOLD, 0.55 + 0.35 * sin(time * 6.0)), false, 2.0)
	if toast_until > time and not toast_text.is_empty():
		# At most TOAST_W wide (the town's buttons stand either side of the top centre), wrapped to more lines.
		var lines: PackedStringArray = UiKit.wrap(toast_text, 16, TOAST_W)
		var w: float = 0.0
		for l in lines:
			w = maxf(w, UiKit.text_width(l, 16))
		w += 32.0
		var lh: float = UiKit.line_height(16)
		var r := Rect2(roundf((UiKit.W - w) / 2.0), 2.0, roundf(w), 12.0 + lines.size() * lh)
		UiKit.frame(self, r, UiKit.BAD if toast_bad else UiKit.GOLD, Color(0.05, 0.03, 0.03, 0.96))
		for i in lines.size():
			UiKit.text(self, Vector2(UiKit.W / 2.0, r.position.y + 6.0 + i * lh), lines[i], 16, UiKit.BONE, HORIZONTAL_ALIGNMENT_CENTER)


## Override: draw the screen and register its buttons.
func paint() -> void:
	pass


## The widest a toast line is drawn (canvas px).
const TOAST_W: float = 330.0


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


func _hit_by_id(id: String) -> Dictionary:
	for i in range(_hits.size() - 1, -1, -1):
		if _hits[i]["id"] == id:
			return _hits[i]
	return {}


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		nav_focus = false
		var h: Dictionary = _hit_at(e.position)
		hover_id = String(h["id"]) if not h.is_empty() else ""
		on_hover(hover_id, e.position)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			var h: Dictionary = _hit_at(e.position)
			if not h.is_empty() and bool(h["enabled"]):
				Sfx.play("ui_click")
				on_press(String(h["id"]))
			else:
				on_click_empty(e.position)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			var h: Dictionary = _hit_at(e.position)
			if not h.is_empty() and bool(h["enabled"]):
				on_alt_press(String(h["id"]))
			else:
				# A right click on nothing goes back, as Esc does.
				go_back()
		elif e.button_index == MOUSE_BUTTON_XBUTTON1:
			go_back()
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


## Back, as Esc does on this screen: by default the Esc key's own meaning, else its back or close button.
func go_back() -> void:
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	if on_key(esc):
		return
	for id in ["back", "close", "cancel"]:
		if press(id):
			return


## The shell's keys, in order: Enter on a button the keys picked presses it; then the screen's own keys; then the
## menu moves. True when the key was used.
func handle_key(e: InputEventKey) -> bool:
	var k: Key = e.keycode
	var enter: bool = k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE
	if nav_enabled and nav_focus and enter and press(hover_id):
		Sfx.play("ui_click")
		return true
	if on_key(e):
		return true
	if not nav_enabled:
		return false
	match k:
		KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
			var d := {KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN, KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT}
			return nav_move(d[k])
		KEY_TAB:
			return nav_step(-1 if e.shift_pressed else 1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if hover_id.is_empty():
				return nav_step(1)
			if press(hover_id):
				Sfx.play("ui_click")
				return true
		KEY_ESCAPE, KEY_BACKSPACE:
			go_back()
			return true
	return false


func _nav_live() -> Array:
	var out: Array = []
	for h in _hits:
		if bool(h["enabled"]) and not out.any(func(o: Dictionary) -> bool: return o["id"] == h["id"]):
			out.append(h)
	return out


## Tab order: the buttons in the order the screen drew them.
func nav_step(dir: int) -> bool:
	var live: Array = _nav_live()
	if live.is_empty():
		return false
	var i: int = -1
	for j in live.size():
		if live[j]["id"] == hover_id:
			i = j
	i = posmod(i + dir, live.size()) if i >= 0 else (0 if dir > 0 else live.size() - 1)
	_nav_to(live[i])
	return true


## The nearest button that way (straight on counts more than to the side); none picked yet: the first one.
func nav_move(dir: Vector2) -> bool:
	var live: Array = _nav_live()
	if live.is_empty():
		return false
	var cur: Dictionary = _hit_by_id(hover_id) if nav_focus or not hover_id.is_empty() else {}
	if cur.is_empty():
		_nav_to(live[0])
		return true
	var from: Vector2 = (cur["rect"] as Rect2).get_center()
	var best: Dictionary = {}
	var best_score: float = INF
	for h in live:
		if h["id"] == cur["id"]:
			continue
		var d: Vector2 = (h["rect"] as Rect2).get_center() - from
		var ahead: float = d.dot(dir)
		if ahead <= 1.0:
			continue
		var side: float = absf(d.dot(Vector2(-dir.y, dir.x)))
		var score: float = ahead + side * 2.5
		if score < best_score:
			best_score = score
			best = h
	if best.is_empty():
		return true
	_nav_to(best)
	return true


func _nav_to(h: Dictionary) -> void:
	nav_focus = true
	hover_id = String(h["id"])
	Sfx.play("ui_click", -12.0)
	on_hover(hover_id, (h["rect"] as Rect2).get_center())


## A scroll offset kept by name (a list's first row).
func scroll_of(name: String) -> int:
	return int(_scroll.get(name, 0))


func scroll_by(name: String, d: int, count: int, visible: int) -> void:
	_scroll[name] = clampi(scroll_of(name) + d, 0, maxi(0, count - visible))


func close() -> void:
	closed.emit()
