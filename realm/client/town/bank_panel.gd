class_name BankPanel
extends PanelBase
## The bank: the account's chest, shared by every hero (100 slots a tab; the gateway's BANK_DEPOSIT and
## BANK_WITHDRAW). Click a thing in the bag or the bank, then MOVE (or right-click it to move it at once).
## Stacks (coin, embers, runes, potions) move 1, 10 or all at a time.

const BAG_COLS: int = 8
const BAG_CELL: float = 38.0
const BANK_COLS: int = 10
const BANK_CELL: float = 32.0
const BANK_PAGE_ROWS: int = 5
const TAB: int = 0

var sel_item: int = 0
var sel_kind: int = -1
var sel_place: int = 0
var qty: int = 1
var page: int = 0


func opened() -> void:
	title = "THE BANK"


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y
	UiKit.text(self, Vector2(x, y), "YOUR BAG", 14, UiKit.GOLD)
	item_grid("bagit:", shell.items_at(GameNames.PLACE_BAG), Vector2(x, y + 24), BAG_COLS, 5, BAG_CELL, sel_item if sel_place == GameNames.PLACE_BAG else 0)
	stack_rows("bstk:", shell.stacks_at(GameNames.PLACE_BAG), Vector2(x, y + 24 + 5 * BAG_CELL + 10), 304.0, 22.0, 6, sel_kind if sel_place == GameNames.PLACE_BAG else -1, "bag")
	var kx: float = inner.position.x + 400
	UiKit.text(self, Vector2(kx, y), "THE BANK", 14, UiKit.GOLD)
	var bank_items: Array[Dictionary] = []
	for it in shell.items_at(GameNames.PLACE_BANK):
		if int(it["tab"]) == TAB:
			var s: Dictionary = it.duplicate()
			s["slot"] = int(it["slot"]) - page * BANK_COLS * BANK_PAGE_ROWS
			if int(s["slot"]) >= 0:
				bank_items.append(s)
	item_grid("bankit:", bank_items, Vector2(kx, y + 24), BANK_COLS, BANK_PAGE_ROWS, BANK_CELL, sel_item if sel_place == GameNames.PLACE_BANK else 0)
	var pages: int = GameNames.BANK_SLOTS / (BANK_COLS * BANK_PAGE_ROWS)
	button("page", Rect2(kx + 336, y + 24, 80, 28), "PAGE %d/%d" % [page + 1, pages], true, false, 12)
	stack_rows("kstk:", shell.stacks_at(GameNames.PLACE_BANK), Vector2(kx, y + 24 + BANK_PAGE_ROWS * BANK_CELL + 10), 416.0, 22.0, 6, sel_kind if sel_place == GameNames.PLACE_BANK else -1, "bank")
	# The move bar.
	var by: float = inner.end.y - 34
	var has_sel: bool = sel_item != 0 or sel_kind >= 0
	var dir: String = "DEPOSIT" if sel_place == GameNames.PLACE_BAG else "WITHDRAW"
	button("move", Rect2(inner.position.x + 330, by, 160, 32), dir if has_sel else "CHOOSE A THING", has_sel and not busy, false, 15)
	if sel_kind >= 0:
		UiKit.text(self, Vector2(inner.position.x, by + 8), "HOW MANY", 12, UiKit.BONE_DIM)
		for i in 3:
			var q: int = [1, 10, 0][i]
			button("qty:%d" % q, Rect2(inner.position.x + 76 + i * 60, by, 54, 32), "ALL" if q == 0 else str(q), true, qty == q, 13)
	elif sel_item != 0:
		var it: Dictionary = shell.item_by_id(sel_item)
		if not it.is_empty():
			UiKit.text(self, Vector2(inner.position.x, by + 8), GameNames.item_name(it), 14, GameNames.rarity_colour(int(it["rarity"])))
	UiKit.text(self, Vector2(inner.end.x, by + 8), "%s COIN carried" % GameNames.commas(shell.coin()), 12, UiKit.BONE_DIM, HORIZONTAL_ALIGNMENT_RIGHT)


func press_body(id: String) -> void:
	if id.begins_with("bagit:"):
		_pick_item(int(id.trim_prefix("bagit:")), GameNames.PLACE_BAG)
	elif id.begins_with("bankit:"):
		_pick_item(int(id.trim_prefix("bankit:")), GameNames.PLACE_BANK)
	elif id.begins_with("bstk:"):
		_pick_stack(int(id.trim_prefix("bstk:")), GameNames.PLACE_BAG)
	elif id.begins_with("kstk:"):
		_pick_stack(int(id.trim_prefix("kstk:")), GameNames.PLACE_BANK)
	elif id.begins_with("qty:"):
		qty = int(id.trim_prefix("qty:"))
	elif id == "page":
		page = (page + 1) % (GameNames.BANK_SLOTS / (BANK_COLS * BANK_PAGE_ROWS))
	elif id == "move":
		move_selected()


func on_alt_press(id: String) -> void:
	press_body(id)
	if id.contains("it:") or id.contains("stk:"):
		move_selected()


func _pick_item(id: int, place: int) -> void:
	sel_item = id
	sel_kind = -1
	sel_place = place


func _pick_stack(kind: int, place: int) -> void:
	sel_kind = kind
	sel_item = 0
	sel_place = place


func wheel_body(dir: int) -> void:
	if hover_id.begins_with("kstk") or mouse_pos.x > frame_rect.position.x + 414:
		scroll_by("bank", dir, shell.stacks_at(GameNames.PLACE_BANK).size(), 6)
	else:
		scroll_by("bag", dir, shell.stacks_at(GameNames.PLACE_BAG).size(), 6)


## Moves what is chosen to the other side. Returns the gateway's reply.
func move_selected() -> Dictionary:
	var hero: int = shell.hero_id()
	var deposit: bool = sel_place == GameNames.PLACE_BAG
	var req: Array = []
	var what: String = ""
	if sel_item != 0:
		req = GwWire.bank(deposit, hero, sel_item, 0, 0, TAB)
		what = GameNames.item_name(shell.item_by_id(sel_item))
	elif sel_kind >= 0:
		var have: int = shell.stack_count(sel_place, sel_kind)
		var n: int = have if qty == 0 else mini(qty, have)
		if n <= 0:
			return {}
		req = GwWire.bank(deposit, hero, 0, sel_kind, n, TAB)
		what = "%s %s" % [GameNames.commas(n), GameNames.stack_name(sel_kind)]
	else:
		return {}
	sel_item = 0
	var r: Dictionary = await do(req, ("%s: %s" % ["DEPOSITED" if deposit else "TAKEN OUT", what]))
	if int(r["t"]) == GwWire.R_OK and sel_kind >= 0 and shell.stack_count(sel_place, sel_kind) == 0:
		sel_kind = -1
	return r
