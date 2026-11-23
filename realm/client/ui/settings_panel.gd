class_name SettingsPanel
extends PanelBase
## Settings: the keys (click one, press the new key; the arrows always walk too), the volume, the window (size or
## fullscreen). Kept in user://settings.cfg (ShellSettings). In town it also holds LEAVE TOWN and QUIT.

const COLS: int = 2
## Ten rows a column (19 keys) in the 270 px the keys had at nine rows of 30.
const ROW_H: float = 27.0

var awaiting: String = ""


func opened() -> void:
	title = "SETTINGS"
	frame_rect = Rect2(110, 30, 740, 480)


func paint_body(inner: Rect2) -> void:
	var x: float = inner.position.x
	var y: float = inner.position.y - 8
	UiKit.text(self, Vector2(x, y), "KEYS", 14, UiKit.GOLD)
	var per_col: int = int(ceil(float(ShellSettings.ACTIONS.size()) / COLS))
	for i in ShellSettings.ACTIONS.size():
		var a: Array = ShellSettings.ACTIONS[i]
		var col: int = i / per_col
		var row: int = i % per_col
		var r := Rect2(x + col * 350.0, y + 24 + row * ROW_H, 330, ROW_H - 4)
		var id: String = "key:" + String(a[0])
		hit(id, r)
		draw_rect(r, Color(0.1, 0.06, 0.06) if awaiting == a[0] else (Color(0.09, 0.08, 0.09) if hover_id == id else Color(0.06, 0.05, 0.06)))
		draw_rect(r, UiKit.GOLD if awaiting == a[0] else Color(UiKit.GOLD_DIM, 0.35), false, 1.0)
		UiKit.text(self, r.position + Vector2(8, 4), String(a[1]), 12, UiKit.BONE)
		var lab: String = "PRESS A KEY" if awaiting == a[0] else ShellSettings.key_label(ShellSettings.key(String(a[0])))
		UiKit.text(self, Vector2(r.end.x - 8, r.position.y + 4), lab, 12, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	var ky: float = y + 24 + per_col * ROW_H + 4
	button("keys_reset", Rect2(x, ky, 160, 26), "RESET KEYS", true, false, 11)
	# Volume.
	var vy: float = ky + 40
	UiKit.text(self, Vector2(x, vy), "VOLUME", 14, UiKit.GOLD)
	var bar := Rect2(x + 110, vy + 2, 360, 18)
	hit("volume", bar)
	UiKit.bar(self, bar, ShellSettings.volume, UiKit.GOLD_DIM)
	UiKit.text(self, Vector2(bar.end.x + 12, vy), "%d%%" % roundi(ShellSettings.volume * 100.0), 13, UiKit.BONE)
	button("vol:-1", Rect2(bar.end.x + 70, vy - 2, 34, 24), "-", true, false, 13)
	button("vol:1", Rect2(bar.end.x + 108, vy - 2, 34, 24), "+", true, false, 13)
	# Window.
	var wy: float = vy + 40
	UiKit.text(self, Vector2(x, wy), "WINDOW", 14, UiKit.GOLD)
	for i in ShellSettings.WINDOW_SIZES.size():
		var sz: Vector2i = ShellSettings.WINDOW_SIZES[i]
		button("win:%d" % i, Rect2(x + 110 + i * 116.0, wy - 4, 108, 28), "%dx%d" % [sz.x, sz.y], not ShellSettings.fullscreen, ShellSettings.window_index == i and not ShellSettings.fullscreen, 12)
	button("full", Rect2(x + 110 + 4 * 116.0, wy - 4, 130, 28), "FULLSCREEN", true, ShellSettings.fullscreen, 12)
	# Leaving.
	var by: float = inner.end.y - 40
	button("resume", Rect2(x, by, 150, 34), "RESUME", true, false, 14)
	if shell.base is TownScreen:
		button("heroes", Rect2(x + 170, by, 170, 34), "LEAVE TOWN", true, false, 14)
	if shell.base is TownScreen or shell.base is HeroListScreen:
		button("logout", Rect2(x + 360, by, 150, 34), "LOG OUT", true, false, 14)
	button("quit", Rect2(inner.end.x - 150, by, 150, 34), "QUIT GAME", true, false, 14)


func press_body(id: String) -> void:
	if id.begins_with("key:"):
		awaiting = id.trim_prefix("key:")
	elif id == "keys_reset":
		ShellSettings.reset_keys()
		ShellSettings.save_file()
	elif id == "volume":
		var bar_x: float = frame_rect.position.x + 14 + 110
		ShellSettings.volume = snappedf(clampf((mouse_pos.x - bar_x) / 360.0, 0.0, 1.0), 0.05)
		_apply()
	elif id.begins_with("vol:"):
		ShellSettings.volume = clampf(snappedf(ShellSettings.volume + 0.1 * int(id.trim_prefix("vol:")), 0.05), 0.0, 1.0)
		_apply()
	elif id.begins_with("win:"):
		ShellSettings.window_index = int(id.trim_prefix("win:"))
		_apply()
	elif id == "full":
		ShellSettings.fullscreen = not ShellSettings.fullscreen
		_apply()
	elif id == "resume":
		close()
	elif id == "heroes":
		close()
		shell.leave_town()
	elif id == "logout":
		close()
		shell.logout()
	elif id == "quit":
		get_tree().quit()


func _apply() -> void:
	ShellSettings.apply(get_window())
	ShellSettings.save_file()


func on_key(e: InputEventKey) -> bool:
	if not awaiting.is_empty():
		if e.keycode != KEY_ESCAPE:
			ShellSettings.rebind(awaiting, e.physical_keycode)
			ShellSettings.save_file()
		awaiting = ""
		return true
	return super(e)
