class_name HeroRoster
extends RefCounted
## The list of saved heroes (the Sanctum's mirror): up to Profile.MAX_HEROES rows with a small portrait, name, race,
## class and class level, the active hero marked. Actions: PICK (makes the row the active hero and closes), SHEET
## (opens the hero's sheet), NEW HERO (opens the builder; hidden when the profile is full) and DELETE (hold the
## confirm button for HOLD_TIME seconds, a bar fills; the last hero never goes). Up/down choose the row, left/right
## the action, confirm does it. Taps and clicks work on rows and buttons. Owns one HeroBuilder and one HeroSheet and
## hands them every event while they are open.

const A_PICK := 0
const A_SHEET := 1
const A_NEW := 2
const A_DELETE := 3
const ACTION_NAMES := ["PICK", "SHEET", "NEW HERO", "DELETE"]
## Seconds the confirm button is held to delete a hero.
const HOLD_TIME := 1.0
const LIST_PANEL := Rect2(12, 30, 300, 212)
const ROW0 := Vector2(18, 36)
const ROW_SIZE := Vector2(288, 24)
const ROW_STEP := 25.0
const SIDE_PANEL := Rect2(322, 30, 146, 212)
const BTN0 := Vector2(330, 46)
const BTN_SIZE := Vector2(130, 22)
const BTN_STEP := 27.0

var active := false
var picked := -1 # the index chosen when it closed with a pick; -1 when closed with back
var sel := 0
var act := A_PICK
var builder := HeroBuilder.new()
var sheet := HeroSheet.new()
var _prof: Profile
var _device := -99
var _hold := 0.0
var _holding := false
var _t := 0.0


func open(profile: Profile, device: int = -99) -> void:
	_prof = profile
	_device = device
	sel = clampi(profile.hero, 0, profile.heroes.size() - 1)
	act = A_PICK
	picked = -1
	_holding = false
	_hold = 0.0
	builder.active = false
	sheet.active = false
	active = true


# ============================================================== LOGIC ===
## The actions on offer, in button order: NEW HERO is hidden when the profile holds the most heroes.
func actions() -> Array[int]:
	var out: Array[int] = [A_PICK, A_SHEET]
	if _prof.heroes.size() < Profile.MAX_HEROES:
		out.append(A_NEW)
	out.append(A_DELETE)
	return out


func can_delete() -> bool:
	return _prof.heroes.size() > 1


## 0..1: how far the held confirm has filled the delete bar.
func hold_fraction() -> float:
	return clampf(_hold / HOLD_TIME, 0.0, 1.0) if _holding else 0.0


## Makes hero `i` the active hero, saves and closes.
func pick(i: int) -> void:
	_prof.hero = clampi(i, 0, _prof.heroes.size() - 1)
	HeroSheet.save_now()
	picked = _prof.hero
	active = false
	Sfx.play("menu_select")


## Deletes the highlighted hero (never the last one), saves. True when one went.
func delete_selected() -> bool:
	if not _prof.remove_hero(sel):
		Sfx.play("hurt", -6.0)
		return false
	sel = clampi(sel, 0, _prof.heroes.size() - 1)
	HeroSheet.save_now()
	Sfx.play("hurt", -2.0, 0.7)
	return true


## Does the highlighted action. DELETE only starts the hold (update finishes it).
func do_action(a: int) -> void:
	match a:
		A_PICK:
			pick(sel)
		A_SHEET:
			sheet.open(_prof, sel)
			Sfx.play("page_turn")
		A_NEW:
			if _prof.heroes.size() < Profile.MAX_HEROES:
				builder.open(_prof, _device)
				Sfx.play("page_turn")
		A_DELETE:
			if can_delete():
				_holding = true
				_hold = 0.0
			else:
				Sfx.play("hurt", -6.0)


func update(delta: float) -> void:
	_t += delta
	if builder.active:
		builder.update(delta)
	if sheet.active:
		sheet.update(delta)
	if _holding and active:
		_hold += delta
		if _hold >= HOLD_TIME:
			_holding = false
			_hold = 0.0
			delete_selected()
			if not actions().has(act):
				act = A_PICK


func _step_action(d: int) -> void:
	var acts := actions()
	act = acts[wrapi(acts.find(act) + d, 0, acts.size())]
	_holding = false
	Sfx.play("menu_move")


static func _is_release(event: InputEvent) -> bool:
	if event is InputEventKey:
		return not event.pressed
	if event is InputEventJoypadButton:
		return not event.pressed
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		return not event.pressed
	return false


func _row_rect(k: int) -> Rect2:
	return Rect2(ROW0 + Vector2(0, k * ROW_STEP), ROW_SIZE)


func _button_rect(k: int) -> Rect2:
	return Rect2(BTN0 + Vector2(0, k * BTN_STEP), BTN_SIZE)


## Handles one input event. Returns true when the roster closed on it (a pick or back).
func handle(event: InputEvent) -> bool:
	if not active:
		return false
	if builder.active:
		if builder.handle(event) and builder.made != null:
			sel = _prof.hero
		return false
	if sheet.active:
		sheet.handle(event)
		return false
	if _holding and _is_release(event):
		_holding = false
		return false
	if PlayerInput.back_pressed(event):
		picked = -1
		active = false
		Sfx.play("menu_select")
		return true
	var d := PlayerInput.menu_dir(event)
	if d != 0:
		sel = wrapi(sel + d, 0, _prof.heroes.size())
		_holding = false
		Sfx.play("menu_move")
		return false
	var side: Array = PlayerInput.menu_side(event)
	if int(side[1]) != 0:
		_step_action(int(side[1]))
		return false
	if event is InputEventMouseMotion:
		for k: int in range(_prof.heroes.size()):
			if _row_rect(k).has_point(event.position) and sel != k:
				sel = k
				Sfx.play("menu_move")
		return false
	if HeroSheet.tap_of(event):
		var acts := actions()
		for k: int in range(acts.size()):
			if _button_rect(k).has_point(event.position):
				act = acts[k]
				do_action(act)
				return not active
		for k: int in range(_prof.heroes.size()):
			if _row_rect(k).has_point(event.position):
				if sel == k:
					do_action(A_PICK)
				sel = k
		return not active
	if PlayerInput.confirm_device(event) != -99:
		do_action(act)
	return not active


# ============================================================== DRAW ===
func draw(ci: CanvasItem, t: float) -> void:
	if not active:
		return
	if builder.active:
		builder.draw(ci, t)
		return
	if sheet.active:
		sheet.draw(ci, t)
		return
	ci.draw_rect(Rect2(0, 0, 480, 270), Color(0.02, 0.0, 0.05, 0.94))
	Occult.frame(ci, Rect2(4, 4, 472, 262), t)
	PixelFont.draw_centered(ci, "THE MIRROR", 240, 10, 2, Occult.GOLD, Occult.INK)
	var count := "%d / %d" % [_prof.heroes.size(), Profile.MAX_HEROES]
	PixelFont.draw(ci, count, Vector2(468 - PixelFont.text_width(count), 14), 1, Occult.BONE, Occult.INK)
	Occult.frame(ci, LIST_PANEL, t, false)
	for k: int in range(Profile.MAX_HEROES):
		var row := _row_rect(k)
		if k >= _prof.heroes.size():
			ci.draw_rect(row, Color(1, 1, 1, 0.04), false, 1.0)
			continue
		_draw_row(ci, t, row, k)
	_draw_side(ci, t)
	var key := "ENTER" if _device == -99 or _device == G.DEV_KBM else "A"
	PixelFont.draw_centered(ci, "UP/DOWN: HERO   LEFT/RIGHT: ACTION   %s: DO IT   ESC/B: BACK" % key, 240, 250, 1,
		Color(1, 1, 1, 0.5), Occult.INK)


func _draw_row(ci: CanvasItem, t: float, row: Rect2, k: int) -> void:
	var h: Hero = _prof.heroes[k]
	if k == sel:
		Occult.highlight(ci, row, t)
	var pr := Rect2(row.position + Vector2(6, 1), Vector2(15, 22))
	HeroSheet.draw_portrait(ci, pr, h.race, h.cls)
	if h.points_left() > 0:
		ci.draw_rect(Rect2(pr.end.x - 2, pr.position.y - 1, 4, 4), Color("5dff7a"))
		ci.draw_rect(Rect2(pr.end.x - 2, pr.position.y - 1, 4, 4), Occult.INK, false, 1.0)
	var tx := row.position.x + 30
	PixelFont.draw(ci, h.name, Vector2(tx, row.position.y + 5), 1, Occult.GOLD if k == sel else Occult.BONE, Occult.INK)
	PixelFont.draw(ci, "%s %s" % [Races.race_name(h.race), Classes.class_name_of(h.cls)],
		Vector2(tx, row.position.y + 14), 1, Occult.DIM, Occult.INK)
	var lv := "LV %d" % h.level
	var lx := row.end.x - 8 - PixelFont.text_width(lv)
	PixelFont.draw(ci, lv, Vector2(lx, row.position.y + 9), 1, Occult.BONE, Occult.INK)
	if k == _prof.hero:
		var tag := "ACTIVE"
		var ax := lx - 14 - PixelFont.text_width(tag)
		PixelFont.draw(ci, tag, Vector2(ax, row.position.y + 9), 1, Occult.GOLD, Occult.INK)
		var c := Vector2(ax - 7, row.position.y + 12)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)]),
			Occult.GOLD)


func _draw_side(ci: CanvasItem, t: float) -> void:
	Occult.frame(ci, SIDE_PANEL, t, false)
	PixelFont.draw_centered(ci, "ACTIONS", SIDE_PANEL.get_center().x, SIDE_PANEL.position.y + 8, 1, Occult.GOLD, Occult.INK)
	var acts := actions()
	for k: int in range(acts.size()):
		var a: int = acts[k]
		var r := _button_rect(k)
		var dim := a == A_DELETE and not can_delete()
		ci.draw_rect(r, Color(0.03, 0.01, 0.07, 0.9))
		if a == A_DELETE and _holding:
			ci.draw_rect(Rect2(r.position, Vector2(r.size.x * hold_fraction(), r.size.y)), Color(Occult.BLOOD, 0.8))
		if a == act:
			Occult.highlight(ci, r, t)
		ci.draw_rect(r, Color(Occult.VIOLET, 0.6), false, 1.0)
		var label := String(ACTION_NAMES[a])
		var col := Occult.GOLD if a == act else Occult.BONE
		if dim:
			col = Color(1, 1, 1, 0.25)
			label = "LAST HERO"
		elif a == A_DELETE and _holding:
			label = "HOLD..."
		PixelFont.draw_centered(ci, label, r.get_center().x, r.position.y + 8, 1, col, Occult.INK)
	var h: Hero = _prof.heroes[sel]
	var y := 166.0
	var x := SIDE_PANEL.position.x + 8
	PixelFont.draw(ci, HeroSheet.fit_text(h.name, 130), Vector2(x, y), 1, Occult.GOLD, Occult.INK)
	PixelFont.draw(ci, "LV %d  %s" % [h.level, Classes.ROLE_NAMES[Classes.role(h.cls)]], Vector2(x, y + 11), 1,
		Occult.DIM, Occult.INK)
	if h.points_left() > 0:
		PixelFont.draw(ci, "%d POINT%s TO SPEND" % [h.points_left(), "" if h.points_left() == 1 else "S"], Vector2(x, y + 22), 1, Color("5dff7a"), Occult.INK)
	var key := "ENTER" if _device == -99 or _device == G.DEV_KBM else "A"
	if act == A_DELETE and can_delete():
		PixelFont.draw(ci, "HOLD %s TO DELETE" % key, Vector2(x, y + 36), 1, Occult.BLOOD.lightened(0.4), Occult.INK)
	elif act == A_PICK:
		PixelFont.draw(ci, "PLAY THIS HERO", Vector2(x, y + 36), 1, Color(1, 1, 1, 0.45), Occult.INK)
	elif act == A_SHEET:
		PixelFont.draw(ci, "STATS AND POINTS", Vector2(x, y + 36), 1, Color(1, 1, 1, 0.45), Occult.INK)
	else:
		PixelFont.draw(ci, "A NEW FACE", Vector2(x, y + 36), 1, Color(1, 1, 1, 0.45), Occult.INK)
