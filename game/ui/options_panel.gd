class_name OptionsPanel
extends RefCounted
## The options panel the title and the pause menu both open: music and sound volume, the window, screen shake,
## crash reports.
## Changes apply at once and are saved when the panel closes.

const RECT := Rect2(120, 134, 240, 112)
const ROW_H := 14

var sel: int = 0
var _rows: Array[Rect2] = []


func open() -> void:
	sel = 0


func _back_row() -> int:
	return Settings.row_count()


func draw(ci: CanvasItem, t: float) -> void:
	var s: Settings = Save.settings
	Occult.frame(ci, RECT, t)
	PixelFont.draw_centered(ci, "OPTIONS", 240, RECT.position.y + 7, 1, Occult.GOLD, Occult.INK)
	_rows.clear()
	for i in Settings.row_count() + 1:
		var y := RECT.position.y + 20 + i * ROW_H + (4 if i == _back_row() else 0)
		var r := Rect2(RECT.position.x + 8, y - 3, RECT.size.x - 16, 13)
		_rows.append(r)
		var picked := i == sel
		if picked:
			Occult.highlight(ci, r, t)
			Occult.cursor(ci, Vector2(r.position.x + 7, y + 3), t)
		if i == _back_row():
			PixelFont.draw_centered(ci, "BACK", 240, y, 1, Occult.GOLD if picked else Occult.DIM, Occult.INK)
			continue
		PixelFont.draw(ci, Settings.label(i), Vector2(r.position.x + 16, y), 1, Occult.GOLD if picked else Color.WHITE)
		var vx := r.end.x - 86.0
		var fill := s.bar(i)
		if fill >= 0.0:
			for k in Settings.VOL_MAX:
				var on := k < int(round(fill * Settings.VOL_MAX))
				ci.draw_rect(Rect2(vx + 8 + k * 6, y + 1, 4, 5), Occult.VIOLET if on else Color("2a1f45"))
				if on:
					ci.draw_rect(Rect2(vx + 8 + k * 6, y + 1, 4, 1), Color("c9a6ff"))
		else:
			PixelFont.draw_centered(ci, s.value_text(i), vx + 37, y, 1, Occult.BONE, Occult.INK)
		if picked:
			PixelFont.draw(ci, "<", Vector2(vx, y), 1, Occult.GOLD)
			PixelFont.draw(ci, ">", Vector2(vx + 70, y), 1, Occult.GOLD)
	PixelFont.draw_centered(ci, "LEFT/RIGHT: CHANGE   ESC/B: BACK", 240, RECT.end.y + 6, 1, Color(1, 1, 1, 0.45), Occult.INK)


## Handles one input event. Returns true when the panel closes.
func handle(event: InputEvent) -> bool:
	if PlayerInput.back_pressed(event):
		return _close()
	var d := PlayerInput.menu_dir(event)
	if d != 0:
		sel = wrapi(sel + d, 0, Settings.row_count() + 1)
		Sfx.play("menu_move")
		return false
	var side: Array = PlayerInput.menu_side(event)
	if int(side[1]) != 0 and sel < _back_row():
		_change(sel, int(side[1]))
		return false
	if event is InputEventMouseMotion:
		for i in _rows.size():
			if _rows[i].has_point(event.position) and sel != i:
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
				_change(i, -1 if event.position.x < _rows[i].end.x - 50 else 1)
		return false
	if PlayerInput.confirm_device(event) != -99:
		if sel == _back_row():
			return _close()
		_change(sel, 1)
	return false


func _change(row: int, dir: int) -> void:
	if Save.settings.adjust(row, dir):
		Save.apply_settings()
		Sfx.play("menu_move" if row != Settings.R_SOUND else "coin")


func _close() -> bool:
	Save.write_settings()
	Sfx.play("menu_select")
	return true
