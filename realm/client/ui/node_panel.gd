class_name NodePanel
extends UiScreen
## A framed panel over the town built from real Control nodes (Button, ItemList, Tree, TabBar, LineEdit ...)
## under the one shared Theme (`UiTheme`), so a screen is worked by mouse, keyboard or controller alike: every
## control takes focus, the D-pad or arrows move it, accept presses, Esc or the controller's B (`ui_cancel`)
## closes. Subclasses fill `body` in `build()`. Each control that matters is registered under an id with
## `reg()`; `press(id)` (what the tests call) does what a click on it does, so a test drives the same nodes.

var title: String = ""
var frame_rect: Rect2 = Rect2(50, 30, 860, 480)
var busy: bool = false
var body: Control = null
var _close: Button = null
var _regs: Dictionary = {}


func opened() -> void:
	theme = UiTheme.shared()
	body = Control.new()
	body.position = frame_rect.position + Vector2(14, 56)
	body.size = frame_rect.size - Vector2(28, 70)
	add_child(body)
	_close = Button.new()
	_close.text = "X"
	_close.position = Vector2(frame_rect.end.x - 40, frame_rect.position.y + 8)
	_close.size = Vector2(30, 28)
	_close.focus_mode = Control.FOCUS_ALL
	_close.pressed.connect(close)
	add_child(_close)
	_regs["close"] = {"c": _close, "f": close}
	build()
	_focus_first.call_deferred()


## Override: add the screen's controls to `body` (its size is the frame's inside).
func build() -> void:
	pass


func _focus_first() -> void:
	var c: Control = _first_focusable(body)
	if c != null:
		c.grab_focus()
	else:
		_close.grab_focus()


func _first_focusable(n: Node) -> Control:
	for ch in n.get_children():
		if ch is Control:
			var c: Control = ch
			if c.visible and c.focus_mode == Control.FOCUS_ALL and not (c is Button and (c as Button).disabled):
				return c
			var d: Control = _first_focusable(c)
			if d != null:
				return d
	return null


func paint() -> void:
	draw_rect(Rect2(0, 0, UiKit.W, UiKit.H), Color(0, 0, 0, 0.62))
	UiKit.frame(self, frame_rect, UiKit.GOLD, Color(0.045, 0.036, 0.045, 0.98))
	# Clear of the close button on the right (and its twin space on the left).
	UiKit.title(self, Vector2(frame_rect.get_center().x, frame_rect.position.y + 10), title, UiKit.title_size(title, frame_rect.size.x - 100.0))


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and shell != null and shell.top() == self:
		close()
		get_viewport().set_input_as_handled()


func on_key(e: InputEventKey) -> bool:
	if e.keycode == KEY_ESCAPE:
		close()
		return true
	return false


# ---- registry (what tests and `press` use)

## Registers `ctrl` under `id`; `act` is what pressing it does (a Button's `pressed` is wired to it here).
func reg(id: String, ctrl: Control, act: Callable) -> void:
	_regs[id] = {"c": ctrl, "f": act}


func unreg_prefix(prefix: String) -> void:
	for k in _regs.keys():
		if String(k).begins_with(prefix):
			_regs.erase(k)


func has_hit(id: String) -> bool:
	if not _regs.has(id):
		return false
	var c: Control = _regs[id]["c"]
	return is_instance_valid(c) and _shown(c)


## True when `c` and every node between it and this panel is shown (the panel itself may sit on a hidden layer).
func _shown(c: Node) -> bool:
	var n: Node = c
	while n != null and n != self:
		if n is CanvasItem and not (n as CanvasItem).visible:
			return false
		n = n.get_parent()
	return n == self


func hit_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _regs:
		if has_hit(String(k)):
			out.append(String(k))
	return out


func press(id: String) -> bool:
	if not has_hit(id):
		return false
	var c: Control = _regs[id]["c"]
	if c is BaseButton and (c as BaseButton).disabled:
		return false
	(_regs[id]["f"] as Callable).call()
	return true


# ---- builders

func add_button(text: String, id: String, act: Callable, parent: Control = null, at: Vector2 = Vector2.ZERO, sz: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.position = at
	if sz != Vector2.ZERO:
		b.size = sz
	b.pressed.connect(act)
	(parent if parent != null else body).add_child(b)
	reg(id, b, act)
	return b


func label(text: String, at: Vector2, size: int = 14, col: Color = UiKit.BONE, width: float = 0.0, parent: Control = null) -> Label:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_override("font", UiKit.pick_font(size))
	l.add_theme_font_size_override("font_size", UiKit.px(size))
	l.add_theme_color_override("font_color", col)
	if width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(width, 0)
		l.size = Vector2(width, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else body).add_child(l)
	if width > 0.0:
		# A wrapping label keeps its width (set again once in the tree, where the theme's font sizes it).
		l.size = Vector2(width, l.get_minimum_size().y)
	return l


func item_list(at: Vector2, sz: Vector2, parent: Control = null) -> ItemList:
	var l := ItemList.new()
	l.position = at
	l.size = sz
	l.focus_mode = Control.FOCUS_ALL
	l.allow_reselect = true
	(parent if parent != null else body).add_child(l)
	return l


## Fills an ItemList with items (dictionaries as the wire decodes them): icon, name, tooltip. Each row's
## metadata is the item's id. Returns nothing.
func fill_items(list: ItemList, items: Array, icon: int = 28) -> void:
	list.clear()
	list.fixed_icon_size = Vector2i(icon, icon)
	for it in items:
		var i: int = list.add_item(item_label(it), UiArt.item_icon(int(it["gear_slot"]), int(it["rarity"]), icon, int(it.get("base", -1))))
		list.set_item_metadata(i, int(it["id"]))
		list.set_item_custom_fg_color(i, GameNames.rarity_colour(int(it["rarity"])))
		list.set_item_tooltip(i, item_tip_text(it))


func fill_stacks(list: ItemList, stacks: Array, icon: int = 22) -> void:
	list.clear()
	list.fixed_icon_size = Vector2i(icon, icon)
	for s in stacks:
		var kind: int = int(s[1]) if s.size() > 2 else int(s[0])
		var n: int = int(s[2]) if s.size() > 2 else int(s[1])
		var i: int = list.add_item("%s  %s" % [GameNames.stack_name(kind), GameNames.commas(n)], UiArt.stack_icon(kind, icon))
		list.set_item_metadata(i, kind)


static func item_label(it: Dictionary) -> String:
	return "%s  L%d" % [GameNames.item_name(it), int(it["level"])]


static func item_tip_text(it: Dictionary) -> String:
	var plus: int = int(it.get("plus", 0))
	var out: PackedStringArray = [GameNames.item_name(it), "ITEM LEVEL %d  %s  %s" % [int(it["level"]), GameNames.RARITIES[int(it["rarity"])], GameNames.SLOTS[int(it["gear_slot"])]]]
	for l in it["lines"]:
		out.append("+%d %s" % [int(l[1]) * (100 + 3 * plus) / 100, GameNames.STATS[int(l[0])]])
	var socketed: Array = it.get("socketed", [])
	for i in int(it["sockets"]):
		var k: int = int(socketed[i]) if i < socketed.size() else 0
		out.append("( empty socket )" if k == 0 else "[%s]" % GameNames.stack_name(k))
	if bool(it.get("bound", false)):
		out.append("BOUND: IT CANNOT BE GIVEN AWAY")
	return "\n".join(out)


## The metadata of the list's chosen row, or -1.
static func chosen(list: ItemList) -> int:
	var s: PackedInt32Array = list.get_selected_items()
	return int(list.get_item_metadata(s[0])) if s.size() > 0 else -1


## Runs a request through the shell (errors are shown in words), then reads her things again.
func do(req: Array, ok_text: String = "", refresh: bool = true) -> Dictionary:
	if busy:
		return {"t": GwWire.R_LOST, "msg": "busy"}
	busy = true
	var r: Dictionary = await shell.act(req, ok_text)
	if refresh and is_instance_valid(self):
		await shell.refresh_all()
	busy = false
	return r


## Wire time (unix ms) to words: "3H 12M".
static func span_text(secs: int) -> String:
	if secs <= 0:
		return "NOW"
	var d: int = secs / 86400
	var h: int = (secs % 86400) / 3600
	var m: int = (secs % 3600) / 60
	if d > 0:
		return "%dD %dH" % [d, h]
	if h > 0:
		return "%dH %dM" % [h, m]
	return "%dM %dS" % [m, secs % 60]
