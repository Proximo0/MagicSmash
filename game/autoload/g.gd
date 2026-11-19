extends Node
## Global constants, shared settings and the scene switcher.

const VERSION := "0.2.0"
const SCREEN := Vector2(480, 270)
## Playfield (inside the walls).
const ARENA := Rect2(20, 38, 440, 220)
const MAX_PLAYERS := 4

## Device id -1 is keyboard + mouse + touch, 0..7 are gamepads.
const DEV_KBM := -1

var is_mobile := false
var touch_active := false
var main: Node = null
var last_score := 0
var high_score := 0
var title_message := ""

## Local devices that joined in the lobby on this machine.
var local_devices: Array[int] = []

func _ready() -> void:
	is_mobile = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	touch_active = is_mobile
	Sprites.build_all()
	_load_high_score()
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	# Switch the on-screen sticks on as soon as a finger touches the screen.
	if event is InputEventScreenTouch and not touch_active:
		touch_active = true

func goto_title() -> void:
	if main:
		main.show_title()

func goto_game() -> void:
	if main:
		main.show_game()

func submit_score(s: int) -> void:
	last_score = s
	if s > high_score:
		high_score = s
		if Flags.is_scripted_run():
			return  # bots, sims and captures never write player data
		var f := FileAccess.open("user://save.cfg", FileAccess.WRITE)
		if f:
			f.store_line(str(high_score))

func _load_high_score() -> void:
	if FileAccess.file_exists("user://save.cfg"):
		var f := FileAccess.open("user://save.cfg", FileAccess.READ)
		if f:
			high_score = int(f.get_line())

static func player_color(slot: int) -> Color:
	return Sprites.PLAYER_COLORS[slot % 4].robe

static func player_fx(slot: int) -> Color:
	return Sprites.PLAYER_COLORS[slot % 4].fx
