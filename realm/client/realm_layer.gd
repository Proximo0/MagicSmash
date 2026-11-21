class_name RealmLayer
extends Node2D
## Two plain things drawn in field px: under the figures the ground grid and the field's edge; over them
## this player's hero with a ring at its feet (from game/crowd/crowd_layer.gd).

const FIELD: Vector2 = Vector2(16384, 16384)
const GRID: float = 64.0
const GRID_COL: Color = Color(1, 1, 1, 0.045)
const EDGE_COL: Color = Color(0.9, 0.3, 0.3, 0.6)
const RING_COL: Color = Color(1.0, 0.85, 0.3, 0.95)
const DEAD_COL: Color = Color(0.55, 0.55, 0.6, 0.45)
## Grid lines are left out when they would be closer than this on screen (px).
const GRID_MIN_SCREEN_PX: float = 6.0
## The hero's ring: 15 field px across at zoom 1, never smaller than this many screen px when zoomed out.
const RING_PX: float = 15.0
const RING_MIN_SCREEN_PX: float = 14.0

var is_ground: bool = true
## Field px on screen.
var view: Rect2 = Rect2()
## Screen px per field px.
var px_scale: float = 1.0
var hero_tex: Texture2D = null
var hero_pos: Vector2 = Vector2.ZERO
var hero_flip: bool = false
var hero_alive: bool = true


func _draw() -> void:
	if is_ground:
		_draw_grid()
	else:
		_draw_hero()


func _draw_grid() -> void:
	var w: float = 1.0 / px_scale
	var step: float = GRID
	while step * px_scale < GRID_MIN_SCREEN_PX:
		step *= 2.0
	var x0: float = maxf(0.0, floorf(view.position.x / step) * step)
	var x1: float = minf(FIELD.x, view.end.x)
	var y0: float = maxf(0.0, floorf(view.position.y / step) * step)
	var y1: float = minf(FIELD.y, view.end.y)
	var x: float = x0
	while x <= x1:
		draw_line(Vector2(x, y0), Vector2(x, y1), GRID_COL, w)
		x += step
	var y: float = y0
	while y <= y1:
		draw_line(Vector2(x0, y), Vector2(x1, y), GRID_COL, w)
		y += step
	draw_rect(Rect2(Vector2.ZERO, FIELD), EDGE_COL, false, 2.0 * w)


func _draw_hero() -> void:
	if hero_tex == null:
		return
	var ring_w: float = maxf(1.5 / px_scale, 0.5)
	var ring: float = maxf(RING_PX, RING_MIN_SCREEN_PX / px_scale)
	draw_set_transform(hero_pos + Vector2(0, 1), 0.0, Vector2(1, 0.45))
	draw_arc(Vector2.ZERO, ring, 0.0, TAU, 28, RING_COL, ring_w)
	var sz := hero_tex.get_size()
	draw_set_transform(hero_pos, 0.0, Vector2(-1.0 if hero_flip else 1.0, 1.0))
	draw_texture(hero_tex, Vector2(-sz.x / 2.0, -sz.y), Color.WHITE if hero_alive else DEAD_COL)
