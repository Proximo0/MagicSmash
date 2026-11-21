class_name ArenaTrayArt
extends RefCounted
## Arena: the hand of cards under an open level-up tray, and a boss's arrival picture. Under each open tray the
## offered cards sit side by side, numbered like the tray's rows (buttons 1, 2, 3): the owner's painting when the
## card has one, else a plain card with its emblem. In the lull after a Lich the hand is drawn at double size
## when it fits. The hand never covers the wizard whose tray it is.
## Static helpers: `a` is the Arena that owns the state.

const CARD := Vector2(31, 63)
const GAP := 2.0
## What a wizard's sprite covers around its position on screen.
const WIZARD_BOX := Rect2(-14, -28, 28, 36)
const SCREEN := Rect2(0, 0, 480, 270)


## Drawn last of the level-up cards, over the banners: a boss's arrival picture, then the hand under each open tray.
static func draw_over(a: Arena, ci: CanvasItem, dark: Color) -> void:
	ArenaFateView._draw_arrival(a, ci, dark)
	if ArenaTray._tray_covered(a):
		return
	var used: Array[Rect2] = []
	for slot: int in a.vp.keys():
		if ArenaTray._draws(a, slot) > 0 and ArenaTray._tray_shown(a, slot):
			_hand(a, ci, slot, dark, used)


## One tray's hand. Double size in the lull when all of it fits clear of every wizard and every other hand.
static func _hand(a: Arena, ci: CanvasItem, slot: int, dark: Color, used: Array[Rect2]) -> void:
	var choices: Array = a.vp[slot].choices
	var n := choices.size()
	if n == 0:
		return
	var tray := ArenaTray._tray_rect(a, slot)
	var scale := 1.0
	var at := Vector2(-1, -1)
	if a.lull_left > 0.0:
		at = _spot(a, slot, tray, _hand_size(n, 2.0), used, true)
		if at.x >= 0.0:
			scale = 2.0
	if at.x < 0.0:
		at = _spot(a, slot, tray, _hand_size(n, 1.0), used, false)
	if at.x < 0.0:
		return
	used.append(Rect2(at, _hand_size(n, scale)))
	var col := G.player_color(slot)
	for c in n:
		if ArenaTray._tray_turn(a, slot, c) < 1.0:
			continue # a card still turning over in its row
		var r := Rect2(at + Vector2(c * (CARD.x * scale + GAP), 0), CARD * scale)
		_card(ci, r, Upgrades.key(choices[c]), dark)
		var badge := Rect2(r.position + Vector2(1, 1), Vector2(7, 9))
		ci.draw_rect(badge, Color(dark, 0.85))
		PixelFont.draw(ci, str(c + 1), badge.position + Vector2(1, 1), 1, col.lerp(Color.WHITE, 0.5), dark)


static func _hand_size(n: int, scale: float) -> Vector2:
	return Vector2(n * CARD.x * scale + (n - 1) * GAP, CARD.y * scale)


## One card: the painting when its file exists (drawn 1:1 at this exact size), else a dark face with a thin frame
## in the card's colour and its emblem in the middle.
static func _card(ci: CanvasItem, r: Rect2, key: String, dark: Color) -> void:
	var painting := TarotArt._painting(key)
	if not painting.is_empty():
		Art.draw(ci, "cards/tarot", painting, r)
		return
	var edge: Color = TarotArt._frame_colors(key)[1]
	ci.draw_rect(r, dark)
	ci.draw_rect(r, edge, false, 1.0)
	var es := 16.0 * floorf(minf(r.size.x - 4.0, 32.0) / 16.0)
	ci.draw_texture_rect(TarotArt.emblem(key), Rect2((r.get_center() - Vector2(es, es) / 2.0).floor(), Vector2(es, es)), false)


## The top-left of the hand: under the tray, at its left edge or else its right edge (or, large, also centred on
## the screen), clear of the wizard, the arrival picture and the hands already placed. (-1, -1) when none is.
static func _spot(a: Arena, slot: int, tray: Rect2, size: Vector2, used: Array[Rect2], large: bool) -> Vector2:
	var y := tray.end.y + 3.0
	var wiz := Rect2(a._on_screen((a.vp[slot] as Dictionary).pos as Vector2) + WIZARD_BOX.position, WIZARD_BOX.size)
	var arrival := ArenaFateView._arrival_rect(a)
	for x: float in [tray.position.x, tray.end.x - size.x]:
		var box := Rect2(Vector2(x, y), size).grow(1)
		if large and not SCREEN.encloses(box):
			continue
		var covers := box.intersects(wiz)
		if large: # the big hand must clear every wizard
			for o: Dictionary in a.vp.values():
				covers = covers or box.intersects(Rect2(a._on_screen(o.pos as Vector2) + WIZARD_BOX.position, WIZARD_BOX.size))
		if covers or (arrival.size.x > 0.0 and box.intersects(arrival)):
			continue
		var clash := false
		for u: Rect2 in used:
			clash = clash or box.intersects(u)
		if not clash:
			return Vector2(x, y)
	return Vector2(-1, -1)
