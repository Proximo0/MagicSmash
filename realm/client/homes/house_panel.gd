class_name HousePanel
extends PanelBase
## A house: its two 10 x 10 rooms as a placement grid, the furniture in her bag, the carpenter, the visiting rule
## and the guestbook. Placing moves the item from her bag into the house (the store keeps one copy: nothing is
## made by placing), picking up moves it back. Visitors see the rooms and may sign the book.

const CELL: float = 34.0
const RECIPE_TABS: Array[String] = ["F1", "F2", "F3", "F4", "F5", "F6", "PLAQUES"]

var room: int = 0
## The chosen item: from her bag (in_house false) or from the house.
var selected: int = 0
var in_house: bool = false
var tab: int = 0
var recipes: Array[Dictionary] = []
var typing: bool = false
var text: String = ""
var last_result: String = ""


func opened() -> void:
	title = "THE HOUSE"
	var r: Dictionary = await shell.link.call_req(HomeWire.hero_only(HomeWire.Q_CATALOGUE, shell.hero_id()))
	if int(r["t"]) == HomeWire.R_HOME and int(r.get("k", -1)) == HomeWire.K_CATALOGUE:
		recipes = r["recipes"]
	await shell.refresh_all()
	await shell.refresh_house()


func _mine() -> bool:
	return bool(shell.house.get("mine", false))


func _house_items() -> Array:
	return shell.house.get("items", [])


func _item_at(cell: int) -> Dictionary:
	for it in _house_items():
		if int(it["slot"]) == cell:
			return it
	return {}


func _bag_things() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in shell.items_at(GameNames.PLACE_BAG):
		if HomeMap.is_thing(int(it["base"])):
			out.append(it)
	return out


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y
	var h: Dictionary = shell.house
	if h.is_empty():
		UiKit.text(self, Vector2(x, y), "You are not in a house.", 14, UiKit.BONE_DIM)
		return
	var nm: String = String(h["name"]) if not String(h["name"]).is_empty() else "THE HOUSE OF %s" % String(h["owner"])
	UiKit.text(self, Vector2(x, y), "%s  ·  DOOR %s" % [nm, HomeMap.RULE_NAMES[int(h["rule"])]], 14, UiKit.BONE)
	# The two rooms and the grid.
	var rooms: Array[String] = ["DOWNSTAIRS", "UPSTAIRS"]
	for i in 2:
		button("room:%d" % i, Rect2(x + i * 112.0, y + 24, 108, 26), rooms[i], true, i == room, 12)
	var go := Vector2(x, y + 58)
	for cy in HomeMap.GRID:
		for cx in HomeMap.GRID:
			var cell: int = HomeMap.cell_of(room, cx, cy)
			var r := Rect2(go + Vector2(cx, cy) * CELL, Vector2(CELL - 2, CELL - 2))
			hit("cell:%d:%d:%d" % [room, cx, cy], r, _mine())
			draw_rect(r, Color(0.07, 0.055, 0.045))
			var it: Dictionary = _item_at(cell)
			if not it.is_empty():
				HomeDraw.draw_thing(self, int(it["base"]), int(it["rarity"]), r.get_center(), CELL - 6.0)
			var sel: bool = not it.is_empty() and in_house and int(it["id"]) == selected
			draw_rect(r, UiKit.GOLD if sel else Color(UiKit.GOLD_DIM, 0.35), false, 2.0 if sel else 1.0)
			if hover_id == "cell:%d:%d:%d" % [room, cx, cy] and _mine():
				draw_rect(r, Color(1, 1, 1, 0.12))
	UiKit.text(self, Vector2(x, y + 58 + 10 * CELL + 2), last_result, 12, UiKit.GOLD)
	var rx: float = x + 372.0
	var rw: float = inner.end.x - rx
	if _mine():
		_mine_side(rx, y, rw)
	else:
		UiKit.text(self, Vector2(rx, y), "You are a visitor here.", 13, UiKit.BONE_DIM)
	_book(rx, y + (0.0 if not _mine() else 262.0), rw)


func _mine_side(rx: float, y: float, rw: float) -> void:
	UiKit.text(self, Vector2(rx, y), "FURNITURE IN YOUR BAG (CLICK, THEN A CELL)", 12, UiKit.GOLD)
	var things: Array[Dictionary] = _bag_things()
	for i in mini(things.size(), 4):
		var it: Dictionary = things[i]
		var r := Rect2(rx + (i % 2) * (rw / 2.0), y + 18 + (i / 2) * 24.0, rw / 2.0 - 4, 22)
		var id: String = "bag:%d" % int(it["id"])
		hit(id, r)
		var sel: bool = not in_house and int(it["id"]) == selected
		draw_rect(r, Color(0.1, 0.06, 0.06) if sel else Color(0.07, 0.06, 0.07))
		draw_rect(r, UiKit.GOLD if sel else Color(UiKit.GOLD_DIM, 0.3), false, 1.0)
		HomeDraw.draw_thing(self, int(it["base"]), int(it["rarity"]), r.position + Vector2(14, 11), 20.0)
		UiKit.text(self, r.position + Vector2(28, 3), HomeMap.thing_name(int(it["base"])), 11, UiKit.BONE)
	if things.is_empty():
		UiKit.text(self, Vector2(rx, y + 20), "None yet. The carpenter makes them.", 11, UiKit.BONE_DIM)
	button("pickup", Rect2(rx + rw - 150, y + 70, 150, 24), "PICK UP", in_house and selected != 0 and not busy, false, 12)
	# The carpenter.
	UiKit.text(self, Vector2(rx, y + 74), "THE CARPENTER", 12, UiKit.GOLD)
	for i in RECIPE_TABS.size():
		button("tab:%d" % i, Rect2(rx + i * 44.0, y + 98, 40 if i < 6 else 74, 22), RECIPE_TABS[i], true, i == tab, 11)
	var shown: Array[Dictionary] = _tab_recipes()
	for i in mini(shown.size(), 8):
		var rc: Dictionary = shown[i]
		var r2 := Rect2(rx + (i % 2) * (rw / 2.0), y + 126 + (i / 2) * 26.0, rw / 2.0 - 4, 24)
		var afford: bool = shell.stack_count(GameNames.PLACE_BAG, int(rc["material"])) >= int(rc["count"]) and shell.coin() >= int(rc["coin"])
		var label: String = "%s  %d %s %dc" % [_recipe_name(int(rc["kind"])), int(rc["count"]), GameNames.stack_name(int(rc["material"])).split(" ")[-1], int(rc["coin"])]
		button("craft:%d" % int(rc["kind"]), r2, label, afford and not busy, false, 10)
	# The door.
	UiKit.text(self, Vector2(rx, y + 232), "WHO MAY COME IN", 12, UiKit.GOLD)
	for i in 4:
		button("rule:%d" % i, Rect2(rx + i * 78.0 + 150, y + 228, 74, 22), HomeMap.RULE_NAMES[i], not busy, i == int(shell.house.get("rule", 0)), 11)


func _tab_recipes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rc in recipes:
		var k: int = int(rc["kind"])
		var t: int = 6 if k >= HomeMap.TROPHY_CRAFT else k / 4
		if t == tab:
			out.append(rc)
	return out


func _recipe_name(kind: int) -> String:
	if kind >= HomeMap.TROPHY_CRAFT:
		return "PLAQUE " + str(kind - HomeMap.TROPHY_CRAFT + 1)
	return HomeMap.FURNITURE[kind]


func _book(rx: float, y: float, rw: float) -> void:
	UiKit.text(self, Vector2(rx, y), "THE GUESTBOOK", 12, UiKit.GOLD)
	var book: Array = shell.house.get("book", [])
	for i in mini(book.size(), 3):
		var e: Dictionary = book[i]
		var r := Rect2(rx, y + 18 + i * 20.0, rw, 18)
		UiKit.text(self, r.position + Vector2(2, 1), "%s: %s" % [String(e["name"]), String(e["text"])], 11, UiKit.BONE)
		if _mine():
			button("wipe:%d" % int(e["id"]), Rect2(r.end.x - 44, r.position.y, 44, 18), "WIPE", not busy, false, 9)
	if book.is_empty():
		UiKit.text(self, Vector2(rx, y + 20), "No one has signed yet.", 11, UiKit.BONE_DIM)
	if not _mine():
		var box := Rect2(rx, y + 88, rw - 70, 24)
		hit("typebox", box)
		UiKit.frame(self, box, UiKit.GOLD if typing else UiKit.GOLD_DIM, Color(0.04, 0.035, 0.045, 0.9))
		var cur: String = "_" if typing and int(time * 2.0) % 2 == 0 else ""
		UiKit.text(self, box.position + Vector2(6, 4), (text + cur) if typing or not text.is_empty() else "CLICK AND WRITE A LINE", 12, UiKit.BONE if typing else UiKit.BONE_DIM)
		button("sign", Rect2(rx + rw - 64, y + 88, 64, 24), "SIGN", not text.strip_edges().is_empty() and not busy, false, 12)


func press_body(id: String) -> void:
	var hero: int = shell.hero_id()
	if id.begins_with("room:"):
		room = int(id.trim_prefix("room:"))
	elif id.begins_with("tab:"):
		tab = int(id.trim_prefix("tab:"))
	elif id.begins_with("bag:"):
		selected = int(id.trim_prefix("bag:"))
		in_house = false
	elif id.begins_with("cell:"):
		var p: PackedStringArray = id.split(":")
		await _cell(int(p[1]), int(p[2]), int(p[3]))
	elif id == "pickup":
		var r: Dictionary = await do(HomeWire.pickup(hero, selected))
		_done(r, "PICKED UP")
		selected = 0
		await shell.refresh_house()
	elif id.begins_with("craft:"):
		var k: int = int(id.trim_prefix("craft:"))
		var r2: Dictionary = await do(HomeWire.craft(hero, k))
		_done(r2, "MADE " + _recipe_name(k))
	elif id.begins_with("rule:"):
		var r3: Dictionary = await do(HomeWire.with_u8(HomeWire.Q_RULE, hero, int(id.trim_prefix("rule:"))))
		_done(r3, "DOOR SET")
		await shell.refresh_house()
	elif id.begins_with("wipe:"):
		var r4: Dictionary = await do(HomeWire.wipe(hero, int(id.trim_prefix("wipe:"))))
		_done(r4, "WIPED")
		await shell.refresh_house()
	elif id == "typebox":
		typing = true
	elif id == "sign":
		var r5: Dictionary = await do(HomeWire.sign_book(hero, text.strip_edges()))
		if _done(r5, "SIGNED"):
			text = ""
			typing = false
		await shell.refresh_house()


## Marks a reply: the message on success, false when the gateway refused.
func _done(r: Dictionary, ok_text: String) -> bool:
	if int(r.get("t", 0)) == HomeWire.R_HOME:
		last_result = ok_text
		return true
	last_result = ""
	return false


func _cell(r: int, cx: int, cy: int) -> void:
	var cell: int = HomeMap.cell_of(r, cx, cy)
	var here: Dictionary = _item_at(cell)
	var hero: int = shell.hero_id()
	if selected != 0 and not in_house:
		var res: Dictionary = await do(HomeWire.item_to(HomeWire.Q_PLACE, hero, selected, cell))
		if _done(res, "PLACED"):
			selected = 0
		await shell.refresh_house()
	elif selected != 0 and in_house and here.is_empty():
		var res2: Dictionary = await do(HomeWire.item_to(HomeWire.Q_MOVE, hero, selected, cell))
		_done(res2, "MOVED")
		await shell.refresh_house()
	elif not here.is_empty():
		selected = int(here["id"])
		in_house = true


func key_body(e: InputEventKey) -> bool:
	if not typing:
		return false
	if e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER:
		typing = false
		press_body("sign")
	elif e.keycode == KEY_BACKSPACE:
		text = text.left(maxi(0, text.length() - 1))
	elif e.unicode >= 32 and e.unicode != 127 and text.length() < 80:
		text += char(e.unicode)
	return true


func on_key(e: InputEventKey) -> bool:
	if typing and e.keycode == KEY_ESCAPE:
		typing = false
		return true
	return super(e)
