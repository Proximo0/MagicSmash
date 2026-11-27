class_name MerchantPanel
extends PanelBase
## The merchant of her field (docs/realm/economy.md part 2, "Merchants"; the gateway's ECON merchant calls in
## EconWire): BUY the six potions, embers and six pieces of COMMON gear of her level, each with a daily stock; SELL
## an item from the bag (a quarter of its value) or embers, a field's material or a trophy by the piece; BUY BACK
## what she sold in the last half hour (110% of what he paid); and set the BELT, the three potions she carries into
## a field (SET_BELT). His list and prices are the server's (MerchantList), read when the screen opens and after
## every purchase or sale.

const TAB_NAMES: Array[String] = ["BUY", "SELL", "BUY BACK", "BELT"]
const T_BUY: int = 0
const T_SELL: int = 1
const T_BACK: int = 2
const T_BELT: int = 3
## What the merchant pays for one of these stacks (realm/gateway economy prices.rs: EMBER_SELL, FIELD_MATERIAL_SELL,
## TROPHY_SELL), and the share of an item's value (NPC_BUY_PCT); the reply says what was paid.
const EMBER_SELL: int = 2
const MATERIAL_SELL: int = 3
const TROPHY_SELL: int = 150
const NPC_BUY_PCT: int = 25

var tab: int = T_BUY
var sel_item: int = 0
var sel_stack: int = -1
var belt_slot: int = 0
var last_result: String = ""
## The merchant's list (EconWire K_OFFERS) and what she may buy back (K_BUYBACKS).
var offers: Array = []
var buybacks: Array = []


func opened() -> void:
	title = "THE MERCHANT"
	read_offers()


## What he sells her today (and her buyback list).
func read_offers() -> void:
	var r: Dictionary = await shell.link.call_req(EconWire.hero_only(EconWire.Q_MERCHANT_LIST, shell.hero_id()))
	if not is_instance_valid(self):
		return
	if int(r["t"]) == EconWire.R_ECON and int(r.get("k", -1)) == EconWire.K_OFFERS:
		offers = r["offers"]
	var b: Dictionary = await shell.link.call_req(EconWire.hero_only(EconWire.Q_BUYBACK, shell.hero_id()))
	if is_instance_valid(self) and int(b["t"]) == EconWire.R_ECON and int(b.get("k", -1)) == EconWire.K_BUYBACKS:
		buybacks = b["buybacks"]


## What the merchant pays for an item (a quarter of its value, at least 1): the gateway's `npc_pays`.
static func pays_for(it: Dictionary) -> int:
	const RARITY_VALUE_MUL: Array[int] = [1, 2, 5, 14, 50]
	var value: int = (5 + 3 * int(it["level"])) * RARITY_VALUE_MUL[clampi(int(it["rarity"]), 0, 4)] * (100 + 25 * int(it.get("plus", 0))) / 100
	return maxi(maxi(value, 1) * NPC_BUY_PCT / 100, 1)


## What he pays for one of a stack kind, or 0 when he does not buy it.
static func pays_for_stack(kind: int) -> int:
	if kind == 1000:
		return EMBER_SELL
	if kind >= 1001 and kind <= 1006:
		return MATERIAL_SELL
	if kind >= 1010 and kind <= 1017:
		return TROPHY_SELL
	return 0


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
		T_BACK:
			_back(inner)
		T_BELT:
			_belt(inner)
	UiKit.text(self, Vector2(x, inner.end.y - 20), last_result, 13, UiKit.GOLD)
	# A piece of gear on offer shows its lines under the mouse.
	if hover_id.begins_with("offer:"):
		var o: Dictionary = _offer(int(hover_id.trim_prefix("offer:")))
		if not o.is_empty() and not (o["item"] as Dictionary).is_empty():
			item_tip(o["item"], mouse_pos + Vector2(16, 12))


func _offer_name(o: Dictionary) -> String:
	match int(o["kind"]):
		0, 1:
			return GameNames.stack_name(int(o["stack"]))
	return GameNames.item_name(o["item"])


func _buy(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y + 36
	if offers.is_empty():
		UiKit.text(self, Vector2(x, y + 10), "THE MERCHANT IS SETTING OUT HIS WARES...", 15, UiKit.BONE_DIM)
		return
	var col_w: float = (inner.size.x - 12.0) / 2.0
	for i in offers.size():
		var o: Dictionary = offers[i]
		var gear: bool = int(o["kind"]) == 2
		var row: int = i - 7 if gear else i
		var rx: float = x + (col_w + 12.0 if gear else 0.0)
		var ry: float = y + row * 46.0
		var r := Rect2(rx, ry, col_w, 42)
		draw_rect(r, Color(0.07, 0.058, 0.066))
		draw_rect(r, Color(UiKit.GOLD_DIM, 0.4), false, 1.0)
		var icon: Texture2D = UiArt.item_icon(int(o["item"]["gear_slot"]), 0, 30, int(o["item"].get("base", -1))) if gear else UiArt.stack_icon(int(o["stack"]), 30)
		draw_texture_rect(icon, Rect2(rx + 6, ry + 6, 30, 30), false)
		if gear:
			hit("offer:%d" % int(o["id"]), Rect2(rx + 6, ry + 6, 30, 30))
		UiKit.text(self, Vector2(rx + 44, ry + 3), _offer_name(o).left(28), 13, UiKit.BONE)
		var left: int = int(o["left"])
		UiKit.text(self, Vector2(rx + 44, ry + 22), "%s COIN   %d LEFT TODAY" % [GameNames.commas(int(o["price"])), left], 11, UiKit.GOLD if left > 0 else UiKit.BAD)
		var price: int = int(o["price"])
		var bx: float = r.end.x - (64.0 if gear else 128.0)
		button("buy:%d:1" % int(o["id"]), Rect2(bx, ry + 6, 58, 30), "BUY", left >= 1 and shell.coin() >= price and not busy, false, 12)
		if not gear:
			button("buy:%d:5" % int(o["id"]), Rect2(bx + 64, ry + 6, 58, 30), "x5", left >= 5 and shell.coin() >= price * 5 and not busy, false, 12)


func _sell(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y + 40
	UiKit.text(self, Vector2(x, y), "YOUR BAG", 13, UiKit.BONE_DIM)
	item_grid("it:", shell.items_at(GameNames.PLACE_BAG), Vector2(x, y + 22), 8, 5, 38.0, sel_item)
	var dx: float = x + 340
	var it: Dictionary = shell.item_by_id(sel_item)
	if it.is_empty() or int(it["place"]) != GameNames.PLACE_BAG:
		sel_item = 0
	var rows: Array[Array] = []
	for s in shell.stacks_at(GameNames.PLACE_BAG):
		if pays_for_stack(int(s[1])) > 0:
			rows.append(s)
	if sel_item != 0:
		UiKit.text(self, Vector2(dx, y + 10), GameNames.item_name(it), 18, GameNames.rarity_colour(int(it["rarity"])))
		UiKit.text(self, Vector2(dx, y + 36), "ITEM LEVEL %d  %s" % [int(it["level"]), GameNames.RARITIES[int(it["rarity"])]], 12, UiKit.BONE_DIM)
		UiKit.text(self, Vector2(dx, y + 60), "The merchant pays %s COIN." % GameNames.commas(pays_for(it)), 15, UiKit.GOLD)
		UiKit.text(self, Vector2(dx, y + 82), "The smith would give %d EMBERS for it." % GameNames.salvage_embers(it), 12, UiKit.BONE_DIM)
		button("sell", Rect2(dx, y + 106, 180, 34), "SELL", not busy, false, 16)
	else:
		UiKit.text(self, Vector2(dx, y + 10), "Choose an item, or embers and materials below.", 13, UiKit.BONE_DIM)
	var sy: float = y + 152
	UiKit.text(self, Vector2(dx, sy), "HE BUYS BY THE PIECE", 13, UiKit.BONE_DIM)
	stack_rows("stk:", rows, Vector2(dx, sy + 20), 300.0, 26.0, 5, sel_stack)
	if rows.is_empty():
		UiKit.text(self, Vector2(dx, sy + 24), "Nothing of that kind in your bag.", 12, UiKit.BONE_DIM)
	elif sel_stack >= 0 and shell.stack_count(GameNames.PLACE_BAG, sel_stack) > 0:
		var each: int = pays_for_stack(sel_stack)
		var have: int = shell.stack_count(GameNames.PLACE_BAG, sel_stack)
		UiKit.text(self, Vector2(dx + 310, sy + 22), "%d COIN EACH" % each, 12, UiKit.GOLD)
		button("sellstk:1", Rect2(dx + 310, sy + 42, 80, 28), "SELL 1", not busy, false, 12)
		button("sellstk:all", Rect2(dx + 396, sy + 42, 110, 28), "ALL: %s" % GameNames.commas(each * have), not busy, false, 12)


func _back(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y + 44
	UiKit.text(self, Vector2(x, y), "What you sold him in the last half hour, for a little more than he paid.", 13, UiKit.BONE_DIM)
	if buybacks.is_empty():
		UiKit.text(self, Vector2(x, y + 30), "Nothing to buy back.", 15, UiKit.BONE_DIM)
		return
	for i in mini(buybacks.size(), 7):
		var b: Dictionary = buybacks[i]
		var it: Dictionary = b["item"]
		var ry: float = y + 28 + i * 44.0
		var r := Rect2(x, ry, inner.size.x, 40)
		draw_rect(r, Color(0.07, 0.058, 0.066))
		draw_rect(r, Color(UiKit.GOLD_DIM, 0.4), false, 1.0)
		draw_texture_rect(UiArt.item_icon(int(it["gear_slot"]), int(it["rarity"]), 30, int(it.get("base", -1))), Rect2(x + 6, ry + 5, 30, 30), false)
		UiKit.text(self, Vector2(x + 44, ry + 4), GameNames.item_name(it), 14, GameNames.rarity_colour(int(it["rarity"])))
		UiKit.text(self, Vector2(x + 44, ry + 22), "%s LEFT" % NodePanel.span_text(int(b["secs_left"])), 11, UiKit.BONE_DIM)
		UiKit.text(self, Vector2(r.end.x - 150, ry + 12), "%s COIN" % GameNames.commas(int(b["price"])), 14, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		button("back:%d" % int(b["id"]), Rect2(r.end.x - 130, ry + 5, 120, 30), "BUY BACK", shell.coin() >= int(b["price"]) and not busy, false, 12)


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
			UiKit.text(self, r.position + Vector2(10, 28), "EMPTY", 15, UiKit.BONE_DIM)
		else:
			draw_texture_rect(UiArt.stack_icon(k, 32), Rect2(r.position + Vector2(10, 24), Vector2(32, 32)), false)
			UiKit.text(self, r.position + Vector2(50, 26), GameNames.stack_name(k), 14, UiKit.BONE)
			UiKit.text(self, r.position + Vector2(50, 44), "CARRY %d" % shell.stack_count(GameNames.PLACE_BAG, k), 11, UiKit.BONE_DIM)
	var py: float = y + 112
	UiKit.text(self, Vector2(x, py), "POTIONS IN YOUR BAG", 13, UiKit.BONE_DIM)
	var rows: Array[Array] = []
	for s in shell.stacks_at(GameNames.PLACE_BAG):
		if int(s[1]) >= 100 and int(s[1]) < 200:
			rows.append(s)
	stack_rows("pot:", rows, Vector2(x, py + 22), 400.0, 28.0, 6, -1)
	button("empty", Rect2(x + 430, py + 22, 160, 30), "EMPTY THE SLOT", int(belt[belt_slot]) != 0 and not busy, false, 12)
	if rows.is_empty():
		UiKit.text(self, Vector2(x, py + 26), "None. Buy some at the BUY tab.", 13, UiKit.BONE_DIM)


func press_body(id: String) -> void:
	if id.begins_with("tab:"):
		tab = int(id.trim_prefix("tab:"))
		last_result = ""
		if tab == T_BACK:
			read_offers()
	elif id.begins_with("buy:"):
		var p: PackedStringArray = id.split(":")
		_buy_offer(int(p[1]), int(p[2]))
	elif id.begins_with("it:"):
		sel_item = int(id.trim_prefix("it:"))
		sel_stack = -1
	elif id.begins_with("stk:"):
		sel_stack = int(id.trim_prefix("stk:"))
		sel_item = 0
	elif id == "sell":
		_sell_item()
	elif id.begins_with("sellstk:"):
		var have: int = shell.stack_count(GameNames.PLACE_BAG, sel_stack)
		_sell_stack(sel_stack, have if id.ends_with("all") else 1)
	elif id.begins_with("back:"):
		_buy_back(int(id.trim_prefix("back:")))
	elif id.begins_with("slot:"):
		belt_slot = int(id.trim_prefix("slot:"))
	elif id.begins_with("pot:"):
		_set_belt(int(id.trim_prefix("pot:")))
	elif id == "empty":
		_set_belt(0)


func _offer(id: int) -> Dictionary:
	for o in offers:
		if int(o["id"]) == id:
			return o
	return {}


func _buy_offer(id: int, n: int) -> void:
	var o: Dictionary = _offer(id)
	if o.is_empty():
		return
	var name: String = _offer_name(o)
	var cost: int = int(o["price"]) * n
	var r: Dictionary = await do(EconWire.merchant_buy(shell.hero_id(), id, n))
	if not is_instance_valid(self):
		return
	if int(r["t"]) == EconWire.R_ECON:
		last_result = "BOUGHT %d %s FOR %s COIN" % [n, name, GameNames.commas(cost)]
		say(last_result)
	await read_offers()


func _sell_item() -> void:
	var it: Dictionary = shell.item_by_id(sel_item)
	if it.is_empty():
		return
	var name: String = GameNames.item_name(it)
	var before: int = shell.coin()
	var r: Dictionary = await do(EconWire.merchant_sell(shell.hero_id(), sel_item, 0, 0))
	if not is_instance_valid(self):
		return
	if int(r["t"]) == EconWire.R_ECON:
		last_result = "SOLD %s FOR %s COIN" % [name, GameNames.commas(int(r["coin"]) - before)]
		sel_item = 0
		say(last_result)
	await read_offers()


func _sell_stack(kind: int, n: int) -> void:
	if kind < 0 or n <= 0:
		return
	var before: int = shell.coin()
	var r: Dictionary = await do(EconWire.merchant_sell(shell.hero_id(), 0, kind, n))
	if is_instance_valid(self) and int(r["t"]) == EconWire.R_ECON:
		last_result = "SOLD %s %s FOR %s COIN" % [GameNames.commas(n), GameNames.stack_name(kind), GameNames.commas(int(r["coin"]) - before)]
		say(last_result)
		if shell.stack_count(GameNames.PLACE_BAG, kind) == 0:
			sel_stack = -1


func _buy_back(entry: int) -> void:
	var r: Dictionary = await do(EconWire.with_id(EconWire.Q_BUYBACK_TAKE, shell.hero_id(), entry))
	if not is_instance_valid(self):
		return
	if int(r["t"]) == EconWire.R_ECON:
		last_result = "BOUGHT BACK"
		say(last_result)
	await read_offers()


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
