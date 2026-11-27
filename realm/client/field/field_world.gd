class_name FieldWorld
extends Node2D
## The field's fixed features over the ground grid: the gate, the heart and its rings, seven waystones (stand
## within 48 px and hold interact to bank) and six war altars (they glow during a tide). Positions come from
## `RealmLink.world().sites` (px pairs: gate, heart, waystones 0..6, altars 0..5).

const RING_HEART_PX: float = 2500.0
const RING_EDGE_PX: float = 6000.0
const BANK_PX: float = 48.0
const RING_COL: Color = Color(0.7, 0.55, 0.9, 0.14)
const STONE_COL: Color = Color(0.7, 0.72, 0.8)
const GLOW_COL: Color = Color(0.45, 0.8, 1.0)
const ALTAR_COL: Color = Color(0.8, 0.5, 0.25)

var sites: PackedFloat32Array = PackedFloat32Array()
var tide: bool = false
var view: Rect2 = Rect2()
var px_scale: float = 1.0
## The waystone the hero banked at is marked brighter (-1 none).
var banked_at: int = -1
## Pictures from art/field_<name>.png (tools/char3d field_models.py), bottom centre on the site; "" until looked up,
## null when the file is missing (the stand-in drawing is used then).
var _tex: Dictionary = {}


func _pic(key: String) -> Texture2D:
	if not _tex.has(key):
		var path: String = "res://art/field_%s.png" % key
		_tex[key] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _tex[key]


## Draws the picture standing on `at`; false when there is none.
func _stand(key: String, at: Vector2, tint: Color = Color.WHITE) -> bool:
	var t: Texture2D = _pic(key)
	if t == null:
		return false
	var sz: Vector2 = t.get_size()
	draw_texture_rect(t, Rect2(at - Vector2(sz.x * 0.5, sz.y - 2.0), sz), false, tint)
	return true


func _site(i: int) -> Vector2:
	return Vector2(sites[i * 2], sites[i * 2 + 1])


func _draw() -> void:
	if sites.size() < 2 * 15:
		return
	var w: float = 1.0 / px_scale
	var wall: float = float(Time.get_ticks_msec()) / 1000.0
	var heart: Vector2 = _site(1)
	for r in [RING_HEART_PX, RING_EDGE_PX]:
		# Only the part of the ring near the view: a ring is a long way round.
		if absf(view.get_center().distance_to(heart) - r) < view.size.length() * 0.6:
			var a0: float = (view.get_center() - heart).angle()
			var span: float = clampf(view.size.length() / r, 0.05, PI)
			draw_arc(heart, r, a0 - span, a0 + span, 64, RING_COL, 3.0 * w, true)
	if view.grow(300).has_point(heart):
		_stand("heart", heart)
	var gate: Vector2 = _site(0)
	if view.grow(40).has_point(gate) and _stand("gate", gate):
		pass
	elif view.grow(40).has_point(gate):
		draw_rect(Rect2(gate + Vector2(-26, -26), Vector2(8, 26)), STONE_COL)
		draw_rect(Rect2(gate + Vector2(18, -26), Vector2(8, 26)), STONE_COL)
		draw_rect(Rect2(gate + Vector2(-26, -30), Vector2(52, 5)), STONE_COL.darkened(0.2))
		var fs: int = UiKit.crisp("jersey10", clampi(roundi(get_viewport().get_final_transform().x.x / px_scale), 1, 8))
		var gw: float = UiKit.font().get_string_size("GATE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(UiKit.font(), (gate + Vector2(-gw / 2.0, 12.0 + fs * 0.6)).round(), "GATE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.85, 0.9))
	for k in 7:
		var p: Vector2 = _site(2 + k)
		if not view.grow(60).has_point(p):
			continue
		var mine: bool = k == banked_at
		var glow := Color(GLOW_COL.r, GLOW_COL.g, GLOW_COL.b, 0.6 if mine else 0.25)
		draw_arc(p, BANK_PX, 0.0, TAU, 32, glow, 1.5 * w, true)
		draw_circle(p, BANK_PX, Color(glow.r, glow.g, glow.b, 0.05))
		var flick: float = 0.6 + 0.4 * sin(wall * 4.0 + k)
		if _pic("waystone") != null:
			# The lit picture while the hero banks here; otherwise a dormant stone that breathes a little.
			var key: String = "waystone_lit" if mine and _pic("waystone_lit") != null else "waystone"
			_stand(key, p, Color.WHITE if mine else Color(1, 1, 1, 0.9 + 0.1 * flick))
			continue
		draw_rect(Rect2(p + Vector2(-4, -22), Vector2(8, 22)), STONE_COL)
		draw_rect(Rect2(p + Vector2(-6, -4), Vector2(12, 4)), STONE_COL.darkened(0.25))
		draw_circle(p + Vector2(0, -25), 3.0, Color(GLOW_COL.r, GLOW_COL.g, GLOW_COL.b, flick))
	for k in 6:
		var p2: Vector2 = _site(9 + k)
		if not view.grow(160).has_point(p2):
			continue
		var lit: float = (0.7 + 0.3 * sin(wall * 5.0 + k)) if tide else 0.15
		var pictured: bool = false
		if _pic("altar") != null:
			pictured = _stand("altar", p2)
			if tide and _pic("altar_lit") != null:
				_stand("altar_lit", p2, Color(1, 1, 1, lit))
		if not pictured:
			draw_rect(Rect2(p2 + Vector2(-9, -10), Vector2(18, 10)), STONE_COL.darkened(0.45))
			draw_rect(Rect2(p2 + Vector2(-7, -14), Vector2(14, 5)), STONE_COL.darkened(0.3))
			draw_circle(p2 + Vector2(0, -16), 4.0, Color(ALTAR_COL.r, ALTAR_COL.g, ALTAR_COL.b, lit))
		if tide:
			draw_arc(p2, 150.0, 0.0, TAU, 40, Color(1.0, 0.5, 0.2, 0.25), 2.0 * w, true)
