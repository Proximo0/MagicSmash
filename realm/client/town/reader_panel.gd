class_name ReaderPanel
extends PanelBase
## The card reader: her deck of up to twenty different cards (the store keeps each once), chosen from the cards she
## owns. A field level draws three of them (the mage four) and she picks one; a card picked again in the field adds
## its effect again, up to five copies. A NOVICE owns the first twelve; each even class level to 24
## adds one; the rest are found as pages (bag) that she learns here. SET THE DECK saves it (the gateway's SET_DECK).

const COLS: int = 3
const ROWS: int = 10
const COL_W: float = 272.0
const ROW_H: float = 22.0
const ROMAN: Array[String] = ["0", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX", "XXI", "XXII", "XXIII", "XXIV", "XXV", "XXVI", "XXVII", "XXVIII", "XXIX", "XXX"]

var deck: Array[int] = []
var focus: int = 0
var dirty: bool = false
var last_result: String = ""


func opened() -> void:
	title = "THE CARD READER"
	_load_deck()


func _load_deck() -> void:
	deck.clear()
	for c in shell.hero.get("deck", []):
		deck.append(int(c))
	dirty = false


func owned(card: int) -> bool:
	return shell.cards.has(card)


func copies(card: int) -> int:
	return deck.count(card)


func unlock_note(card: int) -> String:
	if card < GameNames.NOVICE_CARDS:
		return "Owned from the start"
	if card < GameNames.NOVICE_CARDS + 12:
		return "At class level %d, or from its page" % (2 * (card - GameNames.NOVICE_CARDS + 1))
	return "Found as a page (elites drop them, a boss's first kill gives one)"


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y
	UiKit.text(self, Vector2(x, y - 6), "THE CARDS (click to put in, or take out)", 12, UiKit.BONE_DIM)
	UiKit.text(self, Vector2(inner.end.x, y - 6), "DECK %d / %d" % [deck.size(), GameNames.DECK_SIZE], 13, UiKit.GOLD if deck.size() == GameNames.DECK_SIZE else UiKit.BONE, HORIZONTAL_ALIGNMENT_RIGHT)
	for c in GameNames.DECK_CARDS:
		var col: int = c / ROWS
		var row: int = c % ROWS
		var r := Rect2(x + col * COL_W, y + 14 + row * ROW_H, COL_W - 8, ROW_H - 2)
		var id: String = "card:%d" % c
		hit(id, r)
		var has: bool = owned(c)
		var n: int = copies(c)
		draw_rect(r, Color(0.1, 0.06, 0.07) if focus == c else (Color(0.09, 0.08, 0.09) if hover_id == id else Color(0.06, 0.05, 0.06)))
		draw_rect(r, UiKit.GOLD if focus == c else Color(UiKit.GOLD_DIM, 0.35), false, 1.0)
		var tc: Color = UiKit.BONE if has else Color(0.35, 0.33, 0.3)
		UiKit.text(self, r.position + Vector2(6, 2), ROMAN[c + 1], 11, UiKit.GOLD_DIM if has else Color(0.3, 0.28, 0.25), HORIZONTAL_ALIGNMENT_LEFT)
		UiKit.text(self, r.position + Vector2(48, 2), GameNames.card_name(c), 12, tc)
		if n > 0:
			UiKit.text(self, Vector2(r.end.x - 6, r.position.y + 2), "IN DECK", 11, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		elif not has:
			UiKit.text(self, Vector2(r.end.x - 6, r.position.y + 2), "locked", 10, Color(0.4, 0.3, 0.3), HORIZONTAL_ALIGNMENT_RIGHT)
	# The spread: the deck as cards in a row.
	var sy: float = y + 14 + ROWS * ROW_H + 14
	UiKit.text(self, Vector2(x, sy - 16), "YOUR DECK (click a card to take it out)", 12, UiKit.BONE_DIM)
	for i in GameNames.DECK_SIZE:
		var r := Rect2(x + i * 41.5, sy, 38, 56)
		if i < deck.size():
			var id: String = "slot:%d" % i
			hit(id, r)
			UiKit.frame(self, r, UiKit.GOLD if hover_id == id else UiKit.GOLD_DIM, Color(0.1, 0.045, 0.05, 1.0))
			UiKit.text(self, r.position + Vector2(19, 3), ROMAN[deck[i] + 1], 10, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
			UiKit.rune(self, r.position + Vector2(12, 18), deck[i], 14.0, Color(UiKit.GOLD, 0.8), 1.0)
		else:
			draw_rect(r, Color(0.05, 0.045, 0.05))
			draw_rect(r, Color(UiKit.GOLD_DIM, 0.25), false, 1.0)
	# What she is looking at.
	var dy: float = sy + 64
	UiKit.text(self, Vector2(x, dy), "%s: %s" % [GameNames.card_name(focus), GameNames.CARD_TEXT[focus]], 14, UiKit.GOLD)
	var how: String = ("Owned, in the deck" if copies(focus) > 0 else "Owned, not in the deck") if owned(focus) else unlock_note(focus)
	UiKit.text(self, Vector2(x, dy + 20), how, 12, UiKit.BONE_DIM)
	button("save", Rect2(inner.end.x - 200, dy - 2, 200, 34), "SET THE DECK" if dirty else "DECK IS SET", dirty and not busy and not deck.is_empty(), dirty, 15)
	button("clear", Rect2(inner.end.x - 310, dy - 2, 100, 34), "CLEAR", not deck.is_empty(), false, 13)
	# Pages she carries.
	var pages: Array[Array] = []
	for s in shell.stacks_at(GameNames.PLACE_BAG):
		var k: int = int(s[1])
		if k >= 4000 and k < 5000:
			pages.append(s)
	if not pages.is_empty():
		var p: Array = pages[0]
		var card: int = int(p[1]) - 4000
		UiKit.text(self, Vector2(x + 440, dy + 20), "%s x%d" % [GameNames.stack_name(int(p[1])), int(p[2])], 12, UiKit.BONE)
		button("learn", Rect2(x + 600, dy + 14, 80, 26), "LEARN", not owned(card) and not busy, false, 12)
	UiKit.text(self, Vector2(x, inner.end.y - 14), last_result, 12, UiKit.GOLD)


func press_body(id: String) -> void:
	if id.begins_with("card:"):
		var c: int = int(id.trim_prefix("card:"))
		focus = c
		if not owned(c):
			return
		if copies(c) > 0:
			deck.erase(c)
			dirty = true
		elif deck.size() >= GameNames.DECK_SIZE:
			say("THE DECK IS FULL: %d CARDS" % GameNames.DECK_SIZE, true)
		else:
			deck.append(c)
			deck.sort()
			dirty = true
	elif id.begins_with("slot:"):
		deck.remove_at(int(id.trim_prefix("slot:")))
		dirty = true
	elif id == "clear":
		deck.clear()
		dirty = true
	elif id == "save":
		_save()
	elif id == "learn":
		_learn()


func _save() -> void:
	var r: Dictionary = await do(GwWire.set_deck(shell.hero_id(), deck), "THE DECK IS SET")
	if int(r["t"]) == GwWire.R_OK:
		last_result = "THE DECK IS SET: %d CARDS" % deck.size()
		_load_deck()


func _learn() -> void:
	for s in shell.stacks_at(GameNames.PLACE_BAG):
		var k: int = int(s[1])
		if k >= 4000 and k < 5000:
			var r: Dictionary = await do(GwWire.learn_page(shell.hero_id(), k - 4000))
			if int(r["t"]) == GwWire.R_OK:
				last_result = "LEARNED %s" % GameNames.card_name(k - 4000)
				say(last_result)
			return
