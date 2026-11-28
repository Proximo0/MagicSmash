class_name ArenaDrawFallen
extends RefCounted
## Arena: the fallen (World's spirits, see WorldPlayers). Each spirit is her wizard drawn pale and half see-through
## in her seat's colour over her ritual circle, a ring that fills clockwise with the ritual's progress; a small
## countdown floats over a spirit whose clock runs; a call for help (World.EV_CALL) pings a ring on her and, while
## she is out of view, an arrow in her colour at the screen's edge. Plain placeholders until the finished art.
## Static helpers: `a` is the Arena that owns the state; the pings live in its metadata (META_PINGS).

const META_PINGS := &"fallen_pings"
## Seconds a call's ring grows and fades, its radii, px, and seconds the edge arrow shows after a call.
const PING_LIFE := 0.9
const PING_R0 := 6.0
const PING_R1 := 28.0
const ARROW_LIFE := 2.0
const RING_BACK := Color(0.05, 0.03, 0.1, 0.55)
const INK := Color(0.04, 0.02, 0.08, 1.0)


## The wizards' layer: every spirit with her circle and clock, then the pings.
static func draw(a: Arena, ci: CanvasItem) -> void:
	for p: Dictionary in a.vp.values():
		if not p.get("down", false):
			continue
		_draw_circle(a, ci, p)
		_draw_spirit(a, ci, p)
		if _clock_runs(a, p):
			var t := "%d" % ceili(float(p.down_left))
			var at: Vector2 = (p.pos as Vector2) + Vector2(-PixelFont.text_width(t) / 2.0, -30.0)
			PixelFont.draw(ci, t, at, 1, Color("fff6e0"), INK)
	var keep: Array = []
	for g: Array in _pings(a):
		var k: float = (a.time - float(g[2])) / PING_LIFE
		if k < 0.0 or k >= 1.0:
			if a.time - float(g[2]) < ARROW_LIFE:
				keep.append(g)
			continue
		keep.append(g)
		var col := G.player_color(int(g[0])).lerp(Color.WHITE, 0.3)
		ci.draw_arc(g[1], lerpf(PING_R0, PING_R1, k), 0.0, TAU, 32, Color(col, 1.0 - k), 2.0)
	a.set_meta(META_PINGS, keep)


## A call for help (World.EV_CALL: x, y, a = slot).
static func on_call(a: Arena, ev: Array) -> void:
	var list := _pings(a)
	list.append([int(ev[3]), Vector2(ev[1], ev[2]) + Vector2(0, -8), a.time])
	a.set_meta(META_PINGS, list)
	Sfx.play("ghost", -6.0, 1.5)


## The opacity of `slot`'s edge arrow (drawn by ArenaHud, one per wizard out of view): 1.0 while steady, a blink
## between 0.3 and 1.0 for ARROW_LIFE s after her call for help.
static func call_blink(a: Arena, slot: int) -> float:
	for g: Array in _pings(a):
		if int(g[0]) == slot and a.time - float(g[2]) < ARROW_LIFE:
			return 0.65 + 0.35 * sin(a.time * 10.0)
	return 1.0


## True while a spirit's own clock runs: she has one, and no standing wizard is inside her circle.
static func _clock_runs(a: Arena, p: Dictionary) -> bool:
	if float(p.get("down_left", -1.0)) <= 0.0:
		return false
	for q: Dictionary in a.vp.values():
		if q.alive and (q.pos as Vector2).distance_to(p.pos) <= Tuning.shared().ritual_radius:
			return false
	return true


## The ritual circle: a dark ring with a dim rim in her colour, filled clockwise from the top by the progress.
static func _draw_circle(a: Arena, ci: CanvasItem, p: Dictionary) -> void:
	var c: Vector2 = p.pos
	var r := Tuning.shared().ritual_radius
	var col := G.player_color(int(p.slot))
	var beat := 0.75 + 0.25 * sin(a.time * 3.0)
	ci.draw_arc(c, r, 0.0, TAU, 48, RING_BACK, 4.0)
	ci.draw_arc(c, r, 0.0, TAU, 48, Color(col, 0.35 * beat), 1.0)
	var prog := clampf(float(p.get("revive", 0.0)), 0.0, 1.0)
	if prog > 0.0:
		ci.draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * prog, maxi(4, int(48 * prog)), col.lerp(Color.WHITE, 0.45), 3.0)


## The spirit: her wizard's idle sprite, pale and half see-through, floating a little over her feet.
static func _draw_spirit(a: Arena, ci: CanvasItem, p: Dictionary) -> void:
	var slot: int = p.slot
	var aim: Vector2 = p.aim
	var dirkey := "down"
	var flip := false
	if absf(aim.y) > absf(aim.x) * 1.1:
		dirkey = "up" if aim.y < 0 else "down"
	else:
		dirkey = "side"
		flip = aim.x < 0
	var key := SpritesWizards.frame_key(G.wizard_of(slot), dirkey, false, 0, int(a.time * 2.0 + slot * 0.5), false, aim.x >= 0.0)
	var feet: Vector2 = (p.pos as Vector2) + Vector2(0, -2.0 + roundf(sin(a.time * 2.5 + slot) * 1.5))
	var col := G.player_color(slot)
	var still := Still.hero_name(int(p.get("cls", 0)), bool(p.get("ai", false)), int(p.get("race", -1)))
	if not still.is_empty():
		_draw_spirit_still(a, ci, still, feet, -1 if flip else 1, col, slot)
		return
	# A 1 px rim in her seat's colour (the sprite's white flash frame, tinted, one pixel out each way), so she can be
	# found in a crowd, then the body pale and half see-through over it.
	var rim := Color(col.lerp(Color.WHITE, 0.15), 0.9)
	for o: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		Sprites.draw_at(ci, key, feet + o, flip, true, rim)
	Sprites.draw_at(ci, key, feet, flip, false, Color(col.lerp(Color.WHITE, 0.85) * 1.4, 0.72))


## The spirit from her still picture: the same rim and pale body as the code sprite's.
static func _draw_spirit_still(a: Arena, ci: CanvasItem, still: String, feet: Vector2, facing: int, col: Color, slot: int) -> void:
	var t: float = a.time + slot * 0.5
	var rim := Color(col.lerp(Color.WHITE, 0.15), 0.9)
	for o: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		Still.draw(ci, still, feet + o, facing, t, false, rim, true)
	Still.draw(ci, still, feet, facing, t, false, Color(col.lerp(Color.WHITE, 0.85) * 1.4, 0.72))


static func _pings(a: Arena) -> Array:
	return a.get_meta(META_PINGS, []) as Array
