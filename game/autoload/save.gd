extends Node
## The one place player data is read and written: the Profile (best score, crystals, meta unlocks) in
## user://profile.json. Scripted runs (bots, sims, tests, captures) never write, and play with no unlocks so
## their runs do not depend on whoever ran them. An old user://save.cfg high score is carried over once.
## The player's options (Settings) live beside it in user://settings.json; scripted runs use the defaults.
## Files are written safely: to a .tmp file, the last good one kept as .bak, then renamed into place. A file that
## cannot be read is kept aside as .bad (never overwriting an earlier one) and the .bak is loaded, so a bad save never wipes the player's data.
## A file that parses but holds a wrong type (from_dict returns null) is damaged the same way. A profile a newer build
## wrote (Profile.newer) is loaded but never written back, so its newer data is not lost (newer_save()).

const PATH := "user://profile.json"
const OLD_PATH := "user://save.cfg"
const SETTINGS_PATH := "user://settings.json"

var profile := Profile.new()
var settings := Settings.new()
var _first_run := false # no settings file yet: the window picks the largest scale that fits
var _applied_display := -1 # the DISPLAY value the window was last put into


func _ready() -> void:
	profile = read_profile(PATH, OLD_PATH, not Flags.is_scripted_run())
	if not Flags.is_scripted_run():
		_first_run = not FileAccess.file_exists(SETTINGS_PATH) and not FileAccess.file_exists(SETTINGS_PATH + ".bak")
		settings = read_settings(SETTINGS_PATH, true)
	# G and Sfx load after Save, so apply once every autoload is ready.
	apply_settings.call_deferred()


## The parsed text, or null when it is not valid JSON (quietly, unlike JSON.parse_string).
static func _parse(text: String) -> Variant:
	var j := JSON.new()
	return j.data if j.parse(text) == OK else null


## The dictionary stored in the file at `path`, or null. An empty read of a file that has bytes may be a passing
## failure, not damage, so it is read once more before it counts as unreadable.
static func _read(path: String) -> Variant:
	var parsed: Variant = _parse(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	var f := FileAccess.open(path, FileAccess.READ)
	var size := f.get_length() if f else 0
	if f:
		f.close()
	if size > 0:
		parsed = _parse(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else null


## Renames a damaged file to `path + suffix`, or to `path + suffix + "." + unix time` when that name is taken, so
## every damaged copy is kept.
static func _keep_aside(path: String, suffix: String) -> void:
	var to := path + suffix
	if FileAccess.file_exists(to):
		to = "%s%s.%d" % [path, suffix, int(Time.get_unix_time_from_system())]
		var n := 1
		while FileAccess.file_exists(to):
			to = "%s%s.%d_%d" % [path, suffix, int(Time.get_unix_time_from_system()), n]
			n += 1
	DirAccess.rename_absolute(path, to)
	push_warning("%s could not be read; kept as %s" % [path, to])


## The dictionary stored at `path`, else a complete .tmp left by a save whose rename failed (when the file is
## missing), else the one in its .bak, else null. With `aside`, a file or .bak that exists but does not parse is
## renamed to .bad (or .bak.bad; a name already taken gets the unix time added) so nothing can write over it;
## scripted runs leave files alone.
static func read_json(path: String, aside: bool = false) -> Variant:
	return read_converted(path, aside, Callable())


## read_json, but each dictionary found passes through `convert` (dictionary -> object, or null when it is damaged,
## e.g. Profile.from_dict on a wrong type) and the first non-null result is returned. A null result counts as damage
## exactly like text that does not parse: that file is kept aside and the next one is tried. An empty `convert`
## returns the dictionary itself.
static func read_converted(path: String, aside: bool, convert: Callable) -> Variant:
	if FileAccess.file_exists(path):
		var got: Variant = _convert_read(_read(path), convert)
		if got != null:
			return got
		if aside:
			_keep_aside(path, ".bad")
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".tmp"):
		var newest: Variant = _convert_read(_read(path + ".tmp"), convert)
		if newest != null:
			return newest
	if FileAccess.file_exists(path + ".bak"):
		var old: Variant = _convert_read(_read(path + ".bak"), convert)
		if old != null:
			return old
		if aside:
			_keep_aside(path + ".bak", ".bad")
	return null


static func _convert_read(parsed: Variant, convert: Callable) -> Variant:
	if not parsed is Dictionary:
		return null
	return convert.call(parsed) if convert.is_valid() else parsed


## Test seam: when set, the text bound for the .tmp file passes through it (to inject a bad write).
static var tmp_filter := Callable()


## Writes `data` to `path` safely (see the top). Returns false, leaving `path` as it was, on any failure.
static func write_json(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	var text := JSON.stringify(data, "\t")
	if tmp_filter.is_valid():
		text = tmp_filter.call(text)
	f.store_string(text)
	var ok := f.get_error() == OK
	f.close()
	if not ok or not (_parse(FileAccess.get_file_as_string(tmp)) is Dictionary):
		DirAccess.remove_absolute(tmp)
		return false
	# Keep the last good file as .bak (never a damaged one over a good .bak).
	if FileAccess.file_exists(path) and _read(path) is Dictionary:
		DirAccess.copy_absolute(path, path + ".bak")
	# A failed rename leaves the .tmp: it is then the only copy of the newest data (read_json can use it).
	return DirAccess.rename_absolute(tmp, path) == OK


## The options stored at `path` (or its backup; a damaged or wrong-typed file is kept aside), else the defaults.
static func read_settings(path: String, aside: bool = false) -> Settings:
	var s: Variant = read_converted(path, aside, Settings.from_dict)
	return s if s is Settings else Settings.new()


## Saves the options. Returns false without touching the disk in a scripted run.
func write_settings() -> bool:
	if Flags.is_scripted_run():
		return false
	return write_json(SETTINGS_PATH, settings.to_dict())


## Puts the options into effect: the volumes always, the window only when the DISPLAY choice changed (so an
## option like the music volume does not move the window back), and only in a real windowed run.
func apply_settings() -> void:
	Sfx.set_volumes(settings.music_linear(), settings.sound_linear())
	Crash.set_enabled(settings.crash_reports)
	if Flags.is_scripted_run() or DisplayServer.get_name() == "headless" or OS.has_feature("mobile") or OS.has_feature("web"):
		return
	if _first_run:
		_first_run = false
		settings.display = Settings.best_display(DisplayServer.screen_get_usable_rect().size)
	if settings.display == _applied_display:
		return
	_applied_display = settings.display
	if settings.is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var screen := DisplayServer.screen_get_usable_rect()
	var size := Vector2i(480, 270) * settings.fit_scale(screen.size)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


## The profile stored at `path` (or its backup; a damaged or wrong-typed file is kept aside), or a fresh one (with
## the old save's high score) when there is none.
static func read_profile(path: String, old_path: String, aside: bool = false) -> Profile:
	var got: Variant = read_converted(path, aside, Profile.from_dict)
	if got is Profile:
		return got
	var p := Profile.new()
	if FileAccess.file_exists(old_path):
		var f := FileAccess.open(old_path, FileAccess.READ)
		if f:
			p.high_score = maxi(0, int(f.get_line()))
	return p


## Writes the profile. Returns false without touching the disk in a scripted run or when the profile came from a
## newer build (newer_save()). Every profile write (finish_run, add_card, the menus) goes through here.
func write() -> bool:
	if Flags.is_scripted_run():
		return false
	return write_profile(PATH, profile)


## Writes `prof` to `path` safely, unless it came from a newer build (Profile.newer): then false, the disk untouched.
static func write_profile(path: String, prof: Profile) -> bool:
	if prof.newer:
		return false
	return write_json(path, prof.to_dict())


## True when the profile was written by a newer build: it plays, but nothing is saved (the title says so).
func newer_save() -> bool:
	return profile.newer


## The unlock bonuses a new run starts with; none in scripted runs, except one that seats saved heroes on purpose
## (Net.force_heroes: the bots' hero shard and --autotest --seat-heroes).
func run_bonuses() -> Dictionary:
	return {} if Flags.is_scripted_run() and not Net.force_heroes else profile.bonuses()


## Books a finished run and saves. Returns the crystals earned (shown on the game over screen).
func finish_run(run: Dictionary) -> int:
	var earned := profile.finish_run(run)
	write()
	return earned


## Books a monster card found in play and saves. Returns true if it is the first of its kind. Scripted runs
## never write, so a card a bot finds is not kept.
func add_card(idx: int) -> bool:
	if Flags.is_scripted_run():
		return false
	var first := profile.add_card(idx)
	write()
	return first
