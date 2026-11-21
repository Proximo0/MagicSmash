class_name CrowdLayer
extends Node2D
## Two plain things drawn in world px under (the ground grid) or over (my ring) the figures.

var is_ground: bool = true
var field: Vector2 = Vector2(16384, 16384)
## World px at the screen's top left and bottom right.
var view: Rect2 = Rect2()
var me_tex: Texture2D = null
var me_pos: Vector2 = Vector2.ZERO
var me_flip: bool = false
var px_scale: float = 1.0

const GRID: float = 64.0
const GRID_COL: Color = Color(1, 1, 1, 0.045)
const EDGE_COL: Color = Color(0.9, 0.3, 0.3, 0.6)
const RING_COL: Color = Color(1.0, 0.85, 0.3, 0.95)


func _draw() -> void:
	if is_ground:
		_draw_grid()
	else:
		_draw_me()


func _draw_grid() -> void:
	var x0: float = maxf(0.0, floorf(view.position.x / GRID) * GRID)
	var x1: float = minf(field.x, view.end.x)
	var y0: float = maxf(0.0, floorf(view.position.y / GRID) * GRID)
	var y1: float = minf(field.y, view.end.y)
	var w: float = 1.0 / px_scale
	var x: float = x0
	while x <= x1:
		draw_line(Vector2(x, y0), Vector2(x, y1), GRID_COL, w)
		x += GRID
	var y: float = y0
	while y <= y1:
		draw_line(Vector2(x0, y), Vector2(x1, y), GRID_COL, w)
		y += GRID
	draw_rect(Rect2(0, 0, field.x, field.y), EDGE_COL, false, 2.0 / px_scale)


func _draw_me() -> void:
	draw_set_transform(me_pos + Vector2(0, 1), 0.0, Vector2(1, 0.45))
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 28, RING_COL, 1.5 / px_scale)
	if me_tex:
		var sz := me_tex.get_size()
		draw_set_transform(me_pos, 0.0, Vector2(-1.0 if me_flip else 1.0, 1.0))
		draw_texture(me_tex, Vector2(-sz.x / 2.0, -sz.y))
