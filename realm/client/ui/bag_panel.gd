class_name BagPanel
extends PanelBase
## The bag: 40 slots, her stacks, and what she wears (six slots). Click an item to see it; EQUIP wears it (a worn
## item of that slot goes back to the bag first), an unequip button takes a worn one off. A hero wears gear up to
## her class level.

var sel_item: int = 0
var last_result: String = ""


func opened() -> void:
	title = "THE BAG"
	shell.refresh_inventory()


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y - 8
	UiKit.text(self, Vector2(x, y), "BAG  %d / %d" % [shell.items_at(GameNames.PLACE_BAG).size(), GameNames.BAG_SLOTS], 14, UiKit.GOLD)
	item_grid("it:", shell.items_at(GameNames.PLACE_BAG), Vector2(x, y + 22), 8, 5, 42.0, sel_item)
	var rows: Array[Array] = shell.stacks_at(GameNames.PLACE_BAG)
	stack_rows("stk:", rows, Vector2(x, y + 22 + 5 * 42.0 + 10), 334.0, 22.0, 6, -1, "stacks")
	# What she wears.
	var wx: float = x + 370
	UiKit.text(self, Vector2(wx, y), "WORN", 14, UiKit.GOLD)
	var worn: Dictionary = {}
	for it in shell.items_at(GameNames.PLACE_WORN):
		worn[int(it["slot"])] = it
	for s in 6:
		var r := Rect2(wx, y + 22 + s * 40.0, 450, 36)
		draw_rect(r, Color(0.065, 0.055, 0.065))
		draw_rect(r, Color(UiKit.GOLD_DIM, 0.35), false, 1.0)
		UiKit.text(self, r.position + Vector2(8, 9), GameNames.SLOTS[s], 11, UiKit.BONE_DIM)
		if worn.has(s):
			var it: Dictionary = worn[s]
			hit("wornit:%d" % int(it["id"]), Rect2(r.position + Vector2(70, 0), Vector2(250, 36)))
			draw_texture_rect(UiArt.item_icon(s, int(it["rarity"]), 28, int(it.get("base", -1))), Rect2(r.position + Vector2(72, 4), Vector2(28, 28)), false)
			UiKit.text(self, r.position + Vector2(108, 9), GameNames.item_name(it), 13, GameNames.rarity_colour(int(it["rarity"])))
			button("off:%d" % int(it["id"]), Rect2(r.end.x - 90, r.position.y + 4, 84, 28), "TAKE OFF", not busy, false, 11)
		else:
			UiKit.text(self, r.position + Vector2(108, 9), "Nothing", 12, Color(0.4, 0.38, 0.34))
	var it2: Dictionary = shell.item_by_id(sel_item)
	var by: float = y + 22 + 6 * 40.0 + 6
	if not it2.is_empty() and int(it2["place"]) == GameNames.PLACE_BAG:
		var lvl: int = int(shell.hero.get("level", 1))
		UiKit.text(self, Vector2(wx, by), GameNames.item_name(it2), 14, GameNames.rarity_colour(int(it2["rarity"])))
		var ok: bool = int(it2["level"]) <= lvl
		button("equip", Rect2(wx + 290, by - 4, 160, 30), "WEAR IT" if ok else "LEVEL %d NEEDED" % int(it2["level"]), ok and not busy, false, 12)
	UiKit.text(self, Vector2(x, inner.end.y - 14), last_result, 12, UiKit.GOLD)


func press_body(id: String) -> void:
	if id.begins_with("it:"):
		sel_item = int(id.trim_prefix("it:"))
	elif id.begins_with("off:"):
		var item: int = int(id.trim_prefix("off:"))
		var r: Dictionary = await do(GwWire.hero_item(GwWire.T_UNEQUIP, shell.hero_id(), item), "TAKEN OFF")
		if int(r["t"]) == GwWire.R_OK:
			last_result = "TAKEN OFF"
	elif id == "equip":
		await equip(sel_item)


func wheel_body(dir: int) -> void:
	scroll_by("stacks", dir, shell.stacks_at(GameNames.PLACE_BAG).size(), 6)


## Wears an item from the bag; the one already in that slot goes to the bag first.
func equip(item: int) -> Dictionary:
	var it: Dictionary = shell.item_by_id(item)
	if it.is_empty():
		return {}
	for w in shell.items_at(GameNames.PLACE_WORN):
		if int(w["slot"]) == int(it["gear_slot"]):
			var off: Dictionary = await do(GwWire.hero_item(GwWire.T_UNEQUIP, shell.hero_id(), int(w["id"])))
			if int(off["t"]) != GwWire.R_OK:
				return off
	var r: Dictionary = await do(GwWire.hero_item(GwWire.T_EQUIP, shell.hero_id(), item), "WORN: " + GameNames.item_name(it))
	if int(r["t"]) == GwWire.R_OK:
		last_result = "WORN: " + GameNames.item_name(it)
		sel_item = 0
	return r
