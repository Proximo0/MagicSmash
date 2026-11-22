class_name MerchantPanel
extends PanelBase
## The merchants: BUY potions for coin, SELL items from the bag (they pay little: the smith is where gear gains
## value), and set the BELT, the three potions a hero carries into a field. Buy and sell are the shell's additions
## to the gateway (T_BUY, T_SELL); the belt is SET_BELT.

const TAB_NAMES: Array[String] = ["BUY", "SELL", "BELT"]
const T_BUY: int = 0
const T_SELL: int = 1
const T_BELT: int = 2

var tab: int = T_BUY
var sel_item: int = 0
var belt_slot: int = 0
var last_result: String = ""


func opened() -> void:
	title = "THE MERCHANTS"


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y
	tabs(TAB_NAMES, tab, Vector2(x, y - 4), 104.0)
	UiKit.text(self, Vector2(inner.end.x, y), "%s COIN" % GameNames.commas(shell.coin()), 14, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	match tab:
		T_BUY:
			_buy(inner)
		T_SELL:
			_sell(inner)
		T_BELT:
			_belt(inner)
	UiKit.text(self, Vector2(x, inner.end.y - 20), last_result, 13, UiKit.GOLD)


func _buy(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y + 44
	for p in GameNames.POTIONS.size():
		var ry: float = y + p * 50.0
		var kind: int = 100 + p
		var r := Rect2(x, ry, inner.size.x, 44)
		draw_rect(r, Color(0.07, 0.058, 0.066))
		draw_rect(r, Color(UiKit.GOLD_DIM, 0.4), false, 1.0)
		draw_texture_rect(UiArt.stack_icon(kind, 32), Rect2(x + 6, ry + 6, 32, 32), false)
		UiKit.text(self, Vector2(x + 50, ry + 4), GameNames.POTIONS[p], 15, UiKit.BONE)
		UiKit.text(self, Vector2(x + 50, ry + 24), GameNames.POTION_NOTES[p], 12, UiKit.BONE_DIM)
		UiKit.text(self, Vector2(x + 380, ry + 14), "carry %d" % shell.stack_count(GameNames.PLACE_BAG, kind), 12, UiKit.BONE_DIM)
		var price: int = GameNames.POTION_PRICES[p]
		UiKit.text(self, Vector2(x + 500, ry + 14), "%d COIN" % price, 14, UiKit.GOLD)
		button("buy:%d:1" % p, Rect2(x + 600, ry + 6, 100, 32), "BUY 1", shell.coin() >= price and not busy, false, 13)
		button("buy:%d:5" % p, Rect2(x + 708, ry + 6, 100, 32), "BUY 5", shell.coin() >= price * 5 and not busy, false, 13)


func _sell(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y + 40
	UiKit.text(self, Vector2(x, y), "YOUR BAG", 13, UiKit.BONE_DIM)
	item_grid("it:", shell.items_at(GameNames.PLACE_BAG), Vector2(x, y + 22), 8, 5, 38.0, sel_item)
	var it: Dictionary = shell.item_by_id(sel_item)
	var dx: float = x + 340
	if it.is_empty() or int(it["place"]) != GameNames.PLACE_BAG:
		sel_item = 0
		UiKit.text(self, Vector2(dx, y + 20), "CHOOSE AN ITEM TO SELL", 15, UiKit.BONE_DIM)
		return
	UiKit.text(self, Vector2(dx, y + 10), GameNames.item_name(it), 18, GameNames.rarity_colour(int(it["rarity"])))
	UiKit.text(self, Vector2(dx, y + 36), "ITEM LEVEL %d  %s" % [int(it["level"]), GameNames.RARITIES[int(it["rarity"])]], 12, UiKit.BONE_DIM)
	UiKit.text(self, Vector2(dx, y + 64), "The merchant pays %s COIN." % GameNames.commas(GameNames.sell_price(it)), 15, UiKit.GOLD)
	UiKit.text(self, Vector2(dx, y + 86), "The smith would give %d EMBERS for it." % GameNames.salvage_embers(it), 12, UiKit.BONE_DIM)
	button("sell", Rect2(dx, y + 114, 180, 36), "SELL", not busy, false, 16)


func _belt(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y + 44
	UiKit.text(self, Vector2(x, y), "The three potions she takes into a field (keys 4 5 6). Choose a slot, then a potion.", 13, UiKit.BONE_DIM)
	var belt: Array = shell.hero.get("belt", [0, 0, 0])
	for s in 3:
		var r := Rect2(x + s * 270.0, y + 30, 250, 64)
		hit("slot:%d" % s, r)
		UiKit.frame(self, r, UiKit.GOLD if belt_slot == s else UiKit.GOLD_DIM, Color(0.08, 0.05, 0.05, 1.0) if belt_slot == s else Color(0.06, 0.05, 0.06, 1.0))
		var k: int = int(belt[s])
		UiKit.text(self, r.position + Vector2(10, 6), "SLOT %d" % (s + 1), 11, UiKit.BONE_DIM)
		if k == 0:
			UiKit.text(self, r.position + Vector2(10, 28), "empty", 15, UiKit.BONE_DIM)
		else:
			draw_texture_rect(UiArt.stack_icon(k, 32), Rect2(r.position + Vector2(10, 24), Vector2(32, 32)), false)
			UiKit.text(self, r.position + Vector2(50, 26), GameNames.stack_name(k), 14, UiKit.BONE)
			UiKit.text(self, r.position + Vector2(50, 44), "carry %d" % shell.stack_count(GameNames.PLACE_BAG, k), 11, UiKit.BONE_DIM)
	var py: float = y + 112
	UiKit.text(self, Vector2(x, py), "POTIONS IN YOUR BAG", 13, UiKit.BONE_DIM)
	var rows: Array[Array] = []
	for s in shell.stacks_at(GameNames.PLACE_BAG):
		if int(s[1]) >= 100 and int(s[1]) < 200:
			rows.append(s)
	stack_rows("pot:", rows, Vector2(x, py + 22), 400.0, 28.0, 6, -1)
	button("empty", Rect2(x + 430, py + 22, 160, 30), "EMPTY THE SLOT", int(belt[belt_slot]) != 0 and not busy, false, 12)
	if rows.is_empty():
		UiKit.text(self, Vector2(x, py + 26), "none: buy some at the BUY tab", 13, UiKit.BONE_DIM)


func press_body(id: String) -> void:
	if id.begins_with("tab:"):
		tab = int(id.trim_prefix("tab:"))
		last_result = ""
	elif id.begins_with("buy:"):
		var p: PackedStringArray = id.split(":")
		_buy_potion(int(p[1]), int(p[2]))
	elif id.begins_with("it:"):
		sel_item = int(id.trim_prefix("it:"))
	elif id == "sell":
		_sell_item()
	elif id.begins_with("slot:"):
		belt_slot = int(id.trim_prefix("slot:"))
	elif id.begins_with("pot:"):
		_set_belt(int(id.trim_prefix("pot:")))
	elif id == "empty":
		_set_belt(0)


func _buy_potion(p: int, n: int) -> void:
	var r: Dictionary = await do(GwWire.buy(shell.hero_id(), 100 + p, n))
	if int(r["t"]) == GwWire.R_SMITH:
		last_result = "BOUGHT %d %s FOR %d COIN" % [n, GameNames.POTIONS[p], int(r["amount"])]
		say(last_result)


func _sell_item() -> void:
	var it: Dictionary = shell.item_by_id(sel_item)
	if it.is_empty():
		return
	var name: String = GameNames.item_name(it)
	var r: Dictionary = await do(GwWire.hero_item(GwWire.T_SELL, shell.hero_id(), sel_item))
	if int(r["t"]) == GwWire.R_SMITH:
		last_result = "SOLD %s FOR %d COIN" % [name, int(r["amount"])]
		sel_item = 0
		say(last_result)


func _set_belt(kind: int) -> void:
	var belt: Array = (shell.hero.get("belt", [0, 0, 0]) as Array).duplicate()
	# A potion is in one slot only.
	for i in 3:
		if kind != 0 and int(belt[i]) == kind:
			belt[i] = 0
	belt[belt_slot] = kind
	var r: Dictionary = await do(GwWire.set_belt(shell.hero_id(), belt))
	if int(r["t"]) == GwWire.R_OK:
		last_result = "THE BELT IS SET"
