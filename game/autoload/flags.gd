extends Node
## Run-wide flags and the state hash.
## User args come after "--" on the command line: godot --path . -- --scripted --dev --seed=7

var args: Dictionary = {}
var frame: int = 0
var commands: int = 0  ## player commands issued; compare state hashes only on frames where this is 0
var _hash_providers: Array[Callable] = []


## Flags only the editor, a debug build or a `playtest` export honours. `--smoke` is not one: it works everywhere.
## `hero` is the developer flag that seats a hero nobody built (Arena._ready).
const DEBUG_ARGS: PackedStringArray = ["autotest", "capture", "scripted", "dev", "hero"]
## Flags that make a run scripted: nothing is saved, no crash reports.
const SCRIPTED_ARGS: PackedStringArray = ["scripted", "capture", "autotest", "smoke"]


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	args = without_debug_args(args, debug_args_allowed(OS.has_feature("editor"), OS.is_debug_build(), OS.has_feature("playtest")))


## The debug flags count in the editor build, a debug build, or an export carrying the custom feature tag `playtest`.
static func debug_args_allowed(is_editor: bool, is_debug_build: bool, has_playtest_tag: bool) -> bool:
	return is_editor or is_debug_build or has_playtest_tag


## `parsed` without the debug flags unless `allowed`.
static func without_debug_args(parsed: Dictionary, allowed: bool) -> Dictionary:
	if allowed:
		return parsed
	var kept: Dictionary = parsed.duplicate()
	for k: String in DEBUG_ARGS:
		kept.erase(k)
	return kept


func _physics_process(_delta: float) -> void:
	frame += 1


## Captures, tests and gates: no saves, no writes to player data.
func is_scripted_run() -> bool:
	return has_scripted_arg(args) or DisplayServer.get_name() == "headless"


## True when `parsed` holds a flag that makes the run scripted (the headless half of the rule is the caller's).
static func has_scripted_arg(parsed: Dictionary) -> bool:
	for k: String in SCRIPTED_ARGS:
		if parsed.has(k):
			return true
	return false


## Dev menu entries and cheats only with --dev.
func dev_menu() -> bool:
	return args.has("dev")


func get_arg(key: String, default: String = "") -> String:
	return args.get(key, default)


func seed_value() -> int:
	return int(get_arg("seed", "1"))


## Systems register a Callable returning an int that summarises their state.
func register_hash(provider: Callable) -> void:
	_hash_providers.append(provider)


func state_hash() -> int:
	var h: int = 1469598103934665603
	for p: Callable in _hash_providers:
		if p.is_valid():
			h = hash([h, p.call()])
	return h
