class_name SmithPanel
extends PanelBase
## The smith: SALVAGE an item for embers, UPGRADE it a step (+1 to +10, +3% to its lines a step; a failed step above
## +5 costs the embers, never the item), REROLL its lines, SOCKET a rune or a monster card into it (and take it out),
## and FUSE three runes into one of the next grade. The prices are the loot crate's (GameNames); the gateway charges.
## Works on what is in her bag: take gear off first.

const TAB_NAMES: Array[String] = ["SALVAGE", "UPGRADE", "REROLL", "SOCKET", "FUSE"]
const T_SALVAGE: int = 0
const T_UPGRADE: int = 1
const T_REROLL: int = 2
const T_SOCKET: int = 3
const T_FUSE: int = 4

var tab: int = T_SALVAGE
var sel_item: int = 0
var sel_rune: int = 0
var last_result: String = ""


func opened() -> void:
	title = "THE SMITH"


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y
	tabs(TAB_NAMES, tab, Vector2(x, y - 4), 104.0)
	UiKit.text(self, Vector2(inner.end.x, y), "%s EMBERS   %s COIN" % [GameNames.commas(shell.stack_count(GameNames.PLACE_BAG, GameNames.KIND_EMBERS)), GameNames.commas(shell.coin())], 13, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	if tab == T_FUSE:
		_fuse(inner)
		return
	UiKit.text(self, Vector2(x, y + 40), "YOUR BAG", 13, UiKit.BONE_DIM)
	item_grid("it:", shell.items_at(GameNames.PLACE_BAG), Vector2(x, y + 62), 8, 5, 38.0, sel_item)
	UiKit.text(self, Vector2(x, y + 62 + 5 * 38 + 6), "Worn gear is not shown: take it off first.", 11, UiKit.BONE_DIM)
	var it: Dictionary = shell.item_by_id(sel_item)
	if it.is_empty() or int(it["place"]) != GameNames.PLACE_BAG:
		sel_item = 0
		UiKit.text(self, Vector2(x + 340, y + 70), "CHOOSE AN ITEM", 16, UiKit.BONE_DIM)
		UiKit.text(self, Vector2(x + 340, y + 100), last_result, 13, UiKit.GOLD)
		return
	var dx: float = x + 340
	UiKit.text(self, Vector2(dx, y + 40), GameNames.item_name(it), 18, GameNames.rarity_colour(int(it["rarity"])))
	UiKit.text(self, Vector2(dx, y + 64), "ITEM LEVEL %d  %s  %s" % [int(it["level"]), GameNames.RARITIES[int(it["rarity"])], GameNames.SLOTS[int(it["gear_slot"])]], 12, UiKit.BONE_DIM)
	var ly: float = y + 86
	for l in it["lines"]:
		UiKit.text(self, Vector2(dx, ly), "+%d %s" % [int(l[1]) * (100 + 3 * int(it["plus"])) / 100, GameNames.STATS[int(l[0])]], 13, UiKit.BONE)
		ly += 18
	var embers: int = shell.stack_count(GameNames.PLACE_BAG, GameNames.KIND_EMBERS)
	var coin: int = shell.coin()
	var uy: float = y + 190
	match tab:
		T_SALVAGE:
			UiKit.text(self, Vector2(dx, uy), "Breaks it into %d EMBERS (runes and cards in it come out first)." % GameNames.salvage_embers(it), 13, UiKit.BONE)
			button("do", Rect2(dx, uy + 34, 180, 36), "SALVAGE", not busy, false, 16)
		T_UPGRADE:
			var c: Array = GameNames.upgrade_cost(it)
			if c.is_empty():
				UiKit.text(self, Vector2(dx, uy), "Already +10.", 14, UiKit.GOLD)
			else:
				var plus: int = int(it["plus"])
				UiKit.text(self, Vector2(dx, uy), "+%d to +%d" % [plus, plus + 1], 15, UiKit.GOLD)
				UiKit.text(self, Vector2(dx, uy + 24), "COSTS %d EMBERS AND %s COIN" % [int(c[0]), GameNames.commas(int(c[1]))], 13, UiKit.BONE if (embers >= int(c[0]) and coin >= int(c[1])) else UiKit.BAD)
				UiKit.text(self, Vector2(dx, uy + 44), "CHANCE %d%%%s" % [GameNames.upgrade_chance(it), "" if GameNames.upgrade_chance(it) == 100 else "  (A failure costs the embers, not the item.)"], 12, UiKit.BONE_DIM)
				button("do", Rect2(dx, uy + 70, 180, 36), "UPGRADE", not busy and embers >= int(c[0]) and coin >= int(c[1]), false, 16)
		T_REROLL:
			var c2: Array = GameNames.reroll_cost(it)
			UiKit.text(self, Vector2(dx, uy), "New lines, the same kind of item.", 13, UiKit.BONE)
			UiKit.text(self, Vector2(dx, uy + 24), "COSTS %d EMBERS AND %s COIN" % [int(c2[0]), GameNames.commas(int(c2[1]))], 13, UiKit.BONE if (embers >= int(c2[0]) and coin >= int(c2[1])) else UiKit.BAD)
			button("do", Rect2(dx, uy + 54, 180, 36), "REROLL", not busy and embers >= int(c2[0]) and coin >= int(c2[1]), false, 16)
		T_SOCKET:
			_socket_view(it, dx, uy - 10)
	UiKit.text(self, Vector2(dx, inner.end.y - 20), last_result, 13, UiKit.GOLD)


func _socket_view(it: Dictionary, dx: float, y: float) -> void:
	var n: int = int(it["sockets"])
	if n == 0:
		UiKit.text(self, Vector2(dx, y), "This item has no sockets (RARE and better do).", 13, UiKit.BONE_DIM)
		return
	var socketed: Array = it["socketed"]
	for s in n:
		var k: int = int(socketed[s]) if s < socketed.size() else 0
		var ry: float = y + s * 34.0
		UiKit.text(self, Vector2(dx, ry + 6), "SOCKET %d" % (s + 1), 12, UiKit.BONE_DIM)
		if k == 0:
			UiKit.text(self, Vector2(dx + 76, ry + 6), "empty", 13, UiKit.BONE_DIM)
			var can: bool = sel_rune != 0 and shell.stack_count(GameNames.PLACE_BAG, sel_rune) > 0 and shell.coin() >= GameNames.SOCKET_COIN_PER_LEVEL * int(it["level"])
			button("fill:%d" % s, Rect2(dx + 250, ry, 190, 28), "SET IN (%s COIN)" % GameNames.commas(GameNames.SOCKET_COIN_PER_LEVEL * int(it["level"])), can and not busy, false, 12)
		else:
			UiKit.text(self, Vector2(dx + 76, ry + 6), GameNames.stack_name(k), 13, UiKit.GOLD)
			button("take:%d" % s, Rect2(dx + 250, ry, 190, 28), "TAKE OUT (%s COIN)" % GameNames.commas(GameNames.UNSOCKET_COIN_PER_LEVEL * int(it["level"])), shell.coin() >= GameNames.UNSOCKET_COIN_PER_LEVEL * int(it["level"]) and not busy, false, 12)
	var sy: float = y + n * 34.0 + 8
	UiKit.text(self, Vector2(dx, sy), "RUNES AND CARDS YOU CARRY", 12, UiKit.BONE_DIM)
	var rows: Array[Array] = []
	for s in shell.stacks_at(GameNames.PLACE_BAG):
		if GameNames.is_socketable(int(s[1])):
			rows.append(s)
	stack_rows("rune:", rows, Vector2(dx, sy + 18), 440.0, 22.0, 4, sel_rune, "runes")


func _fuse(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y + 44
	UiKit.text(self, Vector2(x, y), "Three runes of a grade fuse into one of the next. The three are gone for good; grade I to II costs %d COIN, II to III %d COIN." % [GameNames.FUSE_COIN[0], GameNames.FUSE_COIN[1]], 13, UiKit.BONE_DIM)
	for stat in 6:
		var ry: float = y + 34 + stat * 46.0
		UiKit.text(self, Vector2(x, ry + 8), GameNames.STATS[stat], 15, UiKit.BONE)
		for g in 2:
			var kind: int = GameNames.rune_kind(stat, g + 1)
			var have: int = shell.stack_count(GameNames.PLACE_BAG, kind)
			var bx: float = x + 160 + g * 300.0
			UiKit.text(self, Vector2(bx, ry + 8), "%s  x%d" % [GameNames.stack_name(kind), have], 13, UiKit.GOLD if have >= GameNames.FUSE_COUNT else UiKit.BONE_DIM)
			button("fuse:%d:%d" % [stat, g + 1], Rect2(bx + 150, ry, 130, 30), "FUSE 3 > 1", have >= GameNames.FUSE_COUNT and shell.coin() >= GameNames.FUSE_COIN[g] and not busy, false, 12)
	UiKit.text(self, Vector2(x, inner.end.y - 20), last_result, 13, UiKit.GOLD)


func press_body(id: String) -> void:
	if id.begins_with("tab:"):
		tab = int(id.trim_prefix("tab:"))
		last_result = ""
	elif id.begins_with("it:"):
		sel_item = int(id.trim_prefix("it:"))
	elif id.begins_with("rune:"):
		sel_rune = int(id.trim_prefix("rune:"))
	elif id == "do":
		_do_step()
	elif id.begins_with("fill:"):
		_socket(int(id.trim_prefix("fill:")))
	elif id.begins_with("take:"):
		_unsocket(int(id.trim_prefix("take:")))
	elif id.begins_with("fuse:"):
		var p: PackedStringArray = id.split(":")
		_fuse_runes(int(p[1]), int(p[2]))


func wheel_body(dir: int) -> void:
	scroll_by("runes", dir, shell.stacks_at(GameNames.PLACE_BAG).size(), 4)


func _do_step() -> void:
	var hero: int = shell.hero_id()
	var it: Dictionary = shell.item_by_id(sel_item)
	if it.is_empty():
		return
	var name: String = GameNames.item_name(it)
	var req: Array = []
	match tab:
		T_SALVAGE:
			req = GwWire.hero_item(GwWire.T_SALVAGE, hero, sel_item)
		T_UPGRADE:
			req = GwWire.hero_item(GwWire.T_UPGRADE, hero, sel_item)
		T_REROLL:
			req = GwWire.hero_item(GwWire.T_REROLL, hero, sel_item)
	var r: Dictionary = await do(req)
	if int(r["t"]) != GwWire.R_SMITH:
		return
	match tab:
		T_SALVAGE:
			last_result = "%s BROKEN: %d EMBERS" % [name, int(r["amount"])]
			sel_item = 0
		T_UPGRADE:
			sel_item = int(r["item"])
			last_result = ("%s IS NOW +%d" % [name, int(r["plus"])]) if bool(r["success"]) else "THE STEP FAILED: %d EMBERS LOST" % int(r["amount"])
		T_REROLL:
			sel_item = int(r["item"])
			last_result = "%s HAS NEW LINES" % name
	say(last_result, tab == T_UPGRADE and not bool(r["success"]))


func _socket(s: int) -> void:
	var r: Dictionary = await do(GwWire.socket(shell.hero_id(), sel_item, s, sel_rune))
	if int(r["t"]) == GwWire.R_SMITH:
		last_result = "SET IN: %s (%d COIN)" % [GameNames.stack_name(sel_rune), int(r["amount"])]
		say(last_result)


func _unsocket(s: int) -> void:
	var r: Dictionary = await do(GwWire.unsocket(shell.hero_id(), sel_item, s))
	if int(r["t"]) == GwWire.R_SMITH:
		last_result = "TAKEN OUT (%d COIN)" % int(r["amount"])
		say(last_result)


func _fuse_runes(stat: int, grade: int) -> void:
	var r: Dictionary = await do(GwWire.fuse(shell.hero_id(), stat, grade))
	if int(r["t"]) == GwWire.R_SMITH:
		last_result = "FUSED: %s" % GameNames.stack_name(int(r["amount"]))
		say(last_result)
