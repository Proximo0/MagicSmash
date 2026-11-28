extends Node
## Global constants, shared settings and the scene switcher.

const VERSION := "0.9.0"
const SCREEN := Vector2(480, 270)
## The whole arena image, walls included: bigger than the screen, so the camera follows the party around it.
const WORLD := Vector2(800, 450)
## Playfield (inside the walls).
const ARENA := Rect2(20, 38, 760, 400)
## The top of the screen the HUD covers.
const HUD_H := 27.0
const MAX_PLAYERS := 4

## Device id -1 is keyboard + mouse + touch, 0..7 are gamepads. -2 is an apprentice (a computer wizard, no
## device; Net.add_apprentice) and -3 the second keyboard seat (arrows and right Ctrl, PlayerInput).
const DEV_KBM := -1
const DEV_AI := -2
const DEV_KB2 := -3

var is_mobile := false
var touch_active := false
var main: Node = null
var last_score := 0
var high_score := 0
var title_message := ""
## The run that just ended, for Morvane's line in the Sanctum: {result: "loss"|"win", act, seal}. Taken once.
var last_run: Dictionary = {}
## Talk lines said this session ("<speaker>/<condition>"), so a first-time line is said once.
var talk_seen: Dictionary = {}
## The id of the last line each speaker said (Talk.pick's `last`).
var talk_last: Dictionary = {}

## Profile hero indices the local human seats play this run (the lobby sets it, Net.seat_heroes; never a guest).
## Empty in a scripted run, so no hero earns anything there.
var run_heroes: Array[int] = []

## Local devices that joined in the lobby on this machine.
var local_devices: Array[int] = []

func _ready() -> void:
	is_mobile = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	touch_active = is_mobile
	Sprites.build_all()
	high_score = Save.profile.high_score
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	PlayerInput.note_key(event) # keyboard seat 2's right-hand keys
	# F11 and Alt+Enter: fullscreen or the last window size, from anywhere (not on a phone or in a scripted run).
	if event is InputEventKey and event.pressed and not event.echo and not is_mobile and not Flags.is_scripted_run():
		if event.physical_keycode == KEY_F11 or (event.alt_pressed and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]):
			Save.settings.toggle_fullscreen()
			Save.apply_settings()
			Save.write_settings()
			get_viewport().set_input_as_handled()
			return
	# Switch the on-screen sticks on as soon as a finger touches the screen.
	if event is InputEventScreenTouch and not touch_active:
		touch_active = true
	# A keyboard player presses WASD at once: the last input used wins, so one touch does not end mouse aiming.
	elif event is InputEventKey and event.pressed and not is_mobile:
		touch_active = false

func goto_title() -> void:
	if main:
		main.show_title()

## The Sanctum between runs (offline play only).
func goto_sanctum() -> void:
	if main:
		main.show_sanctum()

## Back to the title, straight into the lobby with `device` already in (the Sanctum's portal).
var title_lobby_device := -99
## The title opens on the unlocks (the Sanctum's shopkeeper) and its back goes to the Sanctum.
var title_shop := false

func goto_title_lobby(device: int) -> void:
	title_lobby_device = device
	goto_title()

func goto_game() -> void:
	if main:
		main.show_game()

## Books a finished run in the profile (best score, crystals) through Save. Returns the crystals earned.
## `run` is Profile.finish_run's dictionary: score, seconds, kills, liches, won (and seal, act, results, and party: Achievements.earned's classes, races and seal).
func finish_run(run: Dictionary) -> int:
	last_score = int(run.get("score", 0))
	last_run = {"result": "win" if bool(run.get("won", false)) else "loss", "act": int(run.get("act", -1)),
		"seal": int(run.get("seal", 0))}
	var booked := run.duplicate()
	booked["heroes"] = [] if Flags.is_scripted_run() and not Net.force_heroes else run_heroes.duplicate()
	var earned := Save.finish_run(booked)
	last_run["hero_levels"] = Save.profile.last_hero_levels.duplicate()
	high_score = Save.profile.high_score
	return earned

## Slot -> picked wizard (Wizards index) for drawing, filled from snapshots. A slot not in it shows its own colour.
var slot_wizard := {}

func wizard_of(slot: int) -> int:
	return int(slot_wizard.get(slot, slot % 4))

func player_color(slot: int) -> Color:
	return Sprites.PLAYER_COLORS[wizard_of(slot)].robe

func player_fx(slot: int) -> Color:
	return Sprites.PLAYER_COLORS[wizard_of(slot)].fx
