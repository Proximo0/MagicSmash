class_name ShellSettings
extends RefCounted
## What the settings screen keeps (user://settings.cfg): the keys, the volume, the window. The field client and
## the town read keys through `key(action)`; `apply()` sets the volume and the window. A scripted run
## (`persist = false`) never writes the file.

const PATH: String = "user://settings.cfg"
## Action -> [label, default physical key]. The order is the settings screen's.
const ACTIONS: Array = [
	["up", "MOVE UP", KEY_W], ["down", "MOVE DOWN", KEY_S], ["left", "MOVE LEFT", KEY_A], ["right", "MOVE RIGHT", KEY_D],
	["skill1", "SKILL 1", KEY_SPACE], ["skill2", "SKILL 2", KEY_E], ["ult", "ULTIMATE", KEY_R], ["interact", "INTERACT", KEY_F],
	["mark", "BLOOD MARK RITE", KEY_G],
	["potion1", "POTION 1", KEY_4], ["potion2", "POTION 2", KEY_5], ["potion3", "POTION 3", KEY_6],
	["pick1", "CARD 1", KEY_Z], ["pick2", "CARD 2", KEY_X], ["pick3", "CARD 3", KEY_C], ["pick4", "CARD 4", KEY_V],
	["sheet", "HERO SHEET", KEY_H], ["bag", "BAG", KEY_I]]
## The arrow keys always move as well, so a rebinding never leaves a player with no way to walk.
const ARROWS: Dictionary = {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT}
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1440, 810), Vector2i(1920, 1080)]

static var keys: Dictionary = {}
static var volume: float = 0.8
static var fullscreen: bool = false
static var window_index: int = 2
static var persist: bool = true
static var loaded: bool = false


static func _defaults() -> void:
	keys = {}
	for a in ACTIONS:
		keys[String(a[0])] = int(a[2])


static func load_file() -> void:
	_defaults()
	loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for a in ACTIONS:
		var k: String = String(a[0])
		keys[k] = int(cf.get_value("keys", k, int(a[2])))
	volume = clampf(float(cf.get_value("audio", "volume", volume)), 0.0, 1.0)
	fullscreen = bool(cf.get_value("window", "fullscreen", false))
	window_index = clampi(int(cf.get_value("window", "size", window_index)), 0, WINDOW_SIZES.size() - 1)


static func save_file() -> void:
	if not persist:
		return
	var cf := ConfigFile.new()
	for k in keys:
		cf.set_value("keys", k, keys[k])
	cf.set_value("audio", "volume", volume)
	cf.set_value("window", "fullscreen", fullscreen)
	cf.set_value("window", "size", window_index)
	cf.save(PATH)


## The physical key of an action.
static func key(action: String) -> int:
	if not loaded:
		load_file()
	return int(keys.get(action, KEY_NONE))


## Is the action held now (the action's key, or the arrow for a move)?
static func held(action: String) -> bool:
	if Input.is_physical_key_pressed(key(action) as Key):
		return true
	return ARROWS.has(action) and Input.is_physical_key_pressed(int(ARROWS[action]) as Key)


static func matches(action: String, e: InputEventKey) -> bool:
	return e.physical_keycode == key(action) or (ARROWS.has(action) and e.physical_keycode == int(ARROWS[action]))


## Gives `action` a new key; a key another action had is swapped to this one's old key, so two never share.
static func rebind(action: String, code: int) -> void:
	if not loaded:
		load_file()
	var old: int = int(keys.get(action, KEY_NONE))
	for k in keys:
		if k != action and int(keys[k]) == code:
			keys[k] = old
	keys[action] = code


static func reset_keys() -> void:
	_defaults()


static func key_label(code: int) -> String:
	return OS.get_keycode_string(code as Key).to_upper()


static func apply(window: Window) -> void:
	var db: float = linear_to_db(maxf(volume, 0.0001))
	AudioServer.set_bus_volume_db(0, db)
	AudioServer.set_bus_mute(0, volume <= 0.001)
	if window == null:
		return
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
		var sz: Vector2i = WINDOW_SIZES[clampi(window_index, 0, WINDOW_SIZES.size() - 1)]
		if window.size != sz and DisplayServer.get_name() != "headless":
			window.size = sz
