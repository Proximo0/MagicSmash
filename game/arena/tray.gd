class_name ArenaTray
extends RefCounted
## Arena: the level-up tab, the head marker and the card tray, and taking a card.
## Static helpers: `a` is the Arena that owns the state.

## True while any wizard holds cards (the autotest keys shots on it).
## Left edge of each seat's tab and tray. The outer seats hang under their panel; the inner two lean into the
## empty middle column of the HUD strip. Four 118 px trays with their 1 px rims fill the 480 px exactly: the
## spacing is 120, so no two rims share a pixel.
const TRAY_X: Array[int] = [1, 121, 241, 361]
## Where each open tray is drawn: a Node2D per seat under the HUD, so its opacity can ease (Arena meta keys).
const META_LAYERS := &"tray_layers"
const META_ALPHAS := &"tray_alphas"
## Seconds a card's button is held to banish it.
const BANISH_HOLD := 1.0
## A card button held down, per local slot: [card, time pressed, offer, the Arena's instance id]. Only while the wizard has banishes left
## does a press wait for its release (a take) or for BANISH_HOLD (a banish); otherwise a press takes at once.
static var _holds := {}


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


## The tab and the tray hang under the HUD strip at TRAY_X, under or right beside the wizard's own HUD panel.
static func _tab_rect(a: Arena, slot: int) -> Rect2:
	return Rect2(TRAY_X[slot], G.HUD_H + 1, a.TRAY_W, a.TAB_H)


static func _tray_rect(a: Arena, slot: int) -> Rect2:
	var n: int = (a.vp[slot].choices as Array).size()
	return Rect2(TRAY_X[slot], G.HUD_H + 1, a.TRAY_W, 1 + n * a.TRAY_ROW_H + 8)


static func _tray_row_rect(a: Arena, slot: int, c: int) -> Rect2:
	return Rect2(TRAY_X[slot] + 1, G.HUD_H + 1 + c * a.TRAY_ROW_H, a.TRAY_W - 2, a.TRAY_ROW_H)


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


## True while a fate bet fills the middle of the screen: the trays fold down to their tabs and the take buttons do
## nothing (opening and closing still work). A monster card's notice sits under the HUD and covers nothing.
static func _tray_covered(a: Arena) -> bool:
	for b: Dictionary in a._bets:
		if b.kind == Gamble.TEAM:
			return true
	return false


## The level-up cards on screen: a tab under the HUD panel of every wizard with draws waiting, or the open tray of
## a local wizard; then a marker over each living wizard with a tab, drawn last so no tray hides it.
static func _draw_draws(a: Arena, ci: CanvasItem, dark: Color) -> void:
	var covered := _tray_covered(a)
	var marked: Array[int] = []
	var live: Array[int] = []
	hide_trays(a)
	for slot: int in a.vp.keys():
		if _draws(a, slot) <= 0:
			continue
		if _tray_shown(a, slot) and not covered:
			_show_tray(a, slot, dark)
			live.append(slot)
			continue
		_draw_tab(a, ci, slot, dark)
		# The marker waits out the LEVEL UP call-out, which rises from the same spot.
		if a.vp[slot].alive and a.time - float(a._tab_flash.get(slot, -10.0)) > 0.6:
			marked.append(slot)
	for slot: int in marked:
		_draw_draw_marker(a, ci, slot)
	for slot: int in (a.get_meta(META_ALPHAS, {}) as Dictionary).keys():
		if not live.has(slot):
			(a.get_meta(META_ALPHAS) as Dictionary).erase(slot)
	ArenaTrayArt.draw_over(a, ci, dark)


static func _layers(a: Arena) -> Dictionary:
	if not a.has_meta(META_LAYERS):
		a.set_meta(META_LAYERS, {})
	return a.get_meta(META_LAYERS)


## Hides every open tray's layer. The HUD calls it while the game is paused or over, when it draws no tray: a layer
## left visible would stay on top of the pause and results screens.
static func hide_trays(a: Arena) -> void:
	for n: Node2D in _layers(a).values():
		if is_instance_valid(n):
			n.visible = false


## Draws seat `slot`'s open tray on its own layer, see-through while a living wizard's body is under it.
static func _show_tray(a: Arena, slot: int, dark: Color) -> void:
	var layers := _layers(a)
	var n: Node2D = layers.get(slot)
	if n == null or not is_instance_valid(n):
		n = Node2D.new()
		n.draw.connect(_draw_tray.bind(a, n, slot, dark))
		a.hud.add_child(n)
		layers[slot] = n
	var bodies: Array[Rect2] = []
	for p: Dictionary in a.vp.values():
		if ArenaDrawWorld.in_the_run(p):
			bodies.append(ArenaTrayArt.wizard_body_at(a._on_screen(p.pos)))
	var glass := ArenaTrayArt.tray_hides_wizard(_tray_rect(a, slot), bodies)
	if not a.has_meta(META_ALPHAS):
		a.set_meta(META_ALPHAS, {})
	var alphas: Dictionary = a.get_meta(META_ALPHAS)
	var seen: Array = alphas.get(slot, [ArenaTrayArt.TRAY_GLASS if glass else ArenaTrayArt.TRAY_SOLID, a.time])
	var alpha := ArenaTrayArt.tray_alpha_toward(float(seen[0]), glass, clampf(a.time - float(seen[1]), 0.0, 0.1))
	alphas[slot] = [alpha, a.time]
	n.modulate.a = alpha
	n.visible = true
	n.queue_redraw()


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
		var label := _tray_key(dev)
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
		if Upgrades.kind(idx) == Upgrades.MINOR:
			lv_text = "MINOR"
		var title := Classes.card_name(int(p.get("cls", 0)), idx)
		if title == Upgrades.display_name(idx):
			title = Upgrades.row_name(idx) # no class skin: the row's own name, cut to fit
		TarotArt.draw_card_row(ci, rr, Upgrades.key(idx), title, Upgrades.description(idx), lv_text, 11.0)
		_draw_pick_button(a, ci, rr.position + Vector2(1, 4), dev, c)
		if k < 0.75:
			ci.draw_rect(rr, Color(1, 1, 1, (0.75 - k) * 3.0))
		var held := _hold_left(a, slot, c)
		if held > 0.0:
			# A card held toward a banish: a red bar fills along its foot.
			ci.draw_rect(Rect2(rr.position.x, rr.end.y - 2, rr.size.x * held, 2), Color("ff4d6a"))
	_update_hold(a, slot)
	var fy := r.end.y - 8.0
	var fx := r.position.x + 3
	if _draws(a, slot) > 1:
		# Draws waiting behind this hand: a small card back and +N.
		TarotArt.draw_back_icon(ci, Rect2(Vector2(fx + 1, fy - 1), Vector2(5, 7)), col)
		PixelFont.draw(ci, "+%d" % (_draws(a, slot) - 1), Vector2(fx + 8, fy), 1, Color("ffd94d"), dark)
		fx += 22
	_draw_build_tools(a, ci, Vector2(fx, fy), dev, p, dark)
	var label := _tray_key(dev)
	var hx := r.end.x - 2 - PixelFont.text_width("HIDE")
	PixelFont.draw(ci, "HIDE", Vector2(hx, fy), 1, Color("8a7aa8"), dark)
	_draw_keycap(a, ci, Vector2(hx - 4 - PixelFont.text_width(label) - 2, fy - 1), label, false)


## The tray footer's redraws and banishes left: the redraw key (R, or DN for the pad's d-pad) and its count, then
## a struck-out card and the banishes' count (hold a card's button to banish it). Spent ones dim.
static func _draw_build_tools(a: Arena, ci: CanvasItem, at: Vector2, dev: int, p: Dictionary, dark: Color) -> void:
	var redraws := int(p.get("redraws", 0))
	var banishes := int(p.get("banishes", 0))
	var key := "R" if dev == G.DEV_KBM or dev == -99 else ("O" if dev == G.DEV_KB2 else "DN")
	_draw_keycap(a, ci, at + Vector2(0, -1), key, false)
	var x := at.x + PixelFont.text_width(key) + 4
	PixelFont.draw(ci, str(redraws), Vector2(x, at.y), 1, Color("8bff9e") if redraws > 0 else Color("5a4f70"), dark)
	x += PixelFont.text_width(str(redraws)) + 5
	var icon := Rect2(Vector2(x, at.y - 1), Vector2(5, 7))
	TarotArt.draw_back_icon(ci, icon, Color("ff4d6a") if banishes > 0 else Color("5a4f70"))
	for d in 5:
		ci.draw_rect(Rect2(icon.position + Vector2(d, 1 + d), Vector2(1, 1)), Color("ff4d6a") if banishes > 0 else Color("5a4f70"))
	PixelFont.draw(ci, str(banishes), Vector2(x + 8, at.y), 1, Color("ff8a9a") if banishes > 0 else Color("5a4f70"), dark)


## Keyboard seat 2's card keys (its tray key is P, its redraw key O): the right hand's end of the number row.
const KB2_CARDS: Array[String] = ["8", "9", "0"]


## The key that opens and hides a seat's tray, as its keycap reads.
static func _tray_key(dev: int) -> String:
	return "E" if dev == G.DEV_KBM else ("I" if dev == G.DEV_KB2 else "LB")


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
	if dev == G.DEV_KB2:
		_draw_keycap(a, ci, at + Vector2(1, 0), KB2_CARDS[c], false)
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
	if (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and not event.pressed):
		# Letting go of a card row held toward a banish takes the card instead.
		for r in Net.my_slots():
			var h: Array = _hold_of(a, r.slot) if r.device == G.DEV_KBM else []
			if not h.is_empty():
				return _release_hold(a, r.slot, int(h[0]))
		return false
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
				_press_card(a, ks, c)
		if pos.y >= _tray_row_rect(a, ks, n - 1).end.y:
			_set_tray(a, ks, false) # the footer with HIDE
		return true
	for r in Net.my_slots():
		var slot: int = r.slot
		var dev: int = r.device
		var toggle := false
		var card := -1
		var redraw := false
		var released := -1
		if dev == G.DEV_KBM and event is InputEventKey and not event.echo:
			var k := -1
			match event.physical_keycode:
				KEY_E: toggle = event.pressed
				KEY_R: redraw = event.pressed
				KEY_1, KEY_KP_1: k = 0
				KEY_2, KEY_KP_2: k = 1
				KEY_3, KEY_KP_3: k = 2
			if event.pressed:
				card = k
			else:
				released = k
		elif dev == G.DEV_KB2 and event is InputEventKey and not event.echo:
			var k := -1
			match event.physical_keycode:
				KEY_I: toggle = event.pressed # not P: that pauses
				KEY_O: redraw = event.pressed
				KEY_8, KEY_KP_8: k = 0
				KEY_9, KEY_KP_9: k = 1
				KEY_0, KEY_KP_0: k = 2
			if event.pressed:
				card = k
			else:
				released = k
		elif dev != G.DEV_KBM and event is InputEventJoypadButton and event.device == dev:
			var k := -1
			match event.button_index:
				JOY_BUTTON_LEFT_SHOULDER: toggle = event.pressed
				JOY_BUTTON_DPAD_DOWN: redraw = event.pressed
				JOY_BUTTON_X: k = 0
				JOY_BUTTON_Y: k = 1
				JOY_BUTTON_B: k = 2
			if event.pressed:
				card = k
			else:
				released = k
		if released >= 0 and _release_hold(a, slot, released):
			return true
		if redraw and _tray_shown(a, slot) and not _tray_covered(a):
			if int(a.vp[slot].get("redraws", 0)) > 0:
				_send_pick(a, slot, Upgrades.REDRAW_INPUT)
			return true
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
				_press_card(a, slot, card)
			return true
	return false


## A card's button went down: with banishes left the press waits (a release takes it, BANISH_HOLD seconds held
## banishes it); without, or on a Minor Arcana card (never banished), it takes the card at once.
static func _press_card(a: Arena, slot: int, c: int) -> void:
	var choices: Array = a.vp[slot].choices
	if c >= choices.size():
		return
	if int(a.vp[slot].get("banishes", 0)) <= 0 or Upgrades.kind(int(choices[c])) == Upgrades.MINOR:
		_take_card(a, slot, c)
		return
	if _tray_turn(a, slot, c) < 1.0:
		return
	_holds[slot] = [c, a.time, int(a.vp[slot].offer), a.get_instance_id()]


## `slot`'s hold, if it was started on this arena (holds live in a static, so one never outlives its arena).
static func _hold_of(a: Arena, slot: int) -> Array:
	if not _holds.has(slot):
		return []
	if int(_holds[slot][3]) != a.get_instance_id():
		_holds.erase(slot)
		return []
	return _holds[slot]


## Card `c`'s button came up: if it was held (and not yet banished), takes the card. True if it was held.
static func _release_hold(a: Arena, slot: int, c: int) -> bool:
	var h: Array = _hold_of(a, slot)
	if h.is_empty() or int(h[0]) != c:
		return false
	_holds.erase(slot)
	if a.vp.has(slot) and int(h[2]) == int(a.vp[slot].offer) and _tray_shown(a, slot) and not _tray_covered(a):
		_take_card(a, slot, c)
	return true


## How far `slot`'s held card `c` is toward a banish, 0..1 (0: not held).
static func _hold_left(a: Arena, slot: int, c: int) -> float:
	var h: Array = _hold_of(a, slot)
	if h.is_empty() or int(h[0]) != c:
		return 0.0
	return clampf((a.time - float(h[1])) / BANISH_HOLD, 0.0, 1.0)


## Each frame the tray is up: a hold that reached BANISH_HOLD banishes its card; a hold on a hand that is gone ends.
static func _update_hold(a: Arena, slot: int) -> void:
	var h: Array = _hold_of(a, slot)
	if h.is_empty():
		return
	if int(h[2]) != int(a.vp[slot].offer) or _tray_covered(a):
		_holds.erase(slot)
		return
	if a.time - float(h[1]) >= BANISH_HOLD:
		_holds.erase(slot)
		_send_pick(a, slot, Upgrades.BANISH_INPUT + int(h[0]))
		Sfx.play("menu_move", -2.0, 0.7)


## Takes card `c` of `slot`'s hand, only if that row is there and face up. A hand that turned over on screen takes
## no press until it has been face up for TRAY_READ, and no press counts within PICK_GAP of the wizard's last take,
## so a mashed or held button cannot take the next card unseen.
static func _take_card(a: Arena, slot: int, c: int) -> void:
	if c >= (a.vp[slot].choices as Array).size() or _tray_turn(a, slot, c) < 1.0:
		return
	if _send_pick(a, slot, c):
		Sfx.play("card_pick", -2.0)


## Sends input field 6 = `value` for `slot`'s current hand (a card, Upgrades.REDRAW_INPUT or BANISH_INPUT + card),
## once per hand and not within PICK_GAP of the last, nor before a hand that turned over has been read. True if
## sent.
static func _send_pick(a: Arena, slot: int, value: int) -> bool:
	var seen: Array = a._tray_dealt.get(slot, [-1, -10.0, 7, false])
	if bool(seen[3]) and a.time - float(seen[1]) < a.TRAY_FLIP + a.TRAY_READ:
		return false
	if a.time - float(a._pick_t.get(slot, -10.0)) < a.PICK_GAP:
		return false
	var sent: Array = a._pick_sent.get(slot, [-1, -1])
	if int(sent[1]) == int(a.vp[slot].offer):
		return false
	a._pick_sent[slot] = [value, int(a.vp[slot].offer)]
	a._pick_t[slot] = a.time
	if value == Upgrades.REDRAW_INPUT:
		Sfx.play("card_deal", -2.0)
	return true
