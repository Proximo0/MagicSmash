class_name TouchControls
extends Node2D
## Twin virtual sticks for phones: touch anywhere on the left half to move,
## anywhere on the right half to aim and auto-cast. Round button = Nova.

signal pause_pressed

const STICK_R := 26.0
const BOMB_POS := Vector2(446, 222)
const BOMB_R := 18.0
const PAUSE_RECT := Rect2(224, 0, 32, 16)

var move_vec := Vector2.ZERO
var aim_vec := Vector2.ZERO
var bomb_down := false
var _move_idx := -1
var _aim_idx := -1
var _bomb_idx := -1
var _move_origin := Vector2(70, 210)
var _aim_origin := Vector2(400, 210)
var _move_pos := Vector2.ZERO
var _aim_pos := Vector2.ZERO

func _input(event: InputEvent) -> void:
	if not G.touch_active:
		return
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			if PAUSE_RECT.has_point(p):
				pause_pressed.emit()
			elif p.distance_to(BOMB_POS) < BOMB_R + 6:
				_bomb_idx = event.index
				bomb_down = true
			elif p.x < G.SCREEN.x / 2 and _move_idx == -1:
				_move_idx = event.index
				_move_origin = p
				_move_pos = p
			elif p.x >= G.SCREEN.x / 2 and _aim_idx == -1:
				_aim_idx = event.index
				_aim_origin = p
				_aim_pos = p
		else:
			if event.index == _move_idx:
				_move_idx = -1
				move_vec = Vector2.ZERO
			elif event.index == _aim_idx:
				_aim_idx = -1
				aim_vec = Vector2.ZERO
			elif event.index == _bomb_idx:
				_bomb_idx = -1
				bomb_down = false
	elif event is InputEventScreenDrag:
		if event.index == _move_idx:
			_move_pos = event.position
			move_vec = ((_move_pos - _move_origin) / STICK_R).limit_length(1.0)
			# Drag the base along so the thumb never runs off the stick.
			if (_move_pos - _move_origin).length() > STICK_R * 1.4:
				_move_origin = _move_pos - (_move_pos - _move_origin).normalized() * STICK_R * 1.4
		elif event.index == _aim_idx:
			_aim_pos = event.position
			aim_vec = ((_aim_pos - _aim_origin) / STICK_R).limit_length(1.0)
			if (_aim_pos - _aim_origin).length() > STICK_R * 1.4:
				_aim_origin = _aim_pos - (_aim_pos - _aim_origin).normalized() * STICK_R * 1.4

func _process(_d: float) -> void:
	visible = G.touch_active
	if visible:
		queue_redraw()

func _draw() -> void:
	var base := Color(1, 1, 1, 0.12)
	var knob := Color(1, 1, 1, 0.35)
	var mo := _move_origin if _move_idx != -1 else Vector2(70, 210)
	var ao := _aim_origin if _aim_idx != -1 else Vector2(390, 210)
	draw_arc(mo, STICK_R, 0, TAU, 32, base, 2.0)
	draw_circle(mo + move_vec * STICK_R, 9.0, knob)
	draw_arc(ao, STICK_R, 0, TAU, 32, Color(1, 0.6, 1, 0.15), 2.0)
	draw_circle(ao + aim_vec * STICK_R, 9.0, Color(1, 0.7, 1, 0.35))
	draw_circle(BOMB_POS, BOMB_R, Color(1, 0.9, 0.3, 0.45 if bomb_down else 0.2))
	draw_arc(BOMB_POS, BOMB_R, 0, TAU, 32, Color(1, 0.9, 0.3, 0.6), 1.0)
	PixelFont.draw_centered(self, "NOVA", BOMB_POS.x, BOMB_POS.y - 3, 1, Color(1, 1, 1, 0.8))
	draw_rect(Rect2(PAUSE_RECT.position + Vector2(11, 4), Vector2(3, 9)), Color(1, 1, 1, 0.5))
	draw_rect(Rect2(PAUSE_RECT.position + Vector2(18, 4), Vector2(3, 9)), Color(1, 1, 1, 0.5))
	PixelFont.draw(self, "MOVE", mo + Vector2(-11, STICK_R + 4), 1, Color(1, 1, 1, 0.3))
	PixelFont.draw(self, "CAST", ao + Vector2(-11, STICK_R + 4), 1, Color(1, 1, 1, 0.3))
