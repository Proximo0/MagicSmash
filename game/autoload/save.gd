extends Node
## The one place player data is read and written: the Profile (best score, crystals, meta unlocks) in
## user://profile.json. Scripted runs (bots, sims, tests, captures) never write, and play with no unlocks so
## their runs do not depend on whoever ran them. An old user://save.cfg high score is carried over once.
## The player's options (Settings) live beside it in user://settings.json; scripted runs use the defaults.

const PATH := "user://profile.json"
const OLD_PATH := "user://save.cfg"
const SETTINGS_PATH := "user://settings.json"

var profile := Profile.new()
var settings := Settings.new()


func _ready() -> void:
	profile = read_profile(PATH, OLD_PATH)
	if not Flags.is_scripted_run():
		settings = read_settings(SETTINGS_PATH)
	# G and Sfx load after Save, so apply once every autoload is ready.
	apply_settings.call_deferred()


static func read_settings(path: String) -> Settings:
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			return Settings.from_dict(parsed)
	return Settings.new()


## Saves the options. Returns false without touching the disk in a scripted run.
func write_settings() -> bool:
	if Flags.is_scripted_run():
		return false
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(settings.to_dict(), "\t"))
	return true


## Puts the options into effect: volumes always, the window only in a real windowed run.
func apply_settings() -> void:
	Sfx.set_volumes(settings.music_linear(), settings.sound_linear())
	if Flags.is_scripted_run() or DisplayServer.get_name() == "headless" or G.is_mobile or OS.has_feature("web"):
		return
	if settings.is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var size := Vector2i(480, 270) * settings.window_scale()
	var screen := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


## The profile stored at `path`, or a fresh one (with the old save's high score) when there is none.
static func read_profile(path: String, old_path: String) -> Profile:
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			return Profile.from_dict(parsed)
	var p := Profile.new()
	if FileAccess.file_exists(old_path):
		var f := FileAccess.open(old_path, FileAccess.READ)
		if f:
			p.high_score = maxi(0, int(f.get_line()))
	return p


## Writes the profile. Returns false without touching the disk in a scripted run.
func write() -> bool:
	if Flags.is_scripted_run():
		return false
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(profile.to_dict(), "\t"))
	return true


## The unlock bonuses a new run starts with; none in scripted runs.
func run_bonuses() -> Dictionary:
	return {} if Flags.is_scripted_run() else profile.bonuses()


## Books a finished run and saves. Returns the crystals earned (shown on the game over screen).
func finish_run(score: int, seconds: float, kills: int, liches: int, won: bool = false) -> int:
	var earned := profile.finish_run(score, seconds, kills, liches, won)
	write()
	return earned
