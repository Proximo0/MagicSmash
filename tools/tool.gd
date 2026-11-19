extends SceneTree
## Starts a tool script once the autoloads exist. A SceneTree script that names a game class directly is compiled
## before the autoloads are registered, so it prints "Identifier not found: Save" and "Failed to load script" on
## every start and then runs anyway: eight lines of errors that send the reader after a bug that is not there.
## Usage: godot --headless --path . -s tools/tool.gd -- <name> [args...]
## The tool is tools/<name>.gd: `extends RefCounted` with `func run(args: PackedStringArray) -> int` (the exit code).


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = "res://tools/%s.gd" % (args[0] if not args.is_empty() else "")
	if args.is_empty() or not ResourceLoader.exists(path):
		printerr("usage: godot --headless --path . -s tools/tool.gd -- <name> [args...]  (no tool at %s)" % path)
		quit(2)
		return
	var script: GDScript = load(path)
	var tool: RefCounted = script.new()
	quit(int(tool.call("run", args.slice(1))))
