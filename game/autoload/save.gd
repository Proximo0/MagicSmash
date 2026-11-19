extends Node
## The one place player data is read and written: the Profile (best score, crystals, meta unlocks) in
## user://profile.json. Scripted runs (bots, sims, tests, captures) never write, and play with no unlocks so
## their runs do not depend on whoever ran them. An old user://save.cfg high score is carried over once.

const PATH := "user://profile.json"
const OLD_PATH := "user://save.cfg"

var profile := Profile.new()


func _ready() -> void:
	profile = read_profile(PATH, OLD_PATH)


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
