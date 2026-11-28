class_name OptionsPanel
extends RefCounted
## The options panel the title and the pause menu both open (the rows are Settings.ROWS; RESET PROGRESS only on the
## title, and only after confirm is held for Settings.RESET_HOLD seconds).
## Changes apply at once and are saved when the panel closes.

const ROW_H := 12
const W := 240.0
## Room above the first row (title) and below the last (the key hint and the VERSION line), in px.
const HEAD_H := 22.0
const FOOT_H := 24.0
const BACK_GAP := 3.0

var sel: int = 0
## Whether the panel is open in a run's pause menu (open() reads it): RESET PROGRESS is not offered there.
var in_run: bool = false
## Seconds the confirm key has been held on RESET PROGRESS, and whether it is held now.
var hold: float = 0.0
var holding: bool = false
var rect := Rect2(120, 40, W, 170)
var _rows: Array[Rect2] = []
var _last_ms: int = -1


func open() -> void:
	sel = 0
	in_run = G.main != null and G.main.current is Arena
	_cancel_hold()


## The Settings rows shown, in order (RESET PROGRESS only on the title).
func shown_rows() -> Array[int]:
	var out: Array[int] = []
	for r in Settings.row_count():
		if r == Settings.R_RESET and in_run:
			continue
		out.append(r)
	return out


func _back_row() -> int:
	return shown_rows().size()


func _cancel_hold() -> void:
	holding = false
	hold = 0.0
	_last_ms = -1


func _begin_hold() -> void:
	holding = true
	hold = 0.0
	_last_ms = Time.get_ticks_msec()


## Advances a held RESET PROGRESS by `dt` seconds; at Settings.RESET_HOLD the profile is reset and the game goes to the title.
func tick(dt: float) -> void:
	if not holding:
		return
	hold += dt
	if hold < Settings.RESET_HOLD:
		return
	_cancel_hold()
	Save.write_settings()
	if Save.reset_progress():
		Sfx.play("menu_select")
		G.goto_title.call_deferred()


func draw(ci: CanvasItem, t: float) -> void:
	if holding:
		var now := Time.get_ticks_msec()
		tick(minf(0.1, (now - _last_ms) / 1000.0))
		_last_ms = now
	var s: Settings = Save.settings
	var shown := shown_rows()
	var h := HEAD_H + shown.size() * ROW_H + BACK_GAP + ROW_H + FOOT_H
	rect = Rect2(120, roundf((G.SCREEN.y - h) / 2.0), W, h)
	Occult.frame(ci, rect, t)
	PixelFont.draw_centered(ci, "OPTIONS", 240, rect.position.y + 7, 1, Occult.GOLD, Occult.INK)
	_rows.clear()
	for i in shown.size() + 1:
		var y := rect.position.y + HEAD_H + i * ROW_H + (BACK_GAP if i == _back_row() else 0.0)
		var r := Rect2(rect.position.x + 8, y - 2, rect.size.x - 16, ROW_H - 1)
		_rows.append(r)
		var picked := i == sel
		if picked:
			Occult.highlight(ci, r, t)
			Occult.cursor(ci, Vector2(r.position.x + 7, y + 3), t)
		if i == _back_row():
			PixelFont.draw_centered(ci, "BACK", 240, y, 1, Occult.GOLD if picked else Occult.DIM, Occult.INK)
			continue
		var row: int = shown[i]
		PixelFont.draw(ci, Settings.label(row), Vector2(r.position.x + 16, y), 1, Occult.GOLD if picked else Color.WHITE)
		var vx := r.end.x - 86.0
		var fill := s.bar(row)
		if row == Settings.R_RESET and holding:
			var frac := clampf(hold / Settings.RESET_HOLD, 0.0, 1.0)
			ci.draw_rect(Rect2(vx + 8, y, 70, 6), Color("2a1f45"))
			ci.draw_rect(Rect2(vx + 8, y, 70.0 * frac, 6), Color("e0405a"))
			ci.draw_rect(Rect2(vx + 8, y, 70.0 * frac, 1), Color("ff9aa8"))
		elif fill >= 0.0:
			for k in Settings.VOL_MAX:
				var on := k < int(round(fill * Settings.VOL_MAX))
				ci.draw_rect(Rect2(vx + 8 + k * 6, y + 1, 4, 5), Occult.VIOLET if on else Color("2a1f45"))
				if on:
					ci.draw_rect(Rect2(vx + 8 + k * 6, y + 1, 4, 1), Color("c9a6ff"))
		elif row == Settings.R_RESET:
			PixelFont.draw_centered(ci, s.value_text(row), vx + 37, y, 1, Color("ff9aa8") if picked else Occult.DIM, Occult.INK)
		else:
			PixelFont.draw_centered(ci, s.value_text(row), vx + 37, y, 1, Occult.BONE, Occult.INK)
		if picked and row != Settings.R_RESET:
			PixelFont.draw(ci, "<", Vector2(vx, y), 1, Occult.GOLD)
			PixelFont.draw(ci, ">", Vector2(vx + 70, y), 1, Occult.GOLD)
	# The key hint and the version sit inside the frame: text below it would lie loose over the scene behind.
	var hint := "HOLD CONFIRM: RESET   ESC/B: BACK" if _selected_row() == Settings.R_RESET else "LEFT/RIGHT: CHANGE   ESC/B: BACK"
	PixelFont.draw_centered(ci, hint, 240, rect.end.y - 21, 1, Color(1, 1, 1, 0.45), Occult.INK)
	PixelFont.draw_centered(ci, "VERSION " + G.VERSION, 240, rect.end.y - 11, 1, Color(1, 1, 1, 0.3), Occult.INK)


## The Settings row under the cursor, or -1 on BACK.
func _selected_row() -> int:
	var shown := shown_rows()
	return shown[sel] if sel < shown.size() else -1


## Handles one input event. Returns true when the panel closes.
func handle(event: InputEvent) -> bool:
	if holding and _is_release(event):
		_cancel_hold()
		return false
	if PlayerInput.back_pressed(event):
		_cancel_hold()
		return _close()
	var d := PlayerInput.menu_dir(event)
	if d != 0:
		_cancel_hold()
		sel = wrapi(sel + d, 0, _back_row() + 1)
		Sfx.play("menu_move")
		return false
	var side: Array = PlayerInput.menu_side(event)
	if int(side[1]) != 0 and sel < _back_row():
		_change(sel, int(side[1]))
		return false
	if event is InputEventMouseMotion:
		for i in _rows.size():
			if _rows[i].has_point(event.position) and sel != i:
				_cancel_hold()
				sel = i
				Sfx.play("menu_move")
		return false
	var tap: bool = (event is InputEventScreenTouch and event.pressed) or \
		(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if tap:
		for i in _rows.size():
			if _rows[i].has_point(event.position):
				sel = i
				if i == _back_row():
					return _close()
				if _selected_row() == Settings.R_RESET:
					_begin_hold()
				else:
					_change(i, -1 if event.position.x < _rows[i].end.x - 50 else 1)
		return false
	if PlayerInput.confirm_device(event) != -99:
		if sel == _back_row():
			return _close()
		if _selected_row() == Settings.R_RESET:
			_begin_hold()
		else:
			_change(sel, 1)
	return false


## Whether `event` lets go of a confirm key, button or tap (which cancels a held RESET PROGRESS).
func _is_release(event: InputEvent) -> bool:
	if event is InputEventKey and not event.pressed:
		return event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_Z] or PlayerInput.is_kb2_confirm(event)
	if event is InputEventJoypadButton and not event.pressed:
		return event.button_index in [JOY_BUTTON_A, JOY_BUTTON_START]
	if event is InputEventMouseButton and not event.pressed:
		return true
	return event is InputEventScreenTouch and not event.pressed


## Steps the row at panel position `i` (not a Settings row number: RESET PROGRESS may be absent).
func _change(i: int, dir: int) -> void:
	var row: int = shown_rows()[i]
	if Save.settings.adjust(row, dir):
		Save.apply_settings()
		Sfx.play("menu_move" if row != Settings.R_SOUND else "coin")


func _close() -> bool:
	Save.write_settings()
	Sfx.play("menu_select")
	return true
