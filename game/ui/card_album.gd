class_name CardAlbum
extends RefCounted
## The card album: every monster card (Cards), found or not, and the three equipment sockets. Pick a found card
## and press confirm to socket it into its hat, robe or staff socket (or take it out again). Socketed cards
## power every run the player hosts. Opened from the title menu; the Sanctum's altar opens it too. The grid shows
## PAGE cards at a time; the page follows the cursor (left/right run on across pages, up/down move a row), and the
## page mark at the top right ("< PAGE 1/2 >") turns the page when its arrows are tapped or clicked.

const COLS := 6
const CARD := Vector2(50, 76)
const GAP := 7.0
const GRID := Vector2(126, 32)
const SOCKET_RECT := Rect2(12, 32, 104, 158)
## Cards on one page: two rows of COLS, which fill the grid above the info panel.
const PAGE := 12
## The page mark and its two arrows (tap or click to turn the page).
const PAGE_MARK := Rect2(330, 12, 84, 13)
const PAGE_PREV := Rect2(330, 10, 16, 17)
const PAGE_NEXT := Rect2(398, 10, 16, 17)

var sel: int = 0
var _cells: Array[Rect2] = []


func open() -> void:
	sel = 0


@warning_ignore("integer_division")
static func pages() -> int:
	return (Cards.count() + PAGE - 1) / PAGE


@warning_ignore("integer_division")
func page() -> int:
	return sel / PAGE


## The cell of card `i` on its own page.
func _cell(i: int) -> Rect2:
	@warning_ignore("integer_division")
	var row: int = (i % PAGE) / COLS
	return Rect2(GRID + Vector2((i % COLS) * (CARD.x + GAP), row * (CARD.y + 8)), CARD)


func draw(ci: CanvasItem, t: float) -> void:
	var prof: Profile = Save.profile
	if not Still.draw_scene(ci, "album"):
		ci.draw_rect(Rect2(0, 0, 480, 270), Color(0.02, 0.0, 0.05, 0.92))
	Occult.frame(ci, Rect2(4, 4, 472, 262), t)
	Still.draw_scene(ci, "album", Still.SCENE_INNER)
	PixelFont.draw_centered(ci, "THE CARD ALBUM", 240, 12, 2, Occult.GOLD, Occult.INK)
	PixelFont.draw(ci, "%d / %d" % [prof.cards_owned(), Cards.count()], Vector2(420, 16), 1, Occult.BONE, Occult.INK)
	# Sockets.
	Occult.frame(ci, SOCKET_RECT, t)
	PixelFont.draw_centered(ci, "SOCKETS", SOCKET_RECT.get_center().x, SOCKET_RECT.position.y + 6, 1, Occult.GOLD, Occult.INK)
	var socketed := prof.socket_indices()
	for s: int in range(Cards.SOCKETS):
		var y := SOCKET_RECT.position.y + 22 + s * 44
		var col: Color = MonsterCard.SOCKET_COLORS[s]
		var box := Rect2(SOCKET_RECT.position.x + 8, y, SOCKET_RECT.size.x - 16, 38)
		ci.draw_rect(box, Color(col, 0.08))
		ci.draw_rect(box, Color(col, 0.6), false, 1.0)
		PixelFont.draw(ci, Cards.SOCKET_NAMES[s], box.position + Vector2(4, 4), 1, col, Occult.INK)
		var idx: int = socketed[s]
		if idx >= 0:
			PixelFont.draw(ci, Cards.card_name(idx).trim_prefix("THE "), box.position + Vector2(4, 16), 1, Color.WHITE, Occult.INK)
			PixelFont.draw(ci, Cards.bonus_text(idx), box.position + Vector2(4, 26), 1, Color("5dff7a"), Occult.INK)
		else:
			PixelFont.draw(ci, "EMPTY", box.position + Vector2(4, 16), 1, Color(1, 1, 1, 0.3), Occult.INK)
	# The page mark: the page shown, with arrows while there is another page that way.
	var pg := page()
	PixelFont.draw_centered(ci, "PAGE %d/%d" % [pg + 1, pages()], PAGE_MARK.get_center().x, PAGE_MARK.position.y + 4, 1,
		Occult.GOLD, Occult.INK)
	if pages() > 1:
		var blink := 0.6 + 0.4 * sin(t * 5.0)
		PixelFont.draw(ci, "<", PAGE_PREV.position + Vector2(4, 6), 1, Color(1, 1, 1, blink), Occult.INK)
		PixelFont.draw(ci, ">", PAGE_NEXT.position + Vector2(7, 6), 1, Color(1, 1, 1, blink), Occult.INK)
	# The grid: this page's cards. _cells holds them in card order from the page's first.
	_cells.clear()
	for i: int in range(pg * PAGE, mini(Cards.count(), (pg + 1) * PAGE)):
		var r := _cell(i)
		_cells.append(r)
		var found := prof.card_count(i) > 0
		MonsterCard.draw(ci, r, i, found, t, 0.6 if i == sel and found else 0.0, false)
		if socketed.has(i):
			ci.draw_rect(Rect2(r.end.x - 9, r.position.y - 3, 9, 9), MonsterCard.SOCKET_COLORS[Cards.socket(i)])
			ci.draw_rect(Rect2(r.end.x - 9, r.position.y - 3, 9, 9), Occult.INK, false, 1.0)
		if prof.card_count(i) > 1:
			var many := "x%d" % prof.card_count(i)
			PixelFont.draw_centered(ci, many, r.get_center().x, r.end.y - 11, 1, Occult.BONE, Occult.INK)
		if i == sel:
			var pulse := 0.5 + 0.5 * sin(t * 6.0)
			ci.draw_rect(r.grow(2), Color(Occult.GOLD, 0.6 + 0.4 * pulse), false, 1.0)
	# The picked card.
	var info := Rect2(126, 202, 342, 56)
	Occult.frame(ci, info, t)
	if prof.card_count(sel) > 0:
		PixelFont.draw(ci, Cards.card_name(sel), info.position + Vector2(8, 7), 1, Occult.GOLD, Occult.INK)
		PixelFont.draw(ci, Cards.bonus_text(sel) + "   (" + Cards.SOCKET_NAMES[Cards.socket(sel)] + ")",
			info.position + Vector2(8, 18), 1, Color("5dff7a"), Occult.INK)
		PixelFont.draw(ci, Cards.lore(sel), info.position + Vector2(8, 29), 1, Color("c9b8ff"), Occult.INK)
		var act := "ENTER/A: TAKE OUT" if socketed.has(sel) else "ENTER/A: SOCKET"
		PixelFont.draw(ci, act + "    ESC/B: BACK", info.position + Vector2(8, 42), 1, Color(1, 1, 1, 0.5), Occult.INK)
	else:
		PixelFont.draw(ci, "AN UNKNOWN CARD", info.position + Vector2(8, 7), 1, Color(Occult.GOLD, 0.5), Occult.INK)
		var seal := Seals.of_card(sel)
		var hint := "SOME MONSTER CARRIES IT. VERY FEW EVER DROP." if seal < Seals.MIN else \
			"THE ARCHLICH OF %s CARRIES IT. WIN THAT SEAL." % Seals.title(seal)
		PixelFont.draw(ci, hint, info.position + Vector2(8, 18), 1, Color("c9b8ff"), Occult.INK)
		PixelFont.draw(ci, "ESC/B: BACK", info.position + Vector2(8, 42), 1, Color(1, 1, 1, 0.5), Occult.INK)
	PixelFont.draw(ci, "CARDS DROP FROM", Vector2(14, 200), 1, Color(1, 1, 1, 0.45), Occult.INK)
	PixelFont.draw(ci, "MONSTERS. ELITES", Vector2(14, 210), 1, Color(1, 1, 1, 0.45), Occult.INK)
	PixelFont.draw(ci, "AND LICHES DROP", Vector2(14, 220), 1, Color(1, 1, 1, 0.45), Occult.INK)
	PixelFont.draw(ci, "THEM MORE OFTEN.", Vector2(14, 230), 1, Color(1, 1, 1, 0.45), Occult.INK)


## Handles one input event. Returns true when the album closes.
func handle(event: InputEvent) -> bool:
	if PlayerInput.back_pressed(event):
		Sfx.play("menu_select")
		return true
	var d := PlayerInput.menu_dir(event)
	if d != 0:
		sel = _row_step(sel, d)
		Sfx.play("menu_move")
		return false
	var side: Array = PlayerInput.menu_side(event)
	if int(side[1]) != 0:
		sel = wrapi(sel + int(side[1]), 0, Cards.count())
		Sfx.play("menu_move")
		return false
	if event is InputEventMouseMotion:
		for k: int in range(_cells.size()):
			var i: int = page() * PAGE + k
			if _cells[k].has_point(event.position) and sel != i:
				sel = i
				Sfx.play("menu_move")
		return false
	var tap: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if tap:
		if pages() > 1 and (PAGE_PREV.has_point(event.position) or PAGE_NEXT.has_point(event.position)):
			_turn(-1 if PAGE_PREV.has_point(event.position) else 1)
			return false
		for k: int in range(_cells.size()):
			var i: int = page() * PAGE + k
			if _cells[k].has_point(event.position):
				if sel == i:
					_toggle(i)
				sel = i
		return false
	if PlayerInput.confirm_device(event) != -99:
		_toggle(sel)
	return false


## The card a row up (d -1) or down (d +1) from `i`, in the same column, running on to the next or last page and
## wrapping at the ends; a short last row is skipped over to the card in that column on the first page.
static func _row_step(i: int, d: int) -> int:
	var col := i % COLS
	var n := i + d * COLS
	if n >= Cards.count():
		return col
	if n < 0:
		n = col
		while n + COLS < Cards.count():
			n += COLS
	return n


## Turns the page: the cursor goes to the same place on the next or previous page (or that page's last card).
func _turn(d: int) -> void:
	var p := wrapi(page() + d, 0, pages())
	sel = mini(p * PAGE + sel % PAGE, Cards.count() - 1)
	Sfx.play("menu_move")


## Sockets the card, or takes it out if it is already in.
func _toggle(i: int) -> void:
	var prof: Profile = Save.profile
	if prof.card_count(i) <= 0:
		Sfx.play("hurt", -8.0)
		return
	if prof.socket_indices().has(i):
		prof.unsocket(Cards.socket(i))
		Sfx.play("card_pick", -2.0, 0.8)
	else:
		prof.socket_card(i)
		Sfx.play("card_pick")
	Save.write()
