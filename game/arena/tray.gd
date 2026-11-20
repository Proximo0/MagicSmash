class_name ArenaTray
extends RefCounted
## Arena: the level-up tab, the head marker and the card tray, and taking a card.
## Static helpers: `a` is the Arena that owns the state.

## True while any wizard holds cards (the autotest keys shots on it).
static func _anyone_picking(a: Arena) -> bool:
	for p: Dictionary in a.vp.values():
		if not (p.get("choices", []) as Array).is_empty():
			return true
	return false


static func _draws(a: Arena, slot: int) -> int:
	return int(a.vp[slot].get("draws", 0)) if a.vp.has(slot) else 0


## The input device of a local wizard, or -99 for a remote one.
static func _slot_device(a: Arena, slot: int) -> int:
	for r in Net.my_slots():
		if r.slot == slot:
			return r.device
	return -99


## True while `slot`'s tray is open on this screen: a local wizard holding cards who opened it.
static func _tray_shown(a: Arena, slot: int) -> bool:
	return bool(a._tray_open.get(slot, false)) and a.vp.has(slot) and not (a.vp[slot].choices as Array).is_empty()


static func _set_tray(a: Arena, slot: int, open: bool) -> void:
	if open != _tray_shown(a, slot):
		Sfx.play("card_flip" if open else "menu_move", -4.0)
	a._tray_open[slot] = open


## The tab and the tray sit in the wizard's own HUD column, directly under the HUD strip.
static func _tab_rect(a: Arena, slot: int) -> Rect2:
	return Rect2(slot * 120 + 1, G.HUD_H + 1, a.TRAY_W, a.TAB_H)


static func _tray_rect(a: Arena, slot: int) -> Rect2:
	var n: int = (a.vp[slot].choices as Array).size()
	return Rect2(slot * 120 + 1, G.HUD_H + 1, a.TRAY_W, 1 + n * a.TRAY_ROW_H + 8)


static func _tray_row_rect(a: Arena, slot: int, c: int) -> Rect2:
	return Rect2(slot * 120 + 2, G.HUD_H + 1 + c * a.TRAY_ROW_H, a.TRAY_W - 2, a.TRAY_ROW_H)


## How far row `c` of `slot`'s hand has turned over: 0 face down, 1 face up. A hand dealt while the tray is
## open turns over in TRAY_FLIP seconds, row by row, with the card sounds.
static func _tray_turn(a: Arena, slot: int, c: int) -> float:
	var seen: Array = a._tray_dealt.get(slot, [-1, -10.0, 7, false])
	var step := a.TRAY_FLIP / 5.0
	var k := clampf((a.time - float(seen[1]) - step * c) / (step * 3.0), 0.0, 1.0)
	if k >= 0.5 and (int(seen[2]) & (1 << c)) == 0:
		seen[2] = int(seen[2]) | (1 << c)
		Sfx.play("card_flip", -4.0, 1.0 + c * 0.06, 0.03)
	return k


## Records `slot`'s new hand `offer`: with `turn` its rows turn over from now, with the deal sound; without, it
## is face up already (a hand dealt while the tray was shut, shown when the player opens it).
static func _deal_tray(a: Arena, slot: int, offer: int, turn: bool) -> void:
	a._tray_dealt[slot] = [offer, a.time, 0, true] if turn else [offer, a.time - a.TRAY_FLIP, 7, false]
	if turn:
		Sfx.play("card_deal", -2.0)


## True while a monster card reveal or a fate bet fills the middle of the screen: the trays fold down to their
## tabs and the take buttons do nothing (opening and closing still work).
static func _tray_covered(a: Arena) -> bool:
	if not a._cards.is_empty():
		return true
	for b: Dictionary in a._bets:
		if b.kind == Gamble.TEAM:
			return true
	return false


## The level-up cards on screen: a tab under the HUD panel of every wizard with draws waiting, or the open tray of
## a local wizard; then a marker over each living wizard with a tab, drawn last so no tray hides it.
static func _draw_draws(a: Arena, ci: CanvasItem, dark: Color) -> void:
	var covered := _tray_covered(a)
	var marked: Array[int] = []
	for slot: int in a.vp.keys():
		if _draws(a, slot) <= 0:
			continue
		if _tray_shown(a, slot) and not covered:
			_draw_tray(a, ci, slot, dark)
			continue
		_draw_tab(a, ci, slot, dark)
		# The marker waits out the LEVEL UP call-out, which rises from the same spot.
		if a.vp[slot].alive and a.time - float(a._tab_flash.get(slot, -10.0)) > 0.6:
			marked.append(slot)
	for slot: int in marked:
		_draw_draw_marker(a, ci, slot)


## The tab: a card back, DRAW, the number of draws past one, and the button that opens the tray.
static func _draw_tab(a: Arena, ci: CanvasItem, slot: int, dark: Color) -> void:
	var r := _tab_rect(a, slot)
	var col := G.player_color(slot)
	var flash := clampf(1.0 - (a.time - float(a._tab_flash.get(slot, -10.0))) / 0.5, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(a.time * 5.0)
	# The border pulses in the wizard's colour and turns gold at each peak, so it stands out on any floor.
	var rim := col.lerp(Color("ffd94d"), clampf((pulse - 0.75) * 4.0, 0.0, 1.0)).lerp(Color.WHITE, flash)
	ci.draw_rect(r.grow(1), Color(rim, 0.45 + 0.45 * pulse))
	ci.draw_rect(r, dark.lerp(col, 0.12 + 0.14 * pulse))
	TarotArt.draw_back_icon(ci, Rect2(r.position + Vector2(3, 1), Vector2(7, 9)), col)
	var tc := Color("ffd94d").lerp(Color.WHITE, maxf(flash, pulse * 0.4))
	PixelFont.draw(ci, "DRAW", Vector2(r.position.x + 14, r.position.y + 2), 1, tc, dark)
	if _draws(a, slot) > 1:
		PixelFont.draw(ci, "x%d" % _draws(a, slot), Vector2(r.position.x + 43, r.position.y + 2), 1, Color.WHITE, dark)
	var dev := _slot_device(a, slot)
	if dev != -99:
		var label := "E" if dev == G.DEV_KBM else "LB"
		_draw_keycap(a, ci, Vector2(r.end.x - 3 - PixelFont.text_width(label) - 2, r.position.y + 1), label)
	if flash > 0.0:
		ci.draw_rect(r, Color(1, 1, 1, flash * 0.45))


## The open tray: one row per card, each with the button that takes it; the footer says how many draws wait
## behind this hand and which button hides the tray.
static func _draw_tray(a: Arena, ci: CanvasItem, slot: int, dark: Color) -> void:
	var p: Dictionary = a.vp[slot]
	var col := G.player_color(slot)
	var r := _tray_rect(a, slot)
	var dev := _slot_device(a, slot)
	# The body and footer let a little of the arena through; the card rows are solid behind their text.
	ci.draw_rect(r.grow(1), Color(col, 0.55))
	ci.draw_rect(r, Color(dark, 0.75))
	var choices: Array = p.choices
	for c in choices.size():
		var rr := _tray_row_rect(a, slot, c)
		var k := _tray_turn(a, slot, c)
		if k < 0.5:
			var w := rr.size.x * (1.0 - k * 2.0)
			TarotArt.draw_back(ci, Rect2(rr.get_center().x - w / 2.0, rr.position.y, w, rr.size.y))
			continue
		var idx: int = choices[c]
		var lv: int = p.choice_lv[c]
		var lv_text := "NEW" if lv == 1 else "%d/%d" % [lv, Upgrades.max_level(idx)]
		TarotArt.draw_card_row(ci, rr, Upgrades.key(idx), Upgrades.display_name(idx), Upgrades.description(idx),
			lv_text, 11.0)
		_draw_pick_button(a, ci, rr.position + Vector2(1, 4), dev, c)
		if k < 0.75:
			ci.draw_rect(rr, Color(1, 1, 1, (0.75 - k) * 3.0))
	var fy := r.end.y - 8.0
	if _draws(a, slot) > 1:
		PixelFont.draw(ci, "+%d MORE" % (_draws(a, slot) - 1), Vector2(r.position.x + 3, fy), 1, Color("ffd94d"), dark)
	var label := "E" if dev == G.DEV_KBM else "LB"
	var hx := r.end.x - 2 - PixelFont.text_width("HIDE")
	PixelFont.draw(ci, "HIDE", Vector2(hx, fy), 1, Color("8a7aa8"), dark)
	_draw_keycap(a, ci, Vector2(hx - 4 - PixelFont.text_width(label) - 2, fy - 1), label, false)


## A small light keycap with a label, 9 px tall (11 with its dark outline).
static func _draw_keycap(a: Arena, ci: CanvasItem, at: Vector2, label: String, outline: bool = true) -> void:
	var w := PixelFont.text_width(label) + 2
	if outline:
		ci.draw_rect(Rect2(at - Vector2(1, 1), Vector2(w + 2, 11)), Occult.INK)
	ci.draw_rect(Rect2(at, Vector2(w, 9)), Color("e8dcc0"))
	ci.draw_rect(Rect2(at + Vector2(0, 8), Vector2(w, 1)), Color("a89a80"))
	PixelFont.draw(ci, label, at + Vector2(1, 1), 1, Occult.INK)


## The button that takes card `c`: 1, 2, 3 on a keycap for the keyboard; for a pad, a diamond of four dots with
## the left, the top or the right one lit (pads print different letters on those buttons). `at` is the glyph's
## top-left: the keycap starts 1 px in; the diamond is 9x9 with a 1 px dark outline, 11 px in all.
static func _draw_pick_button(a: Arena, ci: CanvasItem, at: Vector2, dev: int, c: int) -> void:
	if dev == G.DEV_KBM or dev == -99:
		_draw_keycap(a, ci, at + Vector2(1, 0), str(c + 1), false)
		return
	var dots := [Vector2(0, 3), Vector2(3, 0), Vector2(6, 3), Vector2(3, 6)] # left, top, right, bottom
	for d: Vector2 in dots:
		ci.draw_rect(Rect2(at + d - Vector2(1, 1), Vector2(5, 5)), Occult.INK)
	for d in dots.size():
		ci.draw_rect(Rect2(at + dots[d], Vector2(3, 3)), Color("ffd94d") if d == c else Color("8a7aa8"))
	ci.draw_rect(Rect2(at + dots[c] + Vector2(1, 1), Vector2(1, 1)), Color.WHITE)


## A card bobbing over a wizard with draws waiting, so the player sees it where they look; under the feet when
## the wizard is so near the top of the view that the tabs would cover it.
static func _draw_draw_marker(a: Arena, ci: CanvasItem, slot: int) -> void:
	var col := G.player_color(slot)
	var feet := a._on_screen(a.vp[slot].pos)
	var bob := floorf(sin(a.time * 4.0 + slot) * 1.5)
	var at := (feet + Vector2(-3, -36 + bob)).floor()
	if at.y < G.HUD_H + a.TAB_H + 4.0:
		at.y = floorf(feet.y + 6.0 + bob)
	var pulse := 0.5 + 0.5 * sin(a.time * 5.0)
	var r := Rect2(at, Vector2(7, 9))
	ci.draw_rect(r.grow(2), Color(col, 0.25 + 0.35 * pulse))
	TarotArt.draw_back_icon(ci, r, col)


## Routes the card buttons to local trays: E, LB or LT (or a click on the tab, or on the tray's footer) opens and
## closes a wizard's tray; 1 2 3 or X Y B (or a click on a row) takes a card while it is open. The mouse and touch
## work the keyboard wizard's tray. Returns true if the event was used.
static func _tray_input(a: Arena, event: InputEvent) -> bool:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
		var ks := -1
		for r in Net.my_slots():
			if r.device == G.DEV_KBM:
				ks = r.slot
		if ks < 0 or _draws(a, ks) <= 0:
			return false
		var pos: Vector2 = event.position
		if not _tray_shown(a, ks) or _tray_covered(a):
			if not _tab_rect(a, ks).has_point(pos):
				return false
			_set_tray(a, ks, not _tray_shown(a, ks))
			return true
		if not _tray_rect(a, ks).grow(1).has_point(pos):
			return false
		var n: int = (a.vp[ks].choices as Array).size()
		for c in n:
			if _tray_row_rect(a, ks, c).has_point(pos):
				_take_card(a, ks, c)
		if pos.y >= _tray_row_rect(a, ks, n - 1).end.y:
			_set_tray(a, ks, false) # the footer with HIDE
		return true
	for r in Net.my_slots():
		var slot: int = r.slot
		var dev: int = r.device
		var toggle := false
		var card := -1
		if dev == G.DEV_KBM and event is InputEventKey and event.pressed and not event.echo:
			match event.physical_keycode:
				KEY_E: toggle = true
				KEY_1, KEY_KP_1: card = 0
				KEY_2, KEY_KP_2: card = 1
				KEY_3, KEY_KP_3: card = 2
		elif dev != G.DEV_KBM and event is InputEventJoypadButton and event.pressed and event.device == dev:
			match event.button_index:
				JOY_BUTTON_LEFT_SHOULDER: toggle = true
				JOY_BUTTON_X: card = 0
				JOY_BUTTON_Y: card = 1
				JOY_BUTTON_B: card = 2
		elif dev != G.DEV_KBM and event is InputEventJoypadMotion and event.device == dev \
				and event.axis == JOY_AXIS_TRIGGER_LEFT:
			var was: bool = a._lt_held.get(dev, false)
			a._lt_held[dev] = event.axis_value > 0.5
			toggle = event.axis_value > 0.5 and not was
		if toggle and _draws(a, slot) > 0:
			_set_tray(a, slot, not _tray_shown(a, slot))
			return true
		if card >= 0 and _tray_shown(a, slot):
			if not _tray_covered(a): # under a card reveal or a fate bet the tray is folded away
				_take_card(a, slot, card)
			return true
	return false


## Takes card `c` of `slot`'s hand, only if that row is there and face up. A hand that turned over on screen takes
## no press until it has been face up for TRAY_READ, and no press counts within PICK_GAP of the wizard's last take,
## so a mashed or held button cannot take the next card unseen.
static func _take_card(a: Arena, slot: int, c: int) -> void:
	if c >= (a.vp[slot].choices as Array).size() or _tray_turn(a, slot, c) < 1.0:
		return
	var seen: Array = a._tray_dealt.get(slot, [-1, -10.0, 7, false])
	if bool(seen[3]) and a.time - float(seen[1]) < a.TRAY_FLIP + a.TRAY_READ:
		return
	if a.time - float(a._pick_t.get(slot, -10.0)) < a.PICK_GAP:
		return
	var sent: Array = a._pick_sent.get(slot, [-1, -1])
	if int(sent[1]) == int(a.vp[slot].offer):
		return
	a._pick_sent[slot] = [c, int(a.vp[slot].offer)]
	a._pick_t[slot] = a.time
	Sfx.play("card_pick", -2.0)
