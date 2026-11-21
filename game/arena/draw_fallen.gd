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


## The HUD: an arrow at the screen's edge toward a seat that called in the last ARROW_LIFE s and is out of view.
static func call_arrow(a: Arena, ci: CanvasItem, slot: int) -> void:
	var at := Vector2.INF
	for g: Array in _pings(a):
		if int(g[0]) == slot and a.time - float(g[2]) < ARROW_LIFE:
			at = g[1]
	if not at.is_finite():
		return
	var view := Rect2(Vector2(6, G.HUD_H + 6), G.SCREEN - Vector2(12, G.HUD_H + 12))
	var sp := a._on_screen(at)
	if view.grow(4).has_point(sp):
		return
	var center := view.get_center()
	var d := sp - center
	var tip := center + d * minf((view.size.x / 2.0) / maxf(absf(d.x), 0.001), (view.size.y / 2.0) / maxf(absf(d.y), 0.001))
	var dir := d.normalized()
	var side := Vector2(-dir.y, dir.x)
	var col := Color(G.player_color(slot), 0.65 + 0.35 * sin(a.time * 10.0))
	var pts := PackedVector2Array([tip, tip - dir * 9.0 + side * 5.0, tip - dir * 9.0 - side * 5.0])
	ci.draw_colored_polygon(pts, col)
	ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), INK, 1.0)
	PixelFont.draw(ci, "P%d" % (slot + 1), (tip - dir * 17.0 - Vector2(3, 2)).round(), 1, G.player_color(slot), INK)


## True while a spirit's own clock runs: she has one, and no standing wizard is inside her circle.
static func _clock_runs(a: Arena, p: Dictionary) -> bool:
	if float(p.get("down_left", -1.0)) <= 0.0:
		return false
	for q: Dictionary in a.vp.values():
		if q.alive and (q.pos as Vector2).distance_to(p.pos) <= WorldPlayers.RITUAL_R:
			return false
	return true


## The ritual circle: a dark ring with a dim rim in her colour, filled clockwise from the top by the progress.
static func _draw_circle(a: Arena, ci: CanvasItem, p: Dictionary) -> void:
	var c: Vector2 = p.pos
	var r := WorldPlayers.RITUAL_R
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
	Sprites.draw_at(ci, key + "~", feet + Vector2(0, SpritesWizards.HALO), flip, false, Color(col.lerp(Color.WHITE, 0.3), 0.6))
	Sprites.draw_at(ci, key, feet, flip, false, Color(col.lerp(Color.WHITE, 0.8) * 1.3, 0.5))


static func _pings(a: Arena) -> Array:
	return a.get_meta(META_PINGS, []) as Array
