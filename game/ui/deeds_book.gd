class_name DeedsBook
extends RefCounted
## The Book of Deeds (the Sanctum's lectern): every deed in Achievements.LIST as a scrolling list. An earned deed is
## bright with a mark, a locked one dim, a locked secret one reads "???". The reward is on the right, the selected
## deed's description at the bottom and "DEEDS 7 / 41" in the header. Up/down move the selection, left/right a page
## at a time, back closes. Taps, clicks and the wheel work on rows. Reads the profile it was opened with.

const FRAME := Rect2(4, 4, 472, 262)
const LIST_TOP := 34.0
const ROW_H := 14.0
const VISIBLE := 12
const LIST_X := 16.0
const MARK_W := 7.0
## A deed's icon (Still.DEED_MARKS), px, and its tint while the deed is locked.
const MARK_ICON := 12.0
const ICON_DIM := Color(0.45, 0.42, 0.55)
const NAME_X := 32.0
const REWARD_RIGHT := 448.0
const SCROLL_X := 458.0
const DESC_PANEL := Rect2(12, 210, 456, 48)
const SECRET_NAME := "???"
const SECRET_DESC := "A SECRET DEED. IT WILL SHOW ITSELF WHEN EARNED."
const DIM_NAME := Color("8678ad")
const DIM_REWARD := Color("6d6290")
const EARNED_MARK := Color("8bff9e")
const ROW_SEL := Color(0.48, 0.3, 1.0, 0.28)

var active := false
var sel := 0
var top := 0
var _prof: Profile
var _t := 0.0


func open(profile: Profile) -> void:
	_prof = profile
	sel = 0
	top = 0
	active = true
	_t = 0.0


func update(delta: float) -> void:
	_t += delta


## The deeds the book lists, in catalogue order.
static func count() -> int:
	return Achievements.count()


## The first row shown when `sel` must stay in view and `top` is where the list starts now.
static func scroll_for(sel_row: int, top_row: int, total: int) -> int:
	var t := clampi(top_row, 0, maxi(0, total - VISIBLE))
	if sel_row < t:
		t = sel_row
	elif sel_row >= t + VISIBLE:
		t = sel_row - VISIBLE + 1
	return clampi(t, 0, maxi(0, total - VISIBLE))


## What the list shows for a row: [name, description, reward text, earned, secret and locked].
func row_text(i: int) -> Array:
	var row: Array = Achievements.LIST[i]
	var api := str(row[Achievements.C_API])
	var earned := _prof != null and _prof.has_deed(api)
	var hidden := Achievements.is_secret(api) and not earned
	if hidden:
		return [SECRET_NAME, SECRET_DESC, SECRET_NAME, earned, hidden]
	return [str(row[Achievements.C_NAME]), str(row[Achievements.C_DESC]), "+%d" % int(row[Achievements.C_CRYSTALS]),
		earned, hidden]


func _select(i: int) -> void:
	sel = wrapi(i, 0, count())
	top = scroll_for(sel, top, count())


func handle(event: InputEvent) -> bool:
	if not active:
		return false
	if PlayerInput.back_pressed(event):
		Sfx.play("menu_select")
		active = false
		return true
	var d := PlayerInput.menu_dir(event)
	if d != 0:
		_select(sel + d)
		Sfx.play("menu_move")
		return false
	var side: Array = PlayerInput.menu_side(event)
	if int(side[1]) != 0:
		_select(clampi(sel + int(side[1]) * VISIBLE, 0, count() - 1))
		Sfx.play("menu_move")
		return false
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			top = clampi(top - 1, 0, maxi(0, count() - VISIBLE))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			top = clampi(top + 1, 0, maxi(0, count() - VISIBLE))
	var tap: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if tap:
		var k := int((event.position.y - LIST_TOP) / ROW_H)
		if event.position.y >= LIST_TOP and k >= 0 and k < VISIBLE and top + k < count():
			sel = top + k
	return false


func draw(ci: CanvasItem, t: float) -> void:
	if not active:
		return
	if not Still.draw_scene(ci, "deeds"):
		ci.draw_rect(Rect2(0, 0, 480, 270), Color(0.02, 0.0, 0.05, 0.92))
	Occult.frame(ci, FRAME, t)
	Still.draw_scene(ci, "deeds", Still.SCENE_INNER)
	PixelFont.draw_centered(ci, "BOOK OF DEEDS", 240, 12, 2, Occult.GOLD, Occult.INK)
	var got := _prof.deeds_earned() if _prof != null else 0
	var head := "DEEDS %d / %d" % [got, count()]
	PixelFont.draw(ci, head, Vector2(REWARD_RIGHT + 10 - PixelFont.text_width(head), 16), 1, Occult.BONE, Occult.INK)
	for k: int in range(VISIBLE):
		var i := top + k
		if i >= count():
			break
		var y := LIST_TOP + k * ROW_H
		var tx := row_text(i)
		var earned: bool = tx[3]
		if i == sel:
			ci.draw_rect(Rect2(LIST_X - 4, y - 2, 448, ROW_H - 1), ROW_SEL)
			ci.draw_rect(Rect2(LIST_X - 4, y - 2, 2, ROW_H - 1), Occult.GOLD)
		_draw_mark(ci, Vector2(LIST_X, y), earned, str(Achievements.LIST[i][Achievements.C_API]), bool(tx[4]))
		var name_col := Occult.GOLD if earned else DIM_NAME
		if i == sel and not earned:
			name_col = Occult.DIM
		PixelFont.draw(ci, str(tx[0]), Vector2(NAME_X, y), 1, name_col, Occult.INK)
		var rw := str(tx[2])
		PixelFont.draw(ci, rw, Vector2(REWARD_RIGHT - PixelFont.text_width(rw), y), 1,
			Color("8bdcff") if earned else DIM_REWARD, Occult.INK)
	_draw_scroll(ci)
	Occult.frame(ci, DESC_PANEL, t, false)
	var sel_tx := row_text(sel)
	var state := "EARNED" if sel_tx[3] else "LOCKED"
	PixelFont.draw(ci, str(sel_tx[0]), DESC_PANEL.position + Vector2(8, 8), 1, Occult.GOLD if sel_tx[3] else Occult.DIM, Occult.INK)
	PixelFont.draw(ci, state, Vector2(DESC_PANEL.end.x - 8 - PixelFont.text_width(state), DESC_PANEL.position.y + 8), 1,
		EARNED_MARK if sel_tx[3] else DIM_REWARD, Occult.INK)
	PixelFont.draw(ci, str(sel_tx[1]), DESC_PANEL.position + Vector2(8, 24), 1, Occult.BONE, Occult.INK)


## The box before a deed: a green tick in a gold box once earned, an empty dim box before.
## The mark's icon file when the deed's kind has one (Still.DEED_MARKS), drawn bright once earned and dim before; a
## secret still hidden keeps the empty box.
func _draw_mark(ci: CanvasItem, p: Vector2, earned: bool, api: String = "", hidden: bool = false) -> void:
	var icon := "" if hidden else Still.deed_icon(api)
	if not icon.is_empty() and Still.draw_icon(ci, icon, Rect2(p + Vector2(-2, -2), Vector2(MARK_ICON, MARK_ICON)),
			Color.WHITE if earned else ICON_DIM):
		return
	var box := Color(Occult.GOLD, 0.9) if earned else DIM_REWARD
	ci.draw_rect(Rect2(p, Vector2(MARK_W, MARK_W)), box)
	ci.draw_rect(Rect2(p + Vector2(1, 1), Vector2(MARK_W - 2, MARK_W - 2)), Occult.INK)
	if earned:
		for c: Vector2 in [Vector2(1, 3), Vector2(2, 4), Vector2(3, 3), Vector2(4, 2), Vector2(5, 1)]:
			ci.draw_rect(Rect2(p + c, Vector2(1, 1)), EARNED_MARK)


## A thin bar on the right edge: the part of the list on view.
func _draw_scroll(ci: CanvasItem) -> void:
	var total := count()
	if total <= VISIBLE:
		return
	var h := VISIBLE * ROW_H
	ci.draw_rect(Rect2(SCROLL_X, LIST_TOP - 2, 2, h), Color(Occult.DEEP, 0.6))
	var bar := maxf(8.0, h * VISIBLE / total)
	var by := LIST_TOP - 2 + (h - bar) * float(top) / float(total - VISIBLE)
	ci.draw_rect(Rect2(SCROLL_X, by, 2, bar), Occult.GOLD)
