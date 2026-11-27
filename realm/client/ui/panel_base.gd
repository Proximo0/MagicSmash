class_name PanelBase
extends UiScreen
## A framed panel over the town (a station, the sheet, the bag, the settings): a dim backdrop, a frame with a
## title and a close button, and the drawing helpers the panels share: an item grid, a list of stacks, the item
## tooltip. Esc closes. Subclasses draw their inside in `paint_body(inner)`.

var title: String = ""
var frame_rect: Rect2 = Rect2(50, 30, 860, 480)
var mouse_pos: Vector2 = Vector2.ZERO
var busy: bool = false


func paint() -> void:
	draw_rect(Rect2(0, 0, UiKit.W, UiKit.H), Color(0, 0, 0, 0.62))
	UiKit.frame(self, frame_rect, UiKit.GOLD, Color(0.045, 0.036, 0.045, 0.98))
	# Clear of the close button on the right (and its twin space on the left).
	UiKit.title(self, Vector2(frame_rect.get_center().x, frame_rect.position.y + 10), title, UiKit.title_size(title, frame_rect.size.x - 100.0))
	# The swallow: nothing behind the frame is clickable. Registered before the X so the X (the later hit) wins.
	hit("swallow", frame_rect)
	button("close", Rect2(frame_rect.end.x - 40, frame_rect.position.y + 8, 30, 28), "X", true, false, 14)
	paint_body(Rect2(frame_rect.position + Vector2(14, 56), frame_rect.size - Vector2(28, 70)))
	_tooltip()


func paint_body(_inner: Rect2) -> void:
	pass


func on_press(id: String) -> void:
	if id == "close":
		close()
		return
	press_body(id)


func press_body(_id: String) -> void:
	pass


func on_hover(_id: String, pos: Vector2) -> void:
	mouse_pos = pos


func on_key(e: InputEventKey) -> bool:
	if e.keycode == KEY_ESCAPE:
		close()
		return true
	return key_body(e)


func key_body(_e: InputEventKey) -> bool:
	return false


## Runs a request through the shell (errors are shown), then reads her things again.
func do(req: Array, ok_text: String = "") -> Dictionary:
	if busy:
		return {"t": GwWire.R_LOST, "msg": "busy"}
	busy = true
	var r: Dictionary = await shell.act(req, ok_text)
	await shell.refresh_all()
	busy = false
	return r


# ---- helpers

## Draws `items` (already filtered to one place) in a grid by their slot; registers "<prefix><id>" hits. Returns nothing.
func item_grid(prefix: String, items: Array[Dictionary], origin: Vector2, cols: int, rows: int, cell: float, selected: int = 0) -> void:
	for i in cols * rows:
		var r := Rect2(origin + Vector2(i % cols, i / cols) * cell, Vector2(cell - 2, cell - 2))
		draw_rect(r, Color(0.06, 0.05, 0.06))
		draw_rect(r, Color(UiKit.GOLD_DIM, 0.35), false, 1.0)
	for it in items:
		var slot: int = int(it["slot"])
		if slot >= cols * rows:
			continue
		var r := Rect2(origin + Vector2(slot % cols, slot / cols) * cell, Vector2(cell - 2, cell - 2))
		var id: String = prefix + str(int(it["id"]))
		hit(id, r)
		var col: Color = GameNames.rarity_colour(int(it["rarity"]))
		draw_texture_rect(UiArt.item_icon(int(it["gear_slot"]), int(it["rarity"]), 32, int(it.get("base", -1))), r.grow(-2), false)
		draw_rect(r, col if int(it["id"]) != selected else UiKit.GOLD, false, 2.0 if int(it["id"]) == selected else 1.0)
		if int(it.get("plus", 0)) > 0:
			UiKit.text(self, r.end - Vector2(3, 13), "+%d" % int(it["plus"]), 10, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		if hover_id == id:
			draw_rect(r, Color(1, 1, 1, 0.1))


## A list of stacks (kind, count) with icons; "<prefix><kind>" hits. Returns the y after the last row.
func stack_rows(prefix: String, stacks: Array[Array], origin: Vector2, width: float, row_h: float, max_rows: int, selected: int = -1, scroll_name: String = "") -> float:
	var first: int = scroll_of(scroll_name) if not scroll_name.is_empty() else 0
	var y: float = origin.y
	for i in range(first, mini(stacks.size(), first + max_rows)):
		var s: Array = stacks[i]
		var kind: int = int(s[1])
		var r := Rect2(origin.x, y, width, row_h - 2)
		var id: String = prefix + str(kind)
		hit(id, r)
		draw_rect(r, Color(0.1, 0.06, 0.06) if kind == selected else (Color(0.1, 0.085, 0.09) if hover_id == id else Color(0.065, 0.055, 0.065)))
		draw_rect(r, UiKit.GOLD if kind == selected else Color(UiKit.GOLD_DIM, 0.3), false, 1.0)
		draw_texture_rect(UiArt.stack_icon(kind, 20), Rect2(r.position + Vector2(3, 1), Vector2(row_h - 6, row_h - 6)), false)
		UiKit.text(self, r.position + Vector2(row_h + 2, (row_h - 15) / 2.0 - 1), GameNames.stack_name(kind), 12, UiKit.BONE)
		UiKit.text(self, Vector2(r.end.x - 6, r.position.y + (row_h - 15) / 2.0 - 1), GameNames.commas(int(s[2])), 12, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		y += row_h
	if not scroll_name.is_empty() and stacks.size() > max_rows:
		UiKit.text(self, Vector2(origin.x + width, y), "%d-%d of %d (wheel)" % [first + 1, mini(stacks.size(), first + max_rows), stacks.size()], 10, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	return y


func on_wheel(dir: int, _pos: Vector2) -> void:
	wheel_body(dir)


func wheel_body(_dir: int) -> void:
	pass


## The tooltip of the item under the mouse.
func _tooltip() -> void:
	var tip: Dictionary = {}
	# Every item hit id holds "it:" (it:, bagit:, bankit:, wornit:); a stack's never does.
	if hover_id.contains("it:"):
		var idx: int = hover_id.rfind(":")
		tip = shell.item_by_id(int(hover_id.substr(idx + 1)))
	if tip.is_empty():
		return
	item_tip(tip, mouse_pos + Vector2(16, 12))


func item_tip(it: Dictionary, at: Vector2) -> void:
	var lines: Array[Array] = []
	lines.append([GameNames.item_name(it), 15, GameNames.rarity_colour(int(it["rarity"]))])
	lines.append(["ITEM LEVEL %d  %s  %s" % [int(it["level"]), GameNames.RARITIES[int(it["rarity"])], GameNames.SLOTS[int(it["gear_slot"])]], 11, UiKit.BONE_DIM])
	var plus: int = int(it.get("plus", 0))
	for l in it["lines"]:
		var pts: int = int(l[1]) * (100 + 3 * plus) / 100
		lines.append(["+%d %s" % [pts, GameNames.STATS[int(l[0])]], 13, UiKit.BONE])
	var socketed: Array = it.get("socketed", [])
	for i in int(it["sockets"]):
		var k: int = int(socketed[i]) if i < socketed.size() else 0
		if k == 0:
			lines.append(["( empty socket )", 12, UiKit.BONE_DIM])
		else:
			var sp: Array = GameNames.socket_points(k)
			lines.append(["[%s] +%d %s" % [GameNames.stack_name(k), int(sp[1]), GameNames.STATS[int(sp[0])]], 12, UiKit.GOLD])
	var w: float = 150.0
	for l in lines:
		w = maxf(w, UiKit.text_width(String(l[0]), int(l[1])) + 20.0)
	var h: float = 12.0
	for l in lines:
		h += int(l[1]) + 5.0
	var r := Rect2(at, Vector2(w, h))
	if r.end.x > UiKit.W - 4:
		r.position.x = UiKit.W - 4 - w
	if r.end.y > UiKit.H - 4:
		r.position.y = UiKit.H - 4 - h
	UiKit.frame(self, r, GameNames.rarity_colour(int(it["rarity"])), Color(0.03, 0.025, 0.03, 0.98))
	var y: float = r.position.y + 6.0
	for l in lines:
		UiKit.text(self, Vector2(r.position.x + 10, y), String(l[0]), int(l[1]), l[2])
		y += int(l[1]) + 5.0


## The button row of tabs: ids "tab:<i>".
func tabs(names: Array[String], current: int, origin: Vector2, w: float = 110.0) -> void:
	for i in names.size():
		button("tab:%d" % i, Rect2(origin + Vector2(i * (w + 6.0), 0), Vector2(w, 28)), names[i], true, i == current, 13)
