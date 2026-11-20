extends Node
## The one place the game talks to Steam (GodotSteam). Without the GodotSteam extension, without an App ID, or
## in a scripted run (bots, sims, tests, captures), every call is a no-op and the game plays the same.
## The App ID lives in `config/steam.cfg` ([steam] app_id=...), written once the Steamworks app exists.

const CONFIG := "res://config/steam.cfg"

var app_id := 0
var ready_ok := false # Steam initialised and we may unlock achievements
var _steam: Object = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Flags.is_scripted_run() or not Engine.has_singleton("Steam"):
		return
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG) != OK:
		push_warning("Steam is present but %s was not found: Steam stays off." % CONFIG)
		return
	app_id = int(cfg.get_value("steam", "app_id", 0))
	if app_id <= 0:
		push_warning("Steam is present but %s has no app_id: Steam stays off." % CONFIG)
		return
	_steam = Engine.get_singleton("Steam")
	var res: Variant = _steam.call("steamInitEx", true, app_id)
	ready_ok = res is Dictionary and int((res as Dictionary).get("status", 1)) == 0
	if not ready_ok:
		push_warning("Steam did not start: %s" % str(res))


func _process(_delta: float) -> void:
	if ready_ok:
		_steam.call("run_callbacks")


## Unlocks the achievements a finished run earned (see Achievements.earned). Returns how many were sent.
func finish_run(record: Results, won: bool, seconds: float) -> int:
	if not ready_ok or record == null:
		return 0
	var names: Array = Achievements.earned(record, won, seconds)
	for n: String in names:
		_steam.call("setAchievement", n)
	if not names.is_empty():
		_steam.call("storeStats")
	return names.size()
