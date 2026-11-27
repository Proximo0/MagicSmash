class_name TitleScreen
extends UiScreen
## The title: black, a ring of runes, the name in bone, two candles. ENTER (or any key) goes to the login.

const RUNE_RING: int = 24


func paint() -> void:
	UiKit.backdrop(self, time)
	var c := Vector2(UiKit.W / 2.0, 190.0)
	# The emblem: a file `art/ui_title.png` when there is one, else a ring of runes round a flame.
	if UiArt.has_file("title"):
		var t: Texture2D = UiArt.texture("title", 160)
		draw_texture_rect(t, Rect2(c - Vector2(80, 80), Vector2(160, 160)), false)
	else:
		draw_arc(c, 92.0, 0.0, TAU, 64, UiKit.GOLD_DIM, 1.0)
		draw_arc(c, 78.0, 0.0, TAU, 64, Color(UiKit.GOLD_DIM, 0.6), 1.0)
		for i in RUNE_RING:
			var a: float = float(i) / RUNE_RING * TAU + time * 0.05
			UiKit.rune(self, c + Vector2.from_angle(a) * 85.0 - Vector2(5, 7), i, 10.0, Color(UiKit.GOLD, 0.8), 1.0)
		var f: float = 0.85 + 0.15 * sin(time * 7.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-26, 40), c + Vector2(0, -50 * f), c + Vector2(26, 40)]), Color(0.6, 0.1, 0.08, 0.85))
		draw_colored_polygon(PackedVector2Array([c + Vector2(-13, 40), c + Vector2(0, -20 * f), c + Vector2(13, 40)]), Color(0.95, 0.62, 0.18, 0.9))
	UiKit.candle(self, Vector2(250, 220), time, 0.0)
	UiKit.candle(self, Vector2(710, 220), time, 2.0)
	UiKit.text(self, Vector2(UiKit.W / 2.0, 280), "HORDE & HEARTH", 60, UiKit.BONE, HORIZONTAL_ALIGNMENT_CENTER, true, UiKit.display_font())
	UiKit.text(self, Vector2(UiKit.W / 2.0, 370), "Keep the fire lit, and the dead outside", 18, UiKit.BLOOD_BRIGHT, HORIZONTAL_ALIGNMENT_CENTER, true, UiKit.display_font())
	button("enter", Rect2(380, 410, 200, 40), "ENTER", true, false, 18)
	UiKit.glow(self, Rect2(380, 410, 200, 40), time)
	button("settings", Rect2(380, 458, 96, 32), "SETTINGS", true, false, 13)
	button("quit", Rect2(484, 458, 96, 32), "QUIT", true, false, 13)


func on_press(id: String) -> void:
	match id:
		"enter":
			shell.show_base(LoginScreen.new(), "login")
		"settings":
			shell.open_panel(SettingsPanel.new())
		"quit":
			get_tree().quit()


func on_key(e: InputEventKey) -> bool:
	if e.keycode == KEY_ESCAPE:
		return false
	if e.keycode == KEY_ENTER or e.keycode == KEY_SPACE or e.keycode == KEY_KP_ENTER:
		on_press("enter")
		return true
	return false
